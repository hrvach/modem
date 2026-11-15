import sys, collections; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
from machine import CPU_HZ
fs=7200; t0=float(sys.argv[1]); t1=float(sys.argv[2]); which=sys.argv[3] if len(sys.argv)>3 else 'a'
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
m=L.a if which=='a' else L.b
pcs=collections.Counter(); prev=None
while L.samples() < int(t1*fs):
    L.run(CPU_HZ//200)
    t=L.samples()/fs
    if t>=t0:
        pcs[m.cpu.phys_pc()-0x80000]+=1
        w=int(t)//5
        if w!=prev and pcs:
            pass
print("top PCs %.0f-%.0f s:"%(t0,t1),[('%05X'%p,n) for p,n in pcs.most_common(30)])
c=m.cpu; print('E3C=%02X E3B=%02X 134=%04X 32B=%02X 32C=%02X BD7=%02X'%(c.rd8(0xE3C),c.rd8(0xE3B),c.rd16(0x134),c.rd8(0x32B),c.rd8(0x32C),c.rd8(0xBD7)))

ss=c.get('SS'); sp=c.get('SP'); print('B stack:',' '.join('%04X'%c.rd16(ss*16+sp+2*i) for i in range(24)))
print('3CE=%02X 3B1=%04X 3AF=%04X 3B3=%04X 3B5=%04X 4C6=%02X 4CA=%02X 4CE=%02X'%(c.rd8(0x3CE),c.rd16(0x3B1),c.rd16(0x3AF),c.rd16(0x3B3),c.rd16(0x3B5),c.rd8(0x4C6),c.rd8(0x4CA),c.rd8(0x4CE)))
