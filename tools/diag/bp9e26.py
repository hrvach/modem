"""B DSP: at 9E26 (after lacl #20) print call time, ST0(DP), ACC; and at 9E13. usage: bp9e26.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
import machine as _M
fs=7200; T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
d=L.b.dsp; [d.bp(a) for a in (0x9D7F,0x9E11,0x9E1F,0x9E23,0x9E26,0x9D9D,0x9D88,0x9DCF)]; orig=_M.Machine._sample; out=[]; seen={}
def s(self):
    r=orig(self)
    if self is L.b:
        pc=d.get('PC')
        if pc in (0x9D7F,0x9E11,0x9E1F,0x9E23,0x9E26,0x9D9D,0x9D88,0x9DCF) and T0<=L.samples()/fs<=T1:
            k=(pc,); seen[k]=seen.get(k,0)+1
            if seen[k]<3 or pc==0x9E26: out.append('%.4f pc=%04X ST0=%04X ACC=%08X n=%d [3A0]=%04X [20]=%04X rc=%s'%(L.samples()/fs,pc,d.get('ST0'),d.get('ACC'),seen[k],d.dm[0x3A0],d.dm[0x20],' '.join('%04X'%x for x in d.recent_pcs(24))))
    return r
_M.Machine._sample=s
while L.samples()<int(T1*fs): L.run(CPU_HZ//64)
print('\n'.join(out)); print(seen)
