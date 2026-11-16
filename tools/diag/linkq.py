"""receive-queue health of the line between the modems: underruns (silence inserted) and min/mean queue depth after T0. usage: linkq.py T0 T1 (DELAY_SAMPLES env)"""
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
st={'A':[10**9,0,0,0],'B':[10**9,0,0,0]}; u0={}
o_s=_M.Machine._sample
def s(self):
    nm='A' if self is L.a else 'B'
    if T(self)>=T0:
        u0.setdefault(nm,self.rx_under); q=len(self.rxbuf); x=st[nm]; x[0]=min(x[0],q); x[1]+=q; x[2]+=1; x[3]=max(x[3],q)
    return o_s(self)
_M.Machine._sample=s
while T(L.a)<T1: L.run(CPU_HZ//64)
for nm,m in (('A',L.a),('B',L.b)):
    x=st[nm]; print('%s delay=%s underruns since %.1f s: %d   queue min %d mean %.1f max %d (samples)'%(nm,os.environ.get('DELAY_SAMPLES','0'),T0,m.rx_under-u0.get(nm,0),x[0],x[1]/max(1,x[2]),x[3]))
