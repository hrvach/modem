/* Self-checking test of dbg_status: decodes the serial line at the reduced bit time and checks the line text for two flag patterns, and that lines repeat. */
`timescale 1ns/1ps
module tb_dbg_status;
localparam integer CPB = 20;
reg clk = 0;
always #10 clk = ~clk;
reg  [6:0] flags = 7'b1010011;
reg [19:0] pca = 20'hFFFF0;
reg [15:0] pcq = 16'h8004;
reg [15:0] wds = 16'h1234;
reg [15:0] vec = 16'hEA00;
reg        tok = 1'b1;
reg  [1:0] cap = 2'd1;
reg        cok = 1'b1;
reg  [2:0] msk = 3'b010;
reg        jl = 1'b1;
reg [19:0] jf = 20'h0107E, jt = 20'h13A8A;
wire [5:0] tidx;
reg [37:0] tdat = {1'b0, 1'b1, 20'h12345, 16'hABCD};
reg [8*20-1:0] dl;
wire tx;
dbg_status #(.CLKS_PER_BIT(CPB), .PERIOD_CLKS(3000)) dut (.clk(clk), .flags_i(flags), .pc186_i(pca), .pcdsp_i(pcq), .words_i(wds), .vec_i(vec), .test_ok_i(tok), .cap_i(cap), .cal_ok_i(cok), .mask_i(msk), .jlat_i(jl), .jfrom_i(jf), .jto_i(jt), .icu_i(25'h0123456), .int0_i(16'hABCD), .texp_i(16'h0042), .frames_i(16'h0F0F), .rxc_i(16'h0003), .txc_i(16'h0007), .duty_i(16'h8000), .dxrc_i(16'h1234), .dacc_i(16'h00AB), .peak_i(16'h7FFF), .dspg_i(64'h0123456789ABCDEF), .tr_idx_o(tidx), .tr_data_i(tdat), .tx_o(tx));

reg [8*168-1:0] line;
integer n = 0, nlines = 0, errors = 0, k, m;
reg [7:0] b;
task rx_byte(output [7:0] v);
    integer i;
    begin
        @(negedge tx);
        repeat (CPB + CPB / 2) @(posedge clk);
        for (i = 0; i < 8; i = i + 1) begin v[i] = tx; repeat (CPB) @(posedge clk); end
    end
endtask
initial begin
    for (k = 0; k < 2; k = k + 1) begin
        line = 0;
        for (n = 0; n < 168; n = n + 1) begin rx_byte(b); line = {line[8*167-1:0], b}; end
        $display("line: %0s", line);
        if (k == 0 && line[8*168-1:0] !== "[P1 X0 R1 S0 L0 D1 B1 A=FFFF0 Q=8004 N=1234 W=EA00 K1 M2 T1 J=0107E>13A8A I=0123456 O=ABCD E=0042 F=0F0F R=0003 X=0007 D=8000 C=1234 Y=00AB Z=7FFF G=0123456789ABCDEF]\r\n") begin errors = errors + 1; $display("FAIL line 0"); end
        if (k == 0) begin
            /* jl is set: 64 bus-trace lines follow the status line */
            for (m = 0; m < 64; m = m + 1) begin
                dl = 0;
                for (n = 0; n < 19; n = n + 1) begin rx_byte(b); dl = {dl[8*19-1:0], b}; end
                if (m == 0 && dl[8*19-1:0] !== "#00 Rw 12345 ABCD\r\n") begin errors = errors + 1; $display("FAIL dump 0: %0s", dl); end
                if (m == 63 && dl[8*19-1:0] !== "#3F Rw 12345 ABCD\r\n") begin errors = errors + 1; $display("FAIL dump 63: %0s", dl); end
            end
        end
        flags = 7'b0101100; pca = 20'h0BEEF; pcq = 16'h0A5C; wds = 16'h0001; vec = 16'h0000; tok = 0; cok = 0; msk = 3'b000; jl = 0; jf = 20'd0; jt = 20'd0;
    end
    if (line[8*168-1:0] !== "[P0 X1 R0 S1 L1 D0 B0 A=0BEEF Q=0A5C N=0001 W=0000 Kx M0 T0 J-00000>00000 I=0123456 O=ABCD E=0042 F=0F0F R=0003 X=0007 D=8000 C=1234 Y=00AB Z=7FFF G=0123456789ABCDEF]\r\n") begin errors = errors + 1; $display("FAIL line 1"); end
    if (errors == 0) $display("PASS tb_dbg_status"); else $display("FAIL tb_dbg_status: %0d errors", errors);
    $finish;
end
initial begin #20000000; $display("FAIL tb_dbg_status: timeout"); $finish; end
endmodule
