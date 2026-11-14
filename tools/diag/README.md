# tools/diag — one-off diagnostic scripts from the investigation

Copied from the session scratchpad on 2026-11-14. They are throw-away probes, not a tested
suite: each builds a `Machine` or `Link` (two machines), runs it for a while and prints
something. Hard-coded `sys.path` entries point at `/home/hrvoje/Programming/USR/{sys,dsp}`;
output files go to the current directory. Run with `python3 -I`, from `tools/diag/`.
Heavy ones (anything running a full call, 20+ s of line time) belong on the builder.

| Script | Purpose |
|---|---|
| `portaudit.py` | Run a call for 20 s with IN/OUT logging on both 80186s; tally ports read/written (find ports never given meaningful values). Start here for hypothesis 3/1. |
| `portpoll.py` | Poll selected 80186 ports during a run. |
| `pcs.py` | Sample the 80186 program counter during a call (where do the supervisors sit?). |
| `bd7.py` | Watch `[0xBD7]` (go-online loop at B57C wants `&0x1C` nonzero 5 times). |
| `irqchk.py`, `timer.py` | Check interrupt delivery and timer behaviour on the DSP (vector/IFR/TIM). |
| `poke.py` | Poke host RAM (e.g. `[0xE88]`) after a command has settled to test the wait loop. Poking mid-flow is invalid. |
| `detprobe.py`, `pathcheck.py` | DSP energy detector (87B6/87CE) and DXR output-path checks; fs=7200 verification. |
| `energy.py`, `energy2.py`, `rxtest.py`, `linkrx.py` | Line energy / receive-side checks on the linked pair. |
| `linkdiag.py`, `linkmsgs.py`, `linkgain.py` | Link-level diagnostics: DSP messages seen, gain sweeps (`linkgain.py <gain> <dur>`). |
| `dsptrace.py`, `status5e.py`, `trap8.py`, `trap8b.py`, `trap21.py` | Trace DSP execution / status port 0x5E / trap at DSP addresses (8x, 21 command paths). |
| `ringparams.py`, `rates.py`, `profile.py` | Ring-message parameters, tick/heartbeat/sample rates (rates.py writes `ring.json`), instruction profile. |
| `auditcmp.py` | Behavioural regression for core changes: `auditcmp.py name xm cm tdm noise` — run a call and compare timeline. (`linkcall.py auto 65` is the standard gate.) |
| `opsweep.py` | Sweep every C5x opcode pattern against the manual: decode, length, cycles (176/176 pass). |
| `util.py` | Helper: runs a call and prints per-machine DSP utilisation. |
| `cs.py` | Environment shim for building on a machine without `distutils`. |
