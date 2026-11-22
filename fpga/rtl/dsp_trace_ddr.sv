/*
dsp_trace_ddr.sv -- a continuous history of the DSP's executed instructions in the HPS DDR memory (a debug tool for the bring-up of the modem core).

  Every retired DSP instruction contributes its program counter; three of them are packed into one 64-bit word together with AR7 at the time of the third:
      word = { ar7[15:0], pc2[15:0], pc1[15:0], pc0[15:0] }       (pc0 is the oldest)
  The words go through a small clock-crossing FIFO (DSP clock -> the 20.16 MHz DDRAM clock) into a ring in DDR.  The trace never holds the DSP back: when the FIFO is full the word is dropped and
  counted.  It uses the DDR port only in clocks the line interface (line_ddr, which has priority) leaves free.  Freezing (the trap) stops the capture, flushes the FIFO and writes the final header.

Layout, in 64-bit words from BASE (the HPS maps physical 8 * BASE_QADDR):
  0x000  magic: the bytes "MDMTRC01" in memory
  0x001  words written to the ring so far (monotonic); refreshed every 4096 words and when frozen
  0x002  [31:0] words dropped (FIFO full), [32] frozen (the ring holds the last words before the freeze, final header written)
  0x010  ring of 2^RING_BITS words; the newest word is at index (count - 1) mod 2^RING_BITS
*/
`default_nettype none

module dsp_trace_ddr #(
    parameter logic [28:0] BASE_QADDR = 29'h07600000,     /* physical 0x3B000000 */
    parameter int          RING_BITS  = 23                /* 8 M words = 64 MB = about 25 M instructions (12 s of the DSP at its usual rate) */
) (
    /* DSP clock domain: the retire strobe, the PC, AR7 */
    input  logic        clk_dsp,
    input  logic        rst_dsp_n,
    input  logic        ev_i,
    input  logic [15:0] pc_i,
    input  logic [15:0] ar7_i,
    input  logic        freeze_dsp_i,
    input  logic        en_dsp_i,                         /* capture enabled (the HPS armed the trace), in the DSP clock domain */

    /* DDRAM clock domain (20.16 MHz) */
    input  logic        clk,
    input  logic        rst_n,
    input  logic        freeze_i,                         /* the same freeze, already synchronised to clk */
    input  logic        en_i,                             /* armed by the HPS (word A_TRCTL of the line control block); nothing is written to DDR while it is 0 */
    input  logic        line_active_i,                    /* line_ddr is using the port this clock */
    input  logic        ddr_busy_i,
    output logic        ddr_we_o,
    output logic [28:0] ddr_addr_o,
    output logic [63:0] ddr_din_o
);
    localparam logic [28:0] A_MAGIC = 29'h000, A_COUNT = 29'h001, A_INFO = 29'h002, A_RING = 29'h010;

    function automatic logic [3:0] wgray_next(input logic [3:0] b);
        wgray_next = b ^ (b >> 1);
    endfunction
    logic [3:0]  rgray_q;                                 /* read pointer, gray (DDRAM clock domain) */

    /* ---- DSP side: pack three PCs per word, push into the FIFO */
    logic [15:0] pc0_q, pc1_q;
    logic [1:0]  n_q;
    logic [3:0]  wptr_q, rptr_q;                          /* binary, 4 bits: depth 8, wrap bit for full/empty */
    logic [3:0]  wgray_q;
    logic [3:0]  rgray_sync_a_q, rgray_sync_b_q;
    logic [31:0] drop_q;
    (* ramstyle = "logic" *) logic [63:0] fifo_q [0:7];
    logic        fifo_full_d;
    always_comb begin
        /* full when the write pointer is a whole depth ahead of the read pointer (gray compare on the synchronised read pointer) */
        fifo_full_d = (wgray_next(wptr_q + 4'd1) == {~rgray_sync_b_q[3:2], rgray_sync_b_q[1:0]});
    end
    always_ff @(posedge clk_dsp) begin
        if (!rst_dsp_n) begin
            pc0_q <= 16'd0; pc1_q <= 16'd0; n_q <= 2'd0; wptr_q <= 4'd0; wgray_q <= 4'd0; drop_q <= 32'd0;
            rgray_sync_a_q <= 4'd0; rgray_sync_b_q <= 4'd0;
        end else begin
            rgray_sync_a_q <= rgray_q;
            rgray_sync_b_q <= rgray_sync_a_q;
            if (ev_i && !freeze_dsp_i && en_dsp_i) begin
                if (n_q == 2'd0)      begin pc0_q <= pc_i; n_q <= 2'd1; end
                else if (n_q == 2'd1) begin pc1_q <= pc_i; n_q <= 2'd2; end
                else begin
                    n_q <= 2'd0;
                    if (fifo_full_d) drop_q <= drop_q + 32'd1;
                    else begin
                        fifo_q[wptr_q[2:0]] <= {ar7_i, pc_i, pc1_q, pc0_q};
                        wptr_q  <= wptr_q + 4'd1;
                        wgray_q <= wgray_next(wptr_q + 4'd1);
                    end
                end
            end
        end
    end

    /* ---- DDRAM side */
    logic [3:0]  wgray_sync_a_q, wgray_sync_b_q;
    logic [31:0] drop_a_q, drop_b_q;
    logic [63:0] data_q;
    logic        have_q;                                  /* data_q holds a word to write */
    logic [31:0] widx_q;                                  /* words written (monotonic) */
    logic [2:0]  hdr_q;                                   /* header words still to write: [0] magic, [1] count, [2] info */
    logic        final_q;                                 /* the final header was written */
    logic        empty_c;
    always_comb empty_c = (rgray_q == wgray_sync_b_q);

    logic        issue_hdr, issue_data;
    logic        can_issue;
    always_comb begin
        can_issue  = !ddr_busy_i && !line_active_i;
        issue_hdr  = (hdr_q != 3'd0);
        issue_data = !issue_hdr && have_q;
        ddr_we_o   = en_i && can_issue && (issue_hdr || issue_data);
        ddr_addr_o = BASE_QADDR + (hdr_q[0] ? A_MAGIC : hdr_q[1] ? A_COUNT : hdr_q[2] ? A_INFO : (A_RING + {7'd0, widx_q[RING_BITS-1:0]}));
        ddr_din_o  = hdr_q[0] ? "10CRTMDM"  : hdr_q[1] ? {32'd0, widx_q} : hdr_q[2] ? {31'd0, freeze_i, drop_b_q} : data_q;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rgray_q <= 4'd0; rptr_q <= 4'd0; wgray_sync_a_q <= 4'd0; wgray_sync_b_q <= 4'd0; drop_a_q <= 32'd0; drop_b_q <= 32'd0;
            data_q <= 64'd0; have_q <= 1'b0; widx_q <= 32'd0; hdr_q <= 3'b001; final_q <= 1'b0;
        end else begin
            wgray_sync_a_q <= wgray_q; wgray_sync_b_q <= wgray_sync_a_q;
            drop_a_q <= drop_q;        drop_b_q <= drop_a_q;

            /* take the next word out of the FIFO */
            if (!have_q && !empty_c) begin
                data_q  <= fifo_q[rptr_q[2:0]];
                rptr_q  <= rptr_q + 4'd1;
                rgray_q <= wgray_next(rptr_q + 4'd1);
                have_q  <= 1'b1;
            end

            if (ddr_we_o) begin
                if (issue_hdr) begin
                    hdr_q <= hdr_q & ~(hdr_q[0] ? 3'b001 : hdr_q[1] ? 3'b010 : 3'b100);
                end else begin
                    have_q  <= 1'b0;
                    widx_q  <= widx_q + 32'd1;
                    if (widx_q[11:0] == 12'hFFF) hdr_q <= hdr_q | 3'b110;     /* refresh the header every 4096 words */
                end
            end

            /* frozen and everything flushed: the final header */
            if (!freeze_i) final_q <= 1'b0;
            if (freeze_i && !final_q && empty_c && !have_q && (hdr_q == 3'd0)) begin
                hdr_q   <= 3'b110;
                final_q <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
