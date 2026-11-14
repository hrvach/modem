# TMS320C5x On-Chip Peripherals — Chapter 9, §9.1–§9.6

**Source (only authority):** SPRU056D, *TMS320C5x User's Guide*, June 1998, file
`~/workspace/user/files/spru056d.pdf`. Chapter 9 = PDF pp. 510–531 (printed 9-1–9-22).
**§9.7 (Serial Port Interface) starts PDF p. 532 (printed 9-23) — NOT covered here.**
Extraction: `pdftotext -layout`; Tables 9-2, 9-3, 9-7 and §9.1.3 item 5 / §9.4.4 text
additionally verified against rendered page images (PDF pp. 515, 516, 517, 520, 524, 528).

**Citation convention:** every claim carries manual § + table/figure + PDF p. / printed p.
(e.g. `§9.3.1, Table 9–4, PDF p.519 / printed 9-10`).
`[UNVERIFIED — …]` = extraction garbled/illegible, not guessed.
`INFERENCE` = derived, kept out of tables.
Device applicability: `’C51` = TMS320C51. "Family-generic" = manual states it for ’C5x
without device qualification. Where the manual names a device subset, the subset is stated.

---

## 9.1 Peripheral Control — §9.1, PDF pp. 511–515 / printed 9-2–9-6

Peripherals are operated via memory-mapped control/data registers; serial ports and timer
sync to the CPU via interrupts or interrupt polling; setting/clearing bits enables, disables,
initialises and reconfigures peripherals; data moves through memory-mapped data registers.
When a peripheral is not in use its internal clocks can be shut off (lower power in normal
run or idle mode). §9.1, PDF p.511 / printed 9-2.

### 9.1.1 Memory-mapped peripheral registers and I/O ports — §9.1.1, Table 9–1, PDF pp. 511–513 / printed 9-2–9-4

- 28 processor registers, 17 peripheral registers, 16 I/O ports mapped into data memory
  space. §9.1.1, PDF p.511 / printed 9-2. (See Contradiction C1: Table 9–1 enumerates
  only 16 peripheral-register addresses.)
- **All writes to memory-mapped peripheral registers (but NOT processor registers or
  memory-mapped I/O ports) require one additional CLKOUT1 cycle.**
  §9.1.1, PDF p.511 / printed 9-2.

#### Table 9–1. Data page 0 address map — peripheral registers and I/O ports (§9.1.1, PDF pp. 511–513 / printed 9-2–9-4)

| Dec addr | Hex addr | Name | Description |
|---|---|---|---|
| 0–3 | 00–03 | — | Reserved |
| 4–31 | 04–1F | — | Memory-mapped processor registers (§8.3.2) |
| 32 | 20 | DRR | Data receive register (serial port) |
| 33 | 21 | DXR | Data transmit register (serial port) |
| 34 | 22 | SPC | Serial port control register |
| 35 | 23 | — | Reserved |
| 36 | 24 | TIM | Timer counter register |
| 37 | 25 | PRD | Timer period register |
| 38 | 26 | TCR | Timer control register |
| 39 | 27 | — | Reserved |
| 40 | 28 | PDWSR | Program/data wait-state register |
| 41 | 29 | IOWSR | I/O port wait-state register |
| 42 | 2A | CWSR | Wait-state control register |
| 43–47 | 2B–2F | — | Reserved for test/emulation |
| 48 | 30 | TRCV / BDRR | TDM data receive register / BSP data receive register |
| 49 | 31 | TDXR / BDXR | TDM data transmit register / BSP data transmit register |
| 50 | 32 | TSPC / BSPC | TDM serial port control register / BSP control register |
| 51 | 33 | TCSR / SPCE | TDM channel select register / BSP control extension register |
| 52 | 34 | TRTA / AXR | TDM receive/transmit address register / BSP address transmit register |
| 53 | 35 | TRAD / BKX | TDM receive address register / BSP transmit buffer size register |
| 54 | 36 | ARR | BSP address receive register |
| 55 | 37 | BKR | BSP receive buffer size register |
| 56–79 | 38–4F | — | Reserved |
| 80–95 | 50–5F | PA0–PA15 | I/O ports 50h–5Fh (PA0 = 50h, PA15 = 5Fh) |
| 96–127 | 60–7F | — | Scratch-pad RAM (DARAM B2) |

Notes: addresses 48–55 are shared TDM/BSP addresses — the name depends on which
serial port the device implements. §9.1.1, Table 9–1, PDF pp. 512–513 / printed 9-3–9-4.
HPI registers do not appear in Table 9–1 (HPI is covered in §9.10, out of range).

### 9.1.2 External interrupts — §9.1.2, Figure 9–1, PDF pp. 513–514 / printed 9-4–9-5

- Four external maskable user interrupts INT4–INT1 + one external nonmaskable interrupt
  (NMI). Internal interrupts: timer (TINT); serial port (RINT, XINT, TRNT, TXNT, BRNT,
  BXNT); host port (HINT); software interrupt instructions (TRAP, NMI, INTR).
  §9.1.2, PDF p.513 / printed 9-4.
- Priority: reset (RS) highest, INT4 lowest; NMI second highest. Interrupt operation detail
  is in §4.8 (PDF p. not in range). §9.1.2, PDF p.513 / printed 9-4.
- INTn synchronised to the core via a **five flip-flop synchronizer** (Figure 9–1).
  If a **1-1-0-0-0 sequence on five consecutive CLKOUT1 cycles** is detected, a 1 is
  loaded into the interrupt flag register (IFR). §9.1.2, PDF p.513 / printed 9-4.
- Sampling rules (§9.1.2, PDF p.514 / printed 9-5):
  - Pins sampled multiple times to avoid noise-generated interrupts.
  - To detect an active interrupt: signal sampled **low on at least three consecutive
    machine cycles**.
  - To detect another interrupt afterwards: signal sampled **high on at least two
    consecutive machine cycles**.
  - Pins sampled on the **rising edge of CLKOUT1**.
  - Asynchronous interrupts: pulses should be stretched to guarantee three consecutive
    low samples.
  - **IDLE2 mode:** interrupt input must be **high for at least four CLKOUT1 cycles and
    low for a minimum of five CLKOUT1 cycles** to be properly recognised.
- Acceptance (§9.1.2, PDF p.514 / printed 9-5): if INTM bit and mask register (IMR)
  properly enabled, interrupt is accepted. **INTM is set and the appropriate IFR bit is
  cleared when the INTR instruction is jammed into the pipeline; after three CLKOUT1
  cycles, IACK is generated** (see Figure 4–9, printed 4-44).
- **NMI uses the same logic as INT1–INT4 except NMI is not affected by IMR or INTM.**
  §9.1.2, PDF p.514 / printed 9-5.
- INFERENCE (not in manual text): the 1-1-0-0-0 synchronizer sequence (two high, three
  low) is consistent with the prose rule (≥2 high then ≥3 low); the prose rule is the
  operative statement, the sequence is the synchronizer implementation detail.

### 9.1.3 Peripheral reset — §9.1.3, PDF p.515 / printed 9-6

On device reset the CPU sends an **SRESET** signal to the peripheral circuits.
§4.9 (Reset, printed 4-45) describes reset events generally. SRESET effects (§9.1.3,
PDF p.515 / printed 9-6):

1. IOWSR and PDWSR set to **FFFFh** → all external accesses occur with **seven wait
   states**. CWSR loaded with **0Fh**.
2. FO bits of SPC and TSPC/BSPC cleared → **16-bit word length** for each serial port.
3. FSM bits of SPC and TSPC/BSPC cleared. FSM must be set for operation with frame
   sync pulses.
4. TXM bits of SPC and TSPC/BSPC cleared → **FSX and TFSX pins configured as inputs**.
5. SPC and TSPC/BSPC loaded with **0y00h, where the two MSBs of y are 10₂ and the two
   LSBs of y reflect the current levels on the transmit and receive clock pins** of the
   respective port. (Verified against rendered PDF p.515; `pdftotext` renders this as
   "102" — the subscript 2 is a binary radix marker, not part of the value.)
6. **TIM and PRD loaded with FFFFh. TDDR and TSS fields of the TCR are cleared and
   the timer starts.**
7. On the HPI, **HINT and SMOD are cleared while in reset, and then set after reset goes
   high.**

#### Reset values of peripheral registers (within §9.1–§9.6 scope)

| Register | Addr | Reset value | Source |
|---|---|---|---|
| TIM | 24h | FFFFh | §9.1.3 item 6, PDF p.515 / printed 9-6 |
| PRD | 25h | FFFFh | §9.1.3 item 6, PDF p.515 / printed 9-6 |
| TCR | 26h | TDDR = 0000, TSS = 0, Soft = 0, Free = 0, Reserved bits 15–12 read as 0; PSC/TRB reset "—" (see note) | §9.1.3 item 6 + §9.3.1 Table 9–4, PDF pp. 515, 519 / printed 9-6, 9-10 |
| PDWSR | 28h | FFFFh (→ 7 wait states with CWSR = 0Fh) | §9.1.3 item 1, PDF p.515 / printed 9-6 |
| IOWSR | 29h | FFFFh (→ 7 wait states with CWSR = 0Fh) | §9.1.3 item 1, PDF p.515 / printed 9-6 |
| CWSR | 2Ah | 0Fh (BIG = 0, I/O High = 1, I/O Low = 1, D = 1, P = 1) | §9.1.3 item 1 + §9.4.3 Table 9–9, PDF pp. 515, 526–527 / printed 9-6, 9-17–9-18 |
| SPC | 22h | 0y00h (y MSBs = 10₂; y LSBs = TX/RX clock pin levels); FO = 0, FSM = 0, TXM = 0 | §9.1.3 items 2–5, PDF p.515 / printed 9-6 |
| TSPC/BSPC | 32h | Same as SPC (0y00h; FO = 0, FSM = 0, TXM = 0) | §9.1.3 items 2–5, PDF p.515 / printed 9-6 |
| DRR, DXR, TRCV/BDRR, TDXR/BDXR, TCSR/SPCE, TRTA/AXR, TRAD/BKX, ARR, BKR | 20h, 21h, 30h–37h | Not stated in §9.1–§9.6 | — (reset values, if any, are in §9.7–§9.9, out of range) |
| HPI (HINT, SMOD) | — | Cleared in reset, set after reset goes high | §9.1.3 item 7, PDF p.515 / printed 9-6 |

Note on TCR PSC/TRB reset "—": Table 9–4 gives no reset value for PSC (bits 9–6) or TRB
(bit 5). INFERENCE: since §9.3.2 states PSC is loaded with TDDR when the timer is reset
and reset clears TDDR to 0000, PSC is 0000 after reset; TRB is always read as 0 (§9.3.1,
Table 9–4; §9.3.2). The manual itself does not state a PSC reset value.

---

## 9.2 Clock Generator — §9.2, PDF pp. 516–517 / printed 9-7–9-8

The clock generator consists of an internal oscillator and a phase-lock loop (PLL) circuit;
driven by a crystal resonator circuit or an external clock source. §9.2, PDF p.516 /
printed 9-7.

### 9.2.1 Standard clock options — ’C50, ’C51, ’C52, ’C53, ’C53S only — §9.2.1, Table 9–2, PDF p.516 / printed 9-7

- Internal divide-by-2: crystal across **X1 and X2/CLKIN**; internal oscillator enabled;
  **CLKOUT1 = crystal frequency / 2**. §9.2.1, PDF p.516 / printed 9-7.
- External divide-by-2: external clock directly to **X2/CLKIN**, X1 unconnected;
  external frequency divided by 2 to generate the internal machine cycle.
  §9.2.1, PDF p.516 / printed 9-7.
- PLL option (standard-clock devices): external clock directly to the **CLKIN2 pin**,
  X1 disconnected from VDD, X2/CLKIN connected to VDD. **’C50, ’C51, ’C53, ’C53S:
  multiply-by-1. ’C52: multiply-by-2.** §9.2.1, PDF p.516 / printed 9-7.
  (Note the pin difference vs §9.2.2, where the PLL clock goes to X2/CLKIN — see Gap G2.)

#### Table 9–2. Standard clock options (§9.2.1, PDF p.516 / printed 9-7; verified vs rendered page)

| CLKMD1 | CLKMD2 | Clock mode |
|---|---|---|
| 0 | 0 | External divide-by-2, internal oscillator disabled |
| 0 | 1 | Reserved for test purposes |
| 1 | 0 | PLL clock generator: ’C50/’C51/’C53/’C53S multiply-by-1; ’C52 multiply-by-2 |
| 1 | 1 | External divide-by-2, or internal divide-by-2 with an external crystal |

### 9.2.2 PLL clock options — ’LC56, ’C57S, ’LC57 only — §9.2.2, Table 9–3, PDF p.517 / printed 9-8

- PLL lets the CPU run from a lower external frequency than the machine-cycle rate;
  reduces high-frequency noise from a high-speed switching clock. When the PLL option
  is selected, the external clock source connects directly to the **X2/CLKIN pin**.
  §9.2.2, PDF p.517 / printed 9-8.
- **PLL maximum operating frequency 28.6 MHz (on a 35-ns ’C5x device).** PLL requires
  a transitory locking time specified in the TMS320C5x data sheet.
  §9.2.2, PDF p.517 / printed 9-8.
- **In idle2 power-down mode or stop mode the PLL stops; in idle power-down mode the
  PLL continues operating.** External input frequency specification is in the data sheet.
  §9.2.2, PDF p.517 / printed 9-8.
- Clock mode must not be reconfigured with the clock-mode pins during normal operation.
  During idle2 mode it can be reconfigured **after CLKOUT1 settling high**.
  §9.2.2, PDF p.517 / printed 9-8.

#### Table 9–3. PLL clock options (§9.2.2, PDF p.517 / printed 9-8; verified vs rendered page)

| CLKMD1 | CLKMD2 | CLKMD3 | Clock mode |
|---|---|---|---|
| 0 | 0 | 0 | PLL multiply-by-3 |
| 0 | 0 | 1 | External divide-by-2, internal oscillator disabled |
| 0 | 1 | 0 | PLL multiply-by-4 |
| 0 | 1 | 1 | PLL multiply-by-2 |
| 1 | 0 | 0 | PLL multiply-by-5 |
| 1 | 0 | 1 | PLL multiply-by-1 |
| 1 | 1 | 0 | PLL multiply-by-9 |
| 1 | 1 | 1 | External divide-by-2, or internal divide-by-2 with internal oscillator enabled |

C51 relevance: the ’C51 is a standard-clock device (§9.2.1 set); the §9.2.2 PLL table
does NOT apply to the ’C51. The ’C51 PLL option is CLKMD1=1, CLKMD2=0, multiply-by-1
via the CLKIN2 pin (§9.2.1).

---

## 9.3 Timer — §9.3, PDF pp. 518–521 / printed 9-9–9-12

On-chip down counter used to periodically generate CPU interrupts (Figure 9–2).
Driven by a prescaler decremented by 1 at every CLKOUT1 cycle. **A timer interrupt
(TINT) is generated each time the counter decrements to 0.** When the timer is stopped
(TSS = 1) the internal clocks to the timer are shut off (low-power mode).
§9.3, PDF p.518 / printed 9-9.

### 9.3.1 Timer registers — §9.3.1, Figure 9–3, Table 9–4, PDF pp. 518–519 / printed 9-9–9-10

Registers: **TCR** (26h), **TIM** (24h), **PRD** (25h). Figure 9–2 (timer block diagram)
shows PRD → TIM, TDDR → PSC, with Borrow outputs; SRESET and TRB feed the block;
outputs TINT and TOUT. §9.3, Figure 9–2, PDF p.518 / printed 9-9.

#### Table 9–4. Timer control register (TCR) bit summary (§9.3.1, PDF p.519 / printed 9-10)

Bit layout (Figure 9–3): bits 15–12 Reserved | 11 Soft | 10 Free | 9–6 PSC | 5 TRB |
4 TSS | 3–0 TDDR.

| Bit | Name | Reset | Function |
|---|---|---|---|
| 15–12 | Reserved | — (always read as 0) | Reserved; always read as 0 |
| 11 | Soft | 0 | With Free, sets timer state on halt. Free = 0: Soft selects emulation mode. Soft = 0 → timer stops immediately. Soft = 1 → timer stops after decrementing to zero |
| 10 | Free | 0 | With Soft, sets timer state on halt. Free = 0 → Soft bit selects timer mode. Free = 1 → timer runs free regardless of Soft |
| 9–6 | PSC | — | Timer prescaler counter. Count for the on-chip timer. When PSC is decremented past 0 or the timer is reset, PSC is loaded with TDDR and TIM is decremented |
| 5 | TRB | — (always read as 0) | Timer reload bit. Resets the on-chip timer. When TRB is set, TIM is loaded with PRD and PSC is loaded with TDDR. TRB is always read as 0 |
| 4 | TSS | 0 | Timer stop status bit. TSS = 0 → timer started. TSS = 1 → timer stopped. At reset TSS is cleared and the timer immediately starts timing. **Two successive writes of 1 to TSS are required to properly stop the timer** (timer logic implementation) |
| 3–0 | TDDR | 0000 | Timer divide-down register. Divide-down ratio (period) for the on-chip timer. When PSC is decremented past 0, PSC is loaded with TDDR |

- TIM (24h): timer counter register; PRD (25h): timer period register. Reset: both FFFFh
  (§9.1.3 item 6). §9.3.1, PDF p.518 / printed 9-9; §9.1.3, PDF p.515 / printed 9-6.

### 9.3.2 Timer operation — §9.3.2, PDF p.520 / printed 9-11

- When PSC decrements to 0, or the timer is reset by setting TRB: TDDR is loaded into
  PSC and TIM is decremented. §9.3.2, PDF p.520 / printed 9-11.
- When TIM decrements to 0, or the timer is reset by setting TRB: PRD is loaded into TIM.
  TRB is always read as 0; writing 1 to TRB resets the timer but TRB still reads as 0.
  §9.3.2, PDF p.520 / printed 9-11.
- Each time a down counter (PSC or TIM) decrements to 0, a borrow is generated on the
  **next CLKOUT1 cycle** and the down counter is reloaded with its period register
  (TDDR or PRD). The output of the second stage is the TINT signal sent to the CPU and
  to the timer output (**TOUT**) pin. The width of the borrow pulse at the second-stage
  output equals **tc(C)** (one CLKOUT1 period). §9.3.2, PDF p.520 / printed 9-11.
- Reading TIM gives the current timer value; reading TCR gives PSC. Two instructions
  are needed to read both, so the value may change between reads — for precise timing
  measurements stop the timer first. Two successive writes of 1 to TSS are required to
  properly stop the timer. §9.3.2, Note, PDF p.520 / printed 9-11.
- TINT rate = CLKOUT1 frequency divided by two independent factors (u = TDDR + 1,
  v = PRD + 1). §9.3.2, PDF p.520 / printed 9-11.

#### Timer period formula (§9.3.2, PDF p.520 / printed 9-11; formula verified vs rendered page)

```
TINT rate = 1 / [ tc(C) × (TDDR + 1) × (PRD + 1) ]
```

where tc(C) = period of CLKOUT1, u = TDDR contents + 1, v = PRD contents + 1.
Equivalently: TINT rate = f(CLKOUT1) / [(TDDR + 1)(PRD + 1)].
Timer period = tc(C) × (TDDR + 1) × (PRD + 1).

#### Worked example — Example 9–1, §9.3.2, PDF p.521 / printed 9-12

CLKIN = 20 MHz, timer running at 10 MHz (CLKOUT1 = 10 MHz). Target 50 kHz (20 µs period):

```
LDP    #0
SPLK   #199, PRD      ; PRD = 199 → v = 200
OPL    #8, IMR        ; set timer interrupt mask bit (IMR bit 3)
SPLK   #20h, TCR      ; TRB = 1 (reload), TDDR = 0 → u = 1; timer starts
SPLK   #1000b, IFR    ; clear any pending timer interrupt (IFR bit 3)
CLRC   INTM           ; global interrupt enable
```

Check: 10 MHz / (1 × 200) = 50 kHz. ✓ (Arithmetic is mine; register values are the manual's.)

#### Example 9–2 — timer ISR (§9.3.2, PDF p.521 / printed 9-12)

```
TIMER_ISR  MAR *, AR3   ; auxiliary register reserved for timer ISR
           IN *, 14     ; read A/D (port 14)
           RETE         ; re-enable interrupts and return
```

### Timer operation modes (summary of §9.3.1–§9.3.2)

| Mode / condition | Behaviour |
|---|---|
| Running (TSS = 0) | PSC decrements every CLKOUT1; PSC borrow → TIM decrements; TIM borrow → TINT + TOUT pulse, TIM reloads from PRD |
| Stopped (TSS = 1) | Timer stopped; internal timer clocks shut off (low power). Requires two successive writes of 1 to TSS |
| Reset (TRB = 1 written) | TIM ← PRD, PSC ← TDDR; TRB reads back 0 |
| Halt, Free = 1 | Timer runs free regardless of Soft |
| Halt, Free = 0, Soft = 0 | Timer stops immediately |
| Halt, Free = 0, Soft = 1 | Timer stops after decrementing to zero |

Sources: §9.3, PDF p.518 / printed 9-9; §9.3.1 Table 9–4, PDF p.519 / printed 9-10;
§9.3.2, PDF p.520 / printed 9-11.

---

## 9.4 Software-Programmable Wait-State Generators — §9.4, PDF pp. 522–528 / printed 9-13–9-19

- Extend external bus cycles by **up to seven machine cycles**. Interfaces the ’C5x to
  external devices that do not meet full-speed access-time requirements. Devices needing
  more than seven wait states use the hardware **READY** line. §9.4, PDF p.522 / printed 9-13.
- **Wait-state generators affect external accesses only.** §9.4, PDF p.522 / printed 9-13.
- When all external accesses are configured for zero wait states, the internal clocks to
  the wait-state generators are shut off (lower power). §9.4, PDF p.522 / printed 9-13.
- Control: two 16-bit wait-state registers (PDWSR, IOWSR) + one 5-bit control register
  (CWSR). Each of the three external spaces (program, data, I/O) has an assigned field in
  a software wait-state register. §9.4, PDF p.522 / printed 9-13.
- Reset: PDWSR = IOWSR = FFFFh, CWSR = 0Fh → 7 wait states on all external accesses
  (§9.1.3 item 1). §9.4, PDF p.522 / printed 9-13; §9.1.3, PDF p.515 / printed 9-6.

### 9.4.1 Program/data wait-state register (PDWSR, 28h) — §9.4.1, Figures 9–4/9–5, Tables 9–5/9–6, PDF pp. 522–523 / printed 9-13–9-14

Two device variants exist. The manual assigns them by device name; see Gap G1 for
’C53 and ’C57S, which are named in neither figure title.

#### Variant A — ’C50, ’C51, ’C52 only: 2-bit field per 16K block (Figure 9–4, Table 9–5; §9.4.1, PDF pp. 522–523 / printed 9-13–9-14)

Program and data spaces are each 64K words = four 16K-word blocks; each block has a
2-bit wait-state field in PDWSR. Field value = number of wait states (subject to CWSR
mapping, §9.4.3). At reset PDWSR = FFFFh.

| PDWSR bits | Space | Hex address range |
|---|---|---|
| 15–14 | Data 4 | C000–FFFF |
| 13–12 | Data 3 | 8000–BFFF |
| 11–10 | Data 2 | 4000–7FFF |
| 9–8 | Data 1 | 0000–3FFF |
| 7–6 | Program 4 | C000–FFFF |
| 5–4 | Program 3 | 8000–BFFF |
| 3–2 | Program 2 | 4000–7FFF |
| 1–0 | Program 1 | 0000–3FFF |

#### Variant B — ’C53S, ’LC56, ’C57 only: single 3-bit field per space (Figure 9–5, Table 9–6; §9.4.1, PDF p.523 / printed 9-14)

Simpler version: program, data and I/O wait states each specified by one 3-bit field in
PDWSR; all external addresses in each space independently settable 0–7 wait states.

| PDWSR bits | Space | Hex address range |
|---|---|---|
| 15–9 | Reserved | — |
| 8–6 | I/O | 0000–FFFF |
| 5–3 | Data | 0000–FFFF |
| 2–0 | Program | 0000–FFFF |

The ’C51 uses Variant A (2-bit fields per 16K block). §9.4.1, Figure 9–4/Table 9–5,
PDF pp. 522–523 / printed 9-13–9-14.

### READY interaction and cycle counts — §9.4.1, Table 9–7, PDF p.524 / printed 9-15

- Software wait states and writes: with the on-chip generator, the number of CLKOUT1
  cycles required for **writes is not affected until two or more wait states are
  specified** — contrary to wait states generated with the external READY input.
  (Manual's word is "effected"; read as "affected".) §9.4.1, PDF p.524 / printed 9-15.
- **External READY is sampled only after the internal software wait states are
  completed.** If READY is driven low before software wait states complete, no wait
  states are added until the specified software wait states are completed; wait states
  are added only if READY is still low after the software wait states complete.
  §9.4.1, PDF p.524 / printed 9-15.
- **READY is not an asynchronous input**; its setup and hold times in the TMS320C5x
  data sheet must be met or "significant device malfunction will result."
  §9.4.1, PDF p.524 / printed 9-15.

#### Table 9–7. CLKOUT1 cycles per access vs wait states (§9.4.1, PDF p.524 / printed 9-15; verified vs rendered page)

| No. of wait states | Hardware wait state: Read | Hardware wait state: Write | Software wait state: Read | Software wait state: Write |
|---|---|---|---|---|
| 0 | 1 | 2n + 1 | 1 | 2n + 1 |
| 1 | 2 | 3n + 1 | 2 | 2n + 1 |
| 2 | 3 | 4n + 1 | 3 | 3n + 1 |
| 3 | 4 | 5n + 1 | 4 | 4n + 1 |

† n = number of consecutive write cycles. **The manual's Table 9–7 lists only 0–3
wait states**, although §9.4.3/Tables 9–9–9–10 allow up to 7 wait states when the
corresponding CWSR bit is 1 (and Variant B PDWSR allows 0–7 directly). No 4–7 rows
are given anywhere in §9.4. See Gap G3.

### 9.4.2 I/O wait-state register (IOWSR, 29h) — §9.4.2, Figure 9–6, Table 9–8, PDF pp. 525–526 / printed 9-16–9-17

- I/O space = 64K word addresses. IOWSR maps in either of two ways per the BIG bit in
  CWSR. 2-bit field value = wait states for the given port/address range (subject to
  CWSR mapping, §9.4.3). At reset IOWSR = FFFFh. §9.4.2, PDF p.525 / printed 9-16.
- **BIG = 0:** eight pairs of memory-mapped I/O ports, one 2-bit field per pair. The
  entire I/O space is configured with wait states on 2-word boundaries (port 0/1,
  port 10/11, port 20/21 all have the same number of wait states). Maximum flexibility
  for peripherals such as D/A and A/D devices. §9.4.2, PDF p.525 / printed 9-16.
- **BIG = 1:** 64K-word space divided into eight 8K-word blocks, one 2-bit field per
  block. §9.4.2, PDF p.525 / printed 9-16.
- Figure 9–6 bit layout: bits 15–14 I/O 8 | 13–12 I/O 7 | 11–10 I/O 6 | 9–8 I/O 5 |
  7–6 I/O 4 | 5–4 I/O 3 | 3–2 I/O 2 | 1–0 I/O 1. §9.4.2, PDF p.525 / printed 9-16.

#### Table 9–8. IOWSR address ranges (§9.4.2, PDF pp. 525–526 / printed 9-16–9-17)

| Field bits | I/O field | BIG = 0 (port pairs) | BIG = 1 (8K blocks) |
|---|---|---|---|
| 1–0 | I/O 1 | Port 0/1, port 10/11, etc. | 0000–1FFF |
| 3–2 | I/O 2 | Port 2/3, port 12/13, etc. | 2000–3FFF |
| 5–4 | I/O 3 | Port 4/5, port 14/15, etc. | 4000–5FFF |
| 7–6 | I/O 4 | Port 6/7, port 16/17, etc. | 6000–7FFF |
| 9–8 | I/O 5 | Port 8/9, port 18/19, etc. | 8000–9FFF |
| 11–10 | I/O 6 | Port 0A/0B, port 1A/1B, etc. | A000–BFFF |
| 13–12 | I/O 7 | Port 0C/0D, port 1C/1D, etc. | C000–DFFF |
| 15–14 | I/O 8 | Port 0E/0F, port 1E/1F, etc. | E000–FFFF |

INFERENCE (from the "port 0/1, port 10/11, port 20/21" examples): with BIG = 0 the
field index is the port address bits [3:1], i.e. the mapping repeats every 16 ports.
The manual does not state the bit selection explicitly.

### 9.4.3 Wait-state control register (CWSR, 2Ah) — §9.4.3, Figure 9–7, Tables 9–9/9–10, PDF pp. 526–527 / printed 9-17–9-18

- CWSR selects one of two IOWSR mappings (BIG) and one of two mappings between the
  2-bit wait-state fields and the number of wait states (bits 0–3). **Always program
  CWSR before configuring PDWSR and IOWSR**, to avoid configuring memory with too
  few wait states during setup. §9.4.3, PDF p.526 / printed 9-17.
- If a bit (0–3) is cleared, wait states = field value. If set, wait states follow
  Table 9–10. §9.4.3, PDF p.526 / printed 9-17.
- Bit layout (Figure 9–7): bits 15–5 Reserved | 4 BIG | 3 I/O High | 2 I/O Low |
  1 D | 0 P. §9.4.3, PDF p.526 / printed 9-17.

#### Table 9–9. CWSR bit summary (§9.4.3, PDF pp. 526–527 / printed 9-17–9-18)

| Bit | Name | Reset | Function |
|---|---|---|---|
| 15–5 | Reserved | 0 | Reserved |
| 4 | BIG | 0 | IOWSR mapping. 0 → eight pairs of I/O ports, 2-bit field per pair. 1 → eight 8K-word blocks, 2-bit field per block |
| 3 | I/O High | 1 | With IOWSR 2-bit field, sets wait states for I/O upper half (I/O 5–I/O 8). 0 → 0, 1, 2, or 3. 1 → 0, 1, 3, or 7 |
| 2 | I/O Low | 1 | With IOWSR 2-bit field, sets wait states for I/O lower half (I/O 1–I/O 4). 0 → 0, 1, 2, or 3. 1 → 0, 1, 3, or 7 |
| 1 | D | 1 | Data memory space. 0 → 0, 1, 2, or 3 wait states. 1 → 0, 1, 3, or 7 |
| 0 | P | 1 | Program memory space. 0 → 0, 1, 2, or 3 wait states. 1 → 0, 1, 3, or 7 |

Reset value check: bits 15–5 = 0, BIG = 0, bits 3–0 = 1111 → 000Fh = 0Fh, matching
§9.1.3 item 1. (Arithmetic is mine; bit values are Table 9–9's.)

#### Table 9–10. Wait-state field value → number of wait states, as a function of CWSR bits 0–3 (§9.4.3, PDF p.527 / printed 9-18)

| PDWSR/IOWSR 2-bit field | Wait states (CWSR bit = 0) | Wait states (CWSR bit = 1) |
|---|---|---|
| 00 | 0 | 0 |
| 01 | 1 | 1 |
| 10 | 2 | 3 |
| 11 | 3 | 7 |

Applies per space: P bit → program fields, D bit → data fields, I/O Low → I/O 1–4,
I/O High → I/O 5–8. Table 9–10 footnote: the field is the 2-bit field of Figure 9–4
(PDWSR Variant A) and Figure 9–6 (IOWSR). §9.4.3, PDF p.527 / printed 9-18.

### 9.4.4 Logic for external program space — §9.4.4, Figure 9–8, PDF p.528 / printed 9-19

- On an external program access decode, the appropriate PDWSR field is loaded into
  the counter (Figure 9–8: 2-to-4 decoder from PSEL, A14, A15 selects PDWSR field
  Y0–Y3 → 3-bit counter). If the field is **not 00₂**, a not-ready signal is sent to the
  CPU. Not-ready is maintained until the counter decrements to 0 **and** the external
  READY line is high. The external READY and the wait-state READY are ORed to
  generate the CPU WAIT signal. READY is sampled at the **rising edge of CLKOUT1**.
  §9.4.4, PDF p.528 / printed 9-19. (Verified vs rendered PDF p.528: the text reads
  "not 00₂"; `pdftotext` renders it as "0002".)
- Note: **the external READY line is sampled only at the last cycle of an external
  access** if the on-chip wait-state generator is used to insert software wait states.
  §9.4.4, Note, PDF p.528 / printed 9-19.

---

## 9.5 General-Purpose I/O Pins — §9.5, PDF pp. 529–530 / printed 9-20–9-21

Two software-controlled general-purpose pins: **BIO** (branch control input) and **XF**
(external flag output). Detailed timing specifications are in the TMS320C5x data sheet,
not in this chapter. §9.5, PDF p.529 / printed 9-20.

### 9.5.1 Branch control input (BIO) — §9.5.1, Figure 9–9, PDF p.529 / printed 9-20

- BIO monitors peripheral device status, especially as an alternative to an interrupt
  when time-critical loops must not be disturbed. A branch can be conditionally executed
  depending on the state of BIO. §9.5.1, PDF p.529 / printed 9-20.
- Pipeline test point (§9.5.1, PDF p.529 / printed 9-20):
  - **XC instruction:** BIO tested during the **decode (second) phase** of the pipeline.
  - **All other instructions** (BCND, BCNDD, CC, CCD, RETC, RETCD): BIO tested during
    the **execute (fourth) phase** of the pipeline.
- Figure 9–9 (BIO timing diagram) shows setup, hold and pulse-width parameters
  against CLKOUT1 for single-cycle, single-word instructions in external memory, but
  **no numeric values are given in the chapter** — actual timing specifications are in
  the TMS320C5x data sheet. §9.5.1, PDF p.529 / printed 9-20.
- Instructions that test BIO (per §9.5.1): **XC, BCND, BCNDD, CC, CCD, RETC, RETCD**.
  The BIO condition itself (branch-if-BIO / branch-if-not-BIO) is selected by the
  instruction's condition field — the chapter does not enumerate the condition codes;
  those are in the instruction-set chapter (out of range).

### 9.5.2 External flag output (XF) — §9.5.2, Figure 9–10, PDF p.530 / printed 9-21

- XF signals to external devices via software. **Set high by `SETC XF`; reset low by
  `CLRC XF`. XF is set high at device reset.** §9.5.2, PDF p.530 / printed 9-21.
- Figure 9–10 shows the relationship between the time the SETC/CLRC instruction is
  fetched and the time XF is set/reset, for single-cycle, single-word instructions in
  external memory; actual timing can vary with different instruction sequences and
  the numeric delay is in the data sheet, not the chapter. §9.5.2, PDF p.530 / printed 9-21.
- Instructions that set/clear XF: **SETC XF** (XF = 1), **CLRC XF** (XF = 0).
  No instruction reads XF back as a flag in this chapter; XF is write-only via the
  status-register XF bit (SETC/CLRC operate on ST1.XF — INFERENCE from the instruction
  names; the chapter itself only names the two instructions).

---

## 9.6 Parallel I/O Ports — §9.6, Figure 9–11, PDF p.531 / printed 9-22

- **64K parallel I/O ports.** Sixteen of them are memory-mapped in data page 0
  (PA0–PA15, 50h–5Fh; Table 9–1). §9.6, PDF p.531 / printed 9-22.
- Access: **IN and OUT instructions, or any instruction that reads or writes a location
  in data memory space.** §9.6, PDF p.531 / printed 9-22.
- **Port address range: 64K (0000h–FFFFh)** for IN/OUT; the 16 memory-mapped ports
  are at data-memory addresses 50h–5Fh (dec 80–95). §9.6, PDF p.531 / printed 9-22;
  Table 9–1, PDF pp. 512–513 / printed 9-3–9-4.
- Access signalling: accesses to memory-mapped I/O space are distinguished from program
  and data accesses by the **IS signal going low; the DS signal is not active**, even
  though the I/O port is actually accessed through data space. §9.6, PDF p.531 / printed 9-22.
- **RD** can be used with chip-select logic to generate an output-enable for an external
  peripheral; **WE** with chip-select logic to generate a write-enable. Figure 9–11
  shows typical interface circuitry (two 74AS138 decoders: IS + A0–A2 decode ports 0–F
  with RD → OE for an input device and WE → WE for an output device). The decode can
  be simplified if fewer I/O ports are used. §9.6, PDF p.531 / printed 9-22.
- Example (§9.6, PDF p.531 / printed 9-22; DP = 0):

```
SACL  51h   ; store accumulator to external device on port 81 (51h = 81 decimal)
```

- Timing: no I/O-port timing numbers are given in §9.6; Figure 9–11 is a logic
  schematic, not a timing diagram. (Bus-cycle timing for I/O accesses is governed by
  the wait-state rules of §9.4 and Table 9–7.)

---

## Contradictions, gaps and unverified items

### Contradictions (both readings recorded; normative choice stated)

- **C1 — "17 peripheral registers" vs 16 addresses in Table 9–1.** §9.1.1 (PDF p.511 /
  printed 9-2) says there are 17 peripheral registers. Table 9–1 (§9.1.1, PDF pp. 511–513 /
  printed 9-2–9-4) enumerates 16 peripheral-register addresses: 20h, 21h, 22h, 24h, 25h,
  26h, 28h, 29h, 2Ah, 30h, 31h, 32h, 33h, 34h, 35h, 36h, 37h (9 + 7 shared TDM/BSP
  addresses; 23 names because 7 addresses carry two names each). **Normative: the table**,
  because it is the enumerative address map and every address in it is individually
  verifiable; the "17" is treated as a manual counting error (or as counting a register
  not listed in the table, e.g. an HPI register — the manual does not say which).
- **C2 — "decremented past 0" vs "decrements to 0" (timer reload trigger).** Table 9–4
  PSC description (§9.3.1, PDF p.519 / printed 9-10) says PSC is loaded with TDDR "when
  the PSC is decremented past 0"; §9.3.2 (§9.3.2, PDF p.520 / printed 9-11) says "when
  the PSC decrements to 0" (and likewise for TIM/PRD). **Normative: §9.3.2 + Figure 9–2**,
  i.e. the counter reaching 0 generates a borrow on the next CLKOUT1 cycle and is then
  reloaded — this is the only reading consistent with the borrow-pulse description
  ("each time a down counter decrements to 0, a borrow is generated on the next CLKOUT1
  cycle"). The two wordings describe the same event from opposite sides of the 0 boundary.

### Gaps / ambiguities in the manual (within §9.1–§9.6)

- **G1 — PDWSR variant assignment incomplete.** Figure 9–4/Table 9–5 are titled
  "’C50, ’C51, and ’C52 only"; Figure 9–5/Table 9–6 "’C53S, ’LC56, and ’C57 only"
  (§9.4.1, PDF pp. 522–523 / printed 9-13–9-14). The ’C53 (non-S) and ’C57S are named
  in neither. INFERENCE: ’C53 → Variant A (it is a standard-clock device per §9.2.1)
  and ’C57S → Variant B (PLL family per §9.2.2). The manual does not state this.
- **G2 — PLL clock pin differs by family.** §9.2.1 (PDF p.516 / printed 9-7) routes the
  PLL clock to the **CLKIN2** pin (X1 off VDD, X2/CLKIN tied to VDD) for ’C50/’C51/’C52/
  ’C53/’C53S; §9.2.2 (PDF p.517 / printed 9-8) routes it directly to **X2/CLKIN** for
  ’LC56/’C57S/’LC57. Not a contradiction — different device families — but an agent
  must not mix the two wirings. The ’C51 follows §9.2.1 (CLKIN2, ×1).
- **G3 — Table 9–7 stops at 3 wait states.** Table 9–7 (§9.4.1, PDF p.524 / printed 9-15)
  tabulates only 0–3 wait states, although CWSR = 1 mappings (§9.4.3, Tables 9–9/9–10)
  and Variant B PDWSR (§9.4.1, Table 9–6) allow up to 7. No cycle counts for 4–7 wait
  states are given in §9.4. Do not extrapolate the Table 9–7 write formulas to 4–7.
- **G4 — CWSR/IOWSR vs Variant B PDWSR.** §9.4.2/§9.4.3 and Tables 9–8–9–10 are written
  for 2-bit fields (Variant A devices). The manual does not state whether CWSR bits 0–3
  or the IOWSR have any effect on ’C53S/’LC56/’C57, whose PDWSR already carries 3-bit
  I/O, data and program fields (§9.4.1, PDF p.523 / printed 9-14).
- **G5 — No reset values stated in §9.1–§9.6** for DRR, DXR and the TDM/BSP data/control
  registers at 30h–37h (see reset table in §9.1.3 above); their reset behaviour is in
  §9.7–§9.9, out of range.
- **G6 — No numeric timing in §9.5/§9.6.** BIO setup/hold/pulse-width (Figure 9–9),
  XF fetch-to-pin delay (Figure 9–10) and parallel-I/O bus timing are all deferred to
  the TMS320C5x data sheet (§9.5, PDF pp. 529–530 / printed 9-20–9-21; §9.6, PDF p.531 /
  printed 9-22). Only the qualitative rules in §9.5/§9.6 above are in the chapter.

### Unverified items

- None within §9.1–§9.6 required an `[UNVERIFIED]` marker: every garbled extraction
  (Table 9–2/9–3 column alignment, Table 9–7 rows, §9.1.3 item 5 "0y00h / 10₂",
  §9.4.4 "00₂", the §9.3.2 TINT formula) was resolved by inspecting the rendered PDF
  pages (PDF pp. 515, 516, 517, 520, 524, 528). The TCR diagram (Figure 9–3) itself is
  extraction-garbled, but its content is fully recoverable from Table 9–4 (§9.3.1,
  PDF p.519 / printed 9-10), which is the normative bit definition used above.
