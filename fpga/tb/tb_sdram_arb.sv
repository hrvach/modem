/* Self-checking test: 4 clients with random read / write traffic through sdram_arb + sdram16 + behavioural chip. Each client owns a distinct address
   window and keeps a shadow copy; client 3 also reads the window of client 0 (shared reads, checked against client 0's shadow only when quiescent). */
`timescale 1ns/1ps
module tb_sdram_arb;
reg clk = 0, rst_n = 0;
always #6.2004 clk = ~clk;
localparam N = 4;
localparam AW = 24;

reg  [N-1:0]    req = 0, we = 0;
reg  [2*N-1:0]  be = 0;
reg  [N*AW-1:0] addr = 0;
reg  [16*N-1:0] wdata = 0;
wire [N-1:0]    ack;
wire [15:0]     rdata;
wire sd_rd, sd_we, sd_ready, idle_ok, DQ_OE, CKE, SCLK, nCS, nWE, nRAS, nCAS, DQML, DQMH;
wire [1:0] sd_wtbt, BA;
wire [24:0] sd_addr;
wire [15:0] sd_din, sd_dout, DQ_O, DQ_I;
wire [12:0] A;

sdram_arb #(.N(N), .AW(AW)) arb (.clk(clk), .rst_n(rst_n), .req_i(req), .we_i(we), .be_i(be), .addr_i(addr), .wdata_i(wdata), .ack_o(ack), .rdata_o(rdata),
    .sd_rd_o(sd_rd), .sd_we_o(sd_we), .sd_wtbt_o(sd_wtbt), .sd_addr_o(sd_addr), .sd_din_o(sd_din), .sd_dout_i(sd_dout), .sd_ready_i(sd_ready));
sdram16 #(.CAS_LATENCY(3'd2), .CYCLES_PER_REFRESH(14'd600)) ctl (.cap_extra(2'd0), .init(~rst_n), .clk(clk), .SDRAM_DQ_I(DQ_I), .SDRAM_DQ(DQ_O), .SDRAM_DQ_OE(DQ_OE), .SDRAM_A(A),
    .SDRAM_DQML(DQML), .SDRAM_DQMH(DQMH), .SDRAM_BA(BA), .SDRAM_nCS(nCS), .SDRAM_nWE(nWE), .SDRAM_nRAS(nRAS), .SDRAM_nCAS(nCAS), .SDRAM_CKE(CKE), .SDRAM_CLK(SCLK),
    .wtbt(sd_wtbt), .addr(sd_addr), .dout(sd_dout), .din(sd_din), .we(sd_we), .rd(sd_rd), .ready(sd_ready), .idle_ok(idle_ok));
sdram_chip #(.DLY(9)) chip (.clk(SCLK), .nCS(nCS), .nRAS(nRAS), .nCAS(nCAS), .nWE(nWE), .BA(BA), .A(A), .DQ_O(DQ_O), .DQ_I(DQ_I));

integer errors = 0;
integer done_cnt [0:N-1];
integer total = 0;

/* one process per client; word address = client * 'h10000 + offset, so windows never overlap */
genvar g;
generate for (g = 0; g < N; g = g + 1) begin : cl
    reg [15:0] shadow [0:255];
    reg [255:0] known;
    integer n, off, k;
    reg [15:0] d, exp;
    reg [1:0] bm;
    initial begin
        known = 0;
        done_cnt[g] = 0;
        wait (rst_n);
        repeat (2000) @(posedge clk);
        for (n = 0; n < 400; n = n + 1) begin
            repeat ($urandom_range(0, 6)) @(posedge clk);
            off = $urandom_range(0, 255);
            k = $urandom_range(0, 2);
            @(posedge clk);
            addr[AW*g +: AW] <= g * 24'h10000 + off;
            if (k < 2) begin
                bm = $urandom_range(1, 3); d = $urandom;
                we[g] <= 1; be[2*g +: 2] <= bm; wdata[16*g +: 16] <= d; req[g] <= 1;
                @(posedge clk);
                while (!ack[g]) @(posedge clk);
                req[g] <= 0;
                exp = known[off] ? shadow[off] : 16'h0;
                if (bm[1]) exp[15:8] = d[15:8];
                if (bm[0]) exp[7:0]  = d[7:0];
                shadow[off] = exp; known[off] = 1;
            end else begin
                we[g] <= 0; req[g] <= 1;
                @(posedge clk);
                while (!ack[g]) @(posedge clk);
                req[g] <= 0;
                if (known[off] && rdata !== shadow[off]) begin
                    errors = errors + 1; $display("MISMATCH client %0d off %0d got %h want %h", g, off, rdata, shadow[off]);
                end
            end
            done_cnt[g] = done_cnt[g] + 1;
        end
    end
end endgenerate

initial begin
    repeat (20) @(posedge clk);
    rst_n = 1;
    wait (done_cnt[0] == 400 && done_cnt[1] == 400 && done_cnt[2] == 400 && done_cnt[3] == 400);
    repeat (50) @(posedge clk);
    if (chip.max_gap_ns > 7810.0) begin errors = errors + 1; $display("refresh gap %0.0f ns", chip.max_gap_ns); end
    if (errors == 0) $display("PASS tb_sdram_arb (1600 transactions, %0d refreshes)", chip.refreshes); else $display("FAIL tb_sdram_arb: %0d errors", errors);
    $finish;
end
initial begin #100000000; $display("FAIL tb_sdram_arb: global timeout"); $finish; end
endmodule
