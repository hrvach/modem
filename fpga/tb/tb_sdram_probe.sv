/* Self-checking test of sdram_probe's start-up calibration and run-time self-test against sdram_arb + sdram16 + chip model. DLY (ns of chip + pad delay) is a parameter:
   9 -> capture setting 0, 15 -> setting 1, 23 -> setting 2, 40 -> no setting works (cal_ok low, cap 0, cal_done still high). EXPECT_CAP / EXPECT_OK say which. */
`timescale 1ns/1ps
module tb_sdram_probe;
parameter integer DLY = 9;
parameter integer EXPECT_CAP = 0;
parameter integer EXPECT_OK = 1;
reg clk = 0, rst_n = 0, run = 0;
always #4.1336 clk = ~clk;
wire rq_req, rq_we, rq_ack, cal_done, cal_ok, ok;
wire [1:0] cap;
wire [2:0] cal_mask;
wire [23:0] rq_addr;
wire [15:0] rq_wdata, arb_rdata, word;
sdram_probe #(.PAUSE_CLKS(200)) dut (.clk(clk), .rst_n(rst_n), .sdram_ready_i(sd_ready), .run_i(run), .rq_req_o(rq_req), .rq_we_o(rq_we), .rq_addr_o(rq_addr), .rq_wdata_o(rq_wdata),
    .rq_ack_i(rq_ack), .rq_rdata_i(arb_rdata), .cap_o(cap), .cal_done_o(cal_done), .cal_ok_o(cal_ok), .cal_mask_o(cal_mask), .word_o(word), .test_ok_o(ok));
wire sd_rd, sd_we, sd_ready, idle_ok, DQ_OE, CKE, SCLK, nCS, nWE, nRAS, nCAS, DQML, DQMH;
wire [1:0] sd_wtbt, BA;
wire [24:0] sd_addr;
wire [15:0] sd_din, sd_dout, DQ_O, DQ_I;
wire [12:0] A;
sdram_arb #(.N(1), .AW(24)) arb (.clk(clk), .rst_n(rst_n), .req_i(rq_req), .we_i(rq_we), .be_i(2'b11), .addr_i(rq_addr), .wdata_i(rq_wdata), .ack_o(rq_ack),
    .rdata_o(arb_rdata), .sd_rd_o(sd_rd), .sd_we_o(sd_we), .sd_wtbt_o(sd_wtbt), .sd_addr_o(sd_addr), .sd_din_o(sd_din), .sd_dout_i(sd_dout), .sd_ready_i(sd_ready));
sdram16 #(.CAS_LATENCY(3'd3), .CYCLES_PER_REFRESH(14'd900)) ctl (.cap_extra(cap), .init(~rst_n), .clk(clk), .SDRAM_DQ_I(DQ_I), .SDRAM_DQ(DQ_O), .SDRAM_DQ_OE(DQ_OE), .SDRAM_A(A),
    .SDRAM_DQML(DQML), .SDRAM_DQMH(DQMH), .SDRAM_BA(BA), .SDRAM_nCS(nCS), .SDRAM_nWE(nWE), .SDRAM_nRAS(nRAS), .SDRAM_nCAS(nCAS), .SDRAM_CKE(CKE),
    .SDRAM_CLK(SCLK), .wtbt(sd_wtbt), .addr(sd_addr), .dout(sd_dout), .din(sd_din), .we(sd_we), .rd(sd_rd), .ready(sd_ready), .idle_ok(idle_ok));
sdram_chip #(.DLY(DLY)) chip (.clk(SCLK), .nCS(nCS), .nRAS(nRAS), .nCAS(nCAS), .nWE(nWE), .BA(BA), .A(A), .DQ_O(DQ_O), .DQ_I(DQ_I));

integer errors = 0;
initial begin
    repeat (20) @(posedge clk); rst_n = 1;
    wait (cal_done);
    repeat (50) @(posedge clk);
    run = 1;
    repeat (20000) @(posedge clk);
    if (cap !== EXPECT_CAP[1:0]) begin errors = errors + 1; $display("FAIL cap %0d want %0d", cap, EXPECT_CAP); end
    if (cal_ok !== EXPECT_OK[0]) begin errors = errors + 1; $display("FAIL cal_ok %b want %0d", cal_ok, EXPECT_OK); end
    if (EXPECT_OK && !ok) begin errors = errors + 1; $display("FAIL run-time test_ok low"); end
    if (EXPECT_OK && word !== 16'hdead) begin errors = errors + 1; $display("FAIL vector word %h (the model returns dead for unwritten words)", word); end
    $display("mask %b DLY %0d: cap %0d cal_ok %b test_ok %b word %h", cal_mask, DLY, cap, cal_ok, ok, word);
    if (errors == 0) $display("PASS tb_sdram_probe"); else $display("FAIL tb_sdram_probe: %0d errors", errors);
    $finish;
end
initial begin #200000000; $display("FAIL tb_sdram_probe: timeout"); $finish; end
endmodule
