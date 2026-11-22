/* Self-checking test of c5x_xmem + sdram_arb + sdram16 + chip model. The testbench plays the part of the DSP top: ce = ready_o and at least 2 clocks
   since the last ce. At each ce edge the previous operation completes (a read is checked against a 64K shadow, a write updates it) and the next one
   is presented. Mixed footprints: a small hot window (hits, write hits) and the whole 64K space (misses, fills, evictions); host writes in between. */
`timescale 1ns/1ps
module tb_c5x_xmem;
reg clk = 0, rst_n = 0;
always #4.1336 clk = ~clk;                 /* 120.96 MHz */

reg         rd_en = 0, wr_en = 0, hw_en = 0;
reg  [15:0] raddr = 0, waddr = 0, wdata = 0, hw_addr = 0, hw_data = 0;
wire [15:0] rdata;
wire        ready, hw_ready, ce;
integer     since_ce = 0;
assign ce = ready && since_ce >= 2;

wire        rq_req, wq_req, rq_ack, wq_ack;
wire [23:0] rq_addr, wq_addr;
wire [15:0] wq_wdata, arb_rdata;

c5x_xmem #(.BASE(24'h0C0000)) dut (.clk(clk), .rst_n(rst_n), .ce_i(ce), .rd_en_i(rd_en), .raddr_i(raddr), .wr_en_i(wr_en), .waddr_i(waddr), .wdata_i(wdata),
    .rdata_o(rdata), .ready_o(ready), .hw_en_i(hw_en), .hw_addr_i(hw_addr), .hw_data_i(hw_data), .hw_ready_o(hw_ready),
    .rq_req_o(rq_req), .rq_addr_o(rq_addr), .rq_ack_i(rq_ack), .rq_rdata_i(arb_rdata),
    .wq_req_o(wq_req), .wq_addr_o(wq_addr), .wq_wdata_o(wq_wdata), .wq_ack_i(wq_ack));

wire sd_rd, sd_we, sd_ready, idle_ok, DQ_OE, CKE, SCLK, nCS, nWE, nRAS, nCAS, DQML, DQMH;
wire [1:0] sd_wtbt, BA;
wire [24:0] sd_addr;
wire [15:0] sd_din, sd_dout, DQ_O, DQ_I;
wire [12:0] A;
wire [1:0] ack2;
assign rq_ack = ack2[0];
assign wq_ack = ack2[1];

/* client 0 = fill reads (priority), client 1 = writes */
sdram_arb #(.N(2), .AW(24)) arb (.clk(clk), .rst_n(rst_n), .req_i({wq_req, rq_req}), .we_i(2'b10), .be_i({2'b11, 2'b11}), .addr_i({wq_addr, rq_addr}),
    .wdata_i({wq_wdata, 16'h0}), .ack_o(ack2), .rdata_o(arb_rdata), .sd_rd_o(sd_rd), .sd_we_o(sd_we), .sd_wtbt_o(sd_wtbt), .sd_addr_o(sd_addr),
    .sd_din_o(sd_din), .sd_dout_i(sd_dout), .sd_ready_i(sd_ready));
sdram16 #(.CAS_LATENCY(3'd3), .CYCLES_PER_REFRESH(14'd900)) ctl (.cap_extra(2'd0), .init(~rst_n), .clk(clk), .SDRAM_DQ_I(DQ_I), .SDRAM_DQ(DQ_O), .SDRAM_DQ_OE(DQ_OE), .SDRAM_A(A),
    .SDRAM_DQML(DQML), .SDRAM_DQMH(DQMH), .SDRAM_BA(BA), .SDRAM_nCS(nCS), .SDRAM_nWE(nWE), .SDRAM_nRAS(nRAS), .SDRAM_nCAS(nCAS), .SDRAM_CKE(CKE),
    .SDRAM_CLK(SCLK), .wtbt(sd_wtbt), .addr(sd_addr), .dout(sd_dout), .din(sd_din), .we(sd_we), .rd(sd_rd), .ready(sd_ready), .idle_ok(idle_ok));
sdram_chip #(.DLY(9)) chip (.clk(SCLK), .nCS(nCS), .nRAS(nRAS), .nCAS(nCAS), .nWE(nWE), .BA(BA), .A(A), .DQ_O(DQ_O), .DQ_I(DQ_I));

reg [15:0] shadow [0:65535];
reg [65535:0] known;
integer errors = 0, nops = 0, nrd = 0, nwr = 0, nhw = 0, stalls = 0, hits_fast = 0;
integer i;
reg        cur_rd, cur_wr;
reg [15:0] cur_raddr, cur_waddr, cur_wdata;
reg [15:0] a, wd;
integer    kind, win;

always @(posedge clk) begin
    if (!rst_n) since_ce <= 0; else if (ce) since_ce <= 0; else since_ce <= since_ce + 1;
    if (rst_n && !ready && since_ce >= 2) stalls <= stalls + 1;

    if (ce) begin
        /* complete the operation presented during the previous period */
        if (cur_rd) begin
            nrd = nrd + 1;
            if ($test$plusargs("trace") && cur_raddr[15:3] == 13'h100b) $display("%0t RD %h got %h shadow %h", $time, cur_raddr, rdata, shadow[cur_raddr]);
            if (known[cur_raddr] && rdata !== shadow[cur_raddr]) begin
                errors = errors + 1;
                if (errors < 20) $display("MISMATCH read %h got %h want %h", cur_raddr, rdata, shadow[cur_raddr]);
            end
        end
        if (cur_wr) begin
            nwr = nwr + 1;
            if ($test$plusargs("trace") && cur_waddr[15:3] == 13'h100b) $display("%0t WR %h %h", $time, cur_waddr, cur_wdata);
            shadow[cur_waddr] = cur_wdata; known[cur_waddr] = 1;
        end
        nops = nops + 1;
        /* present the next one (below) */
        kind = $urandom_range(0, 9);
        win  = $urandom_range(0, 3);
        a = (win == 0) ? ($urandom_range(0, 255) + 16'h8000) : $urandom;      /* hot window or anywhere */
        cur_rd <= 0; cur_wr <= 0; rd_en <= 0; wr_en <= 0;
        if (kind < 6) begin
            cur_rd <= 1; rd_en <= 1; raddr <= a; cur_raddr <= a; waddr <= $urandom;
        end else if (kind < 9) begin
            cur_wr <= 1; wr_en <= 1; waddr <= a; cur_waddr <= a; wd = $urandom; wdata <= wd; cur_wdata <= wd; raddr <= $urandom;
        end
        if (kind == 9 && !hw_en) begin
            hw_en <= 1; hw_addr <= (win == 0) ? ($urandom_range(0, 255) + 16'h8000) : $urandom; hw_data <= $urandom;
        end
    end

    /* host write is taken in a clock where hw_ready is high; a DSP read completing in the same clock still sees the old word, so this comes after the ce handling */
    if (hw_en && hw_ready) begin
        if ($test$plusargs("trace") && hw_addr[15:3] == 13'h100b) $display("%0t HW %h %h", $time, hw_addr, hw_data);
        shadow[hw_addr] = hw_data; known[hw_addr] = 1; nhw = nhw + 1;
        hw_en <= 0;
    end
end
initial begin
    known = 0; cur_rd = 0; cur_wr = 0;
    repeat (20) @(posedge clk);
    rst_n = 1;
    wait (nops == 20000);
    rd_en = 0; wr_en = 0;
    repeat (200) @(posedge clk);
    $display("ops %0d reads %0d writes %0d host writes %0d, stall clocks %0d, refreshes %0d", nops, nrd, nwr, nhw, stalls, chip.refreshes);
    if (errors == 0) $display("PASS tb_c5x_xmem"); else $display("FAIL tb_c5x_xmem: %0d errors", errors);
    $finish;
end
initial begin #400000000; $display("FAIL tb_c5x_xmem: global timeout (ops %0d)", nops); $finish; end
endmodule
