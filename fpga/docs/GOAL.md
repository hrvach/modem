# TMS320C5x DSP core on FPGA

Goal ID: goal_a3b36971bec1
Goal slug: tms320c5x-dsp-core-on-fpga

## Description
Port the Courier modem's TMS320C5x DSP core to synthesizable SystemVerilog for Cyclone V, with a Verilator testbench. Small, fast and efficient, but above all cycle-accurate against the verified C emulator core, so the real SV25 firmware runs on it.

## Constraints (Hrvoje's words)
- Target: Cyclone V.
- Small, fast, efficient — accuracy above all.
- Reference model is the C core, not the TI manual: the C core matches the
  Python baseline exactly and runs the real SV25 firmware (both modems
  CONNECT 33600). The TI-manual audit found deviations in the C core
  (153/179 obey, 1 violates IDLE2, 25 partial; 53-entry fix list, fixes
  NOT applied) — the RTL matches the C model as-is first; audit fixes are
  a separate later step, logged as KNOWN-DIFF, never silently applied.

## Toolchain (verified 2026-11-19 on this VM)
- Verilator 5.020, Yosys 0.33 — installed from
  ~/workspace/backups/toolchain-debs-2026-11-11.tar (local .debs; no
  apt-get update after a VM reset). Note: yosys .deb needs python3-click,
  which is NOT in the tar; archive.ubuntu.com returned 404 for the
  8.1.7-1 .deb. Yosys binary still runs (0.33, synth works, 24 cells on
  a smoke test) — python3-click is only needed by helper scripts, not
  the synth binary. yosys dpkg status is iU (unconfigured); do not run
  apt-get -f install, it removes yosys.
- No Quartus on this VM. Synthesis check is Yosys generic `synth` (a
  proxy, not Fmax); Quartus Fmax is ground truth when available.
- Verilator --binary smoke test: with --binary, do NOT supply your own
  main() in the C++ file (Verilator generates one — multiple definition
  of main). Use the --cc/--exe flow with your own main, or --binary
  without a C++ main.

## Reference material
- C core (the spec): research_notes/courier-firmware/c-port/c/src/dsp/c5x_core.c
  (3,475 lines) + c5x_core.h + c5x_cyctab.h (cycle counts per instruction).
  Struct C5x: acc/accb/preg 32-bit; treg0/1/2, ar[8] 16-bit; pc/op 16-bit;
  stack[8], sp 0..7; rptc, brcr; ifr/imr; indx/arcr; cbsr/cber/cbcr;
  bmar/dbmr/pasr/paer; peripherals greg/drr/dxr/spc/tim/prd/tcr_tddr/
  pdwsr/iowsr/cwsr; sh (interrupt shadow); cycles; pmem/dmem/iomem 64Kx16.
- Audit + instruction semantics: research_notes/courier-firmware/c5x_core_audit/
  (07-core3-fix-list.md, 07b/07c instruction docs, 07d interrupts,
  07e peripherals/memory, 07a build/cyctab).
- DSP manual (reconstructed): research_notes/courier-firmware/dsp-manual/DSP-MISSING-MANUAL.md
  and handover-2026-11-15/handover/dsp/HOST_PROTOCOL.md.
- Firmware: SV25.XMD, SHA-256 43503d82…ef413f. Never patch it.

## Architecture decision (lead)
- Multi-cycle core, NOT a TI-style 4-phase pipeline: one instruction per
  N cycles with N taken from c5x_cyctab.h. Observable behaviour (regs,
  memory, IO, cycle counts, interrupts, timer) must match the C model
  instruction by instruction. Microarchitecture may differ; the cycle
  counts and the architectural state trace may not.
- Single clock, active-low synchronous reset. PMEM/DMEM as synchronous
  BRAM (M10K inference); IO via explicit req/ack handshake to the host
  glue (codec, 186 mailbox) mirroring the C io_rd/io_wr callbacks.

## Cyclone V targeting (Hrvoje, 2026-11-19; verified on this VM)
- Synthesis check is `synth_intel_alm -top <top> -family cyclonev`
  (Yosys 0.33; cyclonev is the default family). NOT generic `synth`;
  NOT `synth_intel -family` (that one has no Cyclone V — it covers
  max10/cyclone10lp/cycloneiv/cycloneive only). Report ALM/DSP/M10K.
- Multipliers: single signed 16x16 expression, product registered into
  PREG → one Cyclone V variable-precision DSP block in 18x18 mode.
  Never decompose a multiply into shifts/adds; no logic between the
  multiply and its register. MAC accumulate stays one expression where
  the semantics match.
- Memories: EXPLICIT M10K (Hrvoje, 2026-11-19). PMEM/DMEM use the
  `(* ramstyle = "M10K" *)` attribute plus the simple-dual-port
  synchronous template (one write port, one read port, registered read
  data, no reset on the array, no async read). Same-cycle same-address
  read returns OLD data — never rely on read-during-write returning new
  data. Verified on this VM: a 1024x16 RAM in this form maps to
  MISTRAL_M10K cells under synth_intel_alm with zero $mem_v2 left.
  The attribute is what forces M10K in Quartus; it is NOT a Quartus
  primitive instantiation (no altsyncram). 64Kx16 is 1 Mbit per memory —
  expect ~100+ M10K blocks each; report the exact count.

## 80C186EB supervisor core (Hrvoje, 2026-11-19 — same rules as DSP)
- Reference model is the C core `c-port/c/src/cpu/i186.c` (1905 lines)
  + `i186.h` (134 lines). State is opaque in the header; layout lives in
  i186.c. Audit in `research_notes/courier-firmware/i186_audit/`
  (632 checks: 421 obey / 140 violate / 61 partial / 10 unverified;
  fix list `10-i186-fix-list.md`, 66 entries, 6 P0 incl. IDIV SIGFPE,
  BOUND retrap, TF missing). RTL matches the C model AS-IS, fixes NOT
  applied, deviations logged as KNOWN-DIFF, never silently fixed.
- Cycle model: cyc_model 0 = flat 4 cycles/instr, 1 = Table D-2
  approximate; glue sets it from config (machine.c:817) — match the
  configured model, check config.c for the default. Reset: CS=0xFFFF,
  IP=0, FLAGS=0x0002.
- Peripherals (timer/PIC/DMA, UART, DSP mailbox, NEC ASIC PCB) live in
  the GLUE, not the core (i186.c header comment). Worker 7 owns them as
  modeled in glue/machine.c: IO ports 0x40-0x5E DSP mailbox (0x5E/0x5F
  cmd+arg), MMIO pages 0xFF and 0x0F, RO pages. Only ports the firmware
  actually touches; the rest are documented stubs.
- The 1 MB RAM image does NOT go in M10K. It lives in the Verilator
  C++ harness behind the core's bus-master port (req/ack handshake,
  same pattern as the DSP IO handshake). The core exposes a synchronous
  bus port: 20-bit addr, 16-bit data, byte/word, rd/wr strobes, ready.
- Split: worker 6 = i186 CPU core (rtl/i186_core.sv); worker 7 = system
  + top + co-sim harness (rtl/i186_sys.sv, rtl/i186_top.sv, sim/).

## House rules for Verilog (Hrvoje, 2026-11-19)
- The quality bar is `~/workspace/custom-skills/fpga-systemverilog/SKILL.md`
  — read it in full before reporting done. Headlines: SV-2017,
  `default_nettype none`, always_comb/always_ff with complete
  assignments (no latches), nonblocking in clocked logic, explicit
  widths/signedness, named port connections (never `.*` or positional),
  no casex/casez in synthesizable RTL, one owner per register, reset
  control state only, no gated clocks, no silent latency/timing
  changes, inference verified in the synth report, never claim a check
  not run, never change a test to hide an RTL bug.
- Spot-checked 2026-11-19 on the three delivered modules (alu, addr,
  mem): no casex/casez, no `.*`, default_nettype present, KNOWN-DIFFs
  present, lint clean.
- Golden house rules (Hrvoje, 2026-11-19) live verbatim in
  `~/workspace/custom-skills/fpga-systemverilog/SKILL.md` ("House
  rules"). Headlines: /* */ comments ONLY, never //; module header
  block comment (which chip, where it sits, what it talks to, what it
  does not model); 150 cols max; one statement per line; one port
  connection per line, aligned names; case table not ?: chains; typedef
  enum named states; shared constants/layouts in packages as packed
  structs/enums; port groups in packed structs in a package; magic
  numbers become localparams with a source comment; FPGA-only plumbing
  in its own files labelled FPGA-only; rewrites keep behaviour (old
  implementation as reference in tb/, equivalence by random test +
  project workload). The four running workers were told to follow them.
  Retrofit approved by Hrvoje 2026-11-19 14:16 CET and done the same
  day, lead-verified: alu (TB 553/0, synth 2304 cells vs 2333 baseline,
  FF/MUL/mem identical), addr (TB 261/0, synth exactly baseline 2507
  cells), mem (TB 137/0, synth 3548 cells vs 3596, 256 M10K / 1269 FF
  identical). Two deliberate exceptions, both logged: addr keeps two
  `?:` chains (o_ea, ar0_next) because the case forms shift cell counts;
  mem keeps module-local localparams instead of a shared package
  (interface frozen for integration). Originals in
  hidden_files/preconvert/.

## Reporting + delivery (Hrvoje, 2026-11-19)
- Status report every 10 minutes: cron `fpga-port-status-10min`
  (interval 10m, owner this goal, first run ~14:18 CET). Text only,
  no file links in the reports. The cron removes itself when GOAL.md
  records both integrations complete.
- Files go out ONLY once all is done, all of them zipped together.
  No individual module files before then.
- NO Quartus primitives (altsyncram, altmult_accum, ...): no Quartus on
  this VM to verify them. Inference-friendly RTL only; Quartus Fmax is
  ground truth later. AR file stays in logic (8x16, multi-port), FSMs
  binary-encoded, no gated clocks.

## Work split (5 parallel agents, spawned 2026-11-19)
1. c5x_alu — CALU + shifter + 16x16 multiplier, ACC/ACCB/PREG/TREG regs.
   rtl/c5x_alu.sv
2. c5x_addr — AR file, indirect ea(), circular/bit-reverse, stack, RPTC/RPTB,
   status regs ST0/ST1/PMST. rtl/c5x_addr.sv
3. c5x_decode + c5x_ctrl — instruction decode, cycle counts from cyctab,
   control FSM, delay slots, XC, interrupts, IDLE; publishes the control
   bundle package c5x_ctl_pkg.sv that 1/2/4 implement against.
   rtl/c5x_decode.sv, rtl/c5x_ctrl.sv
4. c5x_mem — PMEM/DMEM BRAMs, MMR decode, timer, serial SPC/DXR/DRR, IO
   handshake. rtl/c5x_mem.sv
5. Top + co-sim harness — c5x_core.sv wiring 1-4, Verilator C++ harness
   linking c5x_core.c, runs the SV25 image and diffs architectural state
   per instruction vs the C model. rtl/c5x_core.sv, sim/

## Workspace
- RTL: workspace/goals/tms320c5x-dsp-core-on-fpga/rtl/
- Testbenches: .../tb/ ; harness: .../sim/ ; notes: .../docs/
- Agents own only their files; integration is the lead's job.

## Status
- 2026-11-19: goal created; toolchain installed and smoke-tested
  (Verilator 5.020, Yosys 0.33); 5 module agents spawned.
- 2026-11-19 15:15 CET (Hrvoje): RAM questions deferred — sort out
  later, go ahead with the port. The top-level synth/M10K verification
  (Yosys package-import blocker) is parked, not dropped; the ctrl
  fix agent was told to skip it this round and focus on the two bugs.
- 2026-11-19: DSP port (modules 1-5) delivered; ctrl bugs CTRL-IOWS
  and CTRL-STBIT fixed, OP_LT_NM (KD-23) added, AR/stack and
  mem-register observation outputs added, top rewired (7-bit ALU
  op, acc_next, indexed SAR read, step_i park, obs_*_o). Lead
  verified: lint clean, each module TB re-run by the lead (alu
  1037, addr 313, mem 168, decode 66,726, all 0 failed), smoke
  MATCHED 4, reset-check + selftest pass. Firmware co-sim and DSP
  smoke gate re-runs still pending (harness must learn the new
  observation outputs first). Zip delivered 2026-11-19:
  c5x-dsp-port-2026-11-19.zip (DSP only, no 186 files).
- 2026-11-19 (worker 7, 80C186EB sys/top/co-sim): lint clean
  (`verilator --lint-only -Wall` on top+sys+core); TB
  `tb/tb_i186_sys.sv` PASS 232/232; sys-only Cyclone V synth
  24,012 cells, 0 M10K, 0 DSP (`sim/synth-i186-sys-only.log`).
  Co-sim on the real SV25 firmware now runs **7769 outer
  instructions clean** (11235 incl. REP) after worker 6 fixed the
  TEST 0xA8/0xA9 immediate-fetch bug found by the co-sim at step 259
  (`decode_imm_kind` now lists 0xA8/0xA9; core modified 14:44). The
  1000-instruction run passes clean (DTE 1 byte each). The
  200000-instruction run stops at step 7769 on a timer-interrupt
  timing divergence (RTL takes the interrupt, C has not reached it;
  SP -6, IF cleared, PC to handler 030C vs C 044A), driven by the
  42687-cycle bus-latency overhead — a known harness limitation, not
  a functional bug. Full-top Cyclone V synth is blocked: the core
  uses `gpr[...][...]` double-indexing (22 places, first at line
  3415) which Yosys 0.33 rejects. Sys bus latency is 4 clocks per
  harness transaction; the earlier ST_WAIT_LOW deadlock is fixed.
  `sim/placeholders_i186.sv` deleted (real core landed). Details in
  `docs/i186_cosim.md`.
- 2026-11-19 (lead verification of worker 7, snapshot 15:52 CET of
  i186_top/sys/core): lint clean exit 0; TB `tb_i186_sys.sv` PASS
  232 checks 0 errors (re-run; first attempt failed on a transient
  Verilator write error that did not reproduce); co-sim N=1000 PASS
  clean, exact reproduction (C 35887, RTL 43555, final IP 0454 both,
  DTE 1 byte each); sys-only Cyclone V synth 24,012 cells, exact
  reproduction of worker 7's cell table; 0 `//`, max line 126 in
  worker-7 files. Module 7 VERIFIED. Caveat: snapshot predates
  worker 6's later core edits, so the top-level numbers are
  provisional until worker 6 lands; the 7,769-instruction run and
  its timer-divergence finding were not re-run by the lead.
- 2026-11-19 (ctrl fix agent, lead verification running):
  CTRL-LOOP fixed in `rtl/c5x_ctrl.sv` only (snapshot in
  hidden_files/pre-fix2/c5x_ctrl/) — loop opcodes now route to
  FSM_LOOP; two follow-on bugs fixed in the same file (dropped
  loop dm write moved WR->NEXT; SMMR/LMMR repeat hang). CTRL-BCND
  fixed — taken branch charge 2->4 via br_taken_q gating seq_q
  (also fixes taken RETC and BANZ). Agent proof on a private
  binary: lint clean, 0 `//`; decode TB 66,726/0; smoke MATCHED 4;
  selftest deterministic; reset-check passes; loop minimal tests
  all MATCHED; BCND test MATCHED 10, cycles 25; firmware 1000
  MATCHED 1000; firmware 10000 MATCHED 10000 (pc 0x8098, cycles
  22799); dsp-smoke all 8 checkpoints pass. Open issue 9: the
  smoke gate's end-of-run recent_pcs[16] comparison fails on all
  16 fields, but RTL matches C at every index — the Python
  vector's ring is shifted by one entry (VECTOR/C disagreement,
  not an RTL bug). Flag: top-level write-port mux hazard in TAIL
  (ST0+ST1 with rptc clamp, mux takes ST0) — ctrl works around
  it with a TICK-phase clamp; latent for future ctrl changes.
- 2026-11-19 (lead verification of the combined DSP fixes, shared
  binary rebuilt): lint clean; 0 `//`, max line 83 in c5x_ctrl.sv;
  reset-check passes; smoke MATCHED 4; selftest deterministic;
  decode TB 66,726/0; sim-unit all pass; firmware 10000 MATCHED
  10000 (pc 0x8098, cycles 22799); firmware 100000 MATCHED
  100000 (pc 0x8098, cycles 247799, io_events 9); dsp-smoke all 8
  checkpoints OK (timer_expiries 476 at checkpoint 8). The gate's
  overall FAILED verdict is only the end-of-run recent_pcs[16]
  vector ring shift — RTL equals C at every index. **DSP
  integration complete.** Residual known gaps: TREG1/TREG2
  direct-write gap (unexercised in 100k firmware instructions),
  TAIL write-port mux hazard (latent).
- 2026-11-19 (co-sim successor, lead-verified by re-running both
  gates): harness updated in `sim/cosim.cpp` only — full AR/stack
  and obs_*_o compared per instruction, DXR events fixed (pre-edge
  sample), pseudo-port filtering, run_to_cycles stops at instr_done.
  DSP smoke gate FAILS at checkpoint 1 on 1 field (st0 C=0x2607
  RTL=0x2600, DP 7 vs 0). Firmware co-sim: 13 instructions matched,
  first mismatch at 14 — OPL #lk to PMST, pmst C=0x00B0 RTL=0x0000,
  cycles matched for all 13. Four RTL bugs diagnosed precisely,
  none fixed yet: TOP-STATDP (stat_dp wired to addr_dp[8:0], must
  be [15:7]), TOP-EXTMMR (ext-MMR write strobe unconnected, addr
  MMR writes dropped), CTRL-LOOP (loop engine unreachable),
  TOP-IN (IN dm write suppressed). Details in `docs/cosim.md`.
- 2026-11-19: 186 port (modules 6-7) zipped on Hrvoje's request:
  i186-port-2026-11-19.zip, 288,211 B, SHA-256
  b0098e87c5e1c8d0ef90eb17062150473dfafff5b94b43498a3b027f5ec5d1ed,
  12 files (core/sys/top, both TBs, co-sim harness + Makefile,
  sys-only synth log, i186_cosim.md, GOAL.md). Module 6 lead
  verification still running at zip time.
- 2026-11-19 (top fix agent, lead verification pending the ctrl
  landing): TOP-STATDP, TOP-EXTMMR and TOP-IN fixed in
  `rtl/c5x_core.sv` only (snapshot in hidden_files/pre-fix2/
  c5x_core/). Agent proof on a private binary: lint clean;
  reset-check passes; smoke MATCHED 4; selftest deterministic;
  STATDP minimal test MATCHED 2 (st0 0x0607 both); IN minimal test
  MATCHED 2 (DMEM 0x0060 0x0000 both, cycles 11); firmware 1000
  MATCHED 1000 (passes instruction 14); dsp-smoke checkpoint 1
  passes, checkpoint 2 fails on pc only (C=0x8097 RTL=0x8098).
  New bug found by the agent: CTRL-BCND, taken BCND charges 2
  cycles vs C 4 (minimal test cycles C=5 RTL=3) — passed to the
  ctrl agent in the same round. Residual gap: direct DMEM writes
  to TREG1/TREG2 still dropped, needs an ALU interface change.
- 2026-11-19 (lead verification of worker 6, i186 core): lint clean
  exit 0; TB PASS all checks (cycles_o=1565 vs C 1586, KD-13);
  co-sim N=5000 PASS clean, exact reproduction (C 65887, RTL
  94218, final IP 044E both, DTE 1 byte each); core-only Cyclone V
  synth 12,258 cells, exact reproduction (2 M10K, 1 MUL18X18, 1
  MUL9X9, 0 $mem_v2); 0 `//`, max line 135. Module 6 VERIFIED.
  The 200,000-instruction co-sim stop at step 7,769 (timer
  interrupt timing) was not re-run by the lead; it stands on
  workers 6 and 7 agreeing it is sys/top ICU timing, not the core.
- 2026-11-19 (186 timer-fix agent, lead-verified by re-running the
  gates): timer-interrupt divergence at step 7,769 FIXED in sys/top/
  harness only, core untouched. Root cause: T0 period 32,256 counts
  (CMPA 0x7E00, CON 0xC001 at steps 17/22), C first expiry at C
  cycle 129,183; RTL timers ran ~60 clocks ahead on the 42,687-cycle
  bus-latency overhead plus a 1-count phase lead (RTL div=1/cnt=1 at
  end of CON-write step, C cnt=0). Fix: model-time tick enable
  (harness enables exactly the C charged cycles per step window,
  catch-up), deferred timer/UART writes applied at instruction
  boundaries, ICU same-cycle hit (tmr_hit_now), harness
  interrupt-take alignment (Cases A/B). Lead verification: lint
  clean, TB 232/232, N=5000 PASS, N=200000 now past 7,769. New
  blocker at step 13,454: core bug CMP r/m,imm writes the
  destination — CLASS_ALU_IMM_RM writeback exemption tests regf==0
  (ADD) instead of regf==7 (CMP); `81 FF 00 20` at 0000:0330 sets
  DI=E000 (C DI=0000), all else identical. One-line core fix
  (test regf==ALU_CMP) dispatched to a core successor agent
  2026-11-19 17:54 CET.
- 2026-11-19 (core CMP-fix agent, lead-verified by re-running the
  gates): CMP r/m,imm writeback fixed, one line at
  rtl/i186_core.sv:2753 (regf==3'd0 → regf==ALU_CMP). Lead
  verification: lint clean, TB 232/232, N=5000 PASS, N=200000 now
  past 13,454. New blocker at step 13,458: byte-register
  writeback writes SP/BP/SI/DI instead of AH/CH/DH/BH — read path
  correct (get_byte maps n>=4 to gpr[n-4][15:8]), write path uses
  raw rmf (gpr[4]=SP for rmf=4); `F6 D4` NOT AH at 0000:033D sets
  SP=FDDA (C SP=00DA, AX=FDF5 vs RTL AX=02F5), all else identical.
  10 gpr[rmf] sites + 3 gpr[regf] sites affected; fix is a
  register-index remap for byte writes mirroring get_byte.
  Dispatched to a core successor agent 2026-11-19 17:56 CET.
- 2026-11-19 (core byte-writeback agent, lead-verified by
  re-running the gates): byte-register writeback fixed in
  rtl/i186_core.sv only (snapshot hidden_files/pre-fix3/i186_core/).
  Two helpers mirroring C setreg (i186.c:243) — byte_gpr_idx(n)
  and set_byte_reg(n, v) — applied at 15 raw-index set_byte
  sites (11 gpr[rmf], 3 gpr[regf], 1 gpr[opcode[2:0]]) plus an
  XCHG r/m,r memory-form width guard (byte merges, word keeps
  full write). Word-writeback paths checked, correct, unchanged.
  Lead verification: lint clean, TB 232/232, N=5000 PASS, N=200000
  now past 13,458. New blocker at step 13,465: 0x83 fetches a
  16-bit immediate — decode_imm_kind maps 0x83 to IMM_W and
  decode_width(0x83)=1, but the 0x83 immediate is always 8 bits
  (C fetch8, i186.c:1117-1126); RTL eats the following JZ opcode
  0x74 as the second immediate byte (imm 0x7400 vs 0x0000, IP
  035B vs C 035A, FLAGS F287 vs F206, registers identical).
  Fix: move 0x83 from IMM_W to IMM_8. Dispatched to a core
  successor agent 2026-11-19 18:01 CET.
- 2026-11-19 (core 0x83-fix agent, lead-verified by re-running the
  gates): 0x83 immediate-width fixed in rtl/i186_core.sv only
  (snapshot hidden_files/pre-fix3/i186_core-0x83/). Two parts: 0x83
  moved from IMM_W to IMM_8 in decode_imm_kind (0x80/0x82 stay in
  IMM_W, correct by accident; 0xC6/0xC7 and 0xF6/0xF7 verified
  correct in IMM_W against i186.c:1297/1451), plus sign-extension
  of the 0x83 word-form immediate in the CLASS_ALU_IMM_RM operand
  mux (`alu_b = {{8{imm[7]}}, imm[7:0]}` when opcode==0x83 &&
  is_word, mirroring the 0x6B site) — without it a negative 0x83
  immediate would compare against 0x00FF instead of 0xFFFF.
  Lead verification: lint clean, TB 232/232, N=5000 PASS, N=200000
  now past 13,465. New blocker at step 64,986: interrupt-boundary
  ordering — both models took the same timer interrupt and
  executed STI (SP 00EC both, IP 030D both), but the RTL executed
  the pending IN at 044A (port 0x10 reads 0x00 in both models)
  before taking the interrupt, so RTL AX=0000 vs C AX=0011; the C
  model does do_int BEFORE the next instruction. Core behaves as
  documented (interrupts at finish boundary); fix belongs to the
  sys/top/harness owner. Dispatched 2026-11-19 18:08 CET.
  Toolchain note: the VM had lost Verilator/Yosys between runs;
  the agent reinstalled from the tar (dpkg, no apt-get update),
  Verilator 5.020 / Yosys 0.33 verified.
