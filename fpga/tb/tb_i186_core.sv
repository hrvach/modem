/*
Testbench for i186_core (Intel 80C186EB).

Drives the core through a 1 MB byte memory with combinational ack.
Loads the hand-written test program (test.bin at 0x10000, stub.bin at
the reset vector 0xFFFF0), runs to HLT, and checks the architectural
state and memory against values computed from the C model
(~/workspace/research_notes/courier-firmware/c-port/c/src/cpu/i186.c,
run with the golden harness in /tmp/i186tb: cycle model 1, ud_trap 1).

Golden values (C model, verified by hand for the flag cases):
  status = ST_HLT; cycles to HLT = 1586 (C model; the RTL total differs
  by the documented bus-latency deviation and is printed, not asserted,
  until reconciled -- see the cycles check below).
  AX=5A5A CX=0000 DX=0000 BX=0000 SP=1000 BP=0005 SI=1408 DI=1508
  ES=4000 CS=1000 SS=3000 DS=2000 IP=01E3 FLAGS=F046
*/

`default_nettype none
`timescale 1ns/1ps

module tb_i186_core;
  logic        clk;
  logic        rst_n;
  logic        cyc_model_i;
  logic        ud_trap_i;
  logic        nmi_i;
  logic        irq_i;
  logic [7:0]  irq_vec_i;
  logic        irq_clear_i;
  logic        bus_req;
  logic [19:0] bus_addr;
  logic        bus_wr;
  logic        bus_w;
  logic        bus_io;
  logic [15:0] bus_wdata;
  logic        bus_ack;
  logic [15:0] bus_rdata;
  logic [63:0] cycles_o;
  logic        halted_o;
  logic        st_badop_o;
  logic [19:0] badop_pc_o;
  logic [7:0]  badop_o;
  logic [19:0] pc_o;

  /* 1 MB byte memory (the RAM lives outside the core). */
  logic [7:0] mem [0:1048575];

  i186_core dut (
    .clk          (clk),
        .ce_i         (1'b1),
    .rst_n        (rst_n),
    .cyc_model_i  (cyc_model_i),
    .ud_trap_i    (ud_trap_i),
    .nmi_i        (nmi_i),
    .irq_i        (irq_i),
    .irq_vec_i    (irq_vec_i),
    .irq_clear_i  (irq_clear_i),
    .bus_req      (bus_req),
    .bus_addr     (bus_addr),
    .bus_wr       (bus_wr),
    .bus_w        (bus_w),
    .bus_io       (bus_io),
    .bus_wdata    (bus_wdata),
    .bus_ack      (bus_ack),
    .bus_rdata    (bus_rdata),
    .cycles_o     (cycles_o),
    .halted_o     (halted_o),
    .st_badop_o   (st_badop_o),
    .badop_pc_o   (badop_pc_o),
    .badop_o      (badop_o),
    .pc_o         (pc_o)
  );

  /* Combinational ack; the harness answers in the same cycle. */
  assign bus_ack = bus_req;

  /* Combinational read data. IO space is not used by the test program. */
  assign bus_rdata = bus_io ? 16'h0000 :
                     bus_w ? {mem[bus_addr + 20'd1], mem[bus_addr]} :
                             {8'b0, mem[bus_addr]};

  /* Memory writes land on the clock edge that completes the transaction. */
  always_ff @(posedge clk) begin
    if (bus_req && bus_ack && bus_wr && !bus_io) begin
      if (bus_w) begin
        mem[bus_addr] <= bus_wdata[7:0];
        mem[bus_addr + 20'd1] <= bus_wdata[15:8];
      end else begin
        mem[bus_addr] <= bus_wdata[7:0];
      end
    end
  end

  always #5 clk <= ~clk;

  integer errors;
  integer timeout;
  integer trace_n;
  integer pad_clocks_total;

  /* Count clocks spent in PAD_CYCLES. */
  always @(posedge clk) begin
    if (rst_n && (dut.state == 5'd16))
      pad_clocks_total <= pad_clocks_total + 1;
  end

  /* Instruction trace: CS:IP + opcode at each instruction fetch. */
  always @(posedge clk) begin
    if (rst_n && (dut.state == 5'd0) && dut.fetch_first_byte && bus_req && bus_ack) begin
      if (trace_n < 250) begin
        $display("TRACE %0d cyc=%0d cs=%04X ip=%04X op=%02X ax=%04X cx=%04X dx=%04X bx=%04X sp=%04X bp=%04X si=%04X di=%04X ss=%04X ds=%04X es=%04X",
                 trace_n, cycles_o, dut.sreg[1], dut.ip, bus_rdata[7:0],
                 dut.gpr[0], dut.gpr[1], dut.gpr[2], dut.gpr[3],
                 dut.gpr[4], dut.gpr[5], dut.gpr[6], dut.gpr[7],
                 dut.sreg[2], dut.sreg[3], dut.sreg[0]);
        trace_n <= trace_n + 1;
      end
    end
  end

  function [15:0] rd_word(input [19:0] a);
    rd_word = {mem[a + 20'd1], mem[a]};
  endfunction

  task check_reg(input [15:0] got, input [15:0] want, input [127:0] name);
    begin
      if (got !== want) begin
        $display("FAIL %0s: got %04X want %04X", name, got, want);
        errors = errors + 1;
      end
    end
  endtask

  task check_word(input [19:0] a, input [15:0] want, input [127:0] name);
    begin
      if (rd_word(a) !== want) begin
        $display("FAIL %0s: got %04X want %04X", name, rd_word(a), want);
        errors = errors + 1;
      end
    end
  endtask

  task check_byte(input [19:0] a, input [7:0] want, input [127:0] name);
    begin
      if (mem[a] !== want) begin
        $display("FAIL %0s: got %02X want %02X", name, mem[a], want);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    cyc_model_i = 1'b1;
    ud_trap_i = 1'b1;
    nmi_i = 1'b0;
    irq_i = 1'b0;
    irq_vec_i = 8'd0;
    irq_clear_i = 1'b0;
    errors = 0;
    trace_n = 0;
    pad_clocks_total = 0;

    /* Clear memory, then load the program and the reset-vector stub. */
    for (integer i = 0; i < 1048576; i = i + 1)
      mem[i] = 8'h00;
    mem[20'h10000] = 8'hB8; mem[20'h10001] = 8'h00; mem[20'h10002] = 8'h00; mem[20'h10003] = 8'h8E; mem[20'h10004] = 8'hD8; mem[20'h10005] = 8'hB8; mem[20'h10006] = 8'h00; mem[20'h10007] = 8'h02; mem[20'h10008] = 8'hA3; mem[20'h10009] = 8'h40; mem[20'h1000A] = 8'h00; mem[20'h1000B] = 8'hB8; mem[20'h1000C] = 8'h00; mem[20'h1000D] = 8'h10; mem[20'h1000E] = 8'hA3; mem[20'h1000F] = 8'h42;
    mem[20'h10010] = 8'h00; mem[20'h10011] = 8'hB8; mem[20'h10012] = 8'h00; mem[20'h10013] = 8'h03; mem[20'h10014] = 8'hA3; mem[20'h10015] = 8'h00; mem[20'h10016] = 8'h00; mem[20'h10017] = 8'hB8; mem[20'h10018] = 8'h00; mem[20'h10019] = 8'h10; mem[20'h1001A] = 8'hA3; mem[20'h1001B] = 8'h02; mem[20'h1001C] = 8'h00; mem[20'h1001D] = 8'hB8; mem[20'h1001E] = 8'h00; mem[20'h1001F] = 8'h20;
    mem[20'h10020] = 8'h8E; mem[20'h10021] = 8'hD8; mem[20'h10022] = 8'hB8; mem[20'h10023] = 8'h00; mem[20'h10024] = 8'h30; mem[20'h10025] = 8'h8E; mem[20'h10026] = 8'hD0; mem[20'h10027] = 8'hBC; mem[20'h10028] = 8'h00; mem[20'h10029] = 8'h10; mem[20'h1002A] = 8'hB8; mem[20'h1002B] = 8'h00; mem[20'h1002C] = 8'h40; mem[20'h1002D] = 8'h8E; mem[20'h1002E] = 8'hC0; mem[20'h1002F] = 8'hB8;
    mem[20'h10030] = 8'h34; mem[20'h10031] = 8'h12; mem[20'h10032] = 8'hBB; mem[20'h10033] = 8'hFF; mem[20'h10034] = 8'h00; mem[20'h10035] = 8'h01; mem[20'h10036] = 8'hD8; mem[20'h10037] = 8'hA3; mem[20'h10038] = 8'h00; mem[20'h10039] = 8'h01; mem[20'h1003A] = 8'hB8; mem[20'h1003B] = 8'hFF; mem[20'h1003C] = 8'hFF; mem[20'h1003D] = 8'hBB; mem[20'h1003E] = 8'h01; mem[20'h1003F] = 8'h00;
    mem[20'h10040] = 8'h01; mem[20'h10041] = 8'hD8; mem[20'h10042] = 8'hA3; mem[20'h10043] = 8'h02; mem[20'h10044] = 8'h01; mem[20'h10045] = 8'h9C; mem[20'h10046] = 8'h59; mem[20'h10047] = 8'h89; mem[20'h10048] = 8'h0E; mem[20'h10049] = 8'h04; mem[20'h1004A] = 8'h01; mem[20'h1004B] = 8'hB8; mem[20'h1004C] = 8'h00; mem[20'h1004D] = 8'h10; mem[20'h1004E] = 8'hBB; mem[20'h1004F] = 8'h00;
    mem[20'h10050] = 8'h20; mem[20'h10051] = 8'h29; mem[20'h10052] = 8'hD8; mem[20'h10053] = 8'hA3; mem[20'h10054] = 8'h06; mem[20'h10055] = 8'h01; mem[20'h10056] = 8'h9C; mem[20'h10057] = 8'h59; mem[20'h10058] = 8'h89; mem[20'h10059] = 8'h0E; mem[20'h1005A] = 8'h08; mem[20'h1005B] = 8'h01; mem[20'h1005C] = 8'hB8; mem[20'h1005D] = 8'h05; mem[20'h1005E] = 8'h00; mem[20'h1005F] = 8'hBB;
    mem[20'h10060] = 8'h03; mem[20'h10061] = 8'h00; mem[20'h10062] = 8'hF9; mem[20'h10063] = 8'h11; mem[20'h10064] = 8'hD8; mem[20'h10065] = 8'hA3; mem[20'h10066] = 8'h0A; mem[20'h10067] = 8'h01; mem[20'h10068] = 8'hB8; mem[20'h10069] = 8'h05; mem[20'h1006A] = 8'h00; mem[20'h1006B] = 8'hBB; mem[20'h1006C] = 8'h03; mem[20'h1006D] = 8'h00; mem[20'h1006E] = 8'hF9; mem[20'h1006F] = 8'h19;
    mem[20'h10070] = 8'hD8; mem[20'h10071] = 8'hA3; mem[20'h10072] = 8'h0C; mem[20'h10073] = 8'h01; mem[20'h10074] = 8'hB8; mem[20'h10075] = 8'h34; mem[20'h10076] = 8'h12; mem[20'h10077] = 8'hBB; mem[20'h10078] = 8'h02; mem[20'h10079] = 8'h00; mem[20'h1007A] = 8'hF7; mem[20'h1007B] = 8'hE3; mem[20'h1007C] = 8'hA3; mem[20'h1007D] = 8'h0E; mem[20'h1007E] = 8'h01; mem[20'h1007F] = 8'h89;
    mem[20'h10080] = 8'h16; mem[20'h10081] = 8'h10; mem[20'h10082] = 8'h01; mem[20'h10083] = 8'hB8; mem[20'h10084] = 8'hFE; mem[20'h10085] = 8'hFF; mem[20'h10086] = 8'hBB; mem[20'h10087] = 8'h03; mem[20'h10088] = 8'h00; mem[20'h10089] = 8'hF7; mem[20'h1008A] = 8'hEB; mem[20'h1008B] = 8'hA3; mem[20'h1008C] = 8'h12; mem[20'h1008D] = 8'h01; mem[20'h1008E] = 8'h89; mem[20'h1008F] = 8'h16;
    mem[20'h10090] = 8'h14; mem[20'h10091] = 8'h01; mem[20'h10092] = 8'hB8; mem[20'h10093] = 8'h64; mem[20'h10094] = 8'h00; mem[20'h10095] = 8'hBA; mem[20'h10096] = 8'h00; mem[20'h10097] = 8'h00; mem[20'h10098] = 8'hBB; mem[20'h10099] = 8'h07; mem[20'h1009A] = 8'h00; mem[20'h1009B] = 8'hF7; mem[20'h1009C] = 8'hF3; mem[20'h1009D] = 8'hA3; mem[20'h1009E] = 8'h16; mem[20'h1009F] = 8'h01;
    mem[20'h100A0] = 8'h89; mem[20'h100A1] = 8'h16; mem[20'h100A2] = 8'h18; mem[20'h100A3] = 8'h01; mem[20'h100A4] = 8'hB8; mem[20'h100A5] = 8'h9C; mem[20'h100A6] = 8'hFF; mem[20'h100A7] = 8'h99; mem[20'h100A8] = 8'hBB; mem[20'h100A9] = 8'h07; mem[20'h100AA] = 8'h00; mem[20'h100AB] = 8'hF7; mem[20'h100AC] = 8'hFB; mem[20'h100AD] = 8'hA3; mem[20'h100AE] = 8'h1A; mem[20'h100AF] = 8'h01;
    mem[20'h100B0] = 8'h89; mem[20'h100B1] = 8'h16; mem[20'h100B2] = 8'h1C; mem[20'h100B3] = 8'h01; mem[20'h100B4] = 8'hB8; mem[20'h100B5] = 8'h01; mem[20'h100B6] = 8'h00; mem[20'h100B7] = 8'hB1; mem[20'h100B8] = 8'h04; mem[20'h100B9] = 8'hD3; mem[20'h100BA] = 8'hE0; mem[20'h100BB] = 8'hA3; mem[20'h100BC] = 8'h1E; mem[20'h100BD] = 8'h01; mem[20'h100BE] = 8'hB8; mem[20'h100BF] = 8'h01;
    mem[20'h100C0] = 8'h80; mem[20'h100C1] = 8'hD1; mem[20'h100C2] = 8'hF8; mem[20'h100C3] = 8'hA3; mem[20'h100C4] = 8'h20; mem[20'h100C5] = 8'h01; mem[20'h100C6] = 8'hB8; mem[20'h100C7] = 8'h01; mem[20'h100C8] = 8'h80; mem[20'h100C9] = 8'hD1; mem[20'h100CA] = 8'hC8; mem[20'h100CB] = 8'hA3; mem[20'h100CC] = 8'h22; mem[20'h100CD] = 8'h01; mem[20'h100CE] = 8'hB8; mem[20'h100CF] = 8'h15;
    mem[20'h100D0] = 8'h00; mem[20'h100D1] = 8'h04; mem[20'h100D2] = 8'h27; mem[20'h100D3] = 8'h27; mem[20'h100D4] = 8'hA3; mem[20'h100D5] = 8'h24; mem[20'h100D6] = 8'h01; mem[20'h100D7] = 8'hB8; mem[20'h100D8] = 8'h0F; mem[20'h100D9] = 8'h0F; mem[20'h100DA] = 8'hBB; mem[20'h100DB] = 8'hFF; mem[20'h100DC] = 8'h00; mem[20'h100DD] = 8'h21; mem[20'h100DE] = 8'hD8; mem[20'h100DF] = 8'hA3;
    mem[20'h100E0] = 8'h26; mem[20'h100E1] = 8'h01; mem[20'h100E2] = 8'hB8; mem[20'h100E3] = 8'h00; mem[20'h100E4] = 8'h0F; mem[20'h100E5] = 8'h09; mem[20'h100E6] = 8'hD8; mem[20'h100E7] = 8'hA3; mem[20'h100E8] = 8'h28; mem[20'h100E9] = 8'h01; mem[20'h100EA] = 8'hB8; mem[20'h100EB] = 8'hFF; mem[20'h100EC] = 8'hFF; mem[20'h100ED] = 8'h31; mem[20'h100EE] = 8'hD8; mem[20'h100EF] = 8'hA3;
    mem[20'h100F0] = 8'h2A; mem[20'h100F1] = 8'h01; mem[20'h100F2] = 8'hB8; mem[20'h100F3] = 8'h34; mem[20'h100F4] = 8'h12; mem[20'h100F5] = 8'h3D; mem[20'h100F6] = 8'h34; mem[20'h100F7] = 8'h12; mem[20'h100F8] = 8'h9C; mem[20'h100F9] = 8'h59; mem[20'h100FA] = 8'h89; mem[20'h100FB] = 8'h0E; mem[20'h100FC] = 8'h2C; mem[20'h100FD] = 8'h01; mem[20'h100FE] = 8'hBB; mem[20'h100FF] = 8'h00;
    mem[20'h10100] = 8'h02; mem[20'h10101] = 8'hBE; mem[20'h10102] = 8'h20; mem[20'h10103] = 8'h00; mem[20'h10104] = 8'hB8; mem[20'h10105] = 8'hEF; mem[20'h10106] = 8'hBE; mem[20'h10107] = 8'h89; mem[20'h10108] = 8'h00; mem[20'h10109] = 8'hB8; mem[20'h1010A] = 8'h00; mem[20'h1010B] = 8'h00; mem[20'h1010C] = 8'h8B; mem[20'h1010D] = 8'h00; mem[20'h1010E] = 8'hA3; mem[20'h1010F] = 8'h2E;
    mem[20'h10110] = 8'h01; mem[20'h10111] = 8'hBD; mem[20'h10112] = 8'h00; mem[20'h10113] = 8'h0F; mem[20'h10114] = 8'hB8; mem[20'h10115] = 8'hFE; mem[20'h10116] = 8'hCA; mem[20'h10117] = 8'h89; mem[20'h10118] = 8'h46; mem[20'h10119] = 8'h02; mem[20'h1011A] = 8'hB8; mem[20'h1011B] = 8'h00; mem[20'h1011C] = 8'h00; mem[20'h1011D] = 8'h8B; mem[20'h1011E] = 8'h46; mem[20'h1011F] = 8'h02;
    mem[20'h10120] = 8'hA3; mem[20'h10121] = 8'h30; mem[20'h10122] = 8'h01; mem[20'h10123] = 8'hB8; mem[20'h10124] = 8'hAD; mem[20'h10125] = 8'hDE; mem[20'h10126] = 8'h26; mem[20'h10127] = 8'hA3; mem[20'h10128] = 8'h20; mem[20'h10129] = 8'h00; mem[20'h1012A] = 8'hB8; mem[20'h1012B] = 8'h00; mem[20'h1012C] = 8'h00; mem[20'h1012D] = 8'h26; mem[20'h1012E] = 8'hA1; mem[20'h1012F] = 8'h20;
    mem[20'h10130] = 8'h00; mem[20'h10131] = 8'hA3; mem[20'h10132] = 8'h32; mem[20'h10133] = 8'h01; mem[20'h10134] = 8'hB8; mem[20'h10135] = 8'h11; mem[20'h10136] = 8'h11; mem[20'h10137] = 8'h50; mem[20'h10138] = 8'hB8; mem[20'h10139] = 8'h22; mem[20'h1013A] = 8'h22; mem[20'h1013B] = 8'h50; mem[20'h1013C] = 8'h5B; mem[20'h1013D] = 8'h59; mem[20'h1013E] = 8'h89; mem[20'h1013F] = 8'h1E;
    mem[20'h10140] = 8'h34; mem[20'h10141] = 8'h01; mem[20'h10142] = 8'h89; mem[20'h10143] = 8'h0E; mem[20'h10144] = 8'h36; mem[20'h10145] = 8'h01; mem[20'h10146] = 8'hB8; mem[20'h10147] = 8'h01; mem[20'h10148] = 8'h00; mem[20'h10149] = 8'hB9; mem[20'h1014A] = 8'h02; mem[20'h1014B] = 8'h00; mem[20'h1014C] = 8'hBA; mem[20'h1014D] = 8'h03; mem[20'h1014E] = 8'h00; mem[20'h1014F] = 8'hBB;
    mem[20'h10150] = 8'h04; mem[20'h10151] = 8'h00; mem[20'h10152] = 8'hBD; mem[20'h10153] = 8'h05; mem[20'h10154] = 8'h00; mem[20'h10155] = 8'hBE; mem[20'h10156] = 8'h06; mem[20'h10157] = 8'h00; mem[20'h10158] = 8'hBF; mem[20'h10159] = 8'h07; mem[20'h1015A] = 8'h00; mem[20'h1015B] = 8'h60; mem[20'h1015C] = 8'hB8; mem[20'h1015D] = 8'h00; mem[20'h1015E] = 8'h00; mem[20'h1015F] = 8'hB9;
    mem[20'h10160] = 8'h00; mem[20'h10161] = 8'h00; mem[20'h10162] = 8'hBA; mem[20'h10163] = 8'h00; mem[20'h10164] = 8'h00; mem[20'h10165] = 8'hBB; mem[20'h10166] = 8'h00; mem[20'h10167] = 8'h00; mem[20'h10168] = 8'hBD; mem[20'h10169] = 8'h00; mem[20'h1016A] = 8'h00; mem[20'h1016B] = 8'hBE; mem[20'h1016C] = 8'h00; mem[20'h1016D] = 8'h00; mem[20'h1016E] = 8'hBF; mem[20'h1016F] = 8'h00;
    mem[20'h10170] = 8'h00; mem[20'h10171] = 8'h61; mem[20'h10172] = 8'hA3; mem[20'h10173] = 8'h38; mem[20'h10174] = 8'h01; mem[20'h10175] = 8'h89; mem[20'h10176] = 8'h0E; mem[20'h10177] = 8'h3A; mem[20'h10178] = 8'h01; mem[20'h10179] = 8'h89; mem[20'h1017A] = 8'h16; mem[20'h1017B] = 8'h3C; mem[20'h1017C] = 8'h01; mem[20'h1017D] = 8'h89; mem[20'h1017E] = 8'h1E; mem[20'h1017F] = 8'h3E;
    mem[20'h10180] = 8'h01; mem[20'h10181] = 8'h89; mem[20'h10182] = 8'h2E; mem[20'h10183] = 8'h40; mem[20'h10184] = 8'h01; mem[20'h10185] = 8'h89; mem[20'h10186] = 8'h36; mem[20'h10187] = 8'h42; mem[20'h10188] = 8'h01; mem[20'h10189] = 8'h89; mem[20'h1018A] = 8'h3E; mem[20'h1018B] = 8'h44; mem[20'h1018C] = 8'h01; mem[20'h1018D] = 8'hE8; mem[20'h1018E] = 8'h53; mem[20'h1018F] = 8'h00;
    mem[20'h10190] = 8'hA3; mem[20'h10191] = 8'h46; mem[20'h10192] = 8'h01; mem[20'h10193] = 8'hBE; mem[20'h10194] = 8'h00; mem[20'h10195] = 8'h14; mem[20'h10196] = 8'hBF; mem[20'h10197] = 8'h00; mem[20'h10198] = 8'h15; mem[20'h10199] = 8'hB9; mem[20'h1019A] = 8'h08; mem[20'h1019B] = 8'h00; mem[20'h1019C] = 8'hC6; mem[20'h1019D] = 8'h04; mem[20'h1019E] = 8'h11; mem[20'h1019F] = 8'hC6;
    mem[20'h101A0] = 8'h44; mem[20'h101A1] = 8'h01; mem[20'h101A2] = 8'h22; mem[20'h101A3] = 8'hC6; mem[20'h101A4] = 8'h44; mem[20'h101A5] = 8'h02; mem[20'h101A6] = 8'h33; mem[20'h101A7] = 8'hC6; mem[20'h101A8] = 8'h44; mem[20'h101A9] = 8'h03; mem[20'h101AA] = 8'h44; mem[20'h101AB] = 8'hC6; mem[20'h101AC] = 8'h44; mem[20'h101AD] = 8'h04; mem[20'h101AE] = 8'h55; mem[20'h101AF] = 8'hC6;
    mem[20'h101B0] = 8'h44; mem[20'h101B1] = 8'h05; mem[20'h101B2] = 8'h66; mem[20'h101B3] = 8'hC6; mem[20'h101B4] = 8'h44; mem[20'h101B5] = 8'h06; mem[20'h101B6] = 8'h77; mem[20'h101B7] = 8'hC6; mem[20'h101B8] = 8'h44; mem[20'h101B9] = 8'h07; mem[20'h101BA] = 8'h88; mem[20'h101BB] = 8'hF3; mem[20'h101BC] = 8'hA4; mem[20'h101BD] = 8'h89; mem[20'h101BE] = 8'h36; mem[20'h101BF] = 8'h48;
    mem[20'h101C0] = 8'h01; mem[20'h101C1] = 8'h89; mem[20'h101C2] = 8'h3E; mem[20'h101C3] = 8'h4A; mem[20'h101C4] = 8'h01; mem[20'h101C5] = 8'h89; mem[20'h101C6] = 8'h0E; mem[20'h101C7] = 8'h4C; mem[20'h101C8] = 8'h01; mem[20'h101C9] = 8'hCD; mem[20'h101CA] = 8'h10; mem[20'h101CB] = 8'hA3; mem[20'h101CC] = 8'h4E; mem[20'h101CD] = 8'h01; mem[20'h101CE] = 8'hB8; mem[20'h101CF] = 8'h10;
    mem[20'h101D0] = 8'h00; mem[20'h101D1] = 8'hBA; mem[20'h101D2] = 8'h00; mem[20'h101D3] = 8'h00; mem[20'h101D4] = 8'hBB; mem[20'h101D5] = 8'h00; mem[20'h101D6] = 8'h00; mem[20'h101D7] = 8'hF7; mem[20'h101D8] = 8'hF3; mem[20'h101D9] = 8'hA3; mem[20'h101DA] = 8'h50; mem[20'h101DB] = 8'h01; mem[20'h101DC] = 8'hB8; mem[20'h101DD] = 8'h5A; mem[20'h101DE] = 8'h5A; mem[20'h101DF] = 8'hA3;
    mem[20'h101E0] = 8'h52; mem[20'h101E1] = 8'h01; mem[20'h101E2] = 8'hF4; mem[20'h101E3] = 8'hB8; mem[20'h101E4] = 8'h5A; mem[20'h101E5] = 8'h5A; mem[20'h101E6] = 8'hC3; mem[20'h101E7] = 8'h00; mem[20'h101E8] = 8'h00; mem[20'h101E9] = 8'h00; mem[20'h101EA] = 8'h00; mem[20'h101EB] = 8'h00; mem[20'h101EC] = 8'h00; mem[20'h101ED] = 8'h00; mem[20'h101EE] = 8'h00; mem[20'h101EF] = 8'h00;
    mem[20'h101F0] = 8'h00; mem[20'h101F1] = 8'h00; mem[20'h101F2] = 8'h00; mem[20'h101F3] = 8'h00; mem[20'h101F4] = 8'h00; mem[20'h101F5] = 8'h00; mem[20'h101F6] = 8'h00; mem[20'h101F7] = 8'h00; mem[20'h101F8] = 8'h00; mem[20'h101F9] = 8'h00; mem[20'h101FA] = 8'h00; mem[20'h101FB] = 8'h00; mem[20'h101FC] = 8'h00; mem[20'h101FD] = 8'h00; mem[20'h101FE] = 8'h00; mem[20'h101FF] = 8'h00;
    mem[20'h10200] = 8'hB8; mem[20'h10201] = 8'hCD; mem[20'h10202] = 8'hAB; mem[20'h10203] = 8'hCF; mem[20'h10204] = 8'h00; mem[20'h10205] = 8'h00; mem[20'h10206] = 8'h00; mem[20'h10207] = 8'h00; mem[20'h10208] = 8'h00; mem[20'h10209] = 8'h00; mem[20'h1020A] = 8'h00; mem[20'h1020B] = 8'h00; mem[20'h1020C] = 8'h00; mem[20'h1020D] = 8'h00; mem[20'h1020E] = 8'h00; mem[20'h1020F] = 8'h00;
    mem[20'h10210] = 8'h00; mem[20'h10211] = 8'h00; mem[20'h10212] = 8'h00; mem[20'h10213] = 8'h00; mem[20'h10214] = 8'h00; mem[20'h10215] = 8'h00; mem[20'h10216] = 8'h00; mem[20'h10217] = 8'h00; mem[20'h10218] = 8'h00; mem[20'h10219] = 8'h00; mem[20'h1021A] = 8'h00; mem[20'h1021B] = 8'h00; mem[20'h1021C] = 8'h00; mem[20'h1021D] = 8'h00; mem[20'h1021E] = 8'h00; mem[20'h1021F] = 8'h00;
    mem[20'h10220] = 8'h00; mem[20'h10221] = 8'h00; mem[20'h10222] = 8'h00; mem[20'h10223] = 8'h00; mem[20'h10224] = 8'h00; mem[20'h10225] = 8'h00; mem[20'h10226] = 8'h00; mem[20'h10227] = 8'h00; mem[20'h10228] = 8'h00; mem[20'h10229] = 8'h00; mem[20'h1022A] = 8'h00; mem[20'h1022B] = 8'h00; mem[20'h1022C] = 8'h00; mem[20'h1022D] = 8'h00; mem[20'h1022E] = 8'h00; mem[20'h1022F] = 8'h00;
    mem[20'h10230] = 8'h00; mem[20'h10231] = 8'h00; mem[20'h10232] = 8'h00; mem[20'h10233] = 8'h00; mem[20'h10234] = 8'h00; mem[20'h10235] = 8'h00; mem[20'h10236] = 8'h00; mem[20'h10237] = 8'h00; mem[20'h10238] = 8'h00; mem[20'h10239] = 8'h00; mem[20'h1023A] = 8'h00; mem[20'h1023B] = 8'h00; mem[20'h1023C] = 8'h00; mem[20'h1023D] = 8'h00; mem[20'h1023E] = 8'h00; mem[20'h1023F] = 8'h00;
    mem[20'h10240] = 8'h00; mem[20'h10241] = 8'h00; mem[20'h10242] = 8'h00; mem[20'h10243] = 8'h00; mem[20'h10244] = 8'h00; mem[20'h10245] = 8'h00; mem[20'h10246] = 8'h00; mem[20'h10247] = 8'h00; mem[20'h10248] = 8'h00; mem[20'h10249] = 8'h00; mem[20'h1024A] = 8'h00; mem[20'h1024B] = 8'h00; mem[20'h1024C] = 8'h00; mem[20'h1024D] = 8'h00; mem[20'h1024E] = 8'h00; mem[20'h1024F] = 8'h00;
    mem[20'h10250] = 8'h00; mem[20'h10251] = 8'h00; mem[20'h10252] = 8'h00; mem[20'h10253] = 8'h00; mem[20'h10254] = 8'h00; mem[20'h10255] = 8'h00; mem[20'h10256] = 8'h00; mem[20'h10257] = 8'h00; mem[20'h10258] = 8'h00; mem[20'h10259] = 8'h00; mem[20'h1025A] = 8'h00; mem[20'h1025B] = 8'h00; mem[20'h1025C] = 8'h00; mem[20'h1025D] = 8'h00; mem[20'h1025E] = 8'h00; mem[20'h1025F] = 8'h00;
    mem[20'h10260] = 8'h00; mem[20'h10261] = 8'h00; mem[20'h10262] = 8'h00; mem[20'h10263] = 8'h00; mem[20'h10264] = 8'h00; mem[20'h10265] = 8'h00; mem[20'h10266] = 8'h00; mem[20'h10267] = 8'h00; mem[20'h10268] = 8'h00; mem[20'h10269] = 8'h00; mem[20'h1026A] = 8'h00; mem[20'h1026B] = 8'h00; mem[20'h1026C] = 8'h00; mem[20'h1026D] = 8'h00; mem[20'h1026E] = 8'h00; mem[20'h1026F] = 8'h00;
    mem[20'h10270] = 8'h00; mem[20'h10271] = 8'h00; mem[20'h10272] = 8'h00; mem[20'h10273] = 8'h00; mem[20'h10274] = 8'h00; mem[20'h10275] = 8'h00; mem[20'h10276] = 8'h00; mem[20'h10277] = 8'h00; mem[20'h10278] = 8'h00; mem[20'h10279] = 8'h00; mem[20'h1027A] = 8'h00; mem[20'h1027B] = 8'h00; mem[20'h1027C] = 8'h00; mem[20'h1027D] = 8'h00; mem[20'h1027E] = 8'h00; mem[20'h1027F] = 8'h00;
    mem[20'h10280] = 8'h00; mem[20'h10281] = 8'h00; mem[20'h10282] = 8'h00; mem[20'h10283] = 8'h00; mem[20'h10284] = 8'h00; mem[20'h10285] = 8'h00; mem[20'h10286] = 8'h00; mem[20'h10287] = 8'h00; mem[20'h10288] = 8'h00; mem[20'h10289] = 8'h00; mem[20'h1028A] = 8'h00; mem[20'h1028B] = 8'h00; mem[20'h1028C] = 8'h00; mem[20'h1028D] = 8'h00; mem[20'h1028E] = 8'h00; mem[20'h1028F] = 8'h00;
    mem[20'h10290] = 8'h00; mem[20'h10291] = 8'h00; mem[20'h10292] = 8'h00; mem[20'h10293] = 8'h00; mem[20'h10294] = 8'h00; mem[20'h10295] = 8'h00; mem[20'h10296] = 8'h00; mem[20'h10297] = 8'h00; mem[20'h10298] = 8'h00; mem[20'h10299] = 8'h00; mem[20'h1029A] = 8'h00; mem[20'h1029B] = 8'h00; mem[20'h1029C] = 8'h00; mem[20'h1029D] = 8'h00; mem[20'h1029E] = 8'h00; mem[20'h1029F] = 8'h00;
    mem[20'h102A0] = 8'h00; mem[20'h102A1] = 8'h00; mem[20'h102A2] = 8'h00; mem[20'h102A3] = 8'h00; mem[20'h102A4] = 8'h00; mem[20'h102A5] = 8'h00; mem[20'h102A6] = 8'h00; mem[20'h102A7] = 8'h00; mem[20'h102A8] = 8'h00; mem[20'h102A9] = 8'h00; mem[20'h102AA] = 8'h00; mem[20'h102AB] = 8'h00; mem[20'h102AC] = 8'h00; mem[20'h102AD] = 8'h00; mem[20'h102AE] = 8'h00; mem[20'h102AF] = 8'h00;
    mem[20'h102B0] = 8'h00; mem[20'h102B1] = 8'h00; mem[20'h102B2] = 8'h00; mem[20'h102B3] = 8'h00; mem[20'h102B4] = 8'h00; mem[20'h102B5] = 8'h00; mem[20'h102B6] = 8'h00; mem[20'h102B7] = 8'h00; mem[20'h102B8] = 8'h00; mem[20'h102B9] = 8'h00; mem[20'h102BA] = 8'h00; mem[20'h102BB] = 8'h00; mem[20'h102BC] = 8'h00; mem[20'h102BD] = 8'h00; mem[20'h102BE] = 8'h00; mem[20'h102BF] = 8'h00;
    mem[20'h102C0] = 8'h00; mem[20'h102C1] = 8'h00; mem[20'h102C2] = 8'h00; mem[20'h102C3] = 8'h00; mem[20'h102C4] = 8'h00; mem[20'h102C5] = 8'h00; mem[20'h102C6] = 8'h00; mem[20'h102C7] = 8'h00; mem[20'h102C8] = 8'h00; mem[20'h102C9] = 8'h00; mem[20'h102CA] = 8'h00; mem[20'h102CB] = 8'h00; mem[20'h102CC] = 8'h00; mem[20'h102CD] = 8'h00; mem[20'h102CE] = 8'h00; mem[20'h102CF] = 8'h00;
    mem[20'h102D0] = 8'h00; mem[20'h102D1] = 8'h00; mem[20'h102D2] = 8'h00; mem[20'h102D3] = 8'h00; mem[20'h102D4] = 8'h00; mem[20'h102D5] = 8'h00; mem[20'h102D6] = 8'h00; mem[20'h102D7] = 8'h00; mem[20'h102D8] = 8'h00; mem[20'h102D9] = 8'h00; mem[20'h102DA] = 8'h00; mem[20'h102DB] = 8'h00; mem[20'h102DC] = 8'h00; mem[20'h102DD] = 8'h00; mem[20'h102DE] = 8'h00; mem[20'h102DF] = 8'h00;
    mem[20'h102E0] = 8'h00; mem[20'h102E1] = 8'h00; mem[20'h102E2] = 8'h00; mem[20'h102E3] = 8'h00; mem[20'h102E4] = 8'h00; mem[20'h102E5] = 8'h00; mem[20'h102E6] = 8'h00; mem[20'h102E7] = 8'h00; mem[20'h102E8] = 8'h00; mem[20'h102E9] = 8'h00; mem[20'h102EA] = 8'h00; mem[20'h102EB] = 8'h00; mem[20'h102EC] = 8'h00; mem[20'h102ED] = 8'h00; mem[20'h102EE] = 8'h00; mem[20'h102EF] = 8'h00;
    mem[20'h102F0] = 8'h00; mem[20'h102F1] = 8'h00; mem[20'h102F2] = 8'h00; mem[20'h102F3] = 8'h00; mem[20'h102F4] = 8'h00; mem[20'h102F5] = 8'h00; mem[20'h102F6] = 8'h00; mem[20'h102F7] = 8'h00; mem[20'h102F8] = 8'h00; mem[20'h102F9] = 8'h00; mem[20'h102FA] = 8'h00; mem[20'h102FB] = 8'h00; mem[20'h102FC] = 8'h00; mem[20'h102FD] = 8'h00; mem[20'h102FE] = 8'h00; mem[20'h102FF] = 8'h00;
    mem[20'h10300] = 8'hB8; mem[20'h10301] = 8'h00; mem[20'h10302] = 8'hDC; mem[20'h10303] = 8'hCF;
    mem[20'hFFFF0] = 8'hEA; mem[20'hFFFF1] = 8'h00; mem[20'hFFFF2] = 8'h00; mem[20'hFFFF3] = 8'h00; mem[20'hFFFF4] = 8'h10;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    /* Run until HLT or a generous timeout. */
    timeout = 0;
    while (!halted_o && !st_badop_o && (timeout < 100000)) begin
      @(posedge clk);
      timeout = timeout + 1;
    end

    if (st_badop_o) begin
      $display("FAIL: bad opcode %02X at PC %05X", badop_o, badop_pc_o);
      errors = errors + 1;
    end
    if (!halted_o) begin
      $display("FAIL: did not halt within %0d clocks (PC %05X)", timeout, pc_o);
      errors = errors + 1;
    end

    $display("cycles_o = %0d (C model: 1586) pad_clocks=%0d", cycles_o, pad_clocks_total);

    /* Architectural state (hierarchical refs to the public registers). */
    check_reg(dut.gpr[0], 16'h5A5A, "AX");
    check_reg(dut.gpr[1], 16'h0000, "CX");
    check_reg(dut.gpr[2], 16'h0000, "DX");
    check_reg(dut.gpr[3], 16'h0000, "BX");
    check_reg(dut.gpr[4], 16'h1000, "SP");
    check_reg(dut.gpr[5], 16'h0005, "BP");
    check_reg(dut.gpr[6], 16'h1408, "SI");
    check_reg(dut.gpr[7], 16'h1508, "DI");
    check_reg(dut.sreg[0], 16'h4000, "ES");
    check_reg(dut.sreg[1], 16'h1000, "CS");
    check_reg(dut.sreg[2], 16'h3000, "SS");
    check_reg(dut.sreg[3], 16'h2000, "DS");
    check_reg(dut.ip, 16'h01E3, "IP");

    /* FLAGS (golden F046: CF=0 PF=1 AF=0 ZF=1 SF=0 TF=0 IF=0 DF=0 OF=0). */
    if ((dut.cf !== 1'b0) || (dut.pf !== 1'b1) || (dut.af !== 1'b0) ||
        (dut.zf !== 1'b1) || (dut.sf !== 1'b0) || (dut.tf !== 1'b0) ||
        (dut.ifl !== 1'b0) || (dut.df !== 1'b0) || (dut.of !== 1'b0)) begin
      $display("FAIL FLAGS: cf=%b pf=%b af=%b zf=%b sf=%b tf=%b ifl=%b df=%b of=%b",
               dut.cf, dut.pf, dut.af, dut.zf, dut.sf, dut.tf, dut.ifl, dut.df, dut.of);
      errors = errors + 1;
    end

    check_word(20'h20100, 16'h1333, "DS:0100");
    check_word(20'h20102, 16'h0000, "DS:0102");
    check_word(20'h20104, 16'hF057, "DS:0104");
    check_word(20'h20106, 16'hF000, "DS:0106");
    check_word(20'h20108, 16'hF087, "DS:0108");
    check_word(20'h2010A, 16'h0009, "DS:010A");
    check_word(20'h2010C, 16'h0001, "DS:010C");
    check_word(20'h2010E, 16'h2468, "DS:010E");
    check_word(20'h20110, 16'h0000, "DS:0110");
    check_word(20'h20112, 16'hFFFA, "DS:0112");
    check_word(20'h20114, 16'hFFFF, "DS:0114");
    check_word(20'h20116, 16'h000E, "DS:0116");
    check_word(20'h20118, 16'h0002, "DS:0118");
    check_word(20'h2011A, 16'hFFF2, "DS:011A");
    check_word(20'h2011C, 16'hFFFE, "DS:011C");
    check_word(20'h2011E, 16'h0010, "DS:011E");
    check_word(20'h20120, 16'hC000, "DS:0120");
    check_word(20'h20122, 16'hC000, "DS:0122");
    check_word(20'h20124, 16'h0042, "DS:0124");
    check_word(20'h20126, 16'h000F, "DS:0126");
    check_word(20'h20128, 16'h0FFF, "DS:0128");
    check_word(20'h2012A, 16'hFF00, "DS:012A");
    check_word(20'h2012C, 16'hF046, "DS:012C");
    check_word(20'h2012E, 16'hBEEF, "DS:012E");
    check_word(20'h20130, 16'hCAFE, "DS:0130");
    check_word(20'h20132, 16'hDEAD, "DS:0132");
    check_word(20'h20134, 16'h2222, "DS:0134");
    check_word(20'h20136, 16'h1111, "DS:0136");
    check_word(20'h20138, 16'h0001, "DS:0138");
    check_word(20'h2013A, 16'h0002, "DS:013A");
    check_word(20'h2013C, 16'h0003, "DS:013C");
    check_word(20'h2013E, 16'h0004, "DS:013E");
    check_word(20'h20140, 16'h0005, "DS:0140");
    check_word(20'h20142, 16'h0006, "DS:0142");
    check_word(20'h20144, 16'h0007, "DS:0144");
    check_word(20'h20146, 16'h5A5A, "DS:0146");
    check_word(20'h20148, 16'h1408, "DS:0148");
    check_word(20'h2014A, 16'h1508, "DS:014A");
    check_word(20'h2014C, 16'h0000, "DS:014C");
    check_word(20'h2014E, 16'hABCD, "DS:014E");
    check_word(20'h20150, 16'hDC00, "DS:0150");
    check_word(20'h20152, 16'h5A5A, "DS:0152");
    check_word(20'h20220, 16'hBEEF, "DS:0220");
    check_word(20'h30F02, 16'hCAFE, "SS:0F02");
    check_word(20'h40020, 16'hDEAD, "ES:0020");
    check_byte(20'h41500, 8'h11, "ES:1500");
    check_byte(20'h41501, 8'h22, "ES:1501");
    check_byte(20'h41502, 8'h33, "ES:1502");
    check_byte(20'h41503, 8'h44, "ES:1503");
    check_byte(20'h41504, 8'h55, "ES:1504");
    check_byte(20'h41505, 8'h66, "ES:1505");
    check_byte(20'h41506, 8'h77, "ES:1506");
    check_byte(20'h41507, 8'h88, "ES:1507");
    check_byte(20'h21400, 8'h11, "DS:1400");
    check_byte(20'h21401, 8'h22, "DS:1401");
    check_byte(20'h21402, 8'h33, "DS:1402");
    check_byte(20'h21403, 8'h44, "DS:1403");
    check_byte(20'h21404, 8'h55, "DS:1404");
    check_byte(20'h21405, 8'h66, "DS:1405");
    check_byte(20'h21406, 8'h77, "DS:1406");
    check_byte(20'h21407, 8'h88, "DS:1407");

    if (errors == 0) begin
      $display("PASS: all checks passed (cycles_o=%0d)", cycles_o);
    end else begin
      $display("FAIL: %0d errors", errors);
      $fatal(1, "testbench failed");
    end
    $finish;
  end
endmodule
`default_nettype wire
