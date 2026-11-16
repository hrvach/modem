"""find where the caller's DSP RX bytes come from: capture the first RX bank bytes after CONNECT, then search DSP data memory for them.
usage: rxsrc.py SECONDS"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; dur=float(sys.argv[1])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(dur*fs):
    L.run(CPU_HZ//4)
    if b'CONNECT' in L.txt['b']: break
m=L.b; m.dsp_log.clear(); L.run(CPU_HZ//4)
seq=[v for c,q,v in m.dsp_log if 0x58<=q<=0x5D]
print('B bank words',len(seq),seq[:30])
dm=m.dsp.dm
for k in (4,6,8):
    pat=seq[:k]
    for a in range(0x10000-k):
        if all((dm[a+i]&0xFF)==pat[i] for i in range(k)): print('match',k,hex(a)); break
        if all(dm[a+i]==pat[i] for i in range(k)): print('exactmatch',k,hex(a)); break
for i in range(0,64):
    pass
print('ar regs',{r:hex(m.dsp.get(r)) for r in ('AR0','AR1','AR2','AR3','AR4','AR5','AR6','AR7','PC')})
print('dm[0x20..0x2F]',[hex(dm[a]) for a in range(0x20,0x30)])
print('recent pcs',[hex(p) for p in m.dsp.recent_pcs(16)])
