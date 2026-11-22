/*
c5x_addr.sv -- TMS320C5x addressing unit and status registers.

Part of the TMS320C5x DSP core port for Cyclone V (goal:
"TMS320C5x DSP core on FPGA").  This module owns the auxiliary
registers, the indirect/direct effective-address generation, the
circular-buffer and bit-reversed addressing, the 8-deep hardware
stack, the status registers ST0/ST1/PMST, the repeat state
(RPTC/RPTB/BRCR) and the IFR/IMR interrupt registers. It also
exposes the full AR file and stack for observation (o_ar_all /
o_stack_all) and an indexed AR read (i_ar_rd_sel / o_ar_rd) that
the control FSM uses for SAR; see FIX-1 below.

REFERENCE MODEL (the spec -- this RTL matches it, not the TI
manual): research_notes/courier-firmware/c-port/c/src/dsp/c5x_core.c
  ea()          : lines 1119-1156   (indirect/direct effective address)
  ea_p0()       : lines 1158-1164   (SST page-0 direct variant)
  upd_ar()      : lines 1085-1106   (AR step with circular wrap)
  upd_arp()     : lines 1107-1111   (ARP switch, old ARP -> ARB)
  circ_end()    : lines 1062-1078   (bit-reversed circular end test)
  bitrev16()    : lines 1080-1085
  push()/pop()  : lines 972-985     (stack, incl. pop-copy quirk)
  st0_get()     : lines 453-460, st1_get() : lines 462-471,
  pmst_get()    : lines 473-480
  c5x_set()     : lines 514-563     (ST0/ST1/PMST/AR write decode)
  mmr_rd/wr()   : lines 620-797     (MMR map: IMR 0x04, IFR 0x06,
                  PMST 0x07, RPTC 0x08, BRCR 0x09, PASR 0x0A,
                  PAER 0x0B, DBMR 0x0F, AR0-7 0x10-17, INDX 0x18,
                  ARCR 0x19, CBSR1 0x1A, CBER1 0x1B, CBSR2 0x1C,
                  CBER2 0x1D, CBCR 0x1E (write masked to 0xFF),
                  BMAR 0x1F; IFR is write-1-to-clear)
  apply_ar0_mirror() : lines 2756-2763 (NDX=0 mirror AR0->INDX/ARCR)
  handle_rpt()  : lines 2640-2653   (single-instruction RPT)
  handle_braf() : lines 2656-2668   (RPTB block-end test)
  RPTB setup    : lines 2401-2407   (braf=1, pasr=pc, paer=imm)
  CMPR          : lines 2477-2484   (TC from AR[ARP] vs ARCR/AR0)
  cond()/zlvc_cond()/tp_cond() : lines 1168-1209
  c5x_reset()   : lines 425-452     (reset values; see RESET note)
  check_int()   : lines 1301-1323   (pend = ifr & imr, bits 0..8)
  LDP/LDPK      : lines 1434-1436, 2177 (dp = (d & 0x1ff) << 7)

CONTRACT WITH THE CORE (agent 1's executor):
- Single clock. rst_n is active-low and SYNCHRONOUS.
- ea(): drive i_op and pulse i_ea_en for exactly one cycle. o_ea
  is valid during that cycle (old AR value for indirect, dp|dma
  for direct) and the AR/ARP update commits at the posedge ending
  the cycle. o_ea_badop flags the unlisted modification (m = 6/7);
  on a badop the AR is NOT updated but the ARP switch (m bit 0)
  still happens, exactly as in C.
- i_ea_p0 selects ea_p0(): direct addresses use page 0.
- The NDX mirror is NOT applied by ea() itself: the core pulses
  i_ndx_commit once at the end of each instruction, modelling
  apply_ar0_mirror() in the C run loop. The mirror uses the
  post-update AR0 value even if the AR0 write lands in the same
  cycle as the commit strobe.
- LST #0 (WR_ST0L) does not load INTM and does not touch ARB: the
  C code saves ARB around ea() and restores it, so the core must
  restore ARB with WR_ARB after the ea() of an LST #0. LST #1
  (WR_ST1L) loads ARB and ARP both from the word. The plain
  WR_ST0/WR_ST1 selects implement the c5x_set() host-API decode,
  which differs from both instructions (ST0 loads INTM; ST1 loads
  ARB only).
- Status/flag writes from the ALU use i_flg_we/i_flg_sel/i_flg_in
  (single-bit fields), i_pm_we/i_pm_in (PM, 2 bits), i_iptr_we/
  i_iptr_in (IPTR, 5 bits). Register-file/MMR writes use
  i_wr_en/i_wr_sel/i_wr_data. When two sources write the same
  register in one cycle the LATER program-order source wins:
  ea update < flag/CMPR writes < stack/irq/repeat strobes <
  descriptor commit < i_wr_* (register-file port wins). The core
  never asserts two conflicting strobes in one cycle; the order
  is documented so a violation is deterministic, not X.
- RPT: the core loads RPTC via the write port (RPT/RPTZ/RPT #k/#lk
  immediates, zero-extended 16 bit) and pulses i_rpt_setup with
  i_rpt_pc_in = PC of the repeated instruction, then pulses
  i_rpt_step once per executed instruction with i_rpt_ppc = the PC
  of the instruction just executed; o_rpt_restart + o_rpt_pc tell
  it to rewind PC to rpt_start. i_rpt_dec decrements RPTC by one
  (the per-instruction repeat loops in exec1). RPTB: i_rptb_set loads
  PASR/PAER and sets BRAF; i_braf_check with i_pc = current PC
  (already past the last block word) runs handle_braf().
- Stack: i_push_en/i_push_data, i_pop_en; o_pop_data is the
  combinational top of stack. Push and pop are mutually exclusive
  in the core (no instruction does both); if both are asserted,
  pop wins for SP.

RESET NOTE (c5x_reset, C lines 425-452): rst_n clears the AR file,
ARP/ARB, DP, all status bits, SP/stack, RPTC, BRCR, IFR/IMR, CBCR,
ar0_dirty and rep_cont -- exactly the fields c5x_reset clears.
It does NOT clear INDX, ARCR, CBSR1/CBER1/CBSR2/CBER2, BMAR, DBMR,
PASR, PAER, rpt_start, rpt_end: the C reset deliberately preserves
them, and they power up to 0 (c5x_new uses calloc). They are given
declaration initial values of 0 here (power-on state on Cyclone V,
time-0 state in Verilator) and are untouched by rst_n.

KNOWN-DIFFs (C model vs TI manual, from c5x_core_audit; the RTL
follows the C model, these are NOT fixed here):
- KD-1 (audit #22, 07b:246): *BR0+/- circular wrap. The manual
  wraps the bit-reversed RESULT into the circular block; the C
  ea() only wraps when the CURRENT AR equals CBER (circ_end) and
  otherwise returns the raw bit-reversed step. Verified against
  the current C: AR0=0x0101, INDX=0x0002, CBSR1=0x0100/CBER1=
  0x0102, MAR *BR0+ -> AR0=0x0103 (manual: 0x0100). The audit's
  "C gives 0x0103" note is the same raw step with circular
  disabled. RTL replicates the C behaviour.
- KD-2 (audit #8, 07c:190): RPTB PAER. The audit measured
  paer = imm + 1 in an older core; the CURRENT C sets paer = imm
  (line 2406). RTL follows current C.
- KD-3 (audit #31b, 07c:202): BRCR after a BRCR=0 block. The audit
  measured BRCR = -1; the CURRENT C only decrements when
  brcr > 0 at the wrap (handle_braf), so BRCR stays 0. RTL follows
  current C.
- KD-4 (audit #9, C lines 1277-1279): restore_ctx does not restore
  INTM/XF. The shadow context itself lives in the core (agent 1);
  this module only holds the live bits, so there is nothing to
  replicate here, but the core must NOT expect INTM/XF to come
  back from a shadow restore.

FIXES (changes vs the as-delivered module; the RTL still follows
the C model, these fix the integration, not the model):
- FIX-1 (2026-11-19, top-level co-sim integration): indexed AR
  read for SAR. The core tied the ctrl's ar_rd_i to o_ar =
  AR[ARP]; SAR stores AR[(op>>8)&7] (exec_hi_80_9f, c5x_core.c
  lines 1901-1904), so SAR with any other register stored the
  wrong value. Added i_ar_rd_sel / o_ar_rd = ar_q[i_ar_rd_sel]
  (combinational read of the pre-edge AR file, so a SAR whose
  ea() also switches ARP still stores the old AR, as in C).
  Added the full-file observation outputs o_ar_all =
  {AR7..AR0} and o_stack_all = {stack[7]..stack[0]} (stack
  pointer already on o_sp) so the co-sim can compare the whole
  AR file and stack and verify external-MMR reads of AR0-7.
  Observation-only: no existing port, timing, latency or
  handshake behaviour changes.

PIPELINE SPLIT (2026-11-20, Worker B, converged plan sections
2/5/7/8; audit docs/pipeline-hazards.md sections 2/3/4):
- D-part (combinational): the ARAU is ONE combinational function
  (arau_next_val) used by D for the initial EA/descriptor and by
  E/R for per-iteration re-evaluation during RPT replay. D
  computes the effective address and an AR-update DESCRIPTOR --
  (ar id, mode, ARP-switch flag), mode in {none, +1, -1, +INDX,
  -INDX, bitrev+INDX, bitrev-INDX} plus the ADRK/SBRK +-k8 modes
  -- and NEVER a precomputed new AR value: ea() returns the
  current AR and applies the update as a function of the current
  AR (audit section 3: circular wrap tests ar == CBER on the
  PRE-step value, bank 1 wins; bit-reverse computes
  bitrev16(bitrev16(a) +/- bitrev16(indx)) from the current
  value; the ARP switch runs AFTER the update). The descriptor is
  re-evaluated per iteration from the live AR by the ARAU,
  reading CBCR/CBER/CBSR/INDX live at application time.
- E-part (sequential): the AR file commit, stack, status regs.
  The AR file has exactly one writer: E (ea commit, descriptor
  commit, register-file write port -- in that priority order,
  the write port winning). D never writes state.
- D-stage sources for Worker A's H1/H1a detection (audit
  finding F-2): o_d_src_* expose the AR/INDX/DP/ARP/circular
  sources plus the R-address registers ACC (TBLR/TBLW pfc) and
  BMAR (BLPD-bmar/BLDD-bmar/MADS/MADD pfc). ACC/BMAR use is
  decode-derived, driven in on i_d_pfc_acc / i_d_pfc_bmar; the
  rest is derived from i_op and the live ARP/DP. All D-source
  and descriptor outputs are gated by i_d_ea_use (decode-derived:
  the instruction uses ea()/upd_ar); when it is low they read 0.
- D-stage write targets for A to latch into the R/E pipeline
  registers: o_d_wrt_* (descriptor AR write, ARP switch, AR0
  mirror). ST0/ST1/PMST/DP/TREG/MMR-dynamic targets are NOT
  derived here (they need the decode bundle, which Worker A
  owns in c5x_ctl_pkg.sv); the exact fields A must add are
  listed in the delivery report, not invented here.
- E-stage write targets (actual writes this cycle):
  o_e_wrt_ar_valid/id, o_e_wrt_arp_sw, o_e_wrt_indx_arcr.
- Special orders (audit section 3), how each is served:
  SPLK ea() BEFORE the immediate fetch -- D computes ea/descriptor
  in cycle 1, the ctrl fetches the immediate after; XPL/OPL/APL/
  CPL #lk immediate BEFORE ea() -- the ctrl fetches the immediate
  first, then pulses ea/descriptor; B/CALL ea() for side effects
  -- the descriptor commit applies the AR update with no operand
  read; BANZ tests ar[arp]!=0 BEFORE ea() -- o_ar is the live
  combinational AR[ARP], read before any ea/descriptor strobe;
  SAR reads ar[hi] BEFORE ea() -- o_ar_rd, pre-edge value;
  NORM ea() only on the shifting path -- o_d_desc_norm_cond
  flags the descriptor and i_desc_hold (E-side, from the fresh
  ACC) suppresses the commit when ACC is not shifting; MAR ea()
  only if indirect -- the descriptor is valid only when op[7]
  is set; LMMR/SMMR hoist ea() out of the loop (KD-9) -- the
  descriptor is computed once in D and committed once in E,
  the latched EA is reused for all iterations (the ctrl holds
  the descriptor; it must NOT re-commit per iteration).
- The old multi-cycle ea() path (i_ea_en / i_ea_p0 / o_ea /
  o_ea_badop, i_ndx_commit mirror) is UNCHANGED in behaviour;
  its internals now call the same arau_next_val function, so
  the two paths cannot drift apart.
*/

`default_nettype none

module c5x_addr (
    input  logic        clk,
    input  logic        rst_n,

    /*
    Opcode / accumulator / BIO (ea and cond inputs).
    i_op[15:10] is the opcode class used by the core's executor, not
    by this module (ea uses op[7:0], cond uses op[9:0]).
    */
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [15:0] i_op,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [31:0] i_acc,
    input  logic        i_bio,

    /* Effective address: pulse i_ea_en for exactly one cycle. */
    input  logic        i_ea_en,
    input  logic        i_ea_p0,
    output logic [15:0] o_ea,
    output logic        o_ea_badop,

    /* Branch condition (cond()): combinational. */
    output logic        o_cond,

    /* Register-file / MMR write port (one write per cycle). */
    input  logic        i_wr_en,
    input  logic [5:0]  i_wr_sel,
    input  logic [15:0] i_wr_data,

    /* Single-bit status-flag write port (SETC/CLRC, ALU flag writes). */
    input  logic        i_flg_we,
    input  logic [4:0]  i_flg_sel,
    input  logic        i_flg_in,
    /* PM (2 bits) and IPTR (5 bits) write ports. */
    input  logic        i_pm_we,
    input  logic [1:0]  i_pm_in,
    input  logic        i_iptr_we,
    input  logic [4:0]  i_iptr_in,

    /* CMPR: TC <- compare AR[ARP] against ARCR (or AR0 if i_cmpr_ar0). */
    input  logic        i_cmpr_en,
    input  logic [1:0]  i_cmpr_mode, /* 0 ==, 1 <, 2 >, 3 != */
    input  logic        i_cmpr_ar0,

    /* Hardware stack. */
    input  logic        i_push_en,
    input  logic [15:0] i_push_data,
    input  logic        i_pop_en,
    output logic [15:0] o_pop_data,
    output logic [2:0]  o_sp,

    /*
    Interrupts: OR bits into IFR (c5x_irq); IFR is write-1-to-clear
    through the write port (sel WR_IFR).
    */
    input  logic [15:0] i_irq_set,
    output logic        o_irq_pend, /* (ifr & imr) != 0, as check_int */

    /* NDX mirror commit: pulse once at the end of each instruction. */
    input  logic        i_ndx_commit,

    /*
    Single-instruction repeat (handle_rpt).
    i_rpt_setup loads the repeat window (RPT/RPTZ/RPT #k/#lk:
    rpt_start = rpt_end = PC of the repeated instruction, which is
    the PC just past the RPT itself); RPTC itself is loaded through
    the write port (sel WR_RPTC).
    */
    input  logic        i_rpt_setup,
    input  logic [15:0] i_rpt_pc_in,
    input  logic        i_rpt_step,
    input  logic [15:0] i_rpt_ppc, /* PC of instruction just executed */
    input  logic        i_rpt_dec, /* rptc-- (per-instruction loops) */
    output logic        o_rpt_restart, /* rewind PC to o_rpt_pc */
    output logic [15:0] o_rpt_pc,
    output logic        o_rep_cont,

    /* Block repeat (RPTB / handle_braf). */
    input  logic        i_rptb_set,
    input  logic [15:0] i_rptb_pasr,
    input  logic [15:0] i_rptb_paer,
    input  logic        i_braf_check,
    input  logic [15:0] i_pc, /* current PC (past last block word) */
    output logic        o_braf_restart,
    output logic        o_braf_done,

    /* Architectural state readback. */
    output logic [15:0] o_st0,
    output logic [15:0] o_st1,
    output logic [15:0] o_pmst,
    output logic [15:0] o_ar, /* AR[ARP] */
    output logic [2:0]  o_arp,
    output logic [2:0]  o_arb,
    output logic [15:0] o_dp, /* pre-shifted, as stored in C */
    output logic [15:0] o_indx,
    output logic [15:0] o_arcr,
    output logic [31:0] o_rptc, /* signed */
    output logic [31:0] o_brcr, /* signed */
    output logic [15:0] o_rpt_start,
    output logic [15:0] o_rpt_end,
    output logic [15:0] o_pasr,
    output logic [15:0] o_paer,
    output logic [15:0] o_bmar,
    output logic [15:0] o_dbmr,
    output logic [15:0] o_cbsr1,
    output logic [15:0] o_cber1,
    output logic [15:0] o_cbsr2,
    output logic [15:0] o_cber2,
    output logic [7:0]  o_cbcr,
    output logic [15:0] o_ifr,
    output logic [15:0] o_imr,
    output logic        o_tc,
    output logic        o_ov,
    output logic        o_c,
    output logic        o_braf,
    output logic        o_ar0_dirty,

    /*
    Full-file observation outputs (FIX-1): the whole AR file and
    the whole hardware stack as packed vectors, AR0 / stack[0]
    in the low 16 bits. The stack pointer is already exposed as
    o_sp. Combinational, observation-only.
    */
    output logic [127:0] o_ar_all,
    output logic [127:0] o_stack_all,

    /*
    Indexed AR read (FIX-1): the ctrl drives i_ar_rd_sel with
    op_hi[2:0] and reads the selected register on o_ar_rd (the
    SAR source; CMPR/BANZ keep using o_ar = AR[ARP]).
    */
    input  logic [2:0]  i_ar_rd_sel,
    output logic [15:0] o_ar_rd,

    /*
    Pipeline D-part inputs (Worker B, plan sections 2/5).
    i_d_ea_use is decode-derived: the D-stage instruction uses
    ea()/upd_ar (dma opcodes, B/CALL/BANZD side-effect ea, MAR
    indirect, ADRK/SBRK, NORM-conditional). i_d_pfc_acc /
    i_d_pfc_bmar are decode-derived R-address sources (audit
    finding F-2, hazard class H1a): TBLR/TBLW read ACC to form
    the program address, BLPD-bmar/BLDD-bmar/MADS/MADD read
    BMAR. Worker A drives all three from the decode bundle.
    */
    input  logic        i_d_ea_use,
    input  logic        i_d_pfc_acc,
    input  logic        i_d_pfc_bmar,

    /*
    Pipeline E-part descriptor commit (plan section 5 B6). The
    descriptor is re-evaluated from the LIVE AR file at this
    edge, never from a value captured in D. i_desc_hold
    suppresses the commit (NORM: the E-side ACC test says the
    instruction is not shifting, so ea() never ran in C).
    */
    input  logic        i_desc_en,
    input  logic [2:0]  i_desc_ar_id,
    input  logic [3:0]  i_desc_mode,
    input  logic        i_desc_arp_sw,
    input  logic [2:0]  i_desc_new_arp,
    input  logic [7:0]  i_desc_ark,
    input  logic        i_desc_hold,
    input  logic        i_desc_keep_arb,

    /*
    ARAU replay port (plan section 5, converged B3 fix). During
    RPT replay, R's DMEM address is computed by the ARAU from
    the FORWARDED post-update AR (E's pending descriptor output),
    not from the AR flop (which still holds the pre-update
    value). Worker A drives i_arau_ar with the forwarded AR and
    i_arau_mode with the held descriptor; o_arau_ea is the R
    address for the next iteration. CBCR/CBER/CBSR/INDX are read
    live from this module's state, as the plan requires.
    */
    input  logic [15:0] i_arau_ar,
    input  logic [2:0]  i_arau_ar_id,
    input  logic [3:0]  i_arau_mode,
    input  logic [7:0]  i_arau_ark,
    output logic [15:0] o_arau_ea,
    output logic [15:0] o_arau_next,
    output logic        o_arau_badop,

    /*
    Pipeline D-part outputs: descriptor, D-stage sources and
    D-stage write targets (combinational, valid while the
    D-stage opcode is presented on i_op).
    */
    output logic [2:0]  o_d_desc_ar_id,
    output logic [3:0]  o_d_desc_mode,
    output logic        o_d_desc_arp_sw,
    output logic [2:0]  o_d_desc_new_arp,
    output logic [7:0]  o_d_desc_ark,
    output logic        o_d_desc_valid,
    output logic        o_d_ea_badop,       /* the D-stage instruction uses the indirect modifier and it is the reserved one (m = 6/7): C RUN_BADOP */
    output logic        o_d_desc_norm_cond,
    output logic [15:0] o_d_ar_next,
    output logic        o_d_src_ar_use,
    output logic [2:0]  o_d_src_ar_id,
    output logic        o_d_src_indx_use,
    output logic        o_d_src_dp_use,
    output logic        o_d_src_arp_use,
    output logic        o_d_src_circ_use,
    output logic        o_d_src_acc_use,
    output logic        o_d_src_bmar_use,
    output logic        o_d_wrt_ar_valid,
    output logic [2:0]  o_d_wrt_ar_id,
    output logic        o_d_wrt_arp_sw,
    output logic [2:0]  o_d_wrt_arp_id,
    output logic        o_d_wrt_ar0_mirror,

    /*
    Pipeline E-part outputs: the actual AR/ARP/INDX-ARCR writes
    landing at this edge (for Worker A's H1/H2 detection).
    */
    output logic        o_e_wrt_ar_valid,
    output logic [2:0]  o_e_wrt_ar_id,
    output logic        o_e_wrt_arp_sw,
    output logic        o_e_wrt_indx_arcr
);

    /* Write-port selects (MMR map, c5x_core.c mmr_rd/mmr_wr). */
    localparam logic [5:0] WR_IMR     = 6'h04;
    localparam logic [5:0] WR_IFR     = 6'h06;
    localparam logic [5:0] WR_PMST    = 6'h07;
    localparam logic [5:0] WR_RPTC    = 6'h08;
    localparam logic [5:0] WR_BRCR    = 6'h09;
    localparam logic [5:0] WR_PASR    = 6'h0A;
    localparam logic [5:0] WR_PAER    = 6'h0B;
    localparam logic [5:0] WR_DBMR    = 6'h0F;
    localparam logic [5:0] WR_AR0     = 6'h10;  /* AR0..AR7: 6'h10..6'h17 */
    localparam logic [5:0] WR_AR_LAST = WR_AR0 + 6'd7;  /* AR7, last AR select */
    localparam logic [5:0] WR_INDX    = 6'h18;
    localparam logic [5:0] WR_ARCR    = 6'h19;
    localparam logic [5:0] WR_CBSR1   = 6'h1A;
    localparam logic [5:0] WR_CBER1   = 6'h1B;
    localparam logic [5:0] WR_CBSR2   = 6'h1C;
    localparam logic [5:0] WR_CBER2   = 6'h1D;
    localparam logic [5:0] WR_CBCR    = 6'h1E;
    localparam logic [5:0] WR_BMAR    = 6'h1F;
    localparam logic [5:0] WR_ST0     = 6'h20;  /* c5x_set(ST0): ARP/OV/OVM/INTM/DP */
    localparam logic [5:0] WR_ST1     = 6'h21;  /* c5x_set(ST1): ARB/CNF/TC/SXM/C/HM/XF/PM */
    localparam logic [5:0] WR_DP      = 6'h22;  /* LDP/LDPK: (d & 0x1ff) << 7 */
    localparam logic [5:0] WR_ARB     = 6'h23;  /* restore ARB after the LST #0 ea() */
    localparam logic [5:0] WR_ARP     = 6'h24;  /* direct ARP load */
    localparam logic [5:0] WR_ST0L    = 6'h25;  /* LST #0 (exec1 0x0E): ARP/OV/OVM/DP, INTM not loaded */
    localparam logic [5:0] WR_ST1L    = 6'h26;  /* LST #1 (exec1 0x0F): ARB and ARP from word */

    /* Flag-write selects (single-bit status fields). */
    localparam logic [4:0] FLG_OV   = 5'd0;
    localparam logic [4:0] FLG_OVM  = 5'd1;
    localparam logic [4:0] FLG_INTM = 5'd2;
    localparam logic [4:0] FLG_C    = 5'd3;
    localparam logic [4:0] FLG_CNF  = 5'd4;
    localparam logic [4:0] FLG_SXM  = 5'd5;
    localparam logic [4:0] FLG_HM   = 5'd6;
    localparam logic [4:0] FLG_XF   = 5'd7;
    localparam logic [4:0] FLG_TC   = 5'd8;
    localparam logic [4:0] FLG_NDX  = 5'd9;
    localparam logic [4:0] FLG_TRM  = 5'd10;
    localparam logic [4:0] FLG_BRAF = 5'd11;
    localparam logic [4:0] FLG_RAM  = 5'd12;
    localparam logic [4:0] FLG_OVLY = 5'd13;
    localparam logic [4:0] FLG_MPMC = 5'd14;
    localparam logic [4:0] FLG_AVIS = 5'd15;

    /*
    Indirect-addressing modification codes (ea() m[3:1], op[6:3]).
    Source: c5x_core.c ea(), lines 1119-1156; TI TMS320C5x manual,
    indirect addressing modes. 0 none, 1 AR-1, 2 AR+1, 3 unlisted
    (bad opcode), 4 bit-reversed minus INDX, 5 minus INDX,
    6 plus INDX, 7 bit-reversed plus INDX.
    */
    /*
    MOD_NONE takes no step and is covered by the default arm of the
    step case below, so it is intentionally unreferenced here. It is
    named so the full modify-field encoding is visible in one place.
    */
    /* verilator lint_off UNUSEDPARAM */
    localparam logic [2:0] MOD_NONE     = 3'd0;
    /* verilator lint_on UNUSEDPARAM */
    localparam logic [2:0] MOD_DEC      = 3'd1;
    localparam logic [2:0] MOD_INC      = 3'd2;
    localparam logic [2:0] MOD_BADOP    = 3'd3;
    localparam logic [2:0] MOD_BREV_DEC = 3'd4;
    localparam logic [2:0] MOD_INDX_DEC = 3'd5;
    localparam logic [2:0] MOD_INDX_INC = 3'd6;
    localparam logic [2:0] MOD_BREV_INC = 3'd7;

    /*
    AR-update descriptor modes (pipeline plan section 5 B6). The
    descriptor is an OPERATION, never a precomputed value. The
    first seven modes are the plan's set, mapped from the ea()
    modify field; DESC_ARK_DEC/INC cover ADRK/SBRK, which step
    AR[ARP] by +-k8 through upd_ar() directly (c5x_core.c:1834,
    1862 -- circular wrap applies, same as any upd_ar step).
    DESC_BADOP marks the unlisted modification (m = 6/7): the AR
    is not updated, but the ARP switch still runs (ea(),
    c5x_core.c:1119-1156).
    */
    localparam logic [3:0] DESC_NONE     = 4'd0;
    localparam logic [3:0] DESC_DEC      = 4'd1;
    localparam logic [3:0] DESC_INC      = 4'd2;
    localparam logic [3:0] DESC_INDX_DEC = 4'd3;
    localparam logic [3:0] DESC_INDX_INC = 4'd4;
    localparam logic [3:0] DESC_BREV_DEC = 4'd5;
    localparam logic [3:0] DESC_BREV_INC = 4'd6;
    localparam logic [3:0] DESC_BADOP    = 4'd7;
    localparam logic [3:0] DESC_ARK_DEC  = 4'd8;
    localparam logic [3:0] DESC_ARK_INC  = 4'd9;

    /*
    Opcode high bytes with addressing side effects outside the
    generic dma ea() path (c5x_core.c exec_hi_60_7f / 80_9f /
    a0_af). ADRK/SBRK step AR[ARP] without ea(); MAR runs ea()
    only when indirect; NORM runs ea() only on the shifting path.
    */
    localparam logic [7:0] OP_HI_ADRK = 8'h78;
    localparam logic [7:0] OP_HI_SBRK = 8'h7C;
    localparam logic [7:0] OP_HI_MAR  = 8'h8B;
    localparam logic [7:0] OP_HI_NORM = 8'hA0;

    /*
    CMPR compare modes (exec1 CMPR, c5x_core.c lines 2477-2484).
    */
    localparam logic [1:0] CMPR_EQ = 2'd0;
    localparam logic [1:0] CMPR_LT = 2'd1;
    localparam logic [1:0] CMPR_GT = 2'd2;
    /*
    CMPR_NE is the != arm and is covered by the default arm of the
    CMPR case below, so it is intentionally unreferenced here. It is
    named so the full compare-mode encoding is visible in one place.
    */
    /* verilator lint_off UNUSEDPARAM */
    localparam logic [1:0] CMPR_NE = 2'd3;
    /* verilator lint_on UNUSEDPARAM */

    /*
    Branch-condition TP field (cond(), c5x_core.c lines 1195-1203).
    */
    localparam logic [1:0] TP_BIO    = 2'd0;
    localparam logic [1:0] TP_TC_SET = 2'd1;
    localparam logic [1:0] TP_TC_CLR = 2'd2;
    /*
    TP_ALWAYS is the always-true branch condition and is covered by
    the default arm of the TP case below, so it is intentionally
    unreferenced here. It is named so the full TP-field encoding is
    visible in one place.
    */
    /* verilator lint_off UNUSEDPARAM */
    localparam logic [1:0] TP_ALWAYS = 2'd3;
    /* verilator lint_on UNUSEDPARAM */

    /*
    Auxiliary-register count and hardware-stack depth: eight ARs
    (AR0-AR7) and an 8-deep stack (TI TMS320C5x manual).
    */
    localparam int AUX_REG_COUNT = 8;
    localparam int STACK_DEPTH   = 8;

    /* Auxiliary register 0, the mirror source for INDX/ARCR. */
    localparam logic [2:0] AR0_INDEX = 3'd0;

    /*
    ---------------------------------------------------------------
    State
    ---------------------------------------------------------------
    */
    logic [15:0] ar_q [0:AUX_REG_COUNT-1];
    logic [2:0]  arp_q, arb_q;
    logic [15:0] dp_q; /* pre-shifted: {page[8:0], 7'b0} */
    logic        ov_q, ovm_q, intm_q, c_q, cnf_q, tc_q, sxm_q, hm_q, xf_q;
    logic [1:0]  pm_q;
    logic [4:0]  iptr_q;
    logic        avis_q, ovly_q, ram_q, mpmc_q, ndx_q, trm_q, braf_q;
    logic        braf_done_q;       /* BRAF was cleared at the end of the last block pass in the previous clock (a PMST write from that last instruction lands one clock later) */
    logic [15:0] stack_q [0:STACK_DEPTH-1];
    logic [2:0]  sp_q;
    logic signed [31:0] rptc_q, brcr_q;
    logic [15:0] rpt_start_q, rpt_end_q;
    logic        rep_cont_q;
    logic [15:0] ifr_q, imr_q;
    logic        ar0_dirty_q;

    /*
    Preserved across rst_n (c5x_reset does not touch them); power-on 0.
    rpt_start_q/rpt_end_q are in the same preserved set; they live
    in the main register block below (written by the RPT/RPTB
    setup strobes) and are simply not reset.
    */
    logic [15:0] indx_q  = 16'd0,
                 arcr_q  = 16'd0,
                 cbsr1_q = 16'd0,
                 cber1_q = 16'd0,
                 cbsr2_q = 16'd0,
                 cber2_q = 16'd0,
                 bmar_q  = 16'd0,
                 dbmr_q  = 16'd0,
                 pasr_q  = 16'd0,
                 paer_q  = 16'd0;
    logic [7:0]  cbcr_q; /* 8-bit: mmr_wr masks CBCR writes to 0xFF */

    /*
    ---------------------------------------------------------------
    Helpers (mirror the C static functions exactly)
    ---------------------------------------------------------------
    */
    function automatic logic [15:0] bitrev16(input logic [15:0] v);
        bitrev16 = {v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7],
                    v[8], v[9], v[10], v[11], v[12], v[13], v[14], v[15]};
    endfunction

    /*
    upd_ar() next value: step the GIVEN current value, wrapping to
    the block start at the block end when circular addressing is
    enabled for that AR. Bank 1 wins over bank 2 (C lines
    1085-1106). The wrap test is on the PRE-step value.
    */
    function automatic logic [15:0] upd_ar_next_val(
            input logic [15:0] current_ar,
            input logic [2:0] ar_sel,
            input logic signed [15:0] step);
        begin
            if (cbcr_q[3] && (ar_sel == cbcr_q[2:0])) begin
                if (current_ar == cber1_q) upd_ar_next_val = cbsr1_q;
                else upd_ar_next_val = current_ar + step;
            end else if (cbcr_q[7] && (ar_sel == cbcr_q[6:4])) begin
                if (current_ar == cber2_q) upd_ar_next_val = cbsr2_q;
                else upd_ar_next_val = current_ar + step;
            end else begin
                upd_ar_next_val = current_ar + step;
            end
        end
    endfunction

    /*
    circ_end() as a packed pair {hit, start} (C lines 1062-1078).
    Bank 1 wins when both banks select the same AR. Used by the
    bit-reversed modes only: the pre-step address is end-checked,
    the bit-reversed result itself is never wrapped (KD-16).
    */
    function automatic logic [16:0] circ_end_packed(
            input logic [2:0] ar_sel,
            input logic [15:0] candidate_ar);
        begin
            if (cbcr_q[3] && (ar_sel == cbcr_q[2:0]) && (candidate_ar == cber1_q)) begin
                circ_end_packed = {1'b1, cbsr1_q};
            end else if (!(cbcr_q[3] && (ar_sel == cbcr_q[2:0])) &&
                         cbcr_q[7] && (ar_sel == cbcr_q[6:4]) &&
                         (candidate_ar == cber2_q)) begin
                circ_end_packed = {1'b1, cbsr2_q};
            end else begin
                circ_end_packed = {1'b0, 16'd0};
            end
        end
    endfunction

    /*
    Map the ea() modify field (op[6:3] bits [3:1]) onto a
    descriptor mode. One case table, so D, E and the replay port
    all read the same encoding.
    */
    function automatic logic [3:0] op_modify_to_desc(
            input logic [2:0] modify);
        begin
            case (modify)
                MOD_DEC:      op_modify_to_desc = DESC_DEC;
                MOD_INC:      op_modify_to_desc = DESC_INC;
                MOD_INDX_DEC: op_modify_to_desc = DESC_INDX_DEC;
                MOD_INDX_INC: op_modify_to_desc = DESC_INDX_INC;
                MOD_BREV_DEC: op_modify_to_desc = DESC_BREV_DEC;
                MOD_BREV_INC: op_modify_to_desc = DESC_BREV_INC;
                MOD_BADOP:    op_modify_to_desc = DESC_BADOP;
                default:      op_modify_to_desc = DESC_NONE;
            endcase
        end
    endfunction

    /*
    THE ARAU: one combinational function, used by D (initial EA
    and descriptor), by E (descriptor commit) and by R (replay
    re-evaluation from the forwarded AR). It takes the CURRENT AR
    value as an input and returns the post-update value; the
    returned address is always the current value itself. Circular
    and bit-reverse state (CBCR/CBER/CBSR/INDX) is read live from
    this module, never captured in D (plan section 5 B6).
    */
    function automatic logic [15:0] arau_next_val(
            input logic [15:0] current_ar,
            input logic [2:0] ar_sel,
            input logic [3:0] mode,
            input logic [7:0] ark,
            input logic [15:0] indx_v);
        logic [16:0] circ_result;
        logic signed [15:0] ark_step;
        begin
            circ_result = circ_end_packed(ar_sel, current_ar);
            ark_step = $signed({8'b0, ark});
            case (mode)
                DESC_DEC:      arau_next_val = upd_ar_next_val(current_ar, ar_sel, -16'sd1);
                DESC_INC:      arau_next_val = upd_ar_next_val(current_ar, ar_sel, 16'sd1);
                DESC_INDX_DEC: arau_next_val = upd_ar_next_val(current_ar, ar_sel, -$signed(indx_v));
                DESC_INDX_INC: arau_next_val = upd_ar_next_val(current_ar, ar_sel, $signed(indx_v));
                DESC_BREV_DEC: begin
                    if (circ_result[16])
                        arau_next_val = circ_result[15:0];
                    else
                        arau_next_val = bitrev16(bitrev16(current_ar) - bitrev16(indx_v));
                end
                DESC_BREV_INC: begin
                    if (circ_result[16])
                        arau_next_val = circ_result[15:0];
                    else
                        arau_next_val = bitrev16(bitrev16(current_ar) + bitrev16(indx_v));
                end
                DESC_ARK_DEC:  arau_next_val = upd_ar_next_val(current_ar, ar_sel, -ark_step);
                DESC_ARK_INC:  arau_next_val = upd_ar_next_val(current_ar, ar_sel, ark_step);
                default:       arau_next_val = current_ar;
            endcase
        end
    endfunction

    /*
    ---------------------------------------------------------------
    Effective address (ea / ea_p0) -- combinational
    ---------------------------------------------------------------
    */
    logic        ea_indirect;
    logic [3:0]  ea_modify;
    logic [2:0]  ea_new_arp;
    logic [15:0] ea_current_ar; /* AR[ARP], the returned address */
    logic [3:0]  ea_desc_mode;
    logic        ea_is_step, ea_is_brev;
    logic [15:0] ea_ar_next;
    logic        ea_ar_wr;

    assign ea_indirect    = i_op[7];
    assign ea_modify      = i_op[6:3];
    assign ea_new_arp     = i_op[2:0];
    assign ea_current_ar  = ar_q[arp_q];
    assign ea_desc_mode   = op_modify_to_desc(ea_modify[3:1]);
    assign ea_is_step = ea_indirect &&
        ((ea_desc_mode == DESC_DEC) || (ea_desc_mode == DESC_INC) ||
         (ea_desc_mode == DESC_INDX_DEC) || (ea_desc_mode == DESC_INDX_INC));
    assign ea_is_brev = ea_indirect &&
        ((ea_desc_mode == DESC_BREV_DEC) || (ea_desc_mode == DESC_BREV_INC));
    assign o_ea_badop = ea_indirect && (ea_desc_mode == DESC_BADOP);

    /*
    The ea() update, through the one ARAU function: the same call
    the D descriptor, the E descriptor commit and the replay port
    make, so the three paths cannot drift apart. Direct addressing
    never writes the AR file.
    */
    assign ea_ar_next = arau_next_val(ea_current_ar, arp_q, ea_desc_mode, 8'd0, indx_q);
    assign ea_ar_wr = ea_is_step || ea_is_brev;

    assign o_ea = !ea_indirect ? (i_ea_p0 ? {9'd0, i_op[6:0]}
                                          : (dp_q | {9'd0, i_op[6:0]}))
                               : ea_current_ar;

    /*
    ---------------------------------------------------------------
    Pipeline D-part: descriptor, D-stage sources, D-stage write
    targets, ARAU replay port (plan sections 2/4/5).
    ---------------------------------------------------------------
    Descriptor generation from the D-stage opcode. The generic
    dma path takes its mode from the ea() modify field, GATED on
    indirect addressing: for a direct opcode the low bits are
    address bits, not a mode (ea() returns early for direct,
    c5x_core.c:1121, with no AR update and no ARP switch), so a
    direct descriptor is always NONE. The three special opcodes
    are cased explicitly (ADRK/SBRK step without ea(), MAR only
    when indirect, NORM's descriptor is flagged conditional --
    its commit is held in E when ACC is not shifting).
    o_d_desc_valid means "this instruction carries an AR-file or
    ARP update for E to commit": a mode other than none/badop,
    or an ARP switch (badop still switches ARP).
    */
    logic        d_is_ark;
    logic        d_is_mar;
    logic [3:0]  d_desc_mode_w;
    logic        d_desc_arp_sw_w;
    logic        d_desc_ar_wr_w;
    logic [3:0]  d_ea_mode_w;
    assign d_is_ark  = (i_op[15:8] == OP_HI_ADRK) || (i_op[15:8] == OP_HI_SBRK);
    assign d_is_mar  = (i_op[15:8] == OP_HI_MAR);
    assign d_ea_mode_w = ea_indirect ? ea_desc_mode : DESC_NONE;

    always_comb begin
        d_desc_mode_w   = DESC_NONE;
        d_desc_arp_sw_w = 1'b0;
        o_d_desc_ark    = 8'd0;
        o_d_desc_norm_cond = 1'b0;
        o_d_desc_valid  = 1'b0;
        case (i_op[15:8])
            OP_HI_ADRK: begin
                d_desc_mode_w  = DESC_ARK_INC;
                o_d_desc_ark   = i_op[7:0];
                o_d_desc_valid = i_d_ea_use;
            end
            OP_HI_SBRK: begin
                d_desc_mode_w  = DESC_ARK_DEC;
                o_d_desc_ark   = i_op[7:0];
                o_d_desc_valid = i_d_ea_use;
            end
            OP_HI_MAR: begin
                d_desc_mode_w  = d_ea_mode_w;
                d_desc_arp_sw_w = ea_indirect && ea_modify[0];
                o_d_desc_valid = i_d_ea_use && ea_indirect &&
                    (((d_ea_mode_w != DESC_NONE) &&
                      (d_ea_mode_w != DESC_BADOP)) || d_desc_arp_sw_w);
            end
            OP_HI_NORM: begin
                d_desc_mode_w  = d_ea_mode_w;
                d_desc_arp_sw_w = ea_indirect && ea_modify[0];
                o_d_desc_norm_cond = 1'b1;
                o_d_desc_valid = i_d_ea_use &&
                    (((d_ea_mode_w != DESC_NONE) &&
                      (d_ea_mode_w != DESC_BADOP)) || d_desc_arp_sw_w);
            end
            default: begin
                d_desc_mode_w  = d_ea_mode_w;
                d_desc_arp_sw_w = ea_indirect && ea_modify[0];
                o_d_desc_valid = i_d_ea_use &&
                    (((d_ea_mode_w != DESC_NONE) &&
                      (d_ea_mode_w != DESC_BADOP)) || d_desc_arp_sw_w);
            end
        endcase
        d_desc_ar_wr_w = (d_desc_mode_w != DESC_NONE) &&
                         (d_desc_mode_w != DESC_BADOP);
    end
    assign o_d_desc_ar_id   = arp_q;
    assign o_d_desc_mode    = d_desc_mode_w;
    assign o_d_ea_badop     = i_d_ea_use && ea_indirect && (d_ea_mode_w == DESC_BADOP);
    assign o_d_desc_arp_sw  = d_desc_arp_sw_w;
    assign o_d_desc_new_arp = ea_new_arp;
    /*
    o_d_ar_next shares the ea() ARAU result wherever the inputs
    coincide (every non-ARK opcode: the descriptor mode equals
    the ea() mode when indirect, and is NONE when direct, so the
    next value is ea_ar_next or the current AR). Only ADRK/SBRK
    need their own evaluation, and only through upd_ar (a step
    plus circular wrap, no bit-reverse path). Four independent
    ARAU evaluations would otherwise sit in this module (ea, D
    next, E commit, replay port); this sharing keeps it at three
    plus the small ARK step.
    */
    logic signed [15:0] d_ark_step_w;
    assign d_ark_step_w = (i_op[15:8] == OP_HI_ADRK) ?
                          $signed({8'b0, i_op[7:0]}) :
                          -$signed({8'b0, i_op[7:0]});
    always_comb begin
        if (d_is_ark)
            o_d_ar_next = upd_ar_next_val(ea_current_ar, arp_q, d_ark_step_w);
        else if (ea_indirect)
            o_d_ar_next = ea_ar_next;
        else
            o_d_ar_next = ea_current_ar;
    end

    /*
    D-stage sources (audit section 2, finding F-2/H1a). The AR
    file source is the live ARP; INDX is read only by the
    bit-reversed and +-INDX modes; DP only by direct addressing;
    ARP only when it selects the AR (indirect, incl. ADRK/SBRK,
    which step AR[ARP]); circular state only when a real update
    runs (upd_ar or circ_end consult it). ACC/BMAR are the
    decode-driven R-address sources. ARCR is never a D-source
    (only CMPR reads it, in E -- audit section 2.6); map bits
    are never D-sources either (ea() reads no map bit).
    */
    assign o_d_src_ar_use   = i_d_ea_use && (ea_indirect || d_is_ark);
    assign o_d_src_ar_id    = arp_q;
    assign o_d_src_indx_use = i_d_ea_use && ea_indirect &&
        ((ea_desc_mode == DESC_BREV_DEC) || (ea_desc_mode == DESC_BREV_INC) ||
         (ea_desc_mode == DESC_INDX_DEC) || (ea_desc_mode == DESC_INDX_INC));
    assign o_d_src_dp_use   = i_d_ea_use && !ea_indirect && !d_is_ark && !d_is_mar;
    assign o_d_src_arp_use  = o_d_src_ar_use;
    assign o_d_src_circ_use = i_d_ea_use && ea_indirect && d_desc_ar_wr_w;
    assign o_d_src_acc_use  = i_d_pfc_acc;
    assign o_d_src_bmar_use = i_d_pfc_bmar;

    /*
    D-stage write targets (to be latched into the R/E pipeline
    registers by Worker A). The AR0-mirror flag is provisional:
    the mirror decision uses the NDX live at the writer's E
    (audit section 2.4), so A must re-evaluate it at retire
    time; the D value uses the NDX live in D.
    */
    assign o_d_wrt_ar_valid   = o_d_desc_valid && d_desc_ar_wr_w;
    assign o_d_wrt_ar_id      = arp_q;
    assign o_d_wrt_arp_sw     = o_d_desc_valid && d_desc_arp_sw_w;
    assign o_d_wrt_arp_id     = ea_new_arp;
    assign o_d_wrt_ar0_mirror = o_d_wrt_ar_valid && (arp_q == AR0_INDEX) && !ndx_q;

    /*
    ARAU replay port: the returned address is the forwarded AR
    itself; the next value is the descriptor re-evaluated from
    that forwarded value (converged B3 fix).
    */
    assign o_arau_ea     = i_arau_ar;
    assign o_arau_next   = arau_next_val(i_arau_ar, i_arau_ar_id, i_arau_mode,
                                          i_arau_ark, indx_q);
    assign o_arau_badop  = (i_arau_mode == DESC_BADOP);

    /*
    E-stage write targets: the actual AR/ARP/INDX-ARCR writes
    landing at this edge. The descriptor arm is the pipeline
    commit; the ea arm is the multi-cycle commit; the write-port
    arm is the register-file/MMR write. One writer per register
    per cycle in the C model; the priority below (write port,
    then descriptor, then ea) only orders a violation
    deterministically. o_e_wrt_indx_arcr is the NDX-mirror
    commit landing at this edge (mirror state, section (g)).
    */
    logic desc_ar_wr_e;
    logic desc_applies_e;
    logic ea_applies_e;
    logic wr_ar_e;
    assign desc_ar_wr_e  = (i_desc_mode != DESC_NONE) && (i_desc_mode != DESC_BADOP);
    assign desc_applies_e = i_desc_en && !i_desc_hold && desc_ar_wr_e;
    assign ea_applies_e   = i_ea_en && ea_ar_wr;
    assign wr_ar_e        = i_wr_en && (i_wr_sel >= WR_AR0) && (i_wr_sel <= WR_AR_LAST);
    assign o_e_wrt_ar_valid = desc_applies_e || ea_applies_e || wr_ar_e;
    always_comb begin
        if (wr_ar_e)
            o_e_wrt_ar_id = i_wr_sel[2:0];
        else if (desc_applies_e)
            o_e_wrt_ar_id = i_desc_ar_id;
        else
            o_e_wrt_ar_id = arp_q;
    end
    assign o_e_wrt_arp_sw = (i_desc_en && !i_desc_hold && i_desc_arp_sw) ||
                            (i_ea_en && ea_indirect && ea_modify[0]);
    assign o_e_wrt_indx_arcr = i_ndx_commit && (ar0_dirty_q || ar0_written) && !ndx_q;

    /*
    ---------------------------------------------------------------
    Branch condition (cond / zlvc_cond / tp_cond) -- combinational
    ---------------------------------------------------------------
    */
    logic        zlvc_ok, tp_ok;
    logic signed [31:0] acc_signed;
    assign acc_signed = $signed(i_acc);

    always_comb begin
        zlvc_ok = 1'b1;
        /* mask bit 1: OV test (C lines 1168-1176). */
        if (i_op[1]) begin
            if (i_op[5] && !ov_q) zlvc_ok = 1'b0;
            if (!i_op[5] && ov_q) zlvc_ok = 1'b0;
        end
        /* mask bit 0: C test. */
        if (i_op[0]) begin
            if (i_op[4] && !c_q) zlvc_ok = 1'b0;
            if (!i_op[4] && c_q) zlvc_ok = 1'b0;
        end
        /* (mask & 0xC) | ((zlvc >> 2) & 3) == {op[3:2], op[7:6]}. */
        case ({i_op[3:2], i_op[7:6]})
            4'b0100, 4'b0110, 4'b1100: zlvc_ok = zlvc_ok && (acc_signed > 0);
            4'b0101, 4'b0111, 4'b1101: zlvc_ok = zlvc_ok && (acc_signed < 0);
            4'b1000, 4'b1001: zlvc_ok = zlvc_ok && (acc_signed != 0);
            4'b1010, 4'b1011: zlvc_ok = zlvc_ok && (acc_signed == 0);
            4'b1110: zlvc_ok = zlvc_ok && (acc_signed >= 0);
            4'b1111: zlvc_ok = zlvc_ok && (acc_signed <= 0);
            default: zlvc_ok = zlvc_ok;
        endcase
    end

    always_comb begin
        case (i_op[9:8]) /* TP field (C lines 1195-1203) */
            TP_BIO:    tp_ok = !i_bio;
            TP_TC_SET: tp_ok = tc_q;
            TP_TC_CLR: tp_ok = !tc_q;
            default:   tp_ok = 1'b1;
        endcase
    end
    assign o_cond = zlvc_ok && tp_ok;

    /*
    ---------------------------------------------------------------
    Status-register readback (st0_get / st1_get / pmst_get)
    ---------------------------------------------------------------
    ST0: ARP(13), OV(12), OVM(11), 1(10), INTM(9), DP(8..0).
    */
    assign o_st0 = {arp_q, ov_q, ovm_q, 1'b1, intm_q, dp_q[15:7]};
    /*
    ST1: ARB(13), CNF(12), TC(11), SXM(10), C(9), 1(8), 1(7),
    HM(6), 1(5), XF(4), 1(3), 1(2), PM(1..0).
    */
    assign o_st1 = {arb_q, cnf_q, tc_q, sxm_q, c_q, 1'b1, 1'b1,
                    hm_q, 1'b1, xf_q, 1'b1, 1'b1, pm_q};
    /*
    PMST: IPTR(15..11), 0(10..8), AVIS(7), 0(6), OVLY(5), RAM(4),
    MPMC(3), NDX(2), TRM(1), BRAF(0).
    */
    assign o_pmst = {iptr_q, 3'b000, avis_q, 1'b0, ovly_q, ram_q,
                     mpmc_q, ndx_q, trm_q, braf_q};

    /*
    ---------------------------------------------------------------
    Other readback
    ---------------------------------------------------------------
    */
    assign o_ar         = ar_q[arp_q];
    assign o_arp        = arp_q;
    assign o_arb        = arb_q;
    assign o_dp         = dp_q;
    assign o_indx       = indx_q;
    assign o_arcr       = arcr_q;
    assign o_rptc       = rptc_q;
    assign o_brcr       = brcr_q;
    assign o_rpt_start  = rpt_start_q;
    assign o_rpt_end    = rpt_end_q;
    assign o_rep_cont   = rep_cont_q;
    assign o_pasr       = pasr_q;
    assign o_paer       = paer_q;
    assign o_bmar       = bmar_q;
    assign o_dbmr       = dbmr_q;
    assign o_cbsr1      = cbsr1_q;
    assign o_cber1      = cber1_q;
    assign o_cbsr2      = cbsr2_q;
    assign o_cber2      = cber2_q;
    assign o_cbcr       = cbcr_q;
    assign o_ifr        = ifr_q;
    assign o_imr        = imr_q;
    assign o_sp         = sp_q;
    assign o_pop_data   = stack_q[sp_q];
    assign o_tc         = tc_q;
    assign o_ov         = ov_q;
    assign o_c          = c_q;
    assign o_braf       = braf_q;
    assign o_ar0_dirty  = ar0_dirty_q;
    assign o_irq_pend   = (ifr_q & imr_q) != 16'd0;

    /*
    Full-file observation (FIX-1): pure wiring out of the register
    arrays into the packed vectors; no logic, no timing effect.
    */
    assign o_ar_all = {ar_q[7], ar_q[6], ar_q[5], ar_q[4],
                       ar_q[3], ar_q[2], ar_q[1], ar_q[0]};
    assign o_stack_all = {stack_q[7], stack_q[6], stack_q[5], stack_q[4],
                          stack_q[3], stack_q[2], stack_q[1], stack_q[0]};
    /*
    Indexed AR read (FIX-1): combinational select of the pre-edge
    AR file. A SAR that also switches ARP through ea() still reads
    the old AR, exactly as the C model reads it before ea().
    */
    assign o_ar_rd = ar_q[i_ar_rd_sel];

    /*
    Repeat / block-repeat combinational strobes (handle_rpt /
    handle_braf evaluated on the strobe inputs and current state).
    */
    assign o_rpt_restart = i_rpt_step && (rptc_q > 0) &&
                           (i_rpt_ppc == rpt_end_q);
    assign o_rpt_pc      = o_rpt_restart ? rpt_start_q : 16'd0;
    assign o_braf_restart = i_braf_check && braf_q &&
        ((i_pc - 16'd1) == paer_q) && (brcr_q > 0);
    assign o_braf_done   = i_braf_check && braf_q &&
        ((i_pc - 16'd1) == paer_q) && (brcr_q <= 0);

    /*
    ---------------------------------------------------------------
    AR0 write tracking for the NDX mirror.
    The mirror (apply_ar0_mirror) runs after exec1, so a commit in
    the same cycle as an AR0 write must see the post-write AR0.
    ar0_next resolves that with the same priority as the sequential
    block below: register-file write beats the descriptor commit,
    which beats the ea update.
    ---------------------------------------------------------------
    */
    logic        wr_is_ar0;
    logic [15:0] ar0_next;
    logic        ar0_written;
    logic [15:0] desc_next_w;
    logic        desc_ar0_written;
    assign wr_is_ar0 = i_wr_en && (i_wr_sel >= WR_AR0) &&
                       (i_wr_sel <= WR_AR_LAST) &&
                       (i_wr_sel[2:0] == AR0_INDEX);
    assign desc_next_w = arau_next_val(ar_q[i_desc_ar_id], i_desc_ar_id,
                                        i_desc_mode, i_desc_ark, indx_q);
    assign desc_ar0_written = i_desc_en && !i_desc_hold && desc_ar_wr_e &&
                              (i_desc_ar_id == AR0_INDEX);
    always_comb begin
        if (wr_is_ar0)
            ar0_next = i_wr_data;
        else if (desc_ar0_written)
            ar0_next = desc_next_w;
        else if (i_ea_en && ea_ar_wr && (arp_q == AR0_INDEX))
            ar0_next = ea_ar_next;
        else
            ar0_next = ar_q[0];
    end
    assign ar0_written = wr_is_ar0 || desc_ar0_written ||
        (i_ea_en && ea_ar_wr && (arp_q == AR0_INDEX));

    /*
    CMPR compare operand, hoisted out of the four compare arms below.
    All four CMPR modes compare AR[ARP] against the same operand:
    AR0 when i_cmpr_ar0 is set, the ARCR mirror otherwise (c5x_core.c
    lines 2477-2484). One shared select instead of four copies.
    */
    logic [15:0] cmpr_compare_value;
    always_comb begin
        case (i_cmpr_ar0)
            1'b1: cmpr_compare_value = ar_q[0];
            default: cmpr_compare_value = arcr_q;
        endcase
    end

    /*
    ---------------------------------------------------------------
    Sequential state
    ---------------------------------------------------------------
    */
    integer clear_index;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (clear_index = 0; clear_index < AUX_REG_COUNT;
                 clear_index = clear_index + 1) begin
                ar_q[clear_index] <= 16'd0;
                stack_q[clear_index] <= 16'd0;
            end
            arp_q <= 3'd0;
            arb_q <= 3'd0;
            dp_q <= 16'd0;
            ov_q <= 1'b0;
            ovm_q <= 1'b0;
            intm_q <= 1'b1;
            c_q <= 1'b1;
            cnf_q <= 1'b0;
            tc_q <= 1'b0;
            sxm_q <= 1'b1;
            hm_q <= 1'b1;
            xf_q <= 1'b1;
            pm_q <= 2'd0;
            iptr_q <= 5'd0;
            avis_q <= 1'b0;
            ovly_q <= 1'b0;
            ram_q <= 1'b0;
            mpmc_q <= 1'b0;
            ndx_q <= 1'b0;
            trm_q <= 1'b0;
            braf_q <= 1'b0;
            braf_done_q <= 1'b0;
            sp_q <= 3'd0;
            rptc_q <= 32'sd0;
            brcr_q <= 32'sd0;
            rep_cont_q <= 1'b0;
            ifr_q <= 16'd0;
            imr_q <= 16'd0;
            cbcr_q <= 8'd0;
            ar0_dirty_q <= 1'b0;
            /*
            NOT reset (c5x_reset preserves them): indx_q, arcr_q,
            cbsr1_q, cber1_q, cbsr2_q, cber2_q, bmar_q, dbmr_q,
            pasr_q, paer_q, rpt_start_q, rpt_end_q.
            */
        end else begin
            /*
            (a) ea() AR/ARP update (C lines 1119-1156). On a badop
            the AR is not updated, but the ARP switch still happens.
            */
            if (i_ea_en && ea_indirect) begin
                if (ea_ar_wr) begin
                    ar_q[arp_q] <= ea_ar_next;
                    if (arp_q == AR0_INDEX) ar0_dirty_q <= 1'b1;
                end
                if (ea_modify[0]) begin
                    arb_q <= arp_q;
                    arp_q <= ea_new_arp;
                end
            end

            /*
            (b) Single-bit flag writes (SETC/CLRC, ALU flag writes)
                and CMPR (C lines 2477-2484). CMPR is last: it wins
                over a same-cycle flag-port TC write.
            */
            if (i_flg_we) begin
                case (i_flg_sel)
                    FLG_OV:   ov_q   <= i_flg_in;
                    FLG_OVM:  ovm_q  <= i_flg_in;
                    FLG_INTM: intm_q <= i_flg_in;
                    FLG_C:    c_q    <= i_flg_in;
                    FLG_CNF:  cnf_q  <= i_flg_in;
                    FLG_SXM:  sxm_q  <= i_flg_in;
                    FLG_HM:   hm_q   <= i_flg_in;
                    FLG_XF:   xf_q   <= i_flg_in;
                    FLG_TC:   tc_q   <= i_flg_in;
                    FLG_NDX:  ndx_q  <= i_flg_in;
                    FLG_TRM:  trm_q  <= i_flg_in;
                    FLG_BRAF: braf_q <= i_flg_in;
                    FLG_RAM:  ram_q  <= i_flg_in;
                    FLG_OVLY: ovly_q <= i_flg_in;
                    FLG_MPMC: mpmc_q <= i_flg_in;
                    FLG_AVIS: avis_q <= i_flg_in;
                    default: begin end
                endcase
            end
            if (i_pm_we) pm_q <= i_pm_in;
            if (i_iptr_we) iptr_q <= i_iptr_in;
            if (i_cmpr_en) begin
                case (i_cmpr_mode)
                    CMPR_EQ: tc_q <= (ar_q[arp_q] ==
                                   cmpr_compare_value);
                    CMPR_LT: tc_q <= (ar_q[arp_q] <
                                   cmpr_compare_value);
                    CMPR_GT: tc_q <= (ar_q[arp_q] >
                                   cmpr_compare_value);
                    default: tc_q <= (ar_q[arp_q] !=
                                      cmpr_compare_value);
                endcase
            end

            /*
            (c) Hardware stack (C lines 972-985). Push and pop are
                mutually exclusive in the core; if both are asserted
                pop wins for SP. The pop-copy quirk duplicates the
                entry below the old top into the vacated slot:
                stack[sp] <= stack[sp-1] after sp increments.
            */
            if (i_push_en) begin
                sp_q <= sp_q - 3'd1;
                stack_q[sp_q - 3'd1] <= i_push_data;
            end
            if (i_pop_en) begin
                sp_q <= sp_q + 3'd1;
                stack_q[sp_q] <= stack_q[sp_q - 3'd1];
            end

            /*
            (d) Interrupt flags: OR in newly raised bits (c5x_irq).
                The write-1-to-clear below runs after this, so a
                bit set and cleared in the same cycle ends cleared.
            */
            if (i_irq_set != 16'd0)
                ifr_q <= ifr_q | i_irq_set;

            /*
            (e) Repeat state.
            RPT setup (C lines 1417-1418, 2174-2175, 2391-2397):
            rpt_start = rpt_end = PC of the repeated instruction.
            */
            if (i_rpt_setup) begin
                rpt_start_q <= i_rpt_pc_in;
                rpt_end_q   <= i_rpt_pc_in;
            end
            /* RPTB setup (C lines 2401-2407): braf=1, pasr=pc, paer=imm. */
            if (i_rptb_set) begin
                braf_q <= 1'b1;
                pasr_q <= i_rptb_pasr;
                paer_q <= i_rptb_paer;
            end
            /* handle_braf (C lines 2656-2668). */
            braf_done_q <= i_braf_check && braf_q && ((i_pc - 16'd1) == paer_q) && (brcr_q <= 32'sd0);
            if (i_braf_check && braf_q && ((i_pc - 16'd1) == paer_q)) begin
                if (brcr_q > 0)
                    brcr_q <= brcr_q - 32'sd1;
                else
                    braf_q <= 1'b0;
            end
            /* handle_rpt (C lines 2640-2653). */
            if (i_rpt_step) begin
                if (rptc_q > 0) begin
                    if (i_rpt_ppc == rpt_end_q) begin
                        rptc_q <= rptc_q - 32'sd1;
                        rep_cont_q <= 1'b1;
                    end else begin
                        rep_cont_q <= 1'b0;
                    end
                end else begin
                    rptc_q <= 32'sd0;
                    rep_cont_q <= 1'b0;
                end
            end
            /* Per-instruction repeat-loop decrement (exec1 while loops). */
            if (i_rpt_dec)
                rptc_q <= rptc_q - 32'sd1;

            /*
            (e2) Pipeline descriptor commit (plan section 5 B6).
            The descriptor is re-evaluated from the LIVE AR file
            (desc_next_w, same ARAU function as D), so a held
            descriptor applied on successive RPT iterations steps
            from the current AR each time -- exactly the C model's
            per-iteration ea(). The ARP switch runs AFTER the
            update, as in ea(). A held descriptor (NORM not
            shifting) commits nothing. The register-file write
            port below still wins for the same register.
            */
            if (i_desc_en && !i_desc_hold) begin
                if (desc_ar_wr_e) begin
                    ar_q[i_desc_ar_id] <= desc_next_w;
                    if (i_desc_ar_id == AR0_INDEX) ar0_dirty_q <= 1'b1;
                end
                if (i_desc_arp_sw) begin
                    if (!i_desc_keep_arb) arb_q <= arp_q;
                    arp_q <= i_desc_new_arp;
                end
            end

            /*
            (f) Register-file / MMR write port (c5x_set / mmr_wr).
                Last in program order: beats the ea update and the
                flag writes above for the same register.
            */
            if (i_wr_en) begin
                if ((i_wr_sel >= WR_AR0) && (i_wr_sel <= WR_AR_LAST)) begin
                    ar_q[i_wr_sel[2:0]] <= i_wr_data;
                    if (i_wr_sel[2:0] == AR0_INDEX)
                        ar0_dirty_q <= 1'b1;
                end else begin
                    case (i_wr_sel)
                        WR_IMR:  imr_q <= i_wr_data;
                        WR_IFR:  ifr_q <= (ifr_q | i_irq_set) & ~i_wr_data; /* W1C; a bit raised in this same clock (a frame's XINT) survives unless it is the one being cleared */
                        WR_PMST: begin
                            iptr_q <= i_wr_data[15:11];
                            avis_q <= i_wr_data[7];
                            ovly_q <= i_wr_data[5];
                            ram_q  <= i_wr_data[4];
                            mpmc_q <= i_wr_data[3];
                            ndx_q  <= i_wr_data[2];
                            trm_q  <= i_wr_data[1];
                            /* C: the instruction writes PMST first, handle_braf runs after it: at the end of the last block pass the BRAF clear wins over a stored BRAF=1 */
                            braf_q <= i_wr_data[0] && !(braf_done_q || (i_braf_check && ((i_pc - 16'd1) == paer_q) && (brcr_q <= 32'sd0)));
                        end
                        WR_RPTC: rptc_q <= {16'd0, i_wr_data};
                        WR_BRCR: brcr_q <= {16'd0, i_wr_data};
                        WR_PASR: pasr_q <= i_wr_data;
                        WR_PAER: paer_q <= i_wr_data;
                        WR_DBMR: dbmr_q <= i_wr_data;
                        WR_INDX: indx_q <= i_wr_data;
                        WR_ARCR: arcr_q <= i_wr_data;
                        WR_CBSR1: cbsr1_q <= i_wr_data;
                        WR_CBER1: cber1_q <= i_wr_data;
                        WR_CBSR2: cbsr2_q <= i_wr_data;
                        WR_CBER2: cber2_q <= i_wr_data;
                        WR_CBCR: cbcr_q <= i_wr_data[7:0];
                        WR_BMAR: bmar_q <= i_wr_data;
                        WR_ST0: begin
                            arp_q  <= i_wr_data[15:13];
                            ov_q   <= i_wr_data[12];
                            ovm_q  <= i_wr_data[11];
                            intm_q <= i_wr_data[9];
                            dp_q   <= {i_wr_data[8:0], 7'd0};
                        end
                        WR_ST1: begin
                            arb_q <= i_wr_data[15:13];
                            cnf_q <= i_wr_data[12];
                            tc_q  <= i_wr_data[11];
                            sxm_q <= i_wr_data[10];
                            c_q   <= i_wr_data[9];
                            hm_q  <= i_wr_data[6];
                            xf_q  <= i_wr_data[4];
                            pm_q  <= i_wr_data[1:0];
                        end
                        WR_DP:  dp_q <= {i_wr_data[8:0], 7'd0};
                        WR_ARB: arb_q <= i_wr_data[2:0];
                        WR_ARP: arp_q <= i_wr_data[2:0];
                        WR_ST0L: begin
                            arp_q <= i_wr_data[15:13];
                            ov_q  <= i_wr_data[12];
                            ovm_q <= i_wr_data[11];
                            dp_q  <= {i_wr_data[8:0], 7'd0};
                        end
                        WR_ST1L: begin
                            arb_q <= i_wr_data[15:13];
                            arp_q <= i_wr_data[15:13];
                            cnf_q <= i_wr_data[12];
                            tc_q  <= i_wr_data[11];
                            sxm_q <= i_wr_data[10];
                            c_q   <= i_wr_data[9];
                            hm_q  <= i_wr_data[6];
                            xf_q  <= i_wr_data[4];
                            pm_q  <= i_wr_data[1:0];
                        end
                        default: begin end
                    endcase
                end
            end

            /*
            (g) NDX mirror commit (apply_ar0_mirror, C lines
                2756-2763). Runs last: it clears the dirty flag set
                by an AR0 write in this same cycle, and mirrors the
                post-write AR0 value (ar0_next).
            */
            if (i_ndx_commit &&
                (ar0_dirty_q || ar0_written)) begin
                if (!ndx_q) begin
                    indx_q <= ar0_next;
                    arcr_q <= ar0_next;
                end
                ar0_dirty_q <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
