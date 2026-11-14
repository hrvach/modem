import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys'); sys.path.insert(0,'/home/hrvoje/Programming/USR/dsp')
from machine import *
m=Machine(nvram_mode=None); m.logging=False; m.run(900_000_000)
m.send("AT\r"); m.run(150_000_000); m.send("ATA\r"); m.run(150_000_000)
# now DSP is in ANS: count over a window
h0=m.dsp.dxr_head(); t0=m.hb_count; c0=m.cpu.cycles
m.run(100_000_000)
print("ticks",m.hb_count-t0,"dxr writes",m.dsp.dxr_head()-h0,"80186 cyc",m.cpu.cycles-c0)
r=m.dsp.dxr_ring(); h=m.dsp.dxr_head(); print([r[i&0xFFFF] for i in range(h-24,h)])

import math,json
h=m.dsp.dxr_head(); n=8192
a=[(r[i&0xFFFF]^0x8000)-0x8000 for i in range(h-n,h)]
json.dump(a,open('./ring.json','w'))
def peak(x):
    N=len(x); mu=sum(x)/N; x=[v-mu for v in x]; w=[0.5-0.5*math.cos(2*math.pi*i/N) for i in range(N)]
    best=(0,0); tot=0
    for k in range(1,200):
        f=k/400.0; c=sum(x[i]*w[i]*math.cos(2*math.pi*f*i) for i in range(0,N,2)); s_=sum(x[i]*w[i]*math.sin(2*math.pi*f*i) for i in range(0,N,2))
        mg=c*c+s_*s_; tot+=mg
        if mg>best[0]: best=(mg,f)
    return best[1], best[0]/(tot/199), math.sqrt(sum(v*v for v in x)/N)
for P in (1,2,3,4):
    for ph in range(P):
        f,r_,sd=peak(a[ph::P][:2048]); print("P",P,"ph",ph,"rms %.0f"%sd,"peak f/fs %.4f"%f,"peak/mean %.1f"%r_)
