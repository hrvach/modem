# TMS320C5x Memory — Chapter 8 Distillation

**Source (only authority):** `~/workspace/user/files/spru056d.pdf` — SPRU056D, *TMS320C5x User's Guide*, June 1998, Chapter 8 "Memory".
**Range:** PDF pp. 468–509 = printed pp. 8-1–8-42. Page mapping: printed page = PDF page − 467.
**Citation convention:** every claim carries manual section + table/figure + PDF page / printed page.
`[UNVERIFIED — ...]` marks garbled extraction. All Ch. 8 tables were cross-checked against rendered page images (pdftoppm, 150 dpi) where the text extraction was garbled by box-drawing characters; values below are as printed.
`INFERENCE:` marks conclusions drawn from, but not stated by, the manual; kept out of tables.
Device scope: family-generic unless a device is named. **C51-specific items are flagged `['C51]`** etc. where the manual states them.
**Reset values / R/W for the MMR map:** the map itself is Table 8–13 (§8.3.2, Ch. 8) + Table 9–1 (§9.1.1, Ch. 9, PDF pp. 511–513 / printed 9-2–9-4). Neither table lists reset values; reset bit-states are taken from Table 4–15 / Table 4–16 (§4.9 Reset, PDF pp. 125–127 / printed 4-46–4-48) and the register bit-summary tables in Ch. 4 / Ch. 9, as cited per row. Registers not listed in Tables 4–15/4–16 are **undefined at reset** per §4.9 step 2 (PDF p. 124 / 4-45): "any remaining status bits remain undefined and should be initialized appropriately".

## 8.1 Memory space overview — §8.1 (PDF pp. 468–473 / printed 8-1–8-6)

Total address range **224K 16-bit words**, four individually-selectable segments (§8 intro, PDF p. 468 / 8-1):

| Segment | Size | Contents |
|---|---|---|
| Program | 64K words | Instructions; also tables and immediate operands |
| Local data | 64K words | Data used by instructions |
| I/O ports | 64K words | Parallel I/O ports; also usable as extra data storage |
| Global data | 32K words | Shared with other processors, or additional data space |

- Enhanced Harvard architecture; two parallel buses — program bus (PB) and data read bus (DB) — allow simultaneous program + data access. Within any machine cycle the ALU can execute up to **three concurrent memory operations**: fetch an instruction, read an operand, write an operand (§8.1, PDF p. 469 / 8-2).
- On-chip memory: ROM in program space, SARAM in program and/or data space, DARAM in program and/or data space. Amounts/types per device: Table 1–1 (p. 1-6, outside this chapter).
- **DARAM — all devices, 1056 words in 3 blocks, same addresses on every device:** B0 = 512 words, 0100h–02FFh local data or FE00h–FFFFh program; B1 = 512 words, 0300h–04FFh local data; B2 = 32 words, 0060h–007Fh local data. DARAM can be read from and written to in the **same machine cycle** (§8.1, PDF p. 469 / 8-2).
- **SARAM:** divided into 2K- and 1K-word blocks, contiguous in program or data space. One full machine cycle per read or write; CPU can read/write one block while accessing another block in the same cycle (§8.1, PDF p. 469 / 8-2).
- **ROM:** maskable ROM or boot ROM, in the lowest block of program memory, at address 0000h. Boot ROM includes a device test (internal use) and boot code. Enabled/disabled by MP/MC pin at reset, or by the MP/MC bit in PMST after reset (§8.1, PDF pp. 469–470 / 8-2–8-3).

**Per-device on-chip memory (§8.1 text, PDF p. 470 / 8-3; Figs. 8–1–8–6, PDF pp. 471–473 / 8-4–8-6):**

| Device | ROM (program) | SARAM (program/data) | DARAM | Notes |
|---|---|---|---|---|
| 'C50 | 2K boot ROM, 0000h–07FFh | 9K, 0800h–2BFFh either space | 1056 | Fig. 8–1 |
| 'C51 | 8K maskable ROM, 0000h–1FFFh | 1K: data 0800h–0BFFh, program 2000h–23FFh, or both | 1056 | No boot ROM; Fig. 8–2 |
| 'C52 | 4K maskable ROM, 0000h–0FFFh | None | 1056 | Fig. 8–3 |
| 'C53 / 'C53S | 16K maskable ROM, 0000h–3FFFh | 3K: data 0800h–13FFh, program 4000h–4BFFh, or both | 1056 | Fig. 8–4 |
| 'LC56 / 'LC57 | 32K maskable ROM, 0000h–7FFFh | 6K: data 0800h–1FFFh, program 8000h–97FFh, or both | 1056 | Fig. 8–5 |
| 'C57S | 2K boot ROM, 0000h–07FFh | 6K: data 0800h–1FFFh, program 8000h–97FFh, or both | 1056 | Fig. 8–6 |

## 8.2 Program memory — §8.2 (PDF pp. 474–481 / printed 8-7–8-14)

64K 16-bit words; contains on-chip ROM, SARAM (except 'C52), DARAM. Software configures cells on-/off-chip; the 'C5x automatically accesses on-chip cells within their bounds and generates an external access outside them (§8.2, PDF p. 474 / 8-7).
Advantages of on-chip: higher performance (no wait states), lower cost, lower power. Advantage of off-chip: larger address space.

### 8.2.1 Program memory configurability — §8.2.1 (PDF pp. 474–475 / 8-7–8-8)

| Control | Effect |
|---|---|
| MP/MC pin at reset | High = microprocessor: on-chip ROM **not** addressed. Low = microcomputer: on-chip ROM enabled. Pin sampled **only at reset** |
| MP/MC bit in PMST (after reset) | Software can change configuration. `OPL #8,PMST` removes boot ROM from program space (sets MP/MC = 1) |
| Reset vector | Fetched at program address 0000h. Microcomputer → starts in on-chip ROM; microprocessor → starts in off-chip memory |
| RAM bit in PMST | Set → SARAM resident in program space (at reset SARAM is **not** resident in program space). `OPL #010h,PMST` maps SARAM into program space |
| CNF bit in ST1 | Set → DARAM B0 resident in program space at FE00h–FFFFh (at reset B0 is **not** resident in program space). `SETC CNF` maps B0 to program space |
| Masked ROM | Code for 'C51, 'C52, 'C53, 'C56, 'C57 maskable ROM is submitted to TI (Appendix F) |

**Tables 8–1–8–6. Program memory configuration (all addresses hex; CNF / RAM / MP/MC bit values). Table 8–1 'C50, PDF p. 475 / 8-8:**

| CNF | RAM | MP/MC | ROM (2K) | SARAM (9K) | DARAM B0 (512) | Off-chip |
|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0000–07FF | Off-chip | Off-chip | 0800–FFFF |
| 0 | 0 | 1 | Off-chip | Off-chip | Off-chip | 0000–FFFF |
| 0 | 1 | 0 | 0000–07FF | 0800–2BFF | Off-chip | 2C00–FFFF |
| 0 | 1 | 1 | Off-chip | 0800–2BFF | Off-chip | 0000–07FF, 2C00–FFFF |
| 1 | 0 | 0 | 0000–07FF | Off-chip | FE00–FFFF | 0800–FDFF |
| 1 | 0 | 1 | Off-chip | Off-chip | FE00–FFFF | 0000–FDFF |
| 1 | 1 | 0 | 0000–07FF | 0800–2BFF | FE00–FFFF | 2C00–FDFF |
| 1 | 1 | 1 | Off-chip | 0800–2BFF | FE00–FFFF | 0000–07FF, 2C00–FDFF |

**Table 8–2 'C51, PDF p. 476 / 8-9:**

| CNF | RAM | MP/MC | ROM (8K) | SARAM (1K) | DARAM B0 (512) | Off-chip |
|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0000–1FFF | Off-chip | Off-chip | 2000–FFFF |
| 0 | 0 | 1 | Off-chip | Off-chip | Off-chip | 0000–FFFF |
| 0 | 1 | 0 | 0000–1FFF | 2000–23FF | Off-chip | 2400–FFFF |
| 0 | 1 | 1 | Off-chip | 2000–23FF | Off-chip | 0000–1FFF, 2400–FFFF |
| 1 | 0 | 0 | 0000–1FFF | Off-chip | FE00–FFFF | 2000–FDFF |
| 1 | 0 | 1 | Off-chip | Off-chip | FE00–FFFF | 0000–FDFF |
| 1 | 1 | 0 | 0000–1FFF | 2000–23FF | FE00–FFFF | 2400–FDFF |
| 1 | 1 | 1 | Off-chip | 2000–23FF | FE00–FFFF | 0000–1FFF, 2400–FDFF |

**Table 8–3 'C52, PDF p. 476 / 8-9** (RAM = X don't care; no SARAM):

| CNF | RAM | MP/MC | ROM (4K) | SARAM | DARAM B0 (512) | Off-chip |
|---|---|---|---|---|---|---|
| 0 | X | 0 | 0000–0FFF | None | Off-chip | 1000–FFFF |
| 0 | X | 1 | Off-chip | None | Off-chip | 0000–FFFF |
| 1 | X | 0 | 0000–0FFF | None | FE00–FFFF | 1000–FDFF |
| 1 | X | 1 | Off-chip | None | FE00–FFFF | 0000–FDFF |

**Table 8–4 'C53 and 'C53S, PDF p. 477 / 8-10:**

| CNF | RAM | MP/MC | ROM (16K) | SARAM (3K) | DARAM B0 (512) | Off-chip |
|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0000–3FFF | Off-chip | Off-chip | 4000–FFFF |
| 0 | 0 | 1 | Off-chip | Off-chip | Off-chip | 0000–FFFF |
| 0 | 1 | 0 | 0000–3FFF | 4000–4BFF | Off-chip | 4C00–FFFF |
| 0 | 1 | 1 | Off-chip | 4000–4BFF | Off-chip | 0000–3FFF, 4C00–FFFF |
| 1 | 0 | 0 | 0000–3FFF | Off-chip | FE00–FFFF | 4000–FDFF |
| 1 | 0 | 1 | Off-chip | Off-chip | FE00–FFFF | 0000–FDFF |
| 1 | 1 | 0 | 0000–3FFF | 4000–4BFF | FE00–FFFF | 4C00–FDFF |
| 1 | 1 | 1 | Off-chip | 4000–4BFF | FE00–FFFF | 0000–3FFF, 4C00–FDFF |

**Table 8–5 'LC56 and 'LC57, PDF p. 477 / 8-10:**

| CNF | RAM | MP/MC | ROM (32K) | SARAM (6K) | DARAM B0 (512) | Off-chip |
|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0000–7FFF | Off-chip | Off-chip | 8000–FFFF |
| 0 | 0 | 1 | Off-chip | Off-chip | Off-chip | 0000–FFFF |
| 0 | 1 | 0 | 0000–7FFF | 8000–97FF | Off-chip | 9800–FFFF |
| 0 | 1 | 1 | Off-chip | 8000–97FF | Off-chip | 0000–7FFF, 9800–FFFF |
| 1 | 0 | 0 | 0000–7FFF | Off-chip | FE00–FFFF | 8000–FDFF |
| 1 | 0 | 1 | Off-chip | Off-chip | FE00–FFFF | 0000–FDFF |
| 1 | 1 | 0 | 0000–7FFF | 8000–97FF | FE00–FFFF | 9800–FDFF |
| 1 | 1 | 1 | Off-chip | 8000–97FF | FE00–FFFF | 0000–7FFF, 9800–FDFF |

**Table 8–6 'C57S, PDF p. 478 / 8-11:**

| CNF | RAM | MP/MC | ROM (2K) | SARAM (6K) | DARAM B0 (512) | Off-chip |
|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 0000–07FF | Off-chip | Off-chip | 8000–FFFF |
| 0 | 0 | 1 | Off-chip | Off-chip | Off-chip | 0000–FFFF |
| 0 | 1 | 0 | 0000–07FF | 8000–97FF | Off-chip | 9800–FFFF |
| 0 | 1 | 1 | Off-chip | 8000–97FF | Off-chip | 0000–7FFF, 9800–FFFF |
| 1 | 0 | 0 | 0000–07FF | Off-chip | FE00–FFFF | 8000–FDFF |
| 1 | 0 | 1 | Off-chip | Off-chip | FE00–FFFF | 0000–FDFF |
| 1 | 1 | 0 | 0000–07FF | 8000–97FF | FE00–FFFF | 9800–FDFF |
| 1 | 1 | 1 | Off-chip | 8000–97FF | FE00–FFFF | 0000–7FFF, 9800–FDFF |

### 8.2.2 Program memory address map / interrupt vectors — §8.2.2 (PDF pp. 478–479 / 8-11–8-12)

- Interrupt vectors are in program space and are **soft**: on taking a trap the processor loads PC with the trap address and executes code at the vector location. **Two words are reserved at each vector location** for a branch instruction to the ISR. Table 8–7 lists vector addresses after reset.
- At reset the vector is mapped absolutely to **0000h**. It can be remapped after reset to the beginning of any **2K-word page** by loading the IPTR bits in PMST with the 2K-word page boundary address. After IPTR is loaded, any user interrupt vector is mapped to the new page. Example: `OPL #05800h,PMST` remaps vectors to start at 5800h (off-chip program space in that example); a subsequent INT2 fetches its vector from 5800h+4 = 5804h instead of 0004h. This lets vectors be moved out of boot ROM and the ROM then removed from the map.
- To set IPTR reliably, clear the bits before executing the OPL (the example assumes IPTR currently cleared).
- **Reset vector cannot be remapped**: reset loads IPTR with 0, so the reset vector is always fetched at 0000h.
- **['C51, 'C53]** 100 words are reserved in on-chip ROM for device testing; application code for on-chip ROM must reserve these 100 words at the **top** of the ROM addresses.

**Table 8–7. 'C5x Interrupt Vector Addresses (PDF p. 479 / printed 8-12) — transcribed in full (locations are offsets added to the IPTR page base; after reset base = 0000h):**

| Name | Location Dec | Location Hex | Priority | Function |
|---|---|---|---|---|
| RS | 0 | 0 | 1 (highest) | External nonmaskable reset signal |
| INT1 | 2 | 2 | 3 | External user interrupt #1 |
| INT2 | 4 | 4 | 4 | External user interrupt #2 |
| INT3 | 6 | 6 | 5 | External user interrupt #3 |
| TINT | 8 | 8 | 6 | Internal timer interrupt |
| RINT | 10 | A | 7 | Serial port receive interrupt |
| XINT | 12 | C | 8 | Serial port transmit interrupt |
| TRNT † | 14 | E | 9 | TDM port receive interrupt |
| TXNT ‡ | 16 | 10 | 10 | TDM port transmit interrupt |
| INT4 | 18 | 12 | 11 | External user interrupt #4 |
| — | 20–23 | 14–17 | N/A | Reserved |
| HINT | 24 | 18 | — | HINT ('C57 only) |
| — | 26–33 | 1A–21 | N/A | Reserved |
| TRAP | 34 | 22 | N/A | Software trap instruction |
| NMI | 36 | 24 | 2 | Nonmaskable interrupt |
| — | 38–39 | 26–27 | N/A | Reserved for emulation and test |
| — | 40–63 | 28–3F | N/A | Software interrupts |

† RINT2 on 'C52; BRNT on 'C56/C57. ‡ XINT2 on 'C52; BXNT on 'C56/C57.

### 8.2.3 Program memory addressing — §8.2.3 (PDF p. 480 / 8-13)

- Program memory is accessed **only by the PAB**. The PAB address is generated by the PC for instructions and long immediate operands; the PAB can also be loaded with long immediate, low accumulator, or registered addresses for block transfers, multiply/accumulates, table read/writes.
- Instruction fetch: PC on PAB, read; PC increments during the read. On address discontinuity (branch, call, return, interrupt, block repeat) the appropriate address is loaded into PC. PC is also loaded when operands are fetched from program memory: TBLR/TBLW, BLPD/BLDP, or second multiplicand fetch (MAC, MACD, MADS, MADD). See §4.1 PC (p. 4-2).
- Operand addressing modes: direct, indirect, short immediate, long immediate, dedicated-register, memory-mapped register (Ch. 5).
- **Address visibility (AVIS):** traces program address flow externally for debugging. **Enabled after reset**; disabled by **setting** the AVIS bit in PMST, enabled by clearing it. In AVIS mode the program address is sent to the address pins even when on-chip program memory is addressed. Memory control signals (PS, RD, etc.) are **not active** in this mode (PDF p. 480 / 8-13).
- Instruction addresses can be externally clocked with the falling edge of **IAQ** (datasheet timings). IAQ addresses include both words of a 2-word instruction but **not** block transfers, table reads, or multiply/accumulate operands. AVIS also allows a specific interrupt trap to be decoded with **IACK**: while IACK is low, address pins A1–A4 identify which interrupt is being acknowledged (datasheet timings) (PDF p. 481 / 8-14).
- Disabling AVIS (set AVIS bit) lowers power consumption and RF noise. If the processor runs while HOLDA is active (HM = 0), the program address is **not** available at the address pins regardless of AVIS mode (PDF p. 481 / 8-14).

### 8.2.4 Program memory protection feature — §8.2.4 (PDF p. 481 / 8-14)

Prevents an instruction fetched from off-chip memory from reading or writing on-chip program memory. The pipeline controller tracks instructions fetched from off-chip memory; if the operand address is in on-chip program space, the instruction reads invalid data off the bus. Limitations (apply when the protection mask option is selected — see Contradictions note):

- Instructions fetched from off-chip memory cannot read or write on-chip single-access and read-only program memory.
- Instructions fetched from DARAM B0 cannot read or write on-chip single-access and read-only program memory.
- Coefficients for off-chip multiply/accumulate instructions cannot reside in on-chip single-access and read-only program memory.
- On-chip single-access memory cannot be mapped to program space.
- On-chip single-access memory cannot be mapped to data space.
- External DMA cannot be used.
- The emulator cannot access on-chip program memory.
- The program memory address range corresponding to on-chip SARAM is not available for external memory.

Use: with on-chip ROM, secures code stored in external memory — ROM code can include a decryption algorithm that decrypts off-chip code and stores the routine in on-chip single-access program RAM. This process-mask option, like the ROM, must be submitted to TI.

## 8.3 Local data memory — §8.3 (PDF pp. 482–486 / printed 8-15–8-19)

64K 16-bit words. All devices: 1056 words DARAM, different SARAM sizes (Table 1–1, p. 1-6). Software configures cells on-/off-chip; CALU address outside bounds → automatic external access. On-chip advantages: higher performance (no wait states; more efficient pipeline operation), lower cost, lower power. Off-chip advantage: larger address space (§8.3, PDF p. 482 / 8-15).

### 8.3.1 Local data memory configurability — §8.3.1 (PDF p. 482 / 8-15)

- At reset, the 1056 words of DARAM are mapped into local data space. B0 can be reconfigured into program space by setting CNF in ST1. SARAM is mapped into data space by setting **OVLY** in PMST.
- Tables 8–8–8–12: all locations in 0000h–0800h not mapped to on-chip memory are **on-chip reserved** locations. 0000h–004Fh = on-chip memory-mapped registers; 0050h–005Fh = memory-mapped I/O ports. All addresses hex.

**Table 8–8. 'C50 Local Data Memory Configuration (PDF p. 483 / 8-16):**

| CNF | OVLY | Registers (96) | DARAM B2 (32) | DARAM B0 (512) | DARAM B1 (512) | SARAM (9K) | Off-chip |
|---|---|---|---|---|---|---|---|
| 0 | 0 | 0000–005F | 0060–007F | 0100–02FF | 0300–04FF | Off-chip | 0800–FFFF |
| 0 | 1 | 0000–005F | 0060–007F | 0100–02FF | 0300–04FF | 0800–2BFF | 2C00–FFFF |
| 1 | 0 | 0000–005F | 0060–007F | Reserved | 0300–04FF | Off-chip | 0800–FFFF |
| 1 | 1 | 0000–005F | 0060–007F | Reserved | 0300–04FF | 0800–2BFF | 2C00–FFFF |

**Table 8–9. 'C51 Local Data Memory Configuration (PDF p. 483 / 8-16):**

| CNF | OVLY | Registers (96) | DARAM B2 (32) | DARAM B0 (512) | DARAM B1 (512) | SARAM (1K) | Off-chip |
|---|---|---|---|---|---|---|---|
| 0 | 0 | 0000–005F | 0060–007F | 0100–02FF | 0300–04FF | Off-chip | 0800–FFFF |
| 0 | 1 | 0000–005F | 0060–007F | 0100–02FF | 0300–04FF | 0800–0BFF | 0C00–FFFF |
| 1 | 0 | 0000–005F | 0060–007F | Reserved | 0300–04FF | Off-chip | 0800–FFFF |
| 1 | 1 | 0000–005F | 0060–007F | Reserved | 0300–04FF | 0800–0BFF | 0C00–FFFF |

**Table 8–10. 'C52 Local Data Memory Configuration (PDF p. 483 / 8-16)** (OVLY = X don't care; no SARAM):

| CNF | OVLY | Registers (96) | DARAM B2 (32) | DARAM B0 (512) | DARAM B1 (512) | SARAM | Off-chip |
|---|---|---|---|---|---|---|---|
| 0 | X | 0000–005F | 0060–007F | 0100–02FF | 0300–04FF | None | 0800–FFFF |
| 1 | X | 0000–005F | 0060–007F | Reserved | 0300–04FF | None | 0800–FFFF |

**Table 8–11. 'C53 and 'C53S Local Data Memory Configuration (PDF p. 483 / 8-16):**

| CNF | OVLY | Registers (96) | DARAM B2 (32) | DARAM B0 (512) | DARAM B1 (512) | SARAM (3K) | Off-chip |
|---|---|---|---|---|---|---|---|
| 0 | 0 | 0000–005F | 0060–007F | 0100–02FF | 0300–04FF | Off-chip | 0800–FFFF |
| 0 | 1 | 0000–005F | 0060–007F | 0100–02FF | 0300–04FF | 0800–13FF | 1400–FFFF |
| 1 | 0 | 0000–005F | 0060–007F | Reserved | 0300–04FF | Off-chip | 0800–FFFF |
| 1 | 1 | 0000–005F | 0060–007F | Reserved | 0300–04FF | 0800–13FF | 1400–FFFF |

**Table 8–12. 'LC56, 'LC57, and 'C57S Local Data Memory Configuration (PDF p. 484 / 8-17):**

| CNF | OVLY | Registers (96) | DARAM B2 (32) | DARAM B0 (512) | DARAM B1 (512) | SARAM (6K) | Off-chip |
|---|---|---|---|---|---|---|---|
| 0 | 0 | 0000–005F | 0060–007F | 0100–02FF | 0300–04FF | Off-chip | 0800–FFFF |
| 0 | 1 | 0000–005F | 0060–007F | 0100–02FF | 0300–04FF | 0800–1FFF | 2000–FFFF |
| 1 | 0 | 0000–005F | 0060–007F | Reserved | 0300–04FF | Off-chip | 0800–FFFF |
| 1 | 1 | 0000–005F | 0060–007F | Reserved | 0300–04FF | 0800–1FFF | 2000–FFFF |

### 8.3.2 Local data memory address map (data page 0) — §8.3.2 (PDF pp. 484–486 / 8-17–8-19)

Data page 0 has five sections: CPU registers, peripheral registers, test/emulation reserved area, I/O space, scratch-pad RAM (Table 8–13).

- **28 CPU registers:** zero wait states. Some accessible via paths other than the data bus (e.g. ARs loaded by ARAU with LAR).
- **Peripheral registers:** control/data registers of peripheral circuits, on a dedicated peripheral bus ("TI Bus"). Require **one wait state** when accessed.
- **Test/emulation reserved area:** used by test/emulation systems for special information transfers. **CAUTION: writing to it can change the device's operational mode and affect the application.**
- **I/O space:** 16 words of I/O space (other than IN/OUT instructions) via the fuller addressing modes of data space. E.g. SAMM can write to an I/O memory-mapped port as OUT does; the external interface acts as if an OUT occurred (IS active). Port addresses are off-chip, subject to external wait states and to the on-chip software wait-state generator like any non-memory-mapped I/O port.
- **Scratch-pad RAM (DARAM B2, 32 words, 0060h–007Fh):** holds overhead variables so larger RAM blocks are not fragmented; supports dual-access; addressable via memory-mapped mode or any data-memory addressing mode.

**Table 8–13. Data Page 0 Address Map — CPU Registers (PDF pp. 485–486 / printed 8-18–8-19).** The 0x00–0x1F rows below are Table 8–13; rows 0x20–0x5F are from Table 9–1 (§9.1.1, PDF pp. 511–513 / printed 9-2–9-4), which Table 8–13's footnote points to. Reset values are from Tables 4–15/4–16 (§4.9, PDF pp. 125–127 / printed 4-46–4-48) and Ch. 4 / Ch. 9 bit summaries, cited per row; "undef." = undefined at reset per §4.9 step 2 (PDF p. 124 / 4-45).

### FULL memory-mapped register map, data addresses 0x00–0x5F

| Dec | Hex | Name | Description | Reset value | R/W behaviour |
|---|---|---|---|---|---|
| 0–3 | 00–03 | — | Reserved | — | Reserved; do not use |
| 4 | 04 | IMR | Interrupt mask register | undef. (not in Table 4–15) | R/W (§4.8.4, PDF p. 119 / 4-40). 1 in a bit enables the corresponding interrupt if INTM = 0. NMI/RS not in IMR |
| 5 | 05 | GREG | Global memory allocation register | Low 8 bits → 0 (Table 4–15); upper 8 bits read as 1s (§8.4.1) — read at reset = FF00h (see Contradictions) | R/W; 8-bit register on the 8 LSBs of the data bus |
| 6 | 06 | IFR | Interrupt flag register | 0000h — all bits → 0, no interrupts pending (Table 4–15) | Read to identify pending interrupts; write 1 to a bit clears that flag (§4.8.3, PDF p. 118 / 4-39). Also cleared by reset and by taking the trap |
| 7 | 07 | PMST | Processor mode status register | 0000h if MP/MC pin = 0; 0008h if pin = 1 (Table 4–3, PDF pp. 87–88 / 4-8–4-9: IPTR 00000, bits 10–8 = 000, AVIS 0, bit 6 = 0, OVLY 0, RAM 0, MP/MC = pin, NDX 0, TRM 0, BRAF 0) | R/W (e.g. OPL/SPLK). Bits 10–8 and bit 6 read as 0 |
| 8 | 08 | RPTC | Repeat counter register | 0000h (Table 4–15) | R/W |
| 9 | 09 | BRCR | Block repeat counter register | undef. (not in Table 4–15) | R/W |
| 10 | 0A | PASR | Block repeat program address start register | undef. (not in Table 4–15) | R/W |
| 11 | 0B | PAER | Block repeat program address end register | undef. (not in Table 4–15) | R/W |
| 12 | 0C | TREG0 | Temporary register 0 (multiplicand) | undef. (not in Table 4–15) | R/W. 'C2x-compatible load of TREG0 also loads TREG1/TREG2 unless TRM = 1 (PMST) |
| 13 | 0D | TREG1 | Temporary register 1 (dynamic shift count) | undef. | R/W |
| 14 | 0E | TREG2 | Temporary register 2 (bit pointer in dynamic bit test) | undef. | R/W |
| 15 | 0F | DBMR | Dynamic bit manipulation register | undef. | R/W |
| 16 | 10 | AR0 | Auxiliary register 0 | undef. | R/W (LAR/SAR/SAMM/LMMR; also ARAU in D phase). 'C2x-compatible AR0 ops also affect INDX/ARCR unless NDX = 1 |
| 17 | 11 | AR1 | Auxiliary register 1 | undef. | R/W |
| 18 | 12 | AR2 | Auxiliary register 2 | undef. | R/W |
| 19 | 13 | AR3 | Auxiliary register 3 | undef. | R/W |
| 20 | 14 | AR4 | Auxiliary register 4 | undef. | R/W |
| 21 | 15 | AR5 | Auxiliary register 5 | undef. | R/W |
| 22 | 16 | AR6 | Auxiliary register 6 | undef. | R/W |
| 23 | 17 | AR7 | Auxiliary register 7 | undef. | R/W |
| 24 | 18 | INDX | Index register | undef. | R/W (E-phase modification; 2-word latency, Ch. 7 Table 7–10) |
| 25 | 19 | ARCR | Auxiliary register compare register | undef. | R/W (E-phase modification; 2-word latency) |
| 26 | 1A | CBSR1 | Circular buffer 1 start register | undef. | R/W (2-word latency) |
| 27 | 1B | CBER1 | Circular buffer 1 end register | undef. | R/W (2-word latency) |
| 28 | 1C | CBSR2 | Circular buffer 2 start register | undef. | R/W (2-word latency) |
| 29 | 1D | CBER2 | Circular buffer 2 end register | undef. | R/W (2-word latency) |
| 30 | 1E | CBCR | Circular buffer control register | CENB1 → 0, CENB2 → 0 (both circular buffers disabled) (Table 4–15) | R/W (2-word latency) |
| 31 | 1F | BMAR | Block move address register | undef. | R/W (1-word latency) |
| 32 | 20 | DRR | Data receive register (serial port) | 0000h (Table 4–16) | Read received data; SP: readable/writable any time; BSP: read-only — DRR writable only in BSP reset (§9.7.1, PDF p. 534 / 9-25) |
| 33 | 21 | DXR | Data transmit register (serial port) | 0000h (Table 4–16) | Write transmit data; SP: readable/writable any time; BSP: write-only, DXR readable any time (§9.7.1, PDF p. 534 / 9-25) |
| 34 | 22 | SPC | Serial port control register | 0800h (XRDY → 1, all other bits → 0; IN0/IN1 reflect CLKR/CLKX pin levels) (Table 4–16; Fig. 9–14, PDF p. 537 / 9-28) | R/W per bit: Free/Soft/RRST/XRST/TXM/MCM/FSM/FO/DLB = R/W; RSRFULL/XSREMPTY/XRDY/RRDY/IN1/IN0/Res = read-only |
| 35 | 23 | — | Reserved | — | Reserved |
| 36 | 24 | TIM | Timer counter register | FFFFh — timer counts down from FFFFh (Table 4–16) | R/W |
| 37 | 25 | PRD | Timer period register | FFFFh — timer disabled (Table 4–16) | R/W |
| 38 | 26 | TCR | Timer control register | 0000h (Soft 0, Free 0, TSS 0, TDDR 0000; PSC loaded from TDDR; TRB read as 0) (Table 4–16; Table 9–4, PDF p. 519 / 9-10) | R/W; bits 15–12 reserved, read as 0; TRB write-only reload (always reads 0) |
| 39 | 27 | — | Reserved | — | Reserved |
| 40 | 28 | PDWSR | Program/data wait-state register | FFFFh — all program/data wait-state fields = 7 (Table 4–16; §9.4.1) | R/W. Layout differs by device ('C50/'C51/'C52 vs 'C53S/'LC56/'C57 — Figs. 9–4/9–5) |
| 41 | 29 | IOWSR | I/O port wait-state register | FFFFh — all I/O wait-state fields = 7 (Table 4–16; §9.4.2, PDF p. 525 / 9-16) | R/W |
| 42 | 2A | CWSR | Wait-state control register | 000Fh (BIG 0, I/O High 1, I/O Low 1, D 1, P 1; bits 15–5 reserved = 0) (Table 4–16; Table 9–9, PDF p. 526 / 9-17) | R/W. Program CWSR before PDWSR/IOWSR (§9.4.3) |
| 43–47 | 2B–2F | — | Reserved for test/emulation | — | Reserved; writes can change operational mode (§8.3.2) |
| 48 | 30 | TRCV / BDRR | TDM data receive register / BSP data receive register | undef. (not in Tables 4–15/4–16) | Read (receive data). Device-dependent: TDM on 'C50/'C51/'C53; BSP on 'C56/'C57 |
| 49 | 31 | TDXR / BDXR | TDM data transmit register / BSP data transmit register | undef. | Write (transmit data) |
| 50 | 32 | TSPC / BSPC | TDM serial port control register / BSP control register | SPC-group bits per Table 4–16 (DLB 0, FO 0, Free 0, FSM 0, MCM 0, RRDY 0, RRST 0, Soft 0, TXM 0, XRDY 1, XRST 0; TDM bit → 0 for TSPC) | R/W per bit (same pattern as SPC; TDM bit TSPC-only) |
| 51 | 33 | TCSR / SPCE | TDM channel select register / BSP control extension register | SPCE: BRE 0, BXE 0, CLKDV 00011, CLKP 0, FE 0, FIG 0, FSP 0, HALTR 0, HALTX 0, PCM 0, RH 0, XH 0 (Table 4–16). TCSR reset: not stated in Tables 4–15/4–16 | R/W |
| 52 | 34 | TRTA / AXR | TDM receive/transmit address register / BSP address transmit register | undef. (not in Tables 4–15/4–16) | R/W |
| 53 | 35 | TRAD / BKX | TDM receive address register / BSP transmit buffer size register | undef. | R/W |
| 54 | 36 | ARR | BSP address receive register | undef. | R/W |
| 55 | 37 | BKR | BSP receive buffer size register | undef. | R/W |
| 56–79 | 38–4F | — | Reserved | — | Reserved |
| 80–95 | 50–5F | PA0–PA15 | Memory-mapped I/O ports 50h–5Fh (PA0 = port 50h … PA15 = port 5Fh) (Table 9–1, PDF pp. 512–513 / 9-3–9-4) | N/A (external) | R/W as data-memory locations; IS active on access. Also accessible via IN/OUT over the full 64K I/O space (§8.5.1) |

Notes on the map table:
- The manual counts **28 CPU registers** (IMR, GREG, IFR, PMST, RPTC, BRCR, PASR, PAER, TREG0–2, DBMR, AR0–7, INDX, ARCR, CBSR1/2, CBER1/2, CBCR, BMAR = 28) and **17 peripheral registers** (DRR, DXR, SPC, TIM, PRD, TCR, PDWSR, IOWSR, CWSR, TRCV/BDRR, TDXR/BDXR, TSPC/BSPC, TCSR/SPCE, TRTA/AXR, TRAD/BKX, ARR, BKR = 17), plus 16 I/O ports (§9.1.1, PDF p. 511 / 9-2).
- **HPIC** (HPI control register, 'C57 only) is listed in Table 4–16 reset states (SMOD 0→1, HINT → 0) but has **no data-page-0 address in Tables 8–13/9–1**; it is accessed via the HPI, not the data bus. Not included in the 0x00–0x5F map.
- All writes to memory-mapped **peripheral** registers (but not processor registers or memory-mapped I/O ports) require **one additional CLKOUT1 cycle** (§9.1.1, PDF p. 511 / 9-2).
- ST0/ST1 are CPU status registers, not data-page-0 memory-mapped registers; their reset states (ST0: INTM → 1, OV → 0; ST1: C → 1, CNF → 0, HM → 1, PM → 0, SXM → 1, XF → 1) are in Table 4–15 (PDF p. 125 / 4-46).

### 8.3.3 Local data memory addressing — §8.3.3 (PDF p. 486 / 8-19)

- Address generation controlled by decode of the current instruction. Local data read via **data address bus 1 (DAB)** for single-operand instructions, via **PAB** for instructions with a second data-memory operand. Operand delivered to CALU as in §8.2.3.
- Address generation modes: direct, indirect, long immediate operand, dedicated-register, memory-mapped register (Ch. 5).

## 8.4 Global data memory — §8.4 (PDF pp. 487–488 / printed 8-20–8-21)

For multiprocessing: allocate global data space, communicate via **BR** (bus request) and **READY**. Extends the data address map by overlaying address space. Shared by >1 processor, so access must be arbitrated. Local section = processor's own function; global section = inter-processor communication (shared-data multiprocessing). Unlike DMA between two processors, reading/writing global memory does **not** require halting a processor (§8.4, PDF p. 487 / 8-20).

### 8.4.1 Configurability — §8.4.1 (PDF p. 487 / 8-20)

- **GREG** (data address 05h) specifies part of data memory as global external memory. 8-bit register, connected to the 8 LSBs of the internal data bus; **upper 8 bits of location 05h are unused and are read as 1s**.
- GREG contents determine global size (256–32K words). Values other than those listed lead to fragmented maps and should be avoided.

**Table 8–14. Global Data Memory Configurations (PDF p. 488 / printed 8-21) — transcribed in full:**

| GREG value (bits 7–0) | Local memory range | Local # words | Global memory range | Global # words |
|---|---|---|---|---|
| 0000 00XX | 0000–FFFF | 65 536 | — | 0 |
| 1000 0000 | 0000–7FFF | 32 768 | 8000–FFFF | 32 768 |
| 1100 0000 | 0000–BFFF | 49 152 | C000–FFFF | 16 384 |
| 1110 0000 | 0000–DFFF | 57 344 | E000–FFFF | 8 192 |
| 1111 0000 | 0000–EFFF | 61 440 | F000–FFFF | 4 096 |
| 1111 1000 | 0000–F7FF | 63 488 | F800–FFFF | 2 048 |
| 1111 1100 | 0000–FBFF | 64 512 | FC00–FFFF | 1 024 |
| 1111 1110 | 0000–FDFF | 65 024 | FE00–FFFF | 512 |
| 1111 1111 | 0000–FEFF | 65 280 | FF00–FFFF | 256 |

Legend: X = don't care. All addresses hex.

### 8.4.2 Addressing — §8.4.2 (PDF p. 487 / 8-20)

- When a data address (direct or indirect) corresponds to a global address (per GREG), **BR is asserted low with DS** to indicate a global access. External logic arbitrates; **READY** is asserted when the 'C5x has control. Memory-cycle length is controlled by READY.
- Software wait-state generators can extend access times for slower external memories; the wait-state generators for the overlapped local-data address space generate the wait states for the corresponding global addresses.

## 8.5 Input/Output (I/O) space — §8.5 (PDF p. 489 / printed 8-22)

- 64K 16-bit parallel I/O ports. Peripherals: codecs, D/A, A/D converters. Access multiplexed over the same address/data bus as program/data accesses.
- **§8.5.1 Addressing:** all 64K ports accessible via **IN** and **OUT**. Example: `IN DAT7,0FFFEh` (read port 65534 to data memory); `OUT DAT7,0FFFFh` (write data memory to port 65535).
- **16 of the 64K ports are memory-mapped to data addresses 50h–5Fh** (PA0–PA15). Accessible via IN/OUT or any instruction that reads/writes a data-memory location. See §9.6 Parallel I/O Ports (p. 9-22).
- Access times modified through software wait-state registers **IOWSR and CWSR**. The **BIG bit in CWSR** determines how I/O space is partitioned. See §9.4 (p. 9-13).

## 8.6 Direct memory access (DMA) — §8.6 (PDF pp. 490–492 / printed 8-23–8-25)

Supports multiprocessing designs requiring DMA of external memory or on-chip single-access RAM: temporarily halting one or more processors so another processor can read/write local off-chip memory or on-chip SARAM. External memory access controlled via **HOLD/HOLDA**; on-chip RAM access via **HOLD, HOLDA, R/W, STRB, BR, IAQ** (§8.6, PDF p. 490 / 8-23).

### 8.6.1 DMA in a master-slave configuration — §8.6.1 (PDF pp. 490–491 / 8-23–8-24)

- Master: general-purpose CPU, another 'C5x, or an A/D converter. Fig. 8–7 (PDF p. 490 / 8-23): master XF → slave HOLD; slave HOLDA → master BIO; slave XF → master INT1–INT4; shared A15–A0 / D15–D0 / R/W through buffer/logic; master data/program memory, slave program/data memory (RAM).
- Master takes control of the slave's external memory by asserting slave **HOLD low via the master's XF pin**; slave places address, data, control lines in high-impedance.
- Slave asserts **HOLDA** when master gains control; HOLDA may be tied to master BIO. Slave XF indicates to master when the slave finished / needs reprogramming or more data. In multiple-slave configurations, priority is set by connecting slaves' XF signals to the appropriate INT1–INT4 pin on the master.
- External bus interface goes high-impedance when HOLDA is asserted. Once HOLDA is active, **IAQ does not indicate an instruction acquisition**.
- While HOLDA is active and CPU is in hold mode (**HM = 0**), the CPU **continues running code from internal memory** (internal ROM or single/dual-access RAM). If CPU is not in hold mode (**HM = 1**), the CPU **halts internal execution**. See §4.9 Reset (p. 4-45) for HOLD/RS/external-interrupt interaction.

### 8.6.2 External DMA — §8.6.2 (PDF pp. 491–492 / 8-24–8-25)

Access to on-chip SARAM by external devices. Required signals:

| Signal | Meaning |
|---|---|
| A(15–0) | Address inputs when HOLDA and BR are low |
| BR | Bus request, externally driven low in hold mode to indicate a request for access |
| D(15–0) | DMA data |
| HOLD | External request for control of address, data, control lines |
| HOLDA | Indication to external circuitry that address/data/control lines are high-impedance, allowing external access |
| IAQ | Acknowledges BR request for access while HOLDA is low |
| R/W | Data-bus direction: high = DMA read, low = DMA write |
| STRB | When IAQ and HOLDA are low, selects the memory access and determines its duration |

- Sequence: master asserts 'C5x **HOLD low** → 'C5x asserts **HOLDA** → master gains bus control, asserts **BR low** → 'C5x asserts **IAQ low** to acknowledge → master drives **R/W** (direction). DMA write: master drives address + data. DMA read: master drives address, latches data. Each access (read/write) is selected when **STRB is low**.
- External-access wait states are added by extending STRB. Address decode of a DMA access uses **only A13–A0 (A14/A15 ignored)**. Table 8–15 lists address ranges during DMA, effectively overlaying A13–A0.
- **DMA to on-chip SARAM is not supported in concurrent hold mode (HM = 0).**
- 'C50 aliasing example: writing to address 01h affects the **second** memory location of the SARAM; writing to 4001h is equivalent to writing 01h, 8001h, and C001h (A14/A15 ignored).
- External parallel interface signals are asynchronously disabled during reset; **external DMA is not supported during reset**.

**Table 8–15. Address Ranges for On-Chip Single-Access RAM During External DMA (PDF p. 492 / printed 8-25):**

| Device | SARAM (words) | Address-bus use | Hex address ranges |
|---|---|---|---|
| 'C50 | 9K | A15–A14 ignored, A13–A0 used | 0000–2BFF, 4000–6BFF, 8000–ABFF, C000–EBFF |
| 'C51 | 1K | A15–A14 ignored, A13–A10 must be 0, A9–A0 used | 0000–03FF, 4000–43FF, 8000–83FF, C000–C3FF |
| 'C53 | 3K | A15–A14 ignored, A13–A12 must be 0, A11–A0 used | 0000–0BFF, 4000–4BFF, 8000–8BFF, C000–CBFF |
| 'LC56 | 6K | A15–A14 ignored, A13 must be 0, A12–A0 used | 0000–17FF, 4000–57FF, 8000–97FF, C000–D7FF |
| 'C57S / 'LC57 | 6K | A15–A14 ignored, A13 must be 0, A12–A0 used | 0000–17FF, 4000–57FF, 8000–97FF, C000–D7FF |

Note: 'C52 has no SARAM and does not appear in Table 8–15.

## 8.7 Memory management — §8.7 (PDF pp. 493–498 / printed 8-26–8-31)

Programmable memory map varies per application; instructions integrate device memory into the system map (Table 1–1, p. 1-6).

### 8.7.1 Memory-to-memory moves — §8.7.1 (PDF pp. 493–494 / 8-26–8-27)

| Instruction group | Members |
|---|---|
| Data/program block moves | BLDD (within data memory), BLDP (data → program), BLPD (program → data) |
| Data/program word transfers | TBLR (program → data), TBLW (data → program) |
| Data move | DMOV — access data and operate on it simultaneously in the same cycle |

- Block moves: one address from the data address generator, the other from a long immediate constant or from **BMAR**. With RPT/RPTZ, block moves run efficiently from on- or off-chip memory.
- **DMOV:** copies a word from the currently addressed data-memory location in on-chip RAM to the next-higher location while the data from the addressed location is operated on in the same cycle (e.g. by the CALU). An ARAU operation can also occur in the same cycle with indirect addressing. Implements the z⁻¹ delay (convolution, digital filtering, data passed through a time window). Equivalent to 'C2x DMOV.
- DMOV is most efficient in dual-access on-chip RAM; in single-access RAM it requires an **additional cycle**. DMOV is **contiguous across the B0/B1 dual-access boundary**. DMOV cannot be performed on external data memory.
- Instructions using DMOV: **LTD** (load TREG0 and accumulate product with data move), **MACD** (multiply and accumulate with data move), **MADD** (multiply and accumulate with data move, coefficient address in BMAR).

### 8.7.2 Memory block moves — §8.7.2 (PDF pp. 494–498 / 8-27–8-31)

**§8.7.2.1 BLDD (data → data)** — external→external, external→internal, internal→internal, internal→external. Ex. 8–1 (PDF p. 494 / 8-27): move external data to internal DARAM B1: `LACC #8000h; SAMM BMAR` (source in data memory); `LAR AR7,#300h; MAR *,AR7` (dest, ARP=AR7); `RPT #511; BLDD BMAR,*+` — moves 512 values to B1; `RET`.

**§8.7.2.2 BLDP / TBLW (data → program)** — external→external, external→internal, internal→internal, internal→external program. BLDP can boot-load a program to on-chip program RAM from external data memory. Ex. 8–2 (PDF p. 495 / 8-28): `LACC #2000h; SAMM BMAR` (dest in program memory, 'C51); `LAR AR7,#0F000h; MAR *,AR7` (source); `RPT #1023; BLDP *+` — 1K values data→program. TBLW differs from BLDP: the **accumulator holds the destination program address**, so a calculated (not predetermined) destination can be used. Ex. 8–3 (PDF p. 496 / 8-29): `LAR AR4,#300h; MAR *,AR4; RPT #511; TBLW *+` — caller puts dest program address in ACC; 512 values.

**§8.7.2.3 BLPD / TBLR (program → data)** — external→external, external→internal, internal→internal, internal→external data. Used to load coefficient tables from program memory into internal data memory when no external data memory exists. Ex. 8–4 (PDF p. 497 / 8-30): `LAR AR7,#300h; MAR *,AR7; RPT #127; BLPD #0FD00h,*+` — 128 values external program → B1. TBLR differs from BLPD: the **accumulator holds the source program address** (calculated location). Ex. 8–5 (PDF p. 497 / 8-30): `LAR AR3,#300h; MAR *,AR3; RPT #127; TBLR *+` — caller puts source program address in ACC; 128 values.

**§8.7.2.4 LMMR (data → I/O)** — transfers data from external or internal data memory to an external I/O port. Ex. 8–6 (PDF p. 498 / 8-31): `LDP #0; RPT #63; LMMR 50h,#800h` — 64 values from table at 800h to memory-mapped port 50h; source address incremented. Note: 16 I/O ports are mapped in data page 0.

**§8.7.2.5 SMMR (I/O → data)** — transfers data from an external I/O port to external or internal data memory. Ex. 8–7 (PDF p. 498 / 8-31): `LDP #0; RPT #511; SMMR 51h,#800h` — 512 values from port 51h to table at 800h; dest address incremented.

## 8.8 Boot loader — §8.8 (PDF pp. 499–505 / printed 8-32–8-38)

Several 'C5x devices include a boot-loader program in on-chip ROM (part-numbering nomenclature: Appendix G). Main function: transfer code from an external source to program memory at power-up — serial interface for some applications, parallel interface when code is already in nonvolatile ROM (§8.8, PDF p. 499 / 8-32).
- If MP/MC is sampled **low** during hardware reset, execution begins at program address 0000h of on-chip ROM, which contains a branch to the boot-loader program. The ROM is factory-programmed with the boot loader.
- **Boot-loader CPU setup before loading:**
  - Interrupts globally disabled (INTM = 1).
  - DARAM B0 mapped into program space (CNF = 1).
  - SARAM mapped into program space (RAM = 1, OVLY = 0).
  - Entire program and data memory spaces enabled with **seven wait states**.
  - 32K words of global data memory enabled initially in data spaces 8000h–FFFFh. After the code transfer, global memory is **disabled** before control is transferred to the destination address in program memory.
  - Both DARAM and SARAM enabled in program space, so code can be transferred to on-chip program memory.
- The boot loader reads global data memory location **FFFFh** by driving **BR and DS low**. The **lower 8 bits** of the word at FFFFh specify the boot mode; the higher 8 bits are ignored.

**Figure 8–8. Boot Routine Selection Word (PDF p. 500 / printed 8-33) — transcribed in full (word at global data FFFFh):**

| Bits 15–8 | Bits 7–4 | Bits 3–0 | Boot mode |
|---|---|---|---|
| XXXXXXXX | XXXX | 0000 | 8-bit serial mode |
| XXXXXXXX | XXXX | 0100 | 16-bit serial mode |
| XXXXXXXX | XXXX | 1000 | 8-bit parallel I/O mode |
| XXXXXXXX | XXXX | 1100 | 16-bit parallel I/O mode |
| XXXXXXXX | SRC (bits 7–2) | 01 | 8-bit parallel EPROM mode |
| XXXXXXXX | SRC (bits 7–2) | 10 | 16-bit parallel EPROM mode |
| XXXXXXXX | ADDR (bits 7–2) | 11 | Warm boot |

Legend: X = don't care; SRC = 6-bit page address for parallel EPROM modes; ADDR = 6-bit page address for warm boot mode.
Note: the HPI boot mode is **not** selected by this word — it is detected first by the HINT/INT3 test (§8.8.1).

### 8.8.1 HPI boot mode ('C57 only) — §8.8.1 (PDF pp. 500–501 / 8-33–8-34)

- Select by connecting **HINT to INT3**: this sets the INT3 bit in IFR when HINT is asserted low. The boot loader asserts HINT low, waits **10 CLKOUT1 cycles**, reads the INT3 bit. If set (INT3 pending), control transfers to the start address of on-chip HPI RAM (**8800h in program space**) and user code executes from there. If not set, the boot loader skips HPI mode and reads the boot routine selection word at global FFFFh.
- Host must download code to HPI RAM **before** bringing the 'C5x out of reset. The boot loader keeps HPI in shared-access mode (**SMOD = 1**) during the entire boot-load operation. Once HINT is asserted low by the boot loader, HINT remains low until a host clears it by writing to HPIC.
- Alternative to the HINT–INT3 connection: send a valid interrupt to INT3 within **30 CLKOUT1 cycles** after the 'C5x fetches the reset vector (reset-vector fetch timing: TMS320C5x data sheet).
- Warm boot (§8.8.5) is the alternative to HPI boot if connecting HINT to INT3 is inconvenient, or if the program has already been transferred to program memory.

### 8.8.2 Serial boot mode — §8.8.2 (PDF pp. 501–502 / 8-34–8-35)

- SPC is set to **00F8h for 16-bit** word transfer or **00FCh for 8-bit** word transfer (SPC bits: §9.7.1, p. 9-24).
- **XF pin** signals readiness for the serial-port receive section: set high at reset, driven low to initiate reception. No frame-sync pulses on FSR before XF goes low. Receive clock supplied by an external device.
- **§8.8.2.1 16-bit word serial transfer (Fig. 8–9, PDF p. 501 / 8-34):** first 16-bit word = destination address (Destination16) in program memory; second = length (Length16); then N code words. N does **not** include the first two words. After N words, the 'C5x branches to the destination address. **length N = number of 16-bit words − 1.**
- **§8.8.2.2 8-bit word serial transfer (Fig. 8–10, PDF p. 502 / 8-35):** high byte then low byte form each 16-bit word. First word = destination (Destinationh/Destinationl); second = length (Lengthh/Lengthl); then N code words. N does not include the first four bytes (first two 16-bit words). After transfer, branch to destination. **length N = number of 16-bit words − 1, or (number of bytes to be transferred ÷ 2) − 1.**

### 8.8.3 Parallel EPROM boot mode — §8.8.3 (PDF pp. 502–503 / 8-35–8-36)

- Used only when code is stored in EPROMs (8- or 16-bit wide). Code transfers from **global data memory (starting at the source address)** to **program memory (starting at the destination address)**. The **six MSBs of the source address** are specified by the **SRC** field of the boot routine selection word (Fig. 8–8). A 16-bit source address is defined by SRC as in Fig. 8–11 (PDF p. 502 / 8-35): bits 15–10 = SRC, bits 9–0 = 0 (i.e. source = SRC × 1024, a 1K-word page boundary). The 'C5x transfers control to the **source** address after disabling global data memory. [Wording as printed: "transfers control to the source address" — INFERENCE: in context this is the destination address branched to after the transfer, as in §§8.8.2/8.8.3.1; the manual's sentence is reproduced verbatim here and flagged.]
- **§8.8.3.1 16-bit word parallel transfer (Fig. 8–9):** boot code read in 16-bit words starting at the source address; source incremented by 1 after every read. First word = Destination16, second = Length16, then N code words (N excludes the first two words). After transfer, branch to destination. **length N = number of 16-bit words − 1.** At least a **4-instruction-cycle delay** between a read from the EPROM and a write to the destination address — ensures time to turn off the source memory (e.g. EPROM) before the write if the destination is external (e.g. fast SRAM).
- **§8.8.3.2 8-bit word parallel transfer (Fig. 8–10):** two consecutive memory locations from the source address form a 16-bit word; high-order byte followed by low-order byte; data read from the **lower eight data lines**, higher byte on the bus ignored. First word = destination (Destinationh/l), second = length (Lengthh/l), then N code words. **length N = number of 16-bit words − 1, or (number of bytes ÷ 2) − 1.** Same ≥ 4-instruction-cycle read-to-write delay as §8.8.3.1.

### 8.8.4 Parallel I/O boot mode — §8.8.4 (PDF p. 504 / 8-37)

- Asynchronously transfers code from **I/O port 50h** to internal or external program memory. Each word 16 or 8 bits. The 'C5x communicates with the external device via **BIO and XF**, letting a slow host communicate by polling/driving BIO and XF. The handshake protocol of Fig. 8–12 (PDF p. 504 / 8-37) must be used for each word via I/O port 50h: host requests data transmit → 'C5x ready to receive → host data valid → 'C5x acknowledges data received; then next word transfer.
- 8-bit mode: two consecutive 8-bit words form a 16-bit word, high byte then low byte, read from the lower eight data lines of port 50h, higher byte ignored. Destination/length code words: as in §8.8.3 (parallel EPROM).
- At least a **4-instruction-cycle delay between the XF rising edge and a write to the destination address** (host time to turn off data buffers if the destination is external). The 'C5x accesses the external bus **only when XF is high**.

### 8.8.5 Warm boot mode — §8.8.5 (PDF pp. 504–505 / 8-37–8-38)

- Boot loader runs but **moves no code**; control is simply transferred to the entry address. Use when the program was already transferred to internal/external memory by other means (e.g. HPI or external DMA), or when only a warm device reset is required.
- The **six MSBs of the entry address** are specified by the **ADDR** field of the boot routine selection word (Fig. 8–8). A 16-bit entry address is defined by ADDR as in Fig. 8–13 (PDF p. 505 / 8-38): bits 15–10 = ADDR, bits 9–0 = 0 (entry = ADDR × 1024). The 'C5x transfers control to the entry address **after disabling global data memory**.
- For 'C57 devices, warm boot can be used instead of HPI boot to transfer control to the on-chip HPI RAM.

## 8.9 External parallel interface operation — §8.9 (PDF pp. 506–508 / printed 8-39–8-41)

- All bus cycles comprise integral numbers of CLKOUT1 cycles. **One CLKOUT1 cycle = one falling edge of CLKOUT1 to the next falling edge.**
- Full-speed, 0-wait-state: **reads require 1 cycle**. A write immediately preceded by a read, or immediately followed by a read, requires **3 cycles**. Timings: Fig. 8–14 (p. 8-40), Fig. 8–15 (p. 8-41), Fig. 8–16 (p. 8-41).
- **Read cycles:** STRB goes low and ADDRESS becomes valid with the **falling edge** of CLKOUT1. 0-wait-state read: RD goes low with the **rising edge** of CLKOUT1, high at the next falling edge. 1-wait-state (multicycle) read: RD stays low, goes high with the falling edge of CLKOUT1 before the next cycle, even if cycles are contiguous. Read data is sampled at the **rising edge of RD**.
- **R/W:** goes high at least one half CLKOUT1 cycle before any read cycle; for contiguous reads, STRB stays low. At the end of a read cycle or sequence of reads, STRB and RD go high on the falling edge of CLKOUT1.
- **Write cycles:** always at least **one inactive (pad) cycle** of CLKOUT1 before **and** after the actual write, including contiguous writes (smooth transition between write and adjacent operations). During the pad cycle STRB and WE are always high. R/W always changes state on the **rising edge** of CLKOUT1 during the pad cycle before and after a write or series of writes (prevents bus contention on read/write transitions). For a series of writes, R/W stays low.
- **Write address timing:** between writes, and for the first and last write in a series, ADDRESS becomes valid on the **rising edge** of CLKOUT1. Exception: if a read immediately follows a write or series of writes, ADDRESS becomes valid for that read one half cycle early — on the **rising edge** rather than the falling edge of CLKOUT1.
- **Actual write:** STRB and WE both go low on the falling edge of CLKOUT1 and stay low until the next falling edge (0-wait-state). For 1-wait-state (multicycle) writes, STRB and WE remain low but go high again on the falling edge of CLKOUT1 at the beginning of the pad cycle. Write data is driven approximately at the falling edge of STRB/WE and held approximately one half CLKOUT1 cycle after STRB/WE go high (actual timings: TMS320C5x data sheet).
- **Signal skew:** transitions on control outputs (CLKOUT1, STRB, WE, RD) are initiated by the same two internal clocks and use the same output buffer circuitry, so they switch within close tolerances (data sheet). Transitions on the address bus and related outputs (IS, PS, DS, R/W, BR) are initiated by the same internal signals but different logic, so they typically occur **later** than control-line transitions. Control-output timings vs CLKOUT1: data sheet. Address timings vs CLKOUT1 are derived from address timings for control signals + control-signal timings for CLKOUT1, e.g. delay from CLKOUT1 falling to address-bus valid at the start of a read cycle = [H − (address setup to RD)] + maximum positive RD-to-CLKOUT1 skew (data sheet values).
- **Fig. 8–14 (PDF p. 507 / 8-40) Read-Read-Write, zero wait states:** 1-cycle read, 1-cycle read, 3-cycle write.
- **Fig. 8–15 (PDF p. 508 / 8-41) Write-Write-Read, zero wait states:** first write 2-cycle, second write 3-cycle (read-adjacent), read 1-cycle.
- **Fig. 8–16 (PDF p. 508 / 8-41) Read-Write, one wait state:** 2-cycle read with one READY-generated wait state; 4-cycle write with one READY-generated wait state.

## 8.10 Software wait-state generation — §8.10 (PDF p. 509 / printed 8-42)

- Software-programmable wait-state generators extend external bus cycles by **up to seven machine cycles**. All external reads require ≥ 1 machine cycle; all external writes ≥ 2 machine cycles. An external write immediately followed or preceded by an external read requires **3 cycles** (Figs. 8–14/8–15).
- Wait states from software-programmable generators **or** the hardware **READY** line. Software generators: max 7 wait states. Devices needing > 7 wait states use the hardware READY line.
- **Software vs READY asymmetry:** if the on-chip wait-state generator adds wait states, the number of CLKOUT1 cycles required for writes is **not affected until two or more wait states are specified**, contrary to READY-generated wait states. Table 8–16 gives the cycle counts.
- **READY sampling:** the external READY input is sampled **only after the internal software wait states complete**. If READY is driven low before software wait states complete, no wait states are added until the specified software wait states are done; wait states are added only if READY is still low afterwards. READY is **not an asynchronous input**; its setup/hold times (TMS320C5x data sheet) must be met or significant device malfunction will result.
- **Register detail: Ch. 9 §9.4, Software-Programmable Wait-State Generators (p. 9-13)** — PDWSR (0x28), IOWSR (0x29), CWSR (0x2A) bit layouts and wait-state field mappings. Reset values: PDWSR = FFFFh, IOWSR = FFFFh, CWSR = 000Fh (Table 4–16, PDF p. 126 / 4-47).

**Table 8–16. Number of CLKOUT1 Cycles Per Access for Various Numbers of Wait States (PDF p. 509 / printed 8-42) — transcribed in full as printed (rows for 0–3 wait states only; see Gaps):**

| Number of wait states | Hardware wait state — Read | Hardware wait state — Write | Software wait state — Read | Software wait state — Write |
|---|---|---|---|---|
| 0 | 1 | 2n + 1 | 1 | 2n + 1 |
| 1 | 2 | 3n + 1 | 2 | 2n + 1 |
| 2 | 3 | 4n + 1 | 3 | 3n + 1 |
| 3 | 4 | 5n + 1 | 4 | 4n + 1 |

† n = number of consecutive write cycles.

## Figures / tables in Ch. 8 (all accounted for)

Figs. 8–1 to 8–16: 8–1 'C50 map (PDF p. 471 / 8-4), 8–2 'C51 map (PDF p. 471 / 8-4), 8–3 'C52 map (PDF p. 472 / 8-5), 8–4 'C53/'C53S map (PDF p. 472 / 8-5), 8–5 'LC56/'LC57 map (PDF p. 473 / 8-6), 8–6 'C57S map (PDF p. 473 / 8-6), 8–7 DMA master-slave (PDF p. 490 / 8-23), 8–8 boot selection word (PDF p. 500 / 8-33), 8–9 16-bit transfer (PDF p. 501 / 8-34), 8–10 8-bit transfer (PDF p. 502 / 8-35), 8–11 EPROM source address (PDF p. 502 / 8-35), 8–12 handshake (PDF p. 504 / 8-37), 8–13 warm-boot entry address (PDF p. 505 / 8-38), 8–14 read-read-write (PDF p. 507 / 8-40), 8–15 write-write-read (PDF p. 508 / 8-41), 8–16 read-write 1 wait state (PDF p. 508 / 8-41).
Tables 8–1 to 8–16: 8–1 (PDF p. 475 / 8-8), 8–2/8–3 (PDF p. 476 / 8-9), 8–4/8–5 (PDF p. 477 / 8-10), 8–6 (PDF p. 478 / 8-11), 8–7 (PDF p. 479 / 8-12), 8–8–8–11 (PDF p. 483 / 8-16), 8–12 (PDF p. 484 / 8-17), 8–13 (PDF pp. 485–486 / 8-18–8-19), 8–14 (PDF p. 488 / 8-21), 8–15 (PDF p. 492 / 8-25), 8–16 (PDF p. 509 / 8-42). Examples 8–1 to 8–7 as cited in §8.7.2.

## Contradictions, apparent contradictions, and gaps — Ch. 8

1. **GREG reset value — apparent contradiction, resolved.** Table 4–15 (§4.9, PDF p. 125 / printed 4-46) says GREG "All bits → 0 / All data memory space is configured as local". §8.4.1 (PDF p. 487 / 8-20) says GREG is 8-bit on the 8 LSBs and "the upper eight bits of location 05h are unused and are read as 1s". **Both readings recorded.** Normative treatment: the stored 8 GREG bits are 0 at reset (so no global memory, consistent with Table 8–14 row 1), while a **read** of address 05h at reset returns FF00h because the unused upper byte reads as 1s. The Table 4–15 entry describes the register bits, not the read value of the full 16-bit location.
2. **Program-memory protection vs normal SARAM mapping — scoped, not contradictory.** §8.2.4 (PDF p. 481 / 8-14) says "the on-chip single-access memory cannot be mapped to program space" and "cannot be mapped to data space", while §8.2.1/§8.3.1 describe mapping SARAM into program space (RAM bit) and data space (OVLY bit). **Both readings recorded.** Normative treatment: the §8.2.4 bullets apply only when the protection mask option is selected (the section introduces the feature as a maskable option); the RAM/OVLY mapping is the normal unprotected behaviour. The manual does not explicitly state the scoping sentence; the section heading "Program Memory Protection Feature" is the basis for the scoping.
3. **§8.8.3 wording.** "The 'C5x transfers control to the source address after disabling global data memory" (PDF p. 502 / 8-35). Read literally this says control goes to the *source* address; §§8.8.2/8.8.3.1 say control branches to the *destination* address after the transfer. Flagged as printed; INFERENCE in §8.8.3 above that the intended target is the destination address.
4. **Table 8–16 coverage gap.** §8.10 text says wait-state generators extend cycles "by up to seven machine cycles", but Table 8–16 (PDF p. 509 / 8-42) prints rows only for 0–3 wait states. Rows for 4–7 wait states are **not in the manual** as printed; the pattern (hardware read = w+1; hardware write = (w+2)n+1; software read = w+1; software write = (w+1)n+1 for w ≥ 2) is an INFERENCE and was not added to the table.
5. **Table 8–6 'C57S row CNF=0, RAM=0, MP/MC=0** lists off-chip as 8000–FFFF (not 0800–FFFF as in the 'C50 analogue, where the same bit combination gives off-chip 0800–FFFF with the 2K ROM on-chip). Transcribed as printed (verified against the rendered page image). In that row the range 0800h–7FFFh is left unaccounted for by any column — the SARAM program window is 8000h–97FFh, so it does not explain the gap. Recorded as printed; no correction attempted.
6. **MMR reset values — coverage.** Tables 8–13/9–1 give no reset values. Values in the map table above come from Tables 4–15/4–16 and Ch. 4/Ch. 9 bit summaries (cited per row). Registers not listed there (IMR, BRCR, PASR, PAER, TREG0–2, DBMR, AR0–7, INDX, ARCR, CBSR/CBER, BMAR, TRCV/BDRR, TDXR/BDXR, TCSR, TRTA/AXR, TRAD/BKX, ARR, BKR) are **undefined at reset** per §4.9 — marked "undef.", not guessed.
7. **No unverified/garbled items remain in the transcribed tables.** All box-drawing-garbled tables (8–1–8–16) were verified against rendered page images at 150 dpi.
