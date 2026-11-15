# 06a — Core-2 diff + build + smoke tests (worker 1 of 5)

- Date: 2026-11-15 00:46 CET. Worker: diff + build + smoke tests.
- NEW CORE: `~/workspace/user/files/c5x_core-2.c` — 630 lines, 45,758 bytes, md5 `7aa4227d47e9f72abee2b4cb48fb5fef`.
- OLD CORE: `~/workspace/user/files/c5x_core.c` — 603 lines, 41,745 bytes, md5 `41c51be7e2edfb5daeda96ce6c80bbb5`.
- Manual (authority): distilled SPRU056D June 1998 in `~/workspace/research_notes/courier-firmware/c5x_manual/`; PDF `~/workspace/user/files/spru056d.pdf` used as tiebreaker only where noted. `c5x_users_guide.txt` (1993) and `c5x_opcodes.*` / `c5x_patterns_fixed.json` not used.
- Prior record: `c5x_core_audit/05-full-reverification.md` (old-core verdicts: 179 §6.3 forms, 140 obey / 1 violates / 38 partial; findings #1–#35, N-1..N-20) and `04-pipeline-timing-build.md` (smoke tests T1–T9).
- Neither core file was modified. No stub header was created. No other file was edited except this one and the one `progress.log` line.

## Verdict in one paragraph

**The new core does not build.** Line 10 does `#include "c5x_cyctab.h"` and that header exists nowhere in `~/workspace` or `/tmp` (verified by `find`, §1). The compiler stops at that line, so **no smoke test T1–T9 was run** and no cycle-model claim in the new code could be executed or measured. Everything in §3–§7 below is code reading, not a measured result, and is labelled as such. The toolchain itself is fine: the old core builds clean under the same commands (control, §1). The diff itself is real and narrow — **77 changed lines verified (52 added + 25 removed, 20 hunks)** — and, on paper, it addresses five confirmed old-core findings (#1 ivec, #9 INTM/XF shadow, #10 NDX mirror, #15 BMAR writeback, #17 CRGT/CRLT, #23 NORM, N-1 MADD/MADS TRM mirror) plus the timer-reset value from #12, adds a table-driven cycle model gated behind `cyc_model`, an XINT mode, and pc/watch hit tracing. But three of those fixes are conditional on the `legacy` bitmask (default `legacy=0` = fixed behaviour — §3), the cycle table's contents are entirely [UNVERIFIED] because the header is missing, and the old `ivec` table survives unconditionally as a fallback in the INTR path. The RPT non-repeatable bug (#7), the `rptc` sentinel clobber, delay-slot guards, interrupt-entry cost, CLRC-INTM shadow, RPTB lockout, wait states, TDM and IDLE2 are all untouched (§7).

## 1. Build — FAIL (new core); PASS (old core, control)

Toolchain: gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1). Commands run from `~/workspace/user/files`, exactly as the header comment prescribes (but with the new filename — see note below).

New core, shared library (header's command):
```
$ gcc -O2 -shared -fPIC -o libc5x.so c5x_core-2.c
c5x_core-2.c:10:10: fatal error: c5x_cyctab.h: No such file or directory
   10 | #include "c5x_cyctab.h"
      |          ^~~~~~~~~~~~~~
compilation terminated.
exit 1. No .so produced.
```
New core, `-Wall -Wextra` object run: same fatal error, exit 1. No warnings could even be reached — the failure is at line 10, before any code is compiled.

Old core, same commands (control):
```
$ gcc -O2 -shared -fPIC -o /tmp/libc5x_old.so c5x_core.c
exit 0, no output. /tmp/libc5x_old.so 45,688 bytes.
$ gcc -O2 -c -Wall -Wextra -o /tmp/c5x_core_old.o c5x_core.c
exit 0. Only the two known warnings from audit 04 §1:
  c5x_core.c:287: unused parameter 'c' in sat_acc_shift [-Wunused-parameter]
  c5x_core.c:287: 'sat_acc_shift' defined but not used [-Wunused-function]
```
So the failure is the missing header alone, not the toolchain, flags, or environment.

Header search (verified, not assumed):
- `find ~/workspace /tmp -name 'c5x_cyctab.h'` → no hits.
- `grep -rn 'c5x_cyctab' ~/workspace/user/files/ ~/workspace/research_notes/courier-firmware/` → exactly one hit: the `#include` at new-core line 10. Nothing else in those trees references the header, and no file there defines `cyc_tab` or provides the table's contents.
- No stub header was created and no contents were invented: the table's size, element type, indexing convention and values are all [UNVERIFIED]. Any statement below about what the cycle model *would* do is conditional on unknown table contents.

Header-comment drift (minor, recorded): the new core's own build comment (line 6) still reads `gcc -O2 -shared -fPIC -o libc5x.so c5x_core.c` — it names the old filename, not `c5x_core-2.c`. The build in this report used the new filename as the task instructed.

## 2. Diff inventory — 77 changed lines verified, 20 hunks

Method: `diff -u c5x_core.c c5x_core-2.c` (233 diff-output lines). Count: `+` lines 53 including the `+++` header = **52 added**; `-` lines 26 including the `---` header = **25 removed**; 52 + 25 = **77 changed lines**, matching the task's figure. Hunk count: **20** `@@` hunks. Line numbers below are new-core lines.

### 2a. Build dependency (1 hunk)

| New-core line | Change |
|---|---|
| 10 | Added `#include "c5x_cyctab.h"` — the sole build blocker (§1). The header supplies `cyc_tab[]`, used at line 585. |

### 2b. Interrupt vectors — fixes #1 and N-10 (2 hunks)

| New-core line | Change |
|---|---|
| 281 | `ivec[]` corrected: `{0x02, 0x04, 0x06, 0x08, 0x0A, 0x0C, 0x0E, 0x10, 0x12, …}` — was `{0x02, 0x04, 0x06, 0x18, 0x1A, 0x1C, 0x1E, 0x20, 0x22, …}`. Comment: "INT1..INT3, TINT, RINT, XINT, TRNT, TXNT, INT4". Manual: §4.8.1 Table 4–14 (`04-program-control.md`, PDF p.116/4-37); §8.2.2 Table 8–7 (`08-memory.md`); §6.3 INTR K-table (`06b/06c`). This is the fix for finding #1 (vectors +0x10, CONFIRMED) and for N-10 (INTR shadow save gated on the wrong table, dead for K=4–9 — the save branch at old line ~512 tests `ivec[i] == v`, which could never match for K=4–9 against the old table). |
| 282 | Added `ivec_legacy[]` = the old (wrong) table, verbatim. |
| 521 | INTR k path (`exec_be`, `INTR k` case): after the new-table `ivec[]` loop misses (`i == 9`), a second loop retries against `ivec_legacy[]` with the same `ivec_ind[i]` indirection and `save_ctx()`. Comment: "old (wrong) table, still used so the firmware's `intr 17` (0x22) reaches the INT4 slot via the ROM-stub model". **This fallback is NOT gated on the `legacy` bitmask — it is unconditional.** Any `INTR k` whose vector matches only the old table still takes the old path even with `legacy=0`. Code-reading consequence: the #1 fix is partial in practice for firmware that issues `INTR` with the old vector numbers; whether that is intended (ROM-stub model) is a design decision for the merger, not something the manual adjudicates — the manual's vectors are the new table. |

`check_int()` itself (lines ~284–290) is byte-identical to the old core: still 0-cycle entry, still clears the serviced IFR bit unconditionally (N-2 serial-IFR auto-clear untouched), still loops `i < 9`, still no NMI input.

### 2c. `legacy` bitmask — 7 bits, 5 sites groups (see §3 for the full inventory)

| New-core line | Change |
|---|---|
| 36 | Struct gains `xint_mode, xint_first, cyc_model, words, rep_cont, legacy; uint64_t idle_cycles;` (all zero-initialised by `calloc` in `c5x_new`). |
| 84 | `c5x_reset`: `c->tim = (c->legacy & 8) ? 0 : 0xFFFF` — was unconditionally `0`. Default (legacy=0) now resets TIM to 0xFFFF, matching the manual (§9.1.3 item 6 and §9.3.2, `09a-peripherals-timer-clock-waitstates.md` lines 117/126/235: "TIM and PRD loaded with FFFFh"; "Reset: both FFFFh"). This corrects the TIM half of finding #12 (reset values wrong, CONFIRMED). Note: `legacy` is **not** reset by `c5x_reset` — it persists across resets; it is only ever set by `c5x_set_legacy()` (line 613) and zeroed by `calloc` at creation. So the TIM reset value depends on whether the harness called the setter before the reset. |
| 278 | `restore_ctx`: `if (c->legacy & 32) { c->intm = c->sh.intm; c->xf = c->sh.xf; }` — INTM/XF are no longer restored by default. Fix for #9 (INTM/XF wrongly shadowed, CONFIRMED, §4.8.8, `04-program-control.md`, PDF p.121/4-42). Legacy bit 32 re-enables the old (wrong) restore. |
| 340, 405, 420, 422, 424 | BMAR writeback gated on `legacy & 128` at all five block-move sites: BLDP 0x57 (line 340), BLPD bmar 0xA4 (405), MADS/MADD 0xAA/0xAB (420), BLDD bmar,dma 0xAC (422), BLDD dma,bmar 0xAD (424). Default: `pfc` is advanced locally and BMAR is untouched. Fix for #15 (BMAR written back, CONFIRMED — §6.3 BLDD/BLDP/BLPD/MADD/MADS execution blocks show `(BMAR) → PFC` then `(PFC) → MCS`, no BMAR assignment; `06b-instructions-a-h.md` lines 891/1001/1075). |
| 396 | NORM (0xA0): `if (c->acc == 0 && !(c->legacy & 1)) t = 1;` — default now treats ACC==0 as normalised (TC=1, no shift). Fix for #23 (NORM misses ACC==0, CONFIRMED — §6.3 NORM, `06c-instructions-i-r.md`, PDF p.333/6-181). Legacy bit 0 re-enables the old behaviour (t = bits 31^30 = 0 for ACC==0, so TC=0 and ACC <<= 1, still 0). |
| 417 | MADS/MADD (0xAA/0xAB): `if (c->legacy & 16) set_t0(c, d); else c->treg0 = d;` — default writes TREG0 only, no TRM mirror to TREG1/TREG2. Fix for N-1 (MED — §6.3 MADD/MADS list "Affected by: OVM and PM" only, no TRM step, unlike MAC/MACD and the LT family; `06c-instructions-i-r.md`, PDF pp.310–317/6-158–6-165). Legacy bit 16 re-enables `set_t0()` mirroring when `!trm`. |
| 480–481 | CRGT (exec_be 0x1B) / CRLT (0x1C): default comparison is now signed — `(int32_t)c->acc >= (int32_t)c->accb`; legacy bit 4 selects the old unsigned `c->acc >= c->accb`. Fix for #17 (CRGT/CRLT unsigned, CONFIRMED — §6.3 CRGT/CRLT "larger/smaller value (signed)", `06b-instructions-a-h.md`, PDF pp.252/254). |
| 592 | NDX mirror (see §2e). Gated on `!(c->legacy & 64)`. |
| 613 | Setter: `void c5x_set_legacy(C5x *c, int m) { c->legacy = m; }` with the comment "bit0 NORM(acc=0), bit2 unsigned CRGT/CRLT, bit3 TIM reset 0 (bit1 unused: XC audit finding was wrong)". |

No code anywhere reads `legacy & 2` (bit 1) — verified by grep. The bit-1 note refers to audit #18 (XC k=1 skips opcode words): the old core already skipped `n` words, so there was no XC behaviour to gate.

### 2d. Cycle model — new, gated behind `cyc_model` (3 hunks)

| New-core line | Change |
|---|---|
| 260 | `fetch()` now does `c->words++` on every fetched word. `words` is the per-instruction word count used by the cycle model. |
| 262–268 | `delay_slot()`: saves `cy0 = c->cycles` and `op0 = c->op` on entry; on exit restores `c->op = op0` and, if `c->cyc_model`, resets `c->cycles = cy0` — "the two delay-slot words execute inside the delayed branch's own cycle count". Effect (code reading): with the model on, delay-slot instructions cost 0 cycles on top of the delayed branch's own table/forced value; the branch pays once. With the model off (`cyc_model=0`, the default), `delay_slot()` behaves exactly as before except for the `c->op` restore (which matters because `c->op` is read by the cycle-model code and by `cond()`-style paths after return — in the old core the last slot instruction's opcode leaked into `c->op`). |
| 582–590 | `c5x_run()`: `c->words = 0` before `exec1()`; after it, if `c->cyc_model`: `cy = c->rep_cont ? 1 : cyc_tab[c->op]`; `seq` = PC advanced exactly `words` past `ppc` (sequential fall-through); if not a repeat-continuation and not sequential, taken BANZ (0x7B) / BCND (0xE0–E3) / CC (0xE8–EB) / RETC (0xEC–EF) are forced to `cy = 4`; else if sequential, the same set plus RETCD (0xFC–FE; `h != 0xFF` excludes RETD) is forced to `cy = 2`; then `c->cycles += cy - 1` (exec1 already counted 1). Setter line 612: `c5x_set_cycle_model(C5x *c, int m)`. Default `cyc_model=0` (calloc) = old instruction-count behaviour. |

Code-reading observations on the model (all [UNVERIFIED] as executed behaviour, since the build fails):
- The table itself (`cyc_tab`, indexed by the full 16-bit `c->op` at line 585) is in the missing header. Its size, element type and every value are unknown. The forced-4 / forced-2 overrides above are the only cycle numbers visible in the shipped source.
- The forced lists omit the unconditional 2-word branches/calls (B 0x79, CALL 0x7A, BD 0x7D, CALLD 0x7E — manual class VIII/IX, 4/2 cycles) and the accumulator branches/returns (BACC/CALA/RET/BACCD/CALAD via `exec_be`, `op>>8 == 0xBE` — manual class X/XI, 4/2 cycles). Those rely entirely on `cyc_tab` values. Whether the table covers them correctly cannot be checked without the header.
- Taken RETCD (0xFC–FF) is not in the forced-4 list, so a taken RETCD also relies on the table; only its not-taken case is forced to 2.
- Interaction with the inner RPT loops (code reading, needs a build to confirm): block-move/MAC inner loops still do `c->cycles++` per repeated iteration *inside* `exec1()`, and the model then adds `cy - 1` on top. For a single (non-repeated) BLDD the total would be 1 (exec1) + 1 (inner loop, since `rptc` starts at −1 and the `while (rptc > -1)` body runs once) + (`cyc_tab` − 1). If `cyc_tab[BLDD]` is the manual single-execution cost (2 for BMAR forms, 3 for #lk forms), the total becomes 3/4, not 2/3 — i.e. the model may double-count the inner loop's extra cycle. The old core's "accidentally correct" single-execution counts (audit 04 §2/§4) came from exactly that inner-loop +1. Whether the table was built to compensate (e.g. table value 1 for those opcodes) is [UNVERIFIED] without the header. The merger should treat every cycle number from this model as unverified until the header appears and T1–T9 are re-run.
- `rep_cont` (lines 594–596): set to 1 when the outer RPT loop rewinds, 0 otherwise; a repeat-continuation costs `cy = 1` (i.e. +0 beyond exec1's 1). This matches the comment "repeated iterations cost 1" and the manual's RPT steady-state cost for 1-word ops (App. B Table B-2; audit 04 §2). Note the old `else c->rptc = 0;` sentinel clobber is still there (line 596) — the RPT-sentintel bug from audit 04 §4 is untouched, only `rep_cont` was added alongside it.
- Wait states are still never added: `pdwsr`/`iowsr`/`cwsr` are stored but never read in any cycle calculation (unchanged from audit 04 §2). The model's own comment says "fastest case", i.e. no wait-state accounting by design.

### 2e. NDX=0 AR0 mirror — fixes #10 (1 hunk, in the run loop)

| New-core line | Change |
|---|---|
| 45 | Struct gains `ar0_prev` (previous AR0 value, for change detection). |
| 592–593 | After every `exec1()` in `c5x_run()`: `if (!c->ndx && !(c->legacy & 64) && c->ar[0] != c->ar0_prev) { c->indx = c->arcr = c->ar[0]; }` then `c->ar0_prev = c->ar[0];`. I.e. whenever NDX=0 and AR0 changed during the instruction, INDX and ARCR are loaded with the new AR0. |

Manual basis: PMST Table 4–3 (`04-program-control.md` line 139, NDX bit 2: "0 = 'C2x-compatible mode: any 'C2x-compatible instruction that modifies/writes AR0 also modifies/writes INDX and ARCR… 1 = 'C5x-enhanced mode: 'C2x-compatible instructions do not affect INDX and ARCR; they affect only AR0") and §6.3 CMPR (`06b-instructions-a-h.md` lines 1452–1453: "clearing NDX causes any 'C2x instruction that loads AR0 to load the ARCR and index register (INDX) also"). Reset state is NDX=0 (`04-program-control.md` line 545: "PMST | NDX → 0 | 'C2x-compatible mode selected"), so the mirror is on by default — matching finding #10 (CONFIRMED, §5.2.1). Legacy bit 64 disables it (re-enables the old missing-mirror behaviour).

Two code-reading caveats:
- The mirror is change-based, not instruction-based: it fires on *any* AR0 change, including a direct MMR write to AR0 (mmr_wr line ~155) or `c5x_set(S_AR0)` from the harness, and it also fires when AR0 is changed by an instruction that the manual's "loads AR0" wording may not cover. It does *not* fire if an instruction writes the same value AR0 already held (no change, no mirror) — but in that case INDX/ARCR already hold that value from the earlier write, unless the harness wrote INDX/ARCR directly in between. Edge case, low severity, recorded for the merger.
- Distilled-file inconsistency, flagged not resolved: `03-cpu-registers.md` line 254 says "if NDX bit in PMST is set, LAR also loads INDX and ARCR" — the opposite polarity to Table 4–3 and to §6.3 CMPR quoted above. The core follows Table 4–3 / CMPR (NDX=0 → mirror), which is also the polarity the 05 merge record adopted (05 §4 item 11: "§5.2.1 and Table 4–3 say NDX=0 (cleared)"). The 03 line looks like a distillation error; tiebreaker would be the June 1998 PDF §3.4 (PDF p.73/printed 3-19) — not consulted here because the two other distilled sources agree with each other and with the core.

### 2f. Serial XINT mode — new API, not `legacy`-gated (1 hunk)

| New-core line | Change |
|---|---|
| 36 | Struct gains `xint_mode, xint_first`. |
| 605–610 | `c5x_serial_tick()`: RINT (`ifr \|= 1<<4`) still raised on every tick, unconditionally. XINT (`ifr \|= 1<<5`) now raised only `if (!c->xint_mode \|\| dxr_pending \|\| c->xint_first)`, where `dxr_pending = !c->xrdy` (DXR written since the previous frame) and `xint_first` is a one-shot set by the mode setter. Comment: "XINT: legacy = every tick; mode 1 = only after a DXR write (plus one initial kick)". |
| 611 | Setter: `void c5x_set_xint_mode(C5x *c, int m) { c->xint_mode = m; c->xint_first = 1; }`. Default `xint_mode=0` = old every-tick XINT. |

Manual basis: §9.7.1 Table 9–13 (`09b-peripherals-serial-bsp-tdm-hpi.md`, PDF p.538/9-29) — XINT is tied to the XRDY 0→1 edge, which is finding #4 (serial tick raises XINT every tick, CONFIRMED). Mode 1 approximates the edge rule: a DXR write clears XRDY (0), the tick sets XRDY=1, so the tick after a DXR write is the edge. The "one initial kick" (`xint_first`) is an assumption with no cited manual basis — [UNVERIFIED] as manual behaviour. N-5 (serial tick ignores SPC RRST/XRST) is **not** addressed: `c5x_serial_tick()` still raises RINT/XINT and sets `rrdy`/`xrdy` regardless of reset state.

### 2g. Tracing / watchpoints / idle accounting (3 hunks)

| New-core line | Change |
|---|---|
| 46 | Struct gains `uint32_t pc_hits[65536]; uint32_t watch_hits[65536]; int32_t watch_a;`. |
| 59 | `c5x_new`: `watch_a = -1` (no watch address). |
| 179 | `dm_wr()`: `if ((int32_t)a == c->watch_a) c->watch_hits[c->pc & 0xFFFF]++;` — counts data writes to the watched address, attributed to the current PC. |
| 302 | `exec1()`: `c->pc_hits[c->pc & 0xFFFF]++;` alongside the existing `c->hits[c->pc]++` (line 301). `pc_hits` duplicates `hits[]` exactly (same index, same increment point) — the new value is the accessor API, not new counting. |
| 573 | Idle loop: `c->idle_cycles++` alongside `c->cycles++`. |
| 614–615 | Accessors `c5x_idle_cycles()`, `c5x_total_cycles()` (returns `c->cycles`). |
| 624–627 | `c5x_set_watch()` (sets `watch_a`, clears `watch_hits`), `c5x_watch_hits(pc)`, `c5x_pc_hits(pc)`, `c5x_pc_hits_clear()`. |

Code-reading caveat on watch attribution: `dm_wr()` is called during `exec1()` after `fetch()` has already advanced `c->pc` past the opcode (and past the immediate word for 2-word instructions), so `watch_hits` is keyed by the *mid-instruction* PC, not the instruction-start PC (`cur_pc`). A watch hit for a 1-word instruction at address X is recorded under X+1; for a 2-word instruction under X+2. The merger should not compare `watch_hits` keys directly against `pc_hits`/breakpoint addresses without accounting for that offset. This is a code-reading observation, not a measured result.

### 2h. Comment-only change (1 hunk)

| New-core line | Change |
|---|---|
| 439 | XC case: added the comment "XC n counts instruction WORDS (manual: n=2 = one 2-word or two 1-word instructions)". No code change — `c->pc += n` with `n = ((op >> 12) & 1) + 1` is identical to the old core. Consistent with finding #18 (XC k=1 skips opcode words, CONFIRMED — §6.3 XC + §4.5.6). The setter comment (line 613) confirms bit 1 of `legacy` was deliberately left unused because "XC audit finding was wrong" — i.e. there was no XC behaviour to gate. |

### 2i. Unchanged areas worth stating explicitly

- `sat_acc_shift()` (line ~296) is still present, still dead code, still just `return v;`.
- `in_delay` flag still set/cleared in `delay_slot()` and still read nowhere else.
- `cmpr_ar0` experiment unchanged; `c5x_set_cmpr_ar0()` unchanged.
- `c5x_set` / `c5x_get` (S_* enum) unchanged — finding #32 (no S_ST1/S_PMST in `c5x_set`) untouched.
- No changes to `tick_timer()`, `mmr_rd`/`mmr_wr` (GREG readback N-18 untouched), `pm_ptr()` (OVLY/CNF #13 untouched), `ea()` (circular wrap #22 untouched), `pop()`/`push()`, or the RPTB block-repeat logic.

## 3. `legacy` bitmask inventory — every bit, default vs legacy behaviour

Set by `c5x_set_legacy(C5x *c, int m)` (new-core line 613); stored in `c->legacy` (line 36); zero at creation (`calloc`, line ~55); **not** cleared by `c5x_reset` (lines 77–85) — it persists across resets. Default behaviour (`legacy=0`) is what the core does out of the box, and for every defined bit the default is the audit-fixed behaviour. Setting a bit re-enables the old (audit-confirmed-wrong) behaviour at that site. Bits are independent and combinable.

| Bit (value) | Name / site (new-core lines) | Default `legacy=0` (out-of-the-box) | `legacy` bit set (old behaviour re-enabled) | Manual basis |
|---|---|---|---|---|
| 0 (1) | NORM ACC==0 — line 396 | ACC==0 → TC=1, no shift (normalised). Fixes #23. | Old bug: t = (ACC>>31)^(ACC>>30) = 0, so TC=0 and ACC <<= 1 (still 0). | §6.3 NORM, `06c-instructions-i-r.md`, PDF p.333/6-181 |
| 1 (2) | **Unused** — no code reads `legacy & 2` | — (no effect) | — (no effect) | Setter comment: "XC audit finding was wrong" (line 613). See §2h. |
| 2 (4) | CRGT/CRLT signedness — lines 480–481 | Signed compare: `(int32_t)acc >= (int32_t)accb`. Fixes #17. | Old bug: unsigned `acc >= accb`. | §6.3 CRGT/CRLT "larger/smaller value (signed)", `06b-instructions-a-h.md`, PDF pp.252/254 |
| 3 (8) | TIM reset value — line 84 | TIM = 0xFFFF at reset (PRD already 0xFFFF). Fixes the TIM half of #12. | Old bug: TIM = 0 at reset. | §9.1.3 item 6; §9.3.2, `09a-peripherals-timer-clock-waitstates.md` lines 117/126/235: "TIM and PRD loaded with FFFFh" |
| 4 (16) | MADD/MADS TRM mirror — line 417 | `treg0 = d` only; TREG1/TREG2 untouched. Fixes N-1. | Old bug: `set_t0()` mirrors to TREG1/TREG2 when `!trm` (the reset default), clobbering later LACT/ADDT/SUBT/BITT operands. | §6.3 MADD/MADS "Affected by: OVM and PM" only, no TRM step, `06c-instructions-i-r.md`, PDF pp.310–317/6-158–6-165 |
| 5 (32) | INTM/XF context restore — line 278 | `restore_ctx()` (RETI/RETE path) does **not** restore INTM or XF from the shadow. Fixes #9. | Old bug: INTM and XF restored from shadow. | §4.8.8, `04-program-control.md`, PDF p.121/4-42 |
| 6 (64) | NDX=0 AR0 mirror — line 592 | When NDX=0 and AR0 changed, INDX = ARCR = new AR0. Fixes #10. | Old bug: mirror missing entirely; INDX/ARCR never follow AR0. | PMST Table 4–3, `04-program-control.md` line 139; §6.3 CMPR, `06b-instructions-a-h.md` lines 1452–1453; §5.2.1 (`05-addressing-modes.md`) |
| 7 (128) | BMAR writeback — lines 340, 405, 420, 422, 424 | Block moves (BLDP, BLPD bmar, MADD/MADS, BLDD bmar,dma, BLDD dma,bmar) advance a local `pfc`; BMAR unchanged. Fixes #15. | Old bug: `c->bmar = pfc` after the loop at all five sites. | §6.3 BLDD/BLDP/BLPD/MADD/MADS execution blocks (`(BMAR) → PFC`, then `(PFC) → MCS`, no BMAR assignment), `06b-instructions-a-h.md` lines 891/1001/1075 |

Notes:
- The bitmask does **not** gate the other two behaviour changes in this core: the `ivec_legacy` INTR fallback (line 521) is unconditional, and the XINT mode is a separate setter (`c5x_set_xint_mode`, line 611) defaulting to the old every-tick behaviour (`xint_mode=0`). The cycle model is likewise a separate switch (`c5x_set_cycle_model`, line 612) defaulting to off.
- `c5x_set_legacy` overwrites the whole mask (`c->legacy = m`), it does not OR bits in — a harness must pass the full desired mask each time.
- No validation of the mask exists: bits above bit 7 are accepted and ignored (no code reads them).

## 4. Smoke tests T1–T9 — NOT RUN

**No test was run, because the build fails (§1).** There is no `.so` or `.o` for the new core, so no harness could be linked. The statements in this section are the audit-04 expectations restated for the merger, plus code-reading predictions — none of them is a measured result for the new core.

Audit 04 §7 expectations (old core, functional PASS on T1–T8, T9 bug confirmed):

| Test | Program (audit 04) | Old-core result | What the new core changes (code reading only) |
|---|---|---|---|
| T1 RPT outer `ADD *` | `BF80 1234, BF90 0001, BF08 0100, 9080, BB03, 2080, 5600` | ACC 0x5B09, mem[0x100]=0x1235, 9 cycles excl trap (manual 12) | Cycle count would change only with `cyc_model=1` (table-dependent, [UNVERIFIED]); functional result should be unchanged — no RPT-path semantics changed. |
| T2 BD, 2×1-word slots | `7D00 0030, 8B80, 8B80, BF80 DEAD, 5600` | ACC 0xBEEF, 4 excl trap | With `cyc_model=1`, delay-slot cycles reset to the branch's own count (§2d); BD relies on `cyc_tab` (not in the forced lists) — value [UNVERIFIED]. |
| T3 BD, 1×2-word slot | `7D00 0030, BF80 1111, BF80 DEAD, 5600` | ACC 0xBEEF, 3 excl trap | Same as T2. |
| T4 RPT BLDD BMAR | `BF80 0200, 881F, BF08 0100, BB02, ACA0, 5600` | mem[0x100]=0x1111, AR0→0x103, 8 excl trap (manual 10) | BMAR writeback now off by default (line 422): after the test, BMAR must still read 0x0200 (old core: 0x0203). Functional copy result unchanged. Cycle count with model on is subject to the inner-loop double-count question in §2d — [UNVERIFIED]. |
| T5 single BLDD #lk | `BF08 0100, A880 0300, 5600` | mem[0x100]=0x2222, 3 excl trap (manual 5) | No BLDD #lk BMAR site exists (immediate form), so no behaviour change; cycles table-dependent. |
| T6 B taken | `7900 0030, BF80 DEAD, 5600` | ACC 0xBEEF, 2 excl trap (manual 6) | B (0x79) is not in the forced-4 list; taken-branch cost relies on `cyc_tab` — [UNVERIFIED]. |
| T7 RPTB BRCR=2 | `AE09 0002, BEC6 0006, BF90 0001, 8B80, 5600` | ACC=3, 8 excl trap (manual 13) | No RPTB-path change in this core; result should be unchanged. |
| T8 CALLD return addr | `7E00 0030, 8B80, 8B80, BF80 DEAD, 5600`; sub `BF80 7777, BE32, BE20, 5600` | Return to 0x24 → ACC 0xDEAD | `delay_slot()` now restores `c->op` (line 267) — no effect on the return address, which is pushed before the slots. Should be unchanged. |
| T9 RPT + B (budget 30) | `BB02, 7900 0030, BF80 DEAD, 5600` | **BUG confirmed (old core): B executed 3×** | **Predicted still buggy (code reading):** the RPT rewind at lines 594–595 still has no repeatability check — `rep_cont` was added but no opcode whitelist. A re-run, once the build works, is expected to still execute B three times. Not measured. |

What a re-run needs: the missing `c5x_cyctab.h` (contents unknown — the merger must obtain it from whoever wrote the new core; it was not in the workspace), then the audit-04 harness (`/tmp/test_c5x.c` from audit 04 was kept in /tmp only and is not part of this report's scope to reproduce). Recommended re-run matrix once it builds: T1–T9 with `cyc_model=0` (functional + legacy-default checks, esp. T4 BMAR readback and a NORM/CRGT/MADD spot check) and again with `cyc_model=1` (cycle counts vs audit-04 §2 table), plus `legacy=0xFF` spot checks that each old behaviour is actually re-enabled.

## 5. Cross-references — nothing else in the workspace knows about the new core

- `c5x_cyctab.h`: referenced by exactly one file — new-core line 10. No other file in `~/workspace/user/files/` or `~/workspace/research_notes/courier-firmware/` mentions it (grep -rn, both trees). The header file itself does not exist anywhere under `~/workspace` or `/tmp` (find, §1).
- New symbols `cyc_model`, `pc_hits`, `watch_hits`, `rep_cont`, `ivec_legacy`, `c5x_set_legacy`, `c5x_set_cycle_model`, `c5x_set_xint_mode`, `c5x_set_watch`, `c5x_idle_cycles`, `cyc_tab`: no references outside `c5x_core-2.c` in the two trees searched. No harness, test, header, or document in the workspace uses the new API yet.
- Nothing in those trees references `c5x_core-2.c` by name at all — the new core is currently unreferenced except by this report.
- Search scope note (updated 00:52 CET, after the full-workspace sweep completed): the full-workspace `grep -rn` has now finished. Workspace-wide, the only references to the new symbols outside `c5x_core-2.c` are in this report file itself (06a). The only other hit for `c5x_cyctab` anywhere in `~/workspace` is `workspace/agents/659feae6-e066-4450-9315-26f14266d56f/exec-logs/proc_5b2ef7969085.log:20` — an execution log recording this worker's own failed compile output, not a source reference. So the "no references" claim in this section is now workspace-wide, not scoped to the two trees.

## 6. Open items for the merger (worker 1's list)

1. **Blocker: `c5x_cyctab.h` is missing.** The new core cannot be built, tested, or verified as a cycle model without it. Obtain the header; do not stub it (its values are the model). Once present, re-run the build exactly as §1 and T1–T9 as §4.
2. **Cycle-model double-count question (§2d):** inner-loop block moves still add `cycles++` per iteration inside `exec1()` and the model adds `cy − 1` on top. Check the table values for BLDD/BLDP/BLPD/MAC/MADD/TBLR/TBLW against the manual repeat formulas (App. B Table B-2, `appendix-b-instruction-classes-cycles.md`; N-11: BMAR forms single 2 / RPT n+1, #lk forms single 3 / RPT n+2) once the header exists.
3. **`ivec_legacy` fallback is unconditional (line 521):** decide whether INTR-via-old-vector should stay live with `legacy=0`, or be gated on a legacy bit. As written, the #1 fix is bypassable through INTR.
4. **NDX distilled-file contradiction (§2e):** `03-cpu-registers.md` line 254 states the opposite NDX polarity to Table 4–3 and §6.3 CMPR. The core follows Table 4–3/CMPR. Worth a one-line PDF check (§3.4, PDF p.73/printed 3-19) at merge time.
5. **Watch-hit PC offset (§2g):** `watch_hits` keys are mid-instruction PCs (X+1/X+2), not instruction starts. Document or fix before any consumer compares them with `pc_hits`.
6. **Untouched findings (§7 below):** #7 (RPT repeats non-repeatables — T9 predicted still failing), `rptc` sentinel clobber, delay-slot BADOP/breakpoint guards, interrupt-entry cost (0 cycles), CLRC/ SETC-INTM shadow (#25/N-14), RPTB last-two-words lockout (#31), wait states, TDM (N-4), IDLE2 (#20, the single VIOLATES form), N-2 serial IFR auto-clear, N-5 SPC reset in serial tick. None of these is addressed by this diff.

## 7. What this diff does NOT change (by code reading)

For the merger's regression list — confirmed by diffing, not by execution:

- RPT enforcement (#7): no repeatability whitelist; `c5x_run()` lines 594–596 rewind on `ppc == rpt_end && rptc > 0` for any opcode. T9 behaviour predicted unchanged.
- `rptc` sentinel: line 596 `else c->rptc = 0;` still clobbers −1 after every instruction (audit 04 §4.2).
- Delay slots: still no BADOP abort, no breakpoint check inside `delay_slot()`, no guard on nested PC changes (audit 04 §3). Only the `c->op` restore and the cycle reset were added.
- Interrupts: entry still 0 cycles (audit 04 §2; manual §3.8 minimum 8 cycles, `04-program-control.md`); serial IFR flags still auto-cleared on trap (N-2, §4.8.2); no CLRC/SETC-INTM one-instruction shadow (#25/N-14, §4.8.9); no XC two-word uninterruptible window (N-13); no RPTB last-two-words lockout (#31, §4.7.2).
- Timing: wait states still never applied (PDWSR/IOWSR/CWSR stored, never read); timer still driven off the counted cycles; IDLE2 still conflated with IDLE (`exec_be` 0x22/0x23 both set `idle = 1`; `tick_timer()` still runs through idle) — finding #20, the single VIOLATES form, untouched.
- Peripherals: TDM entirely unmodelled (N-4, §9.9); serial tick still ignores SPC RRST/XRST (N-5); DXR write still clears XRDY even with XRST=0 (N-17); GREG reset readback still 0x0000 (N-18, §8.4.1 says FF00h).
- Dead code: `sat_acc_shift()` still present and unused; `in_delay` still write-only.
