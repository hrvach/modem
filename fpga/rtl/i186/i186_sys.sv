`timescale 1ns/1ps
/*
i186_sys.sv -- 80C186EB system wrapper for the Courier modem (Cyclone V).

Bus fabric + peripherals between worker 6's i186_core bus-master port
and the harness. The peripherals live in the GLUE, not the CPU core
(i186.c header comment); this module is their RTL equivalent, matching
glue/machine.c semantics for the ports/registers the SV25 firmware
actually touches (enumerated by a 200M-cycle C-model probe, see
docs/i186_cosim.md). Anything the firmware never touches is a
documented stub (reads 0, writes ignored).

Reference: c-port/c/src/glue/machine.c (machine_iord/iowr,
machine_mmrd/mmwr, preg/pwr, timer_update, icu_eval, eeprom_clock),
c-port/c/src/cpu/i186.c (mem_read/mem_write routing, io_read/io_write).

Bus protocol (core <-> sys): the core asserts bus_req with addr/wr/
word/io/wdata stable; the sys answers with bus_ack for one cycle
(bus_rdata valid with it for reads); the core samples bus_ack on
the next rising edge and moves on. One outstanding transaction.
The core may re-assert bus_req immediately for the next
transaction (bus_req is combinational from its FSM state, so
there is no guaranteed low gap between back-to-back
transactions). The sys therefore does NOT wait for bus_req to
drop: after asserting bus_ack it spends exactly one cycle in
ST_TURNAROUND (the cycle the core samples bus_ack and moves
on), then returns to ST_IDLE, where bus_req/bus_* already
reflect the next transaction (or idle). Latency per
harness-routed transaction is four clocks (ST_IDLE latch +
h_req, ST_HWAIT for h_ack, ST_ACK asserting bus_ack,
ST_TURNAROUND while the core samples it); the ST_EXEC state is
skipped for harness-routed phases. A word access whose two
bytes route differently (C split_word) is performed as two byte
transactions internally.

Routing (20-bit physical address, IO flag):
  IO 0xFF00-0xFFFF && !pcb_mem  -> PCB register file (preg/pwr)
  IO otherwise                 -> ASIC / mailbox / DTE / DIP ports
  MEM page 0xFF or 0x0F        -> harness MMIO hook (flash-ID + RAM
                                  fallback live in the harness)
  MEM page 0x0F, addr 0x0FF00-0x0FFFF && pcb_mem -> PCB register file
  MEM write, page 0x80-0xFE    -> dropped (read-only flash), acked
  MEM otherwise                -> harness RAM (1 MB, lives in the
                                  C++ harness (Verilator), NOT in M10K)

Cycle model (model time, NOT wall clocks): the core consumes more
clocks per instruction than the C model charges (bus latency, ~4
clocks per harness transaction), so the sys timers/UARTs must NOT
tick on every clk. The harness drives tick_en_i for exactly the C
charged cycles of each instruction (the first charge clocks of the
window); the timer dividers and the UART TX countdowns advance
only on enabled clocks, so they stay in lockstep with the C model
(C timer_update advances 1 count per 4 charged cycles, UART TX
completes at tx_t = now + 10*pu). Timer-register and UART-TDR
writes are latched at the bus commit and applied at the next
retire_i pulse (instruction boundary, pc_o change): the C model
sets last = now at the end of the write instruction, so the
divider restarts at 1 on the retire clock (1 enabled clock past
the boundary), not 0 at the commit. See docs/i186_cosim.md.
Single clock, active-low synchronous reset, no gated clocks, no
Quartus primitives.
*/
`default_nettype none

module i186_sys (
    input  logic        clk,
    input  logic        ce_i, /* 186 clock enable: every register advances only when high */
    input  logic        rst_n,

    /* Model-time control (harness/top-driven, see the cycle model
       in the header): tick_en_i enables the timer dividers and
       the UART TX countdowns for this clock; retire_i is a
       one-cycle pulse at an instruction boundary (pc_o change)
       that applies deferred timer/UART writes. */
    input  logic        tick_en_i,
    input  logic        retire_i,

    /* CPU bus-master port (from i186_core) */
    input  logic        bus_req,
    input  logic        bus_wr,
    input  logic        bus_word,
    input  logic        bus_io,
    input  logic [19:0] bus_addr,
    input  logic [15:0] bus_wdata,
    output logic [15:0] bus_rdata,
    output logic        bus_ack,

    /* Interrupt to CPU core (ICU, continuous evaluation) */
    output logic        irq_req,
    output logic [7:0]  irq_vec,
    input  logic        irq_ack, /* core pulses when it takes the interrupt */
    input  logic [7:0]  irq_ack_vec, /* vector the core took (top latches it) */

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
    output logic        dte_tx_valid, /* pulse: byte to the DTE */
    output logic [7:0]  dte_tx_byte,
    input  logic        dte_rx_valid, /* pulse: byte from the DTE (UART0) */
    input  logic [7:0]  dte_rx_byte,
    input  logic        line, /* DTE TXD level, 1 = mark/idle */
    output logic        dsp_start_req, /* pulse: firmware wrote 4 to port 0x18 */
    output logic        burst_valid, /* pulse: 8-byte overlay burst complete */
    output logic [63:0] burst_data,

    /* Configuration inputs (harness-driven, stable after reset) */
    input  logic [7:0]  port_in_10, /* default 8'h00 */
    input  logic [7:0]  port_in_12, /* default 8'h9A (DIP 3,5,8,9 ON) */
    input  logic [7:0]  port_in_14, /* default 8'h44 */
    input  logic [3:0]  hw_idx, /* default 4'd7 (sv25 profile) */
    input  logic        ring_on, /* default 0 */
    input  logic [63:0] hb_count, /* default 0 (no DSP samples in lite mode) */
    input  logic [63:0] hb_ticks, /* default 3 */
    input  logic [7:0]  p2pin_in, /* default 8'h40 (sw1 off) */

    /* EEPROM load (harness writes while rst_n == 0) */
    input  logic        ee_load_en,
    input  logic [7:0]  ee_load_addr,
    input  logic [15:0] ee_load_data,

    /* Observation (harness / debug) */
    output logic        speaker_on,   /* the firmware's speaker latch: port 0x12 bit 4, active low; counts as off until the first write (as in the web interface) */
    output logic [24:0] dbg_icu,      /* bring-up: {request bits (10), in-service bits (7), mask (8)} of the interrupt controller */
    output logic [7:0]  dbg_evt,
    output logic [15:0] dbg_h2d0,
    output logic [15:0] dbg_pcb_relreg,

    /* DSP glue hooks (rtl/dsp_glue.sv): once the DSP runs, ports 0x18..0x1E, 0x40..0x5E and 0x60/0x62 belong to the glue */
    input  logic        dsp_run_i,
    input  logic [7:0]  glue_rd_data_i,
    output logic [15:0] glue_rd_port_o,
    output logic        glue_rd_commit_o,
    output logic        glue_wr_commit_o,
    output logic [15:0] glue_wr_port_o,
    output logic [7:0]  glue_wr_data_o,
    input  logic        int0_set_i
);
    /*
    ------------------------------------------------------------------
    Interrupt sources (machine.c SRC table, machine.h enum order).
    ------------------------------------------------------------------
    */
    localparam logic [3:0] S_T0 = 4'd0, S_T1 = 4'd1, S_T2 = 4'd2,
                               S_S0RX = 4'd3, S_S0TX = 4'd4, S_INT4 = 4'd5,
                               S_INT0 = 4'd6, S_INT1 = 4'd7, S_INT2 = 4'd8,
                               S_INT3 = 4'd9;

    /*
    Architectural constants. Every value is taken from the C model
    (glue/machine.c, cited by function) or the 80C186EB register map
    the C model implements. A reader with machine.c open can trace any
    constant below to its source; the RTL uses these names, not the
    raw numbers.
    */
    /* PCB register map (machine.c preg/pwr register ranges). */
    localparam logic [7:0] PCB_TIMER_BASE = 8'h30;
    localparam logic [7:0] PCB_TIMER_END = 8'h46;
    localparam logic [7:0] PCB_UART_BASE = 8'h60;
    localparam logic [7:0] PCB_UART_END = 8'h7A;
    localparam logic [7:0] PCB_IMASK_REG = 8'h08;
    localparam logic [7:0] PCB_PRIMSK_REG = 8'h0A;
    localparam logic [7:0] PCB_EOI_REG = 8'h02;
    localparam logic [7:0] PCB_INSV_REG = 8'h0C;
    localparam logic [7:0] PCB_REQSUM_REG = 8'h0E;
    localparam logic [7:0] PCB_REQ7_REG = 8'h10;
    localparam logic [7:0] PCB_P1LTCH_REG = 8'h56;
    localparam logic [7:0] PCB_P2PIN_REG = 8'h5A;
    localparam logic [7:0] PCB_RELREG = 8'hA8;
    /* Timer CON bits (machine.c timer_run / timer_update / pwr). */
    localparam logic [15:0] TMR_CON_EN = 16'h8000;
    localparam logic [15:0] TMR_CON_EN_GATE = 16'h4000;
    localparam logic [15:0] TMR_CON_INTEN = 16'h2000;
    localparam logic [15:0] TMR_CON_MC = 16'h0020;
    localparam logic [15:0] TMR_CON_LOW_MASK = 16'h3FFF;
    /* Timer limit when CMPA is 0 (machine.c timer_sched). */
    localparam logic [15:0] TMR_LIM_DEFAULT = 16'hFFFF;
    /* UART (machine.c pwr / timer_update): pu, TX time, STS bits. */
    localparam logic [15:0] UART_CMP_MASK = 16'h7FFF;
    localparam logic [15:0] UART_STS_TXE = 16'h0008;
    localparam logic [15:0] UART_STS_TX_DONE = 16'h0028;
    localparam logic [15:0] UART_STS_RD_CLEAR = 16'h00F4;
    /* DSP mailbox window (machine.c machine_iord/iowr). */
    localparam logic [15:0] MBOX_BASE = 16'h0040;
    localparam logic [15:0] MBOX_END = 16'h005E;
    localparam logic [15:0] MBOX_BURST0_END = 16'h004E;
    localparam logic [15:0] MBOX_BURST1_END = 16'h005E;
    /* Memory map (machine.c machine_mmrd/mmwr, mem_read/mem_write). */
    localparam logic [7:0] MEM_PAGE_MMIO_HI = 8'hFF;
    localparam logic [7:0] MEM_PAGE_MMIO_LO = 8'h0F;
    localparam logic [7:0] MEM_PAGE_RO_LO = 8'h80;
    localparam logic [7:0] MEM_PAGE_RO_HI = 8'hFE;
    /* EEPROM (machine.c eeprom_clock, 93C66-like, 256 words). */
    localparam int EEPROM_WORDS = 256;
    localparam logic [1:0] EEPROM_OP_WDATA = 2'd1;
    localparam logic [1:0] EEPROM_OP_READ = 2'd2;
    localparam logic [1:0] EEPROM_OP_ERASE = 2'd3;
    /* EEPROM control registers (machine.c pwr r == 0x56 / preg r == 0x5A). */
    localparam logic [7:0] PCB_EE_CS_REG = 8'h58;
    localparam logic [7:0] PCB_EE_DATA_REG = 8'h5E;
    /* P2PIN register DO/line bits (machine.c preg r == 0x5A). */
    localparam logic [15:0] PCB_P2PIN_DO_BIT = 16'h0080;
    localparam logic [7:0] PCB_P2PIN_LINE_BIT = 8'h20;
    /* ICU readback bits (machine.c preg). */
    localparam logic [15:0] PCB_ICON_MASK_BIT = 16'h0008;
    localparam logic [15:0] PCB_REQSUM_S0_BIT = 16'h0004;
    /* UART1 STS bits that request INT4 (machine.c machine_requests). */
    localparam logic [15:0] UART_STS_INT4_BITS = 16'h0060;
    /* UART STS bits (machine.c pwr / timer_update). */
    localparam logic [15:0] UART_STS_OE = 16'h0004;
    localparam logic [15:0] UART_STS_RI = 16'h0040;
    /* EEPROM erased value and sub-op codes (machine.c eeprom_clock). */
    localparam logic [15:0] EEPROM_ERASED = 16'hFFFF;
    localparam logic [1:0] EEPROM_SUBOP_EWDS = 2'd0;
    localparam logic [1:0] EEPROM_SUBOP_ERASE_ALL = 2'd2;
    localparam logic [1:0] EEPROM_SUBOP_EWEN = 2'd3;
    /* Low IO ports with special reads/writes (machine.c machine_iord/iowr). */
    localparam logic [15:0] IO_DTE_PORT = 16'h000A;
    localparam logic [15:0] IO_DSP_START_PORT = 16'h0018;
    localparam logic [15:0] IO_EVT_PORT = 16'h001C;
    localparam logic [15:0] IO_OVL_PORT = 16'h001E;
    localparam logic [15:0] IO_PORT0 = 16'h0000;
    localparam logic [15:0] IO_PORT10 = 16'h0010;
    localparam logic [15:0] IO_PORT12 = 16'h0012;
    localparam logic [15:0] IO_PORT14 = 16'h0014;
    localparam logic [7:0] IO_HWID_A_PORT = 8'h12;
    localparam logic [7:0] IO_HWID_B_PORT = 8'h14;
    localparam logic [7:0] IO_DSP_START_CMD = 8'h04;
    localparam logic [7:0] IO_PORT0_MASK = 8'h08;
    localparam logic [15:0] IO_NODSP_18_READ = 16'h0003;
    localparam logic [15:0] IO_PORT14_RING_BIT = 16'h0002;
    localparam logic [15:0] IO_PORT14_HWID_BIT = 16'h0008;
    /* IO PCB window base (machine.c machine_iord/iowr, p >= 0xFF00). */
    localparam logic [15:0] IO_PCB_BASE = 16'hFF00;
    /* MEM PCB window high nibble (machine.c: 0x0FF00-0x0FFFF). */
    localparam logic [3:0] MEM_PCB_NIBBLE = 4'hF;
    /* UART TX bit count (machine.c pwr: tx_t = now + 10 * pu). */
    localparam logic [3:0] UART_TX_BITS = 4'd10;
    /* RELREG bit that moves the PCB to MEM space (machine.c pwr r == 0xA8). */
    localparam logic [15:0] PCB_RELREG_MEM_BIT = 16'h1000;
    /* Peripheral counts (machine.c: 3 timers, 2 UARTs, 7 ICU levels,
       10 interrupt sources, 32 mailbox burst bytes). */
    localparam int TIMER_COUNT = 3;
    localparam int UART_COUNT = 2;
    localparam int ICU_LEVELS = 7;
    localparam int ICU_SOURCES = 10;
    localparam int BURST_TMP_BYTES = 32;

    /* (vector, IMASK bit, control register) per source. */
    function automatic [7:0] src_vec(input logic [3:0] src_index);
        case (src_index)
            S_T0:   src_vec = 8'h08;
            S_T1:   src_vec = 8'h12;
            S_T2:   src_vec = 8'h13;
            S_S0RX: src_vec = 8'h14;
            S_S0TX: src_vec = 8'h15;
            S_INT4: src_vec = 8'h11;
            S_INT0: src_vec = 8'h0C;
            S_INT1: src_vec = 8'h0D;
            S_INT2: src_vec = 8'h0E;
            S_INT3: src_vec = 8'h0F;
            default: src_vec = 8'h00;
        endcase
    endfunction
    function automatic [7:0] src_bit(input logic [3:0] src_index);
        case (src_index)
            S_T0, S_T1, S_T2: src_bit = 8'h01;
            S_S0RX, S_S0TX:   src_bit = 8'h04;
            S_INT4:           src_bit = 8'h08;
            S_INT0:           src_bit = 8'h10;
            S_INT1:           src_bit = 8'h20;
            S_INT2:           src_bit = 8'h40;
            S_INT3:           src_bit = 8'h80;
            default:          src_bit = 8'h00;
        endcase
    endfunction
    function automatic [7:0] src_con(input logic [3:0] src_index);
        case (src_index)
            S_T0, S_T1, S_T2: src_con = 8'h12;
            S_S0RX, S_S0TX:   src_con = 8'h14;
            S_INT4:           src_con = 8'h16;
            S_INT0:           src_con = 8'h18;
            S_INT1:           src_con = 8'h1A;
            S_INT2:           src_con = 8'h1C;
            S_INT3:           src_con = 8'h1E;
            default:          src_con = 8'h00;
        endcase
    endfunction
    /* Control register -> IMASK bit (machine.c con_bit). */
    function automatic [7:0] con_bit(input [7:0] regno);
        case (regno)
            8'h12: con_bit = 8'h01;
            8'h14: con_bit = 8'h04;
            8'h16: con_bit = 8'h08;
            8'h18: con_bit = 8'h10;
            8'h1A: con_bit = 8'h20;
            8'h1C: con_bit = 8'h40;
            8'h1E: con_bit = 8'h80;
            default: con_bit = 8'h00;
        endcase
    endfunction
    /* Vector type -> IMASK bit for EOI (machine.c eoi_bit). */
    function automatic [7:0] eoi_bit(input [7:0] vec);
        case (vec)
            8'h08, 8'h12, 8'h13: eoi_bit = 8'h01;
            8'h14, 8'h15:        eoi_bit = 8'h04;
            8'h11:              eoi_bit = 8'h08;
            8'h0C:              eoi_bit = 8'h10;
            8'h0D:              eoi_bit = 8'h20;
            8'h0E:              eoi_bit = 8'h40;
            8'h0F:              eoi_bit = 8'h80;
            default:             eoi_bit = 8'h00;
        endcase
    endfunction

    /*
    ------------------------------------------------------------------
    State.
    ------------------------------------------------------------------
    PCB register store: 16-bit words at even offsets 0x00..0xFE.
    (pwr always writes a full word at an even reg; preg always reads
    a full word at an even reg -- the byte merge happens in the bus
    layer, exactly as in machine_iowr/machine_mmwr.)
    */
    (* ramstyle = "M10K" *) logic [15:0] pcb_w [0:127];   /* RAM: registered read (pcb_q); the few registers read asynchronously keep flop copies (pcb_sh_*) */
    logic        pcb_mem; /* RELREG bit12 (reg 0xA8) */
    /* Generic low-port store: IO ports 0x00..0x7F (16-bit values). */
    (* ramstyle = "M10K" *) logic [15:0] ports_w [0:127];   /* RAM: registered read (ports_q); ports 0x00/0x12/0x14 keep flop copies (ports_sh_*) */
    logic        ports_set [0:127];
    logic [15:0] pcb_q, ports_q;
    logic [15:0] pcb_sh_56, pcb_sh_58, pcb_sh_5e, pcb_sh_a8;
    logic [15:0] ports_sh_00, ports_sh_12, ports_sh_14;
    /* DSP mailbox h2d words (0x58..0x5F); d2h stays 0 (no DSP). */
    logic [15:0] h2d_w [0:7];
    logic [7:0]  burst_tmp [0:BURST_TMP_BYTES-1]; /* bytes for ports 0x40..0x5E */
    logic [7:0]  evt_r;
    /* ICU. */
    logic [9:0]  req_r;
    logic [7:0]  msk_r; /* IMASK (bit1 forced 0 on write) */
    logic [2:0]  primsk_r;
    logic [2:0]  icon_12, icon_14, icon_16, icon_18, icon_1a, icon_1c, icon_1e;
    logic [ICU_LEVELS-1:0] isv_present_r; /* by IMASK-bit index 0..6 */
    logic [2:0]  isv_val_r [0:ICU_LEVELS-1];
    /* Timers. */
    logic [15:0] tmr_cnt [0:TIMER_COUNT-1], tmr_cmpa [0:TIMER_COUNT-1], tmr_cmpb [0:TIMER_COUNT-1], tmr_con [0:TIMER_COUNT-1];
    logic [1:0]  tmr_div [0:TIMER_COUNT-1];
    /* Deferred timer writes (model time): a pwr commit to a timer
       register latches here and is applied at the next retire_i
       pulse (instruction boundary), not at the commit. pend_sel
       holds (cmt_pcb_reg & 6): 0 CNT, 2 CMPA, 4 CMPB, 6 CON. */
    logic        tmr_pend_vld [0:TIMER_COUNT-1];
    logic [2:0]  tmr_pend_sel [0:TIMER_COUNT-1];
    logic [15:0] tmr_pend_val [0:TIMER_COUNT-1];
    /* UARTs. */
    logic [15:0] uart_cmp [0:UART_COUNT-1], uart_con [0:UART_COUNT-1], uart_sts [0:UART_COUNT-1], uart_rbuf [0:UART_COUNT-1];
    logic [21:0] uart_tx_left [0:UART_COUNT-1]; /* 0 = idle; counts down in enabled (model-time) clocks */
    logic        uart_rx_pend [0:UART_COUNT-1];
    /* Deferred UART TDR writes (model time): a TDR commit latches
       here and is applied at the next retire_i pulse. */
    logic        uart_pend_tdr [0:UART_COUNT-1];
    logic [7:0]  uart_pend_byte [0:UART_COUNT-1];
    /* EEPROM (Microwire 93C66-like, 256x16; combinational read). */
    (* ramstyle = "M10K" *) logic [15:0] ee_w [0:EEPROM_WORDS-1];   /* RAM: one staged write port, one free-running registered read */
    logic        ee_we_q, ee_ea_req_q, ee_ea_q, ee_ea_prev_q;
    logic [7:0]  ee_wa_q, ee_sw_q;
    logic [15:0] ee_wd_q, ee_rd_q;
    logic        ee_ewen;
    logic [1:0]  ee_state; /* 0 IDLE, 1 CMD, 2 READ, 3 WDATA */
    logic [3:0]  ee_nbits;
    logic [14:0] ee_bits;
    logic        ee_do_bit;
    logic [7:0]  ee_addr;
    logic [3:0]  ee_rdn;
    /* Line level (DTE TXD) + edge detect. */
    logic        line_r;

    /* ring cadence: the C model clears the ring-detect bit while (hb_count / hb_ticks / 60) is odd. hb_count counts DSP timer expiries (hb_ticks = 1 here), so a 64-bit divide is a
       counter modulo 120 that follows the expiries: the line is "ringing" for 60 of them, quiet for 60 */
    logic [6:0] ring_cnt_q;
    logic [7:0] ring_hb_prev_q;
    logic [7:0] ring_delta_c;
    logic [7:0] ring_sum_c;
    logic       ring_phase_c;
    always_comb begin
        ring_delta_c = hb_count[7:0] - ring_hb_prev_q;
        ring_sum_c   = {1'b0, ring_cnt_q} + ring_delta_c;
        ring_phase_c = (ring_cnt_q >= 7'd60);
    end
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ring_cnt_q     <= 7'd0;
            ring_hb_prev_q <= 8'd0;
        end else begin
            ring_hb_prev_q <= hb_count[7:0];
            if (ring_delta_c != 8'd0)
                ring_cnt_q <= (ring_sum_c >= 8'd120) ? (ring_sum_c - 8'd120) : ring_sum_c[6:0];
        end
    end

    /* ICON mux (control register -> 3-bit level, default 0x07). */
    function automatic [2:0] icon_of(input [7:0] regno);
        case (regno)
            8'h12: icon_of = icon_12;
            8'h14: icon_of = icon_14;
            8'h16: icon_of = icon_16;
            8'h18: icon_of = icon_18;
            8'h1A: icon_of = icon_1a;
            8'h1C: icon_of = icon_1c;
            8'h1E: icon_of = icon_1e;
            default: icon_of = 3'd7;
        endcase
    endfunction

    /*
    HW ID bit (machine.c machine_hw_id_bit): ports 0x12/0x14 override
    the DIP values when written (ports_set), hw_idx selects the bit.
    (D,A,B,C) = (port14 bit6, port12 bit1, port14 bit4, port14 bit5);
    an unwritten port reads as 0xFF (bit = 1, no effect).
    */
    logic his_d, his_a, his_b, his_c;
    logic hw_id_bit_c;
    always_comb begin
        his_d = ports_set[IO_HWID_B_PORT[6:0]] ? ports_sh_14[6] : 1'b1;
        his_a = ports_set[IO_HWID_A_PORT[6:0]] ? ports_sh_12[1] : 1'b1;
        his_b = ports_set[IO_HWID_B_PORT[6:0]] ? ports_sh_14[4] : 1'b1;
        his_c = ports_set[IO_HWID_B_PORT[6:0]] ? ports_sh_14[5] : 1'b1;
        hw_id_bit_c = 1'b1;
        if (!his_d) hw_id_bit_c = hw_id_bit_c & hw_idx[3];
        if (!his_a) hw_id_bit_c = hw_id_bit_c & hw_idx[2];
        if (!his_b) hw_id_bit_c = hw_id_bit_c & hw_idx[1];
        if (!his_c) hw_id_bit_c = hw_id_bit_c & hw_idx[0];
    end

    /*
    ------------------------------------------------------------------
    preg: PCB register read (machine.c preg, rd flag selects the
    UART-STS side effect, which the FSM applies as a commit pulse).
    ------------------------------------------------------------------
    */
    function automatic [15:0] preg_val(input [7:0] regno);
        logic [1:0] i;
        logic j;
        int reg_offset;
        logic [15:0] read_value;
        begin
            if (regno >= PCB_TIMER_BASE && regno <= PCB_TIMER_END) begin
                /* Timer index from the register number: the three
                   timers sit 8 bytes apart starting at
                   PCB_TIMER_BASE, so regno[7:3] is the base index
                   plus 0/1/2. Case labels are that base plus the
                   timer number (no magic numbers). */
                case (regno[7:3])
                    PCB_TIMER_BASE[7:3]: i = 2'd0;
                    PCB_TIMER_BASE[7:3] + 5'd1: i = 2'd1;
                    PCB_TIMER_BASE[7:3] + 5'd2: i = 2'd2;
                    default: i = 2'd0;
                endcase
                reg_offset = {24'b0, regno} & 6;
                case (reg_offset >> 1)
                    0: read_value = tmr_cnt[i];
                    1: read_value = tmr_cmpa[i];
                    2: read_value = tmr_cmpb[i];
                    default: read_value = tmr_con[i];
                endcase
            end else if (regno >= PCB_UART_BASE && regno <= PCB_UART_END) begin
                j = regno[4];
                reg_offset = {24'b0, regno} & 14;
                if (reg_offset == 6) read_value = uart_sts[j];
                else if (reg_offset <= 8'h0A) begin
                    case (reg_offset >> 1)
                        0: read_value = uart_cmp[j];
                        1: read_value = 16'h0000;
                        2: read_value = uart_con[j];
                        3: read_value = 16'h0000;
                        4: read_value = uart_rbuf[j];
                        default: read_value = 16'h0000;
                    endcase
                end else read_value = 16'h0000;
            end else if (con_bit(regno) != 8'h00) begin
                read_value = {13'b0, icon_of(regno)} | ((msk_r & con_bit(regno)) != 0 ? PCB_ICON_MASK_BIT : 16'h0000);
            end else if (regno == PCB_IMASK_REG) read_value = {8'h00, msk_r};
            else if (regno == PCB_PRIMSK_REG) read_value = {13'b0, primsk_r};
            else if (regno == PCB_INSV_REG) begin
                read_value = 16'h0000;
                for (int level_index = 0; level_index < ICU_LEVELS; level_index++)
                    if (isv_present_r[level_index]) read_value = read_value + {13'b0, isv_val_r[level_index]};
            end else if (regno == PCB_REQSUM_REG) begin
                read_value = 16'h0000;
                for (int src_index = 0; src_index < ICU_SOURCES; src_index++)
                    if (req_eff[src_index] && src_index[3:0] != S_T1 && src_index[3:0] != S_T2 && src_index[3:0] != S_S0TX)
                        read_value = read_value + {8'b0, src_bit(src_index[3:0])};
                if (req_eff[2:0] != 3'b000) read_value = read_value | 16'h0001;
                if (req_eff[4:3] != 2'b00) read_value = read_value | PCB_REQSUM_S0_BIT;
            end else if (regno == PCB_REQ7_REG) read_value = {13'b0, req_r[2:0]};
            else if (regno == PCB_P2PIN_REG) begin
                read_value = {8'b0, ((p2pin_in & ~PCB_P2PIN_LINE_BIT) | (line_r ? PCB_P2PIN_LINE_BIT : 8'h00))};
                read_value = read_value & ~PCB_P2PIN_DO_BIT;
                if (pcb_sh_58[7]) read_value = read_value | (ee_do_bit ? PCB_P2PIN_DO_BIT : 16'h0000);
                else read_value = read_value | {8'b0, pcb_sh_5e[7], 7'b0};
            end else begin
                read_value = pcb_q;
            end
            preg_val = read_value;
        end
    endfunction

    /*
    ------------------------------------------------------------------
    ICU: effective requests (machine_requests) + continuous eval
    (machine.c icu_eval). The C driver evaluates at chunk boundaries;
    the RTL evaluates continuously and the core samples irq_req at
    instruction boundaries (see KNOWN-DIFF in docs/i186_cosim.md).
    ------------------------------------------------------------------
    */
    logic [9:0] req_eff;
    always_comb begin
        req_eff = req_r;
        if ((uart_sts[1] & UART_STS_INT4_BITS) != 16'h0000) req_eff[S_INT4] = 1'b1;
    end

    logic [3:0] icu_best;
    logic       icu_best_v;
    logic [3:0] icu_bp;
    always_comb begin
        icu_bp = 4'd8; /* C: bp starts at 8 (no in-service level) */
        for (int level_index = 0; level_index < ICU_LEVELS; level_index++)
            if (isv_present_r[level_index[2:0]] && ({1'b0, isv_val_r[level_index[2:0]]} < icu_bp))
        icu_bp = {1'b0, isv_val_r[level_index]};
        /* C: if (primsk + 1 < bp) bp = primsk + 1. */
        if ({1'b0, primsk_r} + 4'd1 < icu_bp)
            icu_bp = {1'b0, primsk_r} + 4'd1;
        icu_best = 4'd0;
        icu_best_v = 1'b0;
        for (int src_index = 0; src_index < ICU_SOURCES; src_index++) begin
            if (req_eff[src_index] && ((msk_r & src_bit(src_index[3:0])) == 8'h00) &&
                ({1'b0, icon_of(src_con(src_index[3:0]))} < icu_bp)) begin
                icu_best = src_index[3:0];
                icu_best_v = 1'b1;
                icu_bp = {1'b0, icon_of(src_con(src_index[3:0]))};
            end
        end
    end
    assign irq_req = icu_best_v;
    assign irq_vec = src_vec(icu_best);

    /*
    ------------------------------------------------------------------
    Bus decode (combinational, for the latched transaction).
    ------------------------------------------------------------------
    */
    typedef enum logic [2:0] {
        RT_RAM, /* harness RAM (is_mmio=0) */
        RT_MMIO, /* harness MMIO hook (is_mmio=1) */
        RT_PCB, /* PCB register file */
        RT_IO, /* ASIC / mailbox / DTE / DIP ports */
        RT_RODROP /* write to read-only flash page: dropped, acked */
    } route_t;

    function automatic route_t route_of(input [19:0] addr, input io, input wr);
        logic [7:0] page;
        begin
            if (io) begin
                if (addr[15:0] >= IO_PCB_BASE && !pcb_mem) route_of = RT_PCB;
                else route_of = RT_IO;
            end else begin
                page = addr[19:12];
                if (page == MEM_PAGE_MMIO_HI || page == MEM_PAGE_MMIO_LO) begin
                    if (page == MEM_PAGE_MMIO_LO && addr[11:8] == MEM_PCB_NIBBLE && pcb_mem)
                        route_of = RT_PCB;
                    else
                        route_of = RT_MMIO;
                end else if (wr && page >= MEM_PAGE_RO_LO && page <= MEM_PAGE_RO_HI)
                    route_of = RT_RODROP;
                else
                    route_of = RT_RAM;
            end
        end
    endfunction

    /*
    First-phase route and harness values for a fresh transaction
    (computed from bus_* in ST_IDLE, before txn_* are latched).
    The split decision is the C split_word rule: a word whose two
    bytes route differently. For a split word the first phase is a
    byte write/read of the low byte at bus_addr.
    */
    logic        idle_split;
    route_t      idle_route;
    logic        idle_h_word;
    logic [15:0] idle_h_wdata;
    always_comb begin
        idle_split = bus_word && !bus_io &&
            (route_of(bus_addr, bus_io, bus_wr) !=
             route_of(bus_addr + 20'd1, bus_io, bus_wr));
        idle_route = route_of(bus_addr, bus_io, bus_wr);
        idle_h_word = idle_split ? 1'b0 : bus_word;
        idle_h_wdata = idle_split ? {8'b0, bus_wdata[7:0]} : bus_wdata;
    end

    /*
    ------------------------------------------------------------------
    Bus FSM.
    ------------------------------------------------------------------
    */
    typedef enum logic [2:0] {
        ST_IDLE, ST_EXEC, ST_HWAIT, ST_ACK, ST_TURNAROUND
    } fsm_t;
    fsm_t fsm_r;

    /* Latched transaction. */
    logic        txn_wr, txn_word, txn_io;
    logic [19:0] txn_addr;
    logic [15:0] txn_wdata;
    /* Split-word state. */
    logic        txn_split;
    logic        txn_phase; /* 0 = low byte, 1 = high byte */
    logic [7:0]  byte0_r; /* low-byte read result (split reads) */
    logic [15:0] rdata_r;
    /* Current-phase access (combinational from the latched transaction). */
    logic [19:0] ph_addr;
    logic        ph_wr;
    logic        ph_word; /* always 0 for split phases */
    logic [15:0] ph_wdata;
    route_t      ph_route;
    always_comb begin
        if (txn_split) begin
            ph_addr  = txn_addr + (txn_phase ? 20'd1 : 20'd0);
            ph_wr    = txn_wr;
            ph_word  = 1'b0;
            ph_wdata = txn_phase ? {8'b0, txn_wdata[15:8]} : {8'b0, txn_wdata[7:0]};
        end else begin
            ph_addr  = txn_addr;
            ph_wr    = txn_wr;
            ph_word  = txn_word;
            ph_wdata = txn_wdata;
        end
        ph_route = route_of(ph_addr, txn_io, ph_wr);
    end

    /* Commit pulses (one cycle) generated by the FSM. */
    logic        cmt_pcb_wr, cmt_pcb_rd_side;
    logic [7:0]  cmt_pcb_reg;
    logic [15:0] cmt_pcb_val;
    logic        cmt_io_wr;
    logic        cmt_io_rd;
    logic [15:0] cmt_io_rd_port;
    logic [15:0] cmt_io_port;
    logic [15:0] cmt_io_val;
    logic        cmt_io_is_word;

    /*
    Combinational read data for RTL-routed phases (PCB / IO).
    For harness phases the data comes from h_rdata (captured).
    */
    logic [15:0] rtl_rdata_c;
    logic [15:0] preg_rd;
    logic [15:0] io_rd;
    always_comb begin
        /* PCB read: preg value, byte-selected for byte reads. */
        preg_rd = preg_val(ph_addr[7:0]);
        if (!ph_word)
            preg_rd = {8'b0, ph_addr[0] ? preg_rd[15:8] : preg_rd[7:0]};
        /* IO read (ports 0x00..0x7F store; specials below). */
        io_rd = 16'h0000;
        if (ph_addr[15:0] < 16'h0080) io_rd = ports_q;
        if (ph_addr[15:0] == IO_PORT0)
            io_rd = {8'b0, (ports_sh_00[7:0] & ~IO_PORT0_MASK)};
        else if (ph_addr[15:0] == IO_DSP_START_PORT)
            io_rd = IO_NODSP_18_READ;
        else if (ph_addr[15:0] == IO_EVT_PORT)
            io_rd = {8'b0, evt_r};
        else if (ph_addr[15:0] == IO_OVL_PORT)
            io_rd = 16'h0000;
        else if (ph_addr[15:0] == IO_PORT10)
            io_rd = {8'b0, port_in_10};
        else if (ph_addr[15:0] == IO_PORT12)
            io_rd = {8'b0, port_in_12};
        else if (ph_addr[15:0] == IO_PORT14) begin
            io_rd = {8'b0, port_in_14} | IO_PORT14_RING_BIT;
            io_rd = (io_rd & ~IO_PORT14_HWID_BIT) | (hw_id_bit_c ? IO_PORT14_HWID_BIT : 16'h0000);
            if (ring_on && ring_phase_c)
        io_rd = io_rd & ~IO_PORT14_RING_BIT;
        end
        /* DSP running: the glue answers the mailbox / flag / event / overlay / data ports (machine.c machine_iord with m->dsp) */
        if (dsp_run_i && (ph_addr[15:0] == 16'h0018 || ph_addr[15:0] == 16'h001A || ph_addr[15:0] == IO_EVT_PORT || ph_addr[15:0] == IO_OVL_PORT ||
                          (ph_addr[15:0] >= 16'h0040 && ph_addr[15:0] <= 16'h005E && !ph_addr[0]) ||
                          ph_addr[15:0] == 16'h0060 || ph_addr[15:0] == 16'h0062))
            io_rd = {8'h00, glue_rd_data_i};
        /*
        Byte reads return the low byte (C: setreg takes v & 0xFF,
        except the PCB path which byte-selects above).
        */
        if (!ph_word && ph_route != RT_PCB)
            io_rd = {8'b0, io_rd[7:0]};
        rtl_rdata_c = (ph_route == RT_PCB) ? preg_rd : io_rd;
    end

    /*
    Byte-merged PCB write value (C: iowr/mmwr read-modify-write
    with preg(rd=0) for byte writes).
    */
    logic [15:0] pcb_wr_val_c;
    always_comb begin
        if (ph_word) pcb_wr_val_c = ph_wdata;
        else begin
            pcb_wr_val_c = preg_val(ph_addr[7:0]);
            if (ph_addr[0]) pcb_wr_val_c = {ph_wdata[7:0], pcb_wr_val_c[7:0]};
            else pcb_wr_val_c = {pcb_wr_val_c[15:8], ph_wdata[7:0]};
        end
    end

    /* FSM outputs (registered). */
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                fsm_r <= ST_IDLE;
                bus_ack <= 1'b0;
                bus_rdata <= 16'h0000;
                h_req <= 1'b0;
                h_wr <= 1'b0;
                h_word <= 1'b0;
                h_is_mmio <= 1'b0;
                h_addr <= 20'h00000;
                h_wdata <= 16'h0000;
                txn_wr <= 1'b0;
                txn_word <= 1'b0;
                txn_io <= 1'b0;
                txn_addr <= 20'h00000;
                txn_wdata <= 16'h0000;
                txn_split <= 1'b0;
                txn_phase <= 1'b0;
                byte0_r <= 8'h00;
                rdata_r <= 16'h0000;
                cmt_pcb_wr <= 1'b0;
                cmt_pcb_rd_side <= 1'b0;
                cmt_pcb_reg <= 8'h00;
                cmt_pcb_val <= 16'h0000;
                cmt_io_wr <= 1'b0;
                cmt_io_rd <= 1'b0;
                cmt_io_rd_port <= 16'h0000;
                cmt_io_port <= 16'h0000;
                cmt_io_val <= 16'h0000;
                cmt_io_is_word <= 1'b0;
            end else begin
                /* Default: single-cycle pulses off. */
                bus_ack <= 1'b0;
                cmt_pcb_wr <= 1'b0;
                cmt_pcb_rd_side <= 1'b0;
                cmt_io_wr <= 1'b0;
                cmt_io_rd <= 1'b0;
                case (fsm_r)
                    ST_IDLE: begin
                        if (bus_req) begin
                            txn_wr <= bus_wr;
                            txn_word <= bus_word;
                            txn_io <= bus_io;
                            txn_addr <= bus_addr;
                            txn_wdata <= bus_wdata;
                            txn_phase <= 1'b0;
                            txn_split <= idle_split;
                            if (idle_route == RT_RAM || idle_route == RT_MMIO) begin
                                /*
                                Harness-routed first phase: assert h_req
                                in the same cycle as the latch, skipping
                                ST_EXEC (one clock saved per transaction).
                                The harness answers with h_ack; ST_HWAIT
                                collects the data using ph_* (valid from
                                txn_*, latched above).
                                */
                                h_req <= 1'b1;
                                h_wr <= bus_wr;
                                h_word <= idle_h_word;
                                h_is_mmio <= (idle_route == RT_MMIO);
                                h_addr <= bus_addr;
                                h_wdata <= idle_h_wdata;
                                fsm_r <= ST_HWAIT;
                            end else begin
                                fsm_r <= ST_EXEC;
                            end
                        end
                    end
                    ST_EXEC: begin
                        /* Route the current phase. */
                        if (ph_route == RT_RAM || ph_route == RT_MMIO) begin
                            h_req <= 1'b1;
                            h_wr <= ph_wr;
                            h_word <= ph_word;
                            h_is_mmio <= (ph_route == RT_MMIO);
                            h_addr <= ph_addr;
                            h_wdata <= ph_wdata;
                            fsm_r <= ST_HWAIT;
                        end else begin
                            /* RTL-routed phase completes now. */
                            if (!ph_wr) begin
                                if (txn_split) begin
                                    if (!txn_phase) byte0_r <= rtl_rdata_c[7:0];
                                    else rdata_r <= {rtl_rdata_c[7:0], byte0_r};
                                end else begin
                                    rdata_r <= rtl_rdata_c;
                                end
                                if (ph_route == RT_PCB) cmt_pcb_rd_side <= 1'b1;
                                if (ph_route == RT_IO) begin
                                    cmt_io_rd <= 1'b1;
                                    cmt_io_rd_port <= ph_addr[15:0];
                                end
                                cmt_pcb_reg <= ph_addr[7:0];
                            end else begin
                                if (ph_route == RT_PCB) begin
                                    cmt_pcb_wr <= 1'b1;
                                    cmt_pcb_reg <= ph_addr[7:0];
                                    cmt_pcb_val <= pcb_wr_val_c;
                                end else if (ph_route == RT_IO) begin
                                    cmt_io_wr <= 1'b1;
                                    cmt_io_port <= ph_addr[15:0];
                                    cmt_io_val <= ph_wdata;
                                    cmt_io_is_word <= ph_word;
                                end
                                /* RT_RODROP: nothing to commit. */
                            end
                            if (txn_split && !txn_phase) begin
                                txn_phase <= 1'b1;
                                fsm_r <= ST_EXEC;
                            end else begin
                                fsm_r <= ST_ACK;
                            end
                        end
                    end
                    ST_HWAIT: begin
                        if (h_ack) begin
                            h_req <= 1'b0;
                            if (!ph_wr) begin
                                if (txn_split) begin
                                    if (!txn_phase) byte0_r <= h_rdata[7:0];
                                    else rdata_r <= {h_rdata[7:0], byte0_r};
                                end else begin
                                    rdata_r <= ph_word ? h_rdata : {8'b0, h_rdata[7:0]};
                                end
                            end
                            if (txn_split && !txn_phase) begin
                                txn_phase <= 1'b1;
                                fsm_r <= ST_EXEC;
                            end else begin
                                fsm_r <= ST_ACK;
                            end
                        end
                    end
                    ST_ACK: begin
                        bus_ack <= 1'b1;
                        bus_rdata <= rdata_r;
                        fsm_r <= ST_TURNAROUND;
                    end
                    ST_TURNAROUND: begin
                        /* One cycle: the core samples bus_ack and moves
                           on (possibly re-asserting bus_req at once).
                           Unconditional -- do not wait for bus_req low. */
                        fsm_r <= ST_IDLE;
                    end
                    default: fsm_r <= ST_IDLE;
                endcase
            end
        
        end
    end

    /*
    ------------------------------------------------------------------
    Cross-block event pulses (registered, consumed the next cycle).
    ------------------------------------------------------------------
    */
    logic        tmr_hit_pulse [0:TIMER_COUNT-1];
    logic        tmr_hit_inten [0:TIMER_COUNT-1];
    logic        uart_tx_done_pulse; /* UART0 TX complete -> S_S0TX */
    logic        uart_rx_pulse; /* UART0 byte received -> S_S0RX */
    logic        line_rise_pulse; /* DTE TXD rising edge -> S_INT1 */
    logic        io_txd_pulse;
    logic [7:0]  io_txd_byte;
    logic        uart_txd_pulse;
    logic [7:0]  uart_txd_byte;

    function automatic [3:0] vec_to_src(input [7:0] vec);
        case (vec)
            8'h08: vec_to_src = 4'd0;
            8'h12: vec_to_src = 4'd1;
            8'h13: vec_to_src = 4'd2;
            8'h14: vec_to_src = 4'd3;
            8'h15: vec_to_src = 4'd4;
            8'h11: vec_to_src = 4'd5;
            8'h0C: vec_to_src = 4'd6;
            8'h0D: vec_to_src = 4'd7;
            8'h0E: vec_to_src = 4'd8;
            8'h0F: vec_to_src = 4'd9;
            default: vec_to_src = 4'd15;
        endcase
    endfunction
    /*
    IMASK-bit index (0..6) for a source: 0x01->0, 0x04->1, 0x08->2,
    0x10->3, 0x20->4, 0x40->5, 0x80->6.
    */
    function automatic [2:0] bit_idx(input [7:0] msk_bit);
        case (msk_bit)
            8'h01: bit_idx = 3'd0;
            8'h04: bit_idx = 3'd1;
            8'h08: bit_idx = 3'd2;
            8'h10: bit_idx = 3'd3;
            8'h20: bit_idx = 3'd4;
            8'h40: bit_idx = 3'd5;
            8'h80: bit_idx = 3'd6;
            default: bit_idx = 3'd0;
        endcase
    endfunction

    /*
    ------------------------------------------------------------------
    Timers: 1 count per 4 enabled (model-time) clocks (C:
    timer_update advances by (now-last)/4). The divider advances
    only when tick_en_i is high, so the timers stay in lockstep
    with the C model despite the core's bus-latency overhead.
    A register write is latched at the bus commit and applied at
    the next retire_i pulse (instruction boundary): C sets
    last=now at the end of the write instruction, so the divider
    restarts at 1 on the retire clock (1 enabled clock past the
    boundary). The divider is NOT reset at the commit: the C
    model advances the timer to the end of the write instruction
    before applying it, and the RTL does the same (the commit
    clock is an enabled clock that advances the divider).
    ------------------------------------------------------------------
    */
    logic run_c [0:TIMER_COUNT-1];
    always_comb begin
        for (int i = 0; i < TIMER_COUNT; i++)
            run_c[i] = tmr_con[i][15] && (i != 1 || !line_r);
    end
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                for (int i = 0; i < TIMER_COUNT; i++) begin
                    tmr_cnt[i] <= 16'h0000;
                    tmr_cmpa[i] <= 16'h0000;
                    tmr_cmpb[i] <= 16'h0000;
                    tmr_con[i] <= 16'h0000;
                    tmr_div[i] <= 2'd0;
                    tmr_hit_pulse[i] <= 1'b0;
                    tmr_hit_inten[i] <= 1'b0;
                    tmr_pend_vld[i] <= 1'b0;
                    tmr_pend_sel[i] <= 3'd0;
                    tmr_pend_val[i] <= 16'h0000;
                end
            end else begin
                for (int i = 0; i < TIMER_COUNT; i++) begin
                    tmr_hit_pulse[i] <= 1'b0;
                    if (retire_i && tmr_pend_vld[i]) begin
                        /*
                        Deferred timer write applies at the instruction
                        boundary. The retire clock is 1 enabled clock
                        past the boundary, so the divider restarts at 1
                        (tick_en_i is high on the retire clock in the
                        co-sim harness and in the unit TB; if it were
                        low the divider restarts at 0 and the next
                        enabled clock makes it 1 -- the same phase).
                        A stopped timer forces the divider back to 0
                        on the next clock, so the 1 here is harmless
                        for a write that stops the timer.
                        */
                        case (tmr_pend_sel[i])
                            3'd0: tmr_cnt[i] <= tmr_pend_val[i];
                            3'd2: tmr_cmpa[i] <= tmr_pend_val[i];
                            3'd4: tmr_cmpb[i] <= tmr_pend_val[i];
                            default: begin
                                /* EN (bit15) updates only if bit14 set. */
                                if ((tmr_pend_val[i] & TMR_CON_EN_GATE) != 16'h0000)
                                    tmr_con[i] <= (tmr_pend_val[i] & TMR_CON_LOW_MASK) | {tmr_pend_val[i][15], 15'b0};
                                else
                                    tmr_con[i] <= (tmr_pend_val[i] & TMR_CON_LOW_MASK) | {tmr_con[i][15], 15'b0};
                            end
                        endcase
                        tmr_div[i] <= tick_en_i ? 2'd1 : 2'd0;
                        tmr_pend_vld[i] <= 1'b0;
                    end else if (!run_c[i]) begin
                        tmr_div[i] <= 2'd0;
                    end else if (tick_en_i) begin
                        if (tmr_div[i] == 2'd3) begin
                            tmr_div[i] <= 2'd0;
                            /*
                            One timer tick. Hit when cnt reaches lim-1, where
                            lim = cmpa ? cmpa : 0x10000 (C timer_sched).
                            */
                            if (tmr_cnt[i] == (tmr_cmpa[i] == 16'h0000 ? TMR_LIM_DEFAULT : tmr_cmpa[i] - 16'd1)) begin
                                tmr_cnt[i] <= 16'h0000;
                                tmr_hit_pulse[i] <= 1'b1;
                                tmr_hit_inten[i] <= (tmr_con[i] & TMR_CON_INTEN) != 16'h0000;
                                /* MC set; one-shot (CONT==0) clears EN. */
                                if (!tmr_con[i][0])
                                    tmr_con[i] <= (tmr_con[i] | TMR_CON_MC) & ~TMR_CON_EN;
                                else
                                    tmr_con[i] <= tmr_con[i] | TMR_CON_MC;
                            end else begin
                                tmr_cnt[i] <= tmr_cnt[i] + 16'd1;
                            end
                        end else begin
                            tmr_div[i] <= tmr_div[i] + 2'd1;
                        end
                    end
                    /*
                    pwr commit for this timer's registers: latch the
                    write; it applies at the next retire_i pulse (see
                    above). The divider is NOT reset here (the C model
                    advances the timer to the end of the write
                    instruction before applying the write).
                    */
                    if (cmt_pcb_wr && cmt_pcb_reg >= PCB_TIMER_BASE && cmt_pcb_reg <= PCB_TIMER_END &&
                        (({24'b0, cmt_pcb_reg} - {24'b0, PCB_TIMER_BASE}) >> 3) == i) begin
                        tmr_pend_vld[i] <= 1'b1;
                        tmr_pend_sel[i] <= cmt_pcb_reg[2:0] & 3'd6;
                        tmr_pend_val[i] <= cmt_pcb_val;
                    end
                end
            end
        
        end
    end

    /*
    ------------------------------------------------------------------
    UARTs. TX completion counts down in enabled (model-time)
    clocks (C: tx_t = now + 10*pu). A TDR write is latched at the
    bus commit and applied at the next retire_i pulse (instruction
    boundary): C sets tx_t = now + 10*pu at the end of the write
    instruction, so the countdown starts at 10*pu - 1 on the retire
    clock (1 enabled clock past the boundary), or at tx_left +
    10*pu when a byte is already queued (the retire clock does not
    consume one of the queued byte's clocks).
    ------------------------------------------------------------------
    */
    logic [21:0] pu_c [0:UART_COUNT-1];
    always_comb begin
        for (int j = 0; j < UART_COUNT; j++)
            pu_c[j] = 22'd8 * ({6'b0, (uart_cmp[j] & UART_CMP_MASK)} + 22'd1);
    end
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                for (int j = 0; j < UART_COUNT; j++) begin
                    uart_cmp[j] <= 16'h0000;
                    uart_con[j] <= 16'h0000;
                    uart_sts[j] <= UART_STS_TXE; /* machine_new: sts = 0x08 */
                    uart_rbuf[j] <= 16'h0000;
                    uart_tx_left[j] <= 22'd0;
                    uart_rx_pend[j] <= 1'b0;
                    uart_pend_tdr[j] <= 1'b0;
                    uart_pend_byte[j] <= 8'h00;
                end
                uart_tx_done_pulse <= 1'b0;
                uart_rx_pulse <= 1'b0;
                uart_txd_pulse <= 1'b0;
                uart_txd_byte <= 8'h00;
            end else begin
                uart_tx_done_pulse <= 1'b0;
                uart_rx_pulse <= 1'b0;
                uart_txd_pulse <= 1'b0;
                for (int j = 0; j < UART_COUNT; j++) begin
                    if (retire_i && uart_pend_tdr[j]) begin
                        /*
                        Deferred TDR write applies at the instruction
                        boundary. The byte is pushed to the DTE now
                        (C: dte_out push at the write), TXE clears, and
                        the TX countdown starts. The retire clock is 1
                        enabled clock past the boundary, so an idle
                        transmitter counts 10*pu - 1 more clocks; a
                        queued byte completes 10*pu after the queued
                        byte's completion (the retire clock does not
                        consume one of the queued byte's clocks, so
                        the queued form keeps the full tx_left).
                        */
                        uart_txd_pulse <= 1'b1;
                        uart_txd_byte <= uart_pend_byte[j];
                        uart_sts[j] <= uart_sts[j] & ~UART_STS_TXE;
                        if (uart_tx_left[j] == 22'd0)
                            uart_tx_left[j] <= {18'b0, UART_TX_BITS} * pu_c[j] - 22'd1;
                        else
                            uart_tx_left[j] <= uart_tx_left[j] + {18'b0, UART_TX_BITS} * pu_c[j];
                        uart_pend_tdr[j] <= 1'b0;
                    end else if (tick_en_i && uart_tx_left[j] != 22'd0) begin
                        /* TX completion countdown (model time). */
                        if (uart_tx_left[j] == 22'd1) begin
                            uart_tx_left[j] <= 22'd0;
                            uart_sts[j] <= uart_sts[j] | UART_STS_TX_DONE; /* TXE, TI */
                            if (j == 0) uart_tx_done_pulse <= 1'b1;
                        end else begin
                            uart_tx_left[j] <= uart_tx_left[j] - 22'd1;
                        end
                    end
                    /*
                    DTE RX byte injection (UART0 only; UART1 has no
                    harness RX source in lite mode).
                    */
                    if (j == 0 && dte_rx_valid) begin
                        /* machine.c uart_rx: the byte always lands in RBUF and S_S0RX is raised; RI was already set -> OE as well (the old byte is overwritten,
                           the request is not dropped: the firmware's RX handler reads only RBUF, RI stays set until S0STS is read) */
                        uart_rbuf[0] <= {8'b0, dte_rx_byte};
                        uart_rx_pend[0] <= 1'b1;
                        uart_sts[0] <= uart_sts[0] | UART_STS_RI | (uart_sts[0][6] ? UART_STS_OE : 16'h0000);
                        uart_rx_pulse <= 1'b1;
                    end
                    /*
                    Read side effect: reading SxSTS clears RB8, RI, TI,
                    FE, OE (machine.c preg, k==6, rd=1).
                    */
                    if (cmt_pcb_rd_side && cmt_pcb_reg >= PCB_UART_BASE && cmt_pcb_reg <= PCB_UART_END &&
                        (({24'b0, cmt_pcb_reg} >> 4) - {28'b0, PCB_UART_BASE[7:4]}) == j && (cmt_pcb_reg & 8'h0E) == 6)
                        uart_sts[j] <= uart_sts[j] & ~UART_STS_RD_CLEAR;
                    /* Read side effect: reading RBUF marks the byte consumed. */
                    if (cmt_pcb_rd_side && cmt_pcb_reg >= PCB_UART_BASE && cmt_pcb_reg <= PCB_UART_END &&
                        (({24'b0, cmt_pcb_reg} >> 4) - {28'b0, PCB_UART_BASE[7:4]}) == j && (cmt_pcb_reg & 8'h0E) == 8)
                        if (uart_rx_pend[j]) uart_rx_pend[j] <= 1'b0;
                    /* pwr commits for this UART's registers. */
                    if (cmt_pcb_wr && cmt_pcb_reg >= PCB_UART_BASE && cmt_pcb_reg <= PCB_UART_END &&
                        (({24'b0, cmt_pcb_reg} >> 4) - {28'b0, PCB_UART_BASE[7:4]}) == j) begin
                        case (cmt_pcb_reg & 8'h0E)
                            0: uart_cmp[j] <= cmt_pcb_val;
                            4: uart_con[j] <= cmt_pcb_val;
                            10: begin /* TDR: transmit (C: dte_out push, */
                                /* TXE low, tx_t = now + 10*pu or queued).
                                   Latched here; applied at the next
                                   retire_i pulse (see above). */
                                uart_pend_tdr[j] <= 1'b1;
                                uart_pend_byte[j] <= cmt_pcb_val[7:0];
                            end
                            default: begin end
                        endcase
                    end
                end
            end
        
        end
    end

    /*
    ------------------------------------------------------------------
    ICU state: req bits, mask, priority mask, icon levels, in-service.
    ------------------------------------------------------------------
    */
    /*
    Timer hit this cycle (combinational): the divider is about to
    wrap and the count is at the limit, so the timer block will hit
    at this edge. The ICU samples this directly, not the registered
    hit pulse, so the request reaches the core one edge sooner.
    That edge matters: the core's finish decision and the IRQ latch
    race on the same edge when a timer fires on the finishing
    instruction's last cycle (the finish reads the pre-edge
    irq_pending), and the extra edge of latency through the hit
    pulse makes the core miss the interrupt and execute one more
    instruction first. The retire guard matters: a deferred timer
    write applied at this edge preempts the tick, so there is no
    hit to report. (The registered hit-pulse path below stays as a
    redundant backup; it sets the same bits one edge later.)
    */
    logic tmr_hit_now [0:TIMER_COUNT-1];
    always_comb begin
        for (int i = 0; i < TIMER_COUNT; i++)
            tmr_hit_now[i] = run_c[i] && tick_en_i && (tmr_div[i] == 2'd3) &&
                (tmr_cnt[i] == (tmr_cmpa[i] == 16'h0000 ? TMR_LIM_DEFAULT : tmr_cmpa[i] - 16'd1)) &&
                !(retire_i && tmr_pend_vld[i]);
    end
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                req_r <= 10'b0;
                msk_r <= 8'hFD; /* machine_new: msk = 0xFD */
                primsk_r <= 3'd7;
                icon_12 <= 3'd7;
                icon_14 <= 3'd7;
                icon_16 <= 3'd7;
                icon_18 <= 3'd7;
                icon_1a <= 3'd7;
                icon_1c <= 3'd7;
                icon_1e <= 3'd7;
                isv_present_r <= 7'b0;
                for (int level_index = 0; level_index < ICU_LEVELS; level_index++) isv_val_r[level_index[2:0]] <= 3'd0;
            end else begin
                /*
                Request sets (timer hits, UART events, line edge).
                T0 hits also set S_INT3 unconditionally (machine.c).
                */
                for (int i = 0; i < TIMER_COUNT; i++) begin
                    if (tmr_hit_pulse[i]) begin
                        if (tmr_hit_inten[i]) req_r[i] <= 1'b1;
                        if (i == 0) req_r[S_INT3] <= 1'b1;
                    end
                    /* Same-cycle hit (see tmr_hit_now above): set the
                       request at the tick edge, one edge before the
                       registered hit pulse would. INTEN is read from
                       the current CON, not the registered hit inten. */
                    if (tmr_hit_now[i]) begin
                        if ((tmr_con[i] & TMR_CON_INTEN) != 16'h0000) req_r[i] <= 1'b1;
                        if (i == 0) req_r[S_INT3] <= 1'b1;
                    end
                end
                if (uart_tx_done_pulse) req_r[S_S0TX] <= 1'b1;
                if (uart_rx_pulse) req_r[S_S0RX] <= 1'b1;
                if (line_rise_pulse) req_r[S_INT1] <= 1'b1;
                if (int0_set_i) req_r[S_INT0] <= 1'b1;
                /*
                Interrupt taken: move the offered source to in-service
                (machine.c machine_sync_ack, via the core's irq_ack).
                The source moved is irq_ack_vec (the vector the core
                took, latched by the top), not the currently offered
                irq_vec: the offered vector can change mid-entry if a
                higher-priority request arrives, and moving the
                current best would move the wrong source.
                */
                if (irq_ack && icu_best_v) begin
                    if (vec_to_src(irq_ack_vec) != 4'd15) begin
                        req_r[vec_to_src(irq_ack_vec)] <= 1'b0;
                        isv_present_r[bit_idx(src_bit(vec_to_src(irq_ack_vec)))] <= 1'b1;
                        isv_val_r[bit_idx(src_bit(vec_to_src(irq_ack_vec)))] <=
                            icon_of(src_con(vec_to_src(irq_ack_vec)));
                    end
                end
                /* EOI + icon/mask/primsk writes (machine.c pwr). */
                if (cmt_pcb_wr) begin
                    if (cmt_pcb_reg == PCB_EOI_REG) begin
                        /* lite_eoi (sync_ack part is the irq_ack move above). */
                        if (cmt_pcb_val[15]) begin
                            logic [2:0] lo;
                            logic found;
                            lo = 3'd7;
                            found = 1'b0;
                            for (int level_index = 0; level_index < ICU_LEVELS; level_index++)
                                if (isv_present_r[level_index[2:0]] && (!found || isv_val_r[level_index[2:0]] < lo)) begin
                                    lo = isv_val_r[level_index[2:0]];
                                    found = 1'b1;
                                end
                            if (found) begin
                                /*
                                First in-service bit (order 01,04,08,10,
                                20,40,80) with the lowest level.
                                */
                                if (isv_present_r[3'd0] && isv_val_r[3'd0] == lo) isv_present_r[3'd0] <= 1'b0;
                                else if (isv_present_r[3'd1] && isv_val_r[3'd1] == lo) isv_present_r[3'd1] <= 1'b0;
                                else if (isv_present_r[3'd2] && isv_val_r[3'd2] == lo) isv_present_r[3'd2] <= 1'b0;
                                else if (isv_present_r[3'd3] && isv_val_r[3'd3] == lo) isv_present_r[3'd3] <= 1'b0;
                                else if (isv_present_r[3'd4] && isv_val_r[3'd4] == lo) isv_present_r[3'd4] <= 1'b0;
                                else if (isv_present_r[3'd5] && isv_val_r[3'd5] == lo) isv_present_r[3'd5] <= 1'b0;
                                else if (isv_present_r[3'd6] && isv_val_r[3'd6] == lo) isv_present_r[3'd6] <= 1'b0;
                            end
                        end else begin
                            if (eoi_bit(cmt_pcb_val[7:0]) != 8'h00)
                                isv_present_r[bit_idx(eoi_bit(cmt_pcb_val[7:0]))] <= 1'b0;
                        end
                    end else if (con_bit(cmt_pcb_reg) != 8'h00) begin
                        case (cmt_pcb_reg)
                            8'h12: icon_12 <= cmt_pcb_val[2:0];
                            8'h14: icon_14 <= cmt_pcb_val[2:0];
                            8'h16: icon_16 <= cmt_pcb_val[2:0];
                            8'h18: icon_18 <= cmt_pcb_val[2:0];
                            8'h1A: icon_1a <= cmt_pcb_val[2:0];
                            8'h1C: icon_1c <= cmt_pcb_val[2:0];
                            8'h1E: icon_1e <= cmt_pcb_val[2:0];
                            default: begin end
                        endcase
                        /*
                        icon store in C is v & 0x77 (level + mask bit);
                        the mask bit lives in msk_r, the level in icon.
                        */
                        if (cmt_pcb_val[3]) msk_r <= msk_r | con_bit(cmt_pcb_reg);
                        else msk_r <= msk_r & ~con_bit(cmt_pcb_reg);
                    end else if (cmt_pcb_reg == PCB_IMASK_REG) begin
                        msk_r <= cmt_pcb_val[7:0] & 8'hFD;
                    end else if (cmt_pcb_reg == PCB_PRIMSK_REG) begin
                        primsk_r <= cmt_pcb_val[2:0];
                    end
                end
            end
        
        end
    end

    /*
    ------------------------------------------------------------------
    IO commit: generic low-port store + ASIC/mailbox/DTE specials
    (machine.c machine_iowr, DSP absent).
    ------------------------------------------------------------------
    */
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                evt_r <= 8'h00;
                dsp_start_req <= 1'b0;
                burst_valid <= 1'b0;
                burst_data <= 64'h0000_0000_0000_0000;
                io_txd_pulse <= 1'b0;
                io_txd_byte <= 8'h00;
                for (int i = 0; i < 8; i++) h2d_w[i] <= 16'h0000;
                for (int i = 0; i < BURST_TMP_BYTES; i++) burst_tmp[i] <= 8'h00;
            end else begin
                dsp_start_req <= 1'b0;
                burst_valid <= 1'b0;
                io_txd_pulse <= 1'b0;
                if (cmt_io_wr) begin
                    /*
                    Generic store (ports 0x00..0x7F only; 0x80..0xFEFF
                    are stubs -- see docs/i186_cosim.md).
                    */
                    if (cmt_io_port < 16'h0080) begin
                        ports_w[cmt_io_port[6:0]] <= cmt_io_is_word ? cmt_io_val :
                            {8'b0, cmt_io_val[7:0]};
                        if (cmt_io_port[6:0] == 7'h00) ports_sh_00 <= cmt_io_is_word ? cmt_io_val : {8'b0, cmt_io_val[7:0]};
                        if (cmt_io_port[6:0] == IO_HWID_A_PORT[6:0]) ports_sh_12 <= cmt_io_is_word ? cmt_io_val : {8'b0, cmt_io_val[7:0]};
                        if (cmt_io_port[6:0] == IO_HWID_B_PORT[6:0]) ports_sh_14 <= cmt_io_is_word ? cmt_io_val : {8'b0, cmt_io_val[7:0]};
                        ports_set[cmt_io_port[6:0]] <= 1'b1;
                    end
                    if (cmt_io_port == IO_DTE_PORT) begin
                        io_txd_pulse <= 1'b1;
                        io_txd_byte <= cmt_io_val[7:0];
                    end
                    if (cmt_io_port == IO_DSP_START_PORT && cmt_io_val[7:0] == IO_DSP_START_CMD)
                        dsp_start_req <= 1'b1; /* no DSP in lite mode: counted */
                    if (cmt_io_port == IO_EVT_PORT)
                        evt_r <= evt_r & ~cmt_io_val[7:0];
                    if (cmt_io_port >= MBOX_BASE && cmt_io_port <= MBOX_END &&
                        cmt_io_port[0] == 1'b0) begin
                        /* h2d word store (byte merge, C machine_iowr). */
                        if (cmt_io_port[1])
                            h2d_w[cmt_io_port[4:2]] <= {cmt_io_val[7:0], h2d_w[cmt_io_port[4:2]][7:0]};
                        else
                            h2d_w[cmt_io_port[4:2]] <= {h2d_w[cmt_io_port[4:2]][15:8], cmt_io_val[7:0]};
                        /*
                        Overlay-burst capture (DSP absent: bursts are
                        recorded for the harness, as in machine.c).
                        */
                        burst_tmp[cmt_io_port[4:0]] <= cmt_io_val[7:0];
                        if (cmt_io_port == MBOX_BURST0_END) begin
                            burst_valid <= 1'b1;
                            burst_data <= {cmt_io_val[7:0], burst_tmp[12], burst_tmp[10],
                                           burst_tmp[8], burst_tmp[6], burst_tmp[4],
                                           burst_tmp[2], burst_tmp[0]};
                        end else if (cmt_io_port == MBOX_BURST1_END) begin
                            burst_valid <= 1'b1;
                            burst_data <= {cmt_io_val[7:0], burst_tmp[28], burst_tmp[26],
                                           burst_tmp[24], burst_tmp[22], burst_tmp[20],
                                           burst_tmp[18], burst_tmp[16]};
                        end
                    end
                end
            end
        
        end
    end

    /*
    ------------------------------------------------------------------
    PCB commit: register store + RELREG.
    ------------------------------------------------------------------
    */
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                pcb_mem <= 1'b0;
            end else begin
                if (cmt_pcb_wr) begin
                    pcb_w[cmt_pcb_reg[7:1]] <= cmt_pcb_val;
                    if (cmt_pcb_reg[7:1] == PCB_P1LTCH_REG[7:1]) pcb_sh_56 <= cmt_pcb_val;
                    if (cmt_pcb_reg[7:1] == PCB_EE_CS_REG[7:1]) pcb_sh_58 <= cmt_pcb_val;
                    if (cmt_pcb_reg[7:1] == PCB_EE_DATA_REG[7:1]) pcb_sh_5e <= cmt_pcb_val;
                    if (cmt_pcb_reg[7:1] == PCB_RELREG[7:1]) pcb_sh_a8 <= cmt_pcb_val;
                    if (cmt_pcb_reg == PCB_RELREG)
                        pcb_mem <= (cmt_pcb_val & PCB_RELREG_MEM_BIT) != 16'h0000;
                end
            end
        
        end
    end

    /*
    ------------------------------------------------------------------
    EEPROM (machine.c eeprom_clock): clocked by P1LTCH writes
    (reg 0x56, CS bit5 + clock bit2); DO read via preg(0x5A).
    ------------------------------------------------------------------
    */
    always_ff @(posedge clk) begin
        if (ce_i) begin
            ee_we_q <= 1'b0;
            ee_ea_req_q <= 1'b0;
            if (ee_load_en) begin
                ee_we_q <= 1'b1; ee_wa_q <= ee_load_addr; ee_wd_q <= ee_load_data;
            end else if (!rst_n) begin
                ee_ewen <= 1'b0;
                ee_state <= 2'd0;
                ee_nbits <= 4'd0;
                ee_bits <= 15'h0000;
                ee_do_bit <= 1'b1;
                ee_addr <= 8'h00;
                ee_rdn <= 4'd0;
            end else if (cmt_pcb_wr && cmt_pcb_reg == PCB_P1LTCH_REG) begin
                /* `old` is the pre-write pcb[0x56] value (non-blocking read). */
                logic cs0, cs1, clk0;
                cs0 = pcb_sh_56[5];
                cs1 = cmt_pcb_val[5];
                clk0 = pcb_sh_56[2];
                if (cs1 && !cs0) begin ee_state <= 2'd0;
                ee_do_bit <= 1'b1;
                end
                else if (cs0 && !cs1) begin ee_state <= 2'd0;
                ee_do_bit <= 1'b1;
                end
                if (cs1 && cmt_pcb_val[2] && !clk0) begin
                    /* eeprom_clock with DI = pcb[0x5E] bit7 (pre-write value). */
                    logic di;
                    di = pcb_sh_5e[7];
                    case (ee_state)
                        2'd0: if (di) begin ee_state <= 2'd1;
                        ee_nbits <= 4'd0;
                        end
                        2'd1: begin
                            ee_bits <= {ee_bits[13:0], di};
                            if (ee_nbits == 4'd9) begin
                                logic [9:0] cmd;
                                logic [1:0] op;
                                logic [7:0] a;
                                cmd = {ee_bits[8:0], di};
                                op = cmd[9:8];
                                a = cmd[7:0];
                                if (op == EEPROM_OP_READ) begin
                                    ee_state <= 2'd2;
                                    ee_addr <= a;
                                    ee_rdn <= 4'd0;
                                    ee_do_bit <= 1'b0;
                                end else if (op == EEPROM_OP_WDATA) begin
                                    ee_state <= 2'd3;
                                    ee_addr <= a;
                                    ee_nbits <= 4'd0;
                                end else if (op == EEPROM_OP_ERASE) begin
                                    if (ee_ewen) begin ee_we_q <= 1'b1; ee_wa_q <= a; ee_wd_q <= EEPROM_ERASED; end
                                    ee_state <= 2'd0;
                                end else begin
                                    if (a[7:6] == EEPROM_SUBOP_EWEN) ee_ewen <= 1'b1;
                                    else if (a[7:6] == EEPROM_SUBOP_EWDS) ee_ewen <= 1'b0;
                                    else if (a[7:6] == EEPROM_SUBOP_ERASE_ALL && ee_ewen) begin
                                        ee_ea_req_q <= 1'b1;   /* sweep all words to erased, one per clock (below) */
                                    end
                                    ee_state <= 2'd0;
                                    ee_do_bit <= 1'b1;
                                end
                            end else begin
                                ee_nbits <= ee_nbits + 4'd1;
                            end
                        end
                        2'd2: begin /* READ: shift out w[addr] MSB first */
                            ee_do_bit <= ee_rd_q[~ee_rdn];
                            if (ee_rdn == 4'd15) begin
                                ee_rdn <= 4'd0;
                                ee_addr <= ee_addr + 8'd1;
                            end else begin
                                ee_rdn <= ee_rdn + 4'd1;
                            end
                        end
                        2'd3: begin /* WDATA: 16 bits then write */
                            ee_bits <= {ee_bits[13:0], di};
                            if (ee_nbits == 4'd15) begin
                                if (ee_ewen) begin ee_we_q <= 1'b1; ee_wa_q <= ee_addr; ee_wd_q <= {ee_bits, di}; end
                                ee_state <= 2'd0;
                                ee_do_bit <= 1'b1;
                            end else begin
                                ee_nbits <= ee_nbits + 4'd1;
                            end
                        end
                        default: ee_state <= 2'd0;
                    endcase
                end
            end
        
        end
    end

    /*
    ------------------------------------------------------------------
    Line level + rising-edge detect (machine.c line_edge: rising
    edge of DTE TXD requests S_INT1; T1 runs only while line == 0).
    ------------------------------------------------------------------
    */
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                line_r <= 1'b1;
                line_rise_pulse <= 1'b0;
            end else begin
                line_r <= line;
                line_rise_pulse <= line && !line_r;
            end
        
        end
    end

    /*
    ------------------------------------------------------------------
    DTE TX mux: port 0x0A writes (IO block) and UART TDR writes
    (UART block) share one output.
    ------------------------------------------------------------------
    */
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                dte_tx_valid <= 1'b0;
                dte_tx_byte <= 8'h00;
            end else begin
                dte_tx_valid <= io_txd_pulse | uart_txd_pulse;
                if (io_txd_pulse) dte_tx_byte <= io_txd_byte;
                else if (uart_txd_pulse) dte_tx_byte <= uart_txd_byte;
            end
        
        end
    end

    /* EEPROM storage: the single write port takes the staged write or the erase-all sweep; the read is registered every clock (ee_addr is stable for many 186 cycles
       before the next EEPROM clock samples ee_rd_q) */
    wire        ee_wr_w = ee_ea_q | ee_we_q;
    wire [7:0]  ee_wa_w = ee_ea_q ? ee_sw_q : ee_wa_q;
    wire [15:0] ee_wd_w = ee_ea_q ? EEPROM_ERASED : ee_wd_q;
    always_ff @(posedge clk) begin
        if (ee_wr_w) ee_w[ee_wa_w] <= ee_wd_w;
        ee_rd_q <= ee_w[ee_addr];
    end
    always_ff @(posedge clk) begin
        ee_ea_prev_q <= ee_ea_req_q;
        if (!ee_ea_q) begin
            if (ee_ea_req_q && !ee_ea_prev_q) begin ee_ea_q <= 1'b1; ee_sw_q <= 8'h00; end
        end else begin
            ee_sw_q <= ee_sw_q + 8'd1;
            if (ee_sw_q == 8'hFF) ee_ea_q <= 1'b0;
        end
    end

    /* registered reads of the PCB / port RAMs: the address is issued the clock before ST_EXEC uses the data (bus_addr while idle, the next byte's address during
       a split transaction), gated by ce_i like the FSM so the data holds while the 186 is throttled */
    wire [19:0] rd_a_w = (fsm_r == ST_IDLE) ? bus_addr : (txn_addr + 20'd1);
    always_ff @(posedge clk) if (ce_i) begin
        pcb_q   <= pcb_w[rd_a_w[7:1]];
        ports_q <= ports_w[rd_a_w[6:0]];
    end

    /*
    ------------------------------------------------------------------
    Observation + array power-up values.
    ------------------------------------------------------------------
    */
    assign dbg_icu = {req_r, isv_present_r, msk_r};
    assign speaker_on = ports_set[7'h12] && !ports_sh_12[4];
    assign dbg_evt = evt_r;
    assign glue_rd_port_o   = ph_addr[15:0];
    assign glue_rd_commit_o = cmt_io_rd;
    assign glue_wr_commit_o = cmt_io_wr;
    assign glue_wr_port_o   = cmt_io_port;
    assign glue_wr_data_o   = cmt_io_val[7:0];
    assign dbg_h2d0 = h2d_w[0];
    assign dbg_pcb_relreg = pcb_sh_a8;

    /*
    Arrays power up zero (C: calloc/memset at machine_new). No
    synchronous reset on the arrays: the harness holds rst_n low
    for at least one cycle and the FPGA powers them up zero.
    */
    initial begin
        for (int i = 0; i < 128; i++) begin
            pcb_w[i] = 16'h0000;
            ports_w[i] = 16'h0000;
            ports_set[i] = 1'b0;
        end
        pcb_sh_56 = 16'h0; pcb_sh_58 = 16'h0; pcb_sh_5e = 16'h0; pcb_sh_a8 = 16'h0; ports_sh_00 = 16'h0; ports_sh_12 = 16'h0; ports_sh_14 = 16'h0; pcb_q = 16'h0; ports_q = 16'h0;
        for (int i = 0; i < EEPROM_WORDS; i++) ee_w[i] = EEPROM_ERASED;
        ee_we_q = 1'b0; ee_ea_q = 1'b0; ee_ea_req_q = 1'b0; ee_ea_prev_q = 1'b0; ee_sw_q = 8'h00;
    end

endmodule
`default_nettype wire
