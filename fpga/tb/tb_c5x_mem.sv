/*
tb_c5x_mem.sv -- self-contained testbench for c5x_mem.

Run: verilator --binary --timing --top-module tb_c5x_mem \
       tb/tb_c5x_mem.sv rtl/c5x_mem.sv && ./obj_dir/Vtb_c5x_mem

Timing discipline: inputs are driven on the falling edge of clk
(100 MHz, `always #5`), combinational outputs are sampled 2 ns
later, registered outputs are sampled on the next falling edge.
Every vector cites its source: the C function + line in
c-port/c/src/dsp/c5x_core.c, or the audit doc section
(c5x_core_audit/07e-core3-peripherals-memory.md).

Models in this bench: an external-MMR owner (register file, the
AR/IMR/IFR/PMST/RPTC/... registers owned by agents 1-3) and a host
I/O model (codec / 186 mailbox) that acks o_io_req after 2 cycles
and answers reads from io_read_model().  Firmware is loaded
through the program-write port, as the module header requires;
there is no $readmemh into the arrays.

NOTE: same-cycle same-address read-during-write cannot be driven
through this interface -- the arbiter serves at most one request
per memory per cycle, so a read and a write to the same memory
never coincide.  The M10K template guarantees old data if they
ever did; there is no vector for it here.
*/

`default_nettype none
`timescale 1ns/1ps

module tb_c5x_mem;

    logic clk = 1'b0;
    logic rst_n;

    always #5 clk = ~clk;

    /*
    Addresses and constants the vectors use (c5x_core.c mmr_rd/mmr_wr
    switch, c5x_core.c:620-797).  Registers keep their manual names.
    Arbitrary test addresses and test data stay literal below: they are
    the vectors themselves, explained by each test comment.
    */
    localparam logic [15:0] MMR_GREG_ADDR  = 16'h0005;
    localparam logic [15:0] MMR_RPTC_ADDR  = 16'h0008;
    localparam logic [15:0] MMR_AR0_ADDR   = 16'h0010;
    localparam logic [15:0] MMR_PMST_ADDR  = 16'h0007;
    localparam logic [15:0] MMR_TREG0_ADDR = 16'h000C;
    localparam logic [15:0] MMR_DRR_ADDR   = 16'h0020;
    localparam logic [15:0] MMR_DXR_ADDR   = 16'h0021;
    localparam logic [15:0] MMR_SPC_ADDR   = 16'h0022;
    localparam logic [15:0] MMR_TIM_ADDR   = 16'h0024;
    localparam logic [15:0] MMR_PRD_ADDR   = 16'h0025;
    localparam logic [15:0] MMR_TCR_ADDR   = 16'h0026;
    localparam logic [15:0] MMR_PDWSR_ADDR = 16'h0028;
    localparam logic [15:0] MMR_IOWSR_ADDR = 16'h0029;
    localparam logic [15:0] MMR_CWSR_ADDR  = 16'h002A;
    /* Host I/O model: ack delay, bus timeout, read-data base (see below). */
    localparam int IO_ACK_DELAY_CYCLES = 2;
    localparam int ACK_TIMEOUT_CYCLES  = 20;
    localparam logic [15:0] IO_READ_BASE = 16'hC000;
    /* External-MMR owner model: 64 registers, values 0xE000 + index. */
    localparam int EXT_MMR_COUNT = 64;
    localparam logic [15:0] EXT_MMR_BASE = 16'hE000;
    /* Host-write capture: one word per 16-bit I/O address. */
    localparam int IO_ADDR_COUNT = 65536;

    /* DUT inputs */
    logic        cnf, ovly, ram;
    logic        xint_mode;
    logic        tick;
    logic        ser_tick;
    logic [15:0] ser_rx;
    logic        replay_active;
    logic [15:0] replay_lo, replay_hi;
    logic        dm_req, dm_rd, dm_dmov;
    logic [15:0] dm_dmov_src, dm_addr, dm_wdata;
    logic        pm_fetch_req;
    logic [15:0] pm_fetch_addr;
    logic        pm_wr_req;
    logic [15:0] pm_wr_addr, pm_wr_data;
    logic [15:0] ext_mmr_rdata;
    logic        io_ack;
    logic [15:0] io_rdata;

    /* DUT outputs */
    logic [15:0] dm_rdata;
    logic        dm_ack;
    logic [2:0]  dm_io_ws;
    logic        dm_periph_ws;
    logic [15:0] pm_fetch_data;
    logic        pm_fetch_ack;
    logic        pm_wr_ack;
    logic        ext_mmr_rd, ext_mmr_wr;
    logic [15:0] ext_mmr_addr, ext_mmr_wdata;
    logic        io_req, io_rd;
    logic [15:0] io_addr, io_wdata;
    logic        tint_pulse, rint_pulse, xint_pulse;
    logic [63:0] timer_exp_cnt;
    logic        dxr_wr;
    logic [15:0] dxr_wdata;
    logic        pm_epoch_inc, replay_dirty_pulse;
    logic [15:0] obs_greg, obs_drr, obs_dxr, obs_spc, obs_tim;
    logic [15:0] obs_prd, obs_tcr, obs_pdwsr, obs_iowsr, obs_cwsr;

    c5x_mem dut (
        .clk                (clk),
        .ce_i (1'b1),
        .rst_n              (rst_n),
        .i_cnf              (cnf),
        .i_ovly             (ovly),
        .i_ram              (ram),
        .i_xint_mode        (xint_mode),
        .i_tick             (tick),
        .i_tick2            (1'b0),
        .i_ser_tick         (ser_tick),
        .i_ser_rx           (ser_rx),
        .i_replay_active    (replay_active),
        .i_replay_lo        (replay_lo),
        .i_replay_hi        (replay_hi),
        .i_dm_req           (dm_req),
        .i_dm_rd            (dm_rd),
        .i_dm_dmov          (dm_dmov),
        .i_dm_dmov_src      (dm_dmov_src),
        .i_dm_addr          (dm_addr),
        .i_dm_wdata         (dm_wdata),
        .o_dm_rdata         (dm_rdata),
        .o_dm_ack           (dm_ack),
        .o_dm_io_ws         (dm_io_ws),
        .o_dm_periph_ws     (dm_periph_ws),
        .i_pm_fetch_req     (pm_fetch_req),
        .i_pm_fetch_addr    (pm_fetch_addr),
        .o_pm_fetch_data    (pm_fetch_data),
        .o_pm_fetch_ack     (pm_fetch_ack),
        .i_pm_wr_req        (pm_wr_req),
        .i_pm_wr_addr       (pm_wr_addr),
        .i_pm_wr_data       (pm_wr_data),
        .o_pm_wr_ack        (pm_wr_ack),
        .i_ext_mmr_rdata    (ext_mmr_rdata),
        .o_ext_mmr_rd       (ext_mmr_rd),
        .o_ext_mmr_wr       (ext_mmr_wr),
        .o_ext_mmr_addr     (ext_mmr_addr),
        .o_ext_mmr_wdata    (ext_mmr_wdata),
        .o_io_req           (io_req),
        .o_io_rd            (io_rd),
        .o_io_addr          (io_addr),
        .o_io_wdata         (io_wdata),
        .i_io_ack           (io_ack),
        .i_io_rdata         (io_rdata),
        .o_tint_pulse       (tint_pulse),
        .o_rint_pulse       (rint_pulse),
        .o_xint_pulse       (xint_pulse),
        .o_timer_exp_cnt    (timer_exp_cnt),
        .o_dxr_wr           (dxr_wr),
        .o_dxr_wdata        (dxr_wdata),
        .o_pm_epoch_inc     (pm_epoch_inc),
        .o_replay_dirty_pulse (replay_dirty_pulse),
        .o_obs_greg         (obs_greg),
        .o_obs_drr          (obs_drr),
        .o_obs_dxr          (obs_dxr),
        .o_obs_spc          (obs_spc),
        .o_obs_tim          (obs_tim),
        .o_obs_prd          (obs_prd),
        .o_obs_tcr          (obs_tcr),
        .o_obs_pdwsr        (obs_pdwsr),
        .o_obs_iowsr        (obs_iowsr),
        .o_obs_cwsr         (obs_cwsr)
    );

    /*
    ------------------------------------------------------------------
    External-MMR owner model (agents 1-3 registers: IMR, IFR, PMST,
    RPTC, BRCR, PASR, PAER, TREG0-2, DBMR, ARs, INDX, ARCR, CBSR,
    CBER, CBCR, BMAR).  Combinational read, synchronous write.
    ------------------------------------------------------------------
    */
    logic [15:0] ext_mmr [0:EXT_MMR_COUNT-1];
    initial begin
        for (int i = 0; i < EXT_MMR_COUNT; i++) ext_mmr[i] = EXT_MMR_BASE + i[15:0];
    end
    always_comb ext_mmr_rdata = ext_mmr[ext_mmr_addr[5:0]];
    always_ff @(posedge clk) begin
        if (ext_mmr_wr)
            ext_mmr[ext_mmr_addr[5:0]] <= ext_mmr_wdata;
    end

    /*
    ------------------------------------------------------------------
    Host I/O model (codec / 186 mailbox).  Level handshake: ack 2
    cycles after o_io_req rises, held until o_io_req drops.  Reads
    answer 0xC000 | port[7:0]; writes are captured for checking.
    ------------------------------------------------------------------
    */
    function automatic logic [15:0] io_read_model(input logic [15:0] a);
        begin
            io_read_model = IO_READ_BASE | {8'b00000000, a[7:0]};
        end
    endfunction

    logic [15:0] io_written_mem [0:IO_ADDR_COUNT-1];
    integer io_delay;
    logic io_ack_active;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            io_ack_active <= 1'b0;
            io_ack <= 1'b0;
            io_rdata <= 16'h0000;
            io_delay <= 0;
        end else begin
            if (io_req && !io_ack_active) begin
                if (io_delay == IO_ACK_DELAY_CYCLES) begin
                    io_ack_active <= 1'b1;
                    io_ack <= 1'b1;
                    io_rdata <= io_read_model(io_addr);
                end else begin
                    io_delay <= io_delay + 1;
                end
            end else if (!io_req) begin
                io_ack_active <= 1'b0;
                io_ack <= 1'b0;
                io_delay <= 0;
            end
            if (io_req && io_ack && !io_rd)
                io_written_mem[io_addr] <= io_wdata;
        end
    end

    /*
    ------------------------------------------------------------------
    Scoreboard
    ------------------------------------------------------------------
    */
    integer passes = 0;
    integer fails = 0;

    task check(input string name, input logic [15:0] got,
               input logic [15:0] exp);
        begin
            if (got !== exp) begin
                $display("FAIL %0s: got %0h exp %0h", name, got, exp);
                fails = fails + 1;
            end else begin
                passes = passes + 1;
            end
        end
    endtask

    task check64(input string name, input logic [63:0] got,
               input logic [63:0] exp);
        begin
            if (got !== exp) begin
                $display("FAIL %0s: got %0h exp %0h", name, got, exp);
                fails = fails + 1;
            end else begin
                passes = passes + 1;
            end
        end
    endtask

    /* Combinational outputs captured during the presented cycle. */
    logic cap_tint, cap_rint, cap_xint, cap_dxrwr, cap_epoch, cap_dirty;
    logic cap_extrd, cap_extwr, cap_periph;
    logic [2:0] cap_iows;

    task capture_comb;
        begin
            cap_tint = tint_pulse;
            cap_rint = rint_pulse;
            cap_xint = xint_pulse;
            cap_dxrwr = dxr_wr;
            cap_epoch = pm_epoch_inc;
            cap_dirty = replay_dirty_pulse;
            cap_extrd = ext_mmr_rd;
            cap_extwr = ext_mmr_wr;
            cap_periph = dm_periph_ws;
            cap_iows = dm_io_ws;
        end
    endtask

    /*
    ------------------------------------------------------------------
    Bus tasks
    ------------------------------------------------------------------
    */
    task do_reset;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            cnf = 1'b0; ovly = 1'b0; ram = 1'b0;
            xint_mode = 1'b0; tick = 1'b0; ser_tick = 1'b0; ser_rx = 16'h0;
            replay_active = 1'b0; replay_lo = 16'h0; replay_hi = 16'h0;
            dm_req = 1'b0; dm_rd = 1'b0; dm_dmov = 1'b0;
            dm_dmov_src = 16'h0; dm_addr = 16'h0; dm_wdata = 16'h0;
            pm_fetch_req = 1'b0; pm_fetch_addr = 16'h0;
            pm_wr_req = 1'b0; pm_wr_addr = 16'h0; pm_wr_data = 16'h0;
            repeat (3) @(negedge clk);
            rst_n = 1'b1;
            @(negedge clk);
        end
    endtask

    task dm_access(input logic rd, input logic [15:0] addr,
                   input logic [15:0] wdata, input logic dmov,
                   input logic [15:0] dmov_src,
                   output logic [15:0] rdata);
        integer timeout;
        begin
            @(negedge clk);
            dm_req = 1'b1; dm_rd = rd; dm_dmov = dmov;
            dm_dmov_src = dmov_src; dm_addr = addr; dm_wdata = wdata;
            #2 capture_comb;
            timeout = 0;
            while (!dm_ack && timeout < ACK_TIMEOUT_CYCLES) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!dm_ack) begin
                $display("FAIL dm_access timeout addr=%04h rd=%0d", addr, rd);
                fails = fails + 1;
                rdata = 16'hXXXX;
            end else begin
                rdata = dm_rdata;
            end
            @(negedge clk);
            dm_req = 1'b0; dm_dmov = 1'b0;
        end
    endtask

    task dm_write(input logic [15:0] addr, input logic [15:0] data);
        logic [15:0] dummy;
        begin
            dm_access(1'b0, addr, data, 1'b0, 16'h0000, dummy);
        end
    endtask

    task dm_read(input logic [15:0] addr, output logic [15:0] rdata);
        begin
            dm_access(1'b1, addr, 16'h0000, 1'b0, 16'h0000, rdata);
        end
    endtask

    task dm_dmov_write(input logic [15:0] src, input logic [15:0] dest,
                       input logic [15:0] data);
        logic [15:0] dummy;
        begin
            dm_access(1'b0, dest, data, 1'b1, src, dummy);
        end
    endtask

    task pm_fetch(input logic [15:0] addr, output logic [15:0] data);
        integer timeout;
        begin
            @(negedge clk);
            pm_fetch_req = 1'b1; pm_fetch_addr = addr;
            timeout = 0;
            while (!pm_fetch_ack && timeout < ACK_TIMEOUT_CYCLES) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!pm_fetch_ack) begin
                $display("FAIL pm_fetch timeout addr=%04h", addr);
                fails = fails + 1;
                data = 16'hXXXX;
            end else begin
                data = pm_fetch_data;
            end
            @(negedge clk);
            pm_fetch_req = 1'b0;
        end
    endtask

    task pm_write(input logic [15:0] addr, input logic [15:0] data);
        integer timeout;
        begin
            @(negedge clk);
            pm_wr_req = 1'b1; pm_wr_addr = addr; pm_wr_data = data;
            #2 capture_comb;
            timeout = 0;
            while (!pm_wr_ack && timeout < ACK_TIMEOUT_CYCLES) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!pm_wr_ack) begin
                $display("FAIL pm_write timeout addr=%04h", addr);
                fails = fails + 1;
            end
            @(negedge clk);
            pm_wr_req = 1'b0;
        end
    endtask

    task tick1;
        begin
            @(negedge clk);
            tick = 1'b1;
            #2 capture_comb;
            @(negedge clk);
            tick = 1'b0;
        end
    endtask

    task tick_n(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i++) tick1;
        end
    endtask

    task ser_tick1(input logic [15:0] rx);
        begin
            @(negedge clk);
            ser_tick = 1'b1; ser_rx = rx;
            #2 capture_comb;
            @(negedge clk);
            ser_tick = 1'b0;
        end
    endtask

    /*
    Fetch and data write to the same memory in the same cycle:
    data wins, fetch is latched and served after.
    */
    task fetch_vs_data(input logic [15:0] faddr, input logic [15:0] daddr,
                       input logic [15:0] ddata,
                       output logic [15:0] fdata);
        integer timeout;
        begin
            @(negedge clk);
            pm_fetch_req = 1'b1; pm_fetch_addr = faddr;
            dm_req = 1'b1; dm_rd = 1'b0; dm_dmov = 1'b0;
            dm_addr = daddr; dm_wdata = ddata;
            @(negedge clk);
            dm_req = 1'b0; pm_fetch_req = 1'b0;
            timeout = 0;
            while (!pm_fetch_ack && timeout < ACK_TIMEOUT_CYCLES) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!pm_fetch_ack) begin
                $display("FAIL fetch_vs_data timeout faddr=%04h", faddr);
                fails = fails + 1;
                fdata = 16'hXXXX;
            end else begin
                fdata = pm_fetch_data;
            end
            @(negedge clk);
        end
    endtask

    /*
    Program write and fetch to the same memory in the same cycle:
    pm_wr wins, fetch is latched and served after.
    */
    task pmwr_vs_fetch(input logic [15:0] waddr, input logic [15:0] wdata,
                       input logic [15:0] faddr,
                       output logic [15:0] fdata);
        integer timeout;
        begin
            @(negedge clk);
            pm_wr_req = 1'b1; pm_wr_addr = waddr; pm_wr_data = wdata;
            pm_fetch_req = 1'b1; pm_fetch_addr = faddr;
            @(negedge clk);
            pm_wr_req = 1'b0; pm_fetch_req = 1'b0;
            timeout = 0;
            while (!pm_fetch_ack && timeout < ACK_TIMEOUT_CYCLES) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (!pm_fetch_ack) begin
                $display("FAIL pmwr_vs_fetch timeout faddr=%04h", faddr);
                fails = fails + 1;
                fdata = 16'hXXXX;
            end else begin
                fdata = pm_fetch_data;
            end
            @(negedge clk);
        end
    endtask

    /*
    ------------------------------------------------------------------
    Tests
    ------------------------------------------------------------------
    */
    logic [15:0] rdata, fdata;
    logic [63:0] exp_cnt_before;
    integer i;

    initial begin
        rst_n = 1'b0;
        cnf = 1'b0; ovly = 1'b0; ram = 1'b0;
        xint_mode = 1'b0; tick = 1'b0; ser_tick = 1'b0; ser_rx = 16'h0;
        replay_active = 1'b0; replay_lo = 16'h0; replay_hi = 16'h0;
        dm_req = 1'b0; dm_rd = 1'b0; dm_dmov = 1'b0;
        dm_dmov_src = 16'h0; dm_addr = 16'h0; dm_wdata = 16'h0;
        pm_fetch_req = 1'b0; pm_fetch_addr = 16'h0;
        pm_wr_req = 1'b0; pm_wr_addr = 16'h0; pm_wr_data = 16'h0;
        for (i = 0; i < IO_ADDR_COUNT; i++) io_written_mem[i] = 16'h0000;

        do_reset;

        /* T1. Reset values (c5x_reset, c5x_core.c:425-451). */
        dm_read(MMR_TIM_ADDR, rdata); check("T1 TIM reset", rdata, 16'hFFFF);
        dm_read(MMR_PRD_ADDR, rdata); check("T1 PRD reset", rdata, 16'hFFFF);
        dm_read(MMR_TCR_ADDR, rdata); check("T1 TCR reset", rdata, 16'h0000);
        dm_read(MMR_PDWSR_ADDR, rdata); check("T1 PDWSR reset", rdata, 16'hFFFF);
        dm_read(MMR_IOWSR_ADDR, rdata); check("T1 IOWSR reset", rdata, 16'hFFFF);
        dm_read(MMR_CWSR_ADDR, rdata); check("T1 CWSR reset", rdata, 16'h000F);
        dm_read(MMR_GREG_ADDR, rdata); check("T1 GREG reset", rdata, 16'h0000);
        dm_read(MMR_DRR_ADDR, rdata); check("T1 DRR reset", rdata, 16'h0000);
        dm_read(MMR_DXR_ADDR, rdata); check("T1 DXR reset", rdata, 16'h0000);
        dm_read(MMR_SPC_ADDR, rdata); check("T1 SPC reset (xrdy=1)", rdata, 16'h0800);
        check64("T1 timer_exp_cnt reset", timer_exp_cnt, 64'd0);

        /* T2. DMEM write/read (dm_rd/dm_wr + dm_internal, c5x_core.c:818-949). */
        dm_write(16'h0100, 16'h1234);
        dm_read(16'h0100, rdata); check("T2 DMEM 0x100", rdata, 16'h1234);
        dm_write(16'h04FF, 16'h5678);
        dm_read(16'h04FF, rdata); check("T2 DMEM 0x4FF", rdata, 16'h5678);
        dm_write(16'h0000, 16'h00AA); /* B2 block, internal */
        dm_read(16'h0000, rdata); check("T2 DMEM B2 0x00", rdata, 16'h00AA);

        /*
        T3. External data write lands in PMEM; fetch sees it
        (dm_wr external route, pm_rd, c5x_core.c:936-943, 956-963).
        */
        dm_write(16'h1000, 16'hABCD);
        dm_read(16'h1000, rdata); check("T3 PMEM via dm 0x1000", rdata, 16'hABCD);
        pm_fetch(16'h1000, fdata); check("T3 PMEM via fetch 0x1000", fdata, 16'hABCD);

        /* T4. Program-write channel (pm_wr, c5x_core.c:965-972). */
        pm_write(16'h2000, 16'hCAFE);
        check("T4 pm_wr bumps epoch", {15'b0, cap_epoch}, 16'd1);
        pm_fetch(16'h2000, fdata); check("T4 pm_wr then fetch", fdata, 16'hCAFE);
        dm_read(16'h2000, rdata); check("T4 pm_wr visible via dm", rdata, 16'hCAFE);

        /*
        T5. Reserved data range 0x500..0x7FF is external unified
        memory (dm_internal false; audit 07e N-19/M17).
        */
        dm_write(16'h0500, 16'h5005);
        pm_fetch(16'h0500, fdata); check("T5 reserved 0x500 in PMEM", fdata, 16'h5005);
        dm_read(16'h0500, rdata); check("T5 reserved 0x500 via dm", rdata, 16'h5005);
        dm_write(16'h07FF, 16'h7FF7);
        pm_fetch(16'h07FF, fdata); check("T5 reserved 0x7FF in PMEM", fdata, 16'h7FF7);

        /*
        T6. CNF=1: B0 0x100..0x2FF leaves data space (dm_internal /
        pm_ptr, KD-1).  A dm write to 0x100 now goes to PMEM; a
        fetch of 0xFE00 reads DMEM[0x100] (the T2 value).
        */
        @(negedge clk); cnf = 1'b1;
        dm_write(16'h0100, 16'hC0FF);
        dm_read(16'h0100, rdata); check("T6 CNF dm 0x100 -> PMEM", rdata, 16'hC0FF);
        pm_fetch(16'hFE00, fdata); check("T6 CNF fetch 0xFE00 -> DMEM 0x100", fdata, 16'h1234);
        pm_fetch(16'h0100, fdata); check("T6 CNF fetch 0x100 -> PMEM", fdata, 16'hC0FF);
        @(negedge clk); cnf = 1'b0;
        dm_read(16'h0100, rdata); check("T6 CNF off: dm 0x100 -> DMEM", rdata, 16'h1234);

        /* T7. OVLY/RAM overlays (dm_internal / pm_ptr, KD-1). */
        dm_write(16'h0800, 16'hAAAA); /* OVLY=0: external -> PMEM */
        dm_read(16'h0800, rdata); check("T7 OVLY=0 dm 0x800 -> PMEM", rdata, 16'hAAAA);
        pm_fetch(16'h0800, fdata); check("T7 OVLY=0 fetch 0x800 -> PMEM", fdata, 16'hAAAA);
        @(negedge clk); ovly = 1'b1;
        dm_write(16'h0800, 16'hBBBB); /* OVLY=1: internal -> DMEM */
        dm_read(16'h0800, rdata); check("T7 OVLY=1 dm 0x800 -> DMEM", rdata, 16'hBBBB);
        pm_fetch(16'h0800, fdata); check("T7 OVLY=1 fetch 0x800 -> PMEM kept", fdata, 16'hAAAA);
        @(negedge clk); ram = 1'b1;
        pm_fetch(16'h2000, fdata); check("T7 RAM=1 fetch 0x2000 -> DMEM 0x800", fdata, 16'hBBBB);
        pm_write(16'h2000, 16'hCCCC); /* program write into SARAM */
        dm_read(16'h0800, rdata); check("T7 RAM=1 pm_wr 0x2000 -> DMEM 0x800", rdata, 16'hCCCC);
        @(negedge clk); ram = 1'b0; ovly = 1'b0;

        /*
        T8a. Raw MMR backing store (mmr_rd/mmr_wr default path,
        c5x_core.c:620-797; audit 07e #29/M27/M39).
        */
        dm_write(16'h0023, 16'hBEEF);
        dm_read(16'h0023, rdata); check("T8 raw MMR 0x23", rdata, 16'hBEEF);
        dm_write(16'h002B, 16'h1234);
        dm_read(16'h002B, rdata); check("T8 raw MMR 0x2B", rdata, 16'h1234);
        dm_write(16'h0000, 16'h0001);
        dm_read(16'h0000, rdata); check("T8 raw MMR 0x00", rdata, 16'h0001);
        /* External MMRs route to the owner (mmr_rd/mmr_wr ext list). */
        dm_read(MMR_RPTC_ADDR, rdata); check("T8 ext MMR 0x08 RPTC", rdata, 16'hE008);
        check("T8 ext MMR read strobe", {15'b0, cap_extrd}, 16'd1);
        dm_write(MMR_RPTC_ADDR, 16'h0042);
        check("T8 ext MMR write strobe", {15'b0, cap_extwr}, 16'd1);
        dm_read(MMR_RPTC_ADDR, rdata); check("T8 ext MMR 0x08 written", rdata, 16'h0042);
        dm_read(MMR_AR0_ADDR, rdata); check("T8 ext MMR 0x10 AR0", rdata, 16'hE010);

        /* T9. Timer (tick_timer, c5x_core.c:1336-1350; mmr_wr 0x26). */
        dm_write(MMR_PRD_ADDR, 16'd5); /* PRD = 5 */
        dm_write(MMR_TIM_ADDR, 16'd5); /* TIM = 5 */
        dm_write(MMR_TCR_ADDR, 16'h0000); /* TCR: tddr=0, tss=0, psc=0 */
        tick_n(5);
        dm_read(MMR_TIM_ADDR, rdata); check("T9 TIM after 5 ticks", rdata, 16'd0);
        tick1; /* 6th tick: reload + TINT */
        check("T9 TINT pulse on reload", {15'b0, cap_tint}, 16'd1);
        dm_read(MMR_TIM_ADDR, rdata); check("T9 TIM reloaded to PRD", rdata, 16'd5);
        check64("T9 timer_exp_cnt == 1", timer_exp_cnt, 64'd1);
        /* Prescaler: TDDR=2 -> TIM decrements every 3 ticks. */
        dm_write(MMR_PRD_ADDR, 16'd2); /* PRD = 2 */
        dm_write(MMR_TIM_ADDR, 16'd2); /* TIM = 2 */
        dm_write(MMR_TCR_ADDR, 16'h0002); /* TCR: tddr=2, psc=0 */
        tick_n(3);
        dm_read(MMR_TIM_ADDR, rdata); check("T9 prescale TIM after 3 ticks", rdata, 16'd1);
        tick_n(3);
        dm_read(MMR_TIM_ADDR, rdata); check("T9 prescale TIM after 6 ticks", rdata, 16'd0);
        tick1; /* 7th tick: reload + TINT */
        check("T9 prescale TINT pulse", {15'b0, cap_tint}, 16'd1);
        dm_read(MMR_TIM_ADDR, rdata); check("T9 prescale TIM reloaded", rdata, 16'd2);
        check64("T9 timer_exp_cnt == 2", timer_exp_cnt, 64'd2);
        /* TRB reloads TIM from PRD and PSC from TDDR. */
        dm_write(MMR_TCR_ADDR, 16'h0020); /* TCR: TRB=1, tddr=0 */
        dm_read(MMR_TIM_ADDR, rdata); check("T9 TRB reloads TIM=PRD", rdata, 16'd2);
        /* TSS freezes the timer. */
        dm_write(MMR_TCR_ADDR, 16'h0010); /* TCR: tss=1 */
        tick_n(3);
        dm_read(MMR_TIM_ADDR, rdata); check("T9 TSS freezes TIM", rdata, 16'd2);
        check64("T9 TSS no expiry", timer_exp_cnt, 64'd2);
        dm_write(MMR_TCR_ADDR, 16'h0000); /* TCR: tss=0 */
        tick1;
        dm_read(MMR_TIM_ADDR, rdata); check("T9 TSS off: TIM resumes", rdata, 16'd1);
        /* TCR read composition: (psc<<6)|(tss<<4)|tddr. */
        dm_write(MMR_TCR_ADDR, 16'h0083); /* psc=2, tss=0, tddr=3 */
        dm_read(MMR_TCR_ADDR, rdata); check("T9 TCR readback 0x83", rdata, 16'h0083);
        /*
        Timer write in the same cycle as a tick: tick applies to the
        post-write state (write first, then tick -- C order).
        */
        dm_write(MMR_TIM_ADDR, 16'd10); /* TIM = 10 */
        dm_write(MMR_TCR_ADDR, 16'h0000); /* psc=0, tddr=0 */
        @(negedge clk);
        dm_req = 1'b1; dm_rd = 1'b0; dm_dmov = 1'b0;
        dm_addr = 16'h0024; dm_wdata = 16'd7; /* TIM <- 7 */
        tick = 1'b1; /* same-cycle tick */
        #2;
        @(negedge clk);
        dm_req = 1'b0; tick = 1'b0;
        dm_read(MMR_TIM_ADDR, rdata); check("T9 write+tick: TIM 7->6", rdata, 16'd6);

        /*
        T10. Serial port (c5x_serial_tick, c5x_core.c:3316-3345;
        mmr_wr 0x20-0x22, c5x_core.c:738-761).
        */
        dm_write(MMR_SPC_ADDR, 16'h00C0); /* SPC: RRST=1, XRST=1 */
        dm_read(MMR_SPC_ADDR, rdata); check("T10 SPC 0xC0 + xrdy", rdata, 16'h08C0);
        dm_write(MMR_DXR_ADDR, 16'h1234); /* DXR */
        check("T10 DXR write pulse", {15'b0, cap_dxrwr}, 16'd1);
        dm_read(MMR_SPC_ADDR, rdata); check("T10 SPC after DXR (xsrempty)", rdata, 16'h10C0);
        ser_tick1(16'h0000); /* XRST: DXR pending -> XINT, xrdy=1 */
        check("T10 XINT on DXR-pending tick", {15'b0, cap_xint}, 16'd1);
        /* Note: RRST=1, so the tick's RX side also fires: DRR=0, RRDY=1. */
        dm_read(MMR_SPC_ADDR, rdata); check("T10 SPC after TX tick", rdata, 16'h1CC0);
        ser_tick1(16'h0000); /* no DXR pending -> underflow; */
                                        /* RX side overruns (RRDY was 1) */
        check("T10 XINT legacy every tick", {15'b0, cap_xint}, 16'd1);
        dm_read(MMR_SPC_ADDR, rdata); check("T10 SPC after underflow (xsrempty=0, rsrfull)", rdata, 16'h2CC0);
        dm_read(MMR_DRR_ADDR, rdata); check("T10 DRR cleanup after underflow", rdata, 16'h0000);
        ser_tick1(16'h55AA); /* RX: DRR=0x55AA, RRDY=1, RINT */
        check("T10 RINT on RX tick", {15'b0, cap_rint}, 16'd1);
        dm_read(MMR_DRR_ADDR, rdata); check("T10 DRR read", rdata, 16'h55AA);
        dm_read(MMR_SPC_ADDR, rdata); check("T10 SPC after DRR read (rrdy=0)", rdata, 16'h08C0);
        ser_tick1(16'h1111); /* RX: DRR=0x1111, RRDY=1 */
        ser_tick1(16'h2222); /* overrun: RSRFULL=1, DRR kept */
        dm_read(MMR_SPC_ADDR, rdata); check("T10 SPC overrun (rsrfull+rrdy)", rdata, 16'h2CC0);
        dm_read(MMR_DRR_ADDR, rdata); check("T10 DRR kept on overrun", rdata, 16'h1111);
        dm_read(MMR_SPC_ADDR, rdata); check("T10 SPC after overrun read", rdata, 16'h08C0);
        dm_write(MMR_DXR_ADDR, 16'hABCD); /* DXR for loopback */
        dm_write(MMR_SPC_ADDR, 16'h00C2); /* SPC: RRST=1, XRST=1, DLB=1 */
        ser_tick1(16'h9999); /* DLB: DRR=DXR, not the RX word */
        dm_read(MMR_DRR_ADDR, rdata); check("T10 DLB DRR=DXR", rdata, 16'hABCD);
        dm_write(MMR_DXR_ADDR, 16'h5555); /* DXR pending (xrdy=0) */
        dm_write(MMR_SPC_ADDR, 16'h0000); /* SPC: XRST=0 with XRDY=0 -> XINT */
        check("T10 XINT on XRST=0 write", {15'b0, cap_xint}, 16'd1);
        dm_read(MMR_SPC_ADDR, rdata); check("T10 SPC after XRST=0 (xrdy=1)", rdata, 16'h0800);
        /*
        XINT mode 1 (c5x_set_xint_mode): first tick fires XINT,
        later ticks do not unless a DXR is pending.
        */
        @(negedge clk); xint_mode = 1'b1;
        @(negedge clk);
        dm_write(MMR_SPC_ADDR, 16'h00C0); /* SPC: RRST=1, XRST=1 */
        ser_tick1(16'h0000);
        check("T10 XINT mode1 first tick", {15'b0, cap_xint}, 16'd1);
        ser_tick1(16'h0000);
        check("T10 XINT mode1 second tick silent", {15'b0, cap_xint}, 16'd0);
        dm_write(MMR_DXR_ADDR, 16'h7777); /* DXR pending */
        ser_tick1(16'h0000);
        check("T10 XINT mode1 DXR-pending tick", {15'b0, cap_xint}, 16'd1);
        @(negedge clk); xint_mode = 1'b0;

        /*
        T11. Host I/O handshake + wait states (io_read/io_write,
        io_ws, c5x_core.c:575-585, 798-812; host window 0xFF50-0xFF5F).
        */
        dm_write(MMR_IOWSR_ADDR, 16'h1B2E); /* IOWSR (f: 2,3,2,0,3,2,1,0) */
        dm_write(MMR_CWSR_ADDR, 16'h0000); /* CWSR: small pages, no alt */
        dm_write(16'h0050, 16'hDEAD); /* MMR IO port write */
        check("T11 IO write ws=2 (port 0x50 idx0 f=2)", {13'b0, cap_iows}, 16'd2);
        check("T11 IO write not periph", {15'b0, cap_periph}, 16'd0);
        check("T11 host captured IO write 0x50", io_written_mem[16'h0050], 16'hDEAD);
        dm_read(16'h0051, rdata);
        check("T11 IO read 0x51", rdata, 16'hC051);
        check("T11 IO read ws=2 (port 0x51 idx0)", {13'b0, cap_iows}, 16'd2);
        dm_read(16'h0052, rdata);
        check("T11 IO read ws=3 (port 0x52 idx1 f=3)", {13'b0, cap_iows}, 16'd3);
        dm_read(16'h005E, rdata);
        check("T11 IO read ws=0 (port 0x5E idx7 f=0)", {13'b0, cap_iows}, 16'd0);
        dm_write(16'hFF50, 16'hBEEF); /* host-window write */
        check("T11 hostwin write ws=2", {13'b0, cap_iows}, 16'd2);
        check("T11 host captured IO write 0xFF50", io_written_mem[16'hFF50], 16'hBEEF);
        dm_read(16'hFF5F, rdata);
        check("T11 hostwin read 0xFF5F", rdata, 16'hC05F);
        check("T11 hostwin read ws=0 (idx7 f=0)", {13'b0, cap_iows}, 16'd0);
        dm_read(16'hFF5C, rdata);
        check("T11 hostwin read ws=1 (idx6 f=1)", {13'b0, cap_iows}, 16'd1);
        /* Big pages (CWSR bit 4): idx = port>>13. */
        dm_write(MMR_CWSR_ADDR, 16'h0010); /* CWSR: big pages, no alt */
        dm_read(16'hFF50, rdata);
        check("T11 big-pages ws=0 (0xFF50 idx7 f=0)", {13'b0, cap_iows}, 16'd0);
        dm_read(16'h0050, rdata);
        check("T11 big-pages ws=2 (0x50 idx0 f=2)", {13'b0, cap_iows}, 16'd2);
        /* Alt mapping, low half (CWSR bit 2): f=2->3, f=3->7. */
        dm_write(MMR_CWSR_ADDR, 16'h0014); /* CWSR: big, alt low */
        dm_read(16'h0050, rdata);
        check("T11 alt-low ws=3 (idx0 f=2->3)", {13'b0, cap_iows}, 16'd3);
        dm_write(MMR_CWSR_ADDR, 16'h0004); /* CWSR: small, alt low */
        dm_read(16'h0052, rdata);
        check("T11 alt-low ws=7 (idx1 f=3->7)", {13'b0, cap_iows}, 16'd7);
        dm_write(MMR_CWSR_ADDR, 16'h0008); /* CWSR: small, alt high */
        dm_read(16'h0058, rdata);
        check("T11 alt-high ws=7 (idx4 f=3->7)", {13'b0, cap_iows}, 16'd7);
        dm_write(MMR_CWSR_ADDR, 16'h000F); /* restore CWSR */
        dm_write(MMR_IOWSR_ADDR, 16'hFFFF); /* restore IOWSR */
        /*
        Peripheral-MMR bus cycle (mmr_bus, c5x_core.c:812-816):
        data WRITE to 0x20..0x4F adds 1; reads do not.
        */
        dm_write(MMR_TIM_ADDR, 16'h00AA);
        check("T11 periph ws on TIM write", {15'b0, cap_periph}, 16'd1);
        dm_read(MMR_TIM_ADDR, rdata);
        check("T11 no periph ws on TIM read", {15'b0, cap_periph}, 16'd0);
        dm_write(MMR_AR0_ADDR, 16'h0000);
        check("T11 no periph ws below 0x20", {15'b0, cap_periph}, 16'd0);

        /* T12. DMOV gate (dmov_wr, c5x_core.c:949-954; audit E-NEW-4). */
        dm_write(16'h0100, 16'h7777);
        dm_dmov_write(16'h0100, 16'h0101, 16'h7777);
        dm_read(16'h0101, rdata); check("T12 DMOV src internal ok", rdata, 16'h7777);
        dm_write(16'h0101, 16'h0000);
        dm_dmov_write(16'h0050, 16'h0101, 16'h9999); /* src < 0x60: drop */
        dm_read(16'h0101, rdata); check("T12 DMOV src MMR dropped", rdata, 16'h0000);
        dm_write(16'h0080, 16'h0000); /* PMEM[0x80] */
        dm_dmov_write(16'h007F, 16'h0080, 16'h9999); /* dest not internal: drop */
        pm_fetch(16'h0080, fdata); check("T12 DMOV dest external dropped", fdata, 16'h0000);

        /*
        T13. pm_epoch / replay_dirty (blk_state_changed,
        blk_store_guard, c5x_core.c:328-334, 848-860, 936-943).
        */
        dm_write(16'h1000, 16'h1111);
        check("T13 epoch on external dm_wr", {15'b0, cap_epoch}, 16'd1);
        dm_write(16'h0100, 16'h2222);
        check("T13 no epoch on internal dm_wr", {15'b0, cap_epoch}, 16'd0);
        dm_write(MMR_PMST_ADDR, 16'h0000); /* PMST (ext MMR) */
        check("T13 epoch on PMST write", {15'b0, cap_epoch}, 16'd1);
        dm_write(MMR_GREG_ADDR, 16'h0000); /* GREG (mine) */
        check("T13 no epoch on GREG write", {15'b0, cap_epoch}, 16'd0);
        dm_write(MMR_TREG0_ADDR, 16'h0000); /* TREG0 (ext, not 0x07-0x0B) */
        check("T13 no epoch on TREG0 write", {15'b0, cap_epoch}, 16'd0);
        @(negedge clk);
        replay_active = 1'b1; replay_lo = 16'h1000; replay_hi = 16'h100F;
        dm_write(16'h1005, 16'h4444);
        check("T13 dirty on block word write", {15'b0, cap_dirty}, 16'd1);
        /*
        blk_state_changed paths set dirty unconditionally in replay
        (c5x_core.c:328-334): PMST write and pm_wr.
        */
        dm_write(MMR_PMST_ADDR, 16'h0000); /* PMST */
        check("T13 dirty on PMST write in replay", {15'b0, cap_dirty}, 16'd1);
        check("T13 epoch on PMST write in replay", {15'b0, cap_epoch}, 16'd1);
        pm_write(16'h3100, 16'hAAAA);
        check("T13 dirty on pm_wr in replay", {15'b0, cap_dirty}, 16'd1);
        check("T13 epoch on pm_wr in replay", {15'b0, cap_epoch}, 16'd1);
        dm_write(16'h2000, 16'h5555);
        check("T13 no dirty outside block", {15'b0, cap_dirty}, 16'd0);
        dm_write(16'h0100, 16'h6666);
        check("T13 no dirty on internal write", {15'b0, cap_dirty}, 16'd0);
        @(negedge clk); ram = 1'b1; ovly = 1'b1;
        dm_write(16'h0800, 16'h7777); /* SARAM -> PM 0x2000, outside block */
        check("T13 no dirty SARAM outside block", {15'b0, cap_dirty}, 16'd0);
        @(negedge clk); replay_lo = 16'h2000; replay_hi = 16'h200F;
        dm_write(16'h0801, 16'h8888); /* SARAM -> PM 0x2001, in block */
        check("T13 dirty SARAM in block", {15'b0, cap_dirty}, 16'd1);
        @(negedge clk); ram = 1'b0; ovly = 1'b0; replay_active = 1'b0;
        dm_write(16'h1005, 16'h9999);
        check("T13 no dirty replay inactive", {15'b0, cap_dirty}, 16'd0);

        /* T14. Arbitration: data > pm_wr > fetch, pending is latched. */
        pm_write(16'h3000, 16'h3000);
        fetch_vs_data(16'h3000, 16'h3001, 16'h3001, fdata);
        check("T14 fetch latched behind data write", fdata, 16'h3000);
        dm_read(16'h3001, rdata); check("T14 data write landed", rdata, 16'h3001);
        pmwr_vs_fetch(16'h3002, 16'h3002, 16'h3000, fdata);
        check("T14 fetch latched behind pm_wr", fdata, 16'h3000);
        pm_fetch(16'h3002, fdata); check("T14 pm_wr landed", fdata, 16'h3002);

        /* T15. Firmware load through the write port (module header). */
        for (i = 0; i < 16; i++) pm_write(16'h4000 + i[15:0], 16'h4000 + i[15:0]);
        for (i = 0; i < 16; i++) begin
            pm_fetch(16'h4000 + i[15:0], fdata);
            if (fdata !== (16'h4000 + i[15:0])) begin
                $display("FAIL T15 firmware load word %0d: got %04h", i, fdata);
                fails = fails + 1;
            end else begin
                passes = passes + 1;
            end
        end

        /*
        T8b. Reset preserves mmr_raw and timer_exp_cnt
        (c5x_reset does not touch them, c5x_core.c:425-451).
        */
        exp_cnt_before = timer_exp_cnt;
        do_reset;
        dm_read(16'h0023, rdata); check("T8b mmr_raw survives reset", rdata, 16'hBEEF);
        check64("T8b timer_exp_cnt survives reset", timer_exp_cnt, exp_cnt_before);
        dm_read(MMR_TIM_ADDR, rdata); check("T8b TIM reset again", rdata, 16'hFFFF);
        dm_read(MMR_SPC_ADDR, rdata); check("T8b SPC reset again", rdata, 16'h0800);

        /*
        T16. Observation outputs track the registers (co-sim).
        Values are the mmr_rd readbacks (c5x_core.c:620-675): SPC
        is the stored bits ORed with the status flags, TCR is
        (psc<<6)|(tss<<4)|tddr, CWSR is zero-extended.  A reset
        first restores the known state, so every value below is
        self-contained.
        */
        do_reset;
        check("T16 obs GREG reset", obs_greg, 16'h0000);
        check("T16 obs DRR reset", obs_drr, 16'h0000);
        check("T16 obs DXR reset", obs_dxr, 16'h0000);
        check("T16 obs SPC reset (xrdy=1)", obs_spc, 16'h0800);
        check("T16 obs TIM reset", obs_tim, 16'hFFFF);
        check("T16 obs PRD reset", obs_prd, 16'hFFFF);
        check("T16 obs TCR reset", obs_tcr, 16'h0000);
        check("T16 obs PDWSR reset", obs_pdwsr, 16'hFFFF);
        check("T16 obs IOWSR reset", obs_iowsr, 16'hFFFF);
        check("T16 obs CWSR reset", obs_cwsr, 16'h000F);
        /* Writes: each observation follows its register. */
        dm_write(MMR_GREG_ADDR, 16'h5A5A);
        check("T16 obs GREG write", obs_greg, 16'h5A5A);
        dm_write(MMR_DXR_ADDR, 16'h1234);
        check("T16 obs DXR write", obs_dxr, 16'h1234);
        check("T16 obs SPC after DXR (xsrempty)", obs_spc, 16'h1000);
        dm_write(MMR_SPC_ADDR, 16'h00C0);
        check("T16 obs SPC write", obs_spc, 16'h10C0);
        dm_write(MMR_DRR_ADDR, 16'hABCD);
        check("T16 obs DRR write", obs_drr, 16'hABCD);
        dm_write(MMR_TIM_ADDR, 16'h0010);
        check("T16 obs TIM write", obs_tim, 16'h0010);
        dm_write(MMR_PRD_ADDR, 16'h0007);
        check("T16 obs PRD write", obs_prd, 16'h0007);
        dm_write(MMR_TCR_ADDR, 16'h0083);
        check("T16 obs TCR write", obs_tcr, 16'h0083);
        dm_write(MMR_PDWSR_ADDR, 16'h1357);
        check("T16 obs PDWSR write", obs_pdwsr, 16'h1357);
        dm_write(MMR_IOWSR_ADDR, 16'h2468);
        check("T16 obs IOWSR write", obs_iowsr, 16'h2468);
        dm_write(MMR_CWSR_ADDR, 16'h001F);
        check("T16 obs CWSR write", obs_cwsr, 16'h001F);
        dm_write(MMR_CWSR_ADDR, 16'hFFFF);
        check("T16 obs CWSR masked to 5 bits", obs_cwsr, 16'h001F);
        /* Serial tick: DRR takes the sample, SPC gains RRDY. */
        ser_tick1(16'h55AA);
        check("T16 obs DRR after ser tick", obs_drr, 16'h55AA);
        check("T16 obs SPC after ser tick", obs_spc, 16'h1CC0);
        /* Timer ticks: TIM counts down, reloads from PRD. */
        dm_write(MMR_TCR_ADDR, 16'h0000);
        check("T16 obs TCR cleared", obs_tcr, 16'h0000);
        dm_write(MMR_TIM_ADDR, 16'h0002);
        check("T16 obs TIM 2", obs_tim, 16'h0002);
        dm_write(MMR_PRD_ADDR, 16'h0002);
        check("T16 obs PRD 2", obs_prd, 16'h0002);
        exp_cnt_before = timer_exp_cnt;
        tick1;
        check("T16 obs TIM after 1 tick", obs_tim, 16'h0001);
        tick1;
        check("T16 obs TIM after 2 ticks", obs_tim, 16'h0000);
        tick1;
        check("T16 obs TIM reloaded", obs_tim, 16'h0002);
        check64("T16 timer_exp_cnt +1", timer_exp_cnt, exp_cnt_before + 64'd1);

        $display("TB_C5X_MEM: %0d passed, %0d failed", passes, fails);
        if (fails == 0)
            $display("TB_C5X_MEM_PASS");
        else
            $display("TB_C5X_MEM_FAIL");
        $finish;
    end

endmodule

`default_nettype wire
