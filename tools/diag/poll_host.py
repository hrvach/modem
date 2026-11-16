"""poll host RAM bytes of both modems during a call; print changes. usage: poll_host.py T0 T1 ADDR[,ADDR...]"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; t0=float(sys.argv[1]); t1=float(sys.argv[2]); addrs=[int(a,16) for a in sys.argv[3].split(',')]
L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); prev={}
while L.samples() < int(t1*fs):
    L.run(CPU_HZ//64); t=L.samples()/fs
    for nm,m in (('A',L.a),('B',L.b)):
        v=tuple(m.cpu.rd8(a) for a in addrs)
        if prev.get(nm)!=v:
            if t>=t0 or prev.get(nm) is None: print('%6.2f %s %s'%(t,nm,' '.join('[%03X]=%02X'%(a,x) for a,x in zip(addrs,v))),flush=True)
            prev[nm]=v
