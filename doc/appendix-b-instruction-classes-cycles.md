# Appendix B — Instruction Classes and Cycles (SPRU056D)

Source: SPRU056D, *TMS320C5x User's Guide*, June 1998, Appendix B, PDF pp.638–649
(printed pp.B-1–B-12). Only authority: `~/workspace/user/files/spru056d.pdf`.
Every factual claim below cites appendix/section + table number + both page
numbers (PDF index page and printed page).

## B.0 What this appendix is

Instructions are classified into categories ("classes") according to cycles
required. A single instruction can have multiple syntaxes and types of
execution, so it can appear in multiple classes. The tables show the number of
cycles required for a given ’C5x instruction to execute **in a given memory
configuration when executed as a single instruction**. [App B intro,
PDF p.638 (printed p.B-1)]

Symbol/abbreviation definitions for the syntax expressions are in Table 6–2
on printed p.6-4 (Chapter 6, not reproduced here). [App B, §§B.1–B.2,
PDF pp.639, 642 (printed pp.B-2, B-5)]

## B.1 Cycle Class-to-Instruction Set Summary — Table B–1

Table B–1 provides a cycle class-to-instruction set cross reference.
[App B, §B.1, PDF pp.639–641 (printed pp.B-2–B-4)]

Notes printed with Table B–1 (all three pages): † bold typeface indicates
instructions that are new for the ’C5x instruction set. ‡ "ADD #k, ADRK #k,
LACL #k, MPY #k, RPT, SBRK #k, SPM, SUB #k, and XC are not repeatable
instructions." (Bold typeface is lost in the text extraction, so new-for-’C5x
marking is NOT reproduced here — see unverified notes.)

| Class | Description | Instructions |
|---|---|---|

| I | 1 word, 1 cycle, no memory operands | ABS, ADCB, ADD #k, ADDB, ADRK #k, ANDB, APAC, BSAR, CLRC, CMPL, CMPR, CRGT, CRLT, EXAR, IDLE, IDLE2, LACB, LACL #k, MAR, MPY #k, NEG, NOP, NORM, ORB, PAC, POP, PUSH, ROL, ROLB, ROR, RORB, SACB, SATH, SATL, SBB, SBBB, SBRK #k, SETC, SFL, SFLB, SFR, SFRB, SPAC, SPM, SUB #k, XC, XORB, ZAP, ZPR |
| IIA | 1 word, 1 cycle, memory read operand | ADD, ADDC, ADDS, ADDT, AND, BIT, BITT, CPL, LACC, LACL, LACT, LPH, LT, LTA, LTP, LTS, MPY, MPYA, MPYS, MPYU, OR, PSHD, RPT, SQRA, SQRS, SUB, SUBB, SUBC, SUBS, SUBT, XOR, ZALR |
| IIB | 1 word, 1 cycle, memory-mapped register read | LAMM |
| III | 2 words, 2 cycles, long-immediate operand, no memory access, not repeatable | ADD #lk, AND #lk, LACC #lk, LAR ARn, #lk, MPY #lk, OR #lk, RPT #lk, RPTB, RPTZ #lk, SUB #lk, XOR #lk |
| IVA | 1 word, 1 cycle, memory write operand | POPD, SACH, SACL, SAR, SPH, SPL, SST |
| IVB | 1 word, 1 cycle, memory-mapped register write | SAMM |
| V | 1 word, 1 cycle, memory read and write | APL, DMOV, LTD, OPL, XPL |
| VI | 2 words, 2 cycles, memory read and write | APL, OPL, XPL |
| VIIa | 2 words, 2 cycles, memory read operand | CPL #lk |
| VIIb | 2 words, 2 cycles, memory write operand, not repeatable | SPLK |
| VIII | 2 words, 4 cycles, program counter discontinuity, no delayed slots, not repeatable | B, BANZ, BCND, CALL, CC |
| IX | 2 words, 2 cycles, program counter discontinuity, 2 delayed slots, not repeatable | BANZD, BCNDD, BD, CALLD, CCD |
| X | 1 word, 4 cycles, program counter discontinuity, no delayed slots, not repeatable | BACC, CALA, INTR, NMI, RET, RETC, RETE, RETI, TRAP |
| XI | 1 word, 2 cycles, program counter discontinuity, 2 delayed slots, not repeatable | BACCD, CALAD, RETCD, RETD |
| XII | 2 words, 3 cycles, block data transfer, data to data space | BLDD |
| XIII | 1 word, 2 cycles, block data transfer, data to data space | BLDD |
| XIV | 2 words, 3 cycles, block data transfer, program to data space | BLPD |
| XV | 1 word, 2 cycles, block data transfer, program to data space | BLPD |
| XVI | 1 word, 2 cycles, block data transfer, data to program space | BLDP |
| XVII | 1 word, 3 cycles, table read | TBLR |
| XVIII | 1 word, 3 cycles, table write | TBLW |
| XIX | 2 words, 3 cycles, multiply accumulate | MAC |
| XX | 1 word, 2 cycles, multiply accumulate | MADS |
| XXI | 2 words, 3 cycles, multiply accumulate with data move | MACD |
| XXII | 1 word, 2 cycles, multiply accumulate with data move | MADD |
| XXIII | 2 words, 2 cycles, memory-mapped register load | LMMR |
| XXIV | 2 words, 2 cycles, memory-mapped register store | SMMR |
| XXV | 2 words, 3 cycles, output port | OUT |
| XXVI | 2 words, 2 cycles, input port | IN |
| XXVII | 1 word, 2 cycles, pipeline-protected, memory read | LAR, LDP, LST |
| XXVIII | 1 word, 2 cycles, pipeline-protected, memory read, not repeatable | LAR ARn, #k; LDP #k |
| XXIIX / XXIX — see discrepancy note | 1 word, 2 cycles, no memory access, not repeatable, pipeline protected | RPT #k |

### Discrepancies inside Appendix B (as printed — not extraction errors)

- **Class XXIIX vs XXIX.** Table B–1 (PDF p.641, printed p.B-4) labels the
  RPT #k class "Class XXIIX"; Table B–2 (PDF p.648, printed p.B-11) labels
  the same RPT #k entry "Class XXIX". Both are "1 word, 2 cycles, no memory
  operands, not repeatable, pipeline protected". Treated here as one class
  with two printed labels.
- **IDLE / IDLE2 repeatability.** Table B–1 Class I lists IDLE and IDLE2
  without a "not repeatable" qualifier, and the Table B–1 footnote ‡ list of
  non-repeatable Class I instructions does not include them; Table B–2
  (PDF p.644, printed p.B-7) lists both IDLE and IDLE2 as Class I
  "not repeatable". Both statements are reproduced as printed.
- **"1 word, 2 cycle" (singular).** Table B–2 prints the RPT #k description
  as "1 word, 2 cycle, no memory operands, not repeatable" — singular
  "cycle" is as printed. [PDF p.648 (printed p.B-11)]
- **AND #lk missing comma.** Table B–2 prints the AND #lk description as
  "2 words, 2 cycles long-immediate operand, no memory access, not
  repeatable" (no comma after "cycles"); the other Class III rows have the
  comma. As printed. [PDF p.642 (printed p.B-5)]

## B.2 Instruction Set-to-Cycle Class Summary — Table B–2

Table B–2 provides an instruction set-to-cycle class cross reference
(155 rows, alphabetical by mnemonic). [App B, §B.2, PDF pp.642–649
(printed pp.B-5–B-12)] The "Ch. 6 page" column is the page in Chapter 6
where that instruction is described, as printed in Table B–2 itself.
Cycle counts here are the single-instruction counts from Appendix B; they
do NOT include wait states or repeat counts.

| Mnemonic | Cycle class | Cycle class description | Ch. 6 page |
|---|---|---|---|

| ABS | Class I | 1 word, 1 cycle, no memory operands | 6-28 |
| ADCB | Class I | 1 word, 1 cycle, no memory operands | 6-30 |
| ADD | Class IIA | 1 word, 1 cycle, memory read operand | 6-31 |
| ADD #k | Class I | 1 word, 1 cycle, no memory operands, not repeatable | 6-31 |
| ADD #lk | Class III | 2 words, 2 cycles, long-immediate operand, no memory access, not repeatable | 6-31 |
| ADDB | Class I | 1 word, 1 cycle, no memory operands | 6-35 |
| ADDC | Class IIA | 1 word, 1 cycle, memory read operand | 6-36 |
| ADDS | Class IIA | 1 word, 1 cycle, memory read operand | 6-38 |
| ADDT | Class IIA | 1 word, 1 cycle, memory read operand | 6-40 |
| ADRK #k | Class I | 1 word, 1 cycle, no memory operands, not repeatable | 6-42 |
| AND | Class IIA | 1 word, 1 cycle, memory read operand | 6-43 |
| AND #lk | Class III | 2 words, 2 cycles long-immediate operand, no memory access, not repeatable | 6-43 |
| ANDB | Class I | 1 word, 1 cycle, no memory operands | 6-46 |
| APAC | Class I | 1 word, 1 cycle, no memory operands | 6-47 |
| APL | Class V | 1 word, 1 cycle, memory read and write | 6-48 |
| APL | Class VI | 2 words, 2 cycles, memory read and write | 6-48 |
| B | Class VIII | 2 words, 4 cycles program counter discontinuity, no delayed slots, not repeatable | 6-51 |
| BACC | Class X | 1 word, 4 cycles, program counter discontinuity, no delayed slots, not repeatable | 6-52 |
| BACCD | Class XI | 1 word, 2 cycles, program counter discontinuity, 2 delayed slots, not repeatable | 6-53 |
| BANZ | Class VIII | 2 words, 4 cycles, program counter discontinuity, no delayed slots, not repeatable | 6-54 |
| BANZD | Class IX | 2 words, 2 cycles, program counter discontinuity, 2 delayed slots, not repeatable | 6-56 |
| BCND | Class VIII | 2 words, 4 cycles, program counter discontinuity, no delayed slots, not repeatable | 6-58 |
| BCNDD | Class IX | 2 words, 2 cycles, program counter discontinuity, 2 delayed slots, not repeatable | 6-60 |
| BD | Class IX | 2 words, 2 cycles, program counter discontinuity, 2 delayed slots, not repeatable | 6-62 |
| BIT | Class IIA | 1 word, 1 cycle, memory read operand | 6-63 |
| BITT | Class IIA | 1 word, 1 cycle, memory read operand | 6-65 |
| BLDD | Class XIII | 1 word, 2 cycles, block data transfer, data to data space | 6-67 |
| BLDD | Class XII | 2 words, 3 cycles, block data transfer, data to data space | 6-67 |
| BLDP | Class XVI | 1 word, 2 cycles, block data transfer, data to program space | 6-73 |
| BLPD | Class XV | 1 word, 2 cycles, block data transfer, program to data space | 6-76 |
| BLPD | Class XIV | 2 words, 3 cycles, block data transfer, program to data space | 6-76 |
| BSAR | Class I | 1 word, 1 cycle, no memory operands | 6-82 |
| CALA | Class X | 1 word, 4 cycles, program counter discontinuity, no delayed slots, not repeatable | 6-83 |
| CALAD | Class XI | 1 word, 2 cycles, program counter discontinuity, 2 delayed slots, not repeatable | 6-84 |
| CALL | Class VIII | 2 words, 4 cycles, program counter discontinuity, no delayed slots, not repeatable | 6-85 |
| CALLD | Class IX | 2 words, 2 cycles, program counter discontinuity, 2 delayed slots, not repeatable | 6-86 |
| CC | Class VIII | 2 words, 4 cycles, program counter discontinuity, no delayed slots, not repeatable | 6-88 |
| CCD | Class IX | 2 words, 2 cycles, program counter discontinuity, 2 delayed slots, not repeatable | 6-90 |
| CLRC | Class I | 1 word, 1 cycle, no memory operands | 6-92 |
| CMPL | Class I | 1 word, 1 cycle, no memory operands | 6-94 |
| CMPR | Class I | 1 word, 1 cycle, no memory operands | 6-95 |
| CPL | Class IIA | 1 word, 1 cycle, memory read operand | 6-97 |
| CPL #lk | Class VIIa | 2 words, 2 cycles, memory read operand | 6-97 |
| CRGT | Class I | 1 word, 1 cycle, no memory operands | 6-100 |
| CRLT | Class I | 1 word, 1 cycle, no memory operands | 6-102 |
| DMOV | Class V | 1 word, 1 cycle, memory read and write | 6-104 |
| EXAR | Class I | 1 word, 1 cycle, no memory operands | 6-106 |
| IDLE | Class I | 1 word, 1 cycle, no memory operands, not repeatable | 6-107 |
| IDLE2 | Class I | 1 word, 1 cycle, no memory operands, not repeatable | 6-108 |
| IN | Class XXVI | 2 words, 2 cycles, input port | 6-109 |
| INTR | Class X | 1 word, 4 cycles, program counter discontinuity, no delayed slots, not repeatable | 6-111 |
| LACB | Class I | 1 word, 1 cycle, no memory operands | 6-113 |
| LACC | Class IIA | 1 word, 1 cycle, memory read operand | 6-114 |
| LACC #lk | Class III | 2 words, 2 cycles, long-immediate operand, no memory access, not repeatable | 6-114 |
| LACL | Class IIA | 1 word, 1 cycle, memory read operand | 6-117 |
| LACL #k | Class I | 1 word, 1 cycle, no memory operands, not repeatable | 6-117 |
| LACT | Class IIA | 1 word, 1 cycle, memory read operand | 6-120 |
| LAMM | Class IIB | 1 word, 1 cycle, memory-mapped register read | 6-122 |
| LAR | Class XXVII | 1 word, 2 cycles, pipeline-protected, memory read | 6-124 |
| LAR ARn, #k | Class XXVIII | 1 word, 2 cycles, pipeline-protected, memory read, not repeatable | 6-124 |
| LAR ARn, #lk | Class III | 2 words, 2 cycles, long-immediate operand, no memory access, not repeatable | 6-124 |
| LDP | Class XXVII | 1 word, 2 cycles, pipeline-protected, memory read | 6-127 |
| LDP #k | Class XXVIII | 1 word, 2 cycles, pipeline-protected, memory read, not repeatable | 6-127 |
| LMMR | Class XXIII | 2 words, 2 cycles, memory-mapped register load | 6-130 |
| LPH | Class IIA | 1 word, 1 cycle, memory read operand | 6-133 |
| LST | Class XXVII | 1 word, 2 cycles, pipeline-protected, memory read | 6-135 |
| LT | Class IIA | 1 word, 1 cycle, memory read operand | 6-138 |
| LTA | Class IIA | 1 word, 1 cycle, memory read operand | 6-140 |
| LTD | Class V | 1 word, 1 cycle, memory read and write | 6-142 |
| LTP | Class IIA | 1 word, 1 cycle, memory read operand | 6-145 |
| LTS | Class IIA | 1 word, 1 cycle, memory read operand | 6-147 |
| MAC | Class XIX | 2 words, 3 cycles, multiply accumulate | 6-149 |
| MACD | Class XXI | 2 words, 3 cycles, multiply accumulate with data move | 6-153 |
| MADD | Class XXII | 1 word, 2 cycles, multiply accumulate with data move | 6-158 |
| MADS | Class XX | 1 word, 2 cycles, multiply accumulate | 6-162 |
| MAR | Class I | 1 word, 1 cycle, no memory operands | 6-166 |
| MPY | Class IIA | 1 word, 1 cycle, memory read operand | 6-168 |
| MPY #k | Class I | 1 word, 1 cycle, no memory operands, not repeatable | 6-168 |
| MPY #lk | Class III | 2 words, 2 cycles, long-immediate operand, no memory access, not repeatable | 6-168 |
| MPYA | Class IIA | 1 word, 1 cycle, memory read operand | 6-171 |
| MPYS | Class IIA | 1 word, 1 cycle, memory read operand | 6-173 |
| MPYU | Class IIA | 1 word, 1 cycle, memory read operand | 6-175 |
| NEG | Class I | 1 word, 1 cycle, no memory operands | 6-177 |
| NMI | Class X | 1 word, 4 cycles, program counter discontinuity, no delayed slots, not repeatable | 6-179 |
| NOP | Class I | 1 word, 1 cycle, no memory operands | 6-180 |
| NORM | Class I | 1 word, 1 cycle, no memory operands | 6-181 |
| OPL | Class V | 1 word, 1 cycle, memory read and write | 6-184 |
| OPL | Class VI | 2 words, 2 cycles, memory read and write | 6-184 |
| OR | Class IIA | 1 word, 1 cycle, memory read operand | 6-187 |
| OR #lk | Class III | 2 words, 2 cycles, long-immediate operand, no memory access, not repeatable | 6-187 |
| ORB | Class I | 1 word, 1 cycle, no memory operands | 6-190 |
| OUT | Class XXV | 2 words, 3 cycles, output port | 6-191 |
| PAC | Class I | 1 word, 1 cycle, no memory operands | 6-193 |
| POP | Class I | 1 word, 1 cycle, no memory operands | 6-194 |
| POPD | Class IVA | 1 word, 1 cycle, memory write operand | 6-196 |
| PSHD | Class IIA | 1 word, 1 cycle, memory read operand | 6-198 |
| PUSH | Class I | 1 word, 1 cycle, no memory operands | 6-200 |
| RET | Class X | 1 word, 4 cycles, program counter discontinuity, no delayed slots, not repeatable | 6-202 |
| RETC | Class X | 1 word, 4 cycles, program counter discontinuity, no delayed slots, not repeatable | 6-203 |
| RETCD | Class XI | 1 word, 2 cycles, program counter discontinuity, 2 delayed slots, not repeatable | 6-205 |
| RETD | Class XI | 1 word, 2 cycles, program counter discontinuity, 2 delayed slots, not repeatable | 6-207 |
| RETE | Class X | 1 word, 4 cycles, program counter discontinuity, no delayed slots, not repeatable | 6-208 |
| RETI | Class X | 1 word, 4 cycles, program counter discontinuity, no delayed slots, not repeatable | 6-209 |
| ROL | Class I | 1 word, 1 cycle, no memory operands | 6-210 |
| ROLB | Class I | 1 word, 1 cycle, no memory operands | 6-211 |
| ROR | Class I | 1 word, 1 cycle, no memory operands | 6-212 |
| RORB | Class I | 1 word, 1 cycle, no memory operands | 6-213 |
| RPT | Class IIA | 1 word, 1 cycle, memory read operand, not repeatable | 6-214 |
| RPT #k | Class XXIX | 1 word, 2 cycle, no memory operands, not repeatable | 6-214 |
| RPT #lk | Class III | 2 words, 2 cycles, long-immediate operand, no memory access, not repeatable | 6-214 |
| RPTB | Class III | 2 words, 2 cycles, long-immediate operand, no memory access, not repeatable | 6-217 |
| RPTZ #lk | Class III | 2 words, 2 cycles, long-immediate operand, no memory access, not repeatable | 6-219 |
| SACB | Class I | 1 word, 1 cycle, no memory operands | 6-220 |
| SACH | Class IVA | 1 word, 1 cycle, memory write operand | 6-221 |
| SACL | Class IVA | 1 word, 1 cycle, memory write operand | 6-223 |
| SAMM | Class IVB | 1 word, 1 cycle, memory-mapped register write | 6-225 |
| SAR | Class IVA | 1 word, 1 cycle, memory write operand | 6-227 |
| SATH | Class I | 1 word, 1 cycle, no memory operands | 6-229 |
| SATL | Class I | 1 word, 1 cycle, no memory operands | 6-231 |
| SBB | Class I | 1 word, 1 cycle, no memory operands | 6-232 |
| SBBB | Class I | 1 word, 1 cycle, no memory operands | 6-233 |
| SBRK #k | Class I | 1 word, 1 cycle, no memory operands, not repeatable | 6-234 |
| SETC | Class I | 1 word, 1 cycle, no memory operands | 6-235 |
| SFL | Class I | 1 word, 1 cycle, no memory operands | 6-237 |
| SFLB | Class I | 1 word, 1 cycle, no memory operands | 6-238 |
| SFR | Class I | 1 word, 1 cycle, no memory operands | 6-239 |
| SFRB | Class I | 1 word, 1 cycle, no memory operands | 6-241 |
| SMMR | Class XXIV | 2 words, 2 cycles, memory-mapped register store | 6-243 |
| SPAC | Class I | 1 word, 1 cycle, no memory operands | 6-246 |
| SPH | Class IVA | 1 word, 1 cycle, memory write operand | 6-247 |
| SPL | Class IVA | 1 word, 1 cycle, memory write operand | 6-249 |
| SPLK | Class VIIb | 2 words, 2 cycles, memory write operand, not repeatable | 6-251 |
| SPM | Class I | 1 word, 1 cycle, no memory operands, not repeatable | 6-252 |
| SQRA | Class IIA | 1 word, 1 cycle, memory read operand | 6-253 |
| SQRS | Class IIA | 1 word, 1 cycle, memory read operand | 6-255 |
| SST | Class IVA | 1 word, 1 cycle, memory write operand | 6-257 |
| SUB | Class IIA | 1 word, 1 cycle, memory read operand | 6-259 |
| SUB #k | Class I | 1 word, 1 cycle, no memory operands, not repeatable | 6-259 |
| SUB #lk | Class III | 2 words, 2 cycles, long-immediate operand, no memory access, not repeatable | 6-259 |
| SUBB | Class IIA | 1 word, 1 cycle, memory read operand | 6-263 |
| SUBC | Class IIA | 1 word, 1 cycle, memory read operand | 6-265 |
| SUBS | Class IIA | 1 word, 1 cycle, memory read operand | 6-267 |
| SUBT | Class IIA | 1 word, 1 cycle, memory read operand | 6-269 |
| TBLR | Class XVII | 1 word, 3 cycles, table read | 6-271 |
| TBLW | Class XVIII | 1 word, 3 cycles, table write | 6-274 |
| TRAP | Class X | 1 word, 4 cycles, program counter discontinuity, no delayed slots, not repeatable | 6-277 |
| XC | Class I | 1 word, 1 cycle, no memory operands, not repeatable | 6-278 |
| XOR | Class IIA | 1 word, 1 cycle, memory read operand | 6-280 |
| XOR #lk | Class III | 2 words, 2 cycles, long-immediate operand, no memory access, not repeatable | 6-280 |
| XORB | Class I | 1 word, 1 cycle, no memory operands | 6-283 |
| XPL | Class V | 1 word, 1 cycle, memory read and write | 6-284 |
| XPL | Class VI | 2 words, 2 cycles, memory read and write | 6-284 |
| ZALR | Class IIA | 1 word, 1 cycle, memory read operand | 6-287 |
| ZAP | Class I | 1 word, 1 cycle, no memory operands | 6-289 |
| ZPR | Class I | 1 word, 1 cycle, no memory operands | 6-290 |

### Reading notes for Table B–2

- Five mnemonics appear in two classes each (both rows transcribed above):
  APL (V, VI), BLDD (XII, XIII), BLPD (XIV, XV), OPL (V, VI), XPL (V, VI).
  The two rows differ in word count / cycle count (1-word vs 2-word form).
- `LAR` appears three times: LAR (XXVII), LAR ARn, #k (XXVIII),
  LAR ARn, #lk (III). `LDP` twice: LDP (XXVII), LDP #k (XXVIII).
  `RPT` three times: RPT (IIA), RPT #k (XXIX), RPT #lk (III).
- Class membership counts cross-checked between Table B–1 and Table B–2:
  Class I 49, IIA 32, III 11, X 9, IVA 7, V 5, VIII 5, IX 5, XI 4, VI 3,
  XXVII 3 — all agree. Remaining classes have 1–2 members each as listed.

## Unverified / extraction notes (Appendix B)

- Bold typeface marking "instructions new for the ’C5x" (Table B–1/B–2
  footnote †) is lost in text extraction and is NOT reproduced.
  [UNVERIFIED — bold marking, App B, PDF pp.639–649]
- No other garbling was found in Appendix B; both tables extracted cleanly
  and all 155 Table B–2 rows parsed with 0 failures.
