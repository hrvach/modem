"""log every event code (AX) that reaches the host result/event dispatcher at flash 0x328C, per modem with call time; shows what precedes CONNECT (0x9D). usage: events_bp.py T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ, ST_BP
fs=7200; t1=float(sys.argv[1]); L=Link(); L.gain=0.5; ev=[]
def mk(nm,m,orig):
    def run(c,s=None):
        r=orig(c,s)
        while r==ST_BP:
            cp=m.cpu; ss=cp.get('SS'); sp=cp.get('SP')
            ev.append((nm,L.samples()/fs,cp.get('AX'),cp.rd16((ss<<4)+sp)))
            r=orig(c,s)
        return r
    return run
for nm,m in (('A',L.a),('B',L.b)):
    m.cpu.bp(0x80000+0x328C); m.run=mk(nm,m,m.run)
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); ev.clear()
while L.samples() < int(t1*fs): L.run(CPU_HZ//8)
last={}
for nm,t,ax,ret in ev:
    if t>=12 and ax not in (0,0xFFFF): print('%s %.2f event %04X (ret %04X)'%(nm,t,ax,ret))
