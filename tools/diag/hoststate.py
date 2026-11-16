"""log changes of the host's start-up state machine variables on both modems: [0x298] state handler, [0x13A] timer, [0x13C] timer callback, [0x33F] flags, [0x600], [0xB2D] rate mask, [0x3BC] rate index. usage: hoststate.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; t0=float(sys.argv[1]); t1=float(sys.argv[2]); L=Link(); L.gain=0.5
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
prev={}
while L.samples() < int(t1*fs):
    L.run(CPU_HZ//32); t=L.samples()/fs
    if t<t0: continue
    for nm,m in (('A',L.a),('B',L.b)):
        c=m.cpu; v=(c.rd16(0x298),c.rd16(0x13A),c.rd16(0x13C),c.rd16(0x33F)&0xFF,c.rd8(0x600),c.rd16(0xB2D),c.rd8(0x3BC))
        key=(v[0],v[2],v[3],v[4],v[5],v[6])
        if prev.get(nm)!=key: print('%6.2f %s state=%04X timer=%04X cb=%04X f33F=%02X [600]=%02X mask=%04X rate=%02X'%((t,nm,v[0],v[1],v[2],v[3],v[4],v[5],v[6])),flush=True); prev[nm]=key
