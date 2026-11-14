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




def peaks(a,t0,t1): 
    x=a[int(t0*fs):int(t1*fs)]; return max([abs(v) for v in x] or [0])
def b20(): return [tt for tt,c,x in L.b.cmd_log16 if (c&0xFF)==0x20]
while not b20(): L.run(5_000_000)
t20=b20()[0]/fs; print("B sent cmd 20 at %.1f s"%t20)
while L.samples() < (t20+4)*fs: L.run(5_000_000)
print("B before poke: E88=%02X A has cmd21: %s"%(L.b.cpu.rd8(0xE88), any((c&0xFF)==0x21 for tt,c,x in L.a.cmd_log16)))
L.b.cpu.wr8(0xE88, L.b.cpu.rd8(0xE88) & 0xDF); t0=L.samples()/fs
for T in [t0+2,t0+6,t0+12,t0+25]:
    while L.samples() < T*fs: L.run(5_000_000)
    mm=L.b
    print("t=%d B E88=%02X 298=%04X 26E=%04X BD7=%02X peakB(last2s)=%d"%(T,mm.cpu.rd8(0xE88),mm.cpu.rd16(0x298),mm.cpu.rd16(0x26E),mm.cpu.rd8(0xBD7),peaks(L.audio['b'],T-2,T)),"cmds:",[("%.1f"%(tt/fs),"%04X"%c,"%04X"%x) for tt,c,x in mm.cmd_log16 if tt>(t0-5)*fs][:14])
    print("   A cmds:",[("%.1f"%(tt/fs),"%04X"%c,"%04X"%x) for tt,c,x in L.a.cmd_log16 if tt>(t0-5)*fs][:8], "DTE B:",L.txt['b'][-80:], "DTE A:",L.txt['a'][-60:])
