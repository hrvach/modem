# OPS notes

## DSP disassembly
Use c5xtools (https://github.com/wgrzegorz/c5xtools, MIT, C99, `make`); the user keeps a built copy at ~/Programming/c5xtools/tools/c5xdis/c5xdis. The base DSP image is program words 0x8000..0xEC3D
(overlays load later at 0x9D00 / 0xDC00 on the C emulator).

    c5xdis image.bin --base 0x8000 --trace --entry 0x8000 -q -o out.asm

`--trace` separates code from data and labels call targets; `@UNRESOLVED` marks computed jumps (BACC dispatch via data[0x326]).

## Comparing the RTL DSP with the C core
Dump the DSP data memory from both at the same input sample (C: `RXINJ_DUMPS`/`RXINJ_DUMPDIR` in the instrumented machine.c,
RTL: `tb_fast2 +rxdumps=N,.. +rxdumpd=DIR`), diff the two, then find the code that writes the first diverging variable.
Restores must keep the DSP fetch held until reset settles and must re-deposit the codec registers (reset clears them).

## Bug log (what was broken, where)

- **MAC/MADS program operand ignored CNF/RAM mapping** — `rtl/dsp/c5x_mem.sv`, r2 read port (`pmem2_rdata_q`). With CNFP the program range
  0xFE00..0xFFFF is B0 (data 0x100..0x2FF), with RAM 0x2000..0x23FF is SARAM (data 0x800..0xBFF); the r2 port read only the PMEM copy and
  returned 0. The firmware's ANSam/CM demodulator (code 0xABF9..0xAC08, `MAC 0xFE34,*-` -> data 0x300) therefore produced 0 and the modem never
  sent V.8 CM. Fix: `shadow_b0` / `shadow_sa` arrays written alongside DMEM, selected by `r2_sel_q`. Found by diffing C vs RTL DSP data memory
  at the same input sample (first divergence 0x300, `P=0` in the MAC loop). The 669 vectors did not cover it.
- **Interrupt entry inside a repeat** — `rtl/dsp/c5x_ctrl.sv` `int_held_w`: hold at `rpt_rewind_w` and at retire of RPT/RPTK/RPT#lk/RPTZ (C gates on rptc<=0).
- **evt bit 0 W1C race** — `rtl/dsp_glue.sv`: ignore W1C of event bit 0 while `h2d_pending==0` (DTMF dial fix).
- **Simulator artefacts (not RTL bugs)** — `tb/tb_fast2.sv` restore: deposits were wiped by the DSP reset (hold fetch, deposit after reset settles),
  and `aic_q` registers were reset to 0 so the line input was muted (gain_in=0); they are re-deposited now. RTL `aic_q` resets to 0 while the C
  model resets reg4 to 5; the DSP programs it at start, so only restores are affected.
- **DSP->host message burst lost the 2nd..7th word** — `rtl/dsp_glue.sv`. The 186's INT0 ISR reads event port 0x1C, reads port 0x58 (frees the DSP's mailbox:
  `d2h_valid` clear), reads the data words, then W1C-clears event bit 1. The DSP wrote the next message of a burst (V.8 JM detect sends 7 words:
  00C1 0145 0211 0310 042A 050D 0600) into the same registers in between, so the ISR read the wrong message and its W1C wiped the event of the pending one;
  the rest never got read and the handshake stalled (then the DSP ran into unloaded overlay code). C delivers messages atomically. Fix: snapshot the
  mailbox at the 0x58 read (`d2h_snap_q`/`snap_vld_q`, data reads return the snapshot), and a W1C of bit 1 while `d2h_valid` is set again keeps the event
  and raises INT0 again. Reproduced in `tb_fast2` from a C snapshot at 17.3 s with a recording of D-Modem's answer + JM (`+rxfile`).
- **Shadow arrays built from flip-flops (+14k ALMs, router congestion)** — `rtl/dsp/c5x_mem.sv`. First version of the MAC fix read both shadow arrays in one
  assignment under one enable; Quartus reported "uninferred due to asynchronous read logic" and made 24.6k registers (ALMs 48% -> 72%, fitter congestion
  failure). Fix: one write port and one enabled synchronous read per array, select afterwards. Always grep the synth log for `uninferred` / `Inferred altsyncram`
  after touching a memory, and compare per-entity ALMs in `Modem.fit.rpt` ("Fitter Resource Utilization by Entity").
- **DSP clock (40.32 MHz) fails timing, results vary run to run on hardware** — worst path (build 112333, -3.119 ns): 25 logic levels, 27.1 ns vs 24.8 ns:
  `u_ctrl` adder -> e_wr_addr -> `c5x_mem` dm_internal_f / LessThan15 -> `rpt_rewind_w` (e_would_retire_w) -> r_hold / mem_r_addr -> ext_mmr_addr compare
  -> e_operand -> alu_b16_mux -> ALU shifter. Same bitstream gave a stuck 900 Hz CM once and a bad codec rate (10080 cps) another time; the simulator is fine.
  Report the paths with: `quartus_sta -t` script (create_timing_netlist; read_sdc; update_timing_netlist; report_timing -setup -npaths 12 -detail full_path).
  Worst-600 paths (seed 3, -2.707 ns) all end in the ALU operand muxes (`alu_b16_mux`, `Mux90..97`) and start in `c5x_addr:u_addr` (AR/ARAU) or `re_q.desc.valid`:
  one structural path (ARAU -> E write address -> mem replay compare / stall -> rpt_rewind_w -> R address -> ext MMR read -> E operand -> ALU), not many small ones.
  A fix needs a pipeline cut there (register the rewind/hold decision or the operand), then 669 vectors + C co-sim; seeds only move it ~0.4 ns.
- **Timing cut 1 (E operand vs shared MMR address mux)** — `c5x_core.sv`/`c5x_mem.sv`: `ext_mmr_rd()` function, two copies of the core-MMR read mux; the deferred E read
  (`mmr_e_rdata`) uses its own copy keyed by `i_e_rd_addr` (`o_ext_mmr_e_addr`), no longer by the shared `o_ext_mmr_addr` mux whose select depends on the E-write decode and
  the R address (rpt_rewind_w). The old path ended in the ALU through e_operand_w; it now ends at the R->E registers. 669 vectors pass. Build 120846 (before): -4.49 ns.
- **Timing cut 2 (ext-MMR write decode)** — core's TREG/IFR/AR... write decode now keyed by `o_ext_mmr_w_addr` (= `i_e_wr_addr`) instead of the shared `o_ext_mmr_addr` mux. Build 122655
  (cut 1 only): -0.914 ns, worst path ended in `u_addr|ifr_q` through that mux. Board with that build still crashed (BACC through data[0x326] -> 0x4B14).

## DSP instruction history in DDR (`rtl/dsp_trace_ddr.sv`, `hps/dsptrace.py`)
Every retired DSP instruction's PC (three per 64-bit word, with AR7 at the third) streams through a small clock-crossing FIFO into a 32 MB ring at physical 0x3B000000
(header: magic "MDMTRC01", words written, words dropped, frozen flag). It never stalls the DSP (full FIFO = dropped word, counted) and only uses DDR clocks the line interface
(`line_ddr`, priority) leaves free. It freezes at the first trap after a core reload (sticky: a DSP restart does not unfreeze). The ring holds about 12 M instructions (~1 s).
On the MiSTer: `python3 dsptrace.py status | dump OUT [N] | escape [LO HI] [LIST] | around PC [LIST]` (LIST = c5xdis-style "ADDR: instr" file, e.g. the scratchpad dsp_list.txt).
Testbench `tb/tb_dsp_trace_ddr.sv` (in-order words, drops counted, freeze flushes + final header). Traps that freeze the rings: zero-opcode walk, frame stall, bad codec rate,
a main-loop (pc 0x80C0..0x80FF) store to data 0x326, AR7 leaving 0xBD0..0xBDF after having been inside.

## DSP trace: 12 s ring, freeze on hangup (2026-11-22)
- Ring is 64 MB (RING_BITS 23, about 25 M instructions, 12 s at the usual ~2 M instr/s), base 0x3B000000 as before.
- Freeze sources: a crash condition only (zero-opcode walk, main-loop store to 0x326, AR7 leaving 0BD0..0BDF) or the HPS (`dsptrace.py freeze` = control word 9 bit 1, sticky until the core is reloaded). The rate / frame-stall traps no longer freeze the DDR ring (they fire on every hangup); they still freeze the small trap rings.
- `lined.py` runs `dsptrace.py freeze` when the SIP call closes after dialling / connecting. Workflow: load core, `dsptrace.py arm`, dial, ring freezes at the hangup, `ssh board 'nice python3 dsptrace.py grab -' > ring.bin`.
- dsptrace.py (RING_BITS 23) matches only builds from run-20261122-171628 on.
