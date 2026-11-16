"""disassemble DSP program memory of B at call time T. usage: dispm.py T LO HI"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys'); sys.path.insert(0, ROOT+'/tools')
from link import *
from machine import CPU_HZ
import importlib.util as _u; _s=_u.spec_from_file_location('c5xdis',ROOT+'/tools/c5x.py'); c5x=_u.module_from_spec(_s); _s.loader.exec_module(c5x)
fs=7200; T=float(sys.argv[1]); lo=int(sys.argv[2],16); hi=int(sys.argv[3],16)
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples()<int(T*fs): L.run(CPU_HZ//16)
d=L.b.dsp; pc=lo
while pc<hi:
    n,t,i=c5x.dis(lambda a:d.pm[a&0xFFFF],pc); print('%04X %s'%(pc,t)); pc+=n
