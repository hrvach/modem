"""watch one DSP data address on one modem; print each value change with the writer PCs. usage: watchaddr.py ADDR(hex) A|B T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; addr=int(sys.argv[1],16); who=sys.argv[2]; t0=float(sys.argv[3]); t1=float(sys.argv[4])
L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
d=(L.a if who=='A' else L.b).dsp; d.set_watch(addr); prev=d.dm[addr]; seen={}
while L.samples() < int(t1*fs):
    L.run(CPU_HZ//64); t=L.samples()/fs
    new=[]
    for pc in range(0x8000,0x10000):
        h=d.watch_hits(pc)
        if h and seen.get(pc,0)!=h: new.append((pc,h-seen.get(pc,0))); seen[pc]=h
    v=d.dm[addr]
    if t>=t0 and (v!=prev or new):
        print('%7.3f [%04X] %04X -> %04X writers %s'%(t,addr,prev,v,' '.join('%04X x%d'%x for x in new[:8])),flush=True)
    prev=v
