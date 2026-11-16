"""breakpoints on every store to host byte [0x32B] (connect rate in 100 bit/s) - log time, site, AL and the stack. usage: rate_writers.py T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ, ST_BP
fs=7200; t1=float(sys.argv[1]); L=Link(); L.gain=0.5; ev=[]
sites=[0x265F2,0x26BDC,0x26BFC]
def mk(nm,m,orig):
    def run(c,s=None):
        r=orig(c,s)
        while r==ST_BP:
            cp=m.cpu; ss=cp.get('SS'); sp=cp.get('SP'); pc=cp.phys_pc()-0x80000 if cp.phys_pc()>=0x80000 else cp.phys_pc()
            ev.append((nm,L.samples()/fs,pc,cp.get('AX')&0xFF,cp.rd8(0x5E2),[cp.rd16((ss<<4)+sp+2*i) for i in range(6)]))
            r=orig(c,s)
        return r
    return run
for nm,m in (('A',L.a),('B',L.b)):
    for s in sites: m.cpu.bp(0x80000+s)
    m.run=mk(nm,m,m.run)
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); ev.clear()
while L.samples() < int(t1*fs): L.run(CPU_HZ//8)
for nm,t,pc,al,cur,stk in ev:
    if t>=12: print('%s %.2f site %05X AL=%02X [5E2]=%02X stack %s'%(nm,t,pc,al,cur,' '.join('%04X'%x for x in stk)))
