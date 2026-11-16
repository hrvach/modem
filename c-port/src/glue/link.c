/* Two emulated modems on one simulated phone line.
 * Port of modem/sys/link.py. See link.h for the time policy.
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "link.h"
#include "wav.h"

#define ACC_WINDOW 100000 /* co_step sees 100k-cycle windows */

static void append_i32(int32_t **arr, size_t *n, size_t *cap,
                       const int32_t *xs, size_t xn)
{
    if (*n + xn > *cap) {
        size_t nc = *cap ? *cap : 1024;
        while (nc < *n + xn) nc *= 2;
        int32_t *na = realloc(*arr, nc * sizeof *na);
        if (!na) abort();
        *arr = na; *cap = nc;
    }
    memcpy(*arr + *n, xs, xn * sizeof *xs);
    *n += xn;
}

static void append_u8(uint8_t **arr, size_t *n, size_t *cap,
                      const uint8_t *xs, size_t xn)
{
    if (*n + xn > *cap) {
        size_t nc = *cap ? *cap : 256;
        while (nc < *n + xn) nc *= 2;
        uint8_t *na = realloc(*arr, nc * sizeof *na);
        if (!na) abort();
        *arr = na; *cap = nc;
    }
    memcpy(*arr + *n, xs, xn);
    *n += xn;
}

Link *link_new(const Config *cfg)
{
    Link *l = calloc(1, sizeof *l);
    if (!l)
        return NULL;
    /* Link machines use nvram_mode=None (machine.py Link.__init__),
     * regardless of the direct-Machine default. Config carries -1. */
    l->a = machine_new(cfg);
    l->b = machine_new(cfg);
    if (!l->a || !l->b) {
        link_free(l);
        return NULL;
    }
    l->a->logging = 0;
    l->b->logging = 0;
    l->a->tag = 'A';
    l->b->tag = 'B';
    l->slice = cfg->link_slice;
    if (strcmp(cfg->link_mode, "frame") == 0) {
        l->mode_frame = 1;
    } else {
        l->mode_frame = 0;
        if (strcmp(cfg->link_mode, "slice") != 0)
            fprintf(stderr, "link: unknown link_mode '%s', using slice\n",
                    cfg->link_mode);
    }
    l->gain = cfg->gain;
    l->echo = cfg->echo;
    l->gate = cfg->gate;
    l->delay_samples = cfg->delay_samples;
    l->line8k = cfg->line8k;
    l->dial_dwell = cfg->dial_dwell;
    l->ring_on = cfg->ring_on;
    l->ring_period = cfg->ring_period;
    snprintf(l->state, sizeof l->state, "idle");
    l->answer_on_ring = 1;
    l->ring_seen_at = 0;
    for (int i = 0; i < 2; i++) {
        l->line_ab[i] = rs_new();
        l->line_ba[i] = rs_new();
    }
    return l;
}

void link_free(Link *l)
{
    if (!l)
        return;
    machine_free(l->a);
    machine_free(l->b);
    free(l->audio_a); free(l->audio_b);
    free(l->events); free(l->txt_a); free(l->txt_b);
    free(l->acc_a); free(l->acc_b);
    free(l->delay_q_a); free(l->delay_q_b);
    for (int i = 0; i < 2; i++) {
        rs_free(l->line_ab[i]);
        rs_free(l->line_ba[i]);
    }
    free(l);
}

int64_t link_samples(Link *l)
{
    if (l->audio_a_n == 0 && l->audio_b_n == 0) {
        l->base_samples = (int64_t)i186_cycles(l->b->cpu);
        l->base_set = 1;
    }
    int64_t base = l->base_set ? l->base_samples : 0;
    return (int64_t)((i186_cycles(l->b->cpu) - (uint64_t)base) * LINK_FS /
                     (uint64_t)l->b->cpu_hz);
}

static void trace_flush(Link *l, int side, const char *dir)
{
    if (!l->tr_n[side]) return;
    printf("%9.3f %-8s \"%.*s\"\n", l->tr_t[side], dir,
           (int)l->tr_n[side], l->tr_buf[side]);
    l->tr_n[side] = 0;
}

void link_trace(Link *l, int side, const char *dir, const uint8_t *s, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        uint8_t c = s[i];
        l->tr_dir[side] = dir;
        l->tr_last[side] = link_samples(l);
        if (c == '\r' || c == '\n') { trace_flush(l, side, dir); continue; }
        if (l->tr_n[side] == 0) l->tr_t[side] = (double)link_samples(l) / LINK_FS;
        if (l->tr_n[side] == sizeof l->tr_buf[side] - 1) trace_flush(l, side, dir);
        l->tr_buf[side][l->tr_n[side]++] = (c >= 0x20 && c < 0x7F) ? (char)c : '.';
    }
}

/* Print a partial line (text with no CR/LF yet, e.g. a payload) once no
 * more characters have arrived on that side for 0.2 s of call time. */
static void trace_idle(Link *l)
{
    int64_t now = link_samples(l);
    for (int side = 0; side < 2; side++)
        if (l->tr_n[side] && l->tr_dir[side] && now - l->tr_last[side] >= LINK_FS / 5)
            trace_flush(l, side, l->tr_dir[side]);
}

void link_send(Link *l, int side, const uint8_t *s, size_t n)
{
    link_trace(l, side, side ? "HOST->B" : "HOST->A", s, n);
    /* A host send ends its line even without CR/LF (e.g. the payload). */
    trace_flush(l, side, side ? "HOST->B" : "HOST->A");
    machine_send(side ? l->b : l->a, s, n);
}

void link_set_state(Link *l, const char *st)
{
    printf("%9.3f STATE    %s\n", (double)link_samples(l) / LINK_FS, st);
    snprintf(l->state, sizeof l->state, "%s", st);
    l->t_state = link_samples(l);
    if (l->events_n >= l->events_cap) {
        size_t nc = l->events_cap ? l->events_cap * 2 : 16;
        void *na = realloc(l->events, nc * sizeof *l->events);
        if (!na) abort();
        l->events = na; l->events_cap = nc;
    }
    l->events[l->events_n].t = (double)link_samples(l) / LINK_FS;
    snprintf(l->events[l->events_n].st, sizeof l->events[l->events_n].st, "%s", st);
    l->events_n++;
}

/* rx_gen adapters: the dial tone / ringback generators live in the Link;
 * Machine.rx_gen calls them with the Link as context. */
static int dial_tone_gen(void *ctx)
{
    Link *l = ctx;
    return tones_next(&l->dial_tone_gen);
}
static int ringback_gen(void *ctx)
{
    Link *l = ctx;
    return ringback_next(&l->ringback);
}

void link_start_call(Link *l, const char *number)
{
    char at[128];
    snprintf(at, sizeof at, "ATDT%s\r", number);
    link_send(l, 1, (const uint8_t *)at, strlen(at));
    dial_tone_init(&l->dial_tone_gen, 3000);
    l->b->rx_gen = dial_tone_gen;
    l->b->rx_gen_ctx = l;
    link_set_state(l, "dialtone");
}

static int max_abs(const int32_t *xs, size_t n)
{
    int m = 0;
    for (size_t i = 0; i < n; i++) {
        int v = xs[i] < 0 ? -xs[i] : xs[i];
        if (v > m) m = v;
    }
    return m;
}

static int txt_contains(const uint8_t *txt, size_t n, const char *needle)
{
    size_t ln = strlen(needle);
    if (n < ln) return 0;
    for (size_t i = 0; i + ln <= n; i++)
        if (memcmp(txt + i, needle, ln) == 0) return 1;
    return 0;
}

void link_co_step(Link *l, const int32_t *ta, size_t ta_n,
                  const int32_t *tb, size_t tb_n)
{
    (void)ta; (void)ta_n;
    double t = (double)(link_samples(l) - l->t_state) / LINK_FS;
    int quiet = tb_n == 0 || max_abs(tb, tb_n) < 300;
    if (strcmp(l->state, "dialtone") == 0 && tb_n && max_abs(tb, tb_n) > 15000) {
        link_set_state(l, "digit"); /* first DTMF digit starts */
    } else if (strcmp(l->state, "digit") == 0 && quiet && t > 0.05) {
        l->b->rx_gen = NULL;
        link_set_state(l, "dialing"); /* digit finished: exchange drops the dial tone */
    } else if (strcmp(l->state, "dialing") == 0 && t > l->dial_dwell) {
        l->ring_t0 = link_samples(l);
        l->rb_on = 0;
        ringback_init(&l->ringback, 0, 2500);
        l->b->rx_gen = ringback_gen;
        l->b->rx_gen_ctx = l;
        link_set_state(l, "ringing");
    } else if (strcmp(l->state, "ringing") == 0) {
        double tr = (double)(link_samples(l) - l->ring_t0) / LINK_FS;
        int on = fmod(tr, l->ring_period) < l->ring_on;
        l->a->ring_on = on;
        l->rb_on = on;
        l->ringback.on = on;
        if (l->answer_on_ring && txt_contains(l->txt_a, l->txt_a_n, "RING") &&
            tr > 0.5 && (double)(link_samples(l) - l->ring_seen_at) / LINK_FS > 0.4) {
            link_send(l, 0, (const uint8_t *)"ATA\r", 4);
            l->a->ring_on = 0;
            l->b->rx_gen = NULL;
            link_set_state(l, "answering");
        }
    } else if (strcmp(l->state, "answering") == 0) {
        link_set_state(l, "connected");
    }
}

/* Append samples to a machine's rxbuf (queue with head compaction). */
static void rxbuf_extend(Machine *m, const int32_t *xs, size_t n)
{
    if (n == 0)
        return;
    if (m->rxbuf_head) {
        memmove(m->rxbuf, m->rxbuf + m->rxbuf_head,
                m->rxbuf_n * sizeof *m->rxbuf);
        m->rxbuf_head = 0;
    }
    while (m->rxbuf_n + n > m->rxbuf_cap) {
        size_t nc = m->rxbuf_cap ? m->rxbuf_cap * 2 : 1024;
        uint16_t *na = realloc(m->rxbuf, nc * sizeof *na);
        if (!na) abort();
        m->rxbuf = na; m->rxbuf_cap = nc;
    }
    for (size_t i = 0; i < n; i++)
        m->rxbuf[m->rxbuf_n++] = (uint16_t)(xs[i] & 0xFFFF);
}

/* Link._delayed: hold `delay_samples` samples back per direction. */
static size_t delayed(Link *l, int which, const int32_t *xs, size_t n,
                      int32_t *out)
{
    if (l->delay_samples <= 0) {
        memcpy(out, xs, n * sizeof *xs);
        return n;
    }
    int32_t **q = which == 0 ? &l->delay_q_a : &l->delay_q_b;
    size_t *qn = which == 0 ? &l->delay_q_a_n : &l->delay_q_b_n;
    if (*qn == 0) {
        *q = calloc((size_t)l->delay_samples, sizeof **q);
        *qn = (size_t)l->delay_samples; /* pre-filled with zeros */
    }
    /* buf = q + xs; out = buf[:n]; q = buf[n:] (kept at delay_samples). */
    size_t total = *qn + n;
    int32_t *buf = malloc(total * sizeof *buf);
    memcpy(buf, *q, *qn * sizeof *buf);
    memcpy(buf + *qn, xs, n * sizeof *buf);
    memcpy(out, buf, n * sizeof *buf);
    memcpy(*q, buf + n, *qn * sizeof *buf);
    free(buf);
    return n;
}

/* Link._rs: linear interpolation resampling, per-direction state. */
static size_t rs_linear(double *phase, double *last, const int32_t *xs,
                        size_t n, double r_in, double r_out, int32_t *out)
{
    double step = r_in / r_out;
    size_t o = 0;
    for (size_t i = 0; i < n; i++) {
        double x = xs[i];
        while (*phase < 1.0) {
            out[o++] = (int32_t)(*last + (x - *last) * *phase);
            *phase += step;
        }
        *phase -= 1.0;
        *last = x;
    }
    return o;
}

size_t link_line8k_run(Link *l, int dir, const int32_t *xs, size_t n,
                       double gain, int src_rate, int dst_rate, int32_t *out);

static size_t link_new_samples(Machine *m, int which, Link *l, int32_t *out, size_t maxout)
{
    size_t n0 = m->lk_seen;
    size_t n = m->tx_all_n - n0;
    if (n > maxout) n = maxout;
    memcpy(out, m->tx_all + n0, n * sizeof *out);
    m->lk_seen = n0 + n;
    int32_t **audio = which == 0 ? &l->audio_a : &l->audio_b;
    size_t *an = which == 0 ? &l->audio_a_n : &l->audio_b_n;
    size_t *ac = which == 0 ? &l->audio_a_cap : &l->audio_b_cap;
    append_i32(audio, an, ac, out, n);
    return n;
}

/* One sample-exchange pass: drain new TX samples and DTE text from both
 * machines, feed the 100k-cycle co_step windows, and (once connected)
 * hand the samples across the line. Shared by slice mode (acc_advance =
 * l->slice) and frame mode (acc_advance = the B-side CPU cycles consumed
 * this pass). The scratch buffers are caller-owned. Moved verbatim out
 * of link_run so the slice-mode behaviour is unchanged. */
static void link_exchange(Link *l, int32_t *ta, int32_t *tb,
                          int32_t *rb, int32_t *ra, int64_t acc_advance)
{
    uint8_t dte[8192];
    size_t ta_n = link_new_samples(l->a, 0, l, ta, 8192);
    size_t tb_n = link_new_samples(l->b, 1, l, tb, 8192);
    size_t xa_n = machine_dte_text(l->a, dte, sizeof dte);
    if (xa_n) {
        link_trace(l, 0, "A->HOST", dte, xa_n);
        append_u8(&l->txt_a, &l->txt_a_n, &l->txt_a_cap, dte, xa_n);
        if (txt_contains(dte, xa_n, "RING"))
            l->ring_seen_at = link_samples(l);
    }
    size_t xb_n = machine_dte_text(l->b, dte, sizeof dte);
    if (xb_n) {
        link_trace(l, 1, "B->HOST", dte, xb_n);
        append_u8(&l->txt_b, &l->txt_b_n, &l->txt_b_cap, dte, xb_n);
    }
    trace_idle(l);
    append_i32(&l->acc_a, &l->acc_a_n, &l->acc_a_cap, ta, ta_n);
    append_i32(&l->acc_b, &l->acc_b_n, &l->acc_b_cap, tb, tb_n);
    l->acc_cyc += acc_advance;
    if (l->acc_cyc >= ACC_WINDOW) {
        link_co_step(l, l->acc_a, l->acc_a_n, l->acc_b, l->acc_b_n);
        l->acc_a_n = 0; l->acc_b_n = 0; l->acc_cyc = 0;
    }
    if (strcmp(l->state, "connected") == 0) {
        size_t n = ta_n < tb_n ? ta_n : tb_n;
        double g_ab = l->gain;
        if (l->gate) {
            int a21 = 0, b20 = 0;
            for (size_t i = 0; i < l->a->cmd_log16_n; i++)
                if ((l->a->cmd_log16[i].c & 0xFF) == 0x21) { a21 = 1; break; }
            for (size_t i = 0; i < l->b->cmd_log16_n; i++)
                if ((l->b->cmd_log16[i].c & 0xFF) == 0x20) { b20 = 1; break; }
            if (a21 && !b20) g_ab = 0.0;
        }
        if (l->line8k && !l->echo) {
            /* Each direction through the 8000 Hz PCM line:
             * codec rate -> 8 kHz -> far codec rate, band-limited
             * (link_line8k_run, below). */
            size_t rbn = link_line8k_run(l, 0, ta, ta_n, g_ab,
                l->a->rate, l->b->rate, rb);
            size_t ran = link_line8k_run(l, 1, tb, tb_n, l->gain,
                l->b->rate, l->a->rate, ra);
            int32_t dly[8192];
            size_t dn = delayed(l, 1, rb, rbn, dly);
            rxbuf_extend(l->b, dly, dn);
            dn = delayed(l, 0, ra, ran, dly);
            rxbuf_extend(l->a, dly, dn);
        } else if (l->a->rate == l->b->rate) {
            size_t rbn = 0, ran = 0;
            for (size_t k = 0; k < n; k++) {
                rb[rbn++] = (int32_t)((int)(ta[k] * g_ab + l->echo * tb[k]) & 0xFFFF);
                ra[ran++] = (int32_t)((int)(tb[k] * l->gain + l->echo * ta[k]) & 0xFFFF);
            }
            for (size_t k = n; k < ta_n; k++)
                rb[rbn++] = (int32_t)((int)(ta[k] * g_ab) & 0xFFFF);
            for (size_t k = n; k < tb_n; k++)
                ra[ran++] = (int32_t)((int)(tb[k] * l->gain) & 0xFFFF);
            int32_t dly[8192];
            size_t dn = delayed(l, 1, rb, rbn, dly);
            rxbuf_extend(l->b, dly, dn);
            dn = delayed(l, 0, ra, ran, dly);
            rxbuf_extend(l->a, dly, dn);
        } else {
            /* Different codec rates: resample each direction to
             * the receiver's rate (linear interpolation). */
            int32_t tmp[8192];
            size_t rn = rs_linear(&l->rs_ab_phase, &l->rs_ab_last,
                ta, ta_n, (double)l->a->rate, (double)l->b->rate, tmp);
            int32_t outb[8192];
            for (size_t k = 0; k < rn; k++)
                outb[k] = (int32_t)((int)(tmp[k] * g_ab) & 0xFFFF);
            rxbuf_extend(l->b, outb, rn);
            rn = rs_linear(&l->rs_ba_phase, &l->rs_ba_last,
                tb, tb_n, (double)l->b->rate, (double)l->a->rate, tmp);
            int32_t outa[8192];
            for (size_t k = 0; k < rn; k++)
                outa[k] = (int32_t)((int)(tmp[k] * l->gain) & 0xFFFF);
            rxbuf_extend(l->a, outa, rn);
        }
    }
}

/* Frame mode: run one machine until it has completed one codec frame
 * (one machine_sample() period), and update its side of the clock
 * tally. Returns the CPU cycles consumed. `side`: 0 = A, 1 = B.
 *
 * The frame boundary is the machine's own next_samp grid. The budget
 * is the distance to the next grid boundary plus one cycle: machine_run
 * services a sample due at the boundary only if the run extends past
 * it (machine_service runs at the top of machine_run's loop, and the
 * loop breaks when now >= end without a final service), and
 * next_samp is always the next event, so the sample is guaranteed to
 * fire inside this call. i186_run executes whole instructions, so the
 * run can overshoot the budget by up to one instruction; that
 * overshoot, plus the +1, is the side's debt, stored in f_debt[side]
 * and repaid automatically next pass: the next boundary sits on the
 * fixed grid, so the next budget (distance to it) is shorter by
 * exactly the debt.
 *
 * Before the DSP starts (next_samp == INF) there is no grid: the
 * nominal frame is sample_cyc and the debt is repaid explicitly by
 * subtracting it from the nominal budget. A pass that completes no
 * frame (machine_run broke early, e.g. a breakpoint) leaves the debt
 * untouched and retries the same boundary next pass.
 */
static int64_t link_frame_pass(Link *l, Machine *m, int side)
{
    uint64_t c0 = i186_cycles(m->cpu);
    uint64_t d0 = m->dsp ? c5x_total_cycles(m->dsp) : 0;
    int64_t now = (int64_t)c0;
    int64_t old_next = m->next_samp;
    int64_t boundary;
    if (old_next == MACHINE_INF) {
        boundary = now + (int64_t)m->sample_cyc - l->f_debt[side];
        if (boundary <= now)
            boundary = now + 1;
    } else {
        boundary = old_next;
    }
    int64_t budget = (boundary - now) + 1;
    if (budget < 1)
        budget = 1;
    machine_run(m, (uint64_t)budget);
    uint64_t c1 = i186_cycles(m->cpu);
    uint64_t d1 = m->dsp ? c5x_total_cycles(m->dsp) : 0;
    int64_t used_cpu = (int64_t)(c1 - c0);
    int64_t used_dsp = (int64_t)(d1 - d0);
    l->f_cpu[side] += used_cpu;
    l->f_dsp[side] += used_dsp;
    if (old_next != MACHINE_INF && m->next_samp > old_next) {
        l->f_frames[side]++;
        l->f_debt[side] = (int64_t)c1 - old_next;
    } else if (old_next == MACHINE_INF) {
        l->f_debt[side] = used_cpu - (int64_t)m->sample_cyc;
    }
    return used_cpu;
}

static void link_run_frame(Link *l, uint64_t cycles)
{
    uint64_t done = 0;
    /* Scratch buffers sized for one frame's worth of samples (a frame
     * is one codec sample per modem at equal rates, a few at most when
     * the rates differ; 8192 is generous). */
    int32_t *ta = malloc(8192 * sizeof *ta);
    int32_t *tb = malloc(8192 * sizeof *tb);
    int32_t *rb = malloc(8192 * sizeof *rb);
    int32_t *ra = malloc(8192 * sizeof *ra);
    while (done < cycles) {
        int64_t used_a = link_frame_pass(l, l->a, 0);
        int64_t used_b = link_frame_pass(l, l->b, 1);
        link_exchange(l, ta, tb, rb, ra, used_b);
        /* Per-pass cumulative |A - B| drift, CPU and DSP separately. */
        int64_t dc = l->f_cpu[0] - l->f_cpu[1];
        int64_t dd = l->f_dsp[0] - l->f_dsp[1];
        if (dc < 0) dc = -dc;
        if (dd < 0) dd = -dd;
        if (dc > l->f_max_abs_cpu_drift) l->f_max_abs_cpu_drift = dc;
        if (dd > l->f_max_abs_dsp_drift) l->f_max_abs_dsp_drift = dd;
        l->f_sum_abs_cpu_drift += dc;
        l->f_sum_abs_dsp_drift += dd;
        l->f_passes++;
        done += (uint64_t)(used_a > used_b ? used_a : used_b);
    }
    free(ta); free(tb); free(rb); free(ra);
}

void link_run(Link *l, uint64_t cycles)
{
    if (l->mode_frame) {
        link_run_frame(l, cycles);
        return;
    }
    uint64_t done = 0;
    /* Scratch buffers sized for one slice's worth of samples (a slice is
     * at most a few codec samples; 8192 is generous). */
    int32_t *ta = malloc(8192 * sizeof *ta);
    int32_t *tb = malloc(8192 * sizeof *tb);
    int32_t *rb = malloc(8192 * sizeof *rb);
    int32_t *ra = malloc(8192 * sizeof *ra);
    while (done < cycles) {
        /* One shared absolute clock (link.py run()): a machine that
         * overshot its slice gets a shorter budget next time. */
        if (!l->clock_started) {
            l->clock_started = 1;
            l->gt = 0;
            l->off_a = i186_cycles(l->a->cpu);
            l->off_b = i186_cycles(l->b->cpu);
        }
        l->gt += l->slice;
        done += (uint64_t)l->slice;
        int64_t na = l->gt - (int64_t)(i186_cycles(l->a->cpu) - l->off_a);
        int64_t nb = l->gt - (int64_t)(i186_cycles(l->b->cpu) - l->off_b);
        if (na > 0) machine_run(l->a, (uint64_t)na);
        if (nb > 0) machine_run(l->b, (uint64_t)nb);
        link_exchange(l, ta, tb, rb, ra, l->slice);
    }
    free(ta); free(tb); free(rb); free(ra);
}

/* LINE8K helper: int32 samples -> int16 -> rs -> rs -> int32, with the
 * gain applied on the first leg (as in link.py: [v * g for v in ta]). */
size_t link_line8k_run(Link *l, int dir, const int32_t *xs, size_t n,
                       double gain, int src_rate, int dst_rate, int32_t *out)
{
    static int16_t in16[8192], mid[16384], out16[16384];
    for (size_t i = 0; i < n; i++) {
        int v = (int)(xs[i] * gain);
        in16[i] = (int16_t)(v > 32767 ? 32767 : v < -32768 ? -32768 : v);
    }
    Resampler **pair = dir == 0 ? l->line_ab : l->line_ba;
    int m1 = rs_run(pair[0], in16, (int)n, mid, 16384, (double)src_rate, 8000.0);
    int m2 = rs_run(pair[1], mid, m1, out16, 16384, 8000.0, (double)dst_rate);
    for (int i = 0; i < m2; i++)
        out[i] = out16[i] & 0xFFFF;
    return (size_t)m2;
}

void link_text(Link *l, uint8_t *a_out, size_t *a_len, uint8_t *b_out, size_t *b_len)
{
    *a_len = machine_dte_text(l->a, a_out, 8192);
    *b_len = machine_dte_text(l->b, b_out, 8192);
}

int link_write_wav(Link *l, const char *path, int rate)
{
    /* One shared Resampler for the whole export (link.py creates one
     * rs and uses it for both channels, in order a then b, so its
     * history/position carry across). */
    Resampler *rs = rs_new();
    if (!rs)
        return -1;
    int16_t *out_a = NULL, *out_b = NULL;
    size_t na = 0, nb = 0;
    Machine *ms[2] = { l->a, l->b };
    int32_t *audios[2] = { l->audio_a, l->audio_b };
    size_t audio_ns[2] = { l->audio_a_n, l->audio_b_n };
    int16_t **outs[2] = { &out_a, &out_b };
    size_t *ns[2] = { &na, &nb };
    for (int ch = 0; ch < 2; ch++) {
        Machine *mm = ms[ch];
        size_t xsn = audio_ns[ch];
        int64_t base = (int64_t)mm->tx_all_n - (int64_t)xsn;
        int cur = 7200;
        for (size_t i = 0; i < mm->rate_idx_n; i++)
            if (mm->rate_idx[i].idx <= base)
                cur = mm->rate_idx[i].rate;
        /* Segments: (start, end, rate), cut at rate changes. */
        size_t pos = 0;
        int16_t *o = NULL;
        size_t on = 0, ocap = 0;
        for (size_t i = 0; i < mm->rate_idx_n; i++) {
            int64_t cut = mm->rate_idx[i].idx - base;
            if (cut <= 0)
                continue;
            if ((size_t)cut > pos) {
                size_t seg_end = (size_t)cut < xsn ? (size_t)cut : xsn;
                if (seg_end > pos) {
                    int16_t seg[4096];
                    int16_t res[32768];
                    size_t done = 0;
                    while (done < seg_end - pos) {
                        size_t chunk = seg_end - pos - done;
                        if (chunk > 4096) chunk = 4096;
                        for (size_t k = 0; k < chunk; k++) {
                            int32_t v = audios[ch][pos + done + k];
                            int32_t u = ((v & 0xFFFF) ^ 0x8000) - 0x8000;
                            seg[k] = (int16_t)u;
                        }
                        int m = rs_run(rs, seg, (int)chunk, res, 32768,
                                       (double)cur, (double)rate);
                        if (on + (size_t)m > ocap) {
                            size_t nc = ocap ? ocap * 2 : 4096;
                            while (nc < on + (size_t)m) nc *= 2;
                            o = realloc(o, nc * sizeof *o);
                            ocap = nc;
                        }
                        memcpy(o + on, res, (size_t)m * sizeof *res);
                        on += (size_t)m;
                        done += chunk;
                    }
                }
                pos = (size_t)cut;
            }
            cur = mm->rate_idx[i].rate;
        }
        if (pos < xsn) {
            int16_t seg[4096];
            int16_t res[32768];
            size_t done = 0;
            while (done < xsn - pos) {
                size_t chunk = xsn - pos - done;
                if (chunk > 4096) chunk = 4096;
                for (size_t k = 0; k < chunk; k++) {
                    int32_t v = audios[ch][pos + done + k];
                    int32_t u = ((v & 0xFFFF) ^ 0x8000) - 0x8000;
                    seg[k] = (int16_t)u;
                }
                int m = rs_run(rs, seg, (int)chunk, res, 32768,
                               (double)cur, (double)rate);
                if (on + (size_t)m > ocap) {
                    size_t nc = ocap ? ocap * 2 : 4096;
                    while (nc < on + (size_t)m) nc *= 2;
                    o = realloc(o, nc * sizeof *o);
                    ocap = nc;
                }
                memcpy(o + on, res, (size_t)m * sizeof *res);
                on += (size_t)m;
                done += chunk;
            }
        }
        *outs[ch] = o;
        *ns[ch] = on;
    }
    rs_free(rs);
    size_t n = na > nb ? na : nb;
    int16_t *left = calloc(n ? n : 1, sizeof *left);
    int16_t *right = calloc(n ? n : 1, sizeof *right);
    for (size_t i = 0; i < nb; i++) left[i] = out_b[i]; /* caller B */
    for (size_t i = 0; i < na; i++) right[i] = out_a[i]; /* answerer A */
    int rc = wav_write_stereo(path, left, right, (int)n, rate);
    free(left); free(right); free(out_a); free(out_b);
    return rc;
}
