"""who sets the resampler reload cell [0x3A0] (= [DP 0x380 : 0x20] of A2A7)? Polls it during the call, and counts writes per PC with the DSP data watch.
usage: a2a7reload.py WHO T1"""
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
d=tgt.dsp; d.set_watch(0x3A0); last=None; log=[]
while L.samples() < int(t1*fs):
    L.run(CPU_HZ//64)
    v=(d.dm[0x3A0], d.dm[0x3BC], d.dm[0x3A3], d.dm[0x3A1])
    if v!=last: log.append((round(L.samples()/fs,3),)+tuple('%04X'%x for x in v)); last=v
print('time  [3A0] [3BC] [3A3] [3A1] (changes only; first 60)')
for e in log[:60]: print(*e)
print('writes to 0x3A0 by PC:', {hex(pc):d.watch_hits(pc) for pc in range(0x10000) if d.watch_hits(pc)})
