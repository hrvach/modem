"""complete DSP hardware access inventory over a call: every IN/OUT port (count, PCs, distinct values), memory-mapped MMR / peripheral / reserved / external accesses, XF pin toggles,
interrupt mask and vectors. usage: hwinv.py SECONDS"""
import os, sys, collections; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
import machine as _M
from machine import CPU_HZ
RD=collections.defaultdict(lambda: collections.defaultdict(collections.Counter)); VAL=collections.defaultdict(lambda: collections.defaultdict(collections.Counter)); WR=collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
_rd=_M.Machine.dsp_rd; _wr=_M.Machine.dsp_wr
def rd(self,p):
    v=_rd(self,p); q=p&0xFFFF; k='A' if self is L.a else 'B'; RD[k][q][self.dsp.get('PC')]+=1; VAL[k][q][v&0xFFFF]+=1; return v
def wr(self,p,v):
    q=p&0xFFFF; k='A' if self is L.a else 'B'; WR[k][q][self.dsp.get('PC')]+=1; return _wr(self,p,v)
_M.Machine.dsp_rd=rd; _M.Machine.dsp_wr=wr
from link import *
fs=7200; dur=float(sys.argv[1]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
for m in (L.a,L.b): m.dsp.pc_hits_clear()
while L.samples() < int(dur*fs): L.run(CPU_HZ//4)
for k,m in (('A',L.a),('B',L.b)):
    d=m.dsp; print('=====',k)
    print('I/O ports read (port: reads, distinct values, top PCs):')
    for q in sorted(RD[k]): 
        n=sum(RD[k][q].values()); vs=VAL[k][q]; print('  IN  %04X %9d reads, %d distinct values %s  PCs %s'%(q,n,len(vs),list(vs.most_common(3)),['%04X:%d'%x for x in RD[k][q].most_common(3)]))
    print('I/O ports written:')
    for q in sorted(WR[k]): print('  OUT %04X %9d writes  PCs %s'%(q,sum(WR[k][q].values()),['%04X:%d'%x for x in WR[k][q].most_common(3)]))
    print('XF pin: clrc xf hits (818E) %d, setc xf hits (81A3) %d'%(d.pc_hits(0x818E),d.pc_hits(0x81A3)))
    print('IMR=%04X IFR=%04X, indirect vectors dm[65..69]=%s'%(d.get('IMR'),d.get('IFR'),' '.join('%04X'%d.dm[a] for a in range(0x65,0x6A))))
    mm=[]
    for a in range(0x60):
        r=d.mmr_count(0,a); w=d.mmr_count(1,a)
        if r or w: mm.append('%02X:r%d/w%d'%(a,r,w))
    print('data page 0 (MMR/peripheral/B2) accesses:',' '.join(mm))
    print('external data 1K blocks (r/w):',{'%04X'%(b<<10):(d.ext_count(0,b),d.ext_count(1,b)) for b in range(64) if d.ext_count(0,b) or d.ext_count(1,b)})
    print('last read of reserved 0500-07FF: addr %04X by PC %04X'%(d.rsv(0),d.rsv(1)))
