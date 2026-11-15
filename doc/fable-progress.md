# fable-progress.md — why the handshake still does not happen

Session 2026-11-14 (late). Running log, newest findings appended at the bottom.
Read `STATUS.md` / `HANDOVER.md` first for background. Addresses: `flash 0xNNNNN` = offset in
`SV25.flash.bin`; `seg:off` = 80186 address (flash offset = seg*16 + off - 0x80000).

## 1. Headline finding: both emulated modems are in FAX mode (Class 2.0 / Class 1 style T.30), not data mode

The "stalled handshake" is a fax call set-up waiting for the DTE (fax software) to drive T.30.
It is not a V.8/V.34 data handshake at all. Cause: the boot patch in `sys/machine.py`
(breakpoint at phys `0x9EB96`, sets `[0xEA7] |= 1`). `[0xEA7]` bit0 is **not** "DTE speed
locked by NVRAM" as assumed; it is the **fax-mode flag**.

Evidence (each item checked in the disassembly or by running the emulator):

1. `AT+FCLASS?` on the emulated modem answers **`2.0`** (run: scratch `fc.py`; `[0xEA7]=01`,
   `[0x26A]=F1A0`). `AT+FCLASS=0` returns ERROR and leaves the state unchanged; the breakpoint
   re-sets bit0 on every command anyway (hit count increases by one per command).
2. flash `0x338E`: `test [0xEA7],1` -> prints `"\r\n+FDM\r\n"` and clears the bit. `+FDM` is the
   fax adaptive-answer "data modem detected" report. So bit0 = fax session flag.
3. Answer path, flash `0xB75F`: `test [0xEA7],1; jz ...; call B82F` = **fax answer**
   (`cmd 12 4AAB` = 2100 Hz CED for `[0x134]=0x1C20` heartbeats = 3 s). The data-mode answer is
   the other branch (`0xB78B...`), which is also where the **DSP overlay load** lives
   (`0xB7CD: mov [0xE3C],5; call E60A`). That is why `[0xE3C]` stayed 0 and no overlay was
   ever loaded (old hypothesis 2 in STATUS).
4. Dial path, flash `0xB55D`: `test [0xEA7],1; jnz B56B` = fax originate (the `B57C-B5A2`
   call-progress loop). Data-mode dialing is at `0xB5C8`.
5. Line signals already observed match T.30, not V.25/V.8:
   - caller tone 1100 Hz, 0.5 s on / 3 s off = **fax CNG** (data calling tone would be 1300 Hz,
     0.5-0.7 s on / 1.5-2 s off);
   - callee 2100 Hz for ~3 s with no AM = **CED**, then 52 ms silence (`[0x134]=0x7D`), then
     1650 Hz = V.21 channel 2 mark = start of the T.30 HDLC preamble (DIS).
6. Mode table at `a110:1086` (used by `22170`): keys `03, 18h(24), 30h(48), 48h(72), 49h(73)...`
   -> DSP mode words `0100, 0202, 0203, 0403...`. These keys are the Class 1 `+FTM/+FRM/+FTH/+FRH`
   modulation codes (3 = V.21, 24/48 = V.27ter, 72/73/96/97... = V.29/V.17). The firmware help
   text even lists `AT+FCLASS=1+FATX=3 (V.21), 24, 48 (V.27), 96, 148 (V.29)`.
   `[0xE8A]=3` is hard-coded in both start routines (`a110:0F28` originate, `a110:0F92` answer).
7. The "bit sampler" state machine at `8F46:6A25-6B32` (`[0xEA0]` = 6A77/6AA4/6B0D) is an
   **HDLC receiver** (six 1s = flag, drop the 0 after five 1s, assemble octets with `rcr`).
8. DSP messages decoded (DSP `87CE`): **type 4 = carrier detected, type 5 = carrier lost**
   (edge-triggered, flag `[0x6F]` bit7, threshold `[0x0B]` with hysteresis). `E88` bit5 means
   "remote V.21 carrier present / frame reception in progress". The wait loop at `a110:15E2`
   therefore waits for the remote carrier to drop (type 5, then `[0xE99]=0x18` ticks of event
   0x76) or a timeout (0x83). The caller sees the callee's 1650 Hz preamble (type 4) and
   correctly waits for a DIS frame that never comes, because nobody (no fax DTE software)
   gives the callee a frame to send.

So everything observed is consistent, correct firmware behaviour for a fax call with no fax
software attached. C5x core semantics, clocks and overlays are not the blocker.

## 2. Other facts established on the way

- The CPU is an **80C186EB** (not a plain 80186). PCB layout (relocated to memory `0xFF00` by
  `RELREG=0x10FF`): `02 EOI, 08 IMASK, 0A PRIMSK, 12 TCUCON, 14 SCUCON, 16 I4CON, 18 I0CON,
  1A I1CON, 1C I2CON, 1E I3CON, 30-36 Timer0, 38-3E Timer1, 40-46 Timer2, 60-6A Serial0
  (66 S0STS, 68 S0RBUF, 6A S0TBUF), 70-7A Serial1`. Init table at flash `0x2BE` (52 port/value
  pairs). Vector types: 8 Timer0, 0C INT0, 0D INT1, 0E INT2, 0F INT3, 11 INT4, 12 Timer1,
  13 Timer2, 14 Serial0 RX, 15 Serial0 TX.
- `machine.py` checks `pcb[0x38] & 8` as "INT0 masked". On the EB `0x38` is T1CNT; the INT0
  control register is **`0x18` (I0CON, bit3 = mask)** and the global mask is IMASK `0x08`.
  The firmware does mask INT0 (`mov [0xFF18],0x0A`) around the event-0x76 post (flash `0xFD8E`,
  `0x14AD1`, `0x15BF8`). Not the stall cause, but the model is wrong.
- Event `0x76` is not a DSP message: it is a **tick** delivered from the periodic ISR
  (vector 0F, `8000:0A70`/`0AD9`, at `0x0EFF: lcall 8F46:00E6 -> call [0x138]`), hook `[0x138]`
  = `6798` during a mode. `[0x141]` reloads with 400 and counts a 12 h clock (`0xA8C0`), so the
  real tick is probably **400 Hz** (WRONG, it is 200 Hz, see section 5); the emulator gives one tick per 100000 CPU cycles = about
  187 Hz relative to the audio clock (7200 samples = 18.75 M CPU cycles). Supervisor timers
  therefore run about 2.1x slow against audio. To fix later.
- The in-call INT0 ISR (`8F46:0979`) calls `[0x298]` with CF=1 on every INT0 (heartbeat entry)
  and with CF=0/AL=type for messages.
- Vectors the firmware installs but the emulator never raises: 08 (Timer0), 11 (INT4),
  12/13 (Timer1/2), 14/15 (Serial0 RX/TX). The DTE path in fax mode uses Serial0 (`0F23`
  reads `[0xFF68]`); data mode very likely needs these.

## 3. Why the patch was there and what the real fix needs

The patch was added because the normal (data mode) DTE setup never installed an AT handler:
`F168` (`9EB0:0096`) returns CF=1 unless the fax flag and `[0x3FBA]` are set, after which the
firmware falls to the autobaud flow (raw oversampled DTE bits, detector `9CC9:0E27`), which
the emulator does not model. Forcing the fax flag gave a prompt (handler `F1A0` = the fixed-speed
fax DTE handler) and silently turned both modems into fax modems.

Plan: (a) experiment: after set-up, disable the breakpoint and clear `[0xEA7]` bit0 right
before `ATDT`/`ATA` and see whether the data-mode dial/answer paths run and request overlays;
(b) proper fix: model the DTE UART / autobaud path so the data-mode command handler is
installed without the fax flag.

## 4. Experiment log

(No emulator experiment has been run yet with the new core. Everything in sections 5-8 is from
disassembly. Section 8 says exactly what is done and what is not.)

## 5. CORRECTION: the supervisor tick is 200 Hz, not 400 Hz. CPU clock = 25.8048 MHz

- Section 2 says "probably 400 Hz". Wrong. Evidence for 200 Hz:
  - Timer0: `T0CMPA = 0x7E00` (flash `0x8C7`), timers count at CPU/4:
    25.8048e6 / 4 / 32256 = **exactly 200.0 Hz**.
  - Firmware converts tenths of a second x20 (flash `0x5685`, `0xB486`) and seconds x200
    (`0x1507C`, `0x1F955`, `0x2276F`) into ticks. `[0x141]` reload 400 = 2 s unit; `[0xDB1]`
    counts to 43200 = 24 h.
- CPU clock derived from the baud table at `9EB0:0C1A` (B0CMP values `800D 801B 8029 8037 8053
  80A7 814F 829F 853F 8A7F 94FF A9FF` = 230400 ... 300 baud; baud = F / (8 * ((BxCMP & 0x7FFF)+1)))
  => F = **25.8048 MHz** = 7200 x 3584 => **3584 CPU cycles per audio sample**.
- Old emulator: one tick per 100000 "cycles" at a flat 4 cycles/instruction = about 187 Hz
  against audio, so supervisor timers ran ~7% slow (not 2.1x as section 2 says).
- Assumption (not proven, no schematic): T0OUT is wired to INT3 (vector 0x0F). T0CON = `C001`
  has no INT bit, yet the tick ISR is on vector 0x0F and I3CON is unmasked. Model: raise INT3 on
  every Timer0 max-count. Tick ISR `8000:0A70` does `sti` at entry (nesting relies on priority).

## 6. 80C186EB peripherals as the firmware uses them

PCB at memory 0xFF00. Offsets:
`02 EOI, 08 IMASK, 0A PRIMSK, 0C INSERV, 0E REQST, 10 INTSTS, 12 TCUCON, 14 SCUCON, 16 I4CON,
18 I0CON, 1A I1CON, 1C I2CON, 1E I3CON, 30-36 Timer0, 38 T1CNT, 3A T1CMPA, 3E T1CON, 40 T2CNT,
42 T2CMPA, 46 T2CON, 50-5E ports (5A = P2PIN), 60 B0CMP, 62 B0CNT, 64 S0CON, 66 S0STS, 68 S0RBUF,
6A S0TBUF, 70 B1CMP, 74 S1CON, 76 S1STS, 78 S1RBUF, 7A S1TBUF`.

- IMASK bits: 0 TMR, 2 SER, 3 INT4, 4 INT0, 5 INT1, 6 INT2, 7 INT3 (each mirrors bit3 of its xCON).
  xCON: bits0-2 priority, bit3 mask, bit4 level-trigger. TxCON: 15 EN, 14 INH, 13 INT, 5 MC,
  4 RTG, 2 EXT, 1 ALT, 0 CONT.
- Init: TCUCON=0A, SCUCON=8, I4CON=0F, I3CON=0B, I2CON=11, I1CON=0F, I0CON=0A, PRIMSK=7, then
  IMASK=0068 => **INT4, INT1, INT2 masked; TMR, SER, INT0, INT3 unmasked**.
- **INT2 is masked.** The old emulator injected DTE characters through INT2 (ISR `8000:1D2C`,
  ports 0x00/0x0A). That path violates the mask. The real command-mode DTE is Serial0.
- **INT0 mask**: I0CON (0x18) bit3 / IMASK bit4. `machine.py` tests `pcb[0x38] & 8` (that is
  T1CNT). Firmware writes I0CON = 0A (masked) / 09 or ax in ~30 places.
- SxSTS bits (confirmed by usage): 9 DBRK1, 8 DBRK0, 7 RB8/PE, **6 RI (0x40), 5 TI (0x20)**,
  4 FE, **3 TXE (0x08, polled 24x)**, 2 OE, 1 CTS#. Reading SxSTS clears RI/TI/FE/OE; reading
  RBUF does not. SxCON: bits0-2 mode (1 = async 10-bit), bit5 REN; 0x21 = mode1+REN.
- P2PIN (0x5A) bit5 = raw DTE TXD level, 1 = idle/mark (read 15x, tested 9x).
- Timer2 is also used as a polled delay timer outside autobaud (`T2CON=C000, T2CMPA=0, T2CNT=0`
  at flash `0x432`, `0xE416`, `0xE4B7`, `0xE5A2`, `0xE5C8`); this is what the old "timer 3" model
  in `machine.py` (0x40/0x42/0x46) approximates.
- Vectors: 08 Timer0, 0C INT0, 0D INT1, 0E INT2, 0F INT3, 11 INT4, 12 Timer1, 13 Timer2,
  14 Serial0 RX, 15 Serial0 TX.

## 7. The real autobaud (segment 9EB0, flash 0x1EB00-0x1F6E3)

Section 3's "raw oversampled DTE bits, detector 9CC9:0E27" is NOT the mechanism. Real one:

- Dispatcher `9EB0:0072` (AL = 0,1,2 -> `0096`, `01CB`, `023E`). Case 0: `lcall 8000:F168`;
  CF=1 -> `009E` tests `[0x89D]&1`: set -> `00A8` (table autobaud), clear -> `0172` (generic:
  INT1 `0AAA` measures T1CNT, Timer1 ISR `0AE5`, Timer2 ISRs `0AF1/0B1E/0B62`, Serial0 RX `0B99`).
  `[0x89D]` is set at `8000:08C7` (`or [0x89D],3`) / `08D8`. Which variant runs: unchecked.
- Two more copies of the same code exist at flash `0x28F48...` and `0x7D5A4...`.
- Hardware inferred from the code:
  - **INT1 = rising edge of DTE TXD**, latched even while masked (firmware installs a bare-EOI
    ISR `064A` first to flush a stale edge).
  - **Timer1 counts only while DTE TXD is SPACE** (gated by T1IN) = start-bit width. Max-count
    `0x9EB0` -> vector 12 = give up/reset.
  - **INT4 = Serial1 interrupt**, level, cleared by reading S1STS. Serial1 RXD is also on the
    DTE line, set to 230400. Serial0 is set to 115200.
- `00A8` setup: `[0xB5A]=0BE4` (T1 threshold table), `[0xB5C]=0C00` (bit-period table),
  `[0xB5E]=0C1A` (B0CMP table), `[0xB58]=2`; vec INT4=`08AE`, I4CON=10; T2CON=6001, T2CNT=9,
  T2CMPA=FFFF; under cli: vec INT1=`0242`, Serial0 RX=`08A7` (bare EOI), Timer1=`0457`,
  Timer2=`0518`; T1CNT=0, T1CMPA=9EB0, T1CON=E001; B0CMP=801B, B1CMP=800D, S0CON=S1CON=21.
- INT1 ISR `0242`, ax = T1CNT (width of the 'A' start bit in CPU/4 units):
  `<0x28` -> 230400 (`0424`, Serial1, vec INT4=`08BB` checks 'A'); `<0x44` -> 115200 (`03F8`,
  Serial0 RX=`0700`, checks (c & 0x5F)==0x41, then vec=`076C`); `<0x60` -> 76800 (`0375`,
  busy-wait sampling on T2CNT, period 0x52); `<0x7D` -> 57600 (`02B2`, period 0x6E);
  else table lookup, T2CMPA = 1.5 bit, Timer2-interrupt sampling (`0518 -> 0555 -> 05AB`).
- Second character, Serial0 RX `076C`: 'A'/'a' restart; **'T'/'t' -> `07EF`**: parity ->
  `[0x5E6]`, `[0x5E5] = 12 - [0xB58]/2`, **`[0x26A] = 9A36` (data-mode AT handler)**,
  `[0xB7F]=9B3A`, `[0xB88] |= 0x40`, Serial0 RX vector = `8000:0F23`; '/' -> `07B7` (repeat);
  anything else -> `085C` (re-arm; `065E` = Timer2 timeout ~10 ms of idle line re-arms all).
- After autobaud: `8000:0F23` = `mov ax,[0xFF68]; call [0x26A]`. `8000:108A` installs it with
  `[0x26A]=9A36`. TX is polled on S0STS bit3 (`8000:1617-1657`) and also interrupt driven
  (vector 0x15, e.g. `196E`).
- Consequence: with a correct DTE line + Serial0/Serial1 + INT1 + Timer1/2 model the data-mode
  handler `9A36` installs by itself and the fax patch (`[0xEA7] |= 1` at bp `0x9EB96`) can go.
  `[0x26A]`: `F1A0` = fax handler (what we have now), `9A36` = data mode (what we want).

## 8. Implementation state (2026-11-14, end of session)

DONE (uncommitted, built, not yet exercised):
- `sys/i186.c`: `cyc_model` field (0 = legacy flat 4 cycles/instruction, default; 1 = approximate
  80C186 timing: `CYC[256]` base table, +6 memory operand, int +42, string ops 8/iteration,
  taken jcc +9, mul +28, div +36/40, far indirect call +28 ...). New API `i186_irq_pending()`,
  `i186_set_cycle_model()`. Rebuilt `libi186.so`.
- `sys/i186.py`: `CPU.irq_clear()`, `CPU.irq_pending()`, `CPU.cycle_model(m)`.
- Legacy behaviour is unchanged unless `cpu.cycle_model(1)` is called, so the old timeline
  should still reproduce (NOT re-verified with the regression gate).

NOT DONE: `sys/machine.py` is untouched. Design to implement:
1. Time base: `cpu.cycle_model(1)`; cycles = real clocks at 25.8048 MHz; one DSP sample
   (`dsp.run(2083)` + `serial_tick`) every 3584 CPU cycles (drop `dsp_acc`/`DSP_RATIO`);
   timers count cycles/4.
2. Event-driven loop: `budget = min(slice, next_event - now)`; PCB writes that change timing
   call `cpu.stop()`; then service events in time order.
3. Interrupt controller: request latch per source (edge sources latch while masked; INT4 level =
   live S1STS RI/TI), IMASK <-> xCON bit3 mirror, PRIMSK, priority from xCON low 3 bits (timers
   share TCUCON, serial SCUCON), tie order TMR > SER > INT4 > INT0 > INT1 > INT2 > INT3, INSERV,
   EOI at 0x02 (0x8000 non-specific, else by vector type). Offer best vector via `cpu.irq(vec)`;
   acknowledge detected by `not cpu.irq_pending()` after run.
4. Timers 0/1/2 with real semantics; Timer0 max-count also raises INT3 (200 Hz tick); Timer1
   counts only while the DTE line is space.
5. DTE line model: `send()` schedules 8N1 characters at `dte_baud` (default 115200, bit =
   CPU_HZ/baud cycles = 224) with ~2 ms gaps; level(t); P2PIN bit5; rising edge -> INT1 latch;
   Serial0 and Serial1 both receive from the line at their own BxCMP rate (RI, FE, OE);
   TX: TBUF write -> `dte_out`, TXE low for 10 bits, then TI + TX request.
6. INT0: keep heartbeat/event logic, but latch into the controller (mask via I0CON/IMASK).
7. Remove INT2 injection and the `[0x270]=0x1DF0` hack; `fax_patch=False` by default (keep the
   flag for A/B).
8. Keep the Machine interface used by `link.py`/`linkcall.py`/`tools/diag` (`send, dte_text, run,
   rx_gen, rxbuf, ring_on, cmd_log16, cmd_log, tx_all, take_tx, noise_amp, xint_mode,
   cycle_model, legacy, tdm_irqs, logging, hb_ticks, hb_count, hb_pending, pcb, dsp_log, _lk_seen`).

### 8a. Update: new `sys/machine.py` written (uncommitted; old version = `git show HEAD:sys/machine.py`)

Implemented exactly the design above (points 1-8): event-driven `_run`, interrupt controller
(`_icu_eval`, `_sync_ack`, `_eoi`, `icu_state()` for debugging, `irq_count` per vector), timers
(`Tmr`, `_tupd/_tsched/_trun`), serial ports (`Uart`, `_uart_rx`, TX done -> TXE+TI), DTE line
(`send()` -> `txq` -> `_line_feed` -> `edges` -> `_edge`), PCB registers (`_preg/_pwr`), INT0
latched into the controller once per sample. Constructor: `Machine(patch_crc, nvram_mode,
fax_patch=False, cpu_model=1)`. `run(cycles, slice_)` ignores `slice_`.
Also fixed in `sys/i186.c`: a halted CPU with a pending request and IF=0 looped forever inside
`i186_run`; it now returns ST_HLT.
Scratch tests: `scratchpad/t1.py [n_boot_2s_steps] [cmds...]`, `t2.py`.

**First run result: boot does NOT get through yet.** After 12 s emulated the CPU sits in a RAM
loop at `0000:044A-0457` that polls I/O port 0x10; no DSP download, only one PCB write (offset
0xA8 from phys 0xFDBD1), all timers/serial untouched. This is before any of the new interrupt
sources matter, so the suspect is the new cycle model (a timing loop) or a core bug in it, not
the peripheral model. Next: run with `cpu_model=0` to confirm, then dump the RAM code at
0x440-0x460 and see what it waits for.

### 8b. RESULT: boot + autobaud + data-mode AT handler work WITHOUT the fax patch

Cause of the 8a hang: after reset the PCB is in **I/O space** (ports 0xFF00-0xFFFF). The boot
loader (runs from RAM, copied from flash ~0xFDBxx) programs it with OUTs and waits on a counter
that the tick decrements. Only its last write, RELREG (0xA8) = 0x10FF, moves the PCB to memory
0x0FF00. Added `pcb_mem` to `machine.py` (I/O-mapped until RELREG bit12 is written).

Loader writes: T0CMPA=7E00, T0CON=C001 (no INT bit), I3CON=0B, IMASK=0079 (INT3 unmasked,
timers masked). So the tick really is **Timer0 output -> INT3**: the assumption in section 5 is
now confirmed by the loader itself (199 ticks in 1.0 s).

Single machine, `Machine(nvram_mode=None)`, fax patch OFF (`scratchpad/t1.py 8 AT 'AT+FCLASS?' ATI4`):
- Boot prints a self test: `TESTING RAM OK / ROM OK / NVRAM CHECKSUM FAILURE / DSP OK / LEDS AND
  SPEAKER`, then `CURRENT DIPSWITCH SETTINGS ... #1-#10 ON`, `SELF TEST COMPLETED` (done by ~5 s).
- `[0x26A] = 9A36` (data-mode AT handler), `[0xEA7] = 00`, `[0x89D] = E7` (bit0 set -> table
  autobaud variant `00A8`).
- **`AT+FCLASS?` answers `0`** (was `2.0`). `ATI4` prints the settings page with
  `BAUD=115200 PARITY=N WORDLEN=8` = autobaud measured our 115200 terminal correctly.
- Interrupts per command: INT1 x2, INT4 x1, Serial0 RX one per character, Serial0 TX per output
  character, INT3 200/s, INT0 2400/s. No stuck in-service bits (all ISRs send EOI).
- Speed: ~1.4 emulated s per wall s for one machine.

Open problems seen in that run (to do next):
1. **Plain `AT` answers `4` (= ERROR in numeric mode), and every command gets an extra `4`**
   after its real answer. Same "extra ERROR" the old emulator had, so not caused by the hack.
   Ideas: (a) the line is terminated by CR only and the firmware sees something after it;
   (b) INT1 fires on every rising edge of every character (2 per command counted, should be
   masked after autobaud, check who re-arms it: `065E` idle timeout re-arm?) so the autobaud
   restarts mid-line and eats the `AT` prefix; (c) my 2 ms inter-character gap or the missing
   echo path; (d) S-register/NVRAM defaults. Trace: log every char passed to `[0x26A]` and
   what the parser at `9A36` rejects.
2. **No echo** although settings say `E1`. May be related to 1.
3. Defaults are odd because NVRAM fails checksum and all DIP switches read ON (port reads = 0):
   `V0 Q2 X1 &B0 &H0 &K1 S0=1` (numeric results, **auto answer on first ring**, dial=PULSE).
   `linkcall.py` sets `ATQ0V1`/`X3`; check what the DIP port is and feed sane switch values
   (real default: DIP 3,5,8,9 ... per manual in `doc/`), or model NVRAM.
4. Self test at every boot: probably DIP-switch or port-bit triggered (all inputs read 0).
   Costs ~5 s emulated; find the input and turn it off.
5. `linkcall.py`/`link.py` still use the old cycle numbers (900 M = 35 s boot, 150 M = 5.8 s per
   command, slice 100 k = 28 samples). They still work, just slow; rescale later.
6. Not yet run: two-modem call. Expected to change completely (data-mode dial `0xB5C8`, answer
   `0xB78B`, overlay load `[0xE3C]=5; call E60A`). Baseline timeline in STATUS is fax mode and
   no longer applies. Things that may break next: overlay download path (banks 0x40-0x5E with
   status ports 0x18/0x1A after the DSP is running), INT0 heartbeat model (invented), DSP
   clock (2083 cycles/sample is a guess), ring detect port 0x14, hook state/DAA ports.
7. Not modelled: parity/7-bit frames in the UART, DTR/RTS/CTS lines, break, Timer0/1 prescale
   by Timer2, special fully nested mode, level-triggered INT0/INT2. `fax_patch=True` is kept
   only as a switch and is untested with the new serial path.
8. Docs to fix once stable: STATUS.md (hypotheses list is obsolete: the blocker was fax mode),
   HANDOVER.md (machine description: INT2 DTE and "INT3 tick every 100000 cycles" are gone),
   `sys/FULL_SYSTEM.md`, memory files. Nothing is committed.

### 8c. RESULT: first two-modem call in DATA mode. New blocker = callee DSP crashes in answer mode

Runs: `sys/linkcall.py auto 65 ../out/new1` (output `out/new1/x.out`, WAVs there) and the faster
`tools/diag/new_call.py <seconds>` (8 s boot, ~45 s wall for a 14 s call; writes
`out/new1/diag_a.wav`, `diag_b.wav`).

What now happens (times = seconds after `ATDT1`):
- Setup commands work but each answers ERROR (`AT` -> `4`, `ATQ0V1` -> `ERROR` yet it is applied:
  later results are verbal `RING`, `NO CARRIER`). Problem 1 of 8b is still open.
- Caller B: dials at 2.1 s (much earlier than the old 7.3 s), ringing 5.2 s, callee prints
  `RING`, `ATA` at 8.4 s. B sends DSP `17 705D` (data originate; fax used `20 0100`) and stays
  silent, waits, prints `NO CARRIER` at ~62 s (S7 = 60 s). B never reacts to A's tone.
- Callee A: at 10.1 s sends the data-answer set-up (`1A 3D00, 3C 32D6, 44, 48, 51, 52, 70, 1C,
  1D, 2A, 42, 49, 50 x7, 53, 71, 77, 76, 04 0000`) ending with **`14 715D`** (fax was `12 4AAB`).
- A's line output: silence, then at 10.0-11.25 s (about 1.25 s) a **near full-scale signal, rms
  ~26000, peak 31232, strongest line 2100 Hz plus 1200/2000/3000/300 Hz components**, then
  silence. A clean answer tone would be one line at 2100 Hz (ANS) or 2100 +/- 15 Hz sidebands
  (ANSam) at a much lower level, so this looks distorted/overflowing, not a proper tone.
- **About 2.4 s after the tone starts A's DSP dies**: PC stuck on `81AE` (`rete`) forever,
  DXR output stops, hardware stack is all `81AE`, ST0 INTM=1, IFR=0030, IMR=002A. `81AE` is the
  default value of the invented vector stubs `dm[0x61..0x6A]`; `dm[0x60]` has been overwritten
  with `37FE`. Reads as a **stack underflow / unbalanced return**, i.e. the DSP ran off the
  rails earlier (bad code path, missing overlay code, or a C5x core bug in code never run in
  the fax path).
- `[0xE3C]` stays 0 on both sides: no overlay load was requested.
- **Reproduces on ONE machine in ~25 s wall**: `python3 -I tools/diag/new_answer.py ATA 14`
  (boot, `ATA`, DSP stops 4.55 s after the command, first output sample 2.5 s after it).

Thoughts on what is wrong / what to do next, most likely first:
1. DSP answer-mode code path. `14` handler = DSP `9E45`, which lies in the region that overlay
   ov6 (`0x9D00`) overlaps. If the data-mode answer needs ov6 loaded and the supervisor thinks
   it already is (or loads it at a point we never reach), the base copy at 9E45 may be the
   wrong code. Check: which image the loaded 55420-byte base holds at 9D00-AFFF, whether the
   supervisor data-answer path (`0xB78B`..`0xB7CD: [0xE3C]=5; call E60A`) is reached before or
   after `14 715D`, and what gates it.
2. Trace the DSP from `14 715D` to the crash: `d.set_trace`, `recent_pcs`, breakpoint on the
   first `rete/ret` that pops `81AE`, find the unbalanced push/pop or the jump into data.
   Compare the 1.25 s of output with a real ANS/ANSam (level, AM, phase reversals). The audio
   path was only ever verified for fax tones.
3. C5x core items left unapplied in the audit may now matter (RPTB PAER, NDX/AR0 mirroring
   hack `cmpr_ar0`, INTR context save, delay-slot stack order, 8-level stack wrap model).
4. The invented DSP ROM stub model (`ivec_ind`, `dm[0x60+n]=81AE`, 65/68/69 special): the data
   path may use an interrupt (IMR bit1 = INT2, bit3 = TINT) that the fax path did not, and
   whose stub we do not provide. TINT with PRD=0 would fire continuously.
5. Caller side: after `17 705D` B should detect the answer tone and start V.8 (CM) or fall
   back. It did nothing, possibly only because A's tone is garbage; re-check once A is fixed.
6. Then the 8b list (ERROR after every command, echo, DIP switches/NVRAM defaults, self test).

Test plan: (1) single machine with fax patch still ON, new time base/ICU: banner, `AT`, compare
timeline; (2) patch OFF: `AT`, `AT+FCLASS?` should answer 0 and `[0x26A]` should be `9A36`;
check `[0x89D]`; try other DTE speeds; (3) `linkcall.py auto 65` on the builder. Cycle-count
durations in `linkcall.py` (`L.run(900_000_000)` boot, `150_000_000` per command) assume the
old time base and will need rescaling (new: 25.8 M cycles = 1 s). The STATUS baseline timeline
is the fax-mode one and is expected to change legitimately once the modems are in data mode;
watch for the data-mode dial (`0xB5C8`) / answer (`0xB78B`, overlay load `[0xE3C]=5; call E60A`).

## 8d. DIP switches (2026-11-14)

User asked whether wrong DIP switches matter. They were all reading ON (ports returned 0). Decoded the read path:
- Print routine 8000:799F, per-switch table 8000:7A05 (word: low = selector, high = mask): `0040 0203 0103 0803 0403 0404 8003 4003 2003 1003`
  (alt table 7A19 when `[0x693]&8` swaps switch 7 and 10 masks).
- Test routine 8000:27F9: selector 0x40 -> P2PIN (FF5A) bit6; else port = cs:27EF[sel&7] (3 -> port 0x12, 4 -> port 0x14); `in al,dx; and al,ah`; zero -> "ON".
  So **bit 1 = OFF, bit 0 = ON**.
- Mapping: DIP1 P2PIN.6 | DIP2 0x12.1 | DIP3 0x12.0 | DIP4 0x12.3 | DIP5 0x12.2 | DIP6 0x14.2 | DIP7 0x12.7 | DIP8 0x12.6 | DIP9 0x12.5 | DIP10 0x12.4
- Factory default (manual: ON = 3,5,8,9) -> port 0x12 = 0x9A, port 0x14 bit2 = 1, P2PIN bit6 = 1.

Done: `Machine.set_dip(on=(3,5,8,9))` in sys/machine.py, called from `__init__`. Self-test printout now shows exactly the factory pattern.

Effect:
- Fixed: ATI4 now shows `E1 Q0 V1` (was E0 Q2 V0), replies are verbal (`ERROR` instead of `4`).
- NOT fixed: plain `AT` still answers ERROR; self test still runs at every boot; `NVRAM CHECKSUM FAILURE`; S0=1; DIAL=PULSE; X1.
  With DIP10 OFF the modem loads NVRAM, which fails checksum -> probably the source of the odd S0=1/PULSE/X1 values. Needs a valid NVRAM image
  (or check what `nvram_mode=6` / bp 0x8063E feeds it).
- NOT fixed: callee DSP crash is identical (`new_answer.py ATA 14`: tone starts +2.51 s, DSP stuck at 81AE at ~+4.6 s, same registers). So the DSP crash is not a
  configuration issue; continue with the 8c list.
- Self test at boot is likely another strap/input (not a DIP): find what selects the "TESTING RAM..." path. ERROR on `AT` needs a trace of the parser at 9A36.

## 9. Session continued (Claude): AT works, overlays load, DSP crash fixed, next = NVRAM

Commits: 2683f1f (fixes) and later. Everything below was checked by running the emulator unless marked (reading).

### 9a. DSP crash root cause = missing NDX=0 coupling (core bug)
- Symptom (8c): callee DSP ends in a `rete` loop at 81AE, PRD=0, TIM=0, IFR stuck.
- Cause: the DSP code `lar ar0,#DC00 ... mar *0+` uses AR0 as the index register. With NDX=0 (reset state, 'C2x compat) any load/modify of AR0 must also load INDX and ARCR (manual 6.3 LAR/MAR/SAR, audit #10). The core did not, so `*0+` added INDX=0, a delay-line write landed on dm[0xBF7/0xBF8] (the TINT ISR's PRD constants 419A/41A4 loaded by `lmmr #25` at 821C), PRD became 0 and TINT fired every cycle.
- Fix (dsp/c5x_core.c, run loop): `if (!ndx && !(legacy&64) && ar[0] != ar0_prev) indx = arcr = ar[0]`. The old `cmpr_ar0` hack is now off by default (env `CMPR=1` restores it). Legacy bit 64 disables the mirroring.
- Also added `pc_hits[]` counters (`DSP.pc_hits(pc)`, `pc_hits_clear()`), used for tracing.

### 9b. "Every AT command answers ERROR" = hardware-ID strap not modelled
- Result printer 8000:9E60 turns OK (0) into ERROR (4) when `[0x89D]&1` and `[0x693]` is 0 or FF. `[0x693]` is the board ID, filled by 8000:0951: it clears four output lines (D=port0x14.6, A=port0x12.1, B=port0x14.4, C=port0x14.5) one at a time and reads port 0x14 bit3 (selectors in table 27EF); the four answers (D,A,B,C = MSB..LSB) index the ID table at 8000:09F6 = `00 00 29 00 00 14 00 22 00 28 00 42 28 22 48 00`.
- Machine now models this (`_hw_id_bit`, `hw_idx`, default 7 -> ID 0x22; env `HWID`; 5 also works; 2 gives no banner). Which index the real board has is unknown.
- Result: `AT` -> OK, `ATI0` -> 5607, `ATI4` fine.

### 9c. DSP overlay download works (HLE of the bank handshake)
- Host protocol (flash 8000:E60A, table at E741 rows 5..8: 5 = base image 0x8000 len 0xD87C, 6 = ov6 0x9D00, 7 = ov7 0xB000, 8 = ov8 0xDC00; sources are raw in flash, e.g. ov6 at 0x36F60): host out 0x1E,4; DSP command `0002 <load addr>`; DSP command 2 handler (8266) writes 0x0700 to its port 0x57 (bit8/9 = bank A/B free, bit10 = ready; cmd 3 writes 0x0300); host reads port 0x1E for those bits, fills bank A (ports 0x40,42,44,46 = 2 words) / bank B (0x48..4E), acks with out 0x1E,1/2; final out 0x1E,4.
- Machine: `ovl_status` follows the DSP's 0x57 writes, `_ovl_host_ack` collects the bank bytes and `load_pm`s them at the commanded address at the final ack (`ovl_loads` log).
- NOTE: ov6 covers 9E45 as the middle of a 2-word instruction, so DSP cmd 0x14 (handler 9E45) is only valid with the base image or ov7/ov8; ov6 is for other modes (leased line, `&L1`).
- Which overlay the firmware selects: code at flash 0xBBDA..0xBC82. `[0xE3C]` = 6 only if `[0x5FA]==1` (= `AT&L1`, leased) etc.; with default config `[0xE3C]` stays 0 and the dial-up data call runs on the BASE DSP image only. Not yet understood whether that is right or a symptom of missing NVRAM profile.

### 9d. Other findings
- `[0x600]` = `&N` value, `[0x5FA]` = `&L`, `[0x5EF]` = volume.
- ATA path: b76c -> b6aa (data answer, no supervisor state machine), `[0xE88]&4`=0.
- Timer: DSP PRD constants 419A/41A4 alternate in the TINT ISR (symbol-timing adjust, about 2400 Hz); implies roughly 5600 DSP cycles per 7200 Hz sample (DSP clock about 40 MHz?), but the emulator uses DSP_CPS 2083 (a guess). Unresolved.
- Messages DSP->host: words 0x5E (type) / 0x5F (payload); `msg_log` in machine.py. Callee posts type 0x16, caller type 0x08 with varying payload (0x81, 0x817B, 0x81E8, 0xC0 ...) when the answer tone arrives; the caller supervisor does not react.

### 9e. Current call result (out/new3, out/new2; tools/diag/call2.py)
- Timeline now: caller dials 2.1 s, ringing 5.2, answered 8.4. Callee sends `14 715D` (data answer), caller `17 705D` (data originate).
- Callee audio: first a clipped, distorted burst 10.15-11.25 s (rms ~26000, peak 32764, 2100 Hz strongest plus 300/1200/2000/3000), then 9 s later a clean 2100 Hz tone (rms ~4900) 19.3-20.4 s; repeats every ~9 s. Caller silent after dial tone.
- Hypothesis: the burst is full gain because the tx-level words sent before the answer (`0x48` built from `[0x5CD]` at 8000:8985-8997, `0x71 7FFF`, `0x77 FFFF`) come from a blank profile (NVRAM checksum failure, DIP 10 OFF = load NVRAM).

### 9f. TODO / next
1. NVRAM: understand the boot read + checksum, provide a valid default image so `NVRAM CHECKSUM FAILURE` goes away and profile/S-registers get real values; rerun call.
2. Re-check DSP clock ratio (timer says ~5600 cycles/sample).
3. Caller reaction to the answer tone (type 0x08 messages) once the profile is sane.
4. DTR/RTS/CTS/DCD lines and DAA/hook ports are only approximated.
5. Docs to rewrite: STATUS.md, HANDOVER.md (old fax-mode baseline is obsolete), sys/FULL_SYSTEM.md, memory files.
6. Output convention: each run into its own out/<tag>/ directory (out/new3 was overwritten by a shorter run).

Tools added: tools/diag/{call2,spec,bp186,errsrc,ansprobe,dspstep,dmwatch,cfgprobe,cfg2,atprobe,mem186,ovl_try,dsp_crash}.py.

## 10. NVRAM (serial EEPROM) decoded and modelled (commit 5ccea37)

- Hardware: 3-wire Microwire EEPROM (93C66-like, 256 x 16) bit-banged on 80C186EB port pins. CS = P1LTCH (0xFF56) bit5, SK = P1LTCH bit2, DI = P2LTCH (0xFF5E) bit7 (output while P2DIR 0xFF58 bit7 = 0), DO = P2PIN (0xFF5A) bit7 (P2DIR bit7 = 1; same pin as DI).
- Firmware: read word = 8000:1419 (12 clocks: 0, start 1, op 10, 8 address bits; then 16 data clocks), write = 8000:1330 (EWEN/WRITE, busy poll on DO), load-all = 8000:13C5 (256 words into RAM 0x696..0x895, all-FF or all-00 = invalid, checksum = sum of bytes 0x696..0x893 compared with byte 0x895; failure sets `[0x25E]` bit0 -> banner `NVRAM CHECKSUM FAILURE`). Banner code 8000:7798..7820.
- Emulator: `Eeprom` class in sys/machine.py driven from `_pwr` (P1LTCH edges) and `_preg` (P2PIN bit7). Image via env `NVRAM=<file>` (local, gitignored `sys/nvram*.bin`). `tools/diag/nvgen.py out.bin` lets the firmware write its own image (`AT&F`, `AT&W`): 44 words written. Booting with it prints `TESTING NVRAM OK`.
- Result: the stored profile equals the defaults (S00=001, DIAL=PULSE, X1 ...), call timeline unchanged, the DSP setup words are the same except `42 0FF9` (was 0FFF) and a few `50 xxxx`. **The clipped first burst on the answerer (rms ~25000, peak 32768) is NOT caused by a blank NVRAM** (still present with `out/nv1/`); `0x48 7FFF`, `0x71 7FFF`, `0x77 FFFF` are sent regardless. Hypothesis in section 9e is refuted; the burst has to be explained from the DSP side (what runs for 1.1 s after `14 715D`, then 9 s of silence, then a clean 2100 Hz tone rms ~4000-4900).
- Open: S00=001 / DIAL=PULSE as factory profile looks odd; the profile template may come from a different default (`AT&F0` vs `&F1`) or from DIP10.

## 11. Why the handshake stalls: message protocol decoded (2026-11-15)

Evidence from running + reading; nothing here fixes the burst or the missing second phase yet.

- **Voice/Data button** = port 0x14 bit6, active low. Boot code 8000:0638 -> 77A9 runs the self-test banner only when it reads 0. It was held (0) all along; now released by default (`VDBTN=1` holds it). Boot is silent and ~3 s.
- **DSP -> host messages** are two words: word1 (low 15 bits) -> host port 0x5E/0x58 = type in AL (AH = high byte); word2 -> port 0x5F = payload (host reads it at 0x5C/0x5E). DSP post routine 83C8 (called twice per message), send routine 83D6.
- **Host handler** [0x298] dispatches on the type through byte-key / word-handler tables (`repne scasb` dispatcher at 8F46:035A). Key tables extracted for ~60 states. While waiting for the answer/handshake the hook is 8F46:5782 with 36 types: 83 07 3A 21 08 3D 28 29 2A 2B 2C 2D 2F 47 0B 2E 23 45 46 48 30 34 35 36 37 6A 6C 6D 70 71 73 74 6B 6E 44.
  - 0x28/0x29 -> 57C6 ([0x32B]=3, [0x32C]|=0x40 = "mode 3 started"), 0x2A -> 5840 (0xC), 0x2B -> 587C (0x18), 0x2C -> 5802 (0xC), 0x2D -> 58B8, 0x2F -> 593A, 0x0B -> 577C, 0x07 -> 579C.
  - **0x47 -> 5963: `[0xE3C] = payload | 0x80`, i.e. the DSP itself requests overlay N** (e60a then loads it; 6 chains 8). Only writer of E3C besides the supervisor's own selection at 0xBC78.
  - Type 0x08 -> 59A8 = signal-status report (bit0 = energy present, bits 2-5 = unusable); drives the call-progress counters [BDC]/[BE3] and uses [0x134] time windows.
- Both supervisors then sit in the loop at flash 0xB912 until `[0x32C]` bit6 (a mode-start handler ran, `[0x32B]` = mode) or bit7 (abort).
- **What the DSP actually posts in our runs**: answerer = type 0x16 only (word2 = analyzer flags [0x2F], from base cmd 14 handler 9E45, `lacc #8016; call 83C8`), originator = type 0x08 status only. Neither type is in the 5782 table, so no mode ever starts.
- **Base image vs overlays**: base cmd 14/17 (9E45 / 9BC5) are *line analyzers* (per-sample task 9E87 / 9C18: filters, energy compares vs 0x7500/0x61D7/..., flags in [0x2F]). Handlers 0x42/0x44 are tiny flag setters in base (B05E/B05B) but big mode inits in ov7 (B05B calls C141/C1AC): the firmware sends the same command sequence regardless of which image is loaded, so the *right overlay must be loaded*. Overlays are requested by 0x47 messages or by the supervisor selection (flash 0xBBFA..0xBC82) which only runs when `[0xA96]&2 | [0x5A5]&1 | [0x685]&1` (writers of those bits not found; `[0x685]` bit0 is set in 8000:76ED = event handler 7604, never called by ATA).
- E88 bit2 = AT+FCLASS=1; EA7 bit0 = FCLASS 2.0 (flash 0x21B17).
- **Event bit2** (INT0 status 0x1C/0x1E bit2 -> hook [0x2D3], 8000:0674): DSP raises it by writing 4 to its port 0x57 (base 84BA, in a routine at 848B..84B7 that also does `out *,#0060`). Now modelled (`evt4_n` counts), but it only fires once per ATA in the base flow, so it does not change the call.
- DSP clock ratio: setting 5600 cycles/sample (`DSP_CPS=5600`) changes nothing in the audio, so the clipped first burst is not a CPU-starvation artifact.
- With E3C poked to 6 or 7 before ATA the overlays load and the DSP stays alive, but no 0x28-0x2F/0x47 messages appear either (poke is not the real trigger).

Open question to resolve next: what makes the real modem leave the analyzer/base state: the answerer's first signal is generated by something we have not identified (clipped burst then a periodic clean 2100 Hz is not it), and the DSP never posts 0x47. Candidates: another command in the sequence (0x50 table, 0x1C/0x1D/0x2A) that needs an overlay, or the supervisor path via 8000:7604 (`[0x685]`, `[0xB8A]`=1) that ATA/auto-answer does not take in our emulation.

## 12. Start-of-call command selection and the 0x7604 lead (2026-11-15)

- The DSP "start" command is chosen at flash 0x84FB: `ax=0x59` if leased line (b893 CF), else `0x14`, and `0x11` instead when b87f says "already online" ([0xA96]&2 | [0x5A5]&1 | [0x685]&1); `bx=[0x281]` (the mode mask built by b96d from [0x27F]/[0x5EC]/[0xB8A]...). So a cold dial-up call always starts with base cmd 0x14 (answer) or 0x17 (originate) = line analyzers, which is exactly what we see (`14 715D`, `17 705D`). The base image is therefore the intended DSP at that point; overlays come later.
- The a518:1D4C function with actions 7600..761C (0x7604 sets [0x685]|=1 and [0xB8A]=1) belongs to the `&T` self-test commands, NOT to answering. [0x685] is the online / escape-sequence state (guard time [0xA97]); the overlay selection at 0xBBFA..0xBC82 therefore runs when going online (after handshake), not at call start.
- Type 0x08 handler (8F46:59A8) is a call-progress tone-cadence classifier: payload bits -> [0xBD7]/[0xBD8] (the go-online loop wants [0xBD7]&0x1C), counters [0xBDA..0xBE3], windows on [0x134]. Our originator's DSP reports 0x01/0x03/0x0B/0x81/0x83 payloads when the answerer's tone arrives, but nothing progresses.
- The answerer's type 0x16 flags message (word2 = [0x2F] energy-band flags) has NO handler in any key table found (60 tables dumped from the 8F46:035A dispatcher). Either the host ignores it (debug) or the real DSP posts the detect types (0x28-0x2F) from a different task that the base analyzers do not reach in our emulation (D8C1 receive task is called only when [0x2F] bit1 is set, set by the energy compares).
- Next: find where the type 0x28-0x2F/0x07/0x0B messages are posted in the DSP images (post routine 83C8 call sites with those constants) and why that code path is not reached (which [0x2F] bit / which host command / which received signal).

## 13. S-register documentation (3453c-s-registers.md, USR support page) vs firmware (2026-11-15)

- S-register block in RAM: S0 = [0x595] (S2..S5 at 0x597..). ROM default template at flash 0x7D54 (S0 template byte 140 is a flag, S2=43 S3=13 S4=10 S5=8 **S6=2** S7=60 S8=2 S9=6 S10=14 S11=70 S12=50 S21=10 S22=17 S23=19 S24=150 S25=5 S26=1 S28=8 S29=20 S32=9 S42=126 S43=200 S44=15 S54=64 S71..S78). Matches the doc except S6 (doc 0, firmware 2).
- Earlier `S0=1`/`S41=1`/`X1`/PULSE defaults were an artifact of the self-test path (8000:787E `mov [0x595],1`) that ran only because the Voice/Data button read as held. With the button released ATI4 shows S0=0 (doc: default 0, correct).
- Documented meaning of the registers the DSP receives: DSP commands `1C`/`1D`/`2A` carry **S28** (extra 3000/600 Hz V.32 answer tones, 0.1 s units), **S29** (V.21 answer tone duration, 0.1 s units) and **S9** (carrier recognition time, 0.1 s units); verified: `ATS29=40` makes the host send `1D 0028`. The audio does NOT change with S29 (identical output for S29=10 and 40) -> the DSP code that consumes it is not the code producing our tones (base cmd 0x1D handler 9BB8 only stores it).
- Doc facts useful for the expected call sequence: S54 default 64 = V.8 enabled (bit7 clear) and Call Indicate (CI) disabled (bit6); S27 bit3 = "disable 2100 Hz answer tone"; S29 default 2.0 s answer tone; S28 default 0.8 s of 3000/600 Hz after it (V.32 AA); S7=60 s carrier wait (matches the NO CARRIER at ~60 s); S9=0.6 s carrier recognition; S56 bits disable V.34/V.34+/V.FC; S58 bit5 V.90, bit6 V.92; S34 bit3 = V.23 enable; S27 bit0 = V.21 only.
- Conclusion: a real ATA with these defaults should give a 2100 Hz answer tone of S29 = 2.0 s then 0.8 s of 3000/600 Hz alternation, then V.32/V.22 answer signals (or V.8 ANSam first, S54 bit7 = 0). We emit a 1.1 s clipped burst, silence, then 1.1 s tone every 9 s with no relation to S29/S28: the answer-sequence generator never runs.

## 14. Quick reference card (3453c-qrc.md) (2026-11-15)

- Factory defaults printed in bold on the card = the `&F1` hardware-flow-control template: B0 C1 E1 F1 L2 M1 Q0 V1 X7 (Courier V.Everything default) &A3 &B1 &C1 &D2 &G0 &H1 &I0 &K1 &M4 &R2 &S0, S6=2, S13=32 (UG says 0), S54=64. Our firmware without an NVRAM profile came up as the blank template (X1 &A1 &B0 &H0 &R1); after `AT&F1` it matches the card (X7 &A3 &B1 &D2 &H1 &R2).
- The emulated chip now starts with that factory profile: `sys/nvram.bin` (made by `tools/diag/nvgen.py sys/nvram.bin AT&F1`, gitignored) is loaded by default; `NVRAM=<file>` overrides, `NVRAM=/dev/null` = blank chip (NVRAM CHECKSUM FAILURE only shows if the Voice/Data button is held).
- Result: DSP command stream and audio are byte-identical with and without the profile, so the stall is not a profile problem. Card notes for later: B1 = Bell answer tone / HST originate, S27 bit3 disables the 2100 Hz answer tone, S28/S29 as in section 13, &G guard tone.

## 15. BREAKTHROUGH: BMAR must not be written back (core bug, audit #15) (2026-11-15)

- Cause of the clipped noise burst and of the stuck handshake: `MADS`/`MADD` (and the `BLDD`/`BLPD` BMAR forms) wrote `BMAR = PFC` after a repeat; the manual says `(BMAR)->PFC ... (MCS)->PFC`, BMAR is unchanged. The tone/symbol generator (base code 0xACD5 task, loops at ACEC..ACF8) runs two consecutive `rpt #3; mads *-` filters that must use the SAME coefficient table; with the write-back the second one used the next 4 words -> broadband full-scale garbage.
- Fix: `if (legacy & 128) bmar = pfc` (default off) on the five sites in dsp/c5x_core.c. Commit e232df9.
- Result (single ATA, `tools/diag/ata_solo.py`): 2.15 s silence, 2100 Hz answer tone 3.3 s (V.25 ANS, pk 14000), then a 2250 Hz carrier for 3 s, no clipping. DSP task schedule: 1A=ACD5 (ANS) -> 875A (2250 Hz) -> B6E6.
- Two-modem call (`tools/diag/call2.py`, `out/bmar1/`): the originator now reacts: B transmits V.21-like FSK (980/1180 Hz), 1100/1200 Hz, then A sends data-pump-like signal (rms ~5150) with periodic 2250 Hz bursts every ~5.3 s. DSP now posts overlay requests itself (type 0x47 payload 6 at ~12.98 s -> host loads ov6 at 0x9D00 and ov8 at 0xDC00 through the HLE bank protocol) plus types 0x48, 0x6B, 0x34, 0x06 that were never seen before. So the "something it never switches to" was a core arithmetic bug, not missing overlay/mode logic.
- Lesson: the earlier suspicion that the core still lacked something was right; remaining unapplied audit items (RPTC reset, RPT whitelist, RETI/INTR context, delay-slot stack order, NORM RPT overshoot, SUBC OV/C, *BR0 wrap, TBLR/TBLW first-instruction-after-reset edge) should be re-evaluated with the same method: check against the manual, gate with call behaviour.

### 15a. 100 s call with the BMAR fix (out/bmar2/, tools/diag/call2.py 100)
- Both modems now exchange real signals but do not connect: A `RING`, then `NO CARRIER` at ~70 s; B `NO CARRIER` at ~62 s (S7=60 s). Timeline: dial 2.1 s, ringing 5.2, answered 8.4; A sends ANS 2100 Hz (3.3 s) + 2250 Hz from ~12.7 s; DSP-requested overlays ov6 (0x9D00) + ov8 (0xDC00) loaded by both around 27 s (type 0x47 payload 6); afterwards A keeps sending a wideband data-pump-like signal (rms ~5000) with a 2250 Hz burst every ~9 s, B sends occasional 980/1100/1180 Hz FSK-like bursts and 2250/2600 Hz bursts; no mode-start (0x28..0x2F) message reaches the host, so the supervisor stays in the 0xB912 wait loop.
- Next gate for core changes: the single-box `ata_solo.py` timeline (silence 2.15 s, ANS 2100 Hz 3.3 s, 2250 Hz 3 s) and the two-modem overlay request at ~27 s.

## 16. DSP clock = 5600 cycles/sample -> first V.34 CONNECT (2026-11-15)

- External core validation (06-core2-recheck.md, new core vs manual): no build issue on our side (their copy lacked c5x_cyctab.h); confirmed fixed #1/#9/#15/#17/N-1; new actionable item 06-NEW-2 (NDX mirror was change-detected) fixed here with an AR0 dirty flag. Other audit fixes applied this session (legacy bit restores old behaviour): SUBC sets C/OV (256), RPTC reset 0 (512), NORM modifies AR only when shifting (1024), LST #0 keeps ARB (2048), NMI sets INTM (4096), DMOV/MACD/LTD/MADD data move only in on-chip RAM (8192), CLRC INTM shadow (16384). None changed the audio by itself (solo ATA bit-identical before/after).
- Core sanity tests (`tools/diag/coretest1.py`): SUBC long division 100/7 = 14 r 2, 65535/3 = 21845 r 0; MACD FIR sum and data shift correct; sin routine 8B75 accurate.
- **Root cause of the stuck V.34 handshake: DSP_CPS.** The DSP symbol timer PRD = 0x419F (16800 cycles, trimmed +-5 by the 820C routine) must equal 3 codec samples (2400 baud at 7200 Hz) -> **5600 DSP cycles per sample, CLKOUT1 = 40.32 MHz** (= 7200 x 5600). Old guess 2083 made every DSP task run at the wrong rate relative to the sample clock. Now default (`DSP_CPS` env still overrides). Commit 5c47d9f.
- Sample rate 7200 Hz re-verified from output tone frequencies (ANS 2099 Hz, V.8 FSK 980/1180 and 1650/1850 Hz); 80186 clock 25.8048 MHz = 7200 x 3584.
- Two-modem call with the new clock (`tools/diag/call2.py 100`, `out/cps5600call/`): ANSam -> V.8 CM/JM (caller 980/1180, answerer 1650/1850) -> V.34 phase 2/3 (DSP messages 0x30/0x34-0x37/0x3C/0x3D/0x20 appear for the first time). Answerer prints `CONNECT 33600/V34/NONE` at ~39 s; the caller's DSP finished the same phases ~20 s earlier (19.7 s) but never prints CONNECT; both end `NO CARRIER` (~62-64 s).
- Open: why the caller does not report connect / why the call drops after ~25 s of data mode (type 0x20 payload 0x0C at 63.65 s = loss of signal?), link gain/echo parameters, the 3 s of 0x20 message bursts, and whether the DSP cycle model needs tuning (scan DSP_CPS 5000-6200).
- Docs STATUS.md / HANDOVER.md are still the old fax-mode versions: rewrite next.

### 16a. Legacy bits removed
The `legacy` switch bits (added as bisect aids after the wrong XC audit item) were unnecessary: git history is the rollback. All fixed behaviours are now unconditional in `dsp/c5x_core.c`; `c5x_set_legacy()` stays as a no-op for API compatibility. Solo ATA output is bit-identical before and after the removal. `ivec_legacy` (INTR fallback to the old vector slots) is still there because the firmware's `intr 17` relies on the ROM-stub model.

### 16b. Audit follow-up in the agreed order (cycle model, then serial/interrupt)
- Cycle model: block moves / MAC-family loops no longer double count (first word is in the table cycles, each extra repeat adds 1: TBLR RPT n = 3 + (n-1) = n+2 as in the manual); interrupt entry now costs 4 cycles and ticks the timer. Two-modem call afterwards: answerer still prints `CONNECT 33600/V34/NONE` (out/cyc1call). Also confirmed after removing the legacy bits (out/nolegacycall): same CONNECT.
- N-12: RETC/RETCD/XC no longer clear OV (manual: no status bits affected); BCND/BCNDD/CC/CCD still clear it when the OV condition is tested.
- Deliberately NOT applied: N-2 (serial IFR not cleared on trap: the manual contradicts itself, C3, and hardware must auto-clear for per-sample XINT), N-5/#19/N-17 (SPC RRST/XRST gating): the firmware never sets SPC (dm[0x22] stays 0), the codec path on this board does not use it, honouring XRST would silence the DSP; INTR K=1-4 save (firmware only uses intr 17).
- Still open from the audit: RPT whitelist, IN/OUT RPT port increment, *BR0 wrap, SMMR/LMMR AR step, delay-slot stack order, RPTB PAER, block-repeat lockout, IDLE2, register widths, memory-map/TDM/READY/clock-generator items.

## 17. Why only the answerer prints CONNECT (traced 2026-11-15; tools/diag/trace_connect.py, hooktrace.py, pcwin.py)

- A's `CONNECT 33600/V34/NONE` (result code AL=0x9D via the result printer 8000:9E60) is printed by 8000:3752/33xx when the data-answer routine b6aa returns (stack 33DE <- 3752 <- B78E <- B694), i.e. after the **error-control (V.42 detect / LAPM / MNP) negotiation** that follows the V.34 start-up. A reaches mode F4 / hook 4B28 at 30.8 s, spends ~15 s in that negotiation, finds no error-control partner (`NONE`) and prints at 45.9 s.
- B (caller): DSP phases complete at 19.7 s (mode F4, hook 49D7 -> 4B28, later 4DDC/4EAD for retrain steps, 4B28 again from 30.8 s). From ~31 s its supervisor sits (99% of the PCs) in the wait loop 8000:514E-515A: `test [0x32C],0x80 (abort); cmp byte [0x3CE],0; jne loop`. Caller routine 8000:5BAB (builds a frame at 0xC17, sends it, waits). [0x3CE] = protocol-engine TX state byte: set to 1 at 52E2/5316/5330 when a block transmit starts; the engine at 8000:4xxx advances it (1->2->3) and clears it to 0 on `cmp [0x3CE],3` (41B9/4640/4699). It never reaches 3 for B. At 62.27 s (S7 = 60 s after dialing) the abort bit is set (`or [0x32C],0x80` at 5BB1) -> NO CARRIER.
- So both ends fail at the same point: **user-data frames (ODP/ADP detection, LAPM) do not cross the data pump** (A sees nothing -> `NONE`, B never completes its transmit). The V.34 negotiation itself finishes on both DSPs.
- Both DSPs post type 0x20 messages (payload 0x0E/0x0C) once a second from ~20 s (B) / ~40 s (A) onward; the host table for state 4B28 contains type 0x20. Meaning not decoded yet; candidate for the data-transfer handshake (TX/RX data request or status).
- Ruled out as causes: interrupt-entry cycles (changes A's DSP timing by ~8 s but not the outcome), RETC/RETCD/XC clearing OV (identical DSP message logs with and without).
- Next: decode the type 0x20 handler (host) and the DSP code that posts it (DSP 802x/B94B area), then find what advances [0x3CE]/the TX hook chain [0x3AF..0x3B5] (8000:1004, 173E, 1852, 18E0) and why the DSP never delivers/accepts data bytes.

## 18. Type 0x20 message and the I/O port map around 0x40/0x60 (2026-11-15)

### Type 0x20 (DSP -> host): rate report
- Host handler in the data-mode tables (hook 8F46:4B28, flash 0x13F94): `in al,0x5E; mov ah,al; in al,0x5C; xor ah,ah` -> AL = rate index (payload low byte). It compares with `&N` ([0x600], 0 = variable) and the current rate ([0x3BC]), stores it in [0xB23], and (when the call parameters ([0x325] == 0x405E) say so) triggers a rate-change/retrain action through the pointers [0xAB8]/[0xABA]/[0xABE] and timers [0xAF4]/[0x3E5]. Both DSPs post `0x20 0x0000` + `0x20 0x000E/0x000C/0x000B` once a second (~1.06 s) in data mode: payload 0x0E = 14 = 33.6 kbps (rate table `&Nn`: 14 -> 28.8 on the card, index convention is the firmware's own). It is a periodic status/rate report, NOT the data path.

### I/O port 0x40 (host side) - what it is
- When the DSP is not running it is bank A byte 0 of the boot/overlay download burst (ports 0x40-0x4E, handshake ports 0x18/0x1A/0x1E).
- With the DSP running, host ports 0x40..0x5E (even) are the byte lanes of the DSP's 8 interface words 0x58..0x5F: host 0x40/0x42 = word 0x58 lo/hi, 0x44/0x46 = 0x59, 0x48/0x4A = 0x5A, 0x4C/0x4E = 0x5B, 0x50/0x52 = 0x5C, 0x54/0x56 = 0x5D, 0x58/0x5A = 0x5E (message type), 0x5C/0x5E = 0x5F (message payload).
- 8000:0FB0-0x1050 (`mov dx,0x40; out dx,al` with delay loops) is the fatal-error blinker (error code shown by toggling bit 3 of the port 0x40 latch [0x30F]); it is not a data path. Other `in/out 0x40` sites: 8000:564D/D7A4 and 8F46:39BD/46C0 read, 8F46:3AD4/477E write word pairs (0x40/0x42) = long-message words.
- Earlier suspicion (port 0x40 as data FIFO) was wrong; the real data channel is ports 0x60/0x62 below.

### The missing DSP -> host data word channel (found by tracing the caller's wait)
- INT0 event bit2 (port 0x1C bit2) calls the hook [0x2D3] (8000:0674). In data mode the hook is 0x2003 (set at mode start) or 0x2035/0x2082 (state-machine style: each call stores the next step in [0x2D3]); it reads **one 16-bit word per event: `in al,0x62` (hi), `in al,0x60` (lo)** into a buffer ([0x2D5+..], [0x8A2], [0x9C0]) and stops when its count is reached.
- DSP side: base code 84B7 = `out *,#0060` (one data word from DSP memory) followed (delay slot) by `lacl #4; samm #57` = write 4 to DSP port 0x57 -> host event bit2. The per-sample step 847A (called from the main loop 80CC) only runs the next step when DSP port 0x57 **bit 2** reads 1 (`bit 13,#7D` counts from the MSB: BIT n tests bit 15-n), then jumps through the state pointer [0x39E] (the sequence 848B..84B3 sends 6 words from AR1 pointers 0x307/0x3BA/0x385/0x30F/0x31C/0xBE6).
- The emulator never set bit 2 of DSP port 0x57, never stored the port 0x60 word and returned 0 for host ports 0x60/0x62, so the data channel was dead: the DSP sent a single word at boot and never again; the host hook never got data (this is the "[0x2D3] never raised" gap noted in FULL_SYSTEM.md).
- Fixed in sys/machine.py: DSP `out 0x60` stores the word and marks the channel full (port 0x57 bit2 = 0), the host read of 0x62/0x60 returns it and reading 0x60 frees the channel, port 0x57 writes with bit2 raise event bit2 (already modelled). Result: ~17 words per mode start now cross (caller 18 reads at 19.7 s, answerer at 30.7 s) and the hook ends in its idle state 0x2034.

## 19. Host<->DSP flag registers (host ports 0x18/0x1A <-> DSP port 0x56) (2026-11-15)

- Host side, bulk data engines (8F46:3AA0-3B2x TX, 39A5-3A9F RX, entry via the INT0 event bit0 continuation pointers [0x27B]/[0x27D]): flags are read with `in al,0x1A -> ah; in al,0x18 -> al`.
  - TX: `test al,1` = bank A free (word 0 at host ports 0x40/0x42), `test al,2` = bank B free (words at 0x44/0x46, 0x48/0x4A..); after filling, `out 0x18/0x1A` with 0x0001, 0x0002, 0x2000 ...
  - RX: `test ah,k` = DSP word k valid (k = 1,2,4,8,0x10...: words read at 0x40/0x42, 0x44/0x46, 0x48/0x4A, 0x4C/0x4E ...), processed through `[0x3B3]` (CX = [0x3BC]), acknowledged by writing 0x0100, 0x0200, 0x0400, 0x0800... (`out 0x18,al; out 0x1A,ah`).
  - At the start of a mode the host clears all flags (`0x18=FF, 0x1A=FF`) and writes each bit once (01, 02, 04...) as initialisation.
- DSP side: port 0x56 (memory-mapped MMR 0x56 or window 0xFF56) is polled ~2 times per sample by routines 82D2 and 8333 (`lar ar1,#FF56; and [0x7B]` mask; if non-zero it processes a word then writes the mask back with `samm #56`). DSP port 0x51 (window FF51) is read once per sample in the 820C routine (timing trim input), DSP port 0x50 is written by ov6 A4EE (bit shifting into FF48+INDX).
- Model (sys/machine.py): two 16-bit registers. E = host-visible (host reads ports 0x18/0x1A), D = DSP-visible (DSP reads port 0x56). A host write of 1-bits clears them in E and sets them in D; a DSP write of 1-bits clears them in D and sets them in E. E starts 0x0003 (both banks free), D = 0. DSP writes to its ports 0x58..0x5D now reach the host bank words (`BANKWR=1`, default). Before this the host read back its own last write (garbage flags), the DSP read 0.
- Result so far: the caller's TX state byte [0x3CE] clears and the hooks [0x27B]/[0x27D] now run through their state sequence (they never ran before); both modems exchange flag/ack sequences (400+ logged host flag writes, `Machine.flag_log`). A 100 s call (out/flagcall) was started to check what this changes at the result-code level. The polarity (host write = clear in E / set in D) is inferred from both engines' use, not from documentation.
- Tools: tools/diag/flags56.py (DSP writes/reads of ports 0x50-0x5F by PC, host flag writes), evt2.py (E, D, [0x3CE], hooks, data words).

### 19a. RESULT: both modems connect (2026-11-15, out/flagcall)
100 s call with the flag-register model: A `CONNECT 33600/V34/NONE`, B `CONNECT 33600/V34/NONE` (the caller never did before), no NO CARRIER within 100 s, overlays ov6+ov8 loaded by both at 27.4 s. After CONNECT B's DTE receives a stream of random-looking bytes (nobody sends): the descrambled data stream is not idle ones, so descrambler/scrambler sync or the receive data path still has a defect. Next: send known data both ways (ATD/ATA connect, then text from one DTE) and compare; check the idle pattern; analyse the byte statistics.

### 19b. User data crosses the link in both directions (2026-11-15, tools/diag/call_data.py, out/datatest)
`python3 -I tools/diag/call_data.py 120 TAG [MSGA] [MSGB]`: both modems print CONNECT 33600/V34/NONE at ~46 s; 4 s later A's DTE sends `HelloFromA` and B's DTE `HelloFromB`.
- A received exactly `HelloFromB` (10 clean bytes, nothing else after CONNECT).
- B received `HelloFromA` intact inside a stream of ~21 KB of random-looking bytes that starts right after CONNECT and runs regardless of whether A sends anything. So the answerer's receive path is clean, the caller's delivers garbage at idle: candidate causes: descrambler/idle-pattern difference between originate and answer direction, stray RX word/flag handling in the host RX engine (E bits 6/7/14/15 stay set on B), or the injected line noise floor (`NOISE`, default 8; Machine now reads the `NOISE` env). A noise-0 run (out/datatest_n0, saves A_rx.bin/B_rx.bin) was started to separate these.
