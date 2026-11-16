"""watch DSP data cells over call time. usage: cdwatch.py WHO T0 T1 STEP_MS ADDR[,ADDR...]"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
who=sys.argv[1]; t0=float(sys.argv[2]); t1=float(sys.argv[3]); step=float(sys.argv[4])/1000; addrs=[int(a,16) for a in sys.argv[5].split(',')]
L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
tgt=L.a if who=='A' else L.b; base=tgt.cpu.cycles; d=tgt.dsp; nxt=t0
while (tgt.cpu.cycles-base) < t1*CPU_HZ:
    L.run(max(1,int(CPU_HZ*step/4))); t=(tgt.cpu.cycles-base)/CPU_HZ
    if t>=nxt:
        print('t=%.3f rate %5d  %s'%(t,tgt.rate,' '.join('[%03X]=%04X'%(a,d.dm[a]) for a in addrs)),flush=True); nxt+=step
