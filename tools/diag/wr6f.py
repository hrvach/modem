"""who writes the DSP status word [0x6F]? watch data address 0x6F on both modems; print the writer PCs (post-fetch PC of the storing instruction) with each value change.
usage: wr6f.py SECONDS"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; dur=float(sys.argv[1])
L=Link(); L.gain=float(os.environ.get("GAIN","1.0")); L.echo=float(os.environ.get("ECHO","0.0")); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
for m in (L.a,L.b): m.dsp.set_watch(0x6F)
prev={'A':0,'B':0}; seen={'A':{},'B':{}}
while L.samples() < int(dur*fs):
    L.run(CPU_HZ//16)
    t=L.samples()/fs
    for nm,m in (('A',L.a),('B',L.b)):
        d=m.dsp; v=d.dm[0x6F]
        new=[]
        for pc in range(0x8000,0x10000):
            h=d.watch_hits(pc)
            if h and seen[nm].get(pc,0)!=h: new.append((pc,h-seen[nm].get(pc,0))); seen[nm][pc]=h
        if v!=prev[nm] or any(h>0 for p,h in new):
            if v!=prev[nm]: print('%6.2f %s 6F %04X -> %04X writers %s'%(t,nm,prev[nm],v,' '.join('%04X x%d'%(p,h) for p,h in new[:6])),flush=True)
            prev[nm]=v
