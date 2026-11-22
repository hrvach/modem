/*
c5x_mem.sv -- TMS320C5x memory subsystem for the Courier DSP core.

PIPELINED core (converged plan hidden_files/pipeline-plan-converged.md
§2-§3, §7-§8; Worker C).  This is a rewrite of the multi-cycle memory
agent (snapshot in hidden_files/pre-pipeline/rtl/c5x_mem.sv).  The old
request/ack data channel and the per-model-cycle timer tick are gone;
the pipeline stages drive the ports directly, one clock per stage.

Owns, for the pipelined C5x core:
  * PMEM and DMEM, 64K x 16 bit each, as simple dual-port M10K
    block RAM: one synchronous write port, one synchronous read
    port, read data registered, single clock, no reset on the
    array, no asynchronous read.  The ramstyle attribute, set to M10K, forces M10K in Quartus; Yosys maps the template via
    memory_bram to $__MISTRAL_M10K.  No Quartus primitive is
    instantiated.
  * The MMR address decode for data space 0x00..0x5F, implementing the
    on-chip peripheral registers (GREG, DRR/DXR/SPC, TIM/PRD/TCR,
    PDWSR/IOWSR/CWSR) and the raw backing store for unlisted MMRs,
    and routing all other MMRs to their owners via the external-MMR
    port.
  * The WALL-CLOCK timer (TIM/PRD with prescaler, TCR/TDDR control):
    tick_timer runs once per wall clock, not per retired model cycle
    (plan §7 B1: the model-cycle timer was proven ~59% fast in real
    time at full load).  Frozen entirely while TSS is set, and while
    the core is parked in IDLE2 (i_idle2_freeze).  The FPGA runs at
    40 MHz against the real 40.32 MHz, so the heartbeat is ~2,382 Hz
    against the nominal 2,401 Hz, a constant 0.8% rate difference
    tolerated by the gates; no compensation is attempted here.
  * The standard serial port (DXR/DRR/SPC with XRDY/RRDY status).
    Serial sub-state advances ONLY on the host serial tick
    (i_ser_tick, machine.c:3129,3221), which is a host event, not a
    model-cycle event: no serial state ever advanced per retired
    model cycle in the old agent either, so nothing serial moves to
    wall-clock timing here.  The timer was the only model-time part.
  * The host I/O-port handshake (req/ack) mirroring the C io_rd/io_wr
    callbacks (codec and 186 mailbox in the modem glue).
  * Wait-state reporting (io_ws) and the peripheral-MMR bus cycle.
  * pm_epoch / replay_dirty event pulses for the block-decode cache.

REFERENCE MODEL (the spec -- this RTL matches it as-is):
  research_notes/courier-firmware/c-port/c/src/dsp/c5x_core.c
  (mmr_rd/mmr_wr, dm_rd/dm_wr, dmov_wr, dm_internal/dm_hostwin,
  pm_ptr, tick_timer, c5x_serial_tick, io_read/io_write, io_ws,
  c5x_reset).  Where the TI manual or the core-3 audit
  (c5x_core_audit/07e) disagrees with that C code, the C code wins;
  see KNOWN-DIFF at the bottom of this header.

PIPELINE INTERFACE CONTRACT (pipe control drives these; Worker A
owns the top and pipe control):
  * Single clock, active-low SYNCHRONOUS reset.  Reset restores the
    c5x_reset() register state; it does NOT touch the memories,
    mmr_raw, xint_first or timer_exp_cnt (the C reset does not
    touch them either -- they are power-on zero, preserved across
    reset).
  * FETCH (F stage): F asserts i_pm_fetch_req with i_pm_fetch_addr
    for one clock per word.  The word is served on the PMEM/DMEM
    read port in that clock unless R steals the port (o_f_stall);
    o_pm_fetch_ack pulses in the following clock with
    o_pm_fetch_data valid.  F holds its request (PC held) while
    o_f_stall is high; this module does NOT latch an unserved
    fetch, so a dropped request must be re-presented.  Pipe control
    captures o_pm_fetch_data at the ending edge of the ack clock.
    The fetch address resolves through pm_ptr (CNF/RAM overlays):
    a fetch at >= 0xFE00 with CNF reads DMEM, a fetch at
    0x2000..0x23FF with RAM reads DMEM, else PMEM.
  * R-OPERAND READ (R stage): R asserts i_r_req with i_r_addr for
    one clock.  i_r_is_prog = 1 selects program-space routing
    (pm_ptr: TBLR/BLDP/LMMR/MAC pma/pfc); 0 selects data-space
    routing (dm_rd).  The read data is valid as o_r_data during the
    FOLLOWING clock (the E clock for a normal instruction, the R2
    clock for a replayed R1 read): BRAM reads land in the registered
    read data at the edge, pure MMR reads are latched at the edge.
    Pipe control's E stage consumes o_r_data combinationally during
    that clock; it must NOT capture o_r_data into the R/E register
    at the R edge (the BRAM data is not there yet).
  * DEFERRED READS (plan §3 C1, audit §7): a read whose target has
    side effects or a live value is NOT performed in R.  o_r_deferred
    is high when the presented R address is DRR 0x20 (read clears
    RRDY/RSRFULL, c5x_core.c:652), an MMR 0x50+ or host-window
    0xFF50..0xFF5F read (host callback, assumed impure), or one of
    the four live-valued reads SPC 0x22, TIM 0x24, TCR 0x26,
    IFR 0x06 (sampled 1-2 clocks early in R).  For a deferred read
    this module performs NO access in R: no BRAM read, no host
    request, no flag clear.  Pipe control presents the same read on
    the E read port instead (i_e_rd_req / i_e_rd_addr); a flushed
    instruction therefore never causes the side effect.  All other
    MMR reads are provably pure and stay in R.
  * H1b (audit §7 caveat (b), finding F-3): an R-phase MMR read at
    distance 1 from an MMR write to the same address samples stale
    data (the write lands at the end of the clock the read samples
    in).  o_r_stall is high when the E-stage write and the R-stage
    read target the same MMR address, EXCEPT when the writer is
    map-changing (PMST 0x07: the H2 hold subsumes it).  o_r_stall is
    also high when the R read and an E access both need the single
    external-MMR read port.  On o_r_stall pipe control holds R (and
    F/D behind it) and re-presents the same R request next clock;
    the write has landed by then, so the re-read is fresh.  The
    stall is exactly one clock.
  * STORE-TO-LOAD BYPASS (plan §3 H4): an E write to a DMEM cell and
    an R read of the same DMEM cell in the same clock forward the
    write data into the read data (the BRAM read itself returns the
    old word).  No stall.  The same bypass is applied to PMEM
    data-space writes (a plain external store in E while R reads the
    same PMEM cell): the C model is sequential, so the younger read
    must see the new value there too.  Program-port (TBLW/SMMR/BLDP)
    writes are excluded from the bypass only in the sense that they
    flush F/D/R, so their R reads never consume the data.
  * PMEM PORT ARBITRATION (plan §3): the PMEM read port is shared by
    F (fetch) and R (program-operand / external-dma reads); R has
    priority, F stalls one clock (o_f_stall, PC held, F/D gets a
    bubble).  The DMEM read port is shared the same way between R
    (internal-dma reads) and F (fetches that resolve to DMEM through
    the CNF/RAM overlays); o_f_stall covers that case too.  The E
    write ports never contend with the read ports (simple dual port).
  * C12 R-STAGE REPLAY: for MAC/MACD/MADS/MADD with an EXTERNAL dma
    operand, R reads PMEM twice (dma, then pma).  Pipe control
    splits R into R1/R2: it presents the dma address first
    (o_r_dma_is_pmem = 1 combinationally during R1 tells it the dma
    routes to PMEM, so the replay is needed), captures o_r_data
    during the R2 clock (it holds the R1 read), then presents the
    pma address with i_r_is_prog = 1 (R2); o_r_data during the E
    clock holds the R2 read.  F stalls during both R1 and R2
    (o_f_stall).  This module holds no replay state.
  * E WRITE (E stage): one write per clock.  i_e_wr with i_e_wr_addr
    / i_e_wr_data routes exactly as dm_wr (MMR / internal DMEM /
    host window / external -> PMEM).  i_e_dmov = 1 applies the
    dmov_wr gate (c5x_core.c:949): the write lands only when the
    source is internal and >= 0x60 AND the destination is internal;
    otherwise it is dropped silently (no strobe, no epoch, no side
    effect).  E is the SINGLE writer: each peripheral register has
    its own enable decoded from the address by a case table, never a
    muxed single write port, so the old TAIL write-port mux hazard
    (ST0+ST1+rptc-clamp collision) cannot recur here.
  * E READ (E stage): i_e_rd_req with i_e_rd_addr reads the deferred
    targets combinationally (DRR/SPC/TIM/TCR from flops, IFR and
    other external MMRs through the ext port, raw MMRs from the
    backing store, 0x50+/hostwin through the host handshake).
    o_e_rdata is valid in the presented clock whenever o_e_stall is
    low.  A DRR read clears RRDY/RSRFULL at the E edge.  E reads
    always commit (E is never flushed), so the clear is safe.
  * IN/OUT + HOST IO (E stage): i_e_io_req with i_e_io_rd,
    i_e_io_addr, i_e_io_wdata is the IN/OUT instruction port (the
    port comes from word2 and always goes to the host).  Host-window
    and MMR-0x50+ reads/writes arrive on the E read/write ports and
    use the same handshake.  o_io_req is a LEVEL: it stays high
    while the access is presented; o_e_stall is high until i_io_ack;
    o_e_io_done pulses with the ack, when o_e_rdata (reads) is
    valid.  Pipe control holds E until o_e_io_done.  o_e_io_ws is
    the combinational io_ws for the presented IO access (retire
    cycle computation); o_e_periph_ws is the mmr_bus +1 for an E
    write to 0x20..0x4F.
  * PROGRAM WRITE (loader + E): i_pm_wr_req / i_pm_wr_addr /
    i_pm_wr_data write program space through pm_ptr (TBLW/BLDP, and
    the firmware loader).  i_pm_wr_is_e = 1 marks an E-stage program
    write (loader quiescent while running); 0 marks the loader.
    o_pm_wr_ack pulses the clock after the write is served.  The
    PMEM write port is muxed between the loader and E; an E data
    write to the same array wins the port in its clock and a pending
    program write is served later (its ack is delayed, never lost).
  * PMEM-WRITE FLUSH (plan §3 H10, audit finding F-1): o_pm_wr_flush
    pulses in the clock an E program write (TBLW/BLDP, i_pm_wr_is_e
    = 1, i_pm_wr_flush_en = 1) is served, or an E data write with
    i_e_wr_flush_en = 1 is presented and accepted.  SMMR writes
    through dm_wr (c5x_core.c:1390), not pm_wr, so its flush arrives
    on the E-data-write path; TBLW/BLDP arrive on the program-write
    path.  Pipe control asserts the flush enable ONLY on the
    retiring iteration and, on the pulse, flushes F/D/R and
    re-fetches from PC.  Plain stores to external data addresses
    need no flush unless the target is a fetch address; pipe control
    asserts i_e_wr_flush_en for those itself (this module cannot see
    the fetch stream).
  * TIMER / INTERRUPT (plan §7): the timer ticks once per wall clock
    with no input strobe.  o_tint_will_raise is combinational:
    !TSS && (psc == 0) && (tim == 0), depth budget <= 4 LUT levels;
    it is high during the clock whose ending edge reloads TIM from
    PRD and raises TINT.  o_tint_pulse is the same signal under its
    old name.  The IFR owner (pipe control / addr agent) must set
    IFR bit 3 at that edge, and must feed the retire-time interrupt
    decision from o_tint_will_raise, not from a registered IFR.
    o_timer_exp_cnt counts expiries and is never reset.
  * TIMER WRITE ORDER: a TCR/TIM/PRD write in E applies before that
    clock's timer tick (C order: write first, then tick --
    advance_timer runs after the instruction).  A TIM write of X
    with PSC = 0 therefore reads back X-1 in the next clock.
  * IDLE2: i_idle2_freeze high parks the timer (prescaler and TIM
    frozen, as TSS).  IDLE (not 2) does not freeze it.
  * Same-cycle same-address read-during-write returns the OLD word
    (M10K RHS semantics), except where the bypass above forwards
    the new word to the R data register.
  * Event pulses (o_tint_pulse, o_rint_pulse, o_xint_pulse,
    o_pm_epoch_inc, o_replay_dirty_pulse, o_dxr_wr) are high for
    exactly one cycle, the cycle in which the causing access/tick is
    presented; the consumer captures them at the ending edge.
  * Observation outputs (o_obs_greg, o_obs_drr, o_obs_dxr,
    o_obs_spc, o_obs_tim, o_obs_prd, o_obs_tcr, o_obs_pdwsr,
    o_obs_iowsr, o_obs_cwsr) expose the current readback value of
    each peripheral MMR (mmr_rd, c5x_core.c:620-675), combinational
    from stored state, for the per-instruction co-sim.  They observe
    only: no logic in this module reads them, and they change no
    cycle timing, latency, arbitration or handshake.
  * i_io_ack is a LEVEL handshake: the host asserts it while o_io_req
    is high and the data is ready, and holds it until o_io_req drops.
  * i_xint_mode is a level from the host glue; a 0->1 edge sets the
    internal xint_first flag (C: c5x_set_xint_mode sets it).

MEMORY CONTENTS: the arrays have no reset and no initial block.
Firmware is loaded through the program-write channel -- the
testbench does exactly that.  For synthesis, initialise PMEM with a
.mif/.hex through the Quartus memory initialisation flow; the array
powers up 0 by default.

KNOWN-DIFF (C model vs TI manual / core-3 audit 07e -- RTL matches C):
  KD-1  dm_internal honours CNF (B0 0x100..0x2FF leaves data space)
        and OVLY (SARAM only when OVLY=1).  Audit #13/M07/M15 say
        core-3 ignored both; the live C code (and this RTL) do not.
  KD-2  SPC writes are masked to 0xC0FE and RRST/XRST have effect
        (audit #19: core-3 stored SPC raw).  Live C + RTL mask.
  KD-3  Reset sets PDWSR/IOWSR=0xFFFF, CWSR=0x0F, TIM/PRD=0xFFFF,
        DRR/DXR/SPC=0 (audit #12/P-06/P-07/P-09/P-10: core-3 left
        them stale).  Live C + RTL set them.
  KD-4  GREG reads back the full stored 16 bits, reset 0x0000
        (manual 08 SS8.4.1: 8-bit, reset 0xFF00).  RTL matches C.
  KD-5  c5x_serial_tick honours RRST/XRST (audit N-5: core-3 never
        read SPC).  Live C + RTL gate on SPC bits 7/6.
  KD-6  dmov_wr gates on source AND dest (audit E-NEW-4: core-3
        tested the source only).  Live C + RTL test both: the gate
        is dm_internal(src) && src >= 0x60 && dm_internal(dest),
        with dest = src_addr + 1 presented as i_e_wr_addr and the
        source as i_e_dmov_src (audit F-5 / KD-15: a DMOV ending
        exactly on a block edge can still write one word past it
        when the gate passes -- the C gate as written, not fixed).
  KD-7  Reserved MMRs (0x00-0x03, 0x23, 0x27, 0x2B-0x4F) and the
        reserved data range 0x500..0x7FF read/write as RAM / external
        unified memory (manual: reserved).  RTL matches C (mmr_raw /
        pmem routing).
  KD-8  CWSR is masked to 5 bits on write (audit P-46: core-3 read
        back full 0xFFFF).  Live C + RTL mask to 0x1F.
  KD-9  TIMER IS WALL-CLOCK IN THIS PIPELINED AGENT (plan §7 B1).
        The multi-cycle agent ran the timer in instruction time (one
        tick per charged machine cycle; audit #3) and the serial tick
        raises XINT every tick in legacy mode (audit #4).  The
        pipelined agent ticks the timer once per wall clock and keeps
        the serial tick as a host event; the C model is matched in
        real time, not in model time (plan §9: tim is dropped from
        the per-retirement comparison, IFR bit 3 is masked).
  KD-10 MPMC is ignored by pm_ptr (audit M16/M34) and there is no
        READY input, clock generator, TDM or HPI (audit N-3/N-4/
        N-16).  Not modelled here, matching C.
  KD-11 The 0xFF50..0xFF5F host window routes to io_read/io_write,
        not pmem (audit M50/#33: not a manual feature).  RTL matches C.
*/

`default_nettype none

module c5x_mem (
    input  logic        clk,
    input  logic        rst_n,

    /* PMST overlay bits (status-register owner, agent 2) */
    input  logic        i_cnf,
    input  logic        i_ovly,
    input  logic        i_ram,

    /* XINT mode level (host glue config; 0->1 edge sets xint_first) */
    input  logic        i_xint_mode,
    input  logic        i_model_tick, /* one timer tick (model-cycle driven by pipe control) */

    /* Serial frame tick: one pulse per codec sample (host event) */
    input  logic        i_ser_tick,
    input  logic [15:0] i_ser_rx,

    /* IDLE2 park: high freezes the timer (plan §6), like TSS */
    input  logic        i_idle2_freeze,

    /* Replay-window inputs (block-decode owner, agent 3) */
    input  logic        i_replay_active,
    input  logic [15:0] i_replay_lo,
    input  logic [15:0] i_replay_hi,

    /* ---- program-fetch channel (F stage) ---- */
    input  logic        i_pm_fetch_req,
    input  logic [15:0] i_pm_fetch_addr,
    output logic [15:0] o_pm_fetch_data, /* valid with o_pm_fetch_ack */
    output logic        o_pm_fetch_ack,
    output logic        o_f_stall, /* R stole the fetch array port */

    /* ---- program-write channel (loader + E: TBLW/BLDP) ---- */
    input  logic        i_pm_wr_req,
    input  logic [15:0] i_pm_wr_addr,
    input  logic [15:0] i_pm_wr_data,
    input  logic        i_pm_wr_is_e, /* 1 = E program write, 0 = loader */
    input  logic        i_pm_wr_flush_en, /* flush F/D/R when served */
    output logic        o_pm_wr_ack,
    output logic        o_pm_wr_flush, /* pulse: flush F/D/R, re-fetch */

    /* ---- R-stage operand read ---- */
    input  logic        i_r2_req,     /* MAC/MADS program operand: a second PMEM read port (a duplicate array), data valid the clock after the request */
    input  logic [15:0] i_r2_addr,
    output logic [15:0] o_r2_data,
    input  logic        i_r_req,
    input  logic [15:0] i_r_addr,
    input  logic        i_r_is_prog, /* 1 = pm_ptr route, 0 = dm_rd route */
    output logic [15:0] o_r_data, /* valid the clock AFTER the R clock */
    output logic        o_r_deferred, /* read moves to E (side effect/live) */
    output logic        o_r_use_pmem, /* R needs the PMEM read port */
    output logic        o_r_use_dmem, /* R needs the DMEM read port */
    output logic        o_r_dma_is_pmem, /* data dma routes to PMEM (C12) */
    output logic        o_r_stall, /* H1b / ext-port conflict: hold R */

    /* ---- E-stage deferred read ---- */
    input  logic        i_e_rd_req,
    input  logic [15:0] i_e_rd_addr,
    output logic [15:0] o_e_rdata, /* valid when o_e_stall is low */

    /* ---- E-stage data write (dm_wr semantics) ---- */
    input  logic        i_e_wr,
    input  logic [15:0] i_e_wr_addr,
    input  logic [15:0] i_e_wr_data,
    input  logic        i_e_dmov, /* 1 = DMOV-family write (dmov_wr gate) */
    input  logic [15:0] i_e_dmov_src, /* DMOV source address (gate input) */
    input  logic        i_e_wr_flush_en, /* flush F/D/R (SMMR / store) */

    /* ---- E-stage IN/OUT instruction port (host, always) ---- */
    input  logic        i_e_io_req,
    input  logic        i_e_io_rd, /* 1 = read, 0 = write */
    input  logic [15:0] i_e_io_addr,
    input  logic [15:0] i_e_io_wdata,
    output logic        o_e_stall, /* IO access presented, no ack yet */
    output logic        o_e_io_done, /* IO access acked this clock */
    output logic [2:0]  o_e_io_ws, /* combinational io_ws for the access */
    output logic        o_e_periph_ws, /* E write to 0x20..0x4F: +1 cycle */

    /* ---- external MMR port (registers owned by other agents) ---- */
    input  logic [15:0] i_ext_mmr_rdata, /* combinational from o_ext_mmr_addr */
    input  logic [15:0] i_ext_mmr_e_rdata, /* combinational from o_ext_mmr_e_addr: the deferred E read */
    output logic [15:0] o_ext_mmr_e_addr,
    output logic [15:0] o_ext_mmr_w_addr,
    output logic        o_ext_mmr_rd,
    output logic        o_ext_mmr_wr,
    output logic [15:0] o_ext_mmr_addr,
    output logic [15:0] o_ext_mmr_wdata,

    /* ---- host I/O port handshake (codec / 186 mailbox) ---- */
    output logic        o_io_req,
    output logic        o_io_rd,
    output logic [15:0] o_io_addr,
    output logic [15:0] o_io_wdata,
    input  logic        i_io_ack, /* level handshake */
    input  logic [15:0] i_io_rdata,

    /* ---- events to the interrupt controller (agent 3) ---- */
    output logic        o_tint_pulse, /* timer expiry: set IFR bit 3 */
    output logic        o_tint_will_raise, /* this edge reloads TIM, raises TINT */
    output logic        o_rint_pulse, /* serial RX ready: set IFR bit 4 */
    output logic        o_xint_pulse, /* serial TX ready / XRST=0: set IFR bit 5 */
    output logic [63:0] o_timer_exp_cnt,

    /* ---- DXR transmit stream to host glue ---- */
    output logic        o_dxr_wr, /* pulse: CPU wrote DXR */
    output logic [15:0] o_dxr_wdata,

    /* ---- block-decode invalidation (agent 3) ---- */
    output logic        o_pm_epoch_inc, /* pulse: pm_epoch must increment */
    output logic        o_replay_dirty_pulse, /* pulse: replay must break out (guard or blk_state_changed) */

    /* ---- observation outputs for co-sim (agent 5) ---- */
    output logic [15:0] o_obs_greg, /* readback value of GREG */
    output logic [15:0] o_obs_drr, /* readback value of DRR */
    output logic [15:0] o_obs_dxr, /* readback value of DXR */
    output logic [15:0] o_obs_spc, /* readback value of SPC */
    output logic [15:0] o_obs_tim, /* readback value of TIM */
    output logic [15:0] o_obs_prd, /* readback value of PRD */
    output logic [15:0] o_obs_tcr, /* readback value of TCR */
    output logic [15:0] o_obs_pdwsr, /* readback value of PDWSR */
    output logic [15:0] o_obs_iowsr, /* readback value of IOWSR */
    output logic [15:0] o_obs_cwsr /* readback value of CWSR */
);

    /*
    ------------------------------------------------------------------
    Address-map constants (c5x_core.c lines 45-67, 82-110)
    ------------------------------------------------------------------
    */
    localparam logic [15:0] DM_B2_END       = 16'h0080;
    localparam logic [15:0] DM_B0_START     = 16'h0100;
    localparam logic [15:0] DM_B0_END       = 16'h0500;
    localparam logic [15:0] DM_B0_CNF_END   = 16'h0300;
    localparam logic [15:0] DM_SARAM_START  = 16'h0800;
    localparam logic [15:0] DM_SARAM_END    = 16'h0C00;
    localparam logic [15:0] DM_MMR_END      = 16'h0060;
    localparam logic [15:0] DM_PERIPH_START = 16'h0020;
    localparam logic [15:0] DM_PERIPH_END   = 16'h0050;
    localparam logic [15:0] DM_HOSTWIN_START = 16'hFF50;
    localparam logic [15:0] DM_HOSTWIN_END   = 16'hFF5F;
    localparam logic [15:0] PM_B0_START     = 16'hFE00;
    localparam logic [15:0] PM_SARAM_START  = 16'h2000;
    localparam logic [15:0] PM_SARAM_END    = 16'h2400;

    /*
    MMR register addresses (mmr_rd/mmr_wr switch, c5x_core.c:620-797).
    Registers keep their manual names; the address is the magic number
    the rule forbids, so it lives here with its source.
    */
    localparam logic [15:0] MMR_GREG_ADDR  = 16'h0005;
    localparam logic [15:0] MMR_DRR_ADDR   = 16'h0020;
    localparam logic [15:0] MMR_DXR_ADDR   = 16'h0021;
    localparam logic [15:0] MMR_SPC_ADDR   = 16'h0022;
    localparam logic [15:0] MMR_TIM_ADDR   = 16'h0024;
    localparam logic [15:0] MMR_PRD_ADDR   = 16'h0025;
    localparam logic [15:0] MMR_TCR_ADDR   = 16'h0026;
    localparam logic [15:0] MMR_PDWSR_ADDR = 16'h0028;
    localparam logic [15:0] MMR_IOWSR_ADDR = 16'h0029;
    localparam logic [15:0] MMR_CWSR_ADDR  = 16'h002A;
    /* First MMR address routed to host I/O (mmr_rd/mmr_wr, c5x_core.c:798-812). */
    localparam logic [15:0] MMR_IO_START   = 16'h0050;
    /* PMST/RPTC/BRCR/PASR/PAER range bumped via blk_state_changed (c5x_core.c:328-334). */
    localparam logic [15:0] MMR_BLK_START  = 16'h0007;
    localparam logic [15:0] MMR_BLK_END    = 16'h000B;
    /*
    Registers owned by other agents (mmr_rd/mmr_wr switch, c5x_core.c:620-797).
    0x0005 is GREG (mine, above); 0x0000..0x0003 are raw backing store.
    The AR file is a contiguous range; the rest are named one by one,
    in the order the C switch lists them.
    */
    localparam logic [15:0] MMR_IMR_ADDR   = 16'h0004;
    localparam logic [15:0] MMR_IFR_ADDR   = 16'h0006;
    localparam logic [15:0] MMR_PMST_ADDR  = 16'h0007;
    localparam logic [15:0] MMR_RPTC_ADDR  = 16'h0008;
    localparam logic [15:0] MMR_BRCR_ADDR  = 16'h0009;
    localparam logic [15:0] MMR_PASR_ADDR  = 16'h000A;
    localparam logic [15:0] MMR_PAER_ADDR  = 16'h000B;
    localparam logic [15:0] MMR_TREG0_ADDR = 16'h000C;
    localparam logic [15:0] MMR_TREG1_ADDR = 16'h000D;
    localparam logic [15:0] MMR_TREG2_ADDR = 16'h000E;
    localparam logic [15:0] MMR_DBMR_ADDR  = 16'h000F;
    localparam logic [15:0] MMR_AR_FIRST   = 16'h0010;
    /* One past the last AR: the C switch covers ARs 0x10..0x17. */
    localparam logic [15:0] MMR_AR_NEXT    = 16'h0018;
    localparam logic [15:0] MMR_INDX_ADDR  = 16'h0018;
    localparam logic [15:0] MMR_ARCR_ADDR  = 16'h0019;
    localparam logic [15:0] MMR_CBSR1_ADDR = 16'h001A;
    localparam logic [15:0] MMR_CBER1_ADDR = 16'h001B;
    localparam logic [15:0] MMR_CBSR2_ADDR = 16'h001C;
    localparam logic [15:0] MMR_CBER2_ADDR = 16'h001D;
    localparam logic [15:0] MMR_CBCR_ADDR  = 16'h001E;
    localparam logic [15:0] MMR_BMAR_ADDR  = 16'h001F;
    /* SPC readback status flags (mmr_rd, c5x_core.c:620-675). */
    localparam logic [15:0] SPC_RSRF_FLAG     = 16'h2000; /* bit 13 */
    localparam logic [15:0] SPC_XSREMPTY_FLAG = 16'h1000; /* bit 12 */
    localparam logic [15:0] SPC_XRDY_FLAG     = 16'h0800; /* bit 11 */
    localparam logic [15:0] SPC_RRDY_FLAG     = 16'h0400; /* bit 10 */
    /* TCR bit positions (mmr_wr, c5x_core.c:738-761). */
    localparam int TCR_TRB_BIT = 5;
    localparam int TCR_TSS_BIT = 4;
    /* CWSR bit positions (io_ws, c5x_core.c:575-585). */
    localparam int CWSR_BIG_PAGES_BIT = 4;
    localparam int CWSR_ALT_LOW_BIT   = 2;
    localparam int CWSR_ALT_HIGH_BIT  = 3;
    /* io_ws page-half split: pages 0..3 use the low alt bit, 4..7 the high one. */
    localparam logic [2:0] IO_WS_HIGH_HALF_START = 3'd4;
    /* Raw backing-store depth: one word per MMR address 0x00..0x5F. */
    localparam int MMR_RAW_COUNT = 96;

    localparam logic [15:0] SPC_WRITABLE_MASK = 16'hC0FE;
    localparam logic [3:0]  SPC_RRST_BIT   = 4'd7; /* bit 7 in the 16-bit word */
    localparam logic [3:0]  SPC_XRST_BIT   = 4'd6; /* bit 6 */
    localparam logic [3:0]  SPC_DLB_BIT    = 4'd1; /* bit 1 */

    /* Data-space route (dm_rd / dm_wr, c5x_core.c:818-949) */
    typedef enum logic [2:0] {
        ROUTE_MMR, /* 0x00..0x5F */
        ROUTE_INTERNAL, /* on-chip DARAM/SARAM -> DMEM */
        ROUTE_HOSTWIN, /* 0xFF50..0xFF5F -> host I/O */
        ROUTE_EXTERNAL, /* everything else -> PMEM (unified) */
        ROUTE_IO /* MMR 0x50..0x5F -> host I/O (mmr_rd/mmr_wr) */
    } route_t;

    /* Pending-read kind for the R-data register (o_r_data mux select) */
    typedef enum logic [1:0] {
        KIND_REG  = 2'b00, /* mmr_rdata_q (registers / ext MMR / raw) */
        KIND_PMEM = 2'b01, /* pmem_rdata_q */
        KIND_DMEM = 2'b10, /* dmem_rdata_q */
        KIND_NONE = 2'b11 /* deferred read: o_r_data is invalid */
    } kind_t;

    /*
    ------------------------------------------------------------------
    Memories.  Simple dual-port M10K RAMs (template verified on this
    VM: synth_intel_alm maps these to $__MISTRAL_M10K, no $mem_v2):
    one synchronous write port, one synchronous read port, read data
    registered, single clock, no reset on the array (c5x_reset does
    not touch memories), no asynchronous read.
    ------------------------------------------------------------------
    */
    (* ramstyle = "M10K" *) reg [15:0] pmem [0:65535];
    (* ramstyle = "M10K" *) reg [15:0] dmem [0:4095];   /* only the on-chip blocks (< 0xC00) live here: 12 address bits, 4K words */
    (* ramstyle = "M10K" *) reg [15:0] pmem2 [0:65535];   /* copy of pmem: the MAC pma read port */
    logic [15:0] pmem2_rdata_q;
    logic [15:0] pmem_rdata_q;
    logic [15:0] dmem_rdata_q;

    /*
    Raw backing store for unlisted MMRs (MMR_RAW_COUNT x 16).  Power-on zero,
    NOT reset (c5x_reset does not touch mmr_raw).  Small table:
    asynchronous read + synchronous write, so it stays in logic
    (ALMs), never BRAM.
    */
    logic [15:0] mmr_raw [0:MMR_RAW_COUNT-1];
    initial begin
        for (int i = 0; i < MMR_RAW_COUNT; i++) mmr_raw[i] = 16'h0000;
    end

    /*
    ------------------------------------------------------------------
    Peripheral registers (c5x_reset values, c5x_core.c:425-451)
    ------------------------------------------------------------------
    */
    logic [15:0] greg_q, drr_q, dxr_q, spc_q;
    logic [15:0] tim_q, prd_q;
    logic [3:0]  tcr_tddr_q;
    logic [15:0] pdwsr_q, iowsr_q;
    logic [4:0]  cwsr_q;
    logic [3:0]  psc_q;
    logic        tss_q;
    logic        xrdy_q, rrdy_q, xsrempty_q, rsrfull_q;
    logic [63:0] timer_exp_cnt_q = 64'd0; /* NOT reset (C: timer_exp untouched) */
    logic        xint_first_q = 1'b0; /* NOT reset (C: set_xint_mode only) */
    logic        xint_mode_q;

    /* R-data holding registers (valid the clock after the R clock) */
    logic [15:0] mmr_rdata_q;
    kind_t       rdata_kind_q;
    /* Store-to-load bypass, latched at the R edge (see o_r_data). */
    logic        bypass_pmem_q, bypass_dmem_q;
    logic [15:0] bypass_pmem_data_q, bypass_dmem_data_q;

    /* Fetch ack / array-select holding registers */
    logic        fetch_ack_q;
    logic        fetch_pend_pmem_q;

    /* Program-write pending latch (loader or E write that lost the port) */
    logic        pmwr_pend_q;
    logic [15:0] pmwr_addr_q;
    logic [15:0] pmwr_data_q;
    logic        pmwr_is_e_q;
    logic        pmwr_flush_en_q;
    logic        pmwr_ack_q;

    /*
    ------------------------------------------------------------------
    Address decode (combinational)
    ------------------------------------------------------------------
    */
    function automatic logic dm_internal_f(
            input logic [15:0] addr, input logic cnf, input logic ovly);
        begin
            dm_internal_f = (addr < DM_B2_END) ||
                ((addr >= DM_B0_START) && (addr < DM_B0_END) &&
                 !(cnf && (addr < DM_B0_CNF_END))) ||
                (ovly && (addr >= DM_SARAM_START) && (addr < DM_SARAM_END));
        end
    endfunction

    function automatic route_t dm_route_f(
            input logic [15:0] addr, input logic cnf, input logic ovly);
        begin
            if (addr < DM_MMR_END)
                dm_route_f = ROUTE_MMR;
            else if (dm_internal_f(addr, cnf, ovly))
                dm_route_f = ROUTE_INTERNAL;
            else if ((addr >= DM_HOSTWIN_START) && (addr <= DM_HOSTWIN_END))
                dm_route_f = ROUTE_HOSTWIN;
            else
                dm_route_f = ROUTE_EXTERNAL;
        end
    endfunction

    /*
    MMR sub-decode: which of my registers / ext / raw / I/O?
    (mmr_rd/mmr_wr switch, c5x_core.c:620-797)
    */
    function automatic logic mmr_is_mine_f(input logic [15:0] addr);
        begin
            mmr_is_mine_f = (addr == MMR_GREG_ADDR) || (addr == MMR_DRR_ADDR) ||
                (addr == MMR_DXR_ADDR) || (addr == MMR_SPC_ADDR) || (addr == MMR_TIM_ADDR) ||
                (addr == MMR_PRD_ADDR) || (addr == MMR_TCR_ADDR) || (addr == MMR_PDWSR_ADDR) ||
                (addr == MMR_IOWSR_ADDR) || (addr == MMR_CWSR_ADDR);
        end
    endfunction

    function automatic logic mmr_is_ext_f(input logic [15:0] addr);
        begin
            /* One term per register, in C-switch order; the AR file is
               the only contiguous range in the list. */
            mmr_is_ext_f = (addr == MMR_IMR_ADDR) || (addr == MMR_IFR_ADDR) ||
                (addr == MMR_PMST_ADDR) || (addr == MMR_RPTC_ADDR) ||
                (addr == MMR_BRCR_ADDR) || (addr == MMR_PASR_ADDR) ||
                (addr == MMR_PAER_ADDR) || (addr == MMR_TREG0_ADDR) ||
                (addr == MMR_TREG1_ADDR) || (addr == MMR_TREG2_ADDR) ||
                (addr == MMR_DBMR_ADDR) ||
                ((addr >= MMR_AR_FIRST) && (addr < MMR_AR_NEXT)) ||
                (addr == MMR_INDX_ADDR) || (addr == MMR_ARCR_ADDR) ||
                (addr == MMR_CBSR1_ADDR) || (addr == MMR_CBER1_ADDR) ||
                (addr == MMR_CBSR2_ADDR) || (addr == MMR_CBER2_ADDR) ||
                (addr == MMR_CBCR_ADDR) || (addr == MMR_BMAR_ADDR);
        end
    endfunction

    function automatic logic mmr_is_io_f(input logic [15:0] addr);
        begin
            mmr_is_io_f = (addr >= MMR_IO_START);
        end
    endfunction

    /*
    Deferred-read test (audit §7): DRR (side effect), the four
    live-valued reads SPC/TIM/TCR/IFR, and any MMR 0x50+ read
    (host callback).  Host-window reads are deferred by the route
    test at the call site, not here.
    */
    function automatic logic mmr_is_deferred_f(input logic [15:0] addr);
        begin
            mmr_is_deferred_f = (addr == MMR_DRR_ADDR) ||
                (addr == MMR_SPC_ADDR) || (addr == MMR_TIM_ADDR) ||
                (addr == MMR_TCR_ADDR) || (addr == MMR_IFR_ADDR) ||
                mmr_is_io_f(addr);
        end
    endfunction

    /*
    Wait states (io_ws, c5x_core.c:575-585).  Only port[15:13] or
    port[3:1] are used (which depends on the CWSR big-pages bit);
    the other port bits are intentionally unused.
    */
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [2:0] io_ws_f(
            input logic [15:0] port,
            input logic [15:0] iowsr, input logic [4:0] cwsr);
        logic       big_pages;
        logic [2:0] page_idx;
        logic [1:0] ws_field;
        logic       alt_mapping;
        begin
            big_pages = cwsr[CWSR_BIG_PAGES_BIT];
            page_idx = big_pages ? port[15:13] : port[3:1];
            case (page_idx)
                3'd0: ws_field = iowsr[1:0];
                3'd1: ws_field = iowsr[3:2];
                3'd2: ws_field = iowsr[5:4];
                3'd3: ws_field = iowsr[7:6];
                3'd4: ws_field = iowsr[9:8];
                3'd5: ws_field = iowsr[11:10];
                3'd6: ws_field = iowsr[13:12];
                default: ws_field = iowsr[15:14];
            endcase
            if (page_idx < IO_WS_HIGH_HALF_START)
                alt_mapping = cwsr[CWSR_ALT_LOW_BIT];
            else
                alt_mapping = cwsr[CWSR_ALT_HIGH_BIT];
            if (alt_mapping) begin
                case (ws_field)
                    2'd3: io_ws_f = 3'd7;
                    2'd2: io_ws_f = 3'd3;
                    default: io_ws_f = {1'b0, ws_field};
                endcase
            end else begin
                io_ws_f = {1'b0, ws_field};
            end
        end
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    /* Program-space pointer (pm_ptr, c5x_core.c:956-963): 1 = DMEM, 0 = PMEM. */
    function automatic logic pm_is_dmem_f(
            input logic [15:0] addr, input logic cnf, input logic ram);
        begin
            pm_is_dmem_f = (cnf && (addr >= PM_B0_START)) ||
                (ram && (addr >= PM_SARAM_START) && (addr < PM_SARAM_END));
        end
    endfunction

    function automatic logic [15:0] pm_dmem_addr_f(input logic [15:0] addr);
        begin
            if (addr >= PM_B0_START)
                pm_dmem_addr_f = addr - PM_B0_START + DM_B0_START;
            else
                pm_dmem_addr_f = addr - PM_SARAM_START + DM_SARAM_START;
        end
    endfunction

    /*
    DMOV gate (dmov_wr, c5x_core.c:949-954): source internal and
    >= 0x60, destination internal.  The destination is presented as
    the write address and the source as i_e_dmov_src.
    */
    function automatic logic dmov_gate_f(
            input logic [15:0] src, input logic [15:0] dest,
            input logic cnf, input logic ovly);
        begin
            dmov_gate_f = dm_internal_f(src, cnf, ovly) &&
                          (src >= DM_MMR_END) &&
                          dm_internal_f(dest, cnf, ovly);
        end
    endfunction

    /*
    ------------------------------------------------------------------
    R-stage decode (combinational, from the presented R address)
    ------------------------------------------------------------------
    */
    route_t r_route;
    logic   r_is_mmr;
    logic   r_is_mine;
    logic   r_is_ext;
    logic   r_is_raw;
    logic   r_is_deferred;
    logic   r_use_pmem;
    logic   r_use_dmem;
    logic   r_dma_is_pmem;

    always_comb begin
        r_route = dm_route_f(i_r_addr, i_cnf, i_ovly);
        r_is_mmr = (r_route == ROUTE_MMR);
        r_is_mine = r_is_mmr && mmr_is_mine_f(i_r_addr);
        r_is_ext = r_is_mmr && mmr_is_ext_f(i_r_addr);
        r_is_raw = r_is_mmr && !mmr_is_mine_f(i_r_addr) &&
                   !mmr_is_ext_f(i_r_addr) && !mmr_is_io_f(i_r_addr);
        /*
        Deferred: DRR / live-valued MMRs / MMR 0x50+ (host), or the
        host window.  A deferred read performs no access in R.
        */
        if (r_route == ROUTE_HOSTWIN)
            r_is_deferred = 1'b1;
        else if (r_is_mmr)
            r_is_deferred = mmr_is_deferred_f(i_r_addr);
        else
            r_is_deferred = 1'b0;
        /*
        Array use: program operands route through pm_ptr, data
        operands through dm_rd (external data reads PMEM directly,
        never through pm_ptr).
        */
        if (i_r_is_prog) begin
            r_use_dmem = pm_is_dmem_f(i_r_addr, i_cnf, i_ram);
            r_use_pmem = !r_use_dmem;
        end else if (r_route == ROUTE_INTERNAL) begin
            r_use_dmem = 1'b1;
            r_use_pmem = 1'b0;
        end else if (r_route == ROUTE_EXTERNAL) begin
            r_use_dmem = 1'b0;
            r_use_pmem = 1'b1;
        end else begin
            r_use_dmem = 1'b0;
            r_use_pmem = 1'b0;
        end
        /* C12 replay condition: the data dma operand routes to PMEM. */
        if (!i_r_is_prog && (r_route == ROUTE_EXTERNAL))
            r_dma_is_pmem = 1'b1;
        else
            r_dma_is_pmem = 1'b0;
    end

    /*
    ------------------------------------------------------------------
    E-stage write decode (combinational, dm_wr semantics)
    ------------------------------------------------------------------
    */
    route_t e_wr_route;
    logic   e_wr_is_mmr;
    logic   e_wr_is_io;
    logic   e_wr_is_ext;
    logic   e_wr_is_raw;
    logic   e_wr_accept; /* DMOV gate result for E writes */

    always_comb begin
        e_wr_route = dm_route_f(i_e_wr_addr, i_cnf, i_ovly);
        e_wr_is_mmr = (e_wr_route == ROUTE_MMR);
        if (e_wr_is_mmr)
            e_wr_is_io = mmr_is_io_f(i_e_wr_addr);
        else if (e_wr_route == ROUTE_HOSTWIN)
            e_wr_is_io = 1'b1;
        else
            e_wr_is_io = 1'b0;
        e_wr_is_ext = e_wr_is_mmr && mmr_is_ext_f(i_e_wr_addr);
        e_wr_is_raw = e_wr_is_mmr && !mmr_is_mine_f(i_e_wr_addr) &&
                      !mmr_is_ext_f(i_e_wr_addr) && !mmr_is_io_f(i_e_wr_addr);
        /*
        DMOV gate (dmov_wr, c5x_core.c:949-954).  Non-DMOV writes
        always pass.  A dropped DMOV write has no side effect at all.
        */
        if (!i_e_dmov)
            e_wr_accept = 1'b1;
        else
            e_wr_accept = dmov_gate_f(i_e_dmov_src, i_e_wr_addr, i_cnf, i_ovly);
    end

    /*
    ------------------------------------------------------------------
    E-stage read decode (combinational)
    ------------------------------------------------------------------
    */
    route_t e_rd_route;
    logic   e_rd_is_mmr;
    logic   e_rd_is_io;
    logic   e_rd_is_mine;
    logic   e_rd_is_ext;
    logic   e_rd_is_raw;

    always_comb begin
        e_rd_route = dm_route_f(i_e_rd_addr, i_cnf, i_ovly);
        e_rd_is_mmr = (e_rd_route == ROUTE_MMR);
        if (e_rd_is_mmr)
            e_rd_is_io = mmr_is_io_f(i_e_rd_addr);
        else if (e_rd_route == ROUTE_HOSTWIN)
            e_rd_is_io = 1'b1;
        else
            e_rd_is_io = 1'b0;
        e_rd_is_mine = e_rd_is_mmr && mmr_is_mine_f(i_e_rd_addr);
        e_rd_is_ext = e_rd_is_mmr && mmr_is_ext_f(i_e_rd_addr);
        e_rd_is_raw = e_rd_is_mmr && !mmr_is_mine_f(i_e_rd_addr) &&
                      !mmr_is_ext_f(i_e_rd_addr) && !mmr_is_io_f(i_e_rd_addr);
    end

    /*
    ------------------------------------------------------------------
    Serial-tick-first status values for the SPC/DRR read muxes
    (c5x_serial_tick precedes the run in the C glue).
    ------------------------------------------------------------------
    */
    logic xrdy_rd, rrdy_rd, xsrempty_rd, rsrfull_rd;
    logic [15:0] drr_rd;

    always_comb begin
        xrdy_rd     = (i_ser_tick && spc_q[SPC_XRST_BIT]) ? 1'b1 : xrdy_q;
        rrdy_rd     = (i_ser_tick && spc_q[SPC_RRST_BIT] && !rrdy_q && !rsrfull_q)
                      ? 1'b1 : rrdy_q;
        rsrfull_rd  = (i_ser_tick && spc_q[SPC_RRST_BIT] && (rrdy_q || rsrfull_q))
                      ? 1'b1 : rsrfull_q;
        xsrempty_rd = (i_ser_tick && spc_q[SPC_XRST_BIT] && xrdy_q) ? 1'b0 : xsrempty_q;
        /* A DRR read coinciding with a tick returns the fresh sample. */
        if (i_ser_tick && spc_q[SPC_RRST_BIT] && !rrdy_q && !rsrfull_q) begin
            if (spc_q[SPC_DLB_BIT])
                drr_rd = dxr_q;
            else
                drr_rd = i_ser_rx;
        end else begin
            drr_rd = drr_q;
        end
    end

    /* MMR read mux for my registers, R address (mmr_rd, c5x_core.c:620-675). */
    logic [15:0] mmr_r_mine_rdata;
    always_comb begin
        case (i_r_addr)
            MMR_GREG_ADDR: mmr_r_mine_rdata = greg_q;
            MMR_DRR_ADDR: mmr_r_mine_rdata = drr_rd;
            MMR_DXR_ADDR: mmr_r_mine_rdata = dxr_q;
            MMR_SPC_ADDR: mmr_r_mine_rdata = (spc_q & SPC_WRITABLE_MASK) |
                                     (rsrfull_rd ? SPC_RSRF_FLAG : 16'h0000) |
                                     (xsrempty_rd ? SPC_XSREMPTY_FLAG : 16'h0000) |
                                     (xrdy_rd ? SPC_XRDY_FLAG : 16'h0000) |
                                     (rrdy_rd ? SPC_RRDY_FLAG : 16'h0000);
            MMR_TIM_ADDR: mmr_r_mine_rdata = tim_q;
            MMR_PRD_ADDR: mmr_r_mine_rdata = prd_q;
            MMR_TCR_ADDR: mmr_r_mine_rdata = {6'b000000, psc_q, 1'b0, tss_q,
                                      tcr_tddr_q};
            MMR_PDWSR_ADDR: mmr_r_mine_rdata = pdwsr_q;
            MMR_IOWSR_ADDR: mmr_r_mine_rdata = iowsr_q;
            MMR_CWSR_ADDR: mmr_r_mine_rdata = {11'b00000000000, cwsr_q};
            default:  mmr_r_mine_rdata = 16'h0000;
        endcase
    end

    /* MMR read mux for my registers, E address (same mmr_rd table). */
    logic [15:0] mmr_e_mine_rdata;
    always_comb begin
        case (i_e_rd_addr)
            MMR_GREG_ADDR: mmr_e_mine_rdata = greg_q;
            MMR_DRR_ADDR: mmr_e_mine_rdata = drr_rd;
            MMR_DXR_ADDR: mmr_e_mine_rdata = dxr_q;
            MMR_SPC_ADDR: mmr_e_mine_rdata = (spc_q & SPC_WRITABLE_MASK) |
                                     (rsrfull_rd ? SPC_RSRF_FLAG : 16'h0000) |
                                     (xsrempty_rd ? SPC_XSREMPTY_FLAG : 16'h0000) |
                                     (xrdy_rd ? SPC_XRDY_FLAG : 16'h0000) |
                                     (rrdy_rd ? SPC_RRDY_FLAG : 16'h0000);
            MMR_TIM_ADDR: mmr_e_mine_rdata = tim_q;
            MMR_PRD_ADDR: mmr_e_mine_rdata = prd_q;
            MMR_TCR_ADDR: mmr_e_mine_rdata = {6'b000000, psc_q, 1'b0, tss_q,
                                      tcr_tddr_q};
            MMR_PDWSR_ADDR: mmr_e_mine_rdata = pdwsr_q;
            MMR_IOWSR_ADDR: mmr_e_mine_rdata = iowsr_q;
            MMR_CWSR_ADDR: mmr_e_mine_rdata = {11'b00000000000, cwsr_q};
            default:  mmr_e_mine_rdata = 16'h0000;
        endcase
    end

    /* Full MMR read value for the R address (mine / ext / raw). */
    logic [15:0] mmr_r_rdata;
    logic [15:0] mmr_raw_rdata_r;
    always_comb begin
        mmr_raw_rdata_r = mmr_raw[i_r_addr[6:0]];
        if (r_is_mine)
            mmr_r_rdata = mmr_r_mine_rdata;
        else if (r_is_ext)
            mmr_r_rdata = i_ext_mmr_rdata;
        else if (r_is_raw)
            mmr_r_rdata = mmr_raw_rdata_r;
        else
            mmr_r_rdata = 16'h0000;
    end

    /* Full MMR read value for the E address (mine / ext / raw). */
    logic [15:0] mmr_e_rdata;
    logic [15:0] mmr_raw_rdata_e;
    always_comb begin
        mmr_raw_rdata_e = mmr_raw[i_e_rd_addr[6:0]];
        if (e_rd_is_mine)
            mmr_e_rdata = mmr_e_mine_rdata;
        else if (e_rd_is_ext)
            mmr_e_rdata = i_ext_mmr_e_rdata;
        else if (e_rd_is_raw)
            mmr_e_rdata = mmr_raw_rdata_e;
        else
            mmr_e_rdata = 16'h0000;
    end

    /* R data output: selected by the kind latched at the R edge.
       The store-to-load bypass is applied here, from the flag and
       write data latched at the same edge: the array read-data
       register itself is never muxed (see the array block above),
       so the read port stays synchronous and maps to M10K. */
    always_comb begin
        case (rdata_kind_q)
            KIND_PMEM: o_r_data = bypass_pmem_q ? bypass_pmem_data_q :
                                   pmem_rdata_q;
            KIND_DMEM: o_r_data = bypass_dmem_q ? bypass_dmem_data_q :
                                   dmem_rdata_q;
            KIND_REG:  o_r_data = mmr_rdata_q;
            default:   o_r_data = 16'h0000;
        endcase
    end

    /* E read data: host reads return the host word when acked.  The
       IN/OUT instruction port reads through the same host word. */
    always_comb begin
        if (i_e_io_req && i_e_io_rd)
            o_e_rdata = i_io_rdata;
        else if (i_e_rd_req && e_rd_is_io)
            o_e_rdata = i_io_rdata;
        else if (i_e_rd_req && e_rd_is_mmr)
            o_e_rdata = mmr_e_rdata;
        else
            o_e_rdata = 16'h0000;
    end

    /*
    ------------------------------------------------------------------
    Deferred / array-use / stall outputs for the R stage
    ------------------------------------------------------------------
    */
    always_comb begin
        o_r_deferred = i_r_req && r_is_deferred;
        o_r_use_pmem = i_r_req && !r_is_deferred && r_use_pmem;
        o_r_use_dmem = i_r_req && !r_is_deferred && r_use_dmem;
        o_r_dma_is_pmem = i_r_req && r_dma_is_pmem;
    end

    /*
    ------------------------------------------------------------------
    Post-write timer state (write first, then tick -- C order:
    the TCR/TIM/PRD write inside an instruction precedes that
    clock's wall-clock tick).  Used by the tick and by
    o_tint_will_raise.
    ------------------------------------------------------------------
    */
    logic        cpu_wr_tim, cpu_wr_prd, cpu_wr_tcr;
    logic [15:0] tim_eff, prd_eff;
    logic [3:0]  psc_eff, tddr_eff;
    logic        tss_eff;

    always_comb begin
        cpu_wr_tim = i_e_wr && e_wr_accept &&
                     (e_wr_route == ROUTE_MMR) && (i_e_wr_addr == MMR_TIM_ADDR);
        cpu_wr_prd = i_e_wr && e_wr_accept &&
                     (e_wr_route == ROUTE_MMR) && (i_e_wr_addr == MMR_PRD_ADDR);
        cpu_wr_tcr = i_e_wr && e_wr_accept &&
                     (e_wr_route == ROUTE_MMR) && (i_e_wr_addr == MMR_TCR_ADDR);
        prd_eff  = cpu_wr_prd ? i_e_wr_data : prd_q;
        tss_eff  = cpu_wr_tcr ? i_e_wr_data[TCR_TSS_BIT] : tss_q;
        tddr_eff = cpu_wr_tcr ? i_e_wr_data[3:0] : tcr_tddr_q;
        /*
        TCR write with TRB reloads TIM from PRD (pre-write PRD: a
        PRD write cannot coincide with a TCR write -- one access).
        */
        if (cpu_wr_tim)
            tim_eff = i_e_wr_data;
        else if (cpu_wr_tcr && i_e_wr_data[TCR_TRB_BIT])
            tim_eff = prd_q;
        else
            tim_eff = tim_q;
        if (cpu_wr_tcr) begin
            if (i_e_wr_data[TCR_TRB_BIT])
                psc_eff = i_e_wr_data[3:0];
            else
                psc_eff = i_e_wr_data[9:6];
        end else begin
            psc_eff = psc_q;
        end
    end

    /*
    ------------------------------------------------------------------
    Wait-state outputs (combinational for the presented E access).
    ------------------------------------------------------------------
    */
    always_comb begin
        if (i_e_io_req)
            o_e_io_ws = io_ws_f(i_e_io_addr, iowsr_q, cwsr_q);
        else if (i_e_rd_req && e_rd_is_io)
            o_e_io_ws = io_ws_f(i_e_rd_addr, iowsr_q, cwsr_q);
        else if (i_e_wr && e_wr_is_io)
            o_e_io_ws = io_ws_f(i_e_wr_addr, iowsr_q, cwsr_q);
        else
            o_e_io_ws = 3'd0;
        /*
        mmr_bus (c5x_core.c:812-816): a data WRITE to 0x20..0x4F
        adds one cycle.  Reads do not (dm_rd never calls mmr_bus).
        */
        o_e_periph_ws = i_e_wr && e_wr_accept &&
            (e_wr_route == ROUTE_MMR) &&
            (i_e_wr_addr >= DM_PERIPH_START) && (i_e_wr_addr < DM_PERIPH_END);
    end

    /*
    ------------------------------------------------------------------
    Event pulses (combinational, high in the cycle the causing
    access/tick is presented; captured at the ending edge).
    ------------------------------------------------------------------
    */
    logic guard_fires;
    logic epoch_inc_ext; /* external E data write: epoch only (C:936-943) */
    logic epoch_inc_mmr; /* MMR 0x07..0x0B write: epoch + dirty (blk_state_changed) */
    logic pmwr_served; /* program-write served this cycle (below) */

    always_comb begin
        /*
        Timer expiry, wall clock: this edge reloads TIM from PRD and
        raises TINT (tick_timer, c5x_core.c:1336-1350).  The signal is
        also the retire-time interrupt-decision input (plan §7 C2):
        !TSS && (psc == 0) && (tim == 0), on post-write state.
        */
        o_tint_will_raise = !tss_eff && !i_idle2_freeze &&
                            (psc_eff == 4'd0) && (tim_eff == 16'd0);
        o_tint_pulse = o_tint_will_raise;
        /* Serial RX ready (c5x_serial_tick:3316-3330). */
        o_rint_pulse = i_ser_tick && spc_q[SPC_RRST_BIT] && !rrdy_q && !rsrfull_q;
        /*
        Serial TX ready: tick with XRST set (legacy: every tick;
        mode 1: only after a DXR write, plus the initial kick), or
        an SPC write with XRST=0 while XRDY was 0 (mmr_wr:754-760).
        */
        o_xint_pulse = (i_ser_tick && spc_q[SPC_XRST_BIT] &&
                        (!i_xint_mode || !xrdy_q || xint_first_q)) ||
                       (i_e_wr && e_wr_accept &&
                        (e_wr_route == ROUTE_MMR) && (i_e_wr_addr == MMR_SPC_ADDR) &&
                        !i_e_wr_data[SPC_XRST_BIT] && !xrdy_q);
        /* DXR write stream to the host glue (dxr_ring in C). */
        o_dxr_wr = i_e_wr && e_wr_accept &&
                   (e_wr_route == ROUTE_MMR) && (i_e_wr_addr == MMR_DXR_ADDR);
        o_dxr_wdata = i_e_wr_data;

        /*
        pm_epoch bumps: an external data write bumps epoch directly
        in dm_wr (c5x_core.c:936-943); a program write or an MMR
        write to PMST/RPTC/BRCR/PASR/PAER (0x07..0x0B) bumps it via
        blk_state_changed (c5x_core.c:328-334, 966, 708-721).
        */
        epoch_inc_ext = i_e_wr && e_wr_accept &&
                        (e_wr_route == ROUTE_EXTERNAL);
        epoch_inc_mmr = i_e_wr && e_wr_accept &&
                        (e_wr_route == ROUTE_MMR) &&
                        (i_e_wr_addr >= MMR_BLK_START) && (i_e_wr_addr <= MMR_BLK_END);
        o_pm_epoch_inc = epoch_inc_ext || epoch_inc_mmr || pmwr_served;

        /*
        blk_store_guard (c5x_core.c:848-860): only while a replay is
        in flight.  External write landing on a block program word,
        or a SARAM write (RAM=1, OVLY=1) mapping into the block.
        */
        guard_fires = i_e_wr && e_wr_accept &&
            (((e_wr_route == ROUTE_EXTERNAL) &&
              (i_e_wr_addr >= i_replay_lo) && (i_e_wr_addr <= i_replay_hi)) ||
             ((e_wr_route == ROUTE_INTERNAL) && i_ram && i_ovly &&
              (i_e_wr_addr >= DM_SARAM_START) && (i_e_wr_addr < DM_SARAM_END) &&
              ((i_e_wr_addr - DM_SARAM_START + PM_SARAM_START) >= i_replay_lo) &&
              ((i_e_wr_addr - DM_SARAM_START + PM_SARAM_START) <= i_replay_hi)));
        /*
        replay_dirty: the blk_state_changed paths (pm_wr, MMR
        0x07..0x0B) set it unconditionally while a replay is in
        flight; a dm_wr sets it ONLY via the guard -- dm_wr does
        NOT call blk_state_changed (see that function's comment).
        */
        o_replay_dirty_pulse = i_replay_active &&
                               (epoch_inc_mmr || pmwr_served || guard_fires);
    end

    /*
    ------------------------------------------------------------------
    External-MMR port (combinational strobes in the presented cycle).
    E has priority: it is the only writer, and an E ext read wins the
    single combinational read port over an R ext read (the R read is
    stalled one clock, see o_r_stall below).
    ------------------------------------------------------------------
    */
    assign o_ext_mmr_e_addr = i_e_rd_addr;
    assign o_ext_mmr_w_addr = i_e_wr_addr;
    logic h1b_stall; /* E MMR write vs R MMR read, same address */
    logic r_ext_blocked; /* R ext read loses the port to an E ext access */

    always_comb begin
        /* e_wr_accept is only the DMOV gate and a DMOV never writes an ext MMR (its destination is >= 0x61), so it is left out of this decode: with it, the (ea + 1) adder and the dm_internal range checks sat in front of the ALU operand mux select (the critical DSP-clock path) */
        o_ext_mmr_wr    = i_e_wr && !i_e_dmov && e_wr_is_ext;
        o_ext_mmr_addr  = i_r_addr;
        o_ext_mmr_wdata = i_e_wr_data;
        if (o_ext_mmr_wr)
            o_ext_mmr_addr = i_e_wr_addr;
        else if (i_e_rd_req && e_rd_is_ext)
            o_ext_mmr_addr = i_e_rd_addr;
        else
            o_ext_mmr_addr = i_r_addr;
        if (i_e_rd_req && e_rd_is_ext)
            o_ext_mmr_rd = 1'b1;
        else if (i_r_req && r_is_ext && !r_is_deferred &&
                 !o_ext_mmr_wr)
            o_ext_mmr_rd = 1'b1;
        else
            o_ext_mmr_rd = 1'b0;
        /*
        H1b (audit §7 caveat (b), finding F-3): an R-phase MMR read
        at distance 1 from an E MMR write to the same address samples
        stale data.  One-clock R stall, except when the writer is
        map-changing (PMST 0x07: the H2 hold subsumes it).  Only
        non-deferred R reads can hit it: deferred reads happen in E.
        */
        if (i_e_wr && e_wr_accept && e_wr_is_mmr &&
            i_r_req && r_is_mmr && !r_is_deferred &&
            (i_e_wr_addr == i_r_addr) &&
            (i_e_wr_addr != MMR_PMST_ADDR))
            h1b_stall = 1'b1;
        else
            h1b_stall = 1'b0;
        /*
        The external-MMR read port serves one address per clock.  An
        R ext read loses to any E ext access (write or read) and is
        stalled one clock with the same hold-and-re-present contract.
        */
        if (i_r_req && r_is_ext && !r_is_deferred &&
            ((i_e_wr && e_wr_accept && e_wr_is_ext) ||
             (i_e_rd_req && e_rd_is_ext)))
            r_ext_blocked = 1'b1;
        else
            r_ext_blocked = 1'b0;
        o_r_stall = h1b_stall || r_ext_blocked;
    end

    /*
    ------------------------------------------------------------------
    Host I/O port (level handshake).  One IO access is presented per
    clock by construction (IN/OUT, or a host-window / MMR-0x50+ read
    or write); the IN/OUT port wins the mux if both were presented.
    ------------------------------------------------------------------
    */
    logic io_active;
    logic io_raw;      /* an IO access is presented by the core (before the one-clock gap) */
    logic io_done_q;   /* the clock after an access completed: the next access is held off for one clock so io_req drops and the host releases its ack */
    logic io_is_rd;

    always_comb begin
        if (i_e_io_req) begin
            io_raw = 1'b1;
            io_is_rd = i_e_io_rd;
        end else if (i_e_rd_req && e_rd_is_io) begin
            io_raw = 1'b1;
            io_is_rd = 1'b1;
        end else if (i_e_wr && e_wr_accept && e_wr_is_io) begin
            io_raw = 1'b1;
            io_is_rd = 1'b0;
        end else begin
            io_raw = 1'b0;
            io_is_rd = 1'b0;
        end
        io_active = io_raw && !io_done_q;
        o_io_req = io_active;
        o_io_rd = io_is_rd;
        if (i_e_io_req) begin
            o_io_addr = i_e_io_addr;
            o_io_wdata = i_e_io_wdata;
        end else if (i_e_rd_req && e_rd_is_io) begin
            o_io_addr = i_e_rd_addr;
            o_io_wdata = 16'h0000;
        end else begin
            o_io_addr = i_e_wr_addr;
            o_io_wdata = i_e_wr_data;
        end
        /* E stalls on an IO access until the host acks it. */
        o_e_stall = io_raw && !(io_active && i_io_ack);
        o_e_io_done = io_active && i_io_ack;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) io_done_q <= 1'b0;
        else        io_done_q <= o_e_io_done;
    end

    /*
    ------------------------------------------------------------------
    Fetch / program-write arbitration.  Per memory, the read port
    serves R first, then F; the write port serves an E data write
    first, then a program write.  A fetch that loses the port is
    NOT latched: o_f_stall tells pipe control to hold PC and
    re-present it.  A program write that loses the port IS latched
    (pmwr_pend_q) and served later.
    ------------------------------------------------------------------
    */
    logic        fetch_is_dmem;
    logic        fetch_serve;
    logic        pmwr_req_eff;
    logic [15:0] pmwr_addr_eff, pmwr_data_eff;
    logic        pmwr_is_e_eff, pmwr_flush_en_eff;
    logic        pmwr_is_dmem;
    logic        pmwr_serve_pmem, pmwr_serve_dmem;
    logic        e_wr_pmem, e_wr_dmem;

    always_comb begin
        fetch_is_dmem = pm_is_dmem_f(i_pm_fetch_addr, i_cnf, i_ram);
        /*
        F stalls when R uses the array F's fetch resolves to.  The
        stall is qualified with the fetch request: pipe control
        ANDs it with its own fetch-valid.
        */
        if (i_pm_fetch_req && i_r_req && !r_is_deferred) begin
            if (r_use_pmem && !fetch_is_dmem)
                o_f_stall = 1'b1;
            else if (r_use_dmem && fetch_is_dmem)
                o_f_stall = 1'b1;
            else
                o_f_stall = 1'b0;
        end else begin
            o_f_stall = 1'b0;
        end
        fetch_serve = i_pm_fetch_req && !o_f_stall;

        pmwr_req_eff = i_pm_wr_req || pmwr_pend_q;
        if (pmwr_pend_q) begin
            pmwr_addr_eff = pmwr_addr_q;
            pmwr_data_eff = pmwr_data_q;
            pmwr_is_e_eff = pmwr_is_e_q;
            pmwr_flush_en_eff = pmwr_flush_en_q;
        end else begin
            pmwr_addr_eff = i_pm_wr_addr;
            pmwr_data_eff = i_pm_wr_data;
            pmwr_is_e_eff = i_pm_wr_is_e;
            pmwr_flush_en_eff = i_pm_wr_flush_en;
        end
        pmwr_is_dmem = pm_is_dmem_f(pmwr_addr_eff, i_cnf, i_ram);

        e_wr_pmem = i_e_wr && e_wr_accept && (e_wr_route == ROUTE_EXTERNAL);
        e_wr_dmem = i_e_wr && e_wr_accept && (e_wr_route == ROUTE_INTERNAL);
        pmwr_serve_pmem = pmwr_req_eff && !pmwr_is_dmem && !e_wr_pmem;
        pmwr_serve_dmem = pmwr_req_eff && pmwr_is_dmem && !e_wr_dmem;
        pmwr_served = pmwr_serve_pmem || pmwr_serve_dmem;

        /*
        PMEM-write flush (plan §3 H10, audit F-1): an E program
        write (TBLW/BLDP) served with flush enabled, or an E data
        write (SMMR, c5x_core.c:1390, writes through dm_wr; or a
        plain store to a fetch address) presented with flush
        enabled.  Pipe control asserts the enable only on the
        retiring iteration and flushes F/D/R on the pulse.
        */
        if (pmwr_served && pmwr_is_e_eff && pmwr_flush_en_eff)
            o_pm_wr_flush = 1'b1;
        else if (i_e_wr && e_wr_accept && i_e_wr_flush_en)
            o_pm_wr_flush = 1'b1;
        else
            o_pm_wr_flush = 1'b0;
    end

    /*
    ------------------------------------------------------------------
    BRAM port arbitration + store-to-load bypass.
    Read port: R first, then fetch.  Write port: E data write first,
    then program write.  The bypass forwards an E write's data into
    the R read-data register when E writes and R reads the same cell
    in the same clock (the BRAM read itself returns the old word).
    ------------------------------------------------------------------
    */
    logic        pmem_rd_en, pmem_wr_en;
    logic [15:0] pmem_raddr, pmem_waddr, pmem_wdata;
    logic        dmem_rd_en, dmem_wr_en;
    logic [15:0] dmem_raddr, dmem_waddr, dmem_wdata;
    logic        bypass_pmem, bypass_dmem;

    always_comb begin
        pmem_rd_en = (i_r_req && !r_is_deferred && r_use_pmem) ||
                     (fetch_serve && !fetch_is_dmem);
        if (i_r_req && !r_is_deferred && r_use_pmem)
            pmem_raddr = i_r_addr;
        else
            pmem_raddr = i_pm_fetch_addr;
        pmem_wr_en = e_wr_pmem || pmwr_serve_pmem;
        if (e_wr_pmem) begin
            pmem_waddr = i_e_wr_addr;
            pmem_wdata = i_e_wr_data;
        end else begin
            pmem_waddr = pmwr_addr_eff;
            pmem_wdata = pmwr_data_eff;
        end

        dmem_rd_en = (i_r_req && !r_is_deferred && r_use_dmem) ||
                     (fetch_serve && fetch_is_dmem);
        /*
        A program operand (pma) resolves through pm_ptr, so its
        DMEM cell is the translated address, exactly as for a fetch
        below; a data operand uses its data address directly.
        */
        if (i_r_req && !r_is_deferred && r_use_dmem) begin
            if (i_r_is_prog)
                dmem_raddr = pm_dmem_addr_f(i_r_addr);
            else
                dmem_raddr = i_r_addr;
        end else
            dmem_raddr = pm_dmem_addr_f(i_pm_fetch_addr);
        dmem_wr_en = e_wr_dmem || pmwr_serve_dmem;
        if (e_wr_dmem) begin
            dmem_waddr = i_e_wr_addr;
            dmem_wdata = i_e_wr_data;
        end else begin
            dmem_waddr = pm_dmem_addr_f(pmwr_addr_eff);
            dmem_wdata = pmwr_data_eff;
        end

        /*
        Bypass: E writes a cell while R reads the same cell, same
        clock.  The flag and write data are latched at the R edge
        by the R-data latch below and applied at the o_r_data
        output; the array read itself stays plain so the read port
        stays synchronous (see the array block above).  The compare
        uses the muxed DMEM read address, so a program operand
        compares against its translated cell.  Loader writes
        (pmwr_is_e = 0) never bypass: the loader is quiescent
        while the pipeline runs.
        */
        if (pmem_wr_en && i_r_req && !r_is_deferred && r_use_pmem &&
            (pmem_waddr == i_r_addr) &&
            (e_wr_pmem || (pmwr_serve_pmem && pmwr_is_e_eff)))
            bypass_pmem = 1'b1;
        else
            bypass_pmem = 1'b0;
        if (dmem_wr_en && i_r_req && !r_is_deferred && r_use_dmem &&
            (dmem_waddr == dmem_raddr) &&
            (e_wr_dmem || (pmwr_serve_dmem && pmwr_is_e_eff)))
            bypass_dmem = 1'b1;
        else
            bypass_dmem = 1'b0;
    end

    assign o_timer_exp_cnt = timer_exp_cnt_q;
    assign o_pm_fetch_ack  = fetch_ack_q;
    assign o_pm_wr_ack     = pmwr_ack_q;
    /* The MAC/MADS program operand (pma) resolves through pm_ptr like any program read: with CNF=1 the pma range 0xFE00..0xFFFF is B0
       (data 0x100..0x2FF) and with RAM=1 0x2000..0x23FF is the SARAM block (data 0x800..0xBFF).  The r2 port reads the PMEM copy only,
       so those two blocks are mirrored in small shadow arrays written alongside DMEM and selected here (the C core's pm_ptr). */
    assign o_r2_data       = r2_sel_q ? (r2_b0_q ? r2_b0_rd_q : r2_sa_rd_q) : pmem2_rdata_q;

    always_comb begin
        if (fetch_pend_pmem_q)
            o_pm_fetch_data = pmem_rdata_q;
        else
            o_pm_fetch_data = dmem_rdata_q;
    end

    /*
    PMEM / DMEM: simple dual-port M10K template.  Same-cycle
    same-address read returns the OLD word (RHS evaluated pre-edge).
    The read-data register is fed DIRECTLY by the array read, with
    no mux in front of it: memory_dff merges it into the read port,
    so the port is synchronous (RD_CLK = clk) and the M10K rule
    maps the array.  A bypass mux in front of the register would
    leave the read port asynchronous (RD_CLK = x) and the array
    would fall back to logic.  The store-to-load bypass is applied
    instead at the o_r_data output below, from the bypass flag and
    data latched at the R edge in the R-data latch.
    */
    always_ff @(posedge clk) begin
        if (pmem_wr_en) begin
            pmem[pmem_waddr] <= pmem_wdata;
            pmem2[pmem_waddr] <= pmem_wdata;
        end
        if (pmem_rd_en)
            pmem_rdata_q <= pmem[pmem_raddr];
        if (i_r2_req)
            pmem2_rdata_q <= pmem2[i_r2_addr];
    end

    (* ramstyle = "M10K" *) reg [15:0] shadow_b0 [0:511];
    (* ramstyle = "M10K" *) reg [15:0] shadow_sa [0:1023];
    logic r2_sel_q = 1'b0, r2_b0_q = 1'b0;
    logic [15:0] r2_b0_rd_q = 16'h0000, r2_sa_rd_q = 16'h0000;
    /* one write port and one enabled synchronous read per array, nothing else in the block: that is what maps to M10K (a read mixed with a select
       between the two arrays in one assignment was "uninferred due to asynchronous read logic" and became 24.6k flip-flops) */
    always_ff @(posedge clk) begin
        if (dmem_wr_en && (dmem_waddr >= DM_B0_START) && (dmem_waddr < DM_B0_CNF_END))
            shadow_b0[9'(dmem_waddr - DM_B0_START)] <= dmem_wdata;   /* data 0x100..0x2FF -> 0..511 */
        if (i_r2_req)
            r2_b0_rd_q <= shadow_b0[i_r2_addr[8:0]];
    end
    always_ff @(posedge clk) begin
        if (dmem_wr_en && (dmem_waddr >= DM_SARAM_START) && (dmem_waddr < DM_SARAM_END))
            shadow_sa[dmem_waddr[9:0]] <= dmem_wdata;
        if (i_r2_req)
            r2_sa_rd_q <= shadow_sa[i_r2_addr[9:0]];
    end
    always_ff @(posedge clk)
        if (i_r2_req) begin
            r2_sel_q <= pm_is_dmem_f(i_r2_addr, i_cnf, i_ram);
            r2_b0_q  <= (i_r2_addr >= PM_B0_START);
        end

    always_ff @(posedge clk) begin
        if (dmem_wr_en)
            dmem[dmem_waddr[11:0]] <= dmem_wdata;
        if (dmem_rd_en)
            dmem_rdata_q <= dmem[dmem_raddr[11:0]];
    end

    /*
    mmr_raw: asynchronous read (combinational), synchronous write.
    The read data is captured into mmr_rdata_q at the R edge by the
    R-data latch below, so o_r_data presents it in the E clock.
    */
    logic        raw_wr_en;
    always_comb begin
        raw_wr_en = i_e_wr && e_wr_accept && e_wr_is_raw;
    end
    always_ff @(posedge clk) begin
        if (raw_wr_en)
            mmr_raw[i_e_wr_addr[6:0]] <= i_e_wr_data;
    end

    /*
    ------------------------------------------------------------------
    Peripheral state: serial tick, E access, wall-clock timer tick.
    Order inside this block is the C call order: serial tick first
    (the glue calls c5x_serial_tick before c5x_run), then the CPU
    access (wins over the tick on shared registers), then the timer
    tick applied to the POST-write state (write first, then tick).
    The timer ticks EVERY wall clock (no tick strobe): frozen only
    while TSS is set (post-write) or IDLE2 is parked.
    ------------------------------------------------------------------
    */
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            greg_q <= 16'h0000;
            drr_q  <= 16'h0000;
            dxr_q  <= 16'h0000;
            spc_q  <= 16'h0000;
            tim_q  <= 16'hFFFF;
            prd_q  <= 16'hFFFF;
            tcr_tddr_q <= 4'd0;
            pdwsr_q <= 16'hFFFF;
            iowsr_q <= 16'hFFFF;
            cwsr_q <= 5'h0F;
            psc_q  <= 4'd0;
            tss_q  <= 1'b0;
            xrdy_q <= 1'b1;
            rrdy_q <= 1'b0;
            xsrempty_q <= 1'b0;
            rsrfull_q <= 1'b0;
            xint_mode_q <= 1'b0;
            /*
            NOT reset (C: c5x_reset does not touch them):
            timer_exp_cnt_q, xint_first_q.
            */
        end else begin
            /* ---- serial tick (c5x_serial_tick, c5x_core.c:3316-3345) ---- */
            if (i_ser_tick) begin
                if (spc_q[SPC_RRST_BIT]) begin /* RRST: receiver enabled */
                    if (rrdy_q || rsrfull_q) begin
                        rsrfull_q <= 1'b1; /* overrun; word lost */
                    end else begin
                        drr_q <= spc_q[SPC_DLB_BIT] ? dxr_q : i_ser_rx; /* DLB */
                        rrdy_q <= 1'b1;
                    end
                end
                if (spc_q[SPC_XRST_BIT]) begin /* XRST: transmitter enabled */
                    if (xrdy_q)
                        xsrempty_q <= 1'b0; /* no DXR pending: underflow */
                    xrdy_q <= 1'b1;
                    if (!i_xint_mode || !xrdy_q || xint_first_q)
                        xint_first_q <= 1'b0;
                end
            end
            /* 0->1 edge on i_xint_mode sets xint_first (c5x_set_xint_mode). */
            if (i_xint_mode && !xint_mode_q)
                xint_first_q <= 1'b1;
            xint_mode_q <= i_xint_mode;

            /* ---- E-stage deferred read: DRR clears RRDY / RSRFULL ---- */
            if (i_e_rd_req && !e_rd_is_io &&
                (e_rd_route == ROUTE_MMR) &&
                (i_e_rd_addr == MMR_DRR_ADDR)) begin
                rrdy_q <= 1'b0;
                rsrfull_q <= 1'b0;
            end

            /* ---- E-stage write: one writer, per-register enables ---- */
            if (i_e_wr && e_wr_accept && (e_wr_route == ROUTE_MMR)) begin
                case (i_e_wr_addr)
                    MMR_GREG_ADDR: greg_q <= i_e_wr_data;
                    MMR_DRR_ADDR: drr_q <= i_e_wr_data;
                    MMR_DXR_ADDR: begin
                        dxr_q <= i_e_wr_data;
                        xrdy_q <= 1'b0;
                        xsrempty_q <= 1'b1;
                    end
                    MMR_SPC_ADDR: begin
                        spc_q <= i_e_wr_data & SPC_WRITABLE_MASK;
                        if (!i_e_wr_data[SPC_RRST_BIT]) begin
                            rrdy_q <= 1'b0;
                            rsrfull_q <= 1'b0;
                        end
                        if (!i_e_wr_data[SPC_XRST_BIT]) begin
                            xsrempty_q <= 1'b0;
                            xrdy_q <= 1'b1;
                        end
                    end
                    MMR_TIM_ADDR: tim_q <= i_e_wr_data;
                    MMR_PRD_ADDR: prd_q <= i_e_wr_data;
                    MMR_TCR_ADDR: begin
                        tcr_tddr_q <= i_e_wr_data[3:0];
                        tss_q <= i_e_wr_data[TCR_TSS_BIT];
                        if (i_e_wr_data[TCR_TRB_BIT]) begin
                            tim_q <= prd_q;
                            psc_q <= i_e_wr_data[3:0];
                        end else begin
                            psc_q <= i_e_wr_data[9:6];
                        end
                    end
                    MMR_PDWSR_ADDR: pdwsr_q <= i_e_wr_data;
                    MMR_IOWSR_ADDR: iowsr_q <= i_e_wr_data;
                    MMR_CWSR_ADDR: cwsr_q <= i_e_wr_data[4:0];
                    default: begin end
                endcase
            end

            /*
            ---- wall-clock timer tick (tick_timer, c5x_core.c:1336-1350) ----
            Applied to the post-write state (tim_eff/psc_eff/...).
            Frozen entirely while TSS is set or IDLE2 is parked.
            */
            if (i_model_tick && !tss_eff && !i_idle2_freeze) begin
                if (psc_eff == 4'd0) begin
                    psc_q <= tddr_eff;
                    if (tim_eff == 16'd0) begin
                        tim_q <= prd_eff;
                        timer_exp_cnt_q <= timer_exp_cnt_q + 64'd1;
                    end else begin
                        tim_q <= tim_eff - 16'd1;
                    end
                end else begin
                    psc_q <= psc_eff - 4'd1;
                end
            end
        end
    end

    /*
    ------------------------------------------------------------------
    R-data latch: the kind of the R read just served, and the MMR
    read value for it.  A stalled R read (o_r_stall) latches nothing:
    pipe control re-presents it next clock and the fresh value is
    latched then.  BRAM reads need no latch here: pmem_rdata_q /
    dmem_rdata_q already hold the data the clock after the R clock.
    The bypass flag and write data are latched here too, for the
    o_r_data mux above: bypass_pmem/bypass_dmem are the presented
    same-clock E-write/R-read coincidence, so they are valid at
    this edge exactly when the R read is served.
    ------------------------------------------------------------------
    */
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rdata_kind_q <= KIND_NONE;
            mmr_rdata_q  <= 16'h0000;
            bypass_pmem_q <= 1'b0;
            bypass_dmem_q <= 1'b0;
            bypass_pmem_data_q <= 16'h0000;
            bypass_dmem_data_q <= 16'h0000;
        end else if (i_r_req && !o_r_stall) begin
            bypass_pmem_q <= bypass_pmem;
            bypass_dmem_q <= bypass_dmem;
            if (bypass_pmem)
                bypass_pmem_data_q <= pmem_wdata;
            if (bypass_dmem)
                bypass_dmem_data_q <= dmem_wdata;
            if (r_is_deferred) begin
                rdata_kind_q <= KIND_NONE;
            end else if (r_use_pmem) begin
                rdata_kind_q <= KIND_PMEM;
            end else if (r_use_dmem) begin
                rdata_kind_q <= KIND_DMEM;
            end else if (r_is_mmr) begin
                rdata_kind_q <= KIND_REG;
                mmr_rdata_q <= mmr_r_rdata;
            end else begin
                rdata_kind_q <= KIND_NONE;
            end
        end
    end

    /*
    ------------------------------------------------------------------
    Fetch channel: ack pulses the clock after the serve clock, with
    the array select latched at the serve edge.  No pending latch:
    an unserved fetch (o_f_stall) must be re-presented by F.
    ------------------------------------------------------------------
    */
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            fetch_ack_q       <= 1'b0;
            fetch_pend_pmem_q <= 1'b1;
        end else begin
            fetch_ack_q <= fetch_serve;
            if (fetch_serve)
                fetch_pend_pmem_q <= !fetch_is_dmem;
        end
    end

    /*
    ------------------------------------------------------------------
    Program-write channel: serve (BRAM write) or latch pending.
    The pending latch carries the E/loader tag and the flush enable
    with the request, so a delayed serve still flushes correctly.
    ------------------------------------------------------------------
    */
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pmwr_pend_q     <= 1'b0;
            pmwr_addr_q     <= 16'h0000;
            pmwr_data_q     <= 16'h0000;
            pmwr_is_e_q     <= 1'b0;
            pmwr_flush_en_q <= 1'b0;
            pmwr_ack_q      <= 1'b0;
        end else begin
            pmwr_ack_q <= pmwr_served;
            if (pmwr_served) begin
                pmwr_pend_q <= i_pm_wr_req;
                if (i_pm_wr_req) begin
                    pmwr_addr_q <= i_pm_wr_addr;
                    pmwr_data_q <= i_pm_wr_data;
                    pmwr_is_e_q <= i_pm_wr_is_e;
                    pmwr_flush_en_q <= i_pm_wr_flush_en;
                end
            end else if (i_pm_wr_req) begin
                pmwr_pend_q <= 1'b1;
                pmwr_addr_q <= i_pm_wr_addr;
                pmwr_data_q <= i_pm_wr_data;
                pmwr_is_e_q <= i_pm_wr_is_e;
                pmwr_flush_en_q <= i_pm_wr_flush_en;
            end
        end
    end

    /*
    Observation outputs for the co-sim (agent 5): the current
    readback value of each peripheral MMR, exactly as mmr_rd
    (c5x_core.c:620-675) composes it, but from stored state only.
    SPC is the stored bits with the status flags overlaid on bits
    13..10 (the stored SPC bits alone are o_obs_spc & 0xC0FE);
    TCR and CWSR are composed from their split stored fields.
    The flag overlay is written bit by bit, as the C code shifts
    and ORs the flags, not as a ternary mux tree: the mux form
    made Yosys ABC keep 78 extra flops (FF 1347 vs 1269) for the
    same function.  Unlike the data-channel read mux above, these
    do NOT include the same-cycle serial-tick-first adjustment:
    at an instruction boundary, with no tick in flight, the two
    agree.  Purely combinational; they drive no logic and add no
    state.
    */
    always_comb begin
        o_obs_greg  = greg_q;
        o_obs_drr   = drr_q;
        o_obs_dxr   = dxr_q;
        o_obs_spc   = spc_q & SPC_WRITABLE_MASK;
        o_obs_spc[13] = rsrfull_q;
        o_obs_spc[12] = xsrempty_q;
        o_obs_spc[11] = xrdy_q;
        o_obs_spc[10] = rrdy_q;
        o_obs_tim   = tim_q;
        o_obs_prd   = prd_q;
        o_obs_tcr   = {6'b000000, psc_q, 1'b0, tss_q, tcr_tddr_q};
        o_obs_pdwsr = pdwsr_q;
        o_obs_iowsr = iowsr_q;
        o_obs_cwsr  = {11'b00000000000, cwsr_q};
    end

endmodule

`default_nettype wire
