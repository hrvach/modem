/*
tb_c5x_decode.sv -- directed + exhaustive testbench for c5x_decode.
Function: proves the decoder against the C spec for every opcode.
Talks to: c5x_decode (the DUT); c5x_ctl_pkg (ALU op enum, cycle
  table); c5x_cyctab.h (the independent cycle reference, generated
  into ref_cycles below).
Does not model: the control FSM, the ALU, the address unit, memory
  (those are agent 5's co-sim); cycle-count adjustments the ctrl
  applies on top of the decoder's base count (class-1/class-2
  taken/not-taken, IN/OUT wait states, interrupt entry).
Source: research_notes/courier-firmware/c-port/c/src/dsp/c5x_core.c
  (exec1_op dispatch ladder, exec_hi_* families, exec_be/exec_bf)
  and c5x_cyctab.h (cycle counts).
Method: directed vectors carry hand-computed expected values (one
  per major group, plus edge cases); the exhaustive section then
  checks all 65536 opcodes against reference functions written
  from the same C spec (ref_cycles is generated from the C header
  file, the rest are a second transcription of the dispatch).
  A mismatch prints FAIL with got/expected and ends $fatal(1).
Run (from workspace/goals/tms320c5x-dsp-core-on-fpga/):
  verilator --binary -j --top-module tb_c5x_decode \
    tb/tb_c5x_decode.sv rtl/c5x_decode.sv rtl/c5x_ctl_pkg.sv
  ./obj_dir/Vtb_c5x_decode
*/

`default_nettype none

module tb_c5x_decode;

    import c5x_ctl_pkg::*;

    /*
    Expected-flag pack, bit per class flag (same order as the
    DUT outputs are assembled in the check task below):
    [8] branch [7] call [6] ret [5] rpt [4] rptb [3] idle
    [2] io [1] mem_wr [0] pm_wr.
    */
    localparam logic [8:0] FLG_NONE   = 9'b000000000;
    localparam logic [8:0] FLG_BRANCH = 9'b100000000;
    localparam logic [8:0] FLG_CALL   = 9'b010000000;
    localparam logic [8:0] FLG_RET    = 9'b001000000;
    localparam logic [8:0] FLG_RPT    = 9'b000100000;
    localparam logic [8:0] FLG_RPTB   = 9'b000010000;
    localparam logic [8:0] FLG_IDLE   = 9'b000001000;
    localparam logic [8:0] FLG_IO     = 9'b000000100;
    localparam logic [8:0] FLG_MEMWR  = 9'b000000010;
    localparam logic [8:0] FLG_PMWR   = 9'b000000001;

    logic        clk;
    logic        rst_n;
    logic [15:0] instr_i;
    logic [15:0] instr2_i;
    logic [6:0]  alu_op_o;
    logic [1:0]  words_o;
    logic [7:0]  cycles_o;
    logic [7:0]  ea_mode_o;
    logic        is_branch_o;
    logic        is_call_o;
    logic        is_ret_o;
    logic        is_rpt_o;
    logic        is_rptb_o;
    logic        is_idle_o;
    logic        is_io_o;
    logic        is_mem_wr_o;
    logic        is_pm_wr_o;
    logic        badop_o;

    integer      checks_passed;
    integer      checks_failed;

    c5x_decode u_decode (
        .clk        (clk),
        .rst_n      (rst_n),
        .instr_i    (instr_i),
        .instr2_i   (instr2_i),
        .alu_op_o   (alu_op_o),
        .words_o    (words_o),
        .cycles_o   (cycles_o),
        .ea_mode_o  (ea_mode_o),
        .is_branch_o (is_branch_o),
        .is_call_o  (is_call_o),
        .is_ret_o   (is_ret_o),
        .is_rpt_o   (is_rpt_o),
        .is_rptb_o  (is_rptb_o),
        .is_idle_o  (is_idle_o),
        .is_io_o    (is_io_o),
        .is_mem_wr_o (is_mem_wr_o),
        .is_pm_wr_o (is_pm_wr_o),
        .badop_o    (badop_o)
    );

    always begin
        #5;
        clk <= ~clk;
    end

    /*
    check: drive one opcode, wait for the combinational decode to
    settle, compare every output. ea_mode_o is always the low byte
    of the opcode (the addressing-mode bits), so it is checked
    against op[7:0] directly, not passed in.
    */
    task automatic check(input logic [15:0] op,
                         input logic [6:0] exp_alu_op,
                         input logic [1:0] exp_words,
                         input logic [7:0] exp_cycles,
                         input logic [8:0] exp_flags,
                         input logic exp_badop);
        logic [8:0] got_flags;
        begin
            instr_i = op;
            #1;
            got_flags = {is_branch_o, is_call_o, is_ret_o,
                         is_rpt_o, is_rptb_o, is_idle_o,
                         is_io_o, is_mem_wr_o, is_pm_wr_o};
            if (alu_op_o !== exp_alu_op ||
                words_o !== exp_words ||
                cycles_o !== exp_cycles ||
                ea_mode_o !== op[7:0] ||
                got_flags !== exp_flags ||
                badop_o !== exp_badop) begin
                checks_failed = checks_failed + 1;
                $display("FAIL op=%h alu_op got=%0d exp=%0d words got=%0d exp=%0d cycles got=%0d exp=%0d",
                         op, alu_op_o, exp_alu_op, words_o, exp_words,
                         cycles_o, exp_cycles);
                $display("     ea got=%h exp=%h flags got=%b exp=%b badop got=%b exp=%b",
                         ea_mode_o, op[7:0], got_flags, exp_flags,
                         badop_o, exp_badop);
                $fatal(1, "tb_c5x_decode: mismatch, see FAIL lines above");
            end
            checks_passed = checks_passed + 1;
        end
    endtask

    /*
    check_ref: same as check, but the expected values come from the
    reference functions (used by the random and exhaustive sections).
    */
    task automatic check_ref(input logic [15:0] op);
        begin
            check(op, ref_alu_op(op), ref_words(op), ref_cycles(op),
                  ref_flags(op), ref_badop(op));
        end
    endtask

    /*
    Directed vectors. Expected values are hand-computed from the C
    spec (exec1 dispatch in c5x_core.c, cycle counts in
    c5x_cyctab.h), not copied from the RTL. Groups follow the task
    brief: arithmetic, logical, MPY, shift, branch/call/return with
    and without delay slots, repeat, IO, IDLE, interrupt-related,
    plus illegal opcodes.
    */
    task automatic directed_vectors;
        begin
            /* Arithmetic (exec_hi 0x10-0x3F, 0x60-0x67, 0xB8-0xBA). */
            check(16'h2000, ALU_ADD_SH, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h6100, ALU_ADD, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h6000, ALU_ADDC, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h3000, ALU_SUB_SH, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h6400, ALU_SUBB, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hB800, ALU_ADD, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBA00, ALU_SUB, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h1000, ALU_LD_EXT, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h6A00, ALU_LD_B16HI, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h6B05, ALU_LACT, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h6300, ALU_ADDT, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h6700, ALU_SUBT, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h6900, ALU_LD_B16Z, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h6800, ALU_LD_ZALR, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hB900, ALU_LD_B16Z, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBF90, ALU_ADD_SH, 2'd2, 8'd2, FLG_NONE, 1'b0);
            check(16'hBFA0, ALU_SUB_SH, 2'd2, 8'd2, FLG_NONE, 1'b0);
            check(16'hBF80, ALU_LD_EXT, 2'd2, 8'd2, FLG_NONE, 1'b0);

            /* Logical (0x6C-0x6F, 0x58-0x5B, 0x5C-0x5F, 0xBE8x). */
            check(16'h6E00, ALU_AND, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h6D00, ALU_OR, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h6C00, ALU_XOR, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h4000, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h6F00, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h5800, ALU_XOR, 2'd1, 8'd1, FLG_MEMWR, 1'b0);
            check(16'h5900, ALU_OR, 2'd1, 8'd1, FLG_MEMWR, 1'b0);
            check(16'h5A00, ALU_AND, 2'd1, 8'd1, FLG_MEMWR, 1'b0);
            check(16'h5B00, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h5C00, ALU_XOR, 2'd2, 8'd2, FLG_MEMWR, 1'b0);
            check(16'h5D00, ALU_OR, 2'd2, 8'd2, FLG_MEMWR, 1'b0);
            check(16'h5E00, ALU_AND, 2'd2, 8'd2, FLG_MEMWR, 1'b0);
            check(16'h5F00, ALU_NOP, 2'd2, 8'd2, FLG_NONE, 1'b0);
            check(16'hBE81, ALU_AND, 2'd2, 8'd2, FLG_NONE, 1'b0);
            check(16'hBE82, ALU_OR, 2'd2, 8'd2, FLG_NONE, 1'b0);
            check(16'hBE83, ALU_XOR, 2'd2, 8'd2, FLG_NONE, 1'b0);
            check(16'hBFB0, ALU_AND, 2'd2, 8'd2, FLG_NONE, 1'b0);
            check(16'hBFC0, ALU_OR, 2'd2, 8'd2, FLG_NONE, 1'b0);
            check(16'hBFD0, ALU_XOR, 2'd2, 8'd2, FLG_NONE, 1'b0);

            /* MPY (0x50-0x55, 0xC0-0xDF, 0xBE80). */
            check(16'h5400, ALU_MPY, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h5500, ALU_MPYU, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h5000, ALU_MPYA, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h5100, ALU_MPYS, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h5200, ALU_SQRA, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h5300, ALU_SQRS, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hC000, ALU_MPY, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE80, ALU_MPY, 2'd2, 8'd2, FLG_NONE, 1'b0);

            /* Shift (SFTA, NORM, SATH/SATL). */
            check(16'hBFE3, ALU_SFTA, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hA000, ALU_NORM, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE5A, ALU_SATH, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE5B, ALU_SATL, 2'd1, 8'd1, FLG_NONE, 1'b0);

            /* Branch / call / return, no delay slot. */
            check(16'h7900, ALU_NOP, 2'd2, 8'd4, FLG_BRANCH, 1'b0);
            check(16'h7A00, ALU_NOP, 2'd2, 8'd4, FLG_CALL, 1'b0);
            check(16'h7B00, ALU_NOP, 2'd2, 8'd1, FLG_BRANCH, 1'b0);
            check(16'h7B80, ALU_NOP, 2'd2, 8'd4, FLG_BRANCH, 1'b0);
            check(16'hE000, ALU_NOP, 2'd2, 8'd4, FLG_BRANCH, 1'b0);
            check(16'hE800, ALU_NOP, 2'd2, 8'd4, FLG_CALL, 1'b0);
            check(16'hEC00, ALU_NOP, 2'd1, 8'd2, FLG_RET, 1'b0);
            check(16'hEF00, ALU_NOP, 2'd1, 8'd4, FLG_RET, 1'b0);
            check(16'hEF01, ALU_NOP, 2'd1, 8'd2, FLG_RET, 1'b0);
            check(16'hBE20, ALU_NOP, 2'd1, 8'd4, FLG_BRANCH, 1'b0);
            check(16'hBE30, ALU_NOP, 2'd1, 8'd4, FLG_CALL, 1'b0);
            check(16'hBE38, ALU_NOP, 2'd1, 8'd4, FLG_RET, 1'b0);
            check(16'hBE3A, ALU_NOP, 2'd1, 8'd4, FLG_RET, 1'b0);

            /* Branch / call / return, with delay slot. */
            check(16'h7D00, ALU_NOP, 2'd2, 8'd2, FLG_BRANCH, 1'b0);
            check(16'h7E00, ALU_NOP, 2'd2, 8'd2, FLG_CALL, 1'b0);
            check(16'h7F00, ALU_NOP, 2'd2, 8'd2, FLG_BRANCH, 1'b0);
            check(16'hBE21, ALU_NOP, 2'd1, 8'd2, FLG_BRANCH, 1'b0);
            check(16'hF800, ALU_NOP, 2'd2, 8'd2, FLG_CALL, 1'b0);
            check(16'hFC00, ALU_NOP, 2'd1, 8'd2, FLG_RET, 1'b0);
            check(16'hBE3D, ALU_NOP, 2'd1, 8'd2, FLG_CALL, 1'b0);

            /* Repeat (RPT forms, RPTZ, RPTB). */
            check(16'h0B00, ALU_NOP, 2'd1, 8'd1, FLG_RPT, 1'b0);
            check(16'hBB05, ALU_NOP, 2'd1, 8'd2, FLG_RPT, 1'b0);
            check(16'hBEC4, ALU_NOP, 2'd2, 8'd2, FLG_RPT, 1'b0);
            check(16'hBEC5, ALU_ACC_PREG_ZERO, 2'd2, 8'd2, FLG_RPT, 1'b0);
            check(16'hBEC6, ALU_NOP, 2'd2, 8'd2, FLG_RPTB, 1'b0);

            /* IO (IN, OUT). */
            check(16'hAF00, ALU_NOP, 2'd2, 8'd2, FLG_IO | FLG_MEMWR, 1'b0);
            check(16'h0C00, ALU_NOP, 2'd2, 8'd3, FLG_IO, 1'b0);

            /* IDLE / IDLE2. */
            check(16'hBE22, ALU_NOP, 2'd1, 8'd1, FLG_IDLE, 1'b0);
            check(16'hBE23, ALU_NOP, 2'd1, 8'd1, FLG_IDLE, 1'b0);

            /* Interrupt-related (INTR, TRAP, NMI, EINT, DINT). */
            check(16'hBE60, ALU_NOP, 2'd1, 8'd4, FLG_NONE, 1'b0);
            check(16'hBE7F, ALU_NOP, 2'd1, 8'd4, FLG_NONE, 1'b0);
            check(16'hBE51, ALU_NOP, 2'd1, 8'd4, FLG_NONE, 1'b0);
            check(16'hBE52, ALU_NOP, 2'd1, 8'd4, FLG_NONE, 1'b0);
            check(16'hBE40, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE41, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b0);

            /* Illegal opcodes (C RUN_BADOP). */
            check(16'h5600, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b1);
            check(16'hA100, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b1);
            check(16'hBE06, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b1);
            check(16'hBE50, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b1);
            check(16'hBF04, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b1);
            check(16'hBF10, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b1);
            check(16'hBEFF, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b1);

            /* Loads / stores / moves / misc. */
            check(16'h0000, ALU_NOP, 2'd1, 8'd2, FLG_NONE, 1'b0);
            check(16'hB000, ALU_NOP, 2'd1, 8'd2, FLG_NONE, 1'b0);
            check(16'hBF08, ALU_NOP, 2'd2, 8'd2, FLG_NONE, 1'b0);
            check(16'h0800, ALU_LD_B16Z, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h0900, ALU_NOP, 2'd2, 8'd2, FLG_MEMWR, 1'b0);
            check(16'h0A00, ALU_SUBC, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h0D00, ALU_NOP, 2'd1, 8'd2, FLG_NONE, 1'b0);
            check(16'hBC00, ALU_NOP, 2'd1, 8'd2, FLG_NONE, 1'b0);
            check(16'h0E00, ALU_NOP, 2'd1, 8'd2, FLG_NONE, 1'b0);
            check(16'h0F00, ALU_NOP, 2'd1, 8'd2, FLG_NONE, 1'b0);
            check(16'h7000, ALU_LTA, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h7100, ALU_LTP, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h7200, ALU_LTD, 2'd1, 8'd1, FLG_MEMWR, 1'b0);
            check(16'h7300, ALU_LT, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h7400, ALU_LTS, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h7500, ALU_LPH, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h7600, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h7700, ALU_NOP, 2'd1, 8'd1, FLG_MEMWR, 1'b0);
            check(16'h7800, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h7C00, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h8000, ALU_NOP, 2'd1, 8'd1, FLG_MEMWR, 1'b0);
            check(16'h8800, ALU_NOP, 2'd1, 8'd1, FLG_MEMWR, 1'b0);
            check(16'h8900, ALU_NOP, 2'd2, 8'd2, FLG_MEMWR, 1'b0);
            check(16'h8A00, ALU_NOP, 2'd1, 8'd1, FLG_MEMWR, 1'b0);
            check(16'h8B00, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'h8C00, ALU_NOP, 2'd1, 8'd1, FLG_MEMWR, 1'b0);
            check(16'h8D00, ALU_NOP, 2'd1, 8'd1, FLG_MEMWR, 1'b0);
            check(16'h8E00, ALU_NOP, 2'd1, 8'd1, FLG_MEMWR, 1'b0);
            check(16'h9000, ALU_NOP, 2'd1, 8'd1, FLG_MEMWR, 1'b0);
            check(16'h9800, ALU_NOP, 2'd1, 8'd1, FLG_MEMWR, 1'b0);
            check(16'hA200, ALU_APAC, 2'd2, 8'd3, FLG_NONE, 1'b0);
            check(16'hA300, ALU_APAC, 2'd2, 8'd3, FLG_MEMWR, 1'b0);
            check(16'hA400, ALU_NOP, 2'd1, 8'd2, FLG_MEMWR, 1'b0);
            check(16'hA500, ALU_NOP, 2'd2, 8'd3, FLG_MEMWR, 1'b0);
            check(16'hA600, ALU_NOP, 2'd1, 8'd3, FLG_MEMWR, 1'b0);
            check(16'hA700, ALU_NOP, 2'd1, 8'd3, FLG_PMWR, 1'b0);
            check(16'hA800, ALU_NOP, 2'd2, 8'd3, FLG_MEMWR, 1'b0);
            check(16'hAC00, ALU_NOP, 2'd1, 8'd2, FLG_MEMWR, 1'b0);
            check(16'hAA00, ALU_APAC, 2'd1, 8'd2, FLG_NONE, 1'b0);
            check(16'hAB00, ALU_APAC, 2'd1, 8'd2, FLG_MEMWR, 1'b0);
            check(16'hAE00, ALU_NOP, 2'd2, 8'd2, FLG_MEMWR, 1'b0);
            check(16'h5700, ALU_NOP, 2'd1, 8'd2, FLG_PMWR, 1'b0);

            /* 0xBE accumulator ops. */
            check(16'hBE00, ALU_ABS, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE01, ALU_CMPL, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE02, ALU_NEG, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE03, ALU_PAC, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE04, ALU_APAC, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE05, ALU_SPAC, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE09, ALU_ROL, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE0A, ALU_ROR, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE0C, ALU_ROLC, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE0D, ALU_RORC, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE10, ALU_ADD_B, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE11, ALU_ADDC_B, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE12, ALU_AND_B, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE13, ALU_OR_B, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE14, ALU_ROLB, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE15, ALU_RORB, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE16, ALU_SFLB, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE17, ALU_SFRB, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE18, ALU_SUB_B, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE19, ALU_SBBB, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE1A, ALU_XOR_B, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE1B, ALU_MAX, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE1C, ALU_MIN, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE1D, ALU_SWAP, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE1E, ALU_SACB, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE1F, ALU_LACB, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE32, ALU_LD_B16Z, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE3C, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE58, ALU_PREG_ZERO, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBE59, ALU_ACC_PREG_ZERO, 2'd1, 8'd1, FLG_NONE, 1'b0);

            /* 0xBF sub-decoder. */
            check(16'hBF00, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b0);
            check(16'hBF44, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b0);

            /* XC (conditional execute, no flag). */
            check(16'hE400, ALU_NOP, 2'd1, 8'd1, FLG_NONE, 1'b0);
        end
    endtask

    /*
    ref_cycles: base cycle count from c5x_cyctab.h, generated
    from the C header file (NOT from the package function
    c5x_cyctab, so a transcription slip in either copy is
    caught by the exhaustive section). Source:
      research_notes/courier-firmware/c-port/c/src/dsp/c5x_cyctab.h
    */
    /*
    ref_cycles: base cycle count from c5x_cyctab.h, generated
    from the C header file (NOT from the package function
    c5x_cyctab, so a transcription slip in either copy is
    caught by the exhaustive section). Source:
      research_notes/courier-firmware/c-port/c/src/dsp/c5x_cyctab.h
    */
    function automatic [7:0] ref_cycles(input logic [15:0] op);
        logic [7:0] hi;
        logic [7:0] lo;
        begin
            hi = op[15:8];
            lo = op[7:0];
            case (hi)
                8'h00: ref_cycles = 8'd2;
                8'h01: ref_cycles = 8'd2;
                8'h02: ref_cycles = 8'd2;
                8'h03: ref_cycles = 8'd2;
                8'h04: ref_cycles = 8'd2;
                8'h05: ref_cycles = 8'd2;
                8'h06: ref_cycles = 8'd2;
                8'h07: ref_cycles = 8'd2;
                8'h08: ref_cycles = 8'd1;
                8'h09: ref_cycles = 8'd2;
                8'h0A: ref_cycles = 8'd1;
                8'h0B: ref_cycles = 8'd1;
                8'h0C: ref_cycles = 8'd3;
                8'h0D: ref_cycles = 8'd2;
                8'h0E: ref_cycles = 8'd2;
                8'h0F: ref_cycles = 8'd2;
                8'h10: ref_cycles = 8'd1;
                8'h11: ref_cycles = 8'd1;
                8'h12: ref_cycles = 8'd1;
                8'h13: ref_cycles = 8'd1;
                8'h14: ref_cycles = 8'd1;
                8'h15: ref_cycles = 8'd1;
                8'h16: ref_cycles = 8'd1;
                8'h17: ref_cycles = 8'd1;
                8'h18: ref_cycles = 8'd1;
                8'h19: ref_cycles = 8'd1;
                8'h1A: ref_cycles = 8'd1;
                8'h1B: ref_cycles = 8'd1;
                8'h1C: ref_cycles = 8'd1;
                8'h1D: ref_cycles = 8'd1;
                8'h1E: ref_cycles = 8'd1;
                8'h1F: ref_cycles = 8'd1;
                8'h20: ref_cycles = 8'd1;
                8'h21: ref_cycles = 8'd1;
                8'h22: ref_cycles = 8'd1;
                8'h23: ref_cycles = 8'd1;
                8'h24: ref_cycles = 8'd1;
                8'h25: ref_cycles = 8'd1;
                8'h26: ref_cycles = 8'd1;
                8'h27: ref_cycles = 8'd1;
                8'h28: ref_cycles = 8'd1;
                8'h29: ref_cycles = 8'd1;
                8'h2A: ref_cycles = 8'd1;
                8'h2B: ref_cycles = 8'd1;
                8'h2C: ref_cycles = 8'd1;
                8'h2D: ref_cycles = 8'd1;
                8'h2E: ref_cycles = 8'd1;
                8'h2F: ref_cycles = 8'd1;
                8'h30: ref_cycles = 8'd1;
                8'h31: ref_cycles = 8'd1;
                8'h32: ref_cycles = 8'd1;
                8'h33: ref_cycles = 8'd1;
                8'h34: ref_cycles = 8'd1;
                8'h35: ref_cycles = 8'd1;
                8'h36: ref_cycles = 8'd1;
                8'h37: ref_cycles = 8'd1;
                8'h38: ref_cycles = 8'd1;
                8'h39: ref_cycles = 8'd1;
                8'h3A: ref_cycles = 8'd1;
                8'h3B: ref_cycles = 8'd1;
                8'h3C: ref_cycles = 8'd1;
                8'h3D: ref_cycles = 8'd1;
                8'h3E: ref_cycles = 8'd1;
                8'h3F: ref_cycles = 8'd1;
                8'h40: ref_cycles = 8'd1;
                8'h41: ref_cycles = 8'd1;
                8'h42: ref_cycles = 8'd1;
                8'h43: ref_cycles = 8'd1;
                8'h44: ref_cycles = 8'd1;
                8'h45: ref_cycles = 8'd1;
                8'h46: ref_cycles = 8'd1;
                8'h47: ref_cycles = 8'd1;
                8'h48: ref_cycles = 8'd1;
                8'h49: ref_cycles = 8'd1;
                8'h4A: ref_cycles = 8'd1;
                8'h4B: ref_cycles = 8'd1;
                8'h4C: ref_cycles = 8'd1;
                8'h4D: ref_cycles = 8'd1;
                8'h4E: ref_cycles = 8'd1;
                8'h4F: ref_cycles = 8'd1;
                8'h50: ref_cycles = 8'd1;
                8'h51: ref_cycles = 8'd1;
                8'h52: ref_cycles = 8'd1;
                8'h53: ref_cycles = 8'd1;
                8'h54: ref_cycles = 8'd1;
                8'h55: ref_cycles = 8'd1;
                8'h56: ref_cycles = 8'd1;
                8'h57: ref_cycles = 8'd2;
                8'h58: ref_cycles = 8'd1;
                8'h59: ref_cycles = 8'd1;
                8'h5A: ref_cycles = 8'd1;
                8'h5B: ref_cycles = 8'd1;
                8'h5C: ref_cycles = 8'd2;
                8'h5D: ref_cycles = 8'd2;
                8'h5E: ref_cycles = 8'd2;
                8'h5F: ref_cycles = 8'd2;
                8'h60: ref_cycles = 8'd1;
                8'h61: ref_cycles = 8'd1;
                8'h62: ref_cycles = 8'd1;
                8'h63: ref_cycles = 8'd1;
                8'h64: ref_cycles = 8'd1;
                8'h65: ref_cycles = 8'd1;
                8'h66: ref_cycles = 8'd1;
                8'h67: ref_cycles = 8'd1;
                8'h68: ref_cycles = 8'd1;
                8'h69: ref_cycles = 8'd1;
                8'h6A: ref_cycles = 8'd1;
                8'h6B: ref_cycles = 8'd1;
                8'h6C: ref_cycles = 8'd1;
                8'h6D: ref_cycles = 8'd1;
                8'h6E: ref_cycles = 8'd1;
                8'h6F: ref_cycles = 8'd1;
                8'h70: ref_cycles = 8'd1;
                8'h71: ref_cycles = 8'd1;
                8'h72: ref_cycles = 8'd1;
                8'h73: ref_cycles = 8'd1;
                8'h74: ref_cycles = 8'd1;
                8'h75: ref_cycles = 8'd1;
                8'h76: ref_cycles = 8'd1;
                8'h77: ref_cycles = 8'd1;
                8'h78: ref_cycles = 8'd1;
                8'h79: ref_cycles = 8'd4;
                8'h7A: ref_cycles = 8'd4;
                8'h7B: begin
                    case (lo) inside
                        [8'h00:8'h7F]: ref_cycles = 8'd1;
                        [8'h80:8'hFF]: ref_cycles = 8'd4;
                        default: ref_cycles = 8'd0;
                    endcase
                end
                8'h7C: ref_cycles = 8'd1;
                8'h7D: ref_cycles = 8'd2;
                8'h7E: ref_cycles = 8'd2;
                8'h7F: ref_cycles = 8'd2;
                8'h80: ref_cycles = 8'd1;
                8'h81: ref_cycles = 8'd1;
                8'h82: ref_cycles = 8'd1;
                8'h83: ref_cycles = 8'd1;
                8'h84: ref_cycles = 8'd1;
                8'h85: ref_cycles = 8'd1;
                8'h86: ref_cycles = 8'd1;
                8'h87: ref_cycles = 8'd1;
                8'h88: ref_cycles = 8'd1;
                8'h89: ref_cycles = 8'd2;
                8'h8A: ref_cycles = 8'd1;
                8'h8B: ref_cycles = 8'd1;
                8'h8C: ref_cycles = 8'd1;
                8'h8D: ref_cycles = 8'd1;
                8'h8E: ref_cycles = 8'd1;
                8'h8F: ref_cycles = 8'd1;
                8'h90: ref_cycles = 8'd1;
                8'h91: ref_cycles = 8'd1;
                8'h92: ref_cycles = 8'd1;
                8'h93: ref_cycles = 8'd1;
                8'h94: ref_cycles = 8'd1;
                8'h95: ref_cycles = 8'd1;
                8'h96: ref_cycles = 8'd1;
                8'h97: ref_cycles = 8'd1;
                8'h98: ref_cycles = 8'd1;
                8'h99: ref_cycles = 8'd1;
                8'h9A: ref_cycles = 8'd1;
                8'h9B: ref_cycles = 8'd1;
                8'h9C: ref_cycles = 8'd1;
                8'h9D: ref_cycles = 8'd1;
                8'h9E: ref_cycles = 8'd1;
                8'h9F: ref_cycles = 8'd1;
                8'hA0: ref_cycles = 8'd1;
                8'hA1: ref_cycles = 8'd1;
                8'hA2: ref_cycles = 8'd3;
                8'hA3: ref_cycles = 8'd3;
                8'hA4: ref_cycles = 8'd2;
                8'hA5: ref_cycles = 8'd3;
                8'hA6: ref_cycles = 8'd3;
                8'hA7: ref_cycles = 8'd3;
                8'hA8: ref_cycles = 8'd3;
                8'hA9: ref_cycles = 8'd3;
                8'hAA: ref_cycles = 8'd2;
                8'hAB: ref_cycles = 8'd2;
                8'hAC: ref_cycles = 8'd2;
                8'hAD: ref_cycles = 8'd2;
                8'hAE: ref_cycles = 8'd2;
                8'hAF: ref_cycles = 8'd2;
                8'hB0: ref_cycles = 8'd2;
                8'hB1: ref_cycles = 8'd2;
                8'hB2: ref_cycles = 8'd2;
                8'hB3: ref_cycles = 8'd2;
                8'hB4: ref_cycles = 8'd2;
                8'hB5: ref_cycles = 8'd2;
                8'hB6: ref_cycles = 8'd2;
                8'hB7: ref_cycles = 8'd2;
                8'hB8: ref_cycles = 8'd1;
                8'hB9: ref_cycles = 8'd1;
                8'hBA: ref_cycles = 8'd1;
                8'hBB: ref_cycles = 8'd2;
                8'hBC: ref_cycles = 8'd2;
                8'hBD: ref_cycles = 8'd2;
                8'hBE: begin
                    case (lo) inside
                        [8'h00:8'h1F]: ref_cycles = 8'd1;
                        8'h20: ref_cycles = 8'd4;
                        8'h21: ref_cycles = 8'd2;
                        [8'h22:8'h2F]: ref_cycles = 8'd1;
                        8'h30: ref_cycles = 8'd4;
                        [8'h31:8'h37]: ref_cycles = 8'd1;
                        8'h38: ref_cycles = 8'd4;
                        8'h39: ref_cycles = 8'd1;
                        8'h3A: ref_cycles = 8'd4;
                        [8'h3B:8'h3C]: ref_cycles = 8'd1;
                        8'h3D: ref_cycles = 8'd2;
                        [8'h3E:8'h50]: ref_cycles = 8'd1;
                        [8'h51:8'h52]: ref_cycles = 8'd4;
                        [8'h53:8'h5F]: ref_cycles = 8'd1;
                        [8'h60:8'h7F]: ref_cycles = 8'd4;
                        [8'h80:8'h83]: ref_cycles = 8'd2;
                        [8'h84:8'hC3]: ref_cycles = 8'd1;
                        [8'hC4:8'hC6]: ref_cycles = 8'd2;
                        [8'hC7:8'hFF]: ref_cycles = 8'd1;
                        default: ref_cycles = 8'd0;
                    endcase
                end
                8'hBF: begin
                    case (lo) inside
                        [8'h00:8'h07]: ref_cycles = 8'd1;
                        [8'h08:8'h0F]: ref_cycles = 8'd2;
                        [8'h10:8'h7F]: ref_cycles = 8'd1;
                        [8'h80:8'hDF]: ref_cycles = 8'd2;
                        [8'hE0:8'hFF]: ref_cycles = 8'd1;
                        default: ref_cycles = 8'd0;
                    endcase
                end
                8'hC0: ref_cycles = 8'd1;
                8'hC1: ref_cycles = 8'd1;
                8'hC2: ref_cycles = 8'd1;
                8'hC3: ref_cycles = 8'd1;
                8'hC4: ref_cycles = 8'd1;
                8'hC5: ref_cycles = 8'd1;
                8'hC6: ref_cycles = 8'd1;
                8'hC7: ref_cycles = 8'd1;
                8'hC8: ref_cycles = 8'd1;
                8'hC9: ref_cycles = 8'd1;
                8'hCA: ref_cycles = 8'd1;
                8'hCB: ref_cycles = 8'd1;
                8'hCC: ref_cycles = 8'd1;
                8'hCD: ref_cycles = 8'd1;
                8'hCE: ref_cycles = 8'd1;
                8'hCF: ref_cycles = 8'd1;
                8'hD0: ref_cycles = 8'd1;
                8'hD1: ref_cycles = 8'd1;
                8'hD2: ref_cycles = 8'd1;
                8'hD3: ref_cycles = 8'd1;
                8'hD4: ref_cycles = 8'd1;
                8'hD5: ref_cycles = 8'd1;
                8'hD6: ref_cycles = 8'd1;
                8'hD7: ref_cycles = 8'd1;
                8'hD8: ref_cycles = 8'd1;
                8'hD9: ref_cycles = 8'd1;
                8'hDA: ref_cycles = 8'd1;
                8'hDB: ref_cycles = 8'd1;
                8'hDC: ref_cycles = 8'd1;
                8'hDD: ref_cycles = 8'd1;
                8'hDE: ref_cycles = 8'd1;
                8'hDF: ref_cycles = 8'd1;
                8'hE0: ref_cycles = 8'd4;
                8'hE1: ref_cycles = 8'd4;
                8'hE2: ref_cycles = 8'd4;
                8'hE3: ref_cycles = 8'd4;
                8'hE4: ref_cycles = 8'd1;
                8'hE5: ref_cycles = 8'd1;
                8'hE6: ref_cycles = 8'd1;
                8'hE7: ref_cycles = 8'd1;
                8'hE8: ref_cycles = 8'd4;
                8'hE9: ref_cycles = 8'd4;
                8'hEA: ref_cycles = 8'd4;
                8'hEB: ref_cycles = 8'd4;
                8'hEC: ref_cycles = 8'd2;
                8'hED: ref_cycles = 8'd2;
                8'hEE: ref_cycles = 8'd2;
                8'hEF: begin
                    case (lo) inside
                        8'h00: ref_cycles = 8'd4;
                        [8'h01:8'hFF]: ref_cycles = 8'd2;
                        default: ref_cycles = 8'd0;
                    endcase
                end
                8'hF0: ref_cycles = 8'd2;
                8'hF1: ref_cycles = 8'd2;
                8'hF2: ref_cycles = 8'd2;
                8'hF3: ref_cycles = 8'd2;
                8'hF4: ref_cycles = 8'd1;
                8'hF5: ref_cycles = 8'd1;
                8'hF6: ref_cycles = 8'd1;
                8'hF7: ref_cycles = 8'd1;
                8'hF8: ref_cycles = 8'd2;
                8'hF9: ref_cycles = 8'd2;
                8'hFA: ref_cycles = 8'd2;
                8'hFB: ref_cycles = 8'd2;
                8'hFC: ref_cycles = 8'd2;
                8'hFD: ref_cycles = 8'd2;
                8'hFE: ref_cycles = 8'd2;
                8'hFF: ref_cycles = 8'd2;
                default: ref_cycles = 8'd0;
            endcase
        end
    endfunction

    /*
    ref_words: instruction length in words, from the 2-word list in
    the C dispatch (exec1 fetches a second word for these opcodes).
    */
    function automatic [1:0] ref_words(input logic [15:0] op);
        logic [7:0] hi;
        logic [7:0] lo;
        begin
            hi = op[15:8];
            lo = op[7:0];
            case (hi)
                8'h09, 8'h0C, 8'h5C, 8'h5D, 8'h5E, 8'h5F,
                8'h79, 8'h7A, 8'h7B, 8'h7D, 8'h7E, 8'h7F,
                8'h89, 8'hA2, 8'hA3, 8'hA5, 8'hA8, 8'hA9,
                8'hAE, 8'hAF, 8'hE0, 8'hE1, 8'hE2, 8'hE3,
                8'hE8, 8'hE9, 8'hEA, 8'hEB, 8'hF0, 8'hF1,
                8'hF2, 8'hF3, 8'hF8, 8'hF9, 8'hFA, 8'hFB:
                    ref_words = 2'd2;
                8'hBE: begin
                    case (lo)
                        8'h80, 8'h81, 8'h82, 8'h83,
                        8'hC4, 8'hC5, 8'hC6:
                            ref_words = 2'd2;
                        default:
                            ref_words = 2'd1;
                    endcase
                end
                8'hBF: begin
                    if ((lo >= 8'h08 && lo <= 8'h0F) ||
                        (lo >= 8'h80 && lo <= 8'hDF))
                        ref_words = 2'd2;
                    else
                        ref_words = 2'd1;
                end
                default:
                    ref_words = 2'd1;
            endcase
        end
    endfunction

    /*
    ref_badop_be: the 0xBE low-byte legality (exec_be_acc /
    exec_be_ctrl). INTR is (lo & 0xE0) == 0x60.
    */
    function automatic ref_badop_be(input logic [7:0] lo);
        begin
            if (lo < 8'h20) begin
                case (lo)
                    8'h06, 8'h07, 8'h08, 8'h0B, 8'h0E, 8'h0F:
                        ref_badop_be = 1'b1;
                    default:
                        ref_badop_be = 1'b0;
                endcase
            end else begin
                case (lo)
                    8'h20, 8'h21, 8'h22, 8'h23, 8'h30, 8'h32,
                    8'h38, 8'h3A, 8'h3C, 8'h3D, 8'h40, 8'h41,
                    8'h42, 8'h43, 8'h44, 8'h45, 8'h46, 8'h47,
                    8'h48, 8'h49, 8'h4A, 8'h4B, 8'h4C, 8'h4D,
                    8'h4E, 8'h4F, 8'h51, 8'h52, 8'h58, 8'h59,
                    8'h5A, 8'h5B, 8'h80, 8'h81, 8'h82, 8'h83,
                    8'hC4, 8'hC5, 8'hC6:
                        ref_badop_be = 1'b0;
                    default:
                        ref_badop_be = ((lo & 8'hE0) != 8'h60);
                endcase
            end
        end
    endfunction

    /*
    ref_badop: illegal opcode (C RUN_BADOP). 0x56 and 0xA1 are
    unconditionally illegal; 0xBE / 0xBF go through their
    sub-decoders.
    */
    function automatic ref_badop(input logic [15:0] op);
        logic [7:0] hi;
        logic [7:0] lo;
        begin
            hi = op[15:8];
            lo = op[7:0];
            if (hi == 8'h56 || hi == 8'hA1)
                ref_badop = 1'b1;
            else if (hi == 8'hBE)
                ref_badop = ref_badop_be(lo);
            else if (hi == 8'hBF)
                ref_badop = !((lo <= 8'h03) ||
                              (lo >= 8'h08 && lo <= 8'h0F) ||
                              (lo >= 8'h44 && lo <= 8'h47) ||
                              (lo >= 8'h80 && lo <= 8'hDF) ||
                              (lo >= 8'hE0 && lo <= 8'hEF));
            else
                ref_badop = 1'b0;
        end
    endfunction

    /*
    ref_flags: the nine class flags, same pack order as FLG_*.
    Each flag is an independent condition on the opcode.
    */
    function automatic [8:0] ref_flags(input logic [15:0] op);
        logic [7:0] hi;
        logic [7:0] lo;
        logic [8:0] flags;
        begin
            hi = op[15:8];
            lo = op[7:0];
            flags = 9'd0;
            if (hi == 8'h79 || hi == 8'h7B || hi == 8'h7D ||
                hi == 8'h7F ||
                (hi >= 8'hE0 && hi <= 8'hE3) ||
                (hi >= 8'hF0 && hi <= 8'hF3) ||
                (hi == 8'hBE && (lo == 8'h20 || lo == 8'h21)))
                flags[8] = 1'b1;
            if (hi == 8'h7A || hi == 8'h7E ||
                (hi >= 8'hE8 && hi <= 8'hEB) ||
                (hi >= 8'hF8 && hi <= 8'hFB) ||
                (hi == 8'hBE && (lo == 8'h30 || lo == 8'h3D)))
                flags[7] = 1'b1;
            if ((hi >= 8'hEC && hi <= 8'hEF) ||
                (hi >= 8'hFC) ||
                (hi == 8'hBE && (lo == 8'h38 || lo == 8'h3A)))
                flags[6] = 1'b1;
            if (hi == 8'h0B || hi == 8'hBB ||
                (hi == 8'hBE && (lo == 8'hC4 || lo == 8'hC5)))
                flags[5] = 1'b1;
            if (hi == 8'hBE && lo == 8'hC6)
                flags[4] = 1'b1;
            if (hi == 8'hBE && (lo == 8'h22 || lo == 8'h23))
                flags[3] = 1'b1;
            if (hi == 8'h0C || hi == 8'hAF)
                flags[2] = 1'b1;
            if (hi == 8'h09 || hi == 8'h58 || hi == 8'h59 ||
                hi == 8'h5A || hi == 8'h5C || hi == 8'h5D ||
                hi == 8'h5E || hi == 8'h72 || hi == 8'h77 ||
                (hi >= 8'h80 && hi <= 8'h87) || hi == 8'h88 ||
                hi == 8'h89 || hi == 8'h8A || hi == 8'h8C ||
                hi == 8'h8D || hi == 8'h8E || hi == 8'h8F ||
                (hi >= 8'h90 && hi <= 8'h9F) || hi == 8'hA3 ||
                hi == 8'hA4 || hi == 8'hA5 || hi == 8'hA6 ||
                hi == 8'hA8 || hi == 8'hA9 || hi == 8'hAB ||
                hi == 8'hAC || hi == 8'hAD || hi == 8'hAE ||
                hi == 8'hAF)
                flags[1] = 1'b1;
            if (hi == 8'h57 || hi == 8'hA7)
                flags[0] = 1'b1;
            ref_flags = flags;
        end
    endfunction

    /*
    ref_alu_op: the micro-op per opcode, a second transcription of
    the C exec1 dispatch (exec_hi_* families, exec_be, exec_bf).
    */
    function automatic [6:0] ref_alu_op(input logic [15:0] op);
        logic [7:0] hi;
        logic [7:0] lo;
        begin
            hi = op[15:8];
            lo = op[7:0];
            case (hi)
                8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06,
                8'h07, 8'h09, 8'h0B, 8'h0C, 8'h0D, 8'h0E, 8'h0F,
                8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h46,
                8'h47, 8'h48, 8'h49, 8'h4A, 8'h4B, 8'h4C, 8'h4D,
                8'h4E, 8'h4F, 8'h56, 8'h57, 8'h5B, 8'h5F, 8'h6F,
                8'h76, 8'h77, 8'h78, 8'h79, 8'h7A, 8'h7B, 8'h7C,
                8'h7D, 8'h7E, 8'h7F, 8'h80, 8'h81, 8'h82, 8'h83,
                8'h84, 8'h85, 8'h86, 8'h87, 8'h88, 8'h89, 8'h8A,
                8'h8B, 8'h8C, 8'h8D, 8'h8E, 8'h8F, 8'h90, 8'h91,
                8'h92, 8'h93, 8'h94, 8'h95, 8'h96, 8'h97, 8'h98,
                8'h99, 8'h9A, 8'h9B, 8'h9C, 8'h9D, 8'h9E, 8'h9F,
                8'hA1, 8'hA4, 8'hA5, 8'hA6, 8'hA7, 8'hA8, 8'hA9,
                8'hAC, 8'hAD, 8'hAE, 8'hAF, 8'hB0, 8'hB1, 8'hB2,
                8'hB3, 8'hB4, 8'hB5, 8'hB6, 8'hB7, 8'hBB, 8'hBC,
                8'hBD, 8'hE0, 8'hE1, 8'hE2, 8'hE3, 8'hE4, 8'hE5,
                8'hE6, 8'hE7, 8'hE8, 8'hE9, 8'hEA, 8'hEB, 8'hEC,
                8'hED, 8'hEE, 8'hEF, 8'hF0, 8'hF1, 8'hF2, 8'hF3,
                8'hF4, 8'hF5, 8'hF6, 8'hF7, 8'hF8, 8'hF9, 8'hFA,
                8'hFB, 8'hFC, 8'hFD, 8'hFE, 8'hFF:
                    ref_alu_op = ALU_NOP;
                8'h08: ref_alu_op = ALU_LD_B16Z;
                8'h0A: ref_alu_op = ALU_SUBC;
                8'h10, 8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16,
                8'h17, 8'h18, 8'h19, 8'h1A, 8'h1B, 8'h1C, 8'h1D,
                8'h1E, 8'h1F:
                    ref_alu_op = ALU_LD_EXT;
                8'h20, 8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26,
                8'h27, 8'h28, 8'h29, 8'h2A, 8'h2B, 8'h2C, 8'h2D,
                8'h2E, 8'h2F:
                    ref_alu_op = ALU_ADD_SH;
                8'h30, 8'h31, 8'h32, 8'h33, 8'h34, 8'h35, 8'h36,
                8'h37, 8'h38, 8'h39, 8'h3A, 8'h3B, 8'h3C, 8'h3D,
                8'h3E, 8'h3F:
                    ref_alu_op = ALU_SUB_SH;
                8'h50: ref_alu_op = ALU_MPYA;
                8'h51: ref_alu_op = ALU_MPYS;
                8'h52: ref_alu_op = ALU_SQRA;
                8'h53: ref_alu_op = ALU_SQRS;
                8'h54: ref_alu_op = ALU_MPY;
                8'h55: ref_alu_op = ALU_MPYU;
                8'h58, 8'h5C: ref_alu_op = ALU_XOR;
                8'h59, 8'h5D: ref_alu_op = ALU_OR;
                8'h5A, 8'h5E: ref_alu_op = ALU_AND;
                8'h60: ref_alu_op = ALU_ADDC;
                8'h61, 8'h62: ref_alu_op = ALU_ADD;
                8'h63: ref_alu_op = ALU_ADDT;
                8'h64: ref_alu_op = ALU_SUBB;
                8'h65, 8'h66: ref_alu_op = ALU_SUB;
                8'h67: ref_alu_op = ALU_SUBT;
                8'h68: ref_alu_op = ALU_LD_ZALR;
                8'h69: ref_alu_op = ALU_LD_B16Z;
                8'h6A: ref_alu_op = ALU_LD_B16HI;
                8'h6B: ref_alu_op = ALU_LACT;
                8'h6C: ref_alu_op = ALU_XOR;
                8'h6D: ref_alu_op = ALU_OR;
                8'h6E: ref_alu_op = ALU_AND;
                8'h70: ref_alu_op = ALU_LTA;
                8'h71: ref_alu_op = ALU_LTP;
                8'h72: ref_alu_op = ALU_LTD;
                8'h73: ref_alu_op = ALU_LT;
                8'h74: ref_alu_op = ALU_LTS;
                8'h75: ref_alu_op = ALU_LPH;
                8'hA0: ref_alu_op = ALU_NORM;
                8'hA2, 8'hA3, 8'hAA, 8'hAB:
                    ref_alu_op = ALU_APAC;
                8'hB8: ref_alu_op = ALU_ADD;
                8'hB9: ref_alu_op = ALU_LD_B16Z;
                8'hBA: ref_alu_op = ALU_SUB;
                8'hBE: ref_alu_op = ref_alu_op_be(lo);
                8'hBF: ref_alu_op = ref_alu_op_bf(lo);
                8'hC0, 8'hC1, 8'hC2, 8'hC3, 8'hC4, 8'hC5, 8'hC6,
                8'hC7, 8'hC8, 8'hC9, 8'hCA, 8'hCB, 8'hCC, 8'hCD,
                8'hCE, 8'hCF, 8'hD0, 8'hD1, 8'hD2, 8'hD3, 8'hD4,
                8'hD5, 8'hD6, 8'hD7, 8'hD8, 8'hD9, 8'hDA, 8'hDB,
                8'hDC, 8'hDD, 8'hDE, 8'hDF:
                    ref_alu_op = ALU_MPY;
                default: ref_alu_op = ALU_NOP;
            endcase
        end
    endfunction

    /*
    ref_alu_op_be: the 0xBE sub-decoder (exec_be_acc / exec_be_ctrl).
    */
    function automatic [6:0] ref_alu_op_be(input logic [7:0] lo);
        begin
            if (lo < 8'h20) begin
                case (lo)
                    8'h00: ref_alu_op_be = ALU_ABS;
                    8'h01: ref_alu_op_be = ALU_CMPL;
                    8'h02: ref_alu_op_be = ALU_NEG;
                    8'h03: ref_alu_op_be = ALU_PAC;
                    8'h04: ref_alu_op_be = ALU_APAC;
                    8'h05: ref_alu_op_be = ALU_SPAC;
                    8'h09: ref_alu_op_be = ALU_ROL;
                    8'h0A: ref_alu_op_be = ALU_ROR;
                    8'h0C: ref_alu_op_be = ALU_ROLC;
                    8'h0D: ref_alu_op_be = ALU_RORC;
                    8'h10: ref_alu_op_be = ALU_ADD_B;
                    8'h11: ref_alu_op_be = ALU_ADDC_B;
                    8'h12: ref_alu_op_be = ALU_AND_B;
                    8'h13: ref_alu_op_be = ALU_OR_B;
                    8'h14: ref_alu_op_be = ALU_ROLB;
                    8'h15: ref_alu_op_be = ALU_RORB;
                    8'h16: ref_alu_op_be = ALU_SFLB;
                    8'h17: ref_alu_op_be = ALU_SFRB;
                    8'h18: ref_alu_op_be = ALU_SUB_B;
                    8'h19: ref_alu_op_be = ALU_SBBB;
                    8'h1A: ref_alu_op_be = ALU_XOR_B;
                    8'h1B: ref_alu_op_be = ALU_MAX;
                    8'h1C: ref_alu_op_be = ALU_MIN;
                    8'h1D: ref_alu_op_be = ALU_SWAP;
                    8'h1E: ref_alu_op_be = ALU_SACB;
                    8'h1F: ref_alu_op_be = ALU_LACB;
                    default: ref_alu_op_be = ALU_NOP;
                endcase
            end else begin
                case (lo)
                    8'h32: ref_alu_op_be = ALU_LD_B16Z;
                    8'h58: ref_alu_op_be = ALU_PREG_ZERO;
                    8'h59: ref_alu_op_be = ALU_ACC_PREG_ZERO;
                    8'h5A: ref_alu_op_be = ALU_SATH;
                    8'h5B: ref_alu_op_be = ALU_SATL;
                    8'h80: ref_alu_op_be = ALU_MPY;
                    8'h81: ref_alu_op_be = ALU_AND;
                    8'h82: ref_alu_op_be = ALU_OR;
                    8'h83: ref_alu_op_be = ALU_XOR;
                    8'hC5: ref_alu_op_be = ALU_ACC_PREG_ZERO;
                    default: ref_alu_op_be = ALU_NOP;
                endcase
            end
        end
    endfunction

    /*
    ref_alu_op_bf: the 0xBF sub-decoder (exec_bf). Only the
    long-immediate ALU forms and SFTA use the ALU.
    */
    function automatic [6:0] ref_alu_op_bf(input logic [7:0] lo);
        begin
            if (lo >= 8'h80 && lo <= 8'hDF) begin
                case (lo[7:4])
                    4'h8: ref_alu_op_bf = ALU_LD_EXT;
                    4'h9: ref_alu_op_bf = ALU_ADD_SH;
                    4'hA: ref_alu_op_bf = ALU_SUB_SH;
                    4'hB: ref_alu_op_bf = ALU_AND;
                    4'hC: ref_alu_op_bf = ALU_OR;
                    4'hD: ref_alu_op_bf = ALU_XOR;
                    default: ref_alu_op_bf = ALU_NOP;
                endcase
            end else if (lo >= 8'hE0 && lo <= 8'hEF) begin
                ref_alu_op_bf = ALU_SFTA;
            end else begin
                ref_alu_op_bf = ALU_NOP;
            end
        end
    endfunction

    integer random_index;
    integer exhaustive_index;
    logic [15:0] random_op;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        instr_i = 16'd0;
        instr2_i = 16'd0;
        checks_passed = 0;
        checks_failed = 0;
        #20;
        rst_n = 1'b1;
        #1;

        /* instr2_i is ignored by the decode; prove it once. */
        instr2_i = 16'hFFFF;
        directed_vectors();
        instr2_i = 16'd0;

        /* Random section (golden-rule equivalence proof): 1024
           random opcodes against the reference functions. */
        for (random_index = 0; random_index < 1024; random_index = random_index + 1) begin
            random_op = 16'($random); /* low 16 bits of the random word */
            check_ref(random_op);
        end
        $display("tb_c5x_decode: random section done, %0d checks passed", checks_passed);

        /* Exhaustive section: every 16-bit opcode. */
        for (exhaustive_index = 0; exhaustive_index < 65536; exhaustive_index = exhaustive_index + 1) begin
            check_ref(exhaustive_index[15:0]);
        end
        $display("tb_c5x_decode: PASS, %0d checks passed, %0d failed", checks_passed, checks_failed);
        $finish;
    end

endmodule

`default_nettype wire
