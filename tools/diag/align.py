"""align A's transmitted samples with B's received samples, then see whether B's failing exit-test frame (9F6C) coincides with a discontinuity in A's transmit (x[n]-x[n-42] break). usage: align.py T0 T1"""
import os, sys, math; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=0.5
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
A=L.a; B=L.b; db=B.dsp; db.bp(0x9F6C)
rx=[]; ot=db.serial_tick
def tick(v): rx.append(v); ot(v)
db.serial_tick=tick
frames=[]; orig=_M.Machine._sample; sg=lambda v: v-65536 if v>=32768 else v
def s(self):
    r=orig(self)
    if self is B and db.get('PC')==0x9F6C and T0<=L.samples()/7200<=T1:
        dm=db.dm; frames.append((len(rx),dm[0x334],[sg(v) for v in dm[0x300:0x304]],[sg(v) for v in dm[0x330:0x334]]))
    return r
_M.Machine._sample=s
while L.samples()<int((T1+0.05)*7200): L.run(CPU_HZ//32)
tx=[sg(v) for v in A.tx_all]; rxs=[sg(v) if v>=0 else v for v in rx]
rxs=[v-65536 if v>=32768 else v for v in [x&0xFFFF for x in rx]]
# offset search: rx[i] ~ k*tx[i+off] around the frames
i0=frames[0][0]; i1=frames[-1][0]; seg=rxs[i0:i1]
best=(0,0)
for off in range(-200000,200000,1):
    pass
# restrict: tx index of the same wall time is unknown, so search offsets near len(tx)-len(rx)
base=len(tx)-len(rx)
for off in range(base-3000,base+3000):
    a=tx[i0+off:i1+off]
    if len(a)!=len(seg) or len(a)<500: continue
    sa=sum(x*x for x in a); sb=sum(y*y for y in seg)
    if sa<1 or sb<1: continue
    c=sum(x*y for x,y in zip(a,seg))/math.sqrt(sa*sb)
    if abs(c)>abs(best[0]): best=(c,off)
c,off=best; print('alignment: corr %.4f, tx index = rx index + %d'%(c,off))
def resid(n,P=42): return tx[n]-tx[n-P]
print('frame#  rxIdx  txIdx  ctr  verdict  block a                         max|tx[n]-tx[n-42]| over the 6 samples of the frame')
K=-24150016; LO=0x06670000; HI=LO+0x13320000
for i,(ri,ctr,a,b) in enumerate(frames):
    s7d=(a[0]+a[3]+b[0]+b[3])>>2; s7e=(a[2]-a[1]+b[2]-b[1])>>2; s7c=(a[2]+a[1]+b[2]+b[1])>>2; s7f=(a[3]-a[0]-b[0]+b[3])>>2
    e1=K+2*(s7c*s7c+s7f*s7f); e2=K+2*(s7d*s7d+s7e*s7e); ok=(e1<0)!=(e2<0) and LO<(e2 if e1<0 else e1)<HI
    n=ri+off; r=max(abs(resid(k)) for k in range(n-6,n)) if n-48>=0 and n<len(tx) else -1
    if i<45: print('%4d  %6d %7d  %3d  %-5s  %-34s %d'%(i,ri,n,ctr,'PASS' if ok else 'fail',a,r))
