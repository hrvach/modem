/* i186.c -- readable 80186 (8086 + 186 extensions) interpreter.
 *
 * Rewritten for humans from the compact original:
 *   modem/sys/i186.c  (453 lines; read-only, do not modify)
 * No behaviour was intentionally changed.  Every quirk of the original is
 * preserved and marked QUIRK with the original line number ("orig. L<n>");
 * where the 80C186EB manual disagrees with the original, the original wins
 * and the comment says so.
 *
 * What this core is: a 1 MB physical address space, a 16-bit I/O space,
 * callback hooks for memory-mapped pages and I/O.  Peripherals (PCB
 * timers/PIC/DMA, UART, DSP mailbox) live outside, in the glue code.
 *
 * Build (standalone check):
 *   gcc -O2 -Wall -Wextra -c src/cpu/i186.c
 * Build (shared library, as the Python wrapper expects):
 *   gcc -O2 -shared -fPIC -o libi186.so src/cpu/i186.c
 *
 * Cycle model: i186_set_cycle_model(0) charges a flat 4 cycles per
 * instruction; model 1 charges approximate 80C186 clock counts from the
 * manual's Appendix D, Table D-2 (base table CYC below, plus the per-form
 * extras in memextra() and at the execution sites).  i186_set_cycle_scale()
 * multiplies the per-instruction charge in model 1 only, carrying the
 * fractional remainder across instructions.
 *
 * Only the C standard library is used.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "i186.h"

/* ------------------------------------------------------------------ */
/* Named constants (magic numbers from the original, kept verbatim).  */
/* ------------------------------------------------------------------ */

/* Address space. */
#define I186_MEM_SIZE   (1u << 20)   /* 1 MB physical space, orig. L82 */
#define I186_MEM_MASK   0xFFFFFu     /* 20-bit wrap for linear addresses */
#define I186_PAGE_SHIFT 12           /* 4 KB pages */
#define I186_NPAGES     256          /* 256 pages cover 1 MB */
#define I186_IO_PORTS   65536        /* 16-bit I/O space */
#define I186_RING_SIZE  256          /* executed-PC ring buffer entries */
#define I186_RING_MASK  255

/* FLAGS bits (orig. L110-117).  Bit 1 is always 1; bits 15-12 read as 1,
 * hence the 0xF002 base in flags_get(). */
#define FLAG_CF   0x0001u
#define FLAG_PF   0x0004u
#define FLAG_AF   0x0010u
#define FLAG_ZF   0x0040u
#define FLAG_SF   0x0080u
#define FLAG_TF   0x0100u
#define FLAG_IF   0x0200u
#define FLAG_DF   0x0400u
#define FLAG_OF   0x0800u
#define FLAG_BASE 0xF002u

/* Reset state (orig. L129-133): CS:IP = FFFF:0000, i.e. linear 0xFFFF0. */
#define RESET_CS    0xFFFFu
#define RESET_IP    0x0000u
#define RESET_FLAGS 0x0002u

/* Prefix bytes (orig. L288-292). */
#define PREFIX_ES  0x26u
#define PREFIX_CS  0x2Eu
#define PREFIX_SS  0x36u
#define PREFIX_DS  0x3Eu
#define PREFIX_LOCK 0xF0u
#define PREFIX_REPNE 0xF2u   /* REPNE / REPNZ */
#define PREFIX_REP   0xF3u   /* REP / REPE / REPZ */

/* Interrupt vectors used internally (manual section 5.1, exceptions). */
#define INT_DIVIDE_ERROR 0   /* DIV/IDIV overflow, AAM by zero */
#define INT_SINGLE_STEP  1
#define INT_NMI          2
#define INT_BREAKPOINT   3
#define INT_OVERFLOW     4   /* INTO */
#define INT_BOUND        5
#define INT_BADOP        6   /* invalid opcode, only when ud_trap is on */

/* ALU operation codes: the reg field of the opcode (op >> 3). */
enum alu_op {
    ALU_ADD = 0, ALU_OR = 1, ALU_ADC = 2, ALU_SBB = 3,
    ALU_AND = 4, ALU_SUB = 5, ALU_XOR = 6, ALU_CMP = 7
};

/* Shift/rotate operation codes: the reg field of the D0-D3 / C0-C1 group. */
enum shift_op {
    SHIFT_ROL = 0, SHIFT_ROR = 1, SHIFT_RCL = 2, SHIFT_RCR = 3,
    SHIFT_SHL = 4, SHIFT_SHR = 5, SHIFT_SAR = 7
    /* 6 is a second encoding of SHL (orig. L226: case 4 / case 6). */
};

/* General registers (orig. L20) and segment registers (orig. L21). */
enum { REG_AX, REG_CX, REG_DX, REG_BX, REG_SP, REG_BP, REG_SI, REG_DI };
enum { SEG_ES, SEG_CS, SEG_SS, SEG_DS };

/* ------------------------------------------------------------------ */
/* CPU state.  This layout is private to this file; the header only    */
/* exposes it as the opaque type C.                                   */
/* ------------------------------------------------------------------ */
struct i186_cpu {
    uint16_t r[8], sr[4], ip;
    /* Flags kept as separate ints (orig. L26); assembled by flags_get(). */
    int cf, pf, af, zf, sf, tf, ifl, df, of;
    uint8_t *mem;                    /* 1 MB RAM image */
    uint8_t mmpage[I186_NPAGES];     /* 4 KB pages with MMIO hooks */
    uint8_t ro[I186_NPAGES];         /* 4 KB pages that ignore writes (flash) */
    io_rd_fn io_rd; io_wr_fn io_wr; mm_rd_fn mm_rd; mm_wr_fn mm_wr;
    void *ctx;
    uint16_t *ioarr;                 /* fallback I/O space, no hook installed */
    int halted, status, stop;
    int irq_pending, irq_vec;        /* external maskable interrupt request */
    int nmi_pending;                 /* latched NMI (type 2) */
    int inh;                         /* interrupt shadow: set by STI / segment-
                                      * register loads, covers the next
                                      * instruction (orig. L36) */
    uint16_t pstart;                 /* IP of the first prefix byte of the
                                      * running instruction (REP restart) */
    int ud_trap;                     /* 1 = an undefined opcode raises type 6
                                      * (invalid opcode, IP = the faulting
                                      * instruction) instead of ST_BADOP */
    int rep_resume;                  /* a REP string loop yielded and is being
                                      * resumed (no second start-up charge) */
    uint64_t run_end;                /* cycle budget end of the current
                                      * i186_run (REP string loops stop there
                                      * and resume) */
    double cscale, cfrac;            /* CPU speed knob: charged clocks per
                                      * instruction are multiplied by cscale
                                      * (1.0 = manual Table D-2) */
    int cyc_model;                   /* 0 = legacy flat 4 cycles/instruction,
                                      * 1 = approximate 80C186 clock counts */
    uint64_t cycles;
    uint32_t *hits;                  /* per-address execution counts */
    uint32_t ring[I186_RING_SIZE], ring_i;
    uint8_t *bp;                     /* breakpoints, one byte per phys addr */
    uint32_t cur_pc;                 /* linear PC of the running instruction */
    /* Instruction decode state. */
    int seg_ovr, rep, repz; uint8_t opc;
    int mod, regf, rmf;
    uint16_t ea_seg, ea_off;
    uint32_t last_badop_pc; uint8_t last_badop;
    /* QUIRK: declared in the original (orig. L63) but never read or
     * written anywhere; retained so the state keeps its shape. */
    uint32_t unmapped_log[64]; int unmapped_n;
};

static void flags_set(C *c, uint16_t f);
static void exec1(C *c);
static void do_int(C *c, int vec);

/* ------------------------------------------------------------------ */
/* Tables.                                                            */
/* ------------------------------------------------------------------ */

/* Parity of the low byte: PAR[n] is 1 when n has an even number of 1 bits
 * (orig. L65-70).  Built with the same nested macros as the original so
 * the values are identical by construction. */
static const uint8_t PAR[256] = {
#define P2(n) n, n ^ 1, n ^ 1, n
#define P4(n) P2(n), P2(n ^ 1), P2(n ^ 1), P2(n)
#define P6(n) P4(n), P4(n ^ 1), P4(n ^ 1), P4(n)
    P6(1), P6(0), P6(0), P6(1)
#undef P2
#undef P4
#undef P6
};

/* Approximate 80C186 clock counts per opcode, register forms (orig. L72-88).
 * decode_modrm() adds 6 for a memory operand plus the per-form extra from
 * memextra(); taken branches, multiplies/divides, indirect calls and
 * interrupt entry add their extra where executed.  Values below are copied
 * verbatim from the original, one row per 16 opcodes (row base in comment).
 * Note the zeros that matter: 0x8D (LEA) charges a 0 base -- its cost is
 * the 6 clocks decode_modrm() adds for the memory operand. */
static const uint8_t CYC[256] = {
    /* 0x00 */  3,  3,  3,  3,  3,  4,  9,  8,  3,  3,  3,  3,  3,  4,  9,  3,
    /* 0x10 */  3,  3,  3,  3,  3,  4,  9,  8,  3,  3,  3,  3,  3,  4,  9,  8,
    /* 0x20 */  3,  3,  3,  3,  3,  4,  3,  4,  3,  3,  3,  3,  3,  4,  3,  4,
    /* 0x30 */  3,  3,  3,  3,  3,  4,  3,  7,  3,  3,  3,  3,  3,  4,  3,  7,
    /* 0x40 */  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,
    /* 0x50 */ 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10,
    /* 0x60 */ 36, 51, 27,  3,  3,  3,  3,  3, 10, 24, 10, 24,  5,  5,  5,  5,
    /* 0x70 */  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,
    /* 0x80 */  4,  4,  4,  4,  3,  3,  4,  4,  2,  2,  2,  2,  2,  0,  2, 14,
    /* 0x90 */  3,  3,  3,  3,  3,  3,  3,  3,  2,  4, 23,  3,  9,  8,  3,  2,
    /* 0xA0 */  9,  9,  8,  8,  5,  5,  5,  5,  3,  3,  5,  5,  5,  5,  5,  5,
    /* 0xB0 */  3,  3,  3,  3,  3,  3,  3,  3,  4,  4,  4,  4,  4,  4,  4,  4,
    /* 0xC0 */  6,  6, 18, 16, 12, 12,  6,  6, 15,  8, 25, 22,  3,  5,  3, 28,
    /* 0xD0 */  4,  4,  4,  4, 19, 15,  3, 11,  3,  3,  3,  3,  3,  3,  3,  3,
    /* 0xE0 */  6,  6,  6,  6, 10, 10,  9,  9, 15, 14, 14, 14,  8,  8,  7,  7,
    /* 0xF0 */  3,  3,  3,  3,  2,  2,  3,  3,  2,  2,  2,  2,  2,  2,  3,  3,
};

/* ------------------------------------------------------------------ */
/* Flags and registers.                                               */
/* ------------------------------------------------------------------ */

/* Assemble the FLAGS word (orig. L109-111).  Bits 15-12 and bit 1 read 1. */
static uint16_t flags_get(C *c) {
    return (uint16_t)(FLAG_BASE | c->cf | (c->pf << 2) | (c->af << 4) |
                      (c->zf << 6) | (c->sf << 7) | (c->tf << 8) |
                      (c->ifl << 9) | (c->df << 10) | (c->of << 11));
}

/* Split a FLAGS word back into the separate flag ints (orig. L113-116).
 * Only the eight architected flag bits are read; the rest are ignored. */
static void flags_set(C *c, uint16_t f) {
    c->cf = f & 1; c->pf = (f >> 2) & 1; c->af = (f >> 4) & 1;
    c->zf = (f >> 6) & 1; c->sf = (f >> 7) & 1;
    c->tf = (f >> 8) & 1; c->ifl = (f >> 9) & 1;
    c->df = (f >> 10) & 1; c->of = (f >> 11) & 1;
}

/* Read one of the eight general registers.  w=1 reads the whole 16-bit
 * register; w=0 reads a byte: n<4 is the low byte of r[n], n>=4 the high
 * byte of r[n-4] (orig. L163). */
static inline uint32_t getreg(C *c, int n, int w) {
    if (w) return c->r[n];
    return n < 4 ? (c->r[n] & 0xFFu) : (c->r[n - 4] >> 8);
}

/* Write one of the eight general registers (orig. L164-166).  A byte write
 * preserves the other byte of the register. */
static inline void setreg(C *c, int n, int w, uint32_t v) {
    if (w) c->r[n] = (uint16_t)v;
    else if (n < 4) c->r[n] = (uint16_t)((c->r[n] & 0xFF00u) | (v & 0xFFu));
    else c->r[n - 4] = (uint16_t)((c->r[n - 4] & 0xFFu) | ((v & 0xFFu) << 8));
}

/* Operand masks for the current width (orig. L167-168). */
static inline uint32_t width_mask(int w) { return w ? 0xFFFFu : 0xFFu; }
static inline uint32_t width_msb(int w) { return w ? 0x8000u : 0x80u; }

/* ------------------------------------------------------------------ */
/* Public API: lifetime, raw access, configuration, interrupts.       */
/* ------------------------------------------------------------------ */

C *i186_new(void) {
    C *c = calloc(1, sizeof *c);
    if (!c) return NULL;
    c->cscale = 1.0;
    c->mem = calloc(I186_MEM_SIZE, 1);
    c->hits = calloc(I186_MEM_SIZE, sizeof *c->hits);
    c->bp = calloc(I186_MEM_SIZE, 1);
    c->ioarr = calloc(I186_IO_PORTS, sizeof *c->ioarr);
    c->seg_ovr = -1;
    if (!c->mem || !c->hits || !c->bp || !c->ioarr) {
        free(c->mem); free(c->hits); free(c->bp); free(c->ioarr);
        free(c);
        return NULL;
    }
    return c;
}

void i186_free(C *c) {
    if (!c) return;
    free(c->mem); free(c->hits); free(c->bp); free(c->ioarr); free(c);
}

uint8_t *i186_mem(C *c) { return c->mem; }
uint32_t *i186_hits(C *c) { return c->hits; }
uint32_t *i186_ring(C *c) { return c->ring; }
uint32_t i186_ring_idx(C *c) { return c->ring_i; }
uint16_t *i186_ioarr(C *c) { return c->ioarr; }

void i186_set_hooks(C *c, io_rd_fn ir, io_wr_fn iw, mm_rd_fn mr, mm_wr_fn mw,
                    void *ctx) {
    c->io_rd = ir; c->io_wr = iw; c->mm_rd = mr; c->mm_wr = mw; c->ctx = ctx;
}

void i186_set_mmio_page(C *c, uint32_t page, int on) {
    if (page < I186_NPAGES) c->mmpage[page] = (uint8_t)on;
}

void i186_set_ro_page(C *c, uint32_t page, int on) {
    if (page < I186_NPAGES) c->ro[page] = (uint8_t)on;
}

void i186_set_bp(C *c, uint32_t phys, int on) {
    if (phys < I186_MEM_SIZE) c->bp[phys] = (uint8_t)on;
}

void i186_stop(C *c) { c->stop = 1; }

void i186_irq(C *c, int vec) { c->irq_pending = 1; c->irq_vec = vec & 0xFF; }
void i186_nmi(C *c) { c->nmi_pending = 1; }
void i186_irq_clear(C *c) { c->irq_pending = 0; }
int i186_irq_pending(C *c) { return c->irq_pending; }

void i186_set_ud_trap(C *c, int m) { c->ud_trap = m; }
void i186_set_cycle_model(C *c, int m) { c->cyc_model = m; }

/* QUIRK (orig. L104): a non-positive scale is silently replaced by 1.0,
 * and setting the scale always resets the fractional remainder. */
void i186_set_cycle_scale(C *c, double f) {
    c->cscale = f > 0 ? f : 1.0;
    c->cfrac = 0;
}

uint64_t i186_cycles(C *c) { return c->cycles; }
void i186_add_cycles(C *c, uint64_t n) { c->cycles += n; }

/* orig. L107: low 24 bits = PC of the last bad opcode, high byte = opcode. */
uint32_t i186_get_badop(C *c) {
    return c->last_badop_pc | ((uint32_t)c->last_badop << 24);
}

/* Register access by the i186_reg index (orig. L117-127).  Out-of-range
 * ids read as 0 / are ignored; a 16-bit register truncates a 32-bit value. */
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
    if (id < 8) c->r[id] = (uint16_t)v;
    else if (id < 12) c->sr[id - 8] = (uint16_t)v;
    else if (id == R_IP) c->ip = (uint16_t)v;
    else if (id == R_FLAGS) flags_set(c, (uint16_t)v);
}

/* Reset (orig. L129-133): CS=0xFFFF, IP=0, FLAGS=0x0002, cycle counter
 * cleared, interrupt state cleared.  QUIRK: this resets ONLY those fields.
 * Memory, hooks, MMIO/RO pages, breakpoints, ud_trap, cycle model/scale,
 * the ring and hit counts all survive a reset, exactly as in the original. */
void i186_reset(C *c) {
    memset(c->r, 0, sizeof c->r);
    memset(c->sr, 0, sizeof c->sr);
    c->sr[SEG_CS] = RESET_CS;
    c->ip = RESET_IP;
    flags_set(c, RESET_FLAGS);
    c->halted = 0;
    c->cycles = 0;
    c->irq_pending = c->nmi_pending = c->inh = 0;
    c->irq_vec = 0;
}

/* ------------------------------------------------------------------ */
/* Memory and I/O.                                                    */
/* ------------------------------------------------------------------ */

/* Segment:offset to a 20-bit linear address (orig. L136). */
static inline uint32_t lin(uint16_t seg, uint16_t off) {
    return (((uint32_t)seg << 4) + off) & I186_MEM_MASK;
}

/* A word access whose two bytes fall on pages that route differently
 * (MMIO hook / read-only / RAM) is performed as two byte accesses, each
 * through its own page's rule; same-routing words keep the single word
 * call to the hook (orig. L137-143). */
static inline int split_word(C *c, uint32_t a, uint32_t b) {
    uint32_t pa = a >> I186_PAGE_SHIFT, pb = b >> I186_PAGE_SHIFT;
    return pa != pb &&
           ((c->mmpage[pa] != c->mmpage[pb]) || (c->ro[pa] != c->ro[pb]));
}

/* Physical read.  w=1 reads a word (little-endian), w=0 a byte.
 * The second byte wraps at 1 MB (orig. L144-151). */
static uint32_t mem_read(C *c, uint32_t a, int w) {
    a &= I186_MEM_MASK;
    if (w) {
        uint32_t b = (a + 1) & I186_MEM_MASK;
        if (split_word(c, a, b))
            return mem_read(c, a, 0) | (mem_read(c, b, 0) << 8);
    }
    if (c->mmpage[a >> I186_PAGE_SHIFT] && c->mm_rd)
        return c->mm_rd(c->ctx, a, w);
    if (w) return c->mem[a] | ((uint32_t)c->mem[(a + 1) & I186_MEM_MASK] << 8);
    return c->mem[a];
}

/* Physical write.  MMIO pages go to the hook, read-only pages drop the
 * write silently, everything else lands in RAM (orig. L152-159). */
static void mem_write(C *c, uint32_t a, int w, uint32_t v) {
    a &= I186_MEM_MASK;
    if (w) {
        uint32_t b = (a + 1) & I186_MEM_MASK;
        if (split_word(c, a, b)) {
            mem_write(c, a, 0, v);
            mem_write(c, b, 0, v >> 8);
            return;
        }
    }
    if (c->mmpage[a >> I186_PAGE_SHIFT] && c->mm_wr) {
        c->mm_wr(c->ctx, a, w, v);
        return;
    }
    if (c->ro[a >> I186_PAGE_SHIFT]) return;
    c->mem[a] = (uint8_t)v;
    if (w) c->mem[(a + 1) & I186_MEM_MASK] = (uint8_t)(v >> 8);
}

/* Fetch the next code byte / word at CS:IP (orig. L160-161).  IP wraps at
 * 16 bits by virtue of being a uint16_t. */
static inline uint8_t fetch8(C *c) {
    uint8_t v = (uint8_t)mem_read(c, lin(c->sr[SEG_CS], c->ip), 0);
    c->ip++;
    return v;
}

static inline uint16_t fetch16(C *c) {
    uint16_t v = fetch8(c);
    v |= (uint16_t)(fetch8(c) << 8);
    return v;
}

static inline void push16(C *c, uint16_t v) {
    c->r[REG_SP] -= 2;
    mem_write(c, lin(c->sr[SEG_SS], c->r[REG_SP]), 1, v);
}

static inline uint16_t pop16(C *c) {
    uint16_t v = (uint16_t)mem_read(c, lin(c->sr[SEG_SS], c->r[REG_SP]), 1);
    c->r[REG_SP] += 2;
    return v;
}

/* I/O space.  With no read hook the fallback ioarr array answers; with no
 * write hook a byte write preserves the high byte of the port (orig. L164
 * in the original numbering: io_read/io_write, L162-163). */
static uint32_t io_read(C *c, uint16_t p, int w) {
    if (c->io_rd) return c->io_rd(c->ctx, p, w);
    return c->ioarr[p];
}

static void io_write(C *c, uint16_t p, int w, uint32_t v) {
    if (c->io_wr) {
        /* QUIRK: when a write hook is installed the fallback array is NOT
         * updated, so a later hook-less read of the same port sees stale
         * data.  Preserved from the original. */
        c->io_wr(c->ctx, p, w, v);
    } else {
        c->ioarr[p] = (uint16_t)(w ? v : (c->ioarr[p] & 0xFF00u) | (v & 0xFFu));
    }
}

/* ------------------------------------------------------------------ */
/* ModR/M decoding.                                                   */
/* ------------------------------------------------------------------ */

/* Extra clocks of the memory form over (register form + 6), from the
 * 80C186EB manual Table D-2 (16-bit, fastest case) -- orig. L173-189.
 * `reg` is the ModR/M reg field.  The fall-through at the end covers the
 * ALU r/m forms (op < 0x40, (op & 7) < 4): +1.  Note 0xC6 (MOV r/m,imm8)
 * is NOT listed, so it gets +0 -- a quirk of the original table. */
static int memextra(uint8_t op, int reg) {
    switch (op) {
    case 0x88: case 0x89: return 4;               /* MOV r/m,r: 12 */
    case 0x8A: case 0x8B: case 0x8E: return 1;    /* MOV r,r/m / sreg,r/m: 9 */
    case 0x8C: return 3;                          /* MOV r/m,sreg: 11 */
    case 0xC7: return 1;                          /* MOV r/m,imm16: 13 */
    case 0x80: case 0x81: case 0x82: case 0x83:
        return reg == 7 ? 0 : 6;                  /* ALU imm,r/m RMW 16 (CMP 10) */
    case 0xFE: return reg < 2 ? 6 : 0;            /* INC/DEC r/m: 15 */
    case 0xFF:
        return reg < 2 ? 6 : reg == 6 ? 7 : 0;    /* INC/DEC r/m 15, PUSH r/m 16 */
    case 0x86: case 0x87: return 7;               /* XCHG r/m,r: 17 */
    case 0x84: case 0x85: return 1;               /* TEST r/m,r: 10 */
    case 0xF6: case 0xF7: return reg < 2 ? 1 : 0; /* TEST r/m,imm: 10 */
    }
    if (op < 0x40 && (op & 7) < 4) return 1;      /* ALU r/m,r and r,r/m: 10 */
    return 0;
}

/* Decode a ModR/M byte plus any displacement into c->mod/regf/rmf and the
 * effective address (c->ea_seg:c->ea_off).  Register form (mod==3) has no
 * effective address and -- note -- charges NO cycles (orig. L191-209).
 * The default segment is DS, except BP-based forms use SS; a segment
 * prefix overrides either.  rm==6 with mod==0 is a 16-bit direct address. */
static void decode_modrm(C *c) {
    uint8_t m = fetch8(c);
    c->mod = m >> 6;
    c->regf = (m >> 3) & 7;
    c->rmf = m & 7;
    if (c->mod == 3) return;
    /* Memory operand: EA + bus cycle, plus the per-form difference to
     * Table D-2.  Charged before the displacement is fetched. */
    if (c->cyc_model) c->cycles += 6 + (uint64_t)memextra(c->opc, c->regf);
    uint16_t off = 0;
    int dseg = SEG_DS;
    switch (c->rmf) {
    case 0: off = (uint16_t)(c->r[REG_BX] + c->r[REG_SI]); break;
    case 1: off = (uint16_t)(c->r[REG_BX] + c->r[REG_DI]); break;
    case 2: off = (uint16_t)(c->r[REG_BP] + c->r[REG_SI]); dseg = SEG_SS; break;
    case 3: off = (uint16_t)(c->r[REG_BP] + c->r[REG_DI]); dseg = SEG_SS; break;
    case 4: off = c->r[REG_SI]; break;
    case 5: off = c->r[REG_DI]; break;
    case 6:
        if (c->mod == 0) off = fetch16(c);
        else { off = c->r[REG_BP]; dseg = SEG_SS; }
        break;
    case 7: off = c->r[REG_BX]; break;
    }
    if (c->mod == 1) off = (uint16_t)(off + (int8_t)fetch8(c));
    else if (c->mod == 2) off = (uint16_t)(off + fetch16(c));
    c->ea_off = off;
    c->ea_seg = c->sr[c->seg_ovr >= 0 ? c->seg_ovr : dseg];
}

/* Read/write the ModR/M operand (orig. L210). */
static uint32_t rm_rd(C *c, int w) {
    return c->mod == 3 ? getreg(c, c->rmf, w)
                       : mem_read(c, lin(c->ea_seg, c->ea_off), w);
}

static void rm_wr(C *c, int w, uint32_t v) {
    if (c->mod == 3) setreg(c, c->rmf, w, v);
    else mem_write(c, lin(c->ea_seg, c->ea_off), w, v);
}

/* ------------------------------------------------------------------ */
/* ALU.                                                               */
/* ------------------------------------------------------------------ */

/* Set ZF/SF/PF from a result of the current width (orig. L210-211).
 * AF/CF/OF are left alone here; the caller sets them. */
static inline void set_szp(C *c, uint32_t r, int w) {
    r &= width_mask(w);
    c->zf = r == 0;
    c->sf = !!(r & width_msb(w));
    c->pf = PAR[r & 0xFFu];
}

/* The eight ALU operations.  `op` is the ALU_* code above.
 * QUIRK (orig. L212-223): the logic operations (OR/AND/XOR) clear CF and
 * OF but leave AF untouched, exactly as the silicon does; ADD/ADC/SUB/SBB/
 * CMP set AF from bit 3 exactly as written.  CMP (7) is SUB whose result
 * the caller discards. */
static uint32_t alu(C *c, int op, uint32_t a, uint32_t b, int w) {
    uint32_t m = width_mask(w), r;
    switch (op) {
    case ALU_ADD: case ALU_ADC: {
        uint32_t carry_in = op == ALU_ADC ? (uint32_t)c->cf : 0;
        r = a + b + carry_in;
        c->cf = r > m;
        c->af = ((a ^ b ^ r) >> 4) & 1;
        c->of = ((a ^ r) & (b ^ r) & width_msb(w)) != 0;
        break;
    }
    case ALU_SUB: case ALU_SBB: case ALU_CMP: {
        uint32_t borrow_in = op == ALU_SBB ? (uint32_t)c->cf : 0;
        r = a - b - borrow_in;
        c->cf = a < b + borrow_in;
        c->af = ((a ^ b ^ r) >> 4) & 1;
        c->of = ((a ^ b) & (a ^ r) & width_msb(w)) != 0;
        break;
    }
    case ALU_OR:
        r = a | b; c->cf = c->of = 0;
        break;
    case ALU_AND:
        r = a & b; c->cf = c->of = 0;
        break;
    default: /* ALU_XOR */
        r = a ^ b; c->cf = c->of = 0;
        break;
    }
    set_szp(c, r, w);
    return r & m;
}

/* INC/DEC (orig. L224-227).  CF is preserved across the operation. */
static uint32_t incdec(C *c, uint32_t a, int dec, int w) {
    uint32_t r = dec ? a - 1 : a + 1;
    int saved_cf = c->cf;
    c->of = dec ? (a == width_msb(w)) : (a == width_msb(w) - 1);
    c->af = ((a ^ 1 ^ r) >> 4) & 1;
    set_szp(c, r, w);
    c->cf = saved_cf;
    return r & width_mask(w);
}

/* Shifts and rotates (orig. L228-238).  `n` is the raw count; the low
 * five bits are used (n &= 0x1F).  A count of 0 after masking returns the
 * value with NO flag change -- including the case n == 32, where the
 * masked count is 0.
 * QUIRKS preserved verbatim:
 *  - ROL/ROR/RCL/RCR never set ZF/SF/PF/AF, and their OF rule applies
 *    only when the masked count is exactly 1.
 *  - RCL/RCR rotate through CF one bit at a time; RCR computes its
 *    count-1 OF from the ORIGINAL value and the incoming CF, before the
 *    loop runs.
 *  - SHL with n == bits takes CF from bit 0 of the value (the
 *    (v >> (bits - n)) expression with n == bits shifts by 0).
 *  - SAR with n > bits uses a shift of bits-1 for both CF and the result.
 */
static uint32_t shift(C *c, int op, uint32_t v, int n, int w) {
    int bits = w ? 16 : 8;
    uint32_t m = width_mask(w);
    n &= 0x1F;
    if (!n) return v;
    v &= m;
    uint32_t r = v;
    switch (op) {
    case SHIFT_ROL: {
        int k = n % bits;
        r = k ? ((v << k) | (v >> (bits - k))) & m : v;
        c->cf = r & 1;
        if (n == 1) c->of = ((r & width_msb(w)) != 0) ^ c->cf;
        return r;
    }
    case SHIFT_ROR: {
        int k = n % bits;
        r = k ? ((v >> k) | (v << (bits - k))) & m : v;
        c->cf = !!(r & width_msb(w));
        if (n == 1) c->of = ((r ^ (r << 1)) & width_msb(w)) != 0;
        return r;
    }
    case SHIFT_RCL:
        for (int i = 0; i < n; i++) {
            int next_cf = !!(r & width_msb(w));
            r = ((r << 1) | (uint32_t)c->cf) & m;
            c->cf = next_cf;
        }
        if (n == 1) c->of = ((r & width_msb(w)) != 0) ^ c->cf;
        return r;
    case SHIFT_RCR:
        if (n == 1) c->of = ((r & width_msb(w)) != 0) ^ c->cf;
        for (int i = 0; i < n; i++) {
            int next_cf = r & 1;
            r = (r >> 1) | (c->cf ? width_msb(w) : 0);
            c->cf = next_cf;
        }
        return r;
    case SHIFT_SHL: /* case 4 and case 6 in the original */
    case 6: {
        if (n > bits) { c->cf = 0; r = 0; }
        else { c->cf = (v >> (bits - n)) & 1; r = (v << n) & m; }
        if (n == 1) c->of = ((r & width_msb(w)) != 0) ^ c->cf;
        set_szp(c, r, w);
        c->af = 0;
        return r;
    }
    case SHIFT_SHR: {
        c->cf = (n > bits) ? 0 : (v >> (n - 1)) & 1;
        r = n >= bits ? 0 : v >> n;
        if (n == 1) c->of = (v & width_msb(w)) != 0;
        set_szp(c, r, w);
        c->af = 0;
        return r;
    }
    default: /* SHIFT_SAR */
    {
        int32_t sv = w ? (int16_t)v : (int8_t)v;
        int k = n >= bits ? bits - 1 : n;
        c->cf = (uint32_t)(sv >> (n > bits ? bits - 1 : n - 1)) & 1;
        r = (uint32_t)(sv >> k) & m;
        c->of = 0;
        set_szp(c, r, w);
        c->af = 0;
        return r;
    }
    }
}

/* ------------------------------------------------------------------ */
/* Interrupts, conditions, bad opcodes.                               */
/* ------------------------------------------------------------------ */

/* Take an interrupt/exception (orig. L239-244): push FLAGS, CS, IP in
 * that order, clear IF and TF, and vector through the IVT at vec*4.
 * Costs 42 clocks in cycle model 1, nothing in the legacy model. */
static void do_int(C *c, int vec) {
    if (c->cyc_model) c->cycles += 42;
    push16(c, flags_get(c));
    push16(c, c->sr[SEG_CS]);
    push16(c, c->ip);
    c->ifl = 0;
    c->tf = 0;
    c->ip = (uint16_t)mem_read(c, (uint32_t)(vec * 4), 1);
    c->sr[SEG_CS] = (uint16_t)mem_read(c, (uint32_t)(vec * 4 + 2), 1);
}

/* Evaluate a Jcc condition code (orig. L245-252).  cc is the low nibble
 * of the opcode; the low bit inverts the sense. */
static int cond(C *c, int cc) {
    int taken;
    switch (cc >> 1) {
    case 0: taken = c->of; break;
    case 1: taken = c->cf; break;
    case 2: taken = c->zf; break;
    case 3: taken = c->cf || c->zf; break;
    case 4: taken = c->sf; break;
    case 5: taken = c->pf; break;
    case 6: taken = c->sf != c->of; break;
    default: taken = c->zf || (c->sf != c->of); break;
    }
    return (cc & 1) ? !taken : taken;
}

/* Record an undefined opcode (orig. L254).  The run loop decides whether
 * this ends the run (ST_BADOP) or vectors to INT 6 (ud_trap). */
static int bad(C *c, uint8_t op) {
    c->status = ST_BADOP;
    c->last_badop = op;
    c->last_badop_pc = c->cur_pc;
    return 0;
}

/* ------------------------------------------------------------------ */
/* String instructions (MOVS/CMPS/STOS/LODS/SCAS/INS/OUTS).           */
/* ------------------------------------------------------------------ */

/* Execute one string instruction, with or without a REP prefix
 * (orig. L256-281).  `op` is the full opcode; the low bit is the width.
 *
 * Cycle accounting in model 1 (manual App. D): the base CYC[op] was
 * already charged by exec1, so the first iteration subtracts it back and
 * charges the single/per-iteration figure instead.  A REP loop charges a
 * one-off setup cost on its first iteration only -- and NOT on a resume
 * after a yield (rep_resume).  In the legacy model every iteration costs
 * a flat 4, on top of the flat 4 exec1 already charged.
 *
 * A REP loop is interruptible between iterations: if iterations remain
 * and an NMI is pending, a maskable IRQ is pending with IF set, or the
 * cycle budget is used up (model 1 only), IP is reset to the start of the
 * instruction (including its prefixes, c->pstart) and rep_resume is set,
 * so the run loop restarts the same instruction with the reduced CX.
 * This is also what keeps the DSP and the codec clock running during a
 * long block move.  CMPS/SCAS additionally stop early on the ZF test:
 * REPE stops when ZF==0, REPNE when ZF==1 (a bare REP prefix on CMPS
 * behaves as REPNE). */
static void strop(C *c, uint8_t op) {
    int w = op & 1;
    int step = (w ? 2 : 1) * (c->df ? -1 : 1);
    int useseg = c->seg_ovr >= 0 ? c->seg_ovr : SEG_DS;
    int rep = c->rep, zrep = c->repz;
    uint32_t cnt = rep ? c->r[REG_CX] : 1;
    int first_it = 1;
    int resumed = c->rep_resume;
    c->rep_resume = 0;

    while (cnt) {
        switch (op & 0xFEu) {
        case 0xA4: /* MOVS */
            mem_write(c, lin(c->sr[SEG_ES], c->r[REG_DI]), w,
                      mem_read(c, lin(c->sr[useseg], c->r[REG_SI]), w));
            c->r[REG_SI] = (uint16_t)(c->r[REG_SI] + step);
            c->r[REG_DI] = (uint16_t)(c->r[REG_DI] + step);
            break;
        case 0xA6: { /* CMPS */
            uint32_t a = mem_read(c, lin(c->sr[useseg], c->r[REG_SI]), w);
            uint32_t b = mem_read(c, lin(c->sr[SEG_ES], c->r[REG_DI]), w);
            alu(c, ALU_CMP, a, b, w);
            c->r[REG_SI] = (uint16_t)(c->r[REG_SI] + step);
            c->r[REG_DI] = (uint16_t)(c->r[REG_DI] + step);
            break;
        }
        case 0xAA: /* STOS */
            mem_write(c, lin(c->sr[SEG_ES], c->r[REG_DI]), w,
                      getreg(c, REG_AX, w));
            c->r[REG_DI] = (uint16_t)(c->r[REG_DI] + step);
            break;
        case 0xAC: /* LODS */
            setreg(c, REG_AX, w,
                   mem_read(c, lin(c->sr[useseg], c->r[REG_SI]), w));
            c->r[REG_SI] = (uint16_t)(c->r[REG_SI] + step);
            break;
        case 0xAE: { /* SCAS */
            uint32_t b = mem_read(c, lin(c->sr[SEG_ES], c->r[REG_DI]), w);
            alu(c, ALU_CMP, getreg(c, REG_AX, w), b, w);
            c->r[REG_DI] = (uint16_t)(c->r[REG_DI] + step);
            break;
        }
        case 0x6C: /* INS */
            mem_write(c, lin(c->sr[SEG_ES], c->r[REG_DI]), w,
                      io_read(c, c->r[REG_DX], w));
            c->r[REG_DI] = (uint16_t)(c->r[REG_DI] + step);
            break;
        case 0x6E: /* OUTS */
            io_write(c, c->r[REG_DX], w,
                     mem_read(c, lin(c->sr[useseg], c->r[REG_SI]), w));
            c->r[REG_SI] = (uint16_t)(c->r[REG_SI] + step);
            break;
        }

        if (c->cyc_model) {
            /* Indexed MOVS, CMPS, STOS, LODS, SCAS, (unused), INS, OUTS. */
            static const uint8_t single[8] = { 14, 22, 10, 12, 15, 0, 14, 14 };
            static const uint8_t per_it[8] = { 8, 22, 9, 11, 15, 0, 8, 8 };
            /* REP setup: 8+8n MOVS/INS/OUTS, 5+22n CMPS, 5+15n SCAS,
             * 6+11n LODS, 6+9n STOS. */
            static const uint8_t setup[8] = { 8, 5, 6, 6, 5, 0, 8, 8 };
            int k = (op & 0xFEu) == 0xA4 ? 0 : (op & 0xFEu) == 0xA6 ? 1 :
                    (op & 0xFEu) == 0xAA ? 2 : (op & 0xFEu) == 0xAC ? 3 :
                    (op & 0xFEu) == 0xAE ? 4 : (op & 0xFEu) == 0x6C ? 6 : 7;
            c->cycles += (uint64_t)(rep ? per_it[k] + (first_it && !resumed ? setup[k] : 0)
                                        : single[k]) -
                         (first_it ? CYC[op] : 0);
            first_it = 0;
        } else {
            c->cycles += 4;
        }

        if (rep) {
            c->r[REG_CX]--;
            cnt = c->r[REG_CX];
            if ((op & 0xFEu) == 0xA6 || (op & 0xFEu) == 0xAE) {
                if (zrep ? !c->zf : c->zf) break;
            }
            if (cnt && (c->nmi_pending || (c->irq_pending && c->ifl) ||
                        (c->cyc_model && c->cycles >= c->run_end))) {
                c->ip = c->pstart;
                c->rep_resume = 1;
                return;
            }
        } else {
            cnt = 0;
        }
    }
}

/* ------------------------------------------------------------------ */
/* Instruction execution.  exec1() fetches prefixes + opcode, charges */
/* the base cycles, then dispatches: first the ALU forms (op < 0x40),  */
/* then dispatch() below.  Each handler below implements one opcode    */
/* group from the original exec1() switch (orig. L283-426).  A handler */
/* that calls bad() sets c->status = ST_BADOP; the run loop then       */
/* restores CS:IP and either returns ST_BADOP or vectors to INT 6.     */
/* There is no code after the dispatch in exec1(), so a handler        */
/* returning after bad() is equivalent to the original's early         */
/* `return (void)bad(c, op)`.                                         */
/* ------------------------------------------------------------------ */

/* ALU forms: op < 0x40 with (op & 7) < 6 (orig. L296-307).
 * Returns 1 if the opcode was an ALU form, 0 otherwise. */
static int exec_alu_forms(C *c, uint8_t op, int w) {
    if (op >= 0x40 || (op & 7) >= 6) return 0;
    int aop = op >> 3;
    switch (op & 7) {
    case 0: case 1: { /* ALU r/m, r */
        decode_modrm(c);
        uint32_t a = rm_rd(c, w), b = getreg(c, c->regf, w);
        uint32_t r = alu(c, aop, a, b, w);
        if (aop != ALU_CMP) rm_wr(c, w, r);
        break;
    }
    case 2: case 3: { /* ALU r, r/m */
        decode_modrm(c);
        uint32_t a = getreg(c, c->regf, w), b = rm_rd(c, w);
        uint32_t r = alu(c, aop, a, b, w);
        if (aop != ALU_CMP) setreg(c, c->regf, w, r);
        break;
    }
    case 4: { /* ALU AL, imm8 */
        uint32_t r = alu(c, aop, getreg(c, REG_AX, 0), fetch8(c), 0);
        if (aop != ALU_CMP) setreg(c, REG_AX, 0, r);
        break;
    }
    case 5: { /* ALU AX, imm16 */
        uint32_t r = alu(c, aop, c->r[REG_AX], fetch16(c), 1);
        if (aop != ALU_CMP) c->r[REG_AX] = (uint16_t)r;
        break;
    }
    }
    return 1;
}

/* PUSH/POP segment register (orig. L310).  Note there is no POP CS
 * (0x0F): it falls through to the bad-opcode default.  POP of a segment
 * register sets the interrupt shadow (inh). */
static void exec_seg_push_pop(C *c, uint8_t op) {
    switch (op) {
    case 0x06: push16(c, c->sr[SEG_ES]); break;
    case 0x0E: push16(c, c->sr[SEG_CS]); break;
    case 0x16: push16(c, c->sr[SEG_SS]); break;
    case 0x1E: push16(c, c->sr[SEG_DS]); break;
    case 0x07: c->sr[SEG_ES] = pop16(c); c->inh = 1; break;
    case 0x17: c->sr[SEG_SS] = pop16(c); c->inh = 1; break;
    case 0x1F: c->sr[SEG_DS] = pop16(c); c->inh = 1; break;
    }
}

/* Decimal adjusts (orig. L312-316, L376-377).
 * DAA/DAS follow the 8086-family silicon: the +-6 adjust carries/borrows
 * into CF, and the second test looks at the adjusted AL (> 0x9F).
 * AAA/AAS adjust AL and AH separately: the AL +-6 does not carry into
 * the AH adjust.  AAD truncates its result to 8 bits (see below). */
static void exec_decimal(C *c, uint8_t op) {
    switch (op) {
    case 0x27: { /* DAA */
        int al = c->r[REG_AX] & 0xFF, cf = c->cf;
        if ((al & 0xF) > 9 || c->af) {
            al += 6; cf |= al > 0xFF; al &= 0xFF; c->af = 1;
        } else c->af = 0;
        if (al > 0x9F || cf) { al = (al + 0x60) & 0xFF; cf = 1; }
        c->cf = cf;
        setreg(c, REG_AX, 0, (uint32_t)al);
        set_szp(c, (uint32_t)al, 0);
        break;
    }
    case 0x2F: { /* DAS */
        int al = c->r[REG_AX] & 0xFF, cf = c->cf;
        if ((al & 0xF) > 9 || c->af) {
            cf |= al < 6; al = (al - 6) & 0xFF; c->af = 1;
        } else c->af = 0;
        if (al > 0x9F || cf) { al = (al - 0x60) & 0xFF; cf = 1; }
        c->cf = cf;
        setreg(c, REG_AX, 0, (uint32_t)al);
        set_szp(c, (uint32_t)al, 0);
        break;
    }
    case 0x37: /* AAA */
        if ((c->r[REG_AX] & 0xF) > 9 || c->af) {
            c->r[REG_AX] = (uint16_t)(((c->r[REG_AX] & 0xFF00u) + 0x100u) |
                                      ((c->r[REG_AX] + 6) & 0xFFu));
            c->af = c->cf = 1;
        } else c->af = c->cf = 0;
        c->r[REG_AX] &= 0xFF0Fu;
        break;
    case 0x3F: /* AAS */
        if ((c->r[REG_AX] & 0xF) > 9 || c->af) {
            c->r[REG_AX] = (uint16_t)(((c->r[REG_AX] & 0xFF00u) - 0x100u) |
                                      ((c->r[REG_AX] - 6) & 0xFFu));
            c->af = c->cf = 1;
        } else c->af = c->cf = 0;
        c->r[REG_AX] &= 0xFF0Fu;
        break;
    case 0xD4: { /* AAM imm8 */
        uint8_t b = fetch8(c);
        if (!b) { do_int(c, INT_DIVIDE_ERROR); break; }
        uint8_t al = (uint8_t)(c->r[REG_AX] & 0xFF);
        c->r[REG_AX] = (uint16_t)(((al / b) << 8) | (al % b));
        set_szp(c, c->r[REG_AX], 0);
        break;
    }
    case 0xD5: { /* AAD imm8 */
        uint8_t b = fetch8(c);
        /* QUIRK (orig. L377): the sum is stored in a uint8_t, so a base
         * that makes AL + AH*base exceed 255 wraps mod 256 instead of
         * producing the textbook 16-bit result. */
        uint8_t al = (uint8_t)((c->r[REG_AX] & 0xFF) + (c->r[REG_AX] >> 8) * b);
        c->r[REG_AX] = al;
        set_szp(c, al, 0);
        break;
    }
    }
}

/* INC/DEC register, 0x40-0x4F (orig. L317-318). */
static void exec_inc_dec_reg(C *c, uint8_t op) {
    c->r[op & 7] = (uint16_t)incdec(c, c->r[op & 7], (op >> 3) & 1, 1);
}

/* PUSH/POP register, 0x50-0x5F (orig. L319-321).
 * QUIRK (orig. L320): 0x54 pushes the SP value from BEFORE the
 * instruction (the 80186 behaviour, unlike the 8086); the sibling
 * courier-emu agrees. */
static void exec_push_pop_reg(C *c, uint8_t op) {
    if (op >= 0x50 && op <= 0x57) {
        if (op == 0x54) {
            uint16_t v = c->r[REG_SP];
            push16(c, v);
        } else {
            push16(c, c->r[op & 7]);
        }
    } else if (op >= 0x58 && op <= 0x5F) {
        if (op == 0x5C) c->r[REG_SP] = pop16(c);
        else c->r[op & 7] = pop16(c);
    }
}

/* PUSHA/POPA, 0x60/0x61 (orig. L322-323).  PUSHA pushes the SP value
 * from before the instruction; POPA discards the slot where SP would go. */
static void exec_pusha_popa(C *c, uint8_t op) {
    if (op == 0x60) {
        uint16_t sp = c->r[REG_SP];
        push16(c, c->r[REG_AX]); push16(c, c->r[REG_CX]);
        push16(c, c->r[REG_DX]); push16(c, c->r[REG_BX]);
        push16(c, sp);
        push16(c, c->r[REG_BP]); push16(c, c->r[REG_SI]);
        push16(c, c->r[REG_DI]);
    } else {
        c->r[REG_DI] = pop16(c); c->r[REG_SI] = pop16(c);
        c->r[REG_BP] = pop16(c); pop16(c);
        c->r[REG_BX] = pop16(c); c->r[REG_DX] = pop16(c);
        c->r[REG_CX] = pop16(c); c->r[REG_AX] = pop16(c);
    }
}

/* BOUND, 0x62 (orig. L324).  A register operand is a bad opcode; an
 * out-of-range index takes INT 5, which is a trap: the pushed IP is the
 * next instruction. */
static void exec_bound(C *c, uint8_t op) {
    decode_modrm(c);
    if (c->mod == 3) { bad(c, op); return; }
    int16_t idx = (int16_t)c->r[c->regf];
    int16_t lo = (int16_t)mem_read(c, lin(c->ea_seg, c->ea_off), 1);
    int16_t hi = (int16_t)mem_read(c, lin(c->ea_seg, (uint16_t)(c->ea_off + 2)), 1);
    if (idx < lo || idx > hi) do_int(c, INT_BOUND);
}

/* PUSH imm16 / PUSH imm8-sign-extended, 0x68/0x6A (orig. L325-326). */
static void exec_push_imm(C *c, uint8_t op) {
    if (op == 0x68) push16(c, fetch16(c));
    else push16(c, (uint16_t)(int16_t)(int8_t)fetch8(c));
}

/* IMUL r16, r/m16, imm -- 0x69 (imm16) / 0x6B (imm8 sign-extended).
 * (orig. L327).  The 32-bit product is truncated to 16 bits; CF/OF are
 * set when the product does not fit in 16 bits. */
static void exec_imul(C *c, uint8_t op) {
    decode_modrm(c);
    int32_t a = (int16_t)rm_rd(c, 1);
    int32_t b = op == 0x69 ? (int16_t)fetch16(c) : (int8_t)fetch8(c);
    int32_t r = a * b;
    c->r[c->regf] = (uint16_t)r;
    c->cf = c->of = (r != (int16_t)r);
}

/* Conditional jumps, 0x70-0x7F (orig. L330).  Taken: +9 clocks in model 1,
 * +12 in the legacy model, on top of the base charge. */
static void exec_jcc(C *c, uint8_t op) {
    int8_t d = (int8_t)fetch8(c);
    if (cond(c, op & 0xF)) {
        c->ip = (uint16_t)(c->ip + d);
        c->cycles += c->cyc_model ? 9 : 12;
    }
}

/* ALU with an immediate operand, 0x80-0x83 (orig. L331).  The immediate
 * is fetched after the r/m operand is read.  For 0x83 the 8-bit immediate
 * is sign-extended to the operand width. */
static void exec_alu_imm(C *c, uint8_t op, int w) {
    decode_modrm(c);
    uint32_t a = rm_rd(c, w);
    uint32_t b = op == 0x81 ? fetch16(c)
                 : (op == 0x83 ? (uint16_t)(int16_t)(int8_t)fetch8(c)
                               : fetch8(c));
    if (op == 0x83 && !w) b &= 0xFFu;
    uint32_t r = alu(c, c->regf, a, b & width_mask(w), w);
    if (c->regf != ALU_CMP) rm_wr(c, w, r);
}

/* TEST / XCHG / MOV forms, 0x84-0x8F (orig. L332-337).
 * LEA (0x8D) with a register operand is a no-op, not a bad opcode.
 * MOV to a segment register (0x8E) sets the interrupt shadow. */
static void exec_test_xchg_mov(C *c, uint8_t op, int w) {
    switch (op) {
    case 0x84: case 0x85: /* TEST r/m, r */
        decode_modrm(c);
        alu(c, ALU_AND, rm_rd(c, w), getreg(c, c->regf, w), w);
        break;
    case 0x86: case 0x87: { /* XCHG r/m, r */
        decode_modrm(c);
        uint32_t a = rm_rd(c, w), b = getreg(c, c->regf, w);
        rm_wr(c, w, b);
        setreg(c, c->regf, w, a);
        break;
    }
    case 0x88: case 0x89: /* MOV r/m, r */
        decode_modrm(c);
        rm_wr(c, w, getreg(c, c->regf, w));
        break;
    case 0x8A: case 0x8B: /* MOV r, r/m */
        decode_modrm(c);
        setreg(c, c->regf, w, rm_rd(c, w));
        break;
    case 0x8C: /* MOV r/m, sreg */
        decode_modrm(c);
        if (c->regf > 3) { bad(c, op); return; }   /* reg 4-7 is undefined */
        rm_wr(c, 1, c->sr[c->regf & 3]);
        break;
    case 0x8D: /* LEA r, m */
        decode_modrm(c);
        if (c->mod != 3) c->r[c->regf] = c->ea_off;
        break;
    case 0x8E: /* MOV sreg, r/m */
        decode_modrm(c);
        if (c->regf > 3) { bad(c, op); return; }   /* reg 4-7 is undefined */
        c->sr[c->regf & 3] = (uint16_t)rm_rd(c, 1);
        c->inh = 1;
        break;
    case 0x8F: { /* POP r/m: EA is decoded BEFORE the pop */
        decode_modrm(c);
        if (c->regf != 0) { bad(c, op); return; }   /* reg != 0 is undefined */
        uint16_t v = pop16(c);
        rm_wr(c, 1, v);
        break;
    }
    }
}

/* XCHG AX, reg, 0x91-0x97; 0x90 is NOP (orig. L338-339). */
static void exec_xchg_ax(C *c, uint8_t op) {
    uint16_t t = c->r[REG_AX];
    c->r[REG_AX] = c->r[op & 7];
    c->r[op & 7] = t;
}

/* CBW / CWD (orig. L340-341). */
static void exec_cbw_cwd(C *c, uint8_t op) {
    if (op == 0x98) c->r[REG_AX] = (uint16_t)(int16_t)(int8_t)(c->r[REG_AX] & 0xFFu);
    else c->r[REG_DX] = (c->r[REG_AX] & 0x8000u) ? 0xFFFFu : 0;
}

/* CALL far, 0x9A (orig. L342).  QUIRK: the extra 20 clocks are charged
 * ONLY in the legacy model; in model 1 the CYC[0x9A] base (5) stands. */
static void exec_call_far(C *c, uint8_t op) {
    (void)op;
    uint16_t off = fetch16(c), seg = fetch16(c);
    push16(c, c->sr[SEG_CS]);
    push16(c, c->ip);
    c->ip = off;
    c->sr[SEG_CS] = seg;
    if (!c->cyc_model) c->cycles += 20;
}

/* PUSHF / POPF / SAHF / LAHF, 0x9C-0x9F (orig. L344-347).  SAHF loads
 * only CF/PF/AF/ZF/SF from AH; OF/DF/IF/TF are untouched. */
static void exec_pushf_popf(C *c, uint8_t op) {
    switch (op) {
    case 0x9C: push16(c, flags_get(c)); break;
    case 0x9D: flags_set(c, pop16(c)); break;
    case 0x9E: {
        uint8_t f = (uint8_t)(c->r[REG_AX] >> 8);
        c->cf = f & 1; c->pf = (f >> 2) & 1; c->af = (f >> 4) & 1;
        c->zf = (f >> 6) & 1; c->sf = (f >> 7) & 1;
        break;
    }
    case 0x9F:
        c->r[REG_AX] = (uint16_t)((c->r[REG_AX] & 0xFFu) |
                                  ((flags_get(c) & 0xFFu) << 8));
        break;
    }
}

/* MOV AX, moffs / MOV moffs, AX, 0xA0-0xA3 (orig. L348-349).  A segment
 * prefix overrides the default DS. */
static void exec_moffs(C *c, uint8_t op, int w) {
    uint16_t off = fetch16(c);
    uint16_t seg = c->sr[c->seg_ovr >= 0 ? c->seg_ovr : SEG_DS];
    if (op == 0xA0 || op == 0xA1)
        setreg(c, REG_AX, w, mem_read(c, lin(seg, off), w));
    else
        mem_write(c, lin(seg, off), w, getreg(c, REG_AX, w));
}

/* TEST accumulator, 0xA8/0xA9 (orig. L351-352). */
static void exec_test_acc(C *c, uint8_t op, int w) {
    if (op == 0xA8) alu(c, ALU_AND, getreg(c, REG_AX, 0), fetch8(c), 0);
    else alu(c, ALU_AND, c->r[REG_AX], fetch16(c), 1);
    (void)w;
}

/* MOV reg, imm, 0xB0-0xBF (orig. L353-354). */
static void exec_mov_imm(C *c, uint8_t op) {
    if (op < 0xB8) setreg(c, op & 7, 0, fetch8(c));
    else c->r[op & 7] = fetch16(c);
}

/* Shifts by an 8-bit immediate, 0xC0/0xC1 (orig. L355-357).
 * QUIRK: the model-1 extra is (mod==3 ? 0 : 6) + (n & 31) - 1, so a
 * shift count of 0 SUBTRACTS one clock (5+n reg / 17+n mem in the
 * manual's terms, with n the masked count).  Kept verbatim, including
 * the unsigned wrap of the subtraction. */
static void exec_shift_imm(C *c, uint8_t op, int w) {
    decode_modrm(c);
    if (c->regf == 6) { bad(c, op); return; }   /* reg 6 is undefined */
    uint32_t v = rm_rd(c, w);
    int n = fetch8(c);
    if (c->cyc_model) c->cycles += (c->mod == 3 ? 0 : 6) + (n & 31) - 1;
    rm_wr(c, w, shift(c, c->regf, v, n, w));
}

/* RET / RETF, 0xC2/0xC3/0xCA/0xCB (orig. L358-359, L367-368). */
static void exec_ret(C *c, uint8_t op) {
    switch (op) {
    case 0xC2: {
        uint16_t n = fetch16(c);
        c->ip = pop16(c);
        c->r[REG_SP] = (uint16_t)(c->r[REG_SP] + n);
        break;
    }
    case 0xC3: c->ip = pop16(c); break;
    case 0xCA: {
        uint16_t n = fetch16(c);
        c->ip = pop16(c);
        c->sr[SEG_CS] = pop16(c);
        c->r[REG_SP] = (uint16_t)(c->r[REG_SP] + n);
        break;
    }
    case 0xCB:
        c->ip = pop16(c);
        c->sr[SEG_CS] = pop16(c);
        break;
    }
}

/* LES / LDS, 0xC4/0xC5 (orig. L360).  A register operand is a bad opcode.
 * The segment word is read from ea+2 (no 16-bit wrap on the offset). */
static void exec_les_lds(C *c, uint8_t op) {
    decode_modrm(c);
    if (c->mod == 3) { bad(c, op); return; }
    uint32_t a = lin(c->ea_seg, c->ea_off);
    c->r[c->regf] = (uint16_t)mem_read(c, a, 1);
    c->sr[op == 0xC4 ? SEG_ES : SEG_DS] = (uint16_t)mem_read(c, a + 2, 1);
}

/* MOV r/m, imm, 0xC6/0xC7 (orig. L361). */
static void exec_mov_rm_imm(C *c, uint8_t op, int w) {
    decode_modrm(c);
    if (c->regf != 0) { bad(c, op); return; }   /* reg != 0 is undefined */
    uint32_t v = w ? fetch16(c) : fetch8(c);
    rm_wr(c, w, v);
}

/* ENTER / LEAVE, 0xC8/0xC9 (orig. L362-366).  ENTER pushes BP, then for
 * nesting level > 1 pushes the chain of saved frame pointers from below
 * the new frame (BP is decremented before each read), then pushes the
 * new frame pointer; BP is set to it and SP drops by the frame size. */
static void exec_enter_leave(C *c, uint8_t op) {
    if (op == 0xC8) {
        uint16_t size = fetch16(c);
        int lvl = fetch8(c) & 31;
        push16(c, c->r[REG_BP]);
        uint16_t fp = c->r[REG_SP];
        if (lvl > 0) {
            for (int i = 1; i < lvl; i++) {
                c->r[REG_BP] = (uint16_t)(c->r[REG_BP] - 2);
                push16(c, (uint16_t)mem_read(c, lin(c->sr[SEG_SS], c->r[REG_BP]), 1));
            }
            push16(c, fp);
        }
        c->r[REG_BP] = fp;
        c->r[REG_SP] = (uint16_t)(c->r[REG_SP] - size);
    } else {
        c->r[REG_SP] = c->r[REG_BP];
        c->r[REG_BP] = pop16(c);
    }
}

/* INT3 / INT imm / INTO / IRET, 0xCC-0xCF (orig. L369-372).  INTO takes
 * INT 4 only when OF is set.  IRET pops IP, CS, then FLAGS. */
static void exec_int(C *c, uint8_t op) {
    switch (op) {
    case 0xCC: do_int(c, INT_BREAKPOINT); break;
    case 0xCD: do_int(c, fetch8(c)); break;
    case 0xCE: if (c->of) do_int(c, INT_OVERFLOW); break;
    case 0xCF:
        c->ip = pop16(c);
        c->sr[SEG_CS] = pop16(c);
        flags_set(c, pop16(c));
        break;
    }
}

/* Shifts by 1 or by CL, 0xD0-0xD3 (orig. L373-375).
 * QUIRK: the model-1 extra for a by-1 register shift is -2 clocks (the
 * expression is (mod==3 ? -2 : 5)), so a register shift-by-1 SUBTRACTS
 * two clocks; a by-CL shift adds (mod==3 ? 0 : 6) + (n & 31) + 1.
 * Kept verbatim, including the unsigned wrap. */
static void exec_shift_1_cl(C *c, uint8_t op, int w) {
    decode_modrm(c);
    if (c->regf == 6) { bad(c, op); return; }   /* reg 6 is undefined */
    uint32_t v = rm_rd(c, w);
    int n = (op & 2) ? (c->r[REG_CX] & 0xFF) : 1;
    if (c->cyc_model) {
        c->cycles += (op & 2) ? (c->mod == 3 ? 0 : 6) + (n & 31) + 1
                              : (c->mod == 3 ? -2 : 5);
    }
    rm_wr(c, w, shift(c, c->regf, v, n, w));
}

/* XLAT, 0xD7 (orig. L379).  The table is in the (possibly overridden)
 * DS segment at BX + AL; the offset wraps at 16 bits. */
static void exec_xlat(C *c, uint8_t op) {
    (void)op;
    uint16_t seg = c->sr[c->seg_ovr >= 0 ? c->seg_ovr : SEG_DS];
    uint16_t off = (uint16_t)(c->r[REG_BX] + (c->r[REG_AX] & 0xFFu));
    setreg(c, REG_AX, 0, mem_read(c, lin(seg, off), 0));
}

/* LOOP / LOOPcc / JCXZ, 0xE0-0xE3 (orig. L381-382).  LOOP decrements CX
 * first and branches while it is non-zero; 0xE0 also requires ZF==0,
 * 0xE1 requires ZF==1.  A taken branch adds 10 clocks in model 1 only.
 * (The "taken 16, not taken 6" comment in the original sits on the JCXZ
 * case; the base CYC for 0xE0-0xE3 is 6 in both models.) */
static void exec_loop(C *c, uint8_t op) {
    if (op == 0xE3) {
        int8_t d = (int8_t)fetch8(c);
        if (!c->r[REG_CX]) {
            c->ip = (uint16_t)(c->ip + d);
            if (c->cyc_model) c->cycles += 10;
        }
        return;
    }
    int8_t d = (int8_t)fetch8(c);
    c->r[REG_CX]--;
    int taken = c->r[REG_CX] != 0;
    if (op == 0xE0) taken = taken && !c->zf;
    else if (op == 0xE1) taken = taken && c->zf;
    if (taken) {
        c->ip = (uint16_t)(c->ip + d);
        if (c->cyc_model) c->cycles += 10;
    }
}

/* IN/OUT with an 8-bit immediate port, 0xE4-0xE7 (orig. L383-384). */
static void exec_in_out_imm(C *c, uint8_t op, int w) {
    uint8_t p = fetch8(c);
    if (op == 0xE4 || op == 0xE5) setreg(c, REG_AX, w, io_read(c, p, w));
    else io_write(c, p, w, getreg(c, REG_AX, w));
}

/* CALL/JMP, 0xE8-0xEB (orig. L385-388). */
static void exec_call_jmp(C *c, uint8_t op) {
    switch (op) {
    case 0xE8: {
        int16_t d = (int16_t)fetch16(c);
        push16(c, c->ip);
        c->ip = (uint16_t)(c->ip + d);
        break;
    }
    case 0xE9: {
        int16_t d = (int16_t)fetch16(c);
        c->ip = (uint16_t)(c->ip + d);
        break;
    }
    case 0xEA: {
        uint16_t off = fetch16(c), seg = fetch16(c);
        c->ip = off;
        c->sr[SEG_CS] = seg;
        break;
    }
    case 0xEB: {
        int8_t d = (int8_t)fetch8(c);
        c->ip = (uint16_t)(c->ip + d);
        break;
    }
    }
}

/* IN/OUT through DX, 0xEC-0xEF (orig. L389-390). */
static void exec_in_out_dx(C *c, uint8_t op, int w) {
    if (op == 0xEC || op == 0xED) setreg(c, REG_AX, w, io_read(c, c->r[REG_DX], w));
    else io_write(c, c->r[REG_DX], w, getreg(c, REG_AX, w));
}

/* HLT / CMC, 0xF4/0xF5 (orig. L391-392). */
static void exec_halt_cmc(C *c, uint8_t op) {
    if (op == 0xF4) c->halted = 1;
    else c->cf = !c->cf;
}

/* Group F6/F7: TEST / NOT / NEG / MUL / IMUL / DIV / IDIV (orig. L393-408).
 * The immediate for TEST is fetched AFTER the r/m operand is read.
 * MUL/IMUL/DIV/IDIV add their model-1 extra on top of the CYC base and
 * of the decode_modrm memory charge (App. D: MUL r8 26-28, r16 35-37;
 * IMUL r8 25-28, r16 34-37; DIV/IDIV r8 29, r16 38).
 * DIV/IDIV overflow (including divide by zero) takes INT 0 with IP
 * pointing at the next instruction. */
static void exec_group_f6f7(C *c, uint8_t op, int w) {
    decode_modrm(c);
    if (c->regf == 1) { bad(c, op); return; }   /* reg 1 is undefined */
    uint32_t v = rm_rd(c, w);
    switch (c->regf) {
    case 0: case 1: /* TEST r/m, imm */
        alu(c, ALU_AND, v, w ? fetch16(c) : fetch8(c), w);
        break;
    case 2: /* NOT r/m */
        rm_wr(c, w, ~v);
        break;
    case 3: { /* NEG r/m: CF is set from the operand, not from the ALU */
        uint32_t r = alu(c, ALU_SUB, 0, v, w);
        c->cf = v != 0;
        rm_wr(c, w, r);
        break;
    }
    case 4: /* MUL r/m */
        if (c->cyc_model) c->cycles += w ? 33 : 24;
        if (w) {
            uint32_t r = (uint32_t)c->r[REG_AX] * v;
            c->r[REG_AX] = (uint16_t)r;
            c->r[REG_DX] = (uint16_t)(r >> 16);
            c->cf = c->of = (r >> 16) != 0;
        } else {
            uint32_t r = (c->r[REG_AX] & 0xFFu) * v;
            c->r[REG_AX] = (uint16_t)r;
            c->cf = c->of = (r >> 8) != 0;
        }
        break;
    case 5: /* IMUL r/m */
        if (c->cyc_model) c->cycles += w ? 33 : 24;
        if (w) {
            int32_t r = (int32_t)(int16_t)c->r[REG_AX] * (int16_t)v;
            c->r[REG_AX] = (uint16_t)r;
            c->r[REG_DX] = (uint16_t)(r >> 16);
            c->cf = c->of = (r != (int16_t)r);
        } else {
            int32_t r = (int8_t)c->r[REG_AX] * (int8_t)v;
            c->r[REG_AX] = (uint16_t)r;
            c->cf = c->of = (r != (int8_t)r);
        }
        break;
    case 6: /* DIV r/m */
        if (c->cyc_model) c->cycles += w ? 35 : 26;
        if (w) {
            uint32_t n = ((uint32_t)c->r[REG_DX] << 16) | c->r[REG_AX];
            if (!v || n / v > 0xFFFFu) { do_int(c, INT_DIVIDE_ERROR); break; }
            c->r[REG_AX] = (uint16_t)(n / v);
            c->r[REG_DX] = (uint16_t)(n % v);
        } else {
            uint32_t n = c->r[REG_AX];
            if (!v || n / v > 0xFFu) { do_int(c, INT_DIVIDE_ERROR); break; }
            c->r[REG_AX] = (uint16_t)(((n % v) << 8) | (n / v));
        }
        break;
    case 7: /* IDIV r/m */
        if (c->cyc_model) c->cycles += w ? 35 : 26;
        if (w) {
            int64_t n = (int32_t)(((uint32_t)c->r[REG_DX] << 16) | c->r[REG_AX]);
            int64_t d = (int16_t)v;
            if (!d || n / d > 32767 || n / d < -32768) {
                do_int(c, INT_DIVIDE_ERROR);
                break;
            }
            c->r[REG_AX] = (uint16_t)(n / d);
            c->r[REG_DX] = (uint16_t)(n % d);
        } else {
            int32_t n = (int16_t)c->r[REG_AX];
            int32_t d = (int8_t)v;
            if (!d || n / d > 127 || n / d < -128) {
                do_int(c, INT_DIVIDE_ERROR);
                break;
            }
            c->r[REG_AX] = (uint16_t)((((n % d) & 0xFF) << 8) | ((n / d) & 0xFF));
        }
        break;
    }
}

/* Flag operations, 0xF8-0xFD (orig. L409-410).  STI sets the interrupt
 * shadow; CLI/STI act immediately on IF itself. */
static void exec_flag_ops(C *c, uint8_t op) {
    switch (op) {
    case 0xF8: c->cf = 0; break;
    case 0xF9: c->cf = 1; break;
    case 0xFA: c->ifl = 0; break;
    case 0xFB: c->ifl = 1; c->inh = 1; break;
    case 0xFC: c->df = 0; break;
    case 0xFD: c->df = 1; break;
    }
}

/* Group FE: INC/DEC r/m8, 0xFE (orig. L411).  reg > 1 is a bad opcode. */
static void exec_group_fe(C *c, uint8_t op) {
    decode_modrm(c);
    if (c->regf > 1) { bad(c, op); return; }
    rm_wr(c, 0, incdec(c, rm_rd(c, 0), c->regf, 0));
}

/* Group FF (orig. L412-425).  Far forms with a register operand are bad
 * opcodes; anything else in reg 7 is a bad opcode.  The model-1 extras
 * are +10 (near indirect CALL), +28 (far indirect CALL) and +8
 * (indirect JMP). */
static void exec_group_ff(C *c, uint8_t op) {
    decode_modrm(c);
    switch (c->regf) {
    case 0: case 1: /* INC/DEC r/m16 */
        rm_wr(c, 1, incdec(c, rm_rd(c, 1), c->regf, 1));
        break;
    case 2: { /* CALL r/m16: the target is read before IP is pushed */
        uint16_t t = (uint16_t)rm_rd(c, 1);
        push16(c, c->ip);
        c->ip = t;
        if (c->cyc_model) c->cycles += 10;
        break;
    }
    case 3: { /* CALL far r/m */
        if (c->mod == 3) { bad(c, op); return; }
        uint32_t a = lin(c->ea_seg, c->ea_off);
        uint16_t off = (uint16_t)mem_read(c, a, 1);
        uint16_t seg = (uint16_t)mem_read(c, a + 2, 1);
        push16(c, c->sr[SEG_CS]);
        push16(c, c->ip);
        c->ip = off;
        c->sr[SEG_CS] = seg;
        if (c->cyc_model) c->cycles += 28;
        break;
    }
    case 4: /* JMP r/m16 */
        c->ip = (uint16_t)rm_rd(c, 1);
        if (c->cyc_model) c->cycles += 8;
        break;
    case 5: { /* JMP far r/m */
        if (c->mod == 3) { bad(c, op); return; }
        uint32_t a = lin(c->ea_seg, c->ea_off);
        c->ip = (uint16_t)mem_read(c, a, 1);
        c->sr[SEG_CS] = (uint16_t)mem_read(c, a + 2, 1);
        break;
    }
    case 6: { /* PUSH r/m16 */
        uint16_t v = (uint16_t)rm_rd(c, 1);
        push16(c, v);
        break;
    }
    default:
        bad(c, op);
        break;
    }
}

/* ------------------------------------------------------------------ */
/* Opcode dispatch (the original exec1() switch, orig. L308-426).      */
/* ALU forms are handled before this, in exec_alu_forms().  String    */
/* opcodes go straight to strop().  0x9B (WAIT) is a no-op.  Anything  */
/* not listed is a bad opcode.                                        */
/* ------------------------------------------------------------------ */
static void dispatch(C *c, uint8_t op, int w) {
    switch (op) {
    case 0x06: case 0x0E: case 0x16: case 0x1E:
    case 0x07: case 0x17: case 0x1F:
        exec_seg_push_pop(c, op);
        break;
    case 0x27: case 0x2F: case 0x37: case 0x3F:
    case 0xD4: case 0xD5:
        exec_decimal(c, op);
        break;
    case 0x40: case 0x41: case 0x42: case 0x43:
    case 0x44: case 0x45: case 0x46: case 0x47:
    case 0x48: case 0x49: case 0x4A: case 0x4B:
    case 0x4C: case 0x4D: case 0x4E: case 0x4F:
        exec_inc_dec_reg(c, op);
        break;
    case 0x50: case 0x51: case 0x52: case 0x53: case 0x54:
    case 0x55: case 0x56: case 0x57:
    case 0x58: case 0x59: case 0x5A: case 0x5B: case 0x5C:
    case 0x5D: case 0x5E: case 0x5F:
        exec_push_pop_reg(c, op);
        break;
    case 0x60: case 0x61:
        exec_pusha_popa(c, op);
        break;
    case 0x62:
        exec_bound(c, op);
        break;
    case 0x68: case 0x6A:
        exec_push_imm(c, op);
        break;
    case 0x69: case 0x6B:
        exec_imul(c, op);
        break;
    case 0x6C: case 0x6D: case 0x6E: case 0x6F:
        strop(c, op);
        break;
    case 0x70: case 0x71: case 0x72: case 0x73:
    case 0x74: case 0x75: case 0x76: case 0x77:
    case 0x78: case 0x79: case 0x7A: case 0x7B:
    case 0x7C: case 0x7D: case 0x7E: case 0x7F:
        exec_jcc(c, op);
        break;
    case 0x80: case 0x81: case 0x82: case 0x83:
        exec_alu_imm(c, op, w);
        break;
    case 0x84: case 0x85: case 0x86: case 0x87:
    case 0x88: case 0x89: case 0x8A: case 0x8B:
    case 0x8C: case 0x8D: case 0x8E: case 0x8F:
        exec_test_xchg_mov(c, op, w);
        break;
    case 0x90:
        break; /* NOP */
    case 0x91: case 0x92: case 0x93: case 0x94:
    case 0x95: case 0x96: case 0x97:
        exec_xchg_ax(c, op);
        break;
    case 0x98: case 0x99:
        exec_cbw_cwd(c, op);
        break;
    case 0x9A:
        exec_call_far(c, op);
        break;
    case 0x9B:
        break; /* WAIT: no-op */
    case 0x9C: case 0x9D: case 0x9E: case 0x9F:
        exec_pushf_popf(c, op);
        break;
    case 0xA0: case 0xA1: case 0xA2: case 0xA3:
        exec_moffs(c, op, w);
        break;
    case 0xA4: case 0xA5: case 0xA6: case 0xA7:
    case 0xAA: case 0xAB: case 0xAC: case 0xAD:
    case 0xAE: case 0xAF:
        strop(c, op);
        break;
    case 0xA8: case 0xA9:
        exec_test_acc(c, op, w);
        break;
    case 0xB0: case 0xB1: case 0xB2: case 0xB3:
    case 0xB4: case 0xB5: case 0xB6: case 0xB7:
    case 0xB8: case 0xB9: case 0xBA: case 0xBB:
    case 0xBC: case 0xBD: case 0xBE: case 0xBF:
        exec_mov_imm(c, op);
        break;
    case 0xC0: case 0xC1:
        exec_shift_imm(c, op, w);
        break;
    case 0xC2: case 0xC3: case 0xCA: case 0xCB:
        exec_ret(c, op);
        break;
    case 0xC4: case 0xC5:
        exec_les_lds(c, op);
        break;
    case 0xC6: case 0xC7:
        exec_mov_rm_imm(c, op, w);
        break;
    case 0xC8: case 0xC9:
        exec_enter_leave(c, op);
        break;
    case 0xCC: case 0xCD: case 0xCE: case 0xCF:
        exec_int(c, op);
        break;
    case 0xD0: case 0xD1: case 0xD2: case 0xD3:
        exec_shift_1_cl(c, op, w);
        break;
    case 0xD7:
        exec_xlat(c, op);
        break;
    case 0xD8: case 0xD9: case 0xDA: case 0xDB:
    case 0xDC: case 0xDD: case 0xDE: case 0xDF:
        decode_modrm(c); /* ESC: decode and ignore */
        break;
    case 0xE0: case 0xE1: case 0xE2: case 0xE3:
        exec_loop(c, op);
        break;
    case 0xE4: case 0xE5: case 0xE6: case 0xE7:
        exec_in_out_imm(c, op, w);
        break;
    case 0xE8: case 0xE9: case 0xEA: case 0xEB:
        exec_call_jmp(c, op);
        break;
    case 0xEC: case 0xED: case 0xEE: case 0xEF:
        exec_in_out_dx(c, op, w);
        break;
    case 0xF4: case 0xF5:
        exec_halt_cmc(c, op);
        break;
    case 0xF6: case 0xF7:
        exec_group_f6f7(c, op, w);
        break;
    case 0xF8: case 0xF9: case 0xFA: case 0xFB: case 0xFC: case 0xFD:
        exec_flag_ops(c, op);
        break;
    case 0xFE:
        exec_group_fe(c, op);
        break;
    case 0xFF:
        exec_group_ff(c, op);
        break;
    default:
        bad(c, op);
        break;
    }
}

/* Fetch the opcode, consuming any prefixes (orig. L288-293).
 *
 * QUIRK -- segment prefixes in the legacy cycle model (orig. L291-292):
 * the prefix loop charges 2 clocks for a segment prefix (or LOCK) ONLY
 * when cyc_model is 1, and the else-if chain that recognises REP/LOCK
 * is attached to that same if.  So in the legacy model (cyc_model == 0)
 * a segment-override byte does NOT continue the loop: it falls through
 * to `break` and is decoded as opcode 0x26/0x2E/0x36/0x3E, which ends in
 * ST_BADOP (or INT 6 with ud_trap).  In other words, segment overrides
 * only take effect in cycle model 1.  LOCK (0xF0) is recognised in both
 * models, and REP/REPNE in both models.  This is almost certainly a bug
 * in the original, but the firmware runs in cycle model 1 and the task
 * is to preserve behaviour, so the control flow below reproduces it
 * exactly -- including setting seg_ovr before the break, which is
 * harmless because the bad-opcode path restores CS:IP and exec1() resets
 * seg_ovr on the next instruction. */
static uint8_t fetch_opcode(C *c) {
    for (;;) {
        uint8_t op = fetch8(c);
        if (op == PREFIX_ES) c->seg_ovr = SEG_ES;
        else if (op == PREFIX_CS) c->seg_ovr = SEG_CS;
        else if (op == PREFIX_SS) c->seg_ovr = SEG_SS;
        else if (op == PREFIX_DS) c->seg_ovr = SEG_DS;

        if (op == PREFIX_ES || op == PREFIX_CS || op == PREFIX_SS ||
            op == PREFIX_DS || op == PREFIX_LOCK) {
            if (c->cyc_model) c->cycles += 2; /* prefix: 2 clocks, model 1 only */
        }
        else if (op == PREFIX_REPNE) { c->rep = 1; c->repz = 0; }
        else if (op == PREFIX_REP) { c->rep = 1; c->repz = 1; }
        else if (op == PREFIX_LOCK) { /* LOCK: accepted, no effect */ }
        else return op;
    }
}

/* Execute one instruction (orig. L283-295): trace it, fetch prefixes +
 * opcode, charge the base cycles, dispatch. */
static void exec1(C *c) {
    uint32_t pc0 = lin(c->sr[SEG_CS], c->ip);
    c->pstart = c->ip;
    c->cur_pc = pc0;
    c->hits[pc0]++;
    c->ring[c->ring_i++ & I186_RING_MASK] = pc0;
    c->seg_ovr = -1;
    c->rep = 0;
    c->repz = 0;

    uint8_t op = fetch_opcode(c);
    c->opc = op;
    c->cycles += c->cyc_model ? CYC[op] : 4;
    int w = op & 1;

    if (exec_alu_forms(c, op, w)) return;
    dispatch(c, op, w);
}

/* ------------------------------------------------------------------ */
/* Run loop.                                                          */
/* ------------------------------------------------------------------ */

/* Run until the cycle budget is exhausted; returns enum i186_status
 * (orig. L428-452).
 *
 * Per iteration, in this order:
 *  1. Take a pending NMI (type 2), else a pending maskable IRQ if IF is
 *     set and the interrupt shadow (inh) from the previous instruction
 *     has expired.  Either clears HLT.  NMI also clears inh; the IRQ
 *     path relies on the inh=0 below.  A pending request with IF=0
 *     cannot wake a halted CPU (NMI can).
 *  2. If still halted, consume the rest of the budget and return ST_HLT.
 *  3. Breakpoint check -- skipped for the very first instruction of the
 *     run, even if a breakpoint is set at the entry PC.
 *  4. Clear the interrupt shadow (it covers exactly one instruction),
 *     execute one instruction, then apply the cycle scale: in model 1
 *     with cscale != 1.0 the clocks charged by that instruction are
 *     multiplied by cscale, the fractional remainder carried forward.
 *  5. Bad opcode: restore CS:IP to the faulting instruction; with
 *     ud_trap off return ST_BADOP, with it on take INT 6 (the pushed IP
 *     is the faulting instruction's, manual 5.1) and continue -- the
 *     single-step and stop checks are skipped for that iteration.
 *  6. Single-step trap: if TF was set at the start of the instruction
 *     and is still set afterwards (and the CPU did not halt), take
 *     INT 1.  Vectoring clears TF, so the trap fires once.
 *  7. If i186_stop() was called, return ST_STOP.
 */
int i186_run(C *c, uint64_t budget) {
    uint64_t end = c->cycles + budget;
    int first = 1;
    c->run_end = end;
    c->stop = 0;
    c->status = ST_OK;
    while (c->cycles < end) {
        if (c->nmi_pending) {
            c->halted = 0;
            c->nmi_pending = 0;
            c->inh = 0;
            do_int(c, INT_NMI);
        } else if (c->irq_pending && c->ifl && !c->inh) {
            c->halted = 0;
            c->irq_pending = 0;
            do_int(c, c->irq_vec);
        }
        if (c->halted) {
            c->cycles = end;
            return ST_HLT;
        }
        uint32_t p = lin(c->sr[SEG_CS], c->ip);
        if (!first && c->bp[p]) return ST_BP;
        first = 0;

        uint16_t ip0 = c->ip, cs0 = c->sr[SEG_CS];
        int tf0 = c->tf;
        c->inh = 0; /* the shadow covers exactly one instruction; STI /
                     * segment loads set it again */
        uint64_t cycles_before = c->cycles;
        exec1(c);
        if (c->cscale != 1.0 && c->cyc_model) {
            double charged = (double)(c->cycles - cycles_before) * c->cscale +
                             c->cfrac;
            uint64_t whole = (uint64_t)charged;
            c->cfrac = charged - (double)whole;
            c->cycles = cycles_before + whole;
        }
        if (c->status == ST_BADOP) {
            c->ip = ip0;
            c->sr[SEG_CS] = cs0;
            if (!c->ud_trap) return ST_BADOP;
            c->status = ST_OK;
            do_int(c, INT_BADOP);
            continue;
        }
        if (tf0 && c->tf && !c->halted) do_int(c, INT_SINGLE_STEP);
        if (c->stop) return ST_STOP;
    }
    return ST_OK;
}
