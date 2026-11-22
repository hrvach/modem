/* Self-checking test of aic: frame spacing, the AC01 control-word protocol (split frame, secondary tick), register 4 gains on the DAC and ADC paths, the
   sample-rate table / formula (A, B, N), the clamp, and the park / release of the core through step_o. The core is modelled by a charged-cycle counter that
   advances 4 cycles per 4 clocks while step_o is high (a 4-cycle "instruction"). */
`timescale 1ns/1ps
module tb_aic;
reg clk = 0, rst_n = 0;
always #5 clk = ~clk;

reg  [31:0] cycles = 0;
reg         run = 0;
wire        step, ser_tick, int3, dac_valid, rx_next, frame_tick;
wire [15:0] ser_rx, rate;
wire signed [15:0] dac_sample;
reg         dxr_wr = 0;
reg  [15:0] dxr_w = 0, mclk_n = 0;
reg signed [15:0] rx_sample = 0;
reg  [1:0]  ph = 0;

aic dut (.clk(clk), .rst_n(rst_n), .ce_i(1'b1), .cycles_i(cycles), .parked_i(!step), .idle_i(1'b0), .run_i(run), .step_o(step), .ser_tick_o(ser_tick),
    .ser_rx_o(ser_rx), .int3_o(int3), .dxr_wr_i(dxr_wr), .dxr_wdata_i(dxr_w), .mclk_n_i(mclk_n), .dac_valid_o(dac_valid), .dac_sample_o(dac_sample),
    .rx_next_o(rx_next), .rx_sample_i(rx_sample), .frame_tick_o(frame_tick), .rate_cps_o(rate));

always @(posedge clk) begin
    if (step) begin ph <= ph + 1; if (ph == 2'd3) cycles <= cycles + 4; end
end

integer errors = 0, ticks = 0, frames = 0, dacs = 0, nexts = 0;
integer last_frame_cyc = 0, spacing = 0;
integer last_ser_rx;
reg signed [15:0] last_dac;
always @(posedge clk) begin
    if (ser_tick) ticks <= ticks + 1;
    if (frame_tick) begin frames <= frames + 1; spacing <= cycles - last_frame_cyc; last_frame_cyc <= cycles; end
    if (dac_valid) begin dacs <= dacs + 1; last_dac <= dac_sample; end
    if (rx_next) nexts <= nexts + 1;
end

task chk(input [255:0] name, input integer got, input integer want);
    begin if (got !== want) begin errors = errors + 1; $display("FAIL %0s: got %0d want %0d", name, got, want); end end
endtask

task dxr(input [15:0] w);
    begin @(posedge clk); dxr_w <= w; dxr_wr <= 1; @(posedge clk); dxr_wr <= 0; end
endtask
task wait_frame;
    integer f0;
    begin f0 = frames; while (frames == f0) @(posedge clk); @(posedge clk); end
endtask
/* write a register through the control protocol: a word with D1 D0 = 11, then (in the next, split frame's first half) the control word */
task aic_write(input [4:0] reg_no, input [7:0] val);
    begin
        dxr(16'h0003);
        wait_frame;                 /* the next frame is split: the secondary tick comes after half a frame */
        dxr({3'b000, reg_no, val});
        wait_frame;
    end
endtask

integer t0, i;
integer got;
initial begin
    repeat (5) @(posedge clk); rst_n = 1; repeat (5) @(posedge clk);
    run = 1;
    wait_frame; wait_frame;
    chk("default spacing >= 5600", spacing >= 5600, 1);
    chk("default spacing < 5604", spacing < 5604, 1);
    chk("default cps", rate, 5600);
    chk("one tick per frame", ticks, frames);

    /* control protocol: reg 4 = 0x05: ADC gain 1 (bits 3:2 = 01), DAC gain 1 (bits 1:0 = 01) */
    t0 = ticks;
    dxr(16'h0003);                       /* control word follows */
    wait_frame;                          /* this frame ends, the next is split */
    chk("DAC sample for the D1D0=11 word", dacs >= 1, 1);
    t0 = ticks;
    dxr(16'h0405);                       /* control word: register 4 */
    wait_frame;
    chk("a split frame has two ticks", ticks - t0, 2);
    chk("register 4", dut.aic_q[4], 8'h05);
    chk("control word gave no DAC sample", dacs, 1);
    t0 = ticks; wait_frame; chk("next frame not split", ticks - t0, 1);

    /* DAC: word with the two low bits dropped, gain 1 */
    dxr(16'h1235); @(posedge clk); @(posedge clk);
    chk("dac gain 1", last_dac, 16'h1234);
    /* gain 0.5 (reg 4 = 0x06, ADC gain stays 1) */
    aic_write(5'd4, 8'h06);
    dxr(16'h1234); @(posedge clk); @(posedge clk);
    chk("dac gain 0.5", last_dac, 16'h091A);
    aic_write(5'd4, 8'h07);
    dxr(16'h1234); @(posedge clk); @(posedge clk);
    chk("dac gain 0.25", last_dac, 16'h048D);
    aic_write(5'd4, 8'h04);
    dxr(16'h1234); @(posedge clk); @(posedge clk);
    chk("dac gain 0", last_dac, 0);

    /* ADC: gain 1, line sample 1000 plus the noise floor (+-8), low two bits dropped */
    aic_write(5'd4, 8'h05);
    rx_sample = 16'sd1000; wait_frame; wait_frame;
    got = ser_rx; chk("adc near 1000", (got >= 988 && got <= 1012), 1);
    chk("adc low bits clear", ser_rx[1:0], 0);
    aic_write(5'd4, 8'h09);              /* ADC gain 2 */
    wait_frame; wait_frame;
    got = ser_rx; chk("adc gain 2 near 2000", (got >= 1976 && got <= 2024), 1);
    aic_write(5'd4, 8'h0D);              /* ADC gain 4 */
    rx_sample = 16'sd20000; wait_frame; wait_frame;
    chk("adc clamp at +32767 (C: &~3 first, then clamp16)", ser_rx, 16'h7FFF);
    rx_sample = -16'sd20000; wait_frame; wait_frame;
    chk("adc clamp at -32768", ser_rx, 16'h8000);
    aic_write(5'd4, 8'h05); rx_sample = 0;

    /* sample rate: table row (A = 10): N 130, B 19 -> T 245 -> 4900 cycles */
    aic_write(5'd1, 8'd10); aic_write(5'd2, 8'd19);
    mclk_n = 16'd130; repeat (20) @(posedge clk); wait_frame; wait_frame;
    chk("table row cps", rate, 4900);
    mclk_n = 16'd120; aic_write(5'd2, 8'd20); wait_frame;
    chk("table row 120/20 cps", rate, 5600);
    /* formula: A = 11, B = 18, N = 100: floor(3360 * 198 / 100) = 6652 */
    aic_write(5'd1, 8'd11); aic_write(5'd2, 8'd18); mclk_n = 16'd100;
    repeat (200) @(posedge clk); wait_frame;
    chk("formula cps", rate, 6652);
    /* clamp: N = 1 -> huge cps -> 10080; N = 60000 -> tiny cps -> 2520 */
    mclk_n = 16'd1; repeat (200) @(posedge clk); chk("clamp low rate", rate, 10080);
    mclk_n = 16'd60000; repeat (200) @(posedge clk); chk("clamp high rate", rate, 2520);
    wait_frame; wait_frame; chk("spacing at 2520", (spacing >= 2520 && spacing < 2524), 1);

    if (errors == 0) $display("PASS tb_aic"); else $display("FAIL tb_aic: %0d errors", errors);
    $finish;
end
initial begin #200000000; $display("FAIL tb_aic: global timeout (frames %0d)", frames); $finish; end
endmodule
