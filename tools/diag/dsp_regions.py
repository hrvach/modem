"""which DSP code regions (256-word buckets, with the top PCs) run in each half second of a call; machine A (answerer) by default"""
import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
from machine import CPU_HZ
fs=7200; dur=float(sys.argv[1]); which=sys.argv[2] if len(sys.argv)>2 else 'a'
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
m=L.a if which=='a' else L.b; d=m.dsp; t=0
while L.samples() < int(dur*fs):
    d.pc_hits_clear(); L.run(CPU_HZ//2); t+=0.5
    if t<8: continue
    hits=[(d.pc_hits(a),a) for a in range(0x8000,0x10000)]
    tot=sum(h for h,_ in hits); b={}
    for h,a in hits:
        if h: b[a>>8]=b.get(a>>8,0)+h
    top=sorted(b.items(),key=lambda x:-x[1])[:6]
    print("t=%4.1f total=%d idle=%.0f%%  %s"%(t,tot,100*d.idle_cycles()/max(1,d.total_cycles()),' '.join('%02X00:%d'%(k,v) for k,v in top)))
