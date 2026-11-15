# Re-verification 06d — NEW core (c5x_core-2.c): CPU / registers / addressing / interrupts

- **Date:** 2026-11-15 00:44 CET (written in the small hours after the 23:43 core drop).
- **Worker 4 of 5** in the re-check of the revised core. Independent work; another agent merges.
- **NEW CORE:** `~/workspace/user/files/c5x_core-2.c`, 630 lines, md5 `7aa4227d47e9f72abee2b4cb48fb5fef` (read-only, unmodified).
- **OLD CORE:** `~/workspace/user/files/c5x_core.c`, 603 lines, md5 `41c51be7e2edfb5daeda96ce6c80bbb5` (diffed, not modified).
- **Source of truth:** distilled manual `~/workspace/research_notes/courier-firmware/c5x_manual/`
  (SPRU056D June 1998). The June 1998 PDF `~/workspace/user/files/spru056d.pdf` was used as
  tiebreaker nowhere in this file — no distilled-file ambiguity affecting a verdict below
  required it. `c5x_users_guide.txt` (1993), `c5x_opcodes.*`, `c5x_patterns_fixed.json` were
  never used as authority.
- **Prior record:** `c5x_core_audit/05-full-reverification.md` (05) and its area files
  `05d-reverify-cpu-registers-addressing.md` (05d, 151 behaviours) and
  `05e-reverify-interrupts-program-control.md` (05e, 62 behaviours), plus
  `c5x_manual/audit-verification.md`.
- **Method:** every verdict below was checked by reading the NEW core's code directly against
  the distilled manual, and against the old core via `diff -u` for the "what changed" half.
  Line numbers are for the 630-line new core unless marked "old". Verdicts:
  **FIXED / STILL PRESENT / PARTIALLY FIXED / REGRESSED** for prior findings;
  **OBEYS / VIOLATES / PARTIAL / UNVERIFIED** for behaviours. Anything the manual is silent
  on is [UNVERIFIED], never guessed.
- **Judgement basis:** DEFAULT behaviour (`legacy = 0`, `cyc_model = 0`, `xint_mode = 0`)
  is the core's behaviour. Legacy-bit effects are documented separately in §4. Normative
  rule throughout, as in 05: opcode-level §6.3 outranks Ch. 4 prose; specific register
  descriptions/tables outrank boilerplate prose.

## 0. Headline

The new core fixes the two interrupt-blockers that mattered most for an interrupt-driven
SV25 run — the vector table (#1) and the INTM/XF shadow (#9) — and fixes TIM reset (#12,
TIM limb), signed CRGT/CRLT, the BMAR writeback, and the MADD/MADS TRM mirror (N-1) by
default. It does **not** fix RPTC reset (#2), the plain-path INTR context save (#11),
NMI `intm=1` (#27), register-width masking (#28), or `c5x_set` S_ST1/S_PMST (#32). The NDX
mirror (#10) is a real fix with a real hole: it is change-detected, not write-detected, so
a same-value LAR write never mirrors. The INTR save gate (N-10) is fixed as a gate, but
the underlying missing save on the plain path remains. No regression in my areas was found
in the diff; two new tracing-accuracy notes (§3, §7) are observational, not semantic.

## 1. Verdict table — assigned prior findings

| # | Finding | Verdict (new core, default) | New-core evidence |
|---|---|---|---|
| 1 | Vectors TINT/RINT/XINT/TRNT/TXNT/INT4 +0x10 in `ivec[]` | **FIXED** (hardware path); `ivec_legacy[]` second loop in INTR is a deliberate compatibility shim, not a fix — see §2.1 | `:281–282`, `:287` |
| 2 | Block moves zero times as first insn after reset — RPTC init | **STILL PRESENT** | `:59`, `:83` |
| 9 | INTM/XF wrongly shadowed | **FIXED** by default; re-enabled by `legacy&32` | `:278` |
| 10 | NDX=0 AR0→INDX/ARCR mirror missing | **PARTIALLY FIXED** — change-detected mirror works for value-changing AR0 writes; same-value LAR writes never mirror; `ar0_prev` not reset | `:592–593`, `:45` |
| 11 | INTR k incomplete (save only K=1–4; IFR not cleared — correct; IPTR remap [UNVERIFIED]) | **PARTIALLY FIXED** — gate fixed (see N-10), plain-path save still missing; IFR non-clear still correct; IPTR still [UNVERIFIED] | `:517–522` |
| 12 | Reset values wrong (Tables 4–15/4–16) | **PARTIALLY FIXED** — TIM limb fixed; RPTC, PDWSR/IOWSR/CWSR, re-reset staleness all still wrong | `:76–86`, `:84` |
| 27 | NMI missing `intm=1`; TRAP/NMI IPTR remap | **STILL PRESENT** (`intm=1`); IPTR half **carried open, not adjudicated** (§6) | `:503–504` |
| 28 | Register widths unmasked | **STILL PRESENT** (narrowed as in 05) | `:138–147`, `:115` |
| 32 | `c5x_set` no S_ST1/S_PMST | **STILL PRESENT** | `:109–118` |
| N-7 | TRAP/NMI absolute vectors vs §8.2.2 IPTR rule | **Carried open, not adjudicated** (§6) — core unchanged | `:503–504` |
| N-10 | INTR shadow save gated on wrong `ivec[]`, dead for K=4–9 | **PARTIALLY FIXED** — gate now matches for K=1–9 when `ivec_ind` is set; plain-path save still missing | `:520–521` |
| N-14 | SETC INTM same missing next-instruction shadow as CLRC INTM | **STILL PRESENT** | `:495`, `:598` |
| 25 (CLRC half only) | CLRC-INTM shadow missing | **STILL PRESENT** (this worker's half; RETE half is the S–Z worker's, not verdict­ed here) | `:495`, `:598` |
| N-1 (adjacent, §3 of 05) | MADD/MADS apply TRM=0 TREG1/TREG2 mirror | **FIXED** by default; re-enabled by `legacy&16` | `:417` |

## 2. Per-finding detail

### 2.1 #1 — Interrupt vectors — FIXED (hardware path)

- Manual: `04` §4.8.1 Table 4–14 (PDF p.116 / printed 4-37): TINT 08h, RINT 0Ah, XINT 0Ch,
  TRNT 0Eh, TXNT 10h, INT4 12h; confirmed independently by the §6.3 INTR K-table
  (`06b` INTR, PDF p.263 / printed 6-111) and §8.2.2 Table 8–7 (`08`, PDF p.479 / 8-12).
- New core `:281`: `ivec[] = { 0x02, 0x04, 0x06, 0x08, 0x0A, 0x0C, 0x0E, 0x10, 0x12, 0, … }` —
  correct for all nine maskable interrupts. `check_int()` `:287` dispatches
  `(c->iptr << 11) | ivec[i]` with the same bit-ascending priority scan as the old core
  (INT1 > INT2 > INT3 > TINT > RINT > XINT > TRNT > TXNT > INT4, per Table 4–14), so the
  hardware trap path is now fully manual-correct on vectors. Old core `:278` had
  `0x18, 0x1A, 0x1C, 0x1E, 0x20, 0x22` for entries 3–8.
- `ivec_legacy[]` `:282` keeps the old wrong table, used only as a second loop in the INTR
  handler `:521`. It is **not** used by `check_int()` — the hardware path never consults
  it. That is the right split: the wrong values survive only as an INTR-path shim.
- **`intr 17` (0x22) path — checked, and the task's phrasing needs a correction.**
  INTR decodes `v = (op & 0x1f) << 1` `:518`, so K=17 gives v=0x22. Per the §6.3 INTR
  K-table (`06b`, PDF p.263), K=17 **is** the TRAP vector (22h); INT4 is K=9 → 12h.
  So the plain `intr 17` → `pc = 0x22` (`:519`, no save, no indirection) is exactly what
  the manual's K-table says for K=17. It does **not** reach "the INT4 slot" in the manual's
  sense — the INT4 vector is 0x12, reached by `intr 9` or a hardware INT4 trap.
  What the legacy second loop `:521` actually preserves is the *firmware's ROM-stub
  arrangement*: under the old wrong table, hardware INT4 trapped to 0x22, so the firmware's
  INT4 handler lives at (or is reached through) 0x22, and `intr 17` was the firmware's way
  of invoking it. The new core reproduces that **only when the host configured
  `ivec_ind[8]`**: first loop `:520` tests `ivec[i] == v` — no entry is 0x22, so it falls
  through; second loop `:521` tests `ivec_legacy[i] == v`, matches i=8, and then
  `pc = dm_rd(c, c->ivec_ind[8]); save_ctx(c)`. Without `ivec_ind[8]` set, `intr 17`
  goes to absolute 0x22 with no save — manual-correct for K=17, and the INT4-slot
  behaviour is simply absent (as it must be without the host indirection: there is no
  manual INT4-at-0x22). Verdict on the claim as stated: the shim works **conditionally**
  on `ivec_ind[8]`; the comment at `:282` ("reaches the INT4 slot via the ROM-stub model")
  overstates it for the unconfigured case, and "INT4 slot" is firmware-model language,
  not manual language. No manual violation either way: for K=17 the manual states no
  context save (K=17 is not INT1–INT4; see §2.5), so the save-when-indirected is
  [UNVERIFIED] harness behaviour, not a deviation.
- Consequence for 05d J1 / 05e B04: VIOLATES → OBEYS.

### 2.2 #2 — Block moves zero times as first insn after reset — STILL PRESENT

- Manual: `04` §4.9 Table 4–15 (PDF p.125 / printed 4-46): "RPTC — All bits → 0 — Repeat
  counter is cleared"; §4.6 (PDF p.101 / printed 4-22): RPTC "is cleared by reset".
- New core unchanged: `c->rptc = -1` in both `c5x_new()` `:59` and `c5x_reset()` `:83`;
  MMR read 0x08 returns `(uint16_t)rptc` = 0xFFFF after reset (`:139`). Every
  `while (c->rptc > -1)` block move (SMMR `:311`, BLDP `:340`, LMMR `:385`, BLPD
  `:405/407`, TBLR/TBLW `:409/411`, BLDD `:413/415`) still executes zero times as the
  first instruction after reset. `c5x_run()` still normalises `rptc` only *after* each
  `exec1()` (`:595–596`), so the first instruction is unprotected. MAC/MACD/MADD/MADS
  `do…while` loops remain immune, as before. No line in the diff touches `rptc`
  initialisation. 05d I11 / 05e B31 remain VIOLATES.

### 2.3 #9 — INTM/XF wrongly shadowed — FIXED (default)

- Manual: `04` §4.8.8 (PDF p.121 / printed 4-42): the 1-level shadow registers cover ACC,
  ACCB, ARCR, INDX, PMST, PREG, ST0, ST1, TREG0, TREG1, TREG2 — "with the exception of
  the INTM bit in ST0 and the XF bit in ST1. On an interrupt, the INTM bit is always set
  to disable interrupts." Shadows "are copied back … when the RETI or RETE instruction
  is executed."
- New core `restore_ctx()` `:278`: `if (c->legacy & 32) { c->intm = c->sh.intm; c->xf = c->sh.xf; }`
  — with default `legacy = 0`, INTM and XF are no longer restored. RETI `:491`
  (pop + `restore_ctx()`) now leaves INTM at whatever the ISR left it (1 as set at trap
  time, unless the ISR did CLRC INTM — which is precisely the §4.8.8 Example 4–13
  behaviour), and an ISR XF toggle survives RETI. RETE `:492` still does
  `restore_ctx()` + explicit `intm = 0`, net INTM = 0 — correct.
- Caveats, all sub-threshold for the default verdict: (a) `save_ctx()` `:269–273` still
  *stores* `sh.intm`/`sh.xf` (and `check_int()` `:287` still sets `intm = 1` *before*
  `save_ctx()`, so `sh.intm` is always 1). The stored values are dead by default — they
  are only read under `legacy&32` — so this is not a default-behaviour defect, but the
  save side was not cleaned up; (b) under `legacy&32` the old bug returns in full,
  including the always-1 `sh.intm` forcing INTM=1 on RETI (see §4). 05d J9 / 05e B17:
  VIOLATES → OBEYS (default). 05e B14 (RETI must not clear INTM / must not undo an ISR
  CLRC INTM): PARTIAL → OBEYS (default) — RETI no longer restores `sh.intm`, so an ISR
  `CLRC INTM` now survives RETI, as §4.8.5/§4.8.8 require.

### 2.4 #10 — NDX=0 AR0→INDX/ARCR mirror — PARTIALLY FIXED

- Manual: `05` §5.2.1 (PDF p.136 / printed 5-6): "When the NDX bit is cleared, **every
  AR0 modification or LAR write also writes the ARCR and INDX with the same value**.
  Subsequent modifications of the current ARs with indexed addressing will use the INDX…
  The NDX bit is cleared at reset." `04` Table 4–3 NDX row (PDF p.88 / printed 4-9)
  agrees. The contradictory `03` §3.4 line ("if the NDX bit … is set") was already
  resolved normative NDX=0 in 05 (05d §16 item 3).
- New core `:592–593`, in `c5x_run()` after each top-level `exec1()`:
  `if (!c->ndx && !(c->legacy & 64) && c->ar[0] != c->ar0_prev) { c->indx = c->arcr = c->ar[0]; }`
  followed by unconditional `c->ar0_prev = c->ar[0];`.
- What this gets right: it is a *post-instruction change detector*, so it covers every
  AR0 write path without per-site edits — LAR dma (`:303–306` area), LAR #k8, LAR #lk,
  ADRK/SBRK on ARP=0, MAR/`ea()` AR0 updates, MMR writes to AR0 (0x10), LMMR/SMMR
  writes to AR0 — whenever the value actually changes. The `!c->ndx` gate is the
  correct polarity (mirror on when NDX=0, the reset state), and `ar0_prev` is updated
  unconditionally, so toggling NDX off→on→off does not produce a stale trigger.
- What it gets wrong — the mirror is **change-detected, not write-detected**, and the
  manual says "every … LAR write", not "every AR0 change":
  1. **Same-value LAR write never mirrors (new finding 06d-N1, §7).** If AR0 already
     holds 0x50 and INDX was loaded directly to 0x99 (e.g. via LMMR), then
     `LAR AR0,#0x50` must set INDX=ARCR=0x50 per §5.2.1, but `ar[0] == ar0_prev`, so
     the core does nothing and indexed addressing keeps using the stale 0x99. Same for
     any same-value AR0 modification (e.g. `ADRK #0` on AR0, `MAR *` with no step).
  2. **`ar0_prev` is not reset (06d-N2, §7).** `c5x_reset()` `:76–86` never touches
     `ar0_prev` (`:45`); `c5x_new()` zeroes it only via `calloc`. After a re-reset,
     `ar[0]` is 0 but `ar0_prev` keeps the pre-reset value, so the first instruction
     spuriously mirrors INDX=ARCR=0 (benign — both are undefined at reset), while a
     first-instruction `LAR AR0,<pre-reset value>` is missed entirely (same-value case
     against a stale comparator). A host `c5x_set` S_AR0 write between runs has the
     same shape: it is only picked up if the value differs from `ar0_prev`.
  3. **Timing within an instruction / delay slot.** The mirror runs after the whole
     top-level instruction, not at the LAR execution point, and `delay_slot()` calls
     `exec1()` directly (`:262–268`) without the mirror — so an AR0 change inside a
     delay slot is only mirrored at the end of the enclosing branch instruction, and a
     second slot instruction using indexed addressing in between sees the stale INDX.
     (Narrow: LAR itself never consumes INDX, so the common case is unaffected; the
     hole needs an AR0-modifying first slot word followed by an indexed second slot
     word.)
- 05d F1: VIOLATES → PARTIAL. 05d F3 (CMPR vs ARCR): stays PARTIAL — the common
  `LAR AR0` → CMPR case now works, but the same-value miss leaves ARCR stale, and the
  `cmpr_ar0` experiment flag (`:45`, still present) still papers over one case and is
  wrong when NDX=1 or ARCR was loaded directly.

### 2.5 #11 — INTR k incomplete — PARTIALLY FIXED

- Manual, per sub-claim (audit-verification §6, confirmed in 05):
  - (a) Context save: `04` §4.8.7 (PDF p.120 / printed 4-41): "An INTR interrupt for the
    external interrupts (INT1–INT4) executes like an external interrupt described in
    subsection 4.8.2", and §4.8.2 (PDF p.117 / printed 4-38) lists the shadow save
    among the trap actions. Save is therefore required for K=1–4 only; for K≠1–4 the
    manual states nothing. The §6.3 INTR execution block itself lists no save.
  - (b) IFR: `06b` INTR §6.3 (PDF p.263 / printed 6-111): INTR "will not clear the
    appropriate bit in the IFR" — opcode-level, normative over §4.8.2's general
    "flag cleared" action. The core not clearing IFR is CORRECT.
  - (c) IPTR remap: [UNVERIFIED] — see §6.
- New core `:517–522`: `push(pc); intm = 1; pc = v;` then the save only inside the
  `ivec_ind` branches. The **plain path still performs no `save_ctx()`** for any K,
  including K=1–4. A plain `INTR 1`–`INTR 4` therefore still takes the trap with no
  shadow save, and a following RETI/RETE restores a stale shadow (corrupting
  ACC/ACCB/PREG/ST0/ST1/PMST/TREGs/INDX/ARCR). **Still present** for the surviving
  defect. What changed is only the gate (N-10, below): the save branch is now reachable
  for K=4–9 when `ivec_ind` is configured.
- IFR: the INTR path still never touches `ifr` — correct, unchanged. 05d J14 / 05e B24
  remain OBEYS.
- IPTR: the INTR path still uses absolute `pc = v` (`:519`), no `(iptr << 11)` term —
  [UNVERIFIED], unchanged (05d J15 / 05e B25).
- Other INTR limbs unchanged and correct: `v = (op & 0x1f) << 1`, push of PC+1
  (`pc` is post-fetch), `intm = 1`, unaffected by INTM/IMR, K=0 → pc=0 (05d J16 /
  05e B23 OBEYS; whether INTR 0 should also perform §4.9 reset initialisations remains
  [UNVERIFIED], 05e B26).

### 2.6 #12 — Reset values wrong — PARTIALLY FIXED

Checked every register in `04` §4.9 Table 4–15 (PDF p.125 / printed 4-46) and Table 4–16
(PDF pp.126–127 / printed 4-47–4-48) against `c5x_reset()` `:76–86` (new core). Only one
limb changed.

| Register / field | Manual reset value | New core | Verdict |
|---|---|---|---|
| TIM | All bits → 1 (FFFFh) — Table 4–16; §9.1.3 item 6 | `:84`: `tim = (legacy & 8) ? 0 : 0xFFFF` — **0xFFFF by default** | **FIXED** (default; `legacy&8` re-enables 0, §4) |
| PRD | All bits → 1 (FFFFh) | `:84`: `prd = 0xFFFF` | OBEYS (unchanged) |
| RPTC | All bits → 0 — Table 4–15 | `:83`: `rptc = -1` (also `:59` in `c5x_new`) | **VIOLATES** (unchanged; see §2.2) |
| PDWSR / IOWSR | All bits → 1 (wait states 7) — Table 4–16 | Never set in reset; 0 via `calloc` only | **VIOLATES** (unchanged) |
| CWSR | BIG→0, D→1, I/O High→1, I/O Low→1, P→1 — Table 4–16 (i.e. 0x0F in the defined bits) | Never set in reset; 0 | **VIOLATES** (unchanged) |
| GREG | All bits → 0 — Table 4–15 (stored bits; readback FF00h per `08` §8.4.1) | Never touched by `c5x_reset()`; stale on re-reset; readback never shows FF00h upper byte | **VIOLATES** (unchanged; 05d B8/A17) |
| SPC / DRR / DXR | SPC: XRDY→1, RRDY→0, RRST/XRST→0, rest 0; DRR/DXR→0 — Table 4–16 | `xrdy=1; rrdy=0` set (`:84`), but `spc`, `drr`, `dxr`, `mmr_raw[]` never cleared on re-reset | **PARTIAL** (unchanged; 05d B12) |
| INTM→1, OV→0, C→1, CNF→0, HM→1, PM→0, SXM→1, XF→1 | Table 4–15 | `:78–80` all correct | OBEYS (unchanged) |
| PMST: AVIS→0, BRAF→0, IPTR→0, NDX→0, OVLY→0, RAM→0, TRM→0 | Table 4–15 | `:81` all zeroed | OBEYS (unchanged) |
| IFR→0; CBCR CENB1/2→0 | Table 4–15 | `:83` `ifr=0; cbcr=0` | OBEYS (unchanged) |
| TCR TDDR→0, TSS→0 | Table 4–16 | `:84` `tss=0; tcr_tddr=0` | OBEYS (unchanged) |
| MP/MC | Pin-sampled — Table 4–15 | No pin input; `mpmc=0` always (`:81`) | [UNVERIFIED] (unchanged; board strapping unknowable) |
| Undefined at reset (ARP, OVM, DP, ARB, TC, ACC/ACCB/PREG/TREGs/ARs, INDX, ARCR, BRCR/PASR/PAER, BMAR, DBMR) | Undefined — §4.9 "any remaining status bits remain undefined" | Core zeroes most; `indx/arcr/bmar/dbmr/pasr/paer/brcr` untouched on re-reset (stale) | OBEYS-as-default (unchanged; 05d B13) |
| Stack contents / SP | Manual silent | Stack zeroed, internal `sp=0` (`:83`, `:86`) | [UNVERIFIED] (unchanged; 05d B15) |
| Shadow registers `sh` | Not listed in Table 4–15 | Never cleared by reset — a RETI after a reset restores a pre-reset shadow | STILL PRESENT (05e B57; the manual leaves shadow state at reset undefined, so this is a re-reset staleness defect, not a stated-value violation) |
| `ar0_prev` (new state) | N/A (core-internal) | Never reset (`:45` field, no reset line) | New staleness — see 06d-N2 (§7) |
| `idle_cycles`, `pc_hits`, `watch_hits` | N/A (tracing counters) | Not reset | Observational only; no architectural effect |

Net: 05d B10 VIOLATES → OBEYS; 05e B54 stays VIOLATES (narrowed: TIM limb fixed, the
PDWSR/IOWSR/CWSR/DRR/DXR re-reset limbs still wrong); 05e B53 stays PARTIAL (RPTC −1,
GREG stale); 05e B57 stays VIOLATES (now also covering `ar0_prev`).

### 2.7 #27 — NMI missing `intm=1`; TRAP/NMI IPTR remap — STILL PRESENT / OPEN

- `intm=1` half: `06c` NMI §6.3 (PDF p.331 / printed 6-179), Execution: "PC+1 → stack;
  24h → PC; 1 → INTM; Automatic context save is not performed." Also `04` §4.8.5
  (PDF p.119 / printed 4-40) lists the NMI instruction among the INTM-setting events,
  and §4.8.6 (PDF p.120 / printed 4-41) step (2) "interrupts globally disabled (INTM = 1)".
  New core `:504`: `case 0x52: push(c, c->pc); c->pc = 0x24;` — address, push and no-save
  are right, **`intm = 1` is still missing**. Identical to the old core. STILL PRESENT.
  05d J17 / 05e B27 remain PARTIAL.
- TRAP `:503`: `push(c, c->pc); c->pc = 0x22`, no INTM change, no save — correct per the
  normative reading (`06d` TRAP §6.3, PDF p.429 / printed 6-277 + Table 4–5 INTM row,
  overruling §4.8.7 prose; 05 §5 item 4). Unchanged, OBEYS.
- IPTR half: carried forward open — see §6. No adjudication here.

### 2.8 #28 — Register widths unmasked — STILL PRESENT (narrowed as in 05)

No line in the diff touches any width/masking. New-core evidence (same code as old):
TREG1 5-bit / TREG2 4-bit (`03` Table 3-1, PDF p.60 / printed 3-6; §3.5.19, PDF p.79 /
printed 3-25): stored full 16-bit, MMR reads 0x0D/0x0E return unmasked (`:140`); all
use sites mask, so readback-only (05d A6/A7 PARTIAL). CBCR 8-bit (normative per 05d
§16 item 1): stored `uint16_t`, MMR read 0x1E unmasked (`:142`); function inspects
only bits 0–7 (05d A15 PARTIAL). GREG 8-bit, upper byte reads as 1s, reset readback
FF00h (`08` §8.4.1, PDF p.487 / printed 8-20): stored/returned full 16-bit (`:138`),
never FF00h (05d A17 VIOLATES). CWSR 5-bit (`03` §3.5.17): MMR read 0x2A unmasked
(`:147`) (05d A18 PARTIAL). IMR/IFR defined bits 0–8 **and 11 (HINT)** (`04` Figs. 4–7/4–8,
PDF pp.118–119 / printed 4-39–4-40): stored/returned full-width, no masking anywhere
(`:138`; `mmr_wr` 0x04/0x06; `c5x_set` S_IMR `:113`) (05d A19 PARTIAL — the "bits 8–0"
shorthand omits HINT bit 11, as narrowed in 05). `c5x_set` S_ST0 `:115` still does
`arp = v >> 13` with no mask (harness API only). RPTC `int32_t` with −1 sentinel still
reads back 0xFFFF (05d A13 PARTIAL, subsumed by #2). Nothing changed; all 05d
A-row verdicts carry over unchanged.

### 2.9 #32 — `c5x_set` no S_ST1/S_PMST — STILL PRESENT

`c5x_set()` `:109–118` handles S_PC, S_ACC, S_DRR, S_DXR, S_IMR, S_ST0, plus the
numeric cases 40 (push) and 41 (idle), and S_AR0 via the range check. The enum at
`:90–91` defines `S_ST1` (=21) and `S_PMST` (=22), and `c5x_get()` `:100` *reads* both
(`st1_get`/`pmst_get`), but `c5x_set()` has no `case S_ST1` / `case S_PMST` — writes
to them fall through silently and do nothing. Byte-identical to the old core. Harness-API
gap, LOW, as in 05d §13. (Note the asymmetry is now worse in one respect: the new
`legacy`/`cyc_model`/`xint_mode` setters exist as separate functions, but there is
still no way to set ST1/PMST through the state API.)

### 2.10 N-7 — TRAP/NMI absolute vectors vs §8.2.2 IPTR rule — CARRIED OPEN

Core unchanged (`:503–504` absolute 0x22/0x24). This is the same open split as the #27
IPTR half; recorded in full in §6 and **not** verdict­ed as a deviation here.

### 2.11 N-10 — INTR shadow save gated on the wrong vector table — PARTIALLY FIXED

- 05 §3 N-10: the save branch tested `ivec[i] == v` against the wrong table
  (0x18–0x22 for K=4–9), so it could never match for K=4–9 even with `ivec_ind`
  configured. Manual basis: `04` §4.8.7 (PDF p.120 / printed 4-41) + §4.8.1 Table 4–14.
- New core `:520`: `for (i = 0; i < 9; i++) if (ivec[i] == v && c->ivec_ind[i]) … save_ctx(c)`.
  With the corrected `ivec[]`, the comparison now matches for K=1–9 (v = 0x02…0x12)
  whenever the host configured `ivec_ind[i]` for that bit. The gate defect is fixed.
- What remains is the defect the gate was wrapped around: on the **plain path** (no
  `ivec_ind`), no `save_ctx()` happens for any K (§2.5). So N-10 as a *gating* bug is
  fixed; as the *missing-save* bug it is the same #11 defect, still present. Verdict:
  PARTIALLY FIXED. (The second loop `:521` additionally makes the save reachable for
  K=17 when `ivec_ind[8]` is set — see §2.1; for K=17 the manual states no save either
  way, so that is [UNVERIFIED] harness behaviour, not a fix or a violation.)

### 2.12 N-14 / #25 (CLRC half) — SETC/CLRC INTM next-instruction shadow — STILL PRESENT

- Manual: `04` §4.8.9 (PDF p.123 / printed 4-44): "if an interrupt occurs during the
  decode phase of CLRC INTM, the CPU completes CLRC INTM **and the following
  instruction** before processing the pending interrupt… Similarly, SETC INTM and the
  next instruction cannot be interrupted."
- New core: `exec_be` `:495` — `case 0x40: c->intm = 0; case 0x41: c->intm = 1;` — no
  shadow counter, no flag, no deferred-interrupt state anywhere in the diff (no new
  field for it; `grep` for a shadow/deferral mechanism finds nothing). `c5x_run()`
  `:598` still calls `check_int(c)` after **every** `exec1()` (when `rptc <= 0`), so an
  interrupt can be taken immediately after CLRC INTM (before the following RET executes
  — the PC-stack-overflow hazard §4.8.9 exists to prevent) and immediately after
  SETC INTM (so an interrupt can be taken before the following instruction executes
  even though INTM was just set — the window the manual closes). Both halves STILL
  PRESENT. 05d J12 / 05e B50 remain VIOLATES.
- RETE half of #25: explicitly **not** verdict­ed here — the S–Z worker covers it. For
  the record only: no distilled passage states a post-RETE shadow (05 §2 #25, [UNVERIFIED]),
  and nothing in this diff adds one; RETE `:492` is unchanged apart from the `restore_ctx()`
  gate in §2.3.

### 2.13 N-1 (adjacent, 05 §3) — MADD/MADS TRM mirror — FIXED (default)

- Manual: `06c` §6.3 MADD (PDF pp.310–313 / printed 6-158–6-161) and MADS
  (pp.314–317 / 6-162–6-165) list "Affected by: OVM and PM" only, with no TRM step —
  unlike MAC/MACD and the LT family, which do mirror TREG0→TREG1/TREG2 when TRM=0
  (`03` §3.5.19, PDF p.79 / printed 3-25).
- New core `:417`: `if (c->legacy & 16) set_t0(c, d); else c->treg0 = d;` — by default
  MADD/MADS load TREG0 only, so a following LACT/ADDT/SUBT/BITT no longer sees a
  clobbered TREG1/TREG2. TRM=0 is the reset default, so this was a live corruption
  before. FIXED by default; `legacy&16` re-enables the mirror (§4). Note the gate is
  correctly scoped: the LT/LTA/LTD/LTP/LTS/SQRA/SQRS/MAC/MACD paths still call
  `set_t0()` unconditionally, as they should.

## 3. Tracing: `pc_hits` / `watch_hits` / `rep_cont` (and adjacent new bookkeeping)

### 3.1 `pc_hits` — pure observation, no semantic change

- `exec1()` `:302`: `c->pc_hits[c->pc & 0xFFFF]++` on every execution, alongside the
  pre-existing `c->hits[c->pc]++` (`:301`). Array declared `:46`; accessors
  `c5x_pc_hits()` / `c5x_pc_hits_clear()` `:626–627`. It writes only its own counter
  array; it does not touch `pc`, registers, memory, cycles, or control flow. One
  accuracy note: because `exec1()` is also called from `delay_slot()` (`:262–268`),
  delay-slot instructions are counted once each, at their own addresses — which is the
  correct count of executions. No finding. (Counter wraps silently past 2^32 executions
  per PC; irrelevant.)

### 3.2 `watch_hits` — pure observation, but attributed to the wrong PC

- `dm_wr()` `:179`: `if ((int32_t)a == c->watch_a) c->watch_hits[c->pc & 0xFFFF]++;`
  before performing the write; setter `c5x_set_watch()` `:624` (clears the array);
  reader `:625`. Default `watch_a = -1` (`:59`) can never equal a 16-bit address, so
  the check is inert until configured. The write itself is unchanged.
- **Attribution is off by the fetched instruction length (06d-N3, §7, LOW, observational
  only).** At the moment `dm_wr()` runs, `c->pc` has already advanced past the
  instruction's opcode word(s) (`fetch()` `:260` increments `pc`), so a watch hit is
  booked under the *next* instruction's address (insn+1 for 1-word, insn+2 for 2-word
  instructions), not under the storing instruction. A consumer correlating watch hits
  with `pc_hits` will misattribute every hit by one or two words. No execution
  semantics change — the write, the value, and the timing are identical — but any
  analysis built on `watch_hits[pc]` as "the PC that wrote address A" is wrong by that
  offset. Fix direction (not implemented): snapshot the instruction PC at `exec1()` entry
  (already available as `cur_pc`, `:300`) and index by that.

### 3.3 `rep_cont` — not tracing; a cycle-model input with no architectural effect by default

- `rep_cont` is set in `c5x_run()` `:595–596`: 1 when a repeat rewinds (`ppc == rpt_end`
  and `rptc > 0`), 0 otherwise. Its only consumer is the `cyc_model` block `:584–590`:
  `int cy = c->rep_cont ? 1 : cyc_tab[c->op]` — repeated iterations cost 1 cycle.
  With default `cyc_model = 0` the block is skipped entirely, so `rep_cont` has **no
  observable effect** on execution: it does not touch `pc`, `rptc`, registers, or memory.
  With `cyc_model = 1` it changes only `c->cycles` (and hence the number of
  `tick_timer()` calls `:597`), i.e. timing state — which is the cycle model's stated
  purpose and belongs to the cycles worker's area, not mine. Two details for that
  worker's record: (a) `rep_cont` is also forced to 1 only on the rewind path — a
  first-iteration repeat does not set it, so the first iteration is charged the table
  value; (b) the `cyc_model` block reads `c->op` after `exec1()`, which is why
  `delay_slot()` now saves/restores `op` (`:263`, `:267`) and restores `cycles` to the
  pre-slot value when the model is on — again timing-only, and architecturally inert
  because `c->op` is overwritten by the next `fetch()` anyway.
- `words` (`fetch()` `:260`, reset per top-level instruction `:583`) is the same class:
  bookkeeping consumed only by the `cyc_model` sequential-detection test (`:586`).
  `idle_cycles` (`:571`, incremented in the idle loop) is a pure counter. None of these
  alters execution semantics. **No finding** on `rep_cont`/`words`/`idle_cycles` in my
  areas; the `watch_hits` attribution note (§3.2) is the only tracing item filed.

## 4. Legacy bits — what each re-enables in my areas (default `legacy = 0` judged above)

`c5x_set_legacy()` `:613`; comment there documents bit 0, bit 2, bit 3 (bit 1 unused).
Bits are independent; the table judges each in isolation at default-plus-that-bit.

| Bit | Behaviour re-enabled | Manual status of the re-enabled behaviour |
|---|---|---|
| `legacy&1` NORM | Old NORM: `t` from ACC bits 31/30 only (`:396–397`); ACC=0 gives TC=0 plus a shift and an AR modification | **Manual-wrong** (expected legacy): `06c` NORM §6.3 (PDF p.333 / printed 6-181): ACC=0 → TC=1, no shift, no AR modification. Default fixes the ACC=0 limb; the AR-modify-on-TC=1 limb remains wrong even by default (§5, D5 → PARTIAL). |
| `legacy&32` shadow INTM/XF | `restore_ctx()` restores `sh.intm`/`sh.xf` (`:278`); with `check_int()` setting `intm=1` before `save_ctx()` (`:287`), `sh.intm` is always 1, so RETI forces INTM=1 and undoes an ISR CLRC INTM / XF toggle | **Manual-wrong** (expected legacy): `04` §4.8.8 (PDF p.121 / printed 4-42). Default is fixed. |
| `legacy&64` NDX mirror off | `:592` gate fails; no AR0→INDX/ARCR mirroring at all | **Manual-wrong** (expected legacy): `05` §5.2.1 (PDF p.136 / printed 5-6). Default is partially fixed (§2.4). |
| `legacy&8` TIM reset 0 | `:84`: `tim = 0` on reset instead of 0xFFFF | **Manual-wrong** (expected legacy): `04` Table 4–16 (PDF pp.126–127 / printed 4-47–4-48). Default is fixed. Note the gate reads `legacy` at reset time, so the bit must be set before `c5x_reset()` to take effect. |
| `legacy&16` TRM mirror (MADD/MADS) | `:417`: `set_t0()` mirrors TREG0→TREG1/TREG2 when TRM=0 | **Manual-wrong** (expected legacy): `06c` §6.3 MADD/MADS list no TRM step. Default is fixed. Correctly scoped: LT-family/MAC/MACD still mirror unconditionally, as `03` §3.5.19 requires. |
| `legacy&4` CRGT/CRLT unsigned (adjacent; 05d C21 is in my CPU area) | `:480–481`: unsigned `acc >= accb` comparison | **Manual-wrong** (expected legacy): `06b` CRGT/CRLT §6.3 (PDF pp.252/254): "larger/smaller value (signed)". Default is signed — fixed. |
| `legacy&128` BMAR writeback (adjacent; block moves, other workers own the forms) | Block moves write PFC back to BMAR (`:340`, `:405`, `:417`, `:413/415` area) | **Manual-wrong** (expected legacy): `05` §5.4.1 + §6.3 execution blocks never assign BMAR. Default is fixed (05d I13 VIOLATES → OBEYS). |

No legacy bit in my areas is accidentally right: every re-enabled behaviour is one the
manual contradicts. The `legacy` mechanism itself is a test-harness facility, not a
manual feature, and is judged here only for what it re-enables.

## 5. Re-run behaviour tallies (same basis as 05 §4, by code reading of the NEW core)

Basis: the same per-behaviour rows as 05d (A1–L2, 151 rows) and 05e (B01–B62, 62 rows).
Only rows whose verdict changes are listed; every unlisted row keeps its 05 verdict
(I re-checked the diff for each area: the only lines in my areas that changed are the
ones cited in §2–§4 — `ivec[]`, `restore_ctx()`, `tim`, NORM, CRGT/CRLT, MADD/MADS,
BMAR writeback gating, the NDX mirror block, and the tracing/cycle bookkeeping).

### 5.1 CPU / registers / addressing / stack (05d basis, 151 checks)

Old (05d §17): 104 obey / 25 violates / 14 partial / 8 unverified.
New: **109 obey / 18 violates / 16 partial / 8 unverified** (total 151).

| Row | Old → New | Reason (new-core line) |
|---|---|---|
| B10 (TIM/PRD reset) | VIOLATES → OBEYS | `:84` TIM=0xFFFF by default (§2.6) |
| C21 (CRGT/CRLT signed) | VIOLATES → OBEYS | `:480–481` signed comparison by default (§4) |
| D5 (NORM) | VIOLATES → PARTIAL | `:396–397` ACC=0 limb fixed; `ea(c)` still unconditional, so AR is still modified when TC=1 (05d D5 defect (b) survives) |
| F1 (NDX mirror) | VIOLATES → PARTIAL | `:592–593` change-detected mirror (§2.4) |
| I13 (BMAR writeback) | VIOLATES → OBEYS | Writeback now gated on `legacy&128` only (§4) |
| J1 (vectors) | VIOLATES → OBEYS | `:281` corrected `ivec[]` (§2.1) |
| J9 (INTM/XF shadow) | VIOLATES → OBEYS | `:278` restore gated on `legacy&32` (§2.3) |

Per-table new breakdown (OBEYS / VIOLATES / PARTIAL / UNVERIFIED): A 14/1/6/0 ·
B 9/2/2/2 · C 21/0/0/0 · D 6/1/1/0 · E 13/0/1/3 · F 1/0/2/0 · G 7/1/0/1 ·
H 8/2/0/0 · I 8/6/1/0 · J 15/3/2/1 · K 5/2/1/1 · L 2/0/0/0. Sums: 109/18/16/8.
Unchanged VIOLATES still standing in this area (18): A17 (GREG), D6 (SUBC OV/C),
F1 is now partial so no longer here; the remaining violators are A17, D6, E-none,
H6 (LST #0 ARB), H10 (OVLY/CNF data side), I5 (RPT nonrepeatables), I9 (block-repeat
lockout), I10 (RPT in delay slot), I11 (block moves zero times), I12 (SMMR/LMMR
`ea()` re-evaluation), I14 (DMOV side-effect), J12 (CLRC shadow), J13 (INTR save),
J17 is partial, J20 (IDLE2), K5 (XC 1 skip width), K6 (XC sampling), plus B9 (RPTC),
B11 (PDWSR/IOWSR/CWSR), and C21 is now obey so not here. (Count: A17, B9, B11, D6,
H6, H10, I5, I9, I10, I11, I12, I14, J12, J13, J20, K5, K6 = 17, plus G6 delay-slot
stack ordering = 18. G6 was VIOLATES in 05d and is unchanged — the `delay_slot()`
op/cycle save-restore does not touch push/pop ordering.)

### 5.2 Interrupts / program control / reset (05e basis, 62 checks)

Old (05e §4): 27 obey / 12 violates / 17 partial / 6 unverified.
New: **30 obey / 10 violates / 16 partial / 6 unverified** (total 62).

| Row | Old → New | Reason |
|---|---|---|
| B04 (TINT/RINT/XINT/TRNT/TXNT/INT4 vectors) | VIOLATES → OBEYS | `:281` (§2.1) |
| B14 (INTM cleared by CLRC/RETE only; RETI does not clear) | PARTIAL → OBEYS | `:278` — RETI no longer restores `sh.intm` (§2.3) |
| B17 (INTM/XF not saved/restored) | VIOLATES → OBEYS | `:278` (§2.3) |

All other 05e rows keep their verdicts, including: B31 (RPTC) VIOLATES, B27 (NMI
`intm=1`) PARTIAL, B22 (INTR save) PARTIAL — narrowed, not changed: the save is now
reachable for K=1–9 when `ivec_ind` is set, but the plain path still has no save
(§2.5/§2.11); B54 (Table 4–16 reset values) VIOLATES — narrowed: TIM limb fixed,
PDWSR/IOWSR/CWSR/DRR/DXR re-reset limbs still wrong (§2.6); B10 (serial IFR
auto-clear) PARTIAL — `check_int()` `:287` still clears unconditionally, including
RINT/XINT (05 §3 N-2, still present, see §8); B50 (CLRC/SETC shadow) VIOLATES (§2.12);
B49 (interrupt latency) PARTIAL — entry still costs 0 cycles, `check_int()` adds none
even with `cyc_model` on (05 §3 N-9, still present, see §8); B59/B60 (IDLE2) VIOLATES —
`exec_be` 0x22/0x23 still share one `idle` flag and the idle loop still ticks the timer
and wakes on any `ifr & imr` (unchanged in the diff); B25/B26/B29 (IPTR remap,
INTR K=0) UNVERIFIED (§6).

## 6. OPEN SPLIT CARRIED FORWARD — IPTR remap for TRAP / NMI (and INTR)

**Status: OPEN, not adjudicated. Do not implement on one reading alone.** The prior
workers disagreed and it was not adjudicated in 05; this pass does not resolve it. Both
readings are recorded with their citations.

**Reading A (05g; also 05 §3 N-7 as filed): TRAP/NMI vectors ARE IPTR-remapped.**
- `08` §8.2.2 (PDF pp.478–479 / printed 8-11–8-12): "After IPTR is loaded, any
  subsequent interrupt (except for a reset) will fetch its vector from the new location."
  (Distilled wording; the 05g formulation is "any subsequent interrupt (except for a
  reset)".) Table 8–7 in the same section lists TRAP (22h) and NMI (24h) as vectors
  among the other interrupts, with the table headed "locations are offsets added to the
  IPTR page base". The general vector-generation rule (`04` §4.8.1 Fig. 4–6, PDF p.117 /
  printed 4-38: address = (IPTR<<11) | (vector#<<1)) has no exception for TRAP/NMI.
  Under this reading the core's absolute `pc = 0x22` / `pc = 0x24` (`:503–504`) is wrong
  whenever IPTR≠0, and so is INTR's absolute `pc = v` (`:519`).
- Note the §8.2.2 passage as distilled says "any **user** interrupt vector" in one
  sentence and "any subsequent interrupt (except for a reset)" in the operative sentence;
  whether TRAP/NMI count as "user" interrupts is part of the ambiguity.

**Reading B (05d/05e): the remap is UNVERIFIED for TRAP/NMI (and INTR); the opcode pages
state absolute addresses.**
- `06d` TRAP §6.3 (PDF p.429 / printed 6-277): Execution is only "(PC)+1 → stack;
  22h → PC", Status Bits "Not affected by: INTM". `06c` NMI §6.3 (PDF p.331 / printed
  6-179): "PC+1 → stack, 24h → PC, 1 → INTM". `06b` INTR §6.3 (PDF p.263 / printed
  6-111): the K-table gives absolute hex locations (0h–3Eh) with no mention of IPTR.
  No passage states explicitly that TRAP/NMI/INTR vectors are IPTR-remapped; the
  opcode pages state the IPTR=0 case, and the general §8.2.2 mechanism is not an
  instruction-level statement for these three. Under this reading the core's absolute
  addresses are correct as written, and the remap is [UNVERIFIED], not a violation.
- Supporting nuance for B: §8.2.2 itself excepts the reset vector ("reset loads IPTR
  with 0, so the reset vector is always fetched at 0000h"), showing the manual does
  carve out exceptions to the general rule where it means to — and it carves out none
  for TRAP/NMI, which cuts both ways and is why this stays open.

**What the new core does:** absolute 0x22/0x24 for TRAP/NMI (`:503–504`), absolute `v`
for INTR (`:519`), IPTR applied only on the hardware-trap path (`:287`). That matches
Reading B and contradicts Reading A when IPTR≠0. **No verdict is entered on this point
in either direction.** The firmware relevance is real either way: if the SV25 code ever
loads IPTR≠0 and then executes TRAP/NMI/INTR, the two readings diverge observably.
Resolution needs a hardware test or a further manual passage, not another reading of
these two passages.

## 7. New findings from the diff in my areas

| ID | Sev | Finding | Manual citation | Core |
|---|---|---|---|---|
| 06d-N1 | MED | **NDX mirror is change-detected, not write-detected: a same-value LAR write never mirrors.** `LAR AR0,<same value>` (or any AR0 modification that leaves the value unchanged, e.g. `ADRK #0` on AR0) must still write INDX and ARCR per §5.2.1 ("every AR0 modification or LAR write"), but `:592` fires only when `ar[0] != ar0_prev`. Concrete case: AR0=0x50, INDX loaded directly to 0x99, `LAR AR0,#0x50` → INDX stays 0x99, later `*0+` steps by 0x99 instead of 0x50. | `05` §5.2.1 (PDF p.136 / printed 5-6) | `:592–593` (new); old core had no mirror at all (05 #10) |
| 06d-N2 | LOW | **`ar0_prev` is never reset.** `c5x_reset()` does not touch it, so after a re-reset the comparator holds the pre-reset AR0. First-instruction `LAR AR0,<pre-reset value>` is missed (same-value case against a stale comparator); any other first instruction spuriously mirrors INDX=ARCR=0 (benign — both undefined at reset). Same shape for a host `c5x_set` S_AR0 write between runs. | `05` §5.2.1 (PDF p.136 / printed 5-6); `04` Table 4–15 (INDX/ARCR undefined at reset) | `:45`, `:76–86` (no reset line) |
| 06d-N3 | LOW | **`watch_hits` is attributed to the post-fetch PC, not the storing instruction.** `dm_wr()` indexes by `c->pc` after `fetch()` advanced it, so hits land on insn+1 (1-word) or insn+2 (2-word). Observational only — the write itself is unchanged. `cur_pc` (`:300`) already holds the instruction address and would fix it. | N/A — tracing has no manual basis; recorded as a harness-accuracy note, not a manual violation | `:179`, `:260`, `:300`, `:624–625` |
| 06d-N4 | LOW | **NDX mirror is deferred across delay slots.** `delay_slot()` calls `exec1()` directly without the `:592` mirror, so an AR0 change in a slot word is only mirrored when the enclosing branch returns to `c5x_run()`. A second slot word using indexed addressing in between sees the stale INDX. Narrow (needs AR0-modifying first slot word + indexed second slot word); LAR itself never consumes INDX. | `05` §5.2.1 (PDF p.136 / printed 5-6) | `:262–268` vs `:592–593` |

Not filed as findings (checked, no defect): `pc_hits` counting (§3.1); `rep_cont` /
`words` / `idle_cycles` (§3.3 — no architectural effect by default, timing-only under
`cyc_model`); `save_ctx()` still storing `sh.intm`/`sh.xf` (§2.3 caveat (a) — dead by
default); the `ivec_legacy[]` second loop (§2.1 — conditional shim, manual-correct
plain path for K=17); INTR K=17 saving context when `ivec_ind[8]` is set (§2.1 —
manual silent for K≠1–4, [UNVERIFIED], not a deviation).

## 8. Carryovers in my areas — checked, still present, unchanged by the diff

These were already filed in 05 and no diff line touches them; recorded so the merge does
not mistake silence for a fix.

- **N-2 (MED, 05 §3): serial-port IFR flags auto-cleared on trap taken.** `check_int()`
  `:287` `c->ifr &= ~(1 << i)` for every serviced bit, including RINT/XINT/TRNT/TXNT.
  `04` §4.8.2 (PDF p.117 / printed 4-38) excepts "an interrupt flag (other than from an
  active serial port)". 05d J6 / 05e B10 remain PARTIAL.
- **N-9 (MED, 05 §3): interrupt entry costs 0 cycles.** `check_int()` adds no cycles;
  the new `cyc_model` block does not add an entry cost either. Floor is 4 cycles
  (`07` §7.2.2, PDF p.448 / printed 7-6 + App. B class X). 05e B49 remains PARTIAL.
- **N-13 / N-14-adjacent (LOW): XC uninterruptible window not honoured.** `check_int()`
  `:598` runs after every instruction including between XC and its guarded words.
  `06d` XC §6.3 (PDF pp.430–431 / printed 6-278–6-279); `04` §4.5.6 (PDF p.100 /
  printed 4-21). Unchanged.
- **#20 IDLE2 conflated with IDLE** (05d J20 / 05e B59–B60, VIOLATES): `exec_be` 0x22/0x23
  still set the same `idle` flag; the idle loop still ticks the timer and wakes on any
  `ifr & imr`. No diff line touches either.
- **#7 RPT repeats nonrepeatables; #8 RPTB PAER off-by-one; #31 block-repeat lockout;
  #14 SMMR/LMMR `ea()` re-evaluation; #16 DMOV side-effect; #21 LST #0 ARB; #22 `*BRO±`
  circular wrap; #24 SUBC OV/C; #26 delay-slot stack ordering** — all unchanged in the
  diff; 05 verdicts stand (see §5.1 for the counts).

## 9. Method note / limits

- Code-reading only, same as 05: no execution tests were run (no build/run harness was
  in scope for this worker; the core was read, diffed, and checked line-by-line). The
  tallies in §5 are recounts of the 05d/05e row sets against the new code, not new
  test results.
- The `c5x_cyctab.h` include (`:9`) and the `cyc_model`/`rep_cont` machinery were
  assessed only for whether they change execution semantics in my areas (§3.3); cycle
  *values* are the cycles worker's area.
- No file was modified except this output file and the one `progress.log` line.
