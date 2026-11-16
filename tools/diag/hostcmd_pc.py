"""print the 80186 code location (recent PCs) when the host writes DSP command CMD (default 0x54) on B or A; also dumps host RAM bytes of interest. usage: hostcmd_pc.py CMDHEX T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
import machine as _M
fs=7200; cmd=int(sys.argv[1],16); t1=float(sys.argv[2]); L=None
_iow=_M.Machine.iowr; hits=[]
def w(self,p,wd,v):
    if p==0x58 and ((v & 0xFF)==cmd) and self.dsp is not None:
        c=self.cpu; hits.append(('A' if self is L.a else 'B', L.samples()/fs, [hex(x) for x in c.recent(24)], c.state()))
    return _iow(self,p,wd,v)
_M.Machine.iowr=w
L=Link(); L.gain=0.5
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); hits.clear()
while L.samples() < int(t1*fs): L.run(CPU_HZ//8)
for nm,t,pcs,st in hits: print('%s t=%.2f recent PCs: %s\n   %s'%(nm,t,' '.join(pcs),st))
