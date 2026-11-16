"""timeline of call set-up: harness states (Link.events), first DTMF/answer-tone energy on each modem's DAC, host text events (RING, CONNECT) and the host commands. usage: calltl.py T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
T1=float(sys.argv[1]); L=Link(); L.gain=0.5
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda m=L.a:(m.cpu.cycles-base)/CPU_HZ
ev=[]; seen={'A':0,'B':0}; first={}
sg=lambda v: v-65536 if v>=32768 else v
o_t=_M.Machine.take_tx
def tx(self):
    out=o_t(self)
    nm='A' if self is L.a else 'B'
    for i,v in enumerate(out):
        if abs(sg(v&0xFFFF))>1500 and nm not in first: first[nm]=T(self)-(len(out)-i)/self.rate; ev.append((first[nm],'%s DAC first output above 1500 (first sound)'%nm))
    return out
_M.Machine.take_tx=tx
last_txt={'a':0,'b':0}
while T()<T1:
    L.run(CPU_HZ//64)
    for k,nm in (('a','A'),('b','B')):
        t=L.txt[k]
        for w in (b'RING',b'CONNECT',b'OK',b'NO CARRIER'):
            if w in t and (nm,w) not in first: first[(nm,w)]=T(); ev.append((T(),'%s host printed %s'%(nm,w.decode())))
for t,st in L.events: ev.append((t-0.0,'harness state -> %s (Link time base 7200 Hz units)'%st))
for m,nm in ((L.a,'A'),(L.b,'B')):
    for c,cmd,arg in m.cmd_log[:6]: ev.append(((c-base)/CPU_HZ,'%s host->DSP cmd %02X/%02X'%(nm,cmd&0xFF,arg&0xFF)))
for t,w in sorted(ev): print('%7.3f  %s'%(t,w))
