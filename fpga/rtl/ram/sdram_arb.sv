/*
sdram_arb.sv -- N-client arbiter in front of the sdram16 controller (rtl/ram/sdram.sv).

FPGA-only plumbing. One clock (clk_sys, the same clock as the controller), no clock crossing. Fixed priority: client 0 wins over 1 over 2 ...
A client raises req with we / be / addr / wdata stable and keeps them until it sees ack (one clock pulse); read data is valid in rdata in the ack
clock and only then. addr is a 16-bit WORD address (byte address / 2); the byte address handed to sdram16 is {addr, 1'b0}.
Lane enables be[1] = high byte, be[0] = low byte; a read ignores them. One transaction at a time: the controller does not pipeline.

Not modelled: bursts, bank interleave (sdram16 does single accesses, about 8 clocks each).
*/
`default_nettype none

module sdram_arb #(
    parameter integer N = 4,
    parameter integer AW = 24   /* client word address width; the controller sees {addr, 1'b0} in 25 bits */
) (
    input  logic            clk,
    input  logic            rst_n,

    input  logic [N-1:0]    req_i,
    input  logic [N-1:0]    we_i,
    input  logic [2*N-1:0]  be_i,
    input  logic [N*AW-1:0] addr_i,
    input  logic [16*N-1:0] wdata_i,
    output logic [N-1:0]    ack_o,
    output logic [15:0]     rdata_o,

    /* sdram16 */
    output logic            sd_rd_o,
    output logic            sd_we_o,
    output logic [1:0]      sd_wtbt_o,
    output logic [24:0]     sd_addr_o,
    output logic [15:0]     sd_din_o,
    input  logic [15:0]     sd_dout_i,
    input  logic            sd_ready_i
);
    typedef enum logic [1:0] {
        ST_IDLE  = 2'd0,
        ST_ISSUE = 2'd1,   /* rd / we high for exactly this clock */
        ST_WAIT0 = 2'd2,   /* the controller drops ready on the edge that sampled rd / we */
        ST_WAIT  = 2'd3    /* wait for ready */
    } state_t;

    state_t          state_q;
    logic [N-1:0]    grant_q;
    logic            we_q;
    logic [1:0]      be_q;
    logic [AW-1:0]   addr_q;
    logic [15:0]     wdata_q;

    logic [N-1:0]    pick;
    logic            any_req;

    always_comb begin
        pick = '0;
        for (int i = N - 1; i >= 0; i = i - 1) begin
            if (req_i[i]) begin
                pick = '0;
                pick[i] = 1'b1;
            end
        end
        any_req = |req_i;
    end

    always_comb begin
        sd_rd_o   = (state_q == ST_ISSUE) && !we_q;
        sd_we_o   = (state_q == ST_ISSUE) && we_q;
        sd_wtbt_o = be_q;
        sd_addr_o = {{(25 - AW - 1){1'b0}}, addr_q, 1'b0};
        sd_din_o  = wdata_q;
        rdata_o   = sd_dout_i;
        ack_o     = '0;
        if (state_q == ST_WAIT && sd_ready_i)
            ack_o = grant_q;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            grant_q <= '0;
            we_q    <= 1'b0;
            be_q    <= 2'b00;
            addr_q  <= '0;
            wdata_q <= 16'h0000;
        end else begin
            case (state_q)
                ST_IDLE: begin
                    if (any_req && sd_ready_i) begin
                        grant_q <= pick;
                        for (int i = 0; i < N; i = i + 1) begin
                            if (pick[i]) begin
                                we_q    <= we_i[i];
                                be_q    <= be_i[2*i +: 2];
                                addr_q  <= addr_i[AW*i +: AW];
                                wdata_q <= wdata_i[16*i +: 16];
                            end
                        end
                        state_q <= ST_ISSUE;
                    end
                end
                ST_ISSUE: state_q <= ST_WAIT0;
                ST_WAIT0: state_q <= ST_WAIT;
                ST_WAIT: begin
                    if (sd_ready_i)
                        state_q <= ST_IDLE;
                end
                default: state_q <= ST_IDLE;
            endcase
        end
    end
endmodule
