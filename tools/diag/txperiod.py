"""is the transmitted S burst of modem A perfectly periodic (42 samples at 10267 Hz)? where does x[n]-x[n-42] stop being ~0? usage: txperiod.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
stamp=[]; ta=L.a; ot=ta.take_tx
def take():
    s=ot(); t=(ta.cpu.cycles-L.a.cpu.cycles)  # placeholder
    stamp.append((ta.cpu.cycles,len(ta.tx_all))); return s
ta.take_tx=take; base=ta.cpu.cycles
while L.samples() < int((T1+0.05)*7200): L.run(CPU_HZ//32)
x=[v-65536 if v>=32768 else v for v in ta.tx_all]
# time of sample index n via the stamps
import bisect
cyc=[c for c,n in stamp]; idx=[n for c,n in stamp]
def t_of(n):
    i=bisect.bisect_left(idx,n); i=min(i,len(idx)-1); return (cyc[i]-base)/CPU_HZ
lo=next(n for n in range(len(x)) if t_of(n)>=T0); hi=next((n for n in range(lo,len(x)) if t_of(n)>=T1),len(x))
print('A tx samples %d..%d (t %.3f..%.3f), looking at x[n]-x[n-42]'%(lo,hi,t_of(lo),t_of(hi-1)))
P=42; bad=[]; run=0
for n in range(lo+P,hi):
    d=x[n]-x[n-P]
    if abs(d)>60: bad.append((n,round(t_of(n),4),d))
print('samples with |x[n]-x[n-42]| > 60:',len(bad))
# group into bursts of consecutive indices
groups=[]
for n,t,d in bad:
    if groups and n-groups[-1][-1][0]<=3: groups[-1].append((n,t,d))
    else: groups.append([(n,t,d)])
for g in groups[:25]: print('  n %d..%d  t %.4f..%.4f  count %d  max|d| %d'%(g[0][0],g[-1][0],g[0][1],g[-1][1],len(g),max(abs(v[2]) for v in g)))
print('peak amplitude in window:',max(abs(v) for v in x[lo:hi]))
