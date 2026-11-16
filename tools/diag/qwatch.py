"""host->DSP message queue of both modems (7.3.14 supervisor: rd [0x29A], wr [0x29C], ring 0x29E..0x2CE, two words per message) against what the DSP actually received (machine cmd_log). usage: qwatch.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
t0=float(sys.argv[1]); t1=float(sys.argv[2])
L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base={'A':L.a.cpu.cycles,'B':L.b.cpu.cycles}; M={'A':L.a,'B':L.b}; last={k:(M[k].cpu.rd16(0x29A),M[k].cpu.rd16(0x29C)) for k in M}; ev={'A':[],'B':[]}
def ring(m,a,b):
    out=[]
    while a!=b:
        out.append(m.cpu.rd16(a)); a+=2
        if a>=0x2CE: a=0x29E
    return out
while L.samples() < int(t1*7200):
    L.run(CPU_HZ//200)
    for k,m in M.items():
        t=(m.cpu.cycles-base[k])/CPU_HZ; rd,wr=m.cpu.rd16(0x29A),m.cpu.rd16(0x29C); orr,owr=last[k]
        if wr!=owr: ev[k].append((t,'ENQ',['%04X'%w for w in ring(m,owr,wr)]))
        if rd!=orr: ev[k].append((t,'SENT',['%04X'%w for w in ring(m,orr,rd)] if False else '%04X->%04X'%(orr,rd)))
        last[k]=(rd,wr)
for k,m in M.items():
    print('=== %s host queue events in %.0f-%.0f s (ENQ = words written to the ring; SENT = read pointer advanced):'%(k,t0,t1))
    for t,w,x in ev[k]:
        if t0<=t<=t1: print('  %6.2f %-4s %s'%(t,w,x))
    print('  DSP received (cmd_log):',[(round((c-base[k])/CPU_HZ,2),'%02X/%04X'%(a&0xFF,b&0xFFFF)) for c,a,b in m.cmd_log if t0<=(c-base[k])/CPU_HZ<=t1])
    print('  final rd/wr: %04X/%04X'%last[k])
