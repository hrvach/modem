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
while L.samples() < int(30*7200): L.run(10_000_000)
for nm,m in (('B',L.b),('A',L.a)):
    m.dsp.set_trace(0x83C8)
for _ in range(3): L.run(10_000_000)
for nm,m in (('B caller',L.b),('A callee',L.a)):
    tr=m.dsp.trace()
    print(nm,"calls of 83C8 (post):",len(tr))
    c=Counter((hex(r2)) for a,r,r2 in tr); print("  by DSP return address (caller):",c.most_common(10))
    c2=Counter(("%08X"%a) for a,r,r2 in tr); print("  by ACC at call:",c2.most_common(12))
