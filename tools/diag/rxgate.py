"""is the receive decision/equalizer stage running? PC hit deltas of the gate at A2C4..A2C7 (bit 3 of [0x6F]) and [0x6F] value on both DSPs over a window. usage: rxgate.py T0 T1"""
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
PCS=(0xA2A7,0xA2C4,0xA2C5,0xA2C6,0xA2C7,0x9E6B,0x9F6C,0x8270,0x8300)
while T()<T0: L.run(CPU_HZ//32)
s0={nm:{p:m.dsp.pc_hits(p) for p in PCS} for nm,m in (('A',L.a),('B',L.b))}
v0={nm:m.dsp.dm[0x6F] for nm,m in (('A',L.a),('B',L.b))}
while T()<T1: L.run(CPU_HZ//32)
for nm,m in (('A',L.a),('B',L.b)):
    print('DSP %s [6F] %04X -> %04X ; hits %.1f-%.1f s:'%(nm,v0[nm],m.dsp.dm[0x6F],T0,T1),' '.join('%04X:%d'%(p,m.dsp.pc_hits(p)-s0[nm][p]) for p in PCS))
