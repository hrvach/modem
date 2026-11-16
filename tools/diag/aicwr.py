"""log every call of the codec secondary-word routine 8149 (ACC = reg<<8|value) per modem with call time. usage: aicwr.py T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; t1=float(sys.argv[1])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
for m in (L.a,L.b): m.dsp.set_trace(0x8149)
seen={'A':0,'B':0}
while L.samples() < int(t1*fs):
    L.run(CPU_HZ//32); t=L.samples()/fs
    for nm,m in (('A',L.a),('B',L.b)):
        tr=m.dsp.trace()
        for a,r,r2 in tr[seen[nm]:]: print('%6.2f %s 8149 ACC=%04X (ret %04X)'%(t,nm,a&0xFFFF,r),flush=True)
        seen[nm]=len(tr)
