"""log the carrier-detector state of one DSP (87B6 energy filter / 87CE hysteresis, status [0x6F] bit7) once per 0.5 s: dm[0x00..0x0F], [0x14], [0x05], [0x07], [0x6F].
usage: carrier_watch.py T0 T1 [A|B]"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys'); sys.path.insert(0, ROOT+'/dsp')
from link import *
from machine import CPU_HZ
fs=7200; t0=float(sys.argv[1]); t1=float(sys.argv[2]); who=sys.argv[3] if len(sys.argv)>3 else 'A'
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
m=L.a if who=='A' else L.b
t=t0
while t<=t1:
    while L.samples() < int(t*fs): L.run(CPU_HZ//16)
    d=m.dsp.dm
    print('%5.1f [6F]=%04X DP=%X p7: %s'%(t,d[0x6F],m.dsp.get('ST0')&0x1FF,' '.join('%04X'%d[0x380+a] for a in range(0,0x20))),flush=True)
    t+=0.5
