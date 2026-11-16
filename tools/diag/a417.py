"""watch the A417 stage conditions on both DSPs: [0x334] (pass counter, data start at >= 0x14, A478), [0x336] (S detector, bail at >= 4, A41A), [0x31A] (timeout, bail when negative, A417), plus hits of A482 (data-mode start message 41/42) and A47F (bail to 8D9D). usage: a417.py T0 T1 STEP_SECONDS"""
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
PCS=(0xA417,0xA47F,0xA482,0xA478)
for m in (L.a,L.b):
    for p in PCS: m.dsp.bp(p)
nxt={'A':T0,'B':T0}; hit={'A':{p:0 for p in PCS},'B':{p:0 for p in PCS}}; mx={'A':0,'B':0}
sg=lambda v: v-65536 if v>=32768 else v
o_s=_M.Machine._sample
def s(self):
    r=o_s(self); nm='A' if self is L.a else 'B'; t=T(self)
    if T0<=t<=T1:
        d=self.dsp; pc=d.get('PC')
        if pc in PCS:
            hit[nm][pc]+=1
            if pc in (0xA482,0xA47F): print('%.4f %s reached %04X  [334]=%d [336]=%d [31A]=%d'%(t,nm,pc,d.dm[0x334],d.dm[0x336],sg(d.dm[0x31A])))
        mx[nm]=max(mx[nm],d.dm[0x334]) if d.dm[0x334]<0x8000 else mx[nm]
        if t>=nxt[nm]: nxt[nm]=t+ST; print('%.3f %s [334]=%04X [336]=%04X [31A]=%04X [6D]=%04X max334=%d hits A417=%d'%(t,nm,d.dm[0x334],d.dm[0x336],d.dm[0x31A],d.dm[0x6D],mx[nm],hit[nm][0xA417]))
    return r
_M.Machine._sample=s
while T(L.a)<T1: L.run(CPU_HZ//64)
