"""overlay loads, host commands and rate changes of both modems in a two-modem call. usage: ovlcmp.py T1 [T0]"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
t1=float(sys.argv[1]); t0=float(sys.argv[2]) if len(sys.argv)>2 else 0; L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); b0=L.b.cpu.cycles; a0=L.a.cpu.cycles
while L.samples() < int(t1*7200): L.run(CPU_HZ//8)
for nm,m,base in (('A',L.a,a0),('B',L.b,b0)):
    print(nm,'overlay loads (t, addr, words):',[(round((c-base)/CPU_HZ,2),hex(a),n//2) for c,a,n in m.ovl_loads if (c-base)/CPU_HZ>=0])
    print(nm,'rate log (t,rate):',[(round(t-base/CPU_HZ,2),r) for t,r in m.rate_log if t-base/CPU_HZ>0])
    cl=[(round((c-base)/CPU_HZ,2),'%02X/%04X'%(a&0xFF,b&0xFFFF)) for c,a,b in m.cmd_log if (c-base)/CPU_HZ>=t0 and a&0xFF not in (0x17,)]
    print(nm,'host cmds (excluding periodic 17):',cl[:40])
    print(nm,'DSP msg types first seen:',sorted({(round((x[5]-base)/CPU_HZ,1),'%02X'%(x[3]&0xFF)) for x in m.msg_log if (x[5]-base)/CPU_HZ>=t0 and (x[3]&0xFF) not in (0,0x08,0x16,0x83,0x06,0x14,0x5D,0x17)})[:30])
