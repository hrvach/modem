"""trace the 9D66 probing step on both DSPs: hits of 9D50 (restart) / 9D80 (compare) / 9D84 (accept) with the compared values. usage: step9d66.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=0.5
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda m:(m.cpu.cycles-base)/CPU_HZ
PCS=(0x9D66,0x9D74,0x9D80,0x9D84,0x9D50)
for m in (L.a,L.b):
    for p in PCS: m.dsp.bp(p)
sg=lambda v: v-65536 if v>=32768 else v
o_s=_M.Machine._sample
def s(self):
    r=o_s(self)
    d=self.dsp; pc=d.get('PC')
    if pc in PCS and T0<=T(self)<=T1:
        nm='A' if self is L.a else 'B'
        print('%.4f %s %04X ACC=%08X [33A]=%04X [34A]=%04X [307]=%04X [387]=%04X [FF27]=%04X [368]=%04X'%(T(self),nm,pc,d.get('ACC'),d.dm[0x33A],d.dm[0x34A],d.dm[0x307],d.dm[0x387],d.dm[0xFF27],d.dm[0x368]))
    return r
_M.Machine._sample=s
while T(L.a)<T1+0.02: L.run(CPU_HZ//64)
