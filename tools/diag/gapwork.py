"""what is a DSP doing while it stops writing the DAC? snapshot PC hit counts of modem A's DSP at T0 and T1 (around the 17.607 s gap) and print the hot addresses of the difference. usage: gapwork.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda: (L.a.cpu.cycles-base)/CPU_HZ
while T()<T0: L.run(CPU_HZ//200)
WHO=os.environ.get('WHO','A'); d=(L.a if WHO=='A' else L.b).dsp; s0=[d.pc_hits(i) for i in range(0x10000)]; h0=d.dxr_head(); c0=d.total_cycles()
while T()<T1: L.run(CPU_HZ//2000)
s1=[d.pc_hits(i) for i in range(0x10000)]; h1=d.dxr_head(); c1=d.total_cycles()
diff=sorted(((s1[i]-s0[i],i) for i in range(0x10000) if s1[i]-s0[i]>0),reverse=True)
print('window %.3f-%.3f s: %s DSP cycles %d, DXR writes %d (expected ~%d)'%(T0,T1,WHO,c1-c0,h1-h0,int((T1-T0)*10267)))
print('instructions executed:',sum(v for v,i in diff))
print('hot addresses:',' '.join('%04X:%d'%(i,v) for v,i in diff[:40]))
