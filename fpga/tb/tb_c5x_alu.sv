/*
tb_c5x_alu.sv -- directed + swept testbench for c5x_alu.

Run (from workspace/goals/tms320c5x-dsp-core-on-fpga/):
  Build and run with: verilator --binary -j --top-module tb_c5x_alu tb/tb_c5x_alu.sv rtl/c5x_alu.sv
  ./obj_dir/Vtb_c5x_alu
Every check cites its source: the C function + line in
research_notes/courier-firmware/c-port/c/src/dsp/c5x_core.c, or the
audit section in research_notes/courier-firmware/c5x_core_audit/.
Golden vectors were computed by hand and cross-checked with Python
(see the arithmetic in the comments); the swept section compares
the RTL against independent reference functions written from the
same C formulas. A failure prints FAIL with got/expected and the
run ends $fatal(1); a clean run prints the pass count and $finish.

Op encodings must match rtl/c5x_alu.sv localparams exactly.
*/

`timescale 1ns/1ps
`default_nettype none

module tb_c5x_alu;

    localparam logic [6:0] OP_NOP           = 7'd0;
    localparam logic [6:0] OP_ADD           = 7'd1;
    localparam logic [6:0] OP_ADDC          = 7'd2;
    localparam logic [6:0] OP_SUB           = 7'd3;
    localparam logic [6:0] OP_SUBB          = 7'd4;
    localparam logic [6:0] OP_SBBB          = 7'd5;
    localparam logic [6:0] OP_ADD_B         = 7'd6;
    localparam logic [6:0] OP_ADDC_B        = 7'd7;
    localparam logic [6:0] OP_SUB_B         = 7'd8;
    localparam logic [6:0] OP_AND           = 7'd9;
    localparam logic [6:0] OP_OR            = 7'd10;
    localparam logic [6:0] OP_XOR           = 7'd11;
    localparam logic [6:0] OP_AND_B         = 7'd12;
    localparam logic [6:0] OP_OR_B          = 7'd13;
    localparam logic [6:0] OP_XOR_B         = 7'd14;
    localparam logic [6:0] OP_ADD_SH        = 7'd15;
    localparam logic [6:0] OP_SUB_SH        = 7'd16;
    localparam logic [6:0] OP_ADDT          = 7'd17;
    localparam logic [6:0] OP_SUBT          = 7'd18;
    localparam logic [6:0] OP_LD_EXT        = 7'd19;
    localparam logic [6:0] OP_LACT          = 7'd20;
    localparam logic [6:0] OP_LD_B32        = 7'd21;
    localparam logic [6:0] OP_LD_B16Z       = 7'd22;
    localparam logic [6:0] OP_LD_B16HI      = 7'd23;
    localparam logic [6:0] OP_LD_ZALR       = 7'd24;
    localparam logic [6:0] OP_NEG           = 7'd25;
    localparam logic [6:0] OP_ABS           = 7'd26;
    localparam logic [6:0] OP_CMPL          = 7'd27;
    localparam logic [6:0] OP_MAX           = 7'd28;
    localparam logic [6:0] OP_MIN           = 7'd29;
    localparam logic [6:0] OP_SWAP          = 7'd30;
    localparam logic [6:0] OP_SACB          = 7'd31;
    localparam logic [6:0] OP_LACB          = 7'd32;
    localparam logic [6:0] OP_SUBC          = 7'd33;
    localparam logic [6:0] OP_PAC           = 7'd34;
    localparam logic [6:0] OP_APAC          = 7'd35;
    localparam logic [6:0] OP_SPAC          = 7'd36;
    localparam logic [6:0] OP_MPYA          = 7'd37;
    localparam logic [6:0] OP_MPYS          = 7'd38;
    localparam logic [6:0] OP_SQRA          = 7'd39;
    localparam logic [6:0] OP_SQRS          = 7'd40;
    localparam logic [6:0] OP_LTA           = 7'd41;
    localparam logic [6:0] OP_LTP           = 7'd42;
    localparam logic [6:0] OP_LTD           = 7'd43;
    localparam logic [6:0] OP_LTS           = 7'd44;
    localparam logic [6:0] OP_LT            = 7'd45;
    localparam logic [6:0] OP_MPY           = 7'd46;
    localparam logic [6:0] OP_MPYU          = 7'd47;
    localparam logic [6:0] OP_LPH           = 7'd48;
    localparam logic [6:0] OP_PREG_ZERO     = 7'd49;
    localparam logic [6:0] OP_ACC_ZERO      = 7'd50;
    localparam logic [6:0] OP_ACC_PREG_ZERO = 7'd51;
    localparam logic [6:0] OP_ROL           = 7'd52;
    localparam logic [6:0] OP_ROR           = 7'd53;
    localparam logic [6:0] OP_ROLC          = 7'd54;
    localparam logic [6:0] OP_RORC          = 7'd55;
    localparam logic [6:0] OP_SFLB          = 7'd56;
    localparam logic [6:0] OP_SFRB          = 7'd57;
    localparam logic [6:0] OP_ROLB          = 7'd58;
    localparam logic [6:0] OP_RORB          = 7'd59;
    localparam logic [6:0] OP_SFTA          = 7'd60;
    localparam logic [6:0] OP_SATH          = 7'd61;
    localparam logic [6:0] OP_SATL          = 7'd62;
    localparam logic [6:0] OP_NORM          = 7'd63;
    localparam logic [6:0] OP_LT_NM         = 7'd64;

    logic        clk = 1'b0;
    logic        rst_n = 1'b0;
    logic        exec = 1'b0;
    logic        ld_acc = 1'b0;
    logic        ld_accb = 1'b0;
    logic        ld_preg = 1'b0;
    logic        ld_treg0 = 1'b0;
    logic [6:0]  op = OP_NOP;
    logic [31:0] b32 = 32'b0;
    logic [15:0] b16 = 16'b0;
    logic [15:0] mpy_a = 16'b0;
    logic [15:0] mpy_b = 16'b0;
    logic        mpy_unsigned = 1'b0;
    logic [3:0]  shift = 4'b0;
    logic        s16 = 1'b0;
    logic        sxm = 1'b1;
    logic        ovm = 1'b0;
    logic [1:0]  pm = 2'b0;
    logic        trm = 1'b0;
    logic        flag_c_we = 1'b0;
    logic        flag_c_in = 1'b0;
    logic        flag_ov_we = 1'b0;
    logic        flag_ov_in = 1'b0;

    logic [31:0] acc, accb, preg;
    logic [15:0] treg0, treg1, treg2;
    logic        c_flag, ov_flag;
    logic [31:0] pscale, ext_out, b16_shl, shl_acc, mpy_out;
    logic [31:0] acc_next;
    logic        tc_next, tc_wr;

    c5x_alu dut (
        .clk            (clk),
        .ce_i (1'b1),
        .rst_n          (rst_n),
        .i_exec         (exec),
        .i_ld_acc       (ld_acc),
        .i_ld_accb      (ld_accb),
        .i_ld_preg      (ld_preg),
        .i_ld_treg0     (ld_treg0),
        .i_op           (op),
        .i_b32          (b32),
        .i_b16          (b16),
        .i_mpy_a        (mpy_a),
        .i_mpy_b        (mpy_b),
        .i_mpy_unsigned (mpy_unsigned),
        .i_shift        (shift),
        .i_s16          (s16),
        .i_sxm          (sxm),
        .i_ovm          (ovm),
        .i_pm           (pm),
        .i_trm          (trm),
        .i_flag_c_we    (flag_c_we),
        .i_flag_c_in    (flag_c_in),
        .i_flag_ov_we   (flag_ov_we),
        .i_flag_ov_in   (flag_ov_in),
        .o_acc          (acc),
        .o_accb         (accb),
        .o_preg         (preg),
        .o_treg0        (treg0),
        .o_treg1        (treg1),
        .o_treg2        (treg2),
        .o_c            (c_flag),
        .o_ov           (ov_flag),
        .o_pscale       (pscale),
        .o_ext          (ext_out),
        .o_b16_shl      (b16_shl),
        .o_shl_acc      (shl_acc),
        .o_mpy          (mpy_out),
        .o_tc_next      (tc_next),
        .o_tc_wr        (tc_wr),
        .acc_next       (acc_next)
    );

    always #5 clk = ~clk;

    integer pass_n = 0;
    integer fail_n = 0;

    /* ---- check helpers (src = "C fn:line" or "audit section") ---- */
    task chk32(input string name, input logic [31:0] got,
               input logic [31:0] exp, input string src);
        begin
            if (got !== exp) begin
                fail_n++;
                $display("FAIL %s: got %h exp %h  [%s]", name, got, exp, src);
            end else begin
                pass_n++;
            end
        end
    endtask

    task chk16(input string name, input logic [15:0] got,
               input logic [15:0] exp, input string src);
        begin
            if (got !== exp) begin
                fail_n++;
                $display("FAIL %s: got %h exp %h  [%s]", name, got, exp, src);
            end else begin
                pass_n++;
            end
        end
    endtask

    task chk1(input string name, input logic got,
              input logic exp, input string src);
        begin
            if (got !== exp) begin
                fail_n++;
                $display("FAIL %s: got %b exp %b  [%s]", name, got, exp, src);
            end else begin
                pass_n++;
            end
        end
    endtask

    /*
    One clock with the current inputs; deassert exec afterwards so
    the op cannot re-execute on the next edge. Before the edge,
    sample the combinational acc_next tap: whenever this tick loads
    ACC, the registered ACC after the edge must equal the sampled
    tap, so every micro-op exercised in this testbench also proves
    the acc_next output (the value the ctrl's alu_y will carry).
    */
    task tick;
        logic [31:0] acc_next_sampled;
        logic [6:0] op_sampled;
        logic ld_acc_sampled;
        begin
            ld_acc_sampled = ld_acc;
            op_sampled     = op;
            #1;
            acc_next_sampled = acc_next;
            @(posedge clk);
            #1;
            exec       = 1'b0;
            ld_acc     = 1'b0;
            ld_accb    = 1'b0;
            ld_preg    = 1'b0;
            ld_treg0   = 1'b0;
            flag_c_we  = 1'b0;
            flag_ov_we = 1'b0;
            op         = OP_NOP;
            if (ld_acc_sampled) begin
                chk32($sformatf("acc_next==acc op=%0d", op_sampled),
                      acc, acc_next_sampled, "acc_next tap");
            end
        end
    endtask

    /* Execute one micro-op with the given load enables. */
    task run_op(input logic [6:0] o, input logic la, input logic lb,
                input logic lp, input logic lt);
        begin
            op       = o;
            ld_acc   = la;
            ld_accb  = lb;
            ld_preg  = lp;
            ld_treg0 = lt;
            exec     = 1'b1;
            tick;
        end
    endtask

    /* Convenience setters (each is one executed micro-op). */
    task set_acc(input logic [31:0] v);
        begin
            b32 = v;
            run_op(OP_LD_B32, 1'b1, 1'b0, 1'b0, 1'b0);
        end
    endtask

    task set_accb(input logic [31:0] v);
        begin
            set_acc(v);
            run_op(OP_SACB, 1'b0, 1'b1, 1'b0, 1'b0);
        end
    endtask

    task set_treg0(input logic [15:0] v);
        begin
            b16 = v;
            run_op(OP_LT, 1'b0, 1'b0, 1'b0, 1'b1);
        end
    endtask

    task set_c(input logic v);
        begin
            flag_c_we = 1'b1;
            flag_c_in = v;
            @(posedge clk);
            #1;
            flag_c_we = 1'b0;
        end
    endtask

    task clear_ov;
        begin
            flag_ov_we = 1'b1;
            flag_ov_in = 1'b0;
            @(posedge clk);
            #1;
            flag_ov_we = 1'b0;
        end
    endtask

    task set_modes(input logic s, input logic v, input logic [1:0] p,
                   input logic t);
        begin
            sxm = s;
            ovm = v;
            pm  = p;
            trm = t;
        end
    endtask

    /* ---- independent reference functions (from the C formulas) ---- */
    function automatic [32:0] ref_add(input logic [31:0] a,
                                      input logic [31:0] b,
                                      input logic cin);
        ref_add = {1'b0, a} + {1'b0, b} + {32'b0, cin};
    endfunction

    function automatic [32:0] ref_sub(input logic [31:0] a,
                                      input logic [31:0] b,
                                      input logic bin);
        ref_sub = {1'b0, a} - {1'b0, b} - {32'b0, bin};
    endfunction

    function automatic logic ref_add_ovf(input logic [31:0] a,
                                         input logic [31:0] b,
                                         input logic [31:0] r);
        ref_add_ovf = (a[31] ^ r[31]) & (b[31] ^ r[31]);
    endfunction

    function automatic logic ref_sub_ovf(input logic [31:0] a,
                                         input logic [31:0] b,
                                         input logic [31:0] r);
        ref_sub_ovf = (a[31] ^ b[31]) & (a[31] ^ r[31]);
    endfunction

    /* Saturation bounds (do_add/do_sub, c5x_core.c:992-1032). */
    localparam logic [31:0] SAT_POS = 32'h7fffffff;
    localparam logic [31:0] SAT_NEG = 32'h80000000;

    /* pscale() shift amounts by PM mode (c5x_core.c:1034-1045). */
    localparam logic [2:0] PM_SHIFT_ONE = 3'd1;
    localparam logic [2:0] PM_SHIFT_FOUR = 3'd4;
    localparam logic [2:0] PM_SHIFT_SIX = 3'd6;

    /* BSAR/SFTA shifts by sh+1, not sh (KD-1; SFTA, c5x_core.c:2507-2511). */
    localparam logic [4:0] SFTA_SHIFT_BIAS = 5'd1;

    /* Sweep controls: arbitrary nonzero LFSR seed, 200 pseudo-random
       operand pairs, 8 cases per round, 3 logic variants. */
    localparam logic [15:0] LFSR_SEED = 16'hace1;
    localparam integer SWEEP_ITERATIONS = 200;
    localparam integer SWEEP_CASE_COUNT = 8;
    localparam integer LOGIC_VARIANT_COUNT = 3;

    function automatic [31:0] ref_sat(input logic [31:0] r,
                                      input logic ovf, input logic ovmode);
        if (ovf && ovmode) begin
            if (r[31])
                ref_sat = SAT_POS;
            else
                ref_sat = SAT_NEG;
        end else begin
            ref_sat = r;
        end
    endfunction

    function automatic [31:0] ref_ext(input logic [15:0] d,
                                      input logic [3:0] sh,
                                      input logic s);
        if (s)
            ref_ext = {{16{d[15]}}, d} << sh;
        else
            ref_ext = {16'b0, d} << sh;
    endfunction

    function automatic [31:0] ref_pscale(input logic [31:0] p,
                                         input logic [1:0] m);
        case (m)
            2'd0:    ref_pscale = p;
            2'd1:    ref_pscale = p << PM_SHIFT_ONE;
            2'd2:    ref_pscale = p << PM_SHIFT_FOUR;
            default: ref_pscale = $signed(p) >>> PM_SHIFT_SIX;
        endcase
    endfunction

    function automatic [15:0] lfsr_next(input logic [15:0] s);
        lfsr_next = {s[14:0], s[15] ^ s[13] ^ s[12] ^ s[10]};
    endfunction

    /* ---- test sequence ---- */
    initial begin
        /* Reset: c5x_reset, c5x_core.c:425-432. */
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        rst_n = 1'b1;
        #1;
        chk32("reset acc", acc, 32'b0, "c5x_reset :427");
        chk32("reset accb", accb, 32'b0, "c5x_reset :427");
        chk32("reset preg", preg, 32'b0, "c5x_reset :427");
        chk16("reset treg0", treg0, 16'b0, "c5x_reset :428");
        chk16("reset treg1", treg1, 16'b0, "c5x_reset :428");
        chk16("reset treg2", treg2, 16'b0, "c5x_reset :428");
        chk1("reset C=1", c_flag, 1'b1, "c5x_reset :431");
        chk1("reset OV=0", ov_flag, 1'b0, "c5x_reset :430");

        /* ============ ADD / SUB (do_add/do_sub, :992-1032) ============ */
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        s16 = 1'b0;
        /* ADD 5+3=8. audit 07b: ADD dma OBEYS. */
        set_acc(32'd5);
        b32 = 32'd3;
        run_op(OP_ADD, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ADD 5+3", acc, 32'd8, "do_add :992");
        chk1("ADD 5+3 C", c_flag, 1'b0, "do_add :992");
        chk1("ADD 5+3 OV", ov_flag, 1'b0, "do_add :992");
        /* ADD 0xFFFFFFFF+1=0, carry. */
        set_acc(32'hffffffff);
        b32 = 32'd1;
        run_op(OP_ADD, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ADD ffffffff+1", acc, 32'b0, "do_add :992");
        chk1("ADD ffffffff+1 C", c_flag, 1'b1, "do_add :992");
        chk1("ADD ffffffff+1 OV", ov_flag, 1'b0, "do_add :992");
        /* ADD overflow, OVM=0: 0x7fffffff+1=0x80000000, OV set, no sat. */
        set_acc(32'h7fffffff);
        b32 = 32'd1;
        run_op(OP_ADD, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ADD ovf OVM=0", acc, 32'h80000000, "do_add :1004");
        chk1("ADD ovf C", c_flag, 1'b0, "do_add :992");
        chk1("ADD ovf OV", ov_flag, 1'b1, "do_add :1004");
        /* Same with OVM=1: saturate to 0x7fffffff. */
        set_modes(1'b1, 1'b1, 2'd0, 1'b0);
        clear_ov;
        set_acc(32'h7fffffff);
        b32 = 32'd1;
        run_op(OP_ADD, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ADD ovf OVM=1", acc, 32'h7fffffff, "do_add :1005");
        chk1("ADD ovf OVM=1 OV", ov_flag, 1'b1, "do_add :1004");
        /* ADD 0x80000000+0x80000000=0, C=1, OV=1, OVM=1 -> 0x80000000. */
        set_acc(32'h80000000);
        b32 = 32'h80000000;
        run_op(OP_ADD, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ADD neg+neg OVM=1", acc, 32'h80000000, "do_add :1005");
        chk1("ADD neg+neg C", c_flag, 1'b1, "do_add :992");
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        clear_ov;
        /* ADD s16 (ADD dma,16): acc=0x00010000, dma=0xFFFF<<16 -> 0, C=1. */
        s16 = 1'b1;
        set_acc(32'h00010000);
        b32 = 32'hffff0000;
        run_op(OP_ADD, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ADD s16 carry", acc, 32'b0, "do_add s16 :999");
        chk1("ADD s16 C=1", c_flag, 1'b1, "do_add s16 :999");
        /* ADD s16 no carry: C holds (was 1, stays 1). */
        set_acc(32'b0);
        b32 = 32'h00010000;
        run_op(OP_ADD, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ADD s16 nocarry", acc, 32'h00010000, "do_add s16 :999");
        chk1("ADD s16 C holds 1", c_flag, 1'b1, "do_add s16 :999");
        /* Same with C=0 preset: holds 0. */
        set_c(1'b0);
        set_acc(32'b0);
        b32 = 32'h00010000;
        run_op(OP_ADD, 1'b1, 1'b0, 1'b0, 1'b0);
        chk1("ADD s16 C holds 0", c_flag, 1'b0, "do_add s16 :999");
        s16 = 1'b0;
        /* SUB 5-3=2, C=1 (no borrow); SUB 3-5 -> C=0. */
        set_acc(32'd5);
        b32 = 32'd3;
        run_op(OP_SUB, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SUB 5-3", acc, 32'd2, "do_sub :1015");
        chk1("SUB 5-3 C", c_flag, 1'b1, "do_sub :1021");
        set_acc(32'd3);
        b32 = 32'd5;
        run_op(OP_SUB, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SUB 3-5", acc, 32'hfffffffe, "do_sub :1015");
        chk1("SUB 3-5 C", c_flag, 1'b0, "do_sub :1021");
        /* SUB overflow, OVM=1: 0x80000000-1 -> 0x80000000 (saturate low). */
        set_modes(1'b1, 1'b1, 2'd0, 1'b0);
        clear_ov;
        set_acc(32'h80000000);
        b32 = 32'd1;
        run_op(OP_SUB, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SUB ovf OVM=1", acc, 32'h80000000, "do_sub :1027");
        chk1("SUB ovf OV", ov_flag, 1'b1, "do_sub :1027");
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        clear_ov;
        /* SUB s16: 0-0x00010000 borrows -> C=0; no borrow holds C. */
        s16 = 1'b1;
        set_c(1'b1);
        set_acc(32'b0);
        b32 = 32'h00010000;
        run_op(OP_SUB, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SUB s16 borrow", acc, 32'hffff0000, "do_sub s16 :1020");
        chk1("SUB s16 C=0", c_flag, 1'b0, "do_sub s16 :1020");
        set_c(1'b1);
        set_acc(32'h00020000);
        b32 = 32'h00010000;
        run_op(OP_SUB, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SUB s16 noborrow", acc, 32'h00010000, "do_sub s16 :1020");
        chk1("SUB s16 C holds 1", c_flag, 1'b1, "do_sub s16 :1020");
        s16 = 1'b0;
        /* ADDC: acc=0xFFFFFFFF, b=0, C=1 -> 0, C=1; C=0 -> 0xFFFFFFFF. */
        set_c(1'b1);
        set_acc(32'hffffffff);
        b32 = 32'b0;
        run_op(OP_ADDC, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ADDC cin=1", acc, 32'b0, "exec_hi_60_7f 0x60 :1705");
        chk1("ADDC C", c_flag, 1'b1, "do_add :992");
        set_c(1'b0);
        set_acc(32'hffffffff);
        b32 = 32'b0;
        run_op(OP_ADDC, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ADDC cin=0", acc, 32'hffffffff, "exec_hi_60_7f 0x60 :1705");
        chk1("ADDC C=0", c_flag, 1'b0, "do_add :992");
        /* SUBB: 5-3-!C; C=0 -> 1, C=1; C=1, 3-5 -> borrow, C=0. */
        set_c(1'b0);
        set_acc(32'd5);
        b32 = 32'd3;
        run_op(OP_SUBB, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SUBB bin=1", acc, 32'd1, "exec_hi_60_7f 0x64 :1725");
        chk1("SUBB C", c_flag, 1'b1, "do_sub :1021");
        set_c(1'b1);
        set_acc(32'd3);
        b32 = 32'd5;
        run_op(OP_SUBB, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SUBB bin=0", acc, 32'hfffffffe, "exec_hi_60_7f 0x64 :1725");
        chk1("SUBB C=0", c_flag, 1'b0, "do_sub :1021");
        /*
        SBBB: C only, no OV/sat (audit 07c SBBB OBEYS; SPRU056D p.6-233).
        0x80000000-1-1 = 0x7ffffffe: do_sub WOULD set OV; SBBB must not.
        */
        clear_ov;
        set_c(1'b0);
        set_accb(32'd1);
        set_acc(32'h80000000);
        run_op(OP_SBBB, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SBBB value", acc, 32'h7ffffffe, "exec_be_acc 0x19 :2240");
        chk1("SBBB C", c_flag, 1'b1, "exec_be_acc 0x19 :2240");
        chk1("SBBB OV stays 0", ov_flag, 1'b0, "exec_be_acc 0x19 :2240");
        /* ADD_B / ADDC_B / SUB_B with ACCB. */
        set_accb(32'd20);
        set_acc(32'd10);
        run_op(OP_ADD_B, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ADDB 10+20", acc, 32'd30, "exec_be_acc 0x10 :2237");
        set_c(1'b0);
        set_accb(32'hffffffff);
        set_acc(32'd1);
        run_op(OP_ADDC_B, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ADDC_B", acc, 32'b0, "exec_be_acc 0x11 :2237");
        chk1("ADDC_B C", c_flag, 1'b1, "do_add :992");
        set_accb(32'd10);
        set_acc(32'd20);
        run_op(OP_SUB_B, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SUBB 20-10", acc, 32'd10, "exec_be_acc 0x18 :2252");
        /* Logic: AND/OR/XOR, AND clears ACCH (16-bit zero-extended). */
        set_acc(32'h0000ff0f);
        b32 = 32'h00000ff0;
        run_op(OP_AND, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("AND", acc, 32'h00000f00, "exec_hi_60_7f 0x6E :1745");
        set_acc(32'h0000ff0f);
        b32 = 32'h00000ff0;
        run_op(OP_OR, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("OR", acc, 32'h0000ffff, "exec_hi_60_7f 0x6D :1740");
        set_acc(32'h0000ff0f);
        b32 = 32'h00000ff0;
        run_op(OP_XOR, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("XOR", acc, 32'h0000f0ff, "exec_hi_60_7f 0x6C :1735");
        set_acc(32'hffffffff);
        b32 = 32'h0000ffff;
        run_op(OP_AND, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("AND clears ACCH", acc, 32'h0000ffff, "exec_hi_60_7f 0x6E :1745");
        set_accb(32'h0f0f0f0f);
        set_acc(32'hff00ff00);
        run_op(OP_AND_B, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ANDB", acc, 32'h0f000f00, "exec_be_acc 0x12 :2248");
        set_accb(32'h0f0f0f0f);
        set_acc(32'hff00ff00);
        run_op(OP_OR_B, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ORB", acc, 32'hff0fff0f, "exec_be_acc 0x13 :2248");
        set_accb(32'h0f0f0f0f);
        set_acc(32'hff00ff00);
        run_op(OP_XOR_B, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("XORB", acc, 32'hf00ff00f, "exec_be_acc 0x1A :2255");

        /*
        ============ ext() / shifts of the operand ============
        ext(): LACC/ADD/SUB with shift, :1326-1331; audit 07b LACC OBEYS.
        */
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        b16   = 16'h8000;
        shift = 4'd15;
        #1;
        chk32("ext sxm=1 0x8000<<15", ext_out, 32'hc0000000, "ext() :1329");
        set_modes(1'b0, 1'b0, 2'd0, 1'b0);
        #1;
        chk32("ext sxm=0 0x8000<<15", ext_out, 32'h40000000, "ext() :1330");
        b16   = 16'hffff;
        shift = 4'd4;
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        #1;
        chk32("ext sxm=1 0xffff<<4", ext_out, 32'hfffffff0, "ext() :1329");
        set_modes(1'b0, 1'b0, 2'd0, 1'b0);
        #1;
        chk32("ext sxm=0 0xffff<<4", ext_out, 32'h000ffff0, "ext() :1330");
        /* b16_shl: plain shift for AND/OR/XOR #lk,sh (exec_bf :2501). */
        b16   = 16'h00f0;
        shift = 4'd4;
        #1;
        chk32("b16_shl", b16_shl, 32'h00000f00, "exec_bf :2501");
        /* LD_EXT / ADD_SH / SUB_SH. */
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        b16   = 16'h0002;
        shift = 4'd3;
        run_op(OP_LD_EXT, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("LD_EXT 2<<3", acc, 32'h10, "exec_hi_10_3f :1477");
        set_acc(32'h100);
        b16   = 16'h0002;
        shift = 4'd3;
        run_op(OP_ADD_SH, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ADD_SH", acc, 32'h110, "exec_hi_10_3f :1482");
        set_acc(32'h100);
        run_op(OP_SUB_SH, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SUB_SH", acc, 32'hf0, "exec_hi_10_3f :1487");
        /* ADDT/SUBT/LACT shift by TREG1 (treg1 = treg0[4:0] via set_t0). */
        set_treg0(16'h0005);
        chk16("set_t0 treg1 mirror", treg1, 16'h0005, "set_t0 :1052");
        chk16("set_t0 treg2 mirror", treg2, 16'h0005, "set_t0 :1053");
        set_acc(32'b0);
        b16 = 16'h0002;
        run_op(OP_LACT, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("LACT 2<<5", acc, 32'h40, "exec_hi_60_7f 0x6B :1760");
        set_acc(32'h100);
        run_op(OP_ADDT, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ADDT", acc, 32'h140, "exec_hi_60_7f 0x63 :1720");
        set_acc(32'h100);
        run_op(OP_SUBT, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SUBT", acc, 32'hc0, "exec_hi_60_7f 0x67 :1740");
        /* TRM=1 blocks the TREG1/2 mirror (set_t0 :1051). */
        set_modes(1'b1, 1'b0, 2'd0, 1'b1);
        set_treg0(16'h001f);
        chk16("TRM treg0 loads", treg0, 16'h001f, "set_t0 :1051");
        chk16("TRM treg1 holds", treg1, 16'h0005, "set_t0 :1051");
        chk16("TRM treg2 holds", treg2, 16'h0005, "set_t0 :1051");
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);

        /*
        ============ multiplier + pscale ============
        MPY signed corners (exec_hi_40_5f 0x54 :1612; audit 07b MPY OBEYS).
        */
        set_treg0(16'h8000);
        mpy_a        = 16'h8000;
        mpy_b        = 16'h8000;
        mpy_unsigned = 1'b0;
        run_op(OP_MPY, 1'b0, 1'b0, 1'b1, 1'b0);
        chk32("MPY -32768*-32768", preg, 32'h40000000, "MPY :1615");
        mpy_a = 16'h8000;
        mpy_b = 16'h0001;
        run_op(OP_MPY, 1'b0, 1'b0, 1'b1, 1'b0);
        chk32("MPY -32768*1", preg, 32'hffff8000, "MPY :1615");
        mpy_a = 16'h7fff;
        mpy_b = 16'h7fff;
        run_op(OP_MPY, 1'b0, 1'b0, 1'b1, 1'b0);
        chk32("MPY 32767*32767", preg, 32'h3fff0001, "MPY :1615");
        mpy_a = 16'hffff;
        mpy_b = 16'hffff;
        run_op(OP_MPY, 1'b0, 1'b0, 1'b1, 1'b0);
        chk32("MPY -1*-1", preg, 32'h00000001, "MPY :1615");
        /* MPYU unsigned (0x55 :1618). */
        mpy_a        = 16'hffff;
        mpy_b        = 16'hffff;
        mpy_unsigned = 1'b1;
        run_op(OP_MPYU, 1'b0, 1'b0, 1'b1, 1'b0);
        chk32("MPYU 65535*65535", preg, 32'hfffe0001, "MPYU :1621");
        mpy_a = 16'h8000;
        mpy_b = 16'h8000;
        run_op(OP_MPYU, 1'b0, 1'b0, 1'b1, 1'b0);
        chk32("MPYU 32768*32768", preg, 32'h40000000, "MPYU :1621");
        mpy_unsigned = 1'b0;
        /* MPY #k13: k13 sign-extended by the core (exec1_op :1532-1538). */
        set_treg0(16'h0002);
        mpy_a = 16'h0002;
        mpy_b = 16'hffff; /* k13 = 0x1FFF -> -1 */
        run_op(OP_MPY, 1'b0, 1'b0, 1'b1, 1'b0);
        chk32("MPY #k13 -1", preg, 32'hfffffffe, "MPY #k13 :1536");
        mpy_b = 16'hf000; /* k13 = 0x1000 -> -4096 */
        run_op(OP_MPY, 1'b0, 1'b0, 1'b1, 1'b0);
        chk32("MPY #k13 -4096", preg, 32'hffffe000, "MPY #k13 :1536");
        /* pscale() all 4 PM modes (pscale :1034-1045), preg=0x40000000. */
        set_treg0(16'h8000);
        mpy_a = 16'h8000;
        mpy_b = 16'h8000;
        run_op(OP_MPY, 1'b0, 1'b0, 1'b1, 1'b0);
        pm = 2'd0;
        #1;
        chk32("pscale PM0", pscale, 32'h40000000, "pscale :1037");
        pm = 2'd1;
        #1;
        chk32("pscale PM1 <<1", pscale, 32'h80000000, "pscale :1038");
        pm = 2'd2;
        #1;
        chk32("pscale PM2 <<4", pscale, 32'h00000000, "pscale :1039");
        pm = 2'd3;
        #1;
        chk32("pscale PM3 >>6", pscale, 32'h01000000, "pscale :1040");
        /* pscale on negative product -32768 (0xffff8000). */
        mpy_a = 16'h8000;
        mpy_b = 16'h0001;
        run_op(OP_MPY, 1'b0, 1'b0, 1'b1, 1'b0);
        pm = 2'd0;
        #1;
        chk32("pscale neg PM0", pscale, 32'hffff8000, "pscale :1037");
        pm = 2'd1;
        #1;
        chk32("pscale neg PM1", pscale, 32'hffff0000, "pscale :1038");
        pm = 2'd2;
        #1;
        chk32("pscale neg PM2", pscale, 32'hfff80000, "pscale :1039");
        pm = 2'd3;
        #1;
        chk32("pscale neg PM3", pscale, 32'hfffffe00, "pscale :1040");
        pm = 2'd0;
        /* PAC / APAC / SPAC (exec_be_acc 0x03-0x05 :2218-2220). */
        set_acc(32'h10);
        run_op(OP_PAC, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("PAC", acc, 32'hffff8000, "exec_be_acc 0x03 :2218");
        set_acc(32'h10);
        run_op(OP_APAC, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("APAC", acc, 32'hffff8010, "exec_be_acc 0x04 :2219");
        set_acc(32'h10);
        run_op(OP_SPAC, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SPAC", acc, 32'h00008010, "exec_be_acc 0x05 :2220");
        /* MPYA / MPYS: ACC op + PREG update in one op. */
        mpy_a = 16'h0002;
        mpy_b = 16'h0003;
        set_treg0(16'h0002);
        set_acc(32'h10);
        run_op(OP_MPYA, 1'b1, 1'b0, 1'b1, 1'b0);
        chk32("MPYA acc", acc, 32'hffff8010, "MPYA :1585");
        chk32("MPYA preg", preg, 32'd6, "MPYA :1586");
        chk1("MPYA C", c_flag, 1'b0, "MPYA :1585");
        set_acc(32'h10);
        run_op(OP_MPYS, 1'b1, 1'b0, 1'b1, 1'b0);
        chk32("MPYS acc", acc, 32'h0000000a, "MPYS :1592");
        chk32("MPYS preg", preg, 32'd6, "MPYS :1593");
        chk1("MPYS C", c_flag, 1'b1, "MPYS :1592");
        /* SQRA / SQRS (0x52/0x53 :1596-1610). */
        set_acc(32'h100);
        b16   = 16'h0003;
        mpy_a = 16'h0003;
        mpy_b = 16'h0003;
        run_op(OP_SQRA, 1'b1, 1'b0, 1'b1, 1'b1);
        chk32("SQRA acc", acc, 32'h00000106, "SQRA :1599");
        chk32("SQRA preg", preg, 32'd9, "SQRA :1601");
        chk16("SQRA treg0", treg0, 16'h0003, "SQRA :1600");
        set_acc(32'h100);
        run_op(OP_SQRS, 1'b1, 1'b0, 1'b1, 1'b1);
        chk32("SQRS acc", acc, 32'h000000f7, "SQRS :1607");
        chk32("SQRS preg", preg, 32'd9, "SQRS :1609");
        /*
        LTA / LTP / LTD / LTS (0x70-0x74 :1786-1816).
        preg currently 9; set preg=0x40000000 first via MPY.
        */
        mpy_a = 16'h8000;
        mpy_b = 16'h8000;
        run_op(OP_MPY, 1'b0, 1'b0, 1'b1, 1'b0);
        set_acc(32'h10);
        b16 = 16'h0012;
        run_op(OP_LTA, 1'b1, 1'b0, 1'b0, 1'b1);
        chk32("LTA acc", acc, 32'h40000010, "LTA :1789");
        chk16("LTA treg0", treg0, 16'h0012, "LTA :1790");
        chk16("LTA treg1", treg1, 16'h0012, "set_t0 :1052");
        run_op(OP_LTP, 1'b1, 1'b0, 1'b0, 1'b1);
        chk32("LTP acc", acc, 32'h40000000, "LTP :1796");
        set_acc(32'h10);
        run_op(OP_LTS, 1'b1, 1'b0, 1'b0, 1'b1);
        chk32("LTS acc", acc, 32'hc0000010, "LTS :1816");
        /* LPH (0x75 :1819): preg high half = dma. */
        b16 = 16'h1234;
        run_op(OP_LPH, 1'b0, 1'b0, 1'b1, 1'b0);
        chk32("LPH", preg, 32'h12340000, "LPH :1822");
        /*
        ============ OP_LT_NM (MADS/MADD no-mirror TREG0 load) ============
        C model (exec_hi_a0_af 0xAA/0xAB, c5x_core.c:2083-2105): per
        iteration ACC += pscale(OLD PREG) (do_add, :2089), TREG0 = dma
        written DIRECTLY (audit N-1, :2092 -- no set_t0, so TREG1/
        TREG2 hold even when TRM=0), PREG = dma * pm[pfc] (signed,
        :2093-2094). The core drives i_mpy_a = dma, i_mpy_b = pm
        word. MADD additionally DMOVs; the DMOV and the BMAR
        sequencing belong to the core / memory agents, not this block.
        KD-23: OP_LT mirrors TREG1/TREG2 when TRM=0; OP_LT_NM does not.
        */
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        set_treg0(16'h0011);
        chk16("LT_NM setup treg1", treg1, 16'h0011, "set_t0 :1052");
        chk16("LT_NM setup treg2", treg2, 16'h0001, "set_t0 :1053");
        /* PREG = 6 via MPY 2*3; ACC = 0x100; d = 0x23, pm word = 4. */
        mpy_a = 16'h0002;
        mpy_b = 16'h0003;
        run_op(OP_MPY, 1'b0, 1'b0, 1'b1, 1'b0);
        chk32("LT_NM setup preg", preg, 32'd6, "MPY :1615");
        set_acc(32'h100);
        b16   = 16'h0023;
        mpy_a = 16'h0023;
        mpy_b = 16'h0004;
        op       = OP_LT_NM;
        ld_acc   = 1'b1;
        ld_preg  = 1'b1;
        ld_treg0 = 1'b1;
        exec     = 1'b1;
        #1;
        chk32("LT_NM acc_next", acc_next, 32'h106, "MADS/MADD :2089");
        tick;
        chk32("LT_NM acc", acc, 32'h106, "MADS/MADD :2089");
        chk32("LT_NM preg", preg, 32'h8c, "MADS/MADD :2093");
        chk16("LT_NM treg0", treg0, 16'h0023, "MADS/MADD :2092");
        chk16("LT_NM treg1 holds", treg1, 16'h0011, "MADS/MADD :2092, N-1");
        chk16("LT_NM treg2 holds", treg2, 16'h0001, "MADS/MADD :2092, N-1");
        chk1("LT_NM C", c_flag, 1'b0, "do_add :992");
        /* TRM=1: same no-mirror behaviour (mirror is off either way). */
        set_modes(1'b1, 1'b0, 2'd0, 1'b1);
        set_treg0(16'h0007);
        chk16("LT_NM TRM treg1 holds", treg1, 16'h0011, "set_t0 :1051");
        chk16("LT_NM TRM treg2 holds", treg2, 16'h0001, "set_t0 :1051");
        mpy_a = 16'h0002;
        mpy_b = 16'h0003;
        run_op(OP_MPY, 1'b0, 1'b0, 1'b1, 1'b0);
        chk32("LT_NM TRM setup preg", preg, 32'd6, "MPY :1615");
        set_acc(32'h200);
        b16   = 16'h0031;
        mpy_a = 16'h0031;
        mpy_b = 16'h0002;
        run_op(OP_LT_NM, 1'b1, 1'b0, 1'b1, 1'b1);
        chk32("LT_NM TRM acc", acc, 32'h206, "MADS/MADD :2089");
        chk32("LT_NM TRM preg", preg, 32'h62, "MADS/MADD :2093");
        chk16("LT_NM TRM treg0", treg0, 16'h0031, "MADS/MADD :2092");
        chk16("LT_NM TRM treg1 holds", treg1, 16'h0011, "MADS/MADD :2092, N-1");
        chk16("LT_NM TRM treg2 holds", treg2, 16'h0001, "MADS/MADD :2092, N-1");
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        /* Contrast: OP_LTA with the same setup DOES mirror (TRM=0). */
        set_treg0(16'h0005);
        mpy_a = 16'h0002;
        mpy_b = 16'h0003;
        run_op(OP_MPY, 1'b0, 1'b0, 1'b1, 1'b0);
        set_acc(32'h100);
        b16 = 16'h001a;
        run_op(OP_LTA, 1'b1, 1'b0, 1'b0, 1'b1);
        chk32("LTA contrast acc", acc, 32'h106, "LTA :1789");
        chk16("LTA contrast treg0", treg0, 16'h001a, "LTA :1790");
        chk16("LTA contrast treg1 mirrors", treg1, 16'h001a, "set_t0 :1052");
        chk16("LTA contrast treg2 mirrors", treg2, 16'h000a, "set_t0 :1053");
        /* Overflow: ACC saturates when OVM=1 (do_add, :1005). */
        set_modes(1'b1, 1'b1, 2'd0, 1'b0);
        clear_ov;
        mpy_a = 16'h8000;
        mpy_b = 16'h8000;
        run_op(OP_MPY, 1'b0, 1'b0, 1'b1, 1'b0);
        set_acc(32'h7fffffff);
        b16   = 16'h0002;
        mpy_a = 16'h0002;
        mpy_b = 16'h0003;
        run_op(OP_LT_NM, 1'b1, 1'b0, 1'b1, 1'b1);
        chk32("LT_NM ovf acc", acc, 32'h7fffffff, "do_add :1005");
        chk32("LT_NM ovf preg", preg, 32'd6, "MADS/MADD :2093");
        chk1("LT_NM ovf OV", ov_flag, 1'b1, "do_add :1004");
        chk1("LT_NM ovf C", c_flag, 1'b0, "do_add :992");
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        clear_ov;
        /* PREG_ZERO / ACC_ZERO / ACC_PREG_ZERO (0xBE58/0xBE59, ZAP). */
        run_op(OP_PREG_ZERO, 1'b0, 1'b0, 1'b1, 1'b0);
        chk32("PREG_ZERO", preg, 32'b0, "exec_be_ctrl 0x58 :2356");
        set_acc(32'h12345678);
        run_op(OP_ACC_ZERO, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ACC_ZERO", acc, 32'b0, "exec_be_ctrl 0x59 :2357");
        run_op(OP_ACC_PREG_ZERO, 1'b1, 1'b0, 1'b1, 1'b0);
        chk32("ACC_PREG_ZERO acc", acc, 32'b0, "exec_be_ctrl 0x59 :2357");
        chk32("ACC_PREG_ZERO preg", preg, 32'b0, "exec_be_ctrl 0x59 :2357");

        /* ============ loads (LACL/LACC/ZALR) ============ */
        b16 = 16'hbeef;
        run_op(OP_LD_B16Z, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("LD_B16Z (LACL)", acc, 32'h0000beef, "exec_hi_60_7f 0x69 :1729");
        b16 = 16'h1234;
        run_op(OP_LD_B16HI, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("LD_B16HI (LACC,16)", acc, 32'h12340000, "exec_hi_60_7f 0x6A :1734");
        b16 = 16'h1234;
        run_op(OP_LD_ZALR, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("LD_ZALR", acc, 32'h12348000, "exec_hi_60_7f 0x68 :1724");

        /* ============ NEG / ABS / CMPL ============ */
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        clear_ov;
        set_acc(32'd5);
        run_op(OP_NEG, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("NEG 5", acc, 32'hfffffffb, "exec_be_acc 0x02 :2211");
        chk1("NEG C=0", c_flag, 1'b0, "exec_be_acc 0x02 :2211");
        set_acc(32'b0);
        run_op(OP_NEG, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("NEG 0", acc, 32'b0, "exec_be_acc 0x02 :2211");
        chk1("NEG 0 C=1", c_flag, 1'b1, "exec_be_acc 0x02 :2211");
        set_acc(32'h80000000);
        run_op(OP_NEG, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("NEG 0x80000000 OVM=0", acc, 32'h80000000, "exec_be_acc 0x02 :2208");
        chk1("NEG 0x80000000 OV", ov_flag, 1'b1, "exec_be_acc 0x02 :2208");
        set_modes(1'b1, 1'b1, 2'd0, 1'b0);
        clear_ov;
        set_acc(32'h80000000);
        run_op(OP_NEG, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("NEG 0x80000000 OVM=1", acc, 32'h7fffffff, "exec_be_acc 0x02 :2208");
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        clear_ov;
        set_acc(32'hfffffffb); /* -5 */
        run_op(OP_ABS, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ABS -5", acc, 32'd5, "exec_be_acc 0x00 :2200");
        chk1("ABS C=0", c_flag, 1'b0, "exec_be_acc 0x00 :2200");
        set_acc(32'h80000000);
        run_op(OP_ABS, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ABS 0x80000000 OVM=0", acc, 32'h80000000, "exec_be_acc 0x00 :2199");
        chk1("ABS OV", ov_flag, 1'b1, "exec_be_acc 0x00 :2199");
        set_modes(1'b1, 1'b1, 2'd0, 1'b0);
        clear_ov;
        set_acc(32'h80000000);
        run_op(OP_ABS, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ABS 0x80000000 OVM=1", acc, 32'h7fffffff, "exec_be_acc 0x00 :2199");
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        set_acc(32'h12345678);
        run_op(OP_CMPL, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("CMPL", acc, 32'hedcba987, "exec_be_acc 0x01 :2206");

        /* ============ MAX / MIN / SWAP / SACB / LACB ============ */
        set_accb(32'd20);
        set_acc(32'd10);
        run_op(OP_MAX, 1'b1, 1'b1, 1'b0, 1'b0);
        chk32("MAX acc", acc, 32'd20, "exec_be_acc 0x1B :2258");
        chk32("MAX accb", accb, 32'd20, "exec_be_acc 0x1B :2258");
        chk1("MAX C=0", c_flag, 1'b0, "exec_be_acc 0x1B :2258");
        set_accb(32'd20);
        set_acc(32'd30);
        run_op(OP_MAX, 1'b1, 1'b1, 1'b0, 1'b0);
        chk32("MAX acc stays", acc, 32'd30, "exec_be_acc 0x1B :2258");
        chk32("MAX accb takes", accb, 32'd30, "exec_be_acc 0x1B :2258");
        chk1("MAX C=1", c_flag, 1'b1, "exec_be_acc 0x1B :2258");
        set_accb(32'd20);
        set_acc(32'd10);
        run_op(OP_MIN, 1'b1, 1'b1, 1'b0, 1'b0);
        chk32("MIN acc", acc, 32'd10, "exec_be_acc 0x1C :2266");
        chk32("MIN accb", accb, 32'd10, "exec_be_acc 0x1C :2266");
        chk1("MIN C=1", c_flag, 1'b1, "exec_be_acc 0x1C :2266");
        set_accb(32'd20);
        set_acc(32'd30);
        run_op(OP_MIN, 1'b1, 1'b1, 1'b0, 1'b0);
        chk32("MIN acc takes", acc, 32'd20, "exec_be_acc 0x1C :2266");
        chk1("MIN C=0", c_flag, 1'b0, "exec_be_acc 0x1C :2266");
        set_accb(32'h22222222);
        set_acc(32'h11111111);
        run_op(OP_SWAP, 1'b1, 1'b1, 1'b0, 1'b0);
        chk32("SWAP acc", acc, 32'h22222222, "exec_be_acc 0x1D :2276");
        chk32("SWAP accb", accb, 32'h11111111, "exec_be_acc 0x1D :2276");
        set_acc(32'hdeadbeef);
        run_op(OP_SACB, 1'b0, 1'b1, 1'b0, 1'b0);
        chk32("SACB", accb, 32'hdeadbeef, "exec_be_acc 0x1E :2277");
        set_accb(32'hcafef00d);
        run_op(OP_LACB, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("LACB", acc, 32'hcafef00d, "exec_be_acc 0x1F :2278");

        /* ============ SUBC (audit 07c:135, measured cases) ============ */
        clear_ov;
        set_acc(32'h00020000);
        b16 = 16'd1;
        run_op(OP_SUBC, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SUBC case1 acc", acc, 32'h00030001, "SUBC :1409, audit 07c:135");
        chk1("SUBC case1 C", c_flag, 1'b1, "SUBC :1417");
        chk1("SUBC case1 OV", ov_flag, 1'b0, "SUBC :1419");
        set_acc(32'h00008000);
        b16 = 16'd2;
        run_op(OP_SUBC, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SUBC case2 acc", acc, 32'h00010000, "SUBC :1409, audit 07c:135");
        chk1("SUBC case2 C", c_flag, 1'b0, "SUBC :1417");
        set_acc(32'h80000000);
        b16 = 16'd1;
        run_op(OP_SUBC, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SUBC case3 acc", acc, 32'hffff0001, "SUBC :1409, audit 07c:135");
        chk1("SUBC case3 C", c_flag, 1'b1, "SUBC :1417");
        chk1("SUBC case3 OV", ov_flag, 1'b1, "SUBC :1419");

        /*
        ============ shifts ============
        SFTA / BSAR: ACC >>= (sh+1), sign per SXM (exec_bf :2507-2511).
        KD-1: amount is sh+1 per the C model (audit 07b:131 OBEYS).
        */
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        set_acc(32'h80000000);
        shift = 4'd0;
        run_op(OP_SFTA, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SFTA sh0 sxm=1", acc, 32'hc0000000, "exec_bf SFTA :2510");
        set_modes(1'b0, 1'b0, 2'd0, 1'b0);
        set_acc(32'h80000000);
        shift = 4'd0;
        run_op(OP_SFTA, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SFTA sh0 sxm=0", acc, 32'h40000000, "exec_bf SFTA :2511");
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        set_acc(32'h80000000);
        shift = 4'd15;
        run_op(OP_SFTA, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SFTA sh15 sxm=1", acc, 32'hffff8000, "exec_bf SFTA :2510");
        set_modes(1'b0, 1'b0, 2'd0, 1'b0);
        set_acc(32'h80000000);
        shift = 4'd15;
        run_op(OP_SFTA, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SFTA sh15 sxm=0", acc, 32'h00008000, "exec_bf SFTA :2511");
        /* Opcode 0xBFE3: sh=3 -> shift 4 (KD-1; C model, not field value). */
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        set_acc(32'h12345678);
        shift = 4'd3;
        run_op(OP_SFTA, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SFTA 0xBFE3 >>4", acc, 32'h01234567, "exec_bf SFTA :2510, KD-1");
        set_acc(32'hf0000000);
        shift = 4'd3;
        run_op(OP_SFTA, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SFTA 0xBFE3 neg >>4", acc, 32'hff000000, "exec_bf SFTA :2510, KD-1");
        /* SATH: >>=16 iff TREG1 bit 4 (exec_be_ctrl 0x5A :2359-2363). */
        set_treg0(16'h0010);
        set_acc(32'h80000000);
        run_op(OP_SATH, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SATH treg1=0x10 sxm=1", acc, 32'hffff8000, "SATH :2361");
        set_modes(1'b0, 1'b0, 2'd0, 1'b0);
        set_acc(32'h80000000);
        run_op(OP_SATH, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SATH treg1=0x10 sxm=0", acc, 32'h00008000, "SATH :2361");
        set_treg0(16'h0000);
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        set_acc(32'h80000000);
        run_op(OP_SATH, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SATH treg1=0 no-op", acc, 32'h80000000, "SATH :2360");
        /* SATL: >>= (TREG1 & 0xF) (exec_be_ctrl 0x5B :2364-2371). */
        set_treg0(16'h0005);
        set_acc(32'h80000000);
        run_op(OP_SATL, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SATL >>5 sxm=1", acc, 32'hfc000000, "SATL :2366");
        set_treg0(16'h000f);
        set_acc(32'h80000000);
        run_op(OP_SATL, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SATL >>15 sxm=1", acc, 32'hffff0000, "SATL :2366");
        set_treg0(16'h0000);
        set_acc(32'h80000000);
        run_op(OP_SATL, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("SATL >>0 no-op", acc, 32'h80000000, "SATL :2366");
        /* ROL / ROR / ROLC / RORC (exec_be_acc 0x09-0x0D :2224-2236). */
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        set_acc(32'h80000000);
        run_op(OP_ROL, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ROL 0x80000000", acc, 32'b0, "ROL :2224");
        chk1("ROL C", c_flag, 1'b1, "ROL :2224");
        set_acc(32'h40000000);
        run_op(OP_ROL, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ROL 0x40000000", acc, 32'h80000000, "ROL :2224");
        chk1("ROL C=0", c_flag, 1'b0, "ROL :2224");
        set_acc(32'h80000001);
        run_op(OP_ROR, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ROR sxm=1", acc, 32'hc0000000, "ROR :2226");
        chk1("ROR C", c_flag, 1'b1, "ROR :2226");
        set_modes(1'b0, 1'b0, 2'd0, 1'b0);
        set_acc(32'h80000001);
        run_op(OP_ROR, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ROR sxm=0", acc, 32'h40000000, "ROR :2226");
        set_modes(1'b1, 1'b0, 2'd0, 1'b0);
        set_c(1'b1);
        set_acc(32'h80000000);
        run_op(OP_ROLC, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ROLC C=1", acc, 32'h00000001, "ROLC :2229");
        chk1("ROLC C out", c_flag, 1'b1, "ROLC :2229");
        set_c(1'b0);
        set_acc(32'h80000000);
        run_op(OP_ROLC, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("ROLC C=0", acc, 32'b0, "ROLC :2229");
        set_c(1'b1);
        set_acc(32'h00000001);
        run_op(OP_RORC, 1'b1, 1'b0, 1'b0, 1'b0);
        chk32("RORC C=1", acc, 32'h80000000, "RORC :2233");
        chk1("RORC C out", c_flag, 1'b1, "RORC :2233");
        /* SFLB / SFRB / ROLB / RORB (exec_be_acc 0x14-0x17 :2252-2264). */
        set_accb(32'h80000000);
        set_acc(32'h40000000);
        run_op(OP_SFLB, 1'b1, 1'b1, 1'b0, 1'b0);
        chk32("SFLB acc", acc, 32'h80000001, "SFLB :2253");
        chk32("SFLB accb", accb, 32'b0, "SFLB :2253");
        chk1("SFLB C", c_flag, 1'b0, "SFLB :2253");
        set_accb(32'h00000003);
        set_acc(32'h80000000);
        run_op(OP_SFRB, 1'b1, 1'b1, 1'b0, 1'b0);
        chk32("SFRB acc", acc, 32'hc0000000, "SFRB :2259");
        chk32("SFRB accb", accb, 32'h80000001, "SFRB :2259");
        chk1("SFRB C", c_flag, 1'b1, "SFRB :2259");
        set_c(1'b1);
        set_accb(32'b0);
        set_acc(32'h80000000);
        run_op(OP_ROLB, 1'b1, 1'b1, 1'b0, 1'b0);
        chk32("ROLB acc", acc, 32'b0, "ROLB :2252");
        chk32("ROLB accb", accb, 32'd1, "ROLB :2252");
        chk1("ROLB C", c_flag, 1'b1, "ROLB :2252");
        set_c(1'b1);
        set_accb(32'h00000002);
        set_acc(32'h00000001);
        run_op(OP_RORB, 1'b1, 1'b1, 1'b0, 1'b0);
        chk32("RORB acc", acc, 32'h80000000, "RORB :2256");
        chk32("RORB accb", accb, 32'h00000001, "RORB :2256");
        chk1("RORB C", c_flag, 1'b0, "RORB :2256");
        /* NORM (exec_hi_a0_af 0xA0 :1965-1985; audit 07b NORM OBEYS). */
        set_acc(32'b0);
        op     = OP_NORM;
        ld_acc = 1'b1;
        exec   = 1'b1;
        #1;
        chk1("NORM acc=0 tc_wr", tc_wr, 1'b1, "NORM :1975");
        chk1("NORM acc=0 tc=1", tc_next, 1'b1, "NORM :1975");
        tick;
        chk32("NORM acc=0 holds", acc, 32'b0, "NORM :1975");
        set_acc(32'h40000000);
        op     = OP_NORM;
        ld_acc = 1'b1;
        exec   = 1'b1;
        #1;
        chk1("NORM 0x40000000 tc=1", tc_next, 1'b1, "NORM :1975");
        tick;
        chk32("NORM 0x40000000 holds", acc, 32'h40000000, "NORM :1975");
        set_acc(32'hc0000000);
        op     = OP_NORM;
        ld_acc = 1'b1;
        exec   = 1'b1;
        #1;
        chk1("NORM 0xC0000000 tc=0", tc_next, 1'b0, "NORM :1979");
        tick;
        chk32("NORM 0xC0000000 shifts", acc, 32'h80000000, "NORM :1981");
        set_acc(32'h20000000);
        op     = OP_NORM;
        ld_acc = 1'b1;
        exec   = 1'b1;
        #1;
        chk1("NORM 0x20000000 tc=0", tc_next, 1'b0, "NORM :1979");
        tick;
        chk32("NORM 0x20000000 shifts", acc, 32'h40000000, "NORM :1981");
        set_acc(32'h00000001);
        op     = OP_NORM;
        ld_acc = 1'b1;
        exec   = 1'b1;
        #1;
        chk1("NORM 0x00000001 tc=0", tc_next, 1'b0, "NORM :1979");
        tick;
        chk32("NORM 0x00000001 shifts", acc, 32'h00000002, "NORM :1981");
        /* o_shl_acc tap (SACL/SACH: exec_hi_80_9f :1947-1955). */
        set_acc(32'h12345678);
        shift = 4'd3;
        #1;
        chk32("o_shl_acc <<3", shl_acc, 32'h91a2b3c0, "SACL/SACH :1949");
        chk32("SACL low half", {16'b0, shl_acc[15:0]}, 32'h0000b3c0, "SACL :1949");
        chk32("SACH high half", {16'b0, shl_acc[31:16]}, 32'h000091a2, "SACH :1953");

        /* ============ swept comparison vs reference functions ============ */
        sweep;
        $display("tb_c5x_alu: %0d passed, %0d failed", pass_n, fail_n);
        if (fail_n != 0)
            $fatal(1, "tb_c5x_alu: %0d failures", fail_n);
        $finish;
    end

    /*
    Swept: LFSR operands, ADD/SUB/AND/OR/XOR/ADD_SH/SFTA/MPY vs refs.
    Reference functions mirror do_add/do_sub/ext/pscale/MPY exactly.
    */
    task sweep;
        logic [15:0] lfsr;
        logic [31:0] a_val, b_val, exp_r, got_r;
        logic [32:0] wide;
        logic        exp_c, exp_ovf;
        logic [15:0] ma, mb;
        integer i;
        begin
            lfsr = LFSR_SEED;
            set_modes(1'b1, 1'b0, 2'd0, 1'b0);
            s16 = 1'b0;
            for (i = 0; i < SWEEP_ITERATIONS; i++) begin
                lfsr  = lfsr_next(lfsr);
                a_val = {lfsr, lfsr_next(lfsr)};
                lfsr  = lfsr_next(lfsr);
                b_val = {lfsr, lfsr_next(lfsr)};
                lfsr  = lfsr_next(lfsr);
                ma    = a_val[15:0];
                mb    = b_val[15:0];
                case (i % SWEEP_CASE_COUNT)
                    0: begin /* ADD */
                        clear_ov;
                        set_acc(a_val);
                        b32 = b_val;
                        run_op(OP_ADD, 1'b1, 1'b0, 1'b0, 1'b0);
                        wide    = ref_add(a_val, b_val, 1'b0);
                        exp_c   = wide[32];
                        exp_ovf = ref_add_ovf(a_val, b_val, wide[31:0]);
                        chk32("sweep ADD", acc, wide[31:0], "do_add :992");
                        chk1("sweep ADD C", c_flag, exp_c, "do_add :992");
                        chk1("sweep ADD OV", ov_flag, exp_ovf, "do_add :1004");
                    end
                    1: begin /* SUB */
                        clear_ov;
                        set_acc(a_val);
                        b32 = b_val;
                        run_op(OP_SUB, 1'b1, 1'b0, 1'b0, 1'b0);
                        wide    = ref_sub(a_val, b_val, 1'b0);
                        exp_c   = ~wide[32];
                        exp_ovf = ref_sub_ovf(a_val, b_val, wide[31:0]);
                        chk32("sweep SUB", acc, wide[31:0], "do_sub :1015");
                        chk1("sweep SUB C", c_flag, exp_c, "do_sub :1021");
                        chk1("sweep SUB OV", ov_flag, exp_ovf, "do_sub :1027");
                    end
                    2: begin /* AND / OR / XOR (rotate by i) */
                        set_acc(a_val);
                        b32 = b_val;
                        if ((i / SWEEP_CASE_COUNT) % LOGIC_VARIANT_COUNT == 0) begin
                            run_op(OP_AND, 1'b1, 1'b0, 1'b0, 1'b0);
                            chk32("sweep AND", acc, a_val & b_val, "AND :1745");
                        end else if ((i / SWEEP_CASE_COUNT) % LOGIC_VARIANT_COUNT == 1) begin
                            run_op(OP_OR, 1'b1, 1'b0, 1'b0, 1'b0);
                            chk32("sweep OR", acc, a_val | b_val, "OR :1740");
                        end else begin
                            run_op(OP_XOR, 1'b1, 1'b0, 1'b0, 1'b0);
                            chk32("sweep XOR", acc, a_val ^ b_val, "XOR :1735");
                        end
                    end
                    3: begin /* ADD_SH with ext() */
                        set_acc(a_val);
                        b16   = mb;
                        shift = a_val[3:0];
                        run_op(OP_ADD_SH, 1'b1, 1'b0, 1'b0, 1'b0);
                        exp_r = ref_ext(mb, a_val[3:0], 1'b1);
                        wide  = ref_add(a_val, exp_r, 1'b0);
                        chk32("sweep ADD_SH", acc, wide[31:0], "ADD dma,s :1482");
                    end
                    4: begin /* SFTA */
                        set_acc(a_val);
                        shift = a_val[3:0];
                        run_op(OP_SFTA, 1'b1, 1'b0, 1'b0, 1'b0);
                        exp_r = $unsigned($signed(a_val) >>> (a_val[3:0] + SFTA_SHIFT_BIAS));
                        chk32("sweep SFTA", acc, exp_r, "SFTA :2510");
                    end
                    5: begin /* MPY signed */
                        set_treg0(ma);
                        mpy_a        = ma;
                        mpy_b        = mb;
                        mpy_unsigned = 1'b0;
                        run_op(OP_MPY, 1'b0, 1'b0, 1'b1, 1'b0);
                        exp_r = $signed(ma) * $signed(mb);
                        chk32("sweep MPY", preg, exp_r, "MPY :1615");
                    end
                    6: begin /* MPYU unsigned */
                        mpy_a        = ma;
                        mpy_b        = mb;
                        mpy_unsigned = 1'b1;
                        run_op(OP_MPYU, 1'b0, 1'b0, 1'b1, 1'b0);
                        exp_r = {16'b0, ma} * {16'b0, mb};
                        chk32("sweep MPYU", preg, exp_r, "MPYU :1621");
                        mpy_unsigned = 1'b0;
                    end
                    default: begin /* pscale tap across PM modes */
                        set_treg0(ma);
                        mpy_a = ma;
                        mpy_b = mb;
                        run_op(OP_MPY, 1'b0, 1'b0, 1'b1, 1'b0);
                        got_r = preg;
                        pm    = 2'd1;
                        #1;
                        chk32("sweep pscale PM1", pscale, ref_pscale(got_r, 2'd1), "pscale :1038");
                        pm = 2'd2;
                        #1;
                        chk32("sweep pscale PM2", pscale, ref_pscale(got_r, 2'd2), "pscale :1039");
                        pm = 2'd3;
                        #1;
                        chk32("sweep pscale PM3", pscale, ref_pscale(got_r, 2'd3), "pscale :1040");
                        pm = 2'd0;
                    end
                endcase
            end
        end
    endtask

endmodule

`default_nettype wire
