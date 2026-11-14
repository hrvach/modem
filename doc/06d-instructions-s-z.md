# TMS320C5x User's Guide (SPRU056D, June 1998) — Chapter 6, §6.3 Per-Instruction Descriptions: RETC–ZPR

Source (only authority): `~/workspace/user/files/spru056d.pdf` (SPRU056D, June 1998).
Range: entries whose Syntax block starts on PDF pp. 355–442 (printed pp. 6-203–6-290).
Printed-page mapping in this range: printed p. 6-N = PDF p. (N + 152).
Chapter 7 starts on PDF p. 443; no entry starting in this range runs past PDF p. 442.
Instruction titles are taken from the Chapter 6 summary tables (Tables 6–4–6–10, §6.2),
since the §6.3 pages themselves carry no title line — only the Syntax block.
Manual Examples are omitted throughout (task scope: no invented examples; the manual's
worked examples are not transcribed).
Notation as printed (§6.1, p. 6-25): `p` = program memory wait states; `d` = data memory
wait states; `io` = I/O wait states (additional clock cycles the device waits for external
memory/I/O to respond); `n` = number of times a repeated instruction is executed
(n > 2 to fill the pipeline). Subscripts src/dst/code (source/destination/code) may be
attached to these variables. `†` footnotes are transcribed verbatim.
Where the manual prints "not repeatable" instead of an RPT table, that is recorded as the
RPT entry. `[UNVERIFIED …]` marks garbled extraction; none was needed in this range.

---

## RETC — Return from subroutine conditionally

- **Source:** §6.3, PDF p. 355, printed p. 6-203.
- **Syntax:** `RETC cond [, cond1 ] [, ...]`
- **Operands — conditions:** ACC = 0 → EQ; ACC ≠ 0 → NEQ; ACC < 0 → LT; ACC ≤ 0 → LEQ; ACC > 0 → GT; ACC ≥ 0 → GEQ; C = 0 → NC; C = 1 → C; OV = 0 → NOV; OV = 1 → OV; BIO low → BIO; TC = 0 → NTC; TC = 1 → TC; Unconditional → UNC.
- **Opcode (15–0):** `1110 11TP ZLVC ZLVC` — bits 15–12 = 1110; 11–10 = 11; 9–8 = TP†; 7–4 = ZLVC†; 3–0 = ZLVC†. † See Table 6–1 on p. 6-2.
- **Words:** 1
- **Cycles — single instruction:**

  | Condition | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | True | 4 | 4 | 4 | 4+3p† |
  | False | 2 | 2 | 2 | 2+p |

  † The 'C5x performs speculative fetching by reading two additional instruction words. If PC discontinuity is taken, these two instruction words are discarded.
- **Cycles — RPT execution:** Not repeatable.
- **Status bits:** None affected.
- **Execution:** If (condition(s)): (TOS) → PC; pop stack one level. Else, continue.
- **Description:** If the specified conditions are met, (TOS) is copied to PC; the stack is popped one level after the contents are copied. Not all combinations of the conditions are meaningful. If the conditions are not met, control passes to the next instruction. RETC is a branch and call instruction (see Table 6–8).

## RETCD — Delayed return from subroutine conditionally

- **Source:** §6.3, PDF p. 357, printed p. 6-205.
- **Syntax:** `RETCD cond [, cond1 ] [, ...]`
- **Operands — conditions:** same 14 as RETC: ACC = 0 → EQ; ACC ≠ 0 → NEQ; ACC < 0 → LT; ACC ≤ 0 → LEQ; ACC > 0 → GT; ACC ≥ 0 → GEQ; C = 0 → NC; C = 1 → C; OV = 0 → NOV; OV = 1 → OV; BIO low → BIO; TC = 0 → NTC; TC = 1 → TC; Unconditional → UNC.
- **Opcode (15–0):** `1111 11TP ZLVC ZLVC` — bits 15–12 = 1111; 11–10 = 11; 9–8 = TP†; 7–4 = ZLVC†; 3–0 = ZLVC†. † See Table 6–1 on p. 6-2.
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 2 | 2 | 2 | 2+p |

- **Cycles — RPT execution:** Not repeatable.
- **Status bits:** None affected.
- **Execution:** If (condition(s)): (TOS) → PC; pop stack one level. Else, continue.
- **Description:** The one 2-word instruction or two 1-word instructions following RETCD are fetched from program memory and executed before the execution of the return. The two instruction words following RETCD have no effect on the conditions being tested. After the instructions are executed, if the specified conditions are met, (TOS) is copied to PC; the stack is popped one level after the contents are copied. Not all combinations of the conditions are meaningful. If the conditions are not met, control passes to the next instruction. RETCD is a branch and call instruction (see Table 6–8).
- **Note — contradiction:** Table 6–8 (§6.2, p. 6-18) lists RETCD cycles as "4¶ or 2#" (¶ = conditions true, # = condition false), but the §6.3 table above gives a single row of 2 cycles with no True/False split. Both are recorded as printed.

## RETD — Delayed return from subroutine

- **Source:** §6.3, PDF p. 359, printed p. 6-207.
- **Syntax:** `RETD`
- **Operands:** None.
- **Opcode (15–0):** `1111 1111 0000 0000`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 2 | 2 | 2 | 2+p |

- **Cycles — RPT execution:** Not repeatable.
- **Status bits:** None affected.
- **Execution:** (TOS) → PC; pop stack one level.
- **Description:** The one 2-word instruction or two 1-word instructions following RETD are fetched from program memory and executed before the execution of the return. After the instructions are executed, (TOS) is copied to PC; the stack is popped one level after the contents are copied. RETD is a branch and call instruction (see Table 6–8).

## RETE — Return from interrupt with context switch and globally enable interrupts (INTM = 0)

- **Source:** §6.3, PDF p. 360, printed p. 6-208.
- **Syntax:** `RETE`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0011 1010`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 4 | 4 | 4 | 4+3p† |

  † The 'C5x performs speculative fetching by reading two additional instruction words. If PC discontinuity is taken, these two instruction words are discarded.
- **Cycles — RPT execution:** Not repeatable.
- **Status bits:** Affects: ARB, ARP, AVIS, BRAF, C, CNF, DP, HM, INTM, MP/MC, NDX, OV, OVLY, OVM, PM, RAM, SXM, TC, TRM, and XF. (No "does not affect" list is printed for RETE.)
- **Execution:** (TOS) → PC; pop stack one level; 0 → INTM.
- **Description:** (TOS) is copied to PC; the stack is popped one level after the contents are copied. RETE automatically clears the INTM bit and pops the shadow register values (see the RETI description, p. 6-209). RETE is the equivalent of clearing the INTM bit and executing a RETI instruction. RETE is a branch and call instruction (see Table 6–8).

## RETI — Return from interrupt with context switch

- **Source:** §6.3, PDF p. 361, printed p. 6-209.
- **Syntax:** `RETI`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0011 1000`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 4 | 4 | 4 | 4+3p† |

  † The 'C5x performs speculative fetching by reading two additional instruction words. If PC discontinuity is taken, these two instruction words are discarded.
- **Cycles — RPT execution:** Not repeatable.
- **Status bits:** Affects: ARB, ARP, AVIS, BRAF, C, CNF, DP, HM, MP/MC, NDX, OV, OVLY, OVM, PM, RAM, SXM, TC, TRM, and XF. Does not affect: INTM.
- **Execution:** (TOS) → PC; pop stack one level.
- **Description:** (TOS) is copied to PC. The values in the shadow registers (stored when an interrupt was taken) are returned to their corresponding strategic registers. Shadowed registers: ACC, ACCB, ARCR, INDX, PMST, PREG, ST0, ST1, TREG0, TREG1, and TREG2. The INTM bit in ST0 and the XF bit in ST1 are not saved or restored to or from the shadow registers during an interrupt service routine (ISR). RETI is a branch and call instruction (see Table 6–8).

## ROL — Rotate ACC left 1 bit

- **Source:** §6.3, PDF p. 362, printed p. 6-210.
- **Syntax:** `ROL`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0000 1100`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** Not affected by: SXM. Affects: C.
- **Execution:** (PC) + 1 → PC; C → ACC(0); (ACC(31)) → C; (ACC(30–0)) → ACC(31–1).
- **Description:** The contents of the accumulator (ACC) are rotated left 1 bit. The value of the C bit is shifted into the LSB of the ACC. The MSB of the original ACC is shifted into the C bit. ROL is an accumulator memory reference instruction (see Table 6–4).

## ROLB — Rotate ACCB and ACC left 1 bit

- **Source:** §6.3, PDF p. 363, printed p. 6-211.
- **Syntax:** `ROLB`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0001 0100`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** Not affected by: SXM. Affects: C.
- **Execution:** (PC) + 1 → PC; C → ACCB(0); (ACCB(30–0)) → ACCB(31–1); (ACCB(31)) → ACC(0); (ACC(30–0)) → ACC(31–1); (ACC(31)) → C.
- **Description:** ROLB causes a 65-bit rotation. The contents of both the accumulator (ACC) and accumulator buffer (ACCB) are rotated left 1 bit. The value of the C bit is shifted into the LSB of the ACCB. The MSB of the original ACCB is shifted into the LSB of the ACC. The MSB of the original ACC is shifted into the C bit. ROLB is an accumulator memory reference instruction (see Table 6–4).

## ROR — Rotate ACC right 1 bit

- **Source:** §6.3, PDF p. 364, printed p. 6-212.
- **Syntax:** `ROR`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0000 1101`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** Not affected by: SXM. Affects: C.
- **Execution:** (PC) + 1 → PC; C → ACC(31); (ACC(0)) → C; (ACC(31–1)) → ACC(30–0).
- **Description:** The contents of the accumulator (ACC) are rotated right 1 bit. The value of the C bit is shifted into the MSB of the ACC. The LSB of the original ACC is shifted into the C bit. ROR is an accumulator memory reference instruction (see Table 6–4).

## RORB — Rotate ACCB and ACC right 1 bit

- **Source:** §6.3, PDF p. 365, printed p. 6-213.
- **Syntax:** `RORB`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0001 0101`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** Not affected by: SXM. Affects: C.
- **Execution:** (PC) + 1 → PC; C → ACC(31); (ACC(31–1)) → ACC(30–0); (ACC(0)) → ACCB(31); (ACCB(31–1)) → ACCB(30–0); (ACCB(0)) → C.
- **Description:** RORB causes a 65-bit rotation. The contents of both the accumulator (ACC) and accumulator buffer (ACCB) are rotated right 1 bit. The value of the C bit is shifted into the MSB of the ACC. The LSB of the original ACC is shifted into the MSB of the ACCB. The LSB of the original ACCB is shifted into the C bit. RORB is an accumulator memory reference instruction (see Table 6–4).

## RPT — Repeat next instruction specified by data memory value

- **Source:** §6.3, PDF pp. 366–367, printed pp. 6-214–6-215.
- **Syntax:**
  - Direct: `RPT dma`
  - Indirect: `RPT {ind} [, ARn ]`
  - Short immediate: `RPT #k`
  - Long immediate: `RPT #lk`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; 0 ≤ k ≤ 255; 0 ≤ lk ≤ 65535; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `0000 1011 0` + dma (bits 6–0) — bits 15–8 = 0000 1011; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `0000 1011 1` + indirect field (bits 6–0) — see Section 5.2.
  - Short immediate addressing: `1011 1011` + 8-bit constant (bits 7–0).
  - Long immediate addressing, word 1: `1011 1110 1100 0100`; word 2: 16-bit constant.
- **Words:** 1 (direct, indirect, or short immediate addressing); 2 (long immediate addressing).
- **Cycles — single instruction (direct or indirect addressing):**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 2† | 1+p |
  | External | 1+d | 1+d | 1+d | 2+d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — single instruction (immediate addressing):**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 2 | 2 | 2 | 2+2p |

- **Cycles — RPT execution:** Not repeatable.
- **Status bits:** None affected.
- **Execution:**
  - Direct or indirect addressing: (PC) + 1 → PC; (dma) → RPTC.
  - Short immediate addressing: (PC) + 1 → PC; k → RPTC.
  - Long immediate addressing: (PC) + 2 → PC; lk → RPTC.
- **Description:** The contents of the data memory address (dma), an 8-bit constant, or a 16-bit constant are loaded into the repeat counter register (RPTC). The instruction following the RPT instruction is repeated n times, where n is one more than the initial value of the RPTC. Since the RPTC cannot be saved during a context switch, repeat loops are regarded as multicycle instructions and are not interruptible. However, the processor can halt a repeat loop in response to an external HOLD signal. The execution restarts when HOLD/HOLDA are deasserted. The RPTC is cleared on a device reset. RPT is especially useful for block moves, multiply-accumulates, normalization, and other functions. RPT is a control instruction (see Table 6–10).

## RPTB — Repeat block of instructions specified by BRCR

- **Source:** §6.3, PDF pp. 369–370, printed pp. 6-217–6-218.
- **Syntax:** `RPTB pma`
- **Operands:** 0 ≤ pma ≤ 65535.
- **Opcode (15–0):** word 1: `1011 1110 1100 0110`; word 2: 16-bit constant.
- **Words:** 2
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 2 | 2 | 2 | 2+2p |

- **Cycles — RPT execution:** Not repeatable.
- **Status bits:** Affected by: BRAF. Affects: BRAF.
- **Execution:** 1 → BRAF; (PC) + 2 → PASR; pma → PAER.
- **Description:** A block of instructions to be repeated a number of times is specified by the memory-mapped block repeat counter register (BRCR) without any penalty for looping. The BRCR must be loaded before execution of an RPTB instruction. When RPTB is executed, the BRAF bit is set, the block repeat program address start register (PASR) is loaded with the contents of the program counter (PC) + 2, and the block repeat program address end register (PAER) is loaded with the program memory address (pma). Block repeat can be deactivated by clearing the BRAF bit. The number of loop iterations is given as (BRCR) + 1. RPTB is interruptible. However, RPTB instructions cannot be nested unless the BRAF bit is properly set and the BRCR, PAER, and PASR are appropriately saved and restored. Single-instruction repeat loops (RPT and RPTZ) can be included as part of RPTB blocks. Note: the repeat block must contain at least 3 instruction words for proper operation. RPTB is a control instruction (see Table 6–10).

## RPTZ — Clear ACC and PREG; repeat next instruction specified by long immediate

- **Source:** §6.3, PDF p. 371, printed p. 6-219.
- **Syntax:** `RPTZ #lk`
- **Operands:** 0 ≤ lk ≤ 65535.
- **Opcode (15–0):** word 1: `1011 1110 1100 0101`; word 2: 16-bit constant.
- **Words:** 2
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 2 | 2 | 2 | 2+2p |

- **Cycles — RPT execution:** Not repeatable.
- **Status bits:** None affected.
- **Execution:** 0 → ACC; 0 → PREG; (PC) + 1 → PC; lk → RPTC.
- **Description:** The contents of the accumulator (ACC) and product register (PREG) are cleared. The 16-bit constant, lk, is loaded into the repeat counter register (RPTC). The instruction following the RPTZ instruction is repeated lk + 1 times. RPTZ is equivalent to the instruction sequence: MPY #0; PAC; RPT #<lk>. RPTZ is a control instruction (see Table 6–10).

## SACB — Store ACC in ACCB

- **Source:** §6.3, PDF p. 372, printed p. 6-220.
- **Syntax:** `SACB`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0001 1110`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** None affected.
- **Execution:** (PC) + 1 → PC; (ACC) → ACCB.
- **Description:** The contents of the accumulator (ACC) are copied to the accumulator buffer (ACCB). The contents of the ACC are unaffected. SACB is an accumulator memory reference instruction (see Table 6–4).

## SACH — Store ACCH, with left shift, in data memory location

- **Source:** §6.3, PDF p. 373, printed p. 6-221.
- **Syntax:**
  - Direct: `SACH dma [, shift2 ]`
  - Indirect: `SACH {ind} [, shift2 [, ARn ] ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; 0 ≤ shift2 ≤ 7 (defaults to 0); ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `1001 1SHF 0` + dma (bits 6–0) — bits 15–11 = 10011; bits 10–8 = SHF†; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `1001 1SHF 1` + indirect field (bits 6–0) — see Section 5.2. † See Table 6–1 on p. 6-2.
- **Words:** 1
- **Cycles — single instruction:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 2† | 1+p |
  | External | 2+d | 2+d | 2+d | 4+d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n | n | n | n+p |
  | SARAM | n | n | n, n+2† | n+p |
  | External | 2n+nd | 2n+nd | 2n+nd | 2n+2+nd+p |

  † If the operand and the code are in the same SARAM block.
- **Status bits:** Not affected by: SXM. (No "affects" list is printed.)
- **Execution:** (PC) + 1 → PC; (ACC) << 2^shift2 → dma. [As printed: `(ACC) × 2^shift2 → dma`.]
- **Description:** The contents of the accumulator (ACC) are shifted left from 0 to 7 bits, as defined by the shift code, and the high-order bits are stored in the data memory address (dma). During shifting, the high-order bits are lost. The contents of the ACC are unaffected. SACH is an accumulator memory reference instruction (see Table 6–4).

## SACL — Store ACCL, with left shift, in data memory location

- **Source:** §6.3, PDF p. 375, printed p. 6-223.
- **Syntax:**
  - Direct: `SACL dma [, shift2 ]`
  - Indirect: `SACL {ind} [, shift2 [, ARn ] ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; 0 ≤ shift2 ≤ 7 (defaults to 0); ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `1001 0SHF 0` + dma (bits 6–0) — bits 15–11 = 10010; bits 10–8 = SHF†; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `1001 0SHF 1` + indirect field (bits 6–0) — see Section 5.2. † See Table 6–1 on p. 6-2.
- **Words:** 1
- **Cycles — single instruction:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 2† | 1+p |
  | External | 2+d | 2+d | 2+d | 4+d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n | n | n | n+p |
  | SARAM | n | n | n, n+2† | n+p |
  | External | 2n+nd | 2n+nd | 2n+nd | 2n+2+nd+p |

  † If the operand and the code are in the same SARAM block.
- **Status bits:** Not affected by: SXM. (No "affects" list is printed.)
- **Execution:** (PC) + 1 → PC; (ACC(15–0)) << 2^shift2 → dma. [As printed: `(ACC(15–0)) × 2^shift2 → dma`.]
- **Description:** The contents of the accumulator low byte (ACCL) are shifted left from 0 to 7 bits, as defined by the shift code, and stored in the data memory address (dma). During shifting, the low-order bits are zero-filled and the high-order bits are lost. The contents of the ACC are unaffected. SACL is an accumulator memory reference instruction (see Table 6–4).

## SAMM — Store ACCL in memory-mapped register

- **Source:** §6.3, PDF p. 377, printed p. 6-225.
- **Syntax:**
  - Direct: `SAMM dma`
  - Indirect: `SAMM {ind} [, ARn ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `1000 1000 0` + dma (bits 6–0) — bits 15–8 = 1000 1000; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `1000 1000 1` + indirect field (bits 6–0) — see Section 5.2.
- **Words:** 1
- **Cycles — single instruction:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | MMR† | 1 | 1 | 1 | 1+p |
  | MMPORT | 2+iodst | 2+iodst | 2+iodst | 4+iodst |

  † Add one more cycle if source is a peripheral memory-mapped register access.
- **Cycles — RPT execution:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | MMR‡ | n | n | n | n+p |
  | MMPORT | 2+niodst | 2+niodst | 2+niodst | 2n+2+p+p niodst |

  ‡ Add n more cycles if source is a peripheral memory-mapped register access.
  [Note: the External/MMPORT RPT cell is transcribed exactly as printed, "2n+2+p+p niodst"; the duplicated "+p" looks like a manual misprint — the corresponding single-instruction cell is "4+iodst" — but both extraction modes agree on the printed characters, so it is left as printed.]
- **Status bits:** None affected.
- **Execution:** (PC) + 1 → PC; (ACC(15–0)) → dma(0–7).
- **Description:** The contents of the accumulator low byte (ACCL) are copied to the addressed memory-mapped register. The 9 MSBs of the data memory address are cleared, regardless of the current value of the data memory page pointer (DP) bits or the upper 9 bits of the current AR. The SAMM instruction allows the ACC to be stored to any memory location on data memory page 0 without modifying the DP bits. SAMM is an accumulator memory reference instruction (see Table 6–4).

## SAR — Store ARx in data memory location

- **Source:** §6.3, PDF pp. 379–380, printed pp. 6-227–6-228.
- **Syntax:**
  - Direct: `SAR ARx, dma`
  - Indirect: `SAR ARx, {ind} [, ARn ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ x ≤ 7; 0 ≤ n ≤ 7; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `1000 0ARX 0` + dma (bits 6–0) — bits 15–11 = 10000; bits 10–8 = ARX†; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `1000 0ARX 1` + indirect field (bits 6–0) — see Section 5.2. † See Table 6–1 on p. 6-2.
- **Words:** 1
- **Cycles — single instruction:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 2† | 1+p |
  | External | 2+d | 2+d | 2+d | 4+d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n | n | n | n+p |
  | SARAM | n | n | n, n+2† | n+p |
  | External | 2n+nd | 2n+nd | 2n+nd | 2n+2+nd+p |

  † If the operand and the code are in the same SARAM block.
- **Status bits:** Affected by: NDX. (No "affects" / "does not affect" list is printed.)
- **Execution:** (PC) + 1 → PC; (AR) → dma.
- **Description:** The contents of the auxiliary register (AR) are stored in the data memory address (dma). When the contents of the current AR are modified in the indirect addressing mode, SAR stores the value of the AR contents before it is incremented, decremented, or indexed by the contents of the index register (INDX). You can maintain software compatibility with the 'C2x by clearing the NDX bit. This causes any 'C2x instruction that loads AR0 to load the auxiliary register compare register (ARCR) and INDX also, maintaining 'C5x object-code compatibility with the 'C2x. The SAR and LAR (load auxiliary register) instructions can be used to store and load the ARs during subroutine calls and interrupts. If an AR is not being used for indirect addressing, LAR and SAR enable the register to be used as an additional storage register, especially for swapping values between data memory locations without affecting the contents of the accumulator (ACC). SAR is an auxiliary registers and data memory page pointer instruction (see Table 6–5).

## SATH — Barrel-shift ACC right 0 or 16 bits as specified by TREG1

- **Source:** §6.3, PDF p. 381, printed p. 6-229.
- **Syntax:** `SATH`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0101 1010`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** Affected by: SXM. Does not affect: C.
- **Execution:** (PC) + 1 → PC; 16 × (TREG1(4)) → count; (ACC) right-shifted by count → ACC.
- **Description:** SATH, in conjunction with SATL, allows for a 2-cycle 0- to 31-bit shift right. The contents of the accumulator (ACC) are barrel-shifted right 16 bits as defined by bit 4 of TREG1. If bit 4 of TREG1 is set, the contents of the ACC are barrel-shifted right by 16 bits. If bit 4 of TREG1 is cleared, the contents of the ACC are unaffected. If the SXM bit is cleared, the high-order bits are zero-filled; if the SXM bit is set, the high-order bits of the ACC are filled with copies of ACC bit 31. The C bit is unaffected. SATH is an accumulator memory reference instruction (see Table 6–4).

## SATL — Barrel-shift ACC right as specified by TREG1

- **Source:** §6.3, PDF p. 383, printed p. 6-231.
- **Syntax:** `SATL`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0101 1011`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** Affected by: SXM. Does not affect: C.
- **Execution:** (PC) + 1 → PC; (TREG1(3–0)) → count; (ACC) right-shifted by count → ACC.
- **Description:** SATL, in conjunction with SATH, allows for a 2-cycle 0- to 31-bit shift right. The contents of the accumulator (ACC) are barrel-shifted right 0 to 15 bits as defined by the 4 LSBs of TREG1. If the SXM bit is cleared, the high-order bits are zero-filled; if the SXM bit is set, the high-order bits of the ACC are filled with copies of ACC bit 31. The C bit is unaffected. SATL is an accumulator memory reference instruction (see Table 6–4).

## SBB — Subtract ACCB from ACC

- **Source:** §6.3, PDF p. 384, printed p. 6-232.
- **Syntax:** `SBB`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0001 1000`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** Affects: C. (No "affected by" / "does not affect" list is printed.)
- **Execution:** (PC) + 1 → PC; (ACC) – (ACCB) → ACC.
- **Description:** The contents of the accumulator buffer (ACCB) are subtracted from the contents of the accumulator (ACC). The result is stored in the ACC and the contents of the ACCB are unaffected. The C bit is cleared, if the result of the subtraction generates a borrow; otherwise, the C bit is set. SBB is an accumulator memory reference instruction (see Table 6–4).

## SBBB — Subtract ACCB and logical inversion of carry bit from ACC

- **Source:** §6.3, PDF p. 385, printed p. 6-233.
- **Syntax:** `SBBB`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0001 1001`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** Affects: C. (No "affected by" / "does not affect" list is printed.)
- **Execution:** (PC) + 1 → PC; (ACC) – (ACCB) – (logical inversion of C) → ACC.
- **Description:** The contents of the accumulator buffer (ACCB) and the logical inversion of the C bit are subtracted from the contents of the accumulator (ACC). The result is stored in the ACC and the contents of the ACCB are unaffected. The C bit is cleared, if the result of the subtraction generates a borrow; otherwise, the C bit is set. SBBB is an accumulator memory reference instruction (see Table 6–4).

## SBRK — Subtract short immediate from AR

- **Source:** §6.3, PDF p. 386, printed p. 6-234.
- **Syntax:** `SBRK #k`
- **Operands:** 0 ≤ k ≤ 255.
- **Opcode (15–0):** `0111 1100` + 8-bit constant (bits 7–0).
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:** Not repeatable.
- **Status bits:** None affected.
- **Execution:** (PC) + 1 → PC; (current AR) – 8-bit positive constant → current AR.
- **Description:** The 8-bit immediate value, right-justified, is subtracted from the current auxiliary register (AR). The result is stored in the current AR. The subtraction takes place in the auxiliary register arithmetic unit (ARAU), with the immediate value treated as a 8-bit positive integer. SBRK is an auxiliary registers and data memory page pointer instruction (see Table 6–5).

## SETC — Set control bit

- **Source:** §6.3, PDF pp. 387–388, printed pp. 6-235–6-236.
- **Syntax:** `SETC control bit`
- **Operands:** control bit: {C, CNF, HM, INTM, OVM, SXM, TC, XF}.
- **Opcode (15–0):** one per control bit (bits 15–8 = 1011 1110 in all cases):
  - SETC OVM (set overflow mode): `1011 1110 0100 0011`
  - SETC SXM (set sign extension mode): `1011 1110 0100 0111`
  - SETC HM (set hold mode): `1011 1110 0100 1001`
  - SETC TC (set test/control): `1011 1110 0100 1011`
  - SETC C (set carry): `1011 1110 0100 1111`
  - SETC XF (set external flag pin): `1011 1110 0100 1101`
  - SETC CNF (set configuration control): `1011 1110 0100 0101`
  - SETC INTM (set interrupt mode): `1011 1110 0100 0001`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** Affects selected control bit.
- **Execution:** (PC) + 1 → PC; 1 → control bit.
- **Description:** The specified control bit is set. The LST instruction can also be used to load ST0 and ST1. See Section 4.4, Status and Control Registers, for more information on each control bit. Constraint: an IDLE instruction must not follow a SETC INTM instruction; otherwise, an unmasked interrupt may take the device out of idle before the INTM bit is set. SETC is a control instruction (see Table 6–10).

## SFL — Shift ACC left 1 bit

- **Source:** §6.3, PDF p. 389, printed p. 6-237.
- **Syntax:** `SFL`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0000 1001`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** Not affected by: SXM. Affects: C.
- **Execution:** (PC) + 1 → PC; (ACC(31)) → C; (ACC(30–0)) → ACC(31–1); 0 → ACC(0).
- **Description:** The contents of the accumulator (ACC) are shifted left 1 bit. The MSB of the ACC is shifted into the C bit. The LSB of the ACC is filled with a 0. SFL, unlike SFR, is unaffected by the SXM bit. SFL is an accumulator memory reference instruction (see Table 6–4).

## SFLB — Shift ACCB and ACC left 1 bit

- **Source:** §6.3, PDF p. 390, printed p. 6-238.
- **Syntax:** `SFLB`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0001 0110`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** Not affected by: SXM. Affects: C.
- **Execution:** (PC) + 1 → PC; 0 → ACCB(0); (ACCB(30–0)) → ACCB(31–1); (ACCB(31)) → ACC(0); (ACC(30–0)) → ACC(31–1); (ACC(31)) → C. [The manual prints the last line as "(ACC(31) → C" with an unbalanced parenthesis; the closing parenthesis is restored here.]
- **Description:** The contents of both the accumulator (ACC) and accumulator buffer (ACCB) are shifted left 1 bit. The LSB of the ACCB is filled with a 0, and the MSB of the ACCB is shifted into the LSB of the ACC. The MSB of the ACC is shifted into the C bit. SFLB, unlike SFRB, is unaffected by the SXM bit. SFLB is an accumulator memory reference instruction (see Table 6–4).

## SFR — Shift ACC right 1 bit

- **Source:** §6.3, PDF p. 391, printed p. 6-239.
- **Syntax:** `SFR`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0000 1010`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** Affected by: SXM. Affects: C.
- **Execution:** (PC) + 1 → PC; if SXM = 0: 0 → ACC(31); if SXM = 1: (ACC(31)) → ACC(31); (ACC(31–1)) → ACC(30–0); (ACC(0)) → C.
- **Description:** The contents of the accumulator (ACC) are shifted right 1 bit. The type of shift is determined by the SXM bit. If the SXM bit is cleared, SFR produces a logic right shift: the MSB of the ACC is filled with a 0; the LSB of the ACC is shifted into the C bit. If the SXM bit is set, SFR produces an arithmetic right shift: the MSB (sign bit) of the ACC is unchanged and is copied into ACC bit 30; the LSB of the ACC is shifted into the C bit. SFR is an accumulator memory reference instruction (see Table 6–4).

## SFRB — Shift ACCB and ACC right 1 bit

- **Source:** §6.3, PDF pp. 393–394, printed pp. 6-241–6-242.
- **Syntax:** `SFRB`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0001 0111`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** Affected by: SXM. Affects: C.
- **Execution:** (PC) + 1 → PC; if SXM = 0: 0 → ACC(31); if SXM = 1: (ACC(31)) → ACC(31); (ACC(31–1)) → ACC(30–0); (ACC(0)) → ACCB(31); (ACCB(31–1)) → ACCB(30–0); (ACCB(0)) → C.
- **Description:** The contents of both the accumulator (ACC) and accumulator buffer (ACCB) are shifted right 1 bit. The type of shift is determined by the SXM bit. If the SXM bit is cleared, a logic right shift: the MSB of the ACC is filled with a 0; the LSB of the ACC is shifted into the MSB of the ACCB; the LSB of the ACCB is shifted into the C bit. If the SXM bit is set, an arithmetic right shift: the MSB (sign bit) of the ACC is unchanged and is copied into ACC bit 30; the LSB of the ACC is shifted into the MSB of the ACCB; the LSB of the ACCB is shifted into the C bit. SFRB is an accumulator memory reference instruction (see Table 6–4). [Note: in the manual's SFRB description, both shift-type sentences name "the SFR instruction" rather than SFRB — an apparent copy error in the source; the Execution block above is SFRB's own.]

## SMMR — Store memory-mapped register in data memory location

- **Source:** §6.3, PDF pp. 395–396, printed pp. 6-243–6-244.
- **Syntax:**
  - Direct: `SMMR dma, #addr`
  - Indirect: `SMMR {ind}, #addr [, ARn ]`
- **Operands:** 0 ≤ addr ≤ 65535; 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing, word 1: `0000 1001 0` + dma (bits 6–0); word 2: 16-bit constant.
  - Indirect addressing, word 1: `0000 1001 1` + indirect field (bits 6–0) — see Section 5.2; word 2: 16-bit constant.
- **Words:** 2
- **Cycles — single instruction:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | Destination: DARAM; Source: MMR‡ | 2 | 2 | 2 | 2+2pcode |
  | Destination: SARAM; Source: MMR‡ | 2 | 2 | 2, 3† | 2+2pcode |
  | Destination: External; Source: MMR‡ | 3+ddst | 3+ddst | 3+ddst | 5+ddst+2pcode |
  | Destination: DARAM; Source: MMPORT | 3+iosrc | 3+iosrc | 3+iosrc | 4+iosrc+2pcode |
  | Destination: SARAM; Source: MMPORT | 3+iosrc | 3+iosrc | 3+iosrc, 4+iosrc† | 3+iosrc+2pcode |
  | Destination: External; Source: MMPORT | 4+iosrc+ddst | 4+iosrc+ddst | 4+iosrc+ddst | 6+iosrc+ddst+2pcode |

  † If the destination operand and the code are in the same SARAM block.
  ‡ Add one more cycle for peripheral memory-mapped register access.
- **Cycles — RPT execution:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | Destination: DARAM; Source: MMR§ | 2n | 2n | 2n | 2n+2pcode |
  | Destination: SARAM; Source: MMR§ | 2n | 2n | 2n, 2n+2† | 2n+2pcode |
  | Destination: External; Source: MMR§ | 3n+nddst | 3n+nddst | 3n+nddst | 3n+3+nddst+2pcode |
  | Destination: DARAM; Source: MMPORT | 2n+niosrc | 2n+niosrc | 2n+niosrc | 2n+1+niosrc+2pcode |
  | Destination: SARAM; Source: MMPORT | 2n+niosrc | 2n+niosrc | 2n+niosrc, 2n+2+niosrc† | 2n+1+niosrc+2pcode |
  | Destination: External; Source: MMPORT | 5n–2+nddst+niosrc | 5n–2+nddst+niosrc | 5n–2+nddst+niosrc | 5n+1+nddst+niosrc+2pcode |

  † If the destination operand and the code are in the same SARAM block.
  § Add n more cycles for peripheral memory-mapped register access.
- **Status bits:** None affected.
- **Execution (as printed):** PFC → MCS; (PC) + 2 → PC; lk → PFC; while (repeat counter ≠ 0): (src, specified by lower 7 bits of dma) → (dst, addressed by PFC); (PFC) + 1 → PFC; (repeat counter) – 1 → repeat counter; MCS → PFC.
- **Description:** The memory-mapped register value pointed at by the lower 7 bits of the data memory address (dma) is stored to the data memory location addressed by the 16-bit source address, #addr. The 9 MSBs of the dma are cleared, regardless of the current value of the data memory page pointer (DP) bits or the upper 9 bits of the current AR. SMMR allows any memory location on data memory page 0 to be stored anywhere in data memory without modifying the DP bits. When using SMMR with the RPT instruction, the destination address, #addr, is incremented after every memory-mapped store operation. SMMR is an I/O and data memory operation instruction (see Table 6–9).
- **Note — contradiction in the source:** the Execution block printed for SMMR (above) is a block-move execution using PFC/MCS/lk/repeat counter; none of PFC, MCS, or lk appears in SMMR's syntax or operands, and it contradicts the Description (store MMR value to the location addressed by #addr). The same PFC/MCS block appears under other instructions in the manual (e.g. BLDD/LMMR). Transcribed as printed; the Description is the normative statement of what SMMR does.

## SPAC — Subtract PREG, with shift specified by PM bits, from ACC

- **Source:** §6.3, PDF p. 398, printed p. 6-246.
- **Syntax:** `SPAC`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0000 0101`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** Affected by: OVM and PM. Not affected by: SXM. Affects: C and OV.
- **Execution:** (PC) + 1 → PC; (ACC) – (shifted PREG) → ACC.
- **Description:** The contents of the product register (PREG) are shifted, as defined by the PM bits, and subtracted from the contents of the accumulator (ACC). The result is stored in the ACC. The C bit is cleared, if the result of the subtraction generates a borrow; otherwise, the C bit is set. SPAC is not affected by the SXM bit and the PREG is always sign extended. SPAC is a subset of the LTS, MPYS, and SQRS instructions. SPAC is a TREG0, PREG, and multiply instruction (see Table 6–7).

## SPH — Store PREG high byte, with shift specified by PM bits, in data memory location

- **Source:** §6.3, PDF p. 399, printed p. 6-247.
- **Syntax:**
  - Direct: `SPH dma`
  - Indirect: `SPH {ind} [, ARn ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `1000 1101 0` + dma (bits 6–0) — bits 15–8 = 1000 1101; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `1000 1101 1` + indirect field (bits 6–0) — see Section 5.2.
- **Words:** 1
- **Cycles — single instruction:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 2† | 1+p |
  | External | 2+d | 2+d | 2+d | 4+d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n | n | n | n+p |
  | SARAM | n | n | n, n+2† | n+p |
  | External | 2n+nd | 2n+nd | 2n+nd | 2n+2+nd+p |

  † If the operand and the code are in the same SARAM block.
- **Status bits:** Affected by: PM. (No "affects" / "does not affect" list is printed.)
- **Execution:** (PC) + 1 → PC; (PREG shifter output (31–16)) → dma.
- **Description:** The contents of the product register (PREG) high byte are shifted, as defined by the PM bits, and stored in the data memory address (dma). The contents of the PREG and the accumulator (ACC) are unaffected. When the right-shift-by-6 mode (PM is set to 11₂) is selected, high-order bits are sign extended. When left shifts are selected, low-order bits are filled from the PREG low byte. SPH is a TREG0, PREG, and multiply instruction (see Table 6–7).

## SPL — Store PREG low byte, with shift specified by PM bits, in data memory location

- **Source:** §6.3, PDF p. 401, printed p. 6-249.
- **Syntax:**
  - Direct: `SPL dma`
  - Indirect: `SPL {ind} [, ARn ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `1000 1100 0` + dma (bits 6–0) — bits 15–8 = 1000 1100; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `1000 1100 1` + indirect field (bits 6–0) — see Section 5.2.
- **Words:** 1
- **Cycles — single instruction:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 2† | 1+p |
  | External | 2+d | 2+d | 2+d | 4+d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n | n | n | n+p |
  | SARAM | n | n | n, n+2† | n+p |
  | External | 2n+nd | 2n+nd | 2n+nd | 2n+2+nd+p |

  † If the operand and the code are in the same SARAM block.
- **Status bits:** Affected by: PM. (No "affects" / "does not affect" list is printed.)
- **Execution:** (PC) + 1 → PC; (PREG shifter output (15–0)) → dma.
- **Description:** The contents of the product register (PREG) low byte are shifted, as defined by the PM bits, and stored in the data memory address (dma). The contents of the PREG and the accumulator (ACC) are unaffected. When the right-shift-by-6 mode (PM is set to 11₂) is selected, high-order bits are filled from the PREG high byte. When left shifts are selected, low-order bits are zero-filled. SPL is a TREG0, PREG, and multiply instruction (see Table 6–7).

## SPLK — Store long immediate in data memory location

- **Source:** §6.3, PDF p. 403, printed p. 6-251.
- **Syntax:**
  - Direct: `SPLK #lk, dma`
  - Indirect: `SPLK #lk, {ind} [, ARn ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; lk: 16-bit constant; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing, word 1: `1010 1110 0` + dma (bits 6–0); word 2: 16-bit constant.
  - Indirect addressing, word 1: `1010 1110 1` + indirect field (bits 6–0) — see Section 5.2; word 2: 16-bit constant.
- **Words:** 2
- **Cycles — single instruction:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 2 | 2 | 2 | 2+2p |
  | SARAM | 2 | 2 | 2, 3† | 2+2p |
  | External | 3+d | 3+d | 3+d | 5+d+2p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution:** Not repeatable.
- **Status bits:** None affected.
- **Execution:** (PC) + 2 → PC; lk → dma.
- **Description:** The 16-bit constant is stored into the data memory address (dma). The parallel logic unit (PLU) supports this bit manipulation independently of the arithmetic logic unit (ALU), so the contents of the accumulator (ACC) are unaffected. SPLK is a parallel logic unit (PLU) instruction (see Table 6–6).

## SPM — Set product shift mode (PM) bits

- **Source:** §6.3, PDF p. 404, printed p. 6-252.
- **Syntax:** `SPM constant`
- **Operands:** 0 ≤ constant ≤ 3.
- **Opcode (15–0):** `1011 1111 0000 00PM` — bits 15–2 = 1011 1111 0000 00; bits 1–0 = PM†. † See Table 6–1 on p. 6-2.
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:** Not repeatable.
- **Status bits:** Not affected by: SXM. Affects: PM.
- **Execution:** (PC) + 1 → PC; constant → PM.
- **Description:** The two low-order bits of the instruction word are copied into the product shift mode (PM) bits of ST1. The PM bits control the product register (PREG) output p-scaler shifter. The p-scaler shifter can shift the PREG output either 1 or 4 bits to the left or 6 bits to the right. PM field: 00 = output is not shifted; 01 = output is left-shifted 1 bit and LSB is zero filled; 10 = output is left-shifted 4 bits and 4 LSBs are zero filled; 11 = output is right-shifted 6 bits, sign extended and 6 LSBs are lost. The left shifts allow the product to be justified for fractional arithmetic. The right shift by 6 accommodates up to 128 multiply-accumulate processes without overflow occurring. The PM bits may also be loaded by an LST #1 instruction (p. 6-135). SPM is a TREG0, PREG, and multiply instruction (see Table 6–7).

## SQRA — Add PREG, with shift specified by PM bits, to ACC; load data memory value to TREG0; square value and store result in PREG

- **Source:** §6.3, PDF pp. 405–406, printed pp. 6-253–6-254.
- **Syntax:**
  - Direct: `SQRA dma`
  - Indirect: `SQRA {ind} [, ARn ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `0101 0010 0` + dma (bits 6–0) — bits 15–8 = 0101 0010; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `0101 0010 1` + indirect field (bits 6–0) — see Section 5.2.
- **Words:** 1
- **Cycles — single instruction:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 2† | 1+p |
  | External | 1+d | 1+d | 1+d | 2+d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n | n | n | n+p |
  | SARAM | n | n | n, n+1† | n+p |
  | External | n+nd | n+nd | n+nd | n+1+p+nd |

  † If the operand and the code are in the same SARAM block.
- **Status bits:** Affected by: OVM, PM, and TRM. Affects: C and OV.
- **Execution:** (PC) + 1 → PC; (ACC) + (shifted PREG) → ACC; (dma) → TREG0; (dma) × (dma) → PREG; if TRM = 0: (dma) → TREG1; (dma) → TREG2.
- **Description:** The contents of the product register (PREG) are shifted, as defined by the PM bits, and added to the contents of the accumulator (ACC). The result is stored in the ACC. The contents of the data memory address (dma) are loaded into TREG0 and squared. The result is stored in PREG. The C bit is set, if the result of the addition generates a carry; otherwise, the C bit is cleared. You can maintain software compatibility with the 'C2x by clearing the TRM bit. This causes any 'C2x instruction that loads TREG0 to write to all three TREGs, maintaining 'C5x object-code compatibility with the 'C2x. The TREGs are memory-mapped registers and can be read and written with any instruction that accesses data memory. TREG1 has only 5 bits, and TREG2 has only 4 bits. SQRA is a TREG0, PREG, and multiply instruction (see Table 6–7).

## SQRS — Subtract PREG, with shift specified by PM bits, from ACC; load data memory value to TREG0; square value and store result in PREG

- **Source:** §6.3, PDF pp. 407–408, printed pp. 6-255–6-256.
- **Syntax:**
  - Direct: `SQRS dma`
  - Indirect: `SQRS {ind} [, ARn ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `0101 0011 0` + dma (bits 6–0) — bits 15–8 = 0101 0011; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `0101 0011 1` + indirect field (bits 6–0) — see Section 5.2.
- **Words:** 1
- **Cycles — single instruction:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 2† | 1+p |
  | External | 1+d | 1+d | 1+d | 2+d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n | n | n | n+p |
  | SARAM | n | n | n, n+1† | n+p |
  | External | n+nd | n+nd | n+nd | n+1+p+nd |

  † If the operand and the code are in the same SARAM block.
- **Status bits:** Affected by: OVM, PM, and TRM. Affects: C and OV.
- **Execution:** (PC) + 1 → PC; (ACC) – (shifted PREG) → ACC; (dma) → TREG0; (dma) × (dma) → PREG; if TRM = 0: (dma) → TREG1; (dma) → TREG2.
- **Description:** The contents of the product register (PREG) are shifted, as defined by the PM bits, and subtracted from the contents of the accumulator (ACC). The result is stored in the ACC. The contents of the data memory address (dma) are loaded into TREG0 and squared. The result is stored in PREG. The C bit is cleared, if the result of the subtraction generates a borrow; otherwise, the C bit is set. You can maintain software compatibility with the 'C2x by clearing the TRM bit. This causes any 'C2x instruction that loads TREG0 to write to all three TREGs, maintaining 'C5x object-code compatibility with the 'C2x. The TREGs are memory-mapped registers and can be read and written with any instruction that accesses data memory. TREG1 has only 5 bits, and TREG2 has only 4 bits. SQRS is a TREG0, PREG, and multiply instruction (see Table 6–7).

## SST — Store ST0 in data memory location / Store ST1 in data memory location

- **Source:** §6.3, PDF pp. 409–410, printed pp. 6-257–6-258.
- **Syntax:**
  - Direct: `SST #m, dma`
  - Indirect: `SST #m, {ind} [, ARn ]`
- **Operands:** 0 ≤ dma ≤ 127; m = 0 or 1; 0 ≤ n ≤ 7; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing for SST #0: `1000 1110 0` + dma (bits 6–0).
  - Indirect addressing for SST #0: `1000 1110 1` + indirect field (bits 6–0) — see Section 5.2.
  - Direct addressing for SST #1: `1000 1111 0` + dma (bits 6–0).
  - Indirect addressing for SST #1: `1000 1111 1` + indirect field (bits 6–0) — see Section 5.2.
- **Words:** 1
- **Cycles — single instruction:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 2† | 1+p |
  | External | 2+d | 2+d | 2+d | 4+d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n | n | n | n+p |
  | SARAM | n | n | n, n+2† | n+p |
  | External | 2n+nd | 2n+nd | 2n+nd | 2n+2+nd+p |

  † If the operand and the code are in the same SARAM block.
- **Status bits:** None affected.
- **Execution:** (PC) + 1 → PC; (STm) → dma.
- **Description:** The contents of the status register STm are stored in the data memory address (dma). In the direct addressing mode, status register STm is always stored in data memory page 0, regardless of the value of the data memory page pointer (DP) bits. The processor automatically forces the data memory page to 0, and the specific location within that data page is defined by the instruction. The DP bits are not physically modified. This allows storage of the DP bits in the data memory on interrupts, etc., in the direct addressing mode without having to change the DP. In the indirect addressing mode, the dma is obtained from the selected auxiliary register (see the LST instruction, p. 6-135, for more information). In the indirect addressing mode, any page in data memory may be accessed. SST is a control instruction (see Table 6–10). Status registers ST0 and ST1 are defined in Section 4.4, Status and Control Registers.

## SUB — Subtract data memory value, with left shift, from ACC

- **Source:** §6.3, PDF pp. 411–413, printed pp. 6-259–6-261.
- **Syntax:**
  - Direct: `SUB dma [, shift ]`
  - Indirect: `SUB {ind} [, shift [, ARn ] ]`
  - Short immediate: `SUB #k`
  - Long immediate: `SUB #lk [, shift ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ shift ≤ 16 (defaults to 0); 0 ≤ n ≤ 7; 0 ≤ k ≤ 255; –32768 ≤ lk ≤ 32767; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing with shift: `0011 SHFT 0` + dma (bits 6–0) — bits 15–12 = 0011; bits 11–8 = SHFT†; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing with shift: `0011 SHFT 1` + indirect field (bits 6–0) — see Section 5.2. † See Table 6–1 on p. 6-2.
  - Direct addressing with shift of 16: `0110 0101 0` + dma (bits 6–0).
  - Indirect addressing with shift of 16: `0110 0101 1` + indirect field (bits 6–0) — see Section 5.2.
  - Short immediate addressing: `1011 1010` + 8-bit constant (bits 7–0).
  - Long immediate addressing with shift, word 1: `1011 1111 1010 SHFT` (bits 3–0 = SHFT†); word 2: 16-bit constant.
- **Words:** 1 (direct, indirect, or short immediate); 2 (long immediate).
- **Cycles — single instruction (direct or indirect addressing):**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 2† | 1+p |
  | External | 1+d | 1+d | 1+d | 2+d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution (direct or indirect addressing):**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n | n | n | n+p |
  | SARAM | n | n | n, n+1† | n+p |
  | External | n+nd | n+nd | n+nd | n+1+p+nd |

  † If the operand and the code are in the same SARAM block.
- **Cycles — single instruction (short immediate addressing):**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — single instruction (long immediate addressing):**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 2 | 2 | 2 | 2+2p |

- **Cycles — RPT execution (short and long immediate addressing):** Not repeatable.
- **Status bits:**
  - Direct or indirect addressing: Affected by: OVM and SXM. Affects: C and OV.
  - Short immediate addressing: Affected by: OVM. Affects: C and OV.
  - Long immediate addressing: Affected by: OVM and SXM. Affects: C and OV.
- **Execution:**
  - Direct or indirect addressing: (PC) + 1 → PC; (ACC) – ((dma) × 2^shift) → ACC.
  - Short immediate addressing: (PC) + 1 → PC; (ACC) – k → ACC.
  - Long immediate addressing: (PC) + 2 → PC; (ACC) – (lk × 2^shift) → ACC.
- **Description:** If direct, indirect, or long immediate addressing is used, the contents of the data memory address (dma) or a 16-bit constant are shifted left, as defined by the shift code, and subtracted from the contents of the accumulator (ACC). The result is stored in the ACC. During shifting, the accumulator low byte (ACCL) is zero-filled. If the SXM bit is cleared, the high-order bits of the ACC are zero-filled; if the SXM bit is set, the high-order bits of the ACC are sign-extended. Note that when the auxiliary register pointer (ARP) is updated during indirect addressing, you must specify a shift operand. If you don't want a shift, you must enter a 0 for this operand (e.g. SUB *+,0,AR0). If short immediate addressing is used, an 8-bit positive constant is subtracted from the contents of the ACC. The result is stored in the ACC. In this mode, no shift value may be specified and the subtraction is unaffected by the SXM bit. The C bit is cleared, if the result of the subtraction generates a borrow; otherwise, the C bit is set. If a 16-bit shift is specified with the SUB instruction, the C bit is cleared only if the result of the subtraction generates a borrow; otherwise, the C bit is unaffected. SUB is an accumulator memory reference instruction (see Table 6–4).

## SUBB — Subtract data memory value and logical inversion of carry bit from ACC with sign extension

- **Source:** §6.3, PDF pp. 415–416, printed pp. 6-263–6-264.
- **Syntax:**
  - Direct: `SUBB dma`
  - Indirect: `SUBB {ind} [, ARn ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `0110 0100 0` + dma (bits 6–0) — bits 15–8 = 0110 0100; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `0110 0100 1` + indirect field (bits 6–0) — see Section 5.2.
- **Words:** 1
- **Cycles — single instruction:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 2† | 1+p |
  | External | 1+d | 1+d | 1+d | 2+d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n | n | n | n+p |
  | SARAM | n | n | n, n+1† | n+p |
  | External | n+nd | n+nd | n+nd | n+1+p+nd |

  † If the operand and the code are in the same SARAM block.
- **Status bits:** Affected by: OVM. Not affected by: SXM. Affects: C and OV.
- **Execution:** (PC) + 1 → PC; (ACC) – (dma) – (logical inversion of C) → ACC.
- **Description:** The contents of the data memory address (dma) and the logical inversion of the C bit are subtracted from the contents of the accumulator (ACC) with sign extension suppressed. The result is stored in the ACC. The C bit is cleared, if the result of the subtraction generates a borrow; otherwise, the C bit is set. SUBB can be used in performing multiple-precision arithmetic. SUBB is an accumulator memory reference instruction (see Table 6–4).

## SUBC — Conditional subtract

- **Source:** §6.3, PDF pp. 417–418, printed pp. 6-265–6-266.
- **Syntax:**
  - Direct: `SUBC dma`
  - Indirect: `SUBC {ind} [, ARn ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `0000 1010 0` + dma (bits 6–0) — bits 15–8 = 0000 1010; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `0000 1010 1` + indirect field (bits 6–0) — see Section 5.2.
- **Words:** 1
- **Cycles — single instruction:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 2† | 1+p |
  | External | 1+d | 1+d | 1+d | 2+d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n | n | n | n+p |
  | SARAM | n | n | n, n+1† | n+p |
  | External | n+nd | n+nd | n+nd | n+1+p+nd |

  † If the operand and the code are in the same SARAM block.
- **Status bits:** Not affected by: OVM (no saturation) and SXM. Affects: C and OV.
- **Execution:** (PC) + 1 → PC; (ACC) – ((dma) × 2^15) → ALU output; if ALU output ≥ 0: (ALU output) × 2 + 1 → ACC; else: (ACC) × 2 → ACC.
- **Description:** SUBC performs conditional subtraction, which may be used for division. The 16-bit dividend is stored in the accumulator low byte (ACCL) and the accumulator high byte (ACCH) is zero-filled. The divisor is in data memory. SUBC is executed 16 times for 16-bit division. After completion of the last SUBC instruction, the quotient of the division is in the ACCL and the remainder is in the ACCH. SUBC assumes that the divisor and the dividend are both positive. The divisor is not sign extended. The dividend, in the ACCL, must initially be positive (bit 31 must be 0) and must remain positive following the ACC shift, which occurs in the first portion of the SUBC execution. If the 16-bit dividend contains fewer than 16 significant bits, the dividend may be placed in the ACC and shifted left by the number of leading nonsignificant zeroes. The number of SUBC executions is reduced from 16 by that number. One leading zero is always significant. SUBC affects the OV bit, but is not affected by the OVM bit, and therefore the ACC does not saturate upon positive or negative overflows when executing this instruction. The C bit is cleared, if the result of the subtraction generates a borrow; otherwise, the C bit is set. SUBC is an accumulator memory reference instruction (see Table 6–4).

## SUBS — Subtract data memory value from ACC with sign extension suppressed

- **Source:** §6.3, PDF pp. 419–420, printed pp. 6-267–6-268.
- **Syntax:**
  - Direct: `SUBS dma`
  - Indirect: `SUBS {ind} [, ARn ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `0110 0110 0` + dma (bits 6–0) — bits 15–8 = 0110 0110; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `0110 0110 1` + indirect field (bits 6–0) — see Section 5.2.
- **Words:** 1
- **Cycles — single instruction:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 2† | 1+p |
  | External | 1+d | 1+d | 1+d | 2+d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n | n | n | n+p |
  | SARAM | n | n | n, n+1† | n+p |
  | External | n+nd | n+nd | n+nd | n+1+p+nd |

  † If the operand and the code are in the same SARAM block.
- **Status bits:** Affected by: OVM. Not affected by: SXM. Affects: C and OV.
- **Execution:** (PC) + 1 → PC; (ACC) – (dma) → ACC; (dma) is an unsigned 16-bit number.
- **Description:** The contents of the data memory address (dma) are subtracted from the contents of the accumulator (ACC) with sign extension suppressed. The result is stored in the ACC. The data is treated as a 16-bit unsigned number, regardless of the SXM bit. The contents of the ACC are treated as a signed number. The C bit is cleared, if the result of the subtraction generates a borrow; otherwise, the C bit is set. SUBS produces the same results as a SUB instruction (p. 6-259) with the SXM bit cleared and a shift count of 0. SUBS is an accumulator memory reference instruction (see Table 6–4).

## SUBT — Subtract data memory value, with left shift specified by TREG1, from ACC

- **Source:** §6.3, PDF pp. 421–422, printed pp. 6-269–6-270.
- **Syntax:**
  - Direct: `SUBT dma`
  - Indirect: `SUBT {ind} [, ARn ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `0110 0111 0` + dma (bits 6–0) — bits 15–8 = 0110 0111; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `0110 0111 1` + indirect field (bits 6–0) — see Section 5.2.
- **Words:** 1
- **Cycles — single instruction:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 2† | 1+p |
  | External | 1+d | 1+d | 1+d | 2+d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n | n | n | n+p |
  | SARAM | n | n | n, n+1† | n+p |
  | External | n+nd | n+nd | n+nd | n+1+p+nd |

  † If the operand and the code are in the same SARAM block.
- **Status bits:** Affected by: OVM, SXM, and TRM. Affects: C and OV.
- **Execution:** (PC) + 1 → PC; (ACC) – ((dma) × 2^TREG1(3–0)) → (ACC); if SXM = 1: (dma) is sign-extended; if SXM = 0: (dma) is not sign-extended.
- **Description:** The contents of the data memory address (dma) are shifted left from 0 to 15 bits, as defined by the 4 LSBs of TREG1, and subtracted from the contents of the accumulator (ACC). The result is stored in the ACC. Sign extension on the dma value is controlled by the SXM bit. The C bit is cleared, if the result of the subtraction generates a borrow; otherwise, the C bit is set. You can maintain software compatibility with the 'C2x by clearing the TRM bit. This causes any 'C2x instruction that loads TREG0 to write to all three TREGs. Subsequent calls to the SUBT instruction will shift the value by the TREG1 value (which is the same as TREG0), maintaining 'C5x object-code compatibility with the 'C2x. SUBT is an accumulator memory reference instruction (see Table 6–4).

## TBLR — Transfer data from program to data memory with source address in ACCL

- **Source:** §6.3, PDF pp. 423–425, printed pp. 6-271–6-273.
- **Syntax:**
  - Direct: `TBLR dma`
  - Indirect: `TBLR {ind} [, ARn ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `1010 0110 0` + dma (bits 6–0) — bits 15–8 = 1010 0110; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `1010 0110 1` + indirect field (bits 6–0) — see Section 5.2.
- **Words:** 1
- **Cycles — single instruction:**

  | Source / Destination | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | Source: DARAM/ROM; Destination: DARAM | 3 | 3 | 3 | 3+pcode |
  | Source: SARAM; Destination: DARAM | 3 | 3 | 3 | 3+pcode |
  | Source: External; Destination: DARAM | 3+psrc | 3+psrc | 3+psrc | 3+psrc+pcode |
  | Source: DARAM/ROM; Destination: SARAM | 3 | 3 | 3, 4† | 3+pcode |
  | Source: SARAM; Destination: SARAM | 3 | 3 | 3, 4† | 3+pcode |
  | Source: External; Destination: SARAM | 3+psrc | 3+psrc | 3+psrc, 4+psrc† | 3+psrc+pcode |
  | Source: DARAM/ROM; Destination: External | 4+ddst | 4+ddst | 4+ddst | 6+ddst+pcode |
  | Source: SARAM; Destination: External | 4+ddst | 4+ddst | 4+ddst | 6+ddst+pcode |
  | Source: External; Destination: External | 4+psrc+ddst | 4+psrc+ddst | 4+psrc+ddst | 6+psrc+ddst+pcode |

  † If the destination operand and the code are in the same SARAM block.
- **Cycles — RPT execution:**

  | Source / Destination | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | Source: DARAM/ROM; Destination: DARAM | n+2 | n+2 | n+2 | n+2+pcode |
  | Source: SARAM; Destination: DARAM | n+2 | n+2 | n+2 | n+2+pcode |
  | Source: External; Destination: DARAM | n+2+npsrc | n+2+npsrc | n+2+npsrc | n+2+npsrc+pcode |
  | Source: DARAM/ROM; Destination: SARAM | n+2 | n+2 | n+2, n+4† | n+2+pcode |
  | Source: SARAM; Destination: SARAM | n+2, 2n‡ | n+2, 2n‡ | n+2, 2n‡, 2n+2§ | n+2+pcode, 2n‡ |
  | Source: External; Destination: SARAM | n+2+npsrc | n+2+npsrc | n+2+npsrc, n+4+npsrc† | n+2+npsrc+pcode |
  | Source: DARAM/ROM; Destination: External | 2n+2+nddst | 2n+2+nddst | 2n+2+nddst | 2n+4+nddst+pcode |
  | Source: SARAM; Destination: External | 2n+2+nddst | 2n+2+nddst | 2n+2+nddst | 2n+4+nddst+pcode |
  | Source: External; Destination: External | 4n+npsrc+nddst | 4n+npsrc+nddst | 4n+npsrc+nddst | 4n+2+npsrc+nddst+pcode |

  † If the destination operand and the code are in the same SARAM block.
  ‡ If both the source and the destination operands are in the same SARAM block.
  § If both operands and the code are in the same SARAM block.
- **Status bits:** None affected.
- **Execution:** (PC) + 1 → PC; (PFC) → MCS; (ACC(15–0)) → PFC; if (repeat counter) ≠ 0: (pma, addressed by PFC) → dma; modify current AR and ARP as specified; (PFC) + 1 → PFC; (repeat counter) – 1 → repeat counter; else: (pma, addressed by PFC) → dma; modify current AR and ARP as specified; (MCS) → PFC.
- **Description:** The contents of the program memory address (pma) are transferred to the data memory address (dma). The pma is specified by the contents of the accumulator low byte (ACCL) and the dma is specified by the instruction. A read from program memory is followed by a write to data memory to complete the instruction. When used with the RPT instruction, the TBLR instruction becomes a single-cycle instruction, once the RPT pipeline is started, and the program counter (PC) that contains the contents of the ACCL is incremented once each cycle. TBLR is an I/O and data memory operation instruction (see Table 6–9).

## TBLW — Transfer data from data to program memory with destination address in ACCL

- **Source:** §6.3, PDF pp. 426–428, printed pp. 6-274–6-276.
- **Syntax:**
  - Direct: `TBLW dma`
  - Indirect: `TBLW {ind} [, ARn ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `1010 0111 0` + dma (bits 6–0) — bits 15–8 = 1010 0111; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `1010 0111 1` + indirect field (bits 6–0) — see Section 5.2.
- **Words:** 1
- **Cycles — single instruction:**

  | Source / Destination | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | Source: DARAM; Destination: DARAM | 3 | 3 | 3 | 3+pcode |
  | Source: SARAM; Destination: DARAM | 3 | 3 | 3 | 3+pcode |
  | Source: External; Destination: DARAM | 3+dsrc | 3+dsrc | 3+dsrc | 3+dsrc+pcode |
  | Source: DARAM; Destination: SARAM | 3 | 3 | 3, 4† | 3+pcode |
  | Source: SARAM; Destination: SARAM | 3 | 3 | 3, 4† | 3+pcode |
  | Source: External; Destination: SARAM | 3+dsrc | 3+dsrc | 3+dsrc, 4+dsrc† | 3+dsrc+pcode |
  | Source: DARAM; Destination: External | 4+pdst | 4+pdst | 4+pdst | 5+pdst+pcode |
  | Source: SARAM; Destination: External | 4+pdst | 4+pdst | 4+pdst | 5+pdst+pcode |
  | Source: External; Destination: External | 4+dsrc+pdst | 4+dsrc+pdst | 4+dsrc+pdst | 5+dsrc+pdst+pcode |

  † If the destination operand and the code are in the same SARAM block.
- **Cycles — RPT execution:**

  | Source / Destination | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | Source: DARAM; Destination: DARAM | n+2 | n+2 | n+2 | n+2+pcode |
  | Source: SARAM; Destination: DARAM | n+2 | n+2 | n+2 | n+2+pcode |
  | Source: External; Destination: DARAM | n+2+ndsrc | n+2+ndsrc | n+2+ndsrc | n+2+ndsrc+pcode |
  | Source: DARAM; Destination: SARAM | n+2 | n+2 | n+2, n+3† | n+2+pcode |
  | Source: SARAM; Destination: SARAM | n+2, 2n‡ | n+2, 2n‡ | n+2, 2n‡, 2n+1§ | n+2+pcode, 2n‡ |
  | Source: External; Destination: SARAM | n+2+ndsrc | n+2+ndsrc | n+2+ndsrc, n+3+ndsrc† | n+2+ndsrc+pcode |
  | Source: DARAM; Destination: External | 2n+2+npdst | 2n+2+npdst | 2n+2+npdst | 2n+3+npdst+pcode |
  | Source: SARAM; Destination: External | 2n+2+npdst | 2n+2+npdst | 2n+2+npdst | 2n+3+npdst+pcode |
  | Source: External; Destination: External | 4n+ndsrc+npdst | 4n+ndsrc+npdst | 4n+ndsrc+npdst | 4n+1+ndsrc+npdst+pcode |

  † If the destination operand and the code are in the same SARAM block.
  ‡ If both the source and the destination operands are in the same SARAM block.
  § If both operands and the code are in the same SARAM block.
- **Status bits:** None affected.
- **Execution:** (PC) + 1 → PC; (PFC) → MCS; (ACC(15–0)) → PFC; if (repeat counter) ≠ 0: (dma, addressed by PFC) → pma; modify current AR and ARP as specified; (PFC) + 1 → PFC; (repeat counter) – 1 → repeat counter; else: (dma, addressed by PFC) → pma; modify current AR and ARP as specified; (MCS) → PFC.
- **Description:** The contents of the data memory address (dma) are transferred to the program memory address (pma). The dma is specified by the instruction and the pma is specified by the contents of the accumulator low byte (ACCL). A read from data memory is followed by a write to program memory to complete the instruction. When used with the RPT instruction, the TBLW instruction becomes a single-cycle instruction, once the RPT pipeline is started, and the program counter (PC) that contains the contents of the ACCL is incremented once each cycle. TBLW is an I/O and data memory operation instruction (see Table 6–9).

## TRAP — Software interrupt that branches program control to program memory location 22h

- **Source:** §6.3, PDF p. 429, printed p. 6-277.
- **Syntax:** `TRAP`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0101 0001`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 4 | 4 | 4 | 4+3p† |

  † The 'C5x performs speculative fetching by reading two additional instruction words. If PC discontinuity is taken, these two instruction words are discarded.
- **Cycles — RPT execution:** Not repeatable.
- **Status bits:** Not affected by: INTM. Does not affect: INTM.
- **Execution:** (PC) + 1 → stack; 22h → PC.
- **Description:** A software interrupt that transfers program control to program memory location 22h. The current program counter (PC) is incremented and pushed onto the stack. The address 22h is loaded into the PC. The instruction at address 22h may contain a branch instruction to transfer control to the TRAP routine. Placing the PC onto the stack enables a return instruction to pop the return address (pointing to the instruction after the TRAP) from the stack. TRAP is not maskable. TRAP is a branch and call instruction (see Table 6–8).

## XC — Execute next instruction(s) conditionally

- **Source:** §6.3, PDF pp. 430–431, printed pp. 6-278–6-279.
- **Syntax:** `XC n, cond [, cond1 ] [, ...]`
- **Operands:** n = 1 or 2. Conditions: ACC = 0 → EQ; ACC ≠ 0 → NEQ; ACC < 0 → LT; ACC ≤ 0 → LEQ; ACC > 0 → GT; ACC ≥ 0 → GEQ; C = 0 → NC; C = 1 → C; OV = 0 → NOV; OV = 1 → OV; TC = 0 → NTC; TC = 1 → TC; BIO low → BIO; Unconditional → UNC.
- **Opcode (15–0):** `111N 01TP ZLVC ZLVC` — bits 15–13 = 111; bit 12 = N†; bits 11–10 = 01; 9–8 = TP†; 7–4 = ZLVC†; 3–0 = ZLVC†. † See Table 6–1 on p. 6-2. Operand (n) value → opcode (N) value: n = 1 → N = 0; n = 2 → N = 1.
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:** Not repeatable.
- **Status bits:** None affected.
- **Execution:** If (condition(s)): next n instructions executed. Else: execute NOPs for next n instructions.
- **Description:** If n = 1 and the conditions are met, the 1-word instruction following the XC instruction executes. If n = 2 and the conditions are met, the one 2-word instruction or two 1-word instructions following the XC instruction execute. Not all combinations of the conditions are meaningful. The XC instruction and the two instruction words following the XC are uninterruptible. If the conditions are not met, one or two NOPs are executed. Conditions tested are sampled one full cycle before the XC is executed. Therefore, if the instruction prior to the XC is a single-cycle instruction, its execution will not affect the condition of the XC. If the instruction prior to the XC does affect the condition being tested, interrupt operation with the XC can cause undesired results. XC is a branch and call instruction (see Table 6–8).

## XOR — Exclusive-OR data memory value with ACCL / Exclusive-OR long immediate, with left shift, with ACC

- **Source:** §6.3, PDF pp. 432–433, printed pp. 6-280–6-281.
- **Syntax:**
  - Direct: `XOR dma`
  - Indirect: `XOR {ind} [, ARn ]`
  - Long immediate: `XOR #lk [, shift ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; lk: 16-bit constant; 0 ≤ shift ≤ 16; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `0110 1100 0` + dma (bits 6–0) — bits 15–8 = 0110 1100; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `0110 1100 1` + indirect field (bits 6–0) — see Section 5.2.
  - Long immediate addressing with shift, word 1: `1011 1111 1101 SHFT` (bits 3–0 = SHFT†); word 2: 16-bit constant.
  - Long immediate addressing with shift of 16, word 1: `1011 1110 1000 0011`; word 2: 16-bit constant. † See Table 6–1 on p. 6-2.
- **Words:** 1 (direct or indirect addressing); 2 (long immediate addressing).
- **Cycles — single instruction (direct or indirect addressing):**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 2† | 1+p |
  | External | 1+d | 1+d | 1+d | 2+d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution (direct or indirect addressing):**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n | n | n | n+p |
  | SARAM | n | n | n, n+1† | n+p |
  | External | n+nd | n+nd | n+nd | n+1+p+nd |

  † If the operand and the code are in the same SARAM block.
- **Cycles — single instruction (long immediate addressing):**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 2 | 2 | 2 | 2+2p |

- **Cycles — RPT execution (long immediate addressing):** Not repeatable.
- **Status bits:** Long immediate addressing: Not affected by: SXM. Does not affect: C. (No status-bits entry is printed for direct/indirect addressing.)
- **Execution:**
  - Direct or indirect addressing: (PC) + 1 → PC; (ACC(15–0)) XOR (dma) → ACC(15–0); (ACC(31–16)) → ACC(31–16).
  - Long immediate addressing: (PC) + 2 → PC; (ACC(31–0)) XOR (lk × 2^shift) → ACC(31–0).
- **Description:** If a long immediate constant is specified, the constant is shifted left, as defined by the shift code, and zero-extended on both ends and is exclusive-ORed with the contents of the accumulator (ACC). The result is stored in the ACC. If a constant is not specified, the contents of the data memory address (dma) are exclusive-ORed with the contents of the accumulator low byte (ACCL). The result is stored in the ACCL and the contents of the accumulator high byte (ACCH) are unaffected. XOR is an accumulator memory reference instruction (see Table 6–4).

## XORB — Exclusive-OR ACCB with ACC

- **Source:** §6.3, PDF p. 435, printed p. 6-283.
- **Syntax:** `XORB`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0001 1010`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** None affected.
- **Execution:** (PC) + 1 → PC; (ACC) XOR (ACCB) → ACC.
- **Description:** The contents of the accumulator (ACC) are exclusive-ORed with the contents of the accumulator buffer (ACCB). The result is stored in the ACC and the contents of the ACCB are unaffected. XORB is an accumulator memory reference instruction (see Table 6–4).

## XPL — Exclusive-OR data memory value with DBMR / with long immediate, and store result in data memory location

- **Source:** §6.3, PDF pp. 436–438, printed pp. 6-284–6-286.
- **Syntax:**
  - Direct: `XPL [#lk,] dma`
  - Indirect: `XPL [#lk,] {ind} [, ARn ]`
- **Operands:** 0 ≤ dma ≤ 127; lk: 16-bit constant; 0 ≤ n ≤ 7; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing, long immediate not specified: `0101 1000 0` + dma (bits 6–0).
  - Indirect addressing, long immediate not specified: `0101 1000 1` + indirect field (bits 6–0) — see Section 5.2.
  - Direct addressing, long immediate specified, word 1: `0101 1100 0` + dma (bits 6–0); word 2: 16-bit constant.
  - Indirect addressing, long immediate specified, word 1: `0101 1100 1` + indirect field (bits 6–0) — see Section 5.2; word 2: 16-bit constant.
- **Words:** 1 (long immediate not specified); 2 (long immediate specified).
- **Cycles — single instruction (long immediate not specified):**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 3† | 1+p |
  | External | 2+2d | 2+2d | 2+2d | 5+2d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution (long immediate not specified):**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n | n | n | n+p |
  | SARAM | 2n–2 | 2n–2 | 2n–2, 2n+1† | 2n–2+p |
  | External | 4n–2+2nd | 4n–2+2nd | 4n–2+2nd | 4n+1+2nd+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — single instruction (long immediate specified):**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 2 | 2 | 2 | 2+2p |
  | SARAM | 2 | 2 | 2 | 2+2p |
  | External | 3+2d | 3+2d | 3+2d | 6+2d+2p |

- **Cycles — RPT execution (long immediate specified):**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n+1 | n+1 | n+1 | n+1+2p |
  | SARAM | 2n–1 | 2n–1 | 2n–1, 2n+2† | 2n–1+2p |
  | External | 4n–1+2nd | 4n–1+2nd | 4n–1+2nd | 4n+2+2nd+2p |

  † If the operand and the code are in the same SARAM block.
- **Status bits:** Affects: TC. (No "affected by" / "does not affect" list is printed.)
- **Execution:**
  - Long immediate not specified: (PC) + 1 → PC; (dma) XOR (DBMR) → dma.
  - Long immediate specified: (PC) + 2 → PC; (dma) XOR lk → dma.
- **Description:** If a long immediate constant is specified, the constant is exclusive-ORed with the contents of the data memory address (dma). If a constant is not specified, the contents of the dma are exclusive-ORed with the contents of the dynamic bit manipulation register (DBMR). In both cases, the result is written directly back to the dma. The contents of the accumulator (ACC) are unaffected. If the result of the XOR operation is 0, the TC bit is set; otherwise, the TC bit is cleared. XPL is a parallel logic unit (PLU) instruction (see Table 6–6).

## ZALR — Zero ACCL and load ACCH with rounding

- **Source:** §6.3, PDF pp. 439–440, printed pp. 6-287–6-288.
- **Syntax:**
  - Direct: `ZALR dma`
  - Indirect: `ZALR {ind} [, ARn ]`
- **Operands:** 0 ≤ dma ≤ 127; 0 ≤ n ≤ 7; ind: {* *+ *– *0+ *0– *BR0+ *BR0–}.
- **Opcode (15–0):**
  - Direct addressing: `0110 1000 0` + dma (bits 6–0) — bits 15–8 = 0110 1000; bit 7 = 0; bits 6–0 = dma.
  - Indirect addressing: `0110 1000 1` + indirect field (bits 6–0) — see Section 5.2.
- **Words:** 1
- **Cycles — single instruction:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | 1 | 1 | 1 | 1+p |
  | SARAM | 1 | 1 | 1, 2† | 1+p |
  | External | 1+d | 1+d | 1+d | 2+d+p |

  † If the operand and the code are in the same SARAM block.
- **Cycles — RPT execution:**

  | Operand | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|---|
  | DARAM | n | n | n | n+p |
  | SARAM | n | n | n, n+1† | n+p |
  | External | n+nd | n+nd | n+nd | n+1+p+nd |

  † If the operand and the code are in the same SARAM block.
- **Status bits:** Does not affect: C. (No "affected by" / "affects" list is printed.)
- **Execution:** (PC) + 1 → PC; 8000h → ACC(15–0); (dma) → ACC(31–16).
- **Description:** The contents of the data memory address (dma) are loaded into the accumulator high byte (ACCH). ZALR rounds the value by adding 1/2 LSB; that is, the 15 low-order bits (bits 0–14) of the accumulator low byte (ACCL) are cleared, and ACCL bit 15 is set. ZALR is an accumulator memory reference instruction (see Table 6–4).

## ZAP — Zero ACC and PREG

- **Source:** §6.3, PDF p. 441, printed p. 6-289.
- **Syntax:** `ZAP`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0101 1001`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** None affected.
- **Execution:** (PC) + 1 → PC; 0 → ACC; 0 → PREG.
- **Description:** The contents of the accumulator (ACC) and product register (PREG) are cleared. ZAP speeds up the preparation for a repeat multiply/accumulate. ZAP is an accumulator memory reference instruction (see Table 6–4).

## ZPR — Zero PREG

- **Source:** §6.3, PDF p. 442, printed p. 6-290. (§6.3 ends on this page; Chapter 7 starts on PDF p. 443.)
- **Syntax:** `ZPR`
- **Operands:** None.
- **Opcode (15–0):** `1011 1110 0101 1000`
- **Words:** 1
- **Cycles — single instruction:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | 1 | 1 | 1 | 1+p |

- **Cycles — RPT execution:**

  | ROM | DARAM | SARAM | External Memory |
  |---|---|---|---|
  | n | n | n | n+p |

- **Status bits:** None affected.
- **Execution:** (PC) + 1 → PC; 0 → PREG.
- **Description:** The contents of the product register (PREG) are cleared. ZPR is a TREG0, PREG, and multiply instruction (see Table 6–7).

---

## Contradictions and source notes (within this range)

1. **RETC cycles, §6.3 vs summary Table 6–8.** §6.3 (PDF p. 355, printed p. 6-203): True 4 / False 2 cycles. Table 6–8 (§6.2, p. 6-18) lists RETC cycles as a single value, 2. Both recorded as printed.
2. **RETCD cycles, §6.3 vs summary Table 6–8.** §6.3 (PDF p. 357, printed p. 6-205): single row, 2 cycles, no True/False split. Table 6–8 (p. 6-18) lists "4¶ or 2#" (¶ = conditions true, # = condition false). Both recorded as printed.
3. **SMMR Execution block vs its own Description.** The Execution block printed for SMMR (PDF p. 395, printed p. 6-243) is a block-move execution using PFC/MCS/lk and a repeat counter; none of PFC, MCS, or lk appears in SMMR's syntax or operands, and it contradicts the Description (store the MMR value to the location addressed by #addr). The same PFC/MCS block is printed under other instructions in the manual (e.g. BLDD/LMMR). Transcribed as printed; the Description is the normative statement of what SMMR does.
4. **SAMM RPT table, External/MMPORT cell.** Printed as "2n+2+p+p niodst" (PDF p. 377, printed p. 6-225); both extraction modes agree on the characters. The duplicated "+p" looks like a manual misprint (cf. the single-instruction cell "4+iodst"), but it is left as printed.
5. **SFRB Description names the wrong instruction.** In the SFRB description (PDF p. 393, printed p. 6-241), both shift-type sentences say "the SFR instruction produces …" where SFRB is meant. The Execution block is SFRB's own and is transcribed as printed.
6. **SFLB Execution line, unbalanced parenthesis.** The manual prints the last execution line as "(ACC(31) → C" (PDF p. 390, printed p. 6-238); the closing parenthesis is restored in the SFLB block above and the deviation is noted there.
7. **No unverified entries.** Every opcode bit row and cycle table in this range was legible in the layout extraction and cross-checked against the raw extraction where ambiguous (RETCD cycles, SAMM RPT cell, SMMR Execution block). No `[UNVERIFIED …]` markers were needed.
8. **Coverage check.** 51 instruction entries start in PDF pp. 355–442: RETC, RETCD, RETD, RETE, RETI, ROL, ROLB, ROR, RORB, RPT, RPTB, RPTZ, SACB, SACH, SACL, SAMM, SAR, SATH, SATL, SBB, SBBB, SBRK, SETC, SFL, SFLB, SFR, SFRB, SMMR, SPAC, SPH, SPL, SPLK, SPM, SQRA, SQRS, SST, SUB, SUBB, SUBC, SUBS, SUBT, TBLR, TBLW, TRAP, XC, XOR, XORB, XPL, ZALR, ZAP, ZPR. Entries starting before PDF p. 355 (RET, p. 354) and the Chapter 7 material (from PDF p. 443) are excluded, per the task range.
