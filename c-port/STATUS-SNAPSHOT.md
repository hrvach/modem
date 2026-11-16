# Status snapshot — Courier C port, 2026-11-16 18:56 CET (work still running)

Source: modem.zip snapshot 2026-11-16 15:30, in `../modem/` (untouched).
Firmware: SV25.XMD decoded to fw/SV25.flash.bin, byte-identical to the
on-disk decoded copy (SHA-256 f24633ab12c21c3cef93c0f6c0bb8150021b0056953cb5517a95932abc673c52).
Profile: sv25. Never patched, never uploaded.

## Done and verified
- `make` builds lib/libc5x.a, lib/libi186.a, bin/courier-call.
  DSP core rewritten readable: src/dsp/c5x_core.c (2,611 lines).
  186 core rewritten readable: src/cpu/i186.c (1,795 lines).
  Glue in C: src/glue/machine.c, link.c, line.c, resamp.c, config.c, wav.c, main.c.
- `make run` writes exactly one WAV: out/call_auto.wav (stereo 22050 Hz,
  left = caller B, right = answerer A), plus out/call.log and
  out/transferred.txt. Config: call.conf.
- Python baseline (baseline/baseline.md, 20 s + 65 s): events digit 2.32,
  ringing 2.89, connected 4.70; callee loops on DSP cmd 02 B000;
  caller NO CARRIER ~62 s; no CONNECT, no 21 0100 / 20 0100.
- C run at default (gain 1.0, slice 1000) matches that baseline exactly
  on events and DSP commands (out/call.log, re-run 18:54).

## Headline since the first draft of this snapshot (see VERIFICATION.md §6–§7)
- Gain 0.5 CONNECTS, in both C and Python, identically:
  CONNECT 33600/ARQ/V34/LAPM/V42BIS on both sides, events unchanged
  (2.32/2.89/4.70), DSP commands after 12 s identical to the hundredth
  of a second. Default in call.conf is still gain 1.0 (the verified
  stall baseline); switching the default is Hrvoje's call.
- Slice sweep (1000/500/250/100/50, gain 1.0): NO CONNECT at any slice.
  Shorter slices do not cure it; gain is the lever.
- Pending: connected-regime raw-audio comparison at gain 0.5
  (C vs Python, sample-by-sample).

## In progress (not in this snapshot, or only partly)
- Frame-based link mode (slice after one frame, per-side clock tally
  with compensation) not yet landed — link.c/link.h/config were being
  edited at 18:55. See VERIFICATION.md §8.
- VERIFICATION.md is included in this zip and covers the slice-mode
  verification, wall times (C 70 s run: 145 s wall; Python 65 s: 260 s),
  and the gain/slice experiments above.

## Known discrepancy to reconcile
- fable-progress §62/§64: shared-clock slice 1000, GAIN 0.5, manual DSP
  cycle table, REP-fixed 186 → CONNECT 18.5 s both, 10 clean bytes each
  way; slice 1k–1M all connect. Our zip baseline (gain 1.0, zip cycle
  tables/cores) stalls. Gain is the prime suspect being tested next.
