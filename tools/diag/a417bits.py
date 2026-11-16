"""in the A417 stage each symbol shifts a bit into [0x320] and keeps a run counter in [0x323] (A41F loop); the stage moves on (A5A1 -> A42E) when the run reaches 0x14. Sample [0x320],[0x323],[0x343],[0x31A],[0x6D] over time on both DSPs. usage: a417bits.py T0 T1 STEP"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
T0=float(sys.argv[1]); T1=float(sys.argv[2]); ST=float(sys.argv[3]); L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda m:(m.cpu.cycles-base)/CPU_HZ
nxt={'A':T0,'B':T0}; mx={'A':0,'B':0}; o_s=_M.Machine._sample
def s(self):
    r=o_s(self); nm='A' if self is L.a else 'B'; t=T(self)
    if T0<=t<=T1:
        d=self.dsp; run=d.dm[0x323]
        if run<0x8000: mx[nm]=max(mx[nm],run)
        if t>=nxt[nm]: nxt[nm]=t+ST; print('%.3f %s [6D]=%04X [320]=%04X [323]=%04X (max run so far %d) [343]=%04X [31A]=%04X [6F]=%04X [4DB]=%04X'%(t,nm,d.dm[0x6D],d.dm[0x320],run,mx[nm],d.dm[0x343],d.dm[0x31A],d.dm[0x6F],d.dm[0x3DB]))
    return r
_M.Machine._sample=s
while T(L.a)<T1: L.run(CPU_HZ//64)
