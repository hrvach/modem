"""how often do the DSP ISRs run in a call? PC hit counts of the ISR entry points. usage: isrhits.py WHO T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; who=sys.argv[1]; t1=float(sys.argv[2]); L=Link(); L.gain=0.5
tgt=L.a if who=='A' else L.b
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
d=tgt.dsp; d.pc_hits_clear(); s0=L.samples(); c0=d.total_cycles()
while L.samples() < int(t1*fs): L.run(CPU_HZ//16)
n=L.samples()-s0; print('samples',n,'dsp cycles',d.total_cycles()-c0,'cycles/sample %.0f'%((d.total_cycles()-c0)/n))
for nm,pc in (('XINT ISR 8189',0x8189),('820C (INT4/timer?)',0x820C),('81B7',0x81B7),('bare rete 81AE',0x81AE)): print('%-22s hits %d  (%.3f per sample)'%(nm,d.pc_hits(pc),d.pc_hits(pc)/n))
