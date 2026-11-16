"""inventory of hardware accesses during a two-modem call: host I/O ports (reads/writes), DSP port reads/writes by PC, and hits of the [0x356] writers on B.
usage: ioinv.py SECONDS"""
import os, sys, collections; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ, ST_BP
fs=7200; dur=float(sys.argv[1])
import machine as _M
INV={}
_ior=_M.Machine.iord; _iow=_M.Machine.iowr; _mmr=_M.Machine.mmrd; _mmw=_M.Machine.mmwr
def _r(self,p,w): INV.setdefault(id(self),{'r':collections.Counter(),'w':collections.Counter(),'mr':collections.Counter(),'mw':collections.Counter()})['r'][p]+=1; return _ior(self,p,w)
def _w(self,p,w,v): INV.setdefault(id(self),{'r':collections.Counter(),'w':collections.Counter(),'mr':collections.Counter(),'mw':collections.Counter()})['w'][p]+=1; return _iow(self,p,w,v)
_M.Machine.iord=_r; _M.Machine.iowr=_w
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}
for m in (L.a,L.b): m.dsp_log.clear(); m.wr_pcs.clear(); m.rd_pcs.clear(); INV[id(m)]['r'].clear(); INV[id(m)]['w'].clear()
sites=[0x52d4,0x5302,0x4d4c,0x4d54,0x47ba,0x4892,0x113af,0x11876,0x11d1f,0x11e51,0xcb22,0xc91f,0x10c05]
hits=collections.defaultdict(list)
for nm,m in (('A',L.a),('B',L.b)):
    for s in sites: m.cpu.bp(0x80000+s)
    orig=m.run
    def mk(nm,m,orig):
        def run(c,s=None):
            r=orig(c,s)
            while r==ST_BP:
                hits[(nm,m.cpu.phys_pc()-0x80000)].append((round(L.samples()/fs,1),m.cpu.rd16(0x356)))
                r=orig(c,s)
            return r
        return run
    m.run=mk(nm,m,orig)
L.start_call("1")
while L.samples() < int(dur*fs): L.run(10_000_000)
for nm in 'AB':
    m=L.a if nm=='A' else L.b
    print(nm,'host IN ports :',{hex(k):v for k,v in sorted(INV[id(m)]['r'].items())})
    print(nm,'host OUT ports:',{hex(k):v for k,v in sorted(INV[id(m)]['w'].items())})
    print(nm,'DSP writes by port:',{hex(k):n for k,n in sorted(collections.Counter(q for c,q,v in m.dsp_log).items())})
    print(nm,'DSP reads by port :',{hex(k):n for k,n in sorted(collections.Counter(q for (q,pc),n in m.rd_pcs.items() for _ in range(1)).items())})
for k,v in sorted(hits.items()): print('hit',k[0],'%05X'%k[1],len(v),v[:3])
print('[0x356] A=%04X B=%04X'%(L.a.cpu.rd16(0x356),L.b.cpu.rd16(0x356)))
