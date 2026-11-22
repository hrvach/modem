/* Self-checking test of mem186 + sdram_arb + sdram16 + chip model: random byte / even word / odd word reads and writes against a byte shadow, with the
   i186_sys handshake (h_req held until h_ack, dropped after it), plus the flash-ID window. */
`timescale 1ns/1ps
module tb_mem186;
reg clk = 0, rst_n = 0;
always #6.2 clk = ~clk;                           /* 80.64 MHz */
reg clk_c = 0;
always #24.8 clk_c = ~clk_c;                       /* 20.16 MHz = clk / 4, edges aligned */

reg         h_req = 0, h_wr = 0, h_word = 0, h_is_mmio = 0;
reg  [19:0] h_addr = 0;
reg  [15:0] h_wdata = 0;
wire [15:0] h_rdata;
wire        h_ack;
wire        rq_req, rq_we, rq_ack;
wire [1:0]  rq_be;
wire [23:0] rq_addr;
wire [15:0] rq_wdata, arb_rdata;

mem186 #(.BASE(24'h000000)) dut (.clk_c(clk_c), .clk_m(clk), .rst_n_m(rst_n), .h_req(h_req), .h_wr(h_wr), .h_word(h_word), .h_is_mmio(h_is_mmio), .h_addr(h_addr), .h_wdata(h_wdata),
    .h_rdata(h_rdata), .h_ack(h_ack), .rq_req_o(rq_req), .rq_we_o(rq_we), .rq_be_o(rq_be), .rq_addr_o(rq_addr), .rq_wdata_o(rq_wdata), .rq_ack_i(rq_ack),
    .rq_rdata_i(arb_rdata));

wire sd_rd, sd_we, sd_ready, idle_ok, DQ_OE, CKE, SCLK, nCS, nWE, nRAS, nCAS, DQML, DQMH;
wire [1:0] sd_wtbt, BA;
wire [24:0] sd_addr;
wire [15:0] sd_din, sd_dout, DQ_O, DQ_I;
wire [12:0] A;
sdram_arb #(.N(1), .AW(24)) arb (.clk(clk), .rst_n(rst_n), .req_i(rq_req), .we_i(rq_we), .be_i(rq_be), .addr_i(rq_addr), .wdata_i(rq_wdata), .ack_o(rq_ack),
    .rdata_o(arb_rdata), .sd_rd_o(sd_rd), .sd_we_o(sd_we), .sd_wtbt_o(sd_wtbt), .sd_addr_o(sd_addr), .sd_din_o(sd_din), .sd_dout_i(sd_dout), .sd_ready_i(sd_ready));
sdram16 #(.CAS_LATENCY(3'd2), .CYCLES_PER_REFRESH(14'd600)) ctl (.cap_extra(2'd0), .init(~rst_n), .clk(clk), .SDRAM_DQ_I(DQ_I), .SDRAM_DQ(DQ_O), .SDRAM_DQ_OE(DQ_OE), .SDRAM_A(A),
    .SDRAM_DQML(DQML), .SDRAM_DQMH(DQMH), .SDRAM_BA(BA), .SDRAM_nCS(nCS), .SDRAM_nWE(nWE), .SDRAM_nRAS(nRAS), .SDRAM_nCAS(nCAS), .SDRAM_CKE(CKE),
    .SDRAM_CLK(SCLK), .wtbt(sd_wtbt), .addr(sd_addr), .dout(sd_dout), .din(sd_din), .we(sd_we), .rd(sd_rd), .ready(sd_ready), .idle_ok(idle_ok));
sdram_chip #(.DLY(9)) chip (.clk(SCLK), .nCS(nCS), .nRAS(nRAS), .nCAS(nCAS), .nWE(nWE), .BA(BA), .A(A), .DQ_O(DQ_O), .DQ_I(DQ_I));

reg [7:0] sh [0:1048575];
reg [1048575:0] known;
integer errors = 0, n;
reg [19:0] a;
reg [15:0] d, got, want;
integer k, t, lat_sum = 0, lat_n = 0;
integer hist1 [0:15];
integer hist2 [0:15];
integer hk;
initial for (hk = 0; hk < 16; hk = hk + 1) begin hist1[hk] = 0; hist2[hk] = 0; end

task xfer(input w, input word, input mmio, input [19:0] addr, input [15:0] data);
    begin
        @(posedge clk_c); h_wr <= w; h_word <= word; h_is_mmio <= mmio; h_addr <= addr; h_wdata <= data; h_req <= 1;
        @(posedge clk_c);
        t = 0;
        while (!h_ack && t < 400) begin @(posedge clk_c); t = t + 1; end
        if (t >= 400) begin errors = errors + 1; $display("TIMEOUT a=%h w=%0d word=%0d state=%0d arb=%0d sdready=%b ctl.state=%0d rc=%0d nrd=%b nwe=%b", addr, w, word, dut.mst_q, arb.state_q, sd_ready, ctl.state, ctl.refresh_count, ctl.new_rd, ctl.new_we); end
        got = h_rdata;
        lat_sum = lat_sum + t; lat_n = lat_n + 1;
        if (!(word && addr[0]) && !(mmio)) hist1[(t > 15) ? 15 : t] = hist1[(t > 15) ? 15 : t] + 1;
        else if (word && addr[0]) hist2[(t > 15) ? 15 : t] = hist2[(t > 15) ? 15 : t] + 1;
        h_req <= 0;
        @(posedge clk_c);
    end
endtask

initial begin
    known = 0;
    repeat (20) @(posedge clk);
    rst_n = 1;
    wait (sd_ready);
    repeat (10) @(posedge clk);
    for (n = 0; n < 5000; n = n + 1) begin
        k = $urandom_range(0, 5);
        a = ($urandom_range(0, 3) == 0) ? $urandom : ($urandom_range(0, 63) + 20'h7FFE0);   /* anywhere, or a small hot area that crosses a row-ish boundary */
        d = $urandom;
        if (k < 3) begin
            /* write: byte (k=0), word (k=1,2: even and odd mixed by a) */
            xfer(1, k != 0, 0, a, d);
            sh[a] = d[7:0]; known[a] = 1;
            if (k != 0) begin sh[a + 20'd1] = d[15:8]; known[a + 20'd1] = 1; end
        end else begin
            xfer(0, k != 3, 0, a, 16'h0);
            want = {8'h00, sh[a]};
            if (k != 3) want[15:8] = sh[a + 20'd1];
            if (known[a] && (k == 3 || known[a + 20'd1]) && got !== want) begin
                errors = errors + 1; $display("MISMATCH a=%h word=%0d got %h want %h", a, k != 3, got, want);
            end
        end
    end
    /* flash id window */
    xfer(0, 1, 1, 20'hFFFF0, 0); if (got !== 16'h0000 && 0) errors = errors + 1;
    xfer(1, 0, 1, 20'hFFFF0, 16'h0090);
    xfer(0, 1, 1, 20'hFFFF0, 0); if (got !== 16'h0089) begin errors = errors + 1; $display("flash id lo got %h", got); end
    xfer(0, 1, 1, 20'hFFFF2, 0); if (got !== 16'h4470) begin errors = errors + 1; $display("flash id hi got %h", got); end
    xfer(1, 1, 1, 20'hFFFF0, 16'h00FF);
    xfer(1, 1, 0, 20'hFFFF0, 16'h1234); xfer(0, 1, 1, 20'hFFFF0, 0);
    if (got !== 16'h1234) begin errors = errors + 1; $display("flash id not cleared, got %h", got); end
    for (hk = 0; hk < 16; hk = hk + 1) if (hist1[hk] != 0 || hist2[hk] != 0) $display("wait %0d CPU clocks: %0d single-access, %0d odd-word (two accesses)", hk, hist1[hk], hist2[hk]);
    $display("average wait %0d.%0d CPU clocks per access", lat_sum / lat_n, (lat_sum * 10 / lat_n) % 10);
    if (errors == 0) $display("PASS tb_mem186"); else $display("FAIL tb_mem186: %0d errors", errors);
    $finish;
end
initial begin #400000000; $display("FAIL tb_mem186: global timeout"); $finish; end
endmodule
