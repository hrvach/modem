/* Self-checking test of the C5x core's interrupt wake from IDLE: IMR enables INT2, the program executes IDLE, the testbench raises INT2 once. The handler (vector 0x0004) increments
   dm[0x61] and RETEs; the main line must resume after the IDLE (dm[0x62] = 1), the handler must have run exactly once (dm[0x61] = 1) and the IFR bit must be cleared.
   Before the fix the IDLE-wake path never cleared IFR, the interrupt re-fired forever (the SV25 DSP boot waits in IDLE six times and never got past the first). */
`default_nettype none
`timescale 1ns/1ps
module tb_c5x_idle;
  logic clk = 0, rst_n = 0, step = 1;
  logic [8:0] irq = 0;
  logic load_en = 0;
  logic [15:0] load_addr = 0, load_data = 0;
  logic [15:0] ifr;
  logic io_req;
  logic io_rd;
  logic [15:0] io_port, io_wdata;
  always #5 clk = ~clk;

  c5x_core #(.RESET_PC(16'h0100), .EXT_PMEM(1'b0)) dut (
    .clk(clk), .ce_i(1'b1), .rst_n(rst_n),
    .xm_rd_en_o(), .xm_raddr_o(), .xm_wr_en_o(), .xm_waddr_o(), .xm_wdata_o(), .xm_rdata_i(16'h0000),
    .step_i(step), .irq_i(irq), .bio_i(1'b0), .ivec_ind_i(144'h0), .ser_tick(1'b0), .ser_rx(16'h0), .xint_mode(1'b1),
    .io_req(io_req), .io_rd(io_rd), .io_port(io_port), .io_wdata(io_wdata), .io_rdata(16'h0000), .io_ack(1'b1),
    .load_en(load_en), .load_pmem(1'b1), .load_addr(load_addr), .load_data(load_data),
    .dbg_en(1'b0), .dbg_addr(16'h0), .dbg_rdata(), .dbg_done(),
    .dxr_wr(), .dxr_wdata(), .timer_exp_cnt_o(), .mem_wr_pulse(), .mem_wr_pmem(), .mem_wr_addr(), .mem_wr_data(),
    .instr_done(), .cycles_o(), .pc_o(), .op_o(), .acc_o(), .accb_o(), .preg_o(), .treg0_o(), .treg1_o(), .treg2_o(), .ar_cur_o(), .arp_o(), .st0_o(), .st1_o(), .pmst_o(),
    .rptc_o(), .brcr_o(), .pasr_o(), .paer_o(), .bmar_o(), .dbmr_o(), .indx_o(), .arcr_o(), .sp_o(), .stack_top_o(), .ar_all_o(), .stack_all_o(), .ifr_o(ifr), .imr_o(), .idle_o());

  task automatic put(input [15:0] a, input [15:0] d);
    begin @(negedge clk); load_en = 1; load_addr = a; load_data = d; @(negedge clk); load_en = 0; end
  endtask

  integer errors = 0;
  initial begin
    repeat (4) @(posedge clk);
    put(16'h0004, 16'h7980); put(16'h0005, 16'h0200);                                  /* INT2 vector: B 0x0200 */
    put(16'h0100, 16'hB902); put(16'h0101, 16'h8804); put(16'h0102, 16'hBE40);          /* LACK #2; SAMM IMR; EINT */
    put(16'h0103, 16'hBE22);                                                           /* IDLE */
    put(16'h0104, 16'hB901); put(16'h0105, 16'h8862);                                  /* LACK #1; SAMM 0x62 */
    put(16'h0106, 16'h7980); put(16'h0107, 16'h0106);                                  /* B $ */
    put(16'h0200, 16'h0861); put(16'h0201, 16'hB801); put(16'h0202, 16'h8861); put(16'h0203, 16'hBE3A);   /* LAMM 0x61; ADDK #1; SAMM 0x61; RETE */
    rst_n = 1;
    repeat (400) @(posedge clk);                                                       /* reach the IDLE */
    @(negedge clk); irq[1] = 1; @(negedge clk); irq[1] = 0;
    repeat (3000) @(posedge clk);
    if (dut.u_mem.dmem[16'h61] !== 16'h0001) begin errors = errors + 1; $display("FAIL handler ran %0d times (want 1)", dut.u_mem.dmem[16'h61]); end
    if (dut.u_mem.dmem[16'h62] !== 16'h0001) begin errors = errors + 1; $display("FAIL main line did not resume after IDLE (dm[0x62] = %h)", dut.u_mem.dmem[16'h62]); end
    if (ifr[1] !== 1'b0) begin errors = errors + 1; $display("FAIL IFR bit 1 still set (%h)", ifr); end
    if (errors == 0) $display("PASS tb_c5x_idle"); else $display("FAIL tb_c5x_idle: %0d errors", errors);
    $finish;
  end
endmodule
