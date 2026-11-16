"""per exit-test frame (9F6C) of modem B: codec ticks and A2A7 (receive filter) calls since the previous frame, to see whether the filter runs more/less often than the codec delivers samples around a failing frame. usage: framecalls.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
import machine as _M
fs=7200; T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=0.5; rec=[]
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
tgt=L.b; d=tgt.dsp; d.bp(0x9F6C); ticks=[0]; ot=d.serial_tick
def tick(v): ticks[0]+=1; ot(v)
d.serial_tick=tick; orig=_M.Machine._sample
def s(self):
    r=orig(self)
    if self is tgt and d.get("PC")==0x9F6C and T0<=L.samples()/fs<=T1:
        dm=d.dm; sg=lambda v: v-65536 if v>=32768 else v
        rec.append((L.samples()/fs,ticks[0],d.pc_hits(0xA2A7),dm[0x334],[sg(v) for v in dm[0x300:0x304]]))
    return r
_M.Machine._sample=s
while L.samples()<int((T1+0.05)*fs): L.run(CPU_HZ//32)
print('t        d_ticks d_A2A7 ctr  block a')
for i in range(1,len(rec)):
    t,tk,ca,c,a=rec[i]; p=rec[i-1]
    print('%.4f  %3d     %3d    %2d   %s'%(t,tk-p[1],ca-p[2],c,a))
