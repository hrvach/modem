# Chapter 5 — Addressing Modes (TMS320C5x User's Guide, SPRU056D, June 1998)

- **Source (only authority):** `~/workspace/user/files/spru056d.pdf` — SPRU056D, June 1998. Chapter 5, PDF pp.131–152 = printed pp.5-1–5-22. Chapter 6 starts PDF p.153.
- **Extraction:** `pdftotext -layout` (`/tmp/spru056d-layout.txt`); page N of the extraction is the Nth form-feed section, i.e. PDF p.N.
- **Page-number convention used throughout:** every claim cites manual section + table/figure number + **PDF p.** (index page) **and printed p.** (e.g. PDF p.132 / printed p.5-2). Printed p. = PDF p. − 130 throughout Ch. 5 (verified against the footers on every page, PDF pp.131–152).
- **Scope:** Ch. 5 covers exactly six modes (§5.1–§5.6, Ch. 5 contents, PDF p.131 / printed p.5-1): direct, indirect, immediate, dedicated-register, memory-mapped register, circular. **Not in Ch. 5** (see §9 below): stack addressing, I/O-port addressing, TBLR/TBLW, and a standalone program-memory-address (pma) treatment — none of those terms appear in Ch. 5; do not import them from other chapters.
- **Notation:** `dma` = 7-bit direct data-memory address field in the instruction; `DAB` = 16-bit internal direct data-memory address bus; `DP` = 9-bit data-page pointer (ST0); `ARn` = auxiliary register n; `ARP` = auxiliary-register pointer (ST1); `ARB` = auxiliary-register buffer (ST1); `ARAU` = auxiliary-register arithmetic unit; `INDX` = index register; `ARCR` = auxiliary-register compare register; `rcINDX` = INDX added/subtracted with reverse-carry propagation; `PFC` = prefetch counter; `MCS` = microcall stack.

## 1. Mode inventory

| § | Mode | Printed pp. | PDF pp. | One-line definition (manual) |
|---|---|---|---|---|
| 5.1 | Direct addressing | 5-2–5-3 | 132–133 | 7-bit dma in instruction + 9-bit DP (ST0) = 16-bit address on DAB (§5.1, PDF p.132 / printed p.5-2) |
| 5.2 | Indirect addressing | 5-4–5-13 | 134–143 | 16-bit address held in current AR (ARP-selected AR0–AR7); ARAU post-access update (§5.2, PDF p.134 / printed p.5-4) |
| 5.2.3 | Bit-reversed addressing (sub-mode of indirect) | 5-12–5-13 | 142–143 | INDX added/subtracted with reverse-carry propagation; FFT data resequencing (§5.2.3, PDF p.142 / printed p.5-12) |
| 5.3 | Immediate addressing | 5-14–5-16 | 144–146 | Operand is in the instruction word(s): 1-word short (8/9/13-bit) or 2-word long (16-bit) (§5.3, PDF p.144 / printed p.5-14) |
| 5.4 | Dedicated-register addressing | 5-17–5-18 | 147–148 | Address/operand comes from BMAR or DBMR (special-purpose memory-mapped CPU registers); like long immediate except the address comes from the register (§5.4, PDF p.147 / printed p.5-17) |
| 5.5 | Memory-mapped register addressing | 5-19–5-20 | 149–150 | Like direct, except the 9 MSBs of the address are forced to 0 (DP ignored); reaches page 0 / DARAM B2 without changing DP (§5.5, PDF p.149 / printed p.5-19) |
| 5.6 | Circular addressing | 5-21–5-22 | 151–152 | Two concurrent circular buffers via ARs, controlled by CBSR1/2, CBER1/2, CBCR (§5.6, PDF p.151 / printed p.5-21) |

## 2. Direct addressing (§5.1, PDF pp.132–133 / printed pp.5-2–5-3)

### 2.1 Address formation

| Field | Width | Source | Value |
|---|---|---|---|
| DP (data-page pointer) | 9 bits | ST0 | Selects one of 512 data-memory pages (§5.1, Fig. 5-1, PDF p.132 / printed p.5-2) |
| dma | 7 bits | Instruction bits 6–0 | Selects one of 128 words within the page (§5.1, Fig. 5-1, PDF p.132 / printed p.5-2) |
| Full data-memory address | 16 bits | `{DP, dma}` on DAB | `address = (DP << 7) \| dma` (§5.1, Fig. 5-1, PDF p.132 / printed p.5-2) |

- DP is loaded with `LDP` or `LST #0` (§5.1, PDF p.132 / printed p.5-2).
- **DP is NOT initialized by reset and is undefined after power-up.** Programs must initialize DP in software; development tools use default DP values, so a program that omits DP init may run under tools but fail on the device (§5.1 Note, PDF p.133 / printed p.5-3).
- Page 0 of the 512-page map holds the memory-mapped registers and DARAM B2 (Fig. 5-1, PDF p.132 / printed p.5-2).

### 2.2 Direct-addressing instruction format (Fig. 5-2, PDF p.133 / printed p.5-3)

| Instruction bits | Value | Meaning |
|---|---|---|
| 15–8 | opcode | Opcode (§5.1, Fig. 5-2, PDF p.133 / printed p.5-3) |
| 7 | 0 | Direct addressing mode (§5.1, Fig. 5-2, PDF p.133 / printed p.5-3) |
| 6–0 | dma | 7-bit direct address (§5.1, Fig. 5-2, PDF p.133 / printed p.5-3) |

- Worked example (Fig. 5-2, PDF p.133 / printed p.5-3): `LDP #019Dh` then `ADD 010h, 5`. DP = `019Dh` (9 bits `1 1001 1101`), dma = `010h`, DAB = `0CE90h` — i.e. `(019Dh << 7) | 010h`. Machine-code bits as extracted: `0010 0101 0 000 10000` (opcode byte `25h`, bit 7 = 0, dma `010h`).
- The hex shown in the figure captions (e.g. "ADD opcode 010h", Fig. 5-2) is the **dma**, not the opcode byte — see §8.1.

### 2.3 Direct-address dma ranges

| dma range | Page | Contents (per Fig. 5-1) |
|---|---|---|
| 00h–7Fh with DP = 0 | Page 0 (0000h–007Fh) | Memory-mapped registers and DARAM B2 (§5.1, Fig. 5-1, PDF p.132 / printed p.5-2; §5.5, PDF p.149 / printed p.5-19) |
| 00h–7Fh with DP = 1–511 | Pages 1–511 | General data memory, 128 words per page (§5.1, PDF p.132 / printed p.5-2) |

## 3. Indirect addressing (§5.2, PDF pp.134–143 / printed pp.5-4–5-13)

### 3.1 Hardware and AR selection (§5.2, PDF p.134 / printed p.5-4; Fig. 5-3)

| Item | Fact |
|---|---|
| Auxiliary registers | Eight 16-bit registers AR0–AR7 (§5.2, PDF p.134 / printed p.5-4) |
| Addressable space | Any location in the 64K-word data-memory space, via the 16-bit address in an AR (§5.2, PDF p.134 / printed p.5-4) |
| ARP | Auxiliary-register pointer, values 0–7 select AR0–AR7; the ARP-selected register is the **current AR** (§5.2, PDF p.134 / printed p.5-4) |
| Loading an AR | `LAR` instruction (§5.2, PDF p.134 / printed p.5-4) |
| Changing an AR | `ADRK`, `MAR`, `SBRK`, or the indirect-addressing field of any instruction supporting indirect addressing (§5.2, PDF p.134 / printed p.5-4) |
| ARAU | Auxiliary-register arithmetic unit; unsigned 16-bit arithmetic; performs the AR update **after** the current instruction has used the AR contents as the address (§5.2, PDF p.134 / printed p.5-4) |
| ARAU timing | AR arithmetic runs in the **decode phase** of the pipeline, so the address is generated before the decode phase of the next instruction; the AR is incremented/decremented after use in the current instruction (§5.2, PDF p.135 / printed p.5-5) |
| Non-address uses of ARs | (a) `CMPR` compares the current AR with ARCR and puts the result in the TC flag (ST1), supporting conditional branches/calls/returns; (b) `LAR`/`SAR` use ARs as temporary storage (§5.2, PDF p.135 / printed p.5-5) |

### 3.2 Memory-mapped writes to ARs — pipeline hazard (§5.2, PDF p.135 / printed p.5-5)

- The ARs can be loaded via the data bus by memory-mapped writes. The instructions that can write to the memory-mapped ARs are (§5.2, PDF p.135 / printed p.5-5):

| | | | |
|---|---|---|---|
| `APL` | `OPL` | `SAMM` | `XPL` |
| `BLDD` | `SACH` | `SMMR` | |
| `LMMR` | `SACL` | `SPLK` | |

- **Hazard:** memory-mapped ARs are modified in the **execute** phase, so a pipeline conflict occurs if one of the **next two instruction words** modifies that AR. See Ch. 7, Pipeline (§5.2, PDF p.135 / printed p.5-5).

### 3.3 Indirect-addressing options (§5.2.1, PDF pp.135–136 / printed pp.5-5–5-6)

The manual says the 'C5x "provides four indirect addressing options" (§5.2.1, PDF p.135 / printed p.5-5) — four *categories*, which expand to seven assembly symbols (the ±1 and ±INDX categories each have an increment and a decrement form):

| # | Category (§5.2.1) | Symbols | Semantics (address used first, then AR updated) |
|---|---|---|---|
| 1 | No increment or decrement | `*` | AR used as address, unchanged (§5.2.1, PDF p.136 / printed p.5-6) |
| 2 | Increment or decrement by 1 | `*+`, `*-` | AR ± 1 after access (§5.2.1, PDF pp.135–136 / printed pp.5-5–5-6) |
| 3 | Increment or decrement by an index amount | `*0+`, `*0-` | AR ± INDX after access; INDX is the index amount (§5.2.1, PDF p.135 / printed p.5-5) |
| 4 | Increment or decrement by an index amount using reverse carry | `*BR0+`, `*BR0-` | AR ± INDX after access, addition/subtraction done with **reverse-carry propagation** (§5.2.1, PDF p.136 / printed p.5-6) |

- All indexing operations are performed on the current AR **in the same cycle as the original instruction's decode phase** (§5.2.1, PDF p.136 / printed p.5-6).
- ARP can be loaded with a new value by the same instruction (see N/NAR, §3.4) (§5.2.1, PDF p.136 / printed p.5-6).

### 3.4 Indirect-addressing opcode format — encoding bits (Table 5-1, Fig. 5-4, §5.2.2, PDF pp.137–138 / printed pp.5-7–5-8)

Single-word format, bits 15–0:

| Bits | Name | Meaning |
|---|---|---|
| 15–8 | (opcode) | 8-bit opcode field (Table 5-1, PDF p.137 / printed p.5-7) |
| 7 | I | Addressing-mode bit: I=0 direct, I=1 indirect (Table 5-1, PDF p.137 / printed p.5-7) |
| 6 | IDV | Index-register bit: IDV=0 → INDX not used, increment/decrement (if any) is by 1; IDV=1 → INDX used, increment/decrement (if any) is by INDX contents or by reverse-carry propagation (Table 5-1, PDF p.138 / printed p.5-8) |
| 5 | INC | AR increment bit: INC=0 not incremented; INC=1 incremented as determined by IDV (Table 5-1, PDF p.138 / printed p.5-8) |
| 4 | DEC | AR decrement bit: DEC=0 not decremented; DEC=1 decremented as determined by IDV (Table 5-1, PDF p.138 / printed p.5-8) |
| 3 | N | Next-AR indicator: N=0 ARP unchanged; N=1 NAR is loaded into ARP and the old ARP value is loaded into ARB (ST1) (Table 5-1, PDF p.138 / printed p.5-8) |
| 2–0 | NAR | Next-AR value (3 bits); loaded into ARP iff N=1 (Table 5-1, PDF p.138 / printed p.5-8) |

- **Applicability restriction:** indirect addressing can be used with **all instructions except those with immediate operands or with no operands** (§5.2.2, PDF p.137 / printed p.5-7).
- Figure 5-4 (indirect addressing opcode format diagram, PDF p.137 / printed p.5-7): [UNVERIFIED — extraction garbled, manual §5.2.2, PDF p.137] — the diagram body renders as `Á` box-drawing characters in the layout extraction; the bit-field layout above is taken from Table 5-1 (same page), which is legible, and from Table 5-3.

### 3.5 Indirect-addressing arithmetic operations — full table (Table 5-2, PDF p.139 / printed p.5-9)

Transcribed verbatim (IDV / INC / DEC → operation on current AR):

| IDV | INC | DEC | Arithmetic operation performed on current AR |
|---|---|---|---|
| 0 | 0 | 0 | No operation on current AR |
| 0 | 0 | 1 | (Current AR) − 1 → current AR |
| 0 | 1 | 0 | (Current AR) + 1 → current AR |
| 0 | 1 | 1 | **Reserved** |
| 1 | 0 | 0 | (Current AR) − INDX [reverse carry propagation] → current AR |
| 1 | 0 | 1 | (Current AR) − INDX → current AR |
| 1 | 1 | 0 | (Current AR) + INDX → current AR |
| 1 | 1 | 1 | (Current AR) + INDX [reverse carry propagation] → current AR |

(Table 5-2, §5.2.2, PDF p.139 / printed p.5-9.)

- Note the non-obvious mapping: reverse-carry is selected when INC == DEC (both 0 → reverse-carry subtract; both 1 → reverse-carry add), while plain INDX add/subtract is selected when INC != DEC. This is exactly what Table 5-3 encodes (see §3.6).

### 3.6 Instruction-field bit values — full table (Table 5-3, PDF pp.139–140 / printed pp.5-9–5-10)

Columns in the manual: bits 15–8 (opcode), 7 (I), 6 (IDV), 5 (INC), 4 (DEC), 3 (N), 2–0 (NAR), notation, operation. I = 1 in every row. Transcribed in full (14 rows):

| I | IDV | INC | DEC | N | NAR | Notation | Operation |
|---|---|---|---|---|---|---|---|
| 1 | 0 | 0 | 0 | 0 | — | `*` | No operation on current AR |
| 1 | 0 | 0 | 0 | 1 | n | `*, ARn` | NAR → ARP |
| 1 | 0 | 0 | 1 | 0 | — | `*-` | (Current AR) − 1 → current AR |
| 1 | 0 | 0 | 1 | 1 | n | `*-, ARn` | (Current AR) − 1 → current AR; NAR → ARP |
| 1 | 0 | 1 | 0 | 0 | — | `*+` | (Current AR) + 1 → current AR |
| 1 | 0 | 1 | 0 | 1 | n | `*+, ARn` | (Current AR) + 1 → current AR; NAR → ARP |
| 1 | 1 | 0 | 0 | 0 | — | `*BR0-` | (Current AR) − rcINDX → current AR |
| 1 | 1 | 0 | 0 | 1 | n | `*BR0-, ARn` | (Current AR) − rcINDX → current AR; NAR → ARP |
| 1 | 1 | 0 | 1 | 0 | — | `*0-` | (Current AR) − INDX → current AR |
| 1 | 1 | 0 | 1 | 1 | n | `*0-, ARn` | (Current AR) − INDX → current AR; NAR → ARP |
| 1 | 1 | 1 | 0 | 0 | — | `*0+` | (Current AR) + INDX → current AR |
| 1 | 1 | 1 | 0 | 1 | n | `*0+, ARn` | (Current AR) + INDX → current AR; NAR → ARP |
| 1 | 1 | 1 | 1 | 0 | — | `*BR0+` | (Current AR) + rcINDX → current AR |
| 1 | 1 | 1 | 1 | 1 | n | `*BR0+, ARn` | (Current AR) + rcINDX → current AR; NAR → ARP |

(Table 5-3, §5.2.2, PDF p.139 / printed p.5-9 and PDF p.140 / printed p.5-10 — the last two rows, `*BR0+` / `*BR0+, ARn`, are on the continued table, PDF p.140 / printed p.5-10.)

- `rcINDX` = INDX with reverse-carry propagation (§5.2.2 / Table 5-3, PDF pp.139–140 / printed pp.5-9–5-10).
- The `, ARn` suffix sets N=1 and NAR=n: after the instruction, ARP = n and the old ARP is copied to ARB (Table 5-1, PDF p.138 / printed p.5-8).
- There is **no** row for IDV=0, INC=1, DEC=1 — that combination is Reserved per Table 5-2 (§3.5); i.e. there is no `*` form that both increments and decrements by 1.

### 3.7 Worked examples 5-1–5-8 (all `ADD <indirect>, 8`; opcode byte 28h)

Each example: the data at the address in the current AR is shifted left 8 bits and added to the ACC; the AR update (if any) happens after the access (§5.2.2, PDF pp.140–142 / printed pp.5-10–5-12). Instruction words below are as printed in the manual prose (the bit-diagrams in the extraction are partially garbled box-drawing, but the prose word values are legible and cross-check against Table 5-3: word = `28h` opcode byte + low byte `{I,IDV,INC,DEC,N,NAR}`).

| Ex. | Instruction | Word | Low byte decode (I IDV INC DEC N NAR) | AR effect |
|---|---|---|---|---|
| 5-1 (PDF p.140 / printed p.5-10) | `ADD *, 8` | `2880h` | 1 0 0 0 0 000 | None |
| 5-2 (PDF p.140 / printed p.5-10) | `ADD *-, 8` | `2890h` | 1 0 0 1 0 000 | AR − 1 |
| 5-3 (PDF p.140 / printed p.5-10) | `ADD *+, 8` | `28A0h` | 1 0 1 0 0 000 | AR + 1 |
| 5-4 (PDF p.141 / printed p.5-11) | `ADD *+, 8, AR3` | `28ABh` | 1 0 1 0 1 011 | AR + 1; ARP ← 3 |
| 5-5 (PDF p.141 / printed p.5-11) | `ADD *0-, 8` | `28D0h` | 1 1 0 1 0 000 | AR − INDX |
| 5-6 (PDF p.141 / printed p.5-11) | `ADD *0+, 8` | `28E0h` | 1 1 1 0 0 000 | AR + INDX |
| 5-7 (PDF p.141 / printed p.5-11) | `ADD *BR0-, 8` | `28C0h` | 1 1 0 0 0 000 | AR − rcINDX |
| 5-8 (PDF p.142 / printed p.5-12) | `ADD *BR0+, 8` | `28F0h` | 1 1 1 1 0 000 | AR + rcINDX |

- Cross-check (arithmetic, not a manual quote): `28ABh` low byte `ABh` = `1010 1011` → I=1, IDV=0, INC=1, DEC=0, N=1, NAR=011=3 — matches Table 5-3 row `*+, ARn`. All eight words decode consistently with Table 5-3.

### 3.8 Example 5-9 — indirect-addressing routine (PDF p.142 / printed p.5-12)

Computes Σ(I=1..10) X(I)·Y(I). X values in on-chip RAM block B0, Y values in block B1. Efficiency comes from indirect addressing + the repeat instruction (§5.2.2, Ex. 5-9, PDF p.142 / printed p.5-12):

| Instruction | Comment (manual) |
|---|---|
| `SERIES MAR *, AR4` | ARP points to AR4 |
| `SETC CNF` | Configure block B0 as program memory |
| `LAR AR4, #0300h` | Point at beginning of data memory |
| `RPTZ #9` | Clear ACC and PREG; repeat next instruction 10 times |
| `MAC 0FF00h, *+` | Multiply and accumulate; increment AR4 |
| `APAC` | Accumulate last product |
| `RET` | ACC contains result |

- Note: `MAC 0FF00h, *+` as printed mixes a direct dma operand (`0FF00h` — sic, as printed; 4 hex digits in a 7-bit dma field) with an indirect operand; the manual gives no further explanation of that operand in Ch. 5. Do not "correct" it; see §8.3.

### 3.9 NDX coupling — AR0 / INDX / ARCR (§5.2.1, PDF p.136 / printed p.5-6)

Transcribed exactly as the manual states it:

- "To maintain compatibility with the 'C2x devices, clear the NDX bit in the PMST. In the 'C2x architecture, the current AR can be incremented or decremented by the value in the AR0. When the NDX bit is cleared, every AR0 modification or LAR write also writes the ARCR and INDX with the same value. Subsequent modifications of the current ARs with indexed addressing will use the INDX, therefore maintaining compatibility with existing 'C2x code. The NDX bit is cleared at reset." (§5.2.1, PDF p.136 / printed p.5-6)
- What Ch. 5 says, in table form:

| NDX (PMST bit) | Behaviour stated in Ch. 5 |
|---|---|
| NDX = 0 (cleared; reset state) | Every AR0 modification **or** LAR write also writes ARCR **and** INDX with the same value; later indexed AR modifications use that INDX (§5.2.1, PDF p.136 / printed p.5-6) |
| NDX = 1 (set) | **Not stated in Ch. 5.** The manual gives no sentence describing NDX=1 behaviour in this chapter (no AR0/INDX/ARCR decoupling statement appears on PDF pp.131–152). Do not assume it from the NDX=0 sentence. |

- The manual's recommendation is to **clear** NDX for 'C2x compatibility (§5.2.1, PDF p.136 / printed p.5-6). The NDX bit lives in PMST; its bit position and the ARCR/INDX register definitions are not given in Ch. 5.
- INFERENCE (kept out of the tables above): NDX=1 presumably decouples AR0 from INDX/ARCR (so INDX is loaded independently), which is the usual reading — but Ch. 5 does not say this, so an emulator must source the NDX=1 rule from elsewhere (e.g. the PMST description in Ch. 4) and verify it there.

### 3.10 Bit-reversed addressing (§5.2.3, PDF pp.142–143 / printed pp.5-12–5-13)

| Item | Rule (manual) |
|---|---|
| Purpose | Efficient I/O by resequencing data points in a radix-2 FFT program (§5.2.3, PDF p.142 / printed p.5-12; also §5.2.1, PDF p.136 / printed p.5-6) |
| INDX setup | INDX specifies **one-half the size of the FFT** (§5.2.3, PDF p.142 / printed p.5-12). Normally INDX is first set to one-half the array's size and the current AR to the base address of the data (first data point) (§5.2.1, PDF p.136 / printed p.5-6) |
| AR precondition | "The value contained in the current AR must be equal to 2n–1, where n is an integer, and the FFT size is 2n." (§5.2.3, PDF p.142 / printed p.5-12) — [UNVERIFIED — extraction garbled, manual §5.2.3, PDF p.142] : the superscripts are lost in extraction; the intended reading is almost certainly 2^n − 1 / FFT size 2^n, but the extracted text literally reads "2n–1" / "2n". Do not rely on the exponent without checking the printed page. |
| Mechanism | Direction of carry propagation in the ARAU is **reversed** when bit-reversed addressing is selected and INDX is added to / subtracted from the current AR (§5.2.1, PDF p.136 / printed p.5-6) |
| Modes | `*BR0+` (AR + rcINDX) and `*BR0-` (AR − rcINDX) only — Table 5-3, §3.6 above (Table 5-2, PDF p.139 / printed p.5-9) |
| Increment rule | Add INDX to the current AR with reverse-carry propagation (§5.2.1, PDF p.136 / printed p.5-6) |
| Decrement rule | Subtract INDX from the current AR with reverse-carry propagation (§5.2.1, PDF p.136 / printed p.5-6) |

**Example 5-10 — sequence of AR modifications (PDF p.143 / printed p.5-13).** Setup as printed: ARs treated as eight bits long for illustration; AR2 = base address `0110 0000` (binary), INDX = `0000 1000` (binary). Repeated `*BR0+`:

| Step | Instruction (as printed) | AR2 after |
|---|---|---|
| 0th value | `*BR0+` | `0110 0000` |
| 1st value | `*BR0+` | `0110 1000` |
| 2nd value | `*BR0+` | `0110 0100` |
| 3rd value | `*BR0+` | `0110 1100` |
| 4th value | `*BR0+` | `0110 0010` |
| 5th value | `*BR0+` | `0110 1010` |
| 6th value | `*BR0+` | `0110 0110` |
| 7th value | `*BR0+` | `0110 1110` |

(Example 5-10, §5.2.3, PDF p.143 / printed p.5-13. The 2nd line is printed as "`*BR0+ ,AR2 = 0110 1000 (1st value)`" — the "`,AR2`" is a typesetting artefact of the listing, not a second operand; the sequence is eight successive `*BR0+` updates.)

**Table 5-4 — Bit-reversed addresses (PDF p.143 / printed p.5-13).** Relationship of the bit pattern of the index steps and the four LSBs of AR2, which contain the bit-reversed address (§5.2.3, PDF p.142 / printed p.5-12):

| Step | Bit pattern | Bit-reversed pattern | Bit-reversed step |
|---|---|---|---|
| 0 | 0000 | 0000 | 0 |
| 1 | 0001 | 1000 | 8 |
| 2 | 0010 | 0100 | 4 |
| 3 | 0011 | 1100 | 12 |
| 4 | 0100 | 0010 | 2 |
| 5 | 0101 | 1010 | 10 |
| 6 | 0110 | 0110 | 6 |
| 7 | 0111 | 1110 | 14 |
| 8 | 1000 | 0001 | 1 |
| 9 | 1001 | 1001 | 9 |
| 10 | 1010 | 0101 | 5 |
| 11 | 1011 | 1101 | 13 |
| 12 | 1100 | 0011 | 3 |
| 13 | 1101 | 1011 | 11 |
| 14 | 1110 | 0111 | 7 |
| 15 | 1111 | 1111 | 15 |

(Table 5-4, §5.2.3, PDF p.143 / printed p.5-13.)

### 3.11 Auxiliary-register operations as they relate to addressing

| Instruction | Role in addressing (Ch. 5 statements only) |
|---|---|
| `LAR` | Loads an address/value into an AR (§5.2, PDF p.134 / printed p.5-4; §5.2, PDF p.135 / printed p.5-5 — also loads ARs for temporary storage) |
| `SAR` | Stores an AR value to a data-memory location (ARs as temporary storage) (§5.2, PDF p.135 / printed p.5-5) |
| `ADRK` | Changes the content of the current AR (add immediate — name implies add; Ch. 5 does not give its operand semantics beyond listing it as an AR-changing instruction) (§5.2, PDF p.134 / printed p.5-4) |
| `SBRK` | Changes the content of the current AR (subtract immediate — name implies subtract; Ch. 5 does not give its operand semantics beyond listing it) (§5.2, PDF p.134 / printed p.5-4) |
| `MAR` | Changes the content of the current AR / points ARP at an AR (used in Ex. 5-9 as `MAR *, AR4` to point ARP at AR4; listed as an AR-changing instruction) (§5.2, PDF p.134 / printed p.5-4; Ex. 5-9, PDF p.142 / printed p.5-12) |
| `CMPR` | Compares current AR with ARCR → TC flag (ST1); supports conditional branches/calls/returns (§5.2, PDF p.135 / printed p.5-5) |
| Indirect field of any supporting instruction | Changes the current AR per Tables 5-2/5-3 (§5.2, PDF p.134 / printed p.5-4) |

- Ch. 5 does **not** define the operand formats, immediate widths, or cycle counts of ADRK/SBRK/MAR/LAR/SAR — those are in Ch. 6 (instruction set). `ADRK`/`SBRK` also appear in the short-immediate table (§4, Table 5-5).

## 4. Immediate addressing (§5.3, PDF pp.144–146 / printed pp.5-14–5-16)

- In immediate addressing the instruction word(s) contain the value of the immediate operand. Two forms: 1-word short immediate (8-bit, 9-bit, 13-bit constants) and 2-word long immediate (16-bit constant) (§5.3, PDF p.144 / printed p.5-14).

### 4.1 Instructions supporting immediate addressing (Table 5-5, PDF p.144 / printed p.5-14)

| Short immediate (1-word) | | | Long immediate (2-word), 16-bit constant |
|---|---|---|---|
| 8-bit constant | 9-bit constant | 13-bit constant | |
| `ADD` | `LDP` | `MPY` | `ADD`, `AND`, `APL`, `CPL`, `LACC`, `LAR`, `MPY`, `OPL`, `OR`, `RPT`, `RPTZ`, `SPLK`, `SUB`, `XOR`, `XPL` |
| `ADRK` | | | |
| `LACL` | | | |
| `LAR` | | | |
| `RPT` | | | |
| `SBRK` | | | |
| `SUB` | | | |

(Table 5-5, §5.3, PDF p.144 / printed p.5-14; column assignment read from the table's row alignment — `ADD/ADRK/LACL/LAR/RPT/SBRK/SUB` under 8-bit, `LDP` under 9-bit, `MPY` under 13-bit, the 15 instructions above under 16-bit. Note `ADD`, `LAR`, `MPY`, `RPT`, `SUB` appear in both short and long columns.)

### 4.2 Short immediate (§5.3.1, PDF p.144 / printed p.5-14; Fig. 5-5)

- Operand is contained within the instruction machine code. Example (Fig. 5-5, PDF p.144 / printed p.5-14): `ADD #0FFh`, machine code `1011 1000 1111 1111` (lower 8 bits = operand `0FFh`, added to ACC by the CALU).

### 4.3 Long immediate (§5.3.2, PDF pp.145–146 / printed pp.5-15–5-16)

- Operand is in the **second word** of a two-word instruction. Two sub-modes (§5.3.2, PDF p.145 / printed p.5-15):
  - one-operand instructions / single-or-no data-memory access (§5.3.2.1);
  - two-operand instructions / dual data-memory access (§5.3.2.2).

| Sub-mode | Behaviour |
|---|---|
| Single/no data-memory access (§5.3.2.1, Fig. 5-6, PDF p.145 / printed p.5-15) | Second word is the operand. Example: `ADD #01234h`, machine code word 1 `1011 1111 1001 0000`, word 2 = `01234h`, added to ACC by the CALU. |
| Dual data-memory access (§5.3.2.2, Fig. 5-7, PDF p.145 / printed p.5-16) | PFC is pushed onto the microcall stack (MCS) and the long immediate value is loaded into the PFC; the program address/data bus is then used for the operand fetch or write. On completion the MCS is popped back to the PFC, the PC is incremented by two, and execution continues. The PFC is used so that when the instruction is repeated, the address generated can be autoincremented. |

- Fig. 5-7 worked example (PDF p.146 / printed p.5-16): `BLDD #02345h, 012h`. Machine code 1: bits 15–8 opcode, bit 7 = 0 (direct), bits 6–0 dma = `012h`; DP = `019Dh` (same `LDP #019Dh` setup as Fig. 5-2), DAB = `(019Dh << 7) | 012h` = `0CE92h`. Machine code 2 = `02345h`; PC = `02345h` (the long-immediate value loaded into PFC). Operand1 = Data(PC) [source, fetched via PAB], Operand2 = Data(DAB) [destination, direct mode].

## 5. Dedicated-register addressing (§5.4, PDF pp.147–148 / printed pp.5-17–5-18)

- Operates like long immediate addressing, **except the address comes from one of two special-purpose memory-mapped registers in the CPU: BMAR (block-move address register) and DBMR (dynamic bit-manipulation register)**. Advantage: the address of the block to be acted on can be changed during program execution (§5.4, PDF p.147 / printed p.5-17).
- Two syntaxes (§5.4, PDF p.147 / printed p.5-17):
  - Specify BMAR by its predefined symbol: `BLDD BMAR, DAT100` with DP = 0 and BMAR = `200h` copies data-memory location `200h` to data-memory location 100 on the current data page.
  - Omit the immediate value from a PLU instruction: `OPL DAT10` with DP = 6 and DBMR = `FFF0h`, address `030Ah` holding `01h` → content of `030Ah` ORed with DBMR, result `FFF1h` stored back in `030Ah`.

### 5.1 BMAR use (§5.4.1, PDF pp.147–148 / printed pp.5-17–5-18; Fig. 5-8)

| Instruction | BMAR role |
|---|---|
| `BLDD`, `BLDP`, `BLPD` | Use BMAR to point at the source or destination space of a block move (§5.4.1, PDF p.147 / printed p.5-17) |
| `MADD`, `MADS` | Use BMAR to address an operand in **program memory** for a multiply-accumulate operation (§5.4.1, PDF p.147 / printed p.5-17) |

- Fig. 5-8 (PDF p.148 / printed p.5-18): `BLDD BMAR, 012h`. Machine code: bits 15–8 opcode, bit 7 = 0 (direct), bits 6–0 dma = `012h`; DP = `019Dh`, DAB = `0CE92h`; BMAR → PFC; Operand1 = Data(PFC) [source via BMAR], Operand2 = Data(DAB) [destination, direct mode].
- This is the **only program-memory addressing mechanism described in Ch. 5**: the BMAR value is loaded into the PFC and the source operand is fetched from program memory via the program address bus (Fig. 5-8, PDF p.148 / printed p.5-18; §5.3.2.2 mechanism, PDF p.145 / printed p.5-15). Ch. 5 uses no "pma" symbol and gives no other program-memory addressing mode.

### 5.2 DBMR use (§5.4.2, PDF p.148 / printed p.5-18; Fig. 5-9)

| Instruction | DBMR role |
|---|---|
| `APL`, `CPL`, `OPL`, `XPL` | Use the PLU and the contents of the DBMR **when an immediate value is not specified** as one of the operands (§5.4.2, PDF p.148 / printed p.5-18) |

- Fig. 5-9 (PDF p.148 / printed p.5-18): `APL 010h` — machine code bits 15–8 opcode, bit 7 = 0 (direct), bits 6–0 dma = `010h`; DP = `019Dh`, DAB = `0CE90h`; Operand1 = Data(DAB), Operand2 = DBMR (DBMR used as the AND mask in `APL`).
- **BLDD / BLDP / TBLR / TBLW in Ch. 5:** `BLDD` appears in §5.3.2.2 (Fig. 5-7, long-immediate dual access), §5.4 (BMAR syntax example), §5.4.1 (BMAR user) and §5.2 (memory-mapped AR-write list). `BLDP` and `BLPD` appear **only** in the §5.4.1 sentence above (BMAR users). **`TBLR` and `TBLW` do not appear anywhere in Ch. 5** (PDF pp.131–152) — their addressing is not described in this chapter; do not source it from here.

## 6. Memory-mapped register addressing (§5.5, PDF pp.149–150 / printed pp.5-19–5-20)

- Lets you modify the memory-mapped registers **without affecting the current DP value**; also reaches any scratch-pad RAM (DARAM B2) location or data page 0 (§5.5, PDF p.149 / printed p.5-19).
- Mechanism (Fig. 5-10, PDF p.149 / printed p.5-19): operates like direct addressing, **except the 9 MSBs of the address are forced to 0** instead of being loaded with DP. Address = `{000000000, dma[6:0]}` — i.e. the 7 LSBs from IREG (direct) or from the current AR (indirect) form a page-0 address, regardless of the current DP (direct) or current AR value (indirect).
- Instructions operating in this mode — using them does **not** affect DP (§5.5, PDF p.149 / printed p.5-19):

| Instruction | Meaning (manual expansion) |
|---|---|
| `LAMM` | Load accumulator with memory-mapped register |
| `LMMR` | Load memory-mapped register |
| `SAMM` | Store accumulator in memory-mapped register |
| `SMMR` | Store memory-mapped register |

- Example 5-11 — indirect form (PDF p.150 / printed p.5-20): `SAMM *+` — "STORE ACC TO PMST REGISTER". Assume ARP = 3 and AR3 = `FF07h`: ACC is stored to PMST (address `07h`), pointed at by the **7 LSBs of AR3**.
- Example 5-12 — direct form (PDF p.150 / printed p.5-20): `LAMM 07h` — "ACC = PMST". Assume DP = `0184h` and TEMP1 = `8060h` (sic — TEMP1 plays no role in the example as printed; see §8.3): content of memory location `07h` (PMST) is loaded into ACC. Fig. 5-11 (PDF p.150 / printed p.5-20): machine code `0000 1000 0000 0111` (bits 15–8 = `08h`, bit 7 = 0, dma = `07h`); DAB = `0007h` despite DP = `0184h`.
- PMST is at page-0 address `07h` (Examples 5-11/5-12, PDF p.150 / printed p.5-20). The full memory-mapped register map is not in Ch. 5.

## 7. Circular addressing (§5.6, PDF pp.151–152 / printed pp.5-21–5-22)

- Use: convolution, correlation, FIR filters — circular buffers implement a sliding window holding the most recent data (§5.6, PDF p.151 / printed p.5-21).
- **Two concurrent circular buffers** operating via the ARs (§5.6, PDF p.151 / printed p.5-21).
- Five memory-mapped registers control circular-buffer operation (§5.6, PDF p.151 / printed p.5-21):

| Register | Meaning |
|---|---|
| CBSR1 | Circular buffer 1 start register |
| CBSR2 | Circular buffer 2 start register |
| CBER1 | Circular buffer 1 end register |
| CBER2 | Circular buffer 2 end register |
| CBCR | Circular buffer control register (8-bit; enables/disables circular-buffer operation) |

- CBCR bit layout is **not in Ch. 5**: "The 8-bit CBCR enables and disables the circular buffer operation and is defined in subsection 4.4.1, Circular Buffer Control Register (CBCR), on page 4-6" (§5.6, PDF p.151 / printed p.5-21). Do not decode CBCR values from Ch. 5 alone — in particular the AR↔buffer assignment is not stated here (see §7.3).
- Setup sequence (§5.6, PDF p.151 / printed p.5-21): (1) load start and end addresses into the corresponding buffer registers; (2) load a value between the start and end registers into an AR; (3) set the corresponding circular-buffer enable bit in CBCR. **You must not enable the same AR for both circular buffers; if you do, unexpected results occur.**

### 7.1 Wrap rule — the algorithm (§5.6, PDF p.151 / printed p.5-21)

Verbatim algorithm (manual's pseudocode):

```
If (ARn = CBER) and (any AR modification),
Then:   ARn = CBSR.
Else:   ARn = ARn + step.
```

| Case | Result |
|---|---|
| ARn = CBER **and** an AR modification occurs | ARn ← CBSR (wrap), regardless of step size or direction (§5.6, PDF p.151 / printed p.5-21) |
| ARn = CBER and **no** AR modification occurs | Current AR is not modified; still equal to CBER (§5.6, PDF p.151 / printed p.5-21) |
| ARn ≠ CBER | ARn ← ARn + step (normal §5.2 update) (§5.6, PDF p.151 / printed p.5-21) |

- The test of the AR value is performed **before** any modifications (§5.6, PDF p.151 / printed p.5-21).
- "When the current AR = CBER, any AR modification (increment or decrement) will set the current AR = CBSR" (§5.6, PDF p.151 / printed p.5-21) — i.e. the wrap triggers on **equality with CBER only**, not on crossing the boundary.
- **Start/end inclusive/exclusive:** both CBSR and CBER are inclusive endpoints of the buffer: the AR is loaded with a value "between the start and end registers" (§5.6, PDF p.151 / printed p.5-21), the buffer in Ex. 5-13 spans `200h`–`203h` inclusive (4 words), and an AR equal to CBER is a valid current address (it is read before any wrap; Ex. 5-13 cases 2/4/6/8). CBSR is the wrap target, CBER is the wrap trigger.
- **Step > 1 hazard:** "the step is the quantity that is being added to or subtracted from the specified AR. Take care when using a step of greater than 1 to modify the AR pointing to an element of the circular buffer. If an update to an AR generates an address outside the range of the circular buffer, the ARAU does not detect this situation, and the buffer does not wrap around." (§5.6, PDF p.152 / printed p.5-22). AR updates are otherwise performed as described in §5.2.
- **Pipeline latency:** two-cycle latency between configuring the CBCR and performing AR modifications (§5.6, PDF p.152 / printed p.5-22).
- **Direction rule:** "For incrementing the value in the AR, the value in CBER must be greater than the value in CBSR. For decrementing the value in the AR, the value in CBSR must be greater than the value in CBER." (§5.6, PDF p.152 / printed p.5-22). Consequence per the algorithm: in an increment-configured buffer (CBSR < CBER), a *decrement* from CBSR walks below the buffer with no wrap (Ex. 5-13 case 5); only hitting CBER wraps.

### 7.2 Example 5-13 — worked cases (§5.6, PDF p.152 / printed p.5-22)

Setup: `CBSR1 = 200h`, `CBER1 = 203h`, `CBCR = 0Eh` ("Enable AR6 pointing to buffer 1"), AR6 is the buffer pointer (via `MAR *, AR6` first). Buffer = `200h, 201h, 202h, 203h` (4 words, inclusive).

| Case | Setup (`LAR AR6, #…`) | Instruction | AR6 after | Why (per §7.1 algorithm) |
|---|---|---|---|---|
| 1 | `200h` | `LACC *` | `200h` | No modification; AR ≠ CBER anyway |
| 2 | `203h` | `LACC *` | `203h` | No modification; AR = CBER but no modification → unchanged |
| 3 | `200h` | `LACC *+` | `201h` | AR ≠ CBER → AR + 1 |
| 4 | `203h` | `LACC *+` | `200h` | AR = CBER + modification → CBSR (wrap) |
| 5 | `200h` | `LACC *-` | `1FFh` | AR ≠ CBER → AR − 1; **below** buffer, no wrap (decrement in an increment-configured buffer) |
| 6 | `203h` | `LACC *-` | `200h` | AR = CBER + modification → CBSR (wrap, even though decrementing) |
| 7 | `202h` | `ADRK 2` | `204h` | AR ≠ CBER → AR + 2; overshoots past CBER, **no wrap** (step > 1 hazard) |
| 8 | `203h` | `ADRK 2` | `200h` | AR = CBER + modification → CBSR (wrap, step ignored) |

(Example 5-13, §5.6, PDF p.152 / printed p.5-22. The manual's listing as printed: `mar *,ar6` / `lpd #,0` / `splk #200h,CBSR1` / `splk #203h,CBER1` / `splk #0Eh,CBCR` / then the `LAR`/`LACC`/`ADRK` cases. The `lpd #,0` line is as printed — its operands are not explained in Ch. 5; see §8.3.)

### 7.3 What Ch. 5 does NOT say about circular buffers

| Question | Status in Ch. 5 |
|---|---|
| Which ARs can serve buffer 1 vs buffer 2? | **Not stated.** Only Ex. 5-13 shows AR6 enabled for buffer 1 via `CBCR = 0Eh`; no general AR↔buffer mapping table is in Ch. 5. The CBCR bit definitions live in §4.4.1 (PDF p.151 / printed p.5-21 cross-ref). |
| CBCR bit fields (enable bits, AR select bits) | **Not in Ch. 5** — deferred to §4.4.1, p.4-6 (§5.6, PDF p.151 / printed p.5-21). `CBCR = 0Eh` in Ex. 5-13 must not be decoded from Ch. 5. |
| CBSR/CBER register addresses | Not in Ch. 5. |
| Whether `ADRK`/`SBRK`/`MAR` updates also wrap | The wrap rule is stated for "any AR modification" (§5.6, PDF p.151 / printed p.5-21) and Ex. 5-13 cases 7–8 demonstrate it for `ADRK`; the manual does not enumerate the instruction list. |

## 8. Addressing restrictions (consolidated)

| Restriction | Source |
|---|---|
| Indirect addressing: usable with all instructions **except** those with immediate operands or with no operands | §5.2.2, PDF p.137 / printed p.5-7 |
| IDV=0, INC=1, DEC=1: **Reserved** — no indirect mode uses it | Table 5-2, PDF p.139 / printed p.5-9 |
| DP must be initialized in software; undefined after reset/power-up | §5.1 Note, PDF p.133 / printed p.5-3 |
| Same AR must not be enabled for both circular buffers — "unexpected results" | §5.6, PDF p.151 / printed p.5-21 |
| Circular buffer: step > 1 can overshoot CBER without wrapping; ARAU does not detect it | §5.6, PDF p.152 / printed p.5-22 |
| Circular buffer direction: increment requires CBER > CBSR; decrement requires CBSR > CBER | §5.6, PDF p.152 / printed p.5-22 |
| CBCR configuration → AR modifications: two-cycle latency | §5.6, PDF p.152 / printed p.5-22 |
| Memory-mapped AR writes (APL/OPL/SAMM/XPL/BLDD/SACH/SMMR/LMMR/SACL/SPLK): pipeline conflict if one of the next two instruction words modifies that AR | §5.2, PDF p.135 / printed p.5-5 |
| NDX: clear it in PMST for 'C2x compatibility (NDX cleared at reset) | §5.2.1, PDF p.136 / printed p.5-6 |
| DBMR is used by APL/CPL/OPL/XPL **only when no immediate value is specified** | §5.4.2, PDF p.148 / printed p.5-18 |
| Bit-reversed addressing requires INDX = half the FFT/array size and AR = base address (first data point) before use | §5.2.1, PDF p.136 / printed p.5-6; §5.2.3, PDF p.142 / printed p.5-12 |

## 9. Topics the task asked for that are NOT in Chapter 5 — do not source from here

| Requested topic | Verdict for Ch. 5 (PDF pp.131–152) |
|---|---|
| Stack addressing | **Absent.** No stack-addressing section, no stack-pointer addressing discussion in Ch. 5. (The microcall stack MCS is mentioned only as the PFC save/restore mechanism for long-immediate dual access, §5.3.2.2, PDF p.145 / printed p.5-15.) |
| I/O addressing / I/O ports | **Absent as an addressing mode.** The word "I/O" occurs once, only in the phrase "efficient I/O by the resequencing of data points" for bit-reversed addressing (§5.2.1, PDF p.136 / printed p.5-6). No port-addressing mode is defined. |
| Program-memory addressing (pma) | **No standalone treatment; no "pma" symbol.** The only program-memory fetch in Ch. 5 is via BMAR→PFC (BLDD/BLDP/BLPD source or destination; MADD/MADS operand), §5.4.1 / Fig. 5-8, PDF pp.147–148 / printed pp.5-17–5-18. |
| `TBLR` / `TBLW` addressing | **Absent.** Neither mnemonic occurs in Ch. 5. `BLDP`/`BLPD` occur only in the §5.4.1 BMAR sentence. |
| Data-memory addressing beyond dma/DP/AR | Covered: dma = 7-bit direct field (§5.1), DP page pointer (§5.1), AR 16-bit indirect (§5.2), page-0 forcing (§5.5). No other dma mechanism in Ch. 5. |
| CBCR bit layout; AR↔buffer mapping; NDX=1 behaviour; ARCR/INDX register addresses; ADRK/SBRK/MAR/LAR/SAR operand formats | **Not in Ch. 5** — deferred to Ch. 4 (CBCR §4.4.1, PMST) and Ch. 6 (instruction formats) respectively. See §§3.9, 3.11, 7.3. |

## 10. Contradictions, ambiguities, and unverified items

### 10.1 Contradictions found

**None that change semantics.** The two candidate contradictions were checked and resolve as consistent:

1. **Table 5-2 vs Table 5-3 (reverse-carry rows).** Table 5-2 (PDF p.139 / printed p.5-9) assigns reverse-carry subtract to IDV=1/INC=0/DEC=0 and reverse-carry add to IDV=1/INC=1/DEC=1; Table 5-3 (PDF pp.139–140 / printed pp.5-9–5-10) assigns exactly those bit patterns to `*BR0-` and `*BR0+`. **Consistent — no contradiction; Table 5-3 is normative for the notation mapping, Table 5-2 for the arithmetic.**
2. **§5.6 wrap rule vs Ex. 5-13 cases 5–7.** The prose ("any AR modification when AR=CBER → CBSR") plus the step->1 hazard reads at first as if decrement/overshoot should also wrap; the examples show decrement from CBSR going to `1FFh` (case 5) and `ADRK 2` from `202h` going to `204h` (case 7) with no wrap. **Consistent:** the wrap test is equality-with-CBER *before* the update, and only that equality triggers it (§5.6, PDF pp.151–152 / printed pp.5-21–5-22). The examples are normative for the edge cases.

### 10.2 Ambiguities / counting notes (not contradictions)

1. **"Four indirect addressing options" vs seven symbols** (§5.2.1, PDF pp.135–136 / printed pp.5-5–5-6): the four are categories (none / ±1 / ±INDX / ±INDX reverse-carry); the ± categories each split into increment/decrement, giving seven notations in Table 5-3. Treat Table 5-3 as the normative enumeration.
2. **Figure captions vs machine-code bits** (§5.1 Fig. 5-2; §5.3.2.2 Fig. 5-7; §5.4 Figs. 5-8/5-9; §5.5 Fig. 5-11): captions read e.g. "ADD opcode 010h" / "BLDD opcode 012h" / "LAMM opcode 07h", but the hex value is the **dma field** (bits 6–0), not the opcode byte — e.g. Fig. 5-11 machine code `0000 1000 0000 0111` has opcode byte `08h` and dma `07h` (PDF p.150 / printed p.5-20). The bit diagrams are normative; the caption hex is the dma.
3. **Ex. 5-12 stray operand** (§5.5, PDF p.150 / printed p.5-20): "assume that DP = 0184h and TEMP1 = 8060h" — TEMP1 plays no role in `LAMM 07h`; the manual does not explain it. Left as printed; it does not affect the address (`07h` via 9-MSB forcing).
4. **Ex. 5-9 `MAC 0FF00h, *+`** (§5.2.2, PDF p.142 / printed p.5-12): the first operand is printed as a 4-digit hex value in a position where a 7-bit dma would be expected; Ch. 5 gives no explanation. Left as printed, not corrected.
5. **Ex. 5-13 `lpd #,0`** (§5.6, PDF p.152 / printed p.5-22): printed with an empty first operand; Ch. 5 does not explain it. Left as printed.

### 10.3 Unverified items (extraction garbled/illegible — not guessed)

| # | Item | Ref |
|---|---|---|
| U1 | Figure 5-4 (indirect addressing opcode format diagram) — body renders as `Á` box-drawing characters in the layout extraction; bit layout recovered from Tables 5-1/5-3 instead | [UNVERIFIED — extraction garbled, manual §5.2.2, PDF p.137] |
| U2 | §5.2.3 AR precondition exponents: extracted as "2n–1" / FFT size "2n"; intended 2^n − 1 / 2^n is near-certain but the superscript is lost in extraction | [UNVERIFIED — extraction garbled, manual §5.2.3, PDF p.142] |
| U3 | Bit-diagrams inside Examples 5-1–5-8 (PDF pp.140–142 / printed pp.5-10–5-12) are partially garbled box-drawing in extraction; the prose instruction words (`2880h`…`28F0h`) are legible and were cross-checked arithmetically against Table 5-3 (§3.7) | [UNVERIFIED — extraction garbled (diagrams only), manual §5.2.2, PDF pp.140–142] |
| U4 | Figure 5-1 / 5-3 / 5-10 diagram geometry (page-map and ARAU block diagrams) is layout text, not vector data, in the extraction; the prose statements they illustrate are legible and are what is cited above | [UNVERIFIED — extraction garbled (diagram geometry only), manual §5.1/§5.2/§5.5, PDF pp.132/134/149] |

## 11. Source map (every section → pages)

| Manual § | Title | PDF pp. | Printed pp. |
|---|---|---|---|
| Ch. 5 intro + contents | Addressing Modes | 131 | 5-1 |
| 5.1 | Direct Addressing | 132–133 | 5-2–5-3 |
| 5.2 | Indirect Addressing | 134–135 | 5-4–5-5 |
| 5.2.1 | Indirect Addressing Options | 135–137 | 5-5–5-7 |
| 5.2.2 | Indirect Addressing Opcode Format (+ Tables 5-1/5-2/5-3, Ex. 5-1–5-9) | 137–142 | 5-7–5-12 |
| 5.2.3 | Bit-Reversed Addressing (+ Ex. 5-10, Table 5-4) | 142–143 | 5-12–5-13 |
| 5.3 (+ 5.3.1, 5.3.2, 5.3.2.1, 5.3.2.2) | Immediate Addressing (+ Table 5-5, Figs. 5-5/5-6/5-7) | 144–146 | 5-14–5-16 |
| 5.4 (+ 5.4.1, 5.4.2) | Dedicated-Register Addressing (+ Figs. 5-8/5-9) | 147–148 | 5-17–5-18 |
| 5.5 | Memory-Mapped Register Addressing (+ Figs. 5-10/5-11, Ex. 5-11/5-12) | 149–150 | 5-19–5-20 |
| 5.6 | Circular Addressing (+ Ex. 5-13) | 151–152 | 5-21–5-22 |

- Tables: 5-1 (PDF pp.137–138 / printed pp.5-7–5-8), 5-2 (PDF p.139 / printed p.5-9), 5-3 (PDF pp.139–140 / printed pp.5-9–5-10), 5-4 (PDF p.143 / printed p.5-13), 5-5 (PDF p.144 / printed p.5-14).
- Figures: 5-1 (PDF p.132 / printed p.5-2), 5-2 (PDF p.133 / printed p.5-3), 5-3 (PDF p.134 / printed p.5-4), 5-4 (PDF p.137 / printed p.5-7), 5-5 (PDF p.144 / printed p.5-14), 5-6 (PDF p.145 / printed p.5-15), 5-7 (PDF p.146 / printed p.5-16), 5-8 (PDF p.148 / printed p.5-18), 5-9 (PDF p.148 / printed p.5-18), 5-10 (PDF p.149 / printed p.5-19), 5-11 (PDF p.150 / printed p.5-20).
- Examples: 5-1–5-3 (PDF p.140 / printed p.5-10), 5-4–5-7 (PDF p.141 / printed p.5-11), 5-8–5-9 (PDF p.142 / printed p.5-12), 5-10 (PDF p.143 / printed p.5-13), 5-11–5-12 (PDF p.150 / printed p.5-20), 5-13 (PDF p.152 / printed p.5-22).
