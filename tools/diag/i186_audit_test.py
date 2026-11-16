"""regression checks for the fixes made from fix-i186.md (i186.c); run: python3 -I tools/diag/i186_audit_test.py"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from i186 import CPU, ST_OK, ST_HLT
ok = True
def mk(code, **regs):
    c = CPU(); c.reset(); c.set('CS', 0); c.set('IP', 0x100); c.set('SS', 0); c.set('SP', 0x8000); c.set('DS', 0); c.set('ES', 0)
    for i, b in enumerate(code): c.wr8(0x100+i, b)
    for k, v in regs.items(): c.set(k, v)
    return c
def chk(name, got, want):
    global ok
    good = got == want; ok &= good; print(('PASS ' if good else 'FAIL ')+name, hex(got) if isinstance(got,int) else got, '' if good else 'want %s' % (hex(want) if isinstance(want,int) else want))
def step(c, n=1):
    for _ in range(n):
        c.run(1)
# BCD
c = mk([0x27], AX=0xFA); step(c); chk('DAA FA', c.get('AX')&0xFF, 0x60); chk('DAA FA cf', c.get('FLAGS')&1, 1)
c = mk([0x2F], AX=0xA1, FLAGS=0x12); step(c); chk('DAS A1 af', c.get('AX')&0xFF, 0x9B); chk('DAS A1 cf', c.get('FLAGS')&1, 0)
c = mk([0x37], AX=0x02FA, FLAGS=0x12); step(c); chk('AAA 02FA', c.get('AX'), 0x0300)
c = mk([0x3F], AX=0x0205, FLAGS=0x12); step(c); chk('AAS 0205', c.get('AX'), 0x010F)
# IDIV word INT32_MIN / -1 must not crash and raise INT 0
c = mk([0xF7, 0xFB], DX=0x8000, AX=0, BX=0xFFFF); c.wr8(0, 0x00); c.wr8(1, 0x02); step(c); chk('IDIV overflow -> INT0 IP', c.get('IP'), 0x200)
# BOUND: trap returns to the next instruction, pushes the IP offset (CS != 0)
c = mk([0x62, 0x07], AX=5, BX=0x300, CS=0x1234)
for i, b in enumerate([0x62, 0x07]): c.wr8(0x12340+0x100+i, b)
c.set('IP', 0x100); c.wr8(0x12340+0x300, 0x10); c.wr8(0x12340+0x301, 0); c.wr8(0x12340+0x302, 0x20); c.wr8(0x12340+0x303, 0)
c.set('AX', 0x30); c.set('BX', 0x300)
step(c); chk('BOUND pushed IP', c.rd16(0x8000-6), 0x102)
# STI shadow: IRQ not taken before the instruction after STI
c = mk([0xFB, 0x40, 0x40], AX=0, FLAGS=0x02); c.wr8(0x44, 0x00); c.wr8(0x45, 0x03); c.irq(0x11); step(c, 3); chk('STI shadow IP (handler entered after 2nd insn)', c.get('IP'), 0x302)
chk('STI shadow pushed IP', c.rd16(0x8000-6), 0x102)
c = mk([0xFB, 0xFA, 0x40], FLAGS=0x02); c.irq(0x11); step(c, 3); chk('STI;CLI leaves IRQ pending', c.irq_pending(), 1)
# TF single-step
c = mk([0x90, 0x90, 0x90, 0x90], FLAGS=0x0302); c.wr8(4, 0x00); c.wr8(5, 0x04); c.wr8(0x400, 0xCF)
step(c, 1); chk('TF trap after NOP', c.get('IP'), 0x400); chk('TF cleared in handler', (c.get('FLAGS')>>8)&1, 0)
# NMI wakes HLT with IF=0
c = mk([0xF4, 0x90], FLAGS=0x02); c.wr8(8, 0x00); c.wr8(9, 0x05); r = c.run(10); chk('HLT', r, ST_HLT)
import ctypes as C; from i186 import _l; _l.i186_nmi.argtypes = [C.c_void_p]; _l.i186_nmi(c.h); c.run(1); chk('NMI vector', c.get('IP')>=0x500, True)
# word write straddling an MMIO page / RO page
c = mk([0xA3, 0xFF, 0x0F], AX=0x1234); c.ro_page(0x01); c.wr8(0x1000, 0xAA)
c.set('DS', 0); step(c); chk('RO byte kept', c.rd8(0x1000), 0xAA); chk('RAM byte written', c.rd8(0xFFF), 0x34)
# REP interruptible (STI shadow lets iteration 1 run, then the pending IRQ is taken with CX reduced, IP at the REP prefix)
c = mk([0xFB, 0xF3, 0xA4], CX=10, SI=0x200, DI=0x300, FLAGS=0x02); c.wr8(0x44, 0x00); c.wr8(0x45, 0x06); c.irq(0x11)
step(c, 3); chk('REP interrupted CX', c.get('CX'), 9); chk('REP pushed IP at prefix', c.rd16(0x8000-6), 0x101)
print('ALL PASS' if ok else 'FAILURES')
