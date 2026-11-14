# TMS320C5x User's Guide (SPRU056D, June 1998) — Chapter 6, §§6.1–6.2

**Source (only authority):** `~/workspace/user/files/spru056d.pdf` (SPRU056D, June 1998), Chapter 6, PDF pp. 153–178 (printed pp. 6-1–6-26).
**Scope:** §6.1 Instruction Set Symbols and Notations + §6.2 Instruction Set Summary only. §6.3 Instruction Set Descriptions (PDF p. 174 / printed p. 6-22 onward) are NOT covered here (separate worker).
**Method:** `pdftotext -layout` extraction cross-checked against 200 dpi page renders of every table page; bold mnemonics read off the renders. Opcode bit-patterns are transcribed exactly as printed, in the manual's own 4-bit groups; a row that is garbled or internally inconsistent is transcribed as printed and flagged, never silently corrected.
**Page refs:** every table heading gives BOTH the PDF index page and the printed page (e.g. PDF p. 161 / printed 6-9). The "Page" column inside Tables 6-4–6-10 is the manual's own pointer to the §6.3 description page (printed numbering).
**Conventions:** **bold mnemonic** = bold in the manual = instruction new for the 'C5x instruction set (footnote † on every summary table). `+ 1 word` = second word of a two-word opcode (16-bit constant: long immediate, program-memory address, or I/O-port / I/O-mapped-register address). Footnotes: † bold = new for 'C5x; ‡ cycle timings are for single-instruction execution, not repeat mode; § peripheral memory-mapped register access; ¶ conditions true; # condition false.

---

## 6.1 Instruction Set Symbols and Notations (PDF p. 154 / printed 6-2)

### 6.1.1 Symbols and Abbreviations Used in the Instruction Set Opcodes

#### Table 6-1. Instruction Set Opcode Symbols and Abbreviations (PDF pp. 154–155 / printed 6-2–6-3)

| Symbol | Meaning |
|---|---|
| AAA AAAA | The data memory address bits. When indirect addressing (I = 1) is being used, the seven As are the seven least significant bits (LSBs) of a data memory address. For indirect addressing, the seven As are bits that control auxiliary register manipulation (see Section 5.2, Indirect Addressing, on page 5-4). |
| ARX | A 3-bit value used in the LAR and SAR instructions to designate which auxiliary register (0–7) will be loaded (LAR) or have its contents stored (SAR). |
| BITX | A 4-bit value (called the bit code) that determines which bit of a designated data memory value will be tested by the BIT instruction. |
| CM | A 2-bit value that determines the comparison performed by the CMPR instruction. |
| I | The addressing mode bit. When I = 0, the direct addressing mode is being used. When I = 1, the indirect addressing mode is being used. |
| kkkk kkkk | An 8-bit constant used in short immediate addressing for the ADD, ADRK, LACL, LAR, RPT, SBRK, and SUB instructions. |
| k kkkk kkkk | A 9-bit constant used in short immediate addressing for the LDP instruction. |
| k kkkk kkkk kkkk | A 13-bit constant used in short immediate addressing for the MPY instruction. |
| I NTR # | The interrupt vector number. A 5-bit value representing a number from 0 to 31. The INTR instruction uses this number to change program control to one of the 32 interrupt vector addresses. |
| PM | A 2-bit value copied into the product shift mode (PM) bits of status register ST1 by the SPM instruction. |
| SHF | A 3-bit shift value for the SACH and SACL instructions. |
| SHFT | A 4-bit shift value for the ADD, AND, BSAR, LACC, OR, SUB, and XOR instructions. |
| N | A 1-bit field for the XC instruction indicating the number of instructions (one or two) to conditionally execute. If N = 0, one instruction will execute. If N = 1, two instructions will execute. |
| TP | A 2-bit value used by the conditional execution instructions to represent the following conditions: 00 = BIO̅ pin low; 01 = TC = 1; 10 = TC = 0 (NTC); 11 = None of the above conditions. |
| ZLVC ZLVC | Two 4-bit fields designating the following bit conditions to be tested and the bit states: Z = ACC = 0; L = ACC < 0; V = Overflow; C = Carry. A conditional instruction contains two of these 4-bit fields. The 4-LSB field of the instruction is a mask field. A 1 in a mask bit indicates that the corresponding condition is being tested. The second 4-bit field (bits 4–7) indicates the state of the conditions being tested. For example, to test for ACC ≥ 0, the Z and L bits of the 4-LSB field are set, while the V and C bits are not set. When the Z bit is set, it indicates to test for the condition ACC = 0; when the L bit is set, it indicates to test for the condition ACC ≥ 0. The conditions possible with these 8 bits are shown in the BCND, BCNDD, CC, CCD, RETC, RETCD, and XC instructions. To determine if the conditions are met, the 4-LSB field is ANDed with the 4-bit field containing the state of the conditions. If any bits are set, the conditions are met. |
| + 1 word | The second word of a two-word opcode. This second word contains a 16-bit constant. Depending on the instruction, this constant is a long immediate value, a program memory address, or an address for an I/O port or an I/O-mapped register. |

### 6.1.2 Symbols and Abbreviations Used in the Instruction Set Descriptions

#### Table 6-2. Instruction Set Descriptions Symbols and Abbreviations (PDF pp. 156–158 / printed 6-4–6-6)

| Symbol | Meaning |
|---|---|
| ACC | Accumulator |
| ACCB | Accumulator buffer |
| ACCH | Accumulator high byte, ACC(31–16) |
| ACCL | Accumulator low byte, ACC(15–0) |
| addr | 16-bit data memory address |
| ALU | Arithmetic logic unit |
| AR | Auxiliary register |
| ARB | Auxiliary register buffer (in ST1). This register stores the previous ARP value. |
| ARCR | Auxiliary register compare register |
| ARn | A value n from 0 to 7 designating the next auxiliary register (AR), the register that will be pointed to by the ARP when the instruction is complete |
| ARP | Auxiliary register pointer (in ST0). This register points to the current auxiliary register (AR). |
| AVIS | Address visibility bit (in PMST) |
| BIO | Branch control input |
| bit code | A 4-bit value that determines which bit of a designated data memory value will be tested by the BIT instruction. |
| BMAR | Block move address register |
| BRAF | Block repeat active flag bit (in PMST) |
| C | Carry bit (in ST1) |
| CNF | On-chip RAM configuration control bit (in ST1) |
| cond | An operand representing a condition used by instructions that execute conditionally. |
| current AR | The current auxiliary register; that is, the auxiliary register (AR) pointed to by the ARP. |
| D | Data memory address field |
| dst | Destination address field |
| DATn | Label assigned to data memory location n |
| DBMR | Dynamic bit manipulation register |
| dma | The 7 LSBs of a data memory address. |
| DP | Data memory page pointer bits (in ST0) |
| HM | Hold mode bit (in ST1) |
| ind | Indirect addressing operand (see Section 5.2, Indirect Addressing, on page 5-4.) |
| INTM | Interrupt mode flag bit (in ST0) |
| k | Short immediate operand (an 8-, 9-, or 13-bit constant) |
| K | A value from 0 to 31 indicating one of the 32 interrupt vector locations. The INTR instruction forces a branch to the location referenced by K. |
| lk | Long immediate operand (a 16-bit constant) |
| MCS | Microcall stack |
| MP/MC̅ | Microprocessor/Microcomputer bit (in PMST) |
| n | A value of 1 or 2 designating the number of words following the XC instruction. |
| OV | Overflow bit (in ST0) |
| OVLY | RAM overlay bit (in PMST) |
| OVM | Overflow mode bit (in ST0) |
| NDX | Enable extra index register bit (in PMST) |
| PA | A 16-bit address for an I/O port or an I/O-mapped register (0 ≤ PA ≤ 65535) |
| PAER | Block Repeat Program Address End Register |
| PASR | Block Repeat Program Address Start Register |
| PC | Program counter |
| PFC | Prefetch counter |
| PGMn | Label assigned to program memory location n |
| PM | Product shift mode bits (in ST1) |
| pma | A 16-bit program memory address |
| PREG | Product register |
| RAM bit | Program RAM enable bit (in PMST) |
| RPTC | Repeat counter |
| shift | A 4-bit shift value from 0–15 |
| shift2 | A 3-bit shift value from 0–7 |
| src | Source address field |
| STm | Status register m (m = 0 or 1) |
| SXM | Sign-extension mode bit (in ST1) |
| TREGn | Temporary register n (n = 0, 1, or 2) |
| TC | Test/control bit (in ST1) |
| TOS | Top of stack |
| TRM | Enable multiple TREGs bit (in PMST) |
| x | A value from 0 to 7 designating one of the eight auxiliary registers (AR0–AR7). |
| XF | XF pin status bit (in ST1) |

### 6.1.3 Notations Used in the Instruction Set Descriptions

#### Table 6-3. Instruction Set Descriptions Notations (PDF pp. 158–159 / printed 6-6–6-7)

| Notation | Meaning |
|---|---|
| x̅ | Logical inversion (1s complement) of x |
| \|x\| | Absolute value of x |
| { } | Alternative items, one of which must be entered |
| nnh | Indicates that nn represents a hexadecimal number |
| (r) | The content of register or location r. Example: (dma) means: The value at data memory address dma. |
| x→y | Value x is assigned to register or location y. Example: (dma) → ACC means: The content of the data memory address is put into the accumulator. |
| x↔y | Value x is switched with value y. Example: (ACCB) ↔ (ACC) means: The content of the accumulator buffer is switched with the content of the accumulator. |
| r(n–m) | Bits n through m of register or location r. Example: ACC(15–0) means: Bits 15 through 0 of the accumulator. |
| (r(n–m)) | The content of bits n through m of register or location r. Example: (ACC(31:16)) means: The content of bits 31 through 16 of the accumulator. |
| **Boldface Characters** | Boldface characters in an instruction syntax are to be typed as shown. Example: For the syntax: ADD dma, **16**, you may use a variety of values for dma, but the word ADD and the number 16 should be typed as shown. Samples: ADD 7h, 16; ADD X, 16. |
| *italic symbols* | Italic symbols in an instruction syntax represent variables. Example: For the syntax: ADD *dma*, you may use a variety of values for dma. Samples: ADD DAT; ADD 15. |
| # | The # symbol is a prefix for constants used in immediate addressing. For short- or long-immediate operands, it is used in instructions where there is ambiguity with other addressing modes. Example: RPT #15 uses short immediate addressing. It causes the next instruction to be repeated 16 times. RPT 15 uses direct addressing. The number of times the next instruction repeats is determined by a value stored in memory. |
| [,x] | Operand x is optional. Example: For the syntax: ADD dma, [,shift], you may use a variety of values for dma. Samples: ADD 7h; ADD 7h, 5. |
| [,x1 [,x2]] | Operands x1 and x2 are optional, but you cannot include x2 without also including x1. Example: For the syntax: ADD ind, [,shift [,ARn]], you must supply ind, as in: ADD *+; ADD *+, 5; ADD *+, 0, AR2. |

---

## 6.2 Instruction Set Summary (PDF p. 160 / printed 6-8)

Tables 6-4 through 6-10 alphabetically list the 'C5x instructions within seven functional groups. The tables assume all instructions are executed from internal program memory (ROM) and internal data memory (RAM). Cycle timings are for single-instruction execution, not for repeat mode. **Bold typeface indicates instructions that are new for the 'C5x instruction set.** Several instructions specify two values in the Words column because different forms occupy a different number of words (e.g. ADD occupies one word with a short immediate operand, two words with a long immediate operand).

### Cycle rules stated in §6.2 (PDF pp. 160–161 / printed 6-8–6-9; PDF pp. 177–178 / printed 6-25–6-26)

- **CAUTION (verbatim, PDF p. 160 / printed 6-8):** "A read or write access to any peripheral memory-mapped register in data memory locations 20h–4Fh will add one cycle to the cycle time shown. This occurs because all peripherals perform these accesses over the TI Bus, which requires an additional cycle." (This is the § footnote on LAMM, SAMM, LMMR, SMMR.)
- **External reads/writes (PDF p. 160 / printed 6-8):** "Note that all writes to external memory require two cycles. Reads require one cycle. Any write access immediately before or after a read cycle will require three cycles (refer to Chapter 8)."
- **SARAM conflict (PDF pp. 160–161 / printed 6-8–6-9):** "In addition, if two pipelined instructions try to access the same 2K-word single-access memory block simultaneously, one extra cycle is required. For example, the DMOV instruction when used with the RPT instruction, requires one cycle in the dual-access RAM but requires two cycles in the single-access RAM."
- **Wait states (PDF p. 161 / printed 6-9):** "Wait states are added to all external accesses according to the configuration of the software wait-state registers described in Section 9.4, Software-Programmable Wait-State Generators, on page 9-13."
- **External read/write with wait states (PDF p. 178 / printed 6-26, verbatim in condensed form):** "All external reads require at least one machine cycle while all external writes require at least two machine cycles. However, if an external write is immediately followed or preceded by an external read cycle, then the external write requires three cycles. See Section 8.9, External Memory Interface Timings, on page 8-39 for details. If you use an on-chip wait-state generator to add m (m>0) wait states to an external access, then both the external reads and the external writes require m+1 cycles, assuming that the external READY line is driven high. If you use the READY input line to add m additional cycles to an external access, then external reads require m+1 cycles and external write accesses require m+2 cycles. See Section 9.4, Software-Programmable Wait-State Generators, on page 9-13 and the data sheet for READY electrical specifications."
- **SARAM parallelism (PDF p. 178 / printed 6-26):** "The on-chip single-access RAM is divided into 1K- and/or 2K-word blocks contiguous in address memory space. All 'C5x processors support parallel accesses to these on-chip SARAM blocks. However, one SARAM block allows only one access per cycle. In other words, the processor can read/write on one SARAM block while accessing another SARAM block."

### Cycle-variable definitions (PDF p. 177 / printed 6-25)

Cycle counts in §6.3 are given in processor machine cycles (CLKOUT1 period). Additional wait states for program/data memory and I/O accesses can be generated by the on-chip software wait-state generator or by the external READY signal. Variables can also use the subscripts src, dst, and code to indicate source, destination, and code, respectively.

| Variable | Meaning |
|---|---|
| d | Data memory wait states. Represents the number of additional clock cycles the device waits for external data memory to respond to an access. |
| io | I/O wait states. Represents the number of additional clock cycles the device waits for an external I/O to respond to an access. |
| n | Repetitions (where n > 2 to fill the pipeline). Represents the number of times a repeated instruction is executed. |
| p | Program memory wait states. Represents the number of additional clock cycles the device waits for external program memory to respond to an access. |

Program source locations (column headings in the §6.3 cycle tables): ROM = instruction executes from on-chip program ROM; DARAM = from on-chip dual-access program RAM; SARAM = from on-chip single-access program RAM; External Memory = from external program memory. Operand locations (row headings): DARAM = operand in internal dual-access RAM; SARAM = operand in internal single-access RAM; External = operand in external memory; ROM = operand in internal program ROM; MMR = operand is a memory-mapped register; MMPORT = operand is a memory-mapped I/O port.

> NOTE (out of assigned range, for completeness): PDF p. 179 / printed 6-27 (§6.3 introductory text, not §6.2) states the assumptions behind the cycle tables: at least four instructions following the current instruction are fetched from the same memory section (on-chip or external) as the current instruction, except for instructions that cause a program counter discontinuity (B, CALL, etc.); when executing a single instruction there is no pipeline conflict between the current instruction and the immediately preceding/following instructions, the only exception being the conflict between the fetch phase of the pipeline and the memory read/write (if any) access of the instruction under consideration (see Chapter 7); in repeat execution mode, all conflicts caused by pipelined execution of that instruction are considered. It also refers to Appendix B for a summary of instruction cycle classifications.

#### Table 6-11. Address Blocks for On-Chip Single-Access RAM (PDF p. 178 / printed 6-26)

| Device | SARAM | Block size | Hex Address Range |
|---|---|---|---|
| 'C50 | 9K-word | 2K-word block | 0800–0FFF |
| 'C50 | 9K-word | 2K-word block | 1000–17FF |
| 'C50 | 9K-word | 2K-word block | 1800–1FFF |
| 'C50 | 9K-word | 2K-word block | 2000–27FF |
| 'C50 | 9K-word | 1K-word block | 2800–2BFF |
| 'C51 | 1K-word | 1K-word block | 0800–0BFF |
| 'C53/'C53S | 3K-word | 2K-word block | 0800–0FFF |
| 'C53/'C53S | 3K-word | 1K-word block | 1000–13FF |
| 'LC56 | 6K-word | 2K-word block | 0800–0FFF |
| 'LC56 | 6K-word | 2K-word block | 1000–17FF |
| 'LC56 | 6K-word | 2K-word block | 1800–1FFF |
| 'C57S/'LC57 | 6K-word | 2K-word block | 0800–0FFF |
| 'C57S/'LC57 | 6K-word | 2K-word block | 1000–17FF |
| 'C57S/'LC57 | 6K-word | 2K-word block | 1800–1FFF |

---

## Summary tables (Tables 6-4–6-10)

### Table 6-4. Accumulator Memory Reference Instructions (PDF pp. 161–164 / printed 6-9–6-12) — 63 forms, 48 mnemonics

| Mnemonic | Description | Words | Cycles | Opcode | Page |
|---|---|---|---|---|---|
| ABS | Absolute value of ACC; zero carry bit | 1 | 1 | `1011 1110 0000 0000` | 6-28 |
| **ADCB** | Add ACCB and carry bit to ACC | 1 | 1 | `1011 1110 0001 0001` | 6-30 |
| ADD | Add data memory value, with left shift, to ACC | 1 | 1 | `0010 SHFT IAAA AAAA` | 6-31 |
| ADD | Add data memory value, with left shift of 16, to ACC | 1 | 1 | `0110 0001 IAAA AAAA` | 6-31 |
| ADD | Add short immediate to ACC | 1 | 1 | `1011 1000 kkkk kkkk` | 6-31 |
| ADD | Add long immediate, with left shift, to ACC | 2 | 2 | `1011 1111 1001 SHFT` + 1 word | 6-31 |
| **ADDB** | Add ACCB to ACC | 1 | 1 | `1011 1110 0001 0000` | 6-35 |
| ADDC | Add data memory value and carry bit to ACC with sign extension suppressed | 1 | 1 | `0110 0000 IAAA AAAA` | 6-36 |
| ADDS | Add data memory value to ACC with sign extension suppressed | 1 | 1 | `0110 0010 IAAA AAAA` | 6-38 |
| ADDT | Add data memory value, with left shift specified by TREG1, to ACC | 1 | 1 | `0110 0011 IAAA AAAA` | 6-40 |
| AND | AND data memory value with ACCL; zero ACCH | 1 | 1 | `0110 1110 IAAA AAAA` | 6-43 |
| AND | AND long immediate, with left shift, with ACC | 2 | 2 | `1011 1111 1011 SHFT` + 1 word | 6-43 |
| AND | AND long immediate, with left shift of 16, with ACC | 2 | 2 | `1011 1110 1000 0001` + 1 word | 6-43 |
| **ANDB** | AND ACCB with ACC | 1 | 1 | `1011 1110 0001 0010` | 6-46 |
| **BSAR** | Barrel-shift ACC right | 1 | 1 | `1011 1111 1110 SHFT` | 6-82 |
| CMPL | 1s complement ACC | 1 | 1 | `1011 1110 0000 0001` | 6-94 |
| **CRGT** | Store ACC in ACCB if ACC > ACCB | 1 | 1 | `1011 1110 0001 1011` | 6-100 |
| **CRLT** | Store ACC in ACCB if ACC < ACCB | 1 | 1 | `1011 1110 0001 1100` | 6-102 |
| **EXAR** | Exchange ACCB with ACC | 1 | 1 | `1011 1110 0001 1101` | 6-106 |
| **LACB** | Load ACC to ACCB | 1 | 1 | `1011 1110 0001 1111` | 6-113 |
| LACC | Load data memory value, with left shift, to ACC | 1 | 1 | `0001 SHFT IAAA AAAA` | 6-114 |
| LACC | Load long immediate, with left shift, to ACC | 2 | 2 | `1011 1111 1000 SHFT` + 1 word | 6-114 |
| LACC | Load data memory value, with left shift of 16, to ACC | 1 | 1 | `0110 1010 IAAA AAAA` | 6-114 |
| LACL | Load data memory value to ACCL; zero ACCH | 1 | 1 | `0110 1001 IAAA AAAA` | 6-117 |
| LACL | Load short immediate to ACCL; zero ACCH | 1 | 1 | `1011 1001 kkkk kkkk` | 6-117 |
| LACT | Load data memory value, with left shift specified by TREG1, to ACC | 1 | 1 | `0110 1011 IAAA AAAA` | 6-120 |
| **LAMM** | Load contents of memory-mapped register to ACCL; zero ACCH | 1 | 1 or 2§ | `0000 1000 IAAA AAAA` | 6-122 |
| NEG | Negate (2s complement) ACC | 1 | 1 | `1011 1110 0000 0010` | 6-177 |
| NORM | Normalize ACC | 1 | 1 | `1010 0000 IAAA AAAA` | 6-181 |
| OR | OR data memory value with ACCL | 1 | 1 | `0110 1101 IAAA AAAA` | 6-187 |
| OR | OR long immediate, with left shift, with ACC | 2 | 2 | `1011 1111 1100 SHFT` + 1 word | 6-187 |
| OR | OR long immediate, with left shift of 16, with ACC | 2 | 2 | `1011 1110 1000 0010` + 1 word | 6-187 |
| **ORB** | OR ACCB with ACC | 1 | 1 | `1011 1110 0001 0011` | 6-190 |
| ROL | Rotate ACC left 1 bit | 1 | 1 | `1011 1110 0000 1100` | 6-210 |
| **ROLB** | Rotate ACCB and ACC left 1 bit | 1 | 1 | `1011 1110 0001 0100` | 6-211 |
| ROR | Rotate ACC right 1 bit | 1 | 1 | `1011 1110 0000 1101` | 6-212 |
| **RORB** | Rotate ACCB and ACC right 1 bit | 1 | 1 | `1011 1110 0001 0101` | 6-213 |
| **SACB** | Store ACC in ACCB | 1 | 1 | `1011 1110 0001 1110` | 6-220 |
| SACH | Store ACCH, with left shift, in data memory location | 1 | 1 | `1001 1SHF IAAA AAAA` | 6-221 |
| SACL | Store ACCL, with left shift, in data memory location | 1 | 1 | `1001 0SHF IAAA AAAA` | 6-223 |
| **SAMM** | Store ACCL in memory-mapped register | 1 | 1 or 2§ | `1000 1000 IAAA AAAA` | 6-225 |
| **SATH** | Barrel-shift ACC right 0 or 16 bits as specified by TREG1 | 1 | 1 | `1011 1110 0101 1010` | 6-229 |
| **SATL** | Barrel-shift ACC right as specified by TREG1 | 1 | 1 | `1011 1110 0101 1011` | 6-231 |
| **SBB** | Subtract ACCB from ACC | 1 | 1 | `1011 1110 0001 1000` | 6-232 |
| **SBBB** | Subtract ACCB and logical inversion of carry bit from ACC | 1 | 1 | `1011 1110 0001 1001` | 6-233 |
| SFL | Shift ACC left 1 bit | 1 | 1 | `1011 1110 0000 1001` | 6-237 |
| **SFLB** | Shift ACCB and ACC left 1 bit | 1 | 1 | `1011 1110 0001 0110` | 6-238 |
| SFR | Shift ACC right 1 bit | 1 | 1 | `1011 1110 0000 1010` | 6-239 |
| **SFRB** | Shift ACCB and ACC right 1 bit | 1 | 1 | `1011 1110 0001 0111` | 6-241 |
| SUB | Subtract data memory value, with left shift, from ACC | 1 | 1 | `0011 SHFT IAAA AAAA` | 6-259 |
| SUB | Subtract data memory value, with left shift of 16, from ACC | 1 | 1 | `0110 0101 IAAA AAAA` | 6-259 |
| SUB | Subtract short immediate from ACC | 1 | 1 | `1011 1010 kkkk kkkk` | 6-259 |
| SUB | Subtract long immediate, with left shift, from ACC | 2 | 2 | `1011 1111 1010 SHFT` + 1 word | 6-259 |
| SUBB | Subtract data memory value and logical inversion of carry bit from ACC with sign extension suppressed | 1 | 1 | `0110 0100 IAAA AAAA` | 6-263 |
| SUBC | Conditional subtract | 1 | 1 | `0000 1010 IAAA AAAA` | 6-265 |
| SUBS | Subtract data memory value from ACC with sign extension suppressed | 1 | 1 | `0110 0110 IAAA AAAA` | 6-267 |
| SUBT | Subtract data memory value, with left shift specified by TREG1, from ACC | 1 | 1 | `0110 0111 IAAA AAAA` | 6-269 |
| XOR | Exclusive-OR data memory value with ACCL | 1 | 1 | `0110 1100 IAAA AAAA` | 6-280 |
| XOR | Exclusive-OR long immediate, with left shift of 16, with ACC | 2 | 2 | `1011 1110 1000 0011` + 1 word | 6-280 |
| XOR | Exclusive-OR long immediate, with left shift, with ACC | 2 | 2 | `1011 1111 1101 SHFT` + 1 word | 6-280 |
| **XORB** | Exclusive-OR ACCB with ACC | 1 | 1 | `1011 1110 0001 1010` | 6-283 |
| ZALR | Zero ACCL and load ACCH with rounding | 1 | 1 | `0110 1000 IAAA AAAA` | 6-287 |
| ZAP | Zero ACC and PREG | 1 | 1 | `1011 1110 0101 1001` | 6-289 |

### Table 6-5. Auxiliary Registers and Data Memory Page Pointer Instructions (PDF p. 165 / printed 6-13) — 10 forms, 7 mnemonics (no bold mnemonics on this page)

| Mnemonic | Description | Words | Cycles | Opcode | Page |
|---|---|---|---|---|---|
| ADRK | Add short immediate to AR | 1 | 1 | `0111 1000 kkkk kkkk` | 6-42 |
| CMPR | Compare AR with ARCR as specified by CM bits | 1 | 1 | `1011 1111 0100 01CM` | 6-95 |
| LAR | Load data memory value to ARx | 1 | 2 | `0000 0ARX IAAA AAAA` | 6-124 |
| LAR | Load short immediate to ARx | 1 | 2 | `1011 0ARX kkkk kkkk` | 6-124 |
| LAR | Load long immediate to ARx | 2 | 2 | `1011 1111 0000 1ARX` + 1 word | 6-124 |
| LDP | Load data memory value to DP bits | 1 | 2 | `0000 1101 IAAA AAAA` | 6-127 |
| LDP | Load short immediate to DP bits | 1 | 2 | `1011 110I kkkk kkkk` — see FLAG LDP below | 6-127 |
| MAR | Modify AR | 1 | 1 | `1000 1011 IAAA AAAA` | 6-166 |
| SAR | Store ARx in data memory location | 1 | 1 | `1000 0ARX IAAA AAAA` | 6-227 |
| SBRK | Subtract short immediate from AR | 1 | 1 | `0111 1100 kkkk kkkk` | 6-234 |

### Table 6-6. Parallel Logic Unit (PLU) Instructions (PDF p. 166 / printed 6-14) — 11 forms, 7 mnemonics

| Mnemonic | Description | Words | Cycles | Opcode | Page |
|---|---|---|---|---|---|
| **APL** | AND data memory value with DBMR, and store result in data memory location | 1 | 1 | `0101 1010 IAAA AAAA` | 6-48 |
| **APL** | AND data memory value with long immediate and store result in data memory location | 2 | 2 | `0101 1110 IAAA AAAA` + 1 word | 6-48 |
| **CPL** | Compare data memory value with DBMR | 1 | 1 | `0101 1011 IAAA AAAA` | 6-97 |
| **CPL** | Compare data memory value with long immediate | 2 | 2 | `0101 1111 IAAA AAAA` + 1 word | 6-97 |
| **OPL** | OR data memory value with DBMR and store result in data memory location | 1 | 1 | `0101 1001 IAAA AAAA` | 6-184 |
| **OPL** | OR data memory value with long immediate and store result in data memory location | 2 | 2 | `0101 1101 IAAA AAAA` + 1 word | 6-184 |
| **SPLK** | Store long immediate in data memory location | 2 | 2 | `1010 1110 IAAA AAAA` + 1 word | 6-251 |
| **XPL** | Exclusive-OR data memory value with DBMR and store result in data memory location | 1 | 1 | `0101 1000 IAAA AAAA` | 6-284 |
| **XPL** | Exclusive-OR data memory value with long immediate and store result in data memory location | 2 | 2 | `0101 1100 IAAA AAAA` + 1 word | 6-284 |
| LPH | Load data memory value to PREG high byte | 1 | 1 | `0111 0101 IAAA AAAA` | 6-133 |
| LT | Load data memory value to TREG0 | 1 | 1 | `0111 0011 IAAA AAAA` | 6-138 |

NOTE: LPH and LT are printed as the last two rows of Table 6-6 in the manual (PDF p. 166 / printed 6-14), although they are TREG0/PREG loads, not PLU operations. Transcribed here under Table 6-6 as printed.

### Table 6-7. TREG0, PREG, and Multiply Instructions (PDF pp. 167–169 / printed 6-15–6-17) — 23 forms, 20 mnemonics

| Mnemonic | Description | Words | Cycles | Opcode | Page |
|---|---|---|---|---|---|
| LTA | Load data memory value to TREG0; add PREG, with shift specified by PM bits, to ACC | 1 | 1 | `0111 0000 IAAA AAAA` | 6-140 |
| LTD | Load data memory value to TREG0; add PREG, with shift specified by PM bits, to ACC; and move data | 1 | 1 | `0111 0010 IAAA AAAA` | 6-142 |
| LTP | Load data memory value to TREG0; store PREG, with shift specified by PM bits, in ACC | 1 | 1 | `0111 0001 IAAA AAAA` | 6-145 |
| LTS | Load data memory value to TREG0; subtract PREG, with shift specified by PM bits, from ACC | 1 | 1 | `0111 0100 IAAA AAAA` | 6-147 |
| MAC | Add PREG, with shift specified by PM bits, to ACC; load data memory value to TREG0; multiply data memory value by program memory value and store result in PREG | 2 | 3 | `1010 0010 IAAA AAAA` + 1 word | 6-149 |
| MACD | Add PREG, with shift specified by PM bits, to ACC; load data memory value to TREG0; multiply data memory value by program memory value and store result in PREG; and move data | 2 | 3 | `1010 0011 IAAA AAAA` + 1 word | 6-153 |
| **MADD** | Add PREG, with shift specified by PM bits, to ACC; load data memory value to TREG0; multiply data memory value by value specified in BMAR and store result in PREG; and move data | 1 | 3 | `1010 1011 IAAA AAAA` | 6-158 |
| **MADS** | Add PREG, with shift specified by PM bits, to ACC; load data memory value to TREG0; multiply data memory value by value specified in BMAR and store result in PREG | 1 | 3 | `1010 1010 IAAA AAAA` | 6-162 |
| MPY | Multiply data memory value by TREG0 and store result in PREG | 1 | 1 | `0101 0100 IAAA AAAA` | 6-168 |
| MPY | Multiply short immediate by TREG0 and store result in PREG | 1 | 1 | `110k kkkk kkkk kkk` — see FLAG MPY below | 6-168 |
| MPY | Multiply long immediate by TREG0 and store result in PREG | 2 | 2 | `1011 1110 1000 0000` + 1 word | 6-168 |
| MPYA | Add PREG, with shift specified by PM bits, to ACC; multiply data memory value by TREG0 and store result in PREG | 1 | 1 | `0101 0000 IAAA AAAA` | 6-171 |
| MPYS | Subtract PREG, with shift specified by PM bits, from ACC; multiply data memory value by TREG0 and store result in PREG | 1 | 1 | `0101 0001 IAAA AAAA` | 6-173 |
| MPYU | Multiply unsigned data memory value by TREG0 and store result in PREG | 1 | 1 | `0101 0101 IAAA AAAA` | 6-175 |
| PAC | Load PREG, with shift specified by PM bits, to ACC | 1 | 1 | `1011 1110 0000 0011` | 6-193 |
| SPAC | Subtract PREG, with shift specified by PM bits, from ACC | 1 | 1 | `1011 1110 0000 0101` | 6-246 |
| SPAC | Subtract PREG, with shift specified by PM bits, from ACC — identical row printed twice in the manual; see FLAG SPAC below | 1 | 1 | `1011 1110 0000 0101` | 6-246 |
| SPH | Store PREG high byte, with shift specified by PM bits, in data memory location | 1 | 1 | `1000 1101 IAAA AAAA` | 6-247 |
| SPL | Store PREG low byte, with shift specified by PM bits, in data memory location | 1 | 1 | `1000 1100 IAAA AAAA` | 6-249 |
| SPM | Set product shift mode (PM) bits | 1 | 1 | `1011 1111 0000 00PM` | 6-252 |
| SQRA | Add PREG, with shift specified by PM bits, to ACC; load data memory value to TREG0; square value and store result in PREG | 1 | 1 | `0101 0010 IAAA AAAA` | 6-253 |
| SQRS | Subtract PREG, with shift specified by PM bits, from ACC; load data memory value to TREG0; square value and store result in PREG | 1 | 1 | `0101 0011 IAAA AAAA` | 6-255 |
| **ZPR** | Zero PREG | 1 | 1 | `1011 1110 0101 1000` | 6-290 |

### Table 6-8. Branch and Call Instructions (PDF pp. 169–170 / printed 6-17–6-18) — 24 forms, 24 mnemonics

| Mnemonic | Description | Words | Cycles | Opcode | Page |
|---|---|---|---|---|---|
| B | Branch unconditionally to program memory location | 2 | 4 | `0111 1001 1AAA AAAA` + 1 word | 6-51 |
| BACC | Branch to program memory location specified by ACCL | 1 | 4 | `1011 1110 0010 0000` | 6-52 |
| **BACCD** | Delayed branch to program memory location specified by ACCL | 1 | 2 | `1011 1110 0010 0001` | 6-53 |
| BANZ | Branch to program memory location if AR not zero | 2 | 4¶ or 2# | `0111 1011 1AAA AAAA` + 1 word | 6-54 |
| **BANZD** | Delayed branch to program memory location if AR not zero | 2 | 2 | `0111 1111 1AAA AAAA` + 1 word | 6-56 |
| **BCND** | Branch conditionally to program memory location | 2 | 4¶ or 2# | `1110 00TP ZLVC ZLVC` + 1 word | 6-58 |
| **BCNDD** | Delayed branch conditionally to program memory location | 2 | 2 | `1111 00TP ZLVC ZLVC` + 1 word | 6-60 |
| **BD** | Delayed branch unconditionally to program memory location | 2 | 2 | `0111 1101 1AAA AAAA` + 1 word | 6-62 |
| CALA | Call to subroutine addressed by ACCL | 1 | 4 | `1011 1110 0011 0000` | 6-83 |
| **CALAD** | Delayed call to subroutine addressed by ACCL | 1 | 2 | `1011 1110 0011 1101` | 6-84 |
| CALL | Call to subroutine unconditionally | 2 | 4 | `0111 1010 1AAA AAAA` + 1 word | 6-85 |
| **CALLD** | Delayed call to subroutine unconditionally | 2 | 2 | `0111 1110 1AAA AAAA` + 1 word | 6-86 |
| **CC** | Call to subroutine conditionally | 2 | 4¶ or 2# | `1110 10TP ZLVC ZLVC` + 1 word | 6-88 |
| **CCD** | Delayed call to subroutine conditionally | 2 | 2 | `1111 10TP ZLVC ZLVC` + 1 word | 6-90 |
| **INTR** | Software interrupt that branches program control to program memory location | 1 | 4 | `1011 1110 011I NTR#` — see FLAG INTR below | 6-111 |
| NMI | Nonmaskable interrupt and globally disable interrupts (INTM = 1) | 1 | 4 | `1011 1110 0101 0010` | 6-179 |
| RET | Return from subroutine | 1 | 4 | `1110 1111 0000 0000` | 6-202 |
| **RETC** | Return from subroutine conditionally | 1 | 2 | `1110 11TP ZLVC ZLVC` | 6-203 |
| **RETCD** | Delayed return from subroutine conditionally | 1 | 4¶ or 2# | `1111 11TP ZLVC ZLVC` | 6-205 |
| RETD | Delayed return from subroutine | 1 | 2 | `1111 1111 0000 0000` | 6-207 |
| **RETE** | Return from interrupt with context switch and globally enable interrupts (INTM = 0) | 1 | 4 | `1011 1110 0011 1010` | 6-208 |
| **RETI** | Return from interrupt with context switch | 1 | 4 | `1011 1110 0011 1000` | 6-209 |
| TRAP | Software interrupt that branches program control to program memory location 22h | 1 | 4 | `1011 1110 0101 0001` | 6-277 |
| **XC** | Execute next instruction(s) conditionally | 1 | 1 | `111N 01TP ZLVC ZLVC` | 6-278 |

### Table 6-9. I/O and Data Memory Operation Instructions (PDF p. 171 / printed 6-19) — 14 forms, 10 mnemonics

| Mnemonic | Description | Words | Cycles | Opcode | Page |
|---|---|---|---|---|---|
| BLDD | Block move from data to data memory | 2 | 3 | `1010 1000 IAAA AAAA` + 1 word | 6-67 |
| BLDD | Block move from data to data memory with destination address long immediate | 2 | 3 | `1010 1001 IAAA AAAA` + 1 word | 6-67 |
| BLDD | Block move from data to data memory with source address in BMAR | 1 | 2 | `1010 1100 IAAA AAAA` | 6-67 |
| BLDD | Block move from data to data memory with destination address in BMAR | 1 | 2 | `1010 1101 IAAA AAAA` | 6-67 |
| **BLDP** | Block move from data to program memory with destination address in BMAR | 1 | 2 | `0101 0111 IAAA AAAA` | 6-73 |
| BLPD | Block move from program to data memory with source address in BMAR | 1 | 2 | `1010 0100 IAAA AAAA` | 6-76 |
| BLPD | Block move from program to data memory with source address long immediate | 2 | 3 | `1010 0101 IAAA AAAA` + 1 word | 6-76 |
| DMOV | Move data in data memory | 1 | 1 | `0111 0111 IAAA AAAA` | 6-104 |
| IN | Input data from I/O port to data memory location | 2 | 2 | `1010 1111 IAAA AAAA` + 1 word | 6-109 |
| **LMMR** | Load data memory value to memory-mapped register | 2 | 2 or 3§ | `1000 1001 IAAA AAAA` + 1 word | 6-130 |
| OUT | Output data from data memory location to I/O port | 2 | 3 | `0000 1100 IAAA AAAA` + 1 word | 6-191 |
| **SMMR** | Store memory-mapped register in data memory location | 2 | 2 or 3§ | `0000 1001 IAAA AAAA` + 1 word | 6-243 |
| TBLR | Transfer data from program to data memory with source address in ACCL | 1 | 3 | `1010 0110 IAAA AAAA` | 6-271 |
| TBLW | Transfer data from data to program memory with destination address in ACCL | 1 | 3 | `1010 0111 IAAA AAAA` | 6-274 |

### Table 6-10. Control Instructions (PDF pp. 172–173 / printed 6-20–6-21) — 34 forms, 16 mnemonics

| Mnemonic | Description | Words | Cycles | Opcode | Page |
|---|---|---|---|---|---|
| BIT | Test bit | 1 | 1 | `0100 BITX IAAA AAAA` | 6-63 |
| BITT | Test bit specified by TREG2 | 1 | 1 | `0110 1111 IAAA AAAA` | 6-65 |
| **CLRC** | Clear overflow mode (OVM) bit | 1 | 1 | `1011 1110 0100 0010` | 6-92 |
| **CLRC** | Clear sign extension mode (SXM) bit | 1 | 1 | `1011 1110 0100 0110` | 6-92 |
| **CLRC** | Clear hold mode (HM) bit | 1 | 1 | `1011 1110 0100 1000` | 6-92 |
| **CLRC** | Clear test/control (TC) bit | 1 | 1 | `1011 1110 0100 1010` | 6-92 |
| **CLRC** | Clear carry (C) bit | 1 | 1 | `1011 1110 0100 1110` | 6-92 |
| **CLRC** | Clear configuration control (CNF) bit | 1 | 1 | `1011 1110 0100 0100` | 6-92 |
| **CLRC** | Clear interrupt mode (INTM) bit | 1 | 1 | `1011 1110 0100 0000` | 6-92 |
| **CLRC** | Clear external flag (XF) pin | 1 | 1 | `1011 1110 0100 1100` | 6-92 |
| IDLE | Idle until nonmaskable interrupt or reset | 1 | 1 | `1011 1110 0010 0010` | 6-107 |
| **IDLE2** | Idle until nonmaskable interrupt or reset — low-power mode | 1 | 1 | `1011 1110 0010 0011` | 6-108 |
| LST | Load data memory value to ST0 | 1 | 2 | `0000 1110 IAAA AAAA` | 6-135 |
| LST | Load data memory value to ST1 | 1 | 2 | `0000 1111 IAAA AAAA` | 6-135 |
| NOP | No operation | 1 | 1 | `1000 1011 0000 0000` | 6-180 |
| POP | Pop top of stack to ACCL; zero ACCH | 1 | 1 | `1011 1110 0011 0010` | 6-194 |
| POPD | Pop top of stack to data memory location | 1 | 1 | `1000 1010 IAAA AAAA` | 6-196 |
| PSHD | Push data memory value to top of stack | 1 | 1 | `0111 0110 IAAA AAAA` | 6-198 |
| PUSH | Push ACCL to top of stack | 1 | 1 | `1011 1110 0011 1100` | 6-200 |
| RPT | Repeat next instruction specified by data memory value | 1 | 1 | `0000 1011 IAAA AAAA` | 6-214 |
| RPT | Repeat next instruction specified by short immediate | 1 | 2 | `1011 1011 kkkk kkkk` | 6-214 |
| RPT | Repeat next instruction specified by long immediate | 2 | 2 | `1011 1110 1100 0100` + 1 word | 6-214 |
| **RPTB** | Repeat block of instructions specified by BRCR | 2 | 2 | `1011 1110 1100 0110` + 1 word | 6-217 |
| **RPTZ** | Clear ACC and PREG; repeat next instruction specified by long immediate | 2 | 2 | `1011 1110 1100 0101` + 1 word | 6-219 |
| **SETC** | Set overflow mode (OVM) bit | 1 | 1 | `1011 1110 0100 0011` | 6-235 |
| **SETC** | Set sign extension mode (SXM) bit | 1 | 1 | `1011 1110 0100 0111` | 6-235 |
| **SETC** | Set hold mode (HM) bit | 1 | 1 | `1011 1110 0100 1001` | 6-235 |
| **SETC** | Set test/control (TC) bit | 1 | 1 | `1011 1110 0100 1011` | 6-235 |
| **SETC** | Set carry (C) bit | 1 | 1 | `1011 1110 0100 1111` | 6-235 |
| **SETC** | Set external flag (XF) pin high | 1 | 1 | `1011 1110 0100 1101` | 6-235 |
| **SETC** | Set configuration control (CNF) bit | 1 | 1 | `1011 1110 0100 0101` | 6-235 |
| **SETC** | Set interrupt mode (INTM) bit | 1 | 1 | `1011 1110 0100 0001` | 6-235 |
| SST | Store ST0 in data memory location | 1 | 1 | `1000 1110 IAAA AAAA` | 6-257 |
| SST | Store ST1 in data memory location | 1 | 1 | `1000 1111 IAAA AAAA` | 6-257 |

---

## Counts (counted from Tables 6-4–6-10 as printed)

| Table | Forms (printed rows) | Distinct mnemonics | New-for-'C5x (bold) mnemonics |
|---|---|---|---|
| 6-4 Accumulator memory reference (PDF pp. 161–164 / 6-9–6-12) | 63 | 48 | 21: ADCB, ADDB, ANDB, BSAR, CRGT, CRLT, EXAR, LACB, LAMM, ORB, ROLB, RORB, SACB, SAMM, SATH, SATL, SBB, SBBB, SFLB, SFRB, XORB |
| 6-5 Auxiliary registers / DP (PDF p. 165 / 6-13) | 10 | 7 | 0 |
| 6-6 PLU (PDF p. 166 / 6-14) | 11 | 7 | 5: APL, CPL, OPL, SPLK, XPL |
| 6-7 TREG0, PREG, multiply (PDF pp. 167–169 / 6-15–6-17) | 23 | 20 | 3: MADD, MADS, ZPR |
| 6-8 Branch and call (PDF pp. 169–170 / 6-17–6-18) | 24 | 24 | 15: BACCD, BANZD, BCND, BCNDD, BD, CALAD, CALLD, CC, CCD, INTR, RETC, RETCD, RETE, RETI, XC |
| 6-9 I/O and data memory (PDF p. 171 / 6-19) | 14 | 10 | 3: BLDP, LMMR, SMMR |
| 6-10 Control (PDF pp. 172–173 / 6-20–6-21) | 34 | 16 | 5: CLRC, IDLE2, RPTB, RPTZ, SETC |
| **Total** | **179** | **132** | **52** |

Distinct opcode patterns: 178 (179 printed rows minus the duplicated SPAC row, which is byte-identical). No mnemonic appears in more than one of Tables 6-4–6-10.

## Check against on-record derived counts — DISCREPANCY, manual wins

On-record (from `c5x_opcodes.json`, derived, not the manual): 191 forms, 122 mnemonics, 182 unique mask/value patterns.
Counted here from the manual's Tables 6-4–6-10: **179 printed forms (178 distinct patterns), 132 distinct mnemonics. Disagreement is real and explained by contamination in the derived file, not by a miscount here:**

- The derived file lists non-mnemonics as mnemonics: ACC (3 entries), AR (1), BMAR (4) — these are register/operand symbols from Table 6-2, not instructions.
- It omits 10 mnemonics that ARE in Tables 6-4–6-10: AND, B, CALL, CALLD, CALAD, CC, CCD, CPL, LTS, SBRK.
- It contains garbage bit-strings, e.g. LDP bits `PagekkkkBoldthat`, INTR bits `CallcallINTR1101` and `ZLVCthat10111110`.
- Per-mnemonic form counts diverge from the manual throughout, e.g. ADDT 4 (manual 1), APL 6 (2), INTR 6 (1), SETC 10 (8), SUB 2 (4), BLDD 2 (4), LACC 5 (3), LAR 5 (3), LDP 1 (2), MADS 2 (1), PUSH 2 (1), SFRB 2 (1), SQRA 2 (1), TBLW 2 (1), XC 2 (1), ZAP 2 (1), ZPR 2 (1), BSAR 2 (1), CALA 2 (1), LACL 1 (2), OPL 1 (2), CPL 0 (2).
- The derived 191/122/182 therefore come from a different (and corrupted) basis — evidently §6.3 syntax parsing — not from Tables 6-4–6-10. The manual's tables as transcribed here are authoritative for the summary. Related: the consolidated core audit's "160 forms" basis also differs from the 179-row summary-table count; the audit counts §6.3 description forms, a different basis. Cross-checks that DO agree with the tables: MPY #k13 is in Table 6-7, XC (single row, N bit = 1 or 2 instructions) is in Table 6-8, and the direct B/CALL forms (`0111 1001/1010 1AAA AAAA` + 1 word) are in Table 6-8.

## Flags and manual self-contradictions (all verified on page renders)

1. **FLAG SPAC (Table 6-7, PDF p. 168 / printed 6-16):** SPAC is printed twice as two identical rows — same description, 1 word, 1 cycle, opcode `1011 1110 0000 0101`, page 6-246. Both rows transcribed. Counted as 2 printed forms, 1 distinct pattern.
2. **FLAG LDP #k (Table 6-5, PDF p. 165 / printed 6-13):** opcode printed `1011 110I kkkk kkkk` — verified at 300 dpi, the character at bit 8 is a capital I, not a lowercase k. Table 6-1 defines the LDP short-immediate constant as 9 bits (`k kkkk kkkk`), so bit 8 is expected to be the MSB of k. Almost certainly a manual misprint; transcribed as printed. §6.3 LDP description (separate worker) to confirm.
3. **FLAG MPY #k13 (Table 6-7, PDF p. 168 / printed 6-16):** opcode printed `110k kkkk kkkk kkk` — verified at 300 dpi, the last group is 3 k's, giving only 15 bit-positions (12 k's). Table 6-1 defines the MPY short-immediate constant as 13 bits, which requires 13 k's (last group `kkkk`) for a 16-bit word. Almost certainly a manual misprint (missing k); transcribed as printed. §6.3 MPY description (separate worker) to confirm.
4. **FLAG INTR (Table 6-8, PDF p. 170 / printed 6-18):** opcode printed `1011 1110 011I NTR#`. Read as: bits 15–8 = `1011 1110`, bits 7–5 = `011`, bits 4–0 = `INTR#` (the 5-bit vector number; the "I" is the first glyph of the symbol name `INTR #`, cf. Table 6-1 symbol `I NTR #`). Transcribed as printed.
5. **CONTRADICTION — APAC missing from the summary tables:** APAC has a §6.3 description (PDF p. 199; "APAC is a TREG0, PREG, and multiply instruction (see Table 6–7)"), is listed in Appendix B (PDF pp. 639, 642: Class I, 1 word, 1 cycle, p. 6-47), and is used in examples elsewhere in the manual (PDF pp. 63–65, 99, 103, 110, 142) — but NO APAC row appears in Table 6-7 (PDF pp. 167–169) or in any of Tables 6-4–6-10. A scan of §6.3 Syntax headings found APAC as the only mnemonic with a §6.3 description that is absent from the summary tables. APAC's opcode/description are NOT transcribed here (out of scope — §6.3 worker).
6. **ZLVC wording quirk (Table 6-1, PDF p. 155 / printed 6-3):** the manual defines L as "ACC < 0" and then, in the worked example, says "when the L bit is set, it indicates to test for the condition ACC ≥ 0". Transcribed as printed; the example sentence is internally inconsistent with the bit definition.
7. **LPH/LT placement:** LPH and LT are printed as the last two rows of Table 6-6 (PLU instructions), PDF p. 166 / printed 6-14, although they are TREG0/PREG loads. Transcribed under Table 6-6 as printed.
8. **Cross-check with §6.3 worker (not verified here — §6.3 side is that worker's):** the §6.3 distillation reports RETC summary Table 6-8 lists 2 cycles vs §6.3 True 4 / False 2, and RETCD summary lists 4-or-2 vs §6.3 flat 2. The summary side of both claims matches this file (RETC 2, RETCD 4¶ or 2#); the §6.3 side is per the §6.3 worker's file.

## Unverified rows

None. Every row of Tables 6-4–6-10 was read from the `pdftotext -layout` extraction and visually confirmed on 200 dpi page renders (with 300 dpi crops for the LDP, MPY #k13, and INTR opcodes). No row required a `[UNVERIFIED — extraction garbled]` marker. The only oddities are the flagged literal printings above, all transcribed as printed.
