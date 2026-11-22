/*
cdc.sv -- crossing primitives between clock domains (the 40.32 MHz DSP domain, the 20.16 MHz CPU domain and the 80.64 MHz memory domain).

FPGA-only plumbing. Every crossing is a toggle (one bit) through STAGES flops; multi-bit payloads never cross on their own: they are held stable by the sender and captured by the
receiver only after the toggle has arrived, so the capture is a data-stable sample. STAGES = 2 is the synchroniser for unrelated clocks; the three clocks of this design come from
one PLL and are phase aligned (80.64 = 2 x 40.32 = 4 x 20.16), so there STAGES = 1 is enough and STA times every crossing path like any other.
*/
`default_nettype none

/* two-flop synchroniser of a level */
module cdc_sync #(
    parameter integer W = 1,
    parameter integer STAGES = 2
) (
    input  logic         clk,
    input  logic [W-1:0] d_i,
    output logic [W-1:0] q_o
);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION AUTO" *) logic [W-1:0] s_q [0:STAGES-1];

    integer k;
    always_ff @(posedge clk) begin
        s_q[0] <= d_i;
        for (k = 1; k < STAGES; k = k + 1)
            s_q[k] <= s_q[k-1];
    end
    assign q_o = s_q[STAGES-1];
endmodule

/* one-clock pulse in the source domain -> one-clock pulse in the destination domain (pulses must be at least 3 destination clocks apart) */
module cdc_pulse #(
    parameter integer STAGES = 2
) (
    input  logic clk_s,
    input  logic rst_s_n,
    input  logic pulse_i,
    input  logic clk_d,
    output logic pulse_o
);
    logic tog_q;
    logic t_s;
    logic t_d_q;

    always_ff @(posedge clk_s) begin
        if (!rst_s_n)
            tog_q <= 1'b0;
        else if (pulse_i)
            tog_q <= ~tog_q;
    end

    cdc_sync #(.W(1), .STAGES(STAGES)) u_s (.clk(clk_d), .d_i(tog_q), .q_o(t_s));

    always_ff @(posedge clk_d)
        t_d_q <= t_s;

    assign pulse_o = t_s ^ t_d_q;
endmodule

/*
Four-phase request / response crossing with a payload.
  source (clk_s): go_i (one clock, payload_i valid and held until ack_o) -> ack_o (one clock, rsp_o valid and held until the next go_i). go_i while busy_o is ignored.
  destination (clk_d): v_o (one clock) with payload_o (a copy, held until the next request); the destination answers with done_i (one clock, any time after v_o, rsp_i sampled then).
*/
module cdc_hs #(
    parameter integer WQ = 16,
    parameter integer WR = 16,
    parameter integer STAGES = 2
) (
    input  logic          clk_s,
    input  logic          rst_s_n,
    input  logic          go_i,
    input  logic [WQ-1:0] payload_i,
    output logic          busy_o,
    output logic          ack_o,
    output logic [WR-1:0] rsp_o,

    input  logic          clk_d,
    input  logic          rst_d_n,
    output logic          v_o,
    output logic [WQ-1:0] payload_o,
    input  logic          done_i,
    input  logic [WR-1:0] rsp_i
);
    /* ---- source */
    logic req_t_q, ack_s, ack_prev_q;
    logic busy_q;
    logic ack_t_q;

    cdc_sync #(.W(1), .STAGES(STAGES)) u_ack (.clk(clk_s), .d_i(ack_t_q), .q_o(ack_s));

    always_ff @(posedge clk_s) begin
        if (!rst_s_n) begin
            req_t_q    <= 1'b0;
            busy_q     <= 1'b0;
            ack_prev_q <= 1'b0;
        end else begin
            ack_prev_q <= ack_s;
            if (go_i && !busy_q) begin
                req_t_q <= ~req_t_q;
                busy_q  <= 1'b1;
            end else if (ack_s ^ ack_prev_q) begin
                busy_q  <= 1'b0;
            end
        end
    end
    assign busy_o = busy_q;
    assign ack_o  = ack_s ^ ack_prev_q;

    /* ---- destination */
    logic req_s, req_prev_q, v_q;
    logic [WQ-1:0] pay_q;
    logic [WR-1:0] rsp_q;

    cdc_sync #(.W(1), .STAGES(STAGES)) u_req (.clk(clk_d), .d_i(req_t_q), .q_o(req_s));

    always_ff @(posedge clk_d) begin
        if (!rst_d_n) begin
            req_prev_q <= 1'b0;
            ack_t_q    <= 1'b0;
            v_q        <= 1'b0;
        end else begin
            req_prev_q <= req_s;
            v_q        <= req_s ^ req_prev_q;
            if (req_s ^ req_prev_q)
                pay_q <= payload_i;
            if (done_i) begin
                rsp_q   <= rsp_i;
                ack_t_q <= ~ack_t_q;
            end
        end
    end
    assign v_o       = v_q;   /* one clock after the toggle arrived: payload_o holds the new payload in this clock */
    assign payload_o = pay_q;
    assign rsp_o     = rsp_q;
endmodule

/* a binary counter crossing: gray-coded in the source domain (one bit changes per count), two-flop synchronised, decoded in the destination domain */
module cdc_count #(
    parameter integer W = 16,
    parameter integer STAGES = 2
) (
    input  logic         clk_s,
    input  logic [W-1:0] cnt_i,
    input  logic         clk_d,
    output logic [W-1:0] cnt_o
);
    logic [W-1:0] gray_q, gray_s, bin;
    integer k;

    always_ff @(posedge clk_s)
        gray_q <= cnt_i ^ (cnt_i >> 1);

    cdc_sync #(.W(W), .STAGES(STAGES)) u_g (.clk(clk_d), .d_i(gray_q), .q_o(gray_s));

    always_comb begin
        bin[W-1] = gray_s[W-1];
        for (k = W - 2; k >= 0; k = k - 1)
            bin[k] = bin[k+1] ^ gray_s[k];
    end
    always_ff @(posedge clk_d)
        cnt_o <= bin;
endmodule

/* reset release synchroniser: asserted asynchronously, released on clk_d */
module cdc_rst (
    input  logic clk_d,
    input  logic rst_n_i,
    output logic rst_n_o
);
    logic s1_q, s2_q;
    always_ff @(posedge clk_d or negedge rst_n_i) begin
        if (!rst_n_i) begin
            s1_q <= 1'b0;
            s2_q <= 1'b0;
        end else begin
            s1_q <= 1'b1;
            s2_q <= s1_q;
        end
    end
    assign rst_n_o = s2_q;
endmodule
