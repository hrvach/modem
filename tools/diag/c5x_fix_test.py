"""regression checks for the DSP core SBBB fix (SPRU056D 6-233: ACC - ACCB - !C, C only, no OV, no saturation)
run: python3 -I tools/diag/c5x_fix_test.py"""
import os, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT + "/dsp")
import c5x

SETC, CLRC, SBBB = 0xBE4F, 0xBE4E, 0xBE19   # SETC C / CLRC C (SPRU056D 6-235, 6-92); SBBB = 1011 1110 0001 1001 (6-233)
ok = True
def chk(name, got, want):
    global ok
    good = got == want; ok &= good
    print(('PASS ' if good else 'FAIL ') + name, hex(got), '' if good else 'want ' + hex(want))

def sbbb(acc, accb, carry_in):
    d = c5x.DSP()
    d.load_pm(0x6000, b''.join(w.to_bytes(2, 'little') for w in (SETC if carry_in else CLRC, SBBB)))
    d.reset(0x6000)                       # reset clears the registers, so the operands are set after it
    d.set('ACC', acc); d.set('ACCB', accb)
    d.run(1); d.run(1)
    return d.get('ACC') & 0xFFFFFFFF, (d.get('ST1') >> 9) & 1, (d.get('ST0') >> 12) & 1

# manual example 1: ACC=2000 0000h, ACCB=1000 0000h, C=1 -> 1000 0000h, C=1
acc, c, ov = sbbb(0x20000000, 0x10000000, 1); chk('SBBB ex1 ACC', acc, 0x10000000); chk('SBBB ex1 C', c, 1)
# manual example 2: ACC=0009 8012h, ACCB=0009 8010h, C=0 -> 01h, C=1
acc, c, ov = sbbb(0x00098012, 0x00098010, 0); chk('SBBB ex2 ACC', acc, 0x1); chk('SBBB ex2 C', c, 1)
# borrow out of bit 31: C cleared, ACC wraps
acc, c, ov = sbbb(0, 1, 1); chk('SBBB borrow ACC', acc, 0xFFFFFFFF); chk('SBBB borrow C', c, 0)
# SBBB never touches OV and does not saturate: plain wrap
acc, c, ov = sbbb(0x7FFFFFFF, 0xFFFFFFFF, 1); chk('SBBB no-sat ACC', acc, 0x80000000); chk('SBBB OV untouched', ov, 0)
print('ALL PASS' if ok else 'FAILURES')
