import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; dur=float(sys.argv[1])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
nxt=24
while L.samples() < int(dur*fs):
    L.run(CPU_HZ); t=L.samples()/fs
    if t>=nxt:
        nxt+=4; s=[]
        for nm,m in (('A',L.a),('B',L.b)):
            c=m.cpu; s.append("%s 34E=%04X 356=%04X 358=%04X 3CA=%04X 3CC=%04X 3C9=%02X 2EA=%04X 2EC=%04X 3CE=%02X rx=%d"%(nm,c.rd16(0x34E),c.rd16(0x356),c.rd16(0x358),c.rd16(0x3CA),c.rd16(0x3CC),c.rd8(0x3C9),c.rd16(0x2EA),c.rd16(0x2EC),c.rd8(0x3CE),len(L.txt['a' if nm=='A' else 'b'])))
        print("t=%5.1f"%t,' | '.join(s))
