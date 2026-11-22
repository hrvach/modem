/*
line_ddr.sv -- the modem's phone line, as two sample rings in the HPS DDR memory (the core's DDRAM port, clocked by clk, the 20.16 MHz CPU clock).

  TX ring: the DAC samples (at the codec rate), packed four per 64-bit word, written in order; the HPS reads them.
  RX ring: the ADC samples, written by the HPS, consumed one per rx_next_i pulse (the codec frame); an empty ring gives 0 and counts an underrun.

Layout, in 64-bit words from BASE (the HPS maps physical 8 * (BASE_QADDR + n)):
  0x000  magic: the bytes "MDMLINE1" in memory
  0x001  tx_count:   DAC samples written so far (monotonic, 32 bit); the ring data are valid up to it
  0x002  rx_taken:   ADC samples consumed so far
  0x003  status:     [15:0] rate_cps (DSP cycles per codec frame: 40.32 MHz / cps = codec rate), [31:16] underruns, [47:32] tx_lost, [63:48] version = 1
  0x008  control, written by the HPS: [31:0] rx_count = ADC samples made available (monotonic), [32] ring request (the modem sees RING), [33] line connected
  0x400  TX ring, 4096 words (16384 samples)
  0x1400 RX ring, 4096 words
The FPGA writes the data word first and the count after it, so a count the HPS reads always covers valid data.
*/
`default_nettype none

module line_ddr #(
    parameter logic [28:0] BASE_QADDR = 29'h07400000     /* physical 0x3A000000 */
) (
    input  logic        clk,
    input  logic        rst_n,

    /* the modem side, all in the clk domain */
    input  logic        dac_valid_i,                      /* one DAC sample */
    input  logic signed [15:0] dac_sample_i,
    input  logic        rx_next_i,                        /* the codec took the current ADC sample: advance */
    output logic signed [15:0] rx_sample_o,
    input  logic [15:0] rate_cps_i,                       /* from the codec model (other clock domain, quasi static) */
    output logic        ring_req_o,                       /* the HPS asks for a RING */
    output logic        connected_o,                      /* the HPS has a call up */

    /* DDRAM, Avalon-MM master */
    output logic [28:0] ddr_addr_o,
    output logic [7:0]  ddr_burstcnt_o,
    input  logic        ddr_busy_i,
    input  logic [63:0] ddr_dout_i,
    input  logic        ddr_dout_ready_i,
    output logic        ddr_rd_o,
    output logic [63:0] ddr_din_o,
    output logic [7:0]  ddr_be_o,
    output logic        ddr_we_o,
    output logic        active_o,                         /* a command is being issued this clock (the port is in use) */
    output logic        trace_fz_o,                       /* word A_TRCTL bit 1, set by the HPS: freeze the DSP trace now (the call ended) */
    output logic        trace_en_o                        /* word A_TRCTL bit 0, set by the HPS: the DSP instruction trace may use the port (off after a reset) */
);
    localparam logic [28:0] A_MAGIC = 29'h000, A_TXCNT = 29'h001, A_RXTAKEN = 29'h002, A_STATUS = 29'h003, A_CTRL = 29'h008, A_TRCTL = 29'h009;
    localparam logic [28:0] A_TX = 29'h400, A_RX = 29'h1400;
    localparam logic [11:0] RING_MASK = 12'hFFF;

    /* ---- DAC side: collect four samples */
    logic [63:0] tx_acc_q;
    logic [1:0]  tx_n_q;
    logic [31:0] tx_count_q;            /* samples completed into words */
    logic        tx_full_q;             /* a full word waits for the sequencer */
    logic [63:0] tx_word_q;
    logic [15:0] tx_lost_q;

    /* ---- ADC side */
    logic [63:0] rx_buf_q;
    logic [2:0]  rx_have_q;             /* samples left in rx_buf_q, 0..4 */
    logic [31:0] rx_fetched_q;          /* samples loaded into rx_buf_q so far (multiple of 4) */
    logic [31:0] rx_taken_q;
    logic [31:0] rx_avail_q;            /* from the control word */
    logic signed [15:0] rx_cur_q;
    logic [15:0] under_q;
    logic        ring_q, conn_q;
    logic        trc_en_q, trc_fz_q;
    assign trace_en_o = trc_en_q;
    assign trace_fz_o = trc_fz_q;
    logic        synced_q;              /* the first control read after reset has set the RX counters to the HPS's count */
    assign rx_sample_o = rx_cur_q;
    assign ring_req_o  = ring_q;
    assign connected_o = conn_q;

    /* rate_cps from the DSP clock domain: two flops, the value changes only on a codec rate change */
    logic [15:0] cps_a_q, cps_b_q;

    /* ---- sequencer */
    typedef enum logic [3:0] {
        S_INIT, S_IDLE, S_WR_DATA, S_WR_CNT, S_WR_TAKEN, S_WR_STAT, S_RD_CTRL, S_RD_CTRL_W, S_RD_RX, S_RD_RX_W, S_RD_TRC, S_RD_TRC_W
    } st_t;
    st_t         st_q;
    logic [15:0] poll_q;                /* housekeeping tick: control read / status write about every 0.8 ms */
    logic [1:0]  hk_q;                  /* which housekeeping step is due: 1 = control read, 2 = taken+status writes */
    logic [11:0] tx_widx_q;

    logic        issue_wr, issue_rd;
    logic [28:0] issue_a;
    logic [63:0] issue_d;
    always_comb begin
        ddr_burstcnt_o = 8'd1;
        ddr_be_o       = 8'hFF;
        ddr_addr_o     = BASE_QADDR + issue_a;
        ddr_din_o      = issue_d;
        ddr_we_o       = issue_wr;
        ddr_rd_o       = issue_rd;
        active_o       = issue_wr | issue_rd;
    end

    logic rx_need;
    always_comb begin
        rx_need = (rx_have_q == 3'd0) && ((rx_avail_q - rx_fetched_q) >= 32'd4) && !(rx_avail_q - rx_fetched_q >= 32'h80000000);
    end

    always_comb begin
        issue_wr = 1'b0; issue_rd = 1'b0; issue_a = 29'd0; issue_d = 64'd0;
        case (st_q)
            S_INIT:      begin issue_wr = 1'b1; issue_a = A_MAGIC;   issue_d = "1ENILMDM";   /* the first character lands in the top byte: memory reads MDMLINE1 */ end
            S_WR_DATA:   begin issue_wr = 1'b1; issue_a = A_TX + {17'd0, tx_widx_q}; issue_d = tx_word_q; end
            S_WR_CNT:    begin issue_wr = 1'b1; issue_a = A_TXCNT;   issue_d = {32'd0, tx_count_q}; end
            S_WR_TAKEN:  begin issue_wr = 1'b1; issue_a = A_RXTAKEN; issue_d = {32'd0, rx_taken_q}; end
            S_WR_STAT:   begin issue_wr = 1'b1; issue_a = A_STATUS;  issue_d = {16'd1, tx_lost_q, under_q, cps_b_q}; end
            S_RD_CTRL:   begin issue_rd = 1'b1; issue_a = A_CTRL; end
            S_RD_TRC:    begin issue_rd = 1'b1; issue_a = A_TRCTL; end
            S_RD_RX:     begin issue_rd = 1'b1; issue_a = A_RX + {17'd0, rx_fetched_q[13:2] & RING_MASK}; end
            default: ;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            tx_acc_q <= 64'd0; tx_n_q <= 2'd0; tx_count_q <= 32'd0; tx_full_q <= 1'b0; tx_word_q <= 64'd0; tx_lost_q <= 16'd0;
            rx_buf_q <= 64'd0; rx_have_q <= 3'd0; rx_fetched_q <= 32'd0; rx_taken_q <= 32'd0; rx_avail_q <= 32'd0;
            rx_cur_q <= 16'sd0; under_q <= 16'd0; ring_q <= 1'b0; conn_q <= 1'b0; synced_q <= 1'b0; trc_en_q <= 1'b0; trc_fz_q <= 1'b0;
            cps_a_q <= 16'd0; cps_b_q <= 16'd0;
            st_q <= S_INIT; poll_q <= 16'd0; hk_q <= 2'd0; tx_widx_q <= 12'd0;
        end else begin
            cps_a_q <= rate_cps_i;
            cps_b_q <= cps_a_q;

            /* DAC samples */
            if (dac_valid_i) begin
                tx_acc_q[{tx_n_q, 4'b0000} +: 16] <= dac_sample_i;
                tx_n_q <= tx_n_q + 2'd1;
                if (tx_n_q == 2'd3) begin
                    if (tx_full_q) tx_lost_q <= tx_lost_q + 16'd1;
                    else begin
                        tx_word_q <= {dac_sample_i, tx_acc_q[47:0]};
                        tx_full_q <= 1'b1;
                    end
                end
            end

            /* ADC sample: the codec took the current one */
            if (rx_next_i) begin
                if (rx_have_q != 3'd0) begin
                    rx_cur_q   <= $signed(rx_buf_q[15:0]);
                    rx_buf_q   <= {16'd0, rx_buf_q[63:16]};
                    rx_have_q  <= rx_have_q - 3'd1;
                    rx_taken_q <= rx_taken_q + 32'd1;
                end else begin
                    rx_cur_q  <= 16'sd0;
                    under_q   <= under_q + 16'd1;
                end
            end

            poll_q <= poll_q + 16'd1;
            if (poll_q == 16'hFFFF) hk_q <= 2'd1;

            case (st_q)
                S_INIT:      if (!ddr_busy_i) st_q <= S_IDLE;
                S_IDLE: begin
                    if (tx_full_q)           st_q <= S_WR_DATA;
                    else if (hk_q == 2'd1)   st_q <= S_RD_CTRL;
                    else if (hk_q == 2'd2)   st_q <= S_WR_TAKEN;
                    else if (rx_need)        st_q <= S_RD_RX;
                end
                S_WR_DATA:   if (!ddr_busy_i) begin
                    tx_full_q  <= 1'b0;
                    tx_count_q <= tx_count_q + 32'd4;
                    tx_widx_q  <= tx_widx_q + 12'd1;
                    st_q       <= S_WR_CNT;
                end
                S_WR_CNT:    if (!ddr_busy_i) st_q <= S_IDLE;
                S_WR_TAKEN:  if (!ddr_busy_i) st_q <= S_WR_STAT;
                S_WR_STAT:   if (!ddr_busy_i) begin hk_q <= 2'd0; st_q <= S_IDLE; end
                S_RD_CTRL:   if (!ddr_busy_i) st_q <= S_RD_CTRL_W;
                S_RD_CTRL_W: if (ddr_dout_ready_i) begin
                    rx_avail_q <= ddr_dout_i[31:0];
                    /* the control word keeps the HPS's count across a core reload, our counters restart at 0: take its count as the starting point, or the old ring content is played back */
                    if (!synced_q) begin
                        synced_q     <= 1'b1;
                        rx_fetched_q <= ddr_dout_i[31:0];
                        rx_taken_q   <= ddr_dout_i[31:0];
                        rx_have_q    <= 3'd0;
                    end
                    ring_q     <= ddr_dout_i[32];
                    conn_q     <= ddr_dout_i[33];
                    hk_q       <= 2'd2;
                    st_q       <= S_RD_TRC;
                end
                S_RD_TRC:    if (!ddr_busy_i) st_q <= S_RD_TRC_W;
                S_RD_TRC_W:  if (ddr_dout_ready_i) begin
                    trc_en_q <= ddr_dout_i[0];
                    trc_fz_q <= trc_fz_q | ddr_dout_i[1];     /* sticky until the core is reloaded */
                    st_q     <= S_IDLE;
                end
                S_RD_RX:     if (!ddr_busy_i) st_q <= S_RD_RX_W;
                S_RD_RX_W:   if (ddr_dout_ready_i) begin
                    rx_buf_q     <= ddr_dout_i;
                    rx_have_q    <= 3'd4;
                    rx_fetched_q <= rx_fetched_q + 32'd4;
                    st_q         <= S_IDLE;
                end
                default: st_q <= S_IDLE;
            endcase

            /* a fresh word from the ring: the first sample becomes current when the codec next asks; nothing else to do here */
        end
    end
endmodule
