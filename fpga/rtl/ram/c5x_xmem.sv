/*
c5x_xmem.sv -- external program / unified memory of the TMS320C5x (64K words) in SDRAM, behind a direct-mapped M10K cache.

FPGA-only plumbing. Sits behind the xm_* port of c5x_core / c5x_mem (EXT_PMEM = 1) and in front of two sdram_arb clients (line fill reads, write-through
writes). The DSP core is clock-enabled (ce_i, built by the top); this module tells the top when the access presented right now can be completed
(ready_o), and the top lets ce_i through only then, so a miss costs DSP wall-clock time but no model time (timer, serial and the cycle counts only advance
with ce_i).

Cache: 512 lines x 8 words = 4K words. index = addr[11:3], tag = addr[15:12], word = addr[2:0]. Read lookup is registered (M10K): address presented in
clock 1, data and tag valid in clock 2 (look_ok_o), so a hit lets ce_i occur 2 clocks after the previous one. Read data (rdata_o) is the registered cache
word and must be sampled at the ce_i edge. A same-address read in the cycle of a write returns the OLD word (the c5x_mem contract).
Writes: write-through, write-no-allocate; a write that hits also updates the cached word. One-entry write buffer; a second write waits for the first
(ready_o low). A line fill starts only when the write buffer is empty, so a fill never reads stale SDRAM.
rd_en_i and wr_en_i are never both high (c5x_mem arbitration: one pmem access per clock).
Host write port (hw_*): the 186 downloading DSP program overlays / the loader copying the firmware; invalidates the line, then queues the write.
The tag array is cleared after reset (512 clocks, ready_o low).

Not modelled: burst fills (the controller does single accesses, a fill is 8 SDRAM transactions), write combining.
*/
`default_nettype none

module c5x_xmem #(
    parameter [23:0] BASE = 24'h0C0000   /* SDRAM word address of DSP program word 0x0000 */
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ce_i,         /* the DSP clock enable (the write is applied on this edge) */

    /* DSP side */
    input  logic        rd_en_i,
    input  logic [15:0] raddr_i,
    input  logic        wr_en_i,
    input  logic [15:0] waddr_i,
    input  logic [15:0] wdata_i,
    output logic [15:0] rdata_o,
    output logic        ready_o,

    /* host write port */
    input  logic        hw_en_i,
    input  logic [15:0] hw_addr_i,
    input  logic [15:0] hw_data_i,
    output logic        hw_ready_o,   /* hw_en_i is taken in a clock where this is high */

    /* sdram_arb client: line fill reads */
    output logic        rq_req_o,
    output logic [23:0] rq_addr_o,
    input  logic        rq_ack_i,
    input  logic [15:0] rq_rdata_i,

    /* sdram_arb client: writes */
    output logic        wq_req_o,
    output logic [23:0] wq_addr_o,
    output logic [15:0] wq_wdata_o,
    input  logic        wq_ack_i
);
    typedef enum logic [1:0] {
        F_INIT = 2'd0,
        F_IDLE = 2'd1,
        F_REQ  = 2'd2,
        F_DONE = 2'd3
    } fill_t;

    fill_t        fill_q;
    logic [8:0]   init_q;
    logic [15:0]  fill_addr_q;
    logic [2:0]   fill_word_q;

    (* ramstyle = "M10K" *) logic [15:0] cdata [0:4095];
    (* ramstyle = "M10K" *) logic [4:0]  ctag   [0:511];
    logic [15:0]  cdata_q;
    logic [4:0]   ctag_q;

    logic [15:0]  look_addr;
    logic [15:0]  look_addr_q;
    logic         dirty_q;
    logic         look_ok;
    logic         hit;
    logic         rd_ok;
    logic         wr_ok;

    logic         wbuf_valid_q;
    logic [15:0]  wbuf_addr_q;
    logic [15:0]  wbuf_data_q;

    logic         wr_apply;
    logic         fill_start;
    logic         hw_take;
    logic         cdata_we;
    logic [11:0]  cdata_waddr;
    logic [15:0]  cdata_wdata;
    logic         ctag_we;
    logic [8:0]   ctag_waddr;
    logic [4:0]   ctag_wdata;

    always_comb begin
        look_addr = rd_en_i ? raddr_i : waddr_i;
        look_ok   = (look_addr == look_addr_q) && !dirty_q && (fill_q == F_IDLE);
        hit       = ctag_q[4] && (ctag_q[3:0] == look_addr_q[15:12]);
        rd_ok     = look_ok && hit;
        wr_ok     = look_ok && !wbuf_valid_q;
        ready_o   = (fill_q == F_IDLE) && (!rd_en_i || rd_ok) && (!wr_en_i || wr_ok);
        rdata_o   = cdata_q;

        fill_start = (fill_q == F_IDLE) && rd_en_i && look_ok && !hit && !wbuf_valid_q;
        wr_apply   = ce_i && wr_en_i && wr_ok;
        /* not in the clock a fill starts: the fill would read the SDRAM word before this write reaches it and then mark the line valid */
        hw_ready_o = (fill_q == F_IDLE) && !wbuf_valid_q && !wr_apply && !fill_start;
        hw_take    = hw_en_i && hw_ready_o;

        rq_req_o   = (fill_q == F_REQ);
        rq_addr_o  = BASE | {8'h00, fill_addr_q[15:3], fill_word_q};     /* BASE is a multiple of 64K words: an OR, not an adder (timing) */
        wq_req_o   = wbuf_valid_q;
        wq_addr_o  = BASE | {8'h00, wbuf_addr_q};
        wq_wdata_o = wbuf_data_q;

        /* cache array write ports: fill word, write-hit update, tag set / clear */
        cdata_we    = 1'b0;
        cdata_waddr = 12'h000;
        cdata_wdata = 16'h0000;
        ctag_we     = 1'b0;
        ctag_waddr  = 9'h000;
        ctag_wdata  = 5'h00;
        if (fill_q == F_INIT) begin
            ctag_we    = 1'b1;
            ctag_waddr = init_q;
        end else if (fill_q == F_REQ && rq_ack_i) begin
            cdata_we    = 1'b1;
            cdata_waddr = {fill_addr_q[11:3], fill_word_q};
            cdata_wdata = rq_rdata_i;
            if (fill_word_q == 3'd7) begin
                ctag_we    = 1'b1;
                ctag_waddr = fill_addr_q[11:3];
                ctag_wdata = {1'b1, fill_addr_q[15:12]};
            end
        end else if (hw_take) begin
            ctag_we    = 1'b1;
            ctag_waddr = hw_addr_i[11:3];
        end else if (wr_apply && hit) begin
            cdata_we    = 1'b1;
            cdata_waddr = waddr_i[11:0];
            cdata_wdata = wdata_i;
        end
    end

    /* cache arrays: simple dual port, registered read, no reset */
    always_ff @(posedge clk) begin
        if (cdata_we)
            cdata[cdata_waddr] <= cdata_wdata;
        cdata_q <= cdata[look_addr[11:0]];
        if (ctag_we)
            ctag[ctag_waddr] <= ctag_wdata;
        ctag_q <= ctag[look_addr[11:3]];
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            fill_q       <= F_INIT;
            init_q       <= 9'd0;
            fill_addr_q  <= 16'h0000;
            fill_word_q  <= 3'd0;
            look_addr_q  <= 16'h0000;
            dirty_q      <= 1'b1;
            wbuf_valid_q <= 1'b0;
            wbuf_addr_q  <= 16'h0000;
            wbuf_data_q  <= 16'h0000;
        end else begin
            look_addr_q <= look_addr;
            dirty_q     <= cdata_we || ctag_we;

            /* write buffer: filled by a DSP write at its ce edge or a host write, emptied by the arbiter ack */
            if (wr_apply) begin
                wbuf_valid_q <= 1'b1;
                wbuf_addr_q  <= waddr_i;
                wbuf_data_q  <= wdata_i;
            end else if (hw_take) begin
                wbuf_valid_q <= 1'b1;
                wbuf_addr_q  <= hw_addr_i;
                wbuf_data_q  <= hw_data_i;
            end else if (wq_ack_i) begin
                wbuf_valid_q <= 1'b0;
            end

            case (fill_q)
                F_INIT: begin
                    init_q <= init_q + 9'd1;
                    if (init_q == 9'd511)
                        fill_q <= F_IDLE;
                end
                F_IDLE: begin
                    if (fill_start) begin
                        fill_addr_q <= look_addr_q;
                        fill_word_q <= 3'd0;
                        fill_q      <= F_REQ;
                    end
                end
                F_REQ: begin
                    if (rq_ack_i) begin
                        fill_word_q <= fill_word_q + 3'd1;
                        if (fill_word_q == 3'd7)
                            fill_q <= F_DONE;
                    end
                end
                F_DONE: fill_q <= F_IDLE;
                default: fill_q <= F_INIT;
            endcase
        end
    end
endmodule
