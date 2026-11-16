"""parse each modem's DXR stream for TLC320AC01 secondary words: a primary word with D1D0 = 11 is followed by a 16-bit control word
(DS15-14 control, DS13 R/W, DS12-8 register address, DS7-0 data). Print every register write with its DXR index and call time. usage: aicparse.py T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; t1=float(sys.argv[1])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(t1*fs): L.run(CPU_HZ//8)
for nm,m in (('A',L.a),('B',L.b)):
    x=[v & 0xFFFF for v in m.tx_all]; t0=m.dsp_started_at/CPU_HZ
    i=0; last=None
    while i < len(x)-1:
        if (x[i] & 3)==3:
            w=x[i+1]; reg=(w>>8)&0x1F; val=w&0xFF; rw=(w>>13)&1; ctl=w>>14
            print('%s dxr#%d (%.2f s after DSP start) primary=%04X secondary=%04X ctl=%d rw=%d reg=%d data=0x%02X (%d)'%(nm,i,i/7200.0,x[i],w,ctl,rw,reg,val,val)); i+=2
        else: i+=1
