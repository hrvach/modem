/* tb_dsp_trace_ddr -- rtl/dsp_trace_ddr.sv against a model of the HPS DDR port (random busy, a competing line interface). Checks: the magic word, the ring holds the PCs in order
   (three per word, AR7 in the top field), the count / drop header, the freeze flushes everything and writes the final header, a burst faster than the DDR port drops whole words
   (counted) and never corrupts a word. */
`timescale 1ns/1ps
module tb_dsp_trace_ddr;
    logic clk_dsp = 0, clk = 0, rst_n = 0;
    always #25 clk_dsp = ~clk_dsp;      /* 20 MHz stand-ins for 40.32 / 20.16 MHz: 2:1, aligned */
    always #50 clk = ~clk;

    logic        ev = 0, freeze = 0, line_act = 0, busy = 0;
    logic [15:0] pc = 16'h8000, ar7 = 16'h0BD0;
    logic        we; logic [28:0] a; logic [63:0] din;
    logic        freeze_c = 0, en = 0;
    dsp_trace_ddr #(.BASE_QADDR(29'h100), .RING_BITS(10)) dut (
        .clk_dsp(clk_dsp), .rst_dsp_n(rst_n), .ev_i(ev), .pc_i(pc), .ar7_i(ar7), .freeze_dsp_i(freeze), .en_dsp_i(en),
        .clk(clk), .rst_n(rst_n), .freeze_i(freeze_c), .en_i(en), .line_active_i(line_act), .ddr_busy_i(busy), .ddr_we_o(we), .ddr_addr_o(a), .ddr_din_o(din));

    logic [63:0] mem [0:4095];
    integer seed = 3;
    always @(posedge clk) begin
        busy     <= ($urandom(seed) % 3) == 0;
        line_act <= ($urandom(seed + 7) % 4) == 0;
        seed <= seed + 1;
        if (!busy && we) begin
            if (line_act) begin $display("FAIL: write while the line interface was active"); end
            mem[a - 29'h100] <= din;
        end
    end
    always @(posedge clk) freeze_c <= freeze;     /* stand-in for the synchroniser */

    integer errors = 0, k, n, nwords, dropped;
    task automatic chk(input string what, input longint got, input longint want);
        if (got !== want) begin errors = errors + 1; $display("FAIL %s: got %0d (0x%0h) want %0d (0x%0h)", what, got, got, want, want); end
    endtask
    task automatic events(input integer count, input integer gap);
        for (n = 0; n < count; n = n + 1) begin
            @(posedge clk_dsp); ev <= 1; pc <= pc + 1; ar7 <= ar7 + 1;
            @(posedge clk_dsp); ev <= 0;
            repeat (gap) @(posedge clk_dsp);
        end
    endtask

    initial begin
        for (k = 0; k < 4096; k = k + 1) mem[k] = 64'd0;
        repeat (10) @(posedge clk); rst_n = 1;
        /* disarmed: events are ignored and nothing reaches the DDR port */
        pc = 16'h7000 - 1; events(60, 2);
        repeat (100) @(posedge clk);
        chk("nothing written while disarmed (magic)", mem[0], 64'd0);
        chk("nothing written while disarmed (ring)", mem[16], 64'd0);
        en = 1;
        repeat (30) @(posedge clk);
        chk("magic", mem[0], {"10CRTMDM"});
        /* slow: 300 events, nothing may be dropped */
        pc = 16'h8000 - 1; ar7 = 16'h0BD0 - 1;
        events(300, 12);
        repeat (200) @(posedge clk);
        freeze <= 1;
        repeat (400) @(posedge clk);
        nwords = mem[1][31:0]; dropped = mem[2][31:0];
        chk("words written", nwords, 100);
        chk("dropped", dropped, 0);
        chk("frozen flag", mem[2][32], 1);
        for (k = 0; k < 100; k = k + 1) begin
            chk($sformatf("ring[%0d].pc0", k), mem[16 + k][15:0],  16'h8000 + 3 * k);
            chk($sformatf("ring[%0d].pc1", k), mem[16 + k][31:16], 16'h8000 + 3 * k + 1);
            chk($sformatf("ring[%0d].pc2", k), mem[16 + k][47:32], 16'h8000 + 3 * k + 2);
            chk($sformatf("ring[%0d].ar7", k), mem[16 + k][63:48], 16'h0BD0 + 3 * k + 2);
        end
        /* restart: a fast burst, faster than the port can take: whole words dropped and counted, every word intact */
        rst_n <= 0; freeze <= 0; en <= 0; repeat (5) @(posedge clk); rst_n <= 1; en <= 1;
        for (k = 0; k < 4096; k = k + 1) mem[k] = 64'd0;
        repeat (30) @(posedge clk);
        pc = 16'h4000 - 1; ar7 = 16'h0001 - 1;
        events(6000, 0);
        repeat (400) @(posedge clk);
        freeze <= 1;
        repeat (800) @(posedge clk);
        nwords = mem[1][31:0]; dropped = mem[2][31:0];
        $display("burst: %0d words written, %0d dropped", nwords, dropped);
        chk("burst words + drops = 2000", nwords + dropped, 2000);
        for (k = 0; k < (nwords < 1024 ? nwords : 1024); k = k + 1) begin
            chk($sformatf("burst[%0d] pc1-pc0", k), mem[16 + k][31:16] - mem[16 + k][15:0], 1);
            chk($sformatf("burst[%0d] pc2-pc1", k), mem[16 + k][47:32] - mem[16 + k][31:16], 1);
            chk($sformatf("burst[%0d] ar7-pc2", k), (mem[16 + k][63:48] - mem[16 + k][47:32]) & 16'hFFFF, (16'h0001 - 16'h4000) & 16'hFFFF + 0);
        end
        if (errors == 0) $display("PASS tb_dsp_trace_ddr"); else $display("FAIL tb_dsp_trace_ddr: %0d errors", errors);
        $finish;
    end
    initial begin #20000000; $display("FAIL tb_dsp_trace_ddr: global timeout"); $finish; end
endmodule
