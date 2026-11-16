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

    /* Memories (flat 64K x 16-bit views owned by the core). */
    uint16_t *pmem, *dmem, *iomem;
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
    int in_delay;                      /* 1 = executing a delay-slot word */

    /* AR0 / NDX mirroring (audit #10). */
    uint16_t ar0_prev;
    int ar0_dirty, int_inh;
    int cmpr_ar0;                      /* experiment: CMPR compares AR0, not ARCR */

    /* Watch / trace diagnostics. */
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
    c->bp = calloc(65536, 1);
    c->iolog = calloc(IOLOG_N, sizeof(IoEv));
    c->dxr_ring = calloc(DXR_RING_N, 2);
    c->rptc = 0;
    c->trace_pc = -1;
    c->watch_a = -1;
    return c;
}

uint16_t *c5x_pmem(C5x *c) { return c->pmem; }
uint16_t *c5x_dmem(C5x *c) { return c->dmem; }
uint16_t *c5x_iomem(C5x *c) { return c->iomem; }
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
void c5x_set_bp(C5x *c, uint16_t a, int on) { c->bp[a] = on; }
void c5x_stop(C5x *c) { c->stop = 1; }
void c5x_set_bio(C5x *c, int v) { c->bio = v; }
/* Reset: restores the power-on register state for a fresh run at pc.
 * Deliberately does NOT touch: the memories, watch/trace diagnostics,
 * MMR counters, breakpoints, the I/O log, the DXR ring,
 * ivec_ind, cmpr_ar0, xint_mode, cyc_model, legacy, idle_cycles,
 * timer_exp, or the unlisted registers below (indx, arcr, cbsr/cber,
 * bmar, dbmr, pasr, paer, rpt_start/rpt_end, io_rep, ar0_prev).
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
        c->cnf = (int)((v >> ST1_CNF_BIT) & 1);
        c->tc = (int)((v >> ST1_TC_BIT) & 1);
        c->sxm = (int)((v >> ST1_SXM_BIT) & 1);
        c->c = (int)((v >> ST1_C_BIT) & 1);
        c->hm = (int)((v >> ST1_HM_BIT) & 1);
        c->xf = (int)((v >> ST1_XF_BIT) & 1);
        c->pm = (int)(v & 3);
        break;
    case C5X_REG_PMST:
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

static uint16_t mmr_rd(C5x *c, uint16_t a)
{
    if (a < N_MMR) {
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

static void mmr_wr(C5x *c, uint16_t a, uint16_t d)
{
    if (a < N_MMR) {
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
        c->iptr = d >> PMST_IPTR_SHIFT;
        c->avis = (d >> PMST_AVIS_BIT) & 1;
        c->ovly = (d >> PMST_OVLY_BIT) & 1;
        c->ram = (d >> PMST_RAM_BIT) & 1;
        c->mpmc = (d >> PMST_MPMC_BIT) & 1;
        c->ndx = (d >> PMST_NDX_BIT) & 1;
        c->trm = (d >> PMST_TRM_BIT) & 1;
        c->braf = d & 1;
        return;
    case 0x08: c->rptc = d; return;
    case 0x09: c->brcr = d; return;
    case 0x0A: c->pasr = d; return;
    case 0x0B: c->paer = d; return;
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

static inline uint16_t dm_rd(C5x *c, uint16_t a)
{
    if (a >= DM_MMR_END && !dm_internal(c, a)) {
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

static inline void dm_wr(C5x *c, uint16_t a, uint16_t d)
{
    mmr_bus(c, a);
    if (a >= DM_MMR_END && !dm_internal(c, a))
        c->ext_n[1][a >> 10]++;
    if (a >= DM_FF_START)
        c->ff_n[1][a & 255]++;
    if ((int32_t)a == c->watch_a)
        c->watch_hits[c->cur_pc]++;
    if (a < DM_MMR_END)
        mmr_wr(c, a, d);
    else if (dm_internal(c, a))
        c->dmem[a] = d;
    else if (dm_hostwin(a))
        io_write(c, a, d);
    else
        c->pmem[a] = d;
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
static inline void pm_wr(C5x *c, uint16_t a, uint16_t d) { *pm_ptr(c, a) = d; }

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
static void upd_ar(C5x *c, int ar, int step)
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
static uint16_t ea_indirect(C5x *c, uint16_t op)
{
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

static inline __attribute__((always_inline)) uint16_t ea(C5x *c)
{
    uint16_t op = c->op;
    if (!(op & 0x80))
        return (uint16_t)(c->dp | (op & 0x7f));
    return ea_indirect(c, op);
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
        /* LST #1: load ST1 (ARB and ARP both come from the word). */
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

static void exec1(C5x *c)
{
    uint16_t op;
    c->cur_pc = c->pc;
    if ((int32_t)c->pc == c->trace_pc && c->trace_n < TRACE_N) {
        c->trace_buf[c->trace_n].acc = c->acc;
        c->trace_buf[c->trace_n].ret = c->stack[c->sp];
        c->trace_buf[c->trace_n].ret2 = c->stack[(c->sp + 1) & 7];
        c->trace_buf[c->trace_n].cyc = c->cycles;
        c->trace_n++;
    }
    op = c->op = fetch(c);
    c->cycles++; /* base cycle; the cycle model adds the rest in c5x_run */

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
    case 0x44: c->cnf = 0; break;  /* RCNF */
    case 0x45: c->cnf = 1; break;  /* SCNF */
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
 * 0xFC..0xFE (h >= 0xFC && h < 0xFF) -- 0xFF is NOT included. */
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
    if (!c->rep_cont && !seq) {
        if (h == 0x7B || (h >= 0xE0 && h <= 0xE3) ||
            (h >= 0xE8 && h <= 0xEB) || (h >= 0xEC && h <= 0xEF))
            cy = 4; /* taken BANZ/BCND/CC/RETC */
    } else if (!c->rep_cont && seq &&
               (h == 0x7B || (h >= 0xE0 && h <= 0xE3) ||
                (h >= 0xE8 && h <= 0xEB) || (h >= 0xEC && h <= 0xEF) ||
                (h >= 0xFC && h < 0xFF))) {
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

/* Run the timer once per machine cycle elapsed since c0 (orig L639). */
static void tick_timers_for(C5x *c, uint64_t c0)
{
    for (uint64_t k = c0; k < c->cycles; k++)
        tick_timer(c);
}

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

/* Run until the cycle budget is exhausted.  Returns RUN_OK, RUN_BP,
 * RUN_BADOP, or RUN_STOP. */
int c5x_run(C5x *c, uint64_t budget)
{
    uint64_t end = c->cycles + budget;
    int first = 1;
    c->stop = 0;
    c->status = RUN_OK;
    while (c->cycles < end) {
        uint64_t c0 = c->cycles;
        if (c->idle) {
            /* IDLE2 (idle == 2) wakes only on INT1-4 (IFR/IMR bits
             * 0,1,2,8 = mask 0x107); IDLE wakes on any unmasked
             * interrupt (orig L611). */
            if (c->ifr & c->imr & (c->idle == 2 ? 0x107 : 0xFFFF)) {
                c->idle = 0;
                check_int(c);
                continue;
            }
            /* Skip forward one cycle at a time (timer granularity);
             * IDLE2 stops the timer. */
            c->cycles++;
            c->idle_cycles++;
            if (c->idle == 1)
                tick_timer(c);
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
        c->ar0_prev = c->ar[0];
        if (c->status == RUN_BADOP) {
            c->pc = ppc;
            return RUN_BADOP;
        }
        handle_rpt(c, ppc);
        handle_braf(c);
        tick_timers_for(c, c0);
        int held = interrupt_held(c);
        /* A single-instruction RPT repeat is not interruptible on the
         * real C5x (orig L645).  EINT's one-cycle inhibit (int_inh)
         * is consumed here whether or not an interrupt was pending. */
        if (c->int_inh)
            c->int_inh = 0;
        else if (held)
            ;
        else if (c->rptc <= 0 && !c->rep_cont)
            check_int(c);
        if (c->stop)
            return RUN_STOP;
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
