"""B DSP acquisition gate (handler 9E56 via callback 9DCF): per hit print call time, [0x32C], level acc ([0x300]<<16 + [0x302]) vs threshold 0x445C, [0x334]. usage: acq9e56.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
import machine as _M
fs=7200; T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=float(os.environ.get('GAIN','0.5')); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
d=L.b.dsp; d.bp(0x9E5A); orig=_M.Machine._sample; out=[]; n=[0]
sg=lambda v: v-65536 if v>=32768 else v
def s(self):
    r=orig(self)
    if self is L.b and d.get('PC')==0x9E5A and T0<=L.samples()/fs<=T1:
        n[0]+=1; dm=d.dm
        if n[0]%4==1: out.append('%.4f ctdn[32C]=%04X lvl=[300]:%04X [302]:%04X [334]=%d  x%d'%(L.samples()/fs,dm[0x32C],dm[0x300],dm[0x302],sg(dm[0x334]),n[0]))
    return r
_M.Machine._sample=s
while L.samples()<int(T1*fs): L.run(CPU_HZ//64)
print('\n'.join(out[:60])); print('hits',n[0])
