import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(4*CPU_HZ); m.send("AT\r"); m.run(CPU_HZ); m.dte_text(); m.send("ATA\r"); d=m.dsp
W=[0x8149,0x8167,0x93F2,0x9482,0xB6CE,0xB9F5,0xBA16,0xC146]
for i in range(26):
    d.pc_hits_clear(); n0=len(m.tx_all); m.run(CPU_HZ//2); x=m.tx_all[n0:]
    pk=max(map(abs,x)) if x else 0
    print("t+%4.1f peak=%5d writers %s"%((i+1)*0.5,pk,' '.join('%04X:%d'%(a,d.pc_hits(a)) for a in W if d.pc_hits(a))))
