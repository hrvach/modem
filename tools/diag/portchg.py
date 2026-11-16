"""time-stamped first occurrence of every distinct (port,value) host OUT write, and every DSP port write value change (ports other than the data/flag ports), on both modems.
usage: portchg.py T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
import machine as _M
fs=7200; t1=float(sys.argv[1])
LOG=[]; cur={'t':0.0}
_iow=_M.Machine.iowr
names={}
def _w(self,p,w,v):
    k=(id(self),p,v & 0xFFFF)
    if k not in names:
        names[k]=1; LOG.append((cur['t'],'A' if self is L.a else 'B','host OUT %04X <- %04X'%(p,v&0xFFFF)))
    return _iow(self,p,w,v)
_M.Machine.iowr=_w
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
for m in (L.a,L.b): m.dsp_log.clear()
seen={}
while L.samples() < int(t1*fs):
    L.run(CPU_HZ//32); cur['t']=L.samples()/fs
    for nm,m in (('A',L.a),('B',L.b)):
        for c,q,v in m.dsp_log:
            if q in (0x56,0x57,0x58,0x59,0x5A,0x5B,0x5C,0x5D,0x5E,0x5F,0x60): continue
            if seen.get((nm,q))!=v: seen[(nm,q)]=v; LOG.append((cur['t'],nm,'DSP  OUT %04X <- %04X'%(q,v)))
        m.dsp_log.clear()
for t,nm,s in LOG: print('%7.2f %s %s'%(t,nm,s))
