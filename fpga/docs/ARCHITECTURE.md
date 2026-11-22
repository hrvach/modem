# Modem core (USRobotics Courier V.Everything, SV25) for the MiSTer — architecture and status

## Layout
- `Modem.sv` MiSTer `emu` top: hps_io (OSD file loads), PLL 120.96 MHz, SDRAM pad, audio, UART pins, video (`NO_VIDEO` = blank).
- `rtl/modem_core.sv` everything else (testable without the framework): clocks and enables, both CPUs, memories, glue.
- `rtl/i186/` 80C186EB core + system (ports, ICU, timers, UART0, EEPROM) + top; `rtl/dsp/` TMS320C5x core. Both from the zip port, now clock-enabled
  (`ce_i` wraps every `always_ff` body).
- `rtl/dsp_glue.sv` mailbox / flags / events / overlay + firmware loader / DSP I/O ports (machine.c semantics).
- `rtl/aic.sv` AC01 codec model + frame scheduler (parks the DSP with `step_i` at sample boundaries).
- `rtl/ram/` `sdram.sv` (sdram16 from ../unixpc, CAS and refresh parameterised, idle refresh fixed), `sdram_arb.sv`, `mem186.sv`, `c5x_xmem.sv` (DSP cache).
- `rtl/loader.sv` OSD loads: index 0 flash image, 1 NVRAM, 2 DSP ROM; `rtl/dte_uart.sv` 115200 8N1.
- `tests/Makefile` (`make test`: 16 tests, `make system` full-firmware run, `make t_smoke`), `tb/`, `tb/smoke/make_smoke.py`.
- `tools/qbuild.sh` Quartus build on agent@builder.hrvoje.org (`STAGE=map` for synthesis only, `NO_VIDEO=1` default).

## Clocking
One clock, 120.96 MHz = 3 x 40.32 MHz. `ce_dsp` = every 3rd clock when `c5x_xmem` is ready (a cache miss stalls the DSP, not its model time).
`ce_186` = every 4th clock (30.24 MHz) when the 186's SDRAM access is done. 186 timers: `tick_en` = 64/75 DDA on `ce_186` edges (25.8048 MHz).
SDRAM controller at 120.96 MHz, CAS 3, refresh every 900 clocks (7.44 us).

## Memory (SDRAM word addresses)
0x000000..0x07FFFF 186 physical 1 MB (flash image at 0x040000 = physical 0x80000); 0x0C0000.. DSP 64K-word program/unified space.
DSP data RAM (B0/B1/B2/SARAM, 4K words) in M10K inside `c5x_mem`. DSP cache: 512 lines x 8 words direct mapped, write-through, 1-entry write buffer.

## Firmware
Never in the bitstream or on the build host (../courier README: local files only). SD card: `sdcard/` (local staging, see `sdcard/README.txt`).

## Verified
Every module has a self-checking testbench; the end-to-end smoke (tiny 186 + DSP programs through loader, SDRAM model, both cores, glue) passes.
The full SV25 firmware has NOT been run end to end: the C flow boots for 900M CPU cycles, far beyond what Verilator can simulate here; first run on hardware.

## Known differences / open items (KNOWN-DIFF)
- Overlay bytes are written to DSP memory as they arrive, not at the 0x1E write of 4 (see dsp_glue.sv header).
- 186 performance: every access goes through SDRAM (about 10 clocks) with no 186 cache yet; the 186 may run below real time. A 186 cache (like c5x_xmem) is the next step if
  the modem lags the codec.
- Line input is silence + the C model's noise floor; no second modem, no audio in. Audio out is the DAC held at the codec rate.
- Terminal video (`rtl/video/term.sv`, keyboard to DTE) not written yet; `NO_VIDEO` and the default build are both blank.
- Core audit KNOWN-DIFFs of the zip port are unchanged (see GOAL.md / cosim.md).
- TREG1/TREG2 direct-write gap and the TAIL write-port hazard of the DSP core (GOAL.md).
