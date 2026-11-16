"""check the claim 'routine 8270 discards every go-online flood word at 8300': count word arrivals (8282), discards (8300) and pack-path entries (8286/828F/8292) on both DSPs and histogram the word [0x50] seen at 8282. usage: floodcheck.py T0 T1 (CPU_SCALE, LINK_SLICE, DELAY_SAMPLES env)"""
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
PCS=(0x8279,0x8282,0x8286,0x828F,0x8300,0x829F)
for m in (L.a,L.b):
    for p in PCS: m.dsp.bp(p)
cnt={'A':collections.Counter(),'B':collections.Counter()}; hist={'A':collections.Counter(),'B':collections.Counter()}
o_s=_M.Machine._sample
def s(self):
    r=o_s(self); d=self.dsp; pc=d.get('PC'); nm='A' if self is L.a else 'B'
    if pc in PCS and T0<=T(self)<=T1:
        cnt[nm][pc]+=1
        if pc==0x8282:
            dp=(d.get('ST0')&0x1FF)<<7; hist[nm][(dp>>7,d.dm[dp|0x50])]+=1
    return r
_M.Machine._sample=s
while T(L.a)<T1: L.run(CPU_HZ//64)
for nm in 'AB':
    print(nm,'hits',{'%04X'%k:v for k,v in sorted(cnt[nm].items())})
    print(nm,'(DP page, [50]) at 8282 (top):',[('dp%d:%04X'%k,v) for k,v in hist[nm].most_common(8)])
