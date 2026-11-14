# Chapter 4 — Program Control (TMS320C5x User's Guide, SPRU056D)

- **Source (only authority):** `~/workspace/user/files/spru056d.pdf` — SPRU056D, June 1998, Chapter 4, PDF pp. 80–130.
- **Page mapping:** PDF p. 80 = printed p. 4-1; printed page = PDF page − 79, chapter 4 (e.g. PDF p. 116 = printed 4-37). Every claim below cites § + table/figure + both page numbers as `§X.Y, Table/Fig N–M, PDF p. A / printed B–C`.
- **Scope:** Chapter 4 only (§4.1–§4.10). Cross-references to Chapter 6 are marked **[Ch6]** and are used ONLY where the task explicitly required them (TP/ZLVC encoding) or where Chapter 4 contradicts itself and the Chapter 6 opcode description is the normative resolution (see §Contradictions). Nothing is taken from `c5x_users_guide.txt` or `c5x_opcodes.*`.
- **Conventions:** `X` in a reset-value column = undefined at reset (manual's own notation). "Read as 0/1" = hardwired value on read. **INFERENCE** = derived, not stated; kept out of tables. **[UNVERIFIED — …]** = extraction garbled/illegible; not guessed.
- **C51 note:** Chapter 4 is family-generic ('C50/'C51/'C52/'C53/'C56/'C57). Device-specific differences are flagged where the manual states them (interrupt usage, TDM/HINT naming). The Courier V.Everything DSP is a TMS320C51.

## Chapter map

| § | Topic | PDF pp. | Printed pp. |
|---|---|---|---|
| 4.1 | Program Counter (PC) | 81–82 | 4-2–4-3 |
| 4.2 | Hardware Stack | 83 | 4-4 |
| 4.3 | Program-Memory Address Generation | 84 | 4-5 |
| 4.4 | Status and Control Registers (CBCR, PMST, ST0, ST1) | 85–95 | 4-6–4-16 |
| 4.5 | Conditional Operations | 96–100 | 4-17–4-21 |
| 4.6 | Single Instruction Repeat Function | 101–109 | 4-22–4-30 |
| 4.7 | Block Repeat Function | 110–114 | 4-31–4-35 |
| 4.8 | Interrupts | 115–123 | 4-36–4-44 |
| 4.9 | Reset | 124–128 | 4-45–4-49 |
| 4.10 | Power-Down Mode | 129–130 | 4-50–4-51 |

Source: Ch. 4 contents list, PDF p. 80 / printed 4-1.

---

## 4.1 Program Counter (PC) — §4.1, PDF p. 81 / printed 4-2; Table 4–1, PDF p. 82 / printed 4-3

- 16-bit PC holds the address of internal or external program memory used to fetch instructions (§4.1, PDF p. 81 / printed 4-2).
- PC drives program memory via the program address bus (PAB); the instruction is loaded into the instruction register (IREG); the PC is then ready for the next fetch (§4.1, PDF p. 81 / printed 4-2).
- Figure 4–1 (program-control functional block diagram, PDF p. 81 / printed 4-2) shows, among others: PFC, PC, 8×16 stack, IREG, PASR, PAER, BMAR, RPTC, BRCR, ST0, ST1, PMST, IMR, IFR, GREG, TREG2; external signals CLKMD1–3, IS, DS, PS, RW, STRB, READY, BR, XF, HOLD, HOLDA, IAQ, BIO, RS, IACK, NMI, INT(1–4), MP/MC, CLKOUT1, X1, X2/CLKIN, CLKIN2, MCS, RD, WE, A15–A0, D15–D0, RBIT, DP(9). All registers and data lines are 16 bits wide unless otherwise specified (Fig. 4–1 note, PDF p. 81 / printed 4-2).

### Table 4–1. Address Loading Into the PC (§4.1, Table 4–1, PDF p. 82 / printed 4-3)

| Code operation | Address loaded into PC |
|---|---|
| Sequential code | PC + 1 |
| Branch (B) | Long immediate value directly following the branch instruction |
| Subroutine call | PC + 2 pushed onto stack, then PC ← long immediate following the call; return pops stack into PC |
| Software interrupt (INTR, TRAP, NMI) or interrupt trap | Address of the appropriate interrupt vector |
| Computed GOTO (BACC / CALA) | Contents of accumulator low byte (ACCL) |
| BLDD, BLDP, BLPD, MAC, or MACD | Long immediate address |
| BACC, BACCD, CALA, TBLR, or TBLW | Contents of ACCL |
| BLDD, BLDP, BLPD, MADD, or MADS | Contents of block move address register (BMAR) |
| End of a block repeat loop | Contents of block repeat program address start register (PASR) |
| Return instruction | Top of stack |

- **Note on the duplicated rows (as printed):** BLDD/BLDP/BLPD appear in both the long-immediate row and the BMAR row; MAC/MACD in the long-immediate row, MADD/MADS in the BMAR row. INFERENCE (not in the table): these are the two addressing forms of the same instructions — §4.3 (PDF p. 84 / printed 4-5) confirms BLPD loads the PC with the long immediate address *or* with BMAR contents, MAC/MACD load the PC with the long immediate, MADD/MADS load it with BMAR.
- In a repeat operation, once the instruction is repeated it is no longer prefetched and the PC can address program memory sequentially to fetch coefficients; MAC, MACD, MADD, MADS, BLDD, BLPD, TBLR, BLDP, TBLW use this (§4.1, PDF p. 82 / printed 4-3).

---

## 4.2 Hardware Stack — §4.2, PDF p. 83 / printed 4-4

| Property | Value |
|---|---|
| Width / depth | 16 bits wide, 8 levels deep |
| Access instructions | PUSH, POP, PSHD, POPD |
| Push behaviour | PC (or value) pushed onto top of stack (TOS); every level shifts down; bottom (8th) location is **lost**. Data is lost if more than 8 successive pushes occur before a pop. |
| Pop behaviour | Reverse; any pop after 7 sequential pops yields the value at the bottom level, then **all stack levels contain the same value**. |
| Data-memory extension | PSHD/POPD let software build a stack in data memory for nesting beyond 8 levels. |

- Stack software instructions (§4.2, PDF p. 83 / printed 4-4): POP (TOS → ACCL), POPD (TOS → data-memory address), PSHD (data-memory value → TOS), PUSH (ACCL → TOS).
- Automatic push on call or interrupt (§4.2, PDF p. 83 / printed 4-4): call instructions CALA, CALAD, CALL, CALLD, CC, CCD; interrupt sources hardware interrupt, NMI, INTR, TRAP — return address automatically saved (a PUSH).
- Automatic pop on return (§4.2, PDF p. 83 / printed 4-4): RET, RETC, RETCD, RETD, RETE, RETI — return address retrieved (a POP) and loaded into PC.
- The stack is also used for the PC save during interrupts (§4.8.8, PDF p. 121 / printed 4-42); subroutine calls inside an ISR are supported as long as the 8-level stack is not exceeded.

---

## 4.3 Program-Memory Address Generation — §4.3, PDF p. 84 / printed 4-5

- Program memory holds application code, table information and immediate operands; it is accessed via the program bus. The address for the bus is generated by the PC for instructions and long immediate operands (§4.3, PDF p. 84 / printed 4-5).
- Fetch: PC is put on the PAB and the location is read; while the read executes, the PC is incremented for the next fetch. On a program-address discontinuity (branch, call, return, interrupt, block repeat) the appropriate address is loaded into the PC (§4.3, PDF p. 84 / printed 4-5).
- The PC can also be loaded when operands are fetched from program memory: TBLR/TBLW (table read/write), BLPD/BLDP (data↔program block transfers). MAC, MACD, MADD, MADS use the program bus to fetch a second multiplicand (§4.3, PDF p. 84 / printed 4-5).
- The PC can address data stored in either program or data space, so that within repeated instructions a second operand can be fetched in parallel with the data bus for 2-operand operations; for repeated instructions the array is sequentially accessed by the PAB by incrementing the PC (§4.3, PDF p. 84 / printed 4-5).
- Block transfers BLDD, BLDP, BLPD use both buses so the pipeline can read the next operand while writing the current one. BLPD loads the PC with the long immediate address or BMAR contents, then uses the program bus to fetch source data; BLDP is the same except the PAB is used for the destination; BLDD uses the PAB to address data space (§4.3, PDF p. 84 / printed 4-5).
- TBLR/TBLW operate like BLPD/BLDP respectively, except the PC is loaded with ACCL instead of the long immediate or BMAR — this allows lookup-table operations (§4.3, PDF p. 84 / printed 4-5).
- MAC/MACD load the PC with the long immediate address following the instruction; MADD/MADS load the PC with BMAR contents (§4.3, PDF p. 84 / printed 4-5).
- **Terminology slip (as printed):** §4.3 first sentence calls the program address bus "(PB)"; §4.1 and the rest of §4.3 call it PAB. PB elsewhere is the program (data) bus. Treat PAB as normative (it matches Fig. 4–1 and §4.1).

---

## 4.4 Status and Control Registers — §4.4, PDF pp. 85–95 / printed 4-6–4-16

Four registers (§4.4, PDF p. 85 / printed 4-6):

| Register | Memory-mapped? | Access |
|---|---|---|
| CBCR — Circular Buffer Control Register | Yes, data-memory page 0 | Like any data-memory location; CALU and PLU can act on it directly |
| PMST — Processor Mode Status Register | Yes, data-memory page 0 | Like any data-memory location; CALU and PLU can act on it directly |
| ST0 — Status Register 0 | **No** — not in the memory map | LST/SST only; PLU instructions cannot be used on it |
| ST1 — Status Register 1 | **No** — not in the memory map | LST/SST only; PLU instructions cannot be used on it |

- CBCR/PMST: CALU and PLU operations change the bits during the execution phase of the pipeline; **the next two instructions after a status-register update must not be affected by the reconfiguration** caused by the update. Required latencies are in Table 7–10 (PDF p. 85–86 / printed 4-6–4-7; Table 7–10 itself is Ch. 7, p. 7-24).
- PMST, ST0, ST1 each have an associated **1-level-deep shadow register stack** for automatic context save on an interrupt trap; automatically restored on RETI or RETE (§4.4.2, PDF p. 86 / printed 4-7; §4.4.3, PDF p. 89 / printed 4-10). See also §4.8.8.
- ST0/ST1: LST writes, SST reads. **INTM (ST0) and XF (ST1) are NOT saved on the shadow stack or restored from it on an automatic context save** (§4.4.3, PDF p. 89 / printed 4-10; §4.8.8, PDF p. 121 / printed 4-42). This lets the XF pin be toggled inside an ISR.
- SETC/CLRC set/clear individual bits: INTM, OVM (ST0); C, CNF, HM, SXM, TC, XF (ST1). DP bits (ST0) loaded with LDP; PM bits (ST1) loaded with SPM (§4.4.3, PDF p. 89 / printed 4-10).
- **CBCR/PMST data-memory addresses are NOT stated in Chapter 4** (only "memory-mapped register space of data memory page 0"). IFR = 06h and IMR = 04h are stated in §4.8. Do not infer CBCR/PMST addresses from this chapter.

### 4.4.1 CBCR — Circular Buffer Control Register (§4.4.1, Fig. 4–2 + Table 4–2, PDF p. 86 / printed 4-7)

Figure 4–2 bit layout (PDF p. 86 / printed 4-7; box-drawing glyphs garbled in extraction, bit ranges and field names recovered from the raw text layer and confirmed against Table 4–2):

```
15–8        7      6–4    3      2–0
Reserved    CENB2  CAR2   CENB1  CAR1
```

| Bit | Name | Reset | Function |
|---|---|---|---|
| 15–8 | Reserved | — | Reserved. |
| 7 | CENB2 | 0 | Circular buffer 2 enable. 0 = disabled; 1 = enabled. |
| 6–4 | CAR2 | — | Circular buffer 2 auxiliary-register bits. Select which AR (AR0–AR7) is assigned to circular buffer 2. |
| 3 | CENB1 | 0 | Circular buffer 1 enable. 0 = disabled; 1 = enabled. |
| 2–0 | CAR1 | — | Circular buffer 1 auxiliary-register bits. Select which AR (AR0–AR7) is assigned to circular buffer 1. |

- **Warning (as printed):** "Do not use the same AR to access both circular buffers or unexpected results will occur." (§4.4.1, PDF p. 85 / printed 4-6).
- Reset: CENB1 → 0, CENB2 → 0 (Table 4–15, PDF p. 125 / printed 4-46). CAR1/CAR2 reset values are not specified in Ch. 4 (shown "—" in Table 4–2; not listed in Table 4–15) — treat as undefined at reset.

### 4.4.2 PMST — Processor Mode Status Register (§4.4.2, Fig. 4–3 + Table 4–3, PDF pp. 87–88 / printed 4-8–4-9)

Figure 4–3 bit layout (PDF p. 87 / printed 4-8; field names/values recovered from raw text layer, confirmed against Table 4–3):

```
15–11   10–8    7     6    5     4    3      2    1    0
IPTR    0       AVIS  0    OVLY  RAM  MP/MC  NDX  TRM  BRAF
```

| Bit | Name | Reset | Function |
|---|---|---|---|
| 15–11 | IPTR | 00000 | Interrupt vector pointer. Selects any of 32 2K-word pages where the interrupt vectors reside. Vectors can be remapped to RAM for boot-loaded operation by loading IPTR. At reset IPTR is cleared, so the reset vector always resides at address 0h in program memory space. |
| 10–8 | — | 000 | Read as 0. |
| 7 | AVIS | 0 | Address visibility. 0 = internal program address is driven to the pins (address can be traced; interrupt vector can be decoded with IACK when vectors reside in on-chip memory). 1 = address lines do not change with the internal program address; control/data lines unaffected; address bus driven with the last address on the bus. |
| 6 | — | 0 | Read as 0. |
| 5 | OVLY | 0 | RAM overlay. Enables/disables on-chip SARAM addressable in data memory space; used with RAM bit (Table 4–4). 0 = SARAM not addressable in data space; 1 = mapped into data space. |
| 4 | RAM | 0 | Program RAM enable. Enables/disables on-chip SARAM addressable in program memory space; used with OVLY bit (Table 4–4). 0 = not addressable in program space; 1 = mapped into program space. |
| 3 | MP/MC | † (pin) | Microprocessor/microcomputer. Enables/disables on-chip ROM addressable in program memory space. At reset set to the logic level on the MP/MC pin (sampled at reset only; no effect until next reset). 0 = on-chip ROM mapped into program space; 1 = on-chip ROM not addressable in program space. |
| 2 | NDX | 0 | Enable extra index register. 0 = 'C2x-compatible mode: any 'C2x-compatible instruction that modifies/writes AR0 also modifies/writes INDX and ARCR ('C2x uses AR0 for indexing and AR compare). 1 = 'C5x-enhanced mode: 'C2x-compatible instructions do not affect INDX and ARCR; they affect only AR0. |
| 1 | TRM | 0 | Enable multiple TREGs. 0 = 'C2x-compatible mode: any 'C2x-compatible instruction that loads TREG0 also loads TREG1 and TREG2 ('C2x uses TREG as shift count for the prescaling shifter and as bit address in BITT). 1 = 'C5x-enhanced mode: 'C2x-compatible instructions do not load TREG1/TREG2; they affect only TREG0. |
| 0 | BRAF | 0 | Block repeat active flag. 0 = block repeat deactivated; cleared when BRCR decrements below 0. 1 = block repeat active; automatically set when an RPTB instruction executes. Can be set/cleared via PMST (see §4.7). |

† MP/MC reset value is the logic level of the MP/MC pin (Table 4–3 footnote, PDF p. 88 / printed 4-9).

#### Table 4–4. On-Chip RAM Configuration Using OVLY and RAM Bits (§4.4.2, Table 4–4, PDF p. 89 / printed 4-10)

| OVLY | RAM | On-chip SARAM configuration |
|---|---|---|
| 0 | 0 | Disabled. Not addressable. |
| 0 | 1 | Mapped into program space. |
| 1 | 0 | Mapped into data space. |
| 1 | 1 | Mapped into both program and data spaces. |

### 4.4.3 ST0 — Status Register 0 (§4.4.3, Fig. 4–4 + Table 4–5, PDF pp. 90–91 / printed 4-11–4-12)

Figure 4–4 bit layout (PDF p. 90 / printed 4-11):

```
15–13  12  11   10  9     8–0
ARP    OV  OVM  1   INTM  DP
```

| Bit | Name | Reset | Function |
|---|---|---|---|
| 15–13 | ARP | X | Auxiliary register pointer. Selects the AR used in indirect addressing. When ARP is loaded, the previous ARP value is copied to ARB (ST1) — **except when using LST #0** (see Contradiction C1). ARP can be modified by memory-reference instructions in indirect addressing, and by MAR or LST #0. When LST #1 executes, ARP is loaded with the same value as ARB. |
| 12 | OV | 0 | Overflow flag. Indicates an ALU arithmetic-operation overflow. Latched: remains set once set. Can be modified by LST #0. 0 = no overflow (cleared by reset or by a conditional branch BCND/BCNDD on OV/NOV); 1 = overflow occurred. |
| 11 | OVM | X | Overflow mode. Enables/disables accumulator overflow saturation in the ALU. Can be modified by LST #0. 0 = disabled: overflowed result loaded into ACC unmodified (CLRC OVM clears). 1 = saturation mode: overflowed result loaded as most positive (00 7FFF FFFFh) or most negative (FF 8000 0000h) (SETC OVM sets). |
| 10 | — | 1 | Read as 1. |
| 9 | INTM | 1 | Interrupt mode. Globally masks/enables all interrupts; no effect on nonmaskable RS and NMI. Unaffected by TRAP and LST #0 (but see Contradiction C2 on TRAP). **Not saved on the shadow stack or restored from it** on an automatic context save. 0 = all unmaskable interrupts enabled (CLRC INTM or RETE clears); 1 = all maskable interrupts disabled (SETC INTM or INTR sets; also set by RS and IACK signal, or when a maskable interrupt trap is taken). |
| 8–0 | DP | X | Data-memory page pointer. Concatenated with the 7 LSBs of an instruction word to form a 16-bit direct memory address. Can be modified by LST #0 or LDP. |

- Note the manual's own wording "All unmaskable interrupts are enabled" for INTM = 0 (Table 4–5, PDF p. 91 / printed 4-12) — as printed; context shows it means maskable interrupts.
- Reset (Table 4–15, PDF p. 125 / printed 4-46): INTM → 1, OV → 0. ARP, OVM, DP are **not** listed in Table 4–15, so they remain undefined at reset (consistent with reset value X).

### 4.4.3 ST1 — Status Register 1 (§4.4.3, Fig. 4–5 + Table 4–6, PDF pp. 92–94 / printed 4-13–4-15)

Figure 4–5 bit layout (PDF p. 92 / printed 4-13):

```
15–13  12   11  10   9  8–7  6   5  4   3–2  1–0
ARB    CNF  TC  SXM  C   11  HM  1   XF  11   PM
```

| Bit | Name | Reset | Function |
|---|---|---|---|
| 15–13 | ARB | XXX | Auxiliary register buffer. Holds the previous ARP value. Whenever ARP is loaded, the previous ARP is copied to ARB, except when using LST #0. When ARB is loaded using LST #1, the same value is also copied to ARP (useful for restoring context without the automatic context save in a subroutine that modifies ARP). Can be modified by LST #1. |
| 12 | CNF | 0 | On-chip RAM configuration control. Enables DARAM block B0 addressable in data or program memory space. Can be modified by LST #1. 0 = DARAM B0 mapped into data space (cleared by reset or CLRC CNF); 1 = mapped into program space (SETC CNF sets). |
| 11 | TC | X | Test/control flag. Stores results of ALU or PLU test-bit operations. Affected by APL, BIT, BITT, CMPR, CPL, NORM, OPL, XPL. Determines whether conditional branch/call/return instructions execute. Can be modified by LST #1. TC = 0: cleared by CLRC TC, or (a) result of logical operation is **1** when tested by APL/OPL/XPL; (b) bit tested by BIT/BITT is 0; (c) compare condition false when tested by CMPR/CPL; (d) XOR result false when tested by NORM. TC = 1: set by SETC TC, or (a) result of logical operation is **0** when tested by APL/OPL/XPL; (b) bit tested by BIT/BITT is 1; (c) compare condition true when tested by CMPR/CPL; (d) XOR result true when tested by NORM. |
| 10 | SXM | 1 | Sign-extension mode. Enables/disables sign extension of an arithmetic operation. Does **not** affect ADDC, ADDS, SUBB, SUBS (these suppress sign extension regardless of SXM). Can be modified by LST #1. 0 = sign extension suppressed (CLRC SXM); 1 = sign extension produced on data passed into ACC through the scaling shifter (set by reset or SETC SXM). |
| 9 | C | 1 | Carry. Indicates ALU arithmetic carry/borrow. Single-bit shift/rotate instructions affect C. Can be modified by LST #1. C = 0: subtraction generated a borrow, or addition (except ADD with 16-bit shift) did not generate a carry; ADD with 16-bit shift can only **set** the bit, otherwise unaffected (CLRC C clears). C = 1: addition generated a carry, or subtraction (except SUB with 16-bit shift) did not generate a borrow; SUB with 16-bit shift can only **clear** the bit, otherwise unaffected (set by reset or SETC C). |
| 8–7 | — | 11 | Read as 1. |
| 6 | HM | 1 | Hold mode. Determines whether the CPU stops or continues when acknowledging an active HOLD signal. Can be modified by LST #1. 0 = CPU continues execution from on-chip program memory but puts its external interface in high-impedance (CLRC HM); 1 = CPU halts internal execution (set by reset or SETC HM). See §4.10.3. |
| 5 | — | 1 | Read as 1. |
| 4 | XF | 1 | XF pin status. Determines the level of the external XF output pin. Can be modified by LST #1. **Not saved or restored from the shadow stack** on an automatic context save during ISRs. 0 = XF pin low (CLRC XF); 1 = XF pin high (set by reset or SETC XF). |
| 3–2 | — | 11 | Read as 1. |
| 1–0 | PM | 00 | Product shift mode. Determines P-SCALER mode/shift for PREG output into the ALU. Can be set by SPM or LST #1. See Table 4–7. PM shifts also occur when PREG contents are stored to data memory; PREG contents remain unchanged during the shifts. |

#### Table 4–7. Product Shifter Mode as Determined by PM Bits (§4.4.3, Table 4–7, PDF p. 95 / printed 4-16)

| PM bit 1 | PM bit 0 | P-SCALER mode for PREG output |
|---|---|---|
| 0 | 0 | No shift. |
| 0 | 1 | Left-shifted 1 bit; LSB zero-filled. |
| 1 | 0 | Left-shifted 4 bits; 4 LSBs zero-filled. |
| 1 | 1 | Right-shifted 6 bits; sign extended; 6 LSBs lost. Product is always sign extended, regardless of SXM. |

- Reset (Table 4–15, PDF p. 125 / printed 4-46): C → 1, CNF → 0, HM → 1, PM → 0, SXM → 1, XF → 1. TC and ARB are **not** listed in Table 4–15, so they remain undefined at reset (consistent with reset value X / XXX).

---

## 4.5 Conditional Operations — §4.5, PDF pp. 96–100 / printed 4-17–4-21

### Table 4–8. Conditions for Branch, Call, and Return Instructions (§4.5, Table 4–8, PDF p. 96 / printed 4-17)

| Mnemonic | Condition | Description |
|---|---|---|
| EQ | ACC = 0 | Accumulator equal to 0 |
| NEQ | ACC ≠ 0 | Accumulator not equal to 0 |
| LT | ACC < 0 | Accumulator less than 0 |
| LEQ | ACC ≤ 0 | Accumulator less than or equal to 0 |
| GT | ACC > 0 | Accumulator greater than 0 |
| GEQ | ACC ≥ 0 | Accumulator greater than or equal to 0 |
| NC | C = 0 | Carry bit cleared |
| C | C = 1 | Carry bit set |
| NOV | OV = 0 | No accumulator overflow detected |
| OV | OV = 1 | Accumulator overflow detected |
| BIO | BIO is low | BIO signal is low |
| NTC | TC = 0 | Test/control flag cleared |
| TC | TC = 1 | Test/control flag set |
| UNC | none | Unconditional operation |

### 4.5.1 Conditional Branch — BCND (§4.5.1, PDF p. 96 / printed 4-17)

- BCND is a 2-word instruction. Conditions are not stable until the **fourth cycle** of the branch instruction's pipeline execution, because the previous instruction must have completely executed for the accumulator status bits to be accurate; the pipeline controller stops decode of following instructions until the conditions are valid.
- **Taken: 4 cycles** (pipeline flushed; PC ← second word; pipeline refills at branch address). **Not taken: 2 cycles** (next instruction, already fetched, is decoded).

### 4.5.2 Conditional Call — CC (§4.5.2, PDF p. 97 / printed 4-18)

- CC is a 2-word instruction. Operates like BCND, except the PC pointing to the instruction following the CC is **pushed onto the stack**; RET pops the stack to return. A subroutine can have multiple return paths depending on data.

### 4.5.3 Conditional Return — RETC (§4.5.3, PDF p. 97 / printed 4-18)

- RETC avoids conditionally branching around a return. 1-word instruction, but because of the potential PC discontinuity it operates with the **same effective execution time as BCND and CC** (4 cycles taken / 2 not taken — see Example 4–1, PDF p. 97 / printed 4-18: CC OVER_FLOW,OV then RETC GEQ inside the overflow handler, RET at the end).

### 4.5.4 Multiconditional Instructions (§4.5.4, PDF pp. 97–98 / printed 4-18–4-19)

- All defined conditions must be met. Instructions that test multiple conditions: **BCND, BCNDD, CC, CCD, RETC, RETCD, XC** (§4.5.4, PDF p. 97 / printed 4-18).
- Up to four conditions may be combined, **each from a different group**; two conditions from the same group are not allowed (e.g. EQ + TC allowed; NEQ + GEQ not allowed) (§4.5.4, PDF p. 98 / printed 4-19).

#### Table 4–9. Groups for Multiconditional Instructions (§4.5.4, Table 4–9, PDF p. 98 / printed 4-19)

| Group 1 (ACC) | Group 2 (OV) | Group 3 (C) | Group 4 (TC/BIO) |
|---|---|---|---|
| EQ | OV | C | TC |
| NEQ | NOV | NC | NTC |
| GT | | | BIO |
| LT | | | |
| GEQ | | | |
| LEQ | | | |

- Example (as printed, §4.5.4, PDF p. 98 / printed 4-19): `BCND BRANCH,LT,NOV,TC` — branch if ACC < 0 AND OV = 0 AND TC = 1.

### 4.5.5 Delayed Conditional Branches, Calls, and Returns (§4.5.5, PDF pp. 98–99 / printed 4-19–4-20)

- Delayed variants: **BCNDD, CCD, RETCD** (and unconditional delayed B/BD, BACC/BACCD, BANZ/BANZD, CALA/CALAD, CALL/CALLD, RETD — see Table 4–13).
- The **one 2-word instruction or two 1-word instructions following** a delayed instruction are executed while the instructions at/after the branch address are being fetched — effective **2-cycle branch** instead of flushing the pipeline. If the instruction following is 2 words, only that 2-word instruction executes before the branch is taken.
- Conditions tested are **not affected** by the instructions following the delayed branch (Example 4–2 vs 4–3, PDF pp. 98–99 / printed 4-19–4-20): Ex. 4–2 (OPL then BCND) = 6 cycles (2 OPL + 4 BCND); Ex. 4–3 (BCNDD then OPL) = 4 cycles (2 dead cycles filled by OPL; condition unaffected by OPL).

### 4.5.6 Conditional Execution — XC (§4.5.6, PDF pp. 99–100 / printed 4-20–4-21)

- Two forms: **XC 1** (conditionally execute a 1-word instruction) and **XC 2** (conditionally execute one 2-word instruction or two 1-word instructions). Conditions are the same as Table 4–8 (§4.5.6, PDF p. 99 / printed 4-20).
- If the condition is met, the following instruction(s) execute; if not, a **NOP** is executed instead (§4.5.6, PDF p. 99 / printed 4-20). Example 4–4 (BCND) = 6 cycles (4 BCND + 1 ADD + 1 APAC); Example 4–5 (XC 1,C) = 3 cycles (1 XC + 1 ADD + 1 APAC).
- **Stability rule:** the condition must be **stable one full cycle before** the XC instruction executes, so the decision is made before the instruction following XC is decoded. Avoid changing the XC test conditions in the 1-word instruction before XC (§4.5.6, PDF p. 100 / printed 4-21).
- **Interrupt hazard:** if no interrupts occur, the preceding instruction has no effect on XC; if an interrupt occurs, it can trap between the instruction and XC, changing the condition before XC executes (§4.5.6, PDF p. 100 / printed 4-21).
- Example 4–6 (unstable, PDF p. 100 / printed 4-21): `LACL #0; ADD TEMP1; XC 2,EQ; SPLK #0EEEEh,TEMP2` — the NEQ status from the 1-cycle ADD is not established in time, so the previous EQ status (from LACL) decides: condition met, SPLK executes. An interrupt trapping before XC and after ADD prevents SPLK from executing.
- Example 4–7 (stable, PDF p. 100 / printed 4-21): `LACL #0; ADD #01234h; XC 2,EQ; SPLK #0EEEEh,TEMP2` — the 2-cycle ADD (long immediate) establishes NEQ one full cycle before XC, so the condition is not met, a NOP executes instead, TEMP2 is unmodified. An interrupt has no effect on this sequence.

### TP / ZLVC condition-code encoding — NOT in Chapter 4 [Ch6 cross-reference]

- Chapter 4 Table 4–8 gives only condition mnemonics. The bit-level encoding (TP field + two ZLVC fields) is defined in Chapter 6, §6.1 "Instruction Set Symbols and Notations" (PDF p. 155 / printed 6-3) and used in the opcode formats of BCND, BCNDD, CC, CCD, RETC, RETCD, XC (Ch. 6 instruction-set summary, PDF pp. 169–170 / printed 6-17–6-18):
  - **TP** — 2-bit field for the conditional-execution instructions: `00` = BIO pin low; `01` = TC = 1; `10` = TC = 0 (NTC); `11` = none of the above conditions.
  - **ZLVC ZLVC** — two 4-bit fields for the bit conditions Z (ACC = 0), L (ACC < 0), V (overflow), C (carry). The 4-LSB field is a **mask**: a 1 in a mask bit means that condition is tested. The second 4-bit field (bits 4–7) gives the **desired state** of the conditions tested. E.g. to test ACC ≥ 0, set the Z and L mask bits and clear V/C mask bits; the conditions are met when the masked state field matches. (Full rules are in the BCND/CC/RETC/XC instruction descriptions, Ch. 6.)
  - Opcode shapes (Ch. 6 summary, PDF pp. 169–170 / printed 6-17–6-18): BCND `1110 00TP ZLVC ZLVC`; BCNDD `1111 00TP ZLVC ZLVC`; CC `1110 10TP ZLVC ZLVC`; CCD `1111 10TP ZLVC ZLVC`; RETC `1110 11TP ZLVC ZLVC`; RETCD `1111 11TP ZLVC ZLVC`; XC `111N 01TP ZLVC ZLVC`.

---

## 4.6 Single Instruction Repeat Function — §4.6, PDF pp. 101–109 / printed 4-22–4-30

- A single instruction is repeated **N + 1 times**, where N is loaded into the 16-bit repeat counter register (RPTC) by RPT or RPTZ. **Maximum executions: 65,536** (§4.6, PDF p. 101 / printed 4-22).
- RPTC **cannot be programmed**; it is cleared by reset and loaded only by RPT or RPTZ. RPTC decrements each time the instruction executes until it equals 0 (§4.6, PDF p. 101 / printed 4-22).
- **Interrupt masking during repeat:** once a repeat instruction is decoded, **all interrupts, including NMI (but not RS), are masked until the repeat loop completes**. The 'C5x still responds to HOLD while executing a repeat loop (§4.6, PDF p. 101 / printed 4-22; see also §4.8.9).
- RPTC is a memory-mapped register, but **writing to it should be avoided** — it can cause undesired results (§4.6, PDF p. 101 / printed 4-22).
- Multi-cycle instructions become effectively single-cycle after the first iteration when repeated (pipelined); absolute program/data addresses are auto-incremented. E.g. TBLR needs ≥3 cycles singly, but in repeat a table location can be read every cycle (§4.6, PDF p. 101 / printed 4-22).
- RPTZ clears ACC and PREG and repeats the next instruction specified by a long immediate; RPT repeats the next instruction specified by a data-memory value (Table 4–13, PDF p. 109 / printed 4-30).
- **Bold typeface in Tables 4–10–4–13 indicates instructions new for the 'C5x** (table footnotes). [UNVERIFIED — which entries are bold is lost in text extraction; the lists below do not mark it.]

### Table 4–10. Multi-cycle Instructions Transformed Into Single-Cycle Instructions by the Repeat Function (§4.6, Table 4–10, PDF p. 102 / printed 4-23)

| Mnemonic | Description |
|---|---|
| BLDD | Block move from data to data memory |
| BLDP | Block move from data to program memory with destination address in BMAR |
| BLPD | Block move from program to data memory |
| IN | Input data from I/O port to data memory location |
| MAC | Add PREG, with shift specified by PM bits, to ACC; load data memory value to TREG0; multiply data memory value by program memory value and store result in PREG |
| MACD | As MAC, and move data |
| MADD | Add PREG, with shift specified by PM bits, to ACC; load data memory value to TREG0; multiply data memory value by value specified in BMAR and store result in PREG; and move data |
| MADS | As MADD, without the move |
| OUT | Output data from data memory location to I/O port |
| TBLR | Transfer data from program to data memory with source address in ACCL |
| TBLW | Transfer data from data to program memory with destination address in ACCL |

### Table 4–11. Repeatable Instructions (§4.6, Table 4–11, PDF pp. 103–105 / printed 4-24–4-26)

ADCB, ADD, ADDB, ADDC, ADDS, ADDT, APAC, APL, BLDD, BLDP, BLPD, BSAR, DMOV, IN, LMMR, LTA, LTD, LTS, MAC, MACD, MADD, MADS, MPYA, MPYS, MAR, NOP, NORM, OPL, OUT, POP, POPD, PSHD, PUSH, ROL, ROLB, ROR, RORB, SACH, SACL, SAMM, SAR AR,{ind}, SATH, SATL, SBB, SBBB, SFL, SFLB, SFR, SFRB, SMMR, SPAC, SPH, SPL, SQRA, SQRS, SST, SUB, SUBB, SUBC, SUBS, SUBT, TBLR, TBLW, XPL. (64 mnemonics; descriptions as in Table 4–11 — e.g. LTA/LTD/LTS load TREG0 and add/subtract PREG; MPYA/MPYS multiply by TREG0 with PREG add/subtract; SQRA/SQRS square; SUBC conditional subtract; SAR has two forms — indirect `SAR AR,{ind}` is repeatable, direct `SAR AR,dma` is not, see Table 4–12.)

### Table 4–12. Instructions Not Meaningful to Repeat (§4.6, Table 4–12, PDF pp. 106–107 / printed 4-27–4-28)

ABS, AND, ANDB, BIT, BITT, CLRC, CMPL, CMPR, CPL, CRGT, CRLT, EXAR, LACB, LACC, LACL, LACT, LAMM, LAR, LDP, LPH, LST, LT, LTP, MPY, MPYU, NEG, OR, ORB, PAC, SACB, SAR AR,dma, SETC, SPM, XOR, XORB, ZALR, ZAP, ZPR. (38 mnemonics.)

### Table 4–13. Nonrepeatable Instructions (§4.6, Table 4–13, PDF pp. 108–109 / printed 4-29–4-30)

ADD #k, ADD #lk,shift, ADRK, AND #lk,shift, APL #lk, B, BACC, BACCD, BANZ, BANZD, BCND, BCNDD, BD, CALA, CALAD, CALL, CALLD, CC, CCD, CPL #lk, IDLE, IDLE2, INTR, LACC #lk,shift, LACL #k, LAR #k, LAR #lk, LDP #k, MPY #k, MPY #lk, NMI, OPL #lk, OR #lk,shift, RET, RETC, RETCD, RETD, RETE, RETI, RPT, RPTB, RPTZ, SBRK, SPLK #lk, SUB #k, SUB #lk,shift, TRAP, XC, XOR #lk,shift, XPL #lk. (50 mnemonics.)

- **Agent note:** RPT is itself nonrepeatable, and repeating a branch/call/return/IDLE/RPTB/XC is prohibited by this table — a repeat count must never be applied to them. The repeatable list is the whitelist; Tables 4–12/4–13 are the exclusion lists. LST is "not meaningful to repeat" (Table 4–12), not nonrepeatable — but repeating it is pointless per the manual.

---

## 4.7 Block Repeat Function — §4.7, PDF pp. 110–114 / printed 4-31–4-35

- A block of instructions is repeated **N + 1 times**, N loaded into the 16-bit block repeat counter register (BRCR) by the RPTB instruction. **Maximum executions: 65,536.** Provides no-overhead looping for FOR/DO loops (§4.7, PDF p. 110 / printed 4-31).
- Controlled by three registers (PASR, PAER, BRCR) and the BRAF bit in PMST. BRAF can be set/cleared via PMST (§4.7, PDF p. 110 / printed 4-31).
- On RPTB execution (§4.7, PDF p. 110 / printed 4-31): BRAF is set automatically; **PASR ← address of the instruction following RPTB**; **PAER ← RPTB's long immediate operand** = address of the instruction following the last loop instruction, minus 1. The block **must contain at least three instruction words**.
- Loop-end test (§4.7, PDF p. 110 / printed 4-31): with each PC update, PAER is compared to the PC. If equal, BRCR is compared to 0: if BRCR > 0, BRCR is decremented and PASR is loaded into the PC (loop restarts); if BRCR = 0, BRAF is cleared and execution resumes past the end of the loop.
- Example 4–8 (§4.7, PDF p. 110 / printed 4-31): `SPLK #0Fh,BRCR` (15) then `RPTB END_LOOP–1` gives **16 executions** of Y = aX² + bX + c, saving the maximum in ACCB. PAER is loaded with the address of the last word; the label END_LOOP is placed after the last instruction and the RPTB operand is END_LOOP–1, in case the last word is a 2-word instruction.

### 4.7.1 Context Save and Restore Used With Block Repeat (§4.7.1, PDF pp. 111–112 / printed 4-32–4-33)

- **Only one set of block-repeat registers exists**, so multiple block repeats cannot be nested without saving the outer block's context (or using BANZD). Simplest nesting: RPTB for the innermost loop only, BANZD for outer loops (§4.7.1, PDF p. 111 / printed 4-32).
- Context save/restore (Example 4–9, PDF p. 111 / printed 4-32): `SMMR BRCR,TEMP1; SMMR PASR,TEMP2; SMMR PAER,TEMP3` before the inner loop; restore with `LMMR BRCR,TEMP1; OPL #1,PMST` (sets BRAF to continue the outer loop); `LMMR PASR,TEMP2; LMMR PAER,TEMP3`. The save+restore costs **14 cycles** (as printed).
- Single-instruction repeats (RPT/RPTZ) and BANZ/BANZD loops can be inside a block repeat, and can include subroutine calls; on return from a call the block repeat resumes (§4.7.1, PDF p. 111 / printed 4-32).
- **Interrupts inside a block repeat:** a repeated block can be interrupted; when the ISR returns, the block repeat resumes. Caution: if the ISR itself uses block repeats, check whether a block repeat was interrupted and, if so, save its context as in Example 4–9 (§4.7.1, PDF p. 111 / printed 4-32).
- Smaller external loops can use BANZD looping (2 extra cycles per loop; if the loop count is less than 8 it can be more efficient than RPTB) (§4.7.1, PDF p. 111 / printed 4-32).
- **WHILE loops:** clear BRAF to drop out of the loop and continue sequentially past the end (e.g. `XC 2,OV; APL #0FFFEh,PMST` clears BRAF on overflow). To exit, **BRAF must be cleared at least four instruction words before the end of the loop**; the program then completes the current pass but does not go back to the top (§4.7.1, PDF pp. 111–112 / printed 4-32–4-33).
- Branches, calls and interrupts do not necessarily affect the loop; when program control returns to the loop, execution resumes (§4.7.1, PDF p. 112 / printed 4-33).
- Example 4–10 (PDF pp. 112–113 / printed 4-33–4-34): task-dispatcher loop — BRCR loaded via `BLPD NUM_TASKS,BRCR`; `RPTB ENDCALL–1`; inside, the task address is fetched with TBLR and called with CALA. **When the task returns, it returns to the top of the loop**, because the PC was already loaded with PASR before CALA executed the PC discontinuity — so CALA pushes the top-of-loop address onto the PC stack.

### 4.7.2 Interrupt Operation in a Block Repeat (§4.7.2, PDF pp. 113–114 / printed 4-34–4-35)

- The **single-word instruction at the end of a repeat block is not interruptible**, except when the previous instruction is a single-word multiple-cycle instruction (Examples 4–11/4–12). An incoming interrupt is latched as soon as timing requirements are met, but the PC does not branch to the ISR vector if it is fetching the last word of a repeat-block loop — functionally equivalent to disabling interrupts before the last instruction word is fetched and re-enabling afterwards. This can increase worst-case interrupt latency (§4.7.2, PDF p. 113 / printed 4-34).
- Example 4–11 (§4.7.2, PDF p. 113 / printed 4-34): interrupt during the last two instruction words of the last loop iteration returns to `MAR *,AR1` after ENDLOOP; interrupt at an earlier `SACL *` returns to `SAR AR0,*` (top of loop) if not the last iteration.
- Example 4–12 (§4.7.2, PDF p. 114 / printed 4-35): `BLDD BMAR,*+` is a single-word multiple-cycle instruction; an interrupt occurring there returns at the following `SACL *` (the end of the repeat block).
- **Required ISR steps for the Example 4–12 case** (§4.7.2 note, PDF p. 113 / printed 4-34): (1) save PMST at the beginning of the ISR; (2) clear the BRAF bit inside the ISR; (3) restore PMST before returning from the ISR.

---

## 4.8 Interrupts — §4.8, PDF pp. 115–123 / printed 4-36–4-44

- The 'C5x CPU supports **16 user-maskable interrupts (INT16–INT1)**; each 'C5x DSP does not necessarily use all 16. **All 'C5x DSPs use only 9 of these except 'C57, which uses 10** (the others are tied high internally). External interrupts are INT1–INT4. Internal interrupts: timer (TINT); serial ports (RINT, XINT, TRNT, TXNT, BRNT, BXNT); host port interface (HINT) (§4.8, PDF p. 115 / printed 4-36).
- In addition: three software interrupt instructions (INTR, NMI, TRAP) and two external nonmaskable interrupts (RS and NMI). **RS has the highest priority; INT16 the lowest** (as printed — see Contradiction C4: no INT16 vector exists in Table 4–14) (§4.8, PDF p. 115 / printed 4-36).
- INT1–INT4 and NMI are valid if the signal is **high for at least two machine cycles and low for a minimum of three machine cycles** (avoids false interrupts from noise / multiple interrupts on one long signal). **In IDLE2 mode**, an interrupt input must be high for at least **four** machine cycles and low for a minimum of **five** machine cycles (§4.8, PDF p. 115 / printed 4-36).
- ROM-vector reprogramming trick (§4.8.1, PDF p. 115 / printed 4-36): `LAMM TEMP0; BACC` — TEMP0 resides in DARAM block B2 and holds the ISR address; ISR addresses must be loaded into block B2 before interrupts are enabled. Device-specific interrupt operation: §9.1.2, External Interrupts (printed 9-4).

### Table 4–14. Interrupt Vector Locations and Priorities (§4.8.1, Table 4–14, PDF p. 116 / printed 4-37)

Verified against the PDF's word-position (bbox) data: rows, decimal/hex locations and priorities confirmed column-by-column. Interrupt addresses are spaced two locations apart so branch instructions fit in the vector locations. TRAP is not prioritized but is included because it has its own vector.

| Name | Location (dec) | Location (hex) | Priority | Function |
|---|---|---|---|---|
| RS | 0 | 0 | 1 (highest) | External nonmaskable reset signal |
| NMI | 36 | 24 | 2 | Nonmaskable interrupt |
| INT1 | 2 | 2 | 3 | External user interrupt #1 |
| INT2 | 4 | 4 | 4 | External user interrupt #2 |
| INT3 | 6 | 6 | 5 | External user interrupt #3 |
| TINT | 8 | 8 | 6 | Internal timer interrupt |
| RINT | 10 | A | 7 | Serial port receive interrupt |
| XINT | 12 | C | 8 | Serial port transmit interrupt |
| TRNT | 14 | E | 9 | TDM port receive interrupt |
| TXNT | 16 | 10 | 10 | TDM port transmit interrupt |
| INT4 | 18 | 12 | 11 | External user interrupt #4 |
| — | 20–23 | 14–17 | N/A | Reserved |
| HINT | 24 | 18 | — (none listed) | HINT ('C57 only) |
| — | 26–33 | 1A–21 | N/A | Reserved |
| TRAP | 34 | 22 | N/A | Software trap instruction |
| — | 38–39 | 26–27 | N/A | Reserved for emulation and test |
| — | 40–63 | 28–3F | N/A | Software interrupts |

- Footnotes (Table 4–14, PDF p. 116 / printed 4-37): † on TRNT — RINT2 on 'C52; BRNT on 'C56/'C57. ‡ on TXNT — XINT2 on 'C52; BXNT on 'C56/'C57. (The † glyph extracts as "{" next to TRNT in the text layer; the footnote text identifies the mapping.)
- **Agent cross-check [Ch6]:** the INTR K-table (Ch. 6, INTR description, PDF p. 263 / printed 6-111) agrees exactly: K = 0 RS (0h), 1 INT1 (2h), 2 INT2 (4h), 3 INT3 (6h), 4 TINT (8h), 5 RINT (Ah), 6 XINT (Ch), 7 TRNT (Eh), 8 TXNT (10h), 9 INT4 (12h), 10–15 Reserved (14h–1Eh), 16 Reserved (20h), 17 TRAP (22h), 18 NMI (24h), 19 Reserved (26h), 20–31 User-defined (28h–3Eh). So vectors 40–63 (28h–3Fh) are user-defined software-interrupt vectors reachable with INTR K = 20–31.
- **C51 relevance:** the 'C51 has no TDM port and no HINT; its usable vectors are RS, INT1–INT4, TINT, RINT, XINT, TRAP, NMI, plus the reserved/user-defined software vectors. Chapter 4 does not enumerate the 9 used interrupts per device — see §9.1.2 for device specifics.

### Interrupt vector address generation — Figure 4–6 (§4.8.1, Fig. 4–6, PDF p. 117 / printed 4-38)

- Vector address = **IPTR (PMST bits 15–11) concatenated with the interrupt vector number (1–16) shifted left by 1**. At reset IPTR = 0, so vectors map to page 0 and the reset vector is always at 0h.
- Worked example (as printed, §4.8.1, PDF p. 116 / printed 4-37; Fig. 4–6, PDF p. 117 / printed 4-38): IPTR = 00001, INT = 5 → vector `0 0 0 0 1 0 0 0 0 0 0 0 1 0 1 0` = **080Ah**.
- **Wording trap (INFERENCE, flagged):** "INT 5" here is **vector number 5 = RINT** (numbering RS = 0, INT1 = 1, INT2 = 2, INT3 = 3, TINT = 4, RINT = 5 — confirmed by the Ch. 6 INTR K-table). There is **no external INT5 pin/interrupt** on the 'C5x. Do not read "INT 5" as a fifth external interrupt.

### 4.8.2 Interrupt Operation (§4.8.2, PDF p. 117 / printed 4-38)

- On an interrupt, a flag is set in the 16-bit IFR, whether the interrupt is enabled or disabled. An interrupt flag **(other than from an active serial port)** is automatically cleared when the corresponding interrupt trap is taken (see Contradiction C3).
- The interrupt number being acknowledged is indicated by **address bits A5–A1 on the falling edge of IACK**. If vectors reside in on-chip memory, the CPU should operate in address-visibility mode (AVIS = 0) so the interrupt number can be decoded. If an interrupt occurs while the CPU is on hold with HM = 0, the address will not be present when IACK is activated.
- Actions on receiving an interrupt (§4.8.2, PDF p. 117 / printed 4-38), in order:
  1. CPU completes execution of the current instruction.
  2. Interrupts globally disabled (INTM = 1).
  3. PC pushed to TOS.
  4. PC set to the interrupt vector address.
  5. Key registers saved into context shadow registers.
  6. IACK signal goes low.
  7. Corresponding IFR flag bit cleared.
- Priority polling: at the start of each machine cycle (when INTM = 0) the interrupt status is polled and the highest-priority present-and-enabled interrupt executes. While an interrupt is being serviced, **even higher-priority interrupts cannot be serviced** until interrupts are re-enabled — usually at the end of the ISR.

### 4.8.3 Interrupt Flag Register (IFR) (§4.8.3, Fig. 4–7, PDF p. 118 / printed 4-39)

- IFR is a memory-mapped CPU register at **data-memory address 06h**. Read to identify pending interrupts; written to clear them. An interrupt sets its IFR flag until recognized by the CPU (§4.8.3, PDF p. 118 / printed 4-39).
- Flag cleared by: (a) reset (RS active); (b) an interrupt trap is taken; (c) **a 1 is written to the appropriate bit**. Writing 0 has no effect. Writing the current IFR contents back into the IFR clears all pending interrupts (§4.8.3, PDF p. 118 / printed 4-39).
- **IDLE/IDLE2 exception:** when interrupts are disabled (INTM = 1) and an interrupt causes an IDLE or IDLE2 instruction to be exited, **none of the IFR bits are cleared** (including the bit that caused the exit). Only reset, direct software clearing, or actually taking the trap (entering the ISR, INTM = 0 case) clears an IFR bit (§4.8.3, PDF p. 118 / printed 4-39).
- **One flag per interrupt:** if several hardware interrupts occur on the same pin before recognition, the CPU responds as though only a single (the last) interrupt occurred (§4.8.3, PDF p. 118 / printed 4-39).
- Example (as printed): `SPLK #5,IFR` clears INT1 and INT3 — #5 = 0b101 = bits 0 and 2, confirming INT1 = bit 0, INT3 = bit 2 (see bit table below).

#### Figure 4–7. IFR bit layout (§4.8.3, Fig. 4–7, PDF p. 118 / printed 4-39)

**Verification note:** the plain-text extraction misaligns this figure (it suggests INT4 at bit 9). The mapping below is from the PDF word-position (bbox) data — label centres matched to bit-number centres — and is confirmed by the `SPLK #5,IFR` example (INT1 = bit 0, INT3 = bit 2). The figure also carries a "Lowest → Highest" priority arrow running left (bit 15) to right (bit 0).

| Bits | Field |
|---|---|
| 15–12 | Reserved |
| 11 | HINT |
| 10–9 | Reserved (single merged field) |
| 8 | INT4 |
| 7 | TXNT |
| 6 | TRNT |
| 5 | XINT |
| 4 | RINT |
| 3 | TINT |
| 2 | INT3 |
| 1 | INT2 |
| 0 | INT1 |

### 4.8.4 Interrupt Mask Register (IMR) (§4.8.4, Fig. 4–8, PDF p. 119 / printed 4-40)

- IMR is a memory-mapped CPU register at **data-memory address 04h**. Used for masking external and internal interrupts. **Neither NMI nor RS are in the IMR**; the IMR has no effect on them. Readable and writable (§4.8.4, PDF p. 119 / printed 4-40).
- **1 in an IMR bit enables the corresponding interrupt, provided INTM (ST0) is cleared** (§4.8.4, PDF p. 119 / printed 4-40).
- Bit layout is identical to the IFR (Fig. 4–8, PDF p. 119 / printed 4-40; same bbox verification as IFR):

| Bits | Field |
|---|---|
| 15–12 | Reserved |
| 11 | HINT |
| 10–9 | Reserved |
| 8 | INT4 |
| 7 | TXNT |
| 6 | TRNT |
| 5 | XINT |
| 4 | RINT |
| 3 | TINT |
| 2 | INT3 |
| 1 | INT2 |
| 0 | INT1 |

### 4.8.5 Interrupt Mode (INTM) Bit (§4.8.5, PDF p. 119 / printed 4-40)

- INTM (ST0 bit 9) globally enables/disables all maskable interrupts: INTM = 0 → all unmasked interrupts enabled; INTM = 1 → all unmasked interrupts disabled. INTM does not modify IFR or IMR (§4.8.5, PDF p. 119 / printed 4-40).
- **Set by:** reset (RS active); an interrupt trap is taken; the NMI instruction is executed; SETC INTM (§4.8.5, PDF p. 119 / printed 4-40).
- **Cleared by:** CLRC INTM; RETE (§4.8.5, PDF p. 119 / printed 4-40). (RETI does **not** clear INTM — see §4.8.8 / Example 4–13.)

### 4.8.6 Nonmaskable Interrupts — RS and NMI (§4.8.6, PDF p. 120 / printed 4-41)

- RS and NMI are unaffected by INTM or IMR. NMI can be used as a soft reset or as the most time-critical interrupt input. As a soft reset, NMI does **not** perform the control-bit/register initializations that RS provides (§4.8.6, PDF p. 120 / printed 4-41).
- On NMI (§4.8.6, PDF p. 120 / printed 4-41): (1) CPU completes execution of all instructions in the pipeline; (2) interrupts globally disabled (INTM = 1); (3) PC set to the NMI vector (**24h**).
- **Key registers are NOT saved automatically on NMI** — because an NMI can be serviced even during an ISR. NMI does not affect any 'C5x modes. NMI is delayed by multicycle instructions (including RPT) and by HOLD (see §4.8.9). RS is covered in §4.9.
- NMI trap can be initiated in software with the NMI instruction (§4.8.6, PDF p. 120 / printed 4-41). [Ch6] NMI opcode description (PDF p. 331 / printed 6-179) confirms: PC+1 → stack, 24h → PC, 1 → INTM; "Automatic context save is not performed."

### 4.8.7 Software-Initiated Interrupts — INTR, NMI, TRAP (§4.8.7, PDF p. 120 / printed 4-41)

- Vectors for interrupts not tied to pins/peripherals can be used as software interrupts. INTR, NMI and TRAP are unaffected by INTM or IMR (§4.8.7, PDF p. 120 / printed 4-41).
- **INTR** (Ch. 6 p. 6-111): executes any ISR from software; an INTR for INT1–INT4 executes like an external interrupt (§4.8.2). [Ch6] INTR K (0–31) selects the vector; it sets INTM = 1; it does **not** clear the corresponding IFR bit (unlike a hardware trap) — Ch. 6 INTR description (PDF p. 263 / printed 6-111). INTR 0 branches to the reset vector (0h).
- **NMI instruction** (Ch. 6 p. 6-179): same effect as a hardware NMI — control to 24h, INTM = 1, **key registers not saved** into shadow registers (§4.8.7, PDF p. 120 / printed 4-41).
- **TRAP** (Ch. 6 p. 6-277): control to **22h**; **key registers not saved** into shadow registers (§4.8.7, PDF p. 120 / printed 4-41). See Contradiction C2: §4.8.7 says TRAP "disables interrupts (INTM = 1)", but Table 4–5 and the Ch. 6 TRAP description say INTM is **not affected** by TRAP — the Ch. 6 opcode description is normative.

### 4.8.8 Interrupt Context Save (§4.8.8, PDF pp. 121–122 / printed 4-42–4-43)

- On a (hardware) interrupt trap, the PC is saved on the 8-deep hardware stack; the following registers are each saved into a **1-level-deep shadow register** (pushed onto a 1-level stack):

| Shadowed register | Notes |
|---|---|
| ACC (accumulator) | |
| ACCB (accumulator buffer) | |
| ARCR (auxiliary register compare register) | |
| INDX (index register) | |
| PMST (processor mode status register) | 1-level shadow stack (§4.4.2) |
| PREG (product register) | |
| ST0 (status register 0) | 1-level shadow stack (§4.4.3); **except INTM bit** |
| ST1 (status register 1) | 1-level shadow stack (§4.4.3); **except XF bit** |
| TREG0 (multiplier) | |
| TREG1 (shift count) | |
| TREG2 (bit test) | |

- Exceptions: the **INTM bit (ST0)** and the **XF bit (ST1)** are not pushed/restored. On an interrupt INTM is always set (to disable interrupts). The register values at trap time remain available to the ISR and are protected in the shadows; shadows are copied back to the CPU registers when **RETI or RETE** executes (§4.8.8, PDF p. 121 / printed 4-42).
- **Only 1 level: nested interrupts are not supported** by the hardware shadow. Serial processing is efficient enough that nesting is usually unnecessary; software stacks can implement nesting if required. A plain **RET cannot restore these registers** (this preserves 'C2x software compatibility) — interrupts are not re-enabled unless RETE or CLRC INTM executes (§4.8.8, PDF p. 121 / printed 4-42).
- **NMI / TRAP / INTR (software) do NOT perform this automatic context save** — see §4.8.6/§4.8.7. The shadow save applies to hardware interrupt traps (and, per §4.8.7, to INTR for INT1–INT4 "like an external interrupt" — INFERENCE: Ch. 4 does not state explicitly whether INTR saves shadows; Ch. 6 INTR says nothing about shadow save either, only that it sets INTM and does not clear IFR. Treat INTR shadow-save as **unconfirmed by the manual**; the safe implementation saves context explicitly).
- Example 4–13 — modifying register values during context save (§4.8.8, PDF p. 122 / printed 4-43): ISR does `LACC #ISR_RE_ENTER; PUSH; RETI` — RETI pops all stacks including the PC stack, resuming at ISR_RE_ENTER; the ISR ends with `CLRC INTM; RET` (plain RET, because the stack is already popped).

### 4.8.9 Interrupt Latency (§4.8.9, PDF pp. 122–123 / printed 4-43–4-44)

- Latency depends on pipeline contents. The CPU always completes all instructions in the pipeline before executing a software vector (Fig. 4–9, PDF p. 123 / printed 4-44).
- **Minimum latency to IACK = 8 cycles:** 3 cycles to externally synchronize the interrupt + 1 cycle for the CPU to recognize it + 4 cycles to execute the INTR and flush the pipeline. On the **6th cycle** an INTR is jammed into the pipeline and INTM is set to 1; on the **9th cycle** the interrupt vector is fetched and IACK is generated (§4.8.9, PDF p. 122 / printed 4-43; Fig. 4–9, PDF p. 123 / printed 4-44).
- **SST #0 trap:** if the instruction immediately ahead of the INTR in the pipeline is SST #0 and INTM was previously cleared, INTM is set before SST executes, so INTM is **stored as 1**. If ST0 is later restored to return to the previous context, interrupts will be disabled (INTM = 1). Mitigation: execute SST #0 only with interrupts disabled, or re-enable interrupts after loading ST0 (§4.8.9, PDF p. 122 / printed 4-43).
- **Maximum latency** is a function of pipeline contents; multicycle instructions add cycles to empty the pipeline; wait-state insertion on memory accesses and wait states for interrupt-vector accesses also affect latency (§4.8.9, PDF p. 123 / printed 4-44).
- **RPT/RPTZ delay interrupts (including NMI, but not RS)** — all executions of the repeated instruction must complete before an interrupt executes, to protect the context of the repeated instruction's parallel pipeline operations, which cannot be saved in the ISR (§4.8.9, PDF p. 123 / printed 4-44).
- **HOLD takes precedence over interrupts** and can delay the trap: if an interrupt occurs while HOLD is asserted, it is not taken until HOLDA is deasserted at the end of hold. Exception: in concurrent hold mode (HM = 0) with the interrupt vector table in on-chip memory, the CPU takes the interrupt regardless of HOLD (§4.8.9, PDF p. 123 / printed 4-44).
- **Interrupts cannot be processed between CLRC INTM and the next instruction**: if an interrupt occurs during the decode phase of CLRC INTM, the CPU completes CLRC INTM and the following instruction before processing the pending interrupt — this ensures a RET can execute in an ISR before the next interrupt is processed, protecting against PC stack overflow. If the ISR ends with RETE, CLRC INTM is unnecessary. Similarly, SETC INTM and the next instruction cannot be interrupted (§4.8.9, PDF p. 123 / printed 4-44).

---

## 4.9 Reset — §4.9, PDF pp. 124–128 / printed 4-45–4-49

- RS is a nonmaskable external interrupt, usable at any time to place the 'C5x in a known state; typically applied after power-up when the state is unknown. **Reset aborts memory operations**; the system should be reinitialized after each reset. RS is the highest-priority interrupt; no other interrupt takes precedence. NMI can be used for soft resets because it does **not** abort memory operations or initialize status bits (§4.9, PDF p. 124 / printed 4-45).
- A hardware reset **clears all pending interrupt flags** (§4.9, PDF p. 124 / printed 4-45).
- Driving RS low terminates execution and forces the PC to the reset vector, **0h**. At power-up the state is undefined. For correct operation after power-up, **RS must be asserted low for a minimum of six clock cycles** (data lines to high-impedance, address lines driven low). The 'C5x latches the reset pulse and generates an internal reset pulse long enough to guarantee a reset. **After RS has been high for 17 clock cycles, CPU execution begins at location 0h** (normally a branch to the system initialization routine) (§4.9, PDF p. 124 / printed 4-45).
- Reset sequence (§4.9, PDF p. 124 / printed 4-45):
  1. Currently executing program is asynchronously aborted.
  2. CPU register status bits set per Table 4–15; **any remaining status bits remain undefined and should be initialized appropriately**.
  3. PC is cleared. Address bus is unknown while RS is low. If HOLD is asserted while RS is low, HOLDA is generated; address lines go high-impedance until HOLD goes high again.
  4. A synchronized reset (SRESET) is sent to the peripheral circuits to initialize them; peripheral register status bits set per Table 4–16 (see §9.1.3, Peripheral Reset, printed 9-6).
- Execution starts from program-memory location 0h when RS is driven high. If HOLD is asserted while RS is low, normal reset occurs internally but all buses/control lines stay high-impedance and HOLDA is asserted (Fig. 4–10(a)/(b), PDF p. 128 / printed 4-49). **If RS is asserted while HOLD and HOLDA are low, the CPU comes out of hold momentarily by deactivating HOLDA — this condition should be avoided.** Upon release of HOLD and RS, execution starts from 0h (§4.9, PDF p. 124 / printed 4-45).
- External parallel-interface signals are asynchronously disabled during reset; **external DMA is not supported during reset** (see §8.6.2, External DMA, printed 8-24) (§4.9, PDF p. 125 / printed 4-46).
- Figure 4–10 (RS and HOLD Interaction, PDF p. 128 / printed 4-49) is a two-panel RS/HOLD/HOLDA waveform diagram. [UNVERIFIED — figure detail: the text extraction carries no numeric timing values for the waveforms beyond the §4.9 prose above.]

### Table 4–15. CPU Registers' Bit Status at Reset (§4.9, Table 4–15, PDF p. 125 / printed 4-46)

| Register | Bit status | Result |
|---|---|---|
| ST0 | INTM → 1 | All maskable interrupts disabled (RS and NMI are nonmaskable). |
| ST0 | OV → 0 | Overflow bit cleared. |
| ST1 | C → 1 | Carry bit set. |
| ST1 | CNF → 0 | DARAM block B0 mapped into data memory space. |
| ST1 | HM → 1 | Processor halts execution during HOLD. |
| ST1 | PM → 0 | PREG output is not shifted. |
| ST1 | SXM → 1 | Sign extension on data enabled. |
| ST1 | XF → 1 | External flag pin set high. |
| PMST | AVIS → 0 | Internal program address appears at address pins. |
| PMST | BRAF → 0 | Block repeat disabled. |
| PMST | IPTR → 0 | Reset vector cleared. |
| PMST | MP/MC → (pin) | MP/MC pin sampled to determine use of on-chip ROM. |
| PMST | NDX → 0 | 'C2x-compatible mode selected. |
| PMST | OVLY → 0 | SARAM block not mapped to data memory space. |
| PMST | RAM → 0 | SARAM block not mapped to program memory space. |
| PMST | TRM → 0 | 'C2x-compatible mode selected. |
| IFR | All bits → 0 | No interrupts pending. |
| CBCR | CENB1 → 0 | Circular buffer 1 disabled. |
| CBCR | CENB2 → 0 | Circular buffer 2 disabled. |
| GREG | All bits → 0 | All data memory space configured as local. |
| RPTC | All bits → 0 | Repeat counter cleared. |

- **Not in Table 4–15 (hence undefined at reset):** ST0 ARP, OVM, DP; ST1 ARB, TC; CBCR CAR1/CAR2; BRCR, PASR, PAER (block-repeat registers — only BRAF → 0 is specified); ACC, ACCB, PREG, TREG0–2, AR0–AR7, INDX, ARCR, PC is cleared (step 3 above).

### Table 4–16. Peripheral Registers' Bit Status at Reset (§4.9, Table 4–16, PDF pp. 126–127 / printed 4-47–4-48)

| Register | Bit status | Result |
|---|---|---|
| PDWSR | All bits → 1 | All program and data wait-state registers set to 7. |
| IOWSR | All bits → 1 | All I/O wait-state registers set to 7. |
| CWSR | BIG → 0 | I/O space divided into eight 8K-word blocks. |
| CWSR | D → 1 | Wait states enabled for data memory space. |
| CWSR | I/O High → 1 | Wait states enabled for upper half of I/O space. |
| CWSR | I/O Low → 1 | Wait states enabled for lower half of I/O space. |
| CWSR | P → 1 | Wait states enabled for program memory space. |
| DRR | All bits → 0 | Data receive register cleared. |
| DXR | All bits → 0 | Data transmit register cleared. |
| SPC/BSPC/TSPC | DLB → 0 | Digital loop back disabled. |
| SPC/BSPC/TSPC | FO → 0 | Data transmitted/received as 16-bit words. |
| SPC/BSPC/TSPC | Free → 0 | Stop serial clock enabled. |
| SPC/BSPC/TSPC | FSM → 0 | Serial port operated in continuous mode. |
| SPC/BSPC/TSPC | IN0 → (pin) | IN0 reflects the current level of the CLKR pin. |
| SPC/BSPC/TSPC | IN1 → (pin) | IN1 reflects the current level of the CLKX pin. |
| SPC/BSPC/TSPC | MCM → 0 | CLKX pin configured as input pin. |
| SPC/BSPC/TSPC | RRDY → 0 | Receive ready reset. |
| SPC/BSPC/TSPC | RRST → 0 | Receive serial port reset. |
| SPC/BSPC/TSPC | RSRFULL → 0 | SPC only: receive shift register full flag reset. |
| SPC/BSPC/TSPC | Soft → 0 | Stop serial clock immediately enabled. |
| SPC/BSPC/TSPC | TDM → 0 | TSPC only: TDM port configured as standard serial port. |
| SPC/BSPC/TSPC | TXM → 0 | FSX pin configured as input pin. |
| SPC/BSPC/TSPC | XRDY → 1 | Transmit ready reset. |
| SPC/BSPC/TSPC | XRST → 0 | Transmit serial port reset. |
| SPC/BSPC/TSPC | XSREMPTY → 0 | SPC only: transmit shift register empty flag reset. |
| SPCE | BRE → 0 | Autobuffering receive disabled. |
| SPCE | BXE → 0 | Autobuffering transmit disabled. |
| SPCE | CLKDV → 00011 | Internal transmit clock division factor set to 3. |
| SPCE | CLKP → 0 | Data sampled by receiver on CLKR falling edge, sent by transmitter on CLKX rising edge. |
| SPCE | FE → 0 | Data transmitted/received as 16-bit words. |
| SPCE | FIG → 0 | Frame pulses following first frame restart the serial port interface. |
| SPCE | FSP → 0 | Frame sync pulses active high. |
| SPCE | HALTR → 0 | Autobuffering halt receive reset. |
| SPCE | HALTX → 0 | Autobuffering halt transmit reset. |
| SPCE | PCM → 0 | Pulse coded modulation not active. |
| SPCE | RH → 0 | Receive buffer half received bit reset. |
| SPCE | XH → 0 | Transmit buffer half transmitted bit reset. |
| TIM | All bits → 1 | Timer counts down from FFFFh. |
| PRD | All bits → 1 | Timer disabled. |
| TCR | TDDR → 0 | Each cycle decrements timer by 1. |
| TCR | TSS → 0 | Timer in run mode. |
| HPIC | SMOD 0 → 1 | Zero while in reset, set to one when reset goes high. |
| HPIC | HINT → 0 | No interrupt (external HINT pin is high). |

---

## 4.10 Power-Down Mode — §4.10, PDF pp. 129–130 / printed 4-50–4-51

- In power-down mode the 'C5x enters a dormant state and dissipates less power than normal mode. Invoked by executing **IDLE** or **IDLE2**, or by driving **HOLD low with HM = 1**. While in power-down, **all internal contents are maintained**, so operations continue unaltered when power-down terminates (§4.10, PDF p. 129 / printed 4-50).

| Mode | What stops | CLKOUT1 | Wake condition | After wake (INTM = 0 / INTM = 1) |
|---|---|---|---|---|
| IDLE (§4.10.1) | All CPU activities; system clock continues to peripherals | Remains active | **Any interrupt** (peripherals keep running, so timer/serial can wake the CPU) | INTM = 0 → enter ISR; INTM = 1 → continue with instruction following IDLE |
| IDLE2 (§4.10.2) | All CPU activities **and on-chip peripherals** | Disabled | **External interrupt pins only: RS, NMI, INT1, INT2, INT3, INT4, held for at least five machine cycles**. On-chip peripherals cannot generate the wake-up interrupt. | INTM = 0 → enter ISR; INTM = 1 → continue with instruction following IDLE2. **Reset all peripherals when IDLE2 terminates, especially if externally clocked.** |
| HOLD, HM = 1 (§4.10.3) | CPU stops executing; address, data and control lines go high-impedance (further power reduction) | — | HOLD becomes inactive | Execution resumes |
| HOLD, HM = 0 (§4.10.3) | External interface goes high-impedance, but CPU **continues executing internally** (from on-chip program memory). Only halts if an off-chip access is required, until hold is removed. | — | HOLD becomes inactive (or not needed if no off-chip access) | Normal operation continues |

- IDLE2 details (§4.10.2, PDF p. 129 / printed 4-50): power is significantly reduced because the complete DSP is stopped. HPI has special IDLE2 considerations — see §9.10, Host Port Interface (printed 9-87).
- HOLD details (§4.10.3, PDF p. 130 / printed 4-51): HOLD does **not** stop on-chip peripherals (serial ports and timers); they continue to operate regardless of HOLD level or HM status. HM = 0 mode is usable when external memory accesses are not required.
- IDLE2 input timing (§4.8, PDF p. 115 / printed 4-36): in IDLE2 an interrupt input must be high ≥ 4 machine cycles and low ≥ 5 machine cycles to be recognized (vs 2 high / 3 low in normal operation).

### IDLE3 — verdict: does NOT exist on the 'C5x

- **The string "IDLE3" occurs nowhere in SPRU056D** (full-manual text search, 0 hits). Chapter 4 §4.10 names only IDLE, IDLE2 and HOLD power-down; Table 4–13 (§4.6, PDF p. 108 / printed 4-29) lists only IDLE and IDLE2 as idle instructions.
- **"IDLE1" occurs exactly once** in the manual, in the Chapter 1 device overview (PDF p. 40 / printed 1-7): "Power consumption control with IDLE1 and IDLE2 instructions for power-down modes". It is the same plain IDLE instruction that Chapter 4 (§4.10.1) and Chapter 6 call "IDLE" — there is no separate IDLE1 opcode. (IDLE3 is a later 'C54x-family feature, not a 'C5x one — INFERENCE from the absence in this manual; do not implement an IDLE3 for 'C5x.)

---

## Contradictions and wording traps found in the manual

Normative rule applied: **opcode-level execution descriptions in Chapter 6 outrank Chapter 4 prose** (they state what the silicon does per instruction); within Chapter 4, a bit table's own row outranks the section's introductory prose when the table is corroborated by Chapter 6.

### C1 — LST #0 and ARP: §4.4.3 prose vs Table 4–5 + Ch. 6 LST

- **Reading A (§4.4.3 prose, PDF p. 89 / printed 4-10):** "The LST instruction writes to ST0 and ST1, and the SST instruction reads from them, except that the ARP bits and INTM bit are not affected by the LST #0 instruction." → ARP not affected by LST #0.
- **Reading B (Table 4–5 ARP row, PDF p. 90 / printed 4-11):** "The ARP can be modified by … the MAR or LST #0 instruction." → ARP IS modified by LST #0. The OV/OVM rows of the same table also say they "can be modified by the LST #0 instruction".
- **Reading C [Ch6] (LST description, PDF p. 287 / printed 6-135):** Execution: `(dma) → STm; dma(13–15) → ARP (regardless of n)`. Status bits affected include ARP; "The INTM bit is unaffected by an LST #0 instruction. In addition, the LST #0 instruction does not affect the auxiliary register buffer (ARB), even though a new auxiliary register pointer (ARP) is loaded."
- **Resolution (normative: C, corroborated by B):** LST #0 **does** load ARP from bits 13–15 of the data word; it does **not** copy the old ARP to ARB, and does **not** affect INTM. The §4.4.3 prose sentence conflates ARP with ARB — it should have said "the ARB and INTM bit are not affected". LST #1 loads ARB, and the loaded ARB value is also copied into ARP.
- **Agent consequence:** an emulator must implement LST #0 as ARP ← dma[15:13], ARB unchanged, INTM unchanged; LST #1 as ARB ← dma[15:13], ARP ← ARB.

### C2 — TRAP and INTM: §4.8.7 prose vs Table 4–5 + Ch. 6 TRAP

- **Reading A (§4.8.7, PDF p. 120 / printed 4-41):** "The TRAP instruction transfers program control to program memory location 22h. The TRAP instruction disables interrupts (INTM = 1)…"
- **Reading B (Table 4–5 INTM row, PDF p. 91 / printed 4-12):** "the INTM bit is unaffected by the TRAP and LST #0 instructions."
- **Reading C [Ch6] (TRAP description, PDF p. 429 / printed 6-277):** Status Bits — "Not affected by: INTM / Does not affect: INTM". Execution is only `(PC)+1 → stack; 22h → PC`.
- **Resolution (normative: C, corroborated by B):** TRAP does **not** set or otherwise affect INTM. §4.8.7's "disables interrupts (INTM = 1)" is wrong. (By contrast, NMI and INTR do set INTM = 1 — Ch. 6 NMI, PDF p. 331 / printed 6-179; Ch. 6 INTR, PDF p. 263 / printed 6-111.)
- **Agent consequence:** after TRAP, INTM keeps its previous value; do not set INTM = 1 on TRAP. Note §4.8.5's list of INTM-setting events (reset, interrupt trap taken, NMI instruction, SETC INTM) does not include TRAP — consistent with the normative reading.

### C3 — Serial-port IFR flags on trap taken: §4.8.2 vs §4.8.3

- **Reading A (§4.8.2, PDF p. 117 / printed 4-38):** "An interrupt flag (other than from an active serial port) is automatically cleared when the corresponding interrupt trap is taken."
- **Reading B (§4.8.3, PDF p. 118 / printed 4-39):** clearing events are reset, trap taken, or writing 1 to the bit — no serial-port exception stated.
- **Resolution:** treat A as normative for the exception (it is the more specific statement): a flag from an **active serial port** is not auto-cleared on trap taken. Chapter 4 does not state what clears a serial-port flag instead (presumably serial-port register service, Ch. 9 — not verified here). Recorded, not resolved further.

### C4 — "16 interrupts, INT16 lowest priority" vs the vector table

- **Reading A (§4.8, PDF p. 115 / printed 4-36):** "The 'C5x CPU supports 16 user-maskable interrupts (INT16–INT1)… The reset (RS) interrupt has the highest priority, and the INT16 interrupt has the lowest priority."
- **Reading B (Table 4–14, PDF p. 116 / printed 4-37):** no INT5–INT16 vectors exist; the lowest priority actually assigned is INT4 (11), HINT has no priority listed, TRAP/reserved are N/A.
- **Resolution:** the "INT16–INT1" phrasing is architectural (16 vector slots / the CPU's interrupt-numbering space — the Ch. 6 INTR K-table spans K = 0–31, with K = 0–15 the first 16 vectors). The manual itself reconciles it: "each 'C5x DSP does not necessarily use all 16 interrupts… all the 'C5x DSPs use only 9… except 'C57, which uses 10". Use Table 4–14 as the ground truth for vectors and priorities.

### Minor slips (recorded, not contradictions)

- **M1 — §4.3 bus naming:** "program address bus (PB)" in the first sentence of §4.3 (PDF p. 84 / printed 4-5) vs PAB everywhere else (§4.1, rest of §4.3, Fig. 4–1). Treat PAB as normative.
- **M2 — Table 4–1 duplicate rows:** BLDD/BLDP/BLPD listed under both long-immediate and BMAR PC loads (Table 4–1, PDF p. 82 / printed 4-3). Not a contradiction — two addressing forms (§4.3).
- **M3 — Table 4–5 INTM = 0 wording:** "All unmaskable interrupts are enabled" (PDF p. 91 / printed 4-12) — as printed; context shows maskable interrupts are meant.
- **M4 — Fig. 4–6 "INT 5":** vector number 5 = RINT, not a fifth external interrupt (see §4.8.1 note above).
- **M5 — IFR/IMR figure misalignment in text extraction:** plain-text extraction suggests INT4 at bit 9; the PDF's own word positions plus the `SPLK #5,IFR` example prove INT4 = bit 8 and bits 10–9 are a single Reserved field (see §4.8.3/§4.8.4 verification notes). The tables in this file use the verified mapping.

---

## RETI / RETE shadow scope — check requested by the task

- **No contradiction found inside Chapter 4.** §4.4.2 (PMST, PDF p. 86 / printed 4-7), §4.4.3 (ST0/ST1, PDF p. 89 / printed 4-10) and §4.8.8 (PDF p. 121 / printed 4-42) agree: PMST, ST0, ST1 have 1-level shadow stacks, auto-restored on RETI **or** RETE; INTM (ST0) and XF (ST1) are excluded from save/restore. The full shadowed set is the 11 registers in §4.8.8 plus PC on the hardware stack.
- **RETI vs RETE difference:** only RETE clears INTM (§4.8.5, PDF p. 119 / printed 4-40; §4.4.3). RETI restores shadows but leaves INTM = 1 (set at trap time) — hence Example 4–13's `CLRC INTM; RET` after the RETI-based re-entry (§4.8.8, PDF p. 122 / printed 4-43).
- **What does NOT restore shadows:** plain RET (§4.8.8: "the RET instruction … cannot restore these registers"); NMI/TRAP software traps do not save shadows in the first place (§4.8.6/§4.8.7).
- **Audit cross-check:** the earlier core-audit note ("RETI restores INTM+XF — manual excludes") describes a bug in `c5x_core.c`, not a manual ambiguity; the manual is unambiguous here.

## Unverified items

1. **Bold/new-for-'C5x marking** in Tables 4–10–4–13 — lost in text extraction; not reproduced. [UNVERIFIED — extraction garbled, §4.6, Tables 4–10–4–13, PDF pp. 102–109 / printed 4-23–4-30.]
2. **Figure 4–10 waveform detail** (RS/HOLD/HOLDA timing diagram) — no numeric values recoverable from text extraction; prose in §4.9 transcribed instead. [UNVERIFIED — figure is a timing diagram, §4.9, Fig. 4–10, PDF p. 128 / printed 4-49.]
3. **CBCR/PMST data-memory addresses** — not stated in Chapter 4 (only "page 0"). Not inferred. (Chapter 3 §3.5 / the memory map may state them; out of scope.)
4. **INTR shadow save** — Chapter 4 does not state explicitly whether INTR performs the §4.8.8 shadow save; marked INFERENCE/unconfirmed in §4.8.7–§4.8.8 above.
5. **Serial-port IFR flag clearing mechanism** (C3) — not specified in Chapter 4.
6. **Per-device list of the 9 used interrupts** — Chapter 4 states the count only; device specifics are in §9.1.2 (out of scope).
7. Figure bit-field box glyphs (Figs. 4–2–4–5, 4–7, 4–8) render as `Á` in extraction; all bit ranges/names were recovered from the raw text layer and cross-checked against the accompanying tables (and, for IFR/IMR, against PDF word positions + the SPLK example). No bit assignment in this file rests on the garbled glyphs alone.

## Agent quick-reference (derived only from the above; INFERENCE-free summary)

- PC loads: Table 4–1 (§4.1). Stack: 8×16, push loses bottom, pop-after-7 duplicates bottom (§4.2).
- Repeat: RPT/RPTZ → N+1 ≤ 65,536; RPTC reset-cleared, write-protected in practice; interrupts incl. NMI masked during repeat, RS not; HOLD still honoured (§4.6). Repeatable whitelist = Table 4–11; never repeat Table 4–13.
- Block repeat: RPTB sets BRAF, PASR = next insn, PAER = operand (last-word addr); ≥ 3 words; BRCR = N → N+1 passes; exit by clearing BRAF ≥ 4 words before loop end; one register set only — save/restore with SMMR/LMMR (14 cycles) for nesting (§4.7). Last single-word instruction of a block is uninterruptible (except after a single-word multicycle instruction) (§4.7.2).
- Interrupts: vectors Table 4–14 (RS 0h pri 1, NMI 24h pri 2, INT1 2h pri 3 … INT4 12h pri 11, TRAP 22h, HINT 18h 'C57 only, no priority); addr = (IPTR<<11)|(vector#<<1); IFR 06h / IMR 04h, bit 0 = INT1 … bit 8 = INT4, bit 11 = HINT; write-1-to-clear IFR; INTM set by trap/NMI-instruction/RESET/SETC, cleared by CLRC/RETE; shadow save = 11 registers + PC, minus INTM/XF, restored by RETI/RETE only; min latency 8 cycles to IACK (§4.8).
- Reset: RS low ≥ 6 clocks, execution 17 clocks after RS high, from 0h; Table 4–15/4–16 for register states; TIM/PRD → FFFFh (§4.9).
- Power-down: IDLE (any interrupt wakes; CLKOUT1 on), IDLE2 (external pins only, ≥ 5 cycles; CLKOUT1 off; reset peripherals on exit), HOLD+HM (§4.10). **No IDLE3 on 'C5x.**
- Traps: TRAP does NOT touch INTM (C2); LST #0 DOES load ARP, does NOT touch ARB/INTM (C1).
