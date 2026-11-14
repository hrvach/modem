# Chapter 2 — Architectural Overview (TMS320C5x User's Guide, SPRU056D)

**Source:** `~/workspace/user/files/spru056d.pdf` — SPRU056D, June 1998, 764 pp., SHA-256 `a31e285f1be9fe87064e914de7bce6c96a99dd53bea3f3882c9fbe56bd45ce30`.
Range distilled: PDF pp.43–54 / printed pp.2-1–2-12 (§2.1–§2.5).
**Scope: C5x-family-generic.** All 'C5x DSPs share the same CPU structure; they differ in on-chip memory configuration and on-chip peripherals (§2 intro, PDF p.43 / printed 2-1). Per-device differences are tabulated in Tables 1–1, 2–1, 2–2; a C51 roll-up is at the end. Nothing here is C51-only.

**Citation convention:** every claim carries manual section + table/figure + PDF page / printed page. "PDF p." = 1-based PDF page; "printed" = the manual's own page number.

## 2.0 Overview (§2 intro, PDF p.43 / printed 2-1)

- Advanced, modified Harvard-type architecture based on the 'C25; separate buses for program and data memory maximize processing power; the instruction set supports data transfers between the two memory spaces (§2 intro, PDF p.43 / printed 2-1).
- Architecture consists of the buses, on-chip memory, CPU, and on-chip peripherals (§2 intro, PDF p.43 / printed 2-1).
- All 'C5x DSPs have the same CPU structure; different on-chip memory configurations and on-chip peripherals (§2 intro, PDF p.43 / printed 2-1).

### Figure 2–1. 'C5x Functional Block Diagram (§2 intro, Figure 2–1, PDF p.44 / printed 2-2)

Blocks shown: program controller (program counter, status/control registers, hardware stack, address generation logic, instruction register); CALU (multiplier, accumulator, ACC buffer, shifters, ALU); parallel logic unit (PLU); auxiliary register arithmetic unit (ARAU); memory-mapped registers; memory control; multiprocessing; interrupts; initialization; oscillator/timer; on-chip memory (program ROM, SARAM, DARAM blocks B0/B1/B2); peripherals (serial port 1, serial port 2, TDM serial port, buffered serial port, timer, host port interface, test/emulation).

Device memory table printed inside Figure 2–1 (PDF p.44 / printed 2-2) — abbreviated figure, not a device table (omits 'C53S, 'LC53, 'LC53S, 'LC57S entirely):

| Device | Program ROM | SARAM |
|---|---|---|
| 'C50 | 2K | 9K |
| 'C51 | 8K | 1K |
| 'C52 | 4K | — |
| 'C53 | 16K | 3K |
| 'LC56 | 32K | 6K |
| 'C57S | 2K | 6K |
| 'LC57 | 32K | 6K |

Values agree with Table 1–1 (§1.2, PDF p.39 / printed 1-6). DARAM in the figure: B0 512×16 (data/program), B1 512×16 (data), B2 32×16 (data) — agrees with §2.3.2.

## 2.1 Bus structure (§2.1, PDF p.45 / printed 2-3)

- Separate program and data buses allow simultaneous access to program instructions and data (high parallelism): while data is multiplied, a previous product can be loaded into / added to / subtracted from the accumulator while a new address is generated (§2.1, PDF p.45 / printed 2-3).
- Parallelism supports arithmetic, logic, and bit-manipulation operations all performable in a single machine cycle; control mechanisms manage interrupts, repeated operations, and function calling (§2.1, PDF p.45 / printed 2-3).
- Four major buses (§2.1, PDF p.45 / printed 2-3):

| Bus | Function as stated |
|---|---|
| Program bus (PB) | Carries instruction code and immediate operands from program memory space to the CPU |
| Program address bus (PAB) | Provides addresses to program memory space for both reads and writes |
| Data read bus (DB) | Interconnects CPU elements to data memory space |
| Data read address bus (DAB) | (Named as fourth major bus; no separate functional sentence in §2.1 — its role is implied by the name and by §2.3.2's "dual data buses (DB and DAB)") |

- Program and data buses can work together to transfer data from on-chip data memory and internal/external program memory to the multiplier for single-cycle multiply/accumulate operations (§2.1, PDF p.45 / printed 2-3).

## 2.2 Central processing unit (CPU) (§2.2, PDF p.46 / printed 2-4)

CPU elements (§2.2, PDF p.46 / printed 2-4): central arithmetic logic unit (CALU); parallel logic unit (PLU); auxiliary register arithmetic unit (ARAU); memory-mapped registers; program controller.
- Source-code compatible with 'C1x and 'C2x generations; improvements include a 32-bit accumulator buffer, additional scaling capabilities, new instructions; block move and memory-mapped register instructions improve data management (§2.2, PDF p.46 / printed 2-4). Detail in Chapter 3.

### 2.2.1 CALU (§2.2.1, PDF p.46 / printed 2-4)

- Performs 2s-complement arithmetic. Elements: 16-bit × 16-bit multiplier; 32-bit ALU; 32-bit accumulator (ACC); 32-bit accumulator buffer (ACCB); additional shifters at the outputs of both the accumulator and the product register (PREG) (§2.2.1, PDF p.46 / printed 2-4). Detail: §3.2, p.3-7.

### 2.2.2 PLU (§2.2.2, PDF p.46 / printed 2-4)

- Independent PLU, operates separately from but in parallel with the ALU; performs Boolean operations / bit manipulations for high-speed controllers (§2.2.2, PDF p.46 / printed 2-4).
- Can set, clear, test, or toggle bits in a status register, control register, or any data memory location (§2.2.2, PDF p.46 / printed 2-4).
- Direct logic-operation path to data memory values **without affecting ACC or PREG**; results written back to the original data memory location (§2.2.2, PDF p.46 / printed 2-4). Detail: §3.3, p.3-15.

### 2.2.3 ARAU (§2.2.3, PDF p.47 / printed 2-5)

- Unsigned 16-bit ALU calculating indirect addresses from auxiliary registers (ARs), index register (INDX), and auxiliary register compare register (ARCR) (§2.2.3, PDF p.47 / printed 2-5).
- Can autoindex the current AR while the data memory location is being addressed; indexes by ±1 or by the contents of INDX (§2.2.3, PDF p.47 / printed 2-5).
- Address manipulation does not require the CALU, so the CALU is free for other operations in parallel (§2.2.3, PDF p.47 / printed 2-5). Detail: §3.4, p.3-17.

### 2.2.4 Memory-mapped registers (§2.2.4, PDF p.47 / printed 2-5)

- 96 registers mapped into page 0 of data memory space (§2.2.4, PDF p.47 / printed 2-5).
- All 'C5x DSPs have **28 CPU registers and 16 I/O port registers**; numbers of peripheral and reserved registers differ per device (§2.2.4, PDF p.47 / printed 2-5; see Chapter 4, Memory).
- Read/written like any other data memory location; used for indirect data address pointers, temporary storage, CPU status and control, or integer arithmetic through the ARAU (§2.2.4, PDF p.47 / printed 2-5). Detail: §3.5, p.3-21.

### 2.2.5 Program controller (§2.2.5, PDF p.47 / printed 2-5)

- Logic circuitry decodes operational instructions, manages the CPU pipeline, stores CPU operation status, decodes conditional operations (§2.2.5, PDF p.47 / printed 2-5).
- Parallelism allows **three concurrent memory operations in any given machine cycle: fetch an instruction, read an operand, and write an operand** (§2.2.5, PDF p.47 / printed 2-5).
- Elements: program counter; status and control registers; hardware stack; address generation logic; instruction register (§2.2.5, PDF p.47 / printed 2-5).
- Cross-references as printed: "See Chapter 4, Program Control, and Chapter 7, Pipeline" (§2.2.5, PDF p.47 / printed 2-5). NOTE: Chapter 4 in this manual is Memory per §2.2.4's own cross-reference ("see Chapter 4, Memory") — the "Chapter 4, Program Control" reference in §2.2.5 is as printed and appears inconsistent with §2.2.4; recorded as printed, not corrected.

## 2.3 On-chip memory (§2.3, PDF p.48 / printed 2-6)

- On-chip memory types: program ROM; data/program dual-access RAM (DARAM); data/program single-access RAM (SARAM) (§2.3, PDF p.48 / printed 2-6).
- Total address range **224K words × 16 bits**, four individually selectable segments: 64K-word program memory space, 64K-word local data memory space, 64K-word I/O ports, 32K-word global data memory space (§2.3, PDF p.48 / printed 2-6). Detail: Chapter 8, Memory.

### 2.3.1 Program ROM (§2.3.1, PDF p.48 / printed 2-6)

| Fact | Value |
|---|---|
| Type | 16-bit on-chip maskable programmable ROM, all 'C5x DSPs (sizes per Table 1–1) |
| Boot loader resident | 'C50 and 'C57S only; all other 'C5x DSPs "offer the boot loader code as an option" — see Contradiction C-5 (Table 1–1 marks no bootloader § for 'LC56/'LC57) |
| Purpose | Boot program code from slower external ROM/EPROM to fast on-chip or external RAM |
| Removal after boot | Boot ROM space can be removed from program memory space by setting the MP/MC bit in the processor mode status register (PMST) |
| Selection at reset | On-chip ROM selected by driving the MP/MC pin low; if not selected, execution starts from off-chip memory |
| Custom ROM | ROM intended for your specific program; final code submitted to TI for implementation — see Appendix F, Submitting ROM Codes to TI |
| Detail ref | §8.2, Program Memory, p.8-7 |

### 2.3.2 DARAM (§2.3.2, PDF pp.48–49 / printed 2-6–2-7)

| Fact | Value |
|---|---|
| Size | 1056-word × 16-bit on **all** 'C5x DSPs |
| Blocks | B0: 512-word data or program; B1: 512-word data; B2: 32-word data. B1/B2 always data memory; B0 software-configurable as data or program |
| Configuration 1 | All 1056 words × 16 bits as data memory |
| Configuration 2 | 544 words × 16 bits as data memory + 512 words × 16 bits as program memory |
| Dual-access | Dual data buses (DB and DAB) allow read from and write to DARAM in the same machine cycle |
| Pipeline rationale | 4-deep pipeline: CPU reads data on the 3rd stage, writes data on the 4th stage — so a second instruction can be reading while the first is writing |
| Detail ref | §8.3, Local Data Memory, p.8-15 |

### 2.3.3 SARAM (§2.3.3, PDF p.49 / printed 2-7)

| Fact | Value |
|---|---|
| Availability | All 'C5x DSPs **except the 'C52**; sizes per Table 1–1 (1K 'C51, 3K 'C53/'C53S, 6K 'LC56/'C57S/'LC57, 9K 'C50) |
| Configurations (software) | All data memory; all program memory; both data and program memory |
| Block structure | Divided into 1K- and/or 2K-word blocks, contiguous in address memory space |
| Parallel access | All 'C5x CPUs support parallel accesses to these SARAM blocks — but **one SARAM block can be accessed only once per machine cycle**: CPU can read/write one block while accessing another; on multiple accesses to the same block, SARAM asserts not-ready to the CPU and executes the accesses one cycle at a time |
| Mapping | More flexible than DARAM: can be mapped to program and data space simultaneously. Cost: an instruction fetch + data fetch that DARAM does in one machine cycle may take **two machine cycles** with SARAM |
| Use | Code booted from off-chip ROM, then executed at full speed once loaded into SARAM |
| Detail ref | §8.3, Local Data Memory, p.8-15 |

### 2.3.4 On-chip memory protection (§2.3.4, PDF p.49 / printed 2-7)

- Maskable option protecting on-chip memory contents: when the related bit is set, **no externally originating instruction can access the on-chip memory spaces** (§2.3.4, PDF p.49 / printed 2-7). Detail: §8.2.4, Program Memory Protection Feature, p.8-14. (Which bit / which register is not stated in §2.3.4 — see Chapter 8.)

## 2.4 On-chip peripherals (§2.4, PDF p.50 / printed 2-8)

Family-level peripheral list (§2.4, PDF p.50 / printed 2-8): clock generator; hardware timer; software-programmable wait-state generators; parallel I/O ports; host port interface (HPI); serial port; buffered serial port (BSP); time-division multiplexed (TDM) serial port; user-maskable interrupts. All 'C5x have the same CPU; on-chip peripherals differ per device.

### 2.4.1 Clock generator (§2.4.1, PDF p.50 / printed 2-8)

- Internal oscillator + phase-locked loop (PLL) circuit; driven internally by a crystal resonator circuit or externally by a clock source; PLL multiplies the clock source by a specific factor so a lower-frequency clock source can feed the CPU (§2.4.1, PDF p.50 / printed 2-8). Detail: §9.2, p.9-7. Per-device PLL factors (x1/x2/x3/x4/x5/x9 per §1.3) are **not** tabulated in Chapters 1–2.

### 2.4.2 Hardware timer (§2.4.2, PDF p.50 / printed 2-8)

- 16-bit hardware timer with 4-bit prescaler; clocks at **1/2 to 1/32 of the machine cycle rate (CLKOUT1)**, depending on divide-down ratio; can be stopped, restarted, reset, or disabled by specific status bits (§2.4.2, PDF p.50 / printed 2-8). Detail: §9.3, p.9-9. (Prescaler divide ratios / which status bits are not given in §2.4.2 — see Chapter 9.)

### 2.4.3 Software-programmable wait-state generators (§2.4.3, PDF p.50 / printed 2-8)

- Wait-state generation without external hardware for interfacing slower off-chip memory and I/O devices; multiple wait-state generating circuits, each user-programmable to operate in different wait states for off-chip memory accesses (§2.4.3, PDF p.50 / printed 2-8). Detail: §9.4, p.9-13. Count "sixteen" is from §1.3 (PDF p.42 / printed 1-9), not repeated in §2.4.3.

### 2.4.4 Parallel I/O ports (§2.4.4, PDF p.51 / printed 2-9)

- **64K I/O ports total; 16 memory-mapped in data memory space** (§2.4.4, PDF p.51 / printed 2-9).
- Each I/O port addressable by IN or OUT; memory-mapped ports accessible with any instruction that reads/writes data memory (§2.4.4, PDF p.51 / printed 2-9).
- **IS signal** indicates a read or write through an I/O port; minimal off-chip address decoding needed for external I/O devices (§2.4.4, PDF p.51 / printed 2-9). Detail: §9.6, p.9-22.
- NOTE: §2.4.4 says "Table 2–1 lists the number and type of parallel ports available" — Table 2–1 as printed lists serial-port counts and the host port, not per-device parallel-port counts (the 64K figure is family-wide in the text). Recorded as printed.

### Table 2–1. Number of Serial/Parallel Ports Available in Different 'C5x Package Types (§2.4.4/§2.4.5, Table 2–1, PDF p.51 / printed 2-9) — full transcription

Columns as printed: TMS320 Device | Package ID† | High-Speed Serial Port | TDM Serial Port | Buffered Serial Port | Host Port (Parallel).
Footnote †: PGE = 20×20×1.4 mm TQFP; PJ = 14×20×2.7 mm QFP; PQ = 20×20×3.8 mm BQFP; PZ and PBK = 14×14×1.4 mm TQFP.
Cell values verified against **two independent extractions** (`pdftotext -layout` and `pdftotext -raw`, PDF p.51); both agree row by row. "–" = none (as printed).

| Device | Package ID | High-speed serial port | TDM serial port | Buffered serial port | Host port (parallel) |
|---|---|---|---|---|---|
| 'C50/'LC50 | PQ | 1 | 1 | – | – |
| 'C51/'LC51 | PQ/PZ | 1 | 1 | – | – |
| 'C52/'LC52 | PJ/PZ | 1 | – | – | – |
| 'C53/'LC53 | PQ | 1 | 1 | – | – |
| 'C53S/'LC53S | PZ | **2** | – | – | – |
| 'LC56 | PZ | 1 | – | 1 | – |
| 'C57S/'LC57S | PGE | 1 | – | 1 | **1** |
| 'LC57 | PBK | 1 | – | 1 | **1** |

Reading notes:
- "High-Speed Serial Port" = general-purpose serial port (§2.4.6). Every device has ≥1.
- **'C53S/'LC53S are the only devices with 2 general-purpose serial ports and no TDM/BSP/HPI** — this is what Table 1–1's bare "2" (no ¶/#) means.
- **TDM: only 'C50, 'C51, 'C53 (+ LC counterparts). BSP: only 'LC56, 'C57S/'LC57S, 'LC57. HPI: only 'C57S/'LC57S and 'LC57.**
- **'C51 has TDM and NO BSP and NO HPI** — the Courier V.Everything's 'C51 therefore has no host-port interface and no buffered serial port per this manual.
- Table 2–1's device grouping differs from Table 1–1: it merges C/LC pairs and merges 'C57S/'LC57S into one row, and has no separate 'LC53S row beyond the 'C53S/'LC53S row.

### 2.4.5 Host port interface (HPI) (§2.4.5, PDF p.51 / printed 2-9)

- HPI "available on the **'C57S and 'LC57**" — 8-bit parallel I/O port interfacing to a host processor; information exchanged between DSP and host through on-chip memory accessible to both the host processor and the 'C57 (§2.4.5, PDF p.51 / printed 2-9). Detail: §9.10, p.9-87.
- See Contradiction C-2: §1.3 names ('C57, 'C57S); Table 2–1 adds 'LC57S (HPI = 1 for the 'C57S/'LC57S row). **Normative: Table 2–1** — HPI on 'C57S, 'LC57S, 'LC57; absent on all others including 'C51.
- The trailing "'C57" in §2.4.5's last clause is the C-1 loose naming (no plain 'C57 device row exists).

### 2.4.6 Serial port (§2.4.6, PDF p.52 / printed 2-10)

- Three kinds available: general-purpose serial port, TDM serial port, BSP (§2.4.6, PDF p.52 / printed 2-10).
- Each 'C5x contains **at least one general-purpose, high-speed synchronous, full-duplex serial port** for direct communication with serial devices such as codecs, serial A/D converters, and other serial systems (§2.4.6, PDF p.52 / printed 2-10).
- Operates at up to **one-fourth the machine cycle rate (CLKOUT1)**; transmitter and receiver double-buffered and individually controlled by maskable external interrupt signals; data framed as bytes or as words (§2.4.6, PDF p.52 / printed 2-10). Detail: §9.7, p.9-23.

### 2.4.7 Buffered serial port (BSP) (§2.4.7, PDF p.52 / printed 2-10)

- BSP "available on the **'C56 and 'C57 devices**" — full-duplex, double-buffered serial port + autobuffering unit (ABU); flexibility on data stream length; ABU supports high-speed data transfer and reduces interrupt latencies (§2.4.7, PDF p.52 / printed 2-10). Detail: §9.8, p.9-53.
- See Contradiction C-3: §1.3 names ('LC56, 'C57S, 'LC57); Table 2–1 gives BSP = 1 for 'LC56, 'C57S/'LC57S, 'LC57. **Normative: Table 2–1.** §2.4.7's "'C56/'C57" is C-1 shorthand.

### 2.4.8 TDM serial port (§2.4.8, PDF p.52 / printed 2-10)

- TDM serial port "available on the **'C50, 'C51, and 'C53 devices**" — full-duplex; software-configurable for synchronous operations or time-division multiplexed operations; commonly used in multiprocessor applications (§2.4.8, PDF p.52 / printed 2-10). Detail: §9.9, p.9-74.
- No contradiction: §1.3, §2.4.8, Table 1–1 (¶), and Table 2–1 all agree on 'C50/'C51/'C53 (+ LC counterparts).

### 2.4.9 User-maskable interrupts (§2.4.9, PDF p.52 / printed 2-10)

- **Four external interrupt lines (INT1–INT4)** and **five internal interrupts: a timer interrupt and four serial-port interrupts** — all user-maskable (§2.4.9, PDF p.52 / printed 2-10).
- On ISR entry: program counter saved on the 8-level hardware stack; contents of **eleven specific CPU registers automatically saved (shadowed) on a 1-level-deep stack**; on return-from-interrupt, CPU register contents restored (§2.4.9, PDF p.52 / printed 2-10). Detail: §4.8, Interrupts, p.4-36.
- INFERENCE (not in the manual text here): four serial-port interrupts is consistent with two serial ports × (receive + transmit) on dual-port devices; the manual does not state this mapping in §2.4.9, and single-port devices ('C52) are not explained here. Do not rely on it.

## 2.5 Test/emulation (§2.5, PDF pp.53–54 / printed 2-11–2-12)

### JTAG interface (§2.5, PDF p.53 / printed 2-11)

| Device group | IEEE Std. 1149.1 (JTAG) interface | Boundary scan |
|---|---|---|
| 'C50, 'LC50, 'C51, 'LC51, 'C53, 'LC53, 'C57S, 'LC57S | Used for emulation **and test**; provides boundary scan to/from interfacing devices; tests pin-to-pin continuity and operational tests on devices peripheral to the 'C5x | Yes |
| 'C52, 'LC52, 'C53S, 'LC53S, 'LC56, 'LC57 | Interface **without** boundary scan, for emulation only; interfaced to other internal scanning logic with access to all on-chip resources; on-board emulation via the 1149.1 serial scan pins and emulation-dedicated pins | No |

- On-chip analysis block + 'C5x debugger software provides debugging and performance-evaluation functions in a target system (§2.5, PDF p.53 / printed 2-11).
- **Full analysis block** capabilities (§2.5, PDF p.53 / printed 2-11):
  - Flexible breakpoint setup, triggerable on: program fetches/reads/writes; EMU0/1 pin activity; data reads/writes; CPU events (calls, returns, interrupts/traps, branches, pipeline clock); event counter overflow.
  - Event counting for performance analysis: CPU clocks; pipeline advances; instruction fetches; calls, returns, interrupts/traps, branches; program fetches/reads/writes; data reads/writes.
  - Program counter discontinuity trace buffer to monitor program counter flow.
- **Reduced analysis block on the 'C53S and 'LC53S**: breakpoint triggering based on program fetches/reads/writes and EMU0/1 pin activity only (§2.5, PDF p.53 / printed 2-11).
- Further info: TMS320 DSP Development Support Reference Guide (§2.5, PDF p.54 / printed 2-12).

### Table 2–2. IEEE Std. 1149.1 (JTAG)/Boundary-Scan Interface Configurations for the 'C5x (§2.5, Table 2–2, PDF p.54 / printed 2-12) — full transcription

Cell values verified against `pdftotext -layout` and `pdftotext -raw` (PDF p.54); both agree.

| TMS320 Device | IEEE Std. 1149.1 Interface | Boundary Scan Capability | On-Chip Analysis Block |
|---|---|---|---|
| 'C50/'LC50 | Yes | Yes | Full |
| 'C51/'LC51 | Yes | Yes | Full |
| 'C52/'LC52 | Yes | No | Full |
| 'C53/'LC53 | Yes | Yes | Full |
| 'C53S/'LC53S | Yes | No | **Reduced** |
| 'LC56 | Yes | No | Full |
| 'C57S/'LC57S | Yes | Yes | Full |
| 'LC57 | Yes | No | Full |

Reading notes:
- Every 'C5x has a JTAG interface; boundary scan is the discriminator, not JTAG itself.
- 'C53S/'LC53S is the only reduced-analysis-block device; it still has a full JTAG interface (without boundary scan).
- 'C51 has JTAG **with** boundary scan and a **full** analysis block.

## C51 at a glance (from this chapter only)

| Attribute | 'C51 value |
|---|---|
| CPU | Same as all 'C5x: CALU (16×16 multiplier, 32-bit ALU/ACC/ACCB, ACC/PREG shifters), PLU, ARAU, 96 page-0 memory-mapped registers (28 CPU + 16 I/O port), program controller with 8-level stack (§2.2, PDF p.46 / printed 2-4) |
| DARAM | 1056 words: B0 512 (data/program), B1 512 (data), B2 32 (data) (§2.3.2, PDF pp.48–49 / printed 2-6–2-7) |
| SARAM | 1K words, in 1K blocks; no 'C52-style absence; one access per block per cycle (§2.3.3, PDF p.49 / printed 2-7; Table 1–1) |
| ROM | 8K words, bootloader available (§) (Table 1–1, PDF p.39 / printed 1-6); boot via MP/MC pin low at reset, MP/MC bit in PMST removes boot ROM space (§2.3.1, PDF p.48 / printed 2-6) |
| Serial ports | 1 general-purpose high-speed + 1 TDM (Table 2–1, PDF p.51 / printed 2-9); **no BSP, no HPI** |
| Timer / wait states / clock | 16-bit timer + 4-bit prescaler, 1/2–1/32 CLKOUT1 (§2.4.2); 16 software-programmable wait-state generators (§1.3); PLL clock generator (§2.4.1) |
| Parallel I/O | 64K ports, 16 memory-mapped, IS signal (§2.4.4, PDF p.51 / printed 2-9) |
| Interrupts | INT1–INT4 external + timer + 4 serial-port interrupts; 11 shadow registers (§2.4.9, PDF p.52 / printed 2-10) |
| Test/emulation | JTAG with boundary scan, full analysis block (Table 2–2, PDF p.54 / printed 2-12) |

## Contradictions / ambiguities in Chapter 2 (recorded, not silently resolved)

- **C-1 — 'C56 / 'C57 vs 'LC56 / 'LC57 naming (also affects Ch.1).** §2.4.7 (PDF p.52 / printed 2-10) "BSP available on the 'C56 and 'C57 devices"; §2.4.5 (PDF p.51 / printed 2-9) says memory accessible to host and "the 'C57". Tables 1–1, 2–1, 2–2 and Figure 2–1 list only 'LC56 and 'LC57. **Normative: the tables** — no plain 'C56/'C57 device rows exist.
- **C-2 — HPI devices.** §1.3 (PDF p.42 / printed 1-9): ('C57, 'C57S). §2.4.5 (PDF p.51 / printed 2-9): 'C57S and 'LC57. Table 2–1 (PDF p.51 / printed 2-9): HPI = 1 for 'C57S/'LC57S and 'LC57. **Normative: Table 2–1.** 'LC57S has HPI only per Table 2–1.
- **C-3 — BSP devices.** §2.4.7 (PDF p.52 / printed 2-10): "'C56 and 'C57 devices". §1.3 (PDF p.42 / printed 1-9): ('LC56, 'C57S, 'LC57). Table 2–1 (PDF p.51 / printed 2-9): BSP = 1 for 'LC56, 'C57S/'LC57S, 'LC57. **Normative: Table 2–1.**
- **C-5 — Boot loader availability.** §2.3.1 (PDF p.48 / printed 2-6): "'C50 and 'C57S have boot loader code resident in the on-chip ROM, all other 'C5x DSPs offer the boot loader code as an option." Table 1–1 (PDF p.39 / printed 1-6) marks § (ROM bootloader available) on every ROM except 'LC56 and 'LC57. **Normative for per-device availability: Table 1–1.** Unresolved whether LC56/LC57 truly lack the option or the § was omitted.
- **C-9 — §2.2.5 cross-reference.** §2.2.5 (PDF p.47 / printed 2-5) says "See Chapter 4, Program Control, and Chapter 7, Pipeline", but §2.2.4 (PDF p.47 / printed 2-5) identifies Chapter 4 as Memory. Recorded as printed; the Program Control chapter number is not corrected here (outside Chapters 1–2 scope to verify).
- **C-11 — §2.4.4 vs Table 2–1.** §2.4.4 (PDF p.51 / printed 2-9) says "Table 2–1 lists the number and type of parallel ports available in 'C5x DSPs" — Table 2–1 as printed lists serial-port counts and the host port, not per-device parallel-port counts (64K is family-wide in the text). Minor descriptive mismatch; recorded as printed.

## Unverified items (Chapter 2)

- Figure 2–1 device list is abbreviated (omits 'C53S, 'LC53, 'LC53S, 'LC57S) — it is a block diagram, not a device table; Table 1–1 governs.
- Per-device PLL multiplication factors: §1.3 gives x1/x2/x3/x4/x5/x9 "depending on the device" (PDF p.42 / printed 1-9); no per-device PLL table exists in Chapters 1–2.
- Memory-protection bit identity: §2.3.4 states the effect only (PDF p.49 / printed 2-7); the bit/register is in §8.2.4 (outside Chapters 1–2).
- §2.4.9 does not state how the four serial-port interrupts map onto ports on single- vs dual-port devices; see INFERENCE note in §2.4.9 above.
