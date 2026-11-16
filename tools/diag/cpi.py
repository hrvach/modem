"""average 80186 clocks per instruction: over the first N seconds of boot, and over a later window (call phase). usage: cpi.py BOOT_SECONDS [WINDOW_T0 WINDOW_T1]  (single modem boot; window uses the two-modem Link)"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
import machine as M
from machine import CPU_HZ
sec=float(sys.argv[1]) if len(sys.argv)>1 else 3.0
m=M.Machine(nvram_mode=None); m.run(int(CPU_HZ*sec)); n=sum(m.cpu.hits[i] for i in range(1<<20))
print('boot %.1f s (idle prompt): %d cycles / %d instructions = %.2f clocks per instruction  (%.0f instr/ms at %d Hz)'%(sec,m.cpu.cycles,n,m.cpu.cycles/max(1,n),n/(sec*1000),CPU_HZ))
if len(sys.argv)>3:
    from link import *
    T0=float(sys.argv[2]); T1=float(sys.argv[3]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
    for mm,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
        for c in cmds: mm.send(c); L.run(int(1.5*CPU_HZ))
    L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
    base=L.a.cpu.cycles; T=lambda: (L.a.cpu.cycles-base)/CPU_HZ
    while T()<T0: L.run(CPU_HZ//32)
    s0=[sum(mm.cpu.hits[i] for i in range(1<<20)) for mm in (L.a,L.b)]; c0=[mm.cpu.cycles for mm in (L.a,L.b)]
    while T()<T1: L.run(CPU_HZ//32)
    for nm,mm,a,b in (('A',L.a,s0[0],c0[0]),('B',L.b,s0[1],c0[1])):
        ni=sum(mm.cpu.hits[i] for i in range(1<<20))-a; nc=mm.cpu.cycles-b
        print('call phase %.1f-%.1f s modem %s: %d cycles / %d instructions = %.2f clocks per instruction (%.0f instr/ms)'%(T0,T1,nm,nc,ni,nc/max(1,ni),ni/((T1-T0)*1000)))
