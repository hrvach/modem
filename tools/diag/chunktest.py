"""is the emulation independent of how the harness chunks L.run()? run the call to T1 with a given chunk (cycles) and print the retrain marker time ([6D] = 8F33 on B after 17 s) and the first A417 times. usage: chunktest.py T1 CHUNK_DIVISOR (CPU_SCALE, LINK_SLICE env)"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
T1=float(sys.argv[1]); DIV=int(sys.argv[2]); L=Link()
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.gain=float(os.environ.get('GAIN','0.5')); L.echo=0.0; L.start_call("1")
base=L.a.cpu.cycles; T=lambda m:(m.cpu.cycles-base)/CPU_HZ
mark={}; o_s=_M.Machine._sample
def s(self):
    r=o_s(self); nm='A' if self is L.a else 'B'; d=self.dsp; v=d.dm[0x6D]
    if v==0xA417 and ('a417',nm) not in mark: mark[('a417',nm)]=T(self)
    if v==0x8F33 and ('retrain',nm) not in mark and T(self)>17: mark[('retrain',nm)]=T(self)
    return r
_M.Machine._sample=s
while T(L.a)<T1: L.run(CPU_HZ//DIV)
print('chunk 1/%d s: '%DIV,{k:round(v,3) for k,v in sorted(mark.items())})
