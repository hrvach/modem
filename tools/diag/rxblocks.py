"""log host reads of DSP->host bank words (ports 0x40-0x56) and DSP writes to ports 0x58-0x5D on both modems after CONNECT.
usage: rxblocks.py SECONDS"""
import os, sys, collections; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
import machine as _M
fs=7200; dur=float(sys.argv[1])
RD={}; WR={}
_ior=_M.Machine.iord; _iow=_M.Machine.iowr
def _r(self,p,w):
    v=_ior(self,p,w)
    if 0x40<=p<=0x5E and self.dsp is not None and getattr(self,'trk',0): RD.setdefault(id(self),[]).append((round(self.cpu.cycles/CPU_HZ,3),p,v))
    return v
def _w(self,p,w,v):
    if 0x40<=p<=0x5E and self.dsp is not None and getattr(self,'trk',0): WR.setdefault(id(self),[]).append((round(self.cpu.cycles/CPU_HZ,3),p,v&0xFF))
    return _iow(self,p,w,v)
_M.Machine.iord=_r; _M.Machine.iowr=_w
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
tc=None
while L.samples() < int(dur*fs):
    L.run(CPU_HZ//2)
    if tc is None and b'CONNECT' in L.txt['b']:
        tc=L.samples()/fs; print("B CONNECT at",tc,flush=True)
        for m in (L.a,L.b): m.trk=1; m.dsp_log.clear(); m.wr_pcs.clear()
        L.b.rxmark=len(L.txt['b'])
for nm,m in (('A',L.a),('B',L.b)):
    r=RD.get(id(m),[]); w=WR.get(id(m),[])
    print(nm,'host reads',len(r),'writes',len(w))
    print(nm,'first reads',r[:48])
    print(nm,'first writes',w[:48])
    d=[(q,v) for c,q,v in m.dsp_log if 0x58<=q<=0x5D]
    print(nm,'DSP bank writes',len(d),d[:40])
    print(nm,'flags',hex(m.flags56),hex(m.flagsD))
print('B rx after CONNECT',L.txt['b'][L.b.rxmark:][:80].hex(' '))
for nm,m in (('A',L.a),('B',L.b)):
    print(nm,'DSP bank-write PCs',sorted(((q,hex(pc),n) for (q,pc),n in m.wr_pcs.items() if 0x58<=q<=0x5D)))
