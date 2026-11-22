`default_nettype none

/*
c5x_ctl_pkg.sv -- shared control-bundle package for the TMS320C5x
DSP core (Cyclone V).  Published by module agent 3 (decode + ctrl);
every other module implements against this package.
Function: the single source of truth for the control bundle -- ALU op
  enum, flag/write selects, decode descriptor, FSM state enum,
  interrupt vectors, cond(), and the verbatim cycle table.
Talks to: every DSP core module (decode, ctrl, ALU, address unit,
  memory); the top level and the co-sim harness read the same package.
Does not model: any hardware itself -- constants, types and pure
  functions only; no state, no clocks, no reset.
Source: research_notes/courier-firmware/c-port/c/src/dsp/c5x_core.c
  (C port of the audited core; the cycle table is c5x_cyctab.h);
  research_notes/courier-firmware/c5x_core_audit/07b, 07c, 07d,
  07-core3-fix-list.md (53 entries; the RTL matches the CURRENT C
  code -- see KNOWN-DIFF below, scored against the CURRENT C code,
  not the core-3 audit snapshot).
*/

/*
TIMING CONTRACT (pipelined core, converged plan 2026-11-20; replaces
the multi-cycle contract below it -- the multi-cycle FSM is deleted,
kept as reference in hidden_files/pre-pipeline/):
- Four stages F/D/R/E, one instruction per clock in steady state.
  Fetch is 1-clock-latency pipelined: the address is presented in
  one clock, the word is valid during the next.  The DMEM-operand
  read is presented in R, its data is valid during E and is
  consumed combinationally there (mem's read data is registered at
  the R->E edge, so the R/E register cannot latch the operand).
  Deferred reads (DRR 0x20, SPC/TIM/TCR/IFR, 0x50+) are serviced
  in E through mem's E read port, combinationally.
- A "machine cycle" is a LOGICAL count (the C model's c->cycles),
  not a clock.  cycles_o advances by the computed C-model charge
  at the retire edge only (retire-time cycle computation, ported
  term-by-term from the multi-cycle cyc_acc_q logic).  It is
  verification bookkeeping only and drives no peripheral.
- The timer is C's wall-clock tick_timer (in c5x_mem.sv): it ticks
  every wall clock, independent of model cycles.  There is NO
  model-cycle timer in this core (B1 -- never reintroduce it).
  While IDLE/IDLE2 the pipeline is parked, cycles_o advances by 1
  per wall clock (the C model fast-forwards idle time the same
  way), the wall-clock timer keeps ticking in IDLE, and in IDLE2
  the timer is frozen (mem i_idle2_freeze).
- step_i is a fetch hold: low stops F from issuing fetches; the
  in-flight instructions complete and retire; no retire pulses
  once the pipeline drains.
- instr_done is a 1-clock registered retire pulse.  At 1 retire
  per clock it stays high across consecutive retires, so a
  once-per-clock sampler cannot count retires from its rising
  edges (Nyquist); the exact count is retire_cnt_o, and
  retire_tgl_o toggles at every retire edge.  The co-sim harness
  must count retires from retire_cnt_o (see docs/cosim.md).
- Single clock domain, active-low synchronous reset.  No gated
  clocks.  No Quartus primitives; inference-friendly RTL only,
  verified with Yosys synth_intel_alm -family cyclonev.
- Multi-cycle contract (superseded, kept for the reference core):
  one instruction took exactly its C-model cycle count; the FSM
  spent as many clocks as an instruction needed and advanced
  cycles_o by the C-model count when the instruction completed;
  the timer was advanced by the same count through mtick_en/
  mtick_n.  While IDLE/IDLE2, cycles_o advanced by 1 per clock
  and the timer advanced with it, EXCEPT in IDLE2 where the
  timer was frozen.
*/

/*
CONTROL BUNDLE (what the FSM produces, and when):
The bundle is expressed as the discrete ports of c5x_ctrl (see
c5x_core.sv u_ctrl) because the top level wires discrete signals.
The struct c5x_ctl_t below is the canonical definition of those
signals; each field documents its meaning and its active cycles.
Signal timing is stated per FSM state; "EXEC" means the clock in
which the instruction's datapath action commits (S_EXEC or
S_OP_DATA, see c5x_ctrl.sv).
*/

/*
  alu_op   [6:0]  c5x_alu_op_e micro-op for the ALU.  Valid during
                  EXEC.  For instructions that do not use the ALU,
                  OP_NOP.
  alu_a    [31:0] A operand (usually ACC).  Valid during EXEC.
  alu_b    [31:0] B operand (usually the shifted/extended data
                  word).  Valid during EXEC.
  alu_d    [15:0] D operand (raw 16-bit data word, e.g. for
                  OP_LD_EXT / shifts).  Valid during EXEC.
  alu_sh   [3:0]  Shift amount (0-15).  Valid during EXEC.
                  NOTE: the top level declares alu_sh [1:0]; that
                  is too narrow (shifts run 0-15) and must be
                  widened to [3:0] -- see OPEN-1.
  alu_c_in        Carry-in for ADDC/SUBB.  Valid during EXEC.
  alu_en          Strobes the ALU combinational result (alu_y /
                  alu_c / alu_ov / mpy_p) for this EXEC clock.
  acc_ld          Load ACC at the EXEC edge.  acc_data selects the
                  value: acc_ld_sel=0 -> alu_y, 1 -> acc_data.
  accb_ld / accb_data, preg_ld / preg_data: same for ACCB / PREG.
  treg_ld  [2:0]  Load TREG0/1/2 at the EXEC edge (bitmask); the
                  value is treg_data.  A set_t0 write asserts only
                  bit 0 (TREG0) and the ALU mirrors TREG1/TREG2
                  from it per the C set_t0() rule (unless TRM);
                  an independent TREG1/TREG2 restore asserts bits
                  1/2 on separate clocks (see c5x_ctrl.sv, RETI).
  mpy_en / mpy_a / mpy_b: 16x16 multiply request; mpy_p is the
                  32-bit product, valid during EXEC.
  ea_en / ea_op  Pulse ea_en for exactly one clock (S_OP_ADDR or
                  the fetch state for side-effect-only ea()) with
                  ea_op = opcode[7:0]; ea_i is the effective
                  address during that clock; the AR/ARP update
                  commits at the edge ending the clock.
  ar_wr_en / ar_wr_sel[2:0] / ar_wr_data: write AR[sel] (LAR,
                  ADRK/SBRK via the addr agent's AR update).
  ar_rd_sel[2:0]: select AR for ar_rd_i (SAR source, CMPR/BANZ
                  use the addr agent's o_ar = AR[ARP] instead).
  push_en / push_data, pop_en / pop_data: hardware stack.
                  pop_data is the combinational top of stack.
  rptc_ld_en / rptc_ld_data, rptc_dec_en: RPTC load / decrement
                  (loop-op iteration accounting).  rptc_i is the
                  live signed RPTC from the addr agent.
  st0_ld_en / st0_ld_data, st1_ld_en / st1_ld_data,
  pmst_ld_en / pmst_ld_data: whole-word ST0/ST1/PMST loads
                  (LST #0/#1, shadow restore).
  st_bit_en / st_bit_sel[4:0] / st_bit_val: single status-bit
                  write (SETC/CLRC, ..., TC from BIT/BITT/CPL,
                  OV clear on taken BCND/CC, INTM, XF, ...).
                  Selects are the FLG_* values below (agent 2).
  rptb_set_en / rptb_pasr / rptb_paer: install an RPTB block
                  (pasr = block-start PC, paer = last block word).
                  RPTB does NOT load BRCR (C model); rptb_brcr is
                  driven 0 -- see OPEN-2.
  rptb_clr_en: clear BRAF (block exit).
  brcr_ld_en / brcr_ld_data: load BRCR (MMR write routing).
  dm_req / dm_wr / dm_addr / dm_wdata: unified data-memory port
                  (MMR / internal DMEM / host window / external
                  -> PMEM, exactly as the C dm_wr()).  dm_rdata is
                  the read data (MMR-muxed by the top level).
  pm_d_req / pm_d_wr / pm_d_addr / pm_d_wdata: direct
                  program-space port (C pm_wr(), CNF/RAM overlays).
                  Used ONLY by BLDP and TBLW.  pm_d_rdata is the
                  program-space read data (C pm_rd()).
  mtick_en / mtick_n[7:0]: advance the timer by mtick_n machine
                  cycles (closed form, C advance_timer()).
  io_req_c / io_wr_c / io_port_c / io_wdata_c: IO request to the
                  mem agent (IN/OUT and host-window pseudo-ports).
                  io_rdata_c / io_ack_c return data / completion.
                  The FSM stalls in S_IO_WAIT until io_ack_c.
                  io_ws_i is the wait-state count for the access
                  (mem agent, from IOWSR/CWSR); the cycle charge
                  is IN = 2+io_ws, OUT = 3+(io_ws>1 ? io_ws-1 : 0).
  irq_ack_o[8:0]: one-hot IFR-bit clear to the mem agent on
                  interrupt entry (set wins over clear if the irq
                  line is still asserted -- C glue re-raises it).
  ndx_commit_o: pulse once at the end of each instruction (and
                  after each delay-slot word) to apply the NDX
                  mirror (C apply_ar0_mirror()).
  instr_done: pulses for one clock when an instruction completes,
                  AFTER the whole post-instruction tail (RPT/RPTB,
                  timer advance, XC hold, and the interrupt entry
                  with its 4-cycle charge when taken).
  cycles_o[63:0]: the C-model cycle counter; equals C c->cycles
                  after every instr_done.
  pc_o / op_o: architectural PC / last opcode after the last
                  instr_done.  idle_o: in IDLE/IDLE2.
  bmar_o / dbmr_o / indx_o / arcr_o: pass-throughs of the addr
                  agent's registers (top-level observation + MMR
                  readback mux).
*/

/*
INTERRUPT ENTRY (C check_int(), exactly):
- Highest-priority pending unmasked interrupt, lowest IFR bit
  first (ivec[] = 02,04,06,08,0A,0C,0E,10,12 for bits 0..8).
- Entry: intm=1, push PC, pc = ivec_ind[i] ? dm_rd(ivec_ind[i])
  : (iptr<<11)|ivec[i]; clear IFR bit i; wake from IDLE; save_ctx
  to the shadow registers; costs 4 machine cycles (each ticks the
  timer).  save_ctx saves ACC/ACCB/PREG, TREG0-2, ARCR, INDX, ARP,
  ARB, DP, OV, OVM, INTM, CNF, TC, SXM, C, HM, XF, PM, IPTR, AVIS,
  OVLY, RAM, MPMC, NDX, TRM, BRAF.  restore_ctx (RETI/RETE)
  restores all of those EXCEPT INTM and XF (audit #9 --
  deliberate in the C model).  RETE additionally clears INTM.
- The entry is NOT interruptible and is not taken while int_inh
  (EINT's one-cycle inhibit, consumed whether or not an interrupt
  was pending), while held (XC window or braf&&pc==paer), while
  rptc>0 or rep_cont (single-instruction RPT repeat), while intm,
  or when no (ifr & imr).
- The XC window: after a taken XC, xc_left=2, xc_new=1.  The next
  post-instruction check holds and clears xc_new; later checks
  hold while xc_left>0, decrementing xc_left by the words of the
  instruction just executed.  So XC plus the two words following
  it are uninterruptible.
- The RPTB lockout in the C model is ONLY the `braf && pc==paer`
  hold (see KNOWN-DIFF KD-6).
*/

/*
KNOWN-DIFF (C model vs TI manual, scored against the CURRENT C
code -- the RTL matches the C model; fixes are a separate step):
  KD-1  BSAR/SFTA amount: C shifts ACC right by (sh+1) (exec_bf
        SFTA: sh = sh + 1), so 0xBFE3 shifts by 4.  Audit 07b
        rates this OBEYS (SPRU056D 6.3).  RTL implements (sh+1).
  KD-2  IDLE2 wake: C wakes IDLE2 on INT1-4 (mask 0x107) and
        stops the timer; the audit (fix-list Rank 1, core-3)
        reads the manual as NMI/RS only.  The C comment cites
        4.10.2 for INT1-4.  The C model has NO hardware NMI
        input (fix-list Rank 48), so NMI cannot wake it.  RTL
        implements the C model (mask 0x107, timer frozen).
  KD-3  Delay-slot stack ordering: C pushes (CCD/CALLD/CALAD)
        the return address BEFORE delay_slot() runs, so a slot
        POPD/PUSH sees the branch's own stack change (fix-list
        Rank 5).  RETCD is the exception: C runs delay_slot()
        FIRST and pops TOS to PC only after the slot completes
        (c5x_core.c, RETCD case).  RTL replicates both: push
        before the slot for CCD/CALLD/CALAD, pop in TAIL after
        the slot for RETCD.
  KD-4  RPT repeats non-repeatable instructions: C rewinds
        unconditionally (fix-list Rank 7); RPT + B/CALL re-executes
        the branch/call.  RTL replicates.
  KD-5  XC k=1 skips opcode WORDS, not instructions (fix-list
        Rank 8): false XC does pc += n words (n = ((op>>12)&1)+1).
        A false XC 1 before a 2-word instruction skips only its
        opcode word and executes the operand word.  RTL replicates.
  KD-6  RPTB interrupt lockout is partial (fix-list Rank 6a): C
        holds interrupts only when braf && pc==paer (i.e. before
        the last block word executes); an interrupt IS taken
        between iterations of a multi-word block.  RTL replicates
        the pc==paer hold exactly.
  KD-7  NDX mirror deferred across delay slots: fixed in the
        CURRENT C code (delay_slot applies the mirror after each
        slot word, c5x_core.c:1238-1242); the fix-list Rank 10
        entry describes core-3.  RTL applies the mirror after
        each slot word and after each top-level instruction.
  KD-8  RPTB PAER off-by-one: fixed in the CURRENT C code
        (paer = imm, c5x_core.c:2407); fix-list Rank 11 describes
        core-3.  RTL uses paer = imm.
  KD-9  SMMR/LMMR ea() re-evaluation: fixed in the CURRENT C
        code (ea() is hoisted out of both loops); fix-list Rank 9
        describes core-3.  RTL evaluates ea() once per loop op.
  KD-10 BRCR underflow: fixed in the CURRENT C code (handle_braf
        decrements only when brcr > 0); fix-list Rank 6b describes
        core-3.  RTL guards the decrement.
  KD-11 TRAP/NMI/INTR vectors: IPTR-relative in the CURRENT C
        code ((iptr<<11)|vector); fix-list Rank 2 describes core-3.
        RTL uses IPTR-relative vectors.
  KD-12 INTR context save on the plain path: present in the
        CURRENT C code (save_ctx when v is 02/04/06/12,
        unconditional on ivec_ind); fix-list Rank 3 describes
        core-3.  RTL saves for K=1,2,3,9 (v=02,04,06,12).
  KD-13 Cycle-table values (fix-list Ranks 20/21): the CURRENT
        c5x_cyctab.h already has the corrected values (B/CALL
        direct = 4, INTR = 4, MADD/MADS = 2, RETCD = 2, LDP #k
        = 2, BD/CALLD/BANZD = 2).  The decoder below reports the
        CURRENT table values verbatim.
  KD-14 `seq` misclassification (fix-list Rank 25): C charges a
        branch that lands exactly on its fall-through address as
        not-taken (seq = pc == ppc + words).  RTL replicates.
  KD-15 DMOV-family block-edge write (fix-list Rank 4): C gates
        the DMOV destination on dm_internal(a+1) && (a+1) >= 0x60
        (dmov_wr); a DMOV ending exactly on a block edge can still
        write one word past it into an MMR/reserved/external word
        when the gate passes.  The RTL mem agent must implement
        the C dmov_wr gate exactly (see c5x_ctrl.sv S_LOOP).
  KD-16 *BRO+/- circular wrap (fix-list Rank 12): C ea() does not
        route bit-reversed steps through the circular-buffer wrap
        (agent 2's ea); RTL replicates the C ea() exactly.
  KD-17 RPT IN/OUT port increment: present in the CURRENT C code
        (io_rep; port += io_rep on repeats); fix-list Rank 13
        describes core-3.  RTL increments the port per repeat.
  KD-18 XC interrupt window: present in the CURRENT C code
        (xc_left/xc_new); fix-list Rank 14 describes core-3.  RTL
        implements the window.
  KD-19 Ex. 7-6 pipeline collision (fix-list Rank 17): the C
        model is sequential and cannot reproduce the manual's
        E-overwrites-D AR collision.  The RTL is multi-cycle
        sequential and inherits the same divergence.
  KD-20 No PMEM/DMEM wait states (fix-list Rank 27): the C model
        (and the RTL) have no memory wait states; only IN/OUT IO
        wait states (io_ws from IOWSR/CWSR) are modelled.
  KD-21 Reset staleness (fix-list Rank 18): C c5x_reset() does not
        clear ar0_dirty or int_inh.  The RTL clears both on
        reset (matches a fresh power-on reset, the only reset the
        harness performs; a mid-run reset with those flags set
        would differ from the C model).
  KD-22 INTR k=17 (0x22) / legacy table: INTR consults ivec_ind
        against the audited table first, then the legacy table
        (02,04,06,18,1A,1C,1E,20,22); only INTR consults the
        legacy table, never external-interrupt entry.  RTL
        replicates (see c5x_ctrl.sv S_INT_INTR).
  KD-23 MADS/MADD TREG0 load mirrors TREG1/TREG2: the C model
        writes TREG0 directly for MADS/MADD (audit N-1, no
        set_t0, so no TRM mirror), but every ALU op that loads
        TREG0 also mirrors TREG1/TREG2 when TRM=0 (c5x_alu
        i_ld_treg0).  FIXED: agent 1 added OP_LT_NM (7'd64),
        and the ctrl issues it for MADS/MADD in the LOOP WR
        phase (whole-body single issue: ACC + PREG + TREG0 in
        one phase, no separate TREG phase any more; see
        OPEN-10).  OP_LT remains the plain LT (0x73), which
        mirrors when TRM=0.
  KD-24 MADS/MADD loop kind (BUG FOUND 2026-11-19 during the
        house-rules ?: to case-table conversion, FIXED in the
        same change): the pre-conversion loop_kind chain used
        the range test op_hi >= A8 && op_hi <= AD for BLDD
        (kind 6), which also caught MADS (AA) and MADD (AB),
        so the LOOP engine would have executed them as block
        moves (no MAC, no TREG0 load, wrong PREG/ACC).  The
        case table in c5x_ctrl.sv (loop_kind_next) maps each
        BLDD form explicitly (A8, A9, AC, AD) and MADS/MADD
        to kind 8.  No co-sim existed yet to catch this; the
        decoder testbench does not cover the ctrl, so this is
        flagged for the agent-5 co-sim to confirm.
*/

/*
OPEN / INTEGRATION DELTAS (for the lead / agent 5, not silent):
  OPEN-1 alu_sh width: the top level declares alu_sh [1:0]; the
        shift needs 4 bits (0-15).  c5x_ctrl drives alu_sh [3:0];
        the top level must widen the wire and the ALU port.
  OPEN-2 rptb_brcr: the C model has no BRCR load at RPTB (BRCR is
        a separate MMR).  c5x_ctrl drives rptb_brcr = 0; the wire
        carries no load semantics.  Agent 5 may drop it.
  OPEN-3 Extra ctrl inputs (not in the top level's assumed u_ctrl
        port list; the top level must wire them):
          acc_i / accb_i / preg_i / treg0_i / treg1_i / treg2_i
            (ALU registered state: shadow save, cond(), NORM,
            SATH/SATL, BACC/CALA targets, TBLR/TBLW pfc=ACC)
          pmst_i[15:0] (PMST word: AVIS/OVLY/TRM for the shadow;
            the other PMST bits arrive as stat_*)
          ar_arp_i[15:0] (AR[ARP]: BANZ test, CMPR compare)
          indx_i / arcr_i / bmar_i / dbmr_i (shadow save +
            observation pass-through bmar_o/dbmr_o/indx_o/arcr_o)
          brcr_i[31:0] / pasr_i / paer_i (handle_braf)
          bio_i (BIO pin for cond() tp=0)
          ivec_ind_i[143:0] (packed 9x16 host vector indirection;
            0 = use the IPTR-relative table)
          io_ws_i[3:0] (IO wait-state count for the access)
          dm_ack (mem agent o_dm_ack: pulses when dm_rdata is
            valid; the ctrl waits for it in OP_ADDR before OP_DATA)
        Extra ctrl outputs:
          ndx_commit_o (pulse to the addr agent's i_ndx_commit)
          irq_ack_o[8:0] (one-hot IFR-bit clear to the mem agent)
          alu_flag_c_we/in, alu_flag_ov_we/in (flag sync to the
            ALU's i_flag_c_we/in, i_flag_ov_we/in; see OPEN-9)
          addr_wr_en_o / addr_wr_sel_o[5:0] / addr_wr_data_o
            (generic write port to the addr agent, agent 2's
            i_wr_*; used for MMR-routed writes with no top-level
            port: INDX, ARCR, CBSR/CBER, CBCR, BMAR, DBMR, IMR,
            IFR, and the shadow restore of ARCR/INDX)
  OPEN-4 The top level's assumed ALU/ADDR port lists do not match
        agents 1/2's real modules (e.g. the top level drives
        u_alu with alu_op/alu_a/alu_b/alu_d/alu_sh/alu_c_in/
        alu_en/acc_ld/... while agent 1's c5x_alu has i_exec/
        i_ld_acc/i_op/i_b32/i_b16/i_mpy_a/i_mpy_b/i_shift/...;
        u_addr is wired with st0_ld_en/ar_wr_sel/... while agent
        2's c5x_addr has i_wr_en/i_wr_sel/i_flg_we/i_pm_we/...).
        Agent 5 adapts the top level to the real submodule ports;
        this package documents the semantics each wire must
        carry so the adaptation is a rename, not a redesign.
  OPEN-5 The addr agent's o_cond / i_op / i_acc / i_bio path is
        not wired by the top level; c5x_ctrl computes cond()
        itself from acc_i + stat_* + bio_i using the package
        function c5x_cond() below (single source of truth).
  OPEN-6 IDLE fast-forward: the top level's comment says
        cycles_o advances 1 per clock while idle.  The RTL does
        that (S_IDLE advances cycles_q by 1 per clock); the
        timer advances with it except in IDLE2 (frozen).  The
        "1 clock = 1 cycle" reading does NOT hold during
        execution (see TIMING CONTRACT above).
  OPEN-7 The decode testbench (tb_c5x_decode.sv) proves decode +
        cycle counts only.  Full co-simulation of the FSM against
        the C model is agent 5's sim/ harness (not this module).
  OPEN-8 The top level's assumed ALU interface has no s16 input
        (agent 1's real ALU has i_s16 for the 16-bit ADD/SUB
        forms 0x61/0x65); c5x_ctrl adds an alu_s16 output, and
        the top level must wire it to the ALU.
  OPEN-9 C/OV dual ownership: agent 1's ALU owns the C/OV
        registers (o_c/o_ov are the REGISTERED old values, not
        the combinational next), and agent 2's addr agent also
        holds c_q/ov_q (stat_c/stat_ov).  The ctrl writes the new
        flags back to the addr agent in TAIL (the ALU registered
        the new flags at the EXEC edge), gated on the latched
        alu_used_q; it also drives alu_flag_c_we/in and
        alu_flag_ov_we/in (to the ALU's i_flag_c_we/in,
        i_flag_ov_we/in) whenever it writes C/OV through the
        addr agent (LST #1, SETC/CLRC, shadow restore), so the
        ALU's flag copy stays in sync.  If agent 1 adds
        combinational o_c_next/o_ov_next/o_c_wr/o_ov_wr taps
        (mirroring o_tc_next/o_tc_wr), the writeback could move
        to the EXEC clock instead.
  OPEN-10 MADS/MADD need a no-mirror TREG0 load (KD-23).
        FIXED: agent 1 added OP_LT_NM (7'd64; ACC += pscale
        of OLD PREG, TREG0 = dma with NO TREG1/TREG2 mirror,
        PREG = dma * pma; c5x_core.c:2083-2105, audit N-1).
        The ctrl issues OP_LT_NM for MADS/MADD in the LOOP WR
        phase (whole-body single issue: ACC + PREG + TREG0 in
        one phase, so there is no separate TREG phase any more);
        OP_LT is still the plain LT (0x73), which mirrors when
        TRM=0 (set_t0, c5x_core.c:1047-1055).
*/

package c5x_ctl_pkg;

    /*
    ------------------------------------------------------------------
    ALU micro-ops (canonical values; identical to agent 1's
    c5x_alu OP_* localparams -- if they ever differ, this package
    wins and c5x_alu.sv must be re-derived from it).
    ------------------------------------------------------------------
    */
    typedef enum logic [6:0] {
        ALU_NOP          = 7'd0,
        ALU_ADD          = 7'd1,
        ALU_ADDC         = 7'd2,
        ALU_SUB          = 7'd3,
        ALU_SUBB         = 7'd4,
        ALU_SBBB         = 7'd5,
        ALU_ADD_B        = 7'd6,
        ALU_ADDC_B       = 7'd7,
        ALU_SUB_B        = 7'd8,
        ALU_AND          = 7'd9,
        ALU_OR           = 7'd10,
        ALU_XOR          = 7'd11,
        ALU_AND_B        = 7'd12,
        ALU_OR_B         = 7'd13,
        ALU_XOR_B        = 7'd14,
        ALU_ADD_SH       = 7'd15,
        ALU_SUB_SH       = 7'd16,
        ALU_ADDT         = 7'd17,
        ALU_SUBT         = 7'd18,
        ALU_LD_EXT       = 7'd19,
        ALU_LACT         = 7'd20,
        ALU_LD_B32       = 7'd21,
        ALU_LD_B16Z      = 7'd22,
        ALU_LD_B16HI     = 7'd23,
        ALU_LD_ZALR      = 7'd24,
        ALU_NEG          = 7'd25,
        ALU_ABS          = 7'd26,
        ALU_CMPL         = 7'd27,
        ALU_MAX          = 7'd28,
        ALU_MIN          = 7'd29,
        ALU_SWAP         = 7'd30,
        ALU_SACB         = 7'd31,
        ALU_LACB         = 7'd32,
        ALU_SUBC         = 7'd33,
        ALU_PAC          = 7'd34,
        ALU_APAC         = 7'd35,
        ALU_SPAC         = 7'd36,
        ALU_MPYA         = 7'd37,
        ALU_MPYS         = 7'd38,
        ALU_SQRA         = 7'd39,
        ALU_SQRS         = 7'd40,
        ALU_LTA          = 7'd41,
        ALU_LTP          = 7'd42,
        ALU_LTD          = 7'd43,
        ALU_LTS          = 7'd44,
        ALU_LT           = 7'd45,
        ALU_MPY          = 7'd46,
        ALU_MPYU         = 7'd47,
        ALU_LPH          = 7'd48,
        ALU_PREG_ZERO    = 7'd49,
        ALU_ACC_ZERO     = 7'd50,
        ALU_ACC_PREG_ZERO = 7'd51,
        ALU_ROL          = 7'd52,
        ALU_ROR          = 7'd53,
        ALU_ROLC         = 7'd54,
        ALU_RORC         = 7'd55,
        ALU_SFLB         = 7'd56,
        ALU_SFRB         = 7'd57,
        ALU_ROLB         = 7'd58,
        ALU_RORB         = 7'd59,
        ALU_SFTA         = 7'd60,
        ALU_SATH         = 7'd61,
        ALU_SATL         = 7'd62,
        ALU_NORM         = 7'd63,
        ALU_LT_NM        = 7'd64
    } c5x_alu_op_e;

    /*
    ------------------------------------------------------------------
    Status-bit selects (identical to agent 2's c5x_addr FLG_*).
    These are the shared interface contract: not every consumer
    uses every constant, so UNUSEDPARAM is waived for this block.
    ------------------------------------------------------------------
    */
    /* verilator lint_off UNUSEDPARAM */
    localparam logic [4:0] FLG_OV   = 5'd0;
    localparam logic [4:0] FLG_OVM  = 5'd1;
    localparam logic [4:0] FLG_INTM = 5'd2;
    localparam logic [4:0] FLG_C    = 5'd3;
    localparam logic [4:0] FLG_CNF  = 5'd4;
    localparam logic [4:0] FLG_SXM  = 5'd5;
    localparam logic [4:0] FLG_HM   = 5'd6;
    localparam logic [4:0] FLG_XF   = 5'd7;
    localparam logic [4:0] FLG_TC   = 5'd8;
    localparam logic [4:0] FLG_NDX  = 5'd9;
    localparam logic [4:0] FLG_TRM  = 5'd10;
    localparam logic [4:0] FLG_BRAF = 5'd11;
    localparam logic [4:0] FLG_RAM  = 5'd12;
    localparam logic [4:0] FLG_OVLY = 5'd13;
    localparam logic [4:0] FLG_MPMC = 5'd14;
    localparam logic [4:0] FLG_AVIS = 5'd15;

    /*
    ------------------------------------------------------------------
    Addr-agent write-port selects (identical to agent 2's WR_*).
    ------------------------------------------------------------------
    */
    localparam logic [5:0] WR_IMR   = 6'h04;
    localparam logic [5:0] WR_IFR   = 6'h06;
    localparam logic [5:0] WR_PMST  = 6'h07;
    localparam logic [5:0] WR_RPTC  = 6'h08;
    localparam logic [5:0] WR_BRCR  = 6'h09;
    localparam logic [5:0] WR_PASR  = 6'h0A;
    localparam logic [5:0] WR_PAER  = 6'h0B;
    localparam logic [5:0] WR_DBMR  = 6'h0F;
    localparam logic [5:0] WR_AR0   = 6'h10; /* AR0..AR7: 6'h10..6'h17 */
    localparam logic [5:0] WR_INDX  = 6'h18;
    localparam logic [5:0] WR_ARCR  = 6'h19;
    localparam logic [5:0] WR_CBSR1 = 6'h1A;
    localparam logic [5:0] WR_CBER1 = 6'h1B;
    localparam logic [5:0] WR_CBSR2 = 6'h1C;
    localparam logic [5:0] WR_CBER2 = 6'h1D;
    localparam logic [5:0] WR_CBCR  = 6'h1E;
    localparam logic [5:0] WR_BMAR  = 6'h1F;
    localparam logic [5:0] WR_ST0   = 6'h20;
    localparam logic [5:0] WR_ST1   = 6'h21;
    localparam logic [5:0] WR_ST0L  = 6'h25; /* LST #0 (exec1 0x0E) */
    localparam logic [5:0] WR_ST1L  = 6'h26; /* LST #1 (exec1 0x0F) */

    /*
    ------------------------------------------------------------------
    Decode descriptor: the canonical bundle c5x_decode produces.
    The module exposes these as discrete ports (the top level
    wires discrete signals); this struct is the definition.
    ------------------------------------------------------------------
    */
    typedef struct packed {
        c5x_alu_op_e alu_op; /* micro-op for the ALU (OP_NOP if none) */
        logic [1:0]  words; /* instruction length in words (1 or 2) */
        logic [7:0]  cycles; /* base cycle count from c5x_cyctab.h */
        logic [7:0]  ea_mode; /* addressing-mode field (opcode[7:0]) */
        logic        is_branch; /* B/BD/BANZ/BANZD/BCND/BCNDD/BACC/BACCD */
        logic        is_call; /* CALL/CALLD/CC/CCD/CALA/CALAD */
        logic        is_ret; /* RETC/RETCD/RETI/RETE */
        logic        is_rpt; /* RPT dma / RPT #k8 / RPT #lk / RPTZ #lk */
        logic        is_rptb; /* RPTB */
        logic        is_idle; /* IDLE / IDLE2 */
        logic        is_io; /* IN / OUT */
        logic        is_mem_wr; /* performs a dm_wr (unified data write) */
        logic        is_pm_wr; /* performs a pm_wr (BLDP / TBLW only) */
        logic        badop; /* illegal opcode (C RUN_BADOP) */
    } c5x_dec_t;

    /*
    ------------------------------------------------------------------
    Control FSM states (binary-encoded, 5 bits -- small, per the
    Cyclone V targeting note).  One state = one clock; a machine
    cycle is a logical count, not a clock (see TIMING CONTRACT).
    ------------------------------------------------------------------
    The FSM is binary-encoded (5 bits; the user asked for a small
    control FSM).  FSM_TICK drains the timer ticks: the mem agent's
    timer advances one pulse per machine cycle (i_tick), but the
    ctrl charges several machine cycles at once (base + loop extra
    + IO wait states).  TICK emits one mtick_en pulse per clock
    until cyc_acc_q is drained, BEFORE TAIL, so TAIL's interrupt
    check sees the up-to-date IFR (a TINT expiring mid-instruction
    is taken at this instruction's boundary, as in the C model).
    IDLE drains one tick per clock inline (no TICK state).
    */
    typedef enum logic [4:0] {
        FSM_RESET      = 5'd0, /* reset / power-on; pc = RESET_PC */
        FSM_FETCH_ADDR = 5'd1, /* present pm_addr = pc (BRAM latches) */
        FSM_FETCH_DATA = 5'd2, /* pm_rdata = opcode; latch op_q, pc++ */
        FSM_FETCH2_ADDR = 5'd3, /* present pm_addr = pc (immediate) */
        FSM_FETCH2_DATA = 5'd4, /* pm_rdata = immediate; latch imm_q */
        FSM_OP_ADDR    = 5'd5, /* pulse ea_en; present dm_addr = ea */
        FSM_OP_DATA    = 5'd6, /* dm_rdata valid; execute + commit */
        FSM_EXEC       = 5'd7, /* register-only execute + commit */
        FSM_LOOP       = 5'd8, /* loop-op iteration engine */
        FSM_IO_WAIT    = 5'd9, /* wait for io_ack_c (IN/OUT) */
        FSM_TICK       = 5'd10, /* drain timer ticks (one per clock) */
        FSM_TAIL       = 5'd11, /* RPT/RPTB tail + interrupt decision */
        FSM_INT        = 5'd12, /* interrupt entry (4 machine cycles) */
        FSM_DONE       = 5'd13, /* pulse instr_done (cycles already in) */
        FSM_IDLE       = 5'd14, /* IDLE/IDLE2 wait (cycles advance) */
        FSM_BADOP      = 5'd15, /* halted: pc restored to ppc */
        FSM_RESTORE    = 5'd16 /* RETI/RETE shadow-restore sequence */
    } c5x_fsm_e;

    /*
    ------------------------------------------------------------------
    Constants.
    ------------------------------------------------------------------
    */
    localparam logic [15:0] IDLE2_WAKE_MASK = 16'h0107; /* INT1,2,3,4 */
    localparam logic [8:0]  INT_MASK_ALL    = 9'h1FF;
    localparam int unsigned N_INT           = 9;
    /* verilator lint_on UNUSEDPARAM */

    /*
    Interrupt vectors (audited order: INT1..INT3, TINT, RINT, XINT,
    TRNT, TXNT, INT4), IPTR-relative.  Index = IFR/IMR bit 0..8.
    */
    function automatic logic [7:0] c5x_ivec(input logic [3:0] idx);
        case (idx)
            4'd0:    c5x_ivec = 8'h02; /* INT1 */
            4'd1:    c5x_ivec = 8'h04; /* INT2 */
            4'd2:    c5x_ivec = 8'h06; /* INT3 */
            4'd3:    c5x_ivec = 8'h08; /* TINT */
            4'd4:    c5x_ivec = 8'h0A; /* RINT */
            4'd5:    c5x_ivec = 8'h0C; /* XINT */
            4'd6:    c5x_ivec = 8'h0E; /* TRNT */
            4'd7:    c5x_ivec = 8'h10; /* TXNT */
            4'd8:    c5x_ivec = 8'h12; /* INT4 */
            default: c5x_ivec = 8'h00;
        endcase
    endfunction

    /*
    Legacy vector table (INTR only, never external entry).
    */
    function automatic logic [7:0] c5x_ivec_legacy(input logic [3:0] idx);
        case (idx)
            4'd0:    c5x_ivec_legacy = 8'h02;
            4'd1:    c5x_ivec_legacy = 8'h04;
            4'd2:    c5x_ivec_legacy = 8'h06;
            4'd3:    c5x_ivec_legacy = 8'h18;
            4'd4:    c5x_ivec_legacy = 8'h1A;
            4'd5:    c5x_ivec_legacy = 8'h1C;
            4'd6:    c5x_ivec_legacy = 8'h1E;
            4'd7:    c5x_ivec_legacy = 8'h20;
            4'd8:    c5x_ivec_legacy = 8'h22;
            default: c5x_ivec_legacy = 8'h00;
        endcase
    endfunction

    /*
    ------------------------------------------------------------------
    Branch condition, C cond() / zlvc_cond() / tp_cond() verbatim.
      op   : the full 16-bit opcode.  zlvc = op[7:4] (the expected
             flag values), mask = op[3:0] (which flags are tested),
             tp = op[9:8].
      acc  : current ACC (32-bit, for sign/zero tests).
      tc, ov, c : status bits.  bio: the BIO pin (tp 0 = BIO low).
    zlvc_cond: if mask bit 1 is set, zlvc bit 1 must equal OV;
    if mask bit 0 is set, zlvc bit 0 must equal C.  Then the ACC
    test, switched on (mask & 0xC) | ((zlvc>>2) & 3):
      4/6/12 ACC>0, 5/7/13 ACC<0, 8/9 ACC!=0, 10/11 ACC==0,
      14 ACC>=0, 15 ACC<=0, anything else -> 1 (no ACC test).
    tp_cond: 0 = BIO low, 1 = TC set, 2 = TC clear, 3 -> 1.
    cond = zlvc_cond && tp_cond.
    ------------------------------------------------------------------
    op[15:10] are the instruction class bits, not part of the
    condition encoding (zlvc = op[7:4], mask = op[3:0],
    tp = op[9:8]); UNUSEDSIGNAL is waived for the op input.
    */
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic c5x_cond(
        input logic [15:0] op,
        input logic [31:0] acc,
        input logic        tc,
        input logic        ov,
        input logic        c,
        input logic        bio
    );
        logic [3:0] zlvc;
        logic [3:0] mask;
        logic [3:0] acc_sel;
        logic       zlvc_r;
        logic [1:0] tp;
        logic       tp_r;
        begin
            zlvc = op[7:4];
            mask = op[3:0];
            zlvc_r = 1'b1;
            /*
            OV test (mask bit 1): zlvc bit 1 must equal OV.
            */
            if (mask[1] && (zlvc[1] != ov))
                zlvc_r = 1'b0;
            /*
            C test (mask bit 0): zlvc bit 0 must equal C.
            */
            if (mask[0] && (zlvc[0] != c))
                zlvc_r = 1'b0;
            /*
            ACC sign/zero test.
            */
            acc_sel = (mask & 4'hC) | {2'b00, zlvc[3:2]};
            case (acc_sel)
                4'd4, 4'd6, 4'd12:
                    zlvc_r = zlvc_r && ($signed(acc) > 0); /* ACC>0 */
                4'd5, 4'd7, 4'd13:
                    zlvc_r = zlvc_r && ($signed(acc) < 0); /* ACC<0 */
                4'd8, 4'd9:
                    zlvc_r = zlvc_r && (acc != 32'd0); /* ACC!=0 */
                4'd10, 4'd11:
                    zlvc_r = zlvc_r && (acc == 32'd0); /* ACC==0 */
                4'd14:
                    zlvc_r = zlvc_r && ($signed(acc) >= 0); /* ACC>=0 */
                4'd15:
                    zlvc_r = zlvc_r && ($signed(acc) <= 0); /* ACC<=0 */
                default: begin end /* no ACC test */
            endcase
            tp = op[9:8];
            case (tp)
                2'd0: tp_r = !bio; /* BIO low */
                2'd1: tp_r = tc; /* TC set */
                2'd2: tp_r = !tc; /* TC clear */
                default: tp_r = 1'b1;
            endcase
            c5x_cond = zlvc_r && tp_r;
        end
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    /*
    ------------------------------------------------------------------
    Cycle table, c5x_cyctab.h verbatim (values 1..4).  A function of
    the high byte alone except hi = 0x7B, 0xBE, 0xBF, 0xEF.
    This is the BASE count the decoder reports; the ctrl applies
    the instr_cycles() adjustments (class-1 taken/not-taken,
    class-2 RETCD seq, IN/OUT wait states) on top.
    ------------------------------------------------------------------
    */
    function automatic logic [7:0] c5x_cyctab(input logic [15:0] op);
        logic [7:0] hi;
        logic [7:0] lo;
        begin
            hi = op[15:8];
            lo = op[7:0];
            case (hi)
                8'h00, 8'h01, 8'h02, 8'h03,
                8'h04, 8'h05, 8'h06, 8'h07: c5x_cyctab = 8'd2; /* LAR dma */
                8'h08: c5x_cyctab = 8'd1; /* LAMM */
                8'h09: c5x_cyctab = 8'd2; /* SMMR */
                8'h0A: c5x_cyctab = 8'd1; /* SUBC */
                8'h0B: c5x_cyctab = 8'd1; /* RPT dma */
                8'h0C: c5x_cyctab = 8'd3; /* OUT */
                8'h0D, 8'h0E, 8'h0F: c5x_cyctab = 8'd2; /* LDP/LST */
                8'h10, 8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17,
                8'h18, 8'h19, 8'h1A, 8'h1B, 8'h1C, 8'h1D, 8'h1E, 8'h1F,
                8'h20, 8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26, 8'h27,
                8'h28, 8'h29, 8'h2A, 8'h2B, 8'h2C, 8'h2D, 8'h2E, 8'h2F,
                8'h30, 8'h31, 8'h32, 8'h33, 8'h34, 8'h35, 8'h36, 8'h37,
                8'h38, 8'h39, 8'h3A, 8'h3B, 8'h3C, 8'h3D, 8'h3E, 8'h3F:
                    c5x_cyctab = 8'd1; /* LACC/ADD/SUB dma,sh */
                8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h46, 8'h47,
                8'h48, 8'h49, 8'h4A, 8'h4B, 8'h4C, 8'h4D, 8'h4E, 8'h4F:
                    c5x_cyctab = 8'd1; /* BIT */
                8'h50, 8'h51, 8'h52, 8'h53, 8'h54, 8'h55:
                    c5x_cyctab = 8'd1; /* MPYA/MPYS/SQRA/SQRS/MPY/MPYU */
                8'h56: c5x_cyctab = 8'd1; /* BADOP (0x56) */
                8'h57: c5x_cyctab = 8'd2; /* BLDP */
                8'h58, 8'h59, 8'h5A, 8'h5B:
                    c5x_cyctab = 8'd1; /* XPL/OPL/APL/CPL dbmr */
                8'h5C, 8'h5D, 8'h5E, 8'h5F:
                    c5x_cyctab = 8'd2; /* XPL/OPL/APL/CPL #lk */
                8'h60, 8'h61, 8'h62, 8'h63, 8'h64, 8'h65, 8'h66, 8'h67,
                8'h68, 8'h69, 8'h6A, 8'h6B, 8'h6C, 8'h6D, 8'h6E, 8'h6F,
                8'h70, 8'h71, 8'h72, 8'h73, 8'h74, 8'h75, 8'h76, 8'h77,
                8'h78: c5x_cyctab = 8'd1; /* ADDC..ADRK */
                8'h79, 8'h7A: c5x_cyctab = 8'd4; /* B / CALL */
                8'h7B: c5x_cyctab = (lo < 8'h80) ? 8'd1 : 8'd4; /* BANZ */
                8'h7C: c5x_cyctab = 8'd1; /* SBRK */
                8'h7D, 8'h7E, 8'h7F: c5x_cyctab = 8'd2; /* BD/CALLD/BANZD */
                8'h80, 8'h81, 8'h82, 8'h83, 8'h84, 8'h85, 8'h86, 8'h87:
                    c5x_cyctab = 8'd1; /* SAR */
                8'h88: c5x_cyctab = 8'd1; /* SAMM */
                8'h89: c5x_cyctab = 8'd2; /* LMMR */
                8'h8A, 8'h8B, 8'h8C, 8'h8D, 8'h8E, 8'h8F:
                    c5x_cyctab = 8'd1; /* POPD/MAR/SPL/SPH/SST */
                8'h90, 8'h91, 8'h92, 8'h93, 8'h94, 8'h95, 8'h96, 8'h97,
                8'h98, 8'h99, 8'h9A, 8'h9B, 8'h9C, 8'h9D, 8'h9E, 8'h9F:
                    c5x_cyctab = 8'd1; /* SACL/SACH */
                8'hA0: c5x_cyctab = 8'd1; /* NORM */
                8'hA1: c5x_cyctab = 8'd1; /* BADOP (0xA1) */
                8'hA2, 8'hA3: c5x_cyctab = 8'd3; /* MAC/MACD */
                8'hA4: c5x_cyctab = 8'd2; /* BLPD bmar */
                8'hA5: c5x_cyctab = 8'd3; /* BLPD #pma */
                8'hA6, 8'hA7: c5x_cyctab = 8'd3; /* TBLR/TBLW */
                8'hA8, 8'hA9: c5x_cyctab = 8'd3; /* BLDD #lk */
                8'hAA, 8'hAB: c5x_cyctab = 8'd2; /* MADS/MADD */
                8'hAC, 8'hAD: c5x_cyctab = 8'd2; /* BLDD bmar */
                8'hAE: c5x_cyctab = 8'd2; /* SPLK */
                8'hAF: c5x_cyctab = 8'd2; /* IN */
                8'hB0, 8'hB1, 8'hB2, 8'hB3, 8'hB4, 8'hB5, 8'hB6, 8'hB7:
                    c5x_cyctab = 8'd2; /* LAR #k8 */
                8'hB8, 8'hB9, 8'hBA: c5x_cyctab = 8'd1; /* ADDK/LACK/SUBK */
                8'hBB: c5x_cyctab = 8'd2; /* RPT #k8 */
                8'hBC, 8'hBD: c5x_cyctab = 8'd2; /* LDP #k9 */
                8'hBE: begin
                    /*
                    0xBE sub-decoder (low byte).
                    */
                    if (lo < 8'h20) c5x_cyctab = 8'd1;
                    else if (lo == 8'h20) c5x_cyctab = 8'd4; /* BACC */
                    else if (lo == 8'h21) c5x_cyctab = 8'd2; /* BACCD */
                    else if (lo >= 8'h22 && lo <= 8'h2F) c5x_cyctab = 8'd1;
                    else if (lo == 8'h30) c5x_cyctab = 8'd4; /* CALA */
                    else if (lo >= 8'h31 && lo <= 8'h37) c5x_cyctab = 8'd1;
                    else if (lo == 8'h38) c5x_cyctab = 8'd4; /* RETI */
                    else if (lo == 8'h39) c5x_cyctab = 8'd1;
                    else if (lo == 8'h3A) c5x_cyctab = 8'd4; /* RETE */
                    else if (lo == 8'h3B || lo == 8'h3C) c5x_cyctab = 8'd1;
                    else if (lo == 8'h3D) c5x_cyctab = 8'd2; /* CALAD */
                    else if (lo >= 8'h3E && lo <= 8'h50) c5x_cyctab = 8'd1;
                    else if (lo == 8'h51 || lo == 8'h52) c5x_cyctab = 8'd4;
                    else if (lo >= 8'h53 && lo <= 8'h5F) c5x_cyctab = 8'd1;
                    else if (lo >= 8'h60 && lo <= 8'h7F) c5x_cyctab = 8'd4;
                    else if (lo >= 8'h80 && lo <= 8'h83) c5x_cyctab = 8'd2;
                    else if (lo >= 8'h84 && lo <= 8'hC3) c5x_cyctab = 8'd1;
                    else if (lo >= 8'hC4 && lo <= 8'hC6) c5x_cyctab = 8'd2;
                    else c5x_cyctab = 8'd1;
                end
                8'hBF: begin
                    /*
                    0xBF sub-decoder (low byte).
                    */
                    if (lo <= 8'h07) c5x_cyctab = 8'd1; /* SPM k */
                    else if (lo >= 8'h08 && lo <= 8'h0F) c5x_cyctab = 8'd2;
                    else if (lo >= 8'h10 && lo <= 8'h7F) c5x_cyctab = 8'd1;
                    else if (lo >= 8'h80 && lo <= 8'hDF) c5x_cyctab = 8'd2;
                    else c5x_cyctab = 8'd1; /* SFTA */
                end
                8'hC0, 8'hC1, 8'hC2, 8'hC3, 8'hC4, 8'hC5, 8'hC6, 8'hC7,
                8'hC8, 8'hC9, 8'hCA, 8'hCB, 8'hCC, 8'hCD, 8'hCE, 8'hCF,
                8'hD0, 8'hD1, 8'hD2, 8'hD3, 8'hD4, 8'hD5, 8'hD6, 8'hD7,
                8'hD8, 8'hD9, 8'hDA, 8'hDB, 8'hDC, 8'hDD, 8'hDE, 8'hDF:
                    c5x_cyctab = 8'd1; /* MPY #k13 */
                8'hE0, 8'hE1, 8'hE2, 8'hE3: c5x_cyctab = 8'd4; /* BCND */
                8'hE4, 8'hE5, 8'hE6, 8'hE7: c5x_cyctab = 8'd1; /* XC */
                8'hE8, 8'hE9, 8'hEA, 8'hEB: c5x_cyctab = 8'd4; /* CC */
                8'hEC, 8'hED, 8'hEE: c5x_cyctab = 8'd2; /* RETC */
                8'hEF: c5x_cyctab = (lo == 8'h00) ? 8'd4 : 8'd2; /* RETC */
                8'hF0, 8'hF1, 8'hF2, 8'hF3: c5x_cyctab = 8'd2; /* BCNDD */
                8'hF4, 8'hF5, 8'hF6, 8'hF7: c5x_cyctab = 8'd1; /* XC */
                8'hF8, 8'hF9, 8'hFA, 8'hFB: c5x_cyctab = 8'd2; /* CCD */
                8'hFC, 8'hFD, 8'hFE, 8'hFF: c5x_cyctab = 8'd2; /* RETCD */
                default: c5x_cyctab = 8'd1;
            endcase
        end
    endfunction

    /*
    ---------------------------------------------------------------
    PIPELINE REGISTERS AND CONTROL TYPES (converged plan 2026-11-20)
    ---------------------------------------------------------------
    Four stages F/D/R/E.  The F/D register holds the raw fetched
    word; the D/R and R/E registers hold one decoded bundle type,
    c5x_pipe_t, which carries everything the later stages need:
    the decoded micro-op bundle (c5x_dec_t), the immediate, the
    effective address, the AR-update descriptor and the E write-
    target set.  The operand VALUE is deliberately not a field of
    the R/E bundle: mem's read data is registered at the R->E
    edge, so it is only valid during E and is consumed
    combinationally there (from o_r_data for a normal R read, from
    o_e_rdata for a deferred E read).  Latching it in R/E would
    cost a clock per instruction.
    The AR-update descriptor is an OPERATION, re-evaluated per
    iteration from the live AR (plan section 5 B6), never a
    precomputed value: circular and bit-reverse state is read live
    from the address unit, never captured in D.
    */

    /* AR-update descriptor (Worker B). */
    typedef struct packed {
        logic [2:0] ar_id;     /* AR the update applies to */
        logic [3:0] mode;      /* DESC_* (c5x_addr.sv) */
        logic       arp_sw;    /* ARP switch after the update */
        logic [2:0] new_arp;   /* ARP value after the switch */
        logic [7:0] ark;       /* ADRK/SBRK step */
        logic       norm_cond; /* NORM: commit held unless shifting */
        logic       valid;     /* this instruction carries an update */
    } c5x_ar_desc_t;

    /* E write-target set (Worker B): every architectural register
       this instruction may write, resolved in D.  The AR0 mirror
       (wr_ar0_mirror) is re-evaluated at E with the live NDX, per
       apply_ar0_mirror (c5x_core.c:2756).  The dynamic MMR target
       (wr_mmr_dyn_*) covers stores and LMMR/SMMR to an MMR address
       that is not a fixed field above (IMR, IFR, DBMR, INDX, ARCR,
       CBSR/CBER, CBCR, BMAR); its select numerically equals the
       MMR address. */
    typedef struct packed {
        logic        wr_ar_valid;
        logic [2:0]  wr_ar_id;
        logic        wr_ar2_valid;
        logic [2:0]  wr_ar2_id;
        logic        wr_arp_sw;
        logic [2:0]  wr_arp_id;
        logic        wr_ar0_mirror;
        logic        wr_dp;
        logic [15:0] wr_st0_mask;
        logic [15:0] wr_st1_mask;
        logic        wr_pmst_map;  /* writes PMST CNF/RAM/OVLY/MPMC */
        logic        wr_treg0;
        logic        wr_treg1;
        logic        wr_treg2;
        logic        wr_acc;      /* writes ACC (H1a: TBLR/TBLW pfc) */
        logic        wr_mmr_dyn_valid;
        logic [4:0]  wr_mmr_dyn_id;
        logic        wr_rptc;
        logic        wr_brcr;
        logic        wr_pasr;
        logic        wr_paer;
    } c5x_e_wrt_t;

    /* F/D pipeline register.  word2 holds the second word of a
       2-word instruction when it has been fetched while D is
       stalled; first_word marks a word fetched as an instruction
       start (not as a word2) -- the RPTB D-cancel rule (audit
       section 6.2) applies only to a first word. */
    typedef struct packed {
        logic [15:0] pc;
        logic [15:0] word;
        logic [15:0] word2;
        logic        word2_valid;
        logic        first_word;
        logic        valid;
    } c5x_fd_t;

    /* D/R and R/E pipeline register (one bundle type).  Fields
       marked (E) are only meaningful in the R/E register. */
    typedef struct packed {
        logic [15:0] pc;        /* PC of the first word */
        logic [15:0] op;        /* raw first word (executor dispatches
                                   on op[15:8]/op[7:0]) */
        c5x_dec_t    dec;       /* decoded micro-op bundle */
        logic [15:0] imm;       /* second word, or zero */
        logic        imm_valid; /* imm holds a real second word */
        logic [15:0] ea;        /* effective address (data) */
        logic [15:0] pfc;       /* program address (MAC/BLPD/TBLR) */
        logic        pfc_valid; /* pfc holds a real program address */
        c5x_ar_desc_t desc;     /* AR-update descriptor */
        c5x_e_wrt_t   wrt;      /* E write-target set */
        logic        map_chg;   /* writes a map bit or PMST */
        logic        ea_use;    /* R read uses ea */
        logic        r_read_pfc;/* R read uses pfc (program read) */
        logic        deferred;  /* R read is deferred to E (H3) */
        logic        is_io;     /* IN/OUT */
        logic        is_loop_a; /* mechanism (a) loop opcode */
        logic [3:0]  loop_kind; /* c5x_loop_e */
        logic        is_rptb;   /* RPTB setup */
        logic        is_idle;   /* IDLE/IDLE2 */
        logic        is_delayed;/* delayed branch/call/return */
        logic        xc_open;   /* this instruction opens an XC window */
        logic [2:0]  xc_left_in;/* XC window remaining on entry to E */
        logic        replay;    /* (E) replay iteration, not front-end */
        logic        replay_last;/* (E) last iteration of this replay */
        logic [15:0] rpt_start; /* (E) PC to retire as, (b) non-last */
        logic        valid;
    } c5x_pipe_t;

    /* Retire bundle: one entry per retirement, held from the
       retire pulse until the next retire (the co-sim harness reads
       it after the retire edge). */
    typedef struct packed {
        logic        valid;
        logic        is_intr;   /* interrupt-entry pseudo-instruction */
        logic [31:0] cycles;    /* C-model charge of this retirement */
        logic [15:0] pc;        /* PC retired as */
    } c5x_retire_t;

    /* Stall-cause classes (plan section 4).  One counter per cause
       is exposed at the top level (plan section 9); the enum names
       the cause in the pipe-control stall logic. */
    typedef enum logic [2:0] {
        STALL_NONE = 3'd0,
        STALL_H1   = 3'd1,
        STALL_H1A  = 3'd2,
        STALL_H1B  = 3'd3,
        STALL_H2   = 3'd4,
        STALL_H3   = 3'd5
    } c5x_stall_e;

    /* Flush causes. */
    typedef enum logic [1:0] {
        FLUSH_NONE   = 2'd0,
        FLUSH_BRANCH = 2'd1,  /* taken branch/call/return in E */
        FLUSH_PMWR   = 2'd2,  /* PMEM-write flush (H10) */
        FLUSH_INTR   = 2'd3   /* interrupt entry (drains, redirects) */
    } c5x_flush_e;

    /* Mechanism (a) loop kinds (audit section 4.1).  The numeric
       values match the multi-cycle loop engine (LOOP_SMMR=1 ..
       LOOP_MADS=9) so the old cycle-charge ports stay readable. */
    typedef enum logic [3:0] {
        LOOP_NONE = 4'd0,
        LOOP_SMMR = 4'd1,
        LOOP_LMMR = 4'd2,
        LOOP_BLDP = 4'd3,
        LOOP_BLPD = 4'd4,
        LOOP_TBLR = 4'd5,
        LOOP_TBLW = 4'd6,
        LOOP_BLDD = 4'd7,
        LOOP_MAC  = 4'd8,
        LOOP_MADS = 4'd9
    } c5x_loop_e;

endpackage

`default_nettype wire
