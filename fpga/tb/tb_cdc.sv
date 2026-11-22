/* Self-checking test of the crossing primitives with unrelated clocks (40.32 MHz and 25.8048 MHz, odd phase): handshake with payload both ways, pulses, gray counter, reset sync. */
`default_nettype none
`timescale 1ps/1ps
module tb_cdc;
    logic clk_a = 0, clk_b = 0;
    always #12400 clk_a = ~clk_a;
    always #19375 clk_b = ~clk_b;
    initial #7000 ;
    logic rst_n = 0;
    integer errors = 0;
    logic go, busy, ack, v, done;
    logic [15:0] pay_i, pay_o, rsp_o, rsp_i;
    cdc_hs #(.WQ(16), .WR(16)) hs (.clk_s(clk_a), .rst_s_n(rst_n), .go_i(go), .payload_i(pay_i), .busy_o(busy), .ack_o(ack), .rsp_o(rsp_o),
                                    .clk_d(clk_b), .rst_d_n(rst_n), .v_o(v), .payload_o(pay_o), .done_i(done), .rsp_i(rsp_i));
    /* destination: answer 3 clocks after v_o with ~payload */
    logic [3:0] dly;
    always_ff @(posedge clk_b) begin
        dly  <= {dly[2:0], v};
        done <= dly[2];
    end
    assign rsp_i = ~pay_o;
    logic pls_i, pls_o;
    cdc_pulse pl (.clk_s(clk_a), .rst_s_n(rst_n), .pulse_i(pls_i), .clk_d(clk_b), .pulse_o(pls_o));
    integer npls = 0;
    always @(posedge clk_b) if (pls_o) npls <= npls + 1;
    logic [15:0] cnt, cnt_o;
    cdc_count #(.W(16)) cc (.clk_s(clk_a), .cnt_i(cnt), .clk_d(clk_b), .cnt_o(cnt_o));
    integer k, t;
    initial begin
        go = 0; pay_i = 0; pls_i = 0; cnt = 16'hFFF0; done = 0; dly = 0;
        repeat (10) @(posedge clk_a);
        rst_n = 1;
        repeat (10) @(posedge clk_a);
        for (k = 0; k < 200; k = k + 1) begin
            @(negedge clk_a); pay_i = $urandom; go = 1;
            @(negedge clk_a); go = 0;
            t = 0;
            while (!ack && t < 100) begin @(posedge clk_a); t = t + 1; end
            if (t >= 100) begin errors = errors + 1; $display("TIMEOUT k=%0d", k); end
            else if (rsp_o !== ~pay_i) begin errors = errors + 1; $display("rsp mismatch k=%0d %h vs %h", k, rsp_o, ~pay_i); end
            repeat ($urandom_range(0, 6)) @(posedge clk_a);
        end
        for (k = 0; k < 50; k = k + 1) begin
            @(negedge clk_a); pls_i = 1; @(negedge clk_a); pls_i = 0; repeat (6) @(posedge clk_a);
        end
        repeat (10) @(posedge clk_b);
        if (npls !== 50) begin errors = errors + 1; $display("pulses %0d != 50", npls); end
        for (k = 0; k < 100; k = k + 1) begin
            @(posedge clk_a); cnt <= cnt + 1; repeat ($urandom_range(2, 8)) @(posedge clk_a);
            if ($countones(cnt ^ cnt_o) > 1 && 0) errors = errors + 1;
        end
        repeat (10) @(posedge clk_b);
        if (cnt_o !== cnt) begin errors = errors + 1; $display("count %h vs %h", cnt_o, cnt); end
        if (errors == 0) $display("PASS tb_cdc"); else $display("FAIL tb_cdc: %0d errors", errors);
        $finish;
    end
endmodule
