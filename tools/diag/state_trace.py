"""per-half-second supervisor state during a two-modem call: hooks [0x30] [0x138] [0x298], mode [0x32B], flags [0x32C], E88, E8A, 134"""
import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
from machine import CPU_HZ
fs=7200; dur=float(sys.argv[1])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
t=0
while L.samples() < int(dur*fs):
    L.run(CPU_HZ//2); t+=0.5
    s=[]
    for nm,mm in (('A',L.a),('B',L.b)):
        c=mm.cpu
        s.append("%s h30=%04X h138=%04X h298=%04X 32B=%02X 32C=%02X E88=%02X E8A=%02X 134=%04X pc=%05X"%(nm,c.rd16(0x30),c.rd16(0x138),c.rd16(0x298),c.rd8(0x32B),c.rd8(0x32C),c.rd8(0xE88),c.rd8(0xE8A),c.rd16(0x134),c.phys_pc()-0x80000))
    print("t=%4.1f"%t,' | '.join(s))
