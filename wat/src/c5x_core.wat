;; c5x_core.wat -- TMS320C5x (C51 flavour) DSP core, hand-written WAT.
;;
;; Design: c-port/wat/DESIGN.md (v1). Oracle: c-port/c/src/dsp/c5x_core.c
;; (2,718 lines) + c5x_core.h + c5x_cyctab.h. Manual authority: SPRU056D.
;; This file is the readable source; tools/build.py splices the generated
;; tables (src/tables.wat, from tools/gen_tables.py) at `;; __TABLES__`
;; to produce build/c5x.wat, assembled by harness/compile_wat.js.
;;
;; Structure mirrors the C original: $exec1 dispatches on the opcode high
;; byte to the $exec_hi_* family functions (same boundaries, same names
;; with a $ prefix); helpers mirror the C helpers ($ea, $delay_slot,
;; $check_int, $advance_timer, ...). One deliberate shape difference:
;; inside the family functions the C `switch` is written as structured
;; if/else chains rather than br_table (same cases, same order); only
;; $exec1's top-level dispatch uses br_table. V8 builds the same jump
;; tables from the chains; the observable dispatch (family boundaries)
;; is identical.
;;
;; Cycle model: the single corrected manual table (DESIGN 4.1). There is
;; no instruction-counter mode and no cycle_model export. $exec1 charges
;; CYCTAB[op] at fetch; $run adds the $cycle_delta override (taken /
;; not-taken branches, repeat-iteration costs); loop forms charge their
;; repeats internally; MMR/IO/PDWSR wait states charge at the access.
;; The timer advances by the instruction's total cycle delta.
;;
;; DEVIATIONS FROM DESIGN.md, recorded here (see the implementation
;; report for the evidence behind each; "follow manual" rows of the
;; DESIGN 8.1 table are implemented as written unless listed here):
;;  V1. PDWSR layout (DESIGN 4.4): the design generalises C's io_ws
;;      formula (8K blocks, CWSR bits 2/3) to PDWSR. That is wrong for
;;      the 'C51: SPRU056D 9.4.1 Table 9-5, Variant A, uses 2-bit fields
;;      per 16K block (program fields PDWSR bits 0-7, data fields bits
;;      8-15) with CWSR bit 0 (P) / bit 1 (D) as the 2->3 / 3->7
;;      mapping (Tables 9-9/9-10). Implemented as $pd_ws_prog/$pd_ws_data
;;      with that layout; charging follows C's io convention (reads +w,
;;      writes +max(0,w-1)). This is the DESIGN 8.5 item-5 verification,
;;      now done. Consequence: with reset PDWSR=FFFF the first 9 fetches
;;      of the smoke workload cost +55 cycles vs the C oracle (which
;;      never reads PDWSR): 7 fetches at 7 wait states (CWSR=0x0F, alt
;;      on) and 2 at 3 (CWSR=0x10, alt off) -- the 0x8006 immediate
;;      fetch still sees CWSR=0x0F because the CWSR write lands after
;;      it. Measured in Gate 1 (per-instruction step trace, 2026-11-16);
;;      the earlier +51 estimate miscounted that fetch.
;;  V2. DXR write (DESIGN 5.4 / 1.6, Rank 33): the design says a DXR
;;      write with XRST=0 stores only (no XRDY clear, no ring entry,
;;      no XINT clear) and that a DXR write clears IFR bit 5. Both
;;      break the smoke vector (IFR must end 0x0028, dxr_ring [0,1]):
;;      the flag is set by the SPC XRST=0 write at 0x8091 while XRDY=0
;;      (which requires the first DXR write to have cleared XRDY) and
;;      survives the DXR write at 0x8096. SPRU056D Table 9-13 says the
;;      SP DXR->XSR copy is "generated directly by DXR write" and
;;      XRDY 0->1 generates XINT -- the write is a set event, not a
;;      clear. Implemented as in C: DXR write always stores, sets
;;      XRDY=0, XSREMPTY=1, appends the ring entry, and never touches
;;      IFR. The ring is glue-visible diagnostic state, not manual
;;      architecture; the C behaviour is what the vector requires.
;;  V3. $check_int IFR clear (DESIGN 5.3): the design's pseudo-code
;;      clears bits i<4 or i>7 (leaving TRNT/TXNT 6-7 set), while its
;;      own prose says bits 6-7 "keep C's trap auto-clear" because no
;;      TDM service path exists in v1. Prose wins: clear every taken
;;      bit except RINT (4) and XINT (5).
;;  V4. IDLE wake on NMI (DESIGN 5.1): the design's wake test only
;;      checks nmi_pending for IDLE2. NMI is unmaskable and wakes IDLE
;;      too (manual 4.10); implemented as a wake source for both.
;;  V5. CALLD/CALAD/CCD push (DESIGN 3.5): the design says "slot, then
;;      push pc+2". After the slot pc has already advanced past the two
;;      slot words, so pushing pc+2 would push start+4. Implemented as
;;      DESIGN intends ("the value is the same"): capture ret=start+2
;;      before the slot, slot first, then push ret.
;;  V6. $handle_rpt (DESIGN 3.3): a nonrepeatable instruction at the
;;      repeat end consumes/clears rptc (DESIGN text). C leaves rptc>0,
;;      which would mask interrupts indefinitely; implemented per
;;      DESIGN text.
;;  V7. REPEATABLE default: forms implemented by the C core but listed
;;      in none of Tables 4-11/4-12/4-13 (MAX/MIN/SWAP 0xBE1B-1D, SFTA
;;      0xBFE0-EF) default to repeatable (only Table 4-13 prohibits).
;;      See tools/gen_tables.py.
;;  V8. Loop-form SARAM repeat costs are not transcribed (DESIGN 8.5
;;      item 4, open): loop forms charge +1 (+2 SMMR/LMMR) per repeat
;;      iteration regardless of operand memory (C parity). See
;;      tools/gen_tables.py D2.
;;  V9. $cycle_delta final-repeat rule (DESIGN 4.3): the design's
;;      constant per-iteration table cannot reproduce the manual's
;;      2n-2 / 2n-1 RPT formulas for SARAM write-back forms. The core
;;      charges p on non-final repeats and q=1 on the final repeat for
;;      the PLU write-back family and DMOV in SARAM (q = 2a+b-s from
;;      the formula). See tools/gen_tables.py D1.
;;  V10. IO-log cycle stamps are (cycm-1) cycles later than the C
;;       oracle's for ANY instruction that logs mid-execution, because
;;       DESIGN 4.1 charges the table value at fetch while C charges a
;;       base 1 at fetch and the rest after exec. Final per-instruction
;;       totals are identical; only the stamp of the event inside the
;;       instruction differs. Measured in Gate 1: the 13 smoke stamps
;;       differ from the cycle_model=1 oracle by exactly V1 + (cycm-1)
;;       -- SPLK +1, OUT +2, SAMM/SAR +0.
;;
;;  GATE 1 AUDIT CORRECTIONS, 2026-11-16 (not deviations -- the first
;;  draft had these families mapped from the wrong table; C and the
;;  manual agree, the draft did not): $exec_hi_80_9f rewritten (SAR /
;;  SAMM / LMMR / POPD / MAR / SPL / SPH / SST / SACL / SACH; SACL and
;;  SACH use C's shift = (op>>8)&7, and the spurious SSTB blocks are
;;  gone); $exec_hi_60_7f rewritten (ADDC / ADD16 / ADDS / ADDT /
;;  SUBB / SUB16 / SUBS / SUBT / ZALR / LACL / LACC16 / LACT / XOR /
;;  OR / AND / BITT / LTA / LTP / LTD / LT / LTS / LPH / PSHD / DMOV /
;;  ADRK / B / CALL / BANZ / SBRK / BD / CALLD / BANZD; RET = 0xEF00
;;  and RETD = 0xFF00 are RETC/RETCD with the always-true condition
;;  and need no case; DMOV is a single execution, repetition via
;;  $handle_rpt); $exec_hi_a0_af rewritten (NORM / MAC / MACD / BLPD
;;  bmar / BLPD #pma / TBLR / TBLW / BLDD / MADS / MADD / SPLK / IN;
;;  loop forms evaluate ea() inside the loop and advance pfc).
;;  All other exec families were audited line-by-line against C in
;;  the same pass and match (00_0f, 10_3f, 40_5f, b0_bf, e0_ff,
;;  be_acc, be_ctrl, be, bf).
;;
;; PERF ports (DESIGN header table): IDLE fast-forward -- yes, verbatim
;; (5.1). Closed-form timer advance -- yes, verbatim (5.2, $advance_timer).
;; Inlined check_int fast path -- yes, same shape (5.3: the condition is
;; inline in $run, $check_int is called only when it can fire).
;; Diagnostics gate -- yes ($g_diag, default 1). ea() circular-buffer
;; cache -- NOT ported (never fires in C). Decoded-instruction cache --
;; NOT ported (v1 fetches from linear memory every time). SIMD -- no.
;; Batching across serial ticks -- no.
;;
;; Memory map (DESIGN 2.1): PM 0x00000, DM 0x20000, IOMEM 0x40000,
;; CYCTAB 0x60000, RPT_DARAM 0x70000, RPT_SARAM 0x80000, TABLES 0x90000
;; (REPEATABLE 0x90000, LEN_HI 0x92000, LEN_BE 0x92100, LEN_BF 0x92200,
;; IVEC 0x92300, IVEC_LEGACY 0x92310, SCRATCH 0x92400: ARs 0x92400,
;; STACK 0x92410, SHADOW 0x92420 (56 bytes used), IVEC_IND 0x92480,
;; MMR_RAW 0x924A0), BP 0xA0000, HITS 0xB0000, PC_HITS 0xF0000,
;; WATCH_HITS 0x130000, TRACE 0x170000, DXR_RING 0x190000,
;; MMR_CTRS 0x1B0000 (mmr_n 0x1B0000, mmr_pc 0x1B0300, mmr_val 0x1B0480,
;; ext_n 0x1B0540, ff_n 0x1B0740, rsv_a/pc 0x1B0F40, pcring 0x1B1000),
;; IOLOG 0x1C0000. 44 pages initial, 64 max. All values little-endian;
;; PM/DM words are addressed base + addr*2.

(module
  ;; Imports: exactly two host functions (DESIGN 7). The harness
  ;; implements them IOMEM-backed for the smoke test (DESIGN 7.4).
  (import "env" "io_read" (func $host_io_read (param i32) (result i32)))
  (import "env" "io_write" (func $host_io_write (param i32 i32)))

  (memory (export "memory") 44 64)

  ;; ---- globals: datapath and control (DESIGN 1.1) ----
  (global $g_acc (mut i32) (i32.const 0))
  (global $g_accb (mut i32) (i32.const 0))
  (global $g_preg (mut i32) (i32.const 0))
  (global $g_treg0 (mut i32) (i32.const 0))
  (global $g_treg1 (mut i32) (i32.const 0))
  (global $g_treg2 (mut i32) (i32.const 0))
  (global $g_arp (mut i32) (i32.const 0))
  (global $g_arb (mut i32) (i32.const 0))
  (global $g_dp (mut i32) (i32.const 0))       ;; pre-shifted << 7
  (global $g_ov (mut i32) (i32.const 0))
  (global $g_ovm (mut i32) (i32.const 0))
  (global $g_intm (mut i32) (i32.const 1))
  (global $g_cnf (mut i32) (i32.const 0))
  (global $g_tc (mut i32) (i32.const 0))
  (global $g_sxm (mut i32) (i32.const 1))
  (global $g_c (mut i32) (i32.const 1))
  (global $g_hm (mut i32) (i32.const 1))
  (global $g_xf (mut i32) (i32.const 1))
  (global $g_pm (mut i32) (i32.const 0))
  (global $g_iptr (mut i32) (i32.const 0))
  (global $g_avis (mut i32) (i32.const 0))
  (global $g_ovly (mut i32) (i32.const 0))
  (global $g_ram (mut i32) (i32.const 0))
  (global $g_mpmc (mut i32) (i32.const 0))
  (global $g_ndx (mut i32) (i32.const 0))
  (global $g_trm (mut i32) (i32.const 0))
  (global $g_braf (mut i32) (i32.const 0))
  (global $g_pc (mut i32) (i32.const 0))
  (global $g_op (mut i32) (i32.const 0))
  (global $g_sp (mut i32) (i32.const 0))
  (global $g_rptc (mut i32) (i32.const 0))
  (global $g_rpt_start (mut i32) (i32.const 0))
  (global $g_rpt_end (mut i32) (i32.const 0))
  (global $g_ifr (mut i32) (i32.const 0))
  (global $g_imr (mut i32) (i32.const 0))
  (global $g_indx (mut i32) (i32.const 0))
  (global $g_arcr (mut i32) (i32.const 0))
  (global $g_cbsr1 (mut i32) (i32.const 0))
  (global $g_cber1 (mut i32) (i32.const 0))
  (global $g_cbsr2 (mut i32) (i32.const 0))
  (global $g_cber2 (mut i32) (i32.const 0))
  (global $g_cbcr (mut i32) (i32.const 0))
  (global $g_bmar (mut i32) (i32.const 0))
  (global $g_dbmr (mut i32) (i32.const 0))
  (global $g_pasr (mut i32) (i32.const 0))
  (global $g_paer (mut i32) (i32.const 0))
  (global $g_brcr (mut i32) (i32.const 0))
  (global $g_io_rep (mut i32) (i32.const 0))
  (global $g_xc_left (mut i32) (i32.const 0))
  (global $g_xc_new (mut i32) (i32.const 0))
  (global $g_cycles (mut i64) (i64.const 0))
  (global $g_idle (mut i32) (i32.const 0))     ;; 0 running, 1 IDLE, 2 IDLE2
  (global $g_idle_cycles (mut i64) (i64.const 0))
  (global $g_timer_exp (mut i64) (i64.const 0))
  (global $g_stop (mut i32) (i32.const 0))
  (global $g_status (mut i32) (i32.const 0))   ;; 0 OK, 1 BP, 2 BADOP, 3 STOP
  (global $g_bio (mut i32) (i32.const 0))
  (global $g_words (mut i32) (i32.const 0))
  (global $g_rep_cont (mut i32) (i32.const 0))
  (global $g_cur_pc (mut i32) (i32.const 0))
  (global $g_ar0_dirty (mut i32) (i32.const 0))
  (global $g_int_inh (mut i32) (i32.const 0))
  (global $g_taken (mut i32) (i32.const 0))    ;; new in WAT (Rank 25)
  (global $g_prev_swmc (mut i32) (i32.const 0)) ;; new in WAT (4.7.2)
  (global $g_cond_latched (mut i32) (i32.const 0)) ;; new in WAT (Rank 8)
  (global $g_ar0_ndx_at_write (mut i32) (i32.const 0)) ;; new (Rank 47)
  (global $g_nmi_pending (mut i32) (i32.const 0)) ;; new in WAT (Rank 48)
  (global $g_tss_arm (mut i32) (i32.const 0))   ;; new in WAT (9.3.1)
  (global $g_diag (mut i32) (i32.const 1))
  (global $g_ea_saram (mut i32) (i32.const 0))  ;; last $ea result in SARAM
  ;; ---- peripherals (DESIGN 1.3) ----
  (global $g_greg (mut i32) (i32.const 0))
  (global $g_drr (mut i32) (i32.const 0))
  (global $g_dxr (mut i32) (i32.const 0))
  (global $g_spc (mut i32) (i32.const 0))
  (global $g_tim (mut i32) (i32.const 0xFFFF))
  (global $g_prd (mut i32) (i32.const 0xFFFF))
  (global $g_tcr_tddr (mut i32) (i32.const 0))
  (global $g_psc (mut i32) (i32.const 0))
  (global $g_tss (mut i32) (i32.const 0))
  (global $g_pdwsr (mut i32) (i32.const 0xFFFF))
  (global $g_iowsr (mut i32) (i32.const 0xFFFF))
  (global $g_cwsr (mut i32) (i32.const 0x0F))
  (global $g_xrdy (mut i32) (i32.const 1))
  (global $g_rrdy (mut i32) (i32.const 0))
  (global $g_xsrempty (mut i32) (i32.const 0))
  (global $g_rsrfull (mut i32) (i32.const 0))
  (global $g_tcr_soft (mut i32) (i32.const 0))
  (global $g_tcr_free (mut i32) (i32.const 0))
  ;; ---- diagnostics / log heads (DESIGN 1.6) ----
  (global $g_dxr_head (mut i32) (i32.const 0))
  (global $g_iolog_n (mut i32) (i32.const 0))
  (global $g_iolog_on (mut i32) (i32.const 0))
  (global $g_pcring_i (mut i32) (i32.const 0))
  (global $g_trace_n (mut i32) (i32.const 0))
  (global $g_trace_pc (mut i32) (i32.const -1))
  (global $g_watch_a (mut i32) (i32.const -1))

;; __TABLES__

  ;; ================= helpers: AR file, stack, status =================
  ;; ARs live in scratch memory at 0x92400 (8 x u16). Every AR0 write
  ;; funnels through $ar_set, which sets ar0_dirty and snapshots NDX
  ;; (Rank 47).

  (func $ar_get (param $i i32) (result i32)
    (i32.load16_u offset=0x92400
      (i32.shl (local.get $i) (i32.const 1))))

  (func $ar_set (param $i i32) (param $v i32)
    (i32.store16 offset=0x92400
      (i32.shl (local.get $i) (i32.const 1))
      (local.get $v))
    (if (i32.eqz (local.get $i))
      (then
        (global.set $g_ar0_dirty (i32.const 1))
        (global.set $g_ar0_ndx_at_write (global.get $g_ndx)))))

  ;; Hardware stack at 0x92410 (8 x u16). push: sp=(sp-1)&7.
  ;; pop duplicates the new second-from-top entry into the vacated
  ;; slot (C quirk, ported verbatim).
  (func $stack_push (param $v i32)
    (global.set $g_sp
      (i32.and (i32.sub (global.get $g_sp) (i32.const 1)) (i32.const 7)))
    (i32.store16 offset=0x92410
      (i32.shl (global.get $g_sp) (i32.const 1)) (local.get $v)))

  (func $stack_pop (result i32) (local $v i32)
    (local.set $v
      (i32.load16_u offset=0x92410
        (i32.shl (global.get $g_sp) (i32.const 1))))
    (global.set $g_sp
      (i32.and (i32.add (global.get $g_sp) (i32.const 1)) (i32.const 7)))
    ;; stack[(sp+7)&7] = stack[(sp+6)&7]  (sp already incremented)
    (i32.store16 offset=0x92410
      (i32.shl (i32.and (i32.add (global.get $g_sp) (i32.const 7))
                        (i32.const 7)) (i32.const 1))
      (i32.load16_u offset=0x92410
        (i32.shl (i32.and (i32.add (global.get $g_sp) (i32.const 6))
                          (i32.const 7)) (i32.const 1))))
    (local.get $v))

  ;; ST0 = (ARP<<13)|(OV<<12)|(OVM<<11)|(1<<10)|(INTM<<9)|(DP>>7).
  (func $st0_get (result i32)
    (i32.or
      (i32.or
        (i32.shl (global.get $g_arp) (i32.const 13))
        (i32.shl (global.get $g_ov) (i32.const 12)))
      (i32.or
        (i32.or
          (i32.shl (global.get $g_ovm) (i32.const 11))
          (i32.const 0x400))
        (i32.or
          (i32.shl (global.get $g_intm) (i32.const 9))
          (i32.shr_u (global.get $g_dp) (i32.const 7))))))

  ;; ST1: bits 8,7,5,3,2 hardwired 1.
  (func $st1_get (result i32)
    (i32.or
      (i32.or
        (i32.shl (global.get $g_arb) (i32.const 13))
        (i32.shl (global.get $g_cnf) (i32.const 12)))
      (i32.or
        (i32.or
          (i32.shl (global.get $g_tc) (i32.const 11))
          (i32.shl (global.get $g_sxm) (i32.const 10)))
        (i32.or
          (i32.or
            (i32.shl (global.get $g_c) (i32.const 9))
            (i32.const 0x1AC)) ;; bits 8,7,5,3,2
          (i32.or
            (i32.shl (global.get $g_hm) (i32.const 6))
            (i32.or
              (i32.shl (global.get $g_xf) (i32.const 4))
              (global.get $g_pm)))))))

  ;; PMST = (IPTR<<11)|(AVIS<<7)|(OVLY<<5)|(RAM<<4)|(MPMC<<3)|(NDX<<2)|(TRM<<1)|BRAF.
  (func $pmst_get (result i32)
    (i32.or
      (i32.or
        (i32.shl (global.get $g_iptr) (i32.const 11))
        (i32.shl (global.get $g_avis) (i32.const 7)))
      (i32.or
        (i32.or
          (i32.shl (global.get $g_ovly) (i32.const 5))
          (i32.shl (global.get $g_ram) (i32.const 4)))
        (i32.or
          (i32.or
            (i32.shl (global.get $g_mpmc) (i32.const 3))
            (i32.shl (global.get $g_ndx) (i32.const 2)))
          (i32.or
            (i32.shl (global.get $g_trm) (i32.const 1))
            (global.get $g_braf))))))

  ;; ================= program-space pointer (DESIGN 2.3) ==============
  ;; Returns a byte offset into linear memory. CNF B0 and RAM SARAM
  ;; resolve into the DM array (internal); everything else is the PM array.
  (func $pm_ptr (param $a i32) (result i32)
    (if (result i32)
      (i32.and (global.get $g_cnf) (i32.ge_u (local.get $a) (i32.const 0xFE00)))
      (then (i32.add (i32.const 0x20000)
              (i32.shl (i32.add (i32.sub (local.get $a) (i32.const 0xFE00))
                                (i32.const 0x100)) (i32.const 1))))
      (else
        (if (result i32)
          (i32.and (global.get $g_ram)
            (i32.and (i32.ge_u (local.get $a) (i32.const 0x2000))
                     (i32.lt_u (local.get $a) (i32.const 0x2400))))
          (then (i32.add (i32.const 0x20000)
                  (i32.shl (i32.add (i32.sub (local.get $a) (i32.const 0x2000))
                                    (i32.const 0x800)) (i32.const 1))))
          (else (i32.shl (local.get $a) (i32.const 1)))))))

  ;; True when a program address resolves into internal RAM (no wait states).
  (func $pm_is_internal (param $a i32) (result i32)
    (i32.or
      (i32.and (global.get $g_cnf) (i32.ge_u (local.get $a) (i32.const 0xFE00)))
      (i32.and (global.get $g_ram)
        (i32.and (i32.ge_u (local.get $a) (i32.const 0x2000))
                 (i32.lt_u (local.get $a) (i32.const 0x2400))))))

  ;; ================= wait states (DESIGN 4.4; manual 9.4) =============
  ;; $io_ws: IOWSR/CWSR (manual 9.4.2/9.4.3, as in C). BIG=1: 8K blocks
  ;; (port>>13); BIG=0: port pairs ((port>>1)&7). Alt bit: CWSR bit 2
  ;; for fields 1-4, bit 3 for fields 5-8; alt maps 2->3, 3->7.
  (func $io_ws (param $port i32) (result i32)
    (local $idx i32) (local $f i32) (local $alt i32)
    (if (i32.and (global.get $g_cwsr) (i32.const 0x10))
      (then (local.set $idx (i32.shr_u (local.get $port) (i32.const 13))))
      (else (local.set $idx
              (i32.and (i32.shr_u (local.get $port) (i32.const 1))
                       (i32.const 7)))))
    (local.set $f
      (i32.and (i32.shr_u (global.get $g_iowsr)
                          (i32.shl (local.get $idx) (i32.const 1)))
               (i32.const 3)))
    (if (i32.lt_u (local.get $idx) (i32.const 4))
      (then (local.set $alt (i32.and (i32.shr_u (global.get $g_cwsr)
                                                (i32.const 2)) (i32.const 1))))
      (else (local.set $alt (i32.and (i32.shr_u (global.get $g_cwsr)
                                                (i32.const 3)) (i32.const 1)))))
    (if (result i32) (local.get $alt)
      (then
        (if (result i32) (i32.eq (local.get $f) (i32.const 3))
          (then (i32.const 7))
          (else
            (if (result i32) (i32.eq (local.get $f) (i32.const 2))
              (then (i32.const 3)) (else (local.get $f))))))
      (else (local.get $f))))

  ;; $pd_ws: PDWSR wait count for one external access (manual 9.4.1
  ;; Variant A, 'C51 -- see deviation V1). Program space: 16K block
  ;; (a>>14) selects a 2-bit field in PDWSR bits 0-7; data space: the
  ;; same block selects a field in PDWSR bits 8-15. Alt mapping from
  ;; CWSR bit 0 (program) / bit 1 (data): 2->3, 3->7.
  (func $pd_ws (param $a i32) (param $is_data i32) (result i32)
    (local $f i32) (local $alt i32)
    (if (local.get $is_data)
      (then
        (local.set $f
          (i32.and (i32.shr_u (global.get $g_pdwsr)
                              (i32.add (i32.const 8)
                                       (i32.shl (i32.shr_u (local.get $a)
                                                           (i32.const 14))
                                                (i32.const 1))))
                   (i32.const 3)))
        (local.set $alt (i32.and (i32.shr_u (global.get $g_cwsr)
                                            (i32.const 1)) (i32.const 1))))
      (else
        (local.set $f
          (i32.and (i32.shr_u (global.get $g_pdwsr)
                              (i32.shl (i32.shr_u (local.get $a)
                                                  (i32.const 14))
                                       (i32.const 1)))
                   (i32.const 3)))
        (local.set $alt (i32.and (global.get $g_cwsr) (i32.const 1)))))
    (if (result i32) (local.get $alt)
      (then
        (if (result i32) (i32.eq (local.get $f) (i32.const 3))
          (then (i32.const 7))
          (else
            (if (result i32) (i32.eq (local.get $f) (i32.const 2))
              (then (i32.const 3)) (else (local.get $f))))))
      (else (local.get $f))))

  (func $cycles_add (param $n i64)
    (global.set $g_cycles (i64.add (global.get $g_cycles) (local.get $n))))

  ;; ================= I/O log (DESIGN 1.6) ============================
  ;; Entry: 16 bytes at IOLOG + n*16: CYC i64 @0, PC u16 @8, PORT u16 @10,
  ;; VAL u16 @12, WR u8 @14. Gated on iolog_on, capacity 65536.
  (func $iolog_add (param $port i32) (param $val i32) (param $wr i32)
    (local $base i32)
    (if (i32.and (global.get $g_iolog_on)
                 (i32.lt_u (global.get $g_iolog_n) (i32.const 65536)))
      (then
        (local.set $base
          (i32.add (i32.const 0x1C0000)
                   (i32.shl (global.get $g_iolog_n) (i32.const 4))))
        (i64.store (local.get $base) (global.get $g_cycles))
        (i32.store16 offset=8 (local.get $base) (global.get $g_cur_pc))
        (i32.store16 offset=10 (local.get $base) (local.get $port))
        (i32.store16 offset=12 (local.get $base) (local.get $val))
        (i32.store8 offset=14 (local.get $base) (local.get $wr))
        (global.set $g_iolog_n
          (i32.add (global.get $g_iolog_n) (i32.const 1))))))

  ;; ================= host I/O ports (DESIGN 2.2/2.4) ==================
  ;; Reads add the full wait count; writes add max(0, w-1) (manual
  ;; Table 9-7, as in C). The log records cycles AFTER the wait charge.
  (func $io_read (param $port i32) (result i32) (local $v i32)
    (call $cycles_add
      (i64.extend_i32_u (call $io_ws (local.get $port))))
    (local.set $v (call $host_io_read (local.get $port)))
    (call $iolog_add (local.get $port) (local.get $v) (i32.const 0))
    (local.get $v))

  (func $io_write (param $port i32) (param $v i32) (local $w i32)
    (local.set $w (call $io_ws (local.get $port)))
    (if (i32.gt_u (local.get $w) (i32.const 1))
      (then (call $cycles_add
              (i64.extend_i32_u (i32.sub (local.get $w) (i32.const 1))))))
    (call $iolog_add (local.get $port) (local.get $v) (i32.const 1))
    (call $host_io_write (local.get $port) (local.get $v)))

  ;; ================= memory-mapped registers (DESIGN 1.4/2.4) ========
  ;; MMR counter bases (DESIGN 2.1): mmr_n 0x1B0000 ([wr][a], u32),
  ;; mmr_pc 0x1B0300 ([wr][a], u16), mmr_val 0x1B0480 (u16),
  ;; ext_n 0x1B0540 ([wr][blk], u32), ff_n 0x1B0740 ([wr][i], u32),
  ;; rsv_a 0x1B0F40, rsv_pc 0x1B0F42, pcring 0x1B1000 (256 x u16).

  (func $mmr_rd (param $a i32) (result i32)
    (if (i32.and (global.get $g_diag) (i32.lt_u (local.get $a) (i32.const 0x60)))
      (then
        (i32.store offset=0x1B0000
          (i32.shl (local.get $a) (i32.const 2))
          (i32.add (i32.load offset=0x1B0000
                      (i32.shl (local.get $a) (i32.const 2))) (i32.const 1)))
        (i32.store16 offset=0x1B0300
          (i32.shl (local.get $a) (i32.const 1)) (global.get $g_cur_pc))))
    (if (result i32) (i32.ge_u (local.get $a) (i32.const 0x50))
      (then (call $io_read (local.get $a)))
      (else
        (if (result i32)
          (i32.and (i32.ge_u (local.get $a) (i32.const 0x10))
                   (i32.lt_u (local.get $a) (i32.const 0x18)))
          (then (call $ar_get (i32.sub (local.get $a) (i32.const 0x10))))
          (else
            (if (result i32) (i32.eq (local.get $a) (i32.const 0x04))
              (then (i32.and (global.get $g_imr) (i32.const 0x1FF)))
              (else
                (if (result i32) (i32.eq (local.get $a) (i32.const 0x05))
                  (then (i32.or (i32.const 0xFF00) (global.get $g_greg)))
                  (else
                    (if (result i32) (i32.eq (local.get $a) (i32.const 0x06))
                      (then (i32.and (global.get $g_ifr) (i32.const 0x1FF)))
                      (else
                        (if (result i32) (i32.eq (local.get $a) (i32.const 0x07))
                          (then (call $pmst_get))
                          (else
                            (if (result i32) (i32.eq (local.get $a) (i32.const 0x08))
                              (then (i32.and (global.get $g_rptc) (i32.const 0xFFFF)))
                              (else
                                (if (result i32) (i32.eq (local.get $a) (i32.const 0x09))
                                  (then (i32.and (global.get $g_brcr) (i32.const 0xFFFF)))
                                  (else
                                    (if (result i32) (i32.eq (local.get $a) (i32.const 0x0A))
                                      (then (global.get $g_pasr))
                                      (else
                                        (if (result i32) (i32.eq (local.get $a) (i32.const 0x0B))
                                          (then (global.get $g_paer))
                                          (else
                                            (if (result i32) (i32.eq (local.get $a) (i32.const 0x0C))
                                              (then (global.get $g_treg0))
                                              (else
                                                (if (result i32) (i32.eq (local.get $a) (i32.const 0x0D))
                                                  (then (i32.and (global.get $g_treg1) (i32.const 0x1F)))
                                                  (else
                                                    (if (result i32) (i32.eq (local.get $a) (i32.const 0x0E))
                                                      (then (i32.and (global.get $g_treg2) (i32.const 0xF)))
                                                      (else
                                                        (if (result i32) (i32.eq (local.get $a) (i32.const 0x0F))
                                                          (then (global.get $g_dbmr))
                                                          (else
                                                            (if (result i32) (i32.eq (local.get $a) (i32.const 0x18))
                                                              (then (global.get $g_indx))
                                                              (else
                                                                (if (result i32) (i32.eq (local.get $a) (i32.const 0x19))
                                                                  (then (global.get $g_arcr))
                                                                  (else
                                                                    (if (result i32) (i32.eq (local.get $a) (i32.const 0x1A))
                                                                      (then (global.get $g_cbsr1))
                                                                      (else
                                                                        (if (result i32) (i32.eq (local.get $a) (i32.const 0x1B))
                                                                          (then (global.get $g_cber1))
                                                                          (else
                                                                            (if (result i32) (i32.eq (local.get $a) (i32.const 0x1C))
                                                                              (then (global.get $g_cbsr2))
                                                                              (else
                                                                                (if (result i32) (i32.eq (local.get $a) (i32.const 0x1D))
                                                                                  (then (global.get $g_cber2))
                                                                                  (else
                                                                                    (if (result i32) (i32.eq (local.get $a) (i32.const 0x1E))
                                                                                      (then (global.get $g_cbcr))
                                                                                      (else
                                                                                        (if (result i32) (i32.eq (local.get $a) (i32.const 0x1F))
                                                                                          (then (global.get $g_bmar))
                                                                                          (else (call $mmr_rd_rest (local.get $a)))))))))))))))))))))))))))))))))))))))))))))))

  ;; MMR reads 0x20-0x2A and the TDM/reserved default (split out so the
  ;; if-chain above stays readable).
  (func $mmr_rd_rest (param $a i32) (result i32)
    (if (result i32) (i32.eq (local.get $a) (i32.const 0x20))
      (then
        ;; Reading DRR clears RRDY / RSRFULL and IFR bit 4 (Rank 31).
        (global.set $g_rrdy (i32.const 0))
        (global.set $g_rsrfull (i32.const 0))
        (global.set $g_ifr
          (i32.and (global.get $g_ifr) (i32.const 0xFFEF)))
        (global.get $g_drr))
      (else
        (if (result i32) (i32.eq (local.get $a) (i32.const 0x21))
          (then (global.get $g_dxr))
          (else
            (if (result i32) (i32.eq (local.get $a) (i32.const 0x22))
              (then
                (i32.or
                  (i32.or
                    (i32.and (global.get $g_spc) (i32.const 0xC0FE))
                    (i32.shl (global.get $g_rsrfull) (i32.const 13)))
                  (i32.or
                    (i32.or
                      (i32.shl (global.get $g_xsrempty) (i32.const 12))
                      (i32.shl (global.get $g_xrdy) (i32.const 11)))
                    (i32.shl (global.get $g_rrdy) (i32.const 10)))))
              (else
                (if (result i32) (i32.eq (local.get $a) (i32.const 0x24))
                  (then (global.get $g_tim))
                  (else
                    (if (result i32) (i32.eq (local.get $a) (i32.const 0x25))
                      (then (global.get $g_prd))
                      (else
                        (if (result i32) (i32.eq (local.get $a) (i32.const 0x26))
                          (then
                            ;; TCR readback: Soft(11) Free(10) PSC(9-6)
                            ;; TSS(4) TDDR(3-0); TRB reads 0.
                            (i32.or
                              (i32.or
                                (i32.shl (global.get $g_tcr_soft) (i32.const 11))
                                (i32.shl (global.get $g_tcr_free) (i32.const 10)))
                              (i32.or
                                (i32.shl (i32.and (global.get $g_psc) (i32.const 0xF))
                                         (i32.const 6))
                                (i32.or
                                  (i32.shl (global.get $g_tss) (i32.const 4))
                                  (global.get $g_tcr_tddr)))))
                          (else
                            (if (result i32) (i32.eq (local.get $a) (i32.const 0x28))
                              (then (global.get $g_pdwsr))
                              (else
                                (if (result i32) (i32.eq (local.get $a) (i32.const 0x29))
                                  (then (global.get $g_iowsr))
                                  (else
                                    (if (result i32) (i32.eq (local.get $a) (i32.const 0x2A))
                                      (then (global.get $g_cwsr))
                                      (else
                                        ;; TDM 0x30-0x37: RAM-backed;
                                        ;; reserved: reads 0 (Rank 37).
                                        (if (result i32)
                                          (i32.and (i32.ge_u (local.get $a) (i32.const 0x30))
                                                   (i32.le_u (local.get $a) (i32.const 0x37)))
                                          (then
                                            (i32.load16_u offset=0x924A0
                                              (i32.shl (local.get $a) (i32.const 1))))
                                          (else (i32.const 0))))))))))))))))))))))

  (func $mmr_wr (param $a i32) (param $d i32) (local $n i32)
    (if (i32.and (global.get $g_diag) (i32.lt_u (local.get $a) (i32.const 0x60)))
      (then
        (i32.store offset=0x1B0000
          (i32.add (i32.const 384) (i32.shl (local.get $a) (i32.const 2)))
          (i32.add (i32.load offset=0x1B0000
                      (i32.add (i32.const 384)
                               (i32.shl (local.get $a) (i32.const 2))))
                   (i32.const 1)))
        (i32.store16 offset=0x1B0300
          (i32.add (i32.const 192) (i32.shl (local.get $a) (i32.const 1)))
          (global.get $g_cur_pc))
        (local.set $n
          (i32.load offset=0x1B0000
            (i32.add (i32.const 384) (i32.shl (local.get $a) (i32.const 2)))))
        ;; mmr_val keeps the first value written, except low MMRs
        ;; (<0x10), 0x1A-0x2A and 0x32, which always update (C quirk).
        (if (i32.or
              (i32.or
                (i32.le_u (local.get $n) (i32.const 1))
                (i32.lt_u (local.get $a) (i32.const 0x10)))
              (i32.or
                (i32.and (i32.ge_u (local.get $a) (i32.const 0x1A))
                         (i32.le_u (local.get $a) (i32.const 0x2A)))
                (i32.eq (local.get $a) (i32.const 0x32))))
          (then
            (i32.store16 offset=0x1B0480
              (i32.shl (local.get $a) (i32.const 1)) (local.get $d))))))
    (if (i32.ge_u (local.get $a) (i32.const 0x50))
      (then (call $io_write (local.get $a) (local.get $d)) (return)))
    (if (i32.and (i32.ge_u (local.get $a) (i32.const 0x10))
                 (i32.lt_u (local.get $a) (i32.const 0x18)))
      (then
        (call $ar_set (i32.sub (local.get $a) (i32.const 0x10)) (local.get $d))
        (return)))
    (if (i32.eq (local.get $a) (i32.const 0x04))
      (then (global.set $g_imr (i32.and (local.get $d) (i32.const 0x1FF))) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x05))
      (then (global.set $g_greg (i32.and (local.get $d) (i32.const 0xFF))) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x06))
      (then
        (global.set $g_ifr
          (i32.and (global.get $g_ifr)
                   (i32.and (i32.xor (local.get $d) (i32.const -1))
                            (i32.const 0xFFFF))))
        (return)))
    (if (i32.eq (local.get $a) (i32.const 0x07))
      (then (call $pmst_set (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x08))
      (then (global.set $g_rptc (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x09))
      (then (global.set $g_brcr (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x0A))
      (then (global.set $g_pasr (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x0B))
      (then (global.set $g_paer (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x0C))
      (then (global.set $g_treg0 (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x0D))
      (then (global.set $g_treg1 (i32.and (local.get $d) (i32.const 0x1F))) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x0E))
      (then (global.set $g_treg2 (i32.and (local.get $d) (i32.const 0xF))) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x0F))
      (then (global.set $g_dbmr (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x18))
      (then (global.set $g_indx (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x19))
      (then (global.set $g_arcr (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x1A))
      (then (global.set $g_cbsr1 (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x1B))
      (then (global.set $g_cber1 (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x1C))
      (then (global.set $g_cbsr2 (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x1D))
      (then (global.set $g_cber2 (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x1E))
      (then (global.set $g_cbcr (i32.and (local.get $d) (i32.const 0xFF))) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x1F))
      (then (global.set $g_bmar (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x20))
      (then (global.set $g_drr (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x21))
      (then
        ;; DXR write (deviation V2: C behaviour, not DESIGN Rank 33):
        ;; always store, XRDY=0, XSREMPTY=1, ring append, no IFR change.
        (global.set $g_dxr (local.get $d))
        (global.set $g_xrdy (i32.const 0))
        (global.set $g_xsrempty (i32.const 1))
        (i32.store16 offset=0x190000
          (i32.shl (i32.and (global.get $g_dxr_head) (i32.const 0xFFFF))
                   (i32.const 1))
          (local.get $d))
        (global.set $g_dxr_head (i32.add (global.get $g_dxr_head) (i32.const 1)))
        (call $iolog_add
          (i32.or (i32.const 0x8000) (local.get $a)) (local.get $d)
          (i32.const 1))
        (return)))
    (if (i32.eq (local.get $a) (i32.const 0x22))
      (then
        (global.set $g_spc (i32.and (local.get $d) (i32.const 0xC0FE)))
        (if (i32.eqz (i32.and (local.get $d) (i32.const 0x80)))
          (then
            (global.set $g_rrdy (i32.const 0))
            (global.set $g_rsrfull (i32.const 0))))
        (if (i32.eqz (i32.and (local.get $d) (i32.const 0x40)))
          (then
            (if (i32.eqz (global.get $g_xrdy))
              (then
                (global.set $g_ifr
                  (i32.or (global.get $g_ifr) (i32.const 0x20)))))
            (global.set $g_xsrempty (i32.const 0))
            (global.set $g_xrdy (i32.const 1))))
        (call $iolog_add
          (i32.or (i32.const 0x8000) (local.get $a)) (local.get $d)
          (i32.const 1))
        (return)))
    (if (i32.eq (local.get $a) (i32.const 0x24))
      (then (global.set $g_tim (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x25))
      (then (global.set $g_prd (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x26))
      (then (call $tcr_wr (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x28))
      (then (global.set $g_pdwsr (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x29))
      (then (global.set $g_iowsr (local.get $d)) (return)))
    (if (i32.eq (local.get $a) (i32.const 0x2A))
      (then (global.set $g_cwsr (i32.and (local.get $d) (i32.const 0x1F))) (return)))
    ;; Default path: TDM 0x30-0x37 are RAM-backed and logged;
    ;; reserved MMRs: writes ignored (Rank 37) but LOGGED as a
    ;; pseudo-port, matching C (whose mmr_wr tail logs every write
    ;; that reaches it). The value is not stored, so reads still
    ;; return 0.
    (if (i32.and (i32.ge_u (local.get $a) (i32.const 0x30))
                 (i32.le_u (local.get $a) (i32.const 0x37)))
      (then
        (i32.store16 offset=0x924A0
          (i32.shl (local.get $a) (i32.const 1)) (local.get $d))
        (call $iolog_add
          (i32.or (i32.const 0x8000) (local.get $a)) (local.get $d)
          (i32.const 1)))
      (else
        (call $iolog_add
          (i32.or (i32.const 0x8000) (local.get $a)) (local.get $d)
          (i32.const 1)))))

  ;; PMST write: decompose into fields (Rank 40).
  (func $pmst_set (param $d i32)
    (global.set $g_iptr (i32.shr_u (local.get $d) (i32.const 11)))
    (global.set $g_avis (i32.and (i32.shr_u (local.get $d) (i32.const 7)) (i32.const 1)))
    (global.set $g_ovly (i32.and (i32.shr_u (local.get $d) (i32.const 5)) (i32.const 1)))
    (global.set $g_ram (i32.and (i32.shr_u (local.get $d) (i32.const 4)) (i32.const 1)))
    (global.set $g_mpmc (i32.and (i32.shr_u (local.get $d) (i32.const 3)) (i32.const 1)))
    (global.set $g_ndx (i32.and (i32.shr_u (local.get $d) (i32.const 2)) (i32.const 1)))
    (global.set $g_trm (i32.and (i32.shr_u (local.get $d) (i32.const 1)) (i32.const 1)))
    (global.set $g_braf (i32.and (local.get $d) (i32.const 1))))

  ;; TCR write (DESIGN 1.3.2): TDDR = d & 0xF; Soft/Free stored;
  ;; TSS needs two successive writes with TSS=1 to stop the timer
  ;; (manual 9.3.1); TRB reloads TIM<-PRD, PSC<-TDDR and clears tss_arm.
  (func $tcr_wr (param $d i32)
    (global.set $g_tcr_tddr (i32.and (local.get $d) (i32.const 0xF)))
    (global.set $g_tcr_soft (i32.and (i32.shr_u (local.get $d) (i32.const 11)) (i32.const 1)))
    (global.set $g_tcr_free (i32.and (i32.shr_u (local.get $d) (i32.const 10)) (i32.const 1)))
    (if (i32.and (local.get $d) (i32.const 0x10))
      (then
        (global.set $g_tss_arm (i32.add (global.get $g_tss_arm) (i32.const 1)))
        (if (i32.ge_u (global.get $g_tss_arm) (i32.const 2))
          (then (global.set $g_tss (i32.const 1)))))
      (else
        (global.set $g_tss_arm (i32.const 0))
        (global.set $g_tss (i32.const 0))))
    (if (i32.and (local.get $d) (i32.const 0x20))
      (then
        (global.set $g_tim (global.get $g_prd))
        (global.set $g_psc (global.get $g_tcr_tddr))
        (global.set $g_tss_arm (i32.const 0)))
      (else
        (global.set $g_psc (i32.and (i32.shr_u (local.get $d) (i32.const 6))
                                     (i32.const 0xF))))))

  ;; ================= data / program routing (DESIGN 2.2/2.3) =========
  (func $dm_internal (param $a i32) (result i32)
    (i32.or
      (i32.or
        (i32.lt_u (local.get $a) (i32.const 0x80))
        (i32.and
          (i32.and (i32.ge_u (local.get $a) (i32.const 0x100))
                   (i32.lt_u (local.get $a) (i32.const 0x500)))
          (i32.eqz (i32.and (global.get $g_cnf)
                             (i32.lt_u (local.get $a) (i32.const 0x300))))))
      (i32.and (global.get $g_ovly)
               (i32.and (i32.ge_u (local.get $a) (i32.const 0x800))
                        (i32.lt_u (local.get $a) (i32.const 0xC00))))))

  (func $dm_reserved (param $a i32) (result i32)
    (i32.or
      (i32.and (i32.ge_u (local.get $a) (i32.const 0x80))
               (i32.lt_u (local.get $a) (i32.const 0x100)))
      (i32.and (i32.ge_u (local.get $a) (i32.const 0x500))
               (i32.lt_u (local.get $a) (i32.const 0x800)))))

  (func $dm_hostwin (param $a i32) (result i32)
    (i32.and (i32.ge_u (local.get $a) (i32.const 0xFF50))
             (i32.le_u (local.get $a) (i32.const 0xFF5F))))

  ;; Program-space read: external accesses charge PDWSR program waits.
  (func $pm_rd (param $a i32) (result i32)
    (if (result i32) (call $pm_is_internal (local.get $a))
      (then (i32.load16_u (call $pm_ptr (local.get $a))))
      (else
        (call $cycles_add
          (i64.extend_i32_u (call $pd_ws (local.get $a) (i32.const 0))))
        (i32.load16_u (i32.shl (local.get $a) (i32.const 1))))))

  (func $pm_wr (param $a i32) (param $d i32) (local $w i32)
    (if (call $pm_is_internal (local.get $a))
      (then (i32.store16 (call $pm_ptr (local.get $a)) (local.get $d)))
      (else
        (local.set $w (call $pd_ws (local.get $a) (i32.const 0)))
        (if (i32.gt_u (local.get $w) (i32.const 1))
          (then (call $cycles_add
                  (i64.extend_i32_u (i32.sub (local.get $w) (i32.const 1))))))
        (i32.store16 (i32.shl (local.get $a) (i32.const 1)) (local.get $d)))))

  (func $dm_rd (param $a i32) (result i32)
    (if (i32.and (global.get $g_diag)
                 (i32.and (i32.ge_u (local.get $a) (i32.const 0x60))
                          (i32.eqz (call $dm_internal (local.get $a)))))
      (then
        (i32.store offset=0x1B0540
          (i32.shl (i32.shr_u (local.get $a) (i32.const 10)) (i32.const 2))
          (i32.add (i32.load offset=0x1B0540
                      (i32.shl (i32.shr_u (local.get $a) (i32.const 10))
                               (i32.const 2))) (i32.const 1)))
        (if (i32.ge_u (local.get $a) (i32.const 0xFF00))
          (then
            (i32.store offset=0x1B0740
              (i32.shl (i32.and (local.get $a) (i32.const 0xFF)) (i32.const 2))
              (i32.add (i32.load offset=0x1B0740
                          (i32.shl (i32.and (local.get $a) (i32.const 0xFF))
                                   (i32.const 2))) (i32.const 1)))))
        (if (i32.and (i32.ge_u (local.get $a) (i32.const 0x500))
                     (i32.lt_u (local.get $a) (i32.const 0x800)))
          (then
            (i32.store16 (i32.const 0x1B0F40) (local.get $a))
            (i32.store16 (i32.const 0x1B0F42) (global.get $g_cur_pc))))))
    (if (result i32) (i32.lt_u (local.get $a) (i32.const 0x60))
      (then (call $mmr_rd (local.get $a)))
      (else
        (if (result i32) (call $dm_internal (local.get $a))
          (then
            (i32.load16_u offset=0x20000
              (i32.shl (local.get $a) (i32.const 1))))
          (else
            (if (result i32) (call $dm_hostwin (local.get $a))
              (then (call $io_read (local.get $a)))
              (else
                (if (result i32) (call $dm_reserved (local.get $a))
                  (then (i32.const 0)) ;; reserved: reads 0 (Rank 45)
                  (else
                    ;; external: PM array alias + PDWSR data waits.
                    (call $cycles_add
                      (i64.extend_i32_u
                        (call $pd_ws (local.get $a) (i32.const 1))))
                    (i32.load16_u (i32.shl (local.get $a) (i32.const 1))))))))))))

  (func $dm_wr (param $a i32) (param $d i32) (local $w i32)
    ;; Peripheral-MMR writes cost +1 cycle (DESIGN 4.4).
    (if (i32.or
          (i32.and (i32.ge_u (local.get $a) (i32.const 0x20))
                   (i32.le_u (local.get $a) (i32.const 0x2A)))
          (i32.and (i32.ge_u (local.get $a) (i32.const 0x30))
                   (i32.le_u (local.get $a) (i32.const 0x37))))
      (then (call $cycles_add (i64.const 1))))
    (if (global.get $g_diag)
      (then
        (if (i32.and (i32.ge_u (local.get $a) (i32.const 0x60))
                     (i32.eqz (call $dm_internal (local.get $a))))
          (then
            (i32.store offset=0x1B0540
              (i32.add (i32.const 256)
                       (i32.shl (i32.shr_u (local.get $a) (i32.const 10))
                                (i32.const 2)))
              (i32.add (i32.load offset=0x1B0540
                          (i32.add (i32.const 256)
                                   (i32.shl (i32.shr_u (local.get $a)
                                                       (i32.const 10))
                                            (i32.const 2))))
                       (i32.const 1)))))
        (if (i32.ge_u (local.get $a) (i32.const 0xFF00))
          (then
            (i32.store offset=0x1B0740
              (i32.add (i32.const 1024)
                       (i32.shl (i32.and (local.get $a) (i32.const 0xFF))
                                (i32.const 2)))
              (i32.add (i32.load offset=0x1B0740
                          (i32.add (i32.const 1024)
                                   (i32.shl (i32.and (local.get $a)
                                                     (i32.const 0xFF))
                                            (i32.const 2))))
                       (i32.const 1)))))))
    (if (i32.eq (local.get $a) (global.get $g_watch_a))
      (then
        (i32.store offset=0x130000
          (i32.shl (global.get $g_cur_pc) (i32.const 2))
          (i32.add (i32.load offset=0x130000
                      (i32.shl (global.get $g_cur_pc) (i32.const 2)))
                   (i32.const 1)))))
    (if (i32.lt_u (local.get $a) (i32.const 0x60))
      (then (call $mmr_wr (local.get $a) (local.get $d)) (return)))
    (if (call $dm_internal (local.get $a))
      (then
        (i32.store16 offset=0x20000
          (i32.shl (local.get $a) (i32.const 1)) (local.get $d))
        (return)))
    (if (call $dm_hostwin (local.get $a))
      (then (call $io_write (local.get $a) (local.get $d)) (return)))
    (if (call $dm_reserved (local.get $a))
      (then (return))) ;; reserved: writes ignored (Rank 45)
    ;; external: PM array alias + PDWSR data waits (write: +max(0,w-1)).
    (local.set $w (call $pd_ws (local.get $a) (i32.const 1)))
    (if (i32.gt_u (local.get $w) (i32.const 1))
      (then (call $cycles_add
              (i64.extend_i32_u (i32.sub (local.get $w) (i32.const 1))))))
    (i32.store16 (i32.shl (local.get $a) (i32.const 1)) (local.get $d)))

  ;; DMOV/LTD/MACD/MADD write: only within on-chip RAM, and both the
  ;; source and the destination (a+1) must be on-chip (Rank 4).
  (func $dmov_wr (param $a i32) (param $d i32)
    (if (i32.and
          (i32.and (call $dm_internal (local.get $a))
                   (i32.ge_u (local.get $a) (i32.const 0x60)))
          (call $dm_internal
            (i32.and (i32.add (local.get $a) (i32.const 1)) (i32.const 0xFFFF))))
      (then
        (call $dm_wr
          (i32.and (i32.add (local.get $a) (i32.const 1)) (i32.const 0xFFFF))
          (local.get $d)))))

  ;; ================= ALU and addressing (DESIGN 3.4) =================
  ;; do_add/do_sub use a 64-bit intermediate. s16=1: 16-bit form (carry
  ;; set only on carry-out / cleared only on borrow-out). Overflow
  ;; saturates only under OVM; OV is always latched. SUBC is separate
  ;; (no saturation, in exec_hi_00_0f).
  (func $do_add (param $a i32) (param $b i32) (param $cin i32) (param $s16 i32)
        (result i32)
    (local $r i64) (local $res i32) (local $carry i32)
    (local.set $r
      (i64.add (i64.add (i64.extend_i32_u (local.get $a))
                        (i64.extend_i32_u (local.get $b)))
               (i64.extend_i32_u (local.get $cin))))
    (local.set $res (i32.wrap_i64 (local.get $r)))
    (local.set $carry (i32.wrap_i64 (i64.shr_u (local.get $r) (i64.const 32))))
    (if (local.get $s16)
      (then (if (local.get $carry) (then (global.set $g_c (i32.const 1)))))
      (else (global.set $g_c (local.get $carry))))
    (if (i32.and
          (i32.and (i32.xor (local.get $a) (local.get $res))
                   (i32.xor (local.get $b) (local.get $res)))
          (i32.const 0x80000000))
      (then
        (if (global.get $g_ovm)
          (then
            (local.set $res
              (if (result i32) (i32.lt_s (local.get $res) (i32.const 0))
                (then (i32.const 0x7FFFFFFF))
                (else (i32.const 0x80000000))))))
        (global.set $g_ov (i32.const 1))))
    (local.get $res))

  (func $do_sub (param $a i32) (param $b i32) (param $bin i32) (param $s16 i32)
        (result i32)
    (local $r i64) (local $res i32) (local $borrow i32)
    (local.set $r
      (i64.sub (i64.sub (i64.extend_i32_u (local.get $a))
                        (i64.extend_i32_u (local.get $b)))
               (i64.extend_i32_u (local.get $bin))))
    (local.set $res (i32.wrap_i64 (local.get $r)))
    (local.set $borrow (i32.wrap_i64 (i64.shr_u (local.get $r) (i64.const 32))))
    (if (local.get $s16)
      (then (if (local.get $borrow) (then (global.set $g_c (i32.const 0)))))
      (else (global.set $g_c (i32.eqz (local.get $borrow)))))
    (if (i32.and
          (i32.and (i32.xor (local.get $a) (local.get $b))
                   (i32.xor (local.get $a) (local.get $res)))
          (i32.const 0x80000000))
      (then
        (if (global.get $g_ovm)
          (then
            (local.set $res
              (if (result i32) (i32.lt_s (local.get $res) (i32.const 0))
                (then (i32.const 0x7FFFFFFF))
                (else (i32.const 0x80000000))))))
        (global.set $g_ov (i32.const 1))))
    (local.get $res))

  ;; PREG scaled by PM: 0 = as-is, 1 = <<1, 2 = <<4, 3 = >>6 (arithmetic).
  (func $pscale (result i32) (local $p i32)
    (local.set $p (global.get $g_preg))
    (if (result i32) (i32.eq (global.get $g_pm) (i32.const 0))
      (then (local.get $p))
      (else
        (if (result i32) (i32.eq (global.get $g_pm) (i32.const 1))
          (then (i32.shl (local.get $p) (i32.const 1)))
          (else
            (if (result i32) (i32.eq (global.get $g_pm) (i32.const 2))
              (then (i32.shl (local.get $p) (i32.const 4)))
              (else (i32.shr_s (local.get $p) (i32.const 6)))))))))

  ;; Load TREG0; unless TRM, TREG1/TREG2 mirror its low bits.
  (func $set_t0 (param $d i32)
    (global.set $g_treg0 (local.get $d))
    (if (i32.eqz (global.get $g_trm))
      (then
        (global.set $g_treg1 (i32.and (local.get $d) (i32.const 0x1F)))
        (global.set $g_treg2 (i32.and (local.get $d) (i32.const 0xF))))))

  ;; Data -> ACC with shift, honouring SXM.
  (func $ext (param $d i32) (param $sh i32) (result i32)
    (if (result i32) (global.get $g_sxm)
      (then (i32.shl (i32.extend16_s (local.get $d)) (local.get $sh)))
      (else (i32.shl (local.get $d) (local.get $sh)))))

  (func $bitrev16 (param $v i32) (result i32)
    (local $r i32) (local $i i32)
    (local.set $r (i32.const 0))
    (local.set $i (i32.const 0))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (i32.const 16)))
        (if (i32.and (local.get $v) (i32.shl (i32.const 1) (local.get $i)))
          (then
            (local.set $r
              (i32.or (local.get $r)
                      (i32.shl (i32.const 1)
                               (i32.sub (i32.const 15) (local.get $i)))))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)))
    (local.get $r))

  ;; Circular-buffer end test for bit-reversed addressing (Rank 12):
  ;; returns the block start when ARn has reached its block end, else -1.
  ;; Bank 1 wins over bank 2 when both select the same AR.
  (func $circ_end (param $ar i32) (param $v i32) (result i32)
    (local $cenb1 i32) (local $car1 i32) (local $cenb2 i32) (local $car2 i32)
    (local.set $cenb1 (i32.and (i32.shr_u (global.get $g_cbcr) (i32.const 3)) (i32.const 1)))
    (local.set $car1 (i32.and (global.get $g_cbcr) (i32.const 7)))
    (local.set $cenb2 (i32.and (i32.shr_u (global.get $g_cbcr) (i32.const 7)) (i32.const 1)))
    (local.set $car2 (i32.and (i32.shr_u (global.get $g_cbcr) (i32.const 4)) (i32.const 7)))
    (if (result i32)
      (i32.and (i32.and (local.get $cenb1) (i32.eq (local.get $ar) (local.get $car1)))
               (i32.eq (local.get $v) (global.get $g_cber1)))
      (then (global.get $g_cbsr1))
      (else
        (if (result i32)
          (i32.and
            (i32.and
              (i32.eqz (i32.and (local.get $cenb1)
                                (i32.eq (local.get $ar) (local.get $car1))))
              (i32.and (local.get $cenb2) (i32.eq (local.get $ar) (local.get $car2))))
            (i32.eq (local.get $v) (global.get $g_cber2)))
          (then (global.get $g_cbsr2))
          (else (i32.const -1))))))

  ;; Step ARn by step, wrapping to the block start at the block end when
  ;; circular addressing is enabled for that AR.
  (func $upd_ar (param $ar i32) (param $step i32)
    (local $cenb1 i32) (local $car1 i32) (local $cenb2 i32) (local $car2 i32)
    (local $cur i32)
    (if (i32.eqz (local.get $ar))
      (then
        (global.set $g_ar0_dirty (i32.const 1))
        (global.set $g_ar0_ndx_at_write (global.get $g_ndx))))
    (local.set $cenb1 (i32.and (i32.shr_u (global.get $g_cbcr) (i32.const 3)) (i32.const 1)))
    (local.set $car1 (i32.and (global.get $g_cbcr) (i32.const 7)))
    (local.set $cenb2 (i32.and (i32.shr_u (global.get $g_cbcr) (i32.const 7)) (i32.const 1)))
    (local.set $car2 (i32.and (i32.shr_u (global.get $g_cbcr) (i32.const 4)) (i32.const 7)))
    (local.set $cur (call $ar_get (local.get $ar)))
    (if (i32.and (local.get $cenb1) (i32.eq (local.get $ar) (local.get $car1)))
      (then
        (if (i32.eq (local.get $cur) (global.get $g_cber1))
          (then (call $ar_set_noflag (local.get $ar) (global.get $g_cbsr1)))
          (else (call $ar_set_noflag (local.get $ar)
                  (i32.and (i32.add (local.get $cur) (local.get $step))
                           (i32.const 0xFFFF))))))
      (else
        (if (i32.and (local.get $cenb2) (i32.eq (local.get $ar) (local.get $car2)))
          (then
            (if (i32.eq (local.get $cur) (global.get $g_cber2))
              (then (call $ar_set_noflag (local.get $ar) (global.get $g_cbsr2)))
              (else (call $ar_set_noflag (local.get $ar)
                      (i32.and (i32.add (local.get $cur) (local.get $step))
                               (i32.const 0xFFFF))))))
          (else
            (call $ar_set_noflag (local.get $ar)
              (i32.and (i32.add (local.get $cur) (local.get $step))
                       (i32.const 0xFFFF))))))))

  ;; AR store without touching ar0_dirty (used inside $upd_ar, which
  ;; already set the flag/snapshot above).
  (func $ar_set_noflag (param $i i32) (param $v i32)
    (i32.store16 offset=0x92400
      (i32.shl (local.get $i) (i32.const 1)) (local.get $v)))

  ;; Switch ARP, saving the old ARP in ARB.
  (func $upd_arp (param $n i32)
    (global.set $g_arb (global.get $g_arp))
    (global.set $g_arp (local.get $n)))

  ;; Effective address (manual 5.2). Direct: dp | low 7 bits. Indirect:
  ;; AR[ARP] plus the modification in bits 6..3; bit 0 switches ARP.
  ;; Unlisted modification sets RUN_BADOP. Sets $g_ea_saram from the
  ;; returned address (used by $cycle_delta).
  (func $ea (result i32)
    (local $op i32) (local $arp i32) (local $nar i32) (local $m i32)
    (local $a i32) (local $st i32)
    (local.set $op (global.get $g_op))
    (if (result i32) (i32.eqz (i32.and (local.get $op) (i32.const 0x80)))
      (then
        (local.set $a
          (i32.and (i32.or (global.get $g_dp)
                           (i32.and (local.get $op) (i32.const 0x7F)))
                   (i32.const 0xFFFF)))
        (global.set $g_ea_saram
          (i32.and (i32.ge_u (local.get $a) (i32.const 0x800))
                   (i32.lt_u (local.get $a) (i32.const 0xC00))))
        (local.get $a))
      (else
        (local.set $arp (global.get $g_arp))
        (local.set $nar (i32.and (local.get $op) (i32.const 7)))
        (local.set $m (i32.and (i32.shr_u (local.get $op) (i32.const 3)) (i32.const 0xF)))
        (local.set $a (call $ar_get (local.get $arp)))
        (if (i32.eq (i32.and (local.get $m) (i32.const 0xE)) (i32.const 0))
          (then (nop))
          (else
            (if (i32.eq (i32.and (local.get $m) (i32.const 0xE)) (i32.const 2))
              (then (call $upd_ar (local.get $arp) (i32.const -1)))
              (else
                (if (i32.eq (i32.and (local.get $m) (i32.const 0xE)) (i32.const 4))
                  (then (call $upd_ar (local.get $arp) (i32.const 1)))
                  (else
                    (if (i32.eq (i32.and (local.get $m) (i32.const 0xE)) (i32.const 8))
                      (then
                        ;; *BR0-: wrap on the RESULT (Rank 12).
                        (local.set $st
                          (call $circ_end (local.get $arp) (local.get $a)))
                        (if (i32.ge_s (local.get $st) (i32.const 0))
                          (then (call $ar_set_noflag (local.get $arp) (local.get $st)))
                          (else
                            (call $ar_set_noflag (local.get $arp)
                              (call $bitrev16
                                (i32.and
                                  (i32.sub
                                    (call $bitrev16 (local.get $a))
                                    (call $bitrev16 (global.get $g_indx)))
                                  (i32.const 0xFFFF))))))
                        (if (i32.eqz (local.get $arp))
                          (then
                            (global.set $g_ar0_dirty (i32.const 1))
                            (global.set $g_ar0_ndx_at_write (global.get $g_ndx)))))
                      (else
                        (if (i32.eq (i32.and (local.get $m) (i32.const 0xE)) (i32.const 0xA))
                          (then
                            (call $upd_ar (local.get $arp)
                              (i32.sub (i32.const 0)
                                       (i32.extend16_s (global.get $g_indx)))))
                          (else
                            (if (i32.eq (i32.and (local.get $m) (i32.const 0xE)) (i32.const 0xC))
                              (then
                                (call $upd_ar (local.get $arp)
                                  (i32.extend16_s (global.get $g_indx))))
                              (else
                                (if (i32.eq (i32.and (local.get $m) (i32.const 0xE)) (i32.const 0xE))
                                  (then
                                    ;; *BR0+: wrap on the RESULT (Rank 12).
                                    (local.set $st
                                      (call $circ_end (local.get $arp) (local.get $a)))
                                    (if (i32.ge_s (local.get $st) (i32.const 0))
                                      (then (call $ar_set_noflag (local.get $arp) (local.get $st)))
                                      (else
                                        (call $ar_set_noflag (local.get $arp)
                                          (call $bitrev16
                                            (i32.and
                                              (i32.add
                                                (call $bitrev16 (local.get $a))
                                                (call $bitrev16 (global.get $g_indx)))
                                              (i32.const 0xFFFF))))))
                                    (if (i32.eqz (local.get $arp))
                                      (then
                                        (global.set $g_ar0_dirty (i32.const 1))
                                        (global.set $g_ar0_ndx_at_write (global.get $g_ndx)))))
                                  (else
                                    ;; Unlisted modification: BADOP.
                                    (global.set $g_status (i32.const 2))))))))))))))))
        (if (i32.and (local.get $m) (i32.const 1))
          (then (call $upd_arp (local.get $nar))))
        (global.set $g_ea_saram
          (i32.and (i32.ge_u (local.get $a) (i32.const 0x800))
                   (i32.lt_u (local.get $a) (i32.const 0xC00))))
        (local.get $a))))

  ;; SST uses page 0 for direct addressing.
  (func $ea_p0 (result i32)
    (if (result i32) (i32.eqz (i32.and (global.get $g_op) (i32.const 0x80)))
      (then (i32.and (global.get $g_op) (i32.const 0x7F)))
      (else (call $ea))))

  ;; Branch-condition ZLVC field (manual 4.5).
  (func $zlvc_cond (param $zlvc i32) (param $mask i32) (result i32)
    (local $a i32)
    (if (i32.and (local.get $mask) (i32.const 2))
      (then
        (if (i32.and (local.get $zlvc) (i32.const 2))
          (then (if (i32.eqz (global.get $g_ov)) (then (return (i32.const 0)))))
          (else (if (global.get $g_ov) (then (return (i32.const 0))))))))
    (if (i32.and (local.get $mask) (i32.const 1))
      (then
        (if (i32.and (local.get $zlvc) (i32.const 1))
          (then (if (i32.eqz (global.get $g_c)) (then (return (i32.const 0)))))
          (else (if (global.get $g_c) (then (return (i32.const 0))))))))
    (local.set $a (global.get $g_acc))
    (call $zlvc_cond_sw (local.get $zlvc) (local.get $mask)))

  ;; ACC sign/zero tests, keyed by (mask & 0xC) | ((zlvc >> 2) & 3).
  (func $zlvc_cond_sw (param $zlvc i32) (param $mask i32) (result i32)
    (local $k i32) (local $a i32)
    (local.set $k
      (i32.or (i32.and (local.get $mask) (i32.const 0xC))
              (i32.and (i32.shr_u (local.get $zlvc) (i32.const 2)) (i32.const 3))))
    (local.set $a (global.get $g_acc))
    (if (i32.eq (local.get $k) (i32.const 4)) (then (return (i32.gt_s (local.get $a) (i32.const 0)))))
    (if (i32.eq (local.get $k) (i32.const 6)) (then (return (i32.gt_s (local.get $a) (i32.const 0)))))
    (if (i32.eq (local.get $k) (i32.const 12)) (then (return (i32.gt_s (local.get $a) (i32.const 0)))))
    (if (i32.eq (local.get $k) (i32.const 5)) (then (return (i32.lt_s (local.get $a) (i32.const 0)))))
    (if (i32.eq (local.get $k) (i32.const 7)) (then (return (i32.lt_s (local.get $a) (i32.const 0)))))
    (if (i32.eq (local.get $k) (i32.const 13)) (then (return (i32.lt_s (local.get $a) (i32.const 0)))))
    (if (i32.eq (local.get $k) (i32.const 8)) (then (return (i32.ne (local.get $a) (i32.const 0)))))
    (if (i32.eq (local.get $k) (i32.const 9)) (then (return (i32.ne (local.get $a) (i32.const 0)))))
    (if (i32.eq (local.get $k) (i32.const 10)) (then (return (i32.eqz (local.get $a)))))
    (if (i32.eq (local.get $k) (i32.const 11)) (then (return (i32.eqz (local.get $a)))))
    (if (i32.eq (local.get $k) (i32.const 14)) (then (return (i32.ge_s (local.get $a) (i32.const 0)))))
    (if (i32.eq (local.get $k) (i32.const 15)) (then (return (i32.le_s (local.get $a) (i32.const 0)))))
    (i32.const 1))

  ;; TP field: 0 = BIO low, 1 = TC set, 2 = TC clear.
  (func $tp_cond (param $tp i32) (result i32)
    (if (result i32) (i32.eq (local.get $tp) (i32.const 0))
      (then (i32.eqz (global.get $g_bio)))
      (else
        (if (result i32) (i32.eq (local.get $tp) (i32.const 1))
          (then (global.get $g_tc))
          (else
            (if (result i32) (i32.eq (local.get $tp) (i32.const 2))
              (then (i32.eqz (global.get $g_tc)))
              (else (i32.const 1))))))))

  (func $cond (result i32)
    (i32.and
      (call $zlvc_cond
        (i32.and (i32.shr_u (global.get $g_op) (i32.const 4)) (i32.const 0xF))
        (i32.and (global.get $g_op) (i32.const 0xF)))
      (call $tp_cond
        (i32.and (i32.shr_u (global.get $g_op) (i32.const 8)) (i32.const 3)))))

  ;; ================= fetch, delay slot, shadow context ================
  (func $fetch (result i32) (local $v i32)
    (local.set $v (call $pm_rd (global.get $g_pc)))
    (global.set $g_pc (i32.and (i32.add (global.get $g_pc) (i32.const 1))
                               (i32.const 0xFFFF)))
    (global.set $g_words (i32.add (global.get $g_words) (i32.const 1)))
    (local.get $v))

  (func $delay_slot (param $start i32) (local $op0 i32)
    (local.set $op0 (global.get $g_op))
    (block $done
      (loop $loop
        (call $exec1)
        ;; NDX mirror applies between slot words too (Rank 10).
        (call $apply_ar0_mirror)
        (br_if $done
          (i32.ge_u
            (i32.and (i32.sub (global.get $g_pc) (local.get $start))
                     (i32.const 0xFFFF))
            (i32.const 2)))
        (br $loop)))
    (global.set $g_op (local.get $op0)))

  ;; Interrupt shadow context (DESIGN 1.2): ACC/ACCB/PREG, TREG0/1/2,
  ;; ARCR, INDX, then the small fields as u16. INTM and XF are NOT
  ;; shadowed (audit #9 / manual 3.8.3). Layout at 0x92420:
  ;;   +0 ACC u32, +4 ACCB u32, +8 PREG u32,
  ;;   +12 TREG0, +14 TREG1, +16 TREG2, +18 ARCR, +20 INDX (u16),
  ;;   +22 ARP, +24 ARB, +26 DP, +28 OV, +30 OVM, +32 CNF, +34 TC,
  ;;   +36 SXM, +38 C, +40 HM, +42 PM, +44 IPTR, +46 AVIS, +48 OVLY,
  ;;   +50 RAM, +52 MPMC, +54 NDX, +56 TRM, +58 BRAF (u16 each).
  (func $save_ctx
    (i32.store offset=0x92420 (i32.const 0) (global.get $g_acc))
    (i32.store offset=0x92420 (i32.const 4) (global.get $g_accb))
    (i32.store offset=0x92420 (i32.const 8) (global.get $g_preg))
    (i32.store16 offset=0x92420 (i32.const 12) (global.get $g_treg0))
    (i32.store16 offset=0x92420 (i32.const 14) (global.get $g_treg1))
    (i32.store16 offset=0x92420 (i32.const 16) (global.get $g_treg2))
    (i32.store16 offset=0x92420 (i32.const 18) (global.get $g_arcr))
    (i32.store16 offset=0x92420 (i32.const 20) (global.get $g_indx))
    (i32.store16 offset=0x92420 (i32.const 22) (global.get $g_arp))
    (i32.store16 offset=0x92420 (i32.const 24) (global.get $g_arb))
    (i32.store16 offset=0x92420 (i32.const 26) (global.get $g_dp))
    (i32.store16 offset=0x92420 (i32.const 28) (global.get $g_ov))
    (i32.store16 offset=0x92420 (i32.const 30) (global.get $g_ovm))
    (i32.store16 offset=0x92420 (i32.const 32) (global.get $g_cnf))
    (i32.store16 offset=0x92420 (i32.const 34) (global.get $g_tc))
    (i32.store16 offset=0x92420 (i32.const 36) (global.get $g_sxm))
    (i32.store16 offset=0x92420 (i32.const 38) (global.get $g_c))
    (i32.store16 offset=0x92420 (i32.const 40) (global.get $g_hm))
    (i32.store16 offset=0x92420 (i32.const 42) (global.get $g_pm))
    (i32.store16 offset=0x92420 (i32.const 44) (global.get $g_iptr))
    (i32.store16 offset=0x92420 (i32.const 46) (global.get $g_avis))
    (i32.store16 offset=0x92420 (i32.const 48) (global.get $g_ovly))
    (i32.store16 offset=0x92420 (i32.const 50) (global.get $g_ram))
    (i32.store16 offset=0x92420 (i32.const 52) (global.get $g_mpmc))
    (i32.store16 offset=0x92420 (i32.const 54) (global.get $g_ndx))
    (i32.store16 offset=0x92420 (i32.const 56) (global.get $g_trm))
    (i32.store16 offset=0x92420 (i32.const 58) (global.get $g_braf)))

  (func $restore_ctx
    (global.set $g_acc (i32.load offset=0x92420 (i32.const 0)))
    (global.set $g_accb (i32.load offset=0x92420 (i32.const 4)))
    (global.set $g_preg (i32.load offset=0x92420 (i32.const 8)))
    (global.set $g_treg0 (i32.load16_u offset=0x92420 (i32.const 12)))
    (global.set $g_treg1 (i32.load16_u offset=0x92420 (i32.const 14)))
    (global.set $g_treg2 (i32.load16_u offset=0x92420 (i32.const 16)))
    (global.set $g_arcr (i32.load16_u offset=0x92420 (i32.const 18)))
    (global.set $g_indx (i32.load16_u offset=0x92420 (i32.const 20)))
    (global.set $g_arp (i32.load16_u offset=0x92420 (i32.const 22)))
    (global.set $g_arb (i32.load16_u offset=0x92420 (i32.const 24)))
    (global.set $g_dp (i32.load16_u offset=0x92420 (i32.const 26)))
    (global.set $g_ov (i32.load16_u offset=0x92420 (i32.const 28)))
    (global.set $g_ovm (i32.load16_u offset=0x92420 (i32.const 30)))
    (global.set $g_cnf (i32.load16_u offset=0x92420 (i32.const 32)))
    (global.set $g_tc (i32.load16_u offset=0x92420 (i32.const 34)))
    (global.set $g_sxm (i32.load16_u offset=0x92420 (i32.const 36)))
    (global.set $g_c (i32.load16_u offset=0x92420 (i32.const 38)))
    (global.set $g_hm (i32.load16_u offset=0x92420 (i32.const 40)))
    (global.set $g_pm (i32.load16_u offset=0x92420 (i32.const 42)))
    (global.set $g_iptr (i32.load16_u offset=0x92420 (i32.const 44)))
    (global.set $g_avis (i32.load16_u offset=0x92420 (i32.const 46)))
    (global.set $g_ovly (i32.load16_u offset=0x92420 (i32.const 48)))
    (global.set $g_ram (i32.load16_u offset=0x92420 (i32.const 50)))
    (global.set $g_mpmc (i32.load16_u offset=0x92420 (i32.const 52)))
    (global.set $g_ndx (i32.load16_u offset=0x92420 (i32.const 54)))
    (global.set $g_trm (i32.load16_u offset=0x92420 (i32.const 56)))
    (global.set $g_braf (i32.load16_u offset=0x92420 (i32.const 58))))

  ;; ================= timer (DESIGN 5.2) ==============================
  ;; Closed-form advance, verbatim from C's advance_timer(): exactly
  ;; equivalent to calling the per-cycle tick n times. All arithmetic
  ;; is i64; prd+1 and tddr+1 never divide by zero.
  (func $advance_timer (param $n i64)
    (local $p0 i64) (local $first i64) (local $rem i64) (local $e i64)
    (local $t0 i64) (local $e2 i64)
    (if (i32.or (global.get $g_tss) (i64.eqz (local.get $n))) (then (return)))
    (local.set $p0 (i64.extend_i32_s (global.get $g_psc)))
    (local.set $first (i64.add (local.get $p0) (i64.const 1)))
    (if (i64.lt_s (local.get $first) (i64.const 1))
      (then (local.set $first (i64.const 1))))
    (if (i64.gt_u (local.get $first) (local.get $n))
      (then
        (global.set $g_psc
          (i32.wrap_i64 (i64.sub (local.get $p0) (local.get $n))))
        (return)))
    (local.set $rem (i64.sub (local.get $n) (local.get $first)))
    ;; e = 1 + rem / (tddr+1); psc = tddr - (rem % (tddr+1)).
    (local.set $e
      (i64.add (i64.const 1)
               (i64.div_u (local.get $rem)
                          (i64.add (i64.extend_i32_u (global.get $g_tcr_tddr))
                                   (i64.const 1)))))
    (global.set $g_psc
      (i32.wrap_i64
        (i64.sub (i64.extend_i32_u (global.get $g_tcr_tddr))
                 (i64.rem_u (local.get $rem)
                            (i64.add (i64.extend_i32_u (global.get $g_tcr_tddr))
                                     (i64.const 1))))))
    (local.set $t0 (i64.extend_i32_u (global.get $g_tim)))
    (if (i64.le_u (local.get $e) (local.get $t0))
      (then
        (global.set $g_tim
          (i32.wrap_i64 (i64.sub (local.get $t0) (local.get $e))))
        (return)))
    (local.set $e2 (i64.sub (local.get $e) (i64.add (local.get $t0) (i64.const 1))))
    (global.set $g_timer_exp
      (i64.add (global.get $g_timer_exp)
               (i64.add (i64.const 1)
                        (i64.div_u (local.get $e2)
                                   (i64.add (i64.extend_i32_u (global.get $g_prd))
                                            (i64.const 1))))))
    (global.set $g_tim
      (i32.wrap_i64
        (i64.sub (i64.extend_i32_u (global.get $g_prd))
                 (i64.rem_u (local.get $e2)
                            (i64.add (i64.extend_i32_u (global.get $g_prd))
                                     (i64.const 1))))))
    (global.set $g_ifr (i32.or (global.get $g_ifr) (i32.const 0x08))))

  ;; Machine cycles until the next TINT expiry (timer running). At least 1.
  (func $timer_cycles_to_expiry (result i64)
    (local $first i64) (local $need i64)
    (local.set $first (i64.add (i64.extend_i32_s (global.get $g_psc)) (i64.const 1)))
    (if (i64.lt_s (local.get $first) (i64.const 1))
      (then (local.set $first (i64.const 1))))
    (local.set $need
      (if (result i64) (i32.eqz (global.get $g_tim))
        (then (i64.const 1))
        (else (i64.add (i64.extend_i32_u (global.get $g_tim)) (i64.const 1)))))
    (i64.add (local.get $first)
             (i64.mul (i64.sub (local.get $need) (i64.const 1))
                      (i64.add (i64.extend_i32_u (global.get $g_tcr_tddr))
                               (i64.const 1)))))

  ;; ================= interrupts (DESIGN 5.3) =========================
  ;; IVEC offsets live in the TABLES page at 0x92300 (ivec) / 0x92310
  ;; (legacy, HOST EXTENSION). ivec_ind lives in scratch at 0x92480.
  (func $ivec_ind_get (param $i i32) (result i32)
    (i32.load16_u offset=0x92480 (i32.shl (local.get $i) (i32.const 1))))

  ;; Take the highest-priority pending, unmasked interrupt (lowest IFR
  ;; bit first). NMI first (ignores INTM/IMR). Entry costs 4 cycles
  ;; always (Rank 29) and advances the timer by 4. IFR clear: every
  ;; taken bit except RINT(4)/XINT(5) (deviation V3: bits 6-7 also clear).
  (func $check_int (local $pend i32) (local $i i32)
    (if (global.get $g_nmi_pending)
      (then
        (global.set $g_nmi_pending (i32.const 0))
        (global.set $g_intm (i32.const 1))
        (call $stack_push (global.get $g_pc))
        (global.set $g_pc
          (i32.or (i32.shl (global.get $g_iptr) (i32.const 11)) (i32.const 0x24)))
        (global.set $g_idle (i32.const 0))
        (call $save_ctx)
        (call $cycles_add (i64.const 4))
        (call $advance_timer (i64.const 4))
        (return)))
    (local.set $pend (i32.and (global.get $g_ifr) (global.get $g_imr)))
    (if (i32.or (global.get $g_intm) (i32.eqz (local.get $pend))) (then (return)))
    (local.set $i (i32.const 0))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (i32.const 9)))
        (if (i32.and (local.get $pend) (i32.shl (i32.const 1) (local.get $i)))
          (then
            (global.set $g_intm (i32.const 1))
            (call $stack_push (global.get $g_pc))
            (if (call $ivec_ind_get (local.get $i))
              (then
                (global.set $g_pc
                  (call $dm_rd (call $ivec_ind_get (local.get $i)))))
              (else
                (global.set $g_pc
                  (i32.or (i32.shl (global.get $g_iptr) (i32.const 11))
                          (i32.load8_u offset=0x92300 (local.get $i))))))
            ;; Clear the taken flag unless it is RINT(4) or XINT(5).
            (if (i32.and (i32.ne (local.get $i) (i32.const 4))
                         (i32.ne (local.get $i) (i32.const 5)))
              (then
                (global.set $g_ifr
                  (i32.and (global.get $g_ifr)
                           (i32.xor (i32.shl (i32.const 1) (local.get $i))
                                    (i32.const -1))))))
            (global.set $g_idle (i32.const 0))
            (call $save_ctx)
            (call $cycles_add (i64.const 4))
            (call $advance_timer (i64.const 4))
            (return)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop))))

  ;; Interrupt-hold accounting for this instruction (DESIGN 5.3):
  ;; the XC window (xc_new / xc_left, counted in words) and the
  ;; single-word instruction at the end of a repeat block (manual
  ;; 4.7.2), except when the previous instruction was a single-word
  ;; multi-cycle instruction ($g_prev_swmc).
  (func $interrupt_held (result i32) (local $hold i32)
    (local.set $hold (i32.const 0))
    (if (global.get $g_xc_new)
      (then
        (global.set $g_xc_new (i32.const 0))
        (local.set $hold (i32.const 1)))
      (else
        (if (i32.gt_s (global.get $g_xc_left) (i32.const 0))
          (then
            (global.set $g_xc_left
              (i32.sub (global.get $g_xc_left) (global.get $g_words)))))))
    (if (i32.gt_s (global.get $g_xc_left) (i32.const 0))
      (then (local.set $hold (i32.const 1)))
      (else (global.set $g_xc_left (i32.const 0))))
    (if (i32.and
          (i32.and (global.get $g_braf)
                   (i32.eq (global.get $g_pc) (global.get $g_paer)))
          (i32.eqz (global.get $g_prev_swmc)))
      (then (local.set $hold (i32.const 1))))
    (local.get $hold))

  ;; AR0 -> INDX/ARCR mirror (Rank 10/47): mirror iff the NDX value
  ;; at the AR0-write moment was 0 (snapshot, not post-instruction NDX).
  (func $apply_ar0_mirror
    (if (global.get $g_ar0_dirty)
      (then
        (if (i32.eqz (global.get $g_ar0_ndx_at_write))
          (then
            (global.set $g_indx (call $ar_get (i32.const 0)))
            (global.set $g_arcr (call $ar_get (i32.const 0)))))
        (global.set $g_ar0_dirty (i32.const 0)))))

  ;; ================= repeat / block-repeat handling ==================
  ;; $repeatable(op): REPEATABLE bitset at 0x90000 (1 bit per opcode).
  (func $repeatable (param $op i32) (result i32)
    (i32.and
      (i32.shr_u
        (i32.load8_u offset=0x90000 (i32.shr_u (local.get $op) (i32.const 3)))
        (i32.and (local.get $op) (i32.const 7)))
      (i32.const 1)))

  ;; Single-instruction RPT handling (DESIGN 3.3): rewind only when
  ;; the executed instruction is the repeated one AND repeatable; a
  ;; nonrepeatable instruction consumes/clears rptc (deviation V6).
  (func $handle_rpt (param $ppc i32)
    (if (i32.gt_s (global.get $g_rptc) (i32.const 0))
      (then
        (if (i32.eq (local.get $ppc) (global.get $g_rpt_end))
          (then
            (if (call $repeatable
                  (call $pm_rd_nocharge (local.get $ppc)))
              (then
                (global.set $g_pc (global.get $g_rpt_start))
                (global.set $g_rptc (i32.sub (global.get $g_rptc) (i32.const 1)))
                (global.set $g_rep_cont (i32.const 1)))
              (else
                (global.set $g_rptc (i32.const 0))
                (global.set $g_rep_cont (i32.const 0)))))
          (else (global.set $g_rep_cont (i32.const 0)))))
      (else
        (global.set $g_rptc (i32.const 0))
        (global.set $g_rep_cont (i32.const 0)))))

  ;; Program read without wait-state charging (used only to fetch the
  ;; opcode at the repeat address for the repeatability test; the
  ;; instruction itself was already fetched and charged once).
  (func $pm_rd_nocharge (param $a i32) (result i32)
    (i32.load16_u (call $pm_ptr (local.get $a))))

  ;; RPTB block-end test (manual 4.7): the last loop word has just
  ;; executed (PC is already past it). BRCR > 0: decrement and restart
  ;; at PASR; BRCR == 0: leave the loop, BRAF cleared.
  (func $handle_braf
    (if (i32.and (global.get $g_braf)
                 (i32.eq
                   (i32.and (i32.sub (global.get $g_pc) (i32.const 1))
                            (i32.const 0xFFFF))
                   (global.get $g_paer)))
      (then
        (if (i32.gt_s (global.get $g_brcr) (i32.const 0))
          (then
            (global.set $g_pc (global.get $g_pasr))
            (global.set $g_brcr (i32.sub (global.get $g_brcr) (i32.const 1))))
          (else (global.set $g_braf (i32.const 0)))))))

  ;; ================= cycle delta (DESIGN 4.2/4.3) ====================
  ;; Per-iteration repeat cost from the RPT tables (DESIGN 4.3, with
  ;; the final-repeat rule of deviation V9 for SARAM write-back forms).
  (func $rpt_cost (param $op i32) (param $saram i32) (param $final i32)
        (result i32)
    (local $p i32)
    (if (local.get $saram)
      (then (local.set $p
              (i32.load8_u offset=0x80000 (local.get $op))))
      (else (local.set $p
              (i32.load8_u offset=0x70000 (local.get $op)))))
    ;; Final repeat iteration of a SARAM write-back form (PLU dbmr/#lk
    ;; 0x58-0x5A/0x5C-0x5E, DMOV 0x77): q=1 instead of p=2 (V9).
    (if (result i32)
      (i32.and
        (i32.and (local.get $final) (local.get $saram))
        (i32.or
          (i32.or
            (i32.and (i32.ge_u (local.get $op) (i32.const 0x5800))
                     (i32.le_u (local.get $op) (i32.const 0x5AFF)))
            (i32.and (i32.ge_u (local.get $op) (i32.const 0x5C00))
                     (i32.le_u (local.get $op) (i32.const 0x5EFF))))
          (i32.and (i32.ge_u (local.get $op) (i32.const 0x7700))
                   (i32.le_u (local.get $op) (i32.const 0x77FF)))))
      (then (i32.const 1))
      (else (local.get $p))))

  ;; Taken/not-taken + repeat override, applied by $run after $exec1.
  ;; rep_cont: delta = rpt_cost - cycm[op] (final repeat iff rptc==0
  ;; at this point -- handle_rpt has not run yet for this iteration).
  ;; Conditional BANZ/BCND/CC/RETC: taken -> 4, not-taken -> 2.
  ;; Everything else: 0 (BD/CALLD/BANZD/BCNDD/CCD/RETCD flat 2 and
  ;; B/CALL flat 4 already match their table values).
  (func $cycle_delta (result i32)
    (local $op i32) (local $hi i32) (local $cycm i32)
    (local.set $op (global.get $g_op))
    (local.set $hi (i32.shr_u (local.get $op) (i32.const 8)))
    (local.set $cycm (i32.load8_u offset=0x60000 (local.get $op)))
    (if (result i32) (global.get $g_rep_cont)
      (then
        (i32.sub
          (call $rpt_cost (local.get $op) (global.get $g_ea_saram)
                (i32.eqz (global.get $g_rptc)))
          (local.get $cycm)))
      (else
        (if (result i32)
          (i32.or
            (i32.or
              (i32.eq (local.get $hi) (i32.const 0x7B))
              (i32.and (i32.ge_u (local.get $hi) (i32.const 0xE0))
                       (i32.le_u (local.get $hi) (i32.const 0xE3))))
            (i32.or
              (i32.and (i32.ge_u (local.get $hi) (i32.const 0xE8))
                       (i32.le_u (local.get $hi) (i32.const 0xEB)))
              (i32.and (i32.ge_u (local.get $hi) (i32.const 0xEC))
                       (i32.le_u (local.get $hi) (i32.const 0xEF)))))
          (then
            (i32.sub
              (if (result i32) (global.get $g_taken)
                (then (i32.const 4)) (else (i32.const 2)))
              (local.get $cycm)))
          (else (i32.const 0))))))

  ;; Instruction length in words (DESIGN 3.2): pure function of opcode.
  (func $len_of (param $op i32) (result i32)
    (local $hi i32) (local $lo i32)
    (local.set $hi (i32.shr_u (local.get $op) (i32.const 8)))
    (local.set $lo (i32.and (local.get $op) (i32.const 0xFF)))
    (if (result i32) (i32.eq (local.get $hi) (i32.const 0xBE))
      (then (i32.load8_u offset=0x92100 (local.get $lo)))
      (else
        (if (result i32) (i32.eq (local.get $hi) (i32.const 0xBF))
          (then (i32.load8_u offset=0x92200 (local.get $lo)))
          (else (i32.load8_u offset=0x92000 (local.get $hi)))))))

  ;; ================= instruction execution ===========================
  ;; Forward declarations are unnecessary in WAT (module-level names
  ;; resolve regardless of order); $exec1 is defined after the families
  ;; but $delay_slot (above) already calls it.

  ;; High bytes 0x00-0x0F: LAR, LAMM, SMMR, SUBC, RPT, OUT, LDP, LST.
  (func $exec_hi_00_0f (param $op i32)
    (local $a i32) (local $d i32) (local $hi i32) (local $pfc i32)
    (local $r i32) (local $b i64) (local $res i32) (local $rr i64)
    (local.set $hi (i32.shr_u (local.get $op) (i32.const 8)))
    (if (i32.le_u (local.get $hi) (i32.const 7))
      (then
        ;; LAR dma: AR[hi] = dm[ea]; AR0 sets ar0_dirty (via $ar_set).
        (local.set $a (call $ea))
        (call $ar_set (local.get $hi) (call $dm_rd (local.get $a)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x08))
      (then
        ;; LAMM: ACC = dm[ea & 0x7F].
        (local.set $a (i32.and (call $ea) (i32.const 0x7F)))
        (global.set $g_acc (call $dm_rd (local.get $a)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x09))
      (then
        ;; SMMR: store the MMR at dma to successive data addresses.
        ;; ea() evaluated ONCE, before the loop (Rank 9). Repeat +2.
        (local.set $pfc (call $fetch))
        (local.set $a (i32.and (call $ea) (i32.const 0x7F)))
        (block $done
          (loop $loop
            (br_if $done (i32.le_s (global.get $g_rptc) (i32.const -1)))
            (call $dm_wr (local.get $pfc) (call $dm_rd (local.get $a)))
            (local.set $pfc
              (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xFFFF)))
            (local.set $r (global.get $g_rptc))
            (global.set $g_rptc (i32.sub (global.get $g_rptc) (i32.const 1)))
            (if (i32.gt_s (local.get $r) (i32.const 0))
              (then (call $cycles_add (i64.const 2))))
            (br $loop)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x0A))
      (then
        ;; SUBC: conditional subtract (divide step). Sets C and OV,
        ;; never saturates (audit #24).
        (local.set $a (call $ea))
        (local.set $d (call $dm_rd (local.get $a)))
        (local.set $b (i64.shl (i64.extend_i32_u (local.get $d)) (i64.const 15)))
        (local.set $rr (i64.sub (i64.extend_i32_u (global.get $g_acc)) (local.get $b)))
        (local.set $res (i32.wrap_i64 (local.get $rr)))
        (global.set $g_c
          (i32.eqz (i32.wrap_i64 (i64.shr_u (local.get $rr) (i64.const 32)))))
        (if (i32.and
              (i32.and (i32.xor (global.get $g_acc) (i32.wrap_i64 (local.get $b)))
                       (i32.xor (global.get $g_acc) (local.get $res)))
              (i32.const 0x80000000))
          (then (global.set $g_ov (i32.const 1))))
        (global.set $g_acc
          (if (result i32) (i32.ge_s (local.get $res) (i32.const 0))
            (then (i32.add (i32.shl (local.get $res) (i32.const 1)) (i32.const 1)))
            (else (i32.shl (global.get $g_acc) (i32.const 1)))))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x0B))
      (then
        ;; RPT dma: repeat count from data memory.
        (local.set $a (call $ea))
        (global.set $g_rptc (call $dm_rd (local.get $a)))
        (global.set $g_rpt_start (global.get $g_pc))
        (global.set $g_rpt_end (global.get $g_pc))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x0C))
      (then
        ;; OUT: with RPT the port increments per access (io_rep).
        (local.set $d (call $fetch)) ;; port
        (if (global.get $g_rep_cont)
          (then (global.set $g_io_rep (i32.add (global.get $g_io_rep) (i32.const 1))))
          (else (global.set $g_io_rep (i32.const 0))))
        (local.set $d
          (i32.and (i32.add (local.get $d) (global.get $g_io_rep)) (i32.const 0xFFFF)))
        (local.set $a (call $ea))
        (call $io_write (local.get $d) (call $dm_rd (local.get $a)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x0D))
      (then
        ;; LDP dma: DP = (dm & 0x1FF) << 7.
        (local.set $a (call $ea))
        (global.set $g_dp
          (i32.shl (i32.and (call $dm_rd (local.get $a)) (i32.const 0x1FF))
                   (i32.const 7)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x0E))
      (then
        ;; LST #0: load ST0. ARB saved/restored around ea() (audit #21).
        ;; INTM is NOT loaded.
        (local.set $r (global.get $g_arb))
        (local.set $a (call $ea))
        (global.set $g_arb (local.get $r))
        (local.set $d (call $dm_rd (local.get $a)))
        (global.set $g_arp (i32.shr_u (local.get $d) (i32.const 13)))
        (global.set $g_ov (i32.and (i32.shr_u (local.get $d) (i32.const 12)) (i32.const 1)))
        (global.set $g_ovm (i32.and (i32.shr_u (local.get $d) (i32.const 11)) (i32.const 1)))
        (global.set $g_dp
          (i32.shl (i32.and (local.get $d) (i32.const 0x1FF)) (i32.const 7)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x0F))
      (then
        ;; LST #1: load ST1 (ARB and ARP both come from the word).
        (local.set $a (call $ea))
        (local.set $d (call $dm_rd (local.get $a)))
        (global.set $g_arb (i32.shr_u (local.get $d) (i32.const 13)))
        (global.set $g_arp (i32.shr_u (local.get $d) (i32.const 13)))
        (global.set $g_cnf (i32.and (i32.shr_u (local.get $d) (i32.const 12)) (i32.const 1)))
        (global.set $g_tc (i32.and (i32.shr_u (local.get $d) (i32.const 11)) (i32.const 1)))
        (global.set $g_sxm (i32.and (i32.shr_u (local.get $d) (i32.const 10)) (i32.const 1)))
        (global.set $g_c (i32.and (i32.shr_u (local.get $d) (i32.const 9)) (i32.const 1)))
        (global.set $g_hm (i32.and (i32.shr_u (local.get $d) (i32.const 6)) (i32.const 1)))
        (global.set $g_xf (i32.and (i32.shr_u (local.get $d) (i32.const 4)) (i32.const 1)))
        (global.set $g_pm (i32.and (local.get $d) (i32.const 3)))
        (return))))

  ;; High bytes 0x10-0x3F: LACC / ADD / SUB dma,shift (shift = high nibble).
  (func $exec_hi_10_3f (param $op i32)
    (local $a i32) (local $hi i32)
    (local.set $hi (i32.shr_u (local.get $op) (i32.const 8)))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0x10))
                 (i32.le_u (local.get $hi) (i32.const 0x1F)))
      (then
        (local.set $a (call $ea))
        (global.set $g_acc
          (call $ext (call $dm_rd (local.get $a))
                     (i32.and (local.get $hi) (i32.const 0xF))))
        (return)))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0x20))
                 (i32.le_u (local.get $hi) (i32.const 0x2F)))
      (then
        (local.set $a (call $ea))
        (global.set $g_acc
          (call $do_add (global.get $g_acc)
                (call $ext (call $dm_rd (local.get $a))
                           (i32.and (local.get $hi) (i32.const 0xF)))
                (i32.const 0) (i32.const 0)))
        (return)))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0x30))
                 (i32.le_u (local.get $hi) (i32.const 0x3F)))
      (then
        (local.set $a (call $ea))
        (global.set $g_acc
          (call $do_sub (global.get $g_acc)
                (call $ext (call $dm_rd (local.get $a))
                           (i32.and (local.get $hi) (i32.const 0xF)))
                (i32.const 0) (i32.const 0)))
        (return))))

  ;; High bytes 0x40-0x5F: BIT, multiply/accumulate, DBMR logic ops.
  (func $exec_hi_40_5f (param $op i32)
    (local $a i32) (local $d i32) (local $imm i32) (local $hi i32)
    (local $pfc i32) (local $r i32) (local $ps i32)
    (local.set $hi (i32.shr_u (local.get $op) (i32.const 8)))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0x40))
                 (i32.le_u (local.get $hi) (i32.const 0x4F)))
      (then
        ;; BIT dma,s: TC = bit (15 - shift) of the operand.
        (local.set $a (call $ea))
        (global.set $g_tc
          (i32.and
            (i32.shr_u (call $dm_rd (local.get $a))
                       (i32.sub (i32.const 15) (i32.and (local.get $hi) (i32.const 0xF))))
            (i32.const 1)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x50))
      (then
        ;; MPYA: ACC += PREG (scaled); PREG = TREG0 * dma.
        (local.set $a (call $ea))
        (local.set $d (call $dm_rd (local.get $a)))
        (local.set $ps (call $pscale))
        (global.set $g_acc
          (call $do_add (global.get $g_acc) (local.get $ps) (i32.const 0) (i32.const 0)))
        (global.set $g_preg
          (i32.mul (i32.extend16_s (global.get $g_treg0))
                   (i32.extend16_s (local.get $d))))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x51))
      (then
        ;; MPYS: ACC -= PREG (scaled); PREG = TREG0 * dma.
        (local.set $a (call $ea))
        (local.set $d (call $dm_rd (local.get $a)))
        (local.set $ps (call $pscale))
        (global.set $g_acc
          (call $do_sub (global.get $g_acc) (local.get $ps) (i32.const 0) (i32.const 0)))
        (global.set $g_preg
          (i32.mul (i32.extend16_s (global.get $g_treg0))
                   (i32.extend16_s (local.get $d))))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x52))
      (then
        ;; SQRA: ACC += PREG; TREG0 = dma; PREG = dma * dma.
        (local.set $a (call $ea))
        (local.set $d (call $dm_rd (local.get $a)))
        (local.set $ps (call $pscale))
        (global.set $g_acc
          (call $do_add (global.get $g_acc) (local.get $ps) (i32.const 0) (i32.const 0)))
        (call $set_t0 (local.get $d))
        (global.set $g_preg
          (i32.mul (i32.extend16_s (local.get $d))
                   (i32.extend16_s (local.get $d))))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x53))
      (then
        ;; SQRS: ACC -= PREG; TREG0 = dma; PREG = dma * dma.
        (local.set $a (call $ea))
        (local.set $d (call $dm_rd (local.get $a)))
        (local.set $ps (call $pscale))
        (global.set $g_acc
          (call $do_sub (global.get $g_acc) (local.get $ps) (i32.const 0) (i32.const 0)))
        (call $set_t0 (local.get $d))
        (global.set $g_preg
          (i32.mul (i32.extend16_s (local.get $d))
                   (i32.extend16_s (local.get $d))))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x54))
      (then
        ;; MPY dma: PREG = TREG0 * dma (signed).
        (local.set $a (call $ea))
        (local.set $d (call $dm_rd (local.get $a)))
        (global.set $g_preg
          (i32.mul (i32.extend16_s (global.get $g_treg0))
                   (i32.extend16_s (local.get $d))))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x55))
      (then
        ;; MPYU: PREG = TREG0 * dma (unsigned).
        (local.set $a (call $ea))
        (local.set $d (call $dm_rd (local.get $a)))
        (global.set $g_preg (i32.mul (global.get $g_treg0) (local.get $d)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x56))
      (then (global.set $g_status (i32.const 2)) (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x57))
      (then
        ;; BLDP: data -> program, BMAR as source. BMAR is NOT written
        ;; back (audit #15); the local pfc advances.
        (local.set $pfc (global.get $g_bmar))
        (block $done
          (loop $loop
            (br_if $done (i32.le_s (global.get $g_rptc) (i32.const -1)))
            (local.set $a (call $ea))
            (call $pm_wr (local.get $pfc) (call $dm_rd (local.get $a)))
            (local.set $pfc
              (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xFFFF)))
            (local.set $r (global.get $g_rptc))
            (global.set $g_rptc (i32.sub (global.get $g_rptc) (i32.const 1)))
            (if (i32.gt_s (local.get $r) (i32.const 0))
              (then (call $cycles_add (i64.const 1))))
            (br $loop)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x58))
      (then
        ;; XPL dbmr: dma ^= DBMR; TC = (result == 0).
        (local.set $a (call $ea))
        (local.set $d
          (i32.and (i32.xor (call $dm_rd (local.get $a)) (global.get $g_dbmr))
                   (i32.const 0xFFFF)))
        (global.set $g_tc (i32.eqz (local.get $d)))
        (call $dm_wr (local.get $a) (local.get $d))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x59))
      (then
        ;; OPL dbmr: dma |= DBMR; TC = (result == 0).
        (local.set $a (call $ea))
        (local.set $d
          (i32.and (i32.or (call $dm_rd (local.get $a)) (global.get $g_dbmr))
                   (i32.const 0xFFFF)))
        (global.set $g_tc (i32.eqz (local.get $d)))
        (call $dm_wr (local.get $a) (local.get $d))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x5A))
      (then
        ;; APL dbmr: dma &= DBMR; TC = (result == 0).
        (local.set $a (call $ea))
        (local.set $d
          (i32.and (i32.and (call $dm_rd (local.get $a)) (global.get $g_dbmr))
                   (i32.const 0xFFFF)))
        (global.set $g_tc (i32.eqz (local.get $d)))
        (call $dm_wr (local.get $a) (local.get $d))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x5B))
      (then
        ;; CPL dbmr: TC = (dma == DBMR); no write.
        (local.set $a (call $ea))
        (global.set $g_tc
          (i32.eq (call $dm_rd (local.get $a)) (global.get $g_dbmr)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x5C))
      (then
        ;; XPL #lk: dma ^= imm; TC = (result == 0).
        (local.set $imm (call $fetch))
        (local.set $a (call $ea))
        (local.set $d
          (i32.and (i32.xor (call $dm_rd (local.get $a)) (local.get $imm))
                   (i32.const 0xFFFF)))
        (global.set $g_tc (i32.eqz (local.get $d)))
        (call $dm_wr (local.get $a) (local.get $d))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x5D))
      (then
        ;; OPL #lk.
        (local.set $imm (call $fetch))
        (local.set $a (call $ea))
        (local.set $d
          (i32.and (i32.or (call $dm_rd (local.get $a)) (local.get $imm))
                   (i32.const 0xFFFF)))
        (global.set $g_tc (i32.eqz (local.get $d)))
        (call $dm_wr (local.get $a) (local.get $d))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x5E))
      (then
        ;; APL #lk.
        (local.set $imm (call $fetch))
        (local.set $a (call $ea))
        (local.set $d
          (i32.and (i32.and (call $dm_rd (local.get $a)) (local.get $imm))
                   (i32.const 0xFFFF)))
        (global.set $g_tc (i32.eqz (local.get $d)))
        (call $dm_wr (local.get $a) (local.get $d))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x5F))
      (then
        ;; CPL #lk: TC = (dma == imm); no write.
        (local.set $imm (call $fetch))
        (local.set $a (call $ea))
        (global.set $g_tc
          (i32.eq (call $dm_rd (local.get $a)) (local.get $imm)))
        (return))))

  ;; High bytes 0x60-0x7F: MPY #lk, LACC/ADD/SUB #lk, shifts, TBLR/W,
  ;; branches, DMOV, PSHD/POPD, MAR, RET/BANZ, SPLK.
  ;; High bytes 0x60-0x7F: add/sub variants, loads, logic, branches.
  ;; (C exec_hi_60_7f, verbatim.)
  ;; CORRECTED 2026-11-16 (Gate 1 audit): the first draft mapped this
  ;; family from the wrong table -- 0x60-0x6F held the #lk forms (which
  ;; live in the 0xBE/0xBF sub-decoders; MPY #lk is 0xBEA0 per SPRU056D
  ;; §6.3), 0x70-0x72 held TBLR/TBLW/BLPD (0xA6/0xA7/0xA5 in C),
  ;; 0x73/0x74 held ROL/ROR dma (no such C5x form; ROL/ROR are 0xBE
  ;; accumulator ops), 0x7C held RET and 0x7F held RETD (both are
  ;; RETC/RETCD with the always-true condition -- RET = 0xEF00,
  ;; RETD = 0xFF00 -- and need no separate case), and the branch
  ;; bodies were wrong in detail: B/CALL/BD/CALLD skipped ea();
  ;; BANZ evaluated $cond and decremented AR; DMOV looped internally
  ;; instead of relying on $handle_rpt; BD/CALLD passed the branch
  ;; address to $delay_slot instead of the first slot word;
  ;; ADDT/SUBT used TREG0 and a plain shift instead of
  ;; $ext(dm, TREG1 & 0xF).
  (func $exec_hi_60_7f (param $op i32)
    (local $a i32) (local $d i32) (local $imm i32) (local $hi i32)
    (local $pfc i32) (local $r i32) (local $ps i32) (local $tmp i32)
    (local $take i32)
    (local.set $hi (i32.shr_u (local.get $op) (i32.const 8)))
    (if (i32.eq (local.get $hi) (i32.const 0x60))
      (then
        ;; ADDC: ACC += dma + C.
        (local.set $a (call $ea))
        (global.set $g_acc
          (call $do_add (global.get $g_acc) (call $dm_rd (local.get $a))
                        (global.get $g_c) (i32.const 0)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x61))
      (then
        ;; ADD dma,16: ACC += dma << 16 (16-bit form, s16=1).
        (local.set $a (call $ea))
        (global.set $g_acc
          (call $do_add (global.get $g_acc)
                        (i32.shl (call $dm_rd (local.get $a)) (i32.const 16))
                        (i32.const 0) (i32.const 1)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x62))
      (then
        ;; ADDS: ACC += dma (zero-extended).
        (local.set $a (call $ea))
        (global.set $g_acc
          (call $do_add (global.get $g_acc) (call $dm_rd (local.get $a))
                        (i32.const 0) (i32.const 0)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x63))
      (then
        ;; ADDT: ACC += ext(dm, TREG1 & 0xF).
        (local.set $a (call $ea))
        (global.set $g_acc
          (call $do_add (global.get $g_acc)
                        (call $ext (call $dm_rd (local.get $a))
                                   (i32.and (global.get $g_treg1) (i32.const 0xF)))
                        (i32.const 0) (i32.const 0)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x64))
      (then
        ;; SUBB: ACC -= dma + !C.
        (local.set $a (call $ea))
        (global.set $g_acc
          (call $do_sub (global.get $g_acc) (call $dm_rd (local.get $a))
                        (i32.eqz (global.get $g_c)) (i32.const 0)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x65))
      (then
        ;; SUB dma,16: ACC -= dma << 16 (16-bit form, s16=1).
        (local.set $a (call $ea))
        (global.set $g_acc
          (call $do_sub (global.get $g_acc)
                        (i32.shl (call $dm_rd (local.get $a)) (i32.const 16))
                        (i32.const 0) (i32.const 1)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x66))
      (then
        ;; SUBS: ACC -= dma.
        (local.set $a (call $ea))
        (global.set $g_acc
          (call $do_sub (global.get $g_acc) (call $dm_rd (local.get $a))
                        (i32.const 0) (i32.const 0)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x67))
      (then
        ;; SUBT: ACC -= ext(dm, TREG1 & 0xF).
        (local.set $a (call $ea))
        (global.set $g_acc
          (call $do_sub (global.get $g_acc)
                        (call $ext (call $dm_rd (local.get $a))
                                   (i32.and (global.get $g_treg1) (i32.const 0xF)))
                        (i32.const 0) (i32.const 0)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x68))
      (then
        ;; ZALR: ACC = (dma << 16) | 0x8000 (rounding bit).
        (local.set $a (call $ea))
        (global.set $g_acc
          (i32.or (i32.shl (call $dm_rd (local.get $a)) (i32.const 16))
                  (i32.const 0x8000)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x69))
      (then
        ;; LACL dma: ACC = dm.
        (local.set $a (call $ea))
        (global.set $g_acc (call $dm_rd (local.get $a)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x6A))
      (then
        ;; LACC dma,16: ACC = dma << 16.
        (local.set $a (call $ea))
        (global.set $g_acc
          (i32.shl (call $dm_rd (local.get $a)) (i32.const 16)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x6B))
      (then
        ;; LACT: ACC = ext(dm, TREG1 & 0xF).
        (local.set $a (call $ea))
        (global.set $g_acc
          (call $ext (call $dm_rd (local.get $a))
                     (i32.and (global.get $g_treg1) (i32.const 0xF))))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x6C))
      (then
        ;; XOR dma: ACC ^= dm.
        (local.set $a (call $ea))
        (global.set $g_acc
          (i32.xor (global.get $g_acc) (call $dm_rd (local.get $a))))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x6D))
      (then
        ;; OR dma: ACC |= dm.
        (local.set $a (call $ea))
        (global.set $g_acc
          (i32.or (global.get $g_acc) (call $dm_rd (local.get $a))))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x6E))
      (then
        ;; AND dma: ACC &= dm.
        (local.set $a (call $ea))
        (global.set $g_acc
          (i32.and (global.get $g_acc) (call $dm_rd (local.get $a))))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x6F))
      (then
        ;; BITT: TC = bit (15 - TREG2) of dma. The (~treg2 & 0xF)
        ;; spelling is the original's (orig L~398).
        (local.set $a (call $ea))
        (global.set $g_tc
          (i32.and
            (i32.shr_u (call $dm_rd (local.get $a))
                       (i32.and (i32.xor (global.get $g_treg2) (i32.const -1))
                                (i32.const 0xF)))
            (i32.const 1)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x70))
      (then
        ;; LTA: ACC += PREG; TREG0 = dma.
        (local.set $a (call $ea))
        (local.set $d (call $dm_rd (local.get $a)))
        (local.set $ps (call $pscale))
        (global.set $g_acc
          (call $do_add (global.get $g_acc) (local.get $ps)
                        (i32.const 0) (i32.const 0)))
        (call $set_t0 (local.get $d))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x71))
      (then
        ;; LTP: ACC = PREG (scaled); TREG0 = dma.
        (local.set $a (call $ea))
        (local.set $d (call $dm_rd (local.get $a)))
        (global.set $g_acc (call $pscale))
        (call $set_t0 (local.get $d))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x72))
      (then
        ;; LTD: ACC += PREG; TREG0 = dma; DMOV dma -> dma+1.
        (local.set $a (call $ea))
        (local.set $d (call $dm_rd (local.get $a)))
        (local.set $ps (call $pscale))
        (global.set $g_acc
          (call $do_add (global.get $g_acc) (local.get $ps)
                        (i32.const 0) (i32.const 0)))
        (call $set_t0 (local.get $d))
        (call $dmov_wr (local.get $a) (local.get $d))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x73))
      (then
        ;; LT: TREG0 = dma.
        (local.set $a (call $ea))
        (call $set_t0 (call $dm_rd (local.get $a)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x74))
      (then
        ;; LTS: ACC -= PREG; TREG0 = dma.
        (local.set $a (call $ea))
        (local.set $d (call $dm_rd (local.get $a)))
        (local.set $ps (call $pscale))
        (global.set $g_acc
          (call $do_sub (global.get $g_acc) (local.get $ps)
                        (i32.const 0) (i32.const 0)))
        (call $set_t0 (local.get $d))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x75))
      (then
        ;; LPH: PREG high half = dma.
        (local.set $a (call $ea))
        (global.set $g_preg
          (i32.or (i32.and (global.get $g_preg) (i32.const 0xFFFF))
                  (i32.shl (call $dm_rd (local.get $a)) (i32.const 16))))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x76))
      (then
        ;; PSHD dma: push dm[ea].
        (local.set $a (call $ea))
        (call $stack_push (call $dm_rd (local.get $a)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x77))
      (then
        ;; DMOV dma: dm[ea+1] = dm[ea]. Single execution; repetition
        ;; comes from $handle_rpt (the first draft looped internally,
        ;; which broke the V9 final-repeat rule and repeat timing).
        (local.set $a (call $ea))
        (call $dmov_wr (local.get $a) (call $dm_rd (local.get $a)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x78))
      (then
        ;; ADRK: AR[ARP] += k8 (low byte, unsigned).
        (call $upd_ar (global.get $g_arp)
                      (i32.and (local.get $op) (i32.const 0xFF)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x79))
      (then
        ;; B: ea() runs for its addressing side effects, then PC = imm.
        (local.set $imm (call $fetch))
        (drop (call $ea))
        (global.set $g_pc (local.get $imm))
        (global.set $g_taken (i32.const 1))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x7A))
      (then
        ;; CALL: push return, PC = imm. (ea() first, as in C.)
        (local.set $imm (call $fetch))
        (drop (call $ea))
        (call $stack_push (global.get $g_pc))
        (global.set $g_pc (local.get $imm))
        (global.set $g_taken (i32.const 1))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x7B))
      (then
        ;; BANZ: branch if AR[ARP] != 0. The take decision is made
        ;; before ea() (audit #14), so an ARP-switching addressing
        ;; mode does not change which AR was tested. No AR decrement.
        (local.set $imm (call $fetch))
        (local.set $take
          (i32.ne (call $ar_get (global.get $g_arp)) (i32.const 0)))
        (drop (call $ea))
        (global.set $g_taken (local.get $take))
        (if (local.get $take)
          (then (global.set $g_pc (local.get $imm))))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x7C))
      (then
        ;; SBRK: AR[ARP] -= k8.
        (call $upd_ar (global.get $g_arp)
                      (i32.sub (i32.const 0)
                               (i32.and (local.get $op) (i32.const 0xFF))))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x7D))
      (then
        ;; BD: delayed branch; two slot words run before the jump.
        (local.set $imm (call $fetch))
        (drop (call $ea))
        (call $delay_slot (global.get $g_pc))
        (global.set $g_pc (local.get $imm))
        (global.set $g_taken (i32.const 1))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x7E))
      (then
        ;; CALLD: delayed call; return address is pc+2 (past the two
        ;; slot words). DESIGN V5: capture ret before the slot, run
        ;; the slot, then push ret (C pushes before the slot).
        ;; The captured pc is the slot start, so the return is
        ;; $tmp+2 -- pushing $tmp itself returns into the slot.
        (local.set $imm (call $fetch))
        (drop (call $ea))
        (local.set $tmp (global.get $g_pc))
        (call $delay_slot (global.get $g_pc))
        (call $stack_push
          (i32.and (i32.add (local.get $tmp) (i32.const 2)) (i32.const 0xFFFF)))
        (global.set $g_pc (local.get $imm))
        (global.set $g_taken (i32.const 1))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x7F))
      (then
        ;; BANZD: delayed BANZ; take decision before ea(), as in BANZ.
        ;; The slot always runs, whether the branch is taken or not.
        (local.set $imm (call $fetch))
        (local.set $take
          (i32.ne (call $ar_get (global.get $g_arp)) (i32.const 0)))
        (drop (call $ea))
        (global.set $g_taken (local.get $take))
        (call $delay_slot (global.get $g_pc))
        (if (local.get $take)
          (then (global.set $g_pc (local.get $imm))))
        (return)))
  )

  ;; High bytes 0x80-0x9F: SACL, SAR, POPD, MAR, SST, LMMR, BLDD, CMPR,
  ;; LACC B, SACH.
  ;; exec_hi_80_9f (C exec_hi_80_9f, verbatim mapping).
  ;; CORRECTED 2026-11-16 (Gate 1 found it): the first draft of this
  ;; function had the blocks scrambled -- hi 0x80-0x87 implemented as
  ;; SACL, hi 0x88-0x8F as SAR (shadowing the real LMMR/POPD/MAR/SPL/
  ;; SPH/SST cases), SACL/SACH used the manual's shift-code table
  ;; (0,1,2,4,8,16,-1,-4) instead of C's shift = (op>>8)&7, and it
  ;; contained SSTB blocks that do not exist in C. Consequence: 0x8821
  ;; is SAMM (ACC low -> page-0 DM), so the DXR write at 0x8096 was
  ;; missed, XRDY stayed 1, and the 0x8097/0x8098 poll loop exited.
  ;; C mapping (c5x_core.c):
  ;;   0x80-0x87 SAR: AR[(op>>8)&7] read BEFORE ea(), dm[ea] = AR.
  ;;   0x88 SAMM: dm[ea()&0x7F] = ACC low half.
  ;;   0x89 LMMR: fetch pfc, a = ea()&0x7F, loop while rptc>-1:
  ;;        dm[a] = dm_rd(pfc++); if (rptc-->0) cycles += 2.
  ;;        (rptc is normalised to 0 after every instruction, so a bare
  ;;        LMMR always performs exactly one write.)
  ;;   0x8A POPD: dm[ea] = stack_pop().
  ;;   0x8B MAR: ea() ONLY when op bit 7 set (indirect); else no-op.
  ;;   0x8C SPL: dm[ea] = pscale() low half.
  ;;   0x8D SPH: dm[ea] = pscale() >> 16.
  ;;   0x8E SST #0: dm[ea_p0()] = st0_get().
  ;;   0x8F SST #1: dm[ea_p0()] = st1_get().
  ;;   0x90-0x97 SACL: dm[ea] = (ACC << (hi&7)) & 0xFFFF.
  ;;   0x98-0x9F SACH: dm[ea] = ((ACC << (hi&7)) >> 16) & 0xFFFF.
  ;;   SACL/SACH shift is C's (op>>8)&7 (0..7); DESIGN does not
  ;;   adjudicate the shift encoding, so C (the oracle) wins.
  (func $exec_hi_80_9f (param $op i32)
    (local $a i32) (local $d i32) (local $hi i32) (local $pfc i32)
    (local $r i32) (local $ar i32) (local $v i32) (local $s i32)
    (local.set $hi (i32.shr_u (local.get $op) (i32.const 8)))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0x80))
                 (i32.le_u (local.get $hi) (i32.const 0x87)))
      (then
        ;; SAR dma: AR[hi&7] read BEFORE ea() (audit #7).
        (local.set $ar (i32.and (local.get $hi) (i32.const 7)))
        (local.set $v (call $ar_get (local.get $ar)))
        (local.set $a (call $ea))
        (call $dm_wr (local.get $a) (local.get $v))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x88))
      (then
        ;; SAMM dma: dm[ea() & 0x7F] = ACC low half.
        (local.set $a (i32.and (call $ea) (i32.const 0x7F)))
        (call $dm_wr (local.get $a)
          (i32.and (global.get $g_acc) (i32.const 0xFFFF)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x89))
      (then
        ;; LMMR: fetch pfc first, then ea()&0x7F (Rank 9: ea once).
        ;; Loop while rptc > -1; +2 cycles when rptc > 0 pre-decrement.
        (local.set $pfc (call $fetch))
        (local.set $a (i32.and (call $ea) (i32.const 0x7F)))
        (block $done
          (loop $loop
            (br_if $done (i32.le_s (global.get $g_rptc) (i32.const -1)))
            (call $dm_wr (local.get $a) (call $dm_rd (local.get $pfc)))
            (local.set $pfc
              (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xFFFF)))
            (local.set $r (global.get $g_rptc))
            (global.set $g_rptc (i32.sub (global.get $g_rptc) (i32.const 1)))
            (if (i32.gt_s (local.get $r) (i32.const 0))
              (then (call $cycles_add (i64.const 2))))
            (br $loop)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x8A))
      (then
        ;; POPD dma: dm[ea] = stack_pop().
        (local.set $a (call $ea))
        (call $dm_wr (local.get $a) (call $stack_pop))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x8B))
      (then
        ;; MAR dma: addressing-mode side effect ONLY when indirect.
        (if (i32.and (local.get $op) (i32.const 0x80))
          (then (drop (call $ea))))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x8C))
      (then
        ;; SPL dma: dm[ea] = pscale() low half.
        (local.set $a (call $ea))
        (call $dm_wr (local.get $a)
          (i32.and (call $pscale) (i32.const 0xFFFF)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x8D))
      (then
        ;; SPH dma: dm[ea] = pscale() >> 16.
        (local.set $a (call $ea))
        (call $dm_wr (local.get $a)
          (i32.and (i32.shr_u (call $pscale) (i32.const 16)) (i32.const 0xFFFF)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x8E))
      (then
        ;; SST #0: dm[ea_p0()] = ST0.
        (local.set $a (call $ea_p0))
        (call $dm_wr (local.get $a) (call $st0_get))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0x8F))
      (then
        ;; SST #1: dm[ea_p0()] = ST1.
        (local.set $a (call $ea_p0))
        (call $dm_wr (local.get $a) (call $st1_get))
        (return)))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0x90))
                 (i32.le_u (local.get $hi) (i32.const 0x97)))
      (then
        ;; SACL dma: dm[ea] = (ACC << (hi&7)) & 0xFFFF (C shift).
        (local.set $s (i32.and (local.get $hi) (i32.const 7)))
        (local.set $a (call $ea))
        (call $dm_wr (local.get $a)
          (i32.and (i32.shl (global.get $g_acc) (local.get $s))
                   (i32.const 0xFFFF)))
        (return)))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0x98))
                 (i32.le_u (local.get $hi) (i32.const 0x9F)))
      (then
        ;; SACH dma: dm[ea] = ((ACC << (hi&7)) >> 16) & 0xFFFF (C shift).
        (local.set $s (i32.and (local.get $hi) (i32.const 7)))
        (local.set $a (call $ea))
        (call $dm_wr (local.get $a)
          (i32.and (i32.shr_s (i32.shl (global.get $g_acc) (local.get $s))
                              (i32.const 16))
                   (i32.const 0xFFFF)))
        (return)))
  )

  ;; High bytes 0xA0-0xAF: NORM, CMPR, BLDD/BLPD, LACCB, MAC family,
  ;; SPLK, TBLW.
  ;; High bytes 0xA0-0xAF: NORM, MAC/MACD, BLPD, TBLR/TBLW, BLDD,
  ;; MADS/MADD, SPLK, IN. (C exec_hi_a0_af, verbatim.)
  ;; CORRECTED 2026-11-16 (Gate 1 audit): the first draft mapped this
  ;; family from the wrong table -- 0xA2/0xA3 held BLDD/BLPD (MAC/MACD
  ;; in C), 0xA4/0xA6/0xA7 held LACC/LACCB/LACB (BLPD bmar/TBLR/TBLW
  ;; in C), 0xA8/0xA9 held MAC/MACD (BLDD in C), 0xAA-0xAD held
  ;; MADS/MADDS/MADD/MADDS (MADS/MADD/BLDD bmar/BLDD dma,bmar in C),
  ;; 0xA1 held CMPR (BADOP in C; CMPR is 0xBF44-0xBF47), 0xA0 held a
  ;; wrong NORM (shift-by-1-or-16; C shifts by 1 iff ACC bits 31/30
  ;; agree, running ea() only on the shifting path), 0xA5 BLPD
  ;; evaluated ea() once and never advanced pfc (C evaluates ea()
  ;; inside the loop and pfc++ per iteration -- the missing advance
  ;; left dm[0x61-0x6A] zero in the smoke), and 0xAF held TBLW
  ;; (IN in C).
  ;; Loop forms (MAC/MACD/MADS/MADD do-while; BLPD/TBLR/TBLW/BLDD
  ;; while) consume rptc inside their own loops and self-charge +1
  ;; per repeat iteration via $cycles_add (the first iteration costs
  ;; the table value); they never rewind via $handle_rpt.
  (func $exec_hi_a0_af (param $op i32)
    (local $a i32) (local $d i32) (local $imm i32) (local $hi i32)
    (local $r i32) (local $ps i32) (local $pfc i32) (local $t i32)
    (local.set $hi (i32.shr_u (local.get $op) (i32.const 8)))
    (if (i32.eq (local.get $hi) (i32.const 0xA0))
      (then
        ;; NORM: shift ACC left until bits 31/30 differ (or ACC == 0).
        ;; Audit #23: the AR is modified only when the ACC is shifted,
        ;; so ea() runs only on the shifting path.
        (local.set $t
          (i32.and
            (i32.xor (i32.shr_u (global.get $g_acc) (i32.const 31))
                     (i32.shr_u (global.get $g_acc) (i32.const 30)))
            (i32.const 1)))
        (if (i32.eqz (global.get $g_acc))
          (then (local.set $t (i32.const 1))))
        (if (i32.eqz (local.get $t))
          (then (drop (call $ea))))
        (if (local.get $t)
          (then (global.set $g_tc (i32.const 1)))
          (else
            (global.set $g_tc (i32.const 0))
            (global.set $g_acc (i32.shl (global.get $g_acc) (i32.const 1)))))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xA1))
      (then (global.set $g_status (i32.const 2)) (return))) ;; BADOP
    (if (i32.or (i32.eq (local.get $hi) (i32.const 0xA2))
                (i32.eq (local.get $hi) (i32.const 0xA3)))
      (then
        ;; MAC / MACD: ACC += PREG; TREG0 = dma; PREG = dma * pma.
        ;; MACD additionally DMOVs dma -> dma+1. The do-while runs
        ;; at least once even with rptc == -1.
        (local.set $pfc (call $fetch))
        (block $done
          (loop $loop
            (local.set $a (call $ea))
            (local.set $d (call $dm_rd (local.get $a)))
            (local.set $ps (call $pscale))
            (global.set $g_acc
              (call $do_add (global.get $g_acc) (local.get $ps)
                            (i32.const 0) (i32.const 0)))
            (call $set_t0 (local.get $d))
            (global.set $g_preg
              (i32.mul (i32.extend16_s (local.get $d))
                       (i32.extend16_s (call $pm_rd (local.get $pfc)))))
            (local.set $pfc
              (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xFFFF)))
            (if (i32.eq (local.get $hi) (i32.const 0xA3))
              (then (call $dmov_wr (local.get $a) (local.get $d))))
            (if (i32.gt_s (global.get $g_rptc) (i32.const -1))
              (then
                (local.set $r (global.get $g_rptc))
                (global.set $g_rptc (i32.sub (global.get $g_rptc) (i32.const 1)))
                (if (i32.gt_s (local.get $r) (i32.const 0))
                  (then (call $cycles_add (i64.const 1))))))
            (br_if $done (i32.le_s (global.get $g_rptc) (i32.const -1)))
            (br $loop)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xA4))
      (then
        ;; BLPD bmar,dma: program (BMAR) -> data. Audit #15: BMAR is
        ;; not written back.
        (local.set $pfc (global.get $g_bmar))
        (block $done
          (loop $loop
            (br_if $done (i32.le_s (global.get $g_rptc) (i32.const -1)))
            (local.set $a (call $ea))
            (call $dm_wr (local.get $a) (call $pm_rd (local.get $pfc)))
            (local.set $pfc
              (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xFFFF)))
            (local.set $r (global.get $g_rptc))
            (global.set $g_rptc (i32.sub (global.get $g_rptc) (i32.const 1)))
            (if (i32.gt_s (local.get $r) (i32.const 0))
              (then (call $cycles_add (i64.const 1))))
            (br $loop)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xA5))
      (then
        ;; BLPD #pma,dma. ea() inside the loop; pfc advances.
        (local.set $pfc (call $fetch))
        (block $done
          (loop $loop
            (br_if $done (i32.le_s (global.get $g_rptc) (i32.const -1)))
            (local.set $a (call $ea))
            (call $dm_wr (local.get $a) (call $pm_rd (local.get $pfc)))
            (local.set $pfc
              (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xFFFF)))
            (local.set $r (global.get $g_rptc))
            (global.set $g_rptc (i32.sub (global.get $g_rptc) (i32.const 1)))
            (if (i32.gt_s (local.get $r) (i32.const 0))
              (then (call $cycles_add (i64.const 1))))
            (br $loop)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xA6))
      (then
        ;; TBLR: program (ACC) -> data. ACC is unchanged (PFC is
        ;; internal).
        (local.set $pfc (i32.and (global.get $g_acc) (i32.const 0xFFFF)))
        (block $done
          (loop $loop
            (br_if $done (i32.le_s (global.get $g_rptc) (i32.const -1)))
            (local.set $a (call $ea))
            (call $dm_wr (local.get $a) (call $pm_rd (local.get $pfc)))
            (local.set $pfc
              (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xFFFF)))
            (local.set $r (global.get $g_rptc))
            (global.set $g_rptc (i32.sub (global.get $g_rptc) (i32.const 1)))
            (if (i32.gt_s (local.get $r) (i32.const 0))
              (then (call $cycles_add (i64.const 1))))
            (br $loop)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xA7))
      (then
        ;; TBLW: data -> program (ACC). ACC is unchanged.
        (local.set $pfc (i32.and (global.get $g_acc) (i32.const 0xFFFF)))
        (block $done
          (loop $loop
            (br_if $done (i32.le_s (global.get $g_rptc) (i32.const -1)))
            (local.set $a (call $ea))
            (call $pm_wr (local.get $pfc) (call $dm_rd (local.get $a)))
            (local.set $pfc
              (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xFFFF)))
            (local.set $r (global.get $g_rptc))
            (global.set $g_rptc (i32.sub (global.get $g_rptc) (i32.const 1)))
            (if (i32.gt_s (local.get $r) (i32.const 0))
              (then (call $cycles_add (i64.const 1))))
            (br $loop)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xA8))
      (then
        ;; BLDD #lk,dma: data -> data.
        (local.set $pfc (call $fetch))
        (block $done
          (loop $loop
            (br_if $done (i32.le_s (global.get $g_rptc) (i32.const -1)))
            (local.set $a (call $ea))
            (call $dm_wr (local.get $a) (call $dm_rd (local.get $pfc)))
            (local.set $pfc
              (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xFFFF)))
            (local.set $r (global.get $g_rptc))
            (global.set $g_rptc (i32.sub (global.get $g_rptc) (i32.const 1)))
            (if (i32.gt_s (local.get $r) (i32.const 0))
              (then (call $cycles_add (i64.const 1))))
            (br $loop)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xA9))
      (then
        ;; BLDD dma,#lk: data -> data (reversed direction).
        (local.set $pfc (call $fetch))
        (block $done
          (loop $loop
            (br_if $done (i32.le_s (global.get $g_rptc) (i32.const -1)))
            (local.set $a (call $ea))
            (call $dm_wr (local.get $pfc) (call $dm_rd (local.get $a)))
            (local.set $pfc
              (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xFFFF)))
            (local.set $r (global.get $g_rptc))
            (global.set $g_rptc (i32.sub (global.get $g_rptc) (i32.const 1)))
            (if (i32.gt_s (local.get $r) (i32.const 0))
              (then (call $cycles_add (i64.const 1))))
            (br $loop)))
        (return)))
    (if (i32.or (i32.eq (local.get $hi) (i32.const 0xAA))
                (i32.eq (local.get $hi) (i32.const 0xAB)))
      (then
        ;; MADS / MADD: like MAC but the program address comes from
        ;; BMAR, and TREG0 is written directly -- audit N-1: no TRM
        ;; mirror (set_t0 is NOT used). MADD additionally DMOVs.
        ;; Audit #15: BMAR is not written back.
        (local.set $pfc (global.get $g_bmar))
        (block $done
          (loop $loop
            (local.set $a (call $ea))
            (local.set $d (call $dm_rd (local.get $a)))
            (local.set $ps (call $pscale))
            (global.set $g_acc
              (call $do_add (global.get $g_acc) (local.get $ps)
                            (i32.const 0) (i32.const 0)))
            (global.set $g_treg0 (local.get $d))
            (global.set $g_preg
              (i32.mul (i32.extend16_s (local.get $d))
                       (i32.extend16_s (call $pm_rd (local.get $pfc)))))
            (local.set $pfc
              (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xFFFF)))
            (if (i32.eq (local.get $hi) (i32.const 0xAB))
              (then (call $dmov_wr (local.get $a) (local.get $d))))
            (if (i32.gt_s (global.get $g_rptc) (i32.const -1))
              (then
                (local.set $r (global.get $g_rptc))
                (global.set $g_rptc (i32.sub (global.get $g_rptc) (i32.const 1)))
                (if (i32.gt_s (local.get $r) (i32.const 0))
                  (then (call $cycles_add (i64.const 1))))))
            (br_if $done (i32.le_s (global.get $g_rptc) (i32.const -1)))
            (br $loop)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xAC))
      (then
        ;; BLDD bmar,dma. Audit #15: BMAR is not written back.
        (local.set $pfc (global.get $g_bmar))
        (block $done
          (loop $loop
            (br_if $done (i32.le_s (global.get $g_rptc) (i32.const -1)))
            (local.set $a (call $ea))
            (call $dm_wr (local.get $a) (call $dm_rd (local.get $pfc)))
            (local.set $pfc
              (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xFFFF)))
            (local.set $r (global.get $g_rptc))
            (global.set $g_rptc (i32.sub (global.get $g_rptc) (i32.const 1)))
            (if (i32.gt_s (local.get $r) (i32.const 0))
              (then (call $cycles_add (i64.const 1))))
            (br $loop)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xAD))
      (then
        ;; BLDD dma,bmar. Audit #15: BMAR is not written back.
        (local.set $pfc (global.get $g_bmar))
        (block $done
          (loop $loop
            (br_if $done (i32.le_s (global.get $g_rptc) (i32.const -1)))
            (local.set $a (call $ea))
            (call $dm_wr (local.get $pfc) (call $dm_rd (local.get $a)))
            (local.set $pfc
              (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xFFFF)))
            (local.set $r (global.get $g_rptc))
            (global.set $g_rptc (i32.sub (global.get $g_rptc) (i32.const 1)))
            (if (i32.gt_s (local.get $r) (i32.const 0))
              (then (call $cycles_add (i64.const 1))))
            (br $loop)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xAE))
      (then
        ;; SPLK: store immediate to data memory. NOTE the order: ea()
        ;; runs BEFORE the immediate is fetched here (orig L~465),
        ;; unlike the 0x5C..0x5F logic-immediate forms.
        (local.set $a (call $ea))
        (local.set $imm (call $fetch))
        (call $dm_wr (local.get $a) (local.get $imm))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xAF))
      (then
        ;; IN: with RPT the port address increments per access
        ;; (manual 6.3 IN/OUT), mirroring OUT (0x0C).
        (local.set $d (call $fetch))
        (if (global.get $g_rep_cont)
          (then (global.set $g_io_rep (i32.add (global.get $g_io_rep) (i32.const 1))))
          (else (global.set $g_io_rep (i32.const 0))))
        (local.set $d
          (i32.and (i32.add (local.get $d) (global.get $g_io_rep)) (i32.const 0xFFFF)))
        (local.set $a (call $ea))
        (call $dm_wr (local.get $a) (call $io_read (local.get $d)))
        (return)))
  )

  ;; High bytes 0xB0-0xBF: LAR #k8, ADDK/LACK/SUBK, RPT #k8, LDP #k9,
  ;; 0xBE / 0xBF sub-decoders.
  (func $exec_hi_b0_bf (param $op i32)
    (local $hi i32)
    (local.set $hi (i32.shr_u (local.get $op) (i32.const 8)))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0xB0))
                 (i32.le_u (local.get $hi) (i32.const 0xB7)))
      (then
        ;; LAR #k8: AR[(op>>8)&7] = low byte.
        (call $ar_set (i32.and (local.get $hi) (i32.const 7))
                      (i32.and (local.get $op) (i32.const 0xFF)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xB8))
      (then
        ;; ADDK: ACC += k8.
        (global.set $g_acc
          (call $do_add (global.get $g_acc)
                        (i32.and (local.get $op) (i32.const 0xFF))
                        (i32.const 0) (i32.const 0)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xB9))
      (then
        ;; LACK: ACC = k8 (zero-extended).
        (global.set $g_acc (i32.and (local.get $op) (i32.const 0xFF)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xBA))
      (then
        ;; SUBK: ACC -= k8.
        (global.set $g_acc
          (call $do_sub (global.get $g_acc)
                        (i32.and (local.get $op) (i32.const 0xFF))
                        (i32.const 0) (i32.const 0)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xBB))
      (then
        ;; RPT #k8: the next instruction (at pc) is the repeated one.
        (global.set $g_rptc (i32.and (local.get $op) (i32.const 0xFF)))
        (global.set $g_rpt_start (global.get $g_pc))
        (global.set $g_rpt_end (global.get $g_pc))
        (return)))
    (if (i32.or (i32.eq (local.get $hi) (i32.const 0xBC))
                (i32.eq (local.get $hi) (i32.const 0xBD)))
      (then
        ;; LDP #k9: DP = low 9 bits << 7.
        (global.set $g_dp
          (i32.shl (i32.and (local.get $op) (i32.const 0x1FF)) (i32.const 7)))
        (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xBE))
      (then (call $exec_be) (return)))
    (if (i32.eq (local.get $hi) (i32.const 0xBF))
      (then (call $exec_bf) (return))))

  ;; 0xBE sub-decoder, part 1: accumulator ops (low byte 0x00..0x1F).
  ;; Unlisted low bytes in this range are BADOP.
  (func $exec_be_acc
    (local $lo i32) (local $t i32) (local $a i32) (local $b i32) (local $cc i32)
    (local $r i64)
    (local.set $lo (i32.and (global.get $g_op) (i32.const 0xFF)))
    (if (i32.eq (local.get $lo) (i32.const 0x00))
      (then
        ;; ABS: |ACC|, saturating at 0x80000000 under OVM.
        (if (i32.eq (global.get $g_acc) (i32.const 0x80000000))
          (then
            (global.set $g_ov (i32.const 1))
            (global.set $g_c (i32.const 0))
            (global.set $g_acc
              (if (result i32) (global.get $g_ovm)
                (then (i32.const 0x7FFFFFFF))
                (else (i32.const 0x80000000)))))
          (else
            (if (i32.lt_s (global.get $g_acc) (i32.const 0))
              (then (global.set $g_acc
                      (i32.sub (i32.const 0) (global.get $g_acc)))))
            (global.set $g_c (i32.const 0))))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x01))
      (then (global.set $g_acc (i32.xor (global.get $g_acc) (i32.const -1))) (return))) ;; CMPL
    (if (i32.eq (local.get $lo) (i32.const 0x02))
      (then
        ;; NEG: -ACC, saturating at 0x80000000 under OVM; C = (result == 0).
        (if (i32.eq (global.get $g_acc) (i32.const 0x80000000))
          (then
            (global.set $g_ov (i32.const 1))
            (global.set $g_c (i32.const 0))
            (global.set $g_acc
              (if (result i32) (global.get $g_ovm)
                (then (i32.const 0x7FFFFFFF))
                (else (i32.const 0x80000000)))))
          (else
            (global.set $g_acc (i32.sub (i32.const 0) (global.get $g_acc)))
            (global.set $g_c (i32.eqz (global.get $g_acc)))))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x03))
      (then (global.set $g_acc (call $pscale)) (return))) ;; ACC = PREG (scaled)
    (if (i32.eq (local.get $lo) (i32.const 0x04))
      (then
        (global.set $g_acc
          (call $do_add (global.get $g_acc) (call $pscale) (i32.const 0) (i32.const 0)))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x05))
      (then
        (global.set $g_acc
          (call $do_sub (global.get $g_acc) (call $pscale) (i32.const 0) (i32.const 0)))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x09))
      (then
        ;; ROL: C = ACC bit 31; ACC <<= 1.
        (global.set $g_c (i32.shr_u (global.get $g_acc) (i32.const 31)))
        (global.set $g_acc (i32.shl (global.get $g_acc) (i32.const 1)))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x0A))
      (then
        ;; ROR: C = ACC bit 0; ACC >>= 1 (sign per SXM).
        (global.set $g_c (i32.and (global.get $g_acc) (i32.const 1)))
        (global.set $g_acc
          (if (result i32) (global.get $g_sxm)
            (then (i32.shr_s (global.get $g_acc) (i32.const 1)))
            (else (i32.shr_u (global.get $g_acc) (i32.const 1)))))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x0C))
      (then
        ;; ROLC: rotate left through C.
        (local.set $t (global.get $g_c))
        (global.set $g_c (i32.shr_u (global.get $g_acc) (i32.const 31)))
        (global.set $g_acc
          (i32.or (i32.shl (global.get $g_acc) (i32.const 1)) (local.get $t)))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x0D))
      (then
        ;; RORC: rotate right through C.
        (local.set $t (global.get $g_c))
        (global.set $g_c (i32.and (global.get $g_acc) (i32.const 1)))
        (global.set $g_acc
          (i32.or (i32.shr_u (global.get $g_acc) (i32.const 1))
                  (i32.shl (local.get $t) (i32.const 31))))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x10))
      (then
        (global.set $g_acc
          (call $do_add (global.get $g_acc) (global.get $g_accb)
                        (i32.const 0) (i32.const 0)))
        (return))) ;; ADDB
    (if (i32.eq (local.get $lo) (i32.const 0x11))
      (then
        (global.set $g_acc
          (call $do_add (global.get $g_acc) (global.get $g_accb)
                        (global.get $g_c) (i32.const 0)))
        (return))) ;; ADDC (ACCB)
    (if (i32.eq (local.get $lo) (i32.const 0x12))
      (then (global.set $g_acc (i32.and (global.get $g_acc) (global.get $g_accb))) (return))) ;; ANDB
    (if (i32.eq (local.get $lo) (i32.const 0x13))
      (then (global.set $g_acc (i32.or (global.get $g_acc) (global.get $g_accb))) (return))) ;; ORB
    (if (i32.eq (local.get $lo) (i32.const 0x14))
      (then
        ;; ROLB: 64-bit rotate left through C.
        (local.set $a (global.get $g_acc))
        (local.set $b (global.get $g_accb))
        (local.set $cc (global.get $g_c))
        (global.set $g_acc
          (i32.or (i32.shl (local.get $a) (i32.const 1))
                  (i32.shr_u (local.get $b) (i32.const 31))))
        (global.set $g_accb
          (i32.or (i32.shl (local.get $b) (i32.const 1)) (local.get $cc)))
        (global.set $g_c (i32.shr_u (local.get $a) (i32.const 31)))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x15))
      (then
        ;; RORB: 64-bit rotate right through C.
        (local.set $a (global.get $g_acc))
        (local.set $b (global.get $g_accb))
        (local.set $cc (global.get $g_c))
        (global.set $g_accb
          (i32.or (i32.shr_u (local.get $b) (i32.const 1))
                  (i32.shl (local.get $a) (i32.const 31))))
        (global.set $g_acc
          (i32.or (i32.shr_u (local.get $a) (i32.const 1))
                  (i32.shl (local.get $cc) (i32.const 31))))
        (global.set $g_c (i32.and (local.get $b) (i32.const 1)))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x16))
      (then
        ;; SFLB: 64-bit shift left (ACCB bit 31 feeds ACC).
        (local.set $a (global.get $g_acc))
        (local.set $b (global.get $g_accb))
        (global.set $g_acc
          (i32.or (i32.shl (local.get $a) (i32.const 1))
                  (i32.shr_u (local.get $b) (i32.const 31))))
        (global.set $g_accb (i32.shl (local.get $b) (i32.const 1)))
        (global.set $g_c (i32.shr_u (local.get $a) (i32.const 31)))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x17))
      (then
        ;; SFRB: 64-bit shift right (ACC bit 31 feeds ACCB).
        (local.set $a (global.get $g_acc))
        (local.set $b (global.get $g_accb))
        (global.set $g_accb
          (i32.or (i32.shr_u (local.get $b) (i32.const 1))
                  (i32.shl (local.get $a) (i32.const 31))))
        (global.set $g_acc
          (if (result i32) (global.get $g_sxm)
            (then (i32.shr_s (local.get $a) (i32.const 1)))
            (else (i32.shr_u (local.get $a) (i32.const 1)))))
        (global.set $g_c (i32.and (local.get $b) (i32.const 1)))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x18))
      (then
        (global.set $g_acc
          (call $do_sub (global.get $g_acc) (global.get $g_accb)
                        (i32.const 0) (i32.const 0)))
        (return))) ;; SUBB
    (if (i32.eq (local.get $lo) (i32.const 0x19))
      (then
        ;; SBBB: ACC -= ACCB + !C. Affects C only: no OV, no saturation.
        (local.set $r
          (i64.sub (i64.sub (i64.extend_i32_u (global.get $g_acc))
                            (i64.extend_i32_u (global.get $g_accb)))
                   (i64.extend_i32_u (i32.eqz (global.get $g_c)))))
        (global.set $g_c
          (i32.eqz (i32.wrap_i64 (i64.shr_u (local.get $r) (i64.const 32)))))
        (global.set $g_acc (i32.wrap_i64 (local.get $r)))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x1A))
      (then (global.set $g_acc (i32.xor (global.get $g_acc) (global.get $g_accb))) (return))) ;; XORB
    (if (i32.eq (local.get $lo) (i32.const 0x1B))
      (then
        ;; MAX: larger of ACC/ACCB ends in ACCB, C = (ACC >= ACCB).
        (if (i32.ge_s (global.get $g_acc) (global.get $g_accb))
          (then
            (global.set $g_accb (global.get $g_acc))
            (global.set $g_c (i32.const 1)))
          (else
            (global.set $g_acc (global.get $g_accb))
            (global.set $g_c (i32.const 0))))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x1C))
      (then
        ;; MIN: smaller of ACC/ACCB ends in ACC, C = (ACC < ACCB).
        (if (i32.ge_s (global.get $g_acc) (global.get $g_accb))
          (then
            (global.set $g_acc (global.get $g_accb))
            (global.set $g_c (i32.const 0)))
          (else
            (global.set $g_accb (global.get $g_acc))
            (global.set $g_c (i32.const 1))))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x1D))
      (then
        ;; SWAP: ACC <-> ACCB.
        (local.set $t (global.get $g_acc))
        (global.set $g_acc (global.get $g_accb))
        (global.set $g_accb (local.get $t))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x1E))
      (then (global.set $g_accb (global.get $g_acc)) (return))) ;; SACB
    (if (i32.eq (local.get $lo) (i32.const 0x1F))
      (then (global.set $g_acc (global.get $g_accb)) (return))) ;; LACB
    (global.set $g_status (i32.const 2)))

  ;; 0xBE sub-decoder, part 2: control, status, and immediate ops
  ;; (low byte 0x20..0xFF), including the INTR default arm.
  (func $exec_be_ctrl
    (local $lo i32) (local $imm i32) (local $p i32) (local $v i32) (local $i i32)
    (local.set $lo (i32.and (global.get $g_op) (i32.const 0xFF)))
    (if (i32.eq (local.get $lo) (i32.const 0x20))
      (then (global.set $g_pc (i32.and (global.get $g_acc) (i32.const 0xFFFF))) (return))) ;; BACC
    (if (i32.eq (local.get $lo) (i32.const 0x21))
      (then
        ;; BACCD: delayed branch to ACC.
        (local.set $p (i32.and (global.get $g_acc) (i32.const 0xFFFF)))
        (call $delay_slot (global.get $g_pc))
        (global.set $g_pc (local.get $p))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x22))
      (then (global.set $g_idle (i32.const 1)) (return))) ;; IDLE
    (if (i32.eq (local.get $lo) (i32.const 0x23))
      (then (global.set $g_idle (i32.const 2)) (return))) ;; IDLE2
    (if (i32.eq (local.get $lo) (i32.const 0x30))
      (then
        ;; CALA: push pc; pc = ACC.
        (call $stack_push (global.get $g_pc))
        (global.set $g_pc (i32.and (global.get $g_acc) (i32.const 0xFFFF)))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x32))
      (then (global.set $g_acc (call $stack_pop)) (return))) ;; POP
    (if (i32.eq (local.get $lo) (i32.const 0x38))
      (then
        ;; RETI: pc = pop; restore context.
        (global.set $g_pc (call $stack_pop))
        (call $restore_ctx)
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x3A))
      (then
        ;; RETE: pc = pop; restore context; INTM = 0.
        (global.set $g_pc (call $stack_pop))
        (call $restore_ctx)
        (global.set $g_intm (i32.const 0))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x3C))
      (then (call $stack_push (i32.and (global.get $g_acc) (i32.const 0xFFFF))) (return))) ;; PSHA
    (if (i32.eq (local.get $lo) (i32.const 0x3D))
      (then
        ;; CALAD: delayed call to ACC; push pc+2 BEFORE the slot.
        (local.set $p (i32.and (global.get $g_acc) (i32.const 0xFFFF)))
        (call $stack_push
          (i32.and (i32.add (global.get $g_pc) (i32.const 2)) (i32.const 0xFFFF)))
        (call $delay_slot (global.get $g_pc))
        (global.set $g_pc (local.get $p))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x40))
      (then (global.set $g_intm (i32.const 0)) (global.set $g_int_inh (i32.const 1)) (return))) ;; EINT
    (if (i32.eq (local.get $lo) (i32.const 0x41))
      (then (global.set $g_intm (i32.const 1)) (return))) ;; DINT
    (if (i32.eq (local.get $lo) (i32.const 0x42))
      (then (global.set $g_ovm (i32.const 0)) (return))) ;; ROVM
    (if (i32.eq (local.get $lo) (i32.const 0x43))
      (then (global.set $g_ovm (i32.const 1)) (return))) ;; SOVM
    (if (i32.eq (local.get $lo) (i32.const 0x44))
      (then (global.set $g_cnf (i32.const 0)) (return))) ;; RCNF
    (if (i32.eq (local.get $lo) (i32.const 0x45))
      (then (global.set $g_cnf (i32.const 1)) (return))) ;; SCNF
    (if (i32.eq (local.get $lo) (i32.const 0x46))
      (then (global.set $g_sxm (i32.const 0)) (return))) ;; RSXM
    (if (i32.eq (local.get $lo) (i32.const 0x47))
      (then (global.set $g_sxm (i32.const 1)) (return))) ;; SSXM
    (if (i32.eq (local.get $lo) (i32.const 0x48))
      (then (global.set $g_hm (i32.const 0)) (return))) ;; RHM
    (if (i32.eq (local.get $lo) (i32.const 0x49))
      (then (global.set $g_hm (i32.const 1)) (return))) ;; SHM
    (if (i32.eq (local.get $lo) (i32.const 0x4A))
      (then (global.set $g_tc (i32.const 0)) (return))) ;; RTC
    (if (i32.eq (local.get $lo) (i32.const 0x4B))
      (then (global.set $g_tc (i32.const 1)) (return))) ;; STC
    (if (i32.eq (local.get $lo) (i32.const 0x4C))
      (then (global.set $g_xf (i32.const 0)) (return))) ;; RXF
    (if (i32.eq (local.get $lo) (i32.const 0x4D))
      (then (global.set $g_xf (i32.const 1)) (return))) ;; SXF
    (if (i32.eq (local.get $lo) (i32.const 0x4E))
      (then (global.set $g_c (i32.const 0)) (return))) ;; RCB
    (if (i32.eq (local.get $lo) (i32.const 0x4F))
      (then (global.set $g_c (i32.const 1)) (return))) ;; SCB
    (if (i32.eq (local.get $lo) (i32.const 0x51))
      (then
        ;; TRAP: push pc, jump to IPTR-relative vector 0x22. No INTM
        ;; set and no context shadow (unlike 0x52).
        (call $stack_push (global.get $g_pc))
        (global.set $g_pc
          (i32.or (i32.shl (global.get $g_iptr) (i32.const 11)) (i32.const 0x22)))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x52))
      (then
        ;; NMI (instruction): push pc, jump to vector 0x24, mask
        ;; interrupts. No context shadow here either.
        (call $stack_push (global.get $g_pc))
        (global.set $g_pc
          (i32.or (i32.shl (global.get $g_iptr) (i32.const 11)) (i32.const 0x24)))
        (global.set $g_intm (i32.const 1))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x58))
      (then (global.set $g_preg (i32.const 0)) (return))) ;; PREG = 0
    (if (i32.eq (local.get $lo) (i32.const 0x59))
      (then
        (global.set $g_acc (i32.const 0))
        (global.set $g_preg (i32.const 0))
        (return))) ;; ACC = 0, PREG = 0
    (if (i32.eq (local.get $lo) (i32.const 0x5A))
      (then
        ;; SATH: if TREG1 bit 4 set, ACC >>= 16 (sign per SXM).
        (if (i32.and (global.get $g_treg1) (i32.const 0x10))
          (then
            (global.set $g_acc
              (if (result i32) (global.get $g_sxm)
                (then (i32.shr_s (global.get $g_acc) (i32.const 16)))
                (else (i32.shr_u (global.get $g_acc) (i32.const 16)))))))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x5B))
      (then
        ;; SATL: ACC >>= (TREG1 & 0xF) (sign per SXM).
        (global.set $g_acc
          (if (result i32) (global.get $g_sxm)
            (then (i32.shr_s (global.get $g_acc)
                             (i32.and (global.get $g_treg1) (i32.const 0xF))))
            (else (i32.shr_u (global.get $g_acc)
                             (i32.and (global.get $g_treg1) (i32.const 0xF))))))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x80))
      (then
        ;; MPY #lk: PREG = TREG0 * imm.
        (local.set $imm (call $fetch))
        (global.set $g_preg
          (i32.mul (i32.extend16_s (global.get $g_treg0))
                   (i32.extend16_s (local.get $imm))))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x81))
      (then
        ;; AND #lk,16: ACC &= imm << 16.
        (local.set $imm (call $fetch))
        (global.set $g_acc
          (i32.and (global.get $g_acc) (i32.shl (local.get $imm) (i32.const 16))))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x82))
      (then
        ;; OR #lk,16.
        (local.set $imm (call $fetch))
        (global.set $g_acc
          (i32.or (global.get $g_acc) (i32.shl (local.get $imm) (i32.const 16))))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0x83))
      (then
        ;; XOR #lk,16.
        (local.set $imm (call $fetch))
        (global.set $g_acc
          (i32.xor (global.get $g_acc) (i32.shl (local.get $imm) (i32.const 16))))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0xC4))
      (then
        ;; RPT #lk: repeat count from the next word.
        (global.set $g_rptc (call $fetch))
        (global.set $g_rpt_start (global.get $g_pc))
        (global.set $g_rpt_end (global.get $g_pc))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0xC5))
      (then
        ;; RPTZ #lk: like RPT, and ACC = PREG = 0.
        (global.set $g_rptc (call $fetch))
        (global.set $g_rpt_start (global.get $g_pc))
        (global.set $g_rpt_end (global.get $g_pc))
        (global.set $g_acc (i32.const 0))
        (global.set $g_preg (i32.const 0))
        (return)))
    (if (i32.eq (local.get $lo) (i32.const 0xC6))
      (then
        ;; RPTB: PAER = operand = address of the last loop word.
        (local.set $imm (call $fetch))
        (global.set $g_braf (i32.const 1))
        (global.set $g_pasr (global.get $g_pc))
        (global.set $g_paer (local.get $imm))
        (return)))
    ;; Default: INTR k when (op & 0xE0) == 0x60, else BADOP.
    (if (i32.eq (i32.and (local.get $lo) (i32.const 0xE0)) (i32.const 0x60))
      (then
        ;; INTR k: vector = K*2, IPTR-relative. Plain-path save set is
        ;; the manual's K=1..4 (v = 0x02/0x04/0x06/0x08, DESIGN 5.3.1
        ;; Rank 3) -- C saves {1,2,3,9} instead; DESIGN follows the
        ;; manual here. ivec_ind (audited table first, then legacy)
        ;; redirects the jump via dmem[ivec_ind[i]], saving context.
        (local.set $v (i32.shl (i32.and (local.get $lo) (i32.const 0x1F)) (i32.const 1)))
        (call $stack_push (global.get $g_pc))
        (global.set $g_intm (i32.const 1))
        (global.set $g_pc
          (i32.or (i32.shl (global.get $g_iptr) (i32.const 11)) (local.get $v)))
        (if (i32.or (i32.or (i32.eq (local.get $v) (i32.const 0x02))
                            (i32.eq (local.get $v) (i32.const 0x04)))
                    (i32.or (i32.eq (local.get $v) (i32.const 0x06))
                            (i32.eq (local.get $v) (i32.const 0x08))))
          (then (call $save_ctx)))
        (local.set $i (i32.const 0))
        (block $found
          (loop $loop
            (br_if $found (i32.ge_u (local.get $i) (i32.const 9)))
            (if (i32.and
                  (i32.eq (i32.load8_u offset=0x92300 (local.get $i)) (local.get $v))
                  ;; i32.and is bitwise: the ivec_ind value must be
                  ;; reduced to a boolean first (an even address like
                  ;; 0x68 would make 1 & 0x68 == 0 and skip the redirect).
                  (i32.ne (call $ivec_ind_get (local.get $i)) (i32.const 0)))
              (then
                (global.set $g_pc (call $dm_rd (call $ivec_ind_get (local.get $i))))
                (call $save_ctx)
                (br $found)))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $loop)))
        (if (i32.ge_u (local.get $i) (i32.const 9))
          (then
            (local.set $i (i32.const 0))
            (block $found2
              (loop $loop2
                (br_if $found2 (i32.ge_u (local.get $i) (i32.const 9)))
                (if (i32.and
                      (i32.eq (i32.load8_u offset=0x92310 (local.get $i)) (local.get $v))
                      (i32.ne (call $ivec_ind_get (local.get $i)) (i32.const 0)))
                  (then
                    (global.set $g_pc (call $dm_rd (call $ivec_ind_get (local.get $i))))
                    (call $save_ctx)
                    (br $found2)))
                (local.set $i (i32.add (local.get $i) (i32.const 1)))
                (br $loop2)))))
        (return)))
    (global.set $g_status (i32.const 2)))

  ;; 0xBE sub-decoder: dispatch on the low byte.
  (func $exec_be
    (if (i32.lt_u (i32.and (global.get $g_op) (i32.const 0xFF)) (i32.const 0x20))
      (then (call $exec_be_acc))
      (else (call $exec_be_ctrl))))

  ;; 0xBF sub-decoder: PM select, LAR #lk, CMPR, long-immediate ALU ops.
  (func $exec_bf
    (local $lo i32) (local $imm i32) (local $sh i32) (local $hi i32)
    (local $r i32) (local $cmpv i32)
    (local.set $lo (i32.and (global.get $g_op) (i32.const 0xFF)))
    (local.set $sh (i32.and (local.get $lo) (i32.const 0xF)))
    (if (i32.le_u (local.get $lo) (i32.const 0x03))
      (then
        ;; SPM k: PM = low 2 bits.
        (global.set $g_pm (i32.and (local.get $lo) (i32.const 3)))
        (return)))
    (if (i32.and (i32.ge_u (local.get $lo) (i32.const 0x08))
                 (i32.le_u (local.get $lo) (i32.const 0x0F)))
      (then
        ;; LAR #lk: AR[(op&7)] = next word.
        (local.set $imm (call $fetch))
        (call $ar_set (i32.and (local.get $lo) (i32.const 7)) (local.get $imm))
        (return)))
    (if (i32.and (i32.ge_u (local.get $lo) (i32.const 0x44))
                 (i32.le_u (local.get $lo) (i32.const 0x47)))
      (then
        ;; CMPR: compare AR[ARP] against ARCR. Mode: 0 ==, 1 <, 2 >, 3 !=.
        ;; (The cmpr_ar0 experiment is OFF in this build: always ARCR.)
        (local.set $r (call $ar_get (global.get $g_arp)))
        (local.set $cmpv (global.get $g_arcr))
        (global.set $g_tc
          (if (result i32) (i32.eq (i32.and (local.get $lo) (i32.const 3)) (i32.const 0))
            (then (i32.eq (local.get $r) (local.get $cmpv)))
            (else
              (if (result i32) (i32.eq (i32.and (local.get $lo) (i32.const 3)) (i32.const 1))
                (then (i32.lt_u (local.get $r) (local.get $cmpv)))
                (else
                  (if (result i32) (i32.eq (i32.and (local.get $lo) (i32.const 3)) (i32.const 2))
                    (then (i32.gt_u (local.get $r) (local.get $cmpv)))
                    (else (i32.ne (local.get $r) (local.get $cmpv)))))))))
        (return)))
    ;; Default: long-immediate ALU (hi = op & 0xF0), SFTA (0xE0), else BADOP.
    (local.set $hi (i32.and (local.get $lo) (i32.const 0xF0)))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0x80))
                 (i32.le_u (local.get $hi) (i32.const 0xD0)))
      (then
        (local.set $imm (call $fetch))
        (if (i32.eq (local.get $hi) (i32.const 0x80))
          (then (global.set $g_acc (call $ext (local.get $imm) (local.get $sh))) (return)))
        (if (i32.eq (local.get $hi) (i32.const 0x90))
          (then
            (global.set $g_acc
              (call $do_add (global.get $g_acc)
                            (call $ext (local.get $imm) (local.get $sh))
                            (i32.const 0) (i32.const 0)))
            (return)))
        (if (i32.eq (local.get $hi) (i32.const 0xA0))
          (then
            (global.set $g_acc
              (call $do_sub (global.get $g_acc)
                            (call $ext (local.get $imm) (local.get $sh))
                            (i32.const 0) (i32.const 0)))
            (return)))
        (if (i32.eq (local.get $hi) (i32.const 0xB0))
          (then
            (global.set $g_acc
              (i32.and (global.get $g_acc)
                       (i32.shl (local.get $imm) (local.get $sh))))
            (return)))
        (if (i32.eq (local.get $hi) (i32.const 0xC0))
          (then
            (global.set $g_acc
              (i32.or (global.get $g_acc)
                      (i32.shl (local.get $imm) (local.get $sh))))
            (return)))
        (if (i32.eq (local.get $hi) (i32.const 0xD0))
          (then
            (global.set $g_acc
              (i32.xor (global.get $g_acc)
                       (i32.shl (local.get $imm) (local.get $sh))))
            (return))))
      (else
        (if (i32.eq (local.get $hi) (i32.const 0xE0))
          (then
            ;; SFTA: ACC >>= (sh + 1), sign per SXM.
            (local.set $sh (i32.add (local.get $sh) (i32.const 1)))
            (global.set $g_acc
              (if (result i32) (global.get $g_sxm)
                (then (i32.shr_s (global.get $g_acc) (local.get $sh)))
                (else (i32.shr_u (global.get $g_acc) (local.get $sh)))))
            (return)))
        (global.set $g_status (i32.const 2)))))

  ;; High bytes 0xE0-0xFF: conditional branches/calls/returns and XC.
  ;; BCND/CC/RETC use the LIVE $cond(); XC uses $g_cond_latched
  ;; (Rank 8). $g_taken is set exactly when the branch is taken
  ;; (Rank 25: a taken branch landing on the fall-through address
  ;; still costs 4 -- never a pc == ppc+words test).
  (func $exec_hi_e0_ff (param $op i32)
    (local $imm i32) (local $hi i32) (local $n i32) (local $c i32)
    (local.set $hi (i32.shr_u (local.get $op) (i32.const 8)))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0xE0))
                 (i32.le_u (local.get $hi) (i32.const 0xE3)))
      (then
        ;; BCND: branch if cond; bit 1 (op & 2) clears OV on the taken path.
        (local.set $imm (call $fetch))
        (local.set $c (call $cond))
        (global.set $g_taken (local.get $c))
        (if (local.get $c)
          (then
            (global.set $g_pc (local.get $imm))
            (if (i32.and (local.get $op) (i32.const 2))
              (then (global.set $g_ov (i32.const 0))))))
        (return)))
    (if (i32.or (i32.and (i32.ge_u (local.get $hi) (i32.const 0xE4))
                         (i32.le_u (local.get $hi) (i32.const 0xE7)))
                (i32.and (i32.ge_u (local.get $hi) (i32.const 0xF4))
                         (i32.le_u (local.get $hi) (i32.const 0xF7))))
      (then
        ;; XC: if the condition fails, skip n instruction WORDS
        ;; (n = ((op>>12)&1) + 1). If it passes, XC and the two words
        ;; following it are uninterruptible, whatever n.
        ;; NOTE: the condition is evaluated LIVE with the XC's own
        ;; opcode (as in C). The earlier $g_cond_latched design was
        ;; wrong: $cond() reads $g_op, so the latch refreshed after an
        ;; instruction carried that instruction's condition field, not
        ;; the XC's -- the XC then tested the previous instruction's
        ;; condition bits. (DESIGN §4.5.6 "condition stable one cycle
        ;; before XC" is about the FLAG values, which live evaluation
        ;; already uses: the XC has not modified them yet.)
        (if (i32.eqz (call $cond))
          (then
            (local.set $n (i32.add (i32.and (i32.shr_u (local.get $op) (i32.const 12)) (i32.const 1)) (i32.const 1)))
            (global.set $g_pc
              (i32.and (i32.add (global.get $g_pc) (local.get $n)) (i32.const 0xFFFF))))
          (else
            (global.set $g_xc_left (i32.const 2))
            (global.set $g_xc_new (i32.const 1))))
        (return)))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0xE8))
                 (i32.le_u (local.get $hi) (i32.const 0xEB)))
      (then
        ;; CC: conditional call; bit 1 clears OV on the taken path.
        (local.set $imm (call $fetch))
        (local.set $c (call $cond))
        (global.set $g_taken (local.get $c))
        (if (local.get $c)
          (then
            (call $stack_push (global.get $g_pc))
            (global.set $g_pc (local.get $imm))
            (if (i32.and (local.get $op) (i32.const 2))
              (then (global.set $g_ov (i32.const 0))))))
        (return)))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0xEC))
                 (i32.le_u (local.get $hi) (i32.const 0xEF)))
      (then
        ;; RETC: conditional return; no status bits affected.
        (local.set $c (call $cond))
        (global.set $g_taken (local.get $c))
        (if (local.get $c)
          (then (global.set $g_pc (call $stack_pop))))
        (return)))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0xF0))
                 (i32.le_u (local.get $hi) (i32.const 0xF3)))
      (then
        ;; BCNDD: delayed conditional branch.
        (local.set $imm (call $fetch))
        (if (call $cond)
          (then
            (if (i32.and (local.get $op) (i32.const 2))
              (then (global.set $g_ov (i32.const 0))))
            (call $delay_slot (global.get $g_pc))
            (global.set $g_pc (local.get $imm))))
        (return)))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0xF8))
                 (i32.le_u (local.get $hi) (i32.const 0xFB)))
      (then
        ;; CCD: delayed conditional call; return is pc+2.
        (local.set $imm (call $fetch))
        (if (call $cond)
          (then
            (call $stack_push
              (i32.and (i32.add (global.get $g_pc) (i32.const 2)) (i32.const 0xFFFF)))
            (if (i32.and (local.get $op) (i32.const 2))
              (then (global.set $g_ov (i32.const 0))))
            (call $delay_slot (global.get $g_pc))
            (global.set $g_pc (local.get $imm))))
        (return)))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0xFC))
                 (i32.le_u (local.get $hi) (i32.const 0xFF)))
      (then
        ;; RETCD: delayed conditional return; slot first, then pop.
        (if (call $cond)
          (then
            (call $delay_slot (global.get $g_pc))
            (global.set $g_pc (call $stack_pop))))
        (return)))
    (global.set $g_status (i32.const 2)))

  ;; ================= single-instruction execution ====================
  ;; $exec1: diagnostics (diag-gated), fetch, charge the manual table
  ;; value at fetch time (DESIGN 4.1 -- NOT a base 1; the run loop
  ;; applies the override delta afterwards), dispatch on the high
  ;; nibble via br_table to the family functions. High bytes
  ;; 0xC0-0xDF are MPY #k13, inlined here as in C.
  (func $exec1
    (local $op i32) (local $k i32)
    (global.set $g_cur_pc (global.get $g_pc))
    (if (global.get $g_diag)
      (then
        ;; hits[pc]++ (HITS @0xB0000, u32 per PC).
        (i32.store offset=0xB0000 (i32.shl (global.get $g_pc) (i32.const 2))
          (i32.add
            (i32.load offset=0xB0000 (i32.shl (global.get $g_pc) (i32.const 2)))
            (i32.const 1)))
        ;; pcring[pcring_i++ & 255] = pc (pcring @0x1B1000, u16).
        (i32.store16 offset=0x1B1000
          (i32.shl (i32.and (global.get $g_pcring_i) (i32.const 255)) (i32.const 1))
          (global.get $g_pc))
        (global.set $g_pcring_i (i32.add (global.get $g_pcring_i) (i32.const 1)))
        ;; pc_hits[pc]++ (PC_HITS @0xF0000, u32 per PC).
        (i32.store offset=0xF0000 (i32.shl (global.get $g_pc) (i32.const 2))
          (i32.add
            (i32.load offset=0xF0000 (i32.shl (global.get $g_pc) (i32.const 2)))
            (i32.const 1)))
        ;; Trace capture: acc, stack[sp], stack[(sp+1)&7], cycles.
        (if (i32.and (i32.eq (global.get $g_pc) (global.get $g_trace_pc))
                     (i32.lt_u (global.get $g_trace_n) (i32.const 8192)))
          (then
            (i32.store offset=0x170000
              (i32.mul (global.get $g_trace_n) (i32.const 16)) (global.get $g_acc))
            (i32.store16 offset=0x170000
              (i32.add (i32.mul (global.get $g_trace_n) (i32.const 16)) (i32.const 4))
              (i32.load16_u offset=0x92410
                (i32.shl (global.get $g_sp) (i32.const 1))))
            (i32.store16 offset=0x170000
              (i32.add (i32.mul (global.get $g_trace_n) (i32.const 16)) (i32.const 6))
              (i32.load16_u offset=0x92410
                (i32.shl (i32.and (i32.add (global.get $g_sp) (i32.const 1))
                                  (i32.const 7))
                         (i32.const 1))))
            (i64.store offset=0x170000
              (i32.add (i32.mul (global.get $g_trace_n) (i32.const 16)) (i32.const 8))
              (global.get $g_cycles))
            (global.set $g_trace_n (i32.add (global.get $g_trace_n) (i32.const 1)))))))
    (local.set $op (call $fetch))
    (global.set $g_op (local.get $op))
    ;; Charge the manual table value at fetch (DESIGN 4.1).
    (call $cycles_add
      (i64.extend_i32_u (i32.load8_u offset=0x60000 (local.get $op))))
    (block $exit
      (block $b0
        (block $b1
          (block $b2
            (block $b3
              (block $b4
                (block $b5
                  (block $b6
                    (block $b7
                      (block $b8
                        (br_table $b0 $b1 $b1 $b1 $b2 $b2 $b3 $b3 $b4 $b4
                                  $b5 $b6 $b7 $b7 $b8 $b8
                          (i32.shr_u (local.get $op) (i32.const 12))))
                      ;; nibble E,F: exec_hi_e0_ff
                      (call $exec_hi_e0_ff (local.get $op))
                      (br $exit))
                    ;; nibble C,D: MPY #k13 (signed 13-bit immediate).
                    (local.set $k (i32.and (local.get $op) (i32.const 0x1FFF)))
                    (if (i32.and (local.get $k) (i32.const 0x1000))
                      (then (local.set $k (i32.sub (local.get $k) (i32.const 0x2000)))))
                    (global.set $g_preg
                      (i32.mul (i32.extend16_s (global.get $g_treg0)) (local.get $k)))
                    (br $exit))
                  ;; nibble B: exec_hi_b0_bf
                  (call $exec_hi_b0_bf (local.get $op))
                  (br $exit))
                ;; nibble A: exec_hi_a0_af
                (call $exec_hi_a0_af (local.get $op))
                (br $exit))
              ;; nibble 8,9: exec_hi_80_9f
              (call $exec_hi_80_9f (local.get $op))
              (br $exit))
            ;; nibble 6,7: exec_hi_60_7f
            (call $exec_hi_60_7f (local.get $op))
            (br $exit))
          ;; nibble 4,5: exec_hi_40_5f
          (call $exec_hi_40_5f (local.get $op))
          (br $exit))
        ;; nibble 1,2,3: exec_hi_10_3f
        (call $exec_hi_10_3f (local.get $op))
        (br $exit))
      ;; nibble 0: exec_hi_00_0f
      (call $exec_hi_00_0f (local.get $op))
      (br $exit)))

  ;; ================= main run loop (DESIGN 5.1/5.3) ==================
  ;; Returns 0 RUN_OK, 1 RUN_BP, 2 RUN_BADOP, 3 RUN_STOP.
  (func $run (export "run") (param $budget i32) (result i32)
    (local $end i64) (local $first i32) (local $c0 i64) (local $ppc i32)
    (local $wake i32) (local $step i64) (local $held i32)
    (local.set $end
      (i64.add (global.get $g_cycles) (i64.extend_i32_u (local.get $budget))))
    (local.set $first (i32.const 1))
    (global.set $g_stop (i32.const 0))
    (global.set $g_status (i32.const 0))
    (block $out
      (loop $loop
        (br_if $out (i64.ge_u (global.get $g_cycles) (local.get $end)))
        (local.set $c0 (global.get $g_cycles))
        (if (global.get $g_idle)
          (then
            ;; Wake test (V4: NMI wakes IDLE as well as IDLE2;
            ;; DESIGN 5.1 lists it only for IDLE2; manual 4.10
            ;; makes NMI unmaskable for both).
            (local.set $wake
              (if (result i32) (i32.eq (global.get $g_idle) (i32.const 2))
                (then (i32.const 0x0107))
                (else (i32.const 0xFFFF))))
            (if (i32.or
                  (i32.ne
                    (i32.and (i32.and (global.get $g_ifr) (global.get $g_imr))
                             (local.get $wake))
                    (i32.const 0))
                  (global.get $g_nmi_pending))
              (then
                (global.set $g_idle (i32.const 0))
                (call $check_int)
                (br $loop)))
            ;; Fast-forward: no wake can arrive before the budget
            ;; ends (interrupts arrive only between run() calls).
            (if (i32.or (i32.eq (global.get $g_idle) (i32.const 2))
                        (global.get $g_tss))
              (then
                ;; IDLE2 stops the timer; a stopped timer never ticks.
                (global.set $g_idle_cycles
                  (i64.add (global.get $g_idle_cycles)
                           (i64.sub (local.get $end) (global.get $g_cycles))))
                (global.set $g_cycles (local.get $end))
                (br $loop)))
            (if (i32.and (global.get $g_imr) (i32.const 0x08))
              (then
                ;; Jump to the next TINT expiry (or the budget end);
                ;; the loop top then takes the interrupt at exactly
                ;; the expiry cycle.
                (local.set $step (call $timer_cycles_to_expiry))
                (if (i64.gt_u (local.get $step)
                              (i64.sub (local.get $end) (global.get $g_cycles)))
                  (then
                    (local.set $step
                      (i64.sub (local.get $end) (global.get $g_cycles)))))
                (call $advance_timer (local.get $step))
                (global.set $g_cycles
                  (i64.add (global.get $g_cycles) (local.get $step)))
                (global.set $g_idle_cycles
                  (i64.add (global.get $g_idle_cycles) (local.get $step))))
              (else
                ;; TINT masked: sleep through every expiry; the timer
                ;; still counts them.
                (call $advance_timer
                  (i64.sub (local.get $end) (global.get $g_cycles)))
                (global.set $g_idle_cycles
                  (i64.add (global.get $g_idle_cycles)
                           (i64.sub (local.get $end) (global.get $g_cycles))))
                (global.set $g_cycles (local.get $end))))
            (br $loop)))
        ;; Breakpoint (first iteration exempt).
        (if (i32.and (i32.load8_u offset=0xA0000 (global.get $g_pc))
                     (i32.eqz (local.get $first)))
          (then
            (global.set $g_status (i32.const 1))
            (return (i32.const 1))))
        (local.set $first (i32.const 0))
        (global.set $g_status (i32.const 0))
        (local.set $ppc (global.get $g_pc))
        (global.set $g_words (i32.const 0))
        (call $exec1)
        ;; Override delta (before $handle_rpt: rptc/rep_cont are still
        ;; the pre-repeat values, as in C's instr_cycles call).
        (call $cycles_add (i64.extend_i32_s (call $cycle_delta)))
        (call $apply_ar0_mirror)
        ;; Refresh the XC condition latch (Rank 8): cond() evaluated
        ;; at the end of this instruction.
        (global.set $g_cond_latched (call $cond))
        (if (i32.eq (global.get $g_status) (i32.const 2))
          (then
            ;; BADOP: restore pc to ppc; cycles keep base+delta, but
            ;; the timer does NOT advance for this instruction.
            (global.set $g_pc (local.get $ppc))
            (return (i32.const 2))))
        (call $handle_rpt (local.get $ppc))
        (call $handle_braf)
        (call $advance_timer (i64.sub (global.get $g_cycles) (local.get $c0)))
        ;; $g_prev_swmc (Rank 6a / DESIGN 5.3): 1 iff the just-executed
        ;; instruction was single-word ($g_words==1) and multi-cycle
        ;; (charged cycles, $g_cycles-$c0, > 1). Feeds the RPTB
        ;; lockout exception in $interrupt_held. (This was declared
        ;; and read but never set, so the lift never fired.)
        (global.set $g_prev_swmc
          (i32.and
            (i32.eq (global.get $g_words) (i32.const 1))
            (i64.gt_u (i64.sub (global.get $g_cycles) (local.get $c0)) (i64.const 1))))
        (local.set $held (call $interrupt_held))
        ;; Inlined check_int fast path (ported from C), plus the
        ;; separate NMI arm (DESIGN 5.3: NMI ignores INTM/IMR).
        (if (global.get $g_int_inh)
          (then (global.set $g_int_inh (i32.const 0)))
          (else
            (if (i32.eqz (local.get $held))
              (then
                (if (i32.and
                      (i32.and
                        (i32.le_s (global.get $g_rptc) (i32.const 0))
                        (i32.eqz (global.get $g_rep_cont)))
                      (i32.and
                        (i32.eqz (global.get $g_intm))
                        (i32.ne (i32.and (global.get $g_ifr) (global.get $g_imr))
                                (i32.const 0))))
                  (then (call $check_int))
                  (else
                    (if (i32.and
                          (i32.and (global.get $g_nmi_pending)
                                   (i32.le_s (global.get $g_rptc) (i32.const 0)))
                          (i32.eqz (global.get $g_rep_cont)))
                      (then (call $check_int)))))))))
        (if (global.get $g_stop)
          (then (return (i32.const 3))))
        (br $loop)))
    (i32.const 0))

  ;; ================= serial port frame tick (DESIGN 5.4) =============
  ;; One call per codec sample period. rx = ADC sample (low 16 bits).
  ;; XINT fires ONLY on the XRDY 0->1 edge (Rank 15: no xint_mode,
  ;; no xint_first kick). RINT fires only when a word is actually
  ;; loaded into DRR.
  (func $serial_tick (export "serial_tick") (param $rx i32)
    (if (i32.and (global.get $g_spc) (i32.const 0x80)) ;; RRST (SPC bit 7)
      (then
        (if (i32.or (global.get $g_rrdy) (global.get $g_rsrfull))
          (then (global.set $g_rsrfull (i32.const 1)))
          (else
            ;; DLB (SPC bit 1): DXR feeds DRR instead of rx.
            (global.set $g_drr
              (if (result i32) (i32.and (global.get $g_spc) (i32.const 2))
                (then (global.get $g_dxr))
                (else (i32.and (local.get $rx) (i32.const 0xFFFF)))))
            (global.set $g_rrdy (i32.const 1))
            (global.set $g_ifr (i32.or (global.get $g_ifr) (i32.const 0x10)))))))
    (if (i32.and (global.get $g_spc) (i32.const 0x40)) ;; XRST (SPC bit 6)
      (then
        (if (i32.eqz (global.get $g_xrdy))
          (then
            (global.set $g_xrdy (i32.const 1))
            (global.set $g_ifr (i32.or (global.get $g_ifr) (i32.const 0x20))))
          (else
            ;; No DXR write since the last tick: underflow.
            (global.set $g_xsrempty (i32.const 0)))))))

  ;; ================= exported API (DESIGN 7) =========================
  ;; $reset(pc): power-on register state (DESIGN 1.7 / C c5x_reset).
  ;; Deliberately does NOT touch: PM/DM/IOMEM, hits/pc_hits/watch/
  ;; trace, MMR counters, breakpoints, I/O log, DXR ring, ivec_ind,
  ;; diag, idle_cycles, timer_exp, INDX/ARCR/CBSR/CBER/BMAR/DBMR/
  ;; PASR/PAER/rpt_start/rpt_end/io_rep.
  (func $reset (export "reset") (param $pc i32)
    (global.set $g_acc (i32.const 0))
    (global.set $g_accb (i32.const 0))
    (global.set $g_preg (i32.const 0))
    (global.set $g_treg0 (i32.const 0))
    (global.set $g_treg1 (i32.const 0))
    (global.set $g_treg2 (i32.const 0))
    (memory.fill (i32.const 0x92400) (i32.const 0) (i32.const 16)) ;; ARs
    (global.set $g_intm (i32.const 1))
    (global.set $g_ov (i32.const 0))
    (global.set $g_ovm (i32.const 0))
    (global.set $g_arp (i32.const 0))
    (global.set $g_arb (i32.const 0))
    (global.set $g_dp (i32.const 0))
    (global.set $g_c (i32.const 1))
    (global.set $g_cnf (i32.const 0))
    (global.set $g_hm (i32.const 1))
    (global.set $g_pm (i32.const 0))
    (global.set $g_sxm (i32.const 1))
    (global.set $g_xf (i32.const 1))
    (global.set $g_tc (i32.const 0))
    (global.set $g_iptr (i32.const 0))
    (global.set $g_avis (i32.const 0))
    (global.set $g_ovly (i32.const 0))
    (global.set $g_ram (i32.const 0))
    (global.set $g_mpmc (i32.const 0))
    (global.set $g_ndx (i32.const 0))
    (global.set $g_trm (i32.const 0))
    (global.set $g_braf (i32.const 0))
    (global.set $g_ifr (i32.const 0))
    (global.set $g_imr (i32.const 0))
    (global.set $g_cbcr (i32.const 0))
    (global.set $g_rptc (i32.const 0))
    (global.set $g_idle (i32.const 0))
    (global.set $g_sp (i32.const 0))
    (global.set $g_ar0_dirty (i32.const 0))
    (global.set $g_ar0_ndx_at_write (i32.const 0))
    (global.set $g_int_inh (i32.const 0))
    (global.set $g_xc_left (i32.const 0))
    (global.set $g_xc_new (i32.const 0))
    (global.set $g_rep_cont (i32.const 0))
    (global.set $g_brcr (i32.const 0))
    (global.set $g_greg (i32.const 0))
    (global.set $g_pdwsr (i32.const 0xFFFF))
    (global.set $g_iowsr (i32.const 0xFFFF))
    (global.set $g_cwsr (i32.const 0x0F))
    (global.set $g_drr (i32.const 0))
    (global.set $g_dxr (i32.const 0))
    (global.set $g_spc (i32.const 0))
    (global.set $g_pc (i32.and (local.get $pc) (i32.const 0xFFFF)))
    (global.set $g_xrdy (i32.const 1))
    (global.set $g_rrdy (i32.const 0))
    (global.set $g_xsrempty (i32.const 0))
    (global.set $g_rsrfull (i32.const 0))
    (global.set $g_cycles (i64.const 0))
    (global.set $g_tss (i32.const 0))
    (global.set $g_psc (i32.const 0))
    (global.set $g_tim (i32.const 0xFFFF))
    (global.set $g_prd (i32.const 0xFFFF))
    (global.set $g_tcr_tddr (i32.const 0))
    (memory.fill (i32.const 0x92410) (i32.const 0) (i32.const 16)) ;; STACK
    (global.set $g_tss_arm (i32.const 0))
    (global.set $g_nmi_pending (i32.const 0))
    (global.set $g_taken (i32.const 0))
    (global.set $g_prev_swmc (i32.const 0))
    (global.set $g_cond_latched (i32.const 0)))

  ;; $init(): fresh instance. Zero-fills every writable region except
  ;; the table bytes (CYCTAB/RPT/REPEATABLE/LEN/IVEC), including
  ;; SCRATCH 0x92400-0x92FFF; resets all globals to fresh-instance
  ;; state (diag=1, trace_pc=-1, watch_a=-1, xrdy=1), then $reset(0).
  ;; Idempotent; the harness calls it once after instantiation.
  (func $init (export "init")
    (memory.fill (i32.const 0x00000) (i32.const 0) (i32.const 0x20000)) ;; PM
    (memory.fill (i32.const 0x20000) (i32.const 0) (i32.const 0x20000)) ;; DM
    (memory.fill (i32.const 0x40000) (i32.const 0) (i32.const 0x20000)) ;; IOMEM
    (memory.fill (i32.const 0x92400) (i32.const 0) (i32.const 0xC00))   ;; SCRATCH
    (memory.fill (i32.const 0xA0000) (i32.const 0) (i32.const 0x10000)) ;; BP
    (memory.fill (i32.const 0xB0000) (i32.const 0) (i32.const 0x40000)) ;; HITS
    (memory.fill (i32.const 0xF0000) (i32.const 0) (i32.const 0x40000)) ;; PC_HITS
    (memory.fill (i32.const 0x130000) (i32.const 0) (i32.const 0x40000)) ;; WATCH_HITS
    (memory.fill (i32.const 0x170000) (i32.const 0) (i32.const 0x20000)) ;; TRACE
    (memory.fill (i32.const 0x190000) (i32.const 0) (i32.const 0x20000)) ;; DXR_RING
    (memory.fill (i32.const 0x1B0000) (i32.const 0) (i32.const 0x10000)) ;; MMR_CTRS
    (memory.fill (i32.const 0x1C0000) (i32.const 0) (i32.const 0x100000)) ;; IOLOG
    (global.set $g_diag (i32.const 1))
    (global.set $g_trace_pc (i32.const -1))
    (global.set $g_watch_a (i32.const -1))
    (global.set $g_idle_cycles (i64.const 0))
    (global.set $g_timer_exp (i64.const 0))
    (global.set $g_iolog_n (i32.const 0))
    (global.set $g_iolog_on (i32.const 0))
    (global.set $g_dxr_head (i32.const 0))
    (global.set $g_pcring_i (i32.const 0))
    (global.set $g_trace_n (i32.const 0))
    (global.set $g_indx (i32.const 0))
    (global.set $g_arcr (i32.const 0))
    (global.set $g_cbsr1 (i32.const 0))
    (global.set $g_cber1 (i32.const 0))
    (global.set $g_cbsr2 (i32.const 0))
    (global.set $g_cber2 (i32.const 0))
    (global.set $g_bmar (i32.const 0))
    (global.set $g_dbmr (i32.const 0))
    (global.set $g_pasr (i32.const 0))
    (global.set $g_paer (i32.const 0))
    (global.set $g_rpt_start (i32.const 0))
    (global.set $g_rpt_end (i32.const 0))
    (global.set $g_io_rep (i32.const 0))
    (global.set $g_tcr_free (i32.const 0))
    (global.set $g_tcr_soft (i32.const 0))
    (global.set $g_bio (i32.const 0))
    (global.set $g_status (i32.const 0))
    (global.set $g_stop (i32.const 0))
    (global.set $g_op (i32.const 0))
    (global.set $g_words (i32.const 0))
    (global.set $g_ea_saram (i32.const 0))
    (global.set $g_cur_pc (i32.const 0))
    (call $reset (i32.const 0)))

  ;; $irq(bit): set IFR bit 0-8.
  (func $irq (export "irq") (param $bit i32)
    (global.set $g_ifr
      (i32.or (global.get $g_ifr) (i32.shl (i32.const 1) (local.get $bit)))))

  ;; $raise_nmi(): latch a host-raised NMI (Rank 48; no C equivalent).
  (func $raise_nmi (export "raise_nmi")
    (global.set $g_nmi_pending (i32.const 1)))

  ;; $set_bio(v): BIO pin level (0 = low, nonzero = high).
  (func $set_bio (export "set_bio") (param $v i32)
    (global.set $g_bio (local.get $v)))

  ;; $stop(): $run returns RUN_STOP after the current instruction.
  (func $stop (export "stop")
    (global.set $g_stop (i32.const 1)))

  ;; $get(id): register ids are the C enum verbatim (DESIGN 7.2).
  ;; Unlisted ids return 0. RPTC returns the signed rptc as u16.
  (func $get (export "get") (param $id i32) (result i32)
    (if (i32.and (i32.ge_u (local.get $id) (i32.const 7))
                 (i32.le_u (local.get $id) (i32.const 14)))
      (then (return (call $ar_get (i32.sub (local.get $id) (i32.const 7))))))
    (if (i32.eq (local.get $id) (i32.const 0)) (then (return (global.get $g_pc))))
    (if (i32.eq (local.get $id) (i32.const 1)) (then (return (global.get $g_acc))))
    (if (i32.eq (local.get $id) (i32.const 2)) (then (return (global.get $g_accb))))
    (if (i32.eq (local.get $id) (i32.const 3)) (then (return (global.get $g_preg))))
    (if (i32.eq (local.get $id) (i32.const 4)) (then (return (global.get $g_treg0))))
    (if (i32.eq (local.get $id) (i32.const 5)) (then (return (global.get $g_treg1))))
    (if (i32.eq (local.get $id) (i32.const 6)) (then (return (global.get $g_treg2))))
    (if (i32.eq (local.get $id) (i32.const 20)) (then (return (call $st0_get))))
    (if (i32.eq (local.get $id) (i32.const 21)) (then (return (call $st1_get))))
    (if (i32.eq (local.get $id) (i32.const 22)) (then (return (call $pmst_get))))
    (if (i32.eq (local.get $id) (i32.const 23)) (then (return (global.get $g_rptc))))
    (if (i32.eq (local.get $id) (i32.const 24)) (then (return (global.get $g_ifr))))
    (if (i32.eq (local.get $id) (i32.const 25)) (then (return (global.get $g_imr))))
    (if (i32.eq (local.get $id) (i32.const 26)) (then (return (global.get $g_sp))))
    (if (i32.eq (local.get $id) (i32.const 27))
      (then (return (i32.wrap_i64 (global.get $g_cycles)))))
    (if (i32.eq (local.get $id) (i32.const 28))
      (then (return (i32.wrap_i64 (i64.shr_u (global.get $g_cycles) (i64.const 32))))))
    (if (i32.eq (local.get $id) (i32.const 29)) (then (return (global.get $g_bmar))))
    (if (i32.eq (local.get $id) (i32.const 30)) (then (return (global.get $g_dbmr))))
    (if (i32.eq (local.get $id) (i32.const 31)) (then (return (global.get $g_indx))))
    (if (i32.eq (local.get $id) (i32.const 32)) (then (return (global.get $g_arcr))))
    (if (i32.eq (local.get $id) (i32.const 33)) (then (return (global.get $g_dxr))))
    (if (i32.eq (local.get $id) (i32.const 34)) (then (return (global.get $g_drr))))
    (if (i32.eq (local.get $id) (i32.const 35)) (then (return (global.get $g_tim))))
    (if (i32.eq (local.get $id) (i32.const 36)) (then (return (global.get $g_prd))))
    (if (i32.eq (local.get $id) (i32.const 37)) (then (return (global.get $g_idle))))
    (i32.const 0))

  ;; $set(id, v): C c5x_set verbatim. Only the listed ids have an
  ;; effect; PREG/T0-T2/RPTC/IFR/SP/CYC/BMAR/DBMR/INDX/ARCR/TIM/PRD
  ;; are get-only here (as in C). AR0 writes set ar0_dirty (via
  ;; $ar_set, which also snapshots NDX per DESIGN 2.4).
  (func $set (export "set") (param $id i32) (param $v i32)
    (if (i32.and (i32.ge_u (local.get $id) (i32.const 7))
                 (i32.le_u (local.get $id) (i32.const 14)))
      (then
        (call $ar_set (i32.sub (local.get $id) (i32.const 7))
                      (i32.and (local.get $v) (i32.const 0xFFFF)))
        (return)))
    (if (i32.eq (local.get $id) (i32.const 0))
      (then (global.set $g_pc (i32.and (local.get $v) (i32.const 0xFFFF))) (return)))
    (if (i32.eq (local.get $id) (i32.const 1))
      (then (global.set $g_acc (local.get $v)) (return)))
    (if (i32.eq (local.get $id) (i32.const 2))
      (then (global.set $g_accb (local.get $v)) (return)))
    (if (i32.eq (local.get $id) (i32.const 34))
      (then (global.set $g_drr (i32.and (local.get $v) (i32.const 0xFFFF))) (return)))
    (if (i32.eq (local.get $id) (i32.const 33))
      (then (global.set $g_dxr (i32.and (local.get $v) (i32.const 0xFFFF))) (return)))
    (if (i32.eq (local.get $id) (i32.const 25))
      (then (global.set $g_imr (i32.and (local.get $v) (i32.const 0xFFFF))) (return)))
    (if (i32.eq (local.get $id) (i32.const 20))
      (then
        ;; ST0: ARP(13), OV(12), OVM(11), INTM(9), DP(8..0).
        (global.set $g_arp (i32.and (i32.shr_u (local.get $v) (i32.const 13)) (i32.const 7)))
        (global.set $g_ov (i32.and (i32.shr_u (local.get $v) (i32.const 12)) (i32.const 1)))
        (global.set $g_ovm (i32.and (i32.shr_u (local.get $v) (i32.const 11)) (i32.const 1)))
        (global.set $g_intm (i32.and (i32.shr_u (local.get $v) (i32.const 9)) (i32.const 1)))
        (global.set $g_dp (i32.shl (i32.and (local.get $v) (i32.const 0x1FF)) (i32.const 7)))
        (return)))
    (if (i32.eq (local.get $id) (i32.const 21))
      (then
        ;; ST1: ARB(13), CNF(12), TC(11), SXM(10), C(9), HM(6), XF(4), PM(1..0).
        (global.set $g_arb (i32.and (i32.shr_u (local.get $v) (i32.const 13)) (i32.const 7)))
        (global.set $g_cnf (i32.and (i32.shr_u (local.get $v) (i32.const 12)) (i32.const 1)))
        (global.set $g_tc (i32.and (i32.shr_u (local.get $v) (i32.const 11)) (i32.const 1)))
        (global.set $g_sxm (i32.and (i32.shr_u (local.get $v) (i32.const 10)) (i32.const 1)))
        (global.set $g_c (i32.and (i32.shr_u (local.get $v) (i32.const 9)) (i32.const 1)))
        (global.set $g_hm (i32.and (i32.shr_u (local.get $v) (i32.const 6)) (i32.const 1)))
        (global.set $g_xf (i32.and (i32.shr_u (local.get $v) (i32.const 4)) (i32.const 1)))
        (global.set $g_pm (i32.and (local.get $v) (i32.const 3)))
        (return)))
    (if (i32.eq (local.get $id) (i32.const 22))
      (then
        ;; PMST: IPTR(15..11), AVIS(7), OVLY(5), RAM(4), MPMC(3),
        ;; NDX(2), TRM(1), BRAF(0).
        (global.set $g_iptr (i32.and (i32.shr_u (local.get $v) (i32.const 11)) (i32.const 0x1F)))
        (global.set $g_avis (i32.and (i32.shr_u (local.get $v) (i32.const 7)) (i32.const 1)))
        (global.set $g_ovly (i32.and (i32.shr_u (local.get $v) (i32.const 5)) (i32.const 1)))
        (global.set $g_ram (i32.and (i32.shr_u (local.get $v) (i32.const 4)) (i32.const 1)))
        (global.set $g_mpmc (i32.and (i32.shr_u (local.get $v) (i32.const 3)) (i32.const 1)))
        (global.set $g_ndx (i32.and (i32.shr_u (local.get $v) (i32.const 2)) (i32.const 1)))
        (global.set $g_trm (i32.and (i32.shr_u (local.get $v) (i32.const 1)) (i32.const 1)))
        (global.set $g_braf (i32.and (local.get $v) (i32.const 1)))
        (return)))
    (if (i32.eq (local.get $id) (i32.const 40))
      (then (call $stack_push (i32.and (local.get $v) (i32.const 0xFFFF))) (return)))
    (if (i32.eq (local.get $id) (i32.const 41))
      (then (global.set $g_idle (local.get $v)) (return))))

  ;; $set_ivec_ind(bit, daddr): ivec_ind[bit] = daddr (16 slots at
  ;; 0x92480; only slots 0-8 are consulted by check_int/INTR).
  (func $set_ivec_ind (export "set_ivec_ind") (param $bit i32) (param $daddr i32)
    (i32.store16 offset=0x92480
      (i32.shl (local.get $bit) (i32.const 1))
      (i32.and (local.get $daddr) (i32.const 0xFFFF))))

  (func $set_diag (export "set_diag") (param $on i32)
    (global.set $g_diag (if (result i32) (local.get $on) (then (i32.const 1)) (else (i32.const 0)))))

  (func $set_bp (export "set_bp") (param $addr i32) (param $on i32)
    (i32.store8 offset=0xA0000
      (i32.and (local.get $addr) (i32.const 0xFFFF))
      (local.get $on)))

  (func $iolog_enable (export "iolog_enable") (param $on i32)
    (global.set $g_iolog_on (if (result i32) (local.get $on) (then (i32.const 1)) (else (i32.const 0)))))

  (func $iolog_clear (export "iolog_clear")
    (global.set $g_iolog_n (i32.const 0)))

  (func $set_trace (export "set_trace") (param $pc i32)
    (global.set $g_trace_pc (local.get $pc))
    (global.set $g_trace_n (i32.const 0)))

  (func $set_watch (export "set_watch") (param $addr i32)
    (global.set $g_watch_a (local.get $addr))
    (memory.fill (i32.const 0x130000) (i32.const 0) (i32.const 0x40000)))

  (func $pc_hits_clear (export "pc_hits_clear")
    (memory.fill (i32.const 0xF0000) (i32.const 0) (i32.const 0x40000)))

  (func $mmr_clear (export "mmr_clear")
    (memory.fill (i32.const 0x1B0000) (i32.const 0) (i32.const 768)))

  (func $layout_version (export "layout_version") (result i32)
    (i32.const 1))

  ;; ================= counter / diagnostic accessors (DESIGN 7.3) =====
  (func $total_cycles (export "total_cycles") (result i64)
    (global.get $g_cycles))
  (func $idle_cycles (export "idle_cycles") (result i64)
    (global.get $g_idle_cycles))
  (func $timer_expiries (export "timer_expiries") (result i64)
    (global.get $g_timer_exp))
  (func $dxr_head (export "dxr_head") (result i32)
    (global.get $g_dxr_head))
  (func $iolog_count (export "iolog_count") (result i32)
    (global.get $g_iolog_n))
  (func $trace_n (export "trace_n") (result i32)
    (global.get $g_trace_n))
  (func $pcring_idx (export "pcring_idx") (result i32)
    (global.get $g_pcring_i))
  (func $watch_hits (export "watch_hits") (param $pc i32) (result i32)
    (i32.load offset=0x130000
      (i32.shl (i32.and (local.get $pc) (i32.const 0xFFFF)) (i32.const 2))))
  (func $pc_hits (export "pc_hits") (param $pc i32) (result i32)
    (i32.load offset=0xF0000
      (i32.shl (i32.and (local.get $pc) (i32.const 0xFFFF)) (i32.const 2))))
  ;; mmr_n[wr][a] at 0x1B0000 + (wr*96 + a)*4; mmr_pc likewise u16
  ;; at 0x1B0300 + (wr*96 + a)*2; mmr_val[a] u16 at 0x1B0480 + a*2.
  (func $mmr_count (export "mmr_count") (param $wr i32) (param $a i32) (result i32)
    (i32.load offset=0x1B0000
      (i32.shl
        (i32.add (i32.mul (local.get $wr) (i32.const 96)) (local.get $a))
        (i32.const 2))))
  (func $mmr_pc (export "mmr_pc") (param $wr i32) (param $a i32) (result i32)
    (i32.load16_u offset=0x1B0300
      (i32.shl
        (i32.add (i32.mul (local.get $wr) (i32.const 96)) (local.get $a))
        (i32.const 1))))
  (func $mmr_val (export "mmr_val") (param $a i32) (result i32)
    (i32.load16_u offset=0x1B0480 (i32.shl (local.get $a) (i32.const 1))))
  ;; ext_n[wr][blk] at 0x1B0540 + (wr*64 + blk)*4 (blk = a>>10).
  (func $ext_count (export "ext_count") (param $wr i32) (param $blk i32) (result i32)
    (i32.load offset=0x1B0540
      (i32.shl
        (i32.add (i32.mul (local.get $wr) (i32.const 64)) (local.get $blk))
        (i32.const 2))))
  ;; ff_n[wr][i] at 0x1B0740 + (wr*256 + (i&255))*4.
  (func $ff_count (export "ff_count") (param $wr i32) (param $i i32) (result i32)
    (i32.load offset=0x1B0740
      (i32.shl
        (i32.add (i32.mul (local.get $wr) (i32.const 256))
                 (i32.and (local.get $i) (i32.const 255)))
        (i32.const 2))))
  ;; rsv(0) = rsv_a @0x1B0F40, rsv(1) = rsv_pc @0x1B0F42.
  (func $rsv (export "rsv") (param $w i32) (result i32)
    (if (result i32) (local.get $w)
      (then (i32.load16_u (i32.const 0x1B0F42)))
      (else (i32.load16_u (i32.const 0x1B0F40)))))
)
