# BinModem bridge

Puts BinModem (a Rust softmodem, `~/Programming/BinModem`) in place of the answerer (A), or with
`BM_ROLE=caller` in place of the caller (B), in a `courier-call` run, to test the emulated modem against an independent V.34 implementation.

```
tools/binmodem-bridge/build.sh                  # prints the bridge binary path
BINMODEM=<that path> bin/courier-call --config call.conf --duration 40 --out /tmp/o
```

- Emulated B still dials, rings and gets the call answered as usual. From `connected`, B's audio
  goes to BinModem and BinModem's audio goes back to B; BinModem's DTE text shows as `A->HOST`.
- The hook is in `src/glue/link.c` (`bm_*`), active only when `BINMODEM` is set.
  `BINMODEM_AT` (default `AT+MS=V34`) is sent to BinModem at start.
- Meeting ground: the line between the two cores is always **28800 Hz**. The emulator converts its
  codec rate to 28800 Hz and back with a windowed-sinc (Lanczos 12) filter (`rs_*` in link.c); the
  codec rate is not constant (7200, 8640/9600 in V.8 and phase 2, 10267 in phases 3 and 4), and the
  filters are rebuilt when it changes. The bridge runs BinModem at 9600 Hz, an exact 3:1 from the line.
- Wire format over the child's stdin/stdout, little endian: `u32 n, u32 d, u32 line_rate, n x f32
  line samples, d DTE bytes`, answered by `u32 n, u32 d, n x f32, d bytes`.
- Levels: input is DRR units / 16384 per modem full scale; the output scale is `BM_OUTSCALE` (default
  5000). The emulated receiver's behaviour depends strongly on it and the useful value differs by role and
  phase: `BM_ROLE=caller BM_OUTSCALE=300` gives a full connect with data both ways; see
  docs/handshake-script-stall.md. Use `AICDBG=1` to see the level the emulated DSP actually gets.
- Tracing: `PHASE2_TRACE=1` (INFO sequences heard), `PHASE4_TRACE=1` (phase 3/4 stages, failures, J
  and MP events; added by `trace.patch`, applied to the scratch copy only) and `MODEM_TRACE=1` (why a
  call ended).
- The bridge logs BinModem's phase and line notes to stderr with timestamps (`[binmodem ...]`).
- The recording (`wav` in call.conf, `out/call_auto.wav`) has B on the left and BinModem on the right.
