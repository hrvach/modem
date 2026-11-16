# TMS320C5x DSP Emulator Implementation Specification
**Reference Document:** Texas Instruments *TMS320C5x User’s Guide* (`SPRU056D`)  
**Target:** Cycle- and Bit-Accurate Software / RTL Emulator Implementation  

---

## Agent Navigation Index
Use this index to jump directly to specific subsystems or implementation rules:

* **Chapter 1: System Architecture, Memory Maps & Bus Model** (`#chapter-1`)
  * `1.1` Core Topology & Pipeline Stages
  * `1.2` Address Spaces & Device Variant Memory Table
  * `1.3` Memory Mapping Control Matrix (`CNF`, `OVLY`, `RAM`, `MP/MC`, `GREG`)
  * `1.4` Memory-Mapped Registers (`00h–5Fh`)
* **Chapter 2: CPU Register File, Status Flags & Reset States** (`#chapter-2`)
  * `2.1` Core Data, Address & Control Registers
  * `2.2` Status Register 0 (`ST0`) Bitfield Specification
  * `2.3` Status Register 1 (`ST1`) Bitfield Specification
  * `2.4` Processor Mode Status Register (`PMST`) Bitfield Specification
* **Chapter 3: Addressing Modes & Pointer Arithmetic** (`#chapter-3`)
  * `3.1` Direct & Memory-Mapped Register Addressing
  * `3.2` Indirect Addressing & `ARP`/`ARB` Update Mechanics
  * `3.3` Bit-Reversed Addressing (`*BR0+`, `*BR0-`)
  * `3.4` Circular Buffer Addressing (`CBSR1/2`, `CBER1/2`, `CBCR`)
  * `3.5` Immediate & Dedicated Register Addressing
* **Chapter 4: ALU, Multiplier, Shifters & Hardware Loops** (`#chapter-4`)
  * `4.1` Central ALU, Saturation (`OVM`), Carry (`C`) & Sign-Extension (`SXM`)
  * `4.2` Parallel Logic Unit (`PLU`) & `DBMR`
  * `4.3` Hardware Multiplier & Product Shifter (`PM`)
  * `4.4` Scaling Shifter & Auxiliary Register Arithmetic Unit (`ARAU`)
  * `4.5` Hardware Loop Mechanics (`RPT` / `RPTC` & `RPTB` / `BRCR` / `PASR` / `PAER`)
* **Chapter 5: Pipeline Execution, Hazards, Branches & Interrupts** (`#chapter-5`)
  * `5.1` 4-Stage Pipeline & Dual-Access Conflict Rules
  * `5.2` Standard vs. Delayed Branches & Calls (`Z`-Suffix Instructions)
  * `5.3` Hardware Stack (`STACK`) Behavior
  * `5.4` Interrupt Vector Table, Masking & Context Save/Restore
  * `5.5` Reset Sequence & Power-Down Modes (`IDLE`, `IDLE2`)
* **Chapter 6: Complete Instruction Set & Opcode Encoding Reference** (`#chapter-6`)
  * `6.1` Instruction Syntax & Operand Notation Key
  * `6.2` Accumulator, Arithmetic & Logic Instructions
  * `6.3` Multiply & Multiply-Accumulate Instructions
  * `6.4` Auxiliary Register & Data Page Instructions
  * `6.5` Parallel Logic Unit (`PLU`) Instructions
  * `6.6` Load, Store & Block Move Instructions
  * `6.7` Branch, Call, Return, Repeat & Control Instructions
  * `6.8` I/O & System Control Instructions

---

<a name="chapter-1"></a>
## Chapter 1: System Architecture, Memory Maps & Bus Model

### 1.1 Core Topology & Pipeline Stages
* **Architecture:** 16-bit fixed-point DSP implementing a modified Harvard architecture with separate program and data spaces, enabling simultaneous instruction fetch and data operand access.
* **Internal Buses:**
  * `PAB` (16-bit Program Address Bus) & `PB` (16-bit Program Data Bus).
  * `DAB` (16-bit Data Address Bus) & `DB` (16-bit Data Data Bus).
* **Pipeline:** 4-stage pipeline (**Fetch**, **Decode**, **Read**, **Execute**). Most instructions execute in 1 single machine cycle (`CLKOUT1` period) once the pipeline is filled.

### 1.2 Address Spaces & Device Variant Memory Table
The CPU addresses **224K × 16-bit words** across four distinct address spaces:
1. **Program Space (`64K × 16`):** `0000h–FFFFh` (Reset vector at `0000h`, interrupt vectors at `(IPTR << 11) | (vec << 1)`).
2. **Local Data Space (`64K × 16`):** `0000h–FFFFh`, partitioned into 512 pages of 128 words each (`DP[8:0]`).
3. **Global Data Space (`32K × 16`):** `8000h–FFFFh`, dynamically mapped over upper local data space via `GREG`.
4. **I/O Space (`64K × 16`):** `0000h–FFFFh`, accessed via `IN` and `OUT`. Ports `PA0–PA15` (`0000h–000Fh`) are additionally memory-mapped to local data addresses `0050h–005Fh`.

| Device | DARAM `B0` | DARAM `B1` | DARAM `B2` | On-Chip SARAM | On-Chip Mask ROM |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **TMS320C50** | `512 × 16` | `512 × 16` | `32 × 16` | `9K × 16` (`0800h–2BFFh`) | `2K × 16` (`0000h–07FFh`) |
| **TMS320C51** | `512 × 16` | `512 × 16` | `32 × 16` | `1K × 16` (`0800h–0BFFh`) | `8K × 16` (`0000h–1FFFh`) |
| **TMS320C52** | `512 × 16` | `512 × 16` | `32 × 16` | None (`0K`) | `4K × 16` (`0000h–0FFFh`) |
| **TMS320C53 / C53S** | `512 × 16` | `512 × 16` | `32 × 16` | `3K × 16` (`0800h–13FFh`) | `16K × 16` (`0000h–3FFFh`) |
| **TMS320LC56 / LC57** | `512 × 16` | `512 × 16` | `32 × 16` | `6K × 16` (`0800h–1FFFh`) | `32K × 16` (`0000h–7FFFh`) |
| **TMS320C57S** | `512 × 16` | `512 × 16` | `32 × 16` | `6K × 16` (`0800h–1FFFh`) | `2K × 16` (`0000h–07FFh`) |

* **DARAM Fixed Address Ranges:**
  * `B2`: Always Local Data `0060h–007Fh`.
  * `B1`: Always Local Data `0300h–04FFh`.
  * `B0`: Local Data `0100h–02FFh` when `ST1.CNF = 0`; Program Space `FE00h–FFFFh` when `ST1.CNF = 1`.
* **SARAM Block Partitioning:** SARAM is organized into `2K × 16` blocks (plus a `1K × 16` tail block on `'C50`/`'C51`/`'C53`). Simultaneous program fetch and data access to *different* SARAM blocks execute in 1 cycle; simultaneous accesses to the *same* SARAM block incur a **1-cycle stall**.

### 1.3 Memory Mapping Control Matrix
* **Data Space Mapping:**
  * `0000h–005Fh`: Memory-Mapped Registers (`MMRs`).
  * `0060h–007Fh`: DARAM `B2`.
  * `0080h–00FFh`: Reserved / External.
  * `0100h–02FFh`: DARAM `B0` if `CNF = 0`; External Data if `CNF = 1`.
  * `0300h–04FFh`: DARAM `B1`.
  * `0500h–07FFh`: Reserved / External.
  * `0800h–(0800h + SARAM_SIZE - 1)`: On-chip SARAM if `PMST.OVLY = 1`; External Data if `PMST.OVLY = 0`.
  * **Global Data Space (`GREG`):** `GREG[7:0]` specifies the size of global data memory at the top of data space (`8000h–FFFFh`). If `GREG = 00h`, all `64K` is local. Otherwise, addresses `>= (0x100 - GREG) << 8` map to Global Data Space (note: `GREG` must be `<= 80h`, capping global space at `32K` words).
* **Program Space Mapping:**
  * `0000h–(ROM_SIZE - 1)`: On-chip Mask ROM if `PMST.MP/MC = 0`; External Program if `PMST.MP/MC = 1`.
  * `0800h–(0800h + SARAM_SIZE - 1)`: On-chip SARAM if `PMST.RAM = 1` (takes priority over ROM if overlapping).
  * `FE00h–FFFFh`: DARAM `B0` if `ST1.CNF = 1`; External Program if `ST1.CNF = 0`.

### 1.4 Memory-Mapped Registers (`00h–5Fh`)
Located in Data Page 0 (`0000h–005Fh`), accessible via standard page-0 direct/indirect operations or from any page via `LAMM`, `SAMM`, `LMMR`, `SMMR`:

| Address | Symbol | Name | Address | Symbol | Name |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `00h–03h` | — | Reserved | `19h` | `AR6` | Auxiliary Register 6 |
| `04h` | `IMR` | Interrupt Mask Register | `1Ah` | `AR7` | Auxiliary Register 7 |
| `05h` | `GREG` | Global Memory Allocation Reg | `1Bh` | `INDX` | Index Register |
| `06h` | `IFR` | Interrupt Flag Register | `1Ch` | `ARCR` | Auxiliary Compare Register |
| `07h` | `PMST` | Processor Mode Status Reg | `1Dh` | `CBSR1` | Circular Buffer 1 Start Reg |
| `08h` | `RPTC` | Repeat Counter Register | `1Eh` | `CBER1` | Circular Buffer 1 End Reg |
| `09h` | `BRCR` | Block Repeat Counter Reg | `1Fh` | `CBSR2` | Circular Buffer 2 Start Reg |
| `0Ah` | `PASR` | Block Repeat Start Address | `20h` | `CBER2` | Circular Buffer 2 End Reg |
| `0Bh` | `PAER` | Block Repeat End Address | `21h` | `CBCR` | Circular Buffer Control Reg |
| `0Ch` | `TREG0` | Temporary Reg 0 (Multiplicand)| `22h` | `BMAR` | Block Move Address Register |
| `0Dh` | `TREG1` | Temporary Reg 1 (Dynamic Shift)| `23h` | `DRR` | Serial Port Data Receive Reg |
| `0Eh` | `TREG2` | Temporary Reg 2 (Bit Pointer) | `24h` | `DXR` | Serial Port Data Transmit Reg |
| `0Fh` | `DBMR` | Dynamic Bit Manipulation Reg | `25h` | `SPC` | Serial Port Control Register |
| `10h` | `AR0` | Auxiliary Register 0 | `26h–29h`| — | Timer (`TIM`, `PRD`, `TCR`) / Reserved |
| `11h` | `AR1` | Auxiliary Register 1 | `2Ah–2Fh`| — | Wait-State / TDM / BSP Peripherals |
| `12h–18h` | `AR2–AR5` | Auxiliary Registers 2–5 | `50h–5Fh`| `PA0–PA15`| Memory-Mapped I/O Ports 0–15 |

*(Note: `ST0`, `ST1`, `ACC`, `ACCB`, `PREG`, `PC`, and `STACK` are **not** memory-mapped.)*

---

<a name="chapter-2"></a>
## Chapter 2: CPU Register File, Status Flags & Reset States

### 2.1 Core Data, Address & Control Registers
* **`ACC` (`32-bit`):** Primary accumulator (`ACCH` = bits `31:16`, `ACCL` = bits `15:0`). Undefined at reset.
* **`ACCB` (`32-bit`):** Accumulator buffer (`ACCBH`:`ACCBL`) used by `EXAR`, `LACB`, `SACB`, `ADCB`, `SBCB`, `CRGT`, `CRLT`, `ORDB`, `ANDB`, `XORB`. Undefined at reset.
* **`PREG` (`32-bit`):** Product register holding the `16×16` signed/unsigned product (`PREGH`:`PREGL`). Undefined at reset.
* **`TREG0` (`16-bit`):** Multiplicand register for multiply instructions.
* **`TREG1` (`5-bit`):** Dynamic shift count register. Bits `3:0` specify left shift (`0–15`) for `ADDT`, `LACT`, `SUBT` and right shift (`0–15`) for `SATL`. Bit `4` (`0` or `1`) specifies `0` or `16`-bit right shift for `SATH`.
* **`TREG2` (`4-bit`):** Dynamic bit index (`0–15`) for `BITT`.
* **`AR0–AR7` (`8 × 16-bit`):** Auxiliary registers addressed by `ST0.ARP`.
* **`INDX` (`16-bit`), `ARCR` (`16-bit`), `BMAR` (`16-bit`), `DBMR` (`16-bit`):** Auxiliary step, compare, block move address, and PLU mask registers.
* **`PC` (`16-bit`), `PFC` (`16-bit`), `MCS` (`16-bit`), `IREG` (`16-bit`):** Program counter (`0000h` on reset), prefetch counter, 1-level microcall stack (used by `BLDD`/`BLPD`/`BLDP` during `RPT`), and instruction register.
* **`STACK` (`8 × 16-bit`):** Hardware LIFO stack for return addresses and `PUSH`/`POP`/`PSHD`/`POPD`.

### 2.2 Status Register 0 (`ST0`) Bitfield Specification
Accessed via `LST #0` and `SST #0`:

| Bit(s) | Field | Reset | Description |
| :--- | :--- | :--- | :--- |
| `15–13` | `ARP` | `X` | **Auxiliary Register Pointer:** Selects active `AR0–AR7` (`000`–`111`). |
| `12` | `OV` | `0` | **Overflow Flag:** Set on signed 32-bit ALU overflow. Sticky until cleared by `RS`, `LST #0`, or conditional branch testing `OV`/`NOV`. |
| `11` | `OVM` | `X` | **Overflow Mode:** `0` = normal 32-bit wrap-around; `1` = saturate `ACC` to `007FFFFFFFh` (+max) or `FF80000000h` (-min) on overflow. |
| `10` | `1` | `1` | Reserved; always reads as `1`. |
| `9` | `INTM` | `1` | **Interrupt Mode:** `0` = all unmasked interrupts enabled; `1` = all maskable interrupts disabled (`NMI` and `RS` unaffected). Automatically set to `1` on interrupt acknowledge. |
| `8–0` | `DP` | `X` | **Data Page Pointer:** Upper 9 bits of direct data memory address (`512` pages of `128` words). **Must be initialized by software after reset.** |

### 2.3 Status Register 1 (`ST1`) Bitfield Specification
Accessed via `LST #1` and `SST #1`:

| Bit(s) | Field | Reset | Description |
| :--- | :--- | :--- | :--- |
| `15–13` | `ARB` | `X` | **Auxiliary Register Buffer:** Automatically loaded with the *previous* `ARP` value whenever `ARP` is modified (`MAR`, `LAR`, indirect `NAR`, `LST #0`). Restoring `ST1` via `LST #1` copies `ARB` back into `ARP`. |
| `12` | `CNF` | `0` | **RAM Configuration:** `0` = DARAM `B0` mapped to Data Space (`0100h–02FFh`); `1` = DARAM `B0` mapped to Program Space (`FE00h–FFFFh`). |
| `11` | `TC` | `X` | **Test/Control Flag:** Set/cleared by `BIT`, `BITT`, `CMPR`, `APL`, `CPL`, `OPL`, `XPL`, and `NORM`. Tested by `BCND`/`CC`/`RETC`. |
| `10` | `SXM` | `1` | **Sign-Extension Mode:** `1` = sign-extend 16-bit operands entering ALU prescaler and `BSAR`/`SFR`; `0` = zero-extend (unsigned). |
| `9` | `C` | `1` | **Carry Bit:** Set on unsigned addition carry-out (`ACC > FFFFFFFFh`), cleared on subtraction borrow (`ACC < 0`). Also modified by shifts (`ROL`, `ROR`, `SFL`, `SFR`, `BSAR`, `BSFL`) and `SETC C` / `CLRC C`. |
| `8–7` | `11` | `11` | Reserved; always read as `1`. |
| `6` | `HM` | `1` | **Hold Mode:** `1` = CPU halts internal execution during external `HOLD`; `0` = CPU continues executing out of internal memory during `HOLD`. |
| `5` | `1` | `1` | Reserved; always reads as `1`. |
| `4` | `XF` | `1` | **External Flag:** Controls external `XF` output pin (`SETC XF` / `CLRC XF`). |
| `3–2` | `11` | `11` | Reserved; always read as `1`. |
| `1–0` | `PM` | `00` | **Product Shift Mode:** Controls `PREG` output shifter: `00` = no shift; `01` = left shift 1 bit (zero-filled LSB); `10` = left shift 4 bits (zero-filled LSBs); `11` = right shift 6 bits (always sign-extended regardless of `SXM`). |

### 2.4 Processor Mode Status Register (`PMST`) Bitfield Specification
Memory-mapped at Data Page 0 address `0007h`:

| Bit(s) | Field | Reset | Description |
| :--- | :--- | :--- | :--- |
| `15–11` | `IPTR` | `00000` | **Interrupt Vector Pointer:** Upper 5 bits of the 16-bit interrupt vector base address (`IPTR × 2048`). |
| `10–8` | `000` | `000` | Reserved; read as `0`. |
| `7` | `AVIS` | `0` | **Address Visibility:** `1` = internal program addresses driven onto external address bus. |
| `6` | `0` | `0` | Reserved; reads as `0`. |
| `5` | `OVLY` | `0` | **RAM Overlay:** `1` = maps on-chip SARAM into Local Data Space; `0` = SARAM unmapped from Data Space. |
| `4` | `RAM` | `0` | **Program RAM:** `1` = maps on-chip SARAM into Program Space; `0` = SARAM unmapped from Program Space. |
| `3` | `MP/MC` | Pin | **Microprocessor/Microcomputer:** `0` = on-chip ROM enabled in Program Space; `1` = on-chip ROM disabled. |
| `2` | `NDX` | `0` | **`'C2x` Index Compatibility:** `0` = writes to `AR0` also write `INDX` and `ARCR`; `1` = `'C5x` mode (`AR0`, `INDX`, `ARCR` are independent). |
| `1` | `TRM` | `0` | **`'C2x` TREG Compatibility:** `0` = writes to `TREG0` also load `TREG1` (`bits 3:0`) and `TREG2` (`bits 3:0`); `1` = `'C5x` mode (`TREG0/1/2` are independent). |
| `0` | `BRAF` | `0` | **Block Repeat Active Flag:** `1` = `RPTB` loop active; `0` = inactive. Automatically cleared when `BRCR` decrements past `0`. |

---

<a name="chapter-3"></a>
## Chapter 3: Addressing Modes & Pointer Arithmetic

### 3.1 Direct & Memory-Mapped Register Addressing
* **Standard Direct (`I = 0` in opcode bit 7):**
  $$\text{EA}_{16} = (\text{ST0.DP}[8:0] \ll 7) \mid \text{IR}[6:0]$$
* **Memory-Mapped Register Direct/Indirect (`LAMM`, `SAMM`, `LMMR`, `SMMR`):**
  Forces the upper 9 bits of the effective data address to `000h`, targeting `0000h–007Fh`:
  $$\text{EA}_{16} = 0000\text{h} \mid \text{BaseEA}[6:0]$$
  where $\text{BaseEA}$ is `IR[6:0]` if `I = 0`, or `AR[ARP]` if `I = 1`. (Note: When `I = 1`, `AR[ARP]` is still post-modified as a full 16-bit register).

### 3.2 Indirect Addressing & `ARP`/`ARB` Update Mechanics
When opcode bit `7` (`I`) is `1`, bits `6:0` of the instruction word decode as:
* `Bit 6`: `IDV` (Index/Modify enable)
* `Bit 5`: `INC` (Increment flag)
* `Bit 4`: `DEC` (Decrement flag)
* `Bit 3`: `N` (New `ARP` enable: `1` = load `IR[2:0]` into `ARP` after address generation)
* `Bits 2:0`: `NAR` (New Auxiliary Register pointer value `0–7`)

**Effective Address & Post-Modification Table:**

| `IDV:INC:DEC` | Syntax | Effective Address | Post-Modification to `AR[ARP]` |
| :--- | :--- | :--- | :--- |
| `000` | `*` | `AR[ARP]` | None |
| `001` | `*-` | `AR[ARP]` | `AR[ARP] = AR[ARP] - 1` |
| `010` | `*+` | `AR[ARP]` | `AR[ARP] = AR[ARP] + 1` |
| `011` | — | Reserved | Undefined |
| `100` | `*BR0-` | `AR[ARP]` | `AR[ARP] = AR[ARP] -_rc INDX` (Reverse-carry subtract) |
| `101` | `*0-` | `AR[ARP]` | `AR[ARP] = AR[ARP] - INDX` |
| `110` | `*0+` | `AR[ARP]` | `AR[ARP] = AR[ARP] + INDX` |
| `111` | `*BR0+` | `AR[ARP]` | `AR[ARP] = AR[ARP] +_rc INDX` (Reverse-carry add) |

**`ARP` / `ARB` Update Rule (executed at end of address generation):**
If `N == 1`:
1. `ST1.ARB = ST0.ARP`
2. `ST0.ARP = IR[2:0]`

*(Exception: In `LST #1`, `ST0.ARP` is overwritten with the newly loaded `ST1.ARB` value.)*

### 3.3 Bit-Reversed Addressing (`*BR0+`, `*BR0-`)
Used for radix-2 FFT bit-reversed indexing. `INDX` is typically initialized to half the FFT size ($N/2$, a power of 2).
* **`*BR0+` (Reverse-Carry Addition):** Propagates carry from MSB (`bit 15`) toward LSB (`bit 0`):
  ```c
  uint16_t bit_rev_add(uint16_t ar, uint16_t indx) {
      uint16_t mask = 0x8000;
      while (mask & indx) {
          ar ^= mask;
          mask >>= 1;
      }
      return ar ^ mask;
  }
  ```
* **`*BR0-` (Reverse-Carry Subtraction):** Propagates borrow from MSB (`bit 15`) toward LSB (`bit 0`):
  ```c
  uint16_t bit_rev_sub(uint16_t ar, uint16_t indx) {
      uint16_t mask = 0x8000;
      while (mask != 0) {
          if (indx & mask) {
              if (ar & mask) {
                  ar &= ~mask;
              } else {
                  ar |= mask;
                  // Borrow propagates to the right (toward bit 0)
                  uint16_t b = mask >> 1;
                  while (b != 0 && !(ar & b)) {
                      ar |= b;
                      b >>= 1;
                  }
                  if (b != 0) ar &= ~b;
              }
          }
          mask >>= 1;
      }
      return ar;
  }
  ```

### 3.4 Circular Buffer Addressing (`CBSR1/2`, `CBER1/2`, `CBCR`)
Two independent circular buffers (`1` and `2`) are controlled by `CBCR`:
* **Buffer 1:** Enabled if `CBCR.CENB1 == 1` (`bit 3`), bound to `AR[CBCR.CAR1]` (`bits 2:0`). Start = `CBSR1`, End = `CBER1`.
* **Buffer 2:** Enabled if `CBCR.CENB2 == 1` (`bit 7`), bound to `AR[CBCR.CAR2]` (`bits 6:4`). Start = `CBSR2`, End = `CBER2`.
* **Boundary Wrap Rule:** Whenever the bound `AR` is modified by an indirect addressing mode (`*+`, `*-`, `*0+`, `*0-`) or `MAR`:
  * After post-increment (`*+`, `*0+`): if `AR > CBER`, wrap to `AR = CBSR`.
  * After post-decrement (`*-`, `*0-`): if `AR < CBSR`, wrap to `AR = CBER`.
  * *(Note: Circular buffers are **not** triggered by `LAR` direct loads or `ARAU` operations like `ADRK`/`SBRK` unless using indirect addressing modes; exact equality/bound comparison occurs after the step is applied).*

### 3.5 Immediate & Dedicated Register Addressing
* **Short Immediate (8-bit or 9-bit):** Embedded directly in the 16-bit instruction word (`LACL #k`, `ADD #k`, `SUB #k`, `MPY #k`, `RPT #k`, `LDP #k`, `ADRK #k`, `SBRK #k`). Unsigned (zero-extended), except `MPY #k` (13-bit signed `-4096` to `+4095`).
* **Long Immediate (16-bit):** Stored in the second word (`PC + 1`) of 2-word instructions (`ADD #lk [, shift]`, `LACC #lk [, shift]`, `AND #lk [, shift]`, `RPT #lk`, `BLDD`, `BLPD`, etc.). Sign-extended if `ST1.SXM == 1` (for arithmetic/load) or zero-extended if `SXM == 0` or logical (`AND`, `OR`, `XOR`).
* **Dedicated Register:** `BMAR` provides the source/destination address for `BLDD`, `BLDP`, `BLPD`, `MADD`, `MADS`.

---

<a name="chapter-4"></a>
## Chapter 4: ALU, Multiplier, Shifters & Hardware Loops

### 4.1 Central ALU, Saturation (`OVM`), Carry (`C`) & Sign-Extension (`SXM`)
* **ALU Width:** 32-bit two's-complement arithmetic.
* **Input Prescaler (0–16 bit left shift):**
  * 16-bit memory/immediate operands enter a `0–16` bit left shifter before the ALU.
  * Lower `shift` bits are zero-filled.
  * Upper `16 - shift` bits are sign-extended from bit 15 if `ST1.SXM == 1`, or zero-filled if `ST1.SXM == 0`.
  * *Exception:* Logical instructions (`AND`, `OR`, `XOR`) always zero-extend the upper bits regardless of `SXM`.
* **Carry (`ST1.C`) Rules:**
  * **Addition (`ADD`, `ADDC`, `ADDS`, `ADDT`, `ADDK`, `ADCB`):** `C = 1` if unsigned 32-bit sum $> \text{FFFFFFFFh}$ (carry out of bit 31); otherwise `C = 0`. *(Exception: `ADD #k` 8-bit short immediate and `ADD mem, 16` affect `C` identically as 32-bit unsigned additions).*
  * **Subtraction (`SUB`, `SUBB`, `SUBC`, `SUBS`, `SUBT`, `SUBK`, `SBCB`):** `C = 0` if unsigned borrow occurs (minuend $<$ subtrahend); `C = 1` if no borrow (minuend $\ge$ subtrahend).
  * **Negation (`NEG`):** `C = 1` if `ACC == 0`, else `C = 0`.
  * **Absolute Value (`ABS`):** `C` is cleared to `0`.
* **Overflow (`ST0.OV`) & Saturation (`ST0.OVM`):**
  * Signed overflow occurs when two operands of the same sign produce a result of the opposite sign in bit 31.
  * If overflow occurs: `ST0.OV = 1` (sticky).
  * If `ST0.OVM == 1` on overflow: `ACC` is clamped to `007FFFFFFFh` (if positive overflow) or `FF80000000h` (if negative overflow).

### 4.2 Parallel Logic Unit (`PLU`) & `DBMR`
The PLU performs read-modify-write bitwise operations directly on data memory without disturbing `ACC` or `PREG`:
* **`APL` / `OPL` / `XPL`:** Reads `dma`, applies `AND` / `OR` / `XOR` with `DBMR` (or 16-bit immediate `#lk`), writes result back to `dma`. Sets `ST1.TC = 1` if the result is `0000h`, else `ST1.TC = 0`.
* **`CPL`:** Compares `dma` with `DBMR` (or `#lk`). Sets `ST1.TC = 1` if `dma == mask`, else `ST1.TC = 0` (does not write back to memory).

### 4.3 Hardware Multiplier & Product Shifter (`PM`)
* **Multiplier:** `16 × 16 -> 32-bit` single-cycle hardware multiplier.
  * Standard signed multiply (`MPY`, `MAC`, `MACD`, `MADS`, `MADD`, `MPYA`, `MPYS`, `SQRA`, `SQRS`): `PREG = (int32_t)(int16_t)TREG0 * (int32_t)(int16_t)Operand`.
  * Unsigned multiply (`MPYU`): `PREG = (uint32_t)(uint16_t)TREG0 * (uint32_t)(uint16_t)Operand`.
* **Product Shifter (`ST1.PM`):** Applied whenever `PREG` is transferred to the ALU (`PAC`, `APAC`, `SPAC`, `MPYA`, `MPYS`, `MAC`, `MACD`, `MADD`, `MADS`, `SQRA`, `SQRS`) or stored (`SPH`, `SPL`):
  * `PM = 00`: `PREG` unshifted.
  * `PM = 01`: `PREG << 1` (LSB zero-filled).
  * `PM = 10`: `PREG << 4` (4 LSBs zero-filled).
  * `PM = 11`: `(int32_t)PREG >> 6` (arithmetic right shift by 6, always sign-extended).

### 4.4 Scaling Shifter & Auxiliary Register Arithmetic Unit (`ARAU`)
* **Post-ALU Output Shifter (`SACH`, `SACL`):** Left-shifts `ACC` by `0–7` bits before storing the high word (`bits 31:16`) or low word (`bits 15:0`) to memory. Does not modify `ACC`.
* **Accumulator Shift Instructions:**
  * `SFL` / `SFR`: 1-bit left/right shift of `ACC`. `SFL` shifts bit 31 into `C` and `0` into bit 0. `SFR` shifts bit 0 into `C` and sign-extends bit 31 if `SXM == 1` (else `0`).
  * `BSFL` / `BSAR`: Barrel shift `ACC` left/right by `1–16` bits (`shift` encoded in opcode). `BSAR` sign-extends if `SXM == 1` (else `0`) and loads the last shifted-out bit into `C`.
  * `ROL` / `ROR`: 1-bit rotate of `ACC` through `C` (`33-bit` rotation).
* **`ARAU`:** 16-bit unsigned arithmetic unit dedicated to `AR0–AR7` updates (`MAR`, `ADRK`, `SBRK`, `CMPR`, `BANZ`). Does not affect `ST0.OV` or `ST1.C`.

### 4.5 Hardware Loop Mechanics (`RPT` / `RPTC` & `RPTB`)
* **Single-Instruction Repeat (`RPT #k`, `RPT #lk`, `RPT dma`):**
  1. Loads `RPTC` with the operand $N$ (`0–255` for `#k`, `0–65535` for `#lk`/`dma`).
  2. Executes the immediately following instruction **$N + 1$ times**.
  3. While `RPTC > 0`, `PC` does not advance, `RPTC` decrements each execution, and **all interrupts (including `NMI`) are masked/deferred** until the repeated instruction completes.
  4. Multi-word instructions (2-word instructions) **cannot** be repeated with `RPT`.
* **Zero-Overhead Block Repeat (`RPTB pma`):**
  1. Software pre-loads `BRCR` with loop count $N$ (executes block **$N + 1$ times**).
  2. `RPTB pma` sets `PASR = PC + 2` (address of first instruction in block), `PAER = pma` (address of **last** instruction in block), and `PMST.BRAF = 1`.
  3. Whenever `PC == PAER` and `PMST.BRAF == 1`:
     * If `BRCR > 0`: `BRCR` decrements by `1` and next `PC = PASR`.
     * If `BRCR == 0`: `PMST.BRAF` is cleared to `0` and `PC` advances normally (`PAER + 1`).
  4. `RPTB` is interruptible; nesting requires software save/restore of `BRCR`, `PASR`, `PAER`, and `PMST.BRAF`.

---

<a name="chapter-5"></a>
## Chapter 5: Pipeline Execution, Hazards, Branches & Interrupts

### 5.1 4-Stage Pipeline & Dual-Access Conflict Rules
* **Pipeline Stages:** `Fetch (F)` $\rightarrow$ `Decode (D)` $\rightarrow$ `Read (R)` $\rightarrow$ `Execute (E)`.
* **Data-Move Instructions (`DMOV`, `MACD`, `LTD`):** Copy data from `dma` to `dma + 1` in on-chip DARAM (`B0`, `B1`, `B2`) within the same cycle. *Rule:* `dma` and `dma + 1` must reside in the same DARAM block (or consecutive SARAM/external addresses with appropriate cycle penalties; `DMOV` only operates on on-chip DARAM/SARAM).
* **Latency Hazards:**
  * Modifying `AR[ARP]` via `LAR` or `MAR` requires 1 cycle before using that `AR` in indirect addressing if back-to-back? *Check:* In `'C5x`, `LAR` updates `AR` in the Execute stage while the following instruction's address generation occurs in the Decode/Read stage—therefore, **do not use a newly loaded `AR` via `LAR` in the immediately following instruction** unless separated by 1 instruction (or using `MAR`).
  * Similarly, `LDP` updates `ST0.DP` in Execute; if pipelined, ensure 1-cycle latency or verify pipeline interlocks (standard `'C5x` hardware interlocks `LDP` or requires 1 cycle depending on revision—emulating standard pipeline stage timing resolves this naturally).

### 5.2 Standard vs. Delayed Branches & Calls (`Z`-Suffix Instructions)
* **Standard Branches/Calls (`B`, `BCND`, `BANZ`, `CALL`, `CC`, `RET`, `RETC`):**
  * Flush the 2 prefetched instructions in the pipeline (`4 cycles` total when taken; `2 cycles` for conditional branches when **not** taken).
* **Delayed Branches/Calls (`BD`, `BCNDD`, `BANZD`, `CALAD`, `CALLD`, `CCD`, `RETD`, `RETCD`):**
  * Execute in **2 cycles** (when taken) by executing the **next two 1-word instructions** (or one 2-word instruction) located immediately after the delayed branch instruction before transferring control to the target address.
  * *Constraint:* Delayed branch delay slots must not contain `RPT`, another branch/call/return, or instructions modifying flags tested by `BCNDD`/`CCD`/`RETCD` before evaluation.
* **Condition Codes (`cond` field in `BCND`, `CC`, `RETC`, `XC`):**
  Supports compound testing of `ACC` (`EQ`, `NEQ`, `LT`, `LEQ`, `GT`, `GEQ`), `OV`/`NOV`, `C`/`NC`, `TC`/`NTC`, and `BIO`/`NBIO` (external `BIO` pin low/high). Multiple conditions in a single instruction are **ANDed** together (except `ACC` comparisons which are mutually exclusive).

### 5.3 Hardware Stack (`STACK`) Behavior
* **Depth:** 8 levels (`16-bit` words).
* **Push (`CALL`, `CC`, `CALA`, `TRAP`, `INTR`, Interrupts, `PUSH`, `PSHD`):**
  * Pushes `PC` (or `ACCL` for `PUSH`, `dma` for `PSHD`) onto Top-of-Stack (`TOS`); oldest entry at level 8 is overwritten on overflow.
* **Pop (`RET`, `RETC`, `RETE`, `RETI`, `POP`, `POPD`):**
  * Pops `TOS` into `PC` (or `ACCL` for `POP`, `dma` for `POPD`); bottom entry (level 8) is duplicated into level 7 on pop.

### 5.4 Interrupt Vector Table, Masking & Context Save/Restore
* **Vector Address Formula:**
  $$\text{VectorAddr}_{16} = (\text{PMST.IPTR}[4:0] \ll 11) \mid (\text{VectorNumber} \times 2)$$
  Each vector slot is **2 words wide** (typically containing a `B isr_addr` branch instruction).

| Vector # | Offset (`IPTR=0`) | Name | Description |
| :--- | :--- | :--- | :--- |
| `0` | `0000h` | `RS` | Hardware / Software Reset (Non-maskable) |
| `1` | `0002h` | `INT1` | External Interrupt 1 (`IMR`/`IFR` bit 0) |
| `2` | `0004h` | `INT2` | External Interrupt 2 (`IMR`/`IFR` bit 1) |
| `3` | `0006h` | `INT3` | External Interrupt 3 (`IMR`/`IFR` bit 2) |
| `4` | `0008h` | `TINT` | Internal Timer Interrupt (`IMR`/`IFR` bit 3) |
| `5` | `000Ah` | `RINT` | Serial Port Receive Interrupt (`IMR`/`IFR` bit 4) |
| `6` | `000Ch` | `XINT` | Serial Port Transmit Interrupt (`IMR`/`IFR` bit 5) |
| `7` | `000Eh` | `TRNT` | TDM / Buffered Serial Receive (`IMR`/`IFR` bit 6) |
| `8` | `0010h` | `TXNT` | TDM / Buffered Serial Transmit (`IMR`/`IFR` bit 7) |
| `9` | `0012h` | `INT4` | External Interrupt 4 (`IMR`/`IFR` bit 8) |
| `10–15` | `0014h–001Eh` | — | Reserved |
| `16` | `0020h` | `TRAP` | Software `TRAP` instruction (Non-maskable) |
| `17` | `0022h` | `NMI` | Non-Maskable Interrupt (`NMI` pin) |
| `18–31` | `0024h–003Eh` | `INTR 18–31` | Software `INTR k` vectors (`0–31` selectable) |

* **Interrupt Acknowledge Sequence:**
  1. When an unmasked interrupt is pending (`(IFR & IMR) != 0` and `ST0.INTM == 0`, or `NMI` asserted):
  2. Clears the corresponding bit in `IFR`.
  3. Sets `ST0.INTM = 1` (disables further maskable interrupts).
  4. Pushes return `PC` onto `STACK`.
  5. **Shadow Register Save (1-level deep):** Automatically saves `ACC`, `ACCB`, `PREG`, `ST0`, `ST1`, `PMST`, `ARCR`, `INDX`, `TREG0`, `TREG1`, `TREG2` into 1-level shadow registers.
  6. Jumps to `VectorAddr`.
* **Return from Interrupt:**
  * `RETI`: Pops `PC` from `STACK` and clears `ST0.INTM = 0` (does **not** restore shadow registers).
  * `RETE`: Pops `PC` from `STACK`, clears `ST0.INTM = 0`, **and restores all shadow registers** (`ACC`, `ACCB`, `PREG`, `ST0`, `ST1`, `PMST`, `ARCR`, `INDX`, `TREG0–2`).

### 5.5 Reset Sequence & Power-Down Modes
* **Hardware Reset (`RS`):** Forces `PC = 0000h`, `ST0.INTM = 1`, `ST0.OV = 0`, `ST1.CNF = 0`, `ST1.SXM = 1`, `ST1.C = 1`, `ST1.HM = 1`, `ST1.XF = 1`, `ST1.PM = 00`, `PMST = 0000h` (with `MP/MC` sampled from pin), `IFR = 0000h`, `GREG = 0000h`, `RPTC = 0000h`, `CBCR = 0000h`. Execution starts at `0000h` after 17 clock cycles.
* **`IDLE` / `IDLE2`:** Halts CPU execution and enters low-power state until an unmasked interrupt (or any enabled interrupt even if `INTM = 1` wakes `IDLE` and branches if `INTM = 0`, or resumes at `PC + 1` if `INTM = 1`) or `RS` occurs.

---

<a name="chapter-6"></a>
## Chapter 6: Complete Instruction Set & Opcode Encoding Reference

### 6.1 Instruction Syntax & Operand Notation Key
* `dma`: Data memory address operand. Opcode bit `7` (`I`) = `0` for direct (`IR[6:0]`), `1` for indirect (`IR[6:0]` = `IDV:INC:DEC:N:NAR`).
* `pma`: 16-bit Program Memory Address (stored in second instruction word `PC + 1`).
* `pa`: 16-bit I/O Port Address (stored in second instruction word `PC + 1`).
* `#k`: Short immediate constant (`8-bit` `00h–FFh`, `9-bit` `000h–1FFh` for `LDP`, or `13-bit` signed for `MPY #k`).
* `#lk`: 16-bit Long Immediate constant (stored in second instruction word `PC + 1`).
* `shift`: 4-bit shift count `0–15` (`IR[11:8]`), or `0–7` (`IR[10:8]`) for `SACH`/`SACL`, or `1–16` (`IR[3:0] + 1`) for `BSAR`/`BSFL`.
* `ARx`: Auxiliary Register `0–7` (`IR[10:8]` or `IR[2:0]`).
* `W / C`: Words / Cycles (assuming zero-wait-state memory and non-conflicting buses).

---

### 6.2 Accumulator, Arithmetic & Logic Instructions

| Mnemonic & Operands | 16-Bit Opcode (`MSB -> LSB`) | W / C | Operation Summary |
| :--- | :--- | :--- | :--- |
| `ABS` | `1011 1110 0000 0000` | `1 / 1` | `ACC = |ACC|`; `C = 0`; updates `OV` if `ACC == 80000000h`. |
| `ADCB` | `1011 1110 0001 0001` | `1 / 1` | `ACC = ACC + ACCB + C` |
| `ADD dma [, shift]` | `0010 ssss Iaaa aaaa` | `1 / 1` | `ACC = ACC + (mem(dma) << shift)` |
| `ADD dma, 16` | `0110 0001 Iaaa aaaa` | `1 / 1` | `ACC = ACC + (mem(dma) << 16)` |
| `ADD #k` | `1011 1000 kkkk kkkk` | `1 / 1` | `ACC = ACC + k` (`0 <= k <= 255`, unsigned) |
| `ADD #lk [, shift]` | `1011 1111 1001 ssss` + `#lk` | `2 / 2` | `ACC = ACC + (lk << shift)` |
| `ADDC dma` | `0110 0000 Iaaa aaaa` | `1 / 1` | `ACC = ACC + mem(dma) + C` (zero-extended) |
| `ADDS dma` | `0110 0010 Iaaa aaaa` | `1 / 1` | `ACC = ACC + mem(dma)` (zero-extended, ignores `SXM`) |
| `ADDT dma` | `0110 0011 Iaaa aaaa` | `1 / 1` | `ACC = ACC + (mem(dma) << TREG1[3:0])` |
| `AND dma` | `0110 1110 Iaaa aaaa` | `1 / 1` | `ACCL = ACCL & mem(dma)`; `ACCH = 0` |
| `AND #lk [, shift]` | `1011 1111 1011 ssss` + `#lk` | `2 / 2` | `ACC = ACC & (lk << shift)` (zero-extended) |
| `AND #lk, 16` | `1011 1110 1000 0001` + `#lk` | `2 / 2` | `ACC = ACC & (lk << 16)` |
| `ANDB` | `1011 1110 0001 1001` | `1 / 1` | `ACC = ACC & ACCB` |
| `BSAR shift` | `1011 1110 1110 ssss` | `1 / 1` | `ACC = ACC >> (ssss + 1)` (`SXM` controls sign-ext) |
| `BSFL shift` | `1011 1110 1111 ssss` | `1 / 1` | `ACC = ACC << (ssss + 1)` (zero-filled) |
| `CMPL` | `1011 1110 0000 0001` | `1 / 1` | `ACC = ~ACC` (1's complement) |
| `CRGT` | `1011 1110 0001 1011` | `1 / 1` | If `ACC > ACCB`, `ACCB = ACC` & `C = 1`; else `ACC = ACCB` & `C = 0` |
| `CRLT` | `1011 1110 0001 1100` | `1 / 1` | If `ACC < ACCB`, `ACCB = ACC` & `C = 1`; else `ACC = ACCB` & `C = 0` |
| `EXAR` | `1011 1110 0001 1101` | `1 / 1` | Swap `ACC` and `ACCB` |
| `LACB` | `1011 1110 0001 1111` | `1 / 1` | `ACC = ACCB` |
| `LACC dma [, shift]` | `0001 ssss Iaaa aaaa` | `1 / 1` | `ACC = mem(dma) << shift` |
| `LACC dma, 16` | `0110 1010 Iaaa aaaa` | `1 / 1` | `ACC = mem(dma) << 16` |
| `LACC #lk [, shift]` | `1011 1111 1000 ssss` + `#lk` | `2 / 2` | `ACC = lk << shift` |
| `LACL dma` | `0110 1001 Iaaa aaaa` | `1 / 1` | `ACCL = mem(dma)`; `ACCH = 0` |
| `LACL #k` | `1011 1001 kkkk kkkk` | `1 / 1` | `ACCL = k` (`0–255`); `ACCH = 0` |
| `LACT dma` | `0110 1011 Iaaa aaaa` | `1 / 1` | `ACC = mem(dma) << TREG1[3:0]` |
| `NEG` | `1011 1110 0000 0010` | `1 / 1` | `ACC = -ACC` (2's complement) |
| `NORM` | `1010 0000 Iaaa aaaa` | `1 / 1` | If `bit 31 != bit 30`: `TC = 1`; else `ACC <<= 1`, `TC = 0`, modifies `AR[ARP]` |
| `OR dma` | `0110 1101 Iaaa aaaa` | `1 / 1` | `ACCL = ACCL | mem(dma)` (`ACCH` unchanged) |
| `OR #lk [, shift]` | `1011 1111 1100 ssss` + `#lk` | `2 / 2` | `ACC = ACC | (lk << shift)` |
| `OR #lk, 16` | `1011 1110 1000 0010` + `#lk` | `2 / 2` | `ACC = ACC | (lk << 16)` |
| `ORB` | `1011 1110 0001 1010` | `1 / 1` | `ACC = ACC | ACCB` |
| `ROL` | `1011 1110 0000 1100` | `1 / 1` | Rotate `ACC` left 1 bit through `C` |
| `ROR` | `1011 1110 0000 1101` | `1 / 1` | Rotate `ACC` right 1 bit through `C` |
| `SACB` | `1011 1110 0001 1110` | `1 / 1` | `ACCB = ACC` |
| `SACH dma [, shift]` | `1001 1sss Iaaa aaaa` | `1 / 1` | `mem(dma) = (ACC << shift)[31:16]` (`0 <= shift <= 7`) |
| `SACL dma [, shift]` | `1001 0sss Iaaa aaaa` | `1 / 1` | `mem(dma) = (ACC << shift)[15:0]` (`0 <= shift <= 7`) |
| `SATH` | `1011 1110 0101 1010` | `1 / 1` | `ACC = (int32_t)ACC >> (TREG1[4] ? 16 : 0)` |
| `SATL` | `1011 1110 0101 1011` | `1 / 1` | `ACC = (int32_t)ACC >> TREG1[3:0]` |
| `SBCB` | `1011 1110 0001 0010` | `1 / 1` | `ACC = ACC - ACCB - ~C` |
| `SFL` | `1011 1110 0000 1001` | `1 / 1` | `C = ACC[31]`; `ACC = ACC << 1` |
| `SFR` | `1011 1110 0000 1010` | `1 / 1` | `C = ACC[0]`; `ACC = ACC >> 1` (`SXM` sign-ext) |
| `SUB dma [, shift]` | `0011 ssss Iaaa aaaa` | `1 / 1` | `ACC = ACC - (mem(dma) << shift)` |
| `SUB dma, 16` | `0110 0101 Iaaa aaaa` | `1 / 1` | `ACC = ACC - (mem(dma) << 16)` |
| `SUB #k` | `1011 1010 kkkk kkkk` | `1 / 1` | `ACC = ACC - k` (`0 <= k <= 255`, unsigned) |
| `SUB #lk [, shift]` | `1011 1111 1010 ssss` + `#lk` | `2 / 2` | `ACC = ACC - (lk << shift)` |
| `SUBB dma` | `0110 0100 Iaaa aaaa` | `1 / 1` | `ACC = ACC - mem(dma) - ~C` (zero-extended) |
| `SUBC dma` | `0000 1010 Iaaa aaaa` | `1 / 1` | Conditional subtract step for 16-bit division |
| `SUBS dma` | `0110 0110 Iaaa aaaa` | `1 / 1` | `ACC = ACC - mem(dma)` (zero-extended, ignores `SXM`) |
| `SUBT dma` | `0110 0111 Iaaa aaaa` | `1 / 1` | `ACC = ACC - (mem(dma) << TREG1[3:0])` |
| `XOR dma` | `0110 1100 Iaaa aaaa` | `1 / 1` | `ACCL = ACCL ^ mem(dma)` (`ACCH` unchanged) |
| `XOR #lk [, shift]` | `1011 1111 1101 ssss` + `#lk` | `2 / 2` | `ACC = ACC ^ (lk << shift)` |
| `XOR #lk, 16` | `1011 1110 1000 0011` + `#lk` | `2 / 2` | `ACC = ACC ^ (lk << 16)` |
| `XORB` | `1011 1110 0001 0011` | `1 / 1` | `ACC = ACC ^ ACCB` |
| `ZALR dma` | `0110 1000 Iaaa aaaa` | `1 / 1` | `ACC = (mem(dma) << 16) + 00008000h` (load & round) |
| `ZAP` | `1011 1110 0101 1001` | `1 / 1` | `ACC = 0`; `PREG = 0` |

---

### 6.3 Multiply & Multiply-Accumulate Instructions

| Mnemonic & Operands | 16-Bit Opcode (`MSB -> LSB`) | W / C | Operation Summary |
| :--- | :--- | :--- | :--- |
| `APAC` | `1011 1110 0000 0100` | `1 / 1` | `ACC = ACC + shift_PM(PREG)` |
| `LT dma` | `0111 0011 Iaaa aaaa` | `1 / 1` | `TREG0 = mem(dma)` (also `TREG1`/`TREG2` if `PMST.TRM == 0`) |
| `LTA dma` | `0111 0000 Iaaa aaaa` | `1 / 1` | `TREG0 = mem(dma)`; `ACC = ACC + shift_PM(PREG)` |
| `LTD dma` | `0111 0010 Iaaa aaaa` | `1 / 1` | `TREG0 = mem(dma)`; `ACC += shift_PM(PREG)`; `mem(dma+1) = mem(dma)` |
| `LTP dma` | `0111 0001 Iaaa aaaa` | `1 / 1` | `TREG0 = mem(dma)`; `ACC = shift_PM(PREG)` |
| `LTS dma` | `0111 0100 Iaaa aaaa` | `1 / 1` | `TREG0 = mem(dma)`; `ACC = ACC - shift_PM(PREG)` |
| `MAC pma, dma` | `1010 0010 Iaaa aaaa` + `pma` | `2 / 3` | `ACC += shift_PM(PREG)`; `TREG0 = mem(dma)`; `PREG = TREG0 * pmem(pma)` (`1` cycle when repeated) |
| `MACD pma, dma` | `1010 0011 Iaaa aaaa` + `pma` | `2 / 3` | Same as `MAC`, plus `mem(dma+1) = mem(dma)` (`1` cycle when repeated) |
| `MADD dma` | `1010 1011 Iaaa aaaa` | `1 / 3` | `ACC += shift_PM(PREG)`; `TREG0 = mem(dma)`; `PREG = TREG0 * pmem(BMAR++)`; `mem(dma+1) = mem(dma)` |
| `MADS dma` | `1010 1010 Iaaa aaaa` | `1 / 3` | Same as `MADD` without `mem(dma+1) = mem(dma)` shift |
| `MPY dma` | `0101 0100 Iaaa aaaa` | `1 / 1` | `PREG = (int16)TREG0 * (int16)mem(dma)` |
| `MPY #k` | `110k kkkk kkkk kkkk` | `1 / 1` | `PREG = (int16)TREG0 * (int13)k` (`-4096 <= k <= 4095`) |
| `MPYA dma` | `0101 0000 Iaaa aaaa` | `1 / 1` | `ACC += shift_PM(PREG)`; `PREG = (int16)TREG0 * (int16)mem(dma)` |
| `MPYS dma` | `0101 0001 Iaaa aaaa` | `1 / 1` | `ACC -= shift_PM(PREG)`; `PREG = (int16)TREG0 * (int16)mem(dma)` |
| `MPYU dma` | `0101 0101 Iaaa aaaa` | `1 / 1` | `PREG = (uint16)TREG0 * (uint16)mem(dma)` (unsigned) |
| `PAC` | `1011 1110 0000 0011` | `1 / 1` | `ACC = shift_PM(PREG)` |
| `SPAC` | `1011 1110 0000 0101` | `1 / 1` | `ACC = ACC - shift_PM(PREG)` |
| `SPH dma` | `1000 1101 Iaaa aaaa` | `1 / 1` | `mem(dma) = shift_PM(PREG)[31:16]` |
| `SPL dma` | `1000 1100 Iaaa aaaa` | `1 / 1` | `mem(dma) = shift_PM(PREG)[15:0]` |
| `SQRA dma` | `0101 0010 Iaaa aaaa` | `1 / 1` | `ACC += shift_PM(PREG)`; `TREG0 = mem(dma)`; `PREG = TREG0 * TREG0` |
| `SQRS dma` | `0101 0011 Iaaa aaaa` | `1 / 1` | `ACC -= shift_PM(PREG)`; `TREG0 = mem(dma)`; `PREG = TREG0 * TREG0` |

---

### 6.4 Auxiliary Register & Data Page Instructions

| Mnemonic & Operands | 16-Bit Opcode (`MSB -> LSB`) | W / C | Operation Summary |
| :--- | :--- | :--- | :--- |
| `ADRK #k` | `0111 1000 kkkk kkkk` | `1 / 1` | `AR[ARP] = AR[ARP] + k` (`0 <= k <= 255`) |
| `CMPR cond` | `1011 1111 0100 01cc` | `1 / 1` | Compare `AR[ARP]` to `ARCR`: `cc=00` (`==`), `01` (`<`), `10` (`>`), `11` (`!=`) -> sets `ST1.TC` |
| `LAR ARx, dma` | `0000 0xxx Iaaa aaaa` | `1 / 1` | `ARx = mem(dma)` |
| `LAR ARx, #k` | `1011 0xxx kkkk kkkk` | `1 / 1` | `ARx = k` (`0 <= k <= 255`, zero-extended) |
| `LAR ARx, #lk` | `1011 1111 0000 1xxx` + `#lk` | `2 / 2` | `ARx = lk` |
| `LDP dma` | `0000 1101 Iaaa aaaa` | `1 / 1` | `ST0.DP = mem(dma)[8:0]` |
| `LDP #k` | `1011 110k kkkk kkkk` | `1 / 1` | `ST0.DP = k` (`9-bit`, `0 <= k <= 511`) |
| `MAR dma` | `1000 1011 Iaaa aaaa` | `1 / 1` | Modify `AR[ARP]` and/or `ARP` per `dma` field (no memory access) |
| `SAR ARx, dma` | `1000 0xxx Iaaa aaaa` | `1 / 1` | `mem(dma) = ARx` |
| `SBRK #k` | `0111 1100 kkkk kkkk` | `1 / 1` | `AR[ARP] = AR[ARP] - k` (`0 <= k <= 255`) |

---

### 6.5 Parallel Logic Unit (`PLU`) Instructions

| Mnemonic & Operands | 16-Bit Opcode (`MSB -> LSB`) | W / C | Operation Summary |
| :--- | :--- | :--- | :--- |
| `APL dma` | `0101 1010 Iaaa aaaa` | `1 / 1` | `mem(dma) &= DBMR`; `TC = (result == 0)` |
| `APL #lk, dma` | `0101 1110 Iaaa aaaa` + `#lk` | `2 / 2` | `mem(dma) &= lk`; `TC = (result == 0)` |
| `CPL dma` | `0101 1011 Iaaa aaaa` | `1 / 1` | `TC = (mem(dma) == DBMR)` |
| `CPL #lk, dma` | `0101 1111 Iaaa aaaa` + `#lk` | `2 / 2` | `TC = (mem(dma) == lk)` |
| `OPL dma` | `0101 1001 Iaaa aaaa` | `1 / 1` | `mem(dma) |= DBMR`; `TC = (result == 0)` |
| `OPL #lk, dma` | `0101 1101 Iaaa aaaa` + `#lk` | `2 / 2` | `mem(dma) |= lk`; `TC = (result == 0)` |
| `SPLK #lk, dma` | `1010 1110 Iaaa aaaa` + `#lk` | `2 / 2` | `mem(dma) = lk` (direct store of immediate to memory) |
| `XPL dma` | `0101 1000 Iaaa aaaa` | `1 / 1` | `mem(dma) ^= DBMR`; `TC = (result == 0)` |
| `XPL #lk, dma` | `0101 1100 Iaaa aaaa` + `#lk` | `2 / 2` | `mem(dma) ^= lk`; `TC = (result == 0)` |

---

### 6.6 Load, Store & Block Move Instructions

| Mnemonic & Operands | 16-Bit Opcode (`MSB -> LSB`) | W / C | Operation Summary |
| :--- | :--- | :--- | :--- |
| `BIT dma, bit_code` | `0100 bbbb Iaaa aaaa` | `1 / 1` | `ST1.TC = mem(dma)[15 - bbbb]` (`bbbb=0` tests MSB bit 15; `bbbb=15` tests LSB bit 0) |
| `BITT dma` | `0110 1111 Iaaa aaaa` | `1 / 1` | `ST1.TC = mem(dma)[15 - TREG2[3:0]]` |
| `BLDD BMAR, dma` | `1010 1100 Iaaa aaaa` | `1 / 3` | `mem(dma) = mem(BMAR++)` (`1` cycle when repeated with `RPT`) |
| `BLDD dma, BMAR` | `1010 1101 Iaaa aaaa` | `1 / 3` | `mem(BMAR++) = mem(dma)` (`1` cycle when repeated with `RPT`) |
| `BLDD #lk, dma` | `1010 1000 Iaaa aaaa` + `#lk` | `2 / 3` | `mem(dma) = mem(lk++)` (`1` cycle when repeated with `RPT`) |
| `BLDD dma, #lk` | `1010 1001 Iaaa aaaa` + `#lk` | `2 / 3` | `mem(lk++) = mem(dma)` (`1` cycle when repeated with `RPT`) |
| `BLDP dma` | `0101 0111 Iaaa aaaa` | `1 / 3` | `pmem(BMAR++) = mem(dma)` (`1` cycle when repeated with `RPT`) |
| `BLPD BMAR, dma` | `1010 0100 Iaaa aaaa` | `1 / 3` | `mem(dma) = pmem(BMAR++)` (`1` cycle when repeated with `RPT`) |
| `BLPD #pma, dma` | `1010 0101 Iaaa aaaa` + `pma` | `2 / 3` | `mem(dma) = pmem(pma++)` (`1` cycle when repeated with `RPT`) |
| `DMOV dma` | `0111 0111 Iaaa aaaa` | `1 / 1` | `mem(dma + 1) = mem(dma)` (DARAM/SARAM data shift) |
| `LAMM dma` | `0000 1000 Iaaa aaaa` | `1 / 1` | `ACCL = mem(0000h | dma[6:0])`; `ACCH = 0` |
| `LMMR dma, #lk` | `1010 0111 Iaaa aaaa` + `#lk` | `2 / 2` | `mem(0000h | dma[6:0]) = mem(lk)` |
| `LST #0, dma` | `0000 1110 Iaaa aaaa` | `1 / 1` | `ST0 = mem(dma)` |
| `LST #1, dma` | `0000 1111 Iaaa aaaa` | `1 / 1` | `ST1 = mem(dma)` (also copies `ST1.ARB` into `ST0.ARP`) |
| `POP` | `1011 1110 0011 0010` | `1 / 1` | `ACCL = pop(STACK)`; `ACCH = 0` |
| `POPD dma` | `1000 1010 Iaaa aaaa` | `1 / 1` | `mem(dma) = pop(STACK)` |
| `PSHD dma` | `0111 0110 Iaaa aaaa` | `1 / 1` | `push(STACK, mem(dma))` |
| `PUSH` | `1011 1110 0011 1100` | `1 / 1` | `push(STACK, ACCL)` |
| `SAMM dma` | `1000 1000 Iaaa aaaa` | `1 / 1` | `mem(0000h | dma[6:0]) = ACCL` |
| `SMMR dma, #lk` | `1010 0110 Iaaa aaaa` + `#lk` | `2 / 2` | `mem(lk) = mem(0000h | dma[6:0])` |
| `SST #0, dma` | `1000 1110 Iaaa aaaa` | `1 / 1` | `mem(dma) = ST0` |
| `SST #1, dma` | `1000 1111 Iaaa aaaa` | `1 / 1` | `mem(dma) = ST1` |
| `TBLR dma` | `1010 0001 Iaaa aaaa` | `1 / 3` | `mem(dma) = pmem(ACCL)` (`1` cycle when repeated with `RPT`) |
| `TBLW dma` | `1010 1111 Iaaa aaaa` | `1 / 3` | `pmem(ACCL) = mem(dma)` (`1` cycle when repeated with `RPT`) |

---

### 6.7 Branch, Call, Return, Repeat & Control Instructions

| Mnemonic & Operands | 16-Bit Opcode (`MSB -> LSB`) | W / C | Operation Summary |
| :--- | :--- | :--- | :--- |
| `B pma [, dma]` | `0111 1001 Iaaa aaaa` + `pma` | `2 / 4` | Unconditional branch to `pma` (optional `dma` modifies `AR`/`ARP`) |
| `BD pma [, dma]` | `0111 1101 Iaaa aaaa` + `pma` | `2 / 2` | Delayed unconditional branch to `pma` (executes next 2 words) |
| `BACC` | `1011 1110 0010 0000` | `1 / 4` | Branch to address in `ACCL` |
| `BACCD` | `1011 1110 0010 0001` | `1 / 2` | Delayed branch to address in `ACCL` |
| `BANZ pma [, dma]` | `0111 1011 Iaaa aaaa` + `pma` | `2 / 4(2)`| If `AR[ARP] != 0`: branch to `pma` (`4` cycles); else continue (`2` cycles); post-modifies `AR[ARP]` |
| `BANZD pma [, dma]`| `0111 1111 Iaaa aaaa` + `pma` | `2 / 2` | Delayed `BANZ` (`2` cycles taken or not taken) |
| `BCND pma, cond` | `1110 00cc cccc cccc` + `pma` | `2 / 4(2)`| Conditional branch (`4` cycles taken, `2` not taken) |
| `BCNDD pma, cond`| `1111 00cc cccc cccc` + `pma` | `2 / 2` | Delayed conditional branch (`2` cycles taken or not taken) |
| `CALA` | `1011 1110 0011 0000` | `1 / 4` | `push(STACK, PC + 1)`; `PC = ACCL` |
| `CALAD` | `1011 1110 0011 1101` | `1 / 2` | Delayed `CALA`: `push(STACK, PC + 3)`; `PC = ACCL` |
| `CALL pma [, dma]` | `0111 1010 Iaaa aaaa` + `pma` | `2 / 4` | `push(STACK, PC + 2)`; `PC = pma` |
| `CALLD pma [, dma]`| `0111 1110 Iaaa aaaa` + `pma` | `2 / 2` | Delayed `CALL`: `push(STACK, PC + 4)`; `PC = pma` |
| `CC pma, cond` | `1110 10cc cccc cccc` + `pma` | `2 / 4(2)`| Conditional call (`4` cycles taken, `2` not taken) |
| `CCD pma, cond` | `1111 10cc cccc cccc` + `pma` | `2 / 2` | Delayed conditional call |
| `CLRC flag` | `1011 1110 0100 fff0` | `1 / 1` | Clear control bit: `fff=000` (`INTM`), `001` (`OVM`), `010` (`CNF`), `011` (`SXM`), `100` (`HM`), `101` (`TC`), `110` (`XF`), `111` (`C`) |
| `INTR k` | `1011 1110 011k kkkk` | `1 / 4` | Software interrupt vector `k` (`0–31`); sets `INTM = 1`, pushes `PC + 1` |
| `NOP` | `1000 1011 0000 0000` | `1 / 1` | No operation (alias of `MAR *`) |
| `RET` | `1110 1111 0000 0000` | `1 / 4` | `PC = pop(STACK)` |
| `RETD` | `1111 1111 0000 0000` | `1 / 2` | Delayed return: executes next 2 words, then `PC = pop(STACK)` |
| `RETC cond` | `1110 11cc cccc cccc` | `1 / 4(2)`| Conditional return (`4` cycles taken, `2` not taken) |
| `RETCD cond` | `1111 11cc cccc cccc` | `1 / 2` | Delayed conditional return |
| `RETE` | `1011 1110 0011 1010` | `1 / 4` | Return from interrupt: `PC = pop(STACK)`, `INTM = 0`, restores shadow registers |
| `RETI` | `1011 1110 0011 1000` | `1 / 4` | Return from interrupt: `PC = pop(STACK)`, `INTM = 0` (no shadow restore) |
| `RPT dma` | `0000 1011 Iaaa aaaa` | `1 / 1` | `RPTC = mem(dma)`; repeat next instruction `RPTC + 1` times |
| `RPT #k` | `1011 1011 kkkk kkkk` | `1 / 1` | `RPTC = k` (`0–255`); repeat next instruction `k + 1` times |
| `RPT #lk` | `1011 1111 1110 0000` + `#lk` | `2 / 2` | `RPTC = lk` (`0–65535`); repeat next instruction `lk + 1` times |
| `RPTB pma` | `1011 1111 1110 0010` + `pma` | `2 / 2` | `PASR = PC + 2`; `PAER = pma`; `PMST.BRAF = 1`; repeat block `BRCR + 1` times |
| `RPTZ #lk` | `1011 1111 1110 0001` + `#lk` | `2 / 2` | `ACC = 0`; `PREG = 0`; `RPTC = lk`; repeat next instruction `lk + 1` times |
| `SETC flag` | `1011 1110 0100 fff1` | `1 / 1` | Set control bit (`fff` encoding identical to `CLRC`) |
| `TRAP` | `1011 1110 0101 0001` | `1 / 4` | Software trap to vector `16` (`IPTR + 0020h`); pushes `PC + 1` |
| `XC n, cond` | `1110 01cc cccc cccc` (n=1)<br>`1111 01cc cccc cccc` (n=2) | `1 / 1` | Execute conditionally: if `cond` true, execute next `n` (`1` or `2`) words; else skip them as `NOP`s |

---

### 6.8 I/O & System Control Instructions

| Mnemonic & Operands | 16-Bit Opcode (`MSB -> LSB`) | W / C | Operation Summary |
| :--- | :--- | :--- | :--- |
| `IDLE` | `1011 1110 0010 0010` | `1 / 1` | Enter low-power idle mode until unmasked interrupt or `RS` |
| `IDLE2` | `1011 1110 0010 0011` | `1 / 1` | Enter deep power-down mode (clocks stopped) until external interrupt or `RS` |
| `IN dma, pa` | `1010 1111 Iaaa aaaa` + `pa` | `2 / 2` | `mem(dma) = io_port(pa)` |
| `OUT dma, pa` | `0000 1100 Iaaa aaaa` + `pa` | `2 / 2` | `io_port(pa) = mem(dma)` |

*(Note: Opcode bit patterns marked with `Iaaa aaaa` encode direct/indirect addressing in bits `7:0`; `cccc cccc cc` encodes the 10-bit `cond` mask for `BCND`/`CC`/`RETC`/`XC`.)*