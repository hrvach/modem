"""run to T seconds, then record ACC each time one DSP executes PC for DUR seconds; print count and a sample of signed values. usage: acctrace.py T A|B PC(hex) DUR"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; T=float(sys.argv[1]); who=sys.argv[2]; pc=int(sys.argv[3],16); dur=float(sys.argv[4])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(T*fs): L.run(CPU_HZ//16)
d=(L.a if who=='A' else L.b).dsp; d.set_trace(pc)
while L.samples() < int((T+dur)*fs): L.run(CPU_HZ//32)
tr=d.trace(); print('hits',len(tr))
sv=lambda a: a-(1<<32) if a>=1<<31 else a
vals=[sv(a) for a,r,r2 in tr]
print('first 40:',vals[:40]); print('min/max',min(vals) if vals else None,max(vals) if vals else None, 'neg count',sum(1 for v in vals if v<0))
