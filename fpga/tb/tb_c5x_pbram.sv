/* Self-checking test of c5x_pbram against a shadow array: random DSP reads / writes with the ce_i / ready_o protocol of the DSP core (the access is presented until
   ready_o, the read data is sampled at the ce_i edge) interleaved with host writes (taken when hw_ready_o). A read must return the value of the last completed write. */
`timescale 1ns/1ps
module tb_c5x_pbram;
reg clk = 0, rst_n = 0;
always #5 clk = ~clk;
reg rd = 0, wr = 0, hw = 0, ce = 0;
reg [15:0] ra = 0, wa = 0, wd = 0, ha = 0, hd = 0;
wire [15:0] rdata;
wire ready, hw_ready;
c5x_pbram dut (.clk(clk), .rst_n(rst_n), .ce_i(ce), .rd_en_i(rd), .raddr_i(ra), .wr_en_i(wr), .waddr_i(wa), .wdata_i(wd), .rdata_o(rdata), .ready_o(ready),
    .hw_en_i(hw), .hw_addr_i(ha), .hw_data_i(hd), .hw_ready_o(hw_ready));
reg [15:0] sh [0:255];
integer i, n, errors = 0;
reg [15:0] got;
reg [7:0] a;
initial begin
    for (i = 0; i < 256; i = i + 1) sh[i] = 16'h0000;
    repeat (4) @(posedge clk); rst_n = 1; repeat (2) @(posedge clk);
    /* fill the shadow window through the host port */
    for (i = 0; i < 256; i = i + 1) begin
        @(negedge clk); hw = 1; ha = 16'h4000 + i; hd = 16'hC000 ^ (i * 16'h0101);
        @(posedge clk); while (!hw_ready) @(posedge clk);
        sh[i] = 16'hC000 ^ (i * 16'h0101);
        #1 hw = 0;
    end
    for (n = 0; n < 4000; n = n + 1) begin
        a = $urandom;
        case ($urandom_range(0, 3))
            0, 1: begin                                   /* DSP read */
                @(negedge clk); rd = 1; ra = 16'h4000 + a; ce = 0;
                @(posedge clk); while (!ready) @(posedge clk);
                @(negedge clk); ce = 1; got = rdata; @(posedge clk); #1 ce = 0; rd = 0;
                if (got !== sh[a]) begin errors = errors + 1; if (errors < 6) $display("FAIL read [%0h] got %h want %h", a, got, sh[a]); end
            end
            2: begin                                      /* DSP write */
                @(negedge clk); wr = 1; wa = 16'h4000 + a; wd = $urandom; ce = 1;
                @(posedge clk); sh[a] = wd; #1 wr = 0; ce = 0;
            end
            3: begin                                      /* host write */
                @(negedge clk); hw = 1; ha = 16'h4000 + a; hd = $urandom;
                @(posedge clk); while (!hw_ready) @(posedge clk);
                sh[a] = hd; #1 hw = 0;
            end
        endcase
    end
    if (errors == 0) $display("PASS tb_c5x_pbram"); else $display("FAIL tb_c5x_pbram: %0d errors", errors);
    $finish;
end
initial begin #50000000; $display("FAIL tb_c5x_pbram: timeout"); $finish; end
endmodule
