/*
loader.sv -- OSD file loader: the firmware flash image into SDRAM and the NVRAM image into the EEPROM preload port.

FPGA-only plumbing. Takes hps_io's byte-wide ioctl download stream (WIDE = 0, ioctl_addr counts bytes) and, per file index:
  index 0: the decoded SV25 flash image (524288 bytes, make fw in ../courier) -> 186 physical addresses 0x80000..0xFFFFF = SDRAM words 0x40000.. through one
           sdram_arb client (a 16-bit word is written when its odd byte arrives; bytes beyond 512 KB are ignored);
  index 2: the DSP on-chip mask ROM image (fw/c5x-onchip-rom-8k.bin, up to 16384 bytes = program words 0..0x1FFF) -> the DSP program space in SDRAM; rom_loaded_o
           then tells dsp_glue not to write its synthesised 0x0440 tables (machine_start_dsp: a loaded ROM replaces dsp_synth_rom). The flag is sticky
           across user resets (it has no reset: FPGA power-up value 0), the ROM stays in the SDRAM;
  index 1: the 512-byte NVRAM image -> ee_load_* (256 little-endian words, one pulse per word; i186_sys takes them while its reset is low).
File slot: a file picked in the OSD (F1, F2) arrives with ioctl_index = n, the core folder's boot0.rom / boot1.rom / boot2.rom (sent by Main_MiSTer at core start, no OSD
needed) with ioctl_index = n << 6; the slot is index[5:0] when that is non-zero, else index[7:6].
busy_o is high from the start of a download until the last write was acknowledged: the top holds the cores in reset meanwhile.
ioctl_wait_o tells hps_io to pause the byte stream when the write FIFO fills (a real HPS is much faster than the SDRAM).
Not modelled: the XMD decode (decode on the host), NVRAM write-back to the card.
*/
`default_nettype none

module loader #(
    parameter [23:0] FLASH_WORD_BASE = 24'h040000,   /* SDRAM word address of 186 physical 0x80000 */
    parameter [23:0] DSP_WORD_BASE   = 24'h0C0000    /* SDRAM word address of DSP program word 0 (c5x_xmem BASE) */
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        ioctl_download_i,
    input  logic [15:0] ioctl_index_i,
    input  logic        ioctl_wr_i,
    input  logic [26:0] ioctl_addr_i,
    input  logic [7:0]  ioctl_dout_i,

    output logic        rq_req_o,
    output logic [23:0] rq_addr_o,
    output logic [15:0] rq_wdata_o,
    input  logic        rq_ack_i,

    output logic        ee_load_en_o,
    output logic [7:0]  ee_load_addr_o,
    output logic [15:0] ee_load_data_o,

    output logic        ioctl_wait_o,        /* hps_io: hold the stream while the SDRAM writes catch up */
    output logic [15:0] words_o,             /* bring-up: SDRAM words written for the flash image (slot 0) */
    output logic [15:0] drops_o,             /* bring-up: words lost because the stream outran the FIFO (must stay 0) */
    output logic        busy_o,
    output logic [1:0]  slot_o,            /* file slot of the last / current download (0 flash, 1 NVRAM, 2 DSP ROM) */
    output logic        rom_loaded_o
);
    localparam [26:0] FLASH_BYTES = 27'h080000;
    localparam [26:0] NVRAM_BYTES = 27'h000200;
    localparam [26:0] ROM_BYTES   = 27'h004000;

    logic rom_loaded_q = 1'b0;   /* no reset on purpose: see the header */

    logic [7:0]  lo_q;
    logic        dl_q;

    /* write FIFO: the HPS streams a byte every few clocks, an SDRAM write takes about 12: 16 words absorb the latency of ioctl_wait (hps_io samples it
       asynchronously, a few bytes still arrive after it is raised) */
    logic [39:0] fifo_q [0:15];
    logic [4:0]  wr_q, rd_q;
    logic [4:0]  count;
    logic        fifo_empty, fifo_full;
    logic        push;
    logic [23:0] push_addr;

    logic        word_done;
    logic [5:0]  slot;
    logic [5:0]  slot_r;       /* registered: the index only changes between files */
    logic [1:0]  slot_q;
    always_comb begin
        slot       = slot_r;
        word_done  = ioctl_wr_i && ioctl_addr_i[0];
        slot_o     = slot_q;
        count      = wr_q - rd_q;
        fifo_empty = (wr_q == rd_q);
        fifo_full  = (count == 5'd16);
        ioctl_wait_o = (count >= 5'd6);
        rq_req_o   = !fifo_empty;
        rq_addr_o  = fifo_q[rd_q[3:0]][39:16];
        rq_wdata_o = fifo_q[rd_q[3:0]][15:0];
        busy_o     = ioctl_download_i || !fifo_empty || dl_q;
        rom_loaded_o = rom_loaded_q;
        push       = 1'b0;
        push_addr  = 24'h000000;
        if (word_done) begin
            if (slot == 6'd0 && ioctl_addr_i < FLASH_BYTES) begin
                push      = 1'b1;
                push_addr = FLASH_WORD_BASE | {6'h00, ioctl_addr_i[18:1]};
            end
            if (slot == 6'd2 && ioctl_addr_i < ROM_BYTES) begin
                push      = 1'b1;
                push_addr = DSP_WORD_BASE | {11'h000, ioctl_addr_i[13:1]};
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            lo_q           <= 8'h00;
            wr_q           <= 5'd0;
            rd_q           <= 5'd0;
            dl_q           <= 1'b0;
            slot_q         <= 2'd0;
            slot_r         <= 6'd0;
            words_o        <= 16'd0;
            drops_o        <= 16'd0;
            ee_load_en_o   <= 1'b0;
            ee_load_addr_o <= 8'h00;
            ee_load_data_o <= 16'h0000;
        end else begin
            ee_load_en_o <= 1'b0;
            slot_r       <= (ioctl_index_i[5:0] != 6'd0) ? ioctl_index_i[5:0] : {4'd0, ioctl_index_i[7:6]};
            dl_q         <= ioctl_download_i;
            if (ioctl_download_i)
                slot_q <= slot[1:0];
            if (ioctl_wr_i && slot == 6'd2)
                rom_loaded_q <= 1'b1;
            if (ioctl_wr_i && !ioctl_addr_i[0])
                lo_q <= ioctl_dout_i;
            if (rq_req_o && rq_ack_i) begin
                rd_q <= rd_q + 5'd1;
                if (slot_q == 2'd0)
                    words_o <= words_o + 16'd1;
            end
            if (push) begin
                if (fifo_full) begin
                    drops_o <= drops_o + 16'd1;
                end else begin
                    fifo_q[wr_q[3:0]] <= {push_addr, ioctl_dout_i, lo_q};
                    wr_q <= wr_q + 5'd1;
                end
            end
            if (word_done && slot == 6'd1 && ioctl_addr_i < NVRAM_BYTES) begin
                ee_load_en_o   <= 1'b1;
                ee_load_addr_o <= ioctl_addr_i[8:1];
                ee_load_data_o <= {ioctl_dout_i, lo_q};
            end
        end
    end
endmodule
