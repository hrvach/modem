/* Full-system SV25 machine: 80C186EB + DSP + peripherals.
 * Port of modem/sys/machine.py. Section comments cite the Python file
 * (machine.py) and modem/sys/FULL_SYSTEM.md where the hardware facts
 * come from.
 *
 * Caps: Python kept log/dsp_log/rx_log unbounded; here they stop growing
 * at the caps below (tx_all, cmd_log16, msg_log and the audio path stay
 * exact). The caps are high enough for a 70 s call and are noted in
 * README.md.
 */
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "machine.h"

#define LOG_CAP (1u << 20)
#define DSP_LOG_CAP (1u << 20)
#define RX_LOG_CAP (1u << 20)
#define CMD_LOG_CAP (1u << 20)

/* What a host->DSP command means, as far as the notes establish it. Only
 * the documented cases are named; anything else is printed as unknown. */
static const char *dsp_cmd_note(int cmd, int arg)
{
    static char buf[96];
    const char *c = "unknown command", *a = "unknown argument";
    switch (cmd) {
    case 0x01:
        c = "boot-ROM/app start request";
        if (arg == 0x3F) a = "0x3F = ask for the 'started' reply";
        break;
    case 0x02: c = "overlay select"; a = "overlay DSP address (low byte shown)"; break;
    case 0x20: c = "B starts its modem mode"; break;
    case 0x21: c = "A starts its carrier"; break;
    case 0x83: c = "sync token sent at start"; break;
    }
    snprintf(buf, sizeof buf, "[cmd: %s; arg: %s]", c, a);
    return buf;
}

/* Live trace of DSP-side events on stdout (overlay loads, host->DSP
 * commands, DSP->host messages, DSP start). Time is that machine's own
 * call clock in seconds. fmt must not end in a newline. */
static void mtrace(Machine *m, const char *fmt, ...)
{
    va_list ap;
    printf("%9.3f %c DSP ", (double)i186_cycles(m->cpu) / (double)m->cpu_hz, m->tag);
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    putchar('\n');
}

/* Interrupt sources in default priority order (machine.py SRC):
 * (vector type, IMASK bit, control register). */
static const struct { int vec, bit, con; } SRC[SRC_N] = {
    { 0x08, 0x01, 0x12 }, { 0x12, 0x01, 0x12 }, { 0x13, 0x01, 0x12 },
    { 0x14, 0x04, 0x14 }, { 0x15, 0x04, 0x14 }, { 0x11, 0x08, 0x16 },
    { 0x0C, 0x10, 0x18 }, { 0x0D, 0x20, 0x1A }, { 0x0E, 0x40, 0x1C },
    { 0x0F, 0x80, 0x1E },
};
/* Control register -> IMASK bit (machine.py CON_BIT). */
static int con_bit(int reg)
{
    switch (reg) {
    case 0x12: return 0x01; case 0x14: return 0x04; case 0x16: return 0x08;
    case 0x18: return 0x10; case 0x1A: return 0x20; case 0x1C: return 0x40;
    case 0x1E: return 0x80;
    }
    return 0;
}
/* Vector type -> IMASK bit for EOI (machine.py EOI_BIT). */
static int eoi_bit(int vec)
{
    switch (vec) {
    case 0x08: case 0x12: case 0x13: return 0x01;
    case 0x14: case 0x15: return 0x04;
    case 0x11: return 0x08; case 0x0C: return 0x10; case 0x0D: return 0x20;
    case 0x0E: return 0x40; case 0x0F: return 0x80;
    }
    return 0;
}

static int clamp16(int v) { return v > 32767 ? 32767 : v < -32768 ? -32768 : v; }

/* ---- growable arrays (one helper per element type, via a macro) ---- */
#define GROW(arr, n, cap, type) do { \
    if ((n) >= (cap)) { \
        size_t nc = (cap) ? (cap) * 2 : 256; \
        type *na = realloc((arr), nc * sizeof *(arr)); \
        if (!na) abort(); \
        (arr) = na; (cap) = nc; \
    } } while (0)

#define PUSH(arr, n, cap, type, val) do { \
    GROW(arr, n, cap, type); (arr)[(n)++] = (val); } while (0)

/* ---- small hash set of uint32 (sec_abs) ---- */
/* st: 0 empty, 1 present, 2 deleted */
void u32set_init(U32Set *s)
{
    s->cap = 4096; s->n = 0;
    s->keys = calloc(s->cap, sizeof *s->keys);
    s->st = calloc(s->cap, sizeof *s->st);
}
static size_t u32_hash(uint32_t x) { return (size_t)(x * 2654435761u); }
int u32set_has(U32Set *s, uint32_t x)
{
    size_t i = u32_hash(x) & (s->cap - 1);
    while (s->st[i]) {
        if (s->st[i] == 1 && s->keys[i] == x)
            return 1;
        i = (i + 1) & (s->cap - 1);
    }
    return 0;
}
static void u32set_grow(U32Set *s)
{
    U32Set ns = { 0 };
    ns.cap = s->cap * 2; ns.n = s->n;
    ns.keys = calloc(ns.cap, sizeof *ns.keys);
    ns.st = calloc(ns.cap, sizeof *ns.st);
    for (size_t i = 0; i < s->cap; i++)
        if (s->st[i] == 1) {
            size_t j = u32_hash(s->keys[i]) & (ns.cap - 1);
            while (ns.st[j])
                j = (j + 1) & (ns.cap - 1);
            ns.st[j] = 1; ns.keys[j] = s->keys[i];
        }
    free(s->keys); free(s->st);
    *s = ns;
}
void u32set_add(U32Set *s, uint32_t x)
{
    if (u32set_has(s, x))
        return;
    if ((s->n + 1) * 2 > s->cap)
        u32set_grow(s);
    size_t i = u32_hash(x) & (s->cap - 1);
    while (s->st[i] == 1)
        i = (i + 1) & (s->cap - 1);
    s->st[i] = 1; s->keys[i] = x; s->n++;
}
void u32set_del(U32Set *s, uint32_t x)
{
    size_t i = u32_hash(x) & (s->cap - 1);
    while (s->st[i]) {
        if (s->st[i] == 1 && s->keys[i] == x) {
            s->st[i] = 2; s->n--;
            return;
        }
        i = (i + 1) & (s->cap - 1);
    }
}

/* ---- small hash counter (wr_pcs / rd_pcs / port5_pcs) ---- */
void counter_init(Counter *c)
{
    c->cap = 16384;
    c->keys = calloc(c->cap, sizeof *c->keys);
    c->vals = calloc(c->cap, sizeof *c->vals);
    c->st = calloc(c->cap, sizeof *c->st);
}
void counter_inc(Counter *c, uint64_t key)
{
    size_t i = (size_t)(key * 1099511628211ull) & (c->cap - 1);
    while (c->st[i] == 1 && c->keys[i] != key)
        i = (i + 1) & (c->cap - 1);
    if (c->st[i] != 1) {
        c->st[i] = 1; c->keys[i] = key; c->vals[i] = 0;
    }
    c->vals[i]++;
}

/* ---- _Lp6 (machine.py) ---- */
void lp6_set(Lp6 *f, double fc, double fs)
{
    long key_fc = lround(fc), key_fs = lround(fs);
    if (f->designed && f->key_fc == key_fc && f->key_fs == key_fs)
        return;
    f->key_fc = key_fc; f->key_fs = key_fs;
    f->designed = 1;
    if (fc >= 0.45 * fs) {
        f->nsec = 0;
        return;
    }
    /* 6th-order Chebyshev I, 0.15 dB ripple, as 3 biquads, bilinear
     * transform, unity DC gain. */
    const int N = 6;
    double eps = sqrt(pow(10.0, 0.015) - 1.0);
    double w3 = cosh(acosh(sqrt(pow(10.0, 0.3) - 1.0) / eps) / N);
    double fp = (fc < 0.46 * fs ? fc : 0.46 * fs) / w3;
    double a = asinh(1.0 / eps) / N;
    double wd = 2 * fs * tan(M_PI * fp / fs);
    double cc = 2 * fs;
    double dc = 1.0;
    for (int k = 1; k <= N / 2; k++) {
        double th = (2 * k - 1) * M_PI / (2 * N);
        double sr = -sinh(a) * sin(th), si = cosh(a) * cos(th);
        double A1 = -2 * sr * wd;
        double A0 = (sr * sr + si * si) * wd * wd;
        double den = cc * cc + A1 * cc + A0;
        double b = A0 / den;
        double a1 = (2 * A0 - 2 * cc * cc) / den;
        double a2 = (cc * cc - A1 * cc + A0) / den;
        f->sec[k - 1][0] = b; f->sec[k - 1][1] = 2 * b; f->sec[k - 1][2] = b;
        f->sec[k - 1][3] = a1; f->sec[k - 1][4] = a2;
        dc *= (4 * b) / (1 + a1 + a2);
    }
    f->sec[0][0] /= dc; f->sec[0][1] /= dc; f->sec[0][2] /= dc;
    f->nsec = 3;
    /* State is NOT reset on redesign (Python design() only creates it
     * when its length differs, i.e. on the first design). */
}

double lp6_call(Lp6 *f, double x)
{
    for (int s = 0; s < f->nsec; s++) {
        double b0 = f->sec[s][0], b1 = f->sec[s][1], b2 = f->sec[s][2];
        double a1 = f->sec[s][3], a2 = f->sec[s][4];
        double y = b0 * x + f->st[s][0];
        f->st[s][0] = b1 * x - a1 * y + f->st[s][1];
        f->st[s][1] = b2 * x - a2 * y;
        x = y;
    }
    return x;
}

/* ---- boot-block CRC (machine.py _boot_crc) ---- */
static uint16_t boot_crc(const uint8_t *flash)
{
    uint32_t crc = 0xFFFF;
    for (uint32_t i = 0x40000; i < 0x77FFE; i++) {
        uint32_t b = flash[i];
        uint32_t dx = crc;
        uint32_t al = b ^ (dx & 0xFF);
        uint32_t ax = al;
        ax = (ax << 4) & 0xFFFF;
        dx = (dx & 0xFF00) | al;
        dx ^= ax;
        ax >>= 1;
        dx = ((dx & 0xFF) << 8) | (dx >> 8);
        dx ^= ax;
        ax = (ax << 4) & 0xFFFF;
        ax = (ax & 0x00FF) | (ax & 0x0700);
        dx ^= ax;
        ax = (ax << 1) & 0xFFFF;
        dx = (dx & 0xFF00) | ((dx ^ (ax >> 8)) & 0xFF);
        crc = dx & 0xFFFF;
    }
    return (uint16_t)crc;
}

static uint8_t *read_file(const char *path, size_t *len_out)
{
    FILE *f = fopen(path, "rb");
    if (!f)
        return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n < 0) {
        fclose(f);
        return NULL;
    }
    uint8_t *buf = malloc((size_t)n ? (size_t)n : 1);
    if (n > 0 && fread(buf, 1, (size_t)n, f) != (size_t)n) {
        free(buf);
        fclose(f);
        return NULL;
    }
    fclose(f);
    *len_out = (size_t)n;
    return buf;
}

uint32_t machine_phys_pc(Machine *m)
{
    return ((i186_get(m->cpu, GLUE_I186_CS) << 4) + i186_get(m->cpu, GLUE_I186_IP)) & 0xFFFFF;
}

uint8_t machine_rd8(Machine *m, uint32_t a)
{
    return i186_mem(m->cpu)[a & 0xFFFFF];
}

uint16_t machine_rd16(Machine *m, uint32_t a)
{
    uint8_t *mem = i186_mem(m->cpu);
    return (uint16_t)(mem[a & 0xFFFFF] | (mem[(a + 1) & 0xFFFFF] << 8));
}

void machine_wr8(Machine *m, uint32_t a, uint8_t v)
{
    i186_mem(m->cpu)[a & 0xFFFFF] = v;
}

/* ---- EEPROM (machine.py Eeprom) ---- */
static void eeprom_init(Eeprom *e, const uint8_t *image, size_t len)
{
    e->n = 256;
    for (int i = 0; i < 256; i++)
        e->w[i] = 0xFFFF;
    e->ewen = 0; e->dirty = 0;
    if (image) {
        for (int i = 0; i < 256 && 2 * i + 1 < (int)len; i++)
            e->w[i] = (uint16_t)(image[2 * i] | (image[2 * i + 1] << 8));
    }
    e->state = EE_IDLE; e->nbits = 0; e->do_bit = 1; e->addr = 0; e->rdn = 0;
}

static void eeprom_clock(Eeprom *e, int di)
{
    if (e->state == EE_IDLE) {
        if (di) { e->state = EE_CMD; e->nbits = 0; }
    } else if (e->state == EE_CMD) {
        e->bits[e->nbits++] = di;
        if (e->nbits == 10) {
            int op = e->bits[0] * 2 + e->bits[1];
            int a = 0;
            for (int i = 2; i < 10; i++)
                a = (a << 1) | e->bits[i];
            if (op == 2) { e->state = EE_READ; e->addr = a; e->rdn = 0; e->do_bit = 0; }
            else if (op == 1) { e->state = EE_WDATA; e->addr = a; e->nbits = 0; }
            else if (op == 3) {
                if (e->ewen) { e->w[a % e->n] = 0xFFFF; e->dirty = 1; }
                e->state = EE_IDLE;
            } else {
                int sub = a >> 6;
                if (sub == 3) e->ewen = 1;
                else if (sub == 0) e->ewen = 0;
                else if (sub == 2 && e->ewen) {
                    for (int i = 0; i < e->n; i++) e->w[i] = 0xFFFF;
                    e->dirty = 1;
                }
                e->state = EE_IDLE; e->do_bit = 1;
            }
        }
    } else if (e->state == EE_READ) {
        e->do_bit = (e->w[e->addr % e->n] >> (15 - e->rdn)) & 1;
        e->rdn++;
        if (e->rdn == 16) { e->rdn = 0; e->addr = (e->addr + 1) % e->n; }
    } else if (e->state == EE_WDATA) {
        e->bits[e->nbits++] = di;
        if (e->nbits == 16) {
            int v = 0;
            for (int i = 0; i < 16; i++)
                v = (v << 1) | e->bits[i];
            if (e->ewen) { e->w[e->addr % e->n] = (uint16_t)v; e->dirty = 1; }
            e->state = EE_IDLE; e->do_bit = 1;
        }
    }
}

/* Forward declarations (defined below). */
void machine_sync_ack(Machine *m);
uint16_t machine_requests(Machine *m);
void machine_eoi(Machine *m, uint32_t v);
static uint32_t machine_iord(void *ctx, uint16_t p, int w);
static void machine_iowr(void *ctx, uint16_t p, int w, uint32_t v);
static uint32_t machine_mmrd(void *ctx, uint32_t a, int w);
static void machine_mmwr(void *ctx, uint32_t a, int w, uint32_t v);
static uint16_t machine_dsp_rd(void *ctx, uint16_t p);
static void machine_dsp_wr(void *ctx, uint16_t p, uint16_t v);
static void dsp_load_pm(C5x *dsp, uint16_t addr, const uint8_t *blob, size_t len);

void machine_set_rate(Machine *m, int rate)
{
    if (rate == m->rate)
        return;
    uint32_t pending = m->dsp ? (c5x_dxr_head(m->dsp) - m->tx_seen) : 0;
    RateIdxEnt e = { (int64_t)m->tx_all_n + (int64_t)pending, rate };
    PUSH(m->rate_idx, m->rate_idx_n, m->rate_idx_cap, RateIdxEnt, e);
    m->rate = rate;
    m->sample_cyc = (int)(m->cpu_hz / rate);
    if (!m->dsp_clk_fixed)
        m->dsp_cps = (int)m->dsp_cps_7200;
    else
        m->dsp_cps = (int)(m->dsp_hz / rate);
    RateLogEnt le = { (double)i186_cycles(m->cpu) / (double)m->cpu_hz, rate };
    PUSH(m->rate_log, m->rate_log_n, m->rate_log_cap, RateLogEnt, le);
}

static double aic_gain_in(Machine *m)
{
    static const double g[4] = { 0.0, 1.0, 2.0, 4.0 };
    return m->ac01_model ? g[(m->aic[4] >> 2) & 3] : 1.0;
}
static double aic_gain_out(Machine *m)
{
    static const double g[4] = { 0.0, 1.0, 0.5, 0.25 };
    return m->ac01_model ? g[m->aic[4] & 3] : 1.0;
}

static void aic_update(Machine *m)
{
    /* fs = 12000 N / (A B) once N (port 0x6B), A and B (AC01 registers
     * 1, 2) are all known. */
    int a = m->aic[1], b = m->aic[2], n = m->mclk_n;
    if (n && a && b) {
        int r = (int)lround(12000.0 * n / (a * b));
        if (r < 4000) r = 4000;
        if (r > 16000) r = 16000;
        for (int i = 0; i < m->ac01_clamp_n; i++)
            if (m->ac01_clamp_keys[i] == r)
                r = m->ac01_clamp_vals[i];
        machine_set_rate(m, r);
    }
}

static void aic_feed(Machine *m, const uint16_t *words, int n)
{
    for (int i = 0; i < n; i++) {
        uint16_t w = words[i] & 0xFFFF;
        if (m->aic_req) {
            m->aic_req = 0;
            int reg = (w >> 8) & 0x1F;
            if (!((w >> 13) & 1) && reg >= 1 && reg <= 6) {
                m->aic[reg] = w & 0xFF;
                AicLogEnt le = { (double)i186_cycles(m->cpu) / (double)m->cpu_hz, reg, w & 0xFF };
                PUSH(m->aic_log, m->aic_log_n, m->aic_log_cap, AicLogEnt, le);
                aic_update(m);
            }
        } else if ((w & 3) == 3) {
            m->aic_req = 1;
        }
    }
}

/* ---- DIP switches / board ID (machine.py set_dip / _hw_id_bit) ---- */
static void machine_set_dip(Machine *m, const int *on, int non)
{
    /* port 0x12 bits by switch number; a 0 bit = ON. Default = factory
     * setting from the manual (switches 3, 5, 8, 9 ON). */
    static const struct { int sw, bit; } p12[] = {
        { 2, 0x02 }, { 3, 0x01 }, { 4, 0x08 }, { 5, 0x04 },
        { 7, 0x80 }, { 8, 0x40 }, { 9, 0x20 }, { 10, 0x10 },
    };
    int v12 = 0;
    for (size_t i = 0; i < sizeof p12 / sizeof *p12; i++) {
        int is_on = 0;
        for (int j = 0; j < non; j++)
            if (on[j] == p12[i].sw) is_on = 1;
        if (!is_on) v12 |= p12[i].bit;
    }
    m->port_in[0x12] = (uint8_t)v12;
    int sw6 = 0;
    for (int j = 0; j < non; j++)
        if (on[j] == 6) sw6 = 1;
    m->port_in[0x14] = (uint8_t)((m->port_in[0x14] & ~0x04) | (sw6 ? 0 : 0x04));
    /* Front-panel Voice/Data button = port 0x14 bit6, active low. */
    m->port_in[0x14] = (uint8_t)((m->port_in[0x14] & ~0x40) | (m->voice_data_button ? 0 : 0x40));
    int sw1 = 0;
    for (int j = 0; j < non; j++)
        if (on[j] == 1) sw1 = 1;
    m->p2pin = (m->p2pin & ~0x40) | (sw1 ? 0 : 0x40);
}

static int machine_hw_id_bit(Machine *m)
{
    uint32_t a = m->ports_set[0x12] ? m->ports[0x12] : 0xFF;
    uint32_t b = m->ports_set[0x14] ? m->ports[0x14] : 0xFF;
    /* (D, A, B, C) = bits 3..0; hi values in that order. */
    uint32_t his[4] = { b & 0x40, a & 0x02, b & 0x10, b & 0x20 };
    int bits[4] = { 3, 2, 1, 0 };
    int r = 1;
    for (int i = 0; i < 4; i++)
        if (!his[i])
            r &= (m->hw_idx >> bits[i]) & 1;
    return r;
}

static void ovl_host_ack(Machine *m, uint32_t v)
{
    if (v & 1) {
        static const int addrs[4] = { 0x40, 0x42, 0x44, 0x46 };
        for (int i = 0; i < 4; i++) {
            uint8_t b = m->ovl_bytes[addrs[i]];
            PUSH(m->ovl_data, m->ovl_data_n, m->ovl_data_cap, uint8_t, b);
        }
    }
    if (v & 2) {
        static const int addrs[4] = { 0x48, 0x4A, 0x4C, 0x4E };
        for (int i = 0; i < 4; i++) {
            uint8_t b = m->ovl_bytes[addrs[i]];
            PUSH(m->ovl_data, m->ovl_data_n, m->ovl_data_cap, uint8_t, b);
        }
    }
    if (v & 4) {
        if (m->ovl_data_n) {
            dsp_load_pm(m->dsp, (uint16_t)m->ovl_addr, m->ovl_data, m->ovl_data_n);
            OvlLoadEnt le = { i186_cycles(m->cpu), m->ovl_addr, (int)m->ovl_data_n };
            PUSH(m->ovl_loads, m->ovl_loads_n, m->ovl_loads_cap, OvlLoadEnt, le);
            mtrace(m, "overlay load: %zu bytes to DSP PM %04X", m->ovl_data_n, m->ovl_addr);
            m->ovl_data_n = 0;
        }
        m->ovl_status &= ~4;
    }
}

/* ---- _cmd_override (machine.py) ---- */
static void cmd_override_build(Machine *m)
{
    memset(m->ovr_arg_set, 0, sizeof m->ovr_arg_set);
    memset(m->ovr_pos_set, 0, sizeof m->ovr_pos_set);
    memset(m->ovr_ren_set, 0, sizeof m->ovr_ren_set);
    memset(m->ovr_cnt, 0, sizeof m->ovr_cnt);
    char buf[CFG_MAX_STR];
    snprintf(buf, sizeof buf, "%s", m->cmd_ovr);
    char *save = NULL;
    for (char *e = strtok_r(buf, ";", &save); e; e = strtok_r(NULL, ";", &save)) {
        while (*e == ' ' || *e == '\t') e++;
        if (!*e) continue;
        char *gt = strchr(e, '>');
        if (gt) {
            *gt = '\0';
            int a = (int)strtol(e, NULL, 16), b = (int)strtol(gt + 1, NULL, 16);
            m->ovr_ren[a & 0xFF] = b; m->ovr_ren_set[a & 0xFF] = 1;
        } else {
            char *eq = strchr(e, '=');
            if (!eq) continue;
            *eq = '\0';
            int v = (int)strtol(eq + 1, NULL, 16);
            char *at = strchr(e, '@');
            if (at) {
                *at = '\0';
                int c = (int)strtol(e, NULL, 16), idx = atoi(at + 1);
                if (idx >= 1 && idx <= 6) {
                    m->ovr_pos[c & 0xFF][idx] = v;
                    m->ovr_pos_set[c & 0xFF][idx] = 1;
                }
            } else {
                int c = (int)strtol(e, NULL, 16);
                m->ovr_arg[c & 0xFF] = v; m->ovr_arg_set[c & 0xFF] = 1;
            }
        }
    }
    m->ovr_built = 1;
}

static void cmd_override(Machine *m)
{
    if (!m->ovr_built)
        cmd_override_build(m);
    int cmd = m->h2d[0x5E - 0x58] & 0xFF;
    int n = m->ovr_cnt[cmd]++;
    if (m->ovr_ren_set[cmd])
        m->h2d[0x5E - 0x58] = (uint16_t)((m->h2d[0x5E - 0x58] & 0xFF00) | m->ovr_ren[cmd]);
    int val = -1;
    if (n % 6 + 1 >= 1 && m->ovr_pos_set[cmd][n % 6 + 1])
        val = m->ovr_pos[cmd][n % 6 + 1];
    else if (m->ovr_arg_set[cmd])
        val = m->ovr_arg[cmd];
    if (val >= 0)
        m->h2d[0x5F - 0x58] = (uint16_t)((m->h2d[0x5F - 0x58] & 0xFF00) | val);
}

static void dsp_load_pm(C5x *dsp, uint16_t addr, const uint8_t *blob, size_t len)
{
    uint16_t *pm = c5x_pmem(dsp);
    size_t n = len / 2;
    for (size_t i = 0; i < n; i++)
        pm[(addr + i) & 0xFFFF] = (uint16_t)(blob[2 * i] | (blob[2 * i + 1] << 8));
    c5x_pm_invalidate(dsp);
}

Machine *machine_new(const Config *cfg)
{
    Machine *m = calloc(1, sizeof *m);
    if (!m)
        return NULL;
    m->cfg = cfg;
    m->prof = cfg->prof;
    m->cpu_hz = cfg->cpu_hz ? cfg->cpu_hz : cfg->prof->cpu_hz;
    m->dsp_hz = cfg->dsp_hz ? cfg->dsp_hz : cfg->prof->dsp_hz;
    m->dsp_cps_7200 = m->dsp_hz / 7200; /* floor division, as in machine.py */
    m->sample_cyc = (int)(m->cpu_hz / 7200);
    m->dsp_cps = (int)m->dsp_cps_7200;
    m->rate = 7200;
    m->iface403 = strcmp(cfg->prof->iface, "403") == 0;
    /* Toggles: config values already carry env fallbacks (config.c). */
    m->p51div = cfg->p51div; m->hb_timer = cfg->hb_timer;
    m->dsp_clk_fixed = cfg->dsp_clk_fixed; m->port_rb = cfg->port_rb;
    m->sec_frame = cfg->sec_frame; m->int23 = cfg->int23;
    m->ac01_model = cfg->ac01_model; m->ac01_filt = cfg->ac01_filt;
    m->ac01_lat = cfg->ac01_lat;
    m->xint_mode = cfg->xint_mode; m->cycle_model = cfg->cycle_model;
    m->legacy = cfg->legacy; m->tdm_irqs = cfg->tdm_irqs;
    m->bankwr = cfg->bankwr; m->cmpr = cfg->cmpr; m->tintslot = cfg->tintslot;
    snprintf(m->cmd_ovr, sizeof m->cmd_ovr, "%s", cfg->cmd_ovr);
    snprintf(m->dsp_rom, sizeof m->dsp_rom, "%s", cfg->dsp_rom);
    m->cpu_scale = cfg->cpu_scale; m->ud_trap = cfg->ud_trap;
    m->cpu_model = cfg->cpu_model; m->patch_crc = cfg->patch_crc;
    m->nvram_mode = cfg->nvram_mode; m->fax_patch = cfg->fax_patch;
    m->dte_speed_code = 0x02;
    m->noise_amp = cfg->noise_amp;
    m->seed = 12345;
    m->heartbeat = 1;
    m->hb_ticks = m->hb_timer ? 1 : 3;
    m->dte_baud = 115200;
    m->dte_gap = (int)(m->cpu_hz / 500);
    m->hw_idx = cfg->hw_idx >= 0 ? cfg->hw_idx : cfg->prof->hw_idx;
    m->voice_data_button = cfg->voice_data_button;
    m->logging = 1;
    m->offered = -1;
    m->msk = 0xFD; m->primsk = 7;
    for (int i = 0; i < 256; i++)
        m->icon[i] = 0x07;
    for (int i = 0; i < 3; i++) {
        m->tm[i].nxt = MACHINE_INF;
        m->tm[i].last = 0;
    }
    for (int j = 0; j < 2; j++) {
        m->uart[j].sts = 0x08;
        m->uart[j].rx_t = MACHINE_INF;
        m->uart[j].tx_t = MACHINE_INF;
        m->uart[j].pu = 8;
    }
    m->line = 1;
    m->next_samp = MACHINE_INF;
    m->aic[1] = 18; m->aic[2] = 18; m->aic[3] = 0;
    m->aic[4] = 5; m->aic[5] = 1; m->aic[6] = 0;
    u32set_init(&m->sec_abs);
    counter_init(&m->wr_pcs); counter_init(&m->rd_pcs); counter_init(&m->port5_pcs);
    /* AC01_CLAMP: "10267:9600, ..." */
    if (cfg->ac01_clamp[0]) {
        char buf[CFG_MAX_STR];
        snprintf(buf, sizeof buf, "%s", cfg->ac01_clamp);
        char *save = NULL;
        for (char *e = strtok_r(buf, ",", &save); e && m->ac01_clamp_n < 16;
             e = strtok_r(NULL, ",", &save)) {
            char *c = strchr(e, ':');
            if (!c) continue;
            *c = '\0';
            m->ac01_clamp_keys[m->ac01_clamp_n] = atoi(e);
            m->ac01_clamp_vals[m->ac01_clamp_n] = atoi(c + 1);
            m->ac01_clamp_n++;
        }
    }
    RateIdxEnt r0 = { 0, 7200 };
    PUSH(m->rate_idx, m->rate_idx_n, m->rate_idx_cap, RateIdxEnt, r0);

    /* CPU + flash (machine.py Machine.__init__). */
    m->cpu = i186_new();
    if (!m->cpu) { free(m); return NULL; }
    char flash_path[CFG_MAX_PATH], nvram_path[CFG_MAX_PATH];
    config_resolve(cfg, cfg->flash, flash_path, sizeof flash_path);
    config_resolve(cfg, cfg->nvram, nvram_path, sizeof nvram_path);
    size_t flen = 0;
    uint8_t *flash = read_file(flash_path, &flen);
    if (!flash) {
        fprintf(stderr, "machine: cannot read flash '%s'\n", flash_path);
        free(m);
        return NULL;
    }
    if (m->patch_crc >= 0 && flen > 0x77FFF &&
        flash[0x77FFE] == 0xFF && flash[0x77FFF] == 0xFF) {
        /* SDL writes the image CRC into flash after programming; XMD
         * does not contain it (images that already carry one keep it). */
        uint16_t crc = boot_crc(flash);
        flash[0x77FFE] = (uint8_t)(crc & 0xFF);
        flash[0x77FFF] = (uint8_t)(crc >> 8);
    }
    uint8_t *mem = i186_mem(m->cpu);
    for (size_t i = 0; i < flen; i++)
        mem[(0x80000 + i) & 0xFFFFF] = flash[i];
    free(flash);
    for (int p = 0x80; p < 0x100; p++)
        i186_set_ro_page(m->cpu, (uint32_t)p, 1);

    /* NVRAM / EEPROM. */
    size_t nvlen = 0;
    uint8_t *nv = NULL;
    FILE *nvf = fopen(nvram_path, "rb");
    if (nvf) {
        fclose(nvf);
        nv = read_file(nvram_path, &nvlen);
    }
    eeprom_init(&m->eeprom, nv, nvlen);
    free(nv);

    i186_set_hooks(m->cpu, machine_iord, machine_iowr, machine_mmrd, machine_mmwr, m);
    if (getenv("RX_TRACE"))
        m->rx_trace = malloc(1); /* non-NULL enables tracing (grows on demand) */
    m->flash_id = 0;
    i186_set_mmio_page(m->cpu, 0xFF, 1);
    i186_set_mmio_page(m->cpu, 0x0F, 1);
    m->port_in[0x10] = 0x00; m->port_in[0x12] = 0x00; m->port_in[0x14] = 0x00;
    { static const int on[] = { 3, 5, 8, 9 }; machine_set_dip(m, on, 4); }
    if (m->fax_patch)
        i186_set_bp(m->cpu, 0x9EB96, 1);
    if (m->nvram_mode >= 0)
        i186_set_bp(m->cpu, 0x8063E, 1);
    i186_set_cycle_model(m->cpu, m->cpu_model);
    i186_set_cycle_scale(m->cpu, m->cpu_scale);
    i186_set_ud_trap(m->cpu, m->ud_trap ? 1 : 0);
    i186_reset(m->cpu);
    return m;
}

void machine_free(Machine *m)
{
    if (!m)
        return;
    free(m->log); free(m->pcblog); free(m->dte_out); free(m->txq);
    free(m->dsp_bursts);
    free(m->edges); free(m->rxbuf); free(m->rx_log); free(m->tx_all);
    free(m->ovl_data); free(m->ovl_loads); free(m->cmd_log);
    free(m->cmd_log16); free(m->msg_log); free(m->dsp_log);
    free(m->rate_idx); free(m->rate_log); free(m->aic_log);
    free(m->rx_trace); free(m->lat_q);
    free(m->sec_abs.keys); free(m->sec_abs.st);
    free(m->wr_pcs.keys); free(m->wr_pcs.vals); free(m->wr_pcs.st);
    free(m->rd_pcs.keys); free(m->rd_pcs.vals); free(m->rd_pcs.st);
    free(m->port5_pcs.keys); free(m->port5_pcs.vals); free(m->port5_pcs.st);
    /* The cores have no free in the Python ABI (c5x has none at all);
     * i186_free exists in i186.c but was not wrapped by i186.py, so the
     * glue does not call it either. OS reclaims on exit. */
    free(m);
}

void machine_send(Machine *m, const uint8_t *text, size_t len)
{
    /* txq is a queue: live bytes are txq[txq_head .. txq_head+txq_n). */
    if (m->txq_head + m->txq_n + len > m->txq_cap) {
        if (m->txq_head) {
            memmove(m->txq, m->txq + m->txq_head, m->txq_n);
            m->txq_head = 0;
        }
        while (m->txq_n + len > m->txq_cap) {
            size_t nc = m->txq_cap ? m->txq_cap * 2 : 256;
            uint8_t *na = realloc(m->txq, nc);
            if (!na) abort();
            m->txq = na; m->txq_cap = nc;
        }
    }
    memcpy(m->txq + m->txq_head + m->txq_n, text, len);
    m->txq_n += len;
}

void machine_send_str(Machine *m, const char *text)
{
    machine_send(m, (const uint8_t *)text, strlen(text));
}

size_t machine_dte_text(Machine *m, uint8_t *out, size_t maxout)
{
    size_t n = 0;
    for (size_t i = 0; i < m->dte_out_n && n < maxout; i++)
        if (m->dte_out[i] != 0xFF)
            out[n++] = m->dte_out[i];
    m->dte_out_n = 0;
    return n;
}

void machine_start_dsp(Machine *m)
{
    mtrace(m, "DSP start (supervisor bursts)");
    /* Resident bank = captured bursts, skipping the first 16 bytes (the
     * 0x83 reset pattern), dsp_base_bytes per profile (sv25: 55420). */
    size_t total = m->dsp_bursts_n * 8;
    size_t avail = total > 16 ? total - 16 : 0;
    size_t take = avail;
    if (m->prof->dsp_base_bytes >= 0 && take > (size_t)m->prof->dsp_base_bytes)
        take = (size_t)m->prof->dsp_base_bytes;
    uint8_t *flat = malloc(total ? total : 1);
    for (size_t i = 0; i < m->dsp_bursts_n; i++)
        memcpy(flat + i * 8, m->dsp_bursts + i * 8, 8);
    m->dsp = c5x_new();
    c5x_set_diag(m->dsp, 0);   /* replay needs diagnostics off */
    dsp_load_pm(m->dsp, 0x8000, flat + 16, take);
    free(flat);
    m->sender_mode = 0;
    memset(m->sender_pcs, 0, sizeof m->sender_pcs);
    if (m->prof->sender_scan) {
        /* The message sender's OUT 005E/005F instructions move between
         * DSP builds: find them in the loaded image. */
        m->sender_mode = 1;
        uint16_t *pm = c5x_pmem(m->dsp);
        for (uint32_t a = 0x8000; a < 0xFFFE; a++) {
            if ((pm[a] >> 8) == 0x0C && (pm[a + 1] == 0x5E || pm[a + 1] == 0x5F)) {
                m->sender_pcs[(a + 1) & 0xFFFF] = 1;
                m->sender_pcs[(a + 2) & 0xFFFF] = 1;
            }
        }
    }
    if (m->dsp_rom[0]) {
        char rom_path[CFG_MAX_PATH];
        if (strcmp(m->dsp_rom, "1") == 0)
            snprintf(rom_path, sizeof rom_path, "fw/c5x-onchip-rom-8k.bin");
        else
            config_resolve(m->cfg, m->dsp_rom, rom_path, sizeof rom_path);
        size_t rlen = 0;
        uint8_t *rom = read_file(rom_path, &rlen);
        if (rom) {
            dsp_load_pm(m->dsp, 0, rom, rlen);
            free(rom);
        }
    }
    const Profile *pre = m->prof;
    uint16_t *dm = c5x_dmem(m->dsp);
    for (int i = 0; i < 11; i++) {
        c5x_set_ivec_ind(m->dsp, i, (uint16_t)(0x60 + i));
        if (pre->isr_presets_all >= 0)
            dm[0x60 + i] = (uint16_t)pre->isr_presets_all;
    }
    if (pre->isr_presets_all >= 0) {
        for (int i = 0; i < pre->isr_extra_n; i++)
            dm[pre->isr_extra_addr[i]] = (uint16_t)pre->isr_extra_val[i];
    }
    if (m->tintslot >= 0)
        c5x_set_ivec_ind(m->dsp, 3, (uint16_t)m->tintslot);
    m->dxr_h = c5x_dxr_head(m->dsp);
    c5x_set_io(m->dsp, machine_dsp_rd, machine_dsp_wr, m);
    c5x_set_cmpr_ar0(m->dsp, m->cmpr ? 1 : 0);
    c5x_set_xint_mode(m->dsp, m->xint_mode);
    c5x_set_cycle_model(m->dsp, m->cycle_model);
    c5x_set_legacy(m->dsp, m->legacy);
    c5x_reset(m->dsp, 0x8000);
    m->dsp_started_at = i186_cycles(m->cpu);
    m->next_samp = (int64_t)i186_cycles(m->cpu) + m->sample_cyc;
    i186_stop(m->cpu);
}

size_t machine_take_tx(Machine *m, int32_t *out, size_t maxout)
{
    /* Return the DSP output samples (signed 16-bit) produced since the
     * last call. The DXR ring only holds 65536 samples, so machine_run
     * calls this after every slice (see machine_run). */
    if (!m->dsp)
        return 0;
    uint32_t h = c5x_dxr_head(m->dsp);
    uint16_t *ring = c5x_dxr_ring(m->dsp);
    uint32_t n = h - m->tx_seen;
    if (n > 65536)
        n = 65536;
    size_t got = 0;
    for (uint32_t i = 0; i < n; i++) {
        uint16_t v = ring[(h - n + i) & 0xFFFF];
        int32_t s = v > 32767 ? (int32_t)v - 65536 : (int32_t)v;
        if (got < maxout)
            out[got] = s;
        got++;
        PUSH(m->tx_all, m->tx_all_n, m->tx_all_cap, int32_t, s);
    }
    m->tx_seen = h;
    if (!m->ac01_model)
        return got;
    /* TLC320AC01 DAC: a primary word with D1 D0 = 11 is followed by a
     * secondary control frame (the DAC holds its last value); the
     * 14-bit DAC ignores the two control LSBs; analog output gain
     * from register 4. Rewrites tx_all in place, as in machine.py. */
    double g = aic_gain_out(m);
    size_t w = 0; /* write index into tx_all for the filtered tail */
    size_t base = m->tx_all_n - got;
    int tx_req = m->tx_req;
    int32_t tx_hold = m->tx_hold;
    for (size_t j = 0; j < got; j++) {
        int32_t v = m->tx_all[base + j];
        uint32_t idx = h - (uint32_t)n + (uint32_t)j;
        if (m->sec_frame && u32set_has(&m->sec_abs, idx)) {
            u32set_del(&m->sec_abs, idx);
            continue; /* secondary control word: no DAC sample */
        }
        if (!m->sec_frame && tx_req) {
            tx_req = 0;
            m->tx_all[base + w++] = (int32_t)(tx_hold * g);
            continue;
        }
        if (!m->sec_frame && (v & 3) == 3)
            tx_req = 1;
        /* Signed, as in Python: v & ~3 keeps the sign (e.g. -1 -> -4). */
        tx_hold = v & ~3;
        m->tx_all[base + w++] = (int32_t)(tx_hold * g);
    }
    m->tx_req = tx_req;
    m->tx_hold = tx_hold;
    m->tx_all_n = base + w;
    if (m->ac01_filt) {
        /* DAC reconstruction low-pass (corner FCLK/40 = fs*B/40). */
        lp6_set(&m->dac_lp, m->rate * (m->aic[2] ? m->aic[2] : 18) / 40.0, m->rate);
        for (size_t j = base; j < m->tx_all_n; j++) {
            double y = lp6_call(&m->dac_lp, (double)m->tx_all[j]);
            m->tx_all[j] = clamp16((int)lround(y));
        }
    }
    /* out[] was filled with pre-filter values; refill from tx_all. */
    size_t outn = m->tx_all_n - base;
    if (outn > maxout)
        outn = maxout;
    for (size_t j = 0; j < outn; j++)
        out[j] = m->tx_all[base + j];
    return outn;
}

/* ---- PCB (machine.py _preg / _pwr) ---- */
static void timer_run(Machine *m, int i)
{
    MachineTimer *T = &m->tm[i];
    T->run = (T->con & 0x8000) && (i != 1 || m->line == 0);
}

static void timer_sched(Machine *m, int i)
{
    MachineTimer *T = &m->tm[i];
    if (!T->run) { T->nxt = MACHINE_INF; return; }
    int64_t lim = T->cmpa ? T->cmpa : 0x10000;
    if ((int64_t)T->cnt >= lim) lim = 0x10000;
    T->nxt = T->last + (lim - (int64_t)T->cnt) * 4;
}

static void timer_update(Machine *m, int i, int64_t t)
{
    MachineTimer *T = &m->tm[i];
    if (!T->run) { T->last = t; return; }
    int64_t n = (t - T->last) / 4;
    if (n <= 0) return;
    T->last += n * 4;
    while (n) {
        int64_t lim = T->cmpa ? T->cmpa : 0x10000;
        int hit = 1;
        if ((int64_t)T->cnt >= lim) { lim = 0x10000; hit = 0; }
        int64_t d = lim - (int64_t)T->cnt;
        if (n < d) { T->cnt += (uint32_t)n; break; }
        n -= d; T->cnt = 0;
        if (hit) {
            T->con |= 0x20; /* MC */
            if (T->con & 0x2000) m->req |= (uint16_t)(1 << i);
            if (i == 0) m->req |= (uint16_t)(1 << S_INT3);
            if (!(T->con & 1)) {
                T->con &= ~0x8000u; T->run = 0; T->last = t;
                break; /* one-shot: EN clears */
            }
        }
    }
    timer_sched(m, i);
}

static uint16_t preg(Machine *m, uint16_t r, int64_t now, int rd)
{
    if (r >= 0x30 && r <= 0x46) {
        int i = (r - 0x30) >> 3, k = r & 6;
        MachineTimer *T = &m->tm[i];
        timer_update(m, i, now);
        switch (k >> 1) {
        case 0: return (uint16_t)T->cnt;
        case 1: return (uint16_t)T->cmpa;
        case 2: return (uint16_t)T->cmpb;
        default: return (uint16_t)T->con;
        }
    }
    if (r >= 0x60 && r <= 0x7A) {
        int j = (r >> 4) - 6, k = r & 0x0E;
        MachineUart *u = &m->uart[j];
        if (k == 6) {
            uint32_t v = u->sts;
            if (rd) {
                u->sts &= ~0xF4u; /* reading SxSTS clears RB8, RI, TI, FE, OE */
                if (j == 1 && (v & 0x60)) i186_stop(m->cpu); /* INT4 level drops */
            }
            return (uint16_t)v;
        }
        if (k <= 0x0A) {
            switch (k >> 1) {
            case 0: return (uint16_t)u->cmp;
            case 1: return 0;
            case 2: return (uint16_t)u->con;
            case 3: return 0;
            case 4: return (uint16_t)u->rbuf;
            default: return 0;
            }
        }
        return 0;
    }
    if (con_bit(r)) return (uint16_t)(m->icon[r] | (m->msk & con_bit(r) ? 8 : 0));
    if (r == 0x08) return (uint16_t)m->msk;
    if (r == 0x0A) return (uint16_t)m->primsk;
    if (r == 0x0C) {
        /* _sync_ack side effect, then sum of in-service levels. */
        machine_sync_ack(m);
        int s = 0;
        for (int b = 0; b < 256; b++)
            if (m->isv_present[b]) s += m->isv_val[b];
        return (uint16_t)s;
    }
    if (r == 0x0E) {
        uint16_t q = machine_requests(m);
        int s = 0;
        for (int i = 0; i < SRC_N; i++)
            if ((q >> i) & 1 && i != S_T1 && i != S_T2 && i != S_S0TX)
                s += SRC[i].bit;
        if (q & 7) s |= 1;
        if (q & 0x18) s |= 4;
        return (uint16_t)s;
    }
    if (r == 0x10) return (uint16_t)(m->req & 7);
    if (r == 0x5A) {
        int v = (m->p2pin & ~0x20) | (m->line ? 0x20 : 0);
        v &= ~0x80;
        if (m->pcb[0x58] & 0x80)
            v |= m->eeprom.do_bit ? 0x80 : 0;
        else
            v |= m->pcb[0x5E] & 0x80;
        return (uint16_t)v;
    }
    return (uint16_t)(m->pcb[r] | (m->pcb[r + 1] << 8));
}

static void pwr(Machine *m, uint16_t r, uint16_t v, int64_t now)
{
    uint16_t old = m->pcb[r];
    m->pcb[r] = (uint8_t)(v & 0xFF);
    m->pcb[r + 1] = (uint8_t)(v >> 8);
    if (r == 0x56) {
        /* P1LTCH: EEPROM chip select (bit5) and clock (bit2). */
        int cs0 = old & 0x20, cs1 = v & 0x20;
        if (cs1 && !cs0) { m->eeprom.state = EE_IDLE; m->eeprom.do_bit = 1; }
        else if (cs0 && !cs1) { m->eeprom.state = EE_IDLE; m->eeprom.do_bit = 1; }
        if (cs1 && (v & 4) && !(old & 4))
            eeprom_clock(&m->eeprom, (m->pcb[0x5E] >> 7) & 1);
    }
    if (r >= 0x30 && r <= 0x46) {
        int i = (r - 0x30) >> 3, k = r & 6;
        MachineTimer *T = &m->tm[i];
        timer_update(m, i, now);
        if (k == 0) T->cnt = v;
        else if (k == 2) T->cmpa = v;
        else if (k == 4) T->cmpb = v;
        else {
            uint32_t en = (v & 0x4000) ? (v & 0x8000) : (T->con & 0x8000);
            T->con = (v & 0x3FFF) | en;
        }
        timer_run(m, i); T->last = now; timer_sched(m, i);
        i186_stop(m->cpu);
    } else if (r >= 0x60 && r <= 0x7A) {
        int j = (r >> 4) - 6, k = r & 0x0E;
        MachineUart *u = &m->uart[j];
        if (k == 0) { u->cmp = v; u->pu = 8 * ((v & 0x7FFF) + 1); }
        else if (k == 4) {
            u->con = v;
            if (!(v & 0x20)) u->rx_t = MACHINE_INF; /* REN off aborts reception */
        } else if (k == 0x0A) {
            PUSH(m->dte_out, m->dte_out_n, m->dte_out_cap, uint8_t, (uint8_t)(v & 0xFF));
            u->sts &= ~0x08u; /* TXE low while the character shifts out */
            u->tx_t = (u->tx_t == MACHINE_INF ? now : u->tx_t) + 10LL * u->pu;
            i186_stop(m->cpu);
        }
    } else if (con_bit(r)) {
        m->icon[r] = v & 0x77;
        if (v & 8) m->msk |= (uint32_t)con_bit(r);
        else m->msk &= ~(uint32_t)con_bit(r);
        i186_stop(m->cpu);
    } else if (r == 0x08) {
        m->msk = v & 0xFD; i186_stop(m->cpu);
    } else if (r == 0x0A) {
        m->primsk = v & 7; i186_stop(m->cpu);
    } else if (r == 0x02) {
        machine_eoi(m, v);
        i186_stop(m->cpu);
    } else if (r == 0xA8) {
        m->pcb_mem = (v & 0x1000) != 0; /* RELREG */
    }
}

/* ---- interrupt controller (machine.py _sync_ack/_requests/_icu_eval/_eoi) ---- */
void machine_sync_ack(Machine *m)
{
    if (m->offered >= 0 && !i186_irq_pending(m->cpu)) {
        int o = m->offered;
        m->offered = -1;
        m->req &= (uint16_t)~(1 << o);
        m->isv_present[SRC[o].bit] = 1;
        m->isv_val[SRC[o].bit] = m->icon[SRC[o].con] & 7;
        m->irq_count[SRC[o].vec]++;
    }
}

uint16_t machine_requests(Machine *m)
{
    return (uint16_t)(m->req | ((m->uart[1].sts & 0x60) ? (1 << S_INT4) : 0));
}

void machine_eoi(Machine *m, uint32_t v)
{
    machine_sync_ack(m);
    if (v & 0x8000) {
        /* Non-specific: highest priority in service. */
        int lo = 8, found = 0;
        for (int b = 0; b < 256; b++)
            if (m->isv_present[b] && (!found || m->isv_val[b] < lo)) {
                lo = m->isv_val[b]; found = 1;
            }
        if (found) {
            static const int order[7] = { 0x01, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80 };
            for (int i = 0; i < 7; i++)
                if (m->isv_present[order[i]] && m->isv_val[order[i]] == lo) {
                    m->isv_present[order[i]] = 0;
                    break;
                }
        }
    } else {
        int b = eoi_bit((int)(v & 0x1F));
        if (b) m->isv_present[b] = 0;
    }
}

static void icu_eval(Machine *m)
{
    machine_sync_ack(m);
    uint16_t r = machine_requests(m);
    int best = -1;
    if (r) {
        int bp = 8;
        for (int b = 0; b < 256; b++)
            if (m->isv_present[b] && m->isv_val[b] < bp) bp = m->isv_val[b];
        if (m->primsk + 1 < bp) bp = m->primsk + 1;
        for (int i = 0; i < SRC_N; i++) {
            if ((r >> i) & 1) {
                if (m->msk & SRC[i].bit) continue;
                int p = m->icon[SRC[i].con] & 7;
                if (p < bp) { best = i; bp = p; }
            }
        }
    }
    if (best != m->offered) {
        if (m->offered >= 0) i186_irq_clear(m->cpu);
        if (best >= 0) i186_irq(m->cpu, SRC[best].vec);
        m->offered = best;
    }
}

const char *machine_icu_state(Machine *m, char *buf, size_t len)
{
    char reqs[256] = "";
    static const char *names[SRC_N] = { "T0", "T1", "T2", "S0RX", "S0TX",
        "INT4", "INT0", "INT1", "INT2", "INT3" };
    uint16_t q = machine_requests(m);
    for (int i = 0; i < SRC_N; i++)
        if ((q >> i) & 1) {
            strncat(reqs, names[i], sizeof reqs - strlen(reqs) - 1);
            strncat(reqs, " ", sizeof reqs - strlen(reqs) - 1);
        }
    snprintf(buf, len, "req=%s msk=%02X primsk=%d offered=%s",
             reqs, (unsigned)m->msk, m->primsk,
             m->offered >= 0 ? names[m->offered] : "(none)");
    return buf;
}

/* ---- I/O ports (machine.py iord / iowr) ---- */
static uint32_t machine_iord(void *ctx, uint16_t p, int w)
{
    Machine *m = ctx;
    if (m->logging && m->log_n < LOG_CAP) {
        IoLogEnt e = { 'R', p, w, 0, machine_phys_pc(m) };
        PUSH(m->log, m->log_n, m->log_cap, IoLogEnt, e);
    }
    if (p >= 0xFF00 && !m->pcb_mem) {
        uint16_t v = preg(m, (uint16_t)(p & 0xFE), (int64_t)i186_cycles(m->cpu), 1);
        return w ? v : ((p & 1) ? (v >> 8) & 0xFF : v & 0xFF);
    }
    if (p == 0x00) return m->ports[0] & ~0x08u;
    if (p == 0x18 && !m->dsp) return 0x03;
    if (m->iface403 && p == 0x1C && m->dsp)
        return 0xFCu | (m->h2d_pending ? 0 : 1) | ((m->d2h_valid ? 1 : 0) << 1);
    if (m->iface403 && p == 0x1E && m->dsp)
        return m->ovl_status ? (0xF8u | (uint32_t)m->ovl_status) : 0xFF;
    if (p == 0x1C || p == 0x1E)
        return p == 0x1C ? (uint32_t)(m->evt & 0xFF)
                         : (uint32_t)(m->dsp ? m->ovl_status : 0);
    if (p >= 0x40 && p <= 0x5E && (p % 2) == 0 && m->dsp) {
        int idx = (p - 0x40) / 4, hi = ((p - 0x40) / 2) % 2;
        uint16_t wv = m->d2h[idx]; /* d2h[0] = word 0x58 */
        if (p == 0x58 && !m->iface403) m->d2h_valid = 0;
        return hi ? (wv >> 8) & 0xFF : wv & 0xFF;
    }
    if ((p == 0x18 || p == 0x1A) && m->dsp)
        return (m->flags56 >> (p == 0x1A ? 8 : 0)) & 0xFF;
    if ((p == 0x60 || p == 0x62) && m->dsp) {
        if (p == 0x60) { m->data_full = 0; m->data_words_read++; }
        return p == 0x62 ? (m->data_word >> 8) & 0xFF : m->data_word & 0xFF;
    }
    if (p == 0x14) {
        int v = m->port_in[0x14] | 0x02;
        v = (v & ~0x08) | (machine_hw_id_bit(m) ? 0x08 : 0);
        if (m->ring_on && ((((uint64_t)m->hb_count / (uint64_t)m->hb_ticks) / 60) & 1))
            v &= ~0x02;
        return (uint32_t)v;
    }
    if (p == 0x10 || p == 0x12 || p == 0x14) return m->port_in[p];
    return m->ports[p];
}

static void machine_iowr(void *ctx, uint16_t p, int w, uint32_t v)
{
    Machine *m = ctx;
    if (m->logging && m->log_n < LOG_CAP) {
        IoLogEnt e = { 'W', p, w, v, machine_phys_pc(m) };
        PUSH(m->log, m->log_n, m->log_cap, IoLogEnt, e);
    }
    if (p >= 0xFF00 && !m->pcb_mem) {
        int64_t now = (int64_t)i186_cycles(m->cpu);
        uint16_t r = (uint16_t)(p & 0xFE);
        uint32_t vv = v;
        if (!w) {
            uint16_t old = preg(m, r, now, 0);
            vv = (p & 1) ? (uint32_t)((old & 0x00FF) | ((v & 0xFF) << 8))
                         : (uint32_t)((old & 0xFF00) | (v & 0xFF));
        }
        pwr(m, r, (uint16_t)(vv & 0xFFFF), now);
        return;
    }
    m->ports[p] = v;
    m->ports_set[p] = 1;
    if (p == 0x0A)
        PUSH(m->dte_out, m->dte_out_n, m->dte_out_cap, uint8_t, (uint8_t)(v & 0xFF));
    if ((p == 0x18 || p == 0x1A) && m->dsp) {
        int sh = p == 0x1A ? 8 : 0;
        m->flags56 &= (uint16_t)(~((v & 0xFF) << sh) & 0xFFFF);
        m->flagsD |= (uint16_t)((v & 0xFF) << sh);
        if (m->flag_log_n < 400) {
            FlagLogEnt e = { round((double)i186_cycles(m->cpu) / (double)m->cpu_hz * 100.0) / 100.0,
                             (int)p, (int)(v & 0xFF), m->flags56 };
            m->flag_log[m->flag_log_n++] = e;
        }
    }
    if (p == 0x18 && (v & 0xFF) == 4 && !m->dsp)
        machine_start_dsp(m);
    if (m->iface403 && p == 0x1C && m->dsp) {
        if (v & 2) m->d2h_valid = 0;
    } else if (p == 0x1C && m->dsp) {
        m->evt &= (uint8_t)~(v & 0xFF);
        m->evt_seen &= m->evt;
    }
    if (p == 0x1E && m->dsp)
        ovl_host_ack(m, v & 0xFF);
    if (m->dsp && p >= 0x40 && p <= 0x4E && (p % 2) == 0)
        m->ovl_bytes[p] = (uint8_t)(v & 0xFF);
    if (m->dsp && p >= 0x40 && p <= 0x5E && (p % 2) == 0) {
        int idx = (p - 0x40) / 4, hi = ((p - 0x40) / 2) % 2;
        int widx = idx; /* h2d[0] = word 0x58 */
        if (hi) m->h2d[widx] = (uint16_t)((m->h2d[widx] & 0x00FF) | ((v & 0xFF) << 8));
        else m->h2d[widx] = (uint16_t)((m->h2d[widx] & 0xFF00) | (v & 0xFF));
        if (p == 0x5E) {
            if (m->cmd_ovr[0]) cmd_override(m);
            m->h2d_pending = 1;
            if (m->int23) c5x_irq(m->dsp, GLUE_C5X_INT2);
        }
    }
    if (p >= 0x40 && p <= 0x5E && (p % 2) == 0 && !m->dsp) {
        m->burst_tmp[p] = (uint8_t)(v & 0xFF);
        if (p == 0x4E || p == 0x5E) {
            int base = p == 0x4E ? 0x40 : 0x50;
            while ((m->dsp_bursts_n + 1) * 8 > m->dsp_bursts_cap) {
                size_t nc = m->dsp_bursts_cap ? m->dsp_bursts_cap * 2 : 1024;
                uint8_t *na = realloc(m->dsp_bursts, nc);
                if (!na) abort();
                m->dsp_bursts = na; m->dsp_bursts_cap = nc;
            }
            for (int q = 0; q < 8; q++)
                m->dsp_bursts[m->dsp_bursts_n * 8 + q] = m->burst_tmp[base + 2 * q];
            m->dsp_bursts_n++;
            memset(m->burst_tmp, 0, sizeof m->burst_tmp);
        }
    }
}

/* ---- DSP I/O (machine.py dsp_rd / dsp_wr) ---- */
static uint16_t machine_dsp_rd(void *ctx, uint16_t p)
{
    Machine *m = ctx;
    int q = p & 0xFF;
    if (q == 0x57)
        return (uint16_t)(m->h2d_pending | ((m->d2h_valid ? 0 : 1) << 1) |
                          (m->data_full ? 0 : 4));
    if (q >= 0x50 && q <= 0x5F && m->dsp) {
        uint64_t key = ((uint64_t)(uint32_t)q << 32) | c5x_get(m->dsp, GLUE_C5X_PC);
        counter_inc(&m->rd_pcs, key);
    }
    if (q == 0x51 && m->p51div)
        return (uint16_t)(((c5x_total_cycles(m->dsp) - m->tick_dc) / (uint64_t)m->p51div) & 0xFFFF);
    if (q == 0x56) return m->flagsD;
    if (q >= 0x58 && q <= 0x5F) return m->h2d[q - 0x58];
    return m->port_rb ? m->port_store[q] : 0;
}

static void machine_dsp_wr(void *ctx, uint16_t p, uint16_t v)
{
    Machine *m = ctx;
    int q = p & 0xFF;
    if (m->dsp_log_n < DSP_LOG_CAP) {
        DspLogEnt e = { i186_cycles(m->cpu), (uint16_t)q, v };
        PUSH(m->dsp_log, m->dsp_log_n, m->dsp_log_cap, DspLogEnt, e);
    }
    if (!(q >= 0x56 && q <= 0x5F)) m->port_store[q] = v & 0xFFFF;
    counter_inc(&m->wr_pcs, ((uint64_t)(uint32_t)q << 32) | c5x_get(m->dsp, GLUE_C5X_PC));
    if (q == 0x6B && m->ac01_model) { m->mclk_n = v & 0xFFFF; aic_update(m); }
    if (q == 0x56) {
        m->flagsD &= (uint16_t)~v;
        m->flags56 |= v;
    }
    if (q >= 0x58 && q <= 0x5D && m->bankwr) m->d2h[q - 0x58] = v & 0xFFFF;
    if (q == 0x60) {
        m->data_word = v & 0xFFFF; m->data_full = 1; m->data_words_sent++;
    }
    if (q == 0x5E || q == 0x5F) {
        uint64_t key = ((uint64_t)c5x_get(m->dsp, GLUE_C5X_PC) << 32) |
                       ((uint64_t)(uint32_t)q << 16) | v;
        counter_inc(&m->port5_pcs, key);
    }
    if (q == 0x57 && (v & 4)) {
        m->evt |= 4; m->evt_seen &= ~4; m->int0_req = 1; m->evt4_n++;
    }
    if (q == 0x57 && ((v >> 8) & 7)) m->ovl_status = (v >> 8) & 7;
    if (q == 0x57 && (v & 1)) {
        m->h2d_pending = 0;
        if (!m->iface403) { m->evt |= 1; m->int0_req = 1; }
        int cmd = m->h2d[0x5E - 0x58] & 0xFF, arg = m->h2d[0x5F - 0x58] & 0xFF;
        if (cmd == 0x02) {
            m->ovl_addr = m->h2d[0x5F - 0x58] & 0xFFFF;
            m->ovl_data_n = 0;
        }
        CmdEnt ce = { i186_cycles(m->cpu), cmd, arg };
        PUSH(m->cmd_log, m->cmd_log_n, m->cmd_log_cap, CmdEnt, ce);
        mtrace(m, "host->DSP cmd %02X arg %02X        %s", cmd, arg,
               dsp_cmd_note(cmd, arg));
        uint32_t pending = c5x_dxr_head(m->dsp) - m->tx_seen;
        Cmd16Ent c16 = { (int64_t)m->tx_all_n + (int64_t)pending,
                         m->h2d[0x5E - 0x58], m->h2d[0x5F - 0x58] };
        PUSH(m->cmd_log16, m->cmd_log16_n, m->cmd_log16_cap, Cmd16Ent, c16);
        if (cmd == 0x01 && arg == 0x3F && m->rom_replies) {
            m->d2h[0x5E - 0x58] = 0x0084; m->d2h[0x5F - 0x58] = 0;
            m->d2h_valid = 1; m->evt |= 2; m->int0_req = 1;
        }
    }
    if (q >= 0x58 && q <= 0x5F) {
        uint16_t pc = (uint16_t)c5x_get(m->dsp, GLUE_C5X_PC);
        int sender = m->sender_mode ? m->sender_pcs[pc]
                                    : (pc >= 0x83D6 && pc <= 0x8420);
        if (sender) {
            m->d2h[q - 0x58] = v & 0xFFFF;
            if (q == 0x5F) {
                m->d2h_valid = 1;
                m->evt |= m->iface403 ? 0 : 2;
                m->int0_req = m->iface403 ? 0 : 1;
                uint32_t pending = c5x_dxr_head(m->dsp) - m->tx_seen;
                MsgEnt me = { (int64_t)m->tx_all_n + (int64_t)pending,
                              m->d2h[0x5C - 0x58], m->d2h[0x5D - 0x58],
                              m->d2h[0x5E - 0x58], m->d2h[0x5F - 0x58],
                              i186_cycles(m->cpu) };
                PUSH(m->msg_log, m->msg_log_n, m->msg_log_cap, MsgEnt, me);
            }
        }
    }
}

/* ---- memory hooks (machine.py mmrd / mmwr) ---- */
static uint32_t machine_mmrd(void *ctx, uint32_t a, int w)
{
    Machine *m = ctx;
    if (m->pcb_mem && a >= 0x0FF00 && a <= 0x0FFFF) {
        uint16_t v = preg(m, (uint16_t)(a & 0xFE), (int64_t)i186_cycles(m->cpu), 1);
        if (!w) v = (uint16_t)((a & 1) ? (v >> 8) & 0xFF : v & 0xFF);
        if (m->logging && m->pcblog_n < LOG_CAP) {
            IoLogEnt e = { 'R', (uint16_t)(a & 0xFF), w, v, machine_phys_pc(m) };
            PUSH(m->pcblog, m->pcblog_n, m->pcblog_cap, IoLogEnt, e);
        }
        return v & 0xFFFF;
    }
    if (m->flash_id && a >= 0xFFFF0 && a <= 0xFFFF3) {
        uint32_t val = a < 0xFFFF2 ? 0x0089 : 0x4470;
        return w ? val : (val >> (8 * (a & 1))) & 0xFF;
    }
    uint8_t *mem = i186_mem(m->cpu);
    return (uint32_t)(mem[a & 0xFFFFF] | (w ? (mem[(a + 1) & 0xFFFFF] << 8) : 0));
}

static void machine_mmwr(void *ctx, uint32_t a, int w, uint32_t v)
{
    Machine *m = ctx;
    if (a >= 0xFFFF0 && a <= 0xFFFF1) {
        /* Flash command write (autoselect probe): 0x90 / 0xFF. */
        if ((v & 0xFF) == 0x90) m->flash_id = 1;
        else if ((v & 0xFF) == 0xFF) m->flash_id = 0;
        return;
    }
    if (m->pcb_mem && a >= 0x0FF00 && a <= 0x0FFFF) {
        if (m->logging && m->pcblog_n < LOG_CAP) {
            IoLogEnt e = { 'W', (uint16_t)(a & 0xFF), w, v, machine_phys_pc(m) };
            PUSH(m->pcblog, m->pcblog_n, m->pcblog_cap, IoLogEnt, e);
        }
        int64_t now = (int64_t)i186_cycles(m->cpu);
        uint16_t r = (uint16_t)(a & 0xFE);
        uint32_t vv = v;
        if (!w) {
            uint16_t old = preg(m, r, now, 0);
            vv = (a & 1) ? (uint32_t)((old & 0x00FF) | ((v & 0xFF) << 8))
                         : (uint32_t)((old & 0xFF00) | (v & 0xFF));
        }
        pwr(m, r, (uint16_t)(vv & 0xFFFF), now);
        return;
    }
    uint8_t *mem = i186_mem(m->cpu);
    mem[a & 0xFFFFF] = (uint8_t)(v & 0xFF);
    if (w) mem[(a + 1) & 0xFFFFF] = (uint8_t)((v >> 8) & 0xFF);
}

/* ---- DTE line and serial ports (machine.py _edge/_uart_rx/_line_feed) ---- */
static void line_edge(Machine *m, int64_t t, int lv)
{
    timer_update(m, 1, t);
    m->line = lv;
    timer_run(m, 1);
    m->tm[1].last = t;
    timer_sched(m, 1);
    if (lv) {
        m->req |= (uint16_t)(1 << S_INT1); /* rising edge of DTE TXD */
    } else {
        for (int j = 0; j < 2; j++) {
            MachineUart *u = &m->uart[j];
            if (u->rx_t == MACHINE_INF && (u->con & 0x20) && (u->con & 7)) {
                u->rx_t = t + u->pu / 2; u->bit = 0; u->sh = 0;
            }
        }
    }
}

static void uart_rx(Machine *m, int j, int64_t t)
{
    MachineUart *u = &m->uart[j];
    int lv = m->line;
    if (u->bit == 0) {
        if (lv) { u->rx_t = MACHINE_INF; return; } /* false start */
    } else if (u->bit <= 8) {
        u->sh |= lv << (u->bit - 1);
    } else {
        if (u->sts & 0x40) u->sts |= 0x04; /* OE */
        u->rbuf = (uint32_t)u->sh;
        u->sts |= 0x40 | (lv ? 0 : 0x10); /* RI, FE if the stop bit is 0 */
        u->rx_t = MACHINE_INF;
        if (j == 0) m->req |= (uint16_t)(1 << S_S0RX);
        return;
    }
    u->bit += 1;
    u->rx_t = t + u->pu;
}

static void line_feed(Machine *m, int64_t now)
{
    /* Start the next typed character: 8N1, LSB first. */
    uint8_t c = m->txq[m->txq_head++];
    m->txq_n--;
    if (m->txq_n == 0) m->txq_head = 0;
    double bl = (double)m->cpu_hz / (double)m->dte_baud;
    if (m->edges_head) {
        memmove(m->edges, m->edges + m->edges_head,
                m->edges_n * sizeof *m->edges);
        m->edges_head = 0;
    }
    int prev = 1;
    int levels[10] = { 0,
        (c >> 0) & 1, (c >> 1) & 1, (c >> 2) & 1, (c >> 3) & 1,
        (c >> 4) & 1, (c >> 5) & 1, (c >> 6) & 1, (c >> 7) & 1, 1 };
    for (int k = 0; k < 10; k++) {
        int lv = levels[k];
        if (lv != prev) {
            size_t n = m->edges_n;
            GROW(m->edges, n, m->edges_cap, __typeof__(*m->edges));
            /* edges is a queue with a head index; append at head+n. */
            m->edges[m->edges_head + m->edges_n].t = now + (int64_t)(k * bl + 0.5);
            m->edges[m->edges_head + m->edges_n].lv = lv;
            m->edges_n++;
            prev = lv;
        }
    }
    m->line_free = now + (int64_t)(10 * bl + 0.5) + m->dte_gap;
}

/* ---- one codec sample period (machine.py _sample) ---- */
static void machine_sample(Machine *m)
{
    if (m->sec_frame && m->ac01_model && m->aic_req) {
        /* A primary word with D1 D0 = 11 was just consumed: the AC01
         * clocks its secondary frame half a primary interval later; it
         * carries the control word, delivers no ADC word and no DAC
         * sample. */
        int64_t half = m->dsp_cps / 2;
        c5x_run(m->dsp, (uint64_t)half);
        uint32_t h = c5x_dxr_head(m->dsp);
        if (h != m->aic_h) {
            uint16_t *rg = c5x_dxr_ring(m->dsp);
            for (uint32_t i = m->aic_h; i < h; i++)
                u32set_add(&m->sec_abs, i);
            uint16_t words[64];
            int nw = 0;
            int64_t start64 = (int64_t)m->aic_h > (int64_t)h - 64
                ? (int64_t)m->aic_h : (int64_t)h - 64;
            if (start64 < 0) start64 = 0;
            for (uint32_t i = (uint32_t)start64; i < h && nw < 64; i++)
                words[nw++] = rg[i & 0xFFFF];
            aic_feed(m, words, nw);
            m->aic_h = h;
        }
        if (m->int23) c5x_irq(m->dsp, GLUE_C5X_INT3);
        c5x_serial_tick(m->dsp, 0); /* secondary DOUT: no conversion result */
        m->sec_n++;
        c5x_run(m->dsp, (uint64_t)(m->dsp_cps - half));
    } else {
        c5x_run(m->dsp, (uint64_t)m->dsp_cps);
    }
    uint32_t h = c5x_dxr_head(m->dsp);
    if (m->ac01_model && h != m->aic_h) {
        if (m->sec_frame && m->aic_req)
            u32set_add(&m->sec_abs, m->aic_h);
        uint16_t *rg = c5x_dxr_ring(m->dsp);
        uint16_t words[64];
        int nw = 0;
        int64_t start64 = (int64_t)m->aic_h > (int64_t)h - 64
            ? (int64_t)m->aic_h : (int64_t)h - 64;
        if (start64 < 0) start64 = 0;
        for (uint32_t i = (uint32_t)start64; i < h && nw < 64; i++)
            words[nw++] = rg[i & 0xFFFF];
        aic_feed(m, words, nw);
        m->aic_h = h;
    }
    if (h != m->dxr_h) {
        /* One new input sample consumed per output sample produced. */
        int cnt = 0;
        for (uint32_t i = m->dxr_h; i < h; i++)
            if (!u32set_has(&m->sec_abs, i)) cnt++;
        if (cnt > 8) cnt = 8;
        for (int k = 0; k < cnt; k++) {
            if (m->rxbuf_n) {
                m->cur_rx = m->rxbuf[m->rxbuf_head++];
                m->rxbuf_n--;
                if (m->rxbuf_n == 0) m->rxbuf_head = 0;
                if (m->rx_log_n < RX_LOG_CAP)
                    PUSH(m->rx_log, m->rx_log_n, m->rx_log_cap, int32_t, m->cur_rx);
            } else if (m->rx_gen) {
                m->cur_rx = (uint16_t)(m->rx_gen(m->rx_gen_ctx) & 0xFFFF);
            } else {
                m->cur_rx = 0; m->rx_under++;
            }
        }
        m->dxr_h = h;
    }
    int32_t base = m->cur_rx < 32768 ? (int32_t)m->cur_rx : (int32_t)m->cur_rx - 65536;
    if (m->noise_amp) {
        /* Line noise floor: the DSP's level estimator hangs on exact
         * digital silence. LCG, seed 12345. */
        m->seed = (m->seed * 1103515245u + 12345u) & 0x7FFFFFFFu;
        base += (int32_t)((m->seed >> 16) % (uint32_t)(2 * m->noise_amp + 1)) - m->noise_amp;
    }
    if (m->ac01_filt) {
        lp6_set(&m->adc_lp, m->rate * (m->aic[2] ? m->aic[2] : 18) / 40.0, (double)m->rate);
        double x = lp6_call(&m->adc_lp, (double)base);
        if (!((m->aic[5] >> 2) & 1)) {
            /* Single-pole high-pass, fs/200, unless register 5 DS02
             * disables it. */
            double k = 1.0 / (1.0 + 2 * M_PI * (m->rate / 200.0) / m->rate);
            double y = k * (m->adc_hp[0] + x - m->adc_hp[1]);
            m->adc_hp[0] = y; m->adc_hp[1] = x;
            x = y;
        }
        base = (int32_t)lround(x);
    }
    if (m->ac01_lat) {
        /* Extra ADC-side latency in codec samples. */
        if (!m->lat_q) {
            m->lat_q_cap = (size_t)m->ac01_lat + 1;
            m->lat_q = calloc(m->lat_q_cap, sizeof *m->lat_q);
            m->lat_q_n = (size_t)m->ac01_lat;
            m->lat_q_head = 0;
        }
        size_t cap = m->lat_q_cap;
        m->lat_q[(m->lat_q_head + m->lat_q_n) % cap] = base;
        m->lat_q_n++;
        base = m->lat_q[m->lat_q_head++];
        m->lat_q_head %= cap;
        m->lat_q_n--;
    }
    if (m->ac01_model)
        base = (int32_t)((int)(base * aic_gain_in(m)) & ~3);
    if (m->rx_trace)
        PUSH(m->rx_trace, m->rx_trace_n, m->rx_trace_cap, int32_t, base);
    c5x_serial_tick(m->dsp, (int16_t)clamp16(base));
    m->tick_dc = c5x_total_cycles(m->dsp);
    if (m->int23) c5x_irq(m->dsp, GLUE_C5X_INT3); /* AC01 FS -> DSP INT3, every frame */
    if (m->tdm_irqs) { c5x_irq(m->dsp, GLUE_C5X_TRNT); c5x_irq(m->dsp, GLUE_C5X_TXNT); }
    if (m->hb_timer) {
        uint64_t e = c5x_timer_expiries(m->dsp);
        uint64_t n = e - m->hb_e;
        m->hb_e = e;
        m->hb_count += (long)n;
        if (m->heartbeat && n) m->hb_pending = 1;
    } else {
        m->hb_count++;
        if (m->heartbeat && m->hb_count % m->hb_ticks == 0) m->hb_pending = 1;
    }
}

static void machine_service(Machine *m, int64_t now)
{
    /* Line edges and receiver sample points, in time order. */
    while (1) {
        int64_t t = m->edges_n ? m->edges[m->edges_head].t : MACHINE_INF;
        int k = 0;
        if (m->uart[0].rx_t < t) { t = m->uart[0].rx_t; k = 1; }
        if (m->uart[1].rx_t < t) { t = m->uart[1].rx_t; k = 2; }
        if (t > now) break;
        if (k == 0) {
            int64_t et = m->edges[m->edges_head].t;
            int lv = m->edges[m->edges_head].lv;
            m->edges_head++;
            m->edges_n--;
            if (m->edges_n == 0) m->edges_head = 0;
            line_edge(m, et, lv);
        } else {
            uart_rx(m, k - 1, t);
        }
    }
    if (m->txq_n && !m->edges_n && now >= m->line_free)
        line_feed(m, now);
    for (int j = 0; j < 2; j++) {
        MachineUart *u = &m->uart[j];
        if (u->tx_t <= now) {
            u->tx_t = MACHINE_INF;
            u->sts |= 0x28; /* TXE, TI */
            if (j == 0) m->req |= (uint16_t)(1 << S_S0TX);
        }
    }
    if (m->tm[0].nxt <= now) timer_update(m, 0, now);
    if (m->tm[1].nxt <= now) timer_update(m, 1, now);
    if (m->tm[2].nxt <= now) timer_update(m, 2, now);
    if (now >= m->next_samp) {
        while (now >= m->next_samp) {
            machine_sample(m);
            m->next_samp += m->sample_cyc;
        }
        if (!m->iface403 && !m->h2d_pending &&
            machine_rd16(m, 0x29A) != machine_rd16(m, 0x29C)) {
            /* SV25 supervisor's ring pointers; on the 403 supervisor
             * INT0 is the free-running heartbeat only. HLE stand-in:
             * TX slot free and the supervisor has queued words. */
            m->evt |= 1;
            m->evt_seen &= (uint8_t)~1;
        }
        if (m->hb_pending || (!m->iface403 && (m->evt & ~m->evt_seen))) {
            int v32 = machine_rd16(m, 0x32), v30 = machine_rd16(m, 0x30);
            int unset = 0;
            for (int i = 0; i < m->prof->int0_unset_n; i++)
                if (v32 == m->prof->int0_unset[i][0] && v30 == m->prof->int0_unset[i][1])
                    unset = 1;
            if (!unset) {
                m->req |= (uint16_t)(1 << S_INT0);
                m->hb_pending = 0;
                m->evt_seen |= (uint8_t)m->evt;
            }
        }
    }
}

static int64_t machine_next_event(Machine *m)
{
    int64_t t = m->next_samp;
    for (int i = 0; i < 3; i++)
        if (m->tm[i].nxt < t) t = m->tm[i].nxt;
    if (m->uart[0].rx_t < t) t = m->uart[0].rx_t;
    if (m->uart[1].rx_t < t) t = m->uart[1].rx_t;
    if (m->uart[0].tx_t < t) t = m->uart[0].tx_t;
    if (m->uart[1].tx_t < t) t = m->uart[1].tx_t;
    if (m->edges_n) {
        if (m->edges[m->edges_head].t < t) t = m->edges[m->edges_head].t;
    } else if (m->txq_n && m->line_free < t) {
        t = m->line_free;
    }
    return t;
}

int machine_run(Machine *m, uint64_t cycles)
{
    uint64_t end = i186_cycles(m->cpu) + cycles;
    int r = GLUE_I186_ST_OK;
    while (1) {
        int64_t now = (int64_t)i186_cycles(m->cpu);
        if (now >= (int64_t)end) break;
        machine_service(m, now);
        icu_eval(m);
        int64_t ne = machine_next_event(m);
        int64_t target = (int64_t)end < ne ? (int64_t)end : ne;
        int64_t b = target - now;
        r = i186_run(m->cpu, (uint64_t)(b > 0 ? b : 1));
        machine_sync_ack(m);
        if (r == GLUE_I186_ST_BP) {
            uint32_t pc = machine_phys_pc(m);
            if (pc == 0x9EB96 && m->fax_patch) {
                machine_wr8(m, 0xEA7, (uint8_t)(machine_rd8(m, 0xEA7) | 1));
                machine_wr8(m, 0x3FBA, (uint8_t)m->dte_speed_code);
                continue;
            }
            if (!m->nvram_done && pc == 0x8063E && m->nvram_mode >= 0) {
                machine_wr8(m, 0x5F1, (uint8_t)m->nvram_mode);
                i186_set_bp(m->cpu, 0x8063E, 0);
                m->nvram_done = 1;
                continue;
            }
            break;
        }
        if (r != GLUE_I186_ST_OK && r != GLUE_I186_ST_HLT && r != GLUE_I186_ST_STOP)
            break;
    }
    /* Keep tx_all complete (the DSP output ring only holds 65536
     * samples): machine.py run() does take_tx() in a finally. */
    int32_t sink[4096];
    (void)machine_take_tx(m, sink, sizeof sink / sizeof *sink);
    return r;
}
