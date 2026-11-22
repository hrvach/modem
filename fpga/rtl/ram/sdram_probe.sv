/*
sdram_probe.sv -- SDRAM start-up calibration and run-time self-test, one arbiter client.

FPGA-only plumbing. The board's SDRAM data delay (clock out, chip access time, input pad) is not known and the read-capture window of sdram16 is only one clock wide at
120.96 MHz, so after every controller initialisation this block calibrates the capture edge: for cap_extra = 0, 1, 2 it writes NW (64) pseudo-random words spread over rows, columns and
banks of a scratch area, reads them all back, then repeats with the complemented data; a setting passes only if every word read back right. cal_mask_o says which
settings passed. The middle passing setting is kept (cap_o: 1 if it passed, else 0, else 2) and cal_done_o goes high (cal_ok_o = a setting was found; if none was,
cap_o stays 0 and cal_ok_o low, cal_done_o still goes high so the machine does not hang). The top holds the cores in reset until cal_done_o.
After that, forever with a pause between rounds: write a pattern to the scratch word, read it back (test_ok_o) and read the word at 186 physical 0xFFFF0
(the reset vector area of the flash image, word_o), so the heartbeat can tell "the flash image is in the SDRAM" from "the SDRAM returns zeros". The scratch word is
outside both the 186 and the DSP regions. Lowest priority; the run-time rounds only while run_i is high (the cores are out of reset).
Not modelled: anything but single word accesses.
*/
`default_nettype none

module sdram_probe #(
    parameter [23:0] SCRATCH_WORD = 24'h0F0000,
    parameter [23:0] VECTOR_WORD  = 24'h07FFF8,     /* 186 physical 0xFFFF0 */
    parameter integer PAUSE_CLKS  = 1_000_000
) (
    input  logic        clk,
    input  logic        rst_n,                      /* low while the SDRAM controller initialises */
    input  logic        sdram_ready_i,              /* the controller has come up (its ready was seen high) */
    input  logic        run_i,

    output logic        rq_req_o,
    output logic        rq_we_o,
    output logic [23:0] rq_addr_o,
    output logic [15:0] rq_wdata_o,
    input  logic        rq_ack_i,
    input  logic [15:0] rq_rdata_i,

    output logic [1:0]  cap_o,
    output logic        cal_done_o,
    output logic        cal_ok_o,
    output logic [2:0]  cal_mask_o,
    output logic [15:0] word_o,
    output logic        test_ok_o
);
    localparam [15:0] PAT_A = 16'hA5C3;
    localparam integer NW = 64;

    typedef enum logic [3:0] {
        ST_WAIT  = 4'd0,     /* controller not up yet */
        ST_CWR   = 4'd1,     /* calibration with the current capture setting: write NW words, read them back, then the same with complemented data */
        ST_CRD   = 4'd2,
        ST_PAUSE = 4'd5,
        ST_WR    = 4'd6,
        ST_RD    = 4'd7,
        ST_VEC   = 4'd8
    } state_t;

    state_t      state_q;
    logic [31:0] cnt_q;
    logic [15:0] pat_q;
    logic [6:0]  idx_q;
    logic        pass_q;
    logic        err_q;
    logic [2:0]  mask_q;
    logic [15:0] cal_pat;

    always_comb begin
        rq_req_o   = (state_q == ST_CWR) || (state_q == ST_CRD) || (state_q == ST_WR) || (state_q == ST_RD) || (state_q == ST_VEC);
        rq_we_o    = (state_q == ST_CWR) || (state_q == ST_WR);
        rq_addr_o  = (state_q == ST_VEC) ? VECTOR_WORD :
                     (state_q == ST_CWR || state_q == ST_CRD) ? SCRATCH_WORD + 24'(idx_q) * 24'h2A5 + 24'h100 : SCRATCH_WORD;
        cal_pat    = (PAT_A ^ (16'(idx_q) * 16'h9E37)) ^ {16{pass_q}};
        rq_wdata_o = (state_q == ST_CWR) ? cal_pat : pat_q;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state_q    <= ST_WAIT;
            cnt_q      <= 32'd0;
            pat_q      <= PAT_A;
            word_o     <= 16'h0000;
            test_ok_o  <= 1'b0;
            cap_o      <= 2'd0;
            cal_done_o <= 1'b0;
            cal_ok_o   <= 1'b0;
            idx_q      <= 7'd0;
            pass_q     <= 1'b0;
            err_q      <= 1'b0;
            mask_q     <= 3'd0;
            cal_mask_o <= 3'd0;
        end else begin
            case (state_q)
                ST_WAIT: begin
                    if (sdram_ready_i)
                        state_q <= ST_CWR;
                end
                ST_CWR: begin
                    if (rq_ack_i) begin
                        if (idx_q == NW - 1) begin
                            idx_q   <= 7'd0;
                            state_q <= ST_CRD;
                        end else begin
                            idx_q <= idx_q + 7'd1;
                        end
                    end
                end
                ST_CRD: begin
                    if (rq_ack_i) begin
                        if (rq_rdata_i != cal_pat)
                            err_q <= 1'b1;
                        if (idx_q != NW - 1) begin
                            idx_q <= idx_q + 7'd1;
                        end else begin
                            idx_q <= 7'd0;
                            if (!pass_q) begin
                                pass_q  <= 1'b1;
                                state_q <= ST_CWR;
                            end else begin
                                /* this capture setting is done: record it, go on with the next or choose */
                                pass_q <= 1'b0;
                                err_q  <= 1'b0;
                                if (!(err_q || rq_rdata_i != cal_pat))
                                    mask_q <= mask_q | (3'd1 << cap_o);
                                if (cap_o == 2'd2) begin
                                    cal_done_o <= 1'b1;
                                    state_q    <= ST_PAUSE;
                                    cal_mask_o <= mask_q | ((!(err_q || rq_rdata_i != cal_pat)) ? 3'b100 : 3'b000);
                                    if (mask_q[1])      begin cap_o <= 2'd1; cal_ok_o <= 1'b1; end
                                    else if (mask_q[0]) begin cap_o <= 2'd0; cal_ok_o <= 1'b1; end
                                    else if (!(err_q || rq_rdata_i != cal_pat)) begin cap_o <= 2'd2; cal_ok_o <= 1'b1; end
                                    else                begin cap_o <= 2'd0; end
                                end else begin
                                    cap_o   <= cap_o + 2'd1;
                                    state_q <= ST_CWR;
                                end
                            end
                        end
                    end
                end
                ST_PAUSE: begin
                    if (run_i) begin
                        if (cnt_q >= PAUSE_CLKS) begin
                            cnt_q   <= 32'd0;
                            state_q <= ST_WR;
                        end else begin
                            cnt_q <= cnt_q + 32'd1;
                        end
                    end
                end
                ST_WR:  if (rq_ack_i) state_q <= ST_RD;
                ST_RD: begin
                    if (rq_ack_i) begin
                        test_ok_o <= (rq_rdata_i == pat_q);
                        pat_q     <= ~pat_q;
                        state_q   <= ST_VEC;
                    end
                end
                ST_VEC: begin
                    if (rq_ack_i) begin
                        word_o  <= rq_rdata_i;
                        state_q <= ST_PAUSE;
                    end
                end
                default: state_q <= ST_WAIT;
            endcase
        end
    end
endmodule
