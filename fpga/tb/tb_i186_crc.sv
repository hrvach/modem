/* Runs the real SV25 boot-block checksum routine (RAM image 0x0FEB: the CRC loop over flash 0xC0000..0xF7FFF + the compare with the word at F000:7FFE) on i186_core with
   the flash image given by +flash= (local firmware, not part of `make test`). With the boot CRC patched into the image (see tools/patch_boot_crc.py) the routine must return
   with CF clear and the running CRC [0x104] = 0x1735; with the unpatched image (FFFF in the slot) it must return CF set. +expect_ok=0|1. */
`default_nettype none
`timescale 1ns/1ps
module tb_i186_crc;
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
  always @(posedge clk) if (bus_req && bus_wr && !bus_io && (bus_addr < 20'h80000)) begin
    mem[bus_addr] <= bus_wdata[7:0];
    if (bus_w) mem[bus_addr + 20'd1] <= bus_wdata[15:8];
  end
  always #5 clk <= ~clk;

  reg [8*256-1:0] flash_path;
  integer ff, n, i, expect_ok = 1, t;
  reg [7:0] fl [0:524287];
  initial begin
    if (!$value$plusargs("flash=%s", flash_path)) flash_path = "fw/SV25.flash.bin";
    void'($value$plusargs("expect_ok=%d", expect_ok));
    ff = $fopen(flash_path, "rb"); if (ff == 0) begin $display("FAIL: cannot open %0s", flash_path); $finish; end
    n = $fread(fl, ff); $fclose(ff);
    for (i = 0; i < 1048576; i = i + 1) mem[i] = 8'h00;
    for (i = 0; i < 524288; i = i + 1) mem[20'h80000 + i] = fl[i];
    for (i = 0; i < 20'h1B14; i = i + 1) mem[i] = fl[20'h7C000 + i];             /* the RAM image the firmware copies to 0 */
    mem['h126] = 8'h02;                                                         /* skip the 0x80000..0xBFFFF phase */
    mem['h124] = 8'h00;
    mem['h2000] = 8'hBC; mem['h2001] = 8'h00; mem['h2002] = 8'h70;              /* mov sp,0x7000 */
    mem['h2003] = 8'hE8; mem['h2004] = 8'hE5; mem['h2005] = 8'hEF;              /* call 0x0FEB */
    mem['h2006] = 8'hF4;                                                        /* hlt */
    mem['hFFFF0] = 8'hEA; mem['hFFFF1] = 8'h00; mem['hFFFF2] = 8'h20; mem['hFFFF3] = 8'h00; mem['hFFFF4] = 8'h00;
    repeat (4) @(posedge clk); #1 rst_n = 1;
    for (t = 0; t < 200000000 && !halted_o; t = t + 1) @(posedge clk);
    $display("halted %b after %0d clocks: CF %b CRC [0x104] %04h", halted_o, t, dut.cf, {mem['h105], mem['h104]});
    if (halted_o && dut.cf == (expect_ok ? 1'b0 : 1'b1) && (!expect_ok || {mem['h105], mem['h104]} == 16'h1735)) $display("PASS tb_i186_crc");
    else $display("FAIL tb_i186_crc");
    $finish;
  end
endmodule
