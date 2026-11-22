/* Self-checking test of i186_core: an interrupt arriving at every possible clock around `call f; f: xchg ax,di; ret` (the SV25 checksum loop's shape), with an ISR that is a single
   IRET, on a bus with 0..3 wait states. After every run the core must reach the HLT after the call with CS=0, SP=0x200, AX/DI exchanged: a RET that follows the IRET must be a
   near return. (A board run showed the RET after such an IRET loading the popped word into CS instead of IP.) */
`default_nettype none
`timescale 1ns/1ps
module tb_i186_intret;
  logic clk = 0, rst_n = 0, irq_i = 0;
  logic bus_req, bus_wr, bus_w, bus_io, bus_ack;
  logic [19:0] bus_addr, pc_o, badop_pc_o;
  logic [15:0] bus_wdata, bus_rdata;
  logic [63:0] cycles_o;
  logic halted_o, st_badop_o;
  logic [7:0] badop_o;
  logic [7:0] mem [0:1048575];
  integer waits = 0, wcnt = 0;

  i186_core dut (.clk(clk), .ce_i(1'b1), .rst_n(rst_n), .cyc_model_i(1'b1), .ud_trap_i(1'b1), .nmi_i(1'b0), .irq_i(irq_i), .irq_vec_i(8'h20), .irq_clear_i(1'b0),
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

  task automatic load_prog;
    integer i;
    begin
      for (i = 0; i < 'h800; i = i + 1) mem[i] = 8'h00;
      /* IVT vector 0x20 -> 0000:0600 */
      mem['h80] = 8'h00; mem['h81] = 8'h06; mem['h82] = 8'h00; mem['h83] = 8'h00;
      mem['h600] = 8'hCF;                                                    /* ISR: iret */
      mem['h400] = 8'hFB;                                                    /* sti */
      mem['h401] = 8'hBC; mem['h402] = 8'h00; mem['h403] = 8'h02;            /* mov sp,0x200 */
      mem['h404] = 8'hB8; mem['h405] = 8'h34; mem['h406] = 8'h12;            /* mov ax,0x1234 */
      mem['h407] = 8'hBF; mem['h408] = 8'h78; mem['h409] = 8'h56;            /* mov di,0x5678 */
      mem['h40A] = 8'hE8; mem['h40B] = 8'h13; mem['h40C] = 8'h00;            /* call 0x420 */
      mem['h40D] = 8'hF4;                                                    /* hlt */
      for (i = 'h40E; i < 'h430; i = i + 1) if (i != 'h420 && i != 'h421) mem[i] = 8'hF4;   /* more HLTs: a wake-up from the first one runs on */
      mem['h420] = 8'h97;                                                    /* xchg ax,di */
      mem['h421] = 8'hC3;                                                    /* ret */
      mem['h422] = 8'h52; mem['h423] = 8'h50;                                /* push dx; push ax (never executed) */
      mem['hFFFF0] = 8'hEA; mem['hFFFF1] = 8'h00; mem['hFFFF2] = 8'h04; mem['hFFFF3] = 8'h00; mem['hFFFF4] = 8'h00;   /* jmp far 0000:0400 */
    end
  endtask

  integer k, w, t, errors = 0, runs = 0, trw = -1, trk = -1;
  reg tr = 0;
  always @(posedge clk) if (tr && rst_n) $display("t=%0d state %0d step %0d opcode %02h class %0d ip %04h cs %04h sp %04h req %b addr %05h wr %b ack %b rd %04h fb %b", t, dut.state, dut.exec_step, dut.opcode, dut.instr_class, dut.ip, dut.sreg[1], dut.gpr[4], bus_req, bus_addr, bus_wr, bus_ack, bus_rdata, dut.fetch_first_byte);
  initial begin
    if ($value$plusargs("trw=%d", trw) && $value$plusargs("trk=%d", trk)) begin end
    for (w = 0; w <= 3; w = w + 1) begin
      for (k = 0; k < 160; k = k + 1) begin
        waits = w; tr = (w == trw && k == trk);
        rst_n = 0; irq_i = 0; load_prog(); repeat (4) @(posedge clk); #1 rst_n = 1;
        for (t = 0; t < 4000 && !halted_o; t = t + 1) begin
          @(posedge clk); #1;
          irq_i = (t == k);
        end
        runs = runs + 1;
        if (!halted_o || dut.sreg[1] !== 16'h0000 || dut.gpr[4] !== 16'h0200 || dut.gpr[0] !== 16'h5678 || dut.gpr[7] !== 16'h1234) begin
          errors = errors + 1;
          if (errors < 8) $display("FAIL waits %0d irq at clock %0d: halted %b CS %04h IP %04h SP %04h AX %04h DI %04h", w, k, halted_o, dut.sreg[1], dut.ip, dut.gpr[4], dut.gpr[0], dut.gpr[7]);
        end
      end
    end
    if (errors == 0) $display("PASS tb_i186_intret (%0d runs)", runs); else $display("FAIL tb_i186_intret: %0d of %0d runs wrong", errors, runs);
    $finish;
  end
  initial begin #400000000; $display("FAIL tb_i186_intret: timeout"); $finish; end
endmodule
