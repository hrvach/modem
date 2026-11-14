import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
from collections import Counter, defaultdict
fs=7200
L=Link(); L.run(900_000_000); L.text()
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(150_000_000)
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0; mm.cmd_log16.clear(); mm.log=[]; mm.logging=True
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < 20*fs:
    L.run(10_000_000)
    for mm in (L.a,L.b):
        if len(mm.log)>3_000_000: del mm.log[:1_000_000]
for nm,mm in (("A",L.a),("B",L.b)):
    R=Counter(); W=defaultdict(Counter)
    for e in mm.log:
        p=e[1]
        if 0x40<=p<=0x5F: continue
        if e[0]=="R": R[p]+=1
        else: W[p][e[3]]+=1
    print("==",nm,"reads (non-DSP ports):",sorted(R.items()))
    print("   writes:",{ "%02X"%p:dict(c.most_common(6)) for p,c in sorted(W.items())})
