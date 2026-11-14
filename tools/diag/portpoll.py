import sys; sys.path.insert(0,'.')
from link import *
from collections import Counter
L=Link()
L.run(900_000_000); L.text()
for m,cmds in ((L.a,("AT\r","ATQ0V1\r")),(L.b,("AT\r","ATQ0V1X3\r"))):
    for c in cmds: m.send(c); L.run(150_000_000)
L.text()
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(28*7200): L.run(10_000_000)
for m in (L.a,L.b): m.logging=True; m.log.clear()
while L.samples() < int(34*7200): L.run(10_000_000)
for nm,m in (('A callee',L.a),('B caller',L.b)):
    c=Counter()
    for e in m.log:
        if e[0]=="R" and e[1] in (0x10,0x12,0x14,0x0b,0x00,0x0a,0x16,0x1c,0x1e): c[(hex(e[1]),"%05X"%(e[-1]-0x80000 if e[-1]>=0x80000 else e[-1]))]+=1
    print(nm,"reads of status ports by (port, flash pc) in 6 s of audio:",c.most_common(16))
    w=Counter((hex(e[1]),hex(e[3] & 0xFF)) for e in m.log if e[0]=="W" and e[1] in (0x10,0x12,0x14,0x16,0x0e,0x00,0x02,0x03,0x0a))
    print(nm,"writes to latch ports (port,value):",w.most_common(14))
