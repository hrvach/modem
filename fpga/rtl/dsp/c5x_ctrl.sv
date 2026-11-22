`default_nettype none
/* verilator lint_off DECLFILENAME */
/* verilator lint_off IMPORTSTAR */

/*
c5x_pipe_ctrl (in c5x_ctrl.sv) -- pipelined control for the TMS320C5x
DSP core (Cyclone V).  Converged pipeline plan 2026-11-20, sections
2-9.  Replaces the multi-cycle FSM (states RESET..RESTORE, deleted;
kept as reference in hidden_files/pre-pipeline/).
Function: four stages F/D/R/E, one instruction per clock in steady
  state.  Hazard detection (H1/H1a/H1b/H2/H3/H4/H5/H6/H8/H9/H10),
  repeat mechanisms (a) opcode-internal loops and (b) PC-rewind
  replay with RPTB fetch redirect, delay slots, XC window,
  interrupt entry at retirement only, IDLE/IDLE2 park and wake,
  retire-time cycle accounting, and the stall-counter observation
  outputs (plan section 9).
Talks to: c5x_decode (D-stage word in, micro-op out); c5x_alu (E
  micro-op in, flags and write targets out); c5x_addr (D descriptor
  and sources in, E descriptor commit and register writes out);
  c5x_mem (fetch, R read, E deferred read, E write, PMEM write,
  IO handshake, wall-clock timer); the top level (pipeline
  registers F/D, D/R, R/E and the fetch PC live there; this module
  drives their load/hold/flush controls).
Does not model: the ALU datapath, the address unit, the memories
  and the timer (owned by workers B and C); any model-cycle timer
  (B1 -- the timer is C's wall-clock tick_timer in c5x_mem.sv).
Source: research_notes/courier-firmware/c-port/c/src/dsp/c5x_core.c
  (c5x_run, exec1, delay_slot, save_ctx/restore_ctx, check_int,
  interrupt_held, handle_rpt, handle_braf, instr_cycles,
  apply_ar0_mirror, io_read/io_write/io_ws, mmr_bus) and
  c5x_cyctab.h; docs/pipeline-hazards.md (audit, findings F-1..F-5).
*/

/*
The executor below (ex_* signals) is the verified multi-cycle
execute datapath, kept verbatim.  Its inputs are aliased to the E
bundle and the live architectural state (section "E-stage aliases"):
op_q is the E opcode, imm_q the E immediate, ea_q the E effective
address, d_w the E operand, pc_q the E fall-through PC.  The FSM
states it used to read (state_q) are gone; d_w is now the operand
mux (R data / deferred E data / immediate).  The main output block
that used to drive the FSM's ports is replaced by the E-commit
block below, which maps ex_* onto the new ALU/address/memory
ports.  Three latent multi-cycle bugs are fixed here, per the C
model as spec (see the E-commit block): RETC pops and jumps only
when taken; CC/CCD push only when taken; taken CC/BCNDD/CCD with
op bit 1 set clear OV.
*/

/*
C/OV ownership (OPEN-9, pipeline form): the ALU owns C/OV.  The
ctrl reads them from the ALU's o_c/o_ov (live, authoritative), and
the top builds st0_o/st1_o with the C/OV bits taken from the ALU.
The address unit's ST0[12]/ST1[9] mirror bits are therefore never
read for a decision; no TAIL writeback is needed and none is
implemented.  TC is owned by the address unit (NORM's TC arrives
through the flag port from the ALU's o_tc_next).
*/

/*
Retire protocol (plan section 9, docs/cosim.md): instr_done_o is
a 1-clock registered pulse, high during the clock after the retire
edge.  At 1 retire per clock it stays high across consecutive
retires, so a once-per-clock sampler cannot count retires from its
rising edges; the exact count is retire_cnt_o, and retire_tgl_o
toggles at every retire edge.  retire_cycles_o holds the C-model
charge of the retiring instruction until the next retire, and
cycles_o advances by exactly that charge at the retire edge.
*/

module c5x_pipe_ctrl #(
    parameter logic [15:0] RESET_PC = 16'h8000,
    parameter bit          WALL_TIME = 1'b0,
    parameter bit          FETCH_CHAIN = 1'b1   /* 1: one fetch per clock (back-to-back); 0: one fetch per two clocks */   /* 1: model time is the DSP clock itself (one tick per clock, the C model's fixed 40.32 MHz DSP clock): the board; 0: retire-charged model cycles (co-sim against the C core) */
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        step_i, /* fetch hold: low stops F issuing */
    input  logic [1:0]  bp_en_i,        /* test-bench breakpoints: F stops fetching at bp_pc (the instruction there is not fetched) */
    input  logic [15:0] bp_pc0_i,
    input  logic [15:0] bp_pc1_i,

    /*
    D-stage inputs (top: F/D register, decode, address-unit D part).
    */
    input  c5x_ctl_pkg::c5x_fd_t     fd_i,
    input  c5x_ctl_pkg::c5x_dec_t    d_dec_i,
    input  logic [15:0] d_ea_i,
    input  c5x_ctl_pkg::c5x_ar_desc_t d_desc_i,
    input  logic         d_src_ar_use_i,
    input  logic [2:0]  d_src_ar_id_i,
    input  logic         d_src_indx_use_i,
    input  logic         d_src_dp_use_i,
    input  logic         d_src_arp_use_i,
    input  logic         d_src_circ_use_i,
    input  logic         d_src_acc_use_i,
    input  logic         d_src_bmar_use_i,
    input  logic         d_wrt_ar_valid_i,
    input  logic [2:0]  d_wrt_ar_id_i,
    input  logic         d_wrt_arp_sw_i,
    input  logic [2:0]  d_wrt_arp_id_i,
    input  logic         d_wrt_ar0_mirror_i,

    /* Pipeline bundles (top registers).  Not every bundle field
       is read in E (imm_valid / pfc_valid / xc_left_in / replay /
       replay_last are written in D for the top's observation). */
    /* verilator lint_off UNUSEDSIGNAL */
    input  c5x_ctl_pkg::c5x_pipe_t   dr_i,
    input  c5x_ctl_pkg::c5x_pipe_t   re_i,
    /* verilator lint_on UNUSEDSIGNAL */

    /* Fetch / memory handshake inputs. */
    input  logic        fetch_ack_i,
    input  logic [15:0] fetch_data_i,
    input  logic        pm_wr_flush_i,
    input  logic        r_stall_i,
    input  logic [15:0] r_data_i,
    input  logic [15:0] e_rdata_i,
    input  logic        e_stall_i,
    input  logic        e_io_done_i,
    input  logic [2:0]  e_io_ws_i,
    input  logic        tint_will_raise_i,

    /* Live architectural state (top: ALU / address unit / memory). */
    input  logic [31:0] acc_i,
    input  logic [31:0] accb_i,
    input  logic [31:0] preg_i,
    input  logic [15:0] treg0_i,
    input  logic [15:0] treg1_i,
    input  logic [15:0] treg2_i,
    input  logic [15:0] ar_cur_i,
    input  logic [15:0] ar_rd_i,
    input  logic [15:0] arcr_i,
    input  logic [15:0] indx_i,
    input  logic [15:0] bmar_i,
    input  logic [15:0] dbmr_i,
    input  logic [31:0] rptc_i,
    input  logic [31:0] brcr_i,
    input  logic [15:0] pasr_i,
    input  logic [15:0] paer_i,
    input  logic [15:0] pop_data_i,
    input  logic [15:0] ifr_i,
    input  logic [15:0] imr_i,
    /* verilator lint_off UNUSEDSIGNAL */
    /* Reserved bits of the status words are not read. */
    input  logic [15:0] pmst_i,
    input  logic [15:0] st0_i,
    input  logic [15:0] st1_i,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic        alu_c_i,
    input  logic        alu_ov_i,
    input  logic [31:0] alu_mpy_i,
    input  logic        bio_i,
    input  logic [143:0] ivec_ind_i,
    input  logic        irq_pend_i,
    input  logic [15:0] io_rdata_i,
    input  logic        io_ack_i,
    input  logic [15:0] arau_next_i,
    input  logic [15:0] iowsr_i,
    input  logic [15:0] cwsr_i,

    /*
    Pipeline flow control (top: F/D, D/R, R/E registers, fetch PC).
    */
    output logic        f_hold_o,
    output logic        d_hold_o,
    output logic        r_hold_o,
    output logic        e_hold_o,
    output logic        flush_fdr_o,
    output logic        flush_all_o,
    output logic        fd_load_o,
    output logic        dr_load_o,
    output logic        re_load_o,
    output logic        e_consume_o,
    output c5x_ctl_pkg::c5x_pipe_t   dr_o,
    output c5x_ctl_pkg::c5x_pipe_t   re_o,
    output logic        fetch_req_o,
    output logic [15:0] fetch_addr_o,
    output logic        fetch_is_word2_o,
    output logic        fetch_is_pma_o,
    output logic        rptb_cancel_o,
    output logic        loop_pma_req_o,
    output logic [15:0] loop_pma_addr_o,
    output logic        r_req_o,
    output logic        r2_req_o,     /* MAC/MADS program operand read (pfc + iteration), second PMEM port */
    output logic [15:0] r2_addr_o,
    input  logic [15:0] r2_data_i,
    output logic [15:0] r_addr_o,
    output logic        r_is_prog_o,
    output logic [2:0]  ar_rd_sel_o,
    output logic [15:0] arau_ar_o,
    output logic [2:0]  arau_ar_id_o,
    output logic [3:0]  arau_mode_o,
    output logic [7:0]  arau_ark_o,
    output logic        d_ea_use_o,
    output logic        d_pfc_acc_o,
    output logic        d_pfc_bmar_o,

    /*
    E-stage datapath outputs (top routes them to ALU / address
    unit / memory).
    */
    output logic        alu_exec_o,
    output logic [6:0]  alu_op_o,
    output logic [31:0] alu_b32_o,
    output logic [15:0] alu_b16_o,
    output logic [15:0] alu_mpy_a_o,
    output logic [15:0] alu_mpy_b_o,
    output logic        alu_mpy_unsigned_o,
    output logic [3:0]  alu_shift_o,
    output logic        alu_s16_o,
    output logic        alu_ld_acc_o,
    output logic        alu_ld_accb_o,
    output logic        alu_ld_preg_o,
    output logic        alu_ld_treg0_o,
    output logic        alu_flag_c_we_o,
    output logic        alu_flag_c_in_o,
    output logic        alu_flag_ov_we_o,
    output logic        alu_flag_ov_in_o,
    output logic        alu_treg12_wr_en_o,
    output logic        alu_treg12_sel_o,
    output logic [15:0] alu_treg12_data_o,
    output logic        ar_wr_en_o,
    output logic [2:0]  ar_wr_sel_o,
    output logic [15:0] ar_wr_data_o,
    output logic        st0_ld_en_o,
    output logic [15:0] st0_ld_data_o,
    output logic        st1_ld_en_o,
    output logic [15:0] st1_ld_data_o,
    output logic        pmst_ld_en_o,
    output logic [15:0] pmst_ld_data_o,
    output logic        rptc_ld_en_o,
    output logic [15:0] rptc_ld_data_o,
    output logic        brcr_ld_en_o,
    output logic [31:0] brcr_ld_data_o,
    output logic        addr_wr_en_o,
    output logic [5:0]  addr_wr_sel_o,
    output logic [15:0] addr_wr_data_o,
    output logic        st_bit_en_o,
    output logic [4:0]  st_bit_sel_o,
    output logic        st_bit_val_o,
    output logic        desc_en_o,
    output logic [2:0]  desc_ar_id_o,
    output logic [3:0]  desc_mode_o,
    output logic        desc_arp_sw_o,
    output logic [2:0]  desc_new_arp_o,
    output logic [7:0]  desc_ark_o,
    output logic        desc_hold_o,
    output logic [15:0] fetch_ldpc_o,  /* address of the word that lands this clock (fetch_addr_o already carries the next one on a chained fetch) */
    output logic        desc_keep_arb_o, /* LST #0: the descriptor's ARP switch leaves ARB alone (C saves/restores ARB around ea()) */
    output logic        ndx_commit_o,
    output logic        push_en_o,
    output logic [15:0] push_data_o,
    output logic        pop_en_o,
    output logic        rptc_dec_o,
    output logic        rptb_set_o,
    output logic [15:0] rptb_pasr_o,
    output logic [15:0] rptb_paer_o,
    output logic        rptb_clr_o,
    output logic        braf_check_o,
    output logic [15:0] braf_pc_o,
    output logic [8:0]  irq_ack_o,
    output logic        e_wr_o,
    output logic [15:0] e_wr_addr_o,
    output logic [15:0] e_wr_data_o,
    output logic        e_dmov_o,
    output logic [15:0] e_dmov_src_o,
    output logic        e_wr_flush_en_o,
    output logic        e_rd_req_o,
    output logic [15:0] e_rd_addr_o,
    output logic        e_io_req_o,
    output logic        e_io_rd_o,
    output logic [15:0] e_io_addr_o,
    output logic [15:0] e_io_wdata_o,
    output logic        pm_wr_req_o,
    output logic [15:0] pm_wr_addr_o,
    output logic [15:0] pm_wr_data_o,
    output logic        pm_wr_is_e_o,
    output logic        pm_wr_flush_en_o,

    /*
    Retire / observation outputs (top forwards them unchanged).
    */
    output logic        instr_done_o,
    output logic [31:0] retire_cycles_o,
    output logic        retire_is_intr_o,
    output logic [63:0] retire_cnt_o,
    output logic        retire_tgl_o,
    output logic [15:0] retire_pc_o,
    output logic [15:0] retire_op_o,
    output logic [63:0] cycles_o,
    output logic        idle_o,
    output logic        idle2_o,
    output logic [31:0] mtime_o, /* DSP model time: timer ticks delivered, plus one per IDLE2 clock (the codec frame schedule runs on this, not on wall clocks) */
    output logic        model_tick_o, /* one DSP timer tick: the model cycles charged at retire (and one per IDLE clock) are queued and drained at one per clock */
    output logic        halted_o,
    output logic [63:0] cnt_stall_branch_o,
    output logic [63:0] cnt_stall_2word_o,
    output logic [63:0] cnt_stall_pmem_op_o,
    output logic [63:0] cnt_stall_rptb_setup_o,
    output logic [63:0] cnt_stall_h1_o,
    output logic [63:0] cnt_stall_h1a_o,
    output logic [63:0] cnt_stall_h1b_o,
    output logic [63:0] cnt_stall_h2_o,
    output logic [63:0] cnt_stall_h3_o,
    output logic [63:0] cnt_stall_int_entry_o,
    output logic [63:0] cnt_stall_h10_o,
    output logic [63:0] cnt_stall_rpt_replay_o,
    output logic [63:0] cnt_stall_mac_replay_o,
    output logic [63:0] cnt_stall_xc_o,
    output logic [63:0] cnt_stall_io_wait_o,
    output logic [31:0] obs_sh_acc_o,
    output logic [31:0] obs_sh_accb_o,
    output logic [31:0] obs_sh_preg_o,
    output logic [15:0] obs_sh_treg0_o,
    output logic [15:0] obs_sh_treg1_o,
    output logic [15:0] obs_sh_treg2_o,
    output logic [15:0] obs_sh_arcr_o,
    output logic [15:0] obs_sh_indx_o,
    output logic [15:0] obs_sh_st0_o,
    output logic [15:0] obs_sh_st1_o,
    output logic [15:0] obs_sh_pmst_o
);

    /*
    The package is imported inside the module, not at file scope,
    so its names (WR_*, FLG_*) do not leak into $unit scope and
    hide the address unit's own same-named localparams (which
    would trigger VARHIDDEN when the address unit is elaborated
    alongside this module). The port list above uses fully
    qualified package types for the same reason.
    */
    import c5x_ctl_pkg::*;

    /*
    Next-PC actions (applied at the retire edge, or by the
    delay-slot stack for delayed forms).  Kept from the multi-cycle
    executor: ex_pc_act / ex_pc_tgt in the verbatim block below.
    */
    localparam logic [2:0] PC_SEQ   = 3'd0;
    localparam logic [2:0] PC_JMP   = 3'd1;
    localparam logic [2:0] PC_DSLOT = 3'd2;
    localparam logic [2:0] PC_RET   = 3'd3;
    localparam logic [2:0] PC_IDLE  = 3'd4;

    /* rptc == -1 means "no repeat" (C: rptc is int32_t). */
    localparam logic [31:0] RPTC_MINUS1 = 32'hFFFF_FFFF;

    /* MMR addresses (C mmr_rd / mmr_wr; c5x_addr.sv write selects
       numerically equal these addresses). */
    localparam logic [15:0] MMR_PMST = 16'h0007;
    localparam logic [15:0] MMR_RPTC = 16'h0008;
    localparam logic [15:0] MMR_BRCR = 16'h0009;
    localparam logic [15:0] MMR_PASR = 16'h000A;
    localparam logic [15:0] MMR_PAER = 16'h000B;
    localparam logic [15:0] MMR_TREG0 = 16'h000C;
    localparam logic [15:0] MMR_TREG1 = 16'h000D;
    localparam logic [15:0] MMR_TREG2 = 16'h000E;
    localparam logic [15:0] DM_PERIPH_START = 16'h0020;
    localparam logic [15:0] DM_PERIPH_END = 16'h0050;


    /*
    ------------------------------------------------------------------
    Control state (all in this module; the pipeline registers and
    the fetch PC live in the top level).
    ------------------------------------------------------------------
    */
    logic [15:0] fetch_pc_q; /* next address to fetch */
    logic [15:0] fetch_addr_q; /* address of the in-flight fetch */
    logic        fetch_inflight_q;
    logic        fetch_is_word2_q; /* in-flight fetch is a 2nd word */
    logic        fetch_is_pma_q; /* in-flight fetch is a loop pm read */
    logic [63:0] cycles_q;
    logic [63:0] retire_cnt_q;
    logic        retire_tgl_q;
    logic        instr_done_q;
    logic [31:0] retire_cycles_q;
    logic        retire_is_intr_q;
    logic [15:0] retire_pc_q;
    logic [15:0] retire_op_q;
    logic        halted_q;
    logic [1:0]  idle_q; /* 0 = running, 1 = IDLE, 2 = IDLE2 */
    logic        int_inh_q; /* EINT one-cycle interrupt inhibit */
    logic        xc_new_q; /* XC window: hold the next check */
    logic [2:0]  xc_left_q; /* XC window: words left to protect */
    logic [15:0] io_rep_q; /* IN/OUT repeat port offset (KD-17) */
    logic [15:0] rpt_start_q; /* RPT window start (repeated instr PC) */
    logic [15:0] rpt_end_q; /* RPT window end (= rpt_start_q) */
    logic        rep_cont_q; /* this execution is an RPT repeat */
    logic        rep_first_q; /* ... and it is the first iteration (the RPT just retired): a multi-word instruction is charged its full count then, 1 only from the second iteration on */
    logic [31:0] pending_braf_q; /* RPTB crossings not yet retired */
    logic        ds_in_slot_q;
    logic [2:0]  ds_words_left_q; /* slot words left (2 at entry) */
    logic [2:0]  ds_sp_q; /* stack pointer (0..4, next free) */
    logic [15:0] ds_ppc_q [0:7];
    logic [15:0] ds_tgt_q [0:7];
    logic [2:0]  ds_kind_q [0:7];
    logic        ds_take_q [0:7];
    /* Loop / replay engine state. */
    logic        loop_active_q; /* mechanism (a) loop running in E */
    logic [3:0]  loop_kind_q;
    logic [31:0] loop_cnt_q; /* iterations remaining (incl. current) */
    logic [31:0] loop_total_q; /* total iterations (for the charge) */
    logic [15:0] loop_pfc_q; /* advancing program/data pointer */
    logic [15:0] loop_a_q; /* latched ea (fixed or per-iteration) */
    logic        loop_ea_fixed_q; /* SMMR/LMMR: ea evaluated once */
    logic        loop_needs_pm_q; /* MAC/MADS: extra pm read of pfc */
    logic        replay_active_q; /* mechanism (b) replay running */
    logic [31:0] replay_cnt_q; /* iterations remaining (incl. current) */
    /* No replay-bundle register: the replayed instruction stays
       frozen in E (re_i) and its per-iteration ea is the live AR
       (ea_q override in p02).  No RPTB-stall register: the RPTB
       hold is combinational from the R/E bundles (p03). */
    /* Interrupt entry / restore sequencer state. */
    logic        entry_active_q; /* entry pseudo-instruction in E */
    logic        entry_pend_q; /* interrupt detected at a retire */
    logic        entry_pend2_q; /* second stage: the entry fires two
        clocks after detect, not one -- a one-clock gap leaves
        instr_done high across the instruction retire and the
        entry retire, and the harness counts retires on rising
        edges of instr_done, so the two would merge into one. */
    logic [15:0] entry_ret_pc_q; /* return PC latched at entry_detect */
    logic [4:0]  entry_idx_q; /* IFR bit (0..8) or INTR k (0..31) */
    logic        entry_via_ind_q;
    logic        entry_is_intr_q; /* serving an INTR instruction */
    logic        restore_active_q; /* RETI/RETE restore in E */
    logic [3:0]  rst_ph_q; /* restore phase (0..7) */
    logic        restore_is_rete_q;
    /* Shadow context (C save_ctx / restore_ctx). */
    logic [31:0] sh_acc_q, sh_accb_q, sh_preg_q;
    logic [15:0] sh_treg0_q, sh_treg1_q, sh_treg2_q;
    logic [15:0] sh_arcr_q, sh_indx_q;
    logic [2:0]  sh_arp_q, sh_arb_q;
    logic [8:0]  sh_dp_q;
    logic        sh_ov_q, sh_ovm_q;
    /* INTM and XF are shadowed (saved on entry) even though the
       restore deliberately does not restore them (audit #9; C
       save_ctx saves them, restore_ctx skips them).  They must be
       shadow registers, not the live bits: the C shadow is zero
       at reset, while the live INTM/XF are 1 at reset. */
    logic        sh_intm_q, sh_xf_q;
    logic        sh_cnf_q, sh_tc_q, sh_sxm_q, sh_c_q, sh_hm_q;
    logic [1:0]  sh_pm_q;
    logic [4:0]  sh_iptr_q;
    logic        sh_avis_q, sh_ovly_q, sh_ram_q, sh_mpmc_q, sh_ndx_q;
    logic        sh_trm_q, sh_braf_q;
    /* Stall counters (plan section 9; extra clocks beyond base). */
    logic [63:0] cnt_branch_q, cnt_2word_q, cnt_pmem_op_q;
    logic [63:0] cnt_rptb_setup_q, cnt_h1_q, cnt_h1a_q, cnt_h1b_q;
    logic [63:0] cnt_h2_q, cnt_h3_q, cnt_int_entry_q, cnt_h10_q;
    logic [63:0] cnt_rpt_replay_q, cnt_mac_replay_q, cnt_xc_q;
    logic [63:0] cnt_io_wait_q;

    /*
    ------------------------------------------------------------------
    E-stage aliases: the verbatim executor below reads the
    multi-cycle signal names.  They are wired to the E bundle and
    the live architectural state here, so the executor is unchanged.
    op_q is the E opcode, imm_q the E immediate, ea_q the E
    effective address, d_w the E operand, pc_q the E fall-through
    PC (first word PC + word count).  stat_c / stat_ov come from
    the ALU (it owns C/OV); the other stat_* come from the address
    unit.  mpy_p is the ALU's combinational product.  The port
    names acc_i / preg_i / treg0_i / arcr_i / bmar_i / dbmr_i /
    pmst_i / ar_rd_i / bio_i / ivec_ind_i / ifr_i / imr_i already
    match the executor's names, so no alias is needed for them.
    ------------------------------------------------------------------
    */
    logic [15:0] op_q;
    logic [15:0] imm_q;
    logic [15:0] ea_q;
    logic [15:0] d_w;
    logic [15:0] pc_q;
    logic [15:0] ppc_q;
    logic [1:0]  words_q;
    logic [6:0]  dec_alu_op;
    logic [7:0]  dec_cycles;
    logic [31:0] mpy_p;
    logic        stat_c, stat_tc, stat_ov, stat_ovm, stat_intm;
    logic        stat_sxm, stat_hm, stat_xf, stat_cnf;
    logic [1:0]  stat_pm;
    logic [8:0]  stat_dp;
    logic [2:0]  stat_arp, stat_arb;
    logic        stat_ndx, stat_braf, stat_ram, stat_mpmc;
    logic        stat_ovly, stat_avis, stat_trm;
    logic [4:0]  stat_iptr;
    logic [15:0] pop_data;
    logic [15:0] ar_arp_i;
    logic [4:0]  int_idx_q;

    assign op_q = re_i.op;
    assign imm_q = re_i.imm;
    /* During a mechanism-(b) replay the frozen bundle's ea is
       stale (the AR auto-increments per iteration); the live AR
       is the current iteration's ea.  The descriptor's ar_id
       selects the AR (ar_rd_sel_o, p03). */
    assign ea_q = (replay_active_q && re_i.desc.valid) ? ar_rd_i :
                  re_i.ea;
    assign ppc_q = re_i.pc;
    assign words_q = re_i.dec.words;
    assign dec_alu_op = re_i.dec.alu_op;
    assign dec_cycles = re_i.dec.cycles;
    assign mpy_p = alu_mpy_i;
    assign stat_c = alu_c_i;
    assign stat_ov = alu_ov_i;
    assign stat_tc = st1_i[11];
    assign stat_ovm = st0_i[11];
    assign stat_intm = st0_i[9];
    assign stat_sxm = st1_i[10];
    assign stat_hm = st1_i[6];
    assign stat_xf = st1_i[4];
    assign stat_cnf = st1_i[12];
    assign stat_pm = st1_i[1:0];
    assign stat_dp = st0_i[8:0];
    assign stat_arp = st0_i[15:13];
    assign stat_arb = st1_i[15:13];
    assign stat_ndx = pmst_i[2];
    assign stat_braf = pmst_i[0];
    assign stat_ram = pmst_i[4];
    assign stat_ovly = pmst_i[5];
    assign stat_avis = pmst_i[7];
    assign stat_trm = pmst_i[1];
    assign stat_mpmc = pmst_i[3];
    assign stat_iptr = pmst_i[15:11];
    assign ar_arp_i = ar_cur_i;
    assign int_idx_q = entry_idx_q;
    assign pop_data = pop_data_i;
    /* E fall-through PC (first word PC + word count). */
    always_comb begin
        case (re_i.dec.words)
            2'd2: pc_q = re_i.pc + 16'd2;
            default: pc_q = re_i.pc + 16'd1;
        endcase
    end

    /*
    E operand mux (d_w): the R read data is valid during E
    (o_r_data, registered at the R->E edge); a deferred read is
    serviced in E through o_e_rdata; an IN reads the host data.
    Loop iterations do not use d_w -- the loop engine reads
    o_r_data / o_pm_fetch_data directly (see the loop block).
    */
    logic        e_operand_is_io_w;
    logic [15:0] e_operand_w;
    assign e_operand_is_io_w = re_i.is_io &&
                               (op_q[15:8] == 8'hAF);
    always_comb begin
        if (re_i.deferred)
            e_operand_w = e_rdata_i;
        else if (e_operand_is_io_w)
            e_operand_w = io_rdata_i;
        else if (re_i.ea_use)
            e_operand_w = r_data_i;
        else
            e_operand_w = re_i.imm;
    end
    assign d_w = e_operand_w;

    /*
    Current opcode bytes (E stage).
    */
    logic [7:0] op_hi;
    logic [7:0] op_lo;
    assign op_hi = op_q[15:8];
    assign op_lo = op_q[7:0];

    /* Effective IFR for the interrupt selection: the TINT that
       will raise at this edge (mem o_tint_will_raise) joins IFR
       bit 3 now, so the entry is taken at the first retirement
       after the wall clock on which the expiry lands (not one
       clock late).  The effective pending bit likewise. */
    logic [15:0] ifr_eff_w;
    logic irq_pend_eff_w;
    assign ifr_eff_w = ifr_i | (tint_will_raise_i ? 16'h0008 : 16'd0);
    assign irq_pend_eff_w = irq_pend_i ||
                            (tint_will_raise_i && imr_i[3]);
    /* Branch condition for the E opcode (C cond()). */
    logic cond_q;
    assign cond_q = c5x_cond(op_q, acc_i, stat_tc, stat_ov, stat_c,
                             bio_i);

    /*
    Branch-taken test for the class-1/2 conditional branches
    (BANZ/BCND/CC/RETC/RETCD): ex_ds_take is the taken signal for
    exactly those opcodes; it defaults to 1 for every other opcode,
    so the opcode-range gate matters.
    */
    logic br_taken_q;
    assign br_taken_q = ((op_hi == 8'h7B) ||
                         (op_hi >= 8'hE0 && op_hi <= 8'hE3) ||
                         (op_hi >= 8'hE8 && op_hi <= 8'hEB) ||
                         (op_hi >= 8'hEC && op_hi <= 8'hEF) ||
                         (op_hi >= 8'hFC && op_hi <= 8'hFE)) &&
                        ex_ds_take;

    /*
    seq test for instr_cycles (C: pc == ppc + words after execution;
    RETC uses sp after the pop).  At the retire edge the
    post-execution PC is the branch target when taken, else the
    fall-through PC -- so seq is 1 exactly when the branch is not
    taken, or when a taken branch lands on its own fall-through
    address (KD-14).  For RETC the pop happens exactly when taken,
    so seq is again !taken.  The single expression below covers
    both, with the KD-14 landing case handled by post_pc_w.
    */
    logic [15:0] post_pc_w;
    logic seq_q;
    /* a return's target is the popped stack word (ex_pc_tgt is not assigned for it: it stayed 0, which made a taken return at 0xFFFF look sequential, 0xFFFF + 1 = 0, and charged 2 instead of 4) */
    assign post_pc_w = br_taken_q ? ((ex_pc_act == PC_RET) ? pop_data : ex_pc_tgt) : pc_q;
    assign seq_q = (post_pc_w == (ppc_q + {14'b0, words_q}));

    /*
    Class-1 / class-2 cycle adjustment (C cyc_adj / instr_cycles).
    Returns the total for a NON-repeat, NON-loop execution, before
    slot words / IO wait states / mmr_bus / interrupt entry.
    */
    logic [7:0] base_cyc_q;
    always_comb begin
        base_cyc_q = dec_cycles;
        if (!rep_cont_q) begin
            if (op_hi == 8'h7B || (op_hi >= 8'hE0 && op_hi <= 8'hE3) ||
                (op_hi >= 8'hE8 && op_hi <= 8'hEB) ||
                (op_hi >= 8'hEC && op_hi <= 8'hEF)) begin
                base_cyc_q = seq_q ? 8'd2 : 8'd4; /* taken 4 / not 2 */
            end else if ((op_hi >= 8'hFC && op_hi <= 8'hFE) && seq_q) begin
                base_cyc_q = 8'd2; /* RETCD not-taken-only 2 */
            end
        end else begin
            /*
            Repeat execution: 1 cycle, except IN = 2, OUT = 3
            (C instr_cycles rep_cont: IN 2, OUT 3, else 1).
            */
            case (op_hi)
                8'hAF:   base_cyc_q = 8'd2; /* IN */
                8'h0C:   base_cyc_q = 8'd3; /* OUT */
                default: base_cyc_q = (rep_first_q && (words_q == 2'd2)) ? dec_cycles : 8'd1;
            endcase
        end
    end

    /*
    Opcode predicates as pure functions (used in D for the R-read
    decision and the bundle flags, and in E for the commit).  The
    case tables are the multi-cycle needs_op_addr / needs_dm_rd /
    is_loop_op / loop_kind_next, unchanged.
    */
    function automatic logic is_loop_op_f(input logic [7:0] hi);
        begin
            case (hi)
                8'h09, 8'h57, 8'h89, 8'hA2, 8'hA3, 8'hA4, 8'hA5,
                8'hA6, 8'hA7, 8'hA8, 8'hA9, 8'hAA, 8'hAB, 8'hAC, 8'hAD:
                    is_loop_op_f = 1'b1;
                default: is_loop_op_f = 1'b0;
            endcase
        end
    endfunction

    function automatic logic [3:0] loop_kind_f(input logic [7:0] hi);
        begin
            case (hi)
                8'h09: loop_kind_f = LOOP_SMMR;
                8'h89: loop_kind_f = LOOP_LMMR;
                8'h57: loop_kind_f = LOOP_BLDP;
                8'hA4, 8'hA5: loop_kind_f = LOOP_BLPD;
                8'hA6: loop_kind_f = LOOP_TBLR;
                8'hA7: loop_kind_f = LOOP_TBLW;
                8'hA8, 8'hA9, 8'hAC, 8'hAD: loop_kind_f = LOOP_BLDD;
                8'hA2, 8'hA3: loop_kind_f = LOOP_MAC;
                8'hAA, 8'hAB: loop_kind_f = LOOP_MADS;
                default: loop_kind_f = LOOP_MADS;
            endcase
        end
    endfunction

    function automatic logic needs_dm_rd_f(input logic [7:0] hi);
        begin
            case (hi)
                8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07,
                8'h08, 8'h09, 8'h0A, 8'h0B, 8'h0C, 8'h0D, 8'h0E, 8'h0F,
                8'h10, 8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17,
                8'h18, 8'h19, 8'h1A, 8'h1B, 8'h1C, 8'h1D, 8'h1E, 8'h1F,
                8'h20, 8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26, 8'h27,
                8'h28, 8'h29, 8'h2A, 8'h2B, 8'h2C, 8'h2D, 8'h2E, 8'h2F,
                8'h30, 8'h31, 8'h32, 8'h33, 8'h34, 8'h35, 8'h36, 8'h37,
                8'h38, 8'h39, 8'h3A, 8'h3B, 8'h3C, 8'h3D, 8'h3E, 8'h3F,
                8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h46, 8'h47,
                8'h48, 8'h49, 8'h4A, 8'h4B, 8'h4C, 8'h4D, 8'h4E, 8'h4F,
                8'h50, 8'h51, 8'h52, 8'h53, 8'h54, 8'h55, 8'h57,
                8'h58, 8'h59, 8'h5A, 8'h5B, 8'h5C, 8'h5D, 8'h5E, 8'h5F,
                8'h60, 8'h61, 8'h62, 8'h63, 8'h64, 8'h65, 8'h66, 8'h67,
                8'h68, 8'h69, 8'h6A, 8'h6B, 8'h6C, 8'h6D, 8'h6E, 8'h6F,
                8'h70, 8'h71, 8'h72, 8'h73, 8'h74, 8'h75, 8'h76, 8'h77,
                /* Loop ops that read DMEM via the ea (the pfc
                   readers -- LMMR/BLPD/TBLR/BLDD-pfc -- use
                   r_read_pfc instead and need no ea_use):
                   SMMR 0x09, BLDP 0x57, TBLW 0xA7, MAC/MACD
                   0xA2/0xA3, MADS/MADD 0xAA/0xAB, BLDD-dma
                   0xA9/0xAD.  Without these the R read is never
                   presented and the loop reads 0. */
                8'hA2, 8'hA3, 8'hA7, 8'hA9, 8'hAA, 8'hAB, 8'hAD:
                    needs_dm_rd_f = 1'b1;
                default: needs_dm_rd_f = 1'b0;
            endcase
        end
    endfunction

    function automatic logic needs_op_addr_f(input logic [7:0] hi);
        begin
            case (hi)
                8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07,
                8'h08, 8'h09, 8'h0A, 8'h0B, 8'h0C, 8'h0D, 8'h0E, 8'h0F,
                8'h10, 8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17,
                8'h18, 8'h19, 8'h1A, 8'h1B, 8'h1C, 8'h1D, 8'h1E, 8'h1F,
                8'h20, 8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26, 8'h27,
                8'h28, 8'h29, 8'h2A, 8'h2B, 8'h2C, 8'h2D, 8'h2E, 8'h2F,
                8'h30, 8'h31, 8'h32, 8'h33, 8'h34, 8'h35, 8'h36, 8'h37,
                8'h38, 8'h39, 8'h3A, 8'h3B, 8'h3C, 8'h3D, 8'h3E, 8'h3F,
                8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h46, 8'h47,
                8'h48, 8'h49, 8'h4A, 8'h4B, 8'h4C, 8'h4D, 8'h4E, 8'h4F,
                8'h50, 8'h51, 8'h52, 8'h53, 8'h54, 8'h55, 8'h57,
                8'h58, 8'h59, 8'h5A, 8'h5B, 8'h5C, 8'h5D, 8'h5E, 8'h5F,
                8'h60, 8'h61, 8'h62, 8'h63, 8'h64, 8'h65, 8'h66, 8'h67,
                8'h68, 8'h69, 8'h6A, 8'h6B, 8'h6C, 8'h6D, 8'h6E, 8'h6F,
                8'h70, 8'h71, 8'h72, 8'h73, 8'h74, 8'h75, 8'h76, 8'h77,
                8'h79, 8'h7A, 8'h7B, 8'h7D, 8'h7E, 8'h7F, /* B / CALL / BANZ (and D forms): the indirect mode field still runs ea() (AR update, next ARP) */
                8'h80, 8'h81, 8'h82, 8'h83, 8'h84, 8'h85, 8'h86, 8'h87,
                8'h88, 8'h89, 8'h8A, 8'h8B, 8'h8C, 8'h8D, 8'h8E, 8'h8F,
                8'h90, 8'h91, 8'h92, 8'h93, 8'h94, 8'h95, 8'h96, 8'h97,
                8'h98, 8'h99, 8'h9A, 8'h9B, 8'h9C, 8'h9D, 8'h9E, 8'h9F,
                8'hA0, /* NORM: ea() runs on the shifting path (the commit is held otherwise) */
                8'hA2, 8'hA3, 8'hA4, 8'hA5, 8'hA6, 8'hA7, 8'hA8, 8'hA9,
                8'hAA, 8'hAB, 8'hAC, 8'hAD, 8'hAE, 8'hAF:
                    needs_op_addr_f = 1'b1;
                default: needs_op_addr_f = 1'b0;
            endcase
        end
    endfunction

    /*
    Is the R read deferred to E (H3)?  DRR 0x20, SPC 0x22, TIM 0x24,
    TCR 0x26, IFR 0x06, and MMR 0x50+ / the host window are live or
    side-effecting (audit section 7; c5x_mem.sv mmr_is_deferred_f).
    The address here is the R read address (ea, page-0-masked).
    */
    function automatic logic is_deferred_f(input logic [15:0] a);
        begin
            case (a)
                16'h0006, 16'h0020, 16'h0022, 16'h0024, 16'h0026:
                    is_deferred_f = 1'b1;
                default:
                    /* MMR IO range 0x50-0x5F and the host window
                       only.  Plain DMEM (>= 0x60) is NOT deferred:
                       the old (a >= 0x50) test wrongly deferred
                       every DMEM read at 0x60+, so no R read was
                       issued for it and the E operand fell through
                       to the (zero) E-read port. */
                    is_deferred_f = ((a >= 16'h0050) &&
                                    (a < 16'h0060)) ||
                                   ((a >= 16'hFF50) &&
                                    (a <= 16'hFF5F));
            endcase
        end
    endfunction

    /*
    Is this a dynamic MMR address (a store to it goes through the
    address unit's write port, select = the address itself)?
    */
    function automatic logic is_dyn_mmr_f(input logic [15:0] a);
        begin
            case (a)
                16'h0004, 16'h0006, 16'h0007, 16'h0008, 16'h0009,
                16'h000A, 16'h000B, 16'h000F:
                    is_dyn_mmr_f = 1'b1;
                default:
                    is_dyn_mmr_f = (a >= 16'h0010) && (a <= 16'h001F);
            endcase
        end
    endfunction

    /*
    Does this ALU op write ACC?  All OP_* except ALU_NOP, ALU_LT,
    ALU_MPY, ALU_MPYU, ALU_LPH and ALU_PREG_ZERO write ACC (c5x_alu.sv
    acc_next case table).  Used for the H1a ACC hazard (TBLR/TBLW
    read ACC for their pfc in D).
    */
    function automatic logic alu_op_writes_acc_f(input logic [6:0] op);
        begin
            case (op)
                ALU_NOP, ALU_LT, ALU_MPY, ALU_MPYU, ALU_LPH, ALU_PREG_ZERO:
                    alu_op_writes_acc_f = 1'b0;
                default: alu_op_writes_acc_f = 1'b1;
            endcase
        end
    endfunction

    /*
    ------------------------------------------------------------------
    D stage: decode the F/D word into the D/R bundle, and compute
    the E-write-target set (wrt) used by the hazard checks.  The
    descriptor and the D sources come from the address unit (D
    part); the immediate is the latched second word (fd.word2) for
    2-word instructions.
    ------------------------------------------------------------------
    */
    logic [15:0] d_op;
    logic [7:0]  d_hi;
    logic [7:0]  d_lo;
    logic [15:0] d_ea_masked;
    logic        d_is_loop;
    logic [3:0]  d_loop_kind;
    logic [15:0] d_pfc;
    logic        d_r_read_pfc;
    logic        d_ea_use;
    logic        d_deferred;
    logic        d_is_delayed;
    logic        d_xc_open;
    logic        d_is_lar;
    logic [2:0]  d_lar_ar;
    logic        d_is_ldp;
    logic        d_is_lst0;
    logic        d_is_lst1;
    logic        d_is_flag;
    logic        d_is_rcnf_scnf;
    logic        d_is_spm;
    logic        d_is_reti;
    logic        d_is_rete;
    logic        d_is_restore;
    logic        d_is_rpt;
    logic        d_is_rptb;
    logic        d_is_store;
    logic        d_store_to_mmr;
    logic        d_store_to_pmst;
    logic        d_store_to_treg0;
    logic        d_store_to_treg1;
    logic        d_store_to_treg2;
    logic        d_map_chg;
    c5x_e_wrt_t  d_wrt;

    assign d_op = fd_i.word;
    assign d_hi = d_op[15:8];
    assign d_lo = d_op[7:0];
    /* LAMM / SAMM / SMMR / LMMR mask the ea to page 0 (KD-15). */
    assign d_ea_masked = ((d_hi == 8'h08) || (d_hi == 8'h88) ||
                          (d_hi == 8'h09) || (d_hi == 8'h89)) ?
                         {9'b0, d_ea_i[6:0]} : d_ea_i;
    logic        d_is_adrk_sbrk;
    assign d_is_adrk_sbrk = (d_hi == 8'h78) || (d_hi == 8'h7C);
    assign d_is_loop = is_loop_op_f(d_hi);
    assign d_loop_kind = loop_kind_f(d_hi);
    /* Loop program/data pointer (old loop_pfc_next, unchanged).
       BLDP (0x57) takes its pfc from BMAR (C: pfc = c->bmar),
       not from word2 -- it is a 1-word instruction. */
    always_comb begin
        case (d_hi)
            8'h09, 8'h89, 8'hA5, 8'hA8, 8'hA9,
            8'hA2, 8'hA3: d_pfc = fd_i.word2; /* imm (word2) */
            8'hA6, 8'hA7: d_pfc = acc_i[15:0]; /* TBLR/TBLW: ACC */
            default:      d_pfc = bmar_i; /* BLDP/BLPD/BLDD bmar, MADS/MADD */
        endcase
    end
    /* The R read's source is the pfc (program) for these kinds. */
    /* i_d_ea_use gates the D descriptor (the ea() side effect:
       AR update + ARP switch).  It is true whenever the
       instruction calls ea() -- every dma opcode in
       needs_op_addr_f, including MAR (0x8B, which calls ea()
       for its side effect only and reads no DMEM) -- plus
       ADRK/SBRK.  It is NOT the same as the bundle's ea_use
       (below), which selects the R-read address: a pfc-reading
       op (LMMR/BLPD/...) still calls ea() for its write
       destination and side effect, so its descriptor is valid
       even though its R read uses the pfc. */
    assign d_ea_use_o = needs_op_addr_f(d_hi) || d_is_adrk_sbrk;
    assign d_pfc_acc_o = (d_hi == 8'hA6) || (d_hi == 8'hA7);
    assign d_pfc_bmar_o = (d_hi == 8'h57) || (d_hi == 8'hA4) || (d_hi == 8'hAC) ||
                          (d_hi == 8'hAD) || (d_hi == 8'hAA) ||
                          (d_hi == 8'hAB);
    assign d_r_read_pfc = (d_hi == 8'h89) || (d_hi == 8'hA4) ||
                          (d_hi == 8'hA5) || (d_hi == 8'hA6) ||
                          (d_hi == 8'hA8) || (d_hi == 8'hAC);
    assign d_ea_use = needs_op_addr_f(d_hi) && needs_dm_rd_f(d_hi) &&
                      !d_r_read_pfc;
    assign d_deferred = needs_dm_rd_f(d_hi) && !d_r_read_pfc &&
                        is_deferred_f(d_ea_masked);
    assign d_is_delayed = ((d_hi == 8'h7D) || (d_hi == 8'h7E) ||
                          (d_hi == 8'h7F)) ||
                          ((d_hi >= 8'hF0) && (d_hi <= 8'hF3)) ||
                          ((d_hi >= 8'hF8) && (d_hi <= 8'hFB)) ||
                          ((d_hi >= 8'hFC)) ||
                          ((d_hi == 8'hBE) &&
                           ((d_lo == 8'h21) || (d_lo == 8'h3D)));
    assign d_xc_open = ((d_hi >= 8'hE4) && (d_hi <= 8'hE7)) ||
                       ((d_hi >= 8'hF4) && (d_hi <= 8'hF7));
    assign d_is_lar = (d_hi <= 8'h07) ||
                      ((d_hi >= 8'hB0) && (d_hi <= 8'hB7)) ||
                      ((d_hi == 8'hBF) && (d_lo >= 8'h08) &&
                       (d_lo <= 8'h0F));
    assign d_lar_ar = (d_hi == 8'hBF) ? d_lo[2:0] : d_op[10:8];
    assign d_is_ldp = (d_hi == 8'hBC) || (d_hi == 8'hBD) ||
                      (d_hi == 8'h0D);
    assign d_is_lst0 = (d_hi == 8'h0E);
    assign d_is_lst1 = (d_hi == 8'h0F);
    assign d_is_flag = (d_hi == 8'hBE) && (d_lo >= 8'h40) &&
                       (d_lo <= 8'h4F);
    assign d_is_rcnf_scnf = (d_hi == 8'hBE) &&
                            ((d_lo == 8'h44) || (d_lo == 8'h45));
    assign d_is_spm = (d_hi == 8'hBF) && (d_lo <= 8'h03);
    assign d_is_reti = (d_hi == 8'hBE) && (d_lo == 8'h38);
    assign d_is_rete = (d_hi == 8'hBE) && (d_lo == 8'h3A);
    assign d_is_restore = d_is_reti || d_is_rete;
    assign d_is_rpt = d_dec_i.is_rpt;
    assign d_is_rptb = d_dec_i.is_rptb;
    assign d_is_store = d_dec_i.is_mem_wr;
    assign d_store_to_mmr = d_is_store && is_dyn_mmr_f(d_ea_masked);
    assign d_store_to_pmst = d_is_store &&
                             (d_ea_masked == MMR_PMST);
    assign d_store_to_treg0 = d_is_store &&
                              (d_ea_masked == MMR_TREG0);
    assign d_store_to_treg1 = d_is_store &&
                              (d_ea_masked == MMR_TREG1);
    assign d_store_to_treg2 = d_is_store &&
                              (d_ea_masked == MMR_TREG2);
    assign d_map_chg = d_is_lst1 || d_is_rcnf_scnf ||
                       d_is_restore || d_store_to_pmst;

    /* D write-target set (B's E-write-target set, computed in D). */
    always_comb begin
        d_wrt.wr_ar_valid = d_wrt_ar_valid_i;
        d_wrt.wr_ar_id = d_wrt_ar_id_i;
        d_wrt.wr_ar2_valid = d_is_lar;
        d_wrt.wr_ar2_id = d_lar_ar;
        /* FIX (interrupt/LST ARP hazard): LST #0 / LST #1 load ARP
           directly through ST0/ST1, not through a descriptor ARP
           switch, so d_wrt_arp_sw_i is low for them.  Without this
           a D-stage indirect reader right behind an LST sees the
           stale arp_q (descriptor AR id and address AR), see
           repro_rptb_irq.py.  Mark them as ARP writers so the d_h1
           interlock stalls the reader until the LST has written ARP. */
        d_wrt.wr_arp_sw = d_wrt_arp_sw_i || d_is_lst0 || d_is_lst1;
        d_wrt.wr_arp_id = d_wrt_arp_id_i;
        d_wrt.wr_ar0_mirror = d_wrt_ar0_mirror_i;
        d_wrt.wr_dp = d_is_ldp || d_is_lst0 || d_is_restore;
        d_wrt.wr_st0_mask = 16'd0;
        d_wrt.wr_st1_mask = 16'd0;
        if (d_is_ldp) begin
            d_wrt.wr_st0_mask = 16'h01FF; /* DP (ST0[8:0]) */
        end else if (d_is_lst0) begin
            /* LST #0: ARP, OV, OVM, DP (INTM NOT loaded). */
            d_wrt.wr_st0_mask = 16'hF9FF;
        end else if (d_is_lst1) begin
            /* LST #1: ARP (ST0) and ARB/CNF/TC/SXM/C/HM/XF/PM. */
            d_wrt.wr_st0_mask = 16'hE000;
            d_wrt.wr_st1_mask = 16'hFE53;
        end else if (d_is_flag) begin
            case (d_lo)
                8'h40, 8'h41: d_wrt.wr_st0_mask = 16'h0200; /* INTM */
                8'h42, 8'h43: d_wrt.wr_st0_mask = 16'h0800; /* OVM */
                8'h44, 8'h45: d_wrt.wr_st1_mask = 16'h1000; /* CNF */
                8'h46, 8'h47: d_wrt.wr_st1_mask = 16'h0400; /* SXM */
                8'h48, 8'h49: d_wrt.wr_st1_mask = 16'h0040; /* HM */
                8'h4A, 8'h4B: d_wrt.wr_st1_mask = 16'h0800; /* TC */
                8'h4C, 8'h4D: d_wrt.wr_st1_mask = 16'h0010; /* XF */
                8'h4E, 8'h4F: d_wrt.wr_st1_mask = 16'h0200; /* C */
                default: begin end
            endcase
        end else if (d_is_spm) begin
            d_wrt.wr_st1_mask = 16'h0003; /* PM (ST1[1:0]) */
        end else if (d_is_reti) begin
            d_wrt.wr_st0_mask = 16'hF9FF;
            d_wrt.wr_st1_mask = 16'hFE53;
        end else if (d_is_rete) begin
            /* RETE also clears INTM. */
            d_wrt.wr_st0_mask = 16'hFBFF;
            d_wrt.wr_st1_mask = 16'hFE53;
        end
        d_wrt.wr_pmst_map = d_map_chg;
        d_wrt.wr_treg0 = ((d_dec_i.alu_op == ALU_LT) ||
                          (d_dec_i.alu_op == ALU_LTA) ||
                          (d_dec_i.alu_op == ALU_LTD) ||
                          (d_dec_i.alu_op == ALU_LTS) ||
                          (d_dec_i.alu_op == ALU_LT_NM) ||
                          (d_is_loop &&
                           ((d_loop_kind == LOOP_MAC) ||
                            (d_loop_kind == LOOP_MADS)))) ||
                         d_store_to_treg0;
        d_wrt.wr_treg1 = d_store_to_treg1;
        d_wrt.wr_treg2 = d_store_to_treg2;
        d_wrt.wr_acc = d_is_restore ||
                       (d_is_loop &&
                        ((d_loop_kind == LOOP_TBLR) ||
                         (d_loop_kind == LOOP_MAC) ||
                         (d_loop_kind == LOOP_MADS))) ||
                       (!d_is_loop &&
                        alu_op_writes_acc_f(d_dec_i.alu_op));
        d_wrt.wr_mmr_dyn_valid = d_store_to_mmr;
        d_wrt.wr_mmr_dyn_id = d_ea_masked[4:0];
        d_wrt.wr_rptc = d_is_rpt ||
                        (d_is_store && (d_ea_masked == MMR_RPTC));
        d_wrt.wr_brcr = d_is_rptb ||
                        (d_is_store && (d_ea_masked == MMR_BRCR));
        d_wrt.wr_pasr = d_is_rptb ||
                        (d_is_store && (d_ea_masked == MMR_PASR));
        d_wrt.wr_paer = d_is_rptb ||
                        (d_is_store && (d_ea_masked == MMR_PAER));
    end

    /* D/R bundle (d_bundle_w): the D instruction, fully decoded.
       The dr_o output muxes this with the loop/replay re-issued
       bundle (p09). */
    c5x_pipe_t d_bundle_w;
    always_comb begin
        d_bundle_w.pc = fd_i.pc;
        d_bundle_w.op = fd_i.word;
        d_bundle_w.dec = d_dec_i;
        d_bundle_w.imm = fd_i.word2;
        d_bundle_w.imm_valid = (d_dec_i.words == 2'd2) && fd_i.word2_valid;
        d_bundle_w.ea = d_ea_masked;
        d_bundle_w.pfc = d_pfc;
        d_bundle_w.pfc_valid = d_is_loop;
        d_bundle_w.desc = d_desc_i;
        d_bundle_w.wrt = d_wrt;
        d_bundle_w.map_chg = d_map_chg;
        d_bundle_w.ea_use = d_ea_use;
        d_bundle_w.r_read_pfc = d_r_read_pfc;
        d_bundle_w.deferred = d_deferred;
        d_bundle_w.is_io = d_dec_i.is_io;
        d_bundle_w.is_loop_a = d_is_loop;
        d_bundle_w.loop_kind = d_loop_kind;
        d_bundle_w.is_rptb = d_is_rptb;
        d_bundle_w.is_idle = d_dec_i.is_idle;
        d_bundle_w.is_delayed = d_is_delayed;
        d_bundle_w.xc_open = d_xc_open;
        d_bundle_w.xc_left_in = xc_left_q;
        d_bundle_w.replay = 1'b0;
        d_bundle_w.replay_last = 1'b0;
        d_bundle_w.rpt_start = rpt_start_q;
        d_bundle_w.valid = fd_i.valid;
    end

    /*
    ------------------------------------------------------------------
    Hazard detection (plan section 4).  A D reader stalls while a
    writer of the same register is in R or E; the writer lands at
    its retire edge, so the reader proceeds the cycle after.
    ------------------------------------------------------------------
    */
    logic d_h1_ar_w, d_h1_indx_w, d_h1_dp_w, d_h1_arp_w, d_h1_circ_w;
    logic d_h1_w, d_h1a_acc_w, d_h1a_bmar_w, d_h1a_w;
    logic d_r_wr_ar_w, d_e_wr_ar_w;
    logic d_r_wr_mmr_w, d_e_wr_mmr_w;

    /* The R/E writer's AR id matches the D reader's AR id. */
    assign d_r_wr_ar_w = dr_i.valid &&
        ((dr_i.wrt.wr_ar_valid &&
          (dr_i.wrt.wr_ar_id == d_src_ar_id_i)) ||
         (dr_i.wrt.wr_ar2_valid &&
          (dr_i.wrt.wr_ar2_id == d_src_ar_id_i)) ||
         (dr_i.wrt.wr_mmr_dyn_valid &&
          (dr_i.wrt.wr_mmr_dyn_id ==
           (5'h10 + {2'b0, d_src_ar_id_i}))));
    assign d_e_wr_ar_w = re_i.valid &&
        ((re_i.wrt.wr_ar_valid &&
          (re_i.wrt.wr_ar_id == d_src_ar_id_i)) ||
         (re_i.wrt.wr_ar2_valid &&
          (re_i.wrt.wr_ar2_id == d_src_ar_id_i)) ||
         (re_i.wrt.wr_mmr_dyn_valid &&
          (re_i.wrt.wr_mmr_dyn_id ==
           (5'h10 + {2'b0, d_src_ar_id_i}))));
    assign d_h1_ar_w = d_src_ar_use_i && (d_r_wr_ar_w || d_e_wr_ar_w);
    assign d_h1_indx_w = d_src_indx_use_i &&
        ((dr_i.valid && dr_i.wrt.wr_mmr_dyn_valid &&
          (dr_i.wrt.wr_mmr_dyn_id == WR_INDX[4:0])) ||
         (re_i.valid && re_i.wrt.wr_mmr_dyn_valid &&
          (re_i.wrt.wr_mmr_dyn_id == WR_INDX[4:0])));
    assign d_h1_dp_w = d_src_dp_use_i &&
        ((dr_i.valid && dr_i.wrt.wr_dp) ||
         (re_i.valid && re_i.wrt.wr_dp));
    assign d_h1_arp_w = d_src_arp_use_i &&
        ((dr_i.valid && dr_i.wrt.wr_arp_sw) ||
         (re_i.valid && re_i.wrt.wr_arp_sw));
    /* Circular state: ARCR, CBSR/CBER, CBCR, and the AR0 step. */
    assign d_r_wr_mmr_w = dr_i.valid && dr_i.wrt.wr_mmr_dyn_valid;
    assign d_e_wr_mmr_w = re_i.valid && re_i.wrt.wr_mmr_dyn_valid;
    /* Circular state (ARCR, CBSR/CBER, CBCR, AR0 step): a D
       reader stalls while an R/E writer targets any of them. */
    function automatic logic is_circ_mmr_f(input logic [4:0] id);
        case (id)
            WR_ARCR[4:0], WR_CBSR1[4:0], WR_CBER1[4:0],
            WR_CBSR2[4:0], WR_CBER2[4:0], WR_CBCR[4:0],
            WR_AR0[4:0]: is_circ_mmr_f = 1'b1;
            default: is_circ_mmr_f = 1'b0;
        endcase
    endfunction
    assign d_h1_circ_w = d_src_circ_use_i &&
        ((d_r_wr_mmr_w &&
          is_circ_mmr_f(dr_i.wrt.wr_mmr_dyn_id)) ||
         (d_e_wr_mmr_w &&
          is_circ_mmr_f(re_i.wrt.wr_mmr_dyn_id)));
    assign d_h1_w = d_h1_ar_w || d_h1_indx_w || d_h1_dp_w ||
                    d_h1_arp_w || d_h1_circ_w;
    /* H1a: ACC (TBLR/TBLW pfc) and BMAR (BLPD/BLDD/MADS/MADD pfc). */
    assign d_h1a_acc_w = d_src_acc_use_i &&
        ((dr_i.valid && dr_i.wrt.wr_acc) ||
         (re_i.valid && re_i.wrt.wr_acc));
    assign d_h1a_bmar_w = d_src_bmar_use_i &&
        ((dr_i.valid && dr_i.wrt.wr_mmr_dyn_valid &&
          (dr_i.wrt.wr_mmr_dyn_id == WR_BMAR[4:0])) ||
         (re_i.valid && re_i.wrt.wr_mmr_dyn_valid &&
          (re_i.wrt.wr_mmr_dyn_id == WR_BMAR[4:0])));
    assign d_h1a_w = d_h1a_acc_w || d_h1a_bmar_w;

    /*
    ------------------------------------------------------------------
    Flow control.  Holds propagate backwards (E -> R -> D -> F);
    a flush clears F/D/R at the branch's retire edge.
    ------------------------------------------------------------------
    */
    logic d_stall_h1_w, d_stall_h1a_w, d_need_word2_w, d_hold_w;
    logic h2_hold_w, d_rep_cfg_w, dr_rep_cfg_w, re_rep_cfg_w;
    logic d_hold_map_w, r_hold_map_w, e_hold_map_w, rptb_hold_w;
    logic f_hold_w, r_hold_w, e_hold_w, e_hold_mem_w;
    logic flush_fdr_w, flush_all_w;
    logic r_use_pmem_w;

    assign d_stall_h1_w = fd_i.valid && (d_h1_w || d_h1a_w);
    assign d_stall_h1a_w = fd_i.valid && d_h1a_w;
    assign d_need_word2_w = fd_i.valid &&
                            (d_dec_i.words == 2'd2) &&
                            !fd_i.word2_valid;
    assign d_rep_cfg_w = (d_wrt.wr_brcr || d_wrt.wr_pasr ||
                          d_wrt.wr_paer) && !d_is_rptb;
    assign dr_rep_cfg_w = (dr_i.wrt.wr_brcr || dr_i.wrt.wr_pasr ||
                           dr_i.wrt.wr_paer) && !dr_i.is_rptb;
    assign re_rep_cfg_w = (re_i.wrt.wr_brcr || re_i.wrt.wr_pasr ||
                           re_i.wrt.wr_paer) && !re_i.is_rptb;
    /* H2: map-changing or repeat-config writer in D/R/E; RPTB
       holds F from R (not D -- the D-clock PASR fetch is the
       correct sequential fetch). */
    assign d_hold_map_w = fd_i.valid && (d_map_chg || d_rep_cfg_w);
    assign r_hold_map_w = dr_i.valid && (dr_i.map_chg ||
                                         dr_rep_cfg_w);
    assign e_hold_map_w = re_i.valid && (re_i.map_chg ||
                                         re_rep_cfg_w);
    assign rptb_hold_w = (dr_i.valid && dr_i.is_rptb) ||
                         (re_i.valid && re_i.is_rptb);
    assign h2_hold_w = (fd_i.valid && (d_map_chg || d_rep_cfg_w)) ||
                       (dr_i.valid && (dr_i.map_chg ||
                                       dr_rep_cfg_w ||
                                       dr_i.is_rptb)) ||
                       (re_i.valid && (re_i.map_chg ||
                                       re_rep_cfg_w ||
                                       re_i.is_rptb));
    assign e_hold_mem_w = (re_i.valid && e_stall_i) ||
                          (restore_active_q && (rst_ph_q != 4'd7));
    assign e_hold_w = e_hold_mem_w || entry_pending_w;
    /* A loop / replay freezes R (and hence E, D, F): the frozen
       bundle re-executes in E while the next sequential
       instruction waits in R.  The freeze starts on the loop's
       first iteration and on a rewind (the replay's next
       iteration), so the R/E register is not loaded then. */
    assign r_hold_w = (r_req_o && r_stall_i) || e_hold_w ||
                      loop_active_q || replay_active_q ||
                      (re_i.is_loop_a && (loop_iters_w > 32'd1)) ||
                      rpt_rewind_w;
    assign d_hold_w = d_stall_h1_w || d_need_word2_w || r_hold_w;
    logic bp_hold_w;
    assign bp_hold_w = (bp_en_i[0] && (fetch_pc_q == bp_pc0_i)) || (bp_en_i[1] && (fetch_pc_q == bp_pc1_i));
    assign f_hold_w = d_hold_w || h2_hold_w || loop_active_q ||
                      replay_active_q || !step_i ||
                      (idle_q != 2'd0) || halted_q;
    /* A taken branch/call/return flushes F/D/R; so does an
       interrupt entry (the ISR is a new fetch stream).  An IDLE
       retire flushes too: the instructions prefetched after the
       IDLE must not retire while parked; they are re-fetched
       after the wake + RETE.  A PMEM-write flush must NOT fire
       while a mechanism-(b) replay continues (pm_flush_fire_w):
       the flush clears the frozen replay bundle from R/E while
       replay_active_q stays set, and the replay then holds F/D/R
       forever with no bundle left to retire -- the firmware
       stall at pc 0x8024, cycles_o frozen (Bug 2, 2026-11-20).
       The flush is deferred to the last iteration, which retires
       with replay_continues_w low and flushes normally, so the
       successors are re-fetched fresh and a mid-burst store to a
       fetch address is still picked up then. */
    logic replay_continues_w, pm_flush_fire_w;
    assign replay_continues_w = rpt_rewind_w ||
        (replay_active_q && (replay_cnt_q > 32'd1));
    assign pm_flush_fire_w = e_retire_w && pm_wr_flush_i &&
                             !replay_continues_w;
    assign flush_fdr_w = (e_retire_w && e_branch_flush_w) ||
                         entry_retire_w ||
                         (e_retire_w && re_i.is_idle) ||
                         pm_flush_fire_w;
    assign flush_all_w = 1'b0; /* no whole-pipeline flush in this
                                  design (reset handles it) */
    assign f_hold_o = f_hold_w;
    assign d_hold_o = d_hold_w;
    assign r_hold_o = r_hold_w;
    assign e_hold_o = e_hold_w;
    assign flush_fdr_o = flush_fdr_w;
    assign flush_all_o = flush_all_w;
    assign fd_load_o = fetch_ack_i && fetch_inflight_q &&
                       !flush_fdr_w && !fetch_is_pma_q &&
                       !rptb_cancel_o &&
                       (!f_hold_w || fetch_is_word2_q);
    assign dr_load_o = fd_i.valid && !d_hold_w && !flush_fdr_w;
    assign re_load_o = dr_i.valid && !r_hold_w && !flush_fdr_w;

    /*
    ------------------------------------------------------------------
    Fetch control.  The fetch port is shared: instruction fetch,
    the second word of a 2-word instruction, and (during a loop)
    the loop's program read.  The RPTB redirect is evaluated at
    fetch time against the live BRCR/PASR/PAER.
    Word2 fetch: when D holds a 2-word instruction waiting for
    its second word, d_need_word2_w holds F (d_hold_w), which
    would also block fetch_need_w and deadlock the pipeline --
    the word2 fetch is the fetch D is waiting for.  So the
    fetch is issued when D needs word2 even though F is held,
    and the F/D load accepts a word2 fetch even though F is
    held (a word2 load fills fd_q.word2, it does not overwrite
    the first word).  The RPTB redirect is suppressed for a
    word2 fetch: the word2 address is sequential, never pasr.
    ------------------------------------------------------------------
    */
    logic fetch_need_w;
    logic [15:0] fetch_addr_w;
    logic fetch_is_word2_w, fetch_is_pma_w;
    logic rptb_redirect_w;
    logic [31:0] eff_brcr_w;

    assign eff_brcr_w = brcr_i - pending_braf_q;
    assign rptb_redirect_w = (fetch_pc_q == (paer_i + 16'd1)) &&
                             stat_braf && (brcr_i != 32'd0) &&
                             (eff_brcr_w != 32'd0);
    /* Loop program read (MAC/MADS pma, BLPD/TBLR pfc): the fetch
       port carries it while F is stalled for the loop. */
    /* The loop's program read rides the fetch port.  It starts
       on the loop's first iteration (loop_active_q is set only at
       its edge), so the start condition is explicit. */
    assign fetch_is_pma_w = 1'b0;   /* the MAC/MADS program operand now has its own PMEM read port (r2) */
    assign fetch_is_word2_w = d_need_word2_w && !fetch_is_pma_w;
    /* Back-to-back fetch: the word in flight lands this clock (fd_load_o), so the next address (fetch_pc_q, already advanced) is issued in the same clock: one fetch per clock, 1 IPC on straight code. A dropped request is still re-presented (inflight and no ack). */
    logic fetch_chain_w;
    /* not at the RPTB block end: the landing PAER word may be the first word of a 2-word instruction, whose word2 (PAER+1) must not be redirected to PASR; the next fetch then issues one clock later, knowing it */
    assign fetch_chain_w = FETCH_CHAIN && fetch_inflight_q && fetch_ack_i && fd_load_o &&
                           !(stat_braf && (fetch_addr_q == paer_i));
    assign fetch_need_w = (!fetch_inflight_q || fetch_chain_w) && !flush_fdr_w && !bp_hold_w &&
                            (!f_hold_w || d_need_word2_w);
    assign fetch_addr_w = fetch_is_pma_w ? loop_pma_addr_o :
                          (rptb_redirect_w && !fetch_is_word2_w) ?
                              pasr_i : fetch_pc_q;
    assign fetch_ldpc_o = fetch_addr_q;
    assign fetch_req_o = fetch_need_w ||
                           (fetch_inflight_q && !fetch_ack_i);
    always_comb begin
        if (fetch_inflight_q && !fetch_chain_w)
            fetch_addr_o = fetch_addr_q;
        else
            fetch_addr_o = fetch_addr_w;
    end
    logic fetch_redirect_take_w;
    assign fetch_redirect_take_w = fetch_need_w && rptb_redirect_w &&
                                     !fetch_is_word2_w;
    /* Load-time word2 flag: the arriving fetch data is the second
       word of the instruction in F/D iff that instruction still
       needs its word2.  The issue-time latch (fetch_is_word2_q)
       is stale by one clock: a word2 fetch is issued the same
       clock the opcode lands in F/D, before d_need_word2_w goes
       high, so the latch reads 0 and the immediate would load as
       a first word, overwriting the opcode.  At load time the
       opcode has landed and d_need_word2_w is true.  When F/D
       needs a word2, F is held, so no other fetch can be in
       flight; the arriving data must be the word2. */
    assign fetch_is_word2_o = d_need_word2_w;
    assign fetch_is_pma_o = fetch_is_pma_q;
    /* RPTB D-cancel: the PAER word is a 2-word FIRST word -- the
       speculative PASR fetch is discarded and PAER+1 is fetched.
       Only once the PAER instruction's word2 has already loaded
       (word2_valid): while it is still in flight, the in-flight
       fetch IS the word2 (PAER+1) and must not be cancelled, or
       the block-end instruction stalls forever. */
    assign rptb_cancel_o = fd_i.valid && fd_i.first_word &&
                           (fd_i.pc == paer_i) && stat_braf &&
                           (d_dec_i.words == 2'd2) &&
                           fd_i.word2_valid;

    /*
    ------------------------------------------------------------------
    R-stage presentation.  The R read is the data read (ea), the
    program read (pfc), or -- during replay -- the next iteration's
    read (forwarded post-update AR / forwarded pfc+1).  The MAC
    family's second read (pma) rides the idle fetch port.
    ------------------------------------------------------------------
    */
    logic r_read_presented_w;
    logic [15:0] r_addr_w;
    logic r_is_prog_w;
    logic loop_pma_req_w;
    logic [15:0] loop_pma_addr_w;

    assign loop_pma_req_w = (loop_active_q || replay_active_q) &&
                            loop_needs_pm_q;
    assign loop_pma_addr_w = loop_active_q ? (loop_pfc_q + 16'd1) :
                             (re_i.pfc + 16'd1);
    assign loop_pma_req_o = loop_pma_req_w;
    assign loop_pma_addr_o = loop_pma_addr_w;
    /* Next-iteration read: presented one clock before the
       iteration's E, so o_r_data is valid in E.  The condition
       covers the loop's iterations (active, or the first
       iteration when more follow) and the replay's iterations
       (active, or the rewind that starts one). */
    logic next_iter_read_w;
    assign next_iter_read_w = loop_active_q || replay_active_q ||
                              (re_i.is_loop_a &&
                               (loop_iters_w > 32'd1)) ||
                              rpt_rewind_w ||
                        /* C: the check requires rptc <= 0, and RPT / RPTK / RPT #lk / RPTZ set rptc in their own step: no entry at the retire of the arming instruction either (an interrupt between RPT and its operand is not taken on the real C5x). */
                        (re_i.valid && re_i.wrt.wr_rptc);
    logic r2_req_w;
    logic [15:0] r2_addr_w;
    always_comb begin
        r_read_presented_w = 1'b0;
        r_addr_w = 16'd0;
        r_is_prog_w = 1'b0;
        r2_req_w = 1'b0;
        r2_addr_w = 16'd0;
        if (next_iter_read_w) begin
            /* The next iteration's read, forwarded addresses.
               Only BLPD/TBLR read the pfc via the PM channel;
               LMMR/BLDD read it via the DM channel (C dm_rd).
               A loop's pfc advances per iteration; a replay's
               pfc is the frozen bundle's pfc. */
            if (re_i.r_read_pfc) begin
                r_read_presented_w = 1'b1;
                /* A loop's pfc advances per iteration; a replay's
                   pfc is the frozen bundle's pfc.  The loop
                   registers are set only at the start edge, so
                   the first iteration uses re_i. */
                if (loop_active_q || re_i.is_loop_a)
                    r_addr_w = loop_active_q ? (loop_pfc_q + 16'd1) :
                               (re_i.pfc + 16'd1);
                else
                    r_addr_w = re_i.pfc;
                r_is_prog_w = (re_i.loop_kind == LOOP_BLPD) ||
                              (re_i.loop_kind == LOOP_TBLR);
            end else if (re_i.ea_use) begin
                r_read_presented_w = 1'b1;
                if (re_i.loop_kind == LOOP_MAC || re_i.loop_kind == LOOP_MADS) begin
                    r2_req_w  = 1'b1;
                    r2_addr_w = loop_active_q ? (loop_pfc_q + 16'd1) : (re_i.pfc + 16'd1);
                end
                /* Next iteration's ea: the post-update AR for an
                   indirect mode, the bundle ea for a direct mode
                   (arau_next_i is the live AR there, not the ea)
                   or a fixed MMR (SMMR/LMMR).  Bug 3, 2026-11-20. */
                if (loop_active_q) begin
                    if (loop_ea_fixed_q)
                        r_addr_w = loop_a_q;
                    else if (re_i.desc.valid)
                        r_addr_w = arau_next_i;
                    else
                        r_addr_w = re_i.ea;
                end else if (re_i.is_loop_a) begin
                    if ((re_i.op[15:8] == 8'h09) ||
                        (re_i.op[15:8] == 8'h89))
                        r_addr_w = re_i.ea;
                    else if (re_i.desc.valid)
                        r_addr_w = arau_next_i;
                    else
                        r_addr_w = re_i.ea;
                end else
                    r_addr_w = re_i.desc.valid ? arau_next_i :
                               re_i.ea;
                r_is_prog_w = 1'b0;
            end
        end else if (dr_i.valid && dr_i.ea_use && !dr_i.deferred) begin
            r_read_presented_w = 1'b1;
            r_addr_w = dr_i.ea;
            r_is_prog_w = 1'b0;
            if (dr_i.loop_kind == LOOP_MAC || dr_i.loop_kind == LOOP_MADS) begin
                r2_req_w  = 1'b1;
                r2_addr_w = dr_i.pfc;
            end
        end else if (dr_i.valid && dr_i.r_read_pfc) begin
            r_read_presented_w = 1'b1;
            r_addr_w = dr_i.pfc;
            r_is_prog_w = (dr_i.loop_kind == LOOP_BLPD) ||
                          (dr_i.loop_kind == LOOP_TBLR);
        end
    end
    assign r_use_pmem_w = r_read_presented_w && r_is_prog_w;
    assign r2_req_o = r2_req_w;
    assign r2_addr_o = r2_addr_w;
    /* interrupt vector indirection: the vector word dmem[ivec_ind] is read through the R port in the entry's pend clock (the E read port only serves IO / MMR / external
       reads); its data is valid in the pend2 clock, when the fetch pointer is redirected */
    logic ent_rd_w;
    assign ent_rd_w = entry_pend_q && entry_via_ind_q;
    assign r_req_o = r_read_presented_w || ent_rd_w;
    assign r_addr_o = ent_rd_w ? entry_ind_addr_w : r_addr_w;
    assign r_is_prog_o = ent_rd_w ? 1'b0 : r_is_prog_w;

    /*
    ARAU replay port: the live AR (ar_rd_i, selected below) plus
    the E bundle's descriptor gives the post-update AR
    (o_arau_next), which is the next iteration's read address.
    The ARP switch (if any) applies after the update, so the
    replay reads the AR of the NEW ARP.
    */
    logic [2:0] replay_ar_id_w;
    assign replay_ar_id_w = re_i.desc.arp_sw ? re_i.desc.new_arp :
                            re_i.desc.ar_id;
    /* The desc AR, not op[10:8], while a loop op is in E: the
       first E clock of a loop needs arau_next_i from the
       addressing AR (activation load + first-iteration
       next-iter R read, Bug 3, 2026-11-20).  op[10:8] is the
       SAR field, a different AR (BLPD 0xA5A0: op[10:8] = 5,
       desc AR = 0), so arau_next_i was computed from the wrong
       AR.  Non-loop E clocks are unchanged. */
    assign ar_rd_sel_o = (loop_active_q || replay_active_q ||
                          re_i.is_loop_a || (rptc_i > 32'sd0)) ?
                         replay_ar_id_w : re_i.op[10:8];
    assign arau_ar_o = ar_rd_i;
    assign arau_ar_id_o = replay_ar_id_w;
    assign arau_mode_o = re_i.desc.mode;
    assign arau_ark_o = re_i.desc.ark;

    /* verilator lint_off UNUSEDSIGNAL */

    /*
    ------------------------------------------------------------------
    Execute datapath (combinational).  Computes the datapath
    controls for the instruction in op_q, with the data word d_w:
      d_w = the E operand mux (R read data / deferred E read data /
      IO read data / immediate), see the E-stage aliases above.
    The E-commit block below applies these at the retire edge.
    The C-model operation for each family is noted; the ALU op
    (ex_alu_op) selects the micro-op, ex_alu_* are its operands,
    and the ex_*_ld strobes are the register writes.  Memory
    writes are ex_dm_wr / ex_pm_wr (with address/data).  The
    next-PC action is ex_pc_act (see below) and ex_pc_tgt.
    ------------------------------------------------------------------
    */

    /*
    Next-PC actions (applied by the sequential block at the EXEC
    edge, or by the delay-slot stack for delayed forms).
    */

    logic [6:0]  ex_alu_op;
    logic [31:0] ex_alu_a;
    logic [31:0] ex_alu_b;
    logic [15:0] ex_alu_d;
    logic [3:0]  ex_alu_sh;
    logic        ex_alu_c_in;
    logic        ex_alu_en;
    logic        ex_alu_s16;
    logic        ex_acc_ld;
    logic        ex_acc_ld_sel;
    logic [31:0] ex_acc_data;
    logic        ex_accb_ld;
    logic [31:0] ex_accb_data;
    logic        ex_preg_ld;
    logic [31:0] ex_preg_data;
    logic [2:0]  ex_treg_ld;
    logic [15:0] ex_treg_data;
    logic        ex_mpy_en;
    logic [15:0] ex_mpy_a;
    logic [15:0] ex_mpy_b;
    logic        ex_dm_wr;
    logic [15:0] ex_dm_addr;
    logic [15:0] ex_dm_wdata;
    logic        ex_pm_wr;
    logic [15:0] ex_pm_addr;
    logic [15:0] ex_pm_wdata;
    logic        ex_push_en;
    logic [15:0] ex_push_data;
    logic        ex_pop_en;
    logic [2:0]  ex_pc_act;
    logic [15:0] ex_pc_tgt;
    logic [2:0]  ex_ds_kind;
    logic        ex_ds_take;
    logic        ex_io_req; /* needs the IO handshake (IN/OUT) */
    logic        ex_io_wr;
    logic [15:0] ex_io_port;
    logic [15:0] ex_io_wdata;

    /*
    Effective-address mask (LAMM/SAMM/SMMR/LMMR use page 0: ea & 0x7F).
    SMMR/LMMR mask in the C model (c5x_core.c exec_09/exec_89:
    a = ea(c) & 0x7f); the mask is also applied to loop_a_q in
    OP_DATA, since the addr unit's o_ea is unmasked for them
    (the top drives i_ea_p0 only for SST0/SST1).
    */
    logic ea_mask_p0;
    assign ea_mask_p0 = (op_hi == 8'h08) || (op_hi == 8'h88) ||
                        (op_hi == 8'h09) || (op_hi == 8'h89);

    /*
    dm_internal(a) (C dm_internal): B2 0x60-0x7F (a<0x80), B0/B1
    0x100-0x4FF (B0 leaves data space when CNF=1 for a<0x300),
    SARAM 0x800-0xBFF when OVLY=1.  Used to gate dmov_wr (the
    DMOV/LTD/MACD/MADD destination write, which only happens when
    both the source and a+1 are internal DM and a >= 0x60).
    */
    function automatic logic dm_internal_f(input logic [15:0] a);
        begin
            dm_internal_f = (a < 16'h0080) ||
                ((a >= 16'h0100) && (a < 16'h0500) &&
                 !(stat_cnf && (a < 16'h0300))) ||
                (pmst_i[5] && (a >= 16'h0800) && (a < 16'h0C00));
        end
    endfunction
    function automatic logic dmov_gate_f(input logic [15:0] a);
        begin
            dmov_gate_f = dm_internal_f(a) && (a >= 16'h0060) &&
                          dm_internal_f(a + 16'd1);
        end
    endfunction
    logic dmov_gate_w;
    assign dmov_gate_w = dmov_gate_f(ea_q);

    /*
    PREG scaled by PM (C pscale): PM 0 = none, 1 = <<1, 2 = <<4,
    3 = arithmetic >>6.  Computed here from preg_i / stat_pm so
    the APAC/SPAC/LTA/LTP/LTD/LTS ops can use it as ex_alu_b.
    */
    logic [31:0] pscale_w;
    always_comb begin
        case (stat_pm)
            2'd0: pscale_w = preg_i;
            2'd1: pscale_w = {preg_i[30:0], 1'b0};
            2'd2: pscale_w = {preg_i[27:0], 4'b0};
            default: pscale_w = $signed(preg_i) >>> 6;
        endcase
    end

    /*
    ext(d, sh): SXM ? sign-extended : zero-extended (C ext()).
    */
    logic [31:0] ext_w;
    always_comb begin
        if (stat_sxm)
            ext_w = {{(32-16){d_w[15]}}, d_w} << (op_hi[3:0]);
        else
            ext_w = {16'b0, d_w} << (op_hi[3:0]);
    end

    /*
    ACC << sh (32-bit); SACL takes the low half, SACH the high half.
    */
    logic [31:0] shl_acc_w;
    assign shl_acc_w = acc_i << op_hi[2:0];

    always_comb begin
        /*
        Defaults: no datapath action, PC continues.
        */
        ex_alu_op     = dec_alu_op;
        ex_alu_a      = acc_i;
        ex_alu_b      = 32'd0;
        ex_alu_d      = d_w;
        ex_alu_sh     = op_hi[3:0];
        ex_alu_c_in   = stat_c;
        ex_alu_en     = 1'b0;
        ex_alu_s16    = 1'b0;
        ex_acc_ld     = 1'b0;
        ex_acc_ld_sel = 1'b0;
        ex_acc_data   = 32'd0;
        ex_accb_ld    = 1'b0;
        ex_accb_data  = 32'd0;
        ex_preg_ld    = 1'b0;
        ex_preg_data  = 32'd0;
        ex_treg_ld    = 3'b000;
        ex_treg_data  = 16'd0;
        ex_mpy_en     = 1'b0;
        ex_mpy_a      = 16'd0;
        ex_mpy_b      = 16'd0;
        ex_dm_wr      = 1'b0;
        ex_dm_addr    = ea_q;
        ex_dm_wdata   = 16'd0;
        ex_pm_wr      = 1'b0;
        ex_pm_addr    = 16'd0;
        ex_pm_wdata   = 16'd0;
        ex_push_en    = 1'b0;
        ex_push_data  = 16'd0;
        ex_pop_en     = 1'b0;
        ex_pc_act     = PC_SEQ;
        ex_pc_tgt     = 16'd0;
        ex_ds_kind    = 3'd0;
        ex_ds_take    = 1'b1;
        ex_io_req     = 1'b0;
        ex_io_wr      = 1'b0;
        ex_io_port    = 16'd0;
        ex_io_wdata   = 16'd0;

        case (op_hi)
            /*
            LAR dma: AR[hi] = d.  (ar_wr driven by main block.)
            */
            8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07: begin
            end
            /*
            LAMM: ACC = d (page 0).
            */
            8'h08: begin
                ex_alu_op = ALU_LD_B16Z;
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            /*
            SUBC: ACC = subc(acc, d<<15).
            */
            8'h0A: begin
                ex_alu_op = ALU_SUBC;
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            /*
            RPT dma: rptc = d (rptc_ld driven by main block).
            */
            8'h0B: begin end
            /*
            OUT: io_write(port, d).  Port = imm + io_rep.
            */
            8'h0C: begin
                ex_io_req   = 1'b1;
                ex_io_wr    = 1'b1;
                ex_io_port  = imm_q + io_rep_q;
                ex_io_wdata = d_w;
            end
            /*
            LDP dma: DP = d[8:0] (st0_ld driven by main block).
            */
            8'h0D: begin end
            /*
            LST #0/#1: st0/st1 load (addr_wr driven by main block).
            */
            8'h0E, 8'h0F: begin end
            /*
            LACC / ADD / SUB dma,sh.
            */
            8'h10, 8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17,
            8'h18, 8'h19, 8'h1A, 8'h1B, 8'h1C, 8'h1D, 8'h1E, 8'h1F: begin
                ex_alu_op = ALU_LD_EXT;
                ex_alu_b  = ext_w;
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            8'h20, 8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26, 8'h27,
            8'h28, 8'h29, 8'h2A, 8'h2B, 8'h2C, 8'h2D, 8'h2E, 8'h2F: begin
                ex_alu_op = ALU_ADD_SH;
                ex_alu_b  = ext_w;
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            8'h30, 8'h31, 8'h32, 8'h33, 8'h34, 8'h35, 8'h36, 8'h37,
            8'h38, 8'h39, 8'h3A, 8'h3B, 8'h3C, 8'h3D, 8'h3E, 8'h3F: begin
                ex_alu_op = ALU_SUB_SH;
                ex_alu_b  = ext_w;
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            /*
            BIT: TC = bit (15-shift) of d (st_bit driven by main).
            */
            8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h46, 8'h47,
            8'h48, 8'h49, 8'h4A, 8'h4B, 8'h4C, 8'h4D, 8'h4E, 8'h4F: begin
            end
            /*
            MPYA / MPYS / SQRA / SQRS / MPY / MPYU.
            */
            8'h50: begin /* MPYA: ACC += pscale; PREG = TREG0*d */
                ex_alu_op  = ALU_MPYA;
                ex_alu_b   = pscale_w;
                ex_alu_en  = 1'b1;
                ex_acc_ld  = 1'b1;
                ex_mpy_en  = 1'b1;
                ex_mpy_a   = treg0_i;
                ex_mpy_b   = d_w;
                ex_preg_ld = 1'b1;
                ex_preg_data = mpy_p;
            end
            8'h51: begin /* MPYS: ACC -= pscale; PREG = TREG0*d */
                ex_alu_op  = ALU_MPYS;
                ex_alu_b   = pscale_w;
                ex_alu_en  = 1'b1;
                ex_acc_ld  = 1'b1;
                ex_mpy_en  = 1'b1;
                ex_mpy_a   = treg0_i;
                ex_mpy_b   = d_w;
                ex_preg_ld = 1'b1;
                ex_preg_data = mpy_p;
            end
            8'h52: begin /* SQRA: ACC += pscale; TREG0=d; PREG=d*d */
                ex_alu_op  = ALU_SQRA;
                ex_alu_b   = pscale_w;
                ex_alu_en  = 1'b1;
                ex_acc_ld  = 1'b1;
                ex_treg_ld = 3'b001;
                ex_treg_data = d_w;
                ex_mpy_en  = 1'b1;
                ex_mpy_a   = d_w;
                ex_mpy_b   = d_w;
                ex_preg_ld = 1'b1;
                ex_preg_data = mpy_p;
            end
            8'h53: begin /* SQRS: ACC -= pscale; TREG0=d; PREG=d*d */
                ex_alu_op  = ALU_SQRS;
                ex_alu_b   = pscale_w;
                ex_alu_en  = 1'b1;
                ex_acc_ld  = 1'b1;
                ex_treg_ld = 3'b001;
                ex_treg_data = d_w;
                ex_mpy_en  = 1'b1;
                ex_mpy_a   = d_w;
                ex_mpy_b   = d_w;
                ex_preg_ld = 1'b1;
                ex_preg_data = mpy_p;
            end
            8'h54: begin /* MPY: PREG = TREG0*d */
                ex_alu_op  = ALU_MPY;
                ex_alu_en  = 1'b1;
                ex_mpy_en  = 1'b1;
                ex_mpy_a   = treg0_i;
                ex_mpy_b   = d_w;
                ex_preg_ld = 1'b1;
                ex_preg_data = mpy_p;
            end
            8'h55: begin /* MPYU: PREG = TREG0*d (unsigned) */
                ex_alu_op  = ALU_MPYU;
                ex_alu_en  = 1'b1;
                ex_mpy_en  = 1'b1;
                ex_mpy_a   = treg0_i;
                ex_mpy_b   = d_w;
                ex_preg_ld = 1'b1;
                ex_preg_data = mpy_p;
            end
            /*
            XPL / OPL / APL / CPL (dbmr and #lk): read-modify-write
            on dm (or compare only for CPL).  TC = (result == 0).
            */
            8'h58: begin /* XPL dbmr */
                ex_dm_wr    = 1'b1;
                ex_dm_wdata = d_w ^ dbmr_i;
            end
            8'h59: begin /* OPL dbmr */
                ex_dm_wr    = 1'b1;
                ex_dm_wdata = d_w | dbmr_i;
            end
            8'h5A: begin /* APL dbmr */
                ex_dm_wr    = 1'b1;
                ex_dm_wdata = d_w & dbmr_i;
            end
            8'h5B: begin end /* CPL dbmr (TC only) */
            8'h5C: begin /* XPL #lk (imm fetched before ea) */
                ex_dm_wr    = 1'b1;
                ex_dm_wdata = d_w ^ imm_q;
            end
            8'h5D: begin /* OPL #lk */
                ex_dm_wr    = 1'b1;
                ex_dm_wdata = d_w | imm_q;
            end
            8'h5E: begin /* APL #lk */
                ex_dm_wr    = 1'b1;
                ex_dm_wdata = d_w & imm_q;
            end
            8'h5F: begin end /* CPL #lk (TC only) */
            /*
            ADDC / ADD / ADDS / ADDT / SUBB / SUB / SUBS / SUBT.
            */
            8'h60: begin /* ADDC: ACC += d + C */
                ex_alu_op = ALU_ADDC;
                ex_alu_b  = {16'b0, d_w};
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            8'h61: begin /* ADD dma,16 (16-bit form) */
                ex_alu_op  = ALU_ADD;
                ex_alu_b   = {d_w, 16'b0};
                ex_alu_s16 = 1'b1;
                ex_alu_en  = 1'b1;
                ex_acc_ld  = 1'b1;
            end
            8'h62: begin /* ADDS: ACC += d (zero-extended) */
                ex_alu_op = ALU_ADD;
                ex_alu_b  = {16'b0, d_w};
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            8'h63: begin /* ADDT: ACC += ext(d, TREG1) */
                ex_alu_op = ALU_ADDT;
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            8'h64: begin /* SUBB: ACC -= d + !C */
                ex_alu_op   = ALU_SUBB;
                ex_alu_b    = {16'b0, d_w};
                ex_alu_c_in = ~stat_c;
                ex_alu_en   = 1'b1;
                ex_acc_ld   = 1'b1;
            end
            8'h65: begin /* SUB dma,16 (16-bit form) */
                ex_alu_op  = ALU_SUB;
                ex_alu_b   = {d_w, 16'b0};
                ex_alu_s16 = 1'b1;
                ex_alu_en  = 1'b1;
                ex_acc_ld  = 1'b1;
            end
            8'h66: begin /* SUBS */
                ex_alu_op = ALU_SUB;
                ex_alu_b  = {16'b0, d_w};
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            8'h67: begin /* SUBT: ACC -= ext(d, TREG1) */
                ex_alu_op = ALU_SUBT;
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            8'h68: begin /* ZALR: ACC = d<<16 | 0x8000 */
                ex_alu_op = ALU_LD_ZALR;
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            8'h69: begin /* LACL dma: ACC = d */
                ex_alu_op = ALU_LD_B16Z;
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            8'h6A: begin /* LACC dma,16: ACC = d<<16 */
                ex_alu_op = ALU_LD_B16HI;
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            8'h6B: begin /* LACT: ACC = ext(d, TREG1) */
                ex_alu_op = ALU_LACT;
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            8'h6C: begin /* XOR dma */
                ex_alu_op = ALU_XOR;
                ex_alu_b  = {16'b0, d_w};
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            8'h6D: begin /* OR dma */
                ex_alu_op = ALU_OR;
                ex_alu_b  = {16'b0, d_w};
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            8'h6E: begin /* AND dma */
                ex_alu_op = ALU_AND;
                ex_alu_b  = {16'b0, d_w};
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            8'h6F: begin end /* BITT (TC, main block) */
            /*
            LTA / LTP / LTD / LT / LTS / LPH / PSHD / DMOV.
            */
            8'h70: begin /* LTA: ACC += pscale; TREG0 = d */
                ex_alu_op  = ALU_LTA;
                ex_alu_b   = pscale_w;
                ex_alu_en  = 1'b1;
                ex_acc_ld  = 1'b1;
                ex_treg_ld = 3'b001;
                ex_treg_data = d_w;
            end
            8'h71: begin /* LTP: ACC = pscale; TREG0 = d */
                ex_alu_op  = ALU_LTP;
                ex_alu_en  = 1'b1;
                ex_acc_ld  = 1'b1;
                ex_treg_ld = 3'b001;
                ex_treg_data = d_w;
            end
            8'h72: begin /* LTD: ACC += pscale; TREG0 = d; DMOV */
                ex_alu_op  = ALU_LTD;
                ex_alu_b   = pscale_w;
                ex_alu_en  = 1'b1;
                ex_acc_ld  = 1'b1;
                ex_treg_ld = 3'b001;
                ex_treg_data = d_w;
                /*
                dmov_wr gate: only when both a and a+1 are
                internal DM and a >= 0x60.
                */
                ex_dm_wr   = dmov_gate_w;
                ex_dm_addr = ea_q + 16'd1;
                ex_dm_wdata = d_w;
            end
            8'h73: begin /* LT: TREG0 = d */
                ex_alu_op  = ALU_LT;
                ex_alu_en  = 1'b1;
                ex_treg_ld = 3'b001;
                ex_treg_data = d_w;
            end
            8'h74: begin /* LTS: ACC -= pscale; TREG0 = d */
                ex_alu_op  = ALU_LTS;
                ex_alu_b   = pscale_w;
                ex_alu_en  = 1'b1;
                ex_acc_ld  = 1'b1;
                ex_treg_ld = 3'b001;
                ex_treg_data = d_w;
            end
            8'h75: begin /* LPH: PREG high half = d */
                ex_alu_op    = ALU_LPH;
                ex_alu_en    = 1'b1;
                ex_preg_ld   = 1'b1;
                ex_preg_data = {d_w, preg_i[15:0]};
            end
            8'h76: begin /* PSHD: push d */
                ex_push_en   = 1'b1;
                ex_push_data = d_w;
            end
            8'h77: begin /* DMOV: dm[a+1] = d (dmov_wr gate) */
                ex_dm_wr    = dmov_gate_w;
                ex_dm_addr  = ea_q + 16'd1;
                ex_dm_wdata = d_w;
            end
            8'h78: begin end /* ADRK (ar update, main block) */
            /*
            B / CALL / BANZ (ea side effects done in FETCH2_DATA).
            */
            8'h79: begin
                ex_pc_act = PC_JMP;
                ex_pc_tgt = imm_q;
            end
            8'h7A: begin
                ex_push_en   = 1'b1;
                ex_push_data = pc_q; /* return = pc past 2nd word */
                ex_pc_act    = PC_JMP;
                ex_pc_tgt    = imm_q;
            end
            8'h7B: begin
                ex_pc_act = PC_JMP;
                ex_pc_tgt = imm_q;
                ex_ds_take = (ar_arp_i != 16'd0);
            end
            8'h7C: begin end /* SBRK (ar update, main block) */
            /*
            BD / CALLD / BANZD: push delay-slot context.
            */
            8'h7D: begin
                ex_pc_act  = PC_DSLOT;
                ex_pc_tgt  = imm_q;
                ex_ds_kind = 3'd0;
                ex_ds_take = 1'b1;
            end
            8'h7E: begin
                ex_push_en   = 1'b1;
                ex_push_data = pc_q + 16'd2; /* past the slot words */
                ex_pc_act    = PC_DSLOT;
                ex_pc_tgt    = imm_q;
                ex_ds_kind   = 3'd1;
                ex_ds_take   = 1'b1;
            end
            8'h7F: begin
                ex_pc_act  = PC_DSLOT;
                ex_pc_tgt  = imm_q;
                ex_ds_kind = 3'd0;
                ex_ds_take = (ar_arp_i != 16'd0);
            end
            /*
            SAR / SAMM / POPD / SPL / SPH / SST / SACL / SACH
            (write-only; dm_addr = ea_q, data below).
            */
            8'h80, 8'h81, 8'h82, 8'h83, 8'h84, 8'h85, 8'h86, 8'h87: begin
                ex_dm_wr    = 1'b1;
                ex_dm_addr  = ea_q;
                ex_dm_wdata = ar_rd_i; /* SAR: store AR[hi] */
            end
            8'h88: begin /* SAMM: dm[ea&0x7F] = ACC low */
                ex_dm_wr    = 1'b1;
                ex_dm_addr  = {9'b0, ea_q[6:0]};
                ex_dm_wdata = acc_i[15:0];
            end
            8'h8A: begin /* POPD: dm[ea] = pop() */
                ex_dm_wr    = 1'b1;
                ex_dm_addr  = ea_q;
                ex_dm_wdata = pop_data;
                ex_pop_en   = 1'b1;
            end
            8'h8B: begin end /* MAR (ea side effect only) */
            8'h8C: begin /* SPL: dm[ea] = pscale low */
                ex_dm_wr    = 1'b1;
                ex_dm_addr  = ea_q;
                ex_dm_wdata = pscale_w[15:0];
            end
            8'h8D: begin /* SPH: dm[ea] = pscale high */
                ex_dm_wr    = 1'b1;
                ex_dm_addr  = ea_q;
                ex_dm_wdata = pscale_w[31:16];
            end
            8'h8E: begin /* SST #0: dm[ea] = ST0 */
                ex_dm_wr    = 1'b1;
                ex_dm_addr  = ea_q;
                /* C computes the address first (an ARP switch of this very instruction lands), then reads ST0: store the ARP the instruction leaves behind */
                ex_dm_wdata = {(re_i.desc.valid && re_i.desc.arp_sw) ? re_i.desc.new_arp : stat_arp,
                               stat_ov, stat_ovm, 1'b1, stat_intm, stat_dp};
            end
            8'h8F: begin /* SST #1: dm[ea] = ST1 */
                ex_dm_wr    = 1'b1;
                ex_dm_addr  = ea_q;
                /* ... and ARB receives the old ARP when the instruction switches it (C set_arp) */
                ex_dm_wdata = {(re_i.desc.valid && re_i.desc.arp_sw) ? stat_arp : stat_arb, stat_cnf, stat_tc, stat_sxm,
                               stat_c, 1'b1, 1'b1, stat_hm, 1'b1,
                               stat_xf, 1'b1, 1'b1, stat_pm};
            end
            8'h90, 8'h91, 8'h92, 8'h93, 8'h94, 8'h95, 8'h96, 8'h97: begin
                /*
                SACL: dm[ea] = (ACC << sh) low half
                */
                ex_dm_wr    = 1'b1;
                ex_dm_addr  = ea_q;
                ex_dm_wdata = shl_acc_w[15:0];
            end
            8'h98, 8'h99, 8'h9A, 8'h9B, 8'h9C, 8'h9D, 8'h9E, 8'h9F: begin
                /*
                SACH: dm[ea] = (ACC << sh) high half
                */
                ex_dm_wr    = 1'b1;
                ex_dm_addr  = ea_q;
                ex_dm_wdata = shl_acc_w[31:16];
            end
            /*
            NORM: shift ACC left if bits 31/30 agree and ACC != 0;
            TC = done.  ea() runs only on the shifting path.
            */
            8'hA0: begin
                ex_alu_op = ALU_NORM;
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            /*
            SPLK: dm[ea] = imm (ea before imm fetch in C; the FSM
            fetches imm first, then ea -- disjoint state, same result).
            */
            8'hAE: begin
                ex_dm_wr    = 1'b1;
                ex_dm_addr  = ea_q;
                ex_dm_wdata = imm_q;
            end
            /*
            IN: io_read(port) -> dm[ea].  Port = imm + io_rep.
            */
            8'hAF: begin
                ex_io_req  = 1'b1;
                ex_io_wr   = 1'b0;
                ex_io_port = imm_q + io_rep_q;
            end
            /*
            ADDK / LACK / SUBK.
            */
            8'hB8: begin /* ADDK: ACC += k8 */
                ex_alu_op = ALU_ADD;
                ex_alu_b  = {24'b0, op_lo};
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            8'hB9: begin /* LACK: ACC = k8 */
                ex_alu_op = ALU_LD_B16Z;
                ex_alu_d  = {8'b0, op_lo};
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            8'hBA: begin /* SUBK: ACC -= k8 */
                ex_alu_op = ALU_SUB;
                ex_alu_b  = {24'b0, op_lo};
                ex_alu_en = 1'b1;
                ex_acc_ld = 1'b1;
            end
            /*
            RPT #k8 / LDP #k9 (rptc/dp loads driven by main block).
            */
            8'hBB: begin end
            8'hBC, 8'hBD: begin end
            /*
            0xBE / 0xBF sub-decoders (handled below by op_lo).
            */
            8'hBE: begin
                if (op_lo < 8'h20) begin
                    /*
                    Accumulator ops: the ALU does the work; the
                    ctrl asserts the register loads.  OP_* came
                    from the decoder (dec_alu_op).
                    */
                    ex_alu_en = 1'b1;
                    case (op_lo)
                        8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05,
                        8'h09, 8'h0A, 8'h0C, 8'h0D, 8'h10, 8'h11,
                        8'h12, 8'h13, 8'h18, 8'h19, 8'h1A,
                        8'h1F:
                            /*
                            ABS/CMPL/NEG/PAC/APAC/SPAC/ROL/ROR/
                            ROLC/RORC/ADDB/ADDC/ANDB/ORB/SUBB/
                            SBBB/XORB/MAX/MIN/LACB: ACC result.
                            */
                            ex_acc_ld = 1'b1;
                        8'h14, 8'h15, 8'h16, 8'h17,
                        8'h1B, 8'h1C: begin   /* CRGT / CRLT also write ACCB (MAX: ACCB = max; MIN: ACCB = min on the other path) */
                            /*
                            ROLB / RORB / SFLB / SFRB: ACC and ACCB
                            */
                            ex_acc_ld  = 1'b1;
                            ex_accb_ld = 1'b1;
                        end
                        8'h1E: begin /* SACB: ACCB = ACC */
                            ex_accb_ld    = 1'b1;
                            ex_acc_ld_sel = 1'b1; /* accb_data = ex_accb_data */
                            ex_accb_data  = acc_i;
                        end
                        8'h1D: begin /* SWAP: ACC <-> ACCB */
                            ex_acc_ld     = 1'b1;
                            ex_acc_ld_sel = 1'b1;
                            ex_acc_data   = accb_i;
                            ex_accb_ld    = 1'b1;
                            ex_accb_data  = acc_i;
                        end
                        default: begin end
                    endcase
                end else begin
                    case (op_lo)
                        8'h20: begin /* BACC: pc = ACC */
                            ex_pc_act = PC_JMP;
                            ex_pc_tgt = acc_i[15:0];
                        end
                        8'h21: begin /* BACCD: slot, then pc = ACC */
                            ex_pc_act  = PC_DSLOT;
                            ex_pc_tgt  = acc_i[15:0];
                            ex_ds_kind = 3'd3;
                            ex_ds_take = 1'b1;
                        end
                        8'h22: begin /* IDLE */
                            ex_pc_act = PC_IDLE;
                        end
                        8'h23: begin /* IDLE2 */
                            ex_pc_act = PC_IDLE;
                        end
                        8'h30: begin /* CALA: push pc, pc = ACC */
                            ex_push_en   = 1'b1;
                            ex_push_data = pc_q;
                            ex_pc_act    = PC_JMP;
                            ex_pc_tgt    = acc_i[15:0];
                        end
                        8'h32: begin /* POP: ACC = pop() */
                            ex_alu_op = ALU_LD_B16Z;
                            ex_alu_d  = pop_data;
                            ex_alu_en = 1'b1;
                            ex_acc_ld = 1'b1;
                            ex_pop_en = 1'b1;
                        end
                        8'h38: begin /* RETI: pc = pop, restore ctx */
                            ex_pop_en = 1'b1;
                            ex_pc_act = PC_RET;
                        end
                        8'h3A: begin /* RETE: pc = pop, restore, intm=0 */
                            ex_pop_en = 1'b1;
                            ex_pc_act = PC_RET;
                        end
                        8'h3C: begin /* PSHA: push ACC */
                            ex_push_en   = 1'b1;
                            ex_push_data = acc_i[15:0];
                        end
                        8'h3D: begin /* CALAD: push pc+2, slot, pc=ACC */
                            ex_push_en   = 1'b1;
                            ex_push_data = pc_q + 16'd2;
                            ex_pc_act    = PC_DSLOT;
                            ex_pc_tgt    = acc_i[15:0];
                            ex_ds_kind   = 3'd4;
                            ex_ds_take   = 1'b1;
                        end
                        8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45,
                        8'h46, 8'h47, 8'h48, 8'h49, 8'h4A, 8'h4B,
                        8'h4C, 8'h4D, 8'h4E, 8'h4F: begin end
                        8'h51: begin /* TRAP: push pc, pc = IPTR|0x22 */
                            ex_push_en   = 1'b1;
                            ex_push_data = pc_q;
                            ex_pc_act    = PC_JMP;
                            ex_pc_tgt    = {stat_iptr, 11'h022};
                        end
                        8'h52: begin /* NMI: push pc, pc = IPTR|0x24 */
                            ex_push_en   = 1'b1;
                            ex_push_data = pc_q;
                            ex_pc_act    = PC_JMP;
                            ex_pc_tgt    = {stat_iptr, 11'h024};
                        end
                        8'h58: begin /* PREG = 0 */
                            ex_alu_op  = ALU_PREG_ZERO;
                            ex_alu_en  = 1'b1;
                            ex_preg_ld = 1'b1;
                            ex_preg_data = 32'd0;
                        end
                        8'h59: begin /* ACC = 0, PREG = 0 */
                            ex_alu_op  = ALU_ACC_PREG_ZERO;
                            ex_alu_en  = 1'b1;
                            ex_acc_ld  = 1'b1;
                            ex_acc_data = 32'd0;
                            ex_preg_ld = 1'b1;
                            ex_preg_data = 32'd0;
                        end
                        8'h5A: begin /* SATH */
                            ex_alu_op = ALU_SATH;
                            ex_alu_en = 1'b1;
                            ex_acc_ld = 1'b1;
                        end
                        8'h5B: begin /* SATL */
                            ex_alu_op = ALU_SATL;
                            ex_alu_en = 1'b1;
                            ex_acc_ld = 1'b1;
                        end
                        8'h80: begin /* MPY #lk: PREG = TREG0*imm */
                            ex_alu_op  = ALU_MPY;
                            ex_alu_en  = 1'b1;
                            ex_mpy_en  = 1'b1;
                            ex_mpy_a   = treg0_i;
                            ex_mpy_b   = imm_q;
                            ex_preg_ld = 1'b1;
                            ex_preg_data = mpy_p;
                        end
                        8'h81: begin /* AND #lk,16 */
                            ex_alu_op = ALU_AND;
                            ex_alu_b  = {imm_q, 16'b0};
                            ex_alu_en = 1'b1;
                            ex_acc_ld = 1'b1;
                        end
                        8'h82: begin /* OR #lk,16 */
                            ex_alu_op = ALU_OR;
                            ex_alu_b  = {imm_q, 16'b0};
                            ex_alu_en = 1'b1;
                            ex_acc_ld = 1'b1;
                        end
                        8'h83: begin /* XOR #lk,16 */
                            ex_alu_op = ALU_XOR;
                            ex_alu_b  = {imm_q, 16'b0};
                            ex_alu_en = 1'b1;
                            ex_acc_ld = 1'b1;
                        end
                        8'hC4: begin end /* RPT #lk */
                        8'hC5: begin /* RPTZ #lk: ACC = 0, PREG = 0, then repeat */
                            ex_alu_op  = ALU_ACC_PREG_ZERO;
                            ex_alu_en  = 1'b1;
                            ex_acc_ld  = 1'b1;
                            ex_acc_data = 32'd0;
                            ex_preg_ld = 1'b1;
                            ex_preg_data = 32'd0;
                        end
                        8'hC6: begin end /* RPTB */
                        default: begin end /* INTR k / BADOP (main blk) */
                    endcase
                end
            end
            /*
            0xBF sub-decoder.
            */
            8'hBF: begin
                if (op_lo <= 8'h03) begin
                    /*
                    SPM k (pm write, main block)
                    */
                end else if (op_lo >= 8'h08 && op_lo <= 8'h0F) begin
                    /*
                    LAR #lk (ar write, main block)
                    */
                end else if (op_lo >= 8'h44 && op_lo <= 8'h47) begin
                    /*
                    CMPR (TC, main block)
                    */
                end else if (op_lo >= 8'h80 && op_lo <= 8'hDF) begin
                    /*
                    Long-immediate ALU #lk,sh (sh = lo[3:0]).
                    */
                    ex_alu_sh = op_lo[3:0];
                    ex_alu_en = 1'b1;
                    ex_acc_ld = 1'b1;
                    case (op_lo[7:4])
                        4'h8: begin /* LACC #lk,sh */
                            ex_alu_op = ALU_LD_EXT;
                            ex_alu_d  = imm_q;
                        end
                        4'h9: begin /* ADD #lk,sh */
                            ex_alu_op = ALU_ADD_SH;
                            ex_alu_b  = stat_sxm ?
                                {{16{imm_q[15]}}, imm_q} << op_lo[3:0] :
                                {16'b0, imm_q} << op_lo[3:0];
                        end
                        4'hA: begin /* SUB #lk,sh */
                            ex_alu_op = ALU_SUB_SH;
                            ex_alu_b  = stat_sxm ?
                                {{16{imm_q[15]}}, imm_q} << op_lo[3:0] :
                                {16'b0, imm_q} << op_lo[3:0];
                        end
                        4'hB: begin /* AND #lk,sh */
                            ex_alu_op = ALU_AND;
                            ex_alu_b  = {16'b0, imm_q} << op_lo[3:0];
                        end
                        4'hC: begin /* OR #lk,sh */
                            ex_alu_op = ALU_OR;
                            ex_alu_b  = {16'b0, imm_q} << op_lo[3:0];
                        end
                        4'hD: begin /* XOR #lk,sh */
                            ex_alu_op = ALU_XOR;
                            ex_alu_b  = {16'b0, imm_q} << op_lo[3:0];
                        end
                        default: begin end
                    endcase
                end else if (op_lo >= 8'hE0 && op_lo <= 8'hEF) begin
                    /*
                    SFTA: ACC >>= (sh+1), sign per SXM (KD-1).
                    */
                    ex_alu_op = ALU_SFTA;
                    ex_alu_sh = op_lo[3:0];
                    ex_alu_en = 1'b1;
                    ex_acc_ld = 1'b1;
                end else begin
                    /*
                    BADOP (main block halts)
                    */
                end
            end
            /*
            MPY #k13 (signed 13-bit imm x TREG0).
            */
            8'hC0, 8'hC1, 8'hC2, 8'hC3, 8'hC4, 8'hC5, 8'hC6, 8'hC7,
            8'hC8, 8'hC9, 8'hCA, 8'hCB, 8'hCC, 8'hCD, 8'hCE, 8'hCF,
            8'hD0, 8'hD1, 8'hD2, 8'hD3, 8'hD4, 8'hD5, 8'hD6, 8'hD7,
            8'hD8, 8'hD9, 8'hDA, 8'hDB, 8'hDC, 8'hDD, 8'hDE, 8'hDF: begin
                ex_alu_op  = ALU_MPY;
                ex_alu_en  = 1'b1;
                ex_mpy_en  = 1'b1;
                ex_mpy_a   = treg0_i;
                ex_mpy_b   = { {(3){op_q[12]}}, op_q[12:0] };
                ex_preg_ld = 1'b1;
                ex_preg_data = mpy_p;
            end
            /*
            BCND / XC / CC / RETC / BCNDD / CCD / RETCD.
            */
            8'hE0, 8'hE1, 8'hE2, 8'hE3: begin /* BCND */
                ex_pc_act  = PC_JMP;
                ex_pc_tgt  = imm_q;
                ex_ds_take = cond_q;
            end
            8'hE4, 8'hE5, 8'hE6, 8'hE7,
            8'hF4, 8'hF5, 8'hF6, 8'hF7: begin /* XC */
                /* False XC skips n words (n = ((op>>12)&1)+1,
                   C: pc += n from the post-XC pc).  True XC opens
                   the uninterruptible window (p10, via ex_ds_take). */
                ex_ds_take = cond_q;
                ex_pc_act = cond_q ? PC_SEQ : PC_JMP;
                ex_pc_tgt = pc_q + {15'd0, op_q[12]} + 16'd1;
            end
            8'hE8, 8'hE9, 8'hEA, 8'hEB: begin /* CC */
                ex_push_en   = 1'b1;
                ex_push_data = pc_q;
                ex_pc_act    = PC_JMP;
                ex_pc_tgt    = imm_q;
                ex_ds_take   = cond_q;
            end
            8'hEC, 8'hED, 8'hEE, 8'hEF: begin /* RETC */
                ex_pop_en = 1'b1;
                ex_pc_act = PC_RET;
                ex_ds_take = cond_q;
            end
            8'hF0, 8'hF1, 8'hF2, 8'hF3: begin /* BCNDD */
                ex_pc_act  = PC_DSLOT;
                ex_pc_tgt  = imm_q;
                ex_ds_kind = 3'd0;
                ex_ds_take = cond_q;
            end
            8'hF8, 8'hF9, 8'hFA, 8'hFB: begin /* CCD */
                ex_push_en   = 1'b1;
                ex_push_data = pc_q + 16'd2;
                ex_pc_act    = PC_DSLOT;
                ex_pc_tgt    = imm_q;
                ex_ds_kind   = 3'd1;
                ex_ds_take   = cond_q;
            end
            8'hFC, 8'hFD, 8'hFE, 8'hFF: begin /* RETCD: slot runs */
                /*
                first, THEN TOS -> PC and pop (6.3 RETD).  The pop
                is done in TAIL when the slot completes (kind 2),
                not here.
                */
                ex_pc_act  = PC_DSLOT;
                ex_pc_tgt  = 16'd0;
                ex_ds_kind = 3'd2;
                ex_ds_take = cond_q;
            end
            default: begin end
        endcase
    end
    /* verilator lint_on UNUSEDSIGNAL */

    /*
    TC result for the XPL/OPL/APL/CPL family (read-modify-write).
    CPL does not write, but TC is still set from the compare.
    */
    logic [15:0] xpl_res_w;
    logic        xpl_tc_w;
    always_comb begin
        case (op_hi)
            8'h58: xpl_res_w = d_w ^ dbmr_i;
            8'h59: xpl_res_w = d_w | dbmr_i;
            8'h5A: xpl_res_w = d_w & dbmr_i;
            8'h5B: xpl_res_w = d_w ^ dbmr_i;
            8'h5C: xpl_res_w = d_w ^ imm_q;
            8'h5D: xpl_res_w = d_w | imm_q;
            8'h5E: xpl_res_w = d_w & imm_q;
            8'h5F: xpl_res_w = d_w ^ imm_q;
            default: xpl_res_w = 16'd0;
        endcase
        xpl_tc_w = (xpl_res_w == 16'd0);
    end

    /*
    CMPR compare result (TC).  Unsigned 16-bit compare of AR[ARP]
    against ARCR (cmpr_ar0 is a C experiment, not wired here).
    */
    logic cmpr_tc_w;
    always_comb begin
        case (op_lo[1:0])
            2'd0: cmpr_tc_w = (ar_arp_i == arcr_i);
            2'd1: cmpr_tc_w = (ar_arp_i <  arcr_i);
            2'd2: cmpr_tc_w = (ar_arp_i >  arcr_i);
            default: cmpr_tc_w = (ar_arp_i != arcr_i);
        endcase
    end

    /*
    INTR redirect index: which ivec_ind entry (0..8) holds the
    indirection for vector v = (op & 0x1F) << 1.  Audited table
    first (02,04,06,08,0A,0C,0E,10,12 -> i = (v-2)/2), then the
    legacy table (18,1A,1C,1E,20,22 -> i = (v-0x18)/2 + 3).
    Returns -1 (as 4'hF) when no table entry matches v.
    */
    logic [3:0] intr_ind_idx_w;
    logic       intr_ind_hit_w;
    logic [5:0] intr_v_w; /* v = (op & 0x1F) << 1, 0..62 (even) */
    logic [3:0] intr_vh4_w; /* (v>>1) & 0xF; the -1 / -9 below wrap */
                            /*
                            correctly in 4 bits for both tables
                            */
    assign intr_v_w  = {op_lo[4:0], 1'b0};
    assign intr_vh4_w = intr_v_w[4:1];
    always_comb begin
        intr_ind_idx_w = 4'hF;
        intr_ind_hit_w = 1'b0;
        if (intr_v_w >= 6'h02 && intr_v_w <= 6'h12) begin
            /*
            i = (v-2)/2 = (v>>1) - 1
            */
            intr_ind_idx_w = intr_vh4_w - 4'd1;
            intr_ind_hit_w = 1'b1;
        end else if (intr_v_w >= 6'h18 && intr_v_w <= 6'h22) begin
            /*
            i = (v - 0x18)/2 + 3 = (v>>1) - 9
            */
            intr_ind_idx_w = intr_vh4_w - 4'd9;
            intr_ind_hit_w = 1'b1;
        end
    end
    /*
    ivec_ind address for the INT state (indexed by int_idx_q).
    */
    logic [15:0] int_ind_addr_w;
    always_comb begin
        case (int_idx_q)
            5'd0: int_ind_addr_w = ivec_ind_i[15:0];
            5'd1: int_ind_addr_w = ivec_ind_i[31:16];
            5'd2: int_ind_addr_w = ivec_ind_i[47:32];
            5'd3: int_ind_addr_w = ivec_ind_i[63:48];
            5'd4: int_ind_addr_w = ivec_ind_i[79:64];
            5'd5: int_ind_addr_w = ivec_ind_i[95:80];
            5'd6: int_ind_addr_w = ivec_ind_i[111:96];
            5'd7: int_ind_addr_w = ivec_ind_i[127:112];
            5'd8: int_ind_addr_w = ivec_ind_i[143:128];
            default: int_ind_addr_w = 16'd0;
        endcase
    end

    /*
    ivec_ind address for the INTR instruction (indexed by the
    redirect index computed from the vector).  0 if no table hit.
    */
    logic [15:0] intr_ind_addr_w;
    always_comb begin
        intr_ind_addr_w = 16'd0;
        if (intr_ind_hit_w) begin
            case (intr_ind_idx_w)
                4'd0: intr_ind_addr_w = ivec_ind_i[15:0];
                4'd1: intr_ind_addr_w = ivec_ind_i[31:16];
                4'd2: intr_ind_addr_w = ivec_ind_i[47:32];
                4'd3: intr_ind_addr_w = ivec_ind_i[63:48];
                4'd4: intr_ind_addr_w = ivec_ind_i[79:64];
                4'd5: intr_ind_addr_w = ivec_ind_i[95:80];
                4'd6: intr_ind_addr_w = ivec_ind_i[111:96];
                4'd7: intr_ind_addr_w = ivec_ind_i[127:112];
                4'd8: intr_ind_addr_w = ivec_ind_i[143:128];
                default: intr_ind_addr_w = 16'd0;
            endcase
        end
    end

    /*
    ------------------------------------------------------------------
    Sequential FSM.
    ------------------------------------------------------------------
    Interrupt selection: the lowest set bit of (ifr & imr).
    */
    logic [3:0] int_sel_w;
    logic       int_sel_found_w;
    always_comb begin
        int_sel_w       = 4'd0;
        int_sel_found_w = 1'b0;
        for (int i = 0; i < 9; i++) begin
            if (!int_sel_found_w && (ifr_eff_w[i] && imr_i[i])) begin
                int_sel_w       = i[3:0];
                int_sel_found_w = 1'b1;
            end
        end
    end


    /*
    ------------------------------------------------------------------
    IO wait states (C io_ws, c5x_core.c:575): from IOWSR/CWSR.
    big = CWSR bit 4 selects large (8K, port>>13) vs small (128-word,
    (port>>1)&7) page indexing; alt doubles 2->3 and 3->7.
    Used for the cycle charge of a deferred host-window read and
    of an E data write to the host window (the IN/OUT wait states
    come from the memory's o_e_io_ws instead).
    ------------------------------------------------------------------
    */
    /* Only port[15:13] (big) / port[3:1] (small) select the
       wait-state field; the other port bits are not read. */
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [2:0] io_ws_f(input logic [15:0] port,
                                           input logic [15:0] iowsr,
                                           input logic [15:0] cwsr);
        logic big_w;
        logic [2:0] idx_w;
        logic [1:0] f_w;
        logic alt_w;
        begin
            big_w = cwsr[4];
            idx_w = big_w ? port[15:13] : {port[3:1]};
            f_w = iowsr[(idx_w * 2) +: 2];
            alt_w = cwsr[(idx_w < 3'd4) ? 2 : 3];
            if (alt_w)
                io_ws_f = (f_w == 2'd3) ? 3'd7 :
                          (f_w == 2'd2) ? 3'd3 : {1'b0, f_w};
            else
                io_ws_f = {1'b0, f_w};
        end
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    /*
    ------------------------------------------------------------------
    E-commit: drive the ALU / address-unit / memory ports from the
    executor (ex_*) and the per-instruction specials (the old main
    output block's OP_DATA/EXEC arms, ported).  The ALU commits its
    internal next values on i_ld_* (ex_acc_data / ex_accb_data /
    ex_preg_data / ex_treg_data and ex_alu_a / ex_alu_c_in /
    ex_mpy_en / ex_acc_ld_sel are therefore dead in this design
    and are waived as UNUSEDSIGNAL in the lint waiver below).
    Three latent multi-cycle bugs are fixed here, per the C model:
    RETC pops and jumps only when taken; CC/CCD push only when
    taken; taken BCND/CC/BCNDD/CCD with op bit 1 set clear OV
    (c5x_core.c:2521, 2547, 2558, 2568).
    The descriptor commit (i_desc_en) is asserted for every E
    instruction with a valid descriptor (the address unit commits
    the AR update + ARP switch at the retire edge); NORM holds it
    unless ACC != 0 and ACC[31] == ACC[30] (i_desc_hold).
    ndx_commit_o pulses at every retire edge (the AR0 mirror).
    ------------------------------------------------------------------
    */
    logic e_is_reti_w, e_is_rete_w;
    logic e_cond_branch_w, e_ov_clear_w;
    logic [2:0] e_pc_act_w;
    logic [15:0] e_pc_tgt_w;
    logic e_push_w, e_pop_w;
    logic [2:0] e_io_ws_w;

    assign e_is_reti_w = (op_hi == 8'hBE) && (op_lo == 8'h38);
    assign e_is_rete_w = (op_hi == 8'hBE) && (op_lo == 8'h3A);
    /* Conditional branch/call/return (ex_ds_take is the taken flag). */
    assign e_cond_branch_w = (op_hi == 8'h7B) ||
                             ((op_hi >= 8'hE0) && (op_hi <= 8'hE3)) ||
                             ((op_hi >= 8'hE8) && (op_hi <= 8'hEB)) ||
                             ((op_hi >= 8'hEC) && (op_hi <= 8'hEF)) ||
                             ((op_hi >= 8'hF0) && (op_hi <= 8'hF3)) ||
                             ((op_hi >= 8'hF8) && (op_hi <= 8'hFB)) ||
                             ((op_hi >= 8'hFC));
    /* Taken BCND/CC/BCNDD/CCD with op bit 1 set clear OV. */
    assign e_ov_clear_w = e_cond_branch_w && ex_ds_take &&
                          (op_q[1] == 1'b1) &&
                          ((op_hi >= 8'hE0) && (op_hi <= 8'hE3) ||
                           (op_hi >= 8'hE8) && (op_hi <= 8'hEB) ||
                           (op_hi >= 8'hF0) && (op_hi <= 8'hF3) ||
                           (op_hi >= 8'hF8) && (op_hi <= 8'hFB));
    /* Effective PC action: a not-taken conditional continues. */
    assign e_pc_act_w = (e_cond_branch_w && !ex_ds_take) ? PC_SEQ :
                        ex_pc_act;
    assign e_pc_tgt_w = ex_pc_tgt;
    /* Push/pop gated on taken for CC/CCD/RETC (C model, above). */
    assign e_push_w = ex_push_en &&
                      !(((op_hi >= 8'hE8) && (op_hi <= 8'hEB) ||
                         (op_hi >= 8'hF8) && (op_hi <= 8'hFB)) &&
                        !ex_ds_take);
    assign e_pop_w = ex_pop_en &&
                     !(((op_hi >= 8'hEC) && (op_hi <= 8'hEF)) &&
                       !ex_ds_take);
    assign e_io_ws_w = e_io_ws_i;

    /*
    The memory outputs (E data write, PMEM write, IN/OUT request,
    deferred read) are presented whenever the normal E instruction
    is present and no loop / replay / entry / restore override is
    active -- they are NOT gated on e_retire_w.  Gating them on
    e_retire_w closes a combinational loop: e_retire_w depends on
    e_hold_mem_w, which depends on the memory's o_e_stall, which
    depends combinationally on these very outputs (the memory's
    io_active is combinational on i_e_io_req / i_e_rd_req /
    i_e_wr).  The ALU and address-unit outputs stay gated on
    e_retire_w below: they are registered effects that must land
    exactly once, at the retire edge, and they do not feed back
    through the memory.  The memory outputs are level-presented
    while the E instruction is in E: a non-IO access is accepted
    in the presented clock (E is not held for it, so it is
    presented exactly once); an IO access is held by the host
    handshake until ack, then the instruction retires and the
    request drops.  The loop / entry / restore overrides below
    (last assignment wins) take these outputs over when active.
    A mechanism-(b) replay iteration presents its memory outputs
    here too (no !replay_active_q): the frozen bundle re-executes
    in E once per iteration, and the per-iteration store / IO /
    deferred read is the replay's commit -- gating it out made
    iterations 2+ retire with no store (Bug 1, 2026-11-20).  The
    addresses and data are live per iteration (ea_q, d_w), and
    the AR descriptor is an operation re-evaluated from the live
    AR, so presenting the outputs each iteration is exactly the
    C model's re-execution.
    */
    logic e_mem_present_w;
    assign e_mem_present_w = re_i.valid && !loop_active_q &&
                             !entry_active_q &&
                             !restore_active_q && !re_i.is_loop_a;
    /*
    The loop iteration's memory outputs are presented whenever
    the loop op is in E and the loop is running (starting or
    continuing) -- they are NOT gated on loop_exec_w.  Gating
    them on loop_exec_w closes a combinational loop: loop_exec_w
    depends on e_hold_mem_w, which depends on the memory's
    o_e_stall, which depends combinationally on these very
    outputs.  See p09 for the matching split of the loop
    override wires.
    */
    logic loop_mem_present_w;
    /* A 0-iteration while-form loop (rptc == -1, loop_iters_w ==
       0) presents no iteration: the C model executes no body
       and no write.  Gating on loop_iters_w (a function of the
       rptc register only) cannot close the combinational loop
       that gating on loop_exec_w would (loop_exec_w depends on
       e_hold_mem_w, which depends on these very outputs).
       Bug 3, 2026-11-20. */
    assign loop_mem_present_w = re_i.valid &&
        ((re_i.is_loop_a && !loop_active_q &&
          (loop_iters_w > 32'd0)) || loop_active_q);

    always_comb begin
        /*
        ---- defaults (all strobes idle) ----
        */
        alu_exec_o = 1'b0;
        alu_op_o = ALU_NOP;
        alu_b32_o = 32'd0;
        alu_b16_o = 16'd0;
        alu_mpy_a_o = 16'd0;
        alu_mpy_b_o = 16'd0;
        alu_mpy_unsigned_o = 1'b0;
        alu_shift_o = 4'd0;
        alu_s16_o = 1'b0;
        alu_ld_acc_o = 1'b0;
        alu_ld_accb_o = 1'b0;
        alu_ld_preg_o = 1'b0;
        alu_ld_treg0_o = 1'b0;
        alu_flag_c_we_o = 1'b0;
        alu_flag_c_in_o = 1'b0;
        alu_flag_ov_we_o = 1'b0;
        alu_flag_ov_in_o = 1'b0;
        alu_treg12_wr_en_o = 1'b0;
        alu_treg12_sel_o = 1'b0;
        alu_treg12_data_o = 16'd0;
        ar_wr_en_o = 1'b0;
        ar_wr_sel_o = 3'd0;
        ar_wr_data_o = 16'd0;
        st0_ld_en_o = 1'b0;
        st0_ld_data_o = 16'd0;
        st1_ld_en_o = 1'b0;
        st1_ld_data_o = 16'd0;
        pmst_ld_en_o = 1'b0;
        pmst_ld_data_o = 16'd0;
        rptc_ld_en_o = 1'b0;
        rptc_ld_data_o = 16'd0;
        brcr_ld_en_o = 1'b0;
        brcr_ld_data_o = 32'd0;
        addr_wr_en_o = 1'b0;
        addr_wr_sel_o = 6'd0;
        addr_wr_data_o = 16'd0;
        st_bit_en_o = 1'b0;
        st_bit_sel_o = 5'd0;
        st_bit_val_o = 1'b0;
        desc_en_o = 1'b0;
        desc_ar_id_o = 3'd0;
        desc_mode_o = 4'd0;
        desc_arp_sw_o = 1'b0;
        desc_new_arp_o = 3'd0;
        desc_ark_o = 8'd0;
        desc_hold_o = 1'b0;
        desc_keep_arb_o = 1'b0;
        ndx_commit_o = 1'b0;
        push_en_o = 1'b0;
        push_data_o = 16'd0;
        pop_en_o = 1'b0;
        rptc_dec_o = 1'b0;
        rptb_set_o = 1'b0;
        rptb_pasr_o = 16'd0;
        rptb_paer_o = 16'd0;
        rptb_clr_o = 1'b0;
        irq_ack_o = 9'd0;
        e_wr_o = 1'b0;
        e_wr_addr_o = 16'd0;
        e_wr_data_o = 16'd0;
        e_dmov_o = 1'b0;
        e_dmov_src_o = 16'd0;
        e_wr_flush_en_o = 1'b0;
        e_rd_req_o = 1'b0;
        e_rd_addr_o = 16'd0;
        e_io_req_o = 1'b0;
        e_io_rd_o = 1'b0;
        e_io_addr_o = 16'd0;
        e_io_wdata_o = 16'd0;
        pm_wr_req_o = 1'b0;
        pm_wr_addr_o = 16'd0;
        pm_wr_data_o = 16'd0;
        pm_wr_is_e_o = 1'b0;
        pm_wr_flush_en_o = 1'b0;

        /*
        ---- memory outputs (presented, not retired: see
             e_mem_present_w above) ----
        */
        if (e_mem_present_w) begin
            if (ex_dm_wr) begin
                e_wr_o = 1'b1;
                e_wr_addr_o = ex_dm_addr;
                e_wr_data_o = ex_dm_wdata;
                /* A plain store to a code address flushes the
                   fetch stream (H10); the memory flushes
                   unconditionally when this is set, so assert it
                   only for a program address: external PMEM
                   (0x8000+) or SARAM data (0x0800-0x0BFF) when
                   OVLY=1 (it is program 0x2000-0x23FF).  A store
                   to a dynamic MMR (0x00-0x1F) is forwarded by
                   the memory as o_ext_mmr_wr to the top's
                   write-port adapter; it is not an addr_wr here. */
                e_wr_flush_en_o = (ex_dm_addr >= 16'h8000) ||
                    (stat_ovly && (ex_dm_addr >= 16'h0800) &&
                     (ex_dm_addr < 16'h0C00));
            end
            if (ex_pm_wr) begin
                pm_wr_req_o = 1'b1;
                pm_wr_addr_o = ex_pm_addr;
                pm_wr_data_o = ex_pm_wdata;
                pm_wr_is_e_o = 1'b1;
                pm_wr_flush_en_o = 1'b1;
            end
            if (ex_io_req) begin
                e_io_req_o = 1'b1;
                e_io_rd_o = !ex_io_wr;
                e_io_addr_o = ex_io_port;
                e_io_wdata_o = ex_io_wdata;
                /* IN: the IO read completes this clock (the host
                   acks io_req); write the read data to DMEM[ea].
                   Gated on io_ack_i (a top-level input), NOT on
                   o_e_io_done: the memory's io_active is
                   combinational on i_e_wr, so gating e_wr_o on
                   o_e_io_done is a combinational loop.  OUT writes
                   nothing to memory. */
                if (!ex_io_wr && io_ack_i) begin
                    e_wr_o = 1'b1;
                    e_wr_addr_o = ea_q;
                    e_wr_data_o = io_rdata_i;
                end
            end
            /* Deferred read (H3): present it to the memory's E
               read port; the E stage holds until o_e_rdata is
               valid (e_stall_i low). */
            if (re_i.deferred) begin
                e_rd_req_o = 1'b1;
                e_rd_addr_o = ea_q;
            end
        end

        if (e_retire_w && re_i.valid && !loop_active_q &&
            !entry_active_q &&
            !restore_active_q) begin
            /*
            ---- ALU (ex_*; the ALU commits its internal next
                 values on i_ld_*) ----
            */
            alu_exec_o = ex_alu_en;
            alu_op_o = ex_alu_op;
            alu_b32_o = ex_alu_b;
            alu_b16_o = ex_alu_d;
            alu_mpy_a_o = ex_mpy_a;
            alu_mpy_b_o = ex_mpy_b;
            alu_mpy_unsigned_o = (ex_alu_op == ALU_MPYU);
            alu_shift_o = ex_alu_sh;
            alu_s16_o = ex_alu_s16;
            alu_ld_acc_o = ex_acc_ld;
            alu_ld_accb_o = ex_accb_ld;
            alu_ld_preg_o = ex_preg_ld;
            alu_ld_treg0_o = ex_treg_ld[0];
            /*
            ---- descriptor commit (AR update + ARP switch) ----
            NORM holds the commit unless ACC != 0 and
            ACC[31] == ACC[30] (C: NORM ea() only on the
            shifting path).
            */
            if (re_i.desc.valid) begin
                desc_en_o = 1'b1;
                desc_ar_id_o = re_i.desc.ar_id;
                desc_mode_o = re_i.desc.mode;
                desc_arp_sw_o = re_i.desc.arp_sw;
                desc_new_arp_o = re_i.desc.new_arp;
                desc_ark_o = re_i.desc.ark;
                desc_keep_arb_o = (op_hi == 8'h0E);
                desc_hold_o = (op_hi == 8'hA0) &&
                              !((acc_i != 32'd0) &&
                                (acc_i[31] == acc_i[30]));
            end
            ndx_commit_o = 1'b1;
            /*
            ---- stack (take-gated for CC/CCD/RETC) ----
            */
            push_en_o = e_push_w;
            push_data_o = ex_push_data;
            pop_en_o = e_pop_w;
            /*
            ---- taken BCND/CC/BCNDD/CCD with op bit 1: clear OV
                 (ALU copy; the address unit's mirror follows the
                 ALU at the next ST0/ST1 load). ----
            */
            if (e_ov_clear_w) begin
                alu_flag_ov_we_o = 1'b1;
                alu_flag_ov_in_o = 1'b0;
            end
            /*
            ---- per-instruction specials (old OP_DATA/EXEC arms) ----
            */
            case (op_hi)
                8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05,
                8'h06, 8'h07: begin /* LAR dma */
                    ar_wr_en_o = 1'b1;
                    ar_wr_sel_o = op_hi[2:0];
                    ar_wr_data_o = d_w;
                end
                8'h0B: begin /* RPT dma */
                    rptc_ld_en_o = 1'b1;
                    rptc_ld_data_o = d_w;
                end
                8'h0D: begin /* LDP dma: DP = d[8:0] */
                    st0_ld_en_o = 1'b1;
                    /* ST0 is rebuilt here, so an ARP switch of this very instruction (LDP *,ARn) has to be folded in: the new ARP, not the old one */
                    st0_ld_data_o = {(re_i.desc.valid && re_i.desc.arp_sw) ? re_i.desc.new_arp : stat_arp,
                                     stat_ov, stat_ovm, 1'b1, stat_intm, d_w[8:0]};
                end
                8'h0E: begin /* LST #0 (ARP/OV/OVM/DP; INTM kept) */
                    addr_wr_en_o = 1'b1;
                    addr_wr_sel_o = WR_ST0L;
                    addr_wr_data_o = d_w;
                    alu_flag_ov_we_o = 1'b1;
                    alu_flag_ov_in_o = d_w[12];
                end
                8'h0F: begin /* LST #1 (ARB/CNF/TC/SXM/C/HM/XF/PM) */
                    addr_wr_en_o = 1'b1;
                    addr_wr_sel_o = WR_ST1L;
                    addr_wr_data_o = d_w;
                    alu_flag_c_we_o = 1'b1;
                    alu_flag_c_in_o = d_w[9];
                end
                8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45,
                8'h46, 8'h47, 8'h48, 8'h49, 8'h4A, 8'h4B,
                8'h4C, 8'h4D, 8'h4E, 8'h4F: begin
                    /* BIT: TC = bit (15-shift) of d */
                    st_bit_en_o = 1'b1;
                    st_bit_sel_o = FLG_TC;
                    st_bit_val_o = d_w[4'd15 - op_hi[3:0]];
                end
                8'h58, 8'h59, 8'h5A, 8'h5B,
                8'h5C, 8'h5D, 8'h5E, 8'h5F: begin
                    /* XPL/OPL/APL/CPL: TC = (result == 0) */
                    st_bit_en_o = 1'b1;
                    st_bit_sel_o = FLG_TC;
                    st_bit_val_o = xpl_tc_w;
                end
                8'h6F: begin /* BITT: TC = bit (~TREG2) of d */
                    st_bit_en_o = 1'b1;
                    st_bit_sel_o = FLG_TC;
                    st_bit_val_o = d_w[~treg2_i[3:0]];
                end
                8'hB0, 8'hB1, 8'hB2, 8'hB3, 8'hB4, 8'hB5, 8'hB6,
                8'hB7: begin /* LAR #k8 (k8 = op_lo) */
                    ar_wr_en_o = 1'b1;
                    ar_wr_sel_o = op_hi[2:0];
                    ar_wr_data_o = {8'b0, op_lo};
                end
                8'hBB: begin /* RPT #k8 */
                    rptc_ld_en_o = 1'b1;
                    rptc_ld_data_o = {8'b0, op_lo};
                end
                8'hBC, 8'hBD: begin /* LDP #k9 (k9 = op[8:0]) */
                    st0_ld_en_o = 1'b1;
                    st0_ld_data_o = {stat_arp, stat_ov, stat_ovm,
                                     1'b1, stat_intm, op_q[8:0]};
                end
                8'hBE: begin
                    if (op_lo < 8'h20) begin
                        /* Accumulator ops: the ALU does the work;
                           TC is the ALU's o_tc_next (the top wires
                           it into the address unit's flag port). */
                    end else if (op_lo >= 8'h40 &&
                                 op_lo <= 8'h4F) begin
                        /* Single-bit status ops (EINT/DINT/ROVM/
                           SOVM/RCNF/SCNF/RSXM/SSXM/RHM/SHM/RTC/
                           STC/RXF/SXF/RCB/SCB).  The flag is the
                           pair index op_lo[3:1]; op_lo[0] is set
                           versus clear. */
                        st_bit_en_o = 1'b1;
                        case (op_lo[3:1])
                            3'b000: st_bit_sel_o = FLG_INTM;
                            3'b001: st_bit_sel_o = FLG_OVM;
                            3'b010: st_bit_sel_o = FLG_CNF;
                            3'b011: st_bit_sel_o = FLG_SXM;
                            3'b100: st_bit_sel_o = FLG_HM;
                            3'b101: st_bit_sel_o = FLG_TC;
                            3'b110: st_bit_sel_o = FLG_XF;
                            default: st_bit_sel_o = FLG_C;
                        endcase
                        st_bit_val_o = (op_lo[0] == 1'b1);
                        /* Only RCB/SCB change C, so only they
                           sync the ALU's C copy. */
                        if (op_lo[3:1] == 3'b111) begin
                            alu_flag_c_we_o = 1'b1;
                            alu_flag_c_in_o = (op_lo[0] == 1'b1);
                        end
                    end else if (op_lo == 8'hC4 || op_lo == 8'hC5) begin
                        /* RPT #lk / RPTZ #lk: rptc = imm. */
                        rptc_ld_en_o = 1'b1;
                        rptc_ld_data_o = imm_q;
                    end else if (op_lo == 8'hC6) begin
                        /* RPTB: braf=1, pasr=pc (first block word),
                           paer=imm.  BRCR is a separate MMR. */
                        rptb_set_o = 1'b1;
                        rptb_pasr_o = pc_q;
                        rptb_paer_o = imm_q;
                    end
                end
                8'hBF: begin
                    if (op_lo <= 8'h03) begin /* SPM k */
                        st1_ld_en_o = 1'b1;
                        st1_ld_data_o = {stat_arb, stat_cnf, stat_tc,
                                         stat_sxm, stat_c, 1'b1, 1'b1,
                                         stat_hm, 1'b1, stat_xf, 1'b1,
                                         1'b1, op_lo[1:0]};
                    end else if (op_lo >= 8'h08 && op_lo <= 8'h0F) begin
                        /* LAR #lk */
                        ar_wr_en_o = 1'b1;
                        ar_wr_sel_o = op_lo[2:0];
                        ar_wr_data_o = imm_q;
                    end else if (op_lo >= 8'h44 && op_lo <= 8'h47) begin
                        /* CMPR: TC = compare(AR[ARP], ARCR) */
                        st_bit_en_o = 1'b1;
                        st_bit_sel_o = FLG_TC;
                        st_bit_val_o = cmpr_tc_w;
                    end
                end
                default: begin end
            endcase
        end
        /*
        A RETCD's pop is deferred to slot completion (C: the slot
        runs first, then TOS -> PC and the stack is popped).  The
        pop is driven here, at the slot-completing instruction's
        retire; the target (pop_data, read now) is the
        retire_next_pc_w in p08.
        */
        if (slot_done_w && slot_take_w &&
            (slot_top_kind_w == 3'd2)) begin
            pop_en_o = 1'b1;
        end
        /*
        ---- loop / entry / restore overrides (the E stage is
             occupied by one of these, not by a normal
             instruction; last assignment wins) ----
             The loop's memory outputs are presented under
             loop_mem_present_w (not loop_ovr_w): gating them on
             loop_ovr_w (= loop_exec_w) would close the
             combinational loop through the memory's o_e_stall.
             The loop's ALU and address-unit outputs stay under
             loop_ovr_w: they are registered effects that must
             land exactly once per iteration.
        */
        if (loop_mem_present_w) begin
            /* the loop op's data source is a live register / host-window address (the R read port defers those): read it in E like a normal instruction does (H3); the loop stays held until e_rdata is valid */
            if (loop_def_rd_w) begin
                e_rd_req_o  = 1'b1;
                e_rd_addr_o = loop_def_addr_w;
            end
            if (loop_e_wr_w) begin
                e_wr_o = 1'b1;
                e_wr_addr_o = loop_wr_addr_w;
                e_wr_data_o = loop_wr_data_w;
                e_wr_flush_en_o = loop_wr_is_code_w;
            end
            if (loop_pm_wr_w) begin
                pm_wr_req_o = 1'b1;
                pm_wr_addr_o = loop_wr_addr_w;
                pm_wr_data_o = loop_wr_data_w;
                pm_wr_is_e_o = 1'b1;
                pm_wr_flush_en_o = 1'b1;
            end
            if (loop_dmov_w) begin
                e_dmov_o = 1'b1;
                /* DMOV source is the current iteration's ea: the
                   bundle ea on the first iteration (loop_a_q is
                   not loaded until the activation edge), the
                   registered ea once active.  Bug 3, 2026-11-20. */
                e_dmov_src_o = loop_a_eff_w;
            end
        end
        if (loop_ovr_w) begin
            alu_exec_o = 1'b1;
            alu_op_o = loop_alu_op_w;
            alu_b16_o = loop_alu_b16_w;
            alu_mpy_a_o = loop_mpy_a_w;
            alu_mpy_b_o = loop_mpy_b_w;
            alu_ld_acc_o = loop_ld_acc_w;
            alu_ld_preg_o = loop_ld_preg_w;
            alu_ld_treg0_o = loop_ld_treg0_w;
            if (loop_desc_en_w) begin
                desc_en_o = 1'b1;
                desc_ar_id_o = re_i.desc.ar_id;
                desc_mode_o = re_i.desc.mode;
                desc_arp_sw_o = re_i.desc.arp_sw;
                desc_new_arp_o = re_i.desc.new_arp;
                desc_ark_o = re_i.desc.ark;
                desc_hold_o = 1'b0;
            end
            if (loop_ndx_w)
                ndx_commit_o = 1'b1;
            if (loop_rptc_dec_w)
                rptc_dec_o = 1'b1;
        end
        /* Mechanism-(b) RPT replay decrement: NOT inside the
           loop override above (loop_ovr_w is false for a replay);
           it fires on its own whenever a replay iteration
           retires with rptc > 0. */
        if (replay_rptc_dec_w)
            rptc_dec_o = 1'b1;
        /* Loop rptc clamp (C handle_rpt): a loop op that retires
           with rptc == -1 (0-iteration while form, or a do-while
           that started at -1) leaves rptc at 0, not -1.  The
           per-iteration decrement is already suppressed at
           rptc <= 0, so this covers only the starting -1. */
        if (e_retire_w && re_i.is_loop_a && (rptc_i == RPTC_MINUS1)) begin
            rptc_ld_en_o = 1'b1;
            rptc_ld_data_o = 16'd0;
        end
        if (entry_ovr_w) begin
            push_en_o = 1'b1;
            push_data_o = entry_push_pc_w;
            st_bit_en_o = 1'b1;
            st_bit_sel_o = FLG_INTM;
            st_bit_val_o = 1'b1;
            if (!entry_is_intr_q)
                irq_ack_o = (9'd1 << entry_idx_q);
        end
        if (restore_ovr_w) begin
            alu_exec_o = (rst_alu_op_w != ALU_NOP);
            alu_op_o = rst_alu_op_w;
            alu_b16_o = rst_alu_b16_w;
            alu_b32_o = rst_alu_b32_w;
            alu_mpy_a_o = rst_mpy_a_w;
            alu_mpy_b_o = rst_mpy_b_w;
            alu_mpy_unsigned_o = (rst_alu_op_w == ALU_MPYU);
            alu_ld_acc_o = rst_ld_acc_w;
            alu_ld_preg_o = rst_ld_preg_w;
            alu_ld_treg0_o = rst_ld_treg0_w;
            alu_treg12_wr_en_o = rst_treg12_en_w;
            alu_treg12_sel_o = rst_treg12_sel_w;
            alu_treg12_data_o = rst_treg12_data_w;
            if (rst_st0_w) begin
                st0_ld_en_o = 1'b1;
                st0_ld_data_o = {sh_arp_q, sh_ov_q, sh_ovm_q, 1'b1,
                                 stat_intm, sh_dp_q};
                alu_flag_ov_we_o = 1'b1;
                alu_flag_ov_in_o = sh_ov_q;
            end
            if (rst_st1_w) begin
                st1_ld_en_o = 1'b1;
                st1_ld_data_o = {sh_arb_q, sh_cnf_q, sh_tc_q,
                                 sh_sxm_q, sh_c_q, 1'b1, 1'b1,
                                 sh_hm_q, 1'b1, stat_xf, 1'b1,
                                 1'b1, sh_pm_q};
                alu_flag_c_we_o = 1'b1;
                alu_flag_c_in_o = sh_c_q;
            end
            if (rst_pmst_w) begin
                pmst_ld_en_o = 1'b1;
                pmst_ld_data_o = {sh_iptr_q, 3'b000, sh_avis_q,
                                  1'b0, sh_ovly_q, sh_ram_q,
                                  sh_mpmc_q, sh_ndx_q, sh_trm_q,
                                  sh_braf_q};
            end
            if (rst_addr_wr_w) begin
                addr_wr_en_o = 1'b1;
                addr_wr_sel_o = rst_addr_sel_w;
                addr_wr_data_o = rst_addr_data_w;
            end
            if (rst_st_bit_w) begin
                st_bit_en_o = 1'b1;
                st_bit_sel_o = FLG_INTM;
                st_bit_val_o = 1'b0;
            end
        end
    end

    /*
    ------------------------------------------------------------------
    Retire decision, next PC, cycle charge, interrupt entry,
    delay slots and the XC window (plan sections 4-7).
    The E stage retires one instruction per clock in steady state.
    A loop (mechanism a) retires once, at its last iteration; a
    replay (mechanism b) retires once per iteration; the restore
    retires at phase 7; the interrupt entry retires as a separate
    pseudo-instruction BEFORE the E instruction (so the E
    instruction is held one clock by the entry).
    ------------------------------------------------------------------
    */
    logic entry_detect_w, entry_retire_w;
    logic entry_pending_w;
    logic idle_wake_w;
    logic entry_is_intr_w;
    logic [4:0] entry_idx_w;
    logic e_retire_w, e_would_retire_w, e_branch_flush_w;
    logic [15:0] retire_next_pc_w;
    logic [15:0] post_exec_pc_w;
    logic [31:0] retire_cyc_w;
    /* cycles charged by an interrupt entry: 4 for a hardware interrupt; INTR is already charged 4 in all by the instruction itself (C), so its entry adds none */
    logic [3:0]  entry_cyc_w;
    assign entry_cyc_w = entry_is_intr_q ? 4'd0 : 4'd4;
    logic slot_done_w, slot_take_w;
    logic [15:0] slot_tgt_w;
    logic rpt_rewind_w;
    logic braf_rewind_w, braf_done_w;
    logic int_held_w;
    logic [15:0] entry_vec_w;
    logic entry_via_ind_w;
    logic [2:0] io_ws_host_w;
    logic e_is_in_w, e_is_out_w;
    logic e_dm_host_rd_w, e_dm_host_wr_w, e_dm_periph_wr_w;

    /* The E instruction is an IN / OUT. */
    assign e_is_in_w = re_i.valid && (op_hi == 8'hAF);
    assign e_is_out_w = re_i.valid && (op_hi == 8'h0C);
    /* A deferred read from the host window (io_read: +io_ws).
       The address is ea_q (live during a replay), not the frozen
       bundle ea: a repeated indirect read advances per iteration. */
    /* C: data 0x50..0x5F (MMR_IO_WINDOW) and 0xFF50..0xFF5F (host window) both go through io_read / io_write, which charge the IOWSR/CWSR wait states */
    assign e_dm_host_rd_w = re_i.valid && re_i.deferred &&
                            (((ea_q >= 16'hFF50) && (ea_q <= 16'hFF5F)) ||
                             ((ea_q >= 16'h0050) && (ea_q <= 16'h005F)));
    /* An E data write to the host window (io_write: +io_ws-1). */
    assign e_dm_host_wr_w = re_i.valid && ex_dm_wr &&
                            (((ex_dm_addr >= 16'hFF50) && (ex_dm_addr <= 16'hFF5F)) ||
                             ((ex_dm_addr >= 16'h0050) && (ex_dm_addr <= 16'h005F)));
    /* An E data write to a peripheral MMR (mmr_bus: +1). */
    /* LMMR / TBLR / BLDD #lk,dma write their destination (dma, page 0 for LMMR) without going through ex_dm_wr; C data_write charges the peripheral bus cycle for them too */
    assign e_dm_periph_wr_w = re_i.valid &&
                              ((ex_dm_wr &&
                                (ex_dm_addr >= DM_PERIPH_START) &&
                                (ex_dm_addr < DM_PERIPH_END)) ||
                               (!ex_dm_wr &&
                                ((re_i.op[15:8] == 8'h89) || (re_i.op[15:8] == 8'hA6) || (re_i.op[15:8] == 8'hA8)) &&
                                (ea_q >= DM_PERIPH_START) && (ea_q < DM_PERIPH_END)));
    assign io_ws_host_w = io_ws_f(e_dm_host_rd_w ? ea_q : ex_dm_addr,
                                  iowsr_i, cwsr_i);

    /*
    Interrupt held conditions (C interrupt_held, c5x_core.c:2735):
    held while the XC window is open (xc_left > 0 after the
    subtraction, or xc_new), while the retiring instruction is
    the last word of a 1-instruction RPTB block (braf && pc ==
    paer, where pc is the next PC after the retiring
    instruction), while the EINT one-cycle inhibit is set, or
    while INTM is set.  The entry is taken only at a retirement
    (never during a mechanism-(a) loop, which has not retired
    yet; a replay may be interrupted -- the replay is aborted
    and the repeat continues via handle_rpt after the return).
    */
    logic [2:0] xc_left_after_w;
    assign xc_left_after_w = xc_new_q ? 3'd0 :
                             (xc_left_q > {1'b0, words_q[1:0]}) ?
                             (xc_left_q - {1'b0, words_q[1:0]}) : 3'd0;
    /* RETE completing: INTM is 0 once this retire lands (C: the interrupt check follows the instruction), so a pending interrupt is taken at this boundary */
    logic retiring_rete_w;
    assign retiring_rete_w = restore_active_q && (rst_ph_q == 4'd7) && restore_is_rete_q;
    /* The RETE retires first and its 8-phase context restore runs after it (E is empty meanwhile); INTM is cleared by the last phase.  C checks for a pending interrupt right after RETE, with no main instruction in between, so the entry is detected at that last phase (E empty, like an idle wake) and returns to the RETE's target. */
    logic [15:0] rete_tgt_q;
    assign int_held_w = (xc_new_q || (xc_left_after_w != 3'd0)) ||
                        (stat_braf &&
                         ((post_exec_pc_w - 16'd1) == paer_i)) ||
                        (stat_intm && !retiring_rete_w) ||
                        /* EINT: its own retire takes no entry (C: interrupt_inhibit is set by EINT and consumed by the check that follows it), the next instruction does. int_inh_q used to hold the entry off through the NEXT retire as well, one instruction too many: a nested interrupt in an ISR that starts with EINT was taken after the second instruction and the shadow saved the ISR's ACC */
                        (re_i.valid && (op_hi == 8'hBE) && (op_lo == 8'h40)) ||
                        /* DINT / SETC INTM (BE41) in E: INTM becomes 1 at this retire, so no entry at the same boundary (C: the check follows the instruction) */
                        (re_i.valid && (op_hi == 8'hBE) && (op_lo == 8'h41)) ||
                        /* C: a taken delayed branch/call/return and its slot words run as one step (delay_slot()), the interrupt check follows it: no entry while the E instruction opens a slot or a slot word retires but is not the last one */
                        (re_i.is_delayed && ex_ds_take && !slot_done_w) ||
                        (ds_in_slot_q && !slot_done_w) ||
                        /* C: RPT and the repeated instruction run all their iterations as one step (the while (rptc > -1) loop), the interrupt check follows it: no entry between iterations. rpt_rewind_w = an iteration retires and repeats remain. */
                        rpt_rewind_w;
    /* The instruction would retire this clock (ignoring the
       entry, which preempts it); the entry decision uses this so
       there is no combinational loop through e_hold_w. */
    /* The E instruction is a software INTR (0xBE, lo&0xE0==0x60):
       it arms an entry with vector k*2, no hardware pending bit. */
    assign entry_is_intr_w = re_i.valid && (op_hi == 8'hBE) &&
                             ((op_lo & 8'hE0) == 8'h60);
    assign entry_idx_w = entry_is_intr_w ? re_i.op[4:0] :
                         {1'b0, int_sel_w};
    /* A mechanism-(a) loop retires once, at its last iteration;
       at its first iteration it does not retire (unless it is a
       single iteration).  A replay retires once per iteration. */
    assign e_would_retire_w = re_i.valid && !e_hold_mem_w &&
                              ((loop_active_q &&
                                (loop_cnt_q <= 32'd1)) ||
                               (restore_active_q &&
                                (rst_ph_q == 4'd7)) ||
                               (!loop_active_q && !restore_active_q &&
                                !(re_i.is_loop_a &&
                                  (loop_iters_w > 32'd1))));
    /* Interrupt detect: at a would-retire edge, or on an idle
       wake (no instruction in E when parked).  The entry fires
       two clocks later (entry_pend2_q), after the retiring
       instruction's effects have landed, so the shadow latched
       at the fire edge is the post-instruction state, matching
       C save_ctx (which runs after exec1_op).  The extra clock
       (vs one) leaves instr_done low for a clock between the
       instruction retire and the entry retire; without it the
       two merge into one rising edge.  The E instruction is
       suppressed only at the fire edge, not at detect. */
    assign entry_detect_w = (e_would_retire_w || retiring_rete_w ||
                            ((idle_q != 2'd0) && idle_wake_w)) &&
                           (((irq_pend_eff_w && int_sel_found_w) &&
                             !int_held_w) || entry_is_intr_w);
    assign entry_pending_w = entry_detect_w || entry_pend_q ||
                             entry_pend2_q;
    /* IDLE wakes on any (IFR & IMR); IDLE2 only on RS/NMI/INT1-4
       (mask 0x107: INT0/INT1/INT2/NMI/RS per manual 4.10.2). */
    assign idle_wake_w = (idle_q == 2'd1) ?
                         ((ifr_i & imr_i) != 16'd0) :
                         (idle_q == 2'd2) ?
                         (((ifr_i & imr_i) & 16'h0107) != 16'd0) :
                         1'b0;
    assign entry_retire_w = entry_pend2_q;
    /* The entry retires one clock after the E instruction, so the
       shadow is post-instruction. */
    assign e_retire_w = e_would_retire_w && !entry_retire_w;
    /* The R/E bundle is consumed at the retire edge, so it cannot
       retire twice: a normal instruction retires once and leaves
       R/E, a mechanism-(a) loop retires only at its last
       iteration, and a mechanism-(b) replay retires once per
       iteration but the bundle stays in R/E until its last
       iteration (replay_cnt_q <= 1).  An entry retire does NOT
       consume the E instruction (it is held for after entry).
       The rewind edge (rpt_rewind_w, replay not yet active) does
       NOT consume: the replay is just starting and the bundle
       must stay in R/E for the next iteration. */
    assign e_consume_o = e_retire_w &&
                         (!replay_active_q ||
                          (replay_cnt_q <= 32'd1)) &&
                         !(rpt_rewind_w && !replay_active_q);
    /* A taken branch/call/return flushes F/D/R (H5, 4-cycle flush:
       the 3 pipeline bubbles plus the branch's own extra cycle). */
    assign e_branch_flush_w = e_retire_w &&
                              ((((e_pc_act_w == PC_JMP) ||
                                 (e_pc_act_w == PC_RET) ||
                                 (e_pc_act_w == PC_DSLOT)) &&
                                !re_i.is_delayed) ||
                               (slot_done_w && slot_take_w));

    /* RPT rewind (C handle_rpt): the repeated instruction just
       retired and repeats remain. */
    assign rpt_rewind_w = e_would_retire_w && (rptc_i > 0) &&
                          (re_i.pc == rpt_end_q);
    /* RPTB block-end test (C handle_braf): the retiring
       instruction ends at paer. */
    assign braf_rewind_w = e_would_retire_w && stat_braf &&
                           ((post_exec_pc_w - 16'd1) == paer_i) &&
                           (brcr_i != 32'd0);
    assign braf_done_w = e_would_retire_w && stat_braf &&
                         ((post_exec_pc_w - 16'd1) == paer_i) &&
                         (brcr_i == 32'd0);
    assign braf_check_o = braf_rewind_w || braf_done_w;
    assign braf_pc_o = post_exec_pc_w;

    /* Delay-slot completion: the retiring instruction is a slot
       word and the word count reaches zero. */
    /* A false XC inside a slot skips the next 1 or 2 words (C: delay_slot counts them as slot words); they never retire, so they must count here or the slot would
       swallow the first instruction after it. */
    logic [2:0] xc_skip_slot_w;
    assign xc_skip_slot_w = (((op_hi >= 8'hE4) && (op_hi <= 8'hE7)) || ((op_hi >= 8'hF4) && (op_hi <= 8'hF7))) && !ex_ds_take ?
                            ({2'b00, op_q[12]} + 3'd1) : 3'd0;
    assign slot_done_w = e_would_retire_w && ds_in_slot_q &&
                         (ds_words_left_q <= ({1'b0, words_q[1:0]} + xc_skip_slot_w));
    assign slot_take_w = ds_take_q[ds_sp_q - 3'd1];
    assign slot_tgt_w = ds_tgt_q[ds_sp_q - 3'd1];
    logic [2:0] slot_top_kind_w;
    assign slot_top_kind_w = ds_kind_q[ds_sp_q - 3'd1];
    /* Kind / target of the slot the E instruction opens (if it is
       a taken delayed instruction).  BACCD/CALAD jump to ACC;
       the other kinds jump to the executor's target (imm). */
    logic [2:0] slot_new_kind_w;
    logic [15:0] slot_new_tgt_w;
    always_comb begin
        slot_new_kind_w = 3'd0;
        slot_new_tgt_w = e_pc_tgt_w;
        if (op_hi == 8'h7E) begin
            slot_new_kind_w = 3'd1; /* CALLD */
        end else if ((op_hi >= 8'hF8) && (op_hi <= 8'hFB)) begin
            slot_new_kind_w = 3'd1; /* CCD */
        end else if ((op_hi >= 8'hFC)) begin
            slot_new_kind_w = 3'd2; /* RETCD */
        end else if ((op_hi == 8'hBE) && (op_lo == 8'h21)) begin
            slot_new_kind_w = 3'd3; /* BACCD */
            slot_new_tgt_w = acc_i[15:0];
        end else if ((op_hi == 8'hBE) && (op_lo == 8'h3D)) begin
            slot_new_kind_w = 3'd4; /* CALAD */
            slot_new_tgt_w = acc_i[15:0];
        end
    end

    /* Next PC after this retire (C: exec1, then handle_rpt /
       handle_braf override; the delay-slot completion overrides
       them when the slot ends on this instruction). */
    /* Post-exec1 PC (before the handle_rpt / handle_braf
       overrides).  The block-end tests use this, not the final
       next PC -- the rewinds override the final PC, so testing
       the final PC would be a combinational loop. */
    always_comb begin
        if (slot_done_w) begin
            if (slot_take_w && (slot_top_kind_w == 3'd2))
                post_exec_pc_w = pop_data;
            else if (slot_take_w)
                post_exec_pc_w = slot_tgt_w;
            else
                post_exec_pc_w = pc_q;
        end else if (re_i.is_delayed && br_taken_q) begin
            /* A taken delayed branch falls through to the slot
               words; the jump is applied at slot completion. */
            post_exec_pc_w = pc_q;
        end else if (e_pc_act_w == PC_JMP) begin
            post_exec_pc_w = e_pc_tgt_w;
        end else if (e_pc_act_w == PC_RET) begin
            post_exec_pc_w = pop_data;
        end else if (e_pc_act_w == PC_IDLE) begin
            post_exec_pc_w = pc_q;
        end else begin
            post_exec_pc_w = pc_q;
        end
    end
    /* handle_rpt / handle_braf override the exec1 PC. */
    always_comb begin
        retire_next_pc_w = post_exec_pc_w;
        if (rpt_rewind_w)
            retire_next_pc_w = rpt_start_q;
        if (braf_rewind_w)
            retire_next_pc_w = pasr_i;
    end
    /* Interrupt entry vector (C check_int / do_int): the lowest
       set bit of (ifr & imr); TRAP (0x22) / NMI (0x24) for the
       software forms.  The full vector is (iptr<<11)|ivec.
       When the entry is via ivec_ind (entry_via_ind_q, latched
       at entry_take), the vector is dmem[ivec_ind[i]], read in
       the entry's E clock through the E deferred read port
       (o_e_rdata is valid in the presented clock). */
    /* the indirection address of the entry being detected (new index / INTR operand, not the previous entry's), latched with the entry */
    logic [15:0] entry_ind_addr_w, entry_ind_new_w, entry_ind_q;
    always_comb begin
        entry_ind_new_w = 16'd0;
        if (entry_is_intr_w)
            entry_ind_new_w = intr_ind_addr_w;
        else if (entry_idx_w <= 5'd8)
            entry_ind_new_w = ivec_ind_i[{entry_idx_w[3:0], 4'b0000} +: 16];
    end
    assign entry_ind_addr_w = entry_ind_q;
    assign entry_via_ind_w = (entry_ind_new_w != 16'd0);
    always_comb begin
        entry_vec_w = 16'd0;
        if (entry_pend2_q && entry_via_ind_q) begin
            entry_vec_w = r_data_i;
        end else if (entry_is_intr_q) begin
            /* latched with the entry: the vector is used two clocks after the INTR retired, when the live entry_is_intr_w / entry_idx_w describe whatever retires now (vector 0) */
            entry_vec_w = {10'b0, entry_idx_q, 1'b0};
        end else if (int_sel_found_w) begin
            entry_vec_w = {stat_iptr, 3'b000, c5x_ivec(int_sel_w)};
        end
    end

    /*
    Whether this entry saves the interrupt shadow context (C
    save_ctx, c5x_core.c exec_be, KD-12). A hardware entry always
    saves. An INTR entry saves only when K is 1, 2, 3 or 9
    (vector 02/04/06/12) or the vector went via ivec_ind (the
    audited or legacy table hit). Any other INTR (K = 0 included)
    does not save, so the shadow keeps its previous values and
    RETE restores those. The latch below must follow this rule:
    latching live state on an INTR 0 entry diverges from the C
    model (shadow acc 0x11 vs C 0x00, arcr/indx 0x60 vs 0x00) and
    fails the intr-rete directed test at the RETE step.
    */
    logic entry_saves_ctx_w;
    always_comb begin
        entry_saves_ctx_w = 1'b1;
        if (entry_is_intr_q) begin
            case (entry_idx_q)
                5'd1, 5'd2, 5'd3, 5'd9: entry_saves_ctx_w = 1'b1;
                default: entry_saves_ctx_w = entry_via_ind_q;
            endcase
        end
    end

    /*
    Cycle charge for this retire (C instr_cycles + io_read /
    io_write + mmr_bus; the entry retire charges 4).  The slot
    words charge their own cycm when they retire; the loop's
    per-iteration cost is folded into the single loop retire
    ((n-1)*k, C: the loop body charges 2 per iteration in the
    multi-cycle engine -- here the replay/loop engine counts
    the extra clocks in cnt_rpt_replay_q / cnt_mac_replay_q and
    the charge is base + (n-1)*k with k from the loop kind).
    */
    logic [31:0] loop_extra_w;
    /* (n-1)*k: k = 2 for SMMR/LMMR ("Repeat total 2n", C
       exec_09/exec_89), k = 1 for BLDP/BLPD/TBLR/TBLW/BLDD/
       MAC/MADS (C: c->cycles++ per iteration after the first).
       n is the latched total (loop_cnt_q is 1 at the retiring
       edge). */
    logic [31:0] loop_k_w;
    assign loop_k_w = ((loop_kind_q == LOOP_SMMR) ||
                       (loop_kind_q == LOOP_LMMR)) ? 32'd2 : 32'd1;
    assign loop_extra_w = (loop_total_q > 32'd1) ?
                          ((loop_total_q - 32'd1) * loop_k_w) : 32'd0;
    always_comb begin
        retire_cyc_w = {24'd0, base_cyc_q};
        if (entry_retire_w) begin
            /* a hardware interrupt entry costs 4; INTR is charged 4 in all by the instruction itself (C), so its entry adds nothing */
            retire_cyc_w = {28'd0, entry_cyc_w};
        end else if (loop_active_q) begin
            retire_cyc_w = {24'd0, base_cyc_q} + loop_extra_w;
        end else begin
            if (e_is_in_w)
                retire_cyc_w = retire_cyc_w + {29'd0, e_io_ws_w};
            if (e_is_out_w && (e_io_ws_w > 3'd1))
                retire_cyc_w = retire_cyc_w +
                               {29'd0, (e_io_ws_w - 3'd1)};
            if (e_dm_host_rd_w)
                retire_cyc_w = retire_cyc_w + {29'd0, io_ws_host_w};
            if (e_dm_host_wr_w && (io_ws_host_w > 3'd1))
                retire_cyc_w = retire_cyc_w +
                               {29'd0, (io_ws_host_w - 3'd1)};
            if (e_dm_periph_wr_w)
                retire_cyc_w = retire_cyc_w + 32'd1;
        end
    end

    /*
    ------------------------------------------------------------------
    Loop / replay / entry / restore E-commit overrides.  When the E
    stage is occupied by a loop iteration, the interrupt entry or
    the restore sequencer, the datapath outputs come from here, not
    from the normal E-commit (p07); the override section at the end
    of p07 applies them (last assignment wins in that always_comb).
    The replay (mechanism b) re-issues the held bundle, so it uses
    the normal E-commit (ex_*) -- only the bundle re-issue below
    is replay-specific.
    ------------------------------------------------------------------
    */
    /* Effective loop address/pfc for the current iteration:
       the registered values once the loop is active, the
       bundle's ea/pfc before activation (1-iteration loop, or
       the first iteration of a multi-iteration loop). */
    logic [15:0] loop_a_eff_w, loop_pfc_eff_w;
    assign loop_a_eff_w = loop_active_q ? loop_a_q : re_i.ea;
    assign loop_pfc_eff_w = loop_active_q ? loop_pfc_q : re_i.pfc;
    /* Loop iteration source data: the R read (data) and the fetch
       port read (program). */
    logic [15:0] loop_dma_w, loop_pma_w;
    /* a source the read port defers (live registers, host window) is read in E: take the E re-read data, as e_operand_w does */
    logic loop_def_rd_w;
    logic [15:0] loop_def_addr_w;
    /* SMMR & co. read their source at the ea; LMMR reads its source at the program-word address (pfc) through the data channel: either may be a live register or a host-window address */
    assign loop_def_rd_w   = (re_i.deferred && re_i.ea_use) ||
                             ((re_i.op[15:8] == 8'h89) && is_deferred_f(loop_pfc_eff_w));
    assign loop_def_addr_w = (re_i.op[15:8] == 8'h89) ? loop_pfc_eff_w : loop_a_eff_w;
    assign loop_dma_w = loop_def_rd_w ? e_rdata_i : r_data_i;
    assign loop_pma_w = r2_data_i;
    /* Loop destination (per the old loop_dst_w, C exec_a2..ad).
       Uses re_i.loop_kind, not the registered loop_kind_q: a
       1-iteration loop never activates (loop_active_q stays 0)
       and so never loads loop_kind_q, but its bundle kind is
       valid in E.  During a multi-iteration loop the op stays
       in R/E, so the two agree. */
    logic [15:0] loop_dst_w;
    always_comb begin
        case (re_i.loop_kind)
            LOOP_SMMR: loop_dst_w = loop_pfc_eff_w;
            LOOP_LMMR: loop_dst_w = loop_a_eff_w;
            LOOP_BLDP: loop_dst_w = loop_pfc_eff_w;
            LOOP_BLPD: loop_dst_w = loop_a_eff_w;
            LOOP_TBLR: loop_dst_w = loop_a_eff_w;
            LOOP_TBLW: loop_dst_w = loop_pfc_eff_w;
            LOOP_BLDD: begin
                if ((re_i.op[15:8] == 8'hA8) ||
                    (re_i.op[15:8] == 8'hAC))
                    loop_dst_w = loop_a_eff_w;
                else
                    loop_dst_w = loop_pfc_eff_w;
            end
            default: loop_dst_w = loop_a_eff_w;
        endcase
    end
    /* Loop iteration count / kind flags for the loop start
       (C: while forms execute 0 iterations when rptc == -1, else
       rptc+1; do-while forms -- MAC/MACD/MADS/MADD -- execute at
       least 1). */
    logic [31:0] loop_iters_w;
    logic loop_needs_pm_w, loop_do_while_w;
    assign loop_do_while_w = (re_i.loop_kind == LOOP_MAC) ||
                             (re_i.loop_kind == LOOP_MADS);
    /* The program read (pma) rides the fetch port, one per
       iteration, for the MAC/MADS multiply operand only.  BLPD
       and TBLR read their PMEM source through the R port
       (is_prog = 1), so they need no fetch-port read and their
       write data is loop_dma_w, not loop_pma_w. */
    assign loop_needs_pm_w = loop_do_while_w;
    assign loop_iters_w = (rptc_i == RPTC_MINUS1) ?
                          (loop_do_while_w ? 32'd1 : 32'd0) :
                          (rptc_i + 32'd1);
    /* Is this loop iteration's E write to a code address (H10)? */
    logic loop_wr_is_code_w;
    assign loop_wr_is_code_w = (loop_dst_w >= 16'h8000) ||
        (stat_ovly && (loop_dst_w >= 16'h0800) &&
         (loop_dst_w < 16'h0C00));
    /* The loop iteration executes this clock (E is the loop op). */
    logic loop_exec_w;
    /* A 0-iteration while-form loop (rptc == -1) executes no
       iteration: no ALU, no descriptor commit, no rptc
       decrement.  The loop op still retires at once
       (e_would_retire_w is 1 while loop_iters_w <= 1).  Bug 3,
       2026-11-20. */
    assign loop_exec_w = re_i.valid && !e_hold_mem_w &&
                         ((re_i.is_loop_a && !loop_active_q &&
                           (loop_iters_w > 32'd0)) || loop_active_q);
    /* rptc-- per iteration, but only while rptc > 0: the C
       model post-decrements (rptc-- > 0) and handle_rpt then
       clamps a negative rptc to 0, so the architectural rptc
       never goes below 0.  Suppressing the decrement at
       rptc == 0 leaves it at 0, which is the clamped value;
       the do-while skip at rptc == -1 is subsumed (rptc > 0
       is false there too).  A loop that starts with
       rptc == -1 (0-iteration while form) still needs the
       clamp at its retire -- see p07 rptc_clamp_o. */
    logic loop_rptc_dec_w;
    assign loop_rptc_dec_w = loop_exec_w && (rptc_i > 32'sd0);
    /* Mechanism-(b) RPT replay decrement (C handle_rpt): rptc--
       whenever the repeated instruction retires with rptc > 0
       and pc == rpt_end -- exactly rpt_rewind_w at the retire
       edge.  Covers the first execution (rewind edge) and every
       replay iteration; the last iteration has rptc == 0, so
       rpt_rewind_w is low and rptc stays 0 (clamped). */
    logic replay_rptc_dec_w;
    assign replay_rptc_dec_w = e_retire_w && rpt_rewind_w;

    /* Loop E-commit override wires (applied in p07). */
    logic loop_ovr_w;
    logic [6:0] loop_alu_op_w;
    logic [15:0] loop_alu_b16_w;
    logic [15:0] loop_mpy_a_w, loop_mpy_b_w;
    logic loop_ld_acc_w, loop_ld_preg_w, loop_ld_treg0_w;
    logic loop_e_wr_w, loop_pm_wr_w, loop_dmov_w;
    logic [15:0] loop_wr_addr_w, loop_wr_data_w;
    logic loop_desc_en_w, loop_ndx_w;
    always_comb begin
        loop_ovr_w = loop_exec_w;
        loop_alu_op_w = ALU_NOP;
        loop_alu_b16_w = 16'd0;
        loop_mpy_a_w = 16'd0;
        loop_mpy_b_w = 16'd0;
        loop_ld_acc_w = 1'b0;
        loop_ld_preg_w = 1'b0;
        loop_ld_treg0_w = 1'b0;
        loop_e_wr_w = 1'b0;
        loop_pm_wr_w = 1'b0;
        loop_dmov_w = 1'b0;
        loop_wr_addr_w = 16'd0;
        loop_wr_data_w = 16'd0;
        loop_desc_en_w = 1'b0;
        loop_ndx_w = 1'b0;
        if (loop_mem_present_w) begin
            /* Memory outputs per iteration (presented, not
               executed: loop_mem_present_w is defined in p07,
               next to e_mem_present_w). */
            case (re_i.loop_kind)
                LOOP_SMMR: begin
                    /* dm_wr(pfc, d): a program write via the data
                       channel (C dm_wr routes it to PMEM). */
                    loop_e_wr_w = 1'b1;
                    loop_wr_addr_w = loop_pfc_eff_w;
                    loop_wr_data_w = loop_dma_w;
                end
                LOOP_LMMR: begin
                    /* dm_wr(a, d): the MMR (fixed ea) from the
                       program source (read via the DM channel). */
                    loop_e_wr_w = 1'b1;
                    loop_wr_addr_w = loop_a_eff_w;
                    loop_wr_data_w = loop_dma_w;
                end
                LOOP_BLDP: begin
                    /* pm_wr(pfc, d). */
                    loop_pm_wr_w = 1'b1;
                    loop_wr_addr_w = loop_pfc_eff_w;
                    loop_wr_data_w = loop_dma_w;
                end
                LOOP_BLPD, LOOP_TBLR: begin
                    /* dm_wr(a, d): the program source comes
                       through the R port (is_prog = 1), so the
                       data is loop_dma_w, not the fetch-port
                       loop_pma_w (which MAC/MADS use for the
                       second operand). */
                    loop_e_wr_w = 1'b1;
                    loop_wr_addr_w = loop_a_eff_w;
                    loop_wr_data_w = loop_dma_w;
                end
                LOOP_TBLW: begin
                    /* pm_wr(pfc, d). */
                    loop_pm_wr_w = 1'b1;
                    loop_wr_addr_w = loop_pfc_eff_w;
                    loop_wr_data_w = loop_dma_w;
                end
                LOOP_BLDD: begin
                    /* dm_wr(dst, d): the source is the R read
                       (data channel, pfc or ea). */
                    loop_e_wr_w = 1'b1;
                    loop_wr_addr_w = loop_dst_w;
                    loop_wr_data_w = loop_dma_w;
                end
                LOOP_MAC: begin
                    /* MACD additionally DMOVs dma -> dma+1
                       (the memory applies the dmov_wr gate). */
                    if (re_i.op[15:8] == 8'hA3) begin
                        loop_dmov_w = 1'b1;
                        loop_e_wr_w = 1'b1;                       /* dm[a+1] = dm[a] (the memory applies the dmov_wr gate) */
                        loop_wr_addr_w = loop_a_eff_w + 16'd1;
                        loop_wr_data_w = loop_dma_w;
                    end
                end
                LOOP_MADS: begin
                    /* MADD additionally DMOVs dma -> dma+1
                       (the memory applies the dmov_wr gate). */
                    if (re_i.op[15:8] == 8'hAB) begin
                        loop_dmov_w = 1'b1;
                        loop_e_wr_w = 1'b1;
                        loop_wr_addr_w = loop_a_eff_w + 16'd1;
                        loop_wr_data_w = loop_dma_w;
                    end
                end
                default: begin end
            endcase
        end
        if (loop_exec_w) begin
            /* Descriptor commit per iteration (SMMR/LMMR hoist
               ea() once, KD-9: no per-iteration descriptor). */
            if (!loop_ea_fixed_q) begin
                loop_desc_en_w = 1'b1;
                loop_ndx_w = 1'b1;
            end
            case (re_i.loop_kind)
                LOOP_MAC: begin
                    /* ALU_SQRA: ACC += pscale, PREG = dma*pma,
                       TREG0 = dma (with the TRM mirror). */
                    loop_alu_op_w = ALU_SQRA;
                    loop_alu_b16_w = loop_dma_w;
                    loop_mpy_a_w = loop_dma_w;
                    loop_mpy_b_w = loop_pma_w;
                    loop_ld_acc_w = 1'b1;
                    loop_ld_preg_w = 1'b1;
                    loop_ld_treg0_w = 1'b1;
                end
                LOOP_MADS: begin
                    /* ALU_LT_NM: ACC += OLD PREG, PREG = dma*pma,
                       TREG0 = dma, NO mirror (KD-23). */
                    loop_alu_op_w = ALU_LT_NM;
                    loop_alu_b16_w = loop_dma_w;
                    loop_mpy_a_w = loop_dma_w;
                    loop_mpy_b_w = loop_pma_w;
                    loop_ld_acc_w = 1'b1;
                    loop_ld_preg_w = 1'b1;
                    loop_ld_treg0_w = 1'b1;
                end
                default: begin end
            endcase
        end
    end

    /*
    Interrupt entry E-commit (the entry pseudo-instruction): push
    the return PC, set INTM, clear the serviced IFR bit.  The
    shadow latch and the vector jump are in the sequential block.
    */
    logic entry_ovr_w;
    assign entry_ovr_w = entry_active_q;
    logic [15:0] entry_push_pc_w;
    assign entry_push_pc_w = entry_ret_pc_q;

    /*
    Restore E-commit (8 phases; the MPYU+LPH trick for PREG, see
    the module header).  The address-unit restores run in parallel
    with the ALU restores (independent ports).  ST0 keeps the live
    INTM; ST1 keeps the live XF (audit #9); RETE clears INTM in
    ph7 via the flag port.
    */
    logic restore_ovr_w;
    assign restore_ovr_w = restore_active_q;
    logic [6:0] rst_alu_op_w;
    logic [15:0] rst_alu_b16_w;
    logic [31:0] rst_alu_b32_w;
    logic [15:0] rst_mpy_a_w, rst_mpy_b_w;
    logic rst_ld_acc_w, rst_ld_preg_w, rst_ld_treg0_w;
    logic rst_treg12_en_w, rst_treg12_sel_w;
    logic [15:0] rst_treg12_data_w;
    logic rst_st_bit_w;
    always_comb begin
        rst_alu_op_w = ALU_NOP;
        rst_alu_b16_w = 16'd0;
        rst_mpy_a_w = 16'd0;
        rst_mpy_b_w = 16'd0;
        rst_ld_acc_w = 1'b0;
        rst_ld_preg_w = 1'b0;
        rst_ld_treg0_w = 1'b0;
        rst_alu_b32_w = 32'd0;
        rst_treg12_en_w = 1'b0;
        rst_treg12_sel_w = 1'b0;
        rst_treg12_data_w = 16'd0;
        rst_st_bit_w = 1'b0;
        if (restore_active_q) begin
            case (rst_ph_q)
                4'd0: begin
                    /* PREG low half: MPYU(sh_preg[15:0], 1). */
                    rst_alu_op_w = ALU_MPYU;
                    rst_mpy_a_w = sh_preg_q[15:0];
                    rst_mpy_b_w = 16'd1;
                    rst_ld_preg_w = 1'b1;
                end
                4'd1: begin
                    /* PREG high half: LPH(sh_preg[31:16]). */
                    rst_alu_op_w = ALU_LPH;
                    rst_alu_b16_w = sh_preg_q[31:16];
                    rst_ld_preg_w = 1'b1;
                end
                4'd2: begin
                    /* TREG0 = sh_treg0 (LT). */
                    rst_alu_op_w = ALU_LT;
                    rst_alu_b16_w = sh_treg0_q;
                    rst_ld_treg0_w = 1'b1;
                end
                4'd3: begin
                    /* TREG1 = sh_treg1 (direct port). */
                    rst_treg12_en_w = 1'b1;
                    rst_treg12_sel_w = 1'b0;
                    rst_treg12_data_w = sh_treg1_q;
                end
                4'd4: begin
                    /* TREG2 = sh_treg2 (direct port). */
                    rst_treg12_en_w = 1'b1;
                    rst_treg12_sel_w = 1'b1;
                    rst_treg12_data_w = sh_treg2_q;
                end
                4'd5: begin
                    /* ACC = sh_accb (LD_B32). */
                    rst_alu_op_w = ALU_LD_B32;
                    rst_alu_b32_w = sh_accb_q;
                    rst_ld_acc_w = 1'b1;
                end
                4'd6: begin
                    /* ACCB = ACC (SACB). */
                    rst_alu_op_w = ALU_SACB;
                    rst_ld_acc_w = 1'b1;
                end
                4'd7: begin
                    /* ACC = sh_acc (LD_B32); RETE clears INTM
                       (the shadow INTM is deliberately not
                       restored). */
                    rst_alu_op_w = ALU_LD_B32;
                    rst_alu_b32_w = sh_acc_q;
                    rst_ld_acc_w = 1'b1;
                    if (restore_is_rete_q)
                        rst_st_bit_w = 1'b1;
                end
                default: begin end
            endcase
        end
    end
    /* The restore's address-unit writes (ST0/ST1/PMST/ARCR/INDX)
       and flag syncs, by phase (old restore phases 4-8). */
    logic rst_addr_wr_w;
    logic [5:0] rst_addr_sel_w;
    logic [15:0] rst_addr_data_w;
    logic rst_st0_w, rst_st1_w, rst_pmst_w;
    always_comb begin
        rst_addr_wr_w = 1'b0;
        rst_addr_sel_w = 6'd0;
        rst_addr_data_w = 16'd0;
        rst_st0_w = 1'b0;
        rst_st1_w = 1'b0;
        rst_pmst_w = 1'b0;
        if (restore_active_q) begin
            case (rst_ph_q)
                4'd0: begin
                    /* ST0 (ARP/OV/OVM/DP; INTM live) + OV sync. */
                    rst_st0_w = 1'b1;
                end
                4'd1: begin
                    /* ST1 (ARB/CNF/TC/SXM/C/HM/PM; XF live) + C sync. */
                    rst_st1_w = 1'b1;
                end
                4'd2: begin
                    rst_pmst_w = 1'b1;
                end
                4'd3: begin
                    rst_addr_wr_w = 1'b1;
                    rst_addr_sel_w = WR_ARCR;
                    rst_addr_data_w = sh_arcr_q;
                end
                4'd4: begin
                    rst_addr_wr_w = 1'b1;
                    rst_addr_sel_w = WR_INDX;
                    rst_addr_data_w = sh_indx_q;
                end
                default: begin end
            endcase
        end
    end

    /*
    ------------------------------------------------------------------
    The loop / replay freezes the pipeline (F/D/R held, E
    re-executes the frozen bundle).  No bundle is re-issued into
    R: the next sequential instruction stays in R, held, and
    resumes when the loop / replay ends.  The R read for the next
    iteration is presented by the loop / replay branch of the
    R-stage presentation (p03), and the E execution uses the
    forwarded addresses (loop_a_q / loop_pfc_q / arau_next_i).
    ------------------------------------------------------------------
    */
    assign dr_o = d_bundle_w;
    assign re_o = dr_i;

    /* Flush / IO-wait events for the stall counters.  H10 counts
       flushes that actually fire (pm_flush_fire_w, p03), not
       flush-eligible presentations: a replay iteration's store
       to a code address is presented every iteration but the
       flush is deferred to the last iteration, so counting
       presentations would charge +3 per iteration. */
    logic e_io_wait_w;
    assign e_io_wait_w = e_io_req_o && !e_io_done_i;
    /*
    ------------------------------------------------------------------
    Sequential state.  All state updates are edge-triggered here;
    the combinational blocks above compute the next values.
    ------------------------------------------------------------------
    */
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            fetch_pc_q <= RESET_PC;
            fetch_addr_q <= 16'd0;
            fetch_inflight_q <= 1'b0;
            fetch_is_word2_q <= 1'b0;
            fetch_is_pma_q <= 1'b0;
            cycles_q <= 64'd0;
            retire_cnt_q <= 64'd0;
            retire_tgl_q <= 1'b0;
            instr_done_q <= 1'b0;
            retire_cycles_q <= 32'd0;
            retire_is_intr_q <= 1'b0;
            retire_pc_q <= RESET_PC;
            retire_op_q <= 16'd0;
            halted_q <= 1'b0;
            idle_q <= 2'd0;
            int_inh_q <= 1'b0;
            xc_new_q <= 1'b0;
            xc_left_q <= 3'd0;
            io_rep_q <= 16'd0;
            rpt_start_q <= 16'd0;
            rpt_end_q <= 16'd0;
            rep_cont_q <= 1'b0;
            rep_first_q <= 1'b0;
            pending_braf_q <= 32'd0;
            ds_in_slot_q <= 1'b0;
            ds_words_left_q <= 3'd0;
            ds_sp_q <= 3'd0;
            for (int i = 0; i < 4; i++) begin
                ds_ppc_q[i] <= 16'd0;
                ds_tgt_q[i] <= 16'd0;
                ds_kind_q[i] <= 3'd0;
                ds_take_q[i] <= 1'b0;
            end
            loop_active_q <= 1'b0;
            loop_kind_q <= LOOP_NONE;
            loop_cnt_q <= 32'd0;
            loop_total_q <= 32'd0;
            loop_pfc_q <= 16'd0;
            loop_a_q <= 16'd0;
            loop_ea_fixed_q <= 1'b0;
            loop_needs_pm_q <= 1'b0;
            replay_active_q <= 1'b0;
            replay_cnt_q <= 32'd0;
            entry_active_q <= 1'b0;
            entry_pend_q <= 1'b0;
            entry_pend2_q <= 1'b0;
            entry_ret_pc_q <= 16'd0;
            entry_idx_q <= 5'd0;
            entry_via_ind_q <= 1'b0;
            entry_is_intr_q <= 1'b0;
            restore_active_q <= 1'b0;
            rst_ph_q <= 4'd0;
            restore_is_rete_q <= 1'b0;
            sh_acc_q <= 32'd0;
            sh_accb_q <= 32'd0;
            sh_preg_q <= 32'd0;
            sh_treg0_q <= 16'd0;
            sh_treg1_q <= 16'd0;
            sh_treg2_q <= 16'd0;
            sh_arcr_q <= 16'd0;
            sh_indx_q <= 16'd0;
            sh_arp_q <= 3'd0;
            sh_arb_q <= 3'd0;
            sh_dp_q <= 9'd0;
            sh_ov_q <= 1'b0;
            sh_ovm_q <= 1'b0;
            sh_intm_q <= 1'b0;
            sh_xf_q <= 1'b0;
            sh_cnf_q <= 1'b0;
            sh_tc_q <= 1'b0;
            sh_sxm_q <= 1'b0;
            sh_c_q <= 1'b0;
            sh_hm_q <= 1'b0;
            sh_pm_q <= 2'd0;
            sh_iptr_q <= 5'd0;
            sh_avis_q <= 1'b0;
            sh_ovly_q <= 1'b0;
            sh_ram_q <= 1'b0;
            sh_mpmc_q <= 1'b0;
            sh_ndx_q <= 1'b0;
            sh_trm_q <= 1'b0;
            sh_braf_q <= 1'b0;
            cnt_branch_q <= 64'd0;
            cnt_2word_q <= 64'd0;
            cnt_pmem_op_q <= 64'd0;
            cnt_rptb_setup_q <= 64'd0;
            cnt_h1_q <= 64'd0;
            cnt_h1a_q <= 64'd0;
            cnt_h1b_q <= 64'd0;
            cnt_h2_q <= 64'd0;
            cnt_h3_q <= 64'd0;
            cnt_int_entry_q <= 64'd0;
            cnt_h10_q <= 64'd0;
            cnt_rpt_replay_q <= 64'd0;
            cnt_mac_replay_q <= 64'd0;
            cnt_xc_q <= 64'd0;
            cnt_io_wait_q <= 64'd0;
        end else begin
            /*
            ---- fetch pointer (flush > rewind > advance) ----
            */
            if (entry_retire_w) begin
                fetch_pc_q <= entry_vec_w;
                fetch_inflight_q <= 1'b0;
            end else if (flush_fdr_w) begin
                fetch_pc_q <= retire_next_pc_w;
                fetch_inflight_q <= 1'b0;
            end else if (fetch_ack_i && !fd_load_o) begin
                fetch_pc_q <= fetch_addr_q;
                fetch_inflight_q <= 1'b0;
            end else if (fetch_need_w) begin
                fetch_pc_q <= fetch_addr_w + 16'd1;
                fetch_addr_q <= fetch_addr_w;
                fetch_inflight_q <= 1'b1;
                fetch_is_word2_q <= fetch_is_word2_w;
                fetch_is_pma_q <= fetch_is_pma_w;
            end
            if (fetch_ack_i && !fetch_need_w)
                fetch_inflight_q <= 1'b0;
            /*
            ---- retire bookkeeping ----
            */
            instr_done_q <= (e_retire_w || entry_retire_w);
            if (e_retire_w) begin
                cycles_q <= cycles_q + {32'd0, retire_cyc_w};
                retire_cnt_q <= retire_cnt_q + 64'd1;
                retire_tgl_q <= ~retire_tgl_q;
                retire_cycles_q <= retire_cyc_w;
                retire_is_intr_q <= 1'b0;
                retire_pc_q <= retire_next_pc_w;
                retire_op_q <= re_i.op;
            end else if (entry_retire_w) begin
                cycles_q <= cycles_q + {60'd0, entry_cyc_w};
                retire_cnt_q <= retire_cnt_q + 64'd1;
                retire_tgl_q <= ~retire_tgl_q;
                retire_cycles_q <= {28'd0, entry_cyc_w};
                retire_is_intr_q <= 1'b1;
                retire_pc_q <= entry_vec_w;
                retire_op_q <= 16'd0;
            end
            /*
            ---- halt on a BADOP in E (a BADOP in a slot restores
                 the outer instruction's ppc first) ----
            */
            if (re_i.valid && re_i.dec.badop && !e_hold_mem_w &&
                !entry_active_q && !restore_active_q) begin
                halted_q <= 1'b1;
                if (ds_in_slot_q)
                    fetch_pc_q <= ds_ppc_q[0];
            end
            /*
            ---- IDLE park / wake ----
            */
            if (e_retire_w && re_i.is_idle) begin
                /* IDLE parks as 1, IDLE2 as 2 (the timer freeze). */
                if ((re_i.op[15:8] == 8'hBE) &&
                    (re_i.op[7:0] == 8'h23))
                    idle_q <= 2'd2;
                else
                    idle_q <= 2'd1;
            end else if ((idle_q != 2'd0) && idle_wake_w) begin
                idle_q <= 2'd0;
            end
            /*
            ---- interrupt inhibit (EINT sets it; the next retire
                 consumes it) ----
            */
            if (e_retire_w && (re_i.op[15:8] == 8'hBE) &&
                (re_i.op[7:0] == 8'h40))
                int_inh_q <= 1'b1;
            else if (e_retire_w || entry_retire_w)
                int_inh_q <= 1'b0;
            /*
            ---- XC window (retire-ordered) ----
            */
            if (e_retire_w) begin
                if (re_i.xc_open && ex_ds_take) begin
                    xc_left_q <= 3'd2;
                    xc_new_q <= 1'b1;
                end else if (xc_new_q) begin
                    xc_new_q <= 1'b0;
                    if (xc_left_after_w == 3'd0)
                        xc_left_q <= 3'd0;
                    else
                        xc_left_q <= xc_left_after_w;
                end else if (xc_left_q != 3'd0) begin
                    if (xc_left_after_w == 3'd0)
                        xc_left_q <= 3'd0;
                    else
                        xc_left_q <= xc_left_after_w;
                end
            end
            /*
            ---- IN/OUT port offset (io_rep) ----
            */
            if (e_retire_w && ((re_i.op[15:8] == 8'hAF) ||
                               (re_i.op[15:8] == 8'h0C))) begin
                if (rep_cont_q)
                    io_rep_q <= io_rep_q + 16'd1;
                else
                    io_rep_q <= 16'd0;
            end
            /*
            ---- RPT window ----
            */
            if (e_retire_w)
                rep_first_q <= re_i.dec.is_rpt;
            if (e_retire_w && re_i.dec.is_rpt) begin
                rpt_start_q <= retire_next_pc_w;
                rpt_end_q <= retire_next_pc_w;
                rep_cont_q <= 1'b1;
            end else if (e_retire_w && rpt_rewind_w) begin
                rep_cont_q <= 1'b1;
            end else if (e_retire_w) begin
                rep_cont_q <= 1'b0;
            end
            /*
            ---- pending BRAF (the block-end decrement not yet
                 committed) ----
            */
            if (flush_fdr_w) begin
                pending_braf_q <= 32'd0;
            end else if (e_retire_w && (braf_rewind_w || braf_done_w)) begin
                if (fetch_redirect_take_w) begin
                    pending_braf_q <= pending_braf_q;
                end else if (pending_braf_q != 32'd0) begin
                    pending_braf_q <= pending_braf_q - 32'd1;
                end
            end else if (fetch_redirect_take_w) begin
                pending_braf_q <= pending_braf_q + 32'd1;
            end
            /*
            ---- delay-slot stack ----
            The push gates on ex_ds_take, not br_taken_q:
            br_taken_q covers only the non-delayed class-1/2
            opcodes (BANZ/BCND/CC/RETC/RETCD) for the seq test,
            and excludes the delayed opcodes (BD/CALLD/BANZD/
            BCNDD/CCD/BACCD/CALAD).  ex_ds_take is the taken
            signal for every delayed opcode (1 for the
            unconditional BD/CALLD, the condition otherwise).
            */
            if (e_retire_w && re_i.is_delayed && ex_ds_take &&
                !slot_done_w) begin
                ds_in_slot_q <= 1'b1;
                ds_words_left_q <= 3'd2;
                ds_sp_q <= ds_sp_q + 3'd1;
                ds_ppc_q[ds_sp_q] <= re_i.pc;
                ds_tgt_q[ds_sp_q] <= slot_new_tgt_w;
                ds_kind_q[ds_sp_q] <= slot_new_kind_w;
                ds_take_q[ds_sp_q] <= 1'b1;
            end else if (e_retire_w && ds_in_slot_q) begin
                if (slot_done_w) begin
                    ds_in_slot_q <= 1'b0;
                    ds_words_left_q <= 3'd0;
                    ds_sp_q <= ds_sp_q - 3'd1;
                end else begin
                    ds_words_left_q <= ds_words_left_q -
                                       {2'd0, words_q[0]};
                end
            end
            /*
            ---- mechanism (a) loop ----
            */
            if (re_i.is_loop_a && !loop_active_q && loop_exec_w) begin
                /* A 0- or 1-iteration loop never activates (its
                   single iteration just executed, or -- 0-iteration
                   while form -- no iteration executes).  A
                   multi-iteration loop activates on its first
                   executing E clock (Bug 3, 2026-11-20): the old
                   gate on e_retire_w could never fire, because a
                   multi-iteration loop's first iteration does not
                   retire (e_would_retire_w is 0 while
                   loop_iters_w > 1), so loop_active_q never set
                   and every iteration reused the first iteration's
                   frozen ea/pfc (BLPD wrote every iteration to
                   the same address with the same pfc+1 data).
                   The registers hold the SECOND iteration's
                   addresses: the first iteration already executed
                   on the bundle's ea/pfc this clock, and the
                   active path runs iterations 2..n from here.
                   The ea is the post-update AR for an indirect
                   mode, the bundle ea for a direct mode (the
                   ARAU returns the live AR there) or a fixed
                   MMR (SMMR/LMMR). */
                if (loop_iters_w <= 32'd1) begin
                    loop_active_q <= 1'b0;
                end else begin
                    loop_active_q <= 1'b1;
                    loop_kind_q <= re_i.loop_kind;
                    loop_cnt_q <= loop_iters_w - 32'd1;
                    loop_total_q <= loop_iters_w;
                    loop_pfc_q <= re_i.pfc + 16'd1;
                    loop_a_q <= (re_i.desc.valid &&
                                 (re_i.op[15:8] != 8'h09) &&
                                 (re_i.op[15:8] != 8'h89)) ?
                                arau_next_i : re_i.ea;
                    loop_ea_fixed_q <= (re_i.op[15:8] == 8'h09) ||
                                       (re_i.op[15:8] == 8'h89);
                    loop_needs_pm_q <= loop_needs_pm_w;
                end
            end else if (loop_active_q && loop_exec_w) begin
                /* The pfc (program pointer) advances every
                   iteration; the ea advances only when it is not
                   fixed (SMMR/LMMR hoist ea() once, KD-9: the
                   source/destination MMR is fixed, only the
                   other side advances) and the mode carries an
                   AR update (a direct mode has no AR to
                   advance; the ARAU returns the live AR). */
                if (!loop_ea_fixed_q && re_i.desc.valid)
                    loop_a_q <= arau_next_i;
                loop_pfc_q <= loop_pfc_q + 16'd1;
                if (loop_cnt_q <= 32'd1)
                    loop_active_q <= 1'b0;
                else
                    loop_cnt_q <= loop_cnt_q - 32'd1;
            end
            /*
            ---- mechanism (b) replay ----
            */
            if (e_retire_w && rpt_rewind_w && !replay_active_q) begin
                replay_active_q <= 1'b1;
                replay_cnt_q <= rptc_i;
            end else if (replay_active_q && e_retire_w) begin
                if (replay_cnt_q <= 32'd1)
                    replay_active_q <= 1'b0;
                else
                    replay_cnt_q <= replay_cnt_q - 32'd1;
            end
            /*
            ---- replay abort on flush ----
            A flush clears the R/E bundle in the top.  If a replay
            was running or starting when any flush fires (taken
            branch, interrupt entry, IDLE -- the PMEM-write flush
            is already gated off while a replay continues, p03),
            the replay state must clear too, or the replay holds
            F/D/R forever with no bundle left to retire (the Bug 2
            stall, via the non-PMEM flush sources).  The repeat
            continues via handle_rpt after the return: the entry
            pushes the rewound PC (rpt_start) and the re-fetched
            instruction rewinds again while rptc > 0.  Placed
            after the replay block so it wins over the rewind-edge
            set above.
            */
            if (flush_fdr_w && (replay_active_q || rpt_rewind_w)) begin
                replay_active_q <= 1'b0;
                replay_cnt_q <= 32'd0;
            end
            /*
            ---- interrupt entry sequencer ----
            Detect at a retire (or idle wake): latch the vector
            select and return PC, set the pending flag.  The
            entry fires one clock later, after the retiring
            instruction's effects have landed.
            */
            if (entry_detect_w && !entry_active_q && !entry_pend_q &&
                !entry_pend2_q) begin
                entry_pend_q <= 1'b1;
                /* Return PC: the next PC after the retiring
                   instruction, or the parked fetch PC on an idle
                   wake (E is empty, retire_next_pc_w is stale). */
                entry_ret_pc_q <= retiring_rete_w ? rete_tgt_q :
                                  (idle_q != 2'd0) ? fetch_pc_q :
                                  retire_next_pc_w;
                entry_idx_q <= entry_idx_w;
                entry_via_ind_q <= entry_via_ind_w;
                entry_ind_q <= entry_ind_new_w;
                entry_is_intr_q <= entry_is_intr_w;
            end
            /* Shift the pending entry one stage per clock: detect
               sets pend, pend shifts to pend2, pend2 fires. */
            if (entry_pend_q) begin
                entry_pend_q <= 1'b0;
                entry_pend2_q <= 1'b1;
            end
            /* Fire: latch the shadow from the live state, which
               is now post-instruction (the instruction retired at
               the detect edge).  This matches C save_ctx, which
               runs after exec1_op.  The two-stage delay leaves
               instr_done low for a clock between the instruction
               retire and this entry retire. */
            if (entry_pend2_q) begin
                entry_pend2_q <= 1'b0;
                entry_active_q <= 1'b1;
                /* Shadow the context from the live state, but only
                   when this entry saves it (entry_saves_ctx_w, KD-12):
                   an INTR that the C model does not save for must
                   leave the shadow untouched. */
                if (entry_saves_ctx_w) begin
                    sh_acc_q <= acc_i;
                    sh_accb_q <= accb_i;
                    sh_preg_q <= preg_i;
                    sh_treg0_q <= treg0_i;
                    sh_treg1_q <= treg1_i;
                    sh_treg2_q <= treg2_i;
                    sh_arcr_q <= arcr_i;
                    sh_indx_q <= indx_i;
                    sh_arp_q <= stat_arp;
                    sh_arb_q <= stat_arb;
                    sh_dp_q <= stat_dp;
                    sh_ov_q <= stat_ov;
                    sh_ovm_q <= stat_ovm;
                    /* C check_int / INTR set intm=1 BEFORE save_ctx, so
                       the shadow INTM is always 1, not the live value
                       (0 after EINT).  XF is not set by check_int, so
                       it is latched live. */
                    sh_intm_q <= 1'b1;
                    sh_xf_q <= stat_xf;
                    sh_cnf_q <= stat_cnf;
                    sh_tc_q <= stat_tc;
                    sh_sxm_q <= stat_sxm;
                    sh_c_q <= stat_c;
                    sh_hm_q <= stat_hm;
                    sh_pm_q <= stat_pm;
                    sh_iptr_q <= stat_iptr;
                    sh_avis_q <= stat_avis;
                    sh_ovly_q <= stat_ovly;
                    sh_ram_q <= stat_ram;
                    sh_mpmc_q <= stat_mpmc;
                    sh_ndx_q <= stat_ndx;
                    sh_trm_q <= stat_trm;
                    sh_braf_q <= stat_braf;
                end
            end else if (entry_active_q && !e_hold_mem_w) begin
                entry_active_q <= 1'b0;
            end
            /*
            ---- restore sequencer ----
            */
            if (restore_active_q) begin
                if (rst_ph_q == 4'd7) begin
                    restore_active_q <= 1'b0;
                    rst_ph_q <= 4'd0;
                end else begin
                    rst_ph_q <= rst_ph_q + 4'd1;
                end
            end else if (e_retire_w && (e_is_reti_w ||
                                           e_is_rete_w)) begin
                restore_active_q <= 1'b1;
                rst_ph_q <= 4'd0;
                restore_is_rete_q <= (re_i.op[7:0] == 8'h3A);
                rete_tgt_q <= retire_next_pc_w;
            end
            /*
            ---- stall counters (actual wall clocks) ----
            */
            if (e_retire_w && br_taken_q && !re_i.is_delayed)
                cnt_branch_q <= cnt_branch_q + 64'd3;
            if (fd_i.valid && d_need_word2_w)
                cnt_2word_q <= cnt_2word_q + 64'd1;
            if (r_req_o && r_use_pmem_w && !loop_active_q &&
                !replay_active_q)
                cnt_pmem_op_q <= cnt_pmem_op_q + 64'd1;
            if (rptb_hold_w)
                cnt_rptb_setup_q <= cnt_rptb_setup_q + 64'd1;
            if (d_stall_h1_w)
                cnt_h1_q <= cnt_h1_q + 64'd1;
            if (d_stall_h1a_w)
                cnt_h1a_q <= cnt_h1a_q + 64'd1;
            if (r_stall_i)
                cnt_h1b_q <= cnt_h1b_q + 64'd1;
            if (d_hold_map_w || r_hold_map_w || e_hold_map_w)
                cnt_h2_q <= cnt_h2_q + 64'd1;
            if (entry_retire_w)
                cnt_int_entry_q <= cnt_int_entry_q + 64'd3;
            if (pm_flush_fire_w)
                cnt_h10_q <= cnt_h10_q + 64'd3;
            if (loop_active_q && loop_exec_w)
                cnt_rpt_replay_q <= cnt_rpt_replay_q + 64'd1;
            if (loop_active_q && loop_exec_w && loop_needs_pm_q)
                cnt_mac_replay_q <= cnt_mac_replay_q + 64'd1;
            if (e_retire_w && re_i.xc_open && !br_taken_q)
                cnt_xc_q <= cnt_xc_q + 64'd1;
            if (e_io_wait_w)
                cnt_io_wait_q <= cnt_io_wait_q + 64'd1;
        end
    end

    /*
    ------------------------------------------------------------------
    Output assigns.
    ------------------------------------------------------------------
    */
    assign instr_done_o = instr_done_q;
    assign cycles_o = cycles_q;
    assign retire_cycles_o = retire_cycles_q;
    assign retire_is_intr_o = retire_is_intr_q;
    assign retire_cnt_o = retire_cnt_q;
    assign retire_tgl_o = retire_tgl_q;
    assign retire_pc_o = retire_pc_q;
    assign retire_op_o = retire_op_q;
    assign halted_o = halted_q;
    assign idle_o = (idle_q != 2'd0);
    assign idle2_o = (idle_q == 2'd2);
    /* model-cycle timer: ticks are queued at retire (charge) and per IDLE clock (not in IDLE2: the timer is stopped there) and drained one per clock */
    logic [15:0] mtick_pend_q;
    logic [15:0] mtick_add_w;
    assign model_tick_o = WALL_TIME ? 1'b1 : (mtick_pend_q != 16'd0);
    always_comb begin
        mtick_add_w = 16'd0;
        if (e_retire_w)
            mtick_add_w = retire_cyc_w[15:0];
        else if (entry_retire_w)
            mtick_add_w = {12'd0, entry_cyc_w};
        else if (idle_q == 2'd1)
            mtick_add_w = 16'd1;
    end
    logic [31:0] mtime_q;
    assign mtime_o = mtime_q;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            mtick_pend_q <= 16'd0;
            mtime_q <= 32'd0;
        end else begin
            mtick_pend_q <= mtick_pend_q + mtick_add_w - {15'd0, model_tick_o};
            mtime_q <= mtime_q + {31'd0, model_tick_o} + {31'd0, (!WALL_TIME && (idle_q == 2'd2))};
        end
    end
    assign obs_sh_acc_o = sh_acc_q;
    assign obs_sh_accb_o = sh_accb_q;
    assign obs_sh_preg_o = sh_preg_q;
    assign obs_sh_treg0_o = sh_treg0_q;
    assign obs_sh_treg1_o = sh_treg1_q;
    assign obs_sh_treg2_o = sh_treg2_q;
    assign obs_sh_arcr_o = sh_arcr_q;
    assign obs_sh_indx_o = sh_indx_q;
    assign obs_sh_st0_o = {sh_arp_q, sh_ov_q, sh_ovm_q, 1'b1,
                           sh_intm_q, sh_dp_q};
    assign obs_sh_st1_o = {sh_arb_q, sh_cnf_q, sh_tc_q, sh_sxm_q,
                           sh_c_q, 1'b1, 1'b1, sh_hm_q, 1'b1,
                           sh_xf_q, 1'b1, 1'b1, sh_pm_q};
    assign obs_sh_pmst_o = {sh_iptr_q, 3'b000, sh_avis_q, 1'b0,
                            sh_ovly_q, sh_ram_q, sh_mpmc_q, sh_ndx_q,
                            sh_trm_q, sh_braf_q};
    assign cnt_stall_branch_o = cnt_branch_q;
    assign cnt_stall_2word_o = cnt_2word_q;
    assign cnt_stall_pmem_op_o = cnt_pmem_op_q;
    assign cnt_stall_rptb_setup_o = cnt_rptb_setup_q;
    assign cnt_stall_h1_o = cnt_h1_q;
    assign cnt_stall_h1a_o = cnt_h1a_q;
    assign cnt_stall_h1b_o = cnt_h1b_q;
    assign cnt_stall_h2_o = cnt_h2_q;
    assign cnt_stall_h3_o = cnt_h3_q;
    assign cnt_stall_int_entry_o = cnt_int_entry_q;
    assign cnt_stall_h10_o = cnt_h10_q;
    assign cnt_stall_rpt_replay_o = cnt_rpt_replay_q;
    assign cnt_stall_mac_replay_o = cnt_mac_replay_q;
    assign cnt_stall_xc_o = cnt_xc_q;
    assign cnt_stall_io_wait_o = cnt_io_wait_q;

endmodule
