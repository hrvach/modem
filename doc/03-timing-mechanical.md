# TMS320C51 — Clock, Bus, Serial, HPI, Reset Timing & Mechanical Data

Distilled from TI datasheet **SPRS030A, April 1995, revised April 1996, PDF pp. 51–86 only**.
Source: `SPRS030A.txt` (pdftotext -layout); PDF `SPRS030A.pdf`. PDF pp. 87–94 are later TI.com addenda, NOT part of the 1996 datasheet — ignored.

## Conventions used throughout

- `tc(CO)` = CLKOUT1 cycle time (one machine cycle). `H = 0.5 tc(CO)` (SPRS030A, p. 53 and passim).
  Hence `2H = 1 cycle`, `12H = 6 cycles`, `34H = 17 cycles`.
- **C51 speed grades** (SPRS030A Table 1, chunk A): TMS320C51 cycle times **50 / 35 / 25 / 20 ns**,
  i.e. datasheet grades **-40 / -57 / -80 / -100**. LC51 is 50/40/25 ns only (no 20 ns grade).
  Grade number ≈ max CLKIN frequency (MHz) in divide-by-two mode: -40 → tc(CI) min 24.4 ns,
  -100 → tc(CI) min 10 ns (SPRS030A p. 54).
- Many timing tables group grades into **three columns**: (-40/-57, LC-40/LC-50) | (-80, LC-80) | (-100).
  The read/write tables on pp. 58–60 instead give **four separate C5x columns** (-40, -57, -80, -100).
  Values below follow the grouping of the table they come from.
- The device is fully static: tc(CI)/tc(CO) max is unbounded († in the tables); characterised near 0 Hz,
  tested at fclk = 6.7 MHz (divide-by-two) or tc(CO) = 300 ns (PLL) (SPRS030A pp. 52–53).
- `[UNVERIFIED]` = value/column assignment unclear in the pdftotext extraction; not guessed.
  "Derived from characterization data and not tested" / "assured by design and not tested" footnotes
  are noted where the datasheet marks them; they are TI's qualification, not this distillation's doubt.

## 0. Which devices / ports this covers

- **C51 serial ports: 1× standard serial port + 1× TDM port. No BSP, no HPI.**
  Datasheet-internal evidence: Table 1 (chunk A) gives 'C51 serial = 2, 'C52 = 1¶, 'LC56 = 2#;
  PZ-package pin table (chunk A, Table 2) assigns pin 5 as **TCLKX on 'C51** vs **BCLKX on 'LC56**,
  pin 92 as **TFSX/TFRM on 'C51** vs **BFSX on 'LC56** — i.e. the B-prefixed BSP pins belong to
  'LC56/'C57 devices, not 'C51. The HPI section heading itself reads
  "HOST PORT INTERFACE (TMS320C57S, TMS320LC57 ONLY)" (SPRS030A p. 77).
  Agrees with SPRU056D distilled manual `../c5x_manual/09b-peripherals-serial-bsp-tdm-hpi.md` §0.
- BSP timing (§5 below) and HPI timing (§6) are therefore included only as **contrast / non-C51
  reference**; do not model them into a C51.
- **C51 packages: PQ 132-pin and PZ 100-pin only** (SPRS030A Table 1, chunk A). PBK 128-pin, PJ 100-pin,
  PGE 144-pin drawings in these pages belong to other family members, not C51 (§7).

---

## 1. Clock characteristics and timing (SPRS030A pp. 51–57)

### 1.1 Clock modes — standard set, C50/C51/C52/C53/C53S (Table 9, p. 51)

| CLKMD1 | CLKMD2 | Clock source |
|---|---|---|
| 1 | 0 | PLL clock generator (see §1.3) |
| 0 | 1 | Reserved for test purposes |
| 1 | 1 | External divide-by-two, or internal divide-by-two with external crystal |
| 0 | 0 | External divide-by-two, internal oscillator disabled |

Table 10 (expanded PLL ×3/×4/×5/×9 etc., CLKMD3) applies **only to 'LC56, 'C57S, 'LC57** — not C51
(SPRS030A p. 51). SPRU056D §9.2.1/§9.2.2 agrees (`../c5x_manual/09a-...md` §9.2).

### 1.2 Internal divide-by-two with crystal (p. 52)

- Crystal across X1 and X2/CLKIN; **CLKOUT1 = crystal frequency / 2**.
- Crystal: fundamental or overtone, parallel resonant, ESR 30 Ω, dissipation 1 mW, specified at 20 pF load.
  Overtone crystals need an additional tuned-LC circuit. Load caps C1, C2 = 10 pF (SPRS030A p. 52, Fig. 12).
- Input-clock frequency (fclk) max, internal divide-by-two (SPRS030A p. 52):

| Grade | Max fclk |
|---|---|
| 'C5x-40 | 40.96 MHz |
| 'C5x-57 | 57.14 MHz |
| 'C5x-80 | 80 MHz |
| 'C5x-100 | 100 MHz (footnote: "'320C51, '320C52 currently available at this clock speed") |
| 'LC5x-40 / -50 / -80 | 40 / 50 / 80 MHz |

### 1.3 External divide-by-two (pp. 53–54)

External source injected directly into X2/CLKIN, X1 unconnected (SPRS030A p. 53, Fig. 13).

CLKOUT1 switching ('C5x only; LC5x values identical except where noted):

| Parameter | -40 (48.8 ns) | -57 (35 ns) | -80 (25 ns) | -100 (20 ns) |
|---|---|---|---|---|
| tc(CO) min | 48.8 ns | 35 ns | 25 ns | 20 ns |
| tc(CO) typ | 2·tc(CI) | 2·tc(CI) | 2·tc(CI) | 2·tc(CI) |
| td(CIH-COH/L) X2/CLKIN high → CLKOUT1 high/low | 3 / 11 / 20 ns | 3 / 11 / 20 ns | 1 / 9 / 18 ns | 1 / 9 / 18 ns |
| tf(CO), tr(CO) max | 5 ns | 5 ns | 4 ns | 4 ns |
| tw(COL), tw(COH) | H−3 / H / H+2 | H−3 / H / H+2 | H−3 / H / H+2 | H−3 / H / H+2 |

LC5x: tc(CO) min 50 / 40 / 25 ns for -40 / -50 / -80; td(CIH-COH/L) 3/11/20 ns (-40/-50), 1/9/18 ns (-80)
(SPRS030A p. 53).

X2/CLKIN timing requirements ('C5x only):

| Parameter | -40 | -57 | -80 | -100 |
|---|---|---|---|---|
| tc(CI) min | 24.4 ns | 17.5 ns | 12.5 ns | 10 ns |
| tf(CI), tr(CI) max | 5 ns | 5 ns | 4 ns | 4 ns |
| tw(CIL), tw(CIH) min | 11 ns | 8 ns | 5 ns | 5 ns |

LC5x: tc(CI) min 25 / 20 / 12.5 ns (-40/-50/-80); tw(CIL/H) min 11 / 9 / 5 ns (SPRS030A p. 54).
tf/tr(CI) are "derived from characterization data and not tested" (SPRS030A p. 54).

### 1.4 PLL clock generator option (pp. 55–57) — C51: multiply-by-1 only

- Wiring: external source into **CLKIN2**, X1 unconnected, **X2 connected to VDD**
  (SPRS030A p. 55). Multiply-by-1 on 'C50/'C51/'C53/'C53S; multiply-by-2 on 'C52 only;
  ×1/×2/×3/×4/×5/×9 only on 'LC56/'C57S/'LC57 (SPRS030A pp. 55, 57).
- CLKOUT1 switching ('C5x only):

| Parameter | -40 | -57 | -80 | -100 |
|---|---|---|---|---|
| tc(CO) min / max | 48.8 / 75 ns | 35 / 75 ns | 25 / 55 ns | 20 / 45 ns |
| tf(CO), tr(CO) max | 5 ns | 5 ns | 4 ns | 4 ns |
| tw(COL), tw(COH) | H−3† / H / H+2† | H−3† / H / H+2† | H−3† / H / H+2† | H−3† / H / H+2† |
| td(C2H-COH) CLKIN2 high → CLKOUT1 high | 2 / 9 / 16 ns | 2 / 9 / 16 ns | 1 / 8 / 15 ns | 1 / 8 / 15 ns |
| td(TP) transitory phase, PLL sync after CLKIN2 supplied | ≤ 1000·tc(C2) | ≤ 1000·tc(C2) | ≤ 1000·tc(C2) | ≤ 1000·tc(C2) |

† "Values assured by design and not tested" (SPRS030A p. 55). LC5x: tc(CO) 50/75, 40/75, 25/55 ns
(-40/-50/-80); td(C2H-COH) as -40/-57/-80 above (SPRS030A p. 56).
- CLKIN2 timing requirements ('C5x, ×1 row — the only row applying to C51):

| Parameter | -40 | -57 | -80 | -100 |
|---|---|---|---|---|
| tc(C2) min / max (×1) | 48.8 / 75 ns | 35 / 75 ns | 25 / 75 ns | 20 / 75 ns |
| tf(C2), tr(C2) max | 5 ns | 5 ns | 4 ns | 4 ns |
| tw(C2L), tw(C2H) | 15 ns … tc(C2)−15 | 11 ns … tc(C2)−11 | 8 ns … tc(C2)−8 | 7 ns … tc(C2)−7 |

×2 row (C52 only, not C51): tc(C2) min 97.6 / 70 / 50 / 40 ns, max 150 / 150 / 150 / 110 ns
(SPRS030A p. 57). tf/tr(C2) "derived from characterization data and not tested".
- **Clocks can be stopped only while executing IDLE2 when using the PLL option**
  (SPRS030A pp. 56–57, footnotes). td(TP) occurs when restarting the clock from IDLE2.

### 1.5 What the Courier modem needs from this section

The Courier's C51 runs from a crystal or external clock; the DSP-side model needs only:
tc(CO) per grade (20/25/35/50 ns), CLKOUT1 = CLKIN/2 in divide-by-two mode, PLL ×1 via CLKIN2
with X2 tied to VDD, and the 1000·tc(C2) PLL lock transient. No other PLL multiplier exists on C51.

---

## 2. Memory and parallel I/O interface timing (SPRS030A pp. 58–63)

All timings for **0 wait states** unless noted; "address" includes A0–A15, PS, DS, IS, R/W, BR
(SPRS030A pp. 58, 60). Timings are for cycles following the first cycle after reset, which is
always seven wait states (SPRS030A p. 58). Address-bus timing varies with load capacitance,
Fig. 16 (p. 62): +0 to ~+2 ns over 10–100 pF — small; use the table values at nominal load.

### 2.1 Read cycle — switching characteristics (p. 58)

| Parameter | -40 | -57 | -80 | -100 |
|---|---|---|---|---|
| tsu(AV-RDL) address valid before RD low, min | H−10 ns | H−10 ns | H−7 ns | H−6 ns |
| th(RDH-AV) address hold after RD high, min | 0 ns | 0 ns | 0 ns | 0 ns |
| tw(RDL) RD low | H−2 … H+2 | H−2 … H+2 | H−2 … H+2 | H−2 … H+2 |
| tw(RDH) RD high, min | H−2 | H−2 | H−2 | H−2 |
| td(CO-ST) CLKOUT1 → STRB edge | −1 … 3 ns | −2 … 2 ns | −2 … 2 ns | −2 … 2 ns |
| td(CO-RD) CLKOUT1 → RD edge | −3 … 1 ns | −3 … 1 ns | −3 … 1 ns | −3 … 1 ns |
| td(RDH-WEL) RD high → WE low, min | 2H−5 | 2H−5 | 2H−4 | 2H−4 |

LC5x (-40/-50/-80): tsu(AV-RDL) H−10 / H−7; td(CO-RD) −2…2 / −3…1; td(CO-ST) 0…4 / −2…2
(SPRS030A p. 58).

### 2.2 Read cycle — timing requirements (p. 59; what external memory must meet)

| Parameter | -40 | -57 | -80 | -100 |
|---|---|---|---|---|
| ta(RDAV) access time, read data from address valid, max | 2H−18 ns | 2H−15 ns | 2H−10 ns | 2H−10 ns |
| ta(RDL-RD) access time, read data after RD low, max | H−10 ns | H−10 ns | H−7 ns | H−6 ns |
| tsu(RD-RDH) read-data setup before RD high, min | 10 ns | 10 ns | 7 ns | 6 ns |
| th(RDH-RD) read-data hold after RD high, min | 0 ns | 0 ns | 0 ns | 0 ns |

At 20 ns cycle (H = 10 ns): external memory must deliver data within 2H−10 = **10 ns of address
valid**, and data must be set up **6 ns before RD high**. At 50 ns cycle (H = 25 ns): 32 ns / 10 ns.
LC5x: ta(RDAV) 2H−17 / 2H−10; tsu(RD-RDH) 10 / 7 ns (SPRS030A p. 59).

### 2.3 Write cycle — switching characteristics (p. 60)

| Parameter | -40 | -57 | -80 | -100 |
|---|---|---|---|---|
| tsu(AV-WEL) address valid before WE low, min | H−5 ns | H−5 ns | H−4 ns | H−3 ns |
| tsu(WDV-WEH) write-data valid before WE high | 2H−20 … 2H ns | 2H−20 … 2H ns | 2H−14 … 2H ns | 2H−14 … 2H ns |
| th(WEH-AV) address hold after WE high, min | H−10 ns | H−10 ns | H−7 ns | H−7 ns |
| th(WEH-WDV) write-data hold after WE high | H−5 … H+10 ns | H−5 … H+10 ns | H−4 … H+7 ns | H−4 … H+7 ns |
| tw(WEL) WE low | 2H−2 … 2H+2 | 2H−2 … 2H+2 | 2H−2 … 2H+2 | 2H−2 … 2H+2 |
| tw(WEH) WE high, min | 2H−2 | 2H−2 | 2H−2 | 2H−2 |
| td(CO-ST) CLKOUT1 → STRB edge | −1 … 3 ns | −2 … 2 ns | −2 … 2 ns | −2 … 2 ns |
| td(CO-WE) CLKOUT1 → WE edge | 0 … 4 ns | −1 … 3 ns | −1 … 3 ns | −1 … 3 ns |
| td(WEH-RDL) WE high → RD low, min | 3H−10 | 3H−10 | 3H−7 | 3H−7 |
| ten(WEL-BUd) WE low → data bus driven | −5 ns [UNVERIFIED: column assignment unclear in extraction; value as printed] | −5 ns | −4 ns | −4 ns |

LC5x (-40/-50/-80): tsu(AV-WEL) H−7 / H−4; tw(WEL) 2H−4 … 2H+2; td(CO-ST) 0…4 / −2…2;
td(CO-WE) 0…4 / −1…3 (SPRS030A p. 60). STRB/WE edges are 0–4 ns from CLKOUT1 edges on writes;
pulse-width tolerance ±2 ns, not ±4 ns (SPRS030A p. 60, footnote #).

### 2.4 Bus-cycle structure (Fig. 15, Note A, p. 61)

- Diagram shows a **one-cycle read and a two-cycle write** (not to scale); all timings are for 0 wait states.
- **External writes always require two cycles** to prevent external bus conflicts.
- An external write immediately preceded by an external read, or immediately followed by an external
  read, requires **three machine cycles** (SPRS030A p. 61, Fig. 15 Note A).
- Logical (cycle-count) timings are in SPRU056D Appendix B, referenced from the figure (SPRS030A p. 61).
  Cf. distilled `../c5x_manual/09a-...md` §9.4, Table 9–7: read = 1 + n cycles, write = 2 + n cycles
  (n = wait states; hardware-READY writes differ — see §2.5).

### 2.5 READY timing for externally-generated wait states (p. 63)

READY is sampled **only after the internal software wait states are completed**
(SPRS030A p. 63, Note 5; SPRU056D §9.4.1 agrees). Columns here are 3-group:
(-40/-57, LC-40/LC-50) | (-80, LC-80) | (-100).

| Parameter | -40/-57 | -80 | -100 |
|---|---|---|---|
| tsu(RY-COH) READY setup before CLKOUT1 rising edge, min | 10 ns | 7 ns | 6 ns |
| tsu(RY-RDL) READY setup before RD falling edge, min | 10 ns | 7 ns | 6 ns |
| th(COH-RYH) READY hold after CLKOUT1 rising edge, min | 0 ns | 0 ns | 0 ns |
| th(RDL-RY) READY hold after RD falling edge, min | 0 ns | 0 ns | 0 ns |
| th(WEL-RY) READY hold after WE falling edge, min | H+5 ns | H+4 ns | H+3 ns |
| tv(WEL-RY) READY valid after WE falling edge, max | H−15 ns | H−10 ns | H−8 ns |

Fig. 17 (read) / Fig. 18 (write) show READY extending the cycle by whole CLKOUT1 periods
(SPRS030A p. 63). SPRU056D §9.4.1 warns READY is **not** an asynchronous input: these setup/hold
times must be met or "significant device malfunction will result."

### 2.6 HOLD / HOLDA and external DMA (pp. 67–68)

HOLD is **not acknowledged until the current external access request is complete**
(SPRS030A p. 67, footnote †). Columns are 3-group as in §2.5.

Switching characteristics (Fig. 21):

| Parameter | -40/-57 | -80 | -100 |
|---|---|---|---|
| td(HOL-HAL) HOLD low → HOLDA low, min | 4H | 4H | 4H |
| td(HOH-HAH) HOLD high → HOLDA high, min | 2H | 2H | 2H |
| th(AZ-HAL) address/control high-impedance before HOLDA low, min | H−15 ns | H−10 ns | H−8 ns |
| ten(HAH-Ad) HOLDA high → address driven, min | H−5 ns | H−4 ns | H−3 ns |
| td(XBL-IQL) XBR low → IAQ low | 4H … 6H | 4H … 6H | 4H … 6H |
| td(XBH-IQH) XBR high → IAQ high | 2H … 4H | 2H … 4H | 2H … 4H |
| td(XSL-RDV) read data valid after XSTRB low, max | 40 ns | 29 ns | 25 ns |
| th(XSH-RD) read data hold after XSTRB high, min | 0 ns | 0 ns | 0 ns |
| ten(IQL-RDd) IAQ low → read data driven | 0 … 2H ns | 0 … 2H ns | 0 … 2H ns |
| th(XRL-DZ) XR/W low → data high-impedance | 0 … 15 ns | 0 … 10 ns | 0 … 8 ns |
| th(IQH-DZ) IAQ high → data high-impedance, max | H | H | H |
| ten(D-XRH) data valid from XR/W going high, max | 4 ns | 3 ns | 2 ns |

Timing requirements (external DMA master driving the bus; "X" prefix = externally driven signal):

| Parameter | -40/-57 | -80 | -100 |
|---|---|---|---|
| td(HAL-XBL) HOLDA low → XBR low, min | 0 ns | 0 ns | 0 ns |
| td(IQL-XSL) IAQ low → XSTRB low, min | 0 ns | 0 ns | 0 ns |
| tsu(AV-XSL) X-address valid before XSTRB low, min | 15 ns | 12 ns | 10 ns |
| tsu(DV-XSL) X-data valid before XSTRB low, min | 15 ns | 12 ns | 10 ns |
| th(XSL-D) X-data hold after XSTRB low, min | 15 ns | 12 ns | 10 ns |
| th(XSL-WA) write X-address hold after XSTRB low, min | 15 ns | 12 ns | 10 ns |
| tw(XSL) XSTRB low, min | 45 ns | 40 ns | 35 ns |
| tw(XSH) XSTRB high, min | 45 ns | 40 ns | 35 ns |
| tsu(RW-XSL) R/W valid before XSTRB low, min | 20 ns | 20 ns | 18 ns |
| th(XSH-RA) read X-address hold after XSTRB high, min | 0 ns | 0 ns | 0 ns |

Notes (SPRS030A p. 67): XBR, XR/W and XSTRB must be pulled up with a **10 kΩ resistor** so they sit
inactive-high during the handover between the 'C5x driving them and the external circuit driving them.
Many values "derived from characterization data and not tested." DMA here is **external-master DMA
into on-chip single-access RAM** (IAQ/XBR handshake), not a 'C51 on-chip DMA controller — the C51 has none.

---

## 3. Reset, interrupt and BIO timing (SPRS030A p. 64, Fig. 19)

Columns are 3-group: (-40/-57, LC-40/LC-50) | (-80, LC-80) | (-100). H = 0.5 tc(CO).

| Parameter | -40/-57 | -80 | -100 |
|---|---|---|---|
| tsu(IN-COL) INT1–INT4, NMI setup before CLKOUT1 low, min | 15 ns | 10 ns | 10 ns [UNVERIFIED: extraction shows the -100 value in the same column group as -80; value 10 ns as printed] |
| tsu(RS-COL) RS setup before CLKOUT1 low | 15 ns … 2H−5 ns | 10 ns … 2H−5 ns | 10 ns … 2H−5 ns |
| tsu(RS-CIL) RS setup before X2/CLKIN low, min | 10 ns | 7 ns | 7 ns [UNVERIFIED: -100 column grouping as printed] |
| tsu(BI-COL) BIO setup before CLKOUT1 low, min | 15 ns | 10 ns | 10 ns |
| th(COL-IN) INT/NMI hold after CLKOUT1 low, min | 0 ns | 0 ns | 0 ns |
| th(COL-BI) BIO hold after CLKOUT1 low, min | 0 ns | 0 ns | 0 ns |
| tw(INL)SYN INT/NMI low, synchronous, min | 4H+15 ns | 4H+10 ns | 4H+10 ns |
| tw(INH)SYN INT/NMI high, synchronous, min | 2H+15 ns | 2H+10 ns | 2H+10 ns |
| tw(INL)ASY INT/NMI low, asynchronous, min | 6H+15 ns | 6H+10 ns | 6H+10 ns |
| tw(INH)ASY INT/NMI high, asynchronous, min | 4H+15 ns | 4H+10 ns | 4H+10 ns |
| tw(RSL) RS low, min | 12H (= 6 cycles) | 12H | 12H |
| tw(BIL)SYN BIO low, synchronous, min | 15 ns | 10 ns | 10 ns |
| tw(BIL)ASY BIO low, asynchronous, min | H+15 ns | H+10 ns | H+10 ns |
| td(RSH) RS high → reset vector fetch | 34H (= 17 cycles) | 34H | 34H |

Notes (SPRS030A p. 64): synchronous parameters must be met to use synchronous timings; reset and
interrupts can also operate asynchronously (pulse durations then need an extra half-cycle for internal
synchronisation). If in IDLE2, add **4H** to the interrupt pulse-duration timings.
No power-up sequencing (supply ramp, power-on reset) is specified in pp. 51–86 — RS is the only
reset mechanism described here; the device latches RS and generates an internal reset pulse.
Cross-check: SPRU056D §4.9 (distilled `../c5x_manual/04-program-control.md`) says RS low ≥ 6 clocks and
execution begins 17 clocks after RS high, from address 0h — **identical** to tw(RSL) = 12H and
td(RSH) = 34H above (12H = 6 cycles, 34H = 17 cycles).

## 4. IAQ, IACK, XF and TOUT (SPRS030A pp. 65–66, Fig. 20)

Columns are 3-group: (-40/-57, LC-40/LC-50) | (-80, LC-80) | (-100).

| Parameter | -40/-57 | -80 | -100 |
|---|---|---|---|
| tsu(AV-IQL) address valid before IAQ low, min | H−12 ns | H−9 ns | H−9 ns |
| th(IQL-AV) address hold after IAQ low, min | H−10 ns | H−7 ns | H−7 ns |
| tw(IQL) IAQ low, min | H−10 ns | H−7 ns | H−7 ns |
| tsu(AV-IKL) address valid before IACK low, min | H−12 ns | H−9 ns | H−9 ns |
| th(IKL-AV) address hold after IACK low, min | H−10 ns | H−7 ns | H−7 ns |
| tw(IKL) IACK low, min | H−10 ns | H−7 ns | H−7 ns |
| td(CO-TU) CLKOUT1 falling edge → TOUT | −6 … 6 ns | −6 … 6 ns | −6 … 6 ns |
| tw(TUH) TOUT high, min | 2H−12 ns | 2H−9 ns | 2H−9 ns |
| td(CO-XFV) XF valid after CLKOUT1 | 0 … 12 ns | 0 … 9 ns | 0 … 9 ns |

Notes (SPRS030A p. 65, Note 6): **IAQ is not present on 100-pin packages; IACK is not present on
100-pin and 128-pin packages.** For C51: PZ (100-pin) has **neither IAQ nor IACK**; PQ (132-pin) has
both. IAQ goes low during instruction acquisition, only on the first cycle of the read when wait
states are used; the falling edge latches the valid address (PMST AVIS bit must be 0 for the address
to be valid when the instruction is in on-chip memory). IACK goes low during fetch of the first word
of the interrupt vector; A1–A4 can be decoded at its falling edge to identify the interrupt.
IAQ and IACK are not affected by wait states (SPRS030A p. 66, Fig. 20).

---

## 5. Serial-port timing

All serial sections use H = 0.5 tc(CO); serial-port clock cycle tc(SCK) is fully static
(max unbounded). Column grouping in §§5.1–5.3 is 3-group: (-40/-57, LC-40/LC-50) | (-80, LC-80) | (-100).

### 5.1 Standard serial port — C51 HAS this (SPRS030A pp. 69–71, Figs. 22–24)

Receive (requirements):

| Parameter | -40/-57 | -80 | -100 |
|---|---|---|---|
| tc(SCK) serial-port clock cycle, min | 5.2H | 5.2H | 5.2H |
| tf(SCK), tr(SCK) max | 8 ns | 6 ns | 6 ns |
| tw(SCK) clock low/high, min | 2.1H | 2.1H | 2.1H |
| tsu(FS-CK) FSR setup before CLKR falling edge, min | 10 ns | 7 ns | 6 ns |
| tsu(DR-CK) DR setup before CLKR falling edge, min | 10 ns | 7 ns | 6 ns |
| th(CK-FS) FSR hold after CLKR falling edge, min | 10 ns | 7 ns | 6 ns |
| th(CK-DR) DR hold after CLKR falling edge, min | 10 ns | 7 ns | 6 ns |

Transmit, external clocks and external frames (Fig. 23) — switching (all grades, single values):

| Parameter | Value |
|---|---|
| td(CXH-DXV) DX valid after CLKX high, max | 25 ns |
| tdis(CXH-DX) DX invalid after CLKX high, max | 40 ns |
| th(CXH-DXV) DX valid after CLKX high, min | −5 ns |

Requirements: tc(SCK) min 5.2H; tf/tr(SCK) max 8 / 6 / 6 ns; tw(SCK) min 2.1H;
td(CXH-FXH) FSX high after CLKX high: 2H−8 / 2H−8 / 2H−5 ns [UNVERIFIED: min/max column
assignment unclear in extraction — values as printed per grade group];
th(CXL-FXL) FSX low hold after CLKX low, min 10 / 7 / 6 ns;
th(CXH-FXL) FSX low hold after CLKX high: 2H−8 / 2H−8 / 2H−5 ns (same caveat).
If the FSX pulse misses th(CXH-FXL), the first data bit is driven on DX until the falling edge of
FSX; the transmit-buffer-empty interrupt is generated when th(CXL-FXL) and th(CXH-FXL) are met
(SPRS030A p. 70). Internal clock with external FSX and vice versa are allowable; FSX-to-CLKX
timing depends on the FSX source, CLKX timing on the CLKX source (Note 8, pp. 70–71).

Transmit, internal clocks and internal frames (Fig. 24) — switching:

| Parameter | -40/-57 | -80/-100 |
|---|---|---|
| td(CX-FX) CLKX rising → FSX | −5 … 25 ns | −4 … 18 ns |
| td(CX-DX) CLKX rising → DX, max | 25 ns | 18 ns |
| tdis(CX-DX) CLKX rising → DX invalid, max | 40 ns | 29 ns |
| tc(SCK) cycle time | 8H | 8H |
| tf(SCK), tr(SCK) max | 5 ns | 4 ns |
| tw(SCK) clock low/high, min | 4H−20 ns | 4H−14 ns |
| th(CXH-DXV) DX valid after CLKX high, min | −5 ns | −4 ns |

Internal CLKX frequency: CLKOUT1/4 when MCM = 1 (per SPRU056D §9.7; the datasheet's 8H cycle
time is consistent: tc(SCK) = 8H = 4·tc(CO)). At 20 ns cycle, max internal serial clock is
1/(8·10 ns) = 12.5 MHz; with external clock, min tc(SCK) = 5.2H = 52 ns → ~19.2 MHz at 20 ns cycle.
SPRU056D §9.7 quotes 5M bps at 50 ns / 7.14M bps at 35 ns for the SP — consistent with the
external-clock 5.2H limit at those grades only if the frame overhead is counted; treat the
datasheet numbers above as normative.

### 5.2 TDM-mode serial port — C51 HAS this (SPRS030A pp. 72–73, Figs. 25–26)

Receive (requirements; TFRM values are for external TFRM):

| Parameter | -40/-57 | -80 | -100 |
|---|---|---|---|
| tc(SCK) min | 5.2H | 5.2H | 5.2H |
| tf(SCK), tr(SCK) max | 8 ns | 8 ns | 8 ns |
| tw(SCK) min | 2.1H | 2.1H | 2.1H |
| tsu(TD-TCH) TDAT setup before TCLK rising edge, min | 30 ns | 21 ns | 18 ns |
| th(TCH-TD) TDAT hold after TCLK rising edge, min | −3 ns | −2 ns | −2 ns |
| tsu(TA-TCH) TADD setup before TCLK rising edge, min (first bits only) | 20 ns | 12 ns | 10 ns |
| th(TCH-TA) TADD hold after TCLK rising edge, min | −3 ns | −2 ns | −2 ns |
| tsu(TF-TCH) TFRM setup before TCLK rising edge, min | 10 ns | 10 ns | 10 ns |
| th(TCH-TF) TFRM hold after TCLK rising edge, min | 10 ns | 10 ns | 10 ns |

Transmit (Fig. 26; TFRM values are for internal TFRM):

| Parameter | -40/-57 | -80 | -100 |
|---|---|---|---|
| th(TCH-TDV) TDAT/TADD valid hold after TCLK rising edge, min | 0 ns | 0 ns | 0 ns |
| td(TCH-TFV) TFRM valid after TCLK rising edge | H … 3H+10 ns | H … 3H+7 ns | H … 3H+5 ns [UNVERIFIED: -100 max printed as "3H + 5" in a collapsed column; value as read] |
| td(TC-TDV) TCLK → valid TDAT/TADD, max | 20 ns | 15 ns | 12 ns |
| tc(SCK) min / typ (internal SCK) | 5.2H / 8H | 5.2H / 8H | 5.2H / 8H |
| tf(SCK), tr(SCK) max | 8 ns | 6 ns | 5 ns |
| tw(SCK) min | 2.1H | 2.1H | 2.1H |

Note the asymmetry: TDM RX tf/tr are 8 ns for all three grade groups (p. 72), while TDM TX
tf/tr step 8/6/5 ns (p. 73) — as printed. TFRM can be internal or external; the RX figure shows
external TFRM, the TX figure internal TFRM (SPRS030A pp. 72–73, footnotes).

### 5.3 Buffered serial port (BSP) — C51 does NOT have this (SPRS030A pp. 74–76, Figs. 27–29)

Included for contrast only; BSP is on 'LC56/'C57S/'LC57 (SPRU056D §9.8; datasheet device/pin
tables, chunk A). **Within pp. 51–86 the BSP timing sections carry no device-restriction heading** —
the restriction comes from the datasheet's own Table 1 / pin tables (chunk A) and SPRU056D, not
from these pages. BSP tables are single-column (no speed-grade split), unlike §§5.1–5.2.

Receive (requirements): tc(SCK) min **25 ns**; tf/tr(SCK) max 6 ns; tw(SCK) min 12 ns;
tsu(FS-CK) 2 ns; tsu(DR-CK) 0 ns; th(CK-DR) 15 ns;
th(CK-FS) **[UNVERIFIED — extraction reads "12 tc(SCK)§", garbled; footnote says the first bit is
read when FSR is sampled low by CLKR]** (SPRS030A p. 74).

Transmit, external frames (Fig. 28) — switching: td(CXH-DXV) 5 … 21 ns; tdis(CXH-DX) 5 … 15 ns;
tdis(CXH-DX)PCM max 15 ns; ten(CXH-DX)PCM min 21 ns; th(CXH-DXV) 5 … 20 ns.
Requirements: tc(SCK) min 25 ns; tf/tr max 4 ns; tw(SCK) min 8.5 ns; tsu(FX-CXL) 5 ns;
th(CXL-FX) 5 ns … tc(SCK)−5 (SPRS030A p. 75).

Transmit, internal frame and internal clock (Fig. 29) — switching: td(CXH-FXH), td(CXH-FXL) max
10 ns; td(CXH-DXV) 5 … 10 ns; tdis(CXH-DX) 4 … 8 ns; tdis(CXH-DX)PCM max 10 ns;
ten(CXH-DX)PCM min 16 ns; tc(SCK) 2H … 62H; tf/tr max 4 ns; tw(SCK) min H−4 ns;
th(CXH-DXV) 4 … 8 ns (SPRS030A p. 76).
Timings are given with polarity bits CLKP and FSP = 0 (Notes 9–10, pp. 75–76).
BSP max serial rate (SPRU056D §9.8): CLKOUT1, i.e. 40M bps at 25 ns — vs SP 5.2H limit above.

---

## 6. Host Port Interface (HPI) — NOT on C51 (SPRS030A pp. 77–81, Figs. 30–33)

Heading: "HOST PORT INTERFACE (TMS320C57S, TMS320LC57 ONLY)" (SPRS030A p. 77). **C51 has no HPI.**
Key numbers only, for completeness (single-column, no speed-grade split; H = 0.5 tc(CO);
SAM = shared-access mode, HOM = host-only mode; DS = logical OR of HCS and HDS):

Switching: td(DSL-HDV) DS low → HD valid, max 5 ns; td(HEL-HDV1) DS low → HD valid, first byte
of a subsequent read — case-dependent: SAM with tw(HDS)h < 7H: 7H+20−tw(DSH); SAM with tw(HDS)h > 7H:
20 ns; HOM with tw(HDS)h < 7H: 40−tw(DSH); HOM with tw(HDS)h > 7H: 20 ns
[UNVERIFIED: case formulas reconstructed from collapsed columns; verify against Fig. 30–32
before use]; td(DSL-HDV2) second byte, max 20 ns;
td(DSH-HYH) DS high → HRDY high, max **[UNVERIFIED — no value recovered from extraction]**;
tsu(HDV-HYH) HD valid before HRDY rising edge, min 3H−10 ns;
th(DSH-HDV) HD valid after DS rising edge 0 … 12 ns; td(COH-HYH) CLKOUT1 rising → HRDY high,
max 10 ns; td(DSH-HYL) HDS/HCS high → HRDY low, max 12 ns;
td(COH-HTX) CLKOUT1 rising → HINT change, max 10 ns (SPRS030A p. 77).

Requirements: tsu(HBV-DSL) HAD/HBIL valid before HAS or DS falling edge, min 10 ns;
th(DSL-HBV) hold after, min 10 ns; tsu(HSL-DSL) HAS low before DS falling edge, min 10 ns;
tw(DSL) DS low, min 25 ns; tw(DSH) DS high, min 10 ns;
tc(DSH-DSH) DS rising → next DS rising: 50 ns (with HRDY, or HOM accesses without HRDY);
10H for SAM accesses and HOM active writes to DSPINT/HINT without HRDY;
tsu(HDV-DSH) HD valid before DS rising edge, min 10 ns; th(DSH-HDV) hold after, min 0 ns
(SPRS030A p. 77). Host-only-mode timings apply to HPIC/HPIA reads, BOB writes, and resetting
DSPINT/HINT to 0 in shared-access mode; HRDY does not go low for these accesses.
HINT/SMOD are cleared in reset and set after reset goes high (SPRU056D §9.1.3 — HPI-only detail,
irrelevant to C51).

---

## 7. Mechanical data (SPRS030A pp. 82–86)

Condensed key dimensions only. Full drawings: PQ Fig. p. 82, PBK p. 83, PJ p. 84, PZ p. 85,
PGE p. 86. All linear dimensions in inches (mm) for PQ; millimetres for the rest.
**pdftotext mangles package drawings badly** — body/tip-to-tip pairings below are best-effort
reads of the figure callouts; verify against the PDF drawing before laying out a footprint.

### 7.1 PQ (S-PQFP-G132) — C51 package (p. 82)

| Item | Value |
|---|---|
| Pins / pitch | 132, 0.025 in (0.635 mm) |
| Body, square | 0.800 in (20.32 mm) SQ [as printed; the figure also lists 0.966/0.934 in (24.54/23.72 mm) SQ, 1.090/1.070 in (27.69/27.18 mm) SQ and 1.112/1.088 in (28.25/27.64 mm) SQ — [UNVERIFIED which pair is body vs tip-to-tip; check the drawing] |
| Height, max | 0.180 in (4.57 mm) |
| Lead width | 0.012 / 0.008 in (0.30 / 0.20 mm) |
| Seating-plane standoff | 0.010 in (0.25 mm); lead thickness 0.006 in (0.15 mm) nom |
| JEDEC | MO-069 |
| Thermal | RθJA 35 °C/W, RθJC 8.5 °C/W |

### 7.2 PZ (S-PQFP-G100) — C51 package (p. 85)

| Item | Value |
|---|---|
| Pins / pitch | 100, 0.50 mm |
| Body, square | 14.20 / 13.80 mm SQ |
| Tip-to-tip, square | 16.20 / 15.80 mm SQ |
| Height, max | 1.60 mm |
| Lead width | 0.27 / 0.17 mm |
| Standoff / seating | 1.45 / 1.35 mm; lead thickness 0.08 mm; 0.25 mm gage-plane offset |
| JEDEC | MO-136 |
| Thermal | RθJA 58 °C/W, RθJC 10 °C/W |

Note: the PZ (thin QFP, 1.60 mm max) is the package the Courier modem's C51 is most likely in;
the PQ is the thicker 132-pin bumpered QFP. IAQ/IACK are absent on the 100-pin PZ (§4).

### 7.3 Other packages in these pages — NOT C51

| Package | Pins / pitch | Body | Height max | RθJA / RθJC | Note |
|---|---|---|---|---|---|
| PBK (S-PQFP-G128), p. 83 | 128, 0.40 mm | 14.20/13.80 mm SQ [body; tip-to-tip 16.20/15.80 mm SQ] | 1.60 mm | 58 / 10 °C/W | 128-pin; IACK absent (§4) |
| PJ (R-PQFP-G100), p. 84 | 100, 0.65 mm | 12.35 mm typ [UNVERIFIED: figure callouts 14.20/13.80 and 18.00/17.20, 20.20/19.80, 24.00/23.20 mm are mutually inconsistent in extraction — check drawing] | 3.10 mm | 78 / 13 °C/W | 100-pin QFP, thicker than PZ; not a C51 package per Table 1 |
| PGE (S-PQFP-G144), p. 86 | 144, 0.50 mm | 20.20/19.80 mm SQ [body; tip-to-tip 22.20/21.80 mm SQ] | 1.60 mm | 40 / 9.9 °C/W | 144-pin; not C51 |

---

## 8. What is NOT in pp. 51–86

- No supply-voltage / power-up ramp sequencing, no power-on-reset timing — RS ( §3) is the only
  reset mechanism specified here. (Absolute maxima / recommended operating conditions are in
  earlier pages, outside this chunk.)
- No timer/TOUT period formula, no interrupt-vector cycle counts, no instruction-cycle tables —
  those are SPRU056D territory (`../c5x_manual/07-pipeline.md`, `09a-...md` §9.3).
- No BSP/HPI device-applicability statement inside the BSP timing sections (§5.3) — see §0.
- No C51-specific serial-port pinout in these pages — pinouts are in chunk A/B (Tables 2–4).

## 9. Contradictions vs SPRU056D (distilled `../c5x_manual/`)

Checked against `09a-peripherals-timer-clock-waitstates.md` (§§9.1–9.4), `09b-peripherals-serial-bsp-tdm-hpi.md`
(§§9.7–9.10), `07-pipeline.md`, `04-program-control.md`. No direct contradiction found; three
points of clarification / apparent tension:

1. **Reset timing — agreement, not contradiction.** SPRU056D §4.9: RS low ≥ 6 clocks, execution
   begins 17 clocks after RS high, from 0h. Datasheet: tw(RSL) min 12H (= 6 cycles),
   td(RSH) = 34H (= 17 cycles) to the reset-vector fetch (SPRS030A p. 64). Identical.
   The datasheet adds the setup windows the manual does not give: tsu(RS-COL) 15/10 ns (min) to
   2H−5 ns (max), tsu(RS-CIL) 10/7 ns.
2. **PLL maximum frequency — grade-qualified, not contradictory.** SPRU056D §9.2.2 states a PLL
   maximum of 28.6 MHz "on a 35-ns 'C5x device" (`09a` §9.2.2). The datasheet's PLL tables allow
   tc(CO) min 25 ns (-80) and 20 ns (-100), i.e. PLL operation up to 40/50 MHz on faster grades
   (SPRS030A pp. 55–57). The manual's figure is the -57-grade value; the datasheet extends it
   per grade. For the Courier (C51, presumably 20–50 ns grade), use the datasheet's per-grade row.
3. **External-write cycle count — apparent tension, likely a transcription artefact in the
   distilled manual, not adjudicated here.** Datasheet Fig. 15 Note A: external writes **always**
   require two cycles (SPRS030A p. 61). The distilled manual's Table 9–7 (`09a` §9.4.1) lists
   hardware/software write cycles as "2n+1" with a footnote "n = number of consecutive write
   cycles" — at n = 0 that would read 1 cycle, contradicting the datasheet. The manual's own
   §7.2.4 (`07-pipeline.md`) says external-memory writes take 3 cycles in the bus-conflict case,
   consistent with the datasheet's 3-cycle read-write/read cases. Treat the datasheet's "writes
   always ≥ 2 cycles" as normative; the Table 9–7 "2n+1" formula needs re-checking against
   SPRU056D PDF p. 524 before being relied on.
4. **Interrupt pulse widths — complementary, not contradictory.** Datasheet gives absolute minima
   (tw(INL)SYN 4H+15 / 4H+10 ns etc., +4H in IDLE2, SPRS030A p. 64). The manual (§9.1.2, `09a`)
   describes the same requirement as a 1-1-0-0-0 pattern over five consecutive CLKOUT1 cycles and
   a 4-high/5-low cycle rule in IDLE2. Same constraint, two framings.
5. **READY — agreement.** Datasheet tsu(RY-COH) 10/7/6 ns, sampled only after software wait states
   complete (SPRS030A p. 63). Manual §9.4.1: READY is not asynchronous, setup/hold must be met
   or "significant device malfunction will result" (`09a` §9.4.1). Same rule.
6. **TDM/BSP/HPI device assignment — agreement.** Datasheet Table 1 / pin tables (chunk A) and
   SPRU056D §§9.7–9.10 agree: C51 = SP + TDM, no BSP, no HPI (see §0). One gap, not a
   contradiction: the BSP timing sections in this chunk (pp. 74–76) never state which devices have
   a BSP — an agent reading only pp. 51–86 could wrongly assume the BSP exists on all 'C5x.
   It does not exist on C51.

## 10. Unrecovered / garbled items (explicit)

- BSP RX th(CK-FS): extraction reads "12 tc(SCK)§" — unusable as printed (SPRS030A p. 74).
- HPI td(DSH-HYH) (DS high → HRDY high): no max value recovered (SPRS030A p. 77).
- HPI td(HEL-HDV1) case formulas: reconstructed from collapsed columns; verify against Figs. 30–32
  before use (SPRS030A p. 77).
- Serial TX (external frames) td(CXH-FXH) / th(CXH-FXL) 2H−8 / 2H−5 values: min/max column
  assignment unclear (SPRS030A p. 70).
- Write ten(WEL-BUd) −5/−4 ns: column assignment unclear (SPRS030A p. 60).
- PQ package body vs tip-to-tip dimensions: multiple SQ callouts, pairing unverified (SPRS030A p. 82).
- PJ package dimensions: extraction internally inconsistent; C51-irrelevant (SPRS030A p. 84).
- Reset/interrupt table (p. 64): the -100 column is collapsed with the -80 column in extraction for
  tsu(IN-COL), tsu(RS-CIL), tw(BIL) rows — values shown (10/7/10 ns) are as printed but the
  -80/-100 split is not independently confirmed from this extraction.
- TDM TX td(TCH-TFV) -100 max "3H+5": read from a collapsed column (SPRS030A p. 73).
