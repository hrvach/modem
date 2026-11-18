/* One modem, on its own, for a separate wasm instance: no link, no shared
 * clock. The line (in JavaScript) moves audio between two of these, and
 * decides call progress (ring, answer). Pacing against the wall clock is
 * done by the caller through modem_cycles() and modem_run(). */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "config.h"
#include "machine.h"

static Machine *M;
static Config cfg;

/* Load the config file and build the machine. Returns 0 on success. */
int modem_create(const char *cfg_path)
{
    char err[256];
    if (config_load(&cfg, cfg_path, err, sizeof err) != 0)
        return -1;
    cfg.nvram_mode = -1;          /* a line modem: no NVRAM hook */
    M = machine_new(&cfg);
    if (!M)
        return -2;
    M->logging = 0;
    M->tag = 'M';
    return 0;
}

/* Send bytes to the modem's serial (host) input. */
void modem_send(const char *s)
{
    machine_send_str(M, s);
}

/* ---- Constellation scope --------------------------------------------------
 * Two cells of the DSP's data memory hold the point the data pump is working
 * on (found by tracing: DM 0x0224 and 0x0228 take one new value each symbol;
 * together they fill a regular grid like the V.34 constellation). They change
 * at the symbol rate, much faster than the page polls, so the modem is run in
 * slices of about one codec sample and the pair is read after each slice;
 * every change goes into a small ring that the page drains. */
#define SCOPE_MAX 4096
static int scope_x = -1, scope_y = -1;
static int16_t scope_pts[2 * SCOPE_MAX];
static int scope_n;
static uint16_t scope_lx, scope_ly;

void modem_scope_set(int ax, int ay)
{
    scope_n = 0;
    if (ax < 0 || ay < 0 || ax >= 0xC00 || ay >= 0xC00) {   /* on-chip RAM only */
        scope_x = scope_y = -1;
        return;
    }
    scope_x = ax;
    scope_y = ay;
}

static void scope_sample(void)
{
    const uint16_t *d = c5x_dmem(M->dsp);
    uint16_t x = d[scope_x], y = d[scope_y];
    if ((x != scope_lx || y != scope_ly) && scope_n < SCOPE_MAX) {
        scope_pts[2 * scope_n] = (int16_t)x;
        scope_pts[2 * scope_n + 1] = (int16_t)y;
        scope_n++;
    }
    scope_lx = x;
    scope_ly = y;
}

/* Copy out up to `max` points (x, y pairs); returns how many. */
int modem_scope_pull(int16_t *out, int max)
{
    int n = scope_n < max ? scope_n : max;
    memcpy(out, scope_pts, (size_t)n * 2 * sizeof *out);
    memmove(scope_pts, scope_pts + 2 * n, (size_t)(scope_n - n) * 2 * sizeof *scope_pts);
    scope_n -= n;
    return n;
}

/* Run the modem for `cycles` CPU cycles. Returns the machine status. */
int modem_run(double cycles)
{
    if (scope_x < 0 || !M->dsp)
        return machine_run(M, (uint64_t)cycles);
    uint64_t left = (uint64_t)cycles;
    uint64_t slice = (uint64_t)((double)M->cpu_hz / (double)(M->rate > 0 ? M->rate : 7200) * 0.9);
    if (slice < 200)
        slice = 200;
    int st = 0;
    while (left > 0) {
        uint64_t s = left < slice ? left : slice;
        st = machine_run(M, s);
        left -= s;
        scope_sample();
    }
    return st;
}

/* Simulated CPU cycles so far, for wall-clock pacing. */
double modem_cycles(void)
{
    return (double)i186_cycles(M->cpu);
}

uint32_t modem_cpu_hz(void)
{
    return (uint32_t)M->cpu_hz;
}

int modem_rate(void)
{
    return M->rate;
}

/* Audio from the line into the modem's receive buffer. */
size_t modem_push_rx(const int32_t *xs, size_t n)
{
    if (n == 0)
        return 0;
    if (M->rxbuf_head) {
        memmove(M->rxbuf, M->rxbuf + M->rxbuf_head,
                M->rxbuf_n * sizeof *M->rxbuf);
        M->rxbuf_head = 0;
    }
    while (M->rxbuf_n + n > M->rxbuf_cap) {
        size_t nc = M->rxbuf_cap ? M->rxbuf_cap * 2 : 1024;
        uint16_t *na = realloc(M->rxbuf, nc * sizeof *na);
        if (!na)
            abort();
        M->rxbuf = na;
        M->rxbuf_cap = nc;
    }
    for (size_t i = 0; i < n; i++)
        M->rxbuf[M->rxbuf_n++] = (uint16_t)(xs[i] & 0xFFFF);
    return n;
}

/* The modem's transmitted audio that has not been pulled yet. */
size_t modem_pull_tx(int32_t *out, size_t max)
{
    size_t n = M->tx_all_n - M->lk_seen;
    if (n > max)
        n = max;
    memcpy(out, M->tx_all + M->lk_seen, n * sizeof *out);
    M->lk_seen += n;
    return n;
}

/* Text the modem printed to its serial output (0xFF bytes dropped). */
size_t modem_dte(uint8_t *out, size_t max)
{
    return machine_dte_text(M, out, max);
}

/* Ring voltage on this modem's line. */
void modem_set_ring(int on)
{
    M->ring_on = on ? 1 : 0;
}

/* Received audio waiting to be heard, in samples at the codec rate. */
size_t modem_rx_level(void)
{
    return M->rxbuf_n - M->rxbuf_head;
}

/* Last value the CPU wrote to an I/O port (the board latches), or -1 if it
 * has never written it. Used by the front-panel driver. */
int modem_port(int port)
{
    if (port < 0 || port > 0xFFFF)
        return -1;
    return M->ports_set[port] ? (int)(M->ports[port] & 0xFF) : -1;
}
