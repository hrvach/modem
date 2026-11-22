/* Directed self-checking test of dsp_glue: firmware burst loader + start + ROM tables, mailbox both ways, flags, events, overlay download, frame hook
   (ring pointer peek, INT0), heartbeat. The reference values come from ../courier/src/glue/machine.c semantics (see the module header). */
`timescale 1ns/1ps
module tb_dsp_glue;
reg clk = 0, rst_n = 0;
always #5 clk = ~clk;

reg  [15:0] rd_port = 0;
wire [7:0]  rd_data;
reg         rd_commit = 0, wr_commit = 0;
reg  [15:0] wr_port = 0;
reg  [7:0]  wr_data = 0;
wire        run, int0, dsp_rst_n, int2;
wire [63:0] hb_count;
reg         start = 0, burst_valid = 0, rom_loaded = 0;
reg  [63:0] burst_data = 0;
reg         io_req = 0, io_rd = 0;
reg  [15:0] io_addr = 0, io_wdata = 0;
wire        io_ack;
wire [15:0] io_rdata, mclk_n;
wire        pw_en;
wire [15:0] pw_addr, pw_data;
reg         pw_ready = 1;
reg         frame = 0;
reg  [15:0] exp_cnt = 0;
wire        pk_req;
wire [23:0] pk_addr;
reg         pk_ack = 0;
reg  [15:0] pk_rdata = 0;
reg  [15:0] ring_rd = 16'h0010, ring_wr = 16'h0010;

dsp_glue dut (.clk(clk), .rst_n(rst_n), .rd_port_i(rd_port), .rd_data_o(rd_data), .rd_commit_i(rd_commit), .wr_commit_i(wr_commit), .wr_port_i(wr_port),
    .wr_data_i(wr_data), .run_o(run), .int0_set_o(int0), .hb_count_o(hb_count), .rom_loaded_i(rom_loaded), .dsp_start_req_i(start), .burst_valid_i(burst_valid), .burst_data_i(burst_data),
    .io_req_i(io_req), .io_rd_i(io_rd), .io_addr_i(io_addr), .io_wdata_i(io_wdata), .io_ack_o(io_ack), .io_rdata_o(io_rdata), .dsp_rst_n_o(dsp_rst_n),
    .dsp_int2_o(int2), .mclk_n_o(mclk_n), .pw_en_o(pw_en), .pw_addr_o(pw_addr), .pw_data_o(pw_data), .pw_ready_i(pw_ready), .frame_tick_i(frame),
    .dsp_timer_exp_i(exp_cnt), .pk_req_o(pk_req), .pk_addr_o(pk_addr), .pk_ack_i(pk_ack), .pk_rdata_i(pk_rdata));

/* program memory model fed by the host write port */
reg [15:0] pm [0:65535];
integer pm_writes = 0;
always @(posedge clk) if (pw_en && pw_ready) begin pm[pw_addr] <= pw_data; pm_writes <= pm_writes + 1; end

/* 186 RAM peek model: one clock latency */
always @(posedge clk) begin
    pk_ack <= 0;
    if (pk_req && !pk_ack) begin pk_ack <= 1; pk_rdata <= (pk_addr[15:0] == (16'h029A >> 1)) ? ring_rd : ring_wr; end
end

integer errors = 0, int0_count = 0, int2_count = 0;
always @(posedge clk) begin if (int0) int0_count <= int0_count + 1; if (int2) int2_count <= int2_count + 1; end

task chk(input [255:0] name, input [31:0] got, input [31:0] want);
    begin if (got !== want) begin errors = errors + 1; $display("FAIL %0s: got %h want %h", name, got, want); end end
endtask

task w186(input [15:0] port, input [7:0] v);
    begin @(posedge clk); wr_port <= port; wr_data <= v; wr_commit <= 1; @(posedge clk); wr_commit <= 0; #1; end
endtask
task r186(input [15:0] port, output [7:0] v);
    begin @(posedge clk); rd_port <= port; rd_commit <= 1; @(negedge clk); v = rd_data; @(posedge clk); rd_commit <= 0; #1; end
endtask
task dspw(input [7:0] port, input [15:0] v);
    begin @(posedge clk); io_addr <= {8'h00, port}; io_wdata <= v; io_rd <= 0; io_req <= 1; @(posedge clk); io_req <= 0; #1; end
endtask
task dspr(input [7:0] port, output [15:0] v);
    begin @(posedge clk); io_addr <= {8'h00, port}; io_rd <= 1; io_req <= 1; @(negedge clk); v = io_rdata; @(posedge clk); io_req <= 0; io_rd <= 0; #1; end
endtask
task do_frame;
    begin @(posedge clk); frame <= 1; @(posedge clk); frame <= 0; repeat (20) @(posedge clk); end
endtask

reg [15:0] rom [0:31];
reg [7:0]  b;
reg [15:0] w;
integer i, n0;
initial begin
    rom[0]=16'hF0F0; rom[1]=16'hF010; rom[2]=16'h10F0; rom[3]=16'h1010; rom[4]=16'hF0D0; rom[5]=16'hD010; rom[6]=16'h30F0; rom[7]=16'h1030;
    rom[8]=16'hD0F0; rom[9]=16'hF030; rom[10]=16'h10D0; rom[11]=16'h3010; rom[12]=16'hD0D0; rom[13]=16'hD030; rom[14]=16'h30D0; rom[15]=16'h3030;
    rom[16]=16'h0002; rom[17]=16'h0000; rom[18]=16'h0003; rom[19]=16'h0001; rom[20]=16'h0003; rom[21]=16'h0002; rom[22]=16'h0001; rom[23]=16'h0000;
    rom[24]=16'h0000; rom[25]=16'h0001; rom[26]=16'h0002; rom[27]=16'h0003; rom[28]=16'h0001; rom[29]=16'h0003; rom[30]=16'h0000; rom[31]=16'h0002;
    for (i = 0; i < 65536; i = i + 1) pm[i] = 16'hxxxx;
    repeat (5) @(posedge clk); rst_n = 1; repeat (5) @(posedge clk);

    /* ---- before the start: 2 skipped bursts (16 bytes), then 3 bursts = 12 words at 0x8000 */
    chk("run before start", run, 0); chk("dsp reset held", dsp_rst_n, 0);
    for (i = 0; i < 5; i = i + 1) begin
        @(posedge clk); burst_data <= {16'h4000 + i[15:0] * 16'h10 + 16'h3, 16'h4000 + i[15:0] * 16'h10 + 16'h2, 16'h4000 + i[15:0] * 16'h10 + 16'h1, 16'h4000 + i[15:0] * 16'h10}; burst_valid <= 1;
        @(posedge clk); burst_valid <= 0; repeat (10) @(posedge clk);
    end
    @(posedge clk); start <= 1; @(posedge clk); start <= 0;
    repeat (200) @(posedge clk);
    chk("run after start", run, 1); chk("dsp released", dsp_rst_n, 1);
    chk("pm 0x8000", pm[16'h8000], 16'h4020); chk("pm 0x8003", pm[16'h8003], 16'h4023); chk("pm 0x8004", pm[16'h8004], 16'h4030);
    chk("pm 0x8008", pm[16'h8008], 16'h4040); chk("pm 0x800B", pm[16'h800B], 16'h4043); chk("pm 0x800C unwritten", pm[16'h800C], 16'hxxxx);
    for (i = 0; i < 32; i = i + 1) if (pm[16'h0440 + i] !== rom[i]) begin errors = errors + 1; $display("FAIL rom word %0d got %h want %h", i, pm[16'h0440 + i], rom[i]); end

    /* ---- 186 -> DSP mailbox: 4 words, bytes through ports 0x40/0x42 (word 0) ... 0x5C/0x5E (word 7) */
    for (i = 0; i < 8; i = i + 1) begin
        w186(16'h0040 + i * 4, 8'h10 + i);
        w186(16'h0042 + i * 4, 8'h20 + i);
    end
    chk("h2d_pending set by 0x5E", dut.h2d_pending_q, 1);
    chk("INT2 pulses", int2_count, 1);
    dspr(8'h57, w); chk("status pending", w[2:0], 3'b111);
    dspr(8'h58, w); chk("h2d word 0", w, 16'h2010);
    dspr(8'h5F, w); chk("h2d word 7", w, 16'h2717);
    /* DSP acks the command: 0x57 <- 1 clears pending */
    dspw(8'h57, 16'h0001);
    chk("pending cleared", dut.h2d_pending_q, 0);
    chk("evt bit 0", dut.evt_q[0], 1);

    /* ---- DSP -> 186 mailbox, word 7 last raises the message-valid event */
    for (i = 0; i < 8; i = i + 1) dspw(8'h58 + i, 16'hA000 + i[15:0] * 16'h0101);
    chk("evt bit 1", dut.evt_q[1], 1);
    r186(16'h0058, b); chk("d2h port 0x58 (word 6 lo)", b, 8'h06);
    r186(16'h005A, b); chk("d2h port 0x5A (word 6 hi)", b, 8'hA6);
    chk("d2h valid cleared by 0x58 read", dut.d2h_valid_q, 0);
    dspr(8'h57, w); chk("status d2h free", w[1], 1);

    /* ---- data word 0x60 */
    dspw(8'h60, 16'hBEEF);
    dspr(8'h57, w); chk("data full -> bit2 low", w[2], 0);
    r186(16'h0062, b); chk("data hi", b, 8'hBE);
    r186(16'h0060, b); chk("data lo", b, 8'hEF);
    dspr(8'h57, w); chk("data free -> bit2 high", w[2], 1);

    /* ---- flags: DSP sets 0x56 bits -> flags56; 186 clears them with 0x18 / 0x1A writes */
    dspw(8'h56, 16'h0305);
    r186(16'h0018, b); chk("flags56 lo", b, 8'h05);
    r186(16'h001A, b); chk("flags56 hi", b, 8'h03);
    w186(16'h0018, 8'h01);
    r186(16'h0018, b); chk("flags56 lo after clear", b, 8'h04);
    dspr(8'h56, w); chk("flagsD after 186 write of 0x18", w, 16'h0001);

    /* ---- overlay: DSP command 2 with address 0x9000 in word 7; then two 4-byte acks */
    w186(16'h0058, 8'h02); w186(16'h005A, 8'h00); w186(16'h005C, 8'h00); w186(16'h005E, 8'h00);   /* sets pending; word 7 = 0 first */
    w186(16'h005C, 8'h00); w186(16'h005E, 8'h90);                                                 /* word 7 = 0x9000 (hi byte last, sets pending again) */
    dspw(8'h57, 16'h0001);                                                                         /* ack the command: overlay pointer = word 7 */
    for (i = 0; i < 4; i = i + 1) w186(16'h0040 + i * 2, 8'h11 * (i + 1));
    w186(16'h001E, 8'h01);
    for (i = 0; i < 4; i = i + 1) w186(16'h0048 + i * 2, 8'h55 + i);
    w186(16'h001E, 8'h02);
    repeat (20) @(posedge clk);
    chk("ovl word 0", pm[16'h9000], 16'h2211); chk("ovl word 1", pm[16'h9001], 16'h4433);
    chk("ovl word 2", pm[16'h9002], 16'h5655); chk("ovl word 3", pm[16'h9003], 16'h5857);
    dspw(8'h57, 16'h0500);
    r186(16'h001E, b); chk("ovl status", b, 8'h05);
    w186(16'h001E, 8'h04);
    r186(16'h001E, b); chk("ovl status after 4", b, 8'h01);

    /* ---- frame hook: events become INT0 once; ring pointers differ -> event 0; heartbeat */
    r186(16'h001C, b);
    w186(16'h001C, b);                                              /* clear every event: event 0 (mailbox free) survives a clear while nothing is in flight */
    chk("evt0 kept by a clear while the mailbox is free", dut.evt_q[0], 1);
    do_frame;                                                       /* it raises its one INT0 */
    n0 = int0_count; do_frame; chk("no int0 without events", int0_count, n0);
    /* a command in flight: the 186's clear takes event 0 away, the DSP's ack sets it again */
    w186(16'h005C, 8'h00); w186(16'h005E, 8'h00);
    chk("pending again", dut.h2d_pending_q, 1);
    w186(16'h001C, 8'h01);
    chk("evt0 cleared while a command is in flight", dut.evt_q[0], 0);
    dspw(8'h57, 16'h0001);
    chk("evt0 set by the ack", dut.evt_q[0], 1);
    do_frame; n0 = int0_count; do_frame; chk("no int0 after the ack was seen", int0_count, n0);
    ring_wr = 16'h0012; do_frame;                                  /* pointers differ, mailbox free */
    chk("int0 on ring difference", int0_count, n0 + 1);
    chk("evt0 set", dut.evt_q[0], 1);
    do_frame; chk("int0 again while the pointers differ", int0_count, n0 + 2);
    ring_wr = ring_rd; do_frame; chk("no int0 once equal (event already seen)", int0_count, n0 + 2);
    exp_cnt = 16'h0003; do_frame;
    chk("heartbeat int0", int0_count, n0 + 3);
    chk("hb_count", hb_count[15:0], 16'h0003);
    do_frame; chk("heartbeat consumed", int0_count, n0 + 3);
    dspw(8'h6B, 16'h0090); chk("mclk n", mclk_n, 16'h0090);
    dspw(8'h70, 16'h1234); dspr(8'h70, w); chk("port store readback", w, 16'h1234);

    /* a loaded on-chip ROM: the synthesised tables must not be written after a restart */
    rst_n = 0; repeat (4) @(posedge clk); rst_n = 1; repeat (4) @(posedge clk);
    for (i = 0; i < 32; i = i + 1) pm[16'h0440 + i] = 16'hDEAD;
    rom_loaded = 1;
    @(posedge clk); start <= 1; @(posedge clk); start <= 0; repeat (200) @(posedge clk);
    chk("run after second start", run, 1);
    for (i = 0; i < 32; i = i + 1) if (pm[16'h0440 + i] !== 16'hDEAD) begin errors = errors + 1; $display("FAIL rom table word %0d overwritten with a ROM loaded", i); end
    chk("dsp released without the tables", dsp_rst_n, 1);
    if (errors == 0) $display("PASS tb_dsp_glue"); else $display("FAIL tb_dsp_glue: %0d errors", errors);
    $finish;
end
initial begin #20000000; $display("FAIL tb_dsp_glue: global timeout"); $finish; end
endmodule
