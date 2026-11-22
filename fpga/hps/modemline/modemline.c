/**
 * @file modemline.c  baresip audio source + player on the FPGA modem's phone line (see rtl/line_ddr.sv, hps/linering.py)
 *
 * One pump thread owns the DDR sample rings (mapped through /dev/mem, or the file in $MODEMLINE_FILE for tests):
 *   modem -> line: the modem's DAC samples (codec rate, which changes during a call) are resampled to 8 kHz for the SIP audio source,
 *                  and run through a DTMF detector and level meter (events to the line controller);
 *   line -> modem: the 8 kHz audio the SIP player delivers is resampled to the codec rate into the RX ring, kept at about 40 ms in the
 *                  ring; the resampler step is trimmed so the free-running modem clock and the RTP clock do not slip;
 *                  with no call the controller can have a dial tone / ringback tone generated instead.
 * Control: datagrams to /tmp/modemline.cmd ("ring 1", "connected 1", "tone dial|ringback|none", "status");
 * events as datagrams to /tmp/modemline.ev ("digit 5", "tx 1", "tx 0", "status ...").
 *
 * baresip config:  audio_source modemline,line   audio_player modemline,line   audio_codecs pcmu,pcma   ptime 20
 */
#define _GNU_SOURCE
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>

#include <re_atomic.h>
#include <re.h>
#include <rem.h>
#include <baresip.h>

#define PHYS_BASE   0x3A000000UL
#define MAP_BYTES   0x12000
#define W_TXCNT     1
#define W_RXTAKEN   2
#define W_STATUS    3
#define W_CTRL      8
#define W_TX        0x400
#define W_RX        0x1400
#define RING_SAMPLES 16384
#define DSP_HZ      40320000.0
#define CMD_PATH    "/tmp/modemline.cmd"
#define EV_PATH     "/tmp/modemline.ev"
#define Q8_CAP      16000          /* 2 s at 8 kHz */
#define RS_HALF     12             /* resampler: 24 taps */

/* ---------------- DDR window */
static volatile uint32_t *dm;      /* 32-bit view, little endian, word w = dm[2*w] (low), dm[2*w+1] (high) */
static volatile int16_t  *txr, *rxr;

static inline uint32_t rd_lo(int w) { return dm[2 * w]; }
static inline void     wr_lo(int w, uint32_t v) { dm[2 * w] = v; }
static inline void     wr_hi(int w, uint32_t v) { dm[2 * w + 1] = v; }

/* ---------------- fractional resampler: windowed sinc, input position in input samples */
struct rs {
	float  *buf;
	size_t  cap, n;       /* stored input samples */
	double  pos;          /* next output position, index into buf (fractional) */
};

static int rs_init(struct rs *r)
{
	r->cap = 8192;
	r->buf = calloc(r->cap, sizeof *r->buf);
	r->n = 0;
	r->pos = RS_HALF;
	return r->buf ? 0 : ENOMEM;
}

static void rs_reset(struct rs *r) { r->n = 0; r->pos = RS_HALF; }

static void rs_push(struct rs *r, const float *x, size_t n)
{
	if (r->n + n > r->cap) {              /* overrun of the intermediate buffer: drop the oldest */
		size_t drop = r->n + n - r->cap;
		if (drop > r->n) drop = r->n;
		memmove(r->buf, r->buf + drop, (r->n - drop) * sizeof *r->buf);
		r->n -= drop;
		r->pos -= (double)drop;
		if (r->pos < RS_HALF) r->pos = RS_HALF;
		if (n > r->cap) { x += n - r->cap; n = r->cap; }
	}
	memcpy(r->buf + r->n, x, n * sizeof *x);
	r->n += n;
}

/* one output sample if enough input is there; step = input samples per output sample */
static int rs_pull(struct rs *r, double step, float *out)
{
	long   ip = (long)floor(r->pos);
	double fr = r->pos - (double)ip;
	if ((size_t)(ip + RS_HALF + 1) >= r->n)
		return 0;
	double fc = step > 1.0 ? 1.0 / step : 1.0;
	double acc = 0.0;
	for (int k = -RS_HALF + 1; k <= RS_HALF; k++) {
		double t = (double)k - fr;
		double a = fc * t * M_PI;
		double s = fabs(a) < 1e-9 ? 1.0 : sin(a) / a;
		double w = 0.5 + 0.5 * cos(M_PI * t / (double)RS_HALF);
		acc += (double)r->buf[ip + k] * fc * s * w;
	}
	*out = (float)acc;
	r->pos += step;
	long drop = (long)floor(r->pos) - RS_HALF - 1;
	if (drop > 512) {
		memmove(r->buf, r->buf + drop, (r->n - (size_t)drop) * sizeof *r->buf);
		r->n -= (size_t)drop;
		r->pos -= (double)drop;
	}
	return 1;
}

/* ---------------- 8 kHz queues between the pump and the baresip threads */
struct q8 {
	int16_t buf[Q8_CAP];
	size_t  head, n;
};
static mtx_t qmtx;
static struct q8 q_tx8, q_rx8;

static void q_clear(struct q8 *q) { q->head = q->n = 0; }
static size_t q_put(struct q8 *q, const int16_t *x, size_t n)
{
	size_t room = Q8_CAP - q->n, i;
	if (n > room) { /* drop the oldest */ size_t d = n - room; q->head = (q->head + d) % Q8_CAP; q->n -= d; }
	for (i = 0; i < n; i++) q->buf[(q->head + q->n + i) % Q8_CAP] = x[i];
	q->n += n;
	return n;
}
static size_t q_get(struct q8 *q, int16_t *x, size_t n)
{
	size_t m = n < q->n ? n : q->n, i;
	for (i = 0; i < m; i++) x[i] = q->buf[(q->head + i) % Q8_CAP];
	q->head = (q->head + m) % Q8_CAP; q->n -= m;
	return m;
}

/* ---------------- state */
static RE_ATOMIC bool run;
static thrd_t pump_thr;
static RE_ATOMIC int src_active, play_active;
static RE_ATOMIC int cmd_ring, cmd_conn, cmd_tone;    /* tone: 0 none, 1 dial, 2 ringback */
static int cmd_fd = -1, ev_fd = -1;

static void event(const char *fmt, ...)
{
	char b[160];
	va_list ap;
	struct sockaddr_un a = { .sun_family = AF_UNIX };
	if (ev_fd < 0) return;
	va_start(ap, fmt); vsnprintf(b, sizeof b, fmt, ap); va_end(ap);
	strncpy(a.sun_path, EV_PATH, sizeof a.sun_path - 1);
	sendto(ev_fd, b, strlen(b), MSG_DONTWAIT, (struct sockaddr *)&a, sizeof a);
}

/* ---------------- DTMF + level on the modem's output */
static const double LOWF[4] = { 697, 770, 852, 941 }, HIGHF[4] = { 1209, 1336, 1477, 1633 };
static const char DIG[4][4] = { {'1','2','3','A'}, {'4','5','6','B'}, {'7','8','9','C'}, {'*','0','#','D'} };

static double goertzel(const float *x, size_t n, double f, double fs)
{
	double c = 2.0 * cos(2.0 * M_PI * f / fs), s1 = 0, s2 = 0;
	for (size_t i = 0; i < n; i++) { double s0 = x[i] + c * s1 - s2; s2 = s1; s1 = s0; }
	return s1 * s1 + s2 * s2 - c * s1 * s2;
}

static char dtmf_block(const float *x, size_t n, double fs)
{
	double tot = 1.0, lo[4], hi[4];
	for (size_t i = 0; i < n; i++) tot += (double)x[i] * x[i];
	int il = 0, ih = 0;
	for (int i = 0; i < 4; i++) { lo[i] = goertzel(x, n, LOWF[i], fs); hi[i] = goertzel(x, n, HIGHF[i], fs); if (lo[i] > lo[il]) il = i; if (hi[i] > hi[ih]) ih = i; }
	double l2 = 0, h2 = 0;
	for (int i = 0; i < 4; i++) { if (i != il && lo[i] > l2) l2 = lo[i]; if (i != ih && hi[i] > h2) h2 = hi[i]; }
	if (lo[il] < 0.08 * tot * (double)n || hi[ih] < 0.08 * tot * (double)n) return 0;
	if (l2 * 8.0 > lo[il] || h2 * 8.0 > hi[ih]) return 0;
	return DIG[il][ih];
}

/* ---------------- tone generator for the idle line */
struct tone { double t; };
static float tone_next(int kind, struct tone *g, double fs)
{
	double v = 0;
	if (kind == 1) v = (sin(2 * M_PI * 350 * g->t) + sin(2 * M_PI * 440 * g->t)) * 0.5;
	else if (kind == 2) v = fmod(g->t, 6.0) < 2.0 ? (sin(2 * M_PI * 440 * g->t) + sin(2 * M_PI * 480 * g->t)) * 0.5 : 0;
	g->t += 1.0 / fs;
	if (g->t > 600.0) g->t -= 600.0;
	return (float)(v * 3000.0);
}

/* ---------------- the pump */
static int pump(void *arg)
{
	(void)arg;
	struct rs rs_tx, rs_rx;
	uint32_t tx_last = rd_lo(W_TXCNT);
	uint32_t rx_count = rd_lo(W_CTRL), flags_cur = 0xFFFFFFFF;   /* the control word keeps the count across restarts of either side: continue from it */
	struct tone tg = { 0 };
	float blk[4096];
	size_t blk_n = 0;
	char last_dig = 0, cand = 0; int cand_n = 0, nodig_n = 0;
	int tx_on = 0, quiet_blocks = 0, loud_blocks = 0;
	double fs_prev = 0, servo = 1.0;
	const char *g = getenv("MODEMLINE_RXGAIN");               /* receive gain for tests (default 1.0) */
	double rx_gain = g ? atof(g) : 1.0;
	if (rx_gain <= 0 || rx_gain > 16) rx_gain = 1.0;
	uint64_t t_status = tmr_jiffies();
	int was_call = 0;

	rs_init(&rs_tx); rs_init(&rs_rx);
	while (re_atomic_rlx(&run)) {
		sys_msleep(4);

		/* control socket */
		for (;;) {
			char b[96];
			ssize_t n = recv(cmd_fd, b, sizeof b - 1, MSG_DONTWAIT);
			if (n <= 0) break;
			b[n] = 0;
			int v;
			if (sscanf(b, "ring %d", &v) == 1) re_atomic_rlx_set(&cmd_ring, v);
			else if (sscanf(b, "connected %d", &v) == 1) re_atomic_rlx_set(&cmd_conn, v);
			else if (!strncmp(b, "tone dial", 9)) re_atomic_rlx_set(&cmd_tone, 1);
			else if (!strncmp(b, "tone ringback", 13)) re_atomic_rlx_set(&cmd_tone, 2);
			else if (!strncmp(b, "tone none", 9)) re_atomic_rlx_set(&cmd_tone, 0);
			else if (!strncmp(b, "status", 6)) {
				uint32_t s = rd_lo(W_STATUS), s2 = dm[2 * W_STATUS + 1];
				event("status cps=%u under=%u lost=%u q_tx=%zu q_rx=%zu servo=%.6f", s & 0xFFFF, s >> 16, s2 & 0xFFFF, q_tx8.n, q_rx8.n, servo);
			}
		}
		uint32_t flags = (re_atomic_rlx(&cmd_ring) ? 1u : 0u) | (re_atomic_rlx(&cmd_conn) ? 2u : 0u);
		if (flags != flags_cur) { flags_cur = flags; wr_hi(W_CTRL, flags); }

		uint32_t stl = rd_lo(W_STATUS);
		double cps = (double)(stl & 0xFFFF);
		double fs = cps > 0 ? DSP_HZ / cps : 7200.0;
		if (fs < 4000 || fs > 20000) fs = 7200.0;
		int rate_changed = (fs_prev != 0) && (fabs(fs - fs_prev) > 50.0);
		fs_prev = fs;

		int call = re_atomic_rlx(&src_active) || re_atomic_rlx(&play_active);
		if (call != was_call) { rs_reset(&rs_tx); rs_reset(&rs_rx); mtx_lock(&qmtx); q_clear(&q_tx8); q_clear(&q_rx8); mtx_unlock(&qmtx); was_call = call; servo = 1.0; }

		/* ---- modem -> line */
		uint32_t cnt = rd_lo(W_TXCNT);
		uint32_t n = cnt - tx_last;
		if (n > RING_SAMPLES - 64) { tx_last = cnt - RING_SAMPLES / 2; n = RING_SAMPLES / 2; }
		if (n) {
			float x[RING_SAMPLES / 2 + 8];
			if (n > RING_SAMPLES / 2) n = RING_SAMPLES / 2;
			for (uint32_t i = 0; i < n; i++) x[i] = (float)txr[(tx_last + i) % RING_SAMPLES];
			tx_last += n;
			for (uint32_t i = 0; i < n; i++) {           /* blocks of 20 ms for DTMF and level */
				blk[blk_n++] = x[i];
				if (blk_n >= (size_t)(fs * 0.02) && blk_n <= sizeof blk / sizeof *blk) {
					double e = 0; for (size_t k = 0; k < blk_n; k++) e += (double)blk[k] * blk[k];
					double rms = sqrt(e / (double)blk_n);
					if (rms > 150) { loud_blocks++; quiet_blocks = 0; } else { quiet_blocks++; loud_blocks = 0; }
					if (!tx_on && loud_blocks >= 15) { tx_on = 1; event("tx 1"); }
					if (tx_on && quiet_blocks >= 75) { tx_on = 0; event("tx 0"); }
					char d = dtmf_block(blk, blk_n, fs);
					if (d) { nodig_n = 0; if (d == cand) cand_n++; else { cand = d; cand_n = 1; } if (cand_n >= 2 && cand != last_dig) { last_dig = cand; event("digit %c", cand); } }
					else { cand = 0; cand_n = 0; if (++nodig_n >= 2) last_dig = 0; }   /* the modem leaves 60 ms between digits: two silent 20 ms blocks end a digit */
					blk_n = 0;
				}
			}
			if (call) {
				rs_push(&rs_tx, x, n);
				float o; int16_t s8[256]; size_t m = 0;
				double step = fs / 8000.0;
				while (rs_pull(&rs_tx, step, &o)) {
					s8[m++] = (int16_t)fmaxf(-32768.f, fminf(32767.f, o));
					if (m == 256) { mtx_lock(&qmtx); q_put(&q_tx8, s8, m); mtx_unlock(&qmtx); m = 0; }
				}
				if (m) { mtx_lock(&qmtx); q_put(&q_tx8, s8, m); mtx_unlock(&qmtx); }
			}
		}

		/* ---- line -> modem: keep the RX ring at about 40 ms */
		uint32_t taken = rd_lo(W_RXTAKEN);
		if (rate_changed) {
			/* the codec rate changed: what is still queued in the RX ring (about 40 ms) was resampled for the old rate, and the modem would play it at the new one. Drop it and refill at the new rate. */
			rx_count = taken; wr_lo(W_CTRL, rx_count); rs_reset(&rs_rx);
			event("rate %.0f Hz", fs);
		}
		int32_t fill = (int32_t)(rx_count - taken);
		int32_t target = (int32_t)(fs * 0.04);
		if (fill < 0) fill = 0;
		int want = target - fill;
		if (want > 0) {
			float o; size_t put = 0;
			if (call && re_atomic_rlx(&play_active)) {
				int16_t in[320];
				mtx_lock(&qmtx);
				size_t qn = q_rx8.n;
				size_t take = qn > 320 ? 320 : qn;
				q_get(&q_rx8, in, take);
				mtx_unlock(&qmtx);
				float f[320]; for (size_t i = 0; i < take; i++) f[i] = in[i];
				rs_push(&rs_rx, f, take);
				/* servo on the 8 kHz queue level: aim for 60 ms (480 samples) */
				double lvl = (double)(qn - take) + (double)(rs_rx.n);
				servo = 1.0 + 0.0002 * ((lvl - 480.0) / 480.0);
				if (servo > 1.0003) servo = 1.0003; else if (servo < 0.9997) servo = 0.9997;
				double step = (8000.0 / fs) * servo;
				while (want > 0 && put < 2048) {
					if (!rs_pull(&rs_rx, step, &o)) o = 0;           /* RTP underrun: silence */
					o *= (float)rx_gain;
					rxr[(rx_count + put) % RING_SAMPLES] = (int16_t)fmaxf(-32768.f, fminf(32767.f, o));
					put++; want--;
				}
			} else if (re_atomic_rlx(&cmd_tone)) {
				int kind = re_atomic_rlx(&cmd_tone);
				while (want > 0 && put < 2048) { rxr[(rx_count + put) % RING_SAMPLES] = (int16_t)tone_next(kind, &tg, fs); put++; want--; }
			}
			if (put) { rx_count += (uint32_t)put; wr_lo(W_CTRL, rx_count); }
		}

		if (tmr_jiffies() - t_status > 5000) t_status = tmr_jiffies();
	}
	free(rs_tx.buf); free(rs_rx.buf);
	return 0;
}

/* ---------------- baresip source / player */
struct ausrc_st {
	ausrc_read_h *rh; void *arg; struct ausrc_prm prm;
	RE_ATOMIC bool run; thrd_t th; size_t sampc;
};
struct auplay_st {
	auplay_write_h *wh; void *arg; struct auplay_prm prm;
	RE_ATOMIC bool run; thrd_t th; size_t sampc;
};
static struct ausrc *ausrc;
static struct auplay *auplay;

static void src_destructor(void *a)
{
	struct ausrc_st *st = a;
	if (re_atomic_rlx(&st->run)) { re_atomic_rlx_set(&st->run, false); thrd_join(st->th, NULL); }
	re_atomic_rlx_set(&src_active, 0);
}

static int src_thread(void *a)
{
	struct ausrc_st *st = a;
	uint64_t ts = tmr_jiffies();
	int16_t *buf = mem_alloc(st->sampc * 2, NULL);
	if (!buf) return ENOMEM;
	while (re_atomic_rlx(&st->run)) {
		sys_msleep(4);
		if (ts > tmr_jiffies()) continue;
		struct auframe af;
		mtx_lock(&qmtx);
		size_t got = q_get(&q_tx8, buf, st->sampc);
		mtx_unlock(&qmtx);
		if (got < st->sampc) memset(buf + got, 0, (st->sampc - got) * 2);
		auframe_init(&af, AUFMT_S16LE, buf, st->sampc, st->prm.srate, st->prm.ch);
		af.timestamp = ts * 1000;
		st->rh(&af, st->arg);
		ts += st->prm.ptime;
	}
	mem_deref(buf);
	return 0;
}

static int src_alloc(struct ausrc_st **stp, const struct ausrc *as, struct ausrc_prm *prm, const char *dev,
		     ausrc_read_h *rh, ausrc_error_h *errh, void *arg)
{
	(void)as; (void)dev; (void)errh;
	struct ausrc_st *st;
	int err;
	if (!stp || !prm || !rh) return EINVAL;
	if (prm->fmt != AUFMT_S16LE || prm->srate != 8000 || prm->ch != 1) { warning("modemline: need 8000 Hz mono S16LE\n"); return ENOTSUP; }
	st = mem_zalloc(sizeof *st, src_destructor);
	if (!st) return ENOMEM;
	st->rh = rh; st->arg = arg; st->prm = *prm; st->sampc = prm->srate * prm->ptime / 1000;
	re_atomic_rlx_set(&src_active, 1);
	re_atomic_rlx_set(&st->run, true);
	err = thread_create_name(&st->th, "modemline_src", src_thread, st);
	if (err) { re_atomic_rlx_set(&st->run, false); mem_deref(st); return err; }
	*stp = st;
	return 0;
}

static void play_destructor(void *a)
{
	struct auplay_st *st = a;
	if (re_atomic_rlx(&st->run)) { re_atomic_rlx_set(&st->run, false); thrd_join(st->th, NULL); }
	re_atomic_rlx_set(&play_active, 0);
}

static int play_thread(void *a)
{
	struct auplay_st *st = a;
	uint64_t ts = tmr_jiffies();
	int16_t *buf = mem_alloc(st->sampc * 2, NULL);
	if (!buf) return ENOMEM;
	while (re_atomic_rlx(&st->run)) {
		sys_msleep(4);
		if (ts > tmr_jiffies()) continue;
		struct auframe af;
		auframe_init(&af, AUFMT_S16LE, buf, st->sampc, st->prm.srate, st->prm.ch);
		st->wh(&af, st->arg);
		mtx_lock(&qmtx);
		q_put(&q_rx8, buf, st->sampc);
		mtx_unlock(&qmtx);
		ts += st->prm.ptime;
	}
	mem_deref(buf);
	return 0;
}

static int play_alloc(struct auplay_st **stp, const struct auplay *ap, struct auplay_prm *prm, const char *dev,
		      auplay_write_h *wh, void *arg)
{
	(void)ap; (void)dev;
	struct auplay_st *st;
	int err;
	if (!stp || !prm || !wh) return EINVAL;
	if (prm->fmt != AUFMT_S16LE || prm->srate != 8000 || prm->ch != 1) { warning("modemline: need 8000 Hz mono S16LE\n"); return ENOTSUP; }
	st = mem_zalloc(sizeof *st, play_destructor);
	if (!st) return ENOMEM;
	st->wh = wh; st->arg = arg; st->prm = *prm; st->sampc = prm->srate * prm->ptime / 1000;
	re_atomic_rlx_set(&play_active, 1);
	re_atomic_rlx_set(&st->run, true);
	err = thread_create_name(&st->th, "modemline_play", play_thread, st);
	if (err) { re_atomic_rlx_set(&st->run, false); mem_deref(st); return err; }
	*stp = st;
	return 0;
}

/* ---------------- module */
static int module_init(void)
{
	const char *file = getenv("MODEMLINE_FILE");
	int fd, err;
	struct sockaddr_un a = { .sun_family = AF_UNIX };
	void *m;

	if (file) fd = open(file, O_RDWR | O_CREAT, 0666);
	else      fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { warning("modemline: cannot open %s: %m\n", file ? file : "/dev/mem", errno); return errno; }
	if (file && ftruncate(fd, MAP_BYTES)) { close(fd); return errno; }
	m = mmap(NULL, MAP_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED, fd, file ? 0 : (off_t)PHYS_BASE);
	if (m == MAP_FAILED) { warning("modemline: mmap failed: %m\n", errno); close(fd); return errno; }
	dm  = m;
	txr = (volatile int16_t *)((volatile uint8_t *)m + W_TX * 8);
	rxr = (volatile int16_t *)((volatile uint8_t *)m + W_RX * 8);
	if (memcmp((const void *)m, "MDMLINE1", 8) && memcmp((const void *)m, "1ENILMDM", 8) && !file) warning("modemline: no line signature in the DDR window (is the core loaded?)\n");

	cmd_fd = socket(AF_UNIX, SOCK_DGRAM, 0);
	strncpy(a.sun_path, CMD_PATH, sizeof a.sun_path - 1);
	unlink(CMD_PATH);
	if (bind(cmd_fd, (struct sockaddr *)&a, sizeof a)) { warning("modemline: cannot bind %s\n", CMD_PATH); return errno; }
	ev_fd = socket(AF_UNIX, SOCK_DGRAM, 0);

	mtx_init(&qmtx, mtx_plain);
	err = ausrc_register(&ausrc, baresip_ausrcl(), "modemline", src_alloc);
	if (err) return err;
	err = auplay_register(&auplay, baresip_auplayl(), "modemline", play_alloc);
	if (err) return err;
	re_atomic_rlx_set(&run, true);
	err = thread_create_name(&pump_thr, "modemline_pump", pump, NULL);
	if (err) return err;
	info("modemline: line rings mapped, %s\n", file ? file : "DDR 0x3A000000");
	return 0;
}

static int module_close(void)
{
	if (re_atomic_rlx(&run)) { re_atomic_rlx_set(&run, false); thrd_join(pump_thr, NULL); }
	ausrc = mem_deref(ausrc);
	auplay = mem_deref(auplay);
	if (cmd_fd >= 0) { close(cmd_fd); unlink(CMD_PATH); }
	if (ev_fd >= 0) close(ev_fd);
	return 0;
}

EXPORT_SYM const struct mod_export DECL_EXPORTS(modemline) = { "modemline", "audio", module_init, module_close };
