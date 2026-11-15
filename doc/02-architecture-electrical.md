# TMS320C51 — Architecture & Electrical Summary (SPRS030A, pp. 30–50)

Source: TI SPRS030A, *TMS320C5x, TMS320LC5x Digital Signal Processors*, April 1995, revised April 1996.
Scope: **datasheet PDF pages 30–50 only**, distilled from
`SPRS030A.txt` (`pdftotext -layout`).
Page numbers below are **PDF page numbers** (printed footer numbers coincide in this range).
Full instruction listing lives in the SPRU056D distillation at `../c5x_manual/06a–06d`;
this file condenses only what the datasheet itself presents, plus the electrical data.

Scope notes (read first):
- The CPU core blocks (ALU, CALU, PLU, ARAU, program/data buses) are described on
  datasheet pages before p. 30 — **not in this chunk**; see `../c5x_manual/02-architectural-overview.md`.
- **Speed grades (50/35/25/20 ns) are not stated in pp. 30–50.** They are in the
  device-summary table on PDF p. 2 (SPRS030A Table 1: TMS320C51 50/35/25/20 ns;
  TMS320LC51 50/40/25 ns). The IDD test frequencies in §4 below (fx = 40/57/80/100 MHz)
  are consistent with that mapping (machine-cycle time = 2 × input-clock period), but the
  grade list itself is outside this chunk — covered in 01-overview-variants-pins-memory.md.
- **No PLL option table exists in pp. 30–50.** The only clock-mode facts here are the
  IDLE2 standby condition ("divide-by-two clock mode", §4) and the CLKIN2 pin being the
  PLL clock input (pin tables, pp. < 30). The PLL multiply table is in the timing section
  (pp. 51+, 03-timing-mechanical.md). Cross-reference only: SPRU056D §9.2.1
  (`../c5x_manual/09a-peripherals-timer-clock-waitstates.md`) states the 'C51 PLL option is
  **multiply-by-1**; the ×3/×4/×5/×9 options belong to the 'LC56/'C57S/'LC57 family and
  do **not** apply to the 'C51.
- No separate power-dissipation table exists in pp. 30–50; power must be derived from
  IDD (§4). No separate IDLE1 current is given — only one standby figure (IDLE2, §4).

---

## 1. External interface, DMA, multiprocessing (pp. 30, 34)

- Three 16-bit address spaces — program, data, I/O — each 64K 16-bit words, selected by
  PS, DS, IS; full 16-bit address + data bus. I/O is treated like memory (memory-mapped
  I/O devices use the same buses) (SPRS030A § External interface, p. 30).
- Control signals: R/W (read/write direction), STRB (timing reference for all external
  cycles), RD and WE (read/write cycle + timing, minimise external gating)
  (SPRS030A p. 30).
- READY line: the processor waits for slow memory/I/O until the device asserts READY
  (SPRS030A p. 30).
- Global memory: external data-memory space shared between processors; BR is asserted
  at the start of a global-memory access and the access length is controlled by READY.
  The 8-bit memory-mapped global-memory allocation register (GREG) defines how much of
  data memory is global; an operand inside that space asserts BR (SPRS030A pp. 30, 34).
- HOLD/HOLDA DMA: another device asserts HOLD low; the 'C5x tristates address/data/
  control lines and asserts HOLDA. Program execution from on-chip memory can continue
  concurrently in hold mode (SPRS030A p. 34).
- BR-requested DMA (single-access RAM devices, incl. 'C51): unlike hold mode, a
  BR-requested DMA **always halts the operation currently being executed by the CPU**.
  Internal-bus access is granted on the **third clock cycle** after BR is received.
  In the PQ package the IAQ pin indicates grant; in the PZ package there is no IAQ pin,
  so the host must wait **two clock cycles** after driving BR low before starting the
  transfer (SPRS030A p. 30). Note: with status bit HM = 0, hold mode lets CPU operation
  continue; BR-DMA does not.
- Multiprocessor serial interconnection: multiple 'C5x devices link through serial ports;
  a full-duplex link needs as few as four signal lines (SPRS030A p. 34).

**HPI — not on the 'C51.** The host-port interface (8-bit parallel host port, 2K-word
buffer, SAM/HOM modes, HBIL/HCNTL/HPIC/HINT/HRDY) exists only on TMS320C57S, TMS320LC57,
TMS320LC57S (SPRS030A pp. 30–31). Ignore for Courier work. (Agrees with SPRU056D §9.10;
see `../c5x_manual/09b-peripherals-serial-bsp-tdm-hpi.md`.)

## 2. Serial ports, wait states, timer (pp. 31–32)

### 2.1 Serial ports — 'C51 verdict: 1× general-purpose SP + 1× TDM port; no BSP

- General-purpose serial port: full-duplex, double-buffered, fully static; DXR/DRR
  memory-mapped registers; byte or 16-bit transfers; maskable XINT/RINT interrupts
  (SPRS030A p. 31).
- TDM port: up to eight 'C5x devices time-multiplexed; 16-bit words on TDAT, destination
  addresses on TADD; one channel transmitted, one or more received per device; frame sync
  once every 128 clock cycles (one 16-bit word per channel × 8 channels); double-buffered
  both directions; can be configured in software as a general-purpose serial port
  (SPRS030A p. 31).
- Both port types operate at up to **one-fourth the machine cycle rate (CLKOUT1)**
  (SPRS030A p. 31).
- Buffered serial port (BSP): SPI + auto-buffering unit (ABU) with its own circular
  addressing registers; buffers in 2K words of internal memory; 8/10/12/16-bit packets;
  burst or continuous mode; PCM mode on transmit; fully static; max operating frequency
  CLKOUT1 — **28.6 Mb/s at 35 ns, 40 Mb/s at 25 ns** (SPRS030A pp. 31–32). BSP is on
  'LC56, 'C57S, 'LC57 only — **not the 'C51**.
- Device matrix (SPRS030A p. 32): most 'C5x = 1 SP + 1 TDM; 'C52 = 1 SP, no TDM;
  'C53SX = 2 SP, no TDM; 'LC56/'C57S/'LC57 = 1 SP + 1 BSP.

### 2.2 Software wait-state generators (p. 32)

- 16 wait-state generating circuits, user-programmable to **0, 1, 2, 3, or 7 wait states**,
  mapped on **16K-word boundaries** in program, data, and I/O spaces (SPRS030A p. 32).
- The 'C53S/'C57S and 'LC56/'LC57 use a single 16-bit wait-state register PDWSR at
  address **0x28**; the programmed count (0–7) applies to all external addresses in the
  corresponding space regardless of address value (SPRS030A p. 32). By implication the
  'C50/'C51/'C52 use the per-16K-block scheme instead — confirmed by SPRU056D §9.4.1
  Variant A (PDWSR 2-bit field per 16K block); see `../c5x_manual/09a-…`, §9.4.1.

### 2.3 Timer (p. 32)

- 16-bit timer + 4-bit prescaler; clocks at **one-half to one-thirty-second** the machine
  rate, depending on the programmable divide-down ratio; can be stopped/restarted/reset/
  disabled by status bits (SPRS030A p. 32).
- The timer is decremented by one at every CLKOUT1 cycle; each time the counter
  decrements to zero a timer interrupt (TINT) and a one-CLKOUT1-cycle pulse on the
  external TOUT pin are generated (SPRS030A p. 32). **Wording caveat:** read literally
  this says TIM decrements every CLKOUT1 cycle; SPRU056D §9.3 is more precise — the
  *prescaler* decrements every CLKOUT1 cycle and TIM decrements when the prescaler wraps
  (TINT rate = f(CLKOUT1) / [(TDDR+1)(PRD+1)]). See Contradictions, C1.
- When the timer is stopped, its internal clocks are shut off (low-power mode)
  (SPRS030A p. 32).

## 3. JTAG / on-chip analysis block (p. 33)

Table 5, IEEE 1149.1 / boundary-scan / analysis-block configurations (SPRS030A Table 5, p. 33):

| Device | IEEE 1149.1 | Boundary scan | Analysis block |
|---|---|---|---|
| 'C50 / 'LC50 | Yes | Yes | Full |
| **'C51 / 'LC51** | **Yes** | **Yes** | **Full** |
| 'C52 / 'LC52 | Yes | No | Full |
| 'C53 / 'LC53 | Yes | Yes | Full |
| 'C53S / 'LC53S | Yes | No | Reduced |
| 'LC56 | Yes | No | Full |
| 'C57S | Yes | Yes | Full |
| 'LC57 | Yes | No | Full |

- Full analysis block: message passing (monitor mode + scan), flexible breakpoints
  (program fetches/reads/writes, EMU0/1 pin activity, data reads/writes, CPU events —
  calls, returns, interrupts/traps, branches, pipeline clock — event-counter overflow),
  16-bit event counter (CPU clocks, pipeline advances, instruction fetches, branches,
  calls, returns, interrupts/traps, program/data reads/writes), PC-discontinuity trace
  buffer (SPRS030A p. 33).
- Reduced block ('C53S/'LC53S only): message passing + breakpoints on program
  fetches/reads/writes and EMU0/1 only (SPRS030A p. 33).

## 4. Instruction-set summary as presented in the datasheet (pp. 34–41)

Condensed from SPRS030A Table 7 (pp. 38–41) and §§ "instruction set" / "addressing modes" /
"repeat feature" (pp. 34–36). **Not a full opcode listing** — opcodes and per-instruction
detail are in `../c5x_manual/06a–06d` and `appendix-b-instruction-classes-cycles.md`.

### 4.1 Ground rules (p. 36)

- 'C5x instruction set is a superset of 'C1x/'C2x; 'C1x/'C2x source is upward compatible;
  the TI assembler accepts 'C2x instructions (SPRS030A p. 36).
- Next instruction is prefetched while the current one executes; cycle count varies with
  whether the next operand fetch is from internal or external memory. Highest throughput
  needs on-chip data memory and internal/fast external program memory (SPRS030A p. 34).
- **Cycle timings in Table 7 assume execution from internal program memory and internal
  dual-access data memory, for single-instruction execution, NOT repeat mode**
  (SPRS030A p. 36).
- **A read or write access to any peripheral memory-mapped register in data-memory
  locations 20h–4Fh adds one cycle** to the listed time (peripherals are accessed over
  the internal peripheral bus) (SPRS030A p. 36).
- Word counts: a form with a long immediate occupies 2 words; short-immediate forms 1 word
  (SPRS030A p. 36).

### 4.2 Addressing modes (pp. 34–35)

Six modes: direct, indirect, immediate, register, memory-mapped, circular
(SPRS030A p. 34).

- Direct: 7-bit field in the instruction + 9-bit data-page pointer (DP) = 16-bit address;
  512 pages × 128 words (SPRS030A p. 34).
- Indirect: through AR0–AR7, selected by ARP (0–7). Seven types: autoincrement/
  autodecrement, post-indexing by ±AR0, single-indirect (no update), bit-reversed
  (FFT) with increment/decrement. AR/ARP update happens in the same cycle as the
  instruction (SPRS030A p. 34).
- Immediate: short (in the single-word instruction) and long (second word of a
  two-word instruction) (SPRS030A p. 35).
- Register: operands in CPU registers, explicit or implicit (SPRS030A p. 35).
- Memory-mapped: page-zero registers accessed independently of DP, without a full
  address (SPRS030A p. 35).
- Circular: two independent circular buffers; five dedicated registers (begin/end per
  buffer + control register) plus one auxiliary register as pointer; all must be
  initialised before use; zero-overhead wrap for FIR/convolution/correlation/waveform
  work (SPRS030A p. 35).

### 4.3 Repeat / block repeat (pp. 35–36)

- RPT/RPTZ load the 16-bit repeat counter RPTC with N; the next single instruction
  executes **N + 1 times, max 65,536**. RPTZ also clears ACC and PREG before repeating.
  RPTC is cleared by reset (SPRS030A p. 35).
- Repeatable instructions include MAC/MACD, BLDD/BLPD, IN/OUT, TBLR/TBLW; when repeated
  these multicycle instructions are pipelined and effectively become single-cycle
  (e.g. a table location read every cycle) (SPRS030A p. 35).
- Once RPT/RPTZ is decoded, **all interrupts including NMI (except reset) are masked
  until the repeat loop completes**; the device still responds to HOLD during RPT/RPTZ
  (SPRS030A p. 35).
- Block repeat (RPTB): zero-overhead FOR/DO loops; controlled by PASR, PAER, BRCR and
  the BRAF bit in PMST. BRCR = loop count 0–65,535. RPTB loads PASR with the address of
  the instruction following RPTB and PAER with its long-immediate operand — the address
  of the instruction following the last loop instruction, **minus one**. The block must
  contain **at least three instruction words**. RPTB sets BRAF. At each PC update PAER
  is compared to PC; if equal and BRCR > 0, BRCR decrements and PASR loads into PC;
  if BRCR = 0, BRAF clears and execution continues past the loop (SPRS030A pp. 35–36).
- WHILE-loop exit: clear BRAF; the current pass completes but the loop is not re-entered.
  **BRAF must be reset at least four instruction words before the end of the loop**
  (SPRS030A p. 36). Branches, calls, and interrupts do not necessarily disturb the loop;
  on return, loop execution resumes (SPRS030A p. 36).

### 4.4 Cycle-count patterns (SPRS030A Table 7, pp. 38–41)

Most single-word ALU/logic/multiply instructions are **1 cycle**; the multicycle cases
that matter for RE timing are:

| Group | Examples | Words | Cycles |
|---|---|---|---|
| Accumulator, 1-word forms | ADD/SUB/AND/OR/XOR/LACC/SACH/SACL, MPY, MPYA/MPYS, APAC/PAC, NORM, shifts/rotates, ACCB ops | 1 | 1 |
| Long-immediate forms | ADD/AND/OR/SUB/XOR/LACC #lk, MPY #lk | 2 | 2 |
| Load/store page pointer | LDP (either form) | 1 | 2 |
| Branches, non-delayed | B, BACC, CALA, CALL, INTR, NMI, RET, RETE, RETI, TRAP | 1–2 | 4 |
| Branches, conditional, non-delayed | BCND, CC, RETC | 1–2 | 2 or 4 (4 if taken) |
| Branches/calls/returns, delayed | BD, BACCD, BANZD, BCNDD, CALAD, CALLD, CCD, RETCD, RETD | 1–2 | 2 |
| BANZ (non-delayed) | BANZ | 2 | 2 or 4 |
| Conditional execution | XC | 1 | 1 |
| Block moves | BLDD/BLPD (2-word forms) | 2 | 3 |
| Block moves, BMAR forms | BLDD/BLPD with source/dest in BMAR | 1 | 2 |
| Table read/write | TBLR, TBLW | 1 | 3 |
| Multiply/accumulate | MAC, MACD (2-word) | 2 | 3 |
| Multiply/accumulate, BMAR | MADD, MADS | 1 | 3 |
| I/O | IN | 2 | 2 |
| I/O | OUT | 2 | 3 |
| Memory-mapped reg load/store | LMMR, SMMR | 2 | 2 or 3 |
| LAMM / SAMM (memory-mapped reg) | LAMM, SAMM | 1 | 1 or 2 (§4.1 +1-cycle rule) |
| Data move | DMOV | 1 | 1 |
| Status load | LST (ST0/ST1) | 1 | 2 |
| Status store | SST | 1 | 1 |
| Repeat setup | RPT (all forms), RPTZ, RPTB | 1–2 | 2 |
| Low-power | IDLE, IDLE2 | 1 | 1 |
| PLU (parallel logic unit) | APL/CPL/OPL/XPL (1-word) | 1 | 1 |
| PLU, long immediate | APL/CPL/OPL/XPL #lk | 2 | 2 |
| SPLK (store long immediate) | SPLK | 2 | 2 |

(All rows: SPRS030A Table 7, pp. 38–41. Opcode bit patterns are in Table 7 itself and
are **not** reproduced here — see `../c5x_manual/06a–06d`.)

**Datasheet-only additions vs the manual distillation:**
- The explicit statement that cycle timings are for single-instruction execution, not
  repeat mode, and the internal-memory assumption (p. 36) — same substance as SPRU056D
  §6.2 footnotes, but stated here as the table's own ground rule.
- Delayed-branch family uniformly 2 cycles vs 4 non-delayed — consistent with the
  manual's pipeline chapter (`../c5x_manual/07-pipeline.md`: 4-cycle flush for non-delayed
  branch/call/return).

## 5. Absolute maximum ratings

Stress ratings only — functional operation at these conditions is not implied; extended
exposure may affect reliability. All voltages with respect to VSS (SPRS030A p. 45, Note 3;
p. 47, Note 3).

| Parameter | 'C5x (5 V) (SPRS030A p. 45) | 'LC5x (3.3 V) (SPRS030A p. 47) |
|---|---|---|
| Supply voltage VDD | −0.3 V to **7 V** | −0.3 V to **5 V** |
| Input voltage VI | −0.3 V to 7 V | −0.3 V to 5 V |
| Output voltage VO | −0.3 V to 7 V | −0.3 V to 5 V |
| Operating ambient TA | −40 °C to 85 °C | −40 °C to 85 °C |
| Operating case TC | 0 °C to 85 °C | 0 °C to 85 °C |
| Storage Tstg | −55 °C to 150 °C | −55 °C to 150 °C |

For the Courier 'C51 (5 V part): never exceed 7 V on any supply/input/output pin, even
transiently; the 3.3 V LC51 ceiling is 5 V — a 5 V rail on an LC51 pin is at the absolute
maximum, not a legal operating point.

## 6. Recommended operating conditions

### 6.1 'C5x, 5 V (SPRS030A p. 45)

| Parameter | Min | Nom | Max | Unit |
|---|---|---|---|---|
| VDD | 4.75 | 5 | 5.25 | V |
| VSS | — | 0 | — | V |
| VIH, X2/CLKIN, CLKIN2 | 3.0 | — | VDD + 0.3 | V |
| VIH, CLKX, CLKR, TCLKX, TCLKR | 2.5 | — | VDD + 0.3 | V |
| VIH, all other inputs | 2.0 | — | VDD + 0.3 | V |
| VIL, X2/CLKIN, CLKIN2, CLKX, CLKR, TCLKX, TCLKR | −0.3 | — | 0.7 | V |
| VIL, all other inputs | −0.3 | — | 0.8 | V |
| IOH (high-level output current) | — | — | −300 µA | (Note 4; see below) |
| IOL (low-level output current) | — | — | 2 mA | |
| TC (operating case temp.) | 0 | — | 85 | °C |
| TA (operating ambient temp.) | −40 | — | 85 | °C |

Note 4 (SPRS030A p. 45): IOH may be exceeded with a 1-kΩ pulldown on the TDM serial
port TADD output; the output still meets VOH under those conditions.

### 6.2 'LC5x, 3.3 V (SPRS030A p. 47) — for contrast only

| Parameter | Min | Nom | Max | Unit |
|---|---|---|---|---|
| VDD | 3.13 | 3.3 | 3.47 | V |
| VIH, X2/CLKIN, CLKIN2 | 2.5 | — | VDD + 0.3 | V |
| VIH, CLKX, CLKR, TCLKX, TCLKR | 2.0 | — | VDD + 0.3 | V |
| VIH, all other inputs | 1.8 | — | VDD + 0.3 | V |
| VIL, clock/serial inputs | −0.3 | — | 0.5 | V |
| VIL, all other inputs | −0.3 | — | 0.6 | V |
| IOH / IOL | — | — | −300 µA / 2 mA | |
| TC / TA | 0–85 °C / −40–85 °C | | | |

Key C51-vs-LC51 differences: LC51 VIH thresholds are lower across the board
(1.8 V vs 2.0 V general; 2.5 V vs 3.0 V clock) and its VIL maxima are tighter
(0.5/0.6 V vs 0.7/0.8 V). A 5 V-tolerant input assumption is wrong for the LC51.

## 7. Electrical characteristics

Typical values at VDD = 5 V (TA = 25 °C) for 'C5x; VDD = 3.3 V (TA = 25 °C) for 'LC5x,
unless otherwise stated (SPRS030A p. 46, footnote †; p. 48, footnote †).

### 7.1 'C5x, 5 V (SPRS030A p. 46)

| Parameter | Test conditions | Min | Typ | Max | Unit |
|---|---|---|---|---|---|
| VOH | IOH = 300 µA | 2.4 | 3 | — | V |
| VOL | IOL = 2 mA | — | 0.3 | 0.6 | V |
| IOZ, BR (internal pullup) | VDD = 5.25 V | −500 | — | 20 | µA |
| IOZ, all other 3-state outputs | VDD = 5.25 V | −20 | — | 20 | µA |
| II, TRST (internal pulldown) | VI = VSS to VDD | −10 | — | 800 | µA |
| II, TMS, TCK, TDI (internal pullups) | VI = VSS to VDD | −500 | — | 10 | µA |
| II, X2/CLKIN | VI = VSS to VDD | −50 | — | 50 | µA |
| II, all other inputs | VI = VSS to VDD | −10 | — | 10 | µA |
| IDD(core), core CPU supply current | fx = 40 MHz, VDD = 5.25 V | — | — | 60 | mA |
| IDD(core) | fx = 57 MHz, VDD = 5.25 V | — | — | 67 | mA |
| IDD(core) | fx = 80 MHz, VDD = 5.25 V | — | — | 94 | mA |
| IDD(core) | fx = 100 MHz, VDD = 5.25 V | — | — | 110 | mA |
| IDD(pins), pin supply current | fx = 40 MHz, VDD = 5.25 V | — | — | 40 | mA |
| IDD(pins) | fx = 57 MHz, VDD = 5.25 V | — | — | 45 | mA |
| IDD(pins) | fx = 80 MHz, VDD = 5.25 V | — | — | 63 | mA |
| IDD(pins) | fx = 100 MHz, VDD = 5.25 V | — | — | 75 | mA |
| IDD(standby), standby supply current | IDLE2, divide-by-two clock mode, clocks shut off | — | — | 5 | µA |
| Ci (input capacitance) | | — | — | 15 | pF |
| Co (output capacitance) | | — | — | 15 | pF |

### 7.2 'LC5x, 3.3 V (SPRS030A p. 48) — for contrast only

| Parameter | Test conditions | Min | Typ | Max | Unit |
|---|---|---|---|---|---|
| VOH | IOH = 300 µA | 2.0 | — | — | V |
| VOH | IOH = 20 µA | — | VDD − 0.3 | — | V (derived from characterisation, not tested) |
| VOL | IOL = 2 mA | — | — | 0.4 | V |
| VOL | IOL = 20 µA | — | — | 0.3 | V (derived from characterisation, not tested) |
| IOZ / II | same pin groups as §7.1 | (same limits, except X2/CLKIN oscillator-disabled: −10 to 10 µA) | | | µA |
| IDD(core) | fx = 40 MHz, VDD = 3.47 V | — | — | 26 | mA |
| IDD(core) | fx = 50 MHz, VDD = 3.47 V | — | — | 33 | mA |
| IDD(core) | fx = 80 MHz, VDD = 3.47 V | — | — | 53 | mA |
| IDD(pins) | fx = 40 MHz, VDD = 3.47 V | — | — | 18 | mA |
| IDD(pins) | fx = 50 MHz, VDD = 3.47 V | — | — | 22 | mA |
| IDD(pins) | fx = 80 MHz, VDD = 3.47 V | — | — | 35 | mA |
| IDD(standby) | IDLE2, divide-by-two clock mode, clocks shut off | — | — | 5 | µA |
| Ci / Co | | — | — | 15 | pF |

### 7.3 Reading the IDD figures (derived — not datasheet statements)

- All IDD maxima are measured at the **maximum** supply (5.25 V / 3.47 V), not nominal
  VDD (SPRS030A pp. 46, 48). Do not compare them against nominal-voltage figures.
- fx is the input clock frequency. With the divide-by-two clock mode the machine-cycle
  rate is fx/2, so fx = 40/57/80/100 MHz correspond to 50/35/25/20 ns machine cycles
  (20/28.6/40/50 MIPS). The fx↔cycle-time mapping itself is in the timing tables
  (pp. 51+, 03-timing-mechanical.md) and the grade list on PDF p. 2 — both outside this chunk.
- mA/MIPS at max VDD, worst case (derived): 'C51 core 110 mA / 50 MIPS = **2.2 mA/MIPS**,
  pins 75 mA / 50 MIPS = 1.5 mA/MIPS, total 185 mA / 50 MIPS = **3.7 mA/MIPS** at
  fx = 100 MHz; at fx = 40 MHz (20 MIPS) core is 60 mA = 3.0 mA/MIPS — current does
  **not** scale linearly with clock (fixed overhead dominates at low fx). LC51 core
  53 mA / 40 MIPS = 1.3 mA/MIPS at fx = 80 MHz, VDD = 3.47 V.
- Derived worst-case total power (arithmetic, not a datasheet spec): 'C51 at
  fx = 100 MHz, VDD = 5.25 V: 5.25 V × (110 + 75) mA ≈ **0.97 W**.
- **No IDLE1 current is given** in pp. 30–50. The only standby figure is IDD(standby)
  = 5 µA max in **IDLE2**, divide-by-two clock mode, clocks shut off — identical for
  'C5x and 'LC5x (SPRS030A pp. 46, 48). IDLE1 (CPU stopped, peripherals/clocks running)
  current is not specified here.

## 8. Parameter measurement information (pp. 49–50)

Test-load and reference levels needed to interpret every timing number in the datasheet
(SPRS030A § Parameter Measurement Information, pp. 49–50; Fig. 9, Figs. 10–11).

- **Test load circuit (Fig. 9, p. 49):** tester pin electronics into a load of
  VLOAD = **1.5 V**, CT = **80 pF** typical load-circuit capacitance; IOL = 2 mA
  (all outputs) minimum, IOH = 300 µA (all outputs) minimum (SPRS030A p. 49).
- **TTL outputs (Fig. 10, p. 49):** driven to min logic-high **2.4 V (2 V for 'LC5x)**
  and max logic-low **0.6 V (0.4 V for 'LC5x)**. Transition times: high-to-low — output
  is "no longer high" at **2 V (1.6 V)**, "low" at **1 V (0.8 V)**; low-to-high —
  "no longer low" at **1 V (0.8 V)**, "high" at **2 V (1.6 V)** (SPRS030A p. 49).
  Parenthesised values are the 3.3 V ('LC5x) figures throughout §8.
- **TTL inputs (Fig. 11, p. 49):** transition times: high-to-low — "no longer high" at
  **2 V (1.8 V)**, "low" at **0.8 V (0.6 V)**; low-to-high — "no longer low" at
  **0.8 V (0.6 V)**, "high" at **2 V (1.8 V)** (SPRS030A p. 49).
- **Timing-parameter symbology (p. 50):** symbols per JEDEC Standard 100-A. Subscripts:
  a = access, c = cycle time (period), d = delay, dis = disable, en = enable, f = fall,
  h = hold, r = rise, su = setup, t = transition, v = valid, w = pulse duration
  (width), X = unknown/changing/don't-care. Letters: H = high, L = low, V = valid,
  Z = high impedance (SPRS030A p. 50).

## 9. Clocking / PLL — what pp. 30–50 actually contain

- **Nothing substantive.** No PLL multiply table, no CLKMD/CLKIN2 option table, and no
  clock-frequency limits appear in pp. 30–50. The only clock-mode facts in this chunk:
  (a) the IDLE2 standby condition is "divide-by-two clock mode, clocks shut off"
  (§7.1/§7.2); (b) serial ports run at up to CLKOUT1/4 and the BSP SPI at up to CLKOUT1
  (§2.1). Everything else clock/PLL is in the timing sections (pp. 51+, 03-timing-mechanical.md).
- Cross-reference (manual, not this datasheet): SPRU056D §9.2.1
  (`../c5x_manual/09a-peripherals-timer-clock-waitstates.md`) assigns the 'C51 to the
  standard-clock family with PLL multiply-by-1 only; the ×3/×4/×5/×9 table (§9.2.2)
  is for 'LC56/'C57S/'LC57 only. Do not apply it to the 'C51.

## 10. Contradictions vs SPRU056D

Checked against `../c5x_manual/02-architectural-overview.md`,
`04-program-control.md`, `06a-instruction-set-summary.md`,
`07-pipeline.md`, `09a-peripherals-timer-clock-waitstates.md`,
`09b-peripherals-serial-bsp-tdm-hpi.md`, `appendix-b-instruction-classes-cycles.md`.
No hard contradiction was found on any checked point; the following are wording gaps or
apparent discrepancies:

- **C1 — Timer decrement rate (datasheet loose, manual precise).** Datasheet p. 32:
  "The timer is decremented by one at every CLKOUT1 cycle" and "clocks between
  one-half and one thirty-second the machine rate". SPRU056D §9.3
  (`../c5x_manual/09a-…`): the **prescaler (PSC)** decrements every CLKOUT1 cycle; TIM
  decrements only when PSC wraps, giving TINT rate =
  f(CLKOUT1) / [(TDDR+1)(PRD+1)]. The datasheet sentence, read literally, would give a
  TINT every (PRD+1) CLKOUT1 cycles with no prescaler effect. Treat the manual's
  two-stage formula as authoritative; the datasheet's "one-half to one-thirty-second"
  is consistent only with the prescaler stage, not with TIM decrementing every cycle.
- **C2 — LAMM/SAMM cycles: apparent only, not a contradiction.** Datasheet Table 7
  (p. 38) and SPRU056D §6.2 (`../c5x_manual/06a-…`) both give LAMM/SAMM as **1 or 2**
  cycles (2 when the access hits a peripheral register, per the 20h–4Fh +1-cycle rule).
  `../c5x_manual/appendix-b-…` class tables list them as "1 word, 1 cycle" (classes IIB/IVB)
  — that is the appendix's simplification, not the manual §6.2 value. No datasheet↔manual
  conflict; do not quote the appendix's 1-cycle figure for peripheral accesses.
- **C3 — Wait-state generator count vs register scheme (consistent, different framing).**
  Datasheet p. 32: "16 wait-state generating circuits … 0, 1, 2, 3, or 7 wait states …
  mapped on 16K-word boundaries", with the single-PDWSR (0x28) scheme restricted to
  'C53S/'C57S/'LC56/'LC57. SPRU056D §9.4 (`../c5x_manual/09a-…`): 'C50/'C51/'C52 use
  Variant A — PDWSR with a 2-bit field per 16K block (program + data), plus IOWSR/CWSR.
  No conflict; the datasheet's "16 circuits" is the family-level count, the manual's
  PDWSR/IOWSR/CWSR is the 'C51 register-level implementation.
- **C4 — RPT/RPTB behaviour: agreement.** Datasheet pp. 35–36 (interrupts incl. NMI
  masked during RPT, HOLD honoured; RPTB PASR/PAER/BRAF/≥3-word block/≥4-word BRAF-clear
  exit) matches SPRU056D §4.6/§4.7 (`../c5x_manual/04-program-control.md`) exactly,
  including the 65,536 maximum and the RPTZ ACC/PREG clear. No contradiction.
- **C5 — IDLE2 standby current: datasheet-only number.** IDD(standby) = 5 µA max in
  IDLE2, divide-by-two mode, clocks shut off (SPRS030A pp. 46, 48) has no counterpart
  figure in the distilled manual sections checked; it does not contradict the manual's
  IDLE2 description (interrupt must be high ≥ 4 CLKOUT1 cycles; PLL stops in IDLE2),
  it supplements it. No IDLE1 current in either source's checked sections.
- **Direction manual→datasheet (gaps in the datasheet, not contradictions):** the
  datasheet's pp. 30–50 give no register addresses (PDWSR 28h, GREG, TCR/PRD/TIM),
  no timer formula, no repeatable-instruction whitelist, no pipeline-conflict rules,
  and no PLL table — all of that is SPRU056D-only. Conversely the datasheet is the sole
  source in this pair for absolute maxima, VIH/VIL/VOH/VOL, IDD/standby currents,
  leakage, capacitance, and the test-load/transition-level definitions.

## 11. Not in pp. 30–50 (left for other workers)

- CPU core blocks (ALU/CALU/PLU/ARAU/buses), on-chip memory map, pinout, package data —
  pp. < 30 .
- Speed-grade table (50/35/25/20 ns for 'C51) — PDF p. 2, Table 1 .
- PLL multiply options, clock timing (tc(CI)/tc(CO), PLL transitory phase), all
  switching characteristics, serial-port/HPI/DMA timing — pp. 51–86 (03-timing-mechanical.md).
- Full opcode bit patterns and per-instruction descriptions — `../c5x_manual/06a–06d`.
- IDLE1 supply current — not specified in pp. 30–50 [UNVERIFIED — no figure found].
