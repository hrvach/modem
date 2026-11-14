# Status — USR Courier V.Everything (SV25) two-modem emulation

Date: 2026-11-14. Git: local repo only (last commit 524dc2b). Detail log: `sys/FULL_SYSTEM.md`.

## Background (read this if you are new)
- **The device.** A USRobotics Courier V.Everything (3453B/C) dial-up modem. Its firmware
  image is `SV25.XMD` (a flash update file; encrypted with a rolling XOR, decoded by
  `sv25_decode.py` into `SV25.flash.bin`, flash address = file offset + 0x80).
- **Two processors.** An Intel 80186 runs the "supervisor": AT commands, dialing, call
  state machine, DTE serial port, NVRAM. A TI TMS320C51 DSP does the modem signal
  processing (tone generation/detection, modulation, line codec). The 80186 downloads the
  DSP's program at boot (images in `dsp/dsp_*.bin`, three overlays ov6/ov7/ov8 loaded later
  by the host) and talks to it through a mailbox: commands to the DSP, a message ring back.
- **The emulator.** `sys/` is a full-system emulator (80186 core in C, memory map,
  peripherals, line codec) and `dsp/` a C5x core, both driven from Python. It boots the real
  firmware unmodified: AT commands work, the modem dials and rings.
- **The test.** `sys/link.py` joins two emulated modems with a simulated phone line (audio
  samples at 7200 Hz, one machine's DSP output = the other's input). `sys/linkcall.py`
  makes one dial the other. A real modem pair would now exchange handshake tones
  (answer tone, then V.8/V.21/V.22/V.32/V.34...) and report CONNECT. Ours do not.
- **Why it matters.** The goal is a working emulated handshake, then line noise, V.34/V.90
  audio and a web/WASM demo. Nothing is known about the firmware beyond what we
  disassembled ourselves; there is no source and no datasheet for the board, only the
  TMS320C5x manual in `doc/`.
- **Names used below.** `[0xE88]` etc. are 80186 data-segment RAM addresses; `a110:15E2`
  is segment:offset in the 80186 address space (flash phys 0x80000 base, so flash offset =
  seg*16 + off - 0x80000); "type-4 / 0x76 / 0x83" are DSP-to-host message codes.

## Goal
Make two emulated modems (80186 host + TMS320C51 DSP, full system) complete a real
handshake over an emulated line; later V.34/V.90 audio, line noise, web/WASM demo.

## What works (verified)
- XMD decode, 80186 boot, DSP image download, host<->DSP mailbox, DTE AT commands.
- Dial tone, DTMF/pulse dialing, ringing, "answering", "connected" (call timeline below).
- DSP audio output path (DXR->line), Fs = 7200 Hz (checked against DSP constants),
  link transport between two machines is sample-exact, carrier energy detector fires.
- C5x core audited against the 1998 manual (`doc/`): 176/176 opcode patterns decode with
  correct length and cycle count; vectors, XINT, cycle table, NORM, CRGT/CRLT, TIM fixed.

## What does NOT work
The handshake never completes. Both supervisors park in 80186 code at a110:15E2 (flash
0x226E2) spinning while `[0xE88] & 0x20`. That bit is set by the type-4 handler (flash
0x1608F) and is cleared only by DSP message 0x76 (0x16088) or the 0x83 timeout paths
(0x16AEA, 0x15E4E, 0x21DC7). Neither arrives. The caller's timeout counter `[0x134]` stays
frozen at 4 during the call, and the originate TX never starts.

Reference timeline (any change here is a regression): dial digit 7.29 s, ringing 10.36,
connected 13.57; callee DSP gets `21 0100` at 23.55 s and `21 4100` at 59.1 s; caller gets
`20 0100` at ~23.89 s.

## Core audit outcome (two audits, `00-consolidated-report.md`, `c5x-core-audit-*.zip`)
Applied and regression-gated: vectors, XINT-on-DXR-write, manual-derived cycle table,
NORM acc=0, signed CRGT/CRLT, TIM reset FFFF, MADD/MADS no TRM mirror, RETI no INTM/XF
restore. **None changed the call timeline.**
Audit claims that were WRONG (do not re-apply): CALAD missing (it is 0xBE3D, implemented),
INTR clears IFR (it does not), XC skips instructions (XC n counts WORDS; applying the
"fix" delayed dialing to 13.7 s and broke the caller).
Not applied: RPTC reset 0, NDX=0 AR0 mirroring (a hack `cmpr_ar0` stands in), RPT
non-repeatable whitelist, RPTB PAER value, INTR K=1-4 context save, SPC RRST/XRST gating,
clock-generator model, delay-slot stack order.
Legacy switches (`LEGACY` env / `Machine.legacy`): bit0 NORM, bit2 CRGT/CRLT unsigned,
bit3 TIM reset 0, bit4 MADD/MADS TRM mirror, bit5 RETI restores INTM/XF.

## Leading hypotheses for the stall (all outside the C5x instruction semantics)
1. Unmodelled 80186-side peripheral behaviour: INT0 event port bit2 (hook `[0x2D3]` via
   8000:0674), DSP bank-status ports 0x18/0x1A, port 0x14 DAA bits.
2. Overlay loader never triggered (`[0xE3C]` = 0); DSP overlays ov6/ov7/ov8 never loaded.
3. Clock ratios: 80186 25 MHz assumption, ~9600 ticks/s, DSP_CPS=2083 cycles/tick and
   DSP_RATIO=0.8 are guesses. The DSP is idle 36-90% so it is not starved.
4. ROM vector-stub model (`ivec_ind`, data[0x60+n]) is invented; real mask ROM unknown.

## Constraints from the user (must be respected)
- Never upload/publish the user's files (audio, firmware, code) anywhere online. No Artifact
  tool for this project. Local paths only.
- Only remote machine allowed: builder `agent@79.137.67.20`, `~/sv25` (emulator code,
  decoded flash, DSP images only; no audio, no SV25.XMD/SDL25.EXE; no package installs).
- Local machine is weak: <= ~2 python jobs. Run parallel/heavy jobs on the builder.
- Save notes as you go (`sys/FULL_SYSTEM.md`); give WAV copies in `out/`.
