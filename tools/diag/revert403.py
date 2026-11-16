"""catch the DSP of modem WHO when its codec rate changes after T0: PC ring, state, selected cells. usage: revert403.py WHO T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as M
from machine import CPU_HZ
who=sys.argv[1]; t0=float(sys.argv[2]); t1=float(sys.argv[3]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
tgt=L.a if who=='A' else L.b; base=tgt.cpu.cycles; d=tgt.dsp; orig=tgt.set_rate; seen=[0]
def sr(r):
    t=(tgt.cpu.cycles-base)/CPU_HZ
    if t>=t0 and r!=tgt.rate and seen[0]<3:
        seen[0]+=1; print('--- set_rate(%d) at t=%.3f (was %d)'%(r,t,tgt.rate)); print('state',d.state()); print('recent PCs',' '.join('%04X'%p for p in d.recent_pcs(48)))
        print('cells 0x300-0x30F',' '.join('%04X'%d.dm[0x300+i] for i in range(16)),'| 0x31A..',' '.join('%04X'%d.dm[0x31A+i] for i in range(6)))
    orig(r)
tgt.set_rate=sr
while (tgt.cpu.cycles-base) < t1*CPU_HZ: L.run(CPU_HZ//8)
print('done; msgs after t0:',[(round((x[5]-base)/CPU_HZ,2),'%02X/%04X'%(x[3]&0xFF,x[4])) for x in tgt.msg_log if (x[5]-base)/CPU_HZ>=t0][:20])
