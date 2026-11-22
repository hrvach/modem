/*
modem_core.sv -- the USRobotics Courier modem: 80C186EB supervisor + TMS320C5x DSP + glue, memories in SDRAM.

FPGA-only integration. Everything outside the MiSTer framework (hps_io, video, audio output stage, the pins) lives here and is testable on its own: this module
has no framework ports, only the SDRAM bus, the OSD file download stream, the DTE serial pins and the line audio.

Clocking: three clocks from one PLL, phase aligned (80.64 = 2 x 40.32 = 4 x 20.16 MHz):
  clk     : 80.64 MHz  SDRAM controller (CL2), arbiter, file loader, SDRAM probe (the hps_io clock too)
  clk_dsp : 40.32 MHz  the DSP core and its program RAM, the codec model (the model's own clock: one model cycle per clock)
  clk_cpu : 20.16 MHz  the 186 (the 20.16 MHz SV20 supervisor's clock; SV25 firmware needs 25.8048 MHz and does not run), glue, DTE UART, memory-access clients
The cores run every clock; they stall (their clock enable is a level, not a divided slot) while a memory access is outstanding. The SDRAM clients on the CPU side cross to the
arbiter through xdom_req (four-phase handshake, STA times the crossings as one fast clock); the few slow-moving values going the other way (reset, ROM-loaded, EEPROM load)
are resynchronised here. The DSP and the glue exchange through the handshakes of rtl/cdc.sv with one register per crossing flag (aligned clocks, timed by STA).
Memory map in the SDRAM (word addresses): 0x000000.. the 186's 1 MB (RAM 0..0x7FFFF, flash image at 0x80000, loaded by loader), 0x0C0000.. the DSP's 64K-word
program / unified memory (c5x_xmem). DSP data RAM (B0/B1/B2/SARAM, 4K words) is inside c5x_mem.

Arbiter clients (priority order): 0 186 memory, 1 DSP cache line fills, 2 DSP write-through, 3 ring-pointer peek (dsp_glue), 4 file loader.
The cores are held in reset while a file is downloading (loader busy), until the SDRAM is up and calibrated, and while the OSD / HPS reset request is active. That request does NOT reach
the SDRAM controller, the arbiter, the loader, the probe or the UART: MiSTer holds RESET high while it downloads the boot files, and the loader has to work then. A reset therefore
keeps the SDRAM contents (no reload needed).
Not modelled: the second modem and the line between two modems (the line input is a silence source with the C model's noise floor), the DTE flow-control lines.
*/
`default_nettype none

module modem_core (
    input  logic        clk,                /* memory clock */
    input  logic        clk_cpu,            /* CPU clock: clk / 4, phase aligned */
    input  logic        clk_dsp,            /* DSP clock: 40.32 MHz, unrelated to the others (every crossing goes through rtl/cdc.sv) */
    input  logic        reset_i,            /* asynchronous request: synchronised here */
    input  logic        pll_locked_i,

    /* SDRAM pins */
    output logic        SDRAM_CLK,
    output logic        SDRAM_CKE,
    output logic [12:0] SDRAM_A,
    output logic [1:0]  SDRAM_BA,
    input  logic [15:0] SDRAM_DQ_I,         /* the pad is in the top: SDRAM_DQ = SDRAM_DQ_OE ? SDRAM_DQ_O : 'Z */
    output logic [15:0] SDRAM_DQ_O,
    output logic        SDRAM_DQ_OE,
    output logic        SDRAM_DQML,
    output logic        SDRAM_DQMH,
    output logic        SDRAM_nCS,
    output logic        SDRAM_nCAS,
    output logic        SDRAM_nRAS,
    output logic        SDRAM_nWE,

    /* OSD file download (hps_io, byte wide) */
    input  logic        ioctl_download_i,
    input  logic [15:0] ioctl_index_i,
    output logic        ioctl_wait_o,
    input  logic        ioctl_wr_i,
    input  logic [26:0] ioctl_addr_i,
    input  logic [7:0]  ioctl_dout_i,

    /* DTE (the HPS UART pins and the keyboard terminal) */
    input  logic        dbg_markers_i,      /* OSD: send marker characters on the DTE port for bring-up (F N M files loaded, S 186 started, D DSP started) */
    input  logic        uart_rxd_i,
    output logic        uart_txd_o,
    input  logic        term_rx_valid_i,    /* a byte typed on the keyboard terminal, as if the DTE had sent it */
    input  logic [7:0]  term_rx_byte_i,
    output logic        dte_tx_valid_o,     /* a byte the modem sent to the DTE (for the terminal screen) */
    output logic [7:0]  dte_tx_byte_o,

    /* line audio out (signed, at the codec rate) */
    output logic        dac_valid_o,
    output logic signed [15:0] dac_sample_o,

    /* the phone line as sample rings in HPS DDR memory (rtl/line_ddr.sv), clocked by clk_cpu */
    output logic [28:0] ddr_addr_o,
    output logic [7:0]  ddr_burstcnt_o,
    input  logic        ddr_busy_i,
    input  logic [63:0] ddr_dout_i,
    input  logic        ddr_dout_ready_i,
    output logic        ddr_rd_o,
    output logic [63:0] ddr_din_o,
    output logic [7:0]  ddr_be_o,
    output logic        ddr_we_o,
    output logic        line_connected_o,
    output logic        speaker_on_o,       /* the firmware's speaker latch (ATM / ATL): on = the modem's speaker plays the line */
    output logic signed [15:0] line_rx_o,       /* the ADC sample the codec is being given (speaker monitor), clk_cpu domain */

    /* status */
    output logic        dsp_run_o,
    output logic        loading_o,
    output logic        sdram_ready_o,
    output logic        core_running_o,     /* the cores are out of reset */
    output logic [19:0] pc186_o,            /* bring-up observation: the 186's physical program counter, its bad-opcode flag, the DSP's program counter */
    output logic        badop186_o,
    output logic [15:0] pcdsp_o,
    output logic [15:0] dbg_words_o,        /* bring-up: loader words written, SDRAM probe (reset-vector word, test result), calibrated capture edge */
    output logic [15:0] dbg_vec_o,
    output logic [15:0] dbg_ifr_o,           /* DSP interrupt flags (heartbeat N=) */
    output logic [15:0] dbg_spc_o,           /* DSP serial port control / status (heartbeat W=) */
    output logic        dbg_test_ok_o,
    output logic [1:0]  dbg_cap_o,
    output logic        dbg_cal_ok_o,
    output logic [2:0]  dbg_cal_mask_o,
    output logic [19:0] dbg_jfrom_o,         /* bring-up: the first time the 186's PC left valid code (RAM image below 0x1B14, flash from 0x80000): last valid PC, first invalid PC */
    output logic [19:0] dbg_jto_o,
    output logic        dbg_text_o,         /* the heartbeat text on the DTE pin is on: toggled by Ctrl-A Ctrl-A Ctrl-A then D on the serial port (no OSD needed), off after reset */
    output logic        dbg_jlat_o,
    input  logic [1:0]  dbg_tr_sel_i,        /* which frozen ring (see dbg_status) */
    output logic        dbg_trap_o,          /* the trap froze the rings: codec rate outside {7200, 9600, 10237} Hz for 5 ms, or no codec frame for 10 ms */
    input  logic [5:0]  dbg_tr_idx_i,        /* bring-up: the frozen ring of the last 64 accesses of the 186's memory port (see bus_trace) */
    output logic [37:0] dbg_tr_data_o,
    output logic [24:0] dbg_icu_o,           /* bring-up: interrupt controller state, INT0 / frame counts, DSP timer expiries */
    output logic [15:0] dbg_int0_o,
    output logic [15:0] dbg_texp_o,
    output logic [15:0] dbg_frames_o,
    output logic [15:0] dbg_rxc_o,           /* bring-up: bytes the DTE UART received, bytes the 186 sent to the DTE, share of clk_cpu cycles the 186 was enabled (0xFFFF = 100%) */
    output logic [15:0] dbg_txc_o,
    output logic [15:0] dbg_duty_o,
    output logic [15:0] dbg_idle_o,           /* DSP IDLE share of the last window (bring-up) */
    output logic [15:0] dbg_dxrc_o,          /* bring-up: DXR writes of the DSP, DAC samples the codec model produced, peak |DAC sample| since the last frame of 2^22 clocks */
    output logic [15:0] dbg_dacc_o,
    output logic [15:0] dbg_peak_o,
    output logic [63:0] dbg_dspg_o          /* DSP interrupt state for the heartbeat (G=): {ST0, IMR, PMST, rptc[7:0], halted, idle, sp} */
);
    /* ---- reset: synchronised, held while the PLL is unlocked, the SDRAM is not ready or a file is loading */
    logic [3:0]  rst_sync_q;         /* power-up / PLL lock only: the SDRAM controller, arbiter, loader, probe and UART */
    logic [3:0]  req_sync_q;         /* the OSD / HPS / button reset request: the cores and the glue only */
    localparam integer CPU_HZ = 20160000;   /* the 186's clock: the DTE UART divisor follows it (the serial rate is 115200) */
    logic        sd_init;
    logic        sd_ready;
    logic        loader_busy;
    logic        rst_n;

    always_ff @(posedge clk) begin
        rst_sync_q <= {rst_sync_q[2:0], pll_locked_i};
        req_sync_q <= {req_sync_q[2:0], !reset_i};
    end

    /* sdram16's ready drops during every access: "up" means it has been ready once since the init pulse */
    logic        sd_up_q;
    logic        sd_seen_q;
    logic        cal_done;
    always_ff @(posedge clk) begin
        if (sd_init) begin
            sd_up_q   <= 1'b0;
            sd_seen_q <= 1'b0;
        end else begin
            if (sd_ready)
                sd_seen_q <= 1'b1;
            if (sd_seen_q && cal_done)
                sd_up_q <= 1'b1;
        end
    end

    assign sd_init       = !rst_sync_q[3];
    /* one register drives the whole reset tree (SDC: false path from it; the cores sample reset only at their enable edges) */
    logic rst_n_q;
    always_ff @(posedge clk)
        rst_n_q <= rst_sync_q[3] && req_sync_q[3] && sd_up_q && !loader_busy;
    /* CPU-domain copies of the slow control signals */
    logic [1:0] rcpu_q, ucpu_q, rlcpu_q, bcpu_q;
    logic [3:0] slcpu_q;
    logic       rom_loaded_c, uart_rst_n, loader_busy_c;
    logic [1:0] ld_slot_c;
    always_ff @(posedge clk_cpu) begin
        rcpu_q  <= {rcpu_q[0], rst_n_q};
        ucpu_q  <= {ucpu_q[0], !sd_init};
        rlcpu_q <= {rlcpu_q[0], rom_loaded};
        bcpu_q  <= {bcpu_q[0], loader_busy};
        slcpu_q <= {slcpu_q[1:0], ld_slot};
    end
    assign rst_n         = rcpu_q[1];
    assign uart_rst_n    = ucpu_q[1];
    assign rom_loaded_c  = rlcpu_q[1];
    assign loader_busy_c = bcpu_q[1];
    assign ld_slot_c     = slcpu_q[3:2];
    assign sdram_ready_o = sd_up_q;
    assign loading_o     = loader_busy;
    assign core_running_o = rst_n_q;

    /* ---- SDRAM controller + arbiter */
    logic        sd_rd, sd_we;
    logic [1:0]  sd_wtbt;
    logic [24:0] sd_addr;
    logic [15:0] sd_din, sd_dout;
    logic        sd_idle_ok;
    logic [1:0]  cap_extra;

    sdram16 #(
        .CAS_LATENCY        (3'd2),         /* 80.64 MHz */
        .CYCLES_PER_REFRESH (14'd600)       /* 7.44 us */
    ) u_sdram (
        .init       (sd_init),
        .cap_extra  (cap_extra),
        .clk        (clk),
        .SDRAM_DQ_I  (SDRAM_DQ_I),
        .SDRAM_DQ    (SDRAM_DQ_O),
        .SDRAM_DQ_OE (SDRAM_DQ_OE),
        .SDRAM_A    (SDRAM_A),
        .SDRAM_DQML (SDRAM_DQML),
        .SDRAM_DQMH (SDRAM_DQMH),
        .SDRAM_BA   (SDRAM_BA),
        .SDRAM_nCS  (SDRAM_nCS),
        .SDRAM_nWE  (SDRAM_nWE),
        .SDRAM_nRAS (SDRAM_nRAS),
        .SDRAM_nCAS (SDRAM_nCAS),
        .SDRAM_CKE  (SDRAM_CKE),
        .SDRAM_CLK  (SDRAM_CLK),
        .wtbt       (sd_wtbt),
        .addr       (sd_addr),
        .dout       (sd_dout),
        .din        (sd_din),
        .we         (sd_we),
        .rd         (sd_rd),
        .ready      (sd_ready),
        .idle_ok    (sd_idle_ok)
    );

    localparam integer NCL = 6;
    logic [NCL-1:0]    cl_req, cl_we, cl_ack;
    logic [2*NCL-1:0]  cl_be;
    logic [24*NCL-1:0] cl_addr;
    logic [16*NCL-1:0] cl_wdata;
    logic [15:0]       arb_rdata;

    sdram_arb #(
        .N  (NCL),
        .AW (24)
    ) u_arb (
        .clk       (clk),
        .rst_n     (!sd_init),
        .req_i     (cl_req),
        .we_i      (cl_we),
        .be_i      (cl_be),
        .addr_i    (cl_addr),
        .wdata_i   (cl_wdata),
        .ack_o     (cl_ack),
        .rdata_o   (arb_rdata),
        .sd_rd_o   (sd_rd),
        .sd_we_o   (sd_we),
        .sd_wtbt_o (sd_wtbt),
        .sd_addr_o (sd_addr),
        .sd_din_o  (sd_din),
        .sd_dout_i (sd_dout),
        .sd_ready_i(sd_ready)
    );

    /* ---- EEPROM image load: loader (memory domain) -> 186 system (CPU domain), toggle + held data (a new word comes at HPS pace, many clocks later) */
    logic        ee_tog_q, ee_en_c;
    logic [7:0]  ee_a_q;
    logic [15:0] ee_d_q;
    logic [2:0]  ee_ts_q;
    always_ff @(posedge clk) begin
        if (ee_load_en) begin
            ee_tog_q <= !ee_tog_q;
            ee_a_q   <= ee_load_addr;
            ee_d_q   <= ee_load_data;
        end
    end
    always_ff @(posedge clk_cpu)
        ee_ts_q <= {ee_ts_q[1:0], ee_tog_q};
    assign ee_en_c = ee_ts_q[2] ^ ee_ts_q[1];

    /* ---- file loader (client 4) */
    logic        ee_load_en;
    logic [7:0]  ee_load_addr;
    logic [15:0] ee_load_data;
    logic        ld_req, rom_loaded;
    logic [1:0]  ld_slot;
    logic [23:0] ld_addr;
    logic [15:0] ld_wdata;

    loader u_loader (
        .clk              (clk),
        .rst_n            (!sd_init),
        .ioctl_download_i (ioctl_download_i),
        .ioctl_index_i    (ioctl_index_i),
        .ioctl_wr_i       (ioctl_wr_i),
        .ioctl_addr_i     (ioctl_addr_i),
        .ioctl_dout_i     (ioctl_dout_i),
        .rq_req_o         (ld_req),
        .rq_addr_o        (ld_addr),
        .rq_wdata_o       (ld_wdata),
        .rq_ack_i         (cl_ack[4] || rom_ack_q),
        .ee_load_en_o     (ee_load_en),
        .ee_load_addr_o   (ee_load_addr),
        .ee_load_data_o   (ee_load_data),
        .ioctl_wait_o     (ioctl_wait_o),
        .words_o          (dbg_words_o),
        .drops_o          (),
        .busy_o           (loader_busy),
        .slot_o           (ld_slot),
        .rom_loaded_o     (rom_loaded)
    );

    /* ---- DSP on-chip ROM image: loader words with address 0x0C0000|idx go to the DSP's block RAM (DSP clock domain) instead of the SDRAM, through a handshake crossing; a new word
       is accepted at most every 24 memory clocks (that spacing is longer than the crossing's round trip) */
    logic        ld_is_rom, rom_ack_q = 1'b0, rom_go_q = 1'b0;
    logic [4:0]  rom_cnt_q = 5'd0;
    logic [15:0] rom_a_q, rom_d_q;
    assign ld_is_rom = (ld_addr[23:16] == 8'h0C);
    always_ff @(posedge clk) begin
        rom_ack_q <= 1'b0;
        rom_go_q  <= 1'b0;
        if (rom_cnt_q != 5'd0) begin
            rom_cnt_q <= rom_cnt_q - 5'd1;
            if (rom_cnt_q == 5'd1)
                rom_ack_q <= 1'b1;
        end else if (ld_req && ld_is_rom && !rom_ack_q) begin
            rom_go_q  <= 1'b1;
            rom_a_q   <= ld_addr[15:0];
            rom_d_q   <= ld_wdata;
            rom_cnt_q <= 5'd24;
        end
    end
    /* ---- clock enables: levels, not divided slots. A core runs every clk_cpu unless it waits for memory. */
    logic        xm_ready;
    logic        h_req, h_ack;
    logic        ce_dsp, ce_186;
    logic signed [15:0] dac_sample_dsp_q;

    assign ce_dsp = 1'b1;   /* the DSP always runs: its program RAM has no wait states */
    assign ce_186 = 1'b1;   /* the 186 always runs: memory latency is waited out by the core itself (bus_ack), and counts toward its instruction cycle budget; the peripherals keep real time */

    /* ---- the 186: core + system (i186_top) with the DSP glue hooks */
    logic        h_wr, h_word, h_is_mmio;
    logic [19:0] h_addr;
    logic [15:0] h_wdata, h_rdata;
    logic        dte_tx_valid;
    logic [7:0]  dte_tx_byte;
    logic        dte_rx_valid;
    logic [7:0]  dte_rx_byte;
    logic        dte_line;
    logic        dsp_start_req, burst_valid;
    logic [63:0] burst_data;
    logic [63:0] hb_count;
    logic        glue_rd_commit, glue_wr_commit, glue_run, int0_set;
    logic        int0_hold_q, rx_hold_q;
    logic [7:0]  rx_hold_byte_q;
    logic [15:0] glue_rd_port, glue_wr_port;
    logic [7:0]  glue_wr_data, glue_rd_data;
    logic        unused_core_halted;
    logic [63:0] unused_cycles;
    logic [19:0] unused_badop_pc;
    logic [7:0]  unused_badop_op, unused_evt;
    logic [15:0] unused_h2d0, unused_relreg;

    i186_top #(.USE_S86(1'b1)) u_186 (
        .clk               (clk_cpu),
        .ce_i              (ce_186),
        .rst_n             (rst_n),
        .model_tick_en     (1'b1),
        .nmi_req           (1'b0),
        .cyc_model         (1'b1),
        .ud_trap           (1'b1),
        .h_req             (h_req),
        .h_wr              (h_wr),
        .h_word            (h_word),
        .h_is_mmio         (h_is_mmio),
        .h_addr            (h_addr),
        .h_wdata           (h_wdata),
        .h_rdata           (h_rdata),
        .h_ack             (h_ack),
        .dte_tx_valid      (dte_tx_valid),
        .dte_tx_byte       (dte_tx_byte),
        .dte_rx_valid      (rx_hold_q),
        .dte_rx_byte       (rx_hold_byte_q),
        .line              (dte_line),
        .dsp_start_req     (dsp_start_req),
        .burst_valid       (burst_valid),
        .burst_data        (burst_data),
        .port_in_10        (8'h00),
        .port_in_12        (8'h9A),
        .port_in_14        (8'h44),
        .hw_idx            (4'd7),
        .ring_on           (line_ring_req),
        .hb_count          (hb_count),
        .hb_ticks          (64'd1),
        .p2pin_in          (8'h40),
        .ee_load_en        (ee_en_c),
        .ee_load_addr      (ee_a_q),
        .ee_load_data      (ee_d_q),
        .core_cycles       (unused_cycles),
        .core_halted       (unused_core_halted),
        .core_pc           (pc186_o),
        .core_badop        (badop186_o),
        .core_badop_pc     (unused_badop_pc),
        .core_badop_opcode (unused_badop_op),
        .speaker_on        (speaker_on_o),
        .dbg_icu           (dbg_icu_o),
        .dbg_evt           (unused_evt),
        .dbg_h2d0          (unused_h2d0),
        .dbg_pcb_relreg    (unused_relreg),
        .dsp_run_i         (glue_run),
        .glue_rd_data_i    (glue_rd_data),
        .glue_rd_port_o    (glue_rd_port),
        .glue_rd_commit_o  (glue_rd_commit),
        .glue_wr_commit_o  (glue_wr_commit),
        .glue_wr_port_o    (glue_wr_port),
        .glue_wr_data_o    (glue_wr_data),
        .int0_set_i        (int0_hold_q)
    );

    /* 186 memory (client 0) */
    logic        m186_req, m186_we;
    logic [1:0]  m186_be;
    logic [23:0] m186_addr;
    logic [15:0] m186_wdata;

    mem186 #(
        .BASE (24'h000000)
    ) u_mem186 (
        .clk_c      (clk_cpu),
        .clk_m      (clk),
        .rst_n_m    (rcm_n),
        .h_req      (h_req),
        .h_wr       (h_wr),
        .h_word     (h_word),
        .h_is_mmio  (h_is_mmio),
        .h_addr     (h_addr),
        .h_wdata    (h_wdata),
        .h_rdata    (h_rdata),
        .h_ack      (h_ack),
        .rq_req_o   (m186_req),
        .rq_we_o    (m186_we),
        .rq_be_o    (m186_be),
        .rq_addr_o  (m186_addr),
        .rq_wdata_o (m186_wdata),
        .rq_ack_i   (cl_ack[0]),
        .rq_rdata_i (arb_rdata)
    );

    /* ---- the DSP: core + program RAM + codec model in the 40.32 MHz domain, the glue stays in the CPU domain. The three clocks are phase aligned (one PLL), so each crossing flag goes
       through one register (XS = 1), and STA times those paths. */
    localparam integer XS = 1;
    logic        dsp_rst_n;
    logic        rst_d_n, dsp_rst_d_n;
    logic        rst_s1, dsp_rst_s1;
    cdc_sync #(.W(1), .STAGES(XS)) u_rst_d  (.clk(clk_dsp), .d_i(rst_n),     .q_o(rst_s1));
    cdc_sync #(.W(1), .STAGES(XS)) u_rstc_d (.clk(clk_dsp), .d_i(dsp_rst_n), .q_o(dsp_rst_s1));
    logic rstl_d_n, rstl_s1;
    cdc_sync #(.W(1), .STAGES(XS)) u_rstl_d (.clk(clk_dsp), .d_i(!sd_init), .q_o(rstl_s1));   /* the load path (host writes of the ROM image) is live during the file download, before the core reset is released */
    always_ff @(posedge clk_dsp) begin
        rst_d_n     <= rst_s1;
        dsp_rst_d_n <= rst_s1 && dsp_rst_s1;
        rstl_d_n    <= rstl_s1;
    end

    logic        pw_en, pw_ready;
    logic [15:0] pw_addr, pw_data;
    logic        pbr_hw_ready;

    /* host writes into the DSP's program RAM: from the glue (CPU domain) and from the loader's ROM image (memory domain); each is a handshake crossing, the two are merged here */
    logic        pwa_busy, pwa_ack, pwa_v, pwa_done;
    logic [31:0] pwa_pay;
    cdc_hs #(.WQ(32), .WR(1), .STAGES(XS)) u_hs_pw (
        .clk_s (clk_cpu), .rst_s_n (rst_n), .go_i (pw_en && !pwa_busy && !pwa_ack), .payload_i ({pw_addr, pw_data}), .busy_o (pwa_busy), .ack_o (pwa_ack), .rsp_o (),
        .clk_d (clk_dsp), .rst_d_n (rstl_d_n), .v_o (pwa_v), .payload_o (pwa_pay), .done_i (pwa_done), .rsp_i (1'b0)
    );
    assign pw_ready = pwa_ack;

    logic        pwb_busy, pwb_ack, pwb_v, pwb_done;
    logic [31:0] pwb_pay;
    cdc_hs #(.WQ(32), .WR(1), .STAGES(XS)) u_hs_rom (
        .clk_s (clk), .rst_s_n (!sd_init), .go_i (rom_go_q && !pwb_busy), .payload_i ({rom_a_q, rom_d_q}), .busy_o (pwb_busy), .ack_o (pwb_ack), .rsp_o (),
        .clk_d (clk_dsp), .rst_d_n (rstl_d_n), .v_o (pwb_v), .payload_o (pwb_pay), .done_i (pwb_done), .rsp_i (1'b0)
    );

    logic pwa_pend_q, pwb_pend_q;
    logic hw_sel_a;
    assign hw_sel_a = pwa_pend_q;
    assign pwa_done = pwa_pend_q && pbr_hw_ready;
    assign pwb_done = !pwa_pend_q && pwb_pend_q && pbr_hw_ready;
    always_ff @(posedge clk_dsp) begin
        if (!rstl_d_n) begin
            pwa_pend_q <= 1'b0;
            pwb_pend_q <= 1'b0;
        end else begin
            if (pwa_v)      pwa_pend_q <= 1'b1;
            else if (pwa_done) pwa_pend_q <= 1'b0;
            if (pwb_v)      pwb_pend_q <= 1'b1;
            else if (pwb_done) pwb_pend_q <= 1'b0;
        end
    end

    /* host writes reach the pipelined core's program-write (load) port: one word, then three clocks of quiet so a write never overlaps the next (the port has no ready) */
    logic [1:0]  ld_cnt_q;
    logic        ld_fire;
    assign ld_fire      = (pwa_pend_q || pwb_pend_q) && (ld_cnt_q == 2'd0);
    assign pbr_hw_ready = ld_fire;
    always_ff @(posedge clk_dsp) begin
        if (!rstl_d_n)        ld_cnt_q <= 2'd0;
        else if (ld_fire)     ld_cnt_q <= 2'd3;
        else if (ld_cnt_q != 2'd0) ld_cnt_q <= ld_cnt_q - 2'd1;
    end
    logic [15:0] ldw_addr, ldw_data;
    assign ldw_addr = hw_sel_a ? pwa_pay[31:16] : pwb_pay[31:16];
    assign ldw_data = hw_sel_a ? pwa_pay[15:0]  : pwb_pay[15:0];
    logic [31:0] dsp_mtime;   /* the DSP's model time: the codec frame schedule follows it */

    logic        io_req, io_rd, io_ack, io_strobe;
    logic [15:0] io_port, io_wdata, io_rdata, io_rdata_g;
    logic        dsp_int2, int2_hold_q;
    logic [15:0] glue_dbg_cmd;
    logic        glue_msg_ev;
    logic [31:0] glue_msg;
    logic [15:0] cmd_cnt_q;
    logic        aic_step, aic_ser_tick, aic_int3, frame_tick;
    logic [15:0] aic_ser_rx, mclk_n, rate_cps, aic_dbg;
    logic [15:0] dsp_g_st0, dsp_g_imr, dsp_g_pmst;  logic [31:0] dsp_g_rptc;  logic [2:0] dsp_g_sp;  logic dsp_g_halt;
    assign dbg_dspg_o = {dsp_g_st0, dsp_g_imr, dsp_g_pmst, dsp_g_rptc[7:0], 3'b000, dsp_g_halt, idle_dsp, dsp_g_sp};
    logic        dxr_wr, instr_done, idle_dsp, rx_next;
    logic        dsp_mwr, dsp_mwr_pm;
    logic [127:0] dsp_ar_all;
    logic [15:0] dsp_mwr_addr, dsp_mwr_data;
    logic [15:0] dxr_wdata;
    logic [63:0] dsp_cycles, timer_exp;
    logic        pk_req;
    logic [23:0] pk_addr;
    logic signed [15:0] rx_sample;

    /* a DSP I/O request is taken once, at the first clock it is seen on; it crosses to the glue (CPU domain) through a handshake: the glue is strobed with the request, its answer
       comes back as io_rdata one handshake later, and io_ack is held until the core drops io_req */
    logic        io_seen_q, io_start, io_hs_ack, io_hs_busy, io_ack_q;
    logic [15:0] io_rdata_hs;
    logic        io_v;
    logic [32:0] io_pay;
    always_ff @(posedge clk_dsp) begin
        io_seen_q <= io_req;
        if (!dsp_rst_d_n)
            io_ack_q <= 1'b0;
        else if (!io_req)
            io_ack_q <= 1'b0;
        else if (io_hs_ack)
            io_ack_q <= 1'b1;
    end
    assign io_start = io_req && !io_seen_q;
    logic [32:0] io_hold_q;   /* the core only presents the request in its first clock: it is held here for the crossing */
    always_ff @(posedge clk_dsp)
        if (io_start) io_hold_q <= {io_rd, io_port, io_wdata};
    assign io_ack   = io_ack_q;
    assign io_rdata = io_rdata_hs;
    cdc_hs #(.WQ(33), .WR(16), .STAGES(XS)) u_hs_io (
        .clk_s (clk_dsp), .rst_s_n (rst_d_n), .go_i (io_start), .payload_i (io_hold_q), .busy_o (io_hs_busy), .ack_o (io_hs_ack), .rsp_o (io_rdata_hs),
        .clk_d (clk_cpu), .rst_d_n (rst_n), .v_o (io_v), .payload_o (io_pay), .done_i (io_v), .rsp_i (io_rdata_g)
    );
    assign io_strobe = io_v;

    /* INT2 request from the glue (CPU domain) held until the core has seen it */
    logic dsp_int2_d;
    cdc_pulse #(.STAGES(XS)) u_int2 (.clk_s (clk_cpu), .rst_s_n (rst_n), .pulse_i (dsp_int2), .clk_d (clk_dsp), .pulse_o (dsp_int2_d));
    always_ff @(posedge clk_dsp) begin
        if (dsp_int2_d)
            int2_hold_q <= 1'b1;
        else if (ce_dsp)
            int2_hold_q <= 1'b0;
    end
    c5x_core #(
        .RESET_PC (16'h8000),
        .WALL_TIME (1'b1)   /* real-time audio: model time is the DSP clock (the C model's fixed 40.32 MHz DSP clock) */
    ) u_dsp (
        .clk             (clk_dsp),
        .rst_n           (dsp_rst_d_n),
        .step_i          (1'b1),
        .bp_en_i         (2'b00),
        .bp_pc0_i        (16'h0000),
        .bp_pc1_i        (16'h0000),
        .irq_i           ({6'd0, aic_int3, int2_hold_q, 1'b0}),
        .bio_i           (1'b0),
        .ivec_ind_i      ({16'h0068, 16'h0067, 16'h0066, 16'h0065, 16'h0064, 16'h0063, 16'h0062, 16'h0061, 16'h0060}),
        .ser_tick        (aic_ser_tick),
        .ser_rx          (aic_ser_rx),
        .xint_mode       (1'b1),
        .io_req          (io_req),
        .io_rd           (io_rd),
        .io_port         (io_port),
        .io_wdata        (io_wdata),
        .io_rdata        (io_rdata),
        .io_ack          (io_ack),
        .load_en         (ld_fire),
        .load_pmem       (1'b1),
        .load_addr       (ldw_addr),
        .load_data       (ldw_data),
        .dbg_en          (1'b0),
        .dbg_addr        (16'h0000),
        .dbg_rdata       (),
        .dbg_done        (),
        .dxr_wr          (dxr_wr),
        .dxr_wdata       (dxr_wdata),
        .timer_exp_cnt_o (timer_exp),
        .mem_wr_pulse    (dsp_mwr),
        .mem_wr_pmem     (dsp_mwr_pm),
        .mem_wr_addr     (dsp_mwr_addr),
        .mem_wr_data     (dsp_mwr_data),
        .instr_done      (instr_done),
        .cycles_o        (dsp_cycles),
        .idle_o          (idle_dsp),
        .mtime_o         (dsp_mtime),
        .ifr_o           (dbg_ifr_o),
        .st0_o           (dsp_g_st0),
        .imr_o           (dsp_g_imr),
        .pmst_o          (dsp_g_pmst),
        .rptc_o          (dsp_g_rptc),
        .sp_o            (dsp_g_sp),
        .halted_o        (dsp_g_halt),
        .obs_spc_o       (dbg_spc_o),
        .op_o            (dsp_op),
        .pc_o            (pcdsp_o),
        .ar_all_o        (dsp_ar_all)
    );

    dsp_glue u_glue (
        .clk             (clk_cpu),
        .rst_n           (rst_n),
        .rd_port_i       (glue_rd_port),
        .rd_data_o       (glue_rd_data),
        .rd_commit_i     (glue_rd_commit && ce_186),
        .wr_commit_i     (glue_wr_commit && ce_186),
        .wr_port_i       (glue_wr_port),
        .wr_data_i       (glue_wr_data),
        .run_o           (glue_run),
        .int0_set_o      (int0_set),
        .hb_count_o      (hb_count),
        .dbg_msg_ev_o    (glue_msg_ev),
        .dbg_msg_o       (glue_msg),
        .dbg_cmd_o       (glue_dbg_cmd),
        .rom_loaded_i    (rom_loaded_c),
        .dsp_start_req_i (dsp_start_req && ce_186),
        .burst_valid_i   (burst_valid && ce_186),
        .burst_data_i    (burst_data),
        .io_req_i        (io_strobe),
        .io_rd_i         (io_pay[32]),
        .io_addr_i       (io_pay[31:16]),
        .io_wdata_i      (io_pay[15:0]),
        .io_ack_o        (),
        .io_rdata_o      (io_rdata_g),
        .dsp_rst_n_o     (dsp_rst_n),
        .dsp_int2_o      (dsp_int2),
        .mclk_n_o        (mclk_n),
        .pw_en_o         (pw_en),
        .pw_addr_o       (pw_addr),
        .pw_data_o       (pw_data),
        .pw_ready_i      (pw_ready),
        .frame_tick_i    (frame_tick_c),
        .dsp_timer_exp_i (timer_exp_c),
        .pk_req_o        (pk_req),
        .pk_addr_o       (pk_addr),
        .pk_ack_i        (xdc_ack[3]),
        .pk_rdata_i      (xdc_rdata[63:48])
    );

    /* glue <-> DSP domain: mclk_n (static configuration), frame ticks and the DSP timer's expiry count cross to the CPU domain, the DAC samples too */
    logic [15:0] mclk_n_d, timer_exp_c;
    logic        frame_tick_c, dac_valid_d;
    logic signed [15:0] dac_sample_d;
    cdc_sync #(.W(16), .STAGES(XS)) u_mclk (.clk(clk_dsp), .d_i(mclk_n), .q_o(mclk_n_d));
    cdc_pulse #(.STAGES(XS)) u_frame (.clk_s (clk_dsp), .rst_s_n (rst_d_n), .pulse_i (frame_tick), .clk_d (clk_cpu), .pulse_o (frame_tick_c));
    cdc_pulse #(.STAGES(XS)) u_dacv  (.clk_s (clk_dsp), .rst_s_n (rst_d_n), .pulse_i (dac_valid_d), .clk_d (clk_cpu), .pulse_o (dac_valid_o));
    assign dac_sample_o = dac_sample_dsp_q;
    always_ff @(posedge clk_cpu)
        if (dac_valid_o) dac_sample_dsp_q <= dac_sample_d;
    cdc_count #(.W(16), .STAGES(XS)) u_texp (.clk_s (clk_dsp), .cnt_i (timer_exp[15:0]), .clk_d (clk_cpu), .cnt_o (timer_exp_c));

    aic u_aic (
        .clk          (clk_dsp),
        .rst_n        (rst_d_n),
        .ce_i         (ce_dsp),
        .cycles_i     (dsp_mtime),      /* codec frames follow the DSP's model time (the timer's own ticks), never the wall clock */
        .parked_i     (1'b1),
        .idle_i       (1'b1),
        .run_i        (dsp_rst_d_n),
        .step_o       (aic_step),
        .ser_tick_o   (aic_ser_tick),
        .ser_rx_o     (aic_ser_rx),
        .int3_o       (aic_int3),
        .dxr_wr_i     (dxr_wr),
        .dxr_wdata_i  (dxr_wdata),
        .mclk_n_i     (mclk_n_d),
        .dac_valid_o  (dac_valid_d),
        .dac_sample_o (dac_sample_d),
        .rx_next_o    (rx_next),
        .rx_sample_i  (rx_sample),
        .frame_tick_o (frame_tick),
        .rate_cps_o   (rate_cps),
        .dbg_o        (aic_dbg)
    );

    /* line input: the ADC ring the HPS fills (silence while it is empty; the C model's noise floor is added in aic). rx_next goes to the clk_cpu domain as a pulse;
       the sample comes back as a level that changes once per codec frame, long before aic reads it again, so two flops in the DSP domain are enough */
    logic rx_next_c, line_ring_req;
    logic signed [15:0] rx_line_c, rx_line_a_q, rx_line_b_q;
    cdc_pulse #(.STAGES(XS)) u_rxn (.clk_s (clk_dsp), .rst_s_n (rst_d_n), .pulse_i (rx_next), .clk_d (clk_cpu), .pulse_o (rx_next_c));
    always_ff @(posedge clk_dsp) begin
        rx_line_a_q <= rx_line_c;
        rx_line_b_q <= rx_line_a_q;
    end
    assign rx_sample = rx_line_b_q;
    assign line_rx_o = rx_line_c;
    logic [28:0] ln_addr;  logic [7:0] ln_burst; logic ln_rd, ln_we, ln_active; logic [63:0] ln_din; logic [7:0] ln_be; logic trc_en_c, trc_fz_c;
    line_ddr u_line (
        .clk               (clk_cpu),
        .rst_n             (rst_n),
        .dac_valid_i       (dac_valid_o),
        .dac_sample_i      (dac_sample_o),
        .rx_next_i         (rx_next_c),
        .rx_sample_o       (rx_line_c),
        .rate_cps_i        (rate_cps),
        .ring_req_o        (line_ring_req),
        .connected_o       (line_connected_o),
        .ddr_addr_o        (ln_addr),
        .ddr_burstcnt_o    (ln_burst),
        .ddr_busy_i        (ddr_busy_i),
        .ddr_dout_i        (ddr_dout_i),
        .ddr_dout_ready_i  (ddr_dout_ready_i),
        .ddr_rd_o          (ln_rd),
        .ddr_din_o         (ln_din),
        .ddr_be_o          (ln_be),
        .ddr_we_o          (ln_we),
        .active_o          (ln_active),
        .trace_fz_o        (trc_fz_c),
        .trace_en_o        (trc_en_c)
    );

    /* ---- DTE serial port and the terminal's keyboard path */
    logic        uart_rx_valid;
    logic [7:0]  uart_rx_byte;
    logic [7:0]  uart_dropped;

    dte_uart #(.CLKS_PER_BIT(CPU_HZ / 115200)) u_uart (   /* 175 at 20.16 MHz */
        .clk        (clk_cpu),
        .rst_n      (uart_rst_n),     /* not the core reset: it is held during file downloads and the bring-up markers are sent then */
        .rxd_i      (uart_rxd_i),
        .txd_o      (uart_txd_o),
        .line_o     (dte_line),
        .rx_valid_o (uart_rx_valid),
        .rx_byte_o  (uart_rx_byte),
        .tx_valid_i (uart_tx_valid),
        .tx_byte_i  (uart_tx_byte),
        .dropped_o  (uart_dropped)
    );

    /* ---- bring-up markers: one character per event, queued as pending bits so simultaneous events are all sent */
    logic [4:0]  mk_pend_q;          /* F N M S D */
    logic        busy_prev_q, rst_prev_q, run_prev_q;
    logic [1:0]  last_idx_q;
    logic        uart_tx_valid;
    logic [7:0]  uart_tx_byte;

    always_ff @(posedge clk_cpu) begin
        busy_prev_q <= loader_busy_c;
        rst_prev_q  <= rst_n;
        run_prev_q  <= glue_run;
        last_idx_q <= ld_slot_c;
        if (!dbg_markers_i) begin
            mk_pend_q <= 5'd0;
        end else begin
            if (busy_prev_q && !loader_busy_c) begin
                if (last_idx_q == 2'd0) mk_pend_q[0] <= 1'b1;
                if (last_idx_q == 2'd1) mk_pend_q[1] <= 1'b1;
                if (last_idx_q == 2'd2) mk_pend_q[2] <= 1'b1;
            end
            if (rst_n && !rst_prev_q) mk_pend_q[3] <= 1'b1;
            if (glue_run && !run_prev_q) mk_pend_q[4] <= 1'b1;
            if (|mk_pend_q) begin
                if (mk_pend_q[0])      mk_pend_q[0] <= 1'b0;
                else if (mk_pend_q[1]) mk_pend_q[1] <= 1'b0;
                else if (mk_pend_q[2]) mk_pend_q[2] <= 1'b0;
                else if (mk_pend_q[3]) mk_pend_q[3] <= 1'b0;
                else                   mk_pend_q[4] <= 1'b0;
            end
        end
    end

    always_comb begin
        uart_tx_valid = (dte_tx_valid && ce_186) || (|mk_pend_q);
        uart_tx_byte  = dte_tx_byte;
        if (|mk_pend_q) begin
            if (mk_pend_q[0])      uart_tx_byte = "F";
            else if (mk_pend_q[1]) uart_tx_byte = "N";
            else if (mk_pend_q[2]) uart_tx_byte = "M";
            else if (mk_pend_q[3]) uart_tx_byte = "S";
            else                   uart_tx_byte = "D";
        end
    end

    /* software switch for the heartbeat text: three Ctrl-A bytes then D (either case) toggle it. The bytes still go on to the modem, which ignores anything that is not an AT command. */
    logic [1:0] esc_cnt_q;
    always_ff @(posedge clk_cpu) begin
        if (!rst_n) begin
            esc_cnt_q  <= 2'd0;
            dbg_text_o <= 1'b0;
        end else if (uart_rx_valid) begin
            if (uart_rx_byte == 8'h01) begin
                if (esc_cnt_q != 2'd3)
                    esc_cnt_q <= esc_cnt_q + 2'd1;
            end else begin
                if (esc_cnt_q == 2'd3 && (uart_rx_byte | 8'h20) == 8'h64)
                    dbg_text_o <= !dbg_text_o;
                esc_cnt_q <= 2'd0;
            end
        end
    end

    assign dte_rx_valid   = uart_rx_valid || term_rx_valid_i;
    assign dte_rx_byte    = uart_rx_valid ? uart_rx_byte : term_rx_byte_i;
    assign dte_tx_valid_o = dte_tx_valid && ce_186;
    assign dte_tx_byte_o  = dte_tx_byte;
    assign dsp_run_o      = glue_run;

    /* ---- arbiter client wiring: clients 0..3 live in the CPU domain (xdom_req), 4 (loader) and 5 (probe) in the memory domain */
    logic [3:0]        xdc_req, xdc_we, xdc_ack, xdm_req, xdm_we;
    logic [7:0]        xdc_be, xdm_be;
    logic [4*24-1:0]   xdc_addr, xdm_addr;
    logic [4*16-1:0]   xdc_wdata, xdm_wdata, xdc_rdata;
    logic              rcm_n;
    assign rcm_n = !sd_init;

    /* client 0 (the 186) talks to the arbiter directly through the aligned-clock mem186; clients 1 and 2 (the DSP's cache) are gone (the DSP memory is block RAM);
       client 3 is the glue's ring-pointer peek (clk_cpu domain, through xdom_req) */
    assign xdc_req   = {pk_req, 3'b000};
    assign xdc_we    = 4'b0000;
    assign xdc_be    = {2'b11, 6'b000000};
    assign xdc_addr  = {pk_addr, 72'h0};
    assign xdc_wdata = 64'h0;
    assign xdc_ack[2:0] = 3'b000;
    assign xdc_rdata[47:0] = 48'h0;

    genvar gi;
    generate for (gi = 3; gi < 4; gi = gi + 1) begin : g_xd
        xdom_req #(.AW(24)) u_xd (
            .clk_c   (clk_cpu),
            .rst_c_n (rst_n),
            .clk_m   (clk),
            .rst_m_n (rcm_n),
            .req_i   (xdc_req[gi]),
            .we_i    (xdc_we[gi]),
            .be_i    (xdc_be[2*gi +: 2]),
            .addr_i  (xdc_addr[24*gi +: 24]),
            .wdata_i (xdc_wdata[16*gi +: 16]),
            .ack_o   (xdc_ack[gi]),
            .rdata_o (xdc_rdata[16*gi +: 16]),
            .req_o   (xdm_req[gi]),
            .we_o    (xdm_we[gi]),
            .be_o    (xdm_be[2*gi +: 2]),
            .addr_o  (xdm_addr[24*gi +: 24]),
            .wdata_o (xdm_wdata[16*gi +: 16]),
            .ack_i   (cl_ack[gi]),
            .rdata_i (arb_rdata)
        );
    end endgenerate
    assign xdm_req[2:0]  = {2'b00, m186_req};
    assign xdm_we[2:0]   = {2'b00, m186_we};
    assign xdm_be[5:0]   = {4'b0000, m186_be};
    assign xdm_addr[71:0]  = {48'h0, m186_addr};
    assign xdm_wdata[47:0] = {32'h0, m186_wdata};

    assign cl_req   = {prb_req, ld_req && !ld_is_rom, xdm_req};
    assign cl_we    = {prb_we, 1'b1, xdm_we};
    assign cl_be    = {2'b11, 2'b11, xdm_be};
    assign cl_addr  = {prb_addr, ld_addr, xdm_addr};
    assign cl_wdata = {prb_wdata, ld_wdata, xdm_wdata};

    /* SDRAM start-up calibration + run-time self-test (client 5, lowest priority) */
    logic        prb_req, prb_we;
    logic [23:0] prb_addr;
    logic [15:0] prb_wdata;
    logic ack_d_q;
    always_ff @(posedge clk_cpu)
        ack_d_q <= h_ack;
    /* bring-up: the trace follows the DSP's executed instructions (PC and opcode at every retirement), frozen when its PC enters the on-chip ROM (below 0x2000) after it has been in
       the RAM image (0x8000 and up): the last 64 instructions before the jump. */
    logic        dtr_high_q;
    logic [15:0] dsp_op;
    always_ff @(posedge clk_dsp) begin
        if (!dsp_rst_d_n)
            dtr_high_q <= 1'b0;
        else if (pcdsp_o[15])
            dtr_high_q <= 1'b1;
    end
    /* bring-up trace: the host-to-DSP commands (count in the address field, command:argument in the data field) instead of the DSP's retired instructions */
    always_ff @(posedge clk_dsp) begin
        if (!rst_d_n)           cmd_cnt_q <= 16'd0;
        else if (dsp_int2_d)    cmd_cnt_q <= cmd_cnt_q + 16'd1;
    end
    /* ---- the trap: freezes the three rings (host commands, DSP messages, DSP instruction history) when the codec does something this modem never does:
       a rate other than 7200 / 9600 / 10237 Hz (cycles per frame 5600 / 4200 / 3939) for 5 ms, or no codec frame for 10 ms after frames had started, or 8 consecutive retired zero opcodes (the DSP lost in empty program memory: the instruction history then still holds the last real instructions before the wild jump). Sticky until reset. */
    logic        trap_q, armed_q, ar7_in_q, crash_q;     /* crash_q: only the conditions that mean the DSP went wrong (not the rate / frame-stall ones, which also fire on every hangup) */
    logic [19:0] bad_cnt_q, stall_cnt_q;
    logic        rate_ok;
    always_comb begin
        rate_ok = (rate_cps == 16'd0) || (rate_cps == 16'd5600) || (rate_cps == 16'd4200) || (rate_cps >= 16'd3936 && rate_cps <= 16'd3941);
    end
    logic [4:0] zrun_q;                          /* consecutive retired instructions with opcode 0x0000: the DSP walking through empty program memory after a wild jump (never in real code) */
    always_ff @(posedge clk_dsp) begin
        if (!rst_d_n || !dsp_rst_d_n) begin
            trap_q <= 1'b0; crash_q <= 1'b0; armed_q <= 1'b0; ar7_in_q <= 1'b0; bad_cnt_q <= 20'd0; stall_cnt_q <= 20'd0; zrun_q <= 5'd0;
        end else if (!trap_q) begin
            if (instr_done) zrun_q <= (dsp_op == 16'h0000) ? (zrun_q + 5'd1) : 5'd0;
            if (zrun_q >= 5'd8) begin trap_q <= 1'b1; crash_q <= 1'b1; end
            /* a store to the dispatcher pointer (data 0x326) from the DSP's main loop (pc 0x80C0..0x80FF, where C never writes it): freeze with the culprit still in the history */
            if (dsp_mwr && !dsp_mwr_pm && (dsp_mwr_addr == 16'h0326) && (pcdsp_o >= 16'h80C0) && (pcdsp_o < 16'h8100)) begin trap_q <= 1'b1; crash_q <= 1'b1; end
            /* AR7 is the DSP's message-ring write pointer (circular buffer 0xBD0..0xBDF): once it has been inside the ring, leaving it freezes the history with the culprit in it */
            if (dsp_ar_all[127:112] >= 16'h0BD0 && dsp_ar_all[127:112] <= 16'h0BDF) ar7_in_q <= 1'b1;
            else if (ar7_in_q) begin trap_q <= 1'b1; crash_q <= 1'b1; end
            bad_cnt_q <= rate_ok ? 20'd0 : bad_cnt_q + 20'd1;
            if (frame_tick) begin stall_cnt_q <= 20'd0; armed_q <= 1'b1; end
            else            stall_cnt_q <= stall_cnt_q + 20'd1;
            if (bad_cnt_q > 20'd200000 || (armed_q && stall_cnt_q > 20'd400000)) trap_q <= 1'b1;
        end
    end
    logic trap_c;
    cdc_sync #(.W(1), .STAGES(XS)) u_trap_c (.clk(clk_cpu), .d_i(trap_q), .q_o(trap_c));
    assign dbg_trap_o = trap_q;

    /* the DSP instruction history in DDR (rtl/dsp_trace_ddr.sv) takes the port only when the line interface leaves it free */
    logic        trc_we;  logic [28:0] trc_addr;  logic [63:0] trc_din;
    /* the trace freezes at the first trap after a core reload and stays frozen (a DSP restart clears the trap, which must not let new history overwrite the crash) */
    /* no codec frame for ~100 ms (4 M DSP clocks; frames normally come every 140 us): the DSP has stopped servicing the codec. Freeze the DDR history with the cause still in it.
       Independent of trap_q (the 10 ms trap above stops that block). */
    logic [22:0] lstall_cnt_q;
    logic        lstall_seen_q, lstall_q;
    always_ff @(posedge clk_dsp) begin
        if (!rst_d_n || !dsp_rst_d_n) begin lstall_cnt_q <= 23'd0; lstall_seen_q <= 1'b0; lstall_q <= 1'b0; end
        else begin
            if (frame_tick) begin lstall_cnt_q <= 23'd0; lstall_seen_q <= 1'b1; end
            else if (lstall_cnt_q != 23'h7FFFFF) lstall_cnt_q <= lstall_cnt_q + 23'd1;
            if (lstall_seen_q && lstall_cnt_q > 23'd4000000) lstall_q <= 1'b1;
        end
    end
    logic        trc_freeze_q, trc_freeze_c;
    logic        trc_fz_d, trc_en_d;
    cdc_sync #(.W(1), .STAGES(XS)) u_trcfzh_d (.clk(clk_dsp), .d_i(trc_fz_c), .q_o(trc_fz_d));     /* the HPS asked for the freeze (the call ended) */
    always_ff @(posedge clk_dsp) begin
        if (!rst_d_n)                    trc_freeze_q <= 1'b0;
        else if (crash_q || lstall_q || trc_fz_d)    trc_freeze_q <= 1'b1;
    end
    cdc_sync #(.W(1), .STAGES(XS)) u_trcen_d (.clk(clk_dsp), .d_i(trc_en_c), .q_o(trc_en_d));
    cdc_sync #(.W(1), .STAGES(XS)) u_trcfz_c (.clk(clk_cpu), .d_i(trc_freeze_q), .q_o(trc_freeze_c));
    dsp_trace_ddr u_trace_ddr (
        .clk_dsp       (clk_dsp),
        .rst_dsp_n     (rst_d_n),
        .ev_i          (instr_done),
        .pc_i          (pcdsp_o),
        .ar7_i         (dsp_ar_all[127:112]),
        .freeze_dsp_i  (trc_freeze_q),
        .en_dsp_i      (trc_en_d),
        .clk           (clk_cpu),
        .rst_n         (rst_n),
        .freeze_i      (trc_freeze_c),
        .en_i          (trc_en_c),
        .line_active_i (ln_active),
        .ddr_busy_i    (ddr_busy_i),
        .ddr_we_o      (trc_we),
        .ddr_addr_o    (trc_addr),
        .ddr_din_o     (trc_din)
    );
    assign ddr_addr_o     = ln_active ? ln_addr  : trc_addr;
    assign ddr_burstcnt_o = ln_burst;
    assign ddr_rd_o       = ln_rd;
    assign ddr_din_o      = ln_active ? ln_din   : trc_din;
    assign ddr_be_o       = ln_be;
    assign ddr_we_o       = ln_active ? ln_we    : trc_we;

    logic [37:0] tr_host_data, tr_msg_data, tr_pc_data, tr_wr_data;
    bus_trace u_trace (
        .clk       (clk_dsp),
        .rst_n     (rst_d_n),
        .ev_i      (dsp_int2_d),
        .wr_i      (1'b0),
        .word_i    (1'b1),
        .addr_i    ({4'h0, dsp_mtime[27:12]}),   /* timestamp of the command: DSP model time / 4096 (about 101 us per count, wraps every 6.6 s) */
        .data_i    (glue_dbg_cmd),
        .freeze_i  (trap_q),
        .rd_idx_i  (dbg_tr_idx_i),
        .rd_data_o (tr_host_data)
    );
    /* DSP -> host messages: words 6 and 7 (address field = word 6, data = word 7) */
    bus_trace u_trace_msg (
        .clk       (clk_cpu),
        .rst_n     (rst_n),
        .ev_i      (glue_msg_ev),
        .wr_i      (1'b1),
        .word_i    (1'b1),
        .addr_i    ({4'h0, glue_msg[31:16]}),
        .data_i    (glue_msg[15:0]),
        .freeze_i  (trap_c),
        .rd_idx_i  (dbg_tr_idx_i),
        .rd_data_o (tr_msg_data)
    );
    /* DSP instruction history: the program counter and opcode of every retired instruction */
    bus_trace u_trace_pc (
        .clk       (clk_dsp),
        .rst_n     (rst_d_n),
        .ev_i      (instr_done),
        .wr_i      (1'b0),
        .word_i    (1'b1),
        .addr_i    ({4'h0, pcdsp_o}),
        .data_i    (dsp_op),
        .freeze_i  (trap_q),
        .rd_idx_i  (dbg_tr_idx_i),
        .rd_data_o (tr_pc_data)
    );
    /* writes of the DSP to its dispatcher pointer (data 0x326: the state routine the main loop calls through BACC): the PC of the writer and the value, so a corrupted pointer can be traced to its writer */
    bus_trace u_trace_wr (
        .clk       (clk_dsp),
        .rst_n     (rst_d_n),
        .ev_i      (dsp_mwr && !dsp_mwr_pm && (dsp_mwr_addr == 16'h0326)),
        .wr_i      (1'b1),
        .word_i    (1'b1),
        .addr_i    ({4'h0, pcdsp_o}),
        .data_i    (dsp_mwr_data),
        .freeze_i  (trap_q),
        .rd_idx_i  (dbg_tr_idx_i),
        .rd_data_o (tr_wr_data)
    );
    assign dbg_tr_data_o = (dbg_tr_sel_i == 2'd1) ? tr_msg_data : (dbg_tr_sel_i == 2'd2) ? tr_pc_data : (dbg_tr_sel_i == 2'd3) ? tr_wr_data : tr_host_data;

    always_ff @(posedge clk_cpu) begin
        if (!rst_n) begin
            dbg_int0_o   <= 16'd0;
            dbg_frames_o <= 16'd0;
        end else begin
            if (int0_set)    dbg_int0_o   <= dbg_int0_o + 16'd1;
            if (frame_tick)  dbg_frames_o <= dbg_frames_o + 16'd1;
        end
    end
    assign dbg_texp_o = timer_exp_c;
    /* DSP-domain counters (read by the heartbeat across the domain: the values only need to be roughly right) */
    logic [15:0] peak_acc_q;
    logic [21:0] dwin_q, dcnt_q;
    wire  [15:0] dac_abs = dac_sample_d[15] ? (~dac_sample_d + 16'd1) : dac_sample_d;
    always_ff @(posedge clk_dsp) begin
        if (!rst_d_n) begin
            dbg_dxrc_o <= 16'd0; dbg_dacc_o <= 16'd0; dbg_peak_o <= 16'd0; peak_acc_q <= 16'd0; dwin_q <= 22'd0; dcnt_q <= 22'd0; dbg_idle_o <= 16'd0;
        end else begin
            if (dxr_wr) dbg_dxrc_o <= dbg_dxrc_o + 16'd1;
            if (dac_valid_d) begin
                dbg_dacc_o <= dbg_dacc_o + 16'd1;
                if (dac_abs > peak_acc_q) peak_acc_q <= dac_abs;
            end
            dwin_q <= dwin_q + 22'd1;
            if (idle_dsp) dcnt_q <= dcnt_q + 22'd1;
            if (dwin_q == 22'h3FFFFF) begin
                dbg_peak_o <= peak_acc_q;
                peak_acc_q <= 16'd0;
                dbg_idle_o <= aic_dbg;
                dcnt_q <= 22'd0;
            end
        end
    end
    logic [21:0] win_q, cecnt_q;
    always_ff @(posedge clk_cpu) begin
        if (!rst_n) begin
            dbg_rxc_o <= 16'd0; dbg_txc_o <= 16'd0; win_q <= 22'd0; cecnt_q <= 22'd0; dbg_duty_o <= 16'd0;
        end else begin
            if (uart_rx_valid) dbg_rxc_o <= dbg_rxc_o + 16'd1;
            if (dte_tx_valid && ce_186) dbg_txc_o <= dbg_txc_o + 16'd1;
            win_q <= win_q + 22'd1;
            if (!(h_req && !h_ack)) cecnt_q <= cecnt_q + 22'd1;   /* share of clocks the 186 is not waiting for memory */
            if (win_q == 22'h3FFFFF) begin
                dbg_duty_o <= cecnt_q[21:6];
                cecnt_q <= 22'd0;
            end
        end
    end

    /* first-jump-out-of-code latch (observation only; the cores never read it) */
    logic [19:0] jpc_q;
    wire         pc_valid = (pc186_o < 20'h01B14) || (pc186_o >= 20'h80000);
    always_ff @(posedge clk_cpu) begin
        if (!rst_n) begin
            jpc_q       <= 20'hFFFF0;
            dbg_jlat_o  <= 1'b0;
            dbg_jfrom_o <= 20'd0;
            dbg_jto_o   <= 20'd0;
        end else begin
            if (pc186_o != jpc_q) begin
                jpc_q <= pc186_o;
                if (!dbg_jlat_o && (!pc_valid || pc186_o == 20'h80A59)) begin   /* bring-up: also freeze the first time the 186 reaches the tick-wait at 0x80A59 */
                    dbg_jlat_o  <= 1'b1;
                    dbg_jfrom_o <= jpc_q;
                    dbg_jto_o   <= pc186_o;
                end
            end
        end
    end

    sdram_probe u_probe (
        .clk           (clk),
        .rst_n         (!sd_init),
        .sdram_ready_i (sd_seen_q),
        .run_i         (rst_n_q),
        .rq_req_o      (prb_req),
        .rq_we_o       (prb_we),
        .rq_addr_o     (prb_addr),
        .rq_wdata_o    (prb_wdata),
        .rq_ack_i      (cl_ack[5]),
        .rq_rdata_i    (arb_rdata),
        .cap_o         (cap_extra),
        .cal_done_o    (cal_done),
        .cal_ok_o      (dbg_cal_ok_o),
        .cal_mask_o    (dbg_cal_mask_o),
        .word_o        (dbg_vec_o),
        .test_ok_o     (dbg_test_ok_o)
    );
    assign dbg_cap_o = cap_extra;

    /* inputs of the 186 are sampled at its ce_186 edges: hold a request until then */
    always_ff @(posedge clk_cpu) begin
        if (!rst_n) begin
            int0_hold_q    <= 1'b0;
            rx_hold_q      <= 1'b0;
            rx_hold_byte_q <= 8'h00;
        end else begin
            if (int0_set)
                int0_hold_q <= 1'b1;
            else if (ce_186)
                int0_hold_q <= 1'b0;
            if (dte_rx_valid) begin
                rx_hold_q      <= 1'b1;
                rx_hold_byte_q <= dte_rx_byte;
            end else if (ce_186) begin
                rx_hold_q <= 1'b0;
            end
        end
    end
endmodule
