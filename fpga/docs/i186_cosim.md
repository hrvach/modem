# i186 co-sim — 80C186EB system wrapper + top + Verilator harness

## What this is

The 80C186EB supervisor core (worker 6, `rtl/i186_core.sv`) plus the
system wrapper (`rtl/i186_sys.sv`) and top (`rtl/i186_top.sv`), checked
against the C reference model (`c-port/c/src/cpu/i186.c` + the
machine-lite glue in `sim/i186_ref.*`) by stepping both models
instruction-by-instruction on the real SV25 firmware image and
diffing the full architectural state after every step.

## Files (worker 7 owns only these)

- `rtl/i186_sys.sv` — bus fabric + peripherals (PCB/NEC-ASIC register
  file, timers, UARTs, ICU, DSP mailbox, EEPROM, DTE, generic IO
  ports, RO-page/MMIO routing, split-word handling).
- `rtl/i186_top.sv` — wires `i186_core` + `i186_sys`; exposes the
  harness port (`h_req/h_ack/h_addr/h_rdata/h_wr/h_word/h_is_mmio`),
  config (`cyc_model`, `ud_trap`), EEPROM load, and core/sys status.
- `rtl/i186_core.sv` — worker 6's file, NOT worker 7's. Do not edit.
- `tb/tb_i186_sys.sv` — directed + random-differential unit testbench
  for the sys (232 checks).
- `tb/reference-pre-house-rules/` — frozen pre-house-rules copies of
  `i186_sys.sv` / `i186_top.sv` (equivalence reference for the restyle).
- `sim/i186_ref.h`, `sim/i186_ref.cpp` — machine-lite C glue
  (reproduces `machine.c` semantics for the modeled subset; DSP
  absent, DTE input empty). FPGA-only.
- `sim/i186_cosim.cpp` — the co-sim harness. FPGA-only.
- `sim/probe_retire.cpp` — retire-timing probe (FPGA-only scratch).
- `sim/Makefile.i186` — targets `lint-i186`, `sim-unit-i186`,
  `cosim-i186`, `synth-i186`, `clean-i186`. Run from `sim/`
  (CURDIR-relative paths).

## How to run

From `sim/`:

- Lint: `make -f Makefile.i186 lint-i186`
  (`verilator --lint-only -Wall --top-module i186_top` on top+sys+core)
- Unit TB: `make -f Makefile.i186 sim-unit-i186`
- Co-sim: `make -f Makefile.i186 cosim-i186 N=<instructions>`
  (default 200000; `C_DIR` overrides the c-port tree)
- Synth: `make -f Makefile.i186 synth-i186`
  (`synth_intel_alm -top i186_top -family cyclonev`)

## Results (2026-11-19)

### Lint

`verilator --lint-only -Wall --top-module i186_top` on
`rtl/i186_top.sv rtl/i186_sys.sv rtl/i186_core.sv`: **clean, exit 0**.
No `//` comments in worker-7 files (house rules); `default_nettype
none`; named port connections throughout; no `casex`/`casez`,
`unique`/`priority` as lint suppressors.

### Unit testbench (sys)

`tb/tb_i186_sys.sv`: **PASS, 232 checks, 0 errors**. Covers RAM
word/byte, RO-page drop, flash-ID, split word at 0x0FFFF, generic IO
port readback, DIP ports 0x12/0x14, DTE out + DSP start, mailbox h2d,
overlay burst, PCB timer + ICU, PCB UART0, EEPROM READ, RELREG, plus a
200-iteration random differential section (fixed seed 0x12345678).

### Co-sim vs the C model (real SV25 firmware)

Build succeeds. Reset state matches (CS=FFFF IP=0000 FLAGS=F002 both).

**5000 instructions clean** (`COSIM CLEAN: 5000 instructions,
C cycles=65887, RTL cycles=94218`, overhead 28331, REP folded 3465,
final CS=0000 IP=044E both, DTE 1 byte each).

**200000-instruction run: first mismatch at step 13465** (was
step 7769 before the timer fix, step 13454 before the CMP fix,
step 13458 before the byte-writeback fix below). The run now
passes the first timer interrupt (steps 13439/13440) and 13,465
instructions clean. The new stop is a **core bug, not a sys/top/
harness bug**: 0x83 fetches a 16-bit immediate (see "New core
bug" below). At the stop point both models are at CS=0000,
all registers identical; only IP (C=035A, RTL=035B) and FLAGS
(C=F206, RTL=F287) differ.

Worker 6 has since fixed the TEST bug found earlier (0xA8 added to
the IMM_8 list, 0xA9 to IMM_16, `rtl/i186_core.sv` modified
2026-11-19 14:44); the 1000-instruction run passes clean
(`COSIM CLEAN: 1000 instructions, C cycles=35887, RTL cycles=43555,
overhead=7668, REP folded=3465, final IP 0454 both, DTE 1 byte each`).

### Timer-interrupt timing fix (2026-11-19)

The 200000-instruction run used to stop at step 7769: the RTL took
a timer interrupt the C model had not reached yet (RTL SP 00EC vs C
SP 00F2, RTL PC 030C vs C PC 044A), driven by the 42,687-cycle
bus-latency overhead — the RTL's eagerly-ticking timers ran ahead of
the C model's lazily-advanced timers. Diagnosis (all measured):
Timer 0 only. Firmware writes T0 CMPA=0x7E00 (32,256 counts) at step
17 and T0 CON=0xC001 at step 22 (EN=1, CONT=1; INTEN 0x2000 NOT set,
so both models raise only S_INT3 / vector 0x0F on the hit). Period
32,256 x 4 = 129,024 cycles; C first expiry at C cycle 129,183
(step ~11,634); the RTL hit ~60 wall clocks earlier and took the
interrupt during step 7768's window. The C timer's phase reference
is the END of the timer-register write instruction (`last` = the
cycle count after the write); the RTL timer had already ticked once
by the end of the CON-write step (div=1, cnt=1) while the C timer
was at cnt=0 — a 1-count phase lead that gating alone cannot fix.

Fix (sys/top/harness only; `rtl/i186_core.sv` untouched):
- Model-time tick enable: the harness drives a new top input
  `model_tick_en`, high for exactly the C charged cycles of each
  step's window (global catch-up: the harness enables whenever the
  delivered enabled-clock count is behind the C cycle count, so an
  interrupt entry's cycles that straddle windows are caught up over
  the next few windows instead of being lost). The sys timers'
  divider and the UART TX countdown advance only on enabled clocks.
  Reset/EEPROM/HLT clocks run with tick enable off.
- Deferred timer/UART writes: timer-register writes (CNT/CMPA/CMPB/
  CON) and UART TDR writes are latched as pending at the bus commit
  and applied at the next instruction boundary, on a retire pulse
  generated in the top from `core_pc` changing (registered previous
  value, reset to 20'hFFFF0). On the retire clock the timer divider
  is set to 1 (matching the C phase: that clock is 1 enabled clock
  after the write instruction's end); a deferred UART TDR pushes
  with `tx_left <= 10*pu - 1` (idle) or `tx_left + 10*pu - 1`
  (queued). Other PCB writes stay at the commit. The top header's
  old claim ("wall clocks == charged cycles") is corrected.
- ICU same-cycle hit: the sys ICU also sets `req_r` (and
  `req_r[S_INT3]` for timer 0) on a combinational `tmr_hit_now`
  (divider at 3, cnt at lim-1, tick enabled, no pending timer write
  at that edge), one edge sooner than the registered hit pulse.
  Without it the core's finish decision and the IRQ latch race on
  the same edge and the core executes the interrupted instruction
  (the IN at 044A) before taking the interrupt; with it the core
  takes the interrupt at the JNZ's finish and skips the IN, matching
  the C.
- Harness interrupt-take alignment (`sim/i186_cosim.cpp`): the C
  step is (entry + first handler instruction) but the RTL window
  stops at the handler entry, so when both models pushed a frame
  and the C is past the entry, the harness extends the RTL window
  through the first handler instruction (Case A). Conversely, when
  the RTL took the entry in the previous window but the C has not
  taken it yet, the harness steps the C once more and extends the
  RTL through the first handler instruction (Case B). A fault or an
  INT instruction lands AT the entry, so the Case A `after.IP !=
  pc_o` check keeps it from firing there.
- `tb/tb_i186_sys.sv` updated minimally: the DUT drives
  `tick_en_i=1` and a `retire_pulse` task after each bus write.
  TB still 232/232.

Result: the 200000-instruction run now passes step 7769 and the
first timer interrupt (steps 13439/13440), reaching step 13454.

### New core bug: CMP r/m,imm writes the destination (2026-11-19)

First mismatch of the 200000-instruction run is now at step 13454,
inside the timer-0 interrupt handler: instruction `81 FF 00 20`
(CMP DI, 0x2000) at 0000:0330. CMP must not write DI, but the RTL
sets DI=E000 (exactly 0x0000 - 0x2000, the SUB result) while the C
keeps DI=0000. All other state matches (IP 0334, FLAGS F287,
SP 00DA, AX/CX/DX/BX/BP/SI identical).

Root cause (read-only inspection of `rtl/i186_core.sv`, not
modified): the CLASS_ALU_IMM_RM EXECUTE case (line ~2752) exempts
`regf == 3'd0` (ADD) from the writeback instead of `regf == 3'd7`
(CMP / ALU_CMP). `regf` is the ModRM reg field, the ALU op selector
(line 1894: `alu_op = regf`; line 1166 correctly treats
`regf_in == 3'd7` as CMP for memextra). So CMP r/m,imm (0x80/0x81/
0x83 with reg=7) writes the SUB result to the destination register
or memory, and ADD r/m,imm (reg=0) never writes. The CLASS_ALU_RM
and CLASS_ALU_IMM cases (lines 2543, 2569) check
`opcode[5:3] == ALU_CMP` correctly; only CLASS_ALU_IMM_RM is wrong.
Fix (core owner, not applied here — `rtl/i186_core.sv` is out of
this task's scope): change the line-2753 test to
`regf == ALU_CMP` (3'd7). The 5000-instruction clean run does not
exercise ADD/CMP r/m,imm, which is why this surfaced only once the
timer fix let the run reach the handler.

### CMP r/m,imm fix applied (2026-11-19)

One-line change in `rtl/i186_core.sv` line 2753, CLASS_ALU_IMM_RM
EXECUTE case: `if (regf == 3'd0)` → `if (regf == ALU_CMP)`.
Pre-fix reproduction: 200000-instruction run stopped at step 13454
exactly as above (DI C=0000 RTL=E000, all else identical). Post-fix
proof: `make -f Makefile.i186 lint-i186` clean; `sim-unit-i186` TB
232/232; `cosim-i186 N=5000` PASS clean; `cosim-i186 N=200000`
now passes step 13454 and stops at step 13458 on a NEW mismatch
(see next section). 0 `//`, max line 135 in the core.

### New core bug: byte-register writeback writes SP/BP/SI/DI (2026-11-19)

First mismatch of the 200000-instruction run is now at step 13458:
instruction `F6 D4` (NOT AH) at 0000:033D. C: AX=FDF5, SP=00DA.
RTL: AX=02F5 (AH never written), SP=FDDA. All other state matches
(IP 033F, FLAGS F287, CX/DX/BX/BP/SI/DI identical).

Root cause (read-only inspection, NOT fixed — out of scope for the
CMP task): the byte writeback pattern `gpr[rmf] <= set_byte(gpr[rmf],
rmf, ...)` indexes the 16-bit register file with the raw ModRM rm
field (`fetched_rmf = bus_rdata[2:0]`, no remap). For a byte
register rm 4-7 (AH/CH/DH/BH) that is gpr[4..7] = SP/BP/SI/DI,
not the high byte of gpr[0..3]. The read path is correct
(`get_byte`: n<4 → gpr[n] low byte, else gpr[n-4] high byte), so
the RTL computed NOT AH = 0xFD correctly, then wrote it as
`set_byte(SP=00DA, 4, FD)` = {FD, DA} = FDDA into SP. Same broken
pattern at 10 `gpr[rmf]` byte-writeback sites (lines 2551, 2760,
2781, 2796, 2933, 2981, 3090, 3201, 3212, 3261, 3263) and 3
`gpr[regf]` sites (2563, 2782, 2807) — any byte op writing
AH/CH/DH/BH corrupts SP/BP/SI/DI instead. Systemic, not a
one-line error in one case; needs a core-owner fix (remap the
register index for byte writes, e.g. `gpr[rmf - (rmf >= 4 ? 4 : 0)]`
or a byte-write helper mirroring `get_byte`).

### Byte-register writeback fix applied (2026-11-19)

Fix in `rtl/i186_core.sv` only (pre-fix snapshot in
`hidden_files/pre-fix3/i186_core/`): two new helpers next to
`get_byte`/`set_byte`, mirroring the C model's `setreg`
(i186.c:243) — `byte_gpr_idx(n)` maps a byte-register index to
its gpr entry (n<4 → gpr[n], n>=4 → gpr[n-4]), and
`set_byte_reg(n, v)` returns the new gpr value with byte v
merged in. All 15 raw-index byte-writeback sites remapped
(11 `gpr[rmf]`, 3 `gpr[regf]`, 1 `gpr[opcode[2:0]]` — the
MOV reg8,imm8 site at old line 2924, which the original bug
report missed): ALU_RM (2), ALU_IMM_RM (1), XCHG reg form (2),
MOV 88/89 + 8A/8B (2), MOV_IMM (1), SHIFT_IMM + SHIFT_1_CL
(2), MOV_RM_IMM (1), GROUP_F6_F7 NOT + NEG (2), GROUP_FE
INC/DEC (2). Word-writeback paths checked and unchanged: in
word mode rmf/regf 0-7 are AX..DI directly, so `gpr[rmf] <=
alu_r` etc. are correct. One further site in the same byte-
writeback family fixed: XCHG r/m,r memory form (old line 2787)
wrote the zero-extended memory byte over the whole 16-bit
register (`gpr[regf] <= rm_operand`, no width guard) — now
word keeps the full write, byte merges via `set_byte_reg`.
Pre-fix reproduction: 200000-instruction run stopped at step
13458 exactly as above (AX C=FDF5 RTL=02F5, SP C=00DA
RTL=FDDA). Post-fix proof: `make -f Makefile.i186 lint-i186`
clean; `sim-unit-i186` TB 232/232; `cosim-i186 N=5000` PASS
clean; `cosim-i186 N=200000` now passes step 13458 and stops
at step 13465 on a NEW mismatch (see next section). 0 `//`,
max line 135 in the core.

### New core bug: 0x83 fetches a 16-bit immediate (2026-11-19)

First mismatch of the 200000-instruction run is now at step
13465: instruction `2E 83 3E F8 00 00` (CS: CMP word [00F8],
0x00) at 0000:0354, followed by `74 05` (JZ +5). C: IP=035A,
FLAGS=F206. RTL: IP=035B, FLAGS=F287. All registers identical.

Root cause (read-only inspection, NOT fixed — out of scope for
the byte-writeback task): `decode_imm_kind` maps 0x83 to IMM_W,
and IMM_W fetches `w ? FETCH_IMM16_LO : FETCH_IMM8`. But
`decode_width(0x83) = op[0] = 1`, so the word form fetches a
16-bit immediate. The 0x83 immediate is always 8 bits
(sign-extended) — the C model fetches it with `fetch8`
(i186.c:1117-1126, "For 0x83 the 8-bit immediate is fetched").
The RTL therefore consumes the JZ opcode byte 0x74 as the
second immediate byte (imm becomes 0x7400 instead of 0x0000),
advances IP one byte too far, and computes CMP against 0x7400
instead of 0x0000 (hence CF/SF/OF set in the RTL flags).
0x80/0x82 are correct by accident (`decode_width` = 0, so
IMM_W fetches IMM8); only the 0x83 word form is broken.
0xC6/0xC7 and 0xF6/0xF7 in the same IMM_W list are correct
(their immediate width follows w). Fix (core owner): move
0x83 out of the IMM_W list to IMM_8 (0x80/0x82 may stay or
move with it — same result either way).

### 0x83 immediate-width fix applied (2026-11-19)

Fix in `rtl/i186_core.sv` only (pre-fix snapshot in
`hidden_files/pre-fix3/i186_core-0x83/`): two parts, both in the
same immediate-width error. (1) `decode_imm_kind`: 0x83 moved
from the IMM_W list to the IMM_8 list, so the word form fetches
FETCH_IMM8 (one byte, IP +1) instead of FETCH_IMM16_LO.
0x80/0x82 stay in IMM_W (correct by accident: `decode_width`
= 0, so IMM_W already fetches IMM8). (2) CLASS_ALU_IMM_RM
operand mux: the decode move alone is NOT sufficient —
FETCH_IMM8 zero-extends `imm` (line ~2511), but the C model
sign-extends the 0x83 immediate for the word form
(i186.c:1124, `(uint16_t)(int16_t)(int8_t)fetch8(c)`), so
`alu_b` is now `{{8{imm[7]}}, imm[7:0]}` when
`opcode == 8'h83 && is_word`, else `imm` as before (same
use-site pattern as the 0x6B sign-extension at line ~1957).
0xC6/0xC7 and 0xF6/0xF7 stay in IMM_W, verified correct
against the C model before changing anything: 0xC6/0xC7 fetch
`w ? fetch16 : fetch8` (i186.c:1297) and 0xF6/0xF7 TEST fetches
`w ? fetch16 : fetch8` (i186.c:1451) — their immediate width
follows w. The C cycle charge for 0x80-0x83 (`memextra`,
i186.c:543-544) depends only on reg, not on imm width, so the
fetch change does not change the charge. Pre-fix reproduction:
200000-instruction run stopped at step 13465 exactly as above
(C IP=035A FLAGS=F206, RTL IP=035B FLAGS=F287). Post-fix
proof: `make -f Makefile.i186 lint-i186` clean;
`sim-unit-i186` TB 232/232; `cosim-i186 N=5000` PASS clean;
`cosim-i186 N=200000` now passes step 13465 and stops at step
64986 on a NEW mismatch (see next section). 0 `//`, max line
135 in the core.

Note: the toolchain had vanished from the VM between the
pre-fix reproduction and the proof run (`verilator: not found`;
`dpkg -l` showed neither verilator nor yosys installed).
Reinstalled from `~/workspace/backups/toolchain-debs-2026-11-11.tar`
(`dpkg -i *.deb`, `dpkg --configure -a`, no `apt-get update`):
Verilator 5.020, Yosys 0.33 verified. The pre-fix run above
used the cached co-sim binary; the proof run rebuilt it.

### New mismatch: interrupt-boundary ordering at step 64986 (2026-11-19)

First mismatch of the 200000-instruction run is now at step
64986: `ax C=0011 RTL=0000`. Everything else matches (C and
RTL pc 0000:030D, FLAGS F206, SP 00EC, CX/DX/BX/BP/SI/DI
identical). Start of the step: pc 0000:044A, bytes
`E4 10 A8 08 75 09 2E A1` — `IN AL, 0x10; TEST AL, 08;
JNZ +9; CS: MOV AX, [moffs]`. Charge 44.

Mechanism (read-only analysis, NOT fixed — out of scope for
the 0x83 task, which is a decode-function fix): step 64986 is
an interrupt-take step, not an IN step. Charge 44 = 42
(interrupt entry) + 2 (STI, the timer handler's first
instruction at 030C), per the harness's own comment
(`sim/i186_cosim.cpp`, interrupt-take alignment). Both models
took the same timer interrupt (SP 00EC = 00F2 - 6 in both) and
both executed STI, landing at 030D. They differ on what
happened to the pending instruction at 044A first: the C
model's `i186_run(cpu, 1)` does do_int BEFORE the next
instruction, so it took the interrupt without executing the
IN — AX stays 0011. The RTL core takes interrupts at an
instruction boundary, i.e. at the FINISH of the current
instruction (`rtl/i186_core.sv` header, INTERRUPTS, and the
`finish_boundary` logic), so it executed `IN AL, 0x10` first
and then took the interrupt. The IN has a visible side
effect: port 0x10 reads 0x00 in both models (C glue
`machine.c:811` sets `port_in[0x10] = 0x00` and nothing ever
writes it again; the RTL sys returns 0x00 too, since RTL AX
ends 0000), so the RTL's AL goes 0x11 -> 0x00 (AX 0011 ->
0000) while the C's stays 0011. One-instruction ordering
skew at the interrupt boundary, exposed because the pending
instruction is an IN with a register side effect. Same family
as the step-7769 timer divergence (timer firing vs C-cycle
accounting), now in its residual boundary-ordering form: the
timer fired at a C-cycle boundary that falls before the IN in
the C model and after the IN in the RTL. Fix belongs to the
timer/interrupt-timing owner (sys/top or harness alignment),
not the core decode: the core is behaving as documented
(interrupts at instruction finish), and the C model's
do_int-first step is a modelling choice the harness already
papers over in both directions (`sim/i186_cosim.cpp`
interrupt-take alignment, Cases A/B) — this case slips
through because the extra executed instruction changes
architectural state before the entry. Do NOT "fix" by making
the IN a no-op or by suppressing the interrupt; the models
must take the same interrupts at the same instruction
boundaries with the same side effects.

### Synth (Cyclone V)

`synth_intel_alm -top i186_top -family cyclonev` was **blocked** on
worker 6's core not parsing under Yosys 0.33 (double-index form
`gpr[REG_DX][15]` in 22 places). Worker 6 has since fixed that
(22 places refactored to an intermediate variable, verified by lead
grep 2026-11-19), so the blocker is gone — but the full-top synth
has NOT been re-run yet, so no full-top stat exists.

Sys-only synth (`synth_intel_alm -top i186_sys -family cyclonev`,
`sim/synth-i186-sys-only.log`): **24,012 cells** — MISTRAL_ALUT2
1840, ALUT3 2010, ALUT4 4102, ALUT5 3805, ALUT6 2533, ALUT_ARITH
477, FF 8759, IB 268, OB 181, NOT 36, CLKBUF 1; **0 memories, 0
memory bits, 0 MISTRAL_M10K, 0 MISTRAL_MUL (DSP)**. The small RTL
register files (`pcb_w`, `ports_w`, `h2d_w`, `burst_tmp`, `ee_w`,
timer/UART/ICU arrays) have combinational reads and map to
logic/FFs, NOT M10K — Yosys reports them as "Replacing memory with
list of registers", which is the expected and intended result. The
1 MB RAM stays in the Verilator harness, never in M10K. (The sys
synth took ~21 min wall under CPU contention with other workers'
Yosys runs; the cell counts are from the completed run.)

## Stepping model (harness)

- C side: `i186_run(cpu, 1)` per step (one instruction, one REP
  iteration, or one interrupt entry). `ST_STOP` (4) is treated as a
  normal step: the glue calls `i186_stop()` from inside a hook
  (PCB timer/UART/ICU write) to end the driver's run chunk; the
  instruction executed fully.
- RTL side: clocked until the core starts the next instruction
  (`pc_o` changes) or a timeout of `charge*4 + 1000` clocks. The
  timeout scales with the charge because a REP accumulates many
  iterations, each costing bus-latency overhead on top of its C
  charge. `pc_o` does not change for a jump-to-self, so the timeout
  path covers it (state is compared anyway).
- Architectural IP is `pc_o` (instr_start_pc, the linear PC of the
  instruction currently being fetched), NOT the core's `ip`
  register: `ip` is the fetch pointer and has already advanced past
  the opcode of the instruction `pc_o` points at.
- REP: one C step is one iteration (IP stays at the instruction
  start, CX decrements). The harness accumulates C iterations until
  the IP moves, then clocks the RTL once for the whole REP (the RTL
  core executes a REP internally). REP iterations do not consume the
  step budget (cap 65536).
- Cycles: the RTL wall clocks run ahead of the C charged cycles by
  the bus-latency overhead (KD-13: the sys bus latency is ~4 clocks
  per harness transaction, which exceeds the Table D-2 charge for
  short instructions). Cycle equality is therefore NOT required;
  the cumulative overhead is tracked and reported (3819 cycles over
  the 259-instruction run, ~12.6%). All other fields are compared
  exactly.
- A pre-step check reports a DESYNC if RTL `pc_o` does not equal the
  C IP before a step (the models were already out of sync, not
  because of this instruction).
- Interrupts are handled entirely by the sys/top (ICU offers, top
  pulses `irq_i`, core latches and takes it, top derives `irq_ack`
  from the IVT read). The harness does not inject interrupts; it
  only drives the outside-world inputs (line idle-high, no DTE RX,
  no NMI).
- Model time: the sys timers and UART TX countdowns advance only on
  `model_tick_en` (driven by the harness, exactly the C charged
  cycles per step, global catch-up so interrupt entries that
  straddle windows are not lost). Timer/UART register writes are
  deferred to the next instruction boundary (retire pulse from
  `core_pc` changing). The harness aligns interrupt takes that
  straddle the C-step / RTL-window boundary (Case A: C took it
  first; Case B: RTL took it first). See "Timer-interrupt timing
  fix" above.
- HLT and BADOP stop the run with a report. DTE bytes are compared
  at the end of a clean run.

## Bus latency (sys FSM)

Per harness-routed transaction: 4 clocks (ST_IDLE latch + `h_req`,
ST_HWAIT for `h_ack`, ST_ACK asserting `bus_ack`, ST_TURNAROUND
while the core samples it). ST_EXEC is skipped for harness-routed
phases. The core may re-assert `bus_req` immediately (it is
combinational from its FSM state, so there is no guaranteed low gap
between back-to-back transactions); the sys therefore does NOT wait
for `bus_req` to drop — after asserting `bus_ack` it spends exactly
one cycle in ST_TURNAROUND, then returns to ST_IDLE. The earlier
ST_WAIT_LOW design (wait for `bus_req` low) deadlocked the core and
was replaced.

## Interface deltas vs worker 6's core (as built)

The top was written against the core's published port list and
matches it as landed:

- Bus: `bus_w` (not `bus_word`); `bus_req`/`bus_addr[19:0]`/
  `bus_wr`/`bus_w`/`bus_io`/`bus_wdata[15:0]`/`bus_ack`/
  `bus_rdata[15:0]`. Bus_req held until ack; a word access is ONE
  word transaction even across a 4 KB page boundary (KD-10 — the sys
  owns the C split-word rule).
- Config: `cyc_model_i` (0=flat 4, 1=Table D-2), `ud_trap_i`
  (1=bad opcode raises INT 6). Glue defaults 1/1.
- Interrupts: `nmi_i`/`irq_i` are edge-latched in the core;
  `irq_vec_i` latched on the edge; `irq_clear_i` is a level that
  clears a pending IRQ. The top pulses `irq_i` for one clock when
  the sys offer rises or the offered vector changes, and drives
  `irq_clear_i = !irq_req`. `nmi_i` is the harness level passed
  through (firmware never uses NMI; harness ties it low).
- Status only: `cycles_o[63:0]`, `halted_o`, `st_badop_o`,
  `badop_pc_o[19:0]`, `badop_o[7:0]`, `pc_o[19:0]`
  (= `instr_start_pc`). No register observation outputs, no
  `instr_retire` pulse, no `int_entry`/`irq_ack` output. Register
  observation is via the core's `/*verilator public*/` signals
  (`gpr`/`sreg`/`ip`/flag bits/`cycles`) read by the harness.
- `irq_ack` derivation (in the top): the core has no
  interrupt-taken output, but its entry sequence is architectural
  (push FLAGS/CS/IP, read IVT IP slot at vec*4, read IVT CS slot at
  vec*4+2). The top watches the bus for a word read of the IVT IP
  slot of the latched vector (`bus_addr == {10'b0, irq_vec_latched,
  2'b00}`) that is acknowledged, while an interrupt is offered, and
  pulses `irq_ack` (with `irq_ack_vec`). Exactly one ack per entry.
  Residual edge case (KNOWN-DIFF): a software INT n whose vector
  equals the offered external vector, while an external IRQ is
  offered, acks the external IRQ early; the take order is unchanged.

## Stub list

Only the ports/registers the firmware actually touches are modeled
(enumerated from `machine.c` by probe runs). Anything else is a
documented stub: reads return the C model's fallback value, writes
ignored.

- DSP absent: mailbox reads return "no DSP" values, port 0x18 reads
  0x03, a write of 4 to port 0x18 (start DSP) is recorded and
  ignored. No c5x core is attached in this co-sim.
- DTE input empty: no characters are ever fed to UART0.
- DMA: the 80C186EB DMA channels are not modeled (the firmware does
  not use them in the boot/idle path exercised here).
- The 1 MB RAM lives in the Verilator C++ harness behind the top's
  `h_*` port, never in M10K.

## KNOWN-DIFFs

- **Bus latency vs charge (KD-13)**: RTL wall clocks exceed the C
  Table D-2 charge for short instructions (~4 clocks per harness
  transaction). Cycle equality is not required; the overhead is
  tracked and reported. The timer divergence this used to cause is
  FIXED 2026-11-19 (model-time tick enable + deferred writes, see
  "Timer-interrupt timing fix" above); the bus-latency overhead
  itself remains, but it no longer shifts interrupt timing.
- **Harness glue at instruction granularity**: `iref_service`
  (timer lazy-update + UART TX completion + ICU eval) runs after
  each C step, mirroring the production driver's `machine_run`
  loop at instruction granularity instead of sample granularity.
- **Eager vs lazy timers/UARTs — FIXED 2026-11-19**: the RTL sys
  used to advance its timers eagerly (every clock / every 4 clocks)
  and its UART TX down-counter eagerly, while the C model advances
  them lazily. The model-time tick enable + deferred timer/UART
  writes (see "Timer-interrupt timing fix" above) align them: the
  sys peripherals now advance on model time, and the first timer
  interrupt is taken at the same instruction boundary in both
  models. The 1-tick phase difference in CNT readback is gone
  (deferred writes apply at the retire, matching the C phase).
- **CMP r/m,imm core bug (2026-11-19, FIXED)**: the core's
  CLASS_ALU_IMM_RM EXECUTE exempted `regf == 3'd0` (ADD) from the
  writeback instead of `regf == 3'd7` (CMP). One-line fix
  (`regf == ALU_CMP`), proof: 200000-instruction run passed step
  13454. See "CMP r/m,imm fix applied" above.
- **Byte-register writeback core bug (2026-11-19, FIXED)**: byte
  ops writing AH/CH/DH/BH corrupted SP/BP/SI/DI instead
  (raw rmf/regf index into gpr). Fixed with `byte_gpr_idx` /
  `set_byte_reg` at all 15 set_byte sites plus the XCHG memory-
  form width guard. Proof: 200000-instruction run passed step
  13458. See "Byte-register writeback fix applied" above.
- **0x83 immediate-width core bug (2026-11-19, FIXED)**: 0x83 was
  mapped to IMM_W, so the word form fetched a 16-bit immediate;
  the 0x83 immediate is always 8 bits. Two-part fix
  (`decode_imm_kind`: 0x83 to IMM_8; CLASS_ALU_IMM_RM: sign-extend
  `imm` for 0x83 word form). Proof: 200000-instruction run passed
  step 13465, stops at step 64986 on the interrupt-boundary
  ordering mismatch below. See "0x83 immediate-width fix applied"
  above.
- **Interrupt-boundary ordering mismatch (2026-11-19, open)**: at
  step 64986 the C model takes a pending timer interrupt BEFORE
  the pending `IN AL, 0x10` at 044A, while the RTL executes the
  IN first and takes the interrupt at the instruction's finish
  boundary — AX differs (C 0011, RTL 0000), all else identical.
  Same family as the step-7769 timer divergence, residual
  boundary-ordering form. Fix belongs to the timer/interrupt-
  timing owner (sys/top or harness alignment), not the core
  decode. See "New mismatch: interrupt-boundary ordering at
  step 64986" above.
- **Timer cmpa lowered below cnt**: if firmware lowers `cmpa`
  below the current count, the RTL wraps to the next period; the C
  model's behaviour in that corner was not probed.
- **IRQ-ack derivation**: see "Interface deltas" (residual edge
  case with a software INT n equal to the offered vector).
- **REP accumulation**: REP iterations are folded into one RTL
  clocking; per-iteration state is not compared, only the final
  state after the REP.
- **Cycle scale**: the C `i186_set_cycle_scale` factor (glue
  default 1.0) is not modeled (KD-14).
- **HLT cycle burn (KD-5)**: on HLT the C run loop burns the whole
  remaining budget while the RTL freezes its cycle counter; the
  harness reports the halt and the state, not a cycle comparison.
- **IDIV overflow (KD-3)**: the C host dies with SIGFPE on
  DX:AX=0x8000:0x0000 by -1; the RTL raises INT 0 instead.
- **Yosys casts**: Yosys 0.33 does not parse SystemVerilog casts
  (`int'(...)`, `N'(...)`). The sys was rewritten to use explicit
  zero-extension concatenations (`{24'b0, x}`) and a `case` on
  `regno[7:3]` for the timer index; behaviour is unchanged (TB
  still 232/232, lint still clean). The core still contains
  `gpr[...][...]` double-indexing that Yosys 0.33 rejects (see
  Synth above).
- **`placeholders_i186.sv` deleted** 2026-11-19: the stub core is
  gone now that the real `rtl/i186_core.sv` has landed. Do not
  build on it.
- **House rules**: worker-7 files use `/* */` block comments only,
  150 columns max, one statement per line, one port connection per
  line (aligned), `typedef enum` FSM states, localparams with a
  source comment for magic numbers. Worker 6's core still uses
  `//` comments throughout (retrofit is worker 6's / the lead's
  call).

## Anything unverified

- The full-top Cyclone V stat (blocked on the core's Yosys parse
  issue; sys-only stat is in the Synth section above).
- Co-sim beyond step 64986 (blocked on the interrupt-boundary
  ordering mismatch; see "New mismatch: interrupt-boundary
  ordering at step 64986" above).
- Timer/UART/ICU interrupt timing over a long run: the first timer
  interrupt is now aligned (steps 13439/13440, taken at the same
  instruction boundary in both models). Timing across many
  interrupts (second and later timer hits) is unverified — the run
  now reaches step 64986, where a later timer hit exposes the
  boundary-ordering difference above.
- The `docs/i186_cosim.md` synth numbers will be filled in once
  the sys-only synth finishes.
