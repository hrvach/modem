`default_nettype none
`timescale 1ns/1ps
module tb_pipe_dxr;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic [8:0] irq = 0;
  logic load_en = 0, ser_tick = 0;
  logic [15:0] load_addr = 0, load_data = 0;
  logic io_req, io_rd; logic [15:0] io_port, io_wdata, io_rdata; logic io_ack = 0;
  logic dxr_wr; logic [15:0] dxr_wdata; logic idle; logic [63:0] cycles; logic [15:0] pc, ifr, imr;
  logic [31:0] accw; logic mwp, mwpm; logic [15:0] mwa, mwd;
  always @(posedge clk) if (mwp && !mwpm && mwa == 16'h039e) $display("W39E data=%h cyc=%0d pc=%h", mwd, cycles, pc);
  integer hw_cnt [0:15]; integer hq; initial for (hq=0; hq<16; hq=hq+1) hw_cnt[hq]=0;
  logic hq_prev = 0;
  always @(posedge clk) begin hq_prev <= io_req; if (io_req && !hq_prev && !io_rd && io_port >= 16'hFF50 && io_port <= 16'hFF5F && nclk < 40000) begin hw_cnt[io_port[3:0]] <= hw_cnt[io_port[3:0]] + 1; end end
  always @(posedge clk) if (nclk == 40000) $display("HW write counts FF50..FF5F: %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d", hw_cnt[0],hw_cnt[1],hw_cnt[2],hw_cnt[3],hw_cnt[4],hw_cnt[5],hw_cnt[6],hw_cnt[7],hw_cnt[8],hw_cnt[9],hw_cnt[10],hw_cnt[11],hw_cnt[12],hw_cnt[13],hw_cnt[14],hw_cnt[15]);
  logic [31:0] mtime; logic aic_tick, aic_int3, aic_step, aic_dacv, aic_rxn, aic_ft; logic [15:0] aic_rx, mclk_n = 0, aic_cps; logic signed [15:0] aic_dac;
  aic u_aic (.clk(clk), .rst_n(rst_n), .ce_i(1'b1), .cycles_i(mtime), .parked_i(1'b1), .idle_i(1'b1), .run_i(rst_n), .step_o(aic_step),
             .ser_tick_o(aic_tick), .ser_rx_o(aic_rx), .int3_o(aic_int3), .dxr_wr_i(dxr_wr), .dxr_wdata_i(dxr_wdata), .mclk_n_i(mclk_n),
             .dac_valid_o(aic_dacv), .dac_sample_o(aic_dac), .rx_next_o(aic_rxn), .rx_sample_i(16'sd0), .frame_tick_o(aic_ft), .rate_cps_o(aic_cps));
  always @(posedge clk) if (io_req && !io_rd && io_port[7:0] == 8'h6B) mclk_n <= io_wdata;
  logic [2:0] arpw; logic [127:0] ar_all_w; logic [63:0] texp; logic [2:0] spw; logic [15:0] stt; logic idn; logic [15:0] opw;
  logic [15:0] hp [0:31]; logic [15:0] ho [0:31]; logic [63:0] hc [0:31]; integer hi = 0; logic seen_hi = 0; logic dumped = 0; integer dk;
  always @(posedge clk) if (idn) begin
    hp[hi[4:0]] <= pc; ho[hi[4:0]] <= opw; hc[hi[4:0]] <= cycles; hi <= hi + 1;
    if (pc >= 16'h8000) seen_hi <= 1;
    if (seen_hi && (pc < 16'h0040 || pc >= 16'hFF00) && !dumped) begin
      dumped <= 1; $display("DERAIL at cycles %0d, last retires:", cycles);
      for (dk = 0; dk < 32; dk = dk + 1) $display("  H pc=%h op=%h cyc=%0d", hp[(hi+dk) % 32], ho[(hi+dk) % 32], hc[(hi+dk) % 32]);
    end
  end
  c5x_core #(.RESET_PC(16'h8000)) dut (
    .clk(clk), .rst_n(rst_n), .step_i(1'b1), .irq_i({6'd0, aic_int3, 1'b0, 1'b0}), .bio_i(1'b0),
    .ivec_ind_i({16'h0068,16'h0067,16'h0066,16'h0065,16'h0064,16'h0063,16'h0062,16'h0061,16'h0060}),
    .ser_tick(aic_tick), .ser_rx(aic_rx), .xint_mode(1'b1),
    .io_req(io_req), .io_rd(io_rd), .io_port(io_port), .io_wdata(io_wdata), .io_rdata(io_rdata), .io_ack(io_ack),
    .load_en(load_en), .load_pmem(1'b1), .load_addr(load_addr), .load_data(load_data),
    .dbg_en(1'b0), .dbg_addr(16'h0), .dbg_rdata(), .dbg_done(),
    .dxr_wr(dxr_wr), .dxr_wdata(dxr_wdata), .timer_exp_cnt_o(texp),
    .mem_wr_pulse(mwp), .mem_wr_pmem(mwpm), .mem_wr_addr(mwa), .mem_wr_data(mwd),
    .mtime_o(mtime), .instr_done(idn), .cycles_o(cycles), .pc_o(pc), .op_o(opw), .acc_o(accw), .accb_o(), .preg_o(), .treg0_o(), .treg1_o(), .treg2_o(), .ar_cur_o(), .arp_o(arpw),
    .st0_o(), .st1_o(), .pmst_o(), .rptc_o(), .brcr_o(), .pasr_o(), .paer_o(), .bmar_o(), .dbmr_o(), .indx_o(), .arcr_o(), .sp_o(spw), .stack_top_o(stt),
    .ar_all_o(ar_all_w), .stack_all_o(), .ifr_o(ifr), .imr_o(imr), .idle_o(idle), .halted_o());
  always @(posedge clk) if (cycles > 1296195 && cycles < 1296216 && idn) $display("RETN pc=%h op=%h cyc=%0d acc=%h", pc, opw, cycles, accw);
  always @(posedge clk) if (mwp && cycles > 1296195 && cycles < 1296216) $display("WRALL pm=%b addr=%h data=%h cyc=%0d", mwpm, mwa, mwd, cycles);
  always @(posedge clk) if (cycles >= 1304500 && cycles <= 1304501) $display("PM23F0: %h %h %h %h %h", dut.u_mem.dmem[16'h0bf0], dut.u_mem.dmem[16'h0bf1], dut.u_mem.dmem[16'h0bf2], dut.u_mem.dmem[16'h0bf3], dut.u_mem.dmem[16'h0bf4]);
  always @(posedge clk) if (cycles >= 25310 && cycles <= 25316) $display("CK n=%0d cyc=%0d E.valid=%b E.op=%h ret=%b R.req=%b R.addr=%h R.data=%h acc=%h AR1=%h", nclk, cycles, dut.u_ctrl.re_i.valid, dut.u_ctrl.re_i.op, dut.u_ctrl.e_retire_w, dut.u_ctrl.r_req_o, dut.u_ctrl.r_addr_o, dut.u_ctrl.r_data_i, dut.u_alu.acc_q, ar_all_w[31:16]);
  always @(posedge clk) if (nclk >= 102115 && nclk <= 102120) $display("H1 n=%0d fd.valid=%b src_ar=%0d use=%b R.valid=%b R.wr_ar=%b/%0d E.valid=%b E.wr_ar=%b/%0d E.mmrdyn=%b/%h h1=%b dhold=%b arp=%0d", nclk, dut.u_ctrl.fd_i.valid, dut.u_ctrl.d_src_ar_id_i, dut.u_ctrl.d_src_ar_use_i, dut.u_ctrl.dr_i.valid, dut.u_ctrl.dr_i.wrt.wr_ar_valid, dut.u_ctrl.dr_i.wrt.wr_ar_id, dut.u_ctrl.re_i.valid, dut.u_ctrl.re_i.wrt.wr_ar_valid, dut.u_ctrl.re_i.wrt.wr_ar_id, dut.u_ctrl.re_i.wrt.wr_mmr_dyn_valid, dut.u_ctrl.re_i.wrt.wr_mmr_dyn_id, dut.u_ctrl.d_h1_w, dut.u_ctrl.d_hold_w, arpw);
  always @(posedge clk) if (mwp && ((!mwpm && mwa == 16'h0bda) || (mwpm && mwa == 16'h23da))) $display("WBDA pm=%b data=%h cyc=%0d pc=%h", mwpm, mwd, cycles, pc);
  logic [15:0] image [0:32767]; logic [15:0] romimg [0:8191];
  integer n, nclk = 0, ndxr = 0, nrd = 0, nframe = 0, period = 5600;
  logic [31:0] hx;
  assign hx = ({16'd0, io_port} * 32'h9E37) ^ ((nrd >> 1) * 32'h1357) ^ 32'h5A5A;
  assign io_rdata = (io_port[7:0] == 8'h57) ? 16'h0006 : 16'h0000;
  logic rq_q = 0;
  always @(posedge clk) begin rq_q <= io_req; io_ack <= io_req; if (io_req && !rq_q && io_rd) nrd <= nrd + 1; end
  initial begin
    $readmemh("../tb/smoke/rom8k.hex", romimg); $readmemh("../tb/smoke/dsp_base.hex", image);
    if ($value$plusargs("period=%d", period)) ;
    repeat (4) @(posedge clk);
    for (n = 0; n < 8192; n = n + 1) begin @(negedge clk); load_en = 1; load_addr = n[15:0]; load_data = romimg[n]; end
    for (n = 0; n < 16384; n = n + 1) begin @(negedge clk); load_en = 1; load_addr = 16'h8000 + n[15:0]; load_data = image[n]; end
    @(negedge clk); load_en = 0; rst_n = 1;
  end
  always @(posedge clk) if (rst_n) begin
    nclk <= nclk + 1;
    if (dxr_wr) ndxr <= ndxr + 1;
    if (aic_int3) nframe <= nframe + 1;
    if (nclk % 100000 == 99999) $display("clk %0d frames %0d dxr %0d texp %0d pc %h idle %b ifr %h imr %h cyc %0d", nclk, nframe, ndxr, texp, pc, idle, ifr, imr, cycles);
    if (nclk == 8000000) $finish;
  end
endmodule
