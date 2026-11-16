"""host (80186) memory cells and host->DSP command values over call time, both modems. usage: memwatch.py T0 T1 STEP ADDR[,ADDR..]   (addresses hex, DS-relative bytes: byte and word shown)"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
t0=float(sys.argv[1]); t1=float(sys.argv[2]); step=float(sys.argv[3]); addrs=[int(a,16) for a in sys.argv[4].split(',')]
L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); a0=L.a.cpu.cycles; b0=L.b.cpu.cycles; nxt=t0; seen={'A':0,'B':0}
while L.samples() < int(t1*7200):
    L.run(max(1,int(CPU_HZ*step/4))); t=L.samples()/7200
    if t>=nxt:
        out=[]
        for k,m,base in (('A',L.a,a0),('B',L.b,b0)):
            new=[(a&0xFF) for c,a,b in m.cmd_log[seen[k]:]]; seen[k]=len(m.cmd_log)
            out.append('%s '%k+' '.join('[%03X]=%02X/%04X'%(a,m.cpu.rd8(a),m.cpu.rd16(a)) for a in addrs)+' cmds:%s'%(','.join('%02X'%c for c in sorted(set(new))) or '-'))
        print('t=%5.2f  '%t+' | '.join(out),flush=True); nxt+=step
