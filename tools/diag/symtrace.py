"""trace the per-symbol scheduler of modem B (ov6 9F33 / 9F3E / 9F6C / 9F5A) with the codec tick count. usage: symtrace.py T0 T1 (DELAY_SAMPLES env)"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
fs=7200; T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=0.5; log=[]
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
tgt=L.b; d=tgt.dsp; PCS=(0x9F33,0x9F3E,0x9F6C,0x9F5A)
for p in PCS: d.bp(p)
ticks=[0]; ot=d.serial_tick
def tick(v): ticks[0]+=1; ot(v)
d.serial_tick=tick; orig=_M.Machine._sample
def s(self):
    r=orig(self)
    if self is tgt:
        pc=d.get("PC")
        if pc in PCS and T0<=L.samples()/fs<=T1: log.append((ticks[0],pc,d.dm[0x34B],d.dm[0x31A],d.dm[0x32C]))
    return r
_M.Machine._sample=s
while L.samples()<int((T1+0.05)*fs): L.run(CPU_HZ//32)
print('tick  pc    [34B] [31A] [32C]')
for t,pc,a,b,c in log: print('%6d %04X  %04X  %04X  %04X'%(t,pc,a,b,c))
