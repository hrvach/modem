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

/* Run the modem for `cycles` CPU cycles. Returns the machine status. */
int modem_run(double cycles)
{
    return machine_run(M, (uint64_t)cycles);
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
