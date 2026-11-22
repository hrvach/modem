# Pipelined TMS320C5x DSP core — CONVERGED design plan (all three agents)

Status: PLAN ONLY. No RTL, testbench, or sim file was changed. This is
the single converged plan from the three-agent review (Agent 1 = lead
designer/proposer; Agent 2 = independent consultant; Agent 3 =
adversarial critic), written 2026-11-20.

Convergence history: base text is Agent 2's Revision 2 plan (R2), which
Agent 1's finalised plan (`hidden_files/pipeline-plan-agent1.md`,
73,858 bytes) agreed with on every point. Agent 3 verified R2 + Agent
1's two clarifications in Part 4 of its critique
(`hidden_files/pipeline-plan-agent3-critique.md`): B1, B4, B6, C1–C12
and both clarifications RESOLVED; B2, B3, B5 PARTIALLY RESOLVED with
three precise fixes. This document is R2 plus Agent 1's two
clarifications plus Agent 3's three fixes plus the branch-cost
correction and the B1 long-run note. Every addition is marked
[CONVERGED]. Nothing in it reintroduces a rejected position
(model-cycle timer, retirement-detected RPTB, R-stage AR sources,
precomputed AR values, TI conflict outcomes, Yosys Fmax claims).

Sign-off: Agent 1 signs this converged document. Agent 2 is confirming
the same three fixes in parallel. Agent 3 verifies this document next;
agreement is complete when all three have signed it.

## Revision 2 — response to Agent 3's critique (2026-11-20)

Agent 3's critique (`hidden_files/pipeline-plan-agent3-critique.md`)
was answered objection by objection against the C model
(`c5x_core.c`) and the TI manual. Verdicts: **all six blocking
objections ACCEPTED** (B1–B6), none contested; all twelve concerns
C1–C12 accepted where they affect the plan. The revisions below are
marked [R2]. Two additions go beyond the critique and are flagged as
such: the two-mechanism repeat analysis (R2-§5) and the
interrupt-aware co-sim comparison (R2-§9) — both are direct
consequences of B1's resolution, verified in the C source, not new
disagreements. Agent 1's plan has not been seen yet; this position
signs the converged plan provided it incorporates these resolutions
and does not reintroduce the rejected positions (model-cycle timer,
retirement-detected RPTB, R-stage AR sources, precomputed AR values,
TI conflict outcomes, Yosys Fmax claims).

## Sources (all read)

- Goal: `~/workspace/goals/tms320c5x-dsp-core-on-fpga/GOAL.md`
- House rules: `~/workspace/custom-skills/fpga-systemverilog/SKILL.md`
  (golden rules, 2026-11-19 — still binding)
- TI manual: `~/workspace/user/files/spru056d.pdf` (SPRU056D, June 1998),
  Figure 2-1 (PDF p.44), Figure 3-1 (PDF p.47), Chapter 7 pipeline
  (PDF pp.443-467); distilled in
  `~/workspace/research_notes/courier-firmware/c5x_manual/02-architectural-overview.md`
  and `07-pipeline.md`
- C model (the correctness spec):
  `~/workspace/research_notes/courier-firmware/c-port/c/src/dsp/c5x_core.c`
  (3,475 lines) + `c5x_cyctab.h` (64K-entry cycle table)
- Current RTL: `rtl/c5x_alu.sv`, `c5x_addr.sv`, `c5x_decode.sv`,
  `c5x_ctrl.sv`, `c5x_ctl_pkg.sv`, `c5x_mem.sv`, `c5x_core.sv`
  (multi-cycle, verified: firmware co-sim 100,000 matched, smoke 8/8)
- Current harness: `sim/cosim.cpp`, `sim/c_ref.c`
- Snapshot of the multi-cycle core (reference):
  `hidden_files/pre-pipeline/` (rtl, sim, tb, cosim.md)

## 0. Goal numbers

- Throughput: 1 instruction retired per clock in steady state.
  Target CPI ~1.0 on the SV25 firmware mix; measured CPI and a stall
  breakdown are deliverables, not a single assumed number.
- Clock: 40 MHz on Cyclone V (25 ns). Yosys 0.33 `synth_intel_alm`
  cannot prove Fmax; the plan claims timing only from stage-local
  combinational depth, and Quartus Fmax is ground truth later.
- Correctness: architectural state matches the C model at every
  instruction retirement. The C model is sequential; TI's hardware
  pipeline is not interlocked. Where they differ, the design stalls
  (interlocks) — it never reproduces TI's conflict outcome.
- Baseline to beat: multi-cycle core, 100,000 instr / 247,799 model
  cycles, ~2.48 cycles/instr, ~16 MIPS at 40 MHz.

## 1. Design thesis

Imitate TI's Figure 3-1 blocks and Chapter 7's four-phase pipeline
(F/D/R/E), not a generic 5-stage RISC pipeline. Keep the existing
modules as the stage datapaths (decode = D, ALU = E, address unit =
D + E commit, memories = F/R/E ports). [R2: the thesis in Revision 1
understated the change (C6). The new/redesigned pieces are: the
pipeline-control unit (hazard detection, stall, flush, retire)
replacing the multi-cycle FSM; the address unit split into D-part and
E-part; the memory block's timer (wall-clock tick), deferred IO reads,
store-to-load bypass, and PMEM arbitration; the top rewire with the
program controller (fetch redirect, interrupt entry); the TREG1/TREG2
explicit write port; and the retire-based, interrupt-aware co-sim
harness. That is the real scope.]

Decouple wall clocks from model cycles — with the correction in [R2]:
the pipeline retires 1 instr/clock; a model-cycle counter advances by
the C-model cycle count at each retirement, and that counter is
**verification bookkeeping only**. The timer is a real-time device and
is driven from the WALL clock (see §7, B1 resolution), not from model
cycles. The serial tick is a host event, unchanged (see §7; this
governs — Revision 1 §1's "timer/serial timing runs off model cycles"
was wrong, C10).

## 2. Pipeline structure and stage boundaries

Four stages, one instruction per stage per clock, in-order retire.

| Stage | Work (one clock) | Owner module |
|---|---|---|
| F | Fetch one instruction word from PMEM (M10K sync read, registered output). PC advances; PC value carried in the F/D pipeline register. | c5x_mem PMEM port, program controller in top |
| D | Decode (combinational, existing c5x_decode). Address generation: ARAU computes the effective address from AR/INDX/ARCR and the addressing mode; the NEW AR value is computed but NOT committed. Two-word instructions: second word fetched in F, D is a dummy (TI Ch.7 §7.2.1). | c5x_decode, c5x_addr (ARAU part) |
| R | Read the data operand from DMEM (M10K sync read) at the address computed in D. The address is carried in the D/R pipeline register — R never re-reads the AR file. | c5x_mem DMEM port |
| E | Execute (CALU/PLU) and commit: write ACC/PREG/TREG/ARs/flags/stack, write DMEM, write MMRs. Retire: pulse `instr_done`, advance the model-cycle counter, present the timer tick. | c5x_alu, c5x_addr (commit part), c5x_mem write ports |

Pipeline registers (packed structs in `c5x_ctl_pkg.sv`, per the house
rules): F/D carries pc + raw word + word2-valid; D/R carries pc,
decoded micro-op bundle, effective address, AR-update descriptor,
immediate; R/E carries pc, micro-op bundle, operand value, effective
address, AR-update descriptor.

Rules that follow from the structure:

- **D is speculative; only E commits architectural state.** AR updates,
  flag writes, register writes, memory writes, and IO accesses happen
  in E or not at all. This is what makes branch/interrupt flushes
  correct: a flushed instruction in F/D/R has changed nothing, so
  there is nothing to roll back. (TI's D-phase AR update is real
  hardware behaviour; ours is computed in D and committed in E. The
  observable effect is identical for code the C model executes, and
  it is the only way flushes can be correct against a sequential
  reference model.)
- **The effective address is computed once, in D, and carried forward.**
  This reproduces TI's "R reads the location pointed at by the AR
  before the D-phase update" rule (Ch.7 §7.2.1, Ex. 7-1) by
  construction, without re-reading the AR file in R: the address R
  uses is the one D computed from the pre-update pointer. The exact
  order of `ea()` vs `upd_ar()` per instruction class must be taken
  from `c5x_core.c` (`ea()` line 1119, `upd_ar()` line 1085) during
  implementation — the D stage must produce exactly the address the
  C model uses, including circular-buffer and bit-reversed modes.
- **The AR file has exactly one writer: E.** D computes the update,
  E applies it. No D/E write-write hazard on the AR file exists by
  construction. The AR file stays in logic (8x16 flops, combinational
  read), as today.
- **Back-to-back ALU dependencies need no forwarding.** E of
  instruction N+1 is one clock after E of instruction N; N's ACC/PREG/
  TREG/flag write lands at the clock edge and is visible to N+1's E
  combinationally from the flops. Same for the multiplier (PREG is a
  register; MPY then APAC/PAC is safe). This holds only because E is
  the last stage and all consumers read in E. Any consumer that reads
  a result in an earlier stage is a hazard (see §4).

## 3. Memory ports and structural hazards

PMEM and DMEM are separate M10K arrays (simple dual port: one sync
read port, one write port, registered read data, same-cycle same-address
read returns OLD data). Per-clock port use in steady state:

| Array | Read port user | Write port user |
|---|---|---|
| PMEM | F (instruction fetch) | Firmware loader (quiescent while running) **and E (TBLW)** — [R2, C3] the PMEM write port is muxed between the loader and E. TBLW writes program memory in E. Self-modifying-code corner: when a TBLW retires, flush F/D/R and re-fetch from PC — the fetch stream may already have fetched the modified word, and the C model (sequential) reads the new value. Cost: rare. |
| DMEM | R (operand read) | E (operand store) |

Structural hazards and their handling (all are stalls of the front
end, never a wrong result):

- **PMEM-operand instructions** (TBLR, BLDP, MACD/MADD with a PMEM
  operand, any instruction reading program memory as data): the data
  read needs the PMEM read port in R while F needs it for fetch.
  Stall F for one clock (PC held, F/D register gets a bubble) while
  R uses the port. The C-model cycle count for these instructions
  already exceeds the base; the stall is the wall-clock counterpart.
- **Two data accesses in one instruction**: none in the C5x needs two
  reads from the SAME array in the same phase (MACD reads PMEM in R
  and DMEM in R — different arrays, both ports free in R; its DMOV
  write lands in E). Required before RTL: a per-opcode port audit
  from the decode table + C model listing (PMEM reads, DMEM reads,
  DMEM writes) per phase; any same-array double access found there
  gets a one-clock stall of the later phase. [R2, C12: if both accesses
  fall in the SAME phase (both in R), there is no later phase — the
  mechanism is an R-stage replay: the instruction takes a second R
  cycle (R holds, front end stalls one clock), i.e. the phase splits
  into R1/R2 for that instruction. The audit's terms of reference
  must state this.]
- **Store-to-load, same DMEM address, same clock**: E writes DMEM at
  address A while R reads DMEM at address A (different instructions).
  R would read OLD data; the C model (sequential) requires the NEW
  data. Forward E's write data to R through a bypass mux (16-bit,
  address compare), do not stall. This is the only data forwarding
  path in the design and it is cheap.
- **[R2, C1 — replaces the Revision 1 "E reads DMEM" bullet, which was
  impossible: a synchronous M10K read presents the address in one
  clock and the data at the next edge, so E cannot use the data in the
  same clock.] Deferred IO reads, per-target latency:** the deferred
  targets (DRR 0x20, MMRs) are flops and are combinationally readable
  in E — no BRAM port is involved. Host IO window 0xFF50–0xFF5F goes
  through the host handshake and stalls E (H8). DMEM reads have no
  side effects in the C model (`dm_rd` is pure outside the MMRs), so
  they stay in R; **E never needs the DMEM BRAM read port**, and the
  "E-reads-DMEM stalls R one clock" bullet is deleted.
- **RPT replay**: the repeated instruction re-executes from R/E (see
  §5); the front end is stalled while it replays, so no port
  contention arises from replay.

## 4. Hazard and interlock policy

Interlocks are stalls of the front end (F/D/R hold, bubble inserted
downstream). The stall condition is computed combinationally from the
pipeline registers each clock. Forwarding exists only where §3 names
it (store-to-load DMEM bypass). Everything else stalls. Rationale:
stalls are provably correct against the sequential C model; forwarding
is used only where the forwarded value is provably the sequential
value.

[R2, B4 — the Revision 1 stage pairing was wrong and is replaced in
full. The error: a younger instruction's D is one cycle BEFORE the
older instruction's E, so comparing "E-stage write target vs D-stage
source" detects the hazard after the reader has already consumed the
stale value. The correct pairing: the reader in D is compared against
writers in R and E (the writers ahead of it), and the reader is held
in D — its D logic is combinational and re-evaluates every cycle, so
holding it until the cycle after the writer's write lands gives the
fresh value. "R-stage source AR" is deleted: R never reads the AR
file (D1), so no R-stage instruction has an AR source to compare.
The pipeline registers must carry each in-flight instruction's write
targets (AR id, MMR ids, ST0/ST1) from its decode bundle, so the
comparison is available from D onward.]

[R2, B5 — ST0/ST1 were missing and are added. D-stage address
generation consumes DP (ST0, direct addressing), ARP (ST1, selects the
current AR), and the map bits (PMST OVLY/RAM/MPMC, ST1 CNF) that the
address resolves against. An LST #0/#1 write in E changes them while a
younger instruction is in D. They are D-stage dependencies under the
same detection as H1. The AR0 mirror is part of the write-target set:
an AR0 update in E also writes INDX and ARCR when NDX=0
(`apply_ar0_mirror`, `c5x_core.c:2756`), so a younger instruction in D
using INDX must stall for an AR0 writer in R/E.]

| # | Hazard | Detection | Handling |
|---|---|---|---|
| H1 | AR/INDX/ARCR/DP/ARP written by an instruction ahead, while a younger instruction in D computes an address from that register (AR id, INDX-indexed mode, direct addressing via DP, AR selection via ARP) | Reader in D: its D-stage sources (AR id, INDX use, DP use, ARP use, circular state CBCR/CBER/CBSR) vs the write targets of the instructions in R and E (from their decode bundles; AR0 writers also list INDX/ARCR when NDX=0). Same register id = hazard. | Hold F and D (reader stays in D, re-evaluating combinationally) until the cycle after the writer's write lands at its E edge, then the reader advances with the fresh value. Cost is 1–2 clocks; these writes are rare. This replaces TI Table 7-10's 2-word prohibition with an interlock: same sequential result, no reliance on the assembler inserting NOPs. Table 7-10 latencies (ARx/ARCR/INDX/CBCR/CBER/CBSR/PMST/CNF = 2, BMAR/CWSR/GREG/IOWSR/PDWSR/TREG1/TREG2 = 1) are the fallback stall budget if a forwarding case cannot be proven — not the target. |
| H2 | Memory-mapped register / configuration write in E (PMST/CNF/GREG/CWSR/PDWSR/IOWSR/BMAR/CBCR/CBER/CBSR) while a younger instruction in D/R depends on the new configuration or value | Same pairing as H1: reader in D vs writers in R/E. Map-changing writes (PMST/OVLY/RAM/CNF) additionally stall F, because F's fetch-address resolution uses the map — the fetch must not go out under the stale map. | Stall F/D until the write retires. Same as H1; configuration changes are rare. The 2-word rule of Ch.7 §7.3 is satisfied by the stall. |
| H3 | IO-space read with side effects performed speculatively in R | Any R-stage read to an address ≥ 0x50, host window 0xFF50–0xFF5F, or MMR 0x20 (DRR) | Defer the read to E (retirement). The E stage reads the flop target combinationally and performs the operation in the same clock (§3, C1). Ground: `mmr_rd` case 0x20 — reading DRR clears RRDY/RSRFULL (`c5x_core.c:652`); `io_read` (0x50+) goes to the host and must be assumed to have side effects. A flushed instruction must never cause an IO read. Non-side-effect MMR reads (TIM/PRD/ST0 etc.) may stay in R, but only if the read is provably pure — default is defer, whitelist later. |
| H4 | DMEM write in E vs DMEM read in R, same address, same clock | Address compare E-write vs R-read | Forward (§3), no stall. |
| H5 | Branch/call/return (BCND taken, CALL, RET/RETE, BACC, CALA) | Decoded in D; condition evaluated in E (TI: PC update depends on the E-phase result, Ch.7 §7.2.2) | Flush F/D/R when the E-stage branch resolves taken (4-cycle flush per TI; the in-flight instructions never committed, so no rollback). BCND not taken: no flush. The model-cycle count is 4 taken / 2 not taken regardless of the wall-clock flush cost. [CONVERGED: TI Ch.7 defines no delayed-branch mechanism, so the C model is the sole authority; the C-model delay slots ARE implemented per §5.] |
| H6 | Interrupt taken at retirement | Retire-stage check: (IFR & IMR) != 0 and INTM == 0, after the retiring instruction's timer tick, and NOT held. Held conditions, from `interrupt_held` (`c5x_core.c:2735`): the instruction after XC (`xc_new`), the remaining XC window (`xc_left > 0`, counted in words), and the single-word instruction at the end of a repeat block (`braf && pc == paer` after the rewind — i.e. a 1-instruction RPTB block that is still looping; interrupts are held for the whole loop and taken when it exits). | Flush F/D/R, enter the interrupt sequence (push PC, shadow 11 registers, load PC from the vector) as a pseudo-instruction occupying the pipeline; model cycles +4 for the entry. Same flush machinery as H5. [R2: the held conditions are part of the retire decision, not a separate mechanism.] |
| H7 | RPT/RPTB state (rptc/brcr) vs the repeated instruction's E | Repeat active | Handled in §5, not by the general interlock. |
| H8 | IN/OUT (IO handshake) | IN/OUT in E | E stalls until the host ack arrives (today's IO_WAIT, moved into E). Front end stalls behind it. Model cycles include the io_ws charge (§7). |
| H9 | 2-word instruction | Decoded in D | Second word fetched in F; D is a dummy for one clock (TI §7.2.1). Costs one fetch slot; unavoidable, measured in the CPI breakdown. |
| H10 | [R2, C3] TBLW writes program memory in E while F/D/R hold instructions fetched from the modified address | TBLW in E | On TBLW retirement, flush F/D/R and re-fetch from PC (see §3). |

[CONVERGED — B5 H2 F-stall pairing fix (Agent 3, Part 4; verified:
`apply_ar0_mirror`, `c5x_core.c:2756`, NDX == 0). The H2 detection
above ("reader in D vs writers in R/E") first fires when a
map-changing writer is in R — but the fetch of the instruction
immediately after the map-writer is issued during the writer's own D
cycle, under the stale map, and that one fetch escapes the stall. Also hold F — no fetch issued — from the cycle in which a
map-changing instruction is decoded until the cycle after its map
write lands in E: F is held while the map-writer is in D, R, or E,
and fetch resumes only in the cycle after the write retires (in the
example: cycles 1–3 held, resume fetch at cycle 4). This hold is NOT
gated on a reader in D — a reader-gated stall leaves cycle 2
unprotected, because the cycle-1 F-hold leaves D empty and the H2
detection does not fire. (The equivalent alternative is
flush-and-refetch F at map-write retirement.) Audit
question to answer alongside: whether the FPGA PMEM fetch path
actually depends on the map bits — if PMEM is a flat 64K array the
F-stall may be unnecessary; the audit must decide, not assume.]

What is deliberately NOT a hazard: ACC/PREG/TREG/flag RAW across
adjacent instructions (E-to-E, register timing covers it, §2);
AR RAW from D's own update to the same instruction's R (address is
carried, §2); PMEM fetch vs DMEM access (separate arrays).

## 5. Repeat: RPT, RPTZ, RPTB, and delay slots

[R2 — this section is rewritten in full. Three corrections: (B2) RPTB
loop-back is detected at FETCH, not retirement; (B3) the RPT replay
stage sequence is now specified per iteration; (B6) the AR-update
descriptor is an operation, not a value. One addition beyond the
critique, verified in the C source: the C model has TWO repeat
mechanisms with different retirement counting, and the plan must
implement both.]

**Two repeat mechanisms in the C model — the plan implements both.**

- **Mechanism (a) — opcode-internal loops.** A family of opcodes
  (MAC/MACD 0xA2/0xA3, BLDP/BLPD/TBLR and others at high bytes
  0xA4–0xAD, plus 0x09, 0x57, 0x7F — the audit in §11.1 enumerates
  them exactly from the C source) iterate INSIDE one `exec1` call:
  the case body is a `do/while (c->rptc > -1)` loop
  (`c5x_core.c:1390, 1631, 1915, 1999-2124`). The whole repeat is
  ONE C-model step and ONE retirement: a single `instr_done` pulse
  when the internal loop completes, model cycles = base + 1 per extra
  iteration (the internal `c->cycles++`, ported via `cyc_acc`). The
  front end is stalled for the whole internal loop. Per iteration,
  R re-reads at the recomputed EA and E re-executes (below).
- **Mechanism (b) — PC-rewind repeats.** All other opcodes under RPT
  are re-executed as separate main-loop iterations: `handle_rpt`
  (`c5x_core.c:2641`) rewinds PC to `rpt_start` while `rptc > 0` and
  sets `rep_cont = 1`; `instr_cycles` charges 1 per iteration (2 for
  IN 0xAF, 3 for OUT 0x0C). Each iteration is a separate C-model step
  and a separate retirement: one `instr_done` pulse per iteration.
  The pipeline implements this as a held-bundle replay (fetch once,
  replay R/E per iteration) — equivalent to the PC rewind, because
  each iteration recomputes its EA and re-reads its operand (below).
  The retire PC after each iteration except the last is `rpt_start`
  (the C model's rewound PC, compared by the harness); after the last
  it is the next instruction's address. For mechanism (a) the retire
  PC is the next instruction's address (the C model never rewinds —
  `handle_rpt` sees `rptc = -1` and clamps it to 0).

**Per-iteration stage sequence (both mechanisms).** The repeated
instruction's decoded bundle is held in the R/E register; the front
end (F/D) is stalled. Per iteration: **R re-reads** — the DMEM operand
at the EA recomputed by the ARAU from the CURRENT AR, and, for
opcodes with a program operand (MACD/MADD: `pfc++` per iteration,
`c5x_core.c:1993-2000`; BLDP/BLPD: the BMAR/program address advancing
per iteration), the PMEM operand at the advancing program address.
The PMEM read in R during replay steals the PMEM port from F, but F
is stalled, so there is no contention. **E re-executes and commits** —
the CALU operation, the AR update (from the descriptor operation,
below), the DMOV write if any, and the retire (one pulse per
iteration for (b), one pulse at the end for (a)). The MACD store-to-
load case is covered by the §3 bypass: iteration k's E writes dma+1
while iteration k+1's R reads dma+1 in the same clock — the bypass
forwards the new (moved) value, as the sequential C model requires.
[CONVERGED — B3 overlapped-replay address forwarding (Agent 3, Part 4;
verified: MAC/MACD per-iteration `ea(c)` + `pm_rd(c, pfc)` + `pfc++`,
`c5x_core.c:1993-2000`; `handle_rpt`, `c5x_core.c:2641`;
`instr_cycles` 1 per repeated iteration, 2 IN / 3 OUT,
`c5x_core.c:2617`). §5 above puts iteration k's E and iteration k+1's
R in the same clock, yet R's address was to be "recomputed by the ARAU
from the CURRENT AR" while the ARAU was assigned to D (initial EA) and
E (per-iteration re-evaluation) — R would read the AR flop, which
still holds the pre-update value (iteration k's update lands at the end
of that clock), so R(k+1) would read the stale address. For MACD `*+`
the operand value coincides by accident (the DMOV moved the same value
to dma+1), but for MADD `*+` iteration k+1 reads the previous tap
instead of the next one, and for `*-` and circular modes the address is
wrong. Required fix: during replay, R's DMEM address is computed by
the ARAU from the forwarded post-update AR — E's pending descriptor
output is forwarded into R's ARAU input in the same clock — and the
PMEM address is the forwarded pfc+1; R and E hold separate
per-iteration copies of the bundle during replay. The non-overlapped
alternative (2 clocks per iteration) is rejected: it breaks the CPI
~1.0 target on the FIR hot path.]

**AR-update descriptor is an OPERATION (B6).** The descriptor carried
in the pipeline registers is (ar id, mode, ARP-switch flag), where
mode ∈ {none, +1, −1, +INDX, −INDX, bitrev+INDX, bitrev−INDX}. It is
NEVER a precomputed new AR value: `ea()` (`c5x_core.c:1119`) returns
the current AR as the address and applies the update as a function of
the current AR — circular wrap tests `ar == cber` before stepping
(`upd_ar`, line 1085), and bit-reverse computes
`bitrev16(bitrev16(a) ± bitrev16(indx))` from the current value. A
precomputed value applied twice would be wrong on the second
iteration. The descriptor is re-evaluated per iteration from the
current AR by the ARAU, reading CBCR/CBER/CBSR/INDX live at
application time (they are not captured in D). The ARAU is a single
combinational function (in `c5x_addr`) used by D for the initial EA
and by E for per-iteration re-evaluation during replay. The E-commit
also applies the ARP switch (ARB = old ARP, ARP = nar, `upd_arp`)
and the AR0 mirror (INDX = ARCR = AR0 when ar == 0 and NDX == 0).
Directed test: RPT + circular MACD against the C model (the FIR hot
path).

- **RPT/RPTZ (single instruction)**: RPT sets rptc in E. The following
  instruction is fetched once, then replayed as above. RPTZ
  additionally zeroes ACC/PREG at setup. Model cycles per iteration:
  1, or 2 for IN, 3 for OUT (existing `cyc_acc` loop terms, ported
  verbatim — mechanism (a) uses the internal-loop terms instead).
- **RPTB (block repeat)**: RPTB sets PASR/PAER/BRCR in E. [R2, B2 —
  the Revision 1 retirement detection is withdrawn: it flushes the 3
  in-flight instructions past the block end and pays a 3-cycle refill
  bubble per iteration, CPI 1.75 on a 4-instruction loop body and 4.0
  on a 1-instruction body, contradicting the CPI ~1.0 gate.] The
  block end is detected at FETCH, as TI does: when F fetches the
  instruction at PAER and the effective BRCR > 0, the next fetch
  redirects to PASR, costing ~0 bubbles. Effective BRCR = BRCR −
  pending_braf (saturating at 0), where pending_braf counts redirects
  decided in F whose block-end instruction has not retired yet — this
  covers the 1-instruction block, where the next iteration is fetched
  before the previous iteration's decrement lands. The BRCR decrement
  commits at the block-end instruction's retirement (E): BRCR−− and
  pending_braf−−. On any flush (branch taken, interrupt entry, TBLW),
  pending_braf resets to 0 — all speculative redirects are discarded
  and the committed BRCR is untouched. [CONVERGED — B2 RPTB entry rule
  (Agent 3, Part 4; verified: RPTB 0xC6 is 2-word,
  `c5x_core.c:2402-2407`: `imm = fetch(c); braf = 1; pasr = pc; paer =
  imm`; BRCR is set only by MMR write 0x09, `c5x_core.c:719`; RPTB
  covers 47.53% of DSP time, profiler comment `c5x_core.c:2768`). The
  fetch-redirect above does not work at RPTB entry: RPTB sets
  BRAF/PASR/PAER only when it retires in E (cycle 3), but PASR is
  first fetched in cycle 2 — for a 1-instruction block (PAER = PASR)
  the block-end fetch happens at cycle 2 while BRAF/PAER are still
  stale, and for a 2-instruction block (PAER = PASR+1) the block-end
  fetch is at cycle 3, during which RPTB is in E and the BRAF flop is
  still 0 — so no redirect is decided and the loop executes once and
  falls through. Only blocks of ≥3 words work at entry. Required fix:
  stall F after RPTB is decoded until RPTB retires (2 bubbles once
  per RPTB setup), so PASR is first fetched with BRAF/PAER/BRCR
  committed and the redirect logic works from the first iteration.
  Equivalent alternatives (forwarding RPTB's pending BRAF/PAER into
  F, or an RPTB-retirement redirect) are acceptable if they achieve
  the same entry behaviour; the stall is the default. Cost: 2 bubbles
  per RPTB setup, counted in the CPI breakdown (§10.8).] Two-word
  block-end corner: the
  C model does NOT rewind for a 2-word block-end instruction
  (`handle_braf` checks `(pc−1) == paer`, `c5x_core.c:2663`, which
  fails after a 2-word instruction), so D cancels a speculative
  redirect when the instruction at PAER decodes as 2-word: flush F
  (discard the speculatively fetched PASR word), fetch PAER+1 (the
  second word), cancel the pending decrement. [CONVERGED: the cancel
  applies only when the PAER word is a FIRST word — a 2-word
  instruction starting at PAER−1 has its second word at PAER, and the
  C model DOES rewind for it (`handle_braf` checks `(pc−1) == paer`,
  `c5x_core.c:2663`, which holds after a 2-word instruction starting
  at PAER−1), so no cancel there. The audit must record, for each
  block-end address, whether the PAER word is a first word.] Cost: 1 bubble, only
  for 2-word block-end instructions (the audit confirms whether any
  occur in the firmware). RPTB cannot be nested (manual); the plan
  does not implement nesting. The existing multi-cycle CTRL-LOOP
  engine is deleted, not ported. The C-model order is preserved:
  `handle_braf` runs before the interrupt check
  (`c5x_core.c:2661, 3282`), so an interrupt taken at the block-end
  retirement pushes the rewound PC (PASR) — in the pipeline the fetch
  redirect has already set the next PC to PASR, so the entry pushes
  PASR. Consistent by construction.
- **Delay slots** (BD/BZD/CALLD/RETD family, XC window): the slot
  words flow through the pipeline as ordinary instructions after the
  branch word; the branch action is held in a pipeline-side register
  and applied when the second slot word retires (existing C logic:
  `delay_slot`, pop when `(pc - slot_start) >= 2`). The multi-cycle
  ctrl's slot handling is the reference for the exact semantics; the
  pipeline version must reproduce the same retire order and the same
  model-cycle charges (slot words add their `cycm` each). A BADOP
  inside a slot restores pc to the outer instruction's ppc and halts,
  as today.
- **XC**: the XC window state is carried in the pipeline registers
  (it gates whether the following instructions execute); no separate
  FSM.

## 6. Interrupts and IDLE

- **Interrupt entry**: recognised at retirement only (never mid-
  instruction). The decision uses the IFR state as of the retire edge,
  including a timer tick landing on that edge — via the combinational
  "this tick will raise TINT" signal (§7, C2) — so the interrupt is
  taken before the next instruction executes, exactly as the C model
  does (`check_int`/`do_int` before the next instruction,
  `c5x_core.c:1298`). [R2, B1 consequence: with a wall-clock timer
  the expiry is a real-time event; the RTL takes the interrupt at the
  first retirement after the wall clock on which the expiry lands,
  i.e. within 1 wall clock of the expiry — the same real-time latency
  as the C model, which takes it after the instruction whose cycle
  charge spans the expiry. The two models take the interrupt after
  different instruction counts (the RTL retires ~2.48x more
  instructions per unit time); the harness handles this in §9
  (interrupt-aware comparison), it is not a correctness defect.]
  Entry cost: +4 model cycles. The 11 shadow registers and
  the 8-level stack are saved by the entry pseudo-instruction;
  RETE restores them. NMI/INTR/TRAP follow the C model's `do_int`
  paths; the audit's interrupt findings stay KNOWN-DIFF, not fixed.
  The held conditions of `interrupt_held` (`c5x_core.c:2735` — XC
  window, and the 1-instruction RPTB block) are part of the retire
  decision (§4 H6).
- **IDLE/IDLE2**: IDLE drains the pipeline, then parks fetch. [R2,
  B1: the Revision 1 rule "while parked, each wall clock is one model
  cycle" is WITHDRAWN — it was the term that made the model-cycle
  timer 59% fast. With a wall-clock timer there is nothing to
  fast-forward: the timer simply keeps ticking once per wall clock
  while the DSP is parked, which IS the fast-forward, in real time.]
  Wake on (IFR & IMR) masked by 0xFFFF (IDLE) or 0x107 (IDLE2,
  INT1–4 only) — `c5x_core.c:3191-3234`. IDLE2 stops the timer
  (TSS-equivalent behaviour in the fast-forward path — the C model
  jumps `cycles` to the budget end without advancing the timer; the
  RTL freezes the prescaler/TIM while IDLE2 is parked). The wake
  interrupt is then taken through the normal entry path.

## 7. Model-cycle accounting and timer/serial adaptation

[R2, B1 — this section is rewritten in full. The Revision 1 design
drove the timer from model cycles; that is functionally wrong in real
time and is withdrawn. The arithmetic, verified against the C model
and the glue: per sample at 7200 Hz the FPGA has 40 MHz / 7200 =
5,555.6 wall clocks, while the C-model budget is 2·A·T = 5,600 model
cycles (`machine.c:396-406`). The firmware's busy work is X model
cycles = N instructions at ~2.48 cycles/instr (100,000 instr /
247,799 cycles), so N ≈ X/2.48. A model-cycle timer advances by the
retirement credits (X) plus the idle wall clocks (5,555.6 − N, under
the Revision 1 IDLE rule) = X + 5,555.6 − X/2.48. At full load
(X = 5,600): 5,600 + 3,297 ≈ 8,897 model cycles per sample vs 5,600
— ~59% too fast; at zero load the error is −0.8% (5,555.6 vs 5,600).
The error scales with DSP load, and the V.34 firmware is heavily
loaded. The observable consequence: `timer_expiries` is the board's
host heartbeat (INT0, 2,401 Hz measured, `c5x_core.c:3362`) — a
model-driven timer pushes it toward ~3,800 Hz at full load and makes
every firmware timeout fire early. Worse, the defect was invisible to
the Revision 1 gates: the smoke gate compares `timer_expiries` in
model time and the co-sim compares `tim` per retirement, and a
model-driven timer matches the C model in model time by
construction.]

- **Retire-time cycle computation.** The retiring instruction's
  C-model cycle count is computed in E from the carried decode bundle
  and the retire-time facts (taken/not-taken, loop iterations, IO
  wait states, MMR write, interrupt entry). This is a port of the
  existing `cyc_acc_q` logic in `c5x_ctrl.sv` (header comment: base
  `dec_cycles`, class-1 taken 4 / not-taken 2, class-2 RETCD 2,
  rep_cont 1 / 2 IN / 3 OUT, loop `(n-1)*k`, slot `cycm`, IN +io_ws,
  OUT +(io_ws-1) if io_ws>1, dm write to peripheral MMR 0x20–0x4F
  +1, dm IO read +io_ws / dm IO write +(io_ws-1), interrupt entry
  +4). Every term must be re-derived from the C model and the port
  must be checked term-by-term against the multi-cycle implementation
  — this is the most bug-prone part of the redesign and gets its own
  directed test (see §10). [R2, C11: the check is against the C
  model, via the firmware co-sim's per-instruction cycle comparison
  (`cosim.cpp:268`), not against the multi-cycle port — the
  multi-cycle `cyc_acc` is itself a port.]
- **Model-cycle counter.** `cycles_o` advances by the computed count
  at the retire edge only. It is a 64-bit counter, never a wall-clock
  count. It is **verification bookkeeping only**: it drives the
  co-sim's `run_to_cycles` pacing and the per-instruction cycle
  comparison, and nothing else. It drives no peripheral.
- **Timer — ticks once per WALL clock, prescaled by TDDR (B1
  resolution).** This is the real-hardware behaviour (TI manual §9.4;
  the C model's `tick_timer` is one tick per machine cycle,
  `c5x_core.c:1333-1350`, and a machine cycle on hardware is a
  clock). The RTL implements `tick_timer` directly as a per-wall-
  clock process in `c5x_mem`: a 4-bit prescaler counts down from
  TDDR; on expiry TIM counts down, and on TIM == 0 it reloads from
  PRD and raises TINT (IFR bit 3, `timer_exp` increments); frozen
  entirely while TSS is set. The closed-form `advance_timer`
  (`c5x_core.c:2683`) is NOT needed in the RTL — it exists in the C
  model to fast-forward; the RTL ticks for real, one clock at a time.
  The existing per-clock tick drain in the multi-cycle ctrl is
  deleted, and no retire-edge `(mtick_en, mtick_n)` interface is
  built. The memory block presents a combinational
  "this tick will raise TINT" signal for the retire-time interrupt
  decision (§6): `!TSS && (psc == 0) && (tim == 0)` [R2, C2] — a
  4-bit zero compare + a 16-bit zero compare + AND, depth budget ≤ 4
  LUT levels, feeding the interrupt decision, the flush, and the PC
  mux. Fallback if that path is too deep: an E-hold — stall E one
  cycle to let IFR register the tick, then decide — costing 1 clock
  only when a timer expiry coincides with a retire boundary (once per
  timer period, ~16.8k clocks at the firmware's 2,401 Hz heartbeat:
  negligible).
- **Clock-rate note.** The FPGA core runs at 40 MHz; the real Courier
  DSP runs at 40.32 MHz. A wall-clock timer therefore ticks at
  40/40.32 = 99.2% of the real rate: the heartbeat is ~2,382 Hz
  against the nominal 2,401 Hz, and firmware timeouts run 0.8% late.
  That is a constant rate difference (crystal-tolerance scale), not a
  load-dependent error, and the gates tolerate it (§9). If the
  top-level PLL runs the DSP at 40.32 MHz instead, the timer matches
  the C model exactly at sample boundaries; that is a top-level
  clocking decision, not part of this plan.
- **Serial port.** The serial tick (`c5x_serial_tick`, driven by the
  host glue per sample — `machine.c:3129,3221`) is unchanged: it is a
  host event, not a model-cycle event. Worker C must confirm which
  serial sub-state in `c5x_mem` advances per wall clock today vs per
  (retired) mtick, and move only the model-time parts to wall-clock
  timing. No serial interface changes.
- **IO wait states.** IN/OUT and dm IO accesses charge exactly as the
  C model does (`io_read`/`io_write`, `c5x_core.c:584-606`); the
  charge is a model-cycle number added at retirement, independent of
  how many wall clocks the host ack actually took.
- **TREG1/TREG2 direct-write fix (C8).** The explicit write port in
  the E-commit implements the C-model `mmr_wr` cases
  (`c5x_core.c:723-724`): direct DMEM write to 0x0D sets
  `treg1 = d & 0x1F`; to 0x0E sets `treg2 = d & 0xF`. Interaction
  with the TREG0-load mirror (`set_t0`, `c5x_core.c:1045-1053`): every
  TREG0 load mirrors to TREG1/TREG2 unless TRM is set (TRM = PMST
  bit 1, `c5x_core.c:88, 555, 715`). A single instruction does either
  a TREG0 load or a direct TREG1/2 write, never both — one writer
  (E), no intra-instruction conflict; the mirror is applied on every
  TREG0 load (LT/LTA/LTS and the MACD `set_t0` path).

## 8. Module map: what changes per file

| File | Change |
|---|---|
| `rtl/c5x_decode.sv` | Unchanged (combinational decode; its TB's 66,726 checks stay the gate). Possibly widened outputs only if the pipeline needs a field the bundle lacks. |
| `rtl/c5x_ctl_pkg.sv` | Add pipeline-register packed structs (F/D, D/R, R/E), hazard/stall/flush enums, retire bundle. Keep KD-1..KD-24 and the cycle table. |
| `rtl/c5x_ctrl.sv` | DELETE the multi-cycle FSM (states RESET..RESTORE) and replace with `c5x_pipe_ctrl`: hazard detection (§4), stall/flush generation, retire logic, model-cycle computation (§7), interrupt entry sequencing, RPT/RPTB/delay-slot state. This is the largest new module and owns the design's correctness. |
| `rtl/c5x_alu.sv` | Mostly unchanged (E-stage datapath). Add the TREG1/TREG2 direct-write path (open gap from the multi-cycle core: direct DMEM writes to 0x0D/0x0E are dropped today) — the pipeline redesign is the moment to fix it, via an explicit write port, not the TREG0 mirror. Citations and mirror interaction in §7 (C8). Keep the single signed 16x16 multiply registered into PREG (one DSP block). |
| `rtl/c5x_addr.sv` | Split into D-part (ARAU address generation, combinational) and E-part (AR file commit, stack, status). AR updates computed in D as an operation descriptor (§5, B6), committed in E. The ARAU is one combinational function used by D and by E during RPT replay. Keep observation outputs. |
| `rtl/c5x_mem.sv` | [R2] Wall-clock timer: `tick_timer` as a per-wall-clock process (prescaler from TDDR, TIM/PRD, TINT, TSS freeze); delete the per-clock tick drain and do NOT build the retire-edge mtick interface. Deferred IO reads in E (flop targets only, §3 C1); store-to-load bypass mux on the DMEM read port; PMEM port arbitration for PMEM-operand reads (stall F) and the PMEM write-port mux (loader vs E/TBLW). M10K template unchanged. Keep the TAIL write-port mux hazard fix in mind: the E-stage write port is redesigned here, and the old latent hazard (ST0+ST1+rptc-clamp collision) must not be reintroduced — one writer per register per cycle, priority defined in the module header. [R2, Part 1 B6: the mux is replaced by E-as-single-writer with per-register enables, not a muxed single port.] |
| `rtl/c5x_core.sv` | Rewired top: instantiates decode/addr/alu/mem plus the new pipeline control; program controller (PC, stack interface, interrupt vectors); pipeline registers; IO handshake to the host glue (unchanged protocol); loader port (unchanged). |
| `tb/` | Old multi-cycle RTL stays in `hidden_files/pre-pipeline/` AND as the `tb/` reference per the house rules. New TBs: §10. |
| `sim/cosim.cpp`, `sim/c_ref.*` | Retire-based harness (§9). |
| `docs/cosim.md` | Updated pipeline description, new harness protocol, CPI measurement. |
| `GOAL.md` | Status entries as work lands. |

House rules apply throughout: block comments only, 150 columns, one
statement per line, case tables not ternary chains, typedef enum named
states, shared constants in packages, magic numbers as localparams
with a source comment.

## 9. Co-sim harness change (retire-based comparison)

- The harness clocks the RTL one clock at a time. On each clock where
  `instr_done` (retire pulse, one clock wide) is high, it steps the C
  model exactly one instruction and compares the full architectural
  state — the same comparison as today (AR file, stack, mem-owned
  registers TIM/PRD/DXR/DRR/GREG/SPC/TCR/PDWSR/IOWSR/CWSR, pc,
  cycles). [CONVERGED — clarification 1 (Agent 1; verified:
  `c->cycles += instr_cycles(c, ppc, sp0) - 1` per instruction after
  `exec1`, `c5x_core.c:3249`; idle fast-forward `c->cycles = end`,
  `c5x_core.c:3216, 3233`). The cycle comparison is per-instruction
  DELTA, not the absolute counter: the harness captures the C model's
  cycles before and after the single-step call (`cref_step`) (excluding the run loop's
  idle fast-forward) and compares that delta to `retire_cycles_o`. The
  absolute counters diverge across idle periods by design, so
  comparing absolutes would fail the gate. `cycles_o` advances by 1 per
  wall clock while parked (IDLE/IDLE2) for pacing only and is not
  compared absolutely. The single-step must exclude the idle
  fast-forward from the measured window (an idle step executes no
  instruction, so there is no delta to compare).] [R2, B1: TWO fields leave the per-retirement comparison.
  `tim` is dropped — the RTL timer ticks per wall clock and the C
  model's per model cycle, so the values legitimately differ at any
  given retirement. IFR is compared with bit 3 (TINT) masked out —
  TINT is timer-driven and the two timers run on different time
  bases. Everything else in the comparison is unchanged. No extra
  clock after retire: the retire edge is final for that instruction.]
- Repeat iterations retire individually for mechanism (b) (§5) and
  once per whole repeat for mechanism (a), so the C-model step count
  and the RTL retire count stay 1:1, as today. The retire PC after a
  mechanism-(b) iteration except the last is `rpt_start` (the C
  model's rewound PC); after the last it is the next instruction's
  address; for mechanism (a) it is the next instruction's address.
- `run_to_cycles` / the smoke gate count MODEL cycles, not wall
  clocks: run until `cycles_o` reaches the checkpoint.
  [R2, B1: the timer is verified at SAMPLE boundaries, not per
  retirement and not in model time. The harness adds a sample strobe:
  every 5,600 model cycles for the C model and every 5,556 wall
  clocks for the RTL (40 MHz / 7200 Hz, rounded — the exact strobe
  interval is the glue's sample period; the 40/40.32 ratio is the
  known constant). At each sample boundary the harness compares
  `timer_expiries` with the ratio tolerance |RTL − C × (5,556/5,600)|
  ≤ 2 (phase), and over the whole run it checks the TINT rate:
  measured heartbeat vs 2,401 × 40/40.32 ≈ 2,382 Hz nominal, tolerance
  ±1%. [CONVERGED — B1 long-run note (Agent 3, Part 4): the ±2
  sample-boundary tolerance is valid for the stated gates (100k
  instructions ≈ 6 ms, smoke ≈ 0.2 s of emulated time; the ratio
  error 8e-5 per expiry stays far below 2) but drifts past ±2 beyond
  ~10 s of emulated time — long runs must use the exact 40/40.32
  ratio with a Bresenham strobe; the TINT-rate check (±1% vs 2,382 Hz)
  is the long-run gate.] The raw TIM value is NOT compared at boundaries (its phase
  differs by the accumulated 0.8%). `idle_cycles` is dropped from the
  checkpoint comparison, with the reason stated: the pipelined core
  legitimately idles more wall clocks per sample than the C model
  idles model cycles, because it retires the same work in fewer
  clocks — the idle fraction is not comparable across time bases, and
  the observable that matters is the timer rate, not the idle count.
  The C model's `idle_cycles` remains a diagnostic, not a gate.]
- [R2, addition beyond the critique — interrupt-aware comparison.
  The wall-clock timer breaks the per-retirement lockstep at
  interrupt entries, and the harness must handle it rather than fail
  on it. The RTL retires ~2.48x more instructions per unit time than
  the C model charges, so a timer expiry (a real-time event) is taken
  after a different instruction count in the two models — in the RTL
  it may fire while the DSP is idle after finishing the sample's
  work, while in the C model it fires mid-stream. The per-retirement
  comparison therefore works as today for straight-line code, but at
  an interrupt entry the harness does NOT require the two models to
  be at the same retirement index. Instead it (i) verifies the entry
  mechanism relative to the preceding retirement in each model
  separately (correct PC pushed = the next instruction's address as
  of that retirement, correct 11 shadow registers as of the last
  retired instruction, correct vector load), and (ii) re-synchronises
  at the next sample boundary with a full-state comparison (same
  instruction stream executed per sample, so the states reconverge
  there, modulo the timer tolerance above). If a sample-boundary
  comparison fails, the cause is investigated as a defect — it is not
  dismissed as a harness artifact — because non-reconvergence would
  mean the ISR observes different intermediate state in the two
  models. The 100,000-instruction gate counts matched retirements
  plus passing sample-boundary comparisons.]
- `step_i` is redefined as a fetch hold: low stops F from fetching;
  in-flight instructions complete and retire; no retire pulses once
  the pipeline drains. The harness single-step protocol is rewritten
  around this; the ability to single-step one instruction at a time
  for debugging is preserved.
- **CPI measurement**: the harness counts wall clocks and retirements
  for each run and reports CPI = clocks / retired instructions, plus
  a stall breakdown counted by cause (branch flush, 2-word fetch,
  PMEM-operand stall, RPT replay clocks, IO-wait clocks, interrupt
  entry clocks, hazard stalls by class H1/H2/H3/E-read). The stall
  counters are RTL observation outputs (like the existing `obs_*_o`),
  not harness guesses.
- IO handshake handling, the debug read port (no clocks spent reading
  RTL memory back), and the pseudo-port filtering stay as today.

## 10. Verification gates

All gates must pass before the plan is declared done. Same gates as
the multi-cycle core, plus pipeline-specific ones:

1. `verilator --lint-only -Wall` clean on all RTL.
2. Unit TBs: decode TB 66,726/0 (unchanged); alu/addr/mem TBs
   re-run (1037/313/168); NEW directed pipeline TBs, one per hazard
   class H1–H9, plus branch flush with a following AR update,
   interrupt flush with a following AR update, RPT/RPTB replay,
   deferred IO read (DRR read must not clear RRDY when flushed),
   IDLE wake. Each directed test compares retire state vs the C
   model on a minimal program.
3. NEW random pipeline test: random valid instruction streams
   (seeded, bounded length) run through the RTL and the C model,
   retire-by-retire comparison — the house-rules equivalence proof
   alongside the firmware run. [R2, C9: the generator must cover the
   hazard classes (or coverage must be measured) — a random test of
   straight-line ALU ops proves little. Folded in here is the Part 1
   B7 opcode/coverage audit: list the opcodes exercised by each gate
   (firmware run, random test, directed tests), and require a directed
   test or a written justification for each unexercised opcode
   (TBLW, IDLE2 wake paths, the TREG1/2 direct writes, addressing
   modes the firmware never uses).]
4. Firmware co-sim: 100,000 instructions MATCHED (same gate as the
   multi-cycle core), counted as matched retirements plus passing
   sample-boundary comparisons (§9). Then a longer run if time
   permits; the 100k gate is the acceptance bar.
5. DSP smoke gate: 8/8 checkpoints OK, under the revised checkpoint
   comparison of §9 (sample-boundary `timer_expiries` with the ratio
   tolerance, TINT-rate check, `idle_cycles` dropped). The
   pre-existing `recent_pcs[16]` vector-ring-shift artifact is a
   vector artifact, not an RTL bug — do not chase it; if it reappears,
   record it as the same artifact.
6. Cyclone V synth (`synth_intel_alm -top c5x_core -family
   cyclonev`): report cells/ALUT/FF/M10K/DSP, zero `$mem_v2`, and
   confirm PMEM/DMEM map to M10K. Also synth the multi-cycle top
   first (its top-level synth was parked) so the pipeline's cost is
   measured against a baseline, not guessed.
7. **40 MHz evidence**: Yosys gives no Fmax — state this plainly.
   Evidence offered: per-stage combinational depth (D: decode case
   table + 16-bit ARAU add + circular/bit-reverse logic; E: 32-bit
   ALU + shifter + writeback muxes; R: BRAM read; the multiplier is
   registered into PREG). [R2, C5 — operationalisation, with the
   honest limitation: the candidate command for a depth number is
   `yosys -p "read_verilog -sv rtl/*.sv; hierarchy -top c5x_core;
   proc; opt; techmap; abc -script <file>"` with the ABC script
   `strash; print_stats;` (ABC's `print_stats` reports `lev`, the
   logic depth). This could NOT be verified on this VM at plan time:
   Yosys is not installed in the shell that wrote this revision (not
   on PATH; the toolchain tar is present but not installed here), and
   ABC availability depends on the Yosys build. The plan therefore
   states: try the command when the toolchain is available; if it
   yields no depth number, the evidence is stage-local reasoning only
   (per-stage depth estimated by inspection) and Quartus Fmax remains
   ground truth. No depth number is claimed that was not measured.]
   If a stage is too deep for 25 ns, the fallbacks are: E splits into
   E1/E2 (a 5-stage pipeline); [R2, C4] D splits into D1 (decode +
   AR-file read) and D2 (ARAU add + circular/bit-reverse) — both are
   documented fallbacks, not part of this plan.
8. **CPI report**: measured CPI on the 100k firmware run with the
   stall breakdown (§9). Acceptance: CPI ~1.0; any class costing
   >0.05 CPI gets a named explanation. If CPI lands above ~1.15,
   the plan is revisited, not the acceptance bar quietly moved.
   [CONVERGED — branch-cost correction (Agent 3, Part 4): a taken
   branch costs 3 extra wall clocks (4 clocks for 1 retirement: the
   branch's E plus the 3-cycle refill), so at 3–5% taken branches the
   branch cost is 0.09–0.15 CPI, not 0.06–0.10 (which assumed 2
   bubbles). The audit's pre-RTL CPI estimate (C7, §11.1(b)) must use
   the 3-bubble figure; the measured CPI gate above governs
   regardless.]
   [R2, C7: the CPI is ALSO estimated from the firmware mix BEFORE
   RTL — the audit (§11.1) counts branch / RPTB / 2-word /
   PMEM-operand / IO frequencies in the 100k firmware run (the C
   model produces the histogram) and derives an expected CPI. The
   measured CPI is checked against the estimate; the CPI is not
   discovered only after RTL.]

## 11. Work subdivision and order

Order matters: audit first, then datapath and memory in parallel,
then control/integration, with the harness running throughout.

1. **Hazard + port audit (short, first, blocks RTL).** From the
   decode table + C model: per-opcode (PMEM reads, DMEM reads, DMEM
   writes) per phase; per-opcode AR/flag/MMR dependencies; the
   `ea()`/`upd_ar()` order per class. [R2: the audit also (a)
   enumerates the two repeat mechanisms — which opcodes use the
   internal rptc loop (mechanism (a)) vs the PC-rewind (mechanism
   (b)) — from the C source; (b) counts branch / RPTB / 2-word /
   PMEM-operand / IO frequencies in the 100k firmware run (C-model
   histogram) and derives an expected CPI before RTL (C7); (c) states
   the audit's terms of reference for a same-array double access in
   one phase (R-stage replay, C12).] Output: a table in
   `docs/cosim.md` (or a new `docs/pipeline-hazards.md`) that §3–§4
   implement. No RTL until this is written.
2. **Worker B — datapath** (`c5x_alu.sv`, `c5x_addr.sv` D/E split,
   TREG1/TREG2 write path). Unit TBs per module.
3. **Worker C — memory + timer** (`c5x_mem.sv`: wall-clock timer
   (`tick_timer` per wall clock), deferred IO reads, bypass mux, PMEM
   arbitration, PMEM write-port mux). Unit TBs.
4. **Worker A — pipeline control + top** (`c5x_ctrl.sv` rewrite as
   pipe control, `c5x_core.sv` rewire, pipeline registers,
   interrupt entry, RPT/RPTB/delay slots). Owns integration.
5. **Worker D — harness + TBs** (retire-based harness, directed
   hazard tests, random pipeline test, CPI counters, smoke-gate
   adaptation). Starts with the audit; runs the gates after each
   landing.
6. **Lead verification** of each landing (lint + TBs + co-sim +
   synth), exactly as for the multi-cycle core. Nothing is reported
   done on a worker's word alone.

## 12. Where I disagree with, or refine, the briefed direction

These are disagreements with the direction as briefed to Agent 1,
stated plainly. Items D1–D3 are refinements of mechanism, not of
goal; D4 is a claim about evidence that the plan must not make.

- **D1 — "R uses the pre-update AR pointer" should be implemented as
  "the EA is computed in D and carried in the pipeline register",
  not as "R re-reads the AR file and somehow sees the old value."**
  Re-reading the AR file in R cannot give the pre-update value once
  D's update has landed in the flops, and TI's rule exists precisely
  because their D update is visible too early. Carrying the EA gives
  the same observable result as TI's rule, is correct for flushed
  instructions, and removes a whole class of timing subtleties. If
  Agent 1 proposes an AR-file re-read in R, that is a blocking
  objection.
- **D2 — "Table 7-10 latencies as stall counts" should be the
  fallback budget, not the mechanism.** Table 7-10 describes TI's
  unprotected pipeline (the assembler inserts NOPs). Our pipeline
  is interlocked: stall only until the conflicting write retires
  (usually 1–2 clocks, often 0 if the use is not actually dependent).
  Using the full Table 7-10 counts as unconditional stalls would
  cost CPI for no correctness benefit. The stall condition must be
  computed from actual dependence (same register id), not from the
  table's worst case. [R2: the mechanism is fixed per B4 (reader in D
  vs writers in R/E; "R-stage source AR" deleted) and B5 (ST0/ST1
  DP/ARP/map bits added as D-stage dependencies, AR0-mirror write
  targets included). With those fixes D2 stands as written.]
- **D3 — "Mimic the C5x pipeline" does not mean "copy TI's lack of
  interlocks".** The C model is sequential and is the spec. TI's
  unprotected behaviour (Ex. 7-6: the E-phase SAMM overwriting the
  D-phase ARAU update) is a hardware quirk that produces results the
  C model does not produce. The plan interlocks instead. Any proposal
  to reproduce a TI conflict outcome in RTL is a blocking objection.
- **D4 — 40 MHz cannot be claimed from Yosys.** `synth_intel_alm`
  reports cells and inference; it does not do timing. The plan's
  §10.7 states the evidence available and names Quartus Fmax as
  ground truth. Any report that says "40 MHz verified" on the basis
  of a Yosys run is wrong and must be corrected.
- **D5 — "1 instruction per clock" needs the honest qualifier.**
  Branches flush (4 clocks), 2-word instructions cost 2 fetch
  slots, PMEM-operand instructions stall F, RPT replay occupies the
  pipeline. The target is CPI ~1.0 on the firmware mix with a
  measured breakdown (§10.8), not a literal 1.0 for every
  instruction. If the measured CPI is materially above 1.0, the
  breakdown says where it went; the plan is then revisited.

## 13. Open questions (resolve from the C source during implementation, not by guessing)

- Exact `ea()` vs `upd_ar()` order for each addressing class
  (direct/indirect/circular/bit-reverse, and the RPT per-iteration
  variants) — read `c5x_core.c:1085-1168` and the per-opcode paths.
  [R2: the order is settled in principle — `ea()` returns the current
  AR as the address and applies the update as a function of the
  current AR (§5, B6); the audit (§11.1) records it per class.]
- Which MMR reads besides DRR (0x20) have side effects in the C
  model (SPC read is pure — computed value; TIM/PRD pure; `io_read`
  0x50+ assumed impure). The H3 whitelist depends on this.
- [R2: RESOLVED — the exact C-model cycle charges for RPTB block-end
  handling and for delay-slot words are ported from the multi-cycle
  `cyc_acc` logic and checked against the C model's per-instruction
  cycle comparison (§7, C11), not re-derived from the manual. The
  RPTB block-end charge is the fetch-redirect design in §5, and the
  2-word block-end case follows `handle_braf`'s `(pc−1) == paer`
  test. Removed from the open list.]
- Whether the serial-port sub-state in `c5x_mem` advances per wall
  clock or per mtick today (worker C to confirm; §7). [R2: reworded —
  with the wall-clock timer there is no mtick; worker C confirms
  which serial sub-state advances per wall clock today vs per retired
  model cycle, and moves only the model-time parts to wall-clock
  timing.]

## 14. Acceptance

This plan is accepted when: the hazard/port audit (§11.1) exists and
is complete; the RTL implements §2–§8; the harness implements §9;
all gates in §10 pass with the numbers reported (CPI + breakdown,
synth table, co-sim counts, sample-boundary timer comparisons and the
TINT-rate check); the residuals (§10.7 fallback, any CPI class >0.05)
are named in GOAL.md. The old multi-cycle core in
`hidden_files/pre-pipeline/` remains the reference; the firmware
co-sim + random test are the equivalence proof. [R2: the acceptance
bar includes the revised §9 gates — per-retirement comparison without
`tim` and with IFR bit 3 masked, timer verified at sample boundaries
with the 40/40.32 ratio tolerance, and the interrupt-aware entry
verification with sample-boundary resynchronisation.]

## 15. Convergence and sign-off

[CONVERGED] This section records the three-agent agreement. The
converged text is: the R2 plan (§0–§14 above) + Agent 1's two
clarifications (§4 H5 rewording; §9 per-instruction DELTA cycle
comparison) + Agent 3's three fixes (§5 RPTB entry rule and D-cancel
first-word conditioning; §5 overlapped-replay address forwarding; §4
H2 F-stall pairing extended to writer-in-D) + the branch-cost
correction (§10.8, 3 bubbles, 0.09–0.15 CPI at 3–5% taken) + the B1
long-run note (§9, exact 40/40.32 ratio with Bresenham strobe beyond
~10 s, TINT-rate check as the long-run gate).

- Agent 1 (lead designer): SIGNS this converged document. All three
  fixes were verified against the C-model citations Agent 3 named
  before writing: RPTB 0xC6 2-word + `braf/pasr/paer`
  (`c5x_core.c:2402-2407`), BRCR set only by MMR write 0x09
  (`c5x_core.c:719`), RPTB 47.53% of DSP time (`c5x_core.c:2768`),
  `handle_braf` `(pc−1) == paer` (`c5x_core.c:2663`), MAC/MACD
  per-iteration `ea(c)` + `pm_rd(c, pfc)` + `pfc++`
  (`c5x_core.c:1993-2000`), `handle_rpt` (`c5x_core.c:2641`),
  `instr_cycles` 1 per repeated iteration / 2 IN / 3 OUT
  (`c5x_core.c:2617`), `apply_ar0_mirror` (`c5x_core.c:2756`),
  per-instruction cycle delta `c->cycles += instr_cycles − 1`
  (`c5x_core.c:3249`) and idle fast-forward `c->cycles = end`
  (`c5x_core.c:3216, 3233`), `delay_slot` (`c5x_core.c:1229`).
- Agent 2 (consultant): confirming the same three fixes in parallel;
  its signature is recorded when its confirmation lands.
- Agent 3 (critic): verifies this document next; agreement is
  complete when it signs.

Once all three have signed, implementation resumes per the subdivision
in §11 (audit first, blocking RTL), with the lead verifying each
landing as before. No rejected position is reintroduced by this
document.
