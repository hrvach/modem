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

### 19c. Why B's DTE gets random bytes (found 2026-11-15, not yet fixed)
Noise-0 run (out/datatest_n0) still gives ~21.5 KB of random bytes on B (entropy 7.98 bits/byte) and a clean `HelloFromB` on A: line noise is not the cause. The garbage ends exactly where `HelloFromA` arrives (offset 21522 of 21532).
Cause (tools/diag/ringstate.py): the modem->DTE output ring (0xC000-0xCFFF, byte reader 8000:4D40, read pointer [0x356], write pointer [0x34E], tail [0x358]) is initialised differently on the two machines: A has [0x356]=0xC000 (empty ring), B has **[0x356]=0x0000**, so B's reader streams its own RAM from address 0 upward until the pointer reaches the write pointer. Writers of [0x356] in flash: 0x52D4, 0x5302, 0xCB22 (mov [356],bx), 0x4D4C/0x4D54/0x10C05 (si), 0x47BA/0x4892/0xC91F (ax), and four `mov [356],0` at 0x113AF, 0x11876, 0x11D1F, 0x11E51 (candidates for B's 0: a path that runs only on the originating side, or a ring init that expects a value (BX/AX) from earlier state that our emulation gives as 0). Next: breakpoint those addresses on B, see which one sets [0x356]=0 and why A's path sets C000.

## 20. Hardware access inventory and what is still a stub (tools/diag/ioinv.py, 34 s call, 2026-11-15)

Host (80186) ports seen in a call: 0x00 (old DTE status, 87 reads, answers constant), 0x0C (3-4 accesses, unmodelled, returns `ports` dict), 0x10 (1 write: output latch), 0x12/0x14 (DIP, ring, ID strap), 0x18/0x1A (flag registers, modelled since 19), 0x1C/0x1E (events/overlay handshake), 0x40-0x56 (bank/mailbox lanes: B reads 6 words (0x40..0x56) 5198 times, writes 4 words (0x40-0x4E) 9917 times; A writes 4 words 4717 times and never reads banks), 0x58-0x5E (command/message), 0x60/0x62 (data words, 18 each).
DSP ports seen: writes 0x50 (ov6 A4EE `sach *` via AR0=FF48+INDX, 193 per call on B: bit-serial word written into the window FF50; value stored nowhere = STUB), 0x51-0x55 (init clear loop at 80A8, constant 0: nothing reads them back), 0x56 (flags), 0x57 (events), 0x58-0x5D (clear loop + bank words, modelled since 19), 0x5E/0x5F (messages), 0x60 (data word), **0x68-0x6C (written once at DSP init: `out` 0x000F, 0x0002, 0x0000, 0x0078, 0x0901 by 8048-8056, rewritten by mode setups; ignored: stub - looks like codec/AFE or serial-port configuration words)**. Reads: **port 0x51 is read once per sample (8212, `lamm #51`) and always returns 0 (stub)**: the 820C routine multiplies it by [0x0BF6] and compares with [0x0BF5] to choose PRD 0xBF7/0xBF8 (symbol-timer trim): it is a timing-phase input (probably a counter/phase from the codec/timer), so the symbol clock trim runs open-loop in the emulator.
DSP cmd 0x83: `table[0x83]` = 0xBF09 (jump-table data, table overrun) but 839B ignores commands > 0x7F (`sub #7F; retc gt`), so it is harmless; the host really sends `0083 0083` at start (timeout/sync token).
Word-sized I/O: only boot PCB init (8000:0421/800B, I/O-space PCB, handled by `_preg/_pwr` as words) and dead alternate copies in segments 9EB0/A7AE/A110 (`in ax,0x10` at 9EB0:B3C9) use `in/out ax`; none on live paths, so no truncation bug observed.
Garbage on B's DTE (not the V.42 detect pattern: entropy 7.98 bits/byte): the caller's frame transmit routine 8000:52BB is called at t=23.0 s with BX=0, CX=0 (5ECB) and sets [0x356]=0, [0x3CA]=0; the ring reader 4D40 uses [0x356]. A never runs that call. B's host reads 6-word RX blocks from the DSP continuously while A's host never reads banks, so the two sides' data engines are in different states; next step is to log B's RX blocks (host reads 0x40-0x56) and see whether they carry DSP RX words (descrambled data) or stale bank contents.

## 21. Core-3 audit pass (doc/audit/07*.md), verified against spru056d.pdf before applying

Applied (each checked in the PDF text, `pdftotext -layout spru056d.pdf`): cycle table fixes (direct B/CALL 4, BD/CALLD/BANZD 2, INTR 4, MADD/MADS 2 per 6.3 + App. B (the 06a summary says 3), LDP #k 2, RETCD flat 2); +1 cycle for peripheral MMR access 20h-4Fh; DMOV/LTD/MACD/MADD destination (a+1) must be on-chip RAM (07-NEW-4); reset clears ar0_dirty/int_inh/xc state (07-NEW-6); TRAP/NMI/INTR vectors IPTR-relative; c5x_set handles ST1/PMST (#32); RPTB PAER = operand (last word) and BRCR stays 0 after the loop (#8, #31); IN/OUT under RPT increment the port and cost 2 per access; XC and the following 1-2 words are uninterruptible (N-13).
Not applied (audit wrong or irrelevant here): #18 XC counts words (manual: n=2 = one 2-word or two 1-word instructions); 07-NEW-1 default-mode (cyc_model=0) block-move cycles (machine always runs cyc_model=1); N-2 serial IFR auto-clear (manual contradictory); #19/N-5/N-17 SPC XRST/RRST (firmware never sets SPC); clock generator/TDM/READY/wait states (no firmware use).
Two-modem data call after the changes: both CONNECT 33600/V34/NONE at 46.4 s, A gets HelloFromB, B still receives ~21.5 KB of garbage before HelloFromA (core timing is not the cause).

## 22. DSP peripheral/MMR inventory vs Table 9-1 (tools/diag/mmrinv.py, core counters c5x_mmr_count/pc/val, c5x_ext_count, c5x_rsv)

Accessed by the DSP in a call (A answerer / B caller): AR0-7, IMR 04, IFR 06, PMST 07 (init 0x00B0: AVIS+OVLY+RAM), RPTC/BRCR 08/09 (BRCR used as scratch: 250k-1.2M writes), TREG0-2, DBMR 0F, INDX/ARCR 18/19, BMAR 1F, DRR 20 / DXR 21 (one per sample), SPC 22 (2560-3200 reads, 8-10 writes), PRD 25 (584k writes: symbol-timer trim, 821C), TCR 26 (init 0x20), PDWSR 28 = 0x000A, IOWSR 29 = 0x0001, CWSR 2A = 0x0010, CBSR1/CBER1 = 0BD0/0BDF, CBSR2/CBER2 = 0058/005D, CBCR 1E = 0xEF (AR7 circular over 0BD0-0BDF, AR6 circular over the six host-bank words 0x58-0x5D), 0x32 (TSPC/BSPC position, init value F8, 4-10 writes), I/O ports 50 (write 0x8000 once), 51 (read per sample, always 0), 56, 57, 58-5D, 5E, 5F.
Modelled: all processor regs, circular buffers (match Ex. 5-13), DRR/DXR/timer (TIM/PRD/TCR), host ports 56-5F, data word port 60.
Not modelled / stubs: (1) wait-state generator: PDWSR=0x000A means program 0000-7FFF has 2 wait states, 8000-FFFF (where the code and all data run) 0; IOWSR=1 gives I/O accesses a wait state (all IN/OUT and the memory-mapped ports 50-5F, which the DSP polls ~1.2M times per call): our cycle count is therefore a little low; (2) port 51 timing-phase input (always 0), port 50 write sink; (3) 0x32 TDM/BSP control (reserved on the C51: harmless), I/O ports 68-6C config words; (4) SPC state machine (RRST/XRST, FSM/ DLB bits); (5) reads of reserved data 0x0500-0x07FF (ov6 filter loop overruns by one word: AD78/ADA7, returns external SRAM) and 0x0080-0x00FF; (6) OVLY/CNF are ignored in the data map (0800-0BFF is always on-chip; PMST sets OVLY=1 so this is right for this firmware); (7) AVIS.
External data space (>=0x0C00) is plain unified SRAM: no DSP data access outside 0BC00-FFFF besides those.

## 23. core-fix-list.md (53 entries) - all read, checked against spru056d.pdf (pdftotext in scratchpad), applied where right

Applied: delay-slot instruction cycles now add to the delayed branch (manual Ex. 4-3: BCNDD 2 + OPL 2 = 4) and the NDX mirror runs between slot words; RETD/RETCD pop after the slot (6.3 RETD); plain INTR for INT1-INT4 (K=1,2,3,9) saves context (audit said K=1-4, but K=4 is TINT; 4.8.7 says INT1-INT4); SMMR/LMMR evaluate the address once, source MMR fixed, repeat costs 2 per access (6.3 SMMR); last word of a block repeat is not interruptible (4.7.2); IDLE2 stops the timer and only RS/NMI/INT1-4 wake it (4.10.2); I/O wait states from IOWSR/CWSR (the firmware programs IOWSR=1, CWSR=0x10: ports 0000-1FFF get 1 wait state, reads +1 cycle, writes unaffected below 2 ws - Table 9-7); reset values PDWSR/IOWSR FFFF, CWSR 0F, DRR/DXR/SPC 0; CBCR 8 bit, CWSR 5 bit; legacy bits removed (nothing reads `legacy`), dead sat_acc_shift removed, zero -Wall -Wextra warnings, watch_hits uses the executing PC.
Rejected / not applied: XC word counting is right (manual: n=2 = one 2-word or two 1-word instructions); *BR0 + circular wrap (manual never combines them); Ex. 7-6 pipeline collision (needs a pipeline model; firmware does not depend on it); FF50-FF5F host window (board hardware, not in the C5x data map); ivec_legacy second loop (the firmware's `intr 17` reaches the INT4 handler through it); OVLY/CNF/MPMC/AVIS/TDM/READY/clock-generator/BIO-pipeline; default-mode (cyc_model=0) cycle counts (the machine always runs cyc_model=1); RPT repeatability whitelist and taken-to-fall-through classification (not hit by this firmware); serial XINT/IFR/SPC items (firmware never programs SPC; machine drives the serial port itself); SARAM same-block cycle extras.
Result: two-modem data call output identical to before (CONNECT 46.4 s, A gets HelloFromB, B still receives the ~21.5 KB garbage run): the DSP work per sample finishes inside its cycle budget, so instruction timing changes do not move the results.

## 24. Chasing the caller's garbage run (tools: rxblocks, rxsrc2, cmdseq, statewatch, wr6f)

Findings (call-time seconds, both modems identical firmware):
- The garbage is a real DSP RX stream: B's DSP (ov6 data pump, bit packer 8317/8333/B55C, ring at 0x240 with [0x28]/[0x29] pointers) writes random bytes into its bank words (writer PC 0x8343) while A's DSP is still running base-image code (tone generation 8B1A sin/cos, FIR 9840-9863), i.e. A has not reached its data mode. B's host starts delivering RX bytes to the DTE at its CONNECT (26 s) and the stream ends when A's CONNECT arrives (46 s): fixed ~21.5 KB because the transfer is bounded by that window and the host RX engine rate.
- DSP status word [0x6F] (writers 87E1 = state set, A4BA/A4BC, A3F8, A432/A44D, B062, 8CA6, 8DC1/8DC3, A464/A466): both DSPs walk through the same phase sequence but each waits 10-15 s per phase: A sits in 0x0153 from 21.55 to 36.11 (14.5 s), B in 0x0ECC from 20.16 to 30.77 (10.6 s); then both go through repeated 0CC3/0CCF / 08E4-09E0-0CC4-0CCC cycles every ~2.4 s (43.8, 46.2 ...), which look like retrains. A V.34 start-up phase takes about 1-2 s on real hardware, so the waits are time-outs: some detector never fires on either side and the modems only advance on a timer.
- Commands: A's host sends nothing to its DSP between 27.4 s (overlay load) and 52 s, B sends 0x0A/0x57 at ~34 s; message blocks 30/03/35/36/37/02 + 20 (rate report) arrive on B at 32.8 s and on A at 52.2 s (19 s later).
- Link gain is not the cause of the slow phases: GAIN=0.5 reproduces the baseline timing to 0.01 s (gain probably clamped/unused below 1), GAIN=2.0 sticks A in state 0x0043 for the whole 40 s.
Next: identify which per-sample detector the waiting states poll (A: 0x0153 handler via [0x4B] script table at 999B-99F0 in base code; B: 0x0ECC) and which of our stubs/line-model properties starves it (port 0x51 timing phase input, line noise floor/level, signal delay/echo model, sample-clock alignment between the two machines).

## 25. i186.c fixes from fix-i186.md (checked against i186-manual.pdf)

Applied (sys/i186.c, test: tools/diag/i186_audit_test.py, all vectors pass):
- IDIV word INT32_MIN/-1 no longer crashes the host (64-bit divide) -> INT 0.
- BOUND: type 5 is a trap (return = next instruction, IP offset not linear address); reg operand -> bad opcode.
- TF single-step (INT 1 after an instruction that started with TF=1; vectoring clears TF).
- Interrupt shadow after STI / MOV Sreg / POP Sreg; STI;CLI leaves the IRQ pending.
- NMI (i186_nmi) incl. wake from HLT; IRQ vector masked to 0-255; reset clears IRQ/NMI/shadow; reset CS:IP = FFFF:0000 (flash reset vector uses a far jump, same linear start).
- REP string ops are interruptible between iterations (rewind to the first prefix, CX reduced).
- Word access straddling pages that route differently (MMIO/RO/RAM) is split into byte accesses (fixes the RO-byte overwrite and the dropped hook byte); same-routing words keep the single hook call.
- AAA/AAS adjust AL and AH separately; DAA/DAS follow the manual (second test on adjusted AL > 9FH, +-6 carry/borrow goes to CF). The audit's DAA claim (AL=FA -> 00/CF=0) is wrong: the +6 carries out, so silicon/MAME give 60/CF=1; the old core already did that.
- SAR clears OF for counts != 1; byte OUT keeps the high byte of the ioarr slot; calloc/NULL/id/range checks, i186_free.
- Cycle model per Table D-2: MUL 26-28/35-37, DIV/IDIV 29/38 (the audit's "44-52/53-61" and my first guess were wrong; the manual says 29/38 for both), shifts 5+n / 17+n and 2 / 15, JCXZ 6/16, string ops single 14/22/15/12/10 and rep 8n/22n/15n/11n/9n.
Not changed, deliberately: HALT burn-to-end-of-slice (machine._run slices to the next event; changing it makes the host loop spin), ST_BADOP instead of INT 6 (diag tools rely on it), skip of a breakpoint on the first instruction of a run (this is how a run resumes past a breakpoint), permissive decoding of undefined encodings, ESC/WAIT, cyc_model validation.
Regression: 60 s two-modem call (call_data.py 60 i186chk) gives the same timeline as before: both CONNECT at 46.4 s, both messages delivered, caller still receives ~21.5 KB of garbage first.

User observation (answered call, ~11 s long beep, then a restart of the handshake, then connect): this is the same defect as §24: a start-up phase that ends on a time-out instead of on detecting the far end's signal.

## 26. Garbage chase, round 2: what the long waits are (tools: waitpcs, dmdiff, carrier_watch)

- Audio (out/i186chk wav, Goertzel per 0.5 s): answerer A sends 2100 Hz ANSam from ~12 s, then noise-like (INFO) from 14 s, then from 22 s to 34 s a perfectly steady periodic signal (identical RMS 4886 in every window, peaks at multiples of 150 Hz = V.34 probing tone L1) for 12 s. Caller B sends noise-like signal (rms ~5200) over the same window. This is the user's "long beep, then the handshake restarts".
- The two modems are NOT symmetric in time: A starts 8.6 s after B (answer event), but from the overlay request (msg 47 at 26.0 s on both) both DSPs are in lockstep: 34 at 28.0/28.1, carrier msg 04 at 28.2 (B) / 29.4 (A), 3D at 30.5/30.6, msg 37 at 32.7/32.8. Then B emits the full result block 30/03/35/36/37/02 at 32.8 s and the rate reports 20/.. at 33.8 s; A emits the same block at 52.2 s and 20/.. at 53.2 s (+19.4 s). Both converge again at 56.4/56.5 (41/42).
- The A wait state [0x6F]=0x0153 is a terminal script entry (count 0) of the handler script at 999B-99F0 ([0x3CB] = script pointer, [0x48]/[0x4A] = current routine/count; 998F fetches the next (routine,count) pair, count 0 = wait until other code changes [0x4B]). It is entered at 21.55 s via the host-command path (8DC1/8DC3) and left at 36.11 s when [0x6F] gets bit 7 from the carrier detector (87B6-87E1: energy filter 87A8/87B6, hysteresis counter, bit 0x80 of [0x6F] = carrier present; 83C8 pushes message 4 = carrier detected / 5 = lost).
- Detector variables (data page 7, DP=7): [0x381]=067E and [0x383]=7EC0 sit frozen for the whole wait and start moving only at 35.5-36.0 s, when A's DSP also starts running overlay code (return/next pointers 9D46/AB76). So the detector is not "reading too little energy"; it is not being stepped until A's DSP switches its processing at ~35 s.
- Open: what switches A's DSP into that processing at ~35 s (B's equivalent happens at 32.8 s with the same inputs?), i.e. why A's equivalent of B's 32.8 s event is 19.4 s late. Next probes: trace A's [0x4B]/[0x48] changes and the overlay request/answer messages between 32 and 36 s; compare A with B at the same relative state; then test line-model properties (delay, echo, noise) one at a time.

## 27. Sample rate: 7200 Hz in phase 1, 9600 Hz in V.34 phase 2/3 (user's tone measurement + AFE config table)

- User measurement of the old 7200 Hz-only emulation: phase 1 tones are standard (ANSam 2100, V.21 980/1180 and 1650/1850) but everything generated in phase 2/3 is exactly 0.75x standard (L1/L2 spacing 112.5 Hz, 64-sample period; tone A 1800 + guard 1350; tone B 900 Hz). Standard = 150 Hz spacing at 9600 Hz sampling (4 samples per 2400-baud symbol). DSP clock is 40.32 MHz (user checked the board): 40.32 MHz / 4200 = 9600 Hz, symbol timer PRD 16800 = 4 samples at 9600 Hz (my earlier "3 samples at 7200 Hz" was the same timer read with the wrong sample rate).
- The DSP programs the codec/AFE with 5-word entries from the table at DSP 0x816B (routine 8151 writes ports 0x68, 0x69, 0x6B, 0x6C; six entries, indexes match the six command words 010A..0620 at init). Entries: E0 (0F,0002,78,0901) init, E4 (0C,0202,90,0901) phase 1, E5 (0B,0808,9A,0926) phase 2/3. Call-time: both modems write E5 at 15.3-15.4 s; A writes E4 again at 20.0 s (until 32.8 s), B at 30.8 s (until 32.7 s); then both E5 within 0.07 s.
- A in E4 at 7200 Hz still transmits 1350/1800 Hz (tone A at 9600 assumption), so E4 is not a 7200 Hz selector by itself; working rule now: E5 (port 0x6B = 0x9A) selects 9600 Hz, E0 (0x78) selects 7200 Hz, other entries leave the rate unchanged (env AFE_RATE="78:7200,9A:9600" overrides). machine.py: Machine.set_rate (CPU clocks and DSP cycles per sample, host heartbeat divider), Link resamples when the two rates differ, Link.samples() is call time again (cycles since the audio reset).
- Result: 60 s call: both CONNECT at 42.8 s (was 46.4 s), messages still delivered both ways, caller still gets ~32 KB garbage; waits are still there (A 0x0153 13.4 s, B 0x0ECC 10.4 s), so the sample rate alone is not the cure.
- B's 0ECC exit test (ov6 9E6B-9E97): counter [0x336] must reach 4 consecutive evaluations of E/4 - T < 0 with E = [0x26A:0x26B] (32-bit energy, ~0x05AF1DBD) and T = [0x268:0x269] (~0x0021405F); E/4 - T stays +21.66 M (+-0.1 %), so the counter is reset every frame (writers 9E89/9E91). Looks like an error-energy convergence test (equalizer/echo canceller or similar): next, find who accumulates [0x26A:0x26B] and what its reference is. Link echo 0.2 does not change the 10 s wait. GAIN 0.5 / 2.0 earlier: no help / worse.
- New probes (all run on the builder, ~15x faster than local): portchg, afewr, scriptwatch, timerwatch, cntwatch, watchaddr, acctrace, bpdump, dspwalk, tonescan.

Correction to §27: the claim that port 0x6B (AFE config word) selects the codec sample rate is a hypothesis from timing correlation only; nothing documents it, and A transmits 9600-based tones while in entry E4. Default is now fixed 7200 Hz (AFE_RATE unset); the mechanism stays available as an experiment. What is established: the 40.32 MHz DSP clock, the 0.75x scale of phase 2/3 tones at 7200 Hz, and the config-table writes. Open: what hardware change (if any) moves the codec to 9600 Hz; look at 80186 port writes and DSP ports 0x50-0x55/0x68-0x6C in the firmware for a clock-divider register.

## 28. TLC320AC01 codec model: sample rate fs = 12000 N / (A B) (replaces the unproven table of section 27)

Source for the codec: tlc320ac01.pdf (user-supplied datasheet, text in scratchpad). The codec sits on the DSP serial port, not on I/O ports 0x68-0x6C:
- DXR stream (tools/diag/aicparse.py): a primary word with D1 D0 = 11 (the XINT handler at DSP 0x8189 ORs [0x6B] = 3 into the sample) is followed by a 16-bit secondary word (handler 0x81AF sends [0x6C]); format DS15-14 control, DS13 R/W, DS12-8 register address, DS7-0 data (datasheet 2.19). Routine 8149 queues one word (ACC = reg<<8 | data).
- Init words (every DSP start): 010A (reg 1 = A = 10), 0214 (reg 2 = B = 20), 0300 (A' = 0), 0409 (reg 4: input gain +6 dB, output 0 dB, monitor squelch), 0505 (reg 5: HPF disabled, IN+/IN-), 0620 (reg 6: conversion free run). Later only reg 2 is rewritten (0x12 = 18) plus reg 4 again at 20.0 s (A) / 30.9 s (B).
- Datasheet Eq. 20: conversion rate = MCLK / (2 A B). MCLK itself is not fixed on this board: the table at DSP 0x816B (routine 8151, 6 entries x 5 words) writes ports 0x68/0x69/0x6B/0x6C and a reg-2 word per mode. Fit: fs = 12000 N / (A B) with N = port 0x6B word: entries (N, B) = (120,20) 7200 Hz, (130,19) 8211, (133,19) 8400, (142,19) 8968, (144,18) 9600, (154,18) 10267 = 3 samples/symbol at 2400/2737/2800/2989(3000)/3200/3422(3429). The AC01 part is documented; the port-0x6B-as-MCLK-divider part is an inference from that fit (not documented anywhere), which also explains the user's measurement (phase 2 tones 0.75x at 7200 Hz = 9600 Hz sampling). AC01_MODEL=0 disables the model.
- machine.py: Machine._aic_feed parses new DXR words, _aic_update recomputes fs when N (port 0x6B), A or B change, set_rate changes CPU clocks / DSP cycles per sample; Link resamples when the modems' rates differ.
- Result (70 s call on the builder): both CONNECT at 31.2 s (was 46.4 s), caller garbage 12.8 KB (was 21.5 KB), messages delivered both ways. First phases now 1-2 s each: B 0x0ECC 18.25 -> 19.37 (was 10.6 s), A 0x0153 19.24 -> 21.81 (was 14.5 s). Remaining long wait: both modems in 0x0CCC / 0x0ECF from 24.25 to 32.4 s (8 s), the stage after the first E5 (10267 Hz) switch.
- Not modelled yet: AC01 input gain +6 dB (reg 4), DAC/ADC 14-bit format with two control LSBs, secondary words are still passed to the line as audio samples, HPF.

TODO (user request): split the AC01 model out of Machine into sys/ac01.py (register file, secondary-word state machine, 14-bit DAC/ADC format with control LSBs, input gain +6 dB from reg 4, high-pass filter, strip secondary words from the line audio, register reads, FC0/FC1/A' phase shift), called once per sample from Machine.

## 29. AC01 signal path (gain / 14-bit / secondary frames), line-loss scan

- machine.py now applies the TLC320AC01 register 4 gains (input +6 dB set by the DSP, output 0 dB; squelch/-6/-12/+12 variants), drops the two control LSBs (14-bit ADC/DAC), and keeps secondary control frames off the line (the DAC holds its last value during them).
- Line loss scan (call_data.py with GAIN env = link gain, two-process link, 60 s): GAIN 0.5 / 0.35 / 0.25 give identical DSP message timelines (the DSP's own level control normalises); GAIN 1.0 (= +6 dB net with the codec gain) overloads the receiver and the call never starts (same symptom as the old GAIN=2.0 test, which was therefore a missing-codec-gain effect). Use GAIN 0.5 as the default line loss from now on.
- Unchanged by level: both CONNECT at 31.2 s (A) / 28.7 s (B), caller garbage ~12.4 KB; B result block 18.2 s, A 24.2 s; both in the long 0x0CCC / 0x0ECF wait 24.25-32.4 s; msgs 41 (A) / 42 (B) at 32.4-32.5.
- Tools: link_mp.py (one process per modem, identical results, 1.8x faster), call_data.py LINKMP=1 GAIN=.. ECHO=.., MSGT lines (DSP message times in call time), 22.05 kHz wav writer. Builder limit: at most 3 pairs of processes at once.

## 30. The remaining 8 s wait is a mutual DSP detection time-out (host side explained)

- Host (80186) side: the V.34 start-up controller is a message-driven state machine: [0x298] = current state handler; routine 0x35A (flash 0x8F46:0x035A) looks the DSP message type up in a byte table (DI/CX) and jumps through a word table (BX); each state also arms a timer [0x13A] (0x3E8 = 1000 ticks = 5 s) with callback [0x13C]. Command 0x54 = rate select (routines 0x4FF4 / 0x500D pick the next rate index [0x3BC] +-1 from the allowed-rate mask [0xB2D], send `mov ax,0x54; call 0x258`, arg = index in [0xB31]); the other senders are at flash 0x14081 / 0x140CF / 0x139D7. Commands are queued in a TX ring ([0x29A..0x2CE]) and sent from the INT0 handler when flag E is set.
- Host state log (tools/diag/hoststate.py): B 4B28 at 18.28 -> 4EAD at 19.36 -> 4B28 at 24.24; A 4B28 at 24.24; both leave 4B28 for 4AD2 (rate select) at 32.40 (B) / 32.44 (A), i.e. both hosts wait in the same state for 8.15 s, and both DSPs leave the 0x0CCC / 0x0ECF wait at the same moment (32.42 / 32.48; B's exit is the ov6 A464 path after the 4-consecutive-detections counter, but at 32.4 both fire together). So the 8 s is a mutual time-out; the detector that never fires is the ov6 per-sample task 9DAF -> accum_9E6B (see doc/dsp-source/ov6): E/4 - T < 0 four times in a row, with E = [0x26A:0x26B] and T = [0x268:0x269], stays at +2e7 for the whole wait.
- Not level related (line loss 0.25..0.5 identical), not echo related, not sample-rate related any more.
- Next: identify E and T (what 9E6B accumulates: sums/differences of samples spaced 6 apart, squared) and what the other modem should be sending in that stage; compare against a V.34 phase-3 reference (TRN/PP training).

## 31. Codec rate sanity checks, timeline, what the wait stage is

- Call-time codec rate timeline (both modems): 13.35 s entry 4 (9600 Hz), 14.85 s entry 5 (10267 Hz), 19.2-19.3 s entry 4 (9600 Hz, probing: spectra show tones at exact multiples of 150 Hz), 20.8 s entry 5 (10267 Hz) and stays; the long wait (24.25-32.4 s) is in that last mode.
- Clamping 10267 -> 9600 (AC01_CLAMP=10267:9600) makes it clearly worse (A result block 24.2 -> 35.4 s, CONNECT A 31 -> 42 s), so the rate model matters and entry 5 really is ~10267 Hz.
- 9E6B decoded: Q = (|x0-x6|^2 - |x0+x6|^2/8)/64 on x/y streams, accumulated; E/4 - T < 0 four times in a row means "signal repeats with period 6 samples" = 2 symbols at 3 samples/symbol = V.34 S signal. Lag-6 autocorrelation of both TX streams is ~0 from 24 s on (noise-like, INFO1/PP-like), strong only in phase 1-2. Hypothesis: both sides wait for the other's S / INFO1, which the other is not sending in the expected form.
- Host side: CONNECT is printed by a host timer/message path (B 28.7 s, A 31.2 s) before the DSP training ends, which is the source of the garbage bytes.
- Tools: call_data.py prints MSGT/CMDT/RATET/AICT/LAG6; AC01_CLAMP, DELAY_MS env for experiments.

## 32. Line delay and noise experiments (two-process link, GAIN 0.5, AC01 model on)

| setting | A result block / rate report | CONNECT A / B | caller garbage |
|---|---|---|---|
| delay 0, noise 8 (default) | 24.2 / 24.9 s | 31.2 / 28.7 s | ~12.4 KB |
| delay 5 ms | same as 0 | 31.2 / 28.7 | ~13 KB |
| delay 10 / 30 / 40 ms | same as 0 (24.4-25.2 s) | 31.2-32.2 / 29.2-29.7 | 13-19 KB |
| **delay 20 ms** | **18.5 / 19.2 s (symmetric with B 18.4 / 19.0)** | **25.2 / 24.2** | A 22 KB, B 13.7 KB |
| delay 50 ms | call never starts (A stops after msg 48) | - | - |
| noise 150 / 400, delay 0 | phase 1 breaks (A: false carrier 04 at 12.3 s, ends 0E/05/07) | A none, B 21.7 / 24.7 | - |
| noise 150, delay 20 ms | A 29.7, B 20.9 | 36.8 / 34.3 | 12 KB |

- The handshake outcome depends strongly (non-monotonically) on the line delay; 20 ms synchronises both modems (result blocks within 0.1 s, both CONNECT earlier) but then both print CONNECT before data mode (garbage on both sides). That sensitivity (also 10/30/40 ms behave like 0) points at symbol-timing phase between the two modems: DSP port 0x51 (timing phase input, read once per sample by the 820C routine, the PRD +-5 trimming) is still a constant 0 in the emulator.
- Noise: the front end is level-sensitive at the bottom: peak noise 150 (~-65 dBFS rms) already trips the phase-1 carrier detector; keep NOISE small until the detectors are understood.

## 33. What the sibling project (~/Programming/courier-emu) confirmed, and the delay sensitivity decoded

Confirmed against the sibling repo (taken as correct): codec rates for the six table rows (7200 / 8210.53 / 8400 / 8968.42 / 9600 / 10266.67 Hz, from the port-0x6B word and the AC01 B register = our model); the AC01 secondary-frame protocol; our C5x core already matches its corrections (SUBC carry/OV, MAC/MACD TREG1/2 with TRM clear, repeated IN/OUT, false XC over the last RPTB word: tested, ACC=3); XF is a 3-sample strobe (122,754 falls / 368,262 ISR runs per call), not a codec reset. Its docs name the receive path (per-frame loop 9DAF calls 8837, A2A7 matched filter, 9E6B; acquisition gate 9E56 needs level [0x380:0x382] >= 0x445C).
Ruled out here (no change of the timeline): band-limited line (LINE_LP 3400/3800, LINE_HP 150), port 0x51 as a frame-phase counter (P51DIV 2/4/8, also at the bad delays), line gain 0.25-0.5, echo.
Delay sensitivity (DELAY_SAMPLES): 143 bad, 144 good, 145 bad, 148 good; 36/72/216/288 bad. Good = A and B enter the post-probing stage at 18.4 s (A 0BC3 -> 0FC7 -> 0ECF, B 0BC0 -> 0EC0 -> 0ECC). Bad = A goes 0FC7 -> 0153 (written by the error handler 8D66 when the per-frame countdown [0x31A] expires, i.e. the receiver did not detect the far end inside its window), both modems spend ~6 s in a retry (A 0153 -> 01D3 -> 0BD3, B 0050 -> 00D0 -> 08D0 -> 09D0) and meet again at 24.6 s. So the outcome is decided by whether the receiver's first detection (the 9E6B accumulator, Q = (|x0-x6|^2 - |x0+x6|^2/8)/64 summed over a short block) succeeds, which depends on the alignment of the incoming signal; it is not the symbol-timer loop (port 0x51).
Next: find what feeds the x/y streams of 9E6B (A2A7 output) and why the first window can miss; test other alignment-dependent inputs (sample phase of the incoming signal vs the 3-sample frame, i.e. delay modulo 3/4/12 at the rate in force).

## 34. The long stage is a rate-negotiation round, gated by a 20-consecutive-frames test (ov6 9F6C)

- Real Courier Phase 3 (sibling repo, x2-v90-protocol-selection.md): caller sends S (128 symbols), S-bar (16), PP (288), TRN (~2 s), then J until it detects the far end's S -> S-bar; the answerer sends J while waiting for the caller's S -> S-bar.
- Our S/S-bar bursts exist (lag-6 correlation windows: B ~15.7-15.8 s, A ~16.5-16.7 s); in the "bad" delay runs both modems restart phase 2 at ~19.4 s (A re-sends tone A at 19.2-19.4 and 20.4-20.7 s, 0FC7 -> 0153 via the error handler 8D66 when the per-frame countdown [0x31A] expires); in the "good" runs they pass to the post-TRN stage (A 0ECF / B 0ECC) at 18.4 s.
- The post-TRN stage (callback A478, DP 6) exits when [0x334] >= 0x14 (20 consecutive frames passing the test in ov6 9F6C-9FA0: four sums/differences of the current 4-word block [0x300..0x303] and the previous one [0x330..0x333], two energies compared with thresholds; the counter is reset to 0 whenever a frame fails) or [0x336] >= 4 (the 9E6B detector). Exit sends DSP message 41 or 42 (A482), and the host answers with command 0x54 (rate select, +-1 index from the allowed mask) and the DSP retrains: rounds at 28.2 / 32.5 s (good path) and 32.4 / 35.9 (bad path).
- Host commands in the good path: both 0A/57/0A at 18.4-18.5, B 0A at 20.1; then 54/0C (B 28.2, A 32.4), 54/0D (B 31.4), 54/0E (B 34.1, A 35.9). CONNECT is printed by the hosts around 24-31 s, i.e. before the DSP rounds finish.
- Injecting an ideal S signal into A's receiver for 22-23 s did not make [0x334] climb during the injection (max 3) but A's counter reached 26 at 24.26 s (no injection: exit at 28.2 s), so the receiver reacts to the far end's later signal, not to a synthetic S with my guessed carrier/phase.
- Open: what B/A transmit that satisfies the 9F6C test and when they start it (host command 0A at 18.4 / 20.1?); whether the 9F6C inputs ([0x300..303]) are the demodulated I/Q at the symbol rate. Tools: inj_test.py (INJECT_A), mp_dmtrace/trace_diff, call_data SBURST/CMDT/RATET lines.

## 35. CONNECT is a host timer; the DSP training is what is slow (not throughput, not the line)

- CONNECT is printed when the host's go-online flag [0x4DB] is set at 0x5500, which happens when the 20 Hz host countdown [0x3DE] reaches 0 (the tick routine at 0x5480-0x5560 decrements a set of byte timers). [0x3DE] is loaded (0x55E5: 0x37; observed start values B 0x3A = 58 at 18.25 s, A 0x85 = 133 at 24.24 s, i.e. 2.9 s and 6.65 s) when the DSP delivers the training-result block (30/03/35/36/37/02), and it is paused while the modem is in the retry state. So the host expects the DSP to finish training a few seconds after that block; ours takes ~10 s, hence the hosts print CONNECT early and B's terminal gets the DSP's receive noise until A is really in data mode.
- The host's result code is derived from [0x32B] = negotiated rate in units of 100 bit/s (table 0x31B5: 03 -> 300, 0C -> 1200, ..., F3 -> ...), set at 18.2 s by the handler of DSP message 0x20 (rate report, sites 0x13DC4/0x13DEE). Rate reports (0x20, payload = rate index) are then sent by each DSP every 0.75 s from ~24.9 s while it waits; B's index climbs 0C -> 0D, A reports 0E.
- DSP utilisation (tools/diag/dsp_util.py): never above ~82 % busy, ~50 % through most of the call, so there is no cycle-budget problem at 9600 / 10267 Hz.
- What is really slow is the DSP-side exit test in ov6 9F6C-9FA0 ([0x334] must reach 20 consecutive passing frames; observed bursts of 1-3 only until a later event): in real hardware it must pass within ~3 s of the result block.
- New tools: hoststate, rate_writers/flag_writers (breakpoints on stores), code_ret, entry3701, events_bp, poll_host, stream60, dsp_util; call_data prints MSGALL / CMDT / RATET / SBURST.

## 36. The exit test decoded; the S burst is detected but the receiver front end beats

- ov6 9F6C-9FA0 decoded and replayed instruction by instruction in a standalone core (tools/diag/replay9f6c.py). With SXM = 1 the constant at 9F89 is NEGATIVE (-24,150,016). E1' = K + 2*(7C^2+7F^2), E2' = K + 2*(7D^2+7E^2), where 7D=(a0+a3+b0+b3)>>2, 7E=(a2-a1+b2-b1)>>2, 7C=(a2+a1+b2+b1)>>2, 7F=(a3-a0-b0+b3)>>2 over the current block a=[0x300..303] and the previous block b=[0x330..333] (one symbol = two T/2 complex samples). PASS iff exactly one of E1', E2' is negative and the other lies in (0x06670000, 0x06670000+0x13320000); [0x334] counts consecutive passes and is reset on any failure; the stage exits at 20 (A478 -> A482 -> message 41/42).
- During a real S burst (128 symbols, 37-39 ms, TX spectrum correct: lines at 1960 +- 1711 Hz) the test passes with E1 = 269M, E2 = 0 (perfect S), but single frames fail every 8-19 frames (counter reaches 19 / 9 / 8 and resets), so 20 is never reached on the first attempt. Between the failures the block pattern jumps ((10936,-3840,-3840,-10950) -> (-8200,8200,8200,8200) -> its negation).
- The I/Q fed to A2A7 (a rational resampler: [0x21] counts 0x2A..0 in steps of 2 = 22 calls per 33 samples, output 2 per symbol) rotates ~80-90 deg per call inside the burst (correct for S) but its magnitude beats between ~370 and ~9700 with the 22-call polyphase cycle ([21] = 1C / 0C are the nulls).
- Ruled out: sample slips in the emulator (ticks == samples consumed, no underruns 15.5-18 s), DSP cycles per sample (clock scaling with the codec rate: identical timeline), MAC/LT/LTP/LTS/MPYA/SQRA/SQRS/PM-shift implementations (match the manual), DMOV delay-line shifting (tested), TX signal correctness. The coefficient pairs in [0x3F6],[0x3F7] are not words of any DSP image, so the polyphase bank is generated at run time (who writes program memory at 0xB46F.. is the next thing to check).
- Tools: test9f6c / replay9f6c / a2a7trace / sspec / sample_slip / dsp_util; DSP_CLK_FIXED=1 restores the old dsp_cps scaling.

## 37. Trying other firmware images (IDSDL302.ROM, fw/ID20_403, fw/V90XX, fw/ID25_403)

- Machine changes: FLASH / CPU_HZ / DSP_HZ env overrides (defaults unchanged: SV25.flash.bin, 25.8048 MHz CPU, 40.32 MHz DSP); the boot-block CRC word at flash 0x77FFE is now COMPUTED with the loader's own routine (fc00:03e0, over file 0x40000-0x77FFD, init 0xFFFF; _boot_crc) when the image has FFFF there (XMD images never carry it; SDL.EXE writes it after programming) - gives 0x1735 for SV25 as before; Intel-style flash autoselect (0x90 -> manufacturer 0x0089 / device 0x4470 at 0xFFFF0/2, 0xFF -> read array) for the newer boot block's chip probe.
- fw/*.XMD decoded with sv25_decode.py to fw/decoded/*.flash.bin (not committed).
- IDSDL302.ROM (supervisor for the 20.16 MHz board; boots with CPU_HZ=DSP_HZ=20160000, Timer 0 ticks at 200 Hz) needs its settings in EEPROM words 94..102 and the extended block (sibling nvram.py: IDSDL302_SETTINGS / IDSDL302_EXTENDED); left erased the dial path sends 0xFF levels and the DSP dials silently. sys/nvram_302.bin = our nvram.bin + those two blocks. tools/diag/mknvram.py lets a firmware build its own NVRAM (blank EEPROM, AT&F, AT+SF, AT&W): it reproduces the extended block byte for byte, but not the six settings words.
- Two-modem call with IDSDL302.ROM (DSP 3.0.x): line setup works (dial tone, digit, ring, answer), the early phases (V.8, codec rate steps) run like the SV25 ones, but it never produces the training-result block; both modems drop at ~17 s (A msg 06, B msgs 04/0E/05/06) and keep retrying (rates cycle 9600/10267 then 8000/7200) until NO CARRIER. Worse than the SV25 image, not better. With CPU 25.8 MHz / DSP 40.32 it does not boot.
- fw/ID20_403 and fw/V90XX (7.4.16 era) boot to the AT prompt (ATI3: USRobotics Courier V.Everything) with firmware-built NVRAM, but a call does not start: B's host sends the usual dial commands (16, 1A, 1B, 13) while its DSP floods the host with message type 0x00 and transmits nothing; the DSP mailbox protocol of these images (tag/data cells 0xFF5E/0xFF5F, ack through port 0x57) differs from the SV25/3.02 model in machine.py. fw/ID25_403 boots the DSP but shows no terminal output. None of the images gives a better handshake; porting the mailbox model is a separate task.

## 38. S burst timing at the exit test (tools: latency, frames9f6c, txdump, cmdwin, stwin, bp9e26, dispm, exp_wait)
- B's DRR input is bit-identical to A's TX (latency.py: lag 20 samples, corr 1.000). Line/codec path does not lose the S burst.
- A's S: 16.607-16.659 s (128 symbols), exactly periodic over 42 samples, then S-bar (sign inversion, 16 symbols), then PP-like noise.
- B's exit test (ov6 9F6C) first runs at 16.6436 s; its input blocks are ~0 for ~8 frames then ramp (x2/frame) and pass from 16.6518; counter reaches 19 when the S-bar inversion arrives and is reset: 1 frame short of 20. After that every later pass-run is also < 20 (pattern jumps in the PP part).
- B's stage is armed ~16.595 s (callback [0x6D] 9D88 -> 9DCF -> ... -> 9F62) independent of A's S (arrives 16.610); the transition is gated by a DP7 counter (cell 0x38A vs 0x4B = 75 ticks, routine 9DF6) so the test starts ~80 symbols into S.
- Open: whether the 75-tick wait / arming time / input ramp match real hardware. Not established. DELAY_SAMPLES sensitivity (143 bad, 144 good, 145 bad) is consistent with the 1-frame margin.
- 8K on-chip ROM (courier-emu artifacts/dsp-onchip-rom-20mhz-8k, fw/c5x-onchip-rom-8k.bin) loadable with DSP_ROM=1: identical result; the firmware never executes 0000-1FFF in a call. Not the missing piece.
- SV20.XMD (CPU 20.16 MHz, DSP 40.32 MHz): boots to OK, NVRAM buildable, call does not start (DSP floods message 0x08/0000), same as the 403 images: different DSP mailbox protocol.
- Clocks used for SV25: CPU 25.8048 MHz, DSP 40.32 MHz (defaults, no env).
- Clocks (updated): CPU default now 25.000 MHz (50 MHz oscillator /2, owner's board reading); 25.0 run: CONNECT A 37.5 s / B 35.0 s, same garbage defect; 25.8048 MHz run: 31.2/28.7 s. Timeline differences are consistent with the marginal exit test, not a clock cure. DSP 40.32 MHz confirmed by timer PRD 0x41A4, TCR TDDR=0.
- Clocks (final): CPU default back to 25.8048 MHz (baud table + sibling project agree). 25.000 MHz was tried: works, CONNECT later (37.5/35.0 s), same defect.

## 39. Gaps vs the sibling (courier-emu) closed one by one, each tested with a 45 s dual call on the builder

Baseline: CONNECT A 31.24 / B 28.72 s, messages both ways, B garbage 18587 bytes.
- XINT: checked against SPRU056D 9.7 (SP: XINT on the XRDY 0->1 transition = DXR copied to XSR; no XINT if DXR was not reloaded). `xint_mode=1` already matches; the sibling's every-frame XINT is a simplification. No change.
- Step 2: DSP INT2 (ASIC mailbox, raised on the host's write of port 0x5E) and INT3 (AC01 FS, every frame) wired (`INT23=0` disables). Result identical.
- Step 3: DSP I/O ports without a model read back the last value written (`PORT_RB=0` disables). Identical.
- Step 4: AC01 secondary frame at half a primary interval (`SEC_FRAME=0` = old model): INT3 + serial tick with DRR = 0, no ADC word consumed, no DAC sample. CONNECT unchanged, messages delivered, B garbage 18587 -> 12419 bytes.
- Step 6: data-space SARAM (0x800-0xBFF) only with OVLY, B0 leaves data space with CNF (`dm_internal(c, a)`). The firmware runs OVLY=1 RAM=1 CNF=0, external data is only touched at 0x8000+ (tools/diag/memmap_probe.py), so identical. FF60/FF61 are the timer ISR's context-save cells (820C ldp #1FE), plain RAM here.
- Step 7: undefined opcodes (0F, 63-67, D6, F1; SALC removed) raise type 6 with the faulting IP instead of stopping with ST_BADOP (`UD_TRAP=0` restores the stop). Identical: the firmware never executes one.
- 8 kHz line path (sys/resamp.c, `LINE8K=1`): worse (A received nothing), default off.
Test script: scratchpad bt.sh (tar sys/dsp/tools to builder ~/sv25/cur, build, run call_data.py 45).
- i186 vs sibling x86 (tools/diag/x86_fuzz.py differential fuzz, REP=1 for string ops; tools/diag/x86_spec.py checks flags against the maths): ~8500 random single instructions. Only real bug in ours: PUSH SP pushed the decremented SP (8086); the 80186 pushes the old value (fixed, sys/i186.c). REP string ops, ENTER/LEAVE, PUSHA/POPA, IMUL imm, XLAT, AAM/AAD, Jcc/LOOP/CALL/JMP/RET forms: 0 mismatches. All other differences are sibling gaps (UcError for reg-operand LEA/LES/far forms, FE/FF groups, div overflow; OF never set by rotates/shifts; AF in ADC/SBB with carry-in; 82 alias; PUSHF bits 15-12 cleared). Ours keeps PUSHF bits 15-12 = 1 (8086-class), DAS/DAA with the manual's adjusted-AL > 9FH test, SALC (D6) now undefined -> type 6.

## 40. courier-emu C5x core swapped in for ours (DSP_CORE=sib): same behaviour

- dsp/sib/ = copy of ../courier-emu/native/c5x_core.{cpp,h}, c5x_ops.ipp, c5x_optable.ipp (BSD-3, LICENSE) with small patches (diff vs dsp/sib/orig/): all members public; `m_shim` mode: host window data 0xFF50-5F -> I/O callback, DRR/SPC ready bits and XINT driven by the shim's serial_tick (same rules as dsp/c5x_core.c, xint_mode=1), DXR write ring. c5x_sib_shim.cpp exports our c5x_* C API on top of it; build with dsp/sib/build.sh (clang++; g++ also fine, no stack growth); dsp/c5x.py picks libc5x_sib.so when DSP_CORE=sib. Diagnostics (iolog, PC ring, hit counts, breakpoints, watch) are stubs in this mode.
- Differences from our setup: vectors come from the real 8K on-chip ROM stubs (fw/c5x-onchip-rom-8k.bin, MP/MC=0, SIB_ROM= to disable) instead of ivec_ind; external RAM shared window 0x0080-0xFFFF; no I/O wait states / our manual cycle table (its own cycle accounting); TIM/PRD = FFFF at reset as ours.
- 45 s dual call on the builder, ours vs sib: DSP message and host command timelines identical to 0.1 s (MSGT/CMDT/RATET), same rate steps, CONNECT A 31.24 / B 28.72 s, A receives MSGB, B receives MSGA, same garbage defect (B 12419 vs 12441 bytes of noise). So the C5x core is not the cause of the exit-test / garbage problem.

## 41. Circular buffers and the A2A7 table checked (tools/diag/a2a7bank.py; builder run, B from 16.0 s)

- Circular addressing (CBSR/CBER/CBCR): dsp/c5x_core.c upd_ar compares AR with CBER before the update for every indirect modify, both directions, as SPRU056D 3.4 says (the sibling core does the same). A2A7 itself does not use it (DMOV, `*0+`/`*0-`, TBLR).
- A2A7 (ov6): `[DP:21]` -= 2, reload from `[DP:20]` when it reaches 0 (`xc 1,leq` + `dmov`), then `tblr` copies two program words from `[DP:3C] + [DP:21]` to data 3F6/3F7 (DP = 0x380: [3C] = 0xB46F). The "polyphase bank" is a table of unit phasors, not filter taps: 21 pairs at B46F..B498, |z| = 16384 +- 0.5, angle step -68.571 deg (= -4/21 turn) per entry, closing exactly after 21 entries (4 turns). The pair at B499/B49A (index 21, -27.0 deg) is never read. The table is byte-identical to the ov6 image (so the earlier "not words of any image" was wrong; it is data listed as code at B46F).
- Sequence observed: offsets 0x28, 0x26 ... 0x02, 0x00, then back to 0x28: 21 calls per cycle with [20] = 0x2A. The note in section 36 says 22 calls per 33 samples (3 samples = 2 calls), which would need [20] = 0x2C and a 22-entry cycle. Lead: [20] is computed by the SFR/XC NC loop at ov6 A41F-A426 (halving); if that loop yields 0x2A where the design intends 0x2C (carry/SFR/XC NC semantics), the mixer period and the sample-rate ratio disagree and the I/Q magnitude beats with the cycle. Not yet tested.
- Follow-up (tools/diag/a2a7reload.py, builder): the reload cell [DP 0x380:0x20] = [0x3A0] is written once by ov6 A6E2-A6F6 from a selector table: the pair (table base -> [0x3BC], reload -> [0x3A0]) is read from A6FE + 2*idx, idx = a nibble of the selector table at A6F8. The four pairs are (B4B5, 8), (B4A3, 18), (B499, 10), (B46F, 42): reload = 2 x number of phases (4, 9, 5, 21) and the four tables are laid out back to back (B46F+42 = B499, +10 = B4A3, +18 = B4B5). So 0x2A is the designed value for the 21-phase table (idx 3, the 10267 Hz case), and the "unused entry" at B499 is simply the first phasor of the next table (5 phases). The off-by-one hypothesis of the previous paragraph is FALSIFIED: nothing wrong with [20], the table or the counter logic. The "22 calls per 33 samples" statement in section 36 is not supported by this code; the mixer period in that mode is 21 calls (4 turns).

## 42. The DSP clock is fixed; what is and is not derived from it (2026-11-15)

- The C51 has no software-programmable PLL (CLKMD pins, SPRU056D 9.2; PLL options only on LC56/C57S/LC57). DSP clock 40.32 MHz (owner), ASIC drives CLKIN (sibling asic-pinout.md pin 119). sys/machine.py now defaults to a FIXED clock: DSP cycles per codec sample = DSP_HZ // rate (5600 @ 7200, 4200 @ 9600, 3927 @ 10267). DSP_CLK_FIXED=0 restores the old model (5600 per sample at every rate = DSP clock following the codec, which was derived from "PRD 16800 = 3 samples" and is physically wrong).
- Firmware facts: TINT is a bare `rete` in these images (data[0x63] only written at init, tools/diag/tintslot.py); the timer is not the symbol clock. PRD = 0x41A4 / 0x419A (16805 / 16795 cycles) at every codec rate.
- Nothing audible reveals the clock: DTMF digit, V.8 300 baud FSK and everything up to the stall are identical to the sample at DSP_HZ 20.16 / 40.32 / 80.64 MHz (tone and bit timing are sample-driven). Only the compute budget depends on it.
- Budget (tools/diag/overrun.py, demand at 161 MHz): at 10267 Hz the heavy work comes once per symbol (3 samples); worst symbol needs ~10,200 cycles (1 cycle/instr, CYC0=1) to ~11,700 (manual cycle table) against 11,781 available at 40.32 MHz: the DSP fits with 1-13 % margin. 20.16 MHz is impossible; the timeline is very sensitive to the cycle model. PDWSR = 0x000A: code and data at 0x8000+ run with 0 wait states.
- ASIC mode table at DSP 0x816B (6 rows x 5 words, routine 8151): fs = 1200 * w2 / B (w2 = 120..154 -> ports 0x6B/0x6C words, B = low byte of the AC01 register word 0x14/0x13/0x12), i.e. master clock 43200 * w2 Hz at A = 18: the ASIC has a programmable-ratio clock generator for the codec.
- Board measurement (sibling dsp-cpu-link.md): host INT0 free-runs at 2401 Hz = 40.32 MHz / ~16800, most likely the DSP timer (TOUT -> ASIC); it drives the host's fine timebase (dec [0x134] countdowns, 20 Hz CONNECT countdown, ring cadence). machine.py now raises the heartbeat from the DSP timer expiries (HB_TIMER=1, c5x_timer_expiries) instead of every 3 samples; HB_TIMER=0 = old model (only right at 7200 Hz; at 9600/10267 the host timers ran 1.33x/1.43x fast).
- Results (45 s call, builder): old clock + 3-sample heartbeat: CONNECT A 31.24 / B 28.72 s, B garbage 12,419 bytes, both messages delivered. Fixed clock only: same timeline, B garbage 46,318 bytes and B does not receive A's message. With the timer heartbeat: see below / next entry.
- Dead ends this round: sibling core swapped in (section 40, identical), circular buffers and the A2A7 table (section 41, correct), AT&N1 forced 300 bps call stalls after DSP message 4A at 13.4 s (no data phase), ID20_403 on the SV25 machine model: DSP message 00 at 0.9 s then nothing (mailbox protocol differs).
- Next: 403 family (DSP 3.1.2 / supervisor 7.4.16, fw/ID20_403, V90XX): mailbox documented in ../courier-emu/docs/dsp-cpu-link.md, mailbox-from-the-rom-dump.md, dsp-mailbox-board-fix.md, mailbox-312-comparison.md, board-verified-403.md.

## 43. DSP 3.1.2 / supervisor 7.4.16 (fw/ID20_403) on the machine model: boots, dials, rings, answers, handshakes up to DSP message 0x34 (branch fw-403-mailbox)

Run with IFACE=403 FLASH=fw/decoded/ID20_403.flash.bin NVRAM=sys/nvram_ID20_403.bin CPU_HZ=20160000 DSP_HZ=40320000 (80186 20.16 MHz = oscillator 40.32 / 2; DSP 40.32 MHz). Changes in sys/machine.py (all behind IFACE=403 except where noted):
- CPU side of the mailbox as on the board (courier-emu docs/dsp-cpu-link.md): port 0x1C reads 0xFC | (input register free) | (reply waiting << 1) (idle 0xFD), 0x1E reads 0xFF; the supervisor's ISR acks by writing the status back (bit 1 = reply taken); no TX-slot events, INT0 is the free-running heartbeat only.
- The SV25-only INT0 "TX event" shortcut (HLE stand-in comparing supervisor cells 0x29A/0x29C) is off in 403 mode. On the 403 supervisor those cells are unrelated, so INT0 fired at 7200 Hz instead of 2400 Hz, tripling every tick count; the ring-sense state machine (0x15015.., thresholds [0xCD1] = 24, [0xCD2] = 180 ticks) then never qualified a ring.
- DSP load: the 3.1.2 base image is 28327 words (SV25 27710): no fixed 55420 byte cut in 403 mode. The message sender's OUT 005E / 005F instructions are at 0x83D3 / 0x83D6 / 0x83DE (SV25: 0x83EB / 0x83EE / 0x83F6): in 403 mode the accepted PCs are found by scanning the loaded image (the fixed window 0x83D6-0x8420 dropped the tag write and produced a flood of tag-0 messages). XINT_MODE env (default 1).
- Result (tools/diag/call_data.py 45, builder): B dials, DTMF digit emitted (695.5 / 1210 Hz, ~60 ms) and detected by the exchange at 2.86 s, A prints RING at ~10 s and answers, both run V.8 / phase 2 with the same DSP messages and codec rate steps as SV25 (0x48, 0x47, 0x6B, 0x34; 8640 -> 9600 -> 10267 Hz at 16.6 / 18.1 s) and then both DSPs fall silent: DSPs idle (~30 % busy, PC 80FB), host sends nothing after 18 s, no CONNECT. Not a cycle-budget problem (peak ~2000 cycles). SV25 continues after its 0x34 (0x04, 0x3D, 0x37 ...). WAV: out/id20_403/.
- Open: what the 403 supervisor/DSP wait for after 0x34 / B's 0x00 at 18.39 s (stream pump 0x1C bit 2 / port 0x60 chain vector not modelled in 403 mode; INT0 stream events dropped); compare with the board-verified message sequence (docs/board-verified-403.md, x2-v90-protocol-selection.md).
- New tools: boot403, link403, dspscan, cmdwin2, hbcheck.

## 44. Per-firmware profiles; what the target image is; the stall is at a countdown expiry

- Target image (ATI7): USRobotics Courier V.Everything, external, options HST / V32bis / x2 / V90, supervisor 7.4.16 (04/30/98), DSP 3.1.2 (09/09/98), 'ID_SDL v4.03d 24/01/00, RUSSIA, Khabarovsk' community build, product type 'Russia (ex. US/Canada) External', clock 20.16 MHz, 512k flash, 64k RAM. The previous image is now a separate profile.
- sys/profiles.py holds everything firmware / board specific (flash, nvram, CPU and DSP clock, mailbox interface, DSP base size, sender scan, interrupt pointer presets, INT0 unset vectors, strap). Default profile = id20_403 (no environment variables needed); PROFILE=sv25 selects the previous one. Verified: plain environment gives the same boot and call as the explicit-env runs.
- Still unverified / open: board strap answer (hw_idx) for this supervisor (identity at 0x287f9, result [0x14b] selects behaviour at 6 sites); stream lane on port 0x60 / 0x1C bit 2; DIP defaults; tools/diag scripts with old-image addresses.
- Stall analysis (two ID20_403 modems, builder): both load overlays 6 (9D00) and 8 (DC00) at ~16.65 s (overlay 8 is the synchronous datapump and is not meant to run in async &M4 calls, courier-emu datapump-gate-403-addresses.md); after the codec rate step to 10267 Hz the DSP reloads its per-symbol countdown [0x31A] (~926 symbols = 0.27 s); at expiry the resident error path (0x8D60: sends DSP message 06, bumps [0x337], rewrites [0x6F], restarts the datapump entry 0x8DED/0x8E09) runs and the modem steps back to 9600 Hz (B at 18.39 s) while the other end stays at 10267 Hz. The flag word [0x39F] (datapump flag word, bit 6/7 pick the receiver family) loses 0x4040 at 16.967 s (writers 0x9031 / 0x9036 in the 0x9000 block; 0xD60A only clears bits 0 and 7). courier-emu codec-sample-rates.md describes the same symptom in the sibling's own pair runs ('the answering end falls back from B = 18 to B = 20 about 2.3 s in ... never transmits again'). LINE8K=1 (8 kHz PCM line) changes the failure (A falls back to 7200 Hz at 19.8 s) but does not fix it. WAVs: out/id20_403/.
- New tools: ovlcmp, revert403, cdwatch, entrychk, w6f.

## 45. Exit-test failure (first training attempt): what the measurements say (2026-11-16)

Image: SV25 (original XMD, supervisor 7.3.14 / DSP 3.0.13), call_data / frames9f6c / framecalls / align / txspan / txperiod on the builder.
- Coefficient table (0x12A-0x1CD) is installed by correct firmware (loader A2D1 -> A2E9, 16-tap seed read twice, same on both attempts); init routine A0DE runs once per attempt with a dense source (128 non-zero words). Not the cause.
- A's transmitted S is correct and phase-continuous: silence until sample 219777, periodic S (period 42 samples) from 219778 to 220165 = 388 samples = 129 symbols (3 samples/symbol), then S-bar / PP. A's codec ticks, DXR writes and XINT runs stay in lockstep (no repeated or dropped sample).
- B's receive path: A's tx and B's rx correlate 1.0000 at a fixed offset. Exit-test (9F6C) frames: first 12 frames fail while the filter output ramps (filter latency, not adaptation); with no disturbance the pass run is 26-27 frames (S window is ample).
- Delay sweep (DELAY_SAMPLES 140..151), longest first pass run: reaches 20 at 141, 145, 146, 147, 148, 151 (fixed DSP clock; 151 fails with the scaled clock); fails (9 then 16-17) at 140, 142, 143, 144, 149, 150. Fixed vs scaled DSP clock gives the same pattern: not a timer-vs-sample beat.
- The failing frame is a grid slip: at delay 140 one frame arrives 3 ticks after the previous one (6 normal), block pattern jumps (about -137 deg, i.e. two 68.57 deg mixer steps), E1'/E2' both ~42 M -> fail, counter reset. At delay 0 the first run is 19 then the same kind of frame fails (E1' = 11.4 M, below the 107 M floor).
- AC01 filter model (AC01_FILT=1: 6th-order LP, corner fs*B/40, bypassed at 7200 Hz; HP only if reg 5 DS02 = 0; AC01_LAT extra samples) with AC01_LAT=3: same timeline, same CONNECT times; B noise 87 KB in the longer run, HelloFromA not found. No effect on the first attempt.
- Mailbox / host: nothing is queued at 25.9 s on either host (SV20 and SV25); every queued command is sent at once and received by the DSP; no constant 0x20FF flood in the host port writes (34-38 s window).
- Open: why B's DSP shifts its frame/sample grid by one symbol inside the S (receiver symbol-timing adjustment?), and why that happens at some line delays and not others.
- Tools: align, txspan, txperiod, framecalls, slipwatch, tablewatch, regiondiff, hear, qwatch, portflood, datapath, memwatch, nvsettings.

## 46. Where the mid-S frame slip comes from (2026-11-16)

Tools: tools/diag/slipcells.py, symtrace.py, stagere.py (FORCE0=1 restores [0x34B]); dspdiff.py (differential test of one routine on both cores).
- Core check: routine 8CF3 (descrambler shift) gives identical results on our core and the sibling core over 3000 random states. Whole calls: at delay 140 both cores give the same timeline; at 141 they differ (cycle accounting). One-cycle-per-instruction (CYC_MODEL=0) moves the pass/fail pattern to a period of 3 delays (fail at 140, 143, 146, 149, 150, 151).
- Per-symbol scheduler (ov6 9F33): [0x34B] counts 49..0 once per symbol (every 3 ticks); the path alternates 9F3E (loop filter) / 9F6C (exit test).
- At 16.8629 (delay 140) the foreground task [0x70] = A12B (a step script, gated by countdown [0x71], tables at A068/A086; main loop 8790 does `cala` on [0x70]) fires for the first time and stores a 0/1 value in [0x34B] (A135), the same cell the ISR uses as symbol countdown. [34B] goes 6 -> 1 at delay 140 (odd jump, alternation flips, 3-tick frame, rotated block pattern, exit-test counter reset) but 6 -> 0 at delay 141 (even jump, alternation kept, 26 passes).
- The step fires at different times for different delays (16.863 at 140, 16.901 at 143, 16.904 at 149) -> its schedule depends on the line delay.
- Restoring [34B] to the expected countdown after the write (FORCE0=1) does not help (max counter 13-14): the step's own check consumes the value, so this is not a simple fix. Whether real hardware shares the cell the same way (benign there) is open. Next: read the A068/A086 step script and A136 check, find what the written bit means (sign of cross product of consecutive symbols = S phase) and why the ISR countdown is not reloaded afterwards.

## 47. The step script and the frame sync (2026-11-16)

Tools: tools/diag/synctl.py (stage entry / S arrival / A12B timeline), stagere.py (FORCE6F, FORCE0).
- Core fixes from pending-bugs.md / pending-bugs2.md applied (commits 3325468, 7bdd678): MMR read cycle, OUT RPT cycles, RETC taken, RPT interrupt gate, RPTB end-test order, BR0 wrap, TREG widths, XRST XINT, DRR/RSRFULL overrun, XC two-word lockout. Sweep 140..151 unchanged (reaches 20 at 141, 145-148, 151).
- ov6 main loop runs a step script (table A086 when [6F] bit 11 is set, as with [6F] = 0AC0): (function, symbol count) pairs: A12B after 44, A145 +2, A136 +1, A146 +16, A158 +2, A112 +14, A16D +256 ... Forcing table A068 at stage entry makes things worse (max counter 3-4).
- A12B = sign of the cross product of consecutive symbols, left in [0x34B] (0/1). [0x34B] is also the ISR's per-symbol countdown; its LSB selects the alternation 9F3E / 9F6C (BIT 15 = bit 0). So A12B deliberately writes the S pattern's phase into the frame alternation (flip or keep); A136 then requires an even countdown and re-checks the sign (fail path A0B8 steps the script back).
- Timeline is identical for all 12 delays: stage entry (9DFD with [6F] = 0AC0), S visible at frame 12 (filter refill after the stage init), A12B at frame 22 after entry. 9 passes before the sync step. No flip: 26 passes (to frame 38) = exit. Flip: counter resets, 17 more frames -> fail (needs 20). Flip written 1 at delays 140, 142, 143, 146, 149, 150, 151; 0 at 141, 144, 145, 147, 148 (144/146/151 are exceptions to flip-vs-fail, not explained).
- S ends for B at frame ~38 after entry: B's stage entry is ~26 frames (~15 ms) after A's S starts. Entering 3 frames (~1.7 ms) earlier would make even the flip case reach 20.
- Open: what triggers B's stage entry (host command 0x3D) and why it is ~15 ms later than A's S start relative to a real modem pair; check host timers, mailbox latency, 100k-cycle Link slices.

## 48. Command/message timeline around the first training attempt (delay 141, CPU-cycle seconds, tools/diag/cmdtl.py)

- 13.38 / 13.38  both DSPs report tag 47, hosts answer with cmd 0002 (13.3778 A, 13.3805 B), again 13.4156 / 13.4182
- 14.9937 B tag 34; 15.0431 A tag 34
- 15.1556 B tag 04;  15.9999 A tag 04  (A is 0.8443 s later than B)
- 16.8087 A tag 3D;  16.8542 B stage entry (9DFD with [6F]=0AC0);  16.8783 B tag 3D
- No host command is logged between 13.42 and the entry: the stage chain runs inside the DSP. B enters 1.6986 s after its own tag 04, A reports tag 3D 0.8088 s after its tag 04; so B's entry minus A's 3D = 1.6986 - 0.8088 - 0.8443 = +0.0455 s. Entry that is ~1.7 ms earlier would let even the flip case reach 20.
- Open: what the DSP waits on between tag 04 and the stage entry on B (countdown / level gate 9E56 / [0x31A]) and what sets A's tag-04 time 0.84 s after B's.

## 49. What the two DSPs wait on (delay 141, tools/diag/waits.py, CPU-cycle seconds)

Both DSPs run the same chain of callback states: 9D56 -> 9D5D -> 9D66 -> 9D88 -> (wait) -> 9DCF -> 9DD3 -> 9DD7 -> stage entry (0 with [32F]=88EB) -> B574 -> B59D / A3xx.
- A: 9D56 15.043, 9D5D 15.172, 9D66 15.321, 9D88 15.359, 9DCF 15.886, 9DD3 15.921, 9DD7 15.928, entry 15.935.
- B: 9D56 15.889, 9D5D 16.016, 9D66 16.166, 9D88 16.278, 9DCF 16.805, 9DD3 16.840, 9DD7 16.847, entry 16.854.
- Identical step lengths on both sides: 9D56->9D5D 0.127-0.129, ->9D66 0.150, 9D88 -> 9DCF 0.527 (fixed wait, same on both), 9DCF->entry 0.049. The only step that differs is 9D66 -> 9D88: A 0.037 s, B 0.112 s (0.075 s = ~770 samples at 10267 Hz).
- B's 9D56 (15.889) starts 3 ms after A's 9DCF (15.886) although the line delay is ~13.7 ms, so B's start is probably not caused by A's signal onset.
- Host side: the only host-driven DSP interrupts are INT2 (ASIC mailbox word, wired) and NMI/RS via the 80186 P1LTCH latch (bit 3 NMI, bit 1 RS, pulsed only during DSP boot/reset in the 403 supervisor, never at run time); INT1 (P1.7) is never driven and masked. Our machine raises INT2 on every mailbox word and INT3 every codec frame; NMI is not modelled (not needed after boot).
- Open: what 9D66 -> 9D88 waits on in B (0.075 s longer than in A), and what starts B's 9D56 at 15.889.

## 50. Who waits for whom: A and B state chains (LINK_SLICE=10000, delay 0; tools/diag/waits.py; times in CPU-cycle seconds)

- A: 8F3E 12.915 ... 932D 13.722 ... 8FCC 14.253 -> 9D56 14.439 (+0.186) -> 9D5D +0.128 -> 9D66 +0.150 -> 9D88 +0.037 -> 9DCF 15.282 (+0.527) -> entry 15.331 -> B574 15.437 -> A3CE 15.594 -> A3E6 16.166 (+0.572, A's tag 3D = S start) -> A417 16.236.
- B: 8E84 12.940 ... 932D 13.278 ... 8F02 14.066 -> 9DCF 14.374 (+0.308) -> entry 14.472 -> B574 14.576 -> A3B4 14.733 -> 9D56 15.304 (+0.571) -> 9D5D +0.127 -> 9D66 +0.150 -> 9D88 +0.037 -> 9DCF 16.145 (+0.527) -> entry 16.194 -> B59D/A03C/B5CB/A040 -> A417 16.373.
- B's second chain mirrors A's first chain, shifted by 0.865 s; the waits are fixed symbol counts (0.127/0.150/0.037/0.527/0.571 identical on both sides). Role-dependent steps: 8F02->9DCF 0.308 (A: 8FCC->9D56 0.186); first 9DCF->9DD3 gate 0.084 on B vs 0.035 on A (level gate 9E56, signal dependent).
- B's receive-stage entry (16.194) comes 28 ms after A's S start (A3E6 16.166). At delay 141 / slice 100k it was 45 ms (A 3D msg 16.8087, B entry 16.8542): the offset grows 1:1 with the line latency (+17 ms latency = +17 ms offset), but is still ~27 ms with none. So the link adds to the problem but is not the cause.
- Consequence: B always enters the stage after A's S has started; whether the 20-pass test succeeds depends on a 27 ms + latency head start against an S of ~38 ms (129 symbols).
- LINK_SLICE=10000 call (shared clock): first attempt still fails (retrain 18.74 / 18.89 s), CONNECT A 30.54 s B 29.04 s, HelloFromA delivered clean (10 bytes) to B, HelloFromB not seen (A got 64 KB noise).
- Link clock drift between A and B is negligible: <= 0.06 ms over 16 s (tools/diag/drift.py).

## 51. Gate trace, 80186 timing (2026-11-16)

- 9E56 gate (ov6): passes only when [32C]=0, level [0x380]:[0x382] >= 0x445C (DP 7) and [0x3B4] < 0; evaluated every 24 symbols (7 ms). The level jumps when the PEER's signal starts (B: 0x1679B4A at 14.451 after A starts at 14.439; A: 0x0607C761 at 15.3168 after B starts at 15.304): each hop of the ping-pong costs ~12 ms of detection. Tools: tools/diag/gate9e56.py.
- GAIN 1.0 / 2.0 (line gain, default 0.5 in call_data) breaks the handshake completely (A stalls at 9F62/A3xx, B at 9D20/B121): 0.5 is a narrow operating point; level thresholds are amplitude-dependent.
- Margin: with the sync flip (A12B, symbol 44) B needs ~22 + 20 frames of S after entry, i.e. entry within ~21 frames (12 ms) of the S start; ours is ~26 frames. A 6 ms trim test (tools/diag/trimtest.py) was inconclusive: the trim point (9D93) is after the wait.
- 80186 timing: CPU model 1 ('approximate 80C186 clock counts') is the default; CPU_MODEL=0 (flat 4 cycles/instruction) moves the whole handshake ~0.3 s earlier and shrinks B-entry minus A-S-start from 28.2 to 25.2 ms, outcome unchanged (retrain structure the same). Not modelled: chip-select wait states. Supervisor PCB writes (tools/diag/pcbwrites.py): UMCS FFA0=0000, LMCS FFA2=200A, PACS FFA4=8000, MMCS FFA6=FFCE, MPCS FFA8=10FF -> LMCS/MMCS 2 wait states, MPCS 3, UMCS/PACS 0 (+external READY). A real 186 is therefore slower than model 1 for RAM accesses.

## 52. 80186 clock counts, link slice and CPU_SCALE (2026-11-16)

- sys/i186.c: per-instruction clocks now match 80C186EB Table D-2 for all 101 forms in tools/diag/i186time.py (33 mismatches before: MOV r/m,r 8 vs 12, PUSH r/m, XCHG r/m, ADD/SUB imm,r/m, INC/DEC r/m, REP string startup, prefix 2 clocks, flag ops 2, OUT 9/7, JCXZ 6/16 ...). Chip selects (supervisor PCB writes, tools/diag/pcbwrites.py): UCS 0x80000-0xFFFFF, LCS 0x00000-0x1FFFF, GCS4 0x80000+, GCS0 I/O 0x00-0x7F, all WS3:0 = 0 and ready ignored: no wait states to add.
- Average 8.22 clocks per instruction over a 4 s boot (3141 instr/ms at 25.8048 MHz); sibling docs quote 5.9 (4348 instr/ms) for a main211 run (derivation unknown). CPU_SCALE env (Machine) multiplies charged clocks per instruction.
- Results (SV25, delay 0, GAIN 0.5), all with the corrected clock counts unless noted:
  * LINK_SLICE=100000, CPU_SCALE=1: retrain at ~18.7 s (first attempt fails), CONNECT A 31.2 / B 28.7.
  * LINK_SLICE=10000, CPU_SCALE=1: retrain 18.75/18.88 s, CONNECT 30.54/29.54.
  * LINK_SLICE=1000, CPU_SCALE=1: first attempt passes (37/30/03/35/36/02 at 17.7-17.8 s), CONNECT 24.68/23.67 s, later retrain at 31.4 s (A->B queue stands at ~46 samples, B->A at ~4: asymmetric latency at this slice).
  * LINK_SLICE=10000, CPU_SCALE=0.72: first attempt passes, no retrain at all (rate stays 10267 Hz to the end), tags 37/30/03/35/36/02 at 17.6 s, CONNECT A 24.53 / B 23.53 s; A receives exactly 'HelloFromB' (10 bytes); B receives 20012 bytes of noise and no 'HelloFromA'. Wav/bins in out/cpu072/.
- Conclusion so far: host (80186) speed and link granularity both move the handshake by enough milliseconds to flip the first attempt; a faster CPU (5.9 clocks per instruction) passes it.
  * LINK_SLICE=10000, CPU_SCALE=0.5 (4.1 clocks/instruction): first attempt FAILS again (retrain 18.87/19.00 s, CONNECT 30.53/28.53 s); both messages arrive (A clean 10 bytes, B inside 18.6 KB of noise). So the pass at 0.72 is not monotonic in CPU speed: the CPU speed shifts the handshake timing like the line delay does, and pass/fail follows the same phase lottery (A12B parity flip vs 20-frame window). CPU speed alone is not the fix.

## 53. Data mode: the 0x20FF word stream and the missing DSP message 0x14 (2026-11-16, CPU_SCALE=0.72, LINK_SLICE=10000)

Correction to section 45: "no constant 0x20FF flood in the host port writes" was wrong; I only watched ports 0x58-0x5F. The flood is on the bank ports 0x40-0x4E (+ flag port 0x18), ~700 words/s per host (1398 loop iterations in 2 s), identical on A and B.
- Host loop (flash 0x93BF0-0x93C76): for each of 4 words: `call *[0x3B5]` -> AX; `out lo`, `out hi`; `out 0x18,<bit>`; wait for the bit to clear. Generator (CS=8F46:0x112A = 0x9058A) returns AH = 0x20, or 0x40 if [0x33F] bit 0 is set. [0x33F] = 02 on both hosts from 17.79 s on (bit 0 never set).
- [0x33F] bit 0 has one setter: `or byte [0x33F],1` at 0x93062, inside the handler at 0x93059 = entry for DSP->host message type 0x14 (dispatch table at 8F46:0x5754.., type 0x08 = 8F46:59A8). The handler also installs [0x298] = 0x3D0F and sets [0xAF4]/[0xB12].
- DSP side: routine 8270 reads the word, `bsar 8; sub #40; bcnd 8300,lt` -> high byte < 0x40 is discarded at 8300 (nothing packed). Measured 24-36 s: 15317/15317 arrivals on A and 6639/6639 on B hit 8300 with [0x3D0] = 0x20FF (tools/diag/floodcheck.py).
- No DSP ever sends type 0x14 (nor 0x12/0x13/0x15) in our runs; tags seen stop at 0x37/0x41/0x42 plus the 0x20 quality reports. In the base image types 0x12-0x15 come from the state machine at D1E1 (D201 0x12, D217 0x13, D229 / D262 0x14, D251 0x15), gated by bit 2 of [0x330] at D223 and the countdowns [0x335]/[0x339].
- So: the hosts stay in idle-fill mode (0x20FF) because the DSP never reports data mode; the DSP discarding those words is correct. CONNECT is printed by the host timer regardless (section 8x notes). The garbage on B's DTE and the repeated 54/00xx rate selects are what follows.
- Open: why HelloFromB still reaches A (DSP->host data words via port 0x60), and which condition at D223 ([0x330] bit 2) the DSP is waiting for; tools: hostwrites.py, dspreads.py, hostgen.py, flag33f.py, floodcheck.py, underruns.py.

## 54. Who should send message 0x14 / where the data goes (2026-11-16, same config)

- Only the base image sends type 0x14 (D229 / D262, inside the state machine D1CB/D1E1, which lives in script steps run by the interpreter at CC9F..CCAB). Over 14-30 s neither DSP executes any of D1E1, D1CB, D1D6, D223, D229, D262, nor the interpreter (tools/diag/d1e1.py, scripteng.py: zero hits). ov8 has no 0x14 sender (its `lacl #14; call 8770` are wait counters); the type 0x41/0x42 sent at E87F is the data-overlay start message. So in V.34 mode the host's type-0x14 handler (the only setter of [0x33F] bit 0) is not reached by this DSP code path; either the V.34 data path switches the host to word type 0x40 some other way that we do not trigger, or the 0x20 stream is what the real V.34 data mode also uses and the 8270 discard is the wrong reader for it.
- DSP->host words (ports 0x58..0x5D) over 28.5-32 s: A's DSP writes only 0x00FF (idle) 2318 times per port (its receiver sees B's idle correctly); B's DSP writes 0xFF mixed with random bytes (about 8-9 times each of many values): B's receiver is not locked on A's signal. No DSP writes to port 0x60 (stream lane) on either side.
- Still unexplained: how 'HelloFromB' reaches A's DTE although neither the host generator (0x20FF only) nor A's bank words (0xFF only) carry it.

## 55. Stall at 17.6 s, REP yield, and the user's i186-fixed.c (2026-11-16)

- Link fidelity in data mode (tools/diag/linkfid.py): correlation 1.0000 and gain 0.500 in both directions, so the line is transparent; A->B lag 56 samples vs B->A 15 samples.
- Cause of the asymmetry: at 17.6047 s B's machine delivered no samples for ~2.3 ms and then 60 at once (tools/diag/slicebursts.py, qseries.py); B's rx queue drained (48 zero samples inserted), A's queue jumped from 12 to 64. A REP string instruction ran all its iterations inside one exec1 and ignored the cycle budget, so the DSP and codec clock stood still during a long block move. Fix (sys/i186.c): REP loops yield when the budget is used up (rep_resume avoids a second start-up charge); the timing table stays 101/101. With it every link slice delivers 2-6 samples in 16.5-21 s.
- The first attempt still fails at CPU_SCALE=1 (retrain 19.15/19.27 s): the stall was not the cause of the retrain.
- i186-fixed.c / i186-fixed.h (user): builds clean as sys/libi186_fixed.so (+ shim.c stubs for set_ud_trap / set_cycle_scale; select with I186_LIB=libi186_fixed.so). Timing table: 98/101 (OR/XOR imm,r/m 10 as printed in the manual; JMP r/m 26 for the register form, manual 11). Call (LINK_SLICE=10000): retrain 19.15/19.28 s, CONNECT 31.04/29.04 s, B gets 'HelloFromA' clean, A gets 42 KB noise: same timeline as our core to the 100 ms.

## 56. The state transition out of acquisition and what flips it (2026-11-16; tools: stepscript.py, a417.py, rxgate.py, eqdump.py)

Chain on B (ISR-level callback [6D], ov6): 9DCF (gate 9E56: [32C]=0, level [0x380:382] >= 0x445C, [0x3B4] < 0) -> 9DD3 -> 9DD7 -> stage init (9E24 clears [4B],[36],[2C],[44],[1A]) -> symbol states B59D/A03C/B5CB/A040 + main-thread script A086 (A12B at symbol 44, A145, A136, A146, A158, A112, A16D, A175, A17B) -> [6D] = A417 at step A17B (16.78 s), then script steps A183 (0x630), A18B (0x640), A19A (0x280), A1AB (0x280), A1B8 (0x1F40 symbols; also sets [0x728]=0xC0, [0x729]=0x10).
- A417 (per symbol): bail to A47F -> 8D9D (retrain path) if [0x31A] < 0 (timeout) or [0x336] >= 4 (S detector 9E6B); otherwise runs 5 sub-steps via `cala [0x43]`.
- A478 (the wait state, reached via A437/A46E): `lacl [34]; sub #14; bcnd A482, geq` -> A482 = the data-mode start: sends message 0x41 or 0x42 (bit 10 of [6F]), [2F] = B59D, call 9E4D, b A3F7. `[0x336] >= 4` -> A47F bail; otherwise retc (stay in A478).
- So the DSP leaves acquisition for data mode when the SAME frame test that gives the first exit (9F6C: exactly one of E1'/E2' negative and the other in (107.3M, 429M); counter [0x334]) passes 20 consecutive frames while [6D] = A478, with [0x336] < 4 and [0x31A] >= 0. In our failing runs B sits in A478 for seconds with [0x334] = 0..1 (and in the first attempt A417 times out at [0x31A] < 0 after ~2 s, then 8D9D -> retrain, host cmd 0x0A at +1.6 s).
- eqdump.py: B's equalizer table is nearly constant between 23 and 30 s while A's keeps adapting; both DSPs run the decision stage (A2C4 gate passes 57 times in 2 s on each; 9F6C 3440 times in 2 s on each, 9E6B never).
- Breakpoints perturb the slice timing enough to flip the first-attempt outcome (a417.py with CPU_SCALE=0.72 retrained at 18.6 s while call_data with the same settings did not).

## 57. What the two modems transmit while a DSP waits in A417 / A478 (tools/diag/sigtype.py)

Per 0.25 s window (SV25, LINK_SLICE=10000, CPU_SCALE=1, first attempt fails): from 16.76 s both modems transmit a random-looking signal continuously (rms ~5160, normalised autocorrelation ~0 at lags 3, 6 and 144 samples) until the retrain at 19.3 s; the same again from 22.5 s through the A417 and A478 states to the end of the run (30 s). No S-like period-6 pattern (ac6 about -0.5..-0.65, ac144 0.6-0.9, seen at 14.3-14.8 s and 19.5-20.5 s) is on the line while a DSP waits in A478.
- The pass counter [0x334] keeps being driven by the same exit-test code in this stage (writers 9F87 +1: 2557 times, 9FA0 clear: 2316 times in 1.5 s on B): it passes a single frame now and then on the random signal and is cleared again, so 20 consecutive passes (A478 -> A482) cannot happen on a random signal.
- B6FD (the symbol callback [2F] in A478) is a per-symbol vector/decision routine (masks &0x3FF, squared magnitudes, calls BC7F).
- Open: whether the real peer is supposed to present a signal that makes the 9F6C test pass in this window (e.g. S/S-bar structure that our A and B do not send there) or whether [0x334] means something else in A478 (decision-error counter); the sender side (what each DSP intends to transmit per stage) is the next thing to read.

## 58. Corrections and the real first-attempt failure (2026-11-16, REP-fixed core, LINK_SLICE=10000)

- The earlier "passes" (CPU_SCALE=0.72, LINK_SLICE=1000, shared-clock) all predate the REP-yield fix; with the fix CPU_SCALE=0.72 retrains at 18.72 s like the others (tools/diag/chunktest.py: chunk size of the harness does not matter, the emulation is deterministic). The stall at 17.6 s (2.3 ms hole + 60-sample burst in B's input) had been helping or perturbing the outcome.
- frames9f6c "max-ctr 19" is a logging artifact (the counter is read before the 20th increment): both DSPs reach A417 (A at 16.08, B at 16.21 s), i.e. the first exit test DOES pass 20; no delay 0-30 or gain 0.35-0.75 changes that.
- The first attempt fails inside A417: it shifts the (descrambled) received bit stream through [0x320] and counts the run length in [0x323] (loop A41F); at A55x, when the run reaches 0x14 (A59D) it branches to A5A1 -> A42E (receiver enable: [6F] bit 8 cleared, then [6D] = A478). In 2 s of A417 the longest run seen is 13 (A) and 16 (B) = random bits; A417 times out ([0x31A] < 0, ~18.6 s) -> A47F -> 8D9D -> retrain (host cmd 0x0A at +1.6 s).
- [6F] bit 1 (selects the shift-register tap in 8CF3: bsar 5 vs bsar 2, i.e. the scrambler polynomial) differs between the modems as it should: A 0BC3 (bit 1 set), B 0BC0 (clear). The bytes B delivers later are not a simple scrambler mismatch of the two V.34 polynomials (tested in both orders).
- Open: whether the training signal each DSP transmits carries scrambled ones (TX side) and whether the received symbols are decided correctly (carrier phase / timing / equalizer / differential decoding), since both A417 stages read random bits. Next test: independent demodulation of A's TRN from the DAC samples.

## 59. Independent TRN check and the DSP cycle model (2026-11-16)

- tools/diag/demodtrn.py + a scan of the recorded wav (out/fixedrep): both transmitters send a correct training signal. B's (caller) QPSK-like stretch (constant modulus, 4th-power coherence 0.7) demodulates to 4637 symbols whose descrambled bits are 96.9% ones with GPC (1+x^-18+x^-23); A's (answerer) stretch gives 94.4% ones with GPA (1+x^-5+x^-23), same dibit map; the residue is my demodulator. So the TX side is right and the receivers read random bits from a correct signal.
- Full call with CYC_MODEL=0 (DSP at 1 cycle per instruction instead of the manual table; REP-fixed 186 core, LINK_SLICE=10000, delay 0): A receives exactly 'HelloFromB' (10 bytes) and B exactly 'HelloFromA' (10 bytes), no noise on either side; CONNECT 25.03 / 25.03 s; the first attempt still retrains at 19.15 / 19.28 s; later retrains at 35.3 s and 43.2 s (rate steps 9600 <-> 10267). With the manual cycle table the same call gives noise on one side and one message missing. So the DSP's receive path needs more speed than our manual-table cycle model gives (heavy work per symbol ~11.7k cycles of 11.78k available at 10267 Hz and 40.32 MHz); the receivers lose their update when the budget is exceeded.
- Out dir: out/dspcyc0/ (wav + rx bins).

## 60. DSP load by cycle model (tools/diag/dspload.py, cycmix.py; data phase 26-28 s, REP-fixed core, LINK_SLICE=10000)

- CYC_MODEL=1 (manual table): DSP busy 82.0% (A) / 82.4% (B); busiest symbol 11936 / 11922 of ~11784 cycles (101.3% / 101.1%).
- CYC_MODEL=0 (1 cycle per instruction): busy 72.5% / 73.0%; busiest symbol 11810 / 11852 of ~11781 (100.2% / 100.6%).
- So the worst symbol fills the whole 3-sample budget in both models (the margin between "decodes" and "random bits" is ~1% = ~126 cycles); the average load differs by ~10 points. (The IFR-pending-at-tick counter in dspload.py reads 100% in both and is not meaningful.)
- Where the table cost goes (26.0-26.2 s, A): 5.14 M table cycles for 4.42 M executed instructions (1.16 per instruction; RPT iterations are not in the hit counts). Share of the "extra over 1 cycle": LAR 22.3% (2 cycles each, 161k executions), BCND 10.9%, RPT 6.1%, CALL 6.0%, MAC 5.8%, CC 4.1%, TBLR 3.4%, AND 3.0%, MACD 2.9%, RETD 2.7%, ADD 2.5%, BANZ 2.5%, CALLD 2.5%, RETC 2.4%, MPY 2.2%, RET 2.1%.
- Next: find which class(es) of the table are too high versus the real C5x by lowering one class at a time (LAR, branches/calls/returns, MAC/TBLR) and re-running the call; the table is generated from the manual summary tables (dsp/gen_cyctab.py, fastest case, with overrides), so any change needs a manual reference.

## 61. Second opinion from the sibling core and the RPT cost (2026-11-16)

- Same call (REP-fixed 186, LINK_SLICE=10000, delay 0) on the sibling's C5x core (DSP_CORE=sib): both messages arrive clean, 10 bytes each way (CONNECT 24.53 / 24.53, first attempt still retrains at 18.75 / 18.88 s, later retrain at 34.1 s). Same as CYC_MODEL=0.
- Per-opcode cycle dump of both cores (tools/diag/cycdump.py; the sibling core rejects 802 of 65536 opcode words): many differences are test artifacts (peripheral-MMR / I/O wait-state registers at reset, flags at reset for conditional branches, delay-slot accounting, XC). The systematic ones in the hot path: RPT #k and RPT dma/lk: ours 2 / sibling 1; one-shot BLDD / BLPD / TBLR / TBLW (0xA5xx-0xA9xx): ours 3 / sibling 2.
- Experiment switch CYC_EXP in dsp/c5x_core.c (bit 1: all RPT forms cost 1; bit 2: one-shot block moves 3 -> 2): CYC_EXP=1 alone already gives clean data both ways (A: HelloFromB 10 bytes, B: HelloFromA 10 bytes; CONNECT 25.03 / 25.03; retrains at 19.15 / 19.28, 38.96 / 39.09 s). CYC_EXP=3 the same.
- The manual says otherwise for RPT: spru056d.pdf p. 6-215: RPT #k / #lk (immediate addressing) = 2 cycles on ROM / DARAM / SARAM, 1 for direct/indirect operand; our table matches it. The sibling's op_rpt_simm charges CYCLES(1) (its core is MAME-derived, not board-verified), so its lower figure is not evidence about the chip.
- Reading: RPT #k runs ~44,000 times per 0.2 s (about 0.55% of the DSP's cycles); removing one cycle from each is enough to flip the receiver. The receiver works only with < 1% of slack in the worst symbol (11,810-11,936 of 11,784). Which of the dozens of small cycle terms is wrong on our side (or whether the real DSP clock / cycle rate is slightly higher) is not yet known; no ground truth for DSP instruction timing is available.

## 62. Shared-clock link, slice 1000, clean first attempt (2026-11-16)

- sys/link.py: each Link slice is now scheduled against one shared absolute clock (a machine that overshot its slice gets a shorter budget next time) instead of a relative budget; the relative budget let the overshoot accumulate (~2% per machine at 1000-cycle slices, different per machine), which made one receive queue grow to ~46 samples. With the fix the receive queues stay at 1-6 samples and there are no underruns at slices of 10000, 2000 and 1000 cycles (tools/diag/linkq.py). Wall time is 3.6x (10000), 4.0x (2000), 4.4x (1000), 5.3x (500) real time (tools/diag/speed.py); the glue profile (tools/diag/prof.py): DSP core ~53%, Python glue ~30%, 186 ~8%, so a C rewrite of the glue gains at most ~1.4x.
- Default LINK_SLICE is now 1000 cycles. Full call with all defaults (manual DSP cycle table, REP-fixed 186 core, delay 0, GAIN 0.5): NO retrain (rates 8640 -> 9600 -> 10267 only), result tags 37/30/03/35/36/02 at 17.8 s on BOTH modems, CONNECT 18.5 s on both, A receives exactly 'HelloFromB' and B exactly 'HelloFromA' (10 bytes each, no noise). Files: out/slice1k_final/.
- Cycle checks against the manual (tools/diag/cyctest.py): repeated OUT = 3n and IN = 2n (+ n*io), RETC true = 4 even when the return address is the next address; the pre-fix core charged OUT like IN (undercount n-1... 15 for n = 16) and 2 cycles for the fall-through RETC.

## 63. Robustness checks of the clean first attempt, and the call set-up timeline (tools/diag/calltl.py)

Default setup (slice 1000, shared clock, manual DSP cycle table, REP-fixed 186): delay 3, 10 and 100 samples all give no retrain, CONNECT 18.5 s (B 19.0 s at delay 100), exactly 10 clean bytes each way; the DSP at 1 cycle/instruction (CYC_MODEL=0, delay 0) the same. Delay 400 samples (~39 ms one way) does NOT connect: A prints RING only, tags stop at 48/47 around 12.3-13 s (the V.8 exchange), B reaches 8640/9600 only at 27 s.
Set-up timeline (call time, ATDT at 0): B DAC first sound (DTMF) 2.32 s (B runs ATX3, no dial-tone detection: it waits S6 = 2 s); harness: digit 2.32, dialing dwell until 5.40 (fixed 3.0 s in Link.co_step), ringing 5.40-8.21 (US cadence, A's host prints RING at 8.22 after its ring qualification), answer 8.21, A host->DSP setup 8.27-8.29, A's first sound (answer tone) 10.57 s = 2.3 s after answering (V.25: CED starts 1.8-2.5 s after the answerer connects to the line). The long part is the harness (3 s dwell + 2.8 s ring), not the firmware.

## 64. Slice size with the shared absolute clock (2026-11-16, defaults otherwise: manual DSP cycle table, REP-fixed 186, delay 0, GAIN 0.5)

| LINK_SLICE | retrain | result tags | CONNECT | data |
|---|---|---|---|---|
| 1000 | none | 17.8 s | 18.5 s | 10 + 10 clean bytes |
| 10000 | none | 17.8 s | 18.51 s | clean |
| 100000 | none | 18.2 s | 19.14 s | clean |
| 1000000 | none | 19.3 s | 20.15 s | clean |

The clean first attempt no longer depends on the slice size (the 1M-slice run that used to retrain several times is clean too; CONNECT moves later by about the extra latency). Open: DELAY_SAMPLES=400 (~39 ms, slice 1000) still stalls in the V.8 exchange (A prints RING only, tags stop at 48/47 around 13 s), while a 1M-cycle slice (similar latency) connects; so the failure is specific to how DELAY_SAMPLES is applied, not to the latency itself.

## 65. Modulation selection by AT commands, rate-correct WAV, and the V.21 / V.22bis failures (2026-11-16)

- 0.75x: the single-process Link wrote every sample at the nominal 7200 Hz; Link.write_wav now resamples each constant-rate segment from its true codec rate (Machine.rate_idx) to 22050 Hz. In the exported file ANSam 2100 Hz, V.21 answer 1651/1847 and caller 976/1170 Hz, Tone B 1200 Hz, Tone A 2400 Hz + guard 1800 Hz, L1 autocorrelation at lag 64 = 0.97 (9600 Hz samples); read at 7200 Hz the last three are exactly 0.75x (900 / 1800 / 1350 / 112.5 Hz).
- Calls with CMDS_A / CMDS_B (call_data.py): V.34 (ATB0, AT&N16) 33600 clean; "V.90" (AT&N0, ATS58=0, ATS53=0) connects as V.34 33600 (both ends analog: no digital side for V.90); "V.32" (AT&N6, ATS53=224) connects as V.34 at 9600 (S53 does not stop V.34); V.21 (AT&N1) and V.22bis (AT&N3): NO CARRIER at both ends after ~62-67 s (S7); WAVs in out/mod_*.
- V.21 attempt: both modems run the V.8 phase like V.34 (A: ANSam 2100 Hz, 1650/1850 V.21; B: 980/1180 FSK) until 9.5 s; the DSPs then each send message 0x4A and fall silent (DSP states 9F9F / 9D20 stay); no host->DSP command follows until the hangup reset (46/58/45/01/0F at 62-67 s). Host side: no new code executes after the 0x4A (tools/diag/newcode.py), host cells unchanged, the DSP->host channel is not stalled (d2h_valid = 0). In the V.34 run the same window runs new host code (the 0x47 handler at 94DC3 and the overlay download 8E60A-8E736: host cmd 02/00 at 9.44 s).
- Host->DSP set-up burst at 7.04 s (answerer; the caller's is at 2.4 s) differs only in the capability words: V.34: 44/3F 42/F9 49/F5 50/45 50/13 53/FF 71/FF 77/FF 76/7F then 14/5D; V.21: 43/3F 42/91 49/85 50/05 50/10 50/10 53/00 71/01 77/00 76/00 then 14/41. DSP [0x6F] bit 13 (0x2000) is set in the V.34 run (0x3xxx) and clear in V.21 / V.22bis (0x1xxx). In the base image the send of 0x4A is the default target (D579) of a mode dispatch table at D54F (pairs per bit of [0x68] | 0x2000, role bit picks the member); [0x68] reads 0x820C in all three runs.
- Message 0x4A on the host is a plain report: its handler (flash 93010) stores the payload word at [0xB00]; so 4A is not an error code to the host. Open: what the DSP should do after reporting it for a V.21 request (a V.21 modulation start) and why it does not; V.22bis: B reaches other states (CE52, CE72), DSP tags up to 05 at ~16.5 s, then silence and NO CARRIER.
- Tools: tools/diag/{tones,wavcheck,calltl,hostst,hosthits,newcode,msgdeliver,mode68}.py.

## 66. Capability words per AT setting; V.34 words substituted into the V.21 attempt (2026-11-16)

- Experiment hook: CMD_OVR env in sys/machine.py rewrites host->DSP command words as they complete in the mailbox ("42=F9" arg of every command 0x42, "50@2=45" 2nd of each run of six 0x50, "43>44" renames command 0x43 to 0x44).
- V.21 attempt (ATB0, AT&N1 on both) with the V.34 capability words substituted (43>44;42=F9;49=F5;53=FF;71=FF;77=FF;76=7F;50@2=45;50@3=13), start command left at 14/41 or set to 14/5D: both modems run the full V.34 handshake (tags 47, 6B, 34, 04, 3D, result tags 37/30/03/35/36/02 at 14.3 s: first attempt passes), then tags 41/42/44 at 15.0-15.1 s, rate drop to 8000/7200 Hz at 15.2 s and NO CARRIER at both hosts (the host does not allow the V.34 connection under &N1). So the capability words select the mode, and the DSP side proceeds when given all modes.
- Capability words the host sends to the answerer DSP at ~7 s (the caller's burst is at ~2.4 s), per AT setting (tools/diag/calltl.py with CMDS_A / CMDS_B):

| setting | 42 | 49 | 43/44 | 53 | 71 | 77 | 76 | start 14 |
|---|---|---|---|---|---|---|---|---|
| &N1 (300 bps) | 91 | 85 | 43=3F | 00 | 01 | 00 | 00 | 41 |
| &N3 (2400 bps) | 91 | 85 | 43=3F | 01 | 01 | 00 | 00 | 09 |
| &N6 (9600 bps) | 91 | 95 | 43=3F | 08 | 01 | 00 | 00 | 0D |
| &N6 + ATS53=224 | 91 | 95 | 43=3F | 08 | 01 | 00 | 00 | 0D |
| &N16 (33600 bps) | F9 | F5 | 44=3F | FF | FF | FF | 7F | 5D |

  Only the &N speed changes these words; S53=224 changes nothing (so the "V.32" call connects as V.34 at 9600). At >= 9600 bps the DSP takes the V.34 handshake; at 2400 and 300 bps it takes the low-speed path and sends message 0x4A and stops (V.21: states 9F9F / 9D20, no further host command until the S7 hangup; V.22bis: caller enters other states CE52 / CE72, tags up to 05 at ~16.5 s, then silence and NO CARRIER).
- Not captured: the V.90 setting (AT&N0, ATS58=0, ATS53=0) and ATB1 (the second batch did not start).
- Next: trace what the DSP does after start command 14/09 (V.22bis) and 14/41 (V.21): it reports 0x4A (default of the mode dispatch at D54F in the base image) and does not start the modulation.

## 67. V.21 works with S27 bit 0 (2026-11-16)

- The hint was right: S27 bit 0 (value 1) "enables V.21 modulation at 300 bps" and defaults to 0 (3453c-qrc.md, 3453c-s-registers.md). Calls: both modems ATB0, ATS27=1, AT&N1: CONNECT (plain, 300 bps) at 10.5 s on both, 10 clean bytes each way (tags 3D, 04, 29, 02, 03 at ~9.5-10.2 s); WAV out/v21_s27/call_22k_B_left_A_right.wav. The capability words are the same as without S27 except the start command: 14/01 instead of 14/41 (S27 bit 0 clears bit 6 of the argument).
- Only the caller limited (ATS27=1, AT&N1) with the answerer at defaults (S27 = 0): both DSPs send 0x4A and stop as before (the answerer has V.21 disabled, so there is no common mode); caller limited to AT&N3 with the answerer at defaults: answerer prints CONNECT at 17.0 s then NO CARRIER, caller never connects.
- V.22bis (AT&N3, with or without ATS27=1, both ends): caller DSP message 3D at 9.6 s but the answerer's 3D only at 15.8 s (6 s later), then 04, 28, 02, 07, 03, 05 at 15.8-16.5 s and NO CARRIER at both: the V.22bis answer path starts 6 s late and does not complete. Next: find what the answerer DSP waits for between 9.5 and 15.8 s (V.22bis needs the caller's S1/SB1 sequence).

## 68. All enable bits set, V.22bis retry, speaker gate (186 port 0x12) (2026-11-16)

- Enable bits that exist: S27 bit 0 (V.21) and S34 bit 3 (V.23); everything else in S27/S34/S53/S58 disables a mode (default 0 = enabled). Calls with ATB0;ATS27=1;ATS34=8 on both ends: &N3 (2400): fails as before (answerer's 3D at 15.7 s, caller's 9.6 s, NO CARRIER); &N2 (1200): connects as V.23: `CONNECT 1200/75/NONE` at the answerer and `CONNECT 75/1200/NONE` at the caller, 10 clean bytes each way (tags 3D, 04, 2C, 02, 03 at 9.5-10.7 s, CONNECT 11.0 s); answerer at defaults and caller &N3: answerer prints CONNECT at 17.0 s then NO CARRIER.
- Speaker gate: 186 I/O port 0x12 values seen: 0x6d / 0x6c early; bit 4 (0x10) goes high on its own (0x7c / 0x7d), bit 0 toggles. tools/diag/gatelog.py stops the audio at the first bit-4 rise (WAV up to it) and logs 10 s of what is transferred afterwards. V.22bis failure (both &N3): the rise is at 16.19 s (caller) and 16.45 s (answerer) and is the hang-up: after it only the DSP reset commands 46/C0, 58/C0|08, 45/C0|08, 01/3F, 0F/00, 83/83 (caller 8 commands, answerer 9) and 6 DSP messages on the answerer (07, 03, 07, 07, 07, 05); NO CARRIER at both DTEs; nothing else is transferred. Working V.21 (S27=1, &N1): the rise is at 9.98 s (answerer), CONNECT follows at ~10.5 s, then 10 s of silence on the mailbox (one DSP message 03 and command 46/C0 at the caller at 10.16 s; data only moves when the DTE sends text). Files: out/gatelog_v22bis/audio_until_speaker_mute.wav (16.19 s), out/gatelog_v21/audio_until_speaker_mute.wav (9.98 s).

## 69. S-register page check (support.usr.com 3453c S-registers; file 3453c-s-registers2.md)

- The repo's older 3453c-qrc.md had the modulation-disable bits under S53; the real S-register page (and 3453c-s-registers2.md) lists S53 as dial security (default 126) and puts "Disable V.34+ / V.34 / V.FC" at S56 bits 5 / 6 / 7 (32 / 64 / 128), "Disable V.8" at S54 bit 7 (default 64 = CI disabled), V.90 at S58 bit 5. My earlier "V.32" call (ATS53=224) and the V.90 set (ATS53=0) therefore wrote the wrong register; the corrected V.32 attempt (ATB0, ATS56=224, AT&N6 on both) does not connect at all (answerer prints RING only; tags stop at 0F at 17.5 s).
- Enable bits: S27 bit 0 (V.21, also answers Bell 103), S34 bit 3 (V.23). There is no V.22 / V.22bis enable (S51 bits 0/1 only disable MNP/V.42 for them). S28 (extra 3000/600 Hz V.32 answer tones, default 8): page says 0 speeds up V.21 / V.23 connects. V.22bis with S28=0 (+S27=1, S34=8, &N3): unchanged (answerer 3D at 15.8 s, NO CARRIER).
- Registers that were set correctly before: S27 bit 0, S34 bit 3. Wrong: S53 (twice). Not yet tried before this note: S54 bit 7 (Disable V.8) for the legacy low-speed handshakes.

## 70. Low-speed calls with V.8 disabled (ATS54=192 on both ends, 2026-11-16)

- V.21 (S27=1, &N1): CONNECT 10.5 s on both, 10 clean bytes each way; tags 3D / 04 / 29 / 02 / 03 at 9.9-10.4 s on both modems (the legacy answer/originate path starts together at 9.9 s).
- V.23 (S27=1, S34=8, &N2): `CONNECT 1200/75/NONE` (answerer, 14.5 s) / `CONNECT 75/1200/NONE` (caller, 14.0 s), 10 clean bytes each way; 3 s later than with V.8 enabled (11.0 s).
- V.22bis (&N3): still fails. Answerer tags 16@7.1, 0B@12.7, 3A@16.5, 3D@16.5, 04, 28, 02, 07, 03, 05 at 16.6-17.2 s; caller 08@0.4, 3D@10.3, then 04 / 28 / 02 / 03 at 16.4-16.9 s; NO CARRIER at both. Both sides wait until ~16.4 s (V.8 enabled: answerer's 3D at 15.8 s): something at ~16.4 s releases the V.22bis answer path and the call then ends within a second. Open: what that event is.

## 71. V.22bis (&N3, ATS54=192): the caller never transmits (2026-11-16)

- Recording out/mod_r3 (22050 Hz wav, measured with Goertzel): answerer A sends 2100 Hz until 9.5 s, then a constant 2250 Hz (rms 6222, no modulation) until 16.5 s, then 2221 Hz; its DSP state word changes A003 -> D1B0 at 16.46 s by itself (own timeout, ~7 s after 9.5 s). Caller B: DSP state CE72 and message 3D at 10.3 s, then RMS exactly 0 from 10.5 s to 15.5 s (no transmission at all) until the hang-up.
- No host->DSP command is issued between 9.0 and 16.9 s on either modem; the host only sends the reset set (46/C0, 58, 45, 01/3F, 0F/00, 83/83) at 16.9-17.7 s.
- So the V.22bis answerer behaves as expected (2250 Hz answer tone); the caller DSP does not detect it / does not start sending its 1200 baud signal. Next: what B's DSP executes between 10.3 and 16.4 s (PC histogram, tone-detector state around the 2250 Hz detection, mode word [0x68]).

## 72. V.22bis caller DSP: what it waits for (2026-11-16, tools pchist.py, dmtl.py)

- S51=3 (both ends) changes nothing (same tags, NO CARRIER). Setup used: ATB0 (ITU-T rather than Bell 212A), ATS54=192 (V.8 off, CI off), AT&N3, both ends; with V.8 on the DSPs send tag 48 at 8.7-9.2 s, with ATS54=192 they do not (so the setting took effect).
- Caller DSP (B) 11-15 s, PC histogram: it runs a 600 baud sample loop (symbol counter [0x3CC] steps 3 up to 0x24 = 12 samples/symbol) in D2F4-D424 / CE80-CEA4 (about 29k hits per routine per 4 s = once per sample) and the energy compare at CE72. Mode words [0x68]=820C on both DSPs, [0x6F] A=100B, B=1040, unchanged during the window.
- CE72-CE7E (DP page 7 = 0x380): compares the 32-bit [0x3BA:0x3BB] (running energy) with the threshold [0x3B6:0x3B7] = 0x0127E3C3; energy >= threshold resets the counter [0x3A2] to 0 (CE80), below counts it up and only at 4 jumps to CCAE (progress). On the call [0x3BA:0x3BB] is 0x01FA.. / 0x020C.. / 0x024C.. (above threshold) from 10.5 s to 16.4 s, so [0x3A2] stays 0 and B never proceeds; a second chain [0x3AA] (0x15,0x14,0x13) and [0x3C5] (6,4,2) / [0x3CC] (9,C,F) steps down every 1.5-3 s; at 16.4 s everything restarts ([0x3C5]=0xC, [0x3BA..]=0). Reading (not verified): B waits for the received level to fall below the threshold for 4 consecutive blocks (a silence / end of the answerer tone) while the answerer keeps sending 2250 Hz for 7 s without a gap.
- Open: whether the answerer should have ended the 2250 Hz tone earlier (watch A's timer from 9.5 s: what ends it at 16.46 s), or the caller's threshold/energy scaling is wrong (energy 0x01FA.. vs 0x0127E3C3 - compare how the V.21/V.23 callers pass the same test).

## 73. Correction to §72: comparison with the V.21 caller (2026-11-16)

- The working V.21 caller (S27=1, &N1, ATS54=192, both ends) does not execute the V.22 code at all: PC histogram 9.0-10.3 s shows D8C1-D939, 9C02-9C7A, A10A-A1E8 and the usual 8Axx-8Bxx host-service ranges, none of CE72-CEA4 / D2F4-D424 / D36E-D3A9. So there is no V.21 pass through the CE72 energy test to compare with.
- Same cells in V.21: [0x3B6:0x3B7] is not a fixed threshold, it moves (0x02A4 8EB9 -> 0x02AE 121A) and [0x3BA:0x3BB] = 0x0001 9Bxx (about 200x smaller than the 0x01FA.. in the V.22bis call); both reset at 9.7 s. In the V.22bis call [0x3B6:0x3B7] stays at 0x0127E3C3 (never updated) and [0x3BA:0x3BB] is 2x above it.
- Therefore the §72 reading ("B waits for the level to drop below the threshold") is NOT established: the compare at CE72 may equally be a carrier-present test (energy above threshold = carrier present, counter counts blocks of carrier loss), in which case B sees the 2250 Hz tone correctly and the blocker is elsewhere. What is established: B is in a V.22 600 baud receive loop (D2F4/D36E/CE80) from 10.3 s, outputs zero, and its state chain times out at 16.4 s; the answerer holds 2250 Hz for 7 s.
- Next (not done): find what the V.22bis caller state machine expects next (the CCAE path, and the routine that starts its transmitter), and what the answerer waits for during 9.5-16.4 s; the reference is the V.22 / V.22bis handshake (answerer: ANS, silence 75 ms, USB1 (2400 Hz carrier unscrambled 1s); caller: after USB1 detect sends S1 (00/11 dibits at 1200 baud) then scrambled 1s).

## 74. V.22bis answerer: what it waits for (2026-11-16, tools dmdiff.py, dmtl.py, dispm.py WHO=A)

- The first word of the `waits.py` state tuple is the foreground step pointer: answerer A parks at A003 from 9.70 s to 16.46 s (step A000: `lacl 0; call 8770` yield, resumes at A003), caller B parks at CE72 from 10.3 s to 17.1 s.
- A003 loop (DP page 7 = 0x380): polls flag word [0x2F] (0x3AF) bits 11 / 12 / 9 and [0x26] bit 1; [0x2B] is a countdown reloaded to 0x8C (reaches 0 at ~12.7 s, A061 branch executes, then it is not reloaded and counts negative); [0x25] counter to 0x0A, [0x27]=0x0010. [0x2F] stays 0 from 9.5 s to 16.46 s and becomes 0x0208 (bits 3 and 9) at 16.46 s.
- [0x2F] is rebuilt every sample by the routine at 9E72-9F33 (1.14M hits in 4 s, ov6): it runs eight band-energy filters (A191, A116, A185, A179, A13E, A16D, A14A, A12A), then compares seven results with fixed thresholds via A0BF / A0CB (compare cell with a constant, optionally against the sum of [0x3B0..]/4 or /2) and ORs one flag per band: bit 15 [0x263] vs 0x7500, bit 8 [0x1FA] vs 0x61D7, bit 9 [0x3BC] vs 0x5305, bit 6 [0x3BE]+.. > 0x1F40, bit 7 [0x1FE] vs 0x5027, bit 3 [0x3BA] vs 0x5890 (A0CB), bit 5 [0x1FC] vs 0x542F, bit 4 [0x3B8] vs 0x47A2, bit 10 [0x3B6]+.. > 0x1F40.
- Those band energies are all ~0 on A during 9.5-16.0 s (the caller transmits nothing); at 16.46 s they jump (0x3BA 0x40D7, 0x3BC 0x016E, 0x1FA 0x11, 0x263 9) = A's detectors see the caller's first transmission (caller's speaker gate 16.19 s, caller tone ~1273 Hz at 16.0-16.5 s in the tones log) and the flags 0x208 are set one after another; A's step loop then exits and the call ends within a second (A's own timeout is already at its limit).
- Summary: a mutual wait. A (after 2250 Hz tone) needs to detect energy from the caller; the caller B (step CE72, 600 baud V.22 receive loop) transmits nothing until its own timeout at ~16.2 s. What B needs before transmitting is still open (the CE72 level compare at [0x3BA:0x3BB] vs [0x3B6:0x3B7]). Observation to check: the V.22 answerer signal after ANS should be USB1 (unscrambled 1s at 1200 baud on a 2400 Hz carrier, spectral lines at 1800 and 3000 Hz), while A sends a single unmodulated 2250 Hz tone with constant amplitude.

## 75. V.22bis: the answerer's USB1 is correct, the caller never answers it (2026-11-16)

- Correction of §74's last observation: V.22 USB1 (all dibits 11, +270° = -90° per 600 baud symbol) is a single spectral line at carrier - 150 Hz, so the answerer's constant 2250 Hz tone IS USB1 (2400 - 150), amplitude constant, as expected. Sequence on the wire (out/mod_r3, 10 ms rms blocks): ANS 2100 Hz until 9.645 s, guard silence ~45-50 ms (spec 75 +/- 20 ms: marginally short, not examined), 2250 Hz from ~9.695 s on.
- Caller timeline: the DSP reaches step CE72 at 10.3 s, ~0.46 s after the end of ANS (the "456 ms" of the standard), i.e. it is in the right state to send its own USB1 (line at 1200 - 150 = 1050 Hz) but its output stays exactly 0 until 16.43 s.
- At 16.43 s the caller starts a constant 1270 Hz tone (rms 6353) and 0.3 s later the answerer changes from 2250 to 2225 Hz: 1270 Hz / 2225 Hz are the Bell 103 originate / answer mark frequencies, so both DSPs fall back to Bell 103 after the ~6.5 s timeout and the call ends (NO CARRIER).
- Open: why the caller transmits nothing at CE72 (transmitter gate / amplitude / modulator not started) while the answerer is waiting for the caller's signal; neither side is the "wrong" one in timing.

## 76. V.22bis caller: receive side is fine, transmit slots stay 0 (2026-11-16; tools txbuf.py, txring.py, dsphits.py)

- Sample ISR (program 8189-81B3, runs once per sample on both DSPs, 14410 hits per 2 s = 7205/s): reads DRR into the ring through AR7, then DXR = [0x6B] | *AR7+ (the ring is at ~0xBC8-0xBE8, pointers [0x390]/[0x391] on DP page 7; AR0/AR1 hold the saved/loaded AR7). The tx writers named by the disassembly (8CF2, 9D2B, 9DE2, 9F4A, A077, 8096, 809A) execute 0 times in 11-13 s on both DSPs; only 81A0 runs.
- Ring content, caller B at 10.5 / 12.0 / 16.6 s: even slots = the received waveform (E7BC F2E0 2254 F2CC E7B4 1FD0 ...: the same 16-sample, 5-cycle pattern the answerer outputs, 2250 Hz at fs 7200), odd slots = the transmit slots, all 0000. Raw DXR ring of B at 12 s: 40 words of 0000; answerer A: 1850 E040 0000 1FC4 E7B4 F2D8 2260 F2D8 E7B4 1FC4 ... (period 16 samples = 2250 Hz).
- So the caller receives the answerer's USB1 cleanly (receive path, line, AC01 and DRR handling are not the problem); its transmit slots are never filled before 16.4 s: the DSP transmitter for V.22 has not been started at step CE72 (the modulator/mode start is not reached, not a gain or mute issue). The cause (what condition the V.22 caller needs before it starts its USB1 / S1 transmission) is still open.
