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

for nm,mm in (("B",L.b),("A",L.a)):
    print(nm,"E88=%02X EA6=%02X EA7=%02X E3C=%02X BD7=%02X 3BDE=%02X"%tuple(mm.cpu.rd8(x) for x in (0xE88,0xEA6,0xEA7,0xE3C,0xBD7,0x3BDE)), "26E=%04X 26A=%04X 298=%04X"%tuple(mm.cpu.rd16(x) for x in (0x26E,0x26A,0x298)))
PC={"A":Counter(),"B":Counter()}
for k in range(3000):
    L.run(20_000)
    for nm,mm in (("B",L.b),("A",L.a)): PC[nm][mm.cpu.phys_pc()]+=1
for nm in "BA": print(nm,"hot pcs:",[("%05X"%(p-0x80000 if p>=0x80000 else p),c) for p,c in PC[nm].most_common(12)])
