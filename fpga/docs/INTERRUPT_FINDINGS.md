# C5x RTL interrupt / ARP findings (fuzz agent report)

Source: subagent report, written here by me because the agent did not write the file. Files named below live in the session scratchpad `rtltest/`; the original `rtl/` and `tb/` were not edited.

## Root cause (verified without interrupts)
LST #0 / LST #1 write ARP through ST0/ST1, but the D-stage ARP interlock (`c5x_ctrl.sv` ~1070, `d_h1_arp_w`) only fires on `wr_arp_sw`. That signal comes from the descriptor ARP switch (`c5x_addr.sv` `o_d_wrt_arp_sw`). An indirect instruction decoded right behind LST #0 therefore reads a stale `arp_q` (both the descriptor AR id and the address AR).

- Probe `probe_lst_hazard.py`: `LST #0 0x38; SACL *+` with ARP0=3 increments AR3 on the original RTL and AR0 on the fixed RTL. `LARP` followed by `SACL *+` is correct on both.
- RPTB repro `repro_rptb_irq.py` (`trace_int.py` gives the per-clock trace): `LAR AR3,*BR-` (03CD) after `LST #0` (0E38) is decoded with descriptor AR id 3 in the baseline (stale ARP). After RETE the interrupted run re-decodes it with ARP=0, so AR0, ARCR and INDX get zeroed.
- The interrupt only flushes and re-decodes, so the baseline is the wrong one.

## Candidate fix (tested against the vectors and the repro only)
`rtltest/fix_arp_lst.diff`, patched copy `rtltest/rtl_fix/c5x_ctrl.sv`:

```
-        d_wrt.wr_arp_sw = d_wrt_arp_sw_i;
+        d_wrt.wr_arp_sw = d_wrt_arp_sw_i || d_is_lst0 || d_is_lst1;
```

## Verified
- `run_tests.py`: 669/669 on the original and the fixed lib (`RTL_LIB=librtl_fix.so`).
- `repro_rptb_irq.py`: baseline and every interrupt offset 1-8 agree (ARCR/AR0/AR3 = 0).
- `probe_lst_hazard.py`: LST #0 then SACL *+ increments AR0 with the fix.
- `recheck.py`: 3 of 13 minimised fuzz records disappear (all seed-36).

## Not verified
- Agreement with the C model (only the vectors were used).
- Full fuzz regression on the fixed lib (seeds 24-71 were killed at about seed 54).
- RETE restore writes ARP through ST0, not via `wr_arp_sw`, so it probably has the same hazard class. No interlock added, untested.

## Unexplained (10 of 13 records remain)
- Clob records, seeds 38 and 42: memory differences with no LST involved; one has an XC window.
- Several ar5 records: probably harness artifacts (that ISR changes AR5 permanently and RETE does not restore ARs). Not verified.
- One record with TREG/AR4 differences.

## Spec deviation (no reproducer)
`c5x_ctrl.sv:991` `d_wrt.wr_brcr = d_is_rptb || ...` contradicts OPEN-2 (RPTB must not load BRCR).

## Repro
`rtltest/`: `repro_rptb_irq.py`, `recheck.py`, `probe_lst_hazard.py`, `trace_int.py`, `trace_retire.py`, `fix_arp_lst.diff`, `rtl_fix/`, `librtl_fix.so`, `mismatches_before/`.

## EINT inhibit one instruction too long (found later, fixed)
Report: a nested interrupt in an ISR that starts with EINT was taken one instruction late (after the second instruction after EINT, not the first), so the 1-deep shadow saved the ISR's ACC.
- Repro: `rtltest/nested_eint.py` (ISR = EINT; LDP; LACK #0x55; ...; INT1 and INT2 together). C model (`nested_c.c`, built against ~/Programming/courier/src/dsp/c5x_core.c) ends with ACC 0x40 at every arrival offset; the RTL ended with 0x55 at all of them (not only a narrow window).
- Cause: `int_inh_q` (set at EINT's retire) blocked the entry decision at the next retire too. Per C (`interrupt_inhibit`, consumed by the check after EINT itself) only EINT's own boundary is blocked.
- Fix (`rtl/dsp/c5x_ctrl.sv`, `int_held_w`): the `int_inh_q` term is replaced by a term for EINT retiring (`BE40`), like the existing DINT term. 669/669, interrupt fuzz 60 seeds 0 mismatches, repro_rptb_irq unchanged.
- Note: at main level the C model itself takes the interrupt right after EINT (ISR saw ACC 0x40, `nm_c.c`), where the TI manual and the C nested case say after the next instruction. After the fix the RTL follows the manual / the nested C case (ACC 0x10 in `nested_main.py`).

## INTR vector taken from live signals (found later, fixed)
Report: the entry vector for a software INTR was computed from `entry_is_intr_w` / `entry_idx_w`, which describe the instruction retiring now, but the vector is used two clocks after the INTR retired (when another instruction retires), so it came out as 0 and the core entered at address 0 (harmless only while address 0 holds NOPs).
- Repro: `rtltest/intr_vec.py` (INTR #4 with a decoy handler at address 0; the real one at 0x0008 stores 0x77). Before: the decoy ran (0x11). After: 0x77.
- Fix (`rtl/dsp/c5x_ctrl.sv`, entry vector logic): use `entry_is_intr_q` / `entry_idx_q` (latched with the entry). 669/669, interrupt fuzz 50 seeds 0 mismatches.
- Open: the hardware-interrupt branch of the same vector logic (`int_sel_w` / `int_sel_found_w`) is also computed live. Not shown to be wrong (no repro); worth a test where IFR changes between detect and entry.
- The second reported bug (nested interrupt one instruction late) is the EINT inhibit fix above. The worker's suggestion there (never set the inhibit at EINT retire) would also let an entry happen at EINT's own boundary when INTM is already 0; the fix applied blocks it, like C.

## Reported, not patched
- Bug 3, one main instruction runs after RETE before a pending interrupt is entered. Reproduced (`rtltest/rete_pend.py`, C: `rp_c.c`): C model 0 instructions between A's RETE and B's entry, RTL 1. Not patched: which side matches the real chip is open (a 22-cycle timer starves the C model forever, the RTL always makes one instruction of progress), and the Courier timer period (~17000 cycles) cannot hit the starvation. A fix would move the INTM restore earlier in the RETE restore sequence (`rst_ph_q`, `retiring_rete_w`).
- Bug 4, timer fires while the timer registers are being written: RTL applies the register write at retire, C at execute, so the entry and the reload differ by one instruction (timer 7 behind afterwards). Not patched, no firmware impact seen (the timer is set up once with interrupts off).

## Bug 3 patched (one main instruction ran after RETE before a pending interrupt)
Manual (SPRU056D 4.8.9) only guarantees that the instruction after CLRC/SETC INTM (EINT) runs before a pending interrupt; it says nothing about RETE with an interrupt already pending. The C core checks right after RETE (INTM cleared, `interrupt_held` false), so the RTL now matches it.
- Cause (traced with a $display build, `rtltest/trace_rete.py`): the RETE retires first, while INTM is still 1; its 8-phase context restore runs after it with E empty and clears INTM only at the last phase, so the pending interrupt was detected at the next main instruction's retire.
- Fix (`rtl/dsp/c5x_ctrl.sv`): `retiring_rete_w` is now "the RETE restore is at its last phase" (E is empty), `entry_detect_w` also fires then, and the return PC is the RETE's target (`rete_tgt_q`, latched at the RETE retire).
- Checks: `rtltest/rete_pend.py` 0 instructions between A's RETE and B's entry at all arrival times (C: 0); 669/669; interrupt fuzz 60 seeds 0 mismatches; recheck.py unchanged (10/13); earlier repros (nested EINT, INTR vector, RPTB) unchanged.

## Bugs 6 and 7 (reports from other workers)
- Bug 6 (MACD/MADD data move writes into program memory): NOT reproduced. `rtltest/macd_gate.py` (RPTK 1; MACD/MADD *+ with AR1 stepping 0x7E -> 0x7F -> 0x80) gives identical results in the RTL and in C (`cmacd.c`): pm[0x80] untouched, dm[0x7F] moved. The loop path already goes through the `dmov_gate_f` gate (`e_dmov_o` -> `i_e_dmov` in c5x_mem.sv).
- Bug 7 (peripheral data reads cost too few cycles): reproduced and fixed. C routes data 0x50..0x5F (MMR_IO_WINDOW) through io_read/io_write, which charge the IOWSR/CWSR wait states; `LACC 0x5F` cost 8 model cycles in C and 1 in the RTL (`rtltest/periph_wait.py`, `cpw.c`). `c5x_ctrl.sv`: `e_dm_host_rd_w` / `e_dm_host_wr_w` now also cover data 0x50..0x5F (besides the host window 0xFF50..0xFF5F). RTL now 8; vectors 669/669.

## Bugs 8-11 (reports from other workers), all checked against the C core
- Bug 8 (INTR entry): the vector part was the Bug 1 fix; the rest was a 4-cycle entry pulse charged on top of INTR's own 4 (`rtltest/cyc_bugs.py`: C 9 cycles, RTL was 13, now 9). `c5x_ctrl.sv`: `entry_cyc_w` = 0 for an INTR entry (cycles_q, retire_cycles_q, model tick).
- Bug 9 (first iteration of a repeated 2-word instruction): RTL charged 1 instead of the full count (C 6, RTL was 5, now 6). New `rep_first_q` (set when the RPT retires, cleared at the next retire); `base_cyc_q` uses `dec_cycles` for a 2-word instruction on that first iteration.
- Bug 10 (return at 0xFFFF): the return executor never assigns `ex_pc_tgt` (stayed 0), so 0xFFFF+1 = 0 looked sequential and the taken return was charged 2 (C 8, RTL was 6, now 8). `post_pc_w` takes the popped word (`pop_data`) for PC_RET.
- Bug 11 (reserved indirect modifier m = 6/7): C sets RUN_BADOP; the RTL ran it. `c5x_addr.sv` new output `o_d_ea_badop` (`i_d_ea_use && ea_indirect && mode == DESC_BADOP`), ORed into `dec.badop` in `c5x_core.sv`, so the existing halt-on-BADOP path handles it (`rtltest/badmode.py`: ADD/SUB/LACC/MPY halt like C, the legal `*+` does not).
- Correction to Bug 6: my first loop test used the wrong RPT opcode (0xCC02 is not a repeat; RPT #k8 is 0xBB). Redone with 0xBB: still no difference between the RTL and C for MACD/MADD loops.

## Bugs 12-14 (reports from other workers), fixed, and the regression suite
- Bug 12 (SST stores ST0 before the ARP switch of the same instruction): `c5x_ctrl.sv` SST #0 stores `desc.new_arp` when the descriptor switches ARP; SST #1 stores the old ARP in ARB then (C `set_arp`).
- Bug 13 (peripheral-register write missing its extra cycle on LMMR / TBLR / BLDD): `e_dm_periph_wr_w` also covers those three when the destination (`ea_q`) is 0x20..0x4F. C: 3 / 4 / 4 cycles.
- Bug 14 (SMMR / LMMR read 0 from live sources): the loop engine took `r_data_i`, which is "no data" for a deferred read (live registers, host window). It now presents the source to the E read port (`loop_def_rd_w`, `loop_def_addr_w`; LMMR reads at its pfc address) and uses `e_rdata_i`. The value read can be a few timer ticks off C (the RTL's timer ticks at retire), the point is that it is no longer 0.
- Regression suite: `tests/dsp_regress/` (`build.sh`, `dsp_regress.py`, `rtlshim.cpp`): one self-checking test per fix (ARP/LST, nested EINT, INTR vector, RETE with pending interrupt, INTR cycles, first-iteration RPT cycles, return at 0xFFFF, reserved indirect mode, peripheral read cycles, SST ARP, peripheral write cycle, SMMR/LMMR live sources, plus a MACD guard). Expected values are what the C core gives for the same program. 13/13 pass; 9 fail on the older RTL build, as they should.

## RETD with push/pop in the delay slots: fixed, then REVERTED (it broke the firmware on the board)
The fix (return address read after the last slot word; double pop; `pop2` port in c5x_addr/core/ctrl) matched C on the test programs and passed 669/669 + fuzz, but bitstreams with it (`s` dev, `t` full) no longer answered V.8 on the board (the DSP stayed in its listening state; with an identical recorded input the previous build answered with CM and INFO0). In the traced firmware none of the 16 executed RETD sites has a stack operation in its slots, so the intended semantic change is not what broke it; a side effect of the wiring is suspected, not found. Reverted. Both tests stay in tests/dsp_regress as known issues; do not re-apply without a replay on the board (feed.py with a recorded RX) and a differential run over the recorded trace.

## Bugs 20-28 (reports), state
- 20 (write snoop used the data range for program-space SARAM writes): fixed (c5x_core.sv), test `snoop_reports_the_real_destination`.
- 21 (I/O window write wait states): already fixed with bug 7; test `io_window_write_wait_states`.
- 22 (loop engine and RPTC as LMMR destination): reproduced (the RTL never finishes the program), not fixed.
- 23 (sticky interrupt ack): NOT reproduced (shim now has an I/O stall, `r_io_delay`; swept stall 0-12 x TINT arrival 0-23 with LACC *+; whenever the ISR ran the flag was cleared). Needs the worker's exact repro.
- 24 (repeat keeps the first iteration's AR), 26 (timer prescaler after a TCR write): not yet checked.
- 25 (BRAF stuck after a block ending in a PMST store): fixed (c5x_addr.sv `braf_done_q`), test `pmst_store_in_the_last_block_word`.
- 27 (timer read one tick high after a 2-cycle instruction): reproduced (C 0xFFFD, RTL 0xFFFE), not fixed (retire-time tick queue).
- 28 (MAC/MADS read a stale value from a peripheral): already fixed by the loop engine's deferred read (bug 14); test `mads_reads_the_live_peripheral_not_a_stale_value`.

## Bug 29 (report: after the ov6 load the RTL leaves the IDLE park at 0x810A, C stays)
Not reproducible here. The code is the DSP's wait-for-command loop: `CALLD 0x23F0` (the trampoline `LACC *; LAMM *; RET` in SARAM) with AR1=0xFF57 reads the host status twice (host-window alias 0xFF57, then port 0x57 through the page-0 mask), then `ANDK #0x0200; BNZ 0x810B`. In this repo's glue (`dsp_glue.sv`) the DSP-side status read (port 0x57) returns only bits 0..2 (`{!data_full, !d2h_valid, h2d_pending}`), so bit 9 is never set, and the mailbox reads (0x58..0x5F) have no read side effects (decoded by the low byte only), so a duplicated or stale read cannot desynchronise the overlay download here. The worker's soak supplies its own host model; needs its `probe12.py` / cmd 30 repro to look at the stale value they see.

## Bug 29 re-run with the worker's bundle (scratch/bug29-repro.zip)
The bundle's .so files are x86-64 (this machine is aarch64) and test an older tarball of the RTL, so `probe12.py` itself cannot run here. Its scenario was reimplemented from `soak3.py` (host model, the 30 setup commands, ov6 at 0x9D00, overlay load, 60 ticks), once on the C core (`c29full.c`) and once on the RTL through `tests/dsp_regress/rtlshim.cpp` (`bug29_rtl.py`, with the new `r_ser_tick` / `r_set_ivec_ind` / `r_io_wr_*` shim calls): current rtl/dsp: parked at 0x810A after the overlay load and for all 60 ticks, 0 differences in PC / IDLE / AR0 / BMAR; RTL from commit f3e3b64 (before the 14 fixes of 2026-11-22): one transient tick (t8: pc 0x80FB, not idle) that recovers, never the reported entry into the 0x811F..0x812F block with PASR/PAER 0x8125/0x812F. Not reproduced; most likely the older RTL of the tarball or a difference in their step/interrupt protocol.

## Bugs 30-33 (reports)
- 30 (LDP *,ARn drops the ARP switch): reproduced, fixed (c5x_ctrl.sv, `st0_ld_data_o` folds in `desc.new_arp`), test `ldp_keeps_its_arp_switch`.
- 31 (OPL/XPL/APL to an I/O address writes nothing) and 32 (IN to an I/O destination): reproduced (C logs 1 I/O write, the RTL 0). Cause: the memory block performs one I/O transaction per instruction (the read), the second (the write) is dropped. Not fixed: the firmware contains no OPL/XPL/APL and no IN. Known-issue tests.
- 33 (LMMR into RPTC hangs; same as the earlier bug 22): reproduced, not fixed (no LMMR in the firmware). Known-issue test.

## Bug 34 (hardware): DSP halts on a BADOP after an interrupt preempts a repeated instruction (found 2026-11-22 with the H= heartbeat probe)

**Symptom.** In failing calls the codec frame counter stops after V.8 / during V.34 phase 1-2 while the 186 side keeps running. The heartbeat (build `Modem_20261122v`/`w`) shows the DSP **halted**:
`G=...` last byte has bit 4 set (halted), and `H=<PC><opcode>` (new, latched at the first BADOP) names the instruction that halted it.

| call | build | halted | PC at halt | notes |
|---|---|---|---|---|
| v1 | v (full, with Copilot's preemption fix) | yes | 0x0002 (heartbeat Q), INTM=1 | H= not yet available |
| w1 | w (dev) | no | - | reached V.34 phase 2, retrained, NO CARRIER |
| w2 | w | no | - | V8_ANS_TIME_OUT_WAITING_FOR_CM |
| w3 | w | **yes** | H=017924B1: PC 0x0179, opcode 0x24B1 | wild jump into low memory; INTM=1 |

So the halt is real but intermittent; the call outcome varies with it (V.8 results differ run to run on the same build).

**What precedes it (DDR trace, calls v1 and w3).** The ROM interrupt handler at 0x8189..0x81AA (`... LAMM 0x6B; ORI *+; SAMM 0x21; SAR AR7,0x10; LAR AR7,0x11; SXF; LAMM 0x6B; SUBK #3; BZ; ZAC; SAMM 0x6B; RETE`) was entered while the main code was inside a **single-instruction repeat**:
- v1: `RPTK #0x0E; NORM *-` (0x8BE8..0x8BE9)
- w3: `RPTZ #1; SACL *+` (0x9C12..0x9C14)

The trace never shows the handler's `RETE` retiring, and after it the core executes at a wild PC (0x0002 / 0x0179), runs into an invalid opcode and halts (`c5x_ctrl.sv`: `halted_q`, BADOP in E; no instruction fetch from the halted core, so the frame clock stops with it).

**Suspects.** The return address pushed at the interrupt entry when it lands inside a repeat, or the repeat state (RPTC / repeat-pending) not restored by RETE, or a stale PFC/pc after RETE (the area of bugs 8-11 and Copilot's "preemption of higher priority" fix, which does not cover this).

**Not reproduced yet.** A directed test in tests/dsp_regress (the real handler words from the firmware ROM at 0x8189.., interrupt arriving at delays 0..15 in `LRLK AR1; RPTZ #1; SACL *+`) did not even reach the handler, so it proves nothing; the harness needs the interrupt delivered like the AIC does (see tests for bugs 28-33). **Next:** differential test against the C core (scratchpad/courier_copy) for an interrupt at every cycle inside RPTK/RPTZ + NORM/SACL/MAC, compare PC / stack / RPTC after RETE.

**Side note (analysis mismatch found by a second agent).** The `ABF9..AC08 = MAC 0xFE34` attribution in docs/OPS.md describes the base DSP image, not overlay 6: in overlay 6 that range is `per_sample_filter2_ABBB` and 0xABFE is `MPYI *0+`. The call5 trace therefore does not show the MAC-mapping bug active in that call.

### Bug 34 - root cause and fix (2026-11-22)
Reproduced with a C-vs-RTL sweep (interrupt arriving at every clock; EINT; `LRLK AR1,#0x263; RPTZ #1; SACL *+`; handler `SAR AR7,0x60; RETE`, AR7 = 0x5A5A): the RTL took the entry **between the RPT instruction and the instruction it repeats** (the C core runs RPT plus all iterations as one step, "a single-instruction RPT repeat is not interruptible on the real C5x", so it never does). The handler then ran with `rptc > 0` still set, and `ar_rd_sel_o` (c5x_ctrl.sv, `rptc_i > 0` term) selected the replay AR instead of the SAR field: the handler's `SAR AR7,0x10` stored AR1, its later `LAR AR7,0x11` restored that into AR7 (the frame pointer the firmware keeps in 0BD0..0BDF), and the main code ran off into low memory -> BADOP -> halt -> no more codec frames. That is the AR7-escape the crash trap was built for.
Fix: `int_held_w` also holds while the RPT instruction itself is in E (`re_i.valid && re_i.dec.is_rpt`), like the EINT/DINT terms. Test: `interrupt_not_between_rpt_and_repeated_insn` (fails on the old RTL, passes now); 669/669 vectors and the 21 regression tests pass.
The C core's atomic `while (rptc > -1)` loop is a speed trick; what the RTL must keep from it is the *semantics* (no entry at the RPT's retire nor between iterations), not the structure.
