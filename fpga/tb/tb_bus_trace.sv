/* Self-checking test of bus_trace: 70 events, freeze, the ring holds the last 64 oldest-first, nothing is recorded after the freeze. */
`timescale 1ns/1ps
module tb_bus_trace;
reg clk = 0, rst_n = 0, ev = 0, wr = 0, word = 0, fr = 0;
reg [19:0] addr = 0;
reg [15:0] data = 0;
reg [5:0] idx = 0;
wire [37:0] q;
always #5 clk = ~clk;
bus_trace dut (.clk(clk), .rst_n(rst_n), .ev_i(ev), .wr_i(wr), .word_i(word), .addr_i(addr), .data_i(data), .freeze_i(fr), .rd_idx_i(idx), .rd_data_o(q));
integer i, errors = 0;
reg [37:0] exp;
initial begin
    repeat (4) @(posedge clk); rst_n = 1;
    for (i = 0; i < 70; i = i + 1) begin
        @(negedge clk); ev = 1; wr = i[0]; word = ~i[0]; addr = 20'h10000 + i; data = 16'hA000 + i;
        @(negedge clk); ev = 0;
    end
    @(negedge clk); fr = 1;
    @(negedge clk); ev = 1; addr = 20'hFFFFF; data = 16'hDEAD;      /* after the freeze: must be ignored */
    @(negedge clk); ev = 0;
    repeat (3) @(posedge clk);
    for (i = 0; i < 64; i = i + 1) begin
        idx = i; repeat (2) @(posedge clk); #1;
        exp = {((i + 6) % 2 == 1) ? 1'b1 : 1'b0, ((i + 6) % 2 == 0) ? 1'b1 : 1'b0, 20'(20'h10000 + i + 6), 16'(16'hA000 + i + 6)};
        if (q !== exp) begin
            errors = errors + 1; if (errors < 5) $display("FAIL idx %0d: %h", i, q);
        end
    end
    if (errors == 0) $display("PASS tb_bus_trace"); else $display("FAIL tb_bus_trace: %0d errors", errors);
    $finish;
end
initial begin #1000000; $display("FAIL tb_bus_trace: timeout"); $finish; end
endmodule
