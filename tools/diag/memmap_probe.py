"""which DSP data regions a call touches, and PMST/ST1 (OVLY/RAM/CNF/MP-MC): usage memmap_probe.py SECONDS"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; dur=float(sys.argv[1]); L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(dur*fs): L.run(CPU_HZ//2)
for k,m in (('A',L.a),('B',L.b)):
    d=m.dsp; pm=d.get('PMST'); st1=d.get('ST1')
    print(k,"PMST=%04X (IPTR=%d AVIS=%d OVLY=%d RAM=%d MPMC=%d NDX=%d) ST1=%04X CNF=%d"%(pm,pm>>11,(pm>>7)&1,(pm>>5)&1,(pm>>4)&1,(pm>>3)&1,(pm>>2)&1,st1,(st1>>12)&1))
    rd=[d.ext_count(0,i) for i in range(64)]; wr=[d.ext_count(1,i) for i in range(64)]
    print(k,"external data reads/writes per 1K block (nonzero):",{"%04X"%(i<<10):(rd[i],wr[i]) for i in range(64) if rd[i] or wr[i]})
    print(k,"FFxx accesses (reads,writes):",{"FF%02X"%i:(d.ff_count(0,i),d.ff_count(1,i)) for i in range(256) if d.ff_count(0,i) or d.ff_count(1,i)})
