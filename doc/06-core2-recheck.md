# Re-check — NEW core `c5x_core-2.c` vs the distilled June 1998 manual

Date: 2026-11-15 00:44–01:15 CET (merge 01:20 CET). Coordinator merge of worker
files 06a–06e.
- NEW CORE: `~/workspace/user/files/c5x_core-2.c`, 630 lines, 45,758 bytes, md5
  `7aa4227d47e9f72abee2b4cb48fb5fef` (read-only, never modified by this pass).
- OLD CORE: `~/workspace/user/files/c5x_core.c`, 603 lines, 41,745 bytes, md5
  `41c51be7e2edfb5daeda96ce6c80bbb5`. Diff: **77 changed lines verified
  (52 added + 25 removed, 20 hunks)**.
- MANUAL (authority): distilled files in `~/workspace/research_notes/courier-firmware/c5x_manual/`
  (SPRU056D June 1998, SHA `a31e285f…`). The June 1998 PDF was used as tiebreaker
  only where noted (§9, NDX polarity; TDM scope already settled in 05). The January
  1993 OCR text and derived `c5x_opcodes.*` / `c5x_patterns_fixed.json` were never
  used as authority.
- PRIOR RECORD: `00-consolidated-report.md` (findings #1–#35, corrected 20:47 CET),
  `05-full-reverification.md` (old-core verified coverage: 179 §6.3 forms, 140 obey /
  1 violates / 38 partial / 0 missing / 0 phantom; 20 new findings N-1..N-20;
  per-area behaviour tallies over 427 checks), `c5x_manual/audit-verification.md`.
- WORKERS: 06a diff+build, 06b instructions A–R, 06c instructions S–Z + cycle model,
  06d CPU/registers/addressing/interrupts, 06e peripherals/memory/pipeline/timer/serial.
  Each worker file is the evidence; this file is the verdict record. Disagreements
  between workers are recorded, not hidden (§8).

## Verdict in one paragraph

**The new core does not build as delivered** — line 10 does
`#include "c5x_cyctab.h"` and that header exists nowhere in `~/workspace` or
`/tmp` (verified by three independent searches, including a full-workspace grep;
the only references are the `#include` itself and workers' own compile logs).
That is the single HIGH finding and it blocks every cycle-model claim and every
smoke test. Judged at default behaviour (`legacy=0`, `cyc_model=0`, `xint_mode=0` —
all calloc-zero, none cleared by reset), the diff is a genuine improvement on the
instruction semantics it touches: **148/179 forms obey (was 140), 1 violates
(IDLE2, unchanged), 30 partial (was 38), 0 missing, 0 phantom**. Fixed outright:
#1 vectors, #9 INTM/XF shadow, #15 BMAR writeback, #17 CRGT/CRLT signed, N-1
MADD/MADS TRM mirror. Partially fixed: #5 cycle model (opt-in, unverifiable),
#10 NDX mirror (change-detected, same-value hole), #11 INTR (gate fixed, plain-path
save still missing), #12 reset values (TIM limb only), #23 NORM (ACC=0 limb only).
Everything else in the old audit stands: 24 of #1–#35 still present, 17 of N-1..N-20
still present, peripherals still the weakest area (25/98 obey). The `legacy`
bitmask is honest — every bit re-enables manual-wrong behaviour, none is
accidentally right — but `legacy&8` bundles a timer regression with the
instruction toggles, and the `ivec_legacy` INTR fallback keeps the old wrong-vector
path reachable without any legacy bit. The open IPTR-remap split is carried
forward unresolved (§9).

## 1. Build — FAIL (new core); PASS (old core, control)

- `gcc -O2 -shared -fPIC -o libc5x.so c5x_core-2.c` (gcc 13.3.0):
  `c5x_core-2.c:10:10: fatal error: c5x_cyctab.h: No such file or directory`,
  exit 1, no `.so`. Same with `-Wall -Wextra` — the failure is at line 10, before
  any code is compiled, so no warnings could even be reached.
- Control: old core builds clean under the same commands, 45,688-byte `.so`,
  only the two known `sat_acc_shift()` warnings (06a §1, 06e §5 R1).
- Consequence: **no smoke test T1–T9 was run on the new core** (06a §4 restates the
  audit-04 expectations and code-reading predictions only). All cycle-model claims
  are static analysis, not measurement.
- Method note on what *was* executed: worker 2 (06b) ran its A–R instruction tests
  against the unmodified new core plus a stub header (`static const int
  cyc_tab[65536] = {0}` in `/tmp/c5x2/`, throwaway, not a deliverable) that is
  **never read at `cyc_model=0`**, the judged default — so its A–R verdicts at
  default are execution-backed. Workers 1, 3, 4, 5 are code-reading only. The stub
  does not change the build verdict: as delivered, the core does not compile.
- Minor: the new core's own build comment (line 6) still reads
  `gcc -O2 -shared -fPIC -o libc5x.so c5x_core.c` — the old filename.

## 2. Coverage — 179 §6.3 forms, same basis as 05 §1

| Range | Forms | OBEYS | VIOLATES | PARTIAL | UNVERIFIED | Old (05) |
|---|---|---|---|---|---|---|
| A–D (06b) | 57 | 49 | 0 | 8 | 0 | 46 / 0 / 11 |
| E–H (06b) | 9 | 6 | 1 | 2 | 0 | 6 / 1 / 2 |
| I–R (06b) | 45 | 35 | 0 | 10 | 0 | 32 / 0 / 13 |
| S–Z (06c) | 68 | 58 | 0 | 10 | 0 | 56 / 0 / 12 |
| **Total** | **179** | **148** | **1** | **30** | **0** | **140 / 1 / 38** |

Net +8 OBEYS: 9 forms fixed (CRGT, CRLT, ADRK, LAR dma, LAR #k, LAR #lk, MAR,
RETI, RETE) minus MAC demoted OBEYS → PARTIAL. The single VIOLATES form is still
IDLE2. No form missing, no phantom opcode (0x56, 0xA1, 0xBE31 still BADOP).

Convention note (flagged by 06b, adopted here): 05 charged loop-cycle deviations
per form for the `while`-loop block-move family (05a1 N-1). This pass extends the
same charging to the `do…while` family (MAC/MACD/MADD/MADS), which demotes MAC;
05b had left MAC/MADD cycle counts in its §2 cross-cutting record. All other
multi-cycle forms are charged only to the global cycle model (#5), as in 05.
Per-form loop-cycle table at default (steady state, internal memory): BLDD-BMAR
single 2 ✓ / RPT n+2 ✗ (manual n+1); BLDD-#lk single 2 ✗ (manual 3) / RPT n+2 ✓;
BLDP single 2 ✓ / RPT n+2 ✗; BLPD-BMAR single 2 ✓ / RPT n+2 ✗; BLPD-#lk single
2 ✗ / RPT n+2 ✓; MAC single 2 ✗ (manual 3) / RPT n+2 ✓; MACD single 2 ✗ / RPT
n+2 ✓; MADD single 2 ✓ / RPT n+2 ✗ (manual n+1); MADS single 2 ✓ / RPT n+2 ✗;
LMMR single 2 ✓ / RPT 2n (n-convention ambiguous in the distilled text — not
charged, left to the cycle worker; LMMR stays PARTIAL on #14 + #2 regardless).

## 3. Verdict table — consolidated findings #1–#35 (new core, default)

Verdicts: FIXED / STILL PRESENT / PARTIALLY FIXED / REGRESSED. "Default" =
`legacy=0`, `cyc_model=0`, `xint_mode=0`. Citations are distilled-manual citations;
"06x" = the worker file that established the verdict.

| # | Finding | Verdict | Note / basis |
|---|---|---|---|
| 1 | Vectors TINT/RINT/XINT/TRNT/TXNT/INT4 +0x10 | **FIXED** | `ivec[]` now {02,04,06,08,0A,0C,0E,10,12} (:281); `check_int()` dispatches correctly. §4.8.1 Table 4–14 (04, PDF p.116/4-37); §8.2.2 Table 8–7 (08); §6.3 INTR K-table. 06a §2b, 06d §2.1, 06e §4.2 M18. |
| 2 | Block moves zero times as first insn after reset | **STILL PRESENT** | `rptc = -1` in `c5x_new()` (:59) and `c5x_reset()` (:83); MMR read 0x08 returns 0xFFFF. §4.9 Table 4–15 (04, PDF p.125/4-46). 06d §2.2. |
| 3 | Timer in instruction time | **STILL PRESENT** | `tick_timer()` :558–561 byte-identical, driven once per counted cycle (:597); default model still 1 cycle/insn. `cyc_model=1` is an unmeasurable partial improvement (no clock generator, §9.2 — N-3). 06e §1.1. |
| 4 | Serial tick raises XINT every tick | **STILL PRESENT** at default; PARTIALLY FIXED only under opt-in `xint_mode=1` | Default `!xint_mode` true → XINT every tick (:609). Mode 1 approximates the XRDY 0→1 edge but has a first-tick kick and still ignores SPC reset (see §7, R3). §9.7.1 Table 9–13 (09b, PDF p.538/9-29). 06e §1.1/§3. |
| 5 | Cycle model is an instruction count | **PARTIALLY FIXED** | Default `cyc_model=0`: identical instruction counter — still present by default. `cyc_model=1`: table + taken/not-taken overrides + delay-slot restore exist with the right fastest-case shape, but no table value is verifiable (header absent), wait states / SARAM extras / DMOV extra cycle structurally absent, block moves double-count (§7, N-C2-1), RPT per-iteration ≠ 1 flattened, interrupt entry still 0 cycles. 06c §2. |
| 6 | CALAD missing + BE3D phantom | WITHDRAWN 20:18, still fine | CALAD 0xBE3D at :494; 0xBE31 BADOPs. Tested by 06b (T12: CALAD reaches PC=0x301). |
| 7 | RPT repeats non-repeatables | **STILL PRESENT** | Run loop :595–596 rewinds on any opcode; `rep_cont` added but no whitelist. 06b §5, 06a §7. |
| 8 | RPTB PAER off by one (value wrong, count right) | **STILL PRESENT** | `paer = imm + 1` (:515) unchanged; §6.3 RPTB "pma → PAER" (06d, PDF pp.369–370/6-217–6-218); §4.7 (04, PDF p.110/4-31). Representation note stands. 06c §4. |
| 9 | INTM/XF wrongly shadowed | **FIXED** at default; re-enabled by `legacy&32` | `restore_ctx()` :278 restores INTM/XF only `if (legacy & 32)`. §4.8.8 (04, PDF p.121/4-42). 06d §2.3, 06c §1 #4–5 (RETI/RETE promoted to OBEYS). |
| 10 | NDX=0 mirror missing | **PARTIALLY FIXED** | Run-loop hook :592–593 mirrors on AR0 change when `!ndx && !(legacy&64)`. Residual: same-value LAR writes never mirror; `ar0_prev` never reset; delay-slot deferral (§7, NDX residual). Polarity verified against the PDF — see §9. 06d §2.4, 06b §5. |
| 11 | INTR k incomplete | **PARTIALLY FIXED** | Gate fixed: save now reachable for K=1–9 when `ivec_ind` set (N-10 fixed as a gate). Plain-path save for K=1–4 still missing; IFR non-clear still correct (§6.3 INTR, PDF p.263); IPTR remap [UNVERIFIED]. 06d §2.5, 06b §2.2. |
| 12 | Reset values wrong | **PARTIALLY FIXED** | TIM limb fixed: `tim = 0xFFFF` by default (:84). RPTC (−1), PDWSR/IOWSR/CWSR (never set), GREG (stale, readback never FF00h), DRR/DXR/SPC re-reset staleness still wrong. §4.9 Tables 4–15/4–16 (04, PDF pp.125–127/4-46–4-48). 06d §2.6, 06e §1.1. |
| 13 | OVLY/CNF ignored in data map | **STILL PRESENT** | `dm_internal()` :176 byte-identical; reads neither `ovly` nor `cnf`. §8.3.1 / Table 8–9 (08, PDF pp.482–483/8-15–8-16). 06e §1.1. |
| 14 | SMMR/LMMR re-evaluate `ea()` per iteration | **STILL PRESENT** | `a = ea(c)` inside the `while` loops (:311, :385). §6.3 SMMR/LMMR execution blocks (no AR-modify step). 06b §5, 06c §4. |
| 15 | BMAR written back by block moves | **FIXED** at default; re-enabled by `legacy&128` | Writeback gated at all five sites (:340, :405, :420, :422, :424). §6.3 BLDD/BLDP/BLPD/MADD/MADS (no BMAR assignment). 06a §2c, 06b §5 (T3). |
| 16 | DMOV side-effect on MMR/external | **STILL PRESENT** | `dm_wr(a+1,…)` unconditional at :372 (DMOV), :367 (LTD), :402 (MACD), :419 (MADD). §6.3 DMOV (06b, PDF pp.256–257/6-104–6-105). 06b §5 (T7), 06e §1.2 N-8. |
| 17 | CRGT/CRLT unsigned | **FIXED** at default; re-enabled by `legacy&4` | Signed `(int32_t)` compare :480–481. §6.3 CRGT/CRLT "larger/smaller value (signed)" (06b, PDF pp.252/254). 06a §2c, 06b §5 (T2/T2c incl. equality C-rules). |
| 18 | XC k=1 skips opcode words | **STILL PRESENT** | `c->pc += n` (:438–439) unchanged; only a comment added, which rationalises rather than fixes. §6.3 XC (06d, PDF pp.430–431/6-278–6-279); §4.5.6 (04, PDF pp.99–100/4-20–4-21). 06c §4. |
| 19 | SPC RRST/XRST ignored; read-only bits leak | **STILL PRESENT** | `mmr_wr()` case 0x22 stores raw (:163); `mmr_rd()` masks only bits 11/10 (:144). §9.7.1 Table 9–13 (09b, PDF pp.537–540/9-28–9-31). 06e §1.1. |
| 20 | IDLE/IDLE2 conflated | **STILL PRESENT** | Both `c->idle = 1` (:487–488); idle loop treats them identically. §6.3 IDLE2 (06b, PDF p.260/6-108); §4.10 (04, PDF p.129/4-50). Sole VIOLATES form. 06b §2.2, 06c §4. |
| 21 | LST #0 corrupts ARB | **STILL PRESENT** | `ea()` → `upd_arp()` (:317, :220). §6.3 LST (06c, PDF p.287/6-135). 06b §5 (T6). |
| 22 | `*BRO±` circular wrap missing | **STILL PRESENT** | `ea()` :231/:234 bypass `upd_ar()`/CBCR wrap. §5.6 (05). 06b §5. |
| 23 | NORM misses ACC==0 | **PARTIALLY FIXED** | ACC=0 → TC=1 fixed (:396). AR overshoot remains: `ea(c)` runs unconditionally, so the AR advances on terminal/normalized RPT iterations (06b T1: AR0 0x0100→0x0106 under RPT #5). §6.3 NORM (06c, PDF pp.333–335/6-181–6-183). 06b §5, 06d §5.1 D5. |
| 24 | SUBC never updates OV/C | **STILL PRESENT** | :312–313 touches neither C nor OV. §6.3 SUBC "Affects: C and OV" (06d, PDF pp.417–418/6-265–6-266). 06b §5 (T8). |
| 25 | CLRC-INTM shadow missing | **STILL PRESENT** (CLRC half); RETE half [UNVERIFIED] | No shadow counter/flag anywhere; `check_int()` :598 runs after every `exec1()`. §4.8.9 (04, PDF p.123/4-44). 06d §2.12. |
| 26 | Delay-slot stack ordering | **STILL PRESENT** | RETCD/RETD still `pop()` before `delay_slot()`; CCD/CALLD still `push()` before it. Op/cycle restore (:266–267) does not touch stack order. 06c §4. |
| 27 | NMI missing `intm=1`; TRAP/NMI IPTR remap | **STILL PRESENT** (`intm=1`); IPTR half **carried open** (§9) | `:504` `push; pc = 0x24` with no `intm = 1`. §6.3 NMI (06c, PDF p.331/6-179). 06d §2.7. |
| 28 | Register widths unmasked | **STILL PRESENT** (narrowed as in 05) | No diff line touches any width/masking; TREG1 5-bit / TREG2 4-bit readback-only, CBCR/GREG/CWSR/IMR/IFR unmasked. 06d §2.8. |
| 29 | Reserved addresses as RAM; TDM regs absent | **STILL PRESENT** (both halves) | Reserved MMR + TDM regs 30h–37h still fall through to `mmr_raw[]` RAM. §9.1.1 Table 9–1 (09a, PDF pp.511–513/9-2–9-4); §9.9 (09b, PDF p.583/9-74). 06e §1.1. |
| 30 | RPT IN/OUT same port | **STILL PRESENT** | IN :426 / OUT :315 re-fetch the same port per repeat (06b T10: both reads hit port 0x100). §6.3 IN/OUT. 06b §5. |
| 31 | Block-repeat lockout; CALA/CALL push; BRCR 0xFFFF | **STILL PRESENT** (lockout + BRCR; CALA/CALL narrowed as in 05) | No block-repeat interrupt guard; `brcr--` unconditional at wrap (:577) so BRCR reads 0xFFFF after completion. §4.7.2 (04, PDF pp.113–114/4-34–4-35); §4.7 (04, PDF p.110/4-31). 06c §4. |
| 32 | `c5x_set` no S_ST1/S_PMST | **STILL PRESENT** | `c5x_set()` :109–118 has no `case S_ST1` / `case S_PMST` (enum defines both; `c5x_get()` reads both). Byte-identical. 06d §2.9. |
| 33 | Host window 0xFF50–0xFF5F not a manual feature | **STILL PRESENT** | `dm_hostwin()` :177, byte-identical. Table 8–9 (08, PDF p.483/8-16). 06e §1.1. |
| 34 | MPMC/ROM mapping unmodelled | **STILL PRESENT** | `pm_ptr()` :180–184 has no MP/MC branch; `mpmc` never read anywhere. Table 8–2 (08, PDF p.476/8-9). 06e §1.1. |
| 35 | Build: only warning dead `sat_acc_shift()` | **REGRESSED** | The old core built (45,688-byte `.so`, two warnings). The new core does not build at all (§1). `sat_acc_shift()` is still present and dead (:296), but unreachable — the build failure supersedes the warning. |

Score over #1–#35 (excluding #6, withdrawn): **4 FIXED (#1, #9, #15, #17),
5 PARTIALLY FIXED (#5, #10, #11, #12, #23), 24 STILL PRESENT, 1 REGRESSED
(#35)**. #4 is counted in STILL PRESENT at default (partial only under opt-in
`xint_mode=1`).

## 4. Verdict table — new findings N-1..N-20 (new core, default)

| ID | Finding (05 severity) | Verdict | Note |
|---|---|---|---|
| N-1 | MADD/MADS TRM=0 TREG1/TREG2 mirror (MED) | **FIXED** | `:417` loads TREG0 only by default. §6.3 MADD/MADS "Affected by: OVM and PM" only. 06b §5 (T4), 06d §2.13. |
| N-2 | Serial IFR flags auto-cleared on trap (MED) | **STILL PRESENT** | `check_int()` :287 clears unconditionally, incl. RINT/XINT/TRNT/TXNT. §4.8.2 excepts "an interrupt flag (other than from an active serial port)" (04, PDF p.117/4-38). 06e §1.2, 06d §8. |
| N-3 | No clock-generator model at all (MED) | **STILL PRESENT** | No CLK/PLL/CLKOUT symbol anywhere. §9.2 (09a, PDF pp.516–517/9-7–9-8). 06e §1.2. |
| N-4 | TDM port entirely unmodelled (MED) | **STILL PRESENT** | No TDM symbol anywhere; regs 30h–35h fall through to `mmr_raw[]`. §9.9 (09b, PDF pp.583–595/9-74–9-86). 06e §1.2. Vector half improved (ivec[6]=0x0E, ivec[7]=0x10) but nothing raises IFR bits 6/7. |
| N-5 | `serial_tick` ignores SPC reset state (MED) | **STILL PRESENT** (both XINT modes) | :605–610 never reads `c->spc`. §9.7.1 Table 9–13 RRST/XRST (09b, PDF pp.538–539/9-29–9-30). 06e §1.2. |
| N-6 | Ex. 7–6 divergence ACC=30h/AR2=62h vs 90h/64h (MED) | **STILL PRESENT** | `ea()`/`mmr_wr()`/SAMM byte-identical; re-traced by code reading, same result. §7.2.3 Ex. 7–6 (07, PDF pp.457–458/7-15–7-16). 06e §1.2. |
| N-7 | TRAP/NMI absolute vectors vs §8.2.2 IPTR rule (MED) | **Carried open, not adjudicated** (§9) | Core unchanged (:503–504). 06d §2.10. |
| N-8 | DMOV SARAM extra cycle + external gate (MED) | **STILL PRESENT** | No SARAM cycle term; `dm_wr(a+1,…)` ungated for MMR/external. §8.7.1 (08, PDF pp.493–494/8-26–8-27). 06b §5, 06e §1.2. |
| N-9 | Interrupt entry costs 0 cycles (MED) | **STILL PRESENT** | `check_int()` adds nothing, in both `cyc_model` modes. Floor 4 cycles (§7.2.2, 07, PDF p.448/7-6; App. B class X). 06c §4, 06d §8. |
| N-10 | INTR shadow save gated on wrong `ivec[]`, dead for K=4–9 (MED) | **PARTIALLY FIXED** | Gate now matches for K=1–9 when `ivec_ind` set (:520). Plain-path save still missing — same #11 defect. 06d §2.11. |
| N-11 | Block-move cycle counts uniformly words+1 (LOW) | **STILL PRESENT** | Default mode unchanged; `cyc_model` mode still wrong, different numbers (§7, N-C2-1). 06c §4. |
| N-12 | OV-clear over-extended to RETC/RETCD/XC (LOW) | **STILL PRESENT** | `if (op & 2) c->ov = 0` unchanged on all three paths. §6.3 RETC/RETCD/XC "Status bits: None affected". 06c §4. |
| N-13 | XC + following-two-words interrupt window (LOW) | **STILL PRESENT** | No window state; `check_int()` :598 runs after every `exec1()`. §6.3 XC (06d, PDF pp.430–431/6-278–6-279). 06c §4. |
| N-14 | SETC INTM same missing shadow as CLRC INTM (LOW) | **STILL PRESENT** | `:495` no shadow mechanism. §4.8.9 (04, PDF p.123/4-44). 06d §2.12. |
| N-15 | BIO pipeline test points unmodelled (LOW) | **STILL PRESENT** | `tp_cond()` :257 samples BIO at execution for all. §9.5.1 (09a, PDF p.529/9-20). 06e §1.2. |
| N-16 | No READY input (LOW) | **STILL PRESENT** | No READY symbol anywhere. §9.4.1 (09a, PDF p.524/9-15). 06e §1.2. |
| N-17 | DXR write clears XRDY even with XRST=0 (LOW) | **STILL PRESENT** | `mmr_wr()` case 0x21 :163 unconditional. §9.7.1 Table 9–13 XRST (09b, PDF p.539/9-30). 06e §1.2. Interacts with `xint_mode=1` (manufactures a pending transmit — §7 R3). |
| N-18 | GREG reset readback FF00h vs core 0000h (LOW) | **STILL PRESENT** | `mmr_rd()` case 0x05 :138 returns full stored 16 bits; `greg` never touched by reset. §8.4.1 (08, PDF p.487/8-20). 06e §1.2. |
| N-19 | Reserved data addresses as external SRAM (LOW) | **STILL PRESENT** | 0080h–00FFh / 0500h–07FFh fall through to `pmem[]`. §8.3.1 (08, PDF p.482/8-15). 06e §1.2. |
| N-20 | AVIS bit stored but never used (LOW) | **STILL PRESENT** | Same six sites as old core. §8.2.3 (08, PDF p.480/8-13). 06e §1.2. |

Score over N-1..N-20: **1 FIXED (N-1), 1 PARTIALLY FIXED (N-10), 17 STILL
PRESENT, 1 OPEN (N-7)**.

## 5. Behaviour tallies re-run (same basis as 05 §4, overlapping per-area counts)

| Area | Checks | OBEYS | VIOLATES | PARTIAL | UNVERIFIED | Old (05) |
|---|---|---|---|---|---|---|
| CPU / registers / addressing / stack (06d) | 151 | 109 | 18 | 16 | 8 | 104 / 25 / 14 / 8 |
| Interrupts / program control / reset (06d) | 62 | 30 | 10 | 16 | 6 | 27 / 12 / 17 / 6 |
| Peripherals (06e) | 98 | 25 | 50 | 21 | 2 | 24 / 50 / 22 / 2 |
| Memory / pipeline / cycles (06e) | 116 | 30 | 61 | 15 | 10 | 28 / 63 / 15 / 10 |
| **Total (overlapping)** | **427** | **194** | **139** | **68** | **26** | **183 / 150 / 68 / 26** |

Net: +11 obey, −11 violates, partial and unverified unchanged. Flips: CPU — B10
(TIM/PRD reset), C21 (CRGT/CRLT), D5 (NORM → partial), F1 (NDX mirror → partial),
I13 (BMAR writeback), J1 (vectors), J9 (INTM/XF shadow); interrupts — B04
(vectors), B14 (RETI/INTM), B17 (INTM/XF save); peripherals — P-05 (TIM/PRD
reset); memory — M18 (vectors), M32 (TIM reset). Peripherals remain the weakest
area (25/98 obey — no time base, no serial state machine, no wait states, no TDM);
memory/pipeline is wrong on nearly every latency (pipeline 3/32 obey, cycles
13/34 obey, unchanged).

## 6. The `legacy` bitmask and the opt-in modes

`c5x_set_legacy()` (:613) overwrites the whole mask (`c->legacy = m`, it does not
OR bits in). `legacy` is zero at creation (`calloc`) and **not cleared by
`c5x_reset()`** — it persists across resets, so the TIM-reset gate reads the bit
at reset time and one setter call poisons every subsequent reset. Default
`legacy=0` is the audit-fixed behaviour for every defined bit. **Every bit
re-enables manual-wrong behaviour; none is accidentally right** (all five workers
agree). Bits are independent and combinable; bits above bit 7 are accepted and
ignored (no code reads them).

| Bit | Site (new-core lines) | Default `legacy=0` | With bit set (old behaviour re-enabled) |
|---|---|---|---|
| 0 (1) | NORM ACC==0 — :396 | ACC=0 → TC=1, no shift. Fixes #23's ACC=0 half. | Old bug: TC=0, shift. §6.3 NORM (06c, PDF p.333/6-181). |
| 1 (2) | **Unused** — no code reads `legacy & 2` | — | — (setter comment: "XC audit finding was wrong"; the XC word-skip itself is unchanged, #18). |
| 2 (4) | CRGT/CRLT signedness — :480–481 | Signed compare. Fixes #17. | Old bug: unsigned compare. §6.3 CRGT/CRLT (06b, PDF pp.252/254). |
| 3 (8) | TIM reset value — :84 | TIM = 0xFFFF. Fixes #12's TIM half. | Old bug: TIM = 0. §9.1.3 item 6; §9.3.2 (09a). See §7 (regression R2). |
| 4 (16) | MADD/MADS TRM mirror — :417 | TREG0 only, no mirror. Fixes N-1. | Old bug: `set_t0()` mirrors to TREG1/TREG2 when `!trm`. §6.3 MADD/MADS. |
| 5 (32) | INTM/XF context restore — :278 | `restore_ctx()` does not restore INTM/XF. Fixes #9. | Old bug: INTM/XF restored (and `sh.intm` is always 1, since `check_int()` sets `intm=1` before `save_ctx()`). §4.8.8 (04, PDF p.121/4-42). |
| 6 (64) | NDX=0 AR0 mirror — :592 | Mirror on when NDX=0. Fixes #10 (partially). | Old bug: mirror missing entirely. §5.2.1 (05, PDF p.136/5-6). |
| 7 (128) | BMAR writeback — :340, :405, :420, :422, :424 | Block moves advance a local `pfc`; BMAR untouched. Fixes #15. | Old bug: `c->bmar = pfc` at all five sites. §6.3 BLDD/BLDP/BLPD/MADD/MADS. |

Not `legacy`-gated: the `ivec_legacy` INTR fallback (:521, unconditional — see
§7), the XINT mode (separate setter :611, default 0 = old every-tick behaviour),
and the cycle model (separate setter :612, default 0 = old instruction counter).

## 7. New findings this pass (deduplicated across workers)

Severity: HIGH = blocks use; MEDIUM = wrong results/state on plausible firmware;
LOW = edge cases, timing-only, or harness-visible only. The build failure is
counted once (it is 06a §1, 06b-N1, 06e-R1 and 06c §2.2 — same finding, found
independently four times).

| ID | Sev | Finding | Manual citation | Core |
|---|---|---|---|---|
| 06-NEW-1 | HIGH | **New core does not compile as delivered.** `#include "c5x_cyctab.h"` (:10); the header exists nowhere in `~/workspace` or `/tmp` (three independent searches, incl. a full-workspace grep — only references are the `#include` and workers' own compile logs). All `cyc_model` claims are therefore [UNVERIFIED] and no smoke test could be run. | — (build, not manual) | :10; :585 `cyc_tab[c->op]` |
| 06-NEW-2 | MED | **NDX mirror is change-detected, not write-detected.** Same-value LAR/ADRK/MAR writes never mirror (06b T5b: LAR AR0,#0x10 with AR0 already 0x10 leaves INDX=0x55 stale); `ar0_prev` never reset (stale comparator after re-reset; host `c5x_set` S_AR0 desync); mirror deferred across delay slots (`delay_slot()` calls `exec1()` directly). Manual requires the write on "every AR0 modification or LAR write". | §5.2.1 (05, PDF p.136/5-6) | :592–593; :45; :262–268 |
| 06-NEW-3 | MED | **`legacy&8` re-introduces the manual-wrong TIM=0 reset as an opt-in.** Any harness setting legacy bit 3 (e.g. while enabling other legacy bits) silently re-acquires the spurious post-reset TINT; the bit bundles an unrelated timer defect with instruction-semantics toggles, and `legacy` persists across resets. | §9.1.3 item 6 (09a, PDF p.515/9-6); Table 4–16 | :84; :613 |
| 06-NEW-4 | MED | **`cyc_model` double-counts block-move words.** `exec1()` loops still `cycles++` per moved word (SMMR :311, TBLR :409, TBLW :411, BLDP/BLPD/BLDD/MAC/MACD/MADD/MADS likewise) and the run loop adds `cy − 1` on top. Assuming a correct table: TBLR single 4 vs manual 3, RPT k+3 vs k+2; SMMR single 3 vs 2, RPT k+2 vs 2k. The model fixes nothing for block moves and moves the error. | §6.3 SMMR/TBLR/TBLW; App. B Classes XVII/XVIII/XXIV | :311, :409, :411; :584–590 |
| 06-NEW-5 | LOW | **`watch_hits` attributed to the post-fetch PC, not the storing instruction.** `dm_wr()` indexes by `c->pc` after `fetch()` advanced it — hits land on insn+1 (1-word) or insn+2 (2-word). Observational only; `cur_pc` (:300) already holds the instruction address. | N/A — tracing has no manual basis | :179; :260; :300 |
| 06-NEW-6 | LOW | **`ivec_legacy[]` keeps the old wrong-vector path reachable via INTR, ungated by `legacy`.** Second loop (:521) retries the old +0x10 table when the correct lookup misses. It only engages when `ivec_ind[8]` is configured (06d §2.1), and plain `intr 17` → 0x22 is manual-correct (K=17 *is* the TRAP vector — see §8), so this is a deliberate-compat note, not a default-behaviour violation. | §6.3 INTR K-table (06b, PDF p.263/6-111) | :282; :521 |
| 06-NEW-7 | LOW | **MAC/MACD single cycles 2 vs manual 3; MADD/MADS RPT n+2 vs n+1.** Same loop shape as 05a1 N-1; the `do…while` adds exactly 1 per iteration, so a single execution can never reach 3 and an RPT run can never reach n+1. Demotes MAC OBEYS → PARTIAL; remaining driver keeping MADS PARTIAL. | §6.3 MAC/MACD/MADD/MADS (06c, PDF pp.301–317/6-149–6-165) | :399–403; :416–420 |
| 06-NEW-8 | LOW | **`cyc_model` taken/not-taken override list is incomplete.** Taken-4 covers only BANZ/BCND/CC/RETC (:588); B, CALL, BACC/CALA, BACCD/CALAD rely entirely on the unverifiable table. | App. B Classes VIII/X (appendix-b) | :588 |
| 06-NEW-9 | LOW | **`seq`-based taken detection misclassifies taken-to-fall-through branches.** A taken RETC/BANZ/BCND/CC whose target equals the fall-through address is charged 2 instead of 4. Fix would be to record taken/not-taken in `exec1()`. | §6.3 BCND/CC/RETC True 4; App. B Class VIII/X | :586; :588–589 |
| 06-NEW-10 | LOW | **`rep_cont` flattens all RPT per-iteration costs to 1.** Manual gives e.g. XPL SARAM RPT `2n−2`, SACH/SACL external RPT `2n+nd`, SUB SARAM same-block RPT `n+1`. Right only for the DARAM `n` case. | §6.3 XPL/SACH/SACL/SUB RPT tables (06d) | :585 |
| 06-NEW-11 | LOW | **`cyc_tab[c->op]` full-opcode index vs unknown table shape — [UNVERIFIED] risk, not a confirmed bug.** If the header defines fewer than 65536 entries, the lookup reads out of bounds. Cannot be resolved without the header. | — (structural) | :585 |
| 06-NEW-12 | LOW | **`delay_slot()` cycle restore also wipes a slot block move's words (cyc_model only).** `:267` resets `cycles` to the pre-slot value, discarding everything the slot instructions counted — including a block move in the slot. The manual gives no rule that slot words execute "inside" the branch's 2 cycles. Pathological firmware; default mode unaffected. | §6.3 delayed-branch entries; App. B Classes IX/XI | :267 |
| 06-NEW-13 | LOW | **`xint_mode=1` still raises a spurious XINT on its first tick, and still ignores SPC reset.** `c5x_set_xint_mode()` sets `xint_first = 1`; the next tick raises XINT with no DXR write ever having happened. Mode 1 does not consult SPC, and N-17's wrongly-cleared XRDY manufactures a `dxr_pending` transmit for a reset-held transmitter. | §9.7.1 Table 9–13 XRDY (09b, PDF p.538/9-29) | :609; :611 |
| 06-NEW-14 | LOW | **`cyc_model=1` timer behaviour is asserted, not verified, and still not CLKOUT1.** Timer loop :597 ticks once per net counted cycle; even a correct fastest-case table omits wait states, READY, MMR-write +1 and interrupt-entry cost — so #3 would remain STILL PRESENT in substance under the mode, only smaller in magnitude, by an unverifiable amount. | §9.3/§9.3.2 (09a, PDF pp.518–520/9-9–9-11); §9.2 | :597; :584–591 |

New-findings total: **14 (1 HIGH, 3 MEDIUM, 10 LOW)**. Two workers found the
same finding independently twice (build failure: 06a + 06b + 06c + 06e; NDX
residual: 06b-N2 + 06d-N1/N2/N4 + 06c N-C2-7; `ivec_legacy`: 06a + 06b-N4 +
06d §2.1 + 06e-R5; double-count: 06a §2d + 06b §7 + 06c N-C2-1; watch_hits:
06a §2g + 06d-N3) — counted once here.

## 8. Corrections to the task brief (established by the workers)

1. **Plain `intr 17` → 0x22 is manual-correct.** The task phrased the `ivec_legacy`
   fallback as "the firmware's `intr 17` (0x22) reaching the INT4 slot". Per the
   §6.3 INTR K-table (06b, PDF p.263/6-111), K=17 **is** the TRAP vector (22h);
   INT4 is K=9 → 12h. The plain path (`:519`, no save, no indirection) is exactly
   what the manual says for K=17. What the legacy second loop (`:521`) preserves
   is the *firmware's ROM-stub arrangement*: under the old wrong table, hardware
   INT4 trapped to 0x22, so the firmware's INT4 handler is reached through 0x22,
   and `intr 17` was the firmware's way of invoking it — and only when the host
   configured `ivec_ind[8]`. Without it there is no INT4-slot behaviour, and none
   is owed by the manual. "INT4 slot" is firmware-model language, not manual
   language. (06d §2.1; 06b-N4.)
2. **NDX polarity — manual self-contradiction, resolved 2-vs-1 in favour of NDX=0
   (merge-time PDF check).** Worker 1 flagged that distilled `03-cpu-registers.md`
   line 254 states the opposite polarity to Table 4–3 and §6.3 CMPR. Checked
   directly against the June 1998 PDF in this merge (fresh `pdftotext -layout`,
   PDF pp. 73, 88, 136): §3.4 (PDF p.73 / printed 3-19) says "if the NDX bit in
   the PMST is set, LAR also loads INDX and ARCR"; Table 4–3 (PDF p.88 / printed
   4-9) says NDX=0 is 'C2x-compatible mode (AR0 writes also write INDX/ARCR) and
   NDX=1 is enhanced mode (AR0 only); §5.2.1 (PDF p.136 / printed 5-6) says
   "clear the NDX bit… When the NDX bit is cleared, every AR0 modification or
   LAR write also writes the ARCR and INDX… The NDX bit is cleared at reset."
   The 03 line is a faithful transcription of §3.4, not a distillation error —
   the manual contradicts itself. Normative choice, as in 05: **NDX=0** (two
   sources + the reset state + the explicit Table 4-3). The new core's polarity
   (`!c->ndx` gate at :592) is correct under that choice; if §3.4 were right, the
   mirror would be inverted. The #10 PARTIALLY FIXED verdict is conditional on
   this choice.

## 9. Open split carried forward — IPTR remap for TRAP / NMI (and INTR)

**Status: OPEN, not adjudicated. Do not implement on one reading alone.** (06d §6,
full write-up there; summarised here.)

- **Reading A (05g; also 05 §3 N-7): TRAP/NMI vectors ARE IPTR-remapped.** `08`
  §8.2.2 (PDF pp.478–479 / 8-11–8-12): "After IPTR is loaded, any subsequent
  interrupt (except for a reset) will fetch its vector from the new location."
  Table 8–7 lists TRAP (22h) and NMI (24h) as vectors among the others. The
  general vector-generation rule (`04` §4.8.1 Fig. 4–6, PDF p.117 / 4-38) has no
  exception for TRAP/NMI. Under this reading the core's absolute `pc = 0x22` /
  `pc = 0x24` (`:503–504`) and INTR's absolute `pc = v` (`:519`) are wrong
  whenever IPTR≠0.
- **Reading B (05d/05e): the remap is UNVERIFIED for TRAP/NMI (and INTR).** `06d`
  TRAP §6.3 (PDF p.429 / 6-277): "(PC)+1 → stack; 22h → PC". `06c` NMI §6.3
  (PDF p.331 / 6-179): "PC+1 → stack, 24h → PC, 1 → INTM". `06b` INTR §6.3
  (PDF p.263 / 6-111): K-table gives absolute hex locations with no mention of
  IPTR. No passage states explicitly that these vectors are IPTR-remapped. Under
  this reading the core's absolute addresses are correct as written.
- **What the new core does:** absolute 0x22/0x24 for TRAP/NMI, absolute `v` for
  INTR, IPTR applied only on the hardware-trap path (`:287`). That matches Reading
  B and contradicts Reading A when IPTR≠0. **No verdict is entered on this point
  in either direction.** Resolution needs a hardware test or a further manual
  passage.

## 10. What this pass changed vs the old core (summary)

1. **Coverage:** 148/179 forms obey, 1 violates (IDLE2), 30 partial, 0 missing,
   0 phantom — superseding 140/1/38. The partial count fell because 9 forms were
   fixed and only MAC was demoted (convention extension, §2).
2. **Findings:** 4 fixed (#1, #9, #15, #17), 5 partially fixed (#5, #10, #11, #12,
   #23), 24 still present, 1 regressed (#35, build), 1 withdrawn (#6). N-1 fixed;
   N-10 partially fixed; N-7 still open; the other 17 N-findings still present.
3. **Behaviour tallies:** 194/139/68/26 over 427 checks (was 183/150/68/26) —
   +11 obey, −11 violates.
4. **The build is the blocker.** Nothing else in the diff matters until
   `c5x_cyctab.h` is supplied: the cycle model cannot be verified or run, no
   smoke test can be re-run, and every `cyc_model=1` claim in this file is
   [UNVERIFIED] as executed behaviour. Once the header appears, re-run the build
   exactly as 06a §1 and T1–T9 as 06a §4, plus `legacy=0xFF` spot checks that each
   old behaviour is actually re-enabled, and re-measure the cycle-model
   double-count (06-NEW-4) against App. B Table B-2.
5. **The interrupt-driven run is still blocked** — by #2 (RPTC), #3 (timer time
   base), #4 (XINT per tick at default), #7 (RPT), #11 (plain-path INTR save),
   #27 (NMI `intm=1`), now joined by 06-NEW-1 (build), 06-NEW-3 (`legacy&8`
   TIM), and the still-present N-2/N-3/N-4/N-5/N-9. What changed: the vector
   table (#1) and the shadow restore (#9) — the two interrupt-blockers that
   mattered most — are fixed at default.
6. **Nothing in the HIGH list was refuted outright** by the new core's changes;
   the diff is a strict improvement on the semantics it touches, except for the
   build failure and the two opt-in regressions (06-NEW-3, 06-NEW-13's first-tick
   kick).

## 11. Files

- This file: `06-core2-recheck.md` (merge record).
- Evidence: `06a-core2-diff-build.md`, `06b-core2-instructions-a-r.md` (490
  lines), `06c-core2-instructions-s-z-cycles.md` (543 lines),
  `06d-core2-cpu-interrupts.md`, `06e-core2-peripherals-memory.md` (169 lines).
- `00-consolidated-report.md` was NOT modified — it is the record for core v1;
  this re-check is a standalone verdict file, as tasked.
- The four area files 01–04, the 05 files, the cores, and the manual were not
  modified. Worker 2's test harness and stub header live in `/tmp/c5x2/` and are
  not deliverables.
