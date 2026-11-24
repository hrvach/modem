/*
   c5x_core.c -- TMS320C5x (C51 flavour) instruction-set emulator

   What it is
     Executes the DSP half of the modem: 64K words each of program, data
     and I/O space, the on-chip peripherals (serial port, timer, wait-state
     registers), interrupts, and the repeat instructions.  The glue code
     talks to it only through c5x_core.h.

   References
     Semantics follow the TI C5x User's Guide (SPRU056D).  MAME's
     tms320c5x core was used as a cross-check where it implements an
     instruction (it stubs about 70 that this firmware uses heavily).
     Comments that say "manual x.y" point at SPRU056D.

   Firmware
     The core never patches the firmware; it only executes the image it
     is given.  See the Makefile for where the image comes from.

   Quirks
     Where the core does something the manual does not describe, the
     comment says QUIRK.  The firmware depends on these, so they are kept.

   Cycle model
     Cycle counts come from the generated table in c5x_cyctab.h (do not
     edit it by hand).  With the cycle model off every instruction costs
     one cycle.

   Layout of this file
     1. constants, state and the RPTB block cache
     2. reset, register access, I/O and memory-mapped registers
     3. data and program memory access
     4. arithmetic and addressing helpers
     5. interrupts and the timer
     6. instruction execution, one function per opcode range
     7. the repeat-block cache and the run loop, c5x_run()
     8. small accessors for the glue code

   Build:  gcc -O2 -Wall -Wextra -c -Isrc/dsp src/dsp/c5x_core.c
*/
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "c5x_core.h"
#include "c5x_opcodes.h"
#include "c5x_cyctab.h" /* static const uint8_t cyc_tab[65536]; generated data */

/* The 16-bit opcode word with the given high byte and low byte. */
#define OPCODE_WORD(high_byte, low_byte) (((high_byte) << 8) | (low_byte))

/* Fields of an instruction word. */
static inline int opcode_high_byte(uint16_t op) {
    return op >> 8;
}

static inline int opcode_low_byte(uint16_t op) {
    return op & 0xFF;
}

/* The auxiliary register number in the high byte of LAR, SAR and LAR #k8. */
static inline int opcode_ar_number(uint16_t op) {
    return (op >> 8) & C5X_OP_AR_MASK;
}

/* The shift count or bit number in the high byte of LACC, ADD, SUB and BIT. */
static inline int opcode_shift(uint16_t op) {
    return (op >> 8) & C5X_OP_SHIFT_MASK;
}

/* The left shift (0-7) in the high byte of SACL and SACH. */
static inline int opcode_sacx_shift(uint16_t op) {
    return (op >> 8) & C5X_OP_SACX_SHIFT_MASK;
}

/* The 8-bit immediate in the low byte. */
static inline uint16_t opcode_k8(uint16_t op) {
    return op & C5X_K8_MASK;
}

/* MPY #k13: the immediate is a signed 13-bit value in the low bits of the word. */
#define K13_MASK 0x1FFF
#define K13_SIGN_BIT 0x1000
#define K13_RANGE 0x2000

/* ------------------------------------------------------------------
   Named constants
   ------------------------------------------------------------------ */

#define IOLOG_N 65536    /* I/O log capacity */
#define PC_RING_N 256    /* recent-PC ring size */
#define TRACE_N 8192     /* trace-buffer capacity */
#define DXR_RING_N 65536 /* DXR write ring size (wraps at 0xFFFF) */
#define STACK_N 8        /* 8-deep hardware stack */
#define N_AR 8           /* auxiliary registers AR0..AR7 */
#define N_MMR 0x60       /* memory-mapped registers, data 0x00..0x5F */
#define N_INT 9          /* interrupt sources INT1..INT4 (bits 0..8) */

/* Data-space regions (manual ch. 8; see dm_internal()). */
#define DM_B2_END 0x80    /* B2 block: 0x60..0x7F (0x00..0x5F are MMRs) */
#define DM_B0_START 0x100 /* B0/B1 blocks: 0x100..0x4FF */
#define DM_B0_END 0x500
#define DM_B0_CNF_END 0x300  /* with CNF=1, B0 (0x100..0x2FF) leaves data space */
#define DM_SARAM_START 0x800 /* SARAM: 0x800..0xBFF, data space only if OVLY=1 */
#define DM_SARAM_END 0xC00
#define DM_RSV_START 0x500 /* reserved range 0x500..0x7FF (diagnostic only) */
#define DM_RSV_END 0x800
#define DM_FF_START 0xFF00      /* 0xFFxx page (diagnostic counters) */
#define DM_HOSTWIN_START 0xFF50 /* external host window 0xFF50..0xFF5F */
#define DM_HOSTWIN_END 0xFF5F
#define DM_MMR_END 0x60      /* MMRs live at data 0x00..0x5F */
#define DM_PERIPH_START 0x20 /* peripheral MMRs 0x20..0x4F cost a bus cycle */
#define DM_PERIPH_END 0x50

/* Program-space overlays (program_ptr()). */
#define PM_B0_START 0xFE00    /* with CNF=1, program 0xFE00.. maps to data B0 */
#define PM_SARAM_START 0x2000 /* with RAM=1, program 0x2000..0x23FF maps to SARAM */
#define PM_SARAM_END 0x2400

/* Memory-mapped registers: their addresses in data space (manual ch. 3). */
enum {
    MMR_IMR = 0x04,   /* interrupt mask */
    MMR_GREG = 0x05,  /* global memory allocation */
    MMR_IFR = 0x06,   /* interrupt flags */
    MMR_PMST = 0x07,  /* processor mode status */
    MMR_RPTC = 0x08,  /* repeat counter */
    MMR_BRCR = 0x09,  /* block repeat counter */
    MMR_PASR = 0x0A,  /* block repeat start address */
    MMR_PAER = 0x0B,  /* block repeat end address */
    MMR_TREG0 = 0x0C, /* temporary register 0 (multiplicand) */
    MMR_TREG1 = 0x0D, /* temporary register 1 (shift count) */
    MMR_TREG2 = 0x0E, /* temporary register 2 (bit number) */
    MMR_DBMR = 0x0F,  /* dynamic bit manipulation register */
    MMR_AR0 = 0x10,   /* auxiliary registers AR0..AR7 at 0x10..0x17 */
    MMR_AR_END = 0x18,
    MMR_INDX = 0x18,  /* index register */
    MMR_ARCR = 0x19,  /* auxiliary register compare register */
    MMR_CBSR1 = 0x1A, /* circular buffer 1 start */
    MMR_CBER1 = 0x1B, /* circular buffer 1 end */
    MMR_CBSR2 = 0x1C,
    MMR_CBER2 = 0x1D,
    MMR_CBCR = 0x1E,  /* circular buffer control */
    MMR_BMAR = 0x1F,  /* block move address register */
    MMR_DRR = 0x20,   /* serial port receive register */
    MMR_DXR = 0x21,   /* serial port transmit register */
    MMR_SPC = 0x22,   /* serial port control */
    MMR_TIM = 0x24,   /* timer counter */
    MMR_PRD = 0x25,   /* timer period */
    MMR_TCR = 0x26,   /* timer control */
    MMR_PDWSR = 0x28, /* program/data wait-state register */
    MMR_IOWSR = 0x29, /* I/O wait-state register */
    MMR_CWSR = 0x2A,  /* wait-state control register */
    MMR_WAIT_STATE_LAST = MMR_CWSR,
    MMR_CIRCULAR_FIRST = MMR_CBSR1,
    MMR_UNDOCUMENTED_32 = 0x32, /* written by the firmware; diagnostics always keep its latest value */
    MMR_IO_WINDOW = 0x50        /* 0x50 and up: I/O ports reached through data space */
};

/* Width of the implemented bits of some registers. */
#define TREG1_MASK 0x1F
#define TREG2_MASK 0x0F
#define CBCR_MASK 0xFF
#define CWSR_MASK 0x1F

/* Status-register bit positions (manual ch. 3). */
#define ST0_ARP_SHIFT 13
#define ST0_OV_BIT 12
#define ST0_OVM_BIT 11
#define ST0_INT_BIT 10 /* hardwired 1 in ST0 reads */
#define ST0_INTM_BIT 9
#define ST1_ARB_SHIFT 13
#define ST1_CNF_BIT 12
#define ST1_TC_BIT 11
#define ST1_SXM_BIT 10
#define ST1_C_BIT 9
#define ST1_HM_BIT 6
#define ST1_XF_BIT 4
#define PMST_IPTR_SHIFT 11
#define PMST_AVIS_BIT 7
#define PMST_OVLY_BIT 5
#define PMST_RAM_BIT 4
#define PMST_MPMC_BIT 3
#define PMST_NDX_BIT 2
#define PMST_TRM_BIT 1

/* Interrupt-vector table offsets (manual 8.2.2). */
#define IVEC_RSVD 0x00 /* vectors 9..15 are unused (0) */

/* Serial port control (SPC, data 0x22; manual Table 9-13). */
#define SPC_RRST_BIT 0x80        /* receiver reset/enable */
#define SPC_XRST_BIT 0x40        /* transmitter reset/enable */
#define SPC_DLB_BIT 0x02         /* digital loopback: DXR feeds DRR */
#define SPC_WRITABLE_MASK 0xC0FE /* writable SPC bits; 13..8 and bit 0 are status */
#define SPC_RSRFULL_BIT 13
#define SPC_XSREMPTY_BIT 12
#define SPC_XRDY_BIT 11
#define SPC_RRDY_BIT 10

/* Timer control (TCR, data 0x26; manual 9.4). */
#define TCR_PSC_SHIFT 6
#define TCR_TSS_BIT 4
#define TCR_TRB_BIT 0x20 /* reload TIM from PRD and PSC from TDDR */
#define TCR_TDDR_MASK 0x0F

/* Wait-state registers (manual 9.4.2/9.4.3). */
#define CWSR_BIG_BIT 4 /* CWSR bit 4: large (8K) vs small (128-word) pages */

/* ------------------------------------------------------------------
   RPTB block replay: decoded-block cache.  See
   block_replay() for the design and the exactness argument.  A RptbBlock
   holds one RPTB block's body decoded once: the opcode word, the
   cycle-model charge (cycle_table[op], or 1 when the cycle model is off),
   and the replay-relevant flags per entry, plus a copy of the raw
   words for validation.  At most BLOCK_MAX_WORDS words / BLOCK_MAX_ENT
   entries per block; longer blocks simply do not replay.
   ------------------------------------------------------------------ */
#define BLOCK_CACHE_N 64
#define BLOCK_MAX_WORDS 128
#define BLOCK_MAX_ENT 128
#define BLOCK_CONT 0    /* block_replay: resume the main loop (block done / left) */
#define BLOCK_F_STORE 1 /* entry may call data_write with an arbitrary address */
#define BLOCK_F_RPTC 2  /* entry is an rptc-loop op: may leave rptc == -1 */
#define BLOCK_F_RPT 4   /* entry is RPT/RPTZ/RPT-dma: sets rptc */
#define BLOCK_F_XC 8    /* entry is XC: may skip 1-2 words */
typedef struct {
    uint16_t pc, opcode, cy;
    uint8_t flags;
} RptbEntry;
typedef struct RptbBlock {
    uint16_t pasr, paer;
    uint16_t n;                      /* entries in e[] */
    uint64_t epoch;                  /* pm_epoch at decode / last validation */
    uint64_t bp_epoch;               /* bp_epoch at decode / last validation */
    uint64_t validated_seq;          /* run_seq at last validation */
    int cycle_model;                 /* cycle_model at decode */
    uint16_t words[BLOCK_MAX_WORDS]; /* raw block words, for validation */
    uint8_t idx_of[BLOCK_MAX_WORDS]; /* word offset -> entry index, 0xFF = none */
    RptbEntry e[BLOCK_MAX_ENT];
} RptbBlock;

/* ------------------------------------------------------------------
   Core state
   ------------------------------------------------------------------ */

struct C5x {
    /* Datapath. */
    uint32_t acc, accb, preg;     /* 32-bit accumulator, ACCB, product reg */
    uint16_t treg0, treg1, treg2; /* temporary registers */
    uint16_t ar[N_AR];            /* auxiliary registers */
    int arp, arb;                 /* current / auxiliary-reg pointer (ST0/ST1) */
    int dp;                       /* data-page pointer, already << 7 */
    int ov, ovm, intm, cnf, tc, sxm, carry, hm, xf, pm;
    int iptr, avis, ovly, ram, mpmc, ndx, trm, braf;
    uint16_t pc, opcode; /* program counter, current opcode */
    uint16_t stack[STACK_N];
    int sp;                                    /* stack pointer (0..7, grows down) */
    int32_t rptc;                              /* repeat counter (RPT/RPTB state) */
    uint16_t rpt_start, rpt_end;               /* single-instruction repeat window */
    uint16_t ifr, imr;                         /* interrupt flag / mask registers */
    uint16_t indx, arcr;                       /* index / AR compare registers */
    uint16_t cbsr1, cber1, cbsr2, cber2, cbcr; /* circular-buffer regs */
    uint16_t bmar, dbmr, pasr, paer;           /* block-move / repeat-block regs */

    /* Diagnostics: MMR / external / 0xFFxx access counts and last values. */
    uint32_t mmr_n[2][N_MMR];  /* [read/write][addr] access counts */
    uint16_t mmr_pc[2][N_MMR]; /* PC of last access */
    uint16_t mmr_val[N_MMR];   /* first-written value (see mmr_write) */
    uint32_t ext_n[2][64];     /* external accesses per 1K block */
    uint32_t ff_n[2][256];     /* 0xFFxx accesses per low byte */
    uint16_t rsv_a, rsv_pc;    /* last reserved-range (0x500..0x7FF) access */
    int32_t brcr;              /* block-repeat counter (RPTB) */
    uint16_t io_rep;           /* IN/OUT port increment under RPT */
    int xc_left, xc_new;       /* XC uninterruptible-window countdown */

    /* On-chip peripherals. */
    uint16_t greg, drr, dxr, spc, tim, prd, tcr_tddr, pdwsr, iowsr, cwsr;
    int psc, tss; /* timer prescaler counter / stop bit */

    /* Raw storage for MMR addresses with no dedicated field. */
    uint16_t mmr_raw[N_MMR];

    /* Interrupt shadow context (saved on entry, restored by RETI/RETE). */
    struct {
        uint32_t acc, accb, preg;
        uint16_t treg0, treg1, treg2, arcr, indx;
        int arp, arb, dp, ov, ovm, intm, cnf, tc, sxm, carry, hm, xf, pm;
        int iptr, avis, ovly, ram, mpmc, ndx, trm, braf;
    } shadow;

    uint64_t cycles;       /* total machine cycles executed */
    int xsrempty, rsrfull; /* SPC status bits 12 / 13 (Table 9-13) */
    int idle, bio, stop, status, xrdy, rrdy, xint_mode, xint_first;
    int cycle_model;                 /* 1 = charge manual cycle counts */
    int words;                       /* words fetched by the current instruction */
    int in_repeat;                   /* 1 = inside a repeated instruction */
    int legacy;                      /* stored by c5x_set_legacy; nothing reads it */
    uint64_t idle_cycles, timer_exp; /* IDLE cycles / timer expiries (diagnostics) */
    /* Diagnostics gate (see c5x_set_diag): when 0, execute_one/mmr/dm skip the
       per-instruction and per-access diagnostic counters (hits, pcring,
       pc_hits, trace, mmr_n/mmr_pc/mmr_val, ext_n, ff_n, rsv).  The C
       driver never reads those counters, so it runs with diag off; the
       default is ON so the Python ctypes .so ABI keeps its old
       behaviour unless the caller opts out.  Counters that the glue
       DOES read (cycles, timer_exp, idle_cycles, dxr_ring, iolog) are
       not gated. */
    int diag;

    /* Memories (flat 64K x 16-bit views owned by the core). */
    uint16_t *pmem, *dmem, *iomem;
    uint32_t *hits; /* per-PC execution counts */

    /* Host I/O callbacks (NULL = use iomem[] as the port array). */
    io_rd_fn io_rd;
    io_wr_fn io_wr;
    void *io_ctx;

    /* I/O event log. */
    int iolog_on;
    IoEv *iolog;
    uint32_t iolog_n;

    /* Breakpoints (one byte per PC). */
    uint8_t *breakpoints;

    uint16_t cur_pc;             /* PC of the instruction now executing */
    uint16_t pc_ring[PC_RING_N]; /* ring of recently executed PCs */
    uint32_t pc_ring_pos;
    int in_delay; /* 1 = executing a delay-slot word */

    /* AR0 / NDX mirroring (audit #10). */
    int ar0_dirty, interrupt_inhibit;
    int cmpr_ar0; /* experiment: CMPR compares AR0, not ARCR */

    /* RPTB block replay.  pm_epoch is bumped on any
       program-word or fetch-mapping change (program_write, glue overlay loads
       via c5x_pm_invalidate, LST #1 / RCNF / SCNF, PMST writes, c5x_set
       ST1/PMST); bp_epoch is bumped by c5x_set_bp; run_seq counts
       c5x_run entries (the per-call validation in block_lookup covers
       the one frequent PM writer that does NOT bump the epoch, data_write
       to external (unified) memory).  replay_active is 1 while
       block_replay is executing entries; replay_dirty is set when a
       write during the replay threatens the block's words or the
       block/mapping state (mmr_write PMST/RPTC/BRCR/PASR/PAER cases,
       program_write). */
    uint64_t pm_epoch, bp_epoch, run_seq;
    int replay_active, replay_dirty;
    uint16_t replay_lo, replay_hi; /* active block range, for block_store_guard */
    RptbBlock *block_cache[BLOCK_CACHE_N];

    /* PC-hit / watch / trace diagnostics. */
    uint32_t pc_hits[65536];
    uint32_t dmw_n[65536]; /* data-memory writes per address (diag only) */
    uint32_t watch_hits[65536];
    int32_t watch_a;
    int32_t trace_pc;
    uint32_t trace_n;
    struct {
        uint32_t acc;
        uint16_t ret, ret2;
        uint64_t cyc;
    } trace_buf[TRACE_N];

    /* Every DXR write is appended here (ring of 65536). */
    uint16_t *dxr_ring;
    uint32_t dxr_head;

    /* Interrupt-vector indirection: if ivec_ind[n] != 0, interrupt n jumps
       to dmem[ivec_ind[n]] instead of the vector-table entry. */
    uint16_t ivec_ind[16];
};

/* A program-word or fetch-mapping change: invalidate cached block
   decodes (bump pm_epoch) and, if a replay is in flight, flag it so
   the replay breaks out after the current instruction.  Only called
   from rare paths (program_write, PMST/RPTC/BRCR/PASR/PAER MMR writes,
   LST #1, RCNF/SCNF, c5x_set ST1/PMST).  The frequent data_write path
   does not call this: its external (unified-memory) writes bump
   pm_epoch directly in data_write, and its in-replay writes are caught
   by block_store_guard. */
static inline void block_state_changed(C5x *dsp) {
    dsp->pm_epoch++;
    if (dsp->replay_active) {
        dsp->replay_dirty = 1;
    }
}

/* Forward declarations for helpers defined in the ALU/addressing section. */
static inline void push(C5x *dsp, uint16_t v);
static inline uint16_t pop(C5x *dsp);

/* ------------------------------------------------------------------
   Cycle table (mutable copy; see cycle_table_setup)
   ------------------------------------------------------------------ */

/* Mutable copy of the manual cycle table.  CYC_EXP (bit mask) lowers
   classes for experiments: 1 = RPT forms cost 1,
   2 = one-shot BLDD/BLPD/TBLR/TBLW cost 2 (0xA5xx-0xA9xx). */
static uint8_t cycle_table[65536];
static int cycle_table_ready;

static void cycle_table_setup(void) {
    if (cycle_table_ready) {
        return;
    }
    cycle_table_ready = 1;
    memcpy(cycle_table, cyc_tab, sizeof cycle_table);
    const char *e = getenv("CYC_EXP");
    int m = e ? atoi(e) : 0;
    if (m & 1) {
        for (int w = OPCODE_WORD(C5X_OP_RPT_DMA, 0x00); w <= OPCODE_WORD(C5X_OP_RPT_DMA, 0xFF); w++) {
            cycle_table[w] = 1;
        }
        for (int w = OPCODE_WORD(C5X_OP_RPT_K8, 0x00); w <= OPCODE_WORD(C5X_OP_RPT_K8, 0xFF); w++) {
            cycle_table[w] = 1;
        }
        cycle_table[OPCODE_WORD(C5X_OP_GROUP_BE, C5X_BE_RPT_LK)] = 1;
    }
    if (m & 2) {
        for (int w = OPCODE_WORD(C5X_OP_BLPD_PMA, 0x00); w <= OPCODE_WORD(C5X_OP_BLDD_DMA_LK, 0xFF); w++) {
            if (cycle_table[w] == 3) {
                cycle_table[w] = 2;
            }
        }
    }
}

/* ------------------------------------------------------------------
   Construction and simple accessors
   ------------------------------------------------------------------ */

C5x *c5x_new(void) {
    cycle_table_setup();
    C5x *dsp = calloc(1, sizeof *dsp);
    dsp->pmem = calloc(65536, 2);
    dsp->dmem = calloc(65536, 2);
    dsp->iomem = calloc(65536, 2);
    dsp->hits = calloc(65536, 4);
    dsp->breakpoints = calloc(65536, 1);
    dsp->iolog = calloc(IOLOG_N, sizeof(IoEv));
    dsp->dxr_ring = calloc(DXR_RING_N, 2);
    dsp->rptc = 0;
    dsp->trace_pc = -1;
    dsp->watch_a = -1;
    dsp->diag = 1; /* default ON: preserves the .so / ctypes behaviour */
    return dsp;
}

uint16_t *c5x_pmem(C5x *dsp) {
    return dsp->pmem;
}
uint16_t *c5x_dmem(C5x *dsp) {
    return dsp->dmem;
}
uint16_t *c5x_iomem(C5x *dsp) {
    return dsp->iomem;
}
uint32_t *c5x_hits(C5x *dsp) {
    return dsp->hits;
}
IoEv *c5x_iolog(C5x *dsp) {
    return dsp->iolog;
}
uint32_t c5x_iolog_count(C5x *dsp) {
    return dsp->iolog_n;
}
void c5x_iolog_clear(C5x *dsp) {
    dsp->iolog_n = 0;
}
void c5x_iolog_enable(C5x *dsp, int on) {
    dsp->iolog_on = on;
}
void c5x_set_io(C5x *dsp, io_rd_fn rd, io_wr_fn wr, void *ctx) {
    dsp->io_rd = rd;
    dsp->io_wr = wr;
    dsp->io_ctx = ctx;
}
void c5x_set_bp(C5x *dsp, uint16_t a, int on) {
    dsp->breakpoints[a] = on;
    dsp->bp_epoch++;
}
void c5x_stop(C5x *dsp) {
    dsp->stop = 1;
}
void c5x_set_bio(C5x *dsp, int v) {
    dsp->bio = v;
}
/* Diagnostic: hardware stack entry, depth 0 = most recent return address. */
uint16_t c5x_stack_at(C5x *dsp, int depth) {
    return dsp->stack[(dsp->sp + depth) & 7];
}
/* Invalidate cached RPTB block decodes.  Called by
   the glue after writing program memory from outside the core
   (overlay loads through the raw c5x_pmem() pointer). */
void c5x_pm_invalidate(C5x *dsp) {
    dsp->pm_epoch++;
}
uint16_t *c5x_pcring(C5x *dsp) {
    return dsp->pc_ring;
}
uint32_t c5x_pcring_idx(C5x *dsp) {
    return dsp->pc_ring_pos;
}

/* Reset: restores the power-on register state for a fresh run at pc.
   Deliberately does NOT touch: the memories, hits/pc_hits/watch/trace
   diagnostics, MMR counters, breakpoints, the I/O log, the DXR ring,
   ivec_ind, cmpr_ar0, xint_mode, cycle_model, legacy, idle_cycles,
   timer_exp, or the unlisted registers below (indx, arcr, cbsr/cber,
   bmar, dbmr, pasr, paer, rpt_start/rpt_end, io_rep).
   That selective reset is deliberate. */
void c5x_reset(C5x *dsp, uint16_t pc) {
    dsp->acc = dsp->accb = dsp->preg = 0;
    dsp->treg0 = dsp->treg1 = dsp->treg2 = 0;
    memset(dsp->ar, 0, sizeof dsp->ar);
    dsp->intm = 1;
    dsp->ov = 0;
    dsp->ovm = 0;
    dsp->arp = 0;
    dsp->arb = 0;
    dsp->dp = 0;
    dsp->carry = 1;
    dsp->cnf = 0;
    dsp->hm = 1;
    dsp->pm = 0;
    dsp->sxm = 1;
    dsp->xf = 1;
    dsp->tc = 0;
    dsp->iptr = 0;
    dsp->avis = 0;
    dsp->ovly = 0;
    dsp->ram = 0;
    dsp->mpmc = 0;
    dsp->ndx = 0;
    dsp->trm = 0;
    dsp->braf = 0;
    dsp->ifr = 0;
    dsp->imr = 0;
    dsp->cbcr = 0;
    dsp->rptc = 0;
    dsp->idle = 0;
    dsp->sp = 0;
    dsp->ar0_dirty = 0;
    dsp->interrupt_inhibit = 0;
    dsp->xc_left = dsp->xc_new = 0;
    dsp->in_repeat = 0;
    dsp->brcr = 0;
    dsp->greg = 0;
    dsp->pdwsr = dsp->iowsr = 0xFFFF;
    dsp->cwsr = 0x0F;
    /* 07-NEW-6: no stale host-side flags across a reset. */
    dsp->drr = dsp->dxr = dsp->spc = 0;
    dsp->pc = pc;
    dsp->xrdy = 1;
    dsp->rrdy = 0;
    dsp->xsrempty = 0;
    dsp->rsrfull = 0;
    dsp->spc = 0;
    dsp->cycles = 0;
    dsp->tss = 0;
    dsp->psc = 0;
    dsp->tim = 0xFFFF;
    dsp->prd = 0xFFFF;
    dsp->tcr_tddr = 0;
    memset(dsp->stack, 0, sizeof dsp->stack);
}

/* ------------------------------------------------------------------
   Status registers
   ------------------------------------------------------------------ */

/* ST0: ARP(13), OV(12), OVM(11), 1(10, hardwired), INTM(9), DP(8..0).
   dp is stored pre-shifted (<< 7), so dp >> 7 recovers the 9-bit page. */
static uint16_t st0_get(C5x *dsp) {
    return (uint16_t)((dsp->arp << ST0_ARP_SHIFT) | (dsp->ov << ST0_OV_BIT) | (dsp->ovm << ST0_OVM_BIT) |
                      (1 << ST0_INT_BIT) | (dsp->intm << ST0_INTM_BIT) | (dsp->dp >> 7));
}

/* ST1: ARB(13), CNF(12), TC(11), SXM(10), C(9), 1(8), 1(7), HM(6),
   1(5), XF(4), 1(3), 1(2), PM(1..0).  Bits 8, 7, 5, 3, 2 read as 1. */
static uint16_t st1_get(C5x *dsp) {
    return (uint16_t)((dsp->arb << ST1_ARB_SHIFT) | (dsp->cnf << ST1_CNF_BIT) | (dsp->tc << ST1_TC_BIT) |
                      (dsp->sxm << ST1_SXM_BIT) | (dsp->carry << ST1_C_BIT) | (1 << 8) | (1 << 7) |
                      (dsp->hm << ST1_HM_BIT) | (1 << 5) | (dsp->xf << ST1_XF_BIT) | (1 << 3) | (1 << 2) | dsp->pm);
}

/* PMST: IPTR(15..11), AVIS(7), OVLY(5), RAM(4), MPMC(3), NDX(2), TRM(1), BRAF(0). */
static uint16_t pmst_get(C5x *dsp) {
    return (uint16_t)((dsp->iptr << PMST_IPTR_SHIFT) | (dsp->avis << PMST_AVIS_BIT) | (dsp->ovly << PMST_OVLY_BIT) |
                      (dsp->ram << PMST_RAM_BIT) | (dsp->mpmc << PMST_MPMC_BIT) | (dsp->ndx << PMST_NDX_BIT) |
                      (dsp->trm << PMST_TRM_BIT) | dsp->braf);
}

uint32_t c5x_get(C5x *dsp, int id) {
    if (id >= C5X_REG_AR0 && id < C5X_REG_AR0 + N_AR) {
        return dsp->ar[id - C5X_REG_AR0];
    }
    switch (id) {
    case C5X_REG_PC:
        return dsp->pc;
    case C5X_REG_ACC:
        return dsp->acc;
    case C5X_REG_ACCB:
        return dsp->accb;
    case C5X_REG_PREG:
        return dsp->preg;
    case C5X_REG_T0:
        return dsp->treg0;
    case C5X_REG_T1:
        return dsp->treg1;
    case C5X_REG_T2:
        return dsp->treg2;
    case C5X_REG_ST0:
        return st0_get(dsp);
    case C5X_REG_ST1:
        return st1_get(dsp);
    case C5X_REG_PMST:
        return pmst_get(dsp);
    case C5X_REG_RPTC:
        return (uint32_t)dsp->rptc;
    case C5X_REG_IFR:
        return dsp->ifr;
    case C5X_REG_IMR:
        return dsp->imr;
    case C5X_REG_SP:
        return (uint32_t)dsp->sp;
    case C5X_REG_CYC_LO:
        return (uint32_t)dsp->cycles;
    case C5X_REG_CYC_HI:
        return (uint32_t)(dsp->cycles >> 32);
    case C5X_REG_BMAR:
        return dsp->bmar;
    case C5X_REG_DBMR:
        return dsp->dbmr;
    case C5X_REG_INDX:
        return dsp->indx;
    case C5X_REG_ARCR:
        return dsp->arcr;
    case C5X_REG_DXR:
        return dsp->dxr;
    case C5X_REG_DRR:
        return dsp->drr;
    case C5X_REG_TIM:
        return dsp->tim;
    case C5X_REG_PRD:
        return dsp->prd;
    case C5X_REG_IDLE:
        return (uint32_t)dsp->idle;
    }
    return 0;
}

void c5x_set(C5x *dsp, int id, uint32_t value) {
    if (id >= C5X_REG_AR0 && id < C5X_REG_AR0 + N_AR) {
        dsp->ar[id - C5X_REG_AR0] = (uint16_t)value;
        if (id == C5X_REG_AR0) {
            dsp->ar0_dirty = 1;
        }
        return;
    }
    switch (id) {
    case C5X_REG_PC:
        dsp->pc = (uint16_t)value;
        break;
    case C5X_REG_ACC:
        dsp->acc = value;
        break;
    case C5X_REG_ACCB:
        dsp->accb = value;
        break;
    case C5X_REG_DRR:
        dsp->drr = (uint16_t)value;
        break;
    case C5X_REG_DXR:
        dsp->dxr = (uint16_t)value;
        break;
    case C5X_REG_IMR:
        dsp->imr = (uint16_t)value;
        break;
    case C5X_REG_ST0:
        dsp->arp = (int)(value >> ST0_ARP_SHIFT);
        dsp->ov = (int)((value >> ST0_OV_BIT) & 1);
        dsp->ovm = (int)((value >> ST0_OVM_BIT) & 1);
        dsp->intm = (int)((value >> ST0_INTM_BIT) & 1);
        dsp->dp = (int)((value & 0x1ff) << 7);
        break;
    case C5X_REG_ST1:
        dsp->arb = (int)(value >> ST1_ARB_SHIFT);
        block_state_changed(dsp); /* CNF is part of the fetch mapping */
        dsp->cnf = (int)((value >> ST1_CNF_BIT) & 1);
        dsp->tc = (int)((value >> ST1_TC_BIT) & 1);
        dsp->sxm = (int)((value >> ST1_SXM_BIT) & 1);
        dsp->carry = (int)((value >> ST1_C_BIT) & 1);
        dsp->hm = (int)((value >> ST1_HM_BIT) & 1);
        dsp->xf = (int)((value >> ST1_XF_BIT) & 1);
        dsp->pm = (int)(value & 3);
        break;
    case C5X_REG_PMST:
        block_state_changed(dsp); /* RAM/BRAF are fetch-mapping / block state */
        dsp->iptr = (int)(value >> PMST_IPTR_SHIFT);
        dsp->avis = (int)((value >> PMST_AVIS_BIT) & 1);
        dsp->ovly = (int)((value >> PMST_OVLY_BIT) & 1);
        dsp->ram = (int)((value >> PMST_RAM_BIT) & 1);
        dsp->mpmc = (int)((value >> PMST_MPMC_BIT) & 1);
        dsp->ndx = (int)((value >> PMST_NDX_BIT) & 1);
        dsp->trm = (int)((value >> PMST_TRM_BIT) & 1);
        dsp->braf = (int)(value & 1);
        break;
    case C5X_REG_PUSH: /* push value on the hardware stack */
        push(dsp, (uint16_t)value);
        break;
    case C5X_REG_SETIDLE:
        dsp->idle = (int)value;
        break;
    }
}

void c5x_irq(C5x *dsp, int bit) {
    dsp->ifr |= (uint16_t)(1 << bit);
}

/* ------------------------------------------------------------------
   Host I/O (ports)
   ------------------------------------------------------------------ */

/* Wait states of an I/O access, from IOWSR/CWSR (manual 9.4.2/9.4.3).
   CWSR bit 4 selects large (8K, port>>13) versus small
   (128-word, (port>>1)&7) page indexing; the CWSR alt bit doubles the
   programmed count for 2->3 and 3->7 wait states. */
static int io_wait_states(C5x *dsp, uint16_t port) {
    int big = (dsp->cwsr >> CWSR_BIG_BIT) & 1;
    int idx = big ? (port >> 13) : ((port >> 1) & 7);
    int f = (dsp->iowsr >> (2 * idx)) & 3;
    int alt = (dsp->cwsr >> (idx < 4 ? 2 : 3)) & 1;
    return alt ? (f == 3 ? 7 : f == 2 ? 3 : f) : f;
}

static uint16_t io_read(C5x *dsp, uint16_t port) {
    uint16_t v;
    /* A read takes one extra cycle per wait state. */
    if (dsp->cycle_model) {
        dsp->cycles += (uint64_t)io_wait_states(dsp, port);
    }
    if (dsp->io_rd) {
        v = dsp->io_rd(dsp->io_ctx, port);
    } else {
        v = dsp->iomem[port];
    }
    if (dsp->iolog_on && dsp->iolog_n < IOLOG_N) {
        dsp->iolog[dsp->iolog_n++] = (IoEv){dsp->cycles, dsp->cur_pc, port, v, 0};
    }
    return v;
}

static void io_write(C5x *dsp, uint16_t port, uint16_t value) {
    /* Software wait states do not lengthen writes until two or more are
       programmed (manual Table 9-7). */
    if (dsp->cycle_model) {
        int w = io_wait_states(dsp, port);
        if (w > 1) {
            dsp->cycles += (uint64_t)(w - 1);
        }
    }
    if (dsp->iolog_on && dsp->iolog_n < IOLOG_N) {
        dsp->iolog[dsp->iolog_n++] = (IoEv){dsp->cycles, dsp->cur_pc, port, value, 1};
    }
    if (dsp->io_wr) {
        dsp->io_wr(dsp->io_ctx, port, value);
    } else {
        dsp->iomem[port] = value;
    }
}

/* ------------------------------------------------------------------
   Memory-mapped registers (data space 0x00..0x5F)
   ------------------------------------------------------------------ */

static inline __attribute__((always_inline)) uint16_t mmr_read(C5x *dsp, uint16_t addr) {
    if (addr < N_MMR && dsp->diag) {
        dsp->mmr_n[0][addr]++;
        dsp->mmr_pc[0][addr] = dsp->cur_pc;
    }
    if (addr >= MMR_IO_WINDOW) {
        return io_read(dsp, addr);
    }
    if (addr >= MMR_AR0 && addr < MMR_AR_END) {
        return dsp->ar[addr - MMR_AR0];
    }
    switch (addr) {
    case MMR_IMR:
        return dsp->imr;
    case MMR_GREG:
        return dsp->greg;
    case MMR_IFR:
        return dsp->ifr;
    case MMR_PMST:
        return pmst_get(dsp);
    case MMR_RPTC:
        return (uint16_t)dsp->rptc;
    case MMR_BRCR:
        return (uint16_t)dsp->brcr;
    case MMR_PASR:
        return dsp->pasr;
    case MMR_PAER:
        return dsp->paer;
    case MMR_TREG0:
        return dsp->treg0;
    case MMR_TREG1:
        return (uint16_t)(dsp->treg1 & TREG1_MASK);
    case MMR_TREG2:
        return (uint16_t)(dsp->treg2 & TREG2_MASK);
    case MMR_DBMR:
        return dsp->dbmr;
    case MMR_INDX:
        return dsp->indx;
    case MMR_ARCR:
        return dsp->arcr;
    case MMR_CBSR1:
        return dsp->cbsr1;
    case MMR_CBER1:
        return dsp->cber1;
    case MMR_CBSR2:
        return dsp->cbsr2;
    case MMR_CBER2:
        return dsp->cber2;
    case MMR_CBCR:
        return dsp->cbcr;
    case MMR_BMAR:
        return dsp->bmar;
    case MMR_DRR:
        /* Reading DRR clears RRDY / RSRFULL. */
        dsp->rrdy = 0;
        dsp->rsrfull = 0;
        return dsp->drr;
    case MMR_DXR:
        return dsp->dxr;
    case MMR_SPC:
        /* SPC read: stored bits masked to 0xC0FE, ORed with live status.
           Bit 0 reads 0; IN0/IN1 (CLKR/CLKX pins) read 0. */
        return (uint16_t)((dsp->spc & SPC_WRITABLE_MASK) | (dsp->rsrfull << SPC_RSRFULL_BIT) |
                          (dsp->xsrempty << SPC_XSREMPTY_BIT) | (dsp->xrdy << SPC_XRDY_BIT) |
                          (dsp->rrdy << SPC_RRDY_BIT));
    case MMR_TIM:
        return dsp->tim;
    case MMR_PRD:
        return dsp->prd;
    case MMR_TCR:
        return (uint16_t)(((dsp->psc & 0xF) << TCR_PSC_SHIFT) | (dsp->tss << TCR_TSS_BIT) |
                          (dsp->tcr_tddr & TCR_TDDR_MASK));
    case MMR_PDWSR:
        return dsp->pdwsr;
    case MMR_IOWSR:
        return dsp->iowsr;
    case MMR_CWSR:
        return dsp->cwsr;
    }
    return dsp->mmr_raw[addr];
}

static inline __attribute__((always_inline)) void mmr_write(C5x *dsp, uint16_t addr, uint16_t data) {
    if (addr < N_MMR && dsp->diag) {
        dsp->mmr_n[1][addr]++;
        dsp->mmr_pc[1][addr] = dsp->cur_pc;
        /* mmr_val keeps the first value written, except for the low MMRs,
           the circular-buffer / wait-state block 0x1A..0x2A, and 0x32,
           which always update. */
        if (dsp->mmr_n[1][addr] <= 1 || addr < MMR_AR0 || (addr >= MMR_CIRCULAR_FIRST && addr <= MMR_WAIT_STATE_LAST) ||
            addr == MMR_UNDOCUMENTED_32) {
            dsp->mmr_val[addr] = data;
        }
    }
    if (addr >= MMR_IO_WINDOW) {
        io_write(dsp, addr, data);
        return;
    }
    if (addr >= MMR_AR0 && addr < MMR_AR_END) {
        dsp->ar[addr - MMR_AR0] = data;
        if (addr == MMR_AR0) {
            dsp->ar0_dirty = 1;
        }
        return;
    }
    switch (addr) {
    case MMR_IMR:
        dsp->imr = data;
        return;
    case MMR_GREG:
        dsp->greg = data;
        return;
    case MMR_IFR:
        /* Writing IFR clears the bits set in data (write-1-to-clear). */
        dsp->ifr &= (uint16_t)~data;
        return;
    case MMR_PMST:
        /* PMST: RAM changes the fetch mapping, BRAF is block state. */
        block_state_changed(dsp);
        dsp->iptr = data >> PMST_IPTR_SHIFT;
        dsp->avis = (data >> PMST_AVIS_BIT) & 1;
        dsp->ovly = (data >> PMST_OVLY_BIT) & 1;
        dsp->ram = (data >> PMST_RAM_BIT) & 1;
        dsp->mpmc = (data >> PMST_MPMC_BIT) & 1;
        dsp->ndx = (data >> PMST_NDX_BIT) & 1;
        dsp->trm = (data >> PMST_TRM_BIT) & 1;
        dsp->braf = data & 1;
        return;
    case MMR_RPTC:
        block_state_changed(dsp);
        dsp->rptc = data;
        return;
    case MMR_BRCR:
        block_state_changed(dsp);
        dsp->brcr = data;
        return;
    case MMR_PASR:
        block_state_changed(dsp);
        dsp->pasr = data;
        return;
    case MMR_PAER:
        block_state_changed(dsp);
        dsp->paer = data;
        return;
    case MMR_TREG0:
        dsp->treg0 = data;
        return;
    case MMR_TREG1:
        dsp->treg1 = (uint16_t)(data & TREG1_MASK);
        return;
    case MMR_TREG2:
        dsp->treg2 = (uint16_t)(data & TREG2_MASK);
        return;
    case MMR_DBMR:
        dsp->dbmr = data;
        return;
    case MMR_INDX:
        dsp->indx = data;
        return;
    case MMR_ARCR:
        dsp->arcr = data;
        return;
    case MMR_CBSR1:
        dsp->cbsr1 = data;
        return;
    case MMR_CBER1:
        dsp->cber1 = data;
        return;
    case MMR_CBSR2:
        dsp->cbsr2 = data;
        return;
    case MMR_CBER2:
        dsp->cber2 = data;
        return;
    case MMR_CBCR:
        dsp->cbcr = (uint16_t)(data & CBCR_MASK);
        return;
    case MMR_BMAR:
        dsp->bmar = data;
        return;
    case MMR_DRR:
        dsp->drr = data;
        return;
    case MMR_DXR:
        /* DXR write: falls through to the tail below (break, not
           return), so it also lands in mmr_raw[] and in the I/O log
           as pseudo-port 0x8000|addr. */
        dsp->dxr = data;
        dsp->xrdy = 0;
        dsp->xsrempty = 1;
        dsp->dxr_ring[dsp->dxr_head++ & 0xFFFF] = data;
        break;
    case MMR_SPC:
        /* SPC: FREE/SOFT, RRST, XRST, TXM, MCM, FSM, FO, DLB are
           writable; bits 13..8 are status.  Also falls through to the
           tail below (break, not return). */
        dsp->spc = (uint16_t)(data & SPC_WRITABLE_MASK);
        /* RRST=0 clears RRDY / RSRFULL. */
        if (!(data & SPC_RRST_BIT)) {
            dsp->rrdy = 0;
            dsp->rsrfull = 0;
        }
        /* XRST=0: XSREMPTY=0, XRDY=1, and XINT fires if XRDY was 0. */
        if (!(data & SPC_XRST_BIT)) {
            if (!dsp->xrdy) {
                dsp->ifr |= (uint16_t)(1 << C5X_XINT);
            }
            dsp->xsrempty = 0;
            dsp->xrdy = 1;
        }
        break;
    case MMR_TIM:
        dsp->tim = data;
        return;
    case MMR_PRD:
        dsp->prd = data;
        return;
    case MMR_TCR:
        dsp->tcr_tddr = (uint16_t)(data & TCR_TDDR_MASK);
        dsp->tss = (data >> TCR_TSS_BIT) & 1;
        if (data & TCR_TRB_BIT) {
            dsp->tim = dsp->prd;
            dsp->psc = dsp->tcr_tddr;
        } else {
            dsp->psc = (data >> TCR_PSC_SHIFT) & 0xF;
        }
        return;
    case MMR_PDWSR:
        dsp->pdwsr = data;
        return;
    case MMR_IOWSR:
        dsp->iowsr = data;
        return;
    case MMR_CWSR:
        dsp->cwsr = (uint16_t)(data & CWSR_MASK);
        return;
    }
    dsp->mmr_raw[addr] = data;
    /* DXR / SPC / unknown-MMR writes are visible through the I/O log as
       pseudo-port 0x8000|addr.  Only the two break cases
       above and the default path reach this tail; every return case
       above skips it. */
    if (dsp->iolog_on && dsp->iolog_n < IOLOG_N) {
        dsp->iolog[dsp->iolog_n++] = (IoEv){dsp->cycles, dsp->cur_pc, (uint16_t)(0x8000 | addr), data, 1};
    }
}

/* ------------------------------------------------------------------
   Data / program memory routing
   ------------------------------------------------------------------ */

/* Internal data RAM: B2 0x60-7F, B0/B1 0x100-4FF, SARAM 0x800-BFF.
   Everything else is external SRAM, which on this board is shared
   between program and data space (unified with pmem).
   B0 leaves data space when CNF=1; SARAM is in data space only when
   OVLY=1 (SPRU056D 8.2, courier-emu data_region). */
static inline int dm_internal(C5x *dsp, uint16_t a) {
    return a < DM_B2_END || (a >= DM_B0_START && a < DM_B0_END && !(dsp->cnf && a < DM_B0_CNF_END)) ||
           (dsp->ovly && a >= DM_SARAM_START && a < DM_SARAM_END);
}

/* External memory-mapped host window. */
static inline int dm_hostwin(uint16_t a) {
    return a >= DM_HOSTWIN_START && a <= DM_HOSTWIN_END;
}

/* Manual 6.2: a peripheral MMR access (20h-4Fh) goes over the TI bus
   and adds one cycle. */
static inline void mmr_bus(C5x *dsp, uint16_t a) {
    if (dsp->cycle_model && a >= DM_PERIPH_START && a < DM_PERIPH_END) {
        dsp->cycles++;
    }
}

/* Diagnostic build only (-DC5X_MEMTRACE): print data-memory reads and writes
   (address, PC, value) while c5x_memtrace is set and the PC is in [lo, hi]. */
#ifdef C5X_MEMTRACE
int c5x_memtrace, c5x_memtrace_lo, c5x_memtrace_hi = 0xFFFF;
#define MEMTRACE_ACTIVE(a)                                                                                             \
    (__builtin_expect(c5x_memtrace, 0) && (a) >= 0x100 && dsp->cur_pc >= c5x_memtrace_lo &&                            \
     dsp->cur_pc <= c5x_memtrace_hi)
#define MEMTRACE_RD(a, v)                                                                                              \
    do {                                                                                                               \
        if (MEMTRACE_ACTIVE(a))                                                                                        \
            fprintf(stderr, "DMR %04X pc=%04X %04X\n", (a), dsp->cur_pc, (v));                                         \
    } while (0)
#define MEMTRACE_WR(a, d)                                                                                              \
    do {                                                                                                               \
        if (MEMTRACE_ACTIVE(a))                                                                                        \
            fprintf(stderr, "DMW %04X pc=%04X %04X\n", (a), dsp->cur_pc, (d));                                         \
    } while (0)
#else
#define MEMTRACE_RD(a, v) ((void)0)
#define MEMTRACE_WR(a, d) ((void)0)
#endif
static inline __attribute__((always_inline)) uint16_t data_read(C5x *dsp, uint16_t addr) {
    if (dsp->diag && addr >= DM_MMR_END && !dm_internal(dsp, addr)) {
        dsp->ext_n[0][addr >> 10]++;
        if (addr >= DM_FF_START) {
            dsp->ff_n[0][addr & 255]++;
        }
        if (addr >= DM_RSV_START && addr < DM_RSV_END) {
            dsp->rsv_a = addr;
            dsp->rsv_pc = dsp->cur_pc;
        }
    }
    uint16_t v;
    if (addr < DM_MMR_END) {
        v = mmr_read(dsp, addr);
    } else if (dm_internal(dsp, addr)) {
        v = dsp->dmem[addr];
    } else if (dm_hostwin(addr)) {
        v = io_read(dsp, addr);
    } else {
        v = dsp->pmem[addr];
    }
    MEMTRACE_RD(addr, v);
    return v;
}

/* A data write during a replay that lands on a program word of the
   block being replayed would make the cached decode stale mid-replay.
   External unified memory (pmem[a] is program word a) and SARAM dmem
   when it is also program space (RAM=1 and OVLY=1: dmem 0x800.. maps
   to program 0x2000..) are the two routes; B0 has none (under CNF=1
   data 0x100.. leaves data space, so a DM write there lands in
   pmem[], a different cell from program 0xFE00's dmem[]).  The
   replay checks replay_dirty after every entry and breaks out, so
   this guard only has to set the flag.  It is a single predictable
   branch when no replay is in flight (replay_active == 0). */
static inline void block_store_guard(C5x *dsp, uint16_t a) {
    if (a >= DM_MMR_END && !dm_internal(dsp, a) && !dm_hostwin(a)) {
        /* External: pmem[a] is program word a. */
        if (a >= dsp->replay_lo && a <= dsp->replay_hi) {
            dsp->replay_dirty = 1;
        }
    } else if (dsp->ram && dsp->ovly && a >= DM_SARAM_START && a < DM_SARAM_END) {
        /* SARAM dmem is program 0x2000.. when RAM=1 and OVLY=1. */
        uint16_t pma = (uint16_t)(a - DM_SARAM_START + PM_SARAM_START);
        if (pma >= dsp->replay_lo && pma <= dsp->replay_hi) {
            dsp->replay_dirty = 1;
        }
    }
}

static inline __attribute__((always_inline)) void data_write(C5x *dsp, uint16_t addr, uint16_t data) {
    mmr_bus(dsp, addr);
    if (dsp->replay_active) {
        block_store_guard(dsp, addr);
    }
    if (dsp->diag) {
        if (addr >= DM_MMR_END && !dm_internal(dsp, addr)) {
            dsp->ext_n[1][addr >> 10]++;
        }
        dsp->dmw_n[addr]++;
        if (addr >= DM_FF_START) {
            dsp->ff_n[1][addr & 255]++;
        }
    }
    MEMTRACE_WR(addr, data);
    if ((int32_t)addr == dsp->watch_a) {
        dsp->watch_hits[dsp->cur_pc]++;
    }
    if (addr < DM_MMR_END) {
        mmr_write(dsp, addr, data);
    } else if (dm_internal(dsp, addr)) {
        dsp->dmem[addr] = data;
    } else if (dm_hostwin(addr)) {
        io_write(dsp, addr, data);
    } else {
        dsp->pmem[addr] = data;
        /* External DM is unified with PM: this may have written addr
           program word, so cached block decodes must re-validate at
           the next lookup (cheap: one increment; re-validation is addr
           word compare, and lookups are infrequent).  The in-replay
           case is covered by block_store_guard above, which also sets
           replay_dirty so the replay breaks out at once. */
        dsp->pm_epoch++;
    }
}

/* Data move only within on-chip RAM (DMOV/LTD/MACD/MADD): both the
   source and the destination (a+1) must be on-chip RAM (audit 07-NEW-4). */
static inline void data_move_write(C5x *dsp, uint16_t addr, uint16_t data) {
    if (dm_internal(dsp, addr) && addr >= DM_MMR_END && dm_internal(dsp, (uint16_t)(addr + 1))) {
        data_write(dsp, (uint16_t)(addr + 1), data);
    }
}

/* Program-space pointer with the CNF/RAM overlays applied. */
static inline uint16_t *program_ptr(C5x *dsp, uint16_t addr) {
    if (dsp->cnf && addr >= PM_B0_START) {
        return &dsp->dmem[addr - PM_B0_START + 0x100];
    }
    if (dsp->ram && addr >= PM_SARAM_START && addr < PM_SARAM_END) {
        return &dsp->dmem[addr - PM_SARAM_START + 0x800];
    }
    return &dsp->pmem[addr];
}

static inline uint16_t program_read(C5x *dsp, uint16_t addr) {
    return *program_ptr(dsp, addr);
}
static inline void program_write(C5x *dsp, uint16_t addr, uint16_t data) {
    *program_ptr(dsp, addr) = data;
    block_state_changed(dsp);
}

/* ------------------------------------------------------------------
   Stack, ALU, and addressing helpers
   ------------------------------------------------------------------ */

static inline void push(C5x *dsp, uint16_t value) {
    dsp->sp = (dsp->sp - 1) & 7;
    dsp->stack[dsp->sp] = value;
}

static inline uint16_t pop(C5x *dsp) {
    uint16_t value = dsp->stack[dsp->sp];
    dsp->sp = (dsp->sp + 1) & 7;
    /* Quirk preserved: the pop also duplicates the new
       second-from-top entry into the vacated slot.  No known instruction
       depends on it, but the copy is part of the observable state. */
    dsp->stack[(dsp->sp + 7) & 7] = dsp->stack[(dsp->sp + 6) & 7];
    return value;
}

/* 32-bit add with carry-in; s16=1 means the 16-bit form, where a carry
   out sets C but a borrow... see below.  Overflow saturates only if
   OVM is set, and always sets OV (manual 6.3 ADD). */
static uint32_t add32(C5x *dsp, uint32_t left, uint32_t right, int carry_in, int is_16bit) {
    uint64_t wide = (uint64_t)left + right + (uint32_t)carry_in;
    uint32_t result = (uint32_t)wide;
    int carry = (int)((wide >> 32) & 1);
    if (is_16bit) {
        if (carry) {
            dsp->carry = 1;
        }
    } else {
        dsp->carry = carry;
    }
    if ((left ^ result) & (right ^ result) & 0x80000000u) {
        if (dsp->ovm) {
            result = ((int32_t)result < 0) ? 0x7fffffffu : 0x80000000u;
        }
        dsp->ov = 1;
    }
    return result;
}

/* 32-bit subtract with borrow-in; s16=1 is the 16-bit form, where a
   borrow out clears C instead of setting it (manual 6.3 SUB). */
static uint32_t sub32(C5x *dsp, uint32_t left, uint32_t right, int borrow_in, int is_16bit) {
    uint64_t wide = (uint64_t)left - right - (uint32_t)borrow_in;
    uint32_t result = (uint32_t)wide;
    int borrow = (int)((wide >> 32) & 1);
    if (is_16bit) {
        if (borrow) {
            dsp->carry = 0;
        }
    } else {
        dsp->carry = !borrow;
    }
    if ((left ^ right) & (left ^ result) & 0x80000000u) {
        if (dsp->ovm) {
            result = ((int32_t)result < 0) ? 0x7fffffffu : 0x80000000u;
        }
        dsp->ov = 1;
    }
    return result;
}

/* PREG scaled by the PM (product shift mode) field: 00 = no shift,
   01 = <<1, 10 = <<4, 11 = >>6 (arithmetic; PREG is signed here). */
static inline int32_t product_scaled(C5x *dsp) {
    int32_t p = (int32_t)dsp->preg;
    switch (dsp->pm & 3) {
    case 0:
        return p;
    case 1:
        return (int32_t)((uint32_t)p << 1);
    case 2:
        return (int32_t)((uint32_t)p << 4);
    default:
        return p >> 6;
    }
}

/* Load TREG0; unless TRM is set, TREG1/TREG2 mirror its low bits
   (TREG1 = d & 0x1F, TREG2 = d & 0xF). */
static inline void set_t0(C5x *dsp, uint16_t value) {
    dsp->treg0 = value;
    if (!dsp->trm) {
        dsp->treg1 = (uint16_t)(value & 0x1F);
        dsp->treg2 = (uint16_t)(value & 0xF);
    }
}

/* Circular-buffer end test for bit-reversed addressing: returns 1 and
   the block start when ARn has reached its block end.  Bank 1 wins
   over bank 2 when both select the same AR. */
static int circular_end(C5x *dsp, int ar, uint16_t value, uint16_t *start) {
    int cenb1 = (dsp->cbcr >> 3) & 1, car1 = dsp->cbcr & 7;
    int cenb2 = (dsp->cbcr >> 7) & 1, car2 = (dsp->cbcr >> 4) & 7;
    if (cenb1 && ar == car1 && value == dsp->cber1) {
        *start = dsp->cbsr1;
        return 1;
    }
    if (!(cenb1 && ar == car1) && cenb2 && ar == car2 && value == dsp->cber2) {
        *start = dsp->cbsr2;
        return 1;
    }
    return 0;
}

static uint16_t bit_reverse16(uint16_t value) {
    uint16_t reversed = 0;
    for (int i = 0; i < 16; i++) {
        if (value & (1 << i)) {
            reversed |= (uint16_t)(1 << (15 - i));
        }
    }
    return reversed;
}

/* Step ARn by step, wrapping to the block start at the block end when
   circular addressing is enabled for that AR. */
static inline __attribute__((always_inline)) void step_aux_reg(C5x *dsp, int ar, int step) {
    if (ar == 0) {
        dsp->ar0_dirty = 1;
    }
    int cenb1 = (dsp->cbcr >> 3) & 1, car1 = dsp->cbcr & 7;
    int cenb2 = (dsp->cbcr >> 7) & 1, car2 = (dsp->cbcr >> 4) & 7;
    if (cenb1 && ar == car1) {
        if (dsp->ar[ar] == dsp->cber1) {
            dsp->ar[ar] = dsp->cbsr1;
        } else {
            dsp->ar[ar] = (uint16_t)(dsp->ar[ar] + step);
        }
    } else if (cenb2 && ar == car2) {
        if (dsp->ar[ar] == dsp->cber2) {
            dsp->ar[ar] = dsp->cbsr2;
        } else {
            dsp->ar[ar] = (uint16_t)(dsp->ar[ar] + step);
        }
    } else {
        dsp->ar[ar] = (uint16_t)(dsp->ar[ar] + step);
    }
}

/* Switch ARP, saving the old ARP in ARB. */
static inline void set_arp(C5x *dsp, int n) {
    dsp->arb = dsp->arp;
    dsp->arp = n;
}

/* Effective address of the current instruction (manual 5.2).
   Direct (bit 7 clear): dp | low 7 bits.  Indirect: AR[ARP] plus the
   modification encoded in bits 6..3 (0 = none, 2 = -1, 4 = +1,
   8 = bit-reversed -INDX, 0xA = -INDX, 0xC = +INDX, 0xE = bit-reversed
   +INDX); bit 0 (m & 1) additionally switches ARP to the low 3 bits.
   An unlisted modification sets RUN_BADOP (the default case). */
static inline __attribute__((always_inline)) uint16_t effective_address(C5x *dsp) {
    uint16_t op = dsp->opcode;
    if (!(op & C5X_DMA_INDIRECT_BIT)) {
        return (uint16_t)(dsp->dp | (op & C5X_DMA_DIRECT_OFFSET_MASK));
    }
    int arp = dsp->arp;
    int next_arp = op & C5X_DMA_NEXT_ARP_MASK;
    int mode = (op >> C5X_DMA_MODE_SHIFT) & C5X_DMA_MODE_MASK;
    uint16_t address = dsp->ar[arp];
    switch (mode & ~C5X_DMA_MODE_LOAD_ARP_BIT) {
    case C5X_AM_NONE:
        break;
    case C5X_AM_DEC:
        step_aux_reg(dsp, arp, -1);
        break;
    case C5X_AM_INC:
        step_aux_reg(dsp, arp, 1);
        break;
    case C5X_AM_BR0_DEC: {
        uint16_t st;
        dsp->ar[arp] = circular_end(dsp, arp, address, &st)
                           ? st
                           : bit_reverse16((uint16_t)(bit_reverse16(address) - bit_reverse16(dsp->indx)));
        if (arp == 0) {
            dsp->ar0_dirty = 1;
        }
        break;
    }
    case C5X_AM_INDX_DEC:
        step_aux_reg(dsp, arp, -(int16_t)dsp->indx);
        break;
    case C5X_AM_INDX_INC:
        step_aux_reg(dsp, arp, (int16_t)dsp->indx);
        break;
    case C5X_AM_BR0_INC: {
        uint16_t st;
        dsp->ar[arp] = circular_end(dsp, arp, address, &st)
                           ? st
                           : bit_reverse16((uint16_t)(bit_reverse16(address) + bit_reverse16(dsp->indx)));
        if (arp == 0) {
            dsp->ar0_dirty = 1;
        }
        break;
    }
    default:
        dsp->status = RUN_BADOP;
        break;
    }
    if (mode & C5X_DMA_MODE_LOAD_ARP_BIT) {
        set_arp(dsp, next_arp);
    }
    return address;
}

/* SST uses page 0 for direct addressing. */
static uint16_t effective_address_page0(C5x *dsp) {
    if (!(dsp->opcode & C5X_DMA_INDIRECT_BIT)) {
        return (uint16_t)(dsp->opcode & C5X_DMA_DIRECT_OFFSET_MASK);
    }
    return effective_address(dsp);
}

/* Branch-condition ZLVC field (manual 4.5): zlvc bits are the expected
   values, mask selects which flags are tested.  The (mask & 0xC) |
   ((zlvc >> 2) & 3) switch encodes the ACC sign/zero tests. */
static int zlvc_condition(C5x *dsp, int zlvc, int mask) {
    if (mask & 2) {
        if ((zlvc & 2) && !dsp->ov) {
            return 0;
        }
        if (!(zlvc & 2) && dsp->ov) {
            return 0;
        }
    }
    if (mask & 1) {
        if ((zlvc & 1) && !dsp->carry) {
            return 0;
        }
        if (!(zlvc & 1) && dsp->carry) {
            return 0;
        }
    }
    int32_t acc_value = (int32_t)dsp->acc;
    switch ((mask & 0xc) | ((zlvc >> 2) & 3)) {
    case 4:
    case 6:
    case 12:
        return acc_value > 0;
    case 5:
    case 7:
    case 13:
        return acc_value < 0;
    case 8:
    case 9:
        return acc_value != 0;
    case 10:
    case 11:
        return acc_value == 0;
    case 14:
        return acc_value >= 0;
    case 15:
        return acc_value <= 0;
    }
    return 1;
}

/* TP field of conditional branches: 0 = BIO low, 1 = TC set, 2 = TC clear. */
static int tp_condition(C5x *dsp, int tp) {
    switch (tp) {
    case 0:
        return dsp->bio == 0;
    case 1:
        return dsp->tc;
    case 2:
        return !dsp->tc;
    }
    return 1;
}

static int branch_condition(C5x *dsp) {
    return zlvc_condition(dsp, (dsp->opcode >> 4) & 0xF, dsp->opcode & 0xF) &&
           tp_condition(dsp, (dsp->opcode >> 8) & 3);
}

static inline uint16_t fetch(C5x *dsp) {
    uint16_t word = program_read(dsp, dsp->pc);
    dsp->pc++;
    dsp->words++;
    return word;
}

/* Forward declaration: the executor, defined in the next section. */
static void execute_one(C5x *dsp);

/* Execute the delay slot of a delayed branch/call/return: the two words
   following the branch (start = PC just past the branch target word).
   The slot words' own cycles are added to the delayed branch's total
   (manual 4.5.5 Ex. 4-3: BCNDD 2 + OPL 2 = 4).
   The NDX mirror applies between the slot words too (manual 5.2.1).
   The opcode is restored afterwards so the
   cycle model charges the branch, not the slot word. */
static void delay_slot(C5x *dsp, uint16_t start) {
    uint64_t cy0 = dsp->cycles;
    uint16_t op0 = dsp->opcode;
    dsp->in_delay = 1;
    do {
        execute_one(dsp);
        if (dsp->cycle_model) {
            dsp->cycles += cycle_table[dsp->opcode] - 1;
        }
        if (dsp->ar0_dirty) {
            if (!dsp->ndx) {
                dsp->indx = dsp->arcr = dsp->ar[0];
            }
            dsp->ar0_dirty = 0;
        }
    } while ((uint16_t)(dsp->pc - start) < 2);
    dsp->in_delay = 0;
    dsp->opcode = op0;
    (void)cy0; /* cy0 is kept only as a debugging anchor. */
}

/* Save / restore the interrupt shadow context.  NOTE (audit #9):
   restore_shadow_context deliberately does NOT restore INTM and XF,
   even though save_shadow_context saves them. */
static void save_shadow_context(C5x *dsp) {
    dsp->shadow.acc = dsp->acc;
    dsp->shadow.accb = dsp->accb;
    dsp->shadow.preg = dsp->preg;
    dsp->shadow.treg0 = dsp->treg0;
    dsp->shadow.treg1 = dsp->treg1;
    dsp->shadow.treg2 = dsp->treg2;
    dsp->shadow.arcr = dsp->arcr;
    dsp->shadow.indx = dsp->indx;
    dsp->shadow.arp = dsp->arp;
    dsp->shadow.arb = dsp->arb;
    dsp->shadow.dp = dsp->dp;
    dsp->shadow.ov = dsp->ov;
    dsp->shadow.ovm = dsp->ovm;
    dsp->shadow.intm = dsp->intm;
    dsp->shadow.cnf = dsp->cnf;
    dsp->shadow.tc = dsp->tc;
    dsp->shadow.sxm = dsp->sxm;
    dsp->shadow.carry = dsp->carry;
    dsp->shadow.hm = dsp->hm;
    dsp->shadow.xf = dsp->xf;
    dsp->shadow.pm = dsp->pm;
    dsp->shadow.iptr = dsp->iptr;
    dsp->shadow.avis = dsp->avis;
    dsp->shadow.ovly = dsp->ovly;
    dsp->shadow.ram = dsp->ram;
    dsp->shadow.mpmc = dsp->mpmc;
    dsp->shadow.ndx = dsp->ndx;
    dsp->shadow.trm = dsp->trm;
    dsp->shadow.braf = dsp->braf;
}

static void restore_shadow_context(C5x *dsp) {
    dsp->acc = dsp->shadow.acc;
    dsp->accb = dsp->shadow.accb;
    dsp->preg = dsp->shadow.preg;
    dsp->treg0 = dsp->shadow.treg0;
    dsp->treg1 = dsp->shadow.treg1;
    dsp->treg2 = dsp->shadow.treg2;
    dsp->arcr = dsp->shadow.arcr;
    dsp->indx = dsp->shadow.indx;
    dsp->arp = dsp->shadow.arp;
    dsp->arb = dsp->shadow.arb;
    dsp->dp = dsp->shadow.dp;
    dsp->ov = dsp->shadow.ov;
    dsp->ovm = dsp->shadow.ovm;
    /* audit #9: INTM/XF are not shadowed -- not restored here. */
    dsp->cnf = dsp->shadow.cnf;
    dsp->tc = dsp->shadow.tc;
    dsp->sxm = dsp->shadow.sxm;
    dsp->carry = dsp->shadow.carry;
    dsp->hm = dsp->shadow.hm;
    dsp->pm = dsp->shadow.pm;
    dsp->iptr = dsp->shadow.iptr;
    dsp->avis = dsp->shadow.avis;
    dsp->ovly = dsp->shadow.ovly;
    dsp->ram = dsp->shadow.ram;
    dsp->mpmc = dsp->shadow.mpmc;
    dsp->ndx = dsp->shadow.ndx;
    dsp->trm = dsp->shadow.trm;
    dsp->braf = dsp->shadow.braf;
}

/* Interrupt vectors, IPTR-relative (manual 8.2.2).
   Index = interrupt bit 0..8 (INT1..INT4).  Audited order:
   INT1..INT3, TINT, RINT, XINT, TRNT, TXNT, INT4. */
static const uint8_t ivec[N_INT] = {0x02, 0x04, 0x06, 0x08, 0x0A, 0x0C, 0x0E, 0x10, 0x12};
/* Old (wrong) table, still used so the firmware's `intr 17` (0x22)
   reaches the INT4 slot via the ROM-stub model.  Only the
   INTR instruction consults it, never external-interrupt entry. */
static const uint8_t ivec_legacy[N_INT] = {0x02, 0x04, 0x06, 0x18, 0x1A, 0x1C, 0x1E, 0x20, 0x22};

static void tick_timer(C5x *dsp);

/* Take the highest-priority pending, unmasked interrupt (lowest bit
   first).  Entry pushes PC, jumps IPTR-relative (or via ivec_ind),
   clears the flag, wakes from IDLE, shadows the context, and costs
   4 cycles when the cycle model is on (pipeline flush, manual 7.2.2 /
   App. B class X). */
static void check_int(C5x *dsp) {
    uint16_t pend = (uint16_t)(dsp->ifr & dsp->imr);
    if (dsp->intm || !pend) {
        return;
    }
    for (int i = 0; i < N_INT; i++) {
        if (pend & (1 << i)) {
            dsp->intm = 1;
            push(dsp, dsp->pc);
            dsp->pc = dsp->ivec_ind[i] ? data_read(dsp, dsp->ivec_ind[i]) : (uint16_t)((dsp->iptr << 11) | ivec[i]);
            dsp->ifr &= (uint16_t)~(1 << i);
            dsp->idle = 0;
            save_shadow_context(dsp);
            if (dsp->cycle_model) {
                for (int k = 0; k < 4; k++) {
                    dsp->cycles++;
                    tick_timer(dsp);
                }
            }
            return;
        }
    }
}

/* Data -> ACC with shift, honouring SXM (sign extension). */
static inline uint32_t extend_shift(C5x *dsp, uint16_t data, int shift) {
    return dsp->sxm ? (uint32_t)((int32_t)(int16_t)data << shift) : ((uint32_t)data << shift);
}

/* One timer tick (manual 9.4).  The prescaler counts down from TDDR;
   on expiry TIM counts down, and on TIM == 0 it reloads from PRD and
   raises TINT (IFR bit 3).  Stopped entirely while TSS is set. */
static inline void tick_timer(C5x *dsp) {
    if (dsp->tss) {
        return;
    }
    if (--dsp->psc < 0) {
        dsp->psc = dsp->tcr_tddr;
        if (dsp->tim == 0) {
            dsp->tim = dsp->prd;
            dsp->ifr |= (uint16_t)(1 << C5X_TINT);
            dsp->timer_exp++;
        } else {
            dsp->tim--;
        }
    }
}

/* ------------------------------------------------------------------
   Instruction execution

   execute_one() fetches one instruction, charges its base cycle, and
   dispatches on the high byte to one small helper per opcode class.
   Repeat loops keep the
   exact post-decrement accounting: the loop runs while rptc > -1
   and charges only when the pre-decrement value was > 0.
   ------------------------------------------------------------------ */

static void exec_be(C5x *dsp);
static void exec_bf(C5x *dsp);

/* High bytes 0x00..0x0F: LAR, LAMM, SMMR, SUBC, RPT, OUT, LDP, LST. */
static void exec_hi_00_0f(C5x *dsp, uint16_t op) {
    uint16_t addr, data;
    switch (opcode_high_byte(op)) {
    case C5X_OP_LAR_DMA_FIRST ... C5X_OP_LAR_DMA_LAST:
        /* LAR dma: load AR[(op>>8)] from data memory. */
        addr = effective_address(dsp);
        dsp->ar[opcode_ar_number(op)] = data_read(dsp, addr);
        if (opcode_ar_number(op) == 0) {
            dsp->ar0_dirty = 1;
        }
        break;
    case C5X_OP_LAMM:
        /* LAMM: ACC = data memory (page 0 only: address & 0x7F). */
        addr = (uint16_t)(effective_address(dsp) & C5X_DMA_DIRECT_OFFSET_MASK);
        dsp->acc = data_read(dsp, addr);
        break;
    case C5X_OP_SMMR: {
        /* SMMR: store the MMR at dma to successive program addresses.
           The source MMR is fixed: only the destination (#addr)
           advances (manual 6.3 SMMR).  Repeat total 2n. */
        uint16_t pfc = fetch(dsp);
        addr = (uint16_t)(effective_address(dsp) & C5X_DMA_DIRECT_OFFSET_MASK);
        while (dsp->rptc > -1) {
            data_write(dsp, pfc, data_read(dsp, addr));
            pfc++;
            if (dsp->rptc-- > 0) {
                dsp->cycles += 2;
            }
        }
        break;
    }
    case C5X_OP_SUBC:
        /* SUBC: conditional subtract, the divide step (audit #24:
           SUBC affects C and OV, no saturation). */
        addr = effective_address(dsp);
        data = data_read(dsp, addr);
        {
            uint32_t subtrahend = (uint32_t)data << 15, accumulator = dsp->acc;
            uint64_t difference = (uint64_t)accumulator - subtrahend;
            uint32_t result = (uint32_t)difference;
            dsp->carry = !((difference >> 32) & 1);
            if ((accumulator ^ subtrahend) & (accumulator ^ result) & 0x80000000u) {
                dsp->ov = 1;
            }
            dsp->acc = (int32_t)result >= 0 ? (result << 1) + 1 : accumulator << 1;
        }
        break;
    case C5X_OP_RPT_DMA:
        /* RPT dma: repeat count from data memory; the next instruction
           (at pc) is the repeated one. */
        addr = effective_address(dsp);
        dsp->rptc = data_read(dsp, addr);
        dsp->rpt_start = dsp->rpt_end = dsp->pc;
        break;
    case C5X_OP_OUT: {
        /* OUT: with RPT the port address increments per access
           (manual 6.3 IN/OUT). */
        uint16_t port = fetch(dsp);
        if (!dsp->in_repeat) {
            dsp->io_rep = 0;
        } else {
            dsp->io_rep++;
        }
        port = (uint16_t)(port + dsp->io_rep);
        addr = effective_address(dsp);
        io_write(dsp, port, data_read(dsp, addr));
        break;
    }
    case C5X_OP_LDP_DMA:
        /* LDP dma: load data-page pointer from data memory. */
        addr = effective_address(dsp);
        dsp->dp = (data_read(dsp, addr) & 0x1ff) << 7;
        break;
    case C5X_OP_LST0:
        /* LST #0: load ST0.  effective_address() may change ARB via an ARP switch, so
           ARB is saved and restored around it.  INTM is
           NOT loaded by LST #0 (only ARP/OV/OVM/DP come from the word). */
        {
            int arb0 = dsp->arb;
            addr = effective_address(dsp);
            dsp->arb = arb0;
        }
        data = data_read(dsp, addr);
        dsp->arp = data >> 13;
        dsp->ov = (data >> 12) & 1;
        dsp->ovm = (data >> 11) & 1;
        dsp->dp = (data & 0x1ff) << 7;
        break;
    case C5X_OP_LST1:
        /* LST #1: load ST1 (ARB and ARP both come from the word).
           CNF is in ST1, so this changes the fetch mapping. */
        block_state_changed(dsp);
        addr = effective_address(dsp);
        data = data_read(dsp, addr);
        dsp->arb = data >> 13;
        dsp->arp = data >> 13;
        dsp->cnf = (data >> 12) & 1;
        dsp->tc = (data >> 11) & 1;
        dsp->sxm = (data >> 10) & 1;
        dsp->carry = (data >> 9) & 1;
        dsp->hm = (data >> 6) & 1;
        dsp->xf = (data >> 4) & 1;
        dsp->pm = data & 3;
        break;
    }
}

/* High bytes 0x10..0x3F: LACC / ADD / SUB with shift, and BIT.
   The shift is the high nibble (op>>8)&0xF for LACC/ADD/SUB, and BIT
   tests bit 15-shift of the operand. */
static void exec_hi_10_3f(C5x *dsp, uint16_t op) {
    uint16_t addr;
    int hi = op >> 8;
    if (hi >= C5X_OP_LACC_SHIFT_FIRST && hi <= C5X_OP_LACC_SHIFT_LAST) {
        /* LACC dma,s */
        addr = effective_address(dsp);
        dsp->acc = extend_shift(dsp, data_read(dsp, addr), opcode_shift(op));
    } else if (hi >= C5X_OP_ADD_SHIFT_FIRST && hi <= C5X_OP_ADD_SHIFT_LAST) {
        /* ADD dma,s */
        addr = effective_address(dsp);
        dsp->acc = add32(dsp, dsp->acc, extend_shift(dsp, data_read(dsp, addr), opcode_shift(op)), 0, 0);
    } else if (hi >= C5X_OP_SUB_SHIFT_FIRST && hi <= C5X_OP_SUB_SHIFT_LAST) {
        /* SUB dma,s */
        addr = effective_address(dsp);
        dsp->acc = sub32(dsp, dsp->acc, extend_shift(dsp, data_read(dsp, addr), opcode_shift(op)), 0, 0);
    }
    /* NOTE: high bytes 0x40..0x4F are also BIT; they live in
       exec_hi_40_5f, not here. */
}

static void exec_hi_40_5f(C5x *dsp, uint16_t op);
static void exec_hi_60_7f(C5x *dsp, uint16_t op);
static void exec_hi_80_9f(C5x *dsp, uint16_t op);
static void exec_hi_a0_af(C5x *dsp, uint16_t op);
static void exec_hi_b0_bf(C5x *dsp, uint16_t op);
static void exec_hi_e0_ff(C5x *dsp, uint16_t op);

/* Execute one already-fetched opcode: the dispatch
   ladder plus the family call, without the fetch, the diagnostics
   branch, or the base-cycle charge.  execute_one() below is the fetch +
   execute_opcode() wrapper used by the main loop and delay_slot(); the RPTB
   block replay calls execute_opcode() directly with the decoded opcode, so a
   replayed instruction skips the re-fetch and the re-dispatch setup
   but executes byte-identical family code (ea/data_read/data_write, the cycle
   additions inside the families, the second-word fetch for two-word
   ops).  always_inline so the slow path keeps its current shape (the
   ladder + the inlined families live in execute_one as before) and the
   replay loop pays no extra call. */
static inline __attribute__((always_inline)) void execute_opcode(C5x *dsp, uint16_t op) {
    uint8_t hi = (uint8_t)(op >> 8);
    if (hi <= C5X_OP_LST1) {
        exec_hi_00_0f(dsp, op);
    } else if (hi <= C5X_OP_SUB_SHIFT_LAST) {
        exec_hi_10_3f(dsp, op);
    } else if (hi <= C5X_OP_CPL_LK) {
        exec_hi_40_5f(dsp, op);
    } else if (hi <= C5X_OP_BANZD) {
        exec_hi_60_7f(dsp, op);
    } else if (hi <= C5X_OP_SACH_LAST) {
        exec_hi_80_9f(dsp, op);
    } else if (hi <= C5X_OP_IN) {
        exec_hi_a0_af(dsp, op);
    } else if (hi <= C5X_OP_GROUP_BF) {
        exec_hi_b0_bf(dsp, op);
    } else if (hi >= C5X_OP_MPY_K13_FIRST && hi <= C5X_OP_MPY_K13_LAST) {
        /* MPY #k13: signed 13-bit immediate times TREG0. */
        int32_t k = op & K13_MASK;
        if (k & K13_SIGN_BIT) {
            k -= K13_RANGE;
        }
        dsp->preg = (uint32_t)((int32_t)(int16_t)dsp->treg0 * k);
    } else if (hi >= C5X_OP_BCND_FIRST) {
        exec_hi_e0_ff(dsp, op);
    } else {
        dsp->status = RUN_BADOP;
    }
}

static void execute_one(C5x *dsp) {
    uint16_t op;
    dsp->cur_pc = dsp->pc;
    /* Per-instruction diagnostics (hits / recent-PC ring / per-PC hits /
       trace capture).  Gated by c5x_set_diag(): the C driver runs with
       them off (it never reads these counters); the default is on so
       the Python ctypes .so keeps its old behaviour. */
    if (dsp->diag) {
        dsp->hits[dsp->pc]++;
        dsp->pc_ring[dsp->pc_ring_pos++ & 255] = dsp->pc;
        dsp->pc_hits[dsp->pc & 0xFFFF]++;
        if ((int32_t)dsp->pc == dsp->trace_pc && dsp->trace_n < TRACE_N) {
            dsp->trace_buf[dsp->trace_n].acc = dsp->acc;
            dsp->trace_buf[dsp->trace_n].ret = dsp->stack[dsp->sp];
            dsp->trace_buf[dsp->trace_n].ret2 = dsp->stack[(dsp->sp + 1) & 7];
            dsp->trace_buf[dsp->trace_n].cyc = dsp->cycles;
            dsp->trace_n++;
        }
    }
    op = dsp->opcode = fetch(dsp);
    dsp->cycles++; /* base cycle; the cycle model adds the rest in c5x_run */
    execute_opcode(dsp, op);
}

/* High bytes 0x40..0x5F: BIT, multiply/accumulate, DBMR logic ops. */
static void exec_hi_40_5f(C5x *dsp, uint16_t op) {
    uint16_t addr, data, immediate;
    int hi = op >> 8;
    switch (hi) {
    case C5X_OP_BIT_FIRST ... C5X_OP_BIT_LAST:
        /* BIT dma,s: TC = bit (15 - shift) of the operand. */
        addr = effective_address(dsp);
        dsp->tc = (data_read(dsp, addr) >> (15 - opcode_shift(op))) & 1;
        break;
    case C5X_OP_MPYA:
        /* MPYA: ACC += PREG (scaled); PREG = TREG0 * dma. */
        addr = effective_address(dsp);
        data = data_read(dsp, addr);
        dsp->acc = add32(dsp, dsp->acc, product_scaled(dsp), 0, 0);
        dsp->preg = (uint32_t)((int32_t)(int16_t)dsp->treg0 * (int32_t)(int16_t)data);
        break;
    case C5X_OP_MPYS:
        /* MPYS: ACC -= PREG (scaled); PREG = TREG0 * dma. */
        addr = effective_address(dsp);
        data = data_read(dsp, addr);
        dsp->acc = sub32(dsp, dsp->acc, product_scaled(dsp), 0, 0);
        dsp->preg = (uint32_t)((int32_t)(int16_t)dsp->treg0 * (int32_t)(int16_t)data);
        break;
    case C5X_OP_SQRA:
        /* SQRA: ACC += PREG; TREG0 = dma; PREG = dma * dma. */
        addr = effective_address(dsp);
        data = data_read(dsp, addr);
        dsp->acc = add32(dsp, dsp->acc, product_scaled(dsp), 0, 0);
        set_t0(dsp, data);
        dsp->preg = (uint32_t)((int32_t)(int16_t)data * (int32_t)(int16_t)data);
        break;
    case C5X_OP_SQRS:
        /* SQRS: ACC -= PREG; TREG0 = dma; PREG = dma * dma. */
        addr = effective_address(dsp);
        data = data_read(dsp, addr);
        dsp->acc = sub32(dsp, dsp->acc, product_scaled(dsp), 0, 0);
        set_t0(dsp, data);
        dsp->preg = (uint32_t)((int32_t)(int16_t)data * (int32_t)(int16_t)data);
        break;
    case C5X_OP_MPY_DMA:
        /* MPY dma: PREG = TREG0 * dma (signed). */
        addr = effective_address(dsp);
        data = data_read(dsp, addr);
        dsp->preg = (uint32_t)((int32_t)(int16_t)dsp->treg0 * (int32_t)(int16_t)data);
        break;
    case C5X_OP_MPYU:
        /* MPYU: PREG = TREG0 * dma (unsigned). */
        addr = effective_address(dsp);
        data = data_read(dsp, addr);
        dsp->preg = (uint32_t)dsp->treg0 * (uint32_t)data;
        break;
    case C5X_OP_UNDEFINED_56:
        dsp->status = RUN_BADOP;
        break;
    case C5X_OP_BLDP: {
        /* BLDP: block move data -> program, BMAR as source.
           Audit #15: BMAR is not written back (PFC <- BMAR, then
           PFC <- MCS); the local pfc advances, BMAR does not. */
        uint16_t pfc = dsp->bmar;
        while (dsp->rptc > -1) {
            addr = effective_address(dsp);
            program_write(dsp, pfc, data_read(dsp, addr));
            pfc++;
            if (dsp->rptc-- > 0) {
                dsp->cycles++;
            }
        }
        break;
    }
    case C5X_OP_XPL_DBMR:
        /* XPL dbmr: dma ^= DBMR; TC = (result == 0). */
        addr = effective_address(dsp);
        data = (uint16_t)(data_read(dsp, addr) ^ dsp->dbmr);
        dsp->tc = data == 0;
        data_write(dsp, addr, data);
        break;
    case C5X_OP_OPL_DBMR:
        /* OPL dbmr: dma |= DBMR; TC = (result == 0). */
        addr = effective_address(dsp);
        data = (uint16_t)(data_read(dsp, addr) | dsp->dbmr);
        dsp->tc = data == 0;
        data_write(dsp, addr, data);
        break;
    case C5X_OP_APL_DBMR:
        /* APL dbmr: dma &= DBMR; TC = (result == 0). */
        addr = effective_address(dsp);
        data = (uint16_t)(data_read(dsp, addr) & dsp->dbmr);
        dsp->tc = data == 0;
        data_write(dsp, addr, data);
        break;
    case C5X_OP_CPL_DBMR:
        /* CPL dbmr: TC = (dma == DBMR); no write. */
        addr = effective_address(dsp);
        dsp->tc = data_read(dsp, addr) == dsp->dbmr;
        break;
    case C5X_OP_XPL_LK:
        /* XPL #lk: dma ^= immediate; TC = (result == 0). */
        immediate = fetch(dsp);
        addr = effective_address(dsp);
        data = (uint16_t)(data_read(dsp, addr) ^ immediate);
        dsp->tc = data == 0;
        data_write(dsp, addr, data);
        break;
    case C5X_OP_OPL_LK:
        /* OPL #lk. */
        immediate = fetch(dsp);
        addr = effective_address(dsp);
        data = (uint16_t)(data_read(dsp, addr) | immediate);
        dsp->tc = data == 0;
        data_write(dsp, addr, data);
        break;
    case C5X_OP_APL_LK:
        /* APL #lk. */
        immediate = fetch(dsp);
        addr = effective_address(dsp);
        data = (uint16_t)(data_read(dsp, addr) & immediate);
        dsp->tc = data == 0;
        data_write(dsp, addr, data);
        break;
    case C5X_OP_CPL_LK:
        /* CPL #lk: TC = (dma == immediate); no write. */
        immediate = fetch(dsp);
        addr = effective_address(dsp);
        dsp->tc = data_read(dsp, addr) == immediate;
        break;
    }
}

/* High bytes 0x60..0x7F: add/sub variants, loads, logic, branches. */
static void exec_hi_60_7f(C5x *dsp, uint16_t op) {
    uint16_t addr, data, immediate;
    switch (opcode_high_byte(op)) {
    case C5X_OP_ADDC:
        /* ADDC: ACC += dma + C. */
        addr = effective_address(dsp);
        dsp->acc = add32(dsp, dsp->acc, data_read(dsp, addr), dsp->carry, 0);
        break;
    case C5X_OP_ADD_16:
        /* ADD dma,16: ACC += dma << 16 (16-bit form: carry sets C). */
        addr = effective_address(dsp);
        dsp->acc = add32(dsp, dsp->acc, (uint32_t)data_read(dsp, addr) << 16, 0, 1);
        break;
    case C5X_OP_ADDS:
        /* ADDS: ACC += dma (zero-extended, clears ACCH). */
        addr = effective_address(dsp);
        dsp->acc = add32(dsp, dsp->acc, data_read(dsp, addr), 0, 0);
        break;
    case C5X_OP_ADDT:
        /* ADDT: ACC += dma << TREG1. */
        addr = effective_address(dsp);
        dsp->acc = add32(dsp, dsp->acc, extend_shift(dsp, data_read(dsp, addr), dsp->treg1 & 0xF), 0, 0);
        break;
    case C5X_OP_SUBB:
        /* SUBB: ACC -= dma + !C. */
        addr = effective_address(dsp);
        dsp->acc = sub32(dsp, dsp->acc, data_read(dsp, addr), !dsp->carry, 0);
        break;
    case C5X_OP_SUB_16:
        /* SUB dma,16 (16-bit form). */
        addr = effective_address(dsp);
        dsp->acc = sub32(dsp, dsp->acc, (uint32_t)data_read(dsp, addr) << 16, 0, 1);
        break;
    case C5X_OP_SUBS:
        /* SUBS. */
        addr = effective_address(dsp);
        dsp->acc = sub32(dsp, dsp->acc, data_read(dsp, addr), 0, 0);
        break;
    case C5X_OP_SUBT:
        /* SUBT: ACC -= dma << TREG1. */
        addr = effective_address(dsp);
        dsp->acc = sub32(dsp, dsp->acc, extend_shift(dsp, data_read(dsp, addr), dsp->treg1 & 0xF), 0, 0);
        break;
    case C5X_OP_ZALR:
        /* ZALR: ACC = dma << 16 | 0x8000 (rounding bit). */
        addr = effective_address(dsp);
        dsp->acc = ((uint32_t)data_read(dsp, addr) << 16) | 0x8000;
        break;
    case C5X_OP_LACL:
        /* LACL dma. */
        addr = effective_address(dsp);
        dsp->acc = data_read(dsp, addr);
        break;
    case C5X_OP_LACC_16:
        /* LACC dma,16: ACC = dma << 16. */
        addr = effective_address(dsp);
        dsp->acc = (uint32_t)data_read(dsp, addr) << 16;
        break;
    case C5X_OP_LACT:
        /* LACT: ACC = dma << TREG1. */
        addr = effective_address(dsp);
        dsp->acc = extend_shift(dsp, data_read(dsp, addr), dsp->treg1 & 0xF);
        break;
    case C5X_OP_XOR:
        /* XOR dma. */
        addr = effective_address(dsp);
        dsp->acc ^= data_read(dsp, addr);
        break;
    case C5X_OP_OR:
        /* OR dma. */
        addr = effective_address(dsp);
        dsp->acc |= data_read(dsp, addr);
        break;
    case C5X_OP_AND:
        /* AND dma (clears ACCH: the 16-bit operand is zero-extended). */
        addr = effective_address(dsp);
        dsp->acc &= data_read(dsp, addr);
        break;
    case C5X_OP_BITT:
        /* BITT: TC = bit (15 - TREG2) of dma.  The (~treg2 & 0xF)
           spelling is the same as (15 - treg2) & 0xF. */
        addr = effective_address(dsp);
        dsp->tc = (data_read(dsp, addr) >> (~dsp->treg2 & 0xF)) & 1;
        break;
    case C5X_OP_LTA:
        /* LTA: ACC += PREG; TREG0 = dma. */
        addr = effective_address(dsp);
        data = data_read(dsp, addr);
        dsp->acc = add32(dsp, dsp->acc, product_scaled(dsp), 0, 0);
        set_t0(dsp, data);
        break;
    case C5X_OP_LTP:
        /* LTP: ACC = PREG (scaled); TREG0 = dma. */
        addr = effective_address(dsp);
        data = data_read(dsp, addr);
        dsp->acc = (uint32_t)product_scaled(dsp);
        set_t0(dsp, data);
        break;
    case C5X_OP_LTD:
        /* LTD: ACC += PREG; TREG0 = dma; DMOV dma -> dma+1. */
        addr = effective_address(dsp);
        data = data_read(dsp, addr);
        dsp->acc = add32(dsp, dsp->acc, product_scaled(dsp), 0, 0);
        set_t0(dsp, data);
        data_move_write(dsp, addr, data);
        break;
    case C5X_OP_LT:
        /* LT: TREG0 = dma. */
        addr = effective_address(dsp);
        set_t0(dsp, data_read(dsp, addr));
        break;
    case C5X_OP_LTS:
        /* LTS: ACC -= PREG; TREG0 = dma. */
        addr = effective_address(dsp);
        data = data_read(dsp, addr);
        dsp->acc = sub32(dsp, dsp->acc, product_scaled(dsp), 0, 0);
        set_t0(dsp, data);
        break;
    case C5X_OP_LPH:
        /* LPH: PREG high half = dma. */
        addr = effective_address(dsp);
        dsp->preg = (dsp->preg & 0xFFFF) | ((uint32_t)data_read(dsp, addr) << 16);
        break;
    case C5X_OP_PSHD:
        /* PSHD: push dma. */
        addr = effective_address(dsp);
        push(dsp, data_read(dsp, addr));
        break;
    case C5X_OP_DMOV:
        /* DMOV: dma -> dma+1, only within on-chip RAM (audit #16). */
        addr = effective_address(dsp);
        data_move_write(dsp, addr, data_read(dsp, addr));
        break;
    case C5X_OP_ADRK:
        /* ADRK: AR[ARP] += k8 (low byte, unsigned). */
        step_aux_reg(dsp, dsp->arp, opcode_k8(op));
        break;
    case C5X_OP_B:
        /* B: effective_address() runs for its addressing side effects, then PC = immediate. */
        immediate = fetch(dsp);
        effective_address(dsp);
        dsp->pc = immediate;
        break;
    case C5X_OP_CALL:
        /* CALL: push return, PC = immediate. */
        immediate = fetch(dsp);
        effective_address(dsp);
        push(dsp, dsp->pc);
        dsp->pc = immediate;
        break;
    case C5X_OP_BANZ: {
        /* BANZ: branch if AR[ARP] != 0.  The take decision is made
           before effective_address(), so an ARP-switching addressing
           mode does not change which AR was tested. */
        immediate = fetch(dsp);
        int take = dsp->ar[dsp->arp] != 0;
        effective_address(dsp);
        if (take) {
            dsp->pc = immediate;
        }
        break;
    }
    case C5X_OP_SBRK:
        /* SBRK: AR[ARP] -= k8. */
        step_aux_reg(dsp, dsp->arp, -(int)opcode_k8(op));
        break;
    case C5X_OP_BD:
        /* BD: delayed branch; two slot words run before the jump. */
        immediate = fetch(dsp);
        effective_address(dsp);
        delay_slot(dsp, dsp->pc);
        dsp->pc = immediate;
        break;
    case C5X_OP_CALLD:
        /* CALLD: delayed call; return address is pc+2 (past the two
           slot words), pushed before the slot runs. */
        immediate = fetch(dsp);
        effective_address(dsp);
        push(dsp, (uint16_t)(dsp->pc + 2));
        delay_slot(dsp, dsp->pc);
        dsp->pc = immediate;
        break;
    case C5X_OP_BANZD: {
        /* BANZD: delayed BANZ; take decision before effective_address(), as in BANZ. */
        immediate = fetch(dsp);
        int take = dsp->ar[dsp->arp] != 0;
        effective_address(dsp);
        delay_slot(dsp, dsp->pc);
        if (take) {
            dsp->pc = immediate;
        }
        break;
    }
    }
}

/* High bytes 0x80..0x9F: SAR, SAMM, LMMR, POPD, MAR, SPL/SPH, SST, SACL/SACH. */
static void exec_hi_80_9f(C5x *dsp, uint16_t op) {
    uint16_t addr, data;
    int hi = op >> 8;
    if (hi >= C5X_OP_SAR_FIRST && hi <= C5X_OP_SAR_LAST) {
        /* SAR: store AR[(op>>8)] to data memory.  The AR value is read
           before effective_address(), so an ARP-switching mode stores the old AR. */
        data = dsp->ar[opcode_ar_number(op)];
        addr = effective_address(dsp);
        data_write(dsp, addr, data);
    } else if (hi == C5X_OP_SAMM) {
        /* SAMM: store ACC low half to page-0 data memory. */
        addr = (uint16_t)(effective_address(dsp) & C5X_DMA_DIRECT_OFFSET_MASK);
        data_write(dsp, addr, (uint16_t)dsp->acc);
    } else if (hi == C5X_OP_LMMR) {
        /* LMMR: load the (fixed) destination MMR from successive
           program addresses (manual 6.3 LMMR).  Repeat total 2n. */
        uint16_t pfc = fetch(dsp);
        addr = (uint16_t)(effective_address(dsp) & C5X_DMA_DIRECT_OFFSET_MASK);
        while (dsp->rptc > -1) {
            data_write(dsp, addr, data_read(dsp, pfc));
            pfc++;
            if (dsp->rptc-- > 0) {
                dsp->cycles += 2;
            }
        }
    } else if (hi == C5X_OP_POPD) {
        /* POPD: pop the stack to data memory. */
        addr = effective_address(dsp);
        data_write(dsp, addr, pop(dsp));
    } else if (hi == C5X_OP_MAR) {
        /* MAR: no-op except for the addressing-mode side effect, and
           only when bit 7 is set (indirect). */
        if (op & C5X_DMA_INDIRECT_BIT) {
            effective_address(dsp);
        }
    } else if (hi == C5X_OP_SPL) {
        /* SPL: store PREG low half (scaled). */
        addr = effective_address(dsp);
        data_write(dsp, addr, (uint16_t)product_scaled(dsp));
    } else if (hi == C5X_OP_SPH) {
        /* SPH: store PREG high half (scaled). */
        addr = effective_address(dsp);
        data_write(dsp, addr, (uint16_t)((uint32_t)product_scaled(dsp) >> 16));
    } else if (hi == C5X_OP_SST0) {
        /* SST #0: store ST0, page-0 direct addressing. */
        addr = effective_address_page0(dsp);
        data_write(dsp, addr, st0_get(dsp));
    } else if (hi == C5X_OP_SST1) {
        /* SST #1: store ST1, page-0 direct addressing. */
        addr = effective_address_page0(dsp);
        data_write(dsp, addr, st1_get(dsp));
    } else if (hi >= C5X_OP_SACL_FIRST && hi <= C5X_OP_SACL_LAST) {
        /* SACL: store ACC low half, shifted left by (op>>8)&7. */
        addr = effective_address(dsp);
        data_write(dsp, addr, (uint16_t)(dsp->acc << opcode_sacx_shift(op)));
    } else if (hi >= C5X_OP_SACH_FIRST && hi <= C5X_OP_SACH_LAST) {
        /* SACH: store ACC high half, shifted left by (op>>8)&7. */
        addr = effective_address(dsp);
        data_write(dsp, addr, (uint16_t)((dsp->acc << opcode_sacx_shift(op)) >> 16));
    }
}

/* High bytes 0xA0..0xAF: NORM, MAC/MACD, BLPD, TBLR/TBLW, BLDD,
   MADS/MADD, SPLK, IN. */
static void exec_hi_a0_af(C5x *dsp, uint16_t op) {
    uint16_t addr, data, immediate;
    int hi = op >> 8;
    switch (hi) {
    case C5X_OP_NORM: {
        /* NORM: shift ACC left until bits 31/30 differ (or ACC == 0).
           Audit #23: the AR is modified only when the ACC is shifted,
           so effective_address() runs only on the shifting path. */
        int t = (int)(((dsp->acc >> 31) ^ (dsp->acc >> 30)) & 1);
        if (dsp->acc == 0) {
            t = 1;
        }
        if (!t) {
            effective_address(dsp);
        }
        if (t) {
            dsp->tc = 1;
        } else {
            dsp->tc = 0;
            dsp->acc <<= 1;
        }
        break;
    }
    case C5X_OP_UNDEFINED_A1:
        dsp->status = RUN_BADOP;
        break;
    case C5X_OP_MAC:
    case C5X_OP_MACD: {
        /* MAC / MACD: ACC += PREG; TREG0 = dma; PREG = dma * pma.
           MACD additionally DMOVs dma -> dma+1.  The do-while runs
           at least once even with rptc == -1. */
        uint16_t pfc = fetch(dsp);
        do {
            addr = effective_address(dsp);
            data = data_read(dsp, addr);
            dsp->acc = add32(dsp, dsp->acc, product_scaled(dsp), 0, 0);
            set_t0(dsp, data);
            dsp->preg = (uint32_t)((int32_t)(int16_t)data * (int32_t)(int16_t)program_read(dsp, pfc));
            pfc++;
            if (opcode_high_byte(op) == C5X_OP_MACD) {
                data_move_write(dsp, addr, data);
            }
            if (dsp->rptc > -1) {
                if (dsp->rptc-- > 0) {
                    dsp->cycles++;
                }
            }
        } while (dsp->rptc > -1);
        break;
    }
    case C5X_OP_BLPD_BMAR: {
        /* BLPD bmar,dma: program (BMAR) -> data.  Audit #15: BMAR is
           not written back. */
        uint16_t pfc = dsp->bmar;
        while (dsp->rptc > -1) {
            addr = effective_address(dsp);
            data_write(dsp, addr, program_read(dsp, pfc));
            pfc++;
            if (dsp->rptc-- > 0) {
                dsp->cycles++;
            }
        }
        break;
    }
    case C5X_OP_BLPD_PMA: {
        /* BLPD #pma,dma. */
        uint16_t pfc = fetch(dsp);
        while (dsp->rptc > -1) {
            addr = effective_address(dsp);
            data_write(dsp, addr, program_read(dsp, pfc));
            pfc++;
            if (dsp->rptc-- > 0) {
                dsp->cycles++;
            }
        }
        break;
    }
    case C5X_OP_TBLR: {
        /* TBLR: program (ACC) -> data.  ACC is unchanged (PFC is
           internal). */
        uint16_t pfc = (uint16_t)dsp->acc;
        while (dsp->rptc > -1) {
            addr = effective_address(dsp);
            data_write(dsp, addr, program_read(dsp, pfc));
            pfc++;
            if (dsp->rptc-- > 0) {
                dsp->cycles++;
            }
        }
        (void)pfc;
        break;
    }
    case C5X_OP_TBLW: {
        /* TBLW: data -> program (ACC).  ACC is unchanged. */
        uint16_t pfc = (uint16_t)dsp->acc;
        while (dsp->rptc > -1) {
            addr = effective_address(dsp);
            program_write(dsp, pfc, data_read(dsp, addr));
            pfc++;
            if (dsp->rptc-- > 0) {
                dsp->cycles++;
            }
        }
        (void)pfc;
        break;
    }
    case C5X_OP_BLDD_LK_DMA: {
        /* BLDD #lk,dma: data -> data. */
        uint16_t pfc = fetch(dsp);
        while (dsp->rptc > -1) {
            addr = effective_address(dsp);
            data_write(dsp, addr, data_read(dsp, pfc));
            pfc++;
            if (dsp->rptc-- > 0) {
                dsp->cycles++;
            }
        }
        break;
    }
    case C5X_OP_BLDD_DMA_LK: {
        /* BLDD dma,#lk: data -> data (reversed direction). */
        uint16_t pfc = fetch(dsp);
        while (dsp->rptc > -1) {
            addr = effective_address(dsp);
            data_write(dsp, pfc, data_read(dsp, addr));
            pfc++;
            if (dsp->rptc-- > 0) {
                dsp->cycles++;
            }
        }
        break;
    }
    case C5X_OP_MADS:
    case C5X_OP_MADD: {
        /* MADS / MADD: like MAC but the program address comes from
           BMAR, and TREG0 is written directly -- audit N-1: no TRM
           mirror (set_t0 is NOT used).  MADD additionally DMOVs.
           Audit #15: BMAR is not written back. */
        uint16_t pfc = dsp->bmar;
        do {
            addr = effective_address(dsp);
            data = data_read(dsp, addr);
            dsp->acc = add32(dsp, dsp->acc, product_scaled(dsp), 0, 0);
            dsp->treg0 = data;
            dsp->preg = (uint32_t)((int32_t)(int16_t)data * (int32_t)(int16_t)program_read(dsp, pfc));
            pfc++;
            if (opcode_high_byte(op) == C5X_OP_MADD) {
                data_move_write(dsp, addr, data);
            }
            if (dsp->rptc > -1) {
                if (dsp->rptc-- > 0) {
                    dsp->cycles++;
                }
            }
        } while (dsp->rptc > -1);
        break;
    }
    case C5X_OP_BLDD_BMAR_DMA: {
        /* BLDD bmar,dma.  Audit #15: BMAR is not written back. */
        uint16_t pfc = dsp->bmar;
        while (dsp->rptc > -1) {
            addr = effective_address(dsp);
            data_write(dsp, addr, data_read(dsp, pfc));
            pfc++;
            if (dsp->rptc-- > 0) {
                dsp->cycles++;
            }
        }
        break;
    }
    case C5X_OP_BLDD_DMA_BMAR: {
        /* BLDD dma,bmar.  Audit #15: BMAR is not written back. */
        uint16_t pfc = dsp->bmar;
        while (dsp->rptc > -1) {
            addr = effective_address(dsp);
            data_write(dsp, pfc, data_read(dsp, addr));
            pfc++;
            if (dsp->rptc-- > 0) {
                dsp->cycles++;
            }
        }
        break;
    }
    case C5X_OP_SPLK:
        /* SPLK: store immediate to data memory.  NOTE the order: effective_address()
           runs BEFORE the immediate is fetched here,
           unlike the 0x5C..0x5F logic-immediate forms. */
        addr = effective_address(dsp);
        immediate = fetch(dsp);
        data_write(dsp, addr, immediate);
        break;
    case C5X_OP_IN: {
        /* IN: with RPT the port address increments per access
           (manual 6.3 IN/OUT), mirroring OUT (0x0C). */
        uint16_t port = fetch(dsp);
        if (!dsp->in_repeat) {
            dsp->io_rep = 0;
        } else {
            dsp->io_rep++;
        }
        port = (uint16_t)(port + dsp->io_rep);
        addr = effective_address(dsp);
        data_write(dsp, addr, io_read(dsp, port));
        break;
    }
    }
}

/* High bytes 0xB0..0xBF: LAR #k8, ADDK/LACK/SUBK, RPT #k8, LDP #k9,
   and the 0xBE / 0xBF sub-decoders. */
static void exec_hi_b0_bf(C5x *dsp, uint16_t op) {
    int hi = op >> 8;
    if (hi >= C5X_OP_LAR_K8_FIRST && hi <= C5X_OP_LAR_K8_LAST) {
        /* LAR #k8: AR[(op>>8)] = low byte. */
        dsp->ar[opcode_ar_number(op)] = opcode_k8(op);
        if (opcode_ar_number(op) == 0) {
            dsp->ar0_dirty = 1;
        }
    } else if (hi == C5X_OP_ADDK) {
        /* ADDK: ACC += k8. */
        dsp->acc = add32(dsp, dsp->acc, opcode_k8(op), 0, 0);
    } else if (hi == C5X_OP_LACK) {
        /* LACK: ACC = k8 (zero-extended). */
        dsp->acc = opcode_k8(op);
    } else if (hi == C5X_OP_SUBK) {
        /* SUBK: ACC -= k8. */
        dsp->acc = sub32(dsp, dsp->acc, opcode_k8(op), 0, 0);
    } else if (hi == C5X_OP_RPT_K8) {
        /* RPT #k8: the next instruction (at pc) is the repeated one. */
        dsp->rptc = opcode_k8(op);
        dsp->rpt_start = dsp->rpt_end = dsp->pc;
    } else if (hi >= C5X_OP_LDP_K9_FIRST && hi <= C5X_OP_LDP_K9_LAST) {
        /* LDP #k9: DP = low 9 bits << 7. */
        dsp->dp = (op & 0x1ff) << 7;
    } else if (hi == C5X_OP_GROUP_BE) {
        exec_be(dsp);
    } else if (hi == C5X_OP_GROUP_BF) {
        exec_bf(dsp);
    }
}

/* 0xBE sub-decoder, part 1: accumulator ops (low byte 0x00..0x1F).
   Unlisted low bytes in this range are BADOP (the default arm; they cannot
   match the INTR pattern 0x60..0x7F). */
static void exec_be_acc(C5x *dsp) {
    uint16_t op = dsp->opcode;
    uint32_t temporary;
    switch (opcode_low_byte(op)) {
    case C5X_BE_ABS:
        /* ABS: |ACC|, saturating at 0x80000000 under OVM. */
        if (dsp->acc == 0x80000000u) {
            dsp->ov = 1;
            dsp->carry = 0;
            dsp->acc = dsp->ovm ? 0x7fffffffu : 0x80000000u;
        } else {
            if ((int32_t)dsp->acc < 0) {
                dsp->acc = (uint32_t)(-(int32_t)dsp->acc);
            }
            dsp->carry = 0;
        }
        break;
    case C5X_BE_CMPL:
        dsp->acc = ~dsp->acc;
        break; /* CMPL */
    case C5X_BE_NEG:
        /* NEG: -ACC, saturating at 0x80000000 under OVM; C = (result == 0). */
        if (dsp->acc == 0x80000000u) {
            dsp->ov = 1;
            dsp->carry = 0;
            dsp->acc = dsp->ovm ? 0x7fffffffu : 0x80000000u;
        } else {
            dsp->acc = (uint32_t)(-(int32_t)dsp->acc);
            dsp->carry = dsp->acc == 0;
        }
        break;
    case C5X_BE_PAC:
        dsp->acc = (uint32_t)product_scaled(dsp);
        break; /* ACC = PREG (scaled) */
    case C5X_BE_APAC:
        dsp->acc = add32(dsp, dsp->acc, product_scaled(dsp), 0, 0);
        break; /* ACC += PREG (scaled) */
    case C5X_BE_SPAC:
        dsp->acc = sub32(dsp, dsp->acc, product_scaled(dsp), 0, 0);
        break;       /* ACC -= PREG (scaled) */
    case C5X_BE_SFL: /* shift left: the bit shifted out goes to C */
        dsp->carry = (int)(dsp->acc >> 31);
        dsp->acc <<= 1;
        break;
    case C5X_BE_SFR: /* shift right (arithmetic when SXM is set): the bit shifted out goes to C */
        dsp->carry = (int)(dsp->acc & 1);
        dsp->acc = dsp->sxm ? (uint32_t)((int32_t)dsp->acc >> 1) : dsp->acc >> 1;
        break;
    case C5X_BE_ROL: /* rotate left through C */
        temporary = (uint32_t)dsp->carry;
        dsp->carry = (int)(dsp->acc >> 31);
        dsp->acc = (dsp->acc << 1) | temporary;
        break;
    case C5X_BE_ROR: /* rotate right through C */
        temporary = (uint32_t)dsp->carry;
        dsp->carry = (int)(dsp->acc & 1);
        dsp->acc = (dsp->acc >> 1) | (temporary << 31);
        break;
    case C5X_BE_ADDB:
        dsp->acc = add32(dsp, dsp->acc, dsp->accb, 0, 0);
        break; /* ADDB */
    case C5X_BE_ADCB:
        dsp->acc = add32(dsp, dsp->acc, dsp->accb, dsp->carry, 0);
        break; /* ADDC (ACCB) */
    case C5X_BE_ANDB:
        dsp->acc &= dsp->accb;
        break; /* ANDB */
    case C5X_BE_ORB:
        dsp->acc |= dsp->accb;
        break;        /* ORB */
    case C5X_BE_ROLB: /* ROLB: 64-bit rotate left through C */
    {
        uint32_t acc_value = dsp->acc, accb_value = dsp->accb, carry_in = (uint32_t)dsp->carry;
        dsp->acc = (acc_value << 1) | (accb_value >> 31);
        dsp->accb = (accb_value << 1) | carry_in;
        dsp->carry = (int)(acc_value >> 31);
    } break;
    case C5X_BE_RORB: /* RORB: 64-bit rotate right through C */
    {
        uint32_t acc_value = dsp->acc, accb_value = dsp->accb, carry_in = (uint32_t)dsp->carry;
        dsp->accb = (accb_value >> 1) | (acc_value << 31);
        dsp->acc = (acc_value >> 1) | (carry_in << 31);
        dsp->carry = (int)(accb_value & 1);
    } break;
    case C5X_BE_SFLB: /* SFLB: 64-bit shift left (ACCB bit 31 feeds ACC) */
    {
        uint32_t addr = dsp->acc, b = dsp->accb;
        dsp->acc = (addr << 1) | (b >> 31);
        dsp->accb = b << 1;
        dsp->carry = (int)(addr >> 31);
    } break;
    case C5X_BE_SFRB: /* SFRB: 64-bit shift right (ACC bit 31 feeds ACCB) */
    {
        uint32_t addr = dsp->acc, b = dsp->accb;
        dsp->accb = (b >> 1) | (addr << 31);
        dsp->acc = dsp->sxm ? (uint32_t)((int32_t)addr >> 1) : addr >> 1;
        dsp->carry = (int)(b & 1);
    } break;
    case C5X_BE_SUBB:
        dsp->acc = sub32(dsp, dsp->acc, dsp->accb, 0, 0);
        break; /* SUBB */
    case C5X_BE_SBBB:
        /* SBBB: ACC -= ACCB + !C.  Affects C only: no OV, no
           saturation (SPRU056D p.6-233). */
        {
            uint64_t r = (uint64_t)dsp->acc - (uint64_t)dsp->accb - (uint64_t)(!dsp->carry);
            dsp->carry = !((r >> 32) & 1);
            dsp->acc = (uint32_t)r;
        }
        break;
    case C5X_BE_XORB:
        dsp->acc ^= dsp->accb;
        break;        /* XORB */
    case C5X_BE_CRGT: /* MAX: larger of ACC/ACCB ends in ACCB, C = (ACC >= ACCB) */
        if ((int32_t)dsp->acc >= (int32_t)dsp->accb) {
            dsp->accb = dsp->acc;
            dsp->carry = 1;
        } else {
            dsp->acc = dsp->accb;
            dsp->carry = 0;
        }
        break;
    case C5X_BE_CRLT: /* MIN: smaller of ACC/ACCB ends in ACC, C = (ACC < ACCB) */
        if ((int32_t)dsp->acc >= (int32_t)dsp->accb) {
            dsp->acc = dsp->accb;
            dsp->carry = 0;
        } else {
            dsp->accb = dsp->acc;
            dsp->carry = 1;
        }
        break;
    case C5X_BE_EXAR:
        temporary = dsp->acc;
        dsp->acc = dsp->accb;
        dsp->accb = temporary;
        break; /* SWAP */
    case C5X_BE_SACB:
        dsp->accb = dsp->acc;
        break; /* SACB */
    case C5X_BE_LACB:
        dsp->acc = dsp->accb;
        break; /* LACB */
    default:
        dsp->status = RUN_BADOP;
    }
}

/* 0xBE sub-decoder, part 2: control, status, and immediate ops
   (low byte 0x20..0xFF), including the INTR default arm. */
static void exec_be_ctrl(C5x *dsp) {
    uint16_t op = dsp->opcode;
    uint16_t immediate;
    switch (opcode_low_byte(op)) {
    case C5X_BE_BACC:
        dsp->pc = (uint16_t)dsp->acc;
        break;         /* BACC */
    case C5X_BE_BACCD: /* BACCD: delayed branch to ACC */
    {
        uint16_t target = (uint16_t)dsp->acc;
        delay_slot(dsp, dsp->pc);
        dsp->pc = target;
    } break;
    case C5X_BE_IDLE:
        dsp->idle = 1;
        break; /* IDLE */
    case C5X_BE_IDLE2:
        dsp->idle = 2;
        break; /* IDLE2: peripherals stopped, only
                                        RS/NMI/INT1-4 wake the CPU (4.10.2) */
    case C5X_BE_CALA:
        push(dsp, dsp->pc);
        dsp->pc = (uint16_t)dsp->acc;
        break; /* CALA */
    case C5X_BE_POP:
        dsp->acc = pop(dsp);
        break; /* POP */
    case C5X_BE_RETI:
        dsp->pc = pop(dsp);
        restore_shadow_context(dsp);
        break; /* RETI */
    case C5X_BE_RETE:
        dsp->pc = pop(dsp);
        restore_shadow_context(dsp);
        dsp->intm = 0;
        break; /* RETE */
    case C5X_BE_PSHA:
        push(dsp, (uint16_t)dsp->acc);
        break;         /* PSHA */
    case C5X_BE_CALAD: /* CALAD: delayed call to ACC; return is pc+2 */
    {
        uint16_t target = (uint16_t)dsp->acc;
        push(dsp, (uint16_t)(dsp->pc + 2));
        delay_slot(dsp, dsp->pc);
        dsp->pc = target;
    } break;
    case C5X_BE_EINT:
        dsp->intm = 0;
        dsp->interrupt_inhibit = 1;
        break; /* EINT (+1-cycle inh.) */
    case C5X_BE_DINT:
        dsp->intm = 1;
        break; /* DINT */
    case C5X_BE_ROVM:
        dsp->ovm = 0;
        break; /* ROVM */
    case C5X_BE_SOVM:
        dsp->ovm = 1;
        break; /* SOVM */
    case C5X_BE_RCNF:
        block_state_changed(dsp);
        dsp->cnf = 0;
        break; /* RCNF */
    case C5X_BE_SCNF:
        block_state_changed(dsp);
        dsp->cnf = 1;
        break; /* SCNF */
    case C5X_BE_RSXM:
        dsp->sxm = 0;
        break; /* RSXM */
    case C5X_BE_SSXM:
        dsp->sxm = 1;
        break; /* SSXM */
    case C5X_BE_RHM:
        dsp->hm = 0;
        break; /* RHM */
    case C5X_BE_SHM:
        dsp->hm = 1;
        break; /* SHM */
    case C5X_BE_RTC:
        dsp->tc = 0;
        break; /* RTC */
    case C5X_BE_STC:
        dsp->tc = 1;
        break; /* STC */
    case C5X_BE_RXF:
        dsp->xf = 0;
        break; /* RXF */
    case C5X_BE_SXF:
        dsp->xf = 1;
        break; /* SXF */
    case C5X_BE_RCB:
        dsp->carry = 0;
        break; /* RCB */
    case C5X_BE_SCB:
        dsp->carry = 1;
        break; /* SCB */
    case C5X_BE_TRAP:
        /* Push PC, jump to IPTR-relative vector 0x22.
           NOTE: no INTM set and no context shadow here,
           unlike INTR for INT1-INT4 below and unlike 0x52. */
        push(dsp, dsp->pc);
        dsp->pc = (uint16_t)((dsp->iptr << 11) | 0x22);
        break;
    case C5X_BE_NMI:
        /* NMI: push PC, jump to vector 0x24, mask interrupts. */
        push(dsp, dsp->pc);
        dsp->pc = (uint16_t)((dsp->iptr << 11) | 0x24);
        dsp->intm = 1;
        break;
    case C5X_BE_ZPR:
        dsp->preg = 0;
        break; /* PREG = 0 */
    case C5X_BE_ZAP:
        dsp->acc = 0;
        dsp->preg = 0;
        break; /* ACC = 0, PREG = 0 */
    case C5X_BE_SATH:
        /* SATH: if TREG1 bit 4 set, ACC >>= 16 (sign per SXM). */
        if (dsp->treg1 & 0x10) {
            dsp->acc = dsp->sxm ? (uint32_t)((int32_t)dsp->acc >> 16) : dsp->acc >> 16;
        }
        break;
    case C5X_BE_SATL: {
        /* SATL: ACC >>= (TREG1 & 0xF) (sign per SXM). */
        uint32_t shift = dsp->treg1 & 0xF;
        dsp->acc = dsp->sxm ? (uint32_t)((int32_t)dsp->acc >> shift) : dsp->acc >> shift;
        break;
    }
    case C5X_BE_MPY_LK:
        /* MPY #lk: PREG = TREG0 * immediate. */
        immediate = fetch(dsp);
        dsp->preg = (uint32_t)((int32_t)(int16_t)dsp->treg0 * (int32_t)(int16_t)immediate);
        break;
    case C5X_BE_AND_LK_16:
        /* AND #lk,16: ACC &= immediate << 16. */
        immediate = fetch(dsp);
        dsp->acc &= (uint32_t)immediate << 16;
        break;
    case C5X_BE_OR_LK_16:
        /* OR #lk,16. */
        immediate = fetch(dsp);
        dsp->acc |= (uint32_t)immediate << 16;
        break;
    case C5X_BE_XOR_LK_16:
        /* XOR #lk,16. */
        immediate = fetch(dsp);
        dsp->acc ^= (uint32_t)immediate << 16;
        break;
    case C5X_BE_RPT_LK:
        /* RPT #lk: repeat count from the next word. */
        dsp->rptc = fetch(dsp);
        dsp->rpt_start = dsp->rpt_end = dsp->pc;
        break;
    case C5X_BE_RPTZ_LK:
        /* RPTZ #lk: like RPT, and ACC = PREG = 0. */
        dsp->rptc = fetch(dsp);
        dsp->rpt_start = dsp->rpt_end = dsp->pc;
        dsp->acc = 0;
        dsp->preg = 0;
        break;
    case C5X_BE_RPTB:
        /* RPTB: repeat block; PAER = operand = address of the last
           loop word (manual 4.7, Example 4-8: RPTB END_LOOP-1). */
        immediate = fetch(dsp);
        dsp->braf = 1;
        dsp->pasr = dsp->pc;
        dsp->paer = immediate;
        break;
    default:
        if ((op & C5X_BE_INTR_MASK) == C5X_BE_INTR_BASE) {
            /* INTR k: software interrupt.  Vector = K*2, IPTR-relative.
               INTR for INT1-INT4 (K=1,2,3,9) behaves like the external
               interrupt, context shadow included (manual 4.8.7).
               If ivec_ind is set for that vector (checked against both
               the audited table and the legacy table), the jump goes
               via dmem[ivec_ind[i]] instead. */
            uint16_t v = (uint16_t)((op & C5X_BE_INTR_VECTOR_MASK) << 1);
            int i;
            push(dsp, dsp->pc);
            dsp->intm = 1;
            dsp->pc = (uint16_t)((dsp->iptr << 11) | v);
            if (v == 0x02 || v == 0x04 || v == 0x06 || v == 0x12) {
                save_shadow_context(dsp);
            }
            for (i = 0; i < N_INT; i++) {
                if (ivec[i] == v && dsp->ivec_ind[i]) {
                    dsp->pc = data_read(dsp, dsp->ivec_ind[i]);
                    save_shadow_context(dsp);
                    break;
                }
            }
            if (i == N_INT) {
                for (i = 0; i < N_INT; i++) {
                    if (ivec_legacy[i] == v && dsp->ivec_ind[i]) {
                        dsp->pc = data_read(dsp, dsp->ivec_ind[i]);
                        save_shadow_context(dsp);
                        break;
                    }
                }
            }
            break;
        }
        dsp->status = RUN_BADOP;
    }
}

/* 0xBE sub-decoder: dispatch on the low byte. */
static void exec_be(C5x *dsp) {
    if ((dsp->opcode & 0xff) < C5X_BE_CONTROL_FIRST) {
        exec_be_acc(dsp);
    } else {
        exec_be_ctrl(dsp);
    }
}

/* 0xBF sub-decoder: PM select, LAR #lk, CMPR, long-immediate ALU ops. */
static void exec_bf(C5x *dsp) {
    uint16_t op = dsp->opcode, immediate;
    int shift_count = op & C5X_BF_SHIFT_MASK;
    int32_t data;
    switch (opcode_low_byte(op)) {
    case C5X_BF_SPM_FIRST ... C5X_BF_SPM_LAST:
        /* SPM k: PM = low 2 bits. */
        dsp->pm = op & C5X_BF_SPM_MASK;
        break;
    case C5X_BF_LAR_LK_FIRST ... C5X_BF_LAR_LK_LAST:
        /* LAR #lk: AR[(op&7)] = next word. */
        immediate = fetch(dsp);
        dsp->ar[op & 7] = immediate;
        if ((op & 7) == 0) {
            dsp->ar0_dirty = 1;
        }
        break;
    case C5X_BF_CMPR_FIRST ... C5X_BF_CMPR_LAST: {
        /* CMPR: compare AR[ARP] against ARCR (or AR0 when the
           cmpr_ar0 experiment is on).  Mode: equal, less, greater, not equal. */
        uint16_t ar_value = dsp->ar[dsp->arp];
        int mode = op & C5X_BF_CMPR_MODE_MASK;
        uint16_t compare_value = dsp->cmpr_ar0 ? dsp->ar[0] : dsp->arcr;
        dsp->tc = mode == C5X_CMPR_EQUAL     ? ar_value == compare_value
                  : mode == C5X_CMPR_LESS    ? ar_value < compare_value
                  : mode == C5X_CMPR_GREATER ? ar_value > compare_value
                                             : ar_value != compare_value;
        break;
    }
    default:
        /* The remaining 0xBFxx opcodes: long-immediate ALU forms (0x80..0xD0),
           SFTA (0xE0); anything else is a bad opcode. */
        {
            int row = op & C5X_BF_ROW_MASK;
            if (row >= C5X_BF_ROW_LK_FIRST && row <= C5X_BF_ROW_LK_LAST) {
                /* Long-immediate ALU: LACC/ADD/SUB/AND/OR/XOR #lk,shift_count. */
                immediate = fetch(dsp);
                switch (row) {
                case C5X_BF_ROW_LACC_LK:
                    dsp->acc = extend_shift(dsp, immediate, shift_count);
                    break;
                case C5X_BF_ROW_ADD_LK:
                    dsp->acc = add32(dsp, dsp->acc, extend_shift(dsp, immediate, shift_count), 0, 0);
                    break;
                case C5X_BF_ROW_SUB_LK:
                    dsp->acc = sub32(dsp, dsp->acc, extend_shift(dsp, immediate, shift_count), 0, 0);
                    break;
                case C5X_BF_ROW_AND_LK:
                    dsp->acc &= (uint32_t)immediate << shift_count;
                    break;
                case C5X_BF_ROW_OR_LK:
                    dsp->acc |= (uint32_t)immediate << shift_count;
                    break;
                case C5X_BF_ROW_XOR_LK:
                    dsp->acc ^= (uint32_t)immediate << shift_count;
                    break;
                }
            } else if (row == C5X_BF_ROW_SFTA) {
                /* SFTA: ACC >>= (shift_count + 1), sign per SXM. */
                shift_count = shift_count + 1;
                data = (int32_t)dsp->acc;
                dsp->acc = dsp->sxm ? (uint32_t)(data >> shift_count) : dsp->acc >> shift_count;
            } else {
                dsp->status = RUN_BADOP;
            }
        }
    }
}

/* High bytes 0xE0..0xFF: conditional branches/calls/returns and XC. */
static void exec_hi_e0_ff(C5x *dsp, uint16_t op) {
    uint16_t immediate;
    int n;
    int hi = op >> 8;
    if (hi >= C5X_OP_BCND_FIRST && hi <= C5X_OP_BCND_LAST) {
        /* BCND: branch if cond; C5X_COND_CLEAR_OV_BIT clears OV on the taken path. */
        immediate = fetch(dsp);
        if (branch_condition(dsp)) {
            dsp->pc = immediate;
            if (op & C5X_COND_CLEAR_OV_BIT) {
                dsp->ov = 0;
            }
        }
    } else if ((hi >= C5X_OP_XC_1_FIRST && hi <= C5X_OP_XC_1_LAST) ||
               (hi >= C5X_OP_XC_2_FIRST && hi <= C5X_OP_XC_2_LAST)) {
        /* XC: if the condition fails, skip n instruction WORDS
           (n = ((op>>12)&1) + 1; manual: n=2 is one 2-word or two
           1-word instructions).  XC does not touch OV (N-12).
           If it passes, XC and the two words following it are
           uninterruptible, whatever n (manual 6.3 XC). */
        if (!branch_condition(dsp)) {
            n = ((op >> C5X_XC_TWO_WORDS_BIT) & 1) + 1;
            dsp->pc = (uint16_t)(dsp->pc + n);
        } else {
            dsp->xc_left = 2;
            dsp->xc_new = 1;
        }
    } else if (hi >= C5X_OP_CC_FIRST && hi <= C5X_OP_CC_LAST) {
        /* CC: conditional call; bit 1 clears OV on the taken path. */
        immediate = fetch(dsp);
        if (branch_condition(dsp)) {
            push(dsp, dsp->pc);
            dsp->pc = immediate;
            if (op & C5X_COND_CLEAR_OV_BIT) {
                dsp->ov = 0;
            }
        }
    } else if (hi >= C5X_OP_RETC_FIRST && hi <= C5X_OP_RETC_LAST) {
        /* RETC: conditional return; no status bits affected (N-12). */
        if (branch_condition(dsp)) {
            dsp->pc = pop(dsp);
        }
    } else if (hi >= C5X_OP_BCNDD_FIRST && hi <= C5X_OP_BCNDD_LAST) {
        /* BCNDD: delayed conditional branch. */
        immediate = fetch(dsp);
        if (branch_condition(dsp)) {
            if (op & C5X_COND_CLEAR_OV_BIT) {
                dsp->ov = 0;
            }
            delay_slot(dsp, dsp->pc);
            dsp->pc = immediate;
        }
    } else if (hi >= C5X_OP_CCD_FIRST && hi <= C5X_OP_CCD_LAST) {
        /* CCD: delayed conditional call; return is pc+2. */
        immediate = fetch(dsp);
        if (branch_condition(dsp)) {
            push(dsp, (uint16_t)(dsp->pc + 2));
            if (op & C5X_COND_CLEAR_OV_BIT) {
                dsp->ov = 0;
            }
            delay_slot(dsp, dsp->pc);
            dsp->pc = immediate;
        }
    } else if (hi >= C5X_OP_RETCD_FIRST && hi <= C5X_OP_RETCD_LAST) {
        /* RETCD: delayed conditional return.  RETD: the slot runs
           first, then TOS -> PC and the stack is popped (6.3 RETD). */
        if (branch_condition(dsp)) {
            delay_slot(dsp, dsp->pc);
            dsp->pc = pop(dsp);
        }
    } else {
        dsp->status = RUN_BADOP;
    }
}

/* ------------------------------------------------------------------
   Main loop
   ------------------------------------------------------------------ */

/* Cycle-model charge for the instruction just executed.
   Returns the total machine-cycle count cy for the instruction; the
   caller adds cy - 1 because execute_one already charged the base cycle.
   Machine cycles come from the manual's tables (fastest case);
   repeated iterations cost 1, except repeated IN (2) and OUT (3).
   Taken conditional branches (BANZ/BCND/CC/RETC) cost 4, not-taken
   ones cost 2.  Sequencing is detected by comparing PC against
   ppc + words, except RETC/RET, where "taken" means the return
   address was popped (TOS may equal the fall-through address).
   QUIRK: the not-taken 2-cycle rule covers RETCD highs
   0xFC..0xFE (h >= 0xFC && h < 0xFF) -- 0xFF is NOT included.
   the two hi-byte range ladders below are a 256-entry
   class table instead (0 = no adjustment, 1 = conditional branch:
   4 cycles taken / 2 not-taken, 2 = not-taken-only 2 cycles).  The
   table is a literal transcription of the two ladders it replaces;
   the (rep_cont, seq) gating is unchanged. */
static const uint8_t cyc_adj[256] = {
    [C5X_OP_BANZ] = 1,

    /* BCND, CC and RETC */
    [C5X_OP_BCND_FIRST] = 1,
    [C5X_OP_BCND_FIRST + 1] = 1,
    [C5X_OP_BCND_FIRST + 2] = 1,
    [C5X_OP_BCND_LAST] = 1,
    [C5X_OP_CC_FIRST] = 1,
    [C5X_OP_CC_FIRST + 1] = 1,
    [C5X_OP_CC_FIRST + 2] = 1,
    [C5X_OP_CC_LAST] = 1,
    [C5X_OP_RETC_FIRST] = 1,
    [C5X_OP_RETC_FIRST + 1] = 1,
    [C5X_OP_RETC_FIRST + 2] = 1,
    [C5X_OP_RETC_LAST] = 1,

    /* RETCD, not-taken-only (2 cycles when sequential).  C5X_OP_RETCD_LAST is not
       included: the original table stops at 0xFE. */
    [C5X_OP_RETCD_FIRST] = 2,
    [C5X_OP_RETCD_FIRST + 1] = 2,
    [C5X_OP_RETCD_FIRST + 2] = 2,
};
static int instr_cycles(C5x *dsp, uint16_t ppc, int sp0) {
    uint8_t high_byte = (uint8_t)(dsp->opcode >> 8);
    int cycles;

    if (dsp->in_repeat) {
        cycles = high_byte == C5X_OP_IN ? 2 : high_byte == C5X_OP_OUT ? 3 : 1;
    } else {
        cycles = cycle_table[dsp->opcode];
    }

    /* Whether the next instruction is the one that follows in memory (no branch taken). */
    int sequential = (uint16_t)dsp->pc == (uint16_t)(ppc + dsp->words);
    if (high_byte >= C5X_OP_RETC_FIRST && high_byte <= C5X_OP_RETC_LAST) {
        sequential = dsp->sp == sp0;
    }

    if (!dsp->in_repeat) {
        uint8_t adjustment = cyc_adj[high_byte];

        if (adjustment == 1) {
            cycles = sequential ? 2 : 4; /* taken BANZ/BCND/CC/RETC: 4, not-taken: 2 */
        } else if (adjustment == 2 && sequential) {
            cycles = 2; /* not-taken conditional */
        }
    }
    return cycles;
}

/* Single-instruction RPT handling: if the instruction
   just executed was the repeated one (ppc == rpt_end) and repeats
   remain, rewind PC to rpt_start and count down; otherwise the
   repeat is over. */
static void handle_rpt(C5x *dsp, uint16_t ppc) {
    if (dsp->rptc > 0) {
        if (ppc == dsp->rpt_end) {
            dsp->pc = dsp->rpt_start;
            dsp->rptc--;
            dsp->in_repeat = 1;
        } else {
            dsp->in_repeat = 0;
        }
    } else {
        dsp->rptc = 0;
        dsp->in_repeat = 0;
    }
}

/* RPTB block-end test (manual 4.7): the last loop word
   has just executed (PC is already past it).  BRCR > 0: decrement and
   restart at PASR; BRCR == 0: leave the loop with BRCR still 0 and
   BRAF cleared.  Runs before the interrupt check so an ISR sees BRAF
   and the return address after the loop-end test. */
static void handle_braf(C5x *dsp) {
    if (dsp->braf && (uint16_t)(dsp->pc - 1) == dsp->paer) {
        if (dsp->brcr > 0) {
            dsp->pc = dsp->pasr;
            dsp->brcr--;
        } else {
            dsp->braf = 0;
        }
    }
}

/* Advance the on-chip timer by n machine cycles, in closed form.
   Exactly equivalent to calling tick_timer() n times (manual 9.4):
   the prescaler counts down from its current value and expires when
   it would go below 0 (so the first TIM step is psc+1 ticks away),
   then once every tddr+1 ticks; each prescaler expiry decrements TIM,
   except when TIM is 0, when TIM reloads from PRD, IFR's TINT bit is
   set and timer_exp counts one expiry.  The timer is frozen while
   TSS is set.  TIM needs t0+1 expiries for its first reload (t0 steps
   down to 0, then one more reloads it), and prd+1 expiries per reload
   after that. */
static void advance_timer(C5x *dsp, uint64_t n) {
    if (dsp->tss || n == 0) {
        return;
    }
    int64_t p0 = dsp->psc;
    int64_t first = p0 + 1; /* ticks to the next prescaler expiry */
    if (first < 1) {
        first = 1;
    }
    if ((uint64_t)first > n) {
        dsp->psc = (int)(p0 - (int64_t)n);
        return;
    }
    uint64_t tddr = (uint64_t)dsp->tcr_tddr;
    uint64_t rem = n - (uint64_t)first;
    /* Prescaler expiries in n ticks: one at `first`, then one every
       tddr+1 ticks.  Just after an expiry psc holds tddr. */
    uint64_t e = 1 + rem / (tddr + 1);
    dsp->psc = (int)(tddr - (rem % (tddr + 1)));
    uint64_t t0 = dsp->tim;
    if (e <= t0) {
        dsp->tim = (uint16_t)(t0 - e);
        return;
    }
    uint64_t e2 = e - (t0 + 1); /* expiries after the first reload */
    dsp->timer_exp += 1 + e2 / ((uint64_t)dsp->prd + 1);
    dsp->tim = (uint16_t)(dsp->prd - (e2 % ((uint64_t)dsp->prd + 1)));
    dsp->ifr |= (uint16_t)(1 << C5X_TINT);
}

/* Machine cycles until the next TINT expiry from the current timer
   state (timer running; callers check TSS first).  At least 1. */
static uint64_t timer_cycles_to_expiry(C5x *dsp) {
    int64_t first = (int64_t)dsp->psc + 1;
    if (first < 1) {
        first = 1;
    }
    /* Prescaler expiries still needed: TIM steps to 0, then one more
       reloads it and raises TINT (1 expiry when TIM is already 0). */
    uint64_t need = dsp->tim == 0 ? 1 : (uint64_t)dsp->tim + 1;
    return (uint64_t)first + (need - 1) * ((uint64_t)dsp->tcr_tddr + 1);
}

/* Run the timer once per machine cycle elapsed since c0.
   The closed-form advance above replaces the per-cycle loop.
   the wrapper is folded into its only caller
   (c5x_run), which now calls advance_timer() directly. */

/* Interrupt-hold accounting for this instruction.
   Returns 1 when interrupts must be held off after this instruction:
   the instruction after XC (xc_new), the remaining XC window
   (xc_left, counted in words), or the single-word instruction at the
   end of a repeat block (manual 4.7.2). */
static int interrupt_held(C5x *dsp) {
    int xc_hold = 0;
    if (dsp->xc_new) {
        dsp->xc_new = 0;
        xc_hold = 1;
    } else if (dsp->xc_left > 0) {
        dsp->xc_left -= dsp->words;
    }
    if (dsp->xc_left > 0) {
        xc_hold = 1;
    } else {
        dsp->xc_left = 0;
    }
    if (dsp->braf && dsp->pc == dsp->paer) {
        xc_hold = 1;
    }
    return xc_hold;
}

/* Apply the AR0 -> INDX/ARCR mirror (audit #10, manual 6.3 LAR/MAR/
   SAR): with NDX=0 ('C2x compatible, the reset state),
   anything that loads/modifies AR0 also loads INDX and ARCR. */
static void apply_ar0_mirror(C5x *dsp) {
    if (dsp->ar0_dirty) {
        if (!dsp->ndx) {
            dsp->indx = dsp->arcr = dsp->ar[0];
        }
        dsp->ar0_dirty = 0;
    }
}

/* ------------------------------------------------------------------
   RPTB block replay

   DESIGN.  The profiler (prof2) shows RPTB covering 47.53% of DSP
   instructions; the ov6/ov7 signal inner loops are the workload.
   A block is decoded once (block_decode) into a RptbBlock and replayed
   directly (block_replay) while the block repeats: the replay skips
   the per-instruction fetch, the diag branch, instr_cycles (the
   cycle charge is precomputed per entry), and the repeat/hold
   guard, but it executes the byte-identical family code through
   execute_opcode, and it runs the byte-identical per-instruction tail:
   apply_ar0_mirror, handle_braf, advance_timer (per instruction,
   NOT batched -- the division is overlapped, not on the critical
   path, and batching would need an expiry countdown plus a
   may-store catch-up), interrupt_held, the interrupt check with
   the exact baseline condition, and the stop check.  The cycle
   budget is honoured per entry (the replay never executes an
   instruction the main loop would not have, and an interrupt is
   taken before the budget check, exactly as in the main loop).

   EXACTNESS.  A replayed entry must execute exactly what the main
   loop would have executed, with the same state afterwards:
    - Validation: a cached decode is used only when its raw words
      still match program_read (per-call: validated_seq == run_seq, plus
      pm_epoch / bp_epoch / cycle_model), and it is re-decoded when
      they do not.  pm_epoch is bumped on every PM/mapping change
      (program_write, glue loads, LST #1, RCNF/SCNF, PMST writes, c5x_set
      ST1/PMST) and on every external data_write (unified memory).  A
      breakpoint anywhere in the block refuses the decode, and a
      breakpoint appearing later is caught by the bp_epoch check.
    - In-replay writes: MMR PMST/RPTC/BRCR/PASR/PAER writes and
      program_write set replay_dirty via block_state_changed; a data_write that
      lands on a block program word sets it via block_store_guard.
      The replay checks replay_dirty after every entry and breaks
      out (the entry that dirtied the block already executed
      correctly; only later entries could be stale).
    - RPT: allowed only when the next entry is an rptc-loop op
      (BLOCK_F_RPTC), which consumes rptc internally to -1; the replay
      clamps rptc to 0 afterwards, which is exactly handle_rpt's
      else branch.  A trailing RPT (consumer outside the block) is
      allowed: the consumer runs in the slow path after the loop.
      rep_cont stays 0 throughout the replay (handle_rpt is never
      needed: it could only set rep_cont = 0 here), so the cycle
      charge is cycle_table[op] and IN/OUT see rep_cont = 0, as in the
      baseline for a bare IN/OUT.  No cyc_adj entry applies: every
      opcode it covers is a branch, and all branches are excluded.
    - XC: allowed with skip handling -- after an XC entry the next
      entry is found by pc through idx_of, so a skip to another
      entry start continues in the block and a skip elsewhere (or
      past the block) breaks out to the slow path, which executes
      the skipped-to word as a fresh opcode exactly as the baseline
      would.  The XC uninterruptible window runs through the real
      interrupt_held, with words maintained per entry.
    - handle_braf runs after every entry (as in the main loop), so
      an XC skip landing on paer+1 triggers the block-end test
      exactly as the baseline does, and a rewind restarts the block
      from entry 0.  The quirk where an XC skip past paer+1 leaves
      braf set is preserved: the replay hands off to the slow path,
      which keeps the same braf state.
    - Interrupts: the check uses the live rptc / rep_cont / intm /
      ifr / imr, and check_int is the real one (with its 4-cycle
      tick_timer entry cost).  An interrupt taken mid-block breaks
      out to the main loop, which executes the ISR; the remainder
      of the interrupted iteration runs slow (58k in-block interrupts
      x ~11 instructions per 20 s -- negligible).  Mid-block re-entry
      after an ISR return is NOT supported and is not needed: the
      return lands on pasr only if the ISR returned there, and the
      main loop then re-enters through the normal hook.
    - diag: the replay requires !diag, so the Python .so / stats
      harness keeps exact per-instruction diagnostic counts (the C
      driver runs with diag off).
    - 2-word entries: the replay sets pc = ppc+1 and words = 1
      before execute_opcode, so the family's fetch() reads the second word
      at ppc+1 exactly as execute_one+fetch do; after the entry pc is
      ppc+words.  A 2-word entry straddling paer refuses the decode.
   ------------------------------------------------------------------ */

/* Classify one opcode word for block replay.  Returns the entry word
   count (1 or 2) and fills *flags; returns 0 when the opcode cannot
   replay.  The classification mirrors the exec_hi_* families exactly:
   every opcode they execute is either allowed here with its true
   word count and flags, or excluded.  Excluded: branches/calls/
   returns of every kind (incl. delayed), RPTB, the PM writers
   (SMMR/BLDP/TBLW), the mapping changers (LST #1, RCNF/SCNF),
   IDLE/IDLE2, EINT, NMI/INTR/TRAP, and the BADOP opcodes. */
static int block_classify(uint16_t op, uint8_t *flags) {
    uint8_t hi = (uint8_t)(op >> 8);
    uint8_t lo = (uint8_t)op;
    uint8_t entry_flags = 0;
    int words = 1;

    if (hi <= C5X_OP_LST1) {
        switch (hi) {
        case C5X_OP_SMMR:
            return 0; /* PM writer */
        case C5X_OP_RPT_DMA:
            entry_flags = BLOCK_F_RPT;
            break;
        case C5X_OP_OUT:
            words = 2;
            break; /* io_write only, not a data_write store */
        case C5X_OP_LST1:
            return 0; /* changes CNF */
        default:
            break; /* LAR, LAMM, SUBC, LDP, LST0 */
        }
    } else if (hi <= C5X_OP_SUB_SHIFT_LAST) {
        /* LACC / ADD / SUB with a shift: 1 word, no store, no branch. */
    } else if (hi <= C5X_OP_CPL_LK) {
        if (hi == C5X_OP_UNDEFINED_56) {
            return 0;
        }
        if (hi == C5X_OP_BLDP) {
            return 0; /* PM writer */
        }
        if (hi >= C5X_OP_XPL_DBMR && hi <= C5X_OP_APL_DBMR) {
            entry_flags = BLOCK_F_STORE;
        } else if (hi >= C5X_OP_XPL_LK && hi <= C5X_OP_APL_LK) {
            words = 2;
            entry_flags = BLOCK_F_STORE;
        } else if (hi == C5X_OP_CPL_LK) {
            words = 2; /* compares only, no write */
        }
        /* BIT, MPYA..MPYU and CPL dbmr: 1 word, no store. */
    } else if (hi <= C5X_OP_BANZD) {
        if (hi >= C5X_OP_B && hi <= C5X_OP_BANZ) {
            return 0; /* B, CALL, BANZ */
        }
        if (hi >= C5X_OP_BD) {
            return 0; /* BD, CALLD, BANZD */
        }
        /* 0x60-0x78 ALU, loads and ADRK, and SBRK: 1 word.  LTD and DMOV only use
           data_move_write (internal data memory, never a program-memory store). */
    } else if (hi <= C5X_OP_SACH_LAST) {
        if (hi <= C5X_OP_SAR_LAST || hi == C5X_OP_SAMM) {
            entry_flags = BLOCK_F_STORE;
        } else if (hi == C5X_OP_LMMR) {
            words = 2;
            entry_flags = BLOCK_F_STORE | BLOCK_F_RPTC;
        } else if (hi == C5X_OP_POPD) {
            entry_flags = BLOCK_F_STORE;
        } else if (hi == C5X_OP_SPL || hi == C5X_OP_SPH || hi == C5X_OP_SST0 || hi == C5X_OP_SST1) {
            entry_flags = BLOCK_F_STORE;
        } else if (hi >= C5X_OP_SACL_FIRST) {
            entry_flags = BLOCK_F_STORE; /* SACL, SACH */
        }
        /* MAR: no store. */
    } else if (hi <= C5X_OP_IN) {
        switch (hi) {
        case C5X_OP_NORM:
            break;
        case C5X_OP_UNDEFINED_A1:
            return 0;
        case C5X_OP_MAC:
        case C5X_OP_MACD:
            words = 2;
            entry_flags = BLOCK_F_RPTC;
            break;
        case C5X_OP_BLPD_BMAR:
            entry_flags = BLOCK_F_STORE | BLOCK_F_RPTC;
            break;
        case C5X_OP_BLPD_PMA:
            words = 2;
            entry_flags = BLOCK_F_STORE | BLOCK_F_RPTC;
            break;
        case C5X_OP_TBLR:
            entry_flags = BLOCK_F_STORE | BLOCK_F_RPTC;
            break;
        case C5X_OP_TBLW:
            return 0; /* PM writer */
        case C5X_OP_BLDD_LK_DMA:
        case C5X_OP_BLDD_DMA_LK:
            words = 2;
            entry_flags = BLOCK_F_STORE | BLOCK_F_RPTC;
            break;
        case C5X_OP_MADS:
        case C5X_OP_MADD:
            entry_flags = BLOCK_F_RPTC;
            break; /* 1 word */
        case C5X_OP_BLDD_BMAR_DMA:
        case C5X_OP_BLDD_DMA_BMAR:
            entry_flags = BLOCK_F_STORE | BLOCK_F_RPTC;
            break;
        case C5X_OP_SPLK:
        case C5X_OP_IN:
            words = 2;
            entry_flags = BLOCK_F_STORE;
            break;
        }
    } else if (hi <= C5X_OP_GROUP_BF) {
        if (hi <= C5X_OP_LAR_K8_LAST) {
            /* LAR #k8: 1 word */
        } else if (hi == C5X_OP_ADDK || hi == C5X_OP_LACK || hi == C5X_OP_SUBK) {
            /* 1 word */
        } else if (hi == C5X_OP_RPT_K8) {
            entry_flags = BLOCK_F_RPT;
        } else if (hi >= C5X_OP_LDP_K9_FIRST && hi <= C5X_OP_LDP_K9_LAST) {
            /* LDP #k9: 1 word */
        } else if (hi == C5X_OP_GROUP_BE) {
            if (lo < C5X_BE_CONTROL_FIRST) {
                switch (lo) {
                case C5X_BE_ABS:
                case C5X_BE_CMPL:
                case C5X_BE_NEG:
                case C5X_BE_PAC:
                case C5X_BE_APAC:
                case C5X_BE_SPAC:
                case C5X_BE_SFL:
                case C5X_BE_SFR:
                case C5X_BE_ROL:
                case C5X_BE_ROR:
                case C5X_BE_ADDB:
                case C5X_BE_ADCB:
                case C5X_BE_ANDB:
                case C5X_BE_ORB:
                case C5X_BE_ROLB:
                case C5X_BE_RORB:
                case C5X_BE_SFLB:
                case C5X_BE_SFRB:
                case C5X_BE_SUBB:
                case C5X_BE_SBBB:
                case C5X_BE_XORB:
                case C5X_BE_CRGT:
                case C5X_BE_CRLT:
                case C5X_BE_EXAR:
                case C5X_BE_SACB:
                case C5X_BE_LACB:
                    break; /* accumulator operations (exec_be_acc) */
                default:
                    return 0; /* undefined */
                }
            } else {
                switch (lo) {
                case C5X_BE_POP:
                case C5X_BE_PSHA:
                case C5X_BE_DINT:
                case C5X_BE_ROVM:
                case C5X_BE_SOVM:
                case C5X_BE_RSXM:
                case C5X_BE_SSXM:
                case C5X_BE_RHM:
                case C5X_BE_SHM:
                case C5X_BE_RTC:
                case C5X_BE_STC:
                case C5X_BE_RXF:
                case C5X_BE_SXF:
                case C5X_BE_RCB:
                case C5X_BE_SCB:
                case C5X_BE_ZPR:
                case C5X_BE_ZAP:
                case C5X_BE_SATH:
                case C5X_BE_SATL:
                    break; /* flag and status operations: no store, no branch */
                case C5X_BE_MPY_LK:
                case C5X_BE_AND_LK_16:
                case C5X_BE_OR_LK_16:
                case C5X_BE_XOR_LK_16:
                    words = 2;
                    break;
                case C5X_BE_RPT_LK:
                case C5X_BE_RPTZ_LK:
                    words = 2;
                    entry_flags = BLOCK_F_RPT;
                    break;
                default:
                    /* BACC, BACCD, IDLE, CALA, RETI, RETE, CALAD, EINT, RCNF, SCNF, TRAP, NMI,
                       RPTB, INTR and the undefined opcodes cannot replay. */
                    return 0;
                }
            }
        } else { /* C5X_OP_GROUP_BF */
            if (lo <= C5X_BF_SPM_LAST) {
                /* SPM: 1 word */
            } else if (lo >= C5X_BF_LAR_LK_FIRST && lo <= C5X_BF_LAR_LK_LAST) {
                words = 2;
            } else if (lo >= C5X_BF_CMPR_FIRST && lo <= C5X_BF_CMPR_LAST) {
                /* CMPR: 1 word */
            } else {
                int row = lo & C5X_BF_ROW_MASK;

                if (row >= C5X_BF_ROW_LK_FIRST && row <= C5X_BF_ROW_LK_LAST) {
                    words = 2; /* long-immediate ALU */
                } else if (row == C5X_BF_ROW_SFTA) {
                    /* 1 word */
                } else {
                    return 0;
                }
            }
        }
    } else if (hi <= C5X_OP_MPY_K13_LAST) {
        /* MPY #k13: 1 word. */
    } else {
        /* 0xE0-0xFF: only XC replays; every other form branches. */
        if ((hi >= C5X_OP_XC_1_FIRST && hi <= C5X_OP_XC_1_LAST) ||
            (hi >= C5X_OP_XC_2_FIRST && hi <= C5X_OP_XC_2_LAST)) {
            entry_flags = BLOCK_F_XC;
        } else {
            return 0; /* BCND, CC, RETC, BCNDD, CCD, RETCD */
        }
    }
    *flags = entry_flags;
    return words;
}

/* Decode the block [pasr, paer] into block (fresh words via program_read).
   Returns 1 on success, 0 when the block cannot replay.  On success
   the epochs/validation stamp are recorded. */
static int block_decode(C5x *dsp, RptbBlock *block, uint16_t pasr, uint16_t paer) {
    uint16_t len = (uint16_t)(paer - pasr + 1);
    int n = 0;
    int i;
    if (len < 1 || len > BLOCK_MAX_WORDS) {
        return 0;
    }
    for (i = 0; i < len; i++) {
        block->words[i] = program_read(dsp, (uint16_t)(pasr + i));
        block->idx_of[i] = 0xFF;
        if (dsp->breakpoints[pasr + i]) {
            return 0; /* a breakpoint inside the block: stay slow */
        }
    }
    uint16_t off = 0;
    while (off < len) {
        uint16_t pc = (uint16_t)(pasr + off);
        uint8_t flags = 0;
        int w = block_classify(block->words[off], &flags);
        if (w == 0) {
            return 0;
        }
        if (off + w > len) {
            return 0; /* a 2-word entry straddling paer */
        }
        if (n >= BLOCK_MAX_ENT) {
            return 0;
        }
        block->idx_of[off] = (uint8_t)n;
        block->e[n].pc = pc;
        block->e[n].opcode = block->words[off];
        block->e[n].cy = dsp->cycle_model ? cycle_table[block->words[off]] : 1;
        block->e[n].flags = flags;
        n++;
        off = (uint16_t)(off + w);
    }
    /* An RPT entry must be followed by an rptc-loop consumer (the
       only repeat form the replay implements); a trailing RPT is
       allowed, its consumer runs in the slow path after the loop. */
    for (i = 0; i < n; i++) {
        if ((block->e[i].flags & BLOCK_F_RPT) && i + 1 < n && !(block->e[i + 1].flags & BLOCK_F_RPTC)) {
            return 0;
        }
    }
    block->pasr = pasr;
    block->paer = paer;
    block->n = (uint16_t)n;
    block->epoch = dsp->pm_epoch;
    block->bp_epoch = dsp->bp_epoch;
    block->validated_seq = dsp->run_seq;
    block->cycle_model = dsp->cycle_model;
    return 1;
}

/* Find (decoding / validating as needed) the cached block for the
   RPTB loop the main loop has just entered (braf set, pc == pasr).
   Returns NULL when the block cannot replay.  Validation is
   per-call (run_seq) plus the epochs, so a PM change through any
   route -- including a data_write to external unified memory, which
   bumps pm_epoch in data_write -- is caught at the next lookup, and a
   dirty break-out forces re-validation even within the same call. */
static RptbBlock *block_lookup(C5x *dsp) {
    uint16_t pasr, paer;
    RptbBlock *block;
    if (dsp->rptc != 0 || dsp->in_repeat || dsp->xc_new || dsp->xc_left != 0 || dsp->interrupt_inhibit || dsp->idle ||
        dsp->stop || dsp->diag) {
        return NULL;
    }
    pasr = dsp->pasr;
    paer = dsp->paer;
    if ((uint16_t)(paer - pasr + 1) > BLOCK_MAX_WORDS) {
        return NULL;
    }
    block = dsp->block_cache[pasr & (BLOCK_CACHE_N - 1)];
    if (!block) {
        block = (RptbBlock *)calloc(1, sizeof(RptbBlock));
        if (!block) {
            return NULL;
        }
        dsp->block_cache[pasr & (BLOCK_CACHE_N - 1)] = block;
    }
    if (block->pasr == pasr && block->paer == paer && block->n > 0) {
        if (block->validated_seq == dsp->run_seq && block->epoch == dsp->pm_epoch && block->bp_epoch == dsp->bp_epoch &&
            block->cycle_model == dsp->cycle_model && !dsp->replay_dirty) {
            return block;
        }
        /* Something changed since the decode: re-validate the words
           (and the breakpoint scan), then keep the decode if they
           still match; otherwise fall through to a fresh decode. */
        uint16_t len = (uint16_t)(paer - pasr + 1);
        int ok = 1;
        uint16_t k;
        for (k = 0; k < len; k++) {
            if (program_read(dsp, (uint16_t)(pasr + k)) != block->words[k]) {
                ok = 0;
                break;
            }
        }
        if (ok) {
            for (k = 0; k < len; k++) {
                if (dsp->breakpoints[pasr + k]) {
                    ok = 0;
                    break;
                }
            }
        }
        if (ok) {
            if (block->cycle_model != dsp->cycle_model) {
                /* Cycle model toggled since the decode: refresh the
                   per-entry charges, else the replay would charge
                   the stale model (cannot fire in the shipped driver — the only
                   c5x_set_cycle_model caller is setup — but an
                   out-of-tree .so user could toggle it). */
                for (k = 0; k < block->n; k++) {
                    block->e[k].cy = dsp->cycle_model ? cycle_table[block->e[k].opcode] : 1;
                }
                block->cycle_model = dsp->cycle_model;
            }
            block->epoch = dsp->pm_epoch;
            block->bp_epoch = dsp->bp_epoch;
            block->validated_seq = dsp->run_seq;
            return block;
        }
    }
    if (!block_decode(dsp, block, pasr, paer)) {
        return NULL;
    }
    return block;
}

/* Replay a validated block.  Returns BLOCK_CONT (resume the main loop),
   RUN_STOP, or RUN_BADOP.  The per-entry tail is the main loop's
   tail, in the same order, with the same functions: apply_ar0_mirror,
   the rptc clamp (handle_rpt's else branch, the only part that can
   fire here), handle_braf, advance_timer over the entry's exact
   cycles, interrupt_held, the interrupt check, and the stop check.
   The budget check follows the interrupt check, as in the main loop
   (an interrupt pending at the budget end is still taken). */
static int block_replay(C5x *dsp, RptbBlock *block, uint64_t end) {
    int i = 0;
    dsp->replay_active = 1;
    dsp->replay_dirty = 0;
    dsp->replay_lo = block->pasr;
    dsp->replay_hi = block->paer;
    for (;;) {
        RptbEntry *e = &block->e[i];
        uint16_t ppc = e->pc;
        uint64_t c0 = dsp->cycles;
        int held;
        dsp->cur_pc = ppc;
        dsp->opcode = e->opcode;
        dsp->pc = (uint16_t)(ppc + 1);
        dsp->words = 1;
        dsp->cycles += e->cy;
        execute_opcode(dsp, e->opcode);
        if (dsp->status == RUN_BADOP) {
            dsp->pc = ppc;
            dsp->replay_active = 0;
            return RUN_BADOP;
        }
        apply_ar0_mirror(dsp);
        if ((e->flags & BLOCK_F_RPTC) && dsp->rptc < 0) {
            dsp->rptc = 0;
        }
        handle_braf(dsp);
        advance_timer(dsp, dsp->cycles - c0);
        held = interrupt_held(dsp);
        if (dsp->interrupt_inhibit) {
            dsp->interrupt_inhibit = 0;
        } else if (!held && dsp->rptc <= 0 && !dsp->in_repeat && !dsp->intm && (dsp->ifr & dsp->imr)) {
            check_int(dsp);
        }
        if (dsp->stop) {
            dsp->replay_active = 0;
            return RUN_STOP;
        }
        if (dsp->cycles >= end) {
            dsp->replay_active = 0;
            return BLOCK_CONT;
        }
        if (dsp->replay_dirty) {
            dsp->replay_active = 0;
            return BLOCK_CONT;
        }
        if (!dsp->braf) {
            dsp->replay_active = 0;
            return BLOCK_CONT;
        }
        /* Next entry by pc: straight-line, a handle_braf rewind to
           pasr, or an XC skip to another entry start.  Any other pc
           leaves the block (the slow path executes the skipped-to
           word as a fresh opcode, exactly as the baseline would). */
        {
            uint16_t off = (uint16_t)(dsp->pc - dsp->pasr);
            uint8_t j;
            if (off > (uint16_t)(dsp->paer - dsp->pasr)) {
                dsp->replay_active = 0;
                return BLOCK_CONT;
            }
            j = block->idx_of[off];
            if (j == 0xFF) {
                dsp->replay_active = 0;
                return BLOCK_CONT;
            }
            i = j;
        }
    }
}

/* Run until the cycle budget is exhausted.  Returns RUN_OK, RUN_BP,
   RUN_BADOP, or RUN_STOP. */
int c5x_run(C5x *dsp, uint64_t budget) {
    uint64_t cycle_limit = dsp->cycles + budget;
    int is_first_instruction = 1;
    dsp->stop = 0;
    dsp->status = RUN_OK;
    dsp->run_seq++; /* per-call validation stamp for the block cache */
    while (dsp->cycles < cycle_limit) {
        uint64_t cycles_at_start = dsp->cycles;
        if (dsp->idle) {
            /* IDLE2 (idle == 2) wakes only on INT1-4 (IFR/IMR bits
               0,1,2,8 = mask 0x107); IDLE wakes on any unmasked
               interrupt. */
            uint16_t wake = (uint16_t)(dsp->idle == 2 ? 0x107 : 0xFFFF);
            if (dsp->ifr & dsp->imr & wake) {
                dsp->idle = 0;
                check_int(dsp);
                continue;
            }
            /* Fast-forward: nothing else can change IFR while idle
               (interrupts and serial ticks arrive only between
               c5x_run calls), so the only event before the budget
               ends is a timer expiry -- and only if TINT is unmasked
               (otherwise the timer still advances, but the DSP
               sleeps through its expiries).  The timer state is
               advanced in closed form by advance_timer(), which is
               exactly equivalent to one tick_timer() per cycle, so
               timer expiries, IFR/TINT, idle_cycles and the
               interrupt-entry cycle are all preserved. */
            uint64_t remain = cycle_limit - dsp->cycles;
            if (dsp->idle == 2 || dsp->tss) {
                /* IDLE2 stops the timer; a stopped timer never
                   ticks, and no wake can arrive before the budget
                   ends. */
                dsp->cycles = cycle_limit;
                dsp->idle_cycles += remain;
                continue;
            }
            if (dsp->imr & (uint16_t)(1 << C5X_TINT)) {
                /* Jump to the next TINT expiry (or the budget cycle_limit,
                   whichever comes is_first_instruction); the loop top then takes
                   the interrupt at exactly the expiry cycle. */
                uint64_t cycles_to_expiry = timer_cycles_to_expiry(dsp);
                uint64_t step = cycles_to_expiry < remain ? cycles_to_expiry : remain;
                advance_timer(dsp, step);
                dsp->cycles += step;
                dsp->idle_cycles += step;
            } else {
                /* TINT masked: sleep through every expiry to the
                   budget cycle_limit; the timer still counts them. */
                advance_timer(dsp, remain);
                dsp->cycles = cycle_limit;
                dsp->idle_cycles += remain;
            }
            continue;
        }
        if (dsp->breakpoints[dsp->pc] && !is_first_instruction) {
            dsp->status = RUN_BP;
            return RUN_BP;
        }
        is_first_instruction = 0;
        dsp->status = RUN_OK;
        uint16_t start_pc = dsp->pc;
        dsp->words = 0;
        int sp_at_start = dsp->sp;
        execute_one(dsp);
        if (dsp->cycle_model) {
            dsp->cycles += (uint64_t)(instr_cycles(dsp, start_pc, sp_at_start) - 1);
        }
        apply_ar0_mirror(dsp);
        if (dsp->status == RUN_BADOP) {
            dsp->pc = start_pc;
            return RUN_BADOP;
        }
        /* The three repeat/hold helpers share one cheap guard.  handle_rpt, handle_braf and
           interrupt_held are each almost always a no-op, but each
           costs its own tests (and handle_rpt's else branch stores
           rptc = 0 / rep_cont = 0 on every instruction).  The guard
           is exact, not heuristic: when rptc == 0 and rep_cont == 0
           handle_rpt's else branch would store the values already
           there; when braf == 0 handle_braf does nothing; when
           xc_new == 0, xc_left == 0 and braf == 0 interrupt_held
           returns 0 and stores xc_left = 0, the value already there.
           (rptc must be == 0, not <= 0: block instructions can leave
           rptc == -1, and only the slow path clamps it to 0.)
           Measured in a scratch instrumented build (20 s call): the
           guard is true for 354.3M of 583.5M loop iterations
           (60.7%); braf is set for 35.9%, rptc > 0 for 1.9%,
           xc active for 2.3%.  The slow path keeps this
           order (rpt, braf, timer, held). */
        int rep_fast = (dsp->rptc == 0 && !dsp->in_repeat && !dsp->braf && !dsp->xc_new && dsp->xc_left == 0);
        if (!rep_fast) {
            handle_rpt(dsp, start_pc);
            handle_braf(dsp);
        }
        /* Advance the timer by the cycles this instruction took. */
        advance_timer(dsp, dsp->cycles - cycles_at_start);
        int held = rep_fast ? 0 : interrupt_held(dsp);
        /* A single-instruction RPT repeat is not interruptible on the
           real C5x.  EINT's one-cycle inhibit (interrupt_inhibit)
           is consumed here whether or not an interrupt was pending.
           The check_int() fast path (masked off, or nothing pending)
           is inlined: it fires on ~92% of instructions. */
        if (dsp->interrupt_inhibit) {
            dsp->interrupt_inhibit = 0;
        } else if (held)
            ;
        else if (dsp->rptc <= 0 && !dsp->in_repeat && !dsp->intm && (dsp->ifr & dsp->imr)) {
            check_int(dsp);
        }
        if (dsp->stop) {
            return RUN_STOP;
        }
        /* RPTB block replay.  Fires when the slow path
           has just executed RPTB (braf set, pc at the block start) or
           an ISR returned there.  Only when budget remains: the
           replay's per-entry budget check then guarantees it never
           executes an instruction the main loop would not have. */
        if (dsp->braf && dsp->pc == dsp->pasr && !dsp->diag && dsp->cycles < cycle_limit) {
            RptbBlock *block = block_lookup(dsp);
            if (block) {
                int replay_status = block_replay(dsp, block, cycle_limit);
                if (replay_status != BLOCK_CONT) {
                    return replay_status;
                }
            }
        }
    }
    return RUN_OK;
}

/* Serial-port frame tick: one codec sample period elapsed.
   rx = ADC sample delivered to DRR. */
void c5x_serial_tick(C5x *dsp, int16_t rx) {
    if (dsp->spc & SPC_RRST_BIT) { /* receiver enabled (RRST=1) */
        /* Previous word not read before the next one arrived:
           overrun; the receiver halts until DRR is read, the new
           word is lost (manual 9.7). */
        if (dsp->rrdy || dsp->rsrfull) {
            dsp->rsrfull = 1;
        } else {
            /* DLB: DX looped back to DR. */
            dsp->drr = (dsp->spc & SPC_DLB_BIT) ? dsp->dxr : (uint16_t)rx;
            dsp->rrdy = 1;
            dsp->ifr |= (uint16_t)(1 << C5X_RINT);
        }
    }
    if (dsp->spc & SPC_XRST_BIT) {    /* transmitter enabled (XRST=1) */
        int dxr_pending = !dsp->xrdy; /* DXR written since the last frame */
        if (!dxr_pending) {
            dsp->xsrempty = 0; /* underflow */
        }
        dsp->xrdy = 1;
        /* XINT: legacy = every tick; mode 1 = only after a DXR write
           (plus one initial kick). */
        if (!dsp->xint_mode || dxr_pending || dsp->xint_first) {
            dsp->ifr |= (uint16_t)(1 << C5X_XINT);
            dsp->xint_first = 0;
        }
    }
}

/* ------------------------------------------------------------------
   Remaining exported API: switches, counters, diagnostics
   ------------------------------------------------------------------ */

void c5x_set_xint_mode(C5x *dsp, int m) {
    dsp->xint_mode = m;
    dsp->xint_first = 1;
}
void c5x_set_cycle_model(C5x *dsp, int m) {
    dsp->cycle_model = m;
}
/* Diagnostics gate: 0 = skip the per-instruction / per-access counters
   listed at the `diag` field (default 1 = on, the historical behaviour).
   The C driver disables them; the .so / ctypes ABI is unchanged. */
void c5x_set_diag(C5x *dsp, int on) {
    dsp->diag = on ? 1 : 0;
}
/* API stub: nothing reads `legacy` any more. */
void c5x_set_legacy(C5x *dsp, int m) {
    dsp->legacy = m;
}
uint64_t c5x_idle_cycles(C5x *dsp) {
    return dsp->idle_cycles;
}
/* TIM reached 0 (TOUT pulses): the board's host heartbeat (INT0,
   2401 Hz measured) follows these. */
uint64_t c5x_timer_expiries(C5x *dsp) {
    return dsp->timer_exp;
}
uint64_t c5x_total_cycles(C5x *dsp) {
    return dsp->cycles;
}

void c5x_set_ivec_ind(C5x *dsp, int bit, uint16_t daddr) {
    dsp->ivec_ind[bit] = daddr;
}

void c5x_set_cmpr_ar0(C5x *dsp, int v) {
    dsp->cmpr_ar0 = v;
}

uint32_t c5x_dxr_head(C5x *dsp) {
    return dsp->dxr_head;
}
uint16_t *c5x_dxr_ring(C5x *dsp) {
    return dsp->dxr_ring;
}

void c5x_set_watch(C5x *dsp, int32_t a) {
    dsp->watch_a = a;
    memset(dsp->watch_hits, 0, sizeof dsp->watch_hits);
}
uint32_t c5x_watch_hits(C5x *dsp, uint32_t pc) {
    return dsp->watch_hits[pc & 0xFFFF];
}
uint32_t c5x_pc_hits(C5x *dsp, uint32_t pc) {
    return dsp->pc_hits[pc & 0xFFFF];
}
void c5x_pc_hits_clear(C5x *dsp) {
    memset(dsp->pc_hits, 0, sizeof dsp->pc_hits);
    memset(dsp->dmw_n, 0, sizeof dsp->dmw_n);
}
uint32_t c5x_dm_writes(C5x *dsp, uint32_t a) {
    return dsp->dmw_n[a & 0xFFFF];
}
void c5x_set_trace(C5x *dsp, int32_t pc) {
    dsp->trace_pc = pc;
    dsp->trace_n = 0;
}
uint32_t c5x_trace_n(C5x *dsp) {
    return dsp->trace_n;
}
void c5x_trace_get(C5x *dsp, uint32_t i, uint32_t *acc, uint16_t *ret, uint16_t *ret2) {
    *acc = dsp->trace_buf[i].acc;
    *ret = dsp->trace_buf[i].ret;
    *ret2 = dsp->trace_buf[i].ret2;
}

uint32_t c5x_mmr_count(C5x *dsp, int wr, int a) {
    return dsp->mmr_n[wr][a];
}
uint16_t c5x_mmr_pc(C5x *dsp, int wr, int a) {
    return dsp->mmr_pc[wr][a];
}
void c5x_mmr_clear(C5x *dsp) {
    memset(dsp->mmr_n, 0, sizeof dsp->mmr_n);
}
uint16_t c5x_mmr_val(C5x *dsp, int a) {
    return dsp->mmr_val[a];
}
uint32_t c5x_ff_count(C5x *dsp, int wr, int i) {
    return dsp->ff_n[wr][i & 255];
}
uint32_t c5x_ext_count(C5x *dsp, int wr, int block) {
    return dsp->ext_n[wr][block];
}
uint16_t c5x_rsv(C5x *dsp, int w) {
    return w ? dsp->rsv_pc : dsp->rsv_a;
}
