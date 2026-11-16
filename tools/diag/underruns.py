"""when does each modem's receive queue run dry (a silent sample inserted = 1-sample timing slip)? usage: underruns.py T1 (CPU_SCALE, LINK_SLICE, DELAY_SAMPLES, GAIN env)"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
T1=float(sys.argv[1]); L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda m:(m.cpu.cycles-base)/CPU_HZ
ev={'A':[],'B':[]}; prev={'A':0,'B':0}; q={'A':[10**9,0],'B':[10**9,0]}
o_s=_M.Machine._sample
def s(self):
    nm='A' if self is L.a else 'B'
    r=o_s(self)
    if self.rx_under!=prev[nm]:
        ev[nm]+= [round(T(self),3)]*(self.rx_under-prev[nm]); prev[nm]=self.rx_under
    return r
_M.Machine._sample=s
while T(L.a)<T1: L.run(CPU_HZ//64)
for nm,m in (('A',L.a),('B',L.b)):
    late=[t for t in ev[nm] if t>=14.0]; print(nm,'underruns since 14 s:',len(late),'total',m.rx_under,'at',late[:60])
