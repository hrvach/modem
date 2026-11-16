# Courier modem emulator — C glue

A readable C port of the Python glue that drives two emulated USRobotics
Courier V.Everything modems through a fake call: 80C186EB supervisor +
TMS320C5x DSP + peripherals (`machine.py`), the two-modem phone line
(`link.py`, `line.py`), the call driver (`linkcall.py`), profiles
(`profiles.py`) and the WAV export. The cores themselves are NOT ported
here; they are C already and are built from `src/cpu/i186.c` and
`src/dsp/c5x_core.c` (verbatim copies from `modem/sys/` and `modem/dsp/`,
owned by other agents).

Source snapshot ported: `modem/` in `c-port/` (the ZIP snapshot, exactly
as-is — no later live-tree changes such as the w25a lockstep/Bresenham
rewrite were imported). Never patch the firmware.

## Firmware source of truth: SV25.XMD

The firmware comes from **SV25.XMD**, not from a pre-decoded flash bin.
Canonical input:

    ~/workspace/research_notes/courier-firmware/SV25.XMD
    524,416 bytes, SHA-256 43503d82caae5377d67c61f4f44d73e6a19e15c61b2cb706a70c6f1b88ef413f

It is decoded with the existing decode path (rolling-XOR decode, flash
address = file offset + 0x80):

    python3 ~/workspace/research_notes/courier-firmware/handover-2-2026-11-15/handover/tools/sv25_decode.py SV25.XMD fw/SV25.flash.bin

which produces a 524,288-byte image, SHA-256
`f24633ab12c21c3cef93c0f6c0bb8150021b0056953cb5517a95932abc673c52`
(verified byte-identical with `cmp` against the on-disk
`handover-2-2026-11-15/handover/SV25.flash.bin`). `make fw` runs exactly
that decode (`make fw XMD=/path/to/SV25.XMD` to override the input);
`make run` depends on it, so a clean checkout produces its flash from
the XMD. `call.conf` documents the same in its header comments, and the
`flash` key names the decoded image `make fw` produces. Never upload or
publish the XMD, the decoded flash, or audio anywhere; local files only.

## Layout

    Makefile                  make / make fw / make run / make test / make clean
    call.conf                 the call: profile, mode, setup strings, toggles
    fw/                       SV25.flash.bin (made by `make fw`), nvram.bin,
                              dsp_base.bin, dsp_ov6/7/8.bin (reference images)
    out/                      make run outputs (see below)
    src/glue/machine.c/.h     port of machine.py (CPU+DSP+PCB+UART+EEPROM+AC01)
    src/glue/link.c/.h        port of link.py (shared-clock two-modem line)
    src/glue/line.c/.h        port of line.py (dial tone, ringback)
    src/glue/resamp.c/.h      readable port of resamp.c (Kaiser sinc, 128 taps,
                              1024 phases, same formulas)
    src/glue/config.c/.h      profiles (profiles.py) + call.conf parsing
    src/glue/wav.c/.h         16-bit PCM stereo WAV writer
    src/glue/main.c           port of linkcall.py (boot, setup, dial, outputs)
    src/dsp/c5x_core.c/.h     TMS320C5x core (verbatim copy; owner: DSP agent)
    src/dsp/c5x_cyctab.h      core cycle table (verbatim copy)
    src/cpu/i186.c/.h         80186 core (verbatim copy; owner: CPU agent)
    tests/                    test_resamp.c, test_config.c, test_line.c

## Build and run

    make            # lib/libc5x.a, lib/libi186.a, bin/courier-call (-O2 -Wall -Wextra, no warnings)
    make fw         # decode SV25.XMD -> fw/SV25.flash.bin
    make run        # fake call with call.conf; writes out/ (below)
    make test       # unit tests + --help smoke run
    make clean      # removes build outputs (keeps fw/ and out/)

Only the C stdlib + libm are used. No Python, no extra packages.
`make run` works from a clean checkout of `c/` with only the config +
firmware paths it documents (the XMD default above).

### `make run` outputs (exactly one WAV)

    out/call_auto.wav     stereo, wav_rate (default 22050 Hz),
                          left = caller B, right = answerer A.
                          Cut at each modem's codec-rate changes and
                          resampled per constant-rate segment
                          (link.py write_wav semantics).
    out/call.log          events with times, setup replies, DTE text A
                          and B verbatim, DSP commands after 12 s.
    out/transferred.txt   all DTE text transferred both directions,
                          byte counts, whether any user payload was sent.
    stdout                run summary (mode, setup replies, events,
                          DTE text, DSP commands after 12 s, wall time).

The old three-WAV set from linkcall.py is NOT written.

## Configuration and override order

`call.conf` is plain `key = value` with `#` comments. Override order,
highest first:

1. **CLI** — `--mode`, `--duration`, `--out`, `--config`
2. **call.conf** keys
3. **environment variables** — only for keys absent from call.conf
   (the `machine.py` / `link.py` names: `NOISE`, `LINK_SLICE`,
   `LINE8K`, `DIAL_DWELL`, `RING_ON`, `RING_PERIOD`, `DELAY_SAMPLES`,
   `XINT_MODE`/`XM`, `CYC_MODEL`/`CM`, `LEGACY`, `TDM`, `AC01_MODEL`,
   `SEC_FRAME`, `HB_TIMER`, `DSP_CLK_FIXED`, `PORT_RB`, `INT23`,
   `AC01_FILT`, `AC01_LAT`, `CMD_OVR`, `AC01_CLAMP`, `P51DIV`,
   `CPU_SCALE`, `UD_TRAP`, `CPU_MODEL`, `DSP_ROM`, `CMPR`,
   `TINTSLOT`, `BANKWR`, `HWID`, `VDBTN`, `CPU_HZ`, `DSP_HZ`,
   `PROFILE`, `FLASH`)
4. **profile defaults** — `sv25` unless `profile` says otherwise.

Env vars are never required; the config file is the source of truth.
Profiles: `sv25` (default: cpu 25.8048 MHz, iface 25, sender_scan off,
`dsp_base_bytes` 55420, isr_presets, `nvram.bin`), `id20_403` and `sv20`
(supported when their flash is supplied later — point `flash`/`nvram`
at the matching images).

Modes (as in `linkcall.py`): `auto` (plain), `v21` (adds `AT&N1`,
`ATB0` both sides), `v22` (`AT&N3`, `ATB0`), `echo` (hybrid leakage
0.1), `gate` (mute A→B between A cmd `0x21` and B cmd `0x20`).

## What was ported faithfully

- Shared absolute-clock link (`Link.run`, slice default 1000 cycles),
  per-sample `_sample`/`_service` event loop, timers/UART/EEPROM/PCB/ICU.
- DSP mailbox/overlay/AC01 model (`SEC_FRAME`, `AC01_FILT` `_Lp6`
  Chebyshev filter, `AC01_LAT`, `CMD_OVR`, `P51DIV`, `PORT_RB`,
  `INT23`, `HB_TIMER`, `DSP_CLK_FIXED`), double precision, same
  formulas and evaluation order in `_Lp6` and the sinc resampler.
- Noise LCG (seed 12345, 1103515245/12345), DTE 8N1 line,
  dial-tone/DTMF/ring/answer/connected state machine, rate changes +
  `rate_idx`, WAV export with per-segment resampling.
- Floor division `SAMPLE_CYC = CPU_HZ // 7200` and
  `DSP_CPS = DSP_HZ // 7200`, as in the ZIP snapshot.
- `machine.py` `_boot_crc` (the SDL-written CRC word patched into
  flash `0x77FFE` only when the image carries `0xFFFF` there).

## Deliberate deviations and caps

- **Unbounded Python lists are capped.** `log`, `pcblog`, `dsp_log`
  and `rx_log` stop growing at 2^20 entries; `flag_log` keeps the
  Python 400-entry cap. `tx_all`, `cmd_log16`, `msg_log`, `cmd_log`,
  `rate_idx` and the audio path stay exact (uncapped, grown as
  needed). A 70 s call stays far below the caps.
- **`hostbytes` is omitted.** It is initialised in `machine.py` and
  never read or written anywhere else.
- **Core headers vs glue.** `src/cpu/i186.h` and `src/dsp/c5x_core.h`
  are the real core headers (they superseded the provisional ones
  during this port; the cores build against them as-is). They cannot
  both be included in one translation unit — each defines plain
  `io_rd_fn`/`io_wr_fn` with different signatures — so `machine.h`
  forward-declares the core ABIs it uses (opaque handles, prefixed
  callback typedefs, register ids/status codes copied verbatim from
  those headers and the Python wrappers). The prototypes were checked
  against the headers; the cores themselves compile against their own
  headers unchanged.
- **`_Lp6` state is never reset on redesign**, matching `design()`
  (state is created only when its length differs, i.e. on the first
  design).
- **Iteration-order effects checked.** `cmd_log` order is insertion
  order (array, preserved). `sec_abs` is a set in Python; membership
  and discard are the only operations used, so a hash set preserves
  the semantics exactly (no iteration over it anywhere). `port_store`
  is a dict keyed by port; reads default to 0, preserved with a
  zeroed array. `wr_pcs`/`rd_pcs`/`port5_pcs` are `Counter`s used only
  for diagnostics; counts are preserved in hash counters. `dsp_bursts`
  / `_burst` order is insertion order (array, preserved). No other
  dict/set iteration affects output.
- **`dsp_base.bin` on disk is informational.** `start_dsp` builds the
  resident DSP image from the supervisor's captured download bursts,
  exactly as `machine.py` does; it does not read `dsp_base.bin`.
  The ov6/7/8 images are likewise present for reference; overlays are
  loaded by the supervisor through the mailbox, as in Python.
- **`RX_TRACE`** is still honoured via the environment (exact sample
  delivered to DRR per codec tick), as in `machine.py`; it is not a
  config key.

## Emscripten

The cores and glue use only the C stdlib + libm and make no OS calls;
all file I/O, argument parsing and directory creation are isolated in
`main.c`, `config.c` and `wav.c`. That is the intended seam for a
future WASM build (one module, both modems + virtual link); WASM was
not built here.

## Regression gate (from modem/HANDOVER.md)

`make run` (auto, 70 s) is the C equivalent of
`python3 linkcall.py auto 65`. Compare `out/call.log` events and the
DSP command lists with the baseline in `modem/STATUS.md`. Any shift in
digit/connected times or in the `21 0100` / `20 0100` times means the
change altered behaviour.
