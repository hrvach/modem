#!/usr/bin/env python3
"""dsp_regress.py -- one self-checking test per fixed DSP-core bug (rtl/dsp), run against the Verilated core through rtlshim.cpp.
Every expected value is what the C reference core (courier/src/dsp/c5x_core.c) produces for the same program (measured when the bug was fixed);
the tests need only the RTL.   Usage: tests/dsp_regress/build.sh && python3 tests/dsp_regress/dsp_regress.py [name ...]
See docs/INTERRUPT_FINDINGS.md for the story behind each test."""
import ctypes, os, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
lib = ctypes.CDLL(os.environ.get("RTL_LIB") or os.path.join(ROOT, "build", "dsp_regress", "librtl.so"))
u16, u32, vp, i32 = ctypes.c_uint16, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_int
lib.r_new.restype = vp
lib.r_snoop.argtypes = [vp, u32]; lib.r_snoop.restype = ctypes.c_uint64
for name, args, res in [("r_free", [vp], None), ("r_reset", [vp, u16], None), ("r_poke_pmem", [vp, u16, u16], None), ("r_poke_dmem", [vp, u16, u16], None),
                        ("r_set", [vp, ctypes.c_char_p, u32], None), ("r_get", [vp, ctypes.c_char_p], u32), ("r_irq", [vp, i32], None),
                        ("r_bp", [vp, i32, i32, u16], None), ("r_run", [vp, u32], i32), ("r_dm_rd", [vp, u16], u16), ("r_pm_rd", [vp, u16], u16),
                        ("r_mtime", [vp], u32), ("r_io_set", [vp, u16, u16], None), ("r_dbg", [vp, i32], u32), ("r_snoop_n", [vp], u32), ("r_io_delay", [vp, i32], None)]:
    f = getattr(lib, name); f.argtypes = args; f.restype = res
BASE, ISR = 0x8000, 0x8800
N = 0x8B00                                                  # NOP


class Core:
    """a fresh core: words poked at `at` (default BASE), a breakpoint after the last word, registers set after reset"""
    def __init__(self, words, regs=(), pm=None, dm=None, io=None, vec=(), isr=None, at=BASE, irq=None):
        self.c = lib.r_new()
        for i, w in enumerate(words): lib.r_poke_pmem(self.c, at + i, w)
        for a, w in (pm or {}).items(): lib.r_poke_pmem(self.c, a, w)
        for a, w in (dm or {}).items(): lib.r_poke_dmem(self.c, a, w)
        for i, w in enumerate(isr or []): lib.r_poke_pmem(self.c, ISR + i, w)
        for v in vec:                                       # interrupt vector v: B ISR
            lib.r_poke_pmem(self.c, v, 0x7980); lib.r_poke_pmem(self.c, v + 1, ISR)
        lib.r_reset(self.c, at)
        for k, v in regs: lib.r_set(self.c, k, v)
        for p, v in (io or {}).items(): lib.r_io_set(self.c, p, v)
        self.end = at + len(words)
        self.irq = irq

    def run(self, end=None, delay=0, budget=20000):
        lib.r_bp(self.c, 0, 1, self.end if end is None else end)
        m0 = lib.r_mtime(self.c)
        if delay: lib.r_run(self.c, delay)
        for b in (self.irq or []): lib.r_irq(self.c, b)
        lib.r_run(self.c, budget)
        self.cycles = lib.r_mtime(self.c) - m0 - delay
        return self

    def get(self, n): return lib.r_get(self.c, n.encode())
    def dm(self, a): return lib.r_dm_rd(self.c, a)
    def pm(self, a): return lib.r_pm_rd(self.c, a)
    def halted(self): return lib.r_dbg(self.c, 4)
    def snoop(self): return [(v >> 32 & 1, v >> 16 & 0xFFFF, v & 0xFFFF) for v in (lib.r_snoop(self.c, i) for i in range(lib.r_snoop_n(self.c)))]   # (pmem, addr, data) per reported write
    def free(self): lib.r_free(self.c)


TESTS = {}
def test(f): TESTS[f.__name__] = f; return f
KNOWN_ISSUES = {}
def known_issue(f): KNOWN_ISSUES[f.__name__] = f; return f
def check(cond, msg): 
    if not cond: raise AssertionError(msg)


@test
def arp_after_lst():
    """LST #0 loads ARP; an indirect instruction right behind it must use the NEW ARP (AR0 steps, not AR3) -- the interlock missed LST (fix 1)"""
    c = Core([0xBE40, 0x0E38, 0x90A0] + [0xB800] * 4, [(b"ARP", 3), (b"AR0", 0x300), (b"AR3", 0x310), (b"DP", 5)], dm={5 * 128 + 0x38: 0}).run()
    check(c.get("AR0") == 0x301 and c.get("AR3") == 0x310, "AR0=%04x AR3=%04x (want 0301 / 0310)" % (c.get("AR0"), c.get("AR3")))

@test
def nested_eint():
    """INT1+INT2 pending, ISR = EINT;LDP;LACK #55: the nested entry comes after the instruction following EINT, so the 1-deep shadow holds the main program's ACC 0x40 (fix 2)"""
    for d in range(10):
        c = Core([0xB940, 0xBE40] + [N] * 12, [(b"IMR", 0xFFFF), (b"DP", 5)], vec=(2, 4, 6, 8), isr=[0xBE40, 0xBC09, 0xB955, N, N, 0xBE3A], irq=(1, 2)).run(delay=d)
        check(c.get("ACC") == 0x40, "irq at %d: final ACC=%#x (want 0x40)" % (d, c.get("ACC")))

@test
def intr_vector():
    """INTR #4 must enter at vector 0x0008; a decoy handler at address 0 must not run (the vector was taken from live signals and came out 0) (fix 3)"""
    c = Core([0xB940, 0xBE64, 0xB910, 0xB920] + [N] * 4, [(b"IMR", 0xFFFF), (b"DP", 5)],
             pm={0: 0x7980, 1: 0x8900, 0x8900: 0xB911, 0x8901: 0x9030, 0x8902: 0xBE3A, 8: 0x7980, 9: ISR}, isr=[0xB977, 0x9030, 0xBE3A]).run()
    check(c.dm(5 * 128 + 0x30) == 0x77, "handler stored %#x (want 0x77)" % c.dm(5 * 128 + 0x30))

@test
def rete_with_pending_interrupt():
    """a pending interrupt is entered right after RETE, with no main-program instruction in between (C: 0) (fix 4)"""
    for d in (24, 30, 31, 33, 36):
        c = Core([0xBE40] + [0xB801] * 40, [(b"IMR", 0xFFFF), (b"DP", 5)],        # INT1 -> ISR A (stores ACC at 0x30), INT2 -> ISR B (at 0x31)
                 pm={2: 0x7980, 3: 0x8800, 4: 0x7980, 5: 0x8900, 0x8800: 0x9030, 0x8801: 0xBE3A, 0x8900: 0x9031, 0x8901: 0xBE3A}, irq=(0, 1))
        c.run(delay=d)
        a, b = c.dm(5 * 128 + 0x30), c.dm(5 * 128 + 0x31)
        check(a == b and a != 0, "irq after %d cycles: A saw %d, B saw %d (want equal)" % (d, a, b))

@test
def intr_cycle_charge():
    """INTR is charged 4 cycles in all, no extra 4-cycle entry pulse: INTR 1 + B + NOP = 9 (fix 5)"""
    c = Core([0xBE61], pm={2: 0x7980, 3: 0x8100, 0: N, 1: N, 0x8100: N}, regs=[(b"IMR", 0xFFFF)]).run(end=0x8101)
    check(c.cycles == 9, "%d cycles (want 9)" % c.cycles)

@test
def rpt_first_iteration_cycles():
    """RPT + 2-word instruction: the first iteration costs the full count, 1 only from the second (RPTK 2; SPLK = 6) (fix 6)"""
    c = Core([0xBB02, 0xAE60, 0x1234], [(b"DP", 0)]).run()
    check(c.cycles == 6, "%d cycles (want 6)" % c.cycles)

@test
def return_at_ffff_cycles():
    """a taken return at address 0xFFFF costs 4 (the target was never assigned, 0xFFFF+1 = 0 looked sequential): CALL + RET = 8 (fix 7)"""
    c = Core([0x7A80, 0xFFFF], pm={0xFFFF: 0xEF00}).run(end=BASE + 2)
    check(c.cycles == 8, "%d cycles (want 8)" % c.cycles)

@test
def reserved_indirect_mode_faults():
    """indirect modifier m = 6/7 is reserved: the core halts (C RUN_BADOP) for ADD/SUB/LACC/MPY, a legal mode does not (fix 8)"""
    for op in (0x20B0, 0x20B9, 0x30B1, 0x10B1, 0x54B1):
        c = Core([op, N], [(b"ARP", 1), (b"AR1", 0x200), (b"DP", 5)]).run(end=BASE + 1)
        check(c.halted() == 1, "%04x did not halt" % op)
    c = Core([0x20A1, N], [(b"ARP", 1), (b"AR1", 0x200), (b"DP", 5)]).run(end=BASE + 1)
    check(c.halted() == 0, "legal *+ halted")

@test
def peripheral_data_read_cycles():
    """data reads at 0x50..0x5F go through the I/O wait states: LACC 0x5F costs 8 (IOWSR/CWSR reset values), LACC 0x61 costs 1 (fix 9)"""
    c = Core([0x105F], [(b"DP", 0)]).run(); check(c.cycles == 8, "LACC 0x5F: %d cycles (want 8)" % c.cycles)
    c = Core([0x1061], [(b"DP", 0)]).run(); check(c.cycles == 1, "LACC 0x61: %d cycles (want 1)" % c.cycles)

@test
def sst_stores_the_new_arp():
    """SST #0 *,AR2 with ARP 1: the stored ST0 carries the ARP the instruction leaves behind (2), not the old one (fix 10)"""
    c = Core([0x8E8A], [(b"ARP", 1), (b"AR1", 0x300), (b"AR2", 0x310)]).run()
    check(c.dm(0x300) >> 13 == 2, "stored %04x, ARP field %d (want 2)" % (c.dm(0x300), c.dm(0x300) >> 13))

@test
def peripheral_write_cycle_on_two_word_forms():
    """2-word instructions that write a peripheral MMR (0x24) cost the extra bus cycle: LMMR 3, TBLR 4, BLDD 4 (fix 11)"""
    for nm, words, regs, want in (("LMMR", [0x8924, 0x0300], [(b"DP", 0)], 3), ("TBLR", [0xA624], [(b"DP", 0), (b"ACC", 0x8100)], 4), ("BLDD", [0xA824, 0x0300], [(b"DP", 0)], 4)):
        c = Core(words, regs).run(); check(c.cycles == want, "%s: %d cycles (want %d)" % (nm, c.cycles, want))

@test
def smmr_lmmr_read_live_sources():
    """SMMR/LMMR sources that are live registers or host-window ports deliver the value, not 0 (the loop engine took the read port's deferred 'no data') (fix 12)"""
    pre = [0xAE24, 0x4321, 0xAE25, 0x2222]                  # SPLK TIM, SPLK PRD
    c = Core(pre + [0x0924, 0x0300], [(b"DP", 0)]).run(); check(0x4300 <= c.dm(0x300) <= 0x4321, "SMMR TIM stored %04x" % c.dm(0x300))
    c = Core(pre + [0x0925, 0x0300], [(b"DP", 0)]).run(); check(c.dm(0x300) == 0x2222, "SMMR PRD stored %04x" % c.dm(0x300))
    c = Core(pre + [0x890C, 0xFF50], [(b"DP", 0)], io={0xFF50: 0x1111}).run(); check(c.get("TREG0") & 0xFFFF == 0x1111, "LMMR T0 from FF50: %04x" % (c.get("TREG0") & 0xFFFF))
    c = Core(pre + [0x890C, 0x0024], [(b"DP", 0)]).run(); check(0x4300 <= c.get("TREG0") & 0xFFFF <= 0x4321, "LMMR T0 from TIM: %04x" % (c.get("TREG0") & 0xFFFF))

@test
def macd_loop_stays_in_data_memory():
    """guard (reported, not reproduced): MACD in a repeat loop stepping past the on-chip RAM edge writes nothing into program memory"""
    c = Core([0xBF01, 0x007E, 0xBB01, 0xA3A0, 0x9000], [(b"ARP", 1), (b"DP", 0)], pm={0x80: 0xBEEF, 0x81: 0xBEEF}, dm={a: 0x1000 + a for a in range(0x70, 0x80)}).run()
    check(c.pm(0x80) == 0xBEEF and c.dm(0x7F) == 0x107F, "pm[0x80]=%04x dm[0x7F]=%04x" % (c.pm(0x80), c.dm(0x7F)))

@test
def mar_after_lst_uses_new_arp():
    """LST #0 loads ARP=0, the very next MAR *+ must step AR0, not AR1 (same interlock as arp_after_lst, for MAR) (fix 13)"""
    c = Core([0x0E38, 0x8BA0], [(b"ARP", 1), (b"AR0", 0x300), (b"AR1", 0x310), (b"DP", 5)], dm={5 * 128 + 0x38: 0}).run()
    check(c.get("AR0") == 0x301 and c.get("AR1") == 0x310, "AR0=%04x AR1=%04x (want 0301 / 0310)" % (c.get("AR0"), c.get("AR1")))

@known_issue
def retd_push_pop_in_the_slots():
    """KNOWN ISSUE (the fix broke V.8 on the board, reverted): RETD with PSHD then POPD in its two slots: the return address is read after both slots, so the push and pop cancel and it returns to the caller (fix 14)"""
    c = Core([0x7A80, 0x8100, N], [(b"DP", 0)], pm={0x8100: 0xFF00, 0x8101: 0x7660, 0x8102: 0x8A61, 0x8200: N, 0x8201: N}, dm={0x60: 0x8200})
    sp0 = c.get("SP"); c.run(end=BASE + 3)
    check(c.get("PC") == BASE + 3 and c.get("SP") == sp0 and c.dm(0x61) == 0x8200, "pc=%04x sp %d->%d dm[0x61]=%04x" % (c.get("PC"), sp0, c.get("SP"), c.dm(0x61)))

@known_issue
def retd_push_in_the_last_slot():
    """KNOWN ISSUE (the fix broke V.8 on the board, reverted): RETD with a push in the second slot: the pushed word is TOS when the return happens (C returns to it) and the real return address stays on the stack (fix 15)"""
    c = Core([0x7A80, 0x8100, N], [(b"DP", 0)], pm={0x8100: 0xFF00, 0x8101: N, 0x8102: 0x7660, 0x8200: N, 0x8201: N, 0x8202: N}, dm={0x60: 0x8200})
    sp0 = c.get("SP"); c.run(end=0x8201)
    check(c.get("SP") == (sp0 - 1) & 7, "sp %d -> %d (want one entry left on the stack)" % (sp0, c.get("SP")))
    check(0x8200 <= c.get("PC") <= 0x8203, "returned to %04x (want the pushed address 0x8200)" % c.get("PC"))

@test
def snoop_reports_the_real_destination():
    """a program-space write into the SARAM overlay (RAM=1, program 0x2000..) is reported as a DATA write at the translated address 0x0800.., not as a program write at the raw address (fix 16)"""
    # TBLW 0x60: program[ACC] = dm[0x60]; ACC = 0x2001 with RAM=1 lands in data 0x0801
    c = Core([0xA760], [(b"DP", 0), (b"PMST", 0x0010 | 0x0020)], dm={0x60: 0x5A5A})
    lib.r_set(c.c, b"ACC", 0x2001); c.run(); w = c.snoop()
    check(any(p == 0 and a == 0x0801 and d == 0x5A5A for p, a, d in w), "SARAM-overlay write reported %r (want data 0x0801 <- 0x5A5A)" % w)
    c = Core([0xA760], [(b"DP", 0)], dm={0x60: 0x5A5A})                         # RAM=0: the same write goes to program memory, reported as such
    lib.r_set(c.c, b"ACC", 0x2001); c.run(); w = c.snoop()
    check(any(p == 1 and a == 0x2001 and d == 0x5A5A for p, a, d in w), "external program write reported %r (want program 0x2001 <- 0x5A5A)" % w)

@test
def io_window_write_wait_states():
    """a data write to 0x50..0x5F charges the I/O wait states: SACL 0x51 with the reset IOWSR/CWSR costs 7 (C io_write) (fix 17)"""
    c = Core([0x9051], [(b"DP", 0), (b"ACC", 0x1234)]).run(); check(c.cycles == 7, "%d cycles (want 7)" % c.cycles)

@test
def mads_reads_the_live_peripheral_not_a_stale_value():
    """AND reads DMEM 0x60 (0xAAAA), then MADS reads the I/O window at 0x55: TREG0 must be the port value (0), not the previous read (fix 18)"""
    c = Core([0x6E60, 0xAA55], [(b"DP", 0), (b"BMAR", 0x8100)], pm={0x8100: 0x1111}, dm={0x60: 0xAAAA}).run()
    check(c.get("TREG0") & 0xFFFF == 0, "TREG0=%04x (want 0)" % (c.get("TREG0") & 0xFFFF))

@test
def pmst_store_in_the_last_block_word():
    """an RPTB block whose last instruction stores ST1 (PM=1, bit 0 set) into PMST: the block-end BRAF clear wins, PMST ends 0x00bc like C (fix 19)"""
    c = Core([0xBEC6, 0x8002, 0x8F07, N], [(b"DP", 0), (b"PM", 1)]).run()
    check(c.get("PMST") == 0x00BC, "PMST=%04x (want 00bc)" % c.get("PMST"))



@test
def ldp_keeps_its_arp_switch():
    """LDP *,AR7 with ARP=2: the pointer switch must survive the ST0 rebuild, ARP ends 7 like C (fix 20)"""
    c = Core([0x0D8F], [(b"ARP", 2)]).run()
    check(c.get("ARP") == 7, "ARP=%d (want 7)" % c.get("ARP"))


lib.r_io_wr_count.argtypes = [vp]; lib.r_io_wr_count.restype = u32
def io_writes(c): return lib.r_io_wr_count(c.c)

@known_issue
def rmw_to_io_address_writes_the_port():
    """KNOWN ISSUE (reproduced, not fixed; the firmware has no OPL/XPL/APL): OPL #lk,0x5B reads the port and must also WRITE the result to it (C logs 1 I/O write); the memory block performs one I/O transaction per instruction and drops the write"""
    c = Core([0x5D5B, 0x0F00], [(b"DP", 0)], io={0x5B: 0x00FF}).run()
    check(io_writes(c) == 1, "%d I/O writes (want 1)" % io_writes(c))

@known_issue
def in_to_io_address_writes_the_port():
    """KNOWN ISSUE (reproduced, not fixed; the firmware has no IN): IN *,0xFF00 with AR1=0xFF50 stores the port value to the host window (C logs 1 I/O write); same one-transaction limit"""
    c = Core([0xAF80, 0xFF00], [(b"ARP", 1), (b"AR1", 0xFF50), (b"DP", 0)], io={0xFF00: 0x1234}).run()
    check(io_writes(c) == 1, "%d I/O writes (want 1)" % io_writes(c))

@known_issue
def lmmr_into_rptc_terminates():
    """KNOWN ISSUE (reproduced, not fixed; the firmware has no LMMR): RPTK 1; LMMR RPTC,#0x300 (0x5A5A there) finishes in C (RPTC 0, 6 cycles); the RTL arms a phantom replay and never finishes"""
    c = Core([0xBB01, 0x8908, 0x0300], [(b"DP", 0)], dm={0x300: 0x5A5A}).run(budget=3000)
    check(c.cycles < 100, "ran %d cycles without finishing (C: 6)" % c.cycles)


@known_issue
def rptb_ending_in_lst1():
    """KNOWN ISSUE (reported, reproduced, not fixed; no RPTB block of the firmware ends with an LST): a repeat block whose last word is LST #1 runs one iteration short and leaves BRAF set (C: 4 iterations, BRAF=0)"""
    c = Core([0xAE09, 0x0003, 0xBC05, 0xBEC6, 0x8006, 0xB801, 0x0F30, N], [(b"DP", 0)], dm={5 * 128 + 0x30: 0}).run()
    check(c.get("ACC") == 4 and (c.get("PMST") & 1) == 0, "ACC=%d BRAF=%d (want 4 / 0)" % (c.get("ACC"), c.get("PMST") & 1))


def main():
    names = sys.argv[1:] or list(TESTS)
    bad = 0
    for n in names:
        try:
            TESTS[n](); print("PASS  %-40s %s" % (n, (TESTS[n].__doc__ or "").split(":")[0][:70]))
        except AssertionError as e:
            bad += 1; print("FAIL  %-40s %s" % (n, e))
    for n, f in KNOWN_ISSUES.items():
        try: f(); print("FIXED %-40s (known issue now passes: move it to a normal test)" % n)
        except AssertionError as e: print("known %-40s %s" % (n, e))
    print("%d passed, %d failed" % (len(names) - bad, bad))
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()
