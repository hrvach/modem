"""trace the 9E56 acquisition gate on both DSPs: [31A] [32C], level [300:302] vs 0x445C, [3B4], and which exit is taken. usage: gate9e56.py T0 T1 (GAIN, LINK_SLICE, DELAY_SAMPLES env)"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda m:(m.cpu.cycles-base)/CPU_HZ
PCS=(0x9E56,0x9E5D,0x9E64,0x9E66,0x9E65)
for m in (L.a,L.b):
    for p in PCS: m.dsp.bp(p)
o_s=_M.Machine._sample; last={}
def s(self):
    r=o_s(self); d=self.dsp; pc=d.get('PC'); nm='A' if self is L.a else 'B'
    if pc in PCS and T0<=T(self)<=T1:
        lv=(d.dm[0x380]<<16)|d.dm[0x382]; k=(pc,d.dm[0x31A],d.dm[0x32C],lv)
        if pc==0x9E56 or last.get(nm)!=k:
            print('%.4f %s %04X [31A]=%04X [32C]=%04X level=%08X (thr %08X, level-thr %s) [3B4]=%04X'%(T(self),nm,pc,d.dm[0x31A],d.dm[0x32C],lv,0x445C,'>=0' if ((lv-0x445C)&0xFFFFFFFF)<0x80000000 else '<0',d.dm[0x3B4]))
        last[nm]=k
    return r
_M.Machine._sample=s
while T(L.a)<T1+0.02: L.run(CPU_HZ//64)
