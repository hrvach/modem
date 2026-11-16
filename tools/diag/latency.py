"""exact latency A tx -> B DRR input: cross-correlate A's transmitted samples with the samples delivered to B's DRR (RX_TRACE), per tick; and show B's input envelope around A's S burst. usage: latency.py T0 T1"""
import os, sys, math; os.environ['RX_TRACE']='1'; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
tick0=len(L.b.rx_trace); marks=[]
while L.samples()<int((T1+0.1)*fs):
    L.run(CPU_HZ//64); marks.append((L.samples()/fs,len(L.audio['a']),len(L.b.rx_trace)-tick0))
xa=L.audio['a']; xb=L.b.rx_trace[tick0:]
def at(t,col):
    for m in marks:
        if m[0]>=t: return m[col]
    return marks[-1][col]
i0,i1=at(T0,1),at(T1,1); print('A tx samples',i0,i1,'B rx ticks',at(T0,2),at(T1,2))
seg=xa[i0:i1]; best=None
for d in range(0,600):
    num=sum(seg[k]*xb[i0+k+d] for k in range(len(seg)) if i0+k+d<len(xb)); 
    den=math.sqrt(sum(v*v for v in seg)*sum(xb[i0+k+d]**2 for k in range(len(seg)) if i0+k+d<len(xb)) or 1)
    c=num/den
    if best is None or c>best[0]: best=(c,d)
print('best lag (samples) A_tx -> B_rx: %d  corr %.3f'%(best[1],best[0]))
# envelope per 1 ms in sample index space
w=10; env_a=[];env_b=[]
for k in range(i0,i1,w):
    ra=math.sqrt(sum(v*v for v in xa[k:k+w])/w); rb=math.sqrt(sum(v*v for v in xb[k+best[1]:k+best[1]+w])/w)
    env_a.append(int(ra)); env_b.append(int(rb))
print('A tx rms per 10 samples (aligned):',env_a[:80]); print('B rx rms per 10 samples (lag-corrected):',env_b[:80])
