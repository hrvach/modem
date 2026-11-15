# Re-verification: instructions S–Z + cycle model on the NEW core (worker 3 of 5)

Date: 2026-11-15 00:47 CET. NEW core: `~/workspace/user/files/c5x_core-2.c`, 630 lines
(md5 `7aa4227d47e9f72abee2b4cb48fb5fef`, read-only, never modified). OLD core:
`~/workspace/user/files/c5x_core.c`, 603 lines (md5 `41c51be7…`), cited only for
diff comparisons. Manual (only authority): distilled files in
`~/workspace/research_notes/courier-firmware/c5x_manual/` (SPRU056D June 1998).
The June 1998 PDF was not needed as tiebreaker: no distilled-file ambiguity in
this range required it. The 1993 OCR text and `c5x_opcodes.*` /
`c5x_patterns_fixed.json` were never used. Prior record: `05-full-reverification.md`
(and its worker file `05c-reverify-instructions-s-z.md` for the old core).

Chapters used: `06d-instructions-s-z.md` (§6.3, S–Z), `06a-instruction-set-summary.md`
(Tables 6-4..6-10), `appendix-b-instruction-classes-cycles.md` (App. B, Tables B-1/B-2),
`04-program-control.md` (§§4.4–4.9) for the status-bit, repeat, block-repeat and
interrupt passages the §6.3 entries cross-reference, `05-addressing-modes.md`
(§5.2.1, NDX), `06b-instructions-a-h.md` (§6.3 IDLE/IDLE2, for finding #20 only),
`audit-verification.md` (§3, RPTB representation note).

## 0. Method, verdict conventions, and what changed in the diff

- **Form basis.** Same 68 §6.3 description forms as 05 §1 / 05c §0: the 51 §6.3
  entries in 06d expanded where one entry covers several operand forms (RPT ×3,
  SETC ×8, SST ×2, SUB ×4, XC ×2, XOR ×3, XPL ×2).
- **Verdict meanings.** As 05c §0: OBEYS — opcode, words, execution semantics,
  status-bit effects and repeatability all match; VIOLATES — decoded but execution
  contradicts the manual; PARTIAL — executes but at least one manual-stated behaviour
  is wrong or missing; UNVERIFIED — manual silent or self-contradictory, never guessed.
- **Cycles.** Per-form verdicts are on decode + execution + status + repeatability,
  NOT on the cycle counter — except where §2 shows a form's cycle behaviour deviates
  beyond the global model. The cycle model itself is verdict­ed separately (§2, §4
  finding #5). Default behaviour judged is `legacy=0` AND `cyc_model=0` (both are 0
  after `calloc` in `c5x_new()`; they change only via `c5x_set_legacy()` :613 /
  `c5x_set_cycle_model()` :612). §3 documents the legacy-bit deltas.
- **Normative rule.** Opcode-level §6.3 outranks Ch. 4 prose; detailed per-operand
  tables outrank summary tables; specific register descriptions outrank boilerplate.
- **Diff hunks touching S–Z** (full `diff -u` old→new reviewed): `restore_ctx()`
  legacy&32 gating (:278); `delay_slot()` op/cycle restore (:262–268); the
  `cyc_model` block in `c5x_run()` (:584–590) + `fetch()` word counting (:260) +
  `rep_cont`/`words` fields (:36); the NDX=0 AR0→INDX/ARCR mirror in `c5x_run()`
  (:592); `ivec[]` correction (:281) + `ivec_legacy[]` fallback in INTR (:282,
  :521); `check_int()` otherwise unchanged (:283–289); RPTB (:515, :575–578),
  SMMR (:310–311), TBLR (:408–409), TBLW (:410–411), SUBC (:312–313), XC (:438–439),
  RETC/RETCD (:442–443, :448–449), IDLE/IDLE2 (:487–488) all textually unchanged
  except a comment on the XC line. Everything else in the diff (NORM legacy&1,
  CRGT/CRLT legacy&4, MADD/MADS legacy&16/128, TIM legacy&8, serial XINT mode,
  watch/pc_hits harness) is out of the S–Z range and is noted only where it
  interacts (§3, §5).
- **Line numbers** below are new-core lines in `c5x_core-2.c` (630 lines).
  Old-core lines are cited as `old :n` only for comparisons.

## 1. Per-form verdicts (68 forms)

Citations: `06d` = §6.3 entry (PDF p. / printed p. as cited there); `06a` = Tables
6-4..6-10; `AppB` = Appendix B class. "Unchanged" means byte-identical to the old
core's code for that form (modulo line shifts), so the 05c reasoning carries over
and is summarised, not re-derived.

| # | Form | Manual | New core | Verdict | Notes |
|---|---|---|---|---|---|
| 1 | RETC cond | 06d §6.3, PDF p.355 / 6-203; 06a Table 6-8; AppB Class X | :442–443 (0xEC–0xEF), cond() :~250–257 | PARTIAL | Unchanged from old core. Decode, 1 word, TOS→PC + pop, all 14 conditions correct. Defect (unchanged): `if (op & 2) c->ov = 0` clears OV on a taken branch when OV is in the mask; §6.3 RETC says "Status bits: None affected", §4.4 ST0 (04, §4.4.2, PDF p.89 / 4-10) allows OV-clear only "by a conditional branch BCND/BCNDD on OV/NOV" (05 §3 N-12, still present — §4). Cycle note: in `cyc_model` mode the taken/not-taken override (:588–589) gives 4 taken / 2 not-taken, matching normative §6.3 True 4 / False 2 — see §2. |
| 2 | RETCD cond | 06d §6.3, PDF p.357 / 6-205; 06a Table 6-8; AppB Class XI | :448–449 (0xFC–0xFF), delay_slot() :262–268 | PARTIAL | Unchanged semantics. Delay-slot execution (2 words) correct; false condition falls through correctly. Two defects (unchanged): (a) OV-clear as RETC (N-12); (b) `pop()` happens BEFORE `delay_slot()` — a delay-slot instruction that pushes/pops sees the wrong stack level (finding #26, still present — §4). The new `delay_slot()` op/cycle restore (:266–267) does not touch stack ordering. Cycle note: §6.3 flat 2 vs Table 6-8 "4¶ or 2#" — §6.3 + AppB agree on 2 (§6); in `cyc_model` mode the false path gets 2 via the :589 override and the true path gets the table value (presumed 2, unverifiable — §2). |
| 3 | RETD | 06d §6.3, PDF p.359 / 6-207; 06a Table 6-8; AppB Class XI | :448–449 (0xFF00 = RETCD UNC) | PARTIAL | Unchanged semantics. Unconditional encoding correct (TP=3, mask 0 → `cond()` always true; `op & 2` = 0 so no OV-clear here). Defect: same pop-before-delay-slot ordering as RETCD (#26). In `cyc_model` mode RETD (0xFF) is deliberately excluded from the :589 not-taken override, so its 2 cycles rest entirely on the unverifiable table (§2). |
| 4 | RETE | 06d §6.3, PDF p.360 / 6-208; 06a Table 6-8; AppB Class X | exec_be :492 (0xBE3A), restore_ctx() :275–279 | OBEYS | **CHANGED — was PARTIAL in 05c.** Opcode, pop PC, `intm = 0` after restore all correct (unchanged). The defect is fixed at `legacy=0`: `restore_ctx()` :278 restores INTM/XF only `if (c->legacy & 32)`; at default legacy=0 neither is restored, matching §6.3 RETE ("RETE automatically clears the INTM bit and pops the shadow register values") read with §4.8.8 (04, PDF p.121 / 4-42: INTM in ST0 and XF in ST1 "are not saved or restored") and §6.3 RETI's "Does not affect: INTM" list. Under `legacy&32` the old bug returns (XF wrongly restored; INTM ends 0 anyway via the explicit assignment after the restore) — §3. |
| 5 | RETI | 06d §6.3, PDF p.361 / 6-209; 06a Table 6-8; AppB Class X | exec_be :491 (0xBE38), restore_ctx() :275–279 | OBEYS | **CHANGED — was PARTIAL in 05c.** Opcode, pop PC, 11-register shadow restore otherwise correct (shadow set matches §6.3 list: ACC, ACCB, ARCR, INDX, PMST, PREG, ST0, ST1, TREG0–2; `restore_ctx()` restores every listed field). Both 05c defects were the #9 shadow: (a) INTM restored — now gated behind `legacy&32` (:278), so at legacy=0 RETI leaves INTM exactly as the ISR left it, matching §6.3 RETI "Does not affect: INTM"; (b) XF restored — likewise gated off at legacy=0, matching §4.8.8. Note `check_int()` :287 still sets `intm = 1` BEFORE `save_ctx()` (:269–273), so `sh.intm` is always 1 — observable only under `legacy&32`, where RETI then forces INTM=1 even after CLRC INTM in the ISR (§3). |
| 6 | ROL | 06d §6.3, PDF p.362 / 6-210; 06a Table 6-4; AppB Class I | exec_be :467 (0xBE0C) | OBEYS | Unchanged. 32-bit rotate through C exactly as printed; SXM correctly ignored; affects C only. |
| 7 | ROLB | 06d §6.3, PDF p.363 / 6-211; 06a Table 6-4; AppB Class I | exec_be :473 (0xBE14) | OBEYS | Unchanged. 65-bit rotate ACCB+ACC through C exactly as printed. |
| 8 | ROR | 06d §6.3, PDF p.364 / 6-212; 06a Table 6-4; AppB Class I | exec_be :468 (0xBE0D) | OBEYS | Unchanged. C→ACC(31), ACC(0)→C, exact; SXM correctly ignored. |
| 9 | RORB | 06d §6.3, PDF p.365 / 6-213; 06a Table 6-4; AppB Class I | exec_be :474 (0xBE15) | OBEYS | Unchanged. 65-bit rotate right exactly as printed. |
| 10 | RPT dma | 06d §6.3, PDF pp.366–367 / 6-214–6-215; 06a Table 6-10; AppB Class IIA | :314 (0x0B) | OBEYS | Unchanged. 16-bit `(dma) → RPTC`; next instruction ×(RPTC+1) via run loop (:595–596). Cross-cutting notes (not demoting this form, per 05c §0): run loop repeats non-repeatable targets (finding #7, still present); RPTC reset value is −1 not 0 (finding #2, still present — `c5x_reset()` :83 `rptc = -1`). |
| 11 | RPT #k | 06d §6.3, PDF pp.366–367 / 6-214–6-215; 06a Table 6-10; AppB Class XXIX | :432 (0xBB) | OBEYS | Unchanged. `rptc = op & 0xff` (0–255), 1 word. Same cross-cutting notes as RPT dma. |
| 12 | RPT #lk | 06d §6.3, PDF pp.366–367 / 6-214–6-215; 06a Table 6-10; AppB Class III | exec_be :513 (0xBEC4) | OBEYS | Unchanged. Word 1 BEC4, word 2 lk → RPTC (0–65535). Same cross-cutting notes as RPT dma. |
| 13 | RPTB pma | 06d §6.3, PDF pp.369–370 / 6-217–6-218; 06a Table 6-10; AppB Class III | exec_be :515 (0xBEC6) + run loop :575–578 | PARTIAL | Unchanged. BRAF←1, PASR←PC (pc after word-2 fetch) and iteration count BRCR+1 are correct. Defects (unchanged): (a) `paer = imm + 1`, manual Execution is "pma → PAER" (finding #8 — §4); (b) `brcr--` runs unconditionally at wrap (:577), so BRCR reads 0xFFFF after completion; §4.7 loop-end test (04, PDF p.110 / 4-31) decrements BRCR only when BRCR > 0, so it must read 0 (finding #31 — §4); (c) last-word interrupt lockout (§4.7.2, 04, PDF pp.113–114 / 4-34–4-35) not implemented — `check_int()` runs after every instruction (finding #31 — §4). |
| 14 | RPTZ #lk | 06d §6.3, PDF p.371 / 6-219; 06a Table 6-10; AppB Class III | exec_be :514 (0xBEC5) | OBEYS | Unchanged. 0→ACC, 0→PREG, lk→RPTC; 2 words. |
| 15 | SACB | 06d §6.3, PDF p.372 / 6-220; 06a Table 6-4; AppB Class I | exec_be :483 (0xBE1E) | OBEYS | Unchanged. ACC→ACCB, ACC unaffected, none affected. |
| 16 | SACH dma[,shift] | 06d §6.3, PDF p.373 / 6-221; 06a Table 6-4; AppB Class IVA | :394–395 (0x98–0x9F) | OBEYS | Unchanged. `(ACC << SHF) >> 16` stored; SHF = bits 10–8; high bits lost, ACC unaffected; SXM correctly ignored. Cycle note only: SARAM same-block +1/+2 and external `2+d` cases are not in the cycle model (§2). |
| 17 | SACL dma[,shift] | 06d §6.3, PDF p.375 / 6-223; 06a Table 6-4; AppB Class IVA | :392–393 (0x90–0x97) | OBEYS | Unchanged. Low 16 of `ACC << SHF` stored; low bits zero-filled; ACC unaffected; SXM correctly ignored. Same cycle note as SACH. |
| 18 | SAMM dma | 06d §6.3, PDF p.377 / 6-225; 06a Table 6-4; AppB Class IVB | :383 (0x88) | OBEYS | Unchanged. ACCL→MMR at page-0 address: `ea(c) & 0x7f` implements "9 MSBs of dma cleared regardless of DP / upper AR bits". None affected. Cycle note only: peripheral +1 cycle and MMPORT `2+io` are not in the cycle model (§2). |
| 19 | SAR ARx,dma | 06d §6.3, PDF pp.379–380 / 6-227–6-228; 06a Table 6-5; AppB Class IVA | :381–382 (0x80–0x87) | OBEYS | Unchanged code, **improved context**: ARX = bits 10–8; value read BEFORE `ea()` applies the indirect modifier, exactly as the manual requires. The 05c cross-cutting NDX note is now partly addressed: the new run-loop mirror (:592) sets INDX=ARCR=AR0 after any AR0 change when `!ndx && !(legacy&64)` — so a SAR whose indirect modifier moves AR0 now mirrors correctly at default settings (audit-verification #8: §5.2.1, 05, PDF p.136 / 5-6). Residual gaps: mirror fires only when AR0's value changes (same-value reload with stale INDX/ARCR missed), and only after an `exec1()` call — see §5 N-C2-7. Not demoting: the form's own semantics were already OBEYS. |
| 20 | SATH | 06d §6.3, PDF p.381 / 6-229; 06a Table 6-4; AppB Class I | exec_be :507 (0xBE5A) | OBEYS | Unchanged. Shift 16 iff TREG1(4); SXM fill; C untouched. |
| 21 | SATL | 06d §6.3, PDF p.383 / 6-231; 06a Table 6-4; AppB Class I | exec_be :508 (0xBE5B) | OBEYS | Unchanged. Shift 0–15 by TREG1(3–0); SXM fill; C untouched. (TREG1 width unmasked — finding #28, shared.) |
| 22 | SBB | 06d §6.3, PDF p.384 / 6-232; 06a Table 6-4; AppB Class I | exec_be :477 (0xBE18) | OBEYS | Unchanged. ACC−ACCB via `do_sub()`; C = !borrow. Same OV/OVM reading as 05c #22 (see §6, item 4): §6.3 lists only "Affects: C", but §4.4 ST0 describes OV/OVM as general ALU properties, so the list is read as abbreviated — no demotion. |
| 23 | SBBB | 06d §6.3, PDF p.385 / 6-233; 06a Table 6-4; AppB Class I | exec_be :478 (0xBE19) | OBEYS | Unchanged. ACC−ACCB−(~C) via `do_sub(acc, accb, !c, 0)`; C = !borrow. Same OV/OVM note as SBB. |
| 24 | SBRK #k | 06d §6.3, PDF p.386 / 6-234; 06a Table 6-5; AppB Class I, not repeatable | :377 (0x7C) | OBEYS | Unchanged code, **improved context**: current AR − 8-bit positive constant via circular-buffer-aware `upd_ar()`; none affected. The new run-loop mirror (:592) now covers the 05c NDX cross-note when the current AR is AR0 (at default settings; disabled by `legacy&64` — §3). Non-repeatability is a run-loop property (finding #7). |
| 25–32 | SETC C / CNF / HM / INTM / OVM / SXM / TC / XF | 06d §6.3, PDF pp.387–388 / 6-235–6-236; 06a Table 6-10; AppB Class I | exec_be :495–502 (0xBE4F / 0xBE45 / 0xBE49 / 0xBE41 / 0xBE43 / 0xBE47 / 0xBE4B / 0xBE4D) | OBEYS (all 8) | Unchanged. All eight opcodes match §6.3 exactly; each sets only its bit; 1 word. Note (unchanged, per 05c §0 convention — not demoting): the CLRC/SETC-INTM next-instruction interrupt shadow (§4.8.9, 04, PDF p.123 / 4-44) is still absent — `check_int()` :598 runs after every `exec1()` (finding #25 / new N-14 in 05; worker 4's area for the interrupt side). |
| 33 | SFL | 06d §6.3, PDF p.389 / 6-237; 06a Table 6-4; AppB Class I | exec_be :465 (0xBE09) | OBEYS | Unchanged. ACC(31)→C, 0→ACC(0); SXM correctly ignored. |
| 34 | SFLB | 06d §6.3, PDF p.390 / 6-238; 06a Table 6-4; AppB Class I | exec_be :475 (0xBE16) | OBEYS | Unchanged. 64-bit shift left exactly as printed. |
| 35 | SFR | 06d §6.3, PDF p.391 / 6-239; 06a Table 6-4; AppB Class I | exec_be :466 (0xBE0A) | OBEYS | Unchanged. SXM arithmetic/logical shift; ACC(0)→C; exact. |
| 36 | SFRB | 06d §6.3, PDF pp.393–394 / 6-241–6-242; 06a Table 6-4; AppB Class I | exec_be :476 (0xBE17) | OBEYS | Unchanged. 64-bit shift right with SXM fill exactly per the Execution block (the Description's two "the SFR instruction" sentences are the manual's copy error, 06d note 5; the Execution block is normative). |
| 37 | SMMR dma,#addr | 06d §6.3, PDF pp.395–396 / 6-243–6-244; 06a Table 6-9; AppB Class XXIV | :310–311 (0x09) | PARTIAL | Unchanged semantics. Direction and addressing right: MMR value at lower 7 bits of dma → data memory at #addr; #addr (`pfc`) increments per repeat; 9 MSBs of dma cleared (`a & 0x7f`); 2 words. The printed Execution block (PFC/MCS/lk) contradicts its own Description and SMMR's syntax; per 06d the Description is normative and the core correctly implements it (05 §6 item 3). Two defects (unchanged): (a) `ea()` re-evaluated on every repeat iteration, so indirect `*+` walks the MMR source address (finding #14); (b) `while (c->rptc > -1)` with `rptc = −1` after reset executes zero times as the first instruction after reset (finding #2). Cycle behaviour worsened in `cyc_model` mode: see §2 / N-11 (§4) — single counts 3 vs manual 2, RPT counts n+2 vs manual 2n (DARAM). |
| 38 | SPAC | 06d §6.3, PDF p.398 / 6-246; 06a Table 6-7; AppB Class I | exec_be :464 (0xBE05) | OBEYS | Unchanged. ACC − shifted PREG via `do_sub()` + `pscale()` (all four PM modes); C/OV set; SXM correctly unused. |
| 39 | SPH dma | 06d §6.3, PDF p.399 / 6-247; 06a Table 6-7; AppB Class IVA | :389 (0x8D) | OBEYS | Unchanged. High 16 of PM-scaled PREG stored; PM modes correct (incl. >>6 sign extension via arithmetic `pscale()`). |
| 40 | SPL dma | 06d §6.3, PDF p.401 / 6-249; 06a Table 6-7; AppB Class IVA | :388 (0x8C) | OBEYS | Unchanged. Low 16 of PM-scaled PREG stored. |
| 41 | SPLK #lk,dma | 06d §6.3, PDF p.403 / 6-251; 06a Table 6-6; AppB Class VIIb, not repeatable | :425 (0xAE) | OBEYS | Unchanged. Word 1 1010 1110 I + dma, word 2 lk → dma; ACC unaffected; none affected. Non-repeatability is a run-loop property (finding #7). |
| 42 | SPM constant | 06d §6.3, PDF p.404 / 6-252; 06a Table 6-7; AppB Class I, not repeatable | exec_bf :530 (0xBF00–0xBF03) | OBEYS | Unchanged. `pm = op & 3`; all four PM modes implemented in `pscale()`. Non-repeatability is a run-loop property (finding #7). |
| 43 | SQRA dma | 06d §6.3, PDF pp.405–406 / 6-253–6-254; 06a Table 6-7; AppB Class IIA | :334 (0x52) | OBEYS | Unchanged. ACC += OLD scaled PREG, dma→TREG0 via `set_t0()` (TRM=0 mirrors to TREG1/TREG2), PREG = dma² (signed 16×16); C/OV via `do_add()`. (TREG1 5-bit / TREG2 4-bit widths unmasked — finding #28, shared.) |
| 44 | SQRS dma | 06d §6.3, PDF pp.407–408 / 6-255–6-256; 06a Table 6-7; AppB Class IIA | :335 (0x53) | OBEYS | Unchanged. As SQRA with `do_sub()`; same TRM behaviour. |
| 45 | SST #0,dma | 06d §6.3, PDF pp.409–410 / 6-257–6-258; 06a Table 6-10; AppB Class IVA | :390 (0x8E) | OBEYS | Unchanged. Direct addressing forced to page 0 via `ea_p0()`; ST0 layout from `st0_get()` matches §4.4. Note (unchanged): which ARP value is stored when the indirect field carries a next-ARP bit is [UNVERIFIED] — no distilled passage settles it (05 §6). |
| 46 | SST #1,dma | 06d §6.3, PDF pp.409–410 / 6-257–6-258; 06a Table 6-10; AppB Class IVA | :391 (0x8F) | OBEYS | Unchanged. As SST #0 with ST1 (`st1_get()`, incl. hardwired-1 bits). Same [UNVERIFIED] next-ARP note. |
| 47 | SUB dma[,shift] | 06d §6.3, PDF pp.411–413 / 6-259–6-261; 06a Table 6-4; AppB Class IIA | :326–327 (0x30–0x3F) | OBEYS | Unchanged. ACC − `ext(dma, SHFT)`; `ext()` honours SXM; shift 0–15; C/OV via `do_sub()`; OVM saturation per §6.3. |
| 48 | SUB dma,16 | 06d §6.3, PDF pp.411–413 / 6-259–6-261; 06a Table 6-4; AppB Class IIA | :354 (0x65) | OBEYS | Unchanged. `do_sub(acc, dma<<16, 0, s16=1)` implements exactly the manual's special C rule: C cleared only if the subtraction generates a borrow, otherwise unaffected. |
| 49 | SUB #k | 06d §6.3, PDF pp.411–413 / 6-259–6-261; 06a Table 6-4; AppB Class I, not repeatable | :431 (0xBA) | OBEYS | Unchanged. ACC − 8-bit positive k; SXM correctly unused; C/OV via `do_sub()`. Non-repeatability is a run-loop property (finding #7). |
| 50 | SUB #lk[,shift] | 06d §6.3, PDF pp.411–413 / 6-259–6-261; 06a Table 6-4; AppB Class III | exec_bf :545 (0xBFA0–0xBFAF, hi=0xA0) | OBEYS | Unchanged. Word 1 1011 1111 1010 SHFT, word 2 lk; ACC − `ext(lk, SHFT)` with SXM sign extension; lk range −32768..32767 via `(int16_t)` in `ext()`. |
| 51 | SUBB dma | 06d §6.3, PDF pp.415–416 / 6-263–6-264; 06a Table 6-4; AppB Class IIA | :353 (0x64) | OBEYS | Unchanged. ACC − dma − (~C) via `do_sub(acc, dm, !c, 0)`; raw 16-bit operand (sign extension suppressed); C/OV set. |
| 52 | SUBC dma | 06d §6.3, PDF pp.417–418 / 6-265–6-266; 06a Table 6-4; AppB Class IIA | :312–313 (0x0A) | PARTIAL | Unchanged. The conditional-subtract formula is exact (`t = ACC − (dma<<15)`; `t ≥ 0 ? (t<<1)+1 : ACC<<1`; no OVM saturation). Defect (unchanged): the core never updates C or OV. §6.3 says "Affects: C and OV" and the Description states the C rule explicitly ("The C bit is cleared, if the result of the subtraction generates a borrow; otherwise, the C bit is set"). Finding #24, still present. Severity LOW (05c): the division result is carried in ACC itself; no SUBC consumer reads C/OV. |
| 53 | SUBS dma | 06d §6.3, PDF pp.419–420 / 6-267–6-268; 06a Table 6-4; AppB Class IIA | :355 (0x66) | OBEYS | Unchanged. Full 32-bit ACC − dma, unsigned operand, SXM suppressed; C/OV via `do_sub()`. |
| 54 | SUBT dma | 06d §6.3, PDF pp.421–422 / 6-269–6-270; 06a Table 6-4; AppB Class IIA | :356 (0x67) | OBEYS | Unchanged. ACC − `ext(dma, TREG1(3–0))`; SXM-controlled sign extension. |
| 55 | TBLR dma | 06d §6.3, PDF pp.423–425 / 6-271–6-273; 06a Table 6-9; AppB Class XVII | :408–409 (0xA6) | PARTIAL | Unchanged semantics. PFC←ACCL (local, ACC unchanged — correct, PFC is internal), (pma)→dma per iteration, PFC+1, AR/ARP modified per iteration via `ea()` (the manual explicitly requires the AR modify step here, unlike SMMR). Defects: (a) `while (c->rptc > -1)` executes zero times as the first instruction after reset (finding #2; RPTC reset value 0 per §4.9 Table 4–15, 04, PDF p.125 / 4-46; audit-verification #2). (b) Cycle count: in default mode still words+1 (single 2 vs manual 3; RPT n+1 vs manual n+2 — N-11, still present); in `cyc_model` mode the count becomes n+3 / 4 — still off by one, opposite direction for RPT (see §2, N-C2-1). |
| 56 | TBLW dma | 06d §6.3, PDF pp.426–428 / 6-274–6-276; 06a Table 6-9; AppB Class XVIII | :410–411 (0xA7) | PARTIAL | Unchanged semantics. As TBLR, data→program, ACC unchanged. Same two defects as TBLR (zero-times-after-reset; cycle off-by-one — §2, N-C2-1). BMAR is correctly NOT touched. |
| 57 | TRAP | 06d §6.3, PDF p.429 / 6-277; 06a Table 6-8; AppB Class X | exec_be :503 (0xBE51) | OBEYS | Unchanged. Push PC+1 (pc already advanced past the 1-word opcode), PC←0x22; INTM untouched; no context save; not maskable; not repeatable. The IPTR-remap open point is [UNVERIFIED], not a violation (05 §2 #27 split — workers disagree; §6.3 gives absolute 22h, §8.2.2 (08, PDF pp.478–479 / 8-11–8-12) states the general IPTR rule). |
| 58 | XC 1,cond | 06d §6.3, PDF pp.430–431 / 6-278–6-279; 06a Table 6-8; AppB Class I, not repeatable | :438–439 (0xE4–0xE7) | PARTIAL | Textually unchanged except a comment. Opcode (1110 01TP…, N=0) and `n = ((op>>12)&1)+1` = 1 correct; condition evaluation via `cond()` correct (see caveat at end of §1). Defects (all unchanged): (a) on a false condition the core does `pc += n` — it skips n WORDS, not n INSTRUCTIONS: a false XC 1 before a 2-word instruction skips 1 word and executes its immediate word as an instruction (finding #18 — §4). The new comment on :438 ("XC n counts instruction WORDS (manual: n=2 = one 2-word or two 1-word instructions)") concedes the n=2 reading while leaving the n=1 word-skip in place — it rationalises rather than fixes. §6.3: "If n = 1 … the 1-word instruction following the XC executes"; §4.5.6 (04, PDF pp.99–100 / 4-20–4-21): "XC 1 (conditionally execute a 1-word instruction)". (b) OV-clear on a taken XC when OV is in the mask (N-12). (c) Condition sampling one full cycle before XC is unmodelled — the core samples flags at execution, so a preceding single-cycle flag-changing instruction affects XC on hardware it must not (§4.5.6 stability rule; finding #18 parenthetical). (d) The XC + following-two-words uninterruptible window (§6.3) is not enforced — `check_int()` :598 can trap between XC and its target (N-13). |
| 59 | XC 2,cond | 06d §6.3, PDF pp.430–431 / 6-278–6-279; 06a Table 6-8; AppB Class I, not repeatable | :438–439 (0xF4–0xF7) | PARTIAL | Unchanged. Opcode (1111 01TP…, N=1) and skip count correct: n=2 words covers both sub-cases (one 2-word instruction, or two 1-word instructions). Bit-12 polarity (N=1 ↔ n=2) confirmed directly from §6.3's "n = 1 → N = 0; n = 2 → N = 1". Defects (b), (c), (d) as XC 1, minus the word/instruction skip: OV-clear (N-12), 1-cycle-early sampling (§4.5.6), uninterruptible window (N-13). |
| 60 | XOR dma | 06d §6.3, PDF pp.432–433 / 6-280–6-281; 06a Table 6-4; AppB Class IIA | :361 (0x6C) | OBEYS | Unchanged. ACCL XOR dma → ACCL; ACCH unaffected (`acc ^= (uint32)dm_rd`, 16-bit operand). |
| 61 | XOR #lk[,shift] | 06d §6.3, PDF pp.432–433 / 6-280–6-281; 06a Table 6-4; AppB Class III | exec_bf :548 (0xBFD0–0xBFD F, hi=0xD0) | OBEYS | Unchanged. Word 1 1011 1111 1101 SHFT, word 2 lk; ACC XOR (lk × 2^shift), zero-extended both ends; SXM correctly unused; C untouched. |
| 62 | XOR #lk,16 | 06d §6.3, PDF pp.432–433 / 6-280–6-281; 06a Table 6-4; AppB Class III | exec_be :512 (0xBE83) | OBEYS | Unchanged. Word 1 BE83, word 2 lk; ACC XOR (lk << 16). |
| 63 | XORB | 06d §6.3, PDF p.435 / 6-283; 06a Table 6-4; AppB Class I | exec_be :479 (0xBE1A) | OBEYS | Unchanged. ACC XOR ACCB → ACC; ACCB unaffected; none affected. |
| 64 | XPL [#lk,]dma (DBMR) | 06d §6.3, PDF pp.436–438 / 6-284–6-286; 06a Table 6-6; AppB Class V | :341 (0x58) | OBEYS | Unchanged. (dma) XOR DBMR → dma; TC = (result == 0); ACC unaffected; 1 word. Cycle note only: SARAM RPT `2n−2` vs DARAM `n` cannot both come out of a per-opcode table (§2). |
| 65 | XPL #lk,dma | 06d §6.3, PDF pp.436–438 / 6-284–6-286; 06a Table 6-6; AppB Class VI | :345 (0x5C) | OBEYS | Unchanged. (dma) XOR lk → dma; TC = (result == 0); 2 words; repeatable per its §6.3 RPT table. |
| 66 | ZALR dma | 06d §6.3, PDF pp.439–440 / 6-287–6-288; 06a Table 6-4; AppB Class IIA | :357 (0x68) | OBEYS | Unchanged. `(dma << 16) \| 0x8000` — dma→ACCH, ACCL = 8000h (rounding); C untouched. |
| 67 | ZAP | 06d §6.3, PDF p.441 / 6-289; 06a Table 6-4; AppB Class I | exec_be :506 (0xBE59) | OBEYS | Unchanged. 0→ACC, 0→PREG; none affected. |
| 68 | ZPR | 06d §6.3, PDF p.442 / 6-290; 06a Table 6-7; AppB Class I | exec_be :505 (0xBE58) | OBEYS | Unchanged. 0→PREG; none affected. |

### Condition-decoding caveat (applies to RETC, RETCD, XC — not a verdict)

`cond()` was already verified correct by the audit and I found no reason to
overturn that: TP matches Table 6-1 (06a §6.1.1: 00=BIO low, 01=TC=1, 10=TC=0,
11=None); V/C mask handling and the AND-of-all-tested-conditions rule match
§4.5.4 (04, PDF p.97 / 4-18). The ZLVC value-field rule itself remains
[UNVERIFIED] from the distilled text alone (Table 6-1's worked example
contradicts its own bit definition — 06a flag #6), as in 05c. No form is demoted
on this ground.

### Counts (§1)

| Verdict | Count | Forms |
|---|---|---|
| OBEYS | 58 | ROL, ROLB, ROR, RORB, RPT dma, RPT #k, RPT #lk, RPTZ, SACB, SACH, SACL, SAMM, SAR, SATH, SATL, SBB, SBBB, SBRK, SETC ×8, SFL, SFLB, SFR, SFRB, SPAC, SPH, SPL, SPLK, SPM, SQRA, SQRS, SST #0, SST #1, SUB dma, SUB dma,16, SUB #k, SUB #lk, SUBB, SUBS, SUBT, TRAP, XOR dma, XOR #lk, XOR #lk,16, XORB, XPL dbmr, XPL #lk, ZALR, ZAP, ZPR, **RETE, RETI** (both promoted from PARTIAL) |
| VIOLATES | 0 | — |
| PARTIAL | 10 | RETC, RETCD, RETD, RPTB, SMMR, SUBC, TBLR, TBLW, XC 1, XC 2 |
| UNVERIFIED (whole-form) | 0 | — |
| **Total** | **68** | |

Change vs 05c (old core: 56 obey / 0 violates / 12 partial): +2 OBEYS (RETI, RETE),
−2 PARTIAL. Both promotions are the `legacy&32` gating of the #9 shadow restore,
effective at the default `legacy=0`. No form regressed; no form changed verdict
in the other direction.

## 2. Cycle model — the new `cyc_model` / `cyc_tab` (code reading only)

### 2.1 What exists in the new core

- `#include "c5x_cyctab.h"` (:10) and use sites: `cyc_tab[c->op]` (:585),
  `c5x_set_cycle_model()` (:612), field `cyc_model` (:36, default 0 via `calloc`).
- `fetch()` (:260) now counts words (`c->words++`); `c5x_run()` resets `c->words = 0`
  per top-level instruction (:583) and computes `seq` (:586) to detect a
  fall-through PC.
- `delay_slot()` (:262–268) snapshots `cy0 = c->cycles` and `op0 = c->op` on entry,
  restores `c->op = op0` on exit, and — only when `cyc_model` is set — restores
  `c->cycles = cy0`, i.e. the two delay-slot words execute inside the delayed
  branch's own cycle count (comment :267).
- `c5x_run()` adjustment (:584–590), executed once per top-level `exec1()`:
  `cy = rep_cont ? 1 : cyc_tab[c->op]`; taken-branch override to 4 for BANZ (0x7B),
  BCND (0xE0–0xE3), CC (0xE8–0xEB), RETC (0xEC–0xEF) when `!seq`; not-taken
  override to 2 for the same set plus RETCD (0xFC–0xFE, with 0xFF/RETD explicitly
  excluded) when `seq`; then `c->cycles += cy - 1` on top of the `cycles++` already
  done inside `exec1()`.
- `rep_cont` (:36, :595–596) is set when the run loop rewinds for an RPT repeat
  (`rptc > 0` and `ppc == rpt_end`); a repeated iteration then costs `cy = 1`
  (plus the `cycles++` in `exec1()` — total 1 per repeat, i.e. the `+= cy-1` adds 0).
- The timer tick loop (:597) runs `tick_timer()` once per counted cycle
  (`for k = c0; k < c->cycles`), so in `cyc_model` mode the timer advances per
  model cycle rather than per instruction — an improvement over the old core's
  once-per-instruction tick (finding #3's mechanism, though the time base itself
  is worker 5's area).

### 2.2 What cannot be verified — the header does not exist

`c5x_cyctab.h` exists NOWHERE under `~/workspace` (searched by the coordinator;
my own `find` under `~` also returns nothing). I therefore did **not** invent its
contents and **no cycle value in `cyc_tab` is verified here**. Consequences, stated
plainly:

- Whether `cyc_tab[op]` holds the §6.3/App. B fastest-case value (1 for Classes
  I/IIA/IVA/IVB/V, 2 for III/VI/VIIb/XI/XXIV/XXIX, 3 for XVII/XVIII, 4 for X) for
  every opcode is [UNVERIFIED]. Every "presumed" in §1/§2 below means "if the
  table holds the manual's fastest-case value".
- The table's shape is unknown: `cyc_tab[c->op]` indexes by the full 16-bit opcode
  (:585). If the header defines a 65536-entry table, the lookup is in range; if it
  defines a smaller table (e.g. 256 entries keyed on the high byte), the lookup
  reads out of bounds. This is an [UNVERIFIED] structural risk, not a confirmed bug
  — I cannot distinguish the two without the header.
- Build consequence (code reading, independently confirmed by worker 1, 06a):
  `#include` of a nonexistent header fails compilation unless the file is supplied
  on the include path — worker 1 measured gcc 13.3.0 fatal error at :10, exit 1,
  no `.so`, while the old core builds clean as control. The new core as delivered
  in `~/workspace/user/files/` does not build standalone.

### 2.3 Structure vs the manual (App. B Tables B-1/B-2; §6.3 cycle tables in 06a–06d)

What the structure gets right, assuming a correct table:

- Single-instruction fastest-case values are at least representable: one value per
  opcode covers the ROM/DARAM column of every §6.3 table (all S–Z forms: 1 except
  RPT #lk/RPTB/RPTZ/SPLK/SUB #lk/XOR #lk/SMMR at 2, TBLR/TBLW at 3, RETC/RETE/
  RETI/TRAP at 4, RETCD/RETD at 2).
- The taken/not-taken overrides (:588–589) match the normative §6.3 splits for the
  forms they cover: BANZ/BCND/CC taken 4 (App. B Class VIII, 4 cycles), not-taken 2
  (§6.3 False 2); RETC taken 4 / not-taken 2 (§6.3, 06d PDF p.355 / 6-203 — the
  normative side of the three-way RETC contradiction, 05 §6 item 1); RETCD
  not-taken 2 (§6.3 flat 2, 06d PDF p.357 / 6-205).
- The delay-slot restore (:267) is the correct shape for Class IX/XI delayed
  branches (2 cycles total including the slot words): RETCD/RETD/BD/BCNDD/CALLD/CCD
  all cost 2 in App. B. The `op0` restore (:266) is necessary and correct — without
  it the run-loop lookup would use the last delay-slot instruction's opcode.
- `rep_cont = 1` matches the manual's RPT per-iteration cost of 1 for the common
  DARAM case (e.g. §6.3 RPT tables: `n` for Class I/IIA/IVA forms).

What the structure cannot express (verified by reading the code — no wait-state,
address, or memory-type input exists anywhere in the :584–590 block):

- **Wait states: absent.** `pdwsr`/`iowsr`/`cwsr` are stored by `mmr_wr()` (:168)
  and read back by `mmr_rd()` (:147) but are never read by the cycle model (grep:
  only those two use sites in the file). The §6.3 tables are per memory
  configuration with `p` (program), `d` (data) and `io` wait-state terms (06d
  header note: "`p` = program memory wait states; `d` = data memory wait states;
  `io` = I/O wait states"); a single per-opcode value can only ever match the
  fastest (0-wait-state, on-chip) column. Every external-memory/SARAM-conflict
  cell is therefore wrong by construction, e.g. SACH external single `2+d`, SAMM
  MMPORT `2+io`, SMMR external `3+d`, TBLR external `4+d`/`6+d+p`.
- **SARAM same-block extra cycles: absent.** No comparison of code/data addresses
  against SARAM ranges exists in the model. §6.3 gives e.g. SACH/SACL/SAR/SPH/SPL/
  SST SARAM single `1, 2†` († = operand and code in the same SARAM block), SUB/
  SQRA SARAM RPT `n, n+1†`, TBLR/TBLW SARAM `3, 4†` / RPT `n+2, 2n‡`. The model
  can only return one of the two values.
- **DMOV/SARAM extra cycle: absent.** No DMOV-specific handling and no address-based
  adjustment (DMOV itself is worker 1's form; the structural point stands for the
  model: §8.7.1, 08, PDF pp.493–494 / 8-26–8-27, requires an additional cycle for
  DMOV in single-access RAM — finding N-8 in 05 — and the model has no input that
  could produce it).
- **Per-iteration costs ≠ 1 under RPT: flattened.** `rep_cont` forces `cy = 1` for
  every repeated instruction, but the manual gives e.g. XPL (DBMR) SARAM RPT `2n−2`,
  XPL #lk SARAM RPT `2n−1`, SACH/SACL external RPT `2n+nd`, SUB SARAM same-block
  RPT `n+1`. The model is right only for the DARAM `n` case.
- **Block-move / multi-word-consumption double count: wrong by construction**
  (new finding N-C2-1, §5). The `while`/`do-while` loops inside `exec1()` still do
  `cycles++` per moved word (SMMR :311, TBLR :409, TBLW :411 — unchanged from the
  old core), and the run-loop block then adds `cy − 1` on top. Measured arithmetic
  (assuming the table holds the manual single-instruction value):
  - SMMR single: `exec1` gives 1 + 1 = 2, model adds 2−1 = 1 → **3 vs manual 2**
    (06d §6.3 SMMR, DARAM; App. B Class XXIV, 2). RPT #n (n+1 executions):
    1 + (n+1) + 1 = n+3 vs manual 2(n+1) — over by 1 at n=0, under by n−1 for n≥2.
  - TBLR single: 1 + 1 + (3−1) = **4 vs manual 3** (06d §6.3; App. B Class XVII, 3).
    RPT: 1 + (n+1) + 2 = n+4 vs manual (n+1)+2 = n+3 — over by 1 in both cases.
    Same for TBLW (Class XVIII, 3; RPT n+2).
  - The same double count applies out of range to BLDP/BLPD/BLDD/MAC/MACD/MADD/MADS
    (their loops also `cycles++` per iteration — :340, :405, :417–420, :422, :424 —
    for the merger's benefit).
  The old core's N-11 ("uniformly words+1") is therefore not fixed by the model;
  it changes shape (see §4, N-11 verdict).
- **Taken/not-taken overrides are incomplete and address-blind** (new finding
  N-C2-3, §5): B (0x79), CALL (0x7A), BACC/CALA (BE20/BE30), BACCD/CALAD
  (BE21/BE3D) are not in the taken-4 list (:588) and rely entirely on the
  unverifiable table; and the `seq` test misclassifies a taken branch whose target
  happens to equal the fall-through address (e.g. RETC returning to `ppc+1`, BANZ
  taken to `ppc+2`) as not-taken (cy = 2 instead of 4).
- **Interrupt entry still costs 0 cycles, including in `cyc_model` mode.**
  `check_int()` (:283–289) adds nothing to `cycles`, and the :584–590 adjustment
  applies to the interrupted instruction, not to the trap. Floor from this pass's
  chapters is 4 cycles (§7.2.2 flush, 07, PDF p.448 / 7-6; App. B Class X, INTR 4)
  — finding N-9, still present (§4). INTR-as-instruction (4 cycles, Class X) would
  come from the table, if correct; the asynchronous trap entry does not.
- **Idle is outside the model.** The idle loop (:570–573) steps `cycles++` 1 per
  tick regardless of `cyc_model`; IDLE/IDLE2 wake timing is unchanged.

### 2.4 Verdict on the cycle model

Finding #5 (cycle model is an instruction count) — **PARTIALLY FIXED**, with the
qualification that the fix is opt-in and unverifiable as delivered:

- At the default `cyc_model=0`, the core is byte-for-byte the old instruction
  counter (`exec1()` :305 `cycles++` once per call; block-move loops add one per
  word). The finding as stated is **still present by default**.
- With `cyc_model=1`, the structure exists (per-opcode table + taken/not-taken
  branch overrides + repeat-iteration cost 1 + delay-slot restore) and its shape
  matches the manual's fastest-case column for the common 1-cycle forms and for
  RETC/RETCD. But no table value can be verified (header absent), wait states and
  SARAM-conflict extras are structurally absent, block moves double-count, RPT
  per-iteration costs ≠ 1 are flattened, and interrupt entry still costs 0.
  This is a fastest-case-only model, not the manual's per-configuration model
  (App. B intro, PDF p.638 / B-1: cycles "in a given memory configuration").

## 3. Legacy-bit behaviour (default `legacy=0` vs the legacy bit)

`c5x_set_legacy()` :613 documents: "bit0 NORM(acc=0), bit2 unsigned CRGT/CRLT,
bit3 TIM reset 0 (bit1 unused: XC audit finding was wrong)". The full bit set as
implemented: bit0 (1) NORM, bit2 (4) CRGT/CRLT unsigned, bit3 (8) TIM reset 0,
bit4 (16) MADD/MADS TRM mirror, bit5 (32) INTM/XF shadow restore, bit6 (64) NDX
mirror off, bit7 (128) BMAR write-back. Only bits 32 and 64 touch S–Z forms;
the rest are listed for completeness / merger cross-reference.

| Legacy bit | Default (`legacy=0`) | With the bit set | S–Z forms affected |
|---|---|---|---|
| bit5 (32) — shadow INTM/XF | `restore_ctx()` :278 does NOT restore INTM or XF: RETI leaves INTM as the ISR left it (§6.3 RETI "Does not affect: INTM"); RETE forces INTM=0 and leaves XF as the ISR left it. Manual-correct per §4.8.8 (04, PDF p.121 / 4-42). | Old (wrong) behaviour restored: RETI restores both INTM (=1 always, since `check_int()` :287 sets `intm=1` before `save_ctx()`) and XF; RETE restores XF (INTM still ends 0 via the explicit assignment :492). RETI/RETE revert to PARTIAL. | RETI (:491), RETE (:492). No other S–Z form calls `restore_ctx()`. |
| bit6 (64) — NDX mirror off | Run-loop mirror :592 active when `!ndx`: any AR0 change during an `exec1()` also loads INDX and ARCR (§5.2.1, 05, PDF p.136 / 5-6; audit-verification #8). | Mirror disabled: SAR/SBRK/every indirect form revert to the old core's missing-mirror behaviour (finding #10, as in 05c). SAR/SBRK stay OBEYS on their own semantics (the mirror was a cross-cutting note, not a demotion), but the #10 fix is lost. | SAR (:381–382), SBRK (:377), and every indirect-addressed S–Z form via `ea()` (all `dma` forms) — as a cross-cutting effect, not a per-form verdict change. |
| bit0 (1) NORM | — | — | None in S–Z (NORM is worker 2's I–R range). |
| bit2 (4) CRGT/CRLT | — | — | None in S–Z (CRGT/CRLT are worker 2's E–H range). |
| bit3 (8) TIM reset 0 | `c5x_reset()` :84: TIM = 0xFFFF (manual-correct per §4.9 Table 4–15, audit-verification #4). | TIM = 0 (old wrong value). | None in S–Z directly (timer is worker 5's area); noted because it is the only other legacy bit the task named. |
| bit4 (16) MADD/MADS TRM mirror | `treg0 = d` only (:417), no TRM mirror — manual-correct per §6.3 MADD/MADS ("Affected by: OVM and PM" only; 05 §3 N-1 fixed). | `set_t0()` mirrors to TREG1/TREG2 when `!trm` (old bug). | None in S–Z (MADD/MADS are worker 2's I–R range). |
| bit7 (128) BMAR write-back | Block moves do NOT write BMAR back (BLDP :340, BLPD :405, MADD/MADS :420, BLDD :422/:424 — all `if (c->legacy & 128)`). Manual-correct per §6.3 (no BMAR assignment; finding #15 fixed). | Old (wrong) write-back restored. | None in S–Z (TBLR/TBLW never touched BMAR; no S–Z block move uses BMAR). |

Note on `save_ctx()` (:269–273): it still unconditionally stores INTM and XF into
the shadow struct. At `legacy=0` those stored values are never read back, so the
store is harmless dead state; under `legacy&32` it is the mechanism of the old bug.

## 4. Verdicts on prior findings (new core)

Verdicts: FIXED / STILL PRESENT / PARTIALLY FIXED / REGRESSED, at default
`legacy=0`, `cyc_model=0` unless stated. Citations are distilled-manual citations.

| # | Prior finding | Verdict (new core) | Evidence |
|---|---|---|---|
| 5 | Cycle model is an instruction count | **PARTIALLY FIXED** | §2.4. Default `cyc_model=0`: identical instruction counter — still present by default. `cyc_model=1`: table + overrides + delay-slot restore exist, fastest-case shape is right for 1-cycle forms and RETC/RETCD, but no table value is verifiable (header absent), wait states / SARAM extras / DMOV extra cycle are structurally absent, block moves double-count (N-C2-1), RPT per-iteration ≠ 1 flattened, interrupt entry still 0 cycles. |
| 8 | RPTB PAER off by one (value wrong, count right) | **STILL PRESENT** | :515 `paer = imm + 1` unchanged; §6.3 RPTB Execution "pma → PAER" (06d, PDF pp.369–370 / 6-217–6-218); §4.7 (04, PDF p.110 / 4-31). Representation note stands exactly as in audit-verification §3: iteration count (BRCR+1) is right via the before-fetch check (:575–578), but the externally visible PAER register reads one high — e.g. a guest reading PAER via SMMR observes pma+1, and an MMR-loaded PAER = pma (the manual's own nested save/restore pattern, §4.7 Ex. 4–9, 04, PDF p.111 / 4-32) makes the run-loop wrap test fire before the last instruction executes, skipping it every iteration. No legacy bit touches this. |
| 18 | XC k=1 skips opcode words | **STILL PRESENT** | :438–439 `c->pc += n` unchanged (comment added only — §1 #58). §6.3 XC (06d, PDF pp.430–431 / 6-278–6-279): "If n = 1 … the 1-word instruction following the XC executes"; §4.5.6 (04, PDF pp.99–100 / 4-20–4-21). The 1-cycle-early condition-sampling half is also still absent (`cond()` evaluated at execution). The `c5x_set_legacy()` comment :613 says "bit1 unused: XC audit finding was wrong" — the bit-1 question in the old audit (whether a legacy bit should preserve the word-skip) is moot: there is no legacy bit for XC, and the word-skip itself is unchanged. No regression, no fix. |
| 20 | IDLE/IDLE2 conflated (the single VIOLATES form in 05) | **STILL PRESENT** | exec_be :487 (IDLE, 0xBE22) and :488 (IDLE2, 0xBE23) are both bare `c->idle = 1`, and the idle loop (:570–573) treats them identically. §6.3 IDLE (06b, PDF p.259 / 6-107) vs IDLE2 (06b, PDF p.260 / 6-108): IDLE keeps timer and serial port peripherals active; IDLE2 removes the functional clock, so timer and serial are NOT active, and is exited by an external interrupt (INT1–INT4), RS, or NMI of at least five machine cycles duration. None of that is modelled — no clock-removal state, no peripheral gating in idle, no 5-cycle duration test, no INTM=1-without-ISR-exit distinction (the run loop always calls `check_int()`, which requires `!intm` at :285). This form is in worker 2's E–H range; verdict­ed here only because the task names #20, and **not** counted in my 68-form totals (§1). |
| 26 | Delay-slot stack ordering | **STILL PRESENT** | RETCD/RETD :448–449 still `pop()` before `delay_slot()`; CCD :446–447 and CALLD (out of range, :379) still `push()` before `delay_slot()`. Push/pop values are correct; only a delay-slot instruction that itself pushes/pops sees the wrong stack level (05 §2 #26, "CONFIRMED as a caveat"). The new `delay_slot()` op/cycle restore (:266–267) does not touch the stack. `in_delay` (:264–266) is still set but read nowhere — still a dead flag. |
| 31 | Block-repeat last-words lockout; CALA/CALL last-insn push; BRCR 0xFFFF | **STILL PRESENT** (lockout + BRCR sub-points; CALA/CALL sub-point unchanged as narrowed) | Lockout: `check_int()` :598 runs after every `exec1()` with no block-repeat guard; §4.7.2 (04, PDF pp.113–114 / 4-34–4-35): "the single-word instruction at the end of a repeat block is not interruptible" (except after a single-word multiple-cycle instruction). No new guard exists. BRCR: :577 `c->brcr--` unconditional at wrap; §4.7 loop-end test (04, PDF p.110 / 4-31) decrements BRCR only when BRCR > 0, so BRCR must read 0 after completion — the core still reads 0xFFFF via MMR 0x09 (:139). CALA/CALL-as-last-instruction: out of range (A–D); the 05 narrowing stands — Ex. 4–10 (§4.7.1, 04, PDF pp.112–113 / 4-33–4-34) gives the top-of-loop return by construction, and the core's before-fetch wrap (:575–578) already produces it; unchanged. |
| N-11 | Block-move cycle counts uniformly words+1 | **STILL PRESENT** | Default mode: SMMR :310–311, TBLR :408–409, TBLW :410–411 still `cycles++` per moved word inside `exec1()`'s single `cycles++` — single 2 vs manual 3 (TBLR/TBLW, 06d §6.3; App. B XVII/XVIII) and RPT n+1 vs manual n+2; SMMR single 2 (accidentally right in default mode) but RPT n+1 vs manual 2n (DARAM). `cyc_model` mode: still wrong, different numbers — §2.3 / N-C2-1 (TBLR single 4, RPT n+4 vs n+3; SMMR single 3 vs 2). The 05 correction to #5's sub-claim ("BLDD-BMAR RPT n+1 matches" is wrong) is unaffected. |
| N-12 | OV-clear over-extended to RETC/RETCD/XC | **STILL PRESENT** | `if (op & 2) c->ov = 0` unchanged on all three paths: XC :438–439, RETC :442–443, RETCD :448–449. §6.3 RETC (06d, PDF p.355 / 6-203), RETCD (p.357 / 6-205), XC (pp.430–431 / 6-278–6-279) all say "Status bits: None affected"; §4.4 ST0 bit 12 (04, PDF p.89 / 4-10) names only BCND/BCNDD for OV-clear. Normative: §6.3 (05 §6 item 4). Hardware/MAME cross-check caveat preserved from 05c. |
| N-13 | XC + following-two-words interrupt window | **STILL PRESENT** | No window state exists: `check_int()` :598 is called after every `exec1()`, including immediately after an XC (:438–439). §6.3 XC (06d, PDF pp.430–431 / 6-278–6-279): "The XC instruction and the two instruction words following the XC are uninterruptible." |
| N-9 | Interrupt entry costs 0 cycles (my half; interrupt worker also covers it) | **STILL PRESENT** | `check_int()` :283–289 sets PC/pushes/clears IFR/saves context with no `cycles` addition, in both `cyc_model` modes (§2.3). Floor 4 cycles (§7.2.2, 07, PDF p.448 / 7-6; App. B Class X). Cross-reference: worker 4 (interrupts) covers the trap-entry side; this is the S–Z/cycle-model half. RETI/RETE shadow behaviour as part of #9's interaction: at `legacy=0` the RETI/RETE restore is now manual-correct (§1 #4–5), so the #9 defect no longer bites through RETI/RETE — but the 0-cycle entry half is untouched. |

Also relevant to §1, for the merger: finding #9 itself (INTM/XF wrongly shadowed)
is **FIXED at default `legacy=0`** via the :278 gating (RETI/RETE §1 #4–5), and
**STILL PRESENT under `legacy&32`** by design. Finding #10 (NDX=0 mirror) is
**PARTIALLY FIXED** for S–Z: the run-loop mirror :592 covers AR0 changes made
during any `exec1()` at default settings, but misses same-value reloads and
changes made outside `exec1()` (see N-C2-7). Finding #2 (RPTC reset −1) is
**STILL PRESENT** (:83 `rptc = -1`; §4.9 Table 4–15, 04, PDF p.125 / 4-46: RPTC
→ 0) — it still demotes SMMR/TBLR/TBLW (§1 #37, #55, #56). Finding #7 (RPT
repeats non-repeatables) is **STILL PRESENT** (:595–596, no whitelist). Finding
#14 (SMMR `ea()` re-evaluation) is **STILL PRESENT** (:310–311). Finding #24
(SUBC C/OV) is **STILL PRESENT** (:312–313).

## 5. New issues / regressions introduced by the diff (S–Z or cycle model)

Severity: MEDIUM = wrong results/state on plausible firmware; LOW = edge cases,
timing-only, or harness-visible only. Old-core behaviour + line cited for comparison
in each case.

### N-C2-1 — MEDIUM — `cyc_model` double-counts block-move words (SMMR/TBLR/TBLW)

- **New core:** `exec1()` loops still do `cycles++` per moved word (SMMR :311,
  TBLR :409, TBLW :411 — carried over from the old core, where they were the
  whole of the N-11 defect), and `c5x_run()` :584–590 then adds `cy − 1` on top.
- **Old core:** single TBLR counted 2 (1 + 1 loop increment); RPT counted n+1.
- **Manual:** TBLR/TBLW single 3, RPT n+2 (06d §6.3, PDF pp.423–428 / 6-271–6-276;
  App. B Classes XVII/XVIII, 3 cycles); SMMR single 2, RPT 2n (DARAM) (06d §6.3,
  PDF pp.395–396 / 6-243–6-244; App. B Class XXIV, 2).
- **New-core `cyc_model` counts** (table assumed correct; k = executions):
  TBLR/TBLW single 4, RPT k+3 vs manual k+2; SMMR single 3, RPT k+2 vs manual
  2k — i.e. SMMR RPT is over by 1 at k=1, exact at k=2, under by k−2 thereafter.
  So the model fixes nothing for block moves and moves the error: TBLR goes from
  −1 to +1 (single) and from −1 to +1 (RPT); SMMR goes from 0 to +1 (single) and
  its RPT error from under-by-(k−1) (default k+1 vs 2k) to under-by-(k−2)
  (model k+2 vs 2k). The same double
  count applies out of range to BLDP/BLPD/BLDD/MAC/MACD/MADD/MADS. Root cause: two
  counting schemes coexist — the per-word increments inside `exec1()` were never
  suppressed when the table model was added.
- **Default mode (`cyc_model=0`) is unaffected** — N-11 as before.

### N-C2-2 — LOW — `cyc_model` taken/not-taken override list is incomplete

- **New core:** :588 taken-4 list covers only BANZ (0x7B), BCND (0xE0–0xE3), CC
  (0xE8–0xEB), RETC (0xEC–0xEF). B (0x79), CALL (0x7A), BACC/CALA (BE20/BE30),
  BACCD/CALAD (BE21/BE3D) are absent and rely entirely on the unverifiable table.
- **Manual:** all are App. B Class VIII (B/BANZ/BCND/CALL/CC — 4 cycles) or Class X
  (BACC/CALA — 4 cycles) (appendix-b, Tables B-1/B-2). If the table holds 4 for
  them, the outcome is right; if any entry is wrong there is no override to catch
  it. In-range impact is nil for RETC/RETCD (covered); the gap bites the merger's
  A–D/E–H forms and is recorded here because the override is the model's only
  verified-correct part.
- **Old core:** no model at all (all 1) — so this is a gap in the new code, not a
  regression of a previously correct value.

### N-C2-3 — LOW — `seq`-based taken detection misclassifies taken-to-fall-through branches

- **New core:** :586 `seq = (pc == ppc + words)`; :588–589 assign cy = 4 only when
  `!seq`, cy = 2 when `seq` for the listed opcodes.
- **Manual:** a taken branch costs 4 regardless of its target (§6.3 BCND/CC/RETC
  True 4; App. B Class VIII/X, 4).
- **Failure case:** a taken RETC whose TOS equals `ppc+1` (return to the next
  instruction), or a taken BANZ/BCND/CC targeting exactly the fall-through address
  (`ppc+words`), is classified `seq` and charged 2 instead of 4. Degenerate but
  legal code (e.g. a conditional return at the end of a subroutine whose caller
  falls through, or a branch-to-next used as a 2-cycle NOP substitute — which is
  precisely when the distinction matters). Fix would be to record taken/not-taken
  in `exec1()` rather than inferring it from the resulting PC.

### N-C2-4 — LOW — `rep_cont` flattens all RPT per-iteration costs to 1

- **New core:** :585 `cy = rep_cont ? 1 : cyc_tab[c->op]`.
- **Manual:** most DARAM RPT tables give `n`, but SARAM same-block and external
  cases do not: XPL (DBMR) SARAM RPT `2n−2`, XPL #lk SARAM RPT `2n−1` (06d §6.3,
  PDF pp.436–438 / 6-284–6-286); SACH/SACL external RPT `2n+nd`; SUB/SQRA SARAM
  same-block RPT `n+1` (06d §6.3). The model returns 1 per iteration for all of
  them. This is the per-iteration half of the §2.3 structural limitation, recorded
  as its own finding because it is a distinct code decision (`rep_cont`), not a
  table-value question.
- **Old core:** every repeat cost 1 as well — no regression, still present.

### N-C2-5 — LOW — `cyc_tab[c->op]` full-opcode index vs unknown table shape [UNVERIFIED]

- **New core:** :585 indexes by the full 16-bit opcode. The header is absent, so
  the table's size and element type are unknown.
- **Risk (not a confirmed bug):** if the header defines fewer than 65536 entries
  (e.g. a 256-entry high-byte table), the lookup reads out of bounds for most
  opcodes. If it defines 65536 entries, the lookup is fine. Cannot be resolved
  without the header — recorded as [UNVERIFIED], not scored as a defect. The
  merger should not assume the table exists in either shape.

### N-C2-6 — LOW — `delay_slot()` cycle restore also wipes a slot block move's words (cyc_model only)

- **New core:** :267 `if (c->cyc_model) c->cycles = cy0` restores the cycle count to
  the value at delay-slot entry, discarding everything the slot instructions
  counted — including a block move in the slot, whose `while` loop may have moved
  many words (SMMR/TBLR/TBLW in a delay slot are legal: only the branch itself is
  non-repeatable, not the slot contents).
- **Manual:** a delayed branch costs 2 total (App. B Class IX/XI) *including* its
  slot words — but a block move in the slot is a multi-cycle instruction in its own
  right, and the manual gives no rule that its words execute "inside" the branch's
  2 cycles; the §6.3 delayed-branch entries say only "the two instruction words
  following [the branch] are fetched and executed before the return/branch". The
  core's blanket restore assumes the slot can never cost more than the branch.
  In practice a block move in a delay slot is pathological firmware, and the
  default mode is unaffected (no restore when `cyc_model=0`). Recorded as LOW /
  edge-case, not as a proven manual violation.

### N-C2-7 — LOW — NDX mirror misses same-value AR0 reloads and non-`exec1()` AR0 writes

- **New core:** :592 `if (!c->ndx && !(c->legacy & 64) && c->ar[0] != c->ar0_prev)`.
- **Manual:** §5.2.1 (05, PDF p.136 / 5-6): "every AR0 modification or LAR write
  also writes the ARCR and INDX with the same value" (NDX=0, the reset state).
- **Gaps:** (a) an AR0 write that leaves the value unchanged (e.g. LAR AR0 with the
  value AR0 already holds, after INDX/ARCR were changed independently via LMMR)
  does not trigger the mirror, because the test is on value change, not on the
  write; (b) AR0 changes made outside `exec1()` — via `c5x_set()` (S_AR0) or a
  direct MMR write through the harness — never pass the :592 test until the next
  instruction that happens to change AR0; (c) `ar0_prev` is only updated in
  `c5x_run()`, so a reset that changes AR0 without a run-loop pass leaves a stale
  comparison; (d) the mirror runs only in `c5x_run()` after a top-level `exec1()`
  returns, so an AR0 change made by a delay-slot instruction is not mirrored until
  the whole delayed branch completes (same mechanism as worker 4's 06d-N4). All three are narrow; the common LAR/SAR/SBRK/MAR paths through
  `exec1()` are covered. The old core had no mirror at all, so this is a partial
  fix with residual edges, not a regression.

### No other new S–Z regressions found

Checked and clean: the `ivec[]` correction (:281) does not change any S–Z form's
decode or semantics (it changes hardware interrupt entry vectors and the INTR
save gating — worker 4's area; the only S–Z interaction is that RETI/RETE now
restore a context saved from a correctly-vectored trap, which is the manual's
behaviour). The `xint_mode` change (serial tick) does not touch S–Z forms. The
watch/pc_hits harness additions do not touch semantics. No S–Z opcode, word count,
or status-bit effect changed except RETI/RETE (fixed at default) and the NDX
mirror (improvement).

## 6. Contradictions recorded (both ways, normative choice stated)

Carried over from 05c §6 (unchanged by the diff — the new core changes no
manual reading) plus one new item from the cycle model:

1. **RETC cycles — three-way.** §6.3 (06d, PDF p.355 / 6-203): True 4 / False 2.
   Table 6-8 (06a): flat 2. App. B Table B-2 (appendix-b, PDF p.644 / B-7):
   Class X, flat 4. Normative: §6.3 (most specific, True/False split). The new
   core's :588–589 override implements exactly the §6.3 split in `cyc_model` mode.
2. **RETCD cycles — two-way.** §6.3 (06d, PDF p.357 / 6-205): flat 2. Table 6-8
   (06a): "4¶ or 2#". App. B Table B-2: Class XI, 2. Normative: 2 (§6.3 + App. B
   agree; Table 6-8 is the outlier).
3. **SMMR Execution block vs its own Description.** §6.3 SMMR (06d, PDF p.395 /
   6-243) prints a PFC/MCS/lk block-move Execution block contradicting the
   Description (store MMR value to #addr) and SMMR's syntax. Normative: the
   Description (06d note 3); the core implements it.
4. **OV-clear: §6.3 "None affected" vs §4.4 ST0 table.** §6.3 BCND/BCNDD/CC/CCD/
   RETC/RETCD/XC pages all say "None affected"; §4.4 ST0 (04) says OV is cleared
   "by a conditional branch BCND/BCNDD on OV/NOV". Normative: §6.3 (opcode-level)
   — hence N-12 for RETC/RETCD/XC. The §4.4 sentence is the reason the BCND/BCNDD
   paths keep their OV-clear in the core pending a hardware check (out of range).
   Note the SBB/SBBB reading from 05c §1 #22–23 is kept: §6.3 lists only
   "Affects: C" for SBB/SBBB while `do_sub()` also sets OV and saturates under OVM;
   §4.4 ST0 describes OV/OVM as general ALU properties, so the §6.3 list is read
   as abbreviated, not as "OV unaffected" — no demotion. Contrast SUBC (#52),
   where §6.3 explicitly lists OV and the core sets neither.
5. **Table 6-1 ZLVC wording.** L defined as "ACC < 0", then the worked example says
   "when the L bit is set, it indicates to test for the condition ACC ≥ 0" (06a
   flag #6). No normative resolution is possible from the distilled text; the
   encoding rule is [UNVERIFIED] (§1 caveat).
6. **RPTB wrap timing vs §4.7 loop-end test.** §4.7 (04, PDF p.110 / 4-31): "with
   each PC update, PAER is compared to the PC. If equal, BRCR is compared to 0…"
   — read literally against PAER = pma (last word address) this is
   timing-ambiguous (PC after executing the last word is pma+1, not pma). The
   core's representation (paer = pma+1, check before fetch) yields the correct
   iteration count; only the observable PAER value is wrong (#8). No change to
   the #8 verdict.
7. **BRCR "decrements below 0" gloss vs §4.7 test.** PMST bit-0 gloss (04, §4.4):
   BRAF "cleared when BRCR decrements below 0". §4.7's loop-end test decrements
   BRCR only when BRCR > 0 and clears BRAF when BRCR = 0. Normative: §4.7's
   operative algorithm — BRCR reads 0 after completion (#31).
8. **NEW — App. B class cycles vs §6.3 RPT tables for repeated block moves.**
   App. B gives single-instruction classes only (TBLR XVII 3, SMMR XXIV 2); the
   RPT totals live in the §6.3 per-instruction tables (TBLR RPT n+2, SMMR RPT 2n).
   The new core's `cyc_tab` is indexed per opcode with no repeat-count input other
   than the `rep_cont` flag, so it cannot hold both the single and the RPT value
   for the same opcode — the two sources are consistent with each other, but the
   model's single-value-per-opcode shape cannot represent both. This is a
   structural fact about the model, not a manual contradiction.

## 7. Counts and limits

| | Count |
|---|---|
| §6.3 forms checked (S–Z) | 68 |
| OBEYS | 58 (was 56 in 05c; RETI + RETE promoted) |
| VIOLATES | 0 |
| PARTIAL | 10 (was 12 in 05c) |
| UNVERIFIED (whole-form) | 0 |
| Prior findings verdict­ed in §4 | #5 PARTIALLY FIXED; #8, #18, #20, #26, #31, N-11, N-12, N-13, N-9 STILL PRESENT (9); #9 FIXED at `legacy=0` / STILL PRESENT under `legacy&32` (noted in §4 text); #10 PARTIALLY FIXED (noted in §4 text) |
| New findings (§5) | 7 (N-C2-1 MEDIUM; N-C2-2..N-C2-7 LOW, incl. N-C2-5 [UNVERIFIED] risk, not a confirmed defect) |

### Limits / not re-verified here

- No execution tests were run (read-only comparison of core code against the
  distilled manual, per task). Empirical claims cited (XC word skip, SMMR `*+`
  walk, RPTB count) are the audit's, re-checked against the code paths, not
  re-executed here. The cycle-model arithmetic in §2/§5 is hand-computed from the
  code (counting `cycles++` sites and the :584–590 adjustment); it was not run.
- No `cyc_tab` value is verified: the header does not exist in `~/workspace`, and
  no value was invented. If the header is supplied later, every "presumed" in §1–§2
  must be re-checked against it, and the N-C2-1/N-C2-2 arithmetic re-measured.
- The build was not attempted by this worker (worker 1 owns the build verdict);
  the `#include "c5x_cyctab.h"` (:10) failure mode is stated from code reading.
- Out-of-range findings are not verdict­ed here except where the task names them
  (#20 IDLE2, #5, #31's CALA/CALL sub-point as narrowed in 05) or where a diff
  hunk interacts with S–Z (INTR `ivec[]` fix, NDX mirror, legacy bits).
- The June 1998 PDF was not needed as tiebreaker; every in-range claim was settled
  from the distilled files. The 1993 OCR text was not consulted.
