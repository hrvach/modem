"""print every change of the script pointer [0x3CB], routine [0x348], count [0x34A], status [0x6F] and the call/return words [0x39A],[0x39B] on both DSPs between T0 and T1 (poll 1/32 s).
usage: scriptwatch.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; t0=float(sys.argv[1]); t1=float(sys.argv[2])
L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
prev={}
while L.samples() < int(t1*fs):
    L.run(CPU_HZ//32); t=L.samples()/fs
    if t<t0: continue
    for nm,m in (('A',L.a),('B',L.b)):
        d=m.dsp.dm; v=(d[0x3CB],d[0x348],d[0x34A],d[0x6F],d[0x39A],d[0x39B])
        if prev.get(nm)!=v:
            print('%6.2f %s 4B=%04X 48=%04X 4A=%04X 6F=%04X 9A/9B=%04X/%04X'%((t,nm)+v),flush=True); prev[nm]=v
