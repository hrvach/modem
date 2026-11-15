import sys, time; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
t0=time.time()
def st(tag):
    c=m.cpu
    print("%s t=%.2fs wall=%.0fs pc=%05X r=%s 26A=%04X EA7=%02X 89D=%02X dsp=%s samp=%d irqs=%s"%(tag,c.cycles/CPU_HZ,time.time()-t0,c.phys_pc(),m._r,c.rd16(0x26A),c.rd8(0xEA7),c.rd8(0x89D),m.dsp is not None,m.hb_count,dict((hex(k),v) for k,v in m.irq_count.items())))
    print("   ",m.icu_state()); print("    dte:",m.dte_text())
    print("    T0 con=%04X cmpa=%04X  T1 con=%04X cnt=%04X  T2 con=%04X cmpa=%04X | S0 con=%04X cmp=%04X sts=%04X  S1 con=%04X sts=%04X"%(m.tm[0].con,m.tm[0].cmpa,m.tm[1].con,m.tm[1].cnt,m.tm[2].con,m.tm[2].cmpa,m.uart[0].con,m.uart[0].cmp,m.uart[0].sts,m.uart[1].con,m.uart[1].sts))
def run(s):
    m._r=m.run(int(s*CPU_HZ))
for i in range(int(sys.argv[1]) if len(sys.argv)>1 else 6):
    run(2); st("boot")
    if m._r not in (0,3,4): print(m.cpu.state(), m.cpu.badop()); break
for cmd in sys.argv[2:]:
    m.send(cmd+"\r"); run(1.5); st(repr(cmd))
