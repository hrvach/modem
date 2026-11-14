# Chapter 3 — Central Processing Unit (CPU) — TMS320C5x User's Guide (SPRU056D)

- **Source (only authority):** `~/workspace/user/files/spru056d.pdf` — SPRU056D, June 1998, Chapter 3, PDF pp. 55–79 / printed pp. 3-1–3-25. Fresh extraction: `pdftotext -layout -f 55 -l 79`.
- **Scope:** §3.1 Functional Overview, §3.2 CALU, §3.3 PLU, §3.4 ARAU, §3.5 Summary of Registers. Printed page = PDF page − 54 throughout this chapter.
- **Family vs device:** Content is **C5x-family-generic** unless a device is named. Named device differences are collected in §8 below. The Courier V.Everything DSP is a TMS320C51; nothing in Ch. 3 states a C51-only CPU behaviour — where the manual's general rule has a named-device exception list that does **not** include the C51, that is labelled INFERENCE in §9.
- **Citation rule used in this file:** every row/claim carries manual section + table/figure + PDF page / printed page. `[UNVERIFIED — …]` marks garbled or unexplained extraction; `INFERENCE` marks conclusions drawn from the text, kept out of tables.
- **ST0 / ST1 / PMST bit layouts are NOT defined in Ch. 3.** They are defined in Ch. 4 (§4.4.2 PMST, §4.4.3 ST0/ST1) — see `04-program-control.md`. Ch. 3 only names individual bits (OVM in ST0; SXM, PM, C, TC in ST1; TRM, NDX in PMST) and their functional effect. Do not duplicate the Ch. 4 layouts here.

## 1. CPU composition and block diagram

| Item | Detail | Ref |
|---|---|---|
| CPU elements (5) | Program controller; central arithmetic logic unit (CALU); parallel logic unit (PLU); auxiliary register arithmetic unit (ARAU); memory-mapped registers | §3, PDF p.55 / printed 3-1 |
| What Ch. 3 excludes | Memory and peripheral segments, except in relation to the CPU | §3, PDF p.55 / printed 3-1 |
| Hardware approach | Single-cycle 16×16-bit multiplication, data shifting, address manipulation in hardware | §3.1, PDF p.56 / printed 3-2 |
| Block diagram | Fig. 3-1, all principal blocks and data paths | §3.1, Fig. 3-1, PDF p.57 / printed 3-3 |
| Fig. 3-1 width rule | All registers and data lines are 16 bits wide unless otherwise specified | §3.1, Fig. 3-1 note, PDF p.57 / printed 3-3 |
| Fig. 3-1 `†` mark | "Not available on all devices" (Serial Port 2, TDM serial port, BSP, host-port interface, timer, emulation are so marked) | §3.1, Fig. 3-1 note, PDF p.57 / printed 3-3 |
| Fig. 3-1 stack | Stack shown as 8×16 (8 words deep, 16 bits wide); separate microcall stack (MCS); program counter (PC) and prefetch counter (PFC) shown | §3.1, Fig. 3-1, PDF p.57 / printed 3-3 |
| Fig. 3-1 `RBIT` | Label appears next to the A15–A0 address bus in Fig. 3-1 only; not listed in Table 3-1 and not explained in Ch. 3 text | §3.1, Fig. 3-1, PDF p.57 / printed 3-3 — [UNVERIFIED — meaning not explained in Ch. 3] |

## 2. Internal hardware summary (Table 3-1, complete)

Table 3-1 spans PDF pp. 58–60 / printed 3-4–3-6. Symbols and names reproduced verbatim; widths in parentheses are as printed. Bits whose register home is defined in Ch. 4 are flagged — see `04-program-control.md` for layouts.

| Symbol | Name | Ref |
|---|---|---|
| A15–A0 | Address bus | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| ACC (32) | Accumulator | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| ACCB (32) | Accumulator buffer | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| ACCH | Accumulator high [word — see contradiction C2 in §10] | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| ACCL | Accumulator low [word — see C2] | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| ALU (32) | Arithmetic logic unit | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| AR0–AR7 | Auxiliary registers | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| ARAU | Auxiliary register arithmetic unit | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| ARB (3) | Auxiliary register buffer bits | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| ARCR | Auxiliary register compare register | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| ARP (3) | Auxiliary register pointer bits | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| BMAR | Block move address register | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| BRAF (1) | Block repeat active flag bit | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| BRCR | Block repeat counter register | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| C | Carry bit | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| CALU | Central arithmetic logic unit | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| CBCR (8) | Circular buffer control register [see contradiction C1 in §10] | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| CBER1, CBER2 | Circular buffer end registers | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| CBSR1, CBSR2 | Circular buffer start registers | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| CNF | Configuration control bit (PMST — Ch. 4) | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| COMPARE | Compare of program address | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| D15–D0 | Data bus | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| DATA BUS | Data bus | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| DBMR | Dynamic bit manipulation register | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| dma (7) | Data memory address (immediate register) [meaning not explained in Ch. 3 — UNVERIFIED] | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| DP (9) | Data memory page pointer bits (in ST0 — Fig. 3-1) | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| DRB | Direct data memory address bus | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| GREG | Global memory allocation register | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| HM (1) | Hold mode bit | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| IFR | Interrupt flag register | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| IMR | Interrupt mask register | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| INDX | Index register | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| INTM (1) | Interrupt mode bit (ST0 — Ch. 4) | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| IPTR (5) | Interrupt vector pointer bits | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| IREG | Instruction register | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| MCS | Microcall stack | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| MP/MC | Microprocessor/microcomputer bit (PMST — Ch. 4) | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| MULTIPLIER | Multiplier | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| MUX | Multiplexer | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| NDX (1) | Enable extra index register bit (PMST — Ch. 4) | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| OV (1) | Overflow bit | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| OVLY (1) | RAM overlay bit (PMST — Ch. 4) | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| OVM (1) | Overflow mode bit (ST0 — Ch. 4) | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| P-SCALER (−6, 0, 1, 4) | Product shifter | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| PAER | Block repeat program address end register | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| PASR | Block repeat program address start register | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| PC | Program counter | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| PFC | Prefetch counter | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| PLU | Parallel logic unit | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| PM (2) | Product shifter mode bits (ST1 — Ch. 4) | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| PMST | Processor mode status register | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| POSTSCALER (0–7) | Accumulator postscaling shifter | §3.1, Table 3-1, PDF p.59 / printed 3-5 |
| PREG (32) | Product register | §3.1, Table 3-1, PDF p.60 / printed 3-6 |
| PRESCALER, SFL (0–16), SFR (0–16) | Prescaling shifters | §3.1, Table 3-1, PDF p.60 / printed 3-6 |
| PROGRAM BUS | Program bus | §3.1, Table 3-1, PDF p.60 / printed 3-6 |
| RAM (1) | Program RAM enable bit (PMST — Ch. 4) | §3.1, Table 3-1, PDF p.60 / printed 3-6 |
| RPTC | Repeat counter register | §3.1, Table 3-1, PDF p.60 / printed 3-6 |
| ST0, ST1 | Status registers | §3.1, Table 3-1, PDF p.60 / printed 3-6 |
| STACK | Stack | §3.1, Table 3-1, PDF p.60 / printed 3-6 |
| SXM (1) | Sign-extension mode bit (ST1 — Ch. 4) | §3.1, Table 3-1, PDF p.60 / printed 3-6 |
| TC (1) | Test/control bit (ST1 — Ch. 4) | §3.1, Table 3-1, PDF p.60 / printed 3-6 |
| TREG0 | Temporary register (multiplicand) | §3.1, Table 3-1, PDF p.60 / printed 3-6 |
| TREG1 (5) | Temporary register (dynamic shift count) | §3.1, Table 3-1, PDF p.60 / printed 3-6 |
| TREG2 (4) | Temporary register (bit pointer in dynamic bit test) | §3.1, Table 3-1, PDF p.60 / printed 3-6 |
| TRM (1) | Enable multiple temporary registers bit (PMST — Ch. 4) | §3.1, Table 3-1, PDF p.60 / printed 3-6 |
| XF (1) | External flag pin status bit | §3.1, Table 3-1, PDF p.60 / printed 3-6 |

## 3. CALU — components

| Component | Width / range | Ref |
|---|---|---|
| Parallel multiplier | 16-bit × 16-bit | §3.2, PDF p.61 / printed 3-7 |
| ALU | 32-bit, 2s-complement | §3.2, PDF p.61 / printed 3-7 |
| Accumulator (ACC) | 32-bit | §3.2, PDF p.61 / printed 3-7 |
| Accumulator buffer (ACCB) | 32-bit | §3.2, PDF p.61 / printed 3-7 |
| P-scaler (product shifter) | 0-, 1-, or 4-bit left, or 6-bit right | §3.2, PDF p.61 / printed 3-7 |
| Prescaler, left barrel shifter (SFL) | 0–16 bits left | §3.2, PDF p.61 / printed 3-7 |
| Prescaler, right barrel shifter (SFR) | 0–16 bits right | §3.2, PDF p.61 / printed 3-7 |
| Postscaler | 0–7 bits left | §3.2, PDF p.61 / printed 3-7 |
| **Guard bits** | **None. ACC is exactly 32 bits; no guard bits are mentioned anywhere in Ch. 3.** Saturation limits are 7FFF FFFFh / 8000 0000h (§4 below), confirming a plain 32-bit range. | §3.2, PDF p.61 / printed 3-7; §3.2.2, PDF p.66 / printed 3-12 |
| CALU block diagram | Fig. 3-2 (data bus → TREG0/multiplier → PREG → p-scaler → ALU → ACC/ACCB → postscaler → data bus; prescalers SFL/SFR feeding ALU) | §3.2, Fig. 3-2, PDF p.62 / printed 3-8 |

### 3.1 Multiplier, PREG, TREG0 (§3.2.1)

| Rule | Detail | Ref |
|---|---|---|
| Multiply width / cycle | 16×16-bit hardware multiplier; signed or unsigned 32-bit product in a single machine cycle | §3.2.1, PDF p.61 / printed 3-7 |
| Signed default | All multiply instructions except MPYU perform signed multiply: operands treated as 2s-complement, result 32-bit 2s-complement | §3.2.1, PDF p.61 / printed 3-7 |
| Multiplier inputs | One input from memory-mapped TREG0; other from data bus or program bus | §3.2.1, PDF p.61 / printed 3-7 |
| Product destination | 32-bit result stored in PREG, available to the ALU | §3.2.1, PDF p.61 / printed 3-7 |
| ALU second input | 16-bit words from data memory or immediate, or 32-bit PREG result; ALU also does Boolean operations; 32-bit ALU result stored in ACC; ACC also supplies an ALU input | §3.2.1, PDF p.61 / printed 3-7 |
| ACC store | Instructions provided for storing high- and low-order ACC words in memory | §3.2.1, PDF p.61 / printed 3-7 |
| Shifter roles | P-scaler, prescaler, postscaler enable numerical scaling, bit extraction, extended-precision arithmetic, overflow prevention; connected to PREG and ACC outputs | §3.2.1, PDF p.61 / printed 3-7 |
| Product rate | A product can be obtained every two cycles, except when a long immediate operand is used | §3.2.1, PDF p.63 / printed 3-9 |
| LT / MPY split | LT loads TREG0 from the data bus with the first operand; MPY supplies the second operand. MPY with immediate operand for short or long immediate multiply. | §3.2.1, PDF p.63 / printed 3-9 |
| PREG store | PREG contents transferred to ALU or data memory via SPH (store product high) and SPL (store product low) | §3.2.1, PDF p.64 / printed 3-10 |
| PM shifts on store | PM shifts also occur when PREG contents are stored to data memory; PREG contents remain unchanged during the shifts | §3.2.1, PDF p.63 / printed 3-9 |

#### Product-shift (PM) modes — PM field of ST1

| PM | P-scaler action on PREG output (to ALU or on store) | Fill / loss | Purpose per manual | Ref |
|---|---|---|---|---|
| `00`₂ | No shift | — | — | §3.2.1, PDF p.61 / printed 3-7 |
| `01`₂ | Left-shift 1 bit | LSB zero-filled | Compensates for the extra sign bit gained multiplying two 16-bit 2s-complement numbers | §3.2.1, PDF p.61 / printed 3-7 |
| `10`₂ | Left-shift 4 bits | 4 LSBs zero-filled | Used with MPY with a short immediate value (13 bits or less) to eliminate the four extra sign bits from multiplying a 16-bit number by a 13-bit number | §3.2.1, PDF p.62 / printed 3-8 |
| `11`₂ | Right-shift 6 bits, sign-extended | 6 LSBs lost | Enables up to 128 consecutive multiply/accumulates without possibility of overflow. Product is **always sign-extended, regardless of SXM** (ST1). | §3.2.1, PDF p.62 / printed 3-8 |

#### Multiply/accumulate instructions

| Instruction(s) | Behaviour | Ref |
|---|---|---|
| MAC, MACD, MADD, MADS | Fully utilise multiplier bandwidth; both operands processed simultaneously; data transferred each cycle via program and data buses. With RPT or RPTZ, become single-cycle multiply/accumulate. Coefficient addresses from PC, data addresses from ARAU. RPTZ also clears ACC and PREG to initialise the operation. | §3.2.1, PDF p.63 / printed 3-9 |
| MAC, MACD | Coefficient pointer from a long immediate address → 2-word instructions | §3.2.1, PDF p.63 / printed 3-9 |
| MADS, MADD | Coefficient pointer from BMAR → 1-word instructions. BMAR source lets one code block support multiple applications; long immediate address changeable without modifying executable code. | §3.2.1, PDF p.63 / printed 3-9 |
| MACD, MADD | Include DMOV data move: data value written to next higher data address in conjunction with fetching the data multiplicand. Supports filter constructs (weighted running averages): sample data shifts in memory, oldest sample discarded. **DMOV portion does not function with external data memory addresses.** | §3.2.1, PDF pp.63–64 / printed 3-9–3-10 |
| MAC, MADS | Circular addressing usable with these for filter implementation | §3.2.1, PDF p.64 / printed 3-10 |
| MADD repeated (manual example) | RPTZ #9 clears ACC=PREG=0; `MADD *–` sums Aᵢ×Xᵢ with Xᵢ₊₁=Xᵢ; APAC final sum. PC held in a temporary register during the repeat, then loaded from BMAR; program bus addresses coefficients, PC increments through the table; ARAU generates sample-data addresses; indirect decrement steps through samples oldest-first. | §3.2.1, PDF p.64 / printed 3-10 |
| MAC repeated (manual example) | 10×10 matrices, MTRX1 = start of matrix 1, INDX=10, current AR = start of matrix 2: `RPTZ #9` / `MAC MTRX1,*0+` / `APAC` | §3.2.1, PDF p.63 / printed 3-9 |
| MPYU | Unsigned multiply: unsigned TREG0 × unsigned addressed data-memory contents → PREG. Facilitates extended-precision arithmetic (operands >16 bits broken into 16-bit words, products >32 bits). | §3.2.1, PDF p.64 / printed 3-10 |
| SQRA, SQRS | Square/add, square/subtract: same value passed to both multiplier inputs, squaring a data-memory value | §3.2.1, PDF p.64 / printed 3-10 |

### 3.2 ALU and accumulators (§3.2.2)

| Rule | Detail | Ref |
|---|---|---|
| ALU / ACC | 32-bit general-purpose ALU and ACC; wide range of arithmetic and logical functions, majority in a single clock cycle. After ALU operation, result transferred to ACC, where further operations (e.g. shifting) can occur. | §3.2.2, PDF p.65 / printed 3-11 |
| Typical ALU instruction steps | 1) Data fetched from memory on data bus. 2) Data passed through prescaler and ALU, arithmetic performed. 3) Result moved into ACC. | §3.2.2, PDF p.65 / printed 3-11 |
| ALU inputs | One input always supplied by ACC. Other input from PREG (via p-scaler), ACCB, or prescaler output (read from data memory or from the ACC). | §3.2.2, PDF p.65 / printed 3-11 |
| ALU operand width | Operates on 16-bit words from data memory or immediate instructions; also Boolean operations (bit manipulation for high-speed controller use) | §3.2.2, PDF p.65 / printed 3-11 |
| ACC split | 32-bit ACC split into two 16-bit segments ACCH (bits 16–31) and ACCL (bits 0–15) for storage in data memory | §3.2.2, PDF p.65 / printed 3-11 |
| Postscaler | At ACC output; left shift 0–7 places while data transferred to data bus for storage; ACC contents unchanged | §3.2.2, PDF p.65 / printed 3-11 |
| Postscaler, high word | MSBs lost; LSBs filled with bits shifted in from low word (bits 0–15) | §3.2.2, PDF p.65 / printed 3-11 |
| Postscaler, low word | LSBs zero-filled | §3.2.2, PDF p.65 / printed 3-11 |
| Postscaler examples (verified — see §10) | ACC=FF23 4567h: `SACL TEMP1,7` → TEMP1=B380h; `SACH TEMP2,7` → TEMP2=91A2h; ACC unchanged | §3.2.2, PDF p.65 / printed 3-11 |
| ALU example (verified) | ACC=0, PREG=0022 2200h, PM=`00`₂, ACCB=0033 3300h: `LACC #01111h,8` → ACC=00111100h; `APAC` → ACC=00333300h; `ADDB` → ACC=00666600h | §3.2.2, PDF p.65 / printed 3-11 |
| NORM | Normalises fixed-point numbers in ACC by left shifts; supports floating-point operations for large dynamic range | §3.2.2, PDF p.66 / printed 3-12 |
| TREG1 variable shift | Four bits of TREG1 define variable shift through prescaler for ADDT / LACT / SUBT; denormalises a number (floating-point → fixed-point); also automatic gain control (AGC) into a filter | §3.2.2, PDF p.66 / printed 3-12 |
| ACCB role | Temporary storage for fast save of ACC; also an ALU input; 32-bit temporary buffer enhances extended-precision arithmetic | §3.2.2, PDF p.66 / printed 3-12 |
| CRLT / CRGT | Minimum / maximum: compare ACCB with ACC; min (CRLT) or max (CRGT) placed in **both** registers; if condition met, carry bit C set. Signed arithmetic operations. | §3.2.2, PDF p.66 / printed 3-12 |
| CRLT / CRGT example | ACC=1234 5678h, ACCB=7654 3210h: `CRLT` → ACC=ACCB=1234 5678h, C=1; `CRGT` → ACC=ACCB=7654 3210h, C=0. See ambiguity C4 in §10 (examples read as sequential code but CRGT result requires the original ACCB value). | §3.2.2, PDF p.66 / printed 3-12 |
| Branches on ALU/ACC status | BCND depends on a variety of ALU/ACC conditions; BACC branches to address stored in ACC; BITT and BIT facilitate branching on a specified bit in data memory | §3.2.2, PDF p.66 / printed 3-12 |

#### Overflow and saturation (OVM, ST0)

| OVM (ST0) | On ACC overflow | Saturation value | Ref |
|---|---|---|---|
| Set (1) | Overflow flag (OV) set; ACC loaded with most positive or most negative representable value, depending on overflow direction | +7FFF FFFFh (positive overflow); 8000 0000h (negative overflow) | §3.2.2, PDF p.66 / printed 3-12 |
| Cleared (0) | Overflowed results loaded into ACC without modification | — (wraps) | §3.2.2, PDF p.66 / printed 3-12 |
| Either | Logical operations cannot result in overflow | — | §3.2.2, PDF p.66 / printed 3-12 |

#### Carry bit C (ST1)

| Rule | Detail | Ref |
|---|---|---|
| Purpose | Efficient extended-precision products, additions/subtractions; overflow management | §3.2.2, PDF p.66 / printed 3-12 |
| Affected by | Most arithmetic instructions; single-bit shift and rotate instructions | §3.2.2, PDF p.66 / printed 3-12 |
| Not affected by | Loading the ACC, logical operations, other nonarithmetic or control instructions | §3.2.2, PDF p.66 / printed 3-12 |
| Add convention | C set if addition/accumulation generates a carry; otherwise cleared after an addition | §3.2.2, PDF p.67 / printed 3-13 |
| Subtract convention | C cleared if subtraction generates a borrow; otherwise set after a subtraction (i.e. C is the **inverse** of borrow) | §3.2.2, PDF p.67 / printed 3-13 |
| Value sources | Value added to / subtracted from ACC can come from prescaler, ACCB, or PREG | §3.2.2, PDF p.67 / printed 3-13 |
| ADDC / ADCB | Add to ACC (with carry) / add ACCB to ACC (with carry): use previous value of carry in the addition | §3.2.2, PDF p.67 / printed 3-13 |
| SUBB / SBBB | Subtract from ACC (with borrow) / subtract ACCB from ACC (with borrow): use logical inversion of previous carry | §3.2.2, PDF p.67 / printed 3-13 |
| ADD/SUB shift-16 exception | ADD with shift count 16 (add to ACCH) and SUB with shift count 16 (subtract from ACCH) can generate a carry/borrow but **will not clear** a carry/borrow if none is generated (unlike normal behaviour). Useful for extended-precision arithmetic. | §3.2.2, PDF p.67 / printed 3-13 |
| Branch conditions | Conditional operands C and NC provided for branching, calling, returning, conditionally executing on carry status | §3.2.2, PDF p.67 / printed 3-13 |
| Loading C | CLRC, LST #1, SETC can load the carry bit | §3.2.2, PDF p.67 / printed 3-13 |
| **Reset value** | **Carry bit is set on a reset** | §3.2.2, PDF p.67 / printed 3-13 |
| Fig. 3-3 worked cases (all verified — §10) | FFFF FFFFh + 1 → C=1, 0000 0000h; 0000 0000h − 1 → C=0, FFFF FFFFh; 7FFF FFFFh + 1 (OVM=0) → C=0, 8000 0000h; 8000 0001h − 2 (OVM=0) → C=1, 7FFF FFFFh; ADDC with C=1: 0000 0000h + 0 → C=0, 0000 0001h; SUBB with C=0: FFFF FFFFh − 1 → C=1, FFFF FFFDh | §3.2.2, Fig. 3-3, PDF p.67 / printed 3-13 |

#### ACC shifts and rotates

| Instruction(s) | Operation | SXM effect | Ref |
|---|---|---|---|
| SFL | Shift ACC left 1 bit through carry; MSB shifted out, 0 shifted in | Not affected by SXM; same in both cases | §3.2.2, PDF pp.67–68 / printed 3-13–3-14 |
| SFR | Shift ACC right 1 bit through carry | SXM=1: arithmetic right shift, sign of ACC maintained. SXM=0: logical shift, LSBs out, 0 in for MSB. | §3.2.2, PDF p.68 / printed 3-14 |
| ROL / ROR | Rotate ACC left / right through carry | (SXM effect not stated for rotates in Ch. 3) | §3.2.2, PDF pp.67–68 / printed 3-13–3-14 |
| RPT / RPTZ + shift/rotate | Repeatable for multiple-bit shifts | — | §3.2.2, PDF p.68 / printed 3-14 |
| SFLB, SFRB, ROLB, RORB | Shift/rotate the 65-bit combination ACC (32) + ACCB (32) + carry (1) | As for the 32-bit forms (SXM governs SFRB right-shift fill, per SFL/SFR rule) | §3.2.2, PDF p.68 / printed 3-14 |
| BSAR n (n = 1–16, embedded in instruction word) | Shift ACC right 1–16 bits in one cycle; bits shifted out lost; bits shifted in are 0s or copies of original sign bit, depending on SXM | SXM=1: sign-filled; SXM=0: zero-filled | §3.2.2, PDF p.68 / printed 3-14 |
| BSAR example | ACC=1234 5678h, `BSAR 7` → manual prints 0246 8ACEh. **Verified arithmetic gives 0024 68ACh — manual example is wrong; see contradiction C3 in §10.** | — | §3.2.2, PDF p.68 / printed 3-14 |
| SATH + SATL (TREG1-controlled 0–31-bit right shift, two cycles) | SATH: shifts ACC 16 bits right if bit 4 of TREG1 = 1. SATL: shifts ACC 0–15 bits, count = bits 0–3 of TREG1. | SXM fill rule as for BSAR (0s or sign copies) | §3.2.2, PDF p.68 / printed 3-14 |
| SATH/SATL example (verified) | SHIFT=01Bh (27), ACC=1234 5678h: `LMMR TREG1,SHIFT` → TREG1=1Bh; `SATH` → ACC=0000 1234h; `SATL` → ACC=0000 0002h | — | §3.2.2, PDF p.68 / printed 3-14 |
| General right shift | ACC can be shifted 0–31 bits right in two instruction cycles, or 1–16 bits right in one cycle | — | §3.2.2, PDF p.68 / printed 3-14 |

### 3.3 Scaling shifters and TREG1 (§3.2.3)

| Shifter | Input → output | Shift | Fill | Count source | Ref |
|---|---|---|---|---|---|
| Prescaler (SFL) | 16-bit input from data bus → 32-bit output to ALU | Left 0–16 bits | LSBs 0-filled; MSBs 0-filled or sign-extended per SXM (ST1) | Constant embedded in instruction word, or value in TREG1 | §3.2.3, PDF p.68 / printed 3-14 |
| Prescaler (SFR) | Shown in Fig. 3-2 as SFR (0–16), right barrel shifter feeding ALU | 0–16 bits right | [UNVERIFIED — no prose description of the SFR prescaler in Ch. 3; only the figure shows it. Do not assume it is the BSAR path.] | Not stated in Ch. 3 | §3.2, Fig. 3-2, PDF p.62 / printed 3-8 |
| P-scaler | PREG output → ALU / store | −6, 0, +1, +4 (see PM table in §3.1 above) | Per PM mode | PM field, ST1 | §3.2.3, PDF p.68 / printed 3-14 |
| Postscaler | ACC output → data bus | Left 0–7 bits | Per §3.2 above | Shift count in instruction (SACH/SACL) | §3.2.3, PDF p.68 / printed 3-14 |
| TREG1 | 5-bit register; dynamic (execution-time programmable) shift count for the prescaling shifter | — | — | Loaded via LMMR / CALU (see §7) | §3.2.3, PDF p.68 / printed 3-14; §3.5.19, PDF p.79 / printed 3-25 |

## 4. Parallel logic unit — PLU (§3.3)

| Rule | Detail | Ref |
|---|---|---|
| Function | Directly set, clear, test, or toggle multiple bits in a control/status register or any data-memory location, without affecting ACC or PREG | §3.3, PDF p.69 / printed 3-15 |
| Operation | Read-modify-write on data space: operand 1 fetched from data memory; operand 2 from a long immediate on the program bus or from DBMR; PLU executes logical operation; result written back to same data-memory location | §3.3, PDF p.69 / printed 3-15 |
| Block diagram | Fig. 3-4 (data bus + DBMR via MUX, program bus long immediate → PLU → data bus) | §3.3, Fig. 3-4, PDF p.69 / printed 3-15 |
| Fig. 3-4 width rule | All registers and data lines 16 bits wide unless otherwise specified | §3.3, Fig. 3-4 note, PDF p.69 / printed 3-15 |
| Operations | AND, OR, exclusive-OR, or load a 16-bit long immediate value to a data location | §3.3, PDF p.69 / printed 3-15 |
| Long-immediate instructions | SPLK (store peripheral long immediate), OPL (OR long immediate) — full PLU instruction list is Table 6–6, Ch. 6 (not reproduced here) | §3.3, PDF p.69 / printed 3-15; PDF p.70 / printed 3-16 |
| DBMR instructions | APL (AND DBMR to data), OPL (OR DBMR to data), XPL (XOR DBMR to data) — use 16-bit dynamic register value instead of long immediate | §3.3, PDF p.70 / printed 3-16 |
| TC bit (ST1) | Set if the result of any PLU instruction is 0. CPL (compare parallel long immediate): TC set if data value equals long immediate value. APL/OPL/XPL also set TC if the written-back result is 0 — allows test-and-clear simultaneously. | §3.3, PDF p.70 / printed 3-16 |
| BIT vs CPL | BIT tests individual bits in a register/data word; CPL tests for a pattern of bits | §3.3, PDF p.70 / printed 3-16 |
| Address range | PLU instructions can operate anywhere in data address space — RAM flags and control registers of on- and off-chip peripherals | §3.3, PDF p.70 / printed 3-16 |
| Worked examples | CBCR init: `SPLK #021h,CBCR` (DP=0) selects AR1 for circular buffer 1 and AR2 for buffer 2 without enabling; `OPL #088h,CBCR` sets bits 7 and 3, enabling both buffers. `APL #0FF00h,TEMP` + `BCND HIGH_BITS_SET,NTC` tests high byte while clearing low byte. `XPL #1,TEMP` + `BCND BIT_SET,TC` toggles bit 0 and branches if it was set. | §3.3, PDF pp.69–70 / printed 3-15–3-16 |

## 5. Auxiliary register arithmetic unit — ARAU (§3.4)

| Item | Detail | Ref |
|---|---|---|
| AR file | Eight memory-mapped auxiliary registers AR0–AR7; indirect addressing of data memory or temporary data storage | §3.4, PDF p.71 / printed 3-17 |
| ARP | 3-bit auxiliary register pointer (in ST0), value 0–7 designates AR0–AR7 | §3.4, PDF p.71 / printed 3-17 |
| AR load/store | ARs and ARP loadable from data memory, ACC, PREG, or immediate operand; AR contents storable in data memory or usable as CALU inputs | §3.4, PDF p.71 / printed 3-17 |
| AR location | Memory-mapped ARs reside in data page 0 (§8.3.2, Ch. 8) | §3.4, PDF p.71 / printed 3-17 |
| ARAU role | Autoindexes current AR while data-memory location is addressed: ±1 or by INDX contents. CALU freed from address manipulation for parallel work. CALU can directly read/write ARs for advanced addressing (e.g. multiplier computing 3-D matrix addresses). | §3.4, PDF p.71 / printed 3-17 |
| ARAU arithmetic | 16-bit **unsigned** arithmetic (CALU is 32-bit 2s-complement) | §3.4, PDF p.74 / printed 3-20 |
| ARAU as GP unit | ARAU can serve as additional general-purpose arithmetic unit; AR file communicates directly with data memory | §3.4, PDF p.74 / printed 3-20 |
| BANZ / BANZD | Permit ARs as loop counters | §3.4, PDF p.74 / printed 3-20 |
| Block diagram | Fig. 3-6 (ST0 ARP(3), ST1 ARB(3), AR0–AR7, CBCR/CBSR/CBER, INDX, ARCR, DRB; ARAU → MUX → address buses) | §3.4, Fig. 3-6, PDF p.72 / printed 3-18 |
| Fig. 3-5 example | ARP=`011`₂ selects AR3=0FF3Ah; data-memory location 0FF3Ah holds 3121h. AR0=0537h, AR1=5150h, AR2=0E9FCh, AR4=103Bh, AR5=26B1h, AR6=0008h, AR7=843Dh (as printed). | §3.4, Fig. 3-5, PDF p.71 / printed 3-17 |
| ARAU inputs | INDX, ARCR, or eight LSBs of IREG as one input; other input is contents of current AR (pointed to by ARP) | §3.4, PDF p.72 / printed 3-18 |
| ARB | 3-bit auxiliary register pointer buffer; stores ARP on subroutine calls when the automatic context-switch feature is not used | §3.4, PDF p.74 / printed 3-20 |
| INDX / ARCR access | INDX and ARCR accessible via CALU regardless of NDX bit (e.g. SAMM ARCR writes only to ARCR) | §3.4, PDF p.74 / printed 3-20 |
| NDX / C2x compat | 'C2x uses AR0 for the extra-index implementation. After reset, LAR can load AR0; if NDX bit in PMST is set, LAR also loads INDX and ARCR, maintaining 'C2x compatibility. | §3.4, PDF p.73 / printed 3-19 |

### 5.1 ARAU functions (Table 3-2, complete)

| Function | Description | Example | Ref |
|---|---|---|---|
| Current AR + INDX → Current AR | Index by adding unsigned 16-bit integer in INDX | `ADD *0+` | §3.4, Table 3-2, PDF p.73 / printed 3-19 |
| Current AR − INDX → Current AR | Index by subtracting unsigned 16-bit integer in INDX | `ADD *0−` | §3.4, Table 3-2, PDF p.73 / printed 3-19 |
| Current AR + 1 → Current AR | Increment by 1 | `ADD *+` | §3.4, Table 3-2, PDF p.73 / printed 3-19 |
| Current AR − 1 → Current AR | Decrement by 1 | `ADD *−` | §3.4, Table 3-2, PDF p.73 / printed 3-19 |
| Current AR → Current AR | Do not modify current AR | `ADD *` | §3.4, Table 3-2, PDF p.73 / printed 3-19 |
| Current AR + IR(7–0) → Current AR | Add 8-bit immediate value | `ADRK #55h` | §3.4, Table 3-2, PDF p.73 / printed 3-19 |
| Current AR − IR(7–0) → Current AR | Subtract 8-bit immediate value | `SBRK #55h` | §3.4, Table 3-2, PDF p.73 / printed 3-19 |
| Current AR + rc(INDX) → Current AR | Bit-reversed indexing; add INDX with reversed-carry (rc) propagation | `ADD *BR0+` | §3.4, Table 3-2, PDF p.73 / printed 3-19 |
| Current AR − rc(INDX) → Current AR | Bit-reversed indexing; subtract INDX with reversed-carry (rc) propagation | `ADD *BR0−` | §3.4, Table 3-2, PDF p.73 / printed 3-19 |
| (Current AR) = (ARCR) → TC = 1 | Compare current AR to ARCR; if condition true, set TC (ST1); if false, clear TC | `CMPR 3` (condition select in instruction) | §3.4, Table 3-2, PDF p.73 / printed 3-19 |
| (Current AR) < (ARCR) → TC = 1 | As above, less-than condition | `CMPR 3` | §3.4, Table 3-2, PDF p.73 / printed 3-19 |
| (Current AR) > (ARCR) → TC = 1 | As above, greater-than condition | `CMPR 3` | §3.4, Table 3-2, PDF p.73 / printed 3-19 |
| (Current AR) ≠ (ARCR) → TC = 1 | As above, not-equal condition | `CMPR 3` | §3.4, Table 3-2, PDF p.73 / printed 3-19 |
| (Current AR) = (CBER) → Current AR = CBSR | Circular-buffer wrap: if current AR is at buffer end, reload start address. Test performed **before** execution of the AR modification. | `ADD *+` | §3.4, Table 3-2, PDF p.73 / printed 3-19 |

Notes on Table 3-2: INDX can be added/subtracted on any AR-update cycle; step >1 useful for matrix-column addressing. ARCR limits data blocks and supports logical comparisons with CMPR. (§3.4, PDF p.73 / printed 3-19)

### 5.2 ARAU pipeline hazards

| Hazard | Rule | Ref |
|---|---|---|
| ARAU vs CALU timing | ARAU updates ARs during decode phase (2nd pipeline stage); CALU writes during execution phase (4th stage). The two instructions immediately following a CALU write to an AR must not use the same AR for address generation. See Ch. 7, Pipeline. | §3.4, PDF p.72 / printed 3-18 |
| CALU load of AR | After a CALU load of an AR, a 2-instruction-cycle delay before the AR can be used for address generation | §3.4, PDF p.74 / printed 3-20 |

### 5.3 Circular buffers

| Rule | Detail | Ref |
|---|---|---|
| Count / concurrency | Two circular buffers can operate at a given time; controlled via CBCR | §3.4, PDF p.74 / printed 3-20 |
| Reset | Upon reset (rising edge of RS), both circular buffers are disabled | §3.4, PDF p.74 / printed 3-20 |
| Setup sequence | 1) Load CBSR1/CBSR2 with buffer start address. 2) Load CBER1/CBER2 with end address. 3) Load the AR to be used with an address between start and end. 4) Load CBCR with the appropriate AR number and set the enable bit (CENB1 or CENB2). | §3.4, PDF p.74 / printed 3-20 |
| Same-AR prohibition | Do not use the same AR to access both circular buffers, or unexpected results will occur | §3.4, PDF p.74 / printed 3-20 |
| Wrap test | As address steps through the buffer, AR value is compared against CBER **prior to** the AR update. If equal and an AR modification occurs, CBSR value is automatically loaded into the AR. If not equal, AR is modified as specified. | §3.4, PDF p.74 / printed 3-20 |
| Increment buffers | CBER value must be larger than CBSR value | §3.4, PDF p.74 / printed 3-20 |
| Decrement buffers | CBER value must be smaller than CBSR value | §3.4, PDF p.74 / printed 3-20 |
| Step-over | Other indirect addressing modes usable, but ARAU tests only for current AR = CBER; it does **not** detect an AR update that steps over the CBER value | §3.4, PDF p.74 / printed 3-20 |
| CBCR layout | Defined in §4.4.1 (Ch. 4) — see `04-program-control.md`, not here | §3.5.6, PDF p.76 / printed 3-22 |
| Further detail | §5.6, Circular Addressing (Ch. 5) | §3.4, PDF p.74 / printed 3-20 |

## 6. Data page pointer (DP)

| Item | Detail | Ref |
|---|---|---|
| DP width | 9 bits, held in ST0 (Fig. 3-1 shows `ST0 [DP]`, 9-bit field) | §3.1, Table 3-1, PDF p.58 / printed 3-4; Fig. 3-1, PDF p.57 / printed 3-3 |
| Ch. 3 coverage | No prose section on DP in Ch. 3; no reset value stated in Ch. 3. Direct addressing and DP use are defined in Ch. 5. | — |
| Related | SPLK example in §3.3 assumes DP = 0 for CBCR access | §3.3, PDF p.69 / printed 3-15 |

## 7. Stack / stack pointer

| Item | Detail | Ref |
|---|---|---|
| Hardware stack | 8 words deep × 16 bits (Fig. 3-1, "Stack (8×16)"); microcall stack (MCS) shown separately | §3.1, Fig. 3-1, PDF p.57 / printed 3-3 |
| Stack pointer register | **No stack-pointer register is defined anywhere in Ch. 3.** No push/pop behaviour is described in Ch. 3. | Ch. 3, PDF pp.55–79 / printed 3-1–3-25 (absence verified by full-text search of the Ch. 3 extraction) |
| Where defined | Stack operation / program control is Ch. 4 material — see `04-program-control.md` | §3, PDF p.55 / printed 3-1 (program controller is a CPU element, detailed in Ch. 4) |
| ARB on calls | 3-bit ARB stores ARP on subroutine calls when automatic context switch is not used | §3.4, PDF p.74 / printed 3-20 |

## 8. Register summary (§3.5) — all registers named in Ch. 3

CPU registers (except ST0 and ST1), peripheral registers, and I/O ports occupy data-memory space. (§3.5, PDF p.75 / printed 3-21)

| Register(s) | Width | Function (one line) | Reset value stated in Ch. 3? | Ref |
|---|---|---|---|---|
| AR0–AR7 | 16-bit each | Indirect-address pointers / general-purpose registers / counters; CALU- and ARAU/PLU-modifiable | Not stated | §3.5.1, PDF p.75 / printed 3-21 |
| ARCR | 16-bit | Address-boundary compare vs selected AR (CMPR → TC in ST1) | Not stated | §3.5.2, PDF p.75 / printed 3-21 |
| BMAR | 16-bit | Address for block moves and MAC ops; indirect-addressed second operand | Not stated | §3.5.3, PDF p.75 / printed 3-21 |
| RPTC | 16-bit | Repeat count for single-instruction repeat (RPT/RPTZ). Memory-mapped but **do not write to it** — undesired results. | Not stated | §3.5.4, PDF p.75 / printed 3-21 |
| BRCR | 16-bit | Block-repeat count; loadable before block repeat; changeable during repeat (avoid infinite loops) | Not stated | §3.5.4, PDF p.76 / printed 3-22 |
| PASR | 16-bit | Block-repeat start address; loaded by RPTB | Not stated | §3.5.4, PDF p.76 / printed 3-22 |
| PAER | 16-bit | Block-repeat end address; loaded by RPTB | Not stated | §3.5.4, PDF p.76 / printed 3-22 |
| ARR, AXR, BKR, BKX | 11-bit each | BSP (C56/C57 only): address receive / address transmit / receive-buffer-size / transmit-buffer-size; address generation for DRR/DXR in internal memory | Not stated | §3.5.5, PDF p.76 / printed 3-22 |
| SPCE | 16-bit | BSP control extension register: BSP mode control and status | Not stated | §3.5.5, PDF p.76 / printed 3-22 |
| CBSR1, CBSR2 | 16-bit each | Circular-buffer start addresses | Not stated | §3.5.6, PDF p.76 / printed 3-22 |
| CBER1, CBER2 | 16-bit each | Circular-buffer end addresses | Not stated | §3.5.6, PDF p.76 / printed 3-22 |
| CBCR | 8-bit per Table 3-1 / Figs. 3-1, 3-6; §3.5.6 prose says 16-bit — see contradiction C1, §10 | Circular-buffer control; identifies ARs used, enables buffers | **Disabled on reset (rising edge of RS)** — both buffers | §3.5.6, PDF p.76 / printed 3-22; §3.4, PDF p.74 / printed 3-20 |
| DBMR | 16-bit | PLU dynamic (execution-time programmable) mask register | Not stated | §3.5.7, PDF p.76 / printed 3-22 |
| GREG | 16-bit | Allocates part of local data space as global memory; defines overlay amount | Not stated | §3.5.8, PDF p.77 / printed 3-23 |
| HPIC, HPIA | Widths not stated in Ch. 3 (HPI is an 8-bit-wide parallel interface) | HPI ('C57 only): control word / host address register | Not stated | §3.5.9, PDF p.77 / printed 3-23 |
| INDX | 16-bit | ARAU step value (add/subtract >1); bit-reversal block dimension | Not stated | §3.5.10, PDF p.77 / printed 3-23 |
| PA0–PA15 (I/O space) | 16 locations, 50h–5Fh | I/O space addressable via local-data-space modes; readable into CALU, writable from ACC, PLU-operable, memory-mapped-addressable, IN/OUT-addressable | Not stated | §3.5.11, PDF p.77 / printed 3-23 |
| IREG | 16-bit | Holds opcode of instruction being executed; used during program control | Not stated | §3.5.12, PDF p.77 / printed 3-23 |
| IMR | 16-bit | Interrupt mask register; individually masks interrupts | Not stated | §3.5.13, PDF p.77 / printed 3-23 |
| IFR | 16-bit | Interrupt flag register; interrupt status, updated regardless of IMR and INTM (ST0) | Not stated | §3.5.13, PDF p.77 / printed 3-23 |
| PMST | 16-bit | Processor mode status register; configures memory (§8.2.1, §8.3.1). Bit layout §4.4.2, Ch. 4. | Not stated in Ch. 3 | §3.5.14, PDF p.78 / printed 3-24 |
| PREG | 32-bit | Multiply result; high/low words individually accessible | Not stated (but RPTZ clears PREG — §3.2.1) | §3.5.15, PDF p.78 / printed 3-24 |
| SPC | 16-bit | Serial-port control register: mode control and status | Not stated | §3.5.16, PDF p.78 / printed 3-24 |
| DRR / DXR | 16-bit each | Serial-port data receive / data transmit registers | Not stated | §3.5.16, PDF p.78 / printed 3-24 |
| XSR / RSR | 16-bit each | Serial-port transmit / receive shift registers (DXR→pin, pin→DRR) | Not stated | §3.5.16, PDF p.78 / printed 3-24 |
| PDWSR | 16-bit | Program/data wait-state register: eight 2-bit fields, one per 16K-word block (most devices — see §9) | Not stated | §3.5.17, PDF p.78 / printed 3-24 |
| IOWSR | 16-bit | I/O wait-state register | Not stated | §3.5.17, PDF p.78 / printed 3-24 |
| CWSR | 5-bit | Wait-state control register; determines wait-state range; BIG bit partitions I/O space (cleared: eight pairs of I/O ports, 2-bit fields per pair; set: eight 8K-word blocks, 2-bit fields each, as PDWSR) | Not stated | §3.5.17, PDF p.78 / printed 3-24 |
| ST0, ST1 | 16-bit each | Status registers; defined §4.4.3, Ch. 4 — see `04-program-control.md` | Not stated in Ch. 3 | §3.5.18, PDF p.79 / printed 3-25 |
| TREG0 | 16-bit | Multiplicand for multiplier; loadable via CALU by LT, LTA, LTD, LTP, LTS, SQRA, SQRS, MAC, MACD, MADS, MADD | Not stated | §3.5.19, PDF p.79 / printed 3-25 |
| TREG1 | 5-bit | Dynamic shift count for prescaling shifter | Not stated | §3.5.19, PDF p.79 / printed 3-25 |
| TREG2 | 4-bit | Dynamic bit address for BITT instruction | Not stated | §3.5.19, PDF p.79 / printed 3-25 |
| TIM | Width not stated in Ch. 3 | Timer counter register: current timer count | Not stated | §3.5.20, PDF p.79 / printed 3-25 |
| PRD | Width not stated in Ch. 3 | Timer period register: defines timer period | Not stated | §3.5.20, PDF p.79 / printed 3-25 |
| TCR | 16-bit | Timer control register | Not stated | §3.5.20, PDF p.79 / printed 3-25 |
| TSPC | 16-bit | TDM serial-port control register: mode control and status | Not stated | §3.5.21, PDF p.79 / printed 3-25 |
| TRCV / TDXR | 16-bit each | TDM data receive / data transmit registers | Not stated | §3.5.21, PDF p.79 / printed 3-25 |
| TRSR | 16-bit | TDM data receive shift register (pin → TRCV) | Not stated | §3.5.21, PDF p.79 / printed 3-25 |
| TCSR | 16-bit | TDM channel-select register: time slot(s) in which this device transmits | Not stated | §3.5.21, PDF p.79 / printed 3-25 |
| TRTA | 16-bit | TDM receive/transmit address register: low 8 bits RA0–RA7 = receive address; high 8 bits TA0–TA7 = transmit address | Not stated | §3.5.21, PDF p.79 / printed 3-25 |
| TRAD | 16-bit | TDM receive-address register: status of TDM address line (TADD) | Not stated | §3.5.21, PDF p.79 / printed 3-25 |
| ACC | 32-bit | Accumulator; ACCH bits 16–31, ACCL bits 0–15 | Not stated | §3.2.2, PDF p.65 / printed 3-11 |
| ACCB | 32-bit | Accumulator buffer | Not stated | §3.2.2, PDF p.66 / printed 3-12 |
| PC / PFC | 16-bit (per Fig. 3-1 width rule) | Program counter / prefetch counter | Not stated in Ch. 3 | §3.1, Fig. 3-1, PDF p.57 / printed 3-3 |
| DP | 9-bit (in ST0) | Data-memory page pointer | Not stated in Ch. 3 | §3.1, Table 3-1, PDF p.58 / printed 3-4 |

### Temporary registers and TRM (C2x compatibility)

| Rule | Detail | Ref |
|---|---|---|
| TREG0 loads | LT, LTA, LTD, LTP, LTS, SQRA, SQRS, MAC, MACD, MADS, MADD load TREG0 via CALU | §3.5.19, PDF p.79 / printed 3-25 |
| TRM = 0 (cleared, in PMST) | Any 'C2x instruction that loads TREG0 writes to **all three** TREGs — maintains 'C5x object-code compatibility with 'C2x | §3.5.19, PDF p.79 / printed 3-25 |
| TRM = 1 (set) | Multiple temporary registers enabled (per Table 3-1 name "Enable multiple temporary registers bit"); TREGs load independently — INFERENCE from the bit name + the TRM=0 rule above; the manual states only the cleared case in Ch. 3. | §3.5.19, PDF p.79 / printed 3-25; Table 3-1, PDF p.60 / printed 3-6 |
| TREG1 role | 5-bit dynamic shift count (prescaler; ADDT/LACT/SUBT; SATH bit 4 / SATL bits 0–3) | §3.5.19, PDF p.79 / printed 3-25; §3.2.2, PDF p.68 / printed 3-14 |
| TREG2 role | 4-bit dynamic bit address for BITT | §3.5.19, PDF p.79 / printed 3-25 |

## 9. Reset values stated in Ch. 3 (complete — only two exist)

| Item | Reset value / state | Ref |
|---|---|---|
| Carry bit C | **Set (1) on reset** | §3.2.2, PDF p.67 / printed 3-13 |
| Circular buffers 1 and 2 | **Disabled on reset** (rising edge of RS) | §3.4, PDF p.74 / printed 3-20 |
| Everything else (ACC, ACCB, PREG, TREG0/1/2, AR0–AR7, ARP/ARB, DP, ST0, ST1, PMST, PC, RPTC, BRCR, PASR, PAER, INDX, ARCR, BMAR, DBMR, IMR, IFR, wait-state registers, serial/timer/TDM/BSP/HPI registers) | **No reset value is stated anywhere in Ch. 3.** Do not assume zero. Reset values for ST0/ST1/PMST are Ch. 4 material — see `04-program-control.md`; other reset values, if the manual gives them, are in Ch. 8/9. | Ch. 3, PDF pp.55–79 / printed 3-1–3-25 (absence verified by full-text search of the Ch. 3 extraction) |

## 10. Per-device differences stated in Ch. 3

| Feature | Devices | Ref |
|---|---|---|
| Buffered serial port (BSP): ARR, AXR, BKR, BKX, SPCE; 2K-word buffer in internal memory; full-duplex double-buffered + autobuffering unit (ABU) | 'C56 and 'C57 only | §3.5.5, PDF p.76 / printed 3-22 |
| Host port interface (HPI): HPIC, HPIA; 8-bit-wide parallel interface to a host processor | 'C57 only (§3.5.9); §9.10 narrows to 'C57S and 'LC57 | §3.5.9, PDF p.77 / printed 3-23 |
| Wait states, scheme A (PDWSR = eight 2-bit fields per 16K-word block; IOWSR under CWSR control) | "Most 'C5x devices" | §3.5.17, PDF p.78 / printed 3-24 |
| Wait states, scheme B (program, data, I/O each a single 3-bit field in PDWSR, 0–7 wait states each) | 'C52, 'LC56, 'C57S, 'LC57 | §3.5.17, PDF p.78 / printed 3-24 |
| INFERENCE — C51 wait-state scheme: the C51 is not in the scheme-B exception list, so it falls under "most devices" (scheme A). Labelled INFERENCE: Ch. 3 never names the C51 in §3.5.17. Verify against Ch. 9 (§9.4) before relying on it. | C51 (inferred) | §3.5.17, PDF p.78 / printed 3-24 |
| TDM serial port, Serial Port 2, BSP, host-port interface, timer, emulation | Marked † "not available on all devices" in Fig. 3-1; no per-device table in Ch. 3 | §3.1, Fig. 3-1, PDF p.57 / printed 3-3 |
| No other C51-specific CPU behaviour is stated in Ch. 3 | — | Ch. 3, PDF pp.55–79 |

## 11. Contradictions, errors, and unverified items

### C1 — CBCR width: 8-bit vs 16-bit (contradiction)

| Reading | Sources | Ref |
|---|---|---|
| CBCR is 8 bits | Table 3-1 "CBCR(8)"; Fig. 3-1 "CBCR(8)"; Fig. 3-6 "CBCR(8)" | Table 3-1, PDF p.58 / printed 3-4; Fig. 3-1, PDF p.57 / printed 3-3; Fig. 3-6, PDF p.72 / printed 3-18 |
| CBCR is 16 bits | §3.5.6 prose: "The 16-bit circular buffer control register (CBCR)" | §3.5.6, PDF p.76 / printed 3-22 |
| Supporting the 8-bit reading | §3.3 worked example uses SPLK #021h and OPL #088h on CBCR — both values fit in 8 bits, and OPL #088h is described as "set bit 7 and bit 3", i.e. the top bit used is bit 7. | §3.3, PDF p.69 / printed 3-15 |
| **Normative (this file): 8-bit.** Three tabular/figure sources plus a consistent worked example outweigh one prose line; the §3.5.6 "16-bit" reads as boilerplate applied to the surrounding registers (CBSR/CBER are genuinely 16-bit). CBCR bit layout itself is §4.4.1 (Ch. 4) — check there before finalising. | | |

### C2 — ACCH / ACCL called "byte" in Table 3-1 (contradiction)

| Reading | Sources | Ref |
|---|---|---|
| "Accumulator high byte" / "Accumulator low byte" | Table 3-1 | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| ACC split into **two 16-bit segments** ACCH/ACCL; SACH/SACL store 16-bit words; postscaler examples move 16-bit values (B380h, 91A2h) | §3.2.2 prose + examples | §3.2.2, PDF p.65 / printed 3-11 |
| **Normative (this file): 16-bit words.** The §3.2.2 prose and the worked postscaler examples are unambiguous; "byte" in Table 3-1 is a wording error. | | |

### C3 — BSAR worked example is arithmetically wrong (manual error, verified)

| Item | Value | Ref |
|---|---|---|
| Manual prints | ACC = 1234 5678h, `BSAR 7` → ACC = 0246 8ACEh | §3.2.2, PDF p.68 / printed 3-14 |
| Verified arithmetic | 1234 5678h >> 7 = 0024 68ACh (0x12345678 = 305,419,896; ÷128 = 2,386,092 = 0x2468AC) | Recomputed from the printed operands; no manual source |
| Cross-check | 1234 5678h >> 3 = 0246 8ACFh — also not the printed value, so the printed 0246 8ACEh matches no single right-shift of the operand. | Recomputed |
| **Normative (this file): the shift definition (BSAR n = right shift by n, 1–16, SXM fill) stands; the printed result 0246 8ACEh is wrong and must not be used as a test vector. Correct result: 0024 68ACh.** | | §3.2.2, PDF p.68 / printed 3-14 |

### C4 — CRLT / CRGT example reads as sequential code but cannot be (ambiguity)

| Item | Detail | Ref |
|---|---|---|
| Manual prints | ACC=1234 5678h, ACCB=7654 3210h: `CRLT` → ACC=ACCB=1234 5678h, C=1. `CRGT` → ACC=ACCB=7654 3210h, C=0. | §3.2.2, PDF p.66 / printed 3-12 |
| Problem | If the two instructions execute sequentially, CRLT leaves both registers at 1234 5678h, so a following CRGT would leave 1234 5678h (max of two equal values), not 7654 3210h. | Logic from the printed values |
| **Normative reading (this file): the two lines are independent examples from the same initial state, not a sequential program.** The min/max semantics and C flag behaviour are unaffected. | | |

### Unverified / gaps (extraction or manual silence — do not guess)

| # | Item | Ref |
|---|---|---|
| U1 | `dma(7)` in Table 3-1 — meaning not explained anywhere in Ch. 3 | §3.1, Table 3-1, PDF p.58 / printed 3-4 |
| U2 | `RBIT` label in Fig. 3-1 — not in Table 3-1, not explained in Ch. 3 text | §3.1, Fig. 3-1, PDF p.57 / printed 3-3 |
| U3 | SFR (0–16) right prescaler in Fig. 3-2 — no prose description in Ch. 3; its role (if any) in BSAR / right-shift paths is not stated | §3.2, Fig. 3-2, PDF p.62 / printed 3-8 |
| U4 | Fig. 3-1, Fig. 3-2, Fig. 3-4, Fig. 3-6 are vector block diagrams; pdftotext -layout recovers labels but not connectivity. Wire-level data paths in the figures were **not** independently verified from the extraction — only the labelled blocks, widths, and notes are cited above. | §3.1–§3.4, Figs. 3-1/3-2/3-4/3-6, PDF pp.57/62/69/72 |
| U5 | No reset values for any register except C (=1) and circular-buffer enable (=disabled) are stated in Ch. 3 — see §9. In particular ACC, PREG, TREG0/1/2, ARs, DP, ST0/ST1, PMST reset values are **not** in Ch. 3. | Ch. 3, PDF pp.55–79 |
| U6 | HPIC/HPIA, TIM, PRD register widths are not stated in Ch. 3 (§3.5.9, §3.5.20 give no widths). | §3.5.9, PDF p.77 / printed 3-23; §3.5.20, PDF p.79 / printed 3-25 |
| U7 | SXM effect on ROL/ROR is not stated in Ch. 3 (only SFR is stated to depend on SXM; SFL explicitly does not). | §3.2.2, PDF p.68 / printed 3-14 |

## 12. Cross-references out of Ch. 3 (pointers, not content)

| Topic | Where defined | Cited from |
|---|---|---|
| ST0/ST1 bit layouts; PMST bit layout (§4.4.2, §4.4.3); CBCR bit layout (§4.4.1) | Ch. 4 — see `04-program-control.md` | §3.5.6, §3.5.14, §3.5.18 |
| Single-instruction repeat (RPT/RPTZ, RPTC) | §4.6, Ch. 4 | §3.5.4 |
| Block repeat (BRCR, PASR, PAER, RPTB) | §4.7, Ch. 4 | §3.5.4 |
| Interrupts (IMR, IFR) | §4.8, Ch. 4 | §3.5.13 |
| Indirect addressing; ARCR/INDX use; circular addressing | §5.2, §5.6, Ch. 5 | §3.5.1, §3.5.2, §3.5.6, §3.5.10 |
| Dedicated-register addressing (BMAR) | §5.4, Ch. 5 | §3.5.3 |
| PLU instruction list | Table 6–6, Ch. 6 | §3.3, PDF p.70 / printed 3-16 |
| Pipeline stages / hazards | Ch. 7 | §3.4, PDF p.72 / printed 3-18 |
| Memory configuration via PMST; AR data-page-0 map | §8.2.1, §8.3.1, §8.3.2, Ch. 8 | §3.4, §3.5.14 |
| Global memory (GREG) | §8.4, Ch. 8 | §3.5.8 |
| Wait-state generators | §9.4, Ch. 9 | §3.5.17 |
| Timer; serial port; TDM serial port; BSP; HPI | §9.3, §9.7, §9.8, §9.9, §9.10, Ch. 9 | §3.5.5, §3.5.9, §3.5.16, §3.5.20, §3.5.21 |

## 13. Worked-example verification log (recomputed, not manual claims)

| Example | Manual result | Recomputed | Verdict | Ref |
|---|---|---|---|---|
| LACC #01111h,8 → ACC | 00111100h | 0x1111 << 8 = 0x111100 = 00111100h | Correct | §3.2.2, PDF p.65 / printed 3-11 |
| APAC (ACC=00111100h, PREG=00222200h) | 00333300h | 0x111100 + 0x222200 = 0x333300 | Correct | §3.2.2, PDF p.65 / printed 3-11 |
| ADDB (ACC=00333300h, ACCB=00333300h) | 00666600h | 0x333300 + 0x333300 = 0x666600 | Correct | §3.2.2, PDF p.65 / printed 3-11 |
| SACL TEMP1,7 (ACC=FF234567h) | B380h | 0x4567 << 7 & 0xFFFF = 0xB380 | Correct | §3.2.2, PDF p.65 / printed 3-11 |
| SACH TEMP2,7 (ACC=FF234567h) | 91A2h | (0xFF23 << 7 \| 0x4567 >> 9) & 0xFFFF = 0x91A2 | Correct | §3.2.2, PDF p.65 / printed 3-11 |
| SATH+SATL (SHIFT=01Bh, ACC=12345678h) | 00001234h, then 00000002h | 0x12345678 >> 16 = 0x1234; 0x1234 >> 11 = 0x2 | Correct | §3.2.2, PDF p.68 / printed 3-14 |
| BSAR 7 (ACC=12345678h) | 02468ACEh | 0x12345678 >> 7 = 0x002468AC | **Wrong — see C3** | §3.2.2, PDF p.68 / printed 3-14 |
| Fig. 3-3 carry cases (6) | As printed | All six recomputed, incl. ADDC carry-in and SUBB inverted-borrow cases | Correct | §3.2.2, Fig. 3-3, PDF p.67 / printed 3-13 |
| CRLT/CRGT (ACC=12345678h, ACCB=76543210h) | Min 12345678h C=1; max 76543210h C=0 | Min/max correct as independent examples | Correct as independent examples; sequential reading impossible — see C4 | §3.2.2, PDF p.66 / printed 3-12 |
