"""clock drift between the two modems: A.cpu.cycles - B.cpu.cycles and the codec tick counts, per few seconds of call time. usage: drift.py T1 (LINK_SLICE env)"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
dh=lambda m: m.dsp.dxr_head() if m.dsp else 0
T1=float(sys.argv[1]); L=Link(); L.gain=0.5; n=[0,0]
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])): pass
L.start_call("1"); t=0
while t<T1:
    L.run(CPU_HZ//2); t+=0.5
    print('t=%4.1f  A-B cpu cycles %+7d (%.3f ms)  A dxr %d  B dxr %d (diff %+d)'%(t,L.a.cpu.cycles-L.b.cpu.cycles,(L.a.cpu.cycles-L.b.cpu.cycles)*1000/CPU_HZ,dh(L.a),dh(L.b),dh(L.a)-dh(L.b)),flush=True)
