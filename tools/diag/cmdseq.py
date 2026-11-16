"""DSP command sequence (host -> DSP commands) per modem up to B's CONNECT + 1 s, with times.
usage: cmdseq.py SECONDS"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; dur=float(sys.argv[1])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}
for m in (L.a,L.b): m.cmd_log.clear(); m.msg_log.clear()
t0=L.samples(); base=L.b.cpu.cycles; L.start_call("1")
while L.samples() < int(dur*fs):
    L.run(CPU_HZ//4)
    if b'CONNECT' in L.txt['b'] and b'CONNECT' in L.txt['a']: L.run(CPU_HZ); break
for nm,m in (('A',L.a),('B',L.b)):
    print(nm,'commands (t s, cmd, arg):')
    print('  ',' '.join('%.1f:%02X/%04X'%((c-base)/CPU_HZ,cmd,arg) for c,cmd,arg in m.cmd_log if cmd<0x80))
    first={}
    for e in m.msg_log:
        k=(e[3],e[4]) if len(e)>4 else e[1:]
        if k not in first: first[k]=[(e[5]-base)/CPU_HZ if len(e)>5 else e[0]/7200.0,0]
        first[k][1]+=1
    print(nm,'msgs (type,payload): first call-time s, count:')
    print('  ',' '.join('%02X/%04X@%.1f x%d'%(k[0],k[1],v[0],v[1]) for k,v in sorted(first.items(),key=lambda kv:kv[1][0])))
print('events',[(round(t,1),s) for t,s in L.events][:12])
