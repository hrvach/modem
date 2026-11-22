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
|---|---|---|
| `lint` | `make lint` | `verilator --lint-only -Wall` on the top level (all real modules). Must be clean. |
| `sim-unit` | `make sim-unit` | Module testbenches in `tb/` (alu, addr, mem, decode). The ctrl FSM has no module testbench; the SV25 co-sim below is its proof. |
| `smoke` | `make smoke` | Harness on the hand-written 4-instruction program (`sim/smoke.hex`): LDP #0, LACK #0x34, SACL 0x60, LACK #0. |
| `cosim` | `make cosim` (or `STEPS=n make cosim`) | Firmware co-sim: SV25 base image, per-instruction compare (default 1000 instructions, `--verbose`). First mismatch stops with both states printed. |
| `dsp-smoke` | `make dsp-smoke` | DSP smoke gate (see below). Run before the full firmware co-sim. |
| `selftest` | `make selftest` | C-model-only determinism check (run twice, compare). |
| `reset-check` | `make reset-check` | Compare post-reset state C vs RTL, then exit. |
| `synth-cyclonev` | `make synth-cyclonev` | Yosys `synth_intel_alm -top c5x_core -family cyclonev` area check. `synth` is an alias; generic `synth` is NOT used. |

Direct harness use: `./cosim --firmware [N] [--verbose]
[--tolerate-cycles]`, `./cosim --smoke [N]`,
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

### Real-control-FSM protocol (step_i park, added 2026-11-19)

The control FSM parks in DONE while `step_i` is low (wired in
the top from the top-level input); tied high, DONE goes straight
to FETCH_ADDR and the path is cycle-identical. The harness still
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
- A 1M-cycle segment is ~6M RTL clocks (the control FSM takes
  ~6 clocks per 1-cycle instruction); the per-segment watchdog
  is 20M clocks.

## Current status (2026-11-19)

- `make lint`: **clean** (`verilator --lint-only -Wall`, top level
  + all real modules). All of agent 3's OPEN-1..OPEN-10 deltas
  are adapted in `rtl/c5x_core.sv` (see its header).
- `make reset-check`: **passes** (post-reset state matches:
  pc=0x8000 st0=0x0600 st1=0x07FC tim=0xFFFF).
- `make selftest 1000`: **passes** (C deterministic).
- `make smoke` (4 instructions): **passes** (MATCHED 4:
  LDP #0, LACK #0x34, SACL 0x60, LACK #0; final pc=0x8004
  cycles=5 io_events=0).
- Firmware co-sim: **10000 instructions matched**
  (`./cosim --firmware 10000 --verbose`, run 2026-11-19 after the
  CTRL-LOOP and CTRL-BCND ctrl fixes; final pc=0x8098 cycles=22799
  io_events=9). The run previously stopped at instruction 1535
  (tim C=0x4136 RTL=0x4138, cycles C=1638 RTL=1636 -- the 2-cycle
  BCND gap); it now passes 10000. Full AR file / stack and
  mem-owned registers compared per instruction.
- DSP smoke gate: **all 8 checkpoints pass** (`./cosim
  --dsp-smoke`, run 2026-11-19 after the CTRL-BCND fix:
  checkpoint 8/8 OK, pc=0x8097 acc=0x00000001 timer_expiries=476
  rtl_instr=3200881). Checkpoint 2 was failing on pc only
  (C=0x8097 RTL=0x8098) before the BCND fix; it now passes.
  Known VECTOR/C disagreements at every checkpoint (not
  failures): pc C=0x8097 vector=0x8098; total_cycles C=8000003
  vector=8000000 at checkpoint 8. **End-of-run recent_pcs ring
  still fails (16 fields)** -- but the RTL matches the C model
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
  + taken BCND 4) after the CTRL-BCND fix (open issue 8, FIXED).
- `make sim-unit`: **passes**. alu 1037 passed, 0 failed; addr
  313 checks ALL PASS; mem 168 passed, 0 failed; decode 66,726
  checks passed, 0 failed (plus a 1190-check random section).
  The decode testbench proves decode + cycle counts only; the
  ctrl FSM has no module testbench (the SV25 co-sim is its
  proof). Note: Verilator needs the package file listed BEFORE
  the files that import it (`c5x_ctl_pkg.sv` first), or the
  decode build fails with `%Error-PKGNODECL`.
- `make synth-cyclonev`: **BLOCKED** -- Yosys 0.33 cannot parse
  `import c5x_ctl_pkg::*;` (`c5x_decode.sv:90: ERROR: syntax
  error, unexpected TOK_PACKAGESEP, expecting '(' or '['`).
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
2. **CTRL-STBIT -- single-bit status ops hit the wrong flag.
   FIXED 2026-11-19.** Firmware instruction 3 (DINT 0xBE41): C sets
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
3. **KD-23 / OPEN-10 -- MADS/MADD TREG0 mirroring. FIXED
   2026-11-19.** The C model writes TREG0 directly for
   MADS/MADD (no `set_t0`, so no TRM mirror), but the ctrl
   loaded TREG0 with ALU `OP_LT`, and `OP_LT` mirrors
   TREG1/TREG2 from the new TREG0 value when TRM=0
   (`c5x_alu.sv` OP_LT case). Fixed: the ALU has `OP_LT_NM`
   (7'd64, `i_op` widened to 7 bits) and the ctrl issues it
   as a whole-body single issue in the WR phase, so TREG1/TREG2
   are untouched; the old loop phase 6 is deleted. (KD-24, the
   MADS/MADD loop-kind fix -- the old range test caught them as
   BLDD -- IS in the ctrl: `loop_kind_next` maps 0xAA/0xAB to
   kind 8; the co-sim will confirm it when a MADS/MADD
   executes.)
4. **TOP-EXTMMR -- external-MMR writes dropped. FIXED
   2026-11-19 (top level only).** Firmware instruction 14 (OPL
   #lk, 0x5D07, imm 0x00B0, to dm 0x0007 = PMST): pmst C=0x00B0
   (AVIS/OVLY/RAM set) RTL=0x0000. The mem routes PMST -- and
   IMR, IFR, RPTC, BRCR, PASR, PAER, TREG0-2, DBMR, AR0-7, INDX,
   ARCR, CBSR/CBER, BMAR -- to the external-MMR path
   (`mmr_is_ext_f`, `c5x_mem.sv`) and pulses `o_ext_mmr_wr`,
   but the top left `.o_ext_mmr_wr` / `.o_ext_mmr_wdata`
   unconnected (`c5x_core.sv`, u_mem instance) and the
   addr-unit write-port mux (`wr_port_*`) was fed only by the
   ctrl's strobes, so a DMEM write to an external MMR never
   reached its owner. The read path worked. Fix (RTL, top
   level): `o_ext_mmr_wr` / `o_ext_mmr_addr` / `o_ext_mmr_wdata`
   are connected and fed into the `wr_port` mux at top priority
   with an address-to-`WR_*` case-table decode (PMST -> WR_PMST,
   IMR -> WR_IMR, ..., AR0-7 -> WR_AR0+n); TREG0 is written
   through the ALU's treg load (one-cycle override: op OP_LT,
   b16 the write data, treg load on, TRM forced so the mirror
   does not fire, exec on). TREG1/TREG2 direct DMEM writes are
   still dropped -- the ALU can change TREG1/TREG2 only through
   the TREG0-load mirror, which also writes TREG0, so there is
   no top-level-only way to write them alone; that needs an ALU
   interface change. The firmware co-sim now passes instruction
   14 and matches 1000 instructions; the first 1000 do not
   write TREG1/TREG2 through DMEM (their per-instruction
   compare would have caught it).
5. **TOP-STATDP -- `stat_dp` wired to the wrong slice. FIXED
   2026-11-19 (top level, one line).** `c5x_core.sv`:
   `.stat_dp (addr_dp[8:0])`. The addr unit's `o_dp` is the
   full pre-shifted `dp_q` ({page[8:0], 7'b0}); the page is
   bits [15:7], as `o_st0` uses (`dp_q[15:7]`). Taking [8:0]
   returns the wrong value (DP=7 -> `stat_dp`=384). Every ALU
   instruction's TAIL C/OV writeback (OPEN-9) then writes the
   corrupted DP back into the addr unit via WR_ST0. Proven by
   a minimal test (LDP #7; LACK #0x34): st0 C=0x0607
   RTL=0x0780 (DP 7 vs 384). Blocked the DSP smoke gate at
   checkpoint 1 (st0 C=0x2607 RTL=0x2600; the smoke run's DP
   ends at 0 after a later LDP #0, but the corruption is the
   same mechanism). Fix: `.stat_dp (addr_dp[15:7])`. The
   smoke gate now passes checkpoint 1 and the minimal test
   matches (st0 0x0607 both sides).
6. **CTRL-LOOP -- loop engine unreachable for loop ops.
   FIXED 2026-11-19 (RTL, ctrl).** SETTLED (was open question a):
   the loop engine is actually dead, not just suspicious. FSM_LOOP
   is implemented (EA/RD/WAIT/PM/WR/NEXT phases) but never
   entered for loop opcodes: `needs_op_addr` excludes 0x09,
   0x57, 0x89, 0xA2-0xAD, so a loop op routes FETCH2->EXEC
   (never OP_DATA->LOOP), and FSM_EXEC has no branch to
   FSM_LOOP. Proven by a BLDD test (RPT #1; BLDD #0x70,0x60):
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
   TBLR / TBLW / MAC / MACD all need FSM_LOOP. Blocks any
   firmware run that reaches a loop op.
   Fix (2026-11-19, `rtl/c5x_ctrl.sv` only): `needs_op_addr`
   now includes 0x09, 0x57, 0x89, 0xA2-0xAD; `ea_mask_p0`
   extended with 0x89; the OP_ADDR ea_en pulse is suppressed
   for loop ops except SMMR/LMMR; OP_DATA latches the loop
   setup (`loop_a_q`, `alu_used_q` for MAC/MADS, the full
   16-bit rptc extra-cycle charge) and skips zero-iteration
   while-forms; the LOOP engine latches the per-iteration ea
   in phase EA. Two follow-on bugs found by the minimal tests
   and fixed in the same file: (a) the loop dm write was
   presented in the WR phase, but a pm_d read in PM is
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
7. **TOP-IN -- IN dm write suppressed. FIXED 2026-11-19
   (top level).** IN (0xAF) from a host-window port: the IO
   read worked (the IO event compares, the value is read),
   but the dm write never landed. Proven by a minimal test
   (SPLK #0x1234,0x60; IN 0x60,0xFF50): DMEM differs at
   0x0060, C=0x0000 RTL-shadow=0x1234. The IN dm write is
   presented combinationally only in the ack cycle while the
   top mux selects the IO branch whenever `ctrl_io_req_c` is
   high. Fix: the top captures the IN write at the
   acknowledge edge (`in_wr_capture`: io_req + io_ack + read
   + dm_req + dm_wr) and presents it to the memory in the
   next cycle, when the data channel is free (FSM in TICK),
   holding it until the memory acknowledges it. The mux keeps
   the IO port address in the acknowledge cycle itself so
   `io_ws_i` stays the port's wait states for the cycle
   charge. The same acknowledge-cycle fix drives the FSM's
   `mmr_wr_hit` from the IN target address, so an IN to a
   peripheral MMR (0x20-0x4F) gets the mmr_bus +1 cycle the C
   model charges (c5x_core.c:812-816). The minimal test now
   matches (DMEM 0x0060 0x0000 both sides, cycles=11).
8. **CTRL-BCND -- taken conditional branch undercharged by 2
   cycles. FIXED 2026-11-19 (RTL, ctrl; NOT a top-level bug.)**
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
9. **DSP smoke end-of-run recent_pcs ring: vector vs C
   disagreement, RTL matches C. (Vector / harness, NOT the ctrl.)**
   After the CTRL-BCND fix the gate passes all 8 checkpoints, but
   the end-of-run `recent_pcs[16]` comparison fails on all 16
   fields: the RTL matches the C model at every index, while the
   Python vector's ring is shifted by one entry (it reads 0x8098
   where C and RTL read 0x8097, and vice versa, at all 16 indices;
   the idle loop alternates 0x8097/0x8098, so a one-entry shift
   looks like a swap). The harness labels these `VECTOR/C
   disagreement`, like the pc / total_cycles disagreements at
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
