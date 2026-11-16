"""what do the two DSPs wait on between tag 04 and the receive stage? logs changes of the callback cells [6D], [32F] and samples the countdowns [31A],[32C],[6E] every 50 ms (CPU-cycle seconds). usage: waits.py T0 T1 (DELAY_SAMPLES env)"""
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
CELLS=(0x6D,0x6E,0x32F,0x31A,0x32C)
prev={}; nxt={}; out=[]
o_s=_M.Machine._sample
def s(self):
    r=o_s(self)
    nm='A' if self is L.a else 'B'; t=T(self); d=self.dsp
    if T0<=t<=T1:
        v=tuple(d.dm[a] for a in CELLS)
        p=prev.get(nm)
        if p is None or v[0]!=p[0] or v[2]!=p[2]: out.append((t,nm,'CHG',v,self.rate))
        elif t>=nxt.get(nm,0): out.append((t,nm,'   ',v,self.rate)); nxt[nm]=t+0.05
        prev[nm]=v
    return r
_M.Machine._sample=s
while T(L.a)<T1+0.02: L.run(CPU_HZ//64)
print('t      mach  [6D]  [6E]  [32F] [31A] [32C]  rate')
for t,nm,k,v,rate in sorted(out): print('%.4f %s %s %s %d'%(t,nm,k,' '.join('%04X'%x for x in v),rate))
