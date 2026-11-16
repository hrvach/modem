"""trace the base-image script interpreter at CCA6..CCAB (reads steps via [72], cala's each) on both DSPs: first time and count per function address, and the script pointer [72]. usage: scripteng.py T0 T1"""
import os, sys, collections; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
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
for m in (L.a,L.b): m.dsp.bp(0xCCAB); m.dsp.bp(0xCCA5); m.dsp.bp(0xCCA6)
seq={'A':[],'B':[]}; cnt={'A':collections.Counter(),'B':collections.Counter()}; entries={'A':[],'B':[]}
o_s=_M.Machine._sample
def s(self):
    r=o_s(self); d=self.dsp; pc=d.get('PC'); nm='A' if self is L.a else 'B'
    if T0<=T(self)<=T1:
        if pc==0xCCA5: entries[nm].append((round(T(self),3),'enter via CCA5 ACC=%04X'%(d.get('ACC')&0xFFFF)))
        if pc==0xCCAB:
            f=d.get('ACC')&0xFFFF; cnt[nm][f]+=1
            if cnt[nm][f]==1: seq[nm].append((round(T(self),3),f,d.dm[0x72]))
    return r
_M.Machine._sample=s
while T(L.a)<T1: L.run(CPU_HZ//64)
for nm in 'AB':
    print('== DSP',nm,'script entries (CCA5):',entries[nm][:12])
    print('   first executions (t, func, [72]):',[('%.3f'%t,'%04X'%f,'%04X'%p) for t,f,p in seq[nm]][:60])
