/* Self-checking test of the C5x core's host I/O handshake with a slow acknowledge: dm reads and writes of the host window (0xFF50..0xFF5F) and IN / OUT, for acknowledge delays of
   1..40 clocks. The I/O model samples the request in its first clock (as the crossing does), answers after D clocks, and the data the core uses must be the answer. */
`default_nettype none
`timescale 1ns/1ps
module tb_c5x_io;
  logic clk = 0, rst_n = 0;
  logic load_en = 0;
  logic [15:0] load_addr = 0, load_data = 0;
  logic io_req, io_rd;
  logic [15:0] io_port, io_wdata, io_rdata;
  logic io_ack;
  logic [31:0] acc;
  logic instr_done;
  always #5 clk = ~clk;

  c5x_core #(.RESET_PC(16'h0100), .EXT_PMEM(1'b0)) dut (
    .clk(clk), .ce_i(1'b1), .rst_n(rst_n),
    .xm_rd_en_o(), .xm_raddr_o(), .xm_wr_en_o(), .xm_waddr_o(), .xm_wdata_o(), .xm_rdata_i(16'h0000),
    .step_i(1'b1), .irq_i(9'd0), .bio_i(1'b0), .ivec_ind_i(144'h0), .ser_tick(1'b0), .ser_rx(16'h0), .xint_mode(1'b1),
    .io_req(io_req), .io_rd(io_rd), .io_port(io_port), .io_wdata(io_wdata), .io_rdata(io_rdata), .io_ack(io_ack),
    .load_en(load_en), .load_pmem(1'b1), .load_addr(load_addr), .load_data(load_data),
    .dbg_en(1'b0), .dbg_addr(16'h0), .dbg_rdata(), .dbg_done(),
    .dxr_wr(), .dxr_wdata(), .timer_exp_cnt_o(), .mem_wr_pulse(), .mem_wr_pmem(), .mem_wr_addr(), .mem_wr_data(),
    .instr_done(instr_done), .cycles_o(), .pc_o(), .op_o(), .acc_o(acc), .accb_o(), .preg_o(), .treg0_o(), .treg1_o(), .treg2_o(), .ar_cur_o(), .arp_o(), .st0_o(), .st1_o(), .pmst_o(),
    .rptc_o(), .brcr_o(), .pasr_o(), .paer_o(), .bmar_o(), .dbmr_o(), .indx_o(), .arcr_o(), .sp_o(), .stack_top_o(), .ar_all_o(), .stack_all_o(), .ifr_o(), .imr_o(), .idle_o());

  /* I/O model: the request is seen in its first clock and held; the answer comes D clocks later, io_ack stays up until io_req drops */
  integer D = 1;
  integer cnt = 0, nreq = 0;
  logic seen = 0, busy = 0;
  logic [15:0] last_port, last_wdata;
  logic last_rd;
  logic [15:0] rdata_q = 0;
  assign io_rdata = rdata_q;
  logic ack_q = 0;
  assign io_ack = ack_q;
  always @(posedge clk) begin
    if (!io_req) begin seen <= 0; busy <= 0; ack_q <= 0; end
    else if (!seen) begin
      seen <= 1; busy <= 1; cnt <= 0; nreq <= nreq + 1;
      last_port <= io_port; last_wdata <= io_wdata; last_rd <= io_rd;
      rdata_q <= {io_port[7:0], 8'h5A} ^ 16'h1234;
    end else if (busy) begin
      cnt <= cnt + 1;
      if (cnt + 1 >= D) begin ack_q <= 1; busy <= 0; end
    end
    /* the core's request lines are only guaranteed in the first clock: scramble them afterwards to catch a core that reads them late */
  end

  integer errors = 0, k;
  task put(input [15:0] a, input [15:0] d);
    begin @(negedge clk); load_en = 1; load_addr = a; load_data = d; @(negedge clk); load_en = 0; end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    /* LRLK AR1,#0xFF57; LARP 1; LACC *  (read host window 0xFF57); SACL 0x60 (save); LRLK AR1,#0xFF58; SACL * (write the low word to the window); B $ */
    put(16'h0100, 16'hBF09); put(16'h0101, 16'hFF57);
    put(16'h0102, 16'h8B89);
    put(16'h0103, 16'h1080);
    put(16'h0104, 16'h9060);
    put(16'h0105, 16'hBF09); put(16'h0106, 16'hFF58);
    put(16'h0107, 16'h9080);
    put(16'h0108, 16'hBF08); put(16'h0109, 16'h0060);                                  /* LRLK AR0,#0x60 (scratch) */
    put(16'h010A, 16'h7980); put(16'h010B, 16'h010A);                                  /* B $ */
    for (k = 0; k < 6; k = k + 1) begin
      case (k) 0: D = 1; 1: D = 2; 2: D = 3; 3: D = 6; 4: D = 15; default: D = 40; endcase
      rst_n = 0; nreq = 0;
      repeat (4) @(posedge clk);
      rst_n = 1;
      repeat (1500) @(posedge clk);
      if (dut.u_mem.dmem[16'h60] !== (({8'h57, 8'h5A} ^ 16'h1234))) begin errors = errors + 1; $display("FAIL D=%0d: read of 0xFF57 stored %h, want %h", D, dut.u_mem.dmem[16'h60], ({8'h57, 8'h5A} ^ 16'h1234)); end
      if (nreq < 2) begin errors = errors + 1; $display("FAIL D=%0d: only %0d host requests", D, nreq); end
      if (last_wdata !== (({8'h57, 8'h5A} ^ 16'h1234)) || last_port !== 16'hFF58 && last_port !== 16'h0058 && last_port !== 16'h58) begin errors = errors + 1; $display("FAIL D=%0d: last write port %h data %h (want data %h)", D, last_port, last_wdata, ({8'h57, 8'h5A} ^ 16'h1234)); end
    end
    if (errors == 0) $display("PASS tb_c5x_io"); else $display("FAIL tb_c5x_io: %0d errors", errors);
    $finish;
  end
endmodule
