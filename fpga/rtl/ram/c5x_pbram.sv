/*
c5x_pbram.sv -- the TMS320C5x's 64K-word external program / unified memory in M10K block RAM (replaces c5x_xmem, which fronted the SDRAM).

FPGA-only plumbing. Same DSP-side and host-side ports as c5x_xmem: the DSP core (EXT_PMEM = 1) reads and writes through rd_en_i / raddr_i / wr_en_i / waddr_i, the dsp_glue
(overlays, firmware bursts) and the loader (on-chip ROM image) write through the host port. ready_o tells the top whether the access presented now can complete at the
DSP's next ce_i edge.

Read: the M10K read is registered, so a new address needs one clock to be looked up: ready_o is low in the first clock of a new read address and high from the second on
(rdata_o is the registered word and must be sampled at the ce_i edge). Any array write invalidates the lookup of the following clock (conservative, like c5x_xmem's dirty flag),
so a read never returns data older than a write one clock before it; a same-address read in the clock of a write returns the OLD word (the c5x_mem contract).
Write: always ready; one write port: a DSP write (applied at its ce_i edge) wins over a host write, which waits (hw_ready_o low in that clock).
*/
`default_nettype none

module c5x_pbram (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ce_i,

    /* DSP side */
    input  logic        rd_en_i,
    input  logic [15:0] raddr_i,
    input  logic        wr_en_i,
    input  logic [15:0] waddr_i,
    input  logic [15:0] wdata_i,
    output logic [15:0] rdata_o,
    output logic        ready_o,

    /* host write port */
    input  logic        hw_en_i,
    input  logic [15:0] hw_addr_i,
    input  logic [15:0] hw_data_i,
    output logic        hw_ready_o
);
    (* ramstyle = "M10K" *) logic [15:0] mem [0:65535];

    logic [15:0] rd_q;
    logic [15:0] look_q;
    logic        dirty_q;
    logic        wr_apply, hw_take, we;
    logic [15:0] wa, wd;

    always_comb begin
        wr_apply   = ce_i && wr_en_i;
        hw_ready_o = !wr_apply;
        hw_take    = hw_en_i && hw_ready_o;
        we         = wr_apply || hw_take;
        wa         = wr_apply ? waddr_i : hw_addr_i;
        wd         = wr_apply ? wdata_i : hw_data_i;
        ready_o    = !rd_en_i || ((raddr_i == look_q) && !dirty_q);
        rdata_o    = rd_q;
    end

    always_ff @(posedge clk) begin
        if (we)
            mem[wa] <= wd;
        if (rd_en_i)
            rd_q <= mem[raddr_i];
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            look_q  <= 16'h0000;
            dirty_q <= 1'b1;
        end else begin
            look_q  <= raddr_i;
            dirty_q <= we;
        end
    end
endmodule
