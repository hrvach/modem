# OPS: build, test, run, measure

Everything here is run from the repo root (`~/Programming/courier`) unless stated.

## Build

| Command | What it does |
|---|---|
| `make` | builds `lib/libc5x.a`, `lib/libi186.a` and `bin/courier-call` |
| `make clean && make` | **required after any change to a `.h` file** (the Makefile has no header dependencies; a stale `.o` silently keeps the old struct layout) |
| `make fw` | decodes `SV25.XMD` to `fw/SV25.flash.bin` (only needed if the flash image is missing) |
| `make test` | `test_resamp`, `test_config`, `test_line`, `dsp_core_smoke`; expect four `PASS` lines |
| `make test-dsp-wat` | WAT vs C DSP differential test; needs `WASM_AS=~/emsdk/upstream/bin/wasm-as` |

Check that the binary really was relinked before trusting a run:

```
ls -la --time-style=+%H:%M:%S bin/courier-call
```

`make bin/courier-call | head` can stop the build early (SIGPIPE) and leave the binary stale. Don't pipe make into `head`.

## Run a call

```
bin/courier-call --config call.conf --out <dir>
```

Outputs go to `<dir>/`:
- `log.txt`: DSP and 80186 trace, host and DTE lines, `wall time`, `d2h overwrites`, and any `dm`/`hits` lines
- `call.log`: event summary and both DTE transcripts
- `transferred.txt`: bytes delivered each way, and whether the user payload was sent
- `call_auto.wav` (under `out/`, per `wav` in `call.conf`)

Useful config overrides go in a temporary file, not in `call.conf`. Keep it outside the repo or delete it after the run; stray `.call-*.tmp.conf` files in the repo root have been left behind before.

```
cp call.conf /tmp/t.conf
sed -i 's|^setup_b = .*|setup_b = AT\r|ATQ0V1\r|' /tmp/t.conf   # no X3, as in the browser
bin/courier-call --config /tmp/t.conf --duration 60 --out /tmp/out1
```

Keys used in this work:

| Key | Meaning |
|---|---|
| `duration_seconds` / `--duration` | simulated seconds to run |
| `setup_a`, `setup_b` | AT strings sent before the call |
| `send_text`, `send_text_a` | payloads sent after CONNECT; **the run stops as soon as both have been seen**, so set them empty for long runs |
| `send_file` | a file sent by the caller (B) after CONNECT; use for throughput |
| `inject_cmd`, `inject_arg`, `inject_at` | test hook: post a host-to-DSP command to both modems at `inject_at` seconds (hex accepted, e.g. `0x21`) |

**Stop-on-delivery trap:** if `send_text` or `send_text_a` is empty, `memmem` matches the empty string and the run stops early. A run that looks stalled after ~20 s is usually this, not the link. Set both payloads to non-empty text, or accept the early stop.

## Check the handshake

A connected call looks like this in `call.log` and `log.txt`:

- `CONNECT 33600/ARQ/V34/LAPM/V42BIS` on both sides (about 14 s simulated)
- both payloads in `transferred.txt`, both directions

The overlay loads show which overlays the DSP took:

```
grep -o "overlay load: [0-9]* bytes to DSP PM [0-9A-F]*" <dir>/log.txt | sort | uniq -c
```

A normal V.34 call here loads overlay 6 (`9D00`) and overlay 8 (`DC00`). Overlay 7 (`B000`) does not load in this call; see `docs/handshake-script-stall.md`.

Host commands and DSP messages are in the log:

```
grep "host->DSP cmd" <dir>/log.txt | head
grep "DSP->host msg" <dir>/log.txt | head
```

## Measure throughput

Throughput is always measured in **simulated** time, from the log timestamps, not wall clock. The wall time is printed for information only and varies a lot.

1. Make a payload, for example 32 kB of text lines:
   ```
   python3 -c "import random; random.seed(2); L=[]; n=0; i=1
   while n < 32000:
       l='%05d ' % i + ''.join(random.choice('abcdefghijklmnopqrstuvwxyz0123456789 ') for _ in range(70)); L.append(l); n += len(l)+2; i+=1
   open('/tmp/payload32k.txt','w',newline='').write('\r\n'.join(L)+'\r\n')"
   ```
2. Set `send_file = /tmp/payload32k.txt`, `send_text =`, `send_text_a =`, and `duration_seconds = 150`.
3. Run it, then take the time of the first and last payload line that A received:
   ```
   f=<dir>/log.txt
   first=$(grep -m1 'A->HOST  "00001 ' $f | awk '{print $1}')
   last=$(grep 'A->HOST  "00411 ' $f | awk '{print $1}')
   python3 -c "print(round(32058/($last-$first),1), 'B/s')"
   ```
4. Repeat the run to confirm. The runs are deterministic, so repeats should match exactly.

The file size must match the payload; check `wc -c` on the file used.

## Web build and browser test

```
web/modem/build-wasm.sh
```

It uses emsdk at `~/emsdk` (override with `EMSDK=`). It rebuilds `web/modem/web/modem.{js,wasm,data}` and `web/modem/build/modem.js`. The page files are plain source and need no build.

The page can't be opened as `file://` in a way that works reliably. Serve the folder over HTTP and reload with a hard refresh (Ctrl+Shift+R), because the browser caches the old `index.html` and `worker.js`:

```
cd web/modem/web && python3 -m http.server 8088
```

Test steps:
1. Power on. The modems run their AT setup.
2. Start call. B dials `ATDT5551234`.
3. A rings, and the page answers `ATA` automatically.
4. Check the speed row: sim time, speed, cpu, text-in rate.
5. Send 32 kB random (button). The text-in rate on A's row is the B-to-A rate.

Known browser issues are in the repo's commit history; the audio path is a relay through the page, so latency and click reports should be checked against the speed row first.

## Working-tree hygiene

- Temporary configs (`.call-*.tmp.conf`) and scratch output stay out of the repo.
- Don't commit build outputs (`bin/`, `lib/`, `*.o`, `*.d`, `web/modem/build/`, `web/modem/web/modem.*`). `web/modem/web/modem.*` and `web/modem/build/` are ignored; `bin/` and `lib/` are ignored too.
- Fonts `web/Glass_TTY_VT220.ttf`, `web/_decterm.ttf`, `web/vt100-regular.ttf`, `web/modem/web/Glass_TTY_VT220.ttf`, `web/modem/web/vt100-regular.ttf` and `web/modem/build-wasm.sh` are untracked. The page needs `vt100-regular.ttf` and the build needs `build-wasm.sh`, so commit them deliberately, not with `git add -A`.
- `docs/handshake-script-stall.md` is the open problem description for the stall.
