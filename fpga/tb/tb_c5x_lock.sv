/* DSP core benchmark / lock-step trace: runs dsp_base.bin (the SV25 DSP image, loaded at 0x8000) on the bare core with an interrupt every INT_EVERY retired instructions and
   pseudo-random I/O read data; prints clocks per model cycle at the end and, with +trace=<n>, one line of architectural state per retired instruction (the golden trace the faster core
   is compared with). Build: tests/Makefile t_c5x_bench. */
`default_nettype none
`timescale 1ns/1ps
module tb_c5x_lock;
  logic clk = 0, rst_n = 0;
  logic [8:0] irq = 0;
  logic load_en = 0, ser_tick = 0;
  logic [15:0] load_addr = 0, load_data = 0;
  logic io_req, io_rd;
  logic [15:0] io_port, io_wdata, io_rdata;
  logic instr_done, idle;
  logic [63:0] cycles;
  logic [15:0] pc, op, st0, st1, pmst, ar_cur, sp;
  logic [31:0] acc, accb;
  logic [2:0] arp;
  logic [15:0] ifr;
  always #5 clk = ~clk;

  c5x_core #(.RESET_PC(16'h8000), .EXT_PMEM(1'b0)) dut (
    .clk(clk), .ce_i(1'b1), .rst_n(rst_n),
    .xm_rd_en_o(), .xm_raddr_o(), .xm_wr_en_o(), .xm_waddr_o(), .xm_wdata_o(), .xm_rdata_i(16'h0000),
    .step_i(1'b1), .irq_i(irq), .bio_i(1'b0), .ivec_ind_i({16'h0068, 16'h0067, 16'h0066, 16'h0065, 16'h0064, 16'h0063, 16'h0062, 16'h0061, 16'h0060}), .ser_tick(ser_tick), .ser_rx(16'h0123), .xint_mode(1'b1),
    .io_req(io_req), .io_rd(io_rd), .io_port(io_port), .io_wdata(io_wdata), .io_rdata(io_rdata), .io_ack(io_ack_w),
    .load_en(load_en), .load_pmem(1'b1), .load_addr(load_addr), .load_data(load_data),
    .dbg_en(1'b0), .dbg_addr(16'h0), .dbg_rdata(), .dbg_done(),
    .dxr_wr(), .dxr_wdata(), .timer_exp_cnt_o(), .mem_wr_pulse(mwp), .mem_wr_pmem(mwpm), .mem_wr_addr(mwa), .mem_wr_data(mwd),
    .instr_done(instr_done), .cycles_o(cycles), .pc_o(pc), .op_o(op), .acc_o(acc), .accb_o(accb), .preg_o(), .treg0_o(), .treg1_o(), .treg2_o(), .ar_cur_o(ar_cur), .arp_o(arp), .st0_o(st0), .st1_o(st1), .pmst_o(pmst),
    .rptc_o(), .brcr_o(), .pasr_o(), .paer_o(), .bmar_o(), .dbmr_o(), .indx_o(), .arcr_o(), .sp_o(sp), .stack_top_o(), .ar_all_o(ar_all), .stack_all_o(), .ifr_o(ifr), .imr_o(imr_w), .idle_o(idle));

  logic mwp, mwpm; logic [15:0] mwa, mwd; logic [15:0] shadow [0:255]; integer qi; initial for (qi=0; qi<256; qi=qi+1) shadow[qi]=0;
  always @(posedge clk) if (mwp && !mwpm && trace != 0 && mwa >= 16'h60 && mwa < 16'h100) begin if (shadow[mwa[7:0]] != mwd) $display("D %h %h", mwa, mwd); shadow[mwa[7:0]] <= mwd; end
  logic [15:0] imr_w; integer tdbg = 0; always @(posedge clk) if (rst_n && trace != 0 && cycles >= 18060 && cycles < 18700 && (nclk % 8 == 0) && tdbg < 80) begin tdbg <= tdbg + 1; $display("TD cyc=%0d tim=%h prd=%h tss=%b psc=%h tddr=%h ifr=%h idle=%b state=%0d", cycles, dut.u_mem.tim_q, dut.u_mem.prd_q, dut.u_mem.tss_q, dut.u_mem.psc_q, dut.u_mem.tcr_tddr_q, ifr, idle, dut.u_ctrl.state_q); end
  logic [127:0] ar_all; logic [1:0] pend = 0; integer pn; logic [31:0] nxt = 3000; logic [63:0] cycp; logic [15:0] timp; logic idle_q = 0; integer since = 0; logic [15:0] pcp;
  logic [15:0] image [0:65535]; logic [15:0] romimg [0:8191];
  integer sth [0:31];
  integer si;
  logic [15:0] ifr_prev;
  integer ph [0:3];
  integer rph [0:15];
  integer nint = 0;
  initial begin for (si=0; si<4; si=si+1) ph[si]=0; for (si=0; si<16; si=si+1) rph[si]=0; end
  integer n, ninstr = 0, nclk = 0, idleclk = 0, trace = 0, every = 400, maxclk = 3000000;
  logic [31:0] lfsr = 32'hACE1ACE1;
  integer nrd = 0; logic io_rq_q = 0; always @(posedge clk) begin io_rq_q <= io_req; if (io_req && io_rd && !io_rq_q) begin nrd <= nrd + 1; if (trace != 0) $display("R %h", io_port); end end
  logic [31:0] hx; assign hx = ({16'd0,io_port} * 32'h9E37) ^ (((nrd-1)>>1) * 32'h1357) ^ 32'h5A5A; assign io_rdata = hx[15:0];
  /* +iod=N: slow-acknowledge I/O model like the DSP clock-domain crossing (request seen once, answered N clocks later, ack held until io_req drops); counts requests that start with no idle gap */
  integer iod = 0, b2b = 0, nio = 0, gapclk = 0;
  logic io_seen = 0, io_busy = 0, io_ack_q = 0;
  integer iocnt = 0;
  logic io_ack_w;
  assign io_ack_w = (iod == 0) ? 1'b1 : io_ack_q;
  always @(posedge clk) if (iod != 0) begin
    if (!io_req) begin io_seen <= 0; io_busy <= 0; io_ack_q <= 0; end
    else if (!io_seen) begin
      io_seen <= 1; io_busy <= 1; iocnt <= 0; nio <= nio + 1;
      if (io_ack_q) b2b <= b2b + 1;
    end else if (io_busy) begin
      iocnt <= iocnt + 1;
      if (iocnt + 1 >= iod) begin io_ack_q <= 1; io_busy <= 0; end
    end
  end
  always @(posedge clk) lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
  initial begin
    if ($value$plusargs("trace=%d", trace)) ;
    if ($value$plusargs("every=%d", every)) ;
    if ($value$plusargs("iod=%d", iod)) ;
    if ($value$plusargs("clocks=%d", maxclk)) ;
    for (si = 0; si < 32; si = si + 1) sth[si] = 0;
    $readmemh("../tb/smoke/dsp_base.hex", image);
    repeat (4) @(posedge clk);
    $readmemh("../tb/smoke/rom8k.hex", romimg);
    for (n = 0; n < 8192; n = n + 1) begin @(negedge clk); load_en = 1; load_addr = n[15:0]; load_data = romimg[n]; end
    for (n = 0; n < 16384; n = n + 1) begin @(negedge clk); load_en = 1; load_addr = 16'h8000 + n[15:0]; load_data = image[n]; end
    @(negedge clk); load_en = 0;
    rst_n = 1;
  end
  always @(posedge clk) if (rst_n) begin
    nclk <= nclk + 1;
    if (idle) idleclk <= idleclk + 1;
    sth[dut.u_ctrl.state_q] <= sth[dut.u_ctrl.state_q] + 1;
    if (dut.u_ctrl.state_q == 12) begin ph[dut.u_ctrl.int_ph_q] <= ph[dut.u_ctrl.int_ph_q] + 1; if (dut.u_ctrl.int_ph_q == 0) begin nint <= nint + 1; if (nint > 100 && nint < 112) $display("ENTRY n=%0d idx=%0d ifr=%h imr=%h pc=%h ind=%h", nint, dut.u_ctrl.int_idx_q, dut.ifr_o, dut.imr_o, dut.u_ctrl.pc_q, dut.u_ctrl.int_ind_addr_w); end end
    if (nint > 100 && nint < 104 && (dut.u_ctrl.irq_ack_o != 0 || dut.ifr_o != ifr_prev)) $display("clk %0d st=%0d ack=%h ifr=%h irq_set=%h", nclk, dut.u_ctrl.state_q, dut.u_ctrl.irq_ack_o, dut.ifr_o, dut.irq_set);
    ifr_prev <= dut.ifr_o;
    if (dut.u_ctrl.state_q == 16) rph[dut.u_ctrl.rst_ph_q] <= rph[dut.u_ctrl.rst_ph_q] + 1;
    irq <= 0; ser_tick <= 0; if ($signed(cycles[31:0] - nxt) >= 0) begin nxt <= nxt + 3000; irq[2] <= 1; ser_tick <= 1; end
    if (pend != 0) begin pend <= pend - 1; if (pend == 1 && trace != 0) $display("T %0d pc=%h acc=%h accb=%h st0=%h st1=%h sp=%h ar=%h/%h/%h/%h/%h/%h/%h/%h ifr=%h imr=%h cyc=%0d tim=%h", pn, pcp, acc, accb, {arp,st0[12:0]}, st1, sp, ar_all[15:0], ar_all[31:16], ar_all[47:32], ar_all[63:48], ar_all[79:64], ar_all[95:80], ar_all[111:96], ar_all[127:112], ifr, imr_w, cycp, timp); end
    if (instr_done) begin
      ninstr <= ninstr + 1;
      pend <= 2'd1; pn <= ninstr; pcp <= pc; cycp <= cycles; timp <= dut.u_mem.tim_q;
      
    end
    if (nclk == maxclk) begin
      $display("BENCH clocks=%0d instr=%0d model_cycles=%0d idle_clocks=%0d  clk/cycle=%0d.%02d clk/instr=%0d.%02d", nclk, ninstr, cycles, idleclk,
               nclk / (cycles == 0 ? 1 : cycles), (nclk * 100 / (cycles == 0 ? 1 : cycles)) % 100, nclk / (ninstr == 0 ? 1 : ninstr), (nclk * 100 / (ninstr == 0 ? 1 : ninstr)) % 100);
      for (si = 0; si < 17; si = si + 1) if (sth[si] != 0) $display("STATE %0d clocks %0d", si, sth[si]);
      $display("IO requests %0d back-to-back %0d", nio, b2b);
      $display("INTPH %0d %0d %0d %0d  entries(ph0 clocks)=%0d", ph[0], ph[1], ph[2], ph[3], nint);
      for (si = 0; si < 10; si = si + 1) $display("RESTPH %0d clocks %0d", si, rph[si]);
      $finish;
    end
  end
endmodule
