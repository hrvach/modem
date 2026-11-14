# Audit HIGH findings — verification against the June 1998 PDF (SPRU056D)

Verification of 10 audit findings against `~/workspace/user/files/spru056d.pdf`
(SPRU056D, June 1998, SHA-256 `a31e285f…`) **only** — not against the January 1993
OCR text (`c5x_users_guide.txt`) the audit largely worked from. Every verdict cites
1998 section + table + PDF page / printed page. Cross-refs to the distilled manual
(`c5x_manual/`) are pointers only; the PDF is the authority.

Verdict meanings: **CONFIRMED** — the 1998 PDF says it, as stated. **REFUTED** — the
1998 PDF says otherwise (or explicitly contradicts it). **NEEDS-1998-REMAP** — the
substance looks right but the audit's citation is to 1993 numbering/text and must be
re-mapped to 1998 numbering. Per-subclaim verdicts are given where a compound claim
splits.

Background: the audit's headline CALAD finding is already withdrawn (parent's
correction, 2026-11-14 20:18 CET): CALAD is `0xBE3D` in the 1998 PDF (§6.3, PDF p.236 /
printed 6-84; also Table 6-8), and the core's `case 0x3D` is correct. The audit's
"CALAD missing + BE3D phantom" is backwards. The same 1993-vs-1998 edition confusion
motivates this pass.

## Verdict table

| # | Audit finding (manual claim) | Verdict |
|---|---|---|
| 1 | Interrupt vectors TINT=08h, RINT=0Ah, XINT=0Ch, TRNT=0Eh, TXNT=10h, INT4=12h | **CONFIRMED** |
| 2 | RPTC reset value is 0 (core inits −1) | **CONFIRMED** |
| 3 | RPTB: PAER ← pma (not pma+1); iterations = BRCR+1; PASR = PC+2 | **CONFIRMED** (with a core-representation note, see §3) |
| 4 | Timer: TIM reset 0xFFFF; prescaler/reload behaviour as stated | **CONFIRMED** |
| 5 | Serial: XINT fires only on DXR→XSR XRDY 0→1 transition | **CONFIRMED** |
| 6 | INTR: full context save, IFR-bit clear, IPTR remap | **REFUTED as stated** (per-subclaim breakdown in §6) |
| 7 | RETI: INTM and XF are NOT part of the shadowed context | **CONFIRMED** |
| 8 | NDX=0: AR0 loads mirror to INDX and ARCR | **CONFIRMED** |
| 9 | CRGT/CRLT are signed MAX/MIN | **CONFIRMED** |
| 10 | NORM with ACC=0 sets TC=1 | **CONFIRMED** |

Score: 8 confirmed as stated, 1 confirmed with a representation note, 1 refuted as stated.

## 1. Interrupt vectors — CONFIRMED

- §4.8.1, Table 4–14 (PDF p.116 / printed 4-37): TINT dec 8 / hex 8, RINT dec 10 / hex A,
  XINT dec 12 / hex C, TRNT dec 14 / hex E, TXNT dec 16 / hex 10, INT4 dec 18 / hex 12.
  Priorities 6, 7, 8, 9, 10, 11 respectively (RS pri 1, NMI pri 2, INT1 pri 3).
- Independently attested by Ch. 6 INTR K-table (§6.3 INTR, PDF p.263 / printed 6-111):
  K=4 TINT 8h, K=5 RINT Ah, K=6 XINT Ch, K=7 TRNT Eh, K=8 TXNT 10h, K=9 INT4 12h.
- And by §8.2.2, Table 8–7 (PDF pp.485–486 / printed 8-18–8-19), transcribed in
  `08-memory.md`. All three agree; the core's `ivec[]` (+0x10) is wrong on every one.
- 1998 citation (re-map note): the audit cited the 1993 OCR's Ch. 8 vector table; in
  1998 numbering the table is §4.8.1 Table 4–14 (and §8.2.2 Table 8–7). Substance identical.

## 2. RPTC reset value 0 — CONFIRMED

- §4.9 Reset, Table 4–15 (PDF p.125 / printed 4-46): "RPTC — All bits → 0 — Repeat
  counter is cleared."
- §4.6 (PDF p.102 / printed 4-23): "RPTC … is cleared by reset and loaded only by the
  RPT or RPTZ instruction."
- The core initialises `rptc = -1` (sentinel for "no repeat"). The manual's reset value
  is 0, so a read of RPTC after reset must return 0, and the first repeatable block-move
  after reset must execute (the audit's "block moves execute zero times as first
  instruction after reset" follows from the −1 sentinel, not from the manual).
- Distilled: `04-program-control.md` §4.9 / Tables 4–15–4–16.

## 3. RPTB: PAER ← pma, iterations = BRCR+1, PASR = PC+2 — CONFIRMED

All three sub-claims verified in two places each:

- §4.7 (PDF p.110 / printed 4-31): "A block of instructions can be repeated N + 1 times,
  where N is the value loaded into [BRCR] by the RPTB instruction." / "When the [RPTB]
  instruction is executed, it … loads [PASR] with the address of the instruction
  following the RPTB instruction, and loads [PAER] with its long immediate operand. The
  long immediate operand is the address of the instruction following the last instruction
  in the loop, minus 1." / Example 4–8: `SPLK #0Fh,BRCR` (15) then `RPTB END_LOOP–1`
  gives **16 executions**.
- §6.3 RPTB (PDF pp.369–370 / printed 6-217–6-218), Execution: "1 → BRAF;
  (PC) + 2 → PASR; pma → PAER." Words: 2. "The number of loop iterations is given as
  (BRCR) + 1."
- PASR = PC+2 follows because RPTB is a 2-word instruction and PC at execution points
  at RPTB itself; PC+2 is the following instruction's address.
- Distilled: `04-program-control.md` §4.7, `06d-instructions-s-z.md` RPTB entry.
- **Core-representation note (for the parent, not a manual dispute):** the core sets
  `paer = imm + 1` and tests `pc == paer` *before* fetching. That yields the correct
  iteration count (BRCR+1) but leaves the externally visible PAER register one higher
  than the manual's value (pma). Audit areas disagreed on this: area 02 calls it an
  off-by-one bug, area 04 calls it a correct adaptation to before-fetch checking. The
  manual fact is CONFIRMED either way; whether the +1 adaptation counts as a bug is an
  implementation judgement — a guest reading PAER (e.g. via SMMR) would observe the
  wrong value, which is the concrete sense in which it bites.

## 4. Timer: TIM reset 0xFFFF; prescaler/reload — CONFIRMED

- §4.9 Reset, Table 4–15 (PDF p.125 / printed 4-46): "TIM — All bits → 1 — Timer counts
  down from FFFFh." PRD likewise all bits → 1 (same table; distilled `04` §4.9).
- §9.1.3 item 6 (PDF p.515 / printed 9-6): "TIM and PRD loaded with FFFFh."
- Prescaler/reload — §9.3.2 Timer operation (PDF p.520 / printed 9-11) and §9.3.1
  Table 9–4 (PDF p.519 / printed 9-10): PSC is loaded with TDDR when the timer is reset
  or when TIM is reloaded; TIM decrements each prescaled tick; on TIM borrow (decrement
  past 0) TIM is reloaded with PRD, PSC with TDDR, and TINT is generated. Timer period
  `1/[tc(C)·(TDDR+1)·(PRD+1)]`. Distilled: `09a-peripherals-timer-clock-waitstates.md`
  §§9.1.3, 9.3.1–9.3.2.
- Note the 09a contradiction C2: Table 9–4 says reload is triggered when TIM is
  "decremented past 0" while §9.3.2 says "decrements to 0" — §9.3.2 borrow semantics
  treated normative in the distillation. Either wording still gives TIM reset = FFFFh
  and the same reload values; it does not affect this verdict.

## 5. Serial: XINT only on XRDY 0→1 — CONFIRMED

- §9.7.1, Table 9–13 SPC bit 11 XRDY (PDF p.538 / printed 9-29): "Transmit Ready. A
  transition from 0 to 1 of the XRDY bit indicates that the DXR [word has been copied to
  XSR]. … A transmit interrupt (XINT) is generated upon the transition."
- §9.7.3 (PDF p.544 / printed 9-35): "A transmit interrupt (XINT) is generated upon
  this transition" (the DXR→XSR copy completing, XRDY 0→1).
- §9.7.6 (PDF p.557 / printed 9-48): "XINT is generated only if the DXR has been written
  to since the last transmit."
- So XINT is a per-word edge event tied to the DXR→XSR copy, not a per-tick level. The
  core's `c5x_serial_tick()` raising XINT on every tick is wrong per the manual.
- Distilled: `09b-peripherals-serial-bsp-tdm-hpi.md` §9.7 (SPC Table 9–13, §§9.7.3/9.7.6).

## 6. INTR: full context save, IFR-bit clear, IPTR remap — REFUTED as stated

The compound claim splits three ways. The audit's citation (1993 OCR) does not map to
a single 1998 passage that says all three; the 1998 manual says different things in
different places, and one sub-claim is explicitly contradicted.

- **(a) Full context save — PARTIAL / scoped, not blanket.** §4.8.7 (PDF p.120 / printed
  4-41): "An INTR interrupt for the external interrupts (INT1–INT4) executes like an
  external interrupt described in subsection 4.8.2." §4.8.2 (PDF p.117 / printed 4-38)
  lists "Key registers are saved into context shadow registers" among the trap actions.
  So for INTR K = 1–4 (INT1–INT4) the shadow save follows. BUT: Ch. 6 INTR Execution
  block (§6.3, PDF p.263 / printed 6-111) lists only "(PC) + 1 → stack; corresponding
  interrupt vector → PC" — no shadow save. And for INTR K other than 1–4 (e.g. TINT,
  RINT, user vectors 20–31) the manual states nothing about a save. By contrast NMI and
  TRAP are stated explicitly *not* to save (§4.8.7: "key registers are not saved into
  context shadow registers"). The safe reading: context save is supported for
  INTR-to-INT1–INT4 via §4.8.7, unconfirmed for all other K. The audit's unqualified
  "full context save" overstates it.
- **(b) IFR-bit clear — REFUTED.** Ch. 6 INTR Description (§6.3, PDF p.263 / printed
  6-111): "An INTR interrupt for the INT1–INT4 interrupts looks exactly like an external
  interrupt **except the interrupt will not clear the appropriate bit in the IFR**." That
  directly contradicts §4.8.2's general trap action ("Corresponding interrupt flag bit
  in the IFR is cleared", PDF p.117 / printed 4-38). Per the distillation's normative
  rule (opcode-level descriptions outrank Ch. 4 prose), Ch. 6 wins: **INTR does not clear
  IFR**. The core's INTR (no IFR clear, per audit area 02) is correct on this point; the
  audit finding as phrased ("IFR-bit clear" as required INTR behaviour) is backwards.
  This is a second CALAD-class reversal: the audit's 1993-OCR reading had the polarity
  wrong.
- **(c) IPTR remap — UNCONFIRMED (ambiguous in the manual).** The general vector
  generation is IPTR-based: Fig. 4–6 (PDF p.117 / printed 4-38) shows IPTR = 00001 with
  INT = 5 generating vector 080Ah (IPTR in bits 15–11, offset 0Ah in bits 10–0); §8.2.2
  (PDF p.474 / printed 8-7) applies IPTR remapping to "any subsequent interrupt except
  reset". But the Ch. 6 INTR K-table gives absolute hex locations (0h–3Eh) with no mention
  of IPTR, and no passage states explicitly that INTR vectors are IPTR-remapped. Plausible
  via the general mechanism, not proven for INTR. Do not implement or assert it without
  a hardware test or a further manual passage.
- **Corrected statement:** INTR sets INTM = 1 (Ch. 6 INTR, "Affects: INTM"; §4.8.7);
  pushes PC+1; jumps to the K vector; for K = 1–4 it otherwise behaves like the
  corresponding external interrupt *except* it does not clear IFR; whether it saves
  shadows for K ≠ 1–4 and whether its vectors are IPTR-remapped are unstated.
- Distilled: `04-program-control.md` §§4.8.2/4.8.7/4.8.8 (incl. the INTR shadow-save
  INFERENCE flag), `06b-instructions-a-h.md` INTR entry.

## 7. RETI: INTM and XF NOT shadowed — CONFIRMED

- §4.8.8 Interrupt Context Save (PDF p.121 / printed 4-42): the 1-level shadow registers
  cover ACC, ACCB, ARCR, INDX, PMST, PREG, ST0, ST1, TREG0, TREG1, TREG2 — "with the
  exception of the INTM bit in ST0 and the XF bit in ST1. On an interrupt, the INTM bit
  is always set to disable interrupts." Shadow registers "are copied back to the CPU
  registers when the RETI or RETE instruction is executed."
- §§4.4.2/4.4.3 and §4.8.8 agree (no contradiction inside Ch. 4 — see `04` Contradiction
  log). The core's `restore_ctx()` restoring INTM and XF is a bug per the manual.
- Distilled: `04-program-control.md` §§4.4.2/4.4.3/4.8.8.

## 8. NDX=0: AR0 loads mirror to INDX and ARCR — CONFIRMED

- §5.2.1 (PDF p.136 / printed 5-6): "To maintain compatibility with the 'C2x devices,
  clear the NDX bit in the PMST. In the 'C2x architecture, the NDX bit is cleared,
  **every AR0 modification or LAR write also writes the ARCR and INDX with the same
  value**. Subsequent modifications of the current ARs with indexed addressing will use
  the INDX, therefore maintaining compatibility with existing 'C2x code. **The NDX bit
  is cleared at reset.**"
- So the coupling is ON when NDX = 0, and NDX = 0 is the reset state — the core (which
  never implements the coupling) is wrong from reset onward, not only after NDX is
  touched. NDX = 1 behaviour is not stated anywhere in Ch. 5 (recorded as a gap in
  `05-addressing-modes.md` §9).
- Distilled: `05-addressing-modes.md` §5.2.1.

## 9. CRGT/CRLT are signed MAX/MIN — CONFIRMED

- §6.3 CRGT (PDF p.252 / printed 6-100), Description: "The contents of the accumulator
  (ACC) are compared to the contents of the accumulator buffer (ACCB). **The larger
  value (signed) is loaded into both registers.** If the contents of the ACC are greater
  than or equal to the contents of the ACCB, the C bit is set; otherwise, the C bit is
  cleared." Execution: ACC > ACCB → ACC → ACCB, C=1; ACC < ACCB → ACCB → ACC, C=0;
  ACC = ACCB → C=1.
- §6.3 CRLT (PDF pp.254–255 / printed 6-102–6-103), Description: "The **smaller (signed)
  value** is loaded into both registers." Execution mirrored (ACC < ACCB → ACC → ACCB,
  C=1; ACC > ACCB → ACCB → ACC, C=0; equal → C=0).
- The core's unsigned comparison is wrong per the manual (audit area 02's finding stands).
- Distilled: `06b-instructions-a-h.md` CRGT/CRLT entries. (Note `03` §3.2: the manual's
  CRLT/CRGT worked examples only work as two independent examples, not sequential code —
  a presentation quirk, not a semantic contradiction.)

## 10. NORM with ACC=0 sets TC=1 — CONFIRMED

- §6.3 NORM (PDF p.333 / printed 6-181), Execution: "If (ACC) = 0: TC → 1. Else: If
  (ACC(31)) XOR (ACC(30)) = 0: TC → 0, (ACC) × 2 → ACC, modify current AR as specified.
  Else: TC → 1." Status bits: Affects TC.
- So ACC = 0 is a distinct first case (TC = 1, no shift, no AR modification — the AR is
  modified only in the shift branch). The core's NORM (which computes `t` from bits 31/30
  without the ACC = 0 case) sets TC = 0 for ACC = 0 — wrong per the manual.
- Distilled: `06c-instructions-i-r.md` NORM entry.

## Notes for the parent (do not edit the audit files — this is the verification record)

1. **Two audit findings are backwards, same root cause.** CALAD/BE3D and INTR/IFR-clear
   were both read off the January 1993 OCR text. In the June 1998 PDF, CALAD = 0xBE3D
   (core correct) and INTR explicitly does *not* clear IFR (core correct on that point).
   Any other audit finding whose only citation is the 1993 OCR should be treated as
   suspect until re-mapped; the eight CONFIRMED items above were re-checked against the
   1998 PDF and stand.
2. **The audit's consolidated "149/160 forms correct, 0 missing"** (parent correction,
   20:18 CET) is consistent with this pass: the §6.3 count is 133 mnemonics / 179 summary
   rows, and the audit's 160-form basis counts §6.3 description forms — a different basis
   from the summary tables (see `index.md` §Counts). The two bases should not be compared
   directly.
3. **RPTB PAER:** the only remaining inter-area disagreement is representational (core
   `paer = imm+1` + before-fetch check vs manual `paer = pma`), noted in §3 above.
   The iteration count (BRCR+1) is right in the core; the observable PAER register value
   is one high.
4. **INTR IPTR remap and INTR shadow-save for K ≠ 1–4** remain genuinely unstated in the
   manual — flagged here rather than resolved, per the distillation's accuracy rules.
