/*
mem186.sv -- the 80C186EB's 1 MB physical memory in SDRAM (arbiter client 0), lean version for the aligned clocks.

FPGA-only plumbing. clk_c is the 186's clock, clk_m the SDRAM / arbiter clock; they come from one PLL and are phase aligned (clk_m = N x clk_c, N = 4 on the board), so the two
sides talk through plain registers, no handshake round trip: the SDRAM side reads the CPU side's request signals directly (they are stable from the clk_c edge that raises h_req until
the one that drops it) and answers with one level, done_m, that the CPU side samples with one register. Latency added to the SDRAM access: one clk_m for the request to be
seen, one clk_c of sampling for the answer. (STA times these paths as one clk_m period; the logic between them is a few LUTs.)

Sits behind the h_* hook port of i186_sys: h_req is held until h_ack, h_ack is a level held until h_req drops, and h_req stays low for at least one clk_c between accesses (that is
what lets done_m be cleared in time: it falls within two clk_m of h_req falling, before the next clk_c edge could sample it).
Physical address a (20 bit): SDRAM word BASE + a[19:1], byte lanes little-endian (even address = low byte), the layout the loader writes (flash image at 0x80000..0xFFFFF; i186_sys
already drops writes to the flash pages). Byte access: one word access with one lane enable. Even word: one access. Odd word: two accesses (high byte of word a[19:1], low byte of the
next word), data merged here.
Flash-ID window (the C model's mmio hook, machine.c mmrd/mmwr): a write of 0x90 to 0xFFFF0 sets flash_id, 0xFF clears it; while set, a read at 0xFFFF0 returns 0x0089 and at 0xFFFF2 returns
0x4470 (h_is_mmio marks the access as coming from the MMIO page). Answered on the CPU side, no SDRAM access.
Not modelled: parity, wait states (the 186's own bus timing is the core's job).
*/
`default_nettype none

module mem186 #(
    parameter [23:0] BASE = 24'h000000
) (
    input  logic        clk_c,
    input  logic        clk_m,
    input  logic        rst_n_m,         /* reset of the SDRAM-side state (clk_m domain) */

    input  logic        h_req,
    input  logic        h_wr,
    input  logic        h_word,
    input  logic        h_is_mmio,
    input  logic [19:0] h_addr,
    input  logic [15:0] h_wdata,
    output logic [15:0] h_rdata,
    output logic        h_ack,

    /* arbiter client (clk_m domain) */
    output logic        rq_req_o,
    output logic        rq_we_o,
    output logic [1:0]  rq_be_o,
    output logic [23:0] rq_addr_o,
    output logic [15:0] rq_wdata_o,
    input  logic        rq_ack_i,
    input  logic [15:0] rq_rdata_i
);
    /* ---- CPU side: flash-ID window and the sampled answer */
    logic        flash_id_q, fid_ack_q, done_c_q;
    logic [15:0] fid_rdata_q;
    logic        is_flash_cmd, is_flash_rd, fid_hit, sd_req;
    logic        done_m;
    logic [15:0] rdata_m;

    always_comb begin
        is_flash_cmd = h_is_mmio && h_wr && (h_addr >= 20'hFFFF0) && (h_addr <= 20'hFFFF1);
        is_flash_rd  = h_is_mmio && !h_wr && flash_id_q && (h_addr >= 20'hFFFF0) && (h_addr <= 20'hFFFF3);
        fid_hit      = h_req && (is_flash_cmd || is_flash_rd);
        sd_req       = h_req && !fid_hit;
        h_ack        = fid_ack_q || (done_c_q && sd_req);
        h_rdata      = fid_ack_q ? fid_rdata_q : rdata_m;
    end

    always_ff @(posedge clk_c) begin
        done_c_q  <= done_m;
        fid_ack_q <= fid_hit;
        if (fid_hit && !fid_ack_q) begin
            if (is_flash_cmd)
                flash_id_q <= (h_wdata[7:0] == 8'h90) ? 1'b1 : (h_wdata[7:0] == 8'hFF) ? 1'b0 : flash_id_q;
            fid_rdata_q <= is_flash_rd ? ((h_addr[1:0] == 2'b00) ? 16'h0089 : 16'h4470) : 16'h0000;
        end
    end

    /* ---- SDRAM side: the request is copied into clk_m registers in M_IDLE (the CPU side holds it stable), the rest works on the copy */
    typedef enum logic [1:0] { M_IDLE = 2'd0, M_A0 = 2'd1, M_A1 = 2'd2, M_DONE = 2'd3 } mstate_t;
    mstate_t     mst_q;
    logic [7:0]  lo_q;
    logic        wr_q, word_q;
    logic [19:0] addr_q;
    logic [15:0] wdata_q;
    logic        odd;
    logic [19:0] addr_next;
    logic [1:0]  be0, be1;
    logic [15:0] wd0, wd1;

    always_comb begin
        odd       = addr_q[0] && word_q;
        addr_next = addr_q + 20'd1;
        be0 = 2'b11; be1 = 2'b00; wd0 = wdata_q; wd1 = 16'h0000;
        if (!word_q) begin
            be0 = addr_q[0] ? 2'b10 : 2'b01;
            wd0 = addr_q[0] ? {wdata_q[7:0], 8'h00} : {8'h00, wdata_q[7:0]};
        end else if (addr_q[0]) begin
            be0 = 2'b10; wd0 = {wdata_q[7:0], 8'h00};
            be1 = 2'b01; wd1 = {8'h00, wdata_q[15:8]};
        end
        rq_req_o   = (mst_q == M_A0) || (mst_q == M_A1);
        rq_we_o    = wr_q;
        rq_be_o    = (mst_q == M_A1) ? be1 : be0;
        rq_addr_o  = BASE | {4'h0, ((mst_q == M_A1) ? addr_next[19:1] : addr_q[19:1])};   /* BASE is a multiple of 512K words: an OR (timing) */
        rq_wdata_o = (mst_q == M_A1) ? wd1 : wd0;
        done_m     = (mst_q == M_DONE);
    end

    always_ff @(posedge clk_m) begin
        if (!rst_n_m) begin
            mst_q   <= M_IDLE;
            rdata_m <= 16'h0000;
            lo_q    <= 8'h00;
            wr_q    <= 1'b0;
            word_q  <= 1'b0;
            addr_q  <= 20'h00000;
            wdata_q <= 16'h0000;
        end else begin
            case (mst_q)
                M_IDLE: begin
                    if (sd_req) begin
                        wr_q    <= h_wr;
                        word_q  <= h_word;
                        addr_q  <= h_addr;
                        wdata_q <= h_wdata;
                        mst_q   <= M_A0;
                    end
                end
                M_A0: begin
                    if (rq_ack_i) begin
                        if (!wr_q) begin
                            if (!word_q)
                                rdata_m <= {8'h00, addr_q[0] ? rq_rdata_i[15:8] : rq_rdata_i[7:0]};
                            else if (!addr_q[0])
                                rdata_m <= rq_rdata_i;
                            else
                                lo_q <= rq_rdata_i[15:8];
                        end
                        mst_q <= odd ? M_A1 : M_DONE;
                    end
                end
                M_A1: begin
                    if (rq_ack_i) begin
                        if (!wr_q)
                            rdata_m <= {rq_rdata_i[7:0], lo_q};
                        mst_q <= M_DONE;
                    end
                end
                M_DONE: if (!sd_req) mst_q <= M_IDLE;
                default: mst_q <= M_IDLE;
            endcase
        end
    end
endmodule
