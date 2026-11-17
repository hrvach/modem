/* TMS320C5x (C51 flavour) instruction-set emulator -- readable rewrite.
 *
 * Written for the SV25 firmware study.  Semantics follow the TI C5x User's
 * Guide (SPRU056D); MAME's tms320c5x core (BSD-3, Ville Linde) was used as
 * a cross-reference where it is implemented (it stubs ~70 ops, which this
 * firmware uses heavily).
 *
 * Firmware source of truth: SV25.XMD (524,416 bytes, SHA-256
 * 43503d82caae5377d67c61f4f44d73e6a19e15c61b2cb706a70c6f1b88ef413f),
 * decoded with handover-2-2026-11-15/handover/tools/sv25_decode.py
 * (rolling-XOR, flash addr = file offset + 0x80) to a 524,288-byte image,
 * SHA-256 f24633ab12c21c3cef93c0f6c0bb8150021b0056953cb5517a95932abc673c52.
 * This core never patches firmware; it only executes the image it is given.
 *
 * This file is a line-for-line behaviour-preserving rewrite of
 * modem/dsp/c5x_core.c (691 lines).  The only intentional changes are
 * presentation: named constants instead of magic numbers, small functions,
 * and comments.  Where the original preserves a quirk, the comment cites
 * the original line number ("orig L<n>") and, where known, the manual
 * section or audit note.  Nothing was added, removed, or reordered.
 *
 * Build: gcc -O2 -shared -fPIC -o libc5x.so c5x_core.c
 *        gcc -O2 -Wall -Wextra -c -I. src/dsp/c5x_core.c   (standalone check)
 *
 * The cycle table (c5x_cyctab.h) is generated data from gen_cyctab.py,
 * copied verbatim from modem/dsp/c5x_cyctab.h; do not hand-edit it.
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "c5x_core.h"
#include "c5x_cyctab.h" /* static const uint8_t cyc_tab[65536]; generated data */

/* ------------------------------------------------------------------ */
/* Named constants (magic values from the original, kept in comments) */
/* ------------------------------------------------------------------ */

#define IOLOG_N 65536          /* I/O log capacity (orig: 65536 entries) */
#define PC_RING_N 256          /* recent-PC ring size */
#define TRACE_N 8192           /* trace-buffer capacity */
#define DXR_RING_N 65536       /* DXR write ring size (wraps at 0xFFFF) */
#define STACK_N 8              /* 8-deep hardware stack */
#define N_AR 8                 /* auxiliary registers AR0..AR7 */
#define N_MMR 0x60             /* memory-mapped registers, data 0x00..0x5F */
#define N_INT 9                /* interrupt sources INT1..INT4 (bits 0..8) */

/* Data-space regions (manual ch. 8; see dm_internal()). */
#define DM_B2_END 0x80         /* B2 block: 0x60..0x7F (0x00..0x5F are MMRs) */
#define DM_B0_START 0x100      /* B0/B1 blocks: 0x100..0x4FF */
#define DM_B0_END 0x500
#define DM_B0_CNF_END 0x300    /* with CNF=1, B0 (0x100..0x2FF) leaves data space */
#define DM_SARAM_START 0x800   /* SARAM: 0x800..0xBFF, data space only if OVLY=1 */
#define DM_SARAM_END 0xC00
#define DM_RSV_START 0x500     /* reserved range 0x500..0x7FF (diagnostic only) */
#define DM_RSV_END 0x800
#define DM_FF_START 0xFF00     /* 0xFFxx page (diagnostic counters) */
#define DM_HOSTWIN_START 0xFF50 /* external host window 0xFF50..0xFF5F */
#define DM_HOSTWIN_END 0xFF5F
#define DM_MMR_END 0x60        /* MMRs live at data 0x00..0x5F */
#define DM_PERIPH_START 0x20   /* peripheral MMRs 0x20..0x4F cost a bus cycle */
#define DM_PERIPH_END 0x50

/* Program-space overlays (pm_ptr()). */
#define PM_B0_START 0xFE00     /* with CNF=1, program 0xFE00.. maps to data B0 */
#define PM_SARAM_START 0x2000  /* with RAM=1, program 0x2000..0x23FF maps to SARAM */
#define PM_SARAM_END 0x2400

/* Status-register bit positions (manual ch. 3). */
#define ST0_ARP_SHIFT 13
#define ST0_OV_BIT 12
#define ST0_OVM_BIT 11
#define ST0_INT_BIT 10         /* hardwired 1 in ST0 reads (orig L~112) */
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

/* Interrupt-vector table offsets (manual 8.2.2; orig L314). */
#define IVEC_RSVD 0x00         /* vectors 9..15 are unused (0) */

/* Serial port control (SPC, data 0x22; manual Table 9-13). */
#define SPC_RRST_BIT 0x80      /* receiver reset/enable */
#define SPC_XRST_BIT 0x40      /* transmitter reset/enable */
#define SPC_DLB_BIT 0x02       /* digital loopback: DXR feeds DRR */
#define SPC_WRITABLE_MASK 0xC0FE /* writable SPC bits; 13..8 and bit 0 are status */
#define SPC_RSRFULL_BIT 13
#define SPC_XSREMPTY_BIT 12
#define SPC_XRDY_BIT 11
#define SPC_RRDY_BIT 10

/* Timer control (TCR, data 0x26; manual 9.4). */
#define TCR_PSC_SHIFT 6
#define TCR_TSS_BIT 4
#define TCR_TRB_BIT 0x20       /* reload TIM from PRD and PSC from TDDR */
#define TCR_TDDR_MASK 0x0F

/* Wait-state registers (manual 9.4.2/9.4.3). */
#define CWSR_BIG_BIT 4         /* CWSR bit 4: large (8K) vs small (128-word) pages */

/* ------------------------------------------------------------------ */
/* RPTB block replay (PERF2 stage 3): decoded-block cache.  See        */
/* blk_replay() for the design and the exactness argument.  A BlkDec   */
/* holds one RPTB block's body decoded once: the opcode word, the      */
/* cycle-model charge (cycm[op], or 1 when the cycle model is off),    */
/* and the replay-relevant flags per entry, plus a copy of the raw     */
/* words for validation.  At most BLK_MAX_WORDS words / BLK_MAX_ENT    */
/* entries per block; longer blocks simply do not replay.              */
/* ------------------------------------------------------------------ */
#define BLK_CACHE_N 64
#define BLK_MAX_WORDS 128
#define BLK_MAX_ENT 128
#define BLK_CONT 0     /* blk_replay: resume the main loop (block done / left) */
#define BLK_F_STORE 1  /* entry may call dm_wr with an arbitrary address */
#define BLK_F_RPTC  2  /* entry is an rptc-loop op: may leave rptc == -1 */
#define BLK_F_RPT   4  /* entry is RPT/RPTZ/RPT-dma: sets rptc */
#define BLK_F_XC    8  /* entry is XC: may skip 1-2 words */
typedef struct { uint16_t pc, op, cy; uint8_t flags; } BlkEnt;
typedef struct BlkDec {
    uint16_t pasr, paer;
    uint16_t n;                /* entries in e[] */
    uint64_t epoch;            /* pm_epoch at decode / last validation */
    uint64_t bp_epoch;         /* bp_epoch at decode / last validation */
    uint64_t validated_seq;    /* run_seq at last validation */
    int cyc_model;             /* cyc_model at decode */
    uint16_t words[BLK_MAX_WORDS];   /* raw block words, for validation */
    uint8_t idx_of[BLK_MAX_WORDS];   /* word offset -> entry index, 0xFF = none */
    BlkEnt e[BLK_MAX_ENT];
} BlkDec;

/* ------------------------------------------------------------------ */
/* Core state                                                          */
/* ------------------------------------------------------------------ */

struct C5x {
    /* Datapath. */
    uint32_t acc, accb, preg;          /* 32-bit accumulator, ACCB, product reg */
    uint16_t treg0, treg1, treg2;      /* temporary registers */
    uint16_t ar[N_AR];                 /* auxiliary registers */
    int arp, arb;                      /* current / auxiliary-reg pointer (ST0/ST1) */
    int dp;                            /* data-page pointer, already << 7 */
    int ov, ovm, intm, cnf, tc, sxm, c, hm, xf, pm;
    int iptr, avis, ovly, ram, mpmc, ndx, trm, braf;
    uint16_t pc, op;                   /* program counter, current opcode */
    uint16_t stack[STACK_N];
    int sp;                            /* stack pointer (0..7, grows down) */
    int32_t rptc;                      /* repeat counter (RPT/RPTB state) */
    uint16_t rpt_start, rpt_end;       /* single-instruction repeat window */
    uint16_t ifr, imr;                 /* interrupt flag / mask registers */
    uint16_t indx, arcr;               /* index / AR compare registers */
    uint16_t cbsr1, cber1, cbsr2, cber2, cbcr; /* circular-buffer regs */
    uint16_t bmar, dbmr, pasr, paer;   /* block-move / repeat-block regs */

    /* Diagnostics: MMR / external / 0xFFxx access counts and last values. */
    uint32_t mmr_n[2][N_MMR];          /* [read/write][addr] access counts */
    uint16_t mmr_pc[2][N_MMR];         /* PC of last access */
    uint16_t mmr_val[N_MMR];           /* first-written value (see mmr_wr) */
    uint32_t ext_n[2][64];             /* external accesses per 1K block */
    uint32_t ff_n[2][256];             /* 0xFFxx accesses per low byte */
    uint16_t rsv_a, rsv_pc;            /* last reserved-range (0x500..0x7FF) access */
    int32_t brcr;                      /* block-repeat counter (RPTB) */
    uint16_t io_rep;                   /* IN/OUT port increment under RPT */
    int xc_left, xc_new;               /* XC uninterruptible-window countdown */

    /* On-chip peripherals. */
    uint16_t greg, drr, dxr, spc, tim, prd, tcr_tddr, pdwsr, iowsr, cwsr;
    int psc, tss;                      /* timer prescaler counter / stop bit */

    /* Raw storage for MMR addresses with no dedicated field. */
    uint16_t mmr_raw[N_MMR];

    /* Interrupt shadow context (saved on entry, restored by RETI/RETE). */
    struct {
        uint32_t acc, accb, preg;
        uint16_t treg0, treg1, treg2, arcr, indx;
        int arp, arb, dp, ov, ovm, intm, cnf, tc, sxm, c, hm, xf, pm;
        int iptr, avis, ovly, ram, mpmc, ndx, trm, braf;
    } sh;

    uint64_t cycles;                   /* total machine cycles executed */
    int xsrempty, rsrfull;             /* SPC status bits 12 / 13 (Table 9-13) */
    int idle, bio, stop, status, xrdy, rrdy, xint_mode, xint_first;
    int cyc_model;                     /* 1 = charge manual cycle counts */
    int words;                         /* words fetched by the current instruction */
    int rep_cont;                      /* 1 = inside a repeated instruction */
    int legacy;                        /* stored by c5x_set_legacy; nothing reads it */
    uint64_t idle_cycles, timer_exp;   /* IDLE cycles / timer expiries (diagnostics) */
    /* Diagnostics gate (see c5x_set_diag): when 0, exec1/mmr/dm skip the
     * per-instruction and per-access diagnostic counters (hits, pcring,
     * pc_hits, trace, mmr_n/mmr_pc/mmr_val, ext_n, ff_n, rsv).  The C
     * driver never reads those counters, so it runs with diag off; the
     * default is ON so the Python ctypes .so ABI keeps its old
     * behaviour unless the caller opts out.  Counters that the glue
     * DOES read (cycles, timer_exp, idle_cycles, dxr_ring, iolog) are
     * not gated. */
    int diag;

    /* Memories (flat 64K x 16-bit views owned by the core). */
    uint16_t *pmem, *dmem, *iomem;
    uint32_t *hits;                    /* per-PC execution counts */

    /* Host I/O callbacks (NULL = use iomem[] as the port array). */
    io_rd_fn io_rd;
    io_wr_fn io_wr;
    void *io_ctx;

    /* I/O event log. */
    int iolog_on;
    IoEv *iolog;
    uint32_t iolog_n;

    /* Breakpoints (one byte per PC). */
    uint8_t *bp;

    uint16_t cur_pc;                   /* PC of the instruction now executing */
    uint16_t pcring[PC_RING_N];        /* ring of recently executed PCs */
    uint32_t pcring_i;
    int in_delay;                      /* 1 = executing a delay-slot word */

    /* AR0 / NDX mirroring (audit #10).  PERF2 stage 1: ar0_prev removed —
     * it was written once per instruction in c5x_run but never read
     * anywhere, in this tree or in the original Python core
     * (handover/dsp/c5x_core.c:600 writes it, nothing reads it, and no
     * accessor exposes it).  Bisect (PERF2.md) showed the removal is not
     * the source of the +3 s seen with the glue logging gates on. */
    int ar0_dirty, int_inh;
    int cmpr_ar0;                      /* experiment: CMPR compares AR0, not ARCR */

    /* RPTB block replay (PERF2 stage 3).  pm_epoch is bumped on any
     * program-word or fetch-mapping change (pm_wr, glue overlay loads
     * via c5x_pm_invalidate, LST #1 / RCNF / SCNF, PMST writes, c5x_set
     * ST1/PMST); bp_epoch is bumped by c5x_set_bp; run_seq counts
     * c5x_run entries (the per-call validation in blk_lookup covers
     * the one frequent PM writer that does NOT bump the epoch, dm_wr
     * to external (unified) memory).  replay_active is 1 while
     * blk_replay is executing entries; replay_dirty is set when a
     * write during the replay threatens the block's words or the
     * block/mapping state (mmr_wr PMST/RPTC/BRCR/PASR/PAER cases,
     * pm_wr). */
    uint64_t pm_epoch, bp_epoch, run_seq;
    int replay_active, replay_dirty;
    uint16_t replay_lo, replay_hi; /* active block range, for blk_store_guard */
    BlkDec *blk_cache[BLK_CACHE_N];

    /* PC-hit / watch / trace diagnostics. */
    uint32_t pc_hits[65536];
    uint32_t watch_hits[65536];
    int32_t watch_a;
    int32_t trace_pc;
    uint32_t trace_n;
    struct { uint32_t acc; uint16_t ret, ret2; uint64_t cyc; } trace_buf[TRACE_N];

    /* Every DXR write is appended here (ring of 65536). */
    uint16_t *dxr_ring;
    uint32_t dxr_head;

    /* Interrupt-vector indirection: if ivec_ind[n] != 0, interrupt n jumps
     * to dmem[ivec_ind[n]] instead of the vector-table entry. */
    uint16_t ivec_ind[16];
};

/* A program-word or fetch-mapping change: invalidate cached block
 * decodes (bump pm_epoch) and, if a replay is in flight, flag it so
 * the replay breaks out after the current instruction.  Only called
 * from rare paths (pm_wr, PMST/RPTC/BRCR/PASR/PAER MMR writes,
 * LST #1, RCNF/SCNF, c5x_set ST1/PMST).  The frequent dm_wr path
 * does not call this: its external (unified-memory) writes bump
 * pm_epoch directly in dm_wr, and its in-replay writes are caught
 * by blk_store_guard. */
static inline void blk_state_changed(C5x *c)
{
    c->pm_epoch++;
    if (c->replay_active)
        c->replay_dirty = 1;
}

/* Forward declarations for helpers defined in the ALU/addressing section. */
static inline void push(C5x *c, uint16_t v);
static inline uint16_t pop(C5x *c);

/* ------------------------------------------------------------------ */
/* Cycle table (mutable copy; see cycm_setup)                          */
/* ------------------------------------------------------------------ */

/* Mutable copy of the manual cycle table.  CYC_EXP (bit mask) lowers
 * classes for experiments (orig L55): 1 = RPT forms cost 1,
 * 2 = one-shot BLDD/BLPD/TBLR/TBLW cost 2 (0xA5xx-0xA9xx). */
static uint8_t cycm[65536];
static int cycm_init;

static void cycm_setup(void)
{
    if (cycm_init)
        return;
    cycm_init = 1;
    memcpy(cycm, cyc_tab, sizeof cycm);
    const char *e = getenv("CYC_EXP");
    int m = e ? atoi(e) : 0;
    if (m & 1) {
        for (int w = 0x0B00; w <= 0x0BFF; w++)
            cycm[w] = 1;
        for (int w = 0xBB00; w <= 0xBBFF; w++)
            cycm[w] = 1;
        cycm[0xBEC4] = 1;
    }
    if (m & 2) {
        for (int w = 0xA500; w <= 0xA9FF; w++)
            if (cycm[w] == 3)
                cycm[w] = 2;
    }
}

/* ------------------------------------------------------------------ */
/* Construction and simple accessors                                   */
/* ------------------------------------------------------------------ */

C5x *c5x_new(void)
{
    cycm_setup();
    C5x *c = calloc(1, sizeof *c);
    c->pmem = calloc(65536, 2);
    c->dmem = calloc(65536, 2);
    c->iomem = calloc(65536, 2);
    c->hits = calloc(65536, 4);
    c->bp = calloc(65536, 1);
    c->iolog = calloc(IOLOG_N, sizeof(IoEv));
    c->dxr_ring = calloc(DXR_RING_N, 2);
    c->rptc = 0;
    c->trace_pc = -1;
    c->watch_a = -1;
    c->diag = 1; /* default ON: preserves the .so / ctypes behaviour */
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
void c5x_set_io(C5x *c, io_rd_fn rd, io_wr_fn wr, void *ctx)
{
    c->io_rd = rd;
    c->io_wr = wr;
    c->io_ctx = ctx;
}
void c5x_set_bp(C5x *c, uint16_t a, int on) { c->bp[a] = on; c->bp_epoch++; }
void c5x_stop(C5x *c) { c->stop = 1; }
void c5x_set_bio(C5x *c, int v) { c->bio = v; }
/* Invalidate cached RPTB block decodes (PERF2 stage 3).  Called by
 * the glue after writing program memory from outside the core
 * (overlay loads through the raw c5x_pmem() pointer). */
void c5x_pm_invalidate(C5x *c) { c->pm_epoch++; }
uint16_t *c5x_pcring(C5x *c) { return c->pcring; }
uint32_t c5x_pcring_idx(C5x *c) { return c->pcring_i; }

/* Reset: restores the power-on register state for a fresh run at pc.
 * Deliberately does NOT touch: the memories, hits/pc_hits/watch/trace
 * diagnostics, MMR counters, breakpoints, the I/O log, the DXR ring,
 * ivec_ind, cmpr_ar0, xint_mode, cyc_model, legacy, idle_cycles,
 * timer_exp, or the unlisted registers below (indx, arcr, cbsr/cber,
 * bmar, dbmr, pasr, paer, rpt_start/rpt_end, io_rep).  (PERF2 stage 1:
 * ar0_prev used to be listed here; the field was removed as write-only.)
 * That selective reset is the original's behaviour (orig L87-99). */
void c5x_reset(C5x *c, uint16_t pc)
{
    c->acc = c->accb = c->preg = 0;
    c->treg0 = c->treg1 = c->treg2 = 0;
    memset(c->ar, 0, sizeof c->ar);
    c->intm = 1; c->ov = 0; c->ovm = 0; c->arp = 0; c->arb = 0; c->dp = 0;
    c->c = 1; c->cnf = 0; c->hm = 1; c->pm = 0; c->sxm = 1; c->xf = 1; c->tc = 0;
    c->iptr = 0; c->avis = 0; c->ovly = 0; c->ram = 0; c->mpmc = 0;
    c->ndx = 0; c->trm = 0; c->braf = 0;
    c->ifr = 0; c->imr = 0; c->cbcr = 0; c->rptc = 0; c->idle = 0; c->sp = 0;
    c->ar0_dirty = 0; c->int_inh = 0; c->xc_left = c->xc_new = 0;
    c->rep_cont = 0; c->brcr = 0; c->greg = 0;
    c->pdwsr = c->iowsr = 0xFFFF; c->cwsr = 0x0F;
    /* 07-NEW-6 (orig L93): no stale host-side flags across a reset. */
    c->drr = c->dxr = c->spc = 0;
    c->pc = pc;
    c->xrdy = 1; c->rrdy = 0; c->xsrempty = 0; c->rsrfull = 0; c->spc = 0;
    c->cycles = 0; c->tss = 0; c->psc = 0;
    c->tim = 0xFFFF; c->prd = 0xFFFF; c->tcr_tddr = 0;
    memset(c->stack, 0, sizeof c->stack);
}

/* ------------------------------------------------------------------ */
/* Status registers                                                    */
/* ------------------------------------------------------------------ */

/* ST0: ARP(13), OV(12), OVM(11), 1(10, hardwired), INTM(9), DP(8..0).
 * dp is stored pre-shifted (<< 7), so dp >> 7 recovers the 9-bit page. */
static uint16_t st0_get(C5x *c)
{
    return (uint16_t)((c->arp << ST0_ARP_SHIFT) | (c->ov << ST0_OV_BIT) |
                      (c->ovm << ST0_OVM_BIT) | (1 << ST0_INT_BIT) |
                      (c->intm << ST0_INTM_BIT) | (c->dp >> 7));
}

/* ST1: ARB(13), CNF(12), TC(11), SXM(10), C(9), 1(8), 1(7), HM(6),
 * 1(5), XF(4), 1(3), 1(2), PM(1..0).  Bits 8, 7, 5, 3, 2 read as 1. */
static uint16_t st1_get(C5x *c)
{
    return (uint16_t)((c->arb << ST1_ARB_SHIFT) | (c->cnf << ST1_CNF_BIT) |
                      (c->tc << ST1_TC_BIT) | (c->sxm << ST1_SXM_BIT) |
                      (c->c << ST1_C_BIT) | (1 << 8) | (1 << 7) |
                      (c->hm << ST1_HM_BIT) | (1 << 5) | (c->xf << ST1_XF_BIT) |
                      (1 << 3) | (1 << 2) | c->pm);
}

/* PMST: IPTR(15..11), AVIS(7), OVLY(5), RAM(4), MPMC(3), NDX(2), TRM(1), BRAF(0). */
static uint16_t pmst_get(C5x *c)
{
    return (uint16_t)((c->iptr << PMST_IPTR_SHIFT) | (c->avis << PMST_AVIS_BIT) |
                      (c->ovly << PMST_OVLY_BIT) | (c->ram << PMST_RAM_BIT) |
                      (c->mpmc << PMST_MPMC_BIT) | (c->ndx << PMST_NDX_BIT) |
                      (c->trm << PMST_TRM_BIT) | c->braf);
}

uint32_t c5x_get(C5x *c, int id)
{
    if (id >= C5X_REG_AR0 && id < C5X_REG_AR0 + N_AR)
        return c->ar[id - C5X_REG_AR0];
    switch (id) {
    case C5X_REG_PC: return c->pc;
    case C5X_REG_ACC: return c->acc;
    case C5X_REG_ACCB: return c->accb;
    case C5X_REG_PREG: return c->preg;
    case C5X_REG_T0: return c->treg0;
    case C5X_REG_T1: return c->treg1;
    case C5X_REG_T2: return c->treg2;
    case C5X_REG_ST0: return st0_get(c);
    case C5X_REG_ST1: return st1_get(c);
    case C5X_REG_PMST: return pmst_get(c);
    case C5X_REG_RPTC: return (uint32_t)c->rptc;
    case C5X_REG_IFR: return c->ifr;
    case C5X_REG_IMR: return c->imr;
    case C5X_REG_SP: return (uint32_t)c->sp;
    case C5X_REG_CYC_LO: return (uint32_t)c->cycles;
    case C5X_REG_CYC_HI: return (uint32_t)(c->cycles >> 32);
    case C5X_REG_BMAR: return c->bmar;
    case C5X_REG_DBMR: return c->dbmr;
    case C5X_REG_INDX: return c->indx;
    case C5X_REG_ARCR: return c->arcr;
    case C5X_REG_DXR: return c->dxr;
    case C5X_REG_DRR: return c->drr;
    case C5X_REG_TIM: return c->tim;
    case C5X_REG_PRD: return c->prd;
    case C5X_REG_IDLE: return (uint32_t)c->idle;
    }
    return 0;
}

void c5x_set(C5x *c, int id, uint32_t v)
{
    if (id >= C5X_REG_AR0 && id < C5X_REG_AR0 + N_AR) {
        c->ar[id - C5X_REG_AR0] = (uint16_t)v;
        if (id == C5X_REG_AR0)
            c->ar0_dirty = 1;
        return;
    }
    switch (id) {
    case C5X_REG_PC: c->pc = (uint16_t)v; break;
    case C5X_REG_ACC: c->acc = v; break;
    case C5X_REG_ACCB: c->accb = v; break;
    case C5X_REG_DRR: c->drr = (uint16_t)v; break;
    case C5X_REG_DXR: c->dxr = (uint16_t)v; break;
    case C5X_REG_IMR: c->imr = (uint16_t)v; break;
    case C5X_REG_ST0:
        c->arp = (int)(v >> ST0_ARP_SHIFT);
        c->ov = (int)((v >> ST0_OV_BIT) & 1);
        c->ovm = (int)((v >> ST0_OVM_BIT) & 1);
        c->intm = (int)((v >> ST0_INTM_BIT) & 1);
        c->dp = (int)((v & 0x1ff) << 7);
        break;
    case C5X_REG_ST1:
        c->arb = (int)(v >> ST1_ARB_SHIFT);
        blk_state_changed(c); /* CNF is part of the fetch mapping */
        c->cnf = (int)((v >> ST1_CNF_BIT) & 1);
        c->tc = (int)((v >> ST1_TC_BIT) & 1);
        c->sxm = (int)((v >> ST1_SXM_BIT) & 1);
        c->c = (int)((v >> ST1_C_BIT) & 1);
        c->hm = (int)((v >> ST1_HM_BIT) & 1);
        c->xf = (int)((v >> ST1_XF_BIT) & 1);
        c->pm = (int)(v & 3);
        break;
    case C5X_REG_PMST:
        blk_state_changed(c); /* RAM/BRAF are fetch-mapping / block state */
        c->iptr = (int)(v >> PMST_IPTR_SHIFT);
        c->avis = (int)((v >> PMST_AVIS_BIT) & 1);
        c->ovly = (int)((v >> PMST_OVLY_BIT) & 1);
        c->ram = (int)((v >> PMST_RAM_BIT) & 1);
        c->mpmc = (int)((v >> PMST_MPMC_BIT) & 1);
        c->ndx = (int)((v >> PMST_NDX_BIT) & 1);
        c->trm = (int)((v >> PMST_TRM_BIT) & 1);
        c->braf = (int)(v & 1);
        break;
    case C5X_REG_PUSH: /* push value on the hardware stack (orig L130) */
        push(c, (uint16_t)v);
        break;
    case C5X_REG_SETIDLE: c->idle = (int)v; break;
    }
}

void c5x_irq(C5x *c, int bit) { c->ifr |= (uint16_t)(1 << bit); }

/* ------------------------------------------------------------------ */
/* Host I/O (ports)                                                    */
/* ------------------------------------------------------------------ */

/* Wait states of an I/O access, from IOWSR/CWSR (manual 9.4.2/9.4.3;
 * orig L135-140).  CWSR bit 4 selects large (8K, port>>13) versus small
 * (128-word, (port>>1)&7) page indexing; the CWSR alt bit doubles the
 * programmed count for 2->3 and 3->7 wait states. */
static int io_ws(C5x *c, uint16_t port)
{
    int big = (c->cwsr >> CWSR_BIG_BIT) & 1;
    int idx = big ? (port >> 13) : ((port >> 1) & 7);
    int f = (c->iowsr >> (2 * idx)) & 3;
    int alt = (c->cwsr >> (idx < 4 ? 2 : 3)) & 1;
    return alt ? (f == 3 ? 7 : f == 2 ? 3 : f) : f;
}

static uint16_t io_read(C5x *c, uint16_t port)
{
    uint16_t v;
    /* A read takes one extra cycle per wait state (orig L143). */
    if (c->cyc_model)
        c->cycles += (uint64_t)io_ws(c, port);
    if (c->io_rd)
        v = c->io_rd(c->io_ctx, port);
    else
        v = c->iomem[port];
    if (c->iolog_on && c->iolog_n < IOLOG_N)
        c->iolog[c->iolog_n++] = (IoEv){ c->cycles, c->cur_pc, port, v, 0 };
    return v;
}

static void io_write(C5x *c, uint16_t port, uint16_t v)
{
    /* Software wait states do not lengthen writes until two or more are
     * programmed (manual Table 9-7; orig L152). */
    if (c->cyc_model) {
        int w = io_ws(c, port);
        if (w > 1)
            c->cycles += (uint64_t)(w - 1);
    }
    if (c->iolog_on && c->iolog_n < IOLOG_N)
        c->iolog[c->iolog_n++] = (IoEv){ c->cycles, c->cur_pc, port, v, 1 };
    if (c->io_wr)
        c->io_wr(c->io_ctx, port, v);
    else
        c->iomem[port] = v;
}

/* ------------------------------------------------------------------ */
/* Memory-mapped registers (data space 0x00..0x5F)                     */
/* ------------------------------------------------------------------ */

static inline __attribute__((always_inline)) uint16_t mmr_rd(C5x *c, uint16_t a)
{
    if (a < N_MMR && c->diag) {
        c->mmr_n[0][a]++;
        c->mmr_pc[0][a] = c->cur_pc;
    }
    if (a >= 0x50)
        return io_read(c, a);
    if (a >= 0x10 && a < 0x18)
        return c->ar[a - 0x10];
    switch (a) {
    case 0x04: return c->imr;
    case 0x05: return c->greg;
    case 0x06: return c->ifr;
    case 0x07: return pmst_get(c);
    case 0x08: return (uint16_t)c->rptc;
    case 0x09: return (uint16_t)c->brcr;
    case 0x0A: return c->pasr;
    case 0x0B: return c->paer;
    case 0x0C: return c->treg0;
    case 0x0D: return (uint16_t)(c->treg1 & 0x1F);
    case 0x0E: return (uint16_t)(c->treg2 & 0xF);
    case 0x0F: return c->dbmr;
    case 0x18: return c->indx;
    case 0x19: return c->arcr;
    case 0x1A: return c->cbsr1;
    case 0x1B: return c->cber1;
    case 0x1C: return c->cbsr2;
    case 0x1D: return c->cber2;
    case 0x1E: return c->cbcr;
    case 0x1F: return c->bmar;
    case 0x20:
        /* Reading DRR clears RRDY / RSRFULL (orig L163). */
        c->rrdy = 0;
        c->rsrfull = 0;
        return c->drr;
    case 0x21: return c->dxr;
    case 0x22:
        /* SPC read: stored bits masked to 0xC0FE, ORed with live status.
         * Bit 0 reads 0; IN0/IN1 (CLKR/CLKX pins) read 0 (orig L165). */
        return (uint16_t)((c->spc & SPC_WRITABLE_MASK) |
                          (c->rsrfull << SPC_RSRFULL_BIT) |
                          (c->xsrempty << SPC_XSREMPTY_BIT) |
                          (c->xrdy << SPC_XRDY_BIT) |
                          (c->rrdy << SPC_RRDY_BIT));
    case 0x24: return c->tim;
    case 0x25: return c->prd;
    case 0x26:
        return (uint16_t)(((c->psc & 0xF) << TCR_PSC_SHIFT) |
                          (c->tss << TCR_TSS_BIT) | (c->tcr_tddr & TCR_TDDR_MASK));
    case 0x28: return c->pdwsr;
    case 0x29: return c->iowsr;
    case 0x2A: return c->cwsr;
    }
    return c->mmr_raw[a];
}

static inline __attribute__((always_inline)) void mmr_wr(C5x *c, uint16_t a, uint16_t d)
{
    if (a < N_MMR && c->diag) {
        c->mmr_n[1][a]++;
        c->mmr_pc[1][a] = c->cur_pc;
        /* mmr_val keeps the first value written, except for the low MMRs,
         * the circular-buffer / wait-state block 0x1A..0x2A, and 0x32,
         * which always update (orig L175). */
        if (c->mmr_n[1][a] <= 1 || a < 0x10 ||
            (a >= 0x1A && a <= 0x2A) || a == 0x32)
            c->mmr_val[a] = d;
    }
    if (a >= 0x50) {
        io_write(c, a, d);
        return;
    }
    if (a >= 0x10 && a < 0x18) {
        c->ar[a - 0x10] = d;
        if (a == 0x10)
            c->ar0_dirty = 1;
        return;
    }
    switch (a) {
    case 0x04: c->imr = d; return;
    case 0x05: c->greg = d; return;
    case 0x06:
        /* Writing IFR clears the bits set in d (write-1-to-clear). */
        c->ifr &= (uint16_t)~d;
        return;
    case 0x07:
        /* PMST: RAM changes the fetch mapping, BRAF is block state. */
        blk_state_changed(c);
        c->iptr = d >> PMST_IPTR_SHIFT;
        c->avis = (d >> PMST_AVIS_BIT) & 1;
        c->ovly = (d >> PMST_OVLY_BIT) & 1;
        c->ram = (d >> PMST_RAM_BIT) & 1;
        c->mpmc = (d >> PMST_MPMC_BIT) & 1;
        c->ndx = (d >> PMST_NDX_BIT) & 1;
        c->trm = (d >> PMST_TRM_BIT) & 1;
        c->braf = d & 1;
        return;
    case 0x08: blk_state_changed(c); c->rptc = d; return;
    case 0x09: blk_state_changed(c); c->brcr = d; return;
    case 0x0A: blk_state_changed(c); c->pasr = d; return;
    case 0x0B: blk_state_changed(c); c->paer = d; return;
    case 0x0C: c->treg0 = d; return;
    case 0x0D: c->treg1 = (uint16_t)(d & 0x1F); return;
    case 0x0E: c->treg2 = (uint16_t)(d & 0xF); return;
    case 0x0F: c->dbmr = d; return;
    case 0x18: c->indx = d; return;
    case 0x19: c->arcr = d; return;
    case 0x1A: c->cbsr1 = d; return;
    case 0x1B: c->cber1 = d; return;
    case 0x1C: c->cbsr2 = d; return;
    case 0x1D: c->cber2 = d; return;
    case 0x1E: c->cbcr = (uint16_t)(d & 0xFF); return;
    case 0x1F: c->bmar = d; return;
    case 0x20: c->drr = d; return;
    case 0x21:
        /* DXR write: falls through to the tail below (orig L184: break,
         * not return), so it also lands in mmr_raw[] and in the I/O log
         * as pseudo-port 0x8000|a. */
        c->dxr = d;
        c->xrdy = 0;
        c->xsrempty = 1;
        c->dxr_ring[c->dxr_head++ & 0xFFFF] = d;
        break;
    case 0x22:
        /* SPC: FREE/SOFT, RRST, XRST, TXM, MCM, FSM, FO, DLB are
         * writable; bits 13..8 are status.  Also falls through to the
         * tail below (orig L184-190: break, not return). */
        c->spc = (uint16_t)(d & SPC_WRITABLE_MASK);
        /* RRST=0 clears RRDY / RSRFULL. */
        if (!(d & SPC_RRST_BIT)) {
            c->rrdy = 0;
            c->rsrfull = 0;
        }
        /* XRST=0: XSREMPTY=0, XRDY=1, and XINT fires if XRDY was 0. */
        if (!(d & SPC_XRST_BIT)) {
            if (!c->xrdy)
                c->ifr |= (uint16_t)(1 << C5X_XINT);
            c->xsrempty = 0;
            c->xrdy = 1;
        }
        break;
    case 0x24: c->tim = d; return;
    case 0x25: c->prd = d; return;
    case 0x26:
        c->tcr_tddr = (uint16_t)(d & TCR_TDDR_MASK);
        c->tss = (d >> TCR_TSS_BIT) & 1;
        if (d & TCR_TRB_BIT) {
            c->tim = c->prd;
            c->psc = c->tcr_tddr;
        } else {
            c->psc = (d >> TCR_PSC_SHIFT) & 0xF;
        }
        return;
    case 0x28: c->pdwsr = d; return;
    case 0x29: c->iowsr = d; return;
    case 0x2A: c->cwsr = (uint16_t)(d & 0x1F); return;
    }
    c->mmr_raw[a] = d;
    /* DXR / SPC / unknown-MMR writes are visible through the I/O log as
     * pseudo-port 0x8000|a (orig L196-197).  Only the two break cases
     * above and the default path reach this tail; every return case
     * above skips it. */
    if (c->iolog_on && c->iolog_n < IOLOG_N)
        c->iolog[c->iolog_n++] =
            (IoEv){ c->cycles, c->cur_pc, (uint16_t)(0x8000 | a), d, 1 };
}

/* ------------------------------------------------------------------ */
/* Data / program memory routing                                       */
/* ------------------------------------------------------------------ */

/* Internal data RAM: B2 0x60-7F, B0/B1 0x100-4FF, SARAM 0x800-BFF.
 * Everything else is external SRAM, which on this board is shared
 * between program and data space (unified with pmem).
 * B0 leaves data space when CNF=1; SARAM is in data space only when
 * OVLY=1 (SPRU056D 8.2, courier-emu data_region; orig L201). */
static inline int dm_internal(C5x *c, uint16_t a)
{
    return a < DM_B2_END ||
           (a >= DM_B0_START && a < DM_B0_END && !(c->cnf && a < DM_B0_CNF_END)) ||
           (c->ovly && a >= DM_SARAM_START && a < DM_SARAM_END);
}

/* External memory-mapped host window. */
static inline int dm_hostwin(uint16_t a)
{
    return a >= DM_HOSTWIN_START && a <= DM_HOSTWIN_END;
}

/* Manual 6.2: a peripheral MMR access (20h-4Fh) goes over the TI bus
 * and adds one cycle. */
static inline void mmr_bus(C5x *c, uint16_t a)
{
    if (c->cyc_model && a >= DM_PERIPH_START && a < DM_PERIPH_END)
        c->cycles++;
}

static inline __attribute__((always_inline)) uint16_t dm_rd(C5x *c, uint16_t a)
{
    if (c->diag && a >= DM_MMR_END && !dm_internal(c, a)) {
        c->ext_n[0][a >> 10]++;
        if (a >= DM_FF_START)
            c->ff_n[0][a & 255]++;
        if (a >= DM_RSV_START && a < DM_RSV_END) {
            c->rsv_a = a;
            c->rsv_pc = c->cur_pc;
        }
    }
    if (a < DM_MMR_END)
        return mmr_rd(c, a);
    if (dm_internal(c, a))
        return c->dmem[a];
    if (dm_hostwin(a))
        return io_read(c, a);
    return c->pmem[a];
}

/* A data write during a replay that lands on a program word of the
 * block being replayed would make the cached decode stale mid-replay.
 * External unified memory (pmem[a] is program word a) and SARAM dmem
 * when it is also program space (RAM=1 and OVLY=1: dmem 0x800.. maps
 * to program 0x2000..) are the two routes; B0 has none (under CNF=1
 * data 0x100.. leaves data space, so a DM write there lands in
 * pmem[], a different cell from program 0xFE00's dmem[]).  The
 * replay checks replay_dirty after every entry and breaks out, so
 * this guard only has to set the flag.  It is a single predictable
 * branch when no replay is in flight (replay_active == 0). */
static inline void blk_store_guard(C5x *c, uint16_t a)
{
    if (a >= DM_MMR_END && !dm_internal(c, a) && !dm_hostwin(a)) {
        /* External: pmem[a] is program word a. */
        if (a >= c->replay_lo && a <= c->replay_hi)
            c->replay_dirty = 1;
    } else if (c->ram && c->ovly && a >= DM_SARAM_START && a < DM_SARAM_END) {
        /* SARAM dmem is program 0x2000.. when RAM=1 and OVLY=1. */
        uint16_t pma = (uint16_t)(a - DM_SARAM_START + PM_SARAM_START);
        if (pma >= c->replay_lo && pma <= c->replay_hi)
            c->replay_dirty = 1;
    }
}

static inline __attribute__((always_inline)) void dm_wr(C5x *c, uint16_t a, uint16_t d)
{
    mmr_bus(c, a);
    if (c->replay_active)
        blk_store_guard(c, a);
    if (c->diag) {
        if (a >= DM_MMR_END && !dm_internal(c, a))
            c->ext_n[1][a >> 10]++;
        if (a >= DM_FF_START)
            c->ff_n[1][a & 255]++;
    }
    if ((int32_t)a == c->watch_a)
        c->watch_hits[c->cur_pc]++;
    if (a < DM_MMR_END)
        mmr_wr(c, a, d);
    else if (dm_internal(c, a))
        c->dmem[a] = d;
    else if (dm_hostwin(a))
        io_write(c, a, d);
    else {
        c->pmem[a] = d;
        /* External DM is unified with PM: this may have written a
         * program word, so cached block decodes must re-validate at
         * the next lookup (cheap: one increment; re-validation is a
         * word compare, and lookups are infrequent).  The in-replay
         * case is covered by blk_store_guard above, which also sets
         * replay_dirty so the replay breaks out at once. */
        c->pm_epoch++;
    }
}

/* Data move only within on-chip RAM (DMOV/LTD/MACD/MADD): both the
 * source and the destination (a+1) must be on-chip RAM (07-NEW-4;
 * orig L206). */
static inline void dmov_wr(C5x *c, uint16_t a, uint16_t d)
{
    if (dm_internal(c, a) && a >= DM_MMR_END && dm_internal(c, (uint16_t)(a + 1)))
        dm_wr(c, (uint16_t)(a + 1), d);
}

/* Program-space pointer with the CNF/RAM overlays applied. */
static inline uint16_t *pm_ptr(C5x *c, uint16_t a)
{
    if (c->cnf && a >= PM_B0_START)
        return &c->dmem[a - PM_B0_START + 0x100];
    if (c->ram && a >= PM_SARAM_START && a < PM_SARAM_END)
        return &c->dmem[a - PM_SARAM_START + 0x800];
    return &c->pmem[a];
}

static inline uint16_t pm_rd(C5x *c, uint16_t a) { return *pm_ptr(c, a); }
static inline void pm_wr(C5x *c, uint16_t a, uint16_t d) { *pm_ptr(c, a) = d; blk_state_changed(c); }

/* ------------------------------------------------------------------ */
/* Stack, ALU, and addressing helpers                                  */
/* ------------------------------------------------------------------ */

static inline void push(C5x *c, uint16_t v)
{
    c->sp = (c->sp - 1) & 7;
    c->stack[c->sp] = v;
}

static inline uint16_t pop(C5x *c)
{
    uint16_t v = c->stack[c->sp];
    c->sp = (c->sp + 1) & 7;
    /* Quirk preserved (orig L219): the pop also duplicates the new
     * second-from-top entry into the vacated slot.  No known instruction
     * depends on it, but the copy is part of the observable state. */
    c->stack[(c->sp + 7) & 7] = c->stack[(c->sp + 6) & 7];
    return v;
}

/* 32-bit add with carry-in; s16=1 means the 16-bit form, where a carry
 * out sets C but a borrow... see below.  Overflow saturates only if
 * OVM is set, and always sets OV (manual 6.3 ADD). */
static uint32_t do_add(C5x *c, uint32_t a, uint32_t b, int cin, int s16)
{
    uint64_t r = (uint64_t)a + b + (uint32_t)cin;
    uint32_t res = (uint32_t)r;
    int carry = (int)((r >> 32) & 1);
    if (s16) {
        if (carry)
            c->c = 1;
    } else {
        c->c = carry;
    }
    if ((a ^ res) & (b ^ res) & 0x80000000u) {
        if (c->ovm)
            res = ((int32_t)res < 0) ? 0x7fffffffu : 0x80000000u;
        c->ov = 1;
    }
    return res;
}

/* 32-bit subtract with borrow-in; s16=1 is the 16-bit form, where a
 * borrow out clears C instead of setting it (manual 6.3 SUB). */
static uint32_t do_sub(C5x *c, uint32_t a, uint32_t b, int bin, int s16)
{
    uint64_t r = (uint64_t)a - b - (uint32_t)bin;
    uint32_t res = (uint32_t)r;
    int borrow = (int)((r >> 32) & 1);
    if (s16) {
        if (borrow)
            c->c = 0;
    } else {
        c->c = !borrow;
    }
    if ((a ^ b) & (a ^ res) & 0x80000000u) {
        if (c->ovm)
            res = ((int32_t)res < 0) ? 0x7fffffffu : 0x80000000u;
        c->ov = 1;
    }
    return res;
}

/* PREG scaled by the PM (product shift mode) field: 00 = no shift,
 * 01 = <<1, 10 = <<4, 11 = >>6 (arithmetic; PREG is signed here). */
static inline int32_t pscale(C5x *c)
{
    int32_t p = (int32_t)c->preg;
    switch (c->pm & 3) {
    case 0: return p;
    case 1: return (int32_t)((uint32_t)p << 1);
    case 2: return (int32_t)((uint32_t)p << 4);
    default: return p >> 6;
    }
}

/* Load TREG0; unless TRM is set, TREG1/TREG2 mirror its low bits
 * (TREG1 = d & 0x1F, TREG2 = d & 0xF). */
static inline void set_t0(C5x *c, uint16_t d)
{
    c->treg0 = d;
    if (!c->trm) {
        c->treg1 = (uint16_t)(d & 0x1F);
        c->treg2 = (uint16_t)(d & 0xF);
    }
}

/* Circular-buffer end test for bit-reversed addressing: returns 1 and
 * the block start when ARn has reached its block end.  Bank 1 wins
 * over bank 2 when both select the same AR (orig L238-245). */
static int circ_end(C5x *c, int ar, uint16_t v, uint16_t *start)
{
    int cenb1 = (c->cbcr >> 3) & 1, car1 = c->cbcr & 7;
    int cenb2 = (c->cbcr >> 7) & 1, car2 = (c->cbcr >> 4) & 7;
    if (cenb1 && ar == car1 && v == c->cber1) {
        *start = c->cbsr1;
        return 1;
    }
    if (!(cenb1 && ar == car1) && cenb2 && ar == car2 && v == c->cber2) {
        *start = c->cbsr2;
        return 1;
    }
    return 0;
}

static uint16_t bitrev16(uint16_t v)
{
    uint16_t r = 0;
    for (int i = 0; i < 16; i++)
        if (v & (1 << i))
            r |= (uint16_t)(1 << (15 - i));
    return r;
}

/* Step ARn by step, wrapping to the block start at the block end when
 * circular addressing is enabled for that AR. */
static inline __attribute__((always_inline)) void upd_ar(C5x *c, int ar, int step)
{
    if (ar == 0)
        c->ar0_dirty = 1;
    int cenb1 = (c->cbcr >> 3) & 1, car1 = c->cbcr & 7;
    int cenb2 = (c->cbcr >> 7) & 1, car2 = (c->cbcr >> 4) & 7;
    if (cenb1 && ar == car1) {
        if (c->ar[ar] == c->cber1)
            c->ar[ar] = c->cbsr1;
        else
            c->ar[ar] = (uint16_t)(c->ar[ar] + step);
    } else if (cenb2 && ar == car2) {
        if (c->ar[ar] == c->cber2)
            c->ar[ar] = c->cbsr2;
        else
            c->ar[ar] = (uint16_t)(c->ar[ar] + step);
    } else {
        c->ar[ar] = (uint16_t)(c->ar[ar] + step);
    }
}

/* Switch ARP, saving the old ARP in ARB. */
static inline void upd_arp(C5x *c, int n)
{
    c->arb = c->arp;
    c->arp = n;
}

/* Effective address of the current instruction (manual 5.2).
 * Direct (bit 7 clear): dp | low 7 bits.  Indirect: AR[ARP] plus the
 * modification encoded in bits 6..3 (0 = none, 2 = -1, 4 = +1,
 * 8 = bit-reversed -INDX, 0xA = -INDX, 0xC = +INDX, 0xE = bit-reversed
 * +INDX); bit 0 (m & 1) additionally switches ARP to the low 3 bits.
 * An unlisted modification sets RUN_BADOP (orig L270: default case). */
static inline __attribute__((always_inline)) uint16_t ea(C5x *c)
{
    uint16_t op = c->op;
    if (!(op & 0x80))
        return (uint16_t)(c->dp | (op & 0x7f));
    int arp = c->arp, nar = op & 7, m = (op >> 3) & 0xF;
    uint16_t a = c->ar[arp];
    switch (m & ~1) {
    case 0x0: break;
    case 0x2: upd_ar(c, arp, -1); break;
    case 0x4: upd_ar(c, arp, 1); break;
    case 0x8: {
        uint16_t st;
        c->ar[arp] = circ_end(c, arp, a, &st)
            ? st
            : bitrev16((uint16_t)(bitrev16(a) - bitrev16(c->indx)));
        if (arp == 0)
            c->ar0_dirty = 1;
        break;
    }
    case 0xA: upd_ar(c, arp, -(int16_t)c->indx); break;
    case 0xC: upd_ar(c, arp, (int16_t)c->indx); break;
    case 0xE: {
        uint16_t st;
        c->ar[arp] = circ_end(c, arp, a, &st)
            ? st
            : bitrev16((uint16_t)(bitrev16(a) + bitrev16(c->indx)));
        if (arp == 0)
            c->ar0_dirty = 1;
        break;
    }
    default: c->status = RUN_BADOP; break;
    }
    if (m & 1)
        upd_arp(c, nar);
    return a;
}

/* SST uses page 0 for direct addressing (orig L275). */
static uint16_t ea_p0(C5x *c)
{
    if (!(c->op & 0x80))
        return (uint16_t)(c->op & 0x7f);
    return ea(c);
}

/* Branch-condition ZLVC field (manual 4.5): zlvc bits are the expected
 * values, mask selects which flags are tested.  The (mask & 0xC) |
 * ((zlvc >> 2) & 3) switch encodes the ACC sign/zero tests. */
static int zlvc_cond(C5x *c, int zlvc, int mask)
{
    if (mask & 2) {
        if ((zlvc & 2) && !c->ov)
            return 0;
        if (!(zlvc & 2) && c->ov)
            return 0;
    }
    if (mask & 1) {
        if ((zlvc & 1) && !c->c)
            return 0;
        if (!(zlvc & 1) && c->c)
            return 0;
    }
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

/* TP field of conditional branches: 0 = BIO low, 1 = TC set, 2 = TC clear. */
static int tp_cond(C5x *c, int tp)
{
    switch (tp) {
    case 0: return c->bio == 0;
    case 1: return c->tc;
    case 2: return !c->tc;
    }
    return 1;
}

static int cond(C5x *c)
{
    return zlvc_cond(c, (c->op >> 4) & 0xF, c->op & 0xF) &&
           tp_cond(c, (c->op >> 8) & 3);
}

static inline uint16_t fetch(C5x *c)
{
    uint16_t v = pm_rd(c, c->pc);
    c->pc++;
    c->words++;
    return v;
}

/* Forward declaration: the executor, defined in the next section. */
static void exec1(C5x *c);

/* Execute the delay slot of a delayed branch/call/return: the two words
 * following the branch (start = PC just past the branch target word).
 * The slot words' own cycles are added to the delayed branch's total
 * (manual 4.5.5 Ex. 4-3: BCNDD 2 + OPL 2 = 4; orig L296-301).
 * The NDX mirror applies between the slot words too (manual 5.2.1).
 * The opcode is restored afterwards (orig L300: op = op0) so the
 * cycle model charges the branch, not the slot word. */
static void delay_slot(C5x *c, uint16_t start)
{
    uint64_t cy0 = c->cycles;
    uint16_t op0 = c->op;
    c->in_delay = 1;
    do {
        exec1(c);
        if (c->cyc_model)
            c->cycles += cycm[c->op] - 1;
        if (c->ar0_dirty) {
            if (!c->ndx)
                c->indx = c->arcr = c->ar[0];
            c->ar0_dirty = 0;
        }
    } while ((uint16_t)(c->pc - start) < 2);
    c->in_delay = 0;
    c->op = op0;
    (void)cy0; /* cy0 is kept only as a debugging anchor (orig L300). */
}

/* Save / restore the interrupt shadow context.  NOTE (audit #9,
 * orig L311): restore_ctx deliberately does NOT restore INTM and XF,
 * even though save_ctx saves them. */
static void save_ctx(C5x *c)
{
    c->sh.acc = c->acc; c->sh.accb = c->accb; c->sh.preg = c->preg;
    c->sh.treg0 = c->treg0; c->sh.treg1 = c->treg1; c->sh.treg2 = c->treg2;
    c->sh.arcr = c->arcr; c->sh.indx = c->indx;
    c->sh.arp = c->arp; c->sh.arb = c->arb; c->sh.dp = c->dp;
    c->sh.ov = c->ov; c->sh.ovm = c->ovm; c->sh.intm = c->intm;
    c->sh.cnf = c->cnf; c->sh.tc = c->tc; c->sh.sxm = c->sxm;
    c->sh.c = c->c; c->sh.hm = c->hm; c->sh.xf = c->xf; c->sh.pm = c->pm;
    c->sh.iptr = c->iptr; c->sh.avis = c->avis; c->sh.ovly = c->ovly;
    c->sh.ram = c->ram; c->sh.mpmc = c->mpmc; c->sh.ndx = c->ndx;
    c->sh.trm = c->trm; c->sh.braf = c->braf;
}

static void restore_ctx(C5x *c)
{
    c->acc = c->sh.acc; c->accb = c->sh.accb; c->preg = c->sh.preg;
    c->treg0 = c->sh.treg0; c->treg1 = c->sh.treg1; c->treg2 = c->sh.treg2;
    c->arcr = c->sh.arcr; c->indx = c->sh.indx;
    c->arp = c->sh.arp; c->arb = c->sh.arb; c->dp = c->sh.dp;
    c->ov = c->sh.ov; c->ovm = c->sh.ovm;
    /* audit #9: INTM/XF are not shadowed -- not restored here. */
    c->cnf = c->sh.cnf; c->tc = c->sh.tc; c->sxm = c->sh.sxm;
    c->c = c->sh.c; c->hm = c->sh.hm; c->pm = c->sh.pm;
    c->iptr = c->sh.iptr; c->avis = c->sh.avis; c->ovly = c->sh.ovly;
    c->ram = c->sh.ram; c->mpmc = c->sh.mpmc;
    c->ndx = c->sh.ndx; c->trm = c->sh.trm; c->braf = c->sh.braf;
}

/* Interrupt vectors, IPTR-relative (manual 8.2.2; orig L314-315).
 * Index = interrupt bit 0..8 (INT1..INT4).  Audited order:
 * INT1..INT3, TINT, RINT, XINT, TRNT, TXNT, INT4. */
static const uint8_t ivec[N_INT] = {
    0x02, 0x04, 0x06, 0x08, 0x0A, 0x0C, 0x0E, 0x10, 0x12
};
/* Old (wrong) table, still used so the firmware's `intr 17` (0x22)
 * reaches the INT4 slot via the ROM-stub model (orig L315).  Only the
 * INTR instruction consults it, never external-interrupt entry. */
static const uint8_t ivec_legacy[N_INT] = {
    0x02, 0x04, 0x06, 0x18, 0x1A, 0x1C, 0x1E, 0x20, 0x22
};

static void tick_timer(C5x *c);

/* Take the highest-priority pending, unmasked interrupt (lowest bit
 * first).  Entry pushes PC, jumps IPTR-relative (or via ivec_ind),
 * clears the flag, wakes from IDLE, shadows the context, and costs
 * 4 cycles when the cycle model is on (pipeline flush, manual 7.2.2 /
 * App. B class X; orig L317-328). */
static void check_int(C5x *c)
{
    uint16_t pend = (uint16_t)(c->ifr & c->imr);
    if (c->intm || !pend)
        return;
    for (int i = 0; i < N_INT; i++) {
        if (pend & (1 << i)) {
            c->intm = 1;
            push(c, c->pc);
            c->pc = c->ivec_ind[i] ? dm_rd(c, c->ivec_ind[i])
                                   : (uint16_t)((c->iptr << 11) | ivec[i]);
            c->ifr &= (uint16_t)~(1 << i);
            c->idle = 0;
            save_ctx(c);
            if (c->cyc_model) {
                for (int k = 0; k < 4; k++) {
                    c->cycles++;
                    tick_timer(c);
                }
            }
            return;
        }
    }
}

/* Data -> ACC with shift, honouring SXM (sign extension). */
static inline uint32_t ext(C5x *c, uint16_t d, int sh)
{
    return c->sxm ? (uint32_t)((int32_t)(int16_t)d << sh)
                  : ((uint32_t)d << sh);
}

/* One timer tick (manual 9.4).  The prescaler counts down from TDDR;
 * on expiry TIM counts down, and on TIM == 0 it reloads from PRD and
 * raises TINT (IFR bit 3).  Stopped entirely while TSS is set. */
static inline void tick_timer(C5x *c)
{
    if (c->tss)
        return;
    if (--c->psc < 0) {
        c->psc = c->tcr_tddr;
        if (c->tim == 0) {
            c->tim = c->prd;
            c->ifr |= (uint16_t)(1 << C5X_TINT);
            c->timer_exp++;
        } else {
            c->tim--;
        }
    }
}

/* ------------------------------------------------------------------ */
/* Instruction execution                                               */
/*                                                                     */
/* exec1() fetches one instruction, charges its base cycle, and      */
/* dispatches on the high byte to one small helper per opcode class.   */
/* Every case body below is the original's (orig L331-500), only       */
/* reformatted and commented.  Repeat loops keep the original's       */
/* exact post-decrement accounting: the loop runs while rptc > -1     */
/* and charges only when the pre-decrement value was > 0.              */
/* ------------------------------------------------------------------ */

static void exec_be(C5x *c);
static void exec_bf(C5x *c);

/* High bytes 0x00..0x0F: LAR, LAMM, SMMR, SUBC, RPT, OUT, LDP, LST. */
static void exec_hi_00_0f(C5x *c, uint16_t op)
{
    uint16_t a, d;
    switch (op >> 8) {
    case 0x00: case 0x01: case 0x02: case 0x03:
    case 0x04: case 0x05: case 0x06: case 0x07:
        /* LAR dma: load AR[(op>>8)] from data memory. */
        a = ea(c);
        c->ar[(op >> 8) & 7] = dm_rd(c, a);
        if (((op >> 8) & 7) == 0)
            c->ar0_dirty = 1;
        break;
    case 0x08:
        /* LAMM: ACC = data memory (page 0 only: address & 0x7F). */
        a = (uint16_t)(ea(c) & 0x7f);
        c->acc = dm_rd(c, a);
        break;
    case 0x09: {
        /* SMMR: store the MMR at dma to successive program addresses.
         * The source MMR is fixed: only the destination (#addr)
         * advances (manual 6.3 SMMR).  Repeat total 2n. */
        uint16_t pfc = fetch(c);
        a = (uint16_t)(ea(c) & 0x7f);
        while (c->rptc > -1) {
            dm_wr(c, pfc, dm_rd(c, a));
            pfc++;
            if (c->rptc-- > 0)
                c->cycles += 2;
        }
        break;
    }
    case 0x0A:
        /* SUBC: conditional subtract, the divide step (audit #24:
         * SUBC affects C and OV, no saturation). */
        a = ea(c);
        d = dm_rd(c, a);
        {
            uint32_t b = (uint32_t)d << 15, A = c->acc;
            uint64_t r = (uint64_t)A - b;
            uint32_t res = (uint32_t)r;
            c->c = !((r >> 32) & 1);
            if ((A ^ b) & (A ^ res) & 0x80000000u)
                c->ov = 1;
            c->acc = (int32_t)res >= 0 ? (res << 1) + 1 : A << 1;
        }
        break;
    case 0x0B:
        /* RPT dma: repeat count from data memory; the next instruction
         * (at pc) is the repeated one. */
        a = ea(c);
        c->rptc = dm_rd(c, a);
        c->rpt_start = c->rpt_end = c->pc;
        break;
    case 0x0C: {
        /* OUT: with RPT the port address increments per access
         * (manual 6.3 IN/OUT). */
        uint16_t port = fetch(c);
        if (!c->rep_cont)
            c->io_rep = 0;
        else
            c->io_rep++;
        port = (uint16_t)(port + c->io_rep);
        a = ea(c);
        io_write(c, port, dm_rd(c, a));
        break;
    }
    case 0x0D:
        /* LDP dma: load data-page pointer from data memory. */
        a = ea(c);
        c->dp = (dm_rd(c, a) & 0x1ff) << 7;
        break;
    case 0x0E:
        /* LST #0: load ST0.  ea() may change ARB via an ARP switch, so
         * ARB is saved and restored around it (orig L365).  INTM is
         * NOT loaded by LST #0 (only ARP/OV/OVM/DP come from the word). */
        {
            int arb0 = c->arb;
            a = ea(c);
            c->arb = arb0;
        }
        d = dm_rd(c, a);
        c->arp = d >> 13;
        c->ov = (d >> 12) & 1;
        c->ovm = (d >> 11) & 1;
        c->dp = (d & 0x1ff) << 7;
        break;
    case 0x0F:
        /* LST #1: load ST1 (ARB and ARP both come from the word).
         * CNF is in ST1, so this changes the fetch mapping. */
        blk_state_changed(c);
        a = ea(c);
        d = dm_rd(c, a);
        c->arb = d >> 13;
        c->arp = d >> 13;
        c->cnf = (d >> 12) & 1;
        c->tc = (d >> 11) & 1;
        c->sxm = (d >> 10) & 1;
        c->c = (d >> 9) & 1;
        c->hm = (d >> 6) & 1;
        c->xf = (d >> 4) & 1;
        c->pm = d & 3;
        break;
    }
}

/* High bytes 0x10..0x3F: LACC / ADD / SUB with shift, and BIT.
 * The shift is the high nibble (op>>8)&0xF for LACC/ADD/SUB, and BIT
 * tests bit 15-shift of the operand. */
static void exec_hi_10_3f(C5x *c, uint16_t op)
{
    uint16_t a;
    int hi = op >> 8;
    if (hi >= 0x10 && hi <= 0x1F) {
        /* LACC dma,s */
        a = ea(c);
        c->acc = ext(c, dm_rd(c, a), hi & 0xF);
    } else if (hi >= 0x20 && hi <= 0x2F) {
        /* ADD dma,s */
        a = ea(c);
        c->acc = do_add(c, c->acc, ext(c, dm_rd(c, a), hi & 0xF), 0, 0);
    } else if (hi >= 0x30 && hi <= 0x3F) {
        /* SUB dma,s */
        a = ea(c);
        c->acc = do_sub(c, c->acc, ext(c, dm_rd(c, a), hi & 0xF), 0, 0);
    }
    /* NOTE: high bytes 0x40..0x4F are also BIT; they live in
     * exec_hi_40_5f, not here. */
}

static void exec_hi_40_5f(C5x *c, uint16_t op);
static void exec_hi_60_7f(C5x *c, uint16_t op);
static void exec_hi_80_9f(C5x *c, uint16_t op);
static void exec_hi_a0_af(C5x *c, uint16_t op);
static void exec_hi_b0_bf(C5x *c, uint16_t op);
static void exec_hi_e0_ff(C5x *c, uint16_t op);

/* Execute one already-fetched opcode (PERF2 stage 3): the dispatch
 * ladder plus the family call, without the fetch, the diagnostics
 * branch, or the base-cycle charge.  exec1() below is the fetch +
 * exec1_op() wrapper used by the main loop and delay_slot(); the RPTB
 * block replay calls exec1_op() directly with the decoded opcode, so a
 * replayed instruction skips the re-fetch and the re-dispatch setup
 * but executes byte-identical family code (ea/dm_rd/dm_wr, the cycle
 * additions inside the families, the second-word fetch for two-word
 * ops).  always_inline so the slow path keeps its current shape (the
 * ladder + the inlined families live in exec1 as before) and the
 * replay loop pays no extra call. */
static inline __attribute__((always_inline)) void exec1_op(C5x *c, uint16_t op)
{
    uint8_t hi = (uint8_t)(op >> 8);
    if (hi <= 0x0F)
        exec_hi_00_0f(c, op);
    else if (hi <= 0x3F)
        exec_hi_10_3f(c, op);
    else if (hi <= 0x5F)
        exec_hi_40_5f(c, op);
    else if (hi <= 0x7F)
        exec_hi_60_7f(c, op);
    else if (hi <= 0x9F)
        exec_hi_80_9f(c, op);
    else if (hi <= 0xAF)
        exec_hi_a0_af(c, op);
    else if (hi <= 0xBF)
        exec_hi_b0_bf(c, op);
    else if (hi >= 0xC0 && hi <= 0xDF) {
        /* MPY #k13: signed 13-bit immediate times TREG0. */
        int32_t k = op & 0x1fff;
        if (k & 0x1000)
            k -= 0x2000;
        c->preg = (uint32_t)((int32_t)(int16_t)c->treg0 * k);
    } else if (hi >= 0xE0)
        exec_hi_e0_ff(c, op);
    else
        c->status = RUN_BADOP;
}

static void exec1(C5x *c)
{
    uint16_t op;
    c->cur_pc = c->pc;
    /* Per-instruction diagnostics (hits / recent-PC ring / per-PC hits /
     * trace capture).  Gated by c5x_set_diag(): the C driver runs with
     * them off (it never reads these counters); the default is on so
     * the Python ctypes .so keeps its old behaviour. */
    if (c->diag) {
        c->hits[c->pc]++;
        c->pcring[c->pcring_i++ & 255] = c->pc;
        c->pc_hits[c->pc & 0xFFFF]++;
        if ((int32_t)c->pc == c->trace_pc && c->trace_n < TRACE_N) {
            c->trace_buf[c->trace_n].acc = c->acc;
            c->trace_buf[c->trace_n].ret = c->stack[c->sp];
            c->trace_buf[c->trace_n].ret2 = c->stack[(c->sp + 1) & 7];
            c->trace_buf[c->trace_n].cyc = c->cycles;
            c->trace_n++;
        }
    }
    op = c->op = fetch(c);
    c->cycles++; /* base cycle; the cycle model adds the rest in c5x_run */
    exec1_op(c, op);
}

/* High bytes 0x40..0x5F: BIT, multiply/accumulate, DBMR logic ops. */
static void exec_hi_40_5f(C5x *c, uint16_t op)
{
    uint16_t a, d, imm;
    int hi = op >> 8;
    switch (hi) {
    case 0x40: case 0x41: case 0x42: case 0x43: case 0x44: case 0x45:
    case 0x46: case 0x47: case 0x48: case 0x49: case 0x4A: case 0x4B:
    case 0x4C: case 0x4D: case 0x4E: case 0x4F:
        /* BIT dma,s: TC = bit (15 - shift) of the operand. */
        a = ea(c);
        c->tc = (dm_rd(c, a) >> (15 - (hi & 0xF))) & 1;
        break;
    case 0x50:
        /* MPYA: ACC += PREG (scaled); PREG = TREG0 * dma. */
        a = ea(c);
        d = dm_rd(c, a);
        c->acc = do_add(c, c->acc, pscale(c), 0, 0);
        c->preg = (uint32_t)((int32_t)(int16_t)c->treg0 * (int32_t)(int16_t)d);
        break;
    case 0x51:
        /* MPYS: ACC -= PREG (scaled); PREG = TREG0 * dma. */
        a = ea(c);
        d = dm_rd(c, a);
        c->acc = do_sub(c, c->acc, pscale(c), 0, 0);
        c->preg = (uint32_t)((int32_t)(int16_t)c->treg0 * (int32_t)(int16_t)d);
        break;
    case 0x52:
        /* SQRA: ACC += PREG; TREG0 = dma; PREG = dma * dma. */
        a = ea(c);
        d = dm_rd(c, a);
        c->acc = do_add(c, c->acc, pscale(c), 0, 0);
        set_t0(c, d);
        c->preg = (uint32_t)((int32_t)(int16_t)d * (int32_t)(int16_t)d);
        break;
    case 0x53:
        /* SQRS: ACC -= PREG; TREG0 = dma; PREG = dma * dma. */
        a = ea(c);
        d = dm_rd(c, a);
        c->acc = do_sub(c, c->acc, pscale(c), 0, 0);
        set_t0(c, d);
        c->preg = (uint32_t)((int32_t)(int16_t)d * (int32_t)(int16_t)d);
        break;
    case 0x54:
        /* MPY dma: PREG = TREG0 * dma (signed). */
        a = ea(c);
        d = dm_rd(c, a);
        c->preg = (uint32_t)((int32_t)(int16_t)c->treg0 * (int32_t)(int16_t)d);
        break;
    case 0x55:
        /* MPYU: PREG = TREG0 * dma (unsigned). */
        a = ea(c);
        d = dm_rd(c, a);
        c->preg = (uint32_t)c->treg0 * (uint32_t)d;
        break;
    case 0x56:
        c->status = RUN_BADOP;
        break;
    case 0x57: {
        /* BLDP: block move data -> program, BMAR as source.
         * Audit #15: BMAR is not written back (PFC <- BMAR, then
         * PFC <- MCS); the local pfc advances, BMAR does not. */
        uint16_t pfc = c->bmar;
        while (c->rptc > -1) {
            a = ea(c);
            pm_wr(c, pfc, dm_rd(c, a));
            pfc++;
            if (c->rptc-- > 0)
                c->cycles++;
        }
        break;
    }
    case 0x58:
        /* XPL dbmr: dma ^= DBMR; TC = (result == 0). */
        a = ea(c);
        d = (uint16_t)(dm_rd(c, a) ^ c->dbmr);
        c->tc = d == 0;
        dm_wr(c, a, d);
        break;
    case 0x59:
        /* OPL dbmr: dma |= DBMR; TC = (result == 0). */
        a = ea(c);
        d = (uint16_t)(dm_rd(c, a) | c->dbmr);
        c->tc = d == 0;
        dm_wr(c, a, d);
        break;
    case 0x5A:
        /* APL dbmr: dma &= DBMR; TC = (result == 0). */
        a = ea(c);
        d = (uint16_t)(dm_rd(c, a) & c->dbmr);
        c->tc = d == 0;
        dm_wr(c, a, d);
        break;
    case 0x5B:
        /* CPL dbmr: TC = (dma == DBMR); no write. */
        a = ea(c);
        c->tc = dm_rd(c, a) == c->dbmr;
        break;
    case 0x5C:
        /* XPL #lk: dma ^= imm; TC = (result == 0). */
        imm = fetch(c);
        a = ea(c);
        d = (uint16_t)(dm_rd(c, a) ^ imm);
        c->tc = d == 0;
        dm_wr(c, a, d);
        break;
    case 0x5D:
        /* OPL #lk. */
        imm = fetch(c);
        a = ea(c);
        d = (uint16_t)(dm_rd(c, a) | imm);
        c->tc = d == 0;
        dm_wr(c, a, d);
        break;
    case 0x5E:
        /* APL #lk. */
        imm = fetch(c);
        a = ea(c);
        d = (uint16_t)(dm_rd(c, a) & imm);
        c->tc = d == 0;
        dm_wr(c, a, d);
        break;
    case 0x5F:
        /* CPL #lk: TC = (dma == imm); no write. */
        imm = fetch(c);
        a = ea(c);
        c->tc = dm_rd(c, a) == imm;
        break;
    }
}

/* High bytes 0x60..0x7F: add/sub variants, loads, logic, branches. */
static void exec_hi_60_7f(C5x *c, uint16_t op)
{
    uint16_t a, d, imm;
    switch (op >> 8) {
    case 0x60:
        /* ADDC: ACC += dma + C. */
        a = ea(c);
        c->acc = do_add(c, c->acc, dm_rd(c, a), c->c, 0);
        break;
    case 0x61:
        /* ADD dma,16: ACC += dma << 16 (16-bit form: carry sets C). */
        a = ea(c);
        c->acc = do_add(c, c->acc, (uint32_t)dm_rd(c, a) << 16, 0, 1);
        break;
    case 0x62:
        /* ADDS: ACC += dma (zero-extended, clears ACCH). */
        a = ea(c);
        c->acc = do_add(c, c->acc, dm_rd(c, a), 0, 0);
        break;
    case 0x63:
        /* ADDT: ACC += dma << TREG1. */
        a = ea(c);
        c->acc = do_add(c, c->acc, ext(c, dm_rd(c, a), c->treg1 & 0xF), 0, 0);
        break;
    case 0x64:
        /* SUBB: ACC -= dma + !C. */
        a = ea(c);
        c->acc = do_sub(c, c->acc, dm_rd(c, a), !c->c, 0);
        break;
    case 0x65:
        /* SUB dma,16 (16-bit form). */
        a = ea(c);
        c->acc = do_sub(c, c->acc, (uint32_t)dm_rd(c, a) << 16, 0, 1);
        break;
    case 0x66:
        /* SUBS. */
        a = ea(c);
        c->acc = do_sub(c, c->acc, dm_rd(c, a), 0, 0);
        break;
    case 0x67:
        /* SUBT: ACC -= dma << TREG1. */
        a = ea(c);
        c->acc = do_sub(c, c->acc, ext(c, dm_rd(c, a), c->treg1 & 0xF), 0, 0);
        break;
    case 0x68:
        /* ZALR: ACC = dma << 16 | 0x8000 (rounding bit). */
        a = ea(c);
        c->acc = ((uint32_t)dm_rd(c, a) << 16) | 0x8000;
        break;
    case 0x69:
        /* LACL dma. */
        a = ea(c);
        c->acc = dm_rd(c, a);
        break;
    case 0x6A:
        /* LACC dma,16: ACC = dma << 16. */
        a = ea(c);
        c->acc = (uint32_t)dm_rd(c, a) << 16;
        break;
    case 0x6B:
        /* LACT: ACC = dma << TREG1. */
        a = ea(c);
        c->acc = ext(c, dm_rd(c, a), c->treg1 & 0xF);
        break;
    case 0x6C:
        /* XOR dma. */
        a = ea(c);
        c->acc ^= dm_rd(c, a);
        break;
    case 0x6D:
        /* OR dma. */
        a = ea(c);
        c->acc |= dm_rd(c, a);
        break;
    case 0x6E:
        /* AND dma (clears ACCH: the 16-bit operand is zero-extended). */
        a = ea(c);
        c->acc &= dm_rd(c, a);
        break;
    case 0x6F:
        /* BITT: TC = bit (15 - TREG2) of dma.  The (~treg2 & 0xF)
         * spelling is the original's (orig L~398). */
        a = ea(c);
        c->tc = (dm_rd(c, a) >> (~c->treg2 & 0xF)) & 1;
        break;
    case 0x70:
        /* LTA: ACC += PREG; TREG0 = dma. */
        a = ea(c);
        d = dm_rd(c, a);
        c->acc = do_add(c, c->acc, pscale(c), 0, 0);
        set_t0(c, d);
        break;
    case 0x71:
        /* LTP: ACC = PREG (scaled); TREG0 = dma. */
        a = ea(c);
        d = dm_rd(c, a);
        c->acc = (uint32_t)pscale(c);
        set_t0(c, d);
        break;
    case 0x72:
        /* LTD: ACC += PREG; TREG0 = dma; DMOV dma -> dma+1. */
        a = ea(c);
        d = dm_rd(c, a);
        c->acc = do_add(c, c->acc, pscale(c), 0, 0);
        set_t0(c, d);
        dmov_wr(c, a, d);
        break;
    case 0x73:
        /* LT: TREG0 = dma. */
        a = ea(c);
        set_t0(c, dm_rd(c, a));
        break;
    case 0x74:
        /* LTS: ACC -= PREG; TREG0 = dma. */
        a = ea(c);
        d = dm_rd(c, a);
        c->acc = do_sub(c, c->acc, pscale(c), 0, 0);
        set_t0(c, d);
        break;
    case 0x75:
        /* LPH: PREG high half = dma. */
        a = ea(c);
        c->preg = (c->preg & 0xFFFF) | ((uint32_t)dm_rd(c, a) << 16);
        break;
    case 0x76:
        /* PSHD: push dma. */
        a = ea(c);
        push(c, dm_rd(c, a));
        break;
    case 0x77:
        /* DMOV: dma -> dma+1, only within on-chip RAM (audit #16). */
        a = ea(c);
        dmov_wr(c, a, dm_rd(c, a));
        break;
    case 0x78:
        /* ADRK: AR[ARP] += k8 (low byte, unsigned). */
        upd_ar(c, c->arp, op & 0xff);
        break;
    case 0x79:
        /* B: ea() runs for its addressing side effects, then PC = imm. */
        imm = fetch(c);
        ea(c);
        c->pc = imm;
        break;
    case 0x7A:
        /* CALL: push return, PC = imm. */
        imm = fetch(c);
        ea(c);
        push(c, c->pc);
        c->pc = imm;
        break;
    case 0x7B: {
        /* BANZ: branch if AR[ARP] != 0.  The take decision is made
         * before ea() (orig L~412), so an ARP-switching addressing
         * mode does not change which AR was tested. */
        imm = fetch(c);
        int take = c->ar[c->arp] != 0;
        ea(c);
        if (take)
            c->pc = imm;
        break;
    }
    case 0x7C:
        /* SBRK: AR[ARP] -= k8. */
        upd_ar(c, c->arp, -(int)(op & 0xff));
        break;
    case 0x7D:
        /* BD: delayed branch; two slot words run before the jump. */
        imm = fetch(c);
        ea(c);
        delay_slot(c, c->pc);
        c->pc = imm;
        break;
    case 0x7E:
        /* CALLD: delayed call; return address is pc+2 (past the two
         * slot words), pushed before the slot runs. */
        imm = fetch(c);
        ea(c);
        push(c, (uint16_t)(c->pc + 2));
        delay_slot(c, c->pc);
        c->pc = imm;
        break;
    case 0x7F: {
        /* BANZD: delayed BANZ; take decision before ea(), as in BANZ. */
        imm = fetch(c);
        int take = c->ar[c->arp] != 0;
        ea(c);
        delay_slot(c, c->pc);
        if (take)
            c->pc = imm;
        break;
    }
    }
}

/* High bytes 0x80..0x9F: SAR, SAMM, LMMR, POPD, MAR, SPL/SPH, SST, SACL/SACH. */
static void exec_hi_80_9f(C5x *c, uint16_t op)
{
    uint16_t a, d;
    int hi = op >> 8;
    if (hi >= 0x80 && hi <= 0x87) {
        /* SAR: store AR[(op>>8)] to data memory.  The AR value is read
         * before ea(), so an ARP-switching mode stores the old AR. */
        d = c->ar[(op >> 8) & 7];
        a = ea(c);
        dm_wr(c, a, d);
    } else if (hi == 0x88) {
        /* SAMM: store ACC low half to page-0 data memory. */
        a = (uint16_t)(ea(c) & 0x7f);
        dm_wr(c, a, (uint16_t)c->acc);
    } else if (hi == 0x89) {
        /* LMMR: load the (fixed) destination MMR from successive
         * program addresses (manual 6.3 LMMR).  Repeat total 2n. */
        uint16_t pfc = fetch(c);
        a = (uint16_t)(ea(c) & 0x7f);
        while (c->rptc > -1) {
            dm_wr(c, a, dm_rd(c, pfc));
            pfc++;
            if (c->rptc-- > 0)
                c->cycles += 2;
        }
    } else if (hi == 0x8A) {
        /* POPD: pop the stack to data memory. */
        a = ea(c);
        dm_wr(c, a, pop(c));
    } else if (hi == 0x8B) {
        /* MAR: no-op except for the addressing-mode side effect, and
         * only when bit 7 is set (indirect). */
        if (op & 0x80)
            ea(c);
    } else if (hi == 0x8C) {
        /* SPL: store PREG low half (scaled). */
        a = ea(c);
        dm_wr(c, a, (uint16_t)pscale(c));
    } else if (hi == 0x8D) {
        /* SPH: store PREG high half (scaled). */
        a = ea(c);
        dm_wr(c, a, (uint16_t)((uint32_t)pscale(c) >> 16));
    } else if (hi == 0x8E) {
        /* SST #0: store ST0, page-0 direct addressing. */
        a = ea_p0(c);
        dm_wr(c, a, st0_get(c));
    } else if (hi == 0x8F) {
        /* SST #1: store ST1, page-0 direct addressing. */
        a = ea_p0(c);
        dm_wr(c, a, st1_get(c));
    } else if (hi >= 0x90 && hi <= 0x97) {
        /* SACL: store ACC low half, shifted left by (op>>8)&7. */
        a = ea(c);
        dm_wr(c, a, (uint16_t)(c->acc << ((op >> 8) & 7)));
    } else if (hi >= 0x98 && hi <= 0x9F) {
        /* SACH: store ACC high half, shifted left by (op>>8)&7. */
        a = ea(c);
        dm_wr(c, a, (uint16_t)((c->acc << ((op >> 8) & 7)) >> 16));
    }
}

/* High bytes 0xA0..0xAF: NORM, MAC/MACD, BLPD, TBLR/TBLW, BLDD,
 * MADS/MADD, SPLK, IN. */
static void exec_hi_a0_af(C5x *c, uint16_t op)
{
    uint16_t a, d, imm;
    int hi = op >> 8;
    switch (hi) {
    case 0xA0: {
        /* NORM: shift ACC left until bits 31/30 differ (or ACC == 0).
         * Audit #23: the AR is modified only when the ACC is shifted,
         * so ea() runs only on the shifting path. */
        int t = (int)(((c->acc >> 31) ^ (c->acc >> 30)) & 1);
        if (c->acc == 0)
            t = 1;
        if (!t)
            ea(c);
        if (t)
            c->tc = 1;
        else {
            c->tc = 0;
            c->acc <<= 1;
        }
        break;
    }
    case 0xA1:
        c->status = RUN_BADOP;
        break;
    case 0xA2: case 0xA3: {
        /* MAC / MACD: ACC += PREG; TREG0 = dma; PREG = dma * pma.
         * MACD additionally DMOVs dma -> dma+1.  The do-while runs
         * at least once even with rptc == -1 (orig L~438). */
        uint16_t pfc = fetch(c);
        do {
            a = ea(c);
            d = dm_rd(c, a);
            c->acc = do_add(c, c->acc, pscale(c), 0, 0);
            set_t0(c, d);
            c->preg = (uint32_t)((int32_t)(int16_t)d *
                                 (int32_t)(int16_t)pm_rd(c, pfc));
            pfc++;
            if ((op >> 8) == 0xA3)
                dmov_wr(c, a, d);
            if (c->rptc > -1) {
                if (c->rptc-- > 0)
                    c->cycles++;
            }
        } while (c->rptc > -1);
        break;
    }
    case 0xA4: {
        /* BLPD bmar,dma: program (BMAR) -> data.  Audit #15: BMAR is
         * not written back. */
        uint16_t pfc = c->bmar;
        while (c->rptc > -1) {
            a = ea(c);
            dm_wr(c, a, pm_rd(c, pfc));
            pfc++;
            if (c->rptc-- > 0)
                c->cycles++;
        }
        break;
    }
    case 0xA5: {
        /* BLPD #pma,dma. */
        uint16_t pfc = fetch(c);
        while (c->rptc > -1) {
            a = ea(c);
            dm_wr(c, a, pm_rd(c, pfc));
            pfc++;
            if (c->rptc-- > 0)
                c->cycles++;
        }
        break;
    }
    case 0xA6: {
        /* TBLR: program (ACC) -> data.  ACC is unchanged (PFC is
         * internal; orig L448). */
        uint16_t pfc = (uint16_t)c->acc;
        while (c->rptc > -1) {
            a = ea(c);
            dm_wr(c, a, pm_rd(c, pfc));
            pfc++;
            if (c->rptc-- > 0)
                c->cycles++;
        }
        (void)pfc;
        break;
    }
    case 0xA7: {
        /* TBLW: data -> program (ACC).  ACC is unchanged. */
        uint16_t pfc = (uint16_t)c->acc;
        while (c->rptc > -1) {
            a = ea(c);
            pm_wr(c, pfc, dm_rd(c, a));
            pfc++;
            if (c->rptc-- > 0)
                c->cycles++;
        }
        (void)pfc;
        break;
    }
    case 0xA8: {
        /* BLDD #lk,dma: data -> data. */
        uint16_t pfc = fetch(c);
        while (c->rptc > -1) {
            a = ea(c);
            dm_wr(c, a, dm_rd(c, pfc));
            pfc++;
            if (c->rptc-- > 0)
                c->cycles++;
        }
        break;
    }
    case 0xA9: {
        /* BLDD dma,#lk: data -> data (reversed direction). */
        uint16_t pfc = fetch(c);
        while (c->rptc > -1) {
            a = ea(c);
            dm_wr(c, pfc, dm_rd(c, a));
            pfc++;
            if (c->rptc-- > 0)
                c->cycles++;
        }
        break;
    }
    case 0xAA: case 0xAB: {
        /* MADS / MADD: like MAC but the program address comes from
         * BMAR, and TREG0 is written directly -- audit N-1: no TRM
         * mirror (set_t0 is NOT used).  MADD additionally DMOVs.
         * Audit #15: BMAR is not written back. */
        uint16_t pfc = c->bmar;
        do {
            a = ea(c);
            d = dm_rd(c, a);
            c->acc = do_add(c, c->acc, pscale(c), 0, 0);
            c->treg0 = d;
            c->preg = (uint32_t)((int32_t)(int16_t)d *
                                 (int32_t)(int16_t)pm_rd(c, pfc));
            pfc++;
            if ((op >> 8) == 0xAB)
                dmov_wr(c, a, d);
            if (c->rptc > -1) {
                if (c->rptc-- > 0)
                    c->cycles++;
            }
        } while (c->rptc > -1);
        break;
    }
    case 0xAC: {
        /* BLDD bmar,dma.  Audit #15: BMAR is not written back. */
        uint16_t pfc = c->bmar;
        while (c->rptc > -1) {
            a = ea(c);
            dm_wr(c, a, dm_rd(c, pfc));
            pfc++;
            if (c->rptc-- > 0)
                c->cycles++;
        }
        break;
    }
    case 0xAD: {
        /* BLDD dma,bmar.  Audit #15: BMAR is not written back. */
        uint16_t pfc = c->bmar;
        while (c->rptc > -1) {
            a = ea(c);
            dm_wr(c, pfc, dm_rd(c, a));
            pfc++;
            if (c->rptc-- > 0)
                c->cycles++;
        }
        break;
    }
    case 0xAE:
        /* SPLK: store immediate to data memory.  NOTE the order: ea()
         * runs BEFORE the immediate is fetched here (orig L~465),
         * unlike the 0x5C..0x5F logic-immediate forms. */
        a = ea(c);
        imm = fetch(c);
        dm_wr(c, a, imm);
        break;
    case 0xAF: {
        /* IN: with RPT the port address increments per access
         * (manual 6.3 IN/OUT), mirroring OUT (0x0C). */
        uint16_t port = fetch(c);
        if (!c->rep_cont)
            c->io_rep = 0;
        else
            c->io_rep++;
        port = (uint16_t)(port + c->io_rep);
        a = ea(c);
        dm_wr(c, a, io_read(c, port));
        break;
    }
    }
}

/* High bytes 0xB0..0xBF: LAR #k8, ADDK/LACK/SUBK, RPT #k8, LDP #k9,
 * and the 0xBE / 0xBF sub-decoders. */
static void exec_hi_b0_bf(C5x *c, uint16_t op)
{
    int hi = op >> 8;
    if (hi >= 0xB0 && hi <= 0xB7) {
        /* LAR #k8: AR[(op>>8)] = low byte. */
        c->ar[(op >> 8) & 7] = (uint16_t)(op & 0xff);
        if (((op >> 8) & 7) == 0)
            c->ar0_dirty = 1;
    } else if (hi == 0xB8) {
        /* ADDK: ACC += k8. */
        c->acc = do_add(c, c->acc, op & 0xff, 0, 0);
    } else if (hi == 0xB9) {
        /* LACK: ACC = k8 (zero-extended). */
        c->acc = op & 0xff;
    } else if (hi == 0xBA) {
        /* SUBK: ACC -= k8. */
        c->acc = do_sub(c, c->acc, op & 0xff, 0, 0);
    } else if (hi == 0xBB) {
        /* RPT #k8: the next instruction (at pc) is the repeated one. */
        c->rptc = op & 0xff;
        c->rpt_start = c->rpt_end = c->pc;
    } else if (hi == 0xBC || hi == 0xBD) {
        /* LDP #k9: DP = low 9 bits << 7. */
        c->dp = (op & 0x1ff) << 7;
    } else if (hi == 0xBE) {
        exec_be(c);
    } else if (hi == 0xBF) {
        exec_bf(c);
    }
}

/* 0xBE sub-decoder, part 1: accumulator ops (low byte 0x00..0x1F).
 * Unlisted low bytes in this range are BADOP, as in the original's
 * default arm (they cannot match the INTR pattern 0x60..0x7F). */
static void exec_be_acc(C5x *c)
{
    uint16_t op = c->op;
    uint32_t t;
    switch (op & 0xff) {
    case 0x00:
        /* ABS: |ACC|, saturating at 0x80000000 under OVM. */
        if (c->acc == 0x80000000u) {
            c->ov = 1;
            c->c = 0;
            c->acc = c->ovm ? 0x7fffffffu : 0x80000000u;
        } else {
            if ((int32_t)c->acc < 0)
                c->acc = (uint32_t)(-(int32_t)c->acc);
            c->c = 0;
        }
        break;
    case 0x01: c->acc = ~c->acc; break; /* CMPL */
    case 0x02:
        /* NEG: -ACC, saturating at 0x80000000 under OVM; C = (result == 0). */
        if (c->acc == 0x80000000u) {
            c->ov = 1;
            c->c = 0;
            c->acc = c->ovm ? 0x7fffffffu : 0x80000000u;
        } else {
            c->acc = (uint32_t)(-(int32_t)c->acc);
            c->c = c->acc == 0;
        }
        break;
    case 0x03: c->acc = (uint32_t)pscale(c); break;              /* ACC = PREG (scaled) */
    case 0x04: c->acc = do_add(c, c->acc, pscale(c), 0, 0); break; /* ACC += PREG (scaled) */
    case 0x05: c->acc = do_sub(c, c->acc, pscale(c), 0, 0); break; /* ACC -= PREG (scaled) */
    case 0x09: c->c = (int)(c->acc >> 31); c->acc <<= 1; break;  /* ROL */
    case 0x0A: /* ROR */
        c->c = (int)(c->acc & 1);
        c->acc = c->sxm ? (uint32_t)((int32_t)c->acc >> 1) : c->acc >> 1;
        break;
    case 0x0C: /* ROLC */
        t = (uint32_t)c->c;
        c->c = (int)(c->acc >> 31);
        c->acc = (c->acc << 1) | t;
        break;
    case 0x0D: /* RORC */
        t = (uint32_t)c->c;
        c->c = (int)(c->acc & 1);
        c->acc = (c->acc >> 1) | (t << 31);
        break;
    case 0x10: c->acc = do_add(c, c->acc, c->accb, 0, 0); break;     /* ADDB */
    case 0x11: c->acc = do_add(c, c->acc, c->accb, c->c, 0); break;  /* ADDC (ACCB) */
    case 0x12: c->acc &= c->accb; break;                             /* ANDB */
    case 0x13: c->acc |= c->accb; break;                             /* ORB */
    case 0x14: /* ROLB: 64-bit rotate left through C */
        { uint32_t a = c->acc, b = c->accb, cc = (uint32_t)c->c;
          c->acc = (a << 1) | (b >> 31);
          c->accb = (b << 1) | cc;
          c->c = (int)(a >> 31); }
        break;
    case 0x15: /* RORB: 64-bit rotate right through C */
        { uint32_t a = c->acc, b = c->accb, cc = (uint32_t)c->c;
          c->accb = (b >> 1) | (a << 31);
          c->acc = (a >> 1) | (cc << 31);
          c->c = (int)(b & 1); }
        break;
    case 0x16: /* SFLB: 64-bit shift left (ACCB bit 31 feeds ACC) */
        { uint32_t a = c->acc, b = c->accb;
          c->acc = (a << 1) | (b >> 31);
          c->accb = b << 1;
          c->c = (int)(a >> 31); }
        break;
    case 0x17: /* SFRB: 64-bit shift right (ACC bit 31 feeds ACCB) */
        { uint32_t a = c->acc, b = c->accb;
          c->accb = (b >> 1) | (a << 31);
          c->acc = c->sxm ? (uint32_t)((int32_t)a >> 1) : a >> 1;
          c->c = (int)(b & 1); }
        break;
    case 0x18: c->acc = do_sub(c, c->acc, c->accb, 0, 0); break;     /* SUBB */
    case 0x19:
        /* SBBB: ACC -= ACCB + !C.  Affects C only: no OV, no
         * saturation (SPRU056D p.6-233; orig L~542). */
        { uint64_t r = (uint64_t)c->acc - (uint64_t)c->accb -
                       (uint64_t)(!c->c);
          c->c = !((r >> 32) & 1);
          c->acc = (uint32_t)r; }
        break;
    case 0x1A: c->acc ^= c->accb; break;                             /* XORB */
    case 0x1B: /* MAX: larger of ACC/ACCB ends in ACCB, C = (ACC >= ACCB) */
        if ((int32_t)c->acc >= (int32_t)c->accb) {
            c->accb = c->acc;
            c->c = 1;
        } else {
            c->acc = c->accb;
            c->c = 0;
        }
        break;
    case 0x1C: /* MIN: smaller of ACC/ACCB ends in ACC, C = (ACC < ACCB) */
        if ((int32_t)c->acc >= (int32_t)c->accb) {
            c->acc = c->accb;
            c->c = 0;
        } else {
            c->accb = c->acc;
            c->c = 1;
        }
        break;
    case 0x1D: t = c->acc; c->acc = c->accb; c->accb = t; break;      /* SWAP */
    case 0x1E: c->accb = c->acc; break;                              /* SACB */
    case 0x1F: c->acc = c->accb; break;                              /* LACB */
    default:
        c->status = RUN_BADOP;
    }
}

/* 0xBE sub-decoder, part 2: control, status, and immediate ops
 * (low byte 0x20..0xFF), including the INTR default arm. */
static void exec_be_ctrl(C5x *c)
{
    uint16_t op = c->op;
    uint16_t imm;
    switch (op & 0xff) {
    case 0x20: c->pc = (uint16_t)c->acc; break;                      /* BACC */
    case 0x21: /* BACCD: delayed branch to ACC */
        { uint16_t p = (uint16_t)c->acc;
          delay_slot(c, c->pc);
          c->pc = p; }
        break;
    case 0x22: c->idle = 1; break; /* IDLE */
    case 0x23: c->idle = 2; break; /* IDLE2: peripherals stopped, only
                                      RS/NMI/INT1-4 wake the CPU (4.10.2) */
    case 0x30: push(c, c->pc); c->pc = (uint16_t)c->acc; break;      /* CALA */
    case 0x32: c->acc = pop(c); break;                               /* POP */
    case 0x38: c->pc = pop(c); restore_ctx(c); break;                /* RETI */
    case 0x3A: c->pc = pop(c); restore_ctx(c); c->intm = 0; break;   /* RETE */
    case 0x3C: push(c, (uint16_t)c->acc); break;                     /* PSHA */
    case 0x3D: /* CALAD: delayed call to ACC; return is pc+2 */
        { uint16_t p = (uint16_t)c->acc;
          push(c, (uint16_t)(c->pc + 2));
          delay_slot(c, c->pc);
          c->pc = p; }
        break;
    case 0x40: c->intm = 0; c->int_inh = 1; break; /* EINT (+1-cycle inh.) */
    case 0x41: c->intm = 1; break;                               /* DINT */
    case 0x42: c->ovm = 0; break;  /* ROVM */
    case 0x43: c->ovm = 1; break;  /* SOVM */
    case 0x44: blk_state_changed(c); c->cnf = 0; break;  /* RCNF */
    case 0x45: blk_state_changed(c); c->cnf = 1; break;  /* SCNF */
    case 0x46: c->sxm = 0; break;  /* RSXM */
    case 0x47: c->sxm = 1; break;  /* SSXM */
    case 0x48: c->hm = 0; break;   /* RHM */
    case 0x49: c->hm = 1; break;   /* SHM */
    case 0x4A: c->tc = 0; break;   /* RTC */
    case 0x4B: c->tc = 1; break;   /* STC */
    case 0x4C: c->xf = 0; break;   /* RXF */
    case 0x4D: c->xf = 1; break;   /* SXF */
    case 0x4E: c->c = 0; break;    /* RCB */
    case 0x4F: c->c = 1; break;    /* SCB */
    case 0x51:
        /* Push PC, jump to IPTR-relative vector 0x22.
         * NOTE: no INTM set and no context shadow here (orig L~568),
         * unlike INTR for INT1-INT4 below and unlike 0x52. */
        push(c, c->pc);
        c->pc = (uint16_t)((c->iptr << 11) | 0x22);
        break;
    case 0x52:
        /* NMI: push PC, jump to vector 0x24, mask interrupts. */
        push(c, c->pc);
        c->pc = (uint16_t)((c->iptr << 11) | 0x24);
        c->intm = 1;
        break;
    case 0x58: c->preg = 0; break;              /* PREG = 0 */
    case 0x59: c->acc = 0; c->preg = 0; break;  /* ACC = 0, PREG = 0 */
    case 0x5A:
        /* SATH: if TREG1 bit 4 set, ACC >>= 16 (sign per SXM). */
        if (c->treg1 & 0x10)
            c->acc = c->sxm ? (uint32_t)((int32_t)c->acc >> 16) : c->acc >> 16;
        break;
    case 0x5B: {
        /* SATL: ACC >>= (TREG1 & 0xF) (sign per SXM). */
        uint32_t t = c->treg1 & 0xF;
        c->acc = c->sxm ? (uint32_t)((int32_t)c->acc >> t) : c->acc >> t;
        break;
    }
    case 0x80:
        /* MPY #lk: PREG = TREG0 * imm. */
        imm = fetch(c);
        c->preg = (uint32_t)((int32_t)(int16_t)c->treg0 * (int32_t)(int16_t)imm);
        break;
    case 0x81:
        /* AND #lk,16: ACC &= imm << 16. */
        imm = fetch(c);
        c->acc &= (uint32_t)imm << 16;
        break;
    case 0x82:
        /* OR #lk,16. */
        imm = fetch(c);
        c->acc |= (uint32_t)imm << 16;
        break;
    case 0x83:
        /* XOR #lk,16. */
        imm = fetch(c);
        c->acc ^= (uint32_t)imm << 16;
        break;
    case 0xC4:
        /* RPT #lk: repeat count from the next word. */
        c->rptc = fetch(c);
        c->rpt_start = c->rpt_end = c->pc;
        break;
    case 0xC5:
        /* RPTZ #lk: like RPT, and ACC = PREG = 0. */
        c->rptc = fetch(c);
        c->rpt_start = c->rpt_end = c->pc;
        c->acc = 0;
        c->preg = 0;
        break;
    case 0xC6:
        /* RPTB: repeat block; PAER = operand = address of the last
         * loop word (manual 4.7, Example 4-8: RPTB END_LOOP-1). */
        imm = fetch(c);
        c->braf = 1;
        c->pasr = c->pc;
        c->paer = imm;
        break;
    default:
        if ((op & 0xe0) == 0x60) {
            /* INTR k: software interrupt.  Vector = K*2, IPTR-relative.
             * INTR for INT1-INT4 (K=1,2,3,9) behaves like the external
             * interrupt, context shadow included (manual 4.8.7).
             * If ivec_ind is set for that vector (checked against both
             * the audited table and the legacy table), the jump goes
             * via dmem[ivec_ind[i]] instead. */
            uint16_t v = (uint16_t)((op & 0x1f) << 1);
            int i;
            push(c, c->pc);
            c->intm = 1;
            c->pc = (uint16_t)((c->iptr << 11) | v);
            if (v == 0x02 || v == 0x04 || v == 0x06 || v == 0x12)
                save_ctx(c);
            for (i = 0; i < N_INT; i++) {
                if (ivec[i] == v && c->ivec_ind[i]) {
                    c->pc = dm_rd(c, c->ivec_ind[i]);
                    save_ctx(c);
                    break;
                }
            }
            if (i == N_INT) {
                for (i = 0; i < N_INT; i++) {
                    if (ivec_legacy[i] == v && c->ivec_ind[i]) {
                        c->pc = dm_rd(c, c->ivec_ind[i]);
                        save_ctx(c);
                        break;
                    }
                }
            }
            break;
        }
        c->status = RUN_BADOP;
    }
}

/* 0xBE sub-decoder: dispatch on the low byte. */
static void exec_be(C5x *c)
{
    if ((c->op & 0xff) < 0x20)
        exec_be_acc(c);
    else
        exec_be_ctrl(c);
}

/* 0xBF sub-decoder: PM select, LAR #lk, CMPR, long-immediate ALU ops. */
static void exec_bf(C5x *c)
{
    uint16_t op = c->op, imm;
    int sh = op & 0xf;
    int32_t d;
    switch (op & 0xff) {
    case 0x00: case 0x01: case 0x02: case 0x03:
        /* SPM k: PM = low 2 bits. */
        c->pm = op & 3;
        break;
    case 0x08: case 0x09: case 0x0A: case 0x0B:
    case 0x0C: case 0x0D: case 0x0E: case 0x0F:
        /* LAR #lk: AR[(op&7)] = next word. */
        imm = fetch(c);
        c->ar[op & 7] = imm;
        if ((op & 7) == 0)
            c->ar0_dirty = 1;
        break;
    case 0x44: case 0x45: case 0x46: case 0x47: {
        /* CMPR: compare AR[ARP] against ARCR (or AR0 when the
         * cmpr_ar0 experiment is on).  Mode: 0 ==, 1 <, 2 >, 3 !=. */
        uint16_t r = c->ar[c->arp];
        int m = op & 3;
        uint16_t cmpv = c->cmpr_ar0 ? c->ar[0] : c->arcr;
        c->tc = m == 0 ? r == cmpv : m == 1 ? r < cmpv
                 : m == 2 ? r > cmpv : r != cmpv;
        break;
    }
    default:
        /* NOTE (orig L~585): the original has an empty if here --
         * `if (op >= 0xBF80 && op <= 0xBFFF) {}` -- followed by a
         * bare block that always runs.  The empty branch is dropped;
         * the block below is that block, unchanged. */
        {
            int hi = op & 0xf0;
            if (hi >= 0x80 && hi <= 0xD0) {
                /* Long-immediate ALU: LACC/ADD/SUB/AND/OR/XOR #lk,sh. */
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
                /* SFTA: ACC >>= (sh + 1), sign per SXM. */
                sh = sh + 1;
                d = (int32_t)c->acc;
                c->acc = c->sxm ? (uint32_t)(d >> sh) : c->acc >> sh;
            } else {
                c->status = RUN_BADOP;
            }
        }
    }
}

/* High bytes 0xE0..0xFF: conditional branches/calls/returns and XC. */
static void exec_hi_e0_ff(C5x *c, uint16_t op)
{
    uint16_t imm;
    int n;
    int hi = op >> 8;
    if (hi >= 0xE0 && hi <= 0xE3) {
        /* BCND: branch if cond; bit 1 (op & 2) clears OV on the taken path. */
        imm = fetch(c);
        if (cond(c)) {
            c->pc = imm;
            if (op & 2)
                c->ov = 0;
        }
    } else if ((hi >= 0xE4 && hi <= 0xE7) || (hi >= 0xF4 && hi <= 0xF7)) {
        /* XC: if the condition fails, skip n instruction WORDS
         * (n = ((op>>12)&1) + 1; manual: n=2 is one 2-word or two
         * 1-word instructions).  XC does not touch OV (N-12).
         * If it passes, XC and the two words following it are
         * uninterruptible, whatever n (manual 6.3 XC). */
        if (!cond(c)) {
            n = ((op >> 12) & 1) + 1;
            c->pc = (uint16_t)(c->pc + n);
        } else {
            c->xc_left = 2;
            c->xc_new = 1;
        }
    } else if (hi >= 0xE8 && hi <= 0xEB) {
        /* CC: conditional call; bit 1 clears OV on the taken path. */
        imm = fetch(c);
        if (cond(c)) {
            push(c, c->pc);
            c->pc = imm;
            if (op & 2)
                c->ov = 0;
        }
    } else if (hi >= 0xEC && hi <= 0xEF) {
        /* RETC: conditional return; no status bits affected (N-12). */
        if (cond(c))
            c->pc = pop(c);
    } else if (hi >= 0xF0 && hi <= 0xF3) {
        /* BCNDD: delayed conditional branch. */
        imm = fetch(c);
        if (cond(c)) {
            if (op & 2)
                c->ov = 0;
            delay_slot(c, c->pc);
            c->pc = imm;
        }
    } else if (hi >= 0xF8 && hi <= 0xFB) {
        /* CCD: delayed conditional call; return is pc+2. */
        imm = fetch(c);
        if (cond(c)) {
            push(c, (uint16_t)(c->pc + 2));
            if (op & 2)
                c->ov = 0;
            delay_slot(c, c->pc);
            c->pc = imm;
        }
    } else if (hi >= 0xFC && hi <= 0xFF) {
        /* RETCD: delayed conditional return.  RETD: the slot runs
         * first, then TOS -> PC and the stack is popped (6.3 RETD). */
        if (cond(c)) {
            delay_slot(c, c->pc);
            c->pc = pop(c);
        }
    } else {
        c->status = RUN_BADOP;
    }
}

/* ------------------------------------------------------------------ */
/* Main loop                                                           */
/* ------------------------------------------------------------------ */

/* Cycle-model charge for the instruction just executed (orig L620-627).
 * Returns the total machine-cycle count cy for the instruction; the
 * caller adds cy - 1 because exec1 already charged the base cycle.
 * Machine cycles come from the manual's tables (fastest case);
 * repeated iterations cost 1, except repeated IN (2) and OUT (3).
 * Taken conditional branches (BANZ/BCND/CC/RETC) cost 4, not-taken
 * ones cost 2.  Sequencing is detected by comparing PC against
 * ppc + words, except RETC/RET, where "taken" means the return
 * address was popped (TOS may equal the fall-through address).
 * QUIRK (orig L625): the not-taken 2-cycle rule covers RETCD highs
 * 0xFC..0xFE (h >= 0xFC && h < 0xFF) -- 0xFF is NOT included.
 * PERF2 stage 2: the two hi-byte range ladders below are a 256-entry
 * class table instead (0 = no adjustment, 1 = conditional branch:
 * 4 cycles taken / 2 not-taken, 2 = not-taken-only 2 cycles).  The
 * table is a literal transcription of the two ladders it replaces;
 * the (rep_cont, seq) gating is unchanged. */
static const uint8_t cyc_adj[256] = {
    /* 0x7B BANZ */ [0x7B] = 1,
    /* 0xE0..0xE3 BCND, 0xE8..0xEB CC, 0xEC..0xEF RETC */ [0xE0] = 1,
    [0xE1] = 1, [0xE2] = 1, [0xE3] = 1, [0xE8] = 1, [0xE9] = 1,
    [0xEA] = 1, [0xEB] = 1, [0xEC] = 1, [0xED] = 1, [0xEE] = 1,
    [0xEF] = 1,
    /* 0xFC..0xFE RETCD: not-taken-only (2 cycles when sequential) */
    [0xFC] = 2, [0xFD] = 2, [0xFE] = 2,
};
static int instr_cycles(C5x *c, uint16_t ppc, int sp0)
{
    int cy;
    if (c->rep_cont) {
        cy = ((c->op >> 8) == 0xAF) ? 2 : ((c->op >> 8) == 0x0C) ? 3 : 1;
    } else {
        cy = cycm[c->op];
    }
    int seq = (uint16_t)c->pc == (uint16_t)(ppc + c->words);
    uint8_t h = (uint8_t)(c->op >> 8);
    if (h >= 0xEC && h <= 0xEF)
        seq = c->sp == sp0;
    if (!c->rep_cont) {
        uint8_t a = cyc_adj[h];
        if (a == 1)
            cy = seq ? 2 : 4; /* taken BANZ/BCND/CC/RETC: 4, not-taken: 2 */
        else if (a == 2 && seq)
            cy = 2; /* not-taken conditional */
    }
    return cy;
}

/* Single-instruction RPT handling (orig L630-631): if the instruction
 * just executed was the repeated one (ppc == rpt_end) and repeats
 * remain, rewind PC to rpt_start and count down; otherwise the
 * repeat is over. */
static void handle_rpt(C5x *c, uint16_t ppc)
{
    if (c->rptc > 0) {
        if (ppc == c->rpt_end) {
            c->pc = c->rpt_start;
            c->rptc--;
            c->rep_cont = 1;
        } else {
            c->rep_cont = 0;
        }
    } else {
        c->rptc = 0;
        c->rep_cont = 0;
    }
}

/* RPTB block-end test (manual 4.7; orig L633-637): the last loop word
 * has just executed (PC is already past it).  BRCR > 0: decrement and
 * restart at PASR; BRCR == 0: leave the loop with BRCR still 0 and
 * BRAF cleared.  Runs before the interrupt check so an ISR sees BRAF
 * and the return address after the loop-end test. */
static void handle_braf(C5x *c)
{
    if (c->braf && (uint16_t)(c->pc - 1) == c->paer) {
        if (c->brcr > 0) {
            c->pc = c->pasr;
            c->brcr--;
        } else {
            c->braf = 0;
        }
    }
}

/* Advance the on-chip timer by n machine cycles, in closed form.
 * Exactly equivalent to calling tick_timer() n times (manual 9.4):
 * the prescaler counts down from its current value and expires when
 * it would go below 0 (so the first TIM step is psc+1 ticks away),
 * then once every tddr+1 ticks; each prescaler expiry decrements TIM,
 * except when TIM is 0, when TIM reloads from PRD, IFR's TINT bit is
 * set and timer_exp counts one expiry.  The timer is frozen while
 * TSS is set.  TIM needs t0+1 expiries for its first reload (t0 steps
 * down to 0, then one more reloads it), and prd+1 expiries per reload
 * after that. */
static void advance_timer(C5x *c, uint64_t n)
{
    if (c->tss || n == 0)
        return;
    int64_t p0 = c->psc;
    int64_t first = p0 + 1; /* ticks to the next prescaler expiry */
    if (first < 1)
        first = 1;
    if ((uint64_t)first > n) {
        c->psc = (int)(p0 - (int64_t)n);
        return;
    }
    uint64_t tddr = (uint64_t)c->tcr_tddr;
    uint64_t rem = n - (uint64_t)first;
    /* Prescaler expiries in n ticks: one at `first`, then one every
     * tddr+1 ticks.  Just after an expiry psc holds tddr. */
    uint64_t e = 1 + rem / (tddr + 1);
    c->psc = (int)(tddr - (rem % (tddr + 1)));
    uint64_t t0 = c->tim;
    if (e <= t0) {
        c->tim = (uint16_t)(t0 - e);
        return;
    }
    uint64_t e2 = e - (t0 + 1); /* expiries after the first reload */
    c->timer_exp += 1 + e2 / ((uint64_t)c->prd + 1);
    c->tim = (uint16_t)(c->prd - (e2 % ((uint64_t)c->prd + 1)));
    c->ifr |= (uint16_t)(1 << C5X_TINT);
}

/* Machine cycles until the next TINT expiry from the current timer
 * state (timer running; callers check TSS first).  At least 1. */
static uint64_t timer_cycles_to_expiry(C5x *c)
{
    int64_t first = (int64_t)c->psc + 1;
    if (first < 1)
        first = 1;
    /* Prescaler expiries still needed: TIM steps to 0, then one more
     * reloads it and raises TINT (1 expiry when TIM is already 0). */
    uint64_t need = c->tim == 0 ? 1 : (uint64_t)c->tim + 1;
    return (uint64_t)first + (need - 1) * ((uint64_t)c->tcr_tddr + 1);
}

/* Run the timer once per machine cycle elapsed since c0 (orig L639).
 * The closed-form advance above replaces the per-cycle loop.
 * PERF2 stage 2: the wrapper is folded into its only caller
 * (c5x_run), which now calls advance_timer() directly. */

/* Interrupt-hold accounting for this instruction (orig L640-644).
 * Returns 1 when interrupts must be held off after this instruction:
 * the instruction after XC (xc_new), the remaining XC window
 * (xc_left, counted in words), or the single-word instruction at the
 * end of a repeat block (manual 4.7.2). */
static int interrupt_held(C5x *c)
{
    int xc_hold = 0;
    if (c->xc_new) {
        c->xc_new = 0;
        xc_hold = 1;
    } else if (c->xc_left > 0) {
        c->xc_left -= c->words;
    }
    if (c->xc_left > 0)
        xc_hold = 1;
    else
        c->xc_left = 0;
    if (c->braf && c->pc == c->paer)
        xc_hold = 1;
    return xc_hold;
}

/* Apply the AR0 -> INDX/ARCR mirror (audit #10, manual 6.3 LAR/MAR/
 * SAR; orig L628): with NDX=0 ('C2x compatible, the reset state),
 * anything that loads/modifies AR0 also loads INDX and ARCR. */
static void apply_ar0_mirror(C5x *c)
{
    if (c->ar0_dirty) {
        if (!c->ndx)
            c->indx = c->arcr = c->ar[0];
        c->ar0_dirty = 0;
    }
}

/* ------------------------------------------------------------------ */
/* RPTB block replay (PERF2 stage 3)                                   */
/*                                                                     */
/* DESIGN.  The profiler (prof2) shows RPTB covering 47.53% of DSP    */
/* instructions; the ov6/ov7 signal inner loops are the workload.      */
/* A block is decoded once (blk_decode) into a BlkDec and replayed     */
/* directly (blk_replay) while the block repeats: the replay skips     */
/* the per-instruction fetch, the diag branch, instr_cycles (the       */
/* cycle charge is precomputed per entry), and the repeat/hold         */
/* guard, but it executes the byte-identical family code through       */
/* exec1_op, and it runs the byte-identical per-instruction tail:      */
/* apply_ar0_mirror, handle_braf, advance_timer (per instruction,     */
/* NOT batched -- the division is overlapped, not on the critical      */
/* path, and batching would need an expiry countdown plus a            */
/* may-store catch-up), interrupt_held, the interrupt check with      */
/* the exact baseline condition, and the stop check.  The cycle        */
/* budget is honoured per entry (the replay never executes an          */
/* instruction the main loop would not have, and an interrupt is       */
/* taken before the budget check, exactly as in the main loop).        */
/*                                                                     */
/* EXACTNESS.  A replayed entry must execute exactly what the main     */
/* loop would have executed, with the same state afterwards:           */
/*  - Validation: a cached decode is used only when its raw words      */
/*    still match pm_rd (per-call: validated_seq == run_seq, plus      */
/*    pm_epoch / bp_epoch / cyc_model), and it is re-decoded when      */
/*    they do not.  pm_epoch is bumped on every PM/mapping change      */
/*    (pm_wr, glue loads, LST #1, RCNF/SCNF, PMST writes, c5x_set     */
/*    ST1/PMST) and on every external dm_wr (unified memory).  A      */
/*    breakpoint anywhere in the block refuses the decode, and a       */
/*    breakpoint appearing later is caught by the bp_epoch check.      */
/*  - In-replay writes: MMR PMST/RPTC/BRCR/PASR/PAER writes and        */
/*    pm_wr set replay_dirty via blk_state_changed; a dm_wr that       */
/*    lands on a block program word sets it via blk_store_guard.       */
/*    The replay checks replay_dirty after every entry and breaks      */
/*    out (the entry that dirtied the block already executed           */
/*    correctly; only later entries could be stale).                   */
/*  - RPT: allowed only when the next entry is an rptc-loop op         */
/*    (BLK_F_RPTC), which consumes rptc internally to -1; the replay  */
/*    clamps rptc to 0 afterwards, which is exactly handle_rpt's       */
/*    else branch.  A trailing RPT (consumer outside the block) is     */
/*    allowed: the consumer runs in the slow path after the loop.      */
/*    rep_cont stays 0 throughout the replay (handle_rpt is never      */
/*    needed: it could only set rep_cont = 0 here), so the cycle       */
/*    charge is cycm[op] and IN/OUT see rep_cont = 0, as in the        */
/*    baseline for a bare IN/OUT.  No cyc_adj entry applies: every     */
/*    opcode it covers is a branch, and all branches are excluded.     */
/*  - XC: allowed with skip handling -- after an XC entry the next     */
/*    entry is found by pc through idx_of, so a skip to another        */
/*    entry start continues in the block and a skip elsewhere (or      */
/*    past the block) breaks out to the slow path, which executes      */
/*    the skipped-to word as a fresh opcode exactly as the baseline    */
/*    would.  The XC uninterruptible window runs through the real      */
/*    interrupt_held, with words maintained per entry.                 */
/*  - handle_braf runs after every entry (as in the main loop), so     */
/*    an XC skip landing on paer+1 triggers the block-end test         */
/*    exactly as the baseline does, and a rewind restarts the block    */
/*    from entry 0.  The quirk where an XC skip past paer+1 leaves     */
/*    braf set is preserved: the replay hands off to the slow path,    */
/*    which keeps the same braf state.                                 */
/*  - Interrupts: the check uses the live rptc / rep_cont / intm /    */
/*    ifr / imr, and check_int is the real one (with its 4-cycle      */
/*    tick_timer entry cost).  An interrupt taken mid-block breaks     */
/*    out to the main loop, which executes the ISR; the remainder      */
/*    of the interrupted iteration runs slow (58k in-block interrupts  */
/*    x ~11 instructions per 20 s -- negligible).  Mid-block re-entry  */
/*    after an ISR return is NOT supported and is not needed: the      */
/*    return lands on pasr only if the ISR returned there, and the     */
/*    main loop then re-enters through the normal hook.                */
/*  - diag: the replay requires !diag, so the Python .so / stats       */
/*    harness keeps exact per-instruction diagnostic counts (the C     */
/*    driver runs with diag off).                                      */
/*  - 2-word entries: the replay sets pc = ppc+1 and words = 1        */
/*    before exec1_op, so the family's fetch() reads the second word   */
/*    at ppc+1 exactly as exec1+fetch do; after the entry pc is        */
/*    ppc+words.  A 2-word entry straddling paer refuses the decode.   */
/* ------------------------------------------------------------------ */

/* Classify one opcode word for block replay.  Returns the entry word
 * count (1 or 2) and fills *flags; returns 0 when the opcode cannot
 * replay.  The classification mirrors the exec_hi_* families exactly:
 * every opcode they execute is either allowed here with its true
 * word count and flags, or excluded.  Excluded: branches/calls/
 * returns of every kind (incl. delayed), RPTB, the PM writers
 * (SMMR/BLDP/TBLW), the mapping changers (LST #1, RCNF/SCNF),
 * IDLE/IDLE2, EINT, NMI/INTR/TRAP, and the BADOP opcodes. */
static int blk_classify(uint16_t op, uint8_t *flags)
{
    uint8_t hi = (uint8_t)(op >> 8);
    uint8_t lo = (uint8_t)op;
    uint8_t f = 0;
    int w = 1;

    if (hi <= 0x0F) {
        switch (hi) {
        case 0x09: return 0; /* SMMR: PM writer */
        case 0x0B: f = BLK_F_RPT; break; /* RPT dma */
        case 0x0C: w = 2; break; /* OUT: io_write only, not a dm_wr store */
        case 0x0F: return 0; /* LST #1: CNF change */
        default: break; /* LAR/LAMM/SUBC/LDP/LST #0 */
        }
    } else if (hi <= 0x3F) {
        /* LACC/ADD/SUB/BIT: 1 word, no store, no branch. */
    } else if (hi <= 0x5F) {
        if (hi == 0x56) return 0; /* BADOP */
        if (hi == 0x57) return 0; /* BLDP: PM writer */
        if (hi >= 0x58 && hi <= 0x5A) f = BLK_F_STORE; /* XPL/OPL/APL dbmr */
        else if (hi >= 0x5C && hi <= 0x5E) { w = 2; f = BLK_F_STORE; } /* #lk */
        else if (hi == 0x5F) w = 2; /* CPL #lk: no write */
        /* 0x40-0x4F BIT, 0x50-0x55 MPY forms, 0x5B CPL dbmr: 1 word. */
    } else if (hi <= 0x7F) {
        if (hi >= 0x79 && hi <= 0x7B) return 0; /* B/CALL/BANZ */
        if (hi >= 0x7D) return 0; /* BD/CALLD/BANZD */
        /* 0x60-0x78 ALU/loads/ADRK, 0x7C SBRK: 1 word.  LTD/DMOV use
         * dmov_wr only (internal dmem, never a PM store). */
    } else if (hi <= 0x9F) {
        if (hi <= 0x87) f = BLK_F_STORE; /* SAR */
        else if (hi == 0x88) f = BLK_F_STORE; /* SAMM */
        else if (hi == 0x89) { w = 2; f = BLK_F_STORE | BLK_F_RPTC; } /* LMMR */
        else if (hi == 0x8A) f = BLK_F_STORE; /* POPD */
        /* 0x8B MAR: no store. */
        else if (hi == 0x8C || hi == 0x8D) f = BLK_F_STORE; /* SPL/SPH */
        else if (hi == 0x8E || hi == 0x8F) f = BLK_F_STORE; /* SST #0/#1 */
        else if (hi >= 0x90) f = BLK_F_STORE; /* SACL/SACH */
    } else if (hi <= 0xAF) {
        switch (hi) {
        case 0xA0: break; /* NORM */
        case 0xA1: return 0; /* BADOP */
        case 0xA2: case 0xA3: w = 2; f = BLK_F_RPTC; break; /* MAC/MACD */
        case 0xA4: f = BLK_F_STORE | BLK_F_RPTC; break; /* BLPD bmar */
        case 0xA5: w = 2; f = BLK_F_STORE | BLK_F_RPTC; break; /* BLPD #pma */
        case 0xA6: f = BLK_F_STORE | BLK_F_RPTC; break; /* TBLR */
        case 0xA7: return 0; /* TBLW: PM writer */
        case 0xA8: case 0xA9: w = 2; f = BLK_F_STORE | BLK_F_RPTC; break; /* BLDD */
        case 0xAA: case 0xAB: f = BLK_F_RPTC; break; /* MADS/MADD: 1 word */
        case 0xAC: case 0xAD: f = BLK_F_STORE | BLK_F_RPTC; break; /* BLDD bmar */
        case 0xAE: w = 2; f = BLK_F_STORE; break; /* SPLK */
        case 0xAF: w = 2; f = BLK_F_STORE; break; /* IN */
        }
    } else if (hi <= 0xBF) {
        if (hi <= 0xB7) {
            /* LAR #k8 */
        } else if (hi == 0xB8 || hi == 0xB9 || hi == 0xBA) {
            /* ADDK/LACK/SUBK */
        } else if (hi == 0xBB) {
            f = BLK_F_RPT; /* RPT #k8 */
        } else if (hi == 0xBC || hi == 0xBD) {
            /* LDP #k9 */
        } else if (hi == 0xBE) {
            /* 0xBE sub-decoder, on the low byte. */
            if (lo < 0x20) {
                switch (lo) {
                case 0x00: case 0x01: case 0x02: case 0x03:
                case 0x04: case 0x05: case 0x09: case 0x0A:
                case 0x0C: case 0x0D: case 0x10: case 0x11:
                case 0x12: case 0x13: case 0x14: case 0x15:
                case 0x16: case 0x17: case 0x18: case 0x19:
                case 0x1A: case 0x1B: case 0x1C: case 0x1D:
                case 0x1E: case 0x1F:
                    break; /* ACC ops (exec_be_acc) */
                default:
                    return 0; /* BADOP */
                }
            } else {
                switch (lo) {
                case 0x32: /* POP */
                case 0x3C: /* PSHA */
                case 0x41: /* DINT */
                case 0x42: case 0x43: case 0x46: case 0x47:
                case 0x48: case 0x49: case 0x4A: case 0x4B:
                case 0x4C: case 0x4D: case 0x4E: case 0x4F:
                case 0x58: case 0x59: case 0x5A: case 0x5B:
                    break; /* flag/status ops, no store/branch */
                case 0x80: case 0x81: case 0x82: case 0x83:
                    w = 2; /* MPY/AND/OR/XOR #lk */
                    break;
                case 0xC4: case 0xC5:
                    w = 2; f = BLK_F_RPT; /* RPT/RPTZ #lk */
                    break;
                default:
                    return 0; /* BACC/BACCD/IDLE/CALA/RETI/RETE/CALAD/
                               * EINT/RCNF/SCNF/TRAP/NMI/RPTB/INTR/BADOP */
                }
            }
        } else { /* 0xBF sub-decoder, on the low byte. */
            if (lo <= 0x03) {
                /* SPM */
            } else if (lo >= 0x08 && lo <= 0x0F) {
                w = 2; /* LAR #lk */
            } else if (lo >= 0x44 && lo <= 0x47) {
                /* CMPR */
            } else {
                int h = lo & 0xF0;
                if (h >= 0x80 && h <= 0xD0) w = 2; /* long-imm ALU */
                else if (h == 0xE0) { /* SFTA: 1 word */ }
                else return 0; /* BADOP */
            }
        }
    } else if (hi <= 0xDF) {
        /* MPY #k13: 1 word. */
    } else {
        /* 0xE0-0xFF: only XC replays; every other form branches. */
        if ((hi >= 0xE4 && hi <= 0xE7) || (hi >= 0xF4 && hi <= 0xF7))
            f = BLK_F_XC;
        else
            return 0; /* BCND/CC/RETC/BCNDD/CCD/RETCD */
    }
    *flags = f;
    return w;
}

/* Decode the block [pasr, paer] into blk (fresh words via pm_rd).
 * Returns 1 on success, 0 when the block cannot replay.  On success
 * the epochs/validation stamp are recorded. */
static int blk_decode(C5x *c, BlkDec *blk, uint16_t pasr, uint16_t paer)
{
    uint16_t len = (uint16_t)(paer - pasr + 1);
    int n = 0;
    int i;
    if (len < 1 || len > BLK_MAX_WORDS)
        return 0;
    for (i = 0; i < len; i++) {
        blk->words[i] = pm_rd(c, (uint16_t)(pasr + i));
        blk->idx_of[i] = 0xFF;
        if (c->bp[pasr + i])
            return 0; /* a breakpoint inside the block: stay slow */
    }
    uint16_t off = 0;
    while (off < len) {
        uint16_t pc = (uint16_t)(pasr + off);
        uint8_t flags = 0;
        int w = blk_classify(blk->words[off], &flags);
        if (w == 0)
            return 0;
        if (off + w > len)
            return 0; /* a 2-word entry straddling paer */
        if (n >= BLK_MAX_ENT)
            return 0;
        blk->idx_of[off] = (uint8_t)n;
        blk->e[n].pc = pc;
        blk->e[n].op = blk->words[off];
        blk->e[n].cy = c->cyc_model ? cycm[blk->words[off]] : 1;
        blk->e[n].flags = flags;
        n++;
        off = (uint16_t)(off + w);
    }
    /* An RPT entry must be followed by an rptc-loop consumer (the
     * only repeat form the replay implements); a trailing RPT is
     * allowed, its consumer runs in the slow path after the loop. */
    for (i = 0; i < n; i++) {
        if ((blk->e[i].flags & BLK_F_RPT) && i + 1 < n &&
            !(blk->e[i + 1].flags & BLK_F_RPTC))
            return 0;
    }
    blk->pasr = pasr;
    blk->paer = paer;
    blk->n = (uint16_t)n;
    blk->epoch = c->pm_epoch;
    blk->bp_epoch = c->bp_epoch;
    blk->validated_seq = c->run_seq;
    blk->cyc_model = c->cyc_model;
    return 1;
}

/* Find (decoding / validating as needed) the cached block for the
 * RPTB loop the main loop has just entered (braf set, pc == pasr).
 * Returns NULL when the block cannot replay.  Validation is
 * per-call (run_seq) plus the epochs, so a PM change through any
 * route -- including a dm_wr to external unified memory, which
 * bumps pm_epoch in dm_wr -- is caught at the next lookup, and a
 * dirty break-out forces re-validation even within the same call. */
static BlkDec *blk_lookup(C5x *c)
{
    uint16_t pasr, paer;
    BlkDec *blk;
    if (c->rptc != 0 || c->rep_cont || c->xc_new || c->xc_left != 0 ||
        c->int_inh || c->idle || c->stop || c->diag)
        return NULL;
    pasr = c->pasr;
    paer = c->paer;
    if ((uint16_t)(paer - pasr + 1) > BLK_MAX_WORDS)
        return NULL;
    blk = c->blk_cache[pasr & (BLK_CACHE_N - 1)];
    if (!blk) {
        blk = (BlkDec *)calloc(1, sizeof(BlkDec));
        if (!blk)
            return NULL;
        c->blk_cache[pasr & (BLK_CACHE_N - 1)] = blk;
    }
    if (blk->pasr == pasr && blk->paer == paer && blk->n > 0) {
        if (blk->validated_seq == c->run_seq &&
            blk->epoch == c->pm_epoch && blk->bp_epoch == c->bp_epoch &&
            blk->cyc_model == c->cyc_model && !c->replay_dirty)
            return blk;
        /* Something changed since the decode: re-validate the words
         * (and the breakpoint scan), then keep the decode if they
         * still match; otherwise fall through to a fresh decode. */
        uint16_t len = (uint16_t)(paer - pasr + 1);
        int ok = 1;
        uint16_t k;
        for (k = 0; k < len; k++) {
            if (pm_rd(c, (uint16_t)(pasr + k)) != blk->words[k]) {
                ok = 0;
                break;
            }
        }
        if (ok) {
            for (k = 0; k < len; k++) {
                if (c->bp[pasr + k]) {
                    ok = 0;
                    break;
                }
            }
        }
        if (ok) {
            if (blk->cyc_model != c->cyc_model) {
                /* Cycle model toggled since the decode: refresh the
                 * per-entry charges, else the replay would charge
                 * the stale model (verifier note, PERF2.md §12;
                 * cannot fire in the shipped driver — the only
                 * c5x_set_cycle_model caller is setup — but an
                 * out-of-tree .so user could toggle it). */
                for (k = 0; k < blk->n; k++)
                    blk->e[k].cy = c->cyc_model ? cycm[blk->e[k].op] : 1;
                blk->cyc_model = c->cyc_model;
            }
            blk->epoch = c->pm_epoch;
            blk->bp_epoch = c->bp_epoch;
            blk->validated_seq = c->run_seq;
            return blk;
        }
    }
    if (!blk_decode(c, blk, pasr, paer))
        return NULL;
    return blk;
}

/* Replay a validated block.  Returns BLK_CONT (resume the main loop),
 * RUN_STOP, or RUN_BADOP.  The per-entry tail is the main loop's
 * tail, in the same order, with the same functions: apply_ar0_mirror,
 * the rptc clamp (handle_rpt's else branch, the only part that can
 * fire here), handle_braf, advance_timer over the entry's exact
 * cycles, interrupt_held, the interrupt check, and the stop check.
 * The budget check follows the interrupt check, as in the main loop
 * (an interrupt pending at the budget end is still taken). */
static int blk_replay(C5x *c, BlkDec *blk, uint64_t end)
{
    int i = 0;
    c->replay_active = 1;
    c->replay_dirty = 0;
    c->replay_lo = blk->pasr;
    c->replay_hi = blk->paer;
    for (;;) {
        BlkEnt *e = &blk->e[i];
        uint16_t ppc = e->pc;
        uint64_t c0 = c->cycles;
        int held;
        c->cur_pc = ppc;
        c->op = e->op;
        c->pc = (uint16_t)(ppc + 1);
        c->words = 1;
        c->cycles += e->cy;
        exec1_op(c, e->op);
        if (c->status == RUN_BADOP) {
            c->pc = ppc;
            c->replay_active = 0;
            return RUN_BADOP;
        }
        apply_ar0_mirror(c);
        if ((e->flags & BLK_F_RPTC) && c->rptc < 0)
            c->rptc = 0;
        handle_braf(c);
        advance_timer(c, c->cycles - c0);
        held = interrupt_held(c);
        if (c->int_inh)
            c->int_inh = 0;
        else if (!held && c->rptc <= 0 && !c->rep_cont && !c->intm &&
                 (c->ifr & c->imr))
            check_int(c);
        if (c->stop) {
            c->replay_active = 0;
            return RUN_STOP;
        }
        if (c->cycles >= end) {
            c->replay_active = 0;
            return BLK_CONT;
        }
        if (c->replay_dirty) {
            c->replay_active = 0;
            return BLK_CONT;
        }
        if (!c->braf) {
            c->replay_active = 0;
            return BLK_CONT;
        }
        /* Next entry by pc: straight-line, a handle_braf rewind to
         * pasr, or an XC skip to another entry start.  Any other pc
         * leaves the block (the slow path executes the skipped-to
         * word as a fresh opcode, exactly as the baseline would). */
        {
            uint16_t off = (uint16_t)(c->pc - c->pasr);
            uint8_t j;
            if (off > (uint16_t)(c->paer - c->pasr)) {
                c->replay_active = 0;
                return BLK_CONT;
            }
            j = blk->idx_of[off];
            if (j == 0xFF) {
                c->replay_active = 0;
                return BLK_CONT;
            }
            i = j;
        }
    }
}

/* Run until the cycle budget is exhausted.  Returns RUN_OK, RUN_BP,
 * RUN_BADOP, or RUN_STOP. */
int c5x_run(C5x *c, uint64_t budget)
{
    uint64_t end = c->cycles + budget;
    int first = 1;
    c->stop = 0;
    c->status = RUN_OK;
    c->run_seq++; /* per-call validation stamp for the block cache */
    while (c->cycles < end) {
        uint64_t c0 = c->cycles;
        if (c->idle) {
            /* IDLE2 (idle == 2) wakes only on INT1-4 (IFR/IMR bits
             * 0,1,2,8 = mask 0x107); IDLE wakes on any unmasked
             * interrupt (orig L611). */
            uint16_t wake = (uint16_t)(c->idle == 2 ? 0x107 : 0xFFFF);
            if (c->ifr & c->imr & wake) {
                c->idle = 0;
                check_int(c);
                continue;
            }
            /* Fast-forward: nothing else can change IFR while idle
             * (interrupts and serial ticks arrive only between
             * c5x_run calls), so the only event before the budget
             * ends is a timer expiry -- and only if TINT is unmasked
             * (otherwise the timer still advances, but the DSP
             * sleeps through its expiries).  The timer state is
             * advanced in closed form by advance_timer(), which is
             * exactly equivalent to one tick_timer() per cycle, so
             * timer expiries, IFR/TINT, idle_cycles and the
             * interrupt-entry cycle are all preserved. */
            uint64_t remain = end - c->cycles;
            if (c->idle == 2 || c->tss) {
                /* IDLE2 stops the timer; a stopped timer never
                 * ticks, and no wake can arrive before the budget
                 * ends. */
                c->cycles = end;
                c->idle_cycles += remain;
                continue;
            }
            if (c->imr & (uint16_t)(1 << C5X_TINT)) {
                /* Jump to the next TINT expiry (or the budget end,
                 * whichever comes first); the loop top then takes
                 * the interrupt at exactly the expiry cycle. */
                uint64_t d = timer_cycles_to_expiry(c);
                uint64_t step = d < remain ? d : remain;
                advance_timer(c, step);
                c->cycles += step;
                c->idle_cycles += step;
            } else {
                /* TINT masked: sleep through every expiry to the
                 * budget end; the timer still counts them. */
                advance_timer(c, remain);
                c->cycles = end;
                c->idle_cycles += remain;
            }
            continue;
        }
        if (c->bp[c->pc] && !first) {
            c->status = RUN_BP;
            return RUN_BP;
        }
        first = 0;
        c->status = RUN_OK;
        uint16_t ppc = c->pc;
        c->words = 0;
        int sp0 = c->sp;
        exec1(c);
        if (c->cyc_model)
            c->cycles += (uint64_t)(instr_cycles(c, ppc, sp0) - 1);
        apply_ar0_mirror(c);
        /* PERF2 stage 1: ar0_prev store removed (write-only, see above). */
        if (c->status == RUN_BADOP) {
            c->pc = ppc;
            return RUN_BADOP;
        }
        /* PERF2 stage 2: the three repeat/hold helpers are merged
         * behind one cheap guard.  handle_rpt, handle_braf and
         * interrupt_held are each almost always a no-op, but each
         * costs its own tests (and handle_rpt's else branch stores
         * rptc = 0 / rep_cont = 0 on every instruction).  The guard
         * is exact, not heuristic: when rptc == 0 and rep_cont == 0
         * handle_rpt's else branch would store the values already
         * there; when braf == 0 handle_braf does nothing; when
         * xc_new == 0, xc_left == 0 and braf == 0 interrupt_held
         * returns 0 and stores xc_left = 0, the value already there.
         * (rptc must be == 0, not <= 0: block instructions can leave
         * rptc == -1, and only the slow path clamps it to 0.)
         * Measured in a scratch instrumented build (20 s call): the
         * guard is true for 354.3M of 583.5M loop iterations
         * (60.7%); braf is set for 35.9%, rptc > 0 for 1.9%,
         * xc active for 2.3%.  The slow path keeps the original
         * order (rpt, braf, timer, held). */
        int rep_fast = (c->rptc == 0 && !c->rep_cont && !c->braf &&
                        !c->xc_new && c->xc_left == 0);
        if (!rep_fast) {
            handle_rpt(c, ppc);
            handle_braf(c);
        }
        /* PERF2 stage 2: tick_timers_for() folded in (it was a thin
         * wrapper over advance_timer, called once per instruction). */
        advance_timer(c, c->cycles - c0);
        int held = rep_fast ? 0 : interrupt_held(c);
        /* A single-instruction RPT repeat is not interruptible on the
         * real C5x (orig L645).  EINT's one-cycle inhibit (int_inh)
         * is consumed here whether or not an interrupt was pending.
         * The check_int() fast path (masked off, or nothing pending)
         * is inlined: it fires on ~92% of instructions. */
        if (c->int_inh)
            c->int_inh = 0;
        else if (held)
            ;
        else if (c->rptc <= 0 && !c->rep_cont && !c->intm &&
                 (c->ifr & c->imr))
            check_int(c);
        if (c->stop)
            return RUN_STOP;
        /* PERF2 stage 3: RPTB block replay.  Fires when the slow path
         * has just executed RPTB (braf set, pc at the block start) or
         * an ISR returned there.  Only when budget remains: the
         * replay's per-entry budget check then guarantees it never
         * executes an instruction the main loop would not have. */
        if (c->braf && c->pc == c->pasr && !c->diag && c->cycles < end) {
            BlkDec *blk = blk_lookup(c);
            if (blk) {
                int r = blk_replay(c, blk, end);
                if (r != BLK_CONT)
                    return r;
            }
        }
    }
    return RUN_OK;
}

/* Serial-port frame tick: one codec sample period elapsed.
 * rx = ADC sample delivered to DRR. */
void c5x_serial_tick(C5x *c, int16_t rx)
{
    if (c->spc & SPC_RRST_BIT) { /* receiver enabled (RRST=1) */
        /* Previous word not read before the next one arrived:
         * overrun; the receiver halts until DRR is read, the new
         * word is lost (manual 9.7). */
        if (c->rrdy || c->rsrfull)
            c->rsrfull = 1;
        else {
            /* DLB: DX looped back to DR. */
            c->drr = (c->spc & SPC_DLB_BIT) ? c->dxr : (uint16_t)rx;
            c->rrdy = 1;
            c->ifr |= (uint16_t)(1 << C5X_RINT);
        }
    }
    if (c->spc & SPC_XRST_BIT) { /* transmitter enabled (XRST=1) */
        int dxr_pending = !c->xrdy; /* DXR written since the last frame */
        if (!dxr_pending)
            c->xsrempty = 0; /* underflow */
        c->xrdy = 1;
        /* XINT: legacy = every tick; mode 1 = only after a DXR write
         * (plus one initial kick) (orig L660). */
        if (!c->xint_mode || dxr_pending || c->xint_first) {
            c->ifr |= (uint16_t)(1 << C5X_XINT);
            c->xint_first = 0;
        }
    }
}

/* ------------------------------------------------------------------ */
/* Remaining exported API: switches, counters, diagnostics             */
/* ------------------------------------------------------------------ */

void c5x_set_xint_mode(C5x *c, int m)
{
    c->xint_mode = m;
    c->xint_first = 1;
}
void c5x_set_cycle_model(C5x *c, int m) { c->cyc_model = m; }
/* Diagnostics gate: 0 = skip the per-instruction / per-access counters
 * listed at the `diag` field (default 1 = on, the historical behaviour).
 * The C driver disables them; the .so / ctypes ABI is unchanged. */
void c5x_set_diag(C5x *c, int on) { c->diag = on ? 1 : 0; }
/* API stub: nothing reads `legacy` any more (orig L665). */
void c5x_set_legacy(C5x *c, int m) { c->legacy = m; }
uint64_t c5x_idle_cycles(C5x *c) { return c->idle_cycles; }
/* TIM reached 0 (TOUT pulses): the board's host heartbeat (INT0,
 * 2401 Hz measured) follows these (orig L667). */
uint64_t c5x_timer_expiries(C5x *c) { return c->timer_exp; }
uint64_t c5x_total_cycles(C5x *c) { return c->cycles; }

void c5x_set_ivec_ind(C5x *c, int bit, uint16_t daddr)
{
    c->ivec_ind[bit] = daddr;
}

void c5x_set_cmpr_ar0(C5x *c, int v) { c->cmpr_ar0 = v; }

uint32_t c5x_dxr_head(C5x *c) { return c->dxr_head; }
uint16_t *c5x_dxr_ring(C5x *c) { return c->dxr_ring; }

void c5x_set_watch(C5x *c, int32_t a)
{
    c->watch_a = a;
    memset(c->watch_hits, 0, sizeof c->watch_hits);
}
uint32_t c5x_watch_hits(C5x *c, uint32_t pc) { return c->watch_hits[pc & 0xFFFF]; }
uint32_t c5x_pc_hits(C5x *c, uint32_t pc) { return c->pc_hits[pc & 0xFFFF]; }
void c5x_pc_hits_clear(C5x *c) { memset(c->pc_hits, 0, sizeof c->pc_hits); }
void c5x_set_trace(C5x *c, int32_t pc)
{
    c->trace_pc = pc;
    c->trace_n = 0;
}
uint32_t c5x_trace_n(C5x *c) { return c->trace_n; }
void c5x_trace_get(C5x *c, uint32_t i, uint32_t *acc, uint16_t *ret, uint16_t *ret2)
{
    *acc = c->trace_buf[i].acc;
    *ret = c->trace_buf[i].ret;
    *ret2 = c->trace_buf[i].ret2;
}

uint32_t c5x_mmr_count(C5x *c, int wr, int a) { return c->mmr_n[wr][a]; }
uint16_t c5x_mmr_pc(C5x *c, int wr, int a) { return c->mmr_pc[wr][a]; }
void c5x_mmr_clear(C5x *c) { memset(c->mmr_n, 0, sizeof c->mmr_n); }
uint16_t c5x_mmr_val(C5x *c, int a) { return c->mmr_val[a]; }
uint32_t c5x_ff_count(C5x *c, int wr, int i) { return c->ff_n[wr][i & 255]; }
uint32_t c5x_ext_count(C5x *c, int wr, int blk) { return c->ext_n[wr][blk]; }
uint16_t c5x_rsv(C5x *c, int w) { return w ? c->rsv_pc : c->rsv_a; }
