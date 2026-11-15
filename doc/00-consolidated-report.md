# C5x core audit — consolidated report

Date: 2026-11-14. Core: `~/workspace/user/files/c5x_core.c`, 603 lines
(md5 `41c51be7…`, source untouched by the audit).
Manual: `~/workspace/user/files/spru056d.pdf`, TMS320C5x User's Guide SPRU056D,
June 1998, 764 pp, SHA-256 `a31e285f1be9fe87064e914de7bce6c96a99dd53bea3f3882c9fbe56bd45ce30`
(identical to `research_notes/courier-firmware/c5x_users_guide.pdf`).

Method: 4 parallel audits, 2,000 lines total, each with manual section + core
line refs. Two auditors per area in places, reconciled by the parent (see
§5 for the reconciliations). Findings were verified against the manual text
itself; the derived `c5x_opcodes.*` / `c5x_patterns*.json` files were used only
as cross-checks, never as authority.

| File | Area | Lines |
|---|---|---|
| `01-instruction-set.md` | Instruction-set completeness (mechanical 65,536-word sweep) | 640 |
| `02-cpu-semantics.md` | Addressing, registers, flags, repeat, stack, interrupts | 226 |
| `03-memory-peripherals-interrupts.md` | Memory map, MMRs, timer, serial, parallel I/O, reset, IDLE | 708 |
| `04-pipeline-timing-build.md` | Build, cycle model, delay slots, RPT/BRAF, smoke test | 426 |

## Verdict

The core is a working sequential emulator, not a cycle-accurate one. It
implements 148 of 160 manual instruction forms correctly, misses exactly one
(CALAD), gets 11 partly wrong, and executes one opcode the manual does not
define (BE3D). It builds clean and passes functional smoke tests (T1–T8),
but its `cycles` counter is an instruction count, its timer runs in
instruction time, its interrupt vectors for TINT/RINT/XINT/TRNT/TXNT/INT4 are
all wrong, and block moves execute zero times as the first instruction after
reset. No interrupt-driven SV25 run can be trusted until the vector table
and the serial/timer interrupt behaviour are fixed. The full fix order is §4.

## 1. Counted coverage (area 01, authoritative)

160 manual forms audited (one row per mnemonic + operand shape, §4.3 Syntax
blocks cross-checked against Table 4-5 and the fixed table).

| Status | Count |
|---|---|
| Implemented correctly | 148 |
| Valid form hitting RUN_BADOP (MISS) | 1 — CALAD, 0xBE31 |
| Partially implemented (wrong semantics) | 11 |
| Missing entirely (no case at all) | 0 |
| Phantom (core executes, manual has no such instruction) | 1 — BE3D |
| Correctly rejected (unassigned → RUN_BADOP) | 0x56, 0xA1, BE/BF gaps — correct, not gaps |

The 11 partial forms: CRGT, CRLT (unsigned MAX/MIN); NORM (ACC=0, RPT-loop
AR overshoot); LAR dma / LAR #k / LAR #lk (NDX=0 mirror missing); INTR k
(no context save, no IFR clear, no IPTR); NMI (no INTM←1, no IPTR); TRAP
(IPTR remap open point only); IDLE2 (treated as IDLE); RPTB (PAER stored
pma+1). No mnemonic family is missing entirely.

Correction to the original brief: the instruction set is **Chapter 4**
("Assembly Language Instructions", Table 4-5), not Chapter 6. Chapter 6 is
Memory. Tables 6-4..6-10 are memory/interrupt-vector tables, not an
instruction list. The brief's "Ch.2/7/8" numbering in area 03 also matched
neither edition; that audit used the June 1998 PDF's own numbering
(Ch.4 program control/interrupts, Ch.8 memory, Ch.9 peripherals).

## 2. Ranked gaps and bugs

Severity is impact on running SV25 modem DSP firmware (serial + timer +
interrupts are the critical path; the blob is still unlocated, so "likely"
is judged from standard C5x DSP idioms).

### HIGH — blocks any interrupt-driven run

1. **Interrupt vectors wrong for TINT/RINT/XINT/TRNT/TXNT/INT4** —
   `ivec[]`, core ~:335 / L278. Core sends them to 0x18–0x22; manual
   Table 8-7 / §7.1 vector-table example puts TINT=0x08, RINT=0x0A,
   XINT=0x0C, TRNT=0x0E, TXNT=0x10, INT4=0x12 (TRAP at 0x22 confirms the
   layout: 10×2 + 14 + 2). INT1–INT3 (0x02/0x04/0x06) are correct.
   Found independently by areas 02 and 03. One-line fix. Every timer/serial
   interrupt dispatches to the wrong ISR unless the `ivec_ind` hack
   bypasses it.
2. **Block moves execute zero times as the first instruction after reset** —
   `while (rptc > -1)` with `rptc=-1` after reset. SMMR ~:306, BLDP ~:335,
   LMMR ~:380, BLPD ~:400/402, TBLR/TBLW ~:404/406, BLDD ~:408–419.
   MAC/MADD (`do…while`) immune. Fix: initialise RPTC to 0 (manual) or
   make the loops do-once. Bites only if the DSP blob starts with a block
   move — but that is exactly an entry-point instruction.
3. **Timer runs in instruction time, not CLKOUT1 time** — `tick_timer()`
   once per executed instruction; the core counts 1 cycle per instruction
   regardless of real cycle counts and wait states (see #5). TINT rate too
   fast by ~2–4×. Prescaler/reload arithmetic itself is correct.
4. **Serial tick raises XINT on every tick** — `c5x_serial_tick()`, :592–595.
   XINT must fire only on a DXR→XSR 0→1 XRDY transition, once per transmitted
   word. Spurious TX interrupts at the sample rate; TX flow otherwise
   unmodelled (no XSR/CLKX/frame sync; XRDY returns to 1 only via this tick,
   so polled TX stalls without RX ticks).
5. **Cycle model is an instruction count, not a cycle model** — `exec1()`
   does `cycles++` once per call (:300); a second fetch word adds nothing.
   Measured vs App. B Table B-2 / Ch. 6 tables: every 2-word instruction
   counts 1 instead of 2; taken B/CALL/BCND counts 1 instead of 4; delayed
   branches count 3 instead of 2; TBLR/MAC/BLDD-#lk count 2 instead of 3;
   OUT counts 1 instead of 3. Wait states never added (PDWSR/IOWSR/CWSR
   stored but never read), no external read-1/write-2 rule, no SARAM
   conflict. Timer/serial timing inherits all of it. Repeat loops are the
   one place it is nearly right (BLDD-BMAR/MADD: n+1 matches; BLDD-#lk/MAC/
   TBLR: n+1 vs manual n+2, off by 1).

### HIGH — kills the run on valid firmware

6. **CALAD missing (0xBE31 → RUN_BADOP) + BE3D phantom** — area 01, M1/X1.
   Manual §4.3 CALAD subsection; `c5x_patterns_fixed.json` has CALAD
   mask 65535 val 48689 (0xBE31); core has no `case 0x31` in `exec_be()`.
   Core's `case 0x3D` (:489) implements a delayed CALA that the manual does
   not define — no bit pattern for 0xBE3D occurs anywhere in the manual, no
   entry in `c5x_opcodes.json`. Fix: add CALAD at 0x31 (mirror the 0x3D
   body), delete the 0x3D case.
7. **RPT repeats non-repeatable instructions** — `c5x_run` ~:579 repeats any
   instruction after RPT, including Table 3-11 nonrepeatable BANZ[D]/BCND[D]/
   CALL[D]/CC[D]/INTR/IDLE/RET/RPT/XC. Measured: `RPT #2; B` executes the
   branch 3×; `RPT; CALL` would push N+1 return addresses, `RPT; RET` pop
   N+1 times. Needs a repeatability whitelist. Related: line 580
   `else c->rptc = 0` clobbers the −1 "no repeat" sentinel after every
   instruction — single BLDD-BMAR/LMMR/SMMR/MAC count 2 only by accident.

### MEDIUM — wrong results / wrong state

8. **RPTB PAER off by one (value wrong, count right)** — RPTB stores
   `paer = imm+1` (:510, manual: PAER ← pma); `c5x_run` wraps *before*
   executing PAER instead of after. Net iteration count (BRCR+1) is
   accidentally right for straight-line RPTB-loaded blocks, but PAER reads
   back pma+1 via MMR 0x0B, MMR-loaded PAER (nested-loop save/restore, the
   manual's own pattern) breaks, and a branch/call landing directly on PAER
   skips the last instruction.
9. **INTM/XF wrongly shadowed on interrupt** — `save_ctx`/`restore_ctx`
   ~:266–276 save both; manual §3.8.3 says neither is saved. Worse,
   `check_int()` sets `intm=1` *before* `save_ctx()`, so `sh.intm` is always
   1 and RETI forces INTM=1 even after CLRC INTM in the ISR. Interrupts
   cannot be re-enabled from inside an ISR via the documented RETI path.
10. **NDX=0 AR0→INDX/ARCR mirroring missing everywhere** — LAR (all forms),
    MAR/`ea()`/ADRK/SBRK, MMR writes to AR0; `ndx` never consulted. Default
    after reset is NDX=0 (coupling on). C25-style `LAR AR0` + `CMPR` compares
    against stale ARCR. The `cmpr_ar0` experiment flag (:44, :528, :596)
    papers over one case — delete once mirroring is implemented.
11. **INTR k incomplete** — `exec_be` INTR branch ~:512–515: IPTR ignored
    (should be `(iptr<<11)|v`), context save gated on host `ivec_ind`
    (manual: full context save, exit via RETI/RETE), IFR bit never cleared
    (re-triggers). Plain INTR with no `ivec_ind` takes the trap with no
    shadow save, so RETI restores a stale shadow.
12. **Reset values wrong** — TIM=0, should be 0xFFFF (§9.1.3; spurious TINT
    ~1 prescaler period after reset; PRD=0xFFFF is correct). PDWSR/IOWSR
    must be 0xFFFF, CWSR 0x0F (core leaves 0). GREG not cleared on re-reset;
    RPTC reads 0xFFFF (sentinel leaks, manual: 0); SPC/DRR/DXR/`mmr_raw`/
    `ivec_ind` not cleared on re-reset.
13. **OVLY/CNF ignored in the data map** — SARAM 0x0800–0xBFF and B0
    0x0100–0x2FF always internal `dmem[]`; manual requires OVLY=1 / CNF=0
    respectively. Program-side `pm_ptr()` CNF/RAM branches are correct.
    Whether it bites depends on what SV25 programs into PMST — open check.
14. **SMMR/LMMR re-evaluate `ea()` per repeat iteration** — ~:306, :380.
    Indirect `*+` walks the MMR address each iteration; manual has no
    AR-modify step for these. Verified: `RPT #1; SMMR *+,AR1,#0x300` writes
    dm[0x301] instead of dm[0x300] twice, AR1 advances 0x70→0x72.
15. **BMAR written back by block moves, even single execution** — ~:335,
    :400, :415, :417/419. Manual pseudocode never assigns BMAR. Verified:
    single BLDP BMAR 0x200→0x201. Breaks code reusing BMAR as a base pointer.
16. **DMOV side-effect of MACD/MADD/LTD/DMOV fires on MMR/external dma** —
    ~:398, :415, :362, :367. Manual: read-only no-op there. Verified: MACD
    with dma=AR0 overwrites AR1; standalone `DMOV 0x10` overwrites AR1.
17. **CRGT/CRLT unsigned instead of signed** — `exec_be` 0x1B/0x1C. Wrong
    whenever ACC/ACCB straddle the sign boundary (ACC=−1 vs ACCB=1: core
    picks −1 as max with C=1; correct max is 1 with C=0).
18. **XC k=1 skips opcode words, not instruction words** — ~:433–434. False
    `XC 1` before a 2-word instruction skips 1 word and executes its
    immediate word as an instruction. Verified empirically. (XC condition
    sampling 1 cycle before is also unmodelled.)
19. **SPC RRST/XRST writes ignored; read-only SPC bits leak through
    readback** — RSRFULL/XSREMPTY/IN1/IN0/reserved bit 0 unmasked.
20. **IDLE/IDLE2 conflated** — `exec_be` 0x22/0x23, same flag. IDLE2 must
    stop the timer and wake only on external INT/RS/NMI. There is no IDLE3
    on the C5x.

### LOW–MEDIUM — edge cases, still real

21. **LST #0 corrupts ARB** — ~:312 via `ea()` → `upd_arp()` when the
    indirect field has a next-ARP bit. Manual: LST #0 never affects ARB.
22. **`*BRO±` circular wrap missing** — `ea()` ~:230, :233 bypass `upd_ar()`.
    INDX paths do wrap; only bit-reversed paths bypass.
23. **NORM misses ACC==0** (TC must be 1, core sets 0) — 0xA0 ~:393–394.
    Breaks normalisation loops testing TC for a zero accumulator. Also
    RPT-loop AR overshoot (area 01, P2).
24. **SUBC never updates OV or C** — 0x0A ~:310–311. Formula branch itself
    is correct.
25. **CLRC-INTM shadow missing** — interrupt can be taken immediately after
    CLRC INTM/RETE, before the next instruction.
26. **Delay-slot stack ordering** — CALLD (:374), CCD (:442), CALAD (:489)
    push the return address *before* `delay_slot()` runs; RETCD (:444) pops
    before it. Push/pop *values* are correct (CALLD PC+4, CCD PC+4, CALAD
    PC+3 — verified), but a delay-slot instruction that itself pushes/pops
    operates on the wrong stack level. (BD/BCNDD/BACC have no stack op and
    are unaffected.) Related: `in_delay` is a dead flag (set :262/264, read
    nowhere); a nested PC-changing instruction in a slot is silently
    discarded (or executed as a slot if the target lands within 2 words);
    RPT in a slot is silently cancelled and leaves stale `rptc>0` gating
    interrupts off effectively forever; BADOP in a slot is not aborted;
    breakpoints aren't checked inside slots.
27. **NMI opcode missing `intm=1`** (opcode p. 6-179 explicit); TRAP/NMI
    probably missing IPTR remap (§8.2.2 + Fig. 4-8 outweigh the opcode
    pages' IPTR=0 wording). NMI/RS inputs unmodelled (no NMI input exists;
    `c5x_irq` only sets IFR bits).
28. **Register widths unmasked** — TREG1 5-bit, TREG2 4-bit, CBCR/GREG 8-bit,
    CWSR 5-bit, IMR/IFR bits 8–0.
29. **Reserved/test-emulation addresses (0x00–0x03, 0x23, 0x27, 0x2B–0x4F,
    0x38–0x4F) behave as RAM** via `mmr_raw[]`; TDM regs 0x30–0x35 entirely
    absent (C51 has no TDM/BSP/HPI — correctly absent as hardware, wrong
    as RAM).
30. **RPT IN/OUT hits the same port every iteration** (manual: PA+1 per
    access); wait states stored but never applied (incl. MMR-write +1 cycle).
31. **Last-two-words interrupt lockout of a block-repeat loop (§3.6.5) not
    implemented**; CALA/CALL as the block's last instruction pushes CALA+1
    instead of PASR (return flow same in the common case, decrement timing
    differs); BRCR reads back 0xFFFF after completion instead of 0.

### LOW — cosmetic / harness-only

32. `c5x_set` has no S_ST1 / S_PMST cases (silently ignored).
33. Host window 0xFF50–0xFF5F is **not** a manual C51 feature (no HPI on C51,
    no in-repo consumer found) — board/harness-specific hack, keep but do not
    mistake for architecture.
34. MPMC/ROM mapping unmodelled (`pm_ptr` always reads `pmem[]` for
    0x0000–0x1FFF) — correct only if the harness pre-loads ROM contents.
35. Build: only warning is dead `sat_acc_shift()` (:287, unused parameter +
    unused function). Source md5 unchanged by the audit.

## 3. Verified correct — do not "fix"

Instruction coverage per §1; indirect modes 0–15 (except `*BRO±` wrap);
direct/DP, LDP/LDPK, SST page 0, LST #1 ARB=ARP (area 02's initial suspicion
was wrong — Table 3-7 confirms it); ST0 layout; LAR/SAR/MAR/ADRK/SBRK (except
NDX mirroring); 32-bit ACC with no guard bits; SXM/`ext()`; PM/`pscale()` all
four modes; OVM saturation values and OV latching; carry C 16/32-bit rules;
ADDC/SUBB; TREG/TRM; MPY/MPYU/LPH; SFL/SFR/ROL/ROR + B-variants; SATH/SATL;
BSAR; BIT/BITT; AND/OR/XOR asymmetry; LACL/ZALR/ADDS/SUBS; RPT count/target/
RPTZ/interruptibility; RPTB BRCR source/PASR/nesting/BRCR=0; stack push/pop
(the suspicious `pop()` copy line is correct shift-register emulation);
CALL/RET return addresses and conditional pop; `delay_slot()` word count;
11-register shadow set; `check_int()` mechanics (except #9/#25) and priority
order (bit-ascending, consistent with §5.1.2); TRAP behaviour; CMPR target/
mapping; conditional field/TP/ZLVC decoding; MAC order/count; MPY #k13; SPM;
ST0/ST1/PMST layouts and hardwired-1 bits; timer period formula; LST #0 not
loading INTM; 0x56/0xA1 BADOPs; RET/RETD as unconditional RETC/RETCD
encodings (0xEF00/0xFF00); BANZ test-before-decrement order; ADDS/SUBS full
32-bit; SMMR/LMMR directions; BIT/BITT bit numbering (`15 − code`).

## 4. Fix order (highest impact first)

1. Vector table `ivec[]` (#1) — blocks all interrupt-driven firmware.
2. Block-move first-instruction bug (#2); SMMR/LMMR fixed `ea()` (#14);
   BMAR write-back removal (#15); DMOV gating (#16).
3. RPTB PAER = `imm` + wrap *after* executing PAER (#8); repeatability
   whitelist (#7); RPT-in-delay-slot + CLRC-INTM shadow (#25, #26).
4. Interrupt context: stop shadowing INTM/XF, save INTM *before* setting it
   (#9); INTR IPTR + unconditional context save + IFR clear (#11); IDLE2
   state (#20); NMI `intm=1` (#27).
5. NDX mirroring (#10), then CALAD/BE3D (#6), then CRGT/CRLT, NORM, SUBC,
   XC, LST #0, `*BRO±` (#17, #23, #24, #18, #21, #22).
6. Serial/timer: XINT-on-transition only (#4), timer off real cycle counts
   — which requires the cycle model (#5) first; reset values (#12); OVLY/CNF
   data map (#13); SPC handling (#19).
7. Remainder: register widths, reserved addresses, RPT IN/OUT, block-repeat
   lockout, `c5x_set` S_ST1/S_PMST.

## 5. Reconciliations (where the auditors disagreed)

- **RPTB PAER (02 vs 04).** 04: `paer=imm+1` is a correct adaptation for the
  documented `RPTB END−1` usage, given the before-fetch check — iteration
  count verified by trace and smoke test T7. 02: the *value* is still wrong
  (MMR readback, MMR-loaded PAER, branch landing on PAER). Resolution: both
  right in their scope — count correct in the common case, value wrong and
  breaks the manual's own nested-save pattern. Listed as #8.
- **CALAD encoding (01 vs 02).** 02 §8 claimed "no documented instruction is
  missing" and treated core `case 0x3D` as CALAD. 01 proved by manual §4.3
  (line 11849), the fixed table (val 48689 = 0xBE31), and a mechanical sweep
  over all 65,536 opcode words that CALAD is 0xBE31 (missing, BADOPs) and
  0xBE3D has no manual basis. 01 wins; 02's coverage claim is withdrawn.
- **Block moves after reset (01 top-10 vs 04 smoke test).** 04's T5 single
  BLDD passed because it was not the first instruction after reset. 02's
  zero-execution finding (#2) stands for the first-instruction case; 01
  lists it as E1 in its own top 10.
- **Manual chapter numbering.** The brief said Ch.6 = instruction set. 01
  proved from the manual's own contents that Ch.4 is the instruction set
  and Ch.6 is Memory. 03's brief numbering (Ch.2/7/8) matched neither
  edition. All refs above use the June 1998 PDF's own numbering.
- **OCR limits.** Table 4-5's Syntax column and §4.5's opcode column are
  largely destroyed by OCR; operand forms were taken from §4.3 Syntax
  blocks instead. The 1993 OCR text's front matter mislabels the edition;
  the PDF is June 1998. Where the manual contradicts itself, opcode
  execution tables were treated as normative over prose (TRAP/INTM) and
  Table 4-5 over §4.4.3 prose (LST #0/ARP).
- **Late §4.5 extraction checked and refuted (area 01, file §9).** A late
  extraction claimed BLDP=0x56, BLPD=0xA0/A1, IDLE=0xE222 and similar
  reassignments. All wrong, from two systematic mis-parses: §4.5's opcode
  column prints only bits 11–0 (e.g. NOP prints `1011 0000 0000`, which is
  the low 12 bits of 0x8B00), and the child grouped 7 opcode bits + the
  mode bit as the "high byte", dropping bit 8 (the mode bit is bit 7).
  0x56/0xA1 remain correctly rejected; counts unchanged.

## 6. Unverified (OCR limits, not core faults)

- Exact ST1 reserved-1 bit positions and PMST AVIS/reserved bits (Fig. 3-15
  garbled); which ARP value SST stores with a next-ARP field; interrupt
  priority order (Tables 3-12/5-2 garbled; bit-ascending scan consistent with
  §5.1.2 but TINT-vs-INT3 ordering not established); OV-clear extension to
  CC/RETC/XC and taken-vs-tested semantics (manual supports BCND/BCNDD only,
  individual pages say "Status Bits: None affected" — needs hardware/MAME
  cross-check); branch/call inside a delay slot; `exec_be` 0x52 as NMI
  encoding; whether TRAP/NMI take IPTR remap (§8.2.2 vs opcode pages).
- Appendix B Class XI lists "TRAPD" exactly once in the whole manual, with
  no §4.3 entry, no Table 4-5 row, no opcode. Presumed manual error/vestige;
  no encoding to implement, not counted as missing.

## 7. Side finding — validator decode-table holes (blob hunt, not core bugs)

`c5x_patterns_fixed.json` (177 entries, used by `c5x_validate.py` /
`c5x_run.py`) is missing manual forms the core gets right: APAC (0xBE04),
MPY #k13 (0xC0–0xDF), XC 2 (0xF4–0xF7), direct B/CALL/BANZ/BD/CALLD/BANZD
(first-word low byte 0x00–0x7F; the table's patterns require bit 7 set).
Anything the validator cannot decode is kind 0 ("invalid") and can break
traversals / S-votes. Fix the table, not the core.

## 8. Open checks for the parent

- What SV25 programs into PMST (OVLY/CNF — decides whether #13 bites) and
  into SPC (FO bit — decides whether 8-bit serial mode matters).
- Whether any harness run relies on `ivec_ind` indirections, which currently
  mask bug #1.
- Whether the DSP blob (still unlocated) uses CALAD, block moves at entry,
  or interrupt-driven serial/timer code — decides which HIGH items bite first.
