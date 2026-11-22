// cosim.cpp -- co-simulation harness: C reference model vs RTL.
//
// Steps the C core (c5x_core.c, the spec) and the Verilated RTL and
// diffs the architectural state. First mismatch stops with both
// states printed. Modes:
//   --smoke N      tiny hand-written program (default N=4)
//   --firmware N   SV25 base image, per-instruction compare (default
//                  N=1000)
//   --dsp-smoke    DSP smoke gate: dsp_base.bin, 8 x 1M cycles,
//                  compare every checkpoint field plus both
//                  checksums and the IO event list (see below)
//   --selftest N   C-model only determinism check
//   --reset-check  compare post-reset state only
//
// Real-control-FSM protocol (step_i park, added 2026-11-19): the
// control FSM parks in DONE while step_i is low; tied high, DONE
// goes straight to FETCH_ADDR and the path is cycle-identical.
// The harness still ties step_i high and clocks the RTL one cycle
// at a time and reads the state the moment instr_done is visible,
// then clocks exactly one more cycle before the next step:
// instr_done is combinational on the DONE state, and the timer's
// last tick for the instruction lands on the DONE clock (the
// control FSM drains its cycle count one tick per clock in TICK,
// and the top-level burst counter applies the final tick on the
// DONE clock). After that one extra clock the architectural state
// is the completed instruction's state and the timer is exact;
// the next instruction is still in FETCH, so nothing has moved.
// No debug reads are done while the core runs: a debug read clocks
// the DUT and the free-running control FSM would execute ahead.
// The mem-owned registers (TIM/PRD/DXR/DRR/GREG/SPC/TCR/PDWSR/
// IOWSR/CWSR) are compared per instruction from the top-level
// obs_*_o outputs (direct observation from c5x_mem, sampled at
// instruction boundaries; SPC is the composed readback, as in
// mmr_rd). The timer is also validated through timer_expiries
// (timer_exp_cnt_o) in the DSP smoke gate. The old debug-sequencer
// outputs (tim_o..cwsr_o) are unchanged and unused by the
// per-instruction comparison.
//
// Memory: DMEM/PMEM are diffed per instruction. The C arrays are
// memcmp'd against the harness's RTL shadow, which starts from the
// loaded image and is updated from the RTL's mem_wr_* write events
// (no clocks are spent reading RTL memory back). IO events are
// compared as (pc, port, wr, val) sequences; the host IO array is
// shared: the C core's iomem[] and the RTL host model are the same
// 64K array in the harness, kept in sync from the C iolog and the
// RTL handshake. IO cycle stamps are NOT compared for exact
// equality: the C iolog stamps the access after the base-cycle
// charge, the RTL stamps it at the handshake; the (pc, port, wr,
// val) sequence is the exact check. The IO event's pc is the
// executing instruction's PC, tracked as the pc_o from the previous
// instr_done (prev_done_pc).
//
// DSP smoke gate (--dsp-smoke): loads dsp_base.bin into PMEM only
// (no overlays, no IO hooks, no serial ticks, no DMEM presets, no
// ivec_ind), resets at 0x8000, runs 8 x 1,000,000 cycles, and
// compares at each 1M-cycle checkpoint the vector's expected state
// (PC, ACC, T0, ST0, ST1, IFR, IMR, AR0-AR7, dxr_head,
// idle_cycles, total_cycles, timer_expiries) plus, at the end,
// pm_checksum, dm_checksum, dxr_ring_first16, recent_pcs and the
// 13 IO events. The vector is
//   c-port/c/tests/vectors/dsp_smoke_base.txt
// (sha256 9e358f6fd99018d07f9e7db1cd5b160ab9246808e387d29f3cb43650e2d689be)
// and the binary is c-port/modem/dsp/dsp_base.bin (55,420 bytes).
// The vector was generated from the Python DSP, not the C core, so
// a checkpoint is first checked against the C core (the reference)
// before the RTL is blamed. AR0-AR7: the full AR file is observable
// from the RTL (ar_all_o) and is compared at every checkpoint,
// as is the full stack (stack_all_o) in the per-instruction
// comparison.
//
// Usage: see docs/cosim.md and `cosim --help`.
// Exit code: 0 = all compared instructions/checkpoints matched,
// 1 = mismatch / error / watchdog.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "Vc5x_core.h"
#include "verilated.h"
#include "c_ref.h"

static const char *FW_DEFAULT =
    "/home/hatch/workspace/research_notes/courier-firmware/c-port/c/"
    "fw/dsp_base.bin";
static const char *DSP_SMOKE_BIN =
    "/home/hatch/workspace/research_notes/courier-firmware/c-port/"
    "modem/dsp/dsp_base.bin";
static const char *DSP_SMOKE_VECTOR =
    "/home/hatch/workspace/research_notes/courier-firmware/c-port/c/"
    "tests/vectors/dsp_smoke_base.txt";

// ------------------------------------------------------------------
// RTL state snapshot (mirrors CState; see c_ref.h). The full AR
// file and stack come from the top-level ar_all_o / stack_all_o
// observation outputs (AR0 in bits [15:0] of ar_all_o); the
// mem-owned registers come from the obs_*_o outputs, sampled at
// instruction boundaries. spc holds the composed readback (as
// mmr_rd returns it), matching CState.spc_rd.
// ------------------------------------------------------------------
struct RState {
    uint16_t pc, op;
    uint32_t acc, accb, preg;
    uint16_t treg0, treg1, treg2;
    uint16_t ar[8];
    uint16_t ar_cur, arp;
    uint16_t st0, st1, pmst;
    int32_t  rptc, brcr;
    uint16_t sp;
    uint16_t stack[8];
    uint16_t stack_top;
    uint16_t ifr, imr;
    uint16_t tim, prd, dxr, drr;
    uint16_t greg, spc, tcr, pdwsr, iowsr, cwsr;
    uint16_t bmar, dbmr, indx, arcr;
    uint16_t pasr, paer;
    uint64_t cycles;
    int      idle;
};

static void rtl_get_state(Vc5x_core *d, RState *s)
{
    memset(s, 0, sizeof *s);
    s->pc    = d->pc_o;
    s->op    = d->op_o;
    s->acc   = d->acc_o;
    s->accb  = d->accb_o;
    s->preg  = d->preg_o;
    s->treg0 = d->treg0_o;
    s->treg1 = d->treg1_o;
    s->treg2 = d->treg2_o;
    s->ar_cur = d->ar_cur_o;
    s->arp   = d->arp_o;
    s->st0  = d->st0_o;
    s->st1  = d->st1_o;
    s->pmst = d->pmst_o;
    s->rptc = (int32_t)d->rptc_o;
    s->brcr = (int32_t)d->brcr_o;
    s->sp   = d->sp_o;
    s->stack_top = d->stack_top_o;
    for (int i = 0; i < 8; i++) {
        // ar_all_o / stack_all_o are VlWide<4>: word w holds bits
        // [32w+31:32w], so AR[2w] is the low half of word w.
        s->ar[i] = (uint16_t)(d->ar_all_o[i >> 1] >> (16 * (i & 1)));
        s->stack[i] =
            (uint16_t)(d->stack_all_o[i >> 1] >> (16 * (i & 1)));
    }
    s->tim   = d->obs_tim_o;
    s->prd   = d->obs_prd_o;
    s->dxr   = d->obs_dxr_o;
    s->drr   = d->obs_drr_o;
    s->greg  = d->obs_greg_o;
    s->spc   = d->obs_spc_o;
    s->tcr   = d->obs_tcr_o;
    s->pdwsr = d->obs_pdwsr_o;
    s->iowsr = d->obs_iowsr_o;
    s->cwsr  = d->obs_cwsr_o;
    s->ifr  = d->ifr_o;
    s->imr  = d->imr_o;
    s->bmar = d->bmar_o;
    s->dbmr = d->dbmr_o;
    s->indx = d->indx_o;
    s->arcr = d->arcr_o;
    s->pasr = d->pasr_o;
    s->paer = d->paer_o;
    s->cycles = d->cycles_o;
    s->idle   = d->idle_o ? 1 : 0;
}

// Diagnostic: when set (--tolerate-cycles), the cycle-count field
// is logged but does not count as a mismatch, so the run continues
// past a known cycle-count bug to find the first STATE divergence.
static int g_tolerate_cycles = 0;

// ------------------------------------------------------------------
// State diff (directly observable fields only).
// ------------------------------------------------------------------
static int diff_state(const CState *c, const RState *r, int step,
                      uint16_t rpc, FILE *out)
{
    int n = 0;
#define CHK(field, fmt)                                                     \
    do {                                                                    \
        if (c->field != r->field) {                                         \
            if (n == 0)                                                     \
                fprintf(out,                                               \
                        "MISMATCH at instruction %d (RTL pc before step " \
                        "0x%04X):\n",                                      \
                        step, rpc);                                         \
            fprintf(out, "  %-6s C=" fmt " RTL=" fmt "\n", #field,          \
                    c->field, r->field);                                    \
            n++;                                                            \
        }                                                                   \
    } while (0)
    CHK(pc, "0x%04X");
    CHK(op, "0x%04X");
    CHK(acc, "0x%08X");
    CHK(accb, "0x%08X");
    CHK(preg, "0x%08X");
    CHK(treg0, "0x%04X");
    CHK(treg1, "0x%04X");
    CHK(treg2, "0x%04X");
    // AR file: all 8 registers, from ar_all_o.
    CHK(arp, "%u");
    CHK(ar_cur, "0x%04X");
    for (int i = 0; i < 8; i++) {
        if (c->ar[i] != r->ar[i]) {
            if (n == 0)
                fprintf(out,
                        "MISMATCH at instruction %d (RTL pc before step "
                        "0x%04X):\n",
                        step, rpc);
            fprintf(out, "  ar%d   C=0x%04X RTL=0x%04X\n", i, c->ar[i],
                    r->ar[i]);
            n++;
        }
    }
    CHK(st0, "0x%04X");
    CHK(st1, "0x%04X");
    CHK(pmst, "0x%04X");
    CHK(rptc, "%d");
    CHK(brcr, "%d");
    CHK(sp, "%u");
    // Stack: all 8 entries, from stack_all_o.
    CHK(stack_top, "0x%04X");
    for (int i = 0; i < 8; i++) {
        if (c->stack[i] != r->stack[i]) {
            if (n == 0)
                fprintf(out,
                        "MISMATCH at instruction %d (RTL pc before step "
                        "0x%04X):\n",
                        step, rpc);
            fprintf(out, "  stack%d C=0x%04X RTL=0x%04X\n", i, c->stack[i],
                    r->stack[i]);
            n++;
        }
    }
    CHK(ifr, "0x%04X");
    CHK(imr, "0x%04X");
    // Mem-owned registers, from obs_*_o. SPC: C holds the composed
    // readback in spc_rd; the RTL obs_spc_o is the same value.
    CHK(tim, "0x%04X");
    CHK(prd, "0x%04X");
    CHK(dxr, "0x%04X");
    CHK(drr, "0x%04X");
    CHK(greg, "0x%04X");
    if (c->spc_rd != r->spc) {
        if (n == 0)
            fprintf(out,
                    "MISMATCH at instruction %d (RTL pc before step "
                    "0x%04X):\n",
                    step, rpc);
        fprintf(out, "  spc    C=0x%04X RTL=0x%04X\n", c->spc_rd, r->spc);
        n++;
    }
    CHK(tcr, "0x%04X");
    CHK(pdwsr, "0x%04X");
    CHK(iowsr, "0x%04X");
    CHK(cwsr, "0x%04X");
    CHK(bmar, "0x%04X");
    CHK(dbmr, "0x%04X");
    CHK(indx, "0x%04X");
    CHK(arcr, "0x%04X");
    CHK(pasr, "0x%04X");
    CHK(paer, "0x%04X");
    if (c->cycles != r->cycles) {
        if (g_tolerate_cycles) {
            fprintf(out,
                    "  (tolerated) cycles C=%llu RTL=%llu at "
                    "instruction %d\n",
                    (unsigned long long)c->cycles,
                    (unsigned long long)r->cycles, step);
        } else {
            if (n == 0)
                fprintf(out,
                        "MISMATCH at instruction %d (RTL pc before step "
                        "0x%04X):\n",
                        step, rpc);
            fprintf(out, "  cycles C=%llu RTL=%llu\n",
                    (unsigned long long)c->cycles,
                    (unsigned long long)r->cycles);
            n++;
        }
    }
    CHK(idle, "%d");
#undef CHK
    if (n > 0) {
        fprintf(out, "  C state: pc=0x%04X op=0x%04X acc=0x%08X\n",
                c->pc, c->op, c->acc);
        fprintf(out, "  RTL state: pc=0x%04X op=0x%04X acc=0x%08X\n",
                r->pc, r->op, r->acc);
    }
    return n;
}

// ------------------------------------------------------------------
// DUT driver: clocking, reset/load, IO handshake, memory shadow,
// DXR ring, recent-PC ring, idle-cycle count.
// ------------------------------------------------------------------
struct IoEv {
    uint16_t pc;   // PC of the instruction that performed the access
    uint16_t port;
    uint16_t val;
    int      wr;
};

// Pseudo-port events: the C core's mmr_wr logs MMR writes as IO
// events with port 0x8000|a (DXR 0x8021, SPC 0x8022, unknown MMRs
// 0x8000|a). Of these only the DXR write is observable at the RTL
// top level (dxr_wr/dxr_wdata); SPC and unknown-MMR writes have no
// top-level strobe (o_ext_mmr_wr is unconnected at the top), so
// they are not comparable as events. Their architectural effects
// are still compared: SPC through obs_spc_o per instruction / per
// checkpoint, unknown-MMR writes through a later readback (the RTL
// returns 0 for external-MMR reads; a divergent read lands in
// compared state). An event is observable as an RTL event if it is
// a real IO access or a DXR pseudo-port write.
static bool io_event_pseudo_port(uint16_t port)
{
    return port >= 0x8000 && port < 0x8060;
}

static bool io_event_observable(uint16_t port)
{
    if (io_event_pseudo_port(port))
        return port == 0x8021; // DXR only
    return true;
}

struct Dut {
    Vc5x_core *d;
    uint64_t clocks = 0;
    uint16_t host_iomem[65536];
    // RTL memory shadow (starts from the loaded image).
    uint16_t shadow_pmem[65536];
    uint16_t shadow_dmem[65536];
    std::vector<IoEv> io_log;
    // DXR write ring (mirrors the C core's dxr_ring, 65536 entries).
    uint16_t dxr_ring[65536];
    uint32_t dxr_head = 0;
    // Recent PCs, in execution order (mirrors the C core's pcring).
    std::vector<uint16_t> recent_pcs;
    // Model cycles spent idle (IDLE instruction; the C core's
    // idle_cycles). Counts clocks where idle_o is high.
    uint64_t idle_cycles = 0;
    // PC of the instruction currently executing: the pc_o from the
    // previous instr_done (that pc_o is the next instruction's
    // address, i.e. the one now executing). At reset it is the
    // reset PC.
    uint16_t prev_done_pc = 0x8000;
    int prev_instr_done = 0;
    // Previous io_req level: the host-window io_req is a LEVEL
    // that stays high for the request clock and the ack-drop clock,
    // so the event is logged only on its rising edge.
    int prev_io_req = 0;
    // Previous dxr_wr level (pre-edge sample): the DXR write strobe
    // is a single-cycle pulse in the presentation clock, so the
    // event is logged only on its rising edge.
    int prev_dxr_wr = 0;
    // Completed-instruction count (instr_done rising edges).
    uint64_t instr_done_count = 0;

    Dut()
    {
        memset(host_iomem, 0, sizeof host_iomem);
        memset(shadow_pmem, 0, sizeof shadow_pmem);
        memset(shadow_dmem, 0, sizeof shadow_dmem);
        memset(dxr_ring, 0, sizeof dxr_ring);
        d = new Vc5x_core;
        d->clk = 0;
        d->rst_n = 0;
        // step_i parks the control FSM in DONE while low (added
        // 2026-11-19). Tie it high: free-running, as in a real
        // system.
        d->step_i = 1;
        d->irq_i = 0;
        d->bio_i = 0;
        d->ser_tick = 0;
        d->ser_rx = 0;
        d->xint_mode = 1; // as the C driver sets it (c5x_set_xint_mode(1))
        d->io_rdata = 0;
        d->io_ack = 0;
        d->load_en = 0;
        d->load_pmem = 0;
        d->load_addr = 0;
        d->load_data = 0;
        d->dbg_en = 0;
        d->dbg_addr = 0;
        set_ivec_ind_zero();
        d->eval();
    }

    // Drive ivec_ind_i (nine 16-bit entries, entry i at [i*16 +: 16])
    // from the C core's ivec_ind[0..8].
    void set_ivec_ind(C5x *c)
    {
        uint16_t e[9];
        for (int i = 0; i < 9; i++)
            e[i] = cref_ivec_ind(c, i);
        d->ivec_ind_i[0] = (uint32_t)e[0] | ((uint32_t)e[1] << 16);
        d->ivec_ind_i[1] = (uint32_t)e[2] | ((uint32_t)e[3] << 16);
        d->ivec_ind_i[2] = (uint32_t)e[4] | ((uint32_t)e[5] << 16);
        d->ivec_ind_i[3] = (uint32_t)e[6] | ((uint32_t)e[7] << 16);
        d->ivec_ind_i[4] = (uint32_t)e[8];
        d->eval();
    }

    void set_ivec_ind_zero()
    {
        for (int i = 0; i < 5; i++)
            d->ivec_ind_i[i] = 0;
        d->eval();
    }

    // One clock cycle. Services the IO handshake: if the core is
    // requesting an access, the host answers in the same cycle (ack
    // asserted before the rising edge), so the access completes on
    // that edge. The mem's o_io_req is a LEVEL (it drops at the
    // completing edge), so the transaction is captured BEFORE the
    // edge, not after. Tracks the DXR ring, the recent-PC ring
    // (on the rising edge of instr_done), and idle cycles.
    // Returns 1 if an IO transaction completed on this edge.
    int tick()
    {
        int completed = 0;
        d->clk = 0;
        d->eval();
        // Capture the pending IO transaction before the edge.
        // The top level signals io_rd (1 = read, 0 = write).
        int io_pending = d->io_req ? 1 : 0;
        uint16_t io_port = d->io_port;
        int io_wr = d->io_rd ? 0 : 1;
        uint16_t io_wdata = d->io_wdata;
        // Capture the DXR write strobe before the edge. o_dxr_wr is
        // a single-cycle pulse (dm_accept in the presentation
        // clock); sampling it after the edge misses it entirely
        // (dm_ack_q clears dm_accept), which is why the old
        // post-edge dxr_ring capture never saw a write.
        int dxr_pending = d->dxr_wr ? 1 : 0;
        uint16_t dxr_wdata_s = d->dxr_wdata;
        if (io_pending) {
            d->io_ack = 1;
            if (!io_wr)
                d->io_rdata = host_iomem[io_port];
            else
                d->io_rdata = 0;
            d->eval(); // settle combinationally, clk still low
        } else {
            d->io_ack = 0;
        }
        d->clk = 1;
        d->eval();
        clocks++;
        // Log the IO event once, on the rising edge of io_req.
        // The request level stays high for two clocks (the request
        // clock and the clock on which the source drops it after
        // seeing the ack), so logging on every high clock would
        // double-count.
        if (io_pending && d->io_ack && !prev_io_req) {
            IoEv e;
            e.pc = prev_done_pc;
            e.port = io_port;
            e.wr = io_wr;
            if (io_wr) {
                e.val = io_wdata;
                host_iomem[io_port] = io_wdata;
            } else {
                e.val = d->io_rdata;
            }
            io_log.push_back(e);
            completed = 1;
        }
        prev_io_req = io_pending ? 1 : 0;
        if (d->mem_wr_pulse) {
            if (d->mem_wr_pmem)
                shadow_pmem[d->mem_wr_addr] = d->mem_wr_data;
            else
                shadow_dmem[d->mem_wr_addr] = d->mem_wr_data;
        }
        if (dxr_pending && !prev_dxr_wr) {
            dxr_ring[dxr_head & 0xFFFF] = dxr_wdata_s;
            dxr_head++;
            // The C core logs a DXR write as a pseudo-port IO event
            // (port 0x8021); log the same event for the RTL so the
            // per-step and smoke-gate IO comparisons see it.
            IoEv e;
            e.pc = prev_done_pc;
            e.port = 0x8021;
            e.val = dxr_wdata_s;
            e.wr = 1;
            io_log.push_back(e);
        }
        prev_dxr_wr = dxr_pending ? 1 : 0;
        if (d->idle_o)
            idle_cycles++;
        // Rising edge of instr_done: the instruction whose PC is
        // prev_done_pc just completed; the new pc_o is the next
        // instruction's address.
        if (d->instr_done && !prev_instr_done) {
            recent_pcs.push_back(prev_done_pc);
            prev_done_pc = d->pc_o;
            instr_done_count++;
        }
        prev_instr_done = d->instr_done ? 1 : 0;
        d->clk = 0;
        d->eval();
        d->io_ack = 0;
        return completed;
    }

    // Harness-only debug read through the top-level debug port.
    // Only safe when the core is halted (BADOP) or before release
    // of reset: a debug read clocks the DUT and the free-running
    // control FSM would execute ahead. Returns the read word, or
    // 0xFFFF on watchdog timeout (caller checks `ok`).
    uint16_t debug_read(uint16_t addr, long max_clocks, int *ok)
    {
        *ok = 0;
        d->dbg_addr = addr;
        d->dbg_en = 1;
        for (long i = 0; i < max_clocks; i++) {
            tick();
            if (d->dbg_done) {
                *ok = 1;
                break;
            }
        }
        uint16_t v = d->dbg_rdata;
        d->dbg_en = 0;
        tick(); // let the sequencer return to idle
        return v;
    }

    void reset_clocks(int n)
    {
        d->rst_n = 0;
        d->load_en = 0;
        for (int i = 0; i < n; i++)
            tick();
        prev_done_pc = 0x8000;
        prev_instr_done = 0;
    }

    // Load one word while held in reset.
    void load_word(int pmem, uint16_t addr, uint16_t data)
    {
        d->load_en = 1;
        d->load_pmem = pmem ? 1 : 0;
        d->load_addr = addr;
        d->load_data = data;
        tick();
        d->load_en = 0;
        if (pmem)
            shadow_pmem[addr] = data;
        else
            shadow_dmem[addr] = data;
    }

    void release_reset()
    {
        d->rst_n = 1;
        d->eval();
    }

    // Clock until instr_done rises. Returns clocks used, or -1 on
    // watchdog timeout. instr_done is combinational on the DONE
    // state; the timer's last tick for the instruction lands on
    // the DONE clock, so one extra clock is taken after seeing
    // instr_done before the caller reads the state. After that
    // extra clock the architectural state is the completed
    // instruction's state and the timer is exact; the next
    // instruction is still in FETCH.
    long run_to_instr_done(long max_clocks)
    {
        for (long i = 0; i < max_clocks; i++) {
            tick();
            if (d->instr_done) {
                tick(); // DONE clock: final timer tick lands here
                return i + 2;
            }
        }
        return -1;
    }

    // Clock until cycles_o reaches `target`, then until the next
    // instr_done rising edge, so the caller reads state at an
    // instruction boundary, not mid-instruction. The cycle counter
    // is advanced during TICK, but the instruction does not retire
    // until TAIL (C/OV writeback, ndx_commit) and DONE (instr_done
    // pulse); stopping at the end of TICK reads pre-retirement
    // state (checkpoint 1 failed on st0 DP and TIM for exactly this
    // reason: cycles_o was already 1000003 but the crossing
    // instruction had not gone through TAIL/DONE). TAIL and DONE
    // advance no cycles and emit no timer ticks, so total_cycles at
    // the boundary is still the target. If the core is idle (no
    // instruction in flight) the boundary is the current clock. A
    // safety bound stops the wait if no instr_done arrives (stuck
    // FSM): the caller then sees the overshoot in total_cycles.
    // Returns clocks used, or -1 on watchdog timeout.
    long run_to_cycles(uint64_t target, long max_clocks)
    {
        for (long i = 0; i < max_clocks; i++) {
            uint64_t n0 = instr_done_count;
            tick();
            if (d->cycles_o >= target) {
                if (instr_done_count > n0)
                    return i + 1;
                if (d->idle_o)
                    return i + 1;
                if (d->cycles_o > target + 4096)
                    return i + 1;
            }
        }
        return (d->cycles_o >= target) ? max_clocks : -1;
    }
};

// ------------------------------------------------------------------
// Memory diff: C arrays vs RTL shadow. Returns the first differing
// address, or -1 when identical.
// ------------------------------------------------------------------
static long mem_diff(const uint16_t *a, const uint16_t *b, uint16_t *addr,
                     uint16_t *av, uint16_t *bv)
{
    for (long i = 0; i < 65536; i++) {
        if (a[i] != b[i]) {
            *addr = (uint16_t)i;
            *av = a[i];
            *bv = b[i];
            return i;
        }
    }
    return -1;
}

static uint32_t checksum_sum(const uint16_t *a, uint32_t base, uint32_t n)
{
    uint64_t s = 0;
    for (uint32_t i = 0; i < n; i++)
        s += a[(base + i) & 0xFFFF];
    return (uint32_t)(s & 0xFFFFFFFFu);
}

// ------------------------------------------------------------------
// DSP smoke-gate vector (dsp_smoke_base.txt).
// ------------------------------------------------------------------
struct SmokeCheckpoint {
    uint64_t cycles;
    uint16_t pc;
    uint32_t acc;
    uint16_t t0, st0, st1, ifr, imr;
    uint16_t ar[8];
    uint32_t dxr_head;
    uint64_t idle_cycles;
    uint64_t total_cycles;
    uint64_t timer_expiries;
};

struct SmokeVector {
    SmokeCheckpoint ckpt[8];
    int nckpt = 0;
    uint32_t pm_checksum = 0;
    uint32_t dm_checksum = 0;
    uint16_t dxr_ring_first16[16];
    uint16_t recent_pcs[16];
    struct Ev {
        uint64_t cyc;
        uint16_t pc, port, val;
        int wr;
    };
    std::vector<Ev> io_events;
};

// Parse one field "KEY=VALUE" from a line. VALUE is hex (no 0x
// prefix) for the register fields (PC/ACC/T0/ST0/ST1/IFR/IMR/AR)
// and decimal for the counter fields (dxr_head/idle_cycles/
// total_cycles/timer_expiries). Returns 1 and sets *v on success,
// 0 otherwise.
static int scan_field(const char *line, const char *key, uint64_t *v,
                      int base)
{
    const char *p = strstr(line, key);
    if (!p)
        return 0;
    p += strlen(key);
    if (*p != '=')
        return 0;
    p++;
    char *end = NULL;
    unsigned long long x = strtoull(p, &end, base);
    if (end == p)
        return 0;
    *v = (uint64_t)x;
    return 1;
}

static int scan_hex_field(const char *line, const char *key, uint64_t *v)
{
    return scan_field(line, key, v, 16);
}

static int scan_dec_field(const char *line, const char *key, uint64_t *v)
{
    return scan_field(line, key, v, 10);
}

static int parse_smoke_vector(const char *path, SmokeVector *vec)
{
    FILE *f = fopen(path, "r");
    if (!f)
        return -1;
    char line[1024];
    int in_io = 0;
    while (fgets(line, sizeof line, f)) {
        if (line[0] == '#')
            continue;
        if (strncmp(line, "after ", 6) == 0) {
            if (vec->nckpt >= 8) {
                fclose(f);
                return -2;
            }
            SmokeCheckpoint *k = &vec->ckpt[vec->nckpt];
            memset(k, 0, sizeof *k);
            uint64_t v = 0;
            if (!scan_hex_field(line, "PC", &v))
                goto bad;
            k->pc = (uint16_t)v;
            if (!scan_hex_field(line, "ACC", &v))
                goto bad;
            k->acc = (uint32_t)v;
            if (!scan_hex_field(line, "T0", &v))
                goto bad;
            k->t0 = (uint16_t)v;
            if (!scan_hex_field(line, "ST0", &v))
                goto bad;
            k->st0 = (uint16_t)v;
            if (!scan_hex_field(line, "ST1", &v))
                goto bad;
            k->st1 = (uint16_t)v;
            if (!scan_hex_field(line, "IFR", &v))
                goto bad;
            k->ifr = (uint16_t)v;
            if (!scan_hex_field(line, "IMR", &v))
                goto bad;
            k->imr = (uint16_t)v;
            for (int i = 0; i < 8; i++) {
                char key[8];
                snprintf(key, sizeof key, "AR%d", i);
                if (!scan_hex_field(line, key, &v))
                    goto bad;
                k->ar[i] = (uint16_t)v;
            }
            if (!scan_dec_field(line, "dxr_head", &v))
                goto bad;
            k->dxr_head = (uint32_t)v;
            if (!scan_dec_field(line, "idle_cycles", &v))
                goto bad;
            k->idle_cycles = v;
            if (!scan_dec_field(line, "total_cycles", &v))
                goto bad;
            k->total_cycles = v;
            if (!scan_dec_field(line, "timer_expiries", &v))
                goto bad;
            k->timer_expiries = v;
            // The leading cycle count ("after N cycles") is the
            // checkpoint's cycle target.
            k->cycles = (uint64_t)strtoull(line + 6, NULL, 10);
            vec->nckpt++;
            continue;
        }
        if (strncmp(line, "pm_checksum:", 12) == 0) {
            const char *p = strstr(line, "= ");
            if (!p)
                goto bad;
            vec->pm_checksum = (uint32_t)strtoul(p + 2, NULL, 10);
            continue;
        }
        if (strncmp(line, "dm_checksum:", 12) == 0) {
            const char *p = strstr(line, "= ");
            if (!p)
                goto bad;
            vec->dm_checksum = (uint32_t)strtoul(p + 2, NULL, 10);
            continue;
        }
        if (strncmp(line, "dxr_ring_first16:", 17) == 0) {
            const char *p = line + 17;
            for (int i = 0; i < 16; i++) {
                char *end = NULL;
                long x = strtol(p, &end, 10);
                if (end == p)
                    goto bad;
                vec->dxr_ring_first16[i] = (uint16_t)x;
                p = end;
            }
            continue;
        }
        if (strncmp(line, "recent_pcs(16):", 15) == 0) {
            const char *p = line + 15;
            for (int i = 0; i < 16; i++) {
                char *end = NULL;
                long x = strtol(p, &end, 16);
                if (end == p)
                    goto bad;
                vec->recent_pcs[i] = (uint16_t)x;
                p = end;
            }
            continue;
        }
        if (strncmp(line, "io_events:", 10) == 0) {
            in_io = 1;
            continue;
        }
        if (in_io) {
            // "  <cyc> pc=XXXX W|R port=XXXX val=XXXX"
            char *end = NULL;
            unsigned long long cyc = strtoull(line, &end, 10);
            if (end == line)
                continue; // blank / trailing line
            SmokeVector::Ev e;
            e.cyc = cyc;
            uint64_t v = 0;
            if (!scan_hex_field(line, "pc", &v))
                goto bad;
            e.pc = (uint16_t)v;
            const char *w = strstr(line, " W ");
            const char *r = strstr(line, " R ");
            if (w)
                e.wr = 1;
            else if (r)
                e.wr = 0;
            else
                goto bad;
            if (!scan_hex_field(line, "port", &v))
                goto bad;
            e.port = (uint16_t)v;
            if (!scan_hex_field(line, "val", &v))
                goto bad;
            e.val = (uint16_t)v;
            vec->io_events.push_back(e);
            continue;
        }
    }
    fclose(f);
    return 0;
bad:
    fclose(f);
    return -2;
}

static void usage(const char *argv0)
{
    fprintf(stderr,
            "usage: %s [options]\n"
            "  --smoke [N]        tiny hand-written program (default N=4)\n"
            "  --firmware [N]     SV25 base image from reset (default N=1000)\n"
            "  --dsp-smoke        DSP smoke gate: dsp_base.bin, 8 x 1M cycles\n"
            "  --image PATH       firmware image path (default: %s)\n"
            "  --vector PATH      smoke vector path (default: %s)\n"
            "  --selftest [N]     C-model only: determinism check (default N=1000)\n"
            "  --reset-check      compare post-reset state only, then exit\n"
            "  --max-clocks N     RTL watchdog clocks per step (default 100000)\n"
            "  --tolerate-cycles  diagnostic: log cycle-count mismatches\n"
            "                     but continue (finds the first STATE\n"
            "                     divergence past a known cycle bug)\n"
            "  --verbose          print progress every 1024 instructions\n",
            argv0, FW_DEFAULT, DSP_SMOKE_VECTOR);
}

// Load a binary file (little-endian words) into the RTL via the
// load port. Returns the word count, or -1 on error.
static long rtl_load_image(Dut &dut, const char *path, uint16_t base)
{
    FILE *f = fopen(path, "rb");
    if (!f)
        return -1;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> img((size_t)n);
    if (fread(img.data(), 1, (size_t)n, f) != (size_t)n) {
        fclose(f);
        return -1;
    }
    fclose(f);
    for (long i = 0; i < n / 2; i++) {
        uint16_t w = (uint16_t)(img[2 * i] | (img[2 * i + 1] << 8));
        dut.load_word(1, (uint16_t)(base + i), w);
    }
    return n / 2;
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);

    enum Mode {
        MODE_SMOKE,
        MODE_FIRMWARE,
        MODE_DSP_SMOKE,
        MODE_SELFTEST,
        MODE_RESET
    } mode = MODE_FIRMWARE;
    long steps = 1000;
    long max_clocks = 100000;
    int verbose = 0;
    int tolerate_cycles = 0;
    std::string image = FW_DEFAULT;
    std::string vector_path = DSP_SMOKE_VECTOR;

    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        auto need_n = [&](long &v, long dflt) {
            if (i + 1 < argc && argv[i + 1][0] != '-')
                v = atol(argv[++i]);
            else
                v = dflt;
        };
        if (a == "--smoke") {
            mode = MODE_SMOKE;
            need_n(steps, 4);
        } else if (a == "--firmware") {
            mode = MODE_FIRMWARE;
            need_n(steps, 1000);
        } else if (a == "--dsp-smoke") {
            mode = MODE_DSP_SMOKE;
        } else if (a == "--image" && i + 1 < argc) {
            image = argv[++i];
        } else if (a == "--vector" && i + 1 < argc) {
            vector_path = argv[++i];
        } else if (a == "--selftest") {
            mode = MODE_SELFTEST;
            need_n(steps, 1000);
        } else if (a == "--reset-check") {
            mode = MODE_RESET;
        } else if (a == "--max-clocks" && i + 1 < argc) {
            max_clocks = atol(argv[++i]);
        } else if (a == "--tolerate-cycles") {
            tolerate_cycles = 1;
            g_tolerate_cycles = 1;
        } else if (a == "--verbose") {
            verbose = 1;
        } else if (a == "--help" || a == "-h") {
            usage(argv[0]);
            return 0;
        } else {
            fprintf(stderr, "cosim: unknown option '%s'\n", a.c_str());
            usage(argv[0]);
            return 2;
        }
    }

    // ---- C model setup ----
    C5x *c = cref_new();
    uint16_t smoke_prog[4] = {
        0xBC00, // LDP #0
        0xB934, // LACK #0x34
        0x9060, // SACL 0x60 (direct, DP=0; B2 RAM, not an MMR)
        0xB900, // LACK #0
    };
    if (mode == MODE_SMOKE) {
        cref_load_program(c, smoke_prog, 4, 0x8000);
    } else if (mode == MODE_DSP_SMOKE) {
        if (cref_load_smoke(c, DSP_SMOKE_BIN) != 0) {
            fprintf(stderr, "cosim: cannot read smoke image '%s'\n",
                    DSP_SMOKE_BIN);
            return 2;
        }
    } else {
        if (cref_load_firmware(c, image.c_str()) != 0) {
            fprintf(stderr, "cosim: cannot read firmware image '%s'\n",
                    image.c_str());
            return 2;
        }
    }

    if (mode == MODE_SELFTEST) {
        // C-only determinism check: run twice from reset, compare the
        // final state, cycle count and IO log.
        CState s1, s2;
        uint32_t io1 = 0, io2 = 0;
        for (long i = 0; i < steps; i++) {
            int st = cref_step(c);
            if (st != 0) {
                fprintf(stderr, "selftest: C step %ld returned status %d\n",
                        i + 1, st);
                return 1;
            }
        }
        cref_get_state(c, &s1);
        io1 = cref_iolog_count(c);
        C5x *c2 = cref_new();
        if (cref_load_firmware(c2, image.c_str()) != 0)
            return 2;
        for (long i = 0; i < steps; i++) {
            int st = cref_step(c2);
            if (st != 0) {
                fprintf(stderr, "selftest: C run 2 step %ld status %d\n",
                        i + 1, st);
                return 1;
            }
        }
        cref_get_state(c2, &s2);
        io2 = cref_iolog_count(c2);
        int bad = memcmp(&s1, &s2, sizeof s1) != 0 || io1 != io2;
        printf("selftest: %ld steps, final pc=0x%04X op=0x%04X "
               "acc=0x%08X cycles=%llu io_events=%u/%u : %s\n",
               steps, s1.pc, s1.op, s1.acc,
               (unsigned long long)s1.cycles, io1, io2,
               bad ? "MISMATCH (non-deterministic!)" : "deterministic OK");
        return bad ? 1 : 0;
    }

    // ---- RTL setup: reset, load the same image ----
    Dut dut;
    dut.reset_clocks(4);
    if (mode == MODE_SMOKE) {
        for (int i = 0; i < 4; i++)
            dut.load_word(1, 0x8000 + i, smoke_prog[i]);
    } else if (mode == MODE_DSP_SMOKE) {
        if (rtl_load_image(dut, DSP_SMOKE_BIN, 0x8000) < 0) {
            fprintf(stderr, "cosim: cannot read smoke image '%s'\n",
                    DSP_SMOKE_BIN);
            return 2;
        }
        // Smoke gate: no DMEM presets, no ivec_ind (all zero,
        // as the C core's ivec_ind defaults). set_ivec_ind_zero()
        // was applied in the Dut constructor.
    } else {
        if (rtl_load_image(dut, image.c_str(), 0x8000) < 0) {
            fprintf(stderr, "cosim: cannot read firmware image '%s'\n",
                    image.c_str());
            return 2;
        }
        // sv25 DMEM presets (same as cref_load_firmware).
        for (int i = 0; i < 11; i++)
            dut.load_word(0, 0x60 + i, 0x81AE);
        dut.load_word(0, 0x65, 0x8189);
        dut.load_word(0, 0x68, 0x820C);
        dut.load_word(0, 0x69, 0x81B7);
        // ivec_ind from the C core (sv25 presets: 0x60+i).
        dut.set_ivec_ind(c);
    }
    dut.reset_clocks(2);
    dut.release_reset();

    // ---- Step 0: post-reset state ----
    CState cs;
    RState rs;
    cref_get_state(c, &cs);
    rtl_get_state(dut.d, &rs);
    int bad = diff_state(&cs, &rs, 0, 0x8000, stdout);
    if (bad) {
        printf("RESET MISMATCH: %d field(s) differ after reset.\n", bad);
        return 1;
    }
    if (mode == MODE_RESET) {
        printf("reset-check: post-reset state matches "
               "(pc=0x%04X st0=0x%04X st1=0x%04X tim=0x%04X).\n",
               cs.pc, cs.st0, cs.st1, cs.tim);
        return 0;
    }

    // ================= DSP smoke gate =================
    if (mode == MODE_DSP_SMOKE) {
        SmokeVector vec;
        if (parse_smoke_vector(vector_path.c_str(), &vec) != 0) {
            fprintf(stderr, "cosim: cannot parse smoke vector '%s'\n",
                    vector_path.c_str());
            return 2;
        }
        if (vec.nckpt != 8) {
            fprintf(stderr, "cosim: vector has %d checkpoints, expected 8\n",
                    vec.nckpt);
            return 2;
        }
        // Run 8 x 1M cycles. The C core runs first for each
        // segment (it is the reference: the vector came from the
        // Python DSP, so a vector/C disagreement is checked
        // against the C core before the RTL is blamed), then the
        // RTL is clocked to the same cycle target. A 1M-cycle
        // segment is ~6M RTL clocks (the control FSM takes ~6
        // clocks per 1-cycle instruction), so the per-segment
        // watchdog is 20M clocks, not the --max-clocks default.
        long seg_max = max_clocks;
        if (seg_max < 20000000)
            seg_max = 20000000;
        for (int k = 0; k < 8; k++) {
            const SmokeCheckpoint *want = &vec.ckpt[k];
            int st = cref_run(c, 1000000);
            if (st != 0) {
                printf("dsp-smoke: C run %d returned status %d\n", k + 1, st);
                return 1;
            }
            cref_get_state(c, &cs);
            // The C core is the reference, and it overshoots a
            // 1M-cycle budget when the boundary falls inside a
            // multi-cycle instruction (c5x_run executes whole
            // instructions; the first segment lands at 1000003,
            // not 1000000). The RTL is therefore clocked to the
            // C core's ACTUAL cycle count after the segment, not
            // to the vector's nominal 1M boundary. The vector/C
            // total_cycles disagreement is reported below, not
            // treated as an RTL failure.
            uint64_t c_target = cs.cycles;
            long used = dut.run_to_cycles(c_target, seg_max);
            if (used < 0) {
                printf("dsp-smoke: WATCHDOG at checkpoint %d: RTL "
                       "cycles_o did not reach %llu in %ld clocks "
                       "(now %llu).\n",
                       k + 1, (unsigned long long)c_target, seg_max,
                       (unsigned long long)dut.d->cycles_o);
                return 1;
            }
            rtl_get_state(dut.d, &rs);
            // Checkpoint comparison. First check the vector
            // against the C core (the reference); then the RTL
            // against the C core.
            int nbad = 0;
#define CKPT_CMP(field, fmt, cval, rval)                                 \
    do {                                                                  \
        if ((cval) != (rval)) {                                           \
            if (nbad == 0)                                                \
                printf("MISMATCH at checkpoint %d (%llu cycles):\n",       \
                       k + 1, (unsigned long long)want->cycles);           \
            printf("  %-14s C=" fmt " RTL=" fmt "\n", #field, (cval),      \
                   (rval));                                               \
            nbad++;                                                       \
        }                                                                 \
    } while (0)
#define CKPT_VEC(field, fmt, cval, wantval)                               \
    do {                                                                  \
        if ((cval) != (wantval)) {                                         \
            printf("VECTOR/C disagreement at checkpoint %d (%llu "         \
                   "cycles): %s C=" fmt " vector=" fmt "\n",               \
                   k + 1, (unsigned long long)want->cycles, #field,        \
                   (cval), (wantval));                                    \
        }                                                                 \
    } while (0)
            CKPT_VEC(pc, "0x%04X", cs.pc, want->pc);
            CKPT_VEC(acc, "0x%08X", cs.acc, want->acc);
            CKPT_VEC(t0, "0x%04X", cs.treg0, want->t0);
            CKPT_VEC(st0, "0x%04X", cs.st0, want->st0);
            CKPT_VEC(st1, "0x%04X", cs.st1, want->st1);
            CKPT_VEC(ifr, "0x%04X", cs.ifr, want->ifr);
            CKPT_VEC(imr, "0x%04X", cs.imr, want->imr);
            for (int i = 0; i < 8; i++) {
                char name[8];
                snprintf(name, sizeof name, "ar%d", i);
                if (cs.ar[i] != want->ar[i])
                    printf("VECTOR/C disagreement at checkpoint %d: %s "
                           "C=0x%04X vector=0x%04X\n",
                           k + 1, name, cs.ar[i], want->ar[i]);
            }
            CKPT_VEC(dxr_head, "%u", cref_dxr_head(c), want->dxr_head);
            CKPT_VEC(idle_cycles, "%llu",
                     (unsigned long long)cref_idle_cycles(c),
                     (unsigned long long)want->idle_cycles);
            CKPT_VEC(total_cycles, "%llu",
                     (unsigned long long)cs.cycles,
                     (unsigned long long)want->total_cycles);
            CKPT_VEC(timer_expiries, "%llu",
                     (unsigned long long)cref_timer_expiries(c),
                     (unsigned long long)want->timer_expiries);
            // RTL vs C (the reference). Full AR file and stack are
            // observable now (ar_all_o / stack_all_o); mem-owned
            // registers from obs_*_o.
            CKPT_CMP(pc, "0x%04X", cs.pc, rs.pc);
            CKPT_CMP(acc, "0x%08X", cs.acc, rs.acc);
            CKPT_CMP(t0, "0x%04X", cs.treg0, rs.treg0);
            CKPT_CMP(st0, "0x%04X", cs.st0, rs.st0);
            CKPT_CMP(st1, "0x%04X", cs.st1, rs.st1);
            CKPT_CMP(ifr, "0x%04X", cs.ifr, rs.ifr);
            CKPT_CMP(imr, "0x%04X", cs.imr, rs.imr);
            CKPT_CMP(ar_cur, "0x%04X", cs.ar_cur, rs.ar_cur);
            CKPT_CMP(arp, "%u", cs.arp, rs.arp);
            for (int i = 0; i < 8; i++) {
                if (cs.ar[i] != rs.ar[i]) {
                    if (nbad == 0)
                        printf("MISMATCH at checkpoint %d (%llu "
                               "cycles):\n",
                               k + 1,
                               (unsigned long long)want->cycles);
                    printf("  ar%-11d C=0x%04X RTL=0x%04X\n", i, cs.ar[i],
                           rs.ar[i]);
                    nbad++;
                }
            }
            CKPT_CMP(tim, "0x%04X", cs.tim, rs.tim);
            CKPT_CMP(prd, "0x%04X", cs.prd, rs.prd);
            CKPT_CMP(dxr, "0x%04X", cs.dxr, rs.dxr);
            CKPT_CMP(drr, "0x%04X", cs.drr, rs.drr);
            CKPT_CMP(greg, "0x%04X", cs.greg, rs.greg);
            CKPT_CMP(spc, "0x%04X", cs.spc_rd, rs.spc);
            CKPT_CMP(tcr, "0x%04X", cs.tcr, rs.tcr);
            CKPT_CMP(pdwsr, "0x%04X", cs.pdwsr, rs.pdwsr);
            CKPT_CMP(iowsr, "0x%04X", cs.iowsr, rs.iowsr);
            CKPT_CMP(cwsr, "0x%04X", cs.cwsr, rs.cwsr);
            CKPT_CMP(dxr_head, "%u", cref_dxr_head(c), dut.dxr_head);
            CKPT_CMP(idle_cycles, "%llu",
                     (unsigned long long)cref_idle_cycles(c),
                     (unsigned long long)dut.idle_cycles);
            CKPT_CMP(total_cycles, "%llu",
                     (unsigned long long)cs.cycles,
                     (unsigned long long)rs.cycles);
            CKPT_CMP(timer_expiries, "%llu",
                     (unsigned long long)cref_timer_expiries(c),
                     (unsigned long long)dut.d->timer_exp_cnt_o);
#undef CKPT_CMP
#undef CKPT_VEC
            if (nbad) {
                printf("dsp-smoke: checkpoint %d FAILED (%d field(s)).\n",
                       k + 1, nbad);
                return 1;
            }
            printf("dsp-smoke: checkpoint %d/%d OK (%llu cycles, "
                   "pc=0x%04X acc=0x%08X timer_expiries=%llu "
                   "rtl_instr=%llu).\n",
                   k + 1, 8, (unsigned long long)want->cycles, rs.pc,
                   rs.acc,
                   (unsigned long long)dut.d->timer_exp_cnt_o,
                   (unsigned long long)dut.instr_done_count);
        }
        // End-of-run checks: checksums, DXR ring, recent PCs,
        // IO events.
        uint32_t pm_c = checksum_sum(cref_pmem(c), 0x8000, 27710);
        uint32_t pm_r = checksum_sum(dut.shadow_pmem, 0x8000, 27710);
        uint32_t dm_c = checksum_sum(cref_dmem(c), 0, 0x10000);
        uint32_t dm_r = checksum_sum(dut.shadow_dmem, 0, 0x10000);
        int nbad = 0;
        if (pm_c != vec.pm_checksum)
            printf("VECTOR/C disagreement: pm_checksum C=%u vector=%u\n",
                   pm_c, vec.pm_checksum);
        if (dm_c != vec.dm_checksum)
            printf("VECTOR/C disagreement: dm_checksum C=%u vector=%u\n",
                   dm_c, vec.dm_checksum);
        if (pm_r != vec.pm_checksum) {
            printf("MISMATCH: pm_checksum RTL-shadow=%u vector=%u "
                   "(C=%u)\n",
                   pm_r, vec.pm_checksum, pm_c);
            nbad++;
        }
        if (dm_r != vec.dm_checksum) {
            printf("MISMATCH: dm_checksum RTL-shadow=%u vector=%u "
                   "(C=%u)\n",
                   dm_r, vec.dm_checksum, dm_c);
            nbad++;
        }
        for (int i = 0; i < 16; i++) {
            if (dut.dxr_ring[i] != vec.dxr_ring_first16[i]) {
                printf("MISMATCH: dxr_ring[%d] RTL=%u vector=%u (C=%u)\n",
                       i, dut.dxr_ring[i], vec.dxr_ring_first16[i],
                       cref_dxr_ring(c)[i]);
                nbad++;
            }
        }
        // recent_pcs: the vector lists them oldest-first (the
        // Python DSP's recent_pcs(n) returns execution order).
        // The C ring: pcring[(idx-16+k) & 255], k=0..15.
        // The RTL list is in execution order; take the last 16.
        uint16_t *pcr = cref_pcring(c);
        uint32_t pcidx = cref_pcring_idx(c);
        for (int i = 0; i < 16; i++) {
            uint16_t cv = pcr[(pcidx - 16 + i) & 255];
            if (cv != vec.recent_pcs[i])
                printf("VECTOR/C disagreement: recent_pcs[%d] C=0x%04X "
                       "vector=0x%04X\n",
                       i, cv, vec.recent_pcs[i]);
        }
        if (dut.recent_pcs.size() < 16) {
            printf("MISMATCH: RTL recent_pcs has %zu entries, expected "
                   "at least 16\n",
                   dut.recent_pcs.size());
            nbad++;
        } else {
            for (int i = 0; i < 16; i++) {
                uint16_t rv =
                    dut.recent_pcs[dut.recent_pcs.size() - 16 + i];
                if (rv != vec.recent_pcs[i]) {
                    printf("MISMATCH: recent_pcs[%d] RTL=0x%04X "
                           "vector=0x%04X (C=0x%04X)\n",
                           i, rv, vec.recent_pcs[i],
                           pcr[(pcidx - 16 + i) & 255]);
                    nbad++;
                }
            }
        }
        // IO events: compare the observable (pc, port, wr, val)
        // sequence only. Cycle stamps are not compared (see header
        // comment). The vector (Python DSP) logs five DMEM writes
        // to 0x68-0x6C as "IO" events; neither the C core nor the
        // RTL logs DMEM writes as IO (they are covered by the
        // dm_checksum above). The C core also logs MMR writes as
        // pseudo-port events (SPC 0x8022, unknown MMR 0x8032);
        // only the DXR pseudo-port (0x8021) is observable at the
        // RTL top level, so SPC/unknown-MMR events are excluded
        // here (SPC is covered by the checkpoint obs_spc_o
        // comparison). The counts below are the observable
        // subsets; the raw counts are shown for reference.
        std::vector<IoEv> r_obs;
        for (size_t i = 0; i < dut.io_log.size(); i++)
            if (io_event_observable(dut.io_log[i].port))
                r_obs.push_back(dut.io_log[i]);
        std::vector<SmokeVector::Ev> v_obs;
        for (size_t i = 0; i < vec.io_events.size(); i++)
            if (io_event_observable(vec.io_events[i].port))
                v_obs.push_back(vec.io_events[i]);
        size_t c_obs = 0;
        for (uint32_t i = 0; i < cref_iolog_count(c); i++) {
            CIoEv e;
            cref_iolog_entry(c, i, &e);
            if (io_event_observable(e.port))
                c_obs++;
        }
        printf("note: io events observable RTL=%zu C=%zu vector=%zu "
               "(raw RTL=%zu C=%u vector=%zu; excluded: vector DMEM "
               "writes 0x68-0x6C and SPC/unknown-MMR pseudo-ports).\n",
               r_obs.size(), c_obs, v_obs.size(), dut.io_log.size(),
               cref_iolog_count(c), vec.io_events.size());
        if (c_obs != v_obs.size())
            printf("VECTOR/C disagreement: observable io event count "
                   "C=%zu vector=%zu\n",
                   c_obs, v_obs.size());
        if (r_obs.size() != v_obs.size()) {
            printf("MISMATCH: observable io event count RTL=%zu "
                   "vector=%zu (C=%zu)\n",
                   r_obs.size(), v_obs.size(), c_obs);
            nbad++;
        } else {
            for (size_t i = 0; i < v_obs.size(); i++) {
                const SmokeVector::Ev &w = v_obs[i];
                const IoEv &r = r_obs[i];
                if (r.pc != w.pc || r.port != w.port || r.wr != w.wr ||
                    r.val != w.val) {
                    printf("MISMATCH: io event %zu: RTL pc=0x%04X "
                           "port=0x%04X %s val=0x%04X; vector pc=0x%04X "
                           "port=0x%04X %s val=0x%04X (cyc %llu)\n",
                           i, r.pc, r.port, r.wr ? "wr" : "rd", r.val,
                           w.pc, w.port, w.wr ? "wr" : "rd", w.val,
                           (unsigned long long)w.cyc);
                    nbad++;
                }
            }
        }
        if (nbad) {
            printf("dsp-smoke: FAILED (%d end-of-run field(s)).\n", nbad);
            return 1;
        }
        printf("dsp-smoke: PASS -- 8 checkpoints, pm_checksum=%u "
               "dm_checksum=%u dxr_head=%u io_events=%zu clocks=%llu\n",
               vec.pm_checksum, vec.dm_checksum, dut.dxr_head,
               r_obs.size(), (unsigned long long)dut.clocks);
        printf("note: full AR file (AR0-AR7) and mem-owned registers "
               "compared at every checkpoint.\n");
        return 0;
    }

    // ---- Step loop (per-instruction co-sim) ----
    size_t r_io_seen = 0;
    long matched = 0;
    // C pseudo-port MMR-write events (SPC / unknown MMR) skipped
    // from the IO-event comparison: no RTL event exists for them
    // (see io_event_observable). Their effects are covered by the
    // per-instruction state comparison.
    long n_pseudo_skipped = 0;
    for (long step = 1; step <= steps; step++) {
        uint16_t rpc = rs.pc; // RTL PC before this step
        int c_idle_before = cs.idle;
        uint64_t c_cyc_before = cs.cycles;

        // C step.
        uint32_t io_before = cref_iolog_count(c);
        int st = cref_step(c);
        if (st != 0) {
            printf("C step %ld: c5x_run returned status %d "
                   "(1=breakpoint 2=BADOP 3=STOP); stopping.\n",
                   step, st);
            printf("instructions matched before stop: %ld\n", matched);
            return 1;
        }
        cref_get_state(c, &cs);
        // Apply the C side's IO writes to the shared host array, and
        // collect this step's C IO events. Pseudo-port MMR-write
        // events (port 0x8000|a) are filtered to the observable
        // subset: only the DXR write (0x8021) has an RTL event
        // (dxr_wr); SPC (0x8022) and unknown-MMR writes have no
        // top-level RTL strobe, and their effects are covered by
        // the per-instruction state comparison (obs_spc_o) and by
        // a later readback. Pseudo-port events are never applied
        // to the shared host array (the C core does not write
        // iomem for them either).
        std::vector<CIoEv> c_evs;
        for (uint32_t i = io_before; i < cref_iolog_count(c); i++) {
            CIoEv e;
            cref_iolog_entry(c, i, &e);
            if (io_event_pseudo_port(e.port) && e.port != 0x8021) {
                n_pseudo_skipped++;
                continue;
            }
            c_evs.push_back(e);
            if (e.wr && !io_event_pseudo_port(e.port))
                dut.host_iomem[e.port] = e.val;
        }

        // RTL step.
        long used;
        if (c_idle_before) {
            // Idle step: no instruction; clock until cycles_o
            // advances by the C delta.
            uint64_t target = c_cyc_before + (cs.cycles - c_cyc_before);
            used = dut.run_to_cycles(target, max_clocks);
            if (used < 0) {
                printf("WATCHDOG at instruction %ld: RTL cycles_o did "
                       "not reach %llu in %ld clocks (now %llu, "
                       "idle_o=%d).\n",
                       step, (unsigned long long)target, max_clocks,
                       (unsigned long long)dut.d->cycles_o,
                       dut.d->idle_o ? 1 : 0);
                printf("instructions matched before stop: %ld\n", matched);
                return 1;
            }
        } else {
            used = dut.run_to_instr_done(max_clocks);
            if (used < 0) {
                printf("WATCHDOG at instruction %ld (pc 0x%04X op "
                       "0x%04X): no instr_done in %ld clocks.\n",
                       step, rpc, cs.op, max_clocks);
                printf("instructions matched before stop: %ld\n", matched);
                return 1;
            }
        }
        (void)used;
        rtl_get_state(dut.d, &rs);

        // Compare IO event sequences for this step.
        std::vector<IoEv> r_evs(dut.io_log.begin() + (long)r_io_seen,
                                dut.io_log.end());
        r_io_seen = dut.io_log.size();
        if (c_evs.size() != r_evs.size()) {
            printf("MISMATCH at instruction %ld (pc 0x%04X): IO event "
                   "count C=%zu RTL=%zu\n",
                   step, rpc, c_evs.size(), r_evs.size());
            for (size_t i = 0; i < c_evs.size(); i++)
                printf("  C  io: pc=0x%04X port=0x%04X %s val=0x%04X\n",
                       c_evs[i].pc, c_evs[i].port,
                       c_evs[i].wr ? "wr" : "rd", c_evs[i].val);
            for (size_t i = 0; i < r_evs.size(); i++)
                printf("  RTL io: pc=0x%04X port=0x%04X %s val=0x%04X\n",
                       r_evs[i].pc, r_evs[i].port,
                       r_evs[i].wr ? "wr" : "rd", r_evs[i].val);
            printf("instructions matched before stop: %ld\n", matched);
            return 1;
        }
        for (size_t i = 0; i < c_evs.size(); i++) {
            if (c_evs[i].pc != r_evs[i].pc ||
                c_evs[i].port != r_evs[i].port ||
                c_evs[i].wr != r_evs[i].wr ||
                c_evs[i].val != r_evs[i].val) {
                printf("MISMATCH at instruction %ld (pc 0x%04X): IO "
                       "event %zu differs\n  C   pc=0x%04X port=0x%04X "
                       "%s val=0x%04X (cyc %llu)\n"
                       "  RTL pc=0x%04X port=0x%04X %s val=0x%04X\n",
                       step, rpc, i, c_evs[i].pc, c_evs[i].port,
                       c_evs[i].wr ? "wr" : "rd", c_evs[i].val,
                       (unsigned long long)c_evs[i].cyc, r_evs[i].pc,
                       r_evs[i].port, r_evs[i].wr ? "wr" : "rd",
                       r_evs[i].val);
                printf("instructions matched before stop: %ld\n", matched);
                return 1;
            }
        }

        // Compare architectural state.
        bad = diff_state(&cs, &rs, (int)step, rpc, stdout);
        if (bad) {
            printf("instructions matched before stop: %ld\n", matched);
            return 1;
        }

        // Compare memories (C arrays vs RTL shadow).
        uint16_t a, av, bv;
        if (mem_diff(cref_dmem(c), dut.shadow_dmem, &a, &av, &bv) >= 0) {
            printf("MISMATCH at instruction %ld (pc 0x%04X): DMEM "
                   "differs at 0x%04X: C=0x%04X RTL-shadow=0x%04X\n",
                   step, rpc, a, av, bv);
            printf("instructions matched before stop: %ld\n", matched);
            return 1;
        }
        if (mem_diff(cref_pmem(c), dut.shadow_pmem, &a, &av, &bv) >= 0) {
            printf("MISMATCH at instruction %ld (pc 0x%04X): PMEM "
                   "differs at 0x%04X: C=0x%04X RTL-shadow=0x%04X\n",
                   step, rpc, a, av, bv);
            printf("instructions matched before stop: %ld\n", matched);
            return 1;
        }

        matched = step;
        if (verbose && (step % 1024) == 0)
            printf("... %ld instructions matched (pc=0x%04X "
                   "cycles=%llu)\n",
                   step, cs.pc, (unsigned long long)cs.cycles);
    }

    // Final host-array check (C iomem vs shared host array).
    if (memcmp(cref_iomem(c), dut.host_iomem, sizeof dut.host_iomem) != 0) {
        uint16_t a, av, bv;
        mem_diff(cref_iomem(c), dut.host_iomem, &a, &av, &bv);
        printf("MISMATCH after %ld instructions: host IO array differs "
               "at port 0x%04X: C=0x%04X RTL=0x%04X\n",
               matched, a, av, bv);
        return 1;
    }

    printf("MATCHED %ld instructions (%s): final pc=0x%04X "
           "cycles=%llu io_events=%zu clocks=%llu\n",
           matched, mode == MODE_SMOKE ? "smoke" : "firmware", cs.pc,
           (unsigned long long)cs.cycles, dut.io_log.size(),
           (unsigned long long)dut.clocks);
    if (n_pseudo_skipped)
        printf("note: %ld C pseudo-port MMR-write events (SPC / "
               "unknown MMR) excluded from the IO-event comparison; "
               "effects covered by the per-instruction state "
               "comparison.\n",
               n_pseudo_skipped);
    printf("note: full AR file / stack and mem-owned registers "
           "(TIM/PRD/DXR/DRR/GREG/SPC/TCR/PDWSR/IOWSR/CWSR) compared "
           "per instruction.\n");
    return 0;
}
