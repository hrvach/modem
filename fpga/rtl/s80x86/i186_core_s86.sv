/*
i186_core_s86.sv -- the s80x86 CPU core (Jamie Iles, GPL-3) behind the same port list as i186_core, so i186_top / i186_sys stay as they are.

FPGA-only plumbing. Differences from i186_core that matter to the rest of the system:
  * Timing: the s80x86 runs most instructions in far fewer clocks than an 80C186 (cyc_model_i is ignored). Delay loops therefore run short. A governor that
    charges the Table D-2 cycles per instruction comes later; for now the core runs unthrottled.
  * One bus: the core's instruction and data buses are merged here (data first), one request at a time, with the request / level-ack handshake i186_top expects
    (bus_req held until bus_ack, nothing new until bus_ack has dropped). Byte accesses leave as bus_w = 0 with the byte address; word accesses are always even.
  * Interrupts: irq_i (edge) / irq_vec_i / irq_clear_i are turned back into the level + vector the s80x86 wants (intr + irq), inta is reported as irq_taken_o.
  * No undefined-opcode trap (ud_trap_i ignored, st_badop_o = 0), cycles_o counts clocks, pc_o is the physical CS:IP of the current instruction.
*/
`default_nettype none

module i186_core_s86 (
    input  logic        clk,
    input  logic        ce_i,
    input  logic        rst_n,

    input  logic        cyc_model_i,
    input  logic        ud_trap_i,

    input  logic        nmi_i,
    input  logic        irq_i,
    input  logic [7:0]  irq_vec_i,
    input  logic        irq_clear_i,

    output logic        bus_req,
    output logic [19:0] bus_addr,
    output logic        bus_wr,
    output logic        bus_w,
    output logic        bus_io,
    output logic [15:0] bus_wdata,
    input  logic        bus_ack,
    input  logic [15:0] bus_rdata,

    output logic [63:0] cycles_o,
    output logic        halted_o,
    output logic        st_badop_o,
    output logic [19:0] badop_pc_o,
    output logic [7:0]  badop_o,
    output logic        irq_taken_o,
    output logic [19:0] pc_o
);
    logic        reset;
    assign reset = !rst_n;

    /* ---- interrupt request: level + vector, as the s80x86 wants them */
    logic        intr_q;
    logic [7:0]  vec_q;
    logic        inta;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            intr_q <= 1'b0;
            vec_q  <= 8'h00;
        end else begin
            if (irq_clear_i || inta)
                intr_q <= 1'b0;
            else if (irq_i) begin
                intr_q <= 1'b1;
                vec_q  <= irq_vec_i;
            end
            if (irq_i && !irq_clear_i && !inta)
                vec_q <= irq_vec_i;
        end
    end

    /* ---- the core */
    logic [19:1] instr_addr, data_addr;
    logic [15:0] instr_din, data_din, data_dout;
    logic        instr_access, instr_ack, data_access, data_ack, data_wr, d_io, lock_unused;
    logic [1:0]  data_bytesel;
    logic        dbg_stopped_unused;
    logic [15:0] dbg_val_unused, obs_cs, obs_ip;
    logic        obs_hlt;

    Core u_core (
        .clk             (clk),
        .reset           (reset),
        .nmi             (nmi_i),
        .intr            (intr_q),
        .irq             (vec_q),
        .inta            (inta),
        .instr_m_addr    (instr_addr),
        .instr_m_data_in (instr_din),
        .instr_m_access  (instr_access),
        .instr_m_ack     (instr_ack),
        .data_m_addr     (data_addr),
        .data_m_data_in  (data_din),
        .data_m_data_out (data_dout),
        .data_m_access   (data_access),
        .data_m_ack      (data_ack),
        .data_m_wr_en    (data_wr),
        .data_m_bytesel  (data_bytesel),
        .d_io            (d_io),
        .lock            (lock_unused),
        .debug_stopped   (dbg_stopped_unused),
        .debug_seize     (1'b0),
        .debug_addr      (8'h00),
        .debug_run       (1'b0),
        .debug_val       (dbg_val_unused),
        .debug_wr_val    (16'h0000),
        .debug_wr_en     (1'b0),
        .obs_cs          (obs_cs),
        .obs_ip          (obs_ip),
        .obs_hlt         (obs_hlt)
    );

    /* ---- merging the two buses: one request in flight, the data bus first.
       IDLE -> issue (latch the request, raise bus_req) -> bus_ack -> ack the master for one clock, drop bus_req -> wait for bus_ack low -> IDLE */
    typedef enum logic [1:0] { B_IDLE = 2'd0, B_REQ = 2'd1, B_REL = 2'd2 } bst_t;
    bst_t        bst_q;
    logic        gr_b_q;
    logic [19:1] addr_q;
    logic [15:0] wdata_q;
    logic        wr_q, io_q;
    logic [1:0]  bsel_q;

    always_comb begin
        bus_req   = (bst_q == B_REQ);
        bus_addr  = {addr_q, (bsel_q == 2'b10)};
        bus_wr    = wr_q;
        bus_w     = (bsel_q == 2'b11);
        bus_io    = io_q;
        bus_wdata = (bsel_q == 2'b10) ? {8'h00, wdata_q[15:8]} : wdata_q;
        /* the master is acked in the clock the bus answers; the data lane follows the byte select */
        instr_ack = (bst_q == B_REQ) && !gr_b_q && bus_ack;
        data_ack  = (bst_q == B_REQ) &&  gr_b_q && bus_ack;
        instr_din = bus_rdata;
        data_din  = (bsel_q == 2'b10) ? {bus_rdata[7:0], 8'h00} : (bsel_q == 2'b01) ? {8'h00, bus_rdata[7:0]} : bus_rdata;
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            bst_q   <= B_IDLE;
            gr_b_q  <= 1'b0;
            addr_q  <= 19'd0;
            wdata_q <= 16'h0000;
            wr_q    <= 1'b0;
            io_q    <= 1'b0;
            bsel_q  <= 2'b11;
        end else begin
            case (bst_q)
                B_IDLE: begin
                    if (data_access) begin
                        gr_b_q  <= 1'b1;
                        addr_q  <= data_addr;
                        wdata_q <= data_dout;
                        wr_q    <= data_wr;
                        io_q    <= d_io;
                        bsel_q  <= data_bytesel;
                        bst_q   <= B_REQ;
                    end else if (instr_access) begin
                        gr_b_q  <= 1'b0;
                        addr_q  <= instr_addr;
                        wdata_q <= 16'h0000;
                        wr_q    <= 1'b0;
                        io_q    <= 1'b0;
                        bsel_q  <= 2'b11;
                        bst_q   <= B_REQ;
                    end
                end
                B_REQ: if (bus_ack) bst_q <= B_REL;
                B_REL: if (!bus_ack) bst_q <= B_IDLE;
                default: bst_q <= B_IDLE;
            endcase
        end
    end

    /* ---- observation */
    always_ff @(posedge clk)
        if (!rst_n) cycles_o <= 64'd0;
        else        cycles_o <= cycles_o + 64'd1;
    assign halted_o    = obs_hlt;
    assign st_badop_o  = 1'b0;
    assign badop_pc_o  = 20'd0;
    assign badop_o     = 8'd0;
    assign irq_taken_o = inta;
    assign pc_o        = {obs_cs, 4'h0} + {4'h0, obs_ip};
endmodule
