"""time line (CPU-cycle seconds) of host->DSP commands, DSP->host messages, A's S onset on the line and B's stage entry. usage: cmdtl.py T0 T1 (DELAY_SAMPLES env)"""
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
base=L.a.cpu.cycles; ev=[]
tg=L.b; d=tg.dsp; d.bp(0x9DFD)
sg=lambda v: v-65536 if v>=32768 else v
T=lambda m:(m.cpu.cycles-base)/CPU_HZ
o_s=_M.Machine._sample; o_t=_M.Machine.take_tx; st={'A_on':None,'amp':0}
def s(self):
    r=o_s(self)
    if self is tg and d.get("PC")==0x9DFD and d.dm[0x6F]==0x0AC0: ev.append((T(self),'B stage entry (9DFD, [6F]=0AC0)'))
    return r
def tx(self,*a,**k):
    out=o_t(self,*a,**k)
    if self is L.a and st['A_on'] is None and out:
        for i,v in enumerate(out):
            if abs(sg(v&0xFFFF))>3000 and T0<=T(self)<=T1: st['A_on']=T(self)-(len(out)-i)/self.rate; break
    return out
_M.Machine._sample=s; _M.Machine.take_tx=tx
while T(L.a)<T1+0.05: L.run(CPU_HZ//64)
for nm,m in (('A',L.a),('B',L.b)):
    for c,cmd,arg in m.cmd_log:
        t=(c-base)/CPU_HZ
        if T0<=t<=T1: ev.append((t,'%s host->DSP cmd %04X arg %04X'%(nm,cmd&0xFFFF,arg&0xFFFF)))
    for e in m.msg_log:
        if len(e)>5:
            t=(e[5]-base)/CPU_HZ
            if T0<=t<=T1: ev.append((t,'%s DSP->host msg tag %02X'%(nm,e[3]&0xFF)))
if st['A_on']: ev.append((st['A_on'],'A line signal onset (|dac|>3000)'))
for t,w in sorted(ev): print('%.4f  %s'%(t,w))
