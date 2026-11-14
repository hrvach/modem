# Chapter 1 — Introduction (TMS320C5x User's Guide, SPRU056D)

**Source:** `~/workspace/user/files/spru056d.pdf` — SPRU056D, June 1998, 764 pp., SHA-256 `a31e285f1be9fe87064e914de7bce6c96a99dd53bea3f3882c9fbe56bd45ce30`.
Range distilled: PDF pp.34–42 / printed pp.1-1–1-9 (§1.1–§1.3).
**Scope: C5x-family-generic.** Nothing in this chapter is C51-specific except where a device name is given in parentheses; a C51 roll-up is at the end. This chapter contains no C51-only discussion, no register map, no instruction detail.

**Citation convention:** every claim carries manual section + table/figure + PDF page / printed page. "PDF p." = 1-based PDF page; "printed" = the manual's own page number.

## 1.1 TMS320 family overview (§1.1, PDF p.35 / printed 1-2)

- The TMS320 family consists of two types of single-chip DSPs: 16-bit fixed-point and 32-bit floating-point; they combine the flexibility of high-speed controllers with the numerical capability of array processors, as inexpensive alternatives to custom VLSI and multichip bit-slice processors (§1.1, PDF p.35 / printed 1-2).
- Family traits claimed: very flexible instruction set; inherent operational flexibility; high-speed performance; innovative parallel architectural design; cost-effectiveness (§1.1, PDF p.35 / printed 1-2).

### 1.1.1 History, development, advantages (§1.1.1, PDF p.35 / printed 1-2)

- 1982: TI introduced the TMS32010, the first fixed-point DSP in the family; Electronic Products magazine named it "Product of the Year" before year-end; it became the model for future generations (§1.1.1, PDF p.35 / printed 1-2).
- Eight generations (§1.1.1, PDF p.35 / printed 1-2):

| Class | Generations |
|---|---|
| Fixed-point | 'C1x, 'C2x, 'C2xx, 'C5x, 'C54x |
| Floating-point | 'C3x, 'C4x |
| Multiprocessor | 'C8x |

- Source code is upward compatible from one fixed-point generation to the next fixed-point generation **except for the 'C54x**, and from one floating-point generation to the next (§1.1.1, PDF p.35 / printed 1-2).
- Each generation has a CPU plus varied on-chip memory/peripheral configurations for spin-off devices; integrating memory and peripherals on-chip reduces system cost and board space (§1.1.1, PDF p.35 / printed 1-2).
- Figure 1–1, "Evolution of the TMS320 Family" (PDF p.36 / printed 1-3): [UNVERIFIED — figure is graphical; extraction contains no data values, no axis numbers, no per-generation performance figures. No performance numbers from this figure are used anywhere in this file.]

### 1.1.2 Typical applications (§1.1.2, Figure 1–2, PDF p.37 / printed 1-4)

Condensed from Figure 1–2 (full list in the manual; categories as printed):

| Category | Applications listed |
|---|---|
| Automotive | Adaptive ride control, antiskid brakes, cellular telephones, digital radios, engine control, global positioning, navigation, vibration analysis, voice commands |
| Consumer | Digital radios/TVs, educational toys, music synthesizers, power tools, radar detectors, solid-state answering machines |
| Control | Disk drive control, engine control, laser printer control, motor control, robotics control, servo control |
| General-purpose | Adaptive filtering, convolution, correlation, digital filtering, FFTs, Hilbert transforms, waveform generation, windowing |
| Graphics/imaging | 3-D rotation, animation/digital map, homomorphic processing, pattern recognition, image enhancement, image compression/transmission, robot vision, workstations |
| Industrial | Numeric control, power-line monitoring, robotics, security access |
| Instrumentation | Digital filtering, function generation, pattern matching, phase-locked loops, seismic processing, spectrum analysis, transient analysis |
| Medical | Diagnostic equipment, fetal monitoring, hearing aids, patient monitoring, prosthetics, ultrasound equipment |
| Military | Image processing, missile guidance, navigation, radar processing, radio frequency modems, secure communications, sonar processing |
| Telecommunications | 1200- to 19200-bps modems, adaptive equalizers, ADPCM transcoders, cellular telephones, channel multiplexing, data encryption, digital PBXs, digital speech interpolation (DSI), DTMF encoding/decoding, echo cancellation, fax, line repeaters, speaker phones, spread spectrum communications, video conferencing, X.25 packet switching, personal digital assistants (PDA), personal communications systems (PCS) |
| Voice/speech | Speech enhancement, speech recognition, speech synthesis, speaker verification, speech vocoding, voice mail, text-to-speech |

## 1.2 TMS320C5x overview (§1.2, PDF p.38 / printed 1-5)

- The 'C5x generation consists of the 'C50, 'C51, 'C52, 'C53, 'C53S, 'C56, 'C57, and 'C57S DSPs, fabricated in CMOS; architectural design based on the 'C25 (§1.2, PDF p.38 / printed 1-5). **See Contradiction C-1:** no plain 'C56 or 'C57 device rows exist in Table 1–1 — only 'LC56 and 'LC57.
- Advanced Harvard architecture (separate buses for program and data memory); CPU with application-specific hardware logic, on-chip peripherals, on-chip memory, highly specialized instruction set (§1.2, PDF p.38 / printed 1-5).
- Designed to execute **up to 50 million instructions per second (MIPS)** (§1.2, PDF p.38 / printed 1-5).
- Spin-off devices combining the 'C5x CPU with customized on-chip memory/peripheral configurations may be developed for special applications (§1.2, PDF p.38 / printed 1-5).
- Advantages listed (§1.2, PDF p.38 / printed 1-5): enhanced TMS320 architecture for performance/versatility; modular architecture for fast spin-off development; advanced IC processing for performance and low power; source-code compatibility with 'C1x, 'C2x, 'C2xx for upgrades; enhanced instruction set for faster algorithms and optimized high-level-language operation; reduced power consumption and increased radiation hardness from new static design techniques.
- The 'C5x CPU is based on the 'C25 CPU with additional architectural enhancements allowing it to run **twice as fast as 'C2x devices**; source code upward compatible between devices (Ch.1 intro, PDF p.34 / printed 1-1).

### Device list as printed on the chapter title page (Ch.1 intro, PDF p.34 / printed 1-1)

Totals are rounded — see Contradiction C-6. Exact per-device figures are in Table 1–1 below.

| Device | On-chip RAM (as printed) | On-chip ROM (as printed) |
|---|---|---|
| TMS320C50/LC50 | 10K words | 2K words |
| TMS320C51/LC51 | 2K words | 8K words |
| TMS320C52/LC52 | 1K words | 4K words |
| TMS320C53/LC53 | 4K words | 16K words |
| TMS320C53S/LC53S | 4K words | 16K words |
| TMS320LC56 | 7K words | 32K words |
| TMS320LC57 | 7K words | 32K words |
| TMS320C57S/LC57S | 7K words | 2K words |

**See Contradiction C-4:** this list omits 'LC57S as a separate entry (it appears in Table 1–1, Table 2–1, Table 2–2) and gives 8 device lines vs. Table 1–1's 18 device/package rows.

### Table 1–1. Characteristics of the 'C5x DSPs (§1.2, Table 1–1, PDF p.39 / printed 1-6) — full transcription

Columns as printed: Device ID | DARAM† | SARAM‡ | ROM | Serial I/O ports | Parallel I/O ports◊ | Power supply (V) | Cycle time (ns) | Package type.
Footnotes (verbatim, Table 1–1, PDF p.39 / printed 1-6): † Dual-access RAM (DARAM); ‡ Single-access RAM (SARAM); § ROM bootloader available; ¶ Includes time-division multiplexed (TDM) serial port; # Includes buffered serial port (BSP); || Includes host port interface (HPI); ◊ Sixteen of the 64K parallel I/O ports are memory mapped; package footnotes: d = 20×20×3.8 mm bumpered quad flat-pack (BQFP); k = 14×14×1.4 mm thin quad flat-pack (TQFP); h = 14×20×2.7 mm quad flat-pack (QFP); D = 20×20×1.4 mm thin quad flat-pack (TQFP).
**See Contradiction C-7:** footnote || is defined but no row visibly carries the || marker in either the `-layout` or `-raw` extraction (C57S/LC57/LC57S rows read "64Kk", where k is the TQFP package footnote). HPI attribution therefore rests on §2.4.5 and Table 2–1, not on Table 1–1.

| Device | Pkg ID | DARAM (words) | SARAM (words) | ROM (words) | Serial ports | Parallel ports | Supply (V) | Cycle time (ns) | Package |
|---|---|---|---|---|---|---|---|---|---|
| 'C50 | PQ | 1056 | 9K | 2K§ | 2¶ | 64K | 5 | 50/35/25 | 132-pin BQFP |
| 'LC50 | PQ | 1056 | 9K | 2K§ | 2¶ | 64K | 3.3 | 50/40/25 | 132-pin BQFP |
| 'C51 | PQ | 1056 | 1K | 8K§ | 2¶ | 64K | 5 | 50/35/25/20 | 132-pin BQFP |
| 'C51 | PZ | 1056 | 1K | 8K§ | 2¶ | 64K | 5 | 50/35/25/20 | 100-pin TQFP |
| 'LC51 | PQ | 1056 | 1K | 8K§ | 2¶ | 64K | 3.3 | 50/40/25 | 132-pin BQFP |
| 'LC51 | PZ | 1056 | 1K | 8K§ | 2¶ | 64K | 3.3 | 50/40/25 | 100-pin TQFP |
| 'C52 | PJ | 1056 | — | 4K§ | 1 | 64K | 5 | 50/35/25/20 | 100-pin QFP |
| 'C52 | PZ | 1056 | — | 4K§ | 1 | 64K | 5 | 50/35/25/20 | 100-pin TQFP |
| 'LC52 | PJ | 1056 | — | 4K§ | 1 | 64K | 3.3 | 50/40/25 | 100-pin QFP |
| 'LC52 | PZ | 1056 | — | 4K§ | 1 | 64K | 3.3 | 50/40/25 | 100-pin TQFP |
| 'C53 | PQ | 1056 | 3K | 16K§ | 2¶ | 64K | 5 | 50/35/25 | 132-pin BQFP |
| 'C53S | PZ | 1056 | 3K | 16K§ | 2 | 64K | 5 | 50/35/25 | 100-pin TQFP |
| 'LC53 | PQ | 1056 | 3K | 16K§ | 2¶ | 64K | 3.3 | 50/40/25 | 132-pin BQFP |
| 'LC53S | PZ | 1056 | 3K | 16K§ | 2 | 64K | 3.3 | 50/40/25 | 100-pin TQFP |
| 'LC56 | PZ | 1056 | 6K | 32K | 2# | 64K | 3.3 | 50/35/25 | 100-pin TQFP |
| 'C57S | PGE | 1056 | 6K | 2K§ | 2# | 64K | 5 | 50/35/25 | 144-pin TQFP |
| 'LC57 | PBK | 1056 | 6K | 32K | 2# | 64K | 3.3 | 50/35/25 | 128-pin TQFP |
| 'LC57S | PGE | 1056 | 6K | 2K§ | 2# | 64K | 3.3 | 50/35 | 144-pin TQFP |

Reading notes from Table 1–1 (PDF p.39 / printed 1-6):
- Every device has 1056 words DARAM; SARAM varies 0 ('C52/'LC52 only) / 1K / 3K / 6K / 9K.
- "Serial ports" counts total serial ports: 2¶ = 1 general-purpose + 1 TDM; 2# = 1 general-purpose + 1 BSP; 2 (no mark, 'C53S/'LC53S) = 2 general-purpose; 1 ('C52/'LC52) = 1 general-purpose only. This reading is confirmed by Table 2–1 (§2.4.4, PDF p.51 / printed 2-9).
- ROM bootloader (§) is marked available on all ROMs **except** 'LC56 and 'LC57 (32K ROM, no §). See Contradiction C-5.
- Cycle times: 20 ns appears only on the 'C51 (PQ/PZ) and 'C52 (PJ/PZ) rows; 'LC51/'LC52 fastest is 25 ns; 'LC57S fastest is 35 ns (50/35 only). 50 ns is the slowest grade on every row.
- 'C57S and 'LC57S are the only 144-pin parts; 'LC57 is the only 128-pin part.

## 1.3 TMS320C5x key features (§1.3, PDF pp.40–42 / printed 1-7–1-9)

Intro rule (§1.3, PDF p.40 / printed 1-7): where a feature is exclusive to a particular device, the device name is enclosed in parentheses after that feature.

### Compatibility, speed, power (§1.3, PDF p.40 / printed 1-7)

| Feature | Value |
|---|---|
| Compatibility | Source-code compatible with 'C1x, 'C2x, 'C2xx devices |
| Speed | 20-/25-/35-/50-ns single-cycle fixed-point instruction execution time (50/40/28.6/20 MIPS) |
| Power | 3.3-V and 5-V static CMOS technology, two power-down modes; power consumption control with IDLE1 and IDLE2 instructions |

### Memory (§1.3, PDF p.40 / printed 1-7)

| Feature | Value |
|---|---|
| Max addressable external memory | 224K-word × 16-bit (64K-word program, 64K-word data, 64K-word I/O, 32K-word global memory) |
| DARAM | 1056-word × 16-bit dual-access on-chip data RAM (all devices) |
| SARAM | 9K-word × 16-bit ('C50); 1K-word ('C51); 3K-word ('C53, 'C53S); 6K-word ('LC56, 'C57S, 'LC57). No SARAM entry for 'C52 — consistent with Table 1–1 "—". |
| Boot ROM | 2K-word × 16-bit single-access on-chip boot ROM ('C50, 'C57S) |
| Program ROM | 8K-word ('C51); 4K-word ('C52); 16K-word ('C53, 'C53S); 32K-word ('LC56, 'LC57) |

### CPU (§1.3, PDF p.41 / printed 1-8)

| Block | Detail |
|---|---|
| CALU | 32-bit ALU, 32-bit accumulator (ACC), 32-bit accumulator buffer (ACCB); 16-bit × 16-bit parallel multiplier with 32-bit product; 0- to 16-bit left and right data barrel shifters and a 64-bit incremental data shifter |
| PLU | 16-bit parallel logic unit |
| ARAU | Dedicated auxiliary register arithmetic unit for indirect addressing |
| Auxiliary registers | Eight |

### Program control (§1.3, PDF p.41 / printed 1-8)

- 8-level hardware stack; 4-deep pipelined operation for delayed branch, call, and return instructions; eleven shadow registers for storing strategic CPU-controlled registers during an interrupt service routine (ISR); extended hold operation for concurrent external DMA of external memory or on-chip RAM; two indirectly addressed circular buffers for circular addressing.

### Instruction set (§1.3, PDF p.41 / printed 1-8)

Single-cycle multiply/accumulate instructions; single-instruction repeat and block repeat operations; block memory move instructions; memory-mapped register load and store instructions; conditional branch and call instructions; delayed execution of branch and call instructions; fast return from interrupt instructions; index-addressing mode; bit-reversed index-addressing mode for radix-2 FFTs.

### On-chip peripherals (§1.3, PDF p.42 / printed 1-9)

| Peripheral/feature | Devices named in §1.3 |
|---|---|
| 64K parallel I/O ports (16 memory-mapped) | all |
| Sixteen software-programmable wait-state generators for program, data, and I/O memory spaces | all |
| Interval timer with period, control, and counter registers for software stop, start, reset | all |
| PLL clock generator with internal oscillator or external clock source | all |
| Multiple PLL clocking option (x1, x2, x3, x4, x5, x9, depending on the device) | per-device factors not tabulated in Ch.1–2 — [UNVERIFIED which factor applies to which device; no per-device PLL table in Chapters 1–2] |
| Full-duplex synchronous serial port for direct communication between the 'C5x and another serial device | all (≥1 per device) |
| TDM serial port | 'C50, 'C51, 'C53 |
| Buffered serial port (BSP) | 'LC56, 'C57S, 'LC57 — see Contradiction C-3 (§2.4.7 names "'C56 and 'C57 devices") |
| 8-bit parallel host port interface (HPI) | 'C57, 'C57S — see Contradiction C-2 (§2.4.5 and Table 2–1 name 'C57S/'LC57S and 'LC57 instead) |

### Test/emulation (§1.3, PDF p.42 / printed 1-9)

- On-chip scan-based emulation logic (all, as listed without device qualifier).
- IEEE JTAG Standard 1149.1 boundary scan logic ('C50, 'C51, 'C53, 'C57S). See Contradiction C-10: §2.5 / Table 2–2 extend boundary scan to the LC counterparts ('LC50, 'LC51, 'LC53, 'LC57S); §1.3's list is abbreviated shorthand.

### Packages (§1.3, PDF p.42 / printed 1-9)

- 100-pin QFP ('C52); 100-pin TQFP ('C51, 'C52, 'C53S, 'LC56); 128-pin TQFP ('LC57); 132-pin BQFP ('C50, 'C51, 'C53); 144-pin TQFP ('C57S). See Contradiction C-8: LC variants ('LC50, 'LC51, 'LC52, 'LC53, 'LC53S, 'LC57S) are omitted from this list; Table 1–1 is normative for packages.

## C51 at a glance (from this chapter only)

| Attribute | 'C51 / 'LC51 value |
|---|---|
| DARAM / SARAM / ROM | 1056 words / 1K words / 8K words, ROM bootloader available (§) (Table 1–1, PDF p.39 / printed 1-6) |
| Serial ports | 2 total: 1 general-purpose + 1 TDM (Table 1–1 "2¶", PDF p.39 / printed 1-6); no BSP, no HPI |
| Parallel I/O | 64K ports, 16 memory-mapped (§1.3, PDF p.42 / printed 1-9) |
| Supply / speed | 5 V ('C51) or 3.3 V ('LC51); cycle 50/35/25/20 ns ('C51), 50/40/25 ns ('LC51) — 20 ns = 50 MIPS is the fastest 'C5x grade and only the 5-V 'C51/'C52 offer it (Table 1–1, PDF p.39 / printed 1-6) |
| Package | 132-pin BQFP (PQ) or 100-pin TQFP (PZ) (Table 1–1, PDF p.39 / printed 1-6) |
| JTAG | Boundary scan listed for 'C51 (§1.3, PDF p.42 / printed 1-9); full per §2.5/Table 2–2 (see file 02) |

## Contradictions / ambiguities in Chapter 1 (recorded, not silently resolved)

- **C-1 — 'C56 / 'C57 vs 'LC56 / 'LC57 naming.** §1.2 (PDF p.38 / printed 1-5) lists the generation as "'C50, 'C51, 'C52, 'C53, 'C53S, 'C56, 'C57, and 'C57S"; §1.3 (PDF p.42 / printed 1-9) likewise names 'C56/'C57 for BSP/HPI. Table 1–1 (PDF p.39 / printed 1-6), Table 2–1, Table 2–2, and Figure 2–1 list only 'LC56 and 'LC57 — there is no plain 'C56 or 'C57 device row anywhere in the device tables. **Normative: the tables.** The §1.2/§1.3 prose drops the "LC" prefix as shorthand. Do not treat "'C57" in prose as a distinct device.
- **C-2 — HPI devices.** §1.3 (PDF p.42 / printed 1-9): HPI ('C57, 'C57S). §2.4.5 (PDF p.51 / printed 2-9): HPI "available on the 'C57S and 'LC57". Table 2–1 (PDF p.51 / printed 2-9): HPI = 1 for 'C57S/'LC57S and 'LC57, 0/– elsewhere. **Normative: Table 2–1**, corroborated by §2.4.5 for 'LC57; 'LC57S has HPI per Table 2–1 only. §1.3's "'C57" is the C-1 shorthand for 'LC57.
- **C-3 — BSP devices.** §2.4.7 (PDF p.52 / printed 2-10): BSP "available on the 'C56 and 'C57 devices". §1.3 (PDF p.42 / printed 1-9): BSP ('LC56, 'C57S, 'LC57). Table 2–1 (PDF p.51 / printed 2-9): BSP = 1 for 'LC56, 'C57S/'LC57S, 'LC57. **Normative: Table 2–1.** §2.4.7's "'C56/'C57" is C-1 shorthand and omits the S-variants.
- **C-4 — Chapter title-page device list vs Table 1–1.** Intro list (PDF p.34 / printed 1-1) has 8 lines and no 'LC57S entry; Table 1–1 (PDF p.39 / printed 1-6) has 18 device/package rows including 'LC57S (1056 DARAM, 6K SARAM, 2K§ ROM, 2# serial, 3.3 V, 50/35 ns, 144-pin TQFP). **Normative: Table 1–1.**
- **C-5 — Boot loader availability.** §2.3.1 (PDF p.48 / printed 2-6, in Ch.2 but affects Ch.1's § marker): "'C50 and 'C57S have boot loader code resident; all other 'C5x DSPs offer the boot loader code as an option." Table 1–1 (PDF p.39 / printed 1-6) marks § (ROM bootloader available) on every ROM except 'LC56 and 'LC57 (32K ROM, no §). **Normative for per-device availability: Table 1–1** (the device table); the §2.3.1 "all other" phrasing is generic and does not survive contact with the LC56/LC57 rows. Unresolved whether LC56/LC57 truly lack the bootloader option or the § was omitted.
- **C-6 — Rounded RAM totals.** Intro list (PDF p.34 / printed 1-1) rounds: 'C50 "10K" vs Table 1–1 1056 + 9K = 10,080 words; 'C51 "2K" vs 1056 + 1K = 2,080; 'C52 "1K" vs 1056 (DARAM only); 'C53 "4K" vs 1056 + 3K = 4,080; 'LC56/'LC57/'C57S "7K" vs 1056 + 6K = 7,200. This is rounding, not a factual conflict; **Table 1–1 figures are exact and normative.**
- **C-7 — Table 1–1 HPI footnote || unattached.** Footnote "|| Includes host port interface (HPI)" is defined (PDF p.39 / printed 1-6) but no row visibly carries "||" in either the `-layout` or `-raw` extraction; the C57S/LC57/LC57S rows read "64Kk" (k = TQFP package footnote). [UNVERIFIED — extraction garbled/omitted marker, manual Table 1–1, PDF p.39.] HPI per-device attribution in this file rests on §2.4.5 + Table 2–1 instead.
- **C-8 — §1.3 package list incomplete.** §1.3 (PDF p.42 / printed 1-9) omits 'LC50, 'LC51, 'LC52, 'LC53, 'LC53S, 'LC57S packages entirely. **Normative: Table 1–1.**
- **C-10 — §1.3 JTAG list abbreviated.** §1.3 (PDF p.42 / printed 1-9) lists boundary scan for ('C50, 'C51, 'C53, 'C57S); §2.5 text + Table 2–2 (PDF pp.53–54 / printed 2-11–2-12) include the LC counterparts ('LC50, 'LC51, 'LC53, 'LC57S). Shorthand, not a substantive conflict; **Table 2–2 normative.**

## Unverified items (Chapter 1)

- Figure 1–1 performance data: graphical only, no extractable numbers [UNVERIFIED, PDF p.36 / printed 1-3].
- Table 1–1 "||" HPI marker attachment: see C-7.
- Per-device PLL multiplication factors (x1/x2/x3/x4/x5/x9 "depending on the device", §1.3, PDF p.42 / printed 1-9): no per-device table in Chapters 1–2.
