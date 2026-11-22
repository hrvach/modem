/*
c5x_mem.sv -- TMS320C5x memory subsystem for the Courier DSP core.

Owns, for the multi-cycle C5x core (see GOAL.md):
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
  * The timer (TIM/PRD with prescaler, TCR/TDDR control) and the
    standard serial port (DXR/DRR/SPC with XRDY/RRDY status).
  * The host I/O-port handshake (req/ack) mirroring the C io_rd/io_wr
    callbacks (codec and 186 mailbox in the modem glue).
  * Wait-state reporting (io_ws) and the peripheral-MMR bus cycle.
  * pm_epoch / replay_dirty event pulses for the block-decode cache.

REFERENCE MODEL (the spec -- this RTL matches it as-is):
  research_notes/courier-firmware/c-port/c/src/dsp/c5x_core.c
  (mmr_rd/mmr_wr, dm_rd/dm_wr, dm_internal/dm_hostwin, pm_ptr,
  tick_timer/advance_timer, c5x_serial_tick, io_read/io_write,
  io_ws, c5x_reset).  Where the TI manual or the core-3 audit
  (c5x_core_audit/07e) disagrees with that C code, the C code wins;
  see KNOWN-DIFF at the bottom of this header.

INTERFACE CONTRACT (the core FSM drives these):
  * Single clock, active-low SYNCHRONOUS reset.  Reset restores the
    c5x_reset() register state; it does NOT touch the memories,
    mmr_raw, xint_first or timer_exp_cnt (the C reset does not
    touch them either -- they are power-on zero, preserved across
    reset).
  * Data channel: pulse i_dm_req for one cycle; o_dm_ack pulses one
    cycle later for on-chip accesses (fixed 2-cycle latency: req
    cycle + ack cycle), later for host I/O (after i_io_ack).  The FSM
    must not issue a new i_dm_req while o_dm_ack is high or an I/O
    access is outstanding.  o_dm_rdata is valid in the o_dm_ack
    cycle.  o_dm_io_ws / o_dm_periph_ws are combinational for the
    presented address: the FSM charges the C-model cycles itself
    (io_read adds io_ws; io_write adds ws-1 when ws > 1; a data
    write to 0x20..0x4F adds 1 -- mmr_bus, C line 814, dm_wr only).
  * Fetch channel: pulse i_pm_fetch_req; o_pm_fetch_ack + data one
    cycle later (BRAM sync read).  One outstanding fetch at a time.
  * Program-write channel (BLPW/TBLW): pulse i_pm_wr_req; o_pm_wr_ack
    one cycle after the write is served.
  * The three channels share the two BRAM ports; arbitration priority
    is data > program-write > fetch.  A fetch or program-write that
    loses arbitration is latched and served later (its ack is
    delayed); a data request is always served in its req cycle.  The
    FSM must therefore never issue a data request and a program-write
    request in the same cycle (it never does -- the core is sequential).
  * i_tick: pulse once per machine cycle the FSM charges, issued for
    already-completed cycles (C advances the timer AFTER the
    instruction: advance_timer at the end of the run-loop iteration,
    4 ticks during a cyc_model interrupt entry, 1 per idle cycle).
    A tick in the same cycle as a TIM/PRD/TCR write applies to the
    POST-write state (write first, then tick -- C order).
  * i_ser_tick: pulse once per codec sample with the ADC word on
    i_ser_rx.  The serial tick is ordered BEFORE any CPU access in
    the same cycle (the C glue calls c5x_serial_tick before c5x_run):
    a DRR read coinciding with a tick returns the fresh sample, an
    SPC read returns post-tick status, and the tick itself sees
    pre-write register state.
  * Same-cycle same-address read-during-write returns the OLD word
    (nonblocking RHS semantics).  The arbiter never serves a read
    and a write to the same memory in the same cycle, so the case
    cannot arise through this interface at all; the C model is
    sequential (fetch-then-execute) and never relies on a
    same-cycle read seeing new data.  No KNOWN-DIFF here.
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
Firmware is loaded through the write port (the program-write
channel, BLPW/TBLW, or a data write) -- the testbench does exactly
that.  For synthesis, initialise PMEM with a .mif/.hex through the
Quartus memory initialisation flow; the array powers up 0 by
default.

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
        tested the source only).  Live C + RTL test both.
  KD-7  Reserved MMRs (0x00-0x03, 0x23, 0x27, 0x2B-0x4F) and the
        reserved data range 0x500..0x7FF read/write as RAM / external
        unified memory (manual: reserved).  RTL matches C (mmr_raw /
        pmem routing).
  KD-8  CWSR is masked to 5 bits on write (audit P-46: core-3 read
        back full 0xFFFF).  Live C + RTL mask to 0x1F.
  KD-9  The timer runs in instruction time (one tick per charged
        machine cycle; audit #3) and the serial tick raises XINT
        every tick in legacy mode (audit #4).  RTL matches C; the
        cycle model is the FSM's job, this module just counts ticks.
  KD-10 MPMC is ignored by pm_ptr (audit M16/M34) and there is no
        READY input, clock generator, TDM or HPI (audit N-3/N-4/
        N-16).  Not modelled here, matching C.
  KD-11 The 0xFF50..0xFF5F host window routes to io_read/io_write,
        not pmem (audit M50/#33: not a manual feature).  RTL matches C.
*/

`default_nettype none

/* EXT_PMEM = 1: the 64K-word external (program / unified) memory is not in this module: it is reached through the o_xm_* / i_xm_* ports
   (rtl/ram/c5x_xmem.sv: M10K cache in front of the SDRAM) and the top holds ce_i low until the lookup for the presented address is ready.
   EXT_PMEM = 0 keeps the 64K array here (unit tests, C co-sim). The internal data RAM (B0/B1/B2/SARAM, addresses below 0xC00) is always a 4K-word array. */
module c5x_mem #(
    parameter bit EXT_PMEM = 1'b0
) (
    input  logic        clk,
    input  logic        ce_i, /* DSP clock enable: every register advances only when high */
    input  logic        rst_n,

    /* ---- external memory port (EXT_PMEM = 1): the read data is registered here at the ce_i edge, same-address read during write returns the OLD word ---- */
    output logic        o_xm_rd_en,
    output logic [15:0] o_xm_raddr,
    output logic        o_xm_wr_en,
    output logic [15:0] o_xm_waddr,
    output logic [15:0] o_xm_wdata,
    input  logic [15:0] i_xm_rdata,

    /* PMST overlay bits (status-register owner, agent 2) */
    input  logic        i_cnf,
    input  logic        i_ovly,
    input  logic        i_ram,

    /* XINT mode level (host glue config; 0->1 edge sets xint_first) */
    input  logic        i_xint_mode,

    /* Timer tick: one pulse per charged machine cycle */
    input  logic        i_tick,
    input  logic        i_tick2,      /* a second tick in the same clock (real-time IDLE runs 1.5625 model cycles per clock); only with i_tick */

    /* Serial frame tick: one pulse per codec sample */
    input  logic        i_ser_tick,
    input  logic [15:0] i_ser_rx,

    /* Replay-window inputs (block-decode owner, agent 3) */
    input  logic        i_replay_active,
    input  logic [15:0] i_replay_lo,
    input  logic [15:0] i_replay_hi,

    /* ---- data-space channel (CPU core) ---- */
    input  logic        i_dm_req,
    input  logic        i_dm_rd, /* 1 = read, 0 = write */
    input  logic        i_dm_dmov, /* 1 = DMOV-family write (dmov_wr gate) */
    input  logic [15:0] i_dm_dmov_src, /* DMOV source address (gate input) */
    input  logic [15:0] i_dm_addr,
    input  logic [15:0] i_dm_wdata,
    output logic [15:0] o_dm_rdata, /* valid with o_dm_ack */
    output logic        o_dm_ack,
    output logic [2:0]  o_dm_io_ws, /* combinational io_ws(i_dm_addr) */
    output logic        o_dm_periph_ws, /* combinational: data write to 0x20..0x4F */

    /* ---- program-fetch channel ---- */
    input  logic        i_pm_fetch_req,
    input  logic [15:0] i_pm_fetch_addr,
    output logic [15:0] o_pm_fetch_data, /* valid with o_pm_fetch_ack */
    output logic        o_pm_fetch_ack,

    /* ---- program-write channel (BLPW/TBLW) ---- */
    input  logic        i_pm_wr_req,
    input  logic [15:0] i_pm_wr_addr,
    input  logic [15:0] i_pm_wr_data,
    output logic        o_pm_wr_ack,

    /* ---- external MMR port (registers owned by other agents) ---- */
    input  logic [15:0] i_ext_mmr_rdata, /* combinational from o_ext_mmr_addr */
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
    output logic        o_tmr_safe,   /* no timer expiry can occur within the next 8 ticks (timer stopped or TIM > 8): the FSM may charge a short instruction's cycles in one clock */
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

    /* Pending-read kind for the ack cycle */
    typedef enum logic [1:0] {
        KIND_REG  = 2'b00, /* dm_rdata_q (registers / ext MMR / host I/O / raw) */
        KIND_PMEM = 2'b01, /* pmem_rdata_q */
        KIND_DMEM = 2'b10 /* dmem_rdata_q */
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
    (* ramstyle = "M10K" *) reg [15:0] pmem [0:(EXT_PMEM ? 0 : 65535)];
    (* ramstyle = "M10K" *) reg [15:0] dmem [0:4095];
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
    ------------------------------------------------------------------
    Current data-access decode
    ------------------------------------------------------------------
    */
    route_t dm_route;
    logic   dm_is_io; /* this access goes to the host (MMR 0x50+ or hostwin) */
    logic   dm_wr_accept; /* DMOV gate result for writes */
    logic   dm_accept; /* this cycle's req is accepted by the channel */

    /* Data-channel state */
    logic        dm_io_wait_q;
    logic        dm_io_rd_q;
    logic [15:0] dm_io_addr_q;
    logic [15:0] dm_io_wdata_q;
    logic        dm_ack_q;
    logic [15:0] dm_rdata_q;
    kind_t       dm_pend_kind_q;

    /* Fetch / program-write pending latches */
    logic        fetch_pend_q;
    logic [15:0] fetch_addr_q;
    logic        fetch_ack_q;
    logic        fetch_pend_pmem_q;
    logic        pmwr_pend_q;
    logic [15:0] pmwr_addr_q;
    logic [15:0] pmwr_data_q;
    logic        pmwr_ack_q;

    always_comb begin
        dm_route = dm_route_f(i_dm_addr, i_cnf, i_ovly);
        dm_is_io = ((dm_route == ROUTE_MMR) && mmr_is_io_f(i_dm_addr)) ||
                   (dm_route == ROUTE_HOSTWIN);
        /*
        DMOV gate (dmov_wr, c5x_core.c:949-954): source internal and
        >= 0x60, destination internal.  Non-DMOV writes always pass.
        (A DMOV destination is always >= 0x61, so it can never be an
        MMR, I/O or raw address.)
        */
        dm_wr_accept = !i_dm_dmov ||
            (dm_internal_f(i_dm_dmov_src, i_cnf, i_ovly) &&
             (i_dm_dmov_src >= DM_MMR_END) &&
             dm_internal_f(i_dm_addr, i_cnf, i_ovly));
        dm_accept = i_dm_req && !dm_io_wait_q && !dm_ack_q;
    end

    /* Wait-state outputs (combinational for the presented address). */
    always_comb begin
        if (dm_is_io)
            o_dm_io_ws = io_ws_f(i_dm_addr, iowsr_q, cwsr_q);
        else
            o_dm_io_ws = 3'd0;
        /*
        mmr_bus (c5x_core.c:812-816): a data WRITE to 0x20..0x4F
        adds one cycle.  Reads do not (dm_rd never calls mmr_bus).
        */
        o_dm_periph_ws = i_dm_req && !i_dm_rd &&
            (dm_route == ROUTE_MMR) &&
            (i_dm_addr >= DM_PERIPH_START) && (i_dm_addr < DM_PERIPH_END);
    end

    /*
    ------------------------------------------------------------------
    Post-write timer state (write first, then tick -- C order:
    the SMMR/TCR write inside an instruction precedes that
    instruction's advance_timer).  Used by the tick and by
    o_tint_pulse.
    ------------------------------------------------------------------
    */
    logic        cpu_wr_tim, cpu_wr_prd, cpu_wr_tcr;
    logic [15:0] tim_eff, prd_eff;
    logic [3:0]  psc_eff, tddr_eff;
    logic        tss_eff;
    logic        t1_exp, t2_exp;
    logic [3:0]  t1_psc, t2_psc;
    logic [15:0] t1_tim, t2_tim;

    always_comb begin
        cpu_wr_tim = dm_accept && !i_dm_rd && dm_wr_accept &&
                     (dm_route == ROUTE_MMR) && (i_dm_addr == MMR_TIM_ADDR);
        cpu_wr_prd = dm_accept && !i_dm_rd && dm_wr_accept &&
                     (dm_route == ROUTE_MMR) && (i_dm_addr == MMR_PRD_ADDR);
        cpu_wr_tcr = dm_accept && !i_dm_rd && dm_wr_accept &&
                     (dm_route == ROUTE_MMR) && (i_dm_addr == MMR_TCR_ADDR);
        prd_eff  = cpu_wr_prd ? i_dm_wdata : prd_q;
        tss_eff  = cpu_wr_tcr ? i_dm_wdata[TCR_TSS_BIT] : tss_q;
        tddr_eff = cpu_wr_tcr ? i_dm_wdata[3:0] : tcr_tddr_q;
        /*
        TCR write with TRB reloads TIM from PRD (pre-write PRD: a
        PRD write cannot coincide with a TCR write -- one access).
        */
        if (cpu_wr_tim)
            tim_eff = i_dm_wdata;
        else if (cpu_wr_tcr && i_dm_wdata[TCR_TRB_BIT])
            tim_eff = prd_q;
        else
            tim_eff = tim_q;
        if (cpu_wr_tcr) begin
            if (i_dm_wdata[TCR_TRB_BIT])
                psc_eff = i_dm_wdata[3:0];
            else
                psc_eff = i_dm_wdata[9:6];
        end else begin
            psc_eff = psc_q;
        end
    end

    /*
    ------------------------------------------------------------------
    Serial-tick-first status values for the SPC read mux
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

    /* MMR read mux for my registers (mmr_rd, c5x_core.c:620-675). */
    logic [15:0] mmr_my_rdata;
    always_comb begin
        case (i_dm_addr)
            MMR_GREG_ADDR: mmr_my_rdata = greg_q;
            MMR_DRR_ADDR: mmr_my_rdata = drr_rd;
            MMR_DXR_ADDR: mmr_my_rdata = dxr_q;
            MMR_SPC_ADDR: mmr_my_rdata = (spc_q & SPC_WRITABLE_MASK) |
                                     (rsrfull_rd ? SPC_RSRF_FLAG : 16'h0000) |
                                     (xsrempty_rd ? SPC_XSREMPTY_FLAG : 16'h0000) |
                                     (xrdy_rd ? SPC_XRDY_FLAG : 16'h0000) |
                                     (rrdy_rd ? SPC_RRDY_FLAG : 16'h0000);
            MMR_TIM_ADDR: mmr_my_rdata = tim_q;
            MMR_PRD_ADDR: mmr_my_rdata = prd_q;
            MMR_TCR_ADDR: mmr_my_rdata = {6'b000000, psc_q, 1'b0, tss_q,
                                      tcr_tddr_q};
            MMR_PDWSR_ADDR: mmr_my_rdata = pdwsr_q;
            MMR_IOWSR_ADDR: mmr_my_rdata = iowsr_q;
            MMR_CWSR_ADDR: mmr_my_rdata = {11'b00000000000, cwsr_q};
            default:  mmr_my_rdata = 16'h0000;
        endcase
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

    /*
    ------------------------------------------------------------------
    Event pulses (combinational, high in the cycle the causing
    access/tick is presented; captured at the ending edge).
    ------------------------------------------------------------------
    */
    logic guard_fires;
    logic epoch_inc_ext; /* external dm_wr: epoch only (C:936-943) */
    logic epoch_inc_mmr; /* MMR 0x07..0x0B write: epoch + dirty (blk_state_changed) */
    logic pmwr_served; /* program-write served this cycle (below) */

    always_comb begin
        /*
        Timer expiry: tick_timer reloads TIM from PRD and raises TINT
        (c5x_core.c:1336-1350).
        */
        o_tmr_safe   = tss_q || (tim_q > 16'd8);
        /* tick 1 on the post-write state, tick 2 on the result of tick 1 */
        t1_exp = i_tick && !tss_eff && (psc_eff == 4'd0) && (tim_eff == 16'd0);
        if (i_tick && !tss_eff) begin
            if (psc_eff == 4'd0) begin
                t1_psc = tddr_eff;
                t1_tim = (tim_eff == 16'd0) ? prd_eff : (tim_eff - 16'd1);
            end else begin
                t1_psc = psc_eff - 4'd1;
                t1_tim = tim_eff;
            end
        end else begin
            t1_psc = psc_eff;
            t1_tim = tim_eff;
        end
        t2_exp = i_tick && i_tick2 && !tss_eff && (t1_psc == 4'd0) && (t1_tim == 16'd0);
        if (i_tick && i_tick2 && !tss_eff) begin
            if (t1_psc == 4'd0) begin
                t2_psc = tddr_eff;
                t2_tim = (t1_tim == 16'd0) ? prd_eff : (t1_tim - 16'd1);
            end else begin
                t2_psc = t1_psc - 4'd1;
                t2_tim = t1_tim;
            end
        end else begin
            t2_psc = t1_psc;
            t2_tim = t1_tim;
        end
        o_tint_pulse = t1_exp || t2_exp;
        /* Serial RX ready (c5x_serial_tick:3316-3330). */
        o_rint_pulse = i_ser_tick && spc_q[SPC_RRST_BIT] && !rrdy_q && !rsrfull_q;
        /*
        Serial TX ready: tick with XRST set (legacy: every tick;
        mode 1: only after a DXR write, plus the initial kick), or
        an SPC write with XRST=0 while XRDY was 0 (mmr_wr:754-760).
        */
        o_xint_pulse = (i_ser_tick && spc_q[SPC_XRST_BIT] &&
                        (!i_xint_mode || !xrdy_q || xint_first_q)) ||
                       (dm_accept && !i_dm_rd && dm_wr_accept &&
                        (dm_route == ROUTE_MMR) && (i_dm_addr == MMR_SPC_ADDR) &&
                        !i_dm_wdata[SPC_XRST_BIT] && !xrdy_q);
        /* DXR write stream to the host glue (dxr_ring in C). */
        o_dxr_wr = dm_accept && !i_dm_rd && dm_wr_accept &&
                   (dm_route == ROUTE_MMR) && (i_dm_addr == MMR_DXR_ADDR);
        o_dxr_wdata = i_dm_wdata;

        /*
        pm_epoch bumps: an external data write bumps epoch directly
        in dm_wr (c5x_core.c:936-943); a program write or an MMR
        write to PMST/RPTC/BRCR/PASR/PAER (0x07..0x0B) bumps it via
        blk_state_changed (c5x_core.c:328-334, 966, 708-721).
        */
        epoch_inc_ext = dm_accept && !i_dm_rd && dm_wr_accept &&
                        (dm_route == ROUTE_EXTERNAL);
        epoch_inc_mmr = dm_accept && !i_dm_rd && dm_wr_accept &&
                        (dm_route == ROUTE_MMR) &&
                        (i_dm_addr >= MMR_BLK_START) && (i_dm_addr <= MMR_BLK_END);
        o_pm_epoch_inc = epoch_inc_ext || epoch_inc_mmr || pmwr_served;

        /*
        blk_store_guard (c5x_core.c:848-860): only while a replay is
        in flight.  External write landing on a block program word,
        or a SARAM write (RAM=1, OVLY=1) mapping into the block.
        */
        guard_fires = dm_accept && !i_dm_rd && dm_wr_accept &&
            (((dm_route == ROUTE_EXTERNAL) &&
              (i_dm_addr >= i_replay_lo) && (i_dm_addr <= i_replay_hi)) ||
             ((dm_route == ROUTE_INTERNAL) && i_ram && i_ovly &&
              (i_dm_addr >= DM_SARAM_START) && (i_dm_addr < DM_SARAM_END) &&
              ((i_dm_addr - DM_SARAM_START + PM_SARAM_START) >= i_replay_lo) &&
              ((i_dm_addr - DM_SARAM_START + PM_SARAM_START) <= i_replay_hi)));
        /*
        replay_dirty: the blk_state_changed paths (pm_wr, MMR
        0x07..0x0B) set it unconditionally while a replay is in
        flight; a dm_wr sets it ONLY via the guard -- dm_wr does
        NOT call blk_state_changed (see that function's comment).
        */
        o_replay_dirty_pulse = i_replay_active &&
                               (epoch_inc_mmr || pmwr_served || guard_fires);
    end

    /* External-MMR port (combinational strobes in the accept cycle). */
    always_comb begin
        o_ext_mmr_rd    = dm_accept && i_dm_rd &&
                          (dm_route == ROUTE_MMR) && mmr_is_ext_f(i_dm_addr);
        o_ext_mmr_wr    = dm_accept && !i_dm_rd && dm_wr_accept &&
                          (dm_route == ROUTE_MMR) && mmr_is_ext_f(i_dm_addr);
        o_ext_mmr_addr  = i_dm_addr;
        o_ext_mmr_wdata = i_dm_wdata;
    end

    /* Host I/O port (level handshake). */
    always_comb begin
        o_io_req   = dm_io_wait_q ||
                     (dm_accept && dm_is_io);
        o_io_rd    = dm_io_wait_q ? dm_io_rd_q : i_dm_rd;
        o_io_addr  = dm_io_wait_q ? dm_io_addr_q : i_dm_addr;
        o_io_wdata = dm_io_wait_q ? dm_io_wdata_q : i_dm_wdata;
    end

    /*
    ------------------------------------------------------------------
    BRAM port arbitration.  Per memory, priority data > pm_wr > fetch.
    A request is "effective" when fresh or latched pending.
    ------------------------------------------------------------------
    */
    logic        fetch_req_eff, pmwr_req_eff;
    logic [15:0] fetch_addr_eff, pmwr_addr_eff, pmwr_data_eff;
    logic        fetch_is_dmem, pmwr_is_dmem;
    logic        data_wants_pmem, data_wants_dmem;
    logic        pmwr_wants_pmem, pmwr_wants_dmem;
    logic        fetch_wants_pmem, fetch_wants_dmem;
    logic        pmem_serve_data, pmem_serve_pmwr, pmem_serve_fetch;
    logic        dmem_serve_data, dmem_serve_pmwr, dmem_serve_fetch;
    /* Simple dual-port signals (one read port + one write port each). */
    logic        pmem_rd_en, pmem_wr_en;
    logic [15:0] pmem_raddr, pmem_waddr, pmem_wdata;
    logic        dmem_rd_en, dmem_wr_en;
    logic [15:0] dmem_raddr, dmem_waddr, dmem_wdata;

    always_comb begin
        fetch_req_eff = i_pm_fetch_req || fetch_pend_q;
        fetch_addr_eff = fetch_pend_q ? fetch_addr_q : i_pm_fetch_addr;
        pmwr_req_eff = i_pm_wr_req || pmwr_pend_q;
        pmwr_addr_eff = pmwr_pend_q ? pmwr_addr_q : i_pm_wr_addr;
        pmwr_data_eff = pmwr_pend_q ? pmwr_data_q : i_pm_wr_data;
        fetch_is_dmem = pm_is_dmem_f(fetch_addr_eff, i_cnf, i_ram);
        pmwr_is_dmem = pm_is_dmem_f(pmwr_addr_eff, i_cnf, i_ram);

        data_wants_pmem = dm_accept && (dm_route == ROUTE_EXTERNAL);
        data_wants_dmem = dm_accept && (dm_route == ROUTE_INTERNAL);
        pmwr_wants_pmem = pmwr_req_eff && !pmwr_is_dmem;
        pmwr_wants_dmem = pmwr_req_eff && pmwr_is_dmem;
        fetch_wants_pmem = fetch_req_eff && !fetch_is_dmem;
        fetch_wants_dmem = fetch_req_eff && fetch_is_dmem;

        pmem_serve_data  = data_wants_pmem;
        pmem_serve_pmwr  = !data_wants_pmem && pmwr_wants_pmem;
        pmem_serve_fetch = !data_wants_pmem && !pmwr_wants_pmem &&
                           fetch_wants_pmem;
        dmem_serve_data  = data_wants_dmem;
        dmem_serve_pmwr  = !data_wants_dmem && pmwr_wants_dmem;
        dmem_serve_fetch = !data_wants_dmem && !pmwr_wants_dmem &&
                           fetch_wants_dmem;

        pmwr_served = pmem_serve_pmwr || dmem_serve_pmwr;

        /*
        Read port: data read or fetch.  Write port: data write or
        program write.  The arbiter serves at most one request per
        memory per cycle, so the two ports are never active together
        on the same memory.
        */
        pmem_rd_en = (pmem_serve_data && i_dm_rd) || pmem_serve_fetch;
        pmem_raddr = pmem_serve_data ? i_dm_addr : fetch_addr_eff;
        pmem_wr_en = (pmem_serve_data && !i_dm_rd && dm_wr_accept) ||
                     pmem_serve_pmwr;
        pmem_waddr = pmem_serve_data ? i_dm_addr : pmwr_addr_eff;
        pmem_wdata = pmem_serve_data ? i_dm_wdata : pmwr_data_eff;

        /*
        A data access uses the data address directly (internal
        addresses map 1:1 into DMEM); a fetch/PM-write overlay
        address is translated by pm_dmem_addr_f.
        */
        dmem_rd_en = (dmem_serve_data && i_dm_rd) || dmem_serve_fetch;
        dmem_raddr = dmem_serve_data ? i_dm_addr :
                     pm_dmem_addr_f(fetch_addr_eff);
        dmem_wr_en = (dmem_serve_data && !i_dm_rd && dm_wr_accept) ||
                     dmem_serve_pmwr;
        dmem_waddr = dmem_serve_data ? i_dm_addr :
                     pm_dmem_addr_f(pmwr_addr_eff);
        dmem_wdata = dmem_serve_data ? i_dm_wdata : pmwr_data_eff;
    end

    /*
    PMEM / DMEM: simple dual-port M10K template.  Same-cycle
    same-address read returns the OLD word (RHS evaluated pre-edge).
    */
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (EXT_PMEM) begin
                if (pmem_rd_en)
                    pmem_rdata_q <= i_xm_rdata;
            end else begin
                if (pmem_wr_en)
                    pmem[pmem_waddr] <= pmem_wdata;
                if (pmem_rd_en)
                    pmem_rdata_q <= pmem[pmem_raddr];
            end
        end
    end

    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (dmem_wr_en)
                dmem[dmem_waddr[11:0]] <= dmem_wdata;
            if (dmem_rd_en)
                dmem_rdata_q <= dmem[dmem_raddr[11:0]];
        
        end
    end

    assign o_xm_rd_en = pmem_rd_en;
    assign o_xm_raddr = pmem_raddr;
    assign o_xm_wr_en = pmem_wr_en;
    assign o_xm_waddr = pmem_waddr;
    assign o_xm_wdata = pmem_wdata;

    /*
    mmr_raw: asynchronous read (combinational), synchronous write.
    The read data is captured into dm_rdata_q at the accept edge by
    the data-channel FSM, so the ack cycle still presents it.
    */
    logic [6:0]  raw_addr_mux;
    logic        raw_wr_en;
    logic [15:0] mmr_raw_rdata_comb;
    always_comb begin
        raw_addr_mux = i_dm_addr[6:0];
        raw_wr_en = dm_accept && !i_dm_rd && dm_wr_accept &&
                    (dm_route == ROUTE_MMR) && !mmr_is_mine_f(i_dm_addr) &&
                    !mmr_is_ext_f(i_dm_addr) && !mmr_is_io_f(i_dm_addr);
        mmr_raw_rdata_comb = mmr_raw[raw_addr_mux];
    end
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (raw_wr_en)
                mmr_raw[raw_addr_mux] <= i_dm_wdata;
        
        end
    end

    /* Data-channel read data (valid with o_dm_ack). */
    always_comb begin
        case (dm_pend_kind_q)
            KIND_PMEM: o_dm_rdata = (EXT_PMEM ? i_xm_rdata : pmem_rdata_q);
            KIND_DMEM: o_dm_rdata = dmem_rdata_q;
            default:   o_dm_rdata = dm_rdata_q;
        endcase
        o_dm_ack = dm_ack_q;
    end

    assign o_timer_exp_cnt = timer_exp_cnt_q;
    assign o_pm_fetch_ack  = fetch_ack_q;
    assign o_pm_wr_ack     = pmwr_ack_q;

    always_comb begin
        if (fetch_pend_pmem_q)
            o_pm_fetch_data = (EXT_PMEM ? i_xm_rdata : pmem_rdata_q);
        else
            o_pm_fetch_data = dmem_rdata_q;
    end

    /*
    ------------------------------------------------------------------
    Peripheral state: timer tick, serial tick, CPU accesses.
    Order inside this block is the C call order: serial tick first
    (the glue calls c5x_serial_tick before c5x_run), then the CPU
    access (wins over the tick on shared registers), then the timer
    tick applied to the POST-write state (write first, then tick --
    advance_timer runs after the instruction in C).
    ------------------------------------------------------------------
    */
    always_ff @(posedge clk) begin
        if (ce_i) begin
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
    
                /* ---- CPU data-channel access ---- */
                if (dm_accept) begin
                    if (i_dm_rd) begin
                        /* Reading DRR clears RRDY / RSRFULL (mmr_rd:652-656). */
                        if ((dm_route == ROUTE_MMR) &&
                            (i_dm_addr == MMR_DRR_ADDR)) begin
                            rrdy_q <= 1'b0;
                            rsrfull_q <= 1'b0;
                        end
                    end else if (dm_wr_accept && (dm_route == ROUTE_MMR)) begin
                        case (i_dm_addr)
                            MMR_GREG_ADDR: greg_q <= i_dm_wdata;
                            MMR_DRR_ADDR: drr_q <= i_dm_wdata;
                            MMR_DXR_ADDR: begin
                                dxr_q <= i_dm_wdata;
                                xrdy_q <= 1'b0;
                                xsrempty_q <= 1'b1;
                            end
                            MMR_SPC_ADDR: begin
                                spc_q <= i_dm_wdata & SPC_WRITABLE_MASK;
                                if (!i_dm_wdata[SPC_RRST_BIT]) begin
                                    rrdy_q <= 1'b0;
                                    rsrfull_q <= 1'b0;
                                end
                                if (!i_dm_wdata[SPC_XRST_BIT]) begin
                                    xsrempty_q <= 1'b0;
                                    xrdy_q <= 1'b1;
                                end
                            end
                            MMR_TIM_ADDR: tim_q <= i_dm_wdata;
                            MMR_PRD_ADDR: prd_q <= i_dm_wdata;
                            MMR_TCR_ADDR: begin
                                tcr_tddr_q <= i_dm_wdata[3:0];
                                tss_q <= i_dm_wdata[TCR_TSS_BIT];
                                if (i_dm_wdata[TCR_TRB_BIT]) begin
                                    tim_q <= prd_q;
                                    psc_q <= i_dm_wdata[3:0];
                                end else begin
                                    psc_q <= i_dm_wdata[9:6];
                                end
                            end
                            MMR_PDWSR_ADDR: pdwsr_q <= i_dm_wdata;
                            MMR_IOWSR_ADDR: iowsr_q <= i_dm_wdata;
                            MMR_CWSR_ADDR: cwsr_q <= i_dm_wdata[4:0];
                            default: begin end
                        endcase
                    end
                end
    
                /*
                ---- timer tick (tick_timer, c5x_core.c:1336-1350) ----
                Applied to the post-write state (tim_eff/psc_eff/...).
                */
                if (i_tick && !tss_eff) begin
                    psc_q <= t2_psc;
                    tim_q <= t2_tim;
                    if (t1_exp || t2_exp)
                        timer_exp_cnt_q <= timer_exp_cnt_q + {63'd0, t1_exp} + {63'd0, t2_exp};
                end
            end
        
        end
    end

    /*
    ------------------------------------------------------------------
    Data-channel state machine.
    ------------------------------------------------------------------
    */
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                dm_io_wait_q   <= 1'b0;
                dm_io_rd_q     <= 1'b0;
                dm_io_addr_q   <= 16'h0000;
                dm_io_wdata_q  <= 16'h0000;
                dm_ack_q       <= 1'b0;
                dm_rdata_q     <= 16'h0000;
                dm_pend_kind_q <= KIND_REG;
            end else begin
                if (dm_ack_q)
                    dm_ack_q <= 1'b0;
                if (dm_io_wait_q && i_io_ack) begin
                    /* Host answered: complete the access. */
                    dm_io_wait_q <= 1'b0;
                    dm_ack_q <= 1'b1;
                    dm_pend_kind_q <= KIND_REG;
                    if (dm_io_rd_q)
                        dm_rdata_q <= i_io_rdata;
                end else if (dm_accept) begin
                    if (dm_is_io) begin
                        dm_io_wait_q  <= 1'b1;
                        dm_io_rd_q    <= i_dm_rd;
                        dm_io_addr_q  <= i_dm_addr;
                        dm_io_wdata_q <= i_dm_wdata;
                    end else begin
                        dm_ack_q <= 1'b1;
                        if (i_dm_rd) begin
                            case (dm_route)
                                ROUTE_EXTERNAL: dm_pend_kind_q <= KIND_PMEM;
                                ROUTE_INTERNAL: dm_pend_kind_q <= KIND_DMEM;
                                ROUTE_MMR: begin
                                    if (mmr_is_mine_f(i_dm_addr)) begin
                                        dm_pend_kind_q <= KIND_REG;
                                        dm_rdata_q <= mmr_my_rdata;
                                    end else if (mmr_is_ext_f(i_dm_addr)) begin
                                        dm_pend_kind_q <= KIND_REG;
                                        dm_rdata_q <= i_ext_mmr_rdata;
                                    end else begin
                                        dm_pend_kind_q <= KIND_REG;
                                        dm_rdata_q <= mmr_raw_rdata_comb;
                                    end
                                end
                                default: begin
                                    dm_pend_kind_q <= KIND_REG;
                                    dm_rdata_q <= 16'h0000;
                                end
                            endcase
                        end else begin
                            dm_pend_kind_q <= KIND_REG;
                            dm_rdata_q <= 16'h0000;
                        end
                    end
                end
            end
        
        end
    end

    /*
    ------------------------------------------------------------------
    Fetch channel: serve (BRAM read) or latch pending.
    ------------------------------------------------------------------
    */
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                fetch_pend_q      <= 1'b0;
                fetch_addr_q      <= 16'h0000;
                fetch_ack_q       <= 1'b0;
                fetch_pend_pmem_q <= 1'b1;
            end else begin
                if (fetch_ack_q)
                    fetch_ack_q <= 1'b0;
                if (pmem_serve_fetch || dmem_serve_fetch) begin
                    fetch_ack_q <= 1'b1;
                    fetch_pend_pmem_q <= pmem_serve_fetch;
                    fetch_pend_q <= 1'b0;
                end else if (i_pm_fetch_req) begin
                    fetch_pend_q <= 1'b1;
                    fetch_addr_q <= i_pm_fetch_addr;
                end
            end
        
        end
    end

    /*
    ------------------------------------------------------------------
    Program-write channel: serve (BRAM write) or latch pending.
    ------------------------------------------------------------------
    */
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                pmwr_pend_q  <= 1'b0;
                pmwr_addr_q  <= 16'h0000;
                pmwr_data_q  <= 16'h0000;
                pmwr_ack_q   <= 1'b0;
            end else begin
                if (pmwr_ack_q)
                    pmwr_ack_q <= 1'b0;
                if (pmem_serve_pmwr || dmem_serve_pmwr) begin
                    pmwr_ack_q <= 1'b1;
                    pmwr_pend_q <= 1'b0;
                end else if (i_pm_wr_req) begin
                    pmwr_pend_q <= 1'b1;
                    pmwr_addr_q <= i_pm_wr_addr;
                    pmwr_data_q <= i_pm_wr_data;
                end
            end
        
        end
    end

endmodule

`default_nettype wire
