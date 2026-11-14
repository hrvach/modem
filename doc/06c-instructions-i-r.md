# TMS320C5x User's Guide (SPRU056D, June 1998) — Chapter 6, §6.3 Per-Instruction Descriptions: LACL – RET

Source (only authority): `~/workspace/user/files/spru056d.pdf` (SPRU056D, June 1998).
Range: entries whose Syntax block starts on PDF pp. 267–354 (printed pp. 6-115 – 6-202).
Entries starting before PDF p. 267 (e.g. LACC) or at PDF p. 355+ (e.g. RETC) are NOT in this file.
Page citations give both the PDF index page and the printed page (printed = PDF − 152 in this range).
Titles: §6.3 itself carries no title headings — entries open directly with the Syntax block.
The title shown for each instruction is the description given for that mnemonic in the
§6.2 Instruction Set Summary tables (Table 6–4 etc., PDF pp. ~155–175).

Conventions used throughout:
- `dma` = 7-bit direct data-memory address (0–127, within the page selected by DP), unless noted.
- `{ind}` = indirect addressing; `ind: {* *+ *– *0+ *0– *BR0+ *BR0–}` unless noted otherwise.
- `p` = number of wait states for external program/data access; `d` = data wait states;
  `iosrc` / `iodsrc` = I/O wait-state terms as printed in the manual (see each table's footnotes).
- `n` = RPT repeat count + 1 (number of executions).
- Cycle tables are transcribed exactly as printed, including the "1, 2†" / "n, n+1†" SARAM
  entries (first value = code and operand in different SARAM blocks, second = same block).
- Examples from the manual are NOT reproduced (task scope: normative rules only).
- `[UNVERIFIED — extraction garbled, §6.3 <mnemonic>, PDF p.Y]` marks any field that could
  not be read legibly; nothing is guessed there. `INFERENCE:` labels any inference, kept out
  of the tables.

---

## LACL — Load data memory value to ACCL; zero ACCH

**Source:** §6.3, PDF p. 269 (printed p. 6-117) – p. 271 (printed p. 6-119).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `LACL dma` |
| Indirect | `LACL {ind} [,ARn]` |
| Short immediate | `LACL #k` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; 0 ≤ k ≤ 255; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing:

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 1 | 1 | 0 | 1 | 0 | 0 | 1 | 0 | dma (bits 6–0) | | | | | | |

Indirect addressing:

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 1 | 1 | 0 | 1 | 0 | 0 | 1 | 1 | See Section 5.2 (bits 6–0) | | | | | | |

Short immediate addressing:

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 1 | 1 | 1 | 0 | 0 | 1 | 8-Bit Constant (bits 7–0) | | | | | | | |

**Words:** 1.

**Cycles**

Cycles for a Single Instruction (direct or indirect addressing):

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution (direct or indirect addressing):

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

Cycles for a Single Instruction (short immediate addressing):

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 1 | 1 | 1 | 1+p |

No RPT table is given for short immediate addressing: the manual states the LACL
instruction is not repeatable for the short immediate addressing mode.

**Status Bits:** Not affected by: SXM. (No "Affected by" / "Affects" list is given.)

**Execution**

- `(PC) + 1 → PC`
- Direct or indirect addressing: `0 → ACC(31–16)`; `(dma) → ACC(15–0)`
- Short immediate addressing: `0 → ACC(31–8)`; `k → ACC(7–0)`

**Description (condensed):** The contents of dma, or a zero-extended 8-bit constant, are
loaded into ACCL; ACCH is zero-filled. The data is treated as an unsigned 16-bit number,
not a 2s-complement number. The operand is not sign-extended, regardless of SXM.
LACL is an accumulator memory reference instruction (see Table 6–4).

---

## LACT — Load data memory value, with left shift specified by TREG1, to ACC

**Source:** §6.3, PDF p. 272 (printed p. 6-120) – p. 273 (printed p. 6-121).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `LACT dma` |
| Indirect | `LACT {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing:

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 1 | 1 | 0 | 1 | 0 | 1 | 1 | 0 | dma (bits 6–0) | | | | | | |

Indirect addressing:

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 1 | 1 | 0 | 1 | 0 | 1 | 1 | 1 | See Section 5.2 (bits 6–0) | | | | | | |

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

**Status Bits:** Affected by: SXM. (No "Not affected by" / "Affects" list is given.)

**Execution**

- `(PC) + 1 → PC`
- `(dma) × 2^TREG1(3–0) → ACC`
- If SXM = 0: (dma) is not sign-extended. If SXM = 1: (dma) is sign-extended.

**Description (condensed):** The contents of dma are shifted left 0–15 bits, as defined by
the 4 LSBs of TREG1, and loaded into ACC; TREG1 thus provides a dynamic shift mechanism.
During shifting, if SXM is cleared the high-order bits are zero-filled; if SXM is set they are
sign-extended. LACT can denormalize a floating-point number if the actual exponent is in
the 4 LSBs of TREG1 and the mantissa is referenced by dma — only when the exponent
magnitude is 4 bits or less. For 'C2x software compatibility, clearing TRM makes any 'C2x
instruction that loads TREG0 write to all three TREGs, so a subsequent LACT shifts by the
TREG1 value (same as TREG0), maintaining 'C5x object-code compatibility with the 'C2x.
LACT is an accumulator memory reference instruction (see Table 6–4).

---

## LAMM — Load contents of memory-mapped register to ACCL; zero ACCH

**Source:** §6.3, PDF p. 274 (printed p. 6-122) – p. 275 (printed p. 6-123).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `LAMM dma` |
| Indirect | `LAMM {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing:

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | Data Memory Address (bits 6–0) | | | | | | |

Indirect addressing:

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 1 | See Section 5.2 (bits 6–0) | | | | | | |

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| MMR† | 1 | 1 | 1 | 1+p |
| MMPORT | 1+iosrc | 1+iosrc | 1+iodsrc | 1+2+p+iodsrc |

† Add one more cycle for peripheral memory-mapped access.

Cycles for a Repeat (RPT) Execution:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| MMR‡ | n | n | n | n+p |
| MMPORT | n+miosrc | n+miosrc | n+miosrc | n+p+miosrc |

‡ Add n more cycles for peripheral memory-mapped access.

**Status Bits:** Not affected by: SXM. (No "Affected by" / "Affects" list is given.)

**Execution**

- `(PC) + 1 → PC`
- `(dma) → ACC(15–0)`; `0 → ACC(31–16)`

**Description (condensed):** The contents of the addressed memory-mapped register are
loaded into ACCL; ACCH is zero-filled. The 9 MSBs of the data memory address are cleared,
regardless of the current DP bits or the upper 9 bits of the current AR. LAMM therefore loads
any memory location on data memory page 0 into the ACC without modifying the DP bits.
LAMM is an accumulator memory reference instruction (see Table 6–4).

---

## LAR — Load data memory value to ARx

**Source:** §6.3, PDF p. 276 (printed p. 6-124) – p. 278 (printed p. 6-126).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `LAR ARx, dma` |
| Indirect | `LAR ARx, {ind} [,ARn]` |
| Short immediate | `LAR ARx, #k` |
| Long immediate | `LAR ARx, #lk` |

**Operands:** 0 ≤ x ≤ 7; 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; 0 ≤ k ≤ 255; 0 ≤ lk ≤ 65535;
ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing — bits 15–11: `00000`; bits 10–8: ARX†; bit 7: `0`; bits 6–0: dma.
Indirect addressing — bits 15–11: `00000`; bits 10–8: ARX†; bit 7: `1`; bits 6–0: See Section 5.2.
Short immediate addressing — bits 15–11: `10110`; bits 10–8: ARX†; bits 7–0: 8-Bit Constant.
Long immediate addressing, word 1 — bits 15–3: `1011111100001`; bits 2–0: ARX†; word 2: 16-Bit Constant.

† ARX: see Table 6–1 on page 6-2.

**Words:** 1 (direct, indirect, or short immediate addressing); 2 (long immediate addressing).

**Cycles**

For the short and long immediate addressing modes, the LAR instruction is not repeatable.

Cycles for a Single Instruction (direct or indirect addressing):

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| Source: DARAM | 2 | 2 | 2 | 2+pcode |
| Source: SARAM | 2 | 2 | 2, 3† | 2+pcode |
| Source: External | 2+dsrc | 2+dsrc | 2+dsrc | 3+dsrc+pcode |

† If the source operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution (direct or indirect addressing):

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| Source: DARAM | 2n | 2n | 2n | 2n+pcode |
| Source: SARAM | 2n | 2n | 2n, 2n+1† | 2n+pcode |
| Source: External | 2n+ndsrc | 2n+ndsrc | 2n+ndsrc | 2n+1+ndsrc+pcode |

† If the source operand and the code are in the same SARAM block.

Cycles for a Single Instruction (short immediate addressing):

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 2 | 2 | 2 | 2+pcode |

(The footnote "† If the source operand and the code are in the same SARAM block" is
printed beneath this table in the manual, although no † marker appears in the table body.)

Cycles for a Single Instruction (long immediate addressing):

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 2 | 2 | 2 | 2+2p |

No RPT table is given for the short or long immediate addressing modes.

**Status Bits:** Affected by: NDX. Not affected by: SXM.

**Execution**

- Direct or indirect addressing: `(PC) + 1 → PC`; `(dma) → AR`
- Short immediate addressing: `(PC) + 1 → PC`; `k → AR`
- Long immediate addressing: `(PC) + 2 → PC`; `lk → AR`

**Description (condensed):** The contents of dma, an 8-bit constant, or a 16-bit constant are
loaded into the auxiliary register (AR). The constant is treated as an unsigned integer,
regardless of SXM. Clearing NDX makes any 'C2x instruction that loads AR0 also load ARCR
and INDX, maintaining 'C5x object-code compatibility with the 'C2x. LAR and SAR can load
and store the ARs during subroutine calls and interrupts; an AR not used for indirect
addressing can serve as an additional storage register, e.g. swapping values between data
memory locations without affecting ACC. Constraint (Note in manual): in indirect addressing,
LAR ignores any AR modification if the AR specified by the instruction is the same as that
pointed to by ARP — e.g. `LAR AR4,*–` with ARP = 4 does not decrement AR4.
LAR is an auxiliary registers and data memory page pointer instruction (see Table 6–5).

---

## LDP — Load data memory value to DP bits

**Source:** §6.3, PDF p. 279 (printed p. 6-127) – p. 281 (printed p. 6-129).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `LDP dma` |
| Indirect | `LDP {ind} [,ARn]` |
| Short immediate | `LDP #k` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; 0 ≤ k ≤ 511; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing:

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 1 | 1 | 0 | 1 | 0 | dma (bits 6–0) | | | | | | |

Indirect addressing:

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 1 | 1 | 0 | 1 | 1 | See Section 5.2 (bits 6–0) | | | | | | |

Short immediate addressing:

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 1 | 1 | 1 | 1 | 0 | 9-Bit Constant (bits 8–0) | | | | | | | | |

**Words:** 1.

**Cycles**

For the short immediate addressing mode, the LDP instruction is not repeatable.

Cycles for a Single Instruction (direct or indirect addressing):

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| Source: DARAM | 2 | 2 | 2 | 2+pcode |
| Source: SARAM | 2 | 2 | 2, 3† | 2+pcode |
| Source: External | 2+dsrc | 2+dsrc | 2+dsrc | 3+dsrc+pcode |

† If the source operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution (direct or indirect addressing):

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| Source: DARAM | 2n | 2n | 2n | 2n+pcode |
| Source: SARAM | 2n | 2n | 2n, 2n+1† | 2n+pcode |
| Source: External | 2n+ndsrc | 2n+ndsrc | 2n+ndsrc | 2n+1+ndsrc+pcode |

† If the source operand and the code are in the same SARAM block.

Cycles for a Single Instruction (short immediate addressing):

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 2 | 2 | 2 | 2+pcode |

(The footnote "† If the source operand and the code are in the same SARAM block" is
printed beneath this table in the manual, although no † marker appears in the table body.)

**Status Bits:** Affects: DP. (No "Affected by" / "Not affected by" list is given.)

**Execution**

- `(PC) + 1 → PC`
- Direct or indirect addressing: Nine LSBs of (dma) → DP bits
- Short immediate addressing: `k → DP bits`

**Description (condensed):** The 9 LSBs of the contents of dma, or a 9-bit constant, are
loaded into the DP bits. The DP bits and the 7-bit dma are concatenated to form the 16-bit
dma. The DP bits can also be loaded by the LST instruction. LDP is an auxiliary registers
and data memory page pointer instruction (see Table 6–5).

---

## LMMR — Load memory-mapped register

**Source:** §6.3, PDF p. 282 (printed p. 6-130) – p. 284 (printed p. 6-132).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `LMMR dma, #addr` |
| Indirect | `LMMR {ind}, #addr [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; 0 ≤ addr ≤ 65535; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing, word 1 — bits 15–8: `10001001`; bit 7: `0`; bits 6–0: dma. Word 2: 16-Bit Constant.
Indirect addressing, word 1 — bits 15–8: `10001001`; bit 7: `1`; bits 6–0: See Section 5.2. Word 2: 16-Bit Constant.

**Words:** 2.

**Cycles**

Cycles for a Single Instruction:

| Operand (Source / Destination) | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| Source: DARAM / Destination: MMR‡ | 2 | 2 | 2 | 2+2pcode |
| Source: SARAM / Destination: MMR‡ | 2 | 2 | 2, 3† | 2+2pcode |
| Source: External / Destination: MMR‡ | 2+psrc | 2+psrc | 2+psrc | 3+psrc+2pcode |
| Source: DARAM / Destination: MMPORT | 3+iodst | 3+iodst | 3+iodst | 5+2pcode+iodst |
| Source: SARAM / Destination: MMPORT | 3+iodst | 3+iodst | 3+iodst, 4† | 5+2pcode+iodst |
| Source: External / Destination: MMPORT | 3+psrc+iodst | 3+psrc+iodst | 3+psrc+iodst | 6+psrc+2pcode+iodst |

† If the source operand and the code are in the same SARAM block.
‡ Add one more cycle for peripheral memory-mapped register access.

Cycles for a Repeat (RPT) Execution:

| Operand (Source / Destination) | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| Source: DARAM / Destination: MMR§ | 2n | 2n | 2n | 2n+2pcode |
| Source: SARAM / Destination: MMR§ | 2n | 2n | 2n, 2n+1† | 2n+2pcode |
| Source: External / Destination: MMR§ | 2n+ndsrc | 2n+ndsrc | 2n+ndsrc | 2n+1+ndsrc+2pcode |
| Source: DARAM / Destination: MMPORT | 3n+niodst | 3n+niodst | 3n+niodst | 3n+3+niodst+2pcode |
| Source: SARAM / Destination: MMPORT | 3n+niodst | 3n+niodst | 3n+niodst, 3n+1+niodst† | 3n+3+niodst+2pcode |
| Source: External / Destination: MMPORT | 4n–1+ndsrc+niodst | 4n–1+ndsrc+niodst | 4n–1+ndsrc+niodst | 4n+2+ndsrc+niodst+2pcode |

† If the source operand and the code are in the same SARAM block.
§ Add n more cycles for peripheral memory-mapped register access.

**Status Bits:** None affected.

**Execution**

- `PFC → MCS`
- `(PC) + 2 → PC`
- `lk → PFC` (as printed; lk is the 16-bit constant #addr, the second instruction word)
- While (repeat counter ≠ 0): `(src, addressed by PFC) → (dst, specified by lower 7 bits of dma)`; `(PFC) + 1 → PFC`; `(repeat counter) – 1 → repeat counter`
- `MCS → PFC`

**Description (condensed):** The memory-mapped register pointed at by the lower 7 bits
of dma is loaded with the contents of the data memory location addressed by the 16-bit
source address #addr. The 9 MSBs of dma are cleared, regardless of the current DP bits or
the upper 9 bits of the current AR. LMMR allows any memory location on data memory
page 0 to be loaded from anywhere in data memory without modifying the DP bits. With
RPT, the source address #addr is incremented after every memory-mapped load operation.
LMMR is an I/O and data memory operation instruction (see Table 6–9).

---

## LPH — Load data memory value to PREG high byte

**Source:** §6.3, PDF p. 285 (printed p. 6-133) – p. 286 (printed p. 6-134).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `LPH dma` |
| Indirect | `LPH {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing:

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 1 | 1 | 1 | 0 | 1 | 0 | 1 | 0 | dma (bits 6–0) | | | | | | |

Indirect addressing:

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 1 | 1 | 1 | 0 | 1 | 0 | 1 | 1 | See Section 5.2 (bits 6–0) | | | | | | |

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

**Status Bits:** None affected.

**Execution**

- `(PC) + 1 → PC`
- `(dma) → PREG (31–16)`

**Description (condensed):** The contents of dma are loaded into the PREG high byte; the
PREG low byte is unaffected. LPH can restore the PREG high byte after interrupts and
subroutine calls, if automatic context save is not used. LPH is a TREG0, PREG, and multiply
instruction (see Table 6–7).

---

## LST — Load data memory value to STm

**Source:** §6.3, PDF p. 287 (printed p. 6-135) – p. 289 (printed p. 6-137).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `LST #m, dma` |
| Indirect | `LST #m, {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; m = 0 or 1; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing for LST #0:

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 1 | 1 | 1 | 0 | 0 | dma (bits 6–0) | | | | | | |

Indirect addressing for LST #0:

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 1 | 1 | 1 | 0 | 1 | See Section 5.2 (bits 6–0) | | | | | | |

Direct addressing for LST #1:

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 1 | 1 | 1 | 1 | 0 | dma (bits 6–0) | | | | | | |

Indirect addressing for LST #1:

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0 | 1 | 1 | 1 | 1 | 1 | See Section 5.2 (bits 6–0) | | | | | | |

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| Source: DARAM | 2 | 2 | 2 | 2+pcode |
| Source: SARAM | 2 | 2 | 2, 3† | 2+pcode |
| Source: External | 2+dsrc | 2+dsrc | 2+dsrc | 3+dsrc+pcode |

† If the source operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| Source: DARAM | 2n | 2n | 2n | 2n+pcode |
| Source: SARAM | 2n | 2n | 2n, 2n+1† | 2n+pcode |
| Source: External | 2n+ndsrc | 2n+ndsrc | 2n+ndsrc | 2n+1+ndsrc+pcode |

† If the source operand and the code are in the same SARAM block.

**Status Bits:** Affects: ARB, ARP, C, CNF, DP, HM, OV, OVM, PM, SXM, TC, and XF.
Does not affect: INTM.

**Execution**

- `(PC) + 1 → PC`
- `(dma) → STm`
- `dma (13–15) → ARP` (as printed; bits 13–15 of the addressed data memory word load ARP, regardless of n)

**Description (condensed):** The contents of dma are loaded into status register STm.
The INTM bit is unaffected by an LST #0 instruction. In addition, LST #0 does not affect
ARB, even though a new ARP is loaded. If a next ARP value is specified via indirect
addressing, the specified value is ignored; instead ARP is loaded with the value contained
within the addressed data memory word. Note: when ST1 is loaded (LST #1), the value
loaded into ARB is also loaded into ARP. LST can restore the status registers after
subroutine calls and interrupts. LST is a control instruction (see Table 6–10).
Note on the status table vs. the description: the "Affects" list includes ARB, but the
description restricts that — LST #0 does not affect ARB (and does not affect INTM);
the ARB effect applies to LST #1 (ARB value also loaded into ARP). Both statements are
as printed in §6.3, PDF p. 287.

---

## LT — Load data memory value to TREG0

**Source:** §6.3, PDF p. 290 (printed p. 6-138) – p. 291 (printed p. 6-139).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `LT dma` |
| Indirect | `LT {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing — bits 15–8: `01110011`; bit 7: `0`; bits 6–0: dma.
Indirect addressing — bits 15–8: `01110011`; bit 7: `1`; bits 6–0: See Section 5.2.

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

**Status Bits:** Affected by: TRM. (No "Not affected by" / "Affects" list is given.)

**Execution**

- `(PC) + 1 → PC`
- `(dma) → TREG0`
- If TRM = 0: `(dma) → TREG1`; `(dma) → TREG2`

**Description (condensed):** The contents of dma are loaded into TREG0, in preparation for
multiplication. Clearing TRM makes any 'C2x instruction that loads TREG0 write to all three
TREGs, maintaining 'C5x object-code compatibility with the 'C2x. The TREGs are
memory-mapped registers readable/writable by any instruction that accesses data memory.
TREG1 has only 5 bits, and TREG2 has only 4 bits. LT is a TREG0, PREG, and multiply
instruction (see Table 6–7).

---

## LTA — Load data memory value to TREG0; add PREG, with shift specified by PM bits, to ACC

**Source:** §6.3, PDF p. 292 (printed p. 6-140) – p. 293 (printed p. 6-141).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `LTA dma` |
| Indirect | `LTA {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing — bits 15–8: `01110000`; bit 7: `0`; bits 6–0: dma.
Indirect addressing — bits 15–8: `01110000`; bit 7: `1`; bits 6–0: See Section 5.2.

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

**Status Bits:** Affected by: OVM, PM, and TRM. Affects: C and OV.

**Execution**

- `(PC) + 1 → PC`
- `(dma) → TREG0`
- `(ACC) + (shifted PREG) → ACC`
- If TRM = 0: `(dma) → TREG1`; `(dma) → TREG2`

**Description (condensed):** The contents of dma are loaded into TREG0. The contents of
PREG are shifted, as defined by the PM bits, and added to ACC; the result is stored in ACC.
The C bit is set if the addition generates a carry; otherwise C is cleared. TRM = 0 makes a
TREG0 load write to all three TREGs ('C2x compatibility; TREG1 has only 5 bits, TREG2
only 4 bits). LTA is a TREG0, PREG, and multiply instruction (see Table 6–7).

---

## LTD — Load data memory value to TREG0; add PREG, with shift specified by PM bits, to ACC; and move data

**Source:** §6.3, PDF p. 294 (printed p. 6-142) – p. 296 (printed p. 6-144).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `LTD dma` |
| Indirect | `LTD {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing — bits 15–8: `01110010`; bit 7: `0`; bits 6–0: dma.
Indirect addressing — bits 15–8: `01110010`; bit 7: `1`; bits 6–0: See Section 5.2.

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 3† | 1+p |
| External | 2+2d | 2+2d | 2+2d | 5+2d+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | 2n–2 | 2n–2 | 2n–2, 2n+1† | 2n–2+p |
| External | 4n–2+2nd | 4n–2+2nd | 4n–2+2nd | 4n+1+2nd+p |

† If the operand and the code are in the same SARAM block.

**Status Bits:** Affected by: OVM, PM, and TRM. Affects: C and OV.

**Execution**

- `(PC) + 1 → PC`
- `(dma) → TREG0`
- `(dma) → dma + 1`
- `(ACC) + (shifted PREG) → ACC`
- If TRM = 0: `(dma) → TREG1`; `(dma) → TREG2`

**Description (condensed):** The contents of dma are loaded into TREG0 and also copied
to the next higher dma (data move). PREG is shifted, as defined by the PM bits, and added
to ACC; the result is stored in ACC. C is set if the addition generates a carry; otherwise C
is cleared. See the DMOV instruction (printed p. 6-104) for the data-move feature. LTD
functions as LTA with the addition of data move for on-chip RAM blocks; with external data
memory its function is identical to LTA. TRM = 0 makes a TREG0 load write to all three
TREGs ('C2x compatibility; TREG1 has only 5 bits, TREG2 only 4 bits). LTD is a TREG0,
PREG, and multiply instruction (see Table 6–7).

---

## LTP — Load data memory value to TREG0; store PREG, with shift specified by PM bits, in ACC

**Source:** §6.3, PDF p. 297 (printed p. 6-145) – p. 298 (printed p. 6-146).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `LTP dma` |
| Indirect | `LTP {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing — bits 15–8: `01110001`; bit 7: `0`; bits 6–0: dma.
Indirect addressing — bits 15–8: `01110001`; bit 7: `1`; bits 6–0: See Section 5.2.

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

**Status Bits:** Affected by: PM and TRM. (No "Not affected by" / "Affects" list is given.)

**Execution**

- `(PC) + 1 → PC`
- `(dma) → TREG0`
- `(shifted PREG) → ACC`
- If TRM = 0: `(dma) → TREG1`; `(dma) → TREG2`

**Description (condensed):** The contents of dma are loaded into TREG0. The contents of
PREG are shifted, as defined by the PM bits, and stored in ACC. TRM = 0 makes a TREG0
load write to all three TREGs ('C2x compatibility; TREG1 has only 5 bits, TREG2 only 4 bits).
LTP is a TREG0, PREG, and multiply instruction (see Table 6–7).

---

## LTS — Load data memory value to TREG0; subtract PREG, with shift specified by PM bits, from ACC

**Source:** §6.3, PDF p. 299 (printed p. 6-147) – p. 300 (printed p. 6-148).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `LTS dma` |
| Indirect | `LTS {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing — bits 15–8: `01110100`; bit 7: `0`; bits 6–0: dma.
Indirect addressing — bits 15–8: `01110100`; bit 7: `1`; bits 6–0: See Section 5.2.

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

**Status Bits:** Affected by: OVM, PM, and TRM. Affects: C and OV.

**Execution**

- `(PC) + 1 → PC`
- `(dma) → TREG0`
- `(ACC) – (shifted PREG) → ACC`
- If TRM = 0: `(dma) → TREG1`; `(dma) → TREG2`

**Description (condensed):** The contents of dma are loaded into TREG0. The contents of
PREG are shifted, as defined by the PM bits, and subtracted from ACC; the result is stored
in ACC. C is cleared if the subtraction generates a borrow; otherwise C is set. TRM = 0
makes a TREG0 load write to all three TREGs ('C2x compatibility; TREG1 has only 5 bits,
TREG2 only 4 bits). LTS is a TREG0, PREG, and multiply instruction (see Table 6–7).

---

## MAC — Add PREG, with shift specified by PM bits, to ACC; load data memory value to TREG0; multiply data memory value by program memory value and store result in PREG

**Source:** §6.3, PDF p. 301 (printed p. 6-149) – p. 304 (printed p. 6-152).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `MAC pma, dma` |
| Indirect | `MAC pma, {ind} [,ARn]` |

**Operands:** 0 ≤ pma ≤ 65535; 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing, word 1 — bits 15–8: `10100010`; bit 7: `0`; bits 6–0: dma. Word 2: 16-Bit Constant.
Indirect addressing, word 1 — bits 15–8: `10100010`; bit 7: `1`; bits 6–0: See Section 5.2. Word 2: 16-Bit Constant.

**Words:** 2.

**Cycles**

Operand rows are printed as "1: … / 2: …". INFERENCE (kept out of the tables): "1:" is the
pma (program-memory) operand location and "2:" is the dma (data-memory) operand
location; the columns are the code location. `p_op1` = wait states for operand 1,
`d_op2` = wait states for operand 2, `p_code` = wait states for the code fetch.

Cycles for a Single Instruction:

| Operand (1: / 2:) | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| 1: DARAM/ROM / 2: DARAM | 3 | 3 | 3 | 3+2p_code |
| 1: SARAM / 2: DARAM | 3 | 3 | 3 | 3+2p_code |
| 1: External / 2: DARAM | 3+p_op1 | 3+p_op1 | 3+p_op1 | 3+p_op1+2p_code |
| 1: DARAM/ROM / 2: SARAM | 3 | 3 | 3 | 3+2p_code |
| 1: SARAM / 2: SARAM | 3, 4† | 3, 4† | 3, 4† | 3+2p_code, 4+2p_code† |
| 1: External / 2: SARAM | 3+p_op1 | 3+p_op1 | 3+p_op1 | 3+p_op1+2p_code |
| 1: DARAM/ROM / 2: External | 3+d_op2 | 3+d_op2 | 3+d_op2 | 3+d_op2+2p_code |
| 1: SARAM / 2: External | 3+d_op2 | 3+d_op2 | 3+d_op2 | 3+d_op2+2p_code |
| 1: External / 2: External | 4+p_op1+d_op2 | 4+p_op1+d_op2 | 4+p_op1+d_op2 | 4+p_op1+d_op2+2p_code |

† If both operands are in the same SARAM block.

Cycles for a Repeat (RPT) Execution:

| Operand (1: / 2:) | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| 1: DARAM/ROM / 2: DARAM | n+2 | n+2 | n+2 | n+2+2p_code |
| 1: SARAM / 2: DARAM | n+2 | n+2 | n+2 | n+2+2p_code |
| 1: External / 2: DARAM | n+2+np_op1 | n+2+np_op1 | n+2+np_op1 | n+2+np_op1+2p_code |
| 1: DARAM/ROM / 2: SARAM | n+2 | n+2 | n+2 | n+2+2p_code |
| 1: SARAM / 2: SARAM | n+2, 2n+2† | n+2, 2n+2† | n+2, 2n+2† | n+2+2p_code, 2n+2† |
| 1: External / 2: SARAM | n+2+np_op1 | n+2+np_op1 | n+2+np_op1 | n+2+np_op1+2p_code |
| 1: DARAM/ROM / 2: External | n+2+nd_op2 | n+2+nd_op2 | n+2+nd_op2 | n+2+nd_op2+2p_code |
| 1: SARAM / 2: External | n+2+nd_op2 | n+2+nd_op2 | n+2+nd_op2 | n+2+nd_op2+2p_code |
| 1: External / 2: External | 2n+2+np_op1+nd_op2 | 2n+2+np_op1+nd_op2 | 2n+2+np_op1+nd_op2 | 2n+2+np_op1+nd_op2+2p_code |

† If both operands are in the same SARAM block.

**Status Bits:** Affected by: OVM, PM, and TRM. Affects: C and OV.

**Execution**

- `(PC) + 2 → PC`; `(PFC) → MCS`; `(pma) → PFC`
- If (repeat counter) ≠ 0: `(ACC) + (shifted PREG) → ACC`; `(dma) → TREG0`;
  `(dma) × (pma, addressed by PFC) → PREG`; Modify current AR and ARP as specified;
  `(PFC) + 1 → PFC`; `(repeat counter) – 1 → repeat counter`
- Else: `(ACC) + (shifted PREG) → ACC`; `(dma) → TREG0`;
  `(dma) × (pma, addressed by PFC) → PREG`; Modify current AR and ARP as specified
- `(MCS) → PFC`
- If TRM = 0: `(dma) → TREG1`; `(dma) → TREG2`

**Description (condensed):** PREG is shifted, as defined by the PM bits, and added to ACC;
the result is stored in ACC. The contents of dma are loaded into TREG0. The contents of
dma are multiplied by the contents of the program memory address pma; the result is stored
in PREG. C is set if the addition generates a carry; otherwise C is cleared. The data and
program memory locations can be any nonreserved on-chip or off-chip memory locations.
If the program memory is block B0 of on-chip RAM, the CNF bit must be set. In direct
addressing mode, the dma cannot be modified during repetition of the instruction. When
repeated, the pma in the prefetch counter (PFC) is incremented by 1 during operation,
allowing access to a series of operands in memory. With RPT, MAC is useful for long
sum-of-products operations because the instruction becomes a single-cycle instruction once
the RPT pipeline is started. TRM = 0 makes a TREG0 load write to all three TREGs
('C2x compatibility; TREG1 has only 5 bits, TREG2 only 4 bits). MAC is a TREG0, PREG,
and multiply instruction (see Table 6–7).

---

## MACD — Add PREG, with shift specified by PM bits, to ACC; load data memory value to TREG0; multiply data memory value by program memory value and store result in PREG; and move data

**Source:** §6.3, PDF p. 305 (printed p. 6-153) – p. 309 (printed p. 6-157).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `MACD pma, dma` |
| Indirect | `MACD pma, {ind} [,ARn]` |

**Operands:** 0 ≤ pma ≤ 65535; 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing, word 1 — bits 15–8: `10100011`; bit 7: `0`; bits 6–0: dma. Word 2: 16-Bit Constant.
Indirect addressing, word 1 — bits 15–8: `10100011`; bit 7: `1`; bits 6–0: See Section 5.2. Word 2: 16-Bit Constant.

**Words:** 2.

**Cycles**

Operand rows are printed as "1: … / 2: …". INFERENCE (kept out of the tables): "1:" is the
pma (program-memory) operand location and "2:" is the dma (data-memory) operand
location; the columns are the code location. `p_op1` = wait states for operand 1,
`d_op2` = wait states for operand 2, `p_code` = wait states for the code fetch.
Cycle values verified against the rendered pages (PDF pp. 307–308), not only the text
extraction, because the multi-value SARAM cells wrap in the extraction.

Cycles for a Single Instruction:

| Operand (1: / 2:) | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| 1: DARAM/ROM / 2: DARAM | 3 | 3 | 3 | 3+2p_code |
| 1: SARAM / 2: DARAM | 3 | 3 | 3 | 3+2p_code |
| 1: External / 2: DARAM | 3+p_op1 | 3+p_op1 | 3+p_op1 | 3+p_op1+2p_code |
| 1: DARAM/ROM / 2: SARAM | 3 | 3 | 3 | 3+2p_code |
| 1: SARAM / 2: SARAM | 3 | 3 | 3, 4‡, 5§ | 3+2p_code, 4+2p_code‡ |
| 1: External / 2: SARAM | 3+p_op1 | 3+p_op1 | 3+p_op1 | 3+p_op1+2p_code |
| 1: DARAM/ROM / 2: External¶ | 3+d_op2 | 3+d_op2 | 3+d_op2 | 3+d_op2+2p_code |
| 1: SARAM / 2: External¶ | 3+d_op2 | 3+d_op2 | 3+d_op2 | 3+d_op2+2p_code |
| 1: External / 2: External¶ | 4+p_op1+d_op2 | 4+p_op1+d_op2 | 4+p_op1+d_op2 | 4+p_op1+d_op2+2p_code |

‡ If both operands are in the same SARAM block.
§ If both operands and the code are in the same SARAM block.
¶ Data move operation is not performed when operand2 is in external data memory.

Cycles for a Repeat (RPT) Execution:

| Operand (1: / 2:) | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| 1: DARAM/ROM / 2: DARAM | n+2 | n+2 | n+2 | n+2+2p_code |
| 1: SARAM / 2: DARAM | n+2 | n+2 | n+2 | n+2+2p_code |
| 1: External / 2: DARAM | n+2+np_op1 | n+2+np_op1 | n+2+np_op1 | n+2+np_op1+2p_code |
| 1: DARAM/ROM / 2: SARAM | 2n | 2n | 2n, 2n+2† | 2n+2p_code |
| 1: SARAM / 2: SARAM | 2n, 3n‡ | 2n, 3n‡ | 2n, 2n+2†, 3n‡, 3n+2§ | 2n+2p_code, 3n‡ |
| 1: External / 2: SARAM | 2n+np_op1 | 2n+np_op1 | 2n+np_op1, 2n+2+np_op1† | 2n+np_op1+2p_code |
| 1: DARAM/ROM / 2: External¶ | n+2+nd_op2 | n+2+nd_op2 | n+2+nd_op2 | n+2+nd_op2+2p_code |
| 1: SARAM / 2: External¶ | n+2+nd_op2 | n+2+nd_op2 | n+2+nd_op2 | n+2+nd_op2+2p_code |
| 1: External / 2: External¶ | 2n+2+np_op1+nd_op2 | 2n+2+np_op1+nd_op2 | 2n+2+np_op1+nd_op2 | 2n+2+np_op1+nd_op2+2p_code |

† If operand2 and code are in the same SARAM block.
‡ If both operands are in the same SARAM block.
§ If both operands and the code are in the same SARAM block.
¶ Data move operation is not performed when operand2 is in external data memory.

**Status Bits:** Affected by: OVM, PM, and TRM. Affects: C and OV.

**Execution**

- `(PC) + 2 → PC`; `(PFC) → MCS`; `(pma) → PFC`
- If (repeat counter) ≠ 0: `(ACC) + (shifted PREG) → ACC`; `(dma) → TREG0`;
  `(dma) × (pma, addressed by PFC) → PREG`; Modify current AR and ARP as specified;
  `(PFC) + 1 → PFC`; `(dma) → (dma) + 1`; `(repeat counter) – 1 → repeat counter`
- Else: `(ACC) + (shifted PREG) → ACC`; `(dma) → TREG0`;
  `(dma) × (pma, addressed by PFC) → PREG`; `(dma) → (dma) + 1`;
  Modify current AR and ARP as specified
- `(MCS) → PFC`
- If TRM = 0: `(dma) → TREG1`; `(dma) → TREG2`

**Description (condensed):** As MAC, with the addition of data move: PREG is shifted per
PM and added to ACC; dma is loaded into TREG0; dma × pma → PREG; C is set if the
addition generates a carry, otherwise cleared. See DMOV (printed p. 6-104) for the
data-move feature. Data and program memory locations can be any nonreserved on-chip or
off-chip locations; if the program memory is block B0 of on-chip RAM, CNF must be set.
In direct addressing mode, the dma cannot be modified during repetition. If MACD
addresses a memory-mapped register or external memory as a data memory location, the
effect is that of a MAC instruction. When repeated, the pma in PFC is incremented by 1
during operation. With RPT, MACD becomes a single-cycle instruction once the RPT
pipeline is started. The data move function can occur only within on-chip data RAM blocks;
with external data memory, MACD's function is identical to MAC. TRM = 0 makes a TREG0
load write to all three TREGs ('C2x compatibility; TREG1 has only 5 bits, TREG2 only
4 bits). MACD is useful for convolution and transversal filtering. MACD is a TREG0, PREG,
and multiply instruction (see Table 6–7).

---

## MADD — Add PREG, with shift specified by PM bits, to ACC; load data memory value to TREG0; multiply data memory value by value specified in BMAR and store result in PREG; and move data

**Source:** §6.3, PDF p. 310 (printed p. 6-158) – p. 313 (printed p. 6-161).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `MADD dma` |
| Indirect | `MADD {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing — bits 15–8: `10101011`; bit 7: `0`; bits 6–0: dma.
Indirect addressing — bits 15–8: `10101011`; bit 7: `1`; bits 6–0: See Section 5.2.

**Words:** 1.

**Cycles**

Operand rows are printed as "1: … / 2: …". INFERENCE (kept out of the tables): "1:" is the
pma (program-memory, BMAR) operand location and "2:" is the dma operand location;
the columns are the code location. `p_op1` = wait states for operand 1, `d_op2` = wait
states for operand 2, `p_code` = wait states for the code fetch.

Cycles for a Single Instruction:

| Operand (1: / 2:) | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| 1: DARAM/ROM / 2: DARAM | 2 | 2 | 2 | 2+p_code |
| 1: SARAM / 2: DARAM | 2 | 2 | 2 | 2+p_code |
| 1: External / 2: DARAM | 2+p_op1 | 2+p_op1 | 2+p_op1 | 2+p_op1+p_code |
| 1: DARAM/ROM / 2: SARAM | 2 | 2 | 2 | 2+p_code |
| 1: SARAM / 2: SARAM | 2 | 2 | 2, 3‡, 4§ | 2+p_code, 3+p_code‡ |
| 1: External / 2: SARAM | 2+p_op1 | 2+p_op1 | 2+p_op1 | 2+p_op1+p_code |
| 1: DARAM/ROM / 2: External¶ | 2+d_op2 | 2+d_op2 | 2+d_op2 | 2+d_op2+p_code |
| 1: SARAM / 2: External¶ | 2+d_op2 | 2+d_op2 | 2+d_op2 | 2+d_op2+p_code |
| 1: External / 2: External¶ | 3+p_op1+d_op2 | 3+p_op1+d_op2 | 3+p_op1+d_op2 | 3+p_op1+d_op2+p_code |

‡ If both operands are in the same SARAM block.
§ If both operands and code are in the same SARAM block.
¶ Data move operation is not performed when operand2 is in external data memory.

Cycles for a Repeat (RPT) Execution:

| Operand (1: / 2:) | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| 1: DARAM/ROM / 2: DARAM | n+1 | n+1 | n+1 | n+1+p_code |
| 1: SARAM / 2: DARAM | n+1 | n+1 | n+1 | n+1+p_code |
| 1: External / 2: DARAM | n+1+np_op1 | n+1+np_op1 | n+1+np_op1 | n+1+np_op1+p_code |
| 1: DARAM/ROM / 2: SARAM | 2n–1 | 2n–1 | 2n–1, 2n+1† | 2n–1+p_code |
| 1: SARAM / 2: SARAM | 2n–1, 3n–1‡ | 2n–1, 3n–1‡ | 2n–1, 2n+1†, 3n–1‡, 3n+1§ | 2n–1+p_code, 3n–1‡ |
| 1: External / 2: SARAM | 2n–1+np_op1 | 2n–1+np_op1 | 2n–1+np_op1, 2n+1+np_op1† | 2n–1+np_op1+p_code |
| 1: DARAM/ROM / 2: External¶ | n+1+nd_op2 | n+1+nd_op2 | n+1+nd_op2 | n+1+nd_op2+p_code |
| 1: SARAM / 2: External¶ | n+1+nd_op2 | n+1+nd_op2 | n+1+nd_op2 | n+1+nd_op2+p_code |
| 1: External / 2: External¶ | 2n+1+np_op1+nd_op2 | 2n+1+np_op1+nd_op2 | 2n+1+np_op1+nd_op2 | 2n+1+np_op1+nd_op2+p_code |

† If operand2 and code are in the same SARAM block.
‡ If both operands are in the same SARAM block.
§ If both operands and code are in the same SARAM block.
¶ Data move operation is not performed when operand2 is in external data memory.

**Status Bits:** Affected by: OVM and PM. Affects: C and OV. (TRM is NOT listed for MADD,
unlike MAC/MACD — the execution block also has no TRM = 0 step.)

**Execution**

- `(PC) + 2 → PC` (as printed — see contradiction note below)
- `(PFC) → MCS`; `(BMAR) → PFC`
- If (repeat counter) ≠ 0: `(ACC) + (shifted PREG) → ACC`; `(dma) → TREG0`;
  `(dma) × (pma, addressed by PFC) → PREG`; Modify current AR and ARP as specified;
  `(PFC) + 1 → PFC`; `(dma) → (dma) + 1`; `(repeat counter) – 1 → repeat counter`
- Else: `(ACC) + (shifted PREG) → ACC`; `(dma) → TREG0`;
  `(dma) × (pma, addressed by PFC) → PREG`; `(dma) → (dma) + 1`;
  Modify current AR and ARP as specified
- `(MCS) → PFC`

**Description (condensed):** As MADS, with the addition of data move: PREG is shifted per
PM and added to ACC; dma is loaded into TREG0; dma × pma → PREG. The pma is in
BMAR, not a long immediate constant, enabling dynamic addressing of coefficient tables.
C is set if the addition generates a carry, otherwise cleared. See DMOV (printed p. 6-104)
for the data-move feature. Data and program memory locations can be any nonreserved
on-chip or off-chip locations; if the program memory is block B0 of on-chip RAM, CNF must
be set. In direct addressing mode, the dma cannot be modified during repetition. If MADD
addresses a memory-mapped register or external memory as a data memory location, the
effect is that of a MADS instruction. When repeated, the pma in PFC is incremented by 1.
With RPT, MADD becomes a single-cycle instruction once the RPT pipeline is started.
The data move function can occur only within on-chip data RAM blocks; with external data
memory, MADD's function is identical to MADS. MADD is a TREG0, PREG, and multiply
instruction (see Table 6–7).

**Contradiction (recorded, both as printed):** MADD's Execution block says
`(PC) + 2 → PC` (PDF p. 310, verified against the rendered page), but the same entry
states Words = 1 (PDF p. 311) and the otherwise-identical MADS entry says
`(PC) + 1 → PC` (PDF p. 314). The PC increment of +2 is inconsistent with a 1-word
instruction; the manual gives no reconciliation.

---

## MADS — Add PREG, with shift specified by PM bits, to ACC; load data memory value to TREG0; multiply data memory value by value specified in BMAR and store result in PREG

**Source:** §6.3, PDF p. 314 (printed p. 6-162) – p. 317 (printed p. 6-165).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `MADS dma` |
| Indirect | `MADS {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing — bits 15–8: `10101010`; bit 7: `0`; bits 6–0: dma.
Indirect addressing — bits 15–8: `10101010`; bit 7: `1`; bits 6–0: See Section 5.2.

**Words:** 1.

**Cycles**

Operand rows are printed as "1: … / 2: …". INFERENCE (kept out of the tables): "1:" is the
pma (program-memory, BMAR) operand location and "2:" is the dma operand location;
the columns are the code location. `p_op1` = wait states for operand 1, `d_op2` = wait
states for operand 2, `p_code` = wait states for the code fetch.

Cycles for a Single Instruction:

| Operand (1: / 2:) | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| 1: DARAM/ROM / 2: DARAM | 2 | 2 | 2 | 2+p_code |
| 1: SARAM / 2: DARAM | 2 | 2 | 2 | 2+p_code |
| 1: External / 2: DARAM | 2+p_op1 | 2+p_op1 | 2+p_op1 | [blank in manual] |
| 1: DARAM/ROM / 2: SARAM | 2 | 2 | 2 | 2+p_code |
| 1: SARAM / 2: SARAM | 2, 3† | 2, 3† | 2, 3† | 2+p_code, 3+p_code† |
| 1: External / 2: SARAM | 2+p_op1 | 2+p_op1 | 2+p_op1 | 2+p_op1+p_code |
| 1: DARAM/ROM / 2: External | 2+d_op2 | 2+d_op2 | 2+d_op2 | 2+d_op2+p_code |
| 1: SARAM / 2: External | 2+d_op2 | 2+d_op2 | 2+d_op2 | 2+d_op2+p_code |
| 1: External / 2: External | 3+p_op1+d_op2 | 3+p_op1+d_op2 | 3+p_op1+d_op2 | 3+p_op1+d_op2+p_code |

† If both operands are in the same SARAM block.

Note: the External Memory cell for the "1: External / 2: DARAM" row is blank in the
printed manual (PDF p. 315, verified against the rendered page). INFERENCE: by the
pattern of the neighbouring rows it would be `2+p_op1+p_code`, but the manual prints
nothing there.

Cycles for a Repeat (RPT) Execution:

| Operand (1: / 2:) | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| 1: DARAM/ROM / 2: DARAM | n+1 | n+1 | n+1 | n+1+p_code |
| 1: SARAM / 2: DARAM | n+1 | n+1 | n+1 | n+1+p_code |
| 1: External / 2: DARAM | n+1+np_op1 | n+1+np_op1 | n+1+np_op1 | n+1+np_op1+p_code |
| 1: DARAM/ROM / 2: SARAM | n+1 | n+1 | n+1 | n+1+p_code |
| 1: SARAM / 2: SARAM | n+1, 2n+1† | n+1, 2n+1† | n+1, 2n+1† | n+1+p_code, 2n+1† |
| 1: External / 2: SARAM | n+1+np_op1 | n+1+np_op1 | n+1+np_op1 | n+1+np_op1+p_code |
| 1: DARAM/ROM / 2: External | n+1+nd_op2 | n+1+nd_op2 | n+1+nd_op2 | n+1+nd_op2+p_code |
| 1: SARAM / 2: External | n+1+nd_op2 | n+1+nd_op2 | n+1+nd_op2 | n+1+nd_op2+p_code |
| 1: External / 2: External | 2n+1+np_op1+nd_op2 | 2n+1+np_op1+nd_op2 | 2n+1+np_op1+nd_op2 | 2n+1+np_op1+nd_op2+p_code |

† If both operands are in the same SARAM block.

**Status Bits:** Affected by: OVM and PM. Affects: C and OV. (TRM is NOT listed for MADS,
unlike MAC/MACD — the execution block also has no TRM = 0 step.)

**Execution**

- `(PC) + 1 → PC`
- `(PFC) → MCS`; `(BMAR) → PFC`
- If (repeat counter) ≠ 0: `(ACC) + (shifted PREG) → ACC`; `(dma) → TREG0`;
  `(dma) × (pma, addressed by PFC) → PREG`; Modify current AR and ARP as specified;
  `(PFC) + 1 → PFC`; `(repeat counter) – 1 → repeat counter`
- Else: `(ACC) + (shifted PREG) → ACC`; `(dma) → TREG0`;
  `(dma) × (pma, addressed by PFC) → PREG`; Modify current AR and ARP as specified
- `(MCS) → PFC`

**Description (condensed):** PREG is shifted per PM and added to ACC; dma is loaded into
TREG0; dma × pma → PREG. The pma is in BMAR, not a long immediate constant,
enabling dynamic addressing of coefficient tables. C is set if the addition generates a
carry, otherwise cleared. Data and program memory locations can be any nonreserved
on-chip or off-chip locations; if the program memory is block B0 of on-chip RAM, CNF must
be set. In direct addressing mode, the dma cannot be modified during repetition. When
repeated, the pma in PFC is incremented by 1. With RPT, MADS is useful for long
sum-of-products operations because it becomes a single-cycle instruction once the RPT
pipeline is started. MADS is a TREG0, PREG, and multiply instruction (see Table 6–7).

---

## MAR — Modify auxiliary register / auxiliary register pointer

**Source:** §6.3, PDF p. 318 (printed p. 6-166) – p. 319 (printed p. 6-167).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `MAR dma` |
| Indirect | `MAR {ind} [,ARn]` |

**Operands:** 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`. (No dma range is given
in the Operands block for MAR; the direct form executes as a NOP — see Execution.)

**Opcode**

Direct addressing — bits 15–8: `10001011`; bit 7: `0`; bits 6–0: dma.
Indirect addressing — bits 15–8: `10001011`; bit 7: `1`; bits 6–0: See Section 5.2.

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 1 | 1 | 1 | 1+p |

Cycles for a Repeat (RPT) Execution:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| n | n | n | n+p |

**Status Bits:** Affected by: NDX. (No "Not affected by" / "Affects" list is given.)

**Execution**

- `(PC) + 1 → PC`
- Indirect addressing: Modify current AR and ARP as specified
- Direct addressing: Executes as a NOP

**Description (condensed):** In indirect addressing mode, the ARs and ARP are modified;
the memory being referenced is unaffected. Clearing NDX makes any 'C2x instruction
that modifies AR0 also modify ARCR and INDX, maintaining 'C5x object-code compatibility
with the 'C2x. MAR modifies the ARs or the ARP bits, and the old ARP bits are copied to
the ARB bits. Any operation performed with MAR can also be performed with any
instruction that supports indirect addressing. The ARP bits can also be loaded by an LST
instruction. Note: the LARP instruction from the 'C2x instruction set is a subset of MAR
(MAR *,4 performs the same function as LARP 4). MAR is an auxiliary registers and data
memory page pointer instruction (see Table 6–5).

---

## MPY — Multiply data memory value by TREG0 and store result in PREG

**Source:** §6.3, PDF p. 320 (printed p. 6-168) – p. 322 (printed p. 6-170).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `MPY dma` |
| Indirect | `MPY {ind} [,ARn]` |
| Short immediate | `MPY #k` |
| Long immediate | `MPY #lk` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; –4096 ≤ k ≤ 4095; –32768 ≤ lk ≤ 32767;
ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing — bits 15–8: `01010100`; bit 7: `0`; bits 6–0: dma.
Indirect addressing — bits 15–8: `01010100`; bit 7: `1`; bits 6–0: See Section 5.2.
Short immediate addressing — bits 15–13: `110`; bits 12–0: 13-Bit Constant.
Long immediate addressing, word 1 — bits 15–0: `1011111010000000`; word 2: 16-Bit Constant.

**Words:** 1 (direct, indirect, or short immediate addressing); 2 (long immediate addressing).

**Cycles**

For the short and long immediate addressing modes, the MPY instruction is not repeatable.

Cycles for a Single Instruction (direct or indirect addressing):

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution (direct or indirect addressing):

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

Cycles for a Single Instruction (short immediate addressing):

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 1 | 1 | 1 | 1+p |

Cycles for a Single Instruction (long immediate addressing):

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 2 | 2 | 2 | 2+2p |

No RPT table is given for the short or long immediate addressing modes.

**Status Bits:** Affected by: TRM. Not affected by: SXM.

**Execution**

- Direct or indirect addressing: `(PC) + 1 → PC`; `(TREG0) × (dma) → PREG`
- Short immediate addressing: `(PC) + 1 → PC`; `(TREG0) × k → PREG`
- Long immediate addressing: `(PC) + 2 → PC`; `(TREG0) × lk → PREG`

**Description (condensed):** If a constant is specified, the constant is multiplied by the
contents of TREG0; otherwise TREG0 is multiplied by the contents of dma. The result is
stored in PREG. Short immediate addressing multiplies TREG0 by a signed 13-bit constant;
the short immediate constant is right-justified and sign-extended before the multiplication,
regardless of the SXM bit. Clearing TRM makes any 'C2x instruction that loads TREG0
write to all three TREGs ('C2x compatibility; TREG1 has only 5 bits, TREG2 only 4 bits).
MPY is a TREG0, PREG, and multiply instruction (see Table 6–7).

---

## MPYA — Add PREG, with shift specified by PM bits, to ACC; multiply data memory value by TREG0 and store result in PREG

**Source:** §6.3, PDF p. 323 (printed p. 6-171) – p. 324 (printed p. 6-172).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `MPYA dma` |
| Indirect | `MPYA {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing — bits 15–8: `01010000`; bit 7: `0`; bits 6–0: dma.
Indirect addressing — bits 15–8: `01010000`; bit 7: `1`; bits 6–0: See Section 5.2.

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

**Status Bits:** Affected by: OVM, PM, and TRM. Affects: C and OV.

**Execution**

- `(PC) + 1 → PC`
- `(ACC) + (shifted PREG) → ACC`
- `(TREG0) × (dma) → PREG`

**Description (condensed):** PREG is shifted, as defined by the PM bits, and added to ACC;
the result is stored in ACC. TREG0 is multiplied by the contents of dma; the result is
stored in PREG. C is set if the addition generates a carry; otherwise C is cleared.
TRM = 0 makes a TREG0 load write to all three TREGs ('C2x compatibility; TREG1 has
only 5 bits, TREG2 only 4 bits). MPYA is a TREG0, PREG, and multiply instruction
(see Table 6–7).

---

## MPYS — Subtract PREG, with shift specified by PM bits, from ACC; multiply data memory value by TREG0 and store result in PREG

**Source:** §6.3, PDF p. 325 (printed p. 6-173) – p. 326 (printed p. 6-174).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `MPYS dma` |
| Indirect | `MPYS {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing — bits 15–8: `01010001`; bit 7: `0`; bits 6–0: dma.
Indirect addressing — bits 15–8: `01010001`; bit 7: `1`; bits 6–0: See Section 5.2.

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

**Status Bits:** Affected by: OVM, PM, and TRM. Affects: C and OV.

**Execution**

- `(PC) + 1 → PC`
- `(ACC) – (shifted PREG) → ACC`
- `(TREG0) × (dma) → PREG`

**Description (condensed):** PREG is shifted, as defined by the PM bits, and subtracted
from ACC; the result is stored in ACC. TREG0 is multiplied by the contents of dma; the
result is stored in PREG. C is cleared if the subtraction generates a borrow; otherwise C
is set. TRM = 0 makes a TREG0 load write to all three TREGs ('C2x compatibility; TREG1
has only 5 bits, TREG2 only 4 bits). MPYS is a TREG0, PREG, and multiply instruction
(see Table 6–7).

---

## MPYU — Multiply unsigned data memory value by TREG0 and store result in PREG

**Source:** §6.3, PDF p. 327 (printed p. 6-175) – p. 328 (printed p. 6-176).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `MPYU dma` |
| Indirect | `MPYU {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing — bits 15–8: `01010101`; bit 7: `0`; bits 6–0: dma.
Indirect addressing — bits 15–8: `01010101`; bit 7: `1`; bits 6–0: See Section 5.2.

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

**Status Bits:** Affected by: TRM. Not affected by: SXM.

**Execution**

- `(PC) + 1 → PC`
- `Unsigned (TREG0) × unsigned (dma) → PREG`

**Description (condensed):** The unsigned contents of TREG0 are multiplied by the
unsigned contents of dma; the result is stored in PREG. The multiplier acts as a signed
17 × 17-bit multiplier for this instruction, with the MSB of both operands forced to 0.
The p-scaler shifter at the output of the PREG always invokes sign-extension on the PREG
when the PM bits are set to 11₂ (right-shift-by-6 mode); therefore that shift mode should
not be used if unsigned products are wanted. TRM = 0 makes a TREG0 load write to all
three TREGs ('C2x compatibility; TREG1 has only 5 bits, TREG2 only 4 bits). MPYU is
particularly useful for computing multiple-precision products, such as multiplying two
32-bit numbers to yield a 64-bit product. MPYU is a TREG0, PREG, and multiply
instruction (see Table 6–7).

---

## NEG — Negate ACC (2s complement)

**Source:** §6.3, PDF p. 329 (printed p. 6-177) – p. 330 (printed p. 6-178).

**Syntax:** `NEG`

**Operands:** None.

**Opcode**

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 1 | 1 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 |

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 1 | 1 | 1 | 1+p |

Cycles for a Repeat (RPT) Execution:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| n | n | n | n+p |

**Status Bits:** Affected by: OVM. Affects: C and OV.

**Execution**

- `(PC) + 1 → PC`
- `(ACC) × –1 → ACC`
- If (ACC) ≠ 0: `0 → C`. If (ACC) = 0: `1 → C`.

**Description (condensed):** The contents of ACC are replaced with their arithmetic
complement (2s complement). If the ACC contents are not 0, C is cleared; if they are 0,
C is set. When taking the 2s complement of 8000 0000h, the OV bit is set and: if OVM is
set, ACC is replaced with 7FFF FFFFh; if OVM is cleared, ACC is replaced with
8000 0000h. NEG is an accumulator memory reference instruction (see Table 6–4).

---

## NMI — Nonmaskable interrupt (software)

**Source:** §6.3, PDF p. 331 (printed p. 6-179).

**Syntax:** `NMI`

**Operands:** None.

**Opcode**

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 1 | 1 | 1 | 1 | 1 | 0 | 0 | 1 | 0 | 1 | 0 | 0 | 1 | 0 |

**Words:** 1.

**Cycles**

The NMI instruction is not repeatable. No RPT table is given.

Cycles for a Single Instruction:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 4 | 4 | 4 | 4+3p† |

† The 'C5x performs speculative fetching by reading two additional instruction words.
If PC discontinuity is taken, these two instruction words are discarded.

**Status Bits:** Not affected by: INTM. Affects: INTM.

**Execution**

- `(PC) + 1 → stack`
- `24h → PC`
- `1 → INTM`

**Description (condensed):** The current PC is incremented and pushed onto the stack.
The nonmaskable interrupt vector at 24h is loaded into the PC; execution continues at
that address. Interrupts are globally disabled (INTM is set). NMI has the same effect as a
hardware nonmaskable interrupt. Automatic context save is not performed. NMI is a branch
and call instruction (see Table 6–8).

---

## NOP — No operation

**Source:** §6.3, PDF p. 332 (printed p. 6-180).

**Syntax:** `NOP`

**Operands:** None.

**Opcode**

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 0 | 0 | 1 | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 1 | 1 | 1 | 1+p |

Cycles for a Repeat (RPT) Execution:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| n | n | n | n+p |

**Status Bits:** None affected.

**Execution**

- `(PC) + 1 → PC`

**Description (condensed):** No operation is performed. NOP affects only the PC. NOP can
be used to create pipeline and execution delays. NOP is a control instruction
(see Table 6–10).

---

## NORM — Normalize ACC

**Source:** §6.3, PDF p. 333 (printed p. 6-181) – p. 335 (printed p. 6-183).

**Syntax:** `NORM {ind}`

**Operands:** ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | See Section 5.2 (bits 6–0) | | | | | | |

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 1 | 1 | 1 | 1+p |

Cycles for a Repeat (RPT) Execution:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| n | n | n | n+p |

**Status Bits:** Affects: TC. (No "Affected by" / "Not affected by" list is given.)

**Execution**

- `(PC) + 1 → PC`
- If (ACC) = 0: `TC → 1`
- Else: if (ACC(31)) XOR (ACC(30)) = 0: `TC → 0`; `(ACC) × 2 → ACC`; Modify current AR as specified. Else: `TC → 1`.

**Description (condensed):** The signed number in ACC is normalized. Normalizing a
fixed-point number separates it into a mantissa and an exponent by finding the magnitude
of the sign-extended number. ACC bit 31 is XORed with ACC bit 30 to determine whether
bit 30 is part of the magnitude or part of the sign extension. If the bits are the same, both
are sign bits and ACC is shifted left to eliminate the extra sign bit. If the XOR result is
true, TC is set; otherwise TC is cleared. The current AR is modified as specified to
generate the magnitude of the exponent; it is assumed the current AR is initialized before
normalization begins. The default modification of the current AR is an increment. Multiple
executions of NORM may be required to completely normalize a 32-bit number. Using
NORM with RPT does not make execution fall out of the repeat loop automatically when
normalization is complete, but no operation is performed for the remainder of the repeat
loop. NORM functions on both positive and negative 2s-complement numbers. Pipeline
constraint: NORM executes the auxiliary register operation during the execution phase of
the pipeline, so the AR used in the NORM instruction should not be used by an auxiliary
register instruction in the next two instruction words immediately following NORM, and ARP
should not be modified by the next two words. Note: NORM can be used without a
specified operand; then any comments on the same line are interpreted as the operand.
If the first character is an asterisk (*), the instruction is assembled as NORM * with no AR
modification on execution; TI recommends replacing such NORM instructions with
NORM *+ when the default increment modification is wanted. NORM is an accumulator
memory reference instruction (see Table 6–4).

---

## OPL — OR data memory value with long immediate / DBMR (PLU)

**Source:** §6.3, PDF p. 336 (printed p. 6-184) – p. 338 (printed p. 6-186).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `OPL [#lk], dma` |
| Indirect | `OPL [#lk], {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; lk: 16-bit constant; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing, long immediate not specified — bits 15–8: `01011001`; bit 7: `0`; bits 6–0: dma.
Indirect addressing, long immediate not specified — bits 15–8: `01011001`; bit 7: `1`; bits 6–0: See Section 5.2.
Direct addressing, long immediate specified, word 1 — bits 15–8: `01011101`; bit 7: `0`; bits 6–0: dma. Word 2: 16-Bit Constant.
Indirect addressing, long immediate specified, word 1 — bits 15–8: `01011101`; bit 7: `1`; bits 6–0: See Section 5.2. Word 2: 16-Bit Constant.

**Words:** 1 (long immediate not specified); 2 (long immediate specified).

**Cycles**

Cycles for a Single Instruction (long immediate not specified):

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 3† | 1+p |
| External | 2+2d | 2+2d | 2+2d | 5+2d+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution (long immediate not specified):

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | 2n–2 | 2n–2 | 2n–2, 2n+1† | 2n–2+p |
| External | 4n–2+2nd | 4n–2+2nd | 4n–2+2nd | 4n+1+2nd+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Single Instruction (long immediate specified):

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 2 | 2 | 2 | 2+2p |
| SARAM | 2 | 2 | 2 | 2+2p |
| External | 3+2d | 3+2d | 3+2d | 6+2d+2p |

Cycles for a Repeat (RPT) Execution (long immediate specified):

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n+1 | n+1 | n+1 | n+1+2p |
| SARAM | 2n–1 | 2n–1 | 2n–1, 2n+2† | 2n–1+2p |
| External | 4n–1+2nd | 4n–1+2nd | 4n–1+2nd | 4n+2+2nd+2p |

† If the operand and the code are in the same SARAM block.

**Status Bits:** Affects: TC. (No "Affected by" / "Not affected by" list is given.)

**Execution**

- Long immediate not specified: `(PC) + 1 → PC`; `(dma) OR (DBMR) → dma`
- Long immediate specified: `(PC) + 2 → PC`; `(dma) OR lk → dma`

**Description (condensed):** If a long immediate constant is specified, the constant is ORed
with the contents of dma. If no constant is specified, the contents of dma are ORed with
the contents of the dynamic bit manipulation register (DBMR). In both cases the result is
written directly back to dma and ACC is unaffected. If the result of the OR operation is 0,
TC is set; otherwise TC is cleared. OPL is a parallel logic unit (PLU) instruction
(see Table 6–6).

---

## OR — OR ACC with data memory value / long immediate

**Source:** §6.3, PDF p. 339 (printed p. 6-187) – p. 341 (printed p. 6-189).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `OR dma` |
| Indirect | `OR {ind} [,ARn]` |
| Long immediate | `OR #lk [,shift]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; lk: 16-bit constant; 0 ≤ shift ≤ 16;
ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing — bits 15–8: `01101101`; bit 7: `0`; bits 6–0: dma.
Indirect addressing — bits 15–8: `01101101`; bit 7: `1`; bits 6–0: See Section 5.2.
Long immediate addressing with shift, word 1 — bits 15–4: `101111111100`; bits 3–0: SHFT†. Word 2: 16-Bit Constant.
Long immediate addressing with shift of 16, word 1 — bits 15–0: `1011111010000010`. Word 2: 16-Bit Constant.

† See Table 6–1 on page 6-2.

**Words:** 1 (direct or indirect addressing); 2 (long immediate addressing).

**Cycles**

For the long immediate addressing mode, the OR instruction is not repeatable.

Cycles for a Single Instruction (direct or indirect addressing):

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution (direct or indirect addressing):

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

Cycles for a Single Instruction (long immediate addressing):

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 2 | 2 | 2 | 2+2p |

No RPT table is given for the long immediate addressing mode.

**Status Bits:** Does not affect: C. Not affected by: SXM (long immediate addressing).
(Status Bits block as printed on PDF p. 339, verified against the rendered page:
"Does not affect: C" on one line; "Not affected by: SXM" with "Long immediate addressing"
set against it.)

**Execution**

- Direct or indirect addressing: `(PC) + 1 → PC`; `(ACC(15–0)) OR (dma) → ACC(15–0)`; `(ACC(31–16)) → ACC(31–16)`
- Long immediate addressing: `(PC) + 2 → PC`; `(ACC) OR (lk × 2^shift) → ACC`

**Description (condensed):** If a long immediate constant is specified, the constant is
shifted as defined by the shift code, zero-extended on both ends, and ORed with ACC;
the result is stored in ACC. If no constant is specified, the contents of dma are ORed
with ACCL; the result is stored in ACCL and ACCH is unaffected. OR is an accumulator
memory reference instruction (see Table 6–4).

---

## ORB — OR ACC with ACCB

**Source:** §6.3, PDF p. 342 (printed p. 6-190).

**Syntax:** `ORB`

**Operands:** None.

**Opcode**

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 1 | 1 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 1 | 1 |

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 1 | 1 | 1 | 1+p |

Cycles for a Repeat (RPT) Execution:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| n | n | n | n+p |

**Status Bits:** None affected.

**Execution**

- `(PC) + 1 → PC`
- `(ACC) OR (ACCB) → ACC`

**Description (condensed):** The contents of ACC are ORed with the contents of the
accumulator buffer (ACCB). The result is stored in ACC; the contents of ACCB are
unaffected. ORB is an accumulator memory reference instruction (see Table 6–4).

---

## OUT — Write data memory value to I/O port

**Source:** §6.3, PDF p. 343 (printed p. 6-191) – p. 344 (printed p. 6-192).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `OUT dma, PA` |
| Indirect | `OUT {ind}, PA [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; 0 ≤ port address PA ≤ 65535;
ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing, word 1 — bits 15–8: `00001100`; bit 7: `0`; bits 6–0: dma. Word 2: 16-Bit Constant.
Indirect addressing, word 1 — bits 15–8: `00001100`; bit 7: `1`; bits 6–0: See Section 5.2. Word 2: 16-Bit Constant.

**Words:** 2.

**Cycles**

Cycles for a Single Instruction:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| Source: DARAM | 3+io_dst | 3+io_dst | 3+io_dst | 5+io_dst+2p_code |
| Source: SARAM | 3+io_dst | 3+io_dst | 3+io_dst, 4+io_dst† | 5+io_dst+2p_code |
| Source: External | 3+d_src+io_dst | 3+d_src+io_dst | 3+d_src+io_dst | 6+d_src+io_dst+2p_code |

† If the source operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| Source: DARAM | 3n+nio_dst | 3n+nio_dst | 3n+nio_dst | 3n+3+nio_dst+2p_code |
| Source: SARAM | 3n+nio_dst | 3n+nio_dst | 3n+nio_dst, 3n+1+nio_dst† | 3n+3+nio_dst+2p_code |
| Source: External | 5n–2+nd_src+nio_dst | 5n–2+nd_src+nio_dst | 5n–2+nd_src+nio_dst | 5n+1+nd_src+nio_dst+2p_code |

† If the source operand and the code are in the same SARAM block.

**Status Bits:** None affected.

**Execution**

- `(PC) + 2 → PC`
- While (repeat counter) ≠ 0: Port address → address bus A15–A0; `(dma) → data bus D15–D0`;
  Port address + 1 → Port address; `(repeat counter – 1) → (repeat counter)`;
  `(dma) → Port address` (as printed — see note below)

**Description (condensed):** A 16-bit value from dma is written to the specified I/O port.
The IS line goes low to indicate an I/O access, and the STRB, R/W, and READY timings are
the same as for an external data memory write. Port addresses 50h–5Fh are memory-mapped
(see subsection 9.1.1, Memory-Mapped Peripheral Registers and I/O Ports); the other port
addresses are not. With RPT, OUT writes consecutive words in data memory to I/O space;
the number of words moved is one greater than the number in RPTC at the beginning of
the instruction. With RPT, OUT becomes a single-cycle instruction once the RPT pipeline
is started, and the port address is incremented after each access. OUT is an I/O and data
memory operation instruction (see Table 6–9).

Note on the Execution block: its final line, `(dma) → Port address`, is as printed in the
manual (PDF p. 343, verified against the rendered page). It is inconsistent with the
description, which states that consecutive data-memory words are written under RPT
(implying the dma advances, not that dma is written into the port address). Recorded
as printed; no correction applied.

---

## PAC — Load PREG, with shift specified by PM bits, to ACC

**Source:** §6.3, PDF p. 345 (printed p. 6-193).

**Syntax:** `PAC`

**Operands:** None.

**Opcode**

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 1 | 1 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 1 |

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 1 | 1 | 1 | 1+p |

Cycles for a Repeat (RPT) Execution:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| n | n | n | n+p |

**Status Bits:** Affected by: PM. (No "Not affected by" / "Affects" list is given.)

**Execution**

- `(PC) + 1 → PC`
- `(shifted PREG) → ACC`

**Description (condensed):** The contents of PREG are shifted, as defined by the PM bits,
and loaded into ACC. PAC is a TREG0, PREG, and multiply instruction (see Table 6–7).

---

## POP — Pop top of stack to ACCL; zero ACCH

**Source:** §6.3, PDF p. 346 (printed p. 6-194) – p. 347 (printed p. 6-195).

**Syntax:** `POP`

**Operands:** None.

**Opcode**

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 1 | 1 | 1 | 1 | 1 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 1 | 0 |

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 1 | 1 | 1 | 1+p |

Cycles for a Repeat (RPT) Execution:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| n | n | n | n+p |

**Status Bits:** None affected.

**Execution**

- `(PC) + 1 → PC`
- `(TOS) → ACC(15–0)`; `0 → ACC(31–16)`
- Pop stack one level

**Description (condensed):** The contents of the top of the stack (TOS) are copied to ACCL;
the stack is popped one level after the contents are copied; ACCH is zero-filled. The
hardware stack is last-in, first-out with eight locations. Any time a pop occurs, every stack
value is copied to the next higher stack location and the top value is removed; after a pop,
the bottom two stack words have the same value. Because each stack value is copied, if
more than seven stack pops (POP, POPD, RET, RETC, RETE, or RETI instructions) occur
before any pushes occur, all levels of the stack contain the same value. No provision
exists to check stack underflow. POP is a control instruction (see Table 6–10).

---

## POPD — Pop top of stack to data memory

**Source:** §6.3, PDF p. 348 (printed p. 6-196) – p. 349 (printed p. 6-197).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `POPD dma` |
| Indirect | `POPD {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing — bits 15–8: `10000100`; bit 7: `0`; bits 6–0: dma.
Indirect addressing — bits 15–8: `10000100`; bit 7: `1`; bits 6–0: See Section 5.2.

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 2+d | 2+d | 2+d | 4+d+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+2† | n+p |
| External | 2n+nd | 2n+nd | 2n+nd | 2n+2+nd+p |

† If the operand and the code are in the same SARAM block.

**Status Bits:** None affected.

**Execution**

- `(PC) + 1 → PC`
- `(TOS) → dma`
- Pop stack one level

**Description (condensed):** The contents of TOS are copied to dma. The values are popped
one level in the lower seven locations of the stack. The value in the lowest stack location
is unaffected. See the POP instruction (printed p. 6-194) for more information. POPD is a
control instruction (see Table 6–10).

---

## PSHD — Push data memory value onto stack

**Source:** §6.3, PDF p. 350 (printed p. 6-198) – p. 351 (printed p. 6-199).

**Syntax**

| Form | Syntax |
|---|---|
| Direct | `PSHD dma` |
| Indirect | `PSHD {ind} [,ARn]` |

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode**

Direct addressing — bits 15–8: `01110110`; bit 7: `0`; bits 6–0: dma.
Indirect addressing — bits 15–8: `01110110`; bit 7: `1`; bits 6–0: See Section 5.2.

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

Cycles for a Repeat (RPT) Execution:

| Operand | ROM | DARAM | SARAM | External Memory |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

**Status Bits:** None affected.

**Execution**

- `(dma) → TOS`
- `(PC) + 1 → PC`
- Push all stack locations down one level

**Description (condensed):** The contents of dma are copied to TOS. The values are pushed
down one level in the lower seven locations of the stack. The value in the lowest stack
location is lost. See the PUSH instruction (printed p. 6-200) for more information. PSHD is
a control instruction (see Table 6–10).

---

## PUSH — Push ACCL onto stack

**Source:** §6.3, PDF p. 352 (printed p. 6-200) – p. 353 (printed p. 6-201).

**Syntax:** `PUSH`

**Operands:** None.

**Opcode**

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 1 | 1 | 1 | 1 | 1 | 0 | 0 | 0 | 1 | 1 | 1 | 1 | 0 | 0 |

**Words:** 1.

**Cycles**

Cycles for a Single Instruction:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 1 | 1 | 1 | 1+p |

Cycles for a Repeat (RPT) Execution:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| n | n | n | n+p |

**Status Bits:** None affected.

**Execution**

- `(PC) + 1 → PC`
- Push all stack locations down one level
- `ACC(15–0) → TOS`

**Description (condensed):** The values are pushed down one level in the lower seven
locations of the stack. The contents of ACCL are copied to TOS. The values on the stack
are pushed down before the ACC value is copied. The hardware stack is last-in,
first-out with eight locations. If more than eight pushes (CALA, CALL, CC, INTR, NMI,
PSHD, PUSH, or TRAP instructions) occur before a pop, the first data values written are
lost with each succeeding push. PUSH is a control instruction (see Table 6–10).

---

## RET — Return from subroutine

**Source:** §6.3, PDF p. 354 (printed p. 6-202). Entry complete on this page; the next
entry (RETC) starts on PDF p. 355 and is NOT in this file.

**Syntax:** `RET`

**Operands:** None.

**Opcode**

| 15 | 14 | 13 | 12 | 11 | 10 | 9 | 8 | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 1 | 0 | 1 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

**Words:** 1.

**Cycles**

The RET instruction is not repeatable. No RPT table is given.

Cycles for a Single Instruction:

| ROM | DARAM | SARAM | External Memory |
|---|---|---|---|
| 4 | 4 | 4 | 4+3p† |

† The 'C5x performs speculative fetching by reading two additional instruction words.
If PC discontinuity is taken, these two instruction words are discarded.

**Status Bits:** None affected.

**Execution**

- `(TOS) → PC`
- Pop stack one level

**Description (condensed):** The contents of TOS are copied to the PC. The stack is popped
one level after the contents are copied. RET is used with the CALA, CALL, and CC
instructions for subroutines. RET is a branch and call instruction (see Table 6–8).

---
