/*
tb_c5x_addr.sv -- directed testbench for c5x_addr (TMS320C5x addressing
unit + status registers).

Reference model: c5x_core.c (C port). Every check cites its source as
the C function + line, or the audit doc section. Values were taken from
a C reference harness (/tmp/c5x_addr_ref) that drives the static C
functions directly, run 2026-11-19.

Build & run (from the goal directory):
  $ verilator --binary --top-module tb_c5x_addr -Mdir obj_tb tb/tb_c5x_addr.sv rtl/c5x_addr.sv
  $ ./obj_tb/Vtb_c5x_addr

Timing discipline: stimulus is driven on negedge clk; combinational
outputs (o_ea, o_cond, o_pop_data, o_rpt_restart, o_braf_restart/done)
are sampled after a #1 settle before the posedge; registered state is
checked after the posedge (+#1). AR-file and stack contents are checked
through hierarchical references (dut.ar_q, dut.stack_q) in sections
A-M; section N checks them through the new observation outputs
(o_ar_all, o_stack_all, o_ar_rd).
*/

`timescale 1ns/1ps
`default_nettype none

module tb_c5x_addr;
    logic        clk = 1'b0;
    logic        rst_n = 1'b0;
    always begin
        #5;
        clk <= ~clk;
    end

    /* ---------------- DUT inputs ---------------- */
    logic [15:0] i_op;
    logic [31:0] i_acc;
    logic        i_bio;
    logic        i_ea_en;
    logic        i_ea_p0;
    logic        i_wr_en;
    logic [5:0]  i_wr_sel;
    logic [15:0] i_wr_data;
    logic        i_flg_we;
    logic [4:0]  i_flg_sel;
    logic        i_flg_in;
    logic        i_pm_we;
    logic [1:0]  i_pm_in;
    logic        i_iptr_we;
    logic [4:0]  i_iptr_in;
    logic        i_cmpr_en;
    logic [1:0]  i_cmpr_mode;
    logic        i_cmpr_ar0;
    logic        i_push_en;
    logic [15:0] i_push_data;
    logic        i_pop_en;
    logic [15:0] i_irq_set;
    logic        i_ndx_commit;
    logic        i_rpt_setup;
    logic [15:0] i_rpt_pc_in;
    logic        i_rpt_step;
    logic [15:0] i_rpt_ppc;
    logic        i_rpt_dec;
    logic        i_rptb_set;
    logic [15:0] i_rptb_pasr;
    logic [15:0] i_rptb_paer;
    logic        i_braf_check;
    logic [15:0] i_pc;
    logic [2:0]  i_ar_rd_sel;

    /* ---------------- DUT outputs ---------------- */
    logic [15:0] o_ea;
    logic        o_ea_badop;
    logic        o_cond;
    logic [15:0] o_pop_data;
    logic [2:0]  o_sp;
    logic        o_irq_pend;
    logic [15:0] o_st0;
    logic [15:0] o_st1;
    logic [15:0] o_pmst;
    logic [15:0] o_ar;
    logic [2:0]  o_arp;
    logic [2:0]  o_arb;
    logic [15:0] o_dp;
    logic [15:0] o_indx;
    logic [15:0] o_arcr;
    logic [31:0] o_rptc;
    logic [31:0] o_brcr;
    logic [15:0] o_rpt_start;
    logic [15:0] o_rpt_end;
    logic [15:0] o_pasr;
    logic [15:0] o_paer;
    logic [15:0] o_bmar;
    logic [15:0] o_dbmr;
    logic [15:0] o_cbsr1;
    logic [15:0] o_cber1;
    logic [15:0] o_cbsr2;
    logic [15:0] o_cber2;
    logic [7:0]  o_cbcr;
    logic [15:0] o_ifr;
    logic [15:0] o_imr;
    logic        o_tc;
    logic        o_ov;
    logic        o_c;
    logic        o_braf;
    logic        o_rep_cont;
    logic        o_rpt_restart;
    logic [15:0] o_rpt_pc;
    logic        o_braf_restart;
    logic        o_braf_done;
    logic        o_ar0_dirty;
    logic [127:0] o_ar_all;
    logic [127:0] o_stack_all;
    logic [15:0] o_ar_rd;

    c5x_addr dut (
        .clk            (clk),
        .ce_i (1'b1),
        .rst_n          (rst_n),
        .i_op           (i_op),
        .i_acc          (i_acc),
        .i_bio          (i_bio),
        .i_ea_en        (i_ea_en),
        .i_ea_p0        (i_ea_p0),
        .i_wr_en        (i_wr_en),
        .i_wr_sel       (i_wr_sel),
        .i_wr_data      (i_wr_data),
        .i_flg_we       (i_flg_we),
        .i_flg_sel      (i_flg_sel),
        .i_flg_in       (i_flg_in),
        .i_pm_we        (i_pm_we),
        .i_pm_in        (i_pm_in),
        .i_iptr_we      (i_iptr_we),
        .i_iptr_in      (i_iptr_in),
        .i_cmpr_en      (i_cmpr_en),
        .i_cmpr_mode    (i_cmpr_mode),
        .i_cmpr_ar0     (i_cmpr_ar0),
        .i_push_en      (i_push_en),
        .i_push_data    (i_push_data),
        .i_pop_en       (i_pop_en),
        .o_pop_data     (o_pop_data),
        .o_sp           (o_sp),
        .i_irq_set      (i_irq_set),
        .o_irq_pend     (o_irq_pend),
        .i_ndx_commit   (i_ndx_commit),
        .i_rpt_setup    (i_rpt_setup),
        .i_rpt_pc_in    (i_rpt_pc_in),
        .i_rpt_step     (i_rpt_step),
        .i_rpt_ppc      (i_rpt_ppc),
        .i_rpt_dec      (i_rpt_dec),
        .i_rptb_set     (i_rptb_set),
        .i_rptb_pasr    (i_rptb_pasr),
        .i_rptb_paer    (i_rptb_paer),
        .i_braf_check   (i_braf_check),
        .i_pc           (i_pc),
        .o_ea           (o_ea),
        .o_ea_badop     (o_ea_badop),
        .o_cond         (o_cond),
        .o_st0          (o_st0),
        .o_st1          (o_st1),
        .o_pmst         (o_pmst),
        .o_ar           (o_ar),
        .o_arp          (o_arp),
        .o_arb          (o_arb),
        .o_dp           (o_dp),
        .o_indx         (o_indx),
        .o_arcr         (o_arcr),
        .o_rptc         (o_rptc),
        .o_brcr         (o_brcr),
        .o_rpt_start    (o_rpt_start),
        .o_rpt_end      (o_rpt_end),
        .o_pasr         (o_pasr),
        .o_paer         (o_paer),
        .o_bmar         (o_bmar),
        .o_dbmr         (o_dbmr),
        .o_cbsr1        (o_cbsr1),
        .o_cber1        (o_cber1),
        .o_cbsr2        (o_cbsr2),
        .o_cber2        (o_cber2),
        .o_cbcr         (o_cbcr),
        .o_ifr          (o_ifr),
        .o_imr          (o_imr),
        .o_tc           (o_tc),
        .o_ov           (o_ov),
        .o_c            (o_c),
        .o_braf         (o_braf),
        .o_rep_cont     (o_rep_cont),
        .o_rpt_restart  (o_rpt_restart),
        .o_rpt_pc       (o_rpt_pc),
        .o_braf_restart (o_braf_restart),
        .o_braf_done    (o_braf_done),
        .o_ar0_dirty    (o_ar0_dirty),
        .o_ar_all       (o_ar_all),
        .o_stack_all    (o_stack_all),
        .i_ar_rd_sel    (i_ar_rd_sel),
        .o_ar_rd        (o_ar_rd)
    );

    /*
    Register-file write selects, flag selects and CMPR modes used by
    the wr()/flg()/cmpr_run() helpers below. Values are the DUT's own
    contract: WR_* and FLG_* from rtl/c5x_addr.sv (c5x_set decode,
    c5x_core.c lines 514-563), CMPR_* from the CMPR case (2477-2484).
    AR0..AR7 are 6'h10..6'h17.
    */
    localparam logic [5:0] WR_IMR   = 6'h04;
    localparam logic [5:0] WR_IFR   = 6'h06;
    localparam logic [5:0] WR_PMST  = 6'h07;
    localparam logic [5:0] WR_RPTC  = 6'h08;
    localparam logic [5:0] WR_BRCR  = 6'h09;
    localparam logic [5:0] WR_PASR  = 6'h0A;
    localparam logic [5:0] WR_PAER  = 6'h0B;
    localparam logic [5:0] WR_DBMR  = 6'h0F;
    localparam logic [5:0] WR_AR0   = 6'h10;
    localparam logic [5:0] WR_AR1   = 6'h11;
    localparam logic [5:0] WR_AR2   = 6'h12;
    localparam logic [5:0] WR_AR3   = 6'h13;
    localparam logic [5:0] WR_AR4   = 6'h14;
    localparam logic [5:0] WR_AR5   = 6'h15;
    localparam logic [5:0] WR_AR6   = 6'h16;
    localparam logic [5:0] WR_AR7   = 6'h17;
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
    localparam logic [5:0] WR_DP    = 6'h22;
    localparam logic [5:0] WR_ARP   = 6'h24;
    localparam logic [5:0] WR_ST0L  = 6'h25;
    localparam logic [5:0] WR_ST1L  = 6'h26;
    localparam logic [4:0] FLG_OV   = 5'd0;
    localparam logic [4:0] FLG_INTM = 5'd2;
    localparam logic [4:0] FLG_C    = 5'd3;
    localparam logic [4:0] FLG_CNF  = 5'd4;
    localparam logic [4:0] FLG_TC   = 5'd8;
    localparam logic [4:0] FLG_NDX  = 5'd9;
    localparam logic [1:0] CMPR_EQ  = 2'd0;
    localparam logic [1:0] CMPR_LT  = 2'd1;
    localparam logic [1:0] CMPR_GT  = 2'd2;
    localparam logic [1:0] CMPR_NE  = 2'd3;

    /* ---------------- check infrastructure ---------------- */
    integer errors = 0;
    integer checks = 0;

    task automatic check(input string name, input logic [31:0] got,
                         input logic [31:0] exp);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("FAIL %-32s got=%08X exp=%08X", name, got, exp);
            end
        end
    endtask

    task automatic tick;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic reset_dut;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            tick; tick;
            @(negedge clk);
            rst_n = 1'b1;
            #1;
        end
    endtask

    task automatic clear_stim;
        begin
            i_op = 16'd0;
            i_acc = 32'd0;
            i_bio = 1'b0;
            i_ea_en = 1'b0;
            i_ea_p0 = 1'b0;
            i_wr_en = 1'b0;
            i_wr_sel = 6'd0;
            i_wr_data = 16'd0;
            i_flg_we = 1'b0;
            i_flg_sel = 5'd0;
            i_flg_in = 1'b0;
            i_pm_we = 1'b0;
            i_pm_in = 2'd0;
            i_iptr_we = 1'b0;
            i_iptr_in = 5'd0;
            i_cmpr_en = 1'b0;
            i_cmpr_mode = 2'd0;
            i_cmpr_ar0 = 1'b0;
            i_push_en = 1'b0;
            i_push_data = 16'd0;
            i_pop_en = 1'b0;
            i_irq_set = 16'd0;
            i_ndx_commit = 1'b0;
            i_rpt_setup = 1'b0;
            i_rpt_pc_in = 16'd0;
            i_rpt_step = 1'b0;
            i_rpt_ppc = 16'd0;
            i_rpt_dec = 1'b0;
            i_rptb_set = 1'b0;
            i_rptb_pasr = 16'd0;
            i_rptb_paer = 16'd0;
            i_braf_check = 1'b0;
            i_pc = 16'd0;
            i_ar_rd_sel = 3'd0;
        end
    endtask

    /* Register-file write port: one strobe cycle. */
    task automatic wr(input logic [5:0] sel, input logic [15:0] data);
        begin
            @(negedge clk);
            i_wr_en = 1'b1;
            i_wr_sel = sel;
            i_wr_data = data;
            tick;
            @(negedge clk);
            i_wr_en = 1'b0;
        end
    endtask

    /* Flag write: one strobe cycle. */
    task automatic flg(input logic [4:0] sel, input logic val);
        begin
            @(negedge clk);
            i_flg_we = 1'b1;
            i_flg_sel = sel;
            i_flg_in = val;
            tick;
            @(negedge clk);
            i_flg_we = 1'b0;
        end
    endtask

    /*
    Indirect/direct ea: check combinational o_ea/o_ea_badop before the
    edge, then commit the AR update on the edge.
    */
    task automatic ea_run(input logic [15:0] op, input logic p0,
                          input logic [15:0] exp_ea,
                          input logic exp_badop);
        begin
            @(negedge clk);
            i_op = op;
            i_ea_p0 = p0;
            i_ea_en = 1'b1;
            #1;
            check("ea", {16'd0, o_ea}, {16'd0, exp_ea});
            check("ea_badop", {31'd0, o_ea_badop}, {31'd0, exp_badop});
            tick;
            @(negedge clk);
            i_ea_en = 1'b0;
            i_ea_p0 = 1'b0;
        end
    endtask

    /*
    ea with the NDX-mirror commit strobe in the SAME cycle (contract:
    mirror uses the post-update AR0).
    */
    task automatic ea_commit_run(input logic [15:0] op,
                                 input logic [15:0] exp_ea);
        begin
            @(negedge clk);
            i_op = op;
            i_ea_en = 1'b1;
            i_ndx_commit = 1'b1;
            #1;
            check("ea_commit_ea", {16'd0, o_ea}, {16'd0, exp_ea});
            tick;
            @(negedge clk);
            i_ea_en = 1'b0;
            i_ndx_commit = 1'b0;
        end
    endtask

    task automatic commit;
        begin
            @(negedge clk);
            i_ndx_commit = 1'b1;
            tick;
            @(negedge clk);
            i_ndx_commit = 1'b0;
        end
    endtask

    task automatic push(input logic [15:0] data);
        begin
            @(negedge clk);
            i_push_en = 1'b1;
            i_push_data = data;
            tick;
            @(negedge clk);
            i_push_en = 1'b0;
        end
    endtask

    /*
    Pop: o_pop_data is combinational on the current top; sample it
    before the edge, then the edge performs the pop.
    */
    task automatic pop(input logic [15:0] exp_data);
        begin
            @(negedge clk);
            i_pop_en = 1'b1;
            #1;
            check("pop_data", {16'd0, o_pop_data}, {16'd0, exp_data});
            tick;
            @(negedge clk);
            i_pop_en = 1'b0;
        end
    endtask

    /*
    rpt step: o_rpt_restart/o_rpt_pc are combinational on ppc; sample
    before the edge, then the edge performs the count.
    */
    task automatic rpt_step_run(input logic [15:0] ppc,
                                input logic exp_restart,
                                input logic [15:0] exp_pc);
        begin
            @(negedge clk);
            i_rpt_step = 1'b1;
            i_rpt_ppc = ppc;
            #1;
            check("rpt_restart", {31'd0, o_rpt_restart},
                  {31'd0, exp_restart});
            check("rpt_pc", {16'd0, o_rpt_pc}, {16'd0, exp_pc});
            tick;
            @(negedge clk);
            i_rpt_step = 1'b0;
        end
    endtask

    task automatic rpt_dec_run;
        begin
            @(negedge clk);
            i_rpt_dec = 1'b1;
            tick;
            @(negedge clk);
            i_rpt_dec = 1'b0;
        end
    endtask

    /* braf check: o_braf_restart/o_braf_done combinational on i_pc. */
    task automatic braf_check_run(input logic [15:0] pc,
                                  input logic exp_restart,
                                  input logic exp_done);
        begin
            @(negedge clk);
            i_braf_check = 1'b1;
            i_pc = pc;
            #1;
            check("braf_restart", {31'd0, o_braf_restart},
                  {31'd0, exp_restart});
            check("braf_done", {31'd0, o_braf_done}, {31'd0, exp_done});
            tick;
            @(negedge clk);
            i_braf_check = 1'b0;
        end
    endtask

    task automatic cmpr_run(input logic [1:0] mode, input logic ar0sel,
                            input logic exp_tc);
        begin
            @(negedge clk);
            i_cmpr_en = 1'b1;
            i_cmpr_mode = mode;
            i_cmpr_ar0 = ar0sel;
            tick;
            @(negedge clk);
            i_cmpr_en = 1'b0;
            check("cmpr_tc", {31'd0, o_tc}, {31'd0, exp_tc});
        end
    endtask

    /*
    cond(): i_op carries {tp[9:8], zlvc[7:4], mask[3:0]} on the low
    10 bits (base 0xE000 in the vectors); i_acc/i_bio set directly.
    */
    task automatic cond_run(input logic [15:0] op, input logic [31:0] acc,
                            input logic bio, input logic exp);
        begin
            @(negedge clk);
            i_op = op;
            i_acc = acc;
            i_bio = bio;
            #1;
            check("cond", {31'd0, o_cond}, {31'd0, exp});
        end
    endtask

    /*
    128-bit check for the packed observation vectors (o_ar_all,
    o_stack_all): one check per whole vector.
    */
    task automatic check128(input string name, input logic [127:0] got,
                            input logic [127:0] exp);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("FAIL %-32s got=%032h exp=%032h", name, got, exp);
            end
        end
    endtask

    /*
    Indexed AR read: drive i_ar_rd_sel and sample o_ar_rd after a
    #1 settle. Combinational, no clock edge.
    */
    task automatic ar_rd_run(input logic [2:0] sel,
                             input logic [15:0] exp);
        begin
            @(negedge clk);
            i_ar_rd_sel = sel;
            #1;
            check("ar_rd", {16'd0, o_ar_rd}, {16'd0, exp});
        end
    endtask

    /*
    ea() with the indexed AR read sampled in the same cycle: the
    SAR source is read BEFORE the ea() AR update commits (C
    exec_hi_80_9f: d = ar[(op>>8)&7] is read before ea()).
    */
    task automatic ea_ar_rd_run(input logic [15:0] op,
                                input logic [2:0] sel,
                                input logic [15:0] exp_ea,
                                input logic [15:0] exp_rd_before,
                                input logic [15:0] exp_rd_after);
        begin
            @(negedge clk);
            i_op = op;
            i_ea_en = 1'b1;
            i_ar_rd_sel = sel;
            #1;
            check("ea_rd_ea", {16'd0, o_ea}, {16'd0, exp_ea});
            check("ea_rd_before", {16'd0, o_ar_rd},
                  {16'd0, exp_rd_before});
            tick;
            @(negedge clk);
            i_ea_en = 1'b0;
            check("ea_rd_after", {16'd0, o_ar_rd},
                  {16'd0, exp_rd_after});
        end
    endtask

    /*
    ================================================================
    A. Reset -- c5x_reset(), c5x_core.c:425-452; getters 453-480
    ================================================================
    */
    initial begin
        clear_stim;
        reset_dut;
        check("A st0 reset", {16'd0, o_st0}, 32'h00000600);
        check("A st1 reset", {16'd0, o_st1}, 32'h000007FC);
        check("A pmst reset", {16'd0, o_pmst}, 32'h00000000);
        check("A sp reset", {29'd0, o_sp}, 32'd0);
        check("A rptc reset", o_rptc, 32'd0);
        check("A brcr reset", o_brcr, 32'd0);
        check("A ifr reset", {16'd0, o_ifr}, 32'd0);
        check("A imr reset", {16'd0, o_imr}, 32'd0);
        check("A ar0 reset", {16'd0, dut.ar_q[0]}, 32'd0);
        check("A arp reset", {29'd0, o_arp}, 32'd0);
        check("A arb reset", {29'd0, o_arb}, 32'd0);

        /*
        ================================================================
        B. ST0/ST1/PMST bit-exactness -- st0_get/st1_get/pmst_get
           (453-480) + c5x_set decode (514-563)
        ================================================================
        */
        wr(WR_ST0, 16'hE7FF); 
        check("B st0 0xE7FF", {16'd0, o_st0}, 32'h0000E7FF);
        wr(WR_ST1, 16'hD5AA); 
        check("B st1 0xD5AA->0xD5AE", {16'd0, o_st1}, 32'h0000D5AE);
        check("B st1 arb=6", {29'd0, o_arb}, 32'd6);
        wr(WR_PMST, 16'hFFDF); 
        check("B pmst 0xFFDF->0xF89F", {16'd0, o_pmst}, 32'h0000F89F);
        check("B pmst braf=1", {31'd0, o_braf}, 32'd1);

        /*
        Reset preserves INDX/ARCR/CBSR/CBER/BMAR/DBMR/PASR/PAER
        (c5x_reset deliberately does not touch them, 425-452).
        */
        wr(WR_INDX, 16'h1234); 
        wr(WR_ARCR, 16'h5678); 
        wr(WR_CBSR1, 16'h0100); 
        wr(WR_CBER1, 16'h0102); 
        wr(WR_BMAR, 16'h9ABC); 
        reset_dut;
        check("B indx survives reset", {16'd0, o_indx}, 32'h00001234);
        check("B arcr survives reset", {16'd0, o_arcr}, 32'h00005678);
        check("B cbsr1 survives reset", {16'd0, o_cbsr1}, 32'h00000100);
        check("B cber1 survives reset", {16'd0, o_cber1}, 32'h00000102);
        check("B bmar survives reset", {16'd0, o_bmar}, 32'h00009ABC);
        check("B ndx cleared by reset", {31'd0, o_braf}, 32'd0);

        /*
        ================================================================
        C. Direct addressing + DP -- ea() 1119-1121, ea_p0() 1158-1164,
           LDP dma 1434-1436 / LDP #k9 2177
        ================================================================
        */
        reset_dut;
        wr(WR_DP, 16'hFFFF); /* masked to 9 bits, <<7 */
        check("C dp 0xFFFF->0xFF80", {16'd0, o_dp}, 32'h0000FF80);
        wr(WR_DP, 16'h0002); /* page 2 -> dp = 0x0100 */
        check("C dp page2", {16'd0, o_dp}, 32'h00000100);
        ea_run(16'h003F, 1'b0, 16'h013F, 1'b0); /* direct, dp|0x3F */
        ea_run(16'h003F, 1'b1, 16'h003F, 1'b0); /* ea_p0: page 0 */

        /*
        ================================================================
        D. Indirect modes -- ea() 1119-1156; AR wrap at 0xFFFF/0x0000
        ================================================================
        */
        reset_dut;
        wr(WR_AR0, 16'h1000); 
        wr(WR_INDX, 16'h0010); 
        ea_run(16'h0080, 1'b0, 16'h1000, 1'b0); /* *        (m=0) */
        check("D * ar unchanged", {16'd0, dut.ar_q[0]}, 32'h00001000);
        ea_run(16'h0090, 1'b0, 16'h1000, 1'b0); /* *-       (m=2) */
        check("D *- ar", {16'd0, dut.ar_q[0]}, 32'h00000FFF);
        ea_run(16'h00A0, 1'b0, 16'h0FFF, 1'b0); /* *+       (m=4) */
        check("D *+ ar", {16'd0, dut.ar_q[0]}, 32'h00001000);
        ea_run(16'h00D0, 1'b0, 16'h1000, 1'b0); /* *0-      (m=0xA) */
        check("D *0- ar", {16'd0, dut.ar_q[0]}, 32'h00000FF0);
        ea_run(16'h00E0, 1'b0, 16'h0FF0, 1'b0); /* *0+      (m=0xC) */
        check("D *0+ ar", {16'd0, dut.ar_q[0]}, 32'h00001000);
        ea_run(16'h008B, 1'b0, 16'h1000, 1'b0); /* * + ARP->3 (m=1) */
        check("D * arp switch", {29'd0, o_arp}, 32'd3);
        check("D * arb saved", {29'd0, o_arb}, 32'd0);
        check("D o_ar reads AR3", {16'd0, o_ar}, 32'h00000000);
        wr(WR_ARP, 16'h0000); /* ARP back to 0 */
        check("D o_ar reads AR0", {16'd0, o_ar}, 32'h00001000);
        ea_run(16'h00B0, 1'b0, 16'h1000, 1'b1); /* m=6 BADOP */
        check("D badop6 ar unchanged", {16'd0, dut.ar_q[0]}, 32'h00001000);
        check("D badop6 arp unchanged", {29'd0, o_arp}, 32'd0);
        ea_run(16'h00BB, 1'b0, 16'h1000, 1'b1); /* m=7 BADOP + ARP->3 */
        check("D badop7 arp switch", {29'd0, o_arp}, 32'd3);
        check("D badop7 arb saved", {29'd0, o_arb}, 32'd0);
        wr(WR_ARP, 16'h0000); /* ARP back to 0 */
        /* 16-bit wrap */
        wr(WR_AR0, 16'hFFFF);
        ea_run(16'h00A0, 1'b0, 16'hFFFF, 1'b0); /* *+ at 0xFFFF */
        check("D wrap *+ 0xFFFF->0", {16'd0, dut.ar_q[0]}, 32'h00000000);
        wr(WR_AR0, 16'h0000);
        ea_run(16'h0090, 1'b0, 16'h0000, 1'b0); /* *- at 0x0000 */
        check("D wrap *- 0->0xFFFF", {16'd0, dut.ar_q[0]}, 32'h0000FFFF);
        /* INDX as signed int16: INDX=0xFFFF is -1 */
        wr(WR_INDX, 16'hFFFF);
        wr(WR_AR0, 16'h1000);
        ea_run(16'h00E0, 1'b0, 16'h1000, 1'b0); /* *0+ by -1 */
        check("D *0+ indx=-1", {16'd0, dut.ar_q[0]}, 32'h00000FFF);
        ea_run(16'h00D0, 1'b0, 16'h0FFF, 1'b0); /* *0- by -1 => +1 */
        check("D *0- indx=-1", {16'd0, dut.ar_q[0]}, 32'h00001000);

        /*
        ================================================================
        E. Bit-reversed -- ea() 1119-1156, bitrev16()
        ================================================================
        */
        reset_dut;
        wr(WR_AR0, 16'h0000);
        wr(WR_INDX, 16'h0002); 
        ea_run(16'h00F0, 1'b0, 16'h0000, 1'b0); /* *BR0+ */
        check("E BR+ 0->2", {16'd0, dut.ar_q[0]}, 32'h00000002);
        ea_run(16'h00F0, 1'b0, 16'h0002, 1'b0);
        check("E BR+ 2->1", {16'd0, dut.ar_q[0]}, 32'h00000001);
        ea_run(16'h00F0, 1'b0, 16'h0001, 1'b0);
        check("E BR+ 1->3", {16'd0, dut.ar_q[0]}, 32'h00000003);
        ea_run(16'h00F0, 1'b0, 16'h0003, 1'b0);
        check("E BR+ 3->0", {16'd0, dut.ar_q[0]}, 32'h00000000);
        wr(WR_AR0, 16'h0003);
        ea_run(16'h00C0, 1'b0, 16'h0003, 1'b0); /* *BR0- */
        check("E BR- 3->1", {16'd0, dut.ar_q[0]}, 32'h00000001);
        ea_run(16'h00C0, 1'b0, 16'h0001, 1'b0);
        check("E BR- 1->2", {16'd0, dut.ar_q[0]}, 32'h00000002);
        wr(WR_INDX, 16'h0001); 
        wr(WR_AR0, 16'h0000);
        ea_run(16'h00F0, 1'b0, 16'h0000, 1'b0);
        check("E BR+ indx1 0->1", {16'd0, dut.ar_q[0]}, 32'h00000001);
        ea_run(16'h00F0, 1'b0, 16'h0001, 1'b0);
        check("E BR+ indx1 1->0", {16'd0, dut.ar_q[0]}, 32'h00000000);

        /*
        ================================================================
        F. Circular buffer -- circ_end() 1062-1078, upd_ar() 1085-1106
        ================================================================
        */
        reset_dut;
        wr(WR_CBSR1, 16'h0100); 
        wr(WR_CBER1, 16'h0102); 
        wr(WR_CBCR, 16'h0008); /* bank1 enabled, car1=0 */
        wr(WR_AR0, 16'h0102);
        ea_run(16'h00A0, 1'b0, 16'h0102, 1'b0); /* *+ at CBER -> wrap */
        check("F circ1 wrap at CBER", {16'd0, dut.ar_q[0]}, 32'h00000100);
        wr(WR_AR0, 16'h0101);
        ea_run(16'h00A0, 1'b0, 16'h0101, 1'b0);
        check("F circ1 0x101->0x102", {16'd0, dut.ar_q[0]}, 32'h00000102);
        wr(WR_AR0, 16'h0100);
        ea_run(16'h0090, 1'b0, 16'h0100, 1'b0); /* *- at CBSR: NO wrap */
        check("F circ1 no wrap at CBSR", {16'd0, dut.ar_q[0]}, 32'h000000FF);
        /* Bank 2 */
        wr(WR_CBSR2, 16'h0200); 
        wr(WR_CBER2, 16'h0202); 
        check("F cbsr2", {16'd0, o_cbsr2}, 32'h00000200);
        check("F cber2", {16'd0, o_cber2}, 32'h00000202);
        wr(WR_CBCR, 16'h0090); /* bank2 enabled, car2=1 */
        wr(WR_AR1, 16'h0202); 
        wr(WR_ARP, 16'h0001); 
        ea_run(16'h00A0, 1'b0, 16'h0202, 1'b0);
        check("F circ2 wrap at CBER", {16'd0, dut.ar_q[1]}, 32'h00000200);
        /* Bank 1 wins over bank 2 (CBCR=0x88: both enabled, car1=car2=0) */
        wr(WR_CBCR, 16'h0088);
        wr(WR_ARP, 16'h0000); 
        wr(WR_AR0, 16'h0102);
        ea_run(16'h00A0, 1'b0, 16'h0102, 1'b0);
        check("F circ bank1 wins", {16'd0, dut.ar_q[0]}, 32'h00000100);
        /* Circular with *0+ step through upd_ar */
        wr(WR_CBCR, 16'h0008);
        wr(WR_INDX, 16'h0001);
        wr(WR_AR0, 16'h0102);
        ea_run(16'h00E0, 1'b0, 16'h0102, 1'b0); /* *0+ at CBER */
        check("F circ *0+ wrap", {16'd0, dut.ar_q[0]}, 32'h00000100);
        /* KD-1: bit-reversed past-end does NOT wrap (C vs manual) */
        wr(WR_AR0, 16'h0101);
        wr(WR_INDX, 16'h0002);
        ea_run(16'h00F0, 1'b0, 16'h0101, 1'b0); /* *BR0+ from 0x101 */
        check("F KD-1 BR past-end 0x103", {16'd0, dut.ar_q[0]}, 32'h00000103);
        /* KD-1 companion: circ_end fires when CURRENT AR == CBER */
        wr(WR_AR0, 16'h0102);
        wr(WR_INDX, 16'h0001);
        ea_run(16'h00F0, 1'b0, 16'h0102, 1'b0);
        check("F KD-1 BR at CBER wraps", {16'd0, dut.ar_q[0]}, 32'h00000100);
        /* No circular: same step gives 0x0103 */
        wr(WR_CBCR, 16'h0000);
        wr(WR_AR0, 16'h0102);
        ea_run(16'h00F0, 1'b0, 16'h0102, 1'b0);
        check("F no-circ BR 0x102->0x103", {16'd0, dut.ar_q[0]}, 32'h00000103);

        /*
        ================================================================
        G. NDX mirror -- apply_ar0_mirror() 2756-2763
        ================================================================
        */
        reset_dut;
        /*
        INDX survives reset by design (c5x_reset 425-452), so clear
        it explicitly: earlier sections left it at 0x0001.
        */
        wr(WR_INDX, 16'h0000); 
        wr(WR_AR0, 16'h0010); /* ar0_dirty=1 */
        check("G dirty set on AR0 write", {31'd0, o_ar0_dirty}, 32'd1);
        check("G mirror not yet applied", {16'd0, o_indx}, 32'h00000000);
        commit;
        check("G mirror indx=ar0", {16'd0, o_indx}, 32'h00000010);
        check("G mirror arcr=ar0", {16'd0, o_arcr}, 32'h00000010);
        check("G dirty cleared", {31'd0, o_ar0_dirty}, 32'd0);
        flg(FLG_NDX, 1'b1); 
        wr(WR_AR0, 16'h0020);
        commit;
        check("G ndx=1 mirror blocked indx", {16'd0, o_indx}, 32'h00000010);
        check("G ndx=1 mirror blocked arcr", {16'd0, o_arcr}, 32'h00000010);
        check("G ndx=1 dirty cleared", {31'd0, o_ar0_dirty}, 32'd0);
        flg(FLG_NDX, 1'b0); 
        wr(WR_AR0, 16'h0020);
        ea_run(16'h00A0, 1'b0, 16'h0020, 1'b0); /* *+ : AR0 0x20->0x21 */
        check("G ea sets dirty", {31'd0, o_ar0_dirty}, 32'd1);
        check("G indx still old", {16'd0, o_indx}, 32'h00000010);
        commit;
        check("G mirror after ea", {16'd0, o_indx}, 32'h00000021);
        check("G mirror arcr after ea", {16'd0, o_arcr}, 32'h00000021);
        /* Same-cycle ea + commit: mirror uses POST-update AR0 */
        wr(WR_AR0, 16'h0030);
        ea_commit_run(16'h00A0, 16'h0030);
        check("G same-cycle ea ar0", {16'd0, dut.ar_q[0]}, 32'h00000031);
        check("G same-cycle mirror indx", {16'd0, o_indx}, 32'h00000031);
        /* Same-value re-write (audit T5b): mirror still applies */
        wr(WR_AR0, 16'h0010);
        commit;
        check("G same-value mirror", {16'd0, o_indx}, 32'h00000010);

        /*
        ================================================================
        H. Stack -- push() 972-975, pop() 978-985 (incl. pop-copy quirk)
        ================================================================
        */
        reset_dut;
        pop(16'h0000); /* pop from reset: returns 0, sp 0->1 */
        check("H pop empty sp", {29'd0, o_sp}, 32'd1);
        reset_dut;
        push(16'h1000);
        push(16'h1001);
        push(16'h1002);
        push(16'h1003);
        push(16'h1004);
        push(16'h1005);
        push(16'h1006);
        push(16'h1007);
        check("H sp after 8 pushes", {29'd0, o_sp}, 32'd0);
        check("H stack[0]=1007", {16'd0, dut.stack_q[0]}, 32'h00001007);
        check("H stack[1]=1006", {16'd0, dut.stack_q[1]}, 32'h00001006);
        check("H stack[2]=1005", {16'd0, dut.stack_q[2]}, 32'h00001005);
        check("H stack[3]=1004", {16'd0, dut.stack_q[3]}, 32'h00001004);
        check("H stack[4]=1003", {16'd0, dut.stack_q[4]}, 32'h00001003);
        check("H stack[5]=1002", {16'd0, dut.stack_q[5]}, 32'h00001002);
        check("H stack[6]=1001", {16'd0, dut.stack_q[6]}, 32'h00001001);
        check("H stack[7]=1000", {16'd0, dut.stack_q[7]}, 32'h00001000);
        pop(16'h1007);
        check("H sp after pop1", {29'd0, o_sp}, 32'd1);
        check("H pop-copy stack[0]", {16'd0, dut.stack_q[0]}, 32'h00001000);
        check("H stack[1] unchanged", {16'd0, dut.stack_q[1]}, 32'h00001006);
        pop(16'h1006);
        check("H sp after pop2", {29'd0, o_sp}, 32'd2);
        check("H pop-copy stack[1]", {16'd0, dut.stack_q[1]}, 32'h00001000);
        push(16'h2000); /* 9th push overwrites stack[1], sp 2->1 */
        check("H sp after 9th push", {29'd0, o_sp}, 32'd1);
        check("H stack[1]=2000", {16'd0, dut.stack_q[1]}, 32'h00002000);

        /*
        ================================================================
        I. Flag / PM / IPTR writes + LST variants
           SETC/CLRC 2327-2342, c5x_set 514-563, LST #0/#1 1440-1466
        ================================================================
        */
        reset_dut;
        flg(FLG_OV, 1'b1); 
        check("I ov flag -> st0 bit12", {16'd0, o_st0}, 32'h00001600);
        flg(FLG_TC, 1'b1); 
        check("I tc flag -> st1 bit11", {16'd0, o_st1}, 32'h00000FFC);
        flg(FLG_CNF, 1'b1); 
        check("I cnf flag -> st1 bit12", {16'd0, o_st1}, 32'h00001FFC);
        @(negedge clk);
        i_pm_we = 1'b1;
        i_pm_in = 2'b10;
        tick;
        @(negedge clk);
        i_pm_we = 1'b0;
        check("I pm=2", {16'd0, o_st1}, 32'h00001FFE);
        @(negedge clk);
        i_iptr_we = 1'b1;
        i_iptr_in = 5'd31;
        tick;
        @(negedge clk);
        i_iptr_we = 1'b0;
        check("I iptr=31", {16'd0, o_pmst}, 32'h0000F800);
        /*
        LST #0: loads ARP/OV/OVM/DP, INTM NOT loaded. Clear INTM
        first so the check proves the word's bit 9 is ignored.
        */
        flg(FLG_INTM, 1'b0); 
        wr(WR_ST0L, 16'hE7FF); /* arp=7, ov=0, ovm=0, dp=0xFF80 */
        check("I LST0 st0", {16'd0, o_st0}, 32'h0000E5FF);
        check("I LST0 intm not loaded", {31'd0, o_st0[9]}, 32'd0);
        /* LST #1: loads ARB and ARP both, + CNF/TC/SXM/C/HM/XF/PM */
        wr(WR_ST1L, 16'hD5AA); 
        check("I LST1 st1", {16'd0, o_st1}, 32'h0000D5AE);
        check("I LST1 arb=6", {29'd0, o_arb}, 32'd6);
        check("I LST1 arp=6", {29'd0, o_arp}, 32'd6);

        /*
        ================================================================
        J. RPTC / RPTB / BRCR -- handle_rpt() 2640-2653,
           handle_braf() 2656-2668, RPTB setup 2401-2407,
           RPT/RPTZ/RPT #k 1417-1418, 2174-2175, 2391-2397
        ================================================================
        */
        reset_dut;
        wr(WR_RPTC, 16'h8000); /* zero-extended, NOT negative */
        check("J rptc 0x8000 zero-ext", o_rptc, 32'h00008000);
        wr(WR_RPTC, 16'h0005);
        @(negedge clk);
        i_rpt_setup = 1'b1;
        i_rpt_pc_in = 16'h0200;
        tick;
        @(negedge clk);
        i_rpt_setup = 1'b0;
        check("J rpt_start", {16'd0, o_rpt_start}, 32'h00000200);
        check("J rpt_end", {16'd0, o_rpt_end}, 32'h00000200);
        rpt_step_run(16'h0200, 1'b1, 16'h0200); /* ppc==end: restart */
        check("J rptc 5->4", o_rptc, 32'd4);
        check("J rep_cont=1", {31'd0, o_rep_cont}, 32'd1);
        rpt_step_run(16'h0200, 1'b1, 16'h0200);
        check("J rptc 4->3", o_rptc, 32'd3);
        rpt_step_run(16'h0201, 1'b0, 16'h0000); /* ppc!=end: no restart */
        check("J rptc unchanged", o_rptc, 32'd3);
        check("J rep_cont=0", {31'd0, o_rep_cont}, 32'd0);
        rpt_dec_run; /* RPTK decrement: 3->2->1->0->-1->-2 */
        check("J rpt_dec 3->2", o_rptc, 32'd2);
        rpt_dec_run;
        check("J rpt_dec 2->1", o_rptc, 32'd1);
        rpt_dec_run;
        check("J rpt_dec 1->0", o_rptc, 32'd0);
        rpt_dec_run;
        check("J rpt_dec 0->-1", o_rptc, 32'hFFFFFFFF);
        rpt_dec_run;
        check("J rpt_dec -1->-2", o_rptc, 32'hFFFFFFFE);
        rpt_step_run(16'h0200, 1'b0, 16'h0000); /* negative rptc clamps */
        check("J rpt negative clamps 0", o_rptc, 32'd0);
        check("J rpt negative rep_cont 0", {31'd0, o_rep_cont}, 32'd0);
        /* RPTB / BRAF */
        wr(WR_BRCR, 16'h0002); 
        @(negedge clk);
        i_rptb_set = 1'b1;
        i_rptb_pasr = 16'h0300;
        i_rptb_paer = 16'h0305;
        tick;
        @(negedge clk);
        i_rptb_set = 1'b0;
        check("J rptb braf=1", {31'd0, o_braf}, 32'd1);
        check("J rptb pasr", {16'd0, o_pasr}, 32'h00000300);
        check("J rptb paer", {16'd0, o_paer}, 32'h00000305);
        braf_check_run(16'h0306, 1'b1, 1'b0); /* pc-1 == paer, brcr 2->1 */
        check("J braf brcr 2->1", o_brcr, 32'd1);
        check("J braf still on", {31'd0, o_braf}, 32'd1);
        braf_check_run(16'h0306, 1'b1, 1'b0); /* brcr 1->0 */
        check("J braf brcr 1->0", o_brcr, 32'd0);
        braf_check_run(16'h0306, 1'b0, 1'b1); /* brcr 0 at wrap: done */
        check("J braf done clears braf", {31'd0, o_braf}, 32'd0);
        check("J braf brcr stays 0 (KD-3)", o_brcr, 32'd0);
        /* pc-1 != paer: no action */
        @(negedge clk);
        i_rptb_set = 1'b1;
        i_rptb_pasr = 16'h0300;
        i_rptb_paer = 16'h0305;
        tick;
        @(negedge clk);
        i_rptb_set = 1'b0;
        wr(WR_BRCR, 16'h0005);
        braf_check_run(16'h0300, 1'b0, 1'b0);
        check("J braf no-op off-window", o_brcr, 32'd5);
        check("J braf no-op stays on", {31'd0, o_braf}, 32'd1);

        /*
        ================================================================
        K. IFR/IMR + CBCR mask -- mmr_rd/mmr_wr 620-797, c5x_irq()
        ================================================================
        */
        reset_dut;
        @(negedge clk);
        i_irq_set = 16'h0028; /* set IFR bits 3 and 5 */
        tick;
        @(negedge clk);
        i_irq_set = 16'd0;
        check("K ifr set 0x28", {16'd0, o_ifr}, 32'h00000028);
        check("K pend 0 (imr=0)", {31'd0, o_irq_pend}, 32'd0);
        wr(WR_IMR, 16'h0028); 
        check("K pend 0x28", {31'd0, o_irq_pend}, 32'd1);
        wr(WR_IFR, 16'h0008); /* write-1-to-clear bit 3 */
        check("K w1c ifr=0x20", {16'd0, o_ifr}, 32'h00000020);
        check("K pend still 1", {31'd0, o_irq_pend}, 32'd1);
        wr(WR_IFR, 16'h0020); /* W1C bit 5 */
        check("K w1c ifr=0", {16'd0, o_ifr}, 32'h00000000);
        check("K pend cleared", {31'd0, o_irq_pend}, 32'd0);
        wr(WR_CBCR, 16'h01FF); /* masked to 0xFF */
        check("K cbcr mask 0xFF", {24'd0, o_cbcr}, 32'h000000FF);
        wr(WR_PASR, 16'hABCD); 
        wr(WR_PAER, 16'h1234); 
        check("K pasr", {16'd0, o_pasr}, 32'h0000ABCD);
        check("K paer", {16'd0, o_paer}, 32'h00001234);
        wr(WR_DBMR, 16'h55AA); 
        check("K dbmr", {16'd0, o_dbmr}, 32'h000055AA);
        wr(WR_BRCR, 16'h0002); 
        check("K brcr=2", o_brcr, 32'd2);

        /*
        ================================================================
        L. CMPR -- exec1 CMPR 2477-2484 (unsigned 16-bit compare,
           cmpv = ARCR, or AR0 when cmpr_ar0 set)
        ================================================================
        */
        reset_dut;
        wr(WR_AR2, 16'h0010); 
        wr(WR_ARCR, 16'h0010); 
        wr(WR_ARP, 16'h0002); 
        cmpr_run(CMPR_EQ, 1'b0, 1'b1); /* ar == cmpv */
        cmpr_run(CMPR_NE, 1'b0, 1'b0); /* ar != cmpv */
        wr(WR_ARCR, 16'h0011); 
        cmpr_run(CMPR_LT, 1'b0, 1'b1); /* ar < cmpv */
        cmpr_run(CMPR_GT, 1'b0, 1'b0); /* ar > cmpv */
        wr(WR_AR0, 16'h0010); /* cmpv switches to AR0 */
        cmpr_run(CMPR_EQ, 1'b1, 1'b1); /* vs AR0: equal */
        wr(WR_AR2, 16'h0011); /* AR2 > AR0 */
        cmpr_run(CMPR_EQ, 1'b1, 1'b0); /* vs AR0: not equal */
        cmpr_run(CMPR_GT, 1'b1, 1'b1); /* vs AR0: greater */

        /*
        ================================================================
        M. cond() -- 1168-1209. Vectors: op low byte =
           {zlvc[7:4], mask[3:0]}, tp at op[9:8], base 0xE000.
        ================================================================
        */
        reset_dut;
        flg(FLG_OV, 1'b0); 
        flg(FLG_C, 1'b1); 
        flg(FLG_TC, 1'b0); 
        cond_run(16'hE088, 32'd0, 1'b0, 1'b1); /* ACC==0, acc=0 */
        cond_run(16'hE088, 32'd5, 1'b0, 1'b0); /* ACC==0, acc=5 */
        cond_run(16'hE044, 32'hFFFFFFFF, 1'b0, 1'b1); /* ACC<0, acc=-1 */
        cond_run(16'hE044, 32'd5, 1'b0, 1'b0); /* ACC<0, acc=5 */
        cond_run(16'hE004, 32'd5, 1'b0, 1'b1); /* ACC>0, acc=5 */
        cond_run(16'hE004, 32'd0, 1'b0, 1'b0); /* ACC>0, acc=0 */
        cond_run(16'hE008, 32'd5, 1'b0, 1'b1); /* ACC!=0, acc=5 */
        cond_run(16'hE008, 32'd0, 1'b0, 1'b0); /* ACC!=0, acc=0 */
        cond_run(16'hE0C8, 32'd0, 1'b0, 1'b1); /* ACC>=0, acc=0 */
        cond_run(16'hE0C8, 32'hFFFFFFFF, 1'b0, 1'b0); /* ACC>=0, acc=-1 */
        cond_run(16'hE0CC, 32'hFFFFFFFF, 1'b0, 1'b1); /* ACC<=0, acc=-1 */
        cond_run(16'hE0CC, 32'd5, 1'b0, 1'b0); /* ACC<=0, acc=5 */
        /* TP field (op[9:8]) */
        flg(FLG_TC, 1'b1); 
        cond_run(16'hE188, 32'd0, 1'b0, 1'b1); /* tp=1, tc=1 */
        flg(FLG_TC, 1'b0); 
        cond_run(16'hE188, 32'd0, 1'b0, 1'b0); /* tp=1, tc=0 */
        cond_run(16'hE288, 32'd0, 1'b0, 1'b1); /* tp=2, tc=0 */
        flg(FLG_TC, 1'b1); 
        cond_run(16'hE288, 32'd0, 1'b0, 1'b0); /* tp=2, tc=1 */
        cond_run(16'hE088, 32'd0, 1'b1, 1'b0); /* tp=0, bio=1 */
        cond_run(16'hE088, 32'd0, 1'b0, 1'b1); /* tp=0, bio=0 */
        cond_run(16'hE388, 32'd0, 1'b1, 1'b1); /* tp=3: always true */
        /* OV / C mask tests (mask bit1=OV, bit0=C; zlvc bit=expected) */
        flg(FLG_OV, 1'b0); 
        check("M o_ov=0", {31'd0, o_ov}, 32'd0);
        cond_run(16'hE002, 32'd0, 1'b0, 1'b1); /* OV mask, zlvc OV=0 */
        flg(FLG_OV, 1'b1); 
        check("M o_ov=1", {31'd0, o_ov}, 32'd1);
        cond_run(16'hE002, 32'd0, 1'b0, 1'b0);
        cond_run(16'hE022, 32'd0, 1'b0, 1'b1); /* OV mask, zlvc OV=1 */
        flg(FLG_OV, 1'b0); 
        cond_run(16'hE022, 32'd0, 1'b0, 1'b0);
        flg(FLG_C, 1'b0); 
        check("M o_c=0", {31'd0, o_c}, 32'd0);
        cond_run(16'hE001, 32'd0, 1'b0, 1'b1); /* C mask, zlvc C=0 */
        flg(FLG_C, 1'b1); 
        check("M o_c=1", {31'd0, o_c}, 32'd1);
        cond_run(16'hE001, 32'd0, 1'b0, 1'b0);
        cond_run(16'hE011, 32'd0, 1'b0, 1'b1); /* C mask, zlvc C=1 */
        flg(FLG_C, 1'b0); 
        cond_run(16'hE011, 32'd0, 1'b0, 1'b0);

        /*
        ================================================================
        N. Full-file observation + indexed AR read -- FIX-1
           (o_ar_all / o_stack_all / i_ar_rd_sel / o_ar_rd)
        ================================================================
        */
        reset_dut;
        /* Observation vectors read 0 out of reset. */
        check128("N ar_all reset 0", o_ar_all, 128'd0);
        check128("N stack_all reset 0", o_stack_all, 128'd0);

        /* Distinct value per AR: ARn = 0xA000 + n*0x0101. */
        wr(WR_AR0, 16'hA000);
        wr(WR_AR1, 16'hA101);
        wr(WR_AR2, 16'hA202);
        wr(WR_AR3, 16'hA303);
        wr(WR_AR4, 16'hA404);
        wr(WR_AR5, 16'hA505);
        wr(WR_AR6, 16'hA606);
        wr(WR_AR7, 16'hA707);
        check128("N ar_all full file", o_ar_all,
                 {16'hA707, 16'hA606, 16'hA505, 16'hA404,
                  16'hA303, 16'hA202, 16'hA101, 16'hA000});

        /*
        o_ar_all is ARP-independent; o_ar tracks ARP. Sweep ARP
        through all eight values and check both each time.
        */
        for (int a = 0; a < 8; a = a + 1) begin
            wr(WR_ARP, {13'd0, a[2:0]});
            check("N arp o_ar", {16'd0, o_ar},
                  {16'd0, 16'hA000 + (a[2:0] * 16'h0101)});
            check128("N arp ar_all stable", o_ar_all,
                     {16'hA707, 16'hA606, 16'hA505, 16'hA404,
                      16'hA303, 16'hA202, 16'hA101, 16'hA000});
        end

        /*
        Indexed read sweep with ARP=0, then with ARP=5: every select
        must return its own register. With the old wiring (ar_rd_i
        tied to o_ar = AR[ARP]) every sel != ARP read the wrong
        register; this is the SAR case (op_hi[2:0] != ARP).
        */
        wr(WR_ARP, 16'h0000);
        for (int s = 0; s < 8; s = s + 1) begin
            ar_rd_run(s[2:0], 16'hA000 + (s[2:0] * 16'h0101));
        end
        wr(WR_ARP, 16'h0005);
        for (int s = 0; s < 8; s = s + 1) begin
            ar_rd_run(s[2:0], 16'hA000 + (s[2:0] * 16'h0101));
        end

        /*
        SAR read-before-ea: AR0 steps *+ from 0xA000, so o_ar_rd
        with sel=0 must read the OLD value in the ea() cycle and
        the NEW value after the edge; sel=3 is unaffected. Two
        ea() steps run, so AR0 ends at 0xA002.
        */
        wr(WR_ARP, 16'h0000);
        ea_ar_rd_run(16'h00A0, 3'd0, 16'hA000, 16'hA000, 16'hA001);
        ea_ar_rd_run(16'h00A0, 3'd3, 16'hA001, 16'hA303, 16'hA303);
        check128("N ar_all after ea", o_ar_all,
                 {16'hA707, 16'hA606, 16'hA505, 16'hA404,
                  16'hA303, 16'hA202, 16'hA101, 16'hA002});

        /*
        Stack observation through 8 pushes, a pop (with the
        pop-copy quirk), a push and a second pop. Push order is
        the same as section H: stack[7] holds the first value.
        */
        reset_dut;
        push(16'h1000);
        push(16'h1001);
        push(16'h1002);
        push(16'h1003);
        push(16'h1004);
        push(16'h1005);
        push(16'h1006);
        push(16'h1007);
        check128("N stack_all 8 pushes", o_stack_all,
                 {16'h1000, 16'h1001, 16'h1002, 16'h1003,
                  16'h1004, 16'h1005, 16'h1006, 16'h1007});
        check("N sp after 8 pushes", {29'd0, o_sp}, 32'd0);
        pop(16'h1007); /* pop-copy: stack[0] <= stack[7] = 0x1000 */
        check128("N stack_all after pop", o_stack_all,
                 {16'h1000, 16'h1001, 16'h1002, 16'h1003,
                  16'h1004, 16'h1005, 16'h1006, 16'h1000});
        check("N sp after pop", {29'd0, o_sp}, 32'd1);
        push(16'h2000); /* sp 1->0, stack[0] <= 0x2000 */
        check128("N stack_all after push", o_stack_all,
                 {16'h1000, 16'h1001, 16'h1002, 16'h1003,
                  16'h1004, 16'h1005, 16'h1006, 16'h2000});
        check("N sp after push", {29'd0, o_sp}, 32'd0);
        pop(16'h2000); /* pop-copy again: stack[0] <= stack[7] */
        check128("N stack_all after pop2", o_stack_all,
                 {16'h1000, 16'h1001, 16'h1002, 16'h1003,
                  16'h1004, 16'h1005, 16'h1006, 16'h1000});
        check("N sp after pop2", {29'd0, o_sp}, 32'd1);

        /*
        ================================================================
        Summary
        ================================================================
        */
        if (errors == 0) begin
            $display("ALL PASS: %0d checks", checks);
        end else begin
            $display("FAILED: %0d of %0d checks", errors, checks);
            $fatal(1, "tb_c5x_addr failed");
        end
        $finish;
    end
endmodule
`default_nettype wire
