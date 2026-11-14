# TMS320C5x User's Guide (SPRU056D, June 1998) — Distilled Reference

Agent-consumable distillation of the full manual. Dense tables, short prose only where
rules need sentences. No tutorialising, no invented examples.

## Provenance (read first)

- **Source (only authority):** `~/workspace/user/files/spru056d.pdf` — TMS320C5x User's
  Guide, Literature Number SPRU056D, June 1998, 764 pages.
  SHA-256 `a31e285f1be9fe87064e914de7bce6c96a99dd53bea3f3882c9fbe56bd45ce30`.
  Identical to `~/workspace/research_notes/courier-firmware/c5x_users_guide.pdf`.
- **Extraction:** fresh `pdftotext -layout` of the PDF (42,379 lines). Where layout
  extraction was garbled, values were checked against rendered pages (`pdftoppm`,
  150–300 dpi) or marked `[UNVERIFIED — …]` — never guessed.
- **Explicitly NOT used:** `~/workspace/research_notes/courier-firmware/c5x_users_guide.txt`
  (unreliable — its front matter claims January 1993 while the PDF is June 1998; its
  tables are garbled) and `c5x_opcodes.json` / `c5x_opcodes.txt` / `c5x_patterns.json`
  (derived from the wrong edition / corrupted parsing; see §Counts below).
- **Citation rule:** every factual claim carries manual section + table/figure number +
  BOTH page numbers (PDF index page and printed page, e.g. "PDF p.200 / printed 6-48").
  Where the two differ, both are stated. `INFERENCE` marks a conclusion drawn, not
  stated; inferences are kept out of tables. `[UNVERIFIED — …]` marks garbled/illegible
  extraction; unverified claims never appear in summaries or tables as fact.
- **Contradictions:** where the manual contradicts itself, BOTH readings are recorded
  in the chapter file with refs and a normative call (opcode execution tables in §6.3
  outrank prose; summary tables outrank prose for device lists). Never silently picked.
- **Scope:** C5x-family-generic unless a file says C51-specific. Per-device feature
  tables are transcribed in `01`/`02`/`09b`; C51 verdicts are in §C51 facts below.

## How to use it

| File | Manual part | PDF pp. | Printed pp. | Lines |
|---|---|---|---|---|
| [01-introduction.md](01-introduction.md) | Ch. 1 Introduction | 34–42 | 1-1–1-9 | 196 |
| [02-architectural-overview.md](02-architectural-overview.md) | Ch. 2 Architectural Overview | 43–54 | 2-1–2-12 | 267 |
| [03-cpu-registers.md](03-cpu-registers.md) | Ch. 3 CPU | 55–79 | 3-1–3-25 | 475 |
| [04-program-control.md](04-program-control.md) | Ch. 4 Program Control | 80–130 | 4-1–4-51 | 696 |
| [05-addressing-modes.md](05-addressing-modes.md) | Ch. 5 Addressing Modes | 131–152 | 5-1–5-22 | 484 |
| [06a-instruction-set-summary.md](06a-instruction-set-summary.md) | Ch. 6 §§6.1–6.2 symbols + Tables 6-1–6-11 | 153–178 | 6-1–6-26 | 435 |
| [06b-instructions-a-h.md](06b-instructions-a-h.md) | Ch. 6 §6.3, ABS–LACC (46 entries) | 179–268 | 6-27–6-116 | 1948 |
| [06c-instructions-i-r.md](06c-instructions-i-r.md) | Ch. 6 §6.3, LACL–RET (36 entries) | 269–354 | 6-117–6-202 | 2382 |
| [06d-instructions-s-z.md](06d-instructions-s-z.md) | Ch. 6 §6.3, RETC–ZPR (51 entries) | 355–442 | 6-203–6-290 | 1477 |
| [07-pipeline.md](07-pipeline.md) | Ch. 7 Pipeline | 443–467 | 7-1–7-25 | 172 |
| [08-memory.md](08-memory.md) | Ch. 8 Memory (incl. full MMR map 0x00–0x5F) | 468–509 | 8-1–8-42 | 533 |
| [09a-peripherals-timer-clock-waitstates.md](09a-peripherals-timer-clock-waitstates.md) | Ch. 9 §§9.1–9.6 control/clock/timer/wait-states/GPIO/parallel | 510–531 | 9-1–9-22 | 595 |
| [09b-peripherals-serial-bsp-tdm-hpi.md](09b-peripherals-serial-bsp-tdm-hpi.md) | Ch. 9 §§9.7–9.10 serial/BSP/TDM/HPI | 532–613 | 9-23–9-104 | 859 |
| [appendix-a-pinouts.md](appendix-a-pinouts.md) | App. A Pinouts and Signal Descriptions | 614–637 | A-1–A-24 | 896 |
| [appendix-b-instruction-classes-cycles.md](appendix-b-instruction-classes-cycles.md) | App. B Instruction Classes and Cycles | 638–649 | B-1–B-12 | 274 |
| [appendix-c-to-i.md](appendix-c-to-i.md) | App. C Migration, D XDS510, E Memories/Sockets/Crystals, F ROM Codes, G Dev Support/Orders, H Glossary, I Updates | 650–764 | C-1–I-8 | 1410 |
| [audit-verification.md](audit-verification.md) | Verification of 10 audit HIGH findings vs this 1998 PDF | — | — | — |
| **Total (chapter files)** | **Ch. 1–9 + App. A–I** | **34–764** | | **13,099** |

Start points by question: instruction encoding/cycles → `06a` (summary) then `06b`/`06c`/`06d`
(full entry); registers/status bits → `03` + `04` §4.4; interrupts/vectors → `04` §4.8
and `08` Table 8–7; memory map/MMRs → `08`; timer/serial → `09a`/`09b`; timing classes
→ `appendix-b-instruction-classes-cycles.md`; C51 device facts → §C51 facts below.

## Counts (machine-checked against the written files)

- **Instruction set:** Tables 6-4–6-10 = **179 printed rows, 178 distinct patterns,
  132 mnemonics** (`06a`). §6.3 describes **133 mnemonics (46 + 36 + 51)** — all 132
  table mnemonics **plus APAC**, which has a §6.3 description (PDF p.199 / printed 6-47)
  and an Appendix B listing but **no row in Tables 6-4–6-10**. No gaps, no overlaps at
  the §6.3 split boundaries (LACC/LACL, RET/RETC).
- **On-record derived counts are wrong — manual wins:** the old derived files claim
  191 forms / 122 mnemonics / 182 unique patterns. They list non-mnemonics (ACC, AR,
  BMAR), omit 10 real mnemonics (AND, B, CALL, CALLD, CALAD, CC, CCD, CPL, LTS, SBRK),
  and contain garbage bit-strings (`PagekkkkBoldthat`, `CallcallINTR1101`). They derive
  from §6.3 syntax parsing of the wrong edition, not from Tables 6-4–6-10.
- **Appendix B:** Table B-2 = **155 rows** (class counts cross-checked B-1 vs B-2).
- **Appendix A:** **604 pins** transcribed (100/100/128/132/144 per package, each pin
  1..N exactly once, mechanically verified).
- **Appendix C:** Tables C-1–C-8, **153 mappings**. **Appendix H:** **352 glossary
  entries**. **Appendix I:** **38 update entries**. **Appendix G:** Table G-1, 13 tool
  part numbers.

## C51 facts (the device this distillation was built for)

- **Serial ports:** 2 — 1 standard serial port + 1 TDM serial port (stand-alone mode =
  second standard serial port). **BSP: NO. HPI: NO.** (`02` Table 2–1, `09b` §§9.8–9.10;
  prose in §§2.4.5/2.4.7/9.8/9.10 omits the 'LC57S rows the tables include — tables
  normative.)
- **Memory:** 1056 words DARAM (B0/B1/B2) + 1K SARAM + 8K ROM (bootloader). 20 ns grade
  (50 MIPS) only on 5-V 'C51/'C52. (`01` Table 1–1, `02` Table 2–1.)
- **Interrupt vectors (confirmed in `04` §4.8, `06b` INTR, `08` Table 8–7 — all agree):**
  RS 00h, INT1 02h, INT2 04h, INT3 06h, **TINT 08h, RINT 0Ah, XINT 0Ch, TRNT 0Eh,
  TXNT 10h, INT4 12h**, HINT 18h ('C57-only), TRAP 22h, NMI 24h.
- **CALAD opcode is `0xBE3D`** (`1011 1110 0011 1101`), §6.3 PDF p.236 / printed 6-84
  and Table 6-8 — attested twice. (An earlier audit working from the 1993 OCR text
  claimed CALAD = 0xBE31 and BE3D a phantom; that is backwards — see
  [audit-verification.md](audit-verification.md).)
- **ACC is exactly 32-bit; no guard bits** (`03` §3.2 — nothing in Ch. 3 mentions them).
- **Timer:** TIM/PRD reset to FFFFh; prescaler TDDR+1, timer period
  `1/[tc(C)·(TDDR+1)·(PRD+1)]` (`09a` §9.3). **Wait states:** 'C51 uses the 2-bit-per-16K-block
  PDWSR variant (Fig. 9–4 names 'C51 explicitly) (`09a` §9.4).
- **IDLE3 does not exist on C5x** ("IDLE3" occurs 0 times in the manual; "IDLE1" occurs
  once, Ch. 1, as the name for the plain IDLE instruction) (`04` §4.10).

## Unverified list (nothing guessed; full wording in the cited file)

- `01`: Fig. 1–1 performance data (graphical, PDF p.36 / 1-3); per-device PLL factors
  (x1–x9, no per-device table in Ch. 1–2); Table 1–1 HPI footnote `||` unattached to
  any row (PDF p.39 / 1-6).
- `03`: `RBIT` label in Fig. 3-1 unexplained (PDF p.57 / 3-3); `dma(7)` meaning
  unexplained (Table 3-1, PDF p.58 / 3-4); SFR prescaler has no prose description
  (Fig. 3-2 only); HPIC/HPIA/TIM/PRD widths unstated in Ch. 3; SXM effect on ROL/ROR
  unstated; figure wire-level connectivity not verifiable from text extraction.
  (One INFERENCE in `03` §13: 'C51 falls under scheme-A wait states — since confirmed
  by `09a` Fig. 9–4; treat as confirmed, not inference.)
- `04`: bold/new-for-'C5x marking in Tables 4–10–4–13 lost in extraction (PDF pp.102–109 /
  4-23–4-30); Fig. 4–10 waveform numeric detail (PDF p.128 / 4-49); CBCR/PMST data-memory
  addresses not stated in Ch. 4; whether INTR performs the §4.8.8 shadow save (unstated);
  serial-port IFR-clear mechanism (unstated in Ch. 4); per-device list of the 9 used
  interrupts (see §9.1.2).
- `05`: Fig. 5-4 diagram body garbled (`Á` box-drawing; layout recovered from Tables 5-1/5-3);
  §5.2.3 exponents extracted as "2n–1"/"2n" (intended 2^n−1/2^n, superscript lost);
  bit-diagrams in Examples 5-1–5-8 partially garbled (prose words cross-checked);
  diagram geometry of Figs. 5-1/5-3/5-10 (prose cited instead). NDX=1 behaviour is
  **not stated anywhere in Ch. 5** — recorded as a gap, not guessed.
- `06a`: none — every row visually confirmed on 200 dpi renders (300 dpi crops for LDP,
  MPY #k13, INTR).
- `06b`: none full-entry; IN (PDF p.261) Execution line "Port address → dma" reproduced
  verbatim, flagged semantically unclear; BLDD RPT long-immediate DARAM→DARAM row
  placement labelled INFERENCE.
- `06c`: none full-entry; garbled multi-value cycle cells (MAC, MACD, MADD, MADS, OR, OUT)
  verified against rendered page images before transcribing.
- `06d`: none — every bit row/cycle table legible, ambiguous cells cross-checked against
  a second extraction mode.
- `07`: none — extraction clean, all tables cross-checked.
- `08`: none — all box-drawing-garbled tables verified against rendered page images
  (pdftoppm 150 dpi).
- `09a`: none — every garbled extraction resolved by inspecting rendered pages
  (PDF pp.515–528).
- `09b`: Fig. 9–14 SPC + Figs. 9–33/9–36 SPCE diagrams garbled (bit maps taken from
  Tables 9–13/9–17/9–20); Fig. 9–43 TSPC diagram garbled (positions beyond bit 0 not
  asserted); Figs. 9–48/9–49 HPIC host-side high-byte values garbled (low nibble confirmed
  via Table 9–27); Tables 9–30–9–32 latch cells partly garbled (legible values only);
  §9.1.3 item 5 SPC reset pattern rendered "0y00h" (per-bit values from Table 9–13;
  SPC reset = 0800h + live IN1/IN0 marked INFERENCE); §9.8.2.2 N-definition superscripts
  lost (alignment rule taken from Fig. 9–38 worked example).
- `appendix-a`: Figs. A–1–A–5 edge-label order scrambled in extraction (tables govern;
  pin 61 `X2/CLKIN1` verified on a 200-dpi render, PDF p.616); Table A–16 BCLKX
  description says "CLKX" where BCLKX is meant (as printed).
- `appendix-b`: bold "new for 'C5x" marking lost in extraction, not reproduced.
- `appendix-c-to-i`: App. C Fig. C–3 pin-diagram detail; App. D Fig. D–2 schematic detail
  (legible values only); App. I reprinted Table 8–6 (p.I-8) garbled — its new Off-Chip
  values not transcribed; App. I figures/tables reprinted there summarised, not re-reprinted.

## Contradictions register (both readings + normative call in the cited file)

- `01`/`02` (C-1–C-11): prose names plain 'C56/'C57, tables list only 'LC56/'LC57;
  HPI device list differs between §1.3, §2.4.5 and Table 2–1 (tables normative);
  BSP device list differs between §2.4.7, §1.3 and Table 2–1 (tables normative);
  Ch. 1 title-page device list omits 'LC57S; §2.3.1 bootloader claim vs Table 1–1;
  §2.2.4 calls Ch. 4 "Memory" (it is Program Control); §2.4.4 misdescribes Table 2–1.
- `03` (C1–C4): CBCR 8-bit (tables/figures) vs 16-bit (§3.5.6 prose) — 8-bit normative;
  ACCH/ACCL "byte" vs two 16-bit segments — 16-bit normative; BSAR worked example is
  arithmetically wrong (manual prints 02468ACEh, verified 002468ACh — do not use as a
  test vector); CRLT/CRGT examples work only as two independent examples.
- `04` (C1–C4): LST #0 / ARP — §4.4.3 prose says ARP unaffected, Table 4–5 and Ch. 6 LST
  say LST #0 loads ARP (Ch. 6 normative); TRAP / INTM — §4.8.7 says TRAP sets INTM=1,
  Table 4–5 and Ch. 6 TRAP say INTM unaffected (Ch. 6 normative); serial-port IFR
  auto-clear exception in §4.8.2 omitted from §4.8.3's list (§4.8.2 normative);
  "INT16 lowest priority" framing vs Table 4–14 (lowest real priority is INT4).
- `05`: none semantic (Table 5-2 vs 5-3 reverse-carry rows agree exactly; §5.6 wrap rule
  vs Ex. 5-13 cases 5/7 consistent — wrap triggers only on pre-update equality with CBER).
- `06a`: SPAC printed twice identically (Table 6-7); LDP #k prints `1011 110I kkkk kkkk`
  (capital I at bit 8 — likely misprint); MPY #k13 prints only 15 bit-positions (12 k's —
  likely missing k); INTR prints `1011 1110 011I NTR#` (I = first glyph of symbol name);
  APAC missing from summary tables (see §Counts); Table 6-1 ZLVC example sentence
  contradicts its own L-bit definition; LPH/LT printed under Table 6-6 (PLU) though
  they are TREG0/PREG loads.
- `06b`: BLDD §6.2 lists one representative opcode, §6.3 eight distinct forms (summary
  abbreviation); AND Status Bits block has no "Affects" line as printed; CMPL Execution
  overbar lost in extraction (Description authoritative).
- `06c`: MADD Execution says `(PC) + 2 → PC` but Words = 1 (MADS says +1); MADS
  single-instruction External Memory cell blank as printed (expected value given only as
  INFERENCE); OUT Execution ends `(dma) → Port address`, inconsistent with its own
  description (reproduced verbatim); LST status table lists ARB under "Affects" but
  description says LST #0 does not affect ARB (applies to LST #1).
- `06d`: RETC §6.3 True 4 / False 2 vs Table 6–8 single value 2; RETCD §6.3 flat 2 vs
  Table 6–8 "4¶ or 2#" (summary side matches `06a`); SMMR printed Execution block is a
  PFC/MCS block-move execution contradicting SMMR's own Description (Description normative);
  SAMM RPT External/MMPORT cell printed "2n+2+p+p niodst" (as printed); SFRB Description
  names "the SFR instruction" twice; SFLB Execution line unbalanced parenthesis (closing
  paren restored, noted).
- `07`/`08`: GREG reset — Table 4–15 "all bits → 0" vs §8.4.1 "upper 8 bits read as 1s"
  (resolved: stored bits 0, read value at reset FF00h); §8.2.4 protection vs §8.2.1/§8.3.1
  mapping (scoped: protection applies only under the protection mask option); §8.8.3
  "transfers control to the source address" vs §§8.8.2/8.8.3.1 "branch to destination
  address" (verbatim flag); Table 8–16 prints only 0–3 wait states while §8.10 text says
  up to 7 (rows 4–7 not extrapolated); Table 8–6 'C57S row leaves 0800h–7FFFh unaccounted
  (as printed).
- `09a`: §9.1.1 "17 peripheral registers" vs Table 9–1 enumerating 16 addresses (table
  normative); timer reload "decremented past 0" (Table 9–4) vs "decrements to 0" (§9.3.2)
  (§9.3.2 borrow semantics normative).
- `09b` (C1–C6): serial-port max clock CLKOUT1/4 (§9.7) vs CLKOUT1/2 (Table 9–16) (§9.7
  normative for internal clock); §9.8.3.1 "(TXM = 1)" vs Table 9–13 + Fig. 9–40 (TXM = 0 —
  misprint); HPI/BSP on 'LC57S — tables include it, prose omits it (tables normative);
  TDM on "'C53 devices" — prose includes 'C53S, tables exclude it (tables normative);
  §9.1.3 item 7 HINT "set after reset" vs Table 9–27 HINT=0 on reset (table normative).
- `appendix-b`: B-1 calls the RPT #k class "XXIIX", B-2 calls it "XXIX"; IDLE/IDLE2 listed
  in Class I without "not repeatable" in B-1 but marked not repeatable in B-2.
- `appendix-c-to-i`: App. D §D.8 Case 4 "timed from TCK_RET low" but uses the TCK_RET-high
  value (24 ns vs 20 ns); "tckfactor" printed for "ttckfactor" (as printed).

## What was left out or summarised (and why)

- **Worked examples in §6.3** omitted (per scope — rules/constraints transcribed; examples
  carry no additional normative content). Manual worked examples elsewhere transcribed
  only where they state a rule (e.g. §9.3 50 kHz timer example, verified arithmetically).
- **App. A Tables A–7–A–18 signal descriptions** condensed to one line per signal
  (verbatim quotes kept where load-bearing); the pin tables themselves are fully transcribed.
- **App. C/D/F/G prose** condensed to operative rules/process; **App. E** transcribed in
  full (lists/part numbers); **App. G** Table G-1 transcribed, contact/ordering data flagged
  as historical 1998 data.
- **App. H glossary:** all 352 entries included (138 "See …" cross-refs included).
- **App. I:** all 38 update entries transcribed; figures/tables reprinted in App. I
  summarised, not re-reprinted.
- **Ch. 7 gaps (in the manual, not omissions here):** no RPT behaviour, no interrupt pipeline
  timing (except the CNF/RETE note), no delayed-branch discussion, no HOLD coverage.
- **Ch. 5 gaps (in the manual):** stack addressing, I/O-port addressing, TBLR/TBLW, standalone
  pma addressing, CBCR bit layout and AR↔buffer mapping (deferred to §4.4.1), NDX=1.
- **Ch. 3:** only two reset values are stated in Ch. 3 (carry C = 1; circular buffers disabled
  on RS rising edge); all other registers' reset values are stated as absent, not assumed —
  see `04` Tables 4–15/4–16 and `08` for the reset table.

## Cross-chapter consistency checks performed

- Instruction coverage: Tables 6-4–6-10 (179 rows / 132 mnemonics) vs §6.3 (133 entries) —
  exact match plus APAC (see §Counts). Boundary mnemonics verified (LACC/LACL, RET/RETC).
- Interrupt vectors: `04` §4.8 Table 4–14, `06b` INTR K-table, `08` Table 8–7 — agree
  (TINT 08h, RINT 0Ah, XINT 0Ch, TRNT 0Eh, TXNT 10h, INT4 12h, TRAP 22h, NMI 24h).
- CALAD = 0xBE3D: attested in `06a` Table 6-8 and `06b` §6.3 entry — agrees.
- RETI/RETE shadow scope: `04` §§4.4.2/4.4.3/4.8.8 agree (11 registers + PC; INTM/XF excluded).
- 'C51 wait-state scheme: `03` INFERENCE (scheme-A) confirmed by `09a` Fig. 9–4 (names 'C51).
- MMR map: lives split across `08` Table 8–13 (0x00–0x1F) and `09a` Table 9–1 (0x20–0x5F);
  reset values taken from `04` Tables 4–15/4–16, cited per row in `08`.
- 'C51 peripherals: `01`/`02` tables, `09a` §9.2 device lists, `09b` §§9.7–9.10 device lists —
  agree (SP yes, TDM yes, BSP no, HPI no).

## Method note

Twelve per-chapter workers distilled from the fresh `pdftotext -layout` extraction, each
citing § + table/figure + dual page numbers; the merge re-checked opcode/vector/bit-layout
agreement across chapters against the PDF and recorded the discrepancies above. Timestamps
per completed chapter are in `~/workspace/research_notes/courier-firmware/progress.log`.
