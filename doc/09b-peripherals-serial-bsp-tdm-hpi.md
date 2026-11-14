# TMS320C5x Serial Ports, BSP, TDM, HPI — SPRU056D Ch. 9, §§9.7–9.10

**Source (only authority):** `~/workspace/user/files/spru056d.pdf` — SPRU056D, *TMS320C5x User's Guide*, June 1998.
Extraction: `pdftotext -layout`, PDF pp. 532–613 (re-extracted for this file; `/tmp/spru056d-97-910.txt`).
Cross-checks outside §§9.7–9.10, same document only: Table 1–1 (PDF p.39 / printed 1-6), Table 2–1 and §§2.4.5–2.4.8
(PDF pp.51–52 / printed 2-9–2-10), §9.1.3 peripheral reset (PDF p.515 / printed 9-6), Table 9–1 (PDF pp.511–513 / printed 9-2–9-4).

**Scope found:** §9.7 starts **PDF p.532 / printed 9-23** (not PDF p.561 as tasked — p.561 is §9.7.7, Example 9–4).
§9.8 starts PDF p.562 / printed 9-53; §9.9 starts PDF p.583 / printed 9-74; §9.10 starts PDF p.596 / printed 9-87;
chapter ends PDF p.613 / printed 9-104 (Appendix A starts PDF p.614). Ch. 9 printed = PDF − 509 throughout.

**Citation rule used:** every factual claim carries § + table/figure + PDF page / printed page. `INFERENCE` = derived, kept out of
tables. `[UNVERIFIED — …]` = extraction garbled/illegible; no guess made. Contradictions are in §6, both readings recorded.

---

## 0. Per-device verdicts (SP / BSP / TDM / HPI)

| Device | Standard SP | BSP | TDM | HPI | Authority |
|---|---|---|---|---|---|
| 'C50 / 'LC50 | Yes (1) | No | **Yes** (1) | No | Tab. 2–1, PDF p.51 / 2-9; Tab. 1–1 ¶, PDF p.39 / 1-6 |
| **'C51 / 'LC51** | **Yes (1)** | **No** | **Yes (1)** | **No** | Tab. 2–1, PDF p.51 / 2-9; Tab. 1–1 ¶, PDF p.39 / 1-6; §9.7, PDF p.532 / 9-23 |
| 'C52 / 'LC52 | Yes (1) | No | No | No | Tab. 2–1, PDF p.51 / 2-9; Tab. 1–1 (serial = 1), PDF p.39 / 1-6 |
| 'C53 / 'LC53 | Yes (1) | No | **Yes** (1) | No | Tab. 2–1, PDF p.51 / 2-9; Tab. 1–1 ¶, PDF p.39 / 1-6 |
| 'C53S / 'LC53S | **Yes (2)** — two standard SPs | No | **No** | No | Tab. 2–1, PDF p.51 / 2-9 (High-Speed SP = 2, TDM = –); Tab. 1–1 (serial = 2, no ¶), PDF p.39 / 1-6 |
| 'LC56 | Yes (1) | **Yes** (1) | No | No | Tab. 2–1, PDF p.51 / 2-9; §9.8, PDF p.562 / 9-53 |
| 'C57S | Yes (1) | **Yes** (1) | No | **Yes** | Tab. 2–1, PDF p.51 / 2-9; §9.10, PDF p.596 / 9-87 |
| 'LC57 | Yes (1) | **Yes** (1) | No | **Yes** | Tab. 2–1, PDF p.51 / 2-9; §9.10, PDF p.596 / 9-87 |
| 'LC57S | Yes (1) | **Yes** (1) | No | **Yes** — see Contradiction C3 | Tab. 2–1 grouped row 'C57S/'LC57S, HPI = 1, PDF p.51 / 2-9; Tab. 1–1 `64K‖`, PDF p.39 / 1-6 |

**'C51 verdict (the Courier target): SP yes, TDM yes, BSP no, HPI no.** Confirmed by all three sources with no
contradiction: §9.7 (PDF p.532 / 9-23) "The TDM serial port interface is implemented on the 'C50, 'C51, and 'C53
devices"; §9.8 (PDF p.562 / 9-53) BSP "available on the 'LC56, 'LC57, and 'C57S devices" (no 'C51); §9.10
(PDF p.596 / 9-87) HPI "available on the 'LC57 and 'C57S devices" (no 'C51); Table 2–1 'C51/'LC51 row = 1 SP, 1 TDM,
BSP –, HPI – (PDF p.51 / 2-9); Table 1–1 'C51 serial = `2¶` (¶ = includes TDM), parallel = `64K` with no `‖`
(‖ = includes HPI) (PDF p.39 / 1-6). The 'C51's two serial ports are therefore 1× standard SP + 1× TDM port
(the TDM port doubles as a second standard SP in stand-alone mode, §9.9, PDF p.583 / 9-74).

Notes on the table: "High-Speed Serial Port" in Table 2–1 is the standard SP. 'C53S/'LC53S are the only devices
with 2 standard SPs and no TDM — the prose phrase "'C53 devices" in §§9.7/9.9 does **not** include the S variant
(see Contradiction C5). BSP/HPI on 'LC57S: the two device tables include it, the §9.8/§9.10 prose omits it
(see Contradictions C3, C4); tables treated as normative. §2.4.7 (PDF p.52 / 2-10) says BSP is on "'C56 and 'C57
devices" generically; §2.4.8 (PDF p.52 / 2-10) says TDM is on "'C50, 'C51, and 'C53 devices".

---

## 1. §9.7 Serial Port Interface (SP) — PDF pp.532–561 / printed 9-23–9-52

Full-duplex, bidirectional, double-buffered, fully static (works at arbitrarily low clock frequencies)
[§9.7, PDF p.532 / 9-23]. Compatible with industry-standard codecs, A/D converters, other serial systems;
also usable for interprocessor communication [§9.7, PDF p.532 / 9-23]. BSP and TDM ports reset into
standard-SP-compatible mode [§9.7, PDF p.532 / 9-23]; in standard/non-TDM mode they behave as the SP except
where §9.7/§9.8/§9.9 specifically indicate otherwise [§9.7, PDF p.532 / 9-23; §9.8, PDF p.563 / 9-54].

### 1.1 Registers

| Addr (data) | Register | Access | Reset | Function | Ref |
|---|---|---|---|---|---|
| 0020h | DRR | R (W: see §1.2) | Cleared (0) | Data receive register; holds RSR contents for CPU read | Tab. 9–11, §9.7.1, PDF p.533 / 9-24 |
| 0021h | DXR | W (R: any time) | Cleared (0) | Data transmit register; holds data to be loaded into XSR | Tab. 9–11, §9.7.1, PDF p.533 / 9-24 |
| 0022h | SPC | R/W (7 bits R-only) | See §1.3 (XRDY=1, rest 0, INx = pin) | Serial port control register: mode + status | Tab. 9–11, §9.7.1, PDF p.533 / 9-24; §9.7.3, PDF p.536 / 9-27 |
| — | RSR | Not CPU-accessible | — | Receive shift register; shifts in DR, copies to DRR | Tab. 9–11, §9.7.1, PDF p.533 / 9-24 |
| — | XSR | Not CPU-accessible | — | Transmit shift register; shifts out to DX | Tab. 9–11, §9.7.1, PDF p.533 / 9-24 |

Same addresses confirmed in Table 9–1, PDF p.511 / 9-2 (DRR 0020h, DXR 0021h, SPC 0022h).

**Pins** (Table 9–12, §9.7.2, PDF p.535 / 9-26): CLKR receive clock, CLKX transmit clock, DR received data,
DX transmitted data, FSR receive frame sync, FSX transmit frame sync. One-way link needs only DX→DR,
FSX→FSR, CLKX→CLKR (Fig. 9–12, PDF p.535 / 9-26). Block diagram Fig. 9–13, PDF p.536 / 9-27.

### 1.2 DXR/DRR access rules

| Rule | SP | BSP (for contrast; §9.8) | Ref |
|---|---|---|---|
| DXR/DRR read or write any time, in reset or not | Yes | Restricted (next column) | §9.7.1, PDF p.534 / 9-25 |
| DRR | Read/write any time | Read only, except writable when BSP in reset | §9.7.1, PDF p.534 / 9-25; §9.8.1, PDF p.564 / 9-55 |
| DXR | Read/write any time | Writable only when ABU disabled; readable any time | §9.7.1, PDF p.534 / 9-25; §9.8.1, PDF p.564 / 9-55 |
| Write to DRR then serial receive before read | Read may not return written value (HW overwrites DRR) | Same precaution | §9.7.1, PDF p.534 / 9-25 |
| Write to DXR before previous contents sent | Previous contents overwritten and lost | Same | §9.7.1, PDF p.534 / 9-25 |
| DXR/DRR as general-purpose storage | Allowed if port unused; disable TX/RX by tying off input pins or putting port in reset | Same, but set BFSR inactive to prevent a receive | §9.7.1, PDF p.534 / 9-25; §9.8.1, PDF p.564 / 9-55 |

### 1.3 SPC — full bit layout (Figure 9–14, Table 9–13)

Bit order MSB→LSB: 15 Free, 14 Soft, 13 RSRFULL, 12 XSREMPTY, 11 XRDY, 10 RRDY, 9 IN1, 8 IN0, 7 RRST,
6 XRST, 5 TXM, 4 MCM, 3 FSM, 2 FO, 1 DLB, 0 Res [Fig. 9–14 / Tab. 9–13, PDF pp.537–540 / 9-28–9-31].
R/W: bits 15,14,7,6,5,4,3,2,1 R/W; bits 13,12,11,10,9,8 R-only; bit 0 R (reads 0) [Fig. 9–14, PDF p.537 / 9-28;
§9.7.3, PDF p.536 / 9-27: "seven bits read only, nine bits read/write"].

| Bit | Name | R/W | Reset | Function | Ref |
|---|---|---|---|---|---|
| 15 | Free | R/W | 0 | With Soft: serial-port clock state on (emulator) halt. Free=1: clock free-runs regardless of Soft | Tab. 9–13, PDF p.537 / 9-28; Tab. 9–14, PDF p.546 / 9-37 |
| 14 | Soft | R/W | 0 | Free=0: Soft selects emulation mode. Soft=0: clock stops immediately, aborting transmission. Soft=1: clock stops after current transmission completes | Tab. 9–13, PDF p.537 / 9-28; §9.7.3, PDF p.546 / 9-37 |
| 13 | RSRFULL | R | 0 | Receive overrun. SP burst (FSM=1): set only when RSR full + DRR unread + FSR pulse occurs. Continuous (FSM=0) and BSP: set as soon as RSR full + DRR unread. Cleared by: DRR read, RRST=0, device reset. When 1: receiver halts, waits for DRR read, DR data lost; SP preserves RSR contents, BSP loses them | Tab. 9–13, PDF p.537 / 9-28; §9.7.3, PDF p.545 / 9-36 |
| 12 | XSREMPTY | R | 0 | Transmit underflow, active-low (0 = underflow). Set to 0 by: DXR not loaded since last DXR→XSR transfer and XSR empties (transition after last bit shifted out); XRST=0; device reset. Set to 1 by: DXR write (SP), or DXR write + FSX pulse (BSP). When 0: transmitter halts, DX pin high-impedance until next frame sync | Tab. 9–13, PDF p.538 / 9-29; §9.7.3, PDF pp.544–545 / 9-35–9-36 |
| 11 | XRDY | R | **1** | Transmit ready. 0→1 = DXR copied to XSR, DXR ready to reload; generates XINT. Pollable. Set to 1 at reset / XRST=0. SP: generated directly by DXR write. BSP: only after DXR loaded + FSX pulse | Tab. 9–13, PDF p.538 / 9-29; §9.7.3, PDF p.544 / 9-35 |
| 10 | RRDY | R | 0 | Receive ready. 0→1 = RSR copied to DRR, data readable; generates RINT. Pollable. Cleared to 0 at reset / RRST=0 | Tab. 9–13, PDF p.538 / 9-29; §9.7.3, PDF p.544 / 9-35 |
| 9 | IN1 | R | x (pin) | CLKX pin level as bit input. Latency 0.5–1.5 CLKOUT1 cycles from pin change to SPC value | Tab. 9–13, PDF p.538 / 9-29; §9.7.3, PDF p.544 / 9-35 |
| 8 | IN0 | R | x (pin) | CLKR pin level as bit input. Same 0.5–1.5 CLKOUT1 latency | Tab. 9–13, PDF p.538 / 9-29; §9.7.3, PDF p.544 / 9-35 |
| 7 | RRST | R/W | 0 | Receive reset, active-low. 0 = receiver reset/halted; clears RSRFULL and RRDY to 0. 1 = receiver enabled | Tab. 9–13, PDF p.538 / 9-29 |
| 6 | XRST | R/W | 0 | Transmit reset, active-low. 0 = transmitter reset/halted; clears XSREMPTY to 0, sets XRDY to 1. 1 = transmitter enabled. Writing 0 to XRST while XRDY=0 generates XINT | Tab. 9–13, PDF p.539 / 9-30 |
| 5 | TXM | R/W | 0 | FSX direction. 0 = external frame sync (FSX input; transmitter idles until FSX). 1 = internal frame sync (FSX output; pulse generated internally when DXR→XSR transfer occurs, synchronous to CLKX) | Tab. 9–13, PDF p.539 / 9-30 |
| 4 | MCM | R/W | 0 | CLKX source. 0 = CLKX pin input (external clock). 1 = CLKX output, internal clock = CLKOUT1/4 (SP and BSP standard mode; BSP offers other ratios via SPCE, §9.8). CLKR pin is always an input. MCM=1 + DLB=1 also supplies CLKR internally | Tab. 9–13, PDF p.539 / 9-30; §9.7.3, PDF p.542 / 9-33 |
| 3 | FSM | R/W | 0 | Frame sync mode. 0 = continuous (only initial frame sync required; later syncs not required but NOT ignored — mistimed syncs cause errors). 1 = burst (frame sync required for every word) | Tab. 9–13, PDF p.539 / 9-30; §9.7.3, PDF p.542 / 9-33 |
| 2 | FO | R/W | 0 | Format/word length. 0 = 16-bit words. 1 = 8-bit bytes, MSB first. BSP also offers 10-/12-bit via SPCE FE (§9.8) | Tab. 9–13, PDF p.540 / 9-31; §9.7.3, PDF p.541 / 9-32 |
| 1 | DLB | R/W | 0 | Digital loopback. 0 = normal (DR/FSR/CLKR from pins). 1 = DR←DX, FSR←FSX via muxes (Fig. 9–15, PDF p.541 / 9-32); CLKR←CLKX if MCM=1, else CLKR pin (external common clock possible); FSX/DX still appear on pins, FSR/DR do not; internal or external FSX per TXM | Tab. 9–13, PDF p.540 / 9-31; §9.7.3, PDF p.541 / 9-32 |
| 0 | Res | R | 0 | Reserved on SP; always reads 0. Performs a function on the TDM port (TDM enable, §9.9) | Tab. 9–13, PDF p.540 / 9-31 |

INFERENCE (derived from Tab. 9–13 reset column): SPC reset value is 0800h plus the live IN1/IN0 pin levels
in bits 9–8 (only XRDY is reset to 1). Corroborated by §9.1.3 item 5 (PDF p.515 / 9-6): SPC/TSPC/BSPC are loaded
at reset with a value whose upper bits are `10`₂ and whose low bits reflect the clock-pin levels — but the exact
hex pattern there is [UNVERIFIED — extraction garbled, §9.1.3, PDF p.515 / 9-6, rendered "0y00h"]; the
Tab. 9–13 per-bit reset values above are legible and are the basis used.

**Reset / reconfigure procedure (two SPC writes)** [§9.7.3, PDF p.543 / 9-34]: (1) write 0 to XRST and RRST
with the desired configuration in the other bits; (2) write 1 to XRST and RRST, resending the configuration.
Second write takes the port out of reset. TX and RX may be reset individually. XRST=0 or RRST=0 stops that
section (lower power). XRST=RRST=MCM=0 further reduces power (CLKX no longer driven as output).
SP may be taken out of reset at any time, but a frame sync may be missed if XRST/RRST go high during or after
it [§9.7.3, PDF p.543 / 9-34]. In IDLE2, SP operation halts like other 'C5x parts (BSP differs, §9.8.4)
[§9.7.3, PDF p.543 / 9-34].

**Emulation clock (Soft/Free)** — Table 9–14 [§9.7.3, PDF p.546 / 9-37]: Free=0, Soft=0 → immediate stop
(reset values); Free=0, Soft=1 → transmitter stops after completion of word, receiver not affected;
Free=1, Soft=X → free run. Receive side behaves similarly; any option other than immediate stop can let
the receiver keep running and overflow [§9.7.3, PDF p.546 / 9-37].

**FO = 1 (8-bit) detail** [§9.7.3, PDF p.541 / 9-32]: only the lower byte of DXR is transmitted; only the lower
byte of DRR is received data. A whole 16-bit word needs two DXR writes / two DRR reads with appropriate shifts
(upper 8 bits written to DXR are ignored). SP: upper 8 bits of DRR indeterminate on 8-bit reception; BSP:
unused DRR bits are sign-extended. BSP also provides 10- and 12-bit transfers (§9.8).

**IN0/IN1 detail** [§9.7.3, PDF p.544 / 9-35]: CLKR/CLKX pins usable as bit inputs by reading SPC (BIT, BITT,
or PLU instructions); usable even when the serial port is in reset; DRR/DXR usable as general-purpose registers
in reset. Latency 0.5–1.5 CLKOUT1 cycles.

**Clock rate** [§9.7, PDF p.532 / 9-23; §2.4.6, PDF p.52 / 2-10]: SP maximum with internal clocks is CLKOUT1/4
(5M bps at 50 ns, 7.14M bps at 35 ns). BSP maximum is CLKOUT1 (28.6M bps at 35 ns, 40M bps at 25 ns)
[§9.8, PDF p.562 / 9-53]. See Contradiction C1 (Table 9–16 says SP CLKOUT1/2).

### 1.4 Operation — double buffering, ready bits, interrupts

- TX: write DXR → copied to XSR when XSR empty (last word fully shifted out) → XSR shifts to DX; another DXR
  write possible as soon as the DXR→XSR copy completes. On copy completion XRDY 0→1, generating XINT
  [§9.7.2, PDF p.535 / 9-26].
- RX: DR shifted into RSR → copied to DRR → RRDY 0→1, generating RINT [§9.7.2, PDF p.536 / 9-27].
- Polling XRDY/RRDY may substitute for or complement interrupts [§9.7.3, PDF p.544 / 9-35].
  Interrupt details (vectors/masks) are in §4.8 / §9.1.2, cited but not reproduced here
  [§9.7.2, PDF p.535 / 9-26].
- DXR→XSR copy rule (both SP and BSP): occurs only if XSR is empty AND DXR has been loaded since the last
  DXR→XSR transfer. Reloading DXR early overwrites previous DXR contents. Load DXR only when XRDY=1
  (assured by writing only in response to XINT or XRDY polling) unless overwriting is intended
  [§9.7.4, PDF p.547 / 9-38].
- SP vs BSP copy timing: SP — DXR→XSR on the second rising edge of CLKX after DXR is loaded; BSP with
  external FSX — transfer does not occur until an FSX occurs; BSP with internal FSX — transfer and FSX
  generation occur directly after loading DXR. On both, once XSR is loaded XRDY goes high, XINT is generated,
  XSREMPTY is set to 1 [§9.7.4, PDF p.546 / 9-37].
- With external FSX, on the SP XSR is loaded directly as a result of loading DXR; on the BSP XSR is not loaded
  until an FSX occurs [§9.7.3, PDF p.544 / 9-35].

### 1.5 Burst mode (FSM = 1) — §9.7.4, PDF pp.546–552 / printed 9-37–9-43

- Inactivity between packets; each packet marked by a frame-sync pulse on FSX/FSR [§9.7.4, PDF p.546 / 9-37].
- TX, internal frame sync (TXM=1): FSX pulse generated on the second rising edge of CLKX following a DXR write;
  first data bit (MSB first) driven on DX on the next rising edge of CLKX after FSX goes high → ~2-CLKX-cycle
  latency from DXR load to data on the line. Remaining bits shift out on the falling edge of frame sync; after all
  bits, DX goes high-impedance [§9.7.4, PDF pp.547–548 / 9-38–9-39]. Internal FSX pulses are assured to be
  one CLKX cycle long [§9.7.4, PDF p.548 / 9-39]. Fig. 9–16 (burst TX), PDF p.547 / 9-38.
- TX, external frame sync (TXM=0): transmission delayed indefinitely after DXR load until FSX occurs; double
  buffer fills and freezes until frame sync [§9.7.4, PDF p.548 / 9-39]. Long external FSX (>1 CLKX cycle):
  first data bit has variable length (Fig. 9–17, PDF p.548 / 9-39).
- Delayed-FSX difference, SP vs BSP (Figs. 9–18/9–19, PDF p.549 / 9-40): SP — when delayed FSX finally occurs,
  the *first* loaded word (A) is transmitted; B (loaded later) follows at the next FSX. BSP — when delayed FSX
  finally occurs, the *last* loaded word (B) is transmitted (twice, at successive frame syncs, in the figure),
  because the BSP requires a frame sync to move DXR→XSR. In both, writes to DXR before the next delayed FSX
  overwrite B.
- RX: shifting into RSR begins on the falling edge of the CLKR cycle after frame sync has gone low; as the last
  data bit is received, RSR→DRR on the falling edge of CLKR and RRDY goes high, generating RINT (Fig. 9–20,
  PDF p.550 / 9-41). Long FSR (>1 CLKR cycle): reception of all bits, including the first, is delayed until FSR
  goes low (Fig. 9–22, PDF p.551 / 9-42).
- Overrun in burst mode (Fig. 9–21, PDF p.550 / 9-41): if DRR unread from previous receive and another word
  arrives, RSRFULL is set — SP: on the next FSR; BSP: on the falling edge of CLKR during the last bit received.
  SP preserves RSR contents on overrun; BSP loses them. SP data loss can only be avoided by polling RSRFULL
  and reading DRR immediately — feasible only if CLKR is slow vs CLKOUT1 (only half a CLKR cycle available:
  RSRFULL set on falling edge of CLKR during FSR, next data starts on the following rising edge)
  [§9.7.4, PDF p.551 / 9-42; §9.7.6, PDF pp.555–556 / 9-46–9-47].
- Maximum packet frequency: minimum frame-sync period = 8 or 16 CLKX/R cycles (per FO); at maximum rate,
  packets are contiguous with no inactivity, FSX overlaps the last bit of the previous packet (Fig. 9–23 TX,
  Fig. 9–24 RX, PDF p.552 / 9-43). At maximum rate with TXM=1, frame sync becomes essentially redundant —
  this is the bridge to continuous mode [§9.7.4, PDF p.553 / 9-44]. Note: in burst mode at maximum packet
  frequency with FSX as output (TXM=1) frame sync is redundant; with FSX as input (TXM=0) its presence is
  still required [§9.7.3, PDF p.542 / 9-33].

### 1.6 Continuous mode (FSM = 0) — §9.7.5, PDF pp.553–555 / printed 9-44–9-46

- After the initial frame sync, no further frame syncs are required for consecutive packets at maximum packet
  frequency — but later syncs are NOT ignored; mistimed syncs cause errors (§1.7) [§9.7.5, PDF p.553 / 9-44].
- TX: one FSX generated after the first DXR load, none after. Continues as long as DXR is reloaded once per
  transmission. Failing to update DXR halts the port (XSREMPTY asserted, as in burst). Reloading DXR after a
  halt restarts continuous transmission and generates a single FSX (internal frame sync selected)
  [§9.7.5, PDF p.553 / 9-44]. DXR overwrites behave as in burst mode (last written is transmitted)
  [§9.7.5, PDF p.554 / 9-45]. Fig. 9–25, PDF p.554 / 9-45.
- TX, external frame sync (TXM=0): DXR load + FSX pulse initiates continuous transmission [§9.7.5, PDF p.553 / 9-44].
- RX: continues as long as DRR is read every transmission. If DRR is not read by end of the next transfer,
  receiver halts and RSRFULL is set (overrun) [§9.7.5, PDF p.554 / 9-45]. Fig. 9–26, PDF p.555 / 9-46.
- Overrun restart differs: SP — reading DRR restarts continuous mode at the next word/byte boundary after the
  read; no new FSR required (receiver tracks the word boundary while halted). BSP — continuous reception does
  not resume until DRR is read AND an FSR occurs [§9.7.5, PDF p.554 / 9-45].
- Mode switching: continuous mode can be discontinued (burst resumed) ONLY by reconfiguring and resetting the
  serial port. Simply changing the FSM bit during transmit/receive or halt does NOT properly switch to burst mode
  [§9.7.5, PDF pp.553–554 / 9-44–9-45].

### 1.7 Exception conditions — §9.7.6, PDF pp.555–559 / printed 9-46–9-50

| Condition | Burst mode | Continuous mode | Ref |
|---|---|---|---|
| RX overrun (RSRFULL=1) | Receiver halts until DRR read; further data may be lost. SP: RSR preserved, RSRFULL set on next FSR. BSP: RSR lost, RSRFULL set on last valid bit; reading DRR before next FSR lets later transfers proceed | Error; RX section halts. SP: DRR read resumes at next word boundary, no FSR needed. BSP: DRR read + FSR needed to resume (also re-establishes bit alignment) | §9.7.6, PDF pp.555–556, 558 / 9-46–9-47, 9-49 |
| TX underflow (XSREMPTY=0) | Exception, but NOT normally considered an error. Transmitter halts, DX high-Z until next FSX. If XSREMPTY active and FSX occurs, old DXR data is shifted out | IS an error (no data transmitted). TX section halts; corrected by writing DXR. If XSREMPTY active and external FSX occurs, previous DXR data is transmitted as in burst mode | §9.7.6, PDF pp.557–559 / 9-48–9-50; §9.7.3, PDF p.545 / 9-36 |
| Frame sync during RX | Present receive aborted, new receive begins; RSR data lost, DRR data NOT lost (no RSR→DRR copy). Fig. 9–27 (SP), Fig. 9–28 (BSP), PDF p.556 / 9-47. If RSRFULL already set, FSR pulse is ignored | Receive aborted, one packet lost (frame sync resets the RSR bit counter); data on DR shifts in again from first bit. Fig. 9–30, PDF p.558 / 9-49. FSR after DRR read cleared RSRFULL but before next word boundary also aborts | §9.7.6, PDF pp.556, 558 / 9-47, 9-49 |
| Frame sync during TX | Transmit in progress + FSX → transmission aborted, XSR data lost; DXR contents at that moment are copied to XSR and transmitted. XINT generated only if DXR was written since last transmit. FSX with no transmit in progress + DXR reloaded since last transmit → DXR→XSR copy + XINT occur at FSX only on BSP (on SP they already occurred at DXR reload). Fig. 9–29, PDF p.557 / 9-48 | Same abort/loss rule; new transmit cycle initiated, transfers continue if DXR updated once per transmission. Fig. 9–31, PDF p.559 / 9-50 | §9.7.6, PDF pp.557, 559 / 9-48, 9-50 |
| Extraneous FSX in continuous TX | — | Current transfer aborted, XSR data lost, one packet lost, new continuous transmit initiated | §9.7.5, PDF p.554 / 9-45; §9.7.6, PDF p.559 / 9-50 |
| FSR during continuous RX | — | Abort, one packet lost, new receive cycle begins (§1.6) | §9.7.5, PDF p.555 / 9-46 |

Flowchart figures: Fig. 9–27 SP RX burst, Fig. 9–28 BSP RX burst (PDF p.556 / 9-47); Fig. 9–29 SP/BSP TX burst
(PDF p.557 / 9-48); Fig. 9–30 SP/BSP RX continuous (PDF p.558 / 9-49); Fig. 9–31 SP/BSP TX continuous
(PDF p.559 / 9-50).

### 1.8 Worked examples — §9.7.7, PDF pp.559–561 / printed 9-50–9-52

One-way transmit of an arithmetic sequence, memory block 9000h–B000h, DP=0, ARP=7, device 0 waits in a BIO
loop for XF ready-to-receive from device 1 [§9.7.7, PDF p.559 / 9-50].

- Example 9–3 (device 0, TX; PDF p.560 / 9-51): `SPLK #0038h, SPC` = TXM=MCM=FSM=1, XRST=RRST=0 (in reset);
  `SPLK #00F8h, SPC` = same + XRST=RRST=1 (out of reset). IMR `#020h` = XINT only; first value 0 written to DXR.
- Example 9–4 (device 1, RX; PDF p.561 / 9-52): `SPLK #0008h, SPC` = FSM=1, TXM=MCM=0, in reset;
  `SPLK #00C8h, SPC` = same + XRST=RRST=1. IMR `#010h` = RINT only; `CLRC XF` signals ready-to-receive;
  RINT ISR reads DRR into the block. (Decodes above are INFERENCE from Tab. 9–13 bit positions; the SPC
  values and comments are verbatim from the manual.)

---

## 2. §9.8 Buffered Serial Port (BSP) — PDF pp.562–582 / printed 9-53–9-73

Full-duplex, double-buffered serial port + autobuffering unit (ABU) (Fig. 9–32, PDF p.563 / 9-54).
The SP section is an enhanced version of the standard SP as on 'C50/'C51/'C52/'C53; the ABU lets the SP section
read/write 'C5x internal memory independent of the CPU [§9.8, PDF p.562 / 9-53]. Available on 'LC56, 'LC57,
'C57S per §9.8 prose (PDF p.562 / 9-53) — plus 'LC57S per Tables 1–1/2–1 (see §0, Contradiction C4).
Transfers in 8-, 10-, 12-, or 16-bit packets; programmable-frequency serial clock; programmable frame-sync and
clock polarity; PCM transmit mode [§9.8, PDF p.562 / 9-53]. Maximum operating frequency CLKOUT1
(28.6M bps at 35 ns, 40M bps at 25 ns) [§9.8, PDF p.562 / 9-53]. BSP pins are prefixed B- (BCLKX, BFSX, BDX,
BDR, BCLKR, BFSR) [§9.8, Fig. 9–32, PDF p.563 / 9-54]. BSP resets to standard-SP-compatible mode
[§9.7, PDF p.532 / 9-23]. Standard-mode operation is a superset of SP operation — study §9.7 first
[§9.8, PDF p.563 / 9-54].

### 2.1 BSP registers

| Addr (data) | Register | Function | Ref |
|---|---|---|---|
| 0030h | BDRR | 16-bit BSP data receive register (cf. DRR) | Tab. 9–15, §9.8.1, PDF p.564 / 9-55 |
| 0031h | BDXR | 16-bit BSP data transmit register (cf. DXR) | Tab. 9–15, §9.8.1, PDF p.564 / 9-55 |
| 0032h | BSPC | 16-bit BSP control register (cf. SPC; same bit layout, Tab. 9–13) | Tab. 9–15, §9.8.1, PDF p.564 / 9-55 |
| 0033h | SPCE | 16-bit BSP control extension register (enhanced features + ABU control) | Tab. 9–15, §9.8.1, PDF p.564 / 9-55 |
| — | BRSR | BSP receive shift register, not CPU-accessible (cf. RSR) | Tab. 9–15, §9.8.1, PDF p.564 / 9-55 |
| — | BXSR | BSP transmit shift register, not CPU-accessible (cf. XSR) | Tab. 9–15, §9.8.1, PDF p.564 / 9-55 |
| 0034h | AXR | 11-bit ABU address transmit register | Tab. 9–19, §9.8.2, PDF p.569 / 9-60 |
| 0035h | BKX | 11-bit ABU transmit buffer size register | Tab. 9–19, §9.8.2, PDF p.569 / 9-60 |
| 0036h | ARR | 11-bit ABU address receive register | Tab. 9–19, §9.8.2, PDF p.569 / 9-60 |
| 0037h | BKR | 11-bit ABU receive buffer size register | Tab. 9–19, §9.8.2, PDF p.569 / 9-60 |

Addresses confirmed in Table 9–1, PDF pp.512–513 / 9-3–9-4 (0030h TRCV/BDRR, 0031h TDXR/BDXR,
0032h TSPC/BSPC, 0033h TCSR/SPCE, 0034h TRTA/AXR, 0035h TRAD/BKX, 0036h ARR, 0037h BKR).
Note the 0030h–0037h block is shared (by address) between TDM registers on TDM devices and BSP registers
on BSP devices — different devices, no conflict. SPCE is at 0033h in both Table 9–15 and Table 9–19
[§9.8.1, PDF p.564 / 9-55; §9.8.2, PDF p.569 / 9-60]. AXR/BKX/ARR/BKR are 11-bit, read as 16-bit words with the
5 MSBs read as 0 and contents right-justified in the low 11 bits; if autobuffering is unused they may be used
for general-purpose 11-bit storage [§9.8.2, PDF p.570 / 9-61].

**Access limits (ABU enabled):** BDRR readable only, BDXR writable only, when the corresponding ABU section
is enabled; BDRR writable only when BSP is in reset; BDXR readable any time [§9.8.1, PDF p.564 / 9-55;
§9.8.2, PDF p.570 / 9-61]. When ABU is disabled for a direction, that section operates in standard mode and
its ABU portion is transparent [§9.8.2, PDF p.570 / 9-61]. BDXR/BDRR usable as general-purpose registers when
the port is unused, with BFSR set inactive to prevent a spurious receive [§9.8.1, PDF p.564 / 9-55].

**Interrupts:** in standard mode, per-word WXINT/WRINT are sent to the CPU as XINT/RINT [§9.8, PDF p.562 / 9-53].
In autobuffering mode, per-word interrupts are NOT generated; XINT/RINT are generated only when a half-buffer
(or bottom-of-buffer) boundary is crossed [§9.8, PDF p.562 / 9-53; §9.8.2.2, PDF p.577 / 9-68].

### 2.2 SP vs BSP differences in standard mode — Table 9–16

| Condition | SP | BSP | Ref |
|---|---|---|---|
| RSRFULL set | RSR full, then an FSR occurs (except continuous mode: as soon as RSR full) | As soon as BRSR is full | Tab. 9–16, §9.8.1.1, PDF p.565 / 9-56 |
| Data in RSR on overrun | Preserved | Not preserved (lost) | Tab. 9–16, PDF p.565 / 9-56 |
| Continuous-mode RX restart after overrun | Restarts as soon as DRR read | Restarts only after BDRR read AND a BFSR occurs | Tab. 9–16, PDF p.565 / 9-56 |
| Sign extension in DRR on 8-/10-/12-bit transfers | No (upper bits indeterminate) | Yes | Tab. 9–16, PDF p.565 / 9-56 |
| XSR load, XSREMPTY clear, XRDY/XINT generation | When DXR is loaded | When a BFSX occurs after BDXR is loaded | Tab. 9–16, PDF p.565 / 9-56 |
| Program access to DXR/DRR | Read/write any time (with §1.2 cautions) | BDRR read-only / BDXR write-only when ABU enabled; BDRR writable only in reset; BDXR readable any time | Tab. 9–16, PDF p.565 / 9-56 |
| Maximum serial port clock rate | CLKOUT1/2 | CLKOUT1 | Tab. 9–16, PDF p.565 / 9-56 — see Contradiction C1 |
| Initialization timing (exit reset vs frame sync) | Any time (frame sync may be ignored if XRST/RRST go high during/after it) | Must precede FSX timing by 1 CLKOUT1 cycle (standard mode) / 6 CLKOUT1 cycles (autobuffering) — §2.5 | Tab. 9–16, PDF p.566 / 9-57 |
| Operates in IDLE2 | No | Yes (external clock; §2.6) | Tab. 9–16, PDF p.566 / 9-57 |

### 2.3 Enhanced BSP features — SPCE serial-port control bits (bits 9–0)

SPCE reset value is **3** (0003h: CLKDV=3, all other bits 0) → standard-mode operation compatible with the SP
[§9.8.1.2, PDF p.566 / 9-57; §9.8.2.1, PDF p.572 / 9-63]. Bits 15–10 are ABU control (§2.4); bits 9–0 are
serial-port control (Fig. 9–33, PDF p.566 / 9-57; Table 9–17, PDF pp.567–568 / 9-58–9-59). All SPCE bits R/W
unless noted [Fig. 9–33, PDF p.566 / 9-57].

| SPCE bit | Name | Reset | Function | Ref |
|---|---|---|---|---|
| 9 | PCM | 0 | Pulse-code modulation mode; TX only. PCM=1: BDXR transmitted only if its MSB is 0; if MSB is 1, BDXR is not transmitted and BDX is high-impedance during the transmission period. BDXR→BXSR transfer unaffected by PCM | Tab. 9–17, PDF p.567 / 9-58 |
| 8 | FIG | 0 | Frame ignore; operates only in TX continuous mode with external frame and in RX continuous mode. FIG=0: frame sync pulses after the first restart the transfer. FIG=1: frame sync pulses after the first are ignored | Tab. 9–17, PDF p.567 / 9-58 |
| 7 | FE | 0 | Format extension; with FO (BSPC bit 2) sets word length (Table 9–18, §2.3.1) | Tab. 9–17, PDF p.567 / 9-58 |
| 6 | CLKP | 0 | Clock polarity. 0: RX samples on BCLKR falling edge, TX sends on BCLKX rising edge. 1: RX samples on BCLKR rising edge, TX sends on BCLKX falling edge | Tab. 9–17, PDF p.567 / 9-58 |
| 5 | FSP | 0 | Frame-sync polarity. 0: BFSX/BFSR active high. 1: active low | Tab. 9–17, PDF p.568 / 9-59 |
| 4–0 | CLKDV | 00011b (3) | Internal TX clock division. MCM=1 (BSPC): CLKX frequency = CLKOUT1/(CLKDV+1); range 0–31. CLKDV odd or 0 → 50% duty cycle. CLKDV even (=2p): CLKP=0 → high p+1 cycles, low p cycles; CLKP=1 → high p cycles, low p+1 cycles | Tab. 9–17, PDF p.568 / 9-59 |

#### 2.3.1 Word length — Table 9–18 (PDF p.568 / 9-59)

| FO (BSPC bit 2) | FE (SPCE bit 7) | Word length |
|---|---|---|
| 0 | 0 | 16-bit (reset values) |
| 0 | 1 | 10-bit |
| 1 | 0 | 8-bit |
| 1 | 1 | 12-bit |

For 8-/10-/12-bit words, received words are right-justified and the sign bit extended to 16 bits; words to
transmit must be right-justified [Tab. 9–17, PDF p.567 / 9-58].

**FIG use** [§9.8.1.2, PDF p.568 / 9-59]: FIG=1 lets continuous 16-bit transfers run where frame syncs occur
every 8/10/12 bits, packing sub-16-bit transfers into single 16-bit memory words (e.g. two received bytes into
one word) instead of one memory word per sub-word transfer; saves buffer size and CPU overhead in both
autobuffered and standard mode. Fig. 9–34 (TX continuous, external frame, FIG=1, 16-bit format), PDF p.569 / 9-60.

### 2.4 ABU — control bits (SPCE bits 15–10, "ABUC")

Figure 9–36, PDF p.572 / 9-63; Table 9–20, PDF pp.573–574 / 9-64–9-65. SPCE reset value 3 (ABU bits all 0)
[§9.8.2.1, PDF p.572 / 9-63].

| SPCE bit | Name | R/W | Reset | Function | Ref |
|---|---|---|---|---|---|
| 15 | HALTR | R/W | 0 | RX autodisable. 0: autobuffering continues past half-buffer. 1: halted when current half of RX buffer received; BRE cleared to 0, port continues in standard mode | Tab. 9–20, PDF p.573 / 9-64 |
| 14 | RH | R | 0 | RX buffer half received. 0: first half filled, receptions now placing data in second half. 1: second half filled, receptions now in first half. Read RH when RINT occurs to identify which boundary was crossed | Tab. 9–20, PDF p.573 / 9-64 |
| 13 | BRE | R/W | 0 | Autobuffering RX enable. 0: disabled, standard mode. 1: enabled for receiver | Tab. 9–20, PDF p.573 / 9-64 |
| 12 | HALTX | R/W | 0 | TX autodisable. 0: continues past half-buffer. 1: halted when current half of TX buffer transmitted; BXE cleared to 0, port continues in standard mode | Tab. 9–20, PDF p.573 / 9-64 |
| 11 | XH | R | 0 | TX buffer half transmitted. 0: first half transmitted, transmissions now taking data from second half. 1: second half transmitted, now taking from first half. Read XH when XINT occurs | Tab. 9–20, PDF p.574 / 9-65 |
| 10 | BXE | R/W | 0 | Autobuffering TX enable. 0: disabled, standard mode. 1: enabled for transmitter | Tab. 9–20, PDF p.574 / 9-65 |

TX and RX ABU sections enable separately [§9.8.2, PDF p.570 / 9-61]. Burst or continuous mode may be used
with autobuffering; burst mode with internal frame sync effectively results in continuous transmission, FSX
generated by the BSP at the start of each transmission [§9.8.2, PDF p.571 / 9-62]. BSPC/SPCE control and status
bits function in autobuffering mode as in standard mode [§9.8.2, PDF p.569 / 9-60].

### 2.5 ABU operation — memory, circular addressing, process

**ABU memory** [§9.8.2, PDF p.572 / 9-63]: a 2K-word block of single-access memory, configurable as data,
program, or both; the ONLY block in which autobuffering can occur; usable by the CPU as general-purpose
storage. Base address varies by device. Located at **800h–FFFh in data memory** or **8000h–87FFh in program
memory**, as specified by the RAM and OVLY control bits. (INFERENCE: this is the same 2K block the HPI uses
on 'C57 devices at different addresses — §9.10 gives HPI RAM at 1000h–17FFh data / 8800h–8FFFh program;
the manual does not state the ABU and HPI blocks coincide or conflict; do not assume.)

- CPU vs ABU conflict on the 2K block: ABU has priority; CPU access delayed by one cycle. Worst case: a CPU
  access delayed one cycle per ABU word transferred [§9.8.2, PDF p.572 / 9-63].
- Simultaneous TX + RX requests: TX takes priority; RX memory access delayed by a wait state, then performed
  after TX access completes [§9.8.2, PDF p.572 / 9-63].
- External DMA in the 2K ABU block is possible only when autobuffering is disabled [§9.8.2, PDF p.572 / 9-63].
- With ROM protection enabled, the 2K ABU block cannot be mapped to program memory (§8.2.4)
  [§9.8.2, PDF p.572 / 9-63].

**Circular addressing** [§9.8.2.2, PDF pp.575–577 / 9-66–9-68; Fig. 9–37, PDF p.576 / 9-67]:

- Per direction, a BK (size) + AR (address) register pair fully specifies the buffer top/bottom. Init: load BK
  with the EXACT buffer size (not size−1); load AR with base address within the 2K block plus initial starting
  offset (often 0 = top of buffer, but any point in range is allowed).
- Buffer alignment: a buffer must start on an N-bit boundary (N low address bits 0), where the modulus is the
  smallest power of two strictly greater than BK — verified by the worked example: BKX=5 → start at a multiple
  of 8 (0x0000, 0x0008, 0x0010, …); BKR=8 → start at a multiple of 16 (0x0000, 0x0010, 0x0020, …)
  [§9.8.2.2, PDF p.576 / 9-67]. [UNVERIFIED — the sentence defining N, §9.8.2.2, PDF p.575 / 9-66, is garbled
  in extraction (superscripts lost, rendered "2N > BK"); the alignment rule above is taken from the Fig. 9–38
  example, which is legible and self-consistent, and is treated as normative.]
- Top-of-buffer (TBA) = ARH concatenated with zero low bits; bottom-of-buffer (BBA) = ARH concatenated with
  BKL−1; current address = full AR contents. First half = ARH|0…0 to ARH|[(BKL>>1)−1]; second half =
  ARH|(BKL>>1) to ARH|(BKL−1) [§9.8.2.2, PDF p.575 / 9-66]. (The printed "N+1 least significant 0 bits" for
  TBA is reproduced as printed; see the [UNVERIFIED] note above — do not recompute TBA from it.)
- Minimum block size 2; maximum 2047. Any buffer of 1024–2047 words must start at relative address 0x0000
  of the 2K block [§9.8.2.2, PDF p.576 / 9-67].
- Mis-loaded AR (outside the BK-defined range): accesses proceed from the loaded location anyway, AR
  increments until it reaches the next permitted buffer-start address, then correct circular operation resumes
  with the new AR as buffer start — and the stray accesses may corrupt memory locations
  [§9.8.2.2, PDF pp.576–577 / 9-67–9-68]. Example: BKX=5 buffer at 0x0008, AXR=0x000D (invalid for modulo-5)
  → accesses run and AXR increments to 0x0010, which then becomes the TX buffer start — colliding with the
  RX buffer in the example [§9.8.2.2, PDF p.577 / 9-68].
- TX and RX buffers may be independent, overlapping, or the same area (TX from a buffer while RX into the same
  buffer is allowed) [§9.8.2.2, PDF p.574 / 9-65]. Fig. 9–38 mapping example, PDF p.577 / 9-68.

**Autobuffering process** [§9.8.2.2, PDF pp.574, 577–578 / 9-65, 9-68–9-69]: activated on request from the
serial port when XRDY or RRDY goes high. Sequence per transfer: (1) ABU performs the memory access to the
buffer; (2) AR incremented, or wrapped to top-of-buffer if bottom reached; (3) generate XINT or RINT and update
XH/RH if a half-buffer or bottom-of-buffer boundary was crossed; (4) autodisable the ABU if selected and a
half/bottom boundary was crossed.

**Autodisable (HALTX/HALTR = 1)** [§9.8.2.2, PDF p.578 / 9-69]: at the next half (first or second) buffer
boundary, BXE/BRE is cleared, autobuffering stops generating requests. TX: current XSR contents and the last
DXR value still finish transmitting (already initiated) — delay between boundary crossing and actual stop;
poll XRDY=1 AND XSREMPTY=0 to know transmission has actually ended. RX: after the boundary, later receptions
may be lost unless software starts servicing receive interrupts, since BDRR is no longer auto-read (standard-mode
overrun rules, §1.7, then apply).

### 2.6 BSP initialization timing and software init

- Fully static design: serial clocks need not run between transfers or before init; FSX/FSR may occur
  simultaneously with CLKX/CLKR starting [§9.8.3.1, PDF pp.578–579 / 9-69–9-70].
- SP: exit reset any time vs FSX/FSR (frame sync may be ignored if XRST/RRST go high during/after it)
  [§9.8.3.1, PDF p.579 / 9-70].
- BSP standard mode (RX, and TX with external frame sync TXM=0): exit reset at least **1 CLKOUT1 cycle +
  1/2 serial-port clock cycle** before the clock edge that detects the active frame sync (Fig. 9–39,
  PDF p.579 / 9-70). TX with internal clock + internal frame sync is exempt (frame sync auto-generated after
  XRST set to 1 when BDXR is loaded); with external clock + internal frame sync, frame-sync generation may be
  delayed by XRST-clear timing vs the clock [§9.8.3.1, PDF p.579 / 9-70].
- BSP autobuffering mode (RX, and TX with external frame sync): exit reset at least **6 CLKOUT1 cycles +
  1/2 serial-port clock cycle** before the detecting clock edge (ABU activation delay) (Fig. 9–40,
  PDF p.580 / 9-71). Same internal-clock/frame exemptions. See Contradiction C2: the §9.8.3.1 body text
  misprints this case as "(TXM = 1)"; Fig. 9–40's caption gives (TXM = 0), which is correct per Tab. 9–13.
- Software init, standard mode: same steps as SP (§1.3 two-write reset) plus initialise SPCE for enhanced
  features [§9.8.3.2, PDF pp.580–581 / 9-71–9-72]. Autobuffering mode: same, plus initialise ABU registers
  [§9.8.3.2, PDF p.581 / 9-72]. TX and RX sections may be initialised together or separately; examples assume
  DP=0, INTM=1 on entry, interrupts (or IFR polling) service the ABU interrupts; the XINT/RINT used are those
  the BSP occupies on 'C56/'C57 — other BSP devices may use different interrupts, consult device documentation
  [§9.8.3.2, PDF p.581 / 9-72].
- Example 9–5 (TX, burst, external frame + external clock, 10-bit; PDF p.581 / 9-72): IMR `#00080h` (XINT);
  `SPLK #00008h, BSPC` (FSM=1, XRST=0); `SPLK #01480h, SPCE` (HALTX=1, BXE=1, FE=1 → FO=0/FE=1 = 10-bit);
  `SPLK #XTOP, AXR`; `SPLK #XSIZE, BKX`; clear IFR XINT; `OPL #00040h, BSPC` (XRST=1, start TX).
  HALTX=1 halts transmission at half-buffer. (SPCE decode is INFERENCE from Tabs. 9–17/9–20.)
- Example 9–6 (RX, continuous, 16-bit, FIG=1; PDF p.582 / 9-73): IMR `#00040h` (RINT);
  `SPLK #00000h, BSPC` (reset); `SPLK #02160h, SPCE` (BRE=1, FIG=1, CLKP=1, FSP=1 → low-true frame/clock,
  16-bit, frame-ignore packs two received bytes per word); `SPLK #RTOP, ARR`; `SPLK #RSIZE, BKR`;
  clear IFR RINT; `OPL #0080h, BSPC` (RRST=1, start RX). (Decode INFERENCE as above.)

### 2.7 BSP power-down behaviour — §9.8.4, PDF p.582 / 9-73

- Power-down invoked by IDLE/IDLE2 or HOLD low with HM=1. BSP (like timer and SP) can take the CPU out of
  IDLE via XINT or RINT.
- IDLE or HOLD: BSP continues to operate, as does the SP.
- **IDLE2: unlike the SP and other peripherals, which stop, the BSP can still operate.** Standard mode with
  external clock + external frame sync: port keeps operating; XINT/RINT takes the device out of IDLE2 if
  INTM=0 before IDLE2 executes. With internal clock and/or frame sync, the BSP remains in IDLE2 until the CPU
  resumes.
- IDLE2 + autobuffering, external clock + frame sync: a TX/RX event turns the internal BSP clock on only for
  the cycles needed for the DXR/DRR↔memory transfer, then off automatically (device stays in IDLE2). The
  device is woken from IDLE2 by the ABU XINT/RINT when a buffer is halfway or entirely emptied/filled, if
  INTM=0 before IDLE2 executes.

---

## 3. §9.9 Time-Division Multiplexed (TDM) Serial Port — PDF pp.583–595 / printed 9-74–9-86

Communicate serially with up to seven other devices; optimised for multiprocessing [§9.9, PDF p.583 / 9-74].
Superset of the §9.7 serial port: TSPC bit 0 (TDM) selects multiprocessing mode (TDM=1) or stand-alone mode
(TDM=0, operates as §9.7 standard SP) [§9.9, PDF p.583 / 9-74; §9.9.2, PDF p.584 / 9-75]. Port can be shut down
for low power via XRST/RRST as in §9.7 [§9.9, PDF p.583 / 9-74]. Eight TDM channels; which device transmits
and which receive(s) per channel are independently specified [§9.9.1, PDF p.583 / 9-74].
Devices: 'C50, 'C51, 'C53 (and 'LC50/'LC51/'LC53) — NOT 'C53S/'LC53S (see §0, Contradiction C5).
Fig. 9–41 (TDM scheme, 4-channel illustration), PDF p.583 / 9-74.

### 3.1 TDM registers

| Addr (data) | Register | Function | Ref |
|---|---|---|---|
| 0030h | TRCV | 16-bit TDM data receive register (cf. DRR) | Tab. 9–21, §9.9.2, PDF p.584 / 9-75 |
| 0031h | TDXR | 16-bit TDM data transmit register (cf. DXR) | Tab. 9–21, §9.9.2, PDF p.584 / 9-75 |
| 0032h | TSPC | 16-bit TDM serial port control register; identical to SPC except bit 0 = TDM enable (SPC bit 0 is reserved) | Tab. 9–21, §9.9.2, PDF p.584 / 9-75 |
| 0033h | TCSR | 16-bit TDM channel select register; specifies slot(s) in which this device transmits | Tab. 9–21, §9.9.2, PDF p.584 / 9-75 |
| 0034h | TRTA | 16-bit TDM receive/transmit address register; low byte RA7–RA0 = receive address, high byte TA7–TA0 = transmit address | Tab. 9–21, §9.9.2, PDF p.584 / 9-75 |
| 0035h | TRAD | 16-bit TDM receive address register; status of the TADD line | Tab. 9–21, §9.9.2, PDF p.584 / 9-75 |
| — | TRSR | TDM data receive shift register, not CPU-accessible (cf. RSR) | Tab. 9–21, §9.9.2, PDF p.585 / 9-76 |
| — | TXSR | TDM data transmit shift register, not CPU-accessible (cf. XSR) | Tab. 9–21, §9.9.2, PDF p.585 / 9-76 |

Addresses confirmed in Table 9–1, PDF p.512 / 9-3 (0030h–0035h). TRCV/TDXR have the same functions as
DRR/DXR; TRSR/TXSR the same as RSR/XSR [§9.9.2, PDF pp.584–585 / 9-75–9-76]. For all other TSPC bits, see
§9.7 / Tab. 9–13 [§9.9.3, PDF p.586 / 9-77].

**TSPC in TDM mode (TDM=1)** [§9.9.3, PDF p.587 / 9-78]: DLB and FO bits are hard-configured to 0 (no digital
loopback; fixed 16-bit word length — a different loopback is shown in §9.9.6). FSM value does not affect the
port. Underflow/overrun flag states are indeterminate (see §3.4). TSPC changes take effect on completion of
channel 7 of the current frame — the TSPC value cannot be changed for the current frame; changes apply from
the next frame. [UNVERIFIED — the TSPC bit-position diagram, Fig. 9–43, PDF p.587 / 9-78, is garbled in
extraction; the statements in this paragraph are from the legible body text on the same page, not the figure.
The figure does show TCSR bits 7–0 = CH7–CH0, TRTA bits 15–8 = TA7–TA0 / 7–0 = RA7–RA0, TRAD bits 13–11 =
X2–X0, 10–8 = S2–S0, 7–0 = A7–A0, consistent with the body text below.]

### 3.2 Bus, pins, and addressing

- Four-wire bus (Fig. 9–42, PDF p.585 / 9-76): TCLK (clock), TFRM (frame), TDAT (data, bidirectional),
  TADD (address, bidirectional). Up to eight devices on the bus. Device pins: TDX+TDR tied externally to form
  TDAT; TFSX→TFRM, TFSR→TADD (this makes the port easy to use in standard mode); TCLKX+TCLKR tied
  externally to form TCLK [§9.9.3, PDF pp.585–586 / 9-76–9-77].
- Only one device may drive TDAT/TADD in a given slot; all others must be high-impedance in that slot
  (achieved by correct TCSR/TRTA programming). All devices (including the transmitter) sample TDAT/TADD
  each slot to decide whether the transmission is valid data for them [§9.9.3, PDF p.586 / 9-77].
- TCLK and TFRM are each generated by only one device (typically the same device); the manual avoids the word
  "master". All other devices use them as inputs. TCSR must be set to prevent slot contention
  [§9.9.3, PDF p.586 / 9-77].
- Clock/frame source: MCM=1 in a device's TSPC makes it the TCLK source (TCLKX output; TCLK = CLKOUT1/4);
  TXM=1 makes it the TFRM source. No more than one device may have MCM or TXM set to 1 at any time;
  normally set once at system initialisation. External TCLK (MCM=0 on all) and external TFRM (TXM=0) are
  possible; external TFRM must meet TDM receive timing vs TCLK [§9.9.3, PDF p.587 / 9-78].

**Channel select — TCSR** [§9.9.3, PDF pp.587–588 / 9-78–9-79]: bit n (0–7) = 1 sets the transmitter active
during time slot n. A device may transmit in more than one slot. **No more than one device may transmit during
the same slot; devices do not check for bus contention — slots must be consistently assigned.** A TCSR write
during a frame is valid only during the next frame.

**Address matching — TRTA** [§9.9.3, PDF p.588 / 9-79]: each device bitwise-ANDs the 8-bit value sampled on
TADD with its receive address RA7–RA0. Nonzero result → a valid TDM receive is executed (on every device
whose address matches, every slot). So TX→RX requires at least one bit set to 1 in both the transmitter's TA
and the receiver's RA. One transmitter can reach one or more receivers, and can select receivers by changing
only its own transmit address (receivers' RA need not change). Transmit address (upper half of TRTA) and TDXR
may be changed within the current frame for a slot not yet reached; the receive address (lower half of TRTA)
takes effect only at the next frame, like TCSR. When changing TA on the fly, do not corrupt RA (both are in TRTA).

**TRAD status** [§9.9.3, PDF pp.588–589 / 9-79–9-80]:

| TRAD bits | Name | Meaning |
|---|---|---|
| 13–11 | X2–X0 | Current slot number, whether or not a valid receive occurred in it. Latched at slot start, retained only until slot end |
| 10–8 | S2–S0 | Number of the last slot + 1 (modulo 8) in which data was received (e.g. last valid read in slot 5 → these bits hold 6). Latched at the TDM receive interrupt (TRNT) at the end of that slot, held until end of next valid-receive slot |
| 7–0 | A7–A0 | Last address sampled on TADD, whether or not a valid receive occurred. Latched halfway through each slot, held until halfway through the next slot |

Reading X2–X0 gives the current slot, enabling slot-by-slot reconfiguration (and slot sharing) if register
changes are made fast enough; TCSR and RA take effect only at a new frame, TA and TDXR at a new slot
[§9.9.4, PDF pp.590–591 / 9-81–9-82].

### 3.3 TDM timing rules — §9.9.4, PDF pp.589–591 / printed 9-80–9-82 (Fig. 9–44, PDF p.589 / 9-80)

- Frame = 128 TCLK cycles: 8 slots × 16 data bits. TFRM pulse occurs every 128 TCLK cycles, timed to coincide
  with bit 0 of slot 7 (the last bit of the previous frame). TCLK frequency = CLKOUT1/4 if generated by a 'C5x.
- Per slot, MSB first, 16 data bits, each one TCLK cycle — except the first bit of each slot, which lasts only
  half a bit time. Data is clocked onto TDAT by the transmitter and sampled from TDAT by receivers on the
  rising edge of TCLK. At the internal clock rate, a maximum of 64 instructions execute per slot.
- TADD: transmitted simultaneously with data, LSB first, during the first half of the slot (first 8 TCLK periods);
  during the second half (last 8 TCLK periods) TADD is driven high. Receive logic samples TADD only during the
  first 8 TCLK periods. First TADD bit also lasts only half a TCLK cycle. (A non-'C5x transmitter may drive TADD
  high or low during the second half.)
- Empty slot (no device's TCSR has that slot): TADD and TDAT are high-impedance. Spurious receives are
  possible (TDAT/TADD are always sampled) — a **1 kΩ pull-down resistor must be tied to TADD** so it reads
  low on empty slots; otherwise noise matching a receive address causes a spurious read. The resistor is not
  required on TDAT. Alternative if power dissipation is a concern: an arbitrary processor with transmit address
  00h drives empty slots by writing TDXR in those slots.
- An empty slot also results if TDXR was not loaded before a transmit slot in a frame, or when TCSR contents
  change (TCSR not updated until the next TFRM pulse).

### 3.4 TDM exceptions — §9.9.5, PDF p.591 / 9-82

- Overrun/underflow concepts are indeterminate in TDM mode (a processor may transmit in multiple slots);
  **the overrun and underflow flags are not active in TDM mode.**
- RX: if TRCV has not been read and a valid receive is initiated, the present TRCV value is overwritten; the
  receiver is NOT halted.
- TX: if TDXR has not been updated before a transmission, TADD/TDAT are not driven (pins stay high-impedance);
  this prevents spurious transmits.
- Improperly timed TFRM: the port cannot continue functioning (slot/bit numbers become ambiguous). Only one
  TFRM per 128 TCLK cycles. Unlike the serial port, the TDM port CANNOT be reinitialised with a frame-sync
  pulse during transmission — to correct it, the TDM port must be reset.

### 3.5 TDM examples — §9.9.6, PDF pp.591–595 / printed 9-82–9-86

**Interprocessor scenario** (Tables 9–22/9–23, PDF p.592 / 9-83): 8 devices. Slot 0: device 0 broadcasts,
TADD=0FEh, receivers 1–7. Slots 1–7: device 7→6 (40h), 6→5 (20h), 5→4 (10h), 4→3 (08h), 3→2 (04h), 2→1 (02h),
1→0 (01h). Register contents (TSPC xxF9h for device 0 — clock/frame source; xxC9h for devices 1–7; TRTA =
TA|RA, e.g. device 0: 0FE01h, TCSR xx01h; device 1: TRTA 0102h, TCSR xx80h; device 7: TRTA 4080h,
TCSR xx02h). TA of a transmitter need only share one 1-bit with the receiver's RA (bitwise AND) — exact match
is not required. Changing TRTA to 8001h on the fly would transmit only to device 7 (if receive addresses are
unique). Self-transmit (loopback): TRTA=0101h transmits to itself, since TX and RX both execute on the rising
edge of TCLK, using the standard connections of Fig. 9–42 [§9.9.6, PDF p.593 / 9-84].

**Code examples** (block 4000h–6000h, device 0 waits in BIO loop for XF from device 1; TX interrupt TXNT,
RX interrupt TRNT):

- Example 9–7 (device 0 TX; PDF p.594 / 9-85): `SPLK #1h, TCSR` (transmit slot 0); `SPLK #100h, TRTA`
  (TX address 01h); `SPLK #0039h, TSPC` (TXM=MCM=FSM=TDM=1, in reset); `SPLK #00F9h, TSPC` (out of reset);
  IMR `#080h` (TXNT). (Decodes INFERENCE from Tab. 9–13/§9.9.2 bit positions.)
- Example 9–8 (device 1 RX; PDF p.595 / 9-86): `SPLK #0h, TCSR` (transmit no slots); `SPLK #001h, TRTA`
  (RX address 01h); `SPLK #0009h, TSPC` (FSM=TDM=1, TXM=MCM=0, in reset); `SPLK #00C9h, TSPC` (out of
  reset); IMR `#040h` (TRNT); `CLRC XF` (ready-to-receive); ISR reads TRCV. (Decodes INFERENCE as above.)

---

## 4. §9.10 Host Port Interface (HPI) — PDF pp.596–613 / printed 9-87–9-104

8-bit parallel port interfacing a host device/processor to the 'C5x as a peripheral, host as master
[§9.10, PDF p.596 / 9-87]. Host and 'C5x exchange information through on-chip 'C5x memory accessible to both.
HPI provides 16-bit data to the 'C5x over the economical 8-bit external interface by automatically combining
successive bytes into 16-bit words [§9.10, PDF p.597 / 9-88]. **Available on 'LC57 and 'C57S per §9.10 prose
(PDF p.596 / 9-87) — plus 'LC57S per Tables 1–1/2–1 (see §0, Contradiction C3). NOT on 'C51.**
Block diagram Fig. 9–45, PDF p.596 / 9-87; generic system Fig. 9–46, PDF p.598 / 9-89.

### 4.1 Modes and memory

| Item | Rule | Ref |
|---|---|---|
| HPI RAM | Dedicated 2K-word block of internal 'C5x single-access RAM; also usable as general-purpose single-access data or program RAM | §9.10, PDF p.597 / 9-88 |
| 'C57 HPI RAM addresses | Data memory 1000h–17FFh; program memory 8800h–8FFFh. May be at different addresses on other 'C5x devices — consult product documentation. Affected by ROM protection if enabled | §9.10.2, PDF p.603 / 9-94 |
| Host view of HPI RAM | Addresses 0–7FFh; any HPIA whose 11 LSBs equal 0 addresses the first word (e.g. 0000h, 0800h, 1000h, 1800h, … F800h all address the word the 'C57 sees at 1000h). Only the 11 LSBs of HPIA are required to address the 2K memory; HPIA is 16-bit and increment/decrement affect all 16 bits | §9.10.2, PDF p.603 / 9-94 |
| Shared-access mode (SAM) | Normal mode: both 'C5x and host access HPI memory. Asynchronous host accesses resynchronised internally; on 'C5x/host conflict, host has priority and 'C5x waits one cycle | §9.10, PDF p.597 / 9-88 |
| Host-only mode (HOM) | Only the host accesses HPI memory, while the 'C5x is in reset or in IDLE2 with all internal and even external clocks stopped — minimum-power host access to HPI RAM | §9.10, PDF p.597 / 9-88 |
| SAM rate | One byte every 5 CLKOUT1 cycles (64M bps at 40 MHz CLKOUT1). Host may run up to (Fd·n)/5, Fd = CLKOUT1 frequency, n = host cycles per external access (e.g. 40 MHz 'C5x, n=4 → 32 MHz host; n=3 → 24 MHz) without wait states | §9.10, PDF p.597 / 9-88 |
| HOM rate | One byte every ~50 ns (160M bps), independent of 'C5x clock rate | §9.10, PDF p.597 / 9-88 |
| IDLE2 + SAM | Host cannot access HPI RAM in SAM while 'C5x is in IDLE2 (CPU clocks required); 'C5x must switch to HOM before entering IDLE2 if host access is needed there | §9.10.5, PDF p.611 / 9-102 |

### 4.2 HPI registers — Table 9–24 (§9.10.1, PDF p.599 / 9-90)

| Name | DSP address | Host access | Function |
|---|---|---|---|
| HPIA | — (host only) | Read/write | HPI address register; pointer into HPI memory for the current access |
| HPIC | **0500h** | Read/write (both sides; see §4.4) | HPI control register; control/status bits for HPI operations |
| HPID | — (host only) | Read/write | HPI data register; data read from HPI memory (read access) or to be written to HPI memory (write access) |

HPIC is the only HPI register directly accessible by the 'C5x (at 0500h in data memory space on the 'C57)
[§9.10.1, PDF p.599 / 9-90; §9.10.2, PDF p.604 / 9-95]. HPIA/HPID are host-only; the host reaches HPIC, HPIA,
and HPID via HCNTL0/1 (§4.3). HPIC is not listed in Table 9–1 (data page 0 map) — it sits at 0500h, outside it.

### 4.3 External signals — Table 9–25 (§9.10.2, PDF pp.600–601 / 9-91–9-92)

| HPI pin | Host equivalent | State | Function |
|---|---|---|---|
| HAS | Address latch enable (ALE) / address strobe, or unused (tied high) | I | Address strobe. Multiplexed-bus hosts connect ALE; HBIL, HCNTL0/1, HR/W latched on HAS falling edge. HAS must precede the later of HCS, HDS1, HDS2. Separate-bus hosts tie HAS high (1); then HBIL/HCNTL/HR/W latched by the later of HDS1, HDS2, HCS falling edge |
| HBIL | Address/control lines | I | Byte identification: low = first byte, high = second byte of a transfer. (NOT MSB/LSB — that is the BOB bit, §4.4.) Must not break the HBIL low/high sequence of an ongoing access — data can be lost, unpredictable operation |
| HCNTL0, HCNTL1 | Address/control lines | I | Select HPIA, HPID (with/without autoincrement), or HPIC (§4.3.1) |
| HCS | Address/control lines | I | Chip select / HPI enable. Must be low during an access, may stay low between accesses. Normally precedes HDS1/HDS2, but also samples HCNTL0/1, HR/W, HBIL if HAS unused and HDS1/HDS2 already low. HCS enables HRDY (HRDY always high when HCS high) |
| HD7–HD0 | Data bus | I/O/Z | Parallel bidirectional 3-state data bus, HD7 MSB. High-impedance when not outputting (HDSx and HCS = 1) or when EMU1/OFF is active (low) |
| HDS1, HDS2 | Read/write strobes or data strobe | I | Data strobe inputs controlling transfer. Also sample HBIL/HCNTL/HR/W when HAS unused and HCS already low. Separate R/W strobes → either HDS1 or HDS2 each; single data strobe → either, unused pin high; HR/W still required for direction. HDS1/HDS2 are internally exclusive-NORed — both low is NOT an enabled condition; a high-true strobe can go to one HDS input with the other tied low. Fig. 9–47 (select input logic), PDF p.602 / 9-93 |
| HINT | Host interrupt input | O/Z | Host interrupt output, controlled by HPIC HINT bit. Driven high while 'C5x is in reset. High-impedance when EMU1/OFF active (low) |
| HRDY | Asynchronous ready | O/Z | HPI ready output. High = ready for a transfer; low = busy completing the internal portion of the previous transaction. High-impedance when EMU1/OFF active (low). HCS enables HRDY |
| HR/W | R/W strobe / address line / muxed address-data | I | High = read HPI, low = write HPI. Hosts without an R/W strobe may use an address line |

HCS/HDS1/HDS2 functions are interchangeable if desired (internal strobe sampling HCNTL0/1, HBIL, HR/W is
derived from all three — the latest of HDS1, HDS2, HCS controls sampling), but using HCS in place of HDSx
affects HRDY operation [§9.10.2, PDF p.602 / 9-93]. Using HAS lets HCNTL/HBIL/HR/W be removed earlier in a
cycle (more time to switch bus states address→data), suiting multiplexed address/data buses
[§9.10.2, PDF p.602 / 9-93].

#### 4.3.1 HCNTL0/1 selection — Table 9–26 (§9.10.2, PDF p.603 / 9-94)

| HCNTL1 | HCNTL0 | Host access |
|---|---|---|
| 0 | 0 | Read or write HPIC |
| 0 | 1 | Read or write HPID data latches, **with autoincrement**: HPIA postincremented on each read, preincremented on each write |
| 1 | 0 | Read or write HPIA (pointer into HPI memory) |
| 1 | 1 | Read or write HPID data latches, HPIA **not** affected |

Autoincrement notes [§9.10.1, PDF p.598 / 9-89; §9.10.2, PDF p.603 / 9-94]: a data read postincrements HPIA,
a data write preincrements HPIA. To write the first HPI word with increment, first load HPIA with 07FFh (or
0FFFh, 17FFh, … FFFFh) so the preincrement lands on the first word. Increment is per 16-bit word, not per byte.

### 4.4 HPIC — HPI control register (Table 9–27, Figs. 9–48–9–51; §9.10.2, PDF pp.603–605 / 9-94–9-96)

Control/status bits are the low 4 bits. Host side: HPIC is organised as a 16-bit register with the same high-
and low-byte contents; the host always accesses it as two consecutive bytes, and **on a host write both bytes
must be the same value**. 'C5x side: 16-bit access at 0500h; bits 4–15 reserved for future expansion
('C5x side); bits 4–7 and 12–15 reserved on the host side [§9.10.2, PDF pp.604–605 / 9-95–9-96].

| HPIC bit | Name | Host access | 'C5x access | Function | Ref |
|---|---|---|---|---|---|
| 0 | BOB | Read/write | — (not visible to 'C5x) | Byte order bit. BOB=1: first byte is least significant. BOB=0: first byte is most significant. Affects both data and address transfers. Host-only; must be initialised before the first data or address register access | Tab. 9–27, PDF p.604 / 9-95 |
| 1 | SMOD | Read | Read/write | Mode. SMOD=1: shared-access mode (SAM), 'C5x may access HPI memory. SMOD=0: host-only mode (HOM), 'C5x denied access to the entire HPI RAM block. SMOD=0 during reset; SMOD=1 after reset. Modifiable only by the 'C5x; readable by both | Tab. 9–27, PDF p.604 / 9-95 |
| 2 | DSPINT | Write (write-only) | — (no effect) | Host→'C5x interrupt. Host writes 1 → interrupt generated to the 'C5x. Writing 0 has no effect. Always read as 0 by host and 'C5x. Both bytes of a host HPIC write must write the same value (see §4.6) | Tab. 9–27, PDF p.604 / 9-95 |
| 3 | HINT | Read/write | Read/write | 'C5x→host interrupt. HINT=0 upon reset → HINT pin inactive (high). Set only by the 'C5x (write 1 → pin driven low); cleared only by the host (write 1). Writing 0 by either side has no effect. Read as 0 when pin inactive (high), 1 when active (low) | Tab. 9–27, PDF p.604 / 9-95 |

HPIC read/write characteristics — Table 9–28 (PDF p.605 / 9-96): host reads 2 bytes, writes 2 bytes (both equal);
'C5x reads/writes 16 bits. Because the 'C5x can change SMOD/HINT between the host's two byte-reads, the two
bytes read by the host may differ [§9.10.2, PDF p.605 / 9-96].
[UNVERIFIED — the host-side high-byte values in Figs. 9–48/9–49, PDF p.605 / 9-96, are garbled in extraction;
the low-nibble mapping above (bits 3–0) is confirmed by Table 9–27 and by Figs. 9–50/9–51 ('C5x read: bit 3
HINT, bit 2 = 0, bit 1 SMOD, bit 0 = 0; 'C5x write: bit 3 HINT, bit 2 any, bit 1 SMOD, bit 0 any). Do not rely on
a high-byte mirror layout from this extraction.]

### 4.5 Host read/write access — §9.10.3, PDF pp.606–610 / printed 9-97–9-101

**Order and prefetch** [§9.10.3, PDF p.606 / 9-97]: host initialises HPIC first (esp. BOB), then HPIA, then
HPID (BOB affects the HPIA access, so HPIC before HPIA). Writing HPIA or HPID starts an internal cycle
transferring data between HPID and HPI memory over several 'C5x cycles: data written to HPID is NOT written
to HPI memory until after the host access cycle; data read from HPID is the data from the PREVIOUS cycle
(the current access initiates the next cycle). An HPID read immediately after an HPID write returns the data
just written. Because of this prefetch, if the 'C5x changed the location between a host read and the previous
access, a stale value may be read — do two reads from the same address, or a fresh address write before the
read, when that matters.

**HRDY / wait states** [§9.10.3, PDF pp.606–608 / 9-97–9-99; Fig. 9–52, PDF p.607 / 9-98]: in SAM, HRDY is
generally used; in HOM, HRDY is not active (stays high) — with exceptions below. During the internal portion
of a transfer HRDY is low (another transfer cannot start); HRDY goes high when the internal cycle completes.
After an external cycle, HRDY goes low for ~5 CLKOUT1 cycles while the 'C5x completes the internal HPI memory
access, then high again. HRDY is always high when HCS is high. Typical cycle: host drives HCNTL0/1, HR/W,
HBIL, HCS → asserts HAS (if used) → asserts a data strobe → if HRDY not already high, it goes high when the
previous internal cycle completes, data transfers, control signals deassert.

Table 9–29 — wait-state (HRDY active / SAM timings apply) conditions (PDF p.608 / 9-99):

| Register | Reads | Writes |
|---|---|---|
| HPIA | No | HOM: No; SAM: Yes |
| HPIC | No | Write 1 to DSPINT/HINT: Yes; all other cycles: No |
| HPID | HOM: No; SAM: Yes | HOM: No; SAM: Yes |

I.e. in SAM, HRDY stays high for: reading HPIC or HPIA, and writing HPIC except when writing 1 to DSPINT or
HINT [§9.10.3, PDF p.607 / 9-98]. In HOM, CPU is not involved (one exception: writing 1 to DSPINT or HINT in
HPIC takes several CPU cycles and SAM timings apply); otherwise HOM accesses complete after a short fixed delay
and are logically the same as SAM accesses [§9.10.3, PDF p.608 / 9-99].

**Two-byte rule** [§9.10.3, PDF p.608 / 9-99]: every host access cycle is two bytes, first HBIL low, second HBIL
high, regardless of register type; the sequence must not be broken or data may be lost / unpredictable operation.

**Worked sequences** (Tables 9–30–9–32, PDF pp.609–610 / 9-100–9-101; per-cell extraction partly garbled —
values below are those legible in the tables and body text):

- Table 9–30 (init BOB=0, HPIA=1000h): host writes HPIC 00h (both bytes) → writes HPIA first byte 10h
  (HBIL 0), second byte 00h (HBIL 1) → HPIA=1000h → internal RAM read completes, latches hold FFh/FEh
  (contents of 1000h). [UNVERIFIED — some intermediate latch cells in Tab. 9–30 are garbled; the HPIA value
  1000h and latch contents FF/FE are legible.]
- Table 9–31 (HPID read, autoincrement HCNTL=01): first byte reads FFh (HBIL 0), second byte FEh (HBIL 1);
  HPIA increments to 1001h between the two byte transfers (increment is per word, +1); the read also initiates
  the next read at 1001h, which completes with 6ABCh in the latches. The data obtained is always from the
  previous cycle's initiation.
- Table 9–32 (HPID write, autoincrement): host writes first byte 12h (HBIL 0), second byte 34h (HBIL 1);
  HPIA preincrements 1001h→1002h; after the internal write completes, HPI RAM 1002h contains 1234h. A read of
  the same address right after returns the data just written (still in the latches).

### 4.6 DSPINT / HINT — §9.10.4, PDF pp.610–611 / printed 9-101–9-102

- **DSPINT (host→'C5x):** host writes 1 to DSPINT in HPIC → 'C5x interrupt generated; can wake the 'C5x from
  IDLE. Host and 'C5x always read it as 0; a 'C5x write has no effect. No need to write 0 before generating
  another interrupt; writing 0 has no effect. Host must not write 1 to DSPINT while writing to BOB or HINT,
  or an unwanted 'C5x interrupt is generated. 'C5x interrupt vector address **18h**; bit 11 of IMR/IFR.
  'C5x vectors can be remapped into HPI memory: host writes the start address of a function to address 19h in
  HPI memory, then interrupts the 'C5x with a branch instruction at address 18h [§9.10.4, PDF p.610 / 9-101].
- **HINT ('C5x→host):** 'C5x writes 1 to HINT → HINT pin driven low; HINT then reads as 1 (host or 'C5x).
  Host acknowledges/clears by writing 1 to HINT → bit cleared, reads as 0, pin driven high. Writing 0 (either
  side) leaves HINT unchanged. While accessing SMOD, the 'C5x must not write 1 to HINT unless it also wants to
  interrupt the host [§9.10.4, PDF p.611 / 9-102].

### 4.7 Changing SAM/HOM and IDLE2 — §9.10.5, PDF pp.611–612 / printed 9-102–9-103

- HOM lets the host access HPI RAM while the 'C5x is in IDLE2 (completely halted); the external clock input
  may even be stopped (lowest power); random accesses still work without restarting the clock per access (no
  PLL lockup wait); the clock need only restart before taking the 'C5x out of IDLE2.
- In HOM, the 'C5x can access HPIC (toggle SMOD, send HINT) but CANNOT access the HPI RAM block — a 'C5x
  access to HPI RAM is disregarded. To access HPI RAM again, switch back to SAM after exiting IDLE2.
- SMOD: write 0 → HOM; write 1 → SAM. Two rules when changing mode:
  1. SAM→HOM: the instruction immediately following the mode-change instruction must NOT be IDLE2 (pipeline
     + mode-switch delay: IDLE2 would take effect before the switch, HPI stays in SAM, no host access).
  2. HOM→SAM: the instruction immediately following the mode-change instruction cannot READ the HPI RAM
     block (mode not yet changed; the read is ignored). HPI RAM WRITES are exempt (they occur much later in
     the pipeline — a write in the following instruction is allowed).
- Host side: no specific considerations. A third device may wake the 'C5x from IDLE2 and the 'C5x switch to SAM
  on wake-up without a software handshake with the host. The host may keep accessing while the mode changes;
  a host access to HPI RAM during the change delays the mode change until the host access completes, and a
  'C5x access to HPI memory is then also delayed.
- Table 9–33 sequence (PDF p.612 / 9-103): 'C5x switches to HOM (NOP — not IDLE2 — must follow) → executes
  IDLE2 → host/other device may stop the DSP clock → 'C5x in IDLE2 (clock stopped or running) → clock restarted
  if stopped (allow PLL wake-up time) → interrupt sent to DSP → 'C5x wakes from IDLE2 → 'C5x switches to SAM.

### 4.8 HPI access during reset — §9.10.6, PDF pp.612–613 / printed 9-103–9-104

- 'C5x is not operational during reset, but the host CAN access the HPI (program/data download to HPI memory);
  the host often controls the 'C5x reset input. Table 9–34 (PDF p.613 / 9-104):
  1. Host stops accessing the HPI at least **6 'C5x periods** before driving reset low.
  2. Host drives reset low; may start accessing the HPI after a minimum of **4 'C5x periods**. HPI mode is
     automatically set to HOM during reset (high-speed download). 'C5x clock may be stopped now, but must be
     running when the reset line falls AND rises (proper reset operation).
  3. Host downloads program/data into HPI memory; restarts the DSP clock if stopped (allow PLL wake-up time).
  4. Host stops accessing the HPI, drives reset high. Host may access the HPI again at least **20 'C5x periods**
     after the reset rising edge (internal reset delay). HPI mode is automatically set to SAM upon exiting reset.
- After reset, the RAM and OVLY bits must be set to 1 for HPI memory to be mapped into 'C5x program and data
  space (as with other single-access RAM blocks). The host can access HPI memory regardless of RAM/OVLY.
- A host write of 1 to DSPINT while the 'C5x is in reset is lost when the 'C5x comes out of reset.
- The 'C5x warm boot can use HPI memory and start execution from the lowest HPI address
  [§9.10.6, PDF p.613 / 9-104].

---

## 5. Timing-figure index (rules are in §§1–4; figures carry no extra numbers)

- SP: Fig. 9–12 one-way transfer (PDF p.535 / 9-26); Fig. 9–13 block diagram (PDF p.536 / 9-27);
  Fig. 9–14 SPC diagram (PDF p.537 / 9-28); Fig. 9–15 RX muxes (PDF p.541 / 9-32); Fig. 9–16 burst TX
  (PDF p.547 / 9-38); Fig. 9–17 long-FSX TX (PDF p.548 / 9-39); Fig. 9–18 delayed-FSX TX, SP
  (PDF p.549 / 9-40); Fig. 9–19 delayed-FSX TX, BSP (PDF p.549 / 9-40); Fig. 9–20 burst RX (PDF p.550 / 9-41);
  Fig. 9–21 burst RX overrun (PDF p.550 / 9-41); Fig. 9–22 long-FSR RX (PDF p.551 / 9-42);
  Fig. 9–23 burst TX max packet frequency (PDF p.552 / 9-43); Fig. 9–24 burst RX max packet frequency
  (PDF p.552 / 9-43); Fig. 9–25 continuous TX (PDF p.554 / 9-45); Fig. 9–26 continuous RX (PDF p.555 / 9-46);
  Figs. 9–27–9–31 exception flowcharts (§1.7).
- BSP: Fig. 9–32 block diagram (PDF p.563 / 9-54); Fig. 9–33 SPCE diagram, SP bits (PDF p.566 / 9-57);
  Fig. 9–34 TX continuous, external frame, FIG=1 (PDF p.569 / 9-60); Fig. 9–35 ABU block diagram
  (PDF p.571 / 9-62); Fig. 9–36 SPCE diagram, ABU bits (PDF p.572 / 9-63); Fig. 9–37 circular addressing
  (PDF p.576 / 9-67); Fig. 9–38 buffer mapping example (PDF p.577 / 9-68); Fig. 9–39 standard-mode init timing
  (PDF p.579 / 9-70); Fig. 9–40 autobuffering-mode init timing (PDF p.580 / 9-71).
- TDM: Fig. 9–41 TDM scheme (PDF p.583 / 9-74); Fig. 9–42 4-wire bus (PDF p.585 / 9-76); Fig. 9–43 TDM
  registers diagram (PDF p.587 / 9-78); Fig. 9–44 TDM timing (PDF p.589 / 9-80).
- HPI: Fig. 9–45 block diagram (PDF p.596 / 9-87); Fig. 9–46 generic system (PDF p.598 / 9-89);
  Fig. 9–47 select-input logic (PDF p.602 / 9-93); Figs. 9–48–9–51 HPIC diagrams (PDF p.605 / 9-96);
  Fig. 9–52 HPI timing (PDF p.607 / 9-98).

---

## 6. Contradictions found (both readings recorded; normative call stated)

- **C1 — SP maximum clock rate.** Reading A: SP maximum with internal clocks is CLKOUT1/4 — §9.7
  (PDF p.532 / 9-23: "5M bps at 50 ns, 7.14M bps at 35 ns"), §2.4.6 (PDF p.52 / 2-10: "up to one-fourth the
  machine cycle rate (CLKOUT1)"), and the MCM bit (Tab. 9–13, PDF p.539 / 9-30: internal clock is CLKOUT1/4).
  Reading B: Table 9–16 (PDF p.565 / 9-56) lists SP maximum serial port clock rate as CLKOUT1/2 (BSP: CLKOUT1).
  Normative: Reading A for internal-clock operation (three mutually consistent statements, one of them the bit
  definition). Reading B is unqualified in the table — it may be an external-clock ceiling, but the manual never
  says so; do not design an internal-clock SP link to CLKOUT1/2 on its basis.
- **C2 — BSP autobuffering init, TXM value.** Reading A: §9.8.3.1 body text (PDF p.580 / 9-71): "for receive,
  and transmit with external frame sync (TXM = 1), the BSP must be taken out of reset at least six CLKOUT1
  cycles…". Reading B: TXM=1 is *internal* frame sync (Tab. 9–13, PDF p.539 / 9-30), and Fig. 9–40's caption
  on the same page says "external frame (TXM = 0)". Normative: Reading B — the "(TXM = 1)" in the body text is
  a misprint; the 6-CLKOUT1 requirement applies to receive and to TX with external frame sync (TXM=0).
  Sub-slip in the same caption: Fig. 9–40 is the *autobuffering*-mode figure but its caption text says "The
  figure shows standard mode operation…"; the 6-cycle value itself comes from the body text and is unaffected.
- **C3 — HPI on 'LC57S.** Reading A (prose): §9.10 (PDF p.596 / 9-87) "HPI is available on the 'LC57 and 'C57S
  devices"; §2.4.5 (PDF p.51 / 2-9) same two devices. Reading B (tables): Table 1–1 (PDF p.39 / 1-6) marks
  the Parallel column `64K‖` (‖ = includes HPI) on all three rows 'C57S, 'LC57, **'LC57S** (visually confirmed
  on the rendered page); Table 2–1 (PDF p.51 / 2-9) groups "'C57S/'LC57S" in one row with Host Port = 1.
  Normative: Reading B — two independent device tables agree and explicitly include 'LC57S; the prose lists are
  treated as incomplete. (Caveat: §9.10's HPI RAM addresses are stated for the 'C57 only, with "different
  addresses on other devices — consult product documentation", §9.10.2, PDF p.603 / 9-94.)
- **C4 — BSP on 'LC57S.** Reading A (prose): §9.8 (PDF p.562 / 9-53) "BSP is available on the 'LC56, 'LC57, and
  'C57S devices". Reading B (tables): Table 1–1 (PDF p.39 / 1-6) marks Serial `2#` (# = includes BSP) on
  'LC56, 'C57S, 'LC57, **'LC57S**; Table 2–1 (PDF p.51 / 2-9) groups "'C57S/'LC57S" with BSP = 1.
  Normative: Reading B, same reasoning as C3.
- **C5 — TDM on "'C53 devices".** Reading A (prose): §9.7 (PDF p.532 / 9-23) and §9.9 (PDF p.583 / 9-74) and
  §2.4.8 (PDF p.52 / 2-10) say TDM is on the "'C50, 'C51, and 'C53 devices". Reading B (tables): Table 1–1
  (PDF p.39 / 1-6) gives 'C53S/'LC53S Serial = 2 with NO ¶ (¶ = includes TDM), while 'C53/'LC53 carry `2¶`;
  Table 2–1 (PDF p.51 / 2-9) gives 'C53S/'LC53S: High-Speed SP = 2, TDM = –, BSP = –, HPI = –.
  Normative: Reading B — "C53 devices" excludes the S variant; 'C53S/'LC53S have two standard SPs and no TDM.
- **C6 — HINT state after reset.** Reading A: §9.1.3 item 7 (PDF p.515 / 9-6): "On the HPI, HINT and SMOD are
  cleared while in reset, and then set after reset goes high" — read literally, both HINT and SMOD are set (=1)
  after reset. Reading B: Table 9–27 (PDF p.604 / 9-95): "HINT = 0 upon reset, which causes the external HINT
  output to be inactive (high)"; SMOD = 0 during reset, = 1 after reset. Normative: Reading B for HINT (the
  detailed HPI section, corroborated by §9.10.4, PDF p.611 / 9-102, and by Tab. 9–25, PDF p.601 / 9-92: HINT
  "driven high when the 'C5x is being reset"). §9.1.3 item 7 is treated as ambiguous shorthand in which "set"
  applies to SMOD only.

## 7. Unverified items (extraction garbled — not guessed)

- **U1** — Fig. 9–14 SPC diagram (PDF p.537 / 9-28) and Fig. 9–33/9–36 SPCE diagrams (PDF pp.566, 572 /
  9-57, 9-63): bit-position graphics render as block characters in extraction. Bit maps in this file are taken
  from the legible Tables 9–13/9–17/9–20, not from the diagrams.
- **U2** — Fig. 9–43 TDM registers diagram (PDF p.587 / 9-78): garbled in extraction. TSPC bit positions beyond
  bit 0 (TDM) are not asserted from the figure; DLB/FO hard-0 and FSM no-effect are from body text (§3.1).
- **U3** — Figs. 9–48/9–49 HPIC host-side high-byte values (PDF p.605 / 9-96): garbled; see §4.4 note. Low
  nibble (bits 3–0) is confirmed by Tab. 9–27 + Figs. 9–50/9–51.
- **U4** — Tables 9–30/9–31/9–32 (PDF pp.609–610 / 9-100–9-101): several per-cell latch values garbled in
  extraction. Sequences in §4.5 use only the values legible in the tables/body text (HPIA 1000h→1001h→1002h,
  data FFFEh, 6ABCh, 1234h); individual intermediate latch cells are not relied on.
- **U5** — §9.1.3 item 5 reset value for SPC/TSPC/BSPC (PDF p.515 / 9-6): rendered "0y00h" with the bit
  description garbled. Per-bit reset values in §1.3 (Tab. 9–13) are used instead.
- **U6** — §9.8.2.2 definition of N in the circular-addressing alignment rule (PDF p.575 / 9-66): superscripts
  lost in extraction. The alignment rule in §2.5 is taken from the Fig. 9–38 worked example (BK=5 → multiple
  of 8; BK=8 → multiple of 16), treated as normative; the printed "N+1 least significant 0 bits" for TBA is
  reproduced as printed and should not be used to recompute alignment.
