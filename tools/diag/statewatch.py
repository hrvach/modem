"""watch the DSP state vector words of both modems during a call and print every change: dm[0x3CD] (state handler pointer, 'splk #4D' on page 7), dm[0x06F]/dm[0x0EF] (status word, page 0 & 1 views), dm[0x34D].
usage: statewatch.py SECONDS"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; dur=float(sys.argv[1])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
last={}
WORDS=(0x3CD,0x06F,0x34D,0x36F)
while L.samples() < int(dur*fs):
    L.run(CPU_HZ//8)
    t=L.samples()/fs
    for nm,m in (('A',L.a),('B',L.b)):
        v=tuple(m.dsp.dm[a] for a in WORDS)
        if last.get(nm)!=v:
            print('%6.2f %s 3CD=%04X 06F=%04X 34D=%04X 36F=%04X'%((t,nm)+v),flush=True); last[nm]=v
