/* Self-checking test of i186_core's irq_taken_o: (1) with IF = 0 a pending interrupt is never reported as taken, even when the program reads the word at the vector's IVT slot
   (the old top-level acknowledge watched the bus for that read and the SV25 RAM test, which sweeps all memory with XCHG AX,(BX), triggered it for INT0 at address 0x30);
   (2) with IF = 1 exactly one irq_taken_o pulse per interrupt, and the ISR runs once. */
`default_nettype none
`timescale 1ns/1ps
module tb_i186_ack;
  logic clk = 0, rst_n = 0, irq_i = 0;
  logic bus_req, bus_wr, bus_w, bus_io, bus_ack;
  logic [19:0] bus_addr, pc_o, badop_pc_o;
  logic [15:0] bus_wdata, bus_rdata;
  logic [63:0] cycles_o;
  logic halted_o, st_badop_o, taken;
  integer ntaken = 0;
  always @(posedge clk) if (taken) ntaken <= ntaken + 1;
  logic [7:0] badop_o;
  logic [7:0] mem [0:1048575];
  integer waits = 0, wcnt = 0;

  i186_core dut (.clk(clk), .ce_i(1'b1), .rst_n(rst_n), .cyc_model_i(1'b1), .ud_trap_i(1'b1), .nmi_i(1'b0), .irq_i(irq_i), .irq_vec_i(8'h20), .irq_clear_i(1'b0), .irq_taken_o(taken),
    .bus_req(bus_req), .bus_addr(bus_addr), .bus_wr(bus_wr), .bus_w(bus_w), .bus_io(bus_io), .bus_wdata(bus_wdata), .bus_ack(bus_ack), .bus_rdata(bus_rdata),
    .cycles_o(cycles_o), .halted_o(halted_o), .st_badop_o(st_badop_o), .badop_pc_o(badop_pc_o), .badop_o(badop_o), .pc_o(pc_o));

  assign bus_ack = bus_req && (wcnt >= waits);
  assign bus_rdata = bus_io ? 16'h0000 : bus_w ? {mem[bus_addr + 20'd1], mem[bus_addr]} : {8'b0, mem[bus_addr]};
  always @(posedge clk) begin
    if (bus_req && !bus_ack) wcnt <= wcnt + 1; else wcnt <= 0;
    if (bus_req && bus_ack && bus_wr && !bus_io) begin
      mem[bus_addr] <= bus_wdata[7:0];
      if (bus_w) mem[bus_addr + 20'd1] <= bus_wdata[15:8];
    end
  end
  always #5 clk <= ~clk;

  integer scen = 0;
  task automatic load_prog;
    integer i;
    begin
      for (i = 0; i < 'h800; i = i + 1) mem[i] = 8'h00;
      mem['h80] = 8'h00; mem['h81] = 8'h06; mem['h82] = 8'h00; mem['h83] = 8'h00;                 /* vector 0x20 -> 0000:0600 */
      mem['h600] = 8'hFF; mem['h601] = 8'h06; mem['h602] = 8'h00; mem['h603] = 8'h03;              /* inc word [0x300] */
      mem['h604] = 8'hCF;                                                                          /* iret */
      if (scen == 0) begin
        mem['h400] = 8'hFA;                                                                        /* cli */
        mem['h401] = 8'hBC; mem['h402] = 8'h00; mem['h403] = 8'h02;                                /* mov sp,0x200 */
        mem['h404] = 8'hBB; mem['h405] = 8'h80; mem['h406] = 8'h00;                                /* mov bx,0x80 (the IVT slot of vector 0x20) */
        mem['h407] = 8'h8B; mem['h408] = 8'h07;                                                    /* mov ax,[bx] */
        mem['h409] = 8'hF4;                                                                        /* hlt */
      end else begin
        mem['h400] = 8'hFB;                                                                        /* sti */
        mem['h401] = 8'hBC; mem['h402] = 8'h00; mem['h403] = 8'h02;                                /* mov sp,0x200 */
        mem['h404] = 8'h90; mem['h405] = 8'h90; mem['h406] = 8'h90; mem['h407] = 8'h90;            /* nops */
        mem['h408] = 8'hF4;                                                                        /* hlt (woken by the interrupt) */
        mem['h409] = 8'hF4;
      end
      mem['hFFFF0] = 8'hEA; mem['hFFFF1] = 8'h00; mem['hFFFF2] = 8'h04; mem['hFFFF3] = 8'h00; mem['hFFFF4] = 8'h00;
    end
  endtask

  integer k, w, t, errors = 0, runs = 0;
  initial begin
    for (scen = 0; scen <= 1; scen = scen + 1) begin
      for (w = 0; w <= 2; w = w + 1) begin
        for (k = 4; k < 60; k = k + 7) begin
          waits = w; ntaken = 0;
          rst_n = 0; irq_i = 0; load_prog(); repeat (4) @(posedge clk); #1 rst_n = 1;
          for (t = 0; t < 1500; t = t + 1) begin
            @(posedge clk); #1;
            irq_i = (t >= k);                                   /* an edge at clock k, level kept */
          end
          runs = runs + 1;
          if (scen == 0 && ntaken != 0) begin errors = errors + 1; if (errors < 6) $display("FAIL scen0 waits %0d: %0d interrupts reported taken with IF=0", w, ntaken); end
          if (scen == 1 && (ntaken != 1 || {mem['h301], mem['h300]} !== 16'h0001)) begin errors = errors + 1; if (errors < 6) $display("FAIL scen1 waits %0d k %0d: taken pulses %0d, ISR runs %0d (state %0d ip %04h sp %04h halted %b ifl %b)", w, k, ntaken, {mem['h301], mem['h300]}, dut.state, dut.ip, dut.gpr[4], halted_o, dut.ifl); end
        end
      end
    end
    if (errors == 0) $display("PASS tb_i186_ack (%0d runs)", runs); else $display("FAIL tb_i186_ack: %0d errors", errors);
    $finish;
  end
  initial begin #400000000; $display("FAIL tb_i186_ack: timeout"); $finish; end
endmodule
