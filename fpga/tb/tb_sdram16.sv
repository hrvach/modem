/* Self-checking test of the sdram16 controller at 80.64 MHz against a behavioural SDR SDRAM: random byte-masked writes and reads checked
   against a shadow copy, plus the refresh interval (every row must be refreshed within 64 ms: 8192 refreshes, i.e. one per 7.81 us on average).
   tests/Makefile builds sdram.sv through a sed that splits the tristate SDRAM_DQ into SDRAM_DQ_I / SDRAM_DQ / SDRAM_DQ_OE (Verilator limitation). */
`timescale 1ns/1ps
module tb_sdram16;
parameter integer DLY = 9;
parameter integer EXTRA = 0;                /* sdram16 CAPTURE_EXTRA */
parameter integer CL = 2;                   /* 2 for 80.64 MHz, 3 for 120.96 MHz */
parameter real HALF = 6.2004;               /* half clock period, ns: 6.2004 = 80.64 MHz, 4.1336 = 120.96 MHz */                  /* clock-out + tAC + pad delay to the controller input, ns (real: 8..12) */
reg clk = 0, init = 1;
always #HALF clk = ~clk;

reg         we = 0, rd = 0;
reg  [24:0] addr = 0;
reg  [1:0]  wtbt = 0;
reg  [15:0] din = 0;
wire [15:0] dout, DQ_O, DQ_I;
wire        ready, idle_ok, DQ_OE, CKE, SCLK, nCS, nWE, nRAS, nCAS, DQML, DQMH;
wire [12:0] A;
wire [1:0]  BA;

sdram16 #(.CAS_LATENCY(CL), .CYCLES_PER_REFRESH(CL == 2 ? 600 : 900)) ctl (.init(init), .cap_extra(EXTRA[1:0]), .clk(clk), .SDRAM_DQ_I(DQ_I), .SDRAM_DQ(DQ_O), .SDRAM_DQ_OE(DQ_OE), .SDRAM_A(A), .SDRAM_DQML(DQML), .SDRAM_DQMH(DQMH),
             .SDRAM_BA(BA), .SDRAM_nCS(nCS), .SDRAM_nWE(nWE), .SDRAM_nRAS(nRAS), .SDRAM_nCAS(nCAS), .SDRAM_CKE(CKE), .SDRAM_CLK(SCLK),
             .wtbt(wtbt), .addr(addr), .dout(dout), .din(din), .we(we), .rd(rd), .ready(ready), .idle_ok(idle_ok));

sdram_chip #(.DLY(DLY)) chip (.clk(SCLK), .nCS(nCS), .nRAS(nRAS), .nCAS(nCAS), .nWE(nWE), .BA(BA), .A(A), .DQ_O(DQ_O), .DQ_I(DQ_I));

integer errors = 0, reads = 0, writes = 0, n, i, k;
reg [15:0] shadow [longint];
reg [24:1] pool [0:63];
reg [24:1] a;
reg [15:0] d, exp;
reg [1:0]  bm;

task xfer_w(input [24:1] w_addr, input [1:0] w_be, input [15:0] w_d);
    begin
        @(posedge clk); addr <= {w_addr, 1'b0}; wtbt <= w_be; din <= w_d; we <= 1;
        @(posedge clk); we <= 0;
        repeat (2) @(posedge clk);
        while (!ready) @(posedge clk);
        writes = writes + 1;
    end
endtask

task xfer_r(input [24:1] r_addr);
    begin
        @(posedge clk); addr <= {r_addr, 1'b0}; rd <= 1;
        @(posedge clk); rd <= 0;
        repeat (2) @(posedge clk);
        while (!ready) @(posedge clk);
        reads = reads + 1;
    end
endtask

initial begin
    repeat (20) @(posedge clk);
    init = 0;
    wait (ready);
    repeat (50) @(posedge clk);
    if (chip.mode[6:4] !== CL) begin errors = errors + 1; $display("MODE REGISTER: CAS latency %0d, want %0d", chip.mode[6:4], CL); end
    for (i = 0; i < 64; i = i + 1) pool[i] = {$urandom_range(0, 3), $urandom_range(0, 1023), $urandom_range(0, 511)};   /* banks, rows, columns */
    for (n = 0; n < 6000; n = n + 1) begin
        a = pool[$urandom_range(0, 63)];
        k = $urandom_range(0, 2);
        if (k < 2) begin
            bm = $urandom_range(1, 3); d = $urandom;
            xfer_w(a, bm, d);
            exp = shadow.exists(a) ? shadow[a] : 16'h0;
            if (bm[1]) exp[15:8] = d[15:8];
            if (bm[0]) exp[7:0]  = d[7:0];
            shadow[a] = exp;
        end else begin
            xfer_r(a);
            if (shadow.exists(a) && dout !== shadow[a]) begin
                errors = errors + 1; $display("MISMATCH a=%h got=%h want=%h", a, dout, shadow[a]);
            end
        end
    end
    /* idle for several refresh intervals, then everything must still read back */
    repeat (20000) @(posedge clk);
    for (i = 0; i < 64; i = i + 1) begin
        xfer_r(pool[i]);
        if (shadow.exists(pool[i]) && dout !== shadow[pool[i]]) begin errors = errors + 1; $display("MISMATCH after idle a=%h", pool[i]); end
    end
    if (chip.refreshes < 10) begin errors = errors + 1; $display("only %0d refreshes", chip.refreshes); end
    /* average interval over the whole run, idle and busy: 8192 refreshes must fit in 64 ms */
    if ($realtime - chip.first_ref > chip.refreshes * 7810.0) begin errors = errors + 1; $display("average refresh interval %0.0f ns > 7810 ns", ($realtime - chip.first_ref) / chip.refreshes); end
    if (chip.max_gap_ns > 7810.0) begin errors = errors + 1; $display("refresh gap %0.0f ns > 7810 ns", chip.max_gap_ns); end
    $display("reads %0d writes %0d refreshes %0d max refresh gap %0.0f ns", reads, writes, chip.refreshes, chip.max_gap_ns);
    if (errors == 0) $display("PASS tb_sdram16"); else $display("FAIL tb_sdram16: %0d errors", errors);
    $finish;
end
initial begin #200000000; $display("FAIL tb_sdram16: global timeout"); $finish; end
endmodule
