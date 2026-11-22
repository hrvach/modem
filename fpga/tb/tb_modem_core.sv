/* System test of modem_core: the real SV25 firmware (flash image + NVRAM streamed through the OSD loader path), booting in Verilator with the SDRAM chip
   model. Plusargs: +flash=<file> +nvram=<file> +clocks=<n> (default 20000000) +send=<text> (typed after +sendat=<clock>, default 12000000).
   Prints every byte the modem sends to the DTE; PASS when "OK" has been seen after the AT command, FAIL on timeout. Not a unit test: slow, needs the files. */
`timescale 1ps/1ps
module tb_modem_core;
reg clk = 0, clk_cpu = 0, clk_dsp = 0;
always #6200 clk = ~clk;                          /* 80.64 MHz memory clock (period 12.4 ns here, a hair fast, so the three clocks stay exactly aligned in integer ps) */
always #12400 clk_dsp = ~clk_dsp;                 /* 40.32 MHz DSP clock: clk / 2 */
always #24800 clk_cpu = ~clk_cpu;                 /* 20.16 MHz CPU clock: clk / 4 */
reg reset = 1;

wire SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nWE;
wire [12:0] SDRAM_A;
wire [1:0]  SDRAM_BA;
wire [15:0] SDRAM_DQ_O, SDRAM_DQ_I;
reg         dl = 0, wr = 0;
reg  [15:0] idx = 0;
reg  [26:0] addr = 0;
reg  [7:0]  dout = 0;
reg         term_v = 0;
reg         rxd = 1;                          /* the DTE serial pin into the core */
reg  [7:0]  term_b = 0;
wire        txd, dte_v, dac_v, run, loading, sdram_up;
wire [7:0]  dte_b;
wire signed [15:0] dac_s;

wire        DQ_OE;
modem_core dut (
    .clk(clk), .clk_cpu(clk_cpu), .clk_dsp(clk_dsp), .reset_i(reset), .pll_locked_i(1'b1),
    .SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA), .SDRAM_DQ_I(SDRAM_DQ_I), .SDRAM_DQ_O(SDRAM_DQ_X), .SDRAM_DQ_OE(DQ_OE), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
    .SDRAM_nCS(SDRAM_nCS), .SDRAM_nCAS(SDRAM_nCAS), .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nWE(SDRAM_nWE),
    .ioctl_download_i(dl), .ioctl_index_i(idx), .ioctl_wr_i(wr), .ioctl_addr_i(addr), .ioctl_dout_i(dout),
    .dbg_markers_i(1'b0), .uart_rxd_i(rxd), .uart_txd_o(txd), .term_rx_valid_i(term_v), .term_rx_byte_i(term_b), .dte_tx_valid_o(dte_v), .dte_tx_byte_o(dte_b),
    .dac_valid_o(dac_v), .dac_sample_o(dac_s), .dsp_run_o(run), .loading_o(loading), .sdram_ready_o(sdram_up), .core_running_o(), .pc186_o(pc186), .badop186_o(), .pcdsp_o(), .dbg_words_o(), .dbg_vec_o(), .dbg_test_ok_o(), .dbg_cap_o(), .dbg_cal_ok_o(), .ioctl_wait_o(ioctl_wait));

wire [15:0] SDRAM_DQ_X;
sdram_chip #(.DLY(9)) chip (.clk(SDRAM_CLK), .nCS(SDRAM_nCS), .nRAS(SDRAM_nRAS), .nCAS(SDRAM_nCAS), .nWE(SDRAM_nWE), .BA(SDRAM_BA), .A(SDRAM_A),
    .DQ_O(SDRAM_DQ_X), .DQ_I(SDRAM_DQ_I));

integer ff, n, k, clocks_max, sendat, start_off, rom_bad, rd_lo, rd_hi;
reg [8*256-1:0] rom_path;
integer ok_state = 0;
reg [8*256-1:0] flash_path, nvram_path, send_text;
reg [7:0]  exp_bytes [0:15];
integer    n_exp = 0, exp_pos = 0, smoke = 0;
reg [7:0] b;
integer got_ok = 0, nbytes = 0, ncyc = 0;
integer fsz;

reg [3:0] wait_hist = 0;
wire      ioctl_wait;
wire [19:0] pc186;
integer pc_prints = 0;
reg [19:0] pc_prev = 0;
/* +pctrace: print every large jump of the 186's program counter and a sample every 200k clocks */
always @(posedge clk) if ($test$plusargs("pctrace") && dut.rst_n) begin
    if (({1'b0, pc186} > {1'b0, pc_prev} + 21'h100 || {1'b0, pc186} + 21'h100 < {1'b0, pc_prev}) && pc_prints < 300) begin $display("[tb] pc %05h -> %05h at clock %0d", pc_prev, pc186, ncyc); pc_prints <= pc_prints + 1; end
    pc_prev <= pc186;
end
/* +mon=N: every N clocks print the codec frame scheduler (frame state, target, the DSP's model time) and the 186 PC */
integer mon_every;
initial if (!$value$plusargs("mon=%d", mon_every)) mon_every = 0;
always @(posedge clk) if (mon_every > 0 && dut.rst_n && ncyc % mon_every == 0) $display("[mon] clk=%0d pc186=%05h mtime=%0d aic_frame=%0d target=%0d run=%b", ncyc, pc186, dut.dsp_mtime, dut.u_aic.frame_q, dut.u_aic.target_q, dut.u_aic.run_i);
always @(posedge clk) wait_hist <= {wait_hist[2:0], ioctl_wait};


/* +dsppc=N: sample the DSP's program counter every N clocks once it runs; +dspio: print the DSP's I/O accesses, +dspint: its interrupt entries */
integer dsppc_every = 0, dsp_idle_clk = 0, dsp_busy_clk = 0, dsp_ints = 0;
initial if (!$value$plusargs("dsppc=%d", dsppc_every)) dsppc_every = 0;
always @(posedge clk_dsp) if (dut.glue_run) begin
    if (dut.idle_dsp) dsp_idle_clk <= dsp_idle_clk + 1; else dsp_busy_clk <= dsp_busy_clk + 1;
    if (dsppc_every != 0 && (ncyc % dsppc_every) < 4 && dut.u_dsp.instr_done) $display("[tb] dsp pc %04h cycles %0d idle %0d busy %0d at clock %0d", dut.u_dsp.pc_o, dut.u_dsp.cycles_o, dsp_idle_clk, dsp_busy_clk, ncyc);
end

always @(posedge clk_dsp) if ($test$plusargs("iodbg") && ncyc > 951400 && ncyc < 951700) $display("[io] t=%0d req=%b rd=%b ack=%b seen=%b start=%b hsack=%b busy=%b port=%h wd=%h rdata=%h", ncyc, dut.io_req, dut.io_rd, dut.io_ack, dut.io_seen_q, dut.io_start, dut.io_hs_ack, dut.io_hs_busy, dut.io_port, dut.io_wdata, dut.io_rdata);

task stream_file(input integer fd, input integer index, input integer size, input integer first);
    integer i, c;
    begin
        idx = index; dl = 1; repeat (4) @(posedge clk);
        if (first != 0) c = $fseek(fd, first, 0);
        for (i = first; i < size; i = i + 1) begin
            c = $fgetc(fd); if (c < 0) c = 0;
            /* like hps_io: a byte every few clocks, and it notices ioctl_wait three clocks late */
            while (wait_hist[2]) @(posedge clk);
            @(posedge clk); addr <= i; dout <= c[7:0]; wr <= 1; @(posedge clk); wr <= 0; repeat (3) @(posedge clk);
        end
        dl = 0; repeat (40) @(posedge clk);
    end
endtask

always @(posedge clk) if ($test$plusargs("trace") && dut.u_dsp.io_req && dut.ce_dsp) $display("[tb] DSP io %s port %h wdata %h rdata %h at clock %0d", dut.u_dsp.io_rd ? "RD" : "WR", dut.u_dsp.io_port, dut.u_dsp.io_wdata, dut.u_glue.io_rdata_o, ncyc);
always @(posedge clk) if ($test$plusargs("trace") && dut.glue_wr_commit && dut.ce_186) $display("[tb] 186 wr port %h data %h at clock %0d", dut.glue_wr_port, dut.glue_wr_data, ncyc);
/* +dumpat=<clock>: print SDRAM words of the 186's RAM and flash (physical addresses) at that clock */
integer dumpat = -1;
task dump_phys(input [19:0] phys, input integer nwords);
    integer i;
    reg [24:0] a;
    reg [23:0] key;
    reg [15:0] w;
    begin
        for (i = 0; i < nwords; i = i + 1) begin
            a = {phys[19:1] + i[18:0], 1'b0};
            key = {a[24:23], a[13:1], a[22:14]};
            w = chip.mem.exists(key) ? chip.mem[key] : 16'hxxxx;
            $write("%04h ", w);
        end
        $write("\n");
    end
endtask
integer icu_prints = 0;
reg [9:0] req_prev = 0;
reg       irq_prev = 0;
/* +icutrace: ICU request / mask / timer state changes in the 186 system */
always @(posedge clk) if ($test$plusargs("icutrace") && dut.rst_n && ncyc > 2634205 && icu_prints < 120) begin
    if (dut.u_186.u_sys.req_r !== req_prev || dut.u_186.u_sys.irq_req !== irq_prev) begin
        $display("[tb] icu req_r=%b irq_req=%b msk=%h primsk=%0d t0con=%h t0cmpa=%h t0cnt=%h at clock %0d", dut.u_186.u_sys.req_r, dut.u_186.u_sys.irq_req, dut.u_186.u_sys.msk_r,
                 dut.u_186.u_sys.primsk_r, dut.u_186.u_sys.tmr_con[0], dut.u_186.u_sys.tmr_cmpa[0], dut.u_186.u_sys.tmr_cnt[0], ncyc);
        icu_prints <= icu_prints + 1;
    end
    req_prev <= dut.u_186.u_sys.req_r;
    irq_prev <= dut.u_186.u_sys.irq_req;
end
integer tm_prints = 0;
reg [15:0] tcon_prev = 0, tcmp_prev = 0;
always @(posedge clk) if ($test$plusargs("icutrace") && dut.rst_n && tm_prints < 60) begin
    if (dut.u_186.u_sys.tmr_con[0] !== tcon_prev || dut.u_186.u_sys.tmr_cmpa[0] !== tcmp_prev) begin
        $display("[tb] timer0 con=%h cmpa=%h cnt=%h at clock %0d", dut.u_186.u_sys.tmr_con[0], dut.u_186.u_sys.tmr_cmpa[0], dut.u_186.u_sys.tmr_cnt[0], ncyc);
        tm_prints <= tm_prints + 1;
    end
    tcon_prev <= dut.u_186.u_sys.tmr_con[0];
    tcmp_prev <= dut.u_186.u_sys.tmr_cmpa[0];
end
integer pcs_every = 0;
always @(posedge clk) if (pcs_every != 0 && ncyc >= 2634205 && (ncyc % pcs_every) == 0) $display("[tb] pc sample %05h at clock %0d", pc186, ncyc);
always @(posedge clk) if (ncyc == dumpat) begin
    $display("[tb] RAM  0000: "); dump_phys(20'h00000, 16);
    $display("[tb] RAM  0430: "); dump_phys(20'h00430, 16);
    $display("[tb] FLSH FC430: "); dump_phys(20'hFC430, 16);
    $display("[tb] RAM  1B00: "); dump_phys(20'h01B00, 16);
    $display("[tb] FLSH FDB00: "); dump_phys(20'hFDB00, 16);
    $display("[tb] RAM  0430 high: "); dump_phys(20'h00800, 8);
end
always @(posedge clk) ncyc <= ncyc + 1;
always @(posedge clk_cpu) begin
    if (dte_v) begin
        nbytes <= nbytes + 1;
        $write("%c", dte_b);
        if (smoke) $display("[tb] dte byte %02h at clock %0d", dte_b, ncyc);
        if (smoke && n_exp != 0) begin
            if (dte_b == exp_bytes[exp_pos]) begin exp_pos <= exp_pos + 1; if (exp_pos + 1 == n_exp) got_ok <= 1; end
            else exp_pos <= (dte_b == exp_bytes[0]) ? 1 : 0;
        end
        if (dte_b == "K" && ok_state == 1) got_ok <= 1;
        ok_state <= (dte_b == "O") ? 1 : 0;
    end
end

initial begin
    if (!$value$plusargs("flash=%s", flash_path)) flash_path = "../courier/fw/SV25.flash.bin";
    if (!$value$plusargs("nvram=%s", nvram_path)) nvram_path = "../courier/fw/nvram.bin";
    if (!$value$plusargs("clocks=%d", clocks_max)) clocks_max = 20000000;
    if (!$value$plusargs("sendat=%d", sendat)) sendat = 12000000;
    if (!$value$plusargs("start=%h", start_off)) start_off = 0;
    if (!$value$plusargs("dumpat=%d", dumpat)) dumpat = -1;
    if (!$value$plusargs("pcs=%d", pcs_every)) pcs_every = 0;
    if (!$value$plusargs("send=%s", send_text)) send_text = "AT";
    if ($test$plusargs("smokerx")) begin
        smoke = 1; n_exp = 1; exp_bytes[0] = 8'h42;
        fork begin
            wait (ncyc >= 3000000);                    /* after the 186 has started: a real 8N1 byte 'A' at 115200 on the pin */
            rxd = 0; #8680560;
            for (int bi = 0; bi < 8; bi++) begin rxd = 8'h41 >> bi; #8680560; end
            rxd = 1; #8680560;
        end join_none
    end else if ($test$plusargs("smokeirx")) begin
        smoke = 1; n_exp = 2; exp_bytes[0] = 8'h42; exp_bytes[1] = 8'h44;
        fork begin
            wait (ncyc >= 3000000);                    /* 'A' then 'C', back to back, 8N1 at 115200 */
            for (int by = 0; by < 2; by++) begin
                rxd = 0; #8680560;
                for (int bi = 0; bi < 8; bi++) begin rxd = (by == 0 ? 8'h41 : 8'h43) >> bi; #8680560; end
                rxd = 1; #8680560;
            end
        end join_none
    end else if ($test$plusargs("smoke")) begin
        smoke = 1; n_exp = 3; exp_bytes[0] = 8'h34; exp_bytes[1] = 8'h12; exp_bytes[2] = 8'h4B;
    end
    repeat (20) @(posedge clk);
    wait (sdram_up); repeat (50) @(posedge clk);                 /* reset stays high: the framework holds RESET while it downloads the boot files */
    ff = $fopen(flash_path, "rb"); if (ff == 0) begin $display("FAIL: cannot open %0s", flash_path); $finish; end
    stream_file(ff, 0, 524288, start_off); $fclose(ff);
    ff = $fopen(nvram_path, "rb"); if (ff == 0) begin $display("FAIL: cannot open %0s", nvram_path); $finish; end
    stream_file(ff, 1, 512, 0); $fclose(ff);
    if ($value$plusargs("rom=%s", rom_path)) begin                         /* DSP on-chip ROM image: index 2 -> the DSP's block RAM words 0.. */
        ff = $fopen(rom_path, "rb"); if (ff == 0) begin $display("FAIL: cannot open %0s", rom_path); $finish; end
        stream_file(ff, 2, 16384, 0); $fclose(ff);
        repeat (2000) @(posedge clk);                                           /* the last words are still crossing into the CPU domain */
        ff = $fopen(rom_path, "rb"); rom_bad = 0;
        for (k = 0; k < 8192; k = k + 1) begin rd_lo = $fgetc(ff); rd_hi = $fgetc(ff); if (dut.u_dsp.u_mem.pmem[k] !== {rd_hi[7:0], rd_lo[7:0]}) begin rom_bad = rom_bad + 1; if (rom_bad < 6) $display("[tb] ROM word %0d: got %h want %h", k, dut.u_dsp.u_mem.pmem[k], {rd_hi[7:0], rd_lo[7:0]}); end end
        $fclose(ff);
        if (rom_bad == 0) $display("[tb] ROM image in the DSP block RAM: PASS"); else $display("[tb] ROM image in the DSP block RAM: FAIL (%0d words differ)", rom_bad);
    end
    repeat (20) @(posedge clk); reset = 0;
    $display("\n[tb] files loaded at clock %0d, SDRAM %b, reset released, now booting", ncyc, sdram_up);
    wait (ncyc >= sendat);
    $display("\n[tb] typing the command at clock %0d, dsp_run=%b", ncyc, run);
    for (k = 0; k < 256 && !smoke && !$test$plusargs("notype"); k = k + 1) begin
        b = send_text[8*(255-k) +: 8];
        if (b != 0) begin @(posedge clk); term_b <= b; term_v <= 1; @(posedge clk); term_v <= 0; repeat (20000) @(posedge clk); end
    end
    if (!smoke && !$test$plusargs("notype")) begin @(posedge clk); term_b <= 8'h0D; term_v <= 1; @(posedge clk); term_v <= 0; end
    wait (ncyc >= clocks_max || got_ok);
    $display("\n[tb] done at clock %0d: dte bytes %0d, dsp_run %b, ok %0d", ncyc, nbytes, run, got_ok);
    if (got_ok) $display("PASS tb_modem_core"); else $display("FAIL tb_modem_core: no OK seen");
    $finish;
end
endmodule
