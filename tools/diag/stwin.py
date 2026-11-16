"""print changes of DSP state cells of B (and A) in a call-time window. usage: stwin.py T0 T1 [cells hex...]"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; T0=float(sys.argv[1]); T1=float(sys.argv[2]); cells=[int(x,16) for x in sys.argv[3:]] or [0x6F,0x6D,0x4B,0x3CB,0x334,0x336,0x20,0x388]
L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
last={}
while L.samples()<int(T1*fs):
    L.run(CPU_HZ//4096); t=L.samples()/fs
    if t<T0: continue
    for k,m in (('A',L.a),('B',L.b)):
        cur=tuple(m.dsp.dm[c] for c in cells)
        if last.get(k)!=cur:
            if k in last: print('%.4f %s %s'%(t,k,' '.join('%03X=%04X'%(c,v) for c,v in zip(cells,cur) if last[k][cells.index(c)]!=v)))
            last[k]=cur
