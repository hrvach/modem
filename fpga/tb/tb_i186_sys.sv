/*
tb_i186_sys.sv -- unit testbench for i186_sys (bus fabric + PCB
peripherals + DSP mailbox + EEPROM). FPGA-only: simulation support,
not synthesizable RTL. Pure SystemVerilog; run with
the Verilator tool --binary --timing (NOT --cc/--exe: this TB has its own
initial block, so Verilator generates the main).

What it checks (each expected value is from the C model, machine.c):
  1. harness RAM word + byte write/read (MEM 0x00100/0x00102)
  2. read-only flash pages: write to 0x80000 dropped, read returns
     the preloaded byte (0xA5A5)
  3. MMIO flash-ID: 0xFFFF0 -> 0x0089, 0xFFFF2 -> 0x4470
  4. split word at 0x0FFFF (byte0 -> MMIO hook, byte1 -> RAM)
  5. generic IO port store/readback (0x0C); port 0x12/0x14 DIP
     readback (0x9A / 0x4E with hw_idx=7); port 0x10 -> port_in
  6. DTE out via port 0x0A (0x41); dsp_start_req via port 0x18 = 4
  7. mailbox h2d byte/word readback (0x40/0x41)
  8. overlay burst: bytes 0x01..0x08 to 0x40..0x4E -> burst_valid
     and burst_data = 0x0807060504030201 (little-endian byte order,
     burst[0] = port 0x40 byte, as in machine.c dsp_bursts)
  9. PCB timer 0 + ICU: CMP=4, CON=0xE000 (EN+INT-en, one-shot) ->
     CON readback 0x2020 (MC set, EN cleared), irq_req=1 with
     irq_vec=0x08 (T0), irq_ack clears it
 10. PCB UART0: CMP=1, TDR=0x42 -> dte_out 0x42, STS reads 0x0028
     then 0x0008 (read clears 0xF4)
 11. EEPROM: load 0x1234 @0, 0x5678 @1, READ command -> 0x1234
     shifted out MSB-first, then 0x5678 (auto-increment)
 12. RELREG: IO 0xFFA8 = 0x1000 moves the PCB to MEM space
     (MEM 0x0FF02 reads the EOI sum = 0x0000); clearing it moves
     it back (MEM 0x0FF02 then goes to the harness hook)

The harness model is deliberately dumb: combinational ack, byte RAM,
flash-ID override. The sys is the unit under test.
*/
`timescale 1ns/1ps
`default_nettype none

module tb_i186_sys;
    logic clk = 1'b0, rst_n = 1'b0;

    /* CPU bus-master port (driven by the TB master tasks) */
    logic        bus_req = 1'b0, bus_wr = 1'b0, bus_word = 1'b0, bus_io = 1'b0;
    logic [19:0] bus_addr = 20'h00000;
    logic [15:0] bus_wdata = 16'h0000;
    logic [15:0] bus_rdata;
    logic        bus_ack;
    logic        irq_req;
    logic [7:0]  irq_vec;
    logic        irq_ack = 1'b0;
    logic [7:0]  irq_ack_vec = 8'h00;

    /* Model-time control: tick_en_i is tied high (the TB's clocks
       ARE model time -- no bus-latency overhead in the TB's
       combinational RAM); retire_i is pulsed after each bus write
       by the retire_pulse task below. */
    logic        retire_i = 1'b0;

    /* Harness port */
    logic        h_req, h_wr, h_word, h_is_mmio;
    logic [19:0] h_addr;
    logic [15:0] h_wdata, h_rdata;
    logic        h_ack;

    /* DTE / outside world */
    logic        dte_tx_valid;
    logic [7:0]  dte_tx_byte;
    logic        dte_rx_valid = 1'b0;
    logic [7:0]  dte_rx_byte = 8'h00;
    logic        line = 1'b1;
    logic        dsp_start_req;
    logic        burst_valid;
    logic [63:0] burst_data;

    /* Config (sv25 profile) */
    logic [7:0]  port_in_10 = 8'h00;
    logic [7:0]  port_in_12 = 8'h9A;
    logic [7:0]  port_in_14 = 8'h44;
    logic [3:0]  hw_idx = 4'd7;
    logic        ring_on = 1'b0;
    logic [63:0] hb_count = 64'd0;
    logic [63:0] hb_ticks = 64'd3;
    logic [7:0]  p2pin_in = 8'h40;

    /* EEPROM load */
    logic        ee_load_en = 1'b0;
    logic [7:0]  ee_load_addr = 8'h00;
    logic [15:0] ee_load_data = 16'h0000;

    logic [7:0]  dbg_evt;
    logic [15:0] dbg_h2d0, dbg_pcb_relreg;

    i186_sys dut (
        .clk(clk), .ce_i(1'b1), .rst_n(rst_n),
        .tick_en_i(1'b1), .retire_i(retire_i),
        .bus_req(bus_req), .bus_wr(bus_wr), .bus_word(bus_word),
        .bus_io(bus_io), .bus_addr(bus_addr), .bus_wdata(bus_wdata),
        .bus_rdata(bus_rdata), .bus_ack(bus_ack),
        .irq_req(irq_req), .irq_vec(irq_vec), .irq_ack(irq_ack),
        .irq_ack_vec(irq_ack_vec),
        .h_req(h_req), .h_wr(h_wr), .h_word(h_word), .h_is_mmio(h_is_mmio),
        .h_addr(h_addr), .h_wdata(h_wdata), .h_rdata(h_rdata), .h_ack(h_ack),
        .dte_tx_valid(dte_tx_valid), .dte_tx_byte(dte_tx_byte),
        .dte_rx_valid(dte_rx_valid), .dte_rx_byte(dte_rx_byte),
        .line(line), .dsp_start_req(dsp_start_req),
        .burst_valid(burst_valid), .burst_data(burst_data),
        .port_in_10(port_in_10), .port_in_12(port_in_12),
        .port_in_14(port_in_14), .hw_idx(hw_idx), .ring_on(ring_on),
        .hb_count(hb_count), .hb_ticks(hb_ticks), .p2pin_in(p2pin_in),
        .ee_load_en(ee_load_en), .ee_load_addr(ee_load_addr),
        .ee_load_data(ee_load_data),
        .dbg_evt(dbg_evt), .dbg_h2d0(dbg_h2d0), .dbg_pcb_relreg(dbg_pcb_relreg),
        .dsp_run_i(1'b0), .glue_rd_data_i(8'h00), .glue_rd_port_o(), .glue_rd_commit_o(), .glue_wr_commit_o(), .glue_wr_port_o(), .glue_wr_data_o(), .int0_set_i(1'b0)
    );

    /* Harness RAM model: 1 MB + 1 guard byte, combinational ack. */
    logic [7:0] ram [0:1048576];
    always_comb begin
        h_ack = h_req;
        if (h_req && !h_wr) begin
            if (h_addr == 20'hFFFF0) h_rdata = 16'h0089;
            else if (h_addr == 20'hFFFF2) h_rdata = 16'h4470;
            else h_rdata = {ram[{1'b0, h_addr} + 21'd1], ram[{1'b0, h_addr}]};
        end else begin
            h_rdata = 16'h0000;
        end
    end
    always @(posedge clk) begin
        if (h_req && h_wr) begin
            ram[{1'b0, h_addr}] <= h_wdata[7:0];
            if (h_word) ram[{1'b0, h_addr} + 21'd1] <= h_wdata[15:8];
        end
    end

    always #5 clk = ~clk;

    /*
    Sticky capture for one-cycle pulses (dte_tx_valid, dsp_start_req):
    a pulse fires during a bus write, before a polling task could see
    it, so the testbench latches it and checks the latch afterwards.
    */
    logic        dte_seen = 1'b0;
    logic [7:0]  dte_seen_byte = 8'h00;
    logic        dsp_start_seen = 1'b0;
    logic        dte_clear = 1'b0;
    logic        dsp_start_clear = 1'b0;
    always @(posedge clk) begin
        if (dte_clear) begin
            dte_seen <= 1'b0;
            dte_seen_byte <= 8'h00;
        end else if (dte_tx_valid) begin
            dte_seen <= 1'b1;
            dte_seen_byte <= dte_tx_byte;
        end
        if (dsp_start_clear) dsp_start_seen <= 1'b0;
        else if (dsp_start_req) dsp_start_seen <= 1'b1;
    end

    int errors = 0;
    int checks = 0;

    task automatic check(input string name, input logic [15:0] got,
                         input logic [15:0] exp);
        begin
            checks++;
            if (got !== exp) begin
                $display("FAIL %0s: got %h expected %h", name, got, exp);
                errors++;
            end else begin
                $display("PASS %0s: %h", name, got);
            end
        end
    endtask

    /* 64-bit variant, for the overlay-burst data word only. */
    task automatic check64(input string name, input logic [63:0] got,
                           input logic [63:0] exp);
        begin
            checks++;
            if (got !== exp) begin
                $display("FAIL %0s: got %h expected %h", name, got, exp);
                errors++;
            end else begin
                $display("PASS %0s: %h", name, got);
            end
        end
    endtask

    /* One bus write transaction (drive on negedge, wait for ack). */
    task automatic bus_write(input logic io, input logic word,
                             input logic [19:0] addr, input logic [15:0] data);
        begin
            @(negedge clk);
            bus_req = 1'b1;
            bus_wr = 1'b1;
            bus_word = word;
            bus_io = io;
            bus_addr = addr;
            bus_wdata = data;
            while (!bus_ack) @(negedge clk);
            @(negedge clk);
            bus_req = 1'b0;
            bus_wr = 1'b0;
            @(negedge clk);
            retire_pulse;
        end
    endtask

    /*
    Instruction-retire pulse (model time): the top pulses retire_i
    for one clock when pc_o changes (instruction boundary). The TB
    has no core, so each bus write is followed by a retire pulse,
    which applies any deferred timer/UART write from that
    transaction. The two trailing posedges let the DTE mux sample
    a pulse the retire produces (e.g. UART TDR -> dte_tx_valid)
    and the sticky pulse latches capture it; the final negedge
    leaves the latches settled before any check runs.
    */
    task automatic retire_pulse;
        begin
            @(negedge clk); retire_i = 1'b1;
            @(posedge clk);           /* retire edge: deferred writes apply */
            @(negedge clk); retire_i = 1'b0;
            @(posedge clk);           /* DTE mux samples the retire pulse */
            @(posedge clk);           /* sticky latches capture dte_tx_valid */
            @(negedge clk);           /* latches settled */
        end
    endtask

    /* One bus read transaction; data is valid while ack is high. */
    task automatic bus_read(input logic io, input logic word,
                            input logic [19:0] addr, output logic [15:0] data);
        begin
            @(negedge clk);
            bus_req = 1'b1;
            bus_wr = 1'b0;
            bus_word = word;
            bus_io = io;
            bus_addr = addr;
            bus_wdata = 16'h0000;
            while (!bus_ack) @(negedge clk);
            data = bus_rdata;
            @(negedge clk);
            bus_req = 1'b0;
            @(negedge clk);
        end
    endtask

    /* Clear the sticky pulse latches (one clock each). */
    task automatic clear_pulse_seen;
        begin
            @(negedge clk);
            dte_clear = 1'b1;
            dsp_start_clear = 1'b1;
            @(negedge clk);
            dte_clear = 1'b0;
            dsp_start_clear = 1'b0;
        end
    endtask

    /* Check that a DTE byte was transmitted since the last clear. */
    task automatic check_dte_tx(input string seen_name, input string byte_name,
                                input logic [7:0] exp_byte);
        int wait_clks;
        begin
            wait_clks = 0;
            while (!dte_seen && wait_clks < 20) begin
                @(negedge clk);
                wait_clks++;
            end
            check(seen_name, {15'b0, dte_seen}, 16'd1);
            check(byte_name, {8'b0, dte_seen_byte}, {8'b0, exp_byte});
        end
    endtask

    /*
    EEPROM helpers: P1LTCH is pcb 0x56 (CS bit5, CLK bit2), DI is
    pcb 0x5E bit7, DO is read from pcb 0x5A bit7 (pcb 0x58 bit7 = 1
    selects the EEPROM DO). All PCB accesses are IO 0xFF00+reg.
    */
    task automatic ee_clock_bit(input logic di);
        begin
            /* Set DI, then pulse CLK (rising edge clocks the bit). */
            bus_write(1'b1, 1'b0, 20'hFF5E, di ? 16'h0080 : 16'h0000);
            bus_write(1'b1, 1'b0, 20'hFF56, 16'h0024);
            bus_write(1'b1, 1'b0, 20'hFF56, 16'h0020);
        end
    endtask

    task automatic ee_read_word(output logic [15:0] w);
        logic [15:0] preg_read;
        logic [15:0] do_bit_value;
        int bit_index;
        begin
            w = 16'h0000;
            for (bit_index = 0; bit_index < 16; bit_index++) begin
                bus_write(1'b1, 1'b0, 20'hFF56, 16'h0024); /* CLK=1 */
                bus_read(1'b1, 1'b0, 20'hFF5A, preg_read); /* DO on bit7 */
                bus_write(1'b1, 1'b0, 20'hFF56, 16'h0020); /* CLK=0 */
                do_bit_value = {15'b0, preg_read[7]};
                w = {w[14:0], do_bit_value[0]};
            end
        end
    endtask

    logic [15:0] read_data;
    logic [15:0] eeprom_word0, eeprom_word1;
    /* Scoreboard for the random differential test. */
    logic [15:0] generic_port_model [0:127];
    logic [15:0] h2d_model [0:7];

    initial begin
        /* Preload the harness RAM (flash page content for the RO test). */
        ram[21'h80000] = 8'hA5;
        ram[21'h80001] = 8'hA5;

        /*
        EEPROM load while reset is held (harness writes ee_w).
        Load inputs change on the negedge: changing them right after
        a posedge would race the DUT's always_ff at that same edge
        and lose the first word.
        */
        ee_load_en = 1'b1;
        ee_load_addr = 8'h00;
        ee_load_data = 16'h1234;
        @(posedge clk);
        @(negedge clk);
        ee_load_addr = 8'h01;
        ee_load_data = 16'h5678;
        @(posedge clk);
        @(negedge clk);
        ee_load_en = 1'b0;

        /* Reset: 4 clocks, then release. */
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        /* --- 1. Harness RAM word + byte write/read --- */
        bus_write(1'b0, 1'b1, 20'h00100, 16'h1234);
        bus_read(1'b0, 1'b1, 20'h00100, read_data);
        check("ram word 0x100", read_data, 16'h1234);
        bus_write(1'b0, 1'b0, 20'h00102, 16'h00AB);
        bus_read(1'b0, 1'b1, 20'h00102, read_data);
        check("ram byte 0x102", read_data, 16'h00AB);

        /* --- 2. Read-only flash page: write dropped --- */
        bus_write(1'b0, 1'b1, 20'h80000, 16'hFFFF);
        bus_read(1'b0, 1'b1, 20'h80000, read_data);
        check("ro page 0x80000", read_data, 16'hA5A5);

        /* --- 3. MMIO flash-ID --- */
        bus_read(1'b0, 1'b1, 20'hFFFF0, read_data);
        check("flash id 0xFFFF0", read_data, 16'h0089);
        bus_read(1'b0, 1'b1, 20'hFFFF2, read_data);
        check("flash id 0xFFFF2", read_data, 16'h4470);

        /* --- 4. Split word at 0x0FFFF (MMIO hook + RAM) --- */
        bus_write(1'b0, 1'b1, 20'h0FFFF, 16'hBEEF);
        bus_read(1'b0, 1'b1, 20'h0FFFF, read_data);
        check("split word 0xFFFF", read_data, 16'hBEEF);

        /* --- 5. IO ports --- */
        bus_write(1'b1, 1'b0, 20'h0000C, 16'h00AB);
        bus_read(1'b1, 1'b0, 20'h0000C, read_data);
        check("port 0x0C readback", read_data, 16'h00AB);
        bus_read(1'b1, 1'b0, 20'h00012, read_data);
        check("port 0x12 DIP", read_data, 16'h009A);
        bus_read(1'b1, 1'b0, 20'h00010, read_data);
        check("port 0x10 port_in", read_data, 16'h0000);
        bus_write(1'b1, 1'b0, 20'h00014, 16'h00F5);
        bus_read(1'b1, 1'b0, 20'h00014, read_data);
        check("port 0x14 computed", read_data, 16'h004E);

        /* --- 6. DTE out + DSP start (one-cycle pulses, sticky latch) --- */
        clear_pulse_seen();
        bus_write(1'b1, 1'b0, 20'h0000A, 16'h0041);
        check_dte_tx("dte out 0x0A seen", "dte out 0x0A byte", 8'h41);
        /* Port 0x18 = 4 starts the DSP (dsp_start_req pulses). */
        clear_pulse_seen();
        bus_write(1'b1, 1'b0, 20'h00018, 16'h0004);
        repeat (4) @(posedge clk);
        check("dsp start seen", {15'b0, dsp_start_seen}, 16'd1);

        /*
        --- 7. Mailbox h2d (C machine_iowr: even ports only, byte
        select on port bit 1; h2d[0] = ports 0x40/0x42). The 186-side
        read returns the generic port store, so h2d is observed via
        dbg_h2d0. An odd-port write must not touch h2d. ---
        */
        bus_write(1'b1, 1'b0, 20'h00040, 16'h0055);
        bus_read(1'b1, 1'b0, 20'h00040, read_data);
        check("h2d byte 0x40", read_data, 16'h0055);
        bus_write(1'b1, 1'b0, 20'h00042, 16'h00AA);
        check("dbg_h2d0", dbg_h2d0, 16'hAA55);
        bus_write(1'b1, 1'b0, 20'h00041, 16'h00FF);
        check("dbg_h2d0 odd ignored", dbg_h2d0, 16'hAA55);

        /* --- 8. Overlay burst (0x40..0x4E, 8 bytes) --- */
        bus_write(1'b1, 1'b0, 20'h00040, 16'h0001);
        bus_write(1'b1, 1'b0, 20'h00042, 16'h0002);
        bus_write(1'b1, 1'b0, 20'h00044, 16'h0003);
        bus_write(1'b1, 1'b0, 20'h00046, 16'h0004);
        bus_write(1'b1, 1'b0, 20'h00048, 16'h0005);
        bus_write(1'b1, 1'b0, 20'h0004A, 16'h0006);
        bus_write(1'b1, 1'b0, 20'h0004C, 16'h0007);
        /*
        The 0x4E write completes the burst; burst_valid pulses for
        one cycle during the commit, so sample it right after.
        */
        @(negedge clk);
        bus_req = 1'b1;
        bus_wr = 1'b1;
        bus_word = 1'b0;
        bus_io = 1'b1;
        bus_addr = 20'h0004E;
        bus_wdata = 16'h0008;
        while (!bus_ack) @(negedge clk);
        /* burst_valid is high during the commit cycle (ack cycle). */
        check("burst valid", {15'b0, burst_valid}, 16'd1);
        check64("burst data", burst_data, 64'h0807060504030201);
        @(negedge clk);
        bus_req = 1'b0;
        bus_wr = 1'b0;

        /*
        --- 9. PCB timer 0 + ICU ---
        Unmask T0 (IMASK 0x08 = 0), primsk 0x0A = 7, con 0x12 = 0.
        */
        bus_write(1'b1, 1'b0, 20'hFF08, 16'h0000);
        bus_write(1'b1, 1'b0, 20'hFF0A, 16'h0007);
        bus_write(1'b1, 1'b0, 20'hFF12, 16'h0000);
        /*
        Timer 0: CMP (0x32) = 4, CON (0x36) = 0xE000 (EN + INT-en,
        one-shot: CONT bit0 = 0). CON stores (v & 0x3FFF) | EN.
        */
        bus_write(1'b1, 1'b0, 20'hFF32, 16'h0004);
        bus_write(1'b1, 1'b1, 20'hFF36, 16'hE000);
        repeat (200) @(posedge clk);
        bus_read(1'b1, 1'b1, 20'hFF36, read_data);
        check("timer0 CON after hit", read_data, 16'h2020);
        check("irq_req after timer hit", {15'b0, irq_req}, 16'd1);
        check("irq_vec T0", {8'b0, irq_vec}, 16'h08);
        /* Acknowledge: core pulses irq_ack, the source leaves service. */
                @(negedge clk);
        irq_ack_vec = irq_vec;
        irq_ack = 1'b1;
                @(negedge clk);
        irq_ack = 1'b0;
        repeat (2) @(posedge clk);
        check("irq_req after ack", {15'b0, irq_req}, 16'd0);

        /*
        --- 10. PCB UART0 ---
        CMP (0x60) = 1 -> pu = 16, TX = 160 cycles. TDR is 0x6A.
        */
        bus_write(1'b1, 1'b0, 20'hFF60, 16'h0001);
        clear_pulse_seen();
        bus_write(1'b1, 1'b0, 20'hFF6A, 16'h0042);
        check_dte_tx("uart0 dte seen", "uart0 dte byte", 8'h42);
        repeat (300) @(posedge clk);
        bus_read(1'b1, 1'b0, 20'hFF66, read_data);
        check("uart0 STS after TX", read_data, 16'h0028);
        bus_read(1'b1, 1'b0, 20'hFF66, read_data);
        check("uart0 STS 2nd read", read_data, 16'h0008);

        /*
        --- 11. EEPROM: READ word 0 (0x1234), then word 1 (0x5678) ---
        DO source = ee_do_bit (pcb 0x58 bit7 = 1).
        */
        bus_write(1'b1, 1'b0, 20'hFF58, 16'h0080);
        /* CS=1 (also resets the EEPROM state machine). */
        bus_write(1'b1, 1'b0, 20'hFF56, 16'h0020);
        /*
        Command: start bit 1, then op 1,0 (READ) and addr 0x00
        (8 bits MSB-first) = 11 clocks total.
        */
        ee_clock_bit(1'b1);
        ee_clock_bit(1'b1);
        ee_clock_bit(1'b0);
        for (int i = 0; i < 8; i++) ee_clock_bit(1'b0);
        ee_read_word(eeprom_word0);
        check("eeprom word 0", eeprom_word0, 16'h1234);
        ee_read_word(eeprom_word1);
        check("eeprom word 1", eeprom_word1, 16'h5678);

        /* --- 12. RELREG: move the PCB to MEM space --- */
        bus_write(1'b1, 1'b1, 20'hFFA8, 16'h1000);
        check("dbg relreg", dbg_pcb_relreg, 16'h1000);
        /* MEM 0x0FF02 now reads the PCB EOI register (sum = 0). */
        bus_read(1'b0, 1'b1, 20'h0FF02, read_data);
        check("mem 0xFF02 via PCB", read_data, 16'h0000);
        /*
        Move it back. After RELREG set, IO 0xFF00+ no longer
        reaches the PCB (it moved to MEM space), so the clear must
        be a MEM write to 0x0FFA8. MEM 0x0FF02 then goes to the
        harness hook again (harness RAM at 0x0FF02 is 0x0000).
        */
        bus_write(1'b0, 1'b1, 20'h0FFA8, 16'h0000);
        check("dbg relreg cleared", dbg_pcb_relreg, 16'h0000);
        bus_read(1'b0, 1'b1, 20'h0FF02, read_data);
        check("mem 0xFF02 via hook", read_data, 16'h0000);

        /*
        --- 13. Random differential sweep (fixed seed). Generic IO
        ports, low RAM, and mailbox h2d[0] (ports 0x40/0x42) with a
        testbench-side scoreboard. The same seed against the
        reference RTL in tb/reference-pre-house-rules must produce
        an identical log: that is the equivalence proof for the
        house-rules restyle. Special ports (0x0A DTE, 0x10/0x12/0x14
        DIP, 0x18 DSP start, 0x1C/0x1E evt/ovl, 0x56/0x58/0x5A/0x5E
        EEPROM, 0xA8 RELREG) are excluded: they have side effects
        the scoreboard does not model. ---
        */
        begin
            int rand_seed;
            int rand_iter;
            int rand_choice;
            int rand_pick;
            int rand_port;
            int rand_is_word;
            int rand_addr;
            logic [15:0] rand_value;
            logic [15:0] rand_expect;
            string rand_name;
            /*
            Scoreboard starts from the directed-test state: port
            0x0C holds 0x00AB (test 5); h2d[0] holds 0x0201 (the
            burst test wrote 0x01 to 0x40 and 0x02 to 0x42).
            */
            generic_port_model[12] = 16'h00AB;
            h2d_model[0] = 16'h0201;
            rand_seed = 32'h12345678;
            for (rand_iter = 0; rand_iter < 200; rand_iter++) begin
                rand_choice = ($random(rand_seed) & 32'h7FFFFFFF) % 3;
                if (rand_choice == 0) begin
                    /*
                    Generic IO port, 80 choices: 0x00-0x09 and
                    0x0B-0x0F (15), 0x16 (1), 0x20-0x3F (32),
                    0x60-0x7F (32).
                    */
                    rand_pick = ($random(rand_seed) & 32'h7FFFFFFF) % 80;
                    if (rand_pick < 15) begin
                        rand_port = rand_pick;
                        if (rand_port >= 10) rand_port = rand_port + 1;
                    end else if (rand_pick < 16) begin
                        rand_port = 22;
                    end else if (rand_pick < 48) begin
                        rand_port = 32 + (rand_pick - 16);
                    end else begin
                        rand_port = 96 + (rand_pick - 48);
                    end
                    rand_is_word = ($random(rand_seed) & 32'h7FFFFFFF) % 2;
                    rand_value = 16'($random(rand_seed));
                    if (rand_is_word == 1)
                        bus_write(1'b1, 1'b1, {12'b0, rand_port[7:0]}, rand_value);
                    else
                        bus_write(1'b1, 1'b0, {12'b0, rand_port[7:0]}, rand_value);
                    if (rand_is_word == 1)
                        generic_port_model[rand_port] = rand_value;
                    else
                        generic_port_model[rand_port] = {8'b0, rand_value[7:0]};
                    rand_name = $sformatf("rand port %0d", rand_port);
                    if (rand_is_word == 1) begin
                        bus_read(1'b1, 1'b1, {12'b0, rand_port[7:0]}, read_data);
                        rand_expect = generic_port_model[rand_port];
                    end else begin
                        bus_read(1'b1, 1'b0, {12'b0, rand_port[7:0]}, read_data);
                        rand_expect = generic_port_model[rand_port] & 16'h00FF;
                    end
                    /* Port 0x00 reads back with bit 3 forced to 0. */
                    if (rand_port == 0) rand_expect = rand_expect & ~16'h0008;
                    check(rand_name, read_data, rand_expect);
                end else if (rand_choice == 1) begin
                    /* Low RAM word/byte, word-aligned, 0..1020. */
                    rand_addr = ($random(rand_seed) & 32'h7FFFFFFF) % 1024;
                    rand_addr = {12'b0, rand_addr[19:2], 2'b00};
                    rand_is_word = ($random(rand_seed) & 32'h7FFFFFFF) % 2;
                    rand_value = 16'($random(rand_seed));
                    rand_name = $sformatf("rand ram %0d", rand_addr);
                    if (rand_is_word == 1) begin
                        bus_write(1'b0, 1'b1, rand_addr[19:0], rand_value);
                        bus_read(1'b0, 1'b1, rand_addr[19:0], read_data);
                        check(rand_name, read_data, rand_value);
                    end else begin
                        bus_write(1'b0, 1'b0, rand_addr[19:0], rand_value);
                        bus_read(1'b0, 1'b0, rand_addr[19:0], read_data);
                        check(rand_name, read_data, rand_value & 16'h00FF);
                    end
                end else begin
                    /* Mailbox h2d[0] via ports 0x40 (low) / 0x42 (high). */
                    rand_port = (($random(rand_seed) & 32'h7FFFFFFF) % 2 == 0) ? 64 : 66;
                    rand_value = 16'($random(rand_seed));
                    bus_write(1'b1, 1'b0, {12'b0, rand_port[7:0]}, rand_value);
                    if (rand_port == 64)
                        h2d_model[0] = {h2d_model[0][15:8], rand_value[7:0]};
                    else
                        h2d_model[0] = {rand_value[7:0], h2d_model[0][7:0]};
                    rand_name = $sformatf("rand h2d0 %0d", rand_port);
                    check(rand_name, dbg_h2d0, h2d_model[0]);
                end
            end
        end

        $display("TB DONE: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("TB PASS");
        else $display("TB FAIL");
        $finish;
    end

    /* Watchdog: the TB must finish. */
    initial begin
        #2000000;
        $display("TB TIMEOUT");
        $finish;
    end
endmodule
`default_nettype wire
