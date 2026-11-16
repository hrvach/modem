"""profile the two-modem emulation for WINDOW seconds of call time starting at T0 (cProfile on the python glue). usage: prof.py T0 WINDOW"""
import os, sys, cProfile, pstats, io, time; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
T0=float(sys.argv[1]); W=float(sys.argv[2]); L=Link(); L.gain=0.5
t=time.time(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda: (L.a.cpu.cycles-base)/CPU_HZ
while T()<T0: L.run(CPU_HZ//32)
t1=time.time(); pr=cProfile.Profile(); pr.enable()
while T()<T0+W: L.run(CPU_HZ//32)
pr.disable(); t2=time.time()
print('emulated %.1f s of call time in %.1f s of wall time (%.1fx slower than real time), two modems'%(W,t2-t1,(t2-t1)/W))
s=io.StringIO(); ps=pstats.Stats(pr,stream=s).sort_stats('tottime'); ps.print_stats(22); print(s.getvalue()[:5200])
