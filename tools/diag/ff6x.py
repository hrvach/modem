"""writers of data FF61 (and FF60) in a call: usage ff6x.py SECONDS"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
d=L.a.dsp; d.set_watch(0xFF61)
while L.samples() < int(float(sys.argv[1])*fs): L.run(CPU_HZ//2)
print("FF61 writers:",[("%04X"%pc,d.watch_hits(pc)) for pc in range(0x8000,0x10000) if d.watch_hits(pc)])
print("FF61 value", "%04X"%d.pm[0xFF61] if hasattr(d,'pm') else '')
