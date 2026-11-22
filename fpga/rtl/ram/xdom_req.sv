/*
xdom_req.sv -- one SDRAM-arbiter client in the slow (CPU) clock domain, crossing to the arbiter in the fast (memory) clock domain.

FPGA-only plumbing. The two clocks come from one PLL and are phase aligned (the memory clock is an integer multiple of the CPU clock), so the crossing is the usual four-phase
handshake with one register per direction and no multi-bit synchroniser: the payload is held stable by the client from req_i until ack_o and is copied into the fast domain
one fast clock after the request is seen; the read data is held in a fast-domain register until the next transaction. STA times every crossing path as one fast clock.

  cpu side (clk_c): req_i / we_i / be_i / addr_i / wdata_i are held until ack_o (one clk_c pulse, rdata_o valid in that cycle and held after).
  memory side (clk_m): req_o / we_o / be_o / addr_o / wdata_o to sdram_arb, held until ack_i (one clk_m pulse, rdata_i valid in that cycle).
Sequence: req_c_q set -> seen as req_m_q -> payload copied, req_o up -> arbiter ack: rdata kept, done_m_q set, req_o down -> seen as done_c_q: ack_o, req_c_q cleared ->
req_m_q falls -> done_m_q cleared -> done_c_q falls -> the next request may start.
*/
`default_nettype none

module xdom_req #(
    parameter integer AW = 24
) (
    input  logic          clk_c,
    input  logic          rst_c_n,
    input  logic          clk_m,
    input  logic          rst_m_n,

    input  logic          req_i,
    input  logic          we_i,
    input  logic [1:0]    be_i,
    input  logic [AW-1:0] addr_i,
    input  logic [15:0]   wdata_i,
    output logic          ack_o,
    output logic [15:0]   rdata_o,

    output logic          req_o,
    output logic          we_o,
    output logic [1:0]    be_o,
    output logic [AW-1:0] addr_o,
    output logic [15:0]   wdata_o,
    input  logic          ack_i,
    input  logic [15:0]   rdata_i
);
    /* ---- slow side */
    logic req_c_q, done_c_q;

    assign ack_o = req_c_q && done_c_q;

    always_ff @(posedge clk_c) begin
        if (!rst_c_n) begin
            req_c_q  <= 1'b0;
            done_c_q <= 1'b0;
        end else begin
            done_c_q <= done_m_q;
            if (!req_c_q) begin
                if (req_i && !done_c_q)
                    req_c_q <= 1'b1;
            end else if (done_c_q) begin
                req_c_q <= 1'b0;
            end
        end
    end

    /* ---- fast side */
    logic req_m_q, done_m_q;
    logic [15:0] rd_q;
    assign rdata_o = rd_q;

    always_ff @(posedge clk_m) begin
        if (!rst_m_n) begin
            req_m_q  <= 1'b0;
            done_m_q <= 1'b0;
            req_o    <= 1'b0;
        end else begin
            req_m_q <= req_c_q;
            if (!req_o && !done_m_q) begin
                if (req_m_q) begin
                    req_o   <= 1'b1;
                    we_o    <= we_i;
                    be_o    <= be_i;
                    addr_o  <= addr_i;
                    wdata_o <= wdata_i;
                end
            end else if (req_o) begin
                if (ack_i) begin
                    req_o    <= 1'b0;
                    rd_q     <= rdata_i;
                    done_m_q <= 1'b1;
                end
            end else if (!req_m_q) begin
                done_m_q <= 1'b0;
            end
        end
    end
endmodule
