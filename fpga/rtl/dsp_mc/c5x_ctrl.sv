/*
c5x_ctrl.sv -- TMS320C5x control FSM (multi-cycle core, Cyclone V).
Function: the control half of the TMS320C5x DSP core port; fetches,
  decodes (via c5x_decode), executes and retires one instruction per
  C-model cycle count, with delay slots, XC window, RPT/RPTB replay,
  interrupt entry/restore and IDLE.
Talks to: c5x_decode (opcode in, micro-op out); c5x_alu (ALU ops and
  flag writeback); c5x_addr (ea, stack, status, repeat state);
  c5x_mem (PM/DM fetch, IO handshake, timer ticks); c5x_ctl_pkg
  (shared bundle, cycle table, cond()).
Does not model: the ALU datapath, the address unit, the memories and
  the timer (owned by agents 1, 2 and 4); the TI 4-phase pipeline --
  this is a multi-cycle core, one instruction per N logical cycles.
Source: research_notes/courier-firmware/c-port/c/src/dsp/c5x_core.c
  (c5x_run, exec1, delay_slot, save_ctx/restore_ctx, check_int,
  interrupt_held, handle_rpt, handle_braf, instr_cycles,
  apply_ar0_mirror, io_read/io_write/io_ws, mmr_bus)
  and c5x_cyctab.h (cycle counts).
*/

/*
Architecture (see c5x_ctl_pkg.sv TIMING CONTRACT): multi-cycle,
one instruction per N C-model cycles.  A machine cycle is a
LOGICAL count (C c->cycles), not a clock.  The FSM spends as many
clocks as an instruction needs (fetch + operand fetch + execute,
loop iterations, IO waits) and advances cycles_o by the C-model
count at instr_done.  The timer is advanced by the same count
through mtick_en/mtick_n (closed form, C advance_timer()).
Single clock, active-low synchronous reset.  Binary-encoded FSM.
No Quartus primitives; inference-friendly RTL only.
*/

/*
Port list: the top level's assumed u_ctrl ports (c5x_core.sv) PLUS
the OPEN-3 deltas documented in c5x_ctl_pkg.sv (acc_i...,
io_ws_i, ndx_commit_o, irq_ack_o, addr_wr_*_o) and the OPEN-1
alu_sh widening ([3:0] -- the top level declares [1:0]) and the
OPEN-8 alu_s16_o (16-bit ADD/SUB form, agent 1's i_s16).
*/

/*
FSM states (c5x_ctl_pkg.sv c5x_fsm_e, binary-encoded):
  RESET, FETCH_ADDR, FETCH_DATA, FETCH2_ADDR, FETCH2_DATA,
  OP_ADDR, OP_DATA, EXEC, LOOP, IO_WAIT, TAIL, INT, DONE, IDLE,
  BADOP, RESTORE.
Per-instruction flow (top-level instruction, not a slot word):
  FETCH_ADDR (pm_addr=pc) -> FETCH_DATA (latch opcode, pc++)
    -> FETCH2_ADDR/DATA (2-word: latch imm, pc++)
    -> OP_ADDR (ea pulse + dm_addr) -> OP_DATA (execute on
       dm_rdata) -> LOOP (loop-op iterations) / IO_WAIT (IN/OUT ack)
    -- or --
    -> EXEC (register-only / write-only execute)
    Loop ops pass through OP_ADDR (for the ea) and OP_DATA
    (loop-engine setup) before LOOP; the OP_ADDR ea_en pulse
    is suppressed for them except SMMR/LMMR, whose ea is
    evaluated once at entry (the LOOP engine re-evaluates ea
    once per iteration in phase EA).
    -> TAIL (mirror, RPT/RPTB, XC hold, interrupt decision)
    -> INT (interrupt entry, 4 cycles) if taken
    -> DONE (pulse instr_done, advance cycles_o, emit mtick)
    -> FETCH_ADDR (or IDLE after an IDLE instruction).
Delay slots run through the same FETCH/EXEC path with in_slot_q
set; after each slot word the FSM checks (pc - slot_start) >= 2
(16-bit unsigned, C delay_slot) and pops the stacked branch
action when done.  A BADOP anywhere (including in a slot) restores
pc to the outer instruction's ppc and halts in BADOP.
*/

/*
Cycle accounting (C instr_cycles + the in-family additions):
  total = base (dec_cycles) adjusted by class-1 (BANZ/BCND/CC/
  RETC: taken 4 / not-taken 2) or class-2 (RETCD 0xFC-0xFE:
  seq -> 2), except when rep_cont (repeat execution: 1, or 2 for
  IN / 3 for OUT); loop ops add (n-1)*k (k=2 SMMR/LMMR, k=1
  others) on top of the base; slot words add their cycm each;
  IN adds io_ws, OUT adds (io_ws>1 ? io_ws-1 : 0) (io_read/
  io_write); a dm_wr to a peripheral MMR (0x20-0x4F) adds 1
  (mmr_bus); a dm access to IO space (MMR 0x50+ or host
  window) adds the io_ws charge -- a dm read adds the full
  io_ws (io_read), a dm write adds io_ws-1 when io_ws > 1
  (io_write) -- charged at OP_DATA / EXEC for single
  instructions and per iteration in LOOP (the read ws is
  latched as dm_rd_ws_q when the read is presented, since
  the address is gone by the charge edge); an interrupt
  entry adds 4.  All of it accumulates in
  cyc_acc_q and is committed to cycles_q at DONE (or at the
  IDLE wake entry).  Single-step: step_i low parks the FSM
  in DONE after retiring an instruction (instr_done stays
  high while parked); step_i high is the normal path.
*/

`default_nettype none

/*
The decoder's class flags (dec_ea_mode, dec_is_branch/call/ret/
rpt/rptb/idle/io/mem_wr/pm_wr), stat_ndx/stat_ram/stat_mpmc and
mmr_hit/mmr_addr are part of the v1 interface contract but the
ctrl dispatches on op_hi/op_lo directly and does not consume
them; UNUSEDSIGNAL is waived for the port list only.
*/
module c5x_ctrl #(
    parameter logic [4:0]  CYC16    = 5'd25,
    parameter logic [15:0] RESET_PC = 16'h8000
) (
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic        clk,
    input  logic        ce_i, /* DSP clock enable: every register advances only when high */
    input  logic        rst_n,
    /*
    Program fetch / program data ports (mem agent).
    */
    output logic [15:0] pm_addr,
    input  logic [15:0] pm_rdata,
    input  logic [15:0] dm_rdata,
    input  logic        dm_ack, /* mem agent: dm_rdata valid this clock */
    input  logic [15:0] pm_d_rdata,
    /*
    Decode interface (the ctrl drives the decoder's inputs).
    */
    output logic [15:0] dec_instr,
    output logic [15:0] dec_instr2,
    input  logic [6:0]  dec_alu_op,
    input  logic [1:0]  dec_words,
    input  logic [7:0]  dec_cycles,
    input  logic [7:0]  dec_ea_mode,
    input  logic        dec_is_branch,
    input  logic        dec_is_call,
    input  logic        dec_is_ret,
    input  logic        dec_is_rpt,
    input  logic        dec_is_rptb,
    input  logic        dec_is_idle,
    input  logic        dec_is_io,
    input  logic        dec_is_mem_wr,
    input  logic        dec_is_pm_wr,
    input  logic        dec_badop,
    /*
    ALU interface (top-level assumed wires; see OPEN-1/OPEN-8).
    */
    output logic [6:0]  alu_op,
    output logic [31:0] alu_a,
    output logic [31:0] alu_b,
    output logic [15:0] alu_d,
    output logic [3:0]  alu_sh,
    output logic        alu_c_in,
    output logic        alu_en,
    output logic        alu_s16,
    input  logic [31:0] alu_y,
    input  logic        alu_c,
    input  logic        alu_ov,
    /*
    Flag sync to the ALU (agent 1's i_flag_c_we/in, i_flag_ov_we/in).
    The ALU owns C/OV; the addr agent mirrors them.  Whenever the
    ctrl writes C/OV through the addr agent (LST #1, SETC/CLRC,
    ROVM/SOVM, shadow restore), it asserts these in the same clock
    so the ALU's c_q/ov_q stay in sync.  The reverse direction
    (ALU op -> addr agent) is the TAIL writeback (st0_ld/st1_ld
    with alu_c/alu_ov, gated on alu_used_q).  See OPEN-9.
    */
    output logic        alu_flag_c_we,
    output logic        alu_flag_c_in,
    output logic        alu_flag_ov_we,
    output logic        alu_flag_ov_in,
    input  logic [31:0] mpy_p,
    /*
    Register load strobes.
    */
    output logic        acc_ld,
    output logic        acc_ld_sel,
    output logic [31:0] acc_data,
    output logic        accb_ld,
    output logic [31:0] accb_data,
    output logic        preg_ld,
    output logic [31:0] preg_data,
    output logic [2:0]  treg_ld,
    output logic [15:0] treg_data,
    output logic        mpy_en,
    output logic [15:0] mpy_a,
    output logic [15:0] mpy_b,
    /*
    Addressing unit interface.
    */
    output logic        ea_en,
    output logic [7:0]  ea_op,
    input  logic [15:0] ea_i,
    output logic [2:0]  ar_wr_sel,
    output logic [15:0] ar_wr_data,
    output logic        ar_wr_en,
    output logic [2:0]  ar_rd_sel,
    input  logic [15:0] ar_rd_i,
    output logic        push_en,
    output logic [15:0] push_data,
    output logic        pop_en,
    input  logic [15:0] pop_data,
    output logic        rptc_ld_en,
    output logic [15:0] rptc_ld_data,
    output logic        rptc_dec_en,
    input  logic [31:0] rptc_i,
    output logic        st0_ld_en,
    output logic [15:0] st0_ld_data,
    output logic        st1_ld_en,
    output logic [15:0] st1_ld_data,
    output logic        pmst_ld_en,
    output logic [15:0] pmst_ld_data,
    output logic        st_bit_en,
    output logic [4:0]  st_bit_sel,
    output logic        st_bit_val,
    output logic        rptb_set_en,
    output logic [15:0] rptb_pasr,
    output logic [15:0] rptb_paer,
    output logic [31:0] rptb_brcr,
    output logic        rptb_clr_en,
    output logic        brcr_ld_en,
    output logic [31:0] brcr_ld_data,
    /*
    Status bits (addr agent).
    */
    input  logic        stat_c,
    input  logic        stat_tc,
    input  logic        stat_ov,
    input  logic        stat_ovm,
    input  logic        stat_intm,
    input  logic        stat_sxm,
    input  logic        stat_hm,
    input  logic        stat_xf,
    input  logic        stat_cnf,
    input  logic [1:0]  stat_pm,
    input  logic [8:0]  stat_dp,
    input  logic [2:0]  stat_arp,
    input  logic [2:0]  stat_arb,
    input  logic        stat_ndx,
    input  logic        stat_braf,
    input  logic        stat_ram,
    input  logic        stat_mpmc,
    input  logic [4:0]  stat_iptr,
    input  logic [2:0]  sp_i,
    /*
    Interrupts (mem agent: IFR/IMR).
    */
    input  logic [15:0] ifr_i,
    input  logic [15:0] imr_i,
    /*
    Data / program-data memory ports (mem agent).
    */
    output logic        dm_req,
    output logic        dm_wr,
    output logic [15:0] dm_addr,
    output logic [15:0] dm_wdata,
    output logic        pm_d_req,
    output logic        pm_d_wr,
    output logic [15:0] pm_d_addr,
    output logic [15:0] pm_d_wdata,
    /*
    Timer advance (mem agent).
    */
    output logic        mtick_en,
    output logic [7:0]  mtick_n,
    output logic        rs_en,       /* the shadow-context restore sequencer is running (acc/accb/preg/treg loads below are restore loads) */
    input  logic        tmr_safe_i,
    /*
    MMR decode (mem agent).
    */
    input  logic        mmr_hit,
    input  logic [5:0]  mmr_addr,
    input  logic        mmr_wr_hit,
    /*
    IO handshake (mem agent -> host).
    */
    output logic        io_req_c,
    output logic        io_wr_c,
    output logic [15:0] io_port_c,
    output logic [15:0] io_wdata_c,
    input  logic [15:0] io_rdata_c,
    input  logic        io_ack_c,
    /*
    Single-step control (harness): when low, the FSM parks in
    DONE after retiring an instruction until step_i goes high.
    Tie high for normal running; the park is cycle-neutral
    (no cycles advance, no timer ticks fire while parked).
    */
    input  logic        step_i,
    /*
    Observation outputs.
    */
    output logic        instr_done,
    output logic [63:0] cycles_o,
    output logic [15:0] pc_o,
    output logic [15:0] op_o,
    output logic        idle_o,
    output logic [15:0] bmar_o,
    output logic [15:0] dbmr_o,
    output logic [15:0] indx_o,
    output logic [15:0] arcr_o,
    /*
    ---- OPEN-3 delta inputs (top level must wire these) ----
    */
    input  logic [31:0] acc_i,
    input  logic [31:0] accb_i,
    input  logic [31:0] preg_i,
    input  logic [15:0] treg0_i,
    input  logic [15:0] treg1_i,
    input  logic [15:0] treg2_i,
    input  logic [15:0] pmst_i,
    input  logic [15:0] ar_arp_i,
    input  logic [15:0] indx_i,
    input  logic [15:0] arcr_i,
    input  logic [15:0] bmar_i,
    input  logic [15:0] dbmr_i,
    input  logic [31:0] brcr_i,
    input  logic [15:0] pasr_i,
    input  logic [15:0] paer_i,
    input  logic        bio_i,
    input  logic [143:0] ivec_ind_i,
    input  logic [3:0]  io_ws_i,
    /*
    ---- OPEN-3 delta outputs ----
    */
    output logic        ndx_commit_o,
    output logic [8:0]  irq_ack_o,
    output logic        addr_wr_en_o,
    output logic [5:0]  addr_wr_sel_o,
    output logic [15:0] addr_wr_data_o
    /* verilator lint_on UNUSEDSIGNAL */
);
    import c5x_ctl_pkg::*;

    /*
    ------------------------------------------------------------------
    Architectural / FSM state.
    ------------------------------------------------------------------
    */
    c5x_fsm_e  state_q;
    logic [15:0] pc_q; /* next instruction address */
    logic [15:0] op_q; /* opcode being executed */
    logic [15:0] imm_q; /* second word (immediate / port / pma) */
    logic [15:0] ppc_q; /* PC of the instruction being executed */
    logic [2:0]  sp0_q; /* SP at instruction start (RETC seq) */
    logic [1:0]  words_q; /* word count of the word just executed */
    logic [15:0] cyc_acc_q; /* cycles accumulated for this instr */
    logic        tick_to_done_q; /* TICK drains to DONE (INT path) not TAIL */
    logic        tick_fast_w;    /* TICK charges the whole cycle count in one clock */
    /* Real-time pacing: the model runs at 40.32 M cycles/s, the DSP clock is 25.8048 MHz (16/25 of it), so one DSP clock is 1.5625 model cycles of real time. wall_q counts real model
       cycles; IDLE advances the model by step_w (1 or 2, 25 per 16 clocks) per clock, or by 8 while the model lags wall_q (after a busy stretch), so audio frames keep real time. */
    logic [3:0]  ph_q;
    logic [3:0]  ph_inc_w;
    assign ph_inc_w = CYC16[3:0] - 4'd0;   /* CYC16 - 16 modulo 16 */
    logic [31:0] wall_q;
    logic [1:0]  step_w;
    logic [31:0] lag_w;
    logic [7:0]  idle_inc_w;
    always_comb begin
        step_w     = 2'd1 + {1'b0, (({1'b0, ph_q} + {1'b0, ph_inc_w}) >= 5'd16)};   /* a carry out of the 4-bit phase adds the extra cycle (25.8048 MHz: 9 of 16 clocks; 40.32 MHz: never) */
        lag_w      = wall_q - cycles_q[31:0];
        idle_inc_w = (!lag_w[31] && lag_w > 32'd8) ? 8'd8 : {6'd0, step_w};
    end
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ph_q   <= 4'd0;
            wall_q <= 32'd0;
        end else if (ce_i) begin
            ph_q   <= ph_q + ph_inc_w;
            wall_q <= wall_q + {30'd0, step_w};
        end
    end
    assign tick_fast_w = tmr_safe_i && (cyc_acc_q != 16'd0) && (cyc_acc_q <= 16'd8);
    logic [63:0] cycles_q; /* C-model cycle counter */
    logic [15:0] rpt_start_q; /* RPT window start (repeated instr PC) */
    logic [15:0] rpt_end_q; /* RPT window end (= rpt_start_q) */
    logic        rep_cont_q; /* this execution is an RPT repeat */
    logic        int_inh_q; /* EINT one-cycle interrupt inhibit */
    logic        xc_new_q; /* XC window: hold the next check */
    logic [1:0]  xc_left_q; /* XC window: words left to protect */
    logic [1:0]  idle_q; /* 0 = running, 1 = IDLE, 2 = IDLE2 */
    logic [15:0] io_rep_q; /* IN/OUT repeat port offset (C io_rep) */
    logic [15:0] wr_addr_q; /* latched dm write address (IN path) */

    /*
    Interrupt-entry state.
    */
    logic [3:0]  int_idx_q; /* IFR bit being serviced (0..8) */
    logic        int_via_ind_q; /* vector came from ivec_ind dm read */
    logic [15:0] int_vec_q; /* vector address (target PC) */
    logic [1:0]  int_ph_q; /* entry sub-phase */

    /*
    Delay-slot stack (depth 4; the C model recurses, real firmware
    nests at most 1 deep, but the stack is cheap and exact).
    kind: 0 = branch (pc=target), 1 = call (pc=target, return
    already pushed), 2 = return (pc=pop after slot), 3 = branch to
    ACC (target latched), 4 = call to ACC (target latched, return
    already pushed).  take_q: the (already evaluated) condition
    for conditional forms; for unconditional forms take_q = 1.
    */
    logic [1:0]  ds_sp_q; /* stack pointer (0..3, next free) */
    logic [15:0] ds_start_q [0:3];
    logic [15:0] ds_ppc_q   [0:3];
    logic [15:0] ds_tgt_q   [0:3];
    logic [2:0]  ds_kind_q  [0:3];
    logic        in_slot_q; /* executing delay-slot words */

    /*
    Loop-op engine state.
    */
    logic [3:0]  loop_kind_q; /* 0 SMMR, 1 LMMR, 2 BLDP, 3 BLPD, */
                                /*
                                4 TBLR, 5 TBLW, 6 BLDD, 7 MAC,
                                8 MADS, 9 IN/OUT handled elsewhere
                                */
    logic [2:0]  loop_ph_q; /* phase within one iteration */
                                /*
                                0 EA, 1 RD, 2 WAIT, 3 PM, 4 WR, 5 NEXT
                                */
    logic [31:0] loop_cnt_q; /* iterations remaining */
    logic [15:0] loop_pfc_q; /* advancing program/data pointer */
    logic [15:0] loop_a_q; /* latched ea (fixed or per-iteration) */
    logic [15:0] loop_d_q; /* latched source read data */
    logic        alu_used_q; /* current instr used the ALU (TAIL C/OV */
                                /*
                                writeback gate, OPEN-9)
                                */
    logic        int_pending_q; /* TAIL selected an interrupt (enter INT) */
    logic        int_idle_q;    /* the interrupt woke the core from IDLE: no TAIL cycle issued the IFR clear, so INT phase 0 does it */
    logic        badop_q; /* current instr is a BADOP (halt) */
    logic [1:0]  idle_next_q; /* IDLE kind to enter after DONE (1/2) */
    logic        dm_wait_q; /* dm_req pulsed, waiting for dm_ack */
    logic [3:0]  dm_rd_ws_q; /* io_ws of the dm read in flight
                                (latched when the read is presented;
                                the read address is not on dm_addr
                                by the time the charge is added) */
    logic        int_is_intr_q; /* INT state is serving an INTR instr */
                                /*
                                (no irq_ack, no +4 entry cycles)
                                */
    logic [3:0]  rst_ph_q; /* RETI/RETE restore phase (0..8) */

    /*
    Shadow context (C save_ctx / restore_ctx).  restore_ctx does
    NOT restore INTM and XF (audit #9) -- they are saved but the
    restore keeps the live values.  sh_dp is dp>>7 (9 bits, as in
    stat_dp).
    */
    logic [31:0] sh_acc_q, sh_accb_q, sh_preg_q;
    logic [15:0] sh_treg0_q, sh_treg1_q, sh_treg2_q;
    logic [15:0] sh_arcr_q, sh_indx_q;
    logic [2:0]  sh_arp_q, sh_arb_q;
    logic [8:0]  sh_dp_q;
    logic        sh_ov_q, sh_ovm_q;
    logic        sh_cnf_q, sh_tc_q, sh_sxm_q, sh_c_q, sh_hm_q;
    logic [1:0]  sh_pm_q;
    logic [4:0]  sh_iptr_q;
    logic        sh_avis_q, sh_ovly_q, sh_ram_q, sh_mpmc_q, sh_ndx_q;
    logic        sh_trm_q, sh_braf_q;

    /*
    ------------------------------------------------------------------
    Decoder input mux: during FETCH_DATA the opcode is pm_rdata
    (just fetched); otherwise it is the latched op_q.  The decoder
    is combinational, so dec_* are valid in the same clock.
    ------------------------------------------------------------------
    */
    assign dec_instr  = (state_q == FSM_FETCH_DATA) ? pm_rdata : op_q;
    assign dec_instr2 = imm_q;
    /*
    (The observation outputs cycles_o/pc_o/op_o/idle_o/bmar_o/
    dbmr_o/indx_o/arcr_o are driven in the main always_comb below,
    not here, so there is a single driver for each.)
    */

    /*
    ------------------------------------------------------------------
    Helpers (combinational).
    ------------------------------------------------------------------
    Current opcode's high / low byte.
    */
    logic [7:0] op_hi;
    logic [7:0] op_lo;
    assign op_hi = op_q[15:8];
    assign op_lo = op_q[7:0];

    /*
    Branch condition for the current opcode (C cond()).
    */
    logic cond_q;
    assign cond_q = c5x_cond(op_q, acc_i, stat_tc, stat_ov, stat_c, bio_i);

    /*
    Branch-taken test for the class-1/2 conditional branches
    (BANZ/BCND/CC/RETC/RETCD): ex_ds_take is the taken signal for
    exactly those opcodes (the branch condition for BCND/CC/RETC/
    RETCD, the AR test for BANZ); it defaults to 1 for every other
    opcode, so the opcode-range gate matters.  It is combinational
    from op_q, so it is valid at the charge edge in EXEC.
    */
    logic br_taken_q;
    assign br_taken_q = ((op_hi == 8'h7B) ||
                         (op_hi >= 8'hE0 && op_hi <= 8'hE3) ||
                         (op_hi >= 8'hE8 && op_hi <= 8'hEB) ||
                         (op_hi >= 8'hEC && op_hi <= 8'hEF) ||
                         (op_hi >= 8'hFC && op_hi <= 8'hFE)) &&
                        ex_ds_take;

    /*
    seq test for instr_cycles (C: pc == ppc + words; RETC uses sp).
    The pc/sp test alone is not enough: at the charge edge (EXEC)
    pc_q is still the fall-through pc (the branch target is applied
    at that same edge), so a taken branch would read as sequential
    and charge 2 instead of 4 (CTRL-BCND: a taken BCND charged 2,
    the DSP smoke gate failed at checkpoint 2 on pc only).  A
    class-1/2 branch is sequential only when it is NOT taken.
    */
    logic seq_q;
    assign seq_q = (op_hi >= 8'hEC && op_hi <= 8'hEF) ?
                   ((sp_i == sp0_q) && !br_taken_q) :
                   ((pc_q == (ppc_q + {14'b0, words_q})) && !br_taken_q);

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
                default: base_cyc_q = 8'd1;
            endcase
        end
    end

    /*
    Is the current opcode a loop op (FSM_LOOP engine)?
    */
    logic is_loop_op;
    always_comb begin
        case (op_hi)
            8'h09, 8'h57, 8'h89, 8'hA2, 8'hA3, 8'hA4, 8'hA5,
            8'hA6, 8'hA7, 8'hA8, 8'hA9, 8'hAA, 8'hAB, 8'hAC, 8'hAD:
                is_loop_op = 1'b1;
            default: is_loop_op = 1'b0;
        endcase
    end

    /*
    Loop-op kind numbers (LOOP engine dispatch). Source: C exec loop
    families in c5x_core.c (exec_09 SMMR, exec_89 LMMR, exec_57 BLDP,
    exec_a4/a5 BLPD, exec_a6 TBLR, exec_a7 TBLW, exec_a8/a9/ac/ad BLDD,
    exec_a2 MAC, exec_a3 MACD, exec_aa MADS, exec_ab MADD).
    */
    localparam logic [3:0] LOOP_SMMR = 4'd0;
    localparam logic [3:0] LOOP_LMMR = 4'd1;
    localparam logic [3:0] LOOP_BLDP = 4'd2;
    localparam logic [3:0] LOOP_BLPD = 4'd3;
    localparam logic [3:0] LOOP_TBLR = 4'd4;
    localparam logic [3:0] LOOP_TBLW = 4'd5;
    localparam logic [3:0] LOOP_BLDD = 4'd6;
    localparam logic [3:0] LOOP_MAC  = 4'd7;
    localparam logic [3:0] LOOP_MADS = 4'd8;

    /* rptc == -1 means "no repeat" (C: rptc is int32_t; the loop ops
       and handle_rpt test rptc == -1 / rptc > -1, c5x_core.c). */
    localparam logic [31:0] RPTC_MINUS1 = 32'hFFFF_FFFF;

    /*
    Loop-op kind select. Case table, not a ternary chain: the old
    chain's range test (op_hi >= A8 && op_hi <= AD) also caught
    MADS (AA) and MADD (AB) and mapped them to BLDD (kind 6), so
    they would have executed as block moves. This table maps each
    BLDD form explicitly and MADS/MADD to kind 8 (KD-24).
    The default is unreachable for loop ops (is_loop_op gates the
    load, and every loop-op high byte is listed); it exists so the
    combinational block assigns on every path.
    */
    logic [3:0] loop_kind_next;
    always_comb begin
        case (op_hi)
            8'h09:                     loop_kind_next = LOOP_SMMR;
            8'h89:                     loop_kind_next = LOOP_LMMR;
            8'h57:                     loop_kind_next = LOOP_BLDP;
            8'hA4, 8'hA5:               loop_kind_next = LOOP_BLPD;
            8'hA6:                     loop_kind_next = LOOP_TBLR;
            8'hA7:                     loop_kind_next = LOOP_TBLW;
            8'hA8, 8'hA9, 8'hAC, 8'hAD: loop_kind_next = LOOP_BLDD;
            8'hA2, 8'hA3:               loop_kind_next = LOOP_MAC;
            8'hAA, 8'hAB:               loop_kind_next = LOOP_MADS;
            default:                    loop_kind_next = LOOP_MADS;
        endcase
    end

    /*
    Loop-op program-flow-control (pfc) select. C: MAC/MACD pfc =
    imm; MADS/MADD and BLDD-bmar pfc = bmar; TBLR/TBLW pfc = ACC;
    SMMR/LMMR/BLDP/BLPD-#pma/BLDD-#lk pfc = imm.
    */
    logic [15:0] loop_pfc_next;
    always_comb begin
        case (op_hi)
            8'h09, 8'h89, 8'hA5, 8'hA8, 8'hA9, 8'hA2, 8'hA3:
                loop_pfc_next = imm_q;
            8'hA6, 8'hA7:
                loop_pfc_next = acc_i[15:0];
            default:
                loop_pfc_next = bmar_i;
        endcase
    end

    /*
    The opcode the routing decisions use: pm_rdata while it is
    being fetched (FETCH_DATA), otherwise the latched op_q.  The
    needs_* signals below are computed from this, so FETCH_DATA
    routes on the NEW opcode, not the stale op_q.
    */
    logic [7:0]  cur_hi_w;
    assign cur_hi_w = (state_q == FSM_FETCH_DATA) ? pm_rdata[15:8] : op_q[15:8];

    /*
    Does the current opcode need the OP_ADDR state (to obtain an
    ea for a dm read or a dm write address)?  Loop ops use FSM_LOOP
    (their own ea sequencing per iteration), but they still pass
    through OP_ADDR: OP_DATA is where the loop engine is set up,
    and OP_ADDR is the only path to OP_DATA.  For SMMR/LMMR the
    OP_ADDR ea pulse IS the loop's ea (evaluated once, KD-9); for
    the other loop ops the pulse is suppressed in the OP_ADDR
    output block and the LOOP engine pulses ea_en once per
    iteration (phase EA).  Side-effect-only ea() (MAR, NORM
    shifting path, B/CALL/BANZ family) is pulsed directly in
    FETCH_DATA / FETCH2_DATA and needs no OP_ADDR.
    */
    logic needs_op_addr;
    always_comb begin
        case (cur_hi_w)
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
            8'h80, 8'h81, 8'h82, 8'h83, 8'h84, 8'h85, 8'h86, 8'h87,
            8'h88, 8'h89, 8'h8A, 8'h8C, 8'h8D, 8'h8E, 8'h8F,
            8'h90, 8'h91, 8'h92, 8'h93, 8'h94, 8'h95, 8'h96, 8'h97,
            8'h98, 8'h99, 8'h9A, 8'h9B, 8'h9C, 8'h9D, 8'h9E, 8'h9F,
            8'hA2, 8'hA3, 8'hA4, 8'hA5, 8'hA6, 8'hA7, 8'hA8, 8'hA9,
            8'hAA, 8'hAB, 8'hAC, 8'hAD, 8'hAE, 8'hAF:
                needs_op_addr = 1'b1;
            default: needs_op_addr = 1'b0;
        endcase
    end

    /*
    Does the current opcode consume the dm read data in OP_DATA?
    (Write-only instructions go OP_ADDR -> EXEC and use the
     latched ea_q as their write address, with NO dm read -- a
     read there would be a spurious host-window / MMR read.)
    Loop ops are excluded: their source reads happen per
    iteration in FSM_LOOP (RD phase), and an OP_ADDR read at
    ea would be a spurious extra read -- for BLDD #lk,dma the
    ea is the DESTINATION, and for an IO-space ea it would log
    an IO event the C model never makes.
    */
    logic needs_dm_rd;
    always_comb begin
        case (cur_hi_w)
            8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07,
            8'h08, 8'h0A, 8'h0B, 8'h0C, 8'h0D, 8'h0E, 8'h0F,
            8'h10, 8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17,
            8'h18, 8'h19, 8'h1A, 8'h1B, 8'h1C, 8'h1D, 8'h1E, 8'h1F,
            8'h20, 8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26, 8'h27,
            8'h28, 8'h29, 8'h2A, 8'h2B, 8'h2C, 8'h2D, 8'h2E, 8'h2F,
            8'h30, 8'h31, 8'h32, 8'h33, 8'h34, 8'h35, 8'h36, 8'h37,
            8'h38, 8'h39, 8'h3A, 8'h3B, 8'h3C, 8'h3D, 8'h3E, 8'h3F,
            8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h46, 8'h47,
            8'h48, 8'h49, 8'h4A, 8'h4B, 8'h4C, 8'h4D, 8'h4E, 8'h4F,
            8'h50, 8'h51, 8'h52, 8'h53, 8'h54, 8'h55,
            8'h58, 8'h59, 8'h5A, 8'h5B, 8'h5C, 8'h5D, 8'h5E, 8'h5F,
            8'h60, 8'h61, 8'h62, 8'h63, 8'h64, 8'h65, 8'h66, 8'h67,
            8'h68, 8'h69, 8'h6A, 8'h6B, 8'h6C, 8'h6D, 8'h6E, 8'h6F,
            8'h70, 8'h71, 8'h72, 8'h73, 8'h74, 8'h75, 8'h76, 8'h77:
                needs_dm_rd = 1'b1;
            default: needs_dm_rd = 1'b0;
        endcase
    end

    /*
    Latched effective address (from OP_ADDR, for write-only ops
    and read-modify-write ops that need it in OP_DATA / EXEC).
    */
    logic [15:0] ea_q;

    /*
    ------------------------------------------------------------------
    Execute datapath (combinational).  Computes the datapath
    controls for the instruction in op_q, with the data word d_w:
      d_w = dm_rdata in FSM_OP_DATA (dm-read instructions),
      d_w = imm_q   in FSM_EXEC     (immediate / write-only forms).
    The main output block applies these in OP_DATA / EXEC / LOOP.
    The C-model operation for each family is noted; the ALU op
    (ex_alu_op) selects the micro-op, ex_alu_* are its operands,
    and the ex_*_ld strobes are the register writes.  Memory
    writes are ex_dm_wr / ex_pm_wr (with address/data).  The
    next-PC action is ex_pc_act (see below) and ex_pc_tgt.
    ------------------------------------------------------------------
    */
    logic [15:0] d_w;
    assign d_w = (state_q == FSM_OP_DATA) ? dm_rdata : imm_q;

    /*
    Next-PC actions (applied by the sequential block at the EXEC
    edge, or by the delay-slot stack for delayed forms).
    */
    localparam logic [2:0] PC_SEQ   = 3'd0; /* pc continues (pc_q) */
    localparam logic [2:0] PC_JMP   = 3'd1; /* pc = ex_pc_tgt */
    localparam logic [2:0] PC_DSLOT = 3'd2; /* push delay-slot ctx */
    localparam logic [2:0] PC_RET   = 3'd3; /* pc = pop_data (after slot) */
    localparam logic [2:0] PC_IDLE  = 3'd4; /* enter IDLE/IDLE2 */

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
                ex_alu_en  = 1'b1;   /* the ALU must execute for its register load (without it the op did nothing) */
                ex_mpy_en  = 1'b1;
                ex_mpy_a   = treg0_i;
                ex_mpy_b   = d_w;
                ex_preg_ld = 1'b1;
                ex_preg_data = mpy_p;
            end
            8'h55: begin /* MPYU: PREG = TREG0*d (unsigned) */
                ex_alu_op  = ALU_MPYU;
                ex_alu_en  = 1'b1;   /* the ALU must execute for its register load (without it the op did nothing) */
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
                ex_alu_en  = 1'b1;   /* the ALU must execute for its register load (without it the op did nothing) */
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
                ex_alu_en  = 1'b1;   /* the ALU must execute for its register load (without it the op did nothing) */
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
                ex_dm_wdata = {stat_arp, stat_ov, stat_ovm, 1'b1,
                               stat_intm, stat_dp};
            end
            8'h8F: begin /* SST #1: dm[ea] = ST1 */
                ex_dm_wr    = 1'b1;
                ex_dm_addr  = ea_q;
                ex_dm_wdata = {stat_arb, stat_cnf, stat_tc, stat_sxm,
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
                        8'h12, 8'h13, 8'h18, 8'h19, 8'h1A, 8'h1B,
                        8'h1C, 8'h1F:
                            /*
                            ABS/CMPL/NEG/PAC/APAC/SPAC/ROL/ROR/
                            ROLC/RORC/ADDB/ADDC/ANDB/ORB/SUBB/
                            SBBB/XORB/MAX/MIN/LACB: ACC result.
                            */
                            ex_acc_ld = 1'b1;
                        8'h14, 8'h15, 8'h16, 8'h17: begin
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
                        8'hC4, 8'hC5: begin end /* RPT/RPTZ #lk */
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
                ex_alu_en  = 1'b1;   /* the ALU must execute for its register load (without it the op did nothing) */
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
            8'hF4, 8'hF5, 8'hF6, 8'hF7: begin end /* XC (main block) */
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

    /*
    ------------------------------------------------------------------
    apply_exec: drive the datapath outputs from the execute signals.
    Called in FSM_OP_DATA and FSM_EXEC (and by the loop engine).
    The ALU result is alu_y (agent 1 computes it internally from
    alu_op/alu_a/alu_b/alu_d/alu_sh/alu_c_in/alu_s16); acc_data /
    accb_data / preg_data / treg_data are the top-level assumed
    load-data wires -- agent 1's ALU ignores them for ALU-computed
    results (it commits its internal next values on i_ld_*), but
    they carry the semantically correct value for a separate
    register file.  Memory writes and IO requests are presented
    here; the FSM waits for the ack (dm_ack / io_ack_c) elsewhere.
    ------------------------------------------------------------------
    */

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
            4'd0: int_ind_addr_w = ivec_ind_i[15:0];
            4'd1: int_ind_addr_w = ivec_ind_i[31:16];
            4'd2: int_ind_addr_w = ivec_ind_i[47:32];
            4'd3: int_ind_addr_w = ivec_ind_i[63:48];
            4'd4: int_ind_addr_w = ivec_ind_i[79:64];
            4'd5: int_ind_addr_w = ivec_ind_i[95:80];
            4'd6: int_ind_addr_w = ivec_ind_i[111:96];
            4'd7: int_ind_addr_w = ivec_ind_i[127:112];
            4'd8: int_ind_addr_w = ivec_ind_i[143:128];
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
    Main combinational output driver.
    ------------------------------------------------------------------
    */
    always_comb begin
        /*
        ---- defaults (all strobes idle, all data zero) ----
        */
        pm_addr        = pc_q;
        alu_op         = ALU_NOP;
        alu_a          = acc_i;
        alu_b          = 32'd0;
        alu_d          = 16'd0;
        alu_sh         = 4'd0;
        alu_c_in       = stat_c;
        alu_en         = 1'b0;
        alu_s16        = 1'b0;
        alu_flag_c_we  = 1'b0;
        alu_flag_c_in = 1'b0;
        alu_flag_ov_we = 1'b0;
        alu_flag_ov_in = 1'b0;
        acc_ld         = 1'b0;
        acc_ld_sel     = 1'b0;
        acc_data       = alu_y;
        accb_ld        = 1'b0;
        accb_data      = alu_y;
        preg_ld        = 1'b0;
        preg_data      = 32'd0;
        treg_ld        = 3'b000;
        treg_data      = 16'd0;
        mpy_en         = 1'b0;
        mpy_a          = 16'd0;
        mpy_b          = 16'd0;
        ea_en          = 1'b0;
        ea_op          = op_lo;
        ar_wr_sel      = op_hi[2:0];
        ar_wr_data     = d_w;
        ar_wr_en       = 1'b0;
        ar_rd_sel      = op_hi[2:0];
        push_en        = 1'b0;
        push_data      = 16'd0;
        pop_en         = 1'b0;
        rptc_ld_en     = 1'b0;
        rptc_ld_data   = 16'd0;
        rptc_dec_en    = 1'b0;
        st0_ld_en      = 1'b0;
        st0_ld_data    = 16'd0;
        st1_ld_en      = 1'b0;
        st1_ld_data    = 16'd0;
        pmst_ld_en     = 1'b0;
        pmst_ld_data   = 16'd0;
        st_bit_en      = 1'b0;
        st_bit_sel     = 5'd0;
        st_bit_val     = 1'b0;
        rptb_set_en    = 1'b0;
        rptb_pasr      = pc_q;
        rptb_paer      = imm_q;
        rptb_brcr      = 32'd0;
        rptb_clr_en    = 1'b0;
        brcr_ld_en     = 1'b0;
        brcr_ld_data   = 32'd0;
        dm_req         = 1'b0;
        dm_wr          = 1'b0;
        dm_addr        = ea_q;
        dm_wdata       = 16'd0;
        pm_d_req       = 1'b0;
        pm_d_wr        = 1'b0;
        pm_d_addr      = 16'd0;
        pm_d_wdata     = 16'd0;
        mtick_en       = 1'b0;
        mtick_n        = 8'd0;
        rs_en          = 1'b0;
        io_req_c       = 1'b0;
        io_wr_c        = 1'b0;
        io_port_c      = 16'd0;
        io_wdata_c     = 16'd0;
        instr_done     = 1'b0;
        ndx_commit_o   = 1'b0;
        irq_ack_o      = 9'd0;
        addr_wr_en_o   = 1'b0;
        addr_wr_sel_o  = 6'd0;
        addr_wr_data_o = 16'd0;
        /*
        Observation outputs (continuous).
        */
        cycles_o = cycles_q;
        pc_o     = pc_q;
        op_o     = op_q;
        idle_o   = (state_q == FSM_IDLE);
        bmar_o   = bmar_i;
        dbmr_o   = dbmr_i;
        indx_o   = indx_i;
        arcr_o   = arcr_i;

        case (state_q)
            FSM_RESET: begin
                /*
                Nothing to drive; the sequential block resets state.
                */
            end
            FSM_FETCH_ADDR: begin
                pm_addr = pc_q;
            end
            FSM_FETCH_DATA: begin
                /*
                Side-effect-only ea() for MAR (bit 7 set) and for
                NORM on the shifting path (ACC != 0 and bits
                31/30 agree).  The opcode is pm_rdata here.
                */
                if (pm_rdata[15:8] == 8'h8B && pm_rdata[7]) begin
                    ea_en = 1'b1;
                    ea_op = pm_rdata[7:0];
                end else if (pm_rdata[15:8] == 8'hA0 &&
                             acc_i != 32'd0 &&
                             acc_i[31] == acc_i[30]) begin
                    ea_en = 1'b1;
                    ea_op = pm_rdata[7:0];
                end
            end
            FSM_FETCH2_ADDR: begin
                pm_addr = pc_q;
            end
            FSM_FETCH2_DATA: begin
                /*
                Side-effect-only ea() for the B/CALL/BANZ family
                (the target comes from the immediate word).
                */
                if (op_hi == 8'h79 || op_hi == 8'h7A ||
                    op_hi == 8'h7B || op_hi == 8'h7D ||
                    op_hi == 8'h7E || op_hi == 8'h7F) begin
                    ea_en = 1'b1;
                    ea_op = op_lo;
                end
            end
            FSM_OP_ADDR: begin
                /*
                Pulse ea_en and, only for instructions that consume
                the dm read data (needs_dm_rd), present the dm read.
                Write-only instructions (SAR/SAMM/SPL/SPH/SST/
                SACL/SACH/SPLK) get the ea only -- no dm read, so
                no spurious host-window / MMR read side effect.
                Loop ops get no dm read either (their reads happen
                per iteration in FSM_LOOP).  The ea_en pulse is
                also suppressed for loop ops other than SMMR/LMMR:
                the LOOP engine pulses ea_en once per iteration
                (phase EA) and latches the per-iteration ea, so a
                pulse here would evaluate ea a second time for
                the first iteration and advance an indirect AR
                twice.  o_ea is combinational, so ea_q still
                latches the first iteration's address.  SMMR/LMMR
                keep the pulse: their ea is evaluated once at
                entry (C ea() hoisted out of the loop, KD-9) and
                the LOOP engine never re-evaluates it.
                */
                if (!dm_wait_q) begin
                    if (!is_loop_op || (op_hi == 8'h09) ||
                        (op_hi == 8'h89))
                        ea_en = 1'b1;
                    ea_op  = op_lo;
                    if (needs_dm_rd) begin
                        dm_req = 1'b1;
                        dm_wr  = 1'b0;
                        dm_addr = ea_mask_p0 ? {9'b0, ea_i[6:0]} : ea_i;
                    end
                end else begin
                    dm_addr = ea_mask_p0 ? {9'b0, ea_i[6:0]} : ea_i;
                end
            end
            FSM_OP_DATA: begin
                if (is_loop_op) begin
                    /*
                    Loop op: the LOOP state does the work; nothing
                    to drive here (the sequential block moves on).
                    */
                end else begin
                    alu_op     = ex_alu_op;
                    alu_a      = ex_alu_a;
                    alu_b      = ex_alu_b;
                    alu_d      = ex_alu_d;
                    alu_sh     = ex_alu_sh;
                    alu_c_in   = ex_alu_c_in;
                    alu_en     = ex_alu_en;
                    alu_s16    = ex_alu_s16;
                    acc_ld     = ex_acc_ld;
                    acc_ld_sel = ex_acc_ld_sel;
                    acc_data   = ex_acc_ld_sel ? ex_acc_data : alu_y;
                    accb_ld    = ex_accb_ld;
                    accb_data  = ex_acc_ld_sel ? ex_accb_data : alu_y;
                    preg_ld    = ex_preg_ld;
                    preg_data  = ex_preg_data;
                    treg_ld    = ex_treg_ld;
                    treg_data  = ex_treg_data;
                    mpy_en     = ex_mpy_en;
                    mpy_a      = ex_mpy_a;
                    mpy_b      = ex_mpy_b;
                    push_en    = ex_push_en;
                    push_data  = ex_push_data;
                    pop_en     = ex_pop_en;
                    if (ex_dm_wr) begin
                        dm_req   = 1'b1;
                        dm_wr    = 1'b1;
                        dm_addr  = ex_dm_addr;
                        dm_wdata = ex_dm_wdata;
                    end
                    if (ex_pm_wr) begin
                        pm_d_req   = 1'b1;
                        pm_d_wr    = 1'b1;
                        pm_d_addr  = ex_pm_addr;
                        pm_d_wdata = ex_pm_wdata;
                    end
                    if (ex_io_req) begin
                        io_req_c   = 1'b1;
                        io_wr_c    = ex_io_wr;
                        io_port_c  = ex_io_port;
                        io_wdata_c = ex_io_wdata;
                    end

                    /*
                    Per-instruction specials (register / flag /
                    repeat loads that the execute datapath does not
                    cover).
                    */
                    case (op_hi)
                        8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05,
                        8'h06, 8'h07: begin /* LAR dma */
                            ar_wr_en   = 1'b1;
                            ar_wr_sel  = op_hi[2:0];
                            ar_wr_data = d_w;
                        end
                        8'h0B: begin /* RPT dma */
                            rptc_ld_en   = 1'b1;
                            rptc_ld_data = d_w;
                        end
                        8'h0D: begin /* LDP dma: DP = d[8:0] */
                            st0_ld_en   = 1'b1;
                            st0_ld_data = {stat_arp, stat_ov, stat_ovm,
                                           1'b1, stat_intm, d_w[8:0]};
                        end
                        8'h0E: begin /* LST #0 (ARP/OV/OVM/DP; INTM kept) */
                            addr_wr_en_o   = 1'b1;
                            addr_wr_sel_o  = WR_ST0L;
                            addr_wr_data_o = d_w;
                            alu_flag_ov_we = 1'b1; /* sync the ALU's OV */
                            alu_flag_ov_in = d_w[12];
                        end
                        8'h0F: begin /* LST #1 (ARB/CNF/TC/SXM/C/HM/XF/PM) */
                            addr_wr_en_o   = 1'b1;
                            addr_wr_sel_o  = WR_ST1L;
                            addr_wr_data_o = d_w;
                            alu_flag_c_we  = 1'b1; /* sync the ALU's C */
                            alu_flag_c_in  = d_w[9];
                        end
                        8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45,
                        8'h46, 8'h47, 8'h48, 8'h49, 8'h4A, 8'h4B,
                        8'h4C, 8'h4D, 8'h4E, 8'h4F: begin
                            /*
                            BIT: TC = bit (15-shift) of d
                            */
                            st_bit_en  = 1'b1;
                            st_bit_sel = FLG_TC;
                            st_bit_val = d_w[4'd15 - op_hi[3:0]];
                        end
                        8'h58, 8'h59, 8'h5A, 8'h5B,
                        8'h5C, 8'h5D, 8'h5E, 8'h5F: begin
                            /*
                            XPL/OPL/APL/CPL: TC = (result == 0)
                            */
                            st_bit_en  = 1'b1;
                            st_bit_sel = FLG_TC;
                            st_bit_val = xpl_tc_w;
                        end
                        8'h6F: begin /* BITT: TC = bit (~TREG2) of d */
                            st_bit_en  = 1'b1;
                            st_bit_sel = FLG_TC;
                            st_bit_val = d_w[~treg2_i[3:0]];
                        end
                        default: begin end
                    endcase
                end
            end
            FSM_EXEC: begin
                alu_op     = ex_alu_op;
                alu_a      = ex_alu_a;
                alu_b      = ex_alu_b;
                alu_d      = ex_alu_d;
                alu_sh     = ex_alu_sh;
                alu_c_in   = ex_alu_c_in;
                alu_en     = ex_alu_en;
                alu_s16    = ex_alu_s16;
                acc_ld     = ex_acc_ld;
                acc_ld_sel = ex_acc_ld_sel;
                acc_data   = ex_acc_ld_sel ? ex_acc_data : alu_y;
                accb_ld    = ex_accb_ld;
                accb_data  = ex_acc_ld_sel ? ex_accb_data : alu_y;
                preg_ld    = ex_preg_ld;
                preg_data  = ex_preg_data;
                treg_ld    = ex_treg_ld;
                treg_data  = ex_treg_data;
                mpy_en     = ex_mpy_en;
                mpy_a      = ex_mpy_a;
                mpy_b      = ex_mpy_b;
                push_en    = ex_push_en;
                push_data  = ex_push_data;
                pop_en     = ex_pop_en;
                if (ex_dm_wr) begin
                    dm_req   = 1'b1;
                    dm_wr    = 1'b1;
                    dm_addr  = ex_dm_addr;
                    dm_wdata = ex_dm_wdata;
                end
                if (ex_pm_wr) begin
                    pm_d_req   = 1'b1;
                    pm_d_wr    = 1'b1;
                    pm_d_addr  = ex_pm_addr;
                    pm_d_wdata = ex_pm_wdata;
                end
                if (ex_io_req) begin
                    io_req_c   = 1'b1;
                    io_wr_c    = ex_io_wr;
                    io_port_c  = ex_io_port;
                    io_wdata_c = ex_io_wdata;
                end

                case (op_hi)
                    8'h78: begin /* ADRK #k8: AR[ARP] += k8 (C step_aux_reg; the circular-buffer wrap is not modelled here) */
                        ar_wr_en   = 1'b1;
                        ar_wr_sel  = stat_arp;
                        ar_wr_data = ar_arp_i + {8'b0, op_lo};
                    end
                    8'h7C: begin /* SBRK #k8: AR[ARP] -= k8 */
                        ar_wr_en   = 1'b1;
                        ar_wr_sel  = stat_arp;
                        ar_wr_data = ar_arp_i - {8'b0, op_lo};
                    end
                    8'hB0, 8'hB1, 8'hB2, 8'hB3, 8'hB4, 8'hB5, 8'hB6,
                    8'hB7: begin /* LAR #k8 (k8 = op_lo) */
                        ar_wr_en   = 1'b1;
                        ar_wr_sel  = op_hi[2:0];
                        ar_wr_data = {8'b0, op_lo};
                    end
                    8'hBB: begin /* RPT #k8 */
                        rptc_ld_en   = 1'b1;
                        rptc_ld_data = {8'b0, op_lo};
                    end
                    8'hBC, 8'hBD: begin /* LDP #k9 (k9 = op[8:0]) */
                        st0_ld_en   = 1'b1;
                        st0_ld_data = {stat_arp, stat_ov, stat_ovm,
                                       1'b1, stat_intm, op_q[8:0]};
                    end
                    8'hBE: begin
                        if (op_lo < 8'h20) begin
                            /*
                            Accumulator ops: the ALU does the work;
                            TC is the ALU's o_tc_next (wired by the
                            top level into stat_tc via st_bit).
                            Nothing extra here.
                            */
                        end else if (op_lo >= 8'h40 && op_lo <= 8'h4F) begin
                            /*
                            Single-bit status ops (EINT/DINT/ROVM/
                            SOVM/RCNF/SCNF/RSXM/SSXM/RHM/SHM/RTC/
                            STC/RXF/SXF/RCB/SCB).  The flag is the
                            pair index op_lo[3:1] (C exec_be_ctrl,
                            c5x_core.c:2334-2353: 0x40/0x41 INTM,
                            0x42/0x43 OVM, 0x44/0x45 CNF, 0x46/0x47
                            SXM, 0x48/0x49 HM, 0x4A/0x4B TC,
                            0x4C/0x4D XF, 0x4E/0x4F C); op_lo[0]
                            is set (1) versus clear (0).  The old
                            code used the low nibble directly as
                            the select, which is only right for
                            RCNF (0x44 -> FLG_CNF) by coincidence:
                            DINT (0x41) selected FLG_OVM.
                            */
                            st_bit_en  = 1'b1;
                            case (op_lo[3:1])
                                3'b000: st_bit_sel = FLG_INTM;
                                3'b001: st_bit_sel = FLG_OVM;
                                3'b010: st_bit_sel = FLG_CNF;
                                3'b011: st_bit_sel = FLG_SXM;
                                3'b100: st_bit_sel = FLG_HM;
                                3'b101: st_bit_sel = FLG_TC;
                                3'b110: st_bit_sel = FLG_XF;
                                default: st_bit_sel = FLG_C;
                            endcase
                            /*
                            SETC/STC/SOVM/SCNF/SSXM/SHM/SXF/SCB set;
                            CLRC/RTC/ROVM/RCNF/RSXM/RHM/RXF/RCB clear.
                            */
                            st_bit_val = (op_lo[0] == 1'b1);
                            /*
                            EINT (0x40) also sets int_inh (sequential).
                            Only RCB/SCB change C, so only they sync
                            the ALU's C copy (C exec_be_ctrl: 0x4A/
                            0x4B RTC/STC change TC, not C; the old
                            code fired here for RTC/STC instead).
                            */
                            if (op_lo[3:1] == 3'b111) begin
                                alu_flag_c_we = 1'b1;
                                alu_flag_c_in = (op_lo[0] == 1'b1);
                            end
                            /*
                            OVM changes are a mode bit in the addr
                            agent (the ALU reads i_ovm from it).
                            */
                        end else if (op_lo == 8'h51 || op_lo == 8'h52) begin
                            /*
                            TRAP / NMI: push + vector (apply_exec
                            did the push; intm is set sequentially).
                            */
                        end else if (op_lo == 8'h3A) begin
                            /*
                            RETE: intm = 0 (sequential, via restore)
                            */
                        end
                    end
                    8'hBF: begin
                        if (op_lo <= 8'h03) begin /* SPM k */
                            st1_ld_en   = 1'b1;
                            st1_ld_data = {stat_arb, stat_cnf, stat_tc,
                                           stat_sxm, stat_c, 1'b1, 1'b1,
                                           stat_hm, 1'b1, stat_xf, 1'b1,
                                           1'b1, op_lo[1:0]};
                        end else if (op_lo >= 8'h08 && op_lo <= 8'h0F) begin
                            /*
                            LAR #lk
                            */
                            ar_wr_en   = 1'b1;
                            ar_wr_sel  = op_lo[2:0];
                            ar_wr_data = imm_q;
                        end else if (op_lo >= 8'h44 && op_lo <= 8'h47) begin
                            /*
                            CMPR: TC = compare(AR[ARP], ARCR)
                            */
                            st_bit_en  = 1'b1;
                            st_bit_sel = FLG_TC;
                            st_bit_val = cmpr_tc_w;
                        end
                    end
                    default: begin end
                endcase
                /*
                RPT #lk / RPTZ #lk (0xBEC4/0xBEC5): rptc = imm.
                */
                if (op_hi == 8'hBE && (op_lo == 8'hC4 || op_lo == 8'hC5)) begin
                    rptc_ld_en   = 1'b1;
                    rptc_ld_data = imm_q;
                end
                /*
                RPTB (0xBEC6): braf=1, pasr=pc (first block word),
                paer=imm.  BRCR is NOT loaded here (separate MMR).
                */
                if (op_hi == 8'hBE && op_lo == 8'hC6) begin
                    rptb_set_en = 1'b1;
                    rptb_pasr   = pc_q;
                    rptb_paer   = imm_q;
                    rptb_brcr   = 32'd0;
                end
            end
            FSM_LOOP: begin
                /*
                The loop engine drives the datapath per phase.
                (See the loop-engine block below; this case only
                holds the FSM state while the engine works.)
                dm/pm requests are driven by the engine signals.
                */
                dm_req   = loop_dm_req_w;
                dm_wr    = loop_dm_wr_w;
                dm_addr  = loop_dm_addr_w;
                dm_wdata = loop_dm_wdata_w;
                pm_d_req   = loop_pm_req_w;
                pm_d_wr    = loop_pm_wr_w;
                pm_d_addr  = loop_pm_addr_w;
                pm_d_wdata = loop_pm_wdata_w;
                alu_op   = loop_alu_op_w;
                alu_a    = acc_i;
                alu_b    = loop_alu_b_w;
                alu_d    = loop_alu_d_w;
                alu_sh   = loop_alu_sh_w;
                alu_c_in = stat_c;
                alu_en   = loop_alu_en_w;
                alu_s16  = 1'b0;
                acc_ld   = loop_acc_ld_w;
                acc_data = alu_y;
                preg_ld  = loop_preg_ld_w;
                preg_data = mpy_p;
                treg_ld  = loop_treg_ld_w;
                treg_data = loop_treg_data_w;
                mpy_en   = loop_mpy_en_w;
                mpy_a    = loop_mpy_a_w;
                mpy_b    = loop_mpy_b_w;
                ea_en    = loop_ea_en_w;
                ea_op    = op_lo;
                push_en  = loop_push_en_w;
                push_data = loop_push_data_w;
                pop_en   = 1'b0;
                /*
                rptc-- once per iteration (phase NEXT).  The
                do-while forms (MAC/MADS) decrement only when
                rptc > -1 at the check.
                */
                if (loop_ph_q == 3'd5) begin
                    if (loop_do_while_w) begin
                        if (rptc_i != RPTC_MINUS1)
                            rptc_dec_en = 1'b1;
                    end else begin
                        rptc_dec_en = 1'b1;
                    end
                end
            end
            FSM_IO_WAIT: begin
                /*
                Hold the IO request until io_ack_c; the sequential
                block completes the access (IN: write io_rdata_c
                to dm[wr_addr_q]; OUT: nothing more to do).
                */
                io_req_c   = 1'b1;
                io_wr_c    = ex_io_wr;
                io_port_c  = ex_io_port;
                io_wdata_c = ex_io_wdata;
                if (io_ack_c && !ex_io_wr) begin
                    /*
                    IN: write the received word to dm[wr_addr_q].
                    */
                    dm_req   = 1'b1;
                    dm_wr    = 1'b1;
                    dm_addr  = wr_addr_q;
                    dm_wdata = io_rdata_c;
                end
            end
            FSM_TAIL: begin
                /*
                ndx_commit (AR0 mirror) after every instruction
                and after every delay-slot word.
                */
                ndx_commit_o = 1'b1;
                /*
                C/OV writeback (OPEN-9): the ALU registered the new
                flags at the EXEC edge; alu_c/alu_ov are now the
                new values.  Gated on alu_used_q so a non-ALU
                instruction (LST, SETC, ...) never clobbers the
                addr agent's flags with a stale ALU copy.
                */
                if (alu_used_q) begin
                    st0_ld_en   = 1'b1;
                    st0_ld_data = {stat_arp, alu_ov, stat_ovm, 1'b1,
                                   stat_intm, stat_dp};
                    st1_ld_en   = 1'b1;
                    st1_ld_data = {stat_arb, stat_cnf, stat_tc,
                                   stat_sxm, alu_c, 1'b1, 1'b1, stat_hm,
                                   1'b1, stat_xf, 1'b1, 1'b1, stat_pm};
                end
                /*
                handle_rpt strobes (C handle_rpt): rewind decrements
                rptc; a negative rptc is clamped to 0.
                */
                if (rpt_rewind_w)
                    rptc_dec_en = 1'b1;
                else if (rptc_i[31])
                    rptc_ld_en   = 1'b1;
                /*
                handle_braf strobes (C handle_braf): at the last
                block word, brcr>0 rewinds (brcr--) else braf clears.
                */
                if (stat_braf && ((pc_q - 16'd1) == paer_i)) begin
                    if (brcr_i != 32'd0) begin
                        brcr_ld_en   = 1'b1;
                        brcr_ld_data = brcr_i - 32'd1;
                    end else begin
                        rptb_clr_en = 1'b1;
                    end
                end
                /*
                Delayed return (RETCD, kind 2): the pop happens
                when the slot completes (this TAIL clock).
                */
                if (in_slot_q && slot_done_w &&
                    ds_kind_q[ds_sp_q - 2'd1] == 3'd2)
                    pop_en = 1'b1;
                /*
                Interrupt entry: clear the IFR bit of the selected
                interrupt (the INT state does the rest).  The ack
                is a one-hot IFR-bit clear to the mem agent.
                */
                if (int_pending_q) begin
                    irq_ack_o = (9'd1 << int_idx_q);
                end
            end
            FSM_INT: begin
                /*
                Interrupt entry phases (see the sequential block):
                ph 0: push PC, set intm, latch vector, save shadow.
                ph 1: dm read of ivec_ind[i] (if set), latch vector.
                ph 2: jump to the vector.
                */
                case (int_ph_q)
                    2'd0: begin
                        push_en   = 1'b1;
                        push_data = pc_q;
                        st_bit_en  = 1'b1;
                        st_bit_sel = FLG_INTM;
                        st_bit_val = 1'b1;
                        if (!int_is_intr_q)
                            irq_ack_o = (9'd1 << int_idx_q);   /* taken external interrupt: clear its IFR bit (C check_int); the INT path never passes through TAIL, so the TAIL ack never fired */
                    end
                    2'd1: begin
                        if (!dm_wait_q) begin
                            dm_req  = 1'b1;
                            dm_wr   = 1'b0;
                            dm_addr = int_ind_addr_w;
                        end
                    end
                    default: begin end
                endcase
            end
            FSM_TICK: begin
                /*
                Drain the timer ticks: one mtick_en pulse per
                clock until cyc_acc_q reaches 0.  The sequential
                block decrements cyc_acc_q and advances cycles_q
                by 1 per tick clock.  mtick_n is always 1 (one
                machine cycle per tick, the mem agent's i_tick).
                */
                if (cyc_acc_q != 16'd0) begin
                    mtick_en = 1'b1;
                    mtick_n  = tick_fast_w ? cyc_acc_q[7:0] : 8'd1;   /* short charge with no timer expiry in reach: all ticks at once, drained by the core's burst expander in the background */
                end
                /*
                RPTC clamp (C handle_rpt): a loop op that consumed
                rptc leaves it at -1; the C model clamps it to 0
                after the instruction.  The clamp is applied here,
                in TICK, not in TAIL: TAIL also asserts the ST0/ST1
                flag writeback for ALU-using loop ops (MAC/MADS),
                and the top's single write port takes ST0 over
                RPTC, so a TAIL clamp would be dropped for exactly
                those ops.  TICK precedes TAIL and nothing else
                uses the write port here, so the load lands (it
                loads 0; rptc_ld_data defaults to 0).  rptc is 0
                between instructions, so this fires only for a
                loop op that just consumed rptc to -1.  The TAIL
                clamp stays as a fallback for any path that reaches
                TAIL with rptc still negative.
                */
                if (rptc_i[31])
                    rptc_ld_en = 1'b1;
            end
            FSM_DONE: begin
                /*
                The cycles were already advanced during TICK.
                Just pulse instr_done (one clock).
                */
                instr_done = 1'b1;
            end
            FSM_IDLE: begin
                /*
                One machine cycle per clock; the timer advances
                with it except in IDLE2 (frozen).  The sequential
                block advances cycles_q; the timer tick is emitted
                here.
                */
                if (idle_q == 2'd1) begin
                    mtick_en = 1'b1;
                    mtick_n  = idle_inc_w;
                end
            end
            FSM_BADOP: begin
                /*
                Halted.  Nothing to drive.
                */
            end
            FSM_RESTORE: begin
                /*
                RETI/RETE shadow restore, one write per clock.
                INTM and XF are NOT restored (audit #9): the ST0
                word keeps the live stat_intm, the ST1 word keeps
                the live stat_xf.  RETE additionally clears INTM
                (the sequential block sets it after the restore).
                */
                rs_en = 1'b1;
                case (rst_ph_q)
                    4'd0: begin /* restore ACC/ACCB/PREG (ALU loads) */
                        acc_ld     = 1'b1;
                        acc_ld_sel = 1'b1;
                        acc_data   = sh_acc_q;
                        accb_ld    = 1'b1;
                        accb_data  = sh_accb_q;
                        preg_ld    = 1'b1;
                        preg_data  = sh_preg_q;
                    end
                    4'd1: begin /* restore TREG0 */
                        treg_ld   = 3'b001;
                        treg_data = sh_treg0_q;
                    end
                    4'd2: begin /* restore TREG1 */
                        treg_ld   = 3'b010;
                        treg_data = sh_treg1_q;
                    end
                    4'd3: begin /* restore TREG2 */
                        treg_ld   = 3'b100;
                        treg_data = sh_treg2_q;
                    end
                    4'd4: begin /* restore ST0 (ARP/OV/OVM/DP; INTM live) */
                        addr_wr_en_o   = 1'b1;
                        addr_wr_sel_o  = WR_ST0;
                        addr_wr_data_o = {sh_arp_q, sh_ov_q, sh_ovm_q,
                                          1'b1, stat_intm, sh_dp_q};
                        alu_flag_ov_we = 1'b1;
                        alu_flag_ov_in = sh_ov_q;
                    end
                    4'd5: begin /* restore ST1 (ARB/CNF/TC/SXM/C/HM/PM; XF live) */
                        addr_wr_en_o   = 1'b1;
                        addr_wr_sel_o  = WR_ST1;
                        addr_wr_data_o = {sh_arb_q, sh_cnf_q, sh_tc_q,
                                          sh_sxm_q, sh_c_q, 1'b1, 1'b1,
                                          sh_hm_q, 1'b1, stat_xf, 1'b1,
                                          1'b1, sh_pm_q};
                        alu_flag_c_we  = 1'b1;
                        alu_flag_c_in  = sh_c_q;
                    end
                    4'd6: begin /* restore PMST */
                        addr_wr_en_o   = 1'b1;
                        addr_wr_sel_o  = WR_PMST;
                        addr_wr_data_o = {sh_iptr_q, 3'b000, sh_avis_q,
                                          1'b0, sh_ovly_q, sh_ram_q,
                                          sh_mpmc_q, sh_ndx_q, sh_trm_q,
                                          sh_braf_q};
                    end
                    4'd7: begin /* restore ARCR */
                        addr_wr_en_o   = 1'b1;
                        addr_wr_sel_o  = WR_ARCR;
                        addr_wr_data_o = sh_arcr_q;
                    end
                    4'd8: begin /* restore INDX */
                        addr_wr_en_o   = 1'b1;
                        addr_wr_sel_o  = WR_INDX;
                        addr_wr_data_o = sh_indx_q;
                        /*
                        RETE clears INTM after the restore (the
                        shadow INTM is deliberately NOT restored).
                        */
                        if (op_lo == 8'h3A) begin
                            st_bit_en  = 1'b1;
                            st_bit_sel = FLG_INTM;
                            st_bit_val = 1'b0;
                        end
                    end
                    default: begin end
                endcase
            end
            default: begin end
        endcase
    end

    /*
    ------------------------------------------------------------------
    Loop-op engine (SMMR/LMMR/BLDP/BLPD/TBLR/TBLW/BLDD/MAC/MACD/
    MADS/MADD).  Per-iteration phases (loop_ph_q):
      0 EA   -- pulse ea_en (per-iteration ea; skipped for SMMR/
                LMMR, whose ea was evaluated once at entry).
      1 RD   -- issue the source read (dm_req if the source is a
                DM address, pm_d_addr if it is a PM address).
      2 WAIT -- the read data is available (dm_rdata on dm_ack,
                pm_d_rdata one clock after the address); latch it
                into loop_d_q.
      3 PM   -- MAC/MADS only: present pm_d_addr = loop_pfc_q
                (the program word for the multiply).
      4 WR   -- execute (ALU, pm_d_wr for BLDP/TBLW).  MADS/MADD
                issue OP_LT_NM here: ACC += pscale (OLD PREG),
                PREG = dma * pma, TREG0 = dma with NO mirror, all
                in this one phase (KD-23).  MAC uses OP_SQRA in WR,
                which loads TREG0 (with the TRM mirror) in the same
                clock as ACC/PREG.  The dm write is NOT here: a
                pm_d read in PM is accepted at the end of PM, so
                its ack pulse (dm_ack_q) is high through WR and the
                memory's dm_accept (which needs !dm_ack_q) drops a
                write presented in WR (lost MACD/MADD DMOV).  The
                dm write is presented in NEXT instead, where the
                ack has cleared.
      5 NEXT -- present this iteration's dm write (accepted at the
                NEXT edge), then decrement the iteration counter
                (and rptc); if more iterations, back to EA (or RD
                for SMMR/LMMR), else to TAIL.
                There is no phase 6 any more: the old TREG phase
                (MADS/MADD TREG0 load via OP_LT) was retired when
                OP_LT_NM moved the load into WR.
    The source is a DM address for SMMR (a), LMMR (pfc), BLDP (a),
    TBLW (a), BLDD (pfc or a), MAC/MADS (a); it is a PM address
    for BLPD (pfc) and TBLR (pfc).  The destination is a DM write
    for LMMR/BLPD/TBLR/BLDD, a PM write (pm_d_wr) for BLDP/TBLW,
    and a DM write to pfc for SMMR (dm_wr routes to PMEM when the
    address is not internal -- the C dm_wr(pfc, ...) call).
    ------------------------------------------------------------------
    */
    logic        loop_dm_req_w, loop_dm_wr_w;
    logic [15:0] loop_dm_addr_w, loop_dm_wdata_w;
    logic        loop_pm_req_w, loop_pm_wr_w;
    logic [15:0] loop_pm_addr_w, loop_pm_wdata_w;
    logic [6:0]  loop_alu_op_w;
    logic [31:0] loop_alu_b_w;
    logic [15:0] loop_alu_d_w;
    logic [3:0]  loop_alu_sh_w;
    logic        loop_alu_en_w;
    logic        loop_acc_ld_w, loop_preg_ld_w;
    logic [2:0]  loop_treg_ld_w;
    logic [15:0] loop_treg_data_w;
    logic        loop_mpy_en_w;
    logic [15:0] loop_mpy_a_w, loop_mpy_b_w;
    logic        loop_ea_en_w;
    logic        loop_push_en_w;
    logic [15:0] loop_push_data_w;

    /*
    Is the source a PM address (read via pm_d) or a DM address?
    */
    logic loop_src_is_pm_w;
    assign loop_src_is_pm_w = (loop_kind_q == 4'd3) || /* BLPD */
                              (loop_kind_q == 4'd4); /* TBLR */

    /*
    Does this kind need the extra pm read of pfc (MAC/MADS)?
    */
    logic loop_needs_pm_w;
    assign loop_needs_pm_w = (loop_kind_q == 4'd7) || /* MAC/MACD */
                             (loop_kind_q == 4'd8); /* MADS/MADD */

    /*
    Is this kind a do-while (runs at least once even with rptc==-1)?
    */
    logic loop_do_while_w;
    assign loop_do_while_w = (loop_kind_q == 4'd7) ||
                             (loop_kind_q == 4'd8);

    /*
    The source read address (DM) and the destination write address.
    */
    logic [15:0] loop_src_dm_w;
    logic [15:0] loop_dst_w;
    always_comb begin
        case (loop_kind_q)
            4'd0: begin /* SMMR: src = a (fixed), dst = pfc */
                loop_src_dm_w = loop_a_q;
                loop_dst_w    = loop_pfc_q;
            end
            4'd1: begin /* LMMR: src = pfc, dst = a (fixed) */
                loop_src_dm_w = loop_pfc_q;
                loop_dst_w    = loop_a_q;
            end
            4'd2: begin /* BLDP: src = a, dst = pfc (PM) */
                loop_src_dm_w = loop_a_q;
                loop_dst_w    = loop_pfc_q;
            end
            4'd3: begin /* BLPD: src = pfc (PM), dst = a */
                loop_src_dm_w = loop_pfc_q;
                loop_dst_w    = loop_a_q;
            end
            4'd4: begin /* TBLR: src = pfc (PM), dst = a */
                loop_src_dm_w = loop_pfc_q;
                loop_dst_w    = loop_a_q;
            end
            4'd5: begin /* TBLW: src = a, dst = pfc (PM) */
                loop_src_dm_w = loop_a_q;
                loop_dst_w    = loop_pfc_q;
            end
            4'd6: begin /* BLDD: src/dst depend on the direction */
                if (op_hi == 8'hA8 || op_hi == 8'hAC) begin
                    /*
                    #lk,dma / bmar,dma: src = pfc, dst = a
                    */
                    loop_src_dm_w = loop_pfc_q;
                    loop_dst_w    = loop_a_q;
                end else begin
                    /*
                    dma,#lk / dma,bmar: src = a, dst = pfc
                    */
                    loop_src_dm_w = loop_a_q;
                    loop_dst_w    = loop_pfc_q;
                end
            end
            default: begin /* MAC/MADS: src = a, dst = n/a */
                loop_src_dm_w = loop_a_q;
                loop_dst_w    = loop_a_q;
            end
        endcase
    end

    always_comb begin
        /*
        Defaults: no datapath action.
        */
        loop_dm_req_w   = 1'b0;
        loop_dm_wr_w    = 1'b0;
        loop_dm_addr_w  = loop_src_dm_w;
        loop_dm_wdata_w = loop_d_q;
        loop_pm_req_w   = 1'b0;
        loop_pm_wr_w    = 1'b0;
        loop_pm_addr_w  = loop_pfc_q;
        loop_pm_wdata_w = loop_d_q;
        loop_alu_op_w   = ALU_NOP;
        loop_alu_b_w    = 32'd0;
        loop_alu_d_w    = loop_d_q;
        loop_alu_sh_w   = 4'd0;
        loop_alu_en_w   = 1'b0;
        loop_acc_ld_w   = 1'b0;
        loop_preg_ld_w  = 1'b0;
        loop_treg_ld_w  = 3'b000;
        loop_treg_data_w = 16'd0;
        loop_mpy_en_w   = 1'b0;
        loop_mpy_a_w    = 16'd0;
        loop_mpy_b_w    = 16'd0;
        loop_ea_en_w    = 1'b0;
        loop_push_en_w  = 1'b0;
        loop_push_data_w = 16'd0;

        case (loop_ph_q)
            3'd0: begin /* EA: pulse ea_en (per-iteration ea). */
                if (loop_kind_q != 4'd0 && loop_kind_q != 4'd1) begin
                    loop_ea_en_w = 1'b1;
                end
            end
            3'd1: begin /* RD: issue the source read. */
                if (loop_src_is_pm_w) begin
                    loop_pm_req_w  = 1'b1;
                    loop_pm_wr_w   = 1'b0;
                    loop_pm_addr_w = loop_pfc_q;
                end else begin
                    if (!dm_wait_q) begin
                        loop_dm_req_w  = 1'b1;
                        loop_dm_wr_w   = 1'b0;
                        loop_dm_addr_w = loop_src_dm_w;
                    end
                end
            end
            3'd2: begin /* WAIT: the read data is available; the */
                        /*
                        sequential block latches loop_d_q.  Nothing
                        to drive here.
                        */
            end
            3'd3: begin /* PM: MAC/MADS present pm_d_addr = pfc. */
                if (loop_needs_pm_w) begin
                    loop_pm_req_w  = 1'b1;
                    loop_pm_wr_w   = 1'b0;
                    loop_pm_addr_w = loop_pfc_q;
                end
            end
            3'd4: begin /* WR: execute (the dm write moved to NEXT). */
                /*
                The dm write is NOT presented here any more: a pm_d
                read in the PM phase is accepted at the end of PM,
                so its ack pulse (dm_ack_q) is high through the whole
                WR cycle, and the memory's dm_accept (which needs
                !dm_ack_q) drops a write presented in WR.  That
                silently lost the DMOV write of MACD/MADD (and the
                write of any loop op whose pfc is a pm_d read:
                BLPD bmar, TBLR, BLDD bmar).  The write is presented
                in NEXT instead, where the ack has cleared; the ALU
                issue and the pm writes (BLDP/TBLW, a separate
                channel) stay here.
                */
                case (loop_kind_q)
                    4'd0: begin /* SMMR: dm write in NEXT. */ end
                    4'd1: begin /* LMMR: dm write in NEXT. */ end
                    4'd2: begin /* BLDP: pm_wr(pfc, d) */
                        loop_pm_req_w   = 1'b1;
                        loop_pm_wr_w    = 1'b1;
                        loop_pm_addr_w  = loop_pfc_q;
                        loop_pm_wdata_w = loop_d_q;
                    end
                    4'd3, 4'd4: begin /* BLPD / TBLR: dm write in NEXT. */
                    end
                    4'd5: begin /* TBLW: pm_wr(pfc, d) */
                        loop_pm_req_w   = 1'b1;
                        loop_pm_wr_w    = 1'b1;
                        loop_pm_addr_w  = loop_pfc_q;
                        loop_pm_wdata_w = loop_d_q;
                    end
                    4'd6: begin /* BLDD: dm write in NEXT. */ end
                    4'd7: begin /* MAC: OP_SQRA does all three -- */
                        /*
                        ACC += pscale, PREG = d*pm, TREG0 = d
                        (with the TRM mirror, i.e. set_t0).
                        */
                        loop_alu_op_w = ALU_SQRA;
                        loop_alu_b_w  = pscale_w;
                        loop_alu_en_w = 1'b1;
                        loop_acc_ld_w = 1'b1;
                        loop_treg_ld_w = 3'b001;
                        loop_treg_data_w = loop_d_q;
                        loop_mpy_en_w = 1'b1;
                        loop_mpy_a_w  = loop_d_q;
                        loop_mpy_b_w  = pm_d_rdata;
                        loop_preg_ld_w = 1'b1;
                        loop_alu_d_w  = loop_d_q;
                        /*
                        MACD additionally DMOVs dma -> dma+1
                        (dmov_wr gate); the write is presented in
                        NEXT, not here (see the WR-phase comment).
                        */
                    end
                    4'd8: begin /* MADS: OP_LT_NM for ACC/PREG/TREG0. */
                        /*
                        Whole-body single issue (KD-23 / OPEN-10):
                        OP_LT_NM does ACC += pscale(OLD PREG),
                        PREG = dma * pma and TREG0 = dma with NO
                        TREG1/TREG2 mirror (C c5x_core.c:2083-2105:
                        c->treg0 = d directly, audit N-1, no
                        set_t0).  It is identical to OP_MPYA for
                        ACC/PREG/C/OV, plus the TREG0 load, so the
                        WR phase takes the extra treg strobes and
                        there is no separate TREG phase any more:
                        OP_LT_NM's C/OV updates fire whenever
                        i_exec is high, so issuing it in a second
                        phase would overwrite the C/OV of this
                        add with a second add off the NEW PREG.
                        */
                        loop_alu_op_w = ALU_LT_NM;
                        loop_alu_b_w  = pscale_w;
                        loop_alu_en_w = 1'b1;
                        loop_acc_ld_w = 1'b1;
                        loop_mpy_en_w = 1'b1;
                        loop_mpy_a_w  = loop_d_q;
                        loop_mpy_b_w  = pm_d_rdata;
                        loop_preg_ld_w = 1'b1;
                        loop_treg_ld_w = 3'b001;
                        loop_treg_data_w = loop_d_q;
                        /*
                        MADD additionally DMOVs dma -> dma+1
                        (dmov_wr gate); the write is presented in
                        NEXT, not here (see the WR-phase comment).
                        */
                    end
                    default: begin end
                endcase
            end
            3'd5: begin /* NEXT: present this iteration's dm write. */
                /*
                The write lands exactly once per iteration, accepted
                at the NEXT edge: by this phase the PM-read ack has
                cleared (dm_ack_q is low), so dm_accept is true.  The
                phase count is unchanged (NEXT already ran one cycle
                per iteration), and the wait-state charge moved with
                the write (sequential, phase NEXT).  loop_a_q,
                loop_d_q, loop_pfc_q and loop_dst_w are stable from
                WR through NEXT (latched in EA/RD), so the address
                and data are the same as WR presented.  BLDP/TBLW
                have no dm write (their pm write stays in WR).
                */
                case (loop_kind_q)
                    4'd0: begin /* SMMR: dm_wr(pfc, d) */
                        loop_dm_req_w   = 1'b1;
                        loop_dm_wr_w    = 1'b1;
                        loop_dm_addr_w  = loop_pfc_q;
                        loop_dm_wdata_w = loop_d_q;
                    end
                    4'd1: begin /* LMMR: dm_wr(a, d) */
                        loop_dm_req_w   = 1'b1;
                        loop_dm_wr_w    = 1'b1;
                        loop_dm_addr_w  = loop_a_q;
                        loop_dm_wdata_w = loop_d_q;
                    end
                    4'd3, 4'd4: begin /* BLPD / TBLR: dm_wr(a, d) */
                        loop_dm_req_w   = 1'b1;
                        loop_dm_wr_w    = 1'b1;
                        loop_dm_addr_w  = loop_a_q;
                        loop_dm_wdata_w = loop_d_q;
                    end
                    4'd6: begin /* BLDD: dm_wr(dst, d) */
                        loop_dm_req_w   = 1'b1;
                        loop_dm_wr_w    = 1'b1;
                        loop_dm_addr_w  = loop_dst_w;
                        loop_dm_wdata_w = loop_d_q;
                    end
                    4'd7: begin /* MACD: DMOV dma -> dma+1 */
                        if (op_hi == 8'hA3 && dmov_gate_f(loop_a_q)) begin
                            loop_dm_req_w   = 1'b1;
                            loop_dm_wr_w    = 1'b1;
                            loop_dm_addr_w  = loop_a_q + 16'd1;
                            loop_dm_wdata_w = loop_d_q;
                        end
                    end
                    4'd8: begin /* MADD: DMOV dma -> dma+1 */
                        if (op_hi == 8'hAB && dmov_gate_f(loop_a_q)) begin
                            loop_dm_req_w   = 1'b1;
                            loop_dm_wr_w    = 1'b1;
                            loop_dm_addr_w  = loop_a_q + 16'd1;
                            loop_dm_wdata_w = loop_d_q;
                        end
                    end
                    default: begin end
                endcase
            end
            default: begin end
        endcase
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
            if (!int_sel_found_w && (ifr_i[i] && imr_i[i])) begin
                int_sel_w       = i[3:0];
                int_sel_found_w = 1'b1;
            end
        end
    end

    /*
    XC hold for the instruction just executed (C interrupt_held):
    xc_new holds one check and clears; else xc_left -= words, and
    the check is held while xc_left > 0 after the subtraction.
    Also held when braf && pc == paer (the last block word).
    */
    logic xc_hold_w;
    logic [1:0] xc_left_after_w;
    always_comb begin
        if (xc_new_q) begin
            xc_hold_w       = 1'b1;
            xc_left_after_w = xc_left_q;
        end else begin
            xc_left_after_w = xc_left_q - words_q[1:0];
            xc_hold_w = (xc_left_after_w != 2'd0) && (xc_left_q != 2'd0);
        end
        if (stat_braf && (pc_q == paer_i))
            xc_hold_w = 1'b1;
    end

    /*
    Delay-slot completion: (pc - start) >= 2 (16-bit unsigned).
    Only meaningful while a slot is in flight.
    */
    logic slot_done_w;
    assign slot_done_w = in_slot_q &&
        ((pc_q - ds_start_q[ds_sp_q - 2'd1]) >= 16'd2);

    /*
    handle_rpt (C handle_rpt) in TAIL: rewind when rptc>0 and the
    instruction just executed is the repeated one (ppc==rpt_end).
    The post-tail rep_cont is 1 exactly when rewinding; the
    post-tail rptc is rptc-1 when rewinding, else rptc (clamped to
    0 when negative).  The interrupt check below uses the
    post-tail values (the C model runs handle_rpt first).
    */
    logic rpt_rewind_w;
    logic rep_cont_after_w;
    logic [31:0] rptc_after_w;
    assign rpt_rewind_w    = (rptc_i[31] == 1'b0) && (rptc_i != 32'd0) &&
                             (tail_ppc_w == rpt_end_q);
    assign rep_cont_after_w = rpt_rewind_w;
    always_comb begin
        if (rpt_rewind_w)
            rptc_after_w = rptc_i - 32'd1;
        else if (rptc_i[31])
            rptc_after_w = 32'd0;
        else
            rptc_after_w = rptc_i;
    end

    /*
    The ppc to use for handle_rpt in TAIL: the outer instruction's
    ppc when a delay slot just finished, else the current ppc.
    */
    logic [15:0] tail_ppc_w;
    assign tail_ppc_w = (in_slot_q && slot_done_w) ?
                        ds_ppc_q[ds_sp_q - 2'd1] : ppc_q;

    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                state_q       <= FSM_RESET;
                pc_q          <= RESET_PC;
                op_q          <= 16'd0;
                imm_q         <= 16'd0;
                ppc_q         <= 16'd0;
                sp0_q         <= 3'd0;
                words_q       <= 2'd0;
                cyc_acc_q     <= 16'd0;
                cycles_q      <= 64'd0;
                rpt_start_q   <= 16'd0;
                rpt_end_q     <= 16'd0;
                rep_cont_q    <= 1'b0;
                int_inh_q     <= 1'b0;
                xc_new_q      <= 1'b0;
                xc_left_q     <= 2'd0;
                idle_q        <= 2'd0;
                io_rep_q      <= 16'd0;
                wr_addr_q     <= 16'd0;
                int_idx_q     <= 4'd0;
                int_via_ind_q <= 1'b0;
                int_vec_q     <= 16'd0;
                int_ph_q      <= 2'd0;
                ds_sp_q       <= 2'd0;
                in_slot_q     <= 1'b0;
                loop_kind_q   <= 4'd0;
                loop_ph_q     <= 3'd0;
                loop_cnt_q    <= 32'd0;
                loop_pfc_q    <= 16'd0;
                loop_a_q      <= 16'd0;
                loop_d_q      <= 16'd0;
                alu_used_q    <= 1'b0;
                int_pending_q <= 1'b0;
                int_idle_q    <= 1'b0;
                badop_q       <= 1'b0;
                idle_next_q   <= 2'd0;
                dm_wait_q     <= 1'b0;
                dm_rd_ws_q    <= 4'd0;
                int_is_intr_q <= 1'b0;
                rst_ph_q      <= 4'd0;
                sh_acc_q      <= 32'd0;
                sh_accb_q     <= 32'd0;
                sh_preg_q     <= 32'd0;
                sh_treg0_q    <= 16'd0;
                sh_treg1_q    <= 16'd0;
                sh_treg2_q    <= 16'd0;
                sh_arcr_q     <= 16'd0;
                sh_indx_q     <= 16'd0;
                sh_arp_q      <= 3'd0;
                sh_arb_q      <= 3'd0;
                sh_dp_q       <= 9'd0;
                sh_ov_q       <= 1'b0;
                sh_ovm_q      <= 1'b0;
                sh_cnf_q      <= 1'b0;
                sh_tc_q       <= 1'b0;
                sh_sxm_q      <= 1'b0;
                sh_c_q        <= 1'b0;
                sh_hm_q       <= 1'b0;
                sh_pm_q       <= 2'd0;
                sh_iptr_q     <= 5'd0;
                sh_avis_q     <= 1'b0;
                sh_ovly_q     <= 1'b0;
                sh_ram_q      <= 1'b0;
                sh_mpmc_q     <= 1'b0;
                sh_ndx_q      <= 1'b0;
                sh_trm_q      <= 1'b0;
                sh_braf_q     <= 1'b0;
                for (int i = 0; i < 4; i++) begin
                    ds_start_q[i] <= 16'd0;
                    ds_ppc_q[i]   <= 16'd0;
                    ds_tgt_q[i]   <= 16'd0;
                    ds_kind_q[i]  <= 3'd0;
                end
            end else begin
                case (state_q)
                    FSM_RESET: begin
                        state_q <= FSM_FETCH_ADDR;
                        pc_q    <= RESET_PC;
                    end
                    FSM_FETCH_ADDR: begin
                        state_q <= FSM_FETCH_DATA;
                    end
                    FSM_FETCH_DATA: begin
                        /*
                        Latch the opcode; pc advances past it.
                        */
                        op_q    <= pm_rdata;
                        ppc_q   <= pc_q;
                        sp0_q   <= sp_i;
                        words_q <= 2'd1;
                        pc_q    <= pc_q + 16'd1;
                        /*
                        The decoder (combinational on pm_rdata) reports
                        the word count and the BADOP flag for this op.
                        */
                        if (dec_badop) begin
                            badop_q   <= 1'b1;
                            cyc_acc_q <= {8'd0, dec_cycles};
                            pc_q      <= pc_q; /* restored to ppc in BADOP */
                            state_q   <= FSM_BADOP;
                        end else if (dec_words == 2'd2) begin
                            state_q <= FSM_FETCH2_ADDR;
                        end else if (needs_op_addr) begin
                            state_q <= FSM_OP_ADDR;
                        end else begin
                            state_q <= FSM_EXEC;
                        end
                    end
                    FSM_FETCH2_ADDR: begin
                        state_q <= FSM_FETCH2_DATA;
                    end
                    FSM_FETCH2_DATA: begin
                        /*
                        Latch the immediate word; pc advances past it.
                        */
                        imm_q   <= pm_rdata;
                        words_q <= 2'd2;
                        pc_q    <= pc_q + 16'd1;
                        if (dec_badop) begin
                            badop_q   <= 1'b1;
                            cyc_acc_q <= {8'd0, dec_cycles};
                            state_q   <= FSM_BADOP;
                        end else if (needs_op_addr) begin
                            state_q <= FSM_OP_ADDR;
                        end else begin
                            state_q <= FSM_EXEC;
                        end
                    end
                    FSM_OP_ADDR: begin
                        if (!dm_wait_q) begin
                            /*
                            The ea_en pulse was presented this clock;
                            latch the ea.  If a dm read was issued,
                            wait for dm_ack; otherwise go straight to
                            EXEC (write-only op, ea_q is the address).
                            */
                            ea_q <= ea_i;
                            if (needs_dm_rd) begin
                                /*
                                Latch this read's wait states now: the
                                read address is on dm_addr this clock
                                (io_ws_i is its io_ws), but by the
                                OP_DATA charge the address is gone, and
                                for page-0-masked reads (LAMM/SAMM)
                                ea_q alone would give the wrong page
                                under big-pages CWSR.  C charges the
                                full io_ws for a dm read (io_read).
                                */
                                dm_rd_ws_q <= io_ws_i;
                                dm_wait_q <= 1'b1;
                            end else if (is_loop_op) begin
                                /*
                                Loop ops have no dm read here (their
                                reads happen per iteration in FSM_LOOP);
                                OP_DATA is where the loop engine is set
                                up, so go there, not to EXEC.
                                */
                                state_q <= FSM_OP_DATA;
                            end else begin
                                state_q <= FSM_EXEC;
                            end
                        end else if (dm_ack) begin
                            dm_wait_q <= 1'b0;
                            state_q   <= FSM_OP_DATA;
                        end
                        /*
                        Else: stay in OP_ADDR (dm_req deasserted) until
                        dm_ack (host-window / IO reads take longer).
                        */
                    end
                    FSM_OP_DATA: begin
                        /*
                        The instruction executes on dm_rdata this edge.
                        Charge the base cycles (class-adjusted), plus
                        the mmr_bus +1 for a dm write to a peripheral
                        MMR (0x20-0x4F, C mmr_bus), plus the dm-access
                        wait states (C io_read/io_write): a dm read
                        from IO space adds its full io_ws (latched in
                        OP_ADDR as dm_rd_ws_q), and a dm write to IO
                        space adds io_ws-1 when io_ws > 1.  The write
                        term is gated on !is_loop_op: loop ops present
                        no write here (the LOOP engine does the work),
                        and their write charge is added per iteration
                        in the LOOP WR phase instead.
                        */
                        cyc_acc_q <= cyc_acc_q + {8'd0, base_cyc_q} +
                                     ((ex_dm_wr && mmr_wr_hit) ? 16'd1 : 16'd0) +
                                     ((needs_dm_rd) ? {12'd0, dm_rd_ws_q} :
                                                      16'd0) +
                                     ((!is_loop_op && ex_dm_wr &&
                                       (io_ws_i > 4'd1)) ?
                                      ({12'd0, io_ws_i} - 16'd1) : 16'd0);
                        alu_used_q <= ex_alu_en;
                        if (is_loop_op) begin
                            /*
                            Set up the loop engine and go to LOOP.
                            */
                            loop_kind_q <= loop_kind_next;
                            loop_pfc_q <= loop_pfc_next;
                            /*
                            SMMR/LMMR use page 0 (C: a = ea(c) & 0x7f);
                            the addr unit's o_ea is unmasked for them,
                            so mask here.  The other loop ops use the
                            full ea.
                            */
                            if (ea_mask_p0)
                                loop_a_q <= {9'd0, ea_q[6:0]};
                            else
                                loop_a_q <= ea_q;
                            /*
                            The TAIL C/OV writeback (OPEN-9) is gated
                            on alu_used_q, which the datapath leaves
                            clear for loop ops (they have no ex case).
                            MAC/MACD/MADS/MADD use the ALU in the LOOP
                            WR phase, so set it here; block moves do
                            not touch C/OV and leave it clear.
                            */
                            alu_used_q <= (op_hi == 8'hA2) ||
                                          (op_hi == 8'hA3) ||
                                          (op_hi == 8'hAA) ||
                                          (op_hi == 8'hAB);
                            /*
                            Iteration count: while loops run 0 times
                            when rptc == -1; do-while runs at least once.
                            */
                            if (op_hi == 8'hA2 || op_hi == 8'hA3 ||
                                op_hi == 8'hAA || op_hi == 8'hAB) begin
                                loop_cnt_q <= (rptc_i == RPTC_MINUS1) ?
                                              32'd1 : (rptc_i + 32'd1);
                            end else begin
                                loop_cnt_q <= (rptc_i == RPTC_MINUS1) ?
                                              32'd0 : (rptc_i + 32'd1);
                            end
                            /*
                            Loop extra cycles: (n-1)*k, k=2 for
                            SMMR/LMMR, k=1 otherwise.  n==0 -> 0.
                            The count is the full 16-bit rptc, not
                            the low 7 bits: RPT #lk / RPT dma set
                            rptc up to 65535, and the old [6:0]
                            slice undercharged any rptc >= 128.
                            */
                            if (rptc_i == RPTC_MINUS1) begin
                                /*
                                n==0 (while) or n==1 (do-while): no extra
                                */
                            end else if (op_hi == 8'h09 || op_hi == 8'h89) begin
                                cyc_acc_q <= cyc_acc_q + {8'd0, base_cyc_q} +
                                             rptc_i[15:0] * 16'd2;
                            end else begin
                                cyc_acc_q <= cyc_acc_q + {8'd0, base_cyc_q} +
                                             rptc_i[15:0];
                            end
                            /*
                            A while-form loop op with rptc == -1 runs
                            zero iterations in the C model (while
                            (rptc > -1) fails at once).  The LOOP
                            engine checks the count only in NEXT, so
                            entering it would run one spurious
                            iteration; skip it and drain the base
                            cycles in TICK instead.  Do-while forms
                            always run at least once.
                            */
                            if ((op_hi == 8'hA2 || op_hi == 8'hA3 ||
                                 op_hi == 8'hAA || op_hi == 8'hAB) ||
                                (rptc_i != RPTC_MINUS1)) begin
                                loop_ph_q <= 3'd0;
                                state_q   <= FSM_LOOP;
                            end else begin
                                state_q        <= FSM_TICK;
                                tick_to_done_q <= 1'b0;
                            end
                        end else if (ex_io_req) begin
                            /*
                            IN / OUT: latch the dm write address (IN)
                            and go wait for the IO ack.
                            */
                            wr_addr_q <= ea_q;
                            state_q   <= FSM_IO_WAIT;
                        end else begin
                            /*
                            Normal execute: apply the PC action, then
                            drain the cycles in TICK before TAIL.
                            */
                            state_q <= FSM_TICK;
                            tick_to_done_q <= 1'b0;
                            case (ex_pc_act)
                                PC_JMP: begin
                                    if (ex_ds_take)
                                        pc_q <= ex_pc_tgt;
                                end
                                PC_DSLOT: begin
                                    if (ex_ds_take) begin
                                        /*
                                        Push the delay-slot entry.
                                        */
                                        ds_start_q[ds_sp_q] <= pc_q;
                                        ds_ppc_q[ds_sp_q]   <= ppc_q;
                                        ds_tgt_q[ds_sp_q]   <= ex_pc_tgt;
                                        ds_kind_q[ds_sp_q]  <= ex_ds_kind;
                                        ds_sp_q             <= ds_sp_q + 2'd1;
                                        in_slot_q           <= 1'b1;
                                        state_q             <= FSM_FETCH_ADDR;
                                    end
                                end
                                PC_RET: begin
                                    pc_q <= pop_data;
                                end
                                PC_IDLE: begin
                                    idle_next_q <= (op_lo == 8'h23) ? 2'd2 : 2'd1;
                                end
                                default: begin end
                            endcase
                            /*
                            XC: a taken XC opens the uninterruptible
                            window (xc_left=2, xc_new=1).
                            */
                            if (op_hi == 8'hE4 || op_hi == 8'hE5 ||
                                op_hi == 8'hE6 || op_hi == 8'hE7 ||
                                op_hi == 8'hF4 || op_hi == 8'hF5 ||
                                op_hi == 8'hF6 || op_hi == 8'hF7) begin
                                if (cond_q) begin
                                    xc_left_q <= 2'd2;
                                    xc_new_q  <= 1'b1;
                                end else begin
                                    /*
                                    False XC: skip n words.
                                    */
                                    pc_q <= pc_q + {15'd0, op_q[12]} + 16'd1;
                                end
                            end
                            /*
                            EINT: one-cycle interrupt inhibit.
                            */
                            if (op_hi == 8'hBE && op_lo == 8'h40)
                                int_inh_q <= 1'b1;
                            /*
                            RPT: the next instruction is the repeated one.
                            */
                            if (op_hi == 8'h0B || op_hi == 8'hBB ||
                                (op_hi == 8'hBE && (op_lo == 8'hC4 ||
                                                    op_lo == 8'hC5))) begin
                                rpt_start_q <= pc_q;
                                rpt_end_q   <= pc_q;
                            end
                            /*
                            RETI/RETE: go to the restore sequencer.
                            */
                            if (op_hi == 8'hBE && (op_lo == 8'h38 ||
                                                    op_lo == 8'h3A)) begin
                                rst_ph_q <= 4'd0;
                                state_q  <= FSM_RESTORE;
                            end
                            /*
                            INTR: go to the interrupt-entry sequencer.
                            */
                            if (op_hi == 8'hBE && (op_lo >= 8'h60 &&
                                                    op_lo <= 8'h7F)) begin
                                int_is_intr_q <= 1'b1;
                                int_idx_q <= intr_ind_hit_w ?
                                             {1'b0, intr_ind_idx_w[2:0]} : 4'd0;
                                int_via_ind_q <= intr_ind_hit_w &&
                                                 (intr_ind_addr_w != 16'd0);
                                int_vec_q <= {stat_iptr, 5'b00000, intr_v_w};
                                int_ph_q  <= 2'd0;
                                state_q   <= FSM_INT;
                            end
                        end
                    end
                    FSM_EXEC: begin
                        /*
                        Register-only / write-only execute.  Same tail
                        handling as OP_DATA (shared below via a
                        fall-through is not possible in SystemVerilog,
                        so the PC-action block is duplicated here).
                        Charge the base cycles plus the mmr_bus +1,
                        plus the dm-write wait states (C io_write):
                        a dm write to IO space adds io_ws-1 when
                        io_ws > 1.  The write is presented this clock
                        (ex_dm_wr), so io_ws_i is its io_ws.  This is
                        the SPLK site: SPLK #imm,0x57 charges 2 base
                        + 6 (io_ws 7) = 8 in the C model.
                        */
                        cyc_acc_q <= cyc_acc_q + {8'd0, base_cyc_q} +
                                     ((ex_dm_wr && mmr_wr_hit) ? 16'd1 : 16'd0) +
                                     ((ex_dm_wr && (io_ws_i > 4'd1)) ?
                                      ({12'd0, io_ws_i} - 16'd1) : 16'd0);
                        alu_used_q <= ex_alu_en;
                        if (ex_io_req) begin
                            wr_addr_q <= ea_q;
                            state_q   <= FSM_IO_WAIT;
                        end else begin
                            state_q <= FSM_TICK;
                            tick_to_done_q <= 1'b0;
                            case (ex_pc_act)
                                PC_JMP: begin
                                    if (ex_ds_take)
                                        pc_q <= ex_pc_tgt;
                                end
                                PC_DSLOT: begin
                                    if (ex_ds_take) begin
                                        ds_start_q[ds_sp_q] <= pc_q;
                                        ds_ppc_q[ds_sp_q]   <= ppc_q;
                                        ds_tgt_q[ds_sp_q]   <= ex_pc_tgt;
                                        ds_kind_q[ds_sp_q]  <= ex_ds_kind;
                                        ds_sp_q             <= ds_sp_q + 2'd1;
                                        in_slot_q           <= 1'b1;
                                        state_q             <= FSM_FETCH_ADDR;
                                    end
                                end
                                PC_RET: begin
                                    pc_q <= pop_data;
                                end
                                PC_IDLE: begin
                                    idle_next_q <= (op_lo == 8'h23) ? 2'd2 : 2'd1;
                                end
                                default: begin end
                            endcase
                            if (op_hi == 8'hE4 || op_hi == 8'hE5 ||
                                op_hi == 8'hE6 || op_hi == 8'hE7 ||
                                op_hi == 8'hF4 || op_hi == 8'hF5 ||
                                op_hi == 8'hF6 || op_hi == 8'hF7) begin
                                if (cond_q) begin
                                    xc_left_q <= 2'd2;
                                    xc_new_q  <= 1'b1;
                                end else begin
                                    pc_q <= pc_q + {15'd0, op_q[12]} + 16'd1;
                                end
                            end
                            if (op_hi == 8'hBE && op_lo == 8'h40)
                                int_inh_q <= 1'b1;
                            if (op_hi == 8'h0B || op_hi == 8'hBB ||
                                (op_hi == 8'hBE && (op_lo == 8'hC4 ||
                                                    op_lo == 8'hC5))) begin
                                rpt_start_q <= pc_q;
                                rpt_end_q   <= pc_q;
                            end
                            if (op_hi == 8'hBE && (op_lo == 8'h38 ||
                                                    op_lo == 8'h3A)) begin
                                rst_ph_q <= 4'd0;
                                state_q  <= FSM_RESTORE;
                            end
                            if (op_hi == 8'hBE && (op_lo >= 8'h60 &&
                                                    op_lo <= 8'h7F)) begin
                                int_is_intr_q <= 1'b1;
                                int_idx_q <= intr_ind_hit_w ?
                                             {1'b0, intr_ind_idx_w[2:0]} : 4'd0;
                                int_via_ind_q <= intr_ind_hit_w &&
                                                 (intr_ind_addr_w != 16'd0);
                                int_vec_q <= {stat_iptr, 5'b00000, intr_v_w};
                                int_ph_q  <= 2'd0;
                                state_q   <= FSM_INT;
                            end
                        end
                    end
                    FSM_LOOP: begin
                        case (loop_ph_q)
                            3'd0: begin /* EA */
                                if (loop_kind_q == 4'd0 || loop_kind_q == 4'd1)
                                    loop_ph_q <= 3'd1; /* ea already done */
                                else begin
                                    /*
                                    Latch this iteration's ea.  The
                                    output block pulses ea_en in this
                                    phase, so o_ea is this iteration's
                                    address (old AR value for indirect;
                                    the AR update commits at this edge)
                                    and the RD phase reads it from
                                    loop_a_q.  The C model calls ea()
                                    once per iteration; without this
                                    latch every iteration would reuse
                                    the entry ea while the ARs advanced
                                    underneath it.  SMMR/LMMR skip this
                                    phase: their ea was evaluated once
                                    at entry (KD-9).
                                    */
                                    loop_a_q  <= ea_i;
                                    loop_ph_q <= 3'd1;
                                end
                            end
                            3'd1: begin /* RD: issue the source read. */
                                if (dm_ack && !dm_wait_q) begin
                                    /*
                                    Stale ack from the previous access is
                                    still high in this cycle: the memory's
                                    dm_accept needs !dm_ack_q, so a read
                                    presented now would be dropped, and
                                    the phase would then wait forever on
                                    an ack that never comes (the RD phase
                                    sets dm_wait_q on presentation and
                                    only clears it on dm_ack).  This bites
                                    on a repeat of SMMR/LMMR, which skip
                                    EA (their ea is fixed): the NEXT-phase
                                    dm write's ack is still high in the
                                    first RD cycle, with no gap cycle to
                                    absorb it.  Hold RD with the read
                                    presented until dm_ack clears; the
                                    read is then accepted at that edge.
                                    One raw clock, not a model cycle
                                    (cyc_acc_q is unchanged).
                                    */
                                end else if (loop_src_is_pm_w) begin
                                    loop_ph_q <= 3'd2; /* pm data next clock */
                                end else if (!dm_wait_q) begin
                                    /*
                                    Latch this read's wait states now:
                                    the source address is on dm_addr
                                    this clock (io_ws_i is its io_ws);
                                    by the WAIT phase the address is
                                    gone.  C charges the full io_ws
                                    for a dm read (io_read).
                                    */
                                    dm_rd_ws_q <= io_ws_i;
                                    dm_wait_q <= 1'b1;
                                end else if (dm_ack) begin
                                    /*
                                    The ack pulse lands in the cycle
                                    right after the request, and the
                                    read data is valid with it (the mem
                                    agent holds o_dm_rdata after the
                                    accept edge).  Latch the data here:
                                    moving to WAIT first would spend
                                    the ack cycle on the transition and
                                    WAIT would wait forever on a pulse
                                    that already passed (the OP_ADDR
                                    path catches the ack in this same
                                    cycle; the LOOP RD phase did not).
                                    Slow reads (host-window / IO, ack
                                    still low) fall through to WAIT.
                                    */
                                    loop_d_q  <= dm_rdata;
                                    dm_wait_q <= 1'b0;
                                    /*
                                    Per-iteration dm-read wait states
                                    (C io_read): the full io_ws of the
                                    source read, latched in the RD phase.
                                    */
                                    cyc_acc_q <= cyc_acc_q + {12'd0, dm_rd_ws_q};
                                    if (loop_needs_pm_w)
                                        loop_ph_q <= 3'd3;
                                    else
                                        loop_ph_q <= 3'd4;
                                end else begin
                                    loop_ph_q <= 3'd2;
                                end
                            end
                            3'd2: begin /* WAIT: latch the read data. */
                                if (loop_src_is_pm_w) begin
                                    loop_d_q  <= pm_d_rdata;
                                    if (loop_needs_pm_w)
                                        loop_ph_q <= 3'd3;
                                    else
                                        loop_ph_q <= 3'd4;
                                end else if (dm_ack) begin
                                    loop_d_q  <= dm_rdata;
                                    dm_wait_q <= 1'b0;
                                    /*
                                    Per-iteration dm-read wait states
                                    (C io_read): the full io_ws of the
                                    source read, latched in the RD phase.
                                    */
                                    cyc_acc_q <= cyc_acc_q + {12'd0, dm_rd_ws_q};
                                    if (loop_needs_pm_w)
                                        loop_ph_q <= 3'd3;
                                    else
                                        loop_ph_q <= 3'd4;
                                end
                                /*
                                Else: stay in WAIT until dm_ack.
                                */
                            end
                            3'd3: begin /* PM: pm_d_addr presented; the */
                                        /*
                                        data is valid in WR.
                                        */
                                loop_ph_q <= 3'd4;
                            end
                            3'd4: begin /* WR: execute. */
                                /*
                                The dm-write wait-state charge moved to
                                NEXT with the write (see there): in WR
                                loop_dm_wr_w is low now, so there is
                                nothing to charge here.
                                */
                                /*
                                MADS/MADD need no TREG phase any more:
                                the WR phase issued OP_LT_NM, which
                                loaded TREG0 (no mirror) together with
                                ACC and PREG, so every kind goes to
                                NEXT from here.
                                */
                                loop_ph_q <= 3'd5; /* NEXT */
                            end
                            3'd5: begin /* NEXT: decrement and loop / finish. */
                                /*
                                The dm-write wait states (moved here with
                                the write): mmr_bus +1 for a dm write to
                                a peripheral MMR, plus the dm-write wait
                                states (C io_write): io_ws-1 when io_ws
                                > 1.  The write is presented this clock
                                (loop_dm_wr_w), so io_ws_i is its io_ws.
                                The two terms are exclusive (IO space
                                versus 0x20-0x4F), and a second
                                assignment to cyc_acc_q here would
                                override the first.
                                */
                                if (loop_dm_wr_w) begin
                                    cyc_acc_q <= cyc_acc_q +
                                                 ((mmr_wr_hit) ? 16'd1 : 16'd0) +
                                                 ((io_ws_i > 4'd1) ?
                                                  ({12'd0, io_ws_i} - 16'd1) :
                                                  16'd0);
                                end
                                loop_pfc_q <= loop_pfc_q + 16'd1;
                                /*
                                rptc_dec_en is asserted combinationally
                                in this phase (output block).
                                */
                                if (loop_cnt_q > 32'd1) begin
                                    loop_cnt_q <= loop_cnt_q - 32'd1;
                                    if (loop_kind_q == 4'd0 ||
                                        loop_kind_q == 4'd1)
                                        loop_ph_q <= 3'd1; /* RD (ea fixed) */
                                    else
                                        loop_ph_q <= 3'd0; /* EA */
                                end else begin
                                    loop_cnt_q <= 32'd0;
                                    state_q    <= FSM_TICK;
                                    tick_to_done_q <= 1'b0;
                                end
                            end
                            default: begin
                                state_q <= FSM_TAIL;
                            end
                        endcase
                    end
                    FSM_IO_WAIT: begin
                        if (io_ack_c) begin
                            /*
                            IN adds io_ws; OUT adds (io_ws>1 ? io_ws-1:0).
                            */
                            if (!ex_io_wr)
                                cyc_acc_q <= cyc_acc_q + {12'd0, io_ws_i} +
                                             ((mmr_wr_hit) ? 16'd1 : 16'd0);
                            else if (io_ws_i > 4'd1)
                                cyc_acc_q <= cyc_acc_q + {12'd0, io_ws_i} - 16'd1;
                            /*
                            The IN dm write was presented this clock
                            (combinational in IO_WAIT); the mmr_bus +1
                            above covers a write to a peripheral MMR.
                            The OUT needs no further action.  io_rep
                            advances on a repeat (rep_cont), else it is
                            cleared.
                            */
                            if (rep_cont_q)
                                io_rep_q <= io_rep_q + 16'd1;
                            else
                                io_rep_q <= 16'd0;
                            state_q <= FSM_TICK;
                            tick_to_done_q <= 1'b0;
                        end
                        /*
                        Else: hold the request until io_ack_c.
                        */
                    end
                    FSM_TICK: begin
                        /*
                        Drain one timer tick per clock.  Each tick
                        advances cycles_q by 1 (the timer in the mem
                        agent advances on the mtick_en pulse).  When
                        the accumulator is empty, go to TAIL (normal
                        path, so the interrupt check sees the
                        up-to-date IFR) or DONE (INT path).
                        */
                        if (tick_fast_w) begin
                            cyc_acc_q <= 16'd0;
                            cycles_q  <= cycles_q + {48'd0, cyc_acc_q};
                            state_q   <= tick_to_done_q ? FSM_DONE : FSM_TAIL;
                        end else if (cyc_acc_q != 16'd0) begin
                            cyc_acc_q <= cyc_acc_q - 16'd1;
                            cycles_q  <= cycles_q + 64'd1;
                        end else if (tick_to_done_q) begin
                            state_q <= FSM_DONE;
                        end else begin
                            state_q <= FSM_TAIL;
                        end
                    end
                    FSM_TAIL: begin
                        /*
                        The ndx_commit pulse and the C/OV writeback are
                        combinational in TAIL (see the output block).
                        The rptc/brcr strobes are combinational too.
                        XC window update.
                        */
                        if (xc_new_q) begin
                            xc_new_q <= 1'b0;
                        end else if (xc_left_q != 2'd0) begin
                            xc_left_q <= xc_left_after_w;
                        end
                        /*
                        handle_rpt / handle_braf (the strobes are
                        combinational; here only rep_cont_q is latched).
                        */
                        rep_cont_q <= rep_cont_after_w;
                        /*
                        Delay-slot completion: pop the entry, perform
                        the branch action, and re-enter TAIL so the
                        outer instruction's tail work (RPT/BRAF/
                        interrupt, on the outer ppc) runs next clock.
                        */
                        if (in_slot_q && slot_done_w) begin
                            ds_sp_q   <= ds_sp_q - 2'd1;
                            in_slot_q <= (ds_sp_q > 2'd1);
                            /*
                            Restore the outer instruction's ppc so the
                            next TAIL's handle_rpt uses the branch's
                            PC, not the slot word's.
                            */
                            ppc_q     <= ds_ppc_q[ds_sp_q - 2'd1];
                            case (ds_kind_q[ds_sp_q - 2'd1])
                                3'd0: pc_q <= ds_tgt_q[ds_sp_q - 2'd1];
                                3'd1: pc_q <= ds_tgt_q[ds_sp_q - 2'd1];
                                3'd2: pc_q <= pop_data;
                                3'd3: pc_q <= ds_tgt_q[ds_sp_q - 2'd1];
                                3'd4: pc_q <= ds_tgt_q[ds_sp_q - 2'd1];
                                default: begin end
                            endcase
                            /*
                            handle_braf rewind (pc=pasr) must not
                            override the branch target: the branch
                            action above wins (it is assigned after
                            the handle_braf pc assignment in this
                            block -- see the note in the header).
                            */
                            state_q <= FSM_TAIL;
                        end else if (in_slot_q) begin
                            /*
                            More slot words to fetch.
                            */
                            state_q <= FSM_FETCH_ADDR;
                        end else begin
                            /*
                            handle_braf rewind (C handle_braf).
                            */
                            if (stat_braf && ((pc_q - 16'd1) == paer_i) &&
                                (brcr_i != 32'd0))
                                pc_q <= pasr_i;
                            /*
                            handle_rpt rewind (C handle_rpt).
                            */
                            if (rpt_rewind_w)
                                pc_q <= rpt_start_q;
                            /*
                            Interrupt decision (C c5x_run tail), on the
                            POST-tail rptc / rep_cont.
                            */
                            if (int_inh_q) begin
                                int_inh_q <= 1'b0;
                                state_q   <= FSM_DONE;
                            end else if (xc_hold_w) begin
                                state_q <= FSM_DONE;
                            end else if ((rptc_after_w == 32'd0) &&
                                         !rep_cont_after_w && !stat_intm &&
                                         ((ifr_i & imr_i) != 16'd0)) begin
                                int_pending_q <= 1'b1;
                                int_idx_q     <= int_sel_w;
                                int_is_intr_q <= 1'b0;
                                int_via_ind_q <= (int_ind_addr_w != 16'd0);
                                int_ph_q      <= 2'd0;
                                state_q       <= FSM_INT;
                            end else begin
                                state_q <= FSM_DONE;
                            end
                        end
                    end
                    FSM_INT: begin
                        case (int_ph_q)
                            2'd0: begin
                                /*
                                Push PC + set intm are combinational.
                                Latch the shadow context and the vector.
                                */
                                sh_acc_q   <= acc_i;
                                sh_accb_q  <= accb_i;
                                sh_preg_q  <= preg_i;
                                sh_treg0_q <= treg0_i;
                                sh_treg1_q <= treg1_i;
                                sh_treg2_q <= treg2_i;
                                sh_arcr_q  <= arcr_i;
                                sh_indx_q  <= indx_i;
                                sh_arp_q   <= stat_arp;
                                sh_arb_q   <= stat_arb;
                                sh_dp_q    <= stat_dp;
                                sh_ov_q    <= stat_ov;
                                sh_ovm_q   <= stat_ovm;
                                sh_cnf_q   <= stat_cnf;
                                sh_tc_q    <= stat_tc;
                                sh_sxm_q   <= stat_sxm;
                                sh_c_q     <= stat_c;
                                sh_hm_q    <= stat_hm;
                                sh_pm_q    <= stat_pm;
                                sh_iptr_q  <= stat_iptr;
                                sh_avis_q  <= pmst_i[7];
                                sh_ovly_q  <= pmst_i[5];
                                sh_ram_q   <= pmst_i[4];
                                sh_mpmc_q  <= pmst_i[3];
                                sh_ndx_q   <= pmst_i[2];
                                sh_trm_q   <= pmst_i[1];
                                sh_braf_q  <= pmst_i[0];
                                /*
                                The vector: ivec_ind redirect or
                                IPTR-relative.  For INTR, int_vec_q was
                                set at the EXEC edge; for an external
                                interrupt, compute it here.  The redirect
                                decision uses the combinational
                                int_ind_addr_w (the nonblocking
                                int_via_ind_q update is not visible yet).
                                */
                                if (!int_is_intr_q) begin
                                    int_vec_q <= {stat_iptr, 3'b000,
                                                  c5x_ivec(int_idx_q)};
                                    int_via_ind_q <= (int_ind_addr_w != 16'd0);
                                end
                                if (int_is_intr_q ? int_via_ind_q :
                                    (int_ind_addr_w != 16'd0))
                                    int_ph_q <= 2'd1;
                                else
                                    int_ph_q <= 2'd2;
                            end
                            2'd1: begin
                                /*
                                dm read of ivec_ind[i].
                                */
                                if (!dm_wait_q) begin
                                    dm_wait_q <= 1'b1;
                                end else if (dm_ack) begin
                                    int_vec_q <= dm_rdata;
                                    dm_wait_q <= 1'b0;
                                    /*
                                    Host-window ivec_ind read charges
                                    io_ws (C dm_rd -> io_read).
                                    */
                                    if (int_ind_addr_w >= 16'hFF50 &&
                                        int_ind_addr_w <= 16'hFF5F)
                                        cyc_acc_q <= cyc_acc_q + {12'd0, io_ws_i};
                                    int_ph_q <= 2'd2;
                                end
                            end
                            2'd2: begin
                                pc_q <= int_vec_q;
                                /*
                                External-interrupt entry costs 4 cycles;
                                INTR costs only its own cyctab cycles.
                                */
                                if (!int_is_intr_q)
                                    cyc_acc_q <= cyc_acc_q + 16'd4;
                                int_pending_q <= 1'b0;
                                int_idle_q    <= 1'b0;
                                state_q <= FSM_TICK;
                                tick_to_done_q <= 1'b1;
                            end
                            default: begin
                                state_q <= FSM_DONE;
                            end
                        endcase
                    end
                    FSM_DONE: begin
                        /*
                        cycles_q was advanced during TICK; cyc_acc_q
                        is already 0.  instr_done is combinational.
                        */
                        alu_used_q <= 1'b0;
                        if (badop_q) begin
                            state_q <= FSM_BADOP;
                        end else if (idle_next_q != 2'd0) begin
                            idle_q      <= idle_next_q;
                            idle_next_q <= 2'd0;
                            state_q     <= FSM_IDLE;
                        end else if (!step_i) begin
                            /*
                            Single-step park: hold DONE until the
                            harness pulses step_i high.  No cycles
                            advance and no timer ticks fire here, so
                            parking is cycle-neutral; instr_done stays
                            high while parked (it is a level, high
                            throughout DONE).  With step_i tied high
                            this branch never runs and the path is
                            identical to before.  The top level must
                            drive step_i (tie high for normal runs).
                            */
                            state_q <= FSM_DONE;
                        end else begin
                            state_q <= FSM_FETCH_DATA;   /* pm_addr = pc_q is already presented in DONE: the next opcode is read here (no FETCH_ADDR clock) */
                        end
                    end
                    FSM_IDLE: begin
                        cycles_q <= cycles_q + {56'd0, idle_inc_w};
                        /*
                        Wake on any unmasked interrupt (IDLE) or only
                        INT1-INT4 (IDLE2, mask 0x0107).
                        */
                        if (idle_q == 2'd2) begin
                            if (((ifr_i & imr_i) & 16'h0107) != 16'd0) begin
                                idle_q        <= 2'd0;
                                int_idle_q    <= 1'b1;
                                int_pending_q <= 1'b1;
                                int_idx_q     <= int_sel_w;
                                int_is_intr_q <= 1'b0;
                                int_ph_q      <= 2'd0;
                                state_q       <= FSM_INT;
                            end
                        end else begin
                            if ((ifr_i & imr_i) != 16'd0) begin
                                idle_q        <= 2'd0;
                                int_idle_q    <= 1'b1;
                                int_pending_q <= 1'b1;
                                int_idx_q     <= int_sel_w;
                                int_is_intr_q <= 1'b0;
                                int_ph_q      <= 2'd0;
                                state_q       <= FSM_INT;
                            end
                        end
                    end
                    FSM_BADOP: begin
                        /*
                        Halted.  The C model returns RUN_BADOP.
                        */
                        state_q <= FSM_BADOP;
                    end
                    FSM_RESTORE: begin
                        if (rst_ph_q < 4'd8) begin
                            rst_ph_q <= rst_ph_q + 4'd1;
                        end else begin
                            /*
                            Restore done.  RETE clears INTM (the
                            st_bit for it was asserted in phase 8).
                            */
                            rst_ph_q <= 4'd0;
                            state_q  <= FSM_TICK;
                            tick_to_done_q <= 1'b0;
                        end
                    end
                    default: begin
                        state_q <= FSM_RESET;
                    end
                endcase
            end
        
        end
    end

endmodule

`default_nettype wire
