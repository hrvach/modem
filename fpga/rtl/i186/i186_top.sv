`timescale 1ns/1ps
/*
i186_top.sv -- 80C186EB system top level (Cyclone V).

Wires worker 6's i186_core (CPU) to i186_sys (bus fabric +
peripherals) and exposes the harness ports. The 1 MB RAM lives in
the Verilator C++ harness behind the h_* port, never in M10K.

i186_core interface (worker 6 owns the module; this is the port
list the top uses -- see docs/i186_cosim.md for the contract):
  Bus master: bus_req (level, held until bus_ack), bus_wr,
    bus_w (1 = word, 0 = byte), bus_io (1 = IO space, port in
    bus_addr[15:0]), bus_addr[19:0], bus_wdata[15:0],
    bus_rdata[15:0] (valid with bus_ack), bus_ack (1-cycle pulse
    from the sys).
  Configuration: cyc_model_i (0 = flat 4/instr, 1 = Table D-2),
    ud_trap_i (1 = bad opcode raises INT 6). Both are level
    inputs from the harness, stable after reset (glue defaults
    are cyc_model = 1, ud_trap = 1).
  Interrupts: nmi_i / irq_i are edge-latched in the core (a
    rising edge latches the request; irq_vec_i is latched on
    that edge). irq_clear_i is a level that clears a pending
    IRQ. The top converts the sys's level irq_req / irq_vec
    into edge pulses (see the adapter below) and derives the
    sys's irq_ack from the core's IVT read (see below).
  Status: cycles_o[63:0] (elapsed clocks, frozen while halted
    or after a terminal bad opcode), halted_o, pc_o[19:0]
    (linear PC), st_badop_o, badop_pc_o[19:0], badop_o[7:0].
    The architectural registers (gpr/sreg/ip/flags) are NOT
    top-level ports: worker 6 marks them verilator public in
    the core, and the co-sim harness reads them directly
    through the Verilator model. The top does not use
    hierarchical references (they are not synthesizable).

IRQ adapter (top-level, between the sys and the core):
  The sys offers an interrupt as a level (irq_req + irq_vec).
  The core latches on a rising edge of irq_i, so the top
  pulses irq_i for one clock when the offer rises or when
  the offered vector changes, and records the pulsed vector
  in irq_vec_latched (the vector the core has pending).
  irq_clear_i is driven as !irq_req: whenever the sys has
  no interrupt offered, any pending IRQ in the core is stale
  (the firmware acked it before the core took it), so it is
  cleared. When irq_req rises, irq_clear_i drops in the same
  cycle, so the new edge is never suppressed by the clear.
  nmi_i is the harness nmi_req level passed through (the core
  does its own edge detection); the firmware never uses NMI,
  so the harness ties it low.

irq_ack derivation (top-level, core -> sys):
  The core has no interrupt-taken output, but its entry
  sequence is architectural (C do_int): push FLAGS/CS/IP,
  then read the IVT IP slot at vec*4 and the CS slot at
  vec*4+2. The top watches the bus for a word read of the
  IVT IP slot of the latched vector (bus_addr ==
  {10'b0, irq_vec_latched, 2'b00}) that is acknowledged,
  while an interrupt is offered. That read completes the
  core's claim of the interrupt, so the top pulses irq_ack
  (with irq_ack_vec = irq_vec_latched) and the sys moves
  that source to in-service. The CS read (vec*4+2) does not
  pulse, so there is exactly one ack per entry. A fault or
  trap entry (divide, single-step, INT n, BOUND) reads a
  different vector's IVT slot, so it does not ack the
  external IRQ; the external IRQ stays offered and is acked
  when the core takes it. See docs/i186_cosim.md KNOWN-DIFF
  for the residual edge cases (a software INT n whose
  vector equals the offered external vector, while an
  external IRQ is offered, acks the external IRQ early;
  the take order is unchanged).

Cycle model: the core consumes MORE clocks per instruction than
  the C model charges (bus latency, ~4 clocks per harness
  transaction), so wall clocks != charged cycles and cycles_o
  runs ahead of the C cycle count by the accumulated overhead
  (tracked and reported by the co-sim harness, not required to
  be zero). The sys peripherals therefore run on MODEL time:
  the harness drives model_tick_en for exactly the C charged
  cycles of each instruction, and the sys timers/UART TX advance
  only on enabled clocks. Timer/UART writes are deferred to the
  instruction boundary: the top pulses retire_i to the sys when
  pc_o changes (the core starts the next instruction), and the
  sys applies the latched writes then. A REP string iteration
  retires as its own instruction (matching the C model with a
  1-cycle budget). Interrupt entry advances cycles_o by 42 in
  model 1 (C do_int charge). While halted (HLT, no pending IRQ)
  the core freezes cycles_o and asserts halted_o (the C
  model's HLT budget-burn is a run-loop behaviour, not
  modelled in the core; see docs/i186_cosim.md).
Single clock, active-low synchronous reset, no gated clocks.
*/
`default_nettype none

module i186_top #(
    parameter bit USE_S86 = 1'b0   /* 1: the s80x86 core (rtl/s80x86, GPL-3) instead of i186_core */
) (
    input  logic        clk,
    input  logic        ce_i, /* 186 clock enable: every register advances only when high */
    input  logic        rst_n,
    /* Model-time tick enable (harness-driven): high for exactly
       the C charged cycles of the current instruction. The sys
       timers and UART TX countdowns advance only on enabled
       clocks. */
    input  logic        model_tick_en,
    input  logic        nmi_req,
    input  logic        cyc_model,
    input  logic        ud_trap,

    /* Harness memory + MMIO hook port (1 MB RAM + flash-ID in harness) */
    output logic        h_req,
    output logic        h_wr,
    output logic        h_word,
    output logic        h_is_mmio,
    output logic [19:0] h_addr,
    output logic [15:0] h_wdata,
    input  logic [15:0] h_rdata,
    input  logic        h_ack,

    /* DTE / outside world (harness-driven) */
    output logic        dte_tx_valid,
    output logic [7:0]  dte_tx_byte,
    input  logic        dte_rx_valid,
    input  logic [7:0]  dte_rx_byte,
    input  logic        line,
    output logic        dsp_start_req,
    output logic        burst_valid,
    output logic [63:0] burst_data,

    /* Configuration inputs (harness-driven, stable after reset) */
    input  logic [7:0]  port_in_10,
    input  logic [7:0]  port_in_12,
    input  logic [7:0]  port_in_14,
    input  logic [3:0]  hw_idx,
    input  logic        ring_on,
    input  logic [63:0] hb_count,
    input  logic [63:0] hb_ticks,
    input  logic [7:0]  p2pin_in,

    /* EEPROM load (harness writes while rst_n == 0) */
    input  logic        ee_load_en,
    input  logic [7:0]  ee_load_addr,
    input  logic [15:0] ee_load_data,

    /* Core status (harness diff + run control) */
    output logic [63:0] core_cycles,
    output logic        core_halted,
    output logic [19:0] core_pc,
    output logic        core_badop,
    output logic [19:0] core_badop_pc,
    output logic [7:0]  core_badop_opcode,

    /* Sys observation (harness / debug) */
    output logic        speaker_on,
    output logic [24:0] dbg_icu,
    output logic [7:0]  dbg_evt,
    output logic [15:0] dbg_h2d0,
    output logic [15:0] dbg_pcb_relreg,

    /* DSP glue hooks, straight through to i186_sys */
    input  logic        dsp_run_i,
    input  logic [7:0]  glue_rd_data_i,
    output logic [15:0] glue_rd_port_o,
    output logic        glue_rd_commit_o,
    output logic        glue_wr_commit_o,
    output logic [15:0] glue_wr_port_o,
    output logic [7:0]  glue_wr_data_o,
    input  logic        int0_set_i
);
    logic        bus_req, bus_wr, bus_word, bus_io;
    logic [19:0] bus_addr;
    logic [15:0] bus_wdata, bus_rdata;
    logic        bus_ack;
    logic        irq_req;
    logic [7:0]  irq_vec;
    logic        core_irq_taken;
    logic        irq_ack;
    logic [7:0]  irq_ack_vec;

    /*
    IRQ adapter state: the previous offer (for edge detection)
    and the vector last pulsed to the core (the vector the core
    has pending; used to recognise its IVT read and to tell the
    sys which source to move to in-service).
    */
    logic        irq_req_prev;
    logic [7:0]  irq_vec_prev;
    logic [7:0]  irq_vec_latched;
    logic        irq_pulse;

    always_comb begin
        irq_pulse = irq_req && (!irq_req_prev || (irq_vec != irq_vec_prev));
    end

    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                irq_req_prev <= 1'b0;
                irq_vec_prev <= 8'h00;
                irq_vec_latched <= 8'h00;
            end else begin
                irq_req_prev <= irq_req;
                irq_vec_prev <= irq_vec;
                if (irq_pulse)
                    irq_vec_latched <= irq_vec;
            end
        
        end
    end

    /*
    irq_ack: the core's IVT IP-slot read for the latched vector,
    acknowledged, while an interrupt is offered. One pulse per
    entry (the CS-slot read at vec*4+2 does not match, so it
    does not pulse). irq_ack_vec carries the latched vector so
    the sys moves the source the core actually took, even if
    the offered vector changed mid-entry.
    */
    always_comb begin
        irq_ack = core_irq_taken && irq_req;   /* the core's own report that it takes an external interrupt (the old bus snoop of the IVT slot read was fooled by ordinary reads of that address) */
        irq_ack_vec = irq_vec_latched;
    end

    /*
    Retire pulse: pc_o (instr_start_pc) changes when the core
    starts fetching the next instruction, i.e. at an instruction
    boundary. The pulse is high for the first clock of the next
    instruction's window; the sys applies deferred timer/UART
    writes on it (see the cycle model above). pc_q resets to the
    reset vector (CS=FFFF, IP=0) so no retire fires at reset.
    */
    logic [19:0] pc_q;
    logic        retire_pulse;

    always_comb begin
        retire_pulse = (core_pc != pc_q);
    end

    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n)
                pc_q <= 20'hFFFF0;
            else
                pc_q <= core_pc;
        
        end
    end

    generate if (USE_S86) begin : g_cpu
    i186_core_s86 u_core (
        .clk          (clk),
        .ce_i          (ce_i),
        .rst_n        (rst_n),
        .cyc_model_i  (cyc_model),
        .ud_trap_i    (ud_trap),
        .nmi_i        (nmi_req),
        .irq_i        (irq_pulse),
        .irq_vec_i    (irq_vec),
        .irq_clear_i  (!irq_req),
        .bus_req      (bus_req),
        .bus_addr     (bus_addr),
        .bus_wr       (bus_wr),
        .bus_w        (bus_word),
        .bus_io       (bus_io),
        .bus_wdata    (bus_wdata),
        .bus_ack      (bus_ack),
        .bus_rdata    (bus_rdata),
        .cycles_o     (core_cycles),
        .halted_o     (core_halted),
        .st_badop_o   (core_badop),
        .badop_pc_o   (core_badop_pc),
        .badop_o      (core_badop_opcode),
        .irq_taken_o  (core_irq_taken),
        .pc_o         (core_pc)
    );
    end else begin : g_cpu
    i186_core u_core (
        .clk          (clk),
        .ce_i          (ce_i),
        .rst_n        (rst_n),
        .cyc_model_i  (cyc_model),
        .ud_trap_i    (ud_trap),
        .nmi_i        (nmi_req),
        .irq_i        (irq_pulse),
        .irq_vec_i    (irq_vec),
        .irq_clear_i  (!irq_req),
        .bus_req      (bus_req),
        .bus_addr     (bus_addr),
        .bus_wr       (bus_wr),
        .bus_w        (bus_word),
        .bus_io       (bus_io),
        .bus_wdata    (bus_wdata),
        .bus_ack      (bus_ack),
        .bus_rdata    (bus_rdata),
        .cycles_o     (core_cycles),
        .halted_o     (core_halted),
        .st_badop_o   (core_badop),
        .badop_pc_o   (core_badop_pc),
        .badop_o      (core_badop_opcode),
        .irq_taken_o  (core_irq_taken),
        .pc_o         (core_pc)
    );
    end endgenerate

    i186_sys u_sys (
        .clk           (clk),
        .ce_i          (ce_i),
        .rst_n         (rst_n),
        .tick_en_i     (model_tick_en),
        .retire_i      (retire_pulse),
        .bus_req       (bus_req),
        .bus_wr        (bus_wr),
        .bus_word      (bus_word),
        .bus_io        (bus_io),
        .bus_addr      (bus_addr),
        .bus_wdata     (bus_wdata),
        .bus_rdata     (bus_rdata),
        .bus_ack       (bus_ack),
        .irq_req       (irq_req),
        .irq_vec       (irq_vec),
        .irq_ack       (irq_ack),
        .irq_ack_vec   (irq_ack_vec),
        .h_req         (h_req),
        .h_wr          (h_wr),
        .h_word        (h_word),
        .h_is_mmio     (h_is_mmio),
        .h_addr        (h_addr),
        .h_wdata       (h_wdata),
        .h_rdata       (h_rdata),
        .h_ack         (h_ack),
        .dte_tx_valid  (dte_tx_valid),
        .dte_tx_byte   (dte_tx_byte),
        .dte_rx_valid  (dte_rx_valid),
        .dte_rx_byte   (dte_rx_byte),
        .line          (line),
        .dsp_start_req (dsp_start_req),
        .burst_valid   (burst_valid),
        .burst_data    (burst_data),
        .port_in_10    (port_in_10),
        .port_in_12    (port_in_12),
        .port_in_14    (port_in_14),
        .hw_idx        (hw_idx),
        .ring_on       (ring_on),
        .hb_count      (hb_count),
        .hb_ticks       (hb_ticks),
        .p2pin_in      (p2pin_in),
        .ee_load_en    (ee_load_en),
        .ee_load_addr  (ee_load_addr),
        .ee_load_data  (ee_load_data),
        .speaker_on    (speaker_on),
        .dbg_icu       (dbg_icu),
        .dbg_evt       (dbg_evt),
        .dbg_h2d0      (dbg_h2d0),
        .dbg_pcb_relreg (dbg_pcb_relreg),
        .dsp_run_i       (dsp_run_i),
        .glue_rd_data_i  (glue_rd_data_i),
        .glue_rd_port_o  (glue_rd_port_o),
        .glue_rd_commit_o (glue_rd_commit_o),
        .glue_wr_commit_o (glue_wr_commit_o),
        .glue_wr_port_o  (glue_wr_port_o),
        .glue_wr_data_o  (glue_wr_data_o),
        .int0_set_i      (int0_set_i)
    );
endmodule
`default_nettype wire
