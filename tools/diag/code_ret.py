"""log the result-code routine 2F74 return value (AX at 0x3724) and its inputs on every change. usage: code_ret.py T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ, ST_BP
fs=7200; t1=float(sys.argv[1]); L=Link(); L.gain=0.5; ev=[]; last={}
V=[0xB60,0xB8A,0x5E2,0x32B,0x4ED,0xAAC,0x33F,0x331,0x5EA,0x5B0,0x4EE,0xAAD,0x694,0xB33,0xB26]
def mk(nm,m,orig):
    def run(c,s=None):
        r=orig(c,s)
        while r==ST_BP:
            cp=m.cpu; v=(cp.get('AX')&0xFFFF,)+tuple(cp.rd8(a) for a in V)
            if last.get(nm)!=v: ev.append((nm,L.samples()/fs)+v); last[nm]=v
            r=orig(c,s)
        return r
    return run
for nm,m in (('A',L.a),('B',L.b)): m.cpu.bp(0x80000+0x3724); m.run=mk(nm,m,m.run)
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); ev.clear(); last.clear()
while L.samples() < int(t1*fs): L.run(CPU_HZ//8)
print('cols: AX '+' '.join('[%03X]'%a for a in V))
for e in ev: print('%s %6.2f AX=%04X '%e[:3]+' '.join('%02X'%x for x in e[3:]))
