"""break on the host result-code printer (flash 0x9F59) and record regs + stack (return addresses) with call time. usage: resultcode_bp.py T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ, ST_BP
fs=7200; t1=float(sys.argv[1]); L=Link(); L.gain=0.5; hits=[]
def mk(nm,m,orig):
    def run(c,s=None):
        r=orig(c,s)
        while r==ST_BP:
            cp=m.cpu; ss=cp.get('SS'); sp=cp.get('SP')
            hits.append((nm,L.samples()/fs,cp.state(),[cp.rd16((ss<<4)+sp+2*i) for i in range(10)]))
            r=orig(c,s)
        return r
    return run
for nm,m in (('A',L.a),('B',L.b)):
    m.cpu.bp(0x80000+0x9F59); m.run=mk(nm,m,m.run)
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); hits.clear()
while L.samples() < int(t1*fs): L.run(CPU_HZ//8)
for nm,t,st,stk in hits: print('%s t=%.2f stack(ret,...) %s\n    %s'%(nm,t,' '.join('%04X'%x for x in stk),st))
