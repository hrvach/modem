"""follow the ov6 main-thread step script ([0x70] function, [0x71] countdown, [0x72]) and the state cells on both DSPs, printing every change of [0x70]/[0x6D]/[0x32F]. usage: stepscript.py T0 T1"""
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
prev={}; nxt={}
o_s=_M.Machine._sample
def s(self):
    r=o_s(self); nm='A' if self is L.a else 'B'; t=T(self)
    if T0<=t<=T1:
        d=self.dsp; v=(d.dm[0x70],d.dm[0x6D],d.dm[0x32F]); p=prev.get(nm)
        if p!=v: print('%.4f %s [70]=%04X [6D]=%04X [32F]=%04X  [71]=%04X [72]=%04X [6E]=%04X [6F]=%04X [334]=%04X [31A]=%04X [330]=%04X'%(t,nm,v[0],v[1],v[2],d.dm[0x71],d.dm[0x72],d.dm[0x6E],d.dm[0x6F],d.dm[0x334],d.dm[0x31A],d.dm[0x330])); prev[nm]=v
    return r
_M.Machine._sample=s
while T(L.a)<T1: L.run(CPU_HZ//64)
