import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(7*CPU_HZ); d=m.dsp
print('boot dm BF7/BF8: %04X %04X'%(d.dm[0xBF7],d.dm[0xBF8]))
m.send("AT\r"); m.run(CPU_HZ); print('after AT %04X %04X'%(d.dm[0xBF7],d.dm[0xBF8]))
d.pc_hits_clear(); m.send("ATA\r")
for i in range(12):
    m.run(CPU_HZ//2); print('t+%.1f BF7/8 %04X %04X PRD %04X PC %04X hits 8003=%d 8059=%d 8027=%d 8001=%d'%((i/2+.5,d.dm[0xBF7],d.dm[0xBF8],d.get('PRD'),d.get('PC'))+tuple(d.pc_hits(a) for a in (0x8003,0x8059,0x8027,0x8001))))
