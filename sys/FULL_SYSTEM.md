# SV25 full-system emulation (80186 + TMS320C51 DSP)

Goal: boot the real `SV25.XMD` firmware, type `ATA` on the emulated DTE port, and capture the DSP's audio output.
Status (2026-11-14): the 80186 boots the real firmware and runs stably in its main idle loop; the DSP image it downloads
is byte-identical to the one extracted from flash; the supervisor is **stuck in the DSP boot handshake** (see section 6).

Files: `i186.c` (80186 core, build `gcc -O2 -fwrapv -shared -fPIC -o libi186.so i186.c`), `i186.py` (ctypes wrapper),
`machine.py` (the machine: memory map, peripherals, DSP attachment), `boot1.py`..`boot3.py` (throwaway experiments).
The DSP core lives in `../dsp/` (`c5x_core.c`, `c5x.py`); protocol notes in `../dsp/HOST_PROTOCOL.md`.

Run: `python3 -I -c "import sys; sys.path.insert(0,'sys'); from machine import *; m=Machine(); m.logging=False; m.run(600_000_000)"`.

## 1. Memory map (as modelled)

| Physical | Contents |
|---|---|
| `0x00000-0x7FFFF` | RAM. Boot block (flash `0x7C000`, 0x1B13 bytes) is copied to `0000:0000` and runs there; main firmware data lives in segment 0 (e.g. `[0x289]`, `[0x5F1]`). |
| `0x80000-0xFFFFF` | Flash, read-only. Flash offset = physical - `0x80000`. Reset vector `FFFF:0` = flash `0x7FFF0`. |
| `0x0FF00-0x0FFFF` | Peripheral control block (PCB) **memory-mapped** (the firmware accesses `[0xFF02]`, `[0xFF40]`...); also reachable via I/O ports `0xFFxx` during boot. Modelled as a register dict. |

The 80186 core is cycle-approximate (4 cycles per instruction, more for rep/branches); the periodic tick is injected as
INT3 (vector `0x0F`) every `TICK=100000` cycles.

## 2. Boot sequence observed

1. Reset stub programs chip selects, copies the boot block to RAM, jumps to it (`0000:043E`).
2. Boot block waits up to 20 ticks (`[0xF8]`, decremented by the vector-`0x0F` handler at `0x30C`) polling port `0x10` bit 3.
3. Boot block validates the firmware: CRC over flash `0x00000-0x2FFFF` and `0x40000-0x77FFD` (routine `0x3E7`, accumulator
   `cs:[0x104]`), compared with the word at flash `0x77FFE`. **The XMD does not contain that CRC** (the SDL flasher writes it
   after programming), so `Machine` patches the emulator-computed value `0x1735` into flash. Mismatch => flasher/"corrupt" path.
4. Valid: `ljmp F7FF:5` -> flash `0x77FF5` -> `ljmp 8000:040D`, the main firmware.
5. Main firmware: clears RAM, programs I/O latches (ports `0x00-0x14`) and the PCB, runs the RAM test, resets and loads the DSP
   (`8000:E3A0` reset, `E4AB` full load), then enters the scheduler loop around `8000:B3F1`/`9267`/`9380`.

## 3. Hardware found

| Item | Detail |
|---|---|
| Timer 3 | PCB `0xFF40` (count), `0xFF42` (max count), `0xFF46` (control; bit 15 = enable, bit 5 = max-count reached). Used for timeouts in the DSP loader; writing `0xFF40` restarts the timeout. Modelled: period = max count x 4 cycles. |
| Interrupts | INT0 (vec `0x0C`) = DSP mailbox, ISR `8F46:0000` = flash `0xF460`; INT2 (vec `0x0E`) = DTE serial, ISR `8000:1D2C`; INT3 (vec `0x0F`) = periodic tick, ISR `8000:0A70` (EOI = write `0x8000` to `[0xFF02]`). INT1 (vec `0x0D`) = `9EB0:0AAA`. |
| DTE UART | Custom ASIC (not a 16550): port `0x00` status (bit 3 = RX char ready), port `0x0A` data (read RX / write TX). RX ISR passes the char to the handler pointer `[0x26A]` (the AT prefix state machine). The ISR also calls a hook through `[0x270]` which is **only installed by the DTE setup code (`0x35xx`-`0x366x`), which has not run yet**; delivering a char before that jumps to address 0 and ends in the fatal-error routine (`0x0F99`, error code in BP). |
| Fatal-error routine | `8000:0F99`: shows error code (BP) via the port-`0x40` indicator in a delay loop (`0x0FC1`). |
| DSP interface | Byte ports `0x40-0x5E` (even) = DSP word ports `0x58-0x5F` (4 words bank A, 4 words bank B; lo byte at +0, hi at +2). Port `0x18` bit 0/1 = bank A/B free during download; `0x18 <- 4` = start. Ports `0x1C/0x1E` = event status; `0x1C` write = write-1-to-clear ack. DSP-side status port `0x57`. |

## 4. DSP download (verified)

`E4AB` streams the image to the DSP through the two register banks, alternating banks, with a timeout on timer 3. Captured
stream (first 16 bytes are the `0x83` reset pattern, then the image) matches `dsp/dsp_base.bin` for all 55,420 bytes.
This validates, end to end: the XMD decoder, the flash address map, the DSP extraction and the 80186 core.

## 5. What `Machine` synthesises (not in the firmware)

* Flash CRC word (section 2).
* Port `0x18` = `0x03` (both banks free) before the DSP starts.
* DSP start when the host writes `0x18 <- 4`; the DSP base image is built from the captured stream.
* DSP boot-ROM messages: type `0x83` at DSP start and type `0x84` after command `01 3F` (the on-chip ROM is not in the XMD).
* TX kick: INT0 is raised when the supervisor's command ring (`[0x29A]` != `[0x29C]`) is non-empty and the DSP slot is free
  (the real hardware condition is not understood; the ISR clears its own enable bit when the ring is empty and nothing in
  software sets it again).
* DSP bank-port writes (`0x58-0x5F`) count as messages only when issued from the DSP message-send routine (`0x83D6-0x8420`);
  the DSP's init code zero-fills those ports and must not be treated as a message.

## 6. Current blocker

After the DSP starts, the supervisor sends the reset pattern, then a long message (`FF00 000F 0000`) and `013F` (command 1,
arg `0x3F` = re-run DSP init). Reply handling is a state machine pointed to by `[0x298]` (8F46-relative):
`F599` (waits for type `0x83`, then enqueues `013F`) -> `F5B0` (table of expected types `80 81 82 83 84` with handlers
`F5CB F5F0 F600 F607 1646A`) -> `1646A` (type `0x84`, selects the next mode handler). The ISR at `F460` forwards only message
types `< 0x76` to `[0x298]`; types `0x80-0x84` therefore must arrive by another route (a different ISR variant, e.g. the `FDD9`
ISR whose receive path calls `[0x298]` for any type, or another INT0 vector value), which has not been identified. The
firmware installs different INT0 vectors in many places (IVT offsets `2AF9`, `4614`, `691B`, `0979`, `390C`...).
Until the `0x84` handler runs, the DTE setup (`[0x270]` hook, `[0x5F1]` state) is not reached and AT input cannot be processed.

## 7. Next steps

1. Find how types `0x80-0x84` reach `[0x298]` (trace which ISR the real hardware vectors INT0 to at each phase; check the
   IVT writes listed above and `FDD9`).
2. Once the `0x84` handler runs, let the supervisor finish init, then type `ATA` (DTE model already exists: `Machine.send`).
3. Handle the DSP overlay loads (`E60A`): the DSP-side bank reception (ports `0x58-0x5F`, status `0x57`, INT4 handler `820C`).
4. Capture DSP serial/TDM output (`dsp.dsp_log`, ports `0x30-0x37`, DXR) as audio.

---
## UPDATE (later the same session): the supervisor now boots to a working AT prompt and runs `ATA`

**Section 6 above (the "DSP boot handshake blocker") was a misdiagnosis.** Events `0x80-0x84` are the supervisor's *own*
progress events (posted from ~32 places such as `8000:05B5`, `B629`, `222EC`), not DSP/boot-ROM messages. The synthesised `0x83`/`0x84`
DSP messages were removed (`rom_replies=False`). Real blockers were mundane hardware-model gaps:

| Symptom | Cause | Fix in `machine.py` |
|---|---|---|
| Supervisor idle, DTE input ignored (`[0x26A]=1D2A`) | `[0x313]` bit2 (DTE hold) cleared only if line probe `8000:2844` finds port `0x12` bit6 = 0; my port read echoed the *output latch* | Ports `0x10/0x12/0x14` are inputs: reads return `port_in` (0), never the written value |
| DTE TX hung at `8000:1617-1640` | The DTE UART is in the PCB: `[0xFF66]` bit3 = TX ready, `[0xFF6A]` = TX data register | PCB read `0x66` returns bit3 set; write `0x6A` appends to `dte_out` (modem output) |
| `AT` prefix scanner (`F1A0`) never installed | `F168` (called at `9EB0:0096`) needs `[0xEA7]`bit0 (NVRAM: DTE speed locked) and a non-zero autobaud result `[0x3FBA]` | Breakpoint at flash `0x1EB96` (phys `0x9EB96`) sets both (persistent across `ATZ` resets). The real autobaud works on raw oversampled bits from the DTE ASIC (detector `9CC9:0E27` looks for `0x16/0x96` patterns); I could not reproduce that stream |
| ISR called address 0 on first DTE char | `[0x270]` hook is zero in this boot flow | `Machine.send()` sets it to `1DF0` (bare `ret`) |
| Mailbox events lost | INT0 delivered before the real ISR was installed, and `0x1C` is a write-1-to-clear acknowledge of latched events (bit0 TX slot freed, bit1 DSP message), not a mask | Latch model: `evt`/`evt_seen`; INT0 only to a real vector; TX kick when ring `[0x29A]!=[0x29C]` |

`nvram_mode=None` (default flow, `[0x5F1]=4`) is the one that works. `nvram_mode=6` forces the other start-up flow (autobaud, never reached the prompt).

### Observed behaviour (real firmware, emulated)
Power-on banner on the DTE port: `TESTING RAM OK / ROM OK / NVRAM CHECKSUM FAILURE / DSP OK / LEDS AND SPEAKER / CURRENT DIPSWITCH SETTINGS ... SELF TEST COMPLETED`.
`ATI7` => `USRobotics Courier V.Everything Configuration Profile... Options HST,V32bis,Terbo,VFC,V34+,x2,V90; Clock 25 Mhz; Flash 512k; Ram 64k; Supervisor 03/13/98 rev 7.3.14; DSP 03/13/98 rev 3.0.13`.
`ATI3` => `USRobotics Courier V.Everything`; `ATI4` settings dump; `ATI0`=5607, `ATI1`=4AD8 (checksums), `ATI2`=OK.
Every command is followed by an extra `ERROR` (numeric `4` with V0): cause not yet understood (NVRAM failure state?).
`ATZ` re-initialises the DSP (reset pattern `83 83`, then cmd `01 3F`, `0F 00`).

### ATA
`ATA\r` runs the real handler (`a518:087D`). DSP traffic observed (cmd, arg): `83 83`, `01 3F`, `0F 00` (DSP re-init), then **`1A 00`, `3C D6`, `12 AB`** (first real mode commands). `12 AB` is the last: the supervisor then waits (timeout counter `[0x134]=0x1C20` ticks, loop `B845-B852`) for a DSP reply message whose handler sets `[0x32C]` bit7 (`B823`). DSP handler for cmd `0x12` = `86DB`: stores arg `0xAB` at `0x372` and installs per-sample task `[0x39A]=0x875A` (a sample generator: `lacc #72<<16; calld 8B75; ...`) - the first signal-generating routine. Commands `1A 00` -> `823B`, `3C D6` -> `8240`.

### Next
Run the DSP long enough with the real sample ticks and capture its serial/TDM output; find why it never posts the reply (task `875A` may complete via a counter/timer or needs the overlay/INT4 path); dump DAC samples to WAV.

---
## AUDIO CAPTURED (2026-11-14): `ATA` -> real DSP answer tone

`capture.py` (`capture(cmd, seconds, wav=...)`) boots the machine, sends the command, waits until the DSP has consumed command `0x12`, then records every
value the DSP writes to its serial transmit register DXR (MMR `0x21`; logged as pseudo-port `0x8021`) as 16-bit mono samples.
Result after `ATA\r` (command sequence `1A 00`, `3C D6`, `12 AB`):
* Output is a **2100 Hz tone**, peak 8388 (~0.256 FS), assuming one DXR write per sample at **7200 Hz** (= 3 x 2400, the V.34 symbol clock). Spectrum has exactly the
  lines at 7/24 and 5/24 cycles/write; 7/24 x 7200 = 2100 Hz. (7200 Hz is inferred from the tone identity; the DSP writes DXR ~1 per 3 of my assumed 2083-cycle codec ticks.)
* **Phase reversals** of the 2100 Hz carrier (dphi ~ pi) at t = 4.19, 7.34, 12.58, 13.63, 16.78, 17.83, 20.97, 24.12 s: clusters 3.15 s apart, pairs 1.05 s apart.
  Amplitude is flat (min/max over 16 ms blocks 8316-8388, no 15 Hz AM visible), so this looks like V.25 ANS (answer tone with phase reversals) rather than V.8 ANSam.
  Reversal spacing is 7560 samples (1.05 s at 7200 Hz), not 450 ms: either the DSP time base differs from my assumption or the sequence is a different variant.
* Files: `../out/ata_answer_tone_25s.wav` (25 s, 7200 Hz), `../out/ata_dxr.wav` (earlier 4 s). The supervisor still never receives a DSP reply for `12 AB` (waits then times out).

---
## FIX: DSP->host INT0 heartbeat = the supervisor's timebase (2026-11-14)

Problem: after `ATA` the tone stayed 2100 Hz (with phase reversals) forever. Cause: the supervisor's wait loop after cmd `12 AB` (`8000:B82F-B852`) ends on a DTE keypress (`[0x32C]` bit7 set by DTE handler `B823`) or when `[0x134]`
(init `0x1C20` = 7200) reaches 0; `[0x134]` is decremented once per **INT0 service** (`F52B` in the INT0 ISR tail, which also posts event 1 and calls `15010`). So INT0 is a periodic
heartbeat from the DSP interface at the DSP sample rate (7200/s => 1 s timeout). The machine only raised INT0 on mailbox events, so the supervisor never timed out.
`machine.py`: `heartbeat=True`, one INT0 per `hb_ticks=3` DSP serial ticks (about one per DXR sample; exact ratio unverified).

Result (40 s capture, `../out/ata_blind_handshake_40s.wav`, 7200 Hz): 2100 Hz tone for the first seconds, then at ~194M cycles the supervisor sends
`01 3F`, `1A 00`, `3C D6`, `21 00`, `1A 00`, `3C D6` and the output becomes a louder (peak ~18200) steady **1650 Hz** carrier (V.21 answering-channel carrier is 1650 Hz - identification is inferred, not decoded).
Per-second coarse analysis earlier wrongly reported 300/2700 Hz; always use a fine (10 Hz) grid and >= 1200-sample windows.
Still unexplained: no further stages (V.8 ANSam / V.34 / V.90) appear within 40 s without a remote modem.

---
## TWO-INSTANCE LINK (started 2026-11-14)
* DSP core now records every DXR write in a ring (`c5x_dxr_head/ring`); `Machine.take_tx()` returns new output samples; `Machine.rxbuf` is the input queue (one input sample consumed per own DXR write; `cur_rx` fed to `serial_tick`).
* `link.py`: `Link(a, b)` runs two `Machine`s in 100k-cycle slices and cross-feeds each side's output samples to the other's input queue. `linktest1.py` = first experiment.
* First result (B: `ATDT1`, A: `ATA`, 160 s): A behaves as before (answer tone, then ~1650 Hz carrier); B sends only `15 00`, `1F 00`, `19 0D` (x2) to its DSP and its DSP output stays silent. The caller is stuck early in call setup, most likely waiting for a line condition (dial tone / loop current / DAA status ports, which are fixed at 0 in `port_in`) that nothing provides. Next: find which line probe B waits on and model it (dial tone, ring on A).
* The WAVs live only in `../out/`. (A private hosted page was published by mistake and deleted at the user's request; do not upload files.)

---
## CALLER SIDE PROGRESS (2026-11-14)
* Commands DO take effect: `ATI4` shows the settings (default profile has `Q2` = no result codes, so a successful AT is silent). The first command after boot/reset prints a spurious `4`/`ERROR`; trailing ERROR after later commands is cosmetic. `ATX3` works (ATI4 shows X3) but does not unblock dialing.
* Dial path: scheduler exit -> go-online routine `8000:B542`; with `[0xEA7]` bit0 set (my patch) it runs the loop `B57C-B5A2` which repeats until `[0xBD7]` bits `0x1C` are set. `[0xBD7]` = line status byte from the call-progress sampler (`0x14EA0-0x14F43`, called every INT0 heartbeat through pointers `[0xBF6]/[0xBF8]`); it tracks tone/cadence timings (`[0xBDA]` etc.) and its input byte comes from the **DSP's own call-progress detector** (messages read from ports `0x5C/0x5E`). The detector listens to the DSP's *input audio*, which is silence in the emulator.
* Fix direction (works so far): model the line. `line.py` has `Tones`/`dial_tone()` (350+440 Hz, 7200 Hz samples); `Machine.rx_gen` supplies the DSP input when the queue is empty. With a dial tone on B's input, `[0xBD7]` becomes 0x02 and B's DSP gets new commands (`30 01`, `12 1C`, `16 16`, `30 00`) and produces audio (peak 8388).
* Still to do: identify what B sends (DTMF?), give A a ring, then link A and B through a central-office model (dial tone -> DTMF -> ring/ringback -> answer -> direct audio path).

### Caller works (with a dial tone on its input)
`ATDT1` with `X3` and a 350+440 Hz dial tone fed to B's DSP input (`Machine.rx_gen = line.dial_tone()`): B's DSP gets the dial sequence `15 00, 1F 00, 19 0D, 16 00, 1A C8, 1B 08, 13 01, ...` and its output shows
* a short loud **DTMF burst** at ~7.2 s after dialing (digit 1: ~697 + 1209 Hz, peak 22776), then
* repeating **1100 Hz bursts, ~0.5 s on / ~3 s off** = V.25 **CNG calling tone**; DSP command loop `30 01, 12 1C, 16 16, 30 00` per burst.
Result codes stay silent (Q2/no remote). Capture: `out/caller_B_dial_74s.wav` (74.7 s, 7200 Hz) made by `sys/capture_caller.py`.
`Machine.run` now drains DSP output every call (`tx_all` complete; keep single `run()` calls <= ~400M cycles).

---
## EMULATOR BUG FOUND AND FIXED: TBLR/TBLW modified ACC (2026-11-14)
User reported (a) the 'ATA blind handshake' WAV 'sounds wrong' and (b) the caller WAV had no DTMF, only periodic beeps. Cause: in `dsp/c5x_core.c`, TBLR/TBLW wrote the incremented program address back into ACC low
(`acc = (acc & 0xFFFF0000) | pfc`). On the real C5x (and in MAME) ACC is untouched by TBLR/TBLW. DSP code that reads two table words as `add #TABLE; tblr; add #1; tblr` therefore skipped a word.
Visible effect: the DTMF generator (cmd `13 dd`, handler `86E9`, increment table at DSP `86FD`) produced the *same* frequency for both oscillators (single 700 Hz sine of double amplitude instead of 697+1209 Hz),
and any other table-driven routine misbehaved (the later 'steady 1650 Hz carrier', the stuck 900+2700 Hz pattern on the caller are suspect too).
After the fix (DSP alone, cmd `13 d`): digit 1 = 697+1209, 2 = 697+1336, 5 = 770+1336, 9 = 852+1477, 0 = 941+1336 Hz, peak ~23.7k.
ALL AUDIO CAPTURED BEFORE THIS FIX IS UNRELIABLE (`out/ata_*`, `out/caller_B_dial_74s.wav`, `out/link2_*`, `out/link3_*`).
Lesson: validate the DSP core against known signal generators (DTMF, tone tables) before trusting captured audio; remaining risk = other subtly wrong C5x instructions.

### Second emulator fix (same session): interrupts inside RPT
The core accepted interrupts between iterations of a repeated instruction (`RPT`); on the real C5x a single-instruction repeat is not interruptible. An ISR that uses its own RPT would clobber the interrupted repeat counter. Symptom: in the two-modem harness the caller's DSP produced a stuck 8-sample periodic pattern (a "900 Hz" wave, peak ~18-22k) instead of DTMF, while the same caller alone produced correct DTMF (timing-dependent). Fix: `check_int` only when `rptc <= 0`.
Also: my quick spectrum scripts that subsample by 2 mirror frequencies about 1800 Hz (900/2700, 1500/2100, 1650/1950 appear as fake pairs). Use full-rate windows.

### Central office v2 (`link.py`)
dial tone (350+440 Hz) -> first DTMF burst -> keep tone until the burst ends -> cut tone ('dialing') -> after 3 s ringback (440+480 Hz, 2 s on/4 s off) -> after 2.5 s callee gets `ATA` -> audio connected both ways.
Reason for 'cut after the burst': cutting the dial tone at the exact start of the DTMF burst left the caller's DSP tone on forever in one scenario (race between the dial sequence and the dial-tone detector in `[0xBD7]`); unresolved, avoided for now.

---
## ROOT CAUSE of the stuck caller: digital silence on the line input (2026-11-14)
When the dial tone was removed the caller's DSP stopped consuming host commands: it was spinning at DSP `8810/8811` = `NORM *+` / `BCND 8810, ntc` (normalise ACC until bit31 != bit30). The loop never ends if ACC == 0; ACC there is a signal-energy estimate of the line input, which is exactly 0 for the emulator's silent input. A real line always has noise.
Fix: `Machine.noise_amp` (default 8 LSB peak, LCG pseudo-random) added to every DRR sample. This is the first piece of the "line noise" work the user planned for later: the minimum noise floor is a *requirement*, not an option.

---
## FIRST REAL TWO-MODEM CALL (2026-11-14, with noise floor)
Files (local only): `out/call_caller_left_answerer_right.wav` (stereo, 7200 Hz, 117 s: caller left, answerer right), `out/call_caller_B.wav`, `out/call_callee_A.wav`. Script: `sys/linktest4.py` (also run on the builder, see below).
Timeline (s of audio from the start of the call, central-office model in `link.py`):
* 0-7.3 dial tone to the caller; 7.38 DTMF digit `1`; CO drops the tone after the digit, ringback from 10.5, callee `ATA` at ~13.0.
* Caller: CNG 1100 Hz bursts at 13.3, 16.9, 20.5 s (cmd `12 271C`).
* Callee: ANS 2100 Hz from 20.2 s (`12 4AAB`), then at 23.3 s `21 0100` (answerer mode start) and a loud ~1660 Hz tone until ~59 s, then `21 4100`, DSP re-init (gives up).
* Caller hears the ANS and at 23.7 s sends `01 3F, 1A 3D00, 3C 32D6, 20 0100` (originator mode start) but then stays SILENT. No handshake exchange yet.
Hypothesis for the missing handshake: command `0x20`/`0x21` handlers are in DSP **overlay 8** (table entries DC9B / DC7B, overlay range 0xDC00-0xF8B6) but overlays are never loaded: `8000:E60A` (overlay loader, gated by `[0xE3C] != 0` at `8000:9272` and `B5FF`) has never executed. The base image occupies the same address range, so the DSP runs base-image *data* as code, which would also explain the odd 1660 Hz tone.
Builder machine: `agent@79.137.67.20` (8-core Xeon E5-1620 v2, 31 GB). Emulator copied to `~/sv25` with the user's permission (code + decoded flash + DSP images only). Builder boots the firmware in 13.6 s vs 28 s locally and runs the modem at 3.7x realtime.

### Diagnosis after the first call (builder run at t=40 s)
* Modes: `21 0100` (answer) / `20 0100` (originate) with param 0x0100 = V.21 (answerer sends 1650 Hz mark carrier). The start routine is in overlay segment `A110:1238-1255` (mode word read from a table via `22170`, [0xE88]&2 selects originate).
* Caller DSP at 40 s: idle main loop, per-sample task A = `8139` (nop), task B = `D8C1` (receiver, in the overlay-5/base region), **no transmit task**; it posts a status word pair every ~375k cycles (`5E=0x0008`, `5F=0x0002`) that never changes. Caller supervisor state `[0x26E]=452A`, reply handler `[0x298]=767C`, waiting; `[0xE3C]=0` (no overlay ever requested).
* Hypothesis: originator waits for the answerer's carrier; its carrier detector isn't triggering, possibly a level/format mismatch between A's DXR samples and B's DRR input. Testing line gains 0.5/0.25/0.1/0.04 on the builder (`sys/linkgain.py`).
* DSP-only harness (`dsp/rxtest.py`) did not reproduce the mode (no status messages), so it is not a valid test.

### Audio link verified (user asked 2026-11-14)
`sys/linkrx.py` on the builder at t=32 s: A produced 230,445 output samples and B 230,439 (rates match); each side's input queue backlog was only 40-46 samples (~6 ms). B's DSP receive ring (`0x0BD0-0x0BDF`, filled by the XINT ISR from DRR) contains A's tone (values like -14688, 9435, 14368, ±15k; every other slot is 0, the ISR writes two words per frame), so the DSP does read the fed samples. Line gain 0.5/0.25/0.1/0.04 made no difference to the caller's behaviour: not a level problem.
Message stats (t=0..45 s): B's DSP posts ~2350 status messages (low word 8, high word 0/2/129/145/128/64...), i.e. it reacts to A's tone; A's DSP posts only 5 words after its mode start. B's supervisor reply handler `[0x298]=767C` reacts to types 0x05/0x76/0x83 only, so the type-8 status words are ignored: the open question is which message the supervisor needs to continue the originate handshake.

---
## LINE SIGNALLING: ring detect added (2026-11-14, evening)
* Ring detect = **port 0x14 bit 1** (idle high). The per-heartbeat state machine (`[0xBF6]`, code at flash `0x1506A-0x1510E`) measures the high/low pulse widths and the period (`[0xBC2]` counter) against limits `[0xDF1]=0x18`, `[0xDF2]=0xB4` heartbeats. Heartbeats run at 2400/s of audio (= one INT0 per 3 DXR samples, the V.34 symbol rate; same as the 3 s ANS wait = 7200 heartbeats). So 20 Hz ring = 120-heartbeat period.
* `Machine.ring_on` toggles bit 1 every 60 heartbeats while the exchange rings the callee (US cadence 2 s on / 4 s off); the caller hears ringback (440+480 Hz) in the same cadence.
* Exchange v3 (`link.py`): dial tone -> DTMF -> tone dropped -> 3 s -> ring starts -> callee modem prints **RING** on its DTE -> exchange sends `ATA` ~0.4 s after the RING text (stops ring, ringback) -> connected. Verified: callee DTE shows `\r\nRING\r\n`, `ATA` sent at 13.6 s (3.2 s after the ring started).
* Forcing 300 bps with `AT&N1` + `ATB0` on both modems made NO difference: same DSP commands (`21 0100` / `20 0100`, same timings), same stall: caller silent after `20 0100`, callee holds ~1650 Hz until `21 4100` + DSP re-init at ~59 s; the caller never prints NO CARRIER. Mode word 0x0100 is already the 300 bps (V.21-type) mode.
* Recordings (local, `out/`): `call_auto_*` and `call_v21_*` (stereo caller-left/answerer-right + mono each, 75 s). Older ones in `out/old_before_ring/`.
* Builder usage: `sys/linkcall.py <auto|v21> <seconds> <outdir>` writes WAVs; both variants run in parallel in ~3 min.

---
## More dead ends and findings (2026-11-14, late)
* **V.22bis forced** (`AT&N3` + `ATB0` on both) and **hybrid echo** (10% of own TX mixed into RX, `Link.echo`): both runs produce the *identical* DSP command sequence and timings as the plain run (`21 0100` / `20 0100`, caller silent, callee gives up at 59 s with `21 4100`). So `&N`/`B` do not influence the mode word on this path, and echo is not what is missing. Recordings: `out/call_v22_*`, `out/call_echo_*`.
* **INT0 ISR variant during a call is `8F46:0979` (flash FDD9)**, not F460. DSP `type 8` messages (low word 8, high word = status bits 0x00/0x02/0x80/0x81/0x91...) are NOT dispatched through `[0x298]`; they are read directly by the call-progress sampler (flash `0x14D6F`, `0x14E08` read ports 0x5E/0x5C) into `[0xBD7]` (= word & 0x3F). On the caller `[0xBD7]` flickers 0/1/2 and only rarely 0x11; the dial loop `B57C-B5A2` needs bits 0x1C stable for 5 consecutive passes.
* Port polling during the stall (6 s of audio): both modems poll only port 0x14 through the probe at `0x2815` (~60 reads/s) plus the INT0 status ports; DAA latch (port 0x14 writes) is `E4/C4` on the callee and `F4/D4` on the caller. No stalled wait on a missing DAA line bit was found.
* The firmware tests ~17 DAA status bits (ports 0x10/0x12/0x14, masks 01..80) in 45 places (`27F9` probe); all held at constants by the emulator.
* Default profile after the NVRAM failure: `S00=001` (auto-answer after 1 ring), `&N0`, `&A1`, `X1`; `AT&F1` gives `X7 &A3 &B1 &H1 &R2` (no handshake-relevant change).
* DSP mode code: per-sample task pointers `[0x39A]`/`[0x39B]`; answerer installs TX task `D976` (`D970`), originator only RX task `D8C1` (`D890`); `D8C1` loop uses state bits in data word `0x370` (`bit 14,#70` -> `intr 17`; `bit 15,#70` -> `87B6/D94A`, `lacl #07; cc 87CE` = post message type 7). Nothing yet explains what makes the originate side start its TX task.
* `22170` (a110 overlay) selects the mode word (`0100`, later `4100`): it looks like an ordered list of candidate modes tried with timeouts.

## UPDATE (audio-path audit + detector probe, 2026-11-14 late)
- DXR output path verified: one DXR word per serial tick (1:1, NOT 1 per 3), clean single tone (1650 Hz = 0.2292*fs; ANS phase inc 0x4AAB = exactly 2100/7200) -> fs=7200 confirmed by the DSP's own constants.
- Link transport verified sample-exact: window of B's DRR input found verbatim in A's DXR output (lag 28-47 ms), 0 underruns while connected (Machine.rx_under / rx_log added; underruns before connect are just silence).
- Gain 0.04..0.5 gives IDENTICAL command timelines on both sides -> reaction is not level driven.
- Caller DSP detector (87B6/87CE): ACC after compare = 0x3296.. (>>threshold) -> carrier-on edge already posted once (flag [0x6F]=0x0088 set); no new type-4 posts since it only posts on edges. 83C8 not called again; ring [0x78]==[0x79] (empty). So carrier detect works; the missing piece is what the supervisor does next.
- Host handler [0x298]=8F46:767C (flash 16ADC) only acts on types 0x05, 0x76, 0x83; type 4 is ignored there.
- 80186 touches only ports 0x00,0x0A,0x0C,0x10,0x12,0x14 (output bits too: 0xC5/E5/D5/D1/F1/E1 written), 0x18,0x1A,0x1C,0x1E (+DSP banks 0x40-0x5E). Port 0x16 never used.
- UNMODELLED: (a) INT0 event-status bit2 (port 0x1C bit2) -> ISR calls hook [0x2D3] (via 8000:0674) = probably DSP data-pump service; I never raise it. (b) 0x18/0x1A status reads (~8.7k per call) are bank-full/ack flags of DSP bulk banks 0x40/0x44/0x48...; I return the last written value. (c) port 0x14 input bits other than ring (bit1). (d) overlay loader (E3C4..E732, uses banks + port 0x1E) never runs ([0xE3C]=0).

## UPDATE (supervisor wait state found, 2026-11-14 night)
- Both supervisors park in the a110:15E2 wait loop (flash 226E2): it spins while [0xE88] bit5 (0x20) is set. Bit set by DSP type-4 handler (flash 1608F) / routine 15E36; cleared by DSP message 0x76 (flash 16088) or timeout event 0x83 (16AEA/15E4E/21DC7); 0x76/0x83 are generated by supervisor code paths (0FD98, 14ADB, 15C02 = 'mov al,0x76; call [0x298]'), not by immediate-constant posts in the DSP base image.
- B (caller) ends with [E88]=0x22, [0x298]=767C, BD7=0x10 (stable, so the go-online loop B57C exits correctly and cmd 20 is sent); its timeout counter [0x134] freezes at 4 (decrement only in boot ISR 8F46:0000 tail F532; the in-call ISR FDD9 does not decrement) -> no 0x83 timeout ever fires on B, whereas A times out at ~35 s.
- Poking [E88]&=~0x20 on B makes the supervisor retry the whole mode start (cmds 08 003F, 1A, 3C, 20 0100) with no new behaviour.
- USER AUDIT (pending details): timer/serial interrupt vectors in my core are +0x10 too high (ivec[] = 02,04,06,18,1A,1C,1E,20,22 should be 02,04,06,08,0A,0C,0E,10,12 per user), serial tick raises XINT every tick (machine also raises TRNT+TXNT each tick), timer ticks per instruction not CLKOUT1 (2-4x too fast). TODO after user's full audit: fix core + rerun call tests.

## UPDATE (core audit applied, 2026-11-14 night) - git repo created (local only; `git log`), backup also in backup_pre_audit_20261114/
Applied (verified against doc/, the 1998 SPRU056D distillation): TINT/RINT/XINT/TRNT/TXNT/INT4 vectors 08/0A/0C/0E/10/12 (hardware IRQs still dispatch via ivec_ind slots; software `intr 17`=0x22 keeps legacy slot mapping); XINT only after a DXR write (+1 initial kick); no spurious TRNT/TXNT per tick; cycle model = per-opcode table GENERATED from the manual (dsp/gen_cyctab.py -> c5x_cyctab.h; 0 mismatches vs manual over all 176 table rows; repeats 1/iter; taken/not-taken conditionals 4/2; delay slots inside the branch's count); NORM ACC==0 -> TC=1; signed CRGT/CRLT; TIM reset 0xFFFF.
Switches: Machine.xint_mode/cycle_model/tdm_irqs/legacy (core c5x_set_legacy bitmask bit0 NORM, bit2 CRGT, bit3 TIM).
Opcode sweep (all 176 manual patterns): 0 BADOP, word lengths all match.
REFUTED audit items: CALAD=0xBE3D (core right), INTR does not clear IFR (core right), XC n counts WORDS (core right; changing it broke the call flow: dial 13.7 s instead of 7.3 s and caller never sent 20 0100 - the firmware has `xc 2,tc` before 2-word `lacc #lk`).
NORM fix means the noise floor is NOT needed any more (call with noise_amp=0 identical to noise 8).
DSP load measured: idle 36-90 percent per sample at 2083 cycles/sample, not starved.
STILL OPEN from audit: RPTC reset 0 / block move first instr, RETI must not restore INTM/XF (check_int sets intm before save_ctx), NDX=0 AR0 mirroring to INDX/ARCR (replaces cmpr_ar0 hack), RPTB PAER value, INTR K=1-4 context save, delay-slot stack order. Handshake still stalls identically (both supervisors wait in a110:15E2 for E88 bit5 to clear).

## Audit round 2 (c5x-core-audit-2026-11-14.zip)
Re-verification confirms same HIGH list; no new handshake-relevant finding. Applied: N-1 MADD/MADS no TRM mirror (legacy bit16 restores old), #9 RETI no INTM/XF restore (legacy bit32). Call timeline unchanged (digit 7.29, connected 13.57, A 21 0100 @23.55, B 20 0100 @23.89). Still stalled. Unapplied: RPTC reset, NDX mirror, RPT whitelist, N-5 SPC reset gating, clock-generator model (N-3).
