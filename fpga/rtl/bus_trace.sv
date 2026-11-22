/*
bus_trace.sv -- bring-up observation: a ring of the last 64 accesses of the 186's memory port, frozen by freeze_i (the first jump out of valid code).

FPGA-only plumbing. ev_i is a one-clock pulse per accepted access (wr_i, word_i, addr_i[19:0], data_i = the written word or the word read). After freeze_i goes high
nothing more is recorded. Entry rd_idx_i of the frozen ring (0 = oldest) is on rd_data_o one clock later as {wr, word, addr[19:0], data[15:0]}; the values are static once
frozen, so a slower clock domain may sample them without synchronisation (dbg_status prints them on the DTE pin).
*/
`default_nettype none

module bus_trace (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ev_i,
    input  logic        wr_i,
    input  logic        word_i,
    input  logic [19:0] addr_i,
    input  logic [15:0] data_i,
    input  logic        freeze_i,
    input  logic [5:0]  rd_idx_i,
    output logic [37:0] rd_data_o
);
    logic [37:0] mem_q [0:63];
    logic [5:0]  wp_q;
    logic        frozen_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wp_q     <= 6'd0;
            frozen_q <= 1'b0;
        end else begin
            if (freeze_i)
                frozen_q <= 1'b1;
            if (ev_i && !frozen_q && !freeze_i) begin
                mem_q[wp_q] <= {wr_i, word_i, addr_i, data_i};
                wp_q        <= wp_q + 6'd1;
            end
        end
        rd_data_o <= mem_q[wp_q + rd_idx_i];
    end
endmodule
