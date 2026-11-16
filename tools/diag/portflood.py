"""aggregate the host (80186) writes to the mailbox ports in a call-time window, per modem: counts of (port,value) and rounds per second. usage: portflood.py T0 T1"""
import os, sys, collections; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); base=L.b.cpu.cycles
on=False
while L.samples() < int(T1*7200):
    t=L.samples()/7200
    if not on and t>=T0:
        on=True
        for m in (L.a,L.b): m.logging=True; m.log.clear()
    L.run(CPU_HZ//16)
for k,m in (('A',L.a),('B',L.b)):
    m.logging=False
    w=[e for e in m.log if e[0]=='W' and e[1] in (0x58,0x5A,0x5C,0x5E,0x1C,0x1E)]
    c=collections.Counter((e[1],e[3]) for e in w)
    byport=collections.Counter(e[1] for e in w)
    print(k,'window %.0f-%.0f s: writes to 0x58/5A/5C/5E/1C/1E:'%(T0,T1),dict((hex(p),n) for p,n in byport.items()))
    print(k,'most common (port,value):',[('%02X'%p,'%04X'%v,n) for (p,v),n in c.most_common(10)])
    words=collections.Counter()
    # reconstruct (0x58,0x5A) pairs and (0x5C,0x5E) pairs written back to back
    lo=None
    for e in w:
        if e[1]==0x58: lo=e[3]&0xFF
        elif e[1]==0x5A and lo is not None: words[(lo|((e[3]&0xFF)<<8))]+=1; lo=None
    print(k,'tag words (0x58 lo + 0x5A hi):',[('%04X'%v,n) for v,n in words.most_common(8)])
