"""dominant tones of each modem's DAC output over time with the TRUE sample rate of each chunk (machine.rate at take_tx), next to what the same tone would measure if the samples were analysed as 7200 Hz. usage: tones.py T1 [WINDOW_S]"""
import os, sys, math; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
T1=float(sys.argv[1]); WS=float(sys.argv[2]) if len(sys.argv)>2 else 0.25; L=Link(); L.gain=0.5
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda m=L.a:(m.cpu.cycles-base)/CPU_HZ
sg=lambda v: v-65536 if v>=32768 else v
chunks={'A':[],'B':[]}                      # (rate, [samples])
o_t=_M.Machine.take_tx
def tx(self):
    out=o_t(self)
    if out and T(self)>0: chunks['A' if self is L.a else 'B'].append((self.rate,T(self),[sg(v&0xFFFF) for v in out]))
    return out
_M.Machine.take_tx=tx
while T()<T1: L.run(CPU_HZ//64)
def peaks(x,fs,n=3):
    N=len(x)
    if N<200: return []
    e=sum(v*v for v in x)/N
    if e<1e4: return []
    w=[0.5-0.5*math.cos(2*math.pi*i/(N-1)) for i in range(N)]
    xs=[a*b for a,b in zip(x,w)]
    fmax=min(fs/2,4800); step=15.0
    freqs=[step*i for i in range(1,int(fmax/step))]
    pw=[]
    for f in freqs:
        k=2*math.cos(2*math.pi*f/fs); s1=s2=0.0
        for v in xs: s0=v+k*s1-s2; s2=s1; s1=s0
        pw.append(s1*s1+s2*s2-k*s1*s2)
    res=[]
    for i in range(1,len(pw)-1):
        if pw[i]>pw[i-1] and pw[i]>=pw[i+1] and pw[i]>0.02*max(pw):
            d=0.5*(pw[i-1]-pw[i+1])/(pw[i-1]-2*pw[i]+pw[i+1]) if (pw[i-1]-2*pw[i]+pw[i+1])!=0 else 0
            res.append((pw[i],freqs[i]+d*step))
    res.sort(reverse=True); return [f for _,f in res[:n]]
print('window    modem rate   true-Hz peaks            (same tones read at 7200 Hz)')
for nm in 'AB':
    cur=None
    for rate,t,s in chunks[nm]:
        pass
    # regroup by time windows
    allc=[(rate,t,s) for rate,t,s in chunks[nm]]
    i=0; t0=None
    win=[];
    buf=[];  rate0=None; tstart=None
    for rate,t,s in allc:
        if rate0 is None or rate!=rate0 or (t-tstart)>=WS:
            if buf and rate0: 
                x=[v for part in buf for v in part]; pk=peaks(x,rate0)
                if pk: print('%6.2f s  %s  %5d  %-26s (%s)'%(tstart,nm,rate0,' '.join('%.0f'%f for f in pk),' '.join('%.0f'%(f*7200/rate0) for f in pk)))
            buf=[]; rate0=rate; tstart=t
        buf.append(s)
