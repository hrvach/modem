/*
c5x_alu.sv -- TMS320C5x (C51 flavour) CALU + barrel shifter + 16x16
multiplier, with the ACC / ACCB / PREG / TREG0-2 registers and the
CALU flags C and OV.

Reference model (the spec; this module matches it as-is):
  research_notes/courier-firmware/c-port/c/src/dsp/c5x_core.c
  - do_add / do_sub ............ lines 992-1032
  - pscale ..................... lines 1034-1045
  - set_t0 ..................... lines 1047-1055
  - ext() ...................... lines 1326-1331
  - MPY/MPYA/MPYS/SQRA/SQRS .... lines 1582-1623 (exec_hi_40_5f)
  - ADD/SUB/ADDT/SUBT/LACT ..... lines 1690-1765 (exec_hi_60_7f)
  - LTA/LTP/LTD/LTS ............ lines 1786-1823 (exec_hi_60_7f)
  - SACL/SACH .................. lines 1947-1955 (exec_hi_80_9f)
  - NORM ....................... lines 1965-1985 (exec_hi_a0_af)
  - MADS/MADD .................. lines 2083-2105 (exec_hi_a0_af)
  - ABS/CMPL/NEG/PAC/APAC/SPAC . lines 2195-2222 (exec_be_acc)
  - ROL/ROR/ROLC/RORC .......... lines 2224-2236 (exec_be_acc)
  - ADDB/ADDC/SUBB/SBBB/AND B/OR B/XOR B/MAX/MIN/SWAP/SACB/LACB
                                 lines 2237-2286 (exec_be_acc)
  - SATH/SATL .................. lines 2359-2371 (exec_be_ctrl)
  - MPY #lk .................... lines 2369-2373 (exec_be_ctrl)
  - SUBC ....................... lines 1409-1425 (exec_hi_00_0f)
  - long-immediate ALU ......... lines 2493-2513 (exec_bf; SFTA)
  - MPY #k13 ................... lines 1532-1538 (exec1_op)
  - c5x_reset .................. lines 425-432 (reset values)
Instruction semantics cross-checked against:
  research_notes/courier-firmware/c5x_core_audit/
    07b-core3-instructions-a-r.md, 07c-core3-instructions-s-z-cycles.md
    (audit verdicts: ADD/SUB/MPY/SATH/SATL/SUBC/NORM/ROL/ROR all OBEYS)

Architecture notes (see GOAL.md):
- Multi-cycle core: this block is a single-cycle combinational
  datapath. The core agent asserts i_exec for one clock when the
  micro-op executes, with i_ld_* selecting which registers take the
  computed next value. Flags C/OV follow the micro-op whenever
  i_exec is high (they are CALU state, not gated by i_ld_acc);
  explicit flag loads (LST #0/#1) use i_flag_*_we and win over an
  op-driven flag update in the same cycle.
- Single clock, active-low synchronous reset (rst_n).
- Combinational datapath; the 16x16 multiplier is one '*' operator
  so Quartus maps it to Cyclone V DSP blocks. No latches: every
  always_comb output has a default assignment.
- "SAR" in the C5x ISA is Store Auxiliary Register (not a shift).
  The shifts implemented here are the C model's: BSAR/SFTA
  (ACC >> (sh+1), sign per SXM), SATH/SATL (ACC >> TREG1), ROL/ROR/
  ROLC/RORC (1-bit), SFLB/SFRB/ROLB/RORB (64-bit ACC:ACCB), NORM
  (conditional <<1), ext() (data << sh, sign per SXM), and the
  SACL/SACH store shift (o_shl_acc). No C5x instruction shifts by
  an amount taken from ACC (verified by grep over exec1 in the C
  model); "shift-by-ACC" below means shifts *of* ACC, with the
  amount from the opcode field (i_shift) or from TREG1.

KNOWN-DIFF (C model vs TI manual; RTL matches the C model as-is,
  fixes are a separate step -- see GOAL.md constraints):
- KD-1 BSAR/SFTA amount: the C model shifts ACC right by (sh+1)
  (exec_bf, SFTA: `sh = sh + 1`), so opcode 0xBFE3 shifts by 4.
  An older reading of the manual suggested the shift equals the
  4-bit field (3 for 0xBFE3). The core-3 audit (07b:131) rates BSAR
  OBEYS against SPRU056D SS6.3, i.e. the (sh+1) reading is the
  audited one. This module implements (sh+1) per the C model.
- KD-2 SUBC/OV latch, SBBB no-OV, SATH/SATL C-untouched, and the
  16-bit ADD/SUB "carry sets / borrow clears, otherwise hold"
  behaviour are all as the C model does them (do_add/do_sub
  s16=1 arms); they match the audit (SUBC #24 FIXED, 07c:135).
- KD-3 The audit fix list (07-core3-fix-list.md) contains no
  CALU/shifter/multiplier item against the C model as used here:
  the open items (RPTB PAER off-by-one, DMOV destination gate,
  XC skip, IDLE2, TRAP/NMI IPTR remap, cycle-count rows) belong
  to the control / memory agents, not this block.
- KD-23 MADS/MADD TREG0 mirror: FIXED by OP_LT_NM (no-mirror TREG0
  load, c5x_core.c:2092, audit N-1). The ctrl must use OP_LT_NM for
  MADS/MADD; OP_LT still mirrors TREG1/TREG2 when TRM=0. MADD's
  DMOV is the memory agent's, not this block's.

Combinational result tap: acc_next is the value the ALU would write
to ACC for the current micro-op (the top level wires it to the
ctrl's alu_y; c5x_core.sv). It is the registered ACC value one
clock early, so a consumer that feeds it back in the same cycle
sees the new result, not the stale ACC.

Register load contract (the core agent must drive i_ld_*
consistently with the instruction; the op determines the next
value, the load enable gates whether it is taken):
  OPs writing ACC only ............ i_ld_acc
  OPs writing ACCB (SWAP, SACB, MAX, MIN, SFLB/SFRB/ROLB/RORB)
      ............................. i_ld_acc + i_ld_accb (both)
  OPs writing PREG (MPY, MPYU, MPYA, MPYS, SQRA, SQRS, LPH,
      PREG_ZERO, ACC_PREG_ZERO) .... i_ld_preg (+ i_ld_acc
      where noted). LTA/LTP/LTD/LTS do NOT write PREG: they
      accumulate the OLD PREG via pscale (c5x_core.c:1789-1816);
      the product is loaded by a preceding LT/MPY.
  OPs writing TREG0 (LT, LTA, LTP, LTD, LTS, SQRA, SQRS)
      ............................. i_ld_treg0 (+ i_ld_acc
                                     where noted; SQRA/SQRS also
                                     write PREG, i_ld_preg).
                                     TREG1/TREG2 mirror
                                     TREG0[4:0]/TREG0[3:0] unless i_trm.
  OP_LT_NM (MADS/MADD) ............ i_ld_treg0 + i_ld_acc +
                                     i_ld_preg. Loads TREG0 with NO
                                     TREG1/TREG2 mirror even when
                                     TRM=0 (KD-23; C writes c->treg0
                                     directly, c5x_core.c:2092,
                                     audit N-1). ACC += pscale(OLD
                                     PREG); PREG = dma * pma.
  MPY operand wiring: drive i_mpy_a/i_mpy_b explicitly:
      MPY/MPYA/MPYS/MPY #k13 ...... a = TREG0 (o_treg0), b = dma/imm
      SQRA/SQRS ................... a = b = dma (i_b16)
      MAC/MACD .................... a = dma, b = pma; MAC maps to
          OP_LTA, MACD to OP_LTD (C: ACC += OLD PREG, TREG0=dma,
          PREG = dma*pma; c5x_core.c:1984-1996). No separate op.
      MADS/MADD ................... a = dma (i_b16), b = pma; maps
          to OP_LT_NM (ACC += OLD PREG, TREG0=dma with NO mirror,
          PREG = dma*pma; c5x_core.c:2083-2105). MADD additionally
          DMOVs; the DMOV and the BMAR program-address sequencing
          belong to the core / memory agents, not this block.
    MPYU sets i_mpy_unsigned=1; all other MPY forms are signed.
  Shift amount i_shift: LACC/ADD/SUB #lk,sh and dma,s use [3:0]
    (0-15); SFTA uses [3:0] as sh (amount sh+1, 1-16); SACL/SACH
    store shift uses [2:0] (0-7) via o_shl_acc; ADDT/SUBT/LACT,
    SATH/SATL take the amount from TREG1 (internal), i_shift ignored.
  i_s16 = 1 selects the 16-bit ADD/SUB form (ADD/SUB dma,16):
    carry sets C / borrow clears C, otherwise C holds (do_add/
    do_sub s16=1, c5x_core.c:992-1032).

Ports are prefixed i_/o_ per project convention. All widths explicit.
One exception: acc_next carries no o_ prefix, matching the name the
ctrl / top-level documentation uses for the combinational ALU result.
*/

`default_nettype none

module c5x_alu (
    input  logic        clk,
    input  logic        ce_i, /* DSP clock enable: every register advances only when high */
    input  logic        rst_n,

    /* Execute strobe and register write enables. */
    input  logic        i_exec,
    input  logic        i_ld_acc,
    input  logic        i_ld_accb,
    input  logic        i_ld_preg,
    input  logic        i_ld_treg0,
    input  logic        i_rs_acc,       /* shadow-context restore (RETI/RETE): load the register from the given value directly, independent of any micro-op */
    input  logic        i_rs_accb,
    input  logic        i_rs_preg,
    input  logic [2:0]  i_rs_treg,      /* bit n loads TREGn */
    input  logic [31:0] i_rs_acc_d,
    input  logic [31:0] i_rs_accb_d,
    input  logic [31:0] i_rs_preg_d,
    input  logic [15:0] i_rs_treg_d,

    /* Micro-op and operands. */
    input  logic [6:0]  i_op,
    input  logic [31:0] i_b32,
    input  logic [15:0] i_b16,
    input  logic [15:0] i_mpy_a,
    input  logic [15:0] i_mpy_b,
    input  logic        i_mpy_unsigned,
    input  logic [3:0]  i_shift,
    input  logic        i_s16,

    /* Mode bits, owned by the core (ST1/PMST). */
    input  logic        i_sxm,
    input  logic        i_ovm,
    input  logic [1:0]  i_pm,
    input  logic        i_trm,

    /* Explicit flag loads (LST #0/#1); win over op-driven updates. */
    input  logic        i_flag_c_we,
    input  logic        i_flag_c_in,
    input  logic        i_flag_ov_we,
    input  logic        i_flag_ov_in,

    /* Architectural state (registered). */
    output logic [31:0] o_acc,
    output logic [31:0] o_accb,
    output logic [31:0] o_preg,
    output logic [15:0] o_treg0,
    output logic [15:0] o_treg1,
    output logic [15:0] o_treg2,
    output logic        o_c,
    output logic        o_ov,

    /* Combinational datapath taps (core / memory agents). */
    output logic [31:0] o_pscale, /* PREG scaled by PM (pscale) */
    output logic [31:0] o_ext, /* ext(i_b16, i_shift[3:0]), SXM-aware */
    output logic [31:0] o_b16_shl, /* {16'b0, i_b16} << i_shift[3:0] */
    output logic [31:0] o_shl_acc, /* ACC << i_shift[2:0] (SACL/SACH) */
    output logic [31:0] o_mpy, /* i_mpy_a * i_mpy_b (signed/unsigned) */

    /* NORM TC (combinational; the core registers TC). */
    output logic        o_tc_next,
    output logic        o_tc_wr,

    /* Combinational micro-op result: the value the ALU would write
       to ACC for the current micro-op. The top level wires this to
       the ctrl's alu_y. Signed: it carries an ACC value. */
    output logic signed [31:0] acc_next
);

    /*
    Micro-op encodings. One op fully determines every register
    next-value; i_ld_* gates which registers take it.
    */
    localparam logic [6:0] OP_NOP           = 7'd0;
    localparam logic [6:0] OP_ADD           = 7'd1;
    localparam logic [6:0] OP_ADDC          = 7'd2;
    localparam logic [6:0] OP_SUB           = 7'd3;
    localparam logic [6:0] OP_SUBB          = 7'd4;
    localparam logic [6:0] OP_SBBB          = 7'd5;
    localparam logic [6:0] OP_ADD_B         = 7'd6;
    localparam logic [6:0] OP_ADDC_B        = 7'd7;
    localparam logic [6:0] OP_SUB_B         = 7'd8;
    localparam logic [6:0] OP_AND           = 7'd9;
    localparam logic [6:0] OP_OR            = 7'd10;
    localparam logic [6:0] OP_XOR           = 7'd11;
    localparam logic [6:0] OP_AND_B         = 7'd12;
    localparam logic [6:0] OP_OR_B          = 7'd13;
    localparam logic [6:0] OP_XOR_B         = 7'd14;
    localparam logic [6:0] OP_ADD_SH        = 7'd15;
    localparam logic [6:0] OP_SUB_SH        = 7'd16;
    localparam logic [6:0] OP_ADDT          = 7'd17;
    localparam logic [6:0] OP_SUBT          = 7'd18;
    localparam logic [6:0] OP_LD_EXT        = 7'd19;
    localparam logic [6:0] OP_LACT          = 7'd20;
    localparam logic [6:0] OP_LD_B32        = 7'd21;
    localparam logic [6:0] OP_LD_B16Z       = 7'd22;
    localparam logic [6:0] OP_LD_B16HI      = 7'd23;
    localparam logic [6:0] OP_LD_ZALR       = 7'd24;
    localparam logic [6:0] OP_NEG           = 7'd25;
    localparam logic [6:0] OP_ABS           = 7'd26;
    localparam logic [6:0] OP_CMPL          = 7'd27;
    localparam logic [6:0] OP_MAX           = 7'd28;
    localparam logic [6:0] OP_MIN           = 7'd29;
    localparam logic [6:0] OP_SWAP          = 7'd30;
    localparam logic [6:0] OP_SACB          = 7'd31;
    localparam logic [6:0] OP_LACB          = 7'd32;
    localparam logic [6:0] OP_SUBC          = 7'd33;
    localparam logic [6:0] OP_PAC           = 7'd34;
    localparam logic [6:0] OP_APAC          = 7'd35;
    localparam logic [6:0] OP_SPAC          = 7'd36;
    localparam logic [6:0] OP_MPYA          = 7'd37;
    localparam logic [6:0] OP_MPYS          = 7'd38;
    localparam logic [6:0] OP_SQRA          = 7'd39;
    localparam logic [6:0] OP_SQRS          = 7'd40;
    localparam logic [6:0] OP_LTA           = 7'd41;
    localparam logic [6:0] OP_LTP           = 7'd42;
    localparam logic [6:0] OP_LTD           = 7'd43;
    localparam logic [6:0] OP_LTS           = 7'd44;
    localparam logic [6:0] OP_LT            = 7'd45;
    localparam logic [6:0] OP_MPY           = 7'd46;
    localparam logic [6:0] OP_MPYU          = 7'd47;
    localparam logic [6:0] OP_LPH           = 7'd48;
    localparam logic [6:0] OP_PREG_ZERO     = 7'd49;
    localparam logic [6:0] OP_ACC_ZERO      = 7'd50;
    localparam logic [6:0] OP_ACC_PREG_ZERO = 7'd51;
    localparam logic [6:0] OP_ROL           = 7'd52;
    localparam logic [6:0] OP_ROR           = 7'd53;
    localparam logic [6:0] OP_ROLC          = 7'd54;
    localparam logic [6:0] OP_RORC          = 7'd55;
    localparam logic [6:0] OP_SFLB          = 7'd56;
    localparam logic [6:0] OP_SFRB          = 7'd57;
    localparam logic [6:0] OP_ROLB          = 7'd58;
    localparam logic [6:0] OP_RORB          = 7'd59;
    localparam logic [6:0] OP_SFTA          = 7'd60;
    localparam logic [6:0] OP_SATH          = 7'd61;
    localparam logic [6:0] OP_SATL          = 7'd62;
    localparam logic [6:0] OP_NORM          = 7'd63;
    localparam logic [6:0] OP_LT_NM         = 7'd64;

    /*
    Architectural constants. Every value here comes from the C model
    or the TI manual; the comment on each one names its source so a
    reader never has to guess where a number came from.
    */
    /* Overflow saturation bounds (do_add/do_sub, c5x_core.c:992-1032). */
    localparam logic [31:0] SAT_POS = 32'h7fffffff;
    localparam logic [31:0] SAT_NEG = 32'h80000000;

    /* pscale() shift amounts by PM mode (c5x_core.c:1034-1045). */
    localparam logic [2:0] PM_SHIFT_ONE = 3'd1;
    localparam logic [2:0] PM_SHIFT_FOUR = 3'd4;
    localparam logic [2:0] PM_SHIFT_SIX = 3'd6;

    /* SUBC forms dma << 15 (exec_hi_00_0f, c5x_core.c:1409-1425). */
    localparam logic [4:0] SUBC_SHIFT = 5'd15;

    /* BSAR/SFTA shifts by sh+1, not sh (KD-1; SFTA, c5x_core.c:2507-2511). */
    localparam logic [4:0] SFTA_SHIFT_BIAS = 5'd1;

    /* set_t0 mirrors: TREG1 holds TREG0[4:0], TREG2 holds TREG0[3:0]
       (c5x_core.c:1047-1055). */
    localparam logic [4:0] TREG1_FIELD_TOP = 5'd4;
    localparam logic [3:0] TREG2_FIELD_TOP = 4'd3;

    /* ZALR loads the low half of ACC with 0x8000 (c5x_core.c:1724). */
    localparam logic [15:0] ZALR_LOW_HALF = 16'h8000;

    /*
    Architectural registers (reset values per c5x_reset,
    c5x_core.c:425-432: ACC=ACCB=PREG=TREG0/1/2=0, C=1, OV=0).
    */
    logic [31:0] acc_q, accb_q, preg_q;
    logic [15:0] treg0_q, treg1_q, treg2_q;
    logic        c_q, ov_q;

    assign o_acc   = acc_q;
    assign o_accb  = accb_q;
    assign o_preg  = preg_q;
    assign o_treg0 = treg0_q;
    assign o_treg1 = treg1_q;
    assign o_treg2 = treg2_q;
    assign o_c     = c_q;
    assign o_ov    = ov_q;

    /*
    ---------------------------------------------------------------
    Combinational datapath taps.
    ---------------------------------------------------------------
    */

    /*
    pscale(): PREG scaled by PM (c5x_core.c:1034-1045).
      PM=0: no shift; PM=1: <<1; PM=2: <<4; PM=3: >>6 arithmetic.
    */
    logic [31:0] pscale_result;
    always_comb begin
        case (i_pm)
            2'd0:    pscale_result = preg_q;
            2'd1:    pscale_result = preg_q << PM_SHIFT_ONE;
            2'd2:    pscale_result = preg_q << PM_SHIFT_FOUR;
            default: pscale_result = $signed(preg_q) >>> PM_SHIFT_SIX;
        endcase
    end
    assign o_pscale = pscale_result;

    /*
    ext(): 16-bit data -> 32-bit with left shift, honouring SXM
    (c5x_core.c:1326-1331). SXM=1 sign-extends, SXM=0 zero-extends.
    */
    logic [31:0] ext_result;
    always_comb begin
        if (i_sxm)
            ext_result = {{16{i_b16[15]}}, i_b16} << i_shift[3:0];
        else
            ext_result = {16'b0000000000000000, i_b16} << i_shift[3:0];
    end
    assign o_ext = ext_result;

    /* Plain zero-extended shift (AND/OR/XOR #lk,sh: exec_bf 0xB0-0xD0). */
    assign o_b16_shl = {16'b0000000000000000, i_b16} << i_shift[3:0];

    /* ACC left shift for SACL/SACH stores (exec_hi_80_9f, 0x90-0x9F). */
    assign o_shl_acc = acc_q << i_shift[2:0];

    /*
    16x16 multiplier -> 32-bit PREG. Single signed expression:
    one 18x18 multiply, product registered straight into PREG.
    Cyclone V DSP mapping (18x18 variable-precision mode): the two
    16-bit operands are extended to 18-bit signed BEFORE the
    multiply -- sign extension for MPY, zero extension for MPYU --
    so the low 32 bits of the one product are correct for both
    forms (signed product range and unsigned product range both fit
    in 32 bits). The 32-bit product keeps exactly the low 32 bits
    of the 18x18 result, which is all PREG holds. No logic sits
    between the multiply output and the PREG register except the
    register's own write-select mux (preg_next: o_mpy vs LPH
    concat vs zero vs hold).
      C model: (int32_t)(int16_t)a * (int32_t)(int16_t)b (MPY,
      MPY #k13, MPY #lk); (uint32_t)a * (uint32_t)b (MPYU).
    No absorbed multiply+accumulate anywhere: in the C model every
    accumulate (MPYA/MPYS/SQRA/SQRS/LTA/LTD/LTS/MAC/MACD) adds the
    OLD PREG via pscale, and the multiply writes the NEW PREG
    (c5x_core.c:1585-1615, 1789-1816, 1992). The new product never
    feeds the ACC adder in the same instruction, so a DSP-block
    accumulate would change semantics; the ACC add stays in ALMs.
    */
    logic signed [17:0] mpy_op_a, mpy_op_b;
    logic signed [31:0] mpy_prod;
    always_comb begin
        if (i_mpy_unsigned) begin
            mpy_op_a = {2'b00, i_mpy_a};
            mpy_op_b = {2'b00, i_mpy_b};
        end else begin
            mpy_op_a = {{2{i_mpy_a[15]}}, i_mpy_a};
            mpy_op_b = {{2{i_mpy_b[15]}}, i_mpy_b};
        end
        mpy_prod = mpy_op_a * mpy_op_b;
    end
    assign o_mpy = mpy_prod;

    /*
    ---------------------------------------------------------------
    Adder / subtractor engines (do_add / do_sub, c5x_core.c:992-1032).

    ADD engine: a + b + cin. Second operand add_operand_b is op-selected.
    SUB engine: a - b - bin. SUBC and SBBB have their own engines
    below because their flag semantics differ from do_sub.
    ---------------------------------------------------------------
    */
    logic [31:0] add_operand_b, sub_operand_b;
    logic        add_carry_in, sub_borrow_in;

    always_comb begin
        add_operand_b = i_b32;
        sub_borrow_in = 1'b0;
        add_carry_in  = 1'b0;
        case (i_op)
            OP_ADDC:   add_carry_in = c_q;
            OP_ADDC_B: begin
                add_carry_in  = c_q;
                add_operand_b = accb_q;
            end
            OP_ADD_B:  add_operand_b = accb_q;
            OP_SUBB:   sub_borrow_in = ~c_q;
            OP_ADD_SH: add_operand_b = ext_result;
            OP_ADDT: begin
                if (i_sxm)
                    add_operand_b = {{16{i_b16[15]}}, i_b16} << treg1_q[3:0];
                else
                    add_operand_b = {16'b0000000000000000, i_b16} << treg1_q[3:0];
            end
            OP_APAC, OP_MPYA, OP_SQRA, OP_LTA, OP_LTD, OP_LT_NM: add_operand_b = pscale_result;
            default: begin end
        endcase
        sub_operand_b = add_operand_b;
        case (i_op)
            OP_SUB_B: sub_operand_b = accb_q;
            OP_SPAC, OP_MPYS, OP_SQRS, OP_LTS: sub_operand_b = pscale_result;
            OP_SUB_SH: sub_operand_b = ext_result;
            OP_SUBT: begin
                if (i_sxm)
                    sub_operand_b = {{16{i_b16[15]}}, i_b16} << treg1_q[3:0];
                else
                    sub_operand_b = {16'b0000000000000000, i_b16} << treg1_q[3:0];
            end
            default: begin end
        endcase
    end

    /*
    do_add: 33-bit sum; carry = bit 32; overflow = sign(a)^sign(res)
    & sign(b)^sign(res); saturation to 0x7FFFFFFF/0x80000000 when
    overflow and OVM (res sign picks the bound).
    */
    logic [32:0] add_sum;
    logic [31:0] add_res, add_sat;
    logic        add_carry, add_ovf;
    assign add_sum   = {1'b0, acc_q} + {1'b0, add_operand_b} + {32'b0, add_carry_in};
    assign add_res   = add_sum[31:0];
    assign add_carry = add_sum[32];
    assign add_ovf   = (acc_q[31] ^ add_res[31]) & (add_operand_b[31] ^ add_res[31]);

    /* Saturate on overflow when OVM is set; the result sign picks the bound. */
    always_comb begin
        if (add_ovf && i_ovm) begin
            if (add_res[31])
                add_sat = SAT_POS;
            else
                add_sat = SAT_NEG;
        end else begin
            add_sat = add_res;
        end
    end

    /*
    do_sub: 33-bit difference; borrow = bit 32; overflow =
    sign(a)^sign(b) & sign(a)^sign(res); same saturation rule.
    */
    logic [32:0] sub_diff;
    logic [31:0] sub_res, sub_sat;
    logic        sub_borrow, sub_ovf;
    assign sub_diff   = {1'b0, acc_q} - {1'b0, sub_operand_b} - {32'b0, sub_borrow_in};
    assign sub_res    = sub_diff[31:0];
    assign sub_borrow = sub_diff[32];
    assign sub_ovf    = (acc_q[31] ^ sub_operand_b[31]) & (acc_q[31] ^ sub_res[31]);

    /* Saturate on overflow when OVM is set; the result sign picks the bound. */
    always_comb begin
        if (sub_ovf && i_ovm) begin
            if (sub_res[31])
                sub_sat = SAT_POS;
            else
                sub_sat = SAT_NEG;
        end else begin
            sub_sat = sub_res;
        end
    end

    /*
    SUBC divide step (exec_hi_00_0f, 0x0A; audit #24 FIXED):
      b = dma << 15; r = ACC - b; C = !borrow; OV set on overflow
      (latched, never cleared here); no saturation;
      ACC = (r >= 0 signed) ? (r << 1) + 1 : ACC << 1.
    */
    logic [31:0] subc_b, subc_res;
    logic [32:0] subc_diff;
    logic        subc_borrow, subc_ovf;
    assign subc_b      = {16'b0, i_b16} << SUBC_SHIFT;
    assign subc_diff   = {1'b0, acc_q} - {1'b0, subc_b};
    assign subc_res    = subc_diff[31:0];
    assign subc_borrow = subc_diff[32];
    assign subc_ovf    = (acc_q[31] ^ subc_b[31]) &
                         (acc_q[31] ^ subc_res[31]);

    /*
    SBBB (exec_be_acc, 0x19): ACC -= ACCB + !C; affects C only --
    no OV, no saturation (SPRU056D p.6-233).
    */
    logic [32:0] sbbb_diff;
    logic [31:0] sbbb_res;
    logic        sbbb_borrow;
    assign sbbb_diff   = {1'b0, acc_q} - {1'b0, accb_q} - {32'b0, ~c_q};
    assign sbbb_res    = sbbb_diff[31:0];
    assign sbbb_borrow = sbbb_diff[32];

    /* Signed views used by arithmetic shifts and signed compares. */
    logic signed [31:0] acc_signed;
    assign acc_signed = acc_q;

    /*
    ---------------------------------------------------------------
    Next-state decode. Defaults hold everything; each op overrides
    only what it writes. carry_next/carry_write_enable/overflow_set follow the op (see the
    flag contract in the header); tc is NORM-only, combinational.
    ---------------------------------------------------------------
    */
    logic [31:0] accb_next, preg_next;
    logic [15:0] treg0_next, treg1_next, treg2_next;
    logic        carry_next, carry_write_enable, overflow_set;
    logic        tc_next_w, tc_wr_w;

    always_comb begin
        acc_next           = acc_q;
        accb_next          = accb_q;
        preg_next          = preg_q;
        treg0_next         = treg0_q;
        treg1_next         = treg1_q;
        treg2_next         = treg2_q;
        carry_next         = c_q;
        carry_write_enable = 1'b0;
        overflow_set       = 1'b0;
        tc_next_w          = 1'b0;
        tc_wr_w            = 1'b0;

        case (i_op)
            OP_NOP: begin end

            /* --- do_add family (flags per do_add, s16 arm) --- */
            OP_ADD: begin
                acc_next           = add_sat;
                carry_write_enable = 1'b1;
                /* 16-bit form: carry sets C, otherwise C holds (do_add s16). */
                if (i_s16) begin
                    if (add_carry)
                        carry_next = 1'b1;
                    else
                        carry_next = c_q;
                end else begin
                    carry_next = add_carry;
                end
                overflow_set = add_ovf;
            end
            OP_ADDC: begin
                acc_next           = add_sat;
                carry_write_enable = 1'b1;
                carry_next         = add_carry;
                overflow_set       = add_ovf;
            end
            OP_ADD_B, OP_ADDC_B: begin
                acc_next           = add_sat;
                carry_write_enable = 1'b1;
                carry_next         = add_carry;
                overflow_set       = add_ovf;
            end
            OP_ADD_SH, OP_ADDT: begin
                acc_next           = add_sat;
                carry_write_enable = 1'b1;
                carry_next         = add_carry;
                overflow_set       = add_ovf;
            end
            OP_APAC: begin
                acc_next           = add_sat;
                carry_write_enable = 1'b1;
                carry_next         = add_carry;
                overflow_set       = add_ovf;
            end

            /* --- do_sub family (flags per do_sub, s16 arm) --- */
            OP_SUB: begin
                acc_next           = sub_sat;
                carry_write_enable = 1'b1;
                /* 16-bit form: borrow clears C, otherwise C holds (do_sub s16). */
                if (i_s16) begin
                    if (sub_borrow)
                        carry_next = 1'b0;
                    else
                        carry_next = c_q;
                end else begin
                    carry_next = ~sub_borrow;
                end
                overflow_set = sub_ovf;
            end
            OP_SUBB, OP_SUB_B: begin
                acc_next           = sub_sat;
                carry_write_enable = 1'b1;
                carry_next         = ~sub_borrow;
                overflow_set       = sub_ovf;
            end
            OP_SUB_SH, OP_SUBT: begin
                acc_next           = sub_sat;
                carry_write_enable = 1'b1;
                carry_next         = ~sub_borrow;
                overflow_set       = sub_ovf;
            end
            OP_SPAC: begin
                acc_next           = sub_sat;
                carry_write_enable = 1'b1;
                carry_next         = ~sub_borrow;
                overflow_set       = sub_ovf;
            end
            OP_SBBB: begin
                acc_next           = sbbb_res;
                carry_write_enable = 1'b1;
                carry_next         = ~sbbb_borrow;
            end

            /* --- logic (no flag effects in the C model) --- */
            OP_AND:      acc_next = acc_q & i_b32;
            OP_OR:       acc_next = acc_q | i_b32;
            OP_XOR:      acc_next = acc_q ^ i_b32;
            OP_AND_B:    acc_next = acc_q & accb_q;
            OP_OR_B:     acc_next = acc_q | accb_q;
            OP_XOR_B:    acc_next = acc_q ^ accb_q;

            /* --- direct loads --- */
            OP_LD_EXT:   acc_next = ext_result;
            OP_LACT: begin
                if (i_sxm)
                    acc_next = {{16{i_b16[15]}}, i_b16} << treg1_q[3:0];
                else
                    acc_next = {16'b0000000000000000, i_b16} << treg1_q[3:0];
            end
            OP_LD_B32:   acc_next = i_b32;
            OP_LD_B16Z:  acc_next = {16'b0000000000000000, i_b16};
            OP_LD_B16HI: acc_next = {i_b16, 16'b0000000000000000};
            OP_LD_ZALR:  acc_next = {i_b16, ZALR_LOW_HALF};
            OP_ACC_ZERO: acc_next = 32'b0;

            /* --- NEG / ABS / CMPL (exec_be_acc 0x00-0x02) --- */
            OP_CMPL: acc_next = ~acc_q;
            OP_NEG: begin
                if (acc_q == SAT_NEG) begin
                    overflow_set       = 1'b1;
                    carry_write_enable = 1'b1;
                    carry_next         = 1'b0;
                    if (i_ovm)
                        acc_next = SAT_POS;
                    else
                        acc_next = SAT_NEG;
                end else begin
                    acc_next           = ~acc_q + 32'd1;
                    carry_write_enable = 1'b1;
                    carry_next   = (acc_next == 32'b0);
                end
            end
            OP_ABS: begin
                if (acc_q == SAT_NEG) begin
                    overflow_set       = 1'b1;
                    carry_write_enable = 1'b1;
                    carry_next         = 1'b0;
                    if (i_ovm)
                        acc_next = SAT_POS;
                    else
                        acc_next = SAT_NEG;
                end else begin
                    if (acc_signed < 0)
                        acc_next           = ~acc_q + 32'd1;
                    carry_write_enable = 1'b1;
                    carry_next         = 1'b0;
                end
            end

            /* --- MAX / MIN / SWAP / SACB / LACB (exec_be_acc 0x1B-0x1F) --- */
            OP_MAX: begin
                carry_write_enable = 1'b1;
                if (acc_signed >= $signed(accb_q)) begin
                    accb_next  = acc_q;
                    carry_next = 1'b1;
                end else begin
                    acc_next   = accb_q;
                    carry_next = 1'b0;
                end
            end
            OP_MIN: begin
                carry_write_enable = 1'b1;
                if (acc_signed >= $signed(accb_q)) begin
                    acc_next   = accb_q;
                    carry_next = 1'b0;
                end else begin
                    accb_next  = acc_q;
                    carry_next = 1'b1;
                end
            end
            OP_SWAP: begin
                acc_next  = accb_q;
                accb_next = acc_q;
            end
            OP_SACB: accb_next = acc_q;
            OP_LACB: acc_next  = accb_q;

            /* --- SUBC divide step --- */
            OP_SUBC: begin
                carry_write_enable = 1'b1;
                carry_next         = ~subc_borrow;
                overflow_set       = subc_ovf;
                if (!subc_res[31])
                    acc_next = {subc_res[30:0], 1'b1};
                else
                    acc_next = {acc_q[30:0], 1'b0};
            end

            /*
            --- PREG-scaled ACC ops (PAC; APAC/SPAC live in the
            do_add/do_sub family arms above, sharing their engines) ---
            */
            OP_PAC:  acc_next = pscale_result;

            /*
            --- multiply-accumulate / load-TREG0 family ---
            preg_next / treg0_next are set per op below; the ACC arm
            reuses the add/sub engines (add_operand_b/sub_operand_b = pscale_result).
            */
            OP_MPYA: begin
                acc_next           = add_sat;
                preg_next          = o_mpy;
                carry_write_enable = 1'b1;
                carry_next         = add_carry;
                overflow_set       = add_ovf;
            end
            OP_MPYS: begin
                acc_next           = sub_sat;
                preg_next          = o_mpy;
                carry_write_enable = 1'b1;
                carry_next         = ~sub_borrow;
                overflow_set       = sub_ovf;
            end
            OP_SQRA: begin
                acc_next           = add_sat;
                preg_next          = o_mpy;
                treg0_next         = i_b16;
                carry_write_enable = 1'b1;
                carry_next         = add_carry;
                overflow_set       = add_ovf;
                if (!i_trm) begin
                    treg1_next = {11'b0, i_b16[TREG1_FIELD_TOP:0]};
                    treg2_next = {12'b0, i_b16[TREG2_FIELD_TOP:0]};
                end
            end
            OP_SQRS: begin
                acc_next           = sub_sat;
                preg_next          = o_mpy;
                treg0_next         = i_b16;
                carry_write_enable = 1'b1;
                carry_next         = ~sub_borrow;
                overflow_set       = sub_ovf;
                if (!i_trm) begin
                    treg1_next = {11'b0, i_b16[TREG1_FIELD_TOP:0]};
                    treg2_next = {12'b0, i_b16[TREG2_FIELD_TOP:0]};
                end
            end
            OP_LTA, OP_LTD: begin
                acc_next           = add_sat;
                treg0_next         = i_b16;
                carry_write_enable = 1'b1;
                carry_next         = add_carry;
                overflow_set       = add_ovf;
                if (!i_trm) begin
                    treg1_next = {11'b0, i_b16[TREG1_FIELD_TOP:0]};
                    treg2_next = {12'b0, i_b16[TREG2_FIELD_TOP:0]};
                end
            end
            OP_LTP: begin
                acc_next   = pscale_result;
                treg0_next = i_b16;
                if (!i_trm) begin
                    treg1_next = {11'b0, i_b16[TREG1_FIELD_TOP:0]};
                    treg2_next = {12'b0, i_b16[TREG2_FIELD_TOP:0]};
                end
            end
            OP_LTS: begin
                acc_next           = sub_sat;
                treg0_next         = i_b16;
                carry_write_enable = 1'b1;
                carry_next         = ~sub_borrow;
                overflow_set       = sub_ovf;
                if (!i_trm) begin
                    treg1_next = {11'b0, i_b16[TREG1_FIELD_TOP:0]};
                    treg2_next = {12'b0, i_b16[TREG2_FIELD_TOP:0]};
                end
            end
            OP_LT: begin
                treg0_next = i_b16;
                if (!i_trm) begin
                    treg1_next = {11'b0, i_b16[TREG1_FIELD_TOP:0]};
                    treg2_next = {12'b0, i_b16[TREG2_FIELD_TOP:0]};
                end
            end
            /*
            MADS/MADD no-mirror TREG0 load (KD-23; c5x_core.c:2083-2105):
            ACC += pscale(OLD PREG) via do_add (same arm as OP_APAC),
            TREG0 = dma, PREG = dma * pma (signed; the core drives
            i_mpy_a = dma, i_mpy_b = pma). TREG1/TREG2 are NOT
            written: the C model writes c->treg0 directly (audit N-1,
            :2092 -- no set_t0), so they hold even when TRM=0. The
            defaults above already hold them; this arm deliberately
            has no mirror block, unlike OP_LT and OP_LTA.
            */
            OP_LT_NM: begin
                acc_next           = add_sat;
                preg_next          = o_mpy;
                treg0_next         = i_b16;
                carry_write_enable = 1'b1;
                carry_next         = add_carry;
                overflow_set       = add_ovf;
            end

            /* --- PREG-only ops --- */
            OP_MPY, OP_MPYU: preg_next = o_mpy;
            OP_LPH:         preg_next = {i_b16, preg_q[15:0]};
            OP_PREG_ZERO:   preg_next = 32'b0;
            OP_ACC_PREG_ZERO: begin
                acc_next  = 32'b0;
                preg_next = 32'b0;
            end

            /* --- 1-bit shifts / rotates (exec_be_acc 0x09-0x0D) --- */
            OP_ROL: begin
                acc_next           = {acc_q[30:0], 1'b0};
                carry_write_enable = 1'b1;
                carry_next         = acc_q[31];
            end
            OP_ROR: begin
                /*
                C model: arithmetic shift when SXM=1, logical when 0
                (ROR is a shift, not a rotate: bit 31 is the sign).
                */
                if (i_sxm)
                    acc_next = {acc_q[31], acc_q[31:1]};
                else
                    acc_next           = {1'b0, acc_q[31:1]};
                carry_write_enable = 1'b1;
                carry_next         = acc_q[0];
            end
            OP_ROLC: begin
                acc_next           = {acc_q[30:0], c_q};
                carry_write_enable = 1'b1;
                carry_next         = acc_q[31];
            end
            OP_RORC: begin
                acc_next           = {c_q, acc_q[31:1]};
                carry_write_enable = 1'b1;
                carry_next         = acc_q[0];
            end

            /* --- 64-bit ACC:ACCB shifts / rotates (0x14-0x17) --- */
            OP_SFLB: begin
                acc_next           = {acc_q[30:0], accb_q[31]};
                accb_next          = {accb_q[30:0], 1'b0};
                carry_write_enable = 1'b1;
                carry_next         = acc_q[31];
            end
            OP_SFRB: begin
                accb_next = {acc_q[31], accb_q[31:1]};
                if (i_sxm)
                    acc_next = {acc_q[31], acc_q[31:1]};
                else
                    acc_next           = {1'b0, acc_q[31:1]};
                carry_write_enable = 1'b1;
                carry_next         = accb_q[0];
            end
            OP_ROLB: begin
                acc_next           = {acc_q[30:0], accb_q[31]};
                accb_next          = {accb_q[30:0], c_q};
                carry_write_enable = 1'b1;
                carry_next         = acc_q[31];
            end
            OP_RORB: begin
                accb_next          = {acc_q[31], accb_q[31:1]};
                acc_next           = {c_q, acc_q[31:1]};
                carry_write_enable = 1'b1;
                carry_next         = accb_q[0];
            end

            /* --- multi-bit shifts --- */
            OP_SFTA: begin
                /*
                BSAR/SFTA: ACC >>= (sh+1), sign per SXM (exec_bf).
                C untouched (KD-1: amount is sh+1 per the C model).
                */
                if (i_sxm)
                    acc_next = $unsigned(acc_signed >>> (i_shift[3:0] + SFTA_SHIFT_BIAS));
                else
                    acc_next = acc_q >> (i_shift[3:0] + SFTA_SHIFT_BIAS);
            end
            OP_SATH: begin
                /* SATH: if TREG1 bit 4 set, ACC >>= 16 (sign per SXM). */
                if (treg1_q[4]) begin
                    if (i_sxm)
                        acc_next = $unsigned(acc_signed >>> 16);
                    else
                        acc_next = acc_q >> 16;
                end
            end
            OP_SATL: begin
                /* SATL: ACC >>= (TREG1 & 0xF) (sign per SXM). */
                if (i_sxm)
                    acc_next = $unsigned(acc_signed >>> treg1_q[3:0]);
                else
                    acc_next = acc_q >> treg1_q[3:0];
            end
            OP_NORM: begin
                /*
                NORM: shift ACC left until bits 31/30 differ (or
                ACC == 0). TC=1 when done, else shift once, TC=0.
                */
                if ((acc_q == 32'b0) || (acc_q[31] ^ acc_q[30])) begin
                    tc_next_w = 1'b1;
                    tc_wr_w   = 1'b1;
                end else begin
                    acc_next  = {acc_q[30:0], 1'b0};
                    tc_next_w = 1'b0;
                    tc_wr_w   = 1'b1;
                end
            end

            default: begin end
        endcase
    end

    assign o_tc_next = tc_next_w;
    assign o_tc_wr   = tc_wr_w;

    /*
    ---------------------------------------------------------------
    Sequential state.
    ---------------------------------------------------------------
    */
    always_ff @(posedge clk) begin
        if (ce_i) begin
            if (!rst_n) begin
                acc_q   <= 32'b0;
                accb_q  <= 32'b0;
                preg_q  <= 32'b0;
                treg0_q <= 16'b0;
                treg1_q <= 16'b0;
                treg2_q <= 16'b0;
                c_q     <= 1'b1; /* c5x_reset: C=1 */
                ov_q    <= 1'b0; /* c5x_reset: OV=0 */
            end else begin
                if (i_exec) begin
                    if (i_ld_acc)   acc_q   <= acc_next;
                    if (i_ld_accb)  accb_q  <= accb_next;
                    if (i_ld_preg)  preg_q  <= preg_next;
                    if (i_ld_treg0) begin
                        treg0_q <= treg0_next;
                        treg1_q <= treg1_next;
                        treg2_q <= treg2_next;
                    end
                    if (carry_write_enable)  c_q  <= carry_next;
                    if (overflow_set) ov_q <= 1'b1;
                end
                /* Shadow-context restore: explicit loads, no mirror (TREG1/TREG2 are restored from their own shadows). */
                if (i_rs_acc)     acc_q   <= i_rs_acc_d;
                if (i_rs_accb)    accb_q  <= i_rs_accb_d;
                if (i_rs_preg)    preg_q  <= i_rs_preg_d;
                if (i_rs_treg[0]) treg0_q <= i_rs_treg_d;
                if (i_rs_treg[1]) treg1_q <= i_rs_treg_d;
                if (i_rs_treg[2]) treg2_q <= i_rs_treg_d;
                /* Explicit flag loads (LST) win over op-driven updates. */
                if (i_flag_c_we)  c_q  <= i_flag_c_in;
                if (i_flag_ov_we) ov_q <= i_flag_ov_in;
            end
        
        end
    end

endmodule

`default_nettype wire
