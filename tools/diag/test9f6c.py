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
d=tgt.dsp; d.bp(0x9F6C); orig=_M.Machine._sample
def s(self):
    r=orig(self)
    if self is tgt and d.get('PC')==0x9F6C and L.samples()/fs>=t0 and len(rec)<N:
        dm=d.dm; rec.append((round(L.samples()/fs,3),list(dm[0x300:0x304]),list(dm[0x330:0x335]),dm[0x336],d.get('ST1'),d.get('ST0'),self.hb_count))
    return r
_M.Machine._sample=s
tmap=[]
while len(rec)<N and L.samples()<int((t0+10)*fs):
    L.run(CPU_HZ//32); tmap.append((L.samples()/fs,len(L.audio['a']),len(L.audio['b'])))
# TXS: where is A's S burst in A's own transmit audio (lag-6 corr 0.45-0.8) mapped to call time
xa=L.audio['a']
import bisect
def t_of(i):
    k=bisect.bisect_left([x[1] for x in tmap],i); k=min(k,len(tmap)-1); return tmap[k][0]
segs=[];run=None
for i in range(0,len(xa)-60,6):
    w=xa[i:i+54]; num=sum(w[k]*w[k+6] for k in range(48)); den=sum(v*v for v in w[:48]) or 1
    ok=den/48>1e5 and 0.45<num/den<0.8
    if ok and run is None: run=i
    if not ok and run is not None:
        if i-run>150: segs.append((round(t_of(run),4),round(t_of(i),4)))
        run=None
print('TXS A transmit S-like segments (call time start,end):',segs)
# RXE: energy (rms) of A's transmit and of B's actual input samples per 2 ms window around 16.60-16.70
import math
rxl=L.b.rx_log; ticks=[(x[0],x[2]) for x in tmap]
def idx_at(t,which):
    k=bisect.bisect_left([x[0] for x in tmap],t); k=min(k,len(tmap)-1); return tmap[k][which]
out=[]
for t in [16.60+0.002*i for i in range(50)]:
    ia0,ia1=idx_at(t,1),idx_at(t+0.002,1); ib0,ib1=idx_at(t,2),idx_at(t+0.002,2)
    wa=xa[ia0:ia1]; wb=rxl[ib0:ib1]
    ra=math.sqrt(sum(v*v for v in wa)/max(len(wa),1)); wb=[v-65536 if v>=32768 else v for v in wb]; rb=math.sqrt(sum(v*v for v in wb)/max(len(wb),1))
    out.append('%.3f:%d/%d'%(t,ra,rb))
print('RXE t:A_tx_rms/B_rx_input_rms',' '.join(out))
json.dump(rec,open('/tmp/t9f6c_%s.json'%tag,'w')); print('saved',len(rec))
