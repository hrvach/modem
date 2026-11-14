# TMS320C5x User's Guide (SPRU056D, June 1998) — Chapter 6, §6.3 Instruction Set Descriptions: ABS – LACC

Source: `~/workspace/user/files/spru056d.pdf` (SPRU056D, June 1998), §6.3, PDF pp. 179–266 (printed pp. 6-27–6-114).
46 instructions transcribed, alphabetically ABS through LACC. Entries are ordered by the mnemonic under which the
manual files them; each entry starts on the PDF page cited. An entry starting on PDF p. 266 (LACC) is included even
though it runs to PDF p. 268; the next entry (LACL, PDF p. 269) is NOT in this file.

## Reading conventions (from the manual itself)

- Cycle assumptions (§6.3 intro, PDF p. 179 / printed 6-27): at least four instructions following the current
  instruction are fetched from the same memory section as the current instruction (except after a PC
  discontinuity such as B, CALL); for a single instruction there is no pipeline conflict with the preceding or
  following instruction except fetch-phase vs. memory read/write of the instruction itself (see Ch. 7); in repeat
  (RPT) execution all pipelining conflicts of that instruction are counted.
- Cycle symbols (manual Ch. 7 usage): `p` = program-memory wait states, `d` = data-memory wait states,
  `io` = I/O wait states (additional clock cycles per external access); `n` in RPT tables = number of
  repetitions. `†` footnote, repeated on the relevant tables: "If the operand and the code are in the same
  SARAM block" (SARAM column shows two values, e.g. `1, 2†` — the second applies when operand and code
  share a SARAM block).
- Opcode rows are transcribed as printed: bit numbers 15..0 left to right; field names (`dma`, `SHFT`,
  `ind` = "See Section 5.2") as printed. `SHFT †` = "See Table 6–1 on page 6-2" (shift-code table).
  Bit patterns were cross-checked against the §6.2 summary tables (PDF pp. 161–172) where legible; any
  disagreement is noted under the entry.
- "Status Bits" reproduces the manual's three columns (Affected by / Not affected by / Affects) per addressing
  form where the manual splits them. "None affected" is the manual's wording where it says so.
- Examples are NOT transcribed (task rule: no examples unless the example states a rule). Descriptions are
  condensed to normative rules/constraints only.
- `[UNVERIFIED — extraction garbled, §6.3 <mnemonic>, PDF p.Y]` marks any field that could not be read
  reliably from the extraction; nothing is guessed in those places.

---

## ABS — Absolute Value of Accumulator

**Ref:** §6.3, PDF p. 180 / printed 6-28 (entry continues PDF p. 181 / printed 6-29, examples only).

**Syntax:** `ABS`
**Operands:** None

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 0 0 0  0 0 0 0` — i.e. `1011 1110 0000 0000`.

**Execution:**
- `(PC) + 1 → PC`
- `|(ACC)| → ACC`
- `0 → C`

**Status bits:** Affected by: OVM. Not affected by: SXM. Affects: C and OV.

**Description:** If (ACC) ≥ 0, ACC unchanged. If (ACC) < 0, ACC is replaced by its 2s-complement value. ABS clears C.
Special case 8000 0000h: with OVM = 0, ABS = 8000 0000h; with OVM = 1, ABS = 7FFF FFFFh. In either case OV is set.
Accumulator memory reference instruction (see Table 6–4).

**Words:** 1

**Cycles — single instruction:** ROM 1, DARAM 1, SARAM 1, External 1+p.
**Cycles — RPT execution:** ROM n, DARAM n, SARAM n, External n+p.

---

## ADCB — Add ACCB and Carry Bit to ACC

**Ref:** §6.3, PDF p. 182 / printed 6-30.

**Syntax:** `ADCB`
**Operands:** None

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 0 0 1  0 0 0 1` — i.e. `1011 1110 0001 0001`.

**Execution:**
- `(PC) + 1 → PC`
- `(ACC) + (ACCB) + (C) → ACC`

**Status bits:** Affected by: OVM. Affects: C and OV.

**Description:** (ACCB) and the C bit are added to (ACC); result in ACC; (ACCB) unaffected. C is set if the
addition generates a carry, otherwise cleared. Accumulator memory reference instruction (see Table 6–4).

**Words:** 1

**Cycles — single instruction:** ROM 1, DARAM 1, SARAM 1, External 1+p.
**Cycles — RPT execution:** ROM n, DARAM n, SARAM n, External n+p.

---

## ADD — Add Data Memory Value, with Left Shift, to ACC

**Ref:** §6.3, PDF pp. 183–186 / printed 6-31–6-34.

**Syntax:**
- Direct: `ADD dma [,shift]`
- Indirect: `ADD {ind} [,shift] [,ARn]`
- Short immediate: `ADD #k`
- Long immediate: `ADD #lk [,shift]`

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ shift ≤ 16 (defaults to 0); 0 ≤ n ≤ 7; 0 ≤ k ≤ 255; −32768 ≤ lk ≤ 32767;
ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcodes** (15..0):
- Direct, with shift: `0 0 1 0  SHFT†  0  dma[6:0]` — bits 15–12 = 0010, bits 11–8 = SHFT, bit 7 = 0, bits 6–0 = dma.
- Indirect, with shift: `0 0 1 0  SHFT†  1  [See Section 5.2]` — bits 15–12 = 0010, bits 11–8 = SHFT, bit 7 = 1, bits 6–0 = indirect-addressing field.
- Direct, shift of 16: `0 1 1 0  0 0 0 1  0  dma[6:0]` — bits 15–8 = 0110 0001, bit 7 = 0, bits 6–0 = dma.
- Indirect, shift of 16: `0 1 1 0  0 0 0 1  1  [See Section 5.2]` — bits 15–8 = 0110 0001, bit 7 = 1, bits 6–0 = indirect-addressing field.
- Short immediate: `1 0 1 1  1 0 0 0  8-Bit Constant` — bits 15–8 = 1011 1000, bits 7–0 = 8-bit constant.
- Long immediate, with shift: `1 0 1 1  1 1 1 1  1 0 0 1  SHFT†`, second word = 16-Bit Constant — bits 15–4 = 1011 1111 1001, bits 3–0 = SHFT.
  † SHFT: see Table 6–1 on page 6-2.

**Execution:**
- Direct or indirect: `(PC) + 1 → PC`; `(ACC) + ((dma) × 2^shift) → ACC`
- Short immediate: `(PC) + 1 → PC`; `(ACC) + k → ACC`
- Long immediate: `(PC) + 2 → PC`; `(ACC) + (lk × 2^shift) → ACC`

**Status bits:**
- Direct or indirect: Affected by OVM and SXM. Affects C and OV.
- Short immediate: Affected by OVM. Affects C and OV.
- Long immediate: Affected by OVM and SXM. Affects C and OV.

**Description:** Direct/indirect/long-immediate: (dma) or the 16-bit constant is shifted left as defined by the
shift code and added to (ACC); result in ACC. During shifting, ACCL is zero-filled. If SXM = 0, the high-order
bits of ACC are zero-filled; if SXM = 1, they are sign-extended. When ARP is updated during indirect
addressing, a shift operand must be specified; enter 0 if no shift is wanted (e.g. `ADD *+,0,AR0`).
Short immediate: an 8-bit positive constant is added to (ACC); result in ACC. No shift value may be specified;
addition is unaffected by SXM. C is set if the addition generates a carry, otherwise cleared — EXCEPT: if a
16-bit shift is specified, C is set only if the addition generates a carry, otherwise C is unaffected (this allows
accumulation to generate the proper single carry when a 32-bit number is added to ACC).
Accumulator memory reference instruction (see Table 6–4).

**Words:** 1 (direct, indirect, or short immediate); 2 (long immediate).

**Cycles — single instruction (direct or indirect):**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

**Cycles — RPT execution (direct or indirect):**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

**Cycles — single instruction (short immediate):** ROM 1, DARAM 1, SARAM 1, External 1+p.
**Cycles — single instruction (long immediate):** ROM 2, DARAM 2, SARAM 2, External 2+2p.
Short and long immediate modes are NOT repeatable.

---

## ADDB — Add ACCB to ACC

**Ref:** §6.3, PDF p. 187 / printed 6-35.

**Syntax:** `ADDB`
**Operands:** None

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 0 0 1  0 0 0 0` — i.e. `1011 1110 0001 0000`.

**Execution:**
- `(PC) + 1 → PC`
- `(ACC) + (ACCB) → ACC`

**Status bits:** Affected by: OVM. Affects: C and OV.

**Description:** (ACCB) is added to (ACC); result in ACC; (ACCB) unaffected. C is set if the addition
generates a carry, otherwise cleared. Accumulator memory reference instruction (see Table 6–4).

**Words:** 1

**Cycles — single instruction:** ROM 1, DARAM 1, SARAM 1, External 1+p.
**Cycles — RPT execution:** ROM n, DARAM n, SARAM n, External n+p.

---

## ADDC — Add Data Memory Value and Carry Bit to ACC

**Ref:** §6.3, PDF pp. 188–189 / printed 6-36–6-37.

**Syntax:**
- Direct: `ADDC dma`
- Indirect: `ADDC {ind} [,ARn]`

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcodes** (15..0):
- Direct: `0 1 1 0  0 0 0 0  0  dma[6:0]` — bits 15–7 = 0110 0000 0, bits 6–0 = dma.
- Indirect: `0 1 1 0  0 0 0 0  1  [See Section 5.2]` — bits 15–7 = 0110 0000 1, bits 6–0 = indirect-addressing field.

**Execution:**
- `(PC) + 1 → PC`
- `(ACC) + (dma) + (C) → ACC`

**Status bits:** Affected by: OVM. Not affected by: SXM. Affects: C and OV.

**Description:** (dma) and the C bit are added to (ACC) with sign extension suppressed; result in ACC.
C is set if the addition generates a carry, otherwise cleared. Usable for multiple-precision arithmetic.
Accumulator memory reference instruction (see Table 6–4).

**Words:** 1

**Cycles — single instruction:**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

**Cycles — RPT execution:**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

---

## ADDS — Add Data Memory Value to ACC (Sign Extension Suppressed)

**Ref:** §6.3, PDF pp. 190–191 / printed 6-38–6-39.

**Syntax:**
- Direct: `ADDS dma`
- Indirect: `ADDS {ind} [,ARn]`

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcodes** (15..0):
- Direct: `0 1 1 0  0 0 1 0  0  dma[6:0]` — bits 15–7 = 0110 0010 0, bits 6–0 = dma.
- Indirect: `0 1 1 0  0 0 1 0  1  [See Section 5.2]` — bits 15–7 = 0110 0010 1, bits 6–0 = indirect-addressing field.

**Execution:**
- `(PC) + 1 → PC`
- `(ACC) + (dma) → ACC`
- (dma) is an unsigned 16-bit number.

**Status bits:** Affected by: OVM. Not affected by: SXM. Affects: C and OV.

**Description:** (dma) is added to (ACC) with sign extension suppressed. The data is treated as an unsigned
16-bit number regardless of SXM; (ACC) is treated as a signed number. Result in ACC. C is set if the
addition generates a carry, otherwise cleared. Produces the same results as ADD with SXM = 0 and shift
count 0. Accumulator memory reference instruction (see Table 6–4).

**Words:** 1

**Cycles — single instruction:**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

**Cycles — RPT execution:**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

---

## ADDT — Add Data Memory Value, Shifted by TREG1, to ACC

**Ref:** §6.3, PDF pp. 192–193 / printed 6-40–6-41.

**Syntax:**
- Direct: `ADDT dma`
- Indirect: `ADDT {ind} [,ARn]`

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcodes** (15..0):
- Direct: `0 1 1 0  0 0 1 1  0  dma[6:0]` — bits 15–7 = 0110 0011 0, bits 6–0 = dma.
- Indirect: `0 1 1 0  0 0 1 1  1  [See Section 5.2]` — bits 15–7 = 0110 0011 1, bits 6–0 = indirect-addressing field.

**Execution:**
- `(PC) + 1 → PC`
- `(ACC) + ((dma) × 2^TREG1(3–0)) → ACC`
- If SXM = 0: (dma) is not sign-extended. If SXM = 1: (dma) is sign-extended.

**Status bits:** Affected by: OVM, SXM, and TRM. Affects: C and OV.

**Description:** (dma) is shifted left 0 to 15 bits, as defined by the 4 LSBs of TREG1, and added to (ACC);
result in ACC. Sign extension on the dma value is controlled by SXM. C is set if the addition generates a
carry, otherwise cleared. 'C2x compatibility: clearing TRM causes any 'C2x instruction that loads TREG0 to
write to all three TREGs, so subsequent ADDT calls shift by the TREG1 value (same as TREG0).
Accumulator memory reference instruction (see Table 6–4).

**Words:** 1

**Cycles — single instruction:**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

**Cycles — RPT execution:**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

---

## ADRK — Add Short Immediate to Auxiliary Register

**Ref:** §6.3, PDF p. 194 / printed 6-42.

**Syntax:** `ADRK #k`
**Operands:** 0 ≤ k ≤ 255

**Opcode** (15..0): `0 1 1 1  1 0 0 0  8-Bit Constant` — bits 15–8 = 0111 1000, bits 7–0 = 8-bit constant.

**Execution:**
- `(PC) + 1 → PC`
- `(current AR) + 8-bit positive constant → current AR`

**Status bits:** None affected.

**Description:** The 8-bit immediate value, right-justified, is added to the current auxiliary register (AR);
result in AR. Addition takes place in the auxiliary register arithmetic unit (ARAU), with the immediate value
treated as an 8-bit positive integer. All arithmetic operations on the AR are unsigned. Auxiliary registers and
data memory page pointer instruction (see Table 6–5).

**Words:** 1

**Cycles:** NOT repeatable. **Single instruction:** ROM 1, DARAM 1, SARAM 1, External 1+p.

---

## AND — AND Data Memory Value with ACC

**Ref:** §6.3, PDF pp. 195–197 / printed 6-43–6-45.

**Syntax:**
- Direct: `AND dma`
- Indirect: `AND {ind} [,ARn]`
- Long immediate: `AND #lk [,shift]`

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; lk: 16-bit constant; 0 ≤ shift ≤ 16; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcodes** (15..0):
- Direct: `0 1 1 0  1 1 1 0  0  dma[6:0]` — bits 15–7 = 0110 1110 0, bits 6–0 = dma.
- Indirect: `0 1 1 0  1 1 1 0  1  [See Section 5.2]` — bits 15–7 = 0110 1110 1, bits 6–0 = indirect-addressing field.
- Long immediate, with shift: `1 0 1 1  1 1 1 1  1 0 1 1  SHFT†`, second word = 16-Bit Constant — bits 15–4 = 1011 1111 1011, bits 3–0 = SHFT.
- Long immediate, shift of 16: `1 0 1 1  1 1 1 0  1 0 0 0  0 0 0 1`, second word = 16-Bit Constant — bits 15–0 = 1011 1110 1000 0001.
  † SHFT: see Table 6–1 on page 6-2.

**Execution:**
- Direct or indirect: `(PC) + 1 → PC`; `(ACC(15–0)) AND (dma) → ACC(15–0)`; `0 → ACC(31–16)`.
- Long immediate: `(PC) + 2 → PC`; `(ACC(30–0)) AND (lk × 2^shift) → ACC`.

**Status bits:** Not affected by: SXM (long immediate addressing). [INFERENCE: the manual's Status Bits block
for AND lists only this "Not affected by" line; no "Affects" line is printed for AND — no status bit is
listed as affected.]

**Description:** Long immediate: the constant is shifted left and zero-extended on both ends and ANDed
with (ACC); result in ACC. Otherwise (dma) is ANDed with ACCL; result in ACCL and ACCH is zero-filled.
Accumulator memory reference instruction (see Table 6–4).

**Words:** 1 (direct or indirect); 2 (long immediate).

**Cycles — single instruction (direct or indirect):**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

**Cycles — RPT execution (direct or indirect):**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

**Cycles — single instruction (long immediate):** ROM 2, DARAM 2, SARAM 2, External 2+2p.
Long immediate mode is NOT repeatable.

---

## ANDB — AND ACCB with ACC

**Ref:** §6.3, PDF p. 198 / printed 6-46.

**Syntax:** `ANDB`
**Operands:** None

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 0 0 1  0 0 1 0` — i.e. `1011 1110 0001 0010`.

**Execution:**
- `(PC) + 1 → PC`
- `(ACC) AND (ACCB) → ACC`

**Status bits:** None affected.

**Description:** (ACC) is ANDed with (ACCB); result in ACC; (ACCB) unaffected. Accumulator memory
reference instruction (see Table 6–4).

**Words:** 1

**Cycles — single instruction:** ROM 1, DARAM 1, SARAM 1, External 1+p.
**Cycles — RPT execution:** ROM n, DARAM n, SARAM n, External n+p.

---

## APAC — Add Shifted PREG to ACC

**Ref:** §6.3, PDF p. 199 / printed 6-47.

**Syntax:** `APAC`
**Operands:** None

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 0 0 0  0 1 0 0` — i.e. `1011 1110 0000 0100`.

**Execution:**
- `(PC) + 1 → PC`
- `(ACC) + (shifted PREG) → ACC`

**Status bits:** Affected by: OVM and PM. Not affected by: SXM. Affects: C and OV.

**Description:** (PREG) is shifted as defined by the PM bits and added to (ACC); result in ACC. C is set if
the addition generates a carry, otherwise cleared. (PREG) is always sign-extended. APAC is a subset of the
LTA, LTD, MAC, MACD, MADS, MADD, MPYA, and SQRA instructions. TREG0, PREG, and multiply
instruction (see Table 6–7).

**Words:** 1

**Cycles — single instruction:** ROM 1, DARAM 1, SARAM 1, External 1+p.
**Cycles — RPT execution:** ROM n, DARAM n, SARAM n, External n+p.

---

## APL — AND Data Memory Value with Long Immediate / DBMR

**Ref:** §6.3, PDF pp. 200–202 / printed 6-48–6-50.

**Syntax:**
- Direct: `APL [#lk,] dma`
- Indirect: `APL [#lk,] {ind} [,ARn]`

**Operands:** 0 ≤ dma ≤ 127; lk: 16-bit constant; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcodes** (15..0):
- Direct, long immediate NOT specified: `0 1 0 1  1 0 1 0  0  dma[6:0]` — bits 15–7 = 0101 1010 0, bits 6–0 = dma.
- Indirect, long immediate NOT specified: `0 1 0 1  1 0 1 0  1  [See Section 5.2]` — bits 15–7 = 0101 1010 1, bits 6–0 = indirect-addressing field.
- Direct, long immediate specified: `0 1 0 1  1 1 1 0  0  dma[6:0]`, second word = 16-Bit Constant — bits 15–7 = 0101 1110 0, bits 6–0 = dma.
- Indirect, long immediate specified: `0 1 0 1  1 1 1 0  1  [See Section 5.2]`, second word = 16-Bit Constant — bits 15–7 = 0101 1110 1, bits 6–0 = indirect-addressing field.

**Execution:**
- Long immediate not specified: `(PC) + 1 → PC`; `(dma) AND (DBMR) → dma`.
- Long immediate specified: `(PC) + 2 → PC`; `(dma) AND lk → dma`.

**Status bits:** Affects: TC.

**Description:** If a long immediate constant is specified, it is ANDed with (dma). If not, (dma) is ANDed
with (DBMR). In both cases the result is written directly back to dma and (ACC) is unaffected. TC is set if
the result of the AND is 0, otherwise cleared. Parallel logic unit (PLU) instruction (see Table 6–6).

**Words:** 1 (long immediate not specified); 2 (long immediate specified).

**Cycles — single instruction (second operand DBMR):**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 3† | 1+p |
| External | 2+2d | 2+2d | 2+2d | 5+2d+p |

† If the operand and the code are in the same SARAM block.

**Cycles — RPT execution (second operand DBMR):**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | 2n−2 | 2n−2 | 2n−2, 2n+1† | 2n−2+p |
| External | 4n−2+2nd | 4n−2+2nd | 4n−2+2nd | 4n+1+2nd+p |

† If the operand and the code are in the same SARAM block.

**Cycles — single instruction (long immediate specified):**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | 2 | 2 | 2 | 2+2p |
| SARAM | 2 | 2 | 2 | 2+2p |
| External | 3+2d | 3+2d | 3+2d | 6+2d+2p |

**Cycles — RPT execution (long immediate specified):**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | n+1 | n+1 | n+1 | n+1+2p |
| SARAM | 2n−1 | 2n−1 | 2n−1, 2n+2† | 2n−1+2p |
| External | 4n−1+2nd | 4n−1+2nd | 4n−1+2nd | 4n+2+2nd+2p |

† If the operand and the code reside in [the] same SARAM block.

---

## B — Branch Unconditionally

**Ref:** §6.3, PDF p. 203 / printed 6-51.

**Syntax:** `B pma [, {ind} [,ARn]]`
**Operands:** 0 ≤ pma ≤ 65535; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode** (15..0): `0 1 1 1  1 0 0 1  1  [See Section 5.2]`, second word = 16-Bit Constant — bits 15–7 =
0111 1001 1, bits 6–0 = indirect-addressing field.

**Execution:**
- `pma → PC`
- Modify current AR and ARP as specified.

**Status bits:** None affected.

**Description:** Control is passed to program memory address pma. The current AR and ARP are modified
as specified. pma can be a symbolic or numeric address. Branch and call instruction (see Table 6–8).

**Words:** 2

**Cycles:** NOT repeatable. **Single instruction:** ROM 4, DARAM 4, SARAM 4, External 4+4p†.
† The 'C5x performs speculative fetching by reading two additional instruction words. If PC discontinuity
is taken, these two instruction words are discarded.

---

## BACC — Branch to Address in ACC

**Ref:** §6.3, PDF p. 204 / printed 6-52.

**Syntax:** `BACC`
**Operands:** None

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 0 1 0  0 0 0 0` — i.e. `1011 1110 0010 0000`.

**Execution:** `ACC(15–0) → PC`

**Status bits:** None affected.

**Description:** Control is passed to the 16-bit address residing in ACCL. Branch and call instruction
(see Table 6–8).

**Words:** 1

**Cycles:** NOT repeatable. **Single instruction:** ROM 4, DARAM 4, SARAM 4, External 4+3p†.
† The 'C5x performs speculative fetching by reading two additional instruction words. If PC discontinuity
is taken, these two instruction words are discarded.

---

## BACCD — Delayed Branch to Address in ACC

**Ref:** §6.3, PDF p. 205 / printed 6-53.

**Syntax:** `BACCD`
**Operands:** None

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 0 1 0  0 0 0 1` — i.e. `1011 1110 0010 0001`.

**Execution:** `ACC(15–0) → PC`

**Status bits:** None affected.

**Description:** The one 2-word instruction or two 1-word instructions following BACCD are fetched from
program memory and executed before the branch is taken. After they execute, control is passed to the
16-bit address residing in ACCL. Branch and call instruction (see Table 6–8).

**Words:** 1

**Cycles:** NOT repeatable. **Single instruction:** ROM 2, DARAM 2, SARAM 2, External 2+p.

---

## BANZ — Branch on Auxiliary Register Not Zero

**Ref:** §6.3, PDF pp. 206–207 / printed 6-54–6-55.

**Syntax:** `BANZ pma [, {ind} [,ARn]]`
**Operands:** 0 ≤ pma ≤ 65535; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode** (15..0): `0 1 1 1  1 0 1 1  1  [See Section 5.2]`, second word = 16-Bit Constant — bits 15–7 =
0111 1011 1, bits 6–0 = indirect-addressing field.

**Execution:**
- If (current AR) ≠ 0: `pma → PC`
- Else: `(PC) + 2 → PC`
- Modify current AR as specified.

**Status bits:** None affected.

**Description:** If (current AR) ≠ 0, control is passed to pma; otherwise to the next instruction. The default
modification to current AR is a decrement by 1. N loop iterations are executed by initializing the AR loop
counter to N−1 before loop entry. pma can be a symbolic or numeric address. Branch and call instruction
(see Table 6–8).

**Words:** 2

**Cycles:** NOT repeatable. **Single instruction:**

| Condition | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| True | 4 | 4 | 4 | 4+4p† |
| False | 2 | 2 | 2 | 2+2p |

† The 'C5x performs speculative fetching by reading two additional instruction words. If PC discontinuity
is taken, these two instruction words are discarded.

---

## BANZD — Delayed Branch on Auxiliary Register Not Zero

**Ref:** §6.3, PDF pp. 208–209 / printed 6-56–6-57.

**Syntax:** `BANZD pma [, {ind} [,ARn]]`
**Operands:** 0 ≤ pma ≤ 65535; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode** (15..0): `0 1 1 1  1 1 1 1  1  [See Section 5.2]`, second word = 16-Bit Constant — bits 15–7 =
0111 1111 1, bits 6–0 = indirect-addressing field.

**Execution:**
- If (current AR) ≠ 0: `pma → PC`
- Else: `(PC) + 2 → PC`
- Modify current AR as specified.

**Status bits:** None affected.

**Description:** The one 2-word instruction or two 1-word instructions following BANZD are fetched from
program memory and executed before the branch is taken. After they execute, if (current AR) ≠ 0, control
is passed to pma; otherwise to the next instruction. Default modification to current AR is a decrement by 1.
N loop iterations are executed by initializing the AR loop counter to N−1 before loop entry. pma can be a
symbolic or numeric address. Branch and call instruction (see Table 6–8).

**Words:** 2

**Cycles:** NOT repeatable. **Single instruction:** ROM 2, DARAM 2, SARAM 2, External 2+2p.

---

## BCND — Branch Conditionally

**Ref:** §6.3, PDF pp. 210–211 / printed 6-58–6-59.

**Syntax:** `BCND pma, cond [,cond1] [,...]`
**Operands:** 0 ≤ pma ≤ 65535. Conditions: ACC = 0 EQ; ACC ≠ 0 NEQ; ACC < 0 LT; ACC ≤ 0 LEQ;
ACC > 0 GT; ACC ≥ 0 GEQ; C = 0 NC; C = 1 C; OV = 0 NOV; OV = 1 OV; TC = 0 NTC; TC = 1 TC;
BIO low BIO; unconditionally UNC.

**Opcode** (15..0): `1 1 1 0  0 0  TP†  ZLVC†  ZLVC†`, second word = 16-Bit Constant — bits 15–10 = 1110 00,
bits 9–8 = TP, bits 7–4 = ZLVC, bits 3–0 = ZLVC.
† See Table 6–1 on page 6-2.

**Execution:**
- If (condition(s)): `pma → PC`
- Else: `(PC) + 2 → PC`

**Status bits:** None affected.

**Description:** If the specified conditions are met, control is passed to pma; otherwise to the next
instruction. Not all combinations of the conditions are meaningful, and testing BIO is mutually exclusive
to testing TC. Branch and call instruction (see Table 6–8).

**Words:** 2

**Cycles:** NOT repeatable. **Single instruction:**

| Condition | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| True | 4 | 4 | 4 | 4+4p† |
| False | 2 | 2 | 2 | 2+2p |

† The 'C5x performs speculative fetching by reading two additional instruction words. If PC discontinuity
is taken, these two instruction words are discarded.

---

## BCNDD — Delayed Branch Conditionally

**Ref:** §6.3, PDF pp. 212–213 / printed 6-60–6-61.

**Syntax:** `BCNDD pma, cond [,cond1] [,...]`
**Operands:** 0 ≤ pma ≤ 65535. Conditions: same list as BCND (EQ, NEQ, LT, LEQ, GT, GEQ, NC, C,
NOV, OV, NTC, TC, BIO, UNC).

**Opcode** (15..0): `1 1 1 1  0 0  TP†  ZLVC†  ZLVC†`, second word = 16-Bit Constant — bits 15–10 = 1111 00,
bits 9–8 = TP, bits 7–4 = ZLVC, bits 3–0 = ZLVC.
† See Table 6–1 on page 6-2.

**Execution:**
- If (condition(s)): `pma → PC`
- Else: `(PC) + 2 → PC`

**Status bits:** None affected.

**Description:** The one 2-word instruction or two 1-word instructions following BCNDD are fetched from
program memory and executed before the branch is taken. The two instruction words following BCNDD
have no effect on the conditions being tested. After they execute, if the specified conditions are met, control
is passed to pma; otherwise to the next instruction. Not all combinations of the conditions are meaningful,
and testing BIO is mutually exclusive to testing TC. Branch and call instruction (see Table 6–8).

**Words:** 2

**Cycles:** NOT repeatable. **Single instruction:** ROM 2, DARAM 2, SARAM 2, External 2+2p.

---

## BD — Delayed Branch Unconditionally

**Ref:** §6.3, PDF p. 214 / printed 6-62.

**Syntax:** `BD pma [, {ind} [,ARn]]`
**Operands:** 0 ≤ pma ≤ 65535; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode** (15..0): `0 1 1 1  1 1 0 1  1  [See Section 5.2]`, second word = 16-Bit Constant — bits 15–7 =
0111 1101 1, bits 6–0 = indirect-addressing field.

**Execution:**
- `pma → PC`
- Modify current AR and ARP as specified.

**Status bits:** None affected.

**Description:** The one 2-word instruction or two 1-word instructions following BD are fetched from
program memory and executed before the branch is taken. After they execute, control is passed to pma.
The current AR and ARP are modified as specified. pma can be a symbolic or numeric address. Branch
and call instruction (see Table 6–8).

**Words:** 2

**Cycles:** NOT repeatable. **Single instruction:** ROM 2, DARAM 2, SARAM 2, External 2+2p.

---

## BIT — Test Bit

**Ref:** §6.3, PDF pp. 215–216 / printed 6-63–6-64.

**Syntax:**
- Direct: `BIT dma, bit code`
- Indirect: `BIT {ind}, bit code [,ARn]`

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; 0 ≤ bit code ≤ 15; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcodes** (15..0):
- Direct: `0 1 0 0  BITX†  0  dma[6:0]` — bits 15–12 = 0100, bits 11–8 = BITX, bit 7 = 0, bits 6–0 = dma.
- Indirect: `0 1 0 0  BITX†  1  [See Section 5.2]` — bits 15–12 = 0100, bits 11–8 = BITX, bit 7 = 1, bits 6–0 = indirect-addressing field.
  † BITX: see Table 6–1 on page 6-2.

**Execution:**
- `(PC) + 1 → PC`
- `(dma bit at bit address (15 − bit code)) → TC`

**Status bits:** Affects: TC.

**Description:** The specified bit of the (dma) value is copied to the TC bit in ST1. APL, BITT, CMPR, CPL,
LST1, NORM, OPL, and XPL also affect TC. Bit-code mapping (bit code = 15 − bit number): bit 0 → 1111,
1 → 1110, 2 → 1101, 3 → 1100, 4 → 1011, 5 → 1010, 6 → 1001, 7 → 1000, 8 → 0111, 9 → 0110,
10 → 0101, 11 → 0100, 12 → 0011, 13 → 0010, 14 → 0001, 15 → 0000. Control instruction (see Table 6–10).

**Words:** 1

**Cycles — single instruction:**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

**Cycles — RPT execution:**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

---

## BITT — Test Bit Specified by TREG2

**Ref:** §6.3, PDF pp. 217–218 / printed 6-65–6-66.

**Syntax:**
- Direct: `BITT dma`
- Indirect: `BITT {ind} [,ARn]`

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcodes** (15..0):
- Direct: `0 1 1 0  1 1 1 1  0  dma[6:0]` — bits 15–7 = 0110 1111 0, bits 6–0 = dma.
- Indirect: `0 1 1 0  1 1 1 1  1  [See Section 5.2]` — bits 15–7 = 0110 1111 1, bits 6–0 = indirect-addressing field.

**Execution:**
- `(PC) + 1 → PC`
- `(dma bit at bit address (15 − TREG2(3–0))) → TC`

**Status bits:** Affects: TC.

**Description:** The specified bit of the (dma) value is copied to the TC bit in ST1. APL, BIT, CMPR, CPL,
LST1, OPL, NORM, and XPL also affect TC. The bit code in the 4 LSBs of TREG2 selects the bit, with the
same mapping as BIT (bit 0 → 1111 … bit 15 → 0000). 'C2x compatibility: clearing TRM causes any 'C2x
instruction that loads TREG0 to write to all three TREGs, so subsequent BITT calls use the TREG2 value
(same as TREG0). Control instruction (see Table 6–10).

**Words:** 1

**Cycles — single instruction:**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

**Cycles — RPT execution:**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

---

## BLDD — Block Move from Data Memory to Data Memory

**Ref:** §6.3, PDF pp. 219–224 / printed 6-67–6-72.

**Syntax:** General: `BLDD src, dst`. Valid cases:
- `BLDD BMAR, dma` / `BLDD BMAR, {ind} [,ARn]` (BMAR/DMA)
- `BLDD dma, BMAR` / `BLDD {ind}, BMAR [,ARn]` (DMA/BMAR)
- `BLDD #addr, dma` / `BLDD #addr, {ind} [,ARn]` (K/DMA)
- `BLDD dma, #addr` / `BLDD {ind}, #addr [,ARn]` (DMA/K)

**Operands:** 0 ≤ addr ≤ 65535; 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcodes** (15..0):
- Direct, SRC in BMAR: `1 0 1 0  1 1 0 0  0  dma[6:0]` — bits 15–7 = 1010 1100 0, bits 6–0 = dma.
- Indirect, SRC in BMAR: `1 0 1 0  1 1 0 0  1  [See Section 5.2]` — bits 15–7 = 1010 1100 1.
- Direct, DEST in BMAR: `1 0 1 0  1 1 0 1  0  dma[6:0]` — bits 15–7 = 1010 1101 0, bits 6–0 = dma.
- Indirect, DEST in BMAR: `1 0 1 0  1 1 0 1  1  [See Section 5.2]` — bits 15–7 = 1010 1101 1.
- Direct, SRC long immediate: `1 0 1 0  1 0 0 0  0  dma[6:0]`, second word = 16-Bit Constant — bits 15–7 = 1010 1000 0.
- Indirect, SRC long immediate: `1 0 1 0  1 0 0 0  1  [See Section 5.2]`, second word = 16-Bit Constant — bits 15–7 = 1010 1000 1.
- Direct, DEST long immediate: `1 0 1 0  1 0 0 1  0  dma[6:0]`, second word = 16-Bit Constant — bits 15–7 = 1010 1001 0.
- Indirect, DEST long immediate: `1 0 1 0  1 0 0 1  1  [See Section 5.2]`, second word = 16-Bit Constant — bits 15–7 = 1010 1001 1.
- Note: §6.2 summary (PDF p. 171) lists a single representative opcode `1010 1000 IAAA AAAA` for BLDD,
  which matches the SRC-long-immediate form above; the other seven forms are as printed in §6.3.

**Execution:**
- `(PFC) → MCS`
- If long immediate: `(PC) + 2 → PC`; `#lk → PFC`. Else: `(PC) + 1 → PC`; `(BMAR) → PFC`.
- While (repeat counter) ≠ 0: `(src, addressed by PFC) → dst` or `src → (dst, addressed by PFC)`; modify
  current AR and ARP as specified; `(PFC) + 1 → PFC`; `(repeat counter) − 1 → repeat counter`.
- Then: `(src, addressed by PFC) → dst` or `src → (dst, addressed by PFC)`; modify current AR and ARP
  as specified; `(MCS) → PFC`.

**Status bits:** None affected.

**Description:** (dma) pointed at by src is copied to the dma pointed at by dst. Source and/or destination
can be pointed at by a long immediate value, (BMAR), or a dma. Not all src/dst combinations of pointer
types are valid. Source and destination blocks do not have to be entirely on-chip or off-chip. In indirect
addressing mode, RPT can be used with BLDD to move consecutive words in data memory; the number of
words moved is one greater than the number in RPTC at the beginning of the instruction. If a long immediate
value or (BMAR) is specified in repeat mode, the source and/or destination address is automatically
incremented. If a dma is specified in repeat mode, the dma address is NOT automatically incremented. With
RPT, BLDD becomes a single-cycle instruction once the RPT pipeline is started. Interrupts are inhibited
during a BLDD operation used with RPT. Neither the long immediate value nor the BMAR can be used as the
address to the on-chip memory-mapped registers; direct or indirect addressing can be used as the address
to the on-chip memory-mapped registers. I/O and data memory operation instruction (see Table 6–9).

**Words:** 1 (one source or destination specified by BMAR); 2 (one source or destination specified by long immediate).

**Cycles — single instruction (SRC or DEST in BMAR):**

| Source → Destination | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM → DARAM | 2 | 2 | 2 | 2+p |
| SARAM → DARAM | 2 | 2 | 2 | 2+p |
| External → DARAM | 2+dsrc | 2+dsrc | 2+dsrc | 2+dsrc+p |
| DARAM → SARAM | 2 | 2 | 2, 3† | 2+p |
| SARAM → SARAM | 2 | 2 | 2, 3† | 2+p |
| External → SARAM | 2+dsrc | 2+dsrc | 2+dsrc, 3+dsrc† | 2+dsrc+p |
| DARAM → External | 3+ddst | 3+ddst | 3+ddst | 5+ddst+p |
| SARAM → External | 3+ddst | 3+ddst | 3+ddst | 5+ddst+p |
| External → External | 3+dsrc+ddst | 3+dsrc+ddst | 3+dsrc+ddst | 5+dsrc+ddst+p |

† If the destination operand and the code are in the same SARAM block.

**Cycles — RPT execution (SRC or DEST in BMAR):**

| Source → Destination | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM → DARAM | n+1 | n+1 | n+1 | n+1+p |
| SARAM → DARAM | n+1 | n+1 | n+1 | n+1+p |
| External → DARAM | n+1+ndsrc | n+1+ndsrc | n+1+ndsrc | n+1+ndsrc+p |
| DARAM → SARAM | n+1 | n+1 | n+1, n+3† | n+1+p |
| SARAM → SARAM | n+1, 2n−1‡ | n+1, 2n−1‡ | n+1, 2n−1‡, n+3§, 2n+1§ | n+1+p, 2n−1+p‡ |
| External → SARAM | n+1+ndsrc† | n+1+ndsrc | n+1+ndsrc, n+3+ndsrc† | n+1+ndsrc+p |
| DARAM → External | 2n+1+nddst | 2n+1+nddst | 2n+1+nddst | 2n+1+nddst+p |
| SARAM → External | 2n+1+nddst | 2n+1+nddst | 2n+1+nddst | 2n+1+nddst+p |
| External → External | 4n−1+ndsrc+nddst | 4n−1+ndsrc+nddst | 4n−1+ndsrc+nddst | 4n+1+ndsrc+nddst+p |

† If the destination operand and the code are in the same SARAM block. ‡ If both the source and the
destination operands are in the same SARAM block. § If both operands and the code are in the same SARAM block.

**Cycles — single instruction (SRC or DEST long immediate):**

| Source → Destination | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM → DARAM | 3 | 3 | 3 | 3+2p |
| SARAM → DARAM | 3 | 3 | 3 | 3+2p |
| External → DARAM | 3+dsrc | 3+dsrc | 3+dsrc | 3+dsrc+2p |
| DARAM → SARAM | 3 | 3 | 3, 4† | 3+2p |
| SARAM → SARAM | 3 | 3 | 3, 4† | 3+2p |
| External → SARAM | 3+dsrc | 3+dsrc | 3+dsrc, 4+dsrc† | 3+dsrc+2p |
| DARAM → External | 4+ddst | 4+ddst | 4+ddst | 6+ddst+2p |
| SARAM → External | 4+ddst | 4+ddst | 4+ddst | 6+ddst+2p |
| External → External | 4+dsrc+ddst | 4+dsrc+ddst | 4+dsrc+ddst | 6+dsrc+ddst+2p |

† If the destination operand and the code are in the same SARAM block.

**Cycles — RPT execution (SRC or DEST long immediate):**

| Source → Destination | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM → DARAM | n+2 | n+2 | n+2 | n+2+2p |
| SARAM → DARAM | n+2 | n+2 | n+2 | n+2+2p |
| External → DARAM | n+2+ndsrc | n+2+ndsrc | n+2+ndsrc | n+2+ndsrc+2p |
| DARAM → SARAM | n+2 | n+2 | n+2, n+4† | n+2+2p |
| SARAM → SARAM | n+2, 2n‡ | n+2, 2n‡ | n+2, 2n‡, n+4†, 2n+2§ | n+2+2p, 2n+2p‡ |
| External → SARAM | n+2+ndsrc | n+2+ndsrc | n+2+ndsrc, n+4+ndsrc† | n+2+ndsrc+2p |
| DARAM → External | 2n+2+nddst | 2n+2+nddst | 2n+2+nddst | 2n+2+nddst+2p |
| SARAM → External | 2n+2+nddst | 2n+2+nddst | 2n+2+nddst | 2n+2+nddst+2p |
| External → External | 4n+ndsrc+nddst‡ | 4n+ndsrc+nddst | 4n+ndsrc+nddst | 4n+2+ndsrc+nddst+2p |

† If the destination operand and the code are in the same SARAM block. ‡ If both the source and the
destination operands are in the same SARAM block. § If both operands and the code are in the same SARAM block.
[INFERENCE — layout: the DARAM → DARAM row of this RPT table (n+2, n+2, n+2, n+2+2p) is printed at the
foot of the preceding single-instruction (long immediate) table on PDF p. 223 / printed 6-71, immediately
before the RPT table heading, which as printed otherwise starts with the SARAM → DARAM row. The row is
placed here because its values belong to the RPT table; the single-instruction table as printed would
otherwise contain an `n`-valued row.]

---

## BLDP — Block Move from Data Memory to Program Memory

**Ref:** §6.3, PDF pp. 225–227 / printed 6-73–6-75.

**Syntax:**
- Direct: `BLDP dma`
- Indirect: `BLDP {ind} [,ARn]`

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcodes** (15..0):
- Direct: `0 1 0 1  0 1 1 1  0  dma[6:0]` — bits 15–7 = 0101 0111 0, bits 6–0 = dma.
- Indirect: `0 1 0 1  0 1 1 1  1  [See Section 5.2]` — bits 15–7 = 0101 0111 1, bits 6–0 = indirect-addressing field.

**Execution:**
- `(PC) + 1 → PC`; `(PFC) → MCS`; `(BMAR) → PFC`.
- While (repeat counter) ≠ 0: `dma → (dst, addressed by PFC)`; modify current AR and ARP as specified;
  `(PFC) + 1 → PFC`; `(repeat counter) − 1 → repeat counter`.
- Then: `dma → (dst, addressed by PFC)`; modify current AR and ARP as specified; `(MCS) → PFC`.

**Status bits:** None affected.

**Description:** (dma) is copied to the program memory address (pma) pointed at by BMAR. Source and
destination blocks do not have to be entirely on-chip or off-chip. In indirect addressing mode, RPT can be
used with BLDP to move consecutive words in data memory to a contiguous program memory space pointed
at by BMAR; the number of words moved is one greater than the number in RPTC at the beginning of the
instruction. (BMAR) is automatically incremented in repeat mode. With RPT, BLDP becomes a single-cycle
instruction once the RPT pipeline is started. Interrupts are inhibited during a BLDP operation used with RPT.
I/O and data memory operation instruction (see Table 6–9).

**Words:** 1

**Cycles — single instruction** (columns ROM/DARAM/SARAM/External; pcode = program wait states of
the code location, pdst = program wait states of the destination, dsrc = data wait states of the source):

| Source → Destination | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM → DARAM | 2 | 2 | 2 | 2+p |
| SARAM → DARAM | 2 | 2, 3¶ | 2 | 2+p |
| External → DARAM | 2+dsrc | 2+dsrc | 2+dsrc | 3+dsrc+pcode |
| DARAM → SARAM | 2 | 2 | 2, 3† | 2+p |
| SARAM → SARAM | 2 | 2 | 2, 3†¶, 4§ | 2+p |
| External → SARAM | 2+dsrc | 2+dsrc | 2+dsrc, 3+dsrc† | 3+dsrc+pcode |
| DARAM → External | 3+pdst | 3+pdst | 3+pdst | 4+pdst+pcode |
| SARAM → External | 3+pdst | 3+pdst | 3+pdst, 4+pdst¶ | 4+pdst+pcode |
| External → External | 3+dsrc+pdst | 3+dsrc+pdst | 3+dsrc+pdst | 5+dsrc+pdst+pcode |

† If the destination operand and the code are in the same SARAM block. § If both operands and the code
are in the same SARAM block. ¶ If the source operand and the code are in the same SARAM block.

**Cycles — RPT execution:**

| Source → Destination | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM → DARAM | n+1 | n+1 | n+1 | n+1+pcode |
| SARAM → DARAM | n+1 | n+1 | n+1, n+2¶ | n+1+pcode |
| External → DARAM | n+1+ndsrc | n+1+ndsrc | n+1+ndsrc | n+2+ndsrc+pcode |
| DARAM → SARAM | n+1 | n+1 | n+1, n+2† | n+1+pcode |
| SARAM → SARAM | n+1, 2n−1‡ | n+1, 2n−1‡ | n+1, 2n−1‡, n+2†¶, 2n+1§ | n+1+pcode, 2n−1+pcode‡ |
| External → SARAM | n+1+ndsrc | n+1+ndsrc | n+1+ndsrc, n+2+npsrc† | n+2+ndsrc+pcode |
| DARAM → External | 2n+1+npdst | 2n+1+npdst | 2n+1+npdst | 2n+2+npdst+pcode |
| SARAM → External | 2n+1+npdst | 2n+1+npdst | 2n+1+npdst, 2n+2+npdst¶ | 2n+2+npdst+pcode |
| External → External | 4n−1+ndsrc+npdst | 4n−1+ndsrc+npdst | 4n−1+ndsrc+npdst | 4n+1+ndsrc+npdst+pcode |

† If the destination operand and the code are in the same SARAM block. ‡ If both the source and the
destination operands are in the same SARAM block. § If both operands and the code are in the same SARAM
block. ¶ If the source operand and the code are in the same SARAM block. (In the RPT tables the manual
uses `npsrc`/`npdst` for the repeated-access program wait-state terms; in the single-instruction table it
uses `pcode`/`pdst`.)

---

## BLPD — Block Move from Program Memory to Data Memory

**Ref:** §6.3, PDF pp. 228–233 / printed 6-76–6-81.

**Syntax:** General: `BLPD src, dst`. Valid cases:
- `BLPD BMAR, dma` / `BLPD BMAR, {ind} [,ARn]` (BMAR/DMA)
- `BLPD #pma, dma` / `BLPD #pma, {ind} [,ARn]` (K/DMA)

**Operands:** 0 ≤ pma ≤ 65535; 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcodes** (15..0):
- Direct, SRC in BMAR: `1 0 1 0  0 1 0 0  0  dma[6:0]` — bits 15–7 = 1010 0100 0, bits 6–0 = dma.
- Indirect, SRC in BMAR: `1 0 1 0  0 1 0 0  1  [See Section 5.2]` — bits 15–7 = 1010 0100 1.
- Direct, SRC long immediate: `1 0 1 0  0 1 0 1  0  dma[6:0]`, second word = 16-Bit Constant — bits 15–7 = 1010 0101 0.
- Indirect, SRC long immediate: `1 0 1 0  0 1 0 1  1  [See Section 5.2]`, second word = 16-Bit Constant — bits 15–7 = 1010 0101 1.

**Execution:**
- If long immediate: `(PC) + 2 → PC`; `(PFC) → MCS`; `lk → PFC`. Else: `(PC) + 1 → PC`; `(PFC) → MCS`; `(BMAR) → PFC`.
- While (repeat counter) ≠ 0: `(pma, addressed by PFC) → dst`; modify current AR and ARP as specified;
  `(PFC) + 1 → PFC`; `(repeat counter) − 1 → repeat counter`.
- Then: `(pma, addressed by PFC) → dst`; modify current AR and ARP as specified; `(MCS) → PFC`.

**Status bits:** None affected.

**Description:** (pma) pointed at by src is copied to the (dma) pointed at by dst. Source can be pointed at
by a long immediate value or (BMAR); destination by a dma or (current AR). Not all src/dst combinations of
pointer types are valid. Source and destination blocks do not have to be entirely on-chip or off-chip. In
indirect addressing mode, RPT can be used with BLPD to move consecutive words in program memory to data
memory; the number of words moved is one greater than the number in RPTC at the beginning of the
instruction. If a long immediate value or (BMAR) is specified in repeat mode, the source address is
automatically incremented. With RPT, BLPD becomes a single-cycle instruction once the RPT pipeline is
started. Interrupts are inhibited during a BLPD operation used with RPT. I/O and data memory operation
instruction (see Table 6–9).

**Words:** 1 (source specified by BMAR); 2 (source specified by long immediate).

**Cycles — single instruction (SRC in BMAR):**

| Source → Destination | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM/ROM → DARAM | 2 | 2 | 2 | 2+pcode |
| SARAM → DARAM | 2 | 2 | 2 | 2+pcode |
| External → DARAM | 2+psrc | 2+psrc | 2+psrc | 2+psrc+pcode |
| DARAM/ROM → SARAM | 2 | 2 | 2, 3† | 2+pcode |
| SARAM → SARAM | 2 | 2 | 2, 3† | 2+pcode |
| External → SARAM | 2+psrc | 2+psrc | 2+psrc, 3+psrc† | 2+psrc+2pcode |
| DARAM/ROM → External | 3+ddst | 3+ddst | 3+ddst | 5+ddst+pcode |
| SARAM → External | 3+ddst | 3+ddst | 3+ddst | 5+ddst+pcode |
| External → External | 3+psrc+ddst | 3+psrc+ddst | 3+psrc+ddst | 5+psrc+ddst+pcode |

† If the destination operand and the code are in the same SARAM block.

**Cycles — RPT execution (SRC in BMAR):**

| Source → Destination | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM/ROM → DARAM | n+1 | n+1 | n+1 | n+1+pcode |
| SARAM → DARAM | n+1 | n+1 | n+1 | n+1+pcode |
| External → DARAM | n+1+npsrc | n+1+npsrc | n+1+npsrc | n+1+npsrc+pcode |
| DARAM/ROM → SARAM | n+1 | n+1 | n+1, n+3† | n+1+pcode |
| SARAM → SARAM | n+1, 2n−1‡ | n+1, 2n−1‡ | n+1, 2n−1‡, n+3†, 2n+1§ | n+1+pcode, 2n−1+pcode‡ |
| External → SARAM | n+1+npsrc | n+1+npsrc | n+1+npsrc, n+3+npsrc† | n+1+npsrc+pcode |
| DARAM/ROM → External | 2n+1+nddst | 2n+1+nddst | 2n+1+nddst | 2n+1+nddst+pcode |
| SARAM → External | 2n+1+nddst | 2n+1+nddst | 2n+1+nddst | 2n+1+nddst+pcode |
| External → External | 4n−1+npsrc+nddst | 4n−1+npsrc+nddst | 4n−1+npsrc+nddst | 4n+1+npsrc+nddst+pcode |

† If the destination operand and the code are in the same SARAM block. ‡ If both the source and the
destination operands are in the same SARAM block. § If both operands and the code are in the same SARAM block.

**Cycles — single instruction (SRC long immediate):**

| Source → Destination | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM/ROM → DARAM | 3 | 3 | 3 | 3+2pcode |
| SARAM → DARAM | 3 | 3 | 3 | 3+2pcode |
| External → DARAM | 3+psrc | 3+psrc | 3+psrc | 3+psrc+2pcode |
| DARAM/ROM → SARAM | 3 | 3 | 3, 4† | 3+2pcode |
| SARAM → SARAM | 3 | 3 | 3, 4† | 3+2pcode |
| External → SARAM | 3+psrc | 3+psrc | 3+psrc, 4+psrc† | 3+psrc+2pcode |
| DARAM/ROM → External | 4+ddst | 4+ddst | 4+ddst | 6+ddst+2pcode |
| SARAM → External | 4+ddst | 4+ddst | 4+ddst | 6+ddst+2pcode |
| External → External | 4+psrc+ddst | 4+psrc+ddst | 4+psrc+ddst | 6+psrc+ddst+2pcode |

† If the destination operand and the code are in the same SARAM block.

**Cycles — RPT execution (SRC long immediate):**

| Source → Destination | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM/ROM → DARAM | n+2 | n+2 | n+2 | n+2+2pcode |
| SARAM → DARAM | n+2 | n+2 | n+2 | n+2+2pcode |
| External → DARAM | n+2+npsrc | n+2+npsrc | n+2+npsrc | n+2+npsrc+2pcode |
| DARAM/ROM → SARAM | n+2 | n+2 | n+2, n+4† | n+2+2pcode |
| SARAM → SARAM | n+2, 2n‡ | n+2, 2n‡ | n+2, 2n‡, n+4†, 2n+2§ | n+2+2pcode, 2n+2pcode‡ |
| External → SARAM | n+2+npsrc† | n+2+npsrc | n+2+npsrc, n+4+npsrc† | n+2+npsrc+2pcode |
| DARAM/ROM → External | 2n+2+nddst | 2n+2+nddst | 2n+2+nddst | 2n+2+nddst+2pcode |
| SARAM → External | 2n+2+nddst | 2n+2+nddst | 2n+2+nddst | 2n+2+nddst+2pcode |
| External → External | 4n+npsrc+nddst† | 4n+npsrc+nddst | 4n+npsrc+nddst | 4n+2+npsrc+nddst+2pcode |

† If the destination operand and the code are in the same SARAM block. ‡ If both the source and the
destination operands are in the same SARAM block. § If both operands and the code are in the same SARAM block.

---

## BSAR — Barrel-Shift ACC Right

**Ref:** §6.3, PDF p. 234 / printed 6-82.

**Syntax:** `BSAR shift`
**Operands:** 1 ≤ shift ≤ 16

**Opcode** (15..0): `1 0 1 1  1 1 1 1  1 1 1 0  SHFT†` — bits 15–4 = 1011 1111 1110, bits 3–0 = SHFT.
† See Table 6–1 on page 6-2.

**Execution:**
- `(PC) + 1 → PC`
- `(ACC) / 2^shift → ACC`

**Status bits:** Affected by: SXM.

**Description:** (ACC) is right-barrel arithmetic shifted 1 to 16 bits, as defined by the shift code, in a
single cycle. If SXM = 0, the high-order bits of ACC are zero-filled; if SXM = 1, they are sign-extended.
Accumulator memory reference instruction (see Table 6–4).

**Words:** 1

**Cycles — single instruction:** ROM 1, DARAM 1, SARAM 1, External 1+p.
**Cycles — RPT execution:** ROM n, DARAM n, SARAM n, External n+p.

---

## CALA — Call Subroutine Addressed by ACC

**Ref:** §6.3, PDF p. 235 / printed 6-83.

**Syntax:** `CALA`
**Operands:** None

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 0 1 1  0 0 0 0` — i.e. `1011 1110 0011 0000` (0xBE30).

**Execution:**
- `(PC) + 1 → TOS`
- `(ACC(15–0)) → PC`

**Status bits:** None affected.

**Description:** The current PC is incremented and pushed onto TOS. (ACCL) is loaded into PC; execution
continues at this address. Used to perform computed subroutine calls. Branch and call instruction
(see Table 6–8).

**Words:** 1

**Cycles:** NOT repeatable. **Single instruction:** ROM 4, DARAM 4, SARAM 4, External 4+3p†.
† The 'C5x performs speculative fetching by reading two additional instruction words. If PC discontinuity
is taken, these two instruction words are discarded.

---

## CALAD — Delayed Call Subroutine Addressed by ACC

**Ref:** §6.3, PDF p. 236 / printed 6-84.

**Syntax:** `CALAD`
**Operands:** None

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 0 1 1  1 1 0 1` — i.e. `1011 1110 0011 1101` (0xBE3D).

**Execution:**
- `(PC) + 3 → TOS`
- `(ACC(15–0)) → PC`

**Status bits:** None affected.

**Description:** The current PC is incremented by 3 and pushed onto TOS. Then the one 2-word instruction
or two 1-word instructions following CALAD are fetched from program memory and executed before the call
is executed. Then (ACCL) is loaded into PC; execution continues at this address. Used to perform computed
subroutine calls. Branch and call instruction (see Table 6–8).

**Words:** 1

**Cycles:** NOT repeatable. **Single instruction:** ROM 2, DARAM 2, SARAM 2, External 2+p.

**Cross-check note:** §6.2 summary (PDF p. 170) agrees: `1011 1110 0011 1101` (0xBE3D). The c5x core
audit's reference to CALAD as 0xBE31 does not match the manual — 0xBE31 (`1011 1110 0011 0001`) is not
the CALAD opcode in SPRU056D.

---

## CALL — Call Subroutine Unconditionally

**Ref:** §6.3, PDF p. 237 / printed 6-85.

**Syntax:** `CALL pma [,{ind} [,ARn]]`
**Operands:** 0 ≤ pma ≤ 65535; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode** (15..0): `0 1 1 1  1 0 1 0  1  [See Section 5.2]`, second word = 16-Bit Constant — bits 15–7 =
0111 1010 1, bits 6–0 = indirect-addressing field.

**Execution:**
- `(PC) + 2 → TOS`
- `pma → PC`
- Modify current AR and ARP as specified.

**Status bits:** None affected.

**Description:** The current PC is incremented and pushed onto TOS. pma is loaded into PC; execution
continues at this address. The current AR and ARP are modified as specified. pma can be a symbolic or
numeric address. Branch and call instruction (see Table 6–8).

**Words:** 2

**Cycles:** NOT repeatable. **Single instruction:** ROM 4, DARAM 4, SARAM 4, External 4+4p†.
† The 'C5x performs speculative fetching by reading two additional instruction words. If PC discontinuity
is taken, these two instruction words are discarded.

---

## CALLD — Delayed Call Subroutine Unconditionally

**Ref:** §6.3, PDF pp. 238–239 / printed 6-86–6-87.

**Syntax:** `CALLD pma [,{ind} [,ARn]]`
**Operands:** 0 ≤ pma ≤ 65535; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcode** (15..0): `0 1 1 1  1 1 1 0  1  [See Section 5.2]`, second word = 16-Bit Constant — bits 15–7 =
0111 1110 1, bits 6–0 = indirect-addressing field.

**Execution:**
- `(PC) + 4 → TOS`
- `pma → PC`
- Modify current AR and ARP as specified.

**Status bits:** None affected.

**Description:** The current PC is incremented by 4 and pushed onto TOS. Then the one 2-word instruction
or two 1-word instructions following CALLD are fetched from program memory and executed before the call
is executed. Then pma is loaded into PC; execution continues at this address. The current AR and ARP are
modified as specified. pma can be a symbolic or numeric address. Branch and call instruction (see Table 6–8).

**Words:** 2

**Cycles:** NOT repeatable. **Single instruction:** ROM 2, DARAM 2, SARAM 2, External 2+2p.

---

## CC — Call Subroutine Conditionally

**Ref:** §6.3, PDF pp. 240–241 / printed 6-88–6-89.

**Syntax:** `CC pma cond [,cond1] [,...]`
**Operands:** 0 ≤ pma ≤ 65535. Conditions: same list as BCND (EQ, NEQ, LT, LEQ, GT, GEQ, NC, C,
NOV, OV, NTC, TC, BIO, UNC).

**Opcode** (15..0): `1 1 1 0  1 0  TP†  ZLVC†  ZLVC†`, second word = 16-Bit Constant — bits 15–10 = 1110 10,
bits 9–8 = TP, bits 7–4 = ZLVC, bits 3–0 = ZLVC.
† See Table 6–1 on page 6-2.

**Execution:**
- If (condition(s)): `(PC) + 2 → TOS`; `pma → PC`
- Else: `(PC) + 2 → PC`

**Status bits:** None affected.

**Description:** If the specified conditions are met, the current PC is incremented and pushed onto TOS;
pma is loaded into PC; execution continues at this address. pma can be a symbolic or numeric address. Not
all combinations of the conditions are meaningful; in addition, the NTC, TC, and BIO conditions are mutually
exclusive. If the conditions are not met, control is passed to the next instruction. CC functions in the same
manner as CALL if all conditions are true. Branch and call instruction (see Table 6–8).

**Words:** 2

**Cycles:** NOT repeatable. **Single instruction:**

| Condition | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| True | 4 | 4 | 4 | 4+4p† |
| False | 2 | 2 | 2 | 2+2p |

† The 'C5x performs speculative fetching by reading two additional instruction words. If PC discontinuity
is taken, these two instruction words are discarded.

---

## CCD — Delayed Call Subroutine Conditionally

**Ref:** §6.3, PDF pp. 242–243 / printed 6-90–6-91.

**Syntax:** `CCD pma cond [,cond1] [,...]`
**Operands:** 0 ≤ pma ≤ 65535. Conditions: same list as BCND (EQ, NEQ, LT, LEQ, GT, GEQ, NC, C,
NOV, OV, NTC, TC, BIO, UNC).

**Opcode** (15..0): `1 1 1 1  1 0  TP†  ZLVC†  ZLVC†`, second word = 16-Bit Constant — bits 15–10 = 1111 10,
bits 9–8 = TP, bits 7–4 = ZLVC, bits 3–0 = ZLVC.
† See Table 6–1 on page 6-2.

**Execution:**
- If (condition(s)): `(PC) + 4 → TOS`; `pma → PC`
- Else: `(PC) + 2 → PC`

**Status bits:** None affected.

**Description:** If the specified conditions are met, the current PC is incremented by 4 and pushed onto
TOS. Then the one 2-word instruction or two 1-word instructions following CCD are fetched from program
memory and executed before the call is executed. Then pma is loaded into PC; execution continues at this
address. pma can be a symbolic or numeric address. Not all combinations of the conditions are meaningful;
in addition, the NTC, TC, and BIO conditions are mutually exclusive. If the conditions are not met, control is
passed to the next instruction. CCD functions in the same manner as CALLD if all conditions are true.
Branch and call instruction (see Table 6–8).

**Words:** 2

**Cycles:** NOT repeatable. **Single instruction:** ROM 2, DARAM 2, SARAM 2, External 2+2p.

---

## CLRC — Clear Control Bit

**Ref:** §6.3, PDF pp. 244–245 / printed 6-92–6-93.

**Syntax:** `CLRC control bit`
**Operands:** control bit: {C, CNF, HM, INTM, OVM, SXM, TC, XF}

**Opcodes** (15..0) — all share bits 15–8 = `1011 1110`, bits 7–4 = `0100`:
- CLRC OVM (clear overflow mode): `1011 1110 0100 0010` (0xBE42)
- CLRC SXM (clear sign-extension mode): `1011 1110 0100 0110` (0xBE46)
- CLRC HM (clear hold mode): `1011 1110 0100 1000` (0xBE48)
- CLRC TC (clear test/control): `1011 1110 0100 1010` (0xBE4A)
- CLRC C (clear carry): `1011 1110 0100 1110` (0xBE4E)
- CLRC CNF (clear configuration control): `1011 1110 0100 0100` (0xBE44)
- CLRC INTM (clear interrupt mode): `1011 1110 0100 0000` (0xBE40)
- CLRC XF (clear external flag pin): `1011 1110 0100 1100` (0xBE4C)

**Execution:**
- `(PC) + 1 → PC`
- `0 → control bit`

**Status bits:** Affects selected control bit.

**Description:** The specified control bit is cleared. The LST instruction can also be used to load ST0 and
ST1. See Section 4.4, Status and Control Registers, for more information on each control bit. Control
instruction (see Table 6–10).

**Words:** 1

**Cycles — single instruction:** ROM 1, DARAM 1, SARAM 1, External 1+p.
**Cycles — RPT execution:** ROM n, DARAM n, SARAM n, External n+p.

---

## CMPL — 1s Complement ACC

**Ref:** §6.3, PDF p. 246 / printed 6-94.

**Syntax:** `CMPL`
**Operands:** None

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 0 0 0  0 0 0 1` — i.e. `1011 1110 0000 0001` (0xBE01).

**Execution:**
- `(PC) + 1 → PC`
- `(ACC) → ACC` [manual prints the execution as logical inversion of ACC; see Description]

**Status bits:** Does not affect: C.

**Description:** (ACC) is replaced with its logical inversion (1s complement). Accumulator memory reference
instruction (see Table 6–4).

**Words:** 1

**Cycles — single instruction:** ROM 1, DARAM 1, SARAM 1, External 1+p.
**Cycles — RPT execution:** ROM n, DARAM n, SARAM n, External n+p.

---

## CMPR — Compare Auxiliary Register with ARCR

**Ref:** §6.3, PDF pp. 247–248 / printed 6-95–6-96.

**Syntax:** `CMPR CM`
**Operands:** 0 ≤ CM ≤ 3

**Opcode** (15..0): `1 0 1 1  1 1 1 1  0 1 0 0  0 1  CM†` — bits 15–2 = 1011 1111 0100 01, bits 1–0 = CM.
† See Table 6–1 on page 6-2.

**Execution:**
- `(PC) + 1 → PC`
- Compare (current AR) to (ARCR).
- If condition true: `1 → TC`. If condition false: `0 → TC`.

**Status bits:** Affected by: NDX. Not affected by: SXM. Affects: TC. Does not affect: SXM.

**Description:** (current AR) is compared with (ARCR), as defined by CM: CM = 00 tests (current AR) =
(ARCR); CM = 01 tests (current AR) < (ARCR); CM = 10 tests (current AR) > (ARCR); CM = 11 tests
(current AR) ≠ (ARCR). If the condition is true, TC is set; if false, TC is cleared. The ARs are treated as
unsigned integers in the comparisons. 'C2x compatibility: clearing NDX causes any 'C2x instruction that
loads AR0 to load the ARCR and index register (INDX) also. Auxiliary registers and data memory page
pointer instruction (see Table 6–5).

**Words:** 1

**Cycles — single instruction:** ROM 1, DARAM 1, SARAM 1, External 1+p.
**Cycles — RPT execution:** ROM n, DARAM n, SARAM n, External n+p.

---

## CPL — Compare Data Memory Value with Long Immediate / DBMR

**Ref:** §6.3, PDF pp. 249–251 / printed 6-97–6-99.

**Syntax:**
- Direct: `CPL [,#lk] dma`
- Indirect: `CPL [,#lk] {ind} [,ARn]`

**Operands:** 0 ≤ dma ≤ 127; lk: 16-bit constant; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcodes** (15..0):
- Direct, long immediate NOT specified: `0 1 0 1  1 0 1 1  0  dma[6:0]` — bits 15–7 = 0101 1011 0, bits 6–0 = dma.
- Indirect, long immediate NOT specified: `0 1 0 1  1 0 1 1  1  [See Section 5.2]` — bits 15–7 = 0101 1011 1.
- Direct, long immediate specified: `0 1 0 1  1 1 1 1  0  dma[6:0]`, second word = 16-Bit Constant — bits 15–7 = 0101 1111 0.
- Indirect, long immediate specified: `0 1 0 1  1 1 1 1  1  [See Section 5.2]`, second word = 16-Bit Constant — bits 15–7 = 0101 1111 1.

**Execution:**
- Long immediate not specified: `(PC) + 1 → PC`; compare (DBMR) to (dma); if (DBMR) = (dma): `1 → TC`, else `0 → TC`.
- Long immediate specified: `(PC) + 2 → PC`; compare lk to (dma); if lk = (dma): `1 → TC`, else `0 → TC`.

**Status bits:** Not affected by: SXM. Affects: TC.

**Description:** If a long immediate constant is specified, it is compared with (dma). If not, (dma) is
compared with (DBMR). If the two quantities are equal, TC is set; otherwise TC is cleared. Parallel logic
unit (PLU) instruction (see Table 6–6).

**Words:** 1 (long immediate not specified); 2 (long immediate specified).

**Cycles — single instruction (long immediate not specified):**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

**Cycles — RPT execution (long immediate not specified):**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

**Cycles — single instruction (long immediate specified):**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | 2 | 2 | 2 | 2+2p |
| SARAM | 2 | 2 | 2, 3† | 2+2p |
| External | 2+d | 2+d | 2+d | 3+d+2p |

† If the operand and the code are in the same SARAM block.

**Cycles — RPT execution (long immediate specified):**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | n+1 | n+1 | n+1 | n+1+2p |
| SARAM | n+1 | n+1 | n+1, n+2† | n+1+2p |
| External | n+1 | n+1 | n+1 | n+2+2p |

† If the operand and the code are in the same SARAM block.

---

## CRGT — Store ACC in ACCB if ACC Greater Than ACCB

**Ref:** §6.3, PDF pp. 252–253 / printed 6-100–6-101.

**Syntax:** `CRGT`
**Operands:** None

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 0 0 1  1 0 1 1` — i.e. `1011 1110 0001 1011` (0xBE1B).

**Execution:**
- `(PC) + 1 → PC`
- Compare (ACC) to (ACCB).
- If (ACC) > (ACCB): `(ACC) → ACCB`; `1 → C`.
- If (ACC) < (ACCB): `(ACCB) → ACC`; `0 → C`.
- If (ACC) = (ACCB): `1 → C`.

**Status bits:** Affects: C.

**Description:** (ACC) is compared to (ACCB). The larger (signed) value is loaded into both registers. If
(ACC) ≥ (ACCB), C is set; otherwise C is cleared. Accumulator memory reference instruction (see Table 6–4).

**Words:** 1

**Cycles — single instruction:** ROM 1, DARAM 1, SARAM 1, External 1+p.
**Cycles — RPT execution:** ROM n, DARAM n, SARAM n, External n+p.

---

## CRLT — Store ACC in ACCB if ACC Less Than ACCB

**Ref:** §6.3, PDF pp. 254–255 / printed 6-102–6-103.

**Syntax:** `CRLT`
**Operands:** None

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 0 0 1  1 1 0 0` — i.e. `1011 1110 0001 1100` (0xBE1C).

**Execution:**
- `(PC) + 1 → PC`
- Compare (ACC) to (ACCB).
- If (ACC) < (ACCB): `(ACC) → ACCB`; `1 → C`.
- If (ACC) > (ACCB): `(ACCB) → ACC`; `0 → C`.
- If (ACC) = (ACCB): `0 → C`.

**Status bits:** Affects: C.

**Description:** (ACC) is compared to (ACCB). The smaller (signed) value is loaded into both registers. If
(ACC) < (ACCB), C is set; otherwise C is cleared. Accumulator memory reference instruction (see Table 6–4).

**Words:** 1

**Cycles — single instruction:** ROM 1, DARAM 1, SARAM 1, External 1+p.
**Cycles — RPT execution:** ROM n, DARAM n, SARAM n, External n+p.

---

## DMOV — Move Data in Data Memory (z⁻¹ Delay)

**Ref:** §6.3, PDF pp. 256–257 / printed 6-104–6-105.

**Syntax:**
- Direct: `DMOV dma`
- Indirect: `DMOV {ind} [,ARn]`

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcodes** (15..0):
- Direct: `0 1 1 1  0 1 1 1  0  dma[6:0]` — bits 15–7 = 0111 0111 0, bits 6–0 = dma.
- Indirect: `0 1 1 1  0 1 1 1  1  [See Section 5.2]` — bits 15–7 = 0111 0111 1, bits 6–0 = indirect-addressing field.

**Execution:**
- `(PC) + 1 → PC`
- `(dma) → dma + 1`

**Status bits:** Affected by: CNF and OVLY.

**Description:** (dma) is copied to the next higher dma. DMOV works only within on-chip data RAM blocks
and within any configurable RAM block configured as data memory. It is continuous across on-chip
dual-access RAM block B0 and B1 boundaries. DMOV cannot be used on external data memory or
memory-mapped registers; if used there, it reads the specified memory location but performs no operation.
When data is copied, the contents of the addressed location remain unaffected. DMOV implements the z⁻¹
delay used in digital signal processing; the DMOV function is included in the LTD, MACD, and MADD
instructions. I/O and data memory operation instruction (see Table 6–9).

**Words:** 1

**Cycles — single instruction:**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 3† | 1+p |
| External | 2+2d | 2+2d | 2+2d | 5+2d+p |

† If the operand and the code are in the same SARAM block.

**Cycles — RPT execution:**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | 2n−2 | 2n−2 | 2n−2, 2n+1† | 2n−2+p |
| External | 4n−2+2nd | 4n−2+2nd | 4n−2+2nd | 4n+1+2nd+p |

† If the operand and the code are in the same SARAM block.

---

## EXAR — Exchange ACCB with ACC

**Ref:** §6.3, PDF p. 258 / printed 6-106.

**Syntax:** `EXAR`
**Operands:** None

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 0 0 1  1 1 0 1` — i.e. `1011 1110 0001 1101` (0xBE1D).

**Execution:**
- `(PC) + 1 → PC`
- `(ACCB) ↔ (ACC)`

**Status bits:** None affected.

**Description:** (ACC) is exchanged (switched) with (ACCB).

**Words:** 1

**Cycles — single instruction:** ROM 1, DARAM 1, SARAM 1, External 1+p.
**Cycles — RPT execution:** ROM n, DARAM n, SARAM n, External n+p.

---

## IDLE — Idle Until Interrupt

**Ref:** §6.3, PDF p. 259 / printed 6-107.

**Syntax:** `IDLE`
**Operands:** None

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 0 1 0  0 0 1 0` — i.e. `1011 1110 0010 0010` (0xBE22).

**Execution:** `(PC) + 1 → PC`

**Status bits:** Affected by: INTM.

**Description:** Execution is forced to wait until an unmasked (external or internal) interrupt or reset
occurs. PC is incremented only once; the device remains in idle mode until interrupted. Idle mode is exited
by an unmasked interrupt even if INTM is set. If INTM = 1, execution continues at the instruction following
IDLE; if INTM = 0, the program branches to the corresponding interrupt service routine (ISR). When an
interrupt exits IDLE with interrupts disabled (INTM = 1), no interrupt flag register (IFR) bits are cleared;
IFR bits are cleared only if interrupts are enabled and IDLE is exited by entering the ISR. IDLE enters
power-down mode; during idle mode the timer and serial port peripherals are still active, so timer and
peripheral interrupts, as well as reset or external interrupts, remove the processor from idle mode. Control
instruction (see Table 6–10).

**Words:** 1

**Cycles:** NOT repeatable. **Single instruction:** ROM 1, DARAM 1, SARAM 1, External 1+p.

---

## IDLE2 — Idle Until Interrupt (Low-Power, Clock Removed)

**Ref:** §6.3, PDF p. 260 / printed 6-108.

**Syntax:** `IDLE2`
**Operands:** None

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 0 1 0  0 0 1 1` — i.e. `1011 1110 0010 0011` (0xBE23).

**Execution:** `(PC) + 1 → PC`

**Status bits:** Affected by: INTM.

**Description:** Execution is forced to wait until an unmasked (external or internal) interrupt or reset
occurs. The functional clock input is removed from the internal device to make an extremely low-power mode
possible. PC is incremented only once; the device remains in idle mode until interrupted. Idle2 mode is
exited by an unmasked interrupt even if INTM is set. If INTM = 1, execution continues at the instruction
following IDLE2; if INTM = 0, the program branches to the corresponding ISR. When an interrupt exits
IDLE2 with interrupts disabled (INTM = 1), no IFR bits are cleared; IFR bits are cleared only if interrupts
are enabled and IDLE2 is exited by entering the ISR. IDLE2 enters power-down mode; during idle2 mode
the timer and serial port peripherals are NOT active. Idle2 mode is exited by a low logic level on an external
interrupt (INT1–INT4), RS, or NMI with a duration of at least five machine cycles, because interrupts are
not latched as in normal device operation. Control instruction (see Table 6–10).

**Words:** 1

**Cycles:** NOT repeatable. **Single instruction:** ROM 1, DARAM 1, SARAM 1, External 1+p.

---

## IN — Input Data from I/O Port to Data Memory

**Ref:** §6.3, PDF pp. 261–262 / printed 6-109–6-110.

**Syntax:**
- Direct: `IN dma, PA`
- Indirect: `IN {ind}, PA [,ARn]`

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; 0 ≤ port address PA ≤ 65535; ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcodes** (15..0):
- Direct: `1 0 1 0  1 1 1 1  0  dma[6:0]`, second word = 16-Bit Constant — bits 15–7 = 1010 1111 0, bits 6–0 = dma.
- Indirect: `1 0 1 0  1 1 1 1  1  [See Section 5.2]`, second word = 16-Bit Constant — bits 15–7 = 1010 1111 1, bits 6–0 = indirect-addressing field.

**Execution:**
- `(PC) + 2 → PC`
- While (repeat counter) ≠ 0:
  - `Port address → address bus A15–A0`
  - `Data bus D15–D0 → dma`
  - `Port address → dma` [as printed in the extraction; semantically unclear — see note below]
  - `Port address + 1 → Port address`
  - `(repeat counter − 1) → repeat counter`
- [NOTE: the extracted Execution block for IN contains the line "Port address → dma" between the data-bus
  transfer and the port-address increment; it is reproduced verbatim as printed in the extraction, but its
  meaning is unclear and it may be an extraction artifact of the manual's loop body. It is NOT relied on
  anywhere else in this file.]

**Status bits:** None affected.

**Description:** A 16-bit value from an external I/O port is read into (dma). The IS line goes low to indicate
an I/O access, and the STRB, RD, and READY timings are the same as for an external data memory read.
Port addresses 50h–5Fh are memory-mapped (see §9.1.1, Memory-Mapped Peripheral Registers and I/O
Ports); the other port addresses are not. RPT can be used with IN to read consecutive words in I/O space
to data space; the number of words moved is one greater than the number in RPTC at the beginning of the
instruction. With RPT, IN becomes a single-cycle instruction once the RPT pipeline is started, and the port
address is incremented after each access. I/O and data memory operation instruction (see Table 6–9).

**Words:** 2

**Cycles — single instruction** (iosrc = I/O wait states of the source; pcode = program wait states of the code):

| Destination | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | 2+iosrc | 2+iosrc | 2+iosrc | 3+iosrc+2pcode |
| SARAM | 2+iosrc | 2+iosrc | 2+iosrc, 3+iosrc† | 3+iosrc+2pcode |
| External | 3+ddst+iosrc | 3+ddst+iosrc | 3+ddst+iosrc | 6+ddst+iosrc+2pcode |

† If the destination operand and the code are in the same SARAM block.

**Cycles — RPT execution:**

| Destination | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | 2n+niosrc | 2n+niosrc | 2n+niosrc | 2n+1+niosrc+2pcode |
| SARAM | 2n+niosrc | 2n+niosrc | 2n+niosrc, 2n+2+niosrc† | 2n+1+niosrc+2pcode |
| External | 4n−1+nddst+niosrc | 4n−1+nddst+niosrc | 4n−1+nddst+niosrc | 4n+2+nddst+niosrc+2pcode |

† If the destination operand and the code are in the same SARAM block.

---

## INTR — Software Interrupt

**Ref:** §6.3, PDF pp. 263–264 / printed 6-111–6-112.

**Syntax:** `INTR K`
**Operands:** 0 ≤ K ≤ 31

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 1 1  INTR#†` — bits 15–5 = 1011 1110 011, bits 4–0 = INTR# (the K value).
† See Table 6–1 on page 6-2.

**Execution:**
- `(PC) + 1 → stack`
- `corresponding interrupt vector → PC`

**Status bits:** Not affected by: INTM. Affects: INTM.

**Description:** A software interrupt that transfers program control to a program-memory-address (pma)
interrupt vector specified by K. The current PC is incremented and pushed onto the stack; the pma is loaded
into PC. The INTM bit has no effect on the INTR instruction. An INTR interrupt for the INT1–INT4
interrupts looks exactly like an external interrupt, except the interrupt will not clear the appropriate bit in
the IFR. See Section 4.8, Interrupts, for a complete description of interrupt operation. Branch and call
instruction (see Table 6–8).

**K → interrupt vector table** (Hex Location = vector address):

| K | Interrupt | Hex | K | Interrupt | Hex |
|---|---|---|---|---|---|
| 0 | RS | 0 | 16 | Reserved | 20 |
| 1 | INT1 | 2 | 17 | TRAP | 22 |
| 2 | INT2 | 4 | 18 | NMI | 24 |
| 3 | INT3 | 6 | 19 | Reserved | 26 |
| 4 | TINT | 8 | 20 | User-defined | 28 |
| 5 | RINT | A | 21 | User-defined | 2A |
| 6 | XINT | C | 22 | User-defined | 2C |
| 7 | TRNT | E | 23 | User-defined | 2E |
| 8 | TXNT | 10 | 24 | User-defined | 30 |
| 9 | INT4 | 12 | 25 | User-defined | 32 |
| 10 | Reserved | 14 | 26 | User-defined | 34 |
| 11 | Reserved | 16 | 27 | User-defined | 36 |
| 12 | Reserved | 18 | 28 | User-defined | 38 |
| 13 | Reserved | 1A | 29 | User-defined | 3A |
| 14 | Reserved | 1C | 30 | User-defined | 3C |
| 15 | Reserved | 1E | 31 | User-defined | 3E |

The reserved interrupt vectors can be used for the 'C50, 'C51, and 'C53. However, software compatibility
with other fifth generation devices is not guaranteed.

**Words:** 1

**Cycles:** NOT repeatable. **Single instruction:** ROM 4, DARAM 4, SARAM 4, External 4+3p†.
† The 'C5x performs speculative fetching by reading two additional instruction words. If PC discontinuity
is taken, these two instruction words are discarded.

---

## LACB — Load ACCB into ACC

**Ref:** §6.3, PDF p. 265 / printed 6-113.

**Syntax:** `LACB`
**Operands:** None

**Opcode** (15..0): `1 0 1 1  1 1 1 0  0 0 0 1  1 1 1 1` — i.e. `1011 1110 0001 1111` (0xBE1F).

**Execution:**
- `(PC) + 1 → PC`
- `(ACCB) → ACC`

**Status bits:** None affected.

**Description:** (ACCB) is loaded into (ACC). Accumulator memory reference instruction (see Table 6–4).

**Words:** 1

**Cycles — single instruction:** ROM 1, DARAM 1, SARAM 1, External 1+p.
**Cycles — RPT execution:** ROM n, DARAM n, SARAM n, External n+p.

---

## LACC — Load Data Memory Value, with Left Shift, into ACC

**Ref:** §6.3, PDF pp. 266–268 / printed 6-114–6-116. (Entry starts on PDF p. 266, the last page of
this file's range, and runs to PDF p. 268.)

**Syntax:**
- Direct: `LACC dma [,shift]`
- Indirect: `LACC {ind} [,shift [,ARn]]`
- Long immediate: `LACC #lk [,shift]`

**Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; 0 ≤ shift ≤ 16 (defaults to 0); −32768 ≤ lk ≤ 32767;
ind: `{* *+ *– *0+ *0– *BR0+ *BR0–}`.

**Opcodes** (15..0):
- Direct, with shift: `0 0 0 1  SHFT†  0  dma[6:0]` — bits 15–12 = 0001, bits 11–8 = SHFT, bit 7 = 0, bits 6–0 = dma.
- Indirect, with shift: `0 0 0 1  SHFT†  1  [See Section 5.2]` — bits 15–12 = 0001, bits 11–8 = SHFT, bit 7 = 1, bits 6–0 = indirect-addressing field.
- Direct, shift of 16: `0 1 1 0  1 0 1 0  0  dma[6:0]` — bits 15–7 = 0110 1010 0, bits 6–0 = dma.
- Indirect, shift of 16: `0 1 1 0  1 0 1 0  1  [See Section 5.2]` — bits 15–7 = 0110 1010 1, bits 6–0 = indirect-addressing field.
- Long immediate, with shift: `1 0 1 1  1 1 1 1  1 0 0 0  SHFT†`, second word = 16-Bit Constant — bits 15–4 = 1011 1111 1000, bits 3–0 = SHFT.
  † SHFT: see Table 6–1 on page 6-2.

**Execution:**
- Direct or indirect: `(PC) + 1 → PC`; `(dma) × 2^shift → ACC`
- Long immediate: `(PC) + 2 → PC`; `lk × 2^shift → ACC`

**Status bits:** Affected by: SXM.

**Description:** (dma) or a 16-bit constant is shifted left, as defined by the shift code, and loaded into (ACC).
During shifting, the low-order bits of ACC are zero-filled. If SXM = 0, the high-order bits of ACC are
zero-filled; if SXM = 1, they are sign-extended. Accumulator memory reference instruction (see Table 6–4).

**Words:** 1 (direct or indirect); 2 (long immediate).

**Cycles — single instruction (direct or indirect):**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | 1 | 1 | 1 | 1+p |
| SARAM | 1 | 1 | 1, 2† | 1+p |
| External | 1+d | 1+d | 1+d | 2+d+p |

† If the operand and the code are in the same SARAM block.

**Cycles — RPT execution (direct or indirect):**

| Operand | ROM | DARAM | SARAM | External |
|---|---|---|---|---|
| DARAM | n | n | n | n+p |
| SARAM | n | n | n, n+1† | n+p |
| External | n+nd | n+nd | n+nd | n+1+p+nd |

† If the operand and the code are in the same SARAM block.

**Cycles — single instruction (long immediate):** ROM 2, DARAM 2, SARAM 2, External 2+2p.
Long immediate mode is NOT repeatable.

---

## Coverage and notes

- Instructions transcribed (46, in manual order): ABS, ADCB, ADD, ADDB, ADDC, ADDS, ADDT, ADRK, AND,
  ANDB, APAC, APL, B, BACC, BACCD, BANZ, BANZD, BCND, BCNDD, BD, BIT, BITT, BLDD, BLDP, BLPD, BSAR, CALA,
  CALAD, CALL, CALLD, CC, CCD, CLRC, CMPL, CMPR, CPL, CRGT, CRLT, DMOV, EXAR, IDLE, IDLE2, IN, INTR, LACB, LACC.
- First entry: ABS (PDF p. 180 / printed 6-28). Last entry: LACC (starts PDF p. 266 / printed 6-114,
  runs to PDF p. 268 / printed 6-116). Next entry, LACL (PDF p. 269 / printed 6-117), belongs to the
  following worker's range and is NOT transcribed here.
- No entry in this range required a `[UNVERIFIED — extraction garbled]` marker: all opcode rows, cycle
  tables, and status-bit blocks were legible in the `pdftotext -layout` extraction. Two items are flagged
  inside their entries instead (not as full-entry unverified): (1) the IN Execution block contains the line
  "Port address → dma" reproduced verbatim but semantically unclear — possible extraction artifact;
  (2) the BLDD RPT long-immediate DARAM → DARAM row is printed at the foot of the preceding
  single-instruction table (PDF p. 223) and is placed in the RPT table here, labelled INFERENCE.
- Contradictions / cross-checks recorded:
  - CALAD opcode is `1011 1110 0011 1101` (0xBE3D) in both §6.3 (PDF p. 236) and the §6.2 summary
    (PDF p. 170). The c5x core audit's reference to CALAD as 0xBE31 does not match the manual.
  - BLDD: the §6.2 summary (PDF p. 171) lists a single representative opcode `1010 1000 IAAA AAAA`,
    which matches only the SRC-long-immediate form; §6.3 prints eight distinct forms (see BLDD entry).
    This is a summary-table abbreviation, not a disagreement on any single form.
  - AND: the manual's Status Bits block lists only "Not affected by: SXM (long immediate addressing)"
    and no "Affects" line; recorded as printed with an INFERENCE note.
  - CMPL: the Execution line prints as `(ACC) → ACC`; the overbar (logical inversion) is lost in text
    extraction — the Description ("replaced with its logical inversion (1s complement)") is authoritative.
  - INTR vector table (PDF p. 263): TINT 8h, RINT Ah, XINT Ch, TRNT Eh, TXNT 10h, INT4 12h. The c5x
    core audit reports the core's vectors as +0x10 too high relative to this table; that is a core bug, not
    a manual contradiction.
