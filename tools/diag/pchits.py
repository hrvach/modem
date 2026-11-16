"""PC hit counts of modem WHO between T0 and T1 for a list of PCs. usage: pchits.py WHO T0 T1 PC[,PC...]"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
who=sys.argv[1]; t0=float(sys.argv[2]); t1=float(sys.argv[3]); pcs=[int(a,16) for a in sys.argv[4].split(',')]
L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
tgt=L.a if who=='A' else L.b; base=tgt.cpu.cycles; d=tgt.dsp
while (tgt.cpu.cycles-base) < t0*CPU_HZ: L.run(CPU_HZ//16)
h0={p:d.pc_hits(p) for p in pcs}; n0=d.total_cycles()
while (tgt.cpu.cycles-base) < t1*CPU_HZ: L.run(CPU_HZ//16)
print('window %.2f-%.2f s (%d DSP cycles), rate %d: '%(t0,t1,d.total_cycles()-n0,tgt.rate)+'  '.join('%04X:%d'%(p,d.pc_hits(p)-h0[p]) for p in pcs))
