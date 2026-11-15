# TMS320C51 — Datasheet Digest (SPRS030A, pp. 1–29)

**Source:** TI SPRS030A, *TMS320C5x, TMS320LC5x Digital Signal Processors*,
April 1995, revised April 1996. This file condenses **PDF pp. 1–29 only**
(front matter, variant table, pinouts, signal descriptions, functional
overview, memory maps). Page numbers below are **PDF page numbers**
(p. 1 = PDF page 1; printed footer numbers coincide in this range).
Full text: `SPRS030A.txt`; PDF: `SPRS030A.pdf`.
PDF pp. 87–94 are later TI.com addenda, **not** part of the 1996 datasheet —
ignored here.

**Cross-references:** the distilled SPRU056D User's Guide lives in
`../c5x_manual/` — cited as `../c5x_manual/<file>` where a claim touches it.
Do not conflate C51 with other C5x variants; where the datasheet speaks
family-generically, this file says so.

**Citation rule:** every load-bearing fact carries `(SPRS030A Table/Fig §, p.N)`.
`[UNVERIFIED]` marks a garbled extraction or an unresolvable reading — no
guess was made.

---

## 1. Device overview

The TMS320C5x is a 16-bit fixed-point DSP generation built on static CMOS,
architecturally descended from the TMS320C25, with an enhanced Harvard
architecture (separate program and data buses), on-chip peripherals, on-chip
memory, and a specialised instruction set (SPRS030A p. 1). Source code for
'C1x and 'C2x devices is upward-compatible with 'C5x (SPRS030A p. 1).

- **Performance:** up to 50 MIPS. Single-cycle instruction execution
  20/25/35/50 ns at 5 V; 25/40/50 ns at 3 V (SPRS030A p. 1).
  C51 specifically: 20 ns = 50 MIPS, 25 ns = 40 MIPS, 35 ns ≈ 28.6 MIPS,
  50 ns = 20 MIPS (cycle times from SPRS030A Table 1, p. 2; MIPS arithmetic
  is 1/cycle-time).
- **CPU core** (SPRS030A pp. 18, 20–21): 32-bit ALU/accumulator with
  scaling shifters (left shift 0–16 on data-bus input; post-scaling 0–7 on
  ACC output); single-cycle 16×16-bit multiply/add (signed 2's-complement,
  32-bit product in PREG, four product-shift modes in ST1); 8 auxiliary
  registers AR0–AR7 with a dedicated ARAU (auto-index ±1 or by INDX);
  parallel logic unit (PLU) for bit operations directly on data-memory
  locations without touching ACC; repeat instructions (RPT/RPTZ) and
  block-memory moves (BLDD/BLDP/BLPD, TBLR/TBLW); NORM instruction and
  TREG1-controlled shifts give floating-point support.
- **Addressable external space:** 224K × 16-bit maximum — 64K program,
  64K data, 64K I/O, 32K global (SPRS030A p. 1). See §5.
- **Wait states:** hardware (READY pin) or software wait-state generation
  (SPRS030A p. 1).
- **Power (family figures, 40 MHz clock):** 47 mA (2.35 mA/MIP) at 5 V;
  23 mA (1.15 mA/MIP) at 3 V; IDLE1 10 mA at 5 V; IDLE2 3 mA at 5 V;
  5 µA at 5 V with clocks off (IDLE2) (SPRS030A p. 1).
- **Test/emulation:** on-chip scan-based emulation logic, boundary scan,
  IEEE 1149.1 JTAG test-access port (SPRS030A p. 1).
- **Technology:** high-performance static CMOS (SPRS030A p. 1).

---

## 2. Variant comparison (SPRS030A Table 1, p. 2)

Table 1 is the datasheet's own comparison. DARAM is split into two
columns: 544 words data-only (B1 512 + B2 32) and 512 words data-or-program
(B0); total DARAM is 1056 words on **every** device (SPRS030A Table 1,
p. 2; §5 below). The column headings are partly garbled in the text
extraction; the split is confirmed by the memory text (SPRS030A p. 22)
and by `../c5x_manual/08-memory.md` §8.1.

| Device | DARAM data-only | DARAM data+prog | SARAM | ROM (prog) | Serial ports | Parallel I/O | Supply (V) | Cycle time (ns) | Package (pins) |
|---|---|---|---|---|---|---|---|---|---|
| TMS320C50 | 544 | 512 | 9K | 2K § | 2 | 64K | 5 | 50/35/25 | 132 |
| TMS320LC50 | 544 | 512 | 9K | 2K § | 2 | 64K | 3.3 | 50/40/25 | 132 |
| **TMS320C51** | **544** | **512** | **1K** | **8K §** | **2** | **64K** | **5** | **50/35/25/20** | **100/132** |
| **TMS320LC51** | **544** | **512** | **1K** | **8K §** | **2** | **64K** | **3.3** | **50/40/25** | **100/132** |
| TMS320C52 | 544 | 512 | – | 4K § | 1 ¶ | 64K | 5 | 50/35/25/20 | 100 |
| TMS320LC52 | 544 | 512 | – | 4K § | 1 ¶ | 64K | 3.3 | 50/40/25 | 100 |
| TMS320C53 | 544 | 512 | 3K | 16K § | 2 | 64K | 5 | 50/35/25 | 132 |
| TMS320LC53 | 544 | 512 | 3K | 16K § | 2 | 64K | 3.3 | 50/40/25 | 132 |
| TMS320C53S | 544 | 512 | 3K | 16K § | 2 ¶ | 64K | 5 | 50/35/25 | 100 |
| TMS320LC53S | 544 | 512 | 3K | 16K § | 2 ¶ | 64K | 3.3 | 50/40/25 | 100 |
| TMS320LC56 | 544 | 512 | 6K | 32K | 2 # | 64K | 3.3 | 35/25 | 100 |
| TMS320LC57 | 544 | 512 | 6K | 32K | 2 # | 64K + HPI ‖ | 3.3 | 35/25 | 128 |
| TMS320C57S | 544 | 512 | 6K | 2K § | 2 # | 64K + HPI ‖ | 5 | 50/35/25 | 144 |
| TMS320LC57S | 544 | 512 | 6K | 2K § | 2 # | 64K + HPI ‖ | 3.3 | 50/35 | 144 |

Footnotes (SPRS030A Table 1, p. 2): § = ROM boot loader available;
¶ = TDM serial port not available; # = includes auto-buffered serial port
(BSP) but TDM serial port not available; ‖ = HPI = host port interface.
† Sixteen of the 64K parallel I/O ports are memory-mapped (see §5).
"Pinouts for each package are device-specific" (SPRS030A p. 2).

**C51 row, exact:** 544 + 512 words DARAM, 1K SARAM, 8K ROM (§),
2 serial ports (standard SP + TDM — no ¶ footnote, so TDM present),
64K parallel I/O (no HPI), 5 V (LC51: 3.3 V), cycle times
50/35/25/20 ns (LC51: 50/40/25 ns — **no 20 ns grade**), packages
100-pin and 132-pin (SPRS030A Table 1, p. 2). C51 is the only 5 V device
with a 20 ns (50 MIPS) grade alongside C52 (SPRS030A Table 1, p. 2).

Family ROM/SARAM ranges on the front page agree: ROM 2K/4K/8K/16K/32K,
SARAM 1K/3K/6K/9K, DARAM "1K" (rounded — actually 1056 words)
(SPRS030A p. 1).

---

## 3. Packages and pinouts

### 3.1 Which packages C51 ships in

Five packaging options exist family-wide (SPRS030A p. 1): 100-pin QFP
(PJ), 100-pin TQFP (PZ), 128-pin TQFP (PBK), 132-pin QFP (PQ),
144-pin TQFP (PGE). **C51 ships in two of them only** (SPRS030A
Table 1, p. 2):

| Package | Suffix | Pins | C51? | Devices in this datasheet's pinout section |
|---|---|---|---|---|
| Thin quad flat pack | PZ | 100 | **Yes** | 'C51/'LC51, 'C52/'LC52, 'C53S/'LC53S, 'LC56 (SPRS030A pp. 9–11) |
| Quad flat pack | PQ | 132 | **Yes** | 'C50/'LC50, 'C51/'LC51, 'C53/'LC53 (SPRS030A pp. 3–5) |
| Quad flat pack | PJ | 100 | No — 'C52 only | 'C52/'LC52 (SPRS030A pp. 12–14) |
| Thin quad flat pack | PBK | 128 | No — 'LC57 only | 'LC57 (SPRS030A pp. 6–8) |
| Thin quad flat pack | PGE | 144 | No — 'C57S only | 'C57S/'LC57S (SPRS030A pp. 15–17) |

The manual agrees: PZ = 'C51/'C52/'C53S/'LC56, PQ ("132-pin bumpered
quad flat-pack", BQFP) = 'C50/'C51/'C53 (`../c5x_manual/appendix-a-pinouts.md`
§§A.2, A.4). Naming difference only: the datasheet calls PQ a plain
"132-pin Quad Flat Package" (SPRS030A p. 1); the manual calls it BQFP.

**Key package difference for C51:** the 132-pin PQ package has **IAQ**
(pin 1) and **IACK** (pin 112) signals; the 100-pin PZ package has
**neither** — IAQ/IACK do not appear in the PZ pin functions at all
(SPRS030A pp. 4–5 vs pp. 10–11). The block diagram notes that "signals
in shaded text are not available on 100-pin QFP packages"
(SPRS030A p. 19). Consequence for RE: in the PZ package there is no
instruction-acquisition or interrupt-acknowledge visibility on pins.
NC = no connect (reserved) (SPRS030A pp. 3, 9).

### 3.2 C51 pin table — PZ package (100-pin TQFP)

Pin numbers from SPRS030A Table 2 (device-specific pins, p. 9) and the
PZ pinout figure (p. 9), cross-checked against
`../c5x_manual/appendix-a-pinouts.md` Tables A–2/A–6 (identical assignments).
Types/functions from SPRS030A pp. 10–11. Legend: I = input, O = output,
Z = high impedance, S = supply.

| Signal | PZ pin(s) | Type | Function (one line) |
|---|---|---|---|
| A0–A15 | 52–61 (A0–A9), 67–72 (A10–A15) | I/O/Z | 16-bit external address bus, MSB A15 |
| D0–D15 | 28–35 (D7–D0), 17–24 (D15–D8) | I/O/Z | 16-bit external data bus, MSB D15 |
| PS, DS, IS | 79, 77, 78 | O/Z | Program / data / I/O space-select outputs |
| STRB | 81 | I/O/Z | Timing strobe, external cycles + external DMA |
| R/W | 80 | I/O/Z | Read/write select, external cycles + external DMA |
| RD, WE | 74, 75 | O/Z | Read / write strobes, external cycles |
| READY | 10 | I | External bus ready / wait-state control |
| BR | 82 | I/O/Z | Bus request; global-memory + external DMA arbitration |
| RS | 9 | I | Reset; initialises device, sets PC to zero |
| MP/MC | 16 | I | Microprocessor/microcomputer select; enables internal ROM |
| HOLD | 11 | I | Puts parallel bus in high-impedance after current cycle |
| HOLDA | 95 | O/Z | Hold acknowledge; bus in hold state |
| XF | 96 | O/Z | External flag output, set/cleared by software |
| BIO | 12 | I | I/O branch input; conditional branches |
| TOUT | 4 | O/Z | Timer output |
| INT1–INT4 | 41–44 | I | External interrupt inputs |
| NMI | 45 | I | Nonmaskable external interrupt |
| DR | 46 | I | Serial-port receive data |
| DX | 93 | O/Z | Serial-port transmit data (Hi-Z when not transmitting) |
| CLKR | 49 | I | Serial-port receive clock |
| CLKX | 6 | I/O/Z | Serial-port transmit clock, internal or external source |
| FSR | 48 | I | Serial-port receive frame sync |
| FSX | 91 | I/O/Z | Serial-port transmit frame sync, internal or external |
| TDR | 47 | I | TDM receive data |
| TDX | 94 | O/Z | TDM transmit data (Hi-Z when not transmitting) |
| TCLKR | 8 | I | TDM receive clock |
| TCLKX | 5 | I/O/Z | TDM transmit clock, internal or external source |
| TFSR/TADD | 7 | I/O/Z | TDM receive frame sync; in TDM mode, TADD address I/O |
| TFSX/TFRM | 92 | I | TDM transmit frame sync; in TDM mode becomes TFRM (see §8, contradiction C2 — datasheet type "I" vs manual "I/O/Z") |
| TDI | 63 | I | JTAG scan-data input |
| TDO | 87 | O/Z | JTAG scan-data output |
| TMS | 36 | I | JTAG mode select |
| TCK | 38 | I | JTAG clock |
| TRST | 13 | I | JTAG reset (with pulldown); disables TAP when low |
| EMU0 | 1 | I/O/Z | Emulation control 0, reserved for emulation |
| EMU1/OFF | 2 | I/O/Z | Emulation control 1; low puts outputs in Hi-Z |
| X1 | 85 | O | Oscillator output |
| X2/CLKIN | 84 | I | Clock/oscillator input |
| CLKIN2 | 83 | I | Clock input; PLL clock input for 'C50/'C51/'C52/'C53/'C53S (SPRS030A p. 11, Note 2) |
| CLKMD1, CLKMD2 | 66, 90 | I | Clock-mode select inputs (no CLKMD3 on C51) |
| CLKOUT1 | 97 | O/Z | Device system-clock output |
| VDDA / VSSA | 50, 73 / 51, 64, 65 | S | Supply / ground, address-bus output |
| VDDD / VSSD | 25, 37 / 26, 27, 39, 40 | S | Supply / ground, data-bus output |
| VDDC / VSSC | 86, 100 / 3, 76 | S | Supply / ground, control output |
| VDDI / VSSI | 62, 98, 99 / 14, 15, 88, 89 | S | Supply / ground, internal logic |

No NC pins on the C51 PZ pinout; every pin is assigned (SPRS030A
Table 2, p. 9; `../c5x_manual/appendix-a-pinouts.md` Table A–2).
Pins 5–8, 46–49, 83, 91–94 are the device-specific ones — on 'C52 they
are VSSI/ground, on 'C53S a second standard serial port, on 'LC56 the
BSP (SPRS030A Table 2, p. 9). **No BSP (B-) pins and no HPI pins exist
on C51 in PZ** (SPRS030A pp. 9–11).

### 3.3 C51 pin table — PQ package (132-pin QFP)

Pin numbers from the PQ pinout figure (SPRS030A p. 3), cross-checked
against `../c5x_manual/appendix-a-pinouts.md` Table A–4 (identical
assignments). Types/functions from SPRS030A pp. 4–5. Signals shared
with PZ have the same type/function; only pin numbers and the extra
signals differ.

| Signal | PQ pin(s) | Type | Function (note only where it differs from PZ) |
|---|---|---|---|
| A0–A15 | 55–64 (A0–A9), 72–77 (A10–A15) | I/O/Z | As PZ |
| D0–D15 | 23–30 (D7–D0), 6–13 (D15–D8) | I/O/Z | As PZ |
| PS, DS, IS | 91, 89, 90 | O/Z | As PZ |
| STRB | 93 | I/O/Z | As PZ |
| R/W | 92 | I/O/Z | As PZ |
| RD, WE | 82, 83 | O/Z | As PZ |
| READY | 128 | I | As PZ |
| BR | 94 | I/O/Z | As PZ |
| RS | 127 | I | As PZ |
| MP/MC | 5 | I | As PZ |
| HOLD | 129 | I | As PZ |
| HOLDA | 108 | O/Z | As PZ |
| XF | 109 | O/Z | As PZ |
| BIO | 130 | I | As PZ |
| TOUT | 122 | O/Z | As PZ |
| IAQ | 1 | O/Z | **PQ only.** Instruction-acquisition signal |
| IACK | 112 | O/Z | **PQ only.** Interrupt-acknowledge signal |
| INT1–INT4 | 38–41 | I | As PZ |
| NMI | 42 | I | As PZ |
| DR / DX | 43 / 106 | I / O/Z | As PZ |
| CLKR / CLKX | 46 / 124 | I / I/O/Z | As PZ |
| FSR / FSX | 45 / 104 | I / I/O/Z | As PZ |
| TDR / TDX | 44 / 107 | I / O/Z | As PZ |
| TCLKR / TCLKX | 126 / 123 | I / I/O/Z | As PZ |
| TFSR/TADD | 125 | I/O/Z | As PZ |
| TFSX/TFRM | 105 | I | As PZ (same type-"I" caveat as §3.2) |
| TDI / TDO / TMS / TCK / TRST | 67 / 100 / 31 / 34 / 2 | I / O/Z / I / I / I | As PZ |
| EMU0 / EMU1/OFF | 118 / 119 | I/O/Z | As PZ |
| X1 / X2/CLKIN / CLKIN2 | 97 / 96 / 95 | O / I / I | As PZ |
| CLKMD1 / CLKMD2 | 71 / 103 | I | As PZ (no CLKMD3) |
| CLKOUT1 | 110 | O/Z | As PZ |
| VDDA / VSSA | 47, 48, 80, 81 / 53, 54, 68, 69 | S | Supply / ground, address bus |
| VDDD / VSSD | 14, 15, 32, 33 / 20, 21, 35, 36 | S | Supply / ground, data bus |
| VDDC / VSSC | 98, 99, 131, 132 / 86, 87, 120, 121 | S | Supply / ground, control |
| VDDI / VSSI | 65, 66, 113, 114 / 3, 4, 101, 102 | S | Supply / ground, internal logic |
| NC (reserved) | 16, 17, 18, 19, 22, 37, 49, 50, 51, 52, 70, 78, 79, 84, 85, 88, 111, 115, 116, 117 | – | No connect (SPRS030A p. 3, note) |

---

## 4. Signal descriptions (grouped)

Condensed from the pin-function tables (SPRS030A pp. 4–5 for PQ,
pp. 10–11 for PZ). Type legend as in §3.2. Functions are identical
across PQ/PZ except where noted.

### 4.1 Parallel bus

- **A0–A15 (I/O/Z):** 16-bit external address bus, MSB A15.
  Inputs during external DMA access of on-chip RAM (manual cross-ref:
  `../c5x_manual/08-memory.md` §8.6).
- **D0–D15 (I/O/Z):** 16-bit external data bus, MSB D15.
- **PS, DS, IS (O/Z):** program / data / I-O space-select outputs.
- **STRB (I/O/Z):** timing strobe for external cycles and external DMA.
- **R/W (I/O/Z):** read/write select for external cycles and external DMA.
- **RD, WE (O/Z):** read and write strobes for external cycles.
- **READY (I):** external bus ready / wait-state control input.
- **BR (I/O/Z):** bus request; arbitrates global memory and external DMA
  (SPRS030A pp. 4, 10).

### 4.2 System / control signals

- **RS (I):** reset; initialises device, sets PC to zero (SPRS030A pp. 4, 10).
- **MP/MC (I):** microprocessor/microcomputer mode select; enables
  internal ROM (SPRS030A pp. 4, 10). See §5.3.
- **HOLD (I) / HOLDA (O/Z):** hold request / hold acknowledge; HOLD puts
  the parallel bus in high-impedance after the current cycle
  (SPRS030A pp. 4, 10).
- **XF (O/Z):** external flag output, set/cleared through software
  (SPRS030A pp. 4, 10).
- **BIO (I):** I/O branch input; implements conditional branches
  (SPRS030A pp. 4, 10).
- **TOUT (O/Z):** timer output (SPRS030A pp. 4, 10).
- **IAQ (O/Z, PQ only):** instruction-acquisition signal (SPRS030A p. 4).
- **IACK (O/Z, PQ only):** interrupt-acknowledge signal (SPRS030A p. 4).
- **INT1–INT4 (I):** external interrupt inputs (SPRS030A pp. 4, 10).
- **NMI (I):** nonmaskable external interrupt (SPRS030A pp. 4, 10).

### 4.3 Serial-port signals (standard full-duplex SP)

- **DR (I):** receive data. **DX (O/Z):** transmit data, Hi-Z when not
  transmitting. **CLKR (I):** receive clock. **CLKX (I/O/Z):** transmit
  clock, internal or external source. **FSR (I):** receive frame sync.
  **FSX (I/O/Z):** transmit frame sync, internal or external source
  (SPRS030A pp. 4, 10). Register-level detail is in
  `../c5x_manual/09b-peripherals-serial-bsp-tdm-hpi.md` §1.

### 4.4 TDM serial-port signals

- **TDR (I) / TDX (O/Z):** TDM receive / transmit data (TDX Hi-Z when not
  transmitting). **TCLKR (I) / TCLKX (I/O/Z):** TDM receive / transmit
  clocks. **TFSR/TADD (I/O/Z):** TDM receive frame sync; in TDM mode
  used to output/input the port address. **TFSX/TFRM (I per this
  datasheet):** TDM transmit frame sync; in TDM mode becomes TFRM, the
  TDM frame sync (SPRS030A pp. 4, 11). See §8, contradiction C2, on the
  listed direction of TFSX/TFRM.
- TDM details (8 channels, addressing, timing) are in
  `../c5x_manual/09b-peripherals-serial-bsp-tdm-hpi.md` §3, not in pp. 1–29.

### 4.5 Clock

- **X1 (O):** oscillator output. **X2/CLKIN (I):** clock/oscillator input.
  **CLKIN2 (I):** clock input; PLL clock input for 'C50/'C51/'C52/'C53/
  'C53S (SPRS030A pp. 5, 11). **CLKMD1, CLKMD2 (I):** clock-mode select
  inputs. **CLKOUT1 (O/Z):** device system-clock output (SPRS030A pp. 5, 11).
- **No CLKMD3 on C51.** CLKMD3 appears only on 'LC56 (PZ pin 83 replaces
  CLKIN2 — SPRS030A p. 11, Note 2) and on 'LC57/'C57S. The per-device
  PLL multiplier table (×1/×2/×3/×4/×5/×9, SPRS030A p. 1) is **not**
  in pp. 1–29; the manual gives C51 as multiply-by-1 only — see §6.
- The functional block diagram (SPRS030A p. 19) shows CLKMD1/CLKMD2,
  X1, X2/CLKIN, CLKIN2/CLKMD3 (shared pin position) and CLKOUT1.

### 4.6 Power

Eight supply/ground pairs, split by load domain (SPRS030A pp. 5, 11):
VDDA/VSSA = address-bus output; VDDD/VSSD = data-bus output;
VDDC/VSSC = control output; VDDI/VSSI = internal logic.
C51 is the 5 V device; LC51 is 3.3 V (SPRS030A Table 1, p. 2).
No voltage numbers (absolute maxima, recommended operating conditions)
are in pp. 1–29 — those are later-datasheet material for another worker.

### 4.7 JTAG / emulation

- **TDI (I), TDO (O/Z), TMS (I), TCK (I):** IEEE 1149.1 TAP scan data
  in/out, mode select, clock (SPRS030A pp. 5, 11).
- **TRST (I):** TAP reset, with pulldown resistor; disables TAP when low
  (SPRS030A pp. 5, 11).
- **EMU0 (I/O/Z):** emulation control 0, reserved for emulation use.
  **EMU1/OFF (I/O/Z):** emulation control 1; puts outputs in
  high-impedance state when low (SPRS030A pp. 5, 11).

---

## 5. Memory map (C51)

### 5.1 Spaces

Three separate address spaces — program, data, I/O — each 64K 16-bit
words (SPRS030A p. 22). Within data space, the top 256 to 32K words can
be defined as external global memory in powers of two, per the global
memory allocation register (GREG); access is arbitrated with BR
(SPRS030A p. 22). First 96 data-memory locations (0000h–005Fh) are
allocated to memory-mapped registers (CPU, serial port, timer, software
wait-state generators); the first 16 I/O port locations are mapped into
this data-memory space, accessible as data memory with single-word
instructions or as I/O with two-word instructions (full 64K I/O space)
(SPRS030A p. 22). Detail: `../c5x_manual/08-memory.md` §§8.3–8.5.

### 5.2 C51 on-chip memory — verified against this datasheet

| Block | Size | Addresses | Notes |
|---|---|---|---|
| ROM (maskable) | 8K words | Program 0000h–1FFFh | Lowest block of program memory when enabled (SPRS030A Table 1, p. 2; Fig. 2, p. 24) |
| SARAM | 1K words, **one 1K block** | Data 0800h–0BFFh (OVLY=1); program 2000h–23FFh (RAM=1); or both | (SPRS030A Table 4, p. 22; Fig. 2, p. 24) |
| DARAM B0 | 512 words | Data 0100h–02FFh (CNF=0); program FE00h–FFFFh (CNF=1) | Configurable data/program (SPRS030A pp. 22–23; Fig. 2, p. 24) |
| DARAM B1 | 512 words | Data 0300h–04FFh | Data only (SPRS030A pp. 22–23; Fig. 2, p. 24) |
| DARAM B2 | 32 words | Data 0060h–007Fh | Data only, scratch-pad (SPRS030A pp. 22–23; Fig. 2, p. 24) |
| **Total DARAM** | **1056 words** | — | 512+512+32 (SPRS030A Table 1, p. 2: 544+512) |

**Prior-work sizes confirmed, not corrected:** 1056 words DARAM +
1K SARAM + 8K ROM matches `../c5x_manual/08-memory.md` §8.1 exactly
(same addresses). SARAM structure: it is made of 2K-word independent
blocks, each allowing one CPU access per cycle; if total SARAM is not a
multiple of 2K, one block is smaller — C51 has a single 1K block
(SPRS030A p. 22, Table 4). DARAM allows a read and a write in the same
cycle without SARAM's address restrictions; together with the parallel
architecture the device can perform three concurrent memory accesses in
one machine cycle (SPRS030A pp. 22–23). On-chip memory runs at full
speed with no wait states; READY interfaces slower external memory
(SPRS030A p. 23).

C51 program map (SPRS030A Fig. 2, p. 24), MP/MC = 1 (microprocessor)
vs MP/MC = 0 (microcomputer): interrupts/reserved 0000h–003Fh;
on-chip ROM 0040h–1FFFh (MC mode) vs external (MP mode); on-chip
SARAM 2000h–23FFh when RAM=1, else external; external 2400h–FDFFh;
DARAM B0 FE00h–FFFFh when CNF=1, else external. Data map (same figure):
memory-mapped registers 0000h–005Fh; DARAM B2 0060h–007Fh; reserved
0080h–00FFh; DARAM B0 0100h–02FFh (CNF=0) / reserved (CNF=1);
DARAM B1 0300h–04FFh; reserved 0500h–07FFh; SARAM 0800h–0BFFh when
OVLY=1, else external; external 0C00h–FFFFh. (SPRS030A Fig. 2, p. 24.)

### 5.3 MP/MC and ROM enable

The mask-programmable ROM is in program memory space, occupying the
lowest block when enabled. It is enabled/disabled by the MP/MC control
input at reset, or by the MP/MC bit in the PMST status register after
reset. When disabled, those addresses are external program memory
(SPRS030A p. 22). MP/MC low = microcomputer mode (internal ROM mapped
in); high = microprocessor mode (all program memory external)
(SPRS030A Fig. 2, p. 24; pin description pp. 4, 10). The MP/MC pin is
sampled only at reset — that detail is in the manual
(`../c5x_manual/08-memory.md` §8.2.1), not stated on pp. 1–29.

### 5.4 Boot loader and reset behaviour (as stated in this datasheet)

- **Boot loader:** "An optional boot loader is available in the device's
  on-chip ROM. This boot loader can be used to transfer a program
  automatically from data memory or the serial port to anywhere in
  program memory. In data memory, the program can be located on any
  1K-word boundary and can be in either byte-wide or 16-bit word format.
  Once the code is transferred, the boot loader releases control to the
  program for execution." (SPRS030A p. 22, verbatim substance.)
  Table 1 marks the C51 8K ROM with § = "ROM boot loader available"
  (SPRS030A Table 1, p. 2). **This conflicts with the manual's "C51: no
  boot ROM" — see §8, contradiction C1.** Do not assume the Courier
  C51 boots from ROM on the basis of either document alone.
- **Reset:** RS initialises the device and sets PC to zero (SPRS030A
  pp. 4, 10). Interrupt vectors are normally at program address 0 and
  can be remapped to the beginning of any 2K-word page by modifying
  IPTR in PMST (SPRS030A p. 29). All vector locations are on two-word
  boundaries to accommodate branch instructions (SPRS030A p. 29).
  Vector addresses / priorities / the reset-vector-cannot-be-remapped
  rule are in `../c5x_manual/08-memory.md` §8.2.2, not in pp. 1–29.
- **ROM security option:** a mask-programmable option provides security
  for on-chip ROM contents — when the internal option bit is
  programmed, no externally-originating instruction can access the
  on-chip ROM (SPRS030A p. 22). The manual's program-memory-protection
  rules (§8.2.4) are the fuller treatment; see
  `../c5x_manual/08-memory.md` §8.2.4.

### 5.5 Interrupts, stack, power-down (SPRS030A p. 29)

- Four general-purpose external interrupts INT1–INT4, plus RS and NMI.
  Internal interrupts from the serial port (RINT, XINT), timer (TINT),
  and software-interrupt instructions (TRAP, INTR, NMI). Priority: RS
  highest, then NMI, INT4 lowest. Any interrupt except RS/NMI is
  individually maskable via IMR and set/cleared/tested via IFR
  (SPRS030A p. 29). (Note: TDM interrupts TRNT/TXNT are not mentioned
  on p. 29; they are in the manual, `../c5x_manual/08-memory.md` §8.2.2.)
- Interrupts during a multicycle instruction are deferred until the
  instruction completes (including RPT-repeated instructions and
  wait-stated instructions) (SPRS030A p. 29).
- Eight-level hardware PC stack (interrupts/subroutines nestable to
  eight levels); eleven key CPU registers have a single-level
  shadow register saved on interrupt entry and restored by RETE/RETI
  (SPRS030A p. 29).
- **Power-down:** IDLE halts CPU activity, CLKOUT1 stays active,
  peripherals continue and can wake the CPU; an IDLE-initiated
  power-down ends on receipt of an interrupt. IDLE2 shuts down the
  core CPU and all on-chip peripherals; it ends when any external
  interrupt pin (RS, NMI, INT1–INT4) is active for at least five
  machine cycles. HOLD-low also initiates a power-down mode in which
  on-chip peripherals continue to operate; it ends when HOLD goes
  inactive. Internal contents are maintained in all power-down modes
  (SPRS030A p. 29).
- **Bus-keeper circuitry: LC56/'C57S/'LC57 only — not C51**
  (SPRS030A p. 29).

---

## 6. Peripherals present / absent on C51 (per THIS datasheet)

| Peripheral | C51? | Datasheet evidence (pp. 1–29) |
|---|---|---|
| Full-duplex synchronous serial port (SP) | **Yes (1)** | Front-page feature list (p. 1); Table 1 serial = 2 (p. 2); SP pins DR/DX/CLKR/CLKX/FSR/FSX in PQ and PZ pin functions (pp. 4, 10) |
| TDM serial port | **Yes (1)** | Front-page feature list (p. 1); Table 1: C51 has no ¶ footnote ("TDM not available") (p. 2); TDM pins TDR/TDX/TCLKR/TCLKX/TFSR/TADD/TFSX/TFRM in both C51 packages (pp. 4, 10–11); PZ Table 2 C51 column (p. 9). The two serial ports are 1× SP + 1× TDM |
| Buffered serial port (BSP) | **No** | BSP pins (BDR/BDX/BCLKR/BCLKX/BFSR/BFSX) in the PZ pin functions carry Note 1: "'LC56 devices only" (p. 10); C51 column of Table 2 has TDM pins at those positions, not B-pins (p. 9); no B-pins in the PQ functions (pp. 4–5) |
| Host port interface (HPI) | **No** | HPI pins (HCNTL0/1, HINT, HDS1/2, HR/W, HAS, HRDY, HCS, HBIL, HD0–HD7) appear only in the PBK ('LC57, pp. 6–8) and PGE ('C57S, pp. 15–17) sections; absent from PQ/PZ C51 sections; Table 1 parallel-I/O column for C51 is plain "64K" with no ‖ (HPI) footnote (p. 2) |
| On-chip timer | **Yes** | Front-page feature list (p. 1); TOUT pin in both C51 packages (pp. 4, 10); timer registers in block diagram (p. 19: TCR/PRD/TIM) |
| PLL clock options | **Family yes; C51 multiplier not tabulated in pp. 1–29** | Front page: "Multiple PLL Clocking Options (×1, ×2, ×3, ×4, ×5, ×9 Depending on Device)" (p. 1); CLKIN2 is the PLL clock input for 'C50/'C51/'C52/'C53/'C53S (p. 11). The per-device multiplier table is later in the datasheet (outside pp. 1–29). Manual cross-ref: `../c5x_manual/appendix-a-pinouts.md` Table A–13 gives C51 as PLL multiply-by-1 only (CLKMD1=1, CLKMD2=0, CLKIN2 input; CLKMD1=0/CLKMD2=0 = PLL disabled, divide-by-2 from X2/CLKIN; CLKMD1=1/CLKMD2=1 = internal oscillator, divide-by-2) — **manual, not this datasheet; verify against the datasheet clock section when that worker reports** |

**Verification status of the three claims from the task:** TDM-yes —
confirmed from this datasheet (Table 1 + TDM pins, above). BSP-no —
confirmed (PZ Note 1, Table 2). HPI-no — confirmed (HPI pins only on
PBK/PGE; Table 1 ‖ footnote absent for C51). All three agree with
`../c5x_manual/09b-peripherals-serial-bsp-tdm-hpi.md` §0 (SP yes, TDM yes,
BSP no, HPI no).

---

## 7. Functional block diagram notes (SPRS030A pp. 18–19)

- Architecture text (p. 18): Harvard, two buses, coefficients in program
  memory readable into RAM (no separate coefficient ROM), immediate
  instructions, computed-value subroutines, single-cycle MAC with
  data-move, 8 ARs + ARAU, PLU, fast I/O, floating-point support,
  block transfers, slow-device interfacing, multiprocessing.
- Block diagram (p. 19) lists per-device ROM sizes ('C50 2K, 'C51 8K,
  'C52 4K, 'C53 16K, 'C56 32K, 'C57 32K) and SARAM sizes ('C50 9K,
  'C51 1K, 'C53 3K, 'C56 6K, 'C57 6K), DARAM B0/B1 512×16 and B2 32×16.
  Serial Port 1 (SPC/DXR/DRR), Serial Port 2 (SPC/DXR/DRR, DX2/FSX2/
  DR2/FSR2/CLKX2/CLKR2), TDM (TSPC/TDXR/TRCV/TCSR/TRTA/TRAD), BSP
  (AXR/BKX/ARR/BKR) and HPI blocks are all drawn with the footnote
  "† Not available on all devices (see Table 1)" — the diagram alone
  does not say which device has which; Table 1 (§2) governs.
- Symbol table (Table 3, p. 18) defines ABU, BSP, HPI, TDM, TSPC,
  TRTA, TRAD, TCSR, AXR/BKX/ARR/BKR, HPIC/HPIA, etc.

---

## 8. Contradictions vs SPRU056D (both directions)

Checked against `../c5x_manual/08-memory.md`,
`../c5x_manual/09b-peripherals-serial-bsp-tdm-hpi.md`, and
`../c5x_manual/appendix-a-pinouts.md`.

- **C1 — Boot loader on C51 (unresolved, matters for the Courier RE).**
  Datasheet: Table 1 marks C51's 8K ROM with § = "ROM boot loader
  available" (SPRS030A Table 1, p. 2), and p. 22 says "an optional boot
  loader is available in the device's on-chip ROM" with serial/data-memory
  transfer. Manual: `../c5x_manual/08-memory.md` §8.1 lists C51 as "8K
  maskable ROM … No boot ROM", and §8.8 describes the boot loader as
  living in the (2K) boot ROM of boot-ROM devices. Possible
  reconciliation (not established): "boot loader available" in the
  datasheet may mean a mask-ROM option rather than a standard fitted
  boot ROM, vs the manual's "no (dedicated) boot ROM". **Do not rely on
  either reading until the SPRU056D §8.8 device list / Appendix G
  part-numbering is checked.** Flagged for adjudication.
- **C2 — TFSX/TFRM direction.** Datasheet pin-function tables list
  TFSX/TFRM as type **I** (input) in both the PQ (SPRS030A p. 4) and PZ
  (SPRS030A p. 11) tables, while FSX is I/O/Z in the same tables.
  Manual: `../c5x_manual/appendix-a-pinouts.md` Table A–15 lists
  FSX/FSX1/FSX2/TFSX/TFRM as **I/O/Z**, with TXM selecting output;
  §9.9 (manual) has a device generate TFRM when TXM=1
  (`../c5x_manual/09b-peripherals-serial-bsp-tdm-hpi.md` §3.2). The
  datasheet's "I" is likely incomplete (TFSX as input is the reset
  default), but as printed it contradicts the manual. The TDM
  transmit-frame-sync source question should be settled from the
  datasheet's TDM/timing sections (outside pp. 1–29), not from p. 4/11.
- **C3 — BFSR direction (not a C51 signal; affects trust in the PZ
  type column).** Datasheet PZ table lists BFSR as type **I**, "BSP
  receive frame-synchronization input" (SPRS030A p. 10, 'LC56 only).
  Manual: `../c5x_manual/appendix-a-pinouts.md` Table A–16 lists BFSR as
  type **O**, active high upon reset. Same class of discrepancy as C2:
  the datasheet's PZ/PQ type column for frame-sync pins does not match
  the manual. C51 has no BFSR pin, so this does not affect C51 directly.
- **C4 — PQ package naming (trivial).** Datasheet: "132-Pin Quad Flat
  Package (PQ)" (SPRS030A p. 1). Manual: "132-pin bumpered quad
  flat-pack (BQFP)" (`../c5x_manual/appendix-a-pinouts.md` §A.0). Same
  package, different name.
- **Agreements confirmed (no contradiction):** C51 memory sizes and
  addresses (§5.2) identical in both documents; TDM-yes / BSP-no /
  HPI-no (§6) identical; PZ package lacks IAQ/IACK, PQ has them,
  identical; CLKMD3 absent on C51, CLKIN2 is the C51 PLL input,
  identical; MP/MC semantics, IPTR 2K-page vector remap, 8-level stack,
  shadow registers, IDLE/IDLE2/HOLD power-down behaviour — all
  consistent between SPRS030A pp. 22, 29 and the manual.
- **Extraction note (not a contradiction):** the front-page "1K
  Dual-Access RAM" (SPRS030A p. 1) is a rounding of the actual 1056
  words (544+512, Table 1, p. 2); the manual's 1056-word figure agrees.

---

## 9. Not in pp. 1–29 (left for other workers)

- Electrical characteristics: absolute maxima, recommended operating
  conditions, supply voltages/tolerances, input/output levels, currents
  beyond the front-page typicals, timing diagrams and switching
  characteristics, PLL multiplier table per device, clock-mode tables.
- Timer register detail, serial-port/TDM register detail, wait-state
  generator registers, interrupt vector table (addresses/priorities),
  boot-loader protocol detail (selection word, serial/parallel modes).
- Mechanical package drawings / thermal data.
- Anything in PDF pp. 87–94 (later TI.com addenda) — excluded by task.

---

