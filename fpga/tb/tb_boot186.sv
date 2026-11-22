/* Fast boot of the real SV25 firmware: i186_top + mem186 + dsp_glue (no DSP, no SDRAM) on one clock with a 1-clock-latency flat memory, to reach the firmware's DSP start
   and what follows in about a minute of simulation instead of hours. Local firmware only (+flash= +nvram=). Prints the 186's PC every +pcs= clocks, the ICU / timer-0 state
   and the tick counter [0x12A] every +ticks= clocks. Not part of `make test`. */
`default_nettype none
`timescale 1ns/1ps
module tb_boot186;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic        h_req, h_wr, h_word, h_is_mmio, h_ack;
  logic [19:0] h_addr;
  logic [15:0] h_wdata, h_rdata;
  logic        rq_req, rq_we, rq_ack;
  logic [1:0]  rq_be;
  logic [23:0] rq_addr;
  logic [15:0] rq_wdata, rq_rdata;
  logic        dte_tx_valid, dsp_start_req, burst_valid, glue_rd_commit, glue_wr_commit, glue_run, int0_set;
  logic [7:0]  dte_tx_byte, glue_rd_data, glue_wr_data;
  logic [63:0] burst_data, hb_count, unused_cycles;
  logic [15:0] glue_rd_port, glue_wr_port;
  logic        ee_en = 0;
  logic [7:0]  ee_a = 0;
  logic [15:0] ee_d = 0;
  logic [19:0] pc;
  logic        pk_req;
  logic [23:0] pk_addr;
  logic        unused_h, unused_b;
  logic [19:0] unused_bpc;
  logic [7:0]  unused_bop, unused_evt;
  logic [15:0] unused_h2d0, unused_rel;
  logic        dsp_int2, dsp_rst_n;
  logic [15:0] mclk_n, pw_addr, pw_data;
  logic        pw_en, io_ack;
  logic [15:0] io_rdata;

  i186_top u_186 (
    .clk(clk), .ce_i(1'b1), .rst_n(rst_n), .model_tick_en(1'b1), .nmi_req(1'b0), .cyc_model(1'b1), .ud_trap(1'b1),
    .h_req(h_req), .h_wr(h_wr), .h_word(h_word), .h_is_mmio(h_is_mmio), .h_addr(h_addr), .h_wdata(h_wdata), .h_rdata(h_rdata), .h_ack(h_ack),
    .dte_tx_valid(dte_tx_valid), .dte_tx_byte(dte_tx_byte), .dte_rx_valid(1'b0), .dte_rx_byte(8'h00), .line(1'b1),
    .dsp_start_req(dsp_start_req), .burst_valid(burst_valid), .burst_data(burst_data),
    .port_in_10(8'h00), .port_in_12(8'h9A), .port_in_14(8'h44), .hw_idx(4'd7), .ring_on(1'b0), .hb_count(hb_count), .hb_ticks(64'd1), .p2pin_in(8'h40),
    .ee_load_en(ee_en), .ee_load_addr(ee_a), .ee_load_data(ee_d),
    .core_cycles(unused_cycles), .core_halted(unused_h), .core_pc(pc), .core_badop(unused_b), .core_badop_pc(unused_bpc), .core_badop_opcode(unused_bop),
    .dbg_evt(unused_evt), .dbg_h2d0(unused_h2d0), .dbg_pcb_relreg(unused_rel),
    .dsp_run_i(glue_run), .glue_rd_data_i(glue_rd_data), .glue_rd_port_o(glue_rd_port), .glue_rd_commit_o(glue_rd_commit), .glue_wr_commit_o(glue_wr_commit),
    .glue_wr_port_o(glue_wr_port), .glue_wr_data_o(glue_wr_data), .int0_set_i(int0_set));

  mem186 #(.BASE(24'h000000)) u_mem (
    .clk(clk), .rst_n(rst_n), .h_req(h_req), .h_wr(h_wr), .h_word(h_word), .h_is_mmio(h_is_mmio), .h_addr(h_addr), .h_wdata(h_wdata), .h_rdata(h_rdata), .h_ack(h_ack),
    .rq_req_o(rq_req), .rq_we_o(rq_we), .rq_be_o(rq_be), .rq_addr_o(rq_addr), .rq_wdata_o(rq_wdata), .rq_ack_i(rq_ack), .rq_rdata_i(rq_rdata));

  dsp_glue u_glue (
    .clk(clk), .rst_n(rst_n), .rd_port_i(glue_rd_port), .rd_data_o(glue_rd_data), .rd_commit_i(glue_rd_commit), .wr_commit_i(glue_wr_commit), .wr_port_i(glue_wr_port), .wr_data_i(glue_wr_data),
    .run_o(glue_run), .int0_set_o(int0_set), .hb_count_o(hb_count), .rom_loaded_i(1'b1), .dsp_start_req_i(dsp_start_req), .burst_valid_i(burst_valid), .burst_data_i(burst_data),
    .io_req_i(1'b0), .io_rd_i(1'b0), .io_addr_i(16'h0), .io_wdata_i(16'h0), .io_ack_o(io_ack), .io_rdata_o(io_rdata), .dsp_rst_n_o(dsp_rst_n), .dsp_int2_o(dsp_int2), .mclk_n_o(mclk_n),
    .pw_en_o(pw_en), .pw_addr_o(pw_addr), .pw_data_o(pw_data), .pw_ready_i(1'b1), .frame_tick_i(1'b0), .dsp_timer_exp_i(16'h0),
    .pk_req_o(pk_req), .pk_addr_o(pk_addr), .pk_ack_i(pk_req), .pk_rdata_i(pk_rdata));

  /* flat word memory, 1 MB; 0x80000.. read only */
  logic [15:0] wm [0:524287];
  logic [15:0] pk_rdata;
  assign pk_rdata = wm[pk_addr[18:0]];
  logic ack_q;
  assign rq_ack = rq_req && !ack_q;
  assign rq_rdata = wm[rq_addr[18:0]];
  always @(posedge clk) begin
    ack_q <= rq_ack;
    if (rq_ack && rq_we && rq_addr[18:0] < 19'h40000) begin
      if (rq_be[0]) wm[rq_addr[18:0]][7:0]  <= rq_wdata[7:0];
      if (rq_be[1]) wm[rq_addr[18:0]][15:8] <= rq_wdata[15:8];
    end
  end

  integer icu_n = 0;
  always @(posedge clk) if (rst_n && $test$plusargs("icu") && cyc > 5000000 && icu_n < 400) begin
    if (u_186.u_sys.irq_ack && u_186.u_sys.icu_best_v) begin $display("[tb] ICU ack vec %02h pc %05h clock %0d isv=%b", u_186.u_sys.irq_ack_vec, pc, cyc, u_186.u_sys.isv_present_r); icu_n <= icu_n + 1; end
    if (u_186.u_sys.cmt_pcb_wr && u_186.u_sys.cmt_pcb_reg == 8'h02) begin $display("[tb] ICU eoi %04h pc %05h clock %0d isv=%b", u_186.u_sys.cmt_pcb_val, pc, cyc, u_186.u_sys.isv_present_r); icu_n <= icu_n + 1; end
  end
  reg [8*256-1:0] flash_path, nvram_path;
  integer ff, n, i, clocks_max = 60000000, pcs_every = 0, tick_every = 0, cyc = 0;
  reg [7:0] fb [0:524287];
  reg [7:0] nb [0:511];
  integer dsp_seen = 0;
  always @(posedge clk) begin
    cyc <= cyc + 1;
    if (rst_n && glue_run && !dsp_seen) begin dsp_seen = 1; $display("[tb] DSP started (glue run) at clock %0d", cyc); end
    if (rst_n && pcs_every != 0 && cyc % pcs_every == 0) $display("[tb] clock %0d pc %05h", cyc, pc);
    if (rst_n && tick_every != 0 && cyc % tick_every == 0)
      $display("[tb] clock %0d pc %05h tick[12A]=%02h [3F2]=%04h req=%b msk=%h primsk=%0d isv=%b t0con=%04h t0cmpa=%04h t0cnt=%04h IF=%b icon12=%0d 14=%0d 16=%0d 18=%0d 1a=%0d 1c=%0d 1e=%0d isvval6=%0d", cyc, pc,
               wm[19'h95][7:0], wm[19'h1F9], u_186.u_sys.req_r, u_186.u_sys.msk_r, u_186.u_sys.primsk_r, u_186.u_sys.isv_present_r,
               u_186.u_sys.tmr_con[0], u_186.u_sys.tmr_cmpa[0], u_186.u_sys.tmr_cnt[0], u_186.u_core.ifl,
               u_186.u_sys.icon_12, u_186.u_sys.icon_14, u_186.u_sys.icon_16, u_186.u_sys.icon_18, u_186.u_sys.icon_1a, u_186.u_sys.icon_1c, u_186.u_sys.icon_1e, u_186.u_sys.isv_val_r[6]);
    if (rst_n && dte_tx_valid) $display("[tb] DTE byte %02h at clock %0d", dte_tx_byte, cyc);
  end

  initial begin
    void'($value$plusargs("clocks=%d", clocks_max));
    void'($value$plusargs("pcs=%d", pcs_every));
    void'($value$plusargs("ticks=%d", tick_every));
    if (!$value$plusargs("flash=%s", flash_path)) flash_path = "fw/SV25.flash.bin";
    if (!$value$plusargs("nvram=%s", nvram_path)) nvram_path = "fw/nvram.bin";
    ff = $fopen(flash_path, "rb"); if (ff == 0) begin $display("FAIL: flash"); $finish; end
    n = $fread(fb, ff); $fclose(ff);
    for (i = 0; i < 524288; i = i + 1) wm[i] = 16'hDEAD;
    for (i = 0; i < 262144; i = i + 1) wm[19'h40000 + i] = {fb[2*i+1], fb[2*i]};
    ff = $fopen(nvram_path, "rb"); if (ff == 0) begin $display("FAIL: nvram"); $finish; end
    n = $fread(nb, ff); $fclose(ff);
    repeat (10) @(posedge clk);
    for (i = 0; i < 256; i = i + 1) begin @(posedge clk); ee_en <= 1; ee_a <= i[7:0]; ee_d <= {nb[2*i+1], nb[2*i]}; @(posedge clk); ee_en <= 0; end
    repeat (10) @(posedge clk); rst_n = 1;
    wait (cyc >= clocks_max);
    $display("[tb] done at clock %0d pc %05h", cyc, pc);
    $finish;
  end
endmodule
