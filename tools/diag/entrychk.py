"""did the DSP of modem WHO ever execute its loaded overlay? [0x6F] flag word, hits at the overlay entry and over the overlay ranges. usage: entrychk.py WHO T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
who=sys.argv[1]; t1=float(sys.argv[2]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
tgt=L.a if who=='A' else L.b; base=tgt.cpu.cycles; d=tgt.dsp
while (tgt.cpu.cycles-base) < t1*CPU_HZ: L.run(CPU_HZ//8)
tot=lambda lo,hi: sum(d.pc_hits(p) for p in range(lo,hi))
print('t=%.1f [0x6F]=%04X  [0x39F]=%04X  hits: base 8000-9CFF %d | ov6 range 9D00-AFFF %d | B000-DBFF %d | DC00-EFFF %d | entry 9D00 %d 9D01 %d'%(t1,d.dm[0x6F],d.dm[0x39F],tot(0x8000,0x9D00),tot(0x9D00,0xB000),tot(0xB000,0xDC00),tot(0xDC00,0xF000),d.pc_hits(0x9D00),d.pc_hits(0x9D01)))
print('first words at 9D00:',' '.join('%04X'%d.pm[0x9D00+i] for i in range(6)),'| at DC00:',' '.join('%04X'%d.pm[0xDC00+i] for i in range(4)))
