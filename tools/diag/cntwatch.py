"""log the B-side wait counters of callback A478 (data page 6: [0x334], [0x336]) plus neighbours, and A's callback 900D neighbourhood, every 0.5 s.
usage: cntwatch.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; t0=float(sys.argv[1]); t1=float(sys.argv[2])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
t=t0
while t<=t1:
    while L.samples() < int(t*fs): L.run(CPU_HZ//16)
    d=L.b.dsp.dm; a=L.a.dsp.dm
    print('%6.2f B [3B4]=%04X [3B6]=%04X p7[B0..B9]=%s | A p6[30..3F]=%s'%(t,d[0x3B4],d[0x3B6],' '.join('%04X'%d[0x3B0+i] for i in range(0,10)),' '.join('%04X'%a[0x3B0+i] for i in range(0,10))),flush=True)
    t+=0.5
