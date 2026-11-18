# Verification — Courier modem emulator, Python glue → C port

Date: 2026-11-16. Port target: the zip snapshot at `c-port/modem/`
(2026-11-16 15:30), **exactly as-is** — no live-tree (w25a lockstep /
Bresenham) change was ported. Source of truth for the firmware is
`SV25.XMD`, never a pre-decoded bin (see §1). `modem/` and the live
handover tree were not modified.

> Status: the slice-mode port is **verified** (events, DTE text, DSP
> commands, raw audio and WAV export all match Python exactly — §3–§5).
> Two experiments are still open and recorded separately: the
> **gain** finding (§6, reproduced in both C and Python) and the
> **frame-mode** scheduler (§8, work in progress at time of writing).
> The default `call.conf` stays at the verified baseline
> (`link_slice = 1000`, `gain = 1.0`, `link_mode = slice`) until
> Hrvoje approves a change.

## 1. Firmware source of truth (Hrvoje correction)

- Canonical input: `~/workspace/research_notes/courier-firmware/SV25.XMD`
  — 524,416 bytes, SHA-256
  `43503d82caae5377d67c61f4f44d73e6a19e15c61b2cb706a70c6f1b88ef413f`.
- Decoded with the existing path (rolling-XOR, flash addr = file offset
  + 0x80):
  `python3 ~/workspace/research_notes/courier-firmware/handover-2-2026-11-15/handover/tools/sv25_decode.py SV25.XMD fw/SV25.flash.bin`
  → 524,288 bytes (0x80000), SHA-256
  `f24633ab12c21c3cef93c0f6c0bb8150021b0056953cb5517a95932abc673c52`,
  `cmp` clean against the on-disk `handover/SV25.flash.bin`.
  Verified independently three times (coordinator + DSP agent + 186
  agent + baseline agent — all identical).
- `make fw` runs exactly that decode (`make fw XMD=…` overrides the
  input); `make run` depends on it, so a clean checkout produces its
  flash from the XMD. The sv25 profile applies (cpu 25.8048 MHz,
  iface 25, sender_scan off, `dsp_base_bytes` 55420, isr_presets,
  `nvram.bin`). Nothing was patched, uploaded or published anywhere.

## 2. Python baseline (the reference behaviour)

Run from the zip with rebuilt x86-64 `.so` files (the zip ships ARM
aarch64 `.so` files, unloadable on this VM — rebuilt from the zip's own
C sources in a scratch copy only, `modem/` untouched; see
`baseline/baseline.md` for the exact commands). `PROFILE=sv25`,
`FLASH=<XMD-derived image>`, driver `python3 linkcall.py auto <dur>`.

| run | wall | events (s) | DTE A / B | DSP cmds after 12 s |
|---|---|---|---|---|
| 20 s | 2m25.379s | dialtone 0.0, digit 2.32, dialing 2.39, ringing 2.89, answering 4.7, connected 4.7 | A `\r\nRING\r\n`, B empty | A `0002 B000` @15.00, 21.65; B none |
| 65 s gate | 4m20.474s | same | A `RING`, B `\r\nNO CARRIER\r\n` | A `0002 B000` ×10 (15.00→75.94); B re-init `01 3F`/`0F 00`/`83 83` @62.44–62.88 |

**No CONNECT, no `21 0100` / `20 0100` anywhere.** The callee loops on
overlay-download command `02 B000` and the caller times out with
NO CARRIER at ~60 s. The 20 s run was repeated: log byte-identical
(deterministic). This zip baseline — stall at `02 B000`, NO CARRIER —
is the port's target, **not** the Nov-14 `STATUS.md` timeline (digit
7.29, connected 13.57, `21 0100` @23.55), which comes from an older
CO model (`DIAL_DWELL` 3.0 s vs 0.5 s, ring 2 s vs 1 s) and a handshake
that progressed further. See §7 for the reconciliation with
fable-progress §62/§64.

Baseline WAVs (linkcall writes raw audio, no resampling):
`baseline/run20s/` (20 s) and `baseline/*.wav` (65 s, SHA-256s in
`baseline/baseline.md`).

## 3. Build and unit tests (coordinator, clean checkout)

```
$ make clean && make        # gcc -O2 -Wall -Wextra -std=gnu11
real 0m8.5s — zero warnings, zero errors; lib/libc5x.a, lib/libi186.a, bin/courier-call
$ make test                 # test_resamp (DC, 2:1 downsample), test_config, test_line,
                            #   ./bin/courier-call --help — all PASS, exit 0
$ make run                  # 70 s, gain 1.0, slice 1000 — see §4
```

Core rewrites (exact behaviour, differential-tested against the
original sources rebuilt for x86-64):

- DSP (`src/dsp/c5x_core.c`, 2,611 lines from 691): all six
  `smoke1–6.py` byte-identical; two extra scenarios (cycle model,
  XINT, `cmpr_ar0`, breakpoints/watch/trace, serial ticks, IDLE/timer)
  identical on cycles, I/O events, DXR ring and diagnostics. All 45
  exported `c5x_*` symbols identical (`nm -D` diff empty). Zero
  behavioural deviations.
- 186 (`src/cpu/i186.c`, 1,795 lines from 453): 94 targeted cases +
  60 randomized trials, all pass (registers, cycles, badop, ring,
  IRQ, RAM SHA-256, IO/MMIO log); boot smoke identical in both cycle
  models. All 26 exported `i186_*` symbols identical. One preserved
  quirk, flagged not fixed: in legacy cycle model 0 a segment prefix
  decodes as a bad opcode (orig. L291–292) — the real firmware hits
  it in model 0, so the glue must keep using model 1 (it does).
- Resampler + `_Lp6` vectors (`tests/vectors/`, harness
  `/tmp/check_vectors.c`, not shipped): all 9 checks **EXACT,
  maxdiff 0** — resampler at 7200→22050, 9600→22050, 7200→8000,
  8000→7200; `_Lp6` at fc 1800/7200, 2400/9600, 3240/7200,
  4320/9600, 4620.15/10267 (including the transparent and razor-edge
  cases). The 7200→22050 vector returns 2206 samples, not 2205 — C
  reproduces the extra sample.
- `c5x_cyctab.h` copied verbatim (`cmp` clean) — generated data.

## 4. C vs Python comparison — slice mode (the verified baseline)

`make run` (70 s, sv25, auto, gain 1.0, slice 1000), final clean run:

```
courier-call: profile sv25 — flash: fw/SV25.flash.bin, nvram: fw/nvram.bin
  mode: auto  duration: 70 s  wav_rate: 22050  gain: 1  slice: 1000
events: (0.00,dialtone) (2.32,digit) (2.39,dialing) (2.89,ringing) (4.70,answering) (4.70,connected)
A DTE: \r\nRING\r\n \r\nNO CARRIER\r\n    B DTE: \r\nNO CARRIER\r\n
A DSP cmds after 12 s: (15.00,0002,B000) (21.65,0002,B000) (28.13,0002,B000) (35.56,0002,B000)
  (42.46,0002,B000) (49.16,0002,B000) (55.90,0002,B000) (62.59,0002,B000) (69.03,0002,B000)
  (75.94,0002,B000) (81.71,0046,003F) (81.77,0058,003F) (81.83,0045,003F) (81.89,0001,003F)
  (81.91,0083,0083) (82.14,0001,003F) (82.14,000F,0000) (82.16,0083,0083)
B DSP cmds after 12 s: (62.44,0046,003F) (62.50,0058,003F) (62.56,0045,003F) (62.62,0001,003F)
  (62.64,0083,0083) (62.86,0001,003F) (62.86,000F,0000) (62.88,0083,0083)
wrote out/call_auto.wav (610631/505033 samples A/B), out/call.log, out/transferred.txt
wall time: 145 s
```

| check | Python baseline | C (`make run`) | match |
|---|---|---|---|
| events (digit/ringing/connected) | 2.32 / 2.89 / 4.70 | 2.32 / 2.89 / 4.70 | YES, exact |
| setup replies | `(b'', b'')` | A= B= (empty) | YES |
| DTE text A / B | `RING` / `NO CARRIER` | `RING` + `NO CARRIER` / `NO CARRIER` | YES, byte-identical |
| DSP cmds after 12 s (A, 65 s vs 70 s) | `02 B000` ×10 @15.00–75.94 | identical ×10 + same 81.7–82.2 s re-init block | YES |
| DSP cmds after 12 s (B) | `46/58/45/01/83/0F` @62.44–62.88 | identical | YES |
| CONNECT / `21 0100` / `20 0100` | none | none | YES |
| audio sample counts A / B (70 s) | — (65 s run: A 570,734 / B 468,760 frames at 7200 Hz) | 610,631 / 505,033 (tx samples; WAV is 22050 Hz, 1,546,670 frames = 70.14 s) | counts reproduce exactly across two independent C builds (glue agent's run and the coordinator's `make run` both gave 610631/505033) |
| `out/` contents | three WAVs (old driver) | exactly ONE WAV: `out/call_auto.wav` (6,186,724 B, stereo, 22050 Hz) + `out/call.log` + `out/transferred.txt` | as specified |

20 s C run (`--config` with `duration 20`, `wav_rate 7200`, wall 51 s):
events, DTE text and DSP commands identical to the Python 20 s run
(see §5 for the audio comparison). Speedup: Python 20 s = 145 s wall
vs C 20 s = 51 s wall (**2.8×**); Python 65 s = 260 s vs C 70 s =
145 s (**~1.9×** on the long run; the boot's 900M cycles dominate
short runs, so the ratios differ — both walls quoted raw).

## 5. Audio comparison — raw audio and WAV export are exact

This needed care, because the two drivers export differently:
Python `linkcall.py` writes **raw** tx audio (its stereo file is
byte-identical to its mono files at lag 0), while C follows the
specified `link.py write_wav` semantics (per-rate-segment sinc
resampling, one shared resampler, A then B). Comparing C's WAV
against Python's raw files directly therefore measures the export,
not the emulator — the first such comparison looked like a mismatch
and was wrong.

- **Raw audio (emulator): identical.** `COURIER_DUMP_RAW` debug aid
  in `main.c` (env-gated, writes raw int16 A/B): C 20 s run vs Python
  20 s mono WAVs — **A: 0 differing / 167,078, B: 0 differing /
  145,095, max diff 0, RMS 0.0**. The ported emulator produces
  sample-identical audio.
- **WAV export (resampling): identical.** Faithful replica of
  `link.py write_wav(rate=7200)` over the Python mono files, using
  the real per-segment `rate_idx` (A has 14 entries — the codec rate
  changes during the handshake: 8640/9600/8000 Hz segments at tx
  59637, 98037, 108000, 146400, 155941; B has 4) — **A: 0 differing /
  145,097, B: 0 differing / 145,097, max diff 0, RMS 0.0** vs the C
  WAV. (An earlier single-rate replica that ignored the rate cuts
  disagreed; the rate cuts were the whole difference. C's own
  resampler was also shown chunk-invariant: 4096-sample chunks ==
  single call, and it reproduces the Python replica exactly on the
  same input.)
- **PENDING — `rate_idx` equality:** the replica above used the C
  run's `rate_idx` lists. A direct Python-vs-C `rate_idx` list
  comparison (20 s Python run printing both lists) was still running
  at time of writing; raw-audio identity over 312,173 samples plus
  identical command/event streams makes a difference very unlikely,
  but it is not yet directly verified. (Update this line when it lands.)

## 6. Gain experiment — the lever that connects (fable §31/§62)

`gain` is now a config key (`call.conf`, default **1.0** = the verified
baseline; `GAIN` env fallback; `link.c` uses `cfg->gain`, was hardcoded
1.0). Fable says 1.0 overloads the receiver (+6 dB net with codec
gain) and the handshake never starts; 0.5 is the narrow operating
point (§31: "Use GAIN 0.5 as the default line loss from now on").

| run | gain | result |
|---|---|---|
| C, 70 s, slice 1000 (wall 314 s, contention-inflated) | 0.5 | **CONNECT 33600/ARQ/V34/LAPM/V42BIS on BOTH sides**; A DSP cmds after 12 s: (16.21,000A,0001) (16.27,0057,003F) (16.27,000A,0001) (16.54,000A,0003); B: (16.18,000A,0001) (16.24,0057,003F) (16.25,000A,0001) (16.49,000A,0003); events unchanged (2.32/2.89/4.70) |
| Python, 70 s, scratch driver (`L.gain=0.5`, zip untouched; wall 549 s) | 0.5 | **CONNECT 33600/ARQ/V34/LAPM/V42BIS on BOTH sides**; events identical; DSP commands after 12 s **identical to C's, to the hundredth of a second** (same four entries per side, same times) |

So gain 0.5 connects in **both** implementations with identical
events and identical DSP command times — this is a property of the
emulated system, not a port divergence. **No default was changed:**
`call.conf` still defaults to `gain = 1.0` (the verified stall
baseline). Whether to switch the default to 0.5 is Hrvoje's call.
Note the C gain-0.5 binary printed a spurious `config: unknown key
'gain' ignored` warning — the key *was* applied (the run header
printed `gain: 0.5`); the `known[]` key list just lacked the name.
Fixed in `src/glue/config.c` afterwards; the warning is gone in the
rebuilt binary.

- **PENDING — connected-regime audio:** a C gain-0.5 70 s run with
  `COURIER_DUMP_RAW` was launched to compare raw audio against the
  Python gain-0.5 mono WAVs sample-by-sample (the §5 check, but in
  the connected regime). (Update this line when it lands.)

## 7. Slice sweep (Hrvoje's "shorter slices should cure it")

C, 70 s, gain 1.0, sv25/auto, slices 1000 / 500 / 250 / 100 / 50
(each a separate `courier-call` run; wall times contention-inflated
because runs overlapped with other jobs — 137 / 186 / 122 / 185 /
185 s — and are not clean speed measurements):

| slice | events | outcome |
|---|---|---|
| 1000 | 0.00/2.32/2.39/2.89/4.70/4.70 | stall: `02 B000` loop from 15.00 s, NO CARRIER both |
| 500 | same | stall: `02 B000` loop, NO CARRIER both |
| 250 | same | stall: `02 B000` loop, NO CARRIER both |
| 100 | same | stall: `02 B000` loop, NO CARRIER both |
| 50 | same | stall: `02 B000` loop, NO CARRIER both |

No CONNECT, no `21`/`20` at any slice. Shorter slices do **not**
cure the connect issue in this zip branch — exactly as
fable-progress §64 says for the shared-clock model (slices
1000/10000/100000/1000000 all connect clean *at gain 0.5*;
CONNECT just moves later with larger slices). The slice is not
the lever here; the gain is (§6).

### Reconciliation with fable-progress §62/§64 (read, not assumed)

§62 (shared-clock link, slice 1000): "Full call with all defaults
(manual DSP cycle table, REP-fixed 186 core, delay 0, GAIN 0.5): NO
retrain, result tags 37/30/03/35/36/02 at 17.8 s on BOTH, CONNECT
18.5 s on both, exactly 'HelloFromB' / 'HelloFromA' 10 bytes each, no
noise. Files: out/slice1k_final/." §64 table: 1000/10000/100000/
1000000 → CONNECT 18.5 / 18.51 / 19.14 / 20.15 s, all clean.
This **contradicts** our zip baseline only if the configs are the
same — they are not. Differences between the §62 run and our
baseline, checked against the text and the trees:

- **GAIN 0.5 (§62) vs 1.0 (zip `link.py` hardcodes `self.gain =
  1.0`)** — the documented handshake-breaker (§31, §62). Prime
  suspect, now confirmed empirically in §6.
- **Firmware: same (SV25).** The live tree's `machine.py` defaults
  to `SV25.flash.bin` directly (no `profiles.py` there), and
  `call_data.py` uses `GAIN` default 0.5 — §62 ran SV25, as did our
  baseline. (The `out/slice1k_final/` directory itself is not
  preserved in the live tree snapshot, so this rests on the driver
  defaults, stated here as the evidence rather than as certainty.)
- **CO timing:** §63's `Link.co_step` had `DIAL_DWELL` fixed 3.0 s
  and US ring cadence 2 s on / 6 s period; the zip has 0.5 s / 1 s /
  6 s (env knobs). Digit matches exactly (2.32 s both); ringing /
  connected differ (ours 2.89 / 4.70 vs §63's 5.40 / 8.21). A
  possible secondary contributor, not tested in isolation.
- **Driver:** §62 used `tools/diag/call_data.py` (sends
  `HelloFromA`/`HelloFromB` after CONNECT, `L.run(8*CPU_HZ)` boot,
  1.5×CPU_HZ setup steps); our baseline used `linkcall.py` (no
  payload, 900M-cycle boot, 150M-cycle setup steps). The handshake
  itself should not depend on the payload.
- **Same:** manual DSP cycle table, REP-fixed 186 core, shared
  absolute clock, slice 1000, delay 0, noise default 8, direct
  (non-8kHz) line. Live has no `LINE8K`/resampler; the zip's
  `LINE8K=0` default is the same direct copy.
- §62 does **not** prove shorter slices cure anything — §64 says
  the opposite for slice size once the shared clock is in.

## 8. Frame-mode link scheduling (Hrvoje's design correction)

PENDING — implementation delegated at time of writing. Design:
slice boundary after one codec frame per modem (one `_sample()`
period), per-side CPU+DSP clock tally with debt/credit so a side
that uses more in one go gets less in the following passes,
`link_mode = slice | frame` (default `slice`), old mode kept for
the verified baseline. Results (events, CONNECT?, `21`/`20`?,
`02 B000`/NO CARRIER?, wall time, tally drift max/mean, Python
per-frame attempt) to be added here when the work lands. The
default stays `slice` until Hrvoje approves a switch.

## 9. Known gaps / behaviour intentionally not ported

- `link_mp.py` (multiprocessing two-process link) — explicitly out
  of scope; the single-process `link.py` is the target.
- Python's unbounded `log`/`pcblog`/`dsp_log`/`rx_log` are capped at
  2^20 entries in C (they stop growing past the cap); `tx_all`,
  `cmd_log16`, `msg_log`, audio stay exact. `hostbytes` omitted
  (dead in Python).
- The two core headers cannot both be included in one TU (each
  defines plain `io_rd_fn`/`io_wr_fn` with different signatures);
  `machine.h` forward-declares the core ABIs it uses. Flagged to the
  core owners, not a behaviour issue. (`i186.h`'s `i186_set_hooks`
  prototype uses the plain names while `c5x_core.h`'s `c5x_set_io`
  uses prefixed ones.)
- WASM was not built (per instructions); the seam is documented in
  README (OS calls isolated in `main.c`/`config.c`/`wav.c`).
- `dsp_base.bin` on disk is informational — `start_dsp` uses the
  supervisor's captured bursts, as in Python.
- Env vars are never required; `call.conf` is the source of truth.
  Override order: CLI > `call.conf` > env (keys absent from the
  file only) > profile defaults.
- The zip-vs-live diff (1,028 lines, `baseline/diff_zip_vs_live.txt`)
  confirms the trees are divergent branches; the port targets the
  zip only. Live-only w25a lockstep/Bresenham was not ported.

## 10. Commands to reproduce

```sh
cd ~/workspace/research_notes/courier-firmware/c-port/c
make clean && make            # zero warnings
make test                     # all PASS
make fw                       # SV25.XMD -> fw/SV25.flash.bin (SHA-256 checked)
make run                      # 70 s fake call -> out/call_auto.wav (one WAV),
                              #   out/call.log, out/transferred.txt
./bin/courier-call --config /tmp/c20/call20b.conf   # 20 s, wav_rate 7200 (see §5)
COURIER_DUMP_RAW=/tmp/raw/raw ./bin/courier-call --config <conf>  # raw A/B dump
```

Python baseline (from a scratch copy; the zip's `.so` files are ARM):
see `baseline/baseline.md` for the rebuild commands and the exact
`linkcall.py` invocations.
