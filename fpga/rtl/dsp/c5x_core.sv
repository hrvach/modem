/*
TMS320C5x DSP core top level, pipelined: the Courier modem DSP
(SV25 firmware).

Wires the real submodules: c5x_alu (CALU, shifter, multiplier),
c5x_addr (AR file, effective address, stack, status, RPT/RPTB,
IFR/IMR), c5x_decode and c5x_pipe_ctrl (instruction decode and
the pipelined control: four stages F/D/R/E, one instruction per
clock in steady state), and c5x_mem (PMEM/DMEM in M10K, MMRs,
timer, serial port, host IO).

Talks to: the host glue through the IO handshake (codec and 186
mailbox), the codec serial tick, the external interrupt lines, the
firmware loader, and the co-simulation harness through the debug
read port, the memory-write event outputs, and the PIPE_OBS
observation outputs (retire bundle, shadow registers, stall
counters).

Does not model: the 80C186 supervisor, the codec analogue front
end, or the telephone line. Those live outside this core; the host
glue provides them.

Reference model (the specification): the C core,
research_notes/courier-firmware/c-port/c/src/dsp/c5x_core.c.
Accuracy above all. Cyclone V, single clock, active-low
synchronous reset, no gated clocks, no Quartus primitives. The
M10K template lives inside c5x_mem (ramstyle attribute, simple
dual-port, registered read data, no reset on the array).

PIPELINE (converged plan, docs/pipeline-hazards.md):
  Four stages F/D/R/E. Fetch is 1-clock-latency pipelined
  (present addr cycle N, ack plus data cycle N+1). The R read
  presents its address in R and the data is valid combinationally
  in E from the memory's registered read port; E consumes it
  combinationally, it is NOT latched in R/E. Deferred reads
  (DRR, SPC, TIM, TCR, IFR, MMR 0x50+, host window) are
  serviced in E through the memory's deferred read port.
  The control unit is the single writer (E is the single writer
  with per-register enables); there is no multi-cycle TAIL
  writeback and no top-level write-port mux priority hazard.
  C and OV are owned by the ALU; the address unit only mirrors
  them, and the observation words take the OV/C bits from the
  ALU. cycles_o advances by the computed C-model charge at the
  retire edge only; the timer is the memory's wall-clock
  tick_timer, there is no model-cycle timer.

KNOWN-DIFF (multi-cycle RTL divergences, docs/cosim.md,
confirmed 2026-11-20 against the C model -- the pipeline must
NOT reproduce them; each is fixed here by wiring, not by
redesigning a submodule):
  (1) IFR never cleared on hardware interrupt entry: the old
      ctrl asserted irq_ack only inside FSM_TAIL after the
      pending flag was already consumed. The pipeline ctrl
      asserts irq_ack_o at the entry edge and this top routes
      it to the address unit's c5x_ctl_pkg::WR_IFR write (W1C).
  (2) BRAF never clears after an RPTB block: the old top left
      rptb_clr_en unconnected and tied i_braf_check to 0. The
      pipeline ctrl drives braf_check_o at the block-end
      retire and this top wires it to the address unit's
      i_braf_check with i_pc the post-execution PC, so the
      address unit's own handle_braf decrements BRCR or
      clears BRAF.
  (3) BRCR decrement dropped when the last RPTB block word is
      an ALU op: the old single write-port mux let the TAIL
      flag writeback win over brcr_ld_en. The pipeline does
      the decrement inside the address unit via handle_braf
      (see (2)), never through the write port, so no mux
      priority can drop it.
  (4) LT/LTA/LTD/LTP/LTS TREG0 load does nothing: the old
      ctrl consumed an unlatched d_w and the core left the
      ALU treg_data port unconnected. The pipeline E operand
      is combinational from the memory's registered R read
      data in the E clock, and this top wires the ctrl's
      alu_b16_o to the ALU i_b16 (the ALU loads TREG0 from
      i_b16).
  (5) Plain MPY/MPYU do not set PREG: same unlatched-d_w root
      cause as (4). The pipeline E operand feeds the ALU
      i_mpy_b through the ctrl's mpy_b_o, so the product is
      TREG0 times the live operand.
  (6) RETE/RETI shadow restore broken: the old core left the
      ALU acc_data/accb_data/preg_data/treg_data ports
      unconnected. The new ALU has no arbitrary data-load
      ports; the pipeline restore rebuilds the shadowed
      registers with ALU ops (MPYU plus LPH for PREG, LD_B32
      for ACC/ACCB, LT for TREG0, the treg12 port for
      TREG1/TREG2) driven by the ctrl, and the address unit
      restores ST0/ST1/PMST/ARCR/INDX through the write port.
      This top wires all of those paths.
  (7) MMR AR-file read returns 0: the old ext-MMR read mux
      had no AR0-AR7 case. This top returns ar[a-0x10] from
      the address unit's full AR-file vector o_ar_all.
  (8) External dm read returns a PMEM word: the C model reads
      c->pmem[a] for an external data address, and the old
      RTL returned the fetch's PMEM word instead of
      pmem[a]. The new memory gives the R read priority on
      the PMEM port and stalls the fetch (o_f_stall, which
      holds the fetch ack low); this top re-presents a
      stalled fetch through the ctrl's fetch_req_o (which
      stays high while a fetch is in flight and unacked),
      so the R read gets pmem[a] and the fetch is served
      after.
  (9) ADRK/SBRK not implemented at all: the old ctrl had empty
      stubs and the decoder maps both to ALU_NOP. The address
      unit already produces the ARK_INC/ARK_DEC descriptor
      for them (ark = opcode low byte); the pipeline ctrl
      drives i_d_ea_use for ADRK/SBRK so the descriptor is
      valid, and the E-commit applies it through desc_en.
      The decoder's ALU_NOP is correct (no ALU op needed).
  (10) Delay-slot / entry retire granularity is a harness
      expectation difference, not an RTL defect: the pipeline
      retires a delayed op as 3 pulses and an interrupt entry
      as a separate pulse (PIPE_OBS encodes this).
  (11) IO io_wdata validity: the old RTL's io_wdata was valid
      only on the first clock of io_req. The pipeline ctrl
      holds the E bundle (and therefore e_io_wdata_o) while
      the IO waits for ack, and this top forwards the
      memory's host IO word unchanged while io_req is high.

CPI gate (100k window): the classifier total is 297024, not
the audit C7 297029 (audit overcounts H2 map writes by 6 and
undercounts H1b by 1; classifier is the operative count).
*/

`default_nettype none

module c5x_core #(
    parameter logic [15:0] RESET_PC = 16'h8000,
    parameter bit          WALL_TIME = 1'b0,
    parameter bit          FETCH_CHAIN = 1'b0
) (
    input  logic         clk,
    input  logic         rst_n,

    /* Run and hold handshake, harness only. Tie to 1 in a
       free-running system. step_i is a fetch hold in the
       pipeline: low stops F from issuing; in-flight
       instructions complete and retire; no retire pulses once
       the pipeline drains. */
    input  logic         step_i,
    input  logic [1:0]   bp_en_i,       /* test breakpoints (tie to 0 in the modem) */
    input  logic [15:0]  bp_pc0_i,
    input  logic [15:0]  bp_pc1_i,

    /* External interrupt lines. Bits 5:3 are intentionally unused
       here: TINT, RINT and XINT are driven by the memory peripheral
       event pulses, not by the host. */
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [8:0]  irq_i,
    /* verilator lint_on UNUSEDSIGNAL */

    /* BIO pin, host driven. The control unit uses it in the branch
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
       data is ready, and holds it until io_req drops. The memory
       drives this port (the control unit's IN/OUT goes through
       the memory's E IO port); io_wdata is held stable while
       io_req is asserted (KNOWN-DIFF 11). */
    output logic         io_req,
    output logic         io_rd,
    output logic [15:0] io_port,
    output logic [15:0] io_wdata,
    input  logic [15:0] io_rdata,
    input  logic         io_ack,

    /* Firmware loader. The core is held in reset while loading.
       load_pmem selects the program-write channel (PMEM); clear
       selects the data channel (DMEM). Both go through the
       memory's program-write port, which routes by pm_ptr
       (CNF/RAM); a DMEM load to the OVLY SARAM range is not
       routed to DMEM by pm_ptr (it ignores OVLY) and is a
       known loader limitation. load_pmem is kept for interface
       compatibility; the routing ignores it. */
    input  logic         load_en,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic         load_pmem,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [15:0] load_addr,
    input  logic [15:0] load_data,

    /* Harness-only debug read. Assert dbg_en with dbg_addr;
       dbg_done pulses when dbg_rdata is valid. MMR and host
       window addresses read through the memory E port; data
       array addresses (DMEM/PMEM) read through the R port.
       Debug reads take clocks but no model cycles, so they do
       not advance the timer. Only use them when the core is
       halted or parked: a debug read clocks the design, and
       the pipeline runs ahead while it completes. A debug read
       of DRR (0x20) clears RRDY and RSRFALL; the harness reads
       DRR only at the end of a run, after its final SPC read. */
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

    /* Observation: architectural state after the last instr_done.
       pc_o / op_o are retire-anchored (the control unit's
       retire_pc_q / retire_op_q), not fetch-anchored. st0_o /
       st1_o take their OV/C bits from the ALU, which owns
       them; the address unit only mirrors them. */
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
    output logic [31:0]  mtime_o,
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
    output logic [15:0]  obs_cwsr_o,

    /* PIPE_OBS retire bundle (docs/cosim.md "RTL observation
       outputs"). retire_cycles_o holds the C-model charge of
       the retiring instruction until the next retire.
       retire_cnt_o counts retirements exactly (instr_done is a
       1-clock pulse that stays high at 1 retire per clock, so
       its rising edges cannot count retires); retire_tgl_o
       toggles at every retire edge. */
    output logic [31:0]  retire_cycles_o,
    output logic         retire_is_intr_o,
    output logic [63:0]  retire_cnt_o,
    output logic         retire_tgl_o,

    /* PIPE_OBS shadow observation outputs. Compared only at an
       interrupt-entry retire, against the C model's saved
       shadow as of the last retired instruction. */
    output logic [31:0]  obs_sh_acc_o,
    output logic [31:0]  obs_sh_accb_o,
    output logic [31:0]  obs_sh_preg_o,
    output logic [15:0]  obs_sh_treg0_o,
    output logic [15:0]  obs_sh_treg1_o,
    output logic [15:0]  obs_sh_treg2_o,
    output logic [15:0]  obs_sh_arcr_o,
    output logic [15:0]  obs_sh_indx_o,
    output logic [15:0]  obs_sh_st0_o,
    output logic [15:0]  obs_sh_st1_o,
    output logic [15:0]  obs_sh_pmst_o,

    /* PIPE_OBS stall counters. Each counts extra clocks beyond
       the base 1 per retire, per cause (docs/cosim.md). */
    output logic [63:0]  cnt_stall_branch_o,
    output logic [63:0]  cnt_stall_2word_o,
    output logic [63:0]  cnt_stall_pmem_op_o,
    output logic [63:0]  cnt_stall_rptb_setup_o,
    output logic [63:0]  cnt_stall_h1_o,
    output logic [63:0]  cnt_stall_h1a_o,
    output logic [63:0]  cnt_stall_h1b_o,
    output logic [63:0]  cnt_stall_h2_o,
    output logic [63:0]  cnt_stall_h3_o,
    output logic [63:0]  cnt_stall_int_entry_o,
    output logic [63:0]  cnt_stall_h10_o,
    output logic [63:0]  cnt_stall_rpt_replay_o,
    output logic [63:0]  cnt_stall_mac_replay_o,
    output logic [63:0]  cnt_stall_xc_o,
    output logic [63:0]  cnt_stall_io_wait_o
);
    /*
    Source citations for the localparams below. SST opcodes and the
    page-0 rule come from the C core. The MMR addresses come from
    the C core memory map. The write-port selects (WR_*) and flag
    selects (FLG_*) are the package's constants (c5x_ctl_pkg.sv);
    this top does not redeclare them (duplicates cause VARHIDDEN).
    The ALU micro-op is the package's c5x_alu_op_e enum member.
    All package types and constants are referenced fully
    qualified (c5x_ctl_pkg::...) -- this top does not import the
    package, because the package file is listed after this file
    in the harness Makefile's RTL_SRCS and an import would fail
    to resolve (PKGNODECL). The control unit's port list uses
    fully qualified package types for the same reason.
    */
    localparam logic [7:0] OP_SST0 = 8'h8E;
    localparam logic [7:0] OP_SST1 = 8'h8F;
    localparam logic [15:0] MMR_AR_FIRST = 16'h0010;
    localparam logic [15:0] MMR_AR_NEXT  = 16'h0018;
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
    The ALU owns C and OV; st0_o / st1_o below take those bits
    from the ALU, not from the address unit's mirror.
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
    logic        alu_tc_next;
    logic        alu_tc_wr;

    logic [15:0] addr_ea;
    logic [15:0] addr_pop_data;
    logic [2:0]  addr_sp;
    logic [15:0] addr_ar;
    logic [15:0] addr_ar_rd;
    logic [2:0]  addr_arp;
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
    logic [127:0] addr_ar_all;
    logic [127:0] addr_stack_all;
    logic [15:0] addr_arau_next;
    logic [2:0]  addr_d_desc_ar_id;
    logic [3:0]  addr_d_desc_mode;
    logic        addr_d_desc_arp_sw;
    logic [2:0]  addr_d_desc_new_arp;
    logic [7:0]  addr_d_desc_ark;
    logic        addr_d_desc_valid;
    logic        addr_d_ea_badop;
    logic        addr_d_desc_norm_cond;
    logic        addr_d_src_ar_use;
    logic [2:0]  addr_d_src_ar_id;
    logic        addr_d_src_indx_use;
    logic        addr_d_src_dp_use;
    logic        addr_d_src_arp_use;
    logic        addr_d_src_circ_use;
    logic        addr_d_src_acc_use;
    logic        addr_d_src_bmar_use;
    logic        addr_d_wrt_ar_valid;
    logic [2:0]  addr_d_wrt_ar_id;
    logic        addr_d_wrt_arp_sw;
    logic [2:0]  addr_d_wrt_arp_id;
    logic        addr_d_wrt_ar0_mirror;

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

    /* Control unit outputs (c5x_pipe_ctrl). */
    logic        ctrl_flush_fdr;
    logic        ctrl_fd_load;
    logic        ctrl_dr_load;
    logic        ctrl_re_load;
    logic        ctrl_e_consume;
    c5x_ctl_pkg::c5x_pipe_t   ctrl_dr_o;
    c5x_ctl_pkg::c5x_pipe_t   ctrl_re_o;
    logic        ctrl_fetch_req;
    logic [15:0] ctrl_fetch_addr;
    logic [15:0] ctrl_fetch_ldpc;
    logic        ctrl_fetch_is_word2;
    logic        ctrl_r_req;
    logic [15:0] ctrl_r_addr;
    logic        ctrl_r_is_prog;
    logic [2:0]  ctrl_ar_rd_sel;
    logic [15:0] ctrl_arau_ar;
    logic [2:0]  ctrl_arau_ar_id;
    logic [3:0]  ctrl_arau_mode;
    logic [7:0]  ctrl_arau_ark;
    logic        ctrl_d_ea_use;
    logic        ctrl_d_pfc_acc;
    logic        ctrl_d_pfc_bmar;
    logic        ctrl_alu_exec;
    logic [6:0]  ctrl_alu_op;
    logic [31:0] ctrl_alu_b32;
    logic [15:0] ctrl_alu_b16;
    logic [15:0] ctrl_alu_mpy_a;
    logic [15:0] ctrl_alu_mpy_b;
    logic        ctrl_alu_mpy_unsigned;
    logic [3:0]  ctrl_alu_shift;
    logic        ctrl_alu_s16;
    logic        ctrl_alu_ld_acc;
    logic        ctrl_alu_ld_accb;
    logic        ctrl_alu_ld_preg;
    logic        ctrl_alu_ld_treg0;
    logic        ctrl_alu_flag_c_we;
    logic        ctrl_alu_flag_c_in;
    logic        ctrl_alu_flag_ov_we;
    logic        ctrl_alu_flag_ov_in;
    logic        ctrl_alu_treg12_wr_en;
    logic        ctrl_alu_treg12_sel;
    logic [15:0] ctrl_alu_treg12_data;
    logic        ctrl_ar_wr_en;
    logic [2:0]  ctrl_ar_wr_sel;
    logic [15:0] ctrl_ar_wr_data;
    logic        ctrl_st0_ld_en;
    logic [15:0] ctrl_st0_ld_data;
    logic        ctrl_st1_ld_en;
    logic [15:0] ctrl_st1_ld_data;
    logic        ctrl_pmst_ld_en;
    logic [15:0] ctrl_pmst_ld_data;
    logic        ctrl_rptc_ld_en;
    logic [15:0] ctrl_rptc_ld_data;
    logic        ctrl_brcr_ld_en;
    /* The write port takes a 16-bit data; BRCR is 32-bit in the
       address unit, and the control unit's brcr_ld_data_o carries
       the full value. Only the low 16 bits ride the write port;
       the address unit's c5x_ctl_pkg::WR_BRCR handler extends them. */
    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0] ctrl_brcr_ld_data;
    /* verilator lint_on UNUSEDSIGNAL */
    logic        ctrl_addr_wr_en;
    logic [5:0]  ctrl_addr_wr_sel;
    logic [15:0] ctrl_addr_wr_data;
    logic        ctrl_st_bit_en;
    logic [4:0]  ctrl_st_bit_sel;
    logic        ctrl_st_bit_val;
    logic        ctrl_desc_en;
    logic [2:0]  ctrl_desc_ar_id;
    logic [3:0]  ctrl_desc_mode;
    logic        ctrl_desc_arp_sw;
    logic [2:0]  ctrl_desc_new_arp;
    logic [7:0]  ctrl_desc_ark;
    logic        ctrl_desc_hold;
    logic        ctrl_ndx_commit;
    logic        ctrl_push_en;
    logic [15:0] ctrl_push_data;
    logic        ctrl_pop_en;
    logic        ctrl_rptc_dec;
    logic        ctrl_rptb_set;
    logic [15:0] ctrl_rptb_pasr;
    logic [15:0] ctrl_rptb_paer;
    logic        ctrl_braf_check;
    logic [15:0] ctrl_braf_pc;
    logic [8:0]  ctrl_irq_ack;
    logic        ctrl_e_wr;
    logic [15:0] ctrl_e_wr_addr;
    logic [15:0] ctrl_e_wr_data;
    logic        ctrl_e_dmov;
    logic [15:0] ctrl_e_dmov_src;
    logic        ctrl_e_wr_flush_en;
    logic        ctrl_e_rd_req;
    logic [15:0] ctrl_e_rd_addr;
    logic        ctrl_e_io_req;
    logic        ctrl_e_io_rd;
    logic [15:0] ctrl_e_io_addr;
    logic [15:0] ctrl_e_io_wdata;
    logic        ctrl_pm_wr_req;
    logic [15:0] ctrl_pm_wr_addr;
    logic [15:0] ctrl_pm_wr_data;
    logic        ctrl_pm_wr_is_e;
    logic        ctrl_pm_wr_flush_en;
    logic        ctrl_instr_done;
    logic [31:0] ctrl_retire_cycles;
    logic        ctrl_retire_is_intr;
    logic [63:0] ctrl_retire_cnt;
    logic        ctrl_retire_tgl;
    logic [15:0] ctrl_retire_pc;
    logic [15:0] ctrl_retire_op;
    logic [63:0] ctrl_cycles;
    logic        ctrl_idle;
    logic        ctrl_idle2;
    logic        ctrl_desc_keep_arb;
    logic        ctrl_r2_req;
    logic [15:0] ctrl_r2_addr, mem_r2_data;
    logic        ctrl_model_tick;
    logic        ctrl_halted;
    logic [31:0] ctrl_obs_sh_acc;
    logic [31:0] ctrl_obs_sh_accb;
    logic [31:0] ctrl_obs_sh_preg;
    logic [15:0] ctrl_obs_sh_treg0;
    logic [15:0] ctrl_obs_sh_treg1;
    logic [15:0] ctrl_obs_sh_treg2;
    logic [15:0] ctrl_obs_sh_arcr;
    logic [15:0] ctrl_obs_sh_indx;
    logic [15:0] ctrl_obs_sh_st0;
    logic [15:0] ctrl_obs_sh_st1;
    logic [15:0] ctrl_obs_sh_pmst;
    logic [63:0] ctrl_cnt_stall_branch;
    logic [63:0] ctrl_cnt_stall_2word;
    logic [63:0] ctrl_cnt_stall_pmem_op;
    logic [63:0] ctrl_cnt_stall_rptb_setup;
    logic [63:0] ctrl_cnt_stall_h1;
    logic [63:0] ctrl_cnt_stall_h1a;
    logic [63:0] ctrl_cnt_stall_h1b;
    logic [63:0] ctrl_cnt_stall_h2;
    logic [63:0] ctrl_cnt_stall_h3;
    logic [63:0] ctrl_cnt_stall_int_entry;
    logic [63:0] ctrl_cnt_stall_h10;
    logic [63:0] ctrl_cnt_stall_rpt_replay;
    logic [63:0] ctrl_cnt_stall_mac_replay;
    logic [63:0] ctrl_cnt_stall_xc;
    logic [63:0] ctrl_cnt_stall_io_wait;

    /* Memory outputs. */
    logic [15:0] mem_pm_fetch_data;
    logic        mem_pm_fetch_ack;
    logic        mem_pm_wr_flush;
    logic [15:0] mem_r_data;
    logic        mem_r_stall;
    logic [15:0] mem_e_rdata;
    logic        mem_e_stall;
    logic        mem_e_io_done;
    logic [2:0]  mem_e_io_ws;
    logic        mem_ext_mmr_wr;
    logic [15:0] mem_ext_mmr_addr;
    logic [15:0] mem_ext_mmr_w_addr;   /* the E write address only: the write decode does not wait for the R / E-read address select (timing) */
    logic [15:0] mem_ext_mmr_wdata;
    logic        mem_io_req;
    logic        mem_io_rd;
    logic [15:0] mem_io_addr;
    logic [15:0] mem_io_wdata;
    logic        mem_tint_pulse;
    logic        mem_tint_will_raise;
    logic        mem_rint_pulse;
    logic        mem_xint_pulse;
    logic [63:0] mem_timer_exp_cnt;
    logic        mem_dxr_wr;
    logic [15:0] mem_dxr_wdata;

    /* Pipeline registers (top-owned). The control unit computes
       the next D/R bundle (dr_o) and passes the R/E bundle
       through (re_o = dr_i); the top registers them. The fetch
       data is routed by the latched kind: a normal fetch loads
       F/D word, a word2 fetch loads F/D word2, a pma fetch
       (loop pm read) is not latched into F/D -- the control
       unit consumes it combinationally as loop_pma_w. */
    c5x_ctl_pkg::c5x_fd_t     fd_q;
    c5x_ctl_pkg::c5x_pipe_t   dr_q;
    c5x_ctl_pkg::c5x_pipe_t   re_q;

    /* Decode / descriptor bundles assembled for the control unit. */
    c5x_ctl_pkg::c5x_dec_t    dec_struct;
    c5x_ctl_pkg::c5x_ar_desc_t desc_struct;

    always_comb begin
        dec_struct.alu_op    = c5x_ctl_pkg::c5x_alu_op_e'(dec_alu_op);
        dec_struct.words     = dec_words;
        dec_struct.cycles    = dec_cycles;
        dec_struct.ea_mode   = dec_ea_mode;
        dec_struct.is_branch = dec_is_branch;
        dec_struct.is_call   = dec_is_call;
        dec_struct.is_ret    = dec_is_ret;
        dec_struct.is_rpt    = dec_is_rpt;
        dec_struct.is_rptb   = dec_is_rptb;
        dec_struct.is_idle   = dec_is_idle;
        dec_struct.is_io     = dec_is_io;
        dec_struct.is_mem_wr = dec_is_mem_wr;
        dec_struct.is_pm_wr  = dec_is_pm_wr;
        dec_struct.badop     = dec_badop || addr_d_ea_badop;   /* + the reserved indirect modifier (C effective_address) */
        desc_struct.ar_id    = addr_d_desc_ar_id;
        desc_struct.mode     = addr_d_desc_mode;
        desc_struct.arp_sw   = addr_d_desc_arp_sw;
        desc_struct.new_arp  = addr_d_desc_new_arp;
        desc_struct.ark      = addr_d_desc_ark;
        desc_struct.norm_cond = addr_d_desc_norm_cond;
        desc_struct.valid    = addr_d_desc_valid;
    end

    /*
    Pipeline registers. On a flush (branch, interrupt entry, or
    a PMEM-write flush) the bundles are cleared, not merely not
    loaded, so no stale instruction can retire after the flush.
    The F/D word2 is loaded only by a word2 fetch; a first-word
    fetch replaces the word and clears word2_valid.
    */
    /*
    Pipeline registers.  Each stage is consumed when it advances:
    F/D is consumed when D loads (dr_load) unless a first-word
    fetch overwrites it the same clock; D/R is consumed when R
    loads (re_load) unless D loads a new bundle the same clock;
    R/E is consumed at the retire edge (e_consume) unless R loads
    a new bundle the same clock.  Without the consume clears a
    bundle would stay valid after advancing and retire (or be
    hazard-counted) twice.  A mechanism-(b) replay bundle is NOT
    consumed until its last iteration (e_consume is low until
    replay_cnt <= 1), so it stays in R/E across iterations.
    */
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            fd_q <= '0;
            dr_q <= '0;
            re_q <= '0;
        end else if (ctrl_flush_fdr) begin
            fd_q <= '0;
            dr_q <= '0;
            re_q <= '0;
        end else begin
            if (ctrl_fd_load) begin
                if (ctrl_fetch_is_word2) begin
                    fd_q.word2 <= mem_pm_fetch_data;
                    fd_q.word2_valid <= 1'b1;
                end else begin
                    fd_q.pc <= ctrl_fetch_ldpc;
                    fd_q.word <= mem_pm_fetch_data;
                    fd_q.word2 <= 16'd0;
                    fd_q.word2_valid <= 1'b0;
                    fd_q.first_word <= 1'b1;
                    fd_q.valid <= 1'b1;
                end
            end else if (ctrl_dr_load) begin
                fd_q.valid <= 1'b0;
            end
            if (ctrl_dr_load)
                dr_q <= ctrl_dr_o;
            else if (ctrl_re_load)
                dr_q.valid <= 1'b0;
            if (ctrl_re_load)
                re_q <= ctrl_re_o;
            else if (ctrl_e_consume)
                re_q.valid <= 1'b0;
        end
    end

    /*
    External-MMR read mux, combinational from the memory address
    output. The memory samples it at the data-accept edge, so it
    must be combinational. AR0 to AR7 return ar[a-0x10] from the
    address unit's full AR-file vector (KNOWN-DIFF 7: the old
    mux returned zero for ARs). The selects numerically equal
    the MMR addresses (c5x_addr.sv write-port selects).
    */
    function automatic [15:0] ext_mmr_rd(input [15:0] ea);
        logic [15:0] r;
        case (ea)
            MMR_IMR:   r = addr_imr;
            MMR_IFR:   r = addr_ifr;
            MMR_PMST:  r = addr_pmst;
            MMR_RPTC:  r = addr_rptc[15:0];
            MMR_BRCR:  r = addr_brcr[15:0];
            MMR_PASR:  r = addr_pasr;
            MMR_PAER:  r = addr_paer;
            MMR_TREG0: r = alu_treg0;
            MMR_TREG1: r = alu_treg1;
            MMR_TREG2: r = alu_treg2;
            MMR_DBMR:  r = addr_dbmr;
            MMR_INDX:  r = addr_indx;
            MMR_ARCR:  r = addr_arcr;
            MMR_CBSR1: r = addr_cbsr1;
            MMR_CBER1: r = addr_cber1;
            MMR_CBSR2: r = addr_cbsr2;
            MMR_CBER2: r = addr_cber2;
            MMR_CBCR:  r = {8'd0, addr_cbcr};
            MMR_BMAR:  r = addr_bmar;
            default: begin
                if ((ea >= MMR_AR_FIRST) &&
                    (ea < MMR_AR_NEXT))
                    r = addr_ar_all[{ea[2:0],
                                                 4'd0} +: 16];
                else
                    r = 16'd0;
            end
        endcase
        ext_mmr_rd = r;
    endfunction
    /* two copies of the read mux: the shared-address one (E write / E read / R read select) for the R read, and one keyed directly by the E read address for the deferred E
       read, so the E operand path does not wait for the E-write decode and the R-address select that steer the shared address (timing) */
    logic [15:0] ext_mmr_rdata, ext_mmr_rdata_e;
    logic [15:0] mem_ext_mmr_e_addr;
    assign ext_mmr_rdata   = ext_mmr_rd(mem_ext_mmr_addr);
    assign ext_mmr_rdata_e = ext_mmr_rd(mem_ext_mmr_e_addr);

    /*
    External-MMR write decode. The memory pulses mem_ext_mmr_wr
    for one cycle when it accepts a data-memory write to an
    external MMR; the address and data ride the same cycle.
    TREG0 goes through the ALU override below; TREG1/TREG2 go
    through the ALU i_treg12 port (KNOWN-DIFF 6: the old core
    dropped them). The selects numerically equal the MMR
    addresses, but the table states the mapping explicitly so
    a renumbering in the address unit cannot silently misroute
    a write. ext_mmr_wr_valid is low for any address outside
    the decode; the write-port mux requires it, so an
    undecoded address is dropped rather than written to
    select 0.
    */
    logic        ext_mmr_treg0_wr;
    logic        ext_mmr_treg12_wr;
    logic [5:0]  ext_mmr_wr_sel;
    logic        ext_mmr_wr_valid;

    assign ext_mmr_treg0_wr  = mem_ext_mmr_wr &&
                               (mem_ext_mmr_w_addr == MMR_TREG0);
    assign ext_mmr_treg12_wr = mem_ext_mmr_wr &&
                               ((mem_ext_mmr_w_addr == MMR_TREG1) ||
                                (mem_ext_mmr_w_addr == MMR_TREG2));
    assign ext_mmr_wr_valid  = (ext_mmr_wr_sel != 6'd0);
    always_comb begin
        case (mem_ext_mmr_w_addr)
            MMR_IMR:   ext_mmr_wr_sel = c5x_ctl_pkg::WR_IMR;
            MMR_IFR:   ext_mmr_wr_sel = c5x_ctl_pkg::WR_IFR;
            MMR_PMST:  ext_mmr_wr_sel = c5x_ctl_pkg::WR_PMST;
            MMR_RPTC:  ext_mmr_wr_sel = c5x_ctl_pkg::WR_RPTC;
            MMR_BRCR:  ext_mmr_wr_sel = c5x_ctl_pkg::WR_BRCR;
            MMR_PASR:  ext_mmr_wr_sel = c5x_ctl_pkg::WR_PASR;
            MMR_PAER:  ext_mmr_wr_sel = c5x_ctl_pkg::WR_PAER;
            MMR_DBMR:  ext_mmr_wr_sel = c5x_ctl_pkg::WR_DBMR;
            MMR_INDX:  ext_mmr_wr_sel = c5x_ctl_pkg::WR_INDX;
            MMR_ARCR:  ext_mmr_wr_sel = c5x_ctl_pkg::WR_ARCR;
            MMR_CBSR1: ext_mmr_wr_sel = c5x_ctl_pkg::WR_CBSR1;
            MMR_CBER1: ext_mmr_wr_sel = c5x_ctl_pkg::WR_CBER1;
            MMR_CBSR2: ext_mmr_wr_sel = c5x_ctl_pkg::WR_CBSR2;
            MMR_CBER2: ext_mmr_wr_sel = c5x_ctl_pkg::WR_CBER2;
            MMR_CBCR:  ext_mmr_wr_sel = c5x_ctl_pkg::WR_CBCR;
            MMR_BMAR:  ext_mmr_wr_sel = c5x_ctl_pkg::WR_BMAR;
            default: begin
                if ((mem_ext_mmr_w_addr >= MMR_AR_FIRST) &&
                    (mem_ext_mmr_w_addr < MMR_AR_NEXT))
                    ext_mmr_wr_sel = c5x_ctl_pkg::WR_AR0 + {3'd0, mem_ext_mmr_w_addr[2:0]};
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
    unit never executes the ALU in that cycle for a plain
    store (its ALU enable is 0; the store data is already the
    E operand), so forcing exec on changes nothing else:
    ACC/PREG hold because their load strobes are 0, and OP_LT
    writes no flags. A loop SMMR/LMMR to TREG0 likewise does
    not use the ALU, so the override is safe there too.
    TREG1/TREG2 use the ALU i_treg12 port (below), not this
    override.
    */
    logic [6:0]  alu_op_mux;
    logic [15:0] alu_b16_mux;
    logic        alu_exec_mux;
    logic        alu_ld_treg0_mux;
    logic        alu_trm_mux;
    logic        alu_treg12_wr_en_mux;
    logic        alu_treg12_sel_mux;
    logic [15:0] alu_treg12_data_mux;

    assign alu_op_mux        = ext_mmr_treg0_wr ? 7'(c5x_ctl_pkg::ALU_LT) : ctrl_alu_op;
    assign alu_b16_mux       = ext_mmr_treg0_wr ? mem_ext_mmr_wdata : ctrl_alu_b16;
    assign alu_exec_mux      = ext_mmr_treg0_wr || ctrl_alu_exec;
    assign alu_ld_treg0_mux  = ext_mmr_treg0_wr || ctrl_alu_ld_treg0;
    assign alu_trm_mux       = ext_mmr_treg0_wr || pmst_trm;
    /* TREG1/TREG2: the external-MMR write wins over the control
       unit's restore sequencer (the two cannot coincide -- the
       restore is a RETI/RETE in E, which performs no data-memory
       write -- so the priority is a safety net, not a rule). */
    assign alu_treg12_wr_en_mux = ext_mmr_treg12_wr || ctrl_alu_treg12_wr_en;
    assign alu_treg12_sel_mux   = ext_mmr_treg12_wr ?
                                  (mem_ext_mmr_w_addr == MMR_TREG2) :
                                  ctrl_alu_treg12_sel;
    assign alu_treg12_data_mux  = ext_mmr_treg12_wr ? mem_ext_mmr_wdata :
                                                       ctrl_alu_treg12_data;

    /*
    IRQ-set composition: external lines plus memory peripheral
    pulses. C interrupt bits: 0 INT1, 1 INT2, 2 INT3, 3 TINT,
    4 RINT, 5 XINT, 6 TRNT, 7 TXNT, 8 INT4. irq_i bits 5:3 are
    OR-ed with the memory's pulses (the top ties them to 0; the C model lets a
    test raise any IFR bit).
    */
    logic [15:0] irq_set;
    assign irq_set = {7'd0, irq_i[8:6], mem_xint_pulse | irq_i[5], mem_rint_pulse | irq_i[4],
                      mem_tint_pulse | irq_i[3], irq_i[2:0]};

    /*
    Address-unit write-port adapter. The control unit is the
    single writer (E is the single writer with per-register
    enables); this adapter only merges its strobes with the
    external-MMR write pulse and the interrupt acknowledge.
    Priority order, highest first: external-MMR write (a
    one-cycle pulse from the memory that must not be dropped),
    the control unit's generic write port (LST ST0L/ST1L and
    the RETI/RETE restore), ST0 load, ST1 load, PMST load, AR
    write, RPTC load, BRCR load, interrupt acknowledge
    (KNOWN-DIFF 1: the entry's irq_ack reaches c5x_ctl_pkg::WR_IFR here;
    at the entry edge no other strobe is active, so the ack
    cannot be dropped by priority). The control unit never
    asserts two conflicting strobes in one cycle; the priority
    is a safety net, not a design rule. The RPTB BRCR
    decrement does NOT go through this mux (KNOWN-DIFF 3):
    it runs inside the address unit via handle_braf on
    i_braf_check.
    */
    logic        wr_port_en;
    logic [5:0]  wr_port_sel;
    logic [15:0] wr_port_data;
    always_comb begin
        wr_port_en   = 1'b0;
        wr_port_sel  = 6'd0;
        wr_port_data = 16'd0;
        if (mem_ext_mmr_wr && !ext_mmr_treg0_wr && !ext_mmr_treg12_wr &&
            ext_mmr_wr_valid) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = ext_mmr_wr_sel;
            wr_port_data = mem_ext_mmr_wdata;
        end else if (ctrl_addr_wr_en) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = ctrl_addr_wr_sel;
            wr_port_data = ctrl_addr_wr_data;
        end else if (ctrl_st0_ld_en) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = c5x_ctl_pkg::WR_ST0;
            wr_port_data = ctrl_st0_ld_data;
        end else if (ctrl_st1_ld_en) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = c5x_ctl_pkg::WR_ST1;
            wr_port_data = ctrl_st1_ld_data;
        end else if (ctrl_pmst_ld_en) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = c5x_ctl_pkg::WR_PMST;
            wr_port_data = ctrl_pmst_ld_data;
        end else if (ctrl_ar_wr_en) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = c5x_ctl_pkg::WR_AR0 + {3'd0, ctrl_ar_wr_sel};
            wr_port_data = ctrl_ar_wr_data;
        end else if (ctrl_rptc_ld_en) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = c5x_ctl_pkg::WR_RPTC;
            wr_port_data = ctrl_rptc_ld_data;
        end else if (ctrl_brcr_ld_en) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = c5x_ctl_pkg::WR_BRCR;
            wr_port_data = ctrl_brcr_ld_data[15:0];
        end else if (ctrl_irq_ack != 9'd0) begin
            wr_port_en   = 1'b1;
            wr_port_sel  = c5x_ctl_pkg::WR_IFR;
            wr_port_data = {7'd0, ctrl_irq_ack};
        end
    end

    /*
    Address-unit flag-port adapter. The control unit writes
    single status bits through st_bit (SETC/CLRC and friends,
    the taken-branch OV clear, the RETE INTM clear, the
    interrupt-entry INTM set). The ALU's NORM TC update rides
    the same port: the control unit never asserts st_bit in
    the same cycle as a NORM (NORM is not a flag op), so the
    two cannot collide; the control unit's st_bit has priority
    as a safety net. There is no TAIL flag writeback in the
    pipeline: C and OV are owned by the ALU and are never
    written back through this port.
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
        end else if (alu_tc_wr) begin
            flag_port_we  = 1'b1;
            flag_port_sel = c5x_ctl_pkg::FLG_TC;
            flag_port_in  = alu_tc_next;
        end
    end
    /*
    Program-write channel mux: loader, then the control unit's
    The loader and the control unit share the memory's
    program-write port for PMEM loads (load_pmem = 1); the
    memory routes by pm_ptr (CNF/RAM).  A DMEM load
    (load_pmem = 0) cannot use that port: pm_is_dmem_f maps
    only the CNF B0 and RAM SARAM program ranges to DMEM, so
    a plain data address (e.g. 0x60) would land in PMEM.
    DMEM loads therefore go through the memory's E data-write
    port, whose dm_route_f maps a plain data address to DMEM
    (ROUTE_INTERNAL).  is_e distinguishes the control unit's
    write (which participates in the PMEM-write flush and the
    replay invalidation) from the loader's.
    */
    logic        mux_pm_wr_req;
    logic [15:0] mux_pm_wr_addr;
    logic [15:0] mux_pm_wr_data;
    logic        mux_pm_wr_is_e;
    logic        mux_pm_wr_flush_en;
    always_comb begin
        if (load_en && load_pmem) begin
            mux_pm_wr_req      = 1'b1;
            mux_pm_wr_addr     = load_addr;
            mux_pm_wr_data     = load_data;
            mux_pm_wr_is_e     = 1'b0;
            mux_pm_wr_flush_en = 1'b0;
        end else if (ctrl_pm_wr_req) begin
            mux_pm_wr_req      = 1'b1;
            mux_pm_wr_addr     = ctrl_pm_wr_addr;
            mux_pm_wr_data     = ctrl_pm_wr_data;
            mux_pm_wr_is_e     = ctrl_pm_wr_is_e;
            mux_pm_wr_flush_en = ctrl_pm_wr_flush_en;
        end else begin
            mux_pm_wr_req      = 1'b0;
            mux_pm_wr_addr     = 16'd0;
            mux_pm_wr_data     = 16'd0;
            mux_pm_wr_is_e     = 1'b0;
            mux_pm_wr_flush_en = 1'b0;
        end
    end

    /*
    DMEM loader (load_pmem = 0): the loader drives the memory's
    E data-write port while the core is held in reset (the
    control unit's e_wr_o is 0 in reset, so there is no
    contention).  dm_route_f maps a plain data address to
    DMEM; the write is accepted in the presented clock and has
    no side effect on the flush (flush_en = 0) or the DMOV
    gate (dmov = 0).
    */
    logic        mux_e_wr;
    logic [15:0] mux_e_wr_addr;
    logic [15:0] mux_e_wr_data;
    logic        mux_e_dmov;
    logic [15:0] mux_e_dmov_src;
    logic        mux_e_wr_flush_en;
    always_comb begin
        if (load_en && !load_pmem) begin
            mux_e_wr          = 1'b1;
            mux_e_wr_addr     = load_addr;
            mux_e_wr_data     = load_data;
            mux_e_dmov        = 1'b0;
            mux_e_dmov_src    = 16'd0;
            mux_e_wr_flush_en = 1'b0;
        end else begin
            mux_e_wr          = ctrl_e_wr;
            mux_e_wr_addr     = ctrl_e_wr_addr;
            mux_e_wr_data     = ctrl_e_wr_data;
            mux_e_dmov        = ctrl_e_dmov;
            mux_e_dmov_src    = ctrl_e_dmov_src;
            mux_e_wr_flush_en = ctrl_e_wr_flush_en;
        end
    end

    /*
    Debug sequencer: one memory read per dbg_en assertion.
    MMR and host-window addresses read through the memory E
    port (combinational data, valid when o_e_stall is low);
    data-array addresses read through the R port (registered
    data, valid the clock after the request is accepted).
    The E port and the R port are both muxed: the debug
    sequencer wins while it is active, the control unit
    otherwise. Only use debug reads when the core is halted
    or parked -- the control unit drives neither port then,
    so the mux cannot steal a live read. DEBUG_IDLE waits for
    dbg_en, REQ_E / REQ_R hold the read request until it is
    accepted, CAP_R waits one clock for the registered R
    data, DONE waits for dbg_en to drop. The request is
    level-held, so a cycle where the memory is busy simply
    delays the accept; the sequencer never loses the request.
    */
    typedef enum logic [2:0] {
        DEBUG_IDLE,
        DEBUG_REQ_E,
        DEBUG_REQ_R,
        DEBUG_CAP_R,
        DEBUG_DONE
    } debug_state_t;
    debug_state_t debug_state_q;
    logic [15:0] debug_addr_q;
    logic        debug_busy_q;
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

    logic debug_e_active;
    logic debug_r_active;
    assign debug_e_active = (debug_state_q == DEBUG_REQ_E);
    assign debug_r_active = (debug_state_q == DEBUG_REQ_R);
    assign dbg_rdata = debug_rdata_q;
    assign dbg_done  = debug_done_q;
    always_ff @(posedge clk) begin
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
                        if ((dbg_addr < MMR_END) ||
                            ((dbg_addr >= IO_HOST_LO) &&
                             (dbg_addr <= IO_HOST_HI)))
                            debug_state_q <= DEBUG_REQ_E;
                        else
                            debug_state_q <= DEBUG_REQ_R;
                    end
                end
                DEBUG_REQ_E: begin
                    if (!mem_e_stall) begin
                        debug_rdata_q <= mem_e_rdata;
                        case (debug_addr_q)
                            MMR_GREG:  debug_greg_q  <= mem_e_rdata;
                            MMR_DRR:   debug_drr_q   <= mem_e_rdata;
                            MMR_DXR:   debug_dxr_q   <= mem_e_rdata;
                            MMR_SPC:   debug_spc_q   <= mem_e_rdata;
                            MMR_TIM:   debug_tim_q   <= mem_e_rdata;
                            MMR_PRD:   debug_prd_q   <= mem_e_rdata;
                            MMR_TCR:   debug_tcr_q   <= mem_e_rdata;
                            MMR_PDWSR: debug_pdwsr_q <= mem_e_rdata;
                            MMR_IOWSR: debug_iowsr_q <= mem_e_rdata;
                            MMR_CWSR:  debug_cwsr_q  <= mem_e_rdata;
                            default: begin end
                        endcase
                        debug_done_q  <= 1'b1;
                        debug_state_q <= DEBUG_DONE;
                    end
                end
                DEBUG_REQ_R: begin
                    if (!mem_r_stall)
                        debug_state_q <= DEBUG_CAP_R;
                end
                DEBUG_CAP_R: begin
                    debug_rdata_q <= mem_r_data;
                    debug_done_q  <= 1'b1;
                    debug_state_q <= DEBUG_DONE;
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

    /*
    Host IO: the memory drives the host port. The control
    unit's IN/OUT goes through the memory's E IO port, and
    the memory's own host-window IO shares the same port, so
    there is no top-level mux -- the memory arbitrates. The
    host acknowledge and read data fan into the memory, which
    completes the control unit's IO (o_e_io_done) and the
    host-window IO. io_wdata is the memory's word, held
    stable while io_req is asserted (KNOWN-DIFF 11).
    */
    assign io_req   = mem_io_req;
    assign io_rd    = mem_io_rd;
    assign io_port  = mem_io_addr;
    assign io_wdata = mem_io_wdata;
    assign dxr_wr   = mem_dxr_wr;
    assign dxr_wdata = mem_dxr_wdata;

    /*
    Memory-write snoop. The control unit's E data write is
    accepted in the cycle it is presented; the program write
    is acknowledged one cycle later (o_pm_wr_ack). The
    registered E request at the next edge is the one being
    accepted. Route classification replicates the memory
    route functions, observation only, not functional logic.
    A data write below 0x60 targets an MMR and has no shadow;
    a write to the host window has no shadow; anything else
    internal is DMEM and anything else external is PMEM.
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
    /* a PROGRAM-space write lands in data memory through the B0 window (CNF=1, program 0xFE00..) or the SARAM overlay (RAM=1, program 0x2000..0x23FF -> data 0x0800..0x0BFF) */
    function automatic logic snoop_pm_is_dmem(input logic [15:0] a);
        begin
            snoop_pm_is_dmem = (st1_cnf && (a >= 16'hFE00)) ||
                (pmst_ram && (a >= 16'h2000) && (a < 16'h2400));
        end
    endfunction
    function automatic logic [15:0] snoop_pm_to_dmem(input logic [15:0] a);
        begin
            snoop_pm_to_dmem = (st1_cnf && (a >= 16'hFE00)) ? (a - 16'hFE00 + 16'h0100) : (a - 16'h2000 + 16'h0800);
        end
    endfunction

    logic        snoop_pulse_q;
    logic        snoop_pmem_q;
    logic [15:0] snoop_wr_addr_q;
    logic [15:0] snoop_wr_data_q;

    assign mem_wr_pulse = snoop_pulse_q;
    assign mem_wr_pmem  = snoop_pmem_q;
    assign mem_wr_addr  = snoop_wr_addr_q;
    assign mem_wr_data  = snoop_wr_data_q;

    /*
    Memory-write snoop. The control unit's E data write is
    presented in the E clock and retires at the edge ending that
    clock, so the snoop pulse is registered AT that edge (one
    stage, not two): mem_wr_pulse is high during the retire
    clock, when the harness samples state after the retire.
    The old two-stage snoop pulsed one clock AFTER the retire,
    so the harness compared stale shadow memory.
    */
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            snoop_pulse_q     <= 1'b0;
            snoop_pmem_q      <= 1'b0;
            snoop_wr_addr_q   <= 16'd0;
            snoop_wr_data_q   <= 16'd0;
        end else begin
            snoop_pulse_q <= 1'b0;
            if (!load_en && ctrl_e_wr) begin
                if ((ctrl_e_wr_addr >= MMR_END) &&
                    !((ctrl_e_wr_addr >= IO_HOST_LO) &&
                      (ctrl_e_wr_addr <= IO_HOST_HI))) begin
                    snoop_pulse_q   <= 1'b1;
                    snoop_pmem_q    <= !snoop_dm_internal(ctrl_e_wr_addr);
                    snoop_wr_addr_q <= ctrl_e_wr_addr;
                    snoop_wr_data_q <= ctrl_e_wr_data;
                end
            end
            /* The program write is presented in the E clock and
               retires at the edge ending that clock, so the snoop
               pulses AT that edge (one stage): the memory latches
               the write into its pending slot when presented and
               serves it, so the harness shadow must update in the
               retire clock, not one clock later on the ack. */
            if (!load_en && mux_pm_wr_req) begin
                snoop_pulse_q   <= 1'b1;
                snoop_pmem_q    <= !snoop_pm_is_dmem(mux_pm_wr_addr);
                snoop_wr_addr_q <= snoop_pm_is_dmem(mux_pm_wr_addr) ? snoop_pm_to_dmem(mux_pm_wr_addr) : mux_pm_wr_addr;   /* reported where it really landed */
                snoop_wr_data_q <= mux_pm_wr_data;
            end
        end
    end

    /*
    Observation outputs. pc_o / op_o are retire-anchored. st0_o
    and st1_o take OV from the ALU's o_ov and C from the ALU's
    o_c (the ALU owns them); the remaining bits come from the
    address unit's words. stack_top_o is the stack top (the
    address unit's pop data: TOS).
    */
    assign instr_done      = ctrl_instr_done;
    assign cycles_o        = ctrl_cycles;
    assign pc_o            = ctrl_retire_pc;
    assign op_o            = ctrl_retire_op;
    assign acc_o           = alu_acc;
    assign accb_o          = alu_accb;
    assign preg_o          = alu_preg;
    assign treg0_o         = alu_treg0;
    assign treg1_o         = alu_treg1;
    assign treg2_o         = alu_treg2;
    assign ar_cur_o        = addr_ar;
    assign arp_o           = addr_arp;
    assign st0_o           = {addr_st0[15:13], alu_ov, addr_st0[11:0]};
    assign st1_o           = {addr_st1[15:10], alu_c, addr_st1[8:0]};
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
    assign ar_all_o        = addr_ar_all;
    assign stack_all_o     = addr_stack_all;
    assign ifr_o           = addr_ifr;
    assign imr_o           = addr_imr;
    assign idle_o          = ctrl_idle;
    assign halted_o        = ctrl_halted;
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

    /* PIPE_OBS retire bundle and stall counters, forwarded. */
    assign retire_cycles_o     = ctrl_retire_cycles;
    assign retire_is_intr_o    = ctrl_retire_is_intr;
    assign retire_cnt_o        = ctrl_retire_cnt;
    assign retire_tgl_o        = ctrl_retire_tgl;
    assign obs_sh_acc_o        = ctrl_obs_sh_acc;
    assign obs_sh_accb_o       = ctrl_obs_sh_accb;
    assign obs_sh_preg_o       = ctrl_obs_sh_preg;
    assign obs_sh_treg0_o      = ctrl_obs_sh_treg0;
    assign obs_sh_treg1_o      = ctrl_obs_sh_treg1;
    assign obs_sh_treg2_o      = ctrl_obs_sh_treg2;
    assign obs_sh_arcr_o       = ctrl_obs_sh_arcr;
    assign obs_sh_indx_o       = ctrl_obs_sh_indx;
    assign obs_sh_st0_o        = ctrl_obs_sh_st0;
    assign obs_sh_st1_o        = ctrl_obs_sh_st1;
    assign obs_sh_pmst_o       = ctrl_obs_sh_pmst;
    assign cnt_stall_branch_o  = ctrl_cnt_stall_branch;
    assign cnt_stall_2word_o   = ctrl_cnt_stall_2word;
    assign cnt_stall_pmem_op_o = ctrl_cnt_stall_pmem_op;
    assign cnt_stall_rptb_setup_o = ctrl_cnt_stall_rptb_setup;
    assign cnt_stall_h1_o      = ctrl_cnt_stall_h1;
    assign cnt_stall_h1a_o     = ctrl_cnt_stall_h1a;
    assign cnt_stall_h1b_o     = ctrl_cnt_stall_h1b;
    assign cnt_stall_h2_o      = ctrl_cnt_stall_h2;
    assign cnt_stall_h3_o      = ctrl_cnt_stall_h3;
    assign cnt_stall_int_entry_o = ctrl_cnt_stall_int_entry;
    assign cnt_stall_h10_o     = ctrl_cnt_stall_h10;
    assign cnt_stall_rpt_replay_o = ctrl_cnt_stall_rpt_replay;
    assign cnt_stall_mac_replay_o = ctrl_cnt_stall_mac_replay;
    assign cnt_stall_xc_o      = ctrl_cnt_stall_xc;
    assign cnt_stall_io_wait_o = ctrl_cnt_stall_io_wait;
    /*
    R-port and E-port muxes for the debug sequencer. The debug
    sequencer wins while it is active; the control unit drives
    the ports otherwise. Only used when the core is halted or
    parked, so the control unit drives neither port then.
    */
    logic        mem_r_req;
    logic [15:0] mem_r_addr;
    logic        mem_r_is_prog;
    logic        mem_e_rd_req;
    logic [15:0] mem_e_rd_addr;
    logic        addr_irq_pend;
    logic [15:0] mem_obs_iowsr;
    logic [15:0] mem_obs_cwsr;

    assign mem_r_req     = debug_r_active ? 1'b1 : ctrl_r_req;
    assign mem_r_addr    = debug_r_active ? debug_addr_q : ctrl_r_addr;
    assign mem_r_is_prog = debug_r_active ? 1'b0 : ctrl_r_is_prog;
    assign mem_e_rd_req  = debug_e_active ? 1'b1 : ctrl_e_rd_req;
    assign mem_e_rd_addr = debug_e_active ? debug_addr_q : ctrl_e_rd_addr;
    assign obs_iowsr_o   = mem_obs_iowsr;
    assign obs_cwsr_o    = mem_obs_cwsr;

    /*
    Submodule instances. One port connection per line, names
    aligned. Empty connections are intentional and documented
    here.

    The ALU is the register file for ACC/ACCB/PREG/TREG0-2 and
    owns C/OV. Its combinational micro-op result is on
    acc_next, wired to the control unit as alu_y (the control
    unit's executor uses it only to form acc_data/accb_data
    for the verbatim ex_* block; the ALU commits the result
    internally on its load strobes). o_pscale, o_ext,
    o_b16_shl and o_shl_acc are not consumed by the control
    unit or this top. o_e_wrt_treg0/1/2 duplicate the
    control unit's bundle write-target set (wr_treg0/1/2),
    which is the hazard source; they are not wired.

    The address unit's old ea path (i_ea_en) is tied low: the
    effective address is combinational from i_op, and the AR
    update goes through the descriptor (i_desc_en), never
    through the ea pulse, so the update cannot be applied
    twice. i_ea_p0 is the SST page-0 rule. The RPT window
    (i_rpt_setup / i_rpt_step) is tracked in the control unit,
    not the address unit; only i_rpt_dec (the RPTC decrement)
    is wired. CMPR goes through the flag port (TC), not the
    address unit's i_cmpr_en. o_rpt_restart / o_rpt_pc /
    o_rep_cont / o_braf_restart / o_braf_done / o_rpt_start /
    o_rpt_end / o_ar0_dirty are the address unit's own
    repeat strobes; the control unit computes them itself
    and drives the updates (i_braf_check), so they are left
    unconnected. o_ea_badop and o_cond are the old path's
    outputs; the control unit uses the descriptor mode and
    c5x_cond() instead.

    The control unit's rptb_clr_o is never asserted: the BRAF
    clear runs inside the address unit via handle_braf on
    i_braf_check (KNOWN-DIFF 2, 3). flush_all_o is always 0
    (no whole-pipeline flush in this design). loop_pma_req_o
    and loop_pma_addr_o are the R-stage pma-read request;
    the fetch port carries the read (fetch_req_o / fetch_addr_o
    with fetch_is_pma_o), so they are observation only here.

    The memory's o_f_stall is not wired to the control unit:
    the stall is visible as a low fetch ack (fetch_serve is
    gated on !o_f_stall inside the memory), and the control
    unit re-presents a stalled fetch while fetch_inflight_q
    is set (KNOWN-DIFF 8). o_r_deferred, o_r_use_pmem,
    o_r_use_dmem, o_r_dma_is_pmem and o_e_periph_ws are R/E
    routing diagnostics the control unit computes itself;
    o_ext_mmr_rd, o_pm_epoch_inc and o_replay_dirty_pulse
    are not consumed (the control unit tracks the replay
    window itself).
    */
    /* verilator lint_off PINCONNECTEMPTY */
    /* verilator lint_off UNUSEDSIGNAL */
    c5x_alu u_alu (
        .clk            (clk),
        .rst_n          (rst_n),
        .i_exec         (alu_exec_mux),
        .i_ld_acc       (ctrl_alu_ld_acc),
        .i_ld_accb      (ctrl_alu_ld_accb),
        .i_ld_preg      (ctrl_alu_ld_preg),
        .i_ld_treg0     (alu_ld_treg0_mux),
        .i_op           (alu_op_mux),
        .i_b32          (ctrl_alu_b32),
        .i_b16          (alu_b16_mux),
        .i_mpy_a        (ctrl_alu_mpy_a),
        .i_mpy_b        (ctrl_alu_mpy_b),
        .i_mpy_unsigned (ctrl_alu_mpy_unsigned),
        .i_shift        (ctrl_alu_shift),
        .i_s16          (ctrl_alu_s16),
        .i_sxm          (st1_sxm),
        .i_ovm          (st0_ovm),
        .i_pm           (st1_pm),
        .i_trm          (alu_trm_mux),
        .i_flag_c_we    (ctrl_alu_flag_c_we),
        .i_flag_c_in    (ctrl_alu_flag_c_in),
        .i_flag_ov_we   (ctrl_alu_flag_ov_we),
        .i_flag_ov_in   (ctrl_alu_flag_ov_in),
        .i_treg12_wr_en (alu_treg12_wr_en_mux),
        .i_treg12_sel   (alu_treg12_sel_mux),
        .i_treg12_data  (alu_treg12_data_mux),
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
        .o_tc_next      (alu_tc_next),
        .o_tc_wr        (alu_tc_wr),
        .o_e_wrt_treg0  (),
        .o_e_wrt_treg1  (),
        .o_e_wrt_treg2  (),
        .acc_next       ()
    );

    c5x_addr u_addr (
        .clk            (clk),
        .rst_n          (rst_n),
        .i_op           (fd_q.word),
        .i_acc          (alu_acc),
        .i_bio          (bio_i),
        .i_ea_en        (1'b0),
        .i_ea_p0        ((fd_q.word[15:8] == OP_SST0) ||
                         (fd_q.word[15:8] == OP_SST1)),
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
        .o_irq_pend     (addr_irq_pend),
        .i_ndx_commit   (ctrl_ndx_commit),
        .i_rpt_setup    (1'b0),
        .i_rpt_pc_in    (16'd0),
        .i_rpt_step     (1'b0),
        .i_rpt_ppc      (16'd0),
        .i_rpt_dec      (ctrl_rptc_dec),
        .o_rpt_restart  (),
        .o_rpt_pc       (),
        .o_rep_cont     (),
        .i_rptb_set     (ctrl_rptb_set),
        .i_rptb_pasr    (ctrl_rptb_pasr),
        .i_rptb_paer    (ctrl_rptb_paer),
        .i_braf_check   (ctrl_braf_check),
        .i_pc           (ctrl_braf_pc),
        .o_braf_restart (),
        .o_braf_done    (),
        .o_st0          (addr_st0),
        .o_st1          (addr_st1),
        .o_pmst         (addr_pmst),
        .o_ar           (addr_ar),
        .o_arp          (addr_arp),
        .o_arb          (),
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
        .o_tc           (),
        .o_ov           (),
        .o_c            (),
        .o_braf         (),
        .o_ar0_dirty    (),
        .o_ar_all       (addr_ar_all),
        .o_stack_all    (addr_stack_all),
        .i_ar_rd_sel    (ctrl_ar_rd_sel),
        .o_ar_rd        (addr_ar_rd),
        .i_d_ea_use     (ctrl_d_ea_use),
        .i_d_pfc_acc    (ctrl_d_pfc_acc),
        .i_d_pfc_bmar   (ctrl_d_pfc_bmar),
        .i_desc_en      (ctrl_desc_en),
        .i_desc_ar_id   (ctrl_desc_ar_id),
        .i_desc_mode    (ctrl_desc_mode),
        .i_desc_arp_sw  (ctrl_desc_arp_sw),
        .i_desc_new_arp (ctrl_desc_new_arp),
        .i_desc_ark     (ctrl_desc_ark),
        .i_desc_hold    (ctrl_desc_hold),
        .i_desc_keep_arb (ctrl_desc_keep_arb),
        .i_arau_ar      (ctrl_arau_ar),
        .i_arau_ar_id   (ctrl_arau_ar_id),
        .i_arau_mode    (ctrl_arau_mode),
        .i_arau_ark     (ctrl_arau_ark),
        .o_arau_ea      (),
        .o_arau_next    (addr_arau_next),
        .o_arau_badop   (),
        .o_d_desc_ar_id (addr_d_desc_ar_id),
        .o_d_desc_mode  (addr_d_desc_mode),
        .o_d_desc_arp_sw (addr_d_desc_arp_sw),
        .o_d_desc_new_arp (addr_d_desc_new_arp),
        .o_d_desc_ark   (addr_d_desc_ark),
        .o_d_desc_valid (addr_d_desc_valid),
        .o_d_ea_badop   (addr_d_ea_badop),
        .o_d_desc_norm_cond (addr_d_desc_norm_cond),
        .o_d_ar_next    (),
        .o_d_src_ar_use (addr_d_src_ar_use),
        .o_d_src_ar_id  (addr_d_src_ar_id),
        .o_d_src_indx_use (addr_d_src_indx_use),
        .o_d_src_dp_use (addr_d_src_dp_use),
        .o_d_src_arp_use (addr_d_src_arp_use),
        .o_d_src_circ_use (addr_d_src_circ_use),
        .o_d_src_acc_use (addr_d_src_acc_use),
        .o_d_src_bmar_use (addr_d_src_bmar_use),
        .o_d_wrt_ar_valid (addr_d_wrt_ar_valid),
        .o_d_wrt_ar_id  (addr_d_wrt_ar_id),
        .o_d_wrt_arp_sw (addr_d_wrt_arp_sw),
        .o_d_wrt_arp_id (addr_d_wrt_arp_id),
        .o_d_wrt_ar0_mirror (addr_d_wrt_ar0_mirror),
        .o_e_wrt_ar_valid (),
        .o_e_wrt_ar_id  (),
        .o_e_wrt_arp_sw (),
        .o_e_wrt_indx_arcr ()
    );

    c5x_decode u_decode (
        .clk            (clk),
        .rst_n          (rst_n),
        .instr_i        (fd_q.word),
        .instr2_i       (fd_q.word2),
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

    c5x_pipe_ctrl #(
        .RESET_PC       (RESET_PC),
        .WALL_TIME      (WALL_TIME),
        .FETCH_CHAIN    (FETCH_CHAIN)
    ) u_ctrl (
        .clk            (clk),
        .rst_n          (rst_n),
        .step_i         (step_i),
        .bp_en_i        (bp_en_i),
        .bp_pc0_i       (bp_pc0_i),
        .bp_pc1_i       (bp_pc1_i),
        .fd_i           (fd_q),
        .d_dec_i        (dec_struct),
        .d_ea_i         (addr_ea),
        .d_desc_i       (desc_struct),
        .d_src_ar_use_i (addr_d_src_ar_use),
        .d_src_ar_id_i  (addr_d_src_ar_id),
        .d_src_indx_use_i (addr_d_src_indx_use),
        .d_src_dp_use_i (addr_d_src_dp_use),
        .d_src_arp_use_i (addr_d_src_arp_use),
        .d_src_circ_use_i (addr_d_src_circ_use),
        .d_src_acc_use_i (addr_d_src_acc_use),
        .d_src_bmar_use_i (addr_d_src_bmar_use),
        .d_wrt_ar_valid_i (addr_d_wrt_ar_valid),
        .d_wrt_ar_id_i  (addr_d_wrt_ar_id),
        .d_wrt_arp_sw_i (addr_d_wrt_arp_sw),
        .d_wrt_arp_id_i (addr_d_wrt_arp_id),
        .d_wrt_ar0_mirror_i (addr_d_wrt_ar0_mirror),
        .dr_i           (dr_q),
        .re_i           (re_q),
        .fetch_ack_i    (mem_pm_fetch_ack),
        .fetch_data_i   (mem_pm_fetch_data),
        .pm_wr_flush_i  (mem_pm_wr_flush),
        .r_stall_i      (mem_r_stall),
        .r_data_i       (mem_r_data),
        .e_rdata_i      (mem_e_rdata),
        .e_stall_i      (mem_e_stall),
        .e_io_done_i    (mem_e_io_done),
        .e_io_ws_i      (mem_e_io_ws),
        .tint_will_raise_i (mem_tint_will_raise),
        .acc_i          (alu_acc),
        .accb_i         (alu_accb),
        .preg_i         (alu_preg),
        .treg0_i        (alu_treg0),
        .treg1_i        (alu_treg1),
        .treg2_i        (alu_treg2),
        .ar_cur_i       (addr_ar),
        .ar_rd_i        (addr_ar_rd),
        .arcr_i         (addr_arcr),
        .indx_i         (addr_indx),
        .bmar_i         (addr_bmar),
        .dbmr_i         (addr_dbmr),
        .rptc_i         (addr_rptc),
        .brcr_i         (addr_brcr),
        .pasr_i         (addr_pasr),
        .paer_i         (addr_paer),
        .pop_data_i     (addr_pop_data),
        .ifr_i          (addr_ifr),
        .imr_i          (addr_imr),
        .pmst_i         (addr_pmst),
        .st0_i          (addr_st0),
        .st1_i          (addr_st1),
        .alu_c_i        (alu_c),
        .alu_ov_i       (alu_ov),
        .alu_mpy_i      (alu_mpy),
        .bio_i          (bio_i),
        .ivec_ind_i     (ivec_ind_i),
        .irq_pend_i     (addr_irq_pend),
        .io_rdata_i     (io_rdata),
        .io_ack_i       (io_ack),
        .arau_next_i    (addr_arau_next),
        .iowsr_i        (mem_obs_iowsr),
        .cwsr_i         (mem_obs_cwsr),
        .f_hold_o       (),
        .d_hold_o       (),
        .r_hold_o       (),
        .e_hold_o       (),
        .flush_fdr_o    (ctrl_flush_fdr),
        .flush_all_o    (),
        .fd_load_o      (ctrl_fd_load),
        .dr_load_o      (ctrl_dr_load),
        .re_load_o      (ctrl_re_load),
        .e_consume_o    (ctrl_e_consume),
        .dr_o           (ctrl_dr_o),
        .re_o           (ctrl_re_o),
        .fetch_req_o    (ctrl_fetch_req),
        .fetch_addr_o   (ctrl_fetch_addr),
        .fetch_ldpc_o   (ctrl_fetch_ldpc),
        .fetch_is_word2_o (ctrl_fetch_is_word2),
        .fetch_is_pma_o (),
        .rptb_cancel_o  (),
        .loop_pma_req_o (),
        .loop_pma_addr_o (),
        .r_req_o        (ctrl_r_req),
        .r2_req_o       (ctrl_r2_req),
        .r2_addr_o      (ctrl_r2_addr),
        .r2_data_i      (mem_r2_data),
        .r_addr_o       (ctrl_r_addr),
        .r_is_prog_o    (ctrl_r_is_prog),
        .ar_rd_sel_o    (ctrl_ar_rd_sel),
        .arau_ar_o      (ctrl_arau_ar),
        .arau_ar_id_o   (ctrl_arau_ar_id),
        .arau_mode_o    (ctrl_arau_mode),
        .arau_ark_o     (ctrl_arau_ark),
        .d_ea_use_o     (ctrl_d_ea_use),
        .d_pfc_acc_o    (ctrl_d_pfc_acc),
        .d_pfc_bmar_o   (ctrl_d_pfc_bmar),
        .alu_exec_o     (ctrl_alu_exec),
        .alu_op_o       (ctrl_alu_op),
        .alu_b32_o      (ctrl_alu_b32),
        .alu_b16_o      (ctrl_alu_b16),
        .alu_mpy_a_o    (ctrl_alu_mpy_a),
        .alu_mpy_b_o    (ctrl_alu_mpy_b),
        .alu_mpy_unsigned_o (ctrl_alu_mpy_unsigned),
        .alu_shift_o    (ctrl_alu_shift),
        .alu_s16_o      (ctrl_alu_s16),
        .alu_ld_acc_o   (ctrl_alu_ld_acc),
        .alu_ld_accb_o  (ctrl_alu_ld_accb),
        .alu_ld_preg_o  (ctrl_alu_ld_preg),
        .alu_ld_treg0_o (ctrl_alu_ld_treg0),
        .alu_flag_c_we_o (ctrl_alu_flag_c_we),
        .alu_flag_c_in_o (ctrl_alu_flag_c_in),
        .alu_flag_ov_we_o (ctrl_alu_flag_ov_we),
        .alu_flag_ov_in_o (ctrl_alu_flag_ov_in),
        .alu_treg12_wr_en_o (ctrl_alu_treg12_wr_en),
        .alu_treg12_sel_o (ctrl_alu_treg12_sel),
        .alu_treg12_data_o (ctrl_alu_treg12_data),
        .ar_wr_en_o     (ctrl_ar_wr_en),
        .ar_wr_sel_o    (ctrl_ar_wr_sel),
        .ar_wr_data_o   (ctrl_ar_wr_data),
        .st0_ld_en_o    (ctrl_st0_ld_en),
        .st0_ld_data_o  (ctrl_st0_ld_data),
        .st1_ld_en_o    (ctrl_st1_ld_en),
        .st1_ld_data_o  (ctrl_st1_ld_data),
        .pmst_ld_en_o   (ctrl_pmst_ld_en),
        .pmst_ld_data_o (ctrl_pmst_ld_data),
        .rptc_ld_en_o   (ctrl_rptc_ld_en),
        .rptc_ld_data_o (ctrl_rptc_ld_data),
        .brcr_ld_en_o   (ctrl_brcr_ld_en),
        .brcr_ld_data_o (ctrl_brcr_ld_data),
        .addr_wr_en_o   (ctrl_addr_wr_en),
        .addr_wr_sel_o  (ctrl_addr_wr_sel),
        .addr_wr_data_o (ctrl_addr_wr_data),
        .st_bit_en_o    (ctrl_st_bit_en),
        .st_bit_sel_o   (ctrl_st_bit_sel),
        .st_bit_val_o   (ctrl_st_bit_val),
        .desc_en_o      (ctrl_desc_en),
        .desc_ar_id_o   (ctrl_desc_ar_id),
        .desc_mode_o    (ctrl_desc_mode),
        .desc_arp_sw_o  (ctrl_desc_arp_sw),
        .desc_new_arp_o (ctrl_desc_new_arp),
        .desc_ark_o     (ctrl_desc_ark),
        .desc_hold_o    (ctrl_desc_hold),
        .desc_keep_arb_o (ctrl_desc_keep_arb),
        .ndx_commit_o   (ctrl_ndx_commit),
        .push_en_o      (ctrl_push_en),
        .push_data_o    (ctrl_push_data),
        .pop_en_o       (ctrl_pop_en),
        .rptc_dec_o     (ctrl_rptc_dec),
        .rptb_set_o     (ctrl_rptb_set),
        .rptb_pasr_o    (ctrl_rptb_pasr),
        .rptb_paer_o    (ctrl_rptb_paer),
        .rptb_clr_o     (),
        .braf_check_o   (ctrl_braf_check),
        .braf_pc_o      (ctrl_braf_pc),
        .irq_ack_o      (ctrl_irq_ack),
        .e_wr_o         (ctrl_e_wr),
        .e_wr_addr_o    (ctrl_e_wr_addr),
        .e_wr_data_o    (ctrl_e_wr_data),
        .e_dmov_o       (ctrl_e_dmov),
        .e_dmov_src_o   (ctrl_e_dmov_src),
        .e_wr_flush_en_o (ctrl_e_wr_flush_en),
        .e_rd_req_o     (ctrl_e_rd_req),
        .e_rd_addr_o    (ctrl_e_rd_addr),
        .e_io_req_o     (ctrl_e_io_req),
        .e_io_rd_o      (ctrl_e_io_rd),
        .e_io_addr_o    (ctrl_e_io_addr),
        .e_io_wdata_o   (ctrl_e_io_wdata),
        .pm_wr_req_o    (ctrl_pm_wr_req),
        .pm_wr_addr_o   (ctrl_pm_wr_addr),
        .pm_wr_data_o   (ctrl_pm_wr_data),
        .pm_wr_is_e_o   (ctrl_pm_wr_is_e),
        .pm_wr_flush_en_o (ctrl_pm_wr_flush_en),
        .instr_done_o   (ctrl_instr_done),
        .retire_cycles_o (ctrl_retire_cycles),
        .retire_is_intr_o (ctrl_retire_is_intr),
        .retire_cnt_o   (ctrl_retire_cnt),
        .retire_tgl_o   (ctrl_retire_tgl),
        .retire_pc_o    (ctrl_retire_pc),
        .retire_op_o    (ctrl_retire_op),
        .cycles_o       (ctrl_cycles),
        .idle_o         (ctrl_idle),
        .idle2_o        (ctrl_idle2),
        .model_tick_o   (ctrl_model_tick),
        .mtime_o        (mtime_o),
        .halted_o       (ctrl_halted),
        .cnt_stall_branch_o (ctrl_cnt_stall_branch),
        .cnt_stall_2word_o (ctrl_cnt_stall_2word),
        .cnt_stall_pmem_op_o (ctrl_cnt_stall_pmem_op),
        .cnt_stall_rptb_setup_o (ctrl_cnt_stall_rptb_setup),
        .cnt_stall_h1_o (ctrl_cnt_stall_h1),
        .cnt_stall_h1a_o (ctrl_cnt_stall_h1a),
        .cnt_stall_h1b_o (ctrl_cnt_stall_h1b),
        .cnt_stall_h2_o (ctrl_cnt_stall_h2),
        .cnt_stall_h3_o (ctrl_cnt_stall_h3),
        .cnt_stall_int_entry_o (ctrl_cnt_stall_int_entry),
        .cnt_stall_h10_o (ctrl_cnt_stall_h10),
        .cnt_stall_rpt_replay_o (ctrl_cnt_stall_rpt_replay),
        .cnt_stall_mac_replay_o (ctrl_cnt_stall_mac_replay),
        .cnt_stall_xc_o (ctrl_cnt_stall_xc),
        .cnt_stall_io_wait_o (ctrl_cnt_stall_io_wait),
        .obs_sh_acc_o   (ctrl_obs_sh_acc),
        .obs_sh_accb_o  (ctrl_obs_sh_accb),
        .obs_sh_preg_o  (ctrl_obs_sh_preg),
        .obs_sh_treg0_o (ctrl_obs_sh_treg0),
        .obs_sh_treg1_o (ctrl_obs_sh_treg1),
        .obs_sh_treg2_o (ctrl_obs_sh_treg2),
        .obs_sh_arcr_o  (ctrl_obs_sh_arcr),
        .obs_sh_indx_o  (ctrl_obs_sh_indx),
        .obs_sh_st0_o   (ctrl_obs_sh_st0),
        .obs_sh_st1_o   (ctrl_obs_sh_st1),
        .obs_sh_pmst_o  (ctrl_obs_sh_pmst)
    );

    c5x_mem u_mem (
        .clk            (clk),
        .rst_n          (rst_n),
        .i_cnf          (st1_cnf),
        .i_ovly         (pmst_ovly),
        .i_ram          (pmst_ram),
        .i_xint_mode    (xint_mode),
        .i_ser_tick     (ser_tick),
        .i_ser_rx       (ser_rx),
        .i_idle2_freeze (ctrl_idle2),
        .i_model_tick   (ctrl_model_tick),
        .i_replay_active (1'b0),
        .i_replay_lo    (16'd0),
        .i_replay_hi    (16'd0),
        .i_pm_fetch_req (ctrl_fetch_req),
        .i_pm_fetch_addr (ctrl_fetch_addr),
        .o_pm_fetch_data (mem_pm_fetch_data),
        .o_pm_fetch_ack (mem_pm_fetch_ack),
        .o_f_stall      (),
        .i_pm_wr_req    (mux_pm_wr_req),
        .i_pm_wr_addr   (mux_pm_wr_addr),
        .i_pm_wr_data   (mux_pm_wr_data),
        .i_pm_wr_is_e   (mux_pm_wr_is_e),
        .i_pm_wr_flush_en (mux_pm_wr_flush_en),
        .o_pm_wr_ack    (),
        .o_pm_wr_flush  (mem_pm_wr_flush),
        .i_r2_req       (ctrl_r2_req),
        .i_r2_addr      (ctrl_r2_addr),
        .o_r2_data      (mem_r2_data),
        .i_r_req        (mem_r_req),
        .i_r_addr       (mem_r_addr),
        .i_r_is_prog    (mem_r_is_prog),
        .o_r_data       (mem_r_data),
        .o_r_deferred   (),
        .o_r_use_pmem   (),
        .o_r_use_dmem   (),
        .o_r_dma_is_pmem (),
        .o_r_stall      (mem_r_stall),
        .i_e_rd_req     (mem_e_rd_req),
        .i_e_rd_addr    (mem_e_rd_addr),
        .o_e_rdata      (mem_e_rdata),
        .i_e_wr         (mux_e_wr),
        .i_e_wr_addr    (mux_e_wr_addr),
        .i_e_wr_data    (mux_e_wr_data),
        .i_e_dmov       (mux_e_dmov),
        .i_e_dmov_src   (mux_e_dmov_src),
        .i_e_wr_flush_en (mux_e_wr_flush_en),
        .i_e_io_req     (ctrl_e_io_req),
        .i_e_io_rd      (ctrl_e_io_rd),
        .i_e_io_addr    (ctrl_e_io_addr),
        .i_e_io_wdata   (ctrl_e_io_wdata),
        .o_e_stall      (mem_e_stall),
        .o_e_io_done    (mem_e_io_done),
        .o_e_io_ws      (mem_e_io_ws),
        .o_e_periph_ws  (),
        .i_ext_mmr_rdata (ext_mmr_rdata),
        .i_ext_mmr_e_rdata (ext_mmr_rdata_e),
        .o_ext_mmr_e_addr (mem_ext_mmr_e_addr),
        .o_ext_mmr_rd   (),
        .o_ext_mmr_wr   (mem_ext_mmr_wr),
        .o_ext_mmr_addr (mem_ext_mmr_addr),
        .o_ext_mmr_w_addr (mem_ext_mmr_w_addr),
        .o_ext_mmr_wdata (mem_ext_mmr_wdata),
        .o_io_req       (mem_io_req),
        .o_io_rd        (mem_io_rd),
        .o_io_addr      (mem_io_addr),
        .o_io_wdata     (mem_io_wdata),
        .i_io_ack       (io_ack),
        .i_io_rdata     (io_rdata),
        .o_tint_pulse   (mem_tint_pulse),
        .o_tint_will_raise (mem_tint_will_raise),
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
        .o_obs_iowsr    (mem_obs_iowsr),
        .o_obs_cwsr     (mem_obs_cwsr)
    );
    /* verilator lint_on UNUSEDSIGNAL */
    /* verilator lint_on PINCONNECTEMPTY */
endmodule
