import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
from collections import Counter
fs=7200
L=Link(); L.run(900_000_000); L.text()
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(150_000_000)
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0; mm.cmd_log16.clear()
from collections import Counter
CNT={'a':Counter(),'b':Counter()}
for k,mm in (('a',L.a),('b',L.b)):
    orig=mm.cpu.irq
    def w(v,orig=orig,k=k): CNT[k][v]+=1; return orig(v)
    mm.cpu.irq=w
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")

for nm,mm in (("B",L.b),("A",L.a)):
    mm.port5_pcs.clear() if hasattr(mm.port5_pcs,'clear') else None



for T in (24,26,28,30):
    while L.samples() < T*fs: L.run(5_000_000)
    for nm,mm in (("B",L.b),("A",L.a)):
        k=nm.lower(); r=mm.cpu.rd16
        print("t=%d %s irqs:%s [134]=%04X pcb38=%s hb_pending=%s ivt30=%04X:%04X pcb=%s"%(T,nm,dict(CNT[k]),r(0x134),mm.pcb.get(0x38),mm.hb_pending,r(0x32),r(0x30),{hex(a):hex(v) for a,v in sorted(mm.pcb.items()) if a in (0x22,0x24,0x28,0x2A,0x2C,0x30,0x32,0x34,0x36,0x38,0x3A)}))
    CNT['a'].clear(); CNT['b'].clear()
