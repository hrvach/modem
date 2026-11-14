import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
from collections import Counter
fs=7200
L=Link(); L.run(900_000_000); L.text()
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(150_000_000)
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0; mm.cmd_log16.clear()
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < 24*fs: L.run(10_000_000)
for nm,mm in (("B",L.b),("A",L.a)):
    mm.port5_pcs.clear() if hasattr(mm.port5_pcs,'clear') else None
H={"A":Counter(),"B":Counter()}; seq={"A":[],"B":[]}
for k in range(1500):
    L.run(100_000)
    for nm,mm in (("B",L.b),("A",L.a)):
        v=mm.cpu.rd8(0xBD7); H[nm][v]+=1; seq[nm].append(v)
for nm in "BA":
    print(nm,"[BD7] histogram:",sorted(H[nm].items()))
    print(nm,"first 120:",''.join("%02X "%v for v in seq[nm][:120]))
for nm,mm in (("B",L.b),("A",L.a)):
    print(nm,"DSP port 5E/5F writes by (pc,port,val):",mm.port5_pcs.most_common(14))
