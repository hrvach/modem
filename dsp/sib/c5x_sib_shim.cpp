// Shim: exports the c5x_* C API of dsp/c5x_core.c on top of the courier-emu C5x core
// (copied to this directory, see README.txt). Experiment only: lets sys/machine.py run the
// SV25 DSP image on the sibling project's core (DSP_CORE=sib) to compare behaviour.
//
// What is NOT provided (stubs): I/O log, PC ring, PC hit counts, breakpoints, watch/trace,
// MMR/FF/external access counters. Only what sys/machine.py and the call tools need.
#include "c5x_core.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <vector>

using courier::C5xCore;

struct IoEv { uint64_t cyc; uint16_t pc, port, val; uint8_t wr; };
typedef uint16_t (*io_rd_fn)(void *, uint16_t);
typedef void (*io_wr_fn)(void *, uint16_t, uint16_t);

struct C5x {
    C5xCore core{C5xCore::Model::C51};
    io_rd_fn rd = nullptr; io_wr_fn wr = nullptr; void *ctx = nullptr;
    int xint_mode = 1, xint_first = 1;
    uint16_t pcring[256] = {};
    uint32_t hits[65536] = {};
    IoEv iolog[1] = {};
};

static void load_rom_file(C5x *c)
{
    const char *path = getenv("SIB_ROM");
    if (path && !*path) return;                     // SIB_ROM= (empty): no ROM at all
    if (!path) path = "../fw/c5x-onchip-rom-8k.bin"; // relative to dsp/ (the Python loader sets cwd-independent path via env)
    std::ifstream f(path, std::ios::binary);
    if (!f) { fprintf(stderr, "c5x_sib: cannot read ROM %s\n", path); return; }
    std::vector<uint8_t> b((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    std::vector<uint16_t> w(b.size() / 2);
    for (size_t i = 0; i < w.size(); ++i) w[i] = uint16_t(b[2 * i] | b[2 * i + 1] << 8);
    if (w.size() > 0x2000) w.resize(0x2000);
    c->core.load_rom(w.data(), w.size(), 0);
}

extern "C" {

C5x *c5x_new()
{
    C5x *c = new C5x();
    C5xCore &k = c->core;
    k.m_shim = true;
    k.set_mpmc_pin(0);                              // MP/MC = 0: on-chip ROM visible at 0x0000 (vector stubs)
    k.set_shared_window(0x0080, 0xFFFF);            // one external RAM in both spaces, as in dsp/c5x_core.c
    k.set_io_callbacks(
        [c](uint16_t p) -> uint16_t { return c->rd ? c->rd(c->ctx, p) : 0; },
        [c](uint16_t p, uint16_t v) { if (c->wr) c->wr(c->ctx, p, v); });
    load_rom_file(c);
    k.trace_register(0, 0);
    return c;
}

uint16_t *c5x_pmem(C5x *c) { return c->core.m_program.data(); }
uint16_t *c5x_dmem(C5x *c) { return c->core.m_data.data(); }   // raw backing store only: use c5x_dm_get/set
uint16_t *c5x_iomem(C5x *c) { return c->core.m_io.data(); }
uint32_t *c5x_hits(C5x *c) { return c->hits; }
IoEv *c5x_iolog(C5x *c) { return c->iolog; }
uint32_t c5x_iolog_count(C5x *) { return 0; }
void c5x_iolog_clear(C5x *) {}
void c5x_iolog_enable(C5x *, int) {}
void c5x_set_io(C5x *c, io_rd_fn rd, io_wr_fn wr, void *ctx) { c->rd = rd; c->wr = wr; c->ctx = ctx; }
void c5x_set_bp(C5x *, uint16_t, int) {}
void c5x_stop(C5x *) {}
void c5x_set_bio(C5x *c, int v) { c->core.set_bio_low(!v); }
uint16_t *c5x_pcring(C5x *c) { return c->pcring; }
uint32_t c5x_pcring_idx(C5x *) { return 0; }

uint16_t c5x_dm_get(C5x *c, uint16_t a) { return a < 0x60 ? c->core.register_value(a) : c->core.data(a); }
void c5x_dm_set(C5x *c, uint16_t a, uint16_t v) { c->core.set_data(a, v); }
uint16_t c5x_pm_get(C5x *c, uint16_t a) { return c->core.program(a); }
void c5x_pm_load(C5x *c, uint16_t a, const uint16_t *w, uint32_t n) { for (uint32_t i = 0; i < n; ++i) c->core.m_program[uint16_t(a + i)] = w[i]; }

void c5x_reset(C5x *c, uint16_t pc)
{
    C5xCore &k = c->core;
    k.reset();
    k.set_pc(pc);
    k.m_timer.tim = k.m_timer.prd = 0xFFFF;         // dsp/c5x_core.c: TIM = PRD = FFFF out of reset
    k.m_shim_xrdy = true; k.m_shim_rrdy = false;
    c->xint_first = 1;
}

enum { S_PC, S_ACC, S_ACCB, S_PREG, S_T0, S_T1, S_T2, S_AR0, S_ST0 = 20, S_ST1, S_PMST, S_RPTC,
       S_IFR, S_IMR, S_SP, S_CYC_LO, S_CYC_HI, S_BMAR, S_DBMR, S_INDX, S_ARCR, S_DXR, S_DRR, S_TIM, S_PRD, S_IDLE };

uint32_t c5x_get(C5x *c, int id)
{
    C5xCore &k = c->core;
    if (id >= S_AR0 && id < S_AR0 + 8) return k.m_ar[id - S_AR0];
    switch (id) {
    case S_PC: return k.m_pc; case S_ACC: return uint32_t(k.m_acc); case S_ACCB: return uint32_t(k.m_accb);
    case S_PREG: return uint32_t(k.m_preg);
    case S_T0: return k.m_treg0; case S_T1: return k.m_treg1; case S_T2: return k.m_treg2;
    case S_ST0: return (k.m_st0.arp << 13) | (k.m_st0.ov << 12) | (k.m_st0.ovm << 11) | (1 << 10) | (k.m_st0.intm << 9) | (k.m_st0.dp >> 7);
    case S_ST1: return (k.m_st1.arb << 13) | (k.m_st1.cnf << 12) | (k.m_st1.tc << 11) | (k.m_st1.sxm << 10) | (k.m_st1.c << 9) | (1 << 8) | (1 << 7)
                       | (k.m_st1.hm << 6) | (1 << 5) | (k.m_st1.xf << 4) | (1 << 3) | (1 << 2) | k.m_st1.pm;
    case S_PMST: return (k.m_pmst.iptr << 11) | (k.m_pmst.avis << 7) | (k.m_pmst.ovly << 5) | (k.m_pmst.ram << 4) | (k.m_pmst.mpmc << 3)
                        | (k.m_pmst.ndx << 2) | (k.m_pmst.trm << 1) | k.m_pmst.braf;
    case S_RPTC: return uint32_t(k.m_rptc); case S_IFR: return k.m_ifr; case S_IMR: return k.m_imr;
    case S_SP: return k.m_pcstack_ptr;
    case S_CYC_LO: return uint32_t(k.m_cycles); case S_CYC_HI: return uint32_t(k.m_cycles >> 32);
    case S_BMAR: return k.m_bmar; case S_DBMR: return k.m_dbmr; case S_INDX: return k.m_indx; case S_ARCR: return k.m_arcr;
    case S_DXR: return k.m_serial.dxr; case S_DRR: return k.m_serial.drr;
    case S_TIM: k.sync_timer_view(); return k.m_timer.tim;
    case S_PRD: return k.m_timer.prd;
    case S_IDLE: return k.m_ff.idle;
    }
    return 0;
}

void c5x_set(C5x *c, int id, uint32_t v)
{
    C5xCore &k = c->core;
    if (id >= S_AR0 && id < S_AR0 + 8) { k.m_ar[id - S_AR0] = uint16_t(v); return; }
    switch (id) {
    case S_PC: k.set_pc(uint16_t(v)); break;
    case S_ACC: k.m_acc = int32_t(v); break; case S_ACCB: k.m_accb = int32_t(v); break;
    case S_DRR: k.m_serial.drr = uint16_t(v); break; case S_DXR: k.m_serial.dxr = uint16_t(v); break;
    case S_IMR: k.m_imr = uint16_t(v); break;
    case 41: k.m_ff.idle = v != 0; break;
    }
}

void c5x_irq(C5x *c, int bit) { c->core.interrupt(unsigned(bit)); }
void c5x_reset_dummy() {}
int c5x_run(C5x *c, uint64_t budget) { c->core.run_cycles(budget); return 0; }

void c5x_serial_tick(C5x *c, int16_t rx)
{
    C5xCore &k = c->core; auto &s = k.m_serial;
    if (s.spc & 0x80) {                                           // RRST: receiver enabled
        s.drr = (s.spc & 0x02) ? s.dxr : uint16_t(rx);             // DLB loopback
        k.m_shim_rrdy = true;
        k.interrupt(4);                                            // RINT
    }
    if (s.spc & 0x40) {                                           // XRST: transmitter enabled
        const bool pending = !k.m_shim_xrdy;                       // DXR written since the previous frame
        k.m_shim_xrdy = true;
        if (!c->xint_mode || pending || c->xint_first) { c->xint_first = 0; k.interrupt(5); }   // XINT
    }
}
void c5x_set_xint_mode(C5x *c, int m) { c->xint_mode = m; c->xint_first = 1; }
void c5x_set_cycle_model(C5x *, int) {}                           // the sibling core has its own cycle accounting
void c5x_set_legacy(C5x *, int) {}
uint64_t c5x_idle_cycles(C5x *) { return 0; }
uint64_t c5x_total_cycles(C5x *c) { return c->core.m_cycles; }
uint64_t c5x_timer_expiries(C5x *c) { return c->core.m_timer_expiries; }      // host heartbeat (INT0) follows the DSP timer, see sys/machine.py HB_TIMER
void c5x_set_ivec_ind(C5x *, int, uint16_t) {}                   // vectors come from the on-chip ROM stubs instead
void c5x_set_cmpr_ar0(C5x *, int) {}
uint32_t c5x_dxr_head(C5x *c) { return c->core.m_dxr_head; }
uint16_t *c5x_dxr_ring(C5x *c) { return c->core.m_dxr_ring; }

void c5x_set_watch(C5x *, int32_t) {}
uint32_t c5x_watch_hits(C5x *, uint32_t) { return 0; }
uint32_t c5x_pc_hits(C5x *, uint32_t) { return 0; }
void c5x_pc_hits_clear(C5x *) {}
void c5x_set_trace(C5x *, int32_t) {}
uint32_t c5x_trace_n(C5x *) { return 0; }
void c5x_trace_get(C5x *, uint32_t, uint32_t *a, uint16_t *r, uint16_t *r2) { *a = 0; *r = 0; *r2 = 0; }
uint32_t c5x_mmr_count(C5x *, int, int) { return 0; }
uint16_t c5x_mmr_pc(C5x *, int, int) { return 0; }
void c5x_mmr_clear(C5x *) {}
uint16_t c5x_mmr_val(C5x *, int) { return 0; }
uint32_t c5x_ff_count(C5x *, int, int) { return 0; }
uint32_t c5x_ext_count(C5x *, int, int) { return 0; }
uint16_t c5x_rsv(C5x *, int) { return 0; }

}  // extern "C"
