"""capture the per-symbol decision vectors of the A478-stage callback B6FD ([0x300..0x307] right after B76E) on both DSPs and summarise their spread. usage: decvec.py T0 T1 [N]"""
import os, sys, math, collections; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
T0=float(sys.argv[1]); T1=float(sys.argv[2]); N=int(sys.argv[3]) if len(sys.argv)>3 else 400; L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda m:(m.cpu.cycles-base)/CPU_HZ
for m in (L.a,L.b): m.dsp.bp(0xB76E)
sg=lambda v: v-65536 if v>=32768 else v
rec={'A':[],'B':[]}; o_s=_M.Machine._sample
def s(self):
    r=o_s(self); nm='A' if self is L.a else 'B'
    if T0<=T(self)<=T1 and self.dsp.get('PC')==0xB76E and len(rec[nm])<N: rec[nm].append([sg(self.dsp.dm[0x300+i]) for i in range(8)])
    return r
_M.Machine._sample=s
while T(L.a)<T1 and (len(rec['A'])<N or len(rec['B'])<N): L.run(CPU_HZ//64)
for nm in 'AB':
    r=rec[nm]; print('== DSP',nm,len(r),'vectors; first 12:'); 
    for v in r[:12]: print('   ',' '.join('%6d'%x for x in v))
    for i in range(8):
        col=[v[i] for v in r]
        if col: mu=sum(col)/len(col); sd=math.sqrt(sum((x-mu)**2 for x in col)/len(col)); print('  cell [30%d]: mean %8.0f  sd %8.0f  min %6d max %6d'%(i,mu,sd,min(col),max(col)))
