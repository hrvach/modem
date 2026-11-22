// c_ref.cpp -- C reference-model wrapper implementation.
//
// Includes the C core translation unit once (no modifications to the
// C tree), so the harness can read the full architectural state,
// including the hardware stack, which the public ABI does not expose.
#include "c_ref.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// The C core lives in the C port tree; the Makefile passes its
// directory with -I. Including the .c file (not linking it) gives
// this translation unit white-box access to struct C5x.
#include "c5x_core.c"

C5x *cref_new(void)
{
    return c5x_new();
}

void cref_free(C5x *c)
{
    // The C core has no c5x_free(); freeing the struct alone leaks
    // its sub-arrays. Harmless for this one-shot CLI harness (the
    // process exits), but do not copy this into a long-lived host.
    free(c);
}

static int read_file(const char *path, uint8_t **out, size_t *len)
{
    FILE *f = fopen(path, "rb");
    if (!f)
        return -1;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n < 0) {
        fclose(f);
        return -1;
    }
    uint8_t *buf = (uint8_t *)malloc((size_t)n ? (size_t)n : 1);
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
        free(buf);
        fclose(f);
        return -1;
    }
    fclose(f);
    *out = buf;
    *len = (size_t)n;
    return 0;
}

int cref_load_firmware(C5x *c, const char *image_path)
{
    uint8_t *img = NULL;
    size_t len = 0;
    if (read_file(image_path, &img, &len) != 0)
        return -1;
    uint16_t *pm = c5x_pmem(c);
    size_t n = len / 2;
    for (size_t i = 0; i < n; i++)
        pm[(0x8000 + i) & 0xFFFF] =
            (uint16_t)(img[2 * i] | (img[2 * i + 1] << 8));
    free(img);
    c5x_pm_invalidate(c);
    // sv25-profile interrupt-vector presets (config.c): ivec slots
    // 0x60+i point at dm[0x60+i], all preset to 0x81AE, with three
    // extras.
    uint16_t *dm = c5x_dmem(c);
    for (int i = 0; i < 11; i++) {
        c5x_set_ivec_ind(c, i, (uint16_t)(0x60 + i));
        dm[0x60 + i] = 0x81AE;
    }
    dm[0x65] = 0x8189;
    dm[0x68] = 0x820C;
    dm[0x69] = 0x81B7;
    c5x_set_cycle_model(c, 1);
    c5x_set_diag(c, 0); // as the C driver runs (diag off)
    c5x_iolog_enable(c, 1);
    c5x_reset(c, 0x8000);
    return 0;
}

void cref_load_program(C5x *c, const uint16_t *words, int nwords,
                       uint16_t base)
{
    uint16_t *pm = c5x_pmem(c);
    for (int i = 0; i < nwords; i++)
        pm[(base + i) & 0xFFFF] = words[i];
    c5x_pm_invalidate(c);
    c5x_set_cycle_model(c, 1);
    c5x_set_diag(c, 0);
    c5x_iolog_enable(c, 1);
    c5x_reset(c, base);
}

int cref_load_smoke(C5x *c, const char *image_path)
{
    uint8_t *img = NULL;
    size_t len = 0;
    if (read_file(image_path, &img, &len) != 0)
        return -1;
    uint16_t *pm = c5x_pmem(c);
    size_t n = len / 2;
    for (size_t i = 0; i < n; i++)
        pm[(0x8000 + i) & 0xFFFF] =
            (uint16_t)(img[2 * i] | (img[2 * i + 1] << 8));
    free(img);
    c5x_pm_invalidate(c);
    // No DMEM presets, no ivec_ind setup: the vector's
    // load_images() loads dsp_base.bin into PM only.
    c5x_set_cycle_model(c, 1);
    c5x_set_diag(c, 1); // pcring (recent_pcs) is gated by diag
    c5x_iolog_enable(c, 1);
    c5x_reset(c, 0x8000);
    return 0;
}

void cref_set_diag(C5x *c, int on)
{
    c5x_set_diag(c, on);
}

uint64_t cref_idle_cycles(C5x *c) { return c5x_idle_cycles(c); }

uint64_t cref_timer_expiries(C5x *c) { return c5x_timer_expiries(c); }

uint32_t cref_dxr_head(C5x *c) { return c5x_dxr_head(c); }

uint16_t *cref_dxr_ring(C5x *c) { return c5x_dxr_ring(c); }

uint16_t *cref_pcring(C5x *c) { return c5x_pcring(c); }

uint32_t cref_pcring_idx(C5x *c) { return c5x_pcring_idx(c); }

uint16_t cref_ivec_ind(C5x *c, int i)
{
    return c->ivec_ind[i & 15];
}

int cref_step(C5x *c)
{
    return c5x_run(c, 1);
}

int cref_run(C5x *c, uint64_t cycles)
{
    return c5x_run(c, cycles);
}

void cref_get_state(C5x *c, CState *s)
{
    memset(s, 0, sizeof *s);
    s->pc    = (uint16_t)c5x_get(c, C5X_REG_PC);
    s->op    = c->op;
    s->acc   = c5x_get(c, C5X_REG_ACC);
    s->accb  = c5x_get(c, C5X_REG_ACCB);
    s->preg  = c5x_get(c, C5X_REG_PREG);
    s->treg0 = (uint16_t)c5x_get(c, C5X_REG_T0);
    s->treg1 = (uint16_t)c5x_get(c, C5X_REG_T1);
    s->treg2 = (uint16_t)c5x_get(c, C5X_REG_T2);
    for (int i = 0; i < 8; i++)
        s->ar[i] = (uint16_t)c5x_get(c, C5X_REG_AR0 + i);
    s->arp    = (uint16_t)((c5x_get(c, C5X_REG_ST0) >> 13) & 7);
    s->ar_cur = s->ar[s->arp];
    s->st0  = (uint16_t)c5x_get(c, C5X_REG_ST0);
    s->st1  = (uint16_t)c5x_get(c, C5X_REG_ST1);
    s->pmst = (uint16_t)c5x_get(c, C5X_REG_PMST);
    s->rptc = c->rptc;
    s->brcr = c->brcr;
    s->sp   = (uint16_t)c5x_get(c, C5X_REG_SP);
    for (int i = 0; i < 8; i++)
        s->stack[i] = c->stack[i];
    s->stack_top = c->stack[c->sp & 7];
    s->ifr  = (uint16_t)c5x_get(c, C5X_REG_IFR);
    s->imr  = (uint16_t)c5x_get(c, C5X_REG_IMR);
    s->tim  = (uint16_t)c5x_get(c, C5X_REG_TIM);
    s->prd  = (uint16_t)c5x_get(c, C5X_REG_PRD);
    s->dxr  = (uint16_t)c5x_get(c, C5X_REG_DXR);
    s->drr  = (uint16_t)c5x_get(c, C5X_REG_DRR);
    s->bmar = c->bmar;
    s->dbmr = c->dbmr;
    s->indx = c->indx;
    s->arcr = c->arcr;
    s->pasr = c->pasr;
    s->paer = c->paer;
    s->greg = c->greg;
    s->spc  = c->spc;
    s->spc_rd = (uint16_t)((c->spc & 0xC0FE) | (c->rsrfull << 13) |
                           (c->xsrempty << 12) | (c->xrdy << 11) |
                           (c->rrdy << 10));
    s->tcr  = (uint16_t)(((c->psc & 0xF) << 6) | ((c->tss & 1) << 4) |
                         (c->tcr_tddr & 0xF));
    s->pdwsr = c->pdwsr;
    s->iowsr = c->iowsr;
    s->cwsr  = c->cwsr;
    s->cycles = c->cycles;
    s->idle   = c->idle;
    s->status = c->status;
}

uint16_t *cref_pmem(C5x *c) { return c5x_pmem(c); }
uint16_t *cref_dmem(C5x *c) { return c5x_dmem(c); }
uint16_t *cref_iomem(C5x *c) { return c5x_iomem(c); }

uint32_t cref_iolog_count(C5x *c) { return c5x_iolog_count(c); }

void cref_iolog_enable(C5x *c, int on) { c5x_iolog_enable(c, on); }

int cref_iolog_entry(C5x *c, uint32_t i, CIoEv *ev)
{
    C5xIoEv e;
    if (i >= c5x_iolog_count(c))
        return -1;
    // iolog is a flat array in the C core (c5x_iolog() accessor).
    e = c5x_iolog(c)[i];
    ev->cyc  = e.cyc;
    ev->pc   = e.pc;
    ev->port = e.port;
    ev->val  = e.val;
    ev->wr   = e.wr;
    return 0;
}

uint64_t cref_total_cycles(C5x *c) { return c5x_total_cycles(c); }
