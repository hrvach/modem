"""do the two modems hear each other across mode (codec rate) changes? per window: rates, tx/rx rms and the best lagged correlation between one DSP's transmitted samples and the other's received samples (equal-rate windows only). usage: hear.py T0 T1 [WIN_S]"""
import os, sys, math; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
t0=float(sys.argv[1]); t1=float(sys.argv[2]); W=float(sys.argv[3]) if len(sys.argv)>3 else 0.5
L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base={'A':L.a.cpu.cycles,'B':L.b.cpu.cycles}; tx={'A':[],'B':[]}; rx={'A':[],'B':[]}
def hook(k,m):
    d=m.dsp; ot=d.serial_tick; otx=m.take_tx
    def tick(v):
        rx[k].append(((m.cpu.cycles-base[k])/CPU_HZ,m.rate,v)); ot(v)
    def take():
        s=otx(); t=(m.cpu.cycles-base[k])/CPU_HZ
        for v in s: tx[k].append((t,m.rate,v))
        return s
    d.serial_tick=tick; m.take_tx=take
hook('A',L.a); hook('B',L.b)
while L.samples() < int(t1*7200): L.run(CPU_HZ//16)
def win(lst,a,b): return [x for x in lst if a<=x[0]<b]
def rms(v): return math.sqrt(sum(x*x for x in v)/len(v)) if v else 0.0
def best(xs,ys):
    n=min(len(xs),len(ys)); 
    if n<200: return None
    bc,bl=0,0
    for lag in range(0,120,1):
        a=xs[:n-lag]; b=ys[lag:n]
        sa=sum(x*x for x in a); sb=sum(y*y for y in b)
        if sa<1 or sb<1: continue
        c=sum(x*y for x,y in zip(a,b))/math.sqrt(sa*sb)
        if abs(c)>abs(bc): bc,bl=c,lag
    return bc,bl
print('window   rates A/B   A->B: tx rms  rx rms  corr@lag      B->A: tx rms  rx rms  corr@lag')
t=t0
while t<t1:
    row=[]
    for s,r in (('A','B'),('B','A')):
        ts=win(tx[s],t,t+W); rr=win(rx[r],t,t+W)
        rs=sorted({x[1] for x in ts}); rr_=sorted({x[1] for x in rr})
        x=[v[2] for v in ts]; y=[v[2] for v in rr]
        c=best(x,y) if len(rs)==1 and rs==rr_ else None
        row.append('%7.0f %7.0f  %s'%(rms(x),rms(y),('%+.3f@%d'%c if c else ('n/a (rates %s vs %s)'%(rs,rr_) if x and y else '-'))))
    ra=sorted({x[1] for x in win(rx['A'],t,t+W)}); rb=sorted({x[1] for x in win(rx['B'],t,t+W)})
    print('%5.1f-%-5.1f %s/%s   %s    |  %s'%(t,t+W,ra,rb,row[0],row[1]))
    t+=W
