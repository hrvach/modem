/* TMS320C5x (C51 flavour) instruction-set emulator.
 * Written for the SV25 firmware study.  Semantics follow the TI C5x User's Guide;
 * MAME's tms320c5x core (BSD-3, Ville Linde) was used as a cross-reference where it
 * is implemented (it stubs ~70 ops, which this firmware uses heavily).
 * Build: gcc -O2 -shared -fPIC -o libc5x.so c5x_core.c
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "c5x_cyctab.h"

typedef uint16_t (*io_rd_fn)(void *ctx, uint16_t port);
typedef void (*io_wr_fn)(void *ctx, uint16_t port, uint16_t val);

typedef struct { uint64_t cyc; uint16_t pc, port, val; uint8_t wr; } IoEv;
#define IOLOG_N 65536

typedef struct {
    uint32_t acc, accb, preg;
    uint16_t treg0, treg1, treg2, ar[8];
    int arp, arb, dp, ov, ovm, intm, cnf, tc, sxm, c, hm, xf, pm;
    int iptr, avis, ovly, ram, mpmc, ndx, trm, braf;
    uint16_t pc, op, stack[8];
    int sp;
    int32_t rptc;
    uint16_t rpt_start, rpt_end;
    uint16_t ifr, imr, indx, arcr, cbsr1, cber1, cbsr2, cber2, cbcr, bmar, dbmr, pasr, paer;
    uint32_t mmr_n[2][0x60]; uint16_t mmr_pc[2][0x60]; uint16_t mmr_val[0x60]; uint32_t ext_n[2][64]; uint32_t ff_n[2][256]; uint16_t rsv_a, rsv_pc; int32_t brcr; uint16_t io_rep; int xc_left, xc_new;
    uint16_t greg, drr, dxr, spc, tim, prd, tcr_tddr, pdwsr, iowsr, cwsr;
    int psc, tss;
    uint16_t mmr_raw[0x60];
    struct { uint32_t acc, accb, preg; uint16_t treg0, treg1, treg2, arcr, indx;
             int arp, arb, dp, ov, ovm, intm, cnf, tc, sxm, c, hm, xf, pm;
             int iptr, avis, ovly, ram, mpmc, ndx, trm, braf; } sh;
    uint64_t cycles;
    int xsrempty, rsrfull;           /* SPC status bits 12 / 13 (Table 9-13) */
    int idle, bio, stop, status, xrdy, rrdy, xint_mode, xint_first, cyc_model, words, rep_cont, legacy; uint64_t idle_cycles, timer_exp;
    uint16_t *pmem, *dmem, *iomem;
    uint32_t *hits;
    io_rd_fn io_rd; io_wr_fn io_wr; void *io_ctx;
    int iolog_on; IoEv *iolog; uint32_t iolog_n;
    uint8_t *bp;
    uint16_t cur_pc;
    uint16_t pcring[256]; uint32_t pcring_i;
    int in_delay;
    uint16_t ar0_prev; int ar0_dirty, int_inh; int cmpr_ar0;            /* experiment: CMPR compares with AR0 instead of ARCR */
    uint32_t pc_hits[65536]; uint32_t watch_hits[65536]; int32_t watch_a; int32_t trace_pc; uint32_t trace_n; struct { uint32_t acc; uint16_t ret, ret2; uint64_t cyc; } trace_buf[8192];
    uint16_t *dxr_ring; uint32_t dxr_head;   /* every DXR write is appended here (ring of 65536) */
    uint16_t ivec_ind[16];   /* if nonzero: interrupt n jumps to dmem[ivec_ind[n]] instead of the vector */
} C5x;

enum { RUN_OK = 0, RUN_BP = 1, RUN_BADOP = 2, RUN_STOP = 3 };

/* ---------- construction ---------- */
/* mutable copy of the manual cycle table; CYC_EXP (bit mask) lowers classes for experiments: 1 = RPT forms cost 1, 2 = one-shot BLDD/BLPD/TBLR/TBLW cost 2 (0xA5xx-0xA9xx) */
static uint8_t cycm[65536]; static int cycm_init;
static void cycm_setup(void) {
    if (cycm_init) return; cycm_init = 1; memcpy(cycm, cyc_tab, sizeof cycm);
    const char *e = getenv("CYC_EXP"); int m = e ? atoi(e) : 0;
    if (m & 1) { for (int w = 0x0B00; w <= 0x0BFF; w++) cycm[w] = 1; for (int w = 0xBB00; w <= 0xBBFF; w++) cycm[w] = 1; cycm[0xBEC4] = 1; }
    if (m & 2) { for (int w = 0xA500; w <= 0xA9FF; w++) if (cycm[w] == 3) cycm[w] = 2; }
}
C5x *c5x_new(void) {
    cycm_setup();
    C5x *c = calloc(1, sizeof *c);
    c->pmem = calloc(65536, 2); c->dmem = calloc(65536, 2); c->iomem = calloc(65536, 2);
    c->hits = calloc(65536, 4); c->bp = calloc(65536, 1);
    c->iolog = calloc(IOLOG_N, sizeof(IoEv)); c->dxr_ring = calloc(65536, 2);
    c->rptc = 0; c->trace_pc = -1; c->watch_a = -1;
    return c;
}
uint16_t *c5x_pmem(C5x *c) { return c->pmem; }
uint16_t *c5x_dmem(C5x *c) { return c->dmem; }
uint16_t *c5x_iomem(C5x *c) { return c->iomem; }
uint32_t *c5x_hits(C5x *c) { return c->hits; }
IoEv *c5x_iolog(C5x *c) { return c->iolog; }
uint32_t c5x_iolog_count(C5x *c) { return c->iolog_n; }
void c5x_iolog_clear(C5x *c) { c->iolog_n = 0; }
void c5x_iolog_enable(C5x *c, int on) { c->iolog_on = on; }
void c5x_set_io(C5x *c, io_rd_fn rd, io_wr_fn wr, void *ctx) { c->io_rd = rd; c->io_wr = wr; c->io_ctx = ctx; }
void c5x_set_bp(C5x *c, uint16_t a, int on) { c->bp[a] = on; }
void c5x_stop(C5x *c) { c->stop = 1; }
void c5x_set_bio(C5x *c, int v) { c->bio = v; }
uint16_t *c5x_pcring(C5x *c) { return c->pcring; }
uint32_t c5x_pcring_idx(C5x *c) { return c->pcring_i; }

void c5x_reset(C5x *c, uint16_t pc) {
    c->acc = c->accb = c->preg = 0; c->treg0 = c->treg1 = c->treg2 = 0;
    memset(c->ar, 0, sizeof c->ar);
    c->intm = 1; c->ov = 0; c->ovm = 0; c->arp = 0; c->arb = 0; c->dp = 0;
    c->c = 1; c->cnf = 0; c->hm = 1; c->pm = 0; c->sxm = 1; c->xf = 1; c->tc = 0;
    c->iptr = 0; c->avis = 0; c->ovly = 0; c->ram = 0; c->mpmc = 0; c->ndx = 0; c->trm = 0; c->braf = 0;
    c->ifr = 0; c->imr = 0; c->cbcr = 0; c->rptc = 0; c->idle = 0; c->sp = 0; c->ar0_dirty = 0; c->int_inh = 0; c->xc_left = c->xc_new = 0; c->rep_cont = 0; c->brcr = 0; c->greg = 0; c->pdwsr = c->iowsr = 0xFFFF; c->cwsr = 0x0F; c->drr = c->dxr = c->spc = 0;   /* 07-NEW-6: no stale host-side flags across a reset */
    c->pc = pc; c->xrdy = 1; c->rrdy = 0; c->xsrempty = 0; c->rsrfull = 0; c->spc = 0; c->cycles = 0; c->tss = 0; c->psc = 0; c->tim = 0xFFFF; c->prd = 0xFFFF; c->tcr_tddr = 0;
    memset(c->stack, 0, sizeof c->stack);
}

static inline void push(C5x *c, uint16_t v);
/* ---------- state access ---------- */
enum { S_PC, S_ACC, S_ACCB, S_PREG, S_T0, S_T1, S_T2, S_AR0, S_ST0 = 20, S_ST1, S_PMST, S_RPTC,
       S_IFR, S_IMR, S_SP, S_CYC_LO, S_CYC_HI, S_BMAR, S_DBMR, S_INDX, S_ARCR, S_DXR, S_DRR, S_TIM, S_PRD, S_IDLE };
static uint16_t st0_get(C5x *c) { return (c->arp << 13) | (c->ov << 12) | (c->ovm << 11) | (1 << 10) | (c->intm << 9) | (c->dp >> 7); }
static uint16_t st1_get(C5x *c) { return (c->arb << 13) | (c->cnf << 12) | (c->tc << 11) | (c->sxm << 10) | (c->c << 9) | (1 << 8) | (1 << 7) | (c->hm << 6) | (1 << 5) | (c->xf << 4) | (1 << 3) | (1 << 2) | c->pm; }
static uint16_t pmst_get(C5x *c) { return (c->iptr << 11) | (c->avis << 7) | (c->ovly << 5) | (c->ram << 4) | (c->mpmc << 3) | (c->ndx << 2) | (c->trm << 1) | c->braf; }
uint32_t c5x_get(C5x *c, int id) {
    if (id >= S_AR0 && id < S_AR0 + 8) return c->ar[id - S_AR0];
    switch (id) {
    case S_PC: return c->pc; case S_ACC: return c->acc; case S_ACCB: return c->accb; case S_PREG: return c->preg;
    case S_T0: return c->treg0; case S_T1: return c->treg1; case S_T2: return c->treg2;
    case S_ST0: return st0_get(c); case S_ST1: return st1_get(c); case S_PMST: return pmst_get(c);
    case S_RPTC: return c->rptc; case S_IFR: return c->ifr; case S_IMR: return c->imr; case S_SP: return c->sp;
    case S_CYC_LO: return (uint32_t)c->cycles; case S_CYC_HI: return (uint32_t)(c->cycles >> 32);
    case S_BMAR: return c->bmar; case S_DBMR: return c->dbmr; case S_INDX: return c->indx; case S_ARCR: return c->arcr;
    case S_DXR: return c->dxr; case S_DRR: return c->drr; case S_TIM: return c->tim; case S_PRD: return c->prd;
    case S_IDLE: return c->idle;
    }
    return 0;
}
void c5x_set(C5x *c, int id, uint32_t v) {
    if (id >= S_AR0 && id < S_AR0 + 8) { c->ar[id - S_AR0] = v; if (id == S_AR0) c->ar0_dirty = 1; return; }
    switch (id) {
    case S_PC: c->pc = v; break; case S_ACC: c->acc = v; break; case S_ACCB: c->accb = v; break; case S_DRR: c->drr = v; break;
    case S_DXR: c->dxr = v; break; case S_IMR: c->imr = v; break;
    case S_ST0: c->arp = v >> 13; c->ov = (v >> 12) & 1; c->ovm = (v >> 11) & 1; c->intm = (v >> 9) & 1; c->dp = (v & 0x1ff) << 7; break;
    case S_ST1: c->arb = v >> 13; c->cnf = (v >> 12) & 1; c->tc = (v >> 11) & 1; c->sxm = (v >> 10) & 1; c->c = (v >> 9) & 1; c->hm = (v >> 6) & 1; c->xf = (v >> 4) & 1; c->pm = v & 3; break;
    case S_PMST: c->iptr = v >> 11; c->avis = (v >> 7) & 1; c->ovly = (v >> 5) & 1; c->ram = (v >> 4) & 1; c->mpmc = (v >> 3) & 1; c->ndx = (v >> 2) & 1; c->trm = (v >> 1) & 1; c->braf = v & 1; break;
    case 40: push(c, (uint16_t)v); break;          /* push value on hardware stack */
    case 41: c->idle = v; break;
    }
}
void c5x_irq(C5x *c, int bit) { c->ifr |= 1 << bit; }

/* ---------- I/O ---------- */
static int io_ws(C5x *c, uint16_t port) {            /* 9.4.2/9.4.3: wait states of an I/O access from IOWSR/CWSR */
    int big = (c->cwsr >> 4) & 1, idx = big ? (port >> 13) : ((port >> 1) & 7);
    int f = (c->iowsr >> (2 * idx)) & 3, alt = (c->cwsr >> (idx < 4 ? 2 : 3)) & 1;
    return alt ? (f == 3 ? 7 : f == 2 ? 3 : f) : f;
}
static uint16_t io_read(C5x *c, uint16_t port) {
    uint16_t v;
    if (c->cyc_model) c->cycles += io_ws(c, port);               /* a read takes one extra cycle per wait state */
    if (c->io_rd) v = c->io_rd(c->io_ctx, port); else v = c->iomem[port];
    if (c->iolog_on && c->iolog_n < IOLOG_N) c->iolog[c->iolog_n++] = (IoEv){ c->cycles, c->cur_pc, port, v, 0 };
    return v;
}
static void io_write(C5x *c, uint16_t port, uint16_t v) {
    if (c->cyc_model) { int w = io_ws(c, port); if (w > 1) c->cycles += w - 1; }   /* software wait states do not lengthen writes until two or more are programmed (Table 9-7) */
    if (c->iolog_on && c->iolog_n < IOLOG_N) c->iolog[c->iolog_n++] = (IoEv){ c->cycles, c->cur_pc, port, v, 1 };
    if (c->io_wr) c->io_wr(c->io_ctx, port, v); else c->iomem[port] = v;
}

/* ---------- memory-mapped registers (data space 0x00..0x5F) ---------- */
static uint16_t mmr_rd(C5x *c, uint16_t a) {
    if (a < 0x60) { c->mmr_n[0][a]++; c->mmr_pc[0][a] = c->cur_pc; }
    if (a >= 0x50) return io_read(c, a);
    if (a >= 0x10 && a < 0x18) return c->ar[a - 0x10];
    switch (a) {
    case 0x04: return c->imr; case 0x05: return c->greg; case 0x06: return c->ifr; case 0x07: return pmst_get(c);
    case 0x08: return (uint16_t)c->rptc; case 0x09: return (uint16_t)c->brcr; case 0x0A: return c->pasr; case 0x0B: return c->paer;
    case 0x0C: return c->treg0; case 0x0D: return c->treg1 & 0x1F; case 0x0E: return c->treg2 & 0xF; case 0x0F: return c->dbmr;
    case 0x18: return c->indx; case 0x19: return c->arcr; case 0x1A: return c->cbsr1; case 0x1B: return c->cber1;
    case 0x1C: return c->cbsr2; case 0x1D: return c->cber2; case 0x1E: return c->cbcr; case 0x1F: return c->bmar;
    case 0x20: c->rrdy = 0; c->rsrfull = 0; return c->drr; case 0x21: return c->dxr;
    case 0x22: return (c->spc & 0xC0FE) | (c->rsrfull << 13) | (c->xsrempty << 12) | (c->xrdy << 11) | (c->rrdy << 10);   /* bit 0 reads 0; IN0/IN1 (CLKR/CLKX pins) read 0 */
    case 0x24: return c->tim; case 0x25: return c->prd;
    case 0x26: return ((c->psc & 0xF) << 6) | (c->tss << 4) | (c->tcr_tddr & 0xF);
    case 0x28: return c->pdwsr; case 0x29: return c->iowsr; case 0x2A: return c->cwsr;
    }
    return c->mmr_raw[a];
}
static void mmr_wr(C5x *c, uint16_t a, uint16_t d) {
    if (a < 0x60) { c->mmr_n[1][a]++; c->mmr_pc[1][a] = c->cur_pc; if (c->mmr_n[1][a] <= 1 || a < 0x10 || (a >= 0x1A && a <= 0x2A) || a == 0x32) c->mmr_val[a] = d; }
    if (a >= 0x50) { io_write(c, a, d); return; }
    if (a >= 0x10 && a < 0x18) { c->ar[a - 0x10] = d; if (a == 0x10) c->ar0_dirty = 1; return; }
    switch (a) {
    case 0x04: c->imr = d; return; case 0x05: c->greg = d; return;
    case 0x06: c->ifr &= ~d; return;
    case 0x07: c->iptr = d >> 11; c->avis = (d >> 7) & 1; c->ovly = (d >> 5) & 1; c->ram = (d >> 4) & 1;
               c->mpmc = (d >> 3) & 1; c->ndx = (d >> 2) & 1; c->trm = (d >> 1) & 1; c->braf = d & 1; return;
    case 0x08: c->rptc = d; return; case 0x09: c->brcr = d; return; case 0x0A: c->pasr = d; return; case 0x0B: c->paer = d; return;
    case 0x0C: c->treg0 = d; return; case 0x0D: c->treg1 = d & 0x1F; return; case 0x0E: c->treg2 = d & 0xF; return; case 0x0F: c->dbmr = d; return;
    case 0x18: c->indx = d; return; case 0x19: c->arcr = d; return; case 0x1A: c->cbsr1 = d; return; case 0x1B: c->cber1 = d; return;
    case 0x1C: c->cbsr2 = d; return; case 0x1D: c->cber2 = d; return; case 0x1E: c->cbcr = d & 0xFF; return; case 0x1F: c->bmar = d; return;
    case 0x20: c->drr = d; return; case 0x21: c->dxr = d; c->xrdy = 0; c->xsrempty = 1; c->dxr_ring[c->dxr_head++ & 0xFFFF] = d; break; case 0x22: {                                   /* SPC: FREE/SOFT, RRST, XRST, TXM, MCM, FSM, FO, DLB are writable; 13..8 are status */
        c->spc = d & 0xC0FE;
        if (!(d & 0x80)) { c->rrdy = 0; c->rsrfull = 0; }                                    /* RRST=0 clears RRDY / RSRFULL */
        if (!(d & 0x40)) { if (!c->xrdy) c->ifr |= (1 << 5); c->xsrempty = 0; c->xrdy = 1; }   /* XRST=0: XSREMPTY=0, XRDY=1, XINT if XRDY was 0 */
        break; }
    case 0x24: c->tim = d; return; case 0x25: c->prd = d; return;
    case 0x26: c->tcr_tddr = d & 0xF; c->tss = (d >> 4) & 1;
               if (d & 0x20) { c->tim = c->prd; c->psc = c->tcr_tddr; } else c->psc = (d >> 6) & 0xF;
               return;
    case 0x28: c->pdwsr = d; return; case 0x29: c->iowsr = d; return; case 0x2A: c->cwsr = d & 0x1F; return;
    }
    c->mmr_raw[a] = d;
    /* DXR / SPC / unknown MMR writes are visible through the I/O log as pseudo-ports 0x1_0000+a? use port a|0x8000 */
    if (c->iolog_on && c->iolog_n < IOLOG_N) c->iolog[c->iolog_n++] = (IoEv){ c->cycles, c->cur_pc, (uint16_t)(0x8000 | a), d, 1 };
}
/* Internal data RAM: B2 0x60-7F, B0/B1 0x100-4FF, SARAM 0x800-BFF. Everything else is external SRAM,
 * which on this board is shared between program and data space (unified with pmem). */
static inline int dm_internal(C5x *c, uint16_t a) { return a < 0x80 || (a >= 0x100 && a < 0x500 && !(c->cnf && a < 0x300)) || (c->ovly && a >= 0x800 && a < 0xC00); }   /* B0 leaves data space when CNF=1; SARAM is in data space only when OVLY=1 (SPRU056D 8.2, courier-emu data_region) */
static inline int dm_hostwin(uint16_t a) { return a >= 0xFF50 && a <= 0xFF5F; }   /* external memory-mapped host window */
static inline void mmr_bus(C5x *c, uint16_t a) { if (c->cyc_model && a >= 0x20 && a < 0x50) c->cycles++; }   /* manual 6.2: a peripheral MMR access (20h-4Fh) goes over the TI bus and adds one cycle */
static inline uint16_t dm_rd(C5x *c, uint16_t a) { if (a >= 0x60 && !dm_internal(c, a)) { c->ext_n[0][a >> 10]++; if (a >= 0xFF00) c->ff_n[0][a & 255]++; if (a >= 0x500 && a < 0x800) { c->rsv_a = a; c->rsv_pc = c->cur_pc; } } return a < 0x60 ? mmr_rd(c, a) : dm_internal(c, a) ? c->dmem[a] : dm_hostwin(a) ? io_read(c, a) : c->pmem[a]; }
static inline void dm_wr(C5x *c, uint16_t a, uint16_t d) { mmr_bus(c, a); if (a >= 0x60 && !dm_internal(c, a)) c->ext_n[1][a >> 10]++; if (a >= 0xFF00) c->ff_n[1][a & 255]++; if ((int32_t)a == c->watch_a) c->watch_hits[c->cur_pc]++; if (a < 0x60) mmr_wr(c, a, d); else if (dm_internal(c, a)) c->dmem[a] = d; else if (dm_hostwin(a)) io_write(c, a, d); else c->pmem[a] = d; }
static inline void dmov_wr(C5x *c, uint16_t a, uint16_t d) { if (dm_internal(c, a) && a >= 0x60 && dm_internal(c, a + 1)) dm_wr(c, a + 1, d); }   /* both the source and the destination (a+1) must be on-chip RAM (07-NEW-4) */   /* data move only within on-chip RAM (DMOV/LTD/MACD/MADD) */
static inline uint16_t *pm_ptr(C5x *c, uint16_t a) {
    if (c->cnf && a >= 0xFE00) return &c->dmem[a - 0xFE00 + 0x100];
    if (c->ram && a >= 0x2000 && a < 0x2400) return &c->dmem[a - 0x2000 + 0x800];
    return &c->pmem[a];
}
static inline uint16_t pm_rd(C5x *c, uint16_t a) { return *pm_ptr(c, a); }
static inline void pm_wr(C5x *c, uint16_t a, uint16_t d) { *pm_ptr(c, a) = d; }

/* ---------- helpers ---------- */
static inline void push(C5x *c, uint16_t v) { c->sp = (c->sp - 1) & 7; c->stack[c->sp] = v; }
static inline uint16_t pop(C5x *c) {
    uint16_t v = c->stack[c->sp]; c->sp = (c->sp + 1) & 7;
    c->stack[(c->sp + 7) & 7] = c->stack[(c->sp + 6) & 7];
    return v;
}
static uint32_t do_add(C5x *c, uint32_t a, uint32_t b, int cin, int s16) {
    uint64_t r = (uint64_t)a + b + cin; uint32_t res = (uint32_t)r; int carry = (r >> 32) & 1;
    if (s16) { if (carry) c->c = 1; } else c->c = carry;
    if ((a ^ res) & (b ^ res) & 0x80000000u) { if (c->ovm) res = ((int32_t)res < 0) ? 0x7fffffff : 0x80000000u; c->ov = 1; }
    return res;
}
static uint32_t do_sub(C5x *c, uint32_t a, uint32_t b, int bin, int s16) {
    uint64_t r = (uint64_t)a - b - bin; uint32_t res = (uint32_t)r; int borrow = (r >> 32) & 1;
    if (s16) { if (borrow) c->c = 0; } else c->c = !borrow;
    if ((a ^ b) & (a ^ res) & 0x80000000u) { if (c->ovm) res = ((int32_t)res < 0) ? 0x7fffffff : 0x80000000u; c->ov = 1; }
    return res;
}
static inline int32_t pscale(C5x *c) {
    int32_t p = (int32_t)c->preg;
    switch (c->pm & 3) { case 0: return p; case 1: return (int32_t)((uint32_t)p << 1); case 2: return (int32_t)((uint32_t)p << 4); default: return p >> 6; }
}
static inline void set_t0(C5x *c, uint16_t d) { c->treg0 = d; if (!c->trm) { c->treg1 = d & 0x1F; c->treg2 = d & 0xF; } }
static int circ_end(C5x *c, int ar, uint16_t v, uint16_t *start) {
    int cenb1 = (c->cbcr >> 3) & 1, car1 = c->cbcr & 7, cenb2 = (c->cbcr >> 7) & 1, car2 = (c->cbcr >> 4) & 7;
    if (cenb1 && ar == car1 && v == c->cber1) { *start = c->cbsr1; return 1; }
    if (!(cenb1 && ar == car1) && cenb2 && ar == car2 && v == c->cber2) { *start = c->cbsr2; return 1; }
    return 0;
}
static uint16_t bitrev16(uint16_t v) { uint16_t r = 0; for (int i = 0; i < 16; i++) if (v & (1 << i)) r |= 1 << (15 - i); return r; }

static void upd_ar(C5x *c, int ar, int step) {
    if (ar == 0) c->ar0_dirty = 1;
    int cenb1 = (c->cbcr >> 3) & 1, car1 = c->cbcr & 7, cenb2 = (c->cbcr >> 7) & 1, car2 = (c->cbcr >> 4) & 7;
    if (cenb1 && ar == car1) { if (c->ar[ar] == c->cber1) c->ar[ar] = c->cbsr1; else c->ar[ar] += step; }
    else if (cenb2 && ar == car2) { if (c->ar[ar] == c->cber2) c->ar[ar] = c->cbsr2; else c->ar[ar] += step; }
    else c->ar[ar] += step;
}
static inline void upd_arp(C5x *c, int n) { c->arb = c->arp; c->arp = n; }

static uint16_t ea(C5x *c) {
    uint16_t op = c->op;
    if (!(op & 0x80)) return c->dp | (op & 0x7f);
    int arp = c->arp, nar = op & 7, m = (op >> 3) & 0xF;
    uint16_t a = c->ar[arp];
    switch (m & ~1) {
    case 0x0: break;
    case 0x2: upd_ar(c, arp, -1); break;
    case 0x4: upd_ar(c, arp, 1); break;
    case 0x8: { uint16_t st; c->ar[arp] = circ_end(c, arp, a, &st) ? st : bitrev16(bitrev16(a) - bitrev16(c->indx)); if (arp == 0) c->ar0_dirty = 1; break; }
    case 0xA: upd_ar(c, arp, -(int16_t)c->indx); break;
    case 0xC: upd_ar(c, arp, (int16_t)c->indx); break;
    case 0xE: { uint16_t st; c->ar[arp] = circ_end(c, arp, a, &st) ? st : bitrev16(bitrev16(a) + bitrev16(c->indx)); if (arp == 0) c->ar0_dirty = 1; break; }
    default: c->status = RUN_BADOP; break;
    }
    if (m & 1) upd_arp(c, nar);
    return a;
}
/* SST uses page 0 for direct addressing */
static uint16_t ea_p0(C5x *c) { if (!(c->op & 0x80)) return c->op & 0x7f; return ea(c); }

static int zlvc_cond(C5x *c, int zlvc, int mask) {
    if (mask & 2) { if ((zlvc & 2) && !c->ov) return 0; if (!(zlvc & 2) && c->ov) return 0; }
    if (mask & 1) { if ((zlvc & 1) && !c->c) return 0; if (!(zlvc & 1) && c->c) return 0; }
    int32_t a = (int32_t)c->acc;
    switch ((mask & 0xc) | ((zlvc >> 2) & 3)) {
    case 4: case 6: case 12: return a > 0;
    case 5: case 7: case 13: return a < 0;
    case 8: case 9: return a != 0;
    case 10: case 11: return a == 0;
    case 14: return a >= 0;
    case 15: return a <= 0;
    }
    return 1;
}
static int tp_cond(C5x *c, int tp) { switch (tp) { case 0: return c->bio == 0; case 1: return c->tc; case 2: return !c->tc; } return 1; }
static int cond(C5x *c) { return zlvc_cond(c, (c->op >> 4) & 0xF, c->op & 0xF) && tp_cond(c, (c->op >> 8) & 3); }

static inline uint16_t fetch(C5x *c) { uint16_t v = pm_rd(c, c->pc); c->pc++; c->words++; return v; }
static void exec1(C5x *c);
static void delay_slot(C5x *c, uint16_t start) {
    uint64_t cy0 = c->cycles; uint16_t op0 = c->op;
    c->in_delay = 1;
    do { exec1(c); if (c->cyc_model) c->cycles += cycm[c->op] - 1; if (c->ar0_dirty) { if (!c->ndx) c->indx = c->arcr = c->ar[0]; c->ar0_dirty = 0; } } while ((uint16_t)(c->pc - start) < 2);   /* NDX mirror applies between the slot words too (5.2.1) */
    c->in_delay = 0; c->op = op0; (void)cy0;                 /* the slot words' own cycles are added to the delayed branch's (4.5.5 Ex. 4-3: BCNDD 2 + OPL 2 = 4) */
}
static void save_ctx(C5x *c) {
    c->sh.acc = c->acc; c->sh.accb = c->accb; c->sh.preg = c->preg; c->sh.treg0 = c->treg0; c->sh.treg1 = c->treg1; c->sh.treg2 = c->treg2;
    c->sh.arcr = c->arcr; c->sh.indx = c->indx; c->sh.arp = c->arp; c->sh.arb = c->arb; c->sh.dp = c->dp; c->sh.ov = c->ov; c->sh.ovm = c->ovm;
    c->sh.intm = c->intm; c->sh.cnf = c->cnf; c->sh.tc = c->tc; c->sh.sxm = c->sxm; c->sh.c = c->c; c->sh.hm = c->hm; c->sh.xf = c->xf; c->sh.pm = c->pm;
    c->sh.iptr = c->iptr; c->sh.avis = c->avis; c->sh.ovly = c->ovly; c->sh.ram = c->ram; c->sh.mpmc = c->mpmc; c->sh.ndx = c->ndx; c->sh.trm = c->trm; c->sh.braf = c->braf;
}
static void restore_ctx(C5x *c) {
    c->acc = c->sh.acc; c->accb = c->sh.accb; c->preg = c->sh.preg; c->treg0 = c->sh.treg0; c->treg1 = c->sh.treg1; c->treg2 = c->sh.treg2;
    c->arcr = c->sh.arcr; c->indx = c->sh.indx; c->arp = c->sh.arp; c->arb = c->sh.arb; c->dp = c->sh.dp; c->ov = c->sh.ov; c->ovm = c->sh.ovm;
    c->cnf = c->sh.cnf; c->tc = c->sh.tc; c->sxm = c->sh.sxm; c->c = c->sh.c; c->hm = c->sh.hm; c->pm = c->sh.pm;   /* audit #9: INTM/XF are not shadowed */
    c->iptr = c->sh.iptr; c->avis = c->sh.avis; c->ovly = c->sh.ovly; c->ram = c->sh.ram; c->mpmc = c->sh.mpmc; c->ndx = c->sh.ndx; c->trm = c->sh.trm; c->braf = c->sh.braf;
}
static const uint8_t ivec[16] = { 0x02, 0x04, 0x06, 0x08, 0x0A, 0x0C, 0x0E, 0x10, 0x12, 0, 0, 0, 0, 0, 0, 0 };   /* audited: INT1..INT3, TINT, RINT, XINT, TRNT, TXNT, INT4 */
static const uint8_t ivec_legacy[16] = { 0x02, 0x04, 0x06, 0x18, 0x1A, 0x1C, 0x1E, 0x20, 0x22, 0, 0, 0, 0, 0, 0, 0 };   /* old (wrong) table, still used so the firmware's `intr 17` (0x22) reaches the INT4 slot via the ROM-stub model */
static void tick_timer(C5x *c);
static void check_int(C5x *c) {
    uint16_t pend = c->ifr & c->imr;
    if (c->intm || !pend) return;
    for (int i = 0; i < 9; i++) if (pend & (1 << i)) {
        c->intm = 1; push(c, c->pc); c->pc = c->ivec_ind[i] ? dm_rd(c, c->ivec_ind[i]) : (c->iptr << 11) | ivec[i]; c->ifr &= ~(1 << i); c->idle = 0; save_ctx(c);
        if (c->cyc_model) for (int k = 0; k < 4; k++) { c->cycles++; tick_timer(c); }      /* interrupt entry: 4 cycles (pipeline flush, 7.2.2 / App. B class X) */
        return;
    }
}


/* data -> acc with shift, honouring SXM */
static inline uint32_t ext(C5x *c, uint16_t d, int sh) { return c->sxm ? (uint32_t)((int32_t)(int16_t)d << sh) : ((uint32_t)d << sh); }

static void exec_be(C5x *c);
static void exec_bf(C5x *c);

static void exec1(C5x *c) {
    uint16_t op; uint16_t a, d, imm; int n;
    c->cur_pc = c->pc; c->hits[c->pc]++; c->pcring[c->pcring_i++ & 255] = c->pc;
    c->pc_hits[c->pc & 0xFFFF]++;
    if ((int32_t)c->pc == c->trace_pc && c->trace_n < 8192) { c->trace_buf[c->trace_n].acc = c->acc; c->trace_buf[c->trace_n].ret = c->stack[c->sp]; c->trace_buf[c->trace_n].ret2 = c->stack[(c->sp + 1) & 7]; c->trace_buf[c->trace_n].cyc = c->cycles; c->trace_n++; }
    op = c->op = fetch(c);
    c->cycles++;
    switch (op >> 8) {
    case 0x00: case 0x01: case 0x02: case 0x03: case 0x04: case 0x05: case 0x06: case 0x07:
        a = ea(c); c->ar[(op >> 8) & 7] = dm_rd(c, a); if (((op >> 8) & 7) == 0) c->ar0_dirty = 1; break;                       /* LAR dma */
    case 0x08: a = ea(c) & 0x7f; c->acc = dm_rd(c, a); break;                       /* LAMM */
    case 0x09: { uint16_t pfc = fetch(c);                                            /* SMMR */
        a = ea(c) & 0x7f;                                                               /* the source MMR is fixed: only the destination (#addr) advances (6.3 SMMR) */
        while (c->rptc > -1) { dm_wr(c, pfc, dm_rd(c, a)); pfc++; if (c->rptc-- > 0) c->cycles += 2; } break; }   /* repeat total 2n (6.3 SMMR tables) */
    case 0x0A: a = ea(c); d = dm_rd(c, a);                                           /* SUBC */
        { uint32_t b = (uint32_t)d << 15, A = c->acc; uint64_t r = (uint64_t)A - b; uint32_t res = (uint32_t)r;   /* audit #24: SUBC affects C and OV (no saturation) */
               c->c = !((r >> 32) & 1); if ((A ^ b) & (A ^ res) & 0x80000000u) c->ov = 1;
               c->acc = (int32_t)res >= 0 ? (res << 1) + 1 : A << 1; } break;
    case 0x0B: a = ea(c); c->rptc = dm_rd(c, a); c->rpt_start = c->rpt_end = c->pc; break;  /* RPT dma */
    case 0x0C: { uint16_t port = fetch(c); if (!c->rep_cont) c->io_rep = 0; else c->io_rep++; port += c->io_rep; a = ea(c); io_write(c, port, dm_rd(c, a)); break; }  /* OUT: with RPT the port address increments per access (6.3 IN/OUT) */
    case 0x0D: a = ea(c); c->dp = (dm_rd(c, a) & 0x1ff) << 7; break;                 /* LDP dma */
    case 0x0E: { int arb0 = c->arb; a = ea(c); c->arb = arb0; } d = dm_rd(c, a); c->arp = d >> 13; c->ov = (d >> 12) & 1; c->ovm = (d >> 11) & 1; c->dp = (d & 0x1ff) << 7; break; /* LST #0 */
    case 0x0F: a = ea(c); d = dm_rd(c, a); c->arb = d >> 13; c->arp = d >> 13; c->cnf = (d >> 12) & 1; c->tc = (d >> 11) & 1; c->sxm = (d >> 10) & 1;
        c->c = (d >> 9) & 1; c->hm = (d >> 6) & 1; c->xf = (d >> 4) & 1; c->pm = d & 3; break;                   /* LST #1 */
    case 0x10: case 0x11: case 0x12: case 0x13: case 0x14: case 0x15: case 0x16: case 0x17:
    case 0x18: case 0x19: case 0x1A: case 0x1B: case 0x1C: case 0x1D: case 0x1E: case 0x1F:
        a = ea(c); c->acc = ext(c, dm_rd(c, a), (op >> 8) & 0xF); break;               /* LACC dma,s */
    case 0x20: case 0x21: case 0x22: case 0x23: case 0x24: case 0x25: case 0x26: case 0x27:
    case 0x28: case 0x29: case 0x2A: case 0x2B: case 0x2C: case 0x2D: case 0x2E: case 0x2F:
        a = ea(c); c->acc = do_add(c, c->acc, ext(c, dm_rd(c, a), (op >> 8) & 0xF), 0, 0); break;
    case 0x30: case 0x31: case 0x32: case 0x33: case 0x34: case 0x35: case 0x36: case 0x37:
    case 0x38: case 0x39: case 0x3A: case 0x3B: case 0x3C: case 0x3D: case 0x3E: case 0x3F:
        a = ea(c); c->acc = do_sub(c, c->acc, ext(c, dm_rd(c, a), (op >> 8) & 0xF), 0, 0); break;
    case 0x40: case 0x41: case 0x42: case 0x43: case 0x44: case 0x45: case 0x46: case 0x47:
    case 0x48: case 0x49: case 0x4A: case 0x4B: case 0x4C: case 0x4D: case 0x4E: case 0x4F:
        a = ea(c); c->tc = (dm_rd(c, a) >> (15 - ((op >> 8) & 0xF))) & 1; break;        /* BIT */
    case 0x50: a = ea(c); d = dm_rd(c, a); c->acc = do_add(c, c->acc, pscale(c), 0, 0); c->preg = (int32_t)(int16_t)c->treg0 * (int32_t)(int16_t)d; break; /* MPYA */
    case 0x51: a = ea(c); d = dm_rd(c, a); c->acc = do_sub(c, c->acc, pscale(c), 0, 0); c->preg = (int32_t)(int16_t)c->treg0 * (int32_t)(int16_t)d; break; /* MPYS */
    case 0x52: a = ea(c); d = dm_rd(c, a); c->acc = do_add(c, c->acc, pscale(c), 0, 0); set_t0(c, d); c->preg = (int32_t)(int16_t)d * (int32_t)(int16_t)d; break; /* SQRA */
    case 0x53: a = ea(c); d = dm_rd(c, a); c->acc = do_sub(c, c->acc, pscale(c), 0, 0); set_t0(c, d); c->preg = (int32_t)(int16_t)d * (int32_t)(int16_t)d; break; /* SQRS */
    case 0x54: a = ea(c); d = dm_rd(c, a); c->preg = (int32_t)(int16_t)c->treg0 * (int32_t)(int16_t)d; break;  /* MPY dma */
    case 0x55: a = ea(c); d = dm_rd(c, a); c->preg = (uint32_t)c->treg0 * (uint32_t)d; break;                  /* MPYU */
    case 0x56: c->status = RUN_BADOP; break;
    case 0x57: { uint16_t pfc = c->bmar;                                             /* BLDP */
        while (c->rptc > -1) { a = ea(c); pm_wr(c, pfc, dm_rd(c, a)); pfc++; if (c->rptc-- > 0) c->cycles++; } break; }   /* audit #15: BMAR is not written back (PFC<-BMAR, then PFC<-MCS) */
    case 0x58: a = ea(c); d = dm_rd(c, a) ^ c->dbmr; c->tc = d == 0; dm_wr(c, a, d); break;     /* XPL dbmr */
    case 0x59: a = ea(c); d = dm_rd(c, a) | c->dbmr; c->tc = d == 0; dm_wr(c, a, d); break;     /* OPL dbmr */
    case 0x5A: a = ea(c); d = dm_rd(c, a) & c->dbmr; c->tc = d == 0; dm_wr(c, a, d); break;     /* APL dbmr */
    case 0x5B: a = ea(c); c->tc = dm_rd(c, a) == c->dbmr; break;                                /* CPL dbmr */
    case 0x5C: imm = fetch(c); a = ea(c); d = dm_rd(c, a) ^ imm; c->tc = d == 0; dm_wr(c, a, d); break;
    case 0x5D: imm = fetch(c); a = ea(c); d = dm_rd(c, a) | imm; c->tc = d == 0; dm_wr(c, a, d); break;
    case 0x5E: imm = fetch(c); a = ea(c); d = dm_rd(c, a) & imm; c->tc = d == 0; dm_wr(c, a, d); break;
    case 0x5F: imm = fetch(c); a = ea(c); c->tc = dm_rd(c, a) == imm; break;
    case 0x60: a = ea(c); c->acc = do_add(c, c->acc, dm_rd(c, a), c->c, 0); break;               /* ADDC */
    case 0x61: a = ea(c); c->acc = do_add(c, c->acc, (uint32_t)dm_rd(c, a) << 16, 0, 1); break;  /* ADD dma,16 */
    case 0x62: a = ea(c); c->acc = do_add(c, c->acc, dm_rd(c, a), 0, 0); break;                  /* ADDS */
    case 0x63: a = ea(c); c->acc = do_add(c, c->acc, ext(c, dm_rd(c, a), c->treg1 & 0xF), 0, 0); break; /* ADDT */
    case 0x64: a = ea(c); c->acc = do_sub(c, c->acc, dm_rd(c, a), !c->c, 0); break;              /* SUBB */
    case 0x65: a = ea(c); c->acc = do_sub(c, c->acc, (uint32_t)dm_rd(c, a) << 16, 0, 1); break;  /* SUB dma,16 */
    case 0x66: a = ea(c); c->acc = do_sub(c, c->acc, dm_rd(c, a), 0, 0); break;                  /* SUBS */
    case 0x67: a = ea(c); c->acc = do_sub(c, c->acc, ext(c, dm_rd(c, a), c->treg1 & 0xF), 0, 0); break; /* SUBT */
    case 0x68: a = ea(c); c->acc = ((uint32_t)dm_rd(c, a) << 16) | 0x8000; break;                /* ZALR */
    case 0x69: a = ea(c); c->acc = dm_rd(c, a); break;                                           /* LACL dma */
    case 0x6A: a = ea(c); c->acc = (uint32_t)dm_rd(c, a) << 16; break;                           /* LACC dma,16 */
    case 0x6B: a = ea(c); c->acc = ext(c, dm_rd(c, a), c->treg1 & 0xF); break;                   /* LACT */
    case 0x6C: a = ea(c); c->acc ^= dm_rd(c, a); break;                                          /* XOR */
    case 0x6D: a = ea(c); c->acc |= dm_rd(c, a); break;                                          /* OR */
    case 0x6E: a = ea(c); c->acc &= dm_rd(c, a); break;                                          /* AND (clears ACCH) */
    case 0x6F: a = ea(c); c->tc = (dm_rd(c, a) >> (~c->treg2 & 0xF)) & 1; break;                 /* BITT */
    case 0x70: a = ea(c); d = dm_rd(c, a); c->acc = do_add(c, c->acc, pscale(c), 0, 0); set_t0(c, d); break;  /* LTA */
    case 0x71: a = ea(c); d = dm_rd(c, a); c->acc = pscale(c); set_t0(c, d); break;               /* LTP */
    case 0x72: a = ea(c); d = dm_rd(c, a); c->acc = do_add(c, c->acc, pscale(c), 0, 0); set_t0(c, d); dmov_wr(c, a, d); break; /* LTD */
    case 0x73: a = ea(c); set_t0(c, dm_rd(c, a)); break;                                          /* LT */
    case 0x74: a = ea(c); d = dm_rd(c, a); c->acc = do_sub(c, c->acc, pscale(c), 0, 0); set_t0(c, d); break;  /* LTS */
    case 0x75: a = ea(c); c->preg = (c->preg & 0xFFFF) | ((uint32_t)dm_rd(c, a) << 16); break;   /* LPH */
    case 0x76: a = ea(c); push(c, dm_rd(c, a)); break;                                            /* PSHD */
    case 0x77: a = ea(c); if (dm_internal(c, a) && a >= 0x60 && dm_internal(c, a + 1)) dm_wr(c, a + 1, dm_rd(c, a)); break;   /* audit #16: DMOV only within on-chip RAM */                                    /* DMOV */
    case 0x78: upd_ar(c, c->arp, op & 0xff); break;                                               /* ADRK */
    case 0x79: imm = fetch(c); ea(c); c->pc = imm; break;                                         /* B */
    case 0x7A: imm = fetch(c); ea(c); push(c, c->pc); c->pc = imm; break;                         /* CALL */
    case 0x7B: imm = fetch(c); { int take = c->ar[c->arp] != 0; ea(c); if (take) c->pc = imm; } break; /* BANZ */
    case 0x7C: upd_ar(c, c->arp, -(int)(op & 0xff)); break;                                       /* SBRK */
    case 0x7D: imm = fetch(c); ea(c); delay_slot(c, c->pc); c->pc = imm; break;                   /* BD */
    case 0x7E: imm = fetch(c); ea(c); push(c, c->pc + 2); delay_slot(c, c->pc); c->pc = imm; break; /* CALLD */
    case 0x7F: imm = fetch(c); { int take = c->ar[c->arp] != 0; ea(c); delay_slot(c, c->pc); if (take) c->pc = imm; } break; /* BANZD */
    case 0x80: case 0x81: case 0x82: case 0x83: case 0x84: case 0x85: case 0x86: case 0x87:
        d = c->ar[(op >> 8) & 7]; a = ea(c); dm_wr(c, a, d); break;                               /* SAR */
    case 0x88: a = ea(c) & 0x7f; dm_wr(c, a, (uint16_t)c->acc); break;                            /* SAMM */
    case 0x89: { uint16_t pfc = fetch(c);                                                         /* LMMR */
        a = ea(c) & 0x7f;                                                               /* destination MMR fixed, source (#addr) advances (6.3 LMMR) */
        while (c->rptc > -1) { dm_wr(c, a, dm_rd(c, pfc)); pfc++; if (c->rptc-- > 0) c->cycles += 2; } break; }
    case 0x8A: a = ea(c); dm_wr(c, a, pop(c)); break;                                             /* POPD */
    case 0x8B: if (op & 0x80) ea(c); break;                                                       /* MAR */
    case 0x8C: a = ea(c); dm_wr(c, a, (uint16_t)pscale(c)); break;                                /* SPL */
    case 0x8D: a = ea(c); dm_wr(c, a, (uint16_t)((uint32_t)pscale(c) >> 16)); break;              /* SPH */
    case 0x8E: a = ea_p0(c); dm_wr(c, a, st0_get(c)); break;                                      /* SST #0 */
    case 0x8F: a = ea_p0(c); dm_wr(c, a, st1_get(c)); break;                                      /* SST #1 */
    case 0x90: case 0x91: case 0x92: case 0x93: case 0x94: case 0x95: case 0x96: case 0x97:
        a = ea(c); dm_wr(c, a, (uint16_t)(c->acc << ((op >> 8) & 7))); break;                     /* SACL */
    case 0x98: case 0x99: case 0x9A: case 0x9B: case 0x9C: case 0x9D: case 0x9E: case 0x9F:
        a = ea(c); dm_wr(c, a, (uint16_t)((c->acc << ((op >> 8) & 7)) >> 16)); break;             /* SACH */
    case 0xA0: { int t = ((c->acc >> 31) ^ (c->acc >> 30)) & 1; if (c->acc == 0) t = 1; if (!t) ea(c);   /* audit #23: AR is modified only when the ACC is shifted */                            /* NORM */
        if (t) c->tc = 1; else { c->tc = 0; c->acc <<= 1; } break; }
    case 0xA1: c->status = RUN_BADOP; break;
    case 0xA2: case 0xA3: { uint16_t pfc = fetch(c);                                              /* MAC / MACD */
        do { a = ea(c); d = dm_rd(c, a); c->acc = do_add(c, c->acc, pscale(c), 0, 0); set_t0(c, d);
             c->preg = (int32_t)(int16_t)d * (int32_t)(int16_t)pm_rd(c, pfc); pfc++;
             if ((op >> 8) == 0xA3) dmov_wr(c, a, d);
             if (c->rptc > -1) { if (c->rptc-- > 0) c->cycles++; } } while (c->rptc > -1); break; }
    case 0xA4: { uint16_t pfc = c->bmar;                                                          /* BLPD bmar,dma */
        while (c->rptc > -1) { a = ea(c); dm_wr(c, a, pm_rd(c, pfc)); pfc++; if (c->rptc-- > 0) c->cycles++; } break; }   /* audit #15: BMAR is not written back (PFC<-BMAR, then PFC<-MCS) */
    case 0xA5: { uint16_t pfc = fetch(c);                                                         /* BLPD #pma,dma */
        while (c->rptc > -1) { a = ea(c); dm_wr(c, a, pm_rd(c, pfc)); pfc++; if (c->rptc-- > 0) c->cycles++; } break; }
    case 0xA6: { uint16_t pfc = (uint16_t)c->acc;                                                 /* TBLR */
        while (c->rptc > -1) { a = ea(c); dm_wr(c, a, pm_rd(c, pfc)); pfc++; if (c->rptc-- > 0) c->cycles++; } (void)pfc; break; }   /* TBLR/TBLW leave ACC unchanged (PFC is internal) */
    case 0xA7: { uint16_t pfc = (uint16_t)c->acc;                                                 /* TBLW */
        while (c->rptc > -1) { a = ea(c); pm_wr(c, pfc, dm_rd(c, a)); pfc++; if (c->rptc-- > 0) c->cycles++; } (void)pfc; break; }   /* TBLR/TBLW leave ACC unchanged (PFC is internal) */
    case 0xA8: { uint16_t pfc = fetch(c);                                                         /* BLDD #lk,dma */
        while (c->rptc > -1) { a = ea(c); dm_wr(c, a, dm_rd(c, pfc)); pfc++; if (c->rptc-- > 0) c->cycles++; } break; }
    case 0xA9: { uint16_t pfc = fetch(c);                                                         /* BLDD dma,#lk */
        while (c->rptc > -1) { a = ea(c); dm_wr(c, pfc, dm_rd(c, a)); pfc++; if (c->rptc-- > 0) c->cycles++; } break; }
    case 0xAA: case 0xAB: { uint16_t pfc = c->bmar;                                               /* MADS / MADD */
        do { a = ea(c); d = dm_rd(c, a); c->acc = do_add(c, c->acc, pscale(c), 0, 0); c->treg0 = d;   /* audit N-1: no TRM mirror */
             c->preg = (int32_t)(int16_t)d * (int32_t)(int16_t)pm_rd(c, pfc); pfc++;
             if ((op >> 8) == 0xAB) dmov_wr(c, a, d);
             if (c->rptc > -1) { if (c->rptc-- > 0) c->cycles++; } } while (c->rptc > -1); break; }   /* audit #15: BMAR is not written back (PFC<-BMAR, then PFC<-MCS) */
    case 0xAC: { uint16_t pfc = c->bmar;                                                          /* BLDD bmar,dma */
        while (c->rptc > -1) { a = ea(c); dm_wr(c, a, dm_rd(c, pfc)); pfc++; if (c->rptc-- > 0) c->cycles++; } break; }   /* audit #15: BMAR is not written back (PFC<-BMAR, then PFC<-MCS) */
    case 0xAD: { uint16_t pfc = c->bmar;                                                          /* BLDD dma,bmar */
        while (c->rptc > -1) { a = ea(c); dm_wr(c, pfc, dm_rd(c, a)); pfc++; if (c->rptc-- > 0) c->cycles++; } break; }   /* audit #15: BMAR is not written back (PFC<-BMAR, then PFC<-MCS) */
    case 0xAE: a = ea(c); imm = fetch(c); dm_wr(c, a, imm); break;                                /* SPLK */
    case 0xAF: { uint16_t port = fetch(c); if (!c->rep_cont) c->io_rep = 0; else c->io_rep++; port += c->io_rep; a = ea(c); dm_wr(c, a, io_read(c, port)); break; }     /* IN */
    case 0xB0: case 0xB1: case 0xB2: case 0xB3: case 0xB4: case 0xB5: case 0xB6: case 0xB7:
        c->ar[(op >> 8) & 7] = op & 0xff; if (((op >> 8) & 7) == 0) c->ar0_dirty = 1; break;                                                   /* LAR #k8 */
    case 0xB8: c->acc = do_add(c, c->acc, op & 0xff, 0, 0); break;
    case 0xB9: c->acc = op & 0xff; break;
    case 0xBA: c->acc = do_sub(c, c->acc, op & 0xff, 0, 0); break;
    case 0xBB: c->rptc = op & 0xff; c->rpt_start = c->rpt_end = c->pc; break;
    case 0xBC: case 0xBD: c->dp = (op & 0x1ff) << 7; break;                                       /* LDP #k9 */
    case 0xBE: exec_be(c); break;
    case 0xBF: exec_bf(c); break;
    case 0xE0: case 0xE1: case 0xE2: case 0xE3:                                                   /* BCND */
        imm = fetch(c); if (cond(c)) { c->pc = imm; if (op & 2) c->ov = 0; } break;
    case 0xE4: case 0xE5: case 0xE6: case 0xE7: case 0xF4: case 0xF5: case 0xF6: case 0xF7:       /* XC */
        if (!cond(c)) { n = ((op >> 12) & 1) + 1; c->pc += n; }   /* XC n counts instruction WORDS (manual: n=2 = one 2-word or two 1-word instructions); XC does not touch OV (N-12) */ else { c->xc_left = 2;   /* XC and the two words following it are uninterruptible, whatever n (6.3 XC) */ c->xc_new = 1; } break;   /* XC and the 1-2 words after it are uninterruptible (6.3 XC) */
    case 0xE8: case 0xE9: case 0xEA: case 0xEB:                                                   /* CC */
        imm = fetch(c); if (cond(c)) { push(c, c->pc); c->pc = imm; if (op & 2) c->ov = 0; } break;
    case 0xEC: case 0xED: case 0xEE: case 0xEF:                                                   /* RETC */
        { if (cond(c)) c->pc = pop(c); } break;   /* RETC: no status bits affected (N-12) */
    case 0xF0: case 0xF1: case 0xF2: case 0xF3:                                                   /* BCNDD */
        imm = fetch(c); if (cond(c)) { if (op & 2) c->ov = 0; delay_slot(c, c->pc); c->pc = imm; } break;
    case 0xF8: case 0xF9: case 0xFA: case 0xFB:                                                   /* CCD */
        imm = fetch(c); if (cond(c)) { push(c, c->pc + 2); if (op & 2) c->ov = 0; delay_slot(c, c->pc); c->pc = imm; } break;
    case 0xFC: case 0xFD: case 0xFE: case 0xFF:                                                   /* RETCD */
        if (cond(c)) { delay_slot(c, c->pc); c->pc = pop(c); } break;   /* RETD: the slot runs first, then TOS -> PC and the stack is popped (6.3 RETD) */
    default:                                                                                       /* MPY #k13 */
        if ((op >> 8) >= 0xC0 && (op >> 8) <= 0xDF) { int32_t k = op & 0x1fff; if (k & 0x1000) k -= 0x2000; c->preg = (int32_t)(int16_t)c->treg0 * k; }
        else c->status = RUN_BADOP;
    }
}

static void exec_be(C5x *c) {
    uint16_t op = c->op; uint32_t t; uint16_t imm;
    switch (op & 0xff) {
    case 0x00: if (c->acc == 0x80000000u) { c->ov = 1; c->c = 0; c->acc = c->ovm ? 0x7fffffffu : 0x80000000u; } else { if ((int32_t)c->acc < 0) c->acc = -c->acc; c->c = 0; } break; /* ABS */
    case 0x01: c->acc = ~c->acc; break;
    case 0x02: if (c->acc == 0x80000000u) { c->ov = 1; c->c = 0; c->acc = c->ovm ? 0x7fffffffu : 0x80000000u; } else { c->acc = -c->acc; c->c = c->acc == 0; } break;
    case 0x03: c->acc = pscale(c); break;
    case 0x04: c->acc = do_add(c, c->acc, pscale(c), 0, 0); break;
    case 0x05: c->acc = do_sub(c, c->acc, pscale(c), 0, 0); break;
    case 0x09: c->c = c->acc >> 31; c->acc <<= 1; break;
    case 0x0A: c->c = c->acc & 1; c->acc = c->sxm ? (uint32_t)((int32_t)c->acc >> 1) : c->acc >> 1; break;
    case 0x0C: t = c->c; c->c = c->acc >> 31; c->acc = (c->acc << 1) | t; break;
    case 0x0D: t = c->c; c->c = c->acc & 1; c->acc = (c->acc >> 1) | (t << 31); break;
    case 0x10: c->acc = do_add(c, c->acc, c->accb, 0, 0); break;
    case 0x11: c->acc = do_add(c, c->acc, c->accb, c->c, 0); break;
    case 0x12: c->acc &= c->accb; break;
    case 0x13: c->acc |= c->accb; break;
    case 0x14: { uint32_t a = c->acc, b = c->accb, cc = c->c; c->acc = (a << 1) | (b >> 31); c->accb = (b << 1) | cc; c->c = a >> 31; break; }
    case 0x15: { uint32_t a = c->acc, b = c->accb, cc = c->c; c->accb = (b >> 1) | (a << 31); c->acc = (a >> 1) | (cc << 31); c->c = b & 1; break; }
    case 0x16: { uint32_t a = c->acc, b = c->accb; c->acc = (a << 1) | (b >> 31); c->accb = b << 1; c->c = a >> 31; break; }
    case 0x17: { uint32_t a = c->acc, b = c->accb; c->accb = (b >> 1) | (a << 31); c->acc = c->sxm ? (uint32_t)((int32_t)a >> 1) : a >> 1; c->c = b & 1; break; }
    case 0x18: c->acc = do_sub(c, c->acc, c->accb, 0, 0); break;
    case 0x19: { uint64_t r = (uint64_t)c->acc - (uint64_t)c->accb - (uint64_t)(!c->c); c->c = !(r >> 32 & 1); c->acc = (uint32_t)r; } break;   /* SBBB affects C only: no OV, no saturation (SPRU056D p.6-233) */
    case 0x1A: c->acc ^= c->accb; break;
    case 0x1B: if ((int32_t)c->acc >= (int32_t)c->accb) { c->accb = c->acc; c->c = 1; } else { c->acc = c->accb; c->c = 0; } break;
    case 0x1C: if ((int32_t)c->acc >= (int32_t)c->accb) { c->acc = c->accb; c->c = 0; } else { c->accb = c->acc; c->c = 1; } break;
    case 0x1D: t = c->acc; c->acc = c->accb; c->accb = t; break;
    case 0x1E: c->accb = c->acc; break;
    case 0x1F: c->acc = c->accb; break;
    case 0x20: c->pc = (uint16_t)c->acc; break;
    case 0x21: { uint16_t p = (uint16_t)c->acc; delay_slot(c, c->pc); c->pc = p; break; }
    case 0x22: c->idle = 1; break;
    case 0x23: c->idle = 2; break;                                                   /* IDLE2: peripherals stopped, only RS/NMI/INT1-4 wake the CPU (4.10.2) */
    case 0x30: push(c, c->pc); c->pc = (uint16_t)c->acc; break;
    case 0x32: c->acc = pop(c); break;
    case 0x38: c->pc = pop(c); restore_ctx(c); break;                       /* RETI */
    case 0x3A: c->pc = pop(c); restore_ctx(c); c->intm = 0; break;          /* RETE */
    case 0x3C: push(c, (uint16_t)c->acc); break;
    case 0x3D: { uint16_t p = (uint16_t)c->acc; push(c, c->pc + 2); delay_slot(c, c->pc); c->pc = p; break; }
    case 0x40: c->intm = 0; c->int_inh = 1; break; case 0x41: c->intm = 1; break;
    case 0x42: c->ovm = 0; break; case 0x43: c->ovm = 1; break;
    case 0x44: c->cnf = 0; break; case 0x45: c->cnf = 1; break;
    case 0x46: c->sxm = 0; break; case 0x47: c->sxm = 1; break;
    case 0x48: c->hm = 0; break; case 0x49: c->hm = 1; break;
    case 0x4A: c->tc = 0; break; case 0x4B: c->tc = 1; break;
    case 0x4C: c->xf = 0; break; case 0x4D: c->xf = 1; break;
    case 0x4E: c->c = 0; break; case 0x4F: c->c = 1; break;
    case 0x51: push(c, c->pc); c->pc = (c->iptr << 11) | 0x22; break;   /* vectors are IPTR-relative (8.2.2) */
    case 0x52: push(c, c->pc); c->pc = (c->iptr << 11) | 0x24; c->intm = 1; break;
    case 0x58: c->preg = 0; break;
    case 0x59: c->acc = 0; c->preg = 0; break;
    case 0x5A: if (c->treg1 & 0x10) c->acc = c->sxm ? (uint32_t)((int32_t)c->acc >> 16) : c->acc >> 16; break;   /* SATH */
    case 0x5B: t = c->treg1 & 0xF; c->acc = c->sxm ? (uint32_t)((int32_t)c->acc >> t) : c->acc >> t; break;      /* SATL */
    case 0x80: imm = fetch(c); c->preg = (int32_t)(int16_t)c->treg0 * (int32_t)(int16_t)imm; break;
    case 0x81: imm = fetch(c); c->acc &= (uint32_t)imm << 16; break;
    case 0x82: imm = fetch(c); c->acc |= (uint32_t)imm << 16; break;
    case 0x83: imm = fetch(c); c->acc ^= (uint32_t)imm << 16; break;
    case 0xC4: c->rptc = fetch(c); c->rpt_start = c->rpt_end = c->pc; break;
    case 0xC5: c->rptc = fetch(c); c->rpt_start = c->rpt_end = c->pc; c->acc = 0; c->preg = 0; break;
    case 0xC6: imm = fetch(c); c->braf = 1; c->pasr = c->pc; c->paer = imm; break;   /* PAER = operand = address of the last loop word (4.7, Example 4-8: RPTB END_LOOP-1) */
    default:
        if ((op & 0xe0) == 0x60) {                                                                  /* INTR k */
            uint16_t v = (op & 0x1f) << 1; int i;
            push(c, c->pc); c->intm = 1; c->pc = (c->iptr << 11) | v;
            if (v == 0x02 || v == 0x04 || v == 0x06 || v == 0x12) save_ctx(c);          /* INTR for INT1-INT4 (K=1,2,3,9) behaves like the external interrupt, context shadow included (4.8.7) */
            for (i = 0; i < 9; i++) if (ivec[i] == v && c->ivec_ind[i]) { c->pc = dm_rd(c, c->ivec_ind[i]); save_ctx(c); break; }
            if (i == 9) for (i = 0; i < 9; i++) if (ivec_legacy[i] == v && c->ivec_ind[i]) { c->pc = dm_rd(c, c->ivec_ind[i]); save_ctx(c); break; }
            break; }
        c->status = RUN_BADOP;
    }
}

static void exec_bf(C5x *c) {
    uint16_t op = c->op, imm; int sh = op & 0xf; int32_t d;
    switch (op & 0xff) {
    case 0x00: case 0x01: case 0x02: case 0x03: c->pm = op & 3; break;
    case 0x08: case 0x09: case 0x0A: case 0x0B: case 0x0C: case 0x0D: case 0x0E: case 0x0F:
        imm = fetch(c); c->ar[op & 7] = imm; if ((op & 7) == 0) c->ar0_dirty = 1; break;
    case 0x44: case 0x45: case 0x46: case 0x47: { uint16_t r = c->ar[c->arp]; int m = op & 3;
        uint16_t cmpv = c->cmpr_ar0 ? c->ar[0] : c->arcr;
        c->tc = m == 0 ? r == cmpv : m == 1 ? r < cmpv : m == 2 ? r > cmpv : r != cmpv; break; }
    default:
        if (op >= 0xBF80 && op <= 0xBFFF) {}
        {
            int hi = op & 0xf0;
            if (hi >= 0x80 && hi <= 0xD0) {
                imm = fetch(c);
                switch (hi) {
                case 0x80: c->acc = ext(c, imm, sh); break;
                case 0x90: c->acc = do_add(c, c->acc, ext(c, imm, sh), 0, 0); break;
                case 0xA0: c->acc = do_sub(c, c->acc, ext(c, imm, sh), 0, 0); break;
                case 0xB0: c->acc &= (uint32_t)imm << sh; break;
                case 0xC0: c->acc |= (uint32_t)imm << sh; break;
                case 0xD0: c->acc ^= (uint32_t)imm << sh; break;
                }
            } else if (hi == 0xE0) {
                sh = sh + 1; d = (int32_t)c->acc; c->acc = c->sxm ? (uint32_t)(d >> sh) : c->acc >> sh;
            } else c->status = RUN_BADOP;
        }
    }
}

/* ---------- main loop ---------- */
static inline void tick_timer(C5x *c) {
    if (c->tss) return;
    if (--c->psc < 0) { c->psc = c->tcr_tddr; if (c->tim == 0) { c->tim = c->prd; c->ifr |= 1 << 3; c->timer_exp++; } else c->tim--; }
}

/* returns RUN_* ; runs until cycle budget exhausted */
int c5x_run(C5x *c, uint64_t budget) {
    uint64_t end = c->cycles + budget;
    int first = 1;
    c->stop = 0; c->status = RUN_OK;
    while (c->cycles < end) {
        uint64_t c0 = c->cycles;
        if (c->idle) {
            if (c->ifr & c->imr & (c->idle == 2 ? 0x107 : 0xFFFF)) { c->idle = 0; check_int(c); continue; }
            /* skip forward: step 1 cycle (timer granularity); IDLE2 stops the timer */
            c->cycles++; c->idle_cycles++; if (c->idle == 1) tick_timer(c); continue;
        }
        if (c->bp[c->pc] && !first) { c->status = RUN_BP; return RUN_BP; }
        first = 0; c->status = RUN_OK;
        uint16_t ppc = c->pc; c->words = 0; int sp0 = c->sp;
        exec1(c);
        if (c->cyc_model) {                                         /* machine cycles from the manual's tables (fastest case); repeated iterations cost 1 */
            int cy = c->rep_cont ? ((c->op >> 8 == 0xAF) ? 2 : (c->op >> 8 == 0x0C) ? 3 : 1) : cycm[c->op];   /* repeated IN: 2 cycles per access (6.3: 2n + n*io), OUT: 3 (3n + n*io) */
            int seq = (uint16_t)c->pc == (uint16_t)(ppc + c->words);
            uint8_t h = c->op >> 8;
            if (h >= 0xEC && h <= 0xEF) seq = c->sp == sp0;                                 /* RETC/RET: taken = the return address was popped (TOS may equal the fall-through address) */
            if (!c->rep_cont && !seq) { if (h == 0x7B || (h >= 0xE0 && h <= 0xE3) || (h >= 0xE8 && h <= 0xEB) || (h >= 0xEC && h <= 0xEF)) cy = 4; }   /* taken BANZ/BCND/CC/RETC */
            else if (!c->rep_cont && seq && (h == 0x7B || (h >= 0xE0 && h <= 0xE3) || (h >= 0xE8 && h <= 0xEB) || (h >= 0xEC && h <= 0xEF) || (h >= 0xFC && h < 0xFF))) cy = 2;   /* not-taken conditional */
            c->cycles += cy - 1;
        }
        if (c->ar0_dirty) { if (!c->ndx) { c->indx = c->arcr = c->ar[0]; } c->ar0_dirty = 0; }   /* NDX=0 ('C2x compatible, the reset state): anything that loads/modifies AR0 also loads INDX and ARCR (audit #10, manual 6.3 LAR/MAR/SAR) */
        c->ar0_prev = c->ar[0];
        if (c->status == RUN_BADOP) { c->pc = ppc; return RUN_BADOP; }
        if (c->rptc > 0) { if (ppc == c->rpt_end) { c->pc = c->rpt_start; c->rptc--; c->rep_cont = 1; } else c->rep_cont = 0; }
        else { c->rptc = 0; c->rep_cont = 0; }
        if (c->braf && (uint16_t)(c->pc - 1) == c->paer) {      /* the last loop word has just executed (PC is already past it); done before the interrupt check so an ISR sees BRAF and the return address after the loop-end test (4.7) */
            if (c->brcr > 0) { c->pc = c->pasr; c->brcr--; }       /* BRCR > 0: decrement and restart; BRCR = 0: leave the loop with BRCR still 0 and BRAF cleared (4.7) */
            else c->braf = 0;
        }
        for (uint64_t k = c0; k < c->cycles; k++) tick_timer(c);
        int xc_hold = 0; if (c->xc_new) { c->xc_new = 0; xc_hold = 1; } else if (c->xc_left > 0) c->xc_left -= c->words;
        if (c->xc_left > 0) xc_hold = 1; else c->xc_left = 0;
        if (c->braf && c->pc == c->paer) xc_hold = 1;                  /* 4.7.2: the single-word instruction at the end of a repeat block is not interruptible */
        if (c->int_inh) c->int_inh = 0; else if (xc_hold) { } else if (c->rptc <= 0 && !c->rep_cont) check_int(c);      /* a single-instruction RPT repeat is not interruptible on the real C5x */
        if (c->stop) return RUN_STOP;
    }
    return RUN_OK;
}

/* serial-port frame tick: one codec sample period elapsed. rx = ADC sample delivered to DRR. */
void c5x_serial_tick(C5x *c, int16_t rx) {
    if (c->spc & 0x80) {                                    /* receiver enabled (RRST=1) */
        if (c->rrdy || c->rsrfull) c->rsrfull = 1;          /* previous word not read before the next one arrived: overrun; the receiver halts until DRR is read, the new word is lost (9.7) */
        else {
            c->drr = (c->spc & 0x02) ? c->dxr : (uint16_t)rx;   /* DLB: DX looped back to DR */
            c->rrdy = 1; c->ifr |= (1 << 4);                    /* RINT */
        }
    }
    if (c->spc & 0x40) {                                    /* transmitter enabled (XRST=1) */
        int dxr_pending = !c->xrdy;                         /* DXR was written since the previous frame */
        if (!dxr_pending) c->xsrempty = 0;                  /* underflow */
        c->xrdy = 1;
        if (!c->xint_mode || dxr_pending || c->xint_first) { c->ifr |= (1 << 5); c->xint_first = 0; }   /* XINT: legacy = every tick; mode 1 = only after a DXR write (plus one initial kick) */
    }
}
void c5x_set_xint_mode(C5x *c, int m) { c->xint_mode = m; c->xint_first = 1; }
void c5x_set_cycle_model(C5x *c, int m) { c->cyc_model = m; }
void c5x_set_legacy(C5x *c, int m) { c->legacy = m; }   /* API stub: nothing reads `legacy` any more */
uint64_t c5x_idle_cycles(C5x *c) { return c->idle_cycles; }
uint64_t c5x_timer_expiries(C5x *c) { return c->timer_exp; }   /* TIM reached 0 (TOUT pulses): the board's host heartbeat (INT0, 2401 Hz measured) follows these */
uint64_t c5x_total_cycles(C5x *c) { return c->cycles; }

void c5x_set_ivec_ind(C5x *c, int bit, uint16_t daddr) { c->ivec_ind[bit] = daddr; }

void c5x_set_cmpr_ar0(C5x *c, int v) { c->cmpr_ar0 = v; }

uint32_t c5x_dxr_head(C5x *c) { return c->dxr_head; }
uint16_t *c5x_dxr_ring(C5x *c) { return c->dxr_ring; }

void c5x_set_watch(C5x *c, int32_t a) { c->watch_a = a; memset(c->watch_hits, 0, sizeof c->watch_hits); }
uint32_t c5x_watch_hits(C5x *c, uint32_t pc) { return c->watch_hits[pc & 0xFFFF]; }
uint32_t c5x_pc_hits(C5x *c, uint32_t pc) { return c->pc_hits[pc & 0xFFFF]; }
void c5x_pc_hits_clear(C5x *c) { memset(c->pc_hits, 0, sizeof c->pc_hits); }
void c5x_set_trace(C5x *c, int32_t pc) { c->trace_pc = pc; c->trace_n = 0; }
uint32_t c5x_trace_n(C5x *c) { return c->trace_n; }
void c5x_trace_get(C5x *c, uint32_t i, uint32_t *acc, uint16_t *ret, uint16_t *ret2) { *acc = c->trace_buf[i].acc; *ret = c->trace_buf[i].ret; *ret2 = c->trace_buf[i].ret2; }

uint32_t c5x_mmr_count(C5x *c, int wr, int a) { return c->mmr_n[wr][a]; }
uint16_t c5x_mmr_pc(C5x *c, int wr, int a) { return c->mmr_pc[wr][a]; }
void c5x_mmr_clear(C5x *c) { memset(c->mmr_n, 0, sizeof c->mmr_n); }
uint16_t c5x_mmr_val(C5x *c, int a) { return c->mmr_val[a]; }
uint32_t c5x_ff_count(C5x *c, int wr, int i) { return c->ff_n[wr][i & 255]; }
uint32_t c5x_ext_count(C5x *c, int wr, int blk) { return c->ext_n[wr][blk]; }
uint16_t c5x_rsv(C5x *c, int w) { return w ? c->rsv_pc : c->rsv_a; }
