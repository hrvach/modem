"""does the firmware ever install a TINT handler? write watch on the TINT vector cell data[0x63] (IFR bit 3 -> B *(data[0x60+3])): PCs that wrote it, and its value over time. usage: tintslot.py WHO T1"""
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
d=tgt.dsp; d.set_watch(0x63); last=None
while L.samples() < int(t1*fs):
    L.run(CPU_HZ//64); v=d.dm[0x63]
    if v!=last: print('t=%.3f data[0x63]=%04X'%(L.samples()/fs, v), flush=True); last=v
print('writers of data[0x63] (pc: count):', {hex(pc):d.watch_hits(pc) for pc in range(0x10000) if d.watch_hits(pc)})
