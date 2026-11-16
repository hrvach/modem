"""exact structure of A's transmitted S / S-bar around the exit test: runs where x[n]==x[n-42] (S periodic), x[n]==-x[n-42] (inverted = S-bar), and what follows; lengths in samples and symbols (3 samples/symbol). usage: txspan.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
T1=float(sys.argv[2]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); A=L.a
while L.samples()<int(T1*7200): L.run(CPU_HZ//32)
sg=lambda v: v-65536 if v>=32768 else v
x=[sg(v) for v in A.tx_all]; P=42; N=len(x)
lo=int(os.environ.get('LO','219500')); hi=min(N,int(os.environ.get('HI','221500')))
def runs(pred,minlen):
    out=[];st=None
    for n in range(lo+P,hi):
        ok=pred(n)
        if ok and st is None: st=n
        if (not ok) and st is not None:
            if n-st>=minlen: out.append((st,n-1))
            st=None
    if st is not None and hi-st>=minlen: out.append((st,hi-1))
    return out
same=runs(lambda n: abs(x[n]-x[n-P])<=3,30)
inv=runs(lambda n: abs(x[n]+x[n-P])<=3,10)
amp=lambda a,b: max(abs(v) for v in x[a:b+1])
print('A tx samples',lo,'..',hi)
for a,b in same: print('periodic S-like run  n %d..%d  length %d samples = %.1f symbols  (amplitude %d)'%(a-P,b,b-a+1+P,(b-a+1+P)/3.0,amp(a,b)))
for a,b in inv: print('inverted (S-bar-like) run n %d..%d  length %d samples = %.1f symbols'%(a-P,b,b-a+1+P,(b-a+1+P)/3.0))
# amplitude envelope per 21 samples
env=[(n,max(abs(v) for v in x[n:n+21])) for n in range(lo,hi,21)]
print('envelope (n:max|x| per 21 samples):',' '.join('%d:%d'%e for e in env[:70]))
