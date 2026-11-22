# DSP bug finding: hardware interrupt vector race

Found 2026-11-22 while investigating the DSP's runaway-PC failure during
handshake.

## Root cause

The DSP control logic delayed interrupt entry by two clocks after detecting an
eligible hardware interrupt. At detection, it latched the selected interrupt
index in `entry_idx_q`, and used that saved index later to acknowledge the
interrupt. However, the vector address was calculated from the live
`int_sel_w` priority encoder at entry time.

If a higher-priority interrupt became pending during that two-clock interval,
the core acknowledged the originally accepted interrupt but branched to the
new interrupt's vector. The wrong handler could then corrupt DSP state or
derail firmware execution.

This differs from the C reference's `check_int`: it snapshots `ifr & imr`,
chooses the lowest pending index, and uses that same index for both the
vector address and flag clear in one atomic entry.

## Reproduction

The directed regression starts with hardware interrupt index 2 pending and
interrupts enabled. Once the core detects it, the test sets index 1 pending
before the entry vector is consumed. The accepted interrupt's vector is
`0x0006`, but the unfixed RTL fetched from `0x0004` (the newly higher-priority
interrupt's vector).

The regression is `hardware_interrupt_vector_is_latched` in
`tests/dsp_regress/dsp_regress.py`.

## Fix

`rtl/dsp/c5x_ctrl.sv` now generates a hardware interrupt vector from the
latched `entry_idx_q`, only while the entry is pending. Software `INTR` and
indirect-vector handling remain on their existing paths. The selected vector
and the acknowledged interrupt therefore refer to the same accepted request,
even if live interrupt flags change before entry.

## Verification and scope

The new directed regression and the existing software `INTR` vector regression
pass; the full DSP regression run reports 20 passing tests and no failing
regular tests.

A direct C-reference check confirmed the expected priority behavior: with
interrupt bit 2 pending, `c5x_run(c, 1)` enters at `PC=0x0006`, clears bit 2,
and sets `INTM`. Setting bit 1 afterward and running another instruction
advances to `PC=0x0007`; bit 1 remains pending (`IFR=0x0002`) while masked.
Thus, a later higher-priority request does not retarget the accepted entry.

This confirms a real RTL bug that can explain execution jumping into the wrong
interrupt handler. However, the user built and tested the fix and reported that
it did not resolve the modem failure, so this is not the cause of that failure.

A subsequent D-Modem call ended with a V.34 link error / `NO CARRIER`. Its full
retained DSP trace (25,165,824 instructions) did not reproduce the documented
runaway: no PC exceeded the base image's upper address `0xEC3D`, none reached
`0xF000`, and every recorded AR7 sample stayed in the expected `0x0BD0..0x0BDF`
range. The trace also had no execution in the C reference's `ov7` (`0xC000..0xCD4A`)
or `ov8` (`0xDC00..0xF8B5`) address windows, so the peer's retrain report does
not establish that the local DSP reached those stages. This call confirms a
link failure but does not identify its cause; the original runaway-PC failure
remains untraced.
