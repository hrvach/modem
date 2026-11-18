# Python baseline — Courier C port (zip snapshot 2026-11-16 15:30)

Date: 2026-11-16. Source ported exactly: `c-port/modem/` (zip). No C code written.
No firmware patched. Nothing uploaded/published. Local only.

## Firmware source of truth (per Hrvoje correction)

- Canonical input: `~/workspace/research_notes/courier-firmware/SV25.XMD`
  - 524,416 bytes, SHA-256 `43503d82caae5377d67c61f4f44d73e6a19e15c61b2cb706a70c6f1b88ef413f`
- Decoded with the existing path (rolling-XOR, flash addr = file offset + 0x80):
  `python3 ~/workspace/research_notes/courier-firmware/handover-2-2026-11-15/handover/tools/sv25_decode.py ~/workspace/research_notes/courier-firmware/SV25.XMD /tmp/SV25.decoded.flash.bin`
  - Output: 524,288 bytes (0x80000), SHA-256 `f24633ab12c21c3cef93c0f6c0bb8150021b0056953cb5517a95932abc673c52`
  - `cmp` against on-disk `handover-2-2026-11-15/handover/SV25.flash.bin`: **clean, byte-identical**. No discrepancy.
- Both baseline runs below used `FLASH=/tmp/SV25.decoded.flash.bin` (the XMD-derived image), `PROFILE=sv25`
  (sv25: cpu 25.8048 MHz, iface 25, sender_scan off, dsp_base_bytes 55420, isr_presets, nvram `modem/sys/nvram.bin`).

## How the baseline was run (important: .so arch)

The zip's shipped `.so` files are **ARM aarch64** (`file` confirms: `libi186.so`, `libresamp.so`,
`libc5x.so` all `ARM aarch64`) and this VM is **x86_64** — the stock zip cannot load at all
(first attempt failed: `OSError: .../libi186.so: cannot open shared object file`).
The zip's own C sources were therefore rebuilt for x86-64 in a scratch copy only —
`modem/` itself was NOT modified:

```
rm -rf /tmp/cport-run && cp -a <zip>/modem /tmp/cport-run/modem
cd /tmp/cport-run/modem/sys && gcc -O2 -fwrapv -shared -fPIC -o libi186.so i186.c
cd /tmp/cport-run/modem/sys && gcc -O2 -shared -fPIC -o libresamp.so resamp.c -lm
cd /tmp/cport-run/modem/dsp && gcc -O2 -fwrapv -shared -fPIC -o libc5x.so c5x_core.c
```

Build flags are the ones in `modem/HANDOVER.md` (plus `-lm` for resamp, per its own header comment).
Rebuilt `.so` verified `ELF 64-bit LSB shared object, x86-64`. The Python code run is the zip's,
unmodified; only the compiled artifacts were re-targeted to the host arch. (The live handover
tree's `.so` files are x86-64, but using them would have mixed live binaries into a zip baseline,
so they were not used.)

## Commands run

No `c/` Makefile existed yet, so there was no C-port `make run` mode to match; default per task: `mode=auto`.

```
cd /tmp/cport-run/modem/sys
time PROFILE=sv25 FLASH=/tmp/SV25.decoded.flash.bin python3 linkcall.py auto 20  <outdir>   # short run
time PROFILE=sv25 FLASH=/tmp/SV25.decoded.flash.bin python3 linkcall.py auto 65  <outdir>   # full gate run
```

`linkcall.py` = the exact driver: boot 900M cycles, setup `AT` / `ATQ0V1` (+`ATQ0V1X3` on B),
then `start_call("1")`, run until `dur` seconds of 7200 Hz call samples.

## 20 s run — `baseline_20s.log` (wall 2m25.379s real, 2m23.478s user)

Verbatim stdout:

```
== mode auto setup replies: (b'', b'')
events: [(0.0, 'dialtone'), (2.32, 'digit'), (2.39, 'dialing'), (2.89, 'ringing'), (4.7, 'answering'), (4.7, 'connected')]
A (callee) DTE text: b'\r\nRING\r\n'
B (caller) DTE text: b''
A DSP commands after 12 s: [(15.0, '0002', 'B000'), (21.65, '0002', 'B000')]
B DSP commands after 12 s: []
wrote call_auto_*.wav (20 s)
```

Setup replies are empty: expected under sv25 NVRAM — default profile is Q2 (no result codes),
so a successful AT is silent (see `sys/FULL_SYSTEM.md`).

## 65 s gate run — `baseline_65s_gate.log` (wall 4m20.474s real, 4m13.473s user)

Verbatim stdout:

```
== mode auto setup replies: (b'', b'')
events: [(0.0, 'dialtone'), (2.32, 'digit'), (2.39, 'dialing'), (2.89, 'ringing'), (4.7, 'answering'), (4.7, 'connected')]
A (callee) DTE text: b'\r\nRING\r\n'
B (caller) DTE text: b'\r\nNO CARRIER\r\n'
A DSP commands after 12 s: [(15.0, '0002', 'B000'), (21.65, '0002', 'B000'), (28.13, '0002', 'B000'), (35.56, '0002', 'B000'), (42.46, '0002', 'B000'), (49.16, '0002', 'B000'), (55.9, '0002', 'B000'), (62.59, '0002', 'B000'), (69.03, '0002', 'B000'), (75.94, '0002', 'B000')]
B DSP commands after 12 s: [(62.44, '0046', '003F'), (62.5, '0058', '003F'), (62.56, '0045', '003F'), (62.62, '0001', '003F'), (62.64, '0083', '0083'), (62.86, '0001', '003F'), (62.86, '000F', '0000'), (62.88, '0083', '0083')]
wrote call_auto_*.wav (65 s)
```

Notes on reading these numbers:

- Event times are call-time seconds from `start_call` (samples/7200). Command times are
  `tx_all` sample positions / 7200 (linkcall clears `tx_all` at `start_call`, but the DSP
  sample counter runs ahead of call time when the codec rate rises above 7200 Hz, so command
  times run past the 65 s call duration — last A entry 75.94).
- `0002 B000` is host→DSP command **0x02, word 0xB000**: the overlay-download command
  (`machine.py` `dsp_wr`: `cmd == 0x02` sets `ovl_addr = h2d[0x5F]`). The callee sends it
  repeatedly every ~6.5–7 s and never progresses past it.
- B's entries at 62.44–62.88 s are the caller giving up: `01 3F` (DSP re-init) + `0F 00`
  + `83 83` reset pattern, after printing `NO CARRIER`.
- **No CONNECT, no `21 0100` / `20 0100` anywhere in 65 s.** This does NOT match the
  `STATUS.md` (2026-11-14) reference timeline (dial digit 7.29 s, ringing 10.36, connected
  13.57; callee `21 0100` at 23.55 s, `21 4100` at 59.1 s; caller `20 0100` at ~23.89 s).
  Differences vs that reference: (a) the zip's CO model is faster — `DIAL_DWELL` 0.5 s
  (live/old: 3.0 s), ring cadence 1 s on / 6 s period (old: 2 s on / 6 s) — so digit/ringing/
  connected land at 2.32 / 2.89 / 4.7 s instead of 7.29 / 10.36 / 13.57; (b) the handshake
  itself never reaches V.21 mode start in the zip: the callee loops on overlay-download
  `02 B000` and the caller times out with NO CARRIER at ~60 s call time. The C port's
  target behaviour is therefore THIS zip baseline (stall at `02 B000`, NO CARRIER), not
  the Nov-14 STATUS.md timeline. Whether the zip regressed vs Nov 14 or the old timeline
  came from a different machine/link revision was not investigated — no code was changed.

## Determinism check

The 20 s run was repeated into `run20s/` (wall 2m32.540s): `run20s.log` is **byte-identical**
to `baseline_20s.log` (`diff` clean, `LOGS_IDENTICAL`). The 65 s WAV audio payloads are
byte-identical to the 20 s WAV audio payloads over the 20 s prefix (all three files, `cmp`
on the audio data after the 44-byte WAV header). The baseline is deterministic on this host.

## WAV files (in this directory)

`linkcall.py` writes all three with the same names for every run, so the 65 s run overwrote
the first 20 s set in place. The 20 s set was re-run into `run20s/` and is preserved there.

| file | bytes | SHA-256 |
|---|---|---|
| `call_auto_callee_A.wav` (65 s) | 1,141,512 | `3ec9544e35ef3016b668b03e29c3c4f00bd0e9f04608f8daf403e9a247106e3d` |
| `call_auto_caller_B.wav` (65 s) | 937,564 | `0901da4128025bd68f5c383607ba00c62d6c35d39f41ebd21f1c153cb963caa6` |
| `call_auto_caller_left_answerer_right.wav` (65 s) | 1,875,084 | `86633483605a93f6c2453a05f55a61c5bce036873877c0eadb4c38afc9f3a72f` |
| `run20s/call_auto_callee_A.wav` (20 s) | 334,200 | `545f21ad777cc544eacd445b3a7840e6d05f8025fae92d4875953a4733cbca05` |
| `run20s/call_auto_caller_B.wav` (20 s) | 290,234 | `f40be0bf2ad802c83b7fe54a7c27cf632d1b672dc4f83aaf3d931e4b6de3fd03` |
| `run20s/call_auto_caller_left_answerer_right.wav` (20 s) | 580,424 | `9aa179b402f0f75c45372a6f4704a7c513681bb11f7b2a88cb2ab3e88d320166` |

## Test vectors — `../tests/vectors/`

Generated by `/tmp/gen_vectors.py` (+ `/tmp/gen_i186_smoke.py` for (d)); each file carries a
header comment with the exact code/command that produced it. Generator inputs are deterministic
(LCG seed 12345; no randomness, stdlib only).

| file | content | SHA-256 |
|---|---|---|
| `resamp_7200_to_22050.csv` | Resampler, 720 in → 2206 out int16 | `0f3dab5e6990a3eba08329edf221759379c32d4f862f186356f079b1d1bf0fec` |
| `resamp_9600_to_22050.csv` | Resampler, 960 in → 2205 out int16 | `f464350c227f9a6dfc8fefab8ee9d0ed95d503c5a0b9658001ee76c29eb3f4e3` |
| `resamp_7200_to_8000.csv` | Resampler, 720 in → 801 out int16 | `cbfe851d941b2c752f6f29577cbaba732e66dc66b1a681e6efeffb1379255873` |
| `resamp_8000_to_7200.csv` | Resampler, 800 in → 720 out int16 | `1230a1aade5adf1d763dbb8c1df294cafc5e01fbf4859238233cf6eb8237efd7` |
| `lp6_7200_B18.csv` | _Lp6 fc=3240 fs=7200, 512 in/out doubles — transparent (0 sections) | `d1c2b99c7a4fc728f28a79b70d30aa0686a3c6310eb5e7966dccf7137bdabeea` |
| `lp6_9600_B18.csv` | _Lp6 fc=4320 fs=9600, 512 in/out doubles — transparent (0 sections) | `54c4a45ac0ecdca83d07d531be90b9d357b1f96cb67dc228b0551fb3265f79b0` |
| `lp6_7200_B10.csv` | _Lp6 fc=1800 fs=7200, 512 in/out doubles — 3 biquad sections | `843bb075199ee2ad0f5350126135364bd2fa859ce0dc073e044abbc0cf996a5c` |
| `lp6_9600_B10.csv` | _Lp6 fc=2400 fs=9600, 512 in/out doubles — 3 biquad sections | `72bd20fda7a04526d5d5fe9b7b6dc50c57a7638e117f66f777b75b39a6de322b` |
| `lp6_10267_B18.csv` | _Lp6 fc=4620.15 fs=10267, 512 in/out doubles — 3 sections (razor edge: fc is ~1e-12 below 0.45*fs in float, so NOT transparent despite B=18) | `d19e40bab1c99cef0a31683442ec06a3c656ca2646e6b24c6bdfaa722bc1ae3c` |
| `dsp_smoke_base.txt` | DSP standalone, dsp_base.bin only, reset 0x8000, 8×1M cycles | `9e358f6fd99018d07f9e7db1cd5b160ab9246808e387d29f3cb43650e2d689be` |
| `i186_smoke_boot.txt` | 186 boot to AT prompt, AT→OK, ATI7→profile | `0c135a8586276765de60a1665c36807eeaeab27c657f0be4747a62af84f51b43` |

Vector details:

- (a) Resampler input (all pairs): `int(8000*sin(2π·1000·i/rate)) + (10000 if n//4≤i<n//2 else 0) + LCG-noise[i]`,
  clamped int16; `LCG: x=12345; x=(1103515245·x+12345)&0x7fffffff; noise=(x>>16)%20001-10000`.
  `Resampler` = zip `sys/link.py` via ctypes on the rebuilt `libresamp.so`
  (`rs_new`/`rs_run`; group delay 63.5 input samples). Note 7200→22050 returns 2206
  samples, not 2205 (720·22050/7200 = 2205) — the resampler emits one extra sample; C must match.
- (b) _Lp6 input (all cases): 512 doubles, `LCG-noise[i] + int(5000·sin(2π·500·i/7200)) + (8000 if 256≤i<384 else 0)`.
  `machine.py` uses `fc = rate·(aic[2] or 18)/40`, `fs = rate`; `aic[2]=18` default, so B=18 is the
  in-machine case (transparent at 7200/9600 — the filter is a no-op there, which the C port must
  reproduce, including the `fc >= 0.45·fs` transparency rule); B=10 cases exercise the real
  3-biquad path. Section coefficients are in each file's header. Outputs are `%.17g`.
- (c) DSP smoke: `DSP(); load_images(d); d.reset(0x8000); d.log(True); 8 × d.run(1000000)`.
  Result: RUN_OK throughout; DSP parks in the `8097/8098` idle loop from 1M cycles on
  (`PC=8098 ACC=00000001 T0=0000 ST0=2607 ST1=25BD IFR=0028 IMR=0000 AR1=0022 AR7=0BD0`),
  `dxr_head=2`, `idle_cycles=0`, `timer_expiries` 59→476 (≈59.5 per 1M cycles).
  `pm_checksum = sum(pm[0x8000:0x8000+27710]) & 0xFFFFFFFF = 952823955 (0x38CAF093)`,
  `dm_checksum = sum(dm[0:0x10000]) & 0xFFFFFFFF = 491427 (0x00077FA3)`.
  `dsp_base.bin` 55,420 bytes, SHA-256 `b87b2b30e217aed19a3499209b935432707adc1ed7c6e28eb0ec7c2cca92f886`.
  Only 13 IO events total (first: `pc=8001 W port=0057 val=FFFF`, then AC01 port writes
  `0068/0069/006A/006B/006C`, then `8032/8022/8021`); full list in the file.
- (d) 186 smoke: `Machine(nvram_mode=None); run(900_000_000)` → `cpu_cycles=900000015`
  (15 over budget — the core overshoots the budget by the last instruction), `phys_pc=0x8934D`
  (idle loop `8000:934D`), `badop=(0, 0)`, DSP attached with DSP PC `810A`.
  `dte_text` after boot was empty (`b''` — no banner captured on this path);
  `AT\r` → `\r\nOK\r\n`; `ATI7\r` → full profile (`US/Canada External`, `HST,V32bis`,
  `Clock Freq 25 Mhz`, `Supervisor 03/13/98 rev 7.3.14`, `DSP 03/13/98 rev 3.0.13`).
  Total wall 48.1 s (boot 38.5 s, AT 4.4 s, ATI7 5.2 s).

## Zip-vs-live differences (port target is the ZIP)

Full diffs: `diff_zip_vs_live.txt` in this directory (1,028 lines: file list + full diffs of
`machine.py`, `link.py`, `i186.c`, `c5x_core.c`, `c5x.py`, `i186.py`, `link_mp.py`).
Live tree compared: `handover-2-2026-11-15/handover/` (files dated 2026-11-16 15:03 — slightly
NEWER than the zip's files, but a divergent branch, not a linear successor).

Diff line counts (`diff | wc -l`): `sys/machine.py` 271, `sys/link.py` 133, `sys/i186.c` 358,
`dsp/c5x_core.c` 131, `dsp/c5x.py` 35, `sys/i186.py` 12, `sys/link_mp.py` 8, `sys/linkcall.py` 0,
`sys/line.py` 0, `dsp/c5x_cyctab.h` 0, `sys/FULL_SYSTEM.md` 5 (zip has the 2026-11-16 time-policy section).

What the ZIP has that live does NOT (C port must include these — they are in the target):

- `sys/profiles.py` (whole file; live has none) — per-firmware profiles; sv25 hardcoded
  values in live (`cpu 25.8048 MHz`, `dsp_base_bytes 55420`, isr presets `0x81AE/0x8189/0x820C/0x81B7`)
  become profile-driven in the zip. `nvram_SV20.bin` also differs between the trees
  (zip `1602bc4d…`, live `b9316805…`); `nvram.bin` is identical (`513b2f7e…`).
- `sys/resamp.c` + `libresamp.so` and `Resampler` in `link.py` (live has no resampler at all);
  `LINE8K` 8 kHz telephone-line path; `Link.write_wav()` (rate-segmented resample to 22050 Hz).
- `machine.py`: `_Lp6` AC01 filter + `AC01_FILT`/`AC01_LAT` switches, `SEC_FRAME`, `CMD_OVR`,
  `INT23` (DSP INT2/INT3 wiring), `PORT_RB`, `HB_TIMER` (heartbeat from DSP timer expiries,
  `hb_ticks=1` vs live's fixed 3), `DSP_CLK_FIXED`, `IFACE403` mailbox model, `CPU_SCALE`/
  `UD_TRAP`/`CPU_MODEL` env knobs, `sender_scan` for the DSP message sender, `rate_idx`
  tracking, `Link`-slice env `LINK_SLICE`, `DIAL_DWELL`/`RING_ON`/`RING_PERIOD` env knobs.
- `dsp/c5x.py` + `c5x_core.c`: SIB-core alternative (`DSP_CORE=sib`, `libc5x_sib.so`),
  `CYC_EXP` cycle-table experiments, `timer_expiries`, `ff_count`, NDX=0 AR0 mirroring
  (`cmpr_ar0`/`ar0_dirty`), circular-buffer `circ_end`, SBBB C-only fix, TREG1/TREG2 masking
  (`& 0x1F` / `& 0xF`), `rsrfull` handling, `dm_internal` CNF/OVLY-aware, XC uninterruptible
  count fix.
- `sys/i186.c` / `i186.py`: hook types defined in-file (live factors them into `i186.h`),
  `cycle_scale`, `ud_trap`, `rep_resume` (REP yields at budget), `ioarr` accessor;
  live instead has TF-single-step suppress, `bp_skip`, ESC-trap/`test_pin`/WAIT, NULL-safe
  accessors, `ring_idx & 255`, and several cycle-table value changes (e.g. some 7→8, 14→10,
  23→6, 28→4 entries) plus RPTB/PAER loop handling.
- Extra zip-only scratch/harness files: `boot1-3.py`, `callertest*.py`, `capture*.py`,
  `find_dial*.py`, `isolate*.py`, `linktest*.py`, `dsp/smoke*.py`, `trace1.py`, `handlers.py`,
  `host1-3.py`, `romcheck.py`, `audio_scan*.py`, `dsp/sib/`, `c5x_core.c.bak`, `doc/`,
  `fable-progress.md`, `STATUS.md`. Live-only: `.git`, `SV25.flash.bin(+.hdr)`, `fw/`,
  `firmware_derived/`, `notes/`, `out/`, `docs/`, `sys/i186.h`.

What LIVE has that the ZIP does NOT (C port must NOT include these — they are not in the target):

- `Link.run_lockstep()` (w25a, per-sample lockstep) + `Machine.run_to()` + exact rational
  cycles/sample (Bresenham `_sc_num/_sc_den`, `_dc_num/_dc_den`); the zip uses the older
  shared-absolute-clock slice model (`Link._gt`, `slice` 1000, `co_step` on 100k-cycle windows)
  with floor-division `CPU_HZ // rate` / `DSP_HZ // rate`.
- `link.py` ring handling reads accumulated text for RING (live) vs per-chunk (zip);
  `DIAL_DWELL` fixed 3.0 s and ring 2 s on / 6 s period in live (zip: 0.5 s / 1 s / 6 s env).
- `i186.h` refactor and the i186/c5x audit fixes listed above.

Net: the two trees are divergent branches of the same Nov-16 work; the zip is the
multi-profile/resampler/AC01 branch, live is the lockstep/Bresenham branch. The C port
targets the zip only.
