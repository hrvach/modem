"""receive-queue length and DXR head of both modems over a short window. usage: qseries.py T0 T1 STEP_SAMPLES"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
T0=float(sys.argv[1]); T1=float(sys.argv[2]); STEP=int(sys.argv[3]); L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda m:(m.cpu.cycles-base)/CPU_HZ
n={'A':0,'B':0}; o_s=_M.Machine._sample
def s(self):
    nm='A' if self is L.a else 'B'; r=o_s(self)
    if T0<=T(self)<=T1:
        n[nm]+=1
        if n[nm]%STEP==0: print('%.4f %s queue %3d under %d dxr %d rate %d'%(T(self),nm,len(self.rxbuf),self.rx_under,self.dsp.dxr_head(),self.rate))
    return r
_M.Machine._sample=s
while T(L.a)<T1: L.run(CPU_HZ//64)
