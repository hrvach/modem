/* Fast full-system simulation of the SV25 firmware: the 186, the DSP core, the glue and the codec model exactly as modem_core wires them (same clock-domain crossings, 40.32 / 20.16 MHz
   aligned clocks), but with a flat zero-wait memory instead of the SDRAM chain and the files poked in at time zero. Local firmware only: +flash= +nvram= +rom=.
   +mon=N prints the codec frame scheduler and the 186 PC every N DSP clocks; +clocks=N stops. Not part of `make test`. */
`default_nettype none
`timescale 1ps/1ps
module tb_fast2;
    reg clk_dsp = 0, clk_cpu = 0;
    always #12400 clk_dsp = ~clk_dsp;
    always #24800 clk_cpu = ~clk_cpu;
    reg rst_n = 0;
    logic dsp_op_dummy;
    logic rom_loaded_c = 1'b1;
    logic [19:0] pc186_o; logic badop186_o; logic [15:0] pcdsp_o, dsp_op;
    logic [24:0] dbg_icu_o; logic [15:0] dbg_ifr_o, dbg_spc_o;
    logic ee_en_c = 1'b0; logic [7:0] ee_a_q = 8'h00; logic [15:0] ee_d_q = 16'h0000;
    logic        ce_dsp, ce_186;
    logic        h_req, h_ack;
    logic signed [15:0] dac_sample_dsp_q;
    logic signed [15:0] dac_sample_o; logic dac_valid_o;
    logic [3:0] xdc_ack = 4'b0; logic [63:0] xdc_rdata = 64'b0;

    assign ce_dsp = 1'b1;
    assign ce_186 = 1'b1;
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
        .ring_on           (1'b0),
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

    /* flat zero-wait 186 memory: 1 MB, answer one CPU clock after the request, level held until the request drops */
    reg [7:0] mem [0:1048575];
    logic        flash_id_q = 1'b0;
    logic        ack_q = 1'b0;
    logic [15:0] rd_q = 16'h0;
    logic        is_fcmd, is_frd;
    always_comb begin
        is_fcmd = h_is_mmio && h_wr && (h_addr >= 20'hFFFF0) && (h_addr <= 20'hFFFF1);
        is_frd  = h_is_mmio && !h_wr && flash_id_q && (h_addr >= 20'hFFFF0) && (h_addr <= 20'hFFFF3);
    end
    integer memwait = 0, wcnt = 0;
    initial if (!$value$plusargs("memwait=%d", memwait)) memwait = 0;
    always @(posedge clk_cpu) begin
        if (!h_req) begin ack_q <= 1'b0; wcnt <= 0; end
        else if (!ack_q) begin
            if (wcnt < memwait) wcnt <= wcnt + 1;
            else begin
                ack_q <= 1'b1;
                if (is_fcmd) flash_id_q <= (h_wdata[7:0] == 8'h90) ? 1'b1 : (h_wdata[7:0] == 8'hFF) ? 1'b0 : flash_id_q;
                if (h_wr) begin
                    if (!is_fcmd && h_addr < 20'h80000) begin
                        mem[h_addr] <= h_wdata[7:0];
                        if (h_word) mem[h_addr + 20'd1] <= h_wdata[15:8];
                    end
                end else if (is_frd) rd_q <= (h_addr[1:0] == 2'b00) ? 16'h0089 : 16'h4470;
                else rd_q <= h_word ? {mem[h_addr + 20'd1], mem[h_addr]} : {8'h00, mem[h_addr]};
            end
        end
    end
    /* glue peek of 186 RAM (the SDRAM client 3 in modem_core): answered one clock later, word at byte address 2*pk_addr */
    always @(posedge clk_cpu) begin
        xdc_ack[3] <= pk_req && !xdc_ack[3];
        if (pk_req && !xdc_ack[3]) xdc_rdata[63:48] <= {mem[{pk_addr[18:0], 1'b1}], mem[{pk_addr[18:0], 1'b0}]};
    end
    assign h_ack   = ack_q;
    assign h_rdata = rd_q;

    /* ---- the DSP: core + program RAM + codec model in the 40.32 MHz domain, the glue stays in the CPU domain. The three clocks are phase aligned (one PLL), so each crossing flag goes
       through one register (XS = 1), and STA times those paths. */
    localparam integer XS = 1;
    logic        dsp_rst_n;
    logic        rst_d_n, dsp_rst_d_n;
    logic        rst_s1, dsp_rst_s1;
    cdc_sync #(.W(1), .STAGES(XS)) u_rst_d  (.clk(clk_dsp), .d_i(rst_n),     .q_o(rst_s1));
    cdc_sync #(.W(1), .STAGES(XS)) u_rstc_d (.clk(clk_dsp), .d_i(dsp_rst_n), .q_o(dsp_rst_s1));
    logic rstl_d_n, rstl_s1;
    cdc_sync #(.W(1), .STAGES(XS)) u_rstl_d (.clk(clk_dsp), .d_i(1'b1), .q_o(rstl_s1));   /* the load path (host writes of the ROM image) is live during the file download, before the core reset is released */
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

    logic pwb_v = 1'b0, pwb_done; logic [31:0] pwb_pay = 32'b0;
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
    logic tb_ld_en = 1'b0; logic [15:0] tb_ld_a, tb_ld_d;
    assign ld_fire      = tb_ld_en || ((pwa_pend_q || pwb_pend_q) && (ld_cnt_q == 2'd0));
    assign pbr_hw_ready = ld_fire;
    always_ff @(posedge clk_dsp) begin
        if (!rstl_d_n)        ld_cnt_q <= 2'd0;
        else if (ld_fire)     ld_cnt_q <= 2'd3;
        else if (ld_cnt_q != 2'd0) ld_cnt_q <= ld_cnt_q - 2'd1;
    end
    logic [15:0] ldw_addr, ldw_data;
    assign ldw_addr = tb_ld_en ? tb_ld_a : hw_sel_a ? pwa_pay[31:16] : pwb_pay[31:16];
    assign ldw_data = tb_ld_en ? tb_ld_d : hw_sel_a ? pwa_pay[15:0]  : pwb_pay[15:0];
    logic [31:0] dsp_mtime;   /* the DSP's model time: the codec frame schedule follows it */

    logic        io_req, io_rd, io_ack, io_strobe;
    logic [15:0] io_port, io_wdata, io_rdata, io_rdata_g;
    logic        dsp_int2, int2_hold_q;
    logic        aic_step, aic_ser_tick, aic_int3, frame_tick;
    logic [15:0] aic_ser_rx, mclk_n, rate_cps, aic_dbg;
    logic        dxr_wr, instr_done, idle_dsp, rx_next;
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
        .mem_wr_pulse    (),
        .mem_wr_pmem     (),
        .mem_wr_addr     (),
        .mem_wr_data     (),
        .instr_done      (instr_done),
        .cycles_o        (dsp_cycles),
        .idle_o          (idle_dsp),
        .mtime_o         (dsp_mtime),
        .ifr_o           (dbg_ifr_o),
        .obs_spc_o       (dbg_spc_o),
        .op_o            (dsp_op),
        .pc_o            (pcdsp_o)
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



    /* ---- line input: silence, or +rxfile=<one signed decimal int16 per line> played from DSP clock +rxat=<n> on, one sample per codec frame (rx_next) */
    reg signed [15:0] rxmem [0:1048575];
    integer rx_n = 0, rx_i = 0, rx_at = 0, rx_fd, rx_r, rx_v;
    reg signed [15:0] rx_cur = 16'sd0;
    string rx_path;
    initial begin
        if ($value$plusargs("rxfile=%s", rx_path)) begin
            void'($value$plusargs("rxat=%d", rx_at));
            rx_fd = $fopen(rx_path, "r");
            while (rx_fd != 0 && !$feof(rx_fd) && rx_n < 1048576) begin rx_r = $fscanf(rx_fd, "%d\n", rx_v); if (rx_r == 1) begin rxmem[rx_n] = rx_v[15:0]; rx_n = rx_n + 1; end end
            $display("[mon] rx file %0s: %0d samples, from dsp clk %0d", rx_path, rx_n, rx_at);
        end
    end
    integer rx_dumpat = -1; string rx_dumpf; string rx_dumpd; integer rx_dumps [0:15]; string rx_dl; integer rx_di, rx_dp;
    initial begin
        for (rx_di = 0; rx_di < 16; rx_di = rx_di + 1) rx_dumps[rx_di] = -1;
        if ($value$plusargs("rxdumpd=%s", rx_dumpd) && $value$plusargs("rxdumps=%s", rx_dl)) begin
            rx_di = 0; rx_dp = 0;
            for (integer ci = 0; ci <= rx_dl.len(); ci = ci + 1) begin
                if (ci == rx_dl.len() || rx_dl[ci] == ",") begin if (rx_di < 16) begin rx_dumps[rx_di] = rx_dp; rx_di = rx_di + 1; end rx_dp = 0; end
                else rx_dp = rx_dp * 10 + (rx_dl[ci] - "0");
            end
        end
    end
    initial begin void'($value$plusargs("rxdump=%d", rx_dumpat)); if (!$value$plusargs("rxdumpf=%s", rx_dumpf)) rx_dumpf = "dmem_rtl.hex"; end
    always @(posedge clk_dsp) if (rx_next && rx_n != 0 && ncyc >= rx_at) begin
        if (rx_i == rx_dumpat) begin $writememh(rx_dumpf, u_dsp.u_mem.dmem); $display("[mon] dmem dumped at rx sample %0d, dsp clk %0d", rx_i, ncyc); end
        for (integer q = 0; q < 16; q = q + 1) if (rx_dumps[q] >= 0 && rx_i == rx_dumps[q]) begin $writememh($sformatf("%0s/dmem_rtl_%0d.hex", rx_dumpd, rx_i), u_dsp.u_mem.dmem); $display("[mon] dmem dumped at rx sample %0d, dsp clk %0d", rx_i, ncyc); end
        rx_cur <= (rx_i < rx_n) ? rxmem[rx_i] : 16'sd0;
        rx_i <= rx_i + 1;
    end
    assign rx_sample = rx_cur;

    /* ---- DSP watch: codec rate changes, and the first jump of the program counter out of program space (history of the last 48 instruction retires) */
    reg [15:0] pc_hist [0:63]; integer pc_hn = 0, pc_dumped = 0, stall_n = 0; reg [15:0] rate_prv2 = 16'd0;
    always @(posedge clk_dsp) if (dsp_rst_d_n) begin
        if (instr_done) begin pc_hist[pc_hn[5:0]] <= pcdsp_o; pc_hn <= pc_hn + 1; end
        if (rate_cps != rate_prv2) begin $display("[rate] %0d cps %0d -> %0d (%0.1f Hz)", ncyc, rate_prv2, rate_cps, 40.32e6 / rate_cps); rate_prv2 <= rate_cps; end
        if (frame_tick) stall_n <= 0; else stall_n <= stall_n + 1;
        if (!pc_dumped && stall_n > 400000 && ncyc > 2000000) begin
            pc_dumped <= 1;
            $display("[crash] %0d no codec frame for 10 ms, dsp pc %04h; last retired pcs:", ncyc, pcdsp_o);
            for (integer q = 47; q >= 0; q = q - 1) $write(" %04h", pc_hist[(pc_hn - 1 - q) & 63]);
            $display("");
        end
    end
    /* ---- DTE serial port and the terminal's keyboard path */
    logic        uart_rx_valid;
    logic rxd = 1'b1; logic [7:0] uart_rx_byte;
    dte_uart #(.CLKS_PER_BIT(175)) u_uart (.clk(clk_cpu), .rst_n(rst_n), .rxd_i(rxd), .txd_o(), .line_o(dte_line), .rx_valid_o(uart_rx_valid), .rx_byte_o(uart_rx_byte),
                                          .tx_valid_i(1'b0), .tx_byte_i(8'h00), .dropped_o());
    logic [15:0] dsp_op_unused;
    logic dte_rx_valid_unused;
    logic dte_rx_valid_r = 1'b0; logic [7:0] dte_rx_byte_r = 8'h00;
    always_ff @(posedge clk_cpu) begin
        if (!rst_n) begin int0_hold_q <= 1'b0; rx_hold_q <= 1'b0; rx_hold_byte_q <= 8'h00; end
        else begin
            if (int0_set) int0_hold_q <= 1'b1; else if (ce_186) int0_hold_q <= 1'b0;
            if (uart_rx_valid) begin rx_hold_q <= 1'b1; rx_hold_byte_q <= uart_rx_byte; end else if (ce_186) rx_hold_q <= 1'b0;
        end
    end

    integer ncyc = 0, k, ff, n;
    reg [7:0] b8;
    reg [8*256-1:0] flash_path, nvram_path, rom_path;
    integer clocks_max, mon_every, dsp_start_clk = -1;
    always @(posedge clk_dsp) ncyc <= ncyc + 1;
    always @(posedge clk_dsp) if (dsp_rst_d_n && dsp_start_clk < 0) begin dsp_start_clk <= ncyc; $display("[mon] DSP released at dsp clk %0d", ncyc); end
    always @(posedge clk_dsp) if (mon_every > 0 && ncyc % mon_every == 0)
        $display("[mon] clk=%0d pc186=%05h run=%b mtime=%0d frame=%0d target=%0d timer_exp=%0d dsp_pc=%04h ifr=%04h imr=%04h intm=%b idle=%0d sp=%0d icu=%07h frames=%0d dxr=%0d ticks=%0d int0=%0d", ncyc, pc186_o, glue_run, dsp_mtime, u_aic.frame_q, u_aic.target_q, timer_exp[15:0], pcdsp_o, dbg_ifr_o, u_dsp.u_addr.imr_q, u_dsp.u_addr.intm_q, u_dsp.u_ctrl.idle_q, u_dsp.sp_o, dbg_icu_o, n_frame, n_dxr, n_tick3, n_int0);
    integer n_frame = 0, n_dxr = 0, n_int0 = 0, n_tick3 = 0;
    always @(posedge clk_dsp) begin if (frame_tick) n_frame <= n_frame + 1; if (dxr_wr) n_dxr <= n_dxr + 1; if (aic_ser_tick) n_tick3 <= n_tick3 + 1; end
    always @(posedge clk_cpu) if (int0_hold_q) n_int0 <= n_int0 + 1;
    integer tr_from, tr_n = 0, tr_max;
    initial begin if (!$value$plusargs("trfrom=%d", tr_from)) tr_from = -1; if (!$value$plusargs("trmax=%d", tr_max)) tr_max = 3000; end
    always @(posedge clk_dsp) if (tr_from >= 0 && ncyc >= tr_from && tr_n < tr_max && instr_done) begin
        $display("[tr] %0d pc=%04h op=%04h sp=%0d top=%04h", ncyc, pcdsp_o, dsp_op, u_dsp.sp_o, u_dsp.stack_top_o);
        tr_n <= tr_n + 1;
    end
    integer ev_from, ev_to; reg [15:0] ifr_prev = 0;
    initial begin if (!$value$plusargs("evfrom=%d", ev_from)) ev_from = -1; if (!$value$plusargs("evto=%d", ev_to)) ev_to = -1; end
    always @(posedge clk_dsp) if (ev_from >= 0 && ncyc >= ev_from && ncyc <= ev_to) begin
        if (aic_ser_tick) $display("[ev] %0d TICK  pc=%04h ifr=%04h imr=%04h intm=%b idle=%0d sp=%0d xrdy=%b", ncyc, pcdsp_o, dbg_ifr_o, u_dsp.u_addr.imr_q, u_dsp.u_addr.intm_q, u_dsp.u_ctrl.idle_q, u_dsp.sp_o, u_dsp.u_mem.xrdy_q);
        if (dbg_ifr_o != ifr_prev) $display("[ev] %0d IFR %04h -> %04h pc=%04h intm=%b", ncyc, ifr_prev, dbg_ifr_o, pcdsp_o, u_dsp.u_addr.intm_q);
        ifr_prev <= dbg_ifr_o;
        if (dxr_wr)       $display("[ev] %0d DXR=%04h pc=%04h", ncyc, dxr_wdata, pcdsp_o);
    end
    /* leak detector: ring of the last 96 retired DSP instructions; dumped the first time the DSP goes idle with sp != 7 */
    reg [15:0] rg_pc [0:127]; reg [15:0] rg_op [0:127]; reg [3:0] rg_sp [0:127]; reg [31:0] rg_t [0:127];
    integer rg_i = 0, rg_dumped = 0, rgk; reg idle_prev = 0;
    always @(posedge clk_dsp) begin
        if (instr_done) begin rg_pc[rg_i] <= pcdsp_o; rg_op[rg_i] <= dsp_op; rg_sp[rg_i] <= u_dsp.sp_o; rg_t[rg_i] <= ncyc; rg_i <= (rg_i + 1) % 128; end
        idle_prev <= (u_dsp.u_ctrl.idle_q == 2'd1);
        if (!rg_dumped && ncyc > 40000000 && (u_dsp.u_ctrl.idle_q == 2'd1) && !idle_prev && u_dsp.sp_o != 4'd7) begin
            rg_dumped <= 1;
            $display("[leak] DSP idles with sp=%0d at %0d, last retires:", u_dsp.sp_o, ncyc);
            for (rgk = 0; rgk < 128; rgk = rgk + 1)
                $display("[leak] %0d pc=%04h op=%04h sp=%0d", rg_t[(rg_i + rgk) % 128], rg_pc[(rg_i + rgk) % 128], rg_op[(rg_i + rgk) % 128], rg_sp[(rg_i + rgk) % 128]);
        end
    end
    /* load per 500k-clock window: busy (not IDLE) clocks, retires, charged model cycles */
    integer ld_busy = 0, ld_ret = 0, ld_cyc = 0, ld_peak = 0; reg [63:0] ld_cyc_prev = 0, ld_ret_prev = 0;
    always @(posedge clk_dsp) if (dsp_rst_d_n) begin
        if (u_dsp.u_ctrl.idle_q == 2'd0) ld_busy <= ld_busy + 1;
        if (ncyc % 500000 == 0) begin
            $display("[load] clk=%0d busy=%0d%% retires=%0d charged=%0d (per busy clk: ipc=%0.2f cyc=%0.2f)", ncyc, ld_busy * 100 / 500000, u_dsp.u_ctrl.retire_cnt_q - ld_ret_prev, u_dsp.u_ctrl.cycles_q - ld_cyc_prev,
                     ld_busy ? (u_dsp.u_ctrl.retire_cnt_q - ld_ret_prev) * 1.0 / ld_busy : 0.0, ld_busy ? (u_dsp.u_ctrl.cycles_q - ld_cyc_prev) * 1.0 / ld_busy : 0.0);
            ld_busy <= 0; ld_ret_prev <= u_dsp.u_ctrl.retire_cnt_q; ld_cyc_prev <= u_dsp.u_ctrl.cycles_q;
        end
    end
    integer gwf = 0;
    initial if ($test$plusargs("gw")) gwf = 1;
    always @(posedge clk_cpu) if (gwf && glue_wr_commit && ncyc > 2000000 && (glue_wr_port == 16'h005C || glue_wr_port == 16'h005E || glue_wr_port == 16'h001E)) $display("[gw] %0d port=%04h data=%02h", ncyc, glue_wr_port, glue_wr_data);
    always @(posedge clk_dsp) if (gwf && dsp_int2_d && ncyc > 25000000) $display("[gw] %0d INT2 to DSP", ncyc);
    integer dinf = 0;
    initial if ($test$plusargs("din")) dinf = 1;
    reg io_req_prev = 0;
    always @(posedge clk_dsp) begin
        io_req_prev <= io_req;
        if (dinf && io_req && !io_req_prev && io_rd && io_port[7:3] == 5'b01011 && ncyc > 40000000) $display("[din] %0d port=%02h", ncyc, io_port[7:0]);
        if (dinf && io_ack && io_rd && io_port[7:3] == 5'b01011 && ncyc > 40000000) $display("[din] %0d port=%02h val=%04h", ncyc, io_port[7:0], io_rdata);
    end
    /* 186 PC history: dumped when the 186 first enters the boot-fault blinker at 80f99 */
    reg [19:0] pch [0:127]; integer pch_i = 0, pch_dumped = 0, pchk; reg [19:0] pch_prev = 0;
    always @(posedge clk_cpu) begin
        if (pc186_o != pch_prev) begin pch[pch_i] <= pc186_o; pch_i <= (pch_i + 1) % 128; pch_prev <= pc186_o; end
        if (!pch_dumped && pc186_o == 20'h80f99) begin
            pch_dumped <= 1;
            $display("[pch] 186 entered 80f99 at dsp clk %0d; last PCs:", ncyc);
            for (pchk = 0; pchk < 128; pchk = pchk + 1) $display("[pch] %05h", pch[(pch_i + pchk) % 128]);
        end
    end
    /* firmware tick counter (ds:0x12A, bumped by the INT3 tick handler): sampled every +tickmon=N dsp clocks */
    integer tickmon = 0; reg [15:0] tk_prev = 0; integer tk_prev_t = 0;
    initial if (!$value$plusargs("tickmon=%d", tickmon)) tickmon = 0;
    always @(posedge clk_dsp) if (tickmon > 0 && ncyc % tickmon == 0 && ncyc > 17000000) begin
        $display("[tick] clk=%0d tick12a=%0d delta=%0d per_second=%0.1f", ncyc, {mem[20'h12b], mem[20'h12a]}, ({mem[20'h12b], mem[20'h12a]} - tk_prev) & 16'hFFFF, (({mem[20'h12b], mem[20'h12a]} - tk_prev) & 16'hFFFF) * 40.32e6 / (ncyc - tk_prev_t));
        tk_prev <= {mem[20'h12b], mem[20'h12a]}; tk_prev_t <= ncyc;
    end
    /* INT3 (Timer-0 tick) request rising edges per window */
    integer i3n = 0; reg i3p = 0; integer i3t = 0;
    always @(posedge clk_cpu) begin i3p <= dbg_icu_o[24]; if (dbg_icu_o[24] && !i3p) i3n <= i3n + 1; end
    always @(posedge clk_dsp) if (tickmon > 0 && ncyc % tickmon == 0 && ncyc > 17000000) begin $display("[i3] clk=%0d INT3 requests in window=%0d (%0.1f /s)", ncyc, i3n - i3t, (i3n - i3t) * 40.32e6 / tickmon); i3t <= i3n; end
    /* 186 reads of the event / overlay / mailbox ports, committed once per read */
    integer grf = 0, dfrom = 200000000, dto = 2000000000;
    initial begin void'($value$plusargs("dfrom=%d", dfrom)); void'($value$plusargs("dto=%d", dto)); end
    initial if ($test$plusargs("gr")) grf = 1;
    always @(posedge clk_cpu) if (grf && glue_rd_commit && ncyc > dfrom && (glue_rd_port == 16'h001C || glue_rd_port == 16'h001E || (glue_rd_port >= 16'h0058 && glue_rd_port <= 16'h005E))) $display("[gr] %0d port=%04h data=%02h", ncyc, glue_rd_port, glue_rd_data);
    /* diag: state the dial routine depends on, at each mailbox command to the DSP and each 0x134 change */
    reg [15:0] c134_prev = 16'h0;
    always @(posedge clk_cpu) if (grf && ncyc > dfrom) begin
        if (glue_wr_commit && glue_wr_port == 16'h005C) $display("[dial] %0d cmd-lo=%02h [5a0]=%02h [dec]=%02h [134]=%04h", ncyc, glue_wr_data, mem[20'h5a0], mem[20'hdec], {mem[20'h135], mem[20'h134]});
        c134_prev <= {mem[20'h135], mem[20'h134]};
        if ({mem[20'h135], mem[20'h134]} != c134_prev) $display("[t134] %0d %04h", ncyc, {mem[20'h135], mem[20'h134]});
    end
    /* diag: DSP port accesses to the mailbox / status ports */
    always @(posedge clk_cpu) if (grf && ncyc > dfrom && ncyc < dto && io_strobe && (io_pay[31:16] == 16'h0057 || io_pay[31:16] == 16'h0056 || (io_pay[31:16] >= 16'h0058 && io_pay[31:16] <= 16'h005f)))
        $display("[dsp] %0d %s port=%04h data=%04h", ncyc, io_pay[32] ? "RD" : "WR", io_pay[31:16], io_pay[15:0]);

    /* ---- +restore=<prefix>: start from a C-machine whole-system snapshot (prefix_mem.bin, _sys.txt, _snv.hex, _pm.hex, _dm.hex written by tools/mksnap.py) */
    reg [31:0] snv [0:511];
    string rs_prefix;
    integer rs_fd, rs_r, rs_i, rs_idx;
    reg [8*10-1:0] rs_key;
    reg [63:0] rs_val;
    logic [7:0] rs_aic [1:6];
    logic [15:0] dm_full [0:65535];
    task automatic restore_sys_side();
        automatic string fn;
        fn = {rs_prefix, "_sys.txt"};
        rs_fd = $fopen(fn, "r");
        if (rs_fd == 0) begin $display("restore: cannot open %0s", fn); $finish; end
        while (!$feof(rs_fd)) begin
            rs_r = $fscanf(rs_fd, "%s %d %h\n", rs_key, rs_idx, rs_val);
            if (rs_r == 3) begin
                case (rs_key)
                    "pcb":      begin u_186.u_sys.pcb_w[rs_idx] = rs_val[15:0]; if (rs_idx == 8'h2B) u_186.u_sys.pcb_sh_56 = rs_val[15:0]; if (rs_idx == 8'h2C) u_186.u_sys.pcb_sh_58 = rs_val[15:0]; if (rs_idx == 8'h2F) u_186.u_sys.pcb_sh_5e = rs_val[15:0]; if (rs_idx == 8'h54) u_186.u_sys.pcb_sh_a8 = rs_val[15:0]; end
                    "pcb_mem":  u_186.u_sys.pcb_mem = rs_val[0];
                    "port":     begin u_186.u_sys.ports_w[rs_idx] = rs_val[15:0]; if (rs_idx == 0) u_186.u_sys.ports_sh_00 = rs_val[15:0]; if (rs_idx == 18) u_186.u_sys.ports_sh_12 = rs_val[15:0]; if (rs_idx == 20) u_186.u_sys.ports_sh_14 = rs_val[15:0]; end
                    "portset":  u_186.u_sys.ports_set[rs_idx] = rs_val[0];
                    "h2d":      u_glue.h2d_q[rs_idx] = rs_val[15:0];
                    "d2h":      u_glue.d2h_q[rs_idx] = rs_val[15:0];
                    "pst":      u_glue.port_store[rs_idx] = rs_val[15:0];
                    "flags56":  u_glue.flags56_q = rs_val[15:0];
                    "flagsD":   begin u_glue.flags_d_q = rs_val[15:0]; u_glue.flags_vis_q = rs_val[15:0]; end
                    "evt":      u_glue.evt_q = rs_val[7:0];
                    "evt_seen": u_glue.evt_seen_q = rs_val[7:0];
                    "h2d_pending": u_glue.h2d_pending_q = rs_val[0];
                    "d2h_valid":   u_glue.d2h_valid_q = rs_val[0];
                    "data_word":   u_glue.data_word_q = rs_val[15:0];
                    "data_full":   u_glue.data_full_q = rs_val[0];
                    "ovl_status":  u_glue.ovl_status_q = rs_val[2:0];
                    "ovl_addr":    u_glue.ovl_ptr_q = rs_val[15:0];
                    "mclk_n":      u_glue.mclk_n_q = rs_val[15:0];
                    "hb_count":    u_glue.hb_count_q = rs_val;
                    "hb_pending":  u_glue.hb_pending_q = rs_val[0];
                    "req":      u_186.u_sys.req_r = rs_val[9:0];
                    "msk":      u_186.u_sys.msk_r = rs_val[7:0];
                    "primsk":   u_186.u_sys.primsk_r = rs_val[2:0];
                    "icon": case (rs_idx)
                                18: u_186.u_sys.icon_12 = rs_val[2:0]; 20: u_186.u_sys.icon_14 = rs_val[2:0]; 22: u_186.u_sys.icon_16 = rs_val[2:0];
                                24: u_186.u_sys.icon_18 = rs_val[2:0]; 26: u_186.u_sys.icon_1a = rs_val[2:0]; 28: u_186.u_sys.icon_1c = rs_val[2:0]; 30: u_186.u_sys.icon_1e = rs_val[2:0];
                                default: ;
                            endcase
                    "isvp":     if (rs_idx < 8) u_186.u_sys.isv_present_r[rs_idx] = rs_val[0];
                    "isvv":     if (rs_idx < 8) u_186.u_sys.isv_val_r[rs_idx] = rs_val[2:0];
                    "tcnt":     u_186.u_sys.tmr_cnt[rs_idx] = rs_val[15:0];
                    "tcmpa":    u_186.u_sys.tmr_cmpa[rs_idx] = rs_val[15:0];
                    "tcmpb":    u_186.u_sys.tmr_cmpb[rs_idx] = rs_val[15:0];
                    "tcon":     u_186.u_sys.tmr_con[rs_idx] = rs_val[15:0];
                    "ucmp":     u_186.u_sys.uart_cmp[rs_idx] = rs_val[15:0];
                    "ucon":     u_186.u_sys.uart_con[rs_idx] = rs_val[15:0];
                    "usts":     u_186.u_sys.uart_sts[rs_idx] = rs_val[15:0];
                    "urbuf":    u_186.u_sys.uart_rbuf[rs_idx] = rs_val[15:0];
                    "utx":      u_186.u_sys.uart_tx_left[rs_idx] = rs_val[63] ? 22'd0 : rs_val[21:0];
                    "eew":      u_186.u_sys.ee_w[rs_idx] = rs_val[15:0];
                    "ee":       case (rs_idx) 0: u_186.u_sys.ee_ewen = rs_val[0]; 1: u_186.u_sys.ee_state = rs_val[1:0]; 2: u_186.u_sys.ee_nbits = rs_val[3:0];
                                               3: u_186.u_sys.ee_do_bit = rs_val[0]; 4: u_186.u_sys.ee_addr = rs_val[7:0]; 5: u_186.u_sys.ee_rdn = rs_val[3:0]; default: ; endcase
                    "eeb":      u_186.u_sys.ee_bits[rs_idx] = rs_val[0];
                    "line":     u_186.u_sys.line_r = rs_val[0];
                    "aic":      if (rs_idx >= 1 && rs_idx <= 6) begin u_aic.aic_q[rs_idx] = rs_val[7:0]; rs_aic[rs_idx] = rs_val[7:0]; end
                    default: ;
                endcase
            end
        end
        $fclose(rs_fd);
        u_glue.run_q = 1'b1; u_glue.run_d_q = 1'b1;
        u_glue.burst_skip_q = 5'd0; u_glue.res_left_q = 16'd0;
        u_aic.upd_q = 1'b1;
    endtask
    task automatic restore_dsp_side();
        integer i;
        $readmemh({rs_prefix, "_snv.hex"}, snv);
        $readmemh({rs_prefix, "_pm.hex"}, u_dsp.u_mem.pmem);
        $readmemh({rs_prefix, "_pm.hex"}, u_dsp.u_mem.pmem2);
        $readmemh({rs_prefix, "_dm.hex"}, dm_full); for (integer q = 0; q < 4096; q = q + 1) u_dsp.u_mem.dmem[q] = dm_full[q];
`include "dsp_restore.svh"
        $display("[mon] DSP state restored, pc=%04h", snv[28]);
    endtask
    always @(u_glue.evt_q or u_glue.h2d_pending_q or u_glue.evt_seen_q) if (grf && ncyc > dfrom && ncyc < dto) $display("[evt] %0d evt=%02h seen=%02h h2d_pend=%b pk=%0d wr=%b/%04h/%02h", ncyc, u_glue.evt_q, u_glue.evt_seen_q, u_glue.h2d_pending_q, u_glue.pk_q, glue_wr_commit, glue_wr_port, glue_wr_data);
    always @(posedge clk_cpu) if (grf && ncyc > dfrom && ncyc < dto && u_glue.pk_q == 3'd2 && xdc_ack[3]) $display("[pk] %0d rd_ptr=%04h wr_ptr=%04h h2d_pend=%b evt=%02h mem29a=%02h%02h mem29c=%02h%02h", ncyc, u_glue.pk_a_q, xdc_rdata[63:48], u_glue.h2d_pending_q, u_glue.evt_q, mem[20'h29b], mem[20'h29a], mem[20'h29d], mem[20'h29c]);
    /* DTE bytes from the modem */
    always @(posedge clk_cpu) if (dte_tx_valid) $display("[tx] %0d %02h %c", ncyc, dte_tx_byte, (dte_tx_byte >= 32 && dte_tx_byte < 127) ? dte_tx_byte : 8'h2E);
    always @(posedge clk_cpu) if (rx_hold_q) $display("[rx] %0d %02h", ncyc, rx_hold_byte_q);
    integer dacf; reg [15:0] rate_prev = 0;
    initial begin dacf = 0; if ($test$plusargs("dac")) dacf = $fopen("dac.txt", "w"); end
    always @(posedge clk_dsp) if (dacf != 0) begin
        if (dac_valid_d) $fwrite(dacf, "%0d %0d\n", dsp_mtime, $signed(dac_sample_d));
        if (rate_cps != rate_prev) $fwrite(dacf, "R %0d %0d\n", dsp_mtime, rate_cps);
        rate_prev <= rate_cps;
    end

    reg [8*80-1:0] send_text; integer send_at, ci, nch;
    reg [7:0] ch; integer bi;
    initial begin
        if (!$value$plusargs("send=%s", send_text)) send_text = "";
        if (!$value$plusargs("sendat=%d", send_at)) send_at = 40000000;
        wait (rst_n); 
        wait (ncyc >= send_at);
        nch = 0; for (ci = 0; ci < 80; ci = ci + 1) if (send_text[8*ci +: 8] != 0) nch = ci + 1;
        for (ci = nch - 1; ci >= 0; ci = ci - 1) begin
            ch = send_text[8*ci +: 8]; if (ch == "@") begin repeat (30000000) @(posedge clk_dsp); end else begin if (ch == "~") ch = 8'h0D;
            /* 115200 8N1 on the serial pin: the firmware measures the bit time on the line */
            @(posedge clk_cpu); rxd <= 1'b0; repeat (175) @(posedge clk_cpu);
            for (bi = 0; bi < 8; bi = bi + 1) begin rxd <= ch[bi]; repeat (175) @(posedge clk_cpu); end
            rxd <= 1'b1; repeat (175) @(posedge clk_cpu);
            repeat (6000) @(posedge clk_cpu);
            end
        end
        $display("[mon] typed at dsp clk %0d", ncyc);
    end
    initial begin
        if (!$value$plusargs("flash=%s", flash_path)) flash_path = "sdcard/games/Modem/boot0.rom";
        if (!$value$plusargs("nvram=%s", nvram_path)) nvram_path = "sdcard/games/Modem/boot1.rom";
        if (!$value$plusargs("rom=%s", rom_path))     rom_path   = "sdcard/games/Modem/boot2.rom";
        if (!$value$plusargs("clocks=%d", clocks_max)) clocks_max = 50000000;
        if (!$value$plusargs("mon=%d", mon_every)) mon_every = 0;
        for (k = 0; k < 1048576; k = k + 1) mem[k] = 8'hFF;
        ff = $fopen(flash_path, "rb");
        if (ff == 0) begin $display("no flash %0s", flash_path); $finish; end
        for (k = 0; k < 524288; k = k + 1) begin n = $fread(b8, ff); mem[20'h80000 + k] = b8; end
        $fclose(ff);
        /* DSP on-chip ROM: byte pairs, little endian, into program words 0.. */
        ff = $fopen(rom_path, "rb");
        if (ff != 0) begin
            repeat (6) @(posedge clk_dsp);
            for (k = 0; k < 8192; k = k + 1) begin
                reg [7:0] lo, hi;
                n = $fread(lo, ff); n = $fread(hi, ff);
                @(posedge clk_dsp); tb_ld_en <= 1; tb_ld_a <= k[15:0]; tb_ld_d <= {hi, lo};
                @(posedge clk_dsp); tb_ld_en <= 0;
                repeat (3) @(posedge clk_dsp);
            end
            $fclose(ff);
        end
        /* NVRAM (256 words, little endian): the EEPROM load path */
        ff = $fopen(nvram_path, "rb");
        if (ff != 0) begin
            for (k = 0; k < 256; k = k + 1) begin
                reg [7:0] lo, hi;
                n = $fread(lo, ff); n = $fread(hi, ff);
                @(posedge clk_cpu); ee_a_q <= k[7:0]; ee_d_q <= {hi, lo}; ee_en_c <= 1;
                @(posedge clk_cpu); ee_en_c <= 0;
            end
            $fclose(ff);
        end
        repeat (8) @(posedge clk_cpu);
        if ($value$plusargs("restore=%s", rs_prefix)) begin
            ff = $fopen({rs_prefix, "_mem.bin"}, "rb");
            for (k = 0; k < 1048576; k = k + 1) begin n = $fread(b8, ff); mem[k] = b8; end
            $fclose(ff);
            force dsp_rst_d_n = 1'b0;
            force u_dsp.step_i = 1'b0;                 // fetch held until the state is in (as the co-sim shim does)
            @(negedge clk_cpu);
            rst_n = 1;
            restore_sys_side();
            repeat (40) @(posedge clk_dsp);
            @(negedge clk_dsp);
            release dsp_rst_d_n;
            repeat (24) @(posedge clk_dsp);            // every reset stage settles with the fetch held (the deposit would be wiped before this)
            @(negedge clk_dsp);
            restore_dsp_side();
            for (integer q = 0; q < 512; q = q + 1) u_dsp.u_mem.shadow_b0[q] = u_dsp.u_mem.dmem[16'h100 + q];
            for (integer q = 0; q < 1024; q = q + 1) u_dsp.u_mem.shadow_sa[q] = u_dsp.u_mem.dmem[16'h800 + q];
            for (integer ai = 1; ai <= 6; ai = ai + 1) u_aic.aic_q[ai] = rs_aic[ai];   // the DSP-side reset cleared them
            force u_dsp.step_i = 1'b1; release u_dsp.step_i;
            $display("[mon] restored from %0s at dsp clk %0d", rs_prefix, ncyc);
        end else
        rst_n = 1;
        $display("[mon] files loaded, reset released at dsp clk %0d", ncyc);
        repeat (clocks_max) @(posedge clk_dsp);
        $display("[mon] done at %0d", ncyc);
        $finish;
    end

    integer wwatch_n = 0;
    always @(posedge clk_dsp) if (u_dsp.u_mem.dmem_wr_en && wwatch_n < 0 && (u_dsp.u_mem.dmem_waddr >= 16'h012A && u_dsp.u_mem.dmem_waddr <= 16'h013D)) begin
        wwatch_n <= wwatch_n + 1;
        $display("[w12f] clk %0d addr %04h data %04h pc %04h", ncyc, u_dsp.u_mem.dmem_waddr, u_dsp.u_mem.dmem_wdata, pcdsp_o);
    end

    logic [15:0] aic4_prev = 16'hxxxx;
    always @(posedge clk_dsp) if (u_aic.aic_q[4] !== aic4_prev) begin aic4_prev <= u_aic.aic_q[4]; $display("[aic4] clk %0d aic_q[4]=%04h gain_in=%0d", ncyc, u_aic.aic_q[4], u_aic.aic_q[4][3:2]); end

    integer pcw_n [0:7]; initial for (integer k=0;k<8;k=k+1) pcw_n[k]=0;
    always @(posedge clk_dsp) begin
        if (pcdsp_o==16'hB308 && pcw_n[0]<5) begin pcw_n[0]<=pcw_n[0]+1; $display("[pc] clk %0d B308 [2B]=%04h", ncyc, u_dsp.u_mem.dmem[16'h2B]); end
        if (pcdsp_o==16'hB312 && pcw_n[1]<5) begin pcw_n[1]<=pcw_n[1]+1; $display("[pc] clk %0d B312", ncyc); end
        if (pcdsp_o==16'hBE61 && pcw_n[2]<5) begin pcw_n[2]<=pcw_n[2]+1; $display("[pc] clk %0d BE61", ncyc); end
        if (pcdsp_o==16'hBEAC && pcw_n[3]<5) begin pcw_n[3]<=pcw_n[3]+1; $display("[pc] clk %0d BEAC", ncyc); end
    end

    logic [15:0] ovl_prev = 16'h0; logic [15:0] d2h7_prev = 16'h0;
    integer burst_t0 = -1; integer burst_n = 0;
    always @(posedge clk_dsp) begin
        if (u_glue.d2h_q[7] !== d2h7_prev) begin if (u_glue.d2h_q[7] != 16'h0) begin $display("[msg] clk %0d d2h7=%04h w6=%04h valid=%b evt=%02h", ncyc, u_glue.d2h_q[7], u_glue.d2h_q[6], u_glue.d2h_valid_q, u_glue.evt_q); if (u_glue.d2h_q[7] == 16'h00c1) burst_t0 <= ncyc; end d2h7_prev <= u_glue.d2h_q[7]; end
        if (burst_t0 >= 0 && ncyc < burst_t0 + 4000000 && burst_n < 300) begin
            if (u_glue.rd_commit_i && (u_glue.rd_port_i == 16'h0058 || (u_glue.rd_port_i >= 16'h005C && u_glue.rd_port_i <= 16'h005F) || u_glue.rd_port_i == 16'h001C)) begin burst_n <= burst_n + 1; $display("[b] clk %0d RD %04h valid=%b evt=%02h", ncyc, u_glue.rd_port_i, u_glue.d2h_valid_q, u_glue.evt_q); end
            if (u_glue.wr_commit_i && (u_glue.wr_port_i == 16'h001C || u_glue.wr_port_i == 16'h0058 || u_glue.wr_port_i >= 16'h005C)) begin burst_n <= burst_n + 1; $display("[b] clk %0d WR %04h=%02h valid=%b evt=%02h", ncyc, u_glue.wr_port_i, u_glue.wr_data_i, u_glue.d2h_valid_q, u_glue.evt_q); end
            if (u_glue.msg_ev_q) $display("[b] clk %0d DSP wrote 5F valid=%b evt=%02h", ncyc, u_glue.d2h_valid_q, u_glue.evt_q);
        end
    end
    integer ar7_n = 0; logic [15:0] ar7_prev = 16'h0;
    always @(posedge clk_dsp) if (ncyc > 200000) begin
        if ((u_dsp.u_addr.ar_q[7] < 16'h0BD0 || u_dsp.u_addr.ar_q[7] > 16'h0BDF) && ar7_n < 60 && u_dsp.u_addr.ar_q[7] !== ar7_prev) begin
            $display("[ar7] clk %0d AR7=%04h pc=%04h cbcr=%02h cbsr1=%04h cber1=%04h", ncyc, u_dsp.u_addr.ar_q[7], pcdsp_o, u_dsp.u_addr.cbcr_q, u_dsp.u_addr.cbsr1_q, u_dsp.u_addr.cber1_q); ar7_n <= ar7_n + 1;
        end
        ar7_prev <= u_dsp.u_addr.ar_q[7];
    end
    logic [15:0] d2h7_prev2 = 16'h0; integer msg_n = 0;
    always @(posedge clk_dsp) if (u_glue.d2h_q[7] !== d2h7_prev2) begin
        if (u_glue.d2h_q[7] != 16'h0 && msg_n < 400) begin $display("[msg] clk %0d d2h7=%04h w6=%04h", ncyc, u_glue.d2h_q[7], u_glue.d2h_q[6]); msg_n <= msg_n + 1; end
        d2h7_prev2 <= u_glue.d2h_q[7];
    end
endmodule
