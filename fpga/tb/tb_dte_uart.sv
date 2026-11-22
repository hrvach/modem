/* Self-checking test of dte_uart: loopback (txd -> rxd) of 40 random bytes, back to back from the FIFO, plus a glitch on rxd that must be ignored and an
   external transmitter at a slightly off baud (2 %) that must still be received. CLKS_PER_BIT is reduced for speed. */
`timescale 1ns/1ps
module tb_dte_uart;
localparam integer CPB = 20;
reg clk = 0, rst_n = 0;
always #5 clk = ~clk;
reg  rxd = 1;
wire txd, line, rx_valid;
wire [7:0] rx_byte, dropped;
reg        tx_valid = 0;
reg  [7:0] tx_byte = 0;
reg        loop = 1;
wire       rxd_in = loop ? txd : rxd;

dte_uart #(.CLKS_PER_BIT(CPB)) dut (.clk(clk), .rst_n(rst_n), .rxd_i(rxd_in), .txd_o(txd), .line_o(line), .rx_valid_o(rx_valid), .rx_byte_o(rx_byte),
    .tx_valid_i(tx_valid), .tx_byte_i(tx_byte), .dropped_o(dropped));

reg [7:0] sent [0:63];
reg [7:0] got [0:63];
integer ns = 0, ng = 0, errors = 0, i, b;
always @(posedge clk) if (rx_valid) begin got[ng] <= rx_byte; ng <= ng + 1; end

task send_ext(input [7:0] d, input integer bitclks);
    integer k;
    begin
        rxd = 0; repeat (bitclks) @(posedge clk);
        for (k = 0; k < 8; k = k + 1) begin rxd = d[k]; repeat (bitclks) @(posedge clk); end
        rxd = 1; repeat (bitclks) @(posedge clk);
    end
endtask

initial begin
    repeat (4) @(posedge clk); rst_n = 1; repeat (4) @(posedge clk);
    for (i = 0; i < 12; i = i + 1) begin
        @(posedge clk); tx_byte <= $urandom; tx_valid <= 1; @(posedge clk); tx_valid <= 0; sent[ns] = tx_byte; ns = ns + 1;
    end
    repeat (CPB * 10 * 14) @(posedge clk);
    for (i = 0; i < 12; i = i + 1) begin
        @(posedge clk); tx_byte <= $urandom; tx_valid <= 1; @(posedge clk); tx_valid <= 0; sent[ns] = tx_byte; ns = ns + 1;
        repeat (CPB * 10 + 3) @(posedge clk);
    end
    repeat (CPB * 12) @(posedge clk);
    if (ng != ns) begin errors = errors + 1; $display("FAIL loopback count %0d want %0d", ng, ns); end
    for (i = 0; i < ns && i < ng; i = i + 1) if (got[i] !== sent[i]) begin errors = errors + 1; $display("FAIL byte %0d: %h want %h", i, got[i], sent[i]); end
    /* glitch, then external bytes at +-2 % */
    loop = 0; rxd = 1; repeat (10) @(posedge clk);
    ng = 0; ns = 0;
    rxd = 0; repeat (CPB / 4) @(posedge clk); rxd = 1; repeat (CPB * 3) @(posedge clk);
    if (ng != 0) begin errors = errors + 1; $display("FAIL glitch received as a byte"); end
    send_ext(8'hA5, CPB + 0); send_ext(8'h3C, CPB); send_ext(8'hFF, CPB + 1); send_ext(8'h00, CPB - 1);
    repeat (CPB * 3) @(posedge clk);
    if (ng != 4 || got[0] !== 8'hA5 || got[1] !== 8'h3C || got[2] !== 8'hFF || got[3] !== 8'h00) begin errors = errors + 1; $display("FAIL external bytes: n=%0d %h %h %h %h", ng, got[0], got[1], got[2], got[3]); end
    /* overflow: 20 bytes pushed at once, 16 fit (+1 in flight) */
    loop = 1; repeat (CPB * 12) @(posedge clk);
    for (i = 0; i < 20; i = i + 1) begin @(posedge clk); tx_byte <= i[7:0]; tx_valid <= 1; end
    @(posedge clk); tx_valid <= 0;
    if (dropped == 0) begin errors = errors + 1; $display("FAIL overflow not counted"); end
    if (errors == 0) $display("PASS tb_dte_uart"); else $display("FAIL tb_dte_uart: %0d errors", errors);
    $finish;
end
initial begin #20000000; $display("FAIL tb_dte_uart: global timeout"); $finish; end
endmodule
