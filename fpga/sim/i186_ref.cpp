// i186_ref.cpp -- C reference-model wrapper for the 80C186EB co-sim.
// FPGA-only: Verilator co-sim harness, not synthesizable RTL.
// Machine-lite glue: reproduces glue/machine.c semantics for the
// subset the co-sim exercises (see i186_ref.h). The DSP is absent;
// DTE input is empty. All behaviour below is copied from machine.c
// (same function names where practical); deviations are marked
// LITE-DIFF.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "i186_ref.h"

// Public ABI only -- no white-box access to the C core.
extern "C" {
#include "i186.h"
}

static const int64_t LITE_INF = (int64_t)1 << 62;

// Interrupt sources (machine.c SRC table, machine.h enum order).
enum { S_T0 = 0, S_T1, S_T2, S_S0RX, S_S0TX, S_INT4, S_INT0, S_INT1, S_INT2, S_INT3, SRC_N = 10 };
static const struct { int vec, bit, con; } SRC[SRC_N] = {
    { 0x08, 0x01, 0x12 }, { 0x12, 0x01, 0x12 }, { 0x13, 0x01, 0x12 },
    { 0x14, 0x04, 0x14 }, { 0x15, 0x04, 0x14 }, { 0x11, 0x08, 0x16 },
    { 0x0C, 0x10, 0x18 }, { 0x0D, 0x20, 0x1A }, { 0x0E, 0x40, 0x1C },
    { 0x0F, 0x80, 0x1E },
};
static int con_bit(int reg) {
    switch (reg) {
    case 0x12: return 0x01; case 0x14: return 0x04; case 0x16: return 0x08;
    case 0x18: return 0x10; case 0x1A: return 0x20; case 0x1C: return 0x40;
    case 0x1E: return 0x80;
    }
    return 0;
}
static int eoi_bit(int vec) {
    switch (vec) {
    case 0x08: case 0x12: case 0x13: return 0x01;
    case 0x14: case 0x15: return 0x04;
    case 0x11: return 0x08; case 0x0C: return 0x10; case 0x0D: return 0x20;
    case 0x0E: return 0x40; case 0x0F: return 0x80;
    }
    return 0;
}

struct LiteTimer { uint32_t cnt, cmpa, cmpb, con; int64_t last; int run; int64_t nxt; };
struct LiteUart {
    uint32_t cmp, con, sts, rbuf;
    int64_t rx_t, tx_t;
    int bit, sh, pu, rx_pending;
    long consumed, overruns;
};
enum { EE_IDLE = 0, EE_CMD, EE_READ, EE_WDATA };
struct LiteEeprom {
    int n; uint16_t w[256]; int ewen, dirty, state, bits[16], nbits;
    int do_bit, addr, rdn;
};

struct IRef {
    I186C *cpu;
    uint32_t ports[65536];
    uint8_t ports_set[65536];
    uint8_t pcb[65536];
    int pcb_mem;
    uint8_t port_in[256];
    int p2pin;
    int hw_idx;
    int line; // DTE TXD, 1 = mark/idle
    // DSP mailbox (DSP absent: d2h never filled, d2h_valid stays 0).
    uint16_t h2d[8], d2h[8];
    uint8_t ovl_bytes[256];
    int ovl_status;
    uint16_t flags56, flagsD;
    int h2d_pending, d2h_valid, evt, evt_seen, int0_req, evt4_n;
    uint16_t data_word; int data_full;
    long h2d_bytes, h2d_bursts, d2h_reads;
    uint8_t burst_tmp[256];
    uint8_t *dsp_bursts; size_t dsp_bursts_n, dsp_bursts_cap;
    // ICU.
    uint16_t req; uint32_t msk; int primsk;
    int icon[256]; int isv_present[256], isv_val[256]; int offered;
    long irq_count[256];
    LiteTimer tm[3];
    LiteUart uart[2];
    LiteEeprom eeprom;
    int flash_id;
    int pcb_mem_init;
    std::vector<ILogEv> log;
    std::vector<uint8_t> dte_out;
    uint32_t dsp_starts;
    // Distinct-access audit.
    uint8_t port_rd[65536], port_wr[65536];
    uint8_t mmio_touched[0x1000 + 0x1000]; // 0x0F000-0x0FFFF, 0xFF000-0xFFFFF
};

static uint32_t phys_pc(IRef *r) {
    uint32_t cs = i186_get(r->cpu, R_CS), ip = i186_get(r->cpu, R_IP);
    return ((cs << 4) + ip) & 0xFFFFF;
}
static void log_ev(IRef *r, uint32_t addr, uint32_t val, int w, int is_io, int is_wr) {
    ILogEv e;
    e.cyc = i186_cycles(r->cpu); e.addr = addr; e.val = val; e.w = w;
    e.is_io = is_io; e.is_wr = is_wr; e.pc = phys_pc(r);
    r->log.push_back(e);
    if (is_io) {
        if (is_wr) r->port_wr[addr & 0xFFFF] = 1; else r->port_rd[addr & 0xFFFF] = 1;
    } else if (addr >= 0x0F000 && addr <= 0x0FFFF) {
        r->mmio_touched[addr - 0x0F000] = 1;
    } else if (addr >= 0xFF000 && addr <= 0xFFFFF) {
        r->mmio_touched[0x1000 + (addr - 0xFF000)] = 1;
    }
}

// ---- EEPROM (machine.c eeprom_init / eeprom_clock, verbatim) ----
static void eeprom_init(LiteEeprom *e, const uint8_t *image, size_t len) {
    e->n = 256;
    for (int i = 0; i < 256; i++) e->w[i] = 0xFFFF;
    e->ewen = 0; e->dirty = 0;
    if (image)
        for (int i = 0; i < 256 && 2 * i + 1 < (int)len; i++)
            e->w[i] = (uint16_t)(image[2 * i] | (image[2 * i + 1] << 8));
    e->state = EE_IDLE; e->nbits = 0; e->do_bit = 1; e->addr = 0; e->rdn = 0;
}
static void eeprom_clock(LiteEeprom *e, int di) {
    if (e->state == EE_IDLE) {
        if (di) { e->state = EE_CMD; e->nbits = 0; }
    } else if (e->state == EE_CMD) {
        e->bits[e->nbits++] = di;
        if (e->nbits == 10) {
            int op = e->bits[0] * 2 + e->bits[1];
            int a = 0;
            for (int i = 2; i < 10; i++) a = (a << 1) | e->bits[i];
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
            for (int i = 0; i < 16; i++) v = (v << 1) | e->bits[i];
            if (e->ewen) { e->w[e->addr % e->n] = (uint16_t)v; e->dirty = 1; }
            e->state = EE_IDLE; e->do_bit = 1;
        }
    }
}

// ---- PCB timers (machine.c timer_run / timer_sched / timer_update) ----
static void timer_run(IRef *r, int i) {
    LiteTimer *T = &r->tm[i];
    T->run = (T->con & 0x8000) && (i != 1 || r->line == 0);
}
static void timer_sched(IRef *r, int i) {
    LiteTimer *T = &r->tm[i];
    if (!T->run) { T->nxt = LITE_INF; return; }
    int64_t lim = T->cmpa ? T->cmpa : 0x10000;
    if ((int64_t)T->cnt >= lim) lim = 0x10000;
    T->nxt = T->last + (lim - (int64_t)T->cnt) * 4;
}
static void timer_update(IRef *r, int i, int64_t t) {
    LiteTimer *T = &r->tm[i];
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
            T->con |= 0x20; // MC
            if (T->con & 0x2000) r->req |= (uint16_t)(1 << i);
            if (i == 0) r->req |= (uint16_t)(1 << S_INT3);
            if (!(T->con & 1)) {
                T->con &= ~0x8000u; T->run = 0; T->last = t;
                break; // one-shot: EN clears
            }
        }
    }
    timer_sched(r, i);
}

// ---- ICU (machine.c machine_sync_ack / machine_requests / machine_eoi / icu_eval) ----
static void lite_sync_ack(IRef *r) {
    if (r->offered >= 0 && !i186_irq_pending(r->cpu)) {
        int o = r->offered;
        r->offered = -1;
        r->req &= (uint16_t)~(1 << o);
        r->isv_present[SRC[o].bit] = 1;
        r->isv_val[SRC[o].bit] = r->icon[SRC[o].con] & 7;
        r->irq_count[SRC[o].vec]++;
    }
}
static uint16_t lite_requests(IRef *r) {
    return (uint16_t)(r->req | ((r->uart[1].sts & 0x60) ? (1 << S_INT4) : 0));
}
static void lite_eoi(IRef *r, uint32_t v) {
    lite_sync_ack(r);
    if (v & 0x8000) {
        int lo = 8, found = 0;
        for (int b = 0; b < 256; b++)
            if (r->isv_present[b] && (!found || r->isv_val[b] < lo)) {
                lo = r->isv_val[b]; found = 1;
            }
        if (found) {
            static const int order[7] = { 0x01, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80 };
            for (int i = 0; i < 7; i++)
                if (r->isv_present[order[i]] && r->isv_val[order[i]] == lo) {
                    r->isv_present[order[i]] = 0;
                    break;
                }
        }
    } else {
        int b = eoi_bit((int)(v & 0x1F));
        if (b) r->isv_present[b] = 0;
    }
}
static void lite_icu_eval(IRef *r) {
    lite_sync_ack(r);
    uint16_t q = lite_requests(r);
    int best = -1;
    if (q) {
        int bp = 8;
        for (int b = 0; b < 256; b++)
            if (r->isv_present[b] && r->isv_val[b] < bp) bp = r->isv_val[b];
        if (r->primsk + 1 < bp) bp = r->primsk + 1;
        for (int i = 0; i < SRC_N; i++) {
            if ((q >> i) & 1) {
                if (r->msk & SRC[i].bit) continue;
                int p = r->icon[SRC[i].con] & 7;
                if (p < bp) { best = i; bp = p; }
            }
        }
    }
    if (best != r->offered) {
        if (r->offered >= 0) i186_irq_clear(r->cpu);
        if (best >= 0) i186_irq(r->cpu, SRC[best].vec);
        r->offered = best;
    }
}

// ---- PCB register file (machine.c preg / pwr, verbatim) ----
static uint16_t lite_preg(IRef *r, uint16_t reg, int64_t now, int rd) {
    if (reg >= 0x30 && reg <= 0x46) {
        int i = (reg - 0x30) >> 3, k = reg & 6;
        LiteTimer *T = &r->tm[i];
        timer_update(r, i, now);
        switch (k >> 1) {
        case 0: return (uint16_t)T->cnt;
        case 1: return (uint16_t)T->cmpa;
        case 2: return (uint16_t)T->cmpb;
        default: return (uint16_t)T->con;
        }
    }
    if (reg >= 0x60 && reg <= 0x7A) {
        int j = (reg >> 4) - 6, k = reg & 0x0E;
        LiteUart *u = &r->uart[j];
        if (k == 6) {
            uint32_t v = u->sts;
            if (rd) {
                u->sts &= ~0xF4u; // reading SxSTS clears RB8, RI, TI, FE, OE
                if (j == 1 && (v & 0x60)) i186_stop(r->cpu); // INT4 level drops
            }
            return (uint16_t)v;
        }
        if (k <= 0x0A) {
            switch (k >> 1) {
            case 0: return (uint16_t)u->cmp;
            case 1: return 0;
            case 2: return (uint16_t)u->con;
            case 3: return 0;
            case 4: if (rd) { if (u->rx_pending) u->consumed++; u->rx_pending = 0; } return (uint16_t)u->rbuf;
            default: return 0;
            }
        }
        return 0;
    }
    if (con_bit(reg)) return (uint16_t)(r->icon[reg] | (r->msk & con_bit(reg) ? 8 : 0));
    if (reg == 0x08) return (uint16_t)r->msk;
    if (reg == 0x0A) return (uint16_t)r->primsk;
    if (reg == 0x0C) {
        lite_sync_ack(r);
        int s = 0;
        for (int b = 0; b < 256; b++)
            if (r->isv_present[b]) s += r->isv_val[b];
        return (uint16_t)s;
    }
    if (reg == 0x0E) {
        uint16_t q = lite_requests(r);
        int s = 0;
        for (int i = 0; i < SRC_N; i++)
            if ((q >> i) & 1 && i != S_T1 && i != S_T2 && i != S_S0TX)
                s += SRC[i].bit;
        if (q & 7) s |= 1;
        if (q & 0x18) s |= 4;
        return (uint16_t)s;
    }
    if (reg == 0x10) return (uint16_t)(r->req & 7);
    if (reg == 0x5A) {
        int v = (r->p2pin & ~0x20) | (r->line ? 0x20 : 0);
        v &= ~0x80;
        if (r->pcb[0x58] & 0x80)
            v |= r->eeprom.do_bit ? 0x80 : 0;
        else
            v |= r->pcb[0x5E] & 0x80;
        return (uint16_t)v;
    }
    return (uint16_t)(r->pcb[reg] | (r->pcb[reg + 1] << 8));
}

static void lite_pwr(IRef *r, uint16_t reg, uint16_t v, int64_t now) {
    uint16_t old = r->pcb[reg];
    r->pcb[reg] = (uint8_t)(v & 0xFF);
    r->pcb[reg + 1] = (uint8_t)(v >> 8);
    if (reg == 0x56) {
        // P1LTCH: EEPROM chip select (bit5) and clock (bit2).
        int cs0 = old & 0x20, cs1 = v & 0x20;
        if (cs1 && !cs0) { r->eeprom.state = EE_IDLE; r->eeprom.do_bit = 1; }
        else if (cs0 && !cs1) { r->eeprom.state = EE_IDLE; r->eeprom.do_bit = 1; }
        if (cs1 && (v & 4) && !(old & 4))
            eeprom_clock(&r->eeprom, (r->pcb[0x5E] >> 7) & 1);
    }
    if (reg >= 0x30 && reg <= 0x46) {
        int i = (reg - 0x30) >> 3, k = reg & 6;
        LiteTimer *T = &r->tm[i];
        timer_update(r, i, now);
        if (k == 0) T->cnt = v;
        else if (k == 2) T->cmpa = v;
        else if (k == 4) T->cmpb = v;
        else {
            uint32_t en = (v & 0x4000) ? (v & 0x8000) : (T->con & 0x8000);
            T->con = (v & 0x3FFF) | en;
        }
        timer_run(r, i); T->last = now; timer_sched(r, i);
        i186_stop(r->cpu);
    } else if (reg >= 0x60 && reg <= 0x7A) {
        int j = (reg >> 4) - 6, k = reg & 0x0E;
        LiteUart *u = &r->uart[j];
        if (k == 0) { u->cmp = v; u->pu = 8 * ((v & 0x7FFF) + 1); }
        else if (k == 4) {
            u->con = v;
            if (!(v & 0x20)) u->rx_t = LITE_INF; // REN off aborts reception
        } else if (k == 0x0A) {
            r->dte_out.push_back((uint8_t)(v & 0xFF));
            u->sts &= ~0x08u; // TXE low while the character shifts out
            u->tx_t = (u->tx_t == LITE_INF ? now : u->tx_t) + 10LL * u->pu;
            i186_stop(r->cpu);
        }
    } else if (con_bit(reg)) {
        r->icon[reg] = v & 0x77;
        if (v & 8) r->msk |= (uint32_t)con_bit(reg);
        else r->msk &= ~(uint32_t)con_bit(reg);
        i186_stop(r->cpu);
    } else if (reg == 0x08) {
        r->msk = v & 0xFD; i186_stop(r->cpu);
    } else if (reg == 0x0A) {
        r->primsk = v & 7; i186_stop(r->cpu);
    } else if (reg == 0x02) {
        lite_eoi(r, v);
        i186_stop(r->cpu);
    } else if (reg == 0xA8) {
        r->pcb_mem = (v & 0x1000) != 0; // RELREG
    }
}

static int lite_hw_id_bit(IRef *r) {
    uint32_t a = r->ports_set[0x12] ? r->ports[0x12] : 0xFF;
    uint32_t b = r->ports_set[0x14] ? r->ports[0x14] : 0xFF;
    uint32_t his[4] = { b & 0x40, a & 0x02, b & 0x10, b & 0x20 };
    int bits[4] = { 3, 2, 1, 0 };
    int res = 1;
    for (int i = 0; i < 4; i++)
        if (!his[i])
            res &= (r->hw_idx >> bits[i]) & 1;
    return res;
}

// ---- I/O hooks (machine.c machine_iord / machine_iowr, DSP absent) ----
static uint32_t lite_iord(void *ctx, uint16_t p, int w) {
    IRef *r = (IRef *)ctx;
    if (p >= 0xFF00 && !r->pcb_mem) {
        uint16_t v = lite_preg(r, (uint16_t)(p & 0xFE), (int64_t)i186_cycles(r->cpu), 1);
        uint32_t ret = w ? v : ((p & 1) ? (v >> 8) & 0xFF : v & 0xFF);
        log_ev(r, p, ret, w, 1, 0);
        return ret;
    }
    uint32_t ret;
    if (p == 0x00) ret = r->ports[0] & ~0x08u;
    else if (p == 0x18) ret = 0x03; // no DSP: machine_iord returns 0x03
    else if (p == 0x1C) ret = (uint32_t)(r->evt & 0xFF);
    else if (p == 0x1E) ret = 0; // no DSP: ovl_status is DSP-side only
    else if (p >= 0x40 && p <= 0x5E && (p % 2) == 0) {
        // DSP absent: the C code only answers this range when m->dsp
        // is set, so it falls through to the generic port store.
        ret = r->ports[p];
    }
    else if (p == 0x60 || p == 0x62) ret = r->ports[p]; // no DSP: no data word
    else if (p == 0x14) {
        int v = r->port_in[0x14] | 0x02;
        v = (v & ~0x08) | (lite_hw_id_bit(r) ? 0x08 : 0);
        // ring_on == 0 in lite mode: no heartbeat blink.
        ret = (uint32_t)v;
    }
    else if (p == 0x10 || p == 0x12 || p == 0x14) ret = r->port_in[p];
    else ret = r->ports[p];
    log_ev(r, p, ret, w, 1, 0);
    return ret;
}

static void lite_iowr(void *ctx, uint16_t p, int w, uint32_t v) {
    IRef *r = (IRef *)ctx;
    log_ev(r, p, v, w, 1, 1);
    if (p >= 0xFF00 && !r->pcb_mem) {
        int64_t now = (int64_t)i186_cycles(r->cpu);
        uint16_t reg = (uint16_t)(p & 0xFE);
        uint32_t vv = v;
        if (!w) {
            uint16_t old = lite_preg(r, reg, now, 0);
            vv = (p & 1) ? (uint32_t)((old & 0x00FF) | ((v & 0xFF) << 8))
                         : (uint32_t)((old & 0xFF00) | (v & 0xFF));
        }
        lite_pwr(r, reg, (uint16_t)(vv & 0xFFFF), now);
        return;
    }
    r->ports[p] = v;
    r->ports_set[p] = 1;
    if (p == 0x0A)
        r->dte_out.push_back((uint8_t)(v & 0xFF));
    if (p == 0x18 && (v & 0xFF) == 4)
        r->dsp_starts++; // LITE-DIFF: no DSP to start; counted, ignored
    if (p == 0x1C) {
        r->evt &= (uint8_t)~(v & 0xFF);
        r->evt_seen &= r->evt;
    }
    if (p >= 0x40 && p <= 0x5E && (p % 2) == 0) {
        // DSP absent: capture the pre-start overlay bursts exactly as
        // machine.c does (dsp_bursts, 8 bytes per burst).
        r->burst_tmp[p] = (uint8_t)(v & 0xFF);
        if (p == 0x4E || p == 0x5E) {
            int base = p == 0x4E ? 0x40 : 0x50;
            if (r->dsp_bursts_n + 1 > r->dsp_bursts_cap) {
                size_t nc = r->dsp_bursts_cap ? r->dsp_bursts_cap * 2 : 1024;
                r->dsp_bursts = (uint8_t *)realloc(r->dsp_bursts, nc * 8);
                r->dsp_bursts_cap = nc;
            }
            for (int q = 0; q < 8; q++)
                r->dsp_bursts[r->dsp_bursts_n * 8 + q] = r->burst_tmp[base + 2 * q];
            r->dsp_bursts_n++;
            memset(r->burst_tmp, 0, sizeof r->burst_tmp);
        }
    }
}

// ---- MMIO hooks (machine.c machine_mmrd / machine_mmwr, DSP absent) ----
static uint32_t lite_mmrd(void *ctx, uint32_t a, int w) {
    IRef *r = (IRef *)ctx;
    uint32_t ret;
    if (r->pcb_mem && a >= 0x0FF00 && a <= 0x0FFFF) {
        uint16_t v = lite_preg(r, (uint16_t)(a & 0xFE), (int64_t)i186_cycles(r->cpu), 1);
        if (!w) v = (uint16_t)((a & 1) ? (v >> 8) & 0xFF : v & 0xFF);
        ret = v & 0xFFFF;
    } else if (r->flash_id && a >= 0xFFFF0 && a <= 0xFFFF3) {
        uint32_t val = a < 0xFFFF2 ? 0x0089 : 0x4470;
        ret = w ? val : (val >> (8 * (a & 1))) & 0xFF;
    } else {
        uint8_t *mem = i186_mem(r->cpu);
        ret = (uint32_t)(mem[a & 0xFFFFF] | (w ? (mem[(a + 1) & 0xFFFFF] << 8) : 0));
    }
    log_ev(r, a, ret, w, 0, 0);
    return ret;
}

static void lite_mmwr(void *ctx, uint32_t a, int w, uint32_t v) {
    IRef *r = (IRef *)ctx;
    log_ev(r, a, v, w, 0, 1);
    if (a >= 0xFFFF0 && a <= 0xFFFF1) {
        if ((v & 0xFF) == 0x90) r->flash_id = 1;
        else if ((v & 0xFF) == 0xFF) r->flash_id = 0;
        return;
    }
    if (r->pcb_mem && a >= 0x0FF00 && a <= 0x0FFFF) {
        int64_t now = (int64_t)i186_cycles(r->cpu);
        uint16_t reg = (uint16_t)(a & 0xFE);
        uint32_t vv = v;
        if (!w) {
            uint16_t old = lite_preg(r, reg, now, 0);
            vv = (a & 1) ? (uint32_t)((old & 0x00FF) | ((v & 0xFF) << 8))
                         : (uint32_t)((old & 0xFF00) | (v & 0xFF));
        }
        lite_pwr(r, reg, (uint16_t)(vv & 0xFFFF), now);
        return;
    }
    uint8_t *mem = i186_mem(r->cpu);
    mem[a & 0xFFFFF] = (uint8_t)(v & 0xFF);
    if (w) mem[(a + 1) & 0xFFFFF] = (uint8_t)((v >> 8) & 0xFF);
}

// ---- file helper ----
static uint8_t *read_file(const char *path, size_t *len_out) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n < 0) { fclose(f); return NULL; }
    uint8_t *buf = (uint8_t *)malloc((size_t)n ? (size_t)n : 1);
    if (!buf) { fclose(f); return NULL; }
    if (n > 0 && fread(buf, 1, (size_t)n, f) != (size_t)n) {
        free(buf); fclose(f); return NULL;
    }
    fclose(f);
    *len_out = (size_t)n;
    return buf;
}

// ---- public API ----
extern "C" {

IRef *iref_new(void) {
    IRef *r = new IRef(); // value-initialization zeroes scalars
    r->cpu = i186_new();
    if (!r->cpu) { delete r; return NULL; }
    r->hw_idx = 7; // sv25 profile
    r->line = 1;
    r->msk = 0xFD; r->primsk = 7;
    for (int i = 0; i < 256; i++) r->icon[i] = 0x07;
    for (int i = 0; i < 3; i++) { r->tm[i].nxt = LITE_INF; r->tm[i].last = 0; }
    for (int j = 0; j < 2; j++) {
        r->uart[j].sts = 0x08;
        r->uart[j].rx_t = LITE_INF;
        r->uart[j].tx_t = LITE_INF;
        r->uart[j].pu = 8;
        r->uart[j].rx_pending = 0;
        r->uart[j].consumed = 0;
        r->uart[j].overruns = 0;
    }
    r->offered = -1;
    // DIP switches 3, 5, 8, 9 ON (machine_set_dip): port 0x12 = 0x9A.
    r->port_in[0x12] = 0x9A;
    // sw6 off -> bit2 set; voice/data button released -> bit6 set.
    r->port_in[0x14] = 0x44;
    // sw1 off -> P2PIN bit6 set.
    r->p2pin = 0x40;
    return r;
}

void iref_free(IRef *r) {
    if (!r) return;
    free(r->dsp_bursts);
    i186_free(r->cpu);
    delete r;
}

I186C *iref_cpu(IRef *r) { return r->cpu; }

int iref_load_firmware(IRef *r, const char *c_dir) {
    char flash_path[512], nvram_path[512];
    snprintf(flash_path, sizeof flash_path, "%s/fw/SV25.flash.bin", c_dir);
    snprintf(nvram_path, sizeof nvram_path, "%s/fw/nvram.bin", c_dir);
    size_t flen = 0;
    uint8_t *flash = read_file(flash_path, &flen);
    if (!flash) {
        fprintf(stderr, "iref: cannot read flash '%s'\n", flash_path);
        return -1;
    }
    uint8_t *mem = i186_mem(r->cpu);
    for (size_t i = 0; i < flen; i++)
        mem[(0x80000 + i) & 0xFFFFF] = flash[i];
    free(flash);
    for (int p = 0x80; p < 0x100; p++)
        i186_set_ro_page(r->cpu, (uint32_t)p, 1);
    size_t nvlen = 0;
    uint8_t *nv = read_file(nvram_path, &nvlen);
    eeprom_init(&r->eeprom, nv, nvlen);
    free(nv);
    i186_set_hooks(r->cpu, lite_iord, lite_iowr, lite_mmrd, lite_mmwr, r);
    r->flash_id = 0;
    i186_set_mmio_page(r->cpu, 0xFF, 1);
    i186_set_mmio_page(r->cpu, 0x0F, 1);
    // sv25 defaults (config.c): cycle model 1, scale 1.0, ud_trap 1.
    // Diag stays ON (unlike the production driver): the harness
    // needs ring_idx to count executed instructions per step.
    i186_set_cycle_model(r->cpu, 1);
    i186_set_cycle_scale(r->cpu, 1.0);
    i186_set_ud_trap(r->cpu, 1);
    i186_set_diag(r->cpu, 1);
    i186_reset(r->cpu);
    return 0;
}

int iref_step(IRef *r, uint32_t *delta_out) {
    uint32_t before = i186_ring_idx(r->cpu);
    int st = i186_run(r->cpu, 1);
    if (delta_out) *delta_out = i186_ring_idx(r->cpu) - before;
    return st;
}

void iref_service(IRef *r) {
    // machine_service-lite: UART TX completion + timer updates, then
    // ICU eval (mirrors machine_run: service -> icu_eval -> run).
    int64_t now = (int64_t)i186_cycles(r->cpu);
    for (int j = 0; j < 2; j++) {
        LiteUart *u = &r->uart[j];
        if (u->tx_t <= now) {
            u->tx_t = LITE_INF;
            u->sts |= 0x28; // TXE, TI
            if (j == 0) r->req |= (uint16_t)(1 << S_S0TX);
        }
    }
    for (int i = 0; i < 3; i++)
        if (r->tm[i].nxt <= now) timer_update(r, i, now);
    lite_icu_eval(r);
}

void iref_get_state(IRef *r, IState *s) {
    memset(s, 0, sizeof *s);
    s->ax = (uint16_t)i186_get(r->cpu, R_AX);
    s->cx = (uint16_t)i186_get(r->cpu, R_CX);
    s->dx = (uint16_t)i186_get(r->cpu, R_DX);
    s->bx = (uint16_t)i186_get(r->cpu, R_BX);
    s->sp = (uint16_t)i186_get(r->cpu, R_SP);
    s->bp = (uint16_t)i186_get(r->cpu, R_BP);
    s->si = (uint16_t)i186_get(r->cpu, R_SI);
    s->di = (uint16_t)i186_get(r->cpu, R_DI);
    s->es = (uint16_t)i186_get(r->cpu, R_ES);
    s->cs = (uint16_t)i186_get(r->cpu, R_CS);
    s->ss = (uint16_t)i186_get(r->cpu, R_SS);
    s->ds = (uint16_t)i186_get(r->cpu, R_DS);
    s->ip = (uint16_t)i186_get(r->cpu, R_IP);
    s->flags = (uint16_t)i186_get(r->cpu, R_FLAGS);
    s->cycles = i186_cycles(r->cpu);
    s->ring_idx = i186_ring_idx(r->cpu);
    // halted is not exposed by the public ABI; infer from the last
    // step status via the caller's iref_step return value. Leave 0.
    s->halted = 0;
    s->status = 0;
}

uint8_t *iref_mem(IRef *r) { return i186_mem(r->cpu); }

uint32_t iref_log_count(IRef *r) { return (uint32_t)r->log.size(); }
int iref_log_entry(IRef *r, uint32_t i, ILogEv *ev) {
    if (i >= r->log.size()) return -1;
    *ev = r->log[i];
    return 0;
}

uint32_t iref_dte_count(IRef *r) { return (uint32_t)r->dte_out.size(); }
uint8_t iref_dte_byte(IRef *r, uint32_t i) {
    return i < r->dte_out.size() ? r->dte_out[i] : 0;
}

int iref_port_touched(IRef *r, uint16_t port, int wr) {
    return wr ? r->port_wr[port] : r->port_rd[port];
}
int iref_mmio_touched(IRef *r, uint32_t addr) {
    if (addr >= 0x0F000 && addr <= 0x0FFFF) return r->mmio_touched[addr - 0x0F000];
    if (addr >= 0xFF000 && addr <= 0xFFFFF) return r->mmio_touched[0x1000 + (addr - 0xFF000)];
    return 0;
}

uint64_t iref_total_cycles(IRef *r) { return i186_cycles(r->cpu); }
uint32_t iref_total_instrs(IRef *r) { return i186_ring_idx(r->cpu); }
uint32_t iref_dsp_starts(IRef *r) { return r->dsp_starts; }

} // extern "C"
