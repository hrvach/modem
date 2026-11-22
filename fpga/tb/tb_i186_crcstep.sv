/* i186_core vs a Python model on the SV25 CRC step routine (RAM image 0x03E7..0x0411, called once per flash byte by the boot checksum): vectors "crc_in byte crc_out" from +vec=. */
`default_nettype none
`timescale 1ns/1ps
module tb_i186_crcstep;
  logic clk = 0, rst_n = 0;
  logic bus_req, bus_wr, bus_w, bus_io, bus_ack;
  logic [19:0] bus_addr, pc_o, badop_pc_o;
  logic [15:0] bus_wdata, bus_rdata;
  logic [63:0] cycles_o;
  logic halted_o, st_badop_o;
  logic [7:0] badop_o;
  logic [7:0] mem [0:1048575];
  i186_core dut (.clk(clk), .ce_i(1'b1), .rst_n(rst_n), .cyc_model_i(1'b1), .ud_trap_i(1'b1), .nmi_i(1'b0), .irq_i(1'b0), .irq_vec_i(8'h00), .irq_clear_i(1'b0),
    .bus_req(bus_req), .bus_addr(bus_addr), .bus_wr(bus_wr), .bus_w(bus_w), .bus_io(bus_io), .bus_wdata(bus_wdata), .bus_ack(bus_ack), .bus_rdata(bus_rdata),
    .cycles_o(cycles_o), .halted_o(halted_o), .st_badop_o(st_badop_o), .badop_pc_o(badop_pc_o), .badop_o(badop_o), .pc_o(pc_o));
  assign bus_ack = bus_req;
  assign bus_rdata = bus_io ? 16'h0000 : bus_w ? {mem[bus_addr + 20'd1], mem[bus_addr]} : {8'b0, mem[bus_addr]};
  always @(posedge clk) if (bus_req && bus_wr && !bus_io) begin
    mem[bus_addr] <= bus_wdata[7:0];
    if (bus_w) mem[bus_addr + 20'd1] <= bus_wdata[15:8];
  end
  always #5 clk <= ~clk;
  always @(posedge clk) if (rst_n && dut.state == 5'd0 && dut.fetch_first_byte && bus_req && bus_ack && $test$plusargs("trace")) $display("TRACE ip=%04h op=%02h ax=%04h cx=%04h dx=%04h bx=%04h di=%04h", dut.ip, bus_rdata[7:0], dut.gpr[0], dut.gpr[1], dut.gpr[2], dut.gpr[3], dut.gpr[7]);
  reg [8*256-1:0] vec_path;
  integer fv, i, t, nv = 0, errors = 0, r;
  reg [15:0] cin, cout;
  reg [7:0] b;
  reg [7:0] code [0:63];
  initial begin
    if (!$value$plusargs("vec=%s", vec_path)) vec_path = "../tb/vectors/crcstep.txt";
    fv = $fopen(vec_path, "r"); if (fv == 0) begin $display("FAIL: no vectors"); $finish; end
    /* the routine, byte for byte from the firmware's RAM image */
    code[0]=8'h8b; code[1]=8'hf8; code[2]=8'h2e; code[3]=8'h8b; code[4]=8'h16; code[5]=8'h04; code[6]=8'h01; code[7]=8'h32; code[8]=8'hc2; code[9]=8'h8a; code[10]=8'hd0;
    code[11]=8'hb4; code[12]=8'h00; code[13]=8'hc1; code[14]=8'he0; code[15]=8'h04; code[16]=8'h33; code[17]=8'hd0; code[18]=8'hd1; code[19]=8'he8; code[20]=8'h86; code[21]=8'hf2;
    code[22]=8'h33; code[23]=8'hd0; code[24]=8'hc1; code[25]=8'he0; code[26]=8'h04; code[27]=8'h80; code[28]=8'he4; code[29]=8'h07; code[30]=8'h33; code[31]=8'hd0; code[32]=8'hd1; code[33]=8'he0;
    code[34]=8'h32; code[35]=8'hd4; code[36]=8'h2e; code[37]=8'h89; code[38]=8'h16; code[39]=8'h04; code[40]=8'h01; code[41]=8'h97; code[42]=8'hc3;
    while (!$feof(fv)) begin
      r = $fscanf(fv, "%h %h %h\n", cin, b, cout);
      if (r == 3) begin
        for (i = 0; i < 'h3000; i = i + 1) mem[i] = 8'h00;
        for (i = 0; i < 43; i = i + 1) mem['h3E7 + i] = code[i];
        mem['h104] = cin[7:0]; mem['h105] = cin[15:8];
        mem['h2000] = 8'hBC; mem['h2001] = 8'h00; mem['h2002] = 8'h70;                  /* mov sp,0x7000 */
        mem['h2003] = 8'hB0; mem['h2004] = b;                                           /* mov al,byte */
        mem['h2005] = 8'hE8; mem['h2006] = 8'hDF; mem['h2007] = 8'hE3;                  /* call 0x3E7 (0x2008 + 0xE3DF = 0x3E7) */
        mem['h2008] = 8'hF4;
        mem['hFFFF0] = 8'hEA; mem['hFFFF1] = 8'h00; mem['hFFFF2] = 8'h20; mem['hFFFF3] = 8'h00; mem['hFFFF4] = 8'h00;
        rst_n = 0; repeat (4) @(posedge clk); #1 rst_n = 1;
        for (t = 0; t < 5000 && !halted_o; t = t + 1) @(posedge clk);
        nv = nv + 1;
        if ({mem['h105], mem['h104]} !== cout) begin
          errors = errors + 1;
          if (errors < 6) $display("MISMATCH crc_in %04h byte %02h: RTL %04h want %04h", cin, b, {mem['h105], mem['h104]}, cout);
        end
      end
    end
    if (errors == 0) $display("PASS tb_i186_crcstep (%0d vectors)", nv); else $display("FAIL tb_i186_crcstep: %0d of %0d", errors, nv);
    $finish;
  end
endmodule
