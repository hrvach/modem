/* Compact 80186 (8086 + 186 extensions) interpreter for the SV25 full-system study.
 * Build: gcc -O2 -shared -fPIC -o libi186.so i186.c
 * 1 MB physical space, 16-bit I/O space, callback hooks for memory-mapped pages and I/O.
 * Peripherals (PCB timers/PIC/DMA, UART, DSP mailbox) live outside, in Python.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef uint32_t (*io_rd_fn)(void *ctx, uint16_t port, int w);
typedef void (*io_wr_fn)(void *ctx, uint16_t port, int w, uint32_t v);
typedef uint32_t (*mm_rd_fn)(void *ctx, uint32_t addr, int w);
typedef void (*mm_wr_fn)(void *ctx, uint32_t addr, int w, uint32_t v);

enum { AX, CX, DX, BX, SP, BP, SI, DI };
enum { ES, CS, SS, DS };
enum { ST_OK = 0, ST_BP = 1, ST_BADOP = 2, ST_HLT = 3, ST_STOP = 4 };

typedef struct {
    uint16_t r[8], sr[4], ip;
    int cf, pf, af, zf, sf, tf, ifl, df, of;
    uint8_t *mem;
    uint8_t mmpage[256];                 /* 4 KB pages with MMIO hooks */
    uint8_t ro[256];                     /* 4 KB pages that ignore writes (flash) */
    io_rd_fn io_rd; io_wr_fn io_wr; mm_rd_fn mm_rd; mm_wr_fn mm_wr; void *ctx;
    uint16_t *ioarr;
    int halted, status, stop;
    int irq_pending, irq_vec;            /* external maskable interrupt request */
    int nmi_pending;                     /* latched NMI (type 2) */
    int inh;                             /* interrupt shadow: set by STI / segment-register loads, covers the next instruction */
    uint16_t pstart;                     /* IP of the first prefix byte of the running instruction (REP restart) */
    int ud_trap;                         /* 1 = an undefined opcode raises type 6 (invalid opcode, IP = the faulting instruction) instead of stopping with ST_BADOP */
    int rep_resume;                      /* a REP string loop yielded and is being resumed (no second start-up charge) */
    uint64_t run_end;                    /* cycle budget end of the current i186_run (REP string loops stop there and resume) */
    double cscale, cfrac;                /* CPU speed knob: charged clocks per instruction are multiplied by cscale (1.0 = manual Table D-2) */
    int cyc_model;                       /* 0 = legacy flat 4 cycles/instruction, 1 = approximate 80C186 clock counts */
    uint64_t cycles;
    uint32_t *hits;
    uint32_t ring[256], ring_i;
    uint8_t *bp;
    uint32_t cur_pc;
    /* instruction decode state */
    int seg_ovr, rep, repz; uint8_t opc;
    int mod, regf, rmf;
    uint16_t ea_seg, ea_off;
    uint32_t last_badop_pc; uint8_t last_badop;
    uint32_t unmapped_log[64]; int unmapped_n;
} C;

static const uint8_t PAR[256] = {
#define P2(n) n, n ^ 1, n ^ 1, n
#define P4(n) P2(n), P2(n ^ 1), P2(n ^ 1), P2(n)
#define P6(n) P4(n), P4(n ^ 1), P4(n ^ 1), P4(n)
    P6(1), P6(0), P6(0), P6(1)
};

/* approximate 80C186 clock counts per opcode (register forms); decode_modrm adds 6 for a memory operand,
 * taken branches, multiplies/divides, indirect calls and interrupt entry add their extra where executed */
static const uint8_t CYC[256] = {
     3,  3,  3,  3,  3,  4,  9,  8,  3,  3,  3,  3,  3,  4,  9,  3,
     3,  3,  3,  3,  3,  4,  9,  8,  3,  3,  3,  3,  3,  4,  9,  8,
     3,  3,  3,  3,  3,  4,  3,  4,  3,  3,  3,  3,  3,  4,  3,  4,
     3,  3,  3,  3,  3,  4,  3,  7,  3,  3,  3,  3,  3,  4,  3,  7,
     3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,
    10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10,
    36, 51, 27,  3,  3,  3,  3,  3, 10, 24, 10, 24,  5,  5,  5,  5,
     4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,
     4,  4,  4,  4,  3,  3,  4,  4,  2,  2,  2,  2,  2,  0,  2, 14,
     3,  3,  3,  3,  3,  3,  3,  3,  2,  4, 23,  3,  9,  8,  3,  2,
     9,  9,  8,  8,  5,  5,  5,  5,  3,  3,  5,  5,  5,  5,  5,  5,
     3,  3,  3,  3,  3,  3,  3,  3,  4,  4,  4,  4,  4,  4,  4,  4,
     6,  6, 18, 16, 12, 12,  6,  6, 15,  8, 25, 22,  3,  5,  3, 28,
     4,  4,  4,  4, 19, 15,  3, 11,  3,  3,  3,  3,  3,  3,  3,  3,
     6,  6,  6,  6, 10, 10,  9,  9, 15, 14, 14, 14,  8,  8,  7,  7,
     3,  3,  3,  3,  2,  2,  3,  3,  2,  2,  2,  2,  2,  2,  3,  3,
};

C *i186_new(void) {
    C *c = calloc(1, sizeof *c);
    if (!c) return NULL;
    c->cscale = 1.0;
    c->mem = calloc(1 << 20, 1); c->hits = calloc(1 << 20, 4); c->bp = calloc(1 << 20, 1);
    c->ioarr = calloc(65536, 2); c->seg_ovr = -1;
    if (!c->mem || !c->hits || !c->bp || !c->ioarr) { free(c->mem); free(c->hits); free(c->bp); free(c->ioarr); free(c); return NULL; }
    return c;
}
void i186_free(C *c) { if (!c) return; free(c->mem); free(c->hits); free(c->bp); free(c->ioarr); free(c); }
uint8_t *i186_mem(C *c) { return c->mem; }
uint32_t *i186_hits(C *c) { return c->hits; }
uint32_t *i186_ring(C *c) { return c->ring; }
uint32_t i186_ring_idx(C *c) { return c->ring_i; }
uint16_t *i186_ioarr(C *c) { return c->ioarr; }
void i186_set_hooks(C *c, io_rd_fn ir, io_wr_fn iw, mm_rd_fn mr, mm_wr_fn mw, void *ctx) { c->io_rd = ir; c->io_wr = iw; c->mm_rd = mr; c->mm_wr = mw; c->ctx = ctx; }
void i186_set_mmio_page(C *c, uint32_t page, int on) { if (page < 256) c->mmpage[page] = on; }
void i186_set_ro_page(C *c, uint32_t page, int on) { if (page < 256) c->ro[page] = on; }
void i186_set_bp(C *c, uint32_t phys, int on) { if (phys < 0x100000) c->bp[phys] = on; }
void i186_stop(C *c) { c->stop = 1; }
void i186_irq(C *c, int vec) { c->irq_pending = 1; c->irq_vec = vec & 0xFF; }
void i186_nmi(C *c) { c->nmi_pending = 1; }
void i186_irq_clear(C *c) { c->irq_pending = 0; }
int i186_irq_pending(C *c) { return c->irq_pending; }
void i186_set_ud_trap(C *c, int m) { c->ud_trap = m; }
void i186_set_cycle_model(C *c, int m) { c->cyc_model = m; }
void i186_set_cycle_scale(C *c, double f) { c->cscale = f > 0 ? f : 1.0; c->cfrac = 0; }
uint64_t i186_cycles(C *c) { return c->cycles; }
void i186_add_cycles(C *c, uint64_t n) { c->cycles += n; }
uint32_t i186_get_badop(C *c) { return c->last_badop_pc | ((uint32_t)c->last_badop << 24); }

static uint16_t flags_get(C *c) {
    return 0xF002 | c->cf | (c->pf << 2) | (c->af << 4) | (c->zf << 6) | (c->sf << 7) | (c->tf << 8) | (c->ifl << 9) | (c->df << 10) | (c->of << 11);
}
static void flags_set(C *c, uint16_t f) {
    c->cf = f & 1; c->pf = (f >> 2) & 1; c->af = (f >> 4) & 1; c->zf = (f >> 6) & 1; c->sf = (f >> 7) & 1;
    c->tf = (f >> 8) & 1; c->ifl = (f >> 9) & 1; c->df = (f >> 10) & 1; c->of = (f >> 11) & 1;
}
enum { R_AX, R_CX, R_DX, R_BX, R_SP, R_BP, R_SI, R_DI, R_ES, R_CS, R_SS, R_DS, R_IP, R_FLAGS };
uint32_t i186_get(C *c, int id) {
    if (id < 0) return 0;
    if (id < 8) return c->r[id];
    if (id < 12) return c->sr[id - 8];
    if (id == R_IP) return c->ip;
    if (id == R_FLAGS) return flags_get(c);
    return 0;
}
void i186_set(C *c, int id, uint32_t v) {
    if (id < 0) return;
    if (id < 8) c->r[id] = v; else if (id < 12) c->sr[id - 8] = v; else if (id == R_IP) c->ip = v; else if (id == R_FLAGS) flags_set(c, v);
}
void i186_reset(C *c) {
    memset(c->r, 0, sizeof c->r); memset(c->sr, 0, sizeof c->sr);
    c->sr[CS] = 0xFFFF; c->ip = 0x0000; flags_set(c, 0x0002); c->halted = 0; c->cycles = 0;   /* manual reset state; same linear start 0xFFFF0 */
    c->irq_pending = c->nmi_pending = c->inh = 0; c->irq_vec = 0;
}

/* ---------------- memory ---------------- */
static inline uint32_t lin(uint16_t seg, uint16_t off) { return (((uint32_t)seg << 4) + off) & 0xFFFFF; }
/* A word access whose two bytes fall on pages that route differently (MMIO hook / read-only / RAM) is performed as two byte
 * accesses, each through its own page's rule; same-routing words keep the single word call to the hook. */
static inline int split_word(C *c, uint32_t a, uint32_t b) {
    uint32_t pa = a >> 12, pb = b >> 12;
    return pa != pb && ((c->mmpage[pa] != c->mmpage[pb]) || (c->ro[pa] != c->ro[pb]));
}
static uint32_t mrd(C *c, uint32_t a, int w) {
    a &= 0xFFFFF;
    if (w) { uint32_t b = (a + 1) & 0xFFFFF; if (split_word(c, a, b)) return mrd(c, a, 0) | (mrd(c, b, 0) << 8); }
    if (c->mmpage[a >> 12] && c->mm_rd) return c->mm_rd(c->ctx, a, w);
    if (w) return c->mem[a] | (c->mem[(a + 1) & 0xFFFFF] << 8);
    return c->mem[a];
}
static void mwr(C *c, uint32_t a, int w, uint32_t v) {
    a &= 0xFFFFF;
    if (w) { uint32_t b = (a + 1) & 0xFFFFF; if (split_word(c, a, b)) { mwr(c, a, 0, v); mwr(c, b, 0, v >> 8); return; } }
    if (c->mmpage[a >> 12] && c->mm_wr) { c->mm_wr(c->ctx, a, w, v); return; }
    if (c->ro[a >> 12]) return;
    c->mem[a] = v; if (w) c->mem[(a + 1) & 0xFFFFF] = v >> 8;
}
static inline uint8_t fetch8(C *c) { uint8_t v = mrd(c, lin(c->sr[CS], c->ip), 0); c->ip++; return v; }
static inline uint16_t fetch16(C *c) { uint16_t v = fetch8(c); v |= fetch8(c) << 8; return v; }
static inline void push16(C *c, uint16_t v) { c->r[SP] -= 2; mwr(c, lin(c->sr[SS], c->r[SP]), 1, v); }
static inline uint16_t pop16(C *c) { uint16_t v = mrd(c, lin(c->sr[SS], c->r[SP]), 1); c->r[SP] += 2; return v; }
static uint32_t io_read(C *c, uint16_t p, int w) { if (c->io_rd) return c->io_rd(c->ctx, p, w); return c->ioarr[p]; }
static void io_write(C *c, uint16_t p, int w, uint32_t v) { if (c->io_wr) c->io_wr(c->ctx, p, w, v); else c->ioarr[p] = w ? v : (c->ioarr[p] & 0xFF00) | (v & 0xFF); }

/* ---------------- registers ---------------- */
static inline uint32_t getreg(C *c, int n, int w) { if (w) return c->r[n]; return n < 4 ? (c->r[n] & 0xFF) : (c->r[n - 4] >> 8); }
static inline void setreg(C *c, int n, int w, uint32_t v) {
    if (w) c->r[n] = v; else if (n < 4) c->r[n] = (c->r[n] & 0xFF00) | (v & 0xFF); else c->r[n - 4] = (c->r[n - 4] & 0xFF) | ((v & 0xFF) << 8);
}
static inline uint32_t MASK(int w) { return w ? 0xFFFF : 0xFF; }
static inline uint32_t MSB(int w) { return w ? 0x8000 : 0x80; }

/* extra clocks of the memory form over (register form + 6), from 80C186EB manual Table D-2 (16-bit, fastest case) */
static int memextra(uint8_t op, int reg) {
    switch (op) {
    case 0x88: case 0x89: return 4;                        /* MOV r/m,r 12 */
    case 0x8A: case 0x8B: case 0x8E: return 1;             /* MOV r,r/m / sreg,r/m 9 */
    case 0x8C: return 3;                                   /* MOV r/m,sreg 11 */
    case 0xC7: return 1;                                   /* MOV r/m,imm16 13 */
    case 0x80: case 0x81: case 0x82: case 0x83: return reg == 7 ? 0 : 6;   /* ALU imm,r/m read-modify-write 16 (CMP 10) */
    case 0xFE: return reg < 2 ? 6 : 0;                     /* INC/DEC r/m 15 */
    case 0xFF: return reg < 2 ? 6 : reg == 6 ? 7 : 0;      /* INC/DEC r/m 15, PUSH r/m 16 */
    case 0x86: case 0x87: return 7;                        /* XCHG r/m,r 17 */
    case 0x84: case 0x85: return 1;                        /* TEST r/m,r 10 */
    case 0xF6: case 0xF7: return reg < 2 ? 1 : 0;          /* TEST r/m,imm 10 */
    }
    if (op < 0x40 && (op & 7) < 4) return 1;               /* ALU r/m,r and r,r/m 10 */
    return 0;
}

/* ---------------- modrm ---------------- */
static void decode_modrm(C *c) {
    uint8_t m = fetch8(c); c->mod = m >> 6; c->regf = (m >> 3) & 7; c->rmf = m & 7;
    if (c->mod == 3) return;
    if (c->cyc_model) c->cycles += 6 + memextra(c->opc, c->regf);   /* memory operand: EA + bus cycle, plus the per-form difference to Table D-2 */
    uint16_t off = 0; int dseg = DS;
    switch (c->rmf) {
    case 0: off = c->r[BX] + c->r[SI]; break; case 1: off = c->r[BX] + c->r[DI]; break;
    case 2: off = c->r[BP] + c->r[SI]; dseg = SS; break; case 3: off = c->r[BP] + c->r[DI]; dseg = SS; break;
    case 4: off = c->r[SI]; break; case 5: off = c->r[DI]; break;
    case 6: if (c->mod == 0) { off = fetch16(c); } else { off = c->r[BP]; dseg = SS; } break;
    case 7: off = c->r[BX]; break;
    }
    if (c->mod == 1) off += (int8_t)fetch8(c); else if (c->mod == 2) off += fetch16(c);
    c->ea_off = off; c->ea_seg = c->sr[c->seg_ovr >= 0 ? c->seg_ovr : dseg];
}
static uint32_t rm_rd(C *c, int w) { return c->mod == 3 ? getreg(c, c->rmf, w) : mrd(c, lin(c->ea_seg, c->ea_off), w); }
static void rm_wr(C *c, int w, uint32_t v) { if (c->mod == 3) setreg(c, c->rmf, w, v); else mwr(c, lin(c->ea_seg, c->ea_off), w, v); }

/* ---------------- ALU ---------------- */
static inline void szp(C *c, uint32_t r, int w) { r &= MASK(w); c->zf = r == 0; c->sf = !!(r & MSB(w)); c->pf = PAR[r & 0xFF]; }
static uint32_t alu(C *c, int op, uint32_t a, uint32_t b, int w) {
    uint32_t m = MASK(w), r;
    switch (op) {
    case 0: case 2: { uint32_t ci = op == 2 ? c->cf : 0; r = a + b + ci; c->cf = r > m; c->af = ((a ^ b ^ r) >> 4) & 1; c->of = ((a ^ r) & (b ^ r) & MSB(w)) != 0; break; }
    case 5: case 7: case 3: { uint32_t ci = op == 3 ? c->cf : 0; r = a - b - ci; c->cf = a < b + ci; c->af = ((a ^ b ^ r) >> 4) & 1; c->of = ((a ^ b) & (a ^ r) & MSB(w)) != 0; break; }
    case 1: r = a | b; c->cf = c->of = 0; break;
    case 4: r = a & b; c->cf = c->of = 0; break;
    default: r = a ^ b; c->cf = c->of = 0; break;
    }
    szp(c, r, w); return r & m;
}
static uint32_t incdec(C *c, uint32_t a, int dec, int w) {
    uint32_t r = dec ? a - 1 : a + 1; int cf = c->cf;
    c->of = dec ? (a == MSB(w)) : (a == MSB(w) - 1); c->af = ((a ^ 1 ^ r) >> 4) & 1; szp(c, r, w); c->cf = cf; return r & MASK(w);
}
static uint32_t shift(C *c, int op, uint32_t v, int n, int w) {
    int bits = w ? 16 : 8; uint32_t m = MASK(w); n &= 0x1F; if (!n) return v; v &= m; uint32_t r = v;
    switch (op) {
    case 0: { int k = n % bits; r = k ? ((v << k) | (v >> (bits - k))) & m : v; c->cf = r & 1; if (n == 1) c->of = ((r & MSB(w)) != 0) ^ c->cf; return r; }
    case 1: { int k = n % bits; r = k ? ((v >> k) | (v << (bits - k))) & m : v; c->cf = !!(r & MSB(w)); if (n == 1) c->of = ((r ^ (r << 1)) & MSB(w)) != 0; return r; }
    case 2: { for (int i = 0; i < n; i++) { int ncf = !!(r & MSB(w)); r = ((r << 1) | c->cf) & m; c->cf = ncf; } if (n == 1) c->of = ((r & MSB(w)) != 0) ^ c->cf; return r; }
    case 3: { if (n == 1) c->of = ((r & MSB(w)) != 0) ^ c->cf; for (int i = 0; i < n; i++) { int ncf = r & 1; r = (r >> 1) | (c->cf ? MSB(w) : 0); c->cf = ncf; } return r; }
    case 4: case 6: { if (n > bits) { c->cf = 0; r = 0; } else { c->cf = (v >> (bits - n)) & 1; r = (v << n) & m; } if (n == 1) c->of = ((r & MSB(w)) != 0) ^ c->cf; szp(c, r, w); c->af = 0; return r; }
    case 5: { c->cf = (n > bits) ? 0 : (v >> (n - 1)) & 1; r = n >= bits ? 0 : v >> n; if (n == 1) c->of = (v & MSB(w)) != 0; szp(c, r, w); c->af = 0; return r; }
    default: { int32_t sv = w ? (int16_t)v : (int8_t)v; int k = n >= bits ? bits - 1 : n; c->cf = (sv >> (n > bits ? bits - 1 : n - 1)) & 1; r = (uint32_t)(sv >> k) & m; c->of = 0; szp(c, r, w); c->af = 0; return r; }
    }
}

static void do_int(C *c, int vec) {
    if (c->cyc_model) c->cycles += 42;
    push16(c, flags_get(c)); push16(c, c->sr[CS]); push16(c, c->ip);
    c->ifl = 0; c->tf = 0;
    c->ip = mrd(c, vec * 4, 1); c->sr[CS] = mrd(c, vec * 4 + 2, 1);
}
static int cond(C *c, int cc) {
    int r;
    switch (cc >> 1) {
    case 0: r = c->of; break; case 1: r = c->cf; break; case 2: r = c->zf; break; case 3: r = c->cf || c->zf; break;
    case 4: r = c->sf; break; case 5: r = c->pf; break; case 6: r = c->sf != c->of; break; default: r = c->zf || (c->sf != c->of); break;
    }
    return (cc & 1) ? !r : r;
}

static int bad(C *c, uint8_t op) { c->status = ST_BADOP; c->last_badop = op; c->last_badop_pc = c->cur_pc; return 0; }

static void strop(C *c, uint8_t op) {
    int w = op & 1; int step = (w ? 2 : 1) * (c->df ? -1 : 1);
    int useseg = c->seg_ovr >= 0 ? c->seg_ovr : DS;
    int rep = c->rep, zrep = c->repz;
    uint32_t cnt = rep ? c->r[CX] : 1; int first_it = 1; int resumed = c->rep_resume; c->rep_resume = 0;
    while (cnt) {
        switch (op & 0xFE) {
        case 0xA4: mwr(c, lin(c->sr[ES], c->r[DI]), w, mrd(c, lin(c->sr[useseg], c->r[SI]), w)); c->r[SI] += step; c->r[DI] += step; break;
        case 0xA6: { uint32_t a = mrd(c, lin(c->sr[useseg], c->r[SI]), w), b = mrd(c, lin(c->sr[ES], c->r[DI]), w); alu(c, 7, a, b, w); c->r[SI] += step; c->r[DI] += step; break; }
        case 0xAA: mwr(c, lin(c->sr[ES], c->r[DI]), w, getreg(c, AX, w)); c->r[DI] += step; break;
        case 0xAC: setreg(c, AX, w, mrd(c, lin(c->sr[useseg], c->r[SI]), w)); c->r[SI] += step; break;
        case 0xAE: { uint32_t b = mrd(c, lin(c->sr[ES], c->r[DI]), w); alu(c, 7, getreg(c, AX, w), b, w); c->r[DI] += step; break; }
        case 0x6C: mwr(c, lin(c->sr[ES], c->r[DI]), w, io_read(c, c->r[DX], w)); c->r[DI] += step; break;
        case 0x6E: io_write(c, c->r[DX], w, mrd(c, lin(c->sr[useseg], c->r[SI]), w)); c->r[SI] += step; break;
        }
        if (c->cyc_model) {                                  /* App. D: single / per-iteration clocks (opcode base already charged) */
            static const uint8_t one[8] = { 14, 22, 10, 12, 15, 0, 14, 14 }, per[8] = { 8, 22, 9, 11, 15, 0, 8, 8 };
            int k = (op & 0xFE) == 0xA4 ? 0 : (op & 0xFE) == 0xA6 ? 1 : (op & 0xFE) == 0xAA ? 2 : (op & 0xFE) == 0xAC ? 3 : (op & 0xFE) == 0xAE ? 4 : (op & 0xFE) == 0x6C ? 6 : 7;
            static const uint8_t setup[8] = { 8, 5, 6, 6, 5, 0, 8, 8 };   /* rep: 8+8n MOVS/INS/OUTS, 5+22n CMPS, 5+15n SCAS, 6+11n LODS, 6+9n STOS */
            c->cycles += (rep ? per[k] + (first_it && !resumed ? setup[k] : 0) : one[k]) - (first_it ? CYC[op] : 0); first_it = 0;
        } else c->cycles += 4;
        if (rep) { c->r[CX]--; cnt = c->r[CX]; if ((op & 0xFE) == 0xA6 || (op & 0xFE) == 0xAE) { if (zrep ? !c->zf : c->zf) break; }
            if (cnt && (c->nmi_pending || (c->irq_pending && c->ifl) || (c->cyc_model && c->cycles >= c->run_end))) { c->ip = c->pstart; c->rep_resume = 1; return; } }   /* interruptible between iterations; resumes with the reduced CX. Also yields when the cycle budget is used up, so the DSP and the codec clock keep running during a long block move */
        else cnt = 0;
    }
}

static void exec1(C *c) {
    uint32_t pc0 = lin(c->sr[CS], c->ip);
    c->pstart = c->ip; c->cur_pc = pc0; c->hits[pc0]++; c->ring[c->ring_i++ & 255] = pc0;
    c->seg_ovr = -1; c->rep = 0; c->repz = 0;
    uint8_t op;
    for (;;) {
        op = fetch8(c);
        if (op == 0x26) c->seg_ovr = ES; else if (op == 0x2E) c->seg_ovr = CS; else if (op == 0x36) c->seg_ovr = SS; else if (op == 0x3E) c->seg_ovr = DS;
        if (c->cyc_model && (op == 0x26 || op == 0x2E || op == 0x36 || op == 0x3E || op == 0xF0)) c->cycles += 2;   /* prefix: 2 clocks */
        else if (op == 0xF2) { c->rep = 1; c->repz = 0; } else if (op == 0xF3) { c->rep = 1; c->repz = 1; } else if (op == 0xF0) {} else break;
    }
    c->opc = op;
    c->cycles += c->cyc_model ? CYC[op] : 4;
    int w = op & 1;
    if (op < 0x40 && (op & 7) < 6) {                       /* ALU forms */
        int aop = op >> 3;
        switch (op & 7) {
        case 0: case 1: { decode_modrm(c); uint32_t a = rm_rd(c, w), b = getreg(c, c->regf, w); uint32_t r = alu(c, aop, a, b, w); if (aop != 7) rm_wr(c, w, r); break; }
        case 2: case 3: { decode_modrm(c); uint32_t a = getreg(c, c->regf, w), b = rm_rd(c, w); uint32_t r = alu(c, aop, a, b, w); if (aop != 7) setreg(c, c->regf, w, r); break; }
        case 4: { uint32_t r = alu(c, aop, getreg(c, AX, 0), fetch8(c), 0); if (aop != 7) setreg(c, AX, 0, r); break; }
        case 5: { uint32_t r = alu(c, aop, c->r[AX], fetch16(c), 1); if (aop != 7) c->r[AX] = r; break; }
        }
        return;
    }
    switch (op) {
    case 0x06: push16(c, c->sr[ES]); break; case 0x0E: push16(c, c->sr[CS]); break; case 0x16: push16(c, c->sr[SS]); break; case 0x1E: push16(c, c->sr[DS]); break;
    case 0x07: c->sr[ES] = pop16(c); c->inh = 1; break; case 0x17: c->sr[SS] = pop16(c); c->inh = 1; break; case 0x1F: c->sr[DS] = pop16(c); c->inh = 1; break;
    /* DAA/DAS follow the 8086-family silicon: the +-6 adjust carries/borrows into CF, the second test looks at the adjusted AL (> 0x9F) */
    case 0x27: { int al = c->r[AX] & 0xFF, cf = c->cf; if ((al & 0xF) > 9 || c->af) { al += 6; cf |= al > 0xFF; al &= 0xFF; c->af = 1; } else c->af = 0; if (al > 0x9F || cf) { al = (al + 0x60) & 0xFF; cf = 1; } c->cf = cf; setreg(c, AX, 0, al); szp(c, al, 0); break; }
    case 0x2F: { int al = c->r[AX] & 0xFF, cf = c->cf; if ((al & 0xF) > 9 || c->af) { cf |= al < 6; al = (al - 6) & 0xFF; c->af = 1; } else c->af = 0; if (al > 0x9F || cf) { al = (al - 0x60) & 0xFF; cf = 1; } c->cf = cf; setreg(c, AX, 0, al); szp(c, al, 0); break; }
    /* AAA/AAS adjust AL and AH separately (AL +-6 does not carry into the AH adjust) */
    case 0x37: if ((c->r[AX] & 0xF) > 9 || c->af) { c->r[AX] = ((c->r[AX] & 0xFF00) + 0x100) | ((c->r[AX] + 6) & 0xFF); c->af = c->cf = 1; } else c->af = c->cf = 0; c->r[AX] &= 0xFF0F; break;
    case 0x3F: if ((c->r[AX] & 0xF) > 9 || c->af) { c->r[AX] = ((c->r[AX] & 0xFF00) - 0x100) | ((c->r[AX] - 6) & 0xFF); c->af = c->cf = 1; } else c->af = c->cf = 0; c->r[AX] &= 0xFF0F; break;
    case 0x40: case 0x41: case 0x42: case 0x43: case 0x44: case 0x45: case 0x46: case 0x47: c->r[op & 7] = incdec(c, c->r[op & 7], 0, 1); break;
    case 0x48: case 0x49: case 0x4A: case 0x4B: case 0x4C: case 0x4D: case 0x4E: case 0x4F: c->r[op & 7] = incdec(c, c->r[op & 7], 1, 1); break;
    case 0x50: case 0x51: case 0x52: case 0x53: case 0x55: case 0x56: case 0x57: push16(c, c->r[op & 7]); break;
    case 0x54: { uint16_t v = c->r[SP]; push16(c, v); break; }                    /* 80186 (unlike the 8086) pushes the SP value from before the instruction; sibling courier-emu agrees */
    case 0x58: case 0x59: case 0x5A: case 0x5B: case 0x5D: case 0x5E: case 0x5F: c->r[op & 7] = pop16(c); break;
    case 0x5C: c->r[SP] = pop16(c); break;
    case 0x60: { uint16_t sp = c->r[SP]; push16(c, c->r[AX]); push16(c, c->r[CX]); push16(c, c->r[DX]); push16(c, c->r[BX]); push16(c, sp); push16(c, c->r[BP]); push16(c, c->r[SI]); push16(c, c->r[DI]); break; }
    case 0x61: c->r[DI] = pop16(c); c->r[SI] = pop16(c); c->r[BP] = pop16(c); pop16(c); c->r[BX] = pop16(c); c->r[DX] = pop16(c); c->r[CX] = pop16(c); c->r[AX] = pop16(c); break;
    case 0x62: { decode_modrm(c); if (c->mod == 3) return (void)bad(c, op); int16_t i = c->r[c->regf]; int16_t lo = mrd(c, lin(c->ea_seg, c->ea_off), 1), hi = mrd(c, lin(c->ea_seg, c->ea_off + 2), 1); if (i < lo || i > hi) do_int(c, 5); break; }   /* type 5 is a trap: return address = next instruction */
    case 0x68: push16(c, fetch16(c)); break;
    case 0x6A: push16(c, (int16_t)(int8_t)fetch8(c)); break;
    case 0x69: case 0x6B: { decode_modrm(c); int32_t a = (int16_t)rm_rd(c, 1); int32_t b = op == 0x69 ? (int16_t)fetch16(c) : (int8_t)fetch8(c); int32_t r = a * b; c->r[c->regf] = r; c->cf = c->of = (r != (int16_t)r); break; }
    case 0x6C: case 0x6D: case 0x6E: case 0x6F: strop(c, op); break;
    case 0x70: case 0x71: case 0x72: case 0x73: case 0x74: case 0x75: case 0x76: case 0x77:
    case 0x78: case 0x79: case 0x7A: case 0x7B: case 0x7C: case 0x7D: case 0x7E: case 0x7F: { int8_t d = fetch8(c); if (cond(c, op & 0xF)) { c->ip += d; c->cycles += c->cyc_model ? 9 : 12; } break; }
    case 0x80: case 0x81: case 0x82: case 0x83: { decode_modrm(c); int ww = op & 1; uint32_t a = rm_rd(c, ww), b = op == 0x81 ? fetch16(c) : (op == 0x83 ? (uint16_t)(int16_t)(int8_t)fetch8(c) : fetch8(c)); if (op == 0x83 && !ww) b &= 0xFF; uint32_t r = alu(c, c->regf, a, b & MASK(ww), ww); if (c->regf != 7) rm_wr(c, ww, r); break; }
    case 0x84: case 0x85: { decode_modrm(c); alu(c, 4, rm_rd(c, w), getreg(c, c->regf, w), w); break; }
    case 0x86: case 0x87: { decode_modrm(c); uint32_t a = rm_rd(c, w), b = getreg(c, c->regf, w); rm_wr(c, w, b); setreg(c, c->regf, w, a); break; }
    case 0x88: case 0x89: decode_modrm(c); rm_wr(c, w, getreg(c, c->regf, w)); break;
    case 0x8A: case 0x8B: decode_modrm(c); setreg(c, c->regf, w, rm_rd(c, w)); break;
    case 0x8C: decode_modrm(c); rm_wr(c, 1, c->sr[c->regf & 3]); break;
    case 0x8D: decode_modrm(c); if (c->mod != 3) c->r[c->regf] = c->ea_off; break;
    case 0x8E: decode_modrm(c); c->sr[c->regf & 3] = rm_rd(c, 1); c->inh = 1; break;
    case 0x8F: { decode_modrm(c); uint16_t v = pop16(c); rm_wr(c, 1, v); break; }
    case 0x90: break;
    case 0x91: case 0x92: case 0x93: case 0x94: case 0x95: case 0x96: case 0x97: { uint16_t t = c->r[AX]; c->r[AX] = c->r[op & 7]; c->r[op & 7] = t; break; }
    case 0x98: c->r[AX] = (int16_t)(int8_t)(c->r[AX] & 0xFF); break;
    case 0x99: c->r[DX] = (c->r[AX] & 0x8000) ? 0xFFFF : 0; break;
    case 0x9A: { uint16_t o = fetch16(c), s = fetch16(c); push16(c, c->sr[CS]); push16(c, c->ip); c->ip = o; c->sr[CS] = s; if (!c->cyc_model) c->cycles += 20; break; }
    case 0x9B: break;
    case 0x9C: push16(c, flags_get(c)); break;
    case 0x9D: flags_set(c, pop16(c)); break;
    case 0x9E: { uint8_t f = c->r[AX] >> 8; c->cf = f & 1; c->pf = (f >> 2) & 1; c->af = (f >> 4) & 1; c->zf = (f >> 6) & 1; c->sf = (f >> 7) & 1; break; }
    case 0x9F: c->r[AX] = (c->r[AX] & 0xFF) | ((flags_get(c) & 0xFF) << 8); break;
    case 0xA0: case 0xA1: { uint16_t off = fetch16(c); setreg(c, AX, w, mrd(c, lin(c->sr[c->seg_ovr >= 0 ? c->seg_ovr : DS], off), w)); break; }
    case 0xA2: case 0xA3: { uint16_t off = fetch16(c); mwr(c, lin(c->sr[c->seg_ovr >= 0 ? c->seg_ovr : DS], off), w, getreg(c, AX, w)); break; }
    case 0xA4: case 0xA5: case 0xA6: case 0xA7: case 0xAA: case 0xAB: case 0xAC: case 0xAD: case 0xAE: case 0xAF: strop(c, op); break;
    case 0xA8: alu(c, 4, getreg(c, AX, 0), fetch8(c), 0); break;
    case 0xA9: alu(c, 4, c->r[AX], fetch16(c), 1); break;
    case 0xB0: case 0xB1: case 0xB2: case 0xB3: case 0xB4: case 0xB5: case 0xB6: case 0xB7: setreg(c, op & 7, 0, fetch8(c)); break;
    case 0xB8: case 0xB9: case 0xBA: case 0xBB: case 0xBC: case 0xBD: case 0xBE: case 0xBF: c->r[op & 7] = fetch16(c); break;
    case 0xC0: case 0xC1: { decode_modrm(c); uint32_t v = rm_rd(c, w); int n = fetch8(c); if (c->cyc_model) c->cycles += (c->mod == 3 ? 0 : 6) + (n & 31) - 1;   /* 5+n reg / 17+n mem */
        rm_wr(c, w, shift(c, c->regf, v, n, w)); break; }
    case 0xC2: { uint16_t n = fetch16(c); c->ip = pop16(c); c->r[SP] += n; break; }
    case 0xC3: c->ip = pop16(c); break;
    case 0xC4: case 0xC5: { decode_modrm(c); if (c->mod == 3) return (void)bad(c, op); uint32_t a = lin(c->ea_seg, c->ea_off); c->r[c->regf] = mrd(c, a, 1); c->sr[op == 0xC4 ? ES : DS] = mrd(c, a + 2, 1); break; }
    case 0xC6: case 0xC7: { decode_modrm(c); uint32_t v = w ? fetch16(c) : fetch8(c); rm_wr(c, w, v); break; }
    case 0xC8: { uint16_t size = fetch16(c); int lvl = fetch8(c) & 31; push16(c, c->r[BP]); uint16_t fp = c->r[SP];
        if (lvl > 0) { for (int i = 1; i < lvl; i++) { c->r[BP] -= 2; push16(c, mrd(c, lin(c->sr[SS], c->r[BP]), 1)); } push16(c, fp); }
        c->r[BP] = fp; c->r[SP] -= size; break; }
    case 0xC9: c->r[SP] = c->r[BP]; c->r[BP] = pop16(c); break;
    case 0xCA: { uint16_t n = fetch16(c); c->ip = pop16(c); c->sr[CS] = pop16(c); c->r[SP] += n; break; }
    case 0xCB: c->ip = pop16(c); c->sr[CS] = pop16(c); break;
    case 0xCC: do_int(c, 3); break;
    case 0xCD: { uint8_t v = fetch8(c); do_int(c, v); break; }
    case 0xCE: if (c->of) do_int(c, 4); break;
    case 0xCF: c->ip = pop16(c); c->sr[CS] = pop16(c); flags_set(c, pop16(c)); break;
    case 0xD0: case 0xD1: case 0xD2: case 0xD3: { decode_modrm(c); uint32_t v = rm_rd(c, w); int n = (op & 2) ? (c->r[CX] & 0xFF) : 1;
        if (c->cyc_model) c->cycles += (op & 2) ? (c->mod == 3 ? 0 : 6) + (n & 31) + 1 : (c->mod == 3 ? -2 : 5);   /* by CL 5+n / 17+n, by 1: 2 / 15 */
        rm_wr(c, w, shift(c, c->regf, v, n, w)); break; }
    case 0xD4: { uint8_t b = fetch8(c); if (!b) { do_int(c, 0); break; } uint8_t al = c->r[AX]; c->r[AX] = ((al / b) << 8) | (al % b); szp(c, c->r[AX], 0); break; }
    case 0xD5: { uint8_t b = fetch8(c); uint8_t al = (c->r[AX] & 0xFF) + (c->r[AX] >> 8) * b; c->r[AX] = al; szp(c, al, 0); break; }
    case 0xD7: setreg(c, AX, 0, mrd(c, lin(c->sr[c->seg_ovr >= 0 ? c->seg_ovr : DS], c->r[BX] + (c->r[AX] & 0xFF)), 0)); break;
    case 0xD8: case 0xD9: case 0xDA: case 0xDB: case 0xDC: case 0xDD: case 0xDE: case 0xDF: decode_modrm(c); break;   /* ESC: ignore */
    case 0xE0: case 0xE1: case 0xE2: { int8_t d = fetch8(c); c->r[CX]--; int t = c->r[CX] != 0; if (op == 0xE0) t = t && !c->zf; else if (op == 0xE1) t = t && c->zf; if (t) { c->ip += d; if (c->cyc_model) c->cycles += 10; } break; }
    case 0xE3: { int8_t d = fetch8(c); if (!c->r[CX]) { c->ip += d; if (c->cyc_model) c->cycles += 10; } break; }   /* taken 16, not taken 6 */
    case 0xE4: case 0xE5: { uint8_t p = fetch8(c); setreg(c, AX, w, io_read(c, p, w)); break; }
    case 0xE6: case 0xE7: { uint8_t p = fetch8(c); io_write(c, p, w, getreg(c, AX, w)); break; }
    case 0xE8: { int16_t d = fetch16(c); push16(c, c->ip); c->ip += d; break; }
    case 0xE9: { int16_t d = fetch16(c); c->ip += d; break; }
    case 0xEA: { uint16_t o = fetch16(c), s = fetch16(c); c->ip = o; c->sr[CS] = s; break; }
    case 0xEB: { int8_t d = fetch8(c); c->ip += d; break; }
    case 0xEC: case 0xED: setreg(c, AX, w, io_read(c, c->r[DX], w)); break;
    case 0xEE: case 0xEF: io_write(c, c->r[DX], w, getreg(c, AX, w)); break;
    case 0xF4: c->halted = 1; break;
    case 0xF5: c->cf = !c->cf; break;
    case 0xF6: case 0xF7: {
        decode_modrm(c); uint32_t v = rm_rd(c, w);
        switch (c->regf) {
        case 0: case 1: alu(c, 4, v, w ? fetch16(c) : fetch8(c), w); break;
        case 2: rm_wr(c, w, ~v); break;
        case 3: { uint32_t r = alu(c, 5, 0, v, w); c->cf = v != 0; rm_wr(c, w, r); break; }
        case 4: if (c->cyc_model) c->cycles += w ? 33 : 24;     /* App. D: MUL r8 26-28, r16 35-37 (memory +6 added by decode_modrm) */
            if (w) { uint32_t r = (uint32_t)c->r[AX] * v; c->r[AX] = r; c->r[DX] = r >> 16; c->cf = c->of = (r >> 16) != 0; } else { uint32_t r = (c->r[AX] & 0xFF) * v; c->r[AX] = r; c->cf = c->of = (r >> 8) != 0; } break;
        case 5: if (c->cyc_model) c->cycles += w ? 33 : 24;     /* IMUL r8 25-28, r16 34-37 */
            if (w) { int32_t r = (int32_t)(int16_t)c->r[AX] * (int16_t)v; c->r[AX] = r; c->r[DX] = r >> 16; c->cf = c->of = (r != (int16_t)r); } else { int32_t r = (int8_t)c->r[AX] * (int8_t)v; c->r[AX] = r; c->cf = c->of = (r != (int8_t)r); } break;
        case 6: if (c->cyc_model) c->cycles += w ? 35 : 26;     /* DIV r8 29, r16 38 */
            if (w) { uint32_t n = ((uint32_t)c->r[DX] << 16) | c->r[AX]; if (!v || n / v > 0xFFFF) { do_int(c, 0); break; } c->r[AX] = n / v; c->r[DX] = n % v; } else { uint32_t n = c->r[AX]; if (!v || n / v > 0xFF) { do_int(c, 0); break; } c->r[AX] = ((n % v) << 8) | (n / v); } break;
        case 7: if (c->cyc_model) c->cycles += w ? 35 : 26;     /* IDIV r8 29, r16 38 (Table D-2) */
            if (w) { int64_t n = (int32_t)(((uint32_t)c->r[DX] << 16) | c->r[AX]); int64_t d = (int16_t)v; if (!d || n / d > 32767 || n / d < -32768) { do_int(c, 0); break; } c->r[AX] = (uint16_t)(n / d); c->r[DX] = (uint16_t)(n % d); } else { int32_t n = (int16_t)c->r[AX]; int32_t d = (int8_t)v; if (!d || n / d > 127 || n / d < -128) { do_int(c, 0); break; } c->r[AX] = (((n % d) & 0xFF) << 8) | ((n / d) & 0xFF); } break;
        }
        break; }
    case 0xF8: c->cf = 0; break; case 0xF9: c->cf = 1; break; case 0xFA: c->ifl = 0; break; case 0xFB: c->ifl = 1; c->inh = 1; break;
    case 0xFC: c->df = 0; break; case 0xFD: c->df = 1; break;
    case 0xFE: { decode_modrm(c); if (c->regf > 1) return (void)bad(c, op); rm_wr(c, 0, incdec(c, rm_rd(c, 0), c->regf, 0)); break; }
    case 0xFF: {
        decode_modrm(c);
        switch (c->regf) {
        case 0: case 1: rm_wr(c, 1, incdec(c, rm_rd(c, 1), c->regf, 1)); break;
        case 2: { uint16_t t = rm_rd(c, 1); push16(c, c->ip); c->ip = t; if (c->cyc_model) c->cycles += 10; break; }
        case 3: { if (c->mod == 3) return (void)bad(c, op); uint32_t a = lin(c->ea_seg, c->ea_off); uint16_t o = mrd(c, a, 1), s = mrd(c, a + 2, 1); push16(c, c->sr[CS]); push16(c, c->ip); c->ip = o; c->sr[CS] = s; if (c->cyc_model) c->cycles += 28; break; }
        case 4: c->ip = rm_rd(c, 1); if (c->cyc_model) c->cycles += 8; break;
        case 5: { if (c->mod == 3) return (void)bad(c, op); uint32_t a = lin(c->ea_seg, c->ea_off); c->ip = mrd(c, a, 1); c->sr[CS] = mrd(c, a + 2, 1); break; }
        case 6: { uint16_t v = rm_rd(c, 1); push16(c, v); break; }
        default: return (void)bad(c, op);
        }
        break; }
    default: bad(c, op);
    }
}

/* run until cycle budget exhausted; returns ST_* */
int i186_run(C *c, uint64_t budget) {
    uint64_t end = c->cycles + budget; int first = 1;
    c->run_end = end;
    c->stop = 0; c->status = ST_OK;
    while (c->cycles < end) {
        if (c->nmi_pending) { c->halted = 0; c->nmi_pending = 0; c->inh = 0; do_int(c, 2); }
        else if (c->irq_pending && c->ifl && !c->inh) { c->halted = 0; c->irq_pending = 0; do_int(c, c->irq_vec); }
        if (c->halted) { c->cycles = end; return ST_HLT; }   /* a pending request with IF=0 cannot wake it (NMI can) */
        uint32_t p = lin(c->sr[CS], c->ip);
        if (!first && c->bp[p]) return ST_BP;
        first = 0;
        uint16_t ip0 = c->ip, cs0 = c->sr[CS]; int tf0 = c->tf;
        c->inh = 0;                                          /* the shadow covers exactly one instruction; STI / segment loads set it again */
        uint64_t cb = c->cycles;
        exec1(c);
        if (c->cscale != 1.0 && c->cyc_model) { double d = (double)(c->cycles - cb) * c->cscale + c->cfrac; uint64_t di = (uint64_t)d; c->cfrac = d - (double)di; c->cycles = cb + di; }
        if (c->status == ST_BADOP) {
            c->ip = ip0; c->sr[CS] = cs0;
            if (!c->ud_trap) return ST_BADOP;
            c->status = ST_OK; do_int(c, 6); continue;      /* 80C186EB: type 6, the pushed IP is the faulting instruction's (manual 5.1 exceptions) */
        }
        if (tf0 && c->tf && !c->halted) do_int(c, 1);        /* single-step trap after an instruction that started with TF=1 (vectoring clears TF) */
        if (c->stop) return ST_STOP;
    }
    return ST_OK;
}
