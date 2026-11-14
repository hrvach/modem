# TMS320C5x Pipeline — Chapter 7 Distillation

**Source (only authority):** `~/workspace/user/files/spru056d.pdf` — SPRU056D, *TMS320C5x User's Guide*, June 1998, Chapter 7 "Pipeline".
**Range:** PDF pp. 443–467 = printed pp. 7-1–7-25. Page mapping: printed page = PDF page − 442.
**Citation convention:** every claim carries manual section + table/figure + PDF page / printed page.
`[UNVERIFIED — ...]` marks garbled extraction (none in Ch. 7 — extraction clean, all tables cross-checked).
`INFERENCE:` marks conclusions drawn from, but not stated by, the manual; kept out of tables.
Device scope: family-generic unless stated. No C51-specific pipeline behaviour is stated in Ch. 7.

## 7.1 Pipeline structure — §7.1, Fig. 7–1 (PDF p. 444 / printed 7-2)

Four independent phases; fetch, decode, operand read and execute overlap, so overall instruction executions overlap (§7 intro, PDF p. 443 / 7-1).

| Phase | Symbol | Function |
|---|---|---|
| Fetch | F | Fetches instruction words from memory; updates PC |
| Decode | D | Decodes instruction word; address generation; ARAU updates of auxiliary registers |
| Read | R | Reads operands from memory if required. With indirect addressing, reads the location pointed at by ARP **before** the update of the previous decode phase |
| Execute | E | Performs the specified operation; if required, writes results of a previous operation to memory |

- Perfect overlap (Fig. 7–1): single-word single-cycle instruction, no wait state — all four phases operate in parallel; in any cycle, F = N, D = N−1, R = N−2, E = N−3.
- **Conflict definition:** when more than one pipeline stage requires processing on the same resource (memory, CPU registers), a pipeline conflict occurs. There is **no priority** between the four phases; unexpected results can occur. Avoid any conflict between the four phases (§7.1, PDF p. 444 / 7-2).

## 7.2 Pipeline operation — §7.2 (PDF p. 445 / printed 7-3)

- Pipeline is essentially invisible to the user **except**: auxiliary register updates, memory-mapped accesses of CPU registers, the NORM instruction, memory configuration commands.
- **Pipeline operation is not protected.** The user must understand pipeline operation and avoid pipeline conflict by arranging the code (§7.2, PDF p. 445 / 7-3).

### 7.2.1 Normal pipeline operation — §7.2.1, Ex. 7–1 / Table 7–1, Ex. 7–2 / Table 7–2 (PDF pp. 445–448 / 7-3–7-6)

**Rules (from Ex. 7–1, Table 7–1, 1-word instructions; mem 60h=10h, 61h=3h, 62h=6h):**

| Rule | Evidence |
|---|---|
| R phase reads the location pointed at by the AR **before** the D-phase update of the preceding cycle (pre-update value) | Table 7–1 cycle 3: R reads 60h although D updated AR6 in cycle 2; cycle 5: R reads 61h, AR6 updated in cycle 4 |
| D-phase ARAU update and R-phase read of the same AR in the same cycle use the pre-update pointer | Table 7–1 cycles 3, 5, 6 |
| E phase uses the operand read two cycles earlier (R at cycle n → E at cycle n+1 for the same instruction; result visible one cycle after R) | Table 7–1: ADD reads 60h cycle 3, executes cycle 4 (ACC=30h) |
| SAMM (memory-mapped store) executes in E: TREG0 = ACC at cycle 5 | Table 7–1 cycle 5 |
| MPY reads TREG0 (written by SAMM in E, cycle 5) and the operand read in cycle 5, executes cycle 6 (PREG=90h) | Table 7–1 cycle 6 |
| SQRA: E at cycle 7 adds ACC (30h) to PREG (90h) → ACC=C0h, and stores the cycle-6 read (6h) to TREG0, squares it → PREG=24h | Table 7–1 cycle 7 |

**Rules (from Ex. 7–2, Table 7–2, 2-word instructions; mem 60h=10h, 61h=3h):**

| Rule | Evidence |
|---|---|
| Second word of a 2-word instruction is fetched in F; the following D phase is a **dummy** (previous fetch phase is an operand) | Table 7–2 cycle 4: D = dummy; cycle 3: F fetches `1000h` |
| R phase of a 2-word instruction is a dummy/operand-fetch-on-fetch-phase; the immediate is not read via R | Table 7–2 cycles 4–6 |
| E of ADD #1000h: ACC 10h + 1000h = 1010h at cycle 5 | Table 7–2 cycle 5 |
| SACL `*+,0,AR2` stores ACC to the location pointed at by AR1 **before** the cycle-5 D update (61h), executes cycle 7 | Table 7–2 cycle 7; text PDF p. 448 / 7-6 |

### 7.2.2 Branch and subroutine call — §7.2.2, Ex. 7–3/7–4/7–5, Tables 7–3/7–4/7–5 (PDF pp. 448–456 / 7-6–7-14)

**Headline rule:** the pipeline is 4 levels deep, so normally any branch, subroutine call, or return-from-subroutine instruction (Table 6–8, p. 6-17) takes **4 cycles to flush the pipeline**. The conditional branch (BCND) also takes 4 cycles when the condition is true (§7.2.2, PDF p. 448 / 7-6).

| Case | Behaviour | Ref |
|---|---|---|
| BCND, condition **true** | PC update and D phase of cycle 5 depend on the E-phase result of BCND. PC is loaded with the destination (LBL, the BCND operand word); dummy ops flush D/R/E; the instruction at LBL is fetched in cycle 5, decoded cycle 7, read cycle 8, executed cycle 9. Net: 4 flush cycles (cycles 5–8 dummy/flush, useful work resumes E at cycle 9) | Ex. 7–3, Table 7–3 (PDF pp. 449–450 / 7-7–7-8) |
| BCND, condition **false** | PC updates to the next instruction; BCND is treated as a 2-word instruction; **no flush** — the following ADD is decoded in cycle 5, read cycle 6, executed cycle 7; SUB executes cycle 8, SACL cycle 9 | Ex. 7–4, Table 7–4 (PDF pp. 451–452 / 7-9–7-10) |
| CALL | E phase (cycle 5) pushes the return address (address of the instruction after CALL) onto TOS and loads PC = LBL. Fetch of the subroutine's first instruction (SUBB) in cycle 6; dummy flush in D/R/E cycles 5–6; SUBB decoded cycle 7, read cycle 8, executed cycle 9 | Ex. 7–5, Table 7–5 (PDF pp. 453–455 / 7-11–7-13) |
| RET | Decoded cycle 8; E phase (cycle 10) pops TOS → PC. Dummy flush cycles 10–12; the return-target ADD is fetched cycle 11, decoded cycle 12, read cycle 13, executed cycle 14; SACL executes cycle 16 | Ex. 7–5, Table 7–5 (PDF pp. 453–456 / 7-11–7-14) |
| CALL+RET pair | CALL flush ≈ cycles 5–6, RET flush ≈ cycles 10–12; 16 cycles from first ADD fetch to SACL execute in the example | Table 7–5 (PDF p. 453 / 7-11) |

**Delayed branches/calls/returns:** Ch. 7 does **not** discuss delayed-branch instructions (BD/BZD etc.) or any delayed-transfer behaviour. The only branch timing given is the 4-cycle flush above. Do not assume delayed-branch semantics from this chapter.

### 7.2.3 ARAU / memory-mapped register conflicts — §7.2.3, Ex. 7–6/7–7/7–8, Tables 7–6/7–7/7–8 (PDF pp. 456–462 / 7-14–7-20)

**Headline rules (§7.2.3, PDF p. 456 / 7-14):**

| Rule | Detail |
|---|---|
| ARAU updates of ARs occur in **D** phase | Address is generated before the R phase |
| Memory-mapped accesses to ARs (e.g. SAMM, LMMR, SACL, SPLK) occur in **E** phase | Therefore the use of ARs for the **next two instructions** after a memory-mapped load of the AR is **prohibited** — the next two instructions after a memory-mapped load of an AR must not use that AR |
| INDX and ARCR modifications also occur in **E** phase | Any AR update using INDX or ARCR must take place **at least two cycles** after a load of these registers |

**Worked evidence (Ex. 7–6, Table 7–6; `LAR AR2,#67h; LACC #64h; SAMM AR2; LACC *–; ADD *–`; mem 65h=30h, 66h=40h, 67h=50h):**

| Cycle | What happens | Conflict consequence |
|---|---|---|
| 4 | E: LAR loads AR2 = 67h | — |
| 5 | E: LACC loads ACC = 64h | — |
| 6 | D decodes `LACC *–`, updates AR2 (67h→66h); E = dummy | — |
| 7 | D decodes ADD, updates AR2 (66h→65h); R reads 67h (pre-cycle-6-update pointer); **E: SAMM stores ACC (64h) to AR2 — conflicts with D phase** | E-phase write of AR2 overwrites the D-phase ARAU value; AR2 ends at 64h, not 65h |
| 8 | R reads 66h (pre-cycle-7-update pointer); E: LACC loads ACC = 50h (value read cycle 7) | — |
| 9 | E: ADD reads 66h value 40h + ACC 50h = 90h | Final ACC = 90h, AR2 = 64h — the "wrong" result the manual warns about |

**Fixes demonstrated (Ex. 7–7, Table 7–7; Ex. 7–8, Table 7–8):**

| Variant | Change | Result |
|---|---|---|
| Ex. 7–7: one NOP inserted between `LACC *–` and `ADD *–` | NOP occupies the slot where the conflicting SAMM E-phase would collide with ADD's D-phase | Still not fully clean: cycle 7 E still stores ACC→AR2 (64h) while D is a flush dummy; LACC reads 67h (50h) cycle 8, ADD reads 64h (20h) cycle 9 → ACC = 70h. The NOP shifts the collision but the SAMM still overwrites AR2 one cycle later than the ARAU update |
| Ex. 7–8: two NOPs inserted after SAMM (`SAMM AR2; NOP; NOP; LACC *–; ADD *–`) | Two full cycles separate the SAMM E-phase (cycle 7: AR2 = 64h) from the first AR use in D (cycle 8: `LACC *–` decodes, AR2 64h→63h) | Clean: LACC reads 64h (20h) cycle 9 → ACC = 20h; ADD reads 63h (10h) cycle 10 → ACC = 30h |

### 7.2.4 External memory (bus) conflict — §7.2.4, Ex. 7–9, Table 7–9 (PDF pp. 463–465 / 7-21–7-23)

| Rule | Detail |
|---|---|
| Cause | The 'C5x has only one set of external address/data buses, so a bus conflict occurs between F, R and E-write phases if both program and data memory are external |
| Remedy | A dummy operation is inserted to eliminate the bus conflict |
| R-vs-F conflict | When R occupies the external bus, F inserts a dummy and PC is **not** updated (Table 7–9 cycles 3–4: two dummy fetches inserted between ADD and SACL because LACC's R and then ADD's R each block SACL's fetch) |
| E-write stall | External memory writes take **3 cycles**; during the execution of SACL, any instruction fetch or operand-read access on the external bus is delayed for 3 cycles (Table 7–9 cycles 8–9: dummy fetches, no PC update; E stores ACC 13h to external 802h in cycle 8) |
| Example data | mem 800h=10h, 801h=3h, 802h=FFh, 803h=6h; final: ACC=13h, [802h]=13h |

## 7.3 Pipeline latency — §7.3, Table 7–10 (PDF pp. 466–467 / 7-24–7-25)

Memory-mapped registers are accessed in the **D** and **operand-fetch (F)** phases. Writes to memory-mapped registers incur latency before subsequent instructions can use the new value. Direct (non-memory-mapped) accesses to the registers — e.g. all 'C2x-compatible instructions such as LAR, LT — are **pipeline-protected (stalled)** and cause no latency (§7.3, PDF p. 466 / 7-24).

**Table 7–10. Latencies Required (PDF p. 466 / printed 7-24) — transcribed in full:**

| Register | Description | Latency (words) | Effect |
|---|---|---|---|
| ARx | Auxiliary registers 0–7 | 2 | Next word uses previous value; second word update gets overwritten |
| ARCR | Auxiliary register compare register | 2 | Next 2 words use previous value |
| BMAR | Block move address register | 1 | Next 1 word uses previous value |
| CBCR | Circular buffer control register | 2 | Next 2 words cannot be end of buffer |
| CBER | Circular buffer end registers 1 and 2 | 2 | Next 2 words cannot be end of buffer |
| CBSR | Circular buffer start registers 1 and 2 | 2 | Next 2 words use previous value |
| CWSR | Wait-state control register | 1 | Next 1 word uses previous modes |
| GREG | Global memory allocation register | 1 | Next 1 word uses previous map |
| INDX | Index register | 2 | Next 2 words use previous value |
| IOWSR | I/O port wait-state register | 1 | Next 1 word uses previous count |
| PDWSR | Program/data wait-state register | 1 | Next 1 word uses previous count |
| PMST | Processor mode status register | 2 | Next 2 words use previous map |
| ST1 (CNF bit) | Configuration control (CNF) bit in ST1 | 2 | Next 2 words use previous map |
| TREG1 | Dynamic shift count | 1 | Next 1 word uses old shift count |
| TREG2 | Dynamic bit address | 1 | Next 1 word uses old bit address |

**Memory reconfiguration rule (§7.3, PDF p. 467 / 7-25):** the core CPU supports reconfiguration of memory segments (internal/external) during the E phase. Before an instruction uses the new configuration, **at least two instruction words** must follow the instruction that reconfigures memory. Example given:

```
CLRC   CNF        ; Map RAM B0 to data space.
LACC   #01234h    ; ACC = 00001234.  (2-word instruction — fills the 2-word requirement)
ADD    *          ; ACC = 00001235.
```

Assumes current AR = 0200h and RAM B0 (0) = 1. The long-immediate LACC is a 2-word instruction and therefore meets the requirement. This also applies to memory configurations controlled by the PMST.

**Interrupt / CNF hazard (§7.3 note, PDF p. 467 / 7-25):** if main code runs in B0 (CNF = 1) and an ISR not in B0 changes CNF to 0, a RETE will **not** restore CNF in time to fetch the next instruction from the B0 block. Therefore, in the ISR, the CNF bit should be set **at least 2 words before the RETE**.

**NORM interaction (§7.3, PDF p. 466 / 7-24):** the current AR is affected by the NORM instruction during its E phase. Similar pipeline management as above applies. The assembler's `-p` option detects an AR update or store (SAR) directly after a NORM instruction and inserts NOP instructions automatically to maintain source-code compatibility with the 'C2x.

## Conflict inventory — every conflict type named in Ch. 7

| # | Conflict | Where named | Rule / remedy |
|---|---|---|---|
| 1 | Pipeline conflict (general) — >1 phase needs the same resource (memory, CPU registers) | §7.1 (PDF p. 444 / 7-2) | No priority between phases; avoid conflicts by code arrangement |
| 2 | R-phase read vs D-phase ARAU update of the same AR | §7.2.1, Ex. 7–1 (PDF pp. 445–446 / 7-3–7-4) | R uses the pre-update pointer value (defined behaviour, not an error — but must be accounted for) |
| 3 | 2-word instruction second word in F → dummy D | §7.2.1, Ex. 7–2 (PDF pp. 447–448 / 7-5–7-6) | D is a dummy; R is a dummy (operand fetch on fetch phase) |
| 4 | Branch/call/return — PC depends on E-phase result | §7.2.2 (PDF p. 448 / 7-6) | 4-cycle pipeline flush; BCND false = no flush, treated as 2-word instruction |
| 5 | Memory-mapped AR load (E phase) vs AR use in the next 2 instructions (D phase) | §7.2.3 (PDF p. 456 / 7-14) | Prohibited: next 2 instructions must not use that AR; insert NOPs (2 NOPs shown clean in Ex. 7–8) |
| 6 | E-phase SAMM store to AR2 vs D-phase ARAU update of AR2 (same cycle) | §7.2.3, Ex. 7–6 cycle 7 (PDF p. 458 / 7-16) | E write wins/overwrites the D update (AR2 = 64h, not 65h) |
| 7 | INDX / ARCR load (E phase) vs AR update using INDX/ARCR | §7.2.3 (PDF p. 456 / 7-14) | AR update using INDX/ARCR must be ≥ 2 cycles after the load |
| 8 | External bus conflict — F vs R vs E-write when program and data are both external | §7.2.4 (PDF p. 463 / 7-21) | Dummy fetch inserted; PC not updated during dummy; external write stalls bus 3 cycles |
| 9 | Memory-mapped register write latency (D/F-phase access vs E-phase write) | §7.3, Table 7–10 (PDF p. 466 / 7-24) | 1- or 2-word latency per register (see table above) |
| 10 | Memory reconfiguration (PMST/CNF) in E vs following instruction using the new map | §7.3 (PDF p. 467 / 7-25) | ≥ 2 instruction words must follow the reconfiguring instruction |
| 11 | CNF changed by ISR + RETE — CNF not restored in time for B0 fetch | §7.3 note (PDF p. 467 / 7-25) | Set CNF ≥ 2 words before RETE in the ISR |
| 12 | NORM (E phase) affects current AR vs following AR update/store (SAR) | §7.3 (PDF p. 466 / 7-24) | Assembler `-p` inserts NOPs automatically ('C2x compatibility) |

## What Ch. 7 does NOT cover (gaps — do not infer from elsewhere)

- **RPT / repeat instructions:** the string "RPT" does not occur in Ch. 7. No pipeline behaviour for RPT/RPTZ/RPTB is given here.
- **Interrupts in the pipeline:** no interrupt-entry/exit pipeline timing is given, except the CNF/RETE note in §7.3 (PDF p. 467 / 7-25). Interrupt latency is Ch. 4, not Ch. 7.
- **Delayed branches/calls/returns:** no delayed-transfer instruction is discussed; only the 4-cycle flush of §7.2.2.
- **HOLD / DMA / wait states in the pipeline:** not discussed in Ch. 7 (HOLD appears only in Ch. 8).
- **Protected vs unprotected:** the chapter's only "protected" statement is §7.3: direct (non-memory-mapped) register accesses are pipeline-protected (stalled); memory-mapped accesses are not. There is no general "protected pipeline" mode.

## Figures / tables in Ch. 7 (all accounted for)

Fig. 7–1 (PDF p. 444 / 7-2); Tables 7–1 to 7–10: 7–1 (PDF p. 445 / 7-3), 7–2 (PDF p. 447 / 7-5), 7–3 (PDF p. 449 / 7-7), 7–4 (PDF p. 451 / 7-9), 7–5 (PDF p. 453 / 7-11), 7–6 (PDF p. 457 / 7-15), 7–7 (PDF p. 459 / 7-17), 7–8 (PDF p. 461 / 7-19), 7–9 (PDF p. 463 / 7-21), 7–10 (PDF p. 466 / 7-24). Examples 7–1 to 7–9 as cited above.

## Contradictions / unverified items — Ch. 7

- None found. No internal contradiction detected in Ch. 7; no garbled extraction. One scope note: §7.2.2 cites "Table 6–8 on page 6-17" for the branch/call/return instruction list — that table is outside this chapter and was not verified here.
