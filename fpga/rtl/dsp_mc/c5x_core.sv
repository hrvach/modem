/*
TMS320C5x DSP core top level: the Courier modem DSP (SV25 firmware).

Wires the real submodules: c5x_alu (CALU, shifter, multiplier),
c5x_addr (AR file, effective address, stack, status, RPT/RPTB,
IFR/IMR), c5x_decode and c5x_ctrl (instruction decode and the
multi-cycle control FSM), and c5x_mem (PMEM/DMEM in M10K, MMRs,
timer, serial port, host IO).

Talks to: the host glue through the IO handshake (codec and 186
mailbox), the codec serial tick, the external interrupt lines, the
firmware loader, and the co-simulation harness through the debug
read port and the memory-write event outputs.

Does not model: the 80C186 supervisor, the codec analogue front
end, or the telephone line. Those live outside this core; the host
glue provides them.

Reference model (the specification): the C core,
research_notes/courier-firmware/c-port/c/src/dsp/c5x_core.c.
Accuracy above all. Cyclone V, single clock, active-low
synchronous reset, no gated clocks, no Quartus primitives. The
M10K template lives inside c5x_mem (ramstyle attribute, simple
dual-port, registered read data, no reset on the array).

KNOWN-DIFF (top-level integration; the RTL matches the C model
except where noted -- see also rtl/c5x_ctl_pkg.sv KD-1..KD-24):
  KD-23 / OPEN-10 MADS/MADD TREG0 mirroring: FIXED 2026-11-19.
        The C model writes TREG0 directly for MADS/MADD (no
        set_t0, so no TRM mirror). The ALU now has OP_LT_NM
        (7'd64, i_op widened to 7 bits), and the ctrl issues it
        as a whole-body single issue in the WR phase (OP_LT_NM
        with acc_ld + preg_ld + treg_ld), so TREG1/TREG2 are
        untouched and ACC/PREG update off the OLD PREG. The old
        loop phase 6 is deleted. Plain LT still uses ALU_LT and
        still mirrors, per set_t0.
  CTRL-IOWS dm IO wait states missing: FIXED 2026-11-19.
        The control FSM added the io_ws charge only for IN/OUT
        (FSM_IO_WAIT) and the host-window ivec_ind read. A
        data-memory read or write to an IO port (MMR 0x50-0x5F,
        host window 0xFF50-0xFF5F) got no wait-state charge,
        but the C model charges io_ws on an IO read and
        (io_ws-1) on an IO write when io_ws > 1 (c5x_core.c
        io_read/io_write). Found by the co-sim at firmware
        instruction 2 (SPLK #0xFFFF, 0x57: C charges 8 cycles,
        the RTL charged 2). Fix: dm_rd_ws_q latches a dm
        read's io_ws at presentation; FSM_OP_DATA adds full
        io_ws on reads, io_ws-1 on writes; FSM_EXEC adds
        io_ws-1 on the presented write (2+6=8); loop phases
        charge per iteration the same way. Rule: dm read from
        IO space = +io_ws, dm write to IO space = +(io_ws-1)
        if io_ws > 1, dm write to peripheral MMR 0x20-0x4F =
        +1, dm read from peripheral MMR = +0.
  CTRL-STBIT single-bit status ops hit the wrong flag: FIXED
        2026-11-19. The control FSM set st_bit_sel = {1'b0,
        op_lo[3:0]} for the 0xBE 0x40-0x4F ops, using the
        opcode low nibble directly as the flag index. The C
        model maps the pair (op_lo[3:1]) to a flag and
        op_lo[0] to set/clear: 0x40/0x41 EINT/DINT -> INTM,
        0x42/0x43 ROVM/SOVM -> OVM, 0x44/0x45 RCNF/SCNF ->
        CNF, 0x46/0x47 RSXM/SSXM -> SXM, 0x48/0x49 RHM/SHM ->
        HM, 0x4A/0x4B RTC/STC -> TC, 0x4C/0x4D RXF/SXF -> XF,
        0x4E/0x4F RCB/SCB -> C (c5x_core.c, 0xBE sub-decoder).
        Found by the co-sim at firmware instruction 3 (DINT
        0xBE41: C sets INTM=1, the RTL set OVM=1, ST0
        C=0x0600 RTL=0x0E00). Fix: case table on op_lo[3:1]
        for the flag, set/clear from op_lo[0]; alu_flag_c_we
        now fires only for RCB/SCB (it fired for RTC/STC,
        corrupting the ALU's C copy).
  TOP-STATDP stat_dp wired to the wrong slice: FIXED
        2026-11-19. The top drove the control FSM's stat_dp
        from addr_dp[8:0], but the address unit's o_dp is the
        full pre-shifted dp_q ({page[8:0], 7'b0}); the page
        is bits [15:7], as o_st0 uses (dp_q[15:7]). DP=7 came
        out as stat_dp=384, and every ALU instruction's TAIL
        C/OV writeback then wrote the corrupted DP back into
        the address unit through WR_ST0. Found by the co-sim
        in the DSP smoke gate at checkpoint 1 (st0 C=0x2607
        RTL=0x2600) and by a minimal test (LDP #7; LACK
        #0x34: st0 C=0x0607 RTL=0x0780). Fix: one line,
        stat_dp from addr_dp[15:7].
  TOP-EXTMMR external-MMR writes dropped: FIXED 2026-11-19.
        The memory routes PMST, IMR, IFR, RPTC, BRCR, PASR,
        PAER, TREG0-2, DBMR, AR0-7, INDX, ARCR, CBSR/CBER,
        BMAR to the external-MMR path and pulses o_ext_mmr_wr,
        but the top left o_ext_mmr_wr / o_ext_mmr_wdata
        unconnected and the address-unit write-port mux was
        fed only by the control FSM's strobes, so a data-memory
        write to an external MMR never reached its owner (the
        read path worked). Found by the co-sim at firmware
        instruction 14 (OPL #lk to PMST: pmst C=0x00B0
        RTL=0x0000). Fix: the top connects the memory's
        ext-MMR write strobe into the write-port mux with an
        address-to-WR_* decode (the selects numerically equal
        the MMR addresses, c5x_addr.sv write-port selects).
        TREG0 is written through the ALU's treg load instead:
        the top overrides the ALU inputs for one cycle (op
        OP_LT, b16 the write data, treg load on, TRM forced so
        the mirror does not fire, exec on). That override is
        safe because the control FSM never executes the ALU in
        the cycle it presents a data-memory write (ex_alu_en
        is 0 for every plain store; the store data is already
        registered in ex_dm_wdata), and OP_LT writes no flags,
        so no other ALU state moves. TREG1/TREG2 are NOT
        routable: the C model writes them directly
        (c5x_core.c mmr_wr 0x0D/0x0E: treg1 = d & 0x1F,
        treg2 = d & 0xF), but the ALU can change TREG1/TREG2
        only through the TREG0-load mirror, which also writes
        TREG0, so there is no top-level-only way to write them
        alone. A direct data-memory write to 0x0D/0x0E is
        still dropped; it needs an ALU interface change. The
        SV25 firmware co-sim compares treg1_o/treg2_o per
        instruction and will show if the firmware ever does it.
        Residual corner: in the loop engine's WR phase the
        loop drives the ALU itself, so the TREG0 override
        would displace the loop's ALU op for one cycle if an
        SMMR/LMMR wrote to TREG0; the loop engine is dead
        (CTRL-LOOP, separate fix) and re-check this when it
        lands.
  TOP-IN IN data-memory write suppressed: FIXED 2026-11-19.
        IN (0xAF) from a host-window port read correctly, but
        the data-memory write never landed. The control FSM
        presents the IN write combinationally only in the
        IO-acknowledge cycle, while the top-level data-channel
        mux selected the IO branch whenever ctrl_io_req_c was
        high (throughout IO_WAIT), so the write was suppressed.
        Found by the co-sim with a minimal test (SPLK
        #0x1234,0x60; IN 0x60,0xFF50: DMEM 0x0060 C=0x0000
        RTL-shadow=0x1234). Fix: the top captures the IN write
        at the acknowledge edge and presents it to the memory
        in the next cycle, when the data channel is free (the
        FSM is in TICK and presents no data request), holding
        it until the memory acknowledges it. The mux must keep
        the IO port address in the acknowledge cycle itself:
        the FSM samples io_ws_i at that edge for the cycle
        charge. The same acknowledge-cycle fix drives the
        FSM's mmr_wr_hit from the IN target address instead of
        the port, so an IN to a peripheral MMR (0x20-0x4F)
        gets the mmr_bus +1 cycle the C model charges
        (c5x_core.c:812-816); a plain IN to data memory is
        unaffected (target outside 0x20-0x4F reads 0 either
        way).

Agent 3 integration deltas, all adapted in this file
(rtl/c5x_ctl_pkg.sv OPEN-1..OPEN-10):
  OPEN-1 alu_sh is [3:0] (shifts run 0-15).
  OPEN-2 rptb_brcr carries no load semantics (RPTB does not
        load BRCR); the wire is left unconnected.
  OPEN-3 extra ctrl inputs/outputs wired: acc_i/accb_i/preg_i/
        treg0/1/2_i, pmst_i, ar_arp_i, indx_i/arcr_i/bmar_i/
        dbmr_i, brcr_i/pasr_i/paer_i, bio_i, ivec_ind_i,
        io_ws_i, dm_ack (from mem o_dm_ack); ndx_commit_o,
        irq_ack_o, alu_flag_c_we/in, alu_flag_ov_we/in,
        addr_wr_en_o/sel_o/data_o.
  OPEN-4 the ALU/ADDR port lists here follow agents 1/2's
        real modules, not the package's assumed lists; the
        adaptation is a rename, not a redesign.
  OPEN-5 the ctrl computes cond() itself (c5x_cond); the
        addr's o_cond is left unconnected.
  OPEN-6 IDLE fast-forward: cycles_o advances 1 per clock
        while idle, timer with it except in IDLE2 (frozen).
  OPEN-7 the ctrl FSM has no module testbench; the SV25
        co-sim in sim/ is its proof.
  OPEN-8 alu_s16 is wired (ctrl alu_s16 output to ALU i_s16).
  OPEN-9 C/OV dual ownership: the ctrl writes the new flags
        back to the addr agent in TAIL and drives
        alu_flag_c_we/in and alu_flag_ov_we/in so the ALU's
        flag copy stays in sync.
  OPEN-10 see KD-23 above.
*/

`default_nettype none

module c5x_core #(
    parameter logic [15:0] RESET_PC = 16'h8000,
    parameter bit          EXT_PMEM = 1'b0, /* 1 = the 64K external memory is behind the xm_* port (see c5x_mem) */
    parameter logic [4:0]  CYC16    = 5'd25  /* model cycles of real time per DSP clock, times 16 (25.8048 MHz: 25, 40.32 MHz: 16): paces IDLE */
) (
    input  logic         clk,
    input  logic        ce_i, /* DSP clock enable: every register advances only when high */
    input  logic         rst_n,

    /* external memory port, see c5x_mem (EXT_PMEM = 1) */
    output logic         xm_rd_en_o,
    output logic [15:0]  xm_raddr_o,
    output logic         xm_wr_en_o,
    output logic [15:0]  xm_waddr_o,
    output logic [15:0]  xm_wdata_o,
    input  logic [15:0]  xm_rdata_i,

    /* Run and hold handshake, harness only. Tie to 1 in a
       free-running system. The control FSM parks in DONE while
       step_i is low; the harness pulses it high to single-step.
       The park is cycle-neutral: no cycles advance and no timer
       ticks fire while parked. */
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic         step_i,
    /* verilator lint_on UNUSEDSIGNAL */

    /* External interrupt lines. Bits 5:3 are intentionally unused
       here: TINT, RINT and XINT are driven by the memory peripheral
       event pulses, not by the host. */
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [8:0]  irq_i,
    /* verilator lint_on UNUSEDSIGNAL */

    /* BIO pin, host driven. The control FSM uses it in the branch
       condition function. */
    input  logic         bio_i,

    /* Interrupt vector indirection table, host configuration. Nine
       16-bit entries, one per interrupt bit 0 to 8. Entry n holds
       the data-memory address whose contents replace vector n, or
       zero for no indirection. The C driver sets entry n to 0x60+n
       for the SV25 firmware. */
    input  logic [143:0] ivec_ind_i,

    /* Codec sample tick and XINT mode, host glue. */
    input  logic         ser_tick,
    input  logic [15:0] ser_rx,
    input  logic         xint_mode,

    /* Host IO handshake, codec and 186 mailbox. io_ack is a level
       handshake: the host asserts it while io_req is high and the
       data is ready, and holds it until io_req drops. */
    output logic         io_req,
    output logic         io_rd,
    output logic [15:0] io_port,
    output logic [15:0] io_wdata,
    input  logic [15:0] io_rdata,
    input  logic         io_ack,

    /* Firmware loader. The core is held in reset while loading.
       load_pmem selects the program-write channel (PMEM); clear
       selects the data channel (DMEM). */
    input  logic         load_en,
    input  logic         load_pmem,
    input  logic [15:0] load_addr,
    input  logic [15:0] load_data,

    /* Harness-only debug read through the memory data channel.
       Assert dbg_en with dbg_addr; dbg_done pulses when dbg_rdata
       is valid. Debug reads take clocks but no model cycles, so
       they do not advance the timer. Only use them when the core
       is halted or parked: a debug read clocks the design, and the
       control FSM runs ahead while it completes. A debug read of
       DRR (0x20) clears RRDY and RSRFALL; the harness reads DRR
       only at the end of a run, after its final SPC read. */
    input  logic         dbg_en,
    input  logic [15:0] dbg_addr,
    output logic [15:0] dbg_rdata,
    output logic         dbg_done,

    /* DXR transmit stream to the host glue, codec DAC word. */
    output logic         dxr_wr,
    output logic [15:0] dxr_wdata,

    /* Timer expiry count, for the DSP smoke gate. Counts timer
       expiries since reset. */
    output logic [63:0]  timer_exp_cnt_o,

    /* Memory write events for the harness shadow. A one-cycle
       pulse after a core write to PMEM or DMEM is accepted. Load
       writes are not reported. */
    output logic         mem_wr_pulse,
    output logic         mem_wr_pmem,
    output logic [15:0] mem_wr_addr,
    output logic [15:0] mem_wr_data,

    /* Observation: architectural state after the last instr_done. */
    output logic         instr_done,
    output logic [63:0]  cycles_o,
    output logic [15:0]  pc_o,
    output logic [15:0]  op_o,
    output logic [31:0]  acc_o,
    output logic [31:0]  accb_o,
    output logic [31:0]  preg_o,
    output logic [15:0]  treg0_o,
    output logic [15:0]  treg1_o,
    output logic [15:0]  treg2_o,
    output logic [15:0]  ar_cur_o,
    output logic [2:0]   arp_o,
    output logic [15:0]  st0_o,
    output logic [15:0]  st1_o,
    output logic [15:0]  pmst_o,
    output logic [31:0]  rptc_o,
    output logic [31:0]  brcr_o,
    output logic [15:0]  pasr_o,
    output logic [15:0]  paer_o,
    output logic [15:0]  bmar_o,
    output logic [15:0]  dbmr_o,
    output logic [15:0]  indx_o,
    output logic [15:0]  arcr_o,
    output logic [2:0]   sp_o,
    output logic [15:0]  stack_top_o,
    output logic [127:0] ar_all_o,
    output logic [127:0] stack_all_o,
    output logic [15:0]  ifr_o,
    output logic [15:0]  imr_o,
    output logic         idle_o,
    output logic         halted_o,

    /* Memory-owned registers, captured by the debug sequencer.
       After reset they hold the C reset values; the harness
       refreshes them with debug reads. */
    output logic [15:0]  tim_o,
    output logic [15:0]  prd_o,
    output logic [15:0]  dxr_o,
    output logic [15:0]  drr_o,
    output logic [15:0]  greg_o,
    output logic [15:0]  spc_o,
    output logic [15:0]  tcr_o,
    output logic [15:0]  pdwsr_o,
    output logic [15:0]  iowsr_o,
    output logic [15:0]  cwsr_o,

    /* Memory-owned registers, direct observation from the memory
       module. Combinational from stored state; sample at
       instruction boundaries. Unlike the debug-sequencer outputs
       above, reading these never clears flags (no DRR side
       effect). SPC carries the status flags in bits 13..10;
       TCR and CWSR are composed readbacks matching mmr_rd. */
    output logic [15:0]  obs_tim_o,
    output logic [15:0]  obs_prd_o,
    output logic [15:0]  obs_dxr_o,
    output logic [15:0]  obs_drr_o,
    output logic [15:0]  obs_greg_o,
    output logic [15:0]  obs_spc_o,
    output logic [15:0]  obs_tcr_o,
    output logic [15:0]  obs_pdwsr_o,
    output logic [15:0]  obs_iowsr_o,
    output logic [15:0]  obs_cwsr_o
);
    /*
    Source citations for the localparams below. SST opcodes and the
    page-0 rule come from the C core. The write-port selects and
    flag selects come from c5x_addr. The MPYU micro-op comes from
    c5x_alu. The MMR addresses come from the C core memory map.
    */
    localparam logic [7:0] OP_SST0 = 8'h8E;
    localparam logic [7:0] OP_SST1 = 8'h8F;
    localparam logic [5:0] WR_IMR   = 6'h04;
    localparam logic [5:0] WR_IFR   = 6'h06;
    localparam logic [5:0] WR_PMST  = 6'h07;
    localparam logic [5:0] WR_RPTC  = 6'h08;
    localparam logic [5:0] WR_BRCR  = 6'h09;
    localparam logic [5:0] WR_PASR  = 6'h0A;
    localparam logic [5:0] WR_PAER  = 6'h0B;
    localparam logic [5:0] WR_DBMR  = 6'h0F;
    localparam logic [5:0] WR_AR0   = 6'h10;
    localparam logic [5:0] WR_INDX  = 6'h18;
    localparam logic [5:0] WR_ARCR  = 6'h19;
    localparam logic [5:0] WR_CBSR1 = 6'h1A;
    localparam logic [5:0] WR_CBER1 = 6'h1B;
    localparam logic [5:0] WR_CBSR2 = 6'h1C;
    localparam logic [5:0] WR_CBER2 = 6'h1D;
    localparam logic [5:0] WR_CBCR  = 6'h1E;
    localparam logic [5:0] WR_BMAR  = 6'h1F;
    localparam logic [5:0] WR_ST0   = 6'h20;
    localparam logic [5:0] WR_ST1   = 6'h21;
    localparam logic [4:0] FLG_C    = 5'd3;
    localparam logic [6:0] ALU_OP_MPYU = 7'd47;
    localparam logic [6:0] ALU_OP_LT   = 7'd45;
    localparam logic [15:0] MMR_AR_FIRST = 16'h0010;
    localparam logic [15:0] MMR_AR_NEXT  = 16'h0018;
    localparam logic [15:0] DM_PERIPH_START = 16'h0020;
    localparam logic [15:0] DM_PERIPH_END   = 16'h0050;
    localparam logic [15:0] MMR_IMR   = 16'h0004;
    localparam logic [15:0] MMR_GREG  = 16'h0005;
    localparam logic [15:0] MMR_IFR   = 16'h0006;
    localparam logic [15:0] MMR_PMST  = 16'h0007;
    localparam logic [15:0] MMR_RPTC  = 16'h0008;
    localparam logic [15:0] MMR_BRCR  = 16'h0009;
    localparam logic [15:0] MMR_PASR  = 16'h000A;
    localparam logic [15:0] MMR_PAER  = 16'h000B;
    localparam logic [15:0] MMR_TREG0 = 16'h000C;
    localparam logic [15:0] MMR_TREG1 = 16'h000D;
    localparam logic [15:0] MMR_TREG2 = 16'h000E;
    localparam logic [15:0] MMR_DBMR  = 16'h000F;
    localparam logic [15:0] MMR_INDX  = 16'h0018;
    localparam logic [15:0] MMR_ARCR  = 16'h0019;
    localparam logic [15:0] MMR_CBSR1 = 16'h001A;
    localparam logic [15:0] MMR_CBER1 = 16'h001B;
    localparam logic [15:0] MMR_CBSR2 = 16'h001C;
    localparam logic [15:0] MMR_CBER2 = 16'h001D;
    localparam logic [15:0] MMR_CBCR  = 16'h001E;
    localparam logic [15:0] MMR_BMAR  = 16'h001F;
    localparam logic [15:0] MMR_DRR   = 16'h0020;
    localparam logic [15:0] MMR_DXR   = 16'h0021;
    localparam logic [15:0] MMR_SPC   = 16'h0022;
    localparam logic [15:0] MMR_TIM   = 16'h0024;
    localparam logic [15:0] MMR_PRD   = 16'h0025;
    localparam logic [15:0] MMR_TCR   = 16'h0026;
    localparam logic [15:0] MMR_PDWSR = 16'h0028;
    localparam logic [15:0] MMR_IOWSR = 16'h0029;
    localparam logic [15:0] MMR_CWSR  = 16'h002A;
    localparam logic [15:0] IO_HOST_LO = 16'hFF50;
    localparam logic [15:0] IO_HOST_HI = 16'hFF5F;
    localparam logic [15:0] MMR_END    = 16'h0060;

    /*
    Status-bit slices, C st0_get, st1_get and pmst_get.
    ST0: ARP[15:13] OV[12] OVM[11] 1[10] INTM[9] DP[8:0].
    ST1: ARB[15:13] CNF[12] TC[11] SXM[10] C[9] 1[8] 1[7] HM[6]
    1[5] XF[4] 1[3] 1[2] PM[1:0].
    PMST: IPTR[15:11] AVIS[7] OVLY[5] RAM[4] MPMC[3] NDX[2]
    TRM[1] BRAF[0].
    */
    logic [15:0] addr_st0;
    logic [15:0] addr_st1;
    logic [15:0] addr_pmst;
    logic        st1_cnf;
    logic        st1_sxm;
    logic        st0_ovm;
    logic [1:0]  st1_pm;
    logic        pmst_ovly;
    logic        pmst_ram;
    logic        pmst_trm;

    assign st1_cnf   = addr_st1[12];
    assign st1_sxm   = addr_st1[10];
    assign st0_ovm   = addr_st0[11];
    assign st1_pm    = addr_st1[1:0];
    assign pmst_ovly = addr_pmst[5];
    assign pmst_ram  = addr_pmst[4];
    assign pmst_trm  = addr_pmst[1];

    /*
    Submodule wires.
    */
    logic [31:0] alu_acc;
    logic [31:0] alu_accb;
    logic [31:0] alu_preg;
    logic [15:0] alu_treg0;
    logic [15:0] alu_treg1;
    logic [15:0] alu_treg2;
    logic        alu_c;
    logic        alu_ov;
    logic [31:0] alu_mpy;
    logic signed [31:0] alu_acc_next;

    logic [15:0] addr_ea;
    logic [15:0] addr_pop_data;
    logic [2:0]  addr_sp;
    logic [15:0] addr_ar;
    logic [15:0] addr_ar_rd;
    logic [2:0]  addr_arp;
    logic [2:0]  addr_arb;
    /* o_dp is the pre-shifted dp_q ({page[8:0], 7'b0}); the DP
       page is bits [15:7], as o_st0 uses (dp_q[15:7]). */
    /* verilator lint_off UNUSEDSIGNAL */
    logic [15:0] addr_dp;
    /* verilator lint_on UNUSEDSIGNAL */
    logic [15:0] addr_indx;
    logic [15:0] addr_arcr;
    logic [31:0] addr_rptc;
    logic [31:0] addr_brcr;
    logic [15:0] addr_pasr;
    logic [15:0] addr_paer;
    logic [15:0] addr_bmar;
    logic [15:0] addr_dbmr;
    logic [15:0] addr_cbsr1;
    logic [15:0] addr_cber1;
    logic [15:0] addr_cbsr2;
    logic [15:0] addr_cber2;
    logic [7:0]  addr_cbcr;
    logic [15:0] addr_ifr;
    logic [15:0] addr_imr;
    logic        addr_tc;
    logic        addr_ov;
    logic        addr_c;
    logic        addr_braf;

    logic [6:0]  dec_alu_op;
    logic [1:0]  dec_words;
    logic [7:0]  dec_cycles;
    logic [7:0]  dec_ea_mode;
    logic        dec_is_branch;
    logic        dec_is_call;
    logic        dec_is_ret;
    logic        dec_is_rpt;
    logic        dec_is_rptb;
    logic        dec_is_idle;
    logic        dec_is_io;
    logic        dec_is_mem_wr;
    logic        dec_is_pm_wr;
    logic        dec_badop;

    logic [15:0] ctrl_pm_addr;
    logic [15:0] ctrl_dec_instr;
    logic [15:0] ctrl_dec_instr2;
    logic [6:0]  ctrl_alu_op;
    logic [2:0]  ctrl_ar_rd_sel;
    logic [31:0] ctrl_alu_b;
    logic [15:0] ctrl_alu_d;
    logic [3:0]  ctrl_alu_sh;
    logic        ctrl_alu_en;
    logic        ctrl_alu_s16;
    logic        ctrl_alu_flag_c_we;
    logic        ctrl_alu_flag_c_in;
    logic        ctrl_alu_flag_ov_we;
    logic        ctrl_alu_flag_ov_in;
    logic        ctrl_acc_ld;
    logic        ctrl_rs_en;
    logic [31:0] ctrl_acc_data, ctrl_accb_data, ctrl_preg_data;
    logic [15:0] ctrl_treg_data;
    logic        ctrl_accb_ld;
    logic        ctrl_preg_ld;
    logic [2:0]  ctrl_treg_ld;
    logic [15:0] ctrl_mpy_a;
    logic [15:0] ctrl_mpy_b;
    logic        ctrl_ea_en;
    logic [7:0]  ctrl_ea_op;
    logic [2:0]  ctrl_ar_wr_sel;
    logic [15:0] ctrl_ar_wr_data;
    logic        ctrl_ar_wr_en;
    logic        ctrl_push_en;
    logic [15:0] ctrl_push_data;
    logic        ctrl_pop_en;
    logic        ctrl_rptc_ld_en;
    logic [15:0] ctrl_rptc_ld_data;
    logic        ctrl_rptc_dec_en;
    logic        ctrl_st0_ld_en;
    logic [15:0] ctrl_st0_ld_data;
    logic        ctrl_st1_ld_en;
    logic [15:0] ctrl_st1_ld_data;
    logic        ctrl_pmst_ld_en;
    logic [15:0] ctrl_pmst_ld_data;
    logic        ctrl_st_bit_en;
    logic [4:0]  ctrl_st_bit_sel;
    logic        ctrl_st_bit_val;
    logic        ctrl_rptb_set_en;
    logic        ctrl_rptb_clr_en;
    logic [15:0] ctrl_rptb_pasr;
    logic [15:0] ctrl_rptb_paer;
    logic        ctrl_brcr_ld_en;
    /* The address-unit write port is 16 bits and zero-extends on
       WR_BRCR, so only the low half of the 32-bit load value
       reaches the register. The block count fits in 16 bits. */
    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0] ctrl_brcr_ld_data;
    /* verilator lint_on UNUSEDSIGNAL */
    logic        ctrl_dm_req;
    logic        ctrl_dm_wr;
    logic [15:0] ctrl_dm_addr;
    logic [15:0] ctrl_dm_wdata;
    logic        ctrl_pm_d_req;
    logic        ctrl_pm_d_wr;
    logic [15:0] ctrl_pm_d_addr;
    logic [15:0] ctrl_pm_d_wdata;
    logic        ctrl_mtick_en;
    logic [7:0]  ctrl_mtick_n;
    logic        ctrl_io_req_c;
    logic        ctrl_io_wr_c;
    logic [15:0] ctrl_io_port_c;
    logic [15:0] ctrl_io_wdata_c;
    logic        ctrl_instr_done;
    logic [63:0] ctrl_cycles;
    logic [15:0] ctrl_pc;
    logic [15:0] ctrl_op;
    logic        ctrl_idle;
    logic        ctrl_ndx_commit_o;
    logic [8:0]  ctrl_irq_ack_o;
    logic        ctrl_addr_wr_en_o;
    logic [5:0]  ctrl_addr_wr_sel_o;
    logic [15:0] ctrl_addr_wr_data_o;

    logic [15:0] mem_dm_rdata;
    logic        mem_dm_ack;
    logic [2:0]  mem_dm_io_ws;
    logic        mem_dm_periph_ws;
    logic [15:0] mem_pm_fetch_data;
    logic        mem_pm_wr_ack;
    logic [15:0] mem_ext_mmr_addr;
    logic        mem_ext_mmr_wr;
    logic [15:0] mem_ext_mmr_wdata;
    logic [15:0] ext_mmr_rdata;
    logic        mem_tint_pulse, mem_tmr_safe;
    logic        mem_rint_pulse;
    logic        mem_xint_pulse;
    logic [63:0] mem_timer_exp_cnt;
    logic        mem_io_req;
    logic        mem_io_rd;
    logic [15:0] mem_io_addr;
    logic [15:0] mem_io_wdata;
    logic        mem_dxr_wr;
    logic [15:0] mem_dxr_wdata;

    /* Muxed data-channel inputs to the memory. */
    logic        mux_dm_req;
    logic        mux_dm_rd;
    logic [15:0] mux_dm_addr;
    logic [15:0] mux_dm_wdata;

    /*
    External-MMR write decode (TOP-EXTMMR). The memory pulses
    mem_ext_mmr_wr for one cycle when it accepts a data-memory
    write to an external MMR; the address and data ride the same
    cycle. TREG0 is written through the ALU's treg load (the
    alu_*_mux wires below); TREG1/TREG2 have no top-level-only
    write path (see the header) and are excluded from the
    address-unit branch.
    */
    logic        ext_mmr_treg0_wr;
    logic        ext_mmr_treg12_wr;
    logic [5:0]  ext_mmr_wr_sel;
    logic        ext_mmr_wr_valid;

    /*
    ALU input overrides for an external-MMR write to TREG0.
    OP_LT loads TREG0 from b16 with no flag side effects; TRM
    forced so the TREG1/TREG2 mirror does not fire.
    */
    logic [6:0]  alu_op_mux;
    logic [15:0] alu_b16_mux;
    logic        alu_exec_mux;
    logic        alu_ld_treg0_mux;
    logic        alu_trm_mux;

    /*
    Pending IN write (TOP-IN). The control FSM presents the IN
    data-memory write only in the IO-acknowledge cycle; it is
    captured here and presented to the memory in the next cycle.
    */
    logic        in_wr_pend_q;
    logic [15:0] in_wr_addr_q;
    logic [15:0] in_wr_data_q;
    logic        in_wr_capture;
    logic        mmr_wr_hit_mux;
    /* Muxed program-write inputs to the memory. */
    logic        mux_pm_wr_req;
    logic [15:0] mux_pm_wr_addr;
    logic [15:0] mux_pm_wr_data;
    /* Timer tick burst counter, expanded from the control FSM
       mtick pulse. */
    logic [15:0] tick_burst_q;
    logic        mem_tick, mem_tick2;

    /* Debug sequencer. */
    typedef enum logic [1:0] {
        DEBUG_IDLE,
        DEBUG_REQUEST,
        DEBUG_DONE
    } debug_state_t;
    debug_state_t debug_state_q;
    logic [15:0] debug_addr_q;
    logic        debug_busy_q;
    logic        debug_req_active;
    logic [15:0] debug_rdata_q;
    logic        debug_done_q;

    /* Debug-captured memory registers, observation outputs. */
    logic [15:0] debug_tim_q;
    logic [15:0] debug_prd_q;
    logic [15:0] debug_dxr_q;
    logic [15:0] debug_drr_q;
    logic [15:0] debug_greg_q;
    logic [15:0] debug_spc_q;
    logic [15:0] debug_tcr_q;
    logic [15:0] debug_pdwsr_q;
    logic [15:0] debug_iowsr_q;
    logic [15:0] debug_cwsr_q;

    /* Memory-write snoop, registered request plus ack tracking. */
    logic        snoop_req_q;
    logic        snoop_rd_q;
    logic [15:0] snoop_addr_q;
    logic [15:0] snoop_data_q;
    logic        snoop_pmwr_q;
    logic [15:0] snoop_pmwr_addr_q;
    logic [15:0] snoop_pmwr_data_q;
    logic        snoop_pulse_q;
    logic        snoop_pmem_q;
    logic [15:0] snoop_wr_addr_q;
    logic [15:0] snoop_wr_data_q;

    /*
    External-MMR read mux, combinational from the memory address
    output. The memory samples it at the data-accept edge, so it
    must be combinational. AR0 to AR7 used to return zero: the address
    unit exposes no AR-file vector (it now does: ar_all_o, used
    below for 0x10..0x17).
    */
    always_comb begin
        case (mem_ext_mmr_addr)
            MMR_IMR:   ext_mmr_rdata = addr_imr;
            MMR_IFR:   ext_mmr_rdata = addr_ifr;
            MMR_PMST:  ext_mmr_rdata = addr_pmst;
            MMR_RPTC:  ext_mmr_rdata = addr_rptc[15:0];
            MMR_BRCR:  ext_mmr_rdata = addr_brcr[15:0];
            MMR_PASR:  ext_mmr_rdata = addr_pasr;
            MMR_PAER:  ext_mmr_rdata = addr_paer;
            MMR_TREG0: ext_mmr_rdata = alu_treg0;
            MMR_TREG1: ext_mmr_rdata = alu_treg1;
            MMR_TREG2: ext_mmr_rdata = alu_treg2;
            MMR_DBMR:  ext_mmr_rdata = addr_dbmr;
            MMR_INDX:  ext_mmr_rdata = addr_indx;
            MMR_ARCR:  ext_mmr_rdata = addr_arcr;
            MMR_CBSR1: ext_mmr_rdata = addr_cbsr1;
            MMR_CBER1: ext_mmr_rdata = addr_cber1;
            MMR_CBSR2: ext_mmr_rdata = addr_cbsr2;
            MMR_CBER2: ext_mmr_rdata = addr_cber2;
            MMR_CBCR:  ext_mmr_rdata = {8'd0, addr_cbcr};
            MMR_BMAR:  ext_mmr_rdata = addr_bmar;
            default:   ext_mmr_rdata = 16'd0;
        endcase
        /* AR0..AR7 at 0x10..0x17 (C mmr_rd returns ar[a - 0x10]) */
        if (mem_ext_mmr_addr[15:3] == 13'h0002)
            ext_mmr_rdata = ar_all_o[16 * mem_ext_mmr_addr[2:0] +: 16];
    end

    /*
    External-MMR write decode. The memory's ext-MMR list
    (c5x_mem.sv mmr_is_ext_f) and this decode cover exactly the
    same addresses: the named registers below plus AR0-AR7.
    TREG0-2 are excluded here -- TREG0 goes through the ALU
    override below, TREG1/TREG2 have no write path (header).
    The selects numerically equal the MMR addresses
    (c5x_addr.sv write-port selects), but the table states the
    mapping explicitly so a renumbering in the address unit
    cannot silently misroute a write. ext_mmr_wr_valid is low
    for any address outside the decode; the write-port mux
    requires it, so an undecoded address is dropped rather
    than written to select 0.
    */
    assign ext_mmr_treg0_wr  = mem_ext_mmr_wr &&
                               (mem_ext_mmr_addr == MMR_TREG0);
    assign ext_mmr_treg12_wr = mem_ext_mmr_wr &&
                               ((mem_ext_mmr_addr == MMR_TREG1) ||
                                (mem_ext_mmr_addr == MMR_TREG2));
    assign ext_mmr_wr_valid  = (ext_mmr_wr_sel != 6'd0);
    always_comb begin
        case (mem_ext_mmr_addr)
            MMR_IMR:   ext_mmr_wr_sel = WR_IMR;
            MMR_IFR:   ext_mmr_wr_sel = WR_IFR;
            MMR_PMST:  ext_mmr_wr_sel = WR_PMST;
            MMR_RPTC:  ext_mmr_wr_sel = WR_RPTC;
            MMR_BRCR:  ext_mmr_wr_sel = WR_BRCR;
            MMR_PASR:  ext_mmr_wr_sel = WR_PASR;
            MMR_PAER:  ext_mmr_wr_sel = WR_PAER;
            MMR_DBMR:  ext_mmr_wr_sel = WR_DBMR;
            MMR_INDX:  ext_mmr_wr_sel = WR_INDX;
            MMR_ARCR:  ext_mmr_wr_sel = WR_ARCR;
            MMR_CBSR1: ext_mmr_wr_sel = WR_CBSR1;
            MMR_CBER1: ext_mmr_wr_sel = WR_CBER1;
            MMR_CBSR2: ext_mmr_wr_sel = WR_CBSR2;
            MMR_CBER2: ext_mmr_wr_sel = WR_CBER2;
            MMR_CBCR:  ext_mmr_wr_sel = WR_CBCR;
            MMR_BMAR:  ext_mmr_wr_sel = WR_BMAR;
            default: begin
                if ((mem_ext_mmr_addr >= MMR_AR_FIRST) &&
                    (mem_ext_mmr_addr < MMR_AR_NEXT))
                    ext_mmr_wr_sel = WR_AR0 + {3'd0, mem_ext_mmr_addr[2:0]};
                else
                    ext_mmr_wr_sel = 6'd0;
            end
        endcase
    end

    /*
    ALU input overrides for an external-MMR write to TREG0.
    The C model writes TREG0 directly (c5x_core.c mmr_wr
    0x0C: treg0 = d, no set_t0 mirror), and OP_LT with TRM
    forced is the ALU op that loads TREG0 from b16 with no
    mirror and no flag write. The overrides are live only in
    the one cycle the memory accepts the write. The control
    FSM never executes the ALU in that cycle for a plain store
    (ex_alu_en is 0; the store data is already registered in
    ex_dm_wdata), so forcing exec on changes nothing else:
    ACC/PREG hold because their load strobes are 0, and OP_LT
    writes no flags. In the loop engine's WR phase the loop
    drives the ALU itself; the override takes priority there
    (see the header).
    */
    assign alu_op_mux        = ext_mmr_treg0_wr ? ALU_OP_LT : ctrl_alu_op;
    assign alu_b16_mux       = ext_mmr_treg0_wr ? mem_ext_mmr_wdata : ctrl_alu_d;
    assign alu_exec_mux      = ext_mmr_treg0_wr || ctrl_alu_en;
    assign alu_ld_treg0_mux  = ext_mmr_treg0_wr || (ctrl_treg_ld != 3'd0);
    assign alu_trm_mux       = ext_mmr_treg0_wr || pmst_trm;

    /*
    IN acknowledge-cycle capture. In the IO-acknowledge cycle
    the control FSM presents the IN data-memory write (dm_req,
    dm_wr, dm_addr = wr_addr_q, dm_wdata = io_rdata_c) while
    still asserting io_req_c; the data-channel mux below must
    keep the IO port address that cycle so io_ws_i stays the
    port's wait states for the cycle charge. The write is
    therefore captured at the acknowledge edge and presented
    to the memory in the next cycle instead.
    */
    assign in_wr_capture = ctrl_io_req_c && io_ack && !ctrl_io_wr_c &&
                           ctrl_dm_req && ctrl_dm_wr;
    /*
    mmr_wr_hit in the IN acknowledge cycle must describe the
    IN target address, not the IO port: the memory's
    periph_ws output follows the mux address, which is the
    port that cycle. Outside the acknowledge cycle the
    memory's output passes through unchanged.
    */
    assign mmr_wr_hit_mux = in_wr_capture ?
        ((ctrl_dm_addr >= DM_PERIPH_START) &&
         (ctrl_dm_addr < DM_PERIPH_END)) :
        mem_dm_periph_ws;

    /*
    IRQ-set composition: external lines plus memory peripheral
    pulses. C interrupt bits: 0 INT1, 1 INT2, 2 INT3, 3 TINT,
    4 RINT, 5 XINT, 6 TRNT, 7 TXNT, 8 INT4. irq_i bits 5:3 are
    ignored; the memory owns them.
    */
    logic [15:0] irq_set;
    assign irq_set = {7'd0, irq_i[8:6], mem_xint_pulse, mem_rint_pulse,
                      mem_tint_pulse, irq_i[2:0]};

    /*
    Address-unit write-port adapter. The control FSM has many load
    strobes; the address unit has one register-file write port.
    Priority order, highest first: external-MMR write (a one-cycle
    pulse from the memory that must not be dropped), LST direct
    write, ST0 load, ST1 load, PMST load, AR write, RPTC load,
    BRCR load, interrupt acknowledge. The control FSM never asserts
    two conflicting strobes in one cycle except the TAIL flag
    writeback, which asserts ST0 and ST1 together and is handled
    below through the flag port. The priority is a safety net, not
    a design rule.
    */
    logic        wr_port_en;
    logic [5:0]  wr_port_sel;
    logic [15:0] wr_port_data;
    logic        tail_writeback;
    assign tail_writeback = ctrl_st0_ld_en && ctrl_st1_ld_en;
    always_comb begin
        wr_port_en   = 1'b0;
        wr_port_sel  = 6'd0;
        wr_port_data = 16'd0;
        if (mem_ext_mmr_wr && !ext_mmr_treg0_wr && !ext_mmr_treg12_wr &&
            ext_mmr_wr_valid) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = ext_mmr_wr_sel;
            wr_port_data = mem_ext_mmr_wdata;
        end else if (ctrl_addr_wr_en_o) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = ctrl_addr_wr_sel_o;
            wr_port_data = ctrl_addr_wr_data_o;
        end else if (ctrl_st0_ld_en) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = WR_ST0;
            wr_port_data = ctrl_st0_ld_data;
        end else if (ctrl_st1_ld_en) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = WR_ST1;
            wr_port_data = ctrl_st1_ld_data;
        end else if (ctrl_pmst_ld_en) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = WR_PMST;
            wr_port_data = ctrl_pmst_ld_data;
        end else if (ctrl_ar_wr_en) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = WR_AR0 + {3'd0, ctrl_ar_wr_sel};
            wr_port_data = ctrl_ar_wr_data;
        end else if (ctrl_rptc_ld_en) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = WR_RPTC;
            wr_port_data = ctrl_rptc_ld_data;
        end else if (ctrl_irq_ack_o != 9'd0) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = WR_IFR;
            wr_port_data = {7'd0, ctrl_irq_ack_o};
        end
    end

    /*
    Address-unit flag-port adapter. The control FSM writes single
    status bits through st_bit. In the TAIL flag writeback the FSM
    asserts ST0 and ST1 loads together; the write port takes ST0
    and this flag port takes the C bit, so both update in the same
    cycle. The other bits of the two load words already hold the
    current status values, so updating only OV through the write
    port and only C through the flag port is equivalent to the two
    whole-word loads.
    */
    logic        flag_port_we;
    logic [4:0]  flag_port_sel;
    logic        flag_port_in;
    always_comb begin
        flag_port_we  = 1'b0;
        flag_port_sel = 5'd0;
        flag_port_in  = 1'b0;
        if (ctrl_st_bit_en) begin
            flag_port_we  = 1'b1;
            flag_port_sel = ctrl_st_bit_sel;
            flag_port_in  = ctrl_st_bit_val;
        end else if (tail_writeback) begin
            flag_port_we  = 1'b1;
            flag_port_sel = FLG_C;
            flag_port_in  = alu_c;
        end
    end

    /*
    Data-channel mux: loader, while the core is held in reset,
    then the debug sequencer, then the control FSM. The control
    FSM drives two read sources through this channel: its data
    access and its program-data read. A program-data read wins
    over a data access; the two are never active together. When
    the control FSM does an IN or OUT, the data channel is idle
    and its address carries the IO port, so the memory wait-state
    output reports the wait states for that port.
    */
    logic ctrl_pm_d_read;
    assign ctrl_pm_d_read = ctrl_pm_d_req && !ctrl_pm_d_wr;
    assign debug_req_active = (debug_state_q == DEBUG_REQUEST);
    always_comb begin
        if (load_en && !load_pmem) begin
            mux_dm_req   = 1'b1;
            mux_dm_rd    = 1'b0;
            mux_dm_addr  = load_addr;
            mux_dm_wdata = load_data;
        end else if (debug_req_active) begin
            mux_dm_req   = 1'b1;
            mux_dm_rd    = 1'b1;
            mux_dm_addr  = debug_addr_q;
            mux_dm_wdata = 16'd0;
        end else if (ctrl_io_req_c) begin
            mux_dm_req   = 1'b0;
            mux_dm_rd    = 1'b1;
            mux_dm_addr  = ctrl_io_port_c;
            mux_dm_wdata = 16'd0;
        end else if (ctrl_pm_d_read) begin
            mux_dm_req   = 1'b1;
            mux_dm_rd    = 1'b1;
            mux_dm_addr  = ctrl_pm_d_addr;
            mux_dm_wdata = 16'd0;
        end else if (in_wr_pend_q) begin
            mux_dm_req   = 1'b1;
            mux_dm_rd    = 1'b0;
            mux_dm_addr  = in_wr_addr_q;
            mux_dm_wdata = in_wr_data_q;
        end else begin
            mux_dm_req   = ctrl_dm_req;
            mux_dm_rd    = !ctrl_dm_wr;
            mux_dm_addr  = ctrl_dm_addr;
            mux_dm_wdata = ctrl_dm_wdata;
        end
    end

    /*
    Pending IN write register. Captured at the IO-acknowledge
    edge (see in_wr_capture above) and presented to the memory
    from the next cycle, when the control FSM is in TICK and
    presents no data request of its own. The request is held
    until the memory acknowledges it -- the same protocol the
    control FSM uses for its own data requests -- so a slow
    target (a data address in IO space, which inserts wait
    states) is presented until accepted instead of being
    dropped after one cycle. The capture wins over the clear;
    the two cannot coincide (a capture needs the FSM in
    IO_WAIT, a clear needs a pending write already presented).
    */
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                in_wr_pend_q <= 1'b0;
                in_wr_addr_q <= 16'd0;
                in_wr_data_q <= 16'd0;
            end else if (in_wr_capture) begin
                in_wr_pend_q <= 1'b1;
                in_wr_addr_q <= ctrl_dm_addr;
                in_wr_data_q <= ctrl_dm_wdata;
            end else if (in_wr_pend_q && mem_dm_ack) begin
                in_wr_pend_q <= 1'b0;
            end
        
        end
    end

    /*
    Program-write channel mux: loader, then the control FSM
    program-data write (BLPW and TBLW).
    */
    always_comb begin
        if (load_en && load_pmem) begin
            mux_pm_wr_req  = 1'b1;
            mux_pm_wr_addr = load_addr;
            mux_pm_wr_data = load_data;
        end else if (ctrl_pm_d_req && ctrl_pm_d_wr) begin
            mux_pm_wr_req  = 1'b1;
            mux_pm_wr_addr = ctrl_pm_d_addr;
            mux_pm_wr_data = ctrl_pm_d_wdata;
        end else begin
            mux_pm_wr_req  = 1'b0;
            mux_pm_wr_addr = 16'd0;
            mux_pm_wr_data = 16'd0;
        end
    end

    /*
    Timer tick burst. The control FSM emits one mtick pulse per
    instruction with the cycle count. The memory takes one pulse
    per charged machine cycle, so this counter expands the pulse
    into that many single-cycle pulses. It drains one per clock
    and accumulates a new pulse if one arrives while draining.
    The timer therefore lags the instruction boundary by at most
    the in-flight count; it catches up because the control FSM
    spends at least as many clocks per instruction as the cycle
    count it charges.
    */
    assign mem_tick  = (tick_burst_q != 16'd0);
    assign mem_tick2 = (tick_burst_q >= 16'd2);
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                tick_burst_q <= 16'd0;
            end else if (ctrl_mtick_en) begin
                tick_burst_q <= tick_burst_q + {8'd0, ctrl_mtick_n} - {15'd0, mem_tick} - {15'd0, mem_tick2};
            end else if (tick_burst_q != 16'd0) begin
                tick_burst_q <= tick_burst_q - {15'd0, mem_tick} - {15'd0, mem_tick2};
            end
        
        end
    end

    /*
    Host IO mux: the control FSM IN and OUT handshake and the
    memory host-window handshake share one host port. The two are
    never active together. The acknowledge and read data fan out
    to whichever side is requesting.
    */
    logic host_io_is_ctrl;
    assign host_io_is_ctrl = ctrl_io_req_c;
    assign io_req   = ctrl_io_req_c || mem_io_req;
    assign io_rd    = host_io_is_ctrl ? !ctrl_io_wr_c : mem_io_rd;
    assign io_port  = host_io_is_ctrl ? ctrl_io_port_c : mem_io_addr;
    assign io_wdata = host_io_is_ctrl ? ctrl_io_wdata_c : mem_io_wdata;
    assign dxr_wr   = mem_dxr_wr;
    assign dxr_wdata = mem_dxr_wdata;

    /*
    Debug sequencer: one data-channel read per dbg_en assertion.
    DEBUG_IDLE waits for dbg_en, DEBUG_REQUEST holds the read
    request until the memory acknowledges, DEBUG_DONE waits for
    dbg_en to drop. The request is level-held, so a cycle where
    the memory channel is busy simply delays the accept; the
    sequencer never loses the request.
    */
    assign dbg_rdata = debug_rdata_q;
    assign dbg_done  = debug_done_q;
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                debug_state_q  <= DEBUG_IDLE;
                debug_addr_q   <= 16'd0;
                debug_busy_q   <= 1'b0;
                debug_rdata_q  <= 16'd0;
                debug_done_q   <= 1'b0;
                debug_tim_q    <= 16'hFFFF;
                debug_prd_q    <= 16'hFFFF;
                debug_dxr_q    <= 16'd0;
                debug_drr_q    <= 16'd0;
                debug_greg_q   <= 16'd0;
                /* SPC reset value is the composed read value, not the
                   stored field: XRdy is 1 after reset, so an MMR read
                   of SPC returns 0x0800. */
                debug_spc_q    <= 16'h0800;
                debug_tcr_q    <= 16'd0;
                debug_pdwsr_q  <= 16'hFFFF;
                debug_iowsr_q  <= 16'hFFFF;
                debug_cwsr_q   <= 16'h000F;
            end else begin
                debug_done_q <= 1'b0;
                case (debug_state_q)
                    DEBUG_IDLE: begin
                        if (dbg_en && !debug_busy_q) begin
                            debug_addr_q  <= dbg_addr;
                            debug_busy_q  <= 1'b1;
                            debug_state_q <= DEBUG_REQUEST;
                        end
                    end
                    DEBUG_REQUEST: begin
                        if (mem_dm_ack) begin
                            debug_rdata_q <= mem_dm_rdata;
                            case (debug_addr_q)
                                MMR_GREG:  debug_greg_q  <= mem_dm_rdata;
                                MMR_DRR:   debug_drr_q   <= mem_dm_rdata;
                                MMR_DXR:   debug_dxr_q   <= mem_dm_rdata;
                                MMR_SPC:   debug_spc_q   <= mem_dm_rdata;
                                MMR_TIM:   debug_tim_q   <= mem_dm_rdata;
                                MMR_PRD:   debug_prd_q   <= mem_dm_rdata;
                                MMR_TCR:   debug_tcr_q   <= mem_dm_rdata;
                                MMR_PDWSR: debug_pdwsr_q <= mem_dm_rdata;
                                MMR_IOWSR: debug_iowsr_q <= mem_dm_rdata;
                                MMR_CWSR:  debug_cwsr_q  <= mem_dm_rdata;
                                default: begin end
                            endcase
                            debug_done_q  <= 1'b1;
                            debug_state_q <= DEBUG_DONE;
                        end
                    end
                    DEBUG_DONE: begin
                        if (!dbg_en) begin
                            debug_busy_q  <= 1'b0;
                            debug_state_q <= DEBUG_IDLE;
                        end
                    end
                    default: debug_state_q <= DEBUG_IDLE;
                endcase
            end
        
        end
    end

    /*
    Memory-write snoop. The memory accepts a data request in the
    cycle it is presented and acknowledges one cycle later; the
    request presented in the acknowledge cycle is never a new one,
    so the registered request at the acknowledge edge is the one
    being acknowledged. Route classification replicates the
    memory route functions, observation only, not functional
    logic. A data write below 0x60 targets an MMR and has no
    shadow; a write to the host window has no shadow; anything
    else internal is DMEM and anything else external is PMEM.
    Load writes are not reported.
    */
    function automatic logic snoop_dm_internal(input logic [15:0] a);
        begin
            snoop_dm_internal = (a < 16'h0080) ||
                ((a >= 16'h0100) && (a < 16'h0500) &&
                 !(st1_cnf && (a < 16'h0300))) ||
                (pmst_ovly && (a >= 16'h0800) && (a < 16'h0C00));
        end
    endfunction
    function automatic logic snoop_pm_is_dmem(input logic [15:0] a);
        begin
            snoop_pm_is_dmem = (st1_cnf && (a >= 16'hFE00)) ||
                (pmst_ram && (a >= 16'h0800) && (a < 16'h0C00));
        end
    endfunction

    assign mem_wr_pulse = snoop_pulse_q;
    assign mem_wr_pmem  = snoop_pmem_q;
    assign mem_wr_addr  = snoop_wr_addr_q;
    assign mem_wr_data  = snoop_wr_data_q;

    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                snoop_req_q       <= 1'b0;
                snoop_rd_q        <= 1'b1;
                snoop_addr_q      <= 16'd0;
                snoop_data_q      <= 16'd0;
                snoop_pmwr_q      <= 1'b0;
                snoop_pmwr_addr_q <= 16'd0;
                snoop_pmwr_data_q <= 16'd0;
                snoop_pulse_q     <= 1'b0;
                snoop_pmem_q      <= 1'b0;
                snoop_wr_addr_q   <= 16'd0;
                snoop_wr_data_q   <= 16'd0;
            end else begin
                snoop_pulse_q <= 1'b0;
                if (!load_en) begin
                    snoop_req_q  <= mux_dm_req;
                    snoop_rd_q   <= mux_dm_rd;
                    snoop_addr_q <= mux_dm_addr;
                    snoop_data_q <= mux_dm_wdata;
                    snoop_pmwr_q      <= mux_pm_wr_req;
                    snoop_pmwr_addr_q <= mux_pm_wr_addr;
                    snoop_pmwr_data_q <= mux_pm_wr_data;
                end else begin
                    snoop_req_q  <= 1'b0;
                    snoop_pmwr_q <= 1'b0;
                end
                if (mem_dm_ack && snoop_req_q && !snoop_rd_q) begin
                    if ((snoop_addr_q >= MMR_END) &&
                        !((snoop_addr_q >= IO_HOST_LO) &&
                          (snoop_addr_q <= IO_HOST_HI))) begin
                        snoop_pulse_q   <= 1'b1;
                        snoop_pmem_q    <= !snoop_dm_internal(snoop_addr_q);
                        snoop_wr_addr_q <= snoop_addr_q;
                        snoop_wr_data_q <= snoop_data_q;
                    end
                end
                if (mem_pm_wr_ack && snoop_pmwr_q) begin
                    snoop_pulse_q   <= 1'b1;
                    snoop_pmem_q    <= !snoop_pm_is_dmem(snoop_pmwr_addr_q);
                    snoop_wr_addr_q <= snoop_pmwr_addr_q;
                    snoop_wr_data_q <= snoop_pmwr_data_q;
                end
            end
        
        end
    end

    /*
    Observation outputs.
    */
    assign instr_done      = ctrl_instr_done;
    assign cycles_o        = ctrl_cycles;
    assign pc_o            = ctrl_pc;
    assign op_o            = ctrl_op;
    assign acc_o           = alu_acc;
    assign accb_o          = alu_accb;
    assign preg_o          = alu_preg;
    assign treg0_o         = alu_treg0;
    assign treg1_o         = alu_treg1;
    assign treg2_o         = alu_treg2;
    assign ar_cur_o        = addr_ar;
    assign arp_o           = addr_arp;
    assign st0_o           = addr_st0;
    assign st1_o           = addr_st1;
    assign pmst_o          = addr_pmst;
    assign rptc_o          = addr_rptc;
    assign brcr_o          = addr_brcr;
    assign pasr_o          = addr_pasr;
    assign paer_o          = addr_paer;
    assign bmar_o          = addr_bmar;
    assign dbmr_o          = addr_dbmr;
    assign indx_o          = addr_indx;
    assign arcr_o          = addr_arcr;
    assign sp_o            = addr_sp;
    assign stack_top_o     = addr_pop_data;
    assign ifr_o           = addr_ifr;
    assign imr_o           = addr_imr;
    assign idle_o          = ctrl_idle;
    assign halted_o        = 1'b0;
    assign tim_o           = debug_tim_q;
    assign prd_o           = debug_prd_q;
    assign dxr_o           = debug_dxr_q;
    assign drr_o           = debug_drr_q;
    assign greg_o          = debug_greg_q;
    assign spc_o           = debug_spc_q;
    assign tcr_o           = debug_tcr_q;
    assign pdwsr_o         = debug_pdwsr_q;
    assign iowsr_o         = debug_iowsr_q;
    assign cwsr_o          = debug_cwsr_q;
    assign timer_exp_cnt_o = mem_timer_exp_cnt;

    /*
    Submodule instances. One port connection per line, names
    aligned. Empty connections are intentional and documented
    here.

    Known interface gaps, all pending the owning agent, all
    logged as KNOWN-DIFF in docs/cosim.md. None is silently
    worked around.

    The ALU exposes its combinational micro-op result on
    acc_next, wired to the control FSM as alu_y. The FSM uses
    it only to form acc_data and accb_data. The ALU is the
    register file: it commits the result internally on i_ld_acc
    and i_ld_accb, so acc_data and accb_data are not wired
    anywhere here. The architectural ACC is observed from the
    ALU output, not from acc_data.

    The control FSM outputs alu_a and alu_c_in, the micro-op A
    operand and carry input. The ALU takes its A operand from
    its own ACC register and its carry from its own synced C
    flag, so those two outputs have no ALU input. They are left
    unconnected.

    The control FSM reads an indexed auxiliary register through
    ar_rd_sel and ar_rd_i. The address unit's indexed read
    (i_ar_rd_sel / o_ar_rd) is wired here, so SAR reads the
    selected register, not AR[ARP]. The full AR file and stack
    are exposed on ar_all_o / stack_all_o for the co-sim.

    External-MMR writes reach their owners through the top
    level. The memory's ext-MMR write strobe, address and data
    feed the address-unit write-port mux with an
    address-to-WR_* decode (TOP-EXTMMR); TREG0 is written
    through the ALU's treg load instead (the alu_*_mux
    overrides in the ALU instance above), and a data-memory
    write to TREG1/TREG2 is still dropped -- the ALU can
    change TREG1/TREG2 only through the TREG0-load mirror,
    which also writes TREG0. An IN instruction's data-memory
    write is captured at the IO-acknowledge edge and presented
    to the memory in the next cycle (TOP-IN), because the
    data-channel mux must still carry the IO port address in
    the acknowledge cycle itself.

    The control FSM parks in DONE while step_i is low; step_i
    is wired from the top-level input. The memory-owned
    registers are exposed twice: tim_o..cwsr_o come from the
    debug sequencer (unchanged), obs_tim_o..obs_cwsr_o are the
    memory module's direct observation outputs.
    */
    /* verilator lint_off PINCONNECTEMPTY */
    /* verilator lint_off UNUSEDSIGNAL */
    c5x_alu u_alu (
        .clk            (clk),
        .ce_i           (ce_i),
        .rst_n          (rst_n),
        .i_exec         (alu_exec_mux),
        .i_ld_acc       (ctrl_acc_ld),
        .i_ld_accb      (ctrl_accb_ld),
        .i_ld_preg      (ctrl_preg_ld),
        .i_ld_treg0     (alu_ld_treg0_mux),
        .i_rs_acc       (ctrl_rs_en && ctrl_acc_ld),
        .i_rs_accb      (ctrl_rs_en && ctrl_accb_ld),
        .i_rs_preg      (ctrl_rs_en && ctrl_preg_ld),
        .i_rs_treg      (ctrl_rs_en ? ctrl_treg_ld : 3'b000),
        .i_rs_acc_d     (ctrl_acc_data),
        .i_rs_accb_d    (ctrl_accb_data),
        .i_rs_preg_d    (ctrl_preg_data),
        .i_rs_treg_d    (ctrl_treg_data),
        .i_op           (alu_op_mux),
        .i_b32          (ctrl_alu_b),
        .i_b16          (alu_b16_mux),
        .i_mpy_a        (ctrl_mpy_a),
        .i_mpy_b        (ctrl_mpy_b),
        .i_mpy_unsigned (ctrl_alu_op == ALU_OP_MPYU),
        .i_shift        (ctrl_alu_sh),
        .i_s16          (ctrl_alu_s16),
        .i_sxm          (st1_sxm),
        .i_ovm          (st0_ovm),
        .i_pm           (st1_pm),
        .i_trm          (alu_trm_mux),
        .i_flag_c_we    (ctrl_alu_flag_c_we),
        .i_flag_c_in    (ctrl_alu_flag_c_in),
        .i_flag_ov_we   (ctrl_alu_flag_ov_we),
        .i_flag_ov_in   (ctrl_alu_flag_ov_in),
        .o_acc          (alu_acc),
        .o_accb         (alu_accb),
        .o_preg         (alu_preg),
        .o_treg0        (alu_treg0),
        .o_treg1        (alu_treg1),
        .o_treg2        (alu_treg2),
        .o_c            (alu_c),
        .o_ov           (alu_ov),
        .o_pscale       (),
        .o_ext          (),
        .o_b16_shl      (),
        .o_shl_acc      (),
        .o_mpy          (alu_mpy),
        .o_tc_next      (),
        .o_tc_wr        (),
        .acc_next       (alu_acc_next)
    );

    c5x_addr u_addr (
        .clk            (clk),
        .ce_i           (ce_i),
        .rst_n          (rst_n),
        .i_op           ({8'd0, ctrl_ea_op}),
        .i_acc          (alu_acc),
        .i_bio          (bio_i),
        .i_ea_en        (ctrl_ea_en),
        .i_ea_p0        ((ctrl_op[15:8] == OP_SST0) ||
                         (ctrl_op[15:8] == OP_SST1)),
        .o_ea           (addr_ea),
        .o_ea_badop     (),
        .o_cond         (),
        .i_wr_en        (wr_port_en),
        .i_wr_sel       (wr_port_sel),
        .i_wr_data      (wr_port_data),
        .i_flg_we       (flag_port_we),
        .i_flg_sel      (flag_port_sel),
        .i_flg_in       (flag_port_in),
        .i_pm_we        (1'b0),
        .i_pm_in        (2'd0),
        .i_iptr_we      (1'b0),
        .i_iptr_in      (5'd0),
        .i_cmpr_en      (1'b0),
        .i_cmpr_mode    (2'd0),
        .i_cmpr_ar0     (1'b0),
        .i_push_en      (ctrl_push_en),
        .i_push_data    (ctrl_push_data),
        .i_pop_en       (ctrl_pop_en),
        .o_pop_data     (addr_pop_data),
        .o_sp           (addr_sp),
        .i_irq_set      (irq_set),
        .i_irq_ack      (ctrl_irq_ack_o),
        .o_irq_pend     (),
        .i_ndx_commit   (ctrl_ndx_commit_o),
        .i_rpt_setup    (1'b0),
        .i_rpt_pc_in    (16'd0),
        .i_rpt_step     (1'b0),
        .i_rpt_ppc      (16'd0),
        .i_rpt_dec      (ctrl_rptc_dec_en),
        .o_rpt_restart  (),
        .o_rpt_pc       (),
        .o_rep_cont     (),
        .i_rptb_set     (ctrl_rptb_set_en),
        .i_rptb_pasr    (ctrl_rptb_pasr),
        .i_rptb_paer    (ctrl_rptb_paer),
        .i_braf_check   (ctrl_brcr_ld_en | ctrl_rptb_clr_en),
        .i_pc           (ctrl_pc),
        .o_braf_restart (),
        .o_braf_done    (),
        .o_st0          (addr_st0),
        .o_st1          (addr_st1),
        .o_pmst         (addr_pmst),
        .o_ar           (addr_ar),
        .o_arp          (addr_arp),
        .o_arb          (addr_arb),
        .o_dp           (addr_dp),
        .o_indx         (addr_indx),
        .o_arcr         (addr_arcr),
        .o_rptc         (addr_rptc),
        .o_brcr         (addr_brcr),
        .o_rpt_start    (),
        .o_rpt_end      (),
        .o_pasr         (addr_pasr),
        .o_paer         (addr_paer),
        .o_bmar         (addr_bmar),
        .o_dbmr         (addr_dbmr),
        .o_cbsr1        (addr_cbsr1),
        .o_cber1        (addr_cber1),
        .o_cbsr2        (addr_cbsr2),
        .o_cber2        (addr_cber2),
        .o_cbcr         (addr_cbcr),
        .o_ifr          (addr_ifr),
        .o_imr          (addr_imr),
        .o_tc           (addr_tc),
        .o_ov           (addr_ov),
        .o_c            (addr_c),
        .o_braf         (addr_braf),
        .o_ar0_dirty    (),
        .o_ar_all       (ar_all_o),
        .o_stack_all    (stack_all_o),
        .i_ar_rd_sel    (ctrl_ar_rd_sel),
        .o_ar_rd        (addr_ar_rd)
    );

    c5x_decode u_decode (
        .clk            (clk),
        .rst_n          (rst_n),
        .instr_i        (ctrl_dec_instr),
        .instr2_i       (ctrl_dec_instr2),
        .alu_op_o       (dec_alu_op),
        .words_o        (dec_words),
        .cycles_o       (dec_cycles),
        .ea_mode_o      (dec_ea_mode),
        .is_branch_o    (dec_is_branch),
        .is_call_o      (dec_is_call),
        .is_ret_o       (dec_is_ret),
        .is_rpt_o       (dec_is_rpt),
        .is_rptb_o      (dec_is_rptb),
        .is_idle_o      (dec_is_idle),
        .is_io_o        (dec_is_io),
        .is_mem_wr_o    (dec_is_mem_wr),
        .is_pm_wr_o     (dec_is_pm_wr),
        .badop_o        (dec_badop)
    );

    c5x_ctrl #(
        .CYC16          (CYC16),
        .RESET_PC       (RESET_PC)
    ) u_ctrl (
        .clk            (clk),
        .ce_i           (ce_i),
        .rst_n          (rst_n),
        .pm_addr        (ctrl_pm_addr),
        .pm_rdata       (mem_pm_fetch_data),
        .dm_rdata       (mem_dm_rdata),
        .dm_ack         (mem_dm_ack),
        .pm_d_rdata     (mem_dm_rdata),
        .dec_instr      (ctrl_dec_instr),
        .dec_instr2     (ctrl_dec_instr2),
        .dec_alu_op     (dec_alu_op),
        .dec_words      (dec_words),
        .dec_cycles     (dec_cycles),
        .dec_ea_mode    (dec_ea_mode),
        .dec_is_branch  (dec_is_branch),
        .dec_is_call    (dec_is_call),
        .dec_is_ret     (dec_is_ret),
        .dec_is_rpt     (dec_is_rpt),
        .dec_is_rptb    (dec_is_rptb),
        .dec_is_idle    (dec_is_idle),
        .dec_is_io      (dec_is_io),
        .dec_is_mem_wr  (dec_is_mem_wr),
        .dec_is_pm_wr   (dec_is_pm_wr),
        .dec_badop      (dec_badop),
        .alu_op         (ctrl_alu_op),
        .alu_a          (),
        .alu_b          (ctrl_alu_b),
        .alu_d          (ctrl_alu_d),
        .alu_sh         (ctrl_alu_sh),
        .alu_c_in       (),
        .alu_en         (ctrl_alu_en),
        .alu_s16        (ctrl_alu_s16),
        .alu_y          (alu_acc_next),
        .alu_c          (alu_c),
        .alu_ov         (alu_ov),
        .alu_flag_c_we  (ctrl_alu_flag_c_we),
        .alu_flag_c_in  (ctrl_alu_flag_c_in),
        .alu_flag_ov_we (ctrl_alu_flag_ov_we),
        .alu_flag_ov_in (ctrl_alu_flag_ov_in),
        .mpy_p          (alu_mpy),
        .rs_en          (ctrl_rs_en),
        .acc_ld         (ctrl_acc_ld),
        .acc_ld_sel     (),
        .acc_data       (ctrl_acc_data),
        .accb_ld        (ctrl_accb_ld),
        .accb_data      (ctrl_accb_data),
        .preg_ld        (ctrl_preg_ld),
        .preg_data      (ctrl_preg_data),
        .treg_ld        (ctrl_treg_ld),
        .treg_data      (ctrl_treg_data),
        .mpy_en         (),
        .mpy_a          (ctrl_mpy_a),
        .mpy_b          (ctrl_mpy_b),
        .ea_en          (ctrl_ea_en),
        .ea_op          (ctrl_ea_op),
        .ea_i           (addr_ea),
        .ar_wr_sel      (ctrl_ar_wr_sel),
        .ar_wr_data     (ctrl_ar_wr_data),
        .ar_wr_en       (ctrl_ar_wr_en),
        .ar_rd_sel      (ctrl_ar_rd_sel),
        .ar_rd_i        (addr_ar_rd),
        .push_en        (ctrl_push_en),
        .push_data      (ctrl_push_data),
        .pop_en         (ctrl_pop_en),
        .pop_data       (addr_pop_data),
        .rptc_ld_en     (ctrl_rptc_ld_en),
        .rptc_ld_data   (ctrl_rptc_ld_data),
        .rptc_dec_en    (ctrl_rptc_dec_en),
        .rptc_i         (addr_rptc),
        .st0_ld_en      (ctrl_st0_ld_en),
        .st0_ld_data    (ctrl_st0_ld_data),
        .st1_ld_en      (ctrl_st1_ld_en),
        .st1_ld_data    (ctrl_st1_ld_data),
        .pmst_ld_en     (ctrl_pmst_ld_en),
        .pmst_ld_data   (ctrl_pmst_ld_data),
        .st_bit_en      (ctrl_st_bit_en),
        .st_bit_sel     (ctrl_st_bit_sel),
        .st_bit_val     (ctrl_st_bit_val),
        .rptb_set_en    (ctrl_rptb_set_en),
        .rptb_pasr      (ctrl_rptb_pasr),
        .rptb_paer      (ctrl_rptb_paer),
        .rptb_brcr      (),
        .rptb_clr_en    (ctrl_rptb_clr_en),
        .brcr_ld_en     (ctrl_brcr_ld_en),
        .brcr_ld_data   (ctrl_brcr_ld_data),
        .stat_c         (addr_c),
        .stat_tc        (addr_tc),
        .stat_ov        (addr_ov),
        .stat_ovm       (st0_ovm),
        .stat_intm      (addr_st0[9]),
        .stat_sxm       (st1_sxm),
        .stat_hm        (addr_st1[6]),
        .stat_xf        (addr_st1[4]),
        .stat_cnf       (st1_cnf),
        .stat_pm        (st1_pm),
        .stat_dp        (addr_dp[15:7]),
        .stat_arp       (addr_arp),
        .stat_arb       (addr_arb),
        .stat_ndx       (addr_pmst[2]),
        .stat_braf      (addr_braf),
        .stat_ram       (pmst_ram),
        .stat_mpmc      (addr_pmst[3]),
        .stat_iptr      (addr_pmst[15:11]),
        .sp_i           (addr_sp),
        .ifr_i          (addr_ifr),
        .imr_i          (addr_imr),
        .dm_req         (ctrl_dm_req),
        .dm_wr          (ctrl_dm_wr),
        .dm_addr        (ctrl_dm_addr),
        .dm_wdata       (ctrl_dm_wdata),
        .pm_d_req       (ctrl_pm_d_req),
        .pm_d_wr        (ctrl_pm_d_wr),
        .pm_d_addr      (ctrl_pm_d_addr),
        .pm_d_wdata     (ctrl_pm_d_wdata),
        .tmr_safe_i     (mem_tmr_safe && (tick_burst_q == 16'd0)),
        .mtick_en       (ctrl_mtick_en),
        .mtick_n        (ctrl_mtick_n),
        .mmr_hit        (1'b0),
        .mmr_addr       (6'd0),
        .mmr_wr_hit     (mmr_wr_hit_mux),
        .io_req_c       (ctrl_io_req_c),
        .io_wr_c        (ctrl_io_wr_c),
        .io_port_c      (ctrl_io_port_c),
        .io_wdata_c     (ctrl_io_wdata_c),
        .io_rdata_c     (io_rdata),
        .io_ack_c       (ctrl_io_req_c && io_ack),
        .step_i         (step_i),
        .instr_done     (ctrl_instr_done),
        .cycles_o       (ctrl_cycles),
        .pc_o           (ctrl_pc),
        .op_o           (ctrl_op),
        .idle_o         (ctrl_idle),
        .bmar_o         (),
        .dbmr_o         (),
        .indx_o         (),
        .arcr_o         (),
        .acc_i          (alu_acc),
        .accb_i         (alu_accb),
        .preg_i         (alu_preg),
        .treg0_i        (alu_treg0),
        .treg1_i        (alu_treg1),
        .treg2_i        (alu_treg2),
        .pmst_i         (addr_pmst),
        .ar_arp_i       (addr_ar),
        .indx_i         (addr_indx),
        .arcr_i         (addr_arcr),
        .bmar_i         (addr_bmar),
        .dbmr_i         (addr_dbmr),
        .brcr_i         (addr_brcr),
        .pasr_i         (addr_pasr),
        .paer_i         (addr_paer),
        .bio_i          (bio_i),
        .ivec_ind_i     (ivec_ind_i),
        .io_ws_i        ({1'b0, mem_dm_io_ws}),
        .ndx_commit_o   (ctrl_ndx_commit_o),
        .irq_ack_o      (ctrl_irq_ack_o),
        .addr_wr_en_o   (ctrl_addr_wr_en_o),
        .addr_wr_sel_o  (ctrl_addr_wr_sel_o),
        .addr_wr_data_o (ctrl_addr_wr_data_o)
    );

    c5x_mem #(
        .EXT_PMEM       (EXT_PMEM)
    ) u_mem (
        .o_xm_rd_en     (xm_rd_en_o),
        .o_xm_raddr     (xm_raddr_o),
        .o_xm_wr_en     (xm_wr_en_o),
        .o_xm_waddr     (xm_waddr_o),
        .o_xm_wdata     (xm_wdata_o),
        .i_xm_rdata     (xm_rdata_i),
        .clk            (clk),
        .ce_i           (ce_i),
        .rst_n          (rst_n),
        .i_cnf          (st1_cnf),
        .i_ovly         (pmst_ovly),
        .i_ram          (pmst_ram),
        .i_xint_mode    (xint_mode),
        .i_tick         (mem_tick),
        .i_tick2        (mem_tick2),
        .i_ser_tick     (ser_tick),
        .i_ser_rx       (ser_rx),
        .i_replay_active (1'b0),
        .i_replay_lo    (16'd0),
        .i_replay_hi    (16'd0),
        .i_dm_req       (mux_dm_req),
        .i_dm_rd        (mux_dm_rd),
        .i_dm_dmov      (1'b0),
        .i_dm_dmov_src  (16'd0),
        .i_dm_addr      (mux_dm_addr),
        .i_dm_wdata     (mux_dm_wdata),
        .o_dm_rdata     (mem_dm_rdata),
        .o_dm_ack       (mem_dm_ack),
        .o_dm_io_ws     (mem_dm_io_ws),
        .o_dm_periph_ws (mem_dm_periph_ws),
        .i_pm_fetch_req (rst_n),
        .i_pm_fetch_addr (ctrl_pm_addr),
        .o_pm_fetch_data (mem_pm_fetch_data),
        .o_pm_fetch_ack  (),
        .i_pm_wr_req    (mux_pm_wr_req),
        .i_pm_wr_addr   (mux_pm_wr_addr),
        .i_pm_wr_data   (mux_pm_wr_data),
        .o_pm_wr_ack    (mem_pm_wr_ack),
        .i_ext_mmr_rdata (ext_mmr_rdata),
        .o_ext_mmr_rd   (),
        .o_ext_mmr_wr   (mem_ext_mmr_wr),
        .o_ext_mmr_addr (mem_ext_mmr_addr),
        .o_ext_mmr_wdata (mem_ext_mmr_wdata),
        .o_io_req       (mem_io_req),
        .o_io_rd        (mem_io_rd),
        .o_io_addr      (mem_io_addr),
        .o_io_wdata     (mem_io_wdata),
        .i_io_ack       (mem_io_req && io_ack),
        .i_io_rdata     (io_rdata),
        .o_tint_pulse   (mem_tint_pulse),
        .o_tmr_safe     (mem_tmr_safe),
        .o_rint_pulse   (mem_rint_pulse),
        .o_xint_pulse   (mem_xint_pulse),
        .o_timer_exp_cnt (mem_timer_exp_cnt),
        .o_dxr_wr       (mem_dxr_wr),
        .o_dxr_wdata    (mem_dxr_wdata),
        .o_pm_epoch_inc (),
        .o_replay_dirty_pulse (),
        .o_obs_greg     (obs_greg_o),
        .o_obs_drr      (obs_drr_o),
        .o_obs_dxr      (obs_dxr_o),
        .o_obs_spc      (obs_spc_o),
        .o_obs_tim      (obs_tim_o),
        .o_obs_prd      (obs_prd_o),
        .o_obs_tcr      (obs_tcr_o),
        .o_obs_pdwsr    (obs_pdwsr_o),
        .o_obs_iowsr    (obs_iowsr_o),
        .o_obs_cwsr     (obs_cwsr_o)
    );
    /* verilator lint_on UNUSEDSIGNAL */
    /* verilator lint_on PINCONNECTEMPTY */
endmodule
