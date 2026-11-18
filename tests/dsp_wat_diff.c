/* Differential test for src/dsp/c5x_core.wat.  Generates random single-
 * instruction cases, runs each on the native C core, and prints the inputs
 * and results for tests/dsp_wat_diff.js to replay on the WAT core.
 * The core source is included directly so the setup can reach its state. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "../src/dsp/c5x_core.c"

static uint32_t rs = 0x2545F491u;

static uint32_t rnd(void)
{
    rs ^= rs << 13;
    rs ^= rs >> 17;
    rs ^= rs << 5;
    return rs;
}

static uint32_t rnd32(void)
{
    static const uint32_t special[] = { 0, 1, 0x7fffffffu, 0x80000000u,
                                        0xffffffffu, 0x00010000u, 0x8000u };
    return rnd() % 3 ? rnd() : special[rnd() % 7];
}

static uint16_t rnd16(void)
{
    static const uint16_t special[] = { 0, 1, 0x7fff, 0x8000, 0xffff };
    return rnd() % 3 ? (uint16_t)rnd() : special[rnd() % 5];
}

/* High bytes the WAT core implements (keep in sync with $supported). */
static int hi_tab[256], nhi;

static void add_range(int lo, int hi)
{
    for (int h = lo; h <= hi; h++)
        hi_tab[nhi++] = h;
}

/* On-chip data RAM address (B2 or B0), so every AR-based access stays internal. */
static uint16_t on_chip_addr(void)
{
    return rnd() & 1 ? (uint16_t)(0x60 + rnd() % 32) : (uint16_t)(0x100 + rnd() % 0x400);
}

int main(int argc, char **argv)
{
    long n = argc > 1 ? atol(argv[1]) : 20000;
    add_range(0x10, 0x3f);
    add_range(0x50, 0x55);
    add_range(0x60, 0x6e);
    add_range(0x70, 0x74);
    add_range(0x77, 0x77);
    add_range(0x8c, 0x8d);
    add_range(0x88, 0x88);
    add_range(0x8e, 0x8f);
    add_range(0xa0, 0xa0);
    add_range(0xa2, 0xa3);
    add_range(0xa5, 0xa5);
    add_range(0xa8, 0xa9);
    add_range(0x09, 0x09);
    add_range(0x89, 0x89);
    add_range(0xa4, 0xa4);
    add_range(0xaa, 0xac);
    add_range(0x7d, 0x7f);
    add_range(0xe4, 0xe7);
    add_range(0xf0, 0xff);
    add_range(0x90, 0x9f);
    add_range(0x40, 0x4f);
    add_range(0x6f, 0x6f);
    add_range(0x79, 0x7c);
    add_range(0xe0, 0xe3);
    add_range(0xe8, 0xef);
    add_range(0xbe, 0xbe);
    add_range(0x00, 0x08);
    add_range(0x0a, 0x0a);
    add_range(0x0d, 0x0f);
    add_range(0x80, 0x87);
    C5x *c = c5x_new();
    uint16_t *pmem = c5x_pmem(c);
    uint16_t *dmem = c5x_dmem(c);
    static const int m4_tab[] = { 0, 1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13, 14, 15 };
    /* 0xBE low bytes the WAT core implements (keep in sync with $be_ok). */
    static const uint16_t be_tab[] = { 0x20, 0x30, 0x32, 0x3c, 0x40, 0x41,
        0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d,
        0x4e, 0x4f, 0x58, 0x59, 0x5a, 0x5b, 0x80, 0x81, 0x82, 0x83,
        0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x09, 0x0a, 0x0c, 0x0d,
        0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b,
        0x1c, 0x1d, 0x1e, 0x1f, 0x21, 0x3d, 0xc6, 0x38, 0x3a };

    for (long i = 0; i < n; i++) {
        int hi = hi_tab[rnd() % nhi];
        int ind = rnd() & 1;
        /* One case in four is a repeat sequence: RPT (dma or #lk) followed by a
         * register-only op, run for RPT + (n+1) executions. */
        int rptmode = rnd() % 4 == 0;
        int rpt_be = rptmode && (rnd() & 1);
        uint32_t n = rnd() % 4;
        int budget = rptmode ? (int)n + 2 : 1;
        /* RPTB block repeat: RPTB #2 with a single-word body at PMEM[2]. */
        int rptb = !rptmode && rnd() % 6 == 0;
        uint32_t brc = rnd() & 3;
        if (rptb) {
            hi = 0xbe;
            brc = n;
            budget = 2 * (int)n + 3;
        }
        int intrm = !rptmode && !rptb && rnd() % 8 == 0;
        uint16_t ret_op = (rnd() & 1) ? 0xbe38 : 0xbe3a;
        if (intrm) {
            hi = 0xbe;
            budget = 3;
        }
        static const uint16_t be_nomem[] = { 0x00, 0x01, 0x09, 0x0a, 0x0c, 0x0d,
            0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b,
            0x1c, 0x1d, 0x1e, 0x1f, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
            0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f, 0x58, 0x59 };
        uint16_t op2 = (uint16_t)(0xbe00 | be_nomem[rnd() % (sizeof be_nomem / sizeof be_nomem[0])]);
        if (rptmode) {
            hi = rpt_be ? 0xbe : 0x0b;
            ind = 0;
        }

        /* Direct addressing into on-chip RAM only (CNF=0, no overlays). */
        uint32_t page = rnd() % 9;
        uint16_t dp = page == 0 ? 0 : (uint16_t)((page + 1) << 7);
        uint16_t low = page == 0 ? (uint16_t)(rnd() % 4 ? 0x60 + rnd() % 32 : 0x60)
                                 : (uint16_t)(rnd() % 128);
        if (hi == 0x08 || hi == 0x88 || hi == 0x09 || hi == 0x89) {
            /* LAMM/SAMM mask the address to page 0: keep it out of the MMR range. */
            ind = 0;
            low = (uint16_t)(0x60 + rnd() % 32);
        } else if (hi == 0x8e || hi == 0x8f) {
            if (!ind)
                low = (uint16_t)(0x60 + rnd() % 32);
            else
                low = (uint16_t)(0x80 | (m4_tab[rnd() % 14] << 3) | (rnd() & 7));
        } else if (hi == 0xbe)
            low = be_tab[rnd() % (sizeof be_tab / sizeof be_tab[0])];
        else if (hi >= 0xe0)
            low = (uint16_t)rnd16() & 0xff;
        else if (ind)
            low = (uint16_t)(0x80 | (m4_tab[rnd() % 14] << 3) | (rnd() & 7));

        uint32_t acc = rnd32(), preg = rnd32();
        uint16_t t0 = rnd16(), t1 = rnd16(), t2 = rnd16(), d0 = rnd16(), d1 = rnd16();
        uint32_t sxm = rnd() & 1, ovm = rnd() & 1, cc = rnd() & 1;
        uint32_t ov = rnd() & 1, pm = rnd() & 3, trm = rnd() & 1;
        uint32_t tc = rnd() & 1, bio = rnd() & 1;
        uint32_t hm = rnd() & 1, xf = rnd() & 1, intm = rnd() & 1;
        uint32_t accb = rnd32();
        uint16_t imm = rnd16();
        if (rptmode && rpt_be)
            imm = (uint16_t)n;
        /* Keep the program-memory operand clear of the vector and op words. */
        if (!rptmode && imm < 8)
            imm = (uint16_t)(imm + 8);
        if (rptb)
            imm = 3;
        if (intrm)
            imm = 200;
        if (hi == 0xa8 || hi == 0xa9 || hi == 0x09 || hi == 0x89 || hi == 0xac)
            imm = on_chip_addr();
        uint16_t p0 = rnd16();
        uint16_t arp = rnd() % 8, arb = rnd() % 8;
        uint16_t indx = rnd16(), arcr = rnd16();
        uint32_t ndx = rnd() & 1, cbcr = rnd() & 0xff;
        uint16_t cbsr1 = rnd16(), cbsr2 = rnd16();
        uint16_t ar[8];
        for (int k = 0; k < 8; k++)
            ar[k] = on_chip_addr();
        /* Half the time the buffer end matches the current AR, so wrap fires. */
        uint16_t cber1 = rnd() & 1 ? ar[cbcr & 7] : rnd16();
        uint16_t cber2 = rnd() & 1 ? ar[(cbcr >> 4) & 7] : rnd16();
        uint16_t op = (uint16_t)((hi << 8) | low);
        if (rptmode && rpt_be)
            op = 0xbec4;
        if (rptmode && !rpt_be)
            d0 = (uint16_t)n;
        if (rptb)
            op = 0xbec6;
        /* INTR 1 (vector 2, shadow context saved) runs a register-only ISR at
         * PMEM[2] and returns with RETI or RETE. */
        if (intrm)
            op = 0xbe61;
        uint16_t addr = ind ? ar[arp]
                      : (uint16_t)((hi == 0x88 || hi == 0x8e || hi == 0x8f) ? low : (dp | low));

        c5x_reset(c, 0);
        c5x_set(c, C5X_REG_ACC, acc);
        c->preg = preg;
        c->accb = accb;
        c->treg0 = t0;
        c->treg1 = t1;
        c->treg2 = t2;
        c5x_set(c, C5X_REG_ST0, (ov << 12) | (ovm << 11) | (intm << 9) | (dp >> 7) | (arp << 13));
        c5x_set(c, C5X_REG_ST1, (sxm << 10) | (cc << 9) | pm | (arb << 13) | (tc << 11) | (hm << 6) | (xf << 4));
        c5x_set(c, C5X_REG_PMST, (ndx << 2) | (trm << 1));
        c->indx = indx;
        c->bmar = imm;
        c->brcr = brc;
        c->arcr = arcr;
        c->cbcr = (uint16_t)cbcr;
        c->cbsr1 = cbsr1;
        c->cber1 = cber1;
        c->cbsr2 = cbsr2;
        c->cber2 = cber2;
        c5x_set_bio(c, bio);
        for (int k = 0; k < 8; k++)
            c5x_set(c, C5X_REG_AR0 + k, ar[k]);
        pmem[imm] = p0;
        pmem[0] = op;
        uint16_t s2 = (uint16_t)(0xbe00 | be_nomem[rnd() % (sizeof be_nomem / sizeof be_nomem[0])]);
        pmem[2] = op2;
        pmem[3] = s2;
        pmem[1] = imm;
        if (rptmode)
            pmem[rpt_be ? 2 : 1] = op2;
        /* Forms without an immediate word take their slot from PMEM[1]. */
        if (intrm) {
            pmem[2] = op2;
            pmem[3] = ret_op;
        }
        if (hi >= 0xfc || op == 0xbe21 || op == 0xbe3d) {
            pmem[1] = op2;
            pmem[2] = s2;
        }
        dmem[addr] = d0;
        dmem[(uint16_t)(addr + 1)] = d1;
        c5x_run(c, (uint64_t)budget);

        printf("%u %u %u %u %u %u %u %u %u %u %u %u %u %u %u %u "
               "%u %u %u %u %u %u %u %u %u %u",
               op, dp, (unsigned)sxm, (unsigned)ovm, (unsigned)cc,
               (unsigned)ov, (unsigned)pm, (unsigned)trm, acc, preg,
               t0, t1, t2, addr, d0, d1,
               arp, arb, indx, arcr, ndx, cbcr, cbsr1, cber1, cbsr2, cber2);
        for (int k = 0; k < 8; k++)
            printf(" %u", ar[k]);
        printf(" %u %u %u %u %u %u %u %u %u %u %u %u %u |", (unsigned)tc, (unsigned)bio,
               (unsigned)pmem[1], (unsigned)hm, (unsigned)xf, accb, (unsigned)intm,
               (unsigned)budget, (unsigned)pmem[2], (unsigned)p0, (unsigned)imm,
               (unsigned)pmem[3], brc);
        printf(" %u %u %u %u %u %u %u %u %u",
               c->acc, c->preg, c->treg0, c->treg1, c->treg2,
               (unsigned)c->c, (unsigned)c->ov, dmem[addr],
               dmem[(uint16_t)(addr + 1)]);
        for (int k = 0; k < 8; k++)
            printf(" %u", c->ar[k]);
        printf(" %u %u %u %u %u %u %u", (unsigned)c->arp, (unsigned)c->arb,
               (unsigned)c->indx, (unsigned)c->arcr,
               (unsigned)c->tc, (unsigned)c->pc, (unsigned)c->sp);
        for (int k = 0; k < 8; k++)
            printf(" %u", c->stack[k]);
        printf(" %u %u %u %u %u %u %u %u %u %u %u %u %u %u\n", (unsigned)c->ovm, (unsigned)c->sxm,
               (unsigned)c->cnf, (unsigned)c->hm, (unsigned)c->xf, (unsigned)c->dp,
               c->accb, (unsigned)c->intm, (unsigned)c->rptc, (unsigned)c->bmar,
               (unsigned)c->braf, (unsigned)c->pasr, (unsigned)c->paer, (unsigned)c->brcr);
    }
    return 0;
}
