# Re-verification — instructions A–R on the NEW core (`c5x_core-2.c`)

Date: 2026-11-15 00:44–01:15 CET. Worker 2 of 5 (instructions A–R).
New core: `~/workspace/user/files/c5x_core-2.c`, 630 lines, md5
`7aa4227d47e9f72abee2b4cb48fb5fef` (read-only, never modified).
Old core: `~/workspace/user/files/c5x_core.c`, 603 lines, md5 `41c51be7…`.
Manual (sole authority): distilled files in
`~/workspace/research_notes/courier-firmware/c5x_manual/` (SPRU056D June
1998). The June 1998 PDF was not needed as a tiebreaker in this range; no
distilled-file ambiguity arose. The 1993 text (`c5x_users_guide.txt`) and
`c5x_opcodes.*` / `c5x_patterns_fixed.json` were never used as authority.
Prior record: `05-full-reverification.md` (§1 per-form old verdicts; §2
findings #1–#35; §3 new findings N-1..N-20), with per-range evidence in
`05a1` (A–D), `05a2` (E–H), `05b` (I–R).

## 0. Method, defaults, and counting conventions

- **Scope:** every §6.3 form A–R, same basis as 05 §1: A–D 57 forms
  (05a1), E–H 9 forms (05a2), I–R 45 forms (05b) — **111 forms**.
  RPT is not in this range: its §6.3 entry sits in `06d` (S–Z worker).
  S-mnemonics in the opcode map (SUB, SQRA, SBRK, SAR, SAMM, SACL, SACH,
  SPL, SPH, SST) are likewise S–Z, not re-verdicted here.
- **Judged behaviour is the default: `legacy = 0` and `cyc_model = 0`**
  (both are 0 from `calloc` in `c5x_new()`). Every legacy-bit effect is
  documented separately in §4 (what `legacy = 0` does = the verdict; what
  the bit re-enables = noted as manual-wrong, as expected, or accidentally
  right).
- **Diff-first check.** The old→new diff is 77 changed lines. `ea()`,
  `do_add`/`do_sub`, `ext()`, `pscale()`, `upd_ar()`, `upd_arp()`,
  `cond()`/`zlvc_cond()`/`tp_cond()`, `set_t0()`, `check_int()`,
  `mmr_rd`/`mmr_wr`, `dm_rd`/`dm_wr` are byte-identical. Every form whose
  code is unchanged carries its 05 verdict forward (re-checked against the
  new line numbers); only forms touched by the diff, or by a changed shared
  mechanism (NDX hook, cycle block, `delay_slot`), were re-derived. The
  diff touches, in this range: BLDP/BLPD/BLDD-BMAR writeback gating,
  NORM, MADD/MADS TREG load, CRGT/CRLT compare, the `ivec[]` table +
  INTR fallback, the `c5x_run` NDX hook + cycle block + `rep_cont`, and
  `delay_slot` (op restore).
- **Verdicts:** OBEYS / VIOLATES / PARTIAL / UNVERIFIED, per form =
  opcode + words + execution semantics + status-bit effects, same as 05.
- **Cycles convention (stated extension of 05).** The global cycle-model
  defect (05 #5) is recorded once, not per form — with one carve-out,
  applied exactly as 05a1 applied it and extended here to the same loop
  shape: forms whose implementation adds its own per-iteration
  `cycles++` inside a `while`/`do…while` loop (BLDD, BLDP, BLPD, LMMR,
  MAC, MACD, MADD, MADS) get per-form cycle verdicts on their
  default-model counts, because those counts are a per-form artifact, not
  the global 1-cycle model. All other multi-cycle forms (LAR 2, LDP 2,
  LST 2, OUT 3, NMI 4, RET 4, INTR 4, LACC #lk 2, …) are charged only to
  the global model. 05b had left MAC/MADD/MACD cycle counts in its §2
  cross-cutting record; this pass charges them per form, which demotes
  MAC (see §2.3). The merger should note the convention change.
  Cycle numbers quoted are the internal-memory (ROM/DARAM, p = d = 0)
  single/RPT tables from §6.3.
- **Empirical checks.** The new core does not compile as delivered (see
  new finding 06b-N1: `c5x_cyctab.h` is missing). All tests below ran
  against the unmodified core plus a stub header (`static const int
  cyc_tab[65536] = {0}` in `/tmp/c5x2/` — never read when `cyc_model =
  0`, the default). Harness `/tmp/c5x2/test.c` + `test2.c` (throwaway, not
  deliverables). Tests cited as T1–T12 / U1–U7 in §8.
- **Citations** are distilled chapter file + §6.3 entry (or table) + PDF /
  printed page as cited in the distilled file. `06b` =
  `06b-instructions-a-h.md`, `06c` = `06c-instructions-i-r.md`, `06d` =
  `06d-instructions-s-z.md`, `05` = `05-addressing-modes.md`,
  `04` = `04-program-control.md`, `06a` = `06a-instruction-set-summary.md`.

## 1. Counts

| Range | Forms | OBEYS | VIOLATES | PARTIAL | UNVERIFIED | Old (05) OBEYS / VIOL / PART |
|---|---|---|---|---|---|---|
| A–D | 57 | 49 | 0 | 8 | 0 | 46 / 0 / 11 |
| E–H | 9 | 6 | 1 | 2 | 0 | 6 / 1 / 2 |
| I–R | 45 | 35 | 0 | 10 | 0 | 32 / 0 / 13 |
| **A–R total** | **111** | **90** | **1** | **20** | **0** | **84 / 1 / 26** |

Net vs 05: **+6 OBEYS** (7 forms fixed: CRGT, CRLT, ADRK, LAR dma, LAR
#k, LAR #lk, MAR; minus MAC demoted OBEYS → PARTIAL on loop-cycle
counts). The single VIOLATES form is still IDLE2. No form is missing; no
phantom opcode in range (0x56 and 0xA1 still BADOP, `:338`/`:398`;
0xBE31 still BADOPs via the `exec_be` default).

## 2. Per-form verdicts

"Old" = 05 verdict for that form. "New" = this pass. Line numbers are
`c5x_core-2.c`. Unchanged-code forms cite the 05 evidence file for the
semantic detail and are not re-litigated here.

### 2.1 A–D (57 forms; 05a1 basis)

| Form | New-core lines | Verdict | Old | Note |
|---|---|---|---|---|
| ABS (0xBE00) | exec_be :459 | OBEYS | OBEYS | Unchanged. §6.3 ABS, 06b PDF p.180/6-28. |
| ADCB (0xBE11) | exec_be :470 | OBEYS | OBEYS | Unchanged. 06b PDF p.182/6-30. |
| ADD dma[,shift] (0x20–0x2F) | :323–325 | OBEYS | OBEYS | Unchanged. 06b PDF pp.183–186/6-31–6-34. |
| ADD dma,16 (0x61) | :350 | OBEYS | OBEYS | Unchanged. s16 C-rule intact. |
| ADD #k (0xB8) | :429 | OBEYS | OBEYS | Unchanged. |
| ADD #lk[,shift] (0xBF90–0xBF9F) | exec_bf :544 | OBEYS | OBEYS | Unchanged. RPT-repeatability is global #7 (§5). |
| ADDB (0xBE10) | exec_be :469 | OBEYS | OBEYS | Unchanged. 06b PDF p.187/6-35. |
| ADDC (0x60) | :349 | OBEYS | OBEYS | Unchanged. 06b PDF pp.188–189/6-36–6-37. |
| ADDS (0x62) | :351 | OBEYS | OBEYS | Unchanged. |
| ADDT (0x63) | :352 | OBEYS | OBEYS | Unchanged. |
| ADRK #k (0x78) | :373 | **OBEYS** | PARTIAL | **FIXED** — NDX mirror now applied (§5 #10; T5c: ADRK #5 on AR0=0x100 gives AR0=INDX=ARCR=0x0105). Residual same-value edge: 06b-N2. |
| AND dma (0x6E) | :363 | OBEYS | OBEYS | Unchanged. |
| AND #lk[,shift] (0xBFB0–0xBFBF) | exec_bf :546 | OBEYS | OBEYS | Unchanged. |
| AND #lk,16 (0xBE81) | exec_be :510 | OBEYS | OBEYS | Unchanged. |
| ANDB (0xBE12) | exec_be :471 | OBEYS | OBEYS | Unchanged. |
| APAC (0xBE04) | exec_be :463 | OBEYS | OBEYS | Unchanged. |
| APL DBMR (0x5A) | :343 | OBEYS | OBEYS | Unchanged. |
| APL #lk (0x5E) | :347 | OBEYS | OBEYS | Unchanged. |
| B pma (0x79) | :374 | OBEYS | OBEYS | Unchanged. |
| BACC (0xBE20) | exec_be :485 | OBEYS | OBEYS | Unchanged. |
| BACCD (0xBE21) | exec_be :486 | OBEYS | OBEYS | Unchanged. `delay_slot` op-restore (:262–268) does not change default behaviour. |
| BANZ pma (0x7B) | :376 | OBEYS | OBEYS | Unchanged. |
| BANZD pma (0x7F) | :380 | OBEYS | OBEYS | Unchanged. Test-timing sub-point still [UNVERIFIED] (05a1 N-2). |
| BCND pma,cond (0xE0–0xE3) | :436 | OBEYS | OBEYS | Unchanged. OV-clear follows the Ch.4 rule as in 05a1 (tension with §6.3 "None affected" recorded, not re-scored). |
| BCNDD pma,cond (0xF0–0xF3) | :444 | OBEYS | OBEYS | Unchanged. cond() evaluated before the slot, as §6.3 requires. |
| BD pma (0x7D) | :378 | OBEYS | OBEYS | Unchanged. |
| BIT dma,bit code (0x40–0x4F) | :329–330 | OBEYS | OBEYS | Unchanged. |
| BITT dma (0x6F) | :364 | OBEYS | OBEYS | Unchanged. |
| BLDD BMAR,dma (0xAC) | :421–422 | PARTIAL | PARTIAL | BMAR writeback **fixed** (gated :422). Remaining: first-after-reset zero execution (#2, T9) + RPT cycles n+2 vs manual n+1 (T11e: total 6 vs 5). Single cycles 2 = manual 2. §6.3 BLDD, 06b PDF pp.219–224/6-67–6-72. |
| BLDD dma,BMAR (0xAD) | :423–424 | PARTIAL | PARTIAL | Same as BMAR-src: writeback fixed (:424); #2 + RPT cycles remain. |
| BLDD #lk,dma (0xA8) | :412–413 | PARTIAL | PARTIAL | No BMAR involvement. Remaining: #2 + single cycles 2 vs manual 3 (steady-state U-test: total 3 vs 4). RPT cycles n+2 = manual n+2. |
| BLDD dma,#lk (0xA9) | :414–415 | PARTIAL | PARTIAL | Same as #lk-src: #2 + single cycles 2 vs 3. RPT correct. |
| BLDP dma (0x57) | :339–340 | PARTIAL | PARTIAL | BMAR writeback **fixed** (gated :340; T3: BMAR stays 0x2000). Remaining: #2 + RPT cycles n+2 vs n+1. Single 2 correct. §6.3 BLDP, 06b PDF pp.225–227/6-73–6-75. |
| BLPD BMAR,dma (0xA4) | :404–405 | PARTIAL | PARTIAL | BMAR writeback **fixed** (gated :405). Remaining: #2 + RPT cycles n+2 vs n+1. Single 2 correct. §6.3 BLPD, 06b PDF pp.228–233/6-76–6-81. |
| BLPD #pma,dma (0xA5) | :406–407 | PARTIAL | PARTIAL | No BMAR involvement. Remaining: #2 + single cycles 2 vs manual 3. RPT correct. |
| BSAR shift (0xBFE0–0xBFEF) | exec_bf :548 | OBEYS | OBEYS | Unchanged. |
| CALA (0xBE30) | exec_be :489 | OBEYS | OBEYS | Unchanged. |
| CALAD (0xBE3D) | exec_be :494 | OBEYS | OBEYS | Unchanged; still correct (see §5 #6). |
| CALL pma (0x7A) | :375 | OBEYS | OBEYS | Unchanged. |
| CALLD pma (0x7E) | :379 | OBEYS | OBEYS | Unchanged (#26 caveat stands, S–Z/05d territory). |
| CC pma,cond (0xE8–0xEB) | :440 | OBEYS | OBEYS | Unchanged. OV-clear scope still the open point O1 (05a1 §4). |
| CCD pma,cond (0xF8–0xFB) | :446 | OBEYS | OBEYS | Unchanged. Same O1 open point. |
| CLRC INTM (0xBE40) | exec_be :495 | OBEYS | OBEYS | Unchanged. Missing INTM shadow is #25 (run-loop, not this form). |
| CLRC OVM (0xBE42) | exec_be :496 | OBEYS | OBEYS | Unchanged. |
| CLRC CNF (0xBE44) | exec_be :497 | OBEYS | OBEYS | Unchanged. |
| CLRC SXM (0xBE46) | exec_be :498 | OBEYS | OBEYS | Unchanged. |
| CLRC HM (0xBE48) | exec_be :499 | OBEYS | OBEYS | Unchanged. |
| CLRC TC (0xBE4A) | exec_be :500 | OBEYS | OBEYS | Unchanged. |
| CLRC XF (0xBE4C) | exec_be :501 | OBEYS | OBEYS | Unchanged. |
| CLRC C (0xBE4E) | exec_be :502 | OBEYS | OBEYS | Unchanged. |
| CMPL (0xBE01) | exec_be :460 | OBEYS | OBEYS | Unchanged. |
| CMPR CM (0xBF44–0xBF47) | exec_bf :533 | OBEYS | OBEYS | Unchanged compare logic; its ARCR operand now tracks AR0 loads via the NDX hook (§5 #10), which removes the dependency noted in 05a1. |
| CPL DBMR (0x5B) | :344 | OBEYS | OBEYS | Unchanged. |
| CPL #lk (0x5F) | :348 | OBEYS | OBEYS | Unchanged. |
| CRGT (0xBE1B) | exec_be :480 | **OBEYS** | PARTIAL | **FIXED** — signed compare by default (T2: ACC=−1 vs ACCB=+1 gives both +1, C=1, per §6.3 "larger (signed)… If (ACC) ≥ (ACCB), C is set", 06b PDF pp.252–253/6-100–6-101; equality C=1 also verified against the Execution block). |
| CRLT (0xBE1C) | exec_be :481 | **OBEYS** | PARTIAL | **FIXED** — signed compare by default (T2c: both −1, C=0, per §6.3 "smaller (signed)… If (ACC) < (ACCB), C is set", 06b PDF pp.254–255/6-102–6-103; equality C=0 verified). |
| DMOV dma (0x77) | :372 | PARTIAL | PARTIAL | **Unchanged, still wrong** — `dm_wr(a+1,…)` unconditional (T7: DMOV 0x10 copies AR0→AR1). §6.3 DMOV, 06b PDF pp.256–257/6-104–6-105: no-op on MMR/external. See §5 #16 / N-8. |

A–D subtotal: **49 OBEYS / 0 VIOLATES / 8 PARTIAL** (was 46 / 0 / 11).
PARTIAL drivers remaining: BLDD ×4, BLDP, BLPD ×2 (all: #2 + loop-cycle
deviations; BMAR writeback fixed), DMOV (#16).

### 2.2 E–H (9 forms; 05a2 basis)

| Form | New-core lines | Verdict | Old | Note |
|---|---|---|---|---|
| EXAR (0xBE1D) | exec_be :482 | OBEYS | OBEYS | Unchanged. 06b PDF p.258/6-106. |
| IDLE (0xBE22) | exec_be :487 | OBEYS | OBEYS | Unchanged. 06b PDF p.259/6-107. |
| IDLE2 (0xBE23) | exec_be :488 | VIOLATES | VIOLATES | **Unchanged, still wholly wrong** — identical `c->idle = 1` to IDLE; timer keeps running, wake on any latched `ifr & imr` incl. TINT/serial. §6.3 IDLE2, 06b PDF p.260/6-108; §4.10 (04, PDF p.129/4-50). The only VIOLATES form in A–R. |
| IN dma,PA (0xAF) | :426 | PARTIAL | PARTIAL | **Unchanged** — single execution obeys; under RPT the port is re-fetched, never incremented (T10: both reads hit port 0x100). §6.3 IN, 06b PDF pp.261–262/6-109–6-110: "the port address is incremented after each access". See §5 #30. |
| INTR k (0xBE60\|k) | exec_be :517–522 | PARTIAL | PARTIAL | **Partly fixed, still PARTIAL.** `ivec[]` corrected (:281: 0x08/0x0A/0x0C/0x0E/0x10/0x12 for TINT…INT4), so the `ivec_ind` save path (05 §3 N-10) now works for K=4–9. Remaining: no `save_ctx()` on the normal path, so INTR K=1–4 still takes the trap with no shadow save (§4.8.7, 04 PDF p.120/4-41 → §4.8.2). IFR non-clear still correct (§6.3 INTR, 06b PDF p.263/6-111: "will not clear"). IPTR remap still [UNVERIFIED]. New legacy-fallback loop :521: see 06b-N4. |
| LACB (0xBE1F) | exec_be :484 | OBEYS | OBEYS | Unchanged; follows §6.3 (ACCB → ACC), not the reversed Table 6-4 description. 06b PDF p.265/6-113. |
| LACC dma[,shift] (0x10–0x1F) | :320–322 | OBEYS | OBEYS | Unchanged. |
| LACC dma,16 (0x6A) | :359 | OBEYS | OBEYS | Unchanged. |
| LACC #lk[,shift] (0xBF80–0xBF8F) | exec_bf :543 | OBEYS | OBEYS | Unchanged. #lk shift-16 encodability still [UNVERIFIED]. |

E–H subtotal: **6 OBEYS / 1 VIOLATES / 2 PARTIAL** (unchanged from 05).

### 2.3 I–R (45 forms; 05b basis)

| Form | New-core lines | Verdict | Old | Note |
|---|---|---|---|---|
| LACL dma (0x69) | :358 | OBEYS | OBEYS | Unchanged. 06c PDF pp.269–271/6-117–6-119. |
| LACL #k (0xB9) | :430 | OBEYS | OBEYS | Unchanged. |
| LACT dma (0x6B) | :360 | OBEYS | OBEYS | Unchanged. 06c PDF pp.272–273/6-120–6-121. |
| LAMM dma (0x08) | :309 | OBEYS | OBEYS | Unchanged. 06c PDF pp.274–275/6-122–6-123. |
| LAR dma (0x00–0x07) | :307 | **OBEYS** | PARTIAL | **FIXED** — NDX mirror via run-loop hook :592 (T5: LAR AR0,#0x10 gives AR0=INDX=ARCR=0x0010). §6.3 LAR + §5.2.1 (05, PDF p.136/5-6). Residual edge: 06b-N2. Same-AR net value still correct (05b §1). |
| LAR #k (0xB0–0xB7) | :427–428 | **OBEYS** | PARTIAL | **FIXED** — same hook (T5). Residual edge: 06b-N2. |
| LAR #lk (0xBF08–0xBF0F) | exec_bf :531 | **OBEYS** | PARTIAL | **FIXED** — same hook. Residual edge: 06b-N2. |
| LDP dma (0x0D) | :316 | OBEYS | OBEYS | Unchanged. 06c PDF pp.279–281/6-127–6-129. |
| LDP #k (0xBC–0xBD) | :433–434 | OBEYS | OBEYS | Unchanged. |
| LMMR dma,#addr (0x89) | :384–385 | PARTIAL | PARTIAL | **Unchanged** — `ea()` re-evaluated per repeat iteration (#14) + zero execution as first instruction after reset (#2). RPT cycle count not charged here: manual RPT table is 2n and the distilled text does not pin the n-convention (executions vs RPTC) — cycle worker's item. §6.3 LMMR, 06c PDF pp.282–284/6-130–6-132. |
| LPH dma (0x75) | :370 | OBEYS | OBEYS | Unchanged. |
| LST #0 (0x0E) | :317 | PARTIAL | PARTIAL | **Unchanged** — `ea()` → `upd_arp()` corrupts ARB (T6: ARB 1→2). §6.3 LST, 06c PDF p.287/6-135: "LST #0 does not affect ARB". See §5 #21. |
| LST #1 (0x0F) | :318–319 | OBEYS | OBEYS | Unchanged. |
| LT dma (0x73) | :368 | OBEYS | OBEYS | Unchanged (`set_t0` TRM mirror is specified here). |
| LTA dma (0x70) | :365 | OBEYS | OBEYS | Unchanged. |
| LTD dma (0x72) | :367 | PARTIAL | PARTIAL | **Unchanged** — DMOV side effect unconditional (see §5 #16). LTA part correct. |
| LTP dma (0x71) | :366 | OBEYS | OBEYS | Unchanged. |
| LTS dma (0x74) | :369 | OBEYS | OBEYS | Unchanged. |
| MAC pma,dma (0xA2) | :399–403 | **PARTIAL** | OBEYS | **DEMOTED on loop-cycle counts (convention extension, §0).** Semantics unchanged and correct (order, signed multiply, TRM mirror as specified, `do…while` immune to #2). Cycles, steady state, internal memory: single 2 vs manual 3 (U-test: NOP+MAC total 3 vs 4); RPT n+2 = manual n+2 (T11b: total 5). §6.3 MAC, 06c PDF pp.301–304/6-149–6-152. |
| MACD pma,dma (0xA3) | :399–403 | PARTIAL | PARTIAL | Still PARTIAL on #16 (unconditional `dm_wr(a+1,…)` :402); **plus** single cycles 2 vs manual 3 (U-test: total 3 vs 4). RPT n+2 correct. §6.3 MACD, 06c PDF pp.305–309/6-153–6-157. |
| MADD dma (0xAB) | :416–420 | PARTIAL | PARTIAL | Two of three old deviations **fixed**: BMAR writeback gated (:420; T4 BMAR stays 0x2000) and TRM mirror removed (N-1 fixed; T4 TREG1/TREG2 preserved). Remaining: DMOV side effect on MMR/external (#16) + RPT cycles n+2 vs manual n+1 (T11c: total 6 vs 5). Single cycles 2 = manual 2. §6.3 MADD, 06c PDF pp.310–313/6-158–6-161 ("Affected by: OVM and PM" — no TRM). |
| MADS dma (0xAA) | :416–420 | PARTIAL | PARTIAL | Both semantic deviations **fixed** (BMAR writeback, TRM mirror). **Remaining driver is now RPT cycles only:** n+2 vs manual n+1 (same loop shape as MADD, T11c). Single cycles 2 = manual 2 (U-test: total 4). §6.3 MADS, 06c PDF pp.314–317/6-162–6-165. |
| MAR dma (0x8B) | :387 | **OBEYS** | PARTIAL | **FIXED** — NDX mirror via hook :592 (T5d: MAR *+ on AR0=0x10 gives AR0=INDX=ARCR=0x0011). §6.3 MAR, 06c PDF pp.318–319/6-166–6-167 ("Affected by: NDX"). Residual edge: 06b-N2. |
| MPY dma (0x54) | :336 | OBEYS | OBEYS | Unchanged. |
| MPY #k13 (0xC0–0xDF) | :451 | OBEYS | OBEYS | Unchanged. |
| MPY #lk (0xBE80) | exec_be :509 | OBEYS | OBEYS | Unchanged. |
| MPYA dma (0x50) | :332 | OBEYS | OBEYS | Unchanged. |
| MPYS dma (0x51) | :333 | OBEYS | OBEYS | Unchanged. |
| MPYU dma (0x55) | :337 | OBEYS | OBEYS | Unchanged. |
| NEG (0xBE02) | exec_be :461 | OBEYS | OBEYS | Unchanged. |
| NMI (0xBE52) | exec_be :504 | PARTIAL | PARTIAL | **Unchanged** — `push(c, c->pc); c->pc = 0x24` with no `intm = 1`. §6.3 NMI, 06c PDF p.331/6-179: Execution lists `1 → INTM`. IPTR remap of 0x24 still [UNVERIFIED] (open split, 05 §2 #27). |
| NOP (0x8B00) | :387 | OBEYS | OBEYS | Unchanged. |
| NORM {ind} (0xA0) | :396–397 | PARTIAL | PARTIAL | **Half fixed.** ACC=0 → TC=1 fixed (:396 `if (c->acc == 0 && !(c->legacy & 1)) t = 1`; T1 TC=1). **Remaining:** `ea(c)` still runs unconditionally before the test, so the AR is modified on the terminal/normalized iteration and on every RPT repeat (T1/T1b: AR0 0x0100→0x0106 under RPT #5). §6.3 NORM, 06c PDF pp.333–335/6-181–6-183: ACC=0 branch has no AR step; "no operation is performed for the remainder of the repeat loop". See §5 #23. |
| OPL DBMR (0x59) | :342 | OBEYS | OBEYS | Unchanged. |
| OPL #lk (0x5D) | :346 | OBEYS | OBEYS | Unchanged. |
| OR dma (0x6D) | :362 | OBEYS | OBEYS | Unchanged. |
| OR #lk[,shift] (0xBFC0–0xBFCF; incl. #lk,16 0xBE82) | exec_bf :547; exec_be :511 | OBEYS | OBEYS | Unchanged. One §6.3 form on the 05 basis (the ,16 encoding is a sub-encoding of this form; 06a counts it as a separate table row — see 05b §3). |
| ORB (0xBE13) | exec_be :472 | OBEYS | OBEYS | Unchanged. |
| OUT dma,PA (0x0C) | :315 | PARTIAL | PARTIAL | **Unchanged** — port re-fetched, never incremented under RPT (#30). §6.3 OUT, 06c PDF pp.343–344/6-191–6-192. |
| PAC (0xBE03) | exec_be :462 | OBEYS | OBEYS | Unchanged. |
| POP (0xBE32) | exec_be :490 | OBEYS | OBEYS | Unchanged. |
| POPD dma (0x8A) | :386 | OBEYS | OBEYS | Unchanged. |
| PSHD dma (0x76) | :371 | OBEYS | OBEYS | Unchanged. |
| PUSH (0xBE3C) | exec_be :493 | OBEYS | OBEYS | Unchanged. |
| RET (0xEF00) | :442 | OBEYS | OBEYS | Unchanged (unconditional RETC encoding; OV-clear not triggered since `op & 2` = 0). |

I–R subtotal: **35 OBEYS / 0 VIOLATES / 10 PARTIAL** (was 32 / 0 / 13).
PARTIAL drivers remaining: LMMR (#14 + #2), LST #0 (#21), LTD (#16),
MAC (single cycles), MACD (#16 + single cycles), MADD (#16 + RPT
cycles), MADS (RPT cycles), NMI (missing INTM←1), NORM (AR overshoot),
OUT (#30).

## 3. What changed vs the old core, in range (diff summary)

Byte-identical in range: all of `ea()` (:222–240), `upd_ar()` (:214–218),
`do_add`/`do_sub` (:195–209), `ext()`, `pscale()`, `cond()`, `set_t0()`
(:211), SMMR (:310–311), LMMR (:384–385), LST (:317–319), SUBC (:312–313),
DMOV (:372), LTD/MACD side effects, IN (:426), OUT (:315), IDLE/IDLE2
(:487–488), NMI (:504), all A–D/I–R arithmetic and PLU forms. Changed:

- **NDX mirror added** — `c5x_run()` :592–593: after each `exec1()`,
  `if (!c->ndx && !(c->legacy & 64) && c->ar[0] != c->ar0_prev)
  { c->indx = c->arcr = c->ar[0]; }`, with `ar0_prev` tracked at :45/:593.
  This is what fixes LAR ×3, MAR, ADRK. Scope note: the hook fires on
  any AR0 change from any instruction (including `*0±`/`*BR0±` indirect
  updates and MMR writes to AR0's address), which matches §5.2.1's "every
  AR0 modification or LAR write" (05, PDF p.136/5-6). It does not fire
  when the value is unchanged (06b-N2) and runs once per `c5x_run`
  iteration, not per `exec1()` inside delay slots (06b-N2).
- **BMAR writeback gated** — BLDP :340, BLPD-BMAR :405, MADD/MADS :420,
  BLDD-BMAR :422/:424: `if (c->legacy & 128) c->bmar = pfc;`.
- **MADD/MADS TREG load** — :417: `if (c->legacy & 16) set_t0(c, d);
  else c->treg0 = d;`. MAC/MACD/LT/LTA/LTD/LTP/LTS keep `set_t0()` (their
  entries specify the mirror).
- **CRGT/CRLT signed** — :480–481: `(int32_t)` compare by default.
- **NORM ACC=0** — :396: `if (c->acc == 0 && !(c->legacy & 1)) t = 1;`.
  The `ea(c)` call on the same line is unchanged and unconditional.
- **`ivec[]` corrected** — :281: `{0x02,0x04,0x06,0x08,0x0A,0x0C,0x0E,
  0x10,0x12,…}` (was +0x10 high for indices 3–8). `check_int()` (:285–289)
  now dispatches TINT/RINT/XINT/TRNT/TXNT/INT4 to the right vectors;
  INTR's `ivec_ind` save path now matches for K=4–9.
- **`delay_slot()` op restore + cycle reset** — :262–268: saves/restores
  `c->op` and, when `cyc_model`, resets `c->cycles` to the pre-slot value.
  Default (`cyc_model = 0`) behaviour unchanged; under `cyc_model` the
  slot words now cost 0 and the branch's table value governs (the stated
  intent). No A–R form changes verdict on this.
- **`rep_cont` / `words` bookkeeping** — :36/:595–596 and the cycle block
  :584–593. No semantic change by default; repeat handling still has no
  non-repeatable whitelist (#7).

## 4. Legacy-bit table (default `legacy = 0` is the judged behaviour)

`c5x_set_legacy()` :613. Bits observed in the new core (the brief listed
&1, &4, &16, &64, &128; &8 and &32 also exist):

| Bit | Default (`legacy = 0`) | With bit set (old behaviour re-enabled) | Assessment |
|---|---|---|---|
| 1 (&1) NORM | ACC=0 → TC=1 (manual-correct) | Old: TC=0, shift (manual-wrong) | Re-enables #23's ACC=0 half. Manual-wrong, as expected (deliberate compat). |
| 4 (&4) CRGT/CRLT | Signed compare (manual-correct) | Unsigned compare (manual-wrong) | Re-enables #17. Manual-wrong, as expected. |
| 8 (&8) TIM reset | TIM = 0xFFFF on reset | TIM = 0 on reset | Out of this worker's range (peripherals worker owns the reset-value verdict, 05 #12); recorded for completeness. |
| 16 (&16) MADD/MADS TRM | TREG0 only, no mirror (manual-correct per §6.3) | `set_t0()` mirror to TREG1/TREG2 (manual-wrong for MADD/MADS) | Re-enables N-1. Manual-wrong, as expected. Note: for MAC/MACD/LT-family the mirror stays on regardless — correct, their entries specify it. |
| 32 (&32) INTM/XF shadow | `restore_ctx()` does NOT restore INTM/XF (manual-correct, §4.8.8) | Restores them (manual-wrong) | RETI/RETE are S–Z; noted for the S–Z worker. |
| 64 (&64) NDX mirror off | Mirror on (manual-correct when NDX=0) | Mirror disabled (manual-wrong) | Re-enables #10. Manual-wrong, as expected. |
| 128 (&128) BMAR writeback | BMAR not written back (manual-correct) | Writeback re-enabled (manual-wrong) | Re-enables #15. Manual-wrong, as expected. |

No legacy bit gates #7, #14, #16, #21, #22, #24, #30, IDLE2, or NMI's
missing INTM←1 — those are present at every `legacy` value.

## 5. Prior-findings verdicts for the NEW core

| # | Finding | Verdict | New-core evidence |
|---|---|---|---|
| 7 | RPT repeats non-repeatables | **STILL PRESENT** | `c5x_run()` :595–596 repeats whatever follows RPT; `rep_cont` added but no whitelist. Non-repeatables in range: ADD/AND/APL/CPL #lk, BLDD/BLPD #lk, LACC #lk, LAR #k/#lk, LDP #k, MPY #k/#lk, OR #lk, NMI, RET, INTR, IDLE/IDLE2, B/CALL/BCND/CC (§6.3 "not repeatable" per form). Per-form verdicts follow the 05 convention (recorded once globally). |
| 10 | NDX=0 mirror missing (LAR/MAR/ADRK) | **FIXED** (with residual edge) | Hook :592–593; T5/T5c/T5d pass. Residual: same-value loads missed + delay-slot staleness → new finding 06b-N2 (LOW). `legacy & 64` re-enables the old gap. |
| 14 | SMMR/LMMR `ea()` re-evaluated per iteration | **STILL PRESENT** | LMMR :385 `a = ea(c)` inside the `while` loop; SMMR :311 same shape (S–Z worker owns SMMR's verdict; the code is identical in structure). §6.3 SMMR/LMMR execution blocks have no AR-modify step. |
| 15 | BMAR written back by block moves | **FIXED** | Gated behind `legacy & 128` at :340 (BLDP), :405 (BLPD), :420 (MADD/MADS), :422/:424 (BLDD). T3: BLDP leaves BMAR=0x2000. `legacy & 128` re-enables it. |
| 16 | DMOV side effect on MMR/external | **STILL PRESENT** | DMOV :372, LTD :367, MACD :402, MADD :419 — all `dm_wr(a+1, d)` unconditional. T7: DMOV 0x10 copies AR0→AR1. §6.3 DMOV (06b PDF pp.256–257/6-104–6-105). |
| 17 | CRGT/CRLT unsigned | **FIXED** | Signed `(int32_t)` compare :480–481 by default; T2/T2c pass incl. equality C rules. `legacy & 4` re-enables unsigned. |
| 21 | LST #0 corrupts ARB | **STILL PRESENT** | :317 via `ea()` → `upd_arp()` :220 sets `arb = old arp` whenever the indirect field carries a next-ARP bit. T6: ARB 1→2. §6.3 LST (06c PDF p.287/6-135). |
| 22 | `*BRO±` circular wrap missing | **STILL PRESENT** | `ea()` :231/:234 compute the bit-reversed update directly, bypassing `upd_ar()` (:214–218) and its CBCR wrap. Unchanged. §5.6 (05). |
| 23 | NORM misses ACC==0 | **PARTIALLY FIXED** | ACC=0 half fixed (:396; T1 TC=1). AR-overshoot half still present: `ea(c)` runs unconditionally, so under RPT the AR advances on terminal/normalized iterations (T1/T1b AR0 0x0100→0x0106). `legacy & 1` re-enables the ACC=0 half. |
| 24 | SUBC never updates OV/C | **STILL PRESENT** | :312–313 computes the conditional subtract but touches neither C nor OV. T8: borrow case leaves C=1 (manual: C cleared on borrow). §6.3 SUBC (06d): "SUBC affects the OV bit… The C bit is cleared, if the result of the subtraction generates a borrow; otherwise, the C bit is set." (SUBC is S–Z range; verdict given here per the task brief.) |
| 30 | RPT IN/OUT same port | **STILL PRESENT** | IN :426 re-fetches the same port word per repeat; OUT :315 same shape. T10: two reads both hit port 0x100 (manual: 0x100 then 0x101). §6.3 IN/OUT. |
| N-1 | MADD/MADS apply TRM=0 TREG1/TREG2 mirror | **FIXED** | :417 loads TREG0 only by default; T4: TREG1/TREG2 keep 0x1111 across MADD. `legacy & 16` re-enables the mirror. |
| N-8 (DMOV part) | DMOV family: SARAM extra cycle + external DMOV ungated | **Memory-gating half STILL PRESENT; cycle half NOT VERIFIABLE here** | Gating: see #16 (all four DMOV sites unconditional). Cycle half (SARAM extra cycle, §8.7.1, 08 PDF pp.493–494/8-26–8-27): default `cyc_model = 0` charges 1 + 1/iter regardless of where `a` points; the `cyc_model = 1` path needs the missing `c5x_cyctab.h` (06b-N1) — cycle-model worker owns the cycle half. |
| 6 | CALAD missing + BE3D phantom (withdrawn) | **Still fine** | CALAD 0xBE3D implemented at exec_be :494; T12 reaches PC=0x301 via CALAD. 0xBE31 falls through to the `exec_be` default → RUN_BADOP. No change. |

## 6. New findings in A–R (this pass)

### 06b-N1 — HIGH (build): the new core does not compile as delivered
`c5x_core-2.c` :10 `#include "c5x_cyctab.h"`, and no file of that name
exists anywhere under `~` (searched `~/workspace`, `/tmp`, whole home).
`gcc -O2 -shared -fPIC -o libc5x.so c5x_core-2.c` fails with `fatal
error: c5x_cyctab.h: No such file or directory`. The table is referenced
only in the `cyc_model` block (:585 `cyc_tab[c->op]`), so default
behaviour is unaffected — but no `cyc_model = 1` behaviour can be built
or executed from the delivered files, and every cycle-model claim in
this pass is therefore static analysis, not measurement. The file's own
build comment (:6) still says `c5x_core.c`. The header must be shipped
with the core (or the include dropped) before the cycle worker can
verify anything about `cyc_model`.

### 06b-N2 — LOW: NDX mirror is change-triggered; same-value AR0 loads are missed
The hook (:592) fires only when `c->ar[0] != c->ar0_prev`. A LAR/ADRK/
MAR/`*0±` operation that leaves AR0 numerically unchanged therefore
does not mirror, although §5.2.1 (05, PDF p.136/5-6) requires the write
on "every AR0 modification or LAR write". Measured (T5b): AR0=0x0010,
INDX preset to 0x0055, `LAR AR0,#0x10` → INDX stays 0x0055 (manual:
0x0010); ARCR was already 0x0010 from the first LAR, so only INDX is
observably stale here. A second, inspection-only half: the hook runs
once per `c5x_run` iteration, not per `exec1()`, so a delay-slot
instruction that loads AR0 does not update INDX/ARCR until the whole
delayed branch returns — a later slot word using `*0±` reads the stale
INDX. Third, harness-only: `c5x_set(S_AR0, …)` desyncs `ar0_prev`, so the
next executed instruction can spuriously mirror (observed while writing
T5b; real firmware, which changes AR0 only through instructions, is not
affected). Fourth, `ar0_prev` is never reset: `c5x_reset()` (:75–86)
zeroes the ARs but not `ar0_prev`, so after a reset that follows AR0≠0
the first executed instruction spuriously mirrors INDX=ARCR=0 — the
same item the CPU worker recorded independently as 06d-N2 (not
double-counted here; listed as a sub-point of this finding). Fix
direction: mirror at the AR0-write sites (LAR/MAR/`ea()`/
`upd_ar` when the target is AR0) instead of by post-hoc change
detection. Judgment call recorded for the merger: this residual is
narrow (it needs a load of the identical value, or a delay-slot
sequence), so LAR/MAR/ADRK are verdict­ed OBEYS with this finding
attached rather than kept PARTIAL.

### 06b-N3 — LOW: MAC/MACD single cycles 2 vs 3; MADD/MADS RPT cycles n+2 vs n+1
Measured steady-state (internal memory, default model): MAC single
delta 2 vs manual 3; MACD single 2 vs 3; MADD RPT #2 delta 4 vs manual
3; MADS RPT #2 delta 4 vs manual 3 (T11a–c, U-tests). MAC RPT n+2 and
MADD/MADS single 2 are correct. Root cause is the same loop shape as
05a1 N-1: the `do…while` adds exactly 1 per iteration (:403/:420), so a
single execution can never reach 3 and an RPT run can never reach n+1.
This demotes MAC OBEYS → PARTIAL and is the remaining driver keeping
MADS PARTIAL. (BLDD/BLPD/BLDP numbers are unchanged from 05a1 N-1 and
were re-measured: BLDD #lk single 2 vs 3, BLDD BMAR RPT 4 vs 3.)

### 06b-N4 — LOW (info, no demotion): INTR legacy-vector fallback
New second loop in the INTR path (:521): if the correct-table lookup
misses, it retries against `ivec_legacy[]` (:282, the old +0x10 table),
so `INTR 17` (vector 0x22) can reach the INT4 `ivec_ind` slot when
configured. Manual-wrong (0x22 is a user vector per the §6.3 INTR
K-table, 06b PDF p.263/6-111) but deliberate per the in-code comment
(firmware ROM-stub model) and gated on `ivec_ind` configuration; the
default path is unaffected. INTR stays PARTIAL on the K=1–4 save, not
on this.

### 06b-N5 — Info: legacy-bit inventory beyond the brief
Bits &8 (TIM reset 0 vs 0xFFFF, :84) and &32 (INTM/XF shadow restore,
:278) also exist; bit 1 is unused (comment :613: "XC audit finding was
wrong"). &8 is peripherals territory (05 #12); &32 is RETI/RETE (S–Z).
No other in-range behaviour is legacy-gated.

## 7. Cycle-model note (for the cycle-model worker)

- **Default (`cyc_model = 0`) counting is identical to the old core:**
  1 per `exec1()` (:305) + 1 per loop iteration inside the
  `while`/`do…while` forms. All 05 per-form cycle measurements therefore
  carry over, plus the MAC/MACD/MADD/MADS measurements in §6 (06b-N3)
  and §8. Per-form loop-cycle table (steady state, internal memory):
  BLDD-BMAR single 2 ✓ / RPT n+2 ✗ (manual n+1); BLDD-#lk single 2 ✗
  (manual 3) / RPT n+2 ✓; BLDP single 2 ✓ / RPT n+2 ✗; BLPD-BMAR single
  2 ✓ / RPT n+2 ✗; BLPD-#lk single 2 ✗ / RPT n+2 ✓; MAC single 2 ✗
  (manual 3) / RPT n+2 ✓; MACD single 2 ✗ / RPT n+2 ✓; MADD single 2 ✓
  / RPT n+2 ✗ (manual n+1); MADS single 2 ✓ / RPT n+2 ✗; LMMR single
  2 ✓ / RPT 2n (n-convention ambiguous — not charged, see §2.3).
- **`cyc_model = 1` is unverifiable as delivered** (06b-N1: table
  missing). Structural analysis only: the block adds `cy − 1` (:584–593)
  on top of the 1 + per-iteration counts, so for a loop form with k
  iterations the total is k + cy. No single table value can make both
  the single and the RPT count right for the same form (BLDD-BMAR:
  single needs cy=1, RPT needs cy=0; MAC: single needs cy=2, RPT needs
  cy=1). The table can therefore at best leave loop-form counts as wrong
  as the default model, never fix them; the per-iteration `cycles++`
  would have to go. (The S–Z/cycle worker reached the same structural
  point independently as N-C2-1.) The `rep_cont` path (cy=1 on repeats) makes
  repeated non-loop instructions cost 1 each, which matches the manual's
  RPT tables for 1-cycle forms only.
- **First-instruction-after-reset interaction (measured, not new):** as
  the first instruction after reset (`rptc = -1`, :59/:83), a `while`
  -loop form executes zero times (T9, #2) and a `do…while` form executes
  once but adds no per-iteration cycle (T11a first-run MAC delta 1 vs
  steady-state 2). Both are consequences of #2, not separate findings.

## 8. Empirical checks run for this file

Harness `/tmp/c5x2/test.c` (+ `test2.c` for steady-state cycles),
compiled against the unmodified new core with the stub `c5x_cyctab.h`
(all zeros; never read at `cyc_model = 0`). Breakpoint-stopped runs so
trailing zero-words (`LAR AR0,0`) could not clobber state; AR0 was set
through instructions, not `c5x_set`, so `ar0_prev` stayed in sync.

| Test | Setup | Measured | Manual |
|---|---|---|---|
| T1 | RPT #5; NORM *+, ACC=0 | TC=1, AR0=0x0106 | TC=1, AR0=0x0100 |
| T1b | RPT #5; NORM *+, ACC=0x40000000 | TC=1, AR0=0x0106 | TC=1, AR0=0x0100 |
| T1c | NORM *+, ACC=0, legacy&1 | TC=0 | (old bug re-enabled) |
| T2 | CRGT, ACC=−1 vs ACCB=+1 | both +1, C=1 | both +1, C=1 |
| T2b | CRGT, legacy&4 | both −1, C=0 | (old unsigned bug) |
| T2c | CRLT, ACC=−1 vs ACCB=+1 | both −1, C=0 | both −1, C=0 |
| T3 | BLDP, BMAR=0x2000 | BMAR=0x2000, pmem written | BMAR unchanged |
| T3b | BLDP, legacy&128 | BMAR=0x2001 | (old writeback) |
| T4 | LT 0x1111; MADD | TREG0=0x2222, TREG1=TREG2=0x1111, BMAR=0x2000 | TREG1/2 untouched, BMAR unchanged |
| T4b | MADD, legacy&16 | TREG1=0x2222 | (old mirror) |
| T5 | LAR AR0,#0x10 | AR0=INDX=ARCR=0x0010 | all 0x0010 |
| T5b | LAR AR0,#0x10; SPLK INDX=0x55; LAR AR0,#0x10 | INDX=0x0055, ARCR=0x0010 | INDX=ARCR=0x0010 |
| T5c | ADRK #5, AR0=0x100 | all 0x0105 | all 0x0105 |
| T5d | MAR *+, AR0=0x10 | all 0x0011 | all 0x0011 |
| T5e | LAR AR0,#0x10, legacy&64 | INDX=ARCR=0 | (old gap) |
| T6 | LST #0 with next-ARP, ARB=1/ARP=2 | ARB=2 | ARB=1 |
| T7 | DMOV 0x10 (AR0→AR1, MMR) | AR1=0x1234 | AR1 untouched |
| T8 | SUBC, ACC=0x10000, divisor 0x4000 | ACC=0x20000, C=1, OV=0 | C=0 (borrow) |
| T9 | BLDD BMAR,dma first after reset | 0 words moved | 1 word |
| T10 | RPT #1; IN port 0x100 | 2 reads, both port 0x100 | 0x100 then 0x101 |
| T11a | MAC single (first after reset) | delta 1 | 3 |
| T11b | MAC RPT #2 | total 5 (RPT 1 + MAC 4) | 5 |
| T11c | MADD RPT #2 | total 6 (SPLK 1 + RPT 1 + MADD 4) | 5 |
| T11d | BLDD #lk single (first after reset) | delta 1 (0 words — #2) | 3 |
| T11e | BLDD BMAR RPT #2 | total 6 | 5 |
| T12 | CALAD to 0x300 | PC=0x301 | target reached |
| U1 | MAC single, steady state | total 3 (NOP 1 + MAC 2) | 4 |
| U2 | BLDD #lk single, steady state | total 3 (NOP 1 + BLDD 2) | 4 |
| U3 | BLDD BMAR single, steady state | total 4 (SPLK 1 + NOP 1 + BLDD 2) | 4 |
| U4 | LMMR single, steady state | total 3 (NOP 1 + LMMR 2) | 3 |
| U5 | BLPD BMAR single, steady state | total 4 | 4 |
| U6 | MADS single, steady state | total 4 | 4 |
| U7 | MACD single, steady state | total 3 (NOP 1 + MACD 2) | 4 |

Note on T2/T2b/T2c expectations: the "want" values in the harness
comments were initially mis-stated for the C bit and corrected against
the distilled text before writing this file — CRGT: C=1 iff ACC ≥ ACCB
(06b PDF pp.252–253, incl. the equality case "If (ACC) = (ACCB):
`1 → C`"); CRLT: C=1 iff ACC < ACCB (equality → C=0). The measured
values match the manual in all three tests.

## 9. Manual contradictions and [UNVERIFIED] items (in range, carried over)

No new manual contradiction was found in this range. Carried over from
05/05a1/05a2/05b (unchanged by the new core):

- MADD/MADS cycles: Table 6-7 says 3, §6.3 detailed tables say 2
  (05b MC-1). Normative: §6.3 detailed tables (2). The core counts 2
  single / n+2 RPT by default either way — the single count happens to
  match, the RPT count does not.
- MADD Execution `(PC) + 2 → PC` vs Words = 1 (05b MC-2). Normative:
  Words = 1. Core follows it.
- LACB direction: Table 6-4 "Load ACC to ACCB" vs §6.3 "(ACCB) → ACC"
  (05a2 NEW-N2). Normative: §6.3. Core follows §6.3.
- INTR IFR-clear: §4.8.2 general trap action vs §6.3 INTR "will not
  clear" (05 §5.2). Normative: §6.3. Core correct.
- OUT Execution final line "`(dma) → Port address`" vs the description
  (port increments, dma advances) — recorded as printed in 06c; verdict
  follows the description.
- [UNVERIFIED]: BANZD test timing vs the delay slot (05a1 N-2);
  CC/CCD/BCND/BCNDD OV-clear scope beyond RETC/RETCD/XC (O1, resolved
  for S–Z only in 05 §3 N-12); BLDD/BLPD/BLDP MMR-address restriction
  behaviour on violation (05a1 N-3); INTR IPTR remap; NMI/TRAP IPTR
  remap (open split, 05 §2 #27); LACC #lk shift-16 encodability; LAR
  next-ARP field when the target is the ARP-pointed AR; IN per-repeat
  AR-modify behaviour under indirect addressing; NDX=1 behaviour
  (Ch. 5 silent); LMMR RPT table n-convention (executions vs RPTC —
  new, §2.3).

## 10. Files and reproducibility

- This file: `06b-core2-instructions-a-r.md`.
- Core diff: `diff ~/workspace/user/files/c5x_core.c
  ~/workspace/user/files/c5x_core-2.c` (77 changed lines; the only
  in-range semantic changes are §3).
- Build check: `gcc -O2 -shared -fPIC -o libc5x2.so c5x_core-2.c`
  fails (06b-N1); with stub `/tmp/c5x2/c5x_cyctab.h` it builds and the
  harness `/tmp/c5x2/test.c`, `/tmp/c5x2/test2.c` reproduces §8.
- Nothing was modified except this file (and the one `progress.log`
  line appended with it). The stub header and harnesses live in `/tmp`
  and are not deliverables.
