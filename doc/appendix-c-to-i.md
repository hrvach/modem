# Appendices C–I (SPRU056D)

Source: SPRU056D, *TMS320C5x User's Guide*, June 1998, Appendices C–I,
PDF pp.650–744 (printed pp.C-1–C-19, D-1–D-13, E-1–E-3, F-1–F-4, G-1–G-9,
H-1–H-27, I-1–I-20). Only authority: `~/workspace/user/files/spru056d.pdf`.
Every factual claim below cites appendix/section + table/figure number + both
page numbers (PDF index page and printed page).

Transcription policy for this file (per appendix, stated up front):
- **C — transcribed in full** for the instruction-mapping tables C–1–C–8;
  prose sections condensed to the operative rules.
- **D — condensed to a rules list**, except Tables D–1/D–2 and the §D.8
  timing assumptions/cases, which are transcribed in full.
- **E — transcribed in full** (small appendix: EPROM list, socket part
  numbers, crystal table/specs/vendors).
- **F — process summary** (flow, submission formats, disclaimer/release
  wording); the two quoted statements are verbatim.
- **G — condensed**, except Table G–1 (tool part numbers, transcribed in
  full) and the nomenclature legends (transcribed). **1998 ordering data —
  part numbers, phone numbers, and addresses are historical; do not order
  from them without re-verification.**
- **H — all 352 glossary entries included** as `term: definition` lines
  (including 138 "See …" cross-references), grouped by letter.
- **I — all 38 change entries transcribed** (change statement + new value
  where stated); the figures/tables reprinted in Appendix I are NOT
  re-reprinted here — see the note under §I.

---

# Appendix C — System Migration (’C2x → ’C5x)

[App C intro, PDF p.650 (printed p.C-1)] Information necessary to upgrade a
’C2x system into a ’C5x system: programming differences and hardware/timing
differences between the two generations. Note: the ’C50, ’C51, and ’C53 have
the same features with the exception of memory map, so in this appendix any
reference to ’C5x applies to ’C50, ’C51, and ’C53, unless otherwise stated.

| Section | Content | PDF p. | Printed p. |
|---|---|---|---|
| C.1 | Package and Pin Layout | 651–656 | C-2–C-7 |
| C.2 | Timing | 657–659 | C-8–C-10 |
| C.3 | On-Chip Peripheral Interfacing | 660 | C-11 |
| C.4 | ’C2x-to-’C5x Instruction Set | 661–668 | C-12–C-19 |

## C.1 Package and Pin Layout [PDF pp.651–656 (printed pp.C-2–C-7)]

- The ’C25 is available in a 68-pin ceramic pin grid array (CPGA, Fig. C–1)
  and a 68-pin plastic leaded chip carrier (PLCC, Fig. C–2). ’C5x packages
  are in Appendix A.
- Thermal resistance (Fig. C–1, CPGA): RθJA (junction-to-free-air) 36 °C/W
  max; RθJC (junction-to-case) 6 °C/W max. (Fig. C–2, PLCC): RθJA 46 °C/W
  max; RθJC 11 °C/W max. All linear dimensions in millimetres (inches in
  parentheses).
- Upgrading a ’C25 to a ’C50/’C51/’C53 needs minimal layout modification:
  the ’C5x signals are on the same side (except the CLKR and A0 pins) and in
  the same order (except the X1 and X2/CLKIN pins) as the ’C25 (Fig. C–3,
  pin-to-pin relationship, devices not drawn to scale). Power (VDD) and
  ground (VSS) are symmetrically positioned on the ’C5x so that, with the OFF
  signal, the device is not damaged by insertion in the wrong orientation.
  The ’C5x has more power and ground pins for higher performance and noise
  immunity.
- Three ’C25 signals are NOT present on the ’C5x: **CLKOUT2, MSC, SYNC**.
  No SYNC is needed because the ’C5x operates with a divide-by-two clock
  and can be synchronized with reset; with only two phases there are no
  external timings tied to the ’C25's CLKOUT2.
- Signals that are now bidirectional on the ’C5x (for external DMA of the
  on-chip single-access RAM block): address lines A0–A15; memory access
  strobe STRB; read/write R/W; bus request BR.
- CLKX: on the ’C5x it can be configured as an output at one-fourth the
  machine clock rate (input by reset); the ’C25 CLKX pin is always an input.
- Clocking (Fig. C–4): ’C25 uses a four-phase clock; machine rate is
  one-fourth the CLKIN rate; CLKOUT1 and CLKOUT2 run at the machine rate,
  90° out of phase. ’C5x uses a two-phase clock; machine rate is one-half
  the CLKIN rate; plus a divide-by-one clock input so the machine rate can
  equal the CLKIN rate. CLKOUT1 runs at the machine rate.
- MP/MC pin: on the ’C5x it is sampled only while RS is low; changes are
  ignored while RS is high; the mode can be changed during execution via
  the MP/MC bit in PMST. On the ’C25, any change on MP/MC affects operation
  regardless of RS.
- IACK (Fig. C–5): the ’C5x IACK goes low only on the first machine cycle
  of the fetch of the first word of the interrupt vector. The ’C25 IACK goes
  low on each wait-state cycle as well as the first machine cycle, but is
  valid only during CLKOUT1 low (during CLKOUT1 high it has a specific
  meaning for emulator/test operations).
- Additional ’C5x functions/pins not on the ’C25: TDM serial port
  (TCLKR, TCLKX, TDR, TDX, TADD, TFRM); emulation interface (EMU0,
  EMU1/OFF, IAQ, TCK, TDI, TDO, TMS, TRST); timer borrow (TOUT);
  divide-by-one clock (CLKIN2, CLKMD1, CLKMD2); fourth external interrupt
  (INT4); nonmaskable interrupt (NMI); read enable (RD); write enable (WE).
- The ’C5x package also includes 12 additional power and 13 additional
  ground pins, and 20 pins are reserved for future ’C5x spinoff devices.

## C.2 Timing [PDF pp.657–659 (printed pp.C-8–C-10)]

Key differences:
- The ’C5x can operate at two to three times the speed of a ’C2x.
- The ’C2x has a three-deep pipeline; the ’C5x a four-deep pipeline.
- The ’C5x external memory interface is faster and includes enhancements.
- Some compatible operations execute in a different number of machine cycles.

### C.2.1 Device clock speed
- ’C2x: divide-by-four clocking. ’C5x: divide-by-two clocking. At the same
  40-MHz CLKIN, a ’C2x executes machine cycles in 100 ns, a ’C5x in 50 ns.
- ’C2x timing values are specified as quarter-phase (Q) + N ns (see the
  TMS320 Second-Generation DSP Data Sheet); ’C5x timing values are defined
  in half-phases (H).

### C.2.2 Pipeline
- PC discontinuity (branch, call, return, interrupt, etc.) takes 4 cycles
  on the ’C5x vs 3 on the ’C2x. The ’C5x also has delayed instructions that
  take only 2 cycles.

### C.2.3 External memory interfacing
- Same signals as the ’C2x; the ’C5x runs at twice the instruction rate at
  the same input clock. The ’C5x software wait-state generators compensate:
  a ’C5x with one software wait state has similar memory timing to a ’C2x
  with no wait states. External writes require two cycles on the ’C5x.
  Exact signal timing differs due to the more advanced process.
- Two additional memory interface signals reduce external interfacing: RD
  can drive directly the output-enable pin of another device; WE can connect
  directly to the write-enable pin — no need to gate STRB and R/W to
  generate the equivalents.

### C.2.4 Execution cycle times
- IN and OUT are now two-word instructions on the ’C5x; same cycle count as
  the ’C2x, but the assembler generates a two-word instruction. Two words
  because the ’C5x addresses 65,536 I/O ports (’C2x: 16). In RPT mode the
  ’C5x IN/OUT behave differently — see Chapter 6. Sixteen of the ’C5x I/O
  ports are addressable in data memory space, so any instruction with
  data-memory addressing can read/write an I/O port directly (e.g. read an
  external A/D converter straight into the ALU via an I/O port).
- The three serial-port mode bits are modified with two-cycle/two-word
  instructions on the ’C5x, but any or all three bits can be modified with
  one instruction without affecting other bits in the register — with the
  PLU instructions.
- NORM modifies the auxiliary register (AR) on the execute (fourth) phase
  of the pipeline, while ARAU operations occur on the decode (second)
  phase. The two instructions following a NORM should not use the same AR
  for an address. If the two instructions following NORM change the ARP,
  the NORM update of the AR is executed on the new ARP, not the old one
  (see Chapter 6 NORM description). The assembler can test for this and
  automatically compensate by adding NOPs; the modification goes into the
  listing and object files, not the source.
- Unlike the ’C2x, the ARs are also accessible in the data address space on
  the ’C5x, so they can be loaded with CALU instructions for
  advanced-addressing modes — but with the same caution as NORM, because
  CALU operations write to the ARs on the execute phase; the assembler can
  flag these conflicts for resolution.

## C.3 On-Chip Peripheral Interfacing [PDF p.660 (printed p.C-11)]

- The ’C5x has more peripherals; many are enhancements of ’C2x peripherals.
  The ’C2x has three peripheral circuits: serial port, timer, 16 I/O ports.
  The ’C5x adds software wait states and a divide-by-one clock.
- Serial port: CLKX can be input or output on the ’C5x (always input on the
  ’C2x); input upon reset for ’C2x compatibility. Serial port status bits
  are now in a dedicated memory-mapped register (SPC); modes are no longer
  controlled via ST1, so serial port modes changed with LST1 no longer work
  — set/reset mode bits via SPC. DXR and DRR moved in the memory map from
  locations 1 and 0 to 33 and 32 respectively (see §9.7, p.9-23).
- Timer: enhanced with a divide-down factor of 1 to 17, stoppable/resettable
  via software, controlled via TCR. On reset the divide-down factor is 1 and
  the timer is enabled (’C2x compatible). TIM and PRD moved from locations
  2 and 3 to locations 36 and 37 respectively (see §9.3, p.9-9).
- I/O ports: the 16 I/O ports are addressable in data memory space; any
  instruction that can address data memory can address the I/O ports,
  including bit operations via the PLU. I/O space can grow from 16 to
  65,536 ports; no extra decode circuitry is needed if only 16 ports are
  used (see §8.5 p.8-22, §9.6 p.9-22).
- Software wait-state generators: mapped on 16K-word page sizes in program
  and data memory spaces; I/O wait-state generators mappable on 2-word or
  8K-word boundaries; programmable for 0, 1, 2, 3, 4, or 7 wait states,
  eliminating off-chip interfacing circuitry. External-access wait states
  can be extended further via READY (see §9.4, p.9-13).

## C.4 ’C2x-to-’C5x Instruction Set [PDF pp.661–668 (printed pp.C-12–C-19)]

The ’C5x instruction set is a superset of the ’C2x instruction set; the ’C2x
instruction set is upward source-code compatible — all ’C2x instruction
features and code written for the ’C2x can be reassembled to run on the ’C5x
(Chapter 6 for details).

### C.4.1 Overview
- New ’C5x instructions provide an advanced addressing scheme and exercise
  the new CPU enhancements. Several different instructions are combined into
  single new instructions with additional operand formats (Table C–1).
- IDLE: on the ’C2x, IDLE automatically enables interrupts globally (saving
  the EINT instruction); on interrupt, the vector executes and operation
  resumes. On the ’C5x, IDLE does NOT automatically enable interrupts
  globally: if interrupts are not globally enabled (INTM = 1), the CPU
  resumes at the instruction following IDLE without taking the interrupt
  trap; if globally enabled (INTM = 0), it operates like the ’C2x. A second
  low-power mode, IDLE2, works like IDLE except the CPU resumes only after
  an external interrupt (see Chapter 6).
- Repeat counter: 16 bits on the ’C5x (8 bits on the ’C2x); RPT loaded from
  RAM supports repeat counts up to 65,536; the assembler also allows a
  16-bit immediate repeat count — but RPT with long immediate addressing is
  a two-word instruction.

Table C–1. TMS320C2x Versus TMS320C5x for the ADD Instruction [PDF p.661 (printed p.C-12)]

| ’C2x instruction | ’C5x instruction |
|---|---|
| ADD *+ | ADD *+ |
| ADDK 0FFh | ADD #0FFh |
| ADLK 0FFFFh | ADD #0FFFFh |
| ADDH *+ | ADD *+, 16 |

### C.4.2 Serial Port Control Bit Instructions
- The serial port mode control bits moved from the status registers to the
  serial port control register (SPC). No longer part of the CPU registers,
  they have no direct set/clear instructions; SPC bits are manipulated with
  the PLU instructions (Table 6–6, p.6-14). Table C–2 shows the ’C5x
  replacements (data page pointer must be set to 0 to execute them).
- Any or all three SPC bits can be set in one OPL execution, cleared with
  one APL, toggled with XPL (see Chapter 6).

Table C–2. TMS320C2x to TMS320C5x Serial Port Instructions [PDF p.662 (printed p.C-13)]

| ’C2x instruction | ’C5x instruction |
|---|---|
| FORT0 | APL #0FFFBh, SPC |
| FORT1 | OPL #4, SPC |
| RFSM | APL #0FFF7h, SPC |
| RTXM | APL #0FFDFh, SPC |
| SFSM | OPL #8, SPC |
| STXM | OPL #020h, SPC |

### C.4.3 ’C2x-to-’C5x Instruction Set Mapping
The TI ’C5x assembler accepts mnemonics from either instruction set. The
following tables (C–3–C–8) alphabetically map ’C2x to ’C5x mnemonics within
functional groups; some ’C5x instructions do not appear in them (superset).
[PDF p.662 (printed p.C-13)]


Table C–3. TMS320C2x-to-TMS320C5x Accumulator Memory Reference Instructions [PDF pp.663–664 (printed pp.C-14–C-15)]


| ’C2x instruction | ’C5x instruction |
| --- | --- |
| ABS | ABS |
| ADD | ADD |
| ADDC | ADDC |
| ADDH | ADD |
| ADDK | ADD |
| ADDS | ADDS |
| ADDT | ADDT |
| ADLK | ADD |
| AND | AND |
| ANDK | AND |
| CMPL | CMPL |
| LAC | LACC |
| LACK | LACL |
| LACT | LACT |
| LALK | LACC |
| NEG | NEG |
| NORM† | NORM |
| OR | OR |
| ORK | OR |
| ROL | ROL |
| ROR | ROR |
| SACH | SACH |
| SACL | SACL |
| SBLK | SUBB |
| SFL | SFL |
| SFR | SFR |
| SUB | SUB |
| SUBB | SUBB |
| SUBC | SUBC |
| SUBH | SUB |
| SUBK | SUB |
| SUBS | SUBS |
| SUBT | SUBT |
| XOR | XOR |
| XORK | XOR |
| ZAC | LACL |
| ZALH | LACC |
| ZALR | ZALR |
| ZALS | LACL |

† NORM: potential pipeline conflict — see the NORM instruction summary (p.6-181).


Table C–4. TMS320C2x-to-TMS320C5x Auxiliary Registers and Data Memory Page Pointer Instructions [PDF p.664 (printed p.C-15)]


| ’C2x instruction | ’C5x instruction |
| --- | --- |
| ADRK | ADRK |
| CMPR | CMPR |
| LAR | LAR |
| LARK | LAR |
| LARP | MAR |
| LDP | LDP |
| LDPK | LDP |
| LRLK | LAR |
| MAR | MAR |
| SAR | SAR |
| SBRK | SBRK |

Table C–5. TMS320C2x-to-TMS320C5x TREG0, PREG, and Multiply Instructions [PDF p.665 (printed p.C-16)]


| ’C2x instruction | ’C5x instruction |
| --- | --- |
| APAC | APAC |
| LPH | LPH |
| LT | LT |
| LTA | LTA |
| LTD | LTD |
| LTP | LTP |
| LTS | LTS |
| MAC | MAC |
| MACD | MACD |
| MPY | MPY |
| MPYA | MPYA |
| MPYK | MPY |
| MPYS | MPYS |
| MPYU | MPYU |
| PAC | PAC |
| SPAC | SPAC |
| SPH | SPH |
| SPL | SPL |
| SPM | SPM |
| SQRA | SQRA |
| SQRS | SQRS |

Table C–6. TMS320C2x-to-TMS320C5x Branch and Call Instructions [PDF p.666 (printed p.C-17)]


| ’C2x instruction | ’C5x instruction |
| --- | --- |
| B | B |
| BACC | BACC |
| BANZ | BANZ |
| BBNZ | BCND |
| BBZ | BCND |
| BC | BCND |
| BGEZ | BCND |
| BGZ | BCND |
| BIOZ | BCND |
| BLEZ | BCND |
| BLZ | BCND |
| BNC | BCND |
| BNV | BCND |
| BNZ | BCND |
| BV | BCND |
| BZ | BCND |
| CALA | CALA |
| CALL | CALL |
| RET | RET |
| TRAP | TRAP |

Table C–7. TMS320C2x-to-TMS320C5x I/O and Data Memory Operation Instructions [PDF p.667 (printed p.C-18)]


| ’C2x instruction | ’C5x instruction |
| --- | --- |
| BLKD | BLDD |
| BLKP | BLPD |
| DMOV | DMOV |
| FORT† | OPL / APL |
| IN | IN |
| OUT | OUT |
| RFSM† | APL |
| RTXM† | APL |
| RXF | CLRC |
| SFSM† | OPL |
| STXM | OPL |
| SXF | SETC |
| TBLR | TBLR |
| TBLW | TBLW |

† FORT, RFSM, RTXM, SFSM mappings require the data page pointer to be set to 0.


Table C–8. TMS320C2x-to-TMS320C5x Control Instructions [PDF p.668 (printed p.C-19)]


| ’C2x instruction | ’C5x instruction |
| --- | --- |
| BIT | BIT |
| BITT | BITT |
| CNFD | CLRC |
| CNFP | SETC |
| DINT | SETC |
| EINT | CLRC |
| IDLE | IDLE |
| LST | LST |
| LST1 | LST |
| NOP | NOP |
| POP | POP |
| POPD | POPD |
| PSHD | PSHD |
| PUSH | PUSH |
| RC | CLRC |
| RHM | CLRC |
| ROVM | CLRC |
| RPT | RPT |
| RPTK | RPT |
| RSXM | CLRC |
| RTC | CLRC |
| SC | SETC |
| SHM | SETC |
| SOVM | SETC |
| SST | SST |
| SST1 | SST |
| SSXM | SETC |
| STC | SETC |


---

# Appendix D — Design Considerations for Using XDS510 Emulator

[App D intro, PDF p.669 (printed p.D-1)] The ’C5x DSPs support emulation
through a dedicated emulation port — a superset of IEEE JTAG 1149.1,
accessible by the XDS510 emulator. The information in this appendix supports
**XDS510 Cable #2563988-001 Rev B**. "JTAG" in this book means TI scan-based
emulation based on IEEE 1149.1. IEEE contact (as printed): IEEE Customer
Service, 445 Hoes Lane, PO Box 1331, Piscataway, NJ 08855-1331; phone
(800) 678–IEEE (US/Canada), (908) 981–1393 (outside US/Canada);
FAX (908) 981–9667; Telex 833233.

| Section | Content | PDF p. | Printed p. |
|---|---|---|---|
| D.1 | Cable Header and Signals | 670 | D-2 |
| D.2 | Bus Protocol | 671 | D-3 |
| D.3 | Emulator Cable Pod | 672–673 | D-4–D-5 |
| D.4 | Emulator Cable Pod Signal Timings | 674 | D-6 |
| D.5 | Target System Test Clock | 675 | D-7 |
| D.6 | Configuring Multiple Processors | 676 | D-8 |
| D.7 | Connections Between the Emulator and the Target System | 677–678 | D-9–D-10 |
| D.8 | Emulation Timing Calculations | 679–681 | D-11–D-13 |

## D.1 Cable Header and Signals [PDF p.670 (printed p.D-2)]

- Target system must have a 14-pin header (two 7-pin rows) with connections
  per Figure D–1. Recommended parts (other headers usable): straight header,
  unshrouded — DuPont Electronics part number 67996–114; right-angle header,
  unshrouded — DuPont Electronics part number 68405–114.
- Figure D–1 header layout (pins, odd left / even right): 1 TMS, 2 TRST;
  3 TDI, 4 GND; 5 PD (VDD), 6 No pin (key); 7 TDO, 8 GND; 9 TCK_RET,
  10 GND; 11 TCK, 12 GND; 13 EMU0, 14 EMU1. Dimensions: pin-to-pin spacing
  0.100 in. (X, Y); pin width 0.025 in. square post; pin length 0.235 in.
  nominal.
- (Appendix I, p.D-2 change: PD pin 5 was changed from +5V to VDD in this
  revision — see §I.)

Table D–1. XDS510 Header Signal Description [PDF p.670 (printed p.D-2)]

| Pin | Signal | Pod state | Target state | Description |
|---:|---|---|---|---|
| 1 | TMS | O | I | JTAG test mode select |
| 2 | TRST | O | I | JTAG test reset |
| 3 | TDI | O | I | JTAG test data input |
| 5 | PD | I | O | Presence detect. Indicates the emulation cable is connected and the target is powered up. PD should be tied to VDD in the target system. |
| 7 | TDO | I | O | JTAG test data output |
| 9 | TCK_RET | I | O | JTAG test clock return. Test clock input to the XDS510 emulator. May be a buffered or unbuffered version of TCK. |
| 11 | TCK | O | I | JTAG test clock. TCK is a 10-MHz clock source from the emulation cable pod. This signal can be used to drive the system test clock. |
| 13 | EMU0 | I | I/O | Emulation pin 0 |
| 14 | EMU1 | I | I/O | Emulation pin 1 |

## D.2 Bus Protocol [PDF p.671 (printed p.D-3)]

- IEEE 1149.1 rules for JTAG bus slave devices (’C5x), summarised:
  - TMS and TDI inputs are sampled on the rising edge of the device's TCK.
  - TDO output is clocked from the falling edge of the device's TCK.
- When JTAG devices are daisy-chained, the TDO of one device has
  approximately a half TCK cycle of setup time before the next device's TDI
  — this minimises race conditions that would occur if TDO and TDI were
  timed from the same TCK edge. Penalty: reduced TCK frequency.
- IEEE 1149.1 gives no rules for JTAG bus master (XDS510) devices; it
  expects a bus master to provide bus-slave-compatible timings. The XDS510
  provides timings meeting the bus-slave rules, plus an optional timing mode
  allowing much higher frequency for improved performance.

## D.3 Emulator Cable Pod [PDF pp.672–673 (printed pp.D-4–D-5)]

Figure D–2 shows a portion of the XDS510 emulator cable pod. Functional
features:
- TDO and TCK_RET can be parallel-terminated inside the pod if the
  application requires; by default they are not terminated.
- TCK is driven with a 74AS1034 device. Because of the high-current drive
  (48 mA IOL/IOH), this signal can be parallel-terminated. If TCK is tied to
  TCK_RET, the parallel terminator in the pod can be used.
- TMS and TDI can be generated from the falling edge of TCK_RET (per IEEE
  1149.1 bus-slave device timing rules) or from the rising edge of TCK_RET
  (higher TCK_RET frequency). Default is the IEEE 1149.1 slave timing.
  This is an emulator software option selectable when the emulator is
  invoked. Single-processor applications can generally benefit from the
  higher clock frequency; multiprocessor applications may prefer IEEE
  1149.1 bus-slave timing to minimise emulation timing constraints.
- TMS and TDI are series-terminated to reduce signal reflections.
- A 10-MHz test clock source is provided; a custom test clock can also be
  supplied for greater flexibility.
- Figure D–2 (pod interface schematic): 74AS devices unless otherwise
  specified; TDO via 180 Ω / 270 Ω terminator (JP1, 74F175); TMS/TDI via
  33 Ω series; TCK via 74AS1034 from a 10 MHz source (10 kΩ); TRST via
  74AS1034; EMU0/EMU1 via 10 kΩ; TCK_RET via JP2, 100 Ω, 74AS1004; PD.
  (Schematic details are as extracted; the figure is a wiring diagram, not
  prose — component values above are the legible ones.)

## D.4 Emulator Cable Pod Signal Timings [PDF p.674 (printed p.D-6)]

- Figure D–3 shows the pod signal timings; Table D–2 defines the
  parameters. Parameters are calculated from values in the standard data
  sheets for the cable pod and are for reference only — TI does not test or
  guarantee these timings.
- The emulator pod uses TCK_RET as its clock source for internal
  synchronisation. TCK is provided as an optional target-system test clock
  source.

Table D–2. Emulator Cable Pod Timing Parameters [PDF p.674 (printed p.D-6)]

| No. | Parameter | Description | Min | Max | Unit |
|---:|---|---|---:|---:|---|
| 1 | tTCKmin / tTCKmax | TCK_RET period | 35 | 200 | ns |
| 2 | tTCKhighmin | TCK_RET high pulse duration | 15 | — | ns |
| 3 | tTCKlowmin | TCK_RET low pulse duration | 15 | — | ns |
| 4 | td(XTMXmin) / td(XTMXmax) | TMS/TDI valid from TCK_RET low (default timing) | 6 | 20 | ns |
| 5 | td(XTMSmin) / td(XTMSmax) | TMS/TDI valid from TCK_RET high (optional timing) | 7 | 24 | ns |
| 6 | tsu(XTDOmin) | TDO setup time to TCK_RET high | 3 | — | ns |
| 7 | thd(XTDOmin) | TDO hold time from TCK_RET high | 12 | — | ns |

## D.5 Target System Test Clock [PDF p.675 (printed p.D-7)]

- Figure D–4: application with the system test clock generated in the
  target system; the TCK signal is left unconnected. Two benefits:
  1. Test clock frequency can be set to match system requirements (the
     emulator provides only a single 10-MHz test clock).
  2. Other devices in the system may require a test clock when the emulator
     is not connected.

## D.6 Configuring Multiple Processors [PDF p.676 (printed p.D-8)]

- Figure D–5: typical daisy-chained multiprocessor configuration meeting
  the minimum requirements of IEEE (JTAG) 1149.1. Emulation signals are
  buffered to isolate the processors from the emulator and provide adequate
  signal drive. Benefit: the test clock can be slowed to eliminate timing
  problems. Key points:
  - Processor TMS, TDI, TDO, and TCK signals should be buffered through
    the same physical device package for better control of timing skew.
  - Input buffers for TMS, TDI, and TCK should have pullup resistors to
    5 volts to hold these signals at a known value when the emulator is not
    connected; 4.7 kΩ or greater is suggested.
  - Buffering EMU0 and EMU1 is optional but highly recommended for
    isolation; they are not critical signals and need not be buffered
    through the same physical package as TMS, TCK, TDI, TDO.

## D.7 Connections Between the Emulator and the Target System [PDF pp.677–678 (printed pp.D-9–D-10)]

- High-quality signals between emulator and target are extremely important;
  correct signal buffering, test-clock inputs, and multiprocessor
  interconnections are required for proper operation.
- EMU0 and EMU1 are I/O pins on the ’C5x but only inputs to the XDS510;
  in multiprocessor systems they provide global run/stop operations.

### D.7.1 Emulation Signals Not Buffered
- If the distance between the emulation header and the target device is less
  than 6 inches, no buffering is necessary (Figure D–6).
- EMU0 and EMU1 must have pullup resistors to 5 volts for a signal rise
  time of less than 10 µs; a 4.7-kΩ resistor is suggested for most
  applications.

### D.7.2 Emulation Signals Buffered
- If the distance between the emulation header and the JTAG target device is
  greater than 6 inches, the emulation signals must be buffered
  (Figure D–7). TMS, TDI, TDO, and TCK_RET are buffered through the same
  device package.
- EMU0 and EMU1 pullups as in §D.7.1 (5 V, <10 µs rise, 4.7 kΩ suggested).
- For high-quality signals (especially processor TCK and emulator TCK_RET),
  special care may be needed in PCB trace routing, and termination resistors
  may be needed to match trace impedance. The emulator pod provides optional
  internal parallel terminators on TCK_RET and TDO; TMS and TDI provide
  fixed series termination.

## D.8 Emulation Timing Calculations [PDF pp.679–681 (printed pp.D-11–D-13)]

Examples of how to calculate emulation timings; for actual target timing
parameters, see the appropriate device data sheets.

Assumptions (as printed):
- tsu(TTMS): target TMS/TDI setup to TCK high — 10 ns
- th(TTMS): target TMS/TDI hold from TCK high — 5 ns
- td(TTDO): target TDO delay from TCK low — 15 ns
- td(bufmax): target buffer delay maximum — 10 ns
- td(bufmin): target buffer delay minimum — 1 ns
- t(bufskew): target buffer skew between two devices in the same package,
  [td(bufmax) − td(bufmin)] × 0.15 — 1.35 ns
- ttckfactor: a 40/60 duty cycle clock — 0.4

From Table D–2 (p.D-6): td(XTMSmax) TMS/TDI delay from TCK_RET low, max
20 ns; td(XTMX[min]) from TCK_RET low, min 6 ns; td(XTMSmax) from TCK_RET
high, max 24 ns; td(XTMXmin) from TCK_RET high, min 7 ns; tsu(XTDOmin)
TDO setup to XDS510 TCK_RET high, 3 ns.

Two key timing paths: (1) TCK_RET/TMS/TDI (tprdtck_TMS); (2) TCK_RET/TDO
(tprdtck_TDO). In each case the worst-case path delay determines the maximum
system test clock frequency.

- **Case 1** — single processor, direct connection, TMS/TDI timed from
  TCK_RET low (default timing): tprdtck_TMS = [td(XTMSmax) + tsu(TTMS)] /
  ttckfactor = (20 + 10) / 0.4 = 75 ns (13.3 MHz); tprdtck_TDO =
  [td(TTDO) + tsu(XTDOmin)] / ttckfactor = (15 + 3) / 0.4 = 45 ns
  (22.2 MHz). Limiting factor: TCK/TMS path.
- **Case 2** — single processor, direct connection, TMS/TDI timed from
  TCK_RET high (optional timing): tprdtck_TMS = td(XTMSmax) + tsu(TTMS) =
  24 + 10 = 34 ns (29.4 MHz); tprdtck_TDO = (15 + 3) / 0.4 = 45 ns
  (22.2 MHz). Limiting factor: TCK/TDO path. Hold-time note: the minimum
  hold time for the XDS510 cable pod is 7 ns, which meets the 5-ns hold time
  of the target device.
- **Case 3** — single/multiple processor, TMS/TDI buffered input;
  TCK_RET/TDO buffered output, TMS/TDI timed from TCK_RET high (optional
  timing): tprdtck_TMS = td(XTMSmax) + tsu(TTMS) + 2·td(bufmax) =
  24 + 10 + 2(10) = 54 ns (18.5 MHz); tprdtck_TDO = [td(TTDO) +
  tsu(XTDOmin) + t(bufskew)] / ttckfactor = (15 + 3 + 1.35) / 0.4 = 58.4 ns
  (20.7 MHz). Limiting factor: TCK/TMS path. TMS/TDI hold time is reduced
  by the buffer skew (1.35 ns) but still meets the minimum device hold time.
- **Case 4** — single/multiprocessor, TMS/TDI/TCK buffered input; TDO
  buffered output, TMS/TDI timed from TCK_RET low (default timing):
  tprdtck_TMS = [td(XTMSmax) + tsu(TTMS) + tbufskew] / tckfactor =
  (24 + 10 + 1.35) / 0.4 = 88.4 ns (11.3 MHz); tprdtck_TDO = [td(TTDO) +
  tsu(XTDOmin) + td(bufmax)] / tckfactor = (15 + 3 + 10) / 0.4 = 70 ns
  (14.3 MHz). Limiting factor: TCK/TMS path. [INFERENCE / manual
  inconsistency flagged: Case 4 says "timed from TCK_RET low (default
  timing)" but uses td(XTMSmax) = 24 ns, the TCK_RET-high value from
  Table D–2 (the low value is 20 ns); the manual also prints "tckfactor"
  for "ttckfactor" in this case. Values reproduced as printed.]
- Multiprocessor EMU0/EMU1 rise time: must go from logic low to logic high
  in less than 10 µs: trise = 5(Rpullup × Ndevices × Cload_per_device) =
  5(4.7 kΩ × 16 × 15 pF) = 5.64 µs.

---

# Appendix E — Memories, Sockets, and Crystals

[App E intro, PDF p.682 (printed p.E-1)] Product information on memories and
sockets manufactured by Texas Instruments and compatible with the ’C5x;
crystal frequencies, specifications, and vendors.

## E.1 Memories [PDF p.683 (printed p.E-2)] — transcribed in full

- EPROM memories that can be interfaced with ’C5x processors; see *Digital
  Signal Processing Applications with the TMS320 Family* for interfaces
  using memories and analog conversion devices.
- Data sheets for EPROM memories are in the MOS Memory Data Book
  (literature number SMYD095): TMS27C64, TMS27C128, TMS27C256, TMS27C512.
- Another EPROM, TMS27C291/292, is described in a data sheet (literature
  number SMLS291).

## E.2 Sockets [PDF p.683 (printed p.E-2)] — transcribed in full

- AMP manufactures a 132-pin quad flat pack socket for the ’C5x devices:
  two pieces, a base (the socket itself) and a lid. Part numbers:
  Base: AMP 821942-1; Lid: AMP 821949-5.
- For additional information about TI sockets, contact the nearest TI sales
  office or: Texas Instruments Incorporated, Connector Systems Dept,
  M/S 14–3, Attleboro, MA 02703, (617) 699–5242/5269, Telex: 92–7708.
  (1998 contact data — historical.)

## E.3 Crystals [PDF p.684 (printed p.E-3)] — transcribed in full

Table E–1. Commonly Used Crystal Frequencies

| Device | Frequency |
|---|---|
| TMS320C25 | 40.96 MHz |
| TMS320C5x | 20.48 MHz |
| TMS320C5x | 40.96 MHz |

- When connected across X1 and X2/CLKIN of the TMS320 processor, a crystal
  enables the internal oscillator.
- Crystal specification requirements: load capacitance = 20 pF; series
  resistance = 30 ohm; power dissipation = 1 mW.
- Vendors of crystals suitable for use with TMS320 devices:
  - RXD, Inc., Norfolk, NB, (800) 228–8108
  - N.E.L. Frequency Controls, Inc., Burlington, WI, (414) 763–3591
  - CTS Knight, Inc. — contact the local distributor.
  (1998 vendor data — historical.)

---

# Appendix F — Submitting ROM Codes to TI

[App F intro, PDF p.685 (printed p.F-1)] TI offers a mask-programmable ROM
for a single-chip solution. This appendix explains the benefits of the
space-saving ROM and describes the function of the TMS320 development tools.

## F.1 Single-Chip Solution [PDF p.686 (printed p.F-2)] — process summary

- A code-customised processor for a specific application gives: greater
  memory expansion; lower system cost; less hardware and wiring; smaller PCB.
- A frequently used routine/algorithm can be programmed into the on-chip ROM
  of a TMS320 DSP. Programs can also be expanded with external memory
  (reduces chip count, more flexible program memory); multiple functions in
  a single device enhance system capabilities.
- Development flow: develop/test/refine in microprocessor mode (external
  program memory, MP/MC mode), then submit the finalised code to TI for
  masking into on-chip program ROM — the device becomes a microcomputer
  executing customised programs from on-chip ROM. If the code needs changing
  or upgrading, the device can be used in microprocessor mode again, which
  shortens field-upgrade time and avoids inventory obsolescence.
  MP/MC mode is available on all ROM-coded TMS320 DSP devices when accesses
  to either on-chip or off-chip memory are required.

## F.2 TMS320 Development Flow [PDF p.687 (printed p.F-3)] — process summary

Figure F–1 (ROM code submittal flowchart):
1. Customer TMS320 design.
2. Customer submits: TMS320 New Code Release Form; Print Evaluation and
   Acceptance Form (PEAF); purchase order for mask prototypes; TMS320 code.
3. TI responds: customer code input into TI system; code sent back to
   customer for verification.
4. Customer approves algorithm? No → back to customer; Yes → TI produces
   prototypes.
5. Customer approves prototypes (minimum production order required)? No →
   back; Yes → TMS320 production.
- When ordering, there is a one-time, nonrefundable charge for mask tooling.
  A minimum production order per year is required for any masked-ROM device.
  ROM codes are deleted from the TI system one year after the final delivery.

## F.3 Submitting TMS320 ROM Code [PDF p.688 (printed p.F-4)] — process summary

Submission formats:
- 3-1/2-inch floppy: COFF format from macro-assembler/linker (preferred)
- 5-1/4-inch floppy: COFF format from macro-assembler/linker
- Modem (BBS): COFF format from macro-assembler/linker
- EPROM (others): TMS27C64
- PROM: TBP28S166, TBP28S86

- On submission, TI reformats the code for the mask-generation system, so
  customer system-level verification is necessary to ensure the reformatting
  stays transparent and does not affect execution. Formatting changes: removal
  of address-relocation information (code address begins at the base address
  of the ROM and progresses without gaps to the last address of the ROM) and
  addition of data in the reserved locations of the ROM for device ROM test.
  Because of these changes, **a checksum comparison is not a valid means of
  verification**.
- With each masked-device order the customer must sign a disclaimer
  (verbatim): "The units to be shipped against this order were assembled,
  for expediency purposes, on a prototype (that is, nonproduction qualified)
  manufacturing line, the reliability of which is not fully characterized.
  Therefore, the anticipated inherent reliability of these prototype units
  cannot be expressly defined." — and a release (verbatim): "Any masked ROM
  device may be resymbolized as TI standard product and resold as though it
  were an unprogrammed version of the device, at the convenience of Texas
  Instruments."
- The use of the ROM-protect feature does not hold for this release statement.
  Additional risk and charges are involved when the ROM-protect feature is
  selected; contact the nearest TI Field Sales Office for procedures,
  leadtimes, and cost. (1998 process — historical.)

---

# Appendix G — Development Support and Part Order Information

[App G intro, PDF p.689 (printed p.G-1)] Development support information,
device part numbers, and support-tool ordering information for the ’C5x.
Each ’C5x support product is described in the *TMS320 DSP Development
Support Reference Guide*; 100+ third-party developers offer TMS320-family
products (see the *TMS320 Third-Party Support Reference Guide*). Pricing and
availability: nearest TI Field Sales Office or authorised distributor (list at
the back of the book). **All part numbers, phone numbers, and addresses in
this appendix are 1998 ordering data — historical; do not order from them
without re-verification.**

## G.1 Development Support [PDF pp.690–691 (printed pp.G-2–G-3)] — condensed

### G.1.1 Software and Hardware Development Tools
- Software: assembler/linker; simulator; optimising ANSI C compiler;
  application algorithms; C/assembly debugger and code profiler.
- Hardware: emulator XDS510; ’C5x Evaluation Module (EVM); ’C5x DSP
  Starter Kit (DSK).

### G.1.2 Third-Party Support
- 100+ independent third-party vendors/consultants: cross-assemblers,
  simulators, DSP utility packages, logic analysers, emulators; services from
  speech encoding and vector quantisation to software/hardware design and
  system analysis. Contact the third party directly; addresses/phone numbers
  in the *TMS320 Third-Party Support Reference Guide*.

### G.1.3 Technical Training Organization (TTO) TMS320 Workshops
- TMS320C5x DSP Design Workshop: for hardware/software design engineers and
  decision-makers designing with the ’C5x; hands-on exercises; microprocessor/
  assembly language experience required; digital design techniques and C
  experience desirable. Topics: DSP fundamentals; ’C5x architecture/
  instruction set; PC-based software simulator; ’C5x assembler/linker; C
  programming environment; system architecture considerations; memory and I/O
  interfacing; serial ports and multiple processor features. Registration/
  pricing/enrolment (as printed): (972) 644–5580.

### G.1.4 Assistance
- For TMS320 questions on device problems, development tools, documentation,
  software upgrades, and new products, contact TI — see "If You Need
  Assistance" in the Preface.

## G.2 Part Order Information [PDF pp.692–695 (printed pp.G-4–G-7)]

### G.2.1 Device and Development Support Tool Nomenclature — condensed
- Development-stage prefixes: devices TMX / TMP / TMS; support tools TMDX /
  TMDS. TMX: experimental device, not necessarily representative of the final
  device's electrical specifications. TMP: final silicon die conforming to
  electrical specifications, quality/reliability verification not completed.
  TMS: fully qualified production device. TMDX: support product not yet
  through TI internal qualification testing. TMDS: fully qualified support
  product.
- TMX/TMP devices and TMDX tools ship with the disclaimer: "Developmental
  product is intended for internal evaluation purposes." TMS devices and TMDS
  tools are fully characterised; TI standard warranty applies.
- Note (manual): prototype devices (TMX/TMP) are expected to have a greater
  failure rate than standard production devices; TI recommends not using them
  in any production system — only qualified production devices should be used.

### G.2.2 Device Nomenclature (Figure G–1 legend) [PDF p.693 (printed p.G-5)] — transcribed
Example: `TMS 320 (B) C 52 PJ (L) –100`
- Prefix: TMX = experimental; TMP = prototype; TMS = qualified; SM = high
  reliability (non 883C); SMJ = MIL–STD–883C.
- Device family: 320 = DSP family.
- Boot loader option: (B).
- Technology: C = CMOS; E = CMOS EPROM; LC = low-voltage CMOS (3.3 V);
  VC = low-voltage CMOS (3 V).
- Device: ’C1x: 10, 14, 15, 16, 17; ’C2x: 25, 26; ’C2xx: 203, 204, 205, 209;
  ’C3x: 30, 31, 32; ’C4x: 40, 44; ’C5x: 50, 51, 52, 53, 56, 57; ’C54x: 541,
  542, 543, 545, 546, 548; ’C8x: 80, 82.
- Package type: FD = ceramic leadless CC; FN = plastic leaded CC;
  FZ = ceramic CER-QUAD; GB = ceramic PGA; J = ceramic CER-DIP;
  JD = ceramic DIP side-brazed; N = plastic DIP; PJ = 100-pin plastic EIAJ
  QFP; PQ = 100/132-pin plastic BQFP; PZ = 100-pin plastic TQFP;
  PBK = 120/128-pin plastic TQFP; PGE = 144-pin plastic TQFP.
- Temperature range: H = 0 to 50 °C; L = 0 to 70 °C; A = −40 to 85 °C;
  S = −55 to 100 °C; M = −55 to 125 °C.
- MIPS: –100 (speed grade in the example).

### G.2.3 Development Support Tools (Figure G–2 legend) [PDF p.694 (printed p.G-6)] — transcribed
Example: `TMDS 32 4 28 1 0 –0 2`
- Qualification status: TMDX = prototype; TMDS = qualified.
- Device family: 32 = TMS320 family.
- Product type: 4 = software; 6 = hardware; 8 = upgrade.
- Model (hardware only): 11 = XDS/11; 22 = XDS/22; 88 = upgrade kits.
- Operating system (software only): 02 = ’C1x VAX/VMS; 08 = ’C1x IBM
  MS/PC-DOS; 22 = ’C2x VAX/VMS; 25 = ’C2x/’C2xx/’C5x SPARC; 28 = ’C2x or
  ’C1x/’C2x/’C2xx/’C5x IBM MS/PC-DOS; 32 = ’C3x VAX/VMS; 38 = ’C3x IBM
  MS/PC-DOS; 42 = ’C4x VAX/VMS; 48 = ’C4x IBM MS/PC-DOS; 52 = ’C5x VAX/VMS;
  55 = ’C5x or ’C2xx/’C5x SPARC; 58 = ’C5x or ’C2xx/’C5x IBM MS/PC-DOS.
- Medium (software only): 2 = 5.25-inch floppy disk; 8 = 1600 BPI magnetic
  tape. S/W format (software only): 0 = object code; 1 = source code.
- Sequence number (hardware only); Generation (hardware only): 1 = ’C1x;
  2 = ’C2x; 3 = ’C3x; 4 = ’C4x; 5 = ’C5x. Format (software only):
  1 = TI-tagged; 5 = COFF.

Table G–1. TMS320C5x Development Support Tools Part Numbers [PDF p.695 (printed p.G-7)] — transcribed in full

| Development tool | Platform | Part number |
|---|---|---|
| Assembler/Linker | PC (DOS, OS/2) | TMDS3242850-02 |
| C Compiler/Assembler/Linker | PC (DOS, OS/2) | TMDS3242855-02 |
| C Compiler/Assembler/Linker | HP (HP-UX) / SPARC (Sun OS) | TMDS3242555-08 |
| Debugger/Emulation Software | PC (DOS, Windows, OS/2) | TMDS3240150 |
| Debugger/Emulation Software | SPARC (Sun OS) | TMDS3240650 |
| Digital Filter Design Package | PC (DOS) | DFDP |
| DSP Starter Kit (DSK) | PC (DOS) | TMDS3200051 |
| Evaluation Module (EVM) | PC (DOS, Windows) | TMDS3260050 |
| Simulator (C language) | PC (DOS, Windows) | TMDS3245851-02 |
| Simulator (C language) | SPARC (Sun OS) | TMDS3245551-09 |
| XDS510XL Emulator† | PC (DOS, OS/2) | TMDS00510 |
| XDS510WS Emulator‡ | SPARC (Sun OS) | TMDS00510WS |
| 3 V/5 V PC/SPARC JTAG Emulation Cable XDS510 / XDS510WS | — | TMDS3080002 |

† Includes XDS510 board and JTAG cable. ‡ Includes XDS510WS box and JTAG cable.

## G.3 Hewlett-Packard E2442A Preprocessor ’C5x Interface [PDF pp.696–697 (printed pp.G-8–G-9)] — condensed

- The HP E2442A preprocessor ’C5x interface is a mechanical/electrical
  connection between the target system and an HP logic analyser; it captures
  processor signals and passes them to the analyser at the appropriate time.
  With the preprocessor plugged in, state and timing analysis are available.
  Two connectors are loaded for other debugging tools: a BNC connector that,
  with the analyser's sequencer, halts the processor on a condition (then the
  ’C5x HLL debugger can examine system state, e.g. microprocessor registers);
  and a 14-pin connector receiving XDS510 signals for use in defining an
  analyser trigger condition.
- The preprocessor includes software that automatically labels address, data,
  and status lines, plus a disassembler that processes state traces and
  displays TMS320 mnemonics.

### G.3.1 Capabilities
- Three modes: (1) State per Transfer — the preprocessor clocks the logic
  analyser only when a bus transfer is complete; wait and halt states are
  filtered out. (2) CLKOUT1 clocks the analyser every time the
  microprocessor is clocked — captures all bus states (e.g. to locate memory
  locations that do not respond). (3) Timing measurements.
- The JTAG TAP (test access port) controller can be monitored in real time;
  TAP state can be viewed under the predefined label TAP.

### G.3.2 Logic Analyzers Supported
HP 1650A/B, HP 16510B, HP 16511B, HP 16540/41(A/D), HP 16550A, HP 1660A/61A/62A.

### G.3.3 Pods Required
- Eight pod-connectors on the preprocessor. Three are terminated and best
  used for state analysis (all signals needed for disassembly available).
  The other five are not terminated and contain all processor signals,
  including a second set of the signals needed for disassembly — allowing
  double-probing for simultaneous state and timing measurements.

### G.3.4 Termination Adapters (TAs)
- Of the eight pods, three are terminated; up to five termination adapters
  may be needed, depending on how many pods are connected at the same time.

### G.3.5 Availability
- Hewlett-Packard Company, 2000 South Park Place, Atlanta, GA 30339,
  (404) 980–7351. (1998 contact data — historical.)

---

# Appendix H — Glossary

[App H, PDF pp.698–724 (printed pp.H-1–H-27)] All 352 glossary entries are
included below as `term: definition` lines, grouped by initial letter, in
manual order. 138 entries are "See …" cross-references (kept verbatim).
Definitions are transcribed in full from the manual; where the manual's
definition itself references another entry, that reference is kept. Printed
page (H-N) is given at the end of each entry; PDF page = 697 + N.


## A

- A0–A15: External address pins for data/program memory or I/O devices. [H-1]
- ABU: See autobuffering unit (ABU). [H-1]
- ACC: See accumulator (ACC). [H-1]
- ACCB: See accumulator buffer (ACCB). [H-1]
- ACCH: See accumulator high byte (ACCH). [H-1]
- ACCL: See accumulator low byte (ACCL). [H-1]
- accumulator (ACC): A 32-bit register that stores the results of an arithmetic logic unit (ALU) operation and provides an input for subsequent ALU operations. The ACC is accessible in two halves: accumulator high (ACCH) and accumulator low (ACCL). [H-1]
- accumulator buffer (ACCB): A 32-bit register that temporarily stores the 32-bit contents of the accumulator (ACC). The ACCB has a direct path back to the arithmetic logic unit (ALU) and can be arithmetically or logical- ly acted upon with the ACC. [H-1]
- accumulator high byte (ACCH): The higher 16 bits stored in the accumula- tor (ACC). See also accumulator. [H-1]
- accumulator low byte (ACCL): The lower 16 bits stored in the accumulator (ACC). See also accumulator. [H-1]
- address: The logical location of program code or data stored in memory. [H-1]
- addressing mode: The method by which an instruction calculates the loca- tion of its required data. [H-1]
- address visibility (AVIS) bit: A 1-bit field that allows the internal program address to appear at the TMS320C5x pins so that the internal program address can be traced and the interrupt vector can be decoded in con- junction with IACK when the interrupt vectors reside in on-chip memory. At reset, AVIS = 0. This bit is stored in the processor mode status register (PMST). [H-1]
- AFB: See auxiliary register file bus (AFB). [H-2]
- ALU: See arithmetic logic unit (ALU). [H-2]
- analog-to-digital (A/D) converter: An 8-bit successive-approximation converter with internal sample-and-hold circuitry that translates an ana- log signal to a digital signal. [H-2]
- AR: See auxiliary register (AR). [H-2]
- ARAU: See auxiliary register arithmetic unit ARAU). [H-2]
- ARB: See auxiliary register buffer (ARB) bits. [H-2]
- ARCR: See auxiliary register compare register (ARCR). [H-2]
- arithmetic logic unit (ALU): A 32-bit 2s-complement arithmetic logic unit that has two 32-bit input ports and one 32-bit output port feeding the ac- cumulator (ACC). Provides the logic for arithmetic and Boolean operations. [H-2]
- ARP: See auxiliary register pointer (ARP) bits. [H-2]
- ARR: See BSP address receive register (ARR). [H-2]
- assembler: A software program that creates a machine-language program from a source file containing assembly language instructions, directives, and macro directives. The assembler substitutes absolute operation codes for symbolic operation codes, and absolute or relocatable ad- dresses for symbolic addresses. [H-2]
- assembly language instructions: The language in which computer opera- tions are represented by mnemonics. [H-2]
- autobuffering receiver enable (BRE) bit: A 1-bit field that enables/dis- ables the autobuffering receiver. At reset, BRE = 0. This bit is stored in the BSP control extension register (SPCE). [H-2]
- autobuffering receiver halt (HALTR) bit: A 1-bit field that enables/disables the autobuffer receiver. At reset, HALTR = 0. This bit is stored in the BSP control extension register (SPCE). [H-2]
- autobuffering transmitter enable (BXE) bit: A 1-bit field that enables/dis- ables the autobuffering transmitter. At reset, BXE = 0. This bit is stored in the BSP control extension register (SPCE). [H-2]
- autobuffering transmitter halt (HALTX) bit: A 1-bit field that enables/dis- ables the autobuffer transmitter. At reset, HALTX = 0. This bit is stored in the BSP control extension extension (SPCE). [H-2]
- autobuffering unit (ABU): An on-chip module that allows the serial port in- terface to read or write directly to internal memory independently of the central processing unit (CPU). Autobuffering capability can be separate- ly enabled for transmit and receive sections. When autobuffering is dis- abled, the operation is similar to that of the ’C5x standard serial port. [H-3]
- auxiliary register (AR): Eight 16-bit memory-mapped registers (AR0–AR7) that are used for indirect data address pointers, temporary storage, or integer arithmetic processing through the auxiliary register arithmetic unit (ARAU). Each AR is selected by the auxiliary register pointer (ARP). [H-3]
- auxiliary register arithmetic unit (ARAU): An unsigned 16-bit arithmetic logic unit that calculates indirect addresses using the auxiliary, index, and compare registers as inputs. [H-3]
- auxiliary register buffer (ARB) bits: A 3-bit field that holds the previous value contained in the auxiliary register pointer (ARP). These bits are stored in status register 1 (ST1). [H-3]
- auxiliary register compare register (ARCR): A 16-bit memory-mapped register used as a limit to compare indirect adresses. [H-3]
- auxiliary register file bus (AFB): The bus on which the currently selected auxiliary register (AR) addresses the data memory location. [H-3]
- auxiliary register pointer (ARP) bits: A 3-bit field that selects the auxiliary register (AR) to use in indirect addressing. When the ARP is loaded, the previous ARP value is copied to the auxiliary register buffer (ARB). The ARP can be modified by memory-reference instructions when using indi- rect addressing, and by the MAR and LST instructions. These bits are stored in status register 0 (ST0). [H-3]
- AVIS: See address visibility (AVIS) bit. [H-3]
- AXR: See BSP address transmit register (AXR). [H-3]

## B

- barrel shifter: A unit that rotates bits in a word. See also POSTSCALER and PRESCALER. [H-3]
- BIG bit: A 1-bit field that specifies how the input/out (I/O) port wait-state reg- ister is mapped. This bit is stored in the wait-state control register (CWSR). At reset, BIG = 0. [H-3]
- bit-reversed addressing: A method of indirect addressing that allows effi- cient I/O operations by resequencing the data points in a radix-2 FFT pro- gram. The direction of carry propagation in the ARAU is reversed. [H-3]
- BKR: See BSP receive buffer size register (BKR). [H-4]
- BKX: See BSP transmit buffer size register (BKX). [H-4]
- block move address register (BMAR): A 16-bit memory-mapped register that holds an address value for use with block moves or multiply/accumu- lates. [H-4]
- block repeat active flag (BRAF) bit: A 1-bit field that indicates a block repeat is currently active. This bit is normally set when the RPTB instruc- tion is executed and is cleared when the BRCR register decrements below 0. Writing a 0 to this bit deactivates block repeat. At reset, BRAF = 0. This bit is stored in the processor mode status register (PMST). [H-4]
- block repeat counter register (BRCR): A 16-bit memory-mapped register that limits the number of times a block is repeated. [H-4]
- block repeat program address end register (PAER): A 16-bit memory- mapped register that contains the end address of the segment of code being repeated. [H-4]
- block repeat program address start register (PASR): A 16-bit memory- mapped register that contains the start address of the segment of code being repeated. [H-4]
- BMAR: See block move address register (BMAR). [H-4]
- BOB: See byte ordering bit (BOB). [H-4]
- boot: The process of loading a program into program memory. [H-4]
- boot loader: A built-in segment of code that transfers code from an external source to program memory at power-up. [H-4]
- BRAF: See block repeat active flag (BRAF) bit. [H-4]
- BRCR: See block repeat counter register (BRCR). [H-4]
- BRE: See autobuffering receiver enable (BRE) bit. [H-4]
- BSP: See buffered serial port (BSP). [H-4]
- BSP address receive register (ARR): An 11-bit memory-mapped register that stores the address for writing a word to be transferred from the data receive register (DRR) to ’C5x internal memory. When autobuffering is enabled (BRE = 1), the ARR is no longer available for software access as a memory-mapped register. [H-4]
- BSP address transmit register (AXR): An 11-bit memory-mapped register that stores the address for reading a word to be transferred from ’C5x in- ternal memory to the data transmit register (DXR). When autobuffering is enabled (BXE = 1), the AXR is no longer available for software access as a memory-mapped register. [H-5]
- BSP control extension register (SPCE): A 16-bit memory-mapped register that contains status and control bits for the buffered serial port (BSP) interface. The 10 LSBs of the SPCE are dedicated to serial port interface control, whereas the 6 MSBs are used for autobuffering unit (ABU) control. [H-5]
- BSP receive buffer size register (BKR): An 11-bit memory-mapped regis- ter that stores the address block size for writing a word to be transferred from the data receive register (DRR) to ’C5x internal memory. When autobuffering is enabled (BRE = 1), the BKR is no longer available for software access as a memory-mapped register. [H-5]
- BSP transmit buffer size register (BKX): An 11-bit memory-mapped regis- ter that stores the address block size for reading a word to be transferred from ’C5x internal memory to the data transmit register (DXR). When autobuffering is enabled (BXE = 1), the BKX is no longer available for software access as a memory-mapped register. [H-5]
- buffered serial port (BSP): An on-chip module that consists of a full-duplex, double-buffered serial port interface and an autobuffering unit (ABU). The double-buffered serial port of the BSP is an enhanced version of that available in other TMS320C5x devices (’C50, ’C51, ’C52, and ’C53). The double-buffered serial port allows transfer of a continuous communica- tion stream (8-,10-,12- or 16-bit data packets). Status and control of the BSP is specified in the BSP control extension register (SPCE). [H-5]
- burst mode: A synchronous serial port mode in which a single word is trans- mitted following a frame synchronization pulse (FSX and FSR). [H-5]
- butterfly: A kernel function that computes an N-point fast Fourier transform (FFT), where N is a power of 2. The combinational pattern of inputs resembles butterfly wings. [H-5]
- BXE: See autobuffering transmitter enable (BXE) bit. [H-5]
- byte ordering bit (BOB): A 1-bit field that affects host processor data and address transfers when using the host port interface. Only the host pro- cessor can toggle this bit. The BOB must be initialized before the first data or address register access. This bit is stored in the HPI control regis- ter (HPIC). [H-5]

## C

- C: See carry (C) bit. [H-6]
- CALU: See central arithmetic logic unit (CALU). [H-6]
- CAR1: See circular buffer 1 auxiliary register (CAR1) bits. [H-6]
- CAR2: See circular buffer 2 auxiliary register (CAR2) bits. [H-6]
- carry (C) bit: A 1-bit field that stores the carry output of the arithmetic logic unit (ALU). At reset, C = 1. The C bit can be tested by conditional instruc- tions. This bit is stored in status register 1 (ST1). [H-6]
- CBCR: See circular buffer control register (CBCR). [H-6]
- CBER1: See circular buffer 1 end register (CBER1). [H-6]
- CBER2: See circular buffer 2 end register (CBER2). [H-6]
- CBSR1: See circular buffer 1 start register (CBSR1). [H-6]
- CBSR2: See circular buffer 2 start register (CBSR2). [H-6]
- CENB1: See circular buffer 1 enable (CENB1) bit. [H-6]
- CENB2: See circular buffer 2 enable (CENB2) bit. [H-6]
- central arithmetic logic unit (CALU): A 32-bit arithmetic logic unit that executes 32-bit operations in a single machine cycle. The CALU consists of the arithmetic logic unit (ALU), multiplier (MULT), accumulator (ACC), accumulator buffer (ACCB), and scaling shifters (PRESCALERS, P-SCALER, and POSTSCALER). [H-6]
- central processing unit (CPU): The module of the TMS320C5x that con- trols and interprets the machine-language program and its execution. The CPU consists of the central arithmetic logic unit (CALU), parallel log- ic unit (PLU), auxiliary register arithmetic unit (ARAU), and registers. [H-6]
- circular buffer 1 auxiliary register (CAR1) bits: A 3-bit field that identifies which auxiliary register (AR) is assigned to circular buffer 1. These bits are stored in the circular buffer control register (CBCR). [H-6]
- circular buffer 1 enable (CENB1) bit: A 1-bit field that enables/disables circular buffer 1. At reset, CENB1 = 0. This bit is stored in the circular buffer control register (CBCR). [H-6]
- circular buffer 1 end register (CBER1): A 16-bit memory-mapped register that indicates the circular buffer 1 end address. [H-6]
- circular buffer 1 start register (CBSR1): A 16-bit memory-mapped regis- ter that indicates the circular buffer 1 start address. [H-7]
- circular buffer 2 auxiliary register (CAR2) bits: A 3-bit field that identifies which auxiliary register (AR) is assigned to circular buffer 2. These bits are stored in the circular buffer control register (CBCR). [H-7]
- circular buffer 2 enable (CENB2) bit: A 1-bit field that enables/disables circular buffer 2. At reset, CENB2 = 0. This bit is stored in the circular buffer control register (CBCR). [H-7]
- circular buffer 2 end register (CBER2): A 16-bit memory-mapped register that indicates the circular buffer 2 end address. [H-7]
- circular buffer 2 start register (CBSR2): A 16-bit memory-mapped regis- ter that indicates the circular buffer 2 start address. [H-7]
- circular buffer control register (CBCR): An 8-bit memory-mapped regis- ter that enables/disables the circular buffers (CENB1 and CENB2 bits) and defines which auxiliary registers (CAR1 and CAR2 bits) are mapped to the circular buffers. [H-7]
- CLKDV: See internal transmit clock division factor (CLKDV) bits. [H-7]
- CLKP: See clock polarity (CLKP) bit. [H-7]
- clock modes: Options used by the clock generator to change the internal CPU clock frequency to a fraction or multiple of the frequency of the input clock signal. [H-7]
- clock mode (MCM) bit: A 1-bit field that specifies the source of the clock for CLKX. At reset, MCM = 0. This bit is stored in the serial port control regis- ter (SPC) and TDM serial port control register (TSPC). [H-7]
- clock polarity (CLKP) bit: A 1-bit field that indicates when the data is sampled by the receiver and sent by the transmitter. At reset, CLKP = 0. This bit is stored in the BSP control extension register (SPCE). [H-7]
- CNF: See configuration control (CNF) bit. [H-7]
- code: A set of instructions written to perform a task. [H-7]
- cold boot: The process of loading a program into program memory at power-up. [H-7]
- configuration control (CNF) bit: A 1-bit field that indicates if on-chip dual- access RAM block 0 (DARAM B0) is mapped to program or data space. At reset, CNF = 0. This bit is stored in status register 1 (ST1). [H-7]
- context save/restore: A save/restore of system status (status registers, ac- cumulator, product register, temporary register, hardware stack, and auxiliary registers, etc.) when the device enters/exits a subroutine such as an interrupt service routine. [H-8]
- continuous mode: A synchronous serial port mode in which only one frame synchronization pulse (FSX and FSR) is necessary to transmit several packets at maximum frequency. [H-8]
- CPU: See central processing unit (CPU). [H-8]
- current auxiliary register: The auxiliary register pointed to by the auxiliary register pointer (ARP). [H-8]
- CWSR: See wait-state control register (CWSR). [H-8]

## D

- D0–D15: External data bus pins that transfer data between the ’C5x and ex- ternal data/program memory or I/O devices. [H-8]
- DAB: See direct address bus (DAB). [H-8]
- DARAM: See dual-access RAM. [H-8]
- data bus: A group of connections used to route data. [H-8]
- data memory: A memory region used for storing and manipulating data. [H-8]
- data memory address (dma): The seven LSBs of a direct addressed instruction that contains the immediate relative address within a 128-word data page. The seven LSBs are concatenated with the data memory page pointer (DP) to form the direct memory address of 16 bits. See also data memory page pointer (DP). [H-8]
- data memory page pointer (DP) bits: A 9-bit field that specifies the current data memory page address. The DP bits are concatenated with the 7 LSBs of the instruction word to form the direct memory address of 16 bits. These bits are stored in status register 0 (ST0). [H-8]
- data memory page 0: The first page in data memory space where the memory-mapped registers and the scratch-pad RAM block (B2) reside. [H-8]
- data receive register (DRR): A 16-bit memory-mapped register that holds serial data copied from the receive shift register (RSR). When autobuf- fering is enabled (BRE = 1), the DRR is no longer available for software access as a memory-mapped register. See also data receive shift regis- ter (RSR). [H-8]
- data receive shift register (RSR): A 16-bit register that holds serial data re- ceived from the DR pin. See also data receive register (DRR). [H-9]
- data transmit register (DXR): A 16-bit memory-mapped register that holds serial data to be copied to the data transmit shift register (XSR). When autobuffering is enabled (BXE = 1), the DXR is no longer available for software access as a memory-mapped register. See also data transmit shift register (XSR). [H-9]
- data transmit shift register (XSR): A 16-bit register that holds serial data to be transmitted from the DX pin (or TDX pin when TDM = 1). See also data transmit register (DXR) and TDM data transmit register (TDXR). [H-9]
- DBMR: See dynamic bit manipulation register (DBMR). [H-9]
- digital loopback (DLB) mode: A synchronous serial port test mode in which the DLB bit connects the receive pins to the transmit pins on the same device to test if the port is operating correctly. [H-9]
- digital loopback mode (DLB) bit: A 1-bit field that puts the serial port in dig- ital loopback mode. At reset, DLB = 0. This bit is stored in the serial port control register (SPC) and TDM serial port control register (TSPC). [H-9]
- direct address bus (DAB): A 16-bit bus that provides the data address used by the central processing unit (CPU). [H-9]
- direct memory access (DMA): A mode where a device other than the host processor contends for, and receives, mastership of the memory bus so that data transfers may take place independent of the host. [H-9]
- DLB: See digital loopback mode (DLB) bit. [H-9]
- dma: See data memory address (dma). [H-9]
- DMA: See direct memory access (DMA). [H-9]
- DP: See data memory page pointer (DP) bits. [H-9]
- DRR: See data receive register (DRR). [H-9]
- DSP interrupt (DSPINT) bit: A 1-bit field that enables/disables an interrupt from a host processor to the TMS320C57. The DSPINT bit is written from the host processor; a ’C57 write has no effect on the DSPINT bit. When DSPINT = 1, a ’C57 interrupt is generated. The host must write a 0 to the DSPINT bit while writing to the BOB or HINT bits, so that the host does not provoke an unwanted ’C57 interrupt. This bit is stored in the HPI con- trol register (HPIC). [H-9]
- DSPINT: See DSP interrupt (DSPINT) bit. [H-10]
- dual-access RAM (DARAM): Memory space that can be read from and written to in the same clock cycle. [H-10]
- dynamic bit manipulation register (DBMR): A 16-bit memory-mapped register that masks the input to the parallel logic unit (PLU) in the absence of a long immediate value. [H-10]
- DXR: See data transmit register (DXR). [H-10]

## E

- enable extra index register (NDX) bit: A 1-bit field that determines if a mod- ification or write to auxiliary register 0 (AR0) also modifies or writes to the index register (INDX), and the auxiliary register compare register (ARCR) to maintain compatibility with the TMS320C2x. This bit is stored in the processor mode status register (PMST). [H-10]
- enable multiple TREGs (TRM) bit: A 1-bit field that indicates if an LT(A,D,P,S) instruction loads only TREG0 or loads all three of the tempo- rary registers (TREG0, TREG1, and TREG2) to maintain compatibility with the TMS320C2x. The TRM bit allows the TMS320C5x to operate in either ’C2x-compatible mode (TRM = 0) or ’C5x-enhanced mode (TRM = 1) in conjunction with the use of TREG0, TREG1, and TREG2. The TRM bit affects the operation of all ’C2x-compatible instructions that modify TREG0. This bit is stored in the processor mode status register (PMST). [H-10]
- external flag (XF) pin status bit: A 1-bit field that drives the level of the ex- ternal flag (XF) pin. At reset, XF = 1.This bit is stored in status register 1 (ST1). [H-10]
- external interrupt: A hardware interrupt triggered by a pin (INT1–INT4). [H-10]

## F

- fast Fourier transform (FFT): An efficient method of computing the discrete Fourier transform, which transforms functions between the time domain and frequency domain. The time-to-frequency domain is called the for- ward transform, and the frequency-to-time domain is called the inverse transformation. See also butterfly. [H-10]
- FE: See format extension (FE) bit. [H-10]
- FFT: See fast Fourier transform (FFT). [H-11]
- FIG: See frame ignore (FIG) bit. [H-11]
- FO: See format (FO) bit. [H-11]
- format (FO) bit: A 1-bit field that specifies the word length of the serial port transmitter and receiver. The data is transferred with the MSB first. At re- set, FO = 0. This bit is stored in the serial port control register (SPC) and TDM serial port control register (TSPC). [H-11]
- format extension (FE) bit: A 1-bit field used in conjunction with the format bit (FO) to specify the word length of the BSP serial port transmitter and receiver. When FO = FE = 00, the format is 16-bit words; when FO = FE = 01, the format is 10-bit words; when FO = FE = 10, the format is 8-bit words; and when FO = FE = 11, the format is 12-bit words. For 8-,10-, and 12-bit words, the received words are right-justified and the sign bit is extended to form a 16-bit word. The words to transmit must be right-justified. At reset, FE = 0. This bit is stored in the BSP control exten- sion register (SPCE). [H-11]
- frame ignore (FIG) bit: A 1-bit field used only in transmit continuous mode with external frame and in receive continuous mode. At reset, FIG = 0. This bit is stored in the BSP control extension register (SPCE). [H-11]
- frame synchronization mode (FSM) bit: A 1-bit field that specifies whether frame synchronization pulses (FSX and FSR) are required for serial port operation. At reset, FSM = 0. This bit is stored in the serial port control register (SPC) and TDM serial port control register (TSPC). [H-11]
- frame synchronization polarity (FSP) bit: A 1-bit field that determines the status of the frame synchronization pulses. At reset, FSP = 0. This bit is stored in the BSP control extension register (SPCE). [H-11]
- Free bit: A 1-bit field used in conjunction with the Soft bit to determine the state of the serial port clock when a breakpoint is encountered in the high- level language debugger. At reset, Free = 0. This bit is stored in the serial port control register (SPC) and TDM serial port control register (TSPC). [H-11]
- FSM: See frame synchronization mode (FSM) bit. [H-11]
- FSP: See frame synchronization polarity (FSP) bit. [H-11]

## G

- general-purpose input/output pins: Pins that can be used to supply input signals from an external device or output signals to an external device. These pins are not linked to specific uses; rather, they provide input or output signals for a variety of purposes. These pins include the general- purpose BIO input pin and XF output pin. [H-12]
- global data memory space: One of four memory spaces. The global data memory space can either share data with other processors within the system or serve as additional data memory space. [H-12]
- global memory allocation register (GREG): An 8-bit memory-mapped register that specifies the size of the global memory space. At reset, the GREG is cleared. [H-12]
- GREG: See global memory allocation register (GREG). [H-12]

## H

- HALTR: See autobuffering receiver halt (HALTR) bit. [H-12]
- HALTX: See autobuffering transmitter halt (HALTX) bit. [H-12]
- hardware interrupt: An interrupt triggered through physical connections with on-chip peripherals or external devices. [H-12]
- HINT bit: ’C57-to-Host Processor Interrupt. A 1-bit field that enables/dis- ables an interrupt from the TMS320C57 to a host processor. At reset, HINT = 0. This bit is stored in the HPI control register (HPIC). [H-12]
- HM: See hold mode (HM) bit. [H-12]
- HOM: See host-only mode (HOM). [H-12]
- hold mode (HM) bit: A 1-bit field that determines whether the central pro- cessing unit (CPU) can stop or continue when the HOLD signal initiates a power-down mode. At reset, HM = 1. This bit is stored in status register 1 (ST1). [H-12]
- host-only mode (HOM): The mode that allows the host to access HPI memory while the TMS230C57 is in IDLE2 (all internal clocks stopped) or in reset mode. The external ’C57 clock may even be stopped. The host can therefore access the HPI RAM while the ’C57 is in its optimum config- uration in terms of power consumption. [H-12]
- host port interface (HPI): An on-chip module consisting of an 8-bit parallel port that interfaces a host processor to the TMS320C57. The HPI has two modes of operation, shared-access mode (SAM) and host-only mode (HOM). Status and control of the HPI is specified in the HPI control register (HPIC). See also shared-access mode (SAM) and host-only mode (HOM). [H-13]
- HPI: See host port interface (HPI). [H-13]
- HPIA: See HPI address register (HPIA). [H-13]
- HPIAH: See HPI address register high byte (HPIAH). [H-13]
- HPIAL: See HPI address register low byte (HPIAL). [H-13]
- HPIC: See HPI control register (HPIC). [H-13]
- HPICH: See HPI control register high byte (HPICH). [H-13]
- HPICL: See HPI control register low byte (HPICL). [H-13]
- HPI address register (HPIA): A 16-bit register that stores the address of the host port interface (HPI) memory block. The HPIA can be preincrem- ented or postincremented. [H-13]
- HPI address register high byte (HPIAH): The higher 16 bits stored in the HPI address register (HPIA). See also HPI address register (HPIA). [H-13]
- HPI address register low byte (HPIAL): The lower 16 bits stored in the HPI address register (HPIA). See also HPI address register (HPIA). [H-13]
- HPI control register (HPIC): A 16-bit register that contains status and con- trol bits for the host port interface (HPI). [H-13]
- HPI control register high byte (HPICH): The higher 16 bits stored in the HPI control register (HPIC). See also HPI control register (HPIC). [H-13]
- HPI control register low byte (HPICL): The lower 16 bits stored in the HPI control register (HPIC). See also HPI control register (HPIC). [H-13]

## I

- I/O port wait-state register (IOWSR): A 16-bit memory-mapped register that specifies the number of wait states for the input/out (I/O) port. The IOWSR can be mapped in one of two ways as specified by the BIG bit in the wait-state control register (CWSR). At reset, IOWSR = FFFF. [H-13]
- IFR: See interrupt flag register (IFR). [H-13]
- IMR: See interrupt mask register (IMR). [H-14]
- IN0 bit: Input 0 bit. A 1-bit field that allows the CLKR pin to be used as an input. IN0 reflects the current level of the CLKR pin of the device. This bit is stored in the SPC and TDM serial port control register (TSPC). [H-14]
- IN1 bit: Input 1 bit. A 1-bit field that allows the CLKX pin to be used as an input. IN1 reflects the current level of the CLKX pin of the device. This bit is stored in the SPC and TDM serial port control register (TSPC). [H-14]
- index register (INDX): A 16-bit memory-mapped register that specifies increment sizes greater than 1 for indirect addressing updates. In bit- reversed addressing, the INDX defines the array size. [H-14]
- INDX: See index register (INDX). [H-14]
- instruction: The basic unit of programming that causes the execution of one operation; it consists of an opcode and operands along with optional labels and comments. [H-14]
- instruction register (IREG): A 16-bit register that contains the actual instruction being executed. [H-14]
- internal interrupt: A hardware interrupt caused by an on-chip peripheral. [H-14]
- internal transmit clock division factor (CLKDV) bits: A 5-bit field that de- termines the internal transmit clock duty cycle. At reset, CLKDV = 00011. These bits are stored in the BSP control extension register (SPCE). [H-14]
- interrupt: An exceptional condition that is caused either by an external event to the CPU or by a previously executed instruction that forces the current program to stop. The CPU executes instructions of an interrupt service routine (ISR) at an address corresponding to the source of the interrupt. After the CPU services the interrupt, the CPU resumes execu- tion of the program at the instruction whose execution was interrupted. [H-14]
- interrupt flag register (IFR): A 16-bit memory-mapped register that flags pending interrupts. The IFR may be read to identify pending interrupts and written to clear selected interrupts. A 1 read from any IFR bit position indicates a pending interrupt. A 1 written to any IFR bit position clears the corresponding interrupt. A 0 written to any IFR bit position has no effect. At reset, the IFR is cleared. [H-14]
- interrupt mask register (IMR): A 16-bit memory-mapped register that masks external and internal interrupts. The IMR may be read and written to. A 1 written to any IMR bit position enables the corresponding interrupt (when INTM = 0). [H-14]
- interrupt mode (INTM) bit: A 1-bit field that globally masks or enables all interrupts. When INTM = 0, all unmasked interrupts are enabled. When INTM = 1, all maskable interrupts are disabled. INTM has no effect on the nonmaskable RS and NMI interrupts. At reset, INTM = 1.This bit is stored in status register 0 (ST0). [H-15]
- interrupt service routine (ISR): A module of code that is executed in response to a hardware or software interrupt. [H-15]
- interrupt vector pointer (IPTR) bits: A 5-bit field that identifies the 2K page where the interrupt vectors currently reside in the system. The IPTR lets you remap the interrupt vectors to RAM for boot-loaded operations. At reset, IPTR = 0. These bits are stored in the processor mode status reg- ister (PMST). [H-15]
- INTM: See interrupt mode (INTM) bit. [H-15]
- IOWSR: See I/O Port Wait-State Register (IOWSR). [H-15]
- IPTR: See interrupt vector pointer (IPTR) bits. [H-15]
- IREG: See instruction register (IREG). [H-15]
- ISR: See interrupt service routine (ISR). [H-15]

## L

- latency: The delay between when a condition occurs and when the device reacts to the condition. Also, in a pipeline, the delay between the execu- tion of two instructions that is necessary to ensure that the values used by the second instruction are correct. [H-15]
- LSB: least significant bit. The lowest-order bit in a word. [H-15]

## M

- maskable interrupts: A hardware interrupt that can be enabled or disabled through software. [H-15]
- MCM: See clock mode (MCM) bit. [H-15]
- MCS: See microcall stack (MCS). [H-15]
- memory map: A map of the addressable memory space accessed by the TMS320C5x processor partitioned according to functionality (memory, registers, etc.). [H-15]
- memory-mapped registers: The TMS320C5x processor has 96 registers mapped into page 0 of the data memory space. There are 28 core CPU registers, 17 peripheral registers, 16 input/output (I/O) port registers, and 35 reserved registers. [H-16]
- microcall stack (MCS): A single-word stack that temporarily stores the contents of the prefetch counter (PFC) while the PFC addresses data memory with the block move (BLDD/BLPD), multiply-accumulate (MAC/ MACD), and table read/write (TBLR/TBLW) instructions. [H-16]
- microprocessor/microcomputer (MP/MC) bit: A 1-bit field that indicates if on-chip ROM is mapped into program address space. When MP/ MC = 0, the on-chip ROM is enabled. When MP/MC = 1, the on-chip ROM is not addressable. At reset, the MP/MC bit is set to the value corre- sponding to the logic level on the MP/MC pin. The level on the MP/MC pin is sampled at reset only and has no effect until the next reset. This bit is stored in the processor mode status register (PMST). [H-16]
- mnemonic: An alphanumeric symbol designed to aid human memory; it commonly represents the operation code of an assembly language instruction name that the assembler translates into machine code. [H-16]
- MP/MC: See microprocessor/microcomputer (MP/MC) bit. [H-16]
- MSB: most significant bit. The highest-order bit in a word. [H-16]
- MULT: See multiplier (MULT). [H-16]
- multiplier (MULT): A 16-by-16-bit multiplier that generates a 32-bit product. The multiplier executes multiple operations in a single machine cycle and operates using either signed or unsigned 2s-complement arithmetic. The operand for the multiplier is specified by the value in temporary register 0 (TREG0). The result of the multiplier is stored in the product register (PREG). [H-16]

## N

- nested interrupt: A higher-priority interrupt that must be serviced before completion of the current interrupt service routine (ISR). An executing ISR can set the interrupt mask register (IMR) bits to prevent being sus- pended by another interrupt. [H-16]
- NDX: See enable extra index register (NDX) bit. [H-16]
- nonmaskable interrupt: An interrupt that can be neither masked by the in- terrupt mask register (IMR) nor disabled by the INTM bit of status register ST0. [H-16]

## O

- off-chip: A device external to the TMS320C5x device. [H-17]
- on-chip: An element or module of the TMS320C5x device. [H-17]
- opcode: operation code. In most cases, the first byte of the machine code that describes the type of operation and combination of operands to the central processing unit (CPU). [H-17]
- operand: The part of an instruction that designates where the central pro- cessing unit (CPU) will fetch or store data. The operand consists of the arguments, or parameters, of an assembly language instruction, assem- bler directive, or macro directive. [H-17]
- OV: See overflow (OV) bit. [H-17]
- overflow: A condition in which the result of an arithmetic operation exceeds the capacity of the register used to hold that result. [H-17]
- overflow (OV) bit: A 1-bit flag that indicates an arithmetic operation over- flow in the arithmetic logic unit (ALU). At reset, OV = 0.This bit is stored in status register 0 (ST0). [H-17]
- overflow mode (OVM) bit: A 1-bit field that determines if an overflow in the arithmetic logic unit (ALU) will wrap around or saturate. This bit is stored in status register 0 (ST0). [H-17]
- OVLY: See RAM overlay (OVLY) bit. [H-17]
- OVM: See overflow mode (OVM) bit. [H-17]

## P

- PAER: See block repeat program address end register (PAER). [H-17]
- parallel logic unit (PLU): A 16-bit logic unit that executes logic operations from either long immediate operands or the contents of the dynamic bit manipulation register (DBMR) directly upon data locations without affect- ing the contents of the accumulator (ACC) or product register (PREG). [H-17]
- PASR: See block repeat program address start register (PASR). [H-17]
- PC: See program counter (PC). [H-17]
- PCM: See pulse coded modulation mode (PCM) bit. [H-17]
- PDWSR: See program/data wait-state register (PDWSR). [H-18]
- PFC: See prefetch counter (PFC). [H-18]
- pipelining: A design technique for reducing the effective propagation delay per instruction operation by partitioning the operation into a series of four independent stages, each of which performs a portion of the operation. [H-18]
- PLU: See parallel logic unit (PLU). [H-18]
- PM: See product shift mode (PM) bits. [H-18]
- PMST: See processor mode status register (PMST). [H-18]
- pop: Action of removing a word from a stack. [H-18]
- POSTSCALER: postscaling shifter. A 0- to 7-bit left barrel shifter used to postscale data coming out of the accumulator (ACC). [H-18]
- PRD: See timer period register (PRD). [H-18]
- prefetch counter (PFC): A 16-bit register that prefetches program instruc- tions. The PFC contains the address of the instruction currently being prefetched and is updated when a new prefetch is initiated. [H-18]
- PREG: See product register (PREG). [H-18]
- PRESCALER: prescaling shifter. A 0- to 16-bit left barrel shifter used to prescale data coming into the arithmetic logic unit (ALU). This shifter is also used as a 0- to 16-bit right barrel shifter of the accumulator (ACC). The shift count is specified by a constant in the instruction or by the value in temporary register 1 (TREG1). [H-18]
- processor mode status register (PMST): A 16-bit memory-mapped regis- ter that contains status and control bits. [H-18]
- product register (PREG): A 32-bit register that holds the output from the multiplier. The high and low words of the PREG can be accessed individ- ually. See also multiplier (MULT). [H-18]
- product shift mode (PM) bits: A 2-bit field that defines the product shifter (P-SCALER) mode. These two bits determine the shift value (0-, 1-, 4-bit left shifter, 6-bit right shifter) for the output of the product register (PREG).These bits are stored in status register 1 (ST1). [H-18]
- program/data wait-state register (PDWSR): (For the TMS320C50, ’C51, and ’C53) a 16-bit memory-mapped register that specifies the number of wait states for the program and data space. The higher byte of PDWSR specifies the data space wait states and the lower byte specifies the pro- gram space wait states. At reset, PDWSR = FFFF. (For the TMS320C52, ’C56, and ’C57) a 16-bit memory-mapped register that specifies the number of wait states for the program, data, and input/ output (I/O) space. Bits 0–2 of PDWSR specify the program space wait states, bits 3–5 specify the data space wait states, bits 6–8 specify the I/O space wait states, and bits 9–15 are reserved. At reset, PDWSR = FFFF. [H-19]
- program controller: Logic circuitry that decodes instructions, manages the pipeline, stores the central processing unit (CPU) status, and decodes conditional operations. [H-19]
- program counter (PC): A 16-bit register that identifies the current state- ment in the program. The PC addresses program memory sequentially and always contains the address of the next instruction to be fetched. The PC contents are updated following each instruction decode opera- tion. [H-19]
- P-SCALER: Product Shifter. A 0-, 1-, or 4-bit left shifter that removes extra signed bits (gained in the multiply operation) when fixed-point arithmetic is used; or a 6-bit right shifter that scales the products down to avoid over- flow in the accumulation process. The shift mode is specified by the prod- uct shift mode (PM) bits. [H-19]
- PSC: See timer prescaler counter (PSC) bits. [H-19]
- pulse coded modulation mode (PCM) bit: A 1-bit field that enables/dis- ables the BSP transmitter. This bit is stored in the BSP control extension register (SPCE). [H-19]
- push: Action of placing a word onto a stack. [H-19]

## R

- RAM overlay (OVLY) bit: A 1-bit field that determines if on-chip single-ac- cess RAM is addressable in data memory space. At reset, OVLY = 0. This bit is stored in the processor mode status register (PMST). [H-19]
- receive buffer half received (RH) bit: A 1-bit flag that indicates which half of the receive buffer has been received. At reset, RH = 0. This bit is stored in the BSP control extension register (SPCE). [H-19]
- receive ready (RRDY) bit: A 1-bit flag that transitions from 0 to 1 to indicate the data receive shift register (RSR) contents have been copied to the data receive register (DRR) and that data can be read. A receive interrupt (RINT) is generated upon the transition. The RRDY bit can be polled in software in lieu of using serial port interrupts. This bit is stored in the serial port control register (SPC) and TDM serial port control register (TSPC). [H-20]
- receiver reset (RRST) bit: A 1-bit flag that resets the serial port receiver. At reset, RRST = 0. This bit is stored in the serial port control register (SPC) and TDM serial port control register (TSPC). [H-20]
- receive shift register full (RSRFULL) bit: A 1-bit flag that indicates if the serial port receiver has experienced overrun. This bit is stored in the seri- al port control register (SPC). [H-20]
- register: A group of bits used for temporarily holding data or for controlling or specifying the status of a device. [H-20]
- repeat counter register (RPTC): A 16-bit memory-mapped register that controls the repeated execution of a single instruction. [H-20]
- reset: A means to bring the central processing unit (CPU) to a known state by setting the registers and control bits to predetermined values and signaling execution to start at a specified address. [H-20]
- RH: See receive buffer half received (RH) bit. [H-20]
- RINT: See serial port receive interrupt (RINT) bit. [H-20]
- RPTC: See repeat counter register (RPTC). [H-20]
- RRDY: See receive ready (RRDY) bit. [H-20]
- RRST: See receiver reset (RRST) bit. [H-20]
- RSR: See data receive shift register (RSR). [H-20]
- RSRFULL: See receive shift register full (RSRFULL) bit. [H-20]

## S

- SAM: See shared-access mode (SAM). [H-20]
- SARAM: See single-access RAM (SARAM). [H-20]
- scratch-pad RAM: Block 2 (B2) on data memory page 0 in local data space (32 words) of DARAM. Scratch-pad RAM supports dual-access opera- tions and can be addressed via any data memory addressing mode. [H-20]
- serial port control register (SPC): A 16-bit memory-mapped register that contains status and control bits for the serial port interface. The SPC is identical to the time-division multiplexed serial port control register (TSPC), except that bit 0 is reserved for the TDM bit. [H-21]
- serial port interface: An on-chip full-duplex serial port interface that pro- vides direct serial communication to serial devices with a minimum of ex- ternal hardware, such as codecs and serial analog-to-digital (A/D) con- verters. Status and control of the serial port is specified in the serial port control register (SPC). [H-21]
- serial port receive interrupt (RINT) bit: A 1-bit flag that indicates the data receive shift register (RSR) contents have been copied to the data re- ceive register (DRR). This bit is stored in the interrupt flag register (IFR). [H-21]
- serial port transmit interrupt (XINT) bit: A 1-bit flag that indicates the the data transmit register (DXR) contents has been copied to the data trans- mit shift register (XSR). This bit is stored in the interrupt flag register (IFR). [H-21]
- shared-access mode (SAM): The mode that allows both the TMS320C57 and the host to access HPI memory. In this mode, asynchronous host accesses are synchronized internally and, in case of conflict, the host has access priority and the ’C57 waits one cycle. [H-21]
- shared-access mode (SMOD) bit: A 1-bit field that enables/disables the shared access mode (SAM). This bit is stored in the HPI control register (HPIC). See also shared-access mode (SAM) and host-only mode (HOM). [H-21]
- shifter: A unit that shifts bits in a word to the left or to the right. See also P-SCALER. [H-21]
- sign-extension: The process of filling the high-order bits of a number with the sign bit, when loading a 16-bit number into a 32-bit field. [H-21]
- sign-extension mode (SXM) bit: A 1-bit field that enables/disables sign ex- tension of an arithmetic operation. This bit is stored in status register 1 (ST1). [H-21]
- single-access RAM (SARAM): Memory space that only can be read from or written to in a single clock cycle. [H-21]
- SMOD: See shared-access mode (SMOD) bit. [H-21]
- Soft bit: A 1-bit field used in conjunction with the Free bit to determine the state of the serial port clock when a breakpoint is encountered in the high- level language debugger. At reset, Soft = 0. This bit is stored in the serial port control register (SPC) and TDM serial port control register (TSPC). [H-21]
- software interrupt: An interrupt caused by the execution of an INTR, NMI, or TRAP instruction. [H-22]
- SPC: See serial port control register (SPC). [H-22]
- SPCE: See BSP control extension register (SPCE). [H-22]
- stack: An 8-level-deep by 16-bit hardware stack used as a last-in, first-out memory for temporary variable storage; used during interrupt service routines (ISR) and calls to store the current program status. The area occupied by the stack is determined by the stack pointer and the application program. [H-22]
- status register: A 16-bit register that contains status and control bits. [H-22]
- SXM: See sign-extension mode (SXM) bit. [H-22]

## T

- TADD: See TDM address (TADD). [H-22]
- TC: See test/control (TC) bit. [H-22]
- TCLK: See TDM clock (TCLK). [H-22]
- TCR: See timer control register (TCR). [H-22]
- TCSR: See TDM channel select register (TCSR). [H-22]
- TDAT: See TDM data (TDAT). [H-22]
- TDDR: See timer divide-down register (TDDR) bits. [H-22]
- TDM: See time-division multiplexed (TDM) bit. [H-22]
- TDM address (TADD): A single, bi-directional address line that identifies which devices on the four-wire serial bus should read in the data on the TDM data (TDAT) line. [H-22]
- TDM channel select register (TCSR): A 16-bit memory-mapped register that specifies in which of the eight time slots (channels) a device on the four-wire serial bus is to transmit. A 1 in any one or more of bits 0–7 of the TCSR sets the device transmitter active during the corresponding time slot. Bits 8–15 are reserved. [H-22]
- TDM clock (TCLK): A single, bi-directional clock line for TDM operation. The TDM receive clock (TCLKR) and TDM transmit clock (TCLKX) pins are externally connected to form the TCLK line. [H-22]
- TDM data (TDAT): A single, bi-directional line from which all TDM data is carried. The TDM serial data receive (TDR) and TDM serial data transmit (TDX) pins are externally connected to form the TDAT line. [H-23]
- TDM data receive register (TRCV): A 16-bit memory-mapped register that holds serial data copied from the TDM receive shift register (TRSR). When multiprocessing is enabled (TDM = 1), the TRCV is no longer available for software access as a memory-mapped register. See also TDM data receive shift register (TRSR). [H-23]
- TDM data receive shift register (TRSR): A 16-bit register that holds serial data received from the TDM data (TDAT) line. See also TDM data receive register (TRCV). [H-23]
- TDM data transmit register (TDXR): A 16-bit memory-mapped register that holds serial data to be copied to the data transmit shift register (XSR). When multiprocessing is enabled (TDM = 1), the TDXR is no longer available for software access as a memory-mapped register. See also data transmit shift register (XSR). [H-23]
- TDM receive address register (TRAD): A 16-bit memory-mapped register that contains various information regarding the status of the TDM ad- dress (TADD) line and verifies the relationship between instruction cycles and TDM port timing. [H-23]
- TDM receive interrupt (TRNT) bit: A 1-bit flag that indicates the TDM data receive shift register (TRSR) contents have been copied to the TDM data receive register (TRCV). This bit is stored in the interrupt flag register (IFR). [H-23]
- TDM receive/transmit address register (TRTA): A 16-bit memory- mapped register that specifies to which device(s) on the four-wire serial bus a given device can transmit. The lower byte of the TRTA specifies the receive address (RA) of the device and the higher byte specifies the transmit address (TA). The address is sent over the TDM address (TADD) line. [H-23]
- TDM serial port control register (TSPC): A 16-bit memory-mapped register that contains status and control bits for the TDM serial port inter- face. The TSPC is identical to the serial port interface control register (SPC), except for the TDM bit 0. [H-23]
- TDM transmit interrupt (TXNT) bit: A 1-bit flag that indicates the TDM data transmit register (TDXR) contents have been copied to the data transmit shift register (XSR). This bit is stored in the interrupt flag register (IFR). [H-23]
- TDXR: See TDM data transmit register (TDXR). [H-23]
- temporary register: A 16-bit register that holds a temporary data value. See alsoTREG0, TREG1, and TREG2. [H-24]
- test/control (TC) bit: A 1-bit flag that stores the results of the arithmetic logic unit (ALU) or parallel logic unit (PLU) test bit operations. The TC bit is af- fected by the APL, BIT, BITT, CMPR, CPL, LST #1, NORM, OPL, and XPL instructions. The status of the TC bit influences the execution of the conditional branch, call, and return instructions. This bit is stored in sta- tus register 1 (ST1). [H-24]
- TIM: See timer counter register (TIM). [H-24]
- time-division multiplexed (TDM) bit: A 1-bit field that enables/disables the TDM serial port. This bit is stored in the TDM serial port control register (TSPC). [H-24]
- time-division multiplexing (TDM): The process by which a single serial bus is shared by up to eight TMS320C5x devices with each device taking turns to communicate on the bus. There are a total of eight time slots (channels) available. During a time slot, a given device may talk to any combination of devices on the bus. [H-24]
- timer control register (TCR): A 16-bit memory-mapped register that con- tains status and control bits for the on-chip timer. [H-24]
- timer counter register (TIM): A 16-bit memory-mapped register that speci- fies the current count for the on-chip timer. The TIM is decremented once after each timer prescaler counter (PSC) decrement past 0. When the TIM is decremented past 0 or the timer is reset, the TIM is loaded with the contents of the timer period register (PRD) and an internal timer inter- rupt (TINT) is generated. [H-24]
- timer divide-down register (TDDR) bits: A 4-bit field that specifies the tim- er divide-down ratio (period) for the on-chip timer. When the timer pres- caler counter (PSC) is decremented past 0, the PSC is loaded with the contents of the TDDR. At reset, TDDR = 0000. These bits are stored in the timer control register (TCR). [H-24]
- timer interrupt (TINT) bit: A 1-bit flag that indicates the timer counter regis- ter (TIM) has decremented past 0. This bit is stored in the interrupt flag register (IFR). [H-24]
- timer period register (PRD): A 16-bit memory-mapped register that speci- fies the period for the on-chip timer. When the timer counter register (TIM) is decremented past 0, the TIM is loaded with the contents of the PRD. [H-24]
- timer prescaler counter (PSC) bits: A 4-bit field that specifies the count for the on-chip timer. When the PSC is decremented past 0 or the timer is reset, the PSC is loaded with the contents of the timer divide-down regis- ter (TDDR) and the timer counter register (TIM) is decremented. These bits are stored in the timer control register (TCR). [H-25]
- timer reload (TRB) bit: A 1-bit flag that resets the on-chip timer. When TRB = 1, the timer counter register (TIM) is loaded with the value in the timer period register (PRD) and the timer prescaler counter (PSC) is loaded with the value of the timer divide-down register (TDDR) bits. This bit is stored in the timer control register (TCR). [H-25]
- timer stop status (TSS) bit: A 1-bit flag that stops and restarts the on-chip timer. At reset, TSS = 0 and the timer immediately starts timing. This bit is stored in the timer control register (TCR). [H-25]
- TINT: See timer interrupt (TINT) bit. [H-25]
- TRAD: See TDM receive address register (TRAD). [H-25]
- transmit buffer half transmitted (XH) bit: A 1-bit flag that indicates which half of transmit buffer transmitted. The XH bit can be read when an XINT interrupt occurs (interrupt program or IFR polling). At reset, XH = 0. This bit is stored in the BSP control extension register (SPCE). [H-25]
- transmit mode bit (TXM) bit: A 1-bit field that specifies the source of the frame synchronization transmit (FSX) pulse. At reset, TXM = 0. This bit is stored in the serial port control register (SPC) and TDM serial port con- trol register (TSPC). [H-25]
- transmit ready (XRDY) bit: A 1-bit flag that transitions from 0 to 1 to indicate the data transmit register (DXR) contents have been copied to the data transmit shift register (XSR) and that data is ready to be loaded with a new data word. A transmit interrupt (XINT) is generated upon the transi- tion. The XRDY bit can be polled in software in lieu of using serial port interrupts. This bit is stored in the serial port control register (SPC) and TDM serial port control register (TSPC). [H-25]
- transmit shift register empty (XSREMPTY) bit: A 1-bit flag that indicates if the serial port transmitter has experienced underflow. This bit is stored in the serial port control register (SPC). [H-25]
- transmitter reset (XRST) bit: A 1-bit flag that resets the serial port transmit- ter. At reset, XRST = 0. This bit is stored in the serial port control register (SPC) and TDM serial port control register (TSPC). [H-25]
- TRB: See timer reload (TRB) bit. [H-25]
- TRCV: See TDM data receive register (TRCV). [H-26]
- TREG0: temporary register 0. A 16-bit memory-mapped register that holds an operand for the multiplier. See also multiplier (MULT). [H-26]
- TREG1: temporary register 1. A 5-bit memory-mapped register that holds a dynamic prescaling shift count for data inputs to the arithmetic logic unit (ALU). See also PRESCALER. [H-26]
- TREG2: temporary register 2. A 4-bit memory-mapped register that holds a dynamic bit pointer for the BITT instruction. [H-26]
- TRM: See enable multiple TREGs (TRM) bit. [H-26]
- TRNT: See TDM receive interrupt (TRNT) bit. [H-26]
- TRSR: See TDM data receive shift register (TRSR). [H-26]
- TRTA: See TDM receive/transmit address register (TRTA). [H-26]
- TSPC: See TDM serial port control register (TSPC). [H-26]
- TSS: See timer stop status (TSS) bit. [H-26]
- TXM: See transmit mode (TXM) bit. [H-26]
- TXNT: See TDM transmit interrupt (TXNT) bit. [H-26]

## W

- wait state: A period of time that the CPU must wait for external program, data, or I/O memory to respond when reading from or writing to that ex- ternal memory. The CPU waits one extra cycle (one CLKOUT1 cycle) for every wait state. [H-26]
- wait-state control register (CWSR): A 5-bit memory-mapped register that controls the mapping of the program/data wait-state register (PDWSR), the input/output port wait-state register (IOWSR), and the number of wait states. At reset, CWSR = 011112. [H-26]
- wait-state generator: A program that can be modified to generate a limited number of wait states for a given off-chip memory space (lower program, upper program, data, or I/O). Wait states are set in the wait-state control register (CWSR). [H-26]
- warm boot: The process by which the processor transfers control to the entry address of a previously-loaded program. [H-26]
- word: A word, as defined in this document, consists of a sequence of 16 ad- jacent bits (two bytes). [H-26]

## X

- XF: See external flag (XF) pin status bit. [H-27]
- XH: See transmit buffer half transmitted (XH) bit. [H-27]
- XINT: See serial port transmit interrupt (XINT) bit. [H-27]
- XRDY: See transmit ready (XRDY) bit. [H-27]
- XRST: See transmitter reset (XRST) bit. [H-27]
- XSR: See data transmit shift register (XSR). [H-27]
- XSREMPTY: See transmit shift register empty (XSREMPTY) bit. [H-27]

## Z

- zero fill: A method of filling the low- or high-order bits with zeros when a shift occurs. [H-27]

---

# Appendix I — Summary of Updates in This Document

[App I intro, PDF p.725 (printed p.I-1)] "This appendix provides a summary
of the updates in this version of the document. Updates within paragraphs
appear in a bold typeface." (Bold typeface is lost in text extraction.)
All 38 change entries are transcribed below: the manual page changed, the
change as stated, and the Appendix I location (PDF p. / printed p.I-N).
The figures and tables reprinted in Appendix I to illustrate the changes are
NOT re-reprinted here — only the change statement and the new value/content
where Appendix I states it. One exception: the reprinted Table 8–6 on
printed p.I-8 is garbled in the extraction (border glyphs), so its cell values
are not transcribed — see the [UNVERIFIED] note on that row.

| Manual page changed | Change (as stated in Appendix I) | App I location |
|---|---|---|
| 3–3 | Fig. 3–1 (’C5x CPU block diagram): in the bottom half, the auxiliary register file MUX output now connects with the trailing wire bus found on the data bus. | PDF p.725 (I-1) |
| 4–11 | Table 4–5 (ST0 bit summary): reset values for the ARP bit and the OVM bit changed to "X" — i.e. no reset value for ARP or OVM. | PDF p.726 (I-2) |
| 4–12 | Table 4–5 (ST0, continued): reset value for the DP bit changed to "X" — i.e. no reset value for DP. | PDF p.726 (I-2) |
| 4–13 | Table 4–6 (ST1 bit summary): reset value for the ARB bit and the TC bit changed so they have no reset value. | PDF p.727 (I-3) |
| 5–2 | Fig. 5–1 (direct addressing): page 0 length changed to "128-WORD PAGE". | PDF p.728 (I-4) |
| 5–22 | Example 5–13 (circular addressing): two new lines added at the beginning — `mar *,ar6` and `ldp #,0`. | PDF p.729 (I-5) |
| 6–32 | ADD instruction: second operand changed to 0 ≤ shift ≤ 16 (defaults to 0). | PDF p.730 (I-6) |
| 6–44 | AND instruction: fourth operand changed to 0 ≤ shift ≤ 16. | PDF p.730 (I-6) |
| 6–83 | BSAR instruction: operand changed to 1 ≤ shift ≤ 16. | PDF p.730 (I-6) |
| 6–85 | CALAD instruction: description changed — PC incremented by 3 and pushed onto TOS; then the one 2-word or two 1-word instructions following CALAD are fetched and executed before the call; then ACCL is loaded into the PC; CALAD is used for computed subroutine calls. | PDF p.730 (I-6) |
| 6–87 | CALLD instruction: description changed — PC incremented by 4 and pushed onto TOS; then the one 2-word or two 1-word instructions following CALLD are fetched and executed before the call; then the program memory address (pma) is loaded into the PC; AR and ARP are modified as specified; pma may be symbolic or numeric. | PDF p.730 (I-6) |
| 6–91 | CCD instruction: description changed — if the specified conditions are met, PC incremented by 4 and pushed onto TOS; then the delayed instruction(s) following CCD are fetched and executed before the call; then pma is loaded into the PC; not all condition combinations are meaningful; NTC, TC, and BIO conditions are mutually exclusive; if conditions are not met, control passes to the next instruction; CCD functions as CALLD if all conditions are true. | PDF p.731 (I-7) |
| 6–103 | CRLT instruction: opcode changed to reflect new values for bits 2, 1, and 0 (opcode bits 15–0 as reprinted: 1 0 1 1 1 1 0 0 0 1 1 1 0 0). | PDF p.731 (I-7) |
| 6–115 | LACC instruction: third operand changed to 0 ≤ shift ≤ 16 (defaults to 0). | PDF p.731 (I-7) |
| 6–127 | "Cycles for a Single Instruction (short immediate addressing)" table changed: ROM 2, DARAM 2, SARAM 2, external memory 2+pcode. (Instruction not named in Appendix I; p.6-127 is the LDP description per Table B–2 — INFERENCE.) | PDF p.731 (I-7) |
| 6–129 | Same cycles-table change as 6–127: ROM 2, DARAM 2, SARAM 2, external memory 2+pcode. (Instruction not named in Appendix I.) | PDF p.731 (I-7) |
| 6–188 | OR instruction: fourth operand changed to 0 ≤ shift ≤ 16. | PDF p.731 (I-7) |
| 6–261 | SUB instruction: second operand changed to 0 ≤ shift ≤ 16 (defaults to 0). | PDF p.732 (I-8) |
| 6–278 | Example 1 data memory address changed from 1905h to 1005h. (p.6-278 is the XC description per Table B–2 — INFERENCE.) | PDF p.732 (I-8) |
| 6–282 | XOR instruction: fourth operand changed to 0 ≤ shift ≤ 16. | PDF p.732 (I-8) |
| 8–6 | Fig. 8–6: the word "Off-chip" changed to "Reserved" on the program memory map for the range 0040h–8000h. | PDF p.732 (I-8) |
| 8–11 | Table 8–6 (’C57S program memory configuration): values in the Off-Chip column changed for the first and fifth rows. [UNVERIFIED — reprinted Table 8–6 extraction garbled (border glyphs), App I, PDF p.732 (printed p.I-8); the new Off-Chip values are not transcribed.] | PDF p.732 (I-8) |
| 8–32 | Last sentence in the fourth bullet changed: 32K words of global data memory are enabled initially in data spaces 8000h–FFFFh; after the code transfer is complete, the global memory is disabled before control is transferred to the destination address in program memory. | PDF p.732 (I-8) |
| 9–10 | Table 9–4 (TCR bit summary): sentences after Soft=0 and Soft=1 changed — when the Free bit is cleared, the Soft bit selects the emulation mode: Soft=0, the timer stops immediately; Soft=1, the timer stops after decrementing to zero. Added sentence for the TSS bit: at reset TSS is cleared and the timer immediately starts timing; due to timer logic implementation, two successive writes of one to the TSS bit are required to properly stop the timer. | PDF p.732 (I-8) |
| 9–11 | Last sentence in the Notes section deleted and replaced: the current value in the timer can be read by reading the TIM; the PSC can be read by reading the TCR; because it takes two instructions to read both registers, there may be a change between the two reads as the counter decrements, so for precise timing measurements it may be more accurate to stop the timer; due to timer logic implementation, two instructions are also required to properly stop the timer — two successive writes of one to the TSS bit should be made when the timer must be stopped. | PDF p.733 (I-9) |
| 9–62 | Fig. 9–35 (ABU block diagram): the XINT and RINT labels in the lower right portion changed (reprinted figure shows WXINT/BXNT and WRINT/BRNT). | PDF p.734 (I-10) |
| 9–63 | Last sentence in the first paragraph changed: the internal ’C5x memory used for autobuffering consists of a 2K-word block of single-access memory configurable as data, program, or both (as with other single-access memory blocks); it can also be used by the CPU as general-purpose storage, but it is the only memory block in which autobuffering can occur; since the BSP is implemented on several different TMS320 devices, the actual base address of the ABU memory may not be the same in all cases; the 2K-word block of BSP memory is located at 800h–FFFh in data memory or at 8000h–87FFh in program memory as specified by the RAM and OVLY control bits. | PDF p.734 (I-10) |
| A–4 | Fig. A–2: signal name on pin 80 changed to R/W. | PDF p.735 (I-11) |
| A–6 | Fig. A–3: signal name on pin 108 changed to X2/CLKIN. | PDF p.736 (I-12) |
| A–7 | Table A–3: signal name on pin 108 changed to X2/CLKIN; signal names reordered. | PDF p.737 (I-13) |
| A–10 | Fig. A–5: signal names corrected for pins 1–16, 28–45, 57–71, and 78–141; signal name on pin 122 changed to X2/CLKIN. | PDF p.738 (I-14) |
| A–11 | Table A–5: signal names corrected for pins 1–16, 28–45, 57–71, and 78–141; signal name on pin 122 changed to X2/CLKIN; signal names reordered. | PDF p.739 (I-15) |
| D–2 | Fig. D–1: PD pin 5 changed from +5V to VDD. | PDF p.740 (I-16) |
| D–5 | Fig. D–2: voltages changed from +5V to VDD. | PDF p.741 (I-17) |
| D–7 | Fig. D–4: voltages changed from +5V to VDD. | PDF p.742 (I-18) |
| D–8 | Fig. D–5: voltages changed from +5V to VDD. | PDF p.743 (I-19) |
| D–9 | Fig. D–6: voltages changed from +5V to VDD. | PDF p.744 (I-20) |
| D–10 | Fig. D–7: voltages changed from +5V to VDD. | PDF p.744 (I-20) |

## Unverified / extraction notes (Appendices C–I)

- Appendix C, Figures C–1–C–5: dimension/thermal values transcribed from the
  layout extraction; the pin-diagram figures (C–3) are spatially scrambled in
  extraction and their pin-by-pin content is not transcribed — the prose
  rules in §C.1 carry the migration content. [UNVERIFIED — figure pin
  detail, App C, PDF pp.651–656]
- Appendix D, Figure D–2 (pod interface schematic): component values are the
  legible ones from the extraction; the schematic was not rendered and
  re-read. [UNVERIFIED — schematic detail, App D, PDF p.673 (printed p.D-5)]
- Appendix G: Figure G–1/G–2 legends transcribed from the layout extraction;
  the diagram geometry itself is not reproduced.
- Appendix H: bold typeface (if any) is lost in extraction; no garbled
  entries were found — all 352 entries parsed cleanly.
- Appendix I: the reprinted Table 8–6 (p.I-8) is garbled in extraction
  (see row above); the reprinted figures/tables are otherwise legible but
  are summarised, not re-reprinted, by design.
