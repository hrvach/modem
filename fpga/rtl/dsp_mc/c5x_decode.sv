/*
c5x_decode.sv -- TMS320C5x instruction decoder (combinational lookup).
Function: the decode half of the TMS320C5x DSP core port for Cyclone V;
  turns one 16-bit opcode word into the micro-op, operand fields and
  base cycle count from c5x_cyctab.h.
Talks to: c5x_ctrl (which consumes alu_op_o / words_o / cycles_o and
  the class flags); c5x_ctl_pkg (opcode enum, cycle table, cond()).
Does not model: cycle-count adjustments (class-1/class-2 taken and
  not-taken, IN/OUT wait states, interrupt entry) -- those are the
  ctrl's job; operand fetch; any architectural state.
Source: research_notes/courier-firmware/c-port/c/src/dsp/c5x_core.c
  (exec1_op dispatch ladder, exec_hi_* families, exec_be/exec_bf)
  and c5x_cyctab.h (cycle counts, verbatim in c5x_cyctab()).
  Audit verdicts are recorded in c5x_ctl_pkg.sv KNOWN-DIFF, not
  applied here.
*/

/*
Interface (matches the top level's assumed u_decode port list in
c5x_core.sv -- see c5x_ctl_pkg.sv OPEN-4 for the known deltas):
  instr_i  : the 16-bit opcode word.
  instr2_i : the second word of a 2-word instruction.  NOT USED by
             the decode itself (alu_op / words / cycles / flags are
             all functions of the opcode alone); it is carried so
             the top level can present both fetched words to the
             decoder in one place.  The ctrl reads the immediate
             from its own imm_q register, not from here.
  clk/rst_n: carried for the top-level v1 contract only.  The
             decoder is purely combinational and uses neither.
Outputs (see c5x_ctl_pkg.sv c5x_dec_t for the bundle definition):
  alu_op_o [6:0] : c5x_alu_op_e micro-op (OP_NOP when the
             instruction does not use the ALU).
  words_o  [1:0] : instruction length in words (1 or 2).
  cycles_o [7:0] : BASE cycle count from c5x_cyctab.h.  The ctrl
             applies the instr_cycles() adjustments on top (class-1
             taken/not-taken, class-2 RETCD seq, IN/OUT wait
             states).
  ea_mode_o[7:0] : addressing-mode field = opcode[7:0].
  is_branch_o / is_call_o / is_ret_o / is_rpt_o / is_rptb_o /
  is_idle_o / is_io_o / is_mem_wr_o / is_pm_wr_o / badop_o.
  badop_o = 1 exactly when the C exec1_op sets RUN_BADOP for the
  opcode (0x56, 0xA1, unlisted 0xBE low bytes, unlisted 0xBF low
  bytes).  A BADOP still reports its cyctab cycle count (the C
  model charges cycm[op] before the run loop halts with pc
  restored to ppc).
*/

/*
Word counts (2-word forms -- the immediate / port / pma word is
fetched by the ctrl in FSM_FETCH2_*):
  SMMR, OUT, XPL/OPL/APL/CPL #lk, B/CALL/BANZ/BD/CALLD/BANZD,
  LMMR, MAC/MACD, BLPD #pma, BLDD #lk, SPLK, IN, MPY/AND/OR/XOR
  #lk (0xBE80-83), RPT #lk / RPTZ #lk / RPTB (0xBEC4-6),
  LAR #lk (0xBF08-0F), long-immediate ALU (0xBF80-DF),
  BCND, CC, BCNDD, CCD.  All other opcodes (including every
  BADOP) are 1 word.
*/

/*
is_mem_wr = the instruction performs a C dm_wr() (unified data
write: MMR / internal DMEM / host window / external -> PMEM).
is_pm_wr  = the instruction performs a C pm_wr() (direct
program-space write: BLDP and TBLW only).  SMMR writes through
the dm port (is_mem_wr=1) even though the word lands in PMEM via
the unified map.
*/

`default_nettype none

module c5x_decode (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] instr_i,
    input  logic [15:0] instr2_i,
    output logic [6:0]  alu_op_o,
    output logic [1:0]  words_o,
    output logic [7:0]  cycles_o,
    output logic [7:0]  ea_mode_o,
    output logic        is_branch_o,
    output logic        is_call_o,
    output logic        is_ret_o,
    output logic        is_rpt_o,
    output logic        is_rptb_o,
    output logic        is_idle_o,
    output logic        is_io_o,
    output logic        is_mem_wr_o,
    output logic        is_pm_wr_o,
    output logic        badop_o
);
    import c5x_ctl_pkg::*;

    /*
    clk / rst_n / instr2_i are carried for the top-level v1
    contract; the decoder is combinational and does not use them.
    */
    /* verilator lint_off UNUSEDSIGNAL */
    logic unused_clk_rst;
    assign unused_clk_rst = clk & rst_n & (|instr2_i);
    /* verilator lint_on UNUSEDSIGNAL */

    logic [7:0] hi;
    logic [7:0] lo;
    assign hi = instr_i[15:8];
    assign lo = instr_i[7:0];

    always_comb begin
        /*
        Defaults: 1 word, OP_NOP, no flags.  Every branch below
        overrides what it needs; there are no latches.
        */
        alu_op_o    = ALU_NOP;
        words_o     = 2'd1;
        cycles_o    = c5x_cyctab(instr_i);
        ea_mode_o   = lo;
        is_branch_o = 1'b0;
        is_call_o   = 1'b0;
        is_ret_o    = 1'b0;
        is_rpt_o    = 1'b0;
        is_rptb_o   = 1'b0;
        is_idle_o   = 1'b0;
        is_io_o     = 1'b0;
        is_mem_wr_o = 1'b0;
        is_pm_wr_o  = 1'b0;
        badop_o     = 1'b0;

        case (hi)
            /*
            ------------------------------------------------------
            0x00-0x0F: LAR / LAMM / SMMR / SUBC / RPT / OUT /
                       LDP / LST
            ------------------------------------------------------
            */
            8'h00, 8'h01, 8'h02, 8'h03,
            8'h04, 8'h05, 8'h06, 8'h07: begin
                alu_op_o = ALU_NOP; /* LAR dma */
            end
            8'h08: alu_op_o = ALU_LD_B16Z; /* LAMM */
            8'h09: begin
                words_o     = 2'd2; /* SMMR (pfc fetch) */
                is_mem_wr_o = 1'b1;
            end
            8'h0A: alu_op_o = ALU_SUBC; /* SUBC */
            8'h0B: is_rpt_o = 1'b1; /* RPT dma */
            8'h0C: begin
                words_o = 2'd2; /* OUT (port fetch) */
                is_io_o = 1'b1;
            end
            8'h0D: begin end /* LDP dma */
            8'h0E, 8'h0F: begin end /* LST #0 / #1 */

            /*
            ------------------------------------------------------
            0x10-0x3F: LACC / ADD / SUB dma,sh (shift = hi & 0xF)
            ------------------------------------------------------
            */
            8'h10, 8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17,
            8'h18, 8'h19, 8'h1A, 8'h1B, 8'h1C, 8'h1D, 8'h1E, 8'h1F:
                alu_op_o = ALU_LD_EXT; /* LACC dma,sh */
            8'h20, 8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26, 8'h27,
            8'h28, 8'h29, 8'h2A, 8'h2B, 8'h2C, 8'h2D, 8'h2E, 8'h2F:
                alu_op_o = ALU_ADD_SH; /* ADD dma,sh */
            8'h30, 8'h31, 8'h32, 8'h33, 8'h34, 8'h35, 8'h36, 8'h37,
            8'h38, 8'h39, 8'h3A, 8'h3B, 8'h3C, 8'h3D, 8'h3E, 8'h3F:
                alu_op_o = ALU_SUB_SH; /* SUB dma,sh */

            /*
            ------------------------------------------------------
            0x40-0x4F: BIT (TC = bit 15-shift of dma; ctrl computes)
            ------------------------------------------------------
            */
            8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h46, 8'h47,
            8'h48, 8'h49, 8'h4A, 8'h4B, 8'h4C, 8'h4D, 8'h4E, 8'h4F:
                alu_op_o = ALU_NOP;

            /*
            ------------------------------------------------------
            0x50-0x5F: MPY forms, BLDP, DBMR / #lk logic ops
            ------------------------------------------------------
            */
            8'h50: alu_op_o = ALU_MPYA;
            8'h51: alu_op_o = ALU_MPYS;
            8'h52: alu_op_o = ALU_SQRA;
            8'h53: alu_op_o = ALU_SQRS;
            8'h54: alu_op_o = ALU_MPY;
            8'h55: alu_op_o = ALU_MPYU;
            8'h56: badop_o = 1'b1;
            8'h57: is_pm_wr_o = 1'b1; /* BLDP (pm_wr loop) */
            8'h58: begin
                alu_op_o    = ALU_XOR; /* XPL dbmr */
                is_mem_wr_o = 1'b1;
            end
            8'h59: begin
                alu_op_o    = ALU_OR; /* OPL dbmr */
                is_mem_wr_o = 1'b1;
            end
            8'h5A: begin
                alu_op_o    = ALU_AND; /* APL dbmr */
                is_mem_wr_o = 1'b1;
            end
            8'h5B: alu_op_o = ALU_NOP; /* CPL dbmr (compare, no write) */
            8'h5C: begin
                alu_op_o    = ALU_XOR; /* XPL #lk */
                words_o     = 2'd2;
                is_mem_wr_o = 1'b1;
            end
            8'h5D: begin
                alu_op_o    = ALU_OR; /* OPL #lk */
                words_o     = 2'd2;
                is_mem_wr_o = 1'b1;
            end
            8'h5E: begin
                alu_op_o    = ALU_AND; /* APL #lk */
                words_o     = 2'd2;
                is_mem_wr_o = 1'b1;
            end
            8'h5F: begin
                words_o = 2'd2; /* CPL #lk (compare, no write) */
            end

            /*
            ------------------------------------------------------
            0x60-0x7F: ADD/SUB variants, loads, logic, branches
            ------------------------------------------------------
            */
            8'h60: alu_op_o = ALU_ADDC; /* ADDC */
            8'h61: alu_op_o = ALU_ADD; /* ADD dma,16 (ctrl sets s16) */
            8'h62: alu_op_o = ALU_ADD; /* ADDS */
            8'h63: alu_op_o = ALU_ADDT; /* ADDT */
            8'h64: alu_op_o = ALU_SUBB; /* SUBB */
            8'h65: alu_op_o = ALU_SUB; /* SUB dma,16 (ctrl sets s16) */
            8'h66: alu_op_o = ALU_SUB; /* SUBS */
            8'h67: alu_op_o = ALU_SUBT; /* SUBT */
            8'h68: alu_op_o = ALU_LD_ZALR; /* ZALR */
            8'h69: alu_op_o = ALU_LD_B16Z; /* LACL dma */
            8'h6A: alu_op_o = ALU_LD_B16HI; /* LACC dma,16 */
            8'h6B: alu_op_o = ALU_LACT; /* LACT */
            8'h6C: alu_op_o = ALU_XOR; /* XOR dma */
            8'h6D: alu_op_o = ALU_OR; /* OR dma */
            8'h6E: alu_op_o = ALU_AND; /* AND dma */
            8'h6F: alu_op_o = ALU_NOP; /* BITT (TC, ctrl computes) */
            8'h70: alu_op_o = ALU_LTA; /* LTA */
            8'h71: alu_op_o = ALU_LTP; /* LTP */
            8'h72: begin
                alu_op_o    = ALU_LTD; /* LTD */
                is_mem_wr_o = 1'b1; /* DMOV dma -> dma+1 */
            end
            8'h73: alu_op_o = ALU_LT; /* LT */
            8'h74: alu_op_o = ALU_LTS; /* LTS */
            8'h75: alu_op_o = ALU_LPH; /* LPH */
            8'h76: alu_op_o = ALU_NOP; /* PSHD */
            8'h77: is_mem_wr_o = 1'b1; /* DMOV */
            8'h78: alu_op_o = ALU_NOP; /* ADRK */
            8'h79: begin
                words_o     = 2'd2; /* B (imm fetch; ea side effects) */
                is_branch_o = 1'b1;
            end
            8'h7A: begin
                words_o   = 2'd2; /* CALL */
                is_call_o = 1'b1;
            end
            8'h7B: begin
                words_o     = 2'd2; /* BANZ */
                is_branch_o = 1'b1;
            end
            8'h7C: alu_op_o = ALU_NOP; /* SBRK */
            8'h7D: begin
                words_o     = 2'd2; /* BD */
                is_branch_o = 1'b1;
            end
            8'h7E: begin
                words_o   = 2'd2; /* CALLD */
                is_call_o = 1'b1;
            end
            8'h7F: begin
                words_o     = 2'd2; /* BANZD */
                is_branch_o = 1'b1;
            end

            /*
            ------------------------------------------------------
            0x80-0x9F: SAR / SAMM / LMMR / POPD / MAR / SPL / SPH /
                       SST / SACL / SACH
            ------------------------------------------------------
            */
            8'h80, 8'h81, 8'h82, 8'h83, 8'h84, 8'h85, 8'h86, 8'h87:
                is_mem_wr_o = 1'b1; /* SAR */
            8'h88: is_mem_wr_o = 1'b1; /* SAMM */
            8'h89: begin
                words_o     = 2'd2; /* LMMR (pfc fetch) */
                is_mem_wr_o = 1'b1;
            end
            8'h8A: is_mem_wr_o = 1'b1; /* POPD */
            8'h8B: begin end /* MAR */
            8'h8C, 8'h8D: is_mem_wr_o = 1'b1; /* SPL / SPH */
            8'h8E, 8'h8F: is_mem_wr_o = 1'b1; /* SST #0 / #1 */
            8'h90, 8'h91, 8'h92, 8'h93, 8'h94, 8'h95, 8'h96, 8'h97,
            8'h98, 8'h99, 8'h9A, 8'h9B, 8'h9C, 8'h9D, 8'h9E, 8'h9F:
                is_mem_wr_o = 1'b1; /* SACL / SACH */

            /*
            ------------------------------------------------------
            0xA0-0xAF: NORM / MAC / BLPD / TBLR / TBLW / BLDD /
                       MADS / MADD / SPLK / IN
            ------------------------------------------------------
            */
            8'hA0: alu_op_o = ALU_NORM; /* NORM */
            8'hA1: badop_o = 1'b1;
            8'hA2: begin
                alu_op_o = ALU_APAC; /* MAC (acc += pscale) */
                words_o  = 2'd2; /* pma fetch */
            end
            8'hA3: begin
                alu_op_o    = ALU_APAC; /* MACD */
                words_o     = 2'd2;
                is_mem_wr_o = 1'b1; /* DMOV */
            end
            8'hA4: is_mem_wr_o = 1'b1; /* BLPD bmar */
            8'hA5: begin
                words_o     = 2'd2; /* BLPD #pma */
                is_mem_wr_o = 1'b1;
            end
            8'hA6: is_mem_wr_o = 1'b1; /* TBLR */
            8'hA7: is_pm_wr_o = 1'b1; /* TBLW (pm_wr loop) */
            8'hA8, 8'hA9: begin
                words_o     = 2'd2; /* BLDD #lk */
                is_mem_wr_o = 1'b1;
            end
            8'hAA: alu_op_o = ALU_APAC; /* MADS */
            8'hAB: begin
                alu_op_o    = ALU_APAC; /* MADD */
                is_mem_wr_o = 1'b1; /* DMOV */
            end
            8'hAC, 8'hAD: is_mem_wr_o = 1'b1; /* BLDD bmar */
            8'hAE: begin
                words_o     = 2'd2; /* SPLK (ea before imm fetch) */
                is_mem_wr_o = 1'b1;
            end
            8'hAF: begin
                words_o     = 2'd2; /* IN (port fetch) */
                is_io_o     = 1'b1;
                is_mem_wr_o = 1'b1;
            end

            /*
            ------------------------------------------------------
            0xB0-0xBF: LAR #k8 / ADDK / LACK / SUBK / RPT #k8 /
                       LDP #k9 / 0xBE / 0xBF sub-decoders
            ------------------------------------------------------
            */
            8'hB0, 8'hB1, 8'hB2, 8'hB3, 8'hB4, 8'hB5, 8'hB6, 8'hB7:
                alu_op_o = ALU_NOP; /* LAR #k8 */
            8'hB8: alu_op_o = ALU_ADD; /* ADDK */
            8'hB9: alu_op_o = ALU_LD_B16Z; /* LACK */
            8'hBA: alu_op_o = ALU_SUB; /* SUBK */
            8'hBB: is_rpt_o = 1'b1; /* RPT #k8 */
            8'hBC, 8'hBD: begin end /* LDP #k9 */
            8'hBE: begin
                /*
                0xBE sub-decoder on the low byte.
                */
                if (lo < 8'h20) begin
                    /*
                    Accumulator ops (exec_be_acc).
                    */
                    case (lo)
                        8'h00: alu_op_o = ALU_ABS;
                        8'h01: alu_op_o = ALU_CMPL;
                        8'h02: alu_op_o = ALU_NEG;
                        8'h03: alu_op_o = ALU_PAC;
                        8'h04: alu_op_o = ALU_APAC;
                        8'h05: alu_op_o = ALU_SPAC;
                        8'h09: alu_op_o = ALU_ROL;
                        8'h0A: alu_op_o = ALU_ROR;
                        8'h0C: alu_op_o = ALU_ROLC;
                        8'h0D: alu_op_o = ALU_RORC;
                        8'h10: alu_op_o = ALU_ADD_B;
                        8'h11: alu_op_o = ALU_ADDC_B;
                        8'h12: alu_op_o = ALU_AND_B;
                        8'h13: alu_op_o = ALU_OR_B;
                        8'h14: alu_op_o = ALU_ROLB;
                        8'h15: alu_op_o = ALU_RORB;
                        8'h16: alu_op_o = ALU_SFLB;
                        8'h17: alu_op_o = ALU_SFRB;
                        8'h18: alu_op_o = ALU_SUB_B;
                        8'h19: alu_op_o = ALU_SBBB;
                        8'h1A: alu_op_o = ALU_XOR_B;
                        8'h1B: alu_op_o = ALU_MAX;
                        8'h1C: alu_op_o = ALU_MIN;
                        8'h1D: alu_op_o = ALU_SWAP;
                        8'h1E: alu_op_o = ALU_SACB;
                        8'h1F: alu_op_o = ALU_LACB;
                        default: badop_o = 1'b1; /* 06,07,08,0B,0E,0F */
                    endcase
                end else begin
                    /*
                    Control ops (exec_be_ctrl).
                    */
                    case (lo)
                        8'h20: is_branch_o = 1'b1; /* BACC */
                        8'h21: is_branch_o = 1'b1; /* BACCD */
                        8'h22: is_idle_o = 1'b1; /* IDLE */
                        8'h23: is_idle_o = 1'b1; /* IDLE2 */
                        8'h30: is_call_o = 1'b1; /* CALA */
                        8'h32: alu_op_o = ALU_LD_B16Z; /* POP */
                        8'h38: is_ret_o = 1'b1; /* RETI */
                        8'h3A: is_ret_o = 1'b1; /* RETE */
                        8'h3C: begin end /* PSHA */
                        8'h3D: is_call_o = 1'b1; /* CALAD */
                        8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45,
                        8'h46, 8'h47, 8'h48, 8'h49, 8'h4A, 8'h4B,
                        8'h4C, 8'h4D, 8'h4E, 8'h4F: begin end
                        8'h51, 8'h52: begin end /* TRAP / NMI */
                        8'h58: alu_op_o = ALU_PREG_ZERO;
                        8'h59: alu_op_o = ALU_ACC_PREG_ZERO;
                        8'h5A: alu_op_o = ALU_SATH;
                        8'h5B: alu_op_o = ALU_SATL;
                        8'h80: begin
                            alu_op_o = ALU_MPY; /* MPY #lk */
                            words_o  = 2'd2;
                        end
                        8'h81: begin
                            alu_op_o = ALU_AND; /* AND #lk,16 */
                            words_o  = 2'd2;
                        end
                        8'h82: begin
                            alu_op_o = ALU_OR; /* OR #lk,16 */
                            words_o  = 2'd2;
                        end
                        8'h83: begin
                            alu_op_o = ALU_XOR; /* XOR #lk,16 */
                            words_o  = 2'd2;
                        end
                        8'hC4: begin
                            is_rpt_o = 1'b1; /* RPT #lk */
                            words_o  = 2'd2;
                        end
                        8'hC5: begin
                            alu_op_o = ALU_ACC_PREG_ZERO; /* RPTZ #lk */
                            is_rpt_o = 1'b1;
                            words_o  = 2'd2;
                        end
                        8'hC6: begin
                            is_rptb_o = 1'b1; /* RPTB */
                            words_o   = 2'd2;
                        end
                        default: begin
                            /*
                            INTR k: (lo & 0xE0) == 0x60.
                            */
                            if ((lo & 8'hE0) == 8'h60) begin
                                /*
                                INTR k (software interrupt)
                                */
                            end else begin
                                badop_o = 1'b1;
                            end
                        end
                    endcase
                end
            end
            8'hBF: begin
                /*
                0xBF sub-decoder on the low byte.
                */
                if (lo <= 8'h03) begin
                    /*
                    SPM k
                    */
                end else if (lo >= 8'h08 && lo <= 8'h0F) begin
                    words_o = 2'd2; /* LAR #lk */
                end else if (lo >= 8'h44 && lo <= 8'h47) begin
                    /*
                    CMPR (TC, ctrl computes)
                    */
                end else if (lo >= 8'h80 && lo <= 8'hDF) begin
                    /*
                    Long-immediate ALU: LACC/ADD/SUB/AND/OR/XOR
                    #lk,sh (sh = lo[3:0]); 2 words.
                    */
                    words_o = 2'd2;
                    case (lo[7:4])
                        4'h8: alu_op_o = ALU_LD_EXT;
                        4'h9: alu_op_o = ALU_ADD_SH;
                        4'hA: alu_op_o = ALU_SUB_SH;
                        4'hB: alu_op_o = ALU_AND;
                        4'hC: alu_op_o = ALU_OR;
                        4'hD: alu_op_o = ALU_XOR;
                        default: badop_o = 1'b1;
                    endcase
                end else if (lo >= 8'hE0 && lo <= 8'hEF) begin
                    alu_op_o = ALU_SFTA; /* SFTA (shift = sh+1) */
                end else begin
                    badop_o = 1'b1;
                end
            end

            /*
            ------------------------------------------------------
            0xC0-0xDF: MPY #k13 (signed 13-bit imm x TREG0)
            ------------------------------------------------------
            */
            8'hC0, 8'hC1, 8'hC2, 8'hC3, 8'hC4, 8'hC5, 8'hC6, 8'hC7,
            8'hC8, 8'hC9, 8'hCA, 8'hCB, 8'hCC, 8'hCD, 8'hCE, 8'hCF,
            8'hD0, 8'hD1, 8'hD2, 8'hD3, 8'hD4, 8'hD5, 8'hD6, 8'hD7,
            8'hD8, 8'hD9, 8'hDA, 8'hDB, 8'hDC, 8'hDD, 8'hDE, 8'hDF:
                alu_op_o = ALU_MPY;

            /*
            ------------------------------------------------------
            0xE0-0xFF: conditional branches/calls/returns, XC
            ------------------------------------------------------
            */
            8'hE0, 8'hE1, 8'hE2, 8'hE3: begin
                words_o     = 2'd2; /* BCND (imm fetch) */
                is_branch_o = 1'b1;
            end
            8'hE4, 8'hE5, 8'hE6, 8'hE7: begin end /* XC */
            8'hE8, 8'hE9, 8'hEA, 8'hEB: begin
                words_o   = 2'd2; /* CC (imm fetch) */
                is_call_o = 1'b1;
            end
            8'hEC, 8'hED, 8'hEE, 8'hEF: is_ret_o = 1'b1; /* RETC */
            8'hF0, 8'hF1, 8'hF2, 8'hF3: begin
                words_o     = 2'd2; /* BCNDD (imm fetch) */
                is_branch_o = 1'b1;
            end
            8'hF4, 8'hF5, 8'hF6, 8'hF7: begin end /* XC */
            8'hF8, 8'hF9, 8'hFA, 8'hFB: begin
                words_o   = 2'd2; /* CCD (imm fetch) */
                is_call_o = 1'b1;
            end
            8'hFC, 8'hFD, 8'hFE, 8'hFF: is_ret_o = 1'b1; /* RETCD */
            default: begin end
        endcase
    end

endmodule

`default_nettype wire
