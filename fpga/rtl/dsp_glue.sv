/*
dsp_glue.sv -- the glue between the 80C186EB and the TMS320C5x of the Courier modem (mailbox, flags, events, overlay / firmware loader, DSP I/O ports).

Where it sits: next to i186_sys (186 I/O ports 0x18..0x1E, 0x40..0x62) and c5x_mem's I/O handshake (the DSP's I/O space), plus the host write port of
c5x_xmem (DSP program memory in SDRAM) and one sdram_arb client for the 186 RAM peek. Single clock, no clock enables here: the DSP side is sampled
with the DSP's own ce_i by the handshake (o_io_req is level, the ack is combinational and immediate).

Reference: ../courier/src/glue/machine.c (machine_iord / machine_iowr 186 side, machine_dsp_rd / machine_dsp_wr DSP side, ovl_host_ack, machine_start_dsp,
dsp_synth_rom, machine_service sample hook). Fixed configuration = call.conf defaults of the SV25 profile: bankwr = 1, port_rb = 1, int23 = 1, hb_timer = 1,
heartbeat = 1, p51div = 0, rom_replies = 0, no cmd override.

What it does
  Before the DSP starts (dsp_run_q = 0): the 186 writes the DSP resident image as 8-byte bursts (i186_sys burst_valid / burst_data). The first 16 bytes are
    the 0x83 reset pattern and are skipped, the next 55420 bytes go to DSP program words 0x8000.. (machine_start_dsp). A write of 4 to 186 port 0x18
    (dsp_start_req) writes the two lookup tables of the on-chip mask ROM (dsp_synth_rom, program 0x0440..0x045F), then releases the DSP (dsp_rst_n_o)
    once every queued program word has reached the memory.
  After the start: 186 ports 0x18/0x1A flags, 0x1C events, 0x1E overlay status/ack, 0x40..0x5E mailbox, 0x60/0x62 data word; DSP ports 0x56..0x60.
  Overlay download (ovl_host_ack): the 186 puts 4 bytes in ports 0x40..0x46 / 0x48..0x4E and writes 1 / 2 to port 0x1E; the bytes become 2 program words
    at the overlay address (set by DSP command 0x02, taken from mailbox word 7). KNOWN-DIFF: the C model collects the bytes and loads them at the 0x1E
    write of 4; here they are written as they arrive, so the DSP could see a half-loaded overlay if it ran that code in between.
  Frame hook (frame_tick_i, once per codec frame): the supervisor ring pointers at 186 RAM 0x29A and 0x29C are compared (HLE stand-in of machine_service);
    event bit 0 is raised when the DSP mailbox is free and they differ; INT0 is raised when an event bit is new or the heartbeat is pending.
  Heartbeat: dsp_timer_exp_i (cumulative DSP timer expiry counter, low 16 bits) -- every frame with new expiries sets hb_pending and adds to hb_count (the 186's
    ring-detect bit, port 0x14, reads hb_count / hb_ticks with hb_ticks = 1).

Not modelled: cmd_ovr / H2D_TWEAK / inject_cmd diagnostics, the diagnostic logs and counters, tdm_irqs.
*/
`default_nettype none

module dsp_glue (
    input  logic        clk,
    input  logic        rst_n,

    /* 186 side: i186_sys io hooks (rd_port is the port of the phase being read, combinational) */
    input  logic [15:0] rd_port_i,
    output logic [7:0]  rd_data_o,
    input  logic        rd_commit_i,
    input  logic        wr_commit_i,
    input  logic [15:0] wr_port_i,
    input  logic [7:0]  wr_data_i,
    output logic        run_o,           /* the DSP has been started: i186_sys routes the ports below to this module */
    output logic        int0_set_o,      /* pulse: ICU INT0 request */
    output logic [63:0] hb_count_o,
    output logic        dbg_msg_ev_o,   /* bring-up: a DSP-to-host message was completed (mailbox word 7 written) */
    output logic [31:0] dbg_msg_o,      /* bring-up: the message's words 6 and 7 (as the 186 reads them at ports 0x5C and 0x5E) */
    output logic [15:0] dbg_cmd_o,      /* bring-up: {command, argument} of the last host-to-DSP command (mailbox words 6 and 7, low bytes, latched when the last mailbox byte is written) */

    /* firmware bursts (i186_sys, before the start) */
    input  logic        rom_loaded_i,    /* the on-chip ROM image was loaded (loader index 2): do not write the synthesised tables */
    input  logic        dsp_start_req_i,
    input  logic        burst_valid_i,
    input  logic [63:0] burst_data_i,

    /* DSP side: c5x_mem I/O handshake */
    input  logic        io_req_i,
    input  logic        io_rd_i,
    input  logic [15:0] io_addr_i,
    input  logic [15:0] io_wdata_i,
    output logic        io_ack_o,
    output logic [15:0] io_rdata_o,
    output logic        dsp_rst_n_o,
    output logic        dsp_int2_o,      /* pulse: message pending raised (INT2 on every host command word 7 write) */
    output logic [15:0] mclk_n_o,        /* port 0x6B, the AC01 master clock divider N */

    /* program memory write port (c5x_xmem host port) */
    output logic        pw_en_o,
    output logic [15:0] pw_addr_o,
    output logic [15:0] pw_data_o,
    input  logic        pw_ready_i,

    /* frame hook and heartbeat */
    input  logic        frame_tick_i,
    input  logic [15:0] dsp_timer_exp_i,

    /* 186 RAM peek (sdram_arb client, read only) */
    output logic        pk_req_o,
    output logic [23:0] pk_addr_o,
    input  logic        pk_ack_i,
    input  logic [15:0] pk_rdata_i
);
    /* ---- constants (machine.c / config.c) */
    localparam logic [15:0] PORT_FLAGS_LO    = 16'h0018;   /* 186: flags56 low byte; 0x18 <- 4 starts the DSP */
    localparam logic [15:0] PORT_FLAGS_HI    = 16'h001A;
    localparam logic [15:0] PORT_EVT         = 16'h001C;
    localparam logic [15:0] PORT_OVL         = 16'h001E;
    localparam logic [15:0] PORT_MBOX_FIRST  = 16'h0040;
    localparam logic [15:0] PORT_MBOX_LAST   = 16'h005E;
    localparam logic [15:0] PORT_DATA_LO     = 16'h0060;
    localparam logic [15:0] PORT_DATA_HI     = 16'h0062;
    localparam logic [7:0]  DSP_PORT_FLAGS   = 8'h56;      /* DSP: flagsD */
    localparam logic [7:0]  DSP_PORT_STATUS  = 8'h57;
    localparam logic [7:0]  DSP_PORT_MBOX    = 8'h58;      /* 0x58..0x5F */
    localparam logic [7:0]  DSP_PORT_DATA    = 8'h60;
    localparam logic [7:0]  DSP_PORT_MCLK_N  = 8'h6B;
    localparam logic [7:0]  OVL_CMD          = 8'h02;      /* host command: next overlay load address in the argument word */
    localparam logic [15:0] RING_RD_PTR      = 16'h029A;   /* supervisor ring pointers in 186 RAM */
    localparam logic [15:0] RING_WR_PTR      = 16'h029C;
    localparam logic [15:0] RESIDENT_WORDS   = 16'd27710;  /* dsp_base_bytes 55420 / 2 */
    localparam logic [15:0] RESIDENT_BASE    = 16'h8000;
    localparam logic [15:0] ROM_TABLE_BASE   = 16'h0440;
    localparam logic [23:0] RAM186_BASE      = 24'h000000; /* SDRAM word address of 186 physical 0 (mem186 BASE) */

    /* ---- the 0x0440 mask-ROM tables (dsp_synth_rom): 16-point constellation then the differential quadrant table */
    function automatic logic [15:0] rom_word(input logic [4:0] idx);
        logic [1:0] ccw [0:3];
        logic [1:0] shift [0:3];
        logic [1:0] quad, q34, k, dibit, prev;
        integer x, y, t, r;
        begin
            ccw[0] = 2'd3; ccw[1] = 2'd1; ccw[2] = 2'd0; ccw[3] = 2'd2;
            shift[0] = 2'd1; shift[1] = 2'd2; shift[2] = 2'd0; shift[3] = 2'd3;
            rom_word = 16'h0000;
            if (idx < 5'd16) begin
                q34  = idx[3:2];
                quad = idx[1:0];
                k = 2'd0;
                for (int j = 3; j >= 0; j = j - 1)
                    if (ccw[j] == quad) k = j[1:0];
                case (q34)
                    2'd0: begin x = 1; y = 1; end
                    2'd1: begin x = 1; y = 3; end
                    2'd2: begin x = 3; y = 1; end
                    default: begin x = 3; y = 3; end
                endcase
                for (r = 0; r < 3; r = r + 1) begin
                    if (r < k) begin t = x; x = -y; y = t; end
                end
                rom_word = {x[3:0], 4'h0, y[3:0], 4'h0};
            end else begin
                dibit = idx[3:2];
                prev  = idx[1:0];
                k = 2'd0;
                for (int j = 3; j >= 0; j = j - 1)
                    if (ccw[j] == prev) k = j[1:0];
                rom_word = {14'h0000, ccw[k + shift[dibit]]};
            end
        end
    endfunction

    /* ---- state */
    logic          run_q;
    logic [15:0]   h2d_q   [0:7];
    logic [15:0]   d2h_q   [0:7];
    logic          h2d_pending_q;
    logic          d2h_valid_q;
    logic [15:0]   d2h_snap_q [4:7];   /* the message the 186 took (port 0x58 read): later DSP writes must not change what its ISR is still reading */
    logic          snap_vld_q;
    logic [15:0]   data_word_q;
    logic          data_full_q;
    logic [15:0]   flags56_q;
    logic [15:0]   flags_d_q;
    logic [15:0]   flags_vis_q;   /* what the DSP reads of flagsD: the 186's writes become visible only once the program words queued before them have been written to the DSP's RAM */
    logic [7:0]    evt_q;
    logic [7:0]    evt_seen_q;
    logic [2:0]    ovl_status_q;
    logic [15:0]   ovl_ptr_q;
    logic [7:0]    ovl_bytes_q [0:7];
    logic [15:0]   mclk_n_q;
    logic          hb_pending_q;
    logic [63:0]   hb_count_q;
    logic [15:0]   exp_prev_q;
    logic [15:0]   port_store [0:255];

    /* ---- program word sequencer + FIFO (burst / ROM / overlay words -> c5x_xmem host port) */
    typedef enum logic [1:0] {
        SQ_IDLE  = 2'd0,
        SQ_BURST = 2'd1,
        SQ_ROM   = 2'd2,
        SQ_OVL   = 2'd3
    } seq_t;
    seq_t          seq_q;
    logic [5:0]    seq_n_q;
    logic [63:0]   burst_q;
    logic [15:0]   res_ptr_q;
    logic [15:0]   res_left_q;
    logic [4:0]    burst_skip_q;
    logic [15:0]   ovl_w0_q, ovl_w1_q;
    logic [15:0]   ovl_addr_q;

    logic [31:0]   fifo_q [0:15];
    logic [4:0]    fifo_wr_q, fifo_rd_q;
    logic          fifo_empty, fifo_full;
    logic          push_en;
    logic [15:0]   push_addr, push_data;

    always_comb begin
        fifo_empty = (fifo_wr_q == fifo_rd_q);
        fifo_full  = (fifo_wr_q[3:0] == fifo_rd_q[3:0]) && (fifo_wr_q[4] != fifo_rd_q[4]);
        pw_en_o    = !fifo_empty;
        pw_addr_o  = fifo_q[fifo_rd_q[3:0]][31:16];
        pw_data_o  = fifo_q[fifo_rd_q[3:0]][15:0];
    end

    /* ---- sequencer output: the word being queued this clock */
    always_comb begin
        push_en   = 1'b0;
        push_addr = 16'h0000;
        push_data = 16'h0000;
        if (!fifo_full) begin
            case (seq_q)
                SQ_BURST: begin
                    push_en   = 1'b1;
                    push_addr = res_ptr_q;
                    push_data = (seq_n_q[1:0] == 2'd0) ? burst_q[15:0] :
                                (seq_n_q[1:0] == 2'd1) ? burst_q[31:16] :
                                (seq_n_q[1:0] == 2'd2) ? burst_q[47:32] : burst_q[63:48];
                end
                SQ_ROM: begin
                    push_en   = 1'b1;
                    push_addr = ROM_TABLE_BASE + {10'h000, seq_n_q};
                    push_data = rom_word(seq_n_q[4:0]);
                end
                SQ_OVL: begin
                    push_en   = 1'b1;
                    push_addr = ovl_addr_q + {15'h0000, seq_n_q[0]};
                    push_data = seq_n_q[0] ? ovl_w1_q : ovl_w0_q;
                end
                default: begin end
            endcase
        end
    end

    /* ---- 186 port decode */
    logic          rd_mbox, wr_mbox;
    logic [2:0]    rd_idx, wr_idx;
    logic          rd_hi, wr_hi;
    always_comb begin
        rd_mbox = (rd_port_i >= PORT_MBOX_FIRST) && (rd_port_i <= PORT_MBOX_LAST) && !rd_port_i[0];
        wr_mbox = (wr_port_i >= PORT_MBOX_FIRST) && (wr_port_i <= PORT_MBOX_LAST) && !wr_port_i[0];
        rd_idx  = rd_port_i[4:2];
        wr_idx  = wr_port_i[4:2];
        rd_hi   = rd_port_i[1];
        wr_hi   = wr_port_i[1];
    end

    always_comb begin
        rd_data_o = 8'h00;
        if (rd_port_i == PORT_FLAGS_LO)
            rd_data_o = flags56_q[7:0];
        else if (rd_port_i == PORT_FLAGS_HI)
            rd_data_o = flags56_q[15:8];
        else if (rd_port_i == PORT_EVT)
            rd_data_o = evt_q;
        else if (rd_port_i == PORT_OVL)
            rd_data_o = {5'b00000, ovl_status_q};
        else if (rd_mbox)
            rd_data_o = (snap_vld_q && rd_idx[2]) ? (rd_hi ? d2h_snap_q[rd_idx][15:8] : d2h_snap_q[rd_idx][7:0]) : (rd_hi ? d2h_q[rd_idx][15:8] : d2h_q[rd_idx][7:0]);
        else if (rd_port_i == PORT_DATA_LO)
            rd_data_o = data_word_q[7:0];
        else if (rd_port_i == PORT_DATA_HI)
            rd_data_o = data_word_q[15:8];
    end

    /* ---- DSP port decode */
    logic [7:0]    dq;
    always_comb begin
        dq        = io_addr_i[7:0];
        io_ack_o  = io_req_i;
        io_rdata_o = port_store[dq];
        if (dq == DSP_PORT_STATUS)
            io_rdata_o = {13'h0000, !data_full_q, !d2h_valid_q, h2d_pending_q};
        else if (dq == DSP_PORT_FLAGS)
            io_rdata_o = flags_vis_q;
        else if (dq >= DSP_PORT_MBOX && dq <= 8'h5F)
            io_rdata_o = h2d_q[dq[2:0]];
    end

    assign run_o       = run_q;
    assign mclk_n_o    = mclk_n_q;
    assign hb_count_o  = hb_count_q;

    /* ---- frame decision (machine_service): ring pointers differ -> event 0; INT0 when the heartbeat is pending or an event bit is new */
    logic ring_diff, int0_n;
    always_comb begin
        ring_diff = !h2d_pending_q && (pk_a_q != pk_rdata_i);
        evt_n     = ring_diff ? (evt_q | 8'h01) : evt_q;
        seen_n    = ring_diff ? (evt_seen_q & ~8'h01) : evt_seen_q;
        int0_n    = hb_pending_q || ((evt_n & ~seen_n) != 8'h00);
        if (int0_n)
            seen_n = seen_n | evt_n;
    end

    /* ---- 186 RAM peek on the frame hook */
    typedef enum logic [2:0] {
        PK_IDLE = 3'd0,
        PK_RD_A = 3'd1,
        PK_RD_B = 3'd2
    } peek_t;
    peek_t         pk_q;
    logic [15:0]   pk_a_q;

    always_comb begin
        pk_req_o  = (pk_q == PK_RD_A) || (pk_q == PK_RD_B);
        pk_addr_o = RAM186_BASE | {8'h00, 1'b0, ((pk_q == PK_RD_A) ? RING_RD_PTR[15:1] : RING_WR_PTR[15:1])};
    end

    logic          int0_q;
    logic [7:0]    evt_n, seen_n;
    logic          int2_q;
    logic [15:0]   dbg_cmd_q;
    assign dbg_cmd_o = dbg_cmd_q;
    logic msg_ev_q;
    assign dbg_msg_ev_o = msg_ev_q;
    assign dbg_msg_o    = {d2h_q[6], d2h_q[7]};
    assign int0_set_o = int0_q;
    assign dsp_int2_o = int2_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            run_q         <= 1'b0;
            h2d_pending_q <= 1'b0;
            d2h_valid_q   <= 1'b0;
            snap_vld_q    <= 1'b0;
            data_word_q   <= 16'h0000;
            data_full_q   <= 1'b0;
            flags56_q     <= 16'h0000;
            flags_d_q     <= 16'h0000;
            flags_vis_q   <= 16'h0000;
            evt_q         <= 8'h00;
            evt_seen_q    <= 8'h00;
            ovl_status_q  <= 3'd0;
            ovl_ptr_q     <= 16'h0000;
            mclk_n_q      <= 16'h0000;
            hb_pending_q  <= 1'b0;
            msg_ev_q      <= 1'b0;
            hb_count_q    <= 64'd0;
            exp_prev_q    <= 16'h0000;
            seq_q         <= SQ_IDLE;
            seq_n_q       <= 6'd0;
            burst_q       <= 64'd0;
            res_ptr_q     <= RESIDENT_BASE;
            res_left_q    <= RESIDENT_WORDS;
            burst_skip_q  <= 5'd2;
            ovl_w0_q      <= 16'h0000;
            ovl_w1_q      <= 16'h0000;
            ovl_addr_q    <= 16'h0000;
            fifo_wr_q     <= 5'd0;
            fifo_rd_q     <= 5'd0;
            pk_q          <= PK_IDLE;
            pk_a_q        <= 16'h0000;
            int0_q        <= 1'b0;
            int2_q        <= 1'b0;
            for (int i = 0; i < 8; i++) begin
                h2d_q[i] <= 16'h0000;
                d2h_q[i] <= 16'h0000;
                ovl_bytes_q[i] <= 8'h00;
            end
        end else begin
            int0_q <= 1'b0;
            int2_q <= 1'b0;
            msg_ev_q <= 1'b0;
            /* a flag the 186 sets after handing over an overlay must not reach the DSP before the overlay is in its RAM: follow flags_d_q only while nothing is queued or being sequenced */
            if (fifo_empty && seq_q == SQ_IDLE)
                flags_vis_q <= flags_d_q;
            /* FIFO drain: the host port takes the head word in a clock where pw_ready_i is high */
            if (!fifo_empty && pw_ready_i)
                fifo_rd_q <= fifo_rd_q + 5'd1;

            /* ---- 186 side: read side effects (committed once per read) */
            if (rd_commit_i && run_q) begin
                if (rd_port_i == 16'h0058) begin
                    d2h_valid_q <= 1'b0;
                    for (int i = 4; i < 8; i++) d2h_snap_q[i] <= d2h_q[i];
                    snap_vld_q  <= 1'b1;
                end
                if (rd_port_i == PORT_DATA_LO)
                    data_full_q <= 1'b0;
            end

            /* ---- 186 side: writes */
            if (wr_commit_i) begin
                if (!run_q) begin
                    /* before the start: 0x18 <- 4 handled by dsp_start_req_i below; bursts by burst_valid_i */
                end else begin
                    if (wr_port_i == PORT_FLAGS_LO) begin
                        flags56_q[7:0] <= flags56_q[7:0] & ~wr_data_i;
                        flags_d_q[7:0] <= flags_d_q[7:0] | wr_data_i;
                    end
                    if (wr_port_i == PORT_FLAGS_HI) begin
                        flags56_q[15:8] <= flags56_q[15:8] & ~wr_data_i;
                        flags_d_q[15:8] <= flags_d_q[15:8] | wr_data_i;
                    end
                    if (wr_port_i == PORT_EVT) begin
                        /* event 0 is "the DSP has taken the command, mailbox free": a clear while the mailbox is already free (the DSP answered before the 186's interrupt handler got to its closing clear) must not eat that event, or the next word waits for the next ring-pointer difference */
                        /* event 1 is "the DSP wrote a message": the 186's ISR takes the message with the port 0x58 read and clears the event at its end; a second message
                           the DSP wrote in between (valid is set again) must keep the event and interrupt the 186 again, or it is never read and the DSP's queue stalls */
                        evt_q      <= evt_q & ~{wr_data_i[7:2], wr_data_i[1] & ~d2h_valid_q, wr_data_i[0] & h2d_pending_q};
                        evt_seen_q <= evt_seen_q & evt_q & ~{wr_data_i[7:2], wr_data_i[1], wr_data_i[0] & h2d_pending_q};
                        if (wr_data_i[1]) begin
                            snap_vld_q <= 1'b0;
                            if (d2h_valid_q) int0_q <= 1'b1;
                        end
                    end
                    if (wr_port_i == PORT_OVL) begin
                        if (wr_data_i[0] || wr_data_i[1]) begin
                            /* 4 bytes -> 2 program words, little endian, at the overlay pointer */
                            ovl_addr_q <= ovl_ptr_q;
                            if (wr_data_i[0]) begin
                                ovl_w0_q <= {ovl_bytes_q[1], ovl_bytes_q[0]};
                                ovl_w1_q <= {ovl_bytes_q[3], ovl_bytes_q[2]};
                            end else begin
                                ovl_w0_q <= {ovl_bytes_q[5], ovl_bytes_q[4]};
                                ovl_w1_q <= {ovl_bytes_q[7], ovl_bytes_q[6]};
                            end
                            ovl_ptr_q <= ovl_ptr_q + 16'd2;
                            seq_q     <= SQ_OVL;
                            seq_n_q   <= 6'd0;
                        end
                        if (wr_data_i[2])
                            ovl_status_q <= ovl_status_q & 3'b011;
                    end
                    if (wr_port_i >= PORT_MBOX_FIRST && wr_port_i <= 16'h004E && !wr_port_i[0])
                        ovl_bytes_q[wr_port_i[3:1]] <= wr_data_i;
                    if (wr_mbox) begin
                        if (wr_hi)
                            h2d_q[wr_idx][15:8] <= wr_data_i;
                        else
                            h2d_q[wr_idx][7:0] <= wr_data_i;
                        if (wr_port_i == PORT_MBOX_LAST) begin
                            dbg_cmd_q     <= {h2d_q[6][7:0], h2d_q[7][7:0]};
                            h2d_pending_q <= 1'b1;
                            int2_q        <= 1'b1;
                        end
                    end
                end
            end

            /* ---- start of the DSP and the loader (before the start) */
            if (!run_q && burst_valid_i) begin
                if (burst_skip_q != 5'd0) begin
                    burst_skip_q <= burst_skip_q - 5'd1;
                end else if (res_left_q != 16'd0) begin
                    burst_q <= burst_data_i;
                    seq_q   <= SQ_BURST;
                    seq_n_q <= 6'd0;
                end
            end
            if (!run_q && dsp_start_req_i) begin
                run_q   <= 1'b1;
                if (!rom_loaded_i) begin
                    seq_q   <= SQ_ROM;
                    seq_n_q <= 6'd0;
                end
            end

            /* ---- sequencer: one word per clock into the FIFO (push_* come from the comb block above) */
            if (push_en) begin
                fifo_q[fifo_wr_q[3:0]] <= {push_addr, push_data};
                fifo_wr_q <= fifo_wr_q + 5'd1;
                seq_n_q   <= seq_n_q + 6'd1;
                if (seq_q == SQ_BURST) begin
                    if (res_left_q != 16'd0) begin
                        res_ptr_q  <= res_ptr_q + 16'd1;
                        res_left_q <= res_left_q - 16'd1;
                    end
                    if (seq_n_q[1:0] == 2'd3)
                        seq_q <= SQ_IDLE;
                end
                if (seq_q == SQ_ROM && seq_n_q == 6'd31)
                    seq_q <= SQ_IDLE;
                if (seq_q == SQ_OVL && seq_n_q[0])
                    seq_q <= SQ_IDLE;
            end

            /* ---- DSP side: port writes (machine_dsp_wr) */
            if (run_q && io_req_i && !io_rd_i) begin
                if (!(dq >= DSP_PORT_FLAGS && dq <= 8'h5F))
                    port_store[dq] <= io_wdata_i;
                if (dq == DSP_PORT_MCLK_N)
                    mclk_n_q <= io_wdata_i;
                if (dq == DSP_PORT_FLAGS) begin
                    flags_d_q <= flags_d_q & ~io_wdata_i;
                    flags56_q <= flags56_q | io_wdata_i;
                end
                if (dq >= DSP_PORT_MBOX && dq <= 8'h5F) begin
                    d2h_q[dq[2:0]] <= io_wdata_i;
                    if (dq == 8'h5F) begin
                        d2h_valid_q <= 1'b1;
                        msg_ev_q    <= 1'b1;
                        evt_q       <= evt_q | 8'h02;
                    end
                end
                if (dq == DSP_PORT_DATA) begin
                    data_word_q <= io_wdata_i;
                    data_full_q <= 1'b1;
                end
                if (dq == DSP_PORT_STATUS) begin
                    if (io_wdata_i[2]) begin
                        evt_q      <= evt_q | 8'h04;
                        evt_seen_q <= evt_seen_q & ~8'h04;
                    end
                    if (io_wdata_i[10:8] != 3'd0)
                        ovl_status_q <= io_wdata_i[10:8];
                    if (io_wdata_i[0]) begin
                        h2d_pending_q <= 1'b0;
                        evt_q         <= evt_q | 8'h01;
                        if (h2d_q[6][7:0] == OVL_CMD)
                            ovl_ptr_q <= h2d_q[7];
                    end
                end
            end

            /* ---- frame hook: ring pointer peek, heartbeat, INT0 */
            if (run_q && frame_tick_i && pk_q == PK_IDLE) begin
                exp_prev_q <= dsp_timer_exp_i;
                if (dsp_timer_exp_i != exp_prev_q) begin
                    hb_pending_q <= 1'b1;
                    hb_count_q   <= hb_count_q + {48'd0, dsp_timer_exp_i - exp_prev_q};
                end
                pk_q <= PK_RD_A;
            end
            case (pk_q)
                PK_RD_A: begin
                    if (pk_ack_i) begin
                        pk_a_q <= pk_rdata_i;
                        pk_q   <= PK_RD_B;
                    end
                end
                PK_RD_B: begin
                    if (pk_ack_i) begin
                        pk_q       <= PK_IDLE;
                        evt_q      <= evt_n;
                        evt_seen_q <= seen_n;
                        if (int0_n) begin
                            int0_q       <= 1'b1;
                            hb_pending_q <= 1'b0;
                        end
                    end
                end
                default: begin end
            endcase
        end
    end

    /* the DSP is released once the start was requested and every program word of the initial load (ROM image, resident image) has reached the memory, and then it runs: a later
       overlay load copies words into its memory while it keeps running (resetting it there wiped its state, the vector-table pointer included, and it fell into the ROM boot-loader) */
    logic run_d_q, go_q;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            run_d_q <= 1'b0;
            go_q    <= 1'b0;
        end else begin
            run_d_q <= run_q;
            if (run_q && run_d_q && seq_q == SQ_IDLE && fifo_empty)
                go_q <= 1'b1;
        end
    end
    assign dsp_rst_n_o = go_q;
endmodule
