# Co-simulation harness (C reference model vs RTL)

Top level `rtl/c5x_core.sv` + harness `sim/cosim.cpp` + `sim/Makefile`.
Reference model (the spec): the C core,
`research_notes/courier-firmware/c-port/c/src/dsp/c5x_core.c`
(+ `c5x_core.h`, `c5x_cyctab.h`). The RTL must match the C model
instruction by instruction; the TI-manual audit fix list is NOT
applied (see KNOWN-DIFF in `rtl/c5x_ctl_pkg.sv` and in the top
level header).

## How to run

From `sim/` (all commands assume the goal directory
`~/workspace/goals/tms320c5x-dsp-core-on-fpga/`):

| target | command | what it does |
| --- | --- | --- |
| `lint` | `make lint` | `verilator --lint-only -Wall` on the top level (all real modules). Must be clean. |
| `sim-unit` | `make sim-unit` | Module testbenches in `tb/` (alu, addr, mem, decode). The ctrl FSM has no module testbench; the SV25 co-sim below is its proof. |
| `smoke` | `make smoke` | Harness on the hand-written 4-instruction program (`sim/smoke.hex`): LDP #0, LACK #0x34, SACL 0x60, LACK #0. |
| `cosim` | `make cosim` (or `STEPS=n make cosim`) | Firmware co-sim: SV25 base image, per-instruction compare (default 1000 instructions, `--verbose`). First mismatch stops with both states printed. |
| `dsp-smoke` | `make dsp-smoke` | DSP smoke gate (see below). Run before the full firmware co-sim. |
| `selftest` | `make selftest` | C-model-only determinism check (run twice, compare). |
| `reset-check` | `make reset-check` | Compare post-reset state C vs RTL, then exit. |
| `synth-cyclonev` | `make synth-cyclonev` | Yosys `synth_intel_alm -top c5x_core -family cyclonev` area check. `synth` is an alias; generic `synth` is NOT used. |

Direct harness use: \`./cosim --firmware [N] [--verbose]
[--tolerate-cycles]`,&#32;`./cosim --smoke [N]\`,
`./cosim --dsp-smoke`, `./cosim --selftest [N]`,
`./cosim --reset-check`, `./cosim --image PATH`,
`./cosim --vector PATH`, `./cosim --max-clocks N`.
Exit 0 = all compared instructions/checkpoints matched;
1 = mismatch / error / watchdog.

## What the harness checks

Per instruction (firmware / smoke modes), after each C step
(`c5x_run(c,1)`) and the matching RTL instruction (clocked until
`instr_done`):

- Full directly-observable architectural state: PC, opcode, ACC,
  ACCB, PREG, TREG0-2, AR[ARP] + ARP, ST0, ST1, PMST, RPTC, BRCR,
  SP + stack top, IFR, IMR, BMAR, DBMR, INDX, ARCR, PASR, PAER,
  cycle count, idle flag. First mismatch stops with both states
  printed and the count of instructions matched before it.
- DMEM/PMEM: the C arrays are memcmp'd against the harness's RTL
  shadow, which starts from the loaded image and is updated from
  the RTL's `mem_wr_*` write-event outputs (no clocks spent
  reading RTL memory back).
- IO events: the (pc, port, wr, val) sequence. IO cycle stamps are
  NOT compared (the C iolog stamps the access after the base-cycle
  charge, the RTL stamps it at the handshake). The host IO array
  is shared: the C core's `iomem[]` and the RTL host model are the
  same 64K array, kept in sync from the C iolog and the RTL
  handshake.
- SPC is compared as the composed MMR-read value (`spc_rd`), not
  the raw stored field, because the RTL's `spc_o` is the composed
  read.

### Real-control-FSM protocol (step\_i park, added 2026-11-19)

The control FSM parks in DONE while `step_i` is low (wired in
the top from the top-level input); tied high, DONE goes straight
to FETCH\_ADDR and the path is cycle-identical. The harness still
ties `step_i` high and clocks the RTL one cycle at a time and reads
the state the moment `instr_done` is visible, then clocks exactly
one more cycle before the next step: `instr_done` is
combinational on the DONE state, and the timer's last tick for the
instruction lands on the DONE clock (the control FSM drains its
cycle count one tick per clock in TICK, and the top-level burst
counter applies the final tick on the DONE clock). After that one
extra clock the architectural state is the completed
instruction's state and the timer is exact; the next instruction
is still in FETCH, so nothing has moved.

No debug reads are done while the core runs: a debug read clocks
the DUT and the free-running control FSM would execute ahead. The
mem-owned registers (TIM/PRD/DXR/DRR/GREG/SPC/TCR/PDWSR/IOWSR/
CWSR) are therefore NOT compared per instruction yet. The
observation outputs exist now (`c5x_mem` `o_obs_*`, wired to
`obs_*_o` at the top, 2026-11-19); the harness still reads them
only via the debug port, which is safe only when the core is
halted (BADOP) or before reset release. The timer is validated
instead through `timer_expiries` (`timer_exp_cnt_o`) in the DSP
smoke gate. Comparing the `obs_*_o` outputs per instruction is
a harness update, still pending.

For an idle step (the C core is idle, no instruction executes),
the harness clocks the RTL until `cycles_o` advances by the C
cycle delta, with no `instr_done` wait.

`--tolerate-cycles` is a diagnostic: cycle-count mismatches are
logged but do not stop the run, so the first STATE divergence
past a known cycle-count bug can be found. It does not change the
strict default.

### Partial observation

- AR file / stack: FIXED 2026-11-19. `c5x_addr` now exposes the
  full file and stack (`o_ar_all` / `o_stack_all`, wired to
  `ar_all_o` / `stack_all_o` at the top). The harness still
  compares only AR[ARP] and stack[sp]; using the full vectors
  is a harness update, still pending.
- The ctrl's indexed AR read (`ar_rd_i`, used by SAR): FIXED
  2026-11-19. The indexed read (`i_ar_rd_sel` / `o_ar_rd`) is
  wired at the top, so SAR reads the selected register. The
  external-MMR read of AR0-7 (0x10-0x17) is a separate path
  and is not changed by this fix.
- The ALU exposes its combinational micro-op result
  (`acc_next`), wired to the ctrl's `alu_y` input at the top
  (2026-11-19). The ALU is the register file; it commits its
  internal next values on `i_ld_*`.

## DSP smoke gate (`--dsp-smoke`)

Standalone gate, no 186 and no glue. Run it before the full SV25
firmware co-sim.

- Vector:
  `research_notes/courier-firmware/c-port/c/tests/vectors/dsp_smoke_base.txt`
  (sha256 of the file itself
  `9e358f6fd99018d07f9e7db1cd5b160ab9246808e387d29f3cb43650e2d689be`).
- Binary:
  `research_notes/courier-firmware/c-port/modem/dsp/dsp_base.bin`
  (55,420 bytes).
- Test: load `dsp_base.bin` into PMEM only (no overlays, no IO
  hooks, no serial ticks, no DMEM presets, no `ivec_ind`), reset
  at 0x8000, run 8 x 1,000,000 cycles. At each 1M-cycle checkpoint
  the vector gives the expected full state: PC, ACC, T0, ST0,
  ST1, IFR, IMR, AR0-AR7, plus `dxr_head`, `idle_cycles`,
  `total_cycles`, `timer_expiries`. At the end it gives
  `pm_checksum` (sum `pm[0x8000:0x8000+27710]` = 952823955),
  `dm_checksum` (491427), `dxr_ring_first16`, `recent_pcs`, and
  13 IO events (cycle, pc, R/W, port, value).

Pass criteria: every checkpoint field matches, both checksums
match, the DXR ring first 16 match, the recent-16-PCs match, and
the 13 IO events match as a (pc, port, wr, val) sequence.
First mismatch stops with both states printed.

Notes:

- The vector was generated from the Python DSP, not the C core.
  A checkpoint is first checked against the C core (the
  reference) before the RTL is blamed; a vector/C disagreement
  is printed but does not fail the gate. Known vector/C
  differences: the C core overshoots a 1M-cycle budget when the
  boundary falls inside a multi-cycle instruction (`c5x_run`
  executes whole instructions; the first segment lands at
  1000003, not 1000000), so the RTL is clocked to the C core's
  ACTUAL cycle count after each segment, not to the vector's
  nominal 1M boundary; the PC phase in the idle loop then
  differs by one instruction (C 0x8097 vs vector 0x8098 at
  checkpoint 1). The register fields in the vector are hex; the
  counter fields (`dxr_head`, `idle_cycles`, `total_cycles`,
  `timer_expiries`) are decimal.
- AR0-AR7: the full file is observable now (`ar_all_o`, wired
  2026-11-19); the harness still compares only AR[ARP]. At the
  checkpoints ARP=1, so AR1 is compared and the rest are
  reported as unobservable until the harness uses the full
  vector.
- The DSP parks in a 0x8097/0x8098 software loop (not the IDLE
  instruction), so `idle_cycles` is 0.
- A 1M-cycle segment is \~6M RTL clocks (the control FSM takes
  \~6 clocks per 1-cycle instruction); the per-segment watchdog
  is 20M clocks.

## Current status (2026-11-19)

- `make lint`: **clean** (`verilator --lint-only -Wall`, top level
- all real modules). All of agent 3's OPEN-1..OPEN-10 deltas
  are adapted in `rtl/c5x_core.sv` (see its header).
- `make reset-check`: **passes** (post-reset state matches:
  pc=0x8000 st0=0x0600 st1=0x07FC tim=0xFFFF).
- `make selftest 1000`: **passes** (C deterministic).
- `make smoke` (4 instructions): **passes** (MATCHED 4:
  LDP #0, LACK #0x34, SACL 0x60, LACK #0; final pc=0x8004
  cycles=5 io\_events=0).
- Firmware co-sim: **10000 instructions matched**
  (`./cosim --firmware 10000 --verbose`, run 2026-11-19 after the
  CTRL-LOOP and CTRL-BCND ctrl fixes; final pc=0x8098 cycles=22799
  io\_events=9). The run previously stopped at instruction 1535
  (tim C=0x4136 RTL=0x4138, cycles C=1638 RTL=1636 -- the 2-cycle
  BCND gap); it now passes 10000. Full AR file / stack and
  mem-owned registers compared per instruction.
- DSP smoke gate: **all 8 checkpoints pass** (\`./cosim
  --dsp-smoke\`, run 2026-11-19 after the CTRL-BCND fix:
  checkpoint 8/8 OK, pc=0x8097 acc=0x00000001 timer\_expiries=476
  rtl\_instr=3200881). Checkpoint 2 was failing on pc only
  (C=0x8097 RTL=0x8098) before the BCND fix; it now passes.
  Known VECTOR/C disagreements at every checkpoint (not
  failures): pc C=0x8097 vector=0x8098; total\_cycles C=8000003
  vector=8000000 at checkpoint 8. \*\*End-of-run recent\_pcs ring
  still fails (16 fields)\*\* -- but the RTL matches the C model
  at every index; the Python vector's ring is shifted by one
  entry (it reads 0x8098 where C and RTL read 0x8097, and vice
  versa, at all 16 indices). This is a vector-vs-C disagreement
  (the harness labels it `VECTOR/C disagreement`), not an RTL
  defect: the RTL is faithful to the C model, which is the spec.
  For the harness/vector owner, not the ctrl. See open issue 9.
- Harness updates (2026-11-19, sim only, no RTL touched):
  full AR file / stack compared per instruction (`ar_all_o` /
  `stack_all_o`) and mem-owned registers from `obs_*_o`;
  DXR writes logged as pseudo-port IO events (port 0x8021)
  from the pre-edge `dxr_wr` sample -- the old post-edge
  sample missed the 1-cycle pulse entirely, so the DXR ring
  never saw a write; C pseudo-port MMR-write events other
  than DXR (SPC 0x8022, unknown MMRs) excluded from the
  IO-event comparison (no RTL event exists for them; their
  effects are covered by the per-instruction state
  comparison -- SPC via `obs_spc_o`, unknown MMRs via a later
  readback); `run_to_cycles` now stops at the next
  `instr_done` after the target (instruction boundary), not
  at the end of TICK -- TICK advances the cycle counter but
  the instruction retires only in TAIL/DONE, and stopping at
  the end of TICK read pre-retirement state (that was the
  checkpoint-1 TIM mismatch). The smoke gate's end-of-run IO
  comparison now compares the observable subset only (real
  IO + DXR): the vector (Python DSP) also logs five DMEM
  writes to 0x68-0x6C as "IO" events, which neither the C
  core nor the RTL logs as IO (covered by `dm_checksum`).
- Targeted tests (scratch images in /tmp, sim only): RPT works --
  RPT #2 + SACL: MATCHED 5, cycles=7. LDP #7 + LACK #0x34 now
  MATCHES (st0 0x0607 both sides) after the TOP-STATDP fix (open
  issue 5, FIXED). SPLK #0x1234,0x60; IN 0x60,0xFF50 now MATCHES
  (DMEM 0x0060 0x0000 both sides, cycles=11) after the TOP-IN fix
  (open issue 7, FIXED). Loop ops (open issue 6, FIXED 2026-11-19,
  see below): BLDD #lk MATCHED 6 (cycles=13); BLDD bmar MATCHED 5;
  BLPD bmar MATCHED 5; TBLR MATCHED 6; MADD MATCHED 6 (cycles=9);
  MACD MATCHED 6; MAC with RPT #1 MATCHED 7; SMMR MATCHED 4;
  LMMR MATCHED 5; bare BLDD (rptc=-1, zero iterations) MATCHED 6;
  bare MAC (do-while, one iteration) MATCHED 6; indirect BLDD
  MATCHED 6. The BCND idle-loop test (BIT 4,0x80; BCND 0x8000)
  now MATCHES 10 instructions, cycles=25 (5 per iteration: BIT 1
- taken BCND 4) after the CTRL-BCND fix (open issue 8, FIXED).
- `make sim-unit`: **passes**. alu 1037 passed, 0 failed; addr
  313 checks ALL PASS; mem 168 passed, 0 failed; decode 66,726
  checks passed, 0 failed (plus a 1190-check random section).
  The decode testbench proves decode + cycle counts only; the
  ctrl FSM has no module testbench (the SV25 co-sim is its
  proof). Note: Verilator needs the package file listed BEFORE
  the files that import it (`c5x_ctl_pkg.sv` first), or the
  decode build fails with `%Error-PKGNODECL`.
- `make synth-cyclonev`: **BLOCKED** -- Yosys 0.33 cannot parse
  `import c5x_ctl_pkg::*;` (\`c5x\_decode.sv:90: ERROR: syntax
  error, unexpected TOK\_PACKAGESEP, expecting '(' or '['\`).
  The M10K/synth check cannot run on the real modules as written.
  Either agent 3 removes the package dependency (inline the
  types/localparams), or the synth check is deferred to Quartus
  (which supports packages). The 256 M10K / 0 `$mem_v2` numbers
  from the placeholder era are NOT claimed for the real modules.
  Deferred 2026-11-19 per the user's RAM decision; the
  top-level synth/M10K verification is parked, not dropped.

## Open issues (ctrl bugs found by the co-sim; suspect in ctrl first)

The co-sim is the proof for the ctrl FSM (it has no module
testbench). Both mismatches below were confirmed against the C
core source before being attributed to the ctrl.

1. **CTRL-IOWS -- dm IO wait states missing. FIXED 2026-11-19.**
   Firmware instruction 2 (SPLK #0xFFFF, 0x57): C charges 8
   cycles (2 base + 6 IO wait states: `io_ws(0x57)=7`, a write
   adds `w-1=6`), the RTL charged 2. The ctrl added the `io_ws`
   charge only for IN/OUT (`FSM_IO_WAIT`) and for the
   host-window `ivec_ind` read; a data-memory read/write to an
   IO port (MMR 0x50-0x5F, host window 0xFF50-0xFF5F) got no
   charge, but the C model charges `io_ws` on an IO read and
   (`io_ws`-1) on an IO write when `io_ws > 1`
   (`c5x_core.c` `io_read`/`io_write`). `io_ws_i` is used in
   only 3 places in `c5x_ctrl.sv` (lines 3204, 3207, 3402).
   Fixed: `dm_rd_ws_q` latches a dm read's `io_ws` at
   presentation; `FSM_OP_DATA` adds full `io_ws` on reads,
   `io_ws`-1 on writes; `FSM_EXEC` adds `io_ws`-1 on the
   presented write (2+6=8); loop phases charge per iteration
   the same way. Blocked the firmware co-sim past instruction
   2; the re-run is pending.
2. \*\*CTRL-STBIT -- single-bit status ops hit the wrong flag.
   FIXED 2026-11-19.\*\* Firmware instruction 3 (DINT 0xBE41): C sets
   INTM=1, the RTL set OVM=1 (ST0 C=0x0600 RTL=0x0E00). The
   ctrl set `st_bit_sel = {1'b0, op_lo[3:0]}` for the 0xBE
   0x40-0x4F ops, using the opcode low nibble directly as the
   flag index. The C model maps the pair (`op_lo[3:1]`) to a
   flag and `op_lo[0]` to set/clear: 0x40/0x41 EINT/DINT ->
   INTM, 0x42/0x43 ROVM/SOVM -> OVM, 0x44/0x45 RCNF/SCNF ->
   CNF, 0x46/0x47 RSXM/SSXM -> SXM, 0x48/0x49 RHM/SHM -> HM,
   0x4A/0x4B RTC/STC -> TC, 0x4C/0x4D RXF/SXF -> XF, 0x4E/0x4F
   RCB/SCB -> C (`c5x_core.c`, 0xBE sub-decoder). The RTL's
   nibble mapping was correct only for RCNF (0x44 -> sel 4 =
   CNF) by coincidence; the other 15 ops set/clear the wrong
   flag. Also, `alu_flag_c_we` was asserted for
   `op_lo[3:0]` == 0xA/0xB (RTC/STC, which change TC) instead
   of 0xE/0xF (RCB/SCB, which change C), so the ALU's C copy
   was corrupted by RTC/STC and not synced by RCB/SCB. Fixed:
   case table on `op_lo[3:1]`, and `alu_flag_c_we` for
   RCB/SCB. Blocked the firmware co-sim past instruction 3 and
   the smoke gate past checkpoint 1 (checkpoint-1 ST0 C=0x2607
   RTL=0x2C00 was the cumulative effect over the init code);
   the re-run is pending.
3. \*\*KD-23 / OPEN-10 -- MADS/MADD TREG0 mirroring. FIXED
   2026-11-19.\*\* The C model writes TREG0 directly for
   MADS/MADD (no `set_t0`, so no TRM mirror), but the ctrl
   loaded TREG0 with ALU `OP_LT`, and `OP_LT` mirrors
   TREG1/TREG2 from the new TREG0 value when TRM=0
   (`c5x_alu.sv` OP\_LT case). Fixed: the ALU has `OP_LT_NM`
   (7'd64, `i_op` widened to 7 bits) and the ctrl issues it
   as a whole-body single issue in the WR phase, so TREG1/TREG2
   are untouched; the old loop phase 6 is deleted. (KD-24, the
   MADS/MADD loop-kind fix -- the old range test caught them as
   BLDD -- IS in the ctrl: `loop_kind_next` maps 0xAA/0xAB to
   kind 8; the co-sim will confirm it when a MADS/MADD
   executes.)
4. \*\*TOP-EXTMMR -- external-MMR writes dropped. FIXED
   2026-11-19 (top level only).\*\* Firmware instruction 14 (OPL
   #lk, 0x5D07, imm 0x00B0, to dm 0x0007 = PMST): pmst C=0x00B0
   (AVIS/OVLY/RAM set) RTL=0x0000. The mem routes PMST -- and
   IMR, IFR, RPTC, BRCR, PASR, PAER, TREG0-2, DBMR, AR0-7, INDX,
   ARCR, CBSR/CBER, BMAR -- to the external-MMR path
   (`mmr_is_ext_f`, `c5x_mem.sv`) and pulses `o_ext_mmr_wr`,
   but the top left `.o_ext_mmr_wr` / `.o_ext_mmr_wdata`
   unconnected (`c5x_core.sv`, u\_mem instance) and the
   addr-unit write-port mux (`wr_port_*`) was fed only by the
   ctrl's strobes, so a DMEM write to an external MMR never
   reached its owner. The read path worked. Fix (RTL, top
   level): `o_ext_mmr_wr` / `o_ext_mmr_addr` / `o_ext_mmr_wdata`
   are connected and fed into the `wr_port` mux at top priority
   with an address-to-`WR_*` case-table decode (PMST -> WR\_PMST,
   IMR -> WR\_IMR, ..., AR0-7 -> WR\_AR0+n); TREG0 is written
   through the ALU's treg load (one-cycle override: op OP\_LT,
   b16 the write data, treg load on, TRM forced so the mirror
   does not fire, exec on). TREG1/TREG2 direct DMEM writes are
   still dropped -- the ALU can change TREG1/TREG2 only through
   the TREG0-load mirror, which also writes TREG0, so there is
   no top-level-only way to write them alone; that needs an ALU
   interface change. The firmware co-sim now passes instruction
   14 and matches 1000 instructions; the first 1000 do not
   write TREG1/TREG2 through DMEM (their per-instruction
   compare would have caught it).
5. \*\*TOP-STATDP -- `stat_dp` wired to the wrong slice. FIXED
   2026-11-19 (top level, one line).\*\* `c5x_core.sv`:
   `.stat_dp (addr_dp[8:0])`. The addr unit's `o_dp` is the
   full pre-shifted `dp_q` ({page[8:0], 7'b0}); the page is
   bits [15:7], as `o_st0` uses (`dp_q[15:7]`). Taking [8:0]
   returns the wrong value (DP=7 -> `stat_dp`=384). Every ALU
   instruction's TAIL C/OV writeback (OPEN-9) then writes the
   corrupted DP back into the addr unit via WR\_ST0. Proven by
   a minimal test (LDP #7; LACK #0x34): st0 C=0x0607
   RTL=0x0780 (DP 7 vs 384). Blocked the DSP smoke gate at
   checkpoint 1 (st0 C=0x2607 RTL=0x2600; the smoke run's DP
   ends at 0 after a later LDP #0, but the corruption is the
   same mechanism). Fix: `.stat_dp (addr_dp[15:7])`. The
   smoke gate now passes checkpoint 1 and the minimal test
   matches (st0 0x0607 both sides).
6. \*\*CTRL-LOOP -- loop engine unreachable for loop ops.
   FIXED 2026-11-19 (RTL, ctrl).\*\* SETTLED (was open question a):
   the loop engine is actually dead, not just suspicious. FSM\_LOOP
   is implemented (EA/RD/WAIT/PM/WR/NEXT phases) but never
   entered for loop opcodes: `needs_op_addr` excludes 0x09,
   0x57, 0x89, 0xA2-0xAD, so a loop op routes FETCH2->EXEC
   (never OP\_DATA->LOOP), and FSM\_EXEC has no branch to
   FSM\_LOOP. Proven by a BLDD test (RPT #1; BLDD #0x70,0x60):
   first mismatch at the BLDD step -- pc C=0x8008
   RTL=0x8006 (PC rewound for the rpt repeat, not advanced
   past the 2-word instruction), cycles C=12 RTL=11, tim
   one behind. The RTL falls through to EXEC (base cycles
   only) and relies on the PC-rewind repeat, which splits
   the repeat across multiple `instr_done` pulses instead
   of the C model's single-step block operation. Plain RPT
   (0xBB) works (RPT #2 + SACL: MATCHED 5, cycles=7) --
   that is the rptc-counter mechanism, not the loop engine.
   RPTB / BLDD / MADD / MADS / SMMR / LMMR / BLDP / BLPD /
   TBLR / TBLW / MAC / MACD all need FSM\_LOOP. Blocks any
   firmware run that reaches a loop op.
   Fix (2026-11-19, `rtl/c5x_ctrl.sv` only): `needs_op_addr`
   now includes 0x09, 0x57, 0x89, 0xA2-0xAD; `ea_mask_p0`
   extended with 0x89; the OP\_ADDR ea\_en pulse is suppressed
   for loop ops except SMMR/LMMR; OP\_DATA latches the loop
   setup (`loop_a_q`, `alu_used_q` for MAC/MADS, the full
   16-bit rptc extra-cycle charge) and skips zero-iteration
   while-forms; the LOOP engine latches the per-iteration ea
   in phase EA. Two follow-on bugs found by the minimal tests
   and fixed in the same file: (a) the loop dm write was
   presented in the WR phase, but a pm\_d read in PM is
   accepted at the end of PM, so its ack pulse is high through
   WR and the memory's `dm_accept` (which needs `!dm_ack_q`)
   dropped the write -- the MACD/MADD DMOV (dm[0x61] C=0x0034,
   RTL shadow=0x81AE) and the BLPD-bmar / TBLR / BLDD-bmar
   writes were lost. The dm write (and its wait-state charge)
   moved to the NEXT phase, where the ack has cleared; the ALU
   issue and the pm writes (BLDP/TBLW, a separate channel)
   stay in WR. (b) On a repeat of SMMR/LMMR (which skip EA,
   so there is no gap cycle), the NEXT-phase write's ack is
   still high in the first RD cycle and the read was dropped,
   then the phase waited forever on an ack that never comes
   (watchdog). The RD phase now holds while `dm_ack` is high
   (stale ack) and only sets `dm_wait_q` once the read can be
   accepted; one raw clock, not a model cycle. All loop minimal
   tests now match (see Current status); the firmware co-sim
   passes 10000 instructions.
7. \*\*TOP-IN -- IN dm write suppressed. FIXED 2026-11-19
   (top level).\*\* IN (0xAF) from a host-window port: the IO
   read worked (the IO event compares, the value is read),
   but the dm write never landed. Proven by a minimal test
   (SPLK #0x1234,0x60; IN 0x60,0xFF50): DMEM differs at
   0x0060, C=0x0000 RTL-shadow=0x1234. The IN dm write is
   presented combinationally only in the ack cycle while the
   top mux selects the IO branch whenever `ctrl_io_req_c` is
   high. Fix: the top captures the IN write at the
   acknowledge edge (`in_wr_capture`: io\_req + io\_ack + read

+ dm\_req + dm\_wr) and presents it to the memory in the
   next cycle, when the data channel is free (FSM in TICK),
   holding it until the memory acknowledges it. The mux keeps
   the IO port address in the acknowledge cycle itself so
   `io_ws_i` stays the port's wait states for the cycle
   charge. The same acknowledge-cycle fix drives the FSM's
   `mmr_wr_hit` from the IN target address, so an IN to a
   peripheral MMR (0x20-0x4F) gets the mmr\_bus +1 cycle the C
   model charges (c5x\_core.c:812-816). The minimal test now
   matches (DMEM 0x0060 0x0000 both sides, cycles=11).

8. \*\*CTRL-BCND -- taken conditional branch undercharged by 2
   cycles. FIXED 2026-11-19 (RTL, ctrl; NOT a top-level bug.)\*\*
   Minimal test of the smoke-gate idle loop (BIT 4,0x80; BCND
   0x8000): first mismatch at instruction 2 (the BCND): cycles C=5
   RTL=3, tim C=0xFFFA RTL=0xFFFC. The C model charges 4 for
   a taken BCND (`c5x_cyctab.h`: BCND 0xE200 base 4; the
   ctrl's own header: class-1 taken 4 / not-taken 2); the RTL
   charged 2 -- the not-taken value -- for a taken branch.
   The charge path is the ctrl's class-1 adjustment
   (`base_cyc_q`, `seq_q` in `c5x_ctrl.sv`); the top level
   does not compute cycle counts and none of its changed
   signals feed the branch charge (no dm write, no IO, no
   ext-MMR write in a BCND cycle). Blocks the DSP smoke gate
   past checkpoint 2: the idle loop is BIT (1 cycle) + taken
   BCND, so the RTL runs 3 cycles per iteration against the
   C model's 5, and the PC phase drifts by one instruction at
   the segment boundary (checkpoint 2: pc C=0x8097
   RTL=0x8098, all other fields match).
   Root cause: `seq_q` (`pc_q == ppc_q + words_q`) is evaluated
   at the EXEC charge edge, when `pc_q` is still the fall-through
   pc -- the branch target is applied at that same edge, so a
   taken branch reads as sequential. The C model computes `seq`
   from the post-execution pc. Fix: a `br_taken_q` signal
   (class-1/2 opcode range AND `ex_ds_take`, the taken signal
   for exactly those opcodes) gates `seq_q` -- a class-1/2
   branch is sequential only when NOT taken. This also fixes
   taken RETC (whose `sp` test is always true pre-edge) and
   taken BANZ. Proof: the BCND test now matches 10 instructions,
   cycles=25 (5 per iteration); the decode testbench still passes
   66,726 checks, 0 failed; the DSP smoke gate passes all 8
   checkpoints; the firmware co-sim passes 10000 instructions.
9. \*\*DSP smoke end-of-run recent\_pcs ring: vector vs C
   disagreement, RTL matches C. (Vector / harness, NOT the ctrl.)\*\*
   After the CTRL-BCND fix the gate passes all 8 checkpoints, but
   the end-of-run `recent_pcs[16]` comparison fails on all 16
   fields: the RTL matches the C model at every index, while the
   Python vector's ring is shifted by one entry (it reads 0x8098
   where C and RTL read 0x8097, and vice versa, at all 16 indices;
   the idle loop alternates 0x8097/0x8098, so a one-entry shift
   looks like a swap). The harness labels these \`VECTOR/C
   disagreement\`, like the pc / total\_cycles disagreements at
   every checkpoint (not failures). The RTL is faithful to the C
   model, which is the spec, so no ctrl change can fix it without
   breaking the C match. For the harness/vector owner: either the
   Python vector's `recent_pcs` is off by one, or the harness's
   ring indexing is. The gate's checkpoints (the substantive
   comparison) all pass.

## INTEGRATION-PENDING (for the lead) -- all RTL items done 2026-11-19

- Agent 3: CTRL-IOWS and CTRL-STBIT fixed; `step_i` park
  implemented and wired. The Yosys package import (synth
  blocker) is deferred per the user's RAM decision.
- Agent 2: AR-file / stack vectors (`o_ar_all` / `o_stack_all`)
  and the indexed AR read added; SAR fixed. Wired at the top
  (`ar_all_o` / `stack_all_o`, `ar_rd_sel` / `ar_rd_i`).
- Agent 1: `acc_next` exposed and wired to the ctrl's `alu_y`;
  `OP_LT_NM` added (KD-23 fixed); `i_op` widened to 7 bits
  and the top-level wires widened to match.
- Agent 4: observation outputs added (`o_obs_*`, wired to
  `obs_*_o` at the top).

Remaining harness work (agent 5) is DONE 2026-11-19: the co-sim
compares the full AR file / stack and the `obs_*_o` registers
per instruction; DXR writes are logged as pseudo-port IO events
(pre-edge `dxr_wr` sample); C pseudo-port events other than DXR
are excluded from the IO-event comparison with their effects
covered by state comparison; `run_to_cycles` stops at the next
`instr_done` (instruction boundary). The firmware co-sim and
the DSP smoke gate were re-run against the C core (see Current
status). Both open questions from agent 3 are SETTLED by the
co-sim evidence (open issues 6 and 7): the loop engine is
actually dead for loop ops, and the IN dm write is suppressed.
CTRL-LOOP (open issue 6) and CTRL-BCND (open issue 8) are both
FIXED 2026-11-19 (ctrl only, `rtl/c5x_ctrl.sv`): the firmware
co-sim passes 10000 instructions and the DSP smoke gate passes
all 8 checkpoints. TOP-EXTMMR, TOP-STATDP and TOP-IN are
FIXED 2026-11-19 (top level only, `rtl/c5x_core.sv`).
Residual top-level gaps, both documented in the top header:
a direct DMEM write to TREG1/TREG2 (0x0D/0x0E) is still
dropped (no ALU write path exists for them alone); in the
loop engine's WR phase the TREG0 ALU override takes priority
over the loop's own ALU op for one cycle if an SMMR/LMMR
wrote to TREG0 (re-check when CTRL-LOOP lands). The ctrl fixes
(CTRL-LOOP, CTRL-BCND) touched only `rtl/c5x_ctrl.sv`; the top
fixes touched only `rtl/c5x_core.sv`.

## House-rule / skill compliance

`rtl/c5x_core.sv`, `sim/cosim.cpp`, `sim/c_ref.c`,
`sim/c_ref.h`, `sim/Makefile` follow the fpga-systemverilog
skill and the golden house rules: SystemVerilog-2017,
`default_nettype none`, `always_comb`/`always_ff` with
complete assignments, nonblocking assignments in clocked logic
only, named port connections (never `.*`, never positional),
no `casex`/`casez`, one procedural owner per register, reset
only control state, no gated clocks, no new clock domains.
Comments in `rtl/c5x_core.sv` are C-style block comments
(`/* ... */`) only, 150 columns max, one statement per line,
one port connection per line with aligned names, typedef enum
states, magic numbers as localparams with a source comment.
`sim/` files are FPGA-only harness plumbing (labelled in their
headers). The sibling modules predate the house rules and use
`//` comments throughout; retrofit is Hrvoje's call, not this
agent's. The Yosys package-import block (synth) and the
`alu_y` / `ar_rd` interface gaps are documented, not silently
worked around.

---

# Pipelined core revision (2026-11-20, Worker D)

This part documents the retire-based harness for the pipelined
TMS320C5x core (converged plan `hidden_files/pipeline-plan-converged.md`,
hazard audit `docs/pipeline-hazards.md`). The multi-cycle content
above is the reference the harness was validated against; the
sections below describe the new protocol and the gates that run
once the pipeline lands. Worker D owns `sim/cosim.cpp`,
`sim/c_ref.c`, `sim/c_ref.h`, `sim/Makefile` (DSP targets only),
`tb/tb_c5x_pipe_step.sv`, and this document. No `rtl/*` file and
no 186 file is touched by this work.

## Pipeline description (what the harness assumes)

The pipelined core retires one instruction per clock in steady
state (1 IPC, 40 MIPS at 40 MHz), per the converged plan. The
retire signal is `instr_done`, a one-clock-wide pulse. The C
model is the spec (`c5x_core.c` + `c5x_cyctab.h`); the RTL must
match it instruction by instruction, exactly as the multi-cycle
core did. The TI-manual audit fixes are a separate later step,
logged as KNOWN-DIFF, never silently applied. The SV25 firmware
(SHA-256 43503d82...ef413f) is never patched.

Retire accounting per C step (plan section 9):

- One C step is one executed instruction. Expected RTL retires
  = (delayed op ? 3 : 1) + (took interrupt ? 1 : 0). A delayed
  op (BD 0x7D/0x7E/0x7F, 0xF0-0xF3, 0xF8-0xFB, 0xFC-0xFF, 0xBE21,
  0xBE3D) retires its branch word and its two slot words
  separately (3 pulses); state is compared only after the last
  retire. An interrupt entry in the same step is a separate
  retire pulse after the instruction's retire. The pushed PC is
  checked against the C stack entry `stack[(sp-1)&7]`.
- Mechanism (a) (one retirement, internal loop: SMMR 0x09, BLDP
  0x57, LMMR 0x89, MAC 0xA2, MACD 0xA3, BLPD 0xA4/A5, TBLR 0xA6,
  TBLW 0xA7, BLDD 0xA8/A9, MADS 0xAA, MADD 0xAB, BLDD bmar
  0xAC/0xAD): one retire, charged with the whole-repeat cycle
  count. Mechanism (b) (RPT + repeatable op, PC rewind via
  `handle_rpt`): one retirement per iteration, 1 cycle per
  iteration; the retire PC after a non-last iteration is
  `rpt_start`. RPTB is a third mechanism (fetch redirect via
  PASR/PAER/BRCR).
- Idle step without interrupt: no retire. The harness clocks the
  RTL until `cycles_o` advances by the C cycle delta; no
  cycle-delta comparison for idle steps (plan section 9,
  clarification 1). Idle step with interrupt (wake): exactly
  1 retire (the entry).
- Cycle comparison is per-instruction DELTA (C cycles before/after
  the single-step call, excluding the run loop's idle
  fast-forward, vs `retire_cycles_o`), NOT the absolute counter
  (absolute counters diverge across idle periods by design).

## New harness protocol (plan section 9)

- The harness clocks the RTL one clock at a time. On each clock
  where `instr_done` is high, it steps the C model exactly one
  instruction and compares the full architectural state (AR file,
  stack, mem-owned registers, pc). No extra clock after retire.
- `tim` is dropped from the per-retirement comparison. IFR is
  compared with bit 3 (TINT) masked out.
- `step_i` is redefined as a fetch hold: low stops F from
  fetching; in-flight instructions complete and retire; no retire
  pulses once the pipeline drains. The single-step protocol is
  rewritten around this (adaptive pulse: pulse `step_i` 1 clock,
  wait for retire, re-pulse up to 4 times for 2-word/redirect
  fetches, then drain-check for no further retire rising edge).
  Pending fetch redirect must survive `step_i` low (Worker A
  design note). `--singlestep N` exercises this protocol.
  Note: on the multi-cycle reference `step_i` only parks the FSM
  in DONE; it cannot prevent the first post-reset fetch, so the
  first instruction retires during the drain and the harness
  consumes that retire without pulsing (see `run_singlestep`).
- IO: the harness latches `io_port`/`io_wdata`/`io_wr` on the
  rising edge of `io_req` (the multi-cycle RTL's `io_wdata` is
  only valid on the first clock of `io_req`; the pipeline must
  hold `io_wdata` stable while `io_req` is asserted). IO events
  are logged on the rising edge of `io_ack` (fixes double-count
  with a delayed ack). `--io-delay N` inserts N clocks of host
  ack delay (H8).
- Interrupt-aware comparison: at an interrupt entry the harness
  does NOT require the two models to be at the same retirement
  index. It verifies the entry mechanism relative to the
  preceding retirement in each model separately (correct PC
  pushed = next instruction's address as of that retirement;
  correct 11 shadow registers as of the last retired
  instruction; correct vector load), then re-synchronises at the
  next sample boundary with a full-state comparison. If a
  sample-boundary comparison fails, it is reported as a defect
  to investigate, never dismissed as a harness artifact.
  Desync window: on an entry-timing mismatch the harness enters
  a window, tries up to 2-instruction phase alignment in either
  direction (advance RTL by up to 2 retires, advance C by up to
  2 steps, re-comparing after each advance), and resyncs once
  both models have taken the same number of entries and the
  full state matches. Resync failure stops with
  "SAMPLE-BOUNDARY RESYNC FAILURE -- defect to investigate".
  Known limitation (2026-11-20): the `--desync-test` one-step
  entry offset does NOT converge on the multi-cycle reference,
  because the C model checks interrupts AFTER executing the
  instruction in the step while the RTL checks at the retire
  boundary, so a one-step entry offset executes a different
  instruction sequence (the C runs the flushed MAR, the RTL
  does not; ar0 and the pushed PC genuinely differ). The resync
  machinery (window, alignment) is implemented and exercised,
  and it correctly reports the unreconcilable divergence rather
  than silently passing. A pure phase-shift desync (same
  instructions, different entry wall-clock) is the case the
  resync handles; the one-step-offset test as written is a
  sequence divergence, not a phase shift. Test-design limitation,
  not a harness bug; revisit when the pipeline lands.
- `PIPE_OBS` compile-time guard: when defined, `RState` /
  `rtl_get_state` read `retire_cycles_o`, `retire_is_intr_o`,
  and `obs_sh_*_o`, and the shadow comparison is active. The
  default build (multi-cycle, no `PIPE_OBS`) derives the RTL
  cycle delta from `cycles_o` at successive retire boundaries
  and cross-checks `retire_cycles_o` against the `cycles_o`
  delta once Worker A lands the ports. Build with
  `make cosim PIPE_OBS=1` for the pipeline. Do NOT define
  `PIPE_OBS` against the multi-cycle reference (the ports do
  not exist there).

## Sample-boundary timer verification (plan section 9 B1)

- Sample strobe: every 5,600 model cycles for the C model,
  every 5,556 wall clocks nominal for the RTL (40 MHz /
  7200 Hz). For long runs the exact 40/40.32 ratio is used
  with a Bresenham strobe (50000/9 wall clocks per sample);
  the +/-2 tolerance drifts past +/-2 beyond \~10 s emulated
  without it.
- At each boundary compare `timer_expiries` with tolerance
  `|RTL - C x (5,556/5,600)| <= 2`. Over the whole run check
  the TINT rate vs 2,401 x 40/40.32 = 2,382 Hz nominal,
  tolerance +/-1%. The check is gated on >=1000 expiries;
  short runs print "too few to gate" instead of failing.
- Do NOT compare the raw TIM value at boundaries (its phase
  differs by the accumulated 0.8%). `idle_cycles` is dropped
  from the checkpoint comparison (the pipelined core
  legitimately idles more wall clocks per sample).
- Sample mode default: wall-clock boundaries when `PIPE_OBS`
  is compiled in, model-cycle boundaries otherwise
  (multi-cycle reference validation mode); overridable by
  `--sample-wall` / `--sample-model`. On the multi-cycle core,
  wall mode is expected to fail (model-cycle timer); that is
  not a gate failure of the harness.

## CPI measurement and the C7 gate (plan section 10, audit section 5)

- The harness counts wall clocks and retirements per run and
  reports CPI = clocks / retired instructions, plus a stall
  breakdown by cause from the RTL observation counters (see
  the interface spec below): branch flush, 2-word fetch,
  PMEM-operand stall, RPT replay clocks, IO-wait clocks,
  interrupt entry clocks, hazard stalls by class
  (H1/H1a/H1b/H2/H3), RPTB setup, H10 flush, MAC replay, XC.
- CPI accounting identity: total wall clocks = retirements +
  sum of stall classes + idle-parked clocks + pipeline-fill
  residual (residual reported explicitly, must be small).
- CPI GATE -- audit section 5.3: the 100k gate window is
  base-code polling (BIT+BCND loop at 3.000 CPI + 1,533 init
  instructions at 1.063 CPI). The audit's C7 expected CPI for
  THIS window is 2.9703 (297,029 clocks / 100,000
  retirements), dominated by taken branches (+1.4770) and
  2-word instructions (+0.4929). Gate the measured CPI against
  the C7 estimate FOR THE SAME WINDOW (tolerance: report the
  delta per class; any class costing >0.05 CPI over its
  estimate gets a named explanation). Do NOT gate the 100k
  window against 1.0 -- the \~1.0 target applies to
  steady-state FIR work, which must be re-derived from a longer
  run reaching ov6 (flagged as a follow-up run once the pipeline
  lands; the 100k gate is the acceptance bar).
- Gate applicability: only in `--firmware` mode with
  steps==100000, image `dsp_base.bin`, final pc 0x8098, C cycles
  247799, AND `PIPE_OBS` counters present. Otherwise the
  harness reports CPI + breakdown only; gate N/A.
- Harness-side classification (live, from the C trace):
  taken branch via `op_is_control` + next-PC test (next-PC =
  pushed PC if entry else `cs.pc`); 2-word via `info.words`.
  This cross-checks the audit's 49,233 taken / 49,287 two-word
  counts. `--cpi-selftest` validates the gate evaluator on
  synthetic vectors (one passing, one with a class +0.06 CPI
  over, which must flag FAIL).
- Classifier-vs-C7 residual (2026-11-20, multi-cycle reference,
  100k window): classifier total 297,024 vs C7 297,029
  (delta -5). Per class: base 100000, taken\_branch 147699,
  two\_word 49287, pmem\_op 1, rpt\_replay 10, h1 23, h1a 0,
  h1b 1, h2 3, h10 0, int\_entry 0, rptb\_setup 0. The -5 is a
  documented audit discrepancy, not a harness error: the audit
  counts 3 map writes (+9 clocks) but only 1 exists in the run
  (+3) -- audit overcounts H2 by 6; the audit counts H1b as 0
  net (subsumed by H2) but the classifier counts 1 (the genuine
  H1b event is NOT the H2 follower, so it is not subsumed).
  Report to the audit owner. Ground truth for the 100k window:
  map writes = 1 (step 11, pc 0x8011, op 0x0F7D, LST #1); H1b
  raw candidates = 8, only 1 genuine (step 1521, pc 0x8088,
  op 0x7718, dma 0x18); mechanism-(a) execution = 1 BLPD #pma
  (step 1470, pc 0x8032, op 0xA5A0, words=2, cyc\_delta=13,
  base charge 3, replay = 10).
- Measured CPI on the multi-cycle reference (for reference
  only, NOT a gate): 100k firmware run = 1,046,410 wall clocks
  / 100,000 retirements = 10.4641 CPI. Classifier prediction
  297,024; residual 749,386 clocks (multi-cycle \~8-10
  clocks/instr vs pipeline \~3). Expected, not a gate.

## RTL observation outputs required

Worker A: implement these ports on `c5x_core` (exact names and
widths). The harness reads them when built with `PIPE_OBS`
(`make cosim PIPE_OBS=1`). Do not guess at RTL internals; the
counting rules below are the contract.

### Per-retire outputs (valid from the retire pulse until the next retire)

| port | width | counting rule |
| --- | --- | --- |
| `retire_cycles_o` | [31:0] | C-model cycle charge of the retiring instruction, including +4 for an entry pseudo-instruction; whole-repeat charge for a mechanism-(a) execution. |
| `retire_is_intr_o` | 1 | High during an entry-pseudo retire pulse (hardware interrupt entry); low otherwise. |

### Stall counters (each [31:0], count-up per wall clock while the stall condition holds, reset with core reset, counting EXTRA clocks beyond the 1-per-retirement base)

| port | counting rule |
| --- | --- |
| `cnt_stall_branch_o` | +3 per taken branch refill. |
| `cnt_stall_2word_o` | +1 per 2-word extra fetch slot. |
| `cnt_stall_pmem_op_o` | +1 per PMEM-operand F stall. |
| `cnt_stall_rpt_replay_o` | +(N-1) per mechanism-(a) execution; 0 for mechanism (b). |
| `cnt_stall_io_wait_o` | E clocks stalled on host IO ack, minus 1 per IO instruction. |
| `cnt_stall_int_entry_o` | +3 per interrupt entry. |
| `cnt_stall_h1_o` | D-hold AR/INDX/ARCR/DP/ARP/circular. H1 cost rule: reader distance 1 from writer costs 2 clocks if 1-word reader, 1 if 2-word; distance 2 costs 1 if 1-word, 0 if 2-word. |
| `cnt_stall_h1a_o` | D-hold ACC/BMAR (R-phase PMEM address sources: TBLR/TBLW pfc=ACC, BLPD-bmar/BLDD-bmar/MADS/MADD pfc=BMAR). |
| `cnt_stall_h1b_o` | R-hold MMR read after MMR write, distance 1. |
| `cnt_stall_h2_o` | F/D hold for a map-changing writer, including F-hold from decode until the cycle after the map write lands. |
| `cnt_stall_h3_o` | Deferred-IO-read hold clocks, normally 0. |
| `cnt_stall_rptb_setup_o` | +2 per RPTB setup. |
| `cnt_stall_h10_o` | +3 per PMEM-write flush (TBLW/SMMR/BLDP). |
| `cnt_stall_mac_replay_o` | +N per external-dma MAC execution (same-array double access; 0 events in the 100k window). |
| `cnt_stall_xc_o` | Refill clocks after XC-false skip; 0 if resolved without refill. |

### Shadow observation outputs (sampled at entry retire; equal to the architectural state as of the last retired instruction)

| port | width |
| --- | --- |
| `obs_sh_acc_o`, `obs_sh_accb_o`, `obs_sh_preg_o` | [31:0] |
| `obs_sh_treg0_o`, `obs_sh_treg1_o`, `obs_sh_treg2_o`, `obs_sh_arcr_o`, `obs_sh_indx_o`, `obs_sh_st0_o`, `obs_sh_st1_o`, `obs_sh_pmst_o` | [15:0] |

### Additional notes for Worker A (from multi-cycle diagnosis)

- The interrupt input must latch a 1-clock pulse into IFR
  (the harness pulses `irq_i`; a level-held line re-sets IFR
  after the entry ack -- the multi-cycle RTL's failure mode).
- IFR must be cleared on hardware entry (the multi-cycle RTL
  never clears it; see KNOWN-DIFF below).
- `io_wdata` must be held stable while `io_req` is asserted
  (the multi-cycle RTL's is only valid on the first request
  clock; the harness latches at the `io_req` rising edge to
  cope).
- BRAF must clear as part of the last RPTB block word (the
  multi-cycle RTL never clears it -- `rptb_clr_en`
  unconnected -- and its BRCR decrement is dropped for ALU
  last words; see KNOWN-DIFF below).
- `pc_o` at retire = next-instruction address (for a
  mechanism-(b) non-last iteration = `rpt_start`; for an entry
  retire = the vector). Fetch-redirect pending must survive
  `step_i` low.
- ADRK/SBRK must update AR[ARP] by +/-k (the multi-cycle RTL
  does not implement them at all; see KNOWN-DIFF below).

## Directed tests (plan section 10.2)

`./cosim --directed NAME`, `--directed-all`, `--list-directed`.
One per hazard class H1-H9 plus H1a, H1b, H10, plus branch flush
with a following AR update, interrupt flush with a following AR
update, RPT/RPTB replay (including RPT + circular MACD, the FIR
hot path), deferred IO read, IDLE wake and IDLE2 wake. Each
compares retire state vs the C model on a minimal program.

| test | class | program (essence) |
| --- | --- | --- |
| h1-ar | H1 | LAR AR0,#0x60 then LACC \*AR0+ (distance 1 and 2); LDP #1 + SACL direct DP variant |
| h1a-acc | H1a | LACC #lk + TBLR (ACC as PMEM address); PMEM pokes 0x9000=0x1234, 0x9001=0x5678 |
| h1a-bmar | H1a | SPLK #0x9000,0x1F (BMAR) then BLPD bmar |
| h1b-indx | H1b | SPLK #0x1234,0x18 (INDX) then LACC 0x1018 |
| h1b-pmst | H1b | SPLK #0x00B0,0x07 (PMST) then LACC 0x1007 (subsumed by H2) |
| h2-map | H2 | SCNF 0xBE45, SPLK PMST 0x00B0 |
| h3-drr | H3 | Serial tick rx=0x5A5A before run; B to target with flushed LACC 0x1020; SPC read checks RRDY bit 10 still 1 before the real DRR read, 0 after |
| h4-bypass | H4 | SPLK #0x1357,0x60 then LACC 0x1060 distance 1; SACL/LACC pair |
| h5-branch-flush-ar | H5 | B to target with flushed MAR \*AR0+; dm[0x60]=0x1111, dm[0x61]=0x2222 |
| h5-bcnd-flush-ar | H5 | BIT 4,0x80 + BCND 0xE200 |
| h6-int-flush-ar | H6 | IMR INT1 via SPLK, EINT, inject INT1 after step 3 so the entry follows step 4 LACK and MAR \*AR0+ is the flushed instruction; ISR at 0x0002: LACK #0x77, then B-self loop (RETE removed; see below) |
| h7-rpt | H7 | RPT #2 + SACL \*AR0+, 3 iterations |
| h7-rptb | H7 | BRCR=2 via LACK #2 + SAMM; RPTB PAER=0x8009; 4-instruction block |
| h7-rpt-macd | H7 | RPT #5 + MACD \*AR0+,0x9000 with circular setup (CBCR=0x08, CBSR1=0x70, CBER1=0x73, INDX=1, BMAR=0x9000); PMEM coeffs 2,3,5,7,11,13 at 0x9000-0x9005; taps at dm 0x70-0x73; 6 iterations, 1 retire, wraps once; TREG0 loaded via SPLK #0x0010, dm[0x0C] (not LT; LT is broken in the multi-cycle RTL) |
| h7-rptb-2word-end | H7 | PAER = first word of a 2-word SPLK; block executes once, no rewind |
| h8-io | H8 | OUT/IN 0xFF50 with `--io-delay 3` |
| h9-2word | H9 | Back-to-back SPLK / LAR #lk / LACC #lk / B |
| h10-tblw | H10 | TBLW writes pm[0x8010]=0xB922 over initial 0xB911, then B 0x8010 executes the new LACK #0x22 |
| h10-smmr | H10 | SMMR {0x0960, 0x8010} |
| h10-bldp | H10 | BMAR=0x8010, BLDP \*AR0+ |
| delay-slot | delay | BD + 2 slot words; 3 retires per 1 C step on the pipeline, 1 on the multi-cycle reference |
| xc-skip | XC | XC 0xE600 skip-if-!TC with TC=1 via BIT |
| xc-noskip | XC | XC 0xE500 no-skip |
| bitrev | addressing | Bit-reversed addressing mode |
| idle-wake | IDLE | PRD=5/TIM=5/TCR=0/IMR TINT via SPLKs, EINT, IDLE 0xBE22, ISR at 0x001E, \~7 idle steps, tail + B-self loop, cap \~40 steps |
| idle2-wake | IDLE2 | IMR INT1 only, IDLE2 0xBE23, inject INT1 after the IDLE step, ISR at 0x0002, tail + B-self loop, cap \~25 steps |
| intr-rete | INTR+RETE | Program {0xBC00, 0xB060, 0xB911, 0xBE60, 0x8BA0, 0x10A0, 0x9062, 0xB900} (8 words, 10 steps); ISR {0x0002, 0xB977, 0x0003, 0xBE3A} (LACK #0x77, RETE); dm preset dm[0x60]=0x1111, dm[0x61]=0x2222; INTR 0 -> vector 0x0002 |

Result on the multi-cycle reference (2026-11-20):
`./cosim --directed-all` = 26/27 passed. Only `intr-rete`
fails (state mismatch at step 8, pc=0x3, op=0xBE3A, the RETE)
-- a genuine multi-cycle RTL bug (RETE shadow restore broken;
see KNOWN-DIFF). It must pass on the pipeline. All others pass.

Notes on the directed tests (multi-cycle reference only):

- The `idle` field comparison is skipped when `c->op` is IDLE
  (0xBE22) or IDLE2 (0xBE23): the phase differs by design at
  the IDLE boundary (the C latches idle=1 after the IDLE
  instruction and takes the wake entry in a later idle step;
  the RTL goes straight to FSM\_INT from the IDLE's TAIL when
  the wake is already pending, so `idle_o` is never 1). The
  wake entry and subsequent state are compared by following
  steps.
- IFR is masked for the injected bit (`g_ifr_mask`, set from
  `o.inject_bit` / `o.desync_bit`), and PMST bit 0 (BRAF) and
  BRCR are masked per step / per run (`g_mask_braf`,
  `g_mask_brcr`), all `#ifndef PIPE_OBS` only. These masks
  exist because the multi-cycle RTL never clears IFR on entry,
  never clears BRAF, and drops the BRCR decrement for ALU last
  words (see KNOWN-DIFF). The pipeline must do all three
  correctly, so the masks are off under `PIPE_OBS`.
- The ISR in h6, idle-wake and idle2-wake uses a B-self loop
  instead of RETE, because the multi-cycle RTL's IFR never
  clears and a RETE would re-enter the ISR. The RETE return
  path is covered by the separate `intr-rete` test.
- The h7-rpt-macd program loads TREG0 via an MMR write
  (SPLK #0x0010, dm[0x0C]; TREG0 is MMR 0x0C, not 0x05 --
  0x05 is GREG), not via LT, because LT does not load TREG0
  in the multi-cycle RTL (see KNOWN-DIFF).

## Random pipeline test (plan section 10.3)

`./cosim --random SEED [N]` (seeded xorshift, program region
0x8000-0x80FF, fixed prologue, body of weighted templates, ends
with B back to body start; step cap bounds the run; pass = all
capped steps matched). `--dump-random SEED` prints the generated
program and exits (diagnostic, kept deliberately).

Generator coverage (hazard classes, not just straight-line ALU):

- dm ALU ops direct and indirect (\*AR modes none/+1/-1, and
  +INDX/-INDX under `PIPE_OBS` only), SACL/SACH, immediates,
  LAR/MAR/ADRK (ADRK under `PIPE_OBS` only; see below), MPY/LT
  family (under `PIPE_OBS` only; see below), LDP/LST/SST, BCND
  to in-program instruction boundaries, RPT + repeatable op,
  RPTB branch-free blocks, SMMR/BLDP/TBLR/TBLW/BLPD/LMMR/BLDD
  with safe addresses, rare IN/OUT, rare XC, rare delayed
  branches. Never emits IDLE/IDLE2, TRAP/NMI/INTR, RETI/RETE,
  BACC/CALA (wild targets), BADOP, or a delayed op within 2
  words after another delayed op.
- Prologue (17 words): init AR0-7 to scratch, INDX=1, DP=0,
  TREG0 (via SPLK MMR write), BMAR=0x9000, circular regs.
  DMEM scratch 0x60-0x7F (preset 0x1000 + i\*0x11) and PMEM
  scratch 0x9000-0x90FF (preset 2+i) set identically in both
  models via pokes.
- Reinit every 5 generated instructions: LAR AR0,#0x60;
  LAR AR1,#0x70; SPLK #0x0001,0x18 (INDX=1). Without it the AR
  drifts out of scratch over a long run into live-MMR or
  external-dm addresses (the multi-cycle RTL mis-reads both;
  see KNOWN-DIFF).
- Coverage is tracked per executed opcode (high byte +
  0xBE/0xBF low byte) and printed at the end of each run.

Multi-cycle reference constraints (all `#ifndef PIPE_OBS`,
all lifted under `PIPE_OBS` so the pipeline is covered fully):

- MPY/LT family: only LACC is generated (plain MPY does not
  set PREG and the LT family does not load TREG0 in the
  multi-cycle RTL; see KNOWN-DIFF). Under `PIPE_OBS` the full
  set is generated (MPY 0x54, LT 0x73, LTA 0x70, LTD 0x72,
  LTS 0x75).
- Indirect modes: only none/+1/-1 (a large INDX takes the AR
  out of scratch). Under `PIPE_OBS` all 5 modes (none/+1/-1/
  +INDX/-INDX).
- ADRK: replaced by SFTA (the multi-cycle RTL does not
  implement ADRK/SBRK at all; see KNOWN-DIFF). Under
  `PIPE_OBS` ADRK 0-15 is generated. SBRK is not generated by
  the template at all; the pipeline must implement it too.
- ADRK range: 0-3 without `PIPE_OBS`, 0-15 with it.
- RPTB last body word: forced to SACL (a store, no ALU flag
  writeback) without `PIPE_OBS`, because the multi-cycle RTL
  drops the BRCR decrement for ALU last words. Under
  `PIPE_OBS` any of LACC/ADD/SACL is generated for all 3 body
  words, so the pipeline's BRCR decrement is covered for ALU
  last words too.
- Random runner masks BRAF and BRCR for the whole run under
  `#ifndef PIPE_OBS` (the RTL never clears BRAF and drops the
  BRCR decrement for ALU last words); the masks are off under
  `PIPE_OBS`.

Results on the multi-cycle reference (2026-11-20, 2000 steps
each): seeds 1, 42, 7, 123, 99, 2024, 5, 17, 3, 11, 2, 6, 8, 13
PASS (2000/2000 matched). Seed 4 FAILS at step 134
(op=0x6CA0 XOR \*AR0+, ea=0x0080, external dm): the AR drifted
to 0x80 (just outside scratch 0x60-0x7F) and the RTL read the
PMEM word (the next instruction, BD 0x7D00) instead of
dm[0x80]=0 -- the external-dm-read bug (see KNOWN-DIFF). 14/15
seeds pass; the one failure is a documented RTL bug, not a
harness failure.

## Opcode coverage

Coverage is tracked per executed opcode (high byte + 0xBE/0xBF
low byte) and printed at the end of each firmware/random run.

Firmware 100k window (2026-11-20): 23 distinct high bytes,
0xBE sub-opcodes 3, 0xBF sub-opcodes 3. High bytes: 0C 0F 44
5D 5E 76 77 87 88 8A 8B 90 98 A5 AE B1 B8 B9 BB BC BE BF E2.
This window is base-code polling only (BIT + BCND loop);
it exercises no ov6/ov7, no RPTB, no MAC, no interrupt, no
delay slot, no XC. Those are covered by the directed tests
(H7 RPT/RPTB/MACD, delay-slot, XC, H6 interrupt, IDLE/IDLE2)
and the random test, not by the firmware window.

Unexercised opcodes and their justification (plan section 10.3:
a directed test or a written justification for each):

- TBLW: directed test h10-tblw (PMEM-write flush).
- IDLE2 wake path: directed test idle2-wake.
- TREG1/TREG2 direct writes: NOT exercised by any gate. The
  multi-cycle RTL drops direct DMEM writes to TREG1/TREG2
  (0x0D/0x0E) entirely (no ALU write path exists for them
  alone; the ALU can change them only via the TREG0 mirror).
  This is a known top-level gap from 2026-11-19, still open.
  The pipeline needs a directed test for a direct TREG1/TREG2
  write once Worker A adds the write path; until then it is
  an explicit coverage gap, not a silent pass.
- Addressing modes the firmware never uses (+INDX/-INDX,
  bit-reversed): covered by the random test (all 5 indirect
  modes under `PIPE_OBS`) and the directed bitrev test.
- MMR AR-file read (0x10-0x17) and external dm read (>=0x80):
  NOT covered by a directed test yet. The random test hits
  both only when the AR drifts out of scratch (seed 4 / seed
  99), which is how the two multi-cycle bugs were found. The
  pipeline needs directed tests for both: an indirect read
  with ea in 0x10-0x17 (must return the AR file value) and an
  indirect read with ea >=0x80 (must return DMEM, not a PMEM
  word). Open follow-up.
- RPTB blocks with control flow inside: coverage gap. The
  directed h7-rptb tests use branch-free blocks; a block
  containing a branch is not exercised. Open follow-up.
- ADRK/SBRK: covered by the random test under `PIPE_OBS`
  only (ADRK 0-15). SBRK is not generated; a directed test
  for SBRK is an open follow-up.

## Smoke-gate adaptation (plan section 10.5)

`./cosim --dsp-smoke`: 8/8 checkpoints OK under the revised
checkpoint comparison of section 9. Changes vs the old gate:

- `tim` dropped from the per-retirement comparison.
- IFR compared with bit 3 (TINT) masked out.
- `idle_cycles` dropped from the checkpoint comparison.
- `timer_expiries` compared via the sample tracker + TINT-rate
  check (section 9 B1), not as a raw checkpoint field.
- End-of-run checks gate RTL-vs-C (checksums, DXR ring,
  recent\_pcs, IO events); vector disagreements are notes only.
- The pre-existing `recent_pcs[16]` vector-ring-shift artifact
  is a vector artifact, not an RTL bug: RTL==C at every index
  but the vector differs (shifted by one entry). Recorded as
  the same artifact, do not chase, do not fail.
- The smoke-vector parse call was fixed 2026-11-20:
  `parse_smoke_vector` returns 0 on success, but the caller
  used `if (!parse_smoke_vector(...))`, which treated success
  as failure ("cannot parse smoke vector"). Now
  `if (parse_smoke_vector(...) != 0)`.

Result on the multi-cycle reference (2026-11-20):
`./cosim --dsp-smoke` = checkpoints 8/8, status=0.
Checkpoints 7 and 8 differ from the vector (C pc=0x8097 vs
vector pc=0x8098) -- a vector disagreement, noted, not a
failure. `recent_pcs` differs from the vector at 16/16 entries
(known ring-shift artifact; RTL==C above). IO events: vector
13 vs RTL 9 (the vector counts unobservable events too; C
observable=9, RTL=9, ok). Sample boundaries: paired=1428,
max|diff|=0 (tol 2); TINT rate 2399 Hz (nom 2401, err 0.08%).

## New SystemVerilog testbench

`tb/tb_c5x_pipe_step.sv`: generic single-step program runner.
Loads a program hex file via `+hex=<path>` (one 16-bit word
per line, loaded at 0x8000), single-steps the core with the
fetch-hold protocol (pulse `step_i` high for one clock, wait
for `instr_done`), and prints one retire record per retire
(index, pc, op, model-cycle delta, acc, ar\_cur, st0, st1).
Plusargs: `+steps=<n>` (default 100), `+maxclk=<n>` (default
100000). It does NOT compare against the C model; that is
cosim's job. Build with `make tb-pipe HEX=<path> N=<n>`
(uses `--binary --timing`). House rules apply (block comments
only, 150 columns, case tables not ternary chains); lints
clean with `verilator --lint-only -Wall --timing`.

Notes: `instr_done` on the multi-cycle reference is a LEVEL
(high while parked in DONE on `step_i` low), not a pulse, so
this runner has no drain check (the pulse property is verified
by cosim, which counts retire pulses). The word count is done
by counting lines with `$fgets`, not an x sentinel (Verilator
is 2-state; x compares as 0). No host is attached, so a program
containing IO stalls until the watchdog fires.

Validated 2026-11-20 against the pre-pipeline snapshot:
6-word smoke program (LACK #1-4, B-self) prints 6 retire
records and PASS.

## Multi-cycle validation status (2026-11-20)

The live `rtl/` was broken during this work (Workers B/C
mid-landing: `make cosim` fails with 11 `PINNOTFOUND` errors
in `rtl/c5x_core.sv` vs `rtl/c5x_mem.sv`). All validation below
used the pre-pipeline snapshot in `hidden_files/pre-pipeline/`
with the new `sim/cosim.cpp` + `sim/c_ref.c`/`sim/c_ref.h`,
built by hand (Verilator 5.020, Yosys 0.33; see the toolchain
note in GOAL.md): `verilator --cc` (no --exe) to generate the
model, `make -f Vc5x_core.mk` in the obj dir, then compile
`cosim.cpp` and link manually. (`verilator --cc --exe --build`
fails because the generated makefile records `cosim.cpp`
relative to `sim/` but make runs in the obj dir.)
`sim/cosim` in the goal dir is a stale Nov 19 old-harness
binary. The `sim/Makefile` targets (`make cosim`,
`make directed-all`, etc.) build against live `rtl/` and
cannot run until B/C/A land; `make -n` was verified for the
new targets.

Exact commands and outputs (all from `/tmp/pipe-ref/cosim`,
built from the pre-pipeline snapshot):

- `./cosim --smoke 4`: steps=4 matched=4 retires=4 clocks=28
  final pc=0x8004 C cycles=4 status=0.
- `./cosim --reset-check`: status=0.
- `./cosim --cpi-selftest`: identical vectors PASS;
  taken\_branch +0.06 CPI correctly FAILs the gate; status=0.
- `./cosim --selftest 1000`: steps=1000 final pc=0x801D
  cycles=1024 pm\_sum=38CAF093 dm\_sum=0005BA79 status=0.
- `./cosim --singlestep 20`: steps=20 status=0. (Required a
  fix: the first instruction retires during the drain because
  `step_i` cannot prevent the first post-reset fetch on the
  multi-cycle core; the harness now consumes that retire
  without pulsing.)
- `./cosim --firmware 1000`: steps=1000 matched=1000
  retires=1000 clocks=8042 final pc=0x801D C cycles=1024
  io\_events=2 entries C=0 RTL=0 status=0. Classifier total
  1022, residual 7020 clocks (multi-cycle \~8 clocks/instr
  vs pipeline \~3; expected, not a gate).
- `./cosim --firmware 100000`: steps=100000 matched=100000
  retires=100000 clocks=1046410 final pc=0x8098 C cycles=247799
  io\_events=9 entries C=0 RTL=0 resyncs=0 status=0. CPI
  measured 10.4641 (multi-cycle). Classifier total 297024
  (see above). Sample boundaries paired=44 max|diff|=0.
  Coverage: 23 distinct high bytes, 0xBE sub-opcodes 3,
  0xBF sub-opcodes 3. CPI gate: N/A (needs `PIPE_OBS` RTL
  counters; classifier prediction is the pre-landing check).
- `./cosim --dsp-smoke`: checkpoints 8/8 status=0 (see above).
- `./cosim --directed-all`: 26/27 passed (only intr-rete
  fails; see above).
- `./cosim --random SEED 2000` (15 seeds): 14/15 pass
  (2000/2000 matched); seed 4 fails at step 134 on the
  external-dm-read bug (see above).
- `./cosim --desync-test`: does NOT converge (see the
  limitation note above); the window opens and the alignment
  runs, but the one-step entry offset is a sequence divergence
  on the multi-cycle reference.
- `tb/tb_c5x_pipe_step.sv`: lints clean (`-Wall --timing`),
  builds and runs against the pre-pipeline snapshot (6-word
  smoke program, 6 retire records, PASS).

The `PIPE_OBS` code path is written but NOT compiled or tested
yet (the ports do not exist in any RTL). Lead verification after
Worker A lands must compile it (`make cosim PIPE_OBS=1`) and
re-run every gate above.

## Known multi-cycle RTL divergences (KNOWN-DIFF)

Confirmed 2026-11-20 against the pre-pipeline snapshot, all
diagnosed against the C model source. These are RTL defects,
not harness bugs. The pipeline must NOT reproduce them.

- IFR never cleared on hardware interrupt entry (affects
  h6-int-flush-ar, idle-wake, idle2-wake). Root cause:
  `irq_ack_o` is asserted only inside the `FSM_TAIL` case in
  `c5x_ctrl.sv` (line \~2330, \`if (int\_pending\_q) irq\_ack\_o =
  (9'd1 << int\_idx\_q)`), but&#32;`int\_pending\_q\` is set only at
  the TAIL's clock edge (line 3674), after which the FSM has
  left TAIL for FSM\_INT -- so the ack never fires. The top
  converts the ack to a WR\_IFR write (W1C) to the addr unit
  (`c5x_core.sv` line \~852), and the addr unit clears `ifr_q`
  on WR\_IFR (`c5x_addr.sv` line 880), but no ack ever arrives.
  Traced: a single pulse latches ifr\_o=0x0001, the entry runs
  (pc=0x0002), the ISR LACK executes, RETE returns pc=0x8005,
  and ifr\_o stays 0x0001 throughout. Consequence: after RETE
  the RTL re-enters the ISR while the C model does not. The C
  model clears the IFR bit in `check_int`. The pipeline must
  clear IFR on entry.
- BRAF never clears after an RPTB block (h7-rptb).
  `rptb_clr_en` is asserted by the ctrl (`c5x_ctrl.sv` line
  2314, in the TAIL when `brcr==0` at the last block word)
  but left UNCONNECTED in `c5x_core.sv` line 1494
  (`.rptb_clr_en()`). So BRAF stays set forever after any
  RPTB block. Also `i_braf_check` is tied to `1'b0` in the
  core's addr-unit instantiation (`c5x_core.sv` line 1351),
  so the addr unit's own `handle_braf` (BRCR decrement / BRAF
  clear, `c5x_addr.sv` lines \~840-850) never runs.
- BRCR decrement dropped when the last RPTB block word is an
  ALU op. The ctrl's `brcr_ld_en` path (`c5x_ctrl.sv` lines
  \~2307-2314: at the last block word, `brcr>0` ->
  `brcr_ld_en=1, data=brcr-1`, else `rptb_clr_en=1`) goes
  through the single write-port mux in `c5x_core.sv`
  (\~line 848), where the TAIL's flag writeback (ST0/ST1 load,
  gated on `alu_used_q`) has higher priority. For an ALU last
  word (LACC/ADD/SUB) the flag writeback wins and the BRCR
  decrement is dropped, so BRCR stays at its initial value and
  the block never terminates (PC rewinds forever instead of
  falling through at block end). For a non-ALU last word
  (SACL/SACH store, no flag writeback) the decrement goes
  through. Traced: h7-rptb (SACL last word) decrements BRCR
  2->1 and 1->0; random seed 7 (LACC last word) keeps BRCR=2
  and the PC rewinds at step 22 (C pc=0x8018 fall-through vs
  RTL pc=0x8015 rewind).
- LT/LTA/LTD/LTP/LTS TREG0 load does nothing (h7-rpt-macd,
  random seeds). Traced: with dm[0x70]=0x2222, LT 0x7370
  retires and treg0 stays 0x1110 (unchanged). Root cause:
  `d_w = (state_q == FSM_OP_DATA)? dm_rdata: imm_q`
  (`c5x_ctrl.sv` line 696) -- the dm operand is never latched,
  so LT/MPY consume it when it is no longer the operand. The
  ctrl's LT case sets `ex_treg_ld=3'b001`,
  `ex_treg_data=d_w` (`c5x_ctrl.sv` line \~1149), but the core's
  ALU instantiation leaves `.treg_data ()` unconnected
  (`c5x_core.sv` line \~1460), and the ALU's TREG0 load data
  comes from `i_b16` (`alu_b16_mux = ctrl_alu_d`).
- Plain MPY/MPYU do not set PREG (random seeds). Traced: MPY
  0x5471 (TREG0=0x1110, dm[0x71]=0x0003) retires and preg stays
  0x00000000 (should be 0x3330). Same unlatched-`d_w` root
  cause: the ctrl's MPY case sets `ex_mpy_a = treg0_i`,
  `ex_mpy_b = d_w` (`c5x_ctrl.sv` lines 937-938, 948-949), and
  in the EXEC/OP\_DATA window `d_w` is `imm_q` (=0 for a 1-word
  op), so the product is TREG0 x 0 = 0. The loop-engine
  MAC/MACD/MADS/MADD use a separate operand path and work
  (directed h7-rpt-macd passes).
- RETE/RETI shadow restore broken (intr-rete). The core's ALU
  instantiation leaves `.acc_data ()`, `.accb_data ()`,
  `.preg_data ()`, `.treg_data ()` all UNCONNECTED
  (`c5x_core.sv` lines \~1455-1460), so the FSM\_RESTORE
  sequencer's data (`acc_data = sh_acc_q`, etc.,
  `c5x_ctrl.sv` lines 2423-2425) never reaches the ALU.
  Observed: after RETE, C acc=0x00000000 st1=0x01BC
  indx=0x0000 arcr=0x0000 (shadow restored), RTL
  acc=0x00000077 st1=0x07FC indx=0x0060 arcr=0x0060 (ISR state
  kept). The restore sequencer itself exists (FSM\_RESTORE
  phases 0-8, `c5x_ctrl.sv` lines 2415-2479, 3836) and the
  RETE does reach it (line 3260), but the restores do not take
  effect. The pipeline must restore all 11 shadow registers
  on RETE/RETI.
- MMR AR-file read returns 0 (random seeds 2024, 11, 99, 5,
  17). The C model's `mmr_rd` returns `c->ar[a-0x10]` for
  addresses 0x10-0x17. The RTL's dm read for those addresses
  returns 0. Evidence: seed 2024 ADD \*AR0- with ea=0x0011
  (AR1=0x70): C adds 0x70 (acc 0x1099->0x1109), RTL adds 0.
  Seed 11 ADD +INDX with ea=0x0010 (AR0=0x61): C adds 0x61
  (0x1121->0x1182), RTL adds 0. Seed 99 AND \*AR0 with
  ea=0x0010 (AR0=0x10): C acc 0xD2 & 0x10 = 0x10, RTL acc 0.
- External dm read (>=0x80) returns a PMEM word (random seeds
  1, 99, 5, 17, 4). Evidence: seed 1 XOR \*AR1+ ea=0x00D1
  (dm=0): RTL effective operand 0xBB01, found in PMEM at
  0x8026 (the next instruction word), not in DMEM. Seed 99 XOR
  \*AR0- ea=0x00C2 (dm=0): RTL operand 0xB060, PMEM at 0x8001.
  Seed 5 ADD \*AR0 ea=0x00BE: RTL operand 0x1062, PMEM at
  0x8017. Seed 17 ADD \*AR0- ea=0x00C2: RTL operand 0xBFC0,
  PMEM at 0x8014. Seed 4 XOR \*AR0+ ea=0x0080: RTL operand
  0x7D00, PMEM at 0x8031. The RTL's dm read for non-scratch
  addresses returns PMEM content instead of DMEM (0 for those
  addresses).
- ADRK/SBRK not implemented at all. The ctrl's ADRK cases are
  empty stubs (`8'h78: begin end` in the main block, line 1176,
  and in the addr agent, line 2078), the decoder maps ADRK to
  ALU\_NOP (`c5x_decode.sv` line 252), and no AR update exists
  anywhere in the addr unit or the core (no ADRK/SBRK handling
  in `c5x_addr.sv` or `c5x_core.sv`). Traced: ADRK #1 (0x7801,
  ARP=1, ar1=0x006F) does nothing (C ar1=0x0070, RTL
  ar1=0x006F). The pipeline must update AR[ARP] by +/-k for
  ADRK/SBRK.
- Delay-slot / entry retire granularity (multi-cycle only).
  The multi-cycle RTL retires BD+2-slots as ONE `instr_done`
  pulse (not 3), and an interrupt entry suppresses the
  interrupted instruction's pulse (TAIL branches to FSM\_INT,
  skipping DONE), so an instruction+entry step produces exactly
  ONE pulse (the entry). On the multi-cycle core every executed
  step is exactly 1 retire, idle step 0 (1 if it woke on an
  entry). On the pipeline (PIPE\_OBS): delayed op = 3 pulses,
  entry = separate pulse after the instruction (instruction +
  entry = 2, +2 more for a delayed op). The harness encodes
  this per build (`expected_retires`).
- Entry cycle-delta +1 (multi-cycle only). The multi-cycle
  FSM\_INT costs one clock more than the C model's +4 (measured
  C delta 5, RTL delta 6 on an entry step). The harness skips
  the cycle-delta check for entry steps on the multi-cycle
  core; state comparison still runs. Not a pipeline property.
- IDLE `idle` field phase difference (idle-wake, idle2-wake).
  C latches idle=1 after the IDLE instruction and takes the
  wake entry in a later idle step; the RTL goes straight to
  FSM\_INT from the IDLE's TAIL when the wake is already pending,
  so `idle_o` is never 1. All other fields agree. The harness
  skips the `idle` comparison when `c->op` is IDLE/IDLE2.
- IO `io_wdata` validity window (multi-cycle only). The RTL's
  `io_wdata` is only valid on the first clock of `io_req`
  (traced: with immediate ack the first ack edge carries
  wdata=0x1357, a second ack edge carries wdata=0xFF50, the
  port). The harness latches at the `io_req` rising edge.
  The pipeline must hold `io_wdata` stable while `io_req` is
  asserted.

## Audit discrepancy (to report to the audit owner)

Classifier vs C7 for the 100k window: total 297,024 vs 297,029
(delta -5). H2: the audit counts 3 map writes (+9 clocks) but
only 1 exists in the run (+3) -- audit overcounts by 6. H1b:
the audit counts 0 net (subsumed by H2) but the classifier
counts 1 (the genuine event, step 1521, pc 0x8088, op 0x7718,
dma 0x18, is NOT the H2 follower, so it is not subsumed).
Net -5. Documented, not a harness error.

## Follow-ups (once the pipeline lands)

- Longer ov6 run for steady-state CPI (\~1.0 target): re-derive
  from a run reaching ov6; the 100k gate is the acceptance bar,
  not the FIR target.
- Worker A landing needed for `retire_cycles_o` / stall
  counters / shadow outputs; then compile the `PIPE_OBS` path
  (`make cosim PIPE_OBS=1`) and re-run every gate above.
- RPTB blocks with control flow inside: coverage gap (directed
  h7-rptb uses branch-free blocks only).
- Directed tests for MMR AR-file read (0x10-0x17) and external
  dm read (>=0x80) on the pipeline.
- Directed test for direct TREG1/TREG2 writes once Worker A
  adds the write path.
- Directed test for SBRK (the random test generates ADRK under
  `PIPE_OBS` but not SBRK).
- `--desync-test` one-step entry offset: revisit as a pure
  phase-shift test once the pipeline lands (see the limitation
  note above).