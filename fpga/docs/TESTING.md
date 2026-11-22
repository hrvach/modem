# Testing the Courier modem core (for the next engineer or agent)

State as of 2026-11-22. Read `docs/GOAL.md` and `docs/ARCHITECTURE.md` first for what the core is. This file is about how to test it and where things stand.

## 0. Rules from the owner (do not break these)
- **Never overwrite a file the owner has edited on the MiSTer**, above all `/media/fat/modem/baresip-cfg/accounts` (the Twilio password). Edit one field with `sed`, print it with `auth_pass` masked, and say so first. Scripts must not ship an accounts file.
- **Keep the Twilio setup intact.** The test peer has its own config dir and `start.sh twilio|peer` flips between them.
- Do not touch `/dev/ttyS1` while the owner is dialling by hand. The owner has allowed dial tests from `/dev/ttyS1` when they ask for them.
- Tell the owner in 1-2 sentences what a job longer than ~10 minutes is doing. Notice finished builds yourself.
- One Quartus build at a time. Never `pkill -f` (it kills your own shell); use PIDs or `pgrep -x`.
- No workarounds that hide bugs. The C emulator (`../courier`) and the manual are ground truth.
- Do not pipe `curl | sh`. Install through the OS package manager; the owner runs `sudo`.

## 1. Machines
| What | Where |
|---|---|
| Repo | `/home/hrvoje/Programming/courier_fpga` (git, `main`) |
| C reference emulator | `/home/hrvoje/Programming/courier` |
| MiSTer (DE10-Nano) | `root@192.168.10.254`, password `1`; use `SSH_ASKPASS` with `SSH_ASKPASS_REQUIRE=force` (a one-line helper script printing the password) |
| Quartus builder (x86_64, Debian 13) | `agent@builder.hrvoje.org` (public IP 79.137.67.20), Quartus in `/opt/fpga/17.1/quartus/bin` |
| D-Modem peer (software modem) | on the builder, `~/dmodem/` |

The builder has the armhf cross compiler (`gcc-arm-linux-gnueabihf`) and `cmake`, `libssl-dev:armhf`, `zlib1g-dev:armhf`, `libzstd-dev:armhf`. **`gcc-multilib` conflicts with the cross compiler**: installing one removes the other. D-Modem is already built, so keep the cross compiler.

## 2. FPGA builds and deploying a core
```
bash tools/qbuild.sh full        # ~35 min, writes the run id to .qbuild_runid
bash tools/qwait.sh              # waits, prints errors
```
Results are on the builder: `~/modem-runs/<run id>/output_files/Modem.rbf`, `Modem.sta.summary` (setup slack per PLL clock: `general[1]` is the 40.32 MHz DSP clock, currently about -1.3 to -3.4 ns; `general[2]` is the CPU clock).
Deploy:
```
scp <rbf> root@192.168.10.254:/media/fat/_Computer/Modem/            # keep the file name pattern Modem_YYYYMMDDx.rbf
ssh root@192.168.10.254 'sed -i "s#Modem_2026112[0-9a-z]*#Modem_<new>#" /media/fat/Modem.mgl; echo "load_core /media/fat/Modem.mgl" > /dev/MiSTer_cmd'
```
Loading a core clears `/tmp` logs and **drops any call**. The core boots in ~15 s; the first AT response can take several seconds more.
**After every core reload resync the ring counters** (see 5): the FPGA restarts its counters at 0, the HPS count lives on in DDR. (Fixed in RTL from build `run-20261122-022828-full` on; older builds need the manual resync.)

## 3. Unit tests and the fast simulator
- `make -C tests test` runs everything. Some tests (`c5x_*`, `smoke*`) are stale for the new ports / s80x86 files and fail for build reasons, not RTL reasons. Passing and relevant: `dsp_glue`, `line_ddr`, `i186_sys`, `aic`, `bus_trace`, `dbg_status`.
- `tb/tb_fast2.sv` is the fast system simulator (186 + DSP + glue + codec, flat memory, real DTE UART). Build recipe: see the `verilator` lines in the history of this file's git log, or copy from `build/tests/fast2r`: sources are `rtl/cdc.sv dte_uart.sv dsp_glue.sv aic.sv i186/*.sv s80x86/i186_core_s86.sv <s80x86 files in dependency order> dsp/*.sv tb/tb_fast2.sv`, flags `--binary --timing -O3 -Itb -DMICROCODE_ROM_PATH=\"$PWD/rtl/s80x86/gen\"`.
  Useful plusargs: `+flash= +nvram= +rom=` (sdcard/games/Modem/boot0.rom boot1.rom boot2.rom), `+memwait=2`, `+send="ATQ0V1X3~ATDT12~"` (`~` = Enter, `@` = wait 30M clocks) `+sendat=<dsp clk>`, `+clocks=`, `+mon=<every N>`, `+gw +gr +dfrom= +dto=` (glue port traces), `+rxfile=<decimal int16 per line> +rxat=<dsp clk>` (feed the line input), `+restore=<prefix>`.
  **A boot from reset needs ~300M DSP clocks (~30 minutes). Do not do that: restore from a C snapshot instead.**
- Restore workflow (80 seconds instead of 30 minutes):
  1. C side, in the scratchpad tool `courier-rl4` (source `machine_rl.c` in the session scratchpad; it is the C emulator's `machine.c` plus recording hooks): `SYS_SNAP_T=15.7 SYS_SNAP_PREFIX=<dir>/pre courier-rl4 --config call.conf --out <dir>` dumps `pre_mem.bin pre_dsp.bin pre_sys.txt` (modem B, an instruction boundary).
  2. `python3 tools/mksnap.py <dir>/pre` writes the DSP hex files and a 186 restore stub at 0x70000 + reset-vector jump.
  3. `Vtb_fast2 +restore=<dir>/pre +flash=... +memwait=2 +clocks=12000000`.
  The scratchpad tools are session-local; `tools/mksnap.py`, `tb/tb_fast2.sv`, `tb/dsp_restore.svh` (generated from the co-sim loader) are in the repo.
- DSP co-sim against the C core: `sim/cosim.cpp` (`--replay LOG --snap FILE --cycles N`), see `docs/cosim.md`.

## 4. The call test rig
```
 DTE terminal (/dev/ttyS1, 115200)        MiSTer HPS                                      builder (79.137.67.20)
 AT commands --> modem core (FPGA) --DDR rings (0x3A000000)--> baresip + modemline module --SIP/RTP-->  D-Modem peer (soft modem)
                                         lined.py (exchange: DTMF -> INVITE, ring, answer)           or Twilio trunk
```
On the MiSTer, `/media/fat/modem`: `baresip` (static armv7, module `modemline` built in), `lined.py`, `linering.py`, `capture.py`, `tones.py`, `start.sh`, `term` (minicom wrapper), `baresip-cfg/` (Twilio: config + accounts, **the owner's**), `baresip-peer/` (test peer: config + accounts).
- `./start.sh twilio` / `./start.sh peer` restarts baresip (SIP trace on) and the controller. Peer mode dials `sip:<digits>@79.137.67.20` over plain UDP/RTP (UDP 5060, RTP 4000-4011; the builder's firewall must allow both **inbound and outbound** UDP to the owner's home IP).
- Logs on the MiSTer: `/tmp/baresip.log` (SIP trace, RTP stats at the end of a call), `/tmp/lined.log` (digits heard, call events). On the builder: `~/dmodem/modem.log` (soft modem), `~/dmodem/wrap.log` (d-modem and pjsip).
- **Test call, one command: `bash tools/dial.sh`** (about 3 s to the INVITE, then it watches the call until it closes; prints the new `lined.log` lines). `RELOAD=1 [RBF=Modem_YYYYMMDDx] bash tools/dial.sh` first reloads the core and sets up the modem (use it after a new .rbf, or after a failed call that left the modem dead: no digits in `lined.log`, or `NO CARRIER` / `NO DIAL TONE` straight away) and takes ~20 s. `DIGITS=`, `WAIT=` as in the script header. It needs only ssh to both machines.
- **The D-Modem answerer arms itself; do not touch it.** `peer.py start` answers with `ATS7=120` + `ATA` 3 s / 5 s after it starts and again 9 s / 10 s after every `NO CARRIER`. The SIP listener refuses an INVITE earlier than ~9 s after that `ATA` and the answer wait lasts 120 s (S7), so the answerer is valid from 10 to ~110 s after the last `ATA` in `~/dmodem/modem.log`. **Never send `ATH` by hand**: slmodemd needs ~24 s to tear down (`modem_stop` is logged that long after the hangup), and a manual `ATH` + `ATA` leaves a listener on 5060 whose modem has already timed out. An INVITE to such a stale or early answerer shows up as `d-modem.c: error writing frame` in `~/dmodem/wrap.log`, `d-modem exited rc=1`, and `CALL_CLOSED Connection reset by peer` right after `CALL_ESTABLISHED` on the MiSTer. `dial.sh` checks the last peer event itself and runs `bash ~/dmodem/peer_restart.sh` (kills slmodemd / d-modem / peer.py, restarts `peer.py`, returns when 5060 has been up for 10 s, ~15 s) only if the answerer is not armed. D-Modem is patched (`hps/peer/*.patch`): answer mode when started by ATA, runs without root, `-e` option fix.
- Modem setup that must hold before a dial (after every core reload; `dial.sh` with `RELOAD=1` does it): `AT&B1` and `ATQ0V1X3` (without `X3` the modem answers `NO DIAL TONE` at once: the line has no dial tone). `kill -HUP lined.py` does nothing (started with nohup, no handler): restart both with `./start.sh peer` on the MiSTer.
- **Dial from the MiSTer** (modem B): `printf 'ATQ0V1X3\r' > /dev/ttyS1; printf 'ATDT100\r' > /dev/ttyS1` (`ATX3`: no dial tone wait). Digits go through `lined.py` after 2.5 s without a digit. For a hand test the owner types in `/media/fat/modem/term`. (`dial.sh` does this and the checks above.) A DSP halt is visible in the heartbeat (Ctrl-A x3, D; again to turn it off): `G=` last byte bit 4 set = halted, `H=<PC><opcode>` = the BADOP. `Q=810A` is the idle park.
- **Record a call**: `python3 capture.py 60 /tmp/cap` (saves every 5 s; `_tx.raw` what the modem sent, `_rx.raw` what the line fed it, both int16 at the codec rate, normally 7200 Hz; `_rate.txt`). Analyse with numpy (FFT per half second): TX should show DTMF, then V.8 CM / handshake tones; RX the far end's ANSam (2100 Hz).
- **Line state**: `python3 linering.py` prints `alive`, codec rate, underruns, `rx_taken`. `rx_taken` must advance 7200/s while audio flows.
- The speaker plays the modem's DAC plus (while the firmware's speaker latch, port 0x12 bit 4 active low, is on) the incoming line audio.

## 5. The DDR line interface (`rtl/line_ddr.sv`, `hps/linering.py`)
Physical 0x3A000000: word 0 magic (bytes `MDMLINE1`), 1 TX count, 2 RX taken, 3 status (cps | underruns | tx_lost | version), 8 control (low 32 bits RX count made available by the HPS, bit 32 ring request, bit 33 connected), TX ring at word 0x400, RX ring at 0x1400, 16384 samples each.
**The control word survives a core reload; the FPGA restarts at 0.** Builds before `263d4bd` replay the old ring content after a reload (stale answer tone, squeals): resync by setting the control count to `rx_taken` before starting baresip (`struct.pack_into("<II", ln.m, A_CTRL*WORD, taken, 0)`), then `start.sh`. The module and `linering.Line` start from the control word's count.

## 6. Reading a crash: the trap rings (build `run-20261122-022828-full` and later)
A trap latches when the codec rate is anything but 7200 / 9600 / 10237 Hz (cycles per frame 5600 / 4200 / 3939) for 5 ms, or no codec frame for 10 ms. It freezes three 64-entry rings: host to DSP commands (`#`), DSP to host messages (`$`), DSP instructions retired (`!`, pc and opcode). After the crash, turn the heartbeat on from the terminal (Ctrl-A three times, then D; again to turn it off): each heartbeat line is followed by the rings. Capture `/dev/ttyS1` while it prints and feed it to `python3 tools/trapdump.py capture.txt [dsp listing]`. The heartbeat's `Q=` is the DSP program counter; `Y=`/`C=` count DAC samples / DXR writes. Reloading the core clears the trap.

## 7. Where things stand (2026-11-22)
Working on the board: AT, ATA answer tone, DTMF dialling (fixed: the glue now keeps event 0 "mailbox free" when the 186 clears it after the DSP acked), SIP calls through Twilio (TLS + SRTP mandatory, From = a verified number, 407 digest) and through the D-Modem peer (plain UDP), RTP both directions without loss.
**The open bug:** when the modem hears an answer tone and starts the handshake, the DSP derails. Observed with the D-Modem peer: the modem reacts to the ANSam, starts a V.8 menu (energy at 980 Hz) for about half a second, then the DSP runs wild (program counter in the 0xF000 range, codec frames go on, the DAC repeats the same 8 samples: a steady 900 + 1800 Hz squeal at 7200 Hz) until the core is reloaded. `ATA` alone has also crashed after a few seconds on an older build. In one call the codec rate was set to 4000 Hz, which this modem never uses. The 186 command sequence up to the answer matches the C emulator. The first bad instruction is still unknown: that is what the trap rings are for. The C emulator's own two-modem call does not get past ringing with the SV20 config, so there is no C reference for the handshake yet; the plan was to feed the recorded ANSam (`recordings/`, session scratchpad `rx_ansam.txt`) to the C core and compare.
Other open items: 40.32 MHz timing is still negative (-1.3 to -3.4 ns on the DSP clock); the 186 core (s80x86) runs unthrottled (no cycle governor); the first character of `NO CARRIER` ("N") is sometimes missing on the DTE port (not investigated; suspect a UART write while the previous character is still being sent); the AT response takes several seconds after a core load; `make test` has stale tests.

## 8. Things that cost time (so you do not repeat them)
- A boot from reset in the simulator takes ~30 minutes; always restore from a C snapshot.
- `sed -i` on the owner's accounts file only, never `scp` over it.
- The Debian armhf `libcrypto.a` needs `-lz -lzstd`; `gcc-multilib` removes the cross compiler.
- `slmodemd` has an option-table bug (`-e` takes no value) and wants root; patched in `hps/peer/slmodemd-nonroot.patch`.
- The heartbeat trace timestamps wrap every 6.6 s; read the rings in index order.
- A recorder that only writes at the end makes the owner wait: `capture.py` now saves as it goes.

## 9. Plan C (the owner's idea): a DDR trace of the DSP
If the frozen 64-entry rings and the C comparison are not enough: log the DSP's retire stream (pc, opcode, acc, ar0-ar7, st0/st1 per instruction, or per codec frame for a longer reach) into a large circular buffer in the HPS DDR through the same DDRAM port as `rtl/line_ddr.sv` (a second region, tens of megabytes), freeze it with the trap, and read it from the HPS afterwards (`/dev/mem`, as `hps/linering.py` does). Run the same scenario in the C emulator with an equivalent trace and diff the two offline: the first differing instruction is the bug, no cycle-accurate replay needed. Needs a DDR write port shared with `line_ddr` (a small arbiter), about 35 minutes of Quartus time, and care for DDR bandwidth (one 64-bit write per retire at the DSP clock is within what the f2sdram port takes; pack several entries per word if not).

## DSP core regression tests (`tests/dsp_regress/`)
One test per fixed bug in `rtl/dsp`, each with the expected value the C reference core produces for the same program:
`tests/dsp_regress/build.sh && python3 tests/dsp_regress/dsp_regress.py [name ...]` (13 tests; needs verilator and g++). Add a test here with every RTL fix; the story behind each one is in `docs/INTERRUPT_FINDINGS.md`. The 669 vector tests and the interrupt fuzzers live with the C-model harness in the session scratchpad (`rtltest/`) and are not part of the repo yet.
