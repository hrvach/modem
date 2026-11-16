"""caller's RX bit packer (DSP 8317/831C/8333/8349): mode word [0x37A]&3 and hit counts on both modems shortly after CONNECT.
usage: rxsrc2.py SECONDS"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; dur=float(sys.argv[1])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(dur*fs):
    L.run(CPU_HZ//4)
    if b'CONNECT' in L.txt['b']: break
for m in (L.a,L.b): m.dsp.pc_hits_clear()
L.run(CPU_HZ//2)
for nm,m in (('A',L.a),('B',L.b)):
    d=m.dsp
    print(nm,'mode [0x37A]=%04X'%d.dm[0x37A],'hits 8317=%d 831C=%d 8333=%d 8349=%d 8324=%d 8300=%d'%tuple(d.pc_hits(a) for a in (0x8317,0x831C,0x8333,0x8349,0x8324,0x8300)))
    print('  page6 0x320..0x32F',[hex(d.dm[0x300+i]) for i in range(0x20,0x30)])
    bk={}
    for a in range(0x8000,0x10000): bk[a>>8]=bk.get(a>>8,0)+d.pc_hits(a)
    tot=sum(bk.values()) or 1
    print('  buckets >2%:',[('%02X00'%k,round(100*v/tot)) for k,v in sorted(bk.items()) if v*50>tot],' ovl_loads',m.ovl_loads[:6])
    hot=sorted(((d.pc_hits(a),a) for a in range(0x8000,0xC000)),reverse=True)[:25]
    print('  hottest PCs',[(hex(a),n) for n,a in hot])
