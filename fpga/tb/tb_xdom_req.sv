/* Self-checking test of xdom_req: a 25.8 MHz client talks through the crossing to a stub arbiter on the 4x faster, phase-aligned clock that acks after a random
   number of fast clocks. 300 random transactions (writes keep their payload, reads get the data the stub makes from the address); payload and data must match,
   every request must get exactly one ack and nothing is acked without a request. */
`timescale 1ns/1ps
module tb_xdom_req;
reg clk_m = 0, clk_c = 0;
reg [1:0] div = 0;
always #4.8445 clk_m = ~clk_m;
always @(posedge clk_m) begin div <= div + 1; end
always @(posedge clk_m) if (div == 2'd1) clk_c <= 1'b1; else if (div == 2'd3) clk_c <= 1'b0;   /* rises with every 4th fast edge, aligned */
reg rst_n = 0;
reg req = 0, we = 0; reg [1:0] be = 0; reg [23:0] addr = 0; reg [15:0] wdata = 0;
wire ack; wire [15:0] rdata;
wire req_o, we_o; wire [1:0] be_o; wire [23:0] addr_o; wire [15:0] wdata_o;
reg ack_i = 0; reg [15:0] rdata_i = 0;
xdom_req dut (.clk_c(clk_c), .rst_c_n(rst_n), .clk_m(clk_m), .rst_m_n(rst_n), .req_i(req), .we_i(we), .be_i(be), .addr_i(addr), .wdata_i(wdata), .ack_o(ack), .rdata_o(rdata),
    .req_o(req_o), .we_o(we_o), .be_o(be_o), .addr_o(addr_o), .wdata_o(wdata_o), .ack_i(ack_i), .rdata_i(rdata_i));

/* stub arbiter */
integer wait_n = 0, served = 0, errors = 0;
reg busy = 0;
always @(posedge clk_m) begin
    ack_i <= 0;
    if (req_o && !busy && !ack_i) begin busy <= 1; wait_n <= $urandom_range(1, 14); end
    else if (busy) begin
        if (wait_n == 0) begin
            ack_i <= 1; busy <= 0; served <= served + 1;
            rdata_i <= we_o ? 16'h0 : (addr_o[15:0] ^ 16'h5A5A);
            if (we_o !== we || be_o !== be || addr_o !== addr || (we_o && wdata_o !== wdata)) begin errors <= errors + 1; $display("FAIL payload at %0t: we %b/%b be %b/%b addr %h/%h wd %h/%h", $time, we_o, we, be_o, be, addr_o, addr, wdata_o, wdata); end
        end else wait_n <= wait_n - 1;
    end
end
integer acks = 0;
always @(posedge clk_c) if (ack) acks <= acks + 1;

integer i;
initial begin
    repeat (8) @(posedge clk_c); rst_n = 1; repeat (4) @(posedge clk_c);
    for (i = 0; i < 300; i = i + 1) begin
        @(posedge clk_c); #1;
        we = $urandom; be = $urandom; addr = $urandom; wdata = $urandom; req = 1;
        @(posedge clk_c);
        while (!ack) begin @(posedge clk_c); end
        if (!we && rdata !== (addr[15:0] ^ 16'h5A5A)) begin errors = errors + 1; $display("FAIL read data %h for addr %h", rdata, addr); end
        #1 req = 0;
        repeat ($urandom_range(0, 3)) @(posedge clk_c);
    end
    repeat (20) @(posedge clk_c);
    if (acks !== 300 || served !== 300) begin errors = errors + 1; $display("FAIL counts: acks %0d served %0d", acks, served); end
    if (errors == 0) $display("PASS tb_xdom_req"); else $display("FAIL tb_xdom_req: %0d errors", errors);
    $finish;
end
initial begin #20000000; $display("FAIL tb_xdom_req: timeout"); $finish; end
endmodule
