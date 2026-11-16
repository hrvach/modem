"""capture the inputs of the ov6 exit test at 9F6C on every frame (current block [0x300..303], previous block [0x330..333], counter [0x334]) from T0, save JSON. usage: test9f6c.py WHO T0 N TAG"""
import os, sys, json; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ, ST_BP
fs=7200; who=sys.argv[1]; t0=float(sys.argv[2]); N=int(sys.argv[3]); tag=sys.argv[4]; L=Link(); L.gain=0.5; rec=[]
tgt=L.a if who=='A' else L.b
def mk(m,orig):
    def run(c,s=None):
        r=orig(c,s)
        while r==ST_BP:
            if L.samples()/fs>=t0 and len(rec)<N:
                d=m.dsp.dm; rec.append((L.samples()/fs,d[0x300:0x304],d[0x330:0x335],d[0x336],d[0x08],d[0x388]))
            r=orig(c,s)
        return r
    return run
tgt.cpu.bp(0x80000+0x9F6C) if False else None
# the DSP is not the 80186: use the DSP breakpoint API through the machine's dsp object
tgt.dsp_bp=True
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
import machine as _M
d=tgt.dsp; d.bp(0xA2AF); orig=_M.Machine._sample
def s(self):
    r=orig(self)
    if self is tgt and d.get('PC')==0xA2AF and L.samples()/fs>=t0 and len(rec)<N:
        dm=d.dm; rec.append((round(L.samples()/fs,4),d.get('ACC')&0xFFFFFFFF,dm[0x3A1],dm[0x3BC],d.pm[d.get('ACC')&0xFFFF],d.pm[(d.get('ACC')&0xFFFF)+1],dm[0x3F6],dm[0x3F7]))
    return r
_M.Machine._sample=s
while len(rec)<N and L.samples()<int((t0+10)*fs): L.run(CPU_HZ//32)
json.dump(rec,open('/tmp/tblr_%s.json'%tag,'w')); print('saved',len(rec))
