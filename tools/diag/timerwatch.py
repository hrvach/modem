"""the DSP software timer: [0x6E] counts down per call of 8767 (main loop), at zero it branches to the callback [0x6D]. Print [6D],[6E],[6F] once per 0.25 s for both DSPs from T0 to T1.
usage: timerwatch.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; t0=float(sys.argv[1]); t1=float(sys.argv[2])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
t=t0
while t<=t1:
    while L.samples() < int(t*fs): L.run(CPU_HZ//16)
    print('%6.2f  A 6D=%04X 6E=%04X 6F=%04X | B 6D=%04X 6E=%04X 6F=%04X'%((t,)+tuple(x for m in (L.a,L.b) for x in (m.dsp.dm[0x6D],m.dsp.dm[0x6E],m.dsp.dm[0x6F]))),flush=True)
    t+=0.25
