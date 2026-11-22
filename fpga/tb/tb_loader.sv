/* Self-checking test of loader: flash bytes -> SDRAM word writes (with a slow acknowledging client), the NVRAM image -> ee_load_* pulses, bytes past the
   end ignored, busy_o. */
`timescale 1ns/1ps
module tb_loader;
reg clk = 0, rst_n = 0;
always #5 clk = ~clk;
reg         dl = 0, wr = 0;
reg  [15:0] idx = 0;
reg  [26:0] addr = 0;
reg  [7:0]  dout = 0;
wire        req, ee_en, busy, rom_loaded;
wire [1:0]  slot;
wire        iowait;
wire [15:0] words, drops;
wire [23:0] raddr;
wire [15:0] rdata;
wire [7:0]  ee_addr;
wire [15:0] ee_data;
reg         ack = 0;
loader dut (.clk(clk), .rst_n(rst_n), .ioctl_download_i(dl), .ioctl_index_i(idx), .ioctl_wr_i(wr), .ioctl_addr_i(addr), .ioctl_dout_i(dout), .rq_req_o(req),
    .rq_addr_o(raddr), .rq_wdata_o(rdata), .rq_ack_i(ack), .ee_load_en_o(ee_en), .ee_load_addr_o(ee_addr), .ee_load_data_o(ee_data), .ioctl_wait_o(iowait), .words_o(words), .drops_o(drops), .busy_o(busy), .slot_o(slot), .rom_loaded_o(rom_loaded));

reg [15:0] mem [0:262143];
reg [15:0] mem_dsp [0:8191];
integer nrom = 0;
integer nwr = 0, errors = 0, nee = 0;
reg [15:0] ee [0:255];
/* slow client: acknowledge 3 clocks after req rises */
integer cnt = 0;
always @(posedge clk) begin
    ack <= 0;
    if (req && !ack) begin
        cnt <= cnt + 1;
        if (cnt == 3) begin
            ack <= 1; cnt <= 0;
            if (raddr >= 24'h0C0000) begin mem_dsp[raddr - 24'h0C0000] <= rdata; nrom <= nrom + 1; end
            else begin mem[raddr - 24'h040000] <= rdata; nwr <= nwr + 1; end
        end
    end
    if (ee_en) begin ee[ee_addr] <= ee_data; nee <= nee + 1; end
end

/* a real HPS: one byte every 2 clocks, and it notices ioctl_wait 3 clocks late */
reg [3:0] wait_hist = 0;
always @(posedge clk) wait_hist <= {wait_hist[2:0], iowait};
task byte_in(input [26:0] a, input [7:0] d);
    begin
        while (wait_hist[2]) @(posedge clk);
        @(posedge clk); addr <= a; dout <= d; wr <= 1; @(posedge clk); wr <= 0; @(posedge clk);
    end
endtask
integer i;
initial begin
    repeat (4) @(posedge clk); rst_n = 1; repeat (4) @(posedge clk);
    idx = 0; dl = 1;
    for (i = 0; i < 64; i = i + 1) byte_in(i, 8'hA0 + i[7:0]);
    byte_in(27'h07FFFE, 8'h12); byte_in(27'h07FFFF, 8'h34);
    byte_in(27'h080000, 8'h55); byte_in(27'h080001, 8'h66);                 /* past 512 KB: ignored */
    if (!busy) begin errors = errors + 1; $display("FAIL busy low during download"); end
    dl = 0; repeat (20) @(posedge clk);
    if (busy) begin errors = errors + 1; $display("FAIL busy high after download"); end
    if (drops != 0) begin errors = errors + 1; $display("FAIL loader dropped %0d words", drops); end
    if (nwr != 33) begin errors = errors + 1; $display("FAIL flash writes %0d want 33", nwr); end
    if (mem[0] !== 16'hA1A0) begin errors = errors + 1; $display("FAIL word 0 %h", mem[0]); end
    if (mem[31] !== 16'hDFDE) begin errors = errors + 1; $display("FAIL word 31 %h", mem[31]); end
    if (mem[18'h3FFFF] !== 16'h3412) begin errors = errors + 1; $display("FAIL last word %h", mem[18'h3FFFF]); end
    idx = 16'h0040; dl = 1;                                                    /* boot1.rom style index */
    for (i = 0; i < 512; i = i + 1) byte_in(i, i[7:0] ^ 8'h5A);
    byte_in(27'h200, 8'h99); byte_in(27'h201, 8'h99);
    dl = 0; repeat (10) @(posedge clk);
    if (nee != 256) begin errors = errors + 1; $display("FAIL ee words %0d want 256", nee); end
    if (ee[0] !== 16'h5B5A) begin errors = errors + 1; $display("FAIL ee[0] %h", ee[0]); end
    if (ee[255] !== {8'hFF ^ 8'h5A, 8'hFE ^ 8'h5A}) begin errors = errors + 1; $display("FAIL ee[255] %h", ee[255]); end
    if (rom_loaded) begin errors = errors + 1; $display("FAIL rom_loaded before any ROM byte"); end
    if (slot !== 2'd1) begin errors = errors + 1; $display("FAIL slot after boot1-style download %0d", slot); end
    idx = 16'h0080; dl = 1;                                                    /* boot2.rom style index */
    for (i = 0; i < 16; i = i + 1) byte_in(i, 8'h30 + i[7:0]);
    byte_in(27'h4000, 8'hEE); byte_in(27'h4001, 8'hEE);                        /* past 16 KB: ignored */
    dl = 0; repeat (20) @(posedge clk);
    if (!rom_loaded) begin errors = errors + 1; $display("FAIL rom_loaded not set"); end
    if (slot !== 2'd2) begin errors = errors + 1; $display("FAIL slot after boot2-style download %0d", slot); end
    if (mem_dsp[0] !== 16'h3130 || mem_dsp[7] !== 16'h3F3E) begin errors = errors + 1; $display("FAIL rom words %h %h", mem_dsp[0], mem_dsp[7]); end
    if (nrom != 8) begin errors = errors + 1; $display("FAIL rom writes %0d want 8", nrom); end
    if (errors == 0) $display("PASS tb_loader"); else $display("FAIL tb_loader: %0d errors", errors);
    $finish;
end
initial begin #50000000; $display("FAIL tb_loader: global timeout"); $finish; end
endmodule
