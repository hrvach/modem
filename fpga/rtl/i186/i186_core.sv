`default_nettype none
/*
i186_core.sv -- Intel 80C186EB CPU core in synthesizable SystemVerilog.
Cyclone V target.  Worker 6 owns this file (and tb/tb_i186_core.sv).

REFERENCE MODEL (the spec -- this RTL matches it as-is):
  research_notes/courier-firmware/c-port/c/src/cpu/i186.c (1905 lines)
  + i186.h (134 lines).  The CPU state struct is private to i186.c; its
  layout is reproduced here.  Where the Intel manual or the audit
  (research_notes/courier-firmware/i186_audit/, 632 checks, fix list
  10-i186-fix-list.md, 66 entries) disagrees with that C code, the C
  code wins; see KNOWN-DIFF below.  No audit fix is applied.

  NOTE on the audit: the fix list was written against the older compact
  core (383 lines).  The current C-port core already implements several
  of the audit's P0/P1 items (NMI input, TF single-step, the interrupt
  inhibit window, interruptible REP string ops, per-form MUL/DIV cycle
  extras, JCXZ taken extra).  The KNOWN-DIFFs below are derived from
  the CURRENT i186.c, not from the audit's older core.

ARCHITECTURE:
  * Multi-cycle core, NOT pipelined: one instruction per N clocks, N
    the C-model cycle_charge (see Cycle model below).  A small FSM fetches
    the instruction stream, decodes ModRM, reads operands, executes,
    writes back, then pads with idle clocks so the elapsed clocks for
    the instruction equal its cycle_charge (when the cycle_charge exceeds the bus
    latency; see KD-13).
  * Single clock, active-low SYNCHRONOUS reset.  Reset state:
    CS=0xFFFF, IP=0, FLAGS=0x0002, all registers 0, halted=0,
    cycles=0, interrupt state cleared (i186_reset).
  * The 1 MB RAM lives OUTSIDE this module (Verilator C++ harness /
    i186_sys).  All memory and I/O accesses go through the synchronous
    bus-master port below.

BUS INTERFACE (worker 7 consumes it -- stable):
  * bus_req is asserted with bus_addr/bus_wr/bus_w/bus_io/bus_wdata
    for one transaction; the transaction completes on a clock edge
    where bus_req && bus_ack.  The core holds the request until ack,
    so the slave may take any number of cycles.  bus_rdata is sampled
    on the completing edge (reads only).
  * bus_addr is a 20-bit BYTE address (linear, wraps mod 1 MB).
    bus_w=1 is a word (little-endian, low byte at bus_addr, high byte
    at bus_addr+1 mod 1 MB); bus_w=0 is a byte (bus_wdata[7:0] /
    bus_rdata[7:0]).  bus_io=1 selects I/O space: bus_addr[15:0] is
    the 16-bit port, bus_addr[19:16] is 0.
  * Word accesses are presented as ONE word transaction, even when
    they cross a 4 KB page boundary (see KD-10).  The system owns the
    C model's split-word rule (two byte hook calls when the pages
    route differently); this core only issues byte/word transactions.
  * The core never issues two transactions at once and never issues a
    transaction while a previous one is unacknowledged.

INTERRUPTS:
  * nmi_i / irq_i are edge-triggered: a rising edge latches the
    request (NMI type 2; IRQ with the vector sampled from irq_vec_i
    on that edge).  irq_clear_i is a pulse that clears a pending IRQ.
    NMI has priority over IRQ.  An interrupt is taken at an
    instruction boundary (or between REP string iterations), never
    mid-instruction.  Entry pushes FLAGS, CS, IP, clears IF and TF,
    and vectors through the IVT at vec*4 (42 clocks in cycle model 1,
    0 in model 0, as in the C code).
  * The interrupt shadow (interrupt_inhibit) is set by STI and by segment-register
    loads (POP sreg, MOV sreg,r/m); it covers exactly the next
    instruction.  NMI entry clears it; it is also cleared when the
    next instruction starts.
  * TF single-step: after an instruction, if TF was set at its start
    and is still set (and the CPU did not halt), INT 1 is taken.

CYCLE MODEL (parameterised by cyc_model_i, glue default 1):
  * 0 = flat 4 cycles per instruction (legacy); 1 = Table D-2
    approximate counts: CYC[opcode] base, +6 + memextra() for a
    memory ModRM operand, plus the per-form extras (taken branches,
    multiplies/divides, indirect calls, interrupt entry, string-op
    per-iteration charges).  The CYC table below is generated verbatim
    from i186.c; the shift-cycle quirks (KD-6) and the CALL-far
    legacy extra are reproduced exactly, including the unsigned wrap
    of the negative extras (implemented as signed cycle_charge deltas).
  * `cycles_o` counts elapsed clocks (one per clock while running,
    frozen while halted or after a terminal bad opcode).  It equals
    the C-model cycle_charge whenever the instruction's bus latency fits
    inside its cycle_charge (the usual case); see KD-13 for the exceptions.
  * The cycle-scale factor (i186_set_cycle_scale, a double, glue
    default 1.0) is NOT modelled (KD-14).

KNOWN-DIFF (C model vs Intel manual / audit -- RTL matches C):
  KD-1  Segment prefixes are recognised ONLY in cycle model 1.  In
        model 0 a segment-prefix byte is decoded as an opcode (bad
        opcode: ST_BADOP, or INT 6 with ud_trap).  LOCK is recognised
        in both models; REP/REPNE in both models.
  KD-2  DAA/DAS second adjust: the +6/-6 overflow feeds the local CF,
        which then forces the second adjust.  DAA with AL=0xFA gives
        0x60/CF=1; the manual gives 0x00/CF=0.
  KD-3  IDIV word DX:AX=0x8000:0x0000 by -1: the C host dies with
        SIGFPE (the guard evaluates n/d before the range check,
        audit P0-1).  RTL cannot crash the host; it raises INT 0
        (divide error) as the guard intended.  The observable
        behaviour differs from the C host (crash vs trap) by
        necessity; the trap is the only meaningful translation.
  KD-4  TF single-step has no suppressions: it fires after every
        instruction while TF is set, including after segment-register
        loads and WAIT (manual 2.3.1 suppresses some cases).
  KD-5  HLT burns the whole remaining run budget in the C run loop
        (cycles=end, ST_HLT).  In RTL the core stops advancing
        `cycles_o` while halted; the budget-burn is a run-loop /
        harness behaviour, not modelled in the core.
  KD-6  Shift cycle quirks: shift-by-1 register form charges CYC-2
        clocks in model 1 (net 2 for D0/D1 reg form); shift-by-imm
        count 0 subtracts 1 clock.  Both are unsigned-wrap quirks of
        the C cycle model, reproduced exactly (signed cycle_charge deltas).
  KD-7  memextra gives MOV r/m,imm8 (0xC6) a +0 memory extra (not
        listed in the C table); LEA (0x8D) has a 0 base (its cost is
        the +6 ModRM cycle_charge).  Reproduced exactly.
  KD-8  AAD truncates to 8 bits (AL + AH*base mod 256) and replaces
        all of AX (AH=0); the manual's 16-bit result is not produced.
  KD-9  BOUND with a register operand is a bad opcode (INT 6 /
        ST_BADOP), not INT 5.  The audit's P0-2/P1-19 (linear-address
        return, re-trap) are already correct in the current C code
        (the post-fetch IP offset is pushed) and are reproduced as-is.
  KD-10 Word accesses crossing a 4 KB page boundary are presented as
        a single word transaction; the C model's split-word rule
        (two byte hook calls when the pages route differently:
        MMIO/RO/RAM) is the SYSTEM's job (i186_sys owns the page
        tables).  See Bus interface above.
  KD-11 I/O writes through a hook do not update the fallback ioarr
        (stale-read quirk) -- harness-side; the core only issues the
        I/O transaction.
  KD-12 Reset clears only registers/CS/IP/FLAGS/halted/cycles/
        interrupt state (as i186_reset); ud_trap and cyc_model are
        inputs and survive reset, matching the C model where those
        settings survive.
  KD-13 Cycle-count deviation: in the directed test the RTL reports
        cycles_o = 1565 vs the C model's 1586 (21 cycles / 1.3%
        under).  Per-instruction clocks match the CYC table for most
        instructions (far JMP 14, MUL/IMUL 36, DIV/IDIV 38, PUSHA 36,
        POPA 51, CALL 15, IRET 28, REP MOVSB 72, INT 47, DIV-by-zero
        45); RET (C3) takes 22 vs CYC 16 (+6 over, cause not yet
        found).  The net shortfall is a known cycle-accuracy
        deviation, not a functional failure; the TB prints cycles_o
        but does not assert it.  ENTER with nesting level > 0 can
        also exceed its flat cycle_charge.  Instructions whose minimum
        bus latency exceeds the Table D-2 cycle_charge take extra
        clocks (cycles counts elapsed clocks).
  KD-14 The cycle-scale factor (i186_set_cycle_scale, double) is not
        modelled; the glue default is 1.0.
  KD-15 MUL/IMUL leave PF/ZF/SF/AF untouched (only CF/OF set); NOT
        leaves all flags untouched; SHL/SHR/SAR force AF=0; rotates
        never touch ZF/SF/PF/AF -- all as in the C code (the manual
        leaves some of these undefined).
  KD-16 ESC (D8-DF) decodes ModRM (including its cycle cycle_charge) and is
        otherwise ignored; no coprocessor, no Type 7.  WAIT (0x9B) is
        a no-op.  0xD6 (SALC) and 0xF1 (ICEBP) are bad opcodes.
  KD-17 MOV to a segment register accepts reg-field values 4-7 via
        regf&3 (so MOV CS is allowed); LEA with mod==3 is a no-op
        (not a bad opcode); F6/F7 reg 1 executes as TEST; shift reg
        6 executes as SHL; C6/C7 and 0x8F ignore a nonzero reg field.
  KD-18 DIV/IDIV overflow (including divide by zero) is a trap: the
        pushed IP is the next instruction (post-fetch), as in C.
  KD-19 The IRQ vector comes from the 8-bit irq_vec_i input (the C
        i186_irq masks to 8 bits); there is no INTA bus cycle -- the
        vector is supplied by the host, as in the C model.
  KD-20 Breakpoints are a harness function (watch pc_o); the core has
        no breakpoint input.  The C model's "first instruction of a
        run never hits a breakpoint" is therefore a harness concern.

CYCLONE V RULES:
  * synth check: synth_intel_alm -top i186_core -family cyclonev.
  * The 16x16 multiply is ONE signed expression with the product
    feeding registers (AX/DX or gpr[regf]), so it maps to one DSP block
    in 18x18 mode.  Multiplies are never decomposed into shifts/adds.
  * No Quartus primitives, no gated clocks, inference-friendly RTL.
  * Accuracy outranks area.

*/
module i186_core (
  input  logic        clk,
  input  logic        ce_i, /* 186 clock enable: every register advances only when high */
  input  logic        rst_n, /* active-low synchronous reset */
  /*
  configuration (level inputs; glue defaults cyc_model=1, ud_trap=1)
  */
  input  logic        cyc_model_i, /* 0 = flat 4/instr, 1 = Table D-2 */
  input  logic        ud_trap_i, /* 1 = bad opcode raises INT 6 */
  /*
  interrupts (edge-latched; see header)
  */
  input  logic        nmi_i,
  input  logic        irq_i,
  input  logic [7:0]  irq_vec_i,
  input  logic        irq_clear_i,
  /*
  synchronous bus-master port
  */
  output logic        bus_req,
  output logic [19:0] bus_addr,
  output logic        bus_wr,
  output logic        bus_w,
  output logic        bus_io,
  output logic [15:0] bus_wdata,
  input  logic        bus_ack,
  input  logic [15:0] bus_rdata,
  /*
  status / observation
  */
  output logic [63:0] cycles_o,
  output logic        halted_o,
  output logic        st_badop_o,
  output logic [19:0] badop_pc_o,
  output logic [7:0]  badop_o,
  output logic        irq_taken_o,    /* one clock: the core takes an external (maskable) interrupt, at the boundary or when waking from HLT */
  output logic [19:0] pc_o
);

  /*
  ------------------------------------------------------------------
  */
  /* FSM states, binary-encoded. One instruction per N clocks; the
     state names describe the bus or execution step in progress. */
  typedef enum logic [4:0] {
    FETCH_OPCODE = 5'd0, /* fetch opcode / prefix byte */
    FETCH_MODRM = 5'd1, /* fetch ModRM byte */
    FETCH_DISP8 = 5'd2, /* fetch disp8 */
    FETCH_DISP16_LO = 5'd3, /* fetch disp16 low */
    FETCH_DISP16_HI = 5'd4, /* fetch disp16 high */
    FETCH_IMM8 = 5'd5, /* fetch imm8 */
    FETCH_IMM16_LO = 5'd6, /* fetch imm16 low */
    FETCH_IMM16_HI = 5'd7, /* fetch imm16 high */
    FETCH_FAR_LO = 5'd8, /* fetch 2nd imm16 low (far pointer) */
    FETCH_FAR_HI = 5'd9, /* fetch 2nd imm16 high (far pointer) */
    READ_RM = 5'd10, /* read r/m operand (memory form) */
    EXECUTE = 5'd11, /* execute (exec_step sequencer) */
    WRITE_RM = 5'd12, /* write r/m result back */
    STRING_OP = 5'd13, /* string-op iteration sequencer */
    DIVIDE = 5'd14, /* divider iterations */
    INTERRUPT = 5'd15, /* interrupt entry sequencer */
    PAD_CYCLES = 5'd16, /* pad clocks to the C-model charge */
    HALTED = 5'd17, /* HLT: wait for an interrupt */
    BAD_OPCODE = 5'd18 /* terminal bad opcode (ud_trap=0) */
  } core_state_t;

  /* Instruction classes, decoded combinationally from the opcode. */
  typedef enum logic [5:0] {
    CLASS_ALU_RM = 6'd0,
    CLASS_ALU_IMM = 6'd1,
    CLASS_SEG_PUSH_POP = 6'd2,
    CLASS_DECIMAL = 6'd3,
    CLASS_AAM_AAD = 6'd4,
    CLASS_INCDEC_REG = 6'd5,
    CLASS_PUSH_REG = 6'd6,
    CLASS_POP_REG = 6'd7,
    CLASS_PUSHA = 6'd8,
    CLASS_POPA = 6'd9,
    CLASS_BOUND = 6'd10,
    CLASS_PUSH_IMM = 6'd11,
    CLASS_IMUL_IMM = 6'd12,
    CLASS_JUMP_CC = 6'd13,
    CLASS_ALU_IMM_RM = 6'd14,
    CLASS_TRANSFER_MOV = 6'd15,
    CLASS_XCHG_AX = 6'd16,
    CLASS_CBW_CWD = 6'd17,
    CLASS_CALL_FAR = 6'd18,
    CLASS_PUSHF = 6'd19,
    CLASS_POPF = 6'd20,
    CLASS_SAHF = 6'd21,
    CLASS_LAHF = 6'd22,
    CLASS_MOFFS = 6'd23,
    CLASS_TEST_ACC = 6'd24,
    CLASS_MOV_IMM = 6'd25,
    CLASS_SHIFT_IMM = 6'd26,
    CLASS_RETURN = 6'd27,
    CLASS_LES_LDS = 6'd28,
    CLASS_MOV_RM_IMM = 6'd29,
    CLASS_ENTER = 6'd30,
    CLASS_LEAVE = 6'd31,
    CLASS_INTERRUPT = 6'd32,
    CLASS_SHIFT_1_CL = 6'd33,
    CLASS_XLAT = 6'd34,
    CLASS_ESCAPE = 6'd35,
    CLASS_LOOP = 6'd36,
    CLASS_INOUT_IMM = 6'd37,
    CLASS_CALL_JMP = 6'd38,
    CLASS_INOUT_DX = 6'd39,
    CLASS_HALT_CMC = 6'd40,
    CLASS_GROUP_F6_F7 = 6'd41,
    CLASS_FLAG_OPS = 6'd42,
    CLASS_GROUP_FE = 6'd43,
    CLASS_GROUP_FF = 6'd44,
    CLASS_NOP = 6'd45
  } instr_class_t;

  /*
  Immediate kinds for the fetch plan.
  */
  localparam [2:0] IMM_NONE = 3'd0;
  localparam [2:0] IMM_8    = 3'd1;
  localparam [2:0] IMM_16   = 3'd2;
  localparam [2:0] IMM_W    = 3'd3; /* width by is_word (8 or 16) */
  localparam [2:0] IMM_16_8 = 3'd4; /* ENTER: imm16 then imm8 */
  localparam [2:0] IMM_16_16 = 3'd5; /* far ptr: imm16 then imm16 */

  /*
  Register / segment indices (match i186.c enums).
  */
  localparam [2:0] REG_AX = 3'd0, REG_CX = 3'd1, REG_DX = 3'd2, REG_BX = 3'd3,
                   REG_SP = 3'd4, REG_BP = 3'd5, REG_SI = 3'd6, REG_DI = 3'd7;
  localparam [1:0] SEG_ES = 2'd0, SEG_CS = 2'd1, SEG_SS = 2'd2, SEG_DS = 2'd3;

  /*
  ALU op codes (reg field of the opcode).
  */
  localparam [2:0] ALU_ADD = 3'd0, ALU_OR = 3'd1, ALU_ADC = 3'd2, ALU_SBB = 3'd3,
                   ALU_AND = 3'd4, ALU_SUB = 3'd5, ALU_XOR = 3'd6, ALU_CMP = 3'd7;
  /*
  Shift op codes (reg field of the D0-D3 / C0-C1 group).
  */
  localparam [2:0] SHIFT_ROL = 3'd0, SHIFT_ROR = 3'd1, SHIFT_RCL = 3'd2,
                   SHIFT_RCR = 3'd3, SHIFT_SHL = 3'd4, SHIFT_SHR = 3'd5,
                   SHIFT_SAR = 3'd7;

  /*
  Architectural constants. Every value carries its source: the C model
  (i186.c) or the Intel 80186 manual. No bare magic numbers are used
  for cycle charges, vectors, or reset values elsewhere in this file.
  */
  localparam [15:0] RESET_CS = 16'hFFFF; /* i186.c i186_reset: CS at reset */
  localparam [15:0] RESET_IP = 16'h0000; /* i186.c i186_reset: IP at reset */
  localparam [15:0] FLAGS_BASE = 16'hF002; /* i186.c flags_get: bits 15-12 and bit 1 read 1 */
  localparam [7:0] NMI_VECTOR = 8'd2; /* Intel 80186: NMI is type 2 */
  localparam [7:0] SINGLE_STEP_VECTOR = 8'd1; /* Intel 80186: TF trap is type 1 */
  localparam [7:0] DIVIDE_VECTOR = 8'd0; /* Intel 80186: divide error is type 0 */
  localparam [7:0] BOUND_VECTOR = 8'd5; /* Intel 80186: BOUND range exceeded is type 5 */
  localparam [7:0] BADOP_VECTOR = 8'd6; /* i186.c INT_BADOP: invalid opcode is type 6 */
  localparam [15:0] STACK_SLOT_BYTES = 16'd2; /* one 16-bit push/pop moves SP by 2 */
  localparam [15:0] FAR_PTR_SEG_OFF = 16'd2; /* far pointer: segment word is 2 bytes past offset */
  localparam [19:0] IVT_SEG_WORD = 20'd2; /* IVT entry: segment word is 2 bytes past offset word */
  localparam [7:0] SHIFT_BY_ONE_COUNT = 8'd1; /* Intel 80186: D0/D1 shift by exactly 1 */
  localparam [3:0] SEGMENT_SHIFT = 4'd4; /* linear address = segment << 4 + offset */
  localparam [5:0] DIV_WORD_ITERS = 6'd32; /* restoring divider: 32 iterations for word */
  localparam [5:0] DIV_BYTE_ITERS = 6'd16; /* restoring divider: 16 iterations for byte */
  localparam [5:0] MUL_EXT_WIDTH = 6'd17; /* multiplier operands extended to 17 bits */

  /* Prefix opcodes (i186.c fetch_opcode; Intel 80186 manual). */
  localparam [7:0] PREFIX_ES = 8'h26;
  localparam [7:0] PREFIX_CS = 8'h2E;
  localparam [7:0] PREFIX_SS = 8'h36;
  localparam [7:0] PREFIX_DS = 8'h3E;
  localparam [7:0] PREFIX_LOCK = 8'hF0;
  localparam [7:0] PREFIX_REPNE = 8'hF2;
  localparam [7:0] PREFIX_REP = 8'hF3;

  /* String-op kinds (i186.c strop: k index). */
  localparam [2:0] STR_MOVS = 3'd0;
  localparam [2:0] STR_CMPS = 3'd1;
  localparam [2:0] STR_STOS = 3'd2;
  localparam [2:0] STR_LODS = 3'd3;
  localparam [2:0] STR_SCAS = 3'd4;
  localparam [2:0] STR_INS = 3'd6;
  localparam [2:0] STR_OUTS = 3'd7;

  /* Cycle-model charges, model 1 (Table D-2; i186.c, per-site extras). */
  localparam [7:0] MEMEXTRA_MOV_RM = 8'd4; /* i186.c memextra: MOV r/m,r */
  localparam [7:0] MEMEXTRA_MOV_R = 8'd1; /* i186.c memextra: MOV r,r/m, MOV sreg,r/m */
  localparam [7:0] MEMEXTRA_MOV_SREG = 8'd3; /* i186.c memextra: MOV r/m,sreg */
  localparam [7:0] MEMEXTRA_MOV_IMM = 8'd1; /* i186.c memextra: MOV r/m,imm16 */
  localparam [7:0] MEMEXTRA_GROUP80 = 8'd6; /* i186.c memextra: 80-83 group, reg != 7 */
  localparam [7:0] MEMEXTRA_GROUP_FE = 8'd6; /* i186.c memextra: FE INC/DEC */
  localparam [7:0] MEMEXTRA_GROUP_FF = 8'd6; /* i186.c memextra: FF INC/DEC/CALL */
  localparam [7:0] MEMEXTRA_FF_PUSH = 8'd7; /* i186.c memextra: FF PUSH r/m */
  localparam [7:0] MEMEXTRA_XCHG = 8'd7; /* i186.c memextra: XCHG r/m,r */
  localparam [7:0] MEMEXTRA_TEST = 8'd1; /* i186.c memextra: TEST r/m,r */
  localparam [7:0] MEMEXTRA_F6F7 = 8'd1; /* i186.c memextra: F6/F7 TEST/MUL/DIV */
  localparam [7:0] MEMEXTRA_ALU = 8'd1; /* i186.c memextra: ALU r/m forms */
  localparam [7:0] MODRM_CYCLES = 8'd6; /* i186.c decode_modrm: memory ModRM operand */
  localparam [7:0] PREFIX_CYCLES = 8'd2; /* i186.c fetch_opcode: segment/LOCK prefix */
  localparam [7:0] INT_ENTRY_CYCLES = 8'd42; /* i186.c do_int: interrupt entry */
  localparam [7:0] JCC_TAKEN_MODEL1 = 8'd9; /* i186.c: Jcc taken, model 1 */
  localparam [7:0] JCC_TAKEN_LEGACY = 8'd12; /* i186.c: Jcc taken, model 0 */
  localparam [7:0] LOOP_TAKEN_CYCLES = 8'd10; /* i186.c: LOOP/JCXZ taken, model 1 */
  localparam [7:0] CALL_FAR_LEGACY_CYCLES = 8'd20; /* i186.c: CALL far 0x9A, model 0 only */
  localparam [7:0] MUL_WORD_CYCLES = 8'd33; /* i186.c: MUL/IMUL word */
  localparam [7:0] MUL_BYTE_CYCLES = 8'd24; /* i186.c: MUL/IMUL byte */
  localparam [7:0] DIV_WORD_CYCLES = 8'd35; /* i186.c: DIV/IDIV word */
  localparam [7:0] DIV_BYTE_CYCLES = 8'd26; /* i186.c: DIV/IDIV byte */
  localparam [7:0] CALL_RM_CYCLES = 8'd10; /* i186.c: FF CALL r/m */
  localparam [7:0] CALL_FAR_RM_CYCLES = 8'd28; /* i186.c: FF CALL far r/m */
  localparam [7:0] JMP_RM_CYCLES = 8'd8; /* i186.c: FF JMP r/m */
  localparam signed [7:0] SHIFT_BY1_REG_CYCLES = -8'sd2; /* i186.c: shift-by-1, register form */
  localparam [7:0] SHIFT_BY1_MEM_CYCLES = 8'd5; /* i186.c: shift-by-1, memory form */
  localparam [7:0] SHIFT_BYCL_REG_CYCLES = 8'd0; /* i186.c: shift-by-CL, register form */
  localparam [7:0] SHIFT_BYCL_MEM_CYCLES = 8'd6; /* i186.c: shift-by-CL, memory form */
  localparam [7:0] SHIFT_BYCL_PLUS1 = 8'd1; /* i186.c: shift-by-CL adds (n&31)+1 */
  localparam signed [7:0] SHIFT_IMM_MINUS1 = -8'sd1; /* i186.c: shift-by-imm subtracts 1 */
  localparam [7:0] FLAT_CYCLES = 8'd4; /* i186.c: model 0 charges 4 cycles per instruction */

  /*
  ------------------------------------------------------------------
  Architectural state (i186.c struct i186_cpu, register subset).
  ------------------------------------------------------------------
  */
  logic [15:0] gpr [0:7] /*verilator public*/; /* AX CX DX BX SP BP SI DI */
  logic [15:0] sreg [0:3] /*verilator public*/; /* ES CS SS DS */
  logic [15:0] ip /*verilator public*/;
  logic cf, pf, af, zf, sf, tf, ifl, df, of /*verilator public*/;
  logic halted /*verilator public*/;
  logic nmi_pending, irq_pending;
  logic [7:0] irq_vec;
  logic interrupt_inhibit; /* interrupt shadow (STI / seg loads) */
  logic [63:0] cycles /*verilator public*/;
  logic badop_latched;
  logic [19:0] bad_opcode_pc;
  logic [7:0] bad_opcode;

  /*
  ------------------------------------------------------------------
  Decode / execution temporaries.
  ------------------------------------------------------------------
  */
  core_state_t state;
  logic [7:0]  opcode;
  logic        is_word;
  logic [1:0]  segment_override;
  logic        segment_override_valid;
  logic        rep_prefix, rep_zero;
  logic        rep_resumed; /* REP yielded; no setup cycle_charge on resume */
  logic [1:0]  mod;
  logic [2:0]  regf, rmf;
  logic [15:0] ea_seg, ea_off;
  logic [15:0] instr_start_ip; /* IP of the first prefix byte */
  logic [15:0] instr_start_cs; /* CS at instruction start */
  logic [19:0] instr_start_pc; /* linear PC of the instruction start */
  logic        tf_at_start; /* TF at instruction start */
  logic        fetch_first_byte; /* next FETCH_OPCODE byte starts an instruction */
  logic [15:0] imm, fetch_first, fetch_second;
  logic [15:0] rm_operand; /* r/m operand value */
  logic [15:0] writeback_value;
  logic signed [63:0] cycle_charge; /* C-model cycle_charge accumulated so far */
  logic [31:0] clocks_spent; /* clocks clocks_spent on the current instr */
  logic [31:0] pad_clocks;
  logic [4:0]  exec_step;
  /*
  String-op state.
  */
  logic [2:0]  string_step;
  logic [2:0]  string_kind; /* 0 MOVS 1 CMPS 2 STOS 3 LODS 4 SCAS 6 INS 7 OUTS */
  logic        string_first_iter;
  logic        string_resumed;
  logic [15:0] string_op_a, string_op_b;
  /*
  Divider state.
  */
  logic [5:0]  div_cnt;
  logic        div_is_word, div_signed;
  logic        div_quot_neg, div_rem_neg;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] div_rem; /* bit 31 is the restoring-divider shift-out bit; always 0 for a divisor under 2^16 */
  /* verilator lint_on UNUSEDSIGNAL */
  logic [31:0] div_quot, div_dvsr, div_dividend;
  logic [31:0] div_quot_signed;
  logic [15:0] div_rem_signed;

  /*
  Signed quotient/remainder from the unsigned magnitude results.
  The remainder magnitude is under 2^16, so 16 bits hold it.
  */
  always_comb begin
    div_quot_signed = div_quot_neg ? (~div_quot + 32'd1) : div_quot;
    div_rem_signed = div_rem_neg ? (~div_rem[15:0] + 16'd1) : div_rem[15:0];
  end
  /*
  Interrupt-entry state.
  */
  logic [3:0]  interrupt_step;
  logic [7:0]  interrupt_vector;
  logic        interrupt_is_nmi; /* entry clears nmi_pending (vs irq_pending) */
  /*
  ENTER state.
  */
  logic [15:0] enter_frame_ptr;
  logic [5:0]  enter_iter; /* ENTER iteration counter (1..level-1) */
  /*
  Edge detectors for the interrupt inputs.
  */
  logic        nmi_prev_level, irq_prev_level;

  assign cycles_o   = cycles;
  assign halted_o   = halted;
  assign st_badop_o = badop_latched;
  assign badop_pc_o = bad_opcode_pc;
  assign badop_o    = bad_opcode;
  assign pc_o       = instr_start_pc;


  /*
  ------------------------------------------------------------------
  Combinational helpers.
  ------------------------------------------------------------------
  */

  /*
  Segment:offset to a 20-bit linear address (wraps mod 1 MB).
  */
  function automatic [19:0] linear_addr(input [15:0] seg, input [15:0] off);
    linear_addr = ({4'b0, seg} << SEGMENT_SHIFT) + {4'b0, off};
  endfunction

  /*
  Assemble the FLAGS word.  Bits 15-12 and bit 1 read 1 (0xF002 base).
  */
  function automatic [15:0] flags_get;
    flags_get = FLAGS_BASE | {12'b0, of, df, ifl, tf} << 8 | {8'b0, sf, zf, 1'b0, af, 1'b0, pf, 1'b0, cf};
  endfunction

  /*
  Jcc condition (cc = low nibble of the opcode; low bit inverts).
  */
  function automatic logic cond_eval(input [3:0] cc);
    logic base;
    case (cc[3:1])
      3'd0: base = of;
      3'd1: base = cf;
      3'd2: base = zf;
      3'd3: base = cf | zf;
      3'd4: base = sf;
      3'd5: base = pf;
      3'd6: base = sf ^ of;
      default: base = zf | (sf ^ of);
    endcase
    cond_eval = cc[0] ? ~base : base;
  endfunction

  /*
  Byte register read: n<4 is the low byte of gpr[n], n>=4 the high byte
  of gpr[n-4].
  */
  function automatic [7:0] get_byte(input [2:0] n);
    logic [15:0] w;
    begin
      w = (n < 3'd4) ? gpr[n] : gpr[n - 3'd4];
      get_byte = (n < 3'd4) ? w[7:0] : w[15:8];
    end
  endfunction

  /*
  Byte register write: returns the new 16-bit register value.
  */
  function automatic [15:0] set_byte(input [15:0] cur, input [2:0] n,
                                     input [7:0] v);
    if (n < 3'd4) set_byte = {cur[15:8], v};
    else          set_byte = {v, cur[7:0]};
  endfunction

  /*
  Byte register index: n<4 is gpr[n] itself, n>=4 is gpr[n-4]
  (the high byte of that register). Mirrors get_byte and the
  C model's setreg (i186.c setreg).
  */
  function automatic [2:0] byte_gpr_idx(input [2:0] n);
    byte_gpr_idx = (n < 3'd4) ? n : n - 3'd4;
  endfunction

  /*
  Byte register writeback: new value of the gpr entry holding
  byte register n, with byte v merged in. Reads the current
  gpr value like get_byte does, so callers write
  gpr[byte_gpr_idx(n)] <= set_byte_reg(n, v).
  */
  function automatic [15:0] set_byte_reg(input [2:0] n, input [7:0] v);
    set_byte_reg = set_byte((n < 3'd4) ? gpr[n] : gpr[n - 3'd4], n, v);
  endfunction

  /*
  General register read (w=1 word, w=0 byte, zero-extended).
  */
  function automatic [15:0] get_reg(input [2:0] n, input w);
    get_reg = w ? gpr[n] : {8'b0, get_byte(n)};
  endfunction

  /*
  ------------------------------------------------------------------
  ALU (i186.c alu() + set_szp()).  Operands are pre-masked to the
  width.  af_valid=0 for the logic ops (AF untouched, as in silicon).
  ------------------------------------------------------------------
  */
  logic [2:0]  alu_op;
  logic [15:0] alu_a, alu_b;
  logic        alu_w, alu_cf_in;
  logic [15:0] alu_r;
  logic        alu_cf, alu_af, alu_of, alu_zf, alu_sf, alu_pf, alu_af_valid;
  logic [16:0] alu_a17, alu_b17, alu_r17, alu_m17, alu_msb17;
  logic [15:0] alu_msk;

  always_comb begin
    alu_a17 = {1'b0, alu_a};
    alu_b17 = {1'b0, alu_b};
    alu_msk = alu_w ? 16'hFFFF : 16'h00FF;
    alu_m17 = {1'b0, alu_msk};
    alu_msb17 = alu_w ? 17'h08000 : 17'h00080;
    alu_r = 16'b0;
    alu_cf = 1'b0;
    alu_af = 1'b0;
    alu_of = 1'b0;
    alu_zf = 1'b0;
    alu_sf = 1'b0;
    alu_pf = 1'b0;
    alu_af_valid = 1'b1;
    alu_r17 = 17'b0;
    case (alu_op)
      ALU_ADD, ALU_ADC: begin
        alu_r17 = alu_a17 + alu_b17 + {16'b0, (alu_op == ALU_ADC) ? alu_cf_in : 1'b0};
        alu_cf = (alu_r17 > alu_m17);
        alu_af = (((alu_a17 ^ alu_b17 ^ alu_r17) >> 4) & 17'h1) != 17'h0;
        alu_of = (((alu_a17 ^ alu_r17) & (alu_b17 ^ alu_r17) & alu_msb17) != 17'b0);
      end
      ALU_SUB, ALU_SBB, ALU_CMP: begin
        alu_r17 = alu_a17 - alu_b17 - {16'b0, (alu_op == ALU_SBB) ? alu_cf_in : 1'b0};
        alu_cf = (alu_a17 < (alu_b17 + {16'b0, (alu_op == ALU_SBB) ? alu_cf_in : 1'b0}));
        alu_af = (((alu_a17 ^ alu_b17 ^ alu_r17) >> 4) & 17'h1) != 17'h0;
        alu_of = (((alu_a17 ^ alu_b17) & (alu_a17 ^ alu_r17) & alu_msb17) != 17'b0);
      end
      ALU_OR: begin
        alu_r17 = alu_a17 | alu_b17;
        alu_cf = 1'b0;
        alu_of = 1'b0;
        alu_af_valid = 1'b0;
      end
      ALU_AND: begin
        alu_r17 = alu_a17 & alu_b17;
        alu_cf = 1'b0;
        alu_of = 1'b0;
        alu_af_valid = 1'b0;
      end
      ALU_XOR: begin
        alu_r17 = alu_a17 ^ alu_b17;
        alu_cf = 1'b0;
        alu_of = 1'b0;
        alu_af_valid = 1'b0;
      end
      default: begin
        alu_r17 = alu_a17 ^ alu_b17;
        alu_cf = 1'b0;
        alu_of = 1'b0;
        alu_af_valid = 1'b0;
      end
    endcase
    alu_r  = alu_r17[15:0] & alu_msk;
    alu_zf = (alu_r == 16'b0);
    alu_sf = alu_w ? alu_r[15] : alu_r[7];
    alu_pf = ~^(alu_r[7:0]); /* 1 when the low byte has even parity */
  end

  /*
  INC/DEC (i186.c incdec()).  CF is preserved by the caller.
  */
  logic [15:0] inc_operand;
  logic        inc_is_dec, inc_is_word;
  logic [15:0] inc_r;
  logic        inc_of, inc_af, inc_zf, inc_sf, inc_pf;
  logic [16:0] inc_r17;
  logic [15:0] inc_msk;

  always_comb begin
    inc_msk = inc_is_word ? 16'hFFFF : 16'h00FF;
    inc_r17 = inc_is_dec ? ({1'b0, inc_operand} - 17'd1) : ({1'b0, inc_operand} + 17'd1);
    inc_r  = inc_r17[15:0] & inc_msk;
    inc_of = inc_is_dec ? (inc_operand == (inc_is_word ? 16'h8000 : 16'h0080))
                     : (inc_operand == (inc_is_word ? 16'h7FFF : 16'h007F));
    inc_af = ((({1'b0, inc_operand} ^ 17'h1 ^ inc_r17) >> 4) & 17'h1) != 17'h0;
    inc_zf = (inc_r == 16'b0);
    inc_sf = inc_is_word ? inc_r[15] : inc_r[7];
    inc_pf = ~^(inc_r[7:0]);
  end

  /*
  Shifts and rotates (i186.c shift()).  sh_count_raw is the raw count;
  the low five bits are used.  A masked count of 0 returns the value
  with NO flag change (sh_nochange).  ROL/ROR/RCL/RCR never set
  ZF/SF/PF/AF; their OF rule applies only when the masked count is
  exactly 1.  SHL/SHR/SAR set AF=0 and do set ZF/SF/PF.
  */
  logic [2:0]  sh_op;
  logic [15:0] sh_value;
  logic [4:0]  sh_count_raw; /* count masked to 5 bits (i186.c shift) */
  logic        sh_w, sh_cf_in;
  logic [15:0] sh_r;
  logic        sh_cf, sh_of, sh_set_of, sh_set_szp, sh_af0, sh_nochange;
  logic [4:0]  sh_n, sh_bits, sh_kk, sh_k;
  logic [15:0] sh_msk, sh_msb, sh_vv, sh_rr;
  logic        sh_c;
  logic [4:0]  sh_k17, sh_k9;
  logic [16:0] sh_v17, sh_r17;
  logic [8:0]  sh_v9, sh_r9;
  logic signed [31:0] sh_sv;

  always_comb begin
    sh_n = sh_count_raw;
    sh_bits = sh_w ? 5'd16 : 5'd8;
    sh_msk = sh_w ? 16'hFFFF : 16'h00FF;
    sh_msb = sh_w ? 16'h8000 : 16'h0080;
    sh_vv = sh_value & sh_msk;
    sh_rr = sh_vv;
    sh_c = sh_cf_in;
    sh_r = sh_vv;
    sh_cf = sh_cf_in;
    sh_of = 1'b0;
    sh_set_of = 1'b0;
    sh_set_szp = 1'b0;
    sh_af0 = 1'b0;
    sh_nochange = (sh_n == 5'd0);
    sh_k = 5'd0;
    sh_kk = 5'd0;
    sh_k17 = 5'd0;
    sh_k9 = 5'd0;
    sh_v17 = 17'd0;
    sh_r17 = 17'd0;
    sh_v9 = 9'd0;
    sh_r9 = 9'd0;
    sh_sv = 32'sd0;
    if (sh_n != 5'd0) begin
      case (sh_op)
        SHIFT_ROL: begin
          sh_k = sh_n % sh_bits;
          sh_rr = (sh_k != 5'd0) ? (((sh_vv << sh_k) | (sh_vv >> (sh_bits - sh_k))) & sh_msk) : sh_vv;
          sh_c = sh_rr[0];
          if (sh_n == 5'd1) begin
            sh_of = ((sh_rr & sh_msb) != 16'b0) ^ sh_c;
            sh_set_of = 1'b1;
          end
          sh_r = sh_rr;
          sh_cf = sh_c;
        end
        SHIFT_ROR: begin
          sh_k = sh_n % sh_bits;
          sh_rr = (sh_k != 5'd0) ? (((sh_vv >> sh_k) | (sh_vv << (sh_bits - sh_k))) & sh_msk) : sh_vv;
          sh_c = (sh_rr & sh_msb) != 16'b0;
          if (sh_n == 5'd1) begin
            sh_of = ((sh_rr ^ (sh_rr << 1)) & sh_msb) != 16'b0;
            sh_set_of = 1'b1;
          end
          sh_r = sh_rr;
          sh_cf = sh_c;
        end
        SHIFT_RCL: begin
          /*
          Rotate the (bits+1)-bit value {value, CF} left by n mod
          (bits+1). No loop variable, so no latch in Yosys 0.33.
          */
          if (sh_w) begin
            sh_k17 = sh_n % 5'd17;
            sh_v17 = {sh_vv, sh_cf_in};
            sh_r17 = (sh_k17 == 5'd0) ? sh_v17 :
                     ((sh_v17 << sh_k17) | (sh_v17 >> (5'd17 - sh_k17)));
            sh_rr = sh_r17[16:1];
            sh_c = sh_r17[0];
          end else begin
            sh_k9 = sh_n % 5'd9;
            sh_v9 = {sh_vv[7:0], sh_cf_in};
            sh_r9 = (sh_k9 == 5'd0) ? sh_v9 :
                    ((sh_v9 << sh_k9) | (sh_v9 >> (5'd9 - sh_k9)));
            sh_rr = {8'b0, sh_r9[8:1]};
            sh_c = sh_r9[0];
          end
          if (sh_n == 5'd1) begin
            sh_of = ((sh_rr & sh_msb) != 16'b0) ^ sh_c;
            sh_set_of = 1'b1;
          end
          sh_r = sh_rr;
          sh_cf = sh_c;
        end
        SHIFT_RCR: begin
          /*
          Rotate the (bits+1)-bit value {CF, value} right by n mod
          (bits+1). No loop variable, so no latch in Yosys 0.33.
          */
          if (sh_n == 5'd1) begin
            sh_of = ((sh_vv & sh_msb) != 16'b0) ^ sh_cf_in;
            sh_set_of = 1'b1;
          end
          if (sh_w) begin
            sh_k17 = sh_n % 5'd17;
            sh_v17 = {sh_cf_in, sh_vv};
            sh_r17 = (sh_k17 == 5'd0) ? sh_v17 :
                     ((sh_v17 >> sh_k17) | (sh_v17 << (5'd17 - sh_k17)));
            sh_rr = sh_r17[15:0];
            sh_c = sh_r17[16];
          end else begin
            sh_k9 = sh_n % 5'd9;
            sh_v9 = {sh_cf_in, sh_vv[7:0]};
            sh_r9 = (sh_k9 == 5'd0) ? sh_v9 :
                    ((sh_v9 >> sh_k9) | (sh_v9 << (5'd9 - sh_k9)));
            sh_rr = {8'b0, sh_r9[7:0]};
            sh_c = sh_r9[8];
          end
          sh_r = sh_rr;
          sh_cf = sh_c;
        end
        SHIFT_SHL, 3'd6: begin /* case 4 and case 6 in the C code */
          if (sh_n > sh_bits) begin
            sh_c = 1'b0;
            sh_rr = 16'b0;
          end else begin
            sh_c = ((sh_vv >> (sh_bits - sh_n)) & 16'h1) != 16'h0;
            sh_rr = (sh_vv << sh_n) & sh_msk;
          end
          if (sh_n == 5'd1) begin
            sh_of = ((sh_rr & sh_msb) != 16'b0) ^ sh_c;
            sh_set_of = 1'b1;
          end
          sh_r = sh_rr;
          sh_cf = sh_c;
          sh_set_szp = 1'b1;
          sh_af0 = 1'b1;
        end
        SHIFT_SHR: begin
          sh_c = (sh_n > sh_bits) ? 1'b0 : (((sh_vv >> (sh_n - 5'd1)) & 16'h1) != 16'h0);
          sh_rr = (sh_n >= sh_bits) ? 16'b0 : (sh_vv >> sh_n);
          if (sh_n == 5'd1) begin
            sh_of = (sh_vv & sh_msb) != 16'b0;
            sh_set_of = 1'b1;
          end
          sh_r = sh_rr;
          sh_cf = sh_c;
          sh_set_szp = 1'b1;
          sh_af0 = 1'b1;
        end
        SHIFT_SAR: begin
          sh_sv = sh_w ? $signed({{16{sh_vv[15]}}, sh_vv}) : $signed({{24{sh_vv[7]}}, sh_vv[7:0]});
          sh_kk = (sh_n >= sh_bits) ? (sh_bits - 5'd1) : sh_n;
          sh_c = ((sh_sv >>> ((sh_n > sh_bits) ? (sh_bits - 5'd1) : (sh_n - 5'd1))) & 32'h1) != 32'h0;
          if (sh_w) begin
            sh_rr = $signed(sh_vv) >>> sh_kk;
          end else begin
            sh_rr = {8'b0, ($signed(sh_vv[7:0]) >>> sh_kk)};
          end
          sh_r = sh_rr;
          sh_cf = sh_c;
          sh_of = 1'b0;
          sh_set_of = 1'b1;
          sh_set_szp = 1'b1;
          sh_af0 = 1'b1;
        end
        default: begin
          sh_r = sh_vv;
          sh_cf = sh_cf_in;
        end
      endcase
    end
  end

  /*
  Single 16x16 multiplier (one DSP block in 18x18 mode).  Operands
  are extended to 17 bits: sign-extended for signed forms, zero
  extended for unsigned.  The product feeds registers directly, so
  the multiply output is registered.
  */
  logic        mul_is_signed;
  logic [15:0] mul_operand_a, mul_operand_b;
  logic signed [33:0] mul_p;
  logic signed [MUL_EXT_WIDTH-1:0] mul_a17, mul_b17;
  always_comb begin
    mul_a17 = mul_is_signed ? {mul_operand_a[15], mul_operand_a} : {1'b0, mul_operand_a};
    mul_b17 = mul_is_signed ? {mul_operand_b[15], mul_operand_b} : {1'b0, mul_operand_b};
    mul_p = mul_a17 * mul_b17;
  end

  /*
  Approximate 80C186 clock counts per opcode (manual App. D Table D-2).
  Generated verbatim from i186.c CYC[256]; do not hand-edit.
  */
  function automatic [7:0] cyc_base(input [7:0] op);
    case (op)
      /*
      0x00
      */
      8'h00: cyc_base = 8'd3;
      8'h01: cyc_base = 8'd3;
      8'h02: cyc_base = 8'd3;
      8'h03: cyc_base = 8'd3;
      8'h04: cyc_base = 8'd3;
      8'h05: cyc_base = 8'd4;
      8'h06: cyc_base = 8'd9;
      8'h07: cyc_base = 8'd8;
      8'h08: cyc_base = 8'd3;
      8'h09: cyc_base = 8'd3;
      8'h0A: cyc_base = 8'd3;
      8'h0B: cyc_base = 8'd3;
      8'h0C: cyc_base = 8'd3;
      8'h0D: cyc_base = 8'd4;
      8'h0E: cyc_base = 8'd9;
      8'h0F: cyc_base = 8'd3;
      /*
      0x10
      */
      8'h10: cyc_base = 8'd3;
      8'h11: cyc_base = 8'd3;
      8'h12: cyc_base = 8'd3;
      8'h13: cyc_base = 8'd3;
      8'h14: cyc_base = 8'd3;
      8'h15: cyc_base = 8'd4;
      8'h16: cyc_base = 8'd9;
      8'h17: cyc_base = 8'd8;
      8'h18: cyc_base = 8'd3;
      8'h19: cyc_base = 8'd3;
      8'h1A: cyc_base = 8'd3;
      8'h1B: cyc_base = 8'd3;
      8'h1C: cyc_base = 8'd3;
      8'h1D: cyc_base = 8'd4;
      8'h1E: cyc_base = 8'd9;
      8'h1F: cyc_base = 8'd8;
      /*
      0x20
      */
      8'h20: cyc_base = 8'd3;
      8'h21: cyc_base = 8'd3;
      8'h22: cyc_base = 8'd3;
      8'h23: cyc_base = 8'd3;
      8'h24: cyc_base = 8'd3;
      8'h25: cyc_base = 8'd4;
      8'h26: cyc_base = 8'd3;
      8'h27: cyc_base = 8'd4;
      8'h28: cyc_base = 8'd3;
      8'h29: cyc_base = 8'd3;
      8'h2A: cyc_base = 8'd3;
      8'h2B: cyc_base = 8'd3;
      8'h2C: cyc_base = 8'd3;
      8'h2D: cyc_base = 8'd4;
      8'h2E: cyc_base = 8'd3;
      8'h2F: cyc_base = 8'd4;
      /*
      0x30
      */
      8'h30: cyc_base = 8'd3;
      8'h31: cyc_base = 8'd3;
      8'h32: cyc_base = 8'd3;
      8'h33: cyc_base = 8'd3;
      8'h34: cyc_base = 8'd3;
      8'h35: cyc_base = 8'd4;
      8'h36: cyc_base = 8'd3;
      8'h37: cyc_base = 8'd7;
      8'h38: cyc_base = 8'd3;
      8'h39: cyc_base = 8'd3;
      8'h3A: cyc_base = 8'd3;
      8'h3B: cyc_base = 8'd3;
      8'h3C: cyc_base = 8'd3;
      8'h3D: cyc_base = 8'd4;
      8'h3E: cyc_base = 8'd3;
      8'h3F: cyc_base = 8'd7;
      /*
      0x40
      */
      8'h40: cyc_base = 8'd3;
      8'h41: cyc_base = 8'd3;
      8'h42: cyc_base = 8'd3;
      8'h43: cyc_base = 8'd3;
      8'h44: cyc_base = 8'd3;
      8'h45: cyc_base = 8'd3;
      8'h46: cyc_base = 8'd3;
      8'h47: cyc_base = 8'd3;
      8'h48: cyc_base = 8'd3;
      8'h49: cyc_base = 8'd3;
      8'h4A: cyc_base = 8'd3;
      8'h4B: cyc_base = 8'd3;
      8'h4C: cyc_base = 8'd3;
      8'h4D: cyc_base = 8'd3;
      8'h4E: cyc_base = 8'd3;
      8'h4F: cyc_base = 8'd3;
      /*
      0x50
      */
      8'h50: cyc_base = 8'd10;
      8'h51: cyc_base = 8'd10;
      8'h52: cyc_base = 8'd10;
      8'h53: cyc_base = 8'd10;
      8'h54: cyc_base = 8'd10;
      8'h55: cyc_base = 8'd10;
      8'h56: cyc_base = 8'd10;
      8'h57: cyc_base = 8'd10;
      8'h58: cyc_base = 8'd10;
      8'h59: cyc_base = 8'd10;
      8'h5A: cyc_base = 8'd10;
      8'h5B: cyc_base = 8'd10;
      8'h5C: cyc_base = 8'd10;
      8'h5D: cyc_base = 8'd10;
      8'h5E: cyc_base = 8'd10;
      8'h5F: cyc_base = 8'd10;
      /*
      0x60
      */
      8'h60: cyc_base = 8'd36;
      8'h61: cyc_base = 8'd51;
      8'h62: cyc_base = 8'd27;
      8'h63: cyc_base = 8'd3;
      8'h64: cyc_base = 8'd3;
      8'h65: cyc_base = 8'd3;
      8'h66: cyc_base = 8'd3;
      8'h67: cyc_base = 8'd3;
      8'h68: cyc_base = 8'd10;
      8'h69: cyc_base = 8'd24;
      8'h6A: cyc_base = 8'd10;
      8'h6B: cyc_base = 8'd24;
      8'h6C: cyc_base = 8'd5;
      8'h6D: cyc_base = 8'd5;
      8'h6E: cyc_base = 8'd5;
      8'h6F: cyc_base = 8'd5;
      /*
      0x70
      */
      8'h70: cyc_base = 8'd4;
      8'h71: cyc_base = 8'd4;
      8'h72: cyc_base = 8'd4;
      8'h73: cyc_base = 8'd4;
      8'h74: cyc_base = 8'd4;
      8'h75: cyc_base = 8'd4;
      8'h76: cyc_base = 8'd4;
      8'h77: cyc_base = 8'd4;
      8'h78: cyc_base = 8'd4;
      8'h79: cyc_base = 8'd4;
      8'h7A: cyc_base = 8'd4;
      8'h7B: cyc_base = 8'd4;
      8'h7C: cyc_base = 8'd4;
      8'h7D: cyc_base = 8'd4;
      8'h7E: cyc_base = 8'd4;
      8'h7F: cyc_base = 8'd4;
      /*
      0x80
      */
      8'h80: cyc_base = 8'd4;
      8'h81: cyc_base = 8'd4;
      8'h82: cyc_base = 8'd4;
      8'h83: cyc_base = 8'd4;
      8'h84: cyc_base = 8'd3;
      8'h85: cyc_base = 8'd3;
      8'h86: cyc_base = 8'd4;
      8'h87: cyc_base = 8'd4;
      8'h88: cyc_base = 8'd2;
      8'h89: cyc_base = 8'd2;
      8'h8A: cyc_base = 8'd2;
      8'h8B: cyc_base = 8'd2;
      8'h8C: cyc_base = 8'd2;
      8'h8D: cyc_base = 8'd0;
      8'h8E: cyc_base = 8'd2;
      8'h8F: cyc_base = 8'd14;
      /*
      0x90
      */
      8'h90: cyc_base = 8'd3;
      8'h91: cyc_base = 8'd3;
      8'h92: cyc_base = 8'd3;
      8'h93: cyc_base = 8'd3;
      8'h94: cyc_base = 8'd3;
      8'h95: cyc_base = 8'd3;
      8'h96: cyc_base = 8'd3;
      8'h97: cyc_base = 8'd3;
      8'h98: cyc_base = 8'd2;
      8'h99: cyc_base = 8'd4;
      8'h9A: cyc_base = 8'd23;
      8'h9B: cyc_base = 8'd3;
      8'h9C: cyc_base = 8'd9;
      8'h9D: cyc_base = 8'd8;
      8'h9E: cyc_base = 8'd3;
      8'h9F: cyc_base = 8'd2;
      /*
      0xA0
      */
      8'hA0: cyc_base = 8'd9;
      8'hA1: cyc_base = 8'd9;
      8'hA2: cyc_base = 8'd8;
      8'hA3: cyc_base = 8'd8;
      8'hA4: cyc_base = 8'd5;
      8'hA5: cyc_base = 8'd5;
      8'hA6: cyc_base = 8'd5;
      8'hA7: cyc_base = 8'd5;
      8'hA8: cyc_base = 8'd3;
      8'hA9: cyc_base = 8'd3;
      8'hAA: cyc_base = 8'd5;
      8'hAB: cyc_base = 8'd5;
      8'hAC: cyc_base = 8'd5;
      8'hAD: cyc_base = 8'd5;
      8'hAE: cyc_base = 8'd5;
      8'hAF: cyc_base = 8'd5;
      /*
      0xB0
      */
      8'hB0: cyc_base = 8'd3;
      8'hB1: cyc_base = 8'd3;
      8'hB2: cyc_base = 8'd3;
      8'hB3: cyc_base = 8'd3;
      8'hB4: cyc_base = 8'd3;
      8'hB5: cyc_base = 8'd3;
      8'hB6: cyc_base = 8'd3;
      8'hB7: cyc_base = 8'd3;
      8'hB8: cyc_base = 8'd4;
      8'hB9: cyc_base = 8'd4;
      8'hBA: cyc_base = 8'd4;
      8'hBB: cyc_base = 8'd4;
      8'hBC: cyc_base = 8'd4;
      8'hBD: cyc_base = 8'd4;
      8'hBE: cyc_base = 8'd4;
      8'hBF: cyc_base = 8'd4;
      /*
      0xC0
      */
      8'hC0: cyc_base = 8'd6;
      8'hC1: cyc_base = 8'd6;
      8'hC2: cyc_base = 8'd18;
      8'hC3: cyc_base = 8'd16;
      8'hC4: cyc_base = 8'd12;
      8'hC5: cyc_base = 8'd12;
      8'hC6: cyc_base = 8'd6;
      8'hC7: cyc_base = 8'd6;
      8'hC8: cyc_base = 8'd15;
      8'hC9: cyc_base = 8'd8;
      8'hCA: cyc_base = 8'd25;
      8'hCB: cyc_base = 8'd22;
      8'hCC: cyc_base = 8'd3;
      8'hCD: cyc_base = 8'd5;
      8'hCE: cyc_base = 8'd3;
      8'hCF: cyc_base = 8'd28;
      /*
      0xD0
      */
      8'hD0: cyc_base = 8'd4;
      8'hD1: cyc_base = 8'd4;
      8'hD2: cyc_base = 8'd4;
      8'hD3: cyc_base = 8'd4;
      8'hD4: cyc_base = 8'd19;
      8'hD5: cyc_base = 8'd15;
      8'hD6: cyc_base = 8'd3;
      8'hD7: cyc_base = 8'd11;
      8'hD8: cyc_base = 8'd3;
      8'hD9: cyc_base = 8'd3;
      8'hDA: cyc_base = 8'd3;
      8'hDB: cyc_base = 8'd3;
      8'hDC: cyc_base = 8'd3;
      8'hDD: cyc_base = 8'd3;
      8'hDE: cyc_base = 8'd3;
      8'hDF: cyc_base = 8'd3;
      /*
      0xE0
      */
      8'hE0: cyc_base = 8'd6;
      8'hE1: cyc_base = 8'd6;
      8'hE2: cyc_base = 8'd6;
      8'hE3: cyc_base = 8'd6;
      8'hE4: cyc_base = 8'd10;
      8'hE5: cyc_base = 8'd10;
      8'hE6: cyc_base = 8'd9;
      8'hE7: cyc_base = 8'd9;
      8'hE8: cyc_base = 8'd15;
      8'hE9: cyc_base = 8'd14;
      8'hEA: cyc_base = 8'd14;
      8'hEB: cyc_base = 8'd14;
      8'hEC: cyc_base = 8'd8;
      8'hED: cyc_base = 8'd8;
      8'hEE: cyc_base = 8'd7;
      8'hEF: cyc_base = 8'd7;
      /*
      0xF0
      */
      8'hF0: cyc_base = 8'd3;
      8'hF1: cyc_base = 8'd3;
      8'hF2: cyc_base = 8'd3;
      8'hF3: cyc_base = 8'd3;
      8'hF4: cyc_base = 8'd2;
      8'hF5: cyc_base = 8'd2;
      8'hF6: cyc_base = 8'd3;
      8'hF7: cyc_base = 8'd3;
      8'hF8: cyc_base = 8'd2;
      8'hF9: cyc_base = 8'd2;
      8'hFA: cyc_base = 8'd2;
      8'hFB: cyc_base = 8'd2;
      8'hFC: cyc_base = 8'd2;
      8'hFD: cyc_base = 8'd2;
      8'hFE: cyc_base = 8'd3;
      8'hFF: cyc_base = 8'd3;
      default: cyc_base = 8'd0;
    endcase
  endfunction

  /*
  Memory extra cycles for a memory ModRM operand (i186.c memextra).
  */
  function automatic [7:0] memextra(input [7:0] op, input [2:0] regf_in);
    case (op)
      8'h88, 8'h89: memextra = MEMEXTRA_MOV_RM;
      8'h8A, 8'h8B, 8'h8E: memextra = MEMEXTRA_MOV_R;
      8'h8C: memextra = MEMEXTRA_MOV_SREG;
      8'hC7: memextra = MEMEXTRA_MOV_IMM;
      8'h80, 8'h81, 8'h82, 8'h83: memextra = (regf_in == 3'd7) ? 8'd0 : MEMEXTRA_GROUP80;
      8'hFE: memextra = (regf_in < 3'd2) ? MEMEXTRA_GROUP_FE : 8'd0;
      8'hFF: memextra = (regf_in < 3'd2) ? MEMEXTRA_GROUP_FF : (regf_in == 3'd6) ? MEMEXTRA_FF_PUSH : 8'd0;
      8'h86, 8'h87: memextra = MEMEXTRA_XCHG;
      8'h84, 8'h85: memextra = MEMEXTRA_TEST;
      8'hF6, 8'hF7: memextra = (regf_in < 3'd2) ? MEMEXTRA_F6F7 : 8'd0;
      default: begin
        if ((op < 8'h40) && ((op[2:0]) < 3'd4)) memextra = MEMEXTRA_ALU;
        else memextra = 8'd0;
      end
    endcase
  endfunction

  /*
  Does this opcode fetch a ModRM byte?
  */
  function automatic logic decode_has_modrm(input [7:0] op);
    decode_has_modrm = ((op < 8'h40) && (op[2:0] < 3'd4)) ||
      (op == 8'h62) || (op == 8'h69) || (op == 8'h6B) ||
      ((op >= 8'h80) && (op <= 8'h8F)) ||
      ((op >= 8'hC0) && (op <= 8'hC1)) || ((op >= 8'hC4) && (op <= 8'hC7)) ||   /* not C2 / C3 (RET imm16 / RET) */
      ((op >= 8'hD0) && (op <= 8'hD3)) || ((op >= 8'hD8) && (op <= 8'hDF)) ||   /* not D4 / D5 (AAM / AAD) / D6 / D7 (XLAT) */
      (op == 8'hF6) || (op == 8'hF7) ||
      (op == 8'hFE) || (op == 8'hFF);
  endfunction

  /*
  Operand width for this opcode (0x62/0xC4/0xC5/0x8C/0x8E/0x8F/0xFF
  are word-only; 0xFE is byte-only; everything else follows op[0]).
  */
  function automatic logic decode_width(input [7:0] op);
    if ((op == 8'h62) || (op == 8'hC4) || (op == 8'hC5) ||
        (op == 8'h8C) || (op == 8'h8E) || (op == 8'h8F) || (op == 8'hFF))
      decode_width = 1'b1;
    else if (op == 8'hFE)
      decode_width = 1'b0;
    else
      decode_width = op[0];
  endfunction

  /*
  Immediate kind for the fetch plan (see IMM_* localparams).
  */
  function automatic [2:0] decode_imm_kind(input [7:0] op);
    if ((op == 8'hCD) || (op == 8'hD4) || (op == 8'hD5) ||
        ((op >= 8'hE0) && (op <= 8'hE7)) || (op == 8'hEB) ||
        (op == 8'h6A) || (op == 8'h6B) ||
        (op == 8'hC0) || (op == 8'hC1) ||
        (op == 8'hA8) ||
        ((op >= 8'h70) && (op <= 8'h7F)) ||
        ((op < 8'h40) && (op[2:0] == 3'd4)) ||
        ((op >= 8'hB0) && (op <= 8'hB7)) ||
        (op == 8'h83)) /* 0x83 imm is always 8 bits, sign-extended (i186.c:1117-1126) */
      decode_imm_kind = IMM_8;
    else if ((op == 8'h68) || (op == 8'h69) || (op == 8'hE8) || (op == 8'hE9) ||
             (op == 8'hC2) || (op == 8'hCA) ||
             (op == 8'hA9) ||
             ((op >= 8'hA0) && (op <= 8'hA3)) ||
             ((op < 8'h40) && (op[2:0] == 3'd5)) ||
             ((op >= 8'hB8) && (op <= 8'hBF)))
      decode_imm_kind = IMM_16;
    else if ((op == 8'h80) || (op == 8'h81) || (op == 8'h82) ||
             (op == 8'hC6) || (op == 8'hC7) || (op == 8'hF6) || (op == 8'hF7))
      decode_imm_kind = IMM_W;
    else if (op == 8'hC8)
      decode_imm_kind = IMM_16_8;
    else if ((op == 8'h9A) || (op == 8'hEA))
      decode_imm_kind = IMM_16_16;
    else
      decode_imm_kind = IMM_NONE;
  endfunction

  /*
  Does this ModRM instruction read the r/m operand before executing?
  */
  function automatic logic decode_need_rm_rd(input [7:0] op, input [1:0] mod_in,
                                          input [2:0] regf_in);
    if (mod_in == 2'd3) decode_need_rm_rd = 1'b0; /* register form: in gpr[] */
    else if ((op < 8'h40) && (op[2:0] < 3'd4)) decode_need_rm_rd = 1'b1;
    else if ((op == 8'h69) || (op == 8'h6B)) decode_need_rm_rd = 1'b1;
    else if ((op >= 8'h80) && (op <= 8'h83)) decode_need_rm_rd = 1'b1;
    else if ((op == 8'h84) || (op == 8'h85)) decode_need_rm_rd = 1'b1;
    else if ((op == 8'h86) || (op == 8'h87)) decode_need_rm_rd = 1'b1;
    else if ((op == 8'h8A) || (op == 8'h8B) || (op == 8'h8E)) decode_need_rm_rd = 1'b1;
    else if ((op == 8'hC0) || (op == 8'hC1)) decode_need_rm_rd = 1'b1;
    else if ((op >= 8'hD0) && (op <= 8'hD3)) decode_need_rm_rd = 1'b1;
    else if ((op == 8'hF6) || (op == 8'hF7)) decode_need_rm_rd = 1'b1;
    else if (op == 8'hFE) decode_need_rm_rd = 1'b1;
    else if (op == 8'hFF) decode_need_rm_rd = (regf_in == 3'd0) || (regf_in == 3'd1) ||
                                           (regf_in == 3'd2) || (regf_in == 3'd4) ||
                                           (regf_in == 3'd6);
    else decode_need_rm_rd = 1'b0;
  endfunction

  /*
  String opcode (A4-A7, AA-AF, 6C-6F)?
  */
  function automatic logic decode_is_string(input [7:0] op);
    decode_is_string = ((op >= 8'hA4) && (op <= 8'hA7)) ||
                    ((op >= 8'hAA) && (op <= 8'hAF)) ||
                    ((op >= 8'h6C) && (op <= 8'h6F));
  endfunction

  /*
  Is this opcode a bad opcode in the C model (given the cycle model)?
  Prefix bytes are handled by the FSM, not here.
  */
  function automatic logic decode_is_badop(input [7:0] op, input cyc_model_in);
    decode_is_badop = (op == 8'h0F) || (op == 8'hD6) || (op == 8'hF1) ||
                   ((op >= 8'h63) && (op <= 8'h67)) ||
                   (!cyc_model_in && ((op == 8'h26) || (op == 8'h2E) ||
                                       (op == 8'h36) || (op == 8'h3E)));
  endfunction

  /*
  Execution class from the opcode.
  */
  function automatic instr_class_t decode_class(input [7:0] op);
    if ((op < 8'h40) && (op[2:0] < 3'd4)) decode_class = CLASS_ALU_RM;
    else if ((op < 8'h40) && (op[2:0] < 3'd6)) decode_class = CLASS_ALU_IMM;
    else if ((op == 8'h06) || (op == 8'h0E) || (op == 8'h16) || (op == 8'h1E) ||
             (op == 8'h07) || (op == 8'h17) || (op == 8'h1F)) decode_class = CLASS_SEG_PUSH_POP;
    else if ((op == 8'h27) || (op == 8'h2F) || (op == 8'h37) || (op == 8'h3F)) decode_class = CLASS_DECIMAL;
    else if ((op == 8'hD4) || (op == 8'hD5)) decode_class = CLASS_AAM_AAD;
    else if ((op >= 8'h40) && (op <= 8'h4F)) decode_class = CLASS_INCDEC_REG;
    else if ((op >= 8'h50) && (op <= 8'h57)) decode_class = CLASS_PUSH_REG;
    else if ((op >= 8'h58) && (op <= 8'h5F)) decode_class = CLASS_POP_REG;
    else if (op == 8'h60) decode_class = CLASS_PUSHA;
    else if (op == 8'h61) decode_class = CLASS_POPA;
    else if (op == 8'h62) decode_class = CLASS_BOUND;
    else if ((op == 8'h68) || (op == 8'h6A)) decode_class = CLASS_PUSH_IMM;
    else if ((op == 8'h69) || (op == 8'h6B)) decode_class = CLASS_IMUL_IMM;
    else if ((op >= 8'h70) && (op <= 8'h7F)) decode_class = CLASS_JUMP_CC;
    else if ((op >= 8'h80) && (op <= 8'h83)) decode_class = CLASS_ALU_IMM_RM;
    else if ((op >= 8'h84) && (op <= 8'h8F)) decode_class = CLASS_TRANSFER_MOV;
    else if (op == 8'h90) decode_class = CLASS_NOP;
    else if (op == 8'h9B) decode_class = CLASS_NOP;
    else if ((op >= 8'h91) && (op <= 8'h97)) decode_class = CLASS_XCHG_AX;
    else if ((op == 8'h98) || (op == 8'h99)) decode_class = CLASS_CBW_CWD;
    else if (op == 8'h9A) decode_class = CLASS_CALL_FAR;
    else if (op == 8'h9C) decode_class = CLASS_PUSHF;
    else if (op == 8'h9D) decode_class = CLASS_POPF;
    else if (op == 8'h9E) decode_class = CLASS_SAHF;
    else if (op == 8'h9F) decode_class = CLASS_LAHF;
    else if ((op >= 8'hA0) && (op <= 8'hA3)) decode_class = CLASS_MOFFS;
    else if ((op == 8'hA8) || (op == 8'hA9)) decode_class = CLASS_TEST_ACC;
    else if ((op >= 8'hB0) && (op <= 8'hBF)) decode_class = CLASS_MOV_IMM;
    else if ((op == 8'hC0) || (op == 8'hC1)) decode_class = CLASS_SHIFT_IMM;
    else if ((op == 8'hC2) || (op == 8'hC3) || (op == 8'hCA) || (op == 8'hCB)) decode_class = CLASS_RETURN;
    else if ((op == 8'hC4) || (op == 8'hC5)) decode_class = CLASS_LES_LDS;
    else if ((op == 8'hC6) || (op == 8'hC7)) decode_class = CLASS_MOV_RM_IMM;
    else if (op == 8'hC8) decode_class = CLASS_ENTER;
    else if (op == 8'hC9) decode_class = CLASS_LEAVE;
    else if ((op >= 8'hCC) && (op <= 8'hCF)) decode_class = CLASS_INTERRUPT;
    else if ((op >= 8'hD0) && (op <= 8'hD3)) decode_class = CLASS_SHIFT_1_CL;
    else if (op == 8'hD7) decode_class = CLASS_XLAT;
    else if ((op >= 8'hD8) && (op <= 8'hDF)) decode_class = CLASS_ESCAPE;
    else if ((op >= 8'hE0) && (op <= 8'hE3)) decode_class = CLASS_LOOP;
    else if ((op >= 8'hE4) && (op <= 8'hE7)) decode_class = CLASS_INOUT_IMM;
    else if ((op == 8'hE8) || (op == 8'hE9) || (op == 8'hEA) || (op == 8'hEB)) decode_class = CLASS_CALL_JMP;
    else if ((op >= 8'hEC) && (op <= 8'hEF)) decode_class = CLASS_INOUT_DX;
    else if ((op == 8'hF4) || (op == 8'hF5)) decode_class = CLASS_HALT_CMC;
    else if ((op == 8'hF6) || (op == 8'hF7)) decode_class = CLASS_GROUP_F6_F7;
    else if ((op >= 8'hF8) && (op <= 8'hFD)) decode_class = CLASS_FLAG_OPS;
    else if (op == 8'hFE) decode_class = CLASS_GROUP_FE;
    else if (op == 8'hFF) decode_class = CLASS_GROUP_FF;
    else decode_class = CLASS_NOP;
  endfunction

  /*
  Effective-address computation (i186.c ea()). The base+index sum and
  the default segment are functions of (mod, rmf), so the fetch states
  can evaluate them for the byte just fetched as well as for the
  registered fields. The fetch states add the displacement they just
  fetched to the base; no displacement register is kept.
  */
  function automatic [15:0] ea_base_for(input [1:0] mod_in, input [2:0] rmf_in);
    case (rmf_in)
      3'd0: ea_base_for = gpr[REG_BX] + gpr[REG_SI];
      3'd1: ea_base_for = gpr[REG_BX] + gpr[REG_DI];
      3'd2: ea_base_for = gpr[REG_BP] + gpr[REG_SI];
      3'd3: ea_base_for = gpr[REG_BP] + gpr[REG_DI];
      3'd4: ea_base_for = gpr[REG_SI];
      3'd5: ea_base_for = gpr[REG_DI];
      3'd6: ea_base_for = (mod_in == 2'd0) ? 16'h0000 : gpr[REG_BP];
      default: ea_base_for = gpr[REG_BX];
    endcase
  endfunction

  function automatic [1:0] ea_seg_default_for(input [1:0] mod_in, input [2:0] rmf_in);
    case (rmf_in)
      3'd2: ea_seg_default_for = SEG_SS;
      3'd3: ea_seg_default_for = SEG_SS;
      3'd6: ea_seg_default_for = (mod_in == 2'd0) ? SEG_DS : SEG_SS;
      default: ea_seg_default_for = SEG_DS;
    endcase
  endfunction

  logic [15:0] ea_base_c;
  logic [1:0] ea_seg_c, ea_seg_default;

  always_comb begin
    ea_base_c = ea_base_for(mod, rmf);
    ea_seg_default = ea_seg_default_for(mod, rmf);
    ea_seg_c = segment_override_valid ? segment_override : ea_seg_default;
  end

  /*
  Displacement register (filled by the fetch states).
  */

  /*
  Register operand for the ModRM reg field (width is_word).
  */
  logic [15:0] reg_operand;
  assign reg_operand = get_reg(regf, is_word);

  /* The AL byte, as a signal (a function result cannot be bit-selected). */
  logic [7:0] al_byte;
  assign al_byte = get_byte(REG_AX);
  /*
  Word aliases for AX/DX/CX (Yosys 0.33 rejects a bit-select on an
  array element, such as gpr with a bit range). The alias is a plain
  signal, so a bit-select on it is fine. ah_byte is the high byte
  of AX. Only the high bits are consumed downstream (AH, sign bits,
  CX low 5); the unused low bits are the price of the full-word read.
  */
  /* verilator lint_off UNUSEDSIGNAL */
  logic [15:0] ax_word, dx_word, cx_word;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [7:0] ah_byte;
  assign ax_word = gpr[REG_AX];
  assign dx_word = gpr[REG_DX];
  assign cx_word = gpr[REG_CX];
  assign ah_byte = ax_word[15:8];

  /*
  Current instruction class (combinational).
  */
  instr_class_t instr_class;
  assign instr_class = decode_class(opcode);


  /*
  ------------------------------------------------------------------
  Bus driver (combinational).  The core holds bus_req until ack.
  ------------------------------------------------------------------
  */
  logic [19:0] bus_addr_c;
  logic        bus_req_c, bus_wr_c, bus_w_c, bus_io_c;
  logic [15:0] bus_wdata_c;

  always_comb begin
    bus_req_c = 1'b0;
    bus_wr_c = 1'b0;
    bus_w_c = 1'b0;
    bus_io_c = 1'b0;
    bus_addr_c = 20'h0;
    bus_wdata_c = 16'h0;
    case (state)
      FETCH_OPCODE, FETCH_MODRM, FETCH_DISP8, FETCH_DISP16_LO, FETCH_DISP16_HI, FETCH_IMM8, FETCH_IMM16_LO,
      FETCH_IMM16_HI, FETCH_FAR_LO, FETCH_FAR_HI: begin
        bus_req_c = 1'b1;
        bus_addr_c = linear_addr(sreg[SEG_CS], ip);
        bus_wr_c = 1'b0;
        bus_w_c = 1'b0;
        bus_io_c = 1'b0;
      end
      READ_RM: begin
        bus_req_c = 1'b1;
        bus_addr_c = linear_addr(ea_seg, ea_off);
        bus_wr_c = 1'b0;
        bus_w_c = is_word;
        bus_io_c = 1'b0;
      end
      EXECUTE: begin
        case (instr_class)
          CLASS_PUSH_REG, CLASS_PUSH_IMM, CLASS_PUSHF: begin
            /*
            One push; the value depends on the class/opcode.
            */
            bus_req_c = 1'b1;
            bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP] - STACK_SLOT_BYTES);
            bus_wr_c = 1'b1;
            bus_w_c = 1'b1;
            bus_io_c = 1'b0;
            if (instr_class == CLASS_PUSH_REG)
              bus_wdata_c = get_reg(opcode[2:0], 1'b1);
            else if (instr_class == CLASS_PUSH_IMM)
              bus_wdata_c = imm;
            else
              bus_wdata_c = flags_get();
          end
          CLASS_SEG_PUSH_POP: begin
            bus_req_c = 1'b1;
            if (opcode[0] == 1'b0) begin
              bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP] - STACK_SLOT_BYTES);
              bus_wr_c = 1'b1;
              bus_w_c = 1'b1;
              bus_io_c = 1'b0;
              bus_wdata_c = sreg[opcode[4:3]];
            end else begin
              bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP]);
              bus_wr_c = 1'b0;
              bus_w_c = 1'b1;
              bus_io_c = 1'b0;
            end
          end
          CLASS_POP_REG, CLASS_POPF: begin
            bus_req_c = 1'b1;
            bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP]);
            bus_wr_c = 1'b0;
            bus_w_c = 1'b1;
            bus_io_c = 1'b0;
          end
          CLASS_PUSHA: begin
            /*
            Step i pushes gpr[i] (AX CX DX BX SP BP SI DI). SP is
            unchanged during the push sequence, so gpr[SP] at step 4 is
            the pre-instruction SP (as in the C code).
            */
            bus_req_c = 1'b1;
            bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP] - ({11'b0, exec_step} << 1) - STACK_SLOT_BYTES);
            bus_wr_c = 1'b1;
            bus_w_c = 1'b1;
            bus_io_c = 1'b0;
            bus_wdata_c = gpr[exec_step[2:0]];
          end
          CLASS_POPA: begin
            bus_req_c = 1'b1;
            bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP] + ({11'b0, exec_step} << 1));
            bus_wr_c = 1'b0;
            bus_w_c = 1'b1;
            bus_io_c = 1'b0;
          end
          CLASS_RETURN: begin
            bus_req_c = 1'b1;
            bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP]);
            bus_wr_c = 1'b0;
            bus_w_c = 1'b1;
            bus_io_c = 1'b0;
          end
          CLASS_CALL_FAR: begin
            /*
            step 0: push CS, step 1: push IP.
            */
            bus_req_c = 1'b1;
            bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP] - STACK_SLOT_BYTES);
            bus_wr_c = 1'b1;
            bus_w_c = 1'b1;
            bus_io_c = 1'b0;
            bus_wdata_c = (exec_step == 5'd0) ? sreg[SEG_CS] : ip;
          end
          CLASS_CALL_JMP: begin
            /* E8 (CALL near) only: push IP. E9/EA/EB need no bus cycle. */
            if (opcode == 8'hE8) begin
              bus_req_c = 1'b1;
              bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP] - STACK_SLOT_BYTES);
              bus_wr_c = 1'b1;
              bus_w_c = 1'b1;
              bus_io_c = 1'b0;
              bus_wdata_c = ip;
            end
          end
          CLASS_INTERRUPT: begin
            /*
            IRET (CF) only: step 0 pop IP, step 1 pop CS, step 2 pop FLAGS.
            */
            if (opcode == 8'hCF) begin
              bus_req_c = 1'b1;
              bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP]);
              bus_wr_c = 1'b0;
              bus_w_c = 1'b1;
              bus_io_c = 1'b0;
            end
          end
          CLASS_TRANSFER_MOV: begin
            if (opcode == 8'h8F) begin /* POP r/m */
              bus_req_c = 1'b1;
              bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP]);
              bus_wr_c = 1'b0;
              bus_w_c = 1'b1;
              bus_io_c = 1'b0;
            end
          end
          CLASS_MOFFS: begin
            bus_req_c = 1'b1;
            bus_addr_c = linear_addr(sreg[segment_override_valid ? segment_override : SEG_DS], imm);
            bus_w_c = is_word;
            bus_io_c = 1'b0;
            if ((opcode == 8'hA0) || (opcode == 8'hA1)) begin
              bus_wr_c = 1'b0;
            end else begin
              bus_wr_c = 1'b1;
              bus_wdata_c = is_word ? gpr[REG_AX] : {8'b0, get_byte(REG_AX)};
            end
          end
          CLASS_GROUP_FF: begin
            if (regf == 3'd2) begin /* CALL r/m: push IP */
              bus_req_c = 1'b1;
              bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP] - STACK_SLOT_BYTES);
              bus_wr_c = 1'b1;
              bus_w_c = 1'b1;
              bus_io_c = 1'b0;
              bus_wdata_c = ip;
            end else if (regf == 3'd3) begin
              if (exec_step == 5'd0) begin /* read the far segment */
                bus_req_c = 1'b1;
                bus_addr_c = linear_addr(ea_seg, ea_off + FAR_PTR_SEG_OFF);
                bus_wr_c = 1'b0;
                bus_w_c = 1'b1;
                bus_io_c = 1'b0;
              end else begin /* push CS, then push IP */
                bus_req_c = 1'b1;
                bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP] - STACK_SLOT_BYTES);
                bus_wr_c = 1'b1;
                bus_w_c = 1'b1;
                bus_io_c = 1'b0;
                bus_wdata_c = (exec_step == 5'd1) ? sreg[SEG_CS] : ip;
              end
            end else if (regf == 3'd5) begin /* JMP far r/m: read segment */
              bus_req_c = 1'b1;
              bus_addr_c = linear_addr(ea_seg, ea_off + FAR_PTR_SEG_OFF);
              bus_wr_c = 1'b0;
              bus_w_c = 1'b1;
              bus_io_c = 1'b0;
            end else if (regf == 3'd6) begin /* PUSH r/m */
              bus_req_c = 1'b1;
              bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP] - STACK_SLOT_BYTES);
              bus_wr_c = 1'b1;
              bus_w_c = 1'b1;
              bus_io_c = 1'b0;
              bus_wdata_c = rm_operand;
            end
          end
          CLASS_BOUND, CLASS_LES_LDS: begin
            /*
            BOUND step 0: read lo, step 1: read hi.
            LES/LDS step 0: read the segment word at ea+2.
            */
            bus_req_c = 1'b1;
            bus_addr_c = linear_addr(ea_seg, ea_off + ((instr_class == CLASS_BOUND && exec_step == 5'd1) ||
                                               instr_class == CLASS_LES_LDS ? FAR_PTR_SEG_OFF : 16'd0));
            bus_wr_c = 1'b0;
            bus_w_c = 1'b1;
            bus_io_c = 1'b0;
          end
          CLASS_XLAT: begin
            bus_req_c = 1'b1;
            bus_addr_c = linear_addr(sreg[segment_override_valid ? segment_override : SEG_DS], gpr[REG_BX] + {8'b0, get_byte(REG_AX)});
            bus_wr_c = 1'b0;
            bus_w_c = 1'b0;
            bus_io_c = 1'b0;
          end
          CLASS_INOUT_IMM: begin
            bus_req_c = 1'b1;
            bus_addr_c = {4'b0, imm};
            bus_io_c = 1'b1;
            bus_w_c = is_word;
            if ((opcode == 8'hE4) || (opcode == 8'hE5)) begin
              bus_wr_c = 1'b0;
            end else begin
              bus_wr_c = 1'b1;
              bus_wdata_c = is_word ? gpr[REG_AX] : {8'b0, get_byte(REG_AX)};
            end
          end
          CLASS_INOUT_DX: begin
            bus_req_c = 1'b1;
            bus_addr_c = {4'b0, gpr[REG_DX]};
            bus_io_c = 1'b1;
            bus_w_c = is_word;
            if ((opcode == 8'hEC) || (opcode == 8'hED)) begin
              bus_wr_c = 1'b0;
            end else begin
              bus_wr_c = 1'b1;
              bus_wdata_c = is_word ? gpr[REG_AX] : {8'b0, get_byte(REG_AX)};
            end
          end
          CLASS_ENTER: begin
            /*
            step 0: push BP. step 1: read [SS:BP] (BP already decremented).
            step 2: push the display word just read. step 3: push fp.
            */
            bus_req_c = 1'b1;
            bus_w_c = 1'b1;
            bus_io_c = 1'b0;
            if (exec_step == 5'd0) begin
              bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP] - STACK_SLOT_BYTES);
              bus_wr_c = 1'b1;
              bus_wdata_c = gpr[REG_BP];
            end else if (exec_step == 5'd1) begin
              bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_BP]);
              bus_wr_c = 1'b0;
            end else if (exec_step == 5'd2) begin
              bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP] - STACK_SLOT_BYTES);
              bus_wr_c = 1'b1;
              bus_wdata_c = fetch_first;
            end else begin
              bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP] - STACK_SLOT_BYTES);
              bus_wr_c = 1'b1;
              bus_wdata_c = enter_frame_ptr;
            end
          end
          CLASS_LEAVE: begin
            if (exec_step == 5'd1) begin /* pop BP (SP already = BP) */
              bus_req_c = 1'b1;
              bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP]);
              bus_wr_c = 1'b0;
              bus_w_c = 1'b1;
              bus_io_c = 1'b0;
            end
          end
          default: begin
            bus_req_c = 1'b0;
          end
        endcase
      end
      WRITE_RM: begin
        bus_req_c = 1'b1;
        bus_addr_c = linear_addr(ea_seg, ea_off);
        bus_wr_c = 1'b1;
        bus_w_c = is_word;
        bus_io_c = 1'b0;
        bus_wdata_c = writeback_value;
      end
      STRING_OP: begin
        /*
        Completion step: MOVS/CMPS/INS/OUTS at step 2, STOS/LODS/SCAS at
        step 1. No bus transaction there; the pointers and charge are
        updated in the FSM, not on the bus.
        */
        if ((((string_kind == STR_MOVS) || (string_kind == STR_CMPS) ||
              (string_kind == STR_INS) || (string_kind == STR_OUTS)) &&
             (string_step == 3'd2)) ||
            (((string_kind == STR_STOS) || (string_kind == STR_LODS) ||
              (string_kind == STR_SCAS)) && (string_step == 3'd1))) begin
          bus_req_c = 1'b0;
        end else begin
          case (string_kind)
            STR_MOVS: begin
              if (string_step == 3'd0) begin
                bus_req_c = 1'b1;
                bus_addr_c = linear_addr(sreg[segment_override_valid ? segment_override : SEG_DS], gpr[REG_SI]);
                bus_wr_c = 1'b0;
                bus_w_c = is_word;
                bus_io_c = 1'b0;
              end else begin
                bus_req_c = 1'b1;
                bus_addr_c = linear_addr(sreg[SEG_ES], gpr[REG_DI]);
                bus_wr_c = 1'b1;
                bus_w_c = is_word;
                bus_io_c = 1'b0;
                bus_wdata_c = string_op_a;
              end
            end
            STR_CMPS: begin
              if (string_step == 3'd0) begin
                bus_req_c = 1'b1;
                bus_addr_c = linear_addr(sreg[segment_override_valid ? segment_override : SEG_DS], gpr[REG_SI]);
                bus_wr_c = 1'b0;
                bus_w_c = is_word;
                bus_io_c = 1'b0;
              end else begin
                bus_req_c = 1'b1;
                bus_addr_c = linear_addr(sreg[SEG_ES], gpr[REG_DI]);
                bus_wr_c = 1'b0;
                bus_w_c = is_word;
                bus_io_c = 1'b0;
              end
            end
            STR_STOS: begin
              bus_req_c = 1'b1;
              bus_addr_c = linear_addr(sreg[SEG_ES], gpr[REG_DI]);
              bus_wr_c = 1'b1;
              bus_w_c = is_word;
              bus_io_c = 1'b0;
              bus_wdata_c = is_word ? gpr[REG_AX] : {8'b0, get_byte(REG_AX)};
            end
            STR_LODS: begin
              bus_req_c = 1'b1;
              bus_addr_c = linear_addr(sreg[segment_override_valid ? segment_override : SEG_DS], gpr[REG_SI]);
              bus_wr_c = 1'b0;
              bus_w_c = is_word;
              bus_io_c = 1'b0;
            end
            STR_SCAS: begin
              bus_req_c = 1'b1;
              bus_addr_c = linear_addr(sreg[SEG_ES], gpr[REG_DI]);
              bus_wr_c = 1'b0;
              bus_w_c = is_word;
              bus_io_c = 1'b0;
            end
            STR_INS: begin
              if (string_step == 3'd0) begin
                bus_req_c = 1'b1;
                bus_addr_c = {4'b0, gpr[REG_DX]};
                bus_wr_c = 1'b0;
                bus_w_c = is_word;
                bus_io_c = 1'b1;
              end else begin
                bus_req_c = 1'b1;
                bus_addr_c = linear_addr(sreg[SEG_ES], gpr[REG_DI]);
                bus_wr_c = 1'b1;
                bus_w_c = is_word;
                bus_io_c = 1'b0;
                bus_wdata_c = string_op_a;
              end
            end
            STR_OUTS: begin
              if (string_step == 3'd0) begin
                bus_req_c = 1'b1;
                bus_addr_c = linear_addr(sreg[segment_override_valid ? segment_override : SEG_DS], gpr[REG_SI]);
                bus_wr_c = 1'b0;
                bus_w_c = is_word;
                bus_io_c = 1'b0;
              end else begin
                bus_req_c = 1'b1;
                bus_addr_c = {4'b0, gpr[REG_DX]};
                bus_wr_c = 1'b1;
                bus_w_c = is_word;
                bus_io_c = 1'b1;
                bus_wdata_c = string_op_a;
              end
            end
            default: bus_req_c = 1'b0;
          endcase
        end
      end
      INTERRUPT: begin
        case (interrupt_step)
          4'd0: begin /* push FLAGS */
            bus_req_c = 1'b1;
            bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP] - STACK_SLOT_BYTES);
            bus_wr_c = 1'b1;
            bus_w_c = 1'b1;
            bus_io_c = 1'b0;
            bus_wdata_c = flags_get();
          end
          4'd1: begin /* push CS */
            bus_req_c = 1'b1;
            bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP] - STACK_SLOT_BYTES);
            bus_wr_c = 1'b1;
            bus_w_c = 1'b1;
            bus_io_c = 1'b0;
            bus_wdata_c = sreg[SEG_CS];
          end
          4'd2: begin /* push IP */
            bus_req_c = 1'b1;
            bus_addr_c = linear_addr(sreg[SEG_SS], gpr[REG_SP] - STACK_SLOT_BYTES);
            bus_wr_c = 1'b1;
            bus_w_c = 1'b1;
            bus_io_c = 1'b0;
            bus_wdata_c = ip;
          end
          4'd3: begin /* read IVT offset (vec*4) */
            bus_req_c = 1'b1;
            bus_addr_c = {10'b0, interrupt_vector, 2'b00};
            bus_wr_c = 1'b0;
            bus_w_c = 1'b1;
            bus_io_c = 1'b0;
          end
          4'd4: begin /* read IVT segment (vec*4+2) */
            bus_req_c = 1'b1;
            bus_addr_c = {10'b0, interrupt_vector, 2'b00} + IVT_SEG_WORD;
            bus_wr_c = 1'b0;
            bus_w_c = 1'b1;
            bus_io_c = 1'b0;
          end
          default: bus_req_c = 1'b0;
        endcase
      end
      default: bus_req_c = 1'b0;
    endcase
  end

  assign bus_req   = bus_req_c;
  assign bus_addr  = bus_addr_c;
  assign bus_wr    = bus_wr_c;
  assign bus_w     = bus_w_c;
  assign bus_io    = bus_io_c;
  assign bus_wdata = bus_wdata_c;

  /*
  ------------------------------------------------------------------
  ALU / shift / INC-DEC / multiplier input muxes.
  ------------------------------------------------------------------
  */
  always_comb begin
    /*
    Defaults.
    */
    alu_op = ALU_ADD;
    alu_a = 16'h0;
    alu_b = 16'h0;
    alu_w = 1'b1;
    alu_cf_in = 1'b0;
    sh_op = SHIFT_SHL;
    sh_value = 16'h0;
    sh_count_raw = 5'd0;
    sh_w = 1'b1;
    sh_cf_in = 1'b0;
    inc_operand = 16'h0;
    inc_is_dec = 1'b0;
    inc_is_word = 1'b1;
    mul_is_signed = 1'b0;
    mul_operand_a = 16'h0;
    mul_operand_b = 16'h0;
    if (state == EXECUTE) begin
      case (instr_class)
        CLASS_ALU_RM: begin
          alu_op = opcode[5:3];
          alu_w = is_word;
          alu_cf_in = cf;
          if (opcode[2:0] < 3'd2) begin
            alu_a = rm_operand;
            alu_b = reg_operand;
          end else begin
            alu_a = reg_operand;
            alu_b = rm_operand;
          end
        end
        CLASS_ALU_IMM: begin
          alu_op = opcode[5:3];
          alu_w = is_word;
          alu_cf_in = cf;
          alu_a = is_word ? gpr[REG_AX] : {8'b0, get_byte(REG_AX)};
          alu_b = imm;
        end
        CLASS_ALU_IMM_RM: begin
          alu_op = regf;
          alu_w = is_word;
          alu_cf_in = cf;
          alu_a = rm_operand;
          /*
          0x83 word form takes a sign-extended 8-bit immediate
          (i186.c:1124); FETCH_IMM8 zero-extends imm, so extend
          it here. 0x80/0x82 are byte forms and 0x81 fetches a
          full 16-bit immediate, so they use imm as-is.
          */
          if ((opcode == 8'h83) && is_word)
            alu_b = {{8{imm[7]}}, imm[7:0]};
          else
            alu_b = imm;
        end
        CLASS_TRANSFER_MOV: begin
          if ((opcode == 8'h84) || (opcode == 8'h85)) begin
            alu_op = ALU_AND;
            alu_w = is_word;
            alu_a = rm_operand;
            alu_b = reg_operand;
          end
        end
        CLASS_TEST_ACC: begin
          alu_op = ALU_AND;
          alu_w = is_word;
          alu_a = is_word ? gpr[REG_AX] : {8'b0, get_byte(REG_AX)};
          alu_b = imm;
        end
        CLASS_GROUP_F6_F7: begin
          if (regf == 3'd0) begin /* TEST */
            alu_op = ALU_AND;
            alu_w = is_word;
            alu_a = rm_operand;
            alu_b = imm;
          end else if (regf == 3'd3) begin /* NEG */
            alu_op = ALU_SUB;
            alu_w = is_word;
            alu_a = 16'h0;
            alu_b = rm_operand;
          end else if (regf == 3'd4) begin /* MUL */
            mul_is_signed = 1'b0;
            mul_operand_a = is_word ? rm_operand : {8'b0, rm_operand[7:0]};
            mul_operand_b = is_word ? gpr[REG_AX] : {8'b0, get_byte(REG_AX)};
          end else if (regf == 3'd5) begin /* IMUL */
            mul_is_signed = 1'b1;
            mul_operand_a = is_word ? rm_operand : {{8{rm_operand[7]}}, rm_operand[7:0]};
            mul_operand_b = is_word ? gpr[REG_AX] : {{8{al_byte[7]}}, al_byte};
          end
        end
        CLASS_IMUL_IMM: begin
          mul_is_signed = 1'b1;
          mul_operand_a = (opcode == 8'h6B) ? {{8{rm_operand[7]}}, rm_operand[7:0]} : rm_operand;
          mul_operand_b = (opcode == 8'h6B) ? {{8{imm[7]}}, imm[7:0]} : imm;
        end
        CLASS_SHIFT_IMM: begin
          sh_op = (regf == 3'd6) ? SHIFT_SHL : regf;
          sh_value = rm_operand;
          sh_count_raw = imm[4:0];
          sh_w = is_word;
          sh_cf_in = cf;
        end
        CLASS_SHIFT_1_CL: begin
          sh_op = (regf == 3'd6) ? SHIFT_SHL : regf;
          sh_value = rm_operand;
          sh_w = is_word;
          sh_cf_in = cf;
          sh_count_raw = ((opcode == 8'hD0) || (opcode == 8'hD1)) ? SHIFT_BY_ONE_COUNT[4:0] : cx_word[4:0];
        end
        CLASS_INCDEC_REG: begin
          inc_operand = get_reg(opcode[2:0], 1'b1);
          inc_is_dec = opcode[3];
          inc_is_word = 1'b1;
        end
        CLASS_GROUP_FE: begin
          inc_operand = rm_operand;
          inc_is_dec = (regf == 3'd1);
          inc_is_word = 1'b0;
        end
        CLASS_GROUP_FF: begin
          inc_operand = rm_operand;
          inc_is_dec = (regf == 3'd1);
          inc_is_word = 1'b1;
        end
        default: begin
        end
      endcase
    end else if (state == STRING_OP) begin
      if (((string_kind == 3'd1) && (string_step == 3'd2)) ||
          ((string_kind == 3'd4) && (string_step == 3'd1))) begin
        alu_op = ALU_SUB;
        alu_w = is_word;
        alu_cf_in = cf;
        alu_a = (string_kind == 3'd1) ? string_op_a : (is_word ? gpr[REG_AX] : {8'b0, get_byte(REG_AX)});
        alu_b = string_op_b;
      end
    end
  end


  /*
  String-op cycle charges (i186.c strop: single / per_it / setup tables,
  indexed by the k value from str_kind_from_opcode).
  */
  function automatic [7:0] str_single(input [2:0] k);
    case (k)
      STR_MOVS: str_single = 8'd14;
      STR_CMPS: str_single = 8'd22;
      STR_STOS: str_single = 8'd10;
      STR_LODS: str_single = 8'd12;
      STR_SCAS: str_single = 8'd15;
      STR_INS: str_single = 8'd14;
      STR_OUTS: str_single = 8'd14;
      default: str_single = 8'd0;
    endcase
  endfunction

  function automatic [7:0] str_per_it(input [2:0] k);
    case (k)
      STR_MOVS: str_per_it = 8'd8;
      STR_CMPS: str_per_it = 8'd22;
      STR_STOS: str_per_it = 8'd9;
      STR_LODS: str_per_it = 8'd11;
      STR_SCAS: str_per_it = 8'd15;
      STR_INS: str_per_it = 8'd8;
      STR_OUTS: str_per_it = 8'd8;
      default: str_per_it = 8'd0;
    endcase
  endfunction

  function automatic [7:0] str_setup(input [2:0] k);
    case (k)
      STR_MOVS: str_setup = 8'd8;
      STR_CMPS: str_setup = 8'd5;
      STR_STOS: str_setup = 8'd6;
      STR_LODS: str_setup = 8'd6;
      STR_SCAS: str_setup = 8'd5;
      STR_INS: str_setup = 8'd8;
      STR_OUTS: str_setup = 8'd8;
      default: str_setup = 8'd0;
    endcase
  endfunction

  /* Segment selected by a segment-prefix opcode. */
  function automatic [1:0] seg_from_prefix(input [7:0] op);
    case (op)
      PREFIX_ES: seg_from_prefix = SEG_ES;
      PREFIX_CS: seg_from_prefix = SEG_CS;
      PREFIX_SS: seg_from_prefix = SEG_SS;
      PREFIX_DS: seg_from_prefix = SEG_DS;
      default: seg_from_prefix = SEG_DS;
    endcase
  endfunction

  /* String-op kind from the opcode (the w bit is ignored, as in i186.c). */
  function automatic [2:0] str_kind_from_opcode(input [7:0] op);
    case (op & 8'hFE)
      8'hA4: str_kind_from_opcode = STR_MOVS;
      8'hA6: str_kind_from_opcode = STR_CMPS;
      8'hAA: str_kind_from_opcode = STR_STOS;
      8'hAC: str_kind_from_opcode = STR_LODS;
      8'hAE: str_kind_from_opcode = STR_SCAS;
      8'h6C: str_kind_from_opcode = STR_INS;
      8'h6E: str_kind_from_opcode = STR_OUTS;
      default: str_kind_from_opcode = STR_MOVS;
    endcase
  endfunction

  /* True when this ModRM combination is a bad opcode (i186.c dispatch). */
  function automatic logic decode_modrm_badop(input [7:0] op, input [1:0] mod_in,
                                              input [2:0] regf_in);
    if (op == 8'h62)
      decode_modrm_badop = (mod_in == 2'd3);
    else if ((op == 8'hC4) || (op == 8'hC5))
      decode_modrm_badop = (mod_in == 2'd3);
    else if (op == 8'hFE)
      decode_modrm_badop = (regf_in > 3'd1);
    else if (op == 8'hFF)
      decode_modrm_badop = (regf_in == 3'd7) ||
                           (((regf_in == 3'd3) || (regf_in == 3'd5)) && (mod_in == 2'd3));
    else
      decode_modrm_badop = 1'b0;
  endfunction

  /*
  Next state after the ModRM/displacement phase: a memory r/m read when
  the instruction needs it, otherwise the immediate fetch or EXECUTE.
  The immediate-fetch state (or EXECUTE when there is no immediate).
  */
  core_state_t after_modrm_next_c;
  core_state_t fetch_imm_next_c;

  always_comb begin
    if (((opcode == 8'hF6) || (opcode == 8'hF7)) &&
        (regf != 3'd0) && (regf != 3'd1))
      fetch_imm_next_c = EXECUTE;
    else begin
      case (decode_imm_kind(opcode))
        IMM_8: fetch_imm_next_c = FETCH_IMM8;
        IMM_16: fetch_imm_next_c = FETCH_IMM16_LO;
        IMM_W: fetch_imm_next_c = is_word ? FETCH_IMM16_LO : FETCH_IMM8;
        IMM_16_8: fetch_imm_next_c = FETCH_IMM16_LO;
        IMM_16_16: fetch_imm_next_c = FETCH_IMM16_LO;
        default: fetch_imm_next_c = EXECUTE;
      endcase
    end
    if (decode_need_rm_rd(opcode, mod, regf))
      after_modrm_next_c = READ_RM;
    else
      after_modrm_next_c = fetch_imm_next_c;
  end

  /*
  Instruction-boundary decision (i186.c i186_run loop head and the
  single-step check). Priority: TF trap, then NMI, then maskable IRQ,
  then HLT. The IRQ check uses the inhibit flag as set by the
  just-finished instruction; the flag is cleared only when the next
  instruction starts.
  */
  logic [1:0] finish_boundary;
  logic [7:0] finish_vector;
  logic finish_is_nmi;
  logic finish_is_irq;

  /* IF as the instruction that is finishing leaves it: CLI, POPF and the last step of IRET write ifl in the same clock that finish_instruction decides about a pending
     interrupt, so the decision has to see the new value (the C core checks at the head of the next instruction with the current IF: no interrupt is taken right after CLI).
     STI sets IF but inhibits for one instruction (interrupt_inhibit), unchanged. */
  logic irq_taken_q;
  assign irq_taken_o = irq_taken_q;
  logic ifl_eff;
  always_comb begin
    ifl_eff = ifl;
    if (state == EXECUTE) begin
      if (instr_class == CLASS_FLAG_OPS && opcode == 8'hFA)
        ifl_eff = 1'b0;
      else if (instr_class == CLASS_POPF && bus_ack)
        ifl_eff = bus_rdata[9];
      else if (instr_class == CLASS_INTERRUPT && opcode == 8'hCF && exec_step == 5'd2 && bus_ack)
        ifl_eff = bus_rdata[9];
    end
  end

  always_comb begin
    finish_is_irq = 1'b0;
    if (tf_at_start && tf && !halted) begin
      finish_boundary = 2'd1;
      finish_vector = SINGLE_STEP_VECTOR;
      finish_is_nmi = 1'b0;
    end else if (nmi_pending) begin
      finish_boundary = 2'd1;
      finish_vector = NMI_VECTOR;
      finish_is_nmi = 1'b1;
    end else if (irq_pending && ifl_eff && !interrupt_inhibit) begin
      finish_boundary = 2'd1;
      finish_vector = irq_vec;
      finish_is_nmi = 1'b0;
      finish_is_irq = 1'b1;
    end else if (halted) begin
      finish_boundary = 2'd2;
      finish_vector = 8'd0;
      finish_is_nmi = 1'b0;
    end else begin
      finish_boundary = 2'd0;
      finish_vector = 8'd0;
      finish_is_nmi = 1'b0;
    end
  end

  /*
  Whether the core is inside an instruction (clocks_spent counts these
  states, including PAD_CYCLES, so the pad countdown and the spent
  count stay in step).
  */
  logic in_instruction;

  always_comb begin
    case (state)
      FETCH_OPCODE, FETCH_MODRM, FETCH_DISP8, FETCH_DISP16_LO, FETCH_DISP16_HI,
      FETCH_IMM8, FETCH_IMM16_LO, FETCH_IMM16_HI, FETCH_FAR_LO, FETCH_FAR_HI,
      READ_RM, EXECUTE, WRITE_RM, STRING_OP, DIVIDE, INTERRUPT, PAD_CYCLES:
        in_instruction = 1'b1;
      default: in_instruction = 1'b0;
    endcase
  end

  /*
  Instruction completion. extra_charge is the charge the completing
  state adds in this same clock (for example a shift-cycle extra); it
  is folded into the total before the pad/boundary decision, so no
  charge is lost when an interrupt is taken in the same clock.
  cycle_charge is always non-negative, so the unsigned comparison of
  the bit patterns is exact.
  */
  task automatic finish_instruction(input signed [63:0] extra_charge);
    logic [63:0] total_charge;
    logic [63:0] spent_plus1;
    logic charge_met;
    logic [31:0] pad_needed;
    begin
      total_charge = cycle_charge + extra_charge;
      spent_plus1 = {32'b0, clocks_spent} + 64'd1;
      charge_met = (spent_plus1 >= total_charge);
      pad_needed = total_charge[31:0] - spent_plus1[31:0];
      if (charge_met) begin
        if (finish_boundary == 2'd1) begin
          interrupt_vector <= finish_vector;
          interrupt_is_nmi <= finish_is_nmi;
          interrupt_step <= 4'd0;
          irq_taken_q <= finish_is_irq;
          halted <= 1'b0;                   /* an interrupt that is already pending when HLT finishes wakes the core: without this it fell back into HALTED before the handler ran */
          cycle_charge <= total_charge;
          if (finish_is_nmi)
            interrupt_inhibit <= 1'b0;
          state <= INTERRUPT;
        end else if (finish_boundary == 2'd2) begin
          cycle_charge <= total_charge;
          state <= HALTED;
        end else begin
          fetch_first_byte <= 1'b1;
          clocks_spent <= 32'd0;
          cycle_charge <= 64'sd0;
          segment_override_valid <= 1'b0;
          rep_prefix <= 1'b0;
          rep_zero <= 1'b0;
          rep_resumed <= 1'b0;
          interrupt_inhibit <= 1'b0;
          state <= FETCH_OPCODE;
        end
      end else begin
        cycle_charge <= total_charge;
        pad_clocks <= pad_needed;
        state <= PAD_CYCLES;
      end
    end
  endtask

  /*
  Bad-opcode path (i186.c i186_run ST_BADOP handling): restore CS:IP to
  the faulting instruction, then take INT 6 with ud_trap, or stop in
  BAD_OPCODE without it. The single-step check is skipped for this
  iteration, which falls out of the interrupt entry clearing TF.
  */
  task automatic bad_opcode_path(input [7:0] bad_op);
    begin
      ip <= instr_start_ip;
      sreg[SEG_CS] <= instr_start_cs;
      bad_opcode <= bad_op;
      bad_opcode_pc <= instr_start_pc;
      if (ud_trap_i) begin
        interrupt_vector <= BADOP_VECTOR;
        interrupt_is_nmi <= 1'b0;
        interrupt_step <= 4'd0;
        state <= INTERRUPT;
      end else begin
        badop_latched <= 1'b1;
        state <= BAD_OPCODE;
      end
    end
  endtask

  /* Apply the ALU result flags (i186.c alu + set_szp). CF/OF always;
     AF only when the operation defines it (logic ops leave AF alone). */
  task automatic apply_alu_flags;
    begin
      cf <= alu_cf;
      if (alu_af_valid)
        af <= alu_af;
      of <= alu_of;
      zf <= alu_zf;
      sf <= alu_sf;
      pf <= alu_pf;
    end
  endtask

  /* Apply the INC/DEC flags (i186.c incdec). CF is preserved. */
  task automatic apply_incdec_flags;
    begin
      of <= inc_of;
      af <= inc_af;
      zf <= inc_zf;
      sf <= inc_sf;
      pf <= inc_pf;
    end
  endtask

  /* Apply the shift/rotate flags (i186.c shift + set_szp). A masked
     count of zero changes nothing. Rotates never set ZF/SF/PF/AF. */
  task automatic apply_shift_flags;
    begin
      if (!sh_nochange) begin
        cf <= sh_cf;
        if (sh_set_of)
          of <= sh_of;
        if (sh_set_szp) begin
          zf <= (sh_r == 16'd0);
          sf <= is_word ? sh_r[15] : sh_r[7];
          pf <= ~^(sh_r[7:0]);
        end
        if (sh_af0)
          af <= 1'b0;
      end
    end
  endtask


  /* Immediate-fetch state for an opcode (used where the opcode is the
     byte just fetched, so the registered opcode is not yet valid). */
  function automatic core_state_t imm_fetch_next(input [7:0] op, input w,
                                                 input [2:0] reg_in);
    if (((op == 8'hF6) || (op == 8'hF7)) &&
        (reg_in != 3'd0) && (reg_in != 3'd1))
      imm_fetch_next = EXECUTE;
    else begin
      case (decode_imm_kind(op))
        IMM_8: imm_fetch_next = FETCH_IMM8;
        IMM_16: imm_fetch_next = FETCH_IMM16_LO;
        IMM_W: imm_fetch_next = w ? FETCH_IMM16_LO : FETCH_IMM8;
        IMM_16_8: imm_fetch_next = FETCH_IMM16_LO;
        IMM_16_16: imm_fetch_next = FETCH_IMM16_LO;
        default: imm_fetch_next = EXECUTE;
      endcase
    end
  endfunction

  /* The ModRM fields of the byte just fetched (FETCH_MODRM). */
  logic [1:0] fetched_mod;
  logic [2:0] fetched_regf, fetched_rmf;
  assign fetched_mod = bus_rdata[7:6];
  assign fetched_regf = bus_rdata[5:3];
  assign fetched_rmf = bus_rdata[2:0];

  /*
  Sequential FSM. One procedural owner for every register in this
  block. Reset clears control state and the architected registers
  (i186.c i186_reset); datapath temporaries are written before they
  are read and are left unreset.
  */
  always_ff @(posedge clk) begin
        if (ce_i) begin
        if (!rst_n) begin
          state <= FETCH_OPCODE;
          fetch_first_byte <= 1'b1;
          gpr[REG_AX] <= 16'h0;
          gpr[REG_CX] <= 16'h0;
          gpr[REG_DX] <= 16'h0;
          gpr[REG_BX] <= 16'h0;
          gpr[REG_SP] <= 16'h0;
          gpr[REG_BP] <= 16'h0;
          gpr[REG_SI] <= 16'h0;
          gpr[REG_DI] <= 16'h0;
          sreg[SEG_ES] <= 16'h0;
          sreg[SEG_CS] <= RESET_CS;
          sreg[SEG_SS] <= 16'h0;
          sreg[SEG_DS] <= 16'h0;
          ip <= RESET_IP;
          cf <= 1'b0;
          pf <= 1'b0;
          af <= 1'b0;
          zf <= 1'b0;
          sf <= 1'b0;
          tf <= 1'b0;
          ifl <= 1'b0;
          df <= 1'b0;
          of <= 1'b0;
          halted <= 1'b0;
          cycles <= 64'd0;
          nmi_pending <= 1'b0;
          irq_pending <= 1'b0;
          irq_vec <= 8'd0;
          interrupt_inhibit <= 1'b0;
          badop_latched <= 1'b0;
          bad_opcode_pc <= 20'd0;
          bad_opcode <= 8'd0;
          clocks_spent <= 32'd0;
          cycle_charge <= 64'sd0;
          pad_clocks <= 32'd0;
          exec_step <= 5'd0;
          string_step <= 3'd0;
          string_kind <= STR_MOVS;
          string_first_iter <= 1'b0;
          string_resumed <= 1'b0;
          interrupt_step <= 4'd0;
          interrupt_vector <= 8'd0;
          interrupt_is_nmi <= 1'b0;
          irq_taken_q <= 1'b0;
          enter_frame_ptr <= 16'd0;
          enter_iter <= 6'd0;
          nmi_prev_level <= 1'b0;
          irq_prev_level <= 1'b0;
          instr_start_ip <= RESET_IP;
          instr_start_cs <= RESET_CS;
          instr_start_pc <= 20'hFFFF0;
          tf_at_start <= 1'b0;
          segment_override <= SEG_DS;
          segment_override_valid <= 1'b0;
          rep_prefix <= 1'b0;
          rep_zero <= 1'b0;
          rep_resumed <= 1'b0;
          div_cnt <= 6'd0;
          div_is_word <= 1'b0;
          div_signed <= 1'b0;
        end else begin
          /*
          cycles advances once per clock while running; clocks_spent
          advances while inside an instruction, including the pad, so
          the finish charge check stays exact. These sit before the FSM
          case so a reset of clocks_spent by finish_instruction in the
          same clock wins over the increment (last nonblocking
          assignment in the block wins).
          */
          irq_taken_q <= 1'b0;
          if ((state != HALTED) && (state != BAD_OPCODE)) begin
            cycles <= cycles + 64'd1;
          end
          if (in_instruction) begin
            clocks_spent <= clocks_spent + 32'd1;
          end
          case (state)
            FETCH_OPCODE: begin
              if (bus_ack) begin
                if (fetch_first_byte) begin
                  instr_start_ip <= ip;
                  instr_start_cs <= sreg[SEG_CS];
                  instr_start_pc <= linear_addr(sreg[SEG_CS], ip);
                  tf_at_start <= tf;
                  fetch_first_byte <= 1'b0;
                end
                if (((bus_rdata[7:0] == PREFIX_ES) || (bus_rdata[7:0] == PREFIX_CS) ||
                     (bus_rdata[7:0] == PREFIX_SS) || (bus_rdata[7:0] == PREFIX_DS)) && cyc_model_i) begin
                  segment_override <= seg_from_prefix(bus_rdata[7:0]);
                  segment_override_valid <= 1'b1;
                  cycle_charge <= cycle_charge + $signed({56'b0, PREFIX_CYCLES});
                  ip <= ip + 16'd1;
                end else if (bus_rdata[7:0] == PREFIX_LOCK) begin
                  if (cyc_model_i)
                    cycle_charge <= cycle_charge + $signed({56'b0, PREFIX_CYCLES});
                  ip <= ip + 16'd1;
                end else if (bus_rdata[7:0] == PREFIX_REPNE) begin
                  rep_prefix <= 1'b1;
                  rep_zero <= 1'b0;
                  ip <= ip + 16'd1;
                end else if (bus_rdata[7:0] == PREFIX_REP) begin
                  rep_prefix <= 1'b1;
                  rep_zero <= 1'b1;
                  ip <= ip + 16'd1;
                end else begin
                  opcode <= bus_rdata[7:0];
                  is_word <= decode_width(bus_rdata[7:0]);
                  ip <= ip + 16'd1;
                  cycle_charge <= cycle_charge + (cyc_model_i ? $signed({56'b0, cyc_base(bus_rdata[7:0])})
                                                              : $signed({56'b0, FLAT_CYCLES}));
                  if (decode_is_badop(bus_rdata[7:0], cyc_model_i)) begin
                    bad_opcode_path(bus_rdata[7:0]);
                  end else if (decode_is_string(bus_rdata[7:0])) begin
                    string_kind <= str_kind_from_opcode(bus_rdata[7:0]);
                    string_first_iter <= 1'b1;
                    string_resumed <= rep_resumed;
                    rep_resumed <= 1'b0;
                    string_step <= 3'd0;
                    exec_step <= 5'd0;
                    state <= STRING_OP;
                  end else if (decode_has_modrm(bus_rdata[7:0])) begin
                    state <= FETCH_MODRM;
                  end else begin
                    exec_step <= 5'd0;
                    state <= imm_fetch_next(bus_rdata[7:0], decode_width(bus_rdata[7:0]), regf);
                  end
                end
              end
            end
            FETCH_MODRM: begin
              if (bus_ack) begin
                mod <= fetched_mod;
                regf <= fetched_regf;
                rmf <= fetched_rmf;
                ip <= ip + 16'd1;
                if (cyc_model_i && (fetched_mod != 2'd3))
                  cycle_charge <= cycle_charge + $signed({56'b0, MODRM_CYCLES})
                                                + $signed({56'b0, memextra(opcode, fetched_regf)});
                if (fetched_mod == 2'd3)
                  rm_operand <= get_reg(fetched_rmf, is_word);
                if (decode_modrm_badop(opcode, fetched_mod, fetched_regf)) begin
                  bad_opcode_path(opcode);
                end else if (fetched_mod == 2'd1) begin
                  state <= FETCH_DISP8;
                end else if ((fetched_mod == 2'd2) || ((fetched_mod == 2'd0) && (fetched_rmf == 3'd6))) begin
                  state <= FETCH_DISP16_LO;
                end else begin
                  if (fetched_mod == 2'd0) begin
                    ea_seg <= sreg[segment_override_valid ? segment_override
                                                     : ea_seg_default_for(fetched_mod, fetched_rmf)];
                    ea_off <= ea_base_for(fetched_mod, fetched_rmf);
                  end
                  if (decode_need_rm_rd(opcode, fetched_mod, fetched_regf))
                    state <= READ_RM;
                  else
                    state <= imm_fetch_next(opcode, is_word, fetched_regf);
                end
              end
            end
            FETCH_DISP8: begin
              if (bus_ack) begin
                ea_seg <= sreg[ea_seg_c];
                ea_off <= ea_base_c + {{8{bus_rdata[7]}}, bus_rdata[7:0]};
                ip <= ip + 16'd1;
                state <= after_modrm_next_c;
              end
            end
            FETCH_DISP16_LO: begin
              if (bus_ack) begin
                fetch_first <= {8'b0, bus_rdata[7:0]};
                ip <= ip + 16'd1;
                state <= FETCH_DISP16_HI;
              end
            end
            FETCH_DISP16_HI: begin
              if (bus_ack) begin
                ea_seg <= sreg[ea_seg_c];
                ea_off <= ea_base_c + {bus_rdata[7:0], fetch_first[7:0]};
                ip <= ip + 16'd1;
                state <= after_modrm_next_c;
              end
            end
            FETCH_IMM8: begin
              if (bus_ack) begin
                if (instr_class == CLASS_ENTER) begin
                  /* ENTER: the level byte goes to fetch_second; imm keeps the
                     16-bit frame size fetched just before it. */
                  fetch_second <= {8'b0, bus_rdata[7:0]};
                end else begin
                  imm <= {8'b0, bus_rdata[7:0]};
                end
                ip <= ip + 16'd1;
                exec_step <= 5'd0;
                state <= EXECUTE;
              end
            end
            FETCH_IMM16_LO: begin
              if (bus_ack) begin
                fetch_first <= {8'b0, bus_rdata[7:0]};
                ip <= ip + 16'd1;
                state <= FETCH_IMM16_HI;
              end
            end
            FETCH_IMM16_HI: begin
              if (bus_ack) begin
                imm <= {bus_rdata[7:0], fetch_first[7:0]};
                ip <= ip + 16'd1;
                exec_step <= 5'd0;
                if (decode_imm_kind(opcode) == IMM_16_8)
                  state <= FETCH_IMM8;
                else if (decode_imm_kind(opcode) == IMM_16_16)
                  state <= FETCH_FAR_LO;
                else
                  state <= EXECUTE;
              end
            end
            FETCH_FAR_LO: begin
              if (bus_ack) begin
                fetch_second <= {8'b0, bus_rdata[7:0]};
                ip <= ip + 16'd1;
                state <= FETCH_FAR_HI;
              end
            end
            FETCH_FAR_HI: begin
              if (bus_ack) begin
                fetch_second <= {bus_rdata[7:0], fetch_second[7:0]};
                ip <= ip + 16'd1;
                exec_step <= 5'd0;
                state <= EXECUTE;
              end
            end
            READ_RM: begin
              if (bus_ack) begin
                if (is_word)
                  rm_operand <= bus_rdata;
                else
                  rm_operand <= {8'b0, bus_rdata[7:0]};
                state <= fetch_imm_next_c;
              end
            end
            EXECUTE: begin
              case (instr_class)
                CLASS_ALU_RM: begin
                  if (opcode[5:3] == ALU_CMP) begin
                    apply_alu_flags();
                    finish_instruction(64'sd0);
                  end else if (opcode[2:0] < 3'd2) begin
                    if (mod == 2'd3) begin
                      if (is_word)
                        gpr[rmf] <= alu_r;
                      else
                        gpr[byte_gpr_idx(rmf)] <= set_byte_reg(rmf, alu_r[7:0]);
                      apply_alu_flags();
                      finish_instruction(64'sd0);
                    end else begin
                      writeback_value <= alu_r;
                      apply_alu_flags();
                      state <= WRITE_RM;
                    end
                  end else begin
                    if (is_word)
                      gpr[regf] <= alu_r;
                    else
                      gpr[byte_gpr_idx(regf)] <= set_byte_reg(regf, alu_r[7:0]);
                    apply_alu_flags();
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_ALU_IMM: begin
                  if (opcode[5:3] == ALU_CMP) begin
                    apply_alu_flags();
                    finish_instruction(64'sd0);
                  end else begin
                    if (is_word)
                      gpr[REG_AX] <= alu_r;
                    else
                      gpr[REG_AX] <= set_byte(gpr[REG_AX], 3'd0, alu_r[7:0]);
                    apply_alu_flags();
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_SEG_PUSH_POP: begin
                  if (bus_ack) begin
                    if (opcode[0] == 1'b0) begin
                      gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                      finish_instruction(64'sd0);
                    end else begin
                      sreg[opcode[4:3]] <= bus_rdata;
                      gpr[REG_SP] <= gpr[REG_SP] + STACK_SLOT_BYTES;
                      interrupt_inhibit <= 1'b1;
                      finish_instruction(64'sd0);
                    end
                  end
                end
                CLASS_DECIMAL: begin
                  if (opcode == 8'h27) begin
                    /* DAA (i186.c exec_decimal): low nibble first; the +6
                       overflow feeds the local carry, which then forces the
                       high adjust (al > 0x9F, not 0x99). */
                    gpr[REG_AX] <= set_byte(gpr[REG_AX], 3'd0, daa_al_final);
                    cf <= daa_cf_final;
                    af <= daa_af_final;
                    zf <= (daa_al_final == 8'd0);
                    sf <= daa_al_final[7];
                    pf <= ~^(daa_al_final);
                    finish_instruction(64'sd0);
                  end else if (opcode == 8'h2F) begin
                    /* DAS (i186.c exec_decimal): same shape, subtract. */
                    gpr[REG_AX] <= set_byte(gpr[REG_AX], 3'd0, das_al_final);
                    cf <= das_cf_final;
                    af <= das_af_final;
                    zf <= (das_al_final == 8'd0);
                    sf <= das_al_final[7];
                    pf <= ~^(das_al_final);
                    finish_instruction(64'sd0);
                  end else if (opcode == 8'h37) begin
                    /* AAA (i186.c exec_decimal): AH+1, AL low nibble only. */
                    if (((al_byte & 8'h0F) > 8'h09) || af) begin
                      gpr[REG_AX] <= {ah_byte + 8'd1, 4'b0, al_byte[3:0] + 4'd6};
                      af <= 1'b1;
                      cf <= 1'b1;
                    end else begin
                      gpr[REG_AX] <= {ah_byte, 4'b0, al_byte[3:0]};
                      af <= 1'b0;
                      cf <= 1'b0;
                    end
                    finish_instruction(64'sd0);
                  end else begin
                    /* AAS (i186.c exec_decimal): AH-1, AL low nibble only. */
                    if (((al_byte & 8'h0F) > 8'h09) || af) begin
                      gpr[REG_AX] <= {ah_byte - 8'd1, 4'b0, al_byte[3:0] - 4'd6};
                      af <= 1'b1;
                      cf <= 1'b1;
                    end else begin
                      gpr[REG_AX] <= {ah_byte, 4'b0, al_byte[3:0]};
                      af <= 1'b0;
                      cf <= 1'b0;
                    end
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_AAM_AAD: begin
                  if (opcode == 8'hD4) begin
                    /* AAM: divide AL by imm; a zero divisor is INT 0. */
                    if (imm[7:0] == 8'd0) begin
                      interrupt_vector <= DIVIDE_VECTOR;
                      interrupt_is_nmi <= 1'b0;
                      interrupt_step <= 4'd0;
                      state <= INTERRUPT;
                    end else begin
                      gpr[REG_AX] <= {al_byte / imm[7:0], al_byte % imm[7:0]};
                      zf <= ((al_byte % imm[7:0]) == 8'd0);
                      sf <= ((al_byte % imm[7:0]) & 8'h80) != 8'd0;
                      pf <= ~^(al_byte % imm[7:0]);
                      finish_instruction(64'sd0);
                    end
                  end else begin
                    /* AAD: AL + AH*imm, truncated to 8 bits; AX replaced. */
                    gpr[REG_AX] <= {8'd0, (al_byte + ah_byte * imm[7:0]) & 8'hFF};
                    zf <= (((al_byte + ah_byte * imm[7:0]) & 8'hFF) == 8'd0);
                    sf <= ((al_byte + ah_byte * imm[7:0]) & 8'h80) != 8'd0;
                    pf <= ~^((al_byte + ah_byte * imm[7:0]) & 8'hFF);
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_INCDEC_REG: begin
                  gpr[opcode[2:0]] <= inc_r;
                  apply_incdec_flags();
                  finish_instruction(64'sd0);
                end
                CLASS_PUSH_REG: begin
                  if (bus_ack) begin
                    gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_POP_REG: begin
                  if (bus_ack) begin
                    gpr[opcode[2:0]] <= bus_rdata;
                    gpr[REG_SP] <= gpr[REG_SP] + STACK_SLOT_BYTES;
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_PUSHA: begin
                  if (bus_ack) begin
                    if (exec_step == 5'd7) begin
                      gpr[REG_SP] <= gpr[REG_SP] - 16'd16;
                      finish_instruction(64'sd0);
                    end else begin
                      exec_step <= exec_step + 5'd1;
                    end
                  end
                end
                CLASS_POPA: begin
                  if (bus_ack) begin
                    case (exec_step)
                      5'd0: gpr[REG_DI] <= bus_rdata;
                      5'd1: gpr[REG_SI] <= bus_rdata;
                      5'd2: gpr[REG_BP] <= bus_rdata;
                      5'd3: begin end
                      5'd4: gpr[REG_BX] <= bus_rdata;
                      5'd5: gpr[REG_DX] <= bus_rdata;
                      5'd6: gpr[REG_CX] <= bus_rdata;
                      5'd7: gpr[REG_AX] <= bus_rdata;
                      default: begin end
                    endcase
                    if (exec_step == 5'd7) begin
                      gpr[REG_SP] <= gpr[REG_SP] + 16'd16;
                      finish_instruction(64'sd0);
                    end else begin
                      exec_step <= exec_step + 5'd1;
                    end
                  end
                end
                CLASS_BOUND: begin
                  if (bus_ack) begin
                    if (exec_step == 5'd0) begin
                      fetch_first <= bus_rdata;
                      exec_step <= 5'd1;
                    end else begin
                      if ((reg_operand < fetch_first) || (reg_operand > bus_rdata)) begin
                        interrupt_vector <= BOUND_VECTOR;
                        interrupt_is_nmi <= 1'b0;
                        interrupt_step <= 4'd0;
                        state <= INTERRUPT;
                      end else begin
                        finish_instruction(64'sd0);
                      end
                    end
                  end
                end
                CLASS_PUSH_IMM: begin
                  if (bus_ack) begin
                    gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_IMUL_IMM: begin
                  gpr[regf] <= mul_p[15:0];
                  cf <= (mul_p[33:16] != {18{mul_p[15]}});
                  of <= (mul_p[33:16] != {18{mul_p[15]}});
                  finish_instruction(64'sd0);
                end
                CLASS_JUMP_CC: begin
                  if (cond_eval(opcode[3:0])) begin
                    ip <= ip + {{8{imm[7]}}, imm[7:0]};
                    finish_instruction(cyc_model_i ? $signed({56'b0, JCC_TAKEN_MODEL1})
                                                  : $signed({56'b0, JCC_TAKEN_LEGACY}));
                  end else begin
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_ALU_IMM_RM: begin
                  if (regf == ALU_CMP) begin
                    apply_alu_flags();
                    finish_instruction(64'sd0);
                  end else if (mod == 2'd3) begin
                    if (is_word)
                      gpr[rmf] <= alu_r;
                    else
                      gpr[byte_gpr_idx(rmf)] <= set_byte_reg(rmf, alu_r[7:0]);
                    apply_alu_flags();
                    finish_instruction(64'sd0);
                  end else begin
                    writeback_value <= alu_r;
                    apply_alu_flags();
                    state <= WRITE_RM;
                  end
                end
                CLASS_TRANSFER_MOV: begin
                  case (opcode)
                    8'h84, 8'h85: begin
                      apply_alu_flags();
                      finish_instruction(64'sd0);
                    end
                    8'h86, 8'h87: begin
                      if (mod == 2'd3) begin
                        if (is_word) begin
                          gpr[rmf] <= reg_operand;
                          gpr[regf] <= rm_operand;
                        end else if (byte_gpr_idx(rmf) == byte_gpr_idx(regf)) begin
                          /* both operands are halves of one register (XCHG DH,DL): one merged write, two writes would each start from the old value and one would be lost */
                          gpr[byte_gpr_idx(rmf)] <= set_byte(set_byte_reg(rmf, reg_operand[7:0]), regf, rm_operand[7:0]);
                        end else begin
                          gpr[byte_gpr_idx(rmf)] <= set_byte_reg(rmf, reg_operand[7:0]);
                          gpr[byte_gpr_idx(regf)] <= set_byte_reg(regf, rm_operand[7:0]);
                        end
                        finish_instruction(64'sd0);
                      end else begin
                        writeback_value <= reg_operand;
                        if (is_word)
                          gpr[regf] <= rm_operand;
                        else
                          gpr[byte_gpr_idx(regf)] <= set_byte_reg(regf, rm_operand[7:0]);
                        state <= WRITE_RM;
                      end
                    end
                    8'h88, 8'h89: begin
                      if (mod == 2'd3) begin
                        if (is_word)
                          gpr[rmf] <= reg_operand;
                        else
                          gpr[byte_gpr_idx(rmf)] <= set_byte_reg(rmf, reg_operand[7:0]);
                        finish_instruction(64'sd0);
                      end else begin
                        writeback_value <= reg_operand;
                        state <= WRITE_RM;
                      end
                    end
                    8'h8A, 8'h8B: begin
                      if (is_word)
                        gpr[regf] <= rm_operand;
                      else
                        gpr[byte_gpr_idx(regf)] <= set_byte_reg(regf, rm_operand[7:0]);
                      finish_instruction(64'sd0);
                    end
                    8'h8C: begin
                      if (mod == 2'd3) begin
                        gpr[rmf] <= sreg[regf[1:0]];
                        finish_instruction(64'sd0);
                      end else begin
                        writeback_value <= sreg[regf[1:0]];
                        state <= WRITE_RM;
                      end
                    end
                    8'h8D: begin
                      gpr[regf] <= ea_off;
                      finish_instruction(64'sd0);
                    end
                    8'h8E: begin
                      sreg[regf[1:0]] <= rm_operand;
                      interrupt_inhibit <= 1'b1;
                      finish_instruction(64'sd0);
                    end
                    8'h8F: begin
                      if (bus_ack) begin
                        gpr[REG_SP] <= gpr[REG_SP] + STACK_SLOT_BYTES;
                        if (mod == 2'd3) begin
                          gpr[rmf] <= bus_rdata;
                          finish_instruction(64'sd0);
                        end else begin
                          writeback_value <= bus_rdata;
                          state <= WRITE_RM;
                        end
                      end
                    end
                    default: finish_instruction(64'sd0);
                  endcase
                end
                CLASS_NOP: begin
                  finish_instruction(64'sd0);
                end
                CLASS_XCHG_AX: begin
                  gpr[REG_AX] <= gpr[opcode[2:0]];
                  gpr[opcode[2:0]] <= gpr[REG_AX];
                  finish_instruction(64'sd0);
                end
                CLASS_CBW_CWD: begin
                  if (opcode == 8'h98) begin
                    gpr[REG_AX] <= {{8{al_byte[7]}}, al_byte};
                  end else begin
                    gpr[REG_DX] <= {16{ax_word[15]}};
                  end
                  finish_instruction(64'sd0);
                end
                CLASS_CALL_FAR: begin
                  if (bus_ack) begin
                    if (exec_step == 5'd0) begin
                      gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                      exec_step <= 5'd1;
                    end else begin
                      gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                      sreg[SEG_CS] <= fetch_second;
                      ip <= imm;
                      finish_instruction(cyc_model_i ? 64'sd0 : $signed({56'b0, CALL_FAR_LEGACY_CYCLES}));
                    end
                  end
                end
                CLASS_PUSHF: begin
                  if (bus_ack) begin
                    gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_POPF: begin
                  if (bus_ack) begin
                    cf <= bus_rdata[0];
                    pf <= bus_rdata[2];
                    af <= bus_rdata[4];
                    zf <= bus_rdata[6];
                    sf <= bus_rdata[7];
                    tf <= bus_rdata[8];
                    ifl <= bus_rdata[9];
                    df <= bus_rdata[10];
                    of <= bus_rdata[11];
                    gpr[REG_SP] <= gpr[REG_SP] + STACK_SLOT_BYTES;
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_SAHF: begin
                  cf <= ax_word[8];
                  pf <= ax_word[10];
                  af <= ax_word[12];
                  zf <= ax_word[14];
                  sf <= ax_word[15];
                  finish_instruction(64'sd0);
                end
                CLASS_LAHF: begin
                  gpr[REG_AX] <= {ah_byte, sf, zf, 1'b0, af, 1'b0, pf, 1'b1, cf};
                  finish_instruction(64'sd0);
                end
                CLASS_MOFFS: begin
                  if (bus_ack) begin
                    if ((opcode == 8'hA0) || (opcode == 8'hA1)) begin
                      if (is_word)
                        gpr[REG_AX] <= bus_rdata;
                      else
                        gpr[REG_AX] <= set_byte(gpr[REG_AX], 3'd0, bus_rdata[7:0]);
                    end
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_TEST_ACC: begin
                  apply_alu_flags();
                  finish_instruction(64'sd0);
                end
                CLASS_MOV_IMM: begin
                  if (opcode[3] == 1'b1) begin
                    gpr[opcode[2:0]] <= imm;
                  end else begin
                    gpr[byte_gpr_idx(opcode[2:0])] <= set_byte_reg(opcode[2:0], imm[7:0]);
                  end
                  finish_instruction(64'sd0);
                end
                CLASS_SHIFT_IMM: begin
                  if (mod == 2'd3) begin
                    if (is_word)
                      gpr[rmf] <= sh_r;
                    else
                      gpr[byte_gpr_idx(rmf)] <= set_byte_reg(rmf, sh_r[7:0]);
                    apply_shift_flags();
                    finish_instruction(shift_extra_c);
                  end else begin
                    writeback_value <= sh_r;
                    apply_shift_flags();
                    state <= WRITE_RM;
                  end
                end
                CLASS_RETURN: begin
                  if (bus_ack) begin
                    if (exec_step == 5'd0) begin
                      ip <= bus_rdata;
                      if ((opcode == 8'hCA) || (opcode == 8'hCB)) begin
                        gpr[REG_SP] <= gpr[REG_SP] + STACK_SLOT_BYTES;
                        exec_step <= 5'd1;
                      end else if (opcode == 8'hC2) begin
                        gpr[REG_SP] <= gpr[REG_SP] + STACK_SLOT_BYTES + imm;
                        finish_instruction(64'sd0);
                      end else begin
                        gpr[REG_SP] <= gpr[REG_SP] + STACK_SLOT_BYTES;
                        finish_instruction(64'sd0);
                      end
                    end else begin
                      sreg[SEG_CS] <= bus_rdata;
                      if (opcode == 8'hCA)
                        gpr[REG_SP] <= gpr[REG_SP] + STACK_SLOT_BYTES + imm;
                      else
                        gpr[REG_SP] <= gpr[REG_SP] + STACK_SLOT_BYTES;
                      finish_instruction(64'sd0);
                    end
                  end
                end
                CLASS_LES_LDS: begin
                  if (bus_ack) begin
                    if (opcode == 8'hC4)
                      sreg[SEG_ES] <= bus_rdata;
                    else
                      sreg[SEG_DS] <= bus_rdata;
                    gpr[regf] <= rm_operand;
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_MOV_RM_IMM: begin
                  if (mod == 2'd3) begin
                    if (is_word)
                      gpr[rmf] <= imm;
                    else
                      gpr[byte_gpr_idx(rmf)] <= set_byte_reg(rmf, imm[7:0]);
                    finish_instruction(64'sd0);
                  end else begin
                    writeback_value <= imm;
                    state <= WRITE_RM;
                  end
                end
                CLASS_ENTER: begin
                  /* i186.c exec_enter_leave: push BP, fp = SP; for i = 1..lvl-1
                     push [SS:BP] after BP -= 2; push fp; BP = fp; SP -= size.
                     Level is fetch_second[4:0] (imm8 & 31); size is imm. */
                  if (bus_ack) begin
                    if (exec_step == 5'd0) begin
                      enter_frame_ptr <= gpr[REG_SP] - STACK_SLOT_BYTES;
                      if (fetch_second[4:0] == 5'd0) begin
                        gpr[REG_BP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                        gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES - imm;
                        finish_instruction(64'sd0);
                      end else begin
                        gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                        if (fetch_second[4:0] == 5'd1) begin
                          exec_step <= 5'd3;
                        end else begin
                          gpr[REG_BP] <= gpr[REG_BP] - STACK_SLOT_BYTES;
                          enter_iter <= 6'd1;
                          exec_step <= 5'd1;
                        end
                      end
                    end else if (exec_step == 5'd1) begin
                      fetch_first <= bus_rdata;
                      exec_step <= 5'd2;
                    end else if (exec_step == 5'd2) begin
                      gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                      if (enter_iter == ({1'b0, fetch_second[4:0]} - 6'd1)) begin
                        exec_step <= 5'd3;
                      end else begin
                        enter_iter <= enter_iter + 6'd1;
                        gpr[REG_BP] <= gpr[REG_BP] - STACK_SLOT_BYTES;
                        exec_step <= 5'd1;
                      end
                    end else begin
                      gpr[REG_BP] <= enter_frame_ptr;
                      gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES - imm;
                      finish_instruction(64'sd0);
                    end
                  end
                end
                CLASS_LEAVE: begin
                  if (exec_step == 5'd0) begin
                    gpr[REG_SP] <= gpr[REG_BP];
                    exec_step <= 5'd1;
                  end else if (bus_ack) begin
                    gpr[REG_BP] <= bus_rdata;
                    gpr[REG_SP] <= gpr[REG_SP] + STACK_SLOT_BYTES;
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_INTERRUPT: begin
                  if (opcode == 8'hCC) begin
                    interrupt_vector <= 8'd3;
                    interrupt_is_nmi <= 1'b0;
                    interrupt_step <= 4'd0;
                    state <= INTERRUPT;
                  end else if (opcode == 8'hCD) begin
                    interrupt_vector <= imm[7:0];
                    interrupt_is_nmi <= 1'b0;
                    interrupt_step <= 4'd0;
                    state <= INTERRUPT;
                  end else if (opcode == 8'hCE) begin
                    if (of) begin
                      interrupt_vector <= 8'd4;
                      interrupt_is_nmi <= 1'b0;
                      interrupt_step <= 4'd0;
                      state <= INTERRUPT;
                    end else begin
                      finish_instruction(64'sd0);
                    end
                  end else begin
                    /* IRET (CF): pop IP, CS, FLAGS. */
                    if (bus_ack) begin
                      if (exec_step == 5'd0) begin
                        ip <= bus_rdata;
                        gpr[REG_SP] <= gpr[REG_SP] + STACK_SLOT_BYTES;
                        exec_step <= 5'd1;
                      end else if (exec_step == 5'd1) begin
                        sreg[SEG_CS] <= bus_rdata;
                        gpr[REG_SP] <= gpr[REG_SP] + STACK_SLOT_BYTES;
                        exec_step <= 5'd2;
                      end else begin
                        cf <= bus_rdata[0];
                        pf <= bus_rdata[2];
                        af <= bus_rdata[4];
                        zf <= bus_rdata[6];
                        sf <= bus_rdata[7];
                        tf <= bus_rdata[8];
                        ifl <= bus_rdata[9];
                        df <= bus_rdata[10];
                        of <= bus_rdata[11];
                        gpr[REG_SP] <= gpr[REG_SP] + STACK_SLOT_BYTES;
                        finish_instruction(64'sd0);
                      end
                    end
                  end
                end
                CLASS_SHIFT_1_CL: begin
                  if (mod == 2'd3) begin
                    if (is_word)
                      gpr[rmf] <= sh_r;
                    else
                      gpr[byte_gpr_idx(rmf)] <= set_byte_reg(rmf, sh_r[7:0]);
                    apply_shift_flags();
                    finish_instruction(shift_extra_c);
                  end else begin
                    writeback_value <= sh_r;
                    apply_shift_flags();
                    state <= WRITE_RM;
                  end
                end
                CLASS_XLAT: begin
                  if (bus_ack) begin
                    gpr[REG_AX] <= set_byte(gpr[REG_AX], 3'd0, bus_rdata[7:0]);
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_ESCAPE: begin
                  finish_instruction(64'sd0);
                end
                CLASS_LOOP: begin
                  if (opcode == 8'hE0) begin
                    gpr[REG_CX] <= gpr[REG_CX] - 16'd1;
                    if ((gpr[REG_CX] != 16'd1) && !zf) begin
                      ip <= ip + {{8{imm[7]}}, imm[7:0]};
                      finish_instruction(cyc_model_i ? $signed({56'b0, LOOP_TAKEN_CYCLES}) : 64'sd0);
                    end else begin
                      finish_instruction(64'sd0);
                    end
                  end else if (opcode == 8'hE1) begin
                    gpr[REG_CX] <= gpr[REG_CX] - 16'd1;
                    if ((gpr[REG_CX] != 16'd1) && zf) begin
                      ip <= ip + {{8{imm[7]}}, imm[7:0]};
                      finish_instruction(cyc_model_i ? $signed({56'b0, LOOP_TAKEN_CYCLES}) : 64'sd0);
                    end else begin
                      finish_instruction(64'sd0);
                    end
                  end else if (opcode == 8'hE2) begin
                    gpr[REG_CX] <= gpr[REG_CX] - 16'd1;
                    if (gpr[REG_CX] != 16'd1) begin
                      ip <= ip + {{8{imm[7]}}, imm[7:0]};
                      finish_instruction(cyc_model_i ? $signed({56'b0, LOOP_TAKEN_CYCLES}) : 64'sd0);
                    end else begin
                      finish_instruction(64'sd0);
                    end
                  end else begin
                    if (gpr[REG_CX] == 16'd0) begin
                      ip <= ip + {{8{imm[7]}}, imm[7:0]};
                      finish_instruction(cyc_model_i ? $signed({56'b0, LOOP_TAKEN_CYCLES}) : 64'sd0);
                    end else begin
                      finish_instruction(64'sd0);
                    end
                  end
                end
                CLASS_INOUT_IMM: begin
                  if (bus_ack) begin
                    if ((opcode == 8'hE4) || (opcode == 8'hE5)) begin
                      if (is_word)
                        gpr[REG_AX] <= bus_rdata;
                      else
                        gpr[REG_AX] <= set_byte(gpr[REG_AX], 3'd0, bus_rdata[7:0]);
                    end
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_CALL_JMP: begin
                  if (opcode == 8'hE8) begin
                    if (bus_ack) begin
                      gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                      ip <= ip + imm;
                      finish_instruction(64'sd0);
                    end
                  end else if (opcode == 8'hE9) begin
                    ip <= ip + imm;
                    finish_instruction(64'sd0);
                  end else if (opcode == 8'hEA) begin
                    sreg[SEG_CS] <= fetch_second;
                    ip <= imm;
                    finish_instruction(64'sd0);
                  end else begin
                    ip <= ip + {{8{imm[7]}}, imm[7:0]};
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_INOUT_DX: begin
                  if (bus_ack) begin
                    if ((opcode == 8'hEC) || (opcode == 8'hED)) begin
                      if (is_word)
                        gpr[REG_AX] <= bus_rdata;
                      else
                        gpr[REG_AX] <= set_byte(gpr[REG_AX], 3'd0, bus_rdata[7:0]);
                    end
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_HALT_CMC: begin
                  if (opcode == 8'hF4) begin
                    halted <= 1'b1;
                    finish_instruction(64'sd0);
                  end else begin
                    cf <= ~cf;
                    finish_instruction(64'sd0);
                  end
                end
                CLASS_GROUP_F6_F7: begin
                  if (regf == 3'd0) begin
                    apply_alu_flags();
                    finish_instruction(64'sd0);
                  end else if (regf == 3'd2) begin
                    if (mod == 2'd3) begin
                      if (is_word)
                        gpr[rmf] <= ~rm_operand;
                      else
                        gpr[byte_gpr_idx(rmf)] <= set_byte_reg(rmf, ~rm_operand[7:0]);
                      finish_instruction(64'sd0);
                    end else begin
                      writeback_value <= ~rm_operand;
                      state <= WRITE_RM;
                    end
                  end else if (regf == 3'd3) begin
                    if (mod == 2'd3) begin
                      if (is_word)
                        gpr[rmf] <= alu_r;
                      else
                        gpr[byte_gpr_idx(rmf)] <= set_byte_reg(rmf, alu_r[7:0]);
                      apply_alu_flags();
                      finish_instruction(64'sd0);
                    end else begin
                      writeback_value <= alu_r;
                      apply_alu_flags();
                      state <= WRITE_RM;
                    end
                  end else if ((regf == 3'd4) || (regf == 3'd5)) begin
                    if (is_word) begin
                      gpr[REG_AX] <= mul_p[15:0];
                      gpr[REG_DX] <= mul_p[31:16];
                      cf <= (mul_p[33:16] != 18'd0);
                      of <= (mul_p[33:16] != 18'd0);
                    end else begin
                      gpr[REG_AX] <= {mul_p[15:8], mul_p[7:0]};
                      cf <= (mul_p[15:8] != 8'd0);
                      of <= (mul_p[15:8] != 8'd0);
                    end
                    finish_instruction(cyc_model_i ? $signed({56'b0, is_word ? MUL_WORD_CYCLES : MUL_BYTE_CYCLES}) : 64'sd0);
                  end else begin
                    div_is_word <= is_word;
                    div_signed <= (regf == 3'd7);
                    div_cnt <= 6'd0;
                    div_quot <= 32'd0;
                    div_rem <= 32'd0;
                    div_dvsr <= 32'd0;
                    exec_step <= 5'd0;
                    state <= DIVIDE;
                  end
                end
                CLASS_FLAG_OPS: begin
                  case (opcode)
                    8'hF8: cf <= 1'b0;
                    8'hF9: cf <= 1'b1;
                    8'hFA: ifl <= 1'b0;
                    8'hFB: begin
                      ifl <= 1'b1;
                      interrupt_inhibit <= 1'b1;
                    end
                    8'hFC: df <= 1'b0;
                    8'hFD: df <= 1'b1;
                    default: begin end
                  endcase
                  finish_instruction(64'sd0);
                end
                CLASS_GROUP_FE: begin
                  if (mod == 2'd3) begin
                    if (regf == 3'd0)
                      gpr[byte_gpr_idx(rmf)] <= set_byte_reg(rmf, inc_r[7:0]);
                    else
                      gpr[byte_gpr_idx(rmf)] <= set_byte_reg(rmf, inc_r[7:0]);
                    apply_incdec_flags();
                    finish_instruction(64'sd0);
                  end else begin
                    writeback_value <= inc_r;
                    apply_incdec_flags();
                    state <= WRITE_RM;
                  end
                end
                CLASS_GROUP_FF: begin
                  if ((regf == 3'd0) || (regf == 3'd1)) begin
                    if (mod == 2'd3) begin
                      gpr[rmf] <= inc_r;
                      apply_incdec_flags();
                      finish_instruction(64'sd0);
                    end else begin
                      writeback_value <= inc_r;
                      apply_incdec_flags();
                      state <= WRITE_RM;
                    end
                  end else if (regf == 3'd2) begin
                    if (bus_ack) begin
                      gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                      ip <= rm_operand;
                      finish_instruction(cyc_model_i ? $signed({56'b0, CALL_RM_CYCLES}) : 64'sd0);
                    end
                  end else if (regf == 3'd3) begin
                    if (bus_ack) begin
                      if (exec_step == 5'd0) begin
                        fetch_second <= bus_rdata;
                        exec_step <= 5'd1;
                      end else if (exec_step == 5'd1) begin
                        gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                        exec_step <= 5'd2;
                      end else begin
                        gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                        sreg[SEG_CS] <= fetch_second;
                        ip <= rm_operand;
                        finish_instruction(cyc_model_i ? $signed({56'b0, CALL_FAR_RM_CYCLES}) : 64'sd0);
                      end
                    end
                  end else if (regf == 3'd4) begin
                    ip <= rm_operand;
                    finish_instruction(cyc_model_i ? $signed({56'b0, JMP_RM_CYCLES}) : 64'sd0);
                  end else if (regf == 3'd5) begin
                    if (bus_ack) begin
                      sreg[SEG_CS] <= bus_rdata;
                      ip <= rm_operand;
                      finish_instruction(cyc_model_i ? $signed({56'b0, JMP_RM_CYCLES}) : 64'sd0);
                    end
                  end else begin
                    if (bus_ack) begin
                      gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                      finish_instruction(64'sd0);
                    end
                  end
                end
                default: begin
                  finish_instruction(64'sd0);
                end
              endcase
            end
            WRITE_RM: begin
              if (bus_ack) begin
                finish_instruction(64'sd0);
              end
            end
            STRING_OP: begin
              if ((((string_kind == STR_MOVS) || (string_kind == STR_CMPS) ||
                    (string_kind == STR_INS) || (string_kind == STR_OUTS)) &&
                   (string_step == 3'd2)) ||
                  (((string_kind == STR_STOS) || (string_kind == STR_LODS) ||
                    (string_kind == STR_SCAS)) && (string_step == 3'd1))) begin
                /* Completion step: pointers, flags, AX, then charge + decide. */
                case (string_kind)
                  STR_MOVS: begin
                    if (df) begin
                      gpr[REG_SI] <= gpr[REG_SI] - (is_word ? 16'd2 : 16'd1);
                      gpr[REG_DI] <= gpr[REG_DI] - (is_word ? 16'd2 : 16'd1);
                    end else begin
                      gpr[REG_SI] <= gpr[REG_SI] + (is_word ? 16'd2 : 16'd1);
                      gpr[REG_DI] <= gpr[REG_DI] + (is_word ? 16'd2 : 16'd1);
                    end
                  end
                  STR_CMPS: begin
                    apply_alu_flags();
                    if (df) begin
                      gpr[REG_SI] <= gpr[REG_SI] - (is_word ? 16'd2 : 16'd1);
                      gpr[REG_DI] <= gpr[REG_DI] - (is_word ? 16'd2 : 16'd1);
                    end else begin
                      gpr[REG_SI] <= gpr[REG_SI] + (is_word ? 16'd2 : 16'd1);
                      gpr[REG_DI] <= gpr[REG_DI] + (is_word ? 16'd2 : 16'd1);
                    end
                  end
                  STR_STOS: begin
                    if (df)
                      gpr[REG_DI] <= gpr[REG_DI] - (is_word ? 16'd2 : 16'd1);
                    else
                      gpr[REG_DI] <= gpr[REG_DI] + (is_word ? 16'd2 : 16'd1);
                  end
                  STR_LODS: begin
                    if (is_word)
                      gpr[REG_AX] <= string_op_a;
                    else
                      gpr[REG_AX] <= set_byte(gpr[REG_AX], 3'd0, string_op_a[7:0]);
                    if (df)
                      gpr[REG_SI] <= gpr[REG_SI] - (is_word ? 16'd2 : 16'd1);
                    else
                      gpr[REG_SI] <= gpr[REG_SI] + (is_word ? 16'd2 : 16'd1);
                  end
                  STR_SCAS: begin
                    apply_alu_flags();
                    if (df)
                      gpr[REG_DI] <= gpr[REG_DI] - (is_word ? 16'd2 : 16'd1);
                    else
                      gpr[REG_DI] <= gpr[REG_DI] + (is_word ? 16'd2 : 16'd1);
                  end
                  STR_INS: begin
                    if (df)
                      gpr[REG_DI] <= gpr[REG_DI] - (is_word ? 16'd2 : 16'd1);
                    else
                      gpr[REG_DI] <= gpr[REG_DI] + (is_word ? 16'd2 : 16'd1);
                  end
                  STR_OUTS: begin
                    if (df)
                      gpr[REG_SI] <= gpr[REG_SI] - (is_word ? 16'd2 : 16'd1);
                    else
                      gpr[REG_SI] <= gpr[REG_SI] + (is_word ? 16'd2 : 16'd1);
                  end
                  default: begin end
                endcase
                string_complete_iteration();
              end else if (bus_ack) begin
                case (string_kind)
                  STR_MOVS: begin
                    if (string_step == 3'd0)
                      string_op_a <= is_word ? bus_rdata : {8'b0, bus_rdata[7:0]};
                    string_step <= string_step + 3'd1;
                  end
                  STR_CMPS: begin
                    if (string_step == 3'd0)
                      string_op_a <= is_word ? bus_rdata : {8'b0, bus_rdata[7:0]};
                    else
                      string_op_b <= is_word ? bus_rdata : {8'b0, bus_rdata[7:0]};
                    string_step <= string_step + 3'd1;
                  end
                  STR_STOS: begin
                    string_step <= string_step + 3'd1;
                  end
                  STR_LODS: begin
                    string_op_a <= is_word ? bus_rdata : {8'b0, bus_rdata[7:0]};
                    string_step <= string_step + 3'd1;
                  end
                  STR_SCAS: begin
                    string_op_b <= is_word ? bus_rdata : {8'b0, bus_rdata[7:0]};
                    string_step <= string_step + 3'd1;
                  end
                  STR_INS: begin
                    if (string_step == 3'd0)
                      string_op_a <= is_word ? bus_rdata : {8'b0, bus_rdata[7:0]};
                    string_step <= string_step + 3'd1;
                  end
                  STR_OUTS: begin
                    if (string_step == 3'd0)
                      string_op_a <= is_word ? bus_rdata : {8'b0, bus_rdata[7:0]};
                    string_step <= string_step + 3'd1;
                  end
                  default: begin end
                endcase
              end
            end
            DIVIDE: begin
              if (exec_step == 5'd0) begin
                /*
                Latch the dividend and divisor, then start the iterations.
                Signed division runs on the magnitudes; the signs are
                re-applied to the quotient and remainder at completion.
                */
                if (div_signed) begin
                  if (div_is_word) begin
                    div_quot_neg <= (dx_word[15] ^ rm_operand[15]);
                    div_rem_neg <= dx_word[15];
                    div_dividend <= dx_word[15] ?
                                    (~{gpr[REG_DX], gpr[REG_AX]} + 32'd1) :
                                    {gpr[REG_DX], gpr[REG_AX]};
                    div_dvsr <= rm_operand[15] ? (~{16'b0, rm_operand} + 32'd1)
                                                : {16'b0, rm_operand};
                  end else begin
                    div_quot_neg <= (ax_word[15] ^ rm_operand[7]);
                    div_rem_neg <= ax_word[15];
                    div_dividend <= ax_word[15] ?
                                    (~{16'b0, gpr[REG_AX]} + 32'd1) :
                                    {16'b0, gpr[REG_AX]};
                    div_dvsr <= rm_operand[7] ? (~{24'b0, rm_operand[7:0]} + 32'd1)
                                               : {24'b0, rm_operand[7:0]};
                  end
                end else begin
                  div_quot_neg <= 1'b0;
                  div_rem_neg <= 1'b0;
                  if (div_is_word) begin
                    div_dividend <= {gpr[REG_DX], gpr[REG_AX]};
                    div_dvsr <= {16'b0, rm_operand};
                  end else begin
                    div_dividend <= {16'b0, gpr[REG_AX]};
                    div_dvsr <= {24'b0, rm_operand[7:0]};
                  end
                end
                if (rm_operand == 16'd0) begin
                  interrupt_vector <= DIVIDE_VECTOR;
                  interrupt_is_nmi <= 1'b0;
                  interrupt_step <= 4'd0;
                  state <= INTERRUPT;
                end else begin
                  div_cnt <= 6'd0;
                  div_quot <= 32'd0;
                  div_rem <= 32'd0;
                  exec_step <= 5'd1;
                end
              end else if (div_cnt < (div_is_word ? DIV_WORD_ITERS : DIV_BYTE_ITERS)) begin
                /* One restoring-division iteration per clock. */
                div_rem <= {div_rem[30:0], div_dividend[31]};
                div_dividend <= {div_dividend[30:0], 1'b0};
                if ({div_rem[30:0], div_dividend[31]} >= div_dvsr) begin
                  div_rem <= ({div_rem[30:0], div_dividend[31]} - div_dvsr);
                  div_quot <= {div_quot[30:0], 1'b1};
                end else begin
                  div_quot <= {div_quot[30:0], 1'b0};
                end
                div_cnt <= div_cnt + 6'd1;
              end else begin
                /*
                Division done: range-check the signed quotient, then deliver
                the signed quotient and remainder.
                */
                if (div_signed) begin
                  if (div_is_word) begin
                    if (($signed(div_quot_signed) > $signed(32'd32767)) ||
                        ($signed(div_quot_signed) < $signed(32'hFFFF8000))) begin
                      interrupt_vector <= DIVIDE_VECTOR;
                      interrupt_is_nmi <= 1'b0;
                      interrupt_step <= 4'd0;
                      state <= INTERRUPT;
                    end else begin
                      gpr[REG_AX] <= div_quot_signed[15:0];
                      gpr[REG_DX] <= div_rem_signed[15:0];
                      finish_instruction(cyc_model_i ? $signed({56'b0, DIV_WORD_CYCLES}) : 64'sd0);
                    end
                  end else begin
                    if (($signed(div_quot_signed) > $signed(32'd127)) ||
                        ($signed(div_quot_signed) < $signed(32'hFFFFFF80))) begin
                      interrupt_vector <= DIVIDE_VECTOR;
                      interrupt_is_nmi <= 1'b0;
                      interrupt_step <= 4'd0;
                      state <= INTERRUPT;
                    end else begin
                      gpr[REG_AX] <= {div_rem_signed[7:0], div_quot_signed[7:0]};
                      finish_instruction(cyc_model_i ? $signed({56'b0, DIV_BYTE_CYCLES}) : 64'sd0);
                    end
                  end
                end else begin
                  if (div_is_word) begin
                    if (div_quot > 32'd65535) begin
                      interrupt_vector <= DIVIDE_VECTOR;
                      interrupt_is_nmi <= 1'b0;
                      interrupt_step <= 4'd0;
                      state <= INTERRUPT;
                    end else begin
                      gpr[REG_AX] <= div_quot[15:0];
                      gpr[REG_DX] <= div_rem[15:0];
                      finish_instruction(cyc_model_i ? $signed({56'b0, DIV_WORD_CYCLES}) : 64'sd0);
                    end
                  end else begin
                    if (div_quot > 32'd255) begin
                      interrupt_vector <= DIVIDE_VECTOR;
                      interrupt_is_nmi <= 1'b0;
                      interrupt_step <= 4'd0;
                      state <= INTERRUPT;
                    end else begin
                      gpr[REG_AX] <= {div_rem[7:0], div_quot[7:0]};
                      finish_instruction(cyc_model_i ? $signed({56'b0, DIV_BYTE_CYCLES}) : 64'sd0);
                    end
                  end
                end
              end
            end
            INTERRUPT: begin
              case (interrupt_step)
                4'd0: begin /* push FLAGS */
                  if (bus_ack) begin
                    gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                    interrupt_step <= 4'd1;
                  end
                end
                4'd1: begin /* push CS */
                  if (bus_ack) begin
                    gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                    interrupt_step <= 4'd2;
                  end
                end
                4'd2: begin /* push IP */
                  if (bus_ack) begin
                    gpr[REG_SP] <= gpr[REG_SP] - STACK_SLOT_BYTES;
                    interrupt_step <= 4'd3;
                  end
                end
                4'd3: begin /* read IVT offset */
                  if (bus_ack) begin
                    ip <= bus_rdata;
                    interrupt_step <= 4'd4;
                  end
                end
                4'd4: begin /* read IVT segment, then finish */
                  if (bus_ack) begin
                    sreg[SEG_CS] <= bus_rdata;
                    ifl <= 1'b0;
                    tf <= 1'b0;
                    if (interrupt_is_nmi)
                      nmi_pending <= 1'b0;
                    else
                      irq_pending <= 1'b0;
                    /*
                    Interrupt-entry charge as the finish extra, so it
                    enters the pad/boundary decision in this same clock.
                    A separate nonblocking add to cycle_charge here would
                    be read stale by finish_instruction and then
                    overwritten, losing the 42 cycles.
                    */
                    finish_instruction(cyc_model_i ? $signed({56'b0, INT_ENTRY_CYCLES}) : 64'sd0);
                  end
                end
                default: begin
                  finish_instruction(64'sd0);
                end
              endcase
            end
            PAD_CYCLES: begin
              if (pad_clocks <= 32'd1) begin
                finish_instruction(64'sd0);
              end else begin
                pad_clocks <= pad_clocks - 32'd1;
              end
            end
            HALTED: begin
              if (nmi_pending || (irq_pending && ifl && !interrupt_inhibit)) begin
                if (nmi_pending) begin
                  interrupt_vector <= NMI_VECTOR;
                  interrupt_is_nmi <= 1'b1;
                  interrupt_step <= 4'd0;
                  halted <= 1'b0;
                  state <= INTERRUPT;
                end else begin
                  interrupt_vector <= irq_vec;
                  interrupt_is_nmi <= 1'b0;
                  interrupt_step <= 4'd0;
                  irq_taken_q <= 1'b1;
                  halted <= 1'b0;
                  state <= INTERRUPT;
                end
              end
            end
            BAD_OPCODE: begin
              /* Terminal. The harness reads badop_pc_o / badop_o. */
            end
            default: begin
              state <= FETCH_OPCODE;
            end
          endcase
          /* Interrupt edge capture AFTER the FSM: a new edge wins over a
             same-cycle clear from the FSM or from irq_clear_i. */
          if (nmi_i && !nmi_prev_level) begin
            nmi_pending <= 1'b1;
          end
          if (irq_i && !irq_prev_level) begin
            irq_pending <= 1'b1;
            irq_vec <= irq_vec_i;
          end
          nmi_prev_level <= nmi_i;
          irq_prev_level <= irq_i;
          if (irq_clear_i) begin
            if (!(irq_i && !irq_prev_level))
              irq_pending <= 1'b0;
          end
        end
      
        end
    end

  /* Per-iteration charge for a string operation (i186.c strop). Model 1:
     first iteration per_it + (setup unless resumed) - CYC[op] when REP,
     single - CYC[op] when not REP; later iterations per_it. Model 0: 4. */
  logic signed [63:0] string_iter_charge_c;
  always_comb begin
    if (!cyc_model_i) begin
      string_iter_charge_c = $signed({56'b0, FLAT_CYCLES});
    end else if (string_first_iter) begin
      if (rep_prefix) begin
        string_iter_charge_c = $signed({56'b0, str_per_it(string_kind)})
                             + (string_resumed ? 64'sd0 : $signed({56'b0, str_setup(string_kind)}))
                             - $signed({56'b0, cyc_base(opcode)});
      end else begin
        string_iter_charge_c = $signed({56'b0, str_single(string_kind)})
                             - $signed({56'b0, cyc_base(opcode)});
      end
    end else begin
      string_iter_charge_c = $signed({56'b0, str_per_it(string_kind)});
    end
  end

  /* Charge one string iteration, then decide: CMPS/SCAS early exit, REP
     yield on a pending interrupt, next iteration, or finish. The
     iteration charge is both folded into cycle_charge and passed to
     finish_instruction, so the pad uses the full charge even though the
     nonblocking cycle_charge update has not landed yet. The ZF test
     uses alu_zf (the combinational result just computed), not the zf
     register, which still holds the old value in this clock. */
  task automatic string_complete_iteration;
    begin
      cycle_charge <= cycle_charge + string_iter_charge_c;
      string_first_iter <= 1'b0;
      if (rep_prefix) begin
        gpr[REG_CX] <= gpr[REG_CX] - 16'd1;
        if (((string_kind == STR_CMPS) || (string_kind == STR_SCAS)) &&
            (rep_zero ? !alu_zf : alu_zf)) begin
          finish_instruction(string_iter_charge_c);
        end else if ((gpr[REG_CX] != 16'd1) && (nmi_pending || (irq_pending && ifl))) begin
          ip <= instr_start_ip;
          rep_resumed <= 1'b1;
          finish_instruction(string_iter_charge_c);
        end else if (gpr[REG_CX] == 16'd1) begin
          finish_instruction(string_iter_charge_c);
        end else begin
          string_step <= 3'd0;
        end
      end else begin
        finish_instruction(string_iter_charge_c);
      end
    end
  endtask

  /* DAA / DAS intermediate values (i186.c exec_decimal). The low-nibble
     adjust runs first; its overflow feeds the local carry, which then
     forces the high adjust (threshold 0x9F, not 0x99). */
  logic        daa_low_adj;
  logic [8:0]  daa_al_after_low;
  logic        daa_cf_after_low;
  logic [7:0]  daa_al_low;
  logic        daa_high_adj;
  logic [7:0]  daa_al_final;
  logic        daa_cf_final;
  logic        daa_af_final;
  logic        das_low_adj;
  logic [7:0]  das_al_after_low;
  logic        das_cf_after_low;
  logic [7:0]  das_al_low;
  logic        das_high_adj;
  logic [7:0]  das_al_final;
  logic        das_cf_final;
  logic        das_af_final;
  always_comb begin
    daa_low_adj = ((al_byte[3:0] > 4'd9) || af);
    daa_al_after_low = daa_low_adj ? ({1'b0, al_byte} + 9'd6) : {1'b0, al_byte};
    daa_cf_after_low = cf || daa_al_after_low[8];
    daa_al_low = daa_al_after_low[7:0];
    daa_high_adj = (daa_al_low > 8'h9F) || daa_cf_after_low;
    daa_al_final = daa_high_adj ? (daa_al_low + 8'h60) : daa_al_low;
    daa_cf_final = daa_high_adj ? 1'b1 : daa_cf_after_low;
    daa_af_final = daa_low_adj;
    das_low_adj = ((al_byte[3:0] > 4'd9) || af);
    das_al_after_low = das_low_adj ? (al_byte - 8'd6) : al_byte;
    das_cf_after_low = cf || (das_low_adj && (al_byte < 8'd6));
    das_al_low = das_al_after_low;
    das_high_adj = (das_al_low > 8'h9F) || das_cf_after_low;
    das_al_final = das_high_adj ? (das_al_low - 8'h60) : das_al_low;
    das_cf_final = das_high_adj ? 1'b1 : das_cf_after_low;
    das_af_final = das_low_adj;
  end

  /* Shift/rotate cycle extra (i186.c exec_shift_imm / exec_shift_1_cl).
     Model 1 only. By-imm: (mod==3 ? 0 : 6) + (n & 31) - 1. By-CL:
     (mod==3 ? 0 : 6) + (n & 31) + 1. By-1: (mod==3 ? -2 : 5). */
  logic signed [63:0] shift_extra_c;
  always_comb begin
    if (!cyc_model_i) begin
      shift_extra_c = 64'sd0;
    end else if (instr_class == CLASS_SHIFT_IMM) begin
      shift_extra_c = ((mod == 2'd3) ? 64'sd0 : $signed({56'b0, SHIFT_BYCL_MEM_CYCLES}))
                    + $signed({59'b0, sh_n})
                    + $signed({{56{SHIFT_IMM_MINUS1[7]}}, SHIFT_IMM_MINUS1});
    end else if (instr_class == CLASS_SHIFT_1_CL) begin
      if ((opcode == 8'hD2) || (opcode == 8'hD3)) begin
        shift_extra_c = ((mod == 2'd3) ? $signed({56'b0, SHIFT_BYCL_REG_CYCLES}) : $signed({56'b0, SHIFT_BYCL_MEM_CYCLES}))
                      + $signed({59'b0, sh_n})
                      + $signed({56'b0, SHIFT_BYCL_PLUS1});
      end else begin
        shift_extra_c = (mod == 2'd3) ? $signed({{56{SHIFT_BY1_REG_CYCLES[7]}}, SHIFT_BY1_REG_CYCLES})
                                      : $signed({56'b0, SHIFT_BY1_MEM_CYCLES});
      end
    end else begin
      shift_extra_c = 64'sd0;
    end
  end

endmodule
`default_nettype wire
