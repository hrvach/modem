"""where does the host decide to print CONNECT? On the first DTE byte 'C' after T0 print recent 80186 PCs and the stack words (return addresses). usage: connect_pc.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; t0=float(sys.argv[1]); t1=float(sys.argv[2]); seen={}
class Hook(list):
    def __init__(self, m, k): super().__init__(); self.m=m; self.k=k
    def append(self, v):
        if (v&0xFF)==ord('C') and L.samples()/fs>=t0 and seen.get(self.k,0)<1:
            seen[self.k]=1; c=self.m.cpu; ss=c.get('SS'); sp=c.get('SP')
            print('%s t=%.2f recent: %s\n   stack: %s\n   %s'%(self.k,L.samples()/fs,' '.join(hex(x) for x in c.recent(60)),' '.join('%04X'%c.rd16((ss<<4)+sp+2*i) for i in range(16)),c.state()),flush=True)
        super().append(v)
L=Link(); L.gain=0.5
for k,m in (('A',L.a),('B',L.b)):
    import collections
    m.dte_out=Hook(m,k)
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(t1*fs) and len(seen)<2: L.run(CPU_HZ//8)
