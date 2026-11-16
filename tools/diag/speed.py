"""wall time to emulate WINDOW seconds of call time for the current LINK_SLICE (no profiler). usage: speed.py T0 WINDOW"""
import os, sys, time; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
T0=float(sys.argv[1]); W=float(sys.argv[2]); L=Link(); L.gain=0.5
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda: (L.a.cpu.cycles-base)/CPU_HZ
while T()<T0: L.run(CPU_HZ//32)
t1=time.time()
while T()<T0+W: L.run(CPU_HZ//32)
print('LINK_SLICE=%s: %.1f s of call time in %.1f s wall = %.1fx real time'%(os.environ.get('LINK_SLICE','100000'),W,time.time()-t1,(time.time()-t1)/W))
