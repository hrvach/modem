"""two-modem call: host commands and DSP messages of both modems inside a time window (call time, s). usage: cmdwin2.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
t0=float(sys.argv[1]); t1=float(sys.argv[2]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); b0=L.b.cpu.cycles; a0=L.a.cpu.cycles
while L.samples() < int(t1*7200): L.run(CPU_HZ//8)
for nm,m,base in (('A',L.a,a0),('B',L.b,b0)):
    print(nm,'host cmds:',[(round((c-base)/CPU_HZ,2),'%02X/%04X'%(a&0xFF,b&0xFFFF)) for c,a,b in m.cmd_log if t0<=(c-base)/CPU_HZ<=t1])
    print(nm,'DSP msgs :',[(round((x[5]-base)/CPU_HZ,2),'%02X/%04X'%(x[3]&0xFF,x[4])) for x in m.msg_log if t0<=(x[5]-base)/CPU_HZ<=t1 and (x[3]&0xFF) not in (0,)])
