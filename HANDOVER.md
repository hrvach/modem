# Handover — getting two emulated Couriers to complete a handshake

Read `STATUS.md` first. This file is how to work in the repo.

## Layout
- `SV25.XMD` -> `sv25_decode.py` -> `SV25.flash.bin` (flash addr = file offset + 0x80).
- `sys/i186.c` + `i186.py` (`libi186.so`): 80186 core. `sys/machine.py`: whole modem
  (memory map, PCB at 0xFF00, INT0 DSP mailbox/heartbeat, INT2 DTE, INT3 tick, event ports
  0x1C/0x1E, DSP ports 0x58/0x5A/0x5E/0x5F, bank ports 0x18/0x1A, line codec).
- `dsp/c5x_core.c` (+`c5x.py`, `libc5x.so`): TMS320C5x core. `dsp/dsp_base.*`, `dsp_ov6/7/8.*`
  DSP images/disassembly. `dsp/HOST_PROTOCOL.md`: host<->DSP command protocol.
- `sys/link.py`, `line.py`, `linkcall.py`: two machines joined by an audio line.
  `python3 -I linkcall.py auto <seconds> <outdir>`; env `NOISE XM CM TDM LEGACY`.
- `doc/`: distilled TMS320C5x User's Guide (SPRU056D, 1998) with `doc/index.md`.
  `00-consolidated-report.md`: core audit (take with salt, see STATUS).
- Notes: `sys/FULL_SYSTEM.md` (long log), memory files in
  `~/.claude/projects/-home-hrvoje-Programming-USR/memory/`.

## Build
`cd dsp && gcc -O2 -fwrapv -shared -fPIC -o libc5x.so c5x_core.c` (same for i186.c).
No numpy locally; use pure Python and `python3 -I`.

## Regression gate (MANDATORY before keeping any core/machine change)
Run `linkcall.py auto 65` (takes minutes; on the builder). Compare the printed `events:` and
DSP command lists with the baseline in STATUS.md. Any shift in digit/connected times or in the
`21 0100` / `20 0100` times means the change altered behaviour; bisect with per-fix legacy bits.
Builder run: `scp dsp/c5x_core.c agent@79.137.67.20:~/sv25/dsp/`, rebuild there, run
`cd ~/sv25/sys && nohup python3 linkcall.py auto 65 ../bisN > ../bisN/x.out &`, poll with an
until-loop (never chained sleeps). Previous runs: `~/sv25/bis*/`.

## Rollback
Local git: `git log`, `git checkout <commit> -- dsp/c5x_core.c dsp/c5x.py sys/machine.py`,
rebuild. Pre-audit snapshot: `backup_pre_audit_20261114/RESTORE.sh`. First audit commit 8f2f5ee.

## Where to dig (suggested order)
1. Trace the writers of `[0xE88]` bit5 and the readers of messages 0x76/0x83: path is
   8F46:0134 (flash F594) -> `call [0x298]` handler -> 16088/16AEA. Find what real event
   is supposed to produce 0x76 (likely a DSP-side detection/"tone present" report or an
   80186 timer), then see why the DSP never posts it (DSP message ring at data 0x0BD0,
   post routine 83C8, send 83D6; detector 87B6/87CE; receive task D8C1, D94A posts 7).
2. Why caller `[0x134]` freezes at 4: find the decrementer (INT3 tick path) and what gates it.
3. Event port bit2 / hook `[0x2D3]`, ports 0x18/0x1A/0x14: log all IN/OUT on the 80186
   during the stall and look for ports read but never given meaningful values
   (`tools/diag/portaudit.py`; scripts in `tools/diag/`, see its README).
4. Overlay load (banks 0x40-0x5E, status 0x18/0x1A, `[0xE3C]`): decide whether handshake
   code lives in ov6/7/8 and why the host never loads them.
5. Only then revisit clocks (DSP_CPS, DSP_RATIO) and the unapplied audit items.

## Pitfalls learned
- Stride-2 DFTs mirror frequencies; scan at full rate.
- Do not trust audit claims blindly; check the manual in `doc/` and the regression gate.
- Pokes made mid-flow are invalid (E88 gets re-set instantly); poke after commands settle.
- Don't upload anything; don't copy audio or original firmware to the builder.
