import sys; sys.path.insert(0,'.')
from link import *
L=Link()
L.run(900_000_000); L.text()
for m,cmds in ((L.a,("AT\r","ATQ0V1\r")),(L.b,("AT\r","ATQ0V1X3\r"))):
    for c in cmds: m.send(c); L.run(150_000_000)
L.text()
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(30*7200): L.run(10_000_000)
for m in (L.a,L.b): m.port5_pcs.clear()
while L.samples() < int(36*7200): L.run(10_000_000)
for nm,m in (('B caller',L.b),('A callee',L.a)):
    print(nm,"DSP writes to ports 5E/5F in 6 s, by (DSP pc, port, value):")
    for (pc,q,v),n in sorted(m.port5_pcs.items(), key=lambda x:-x[1])[:14]: print("    pc=%04X port=%02X value=%04X  x%d"%(pc,q,v,n))
