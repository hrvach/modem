"""host->DSP commands and DSP->host messages of both modems in a call-time window, ~1 ms resolution. usage: cmdwin.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=0.5
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
n={k:[len(m.cmd_log),len(m.msg_log)] for k,m in (('A',L.a),('B',L.b))}
while L.samples()<int(T1*fs):
    L.run(CPU_HZ//1024); t=L.samples()/fs
    for k,m in (('A',L.a),('B',L.b)):
        for c in m.cmd_log[n[k][0]:]:
            if t>=T0: print('%.4f %s CMD %02X %04X'%(t,k,c[1],c[2]))
        for g in m.msg_log[n[k][1]:]:
            if t>=T0 and g[1]&0xFF not in (0x08,): print('%.4f %s MSG %04X %04X %04X %04X'%(t,k,g[1],g[2],g[3],g[4]))
        n[k]=[len(m.cmd_log),len(m.msg_log)]
