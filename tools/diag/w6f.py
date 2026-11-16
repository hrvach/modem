"""PCs that write DSP data cell ADDR (hit counts) between T0 and T1 of a two-modem call; modem WHO. usage: w6f.py WHO T0 T1 ADDR"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
who=sys.argv[1]; t0=float(sys.argv[2]); t1=float(sys.argv[3]); addr=int(sys.argv[4],16)
L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
tgt=L.a if who=='A' else L.b; base=tgt.cpu.cycles; d=tgt.dsp; armed=False; last=d.dm[addr]
while (tgt.cpu.cycles-base) < t1*CPU_HZ:
    t=(tgt.cpu.cycles-base)/CPU_HZ
    if not armed and t>=t0: d.set_watch(addr); armed=True; print('armed at %.2f, value %04X'%(t,d.dm[addr]))
    L.run(CPU_HZ//64); v=d.dm[addr]
    if armed and v!=last: print('t=%.3f [%03X] %04X -> %04X  PC now %04X'%((tgt.cpu.cycles-base)/CPU_HZ,addr,last,v,d.get('PC'))); last=v
print('writers (pc: count):', {hex(pc):d.watch_hits(pc) for pc in range(0x10000) if d.watch_hits(pc)})
