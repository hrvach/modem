import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(4*CPU_HZ); m.send("AT\r"); m.run(CPU_HZ); m.dte_text(); m.send("ATA\r"); d=m.dsp; d.set_watch(0x392)
prev=set()
for i in range(26):
    n0=len(m.tx_all); m.run(CPU_HZ//2); x=m.tx_all[n0:]; pk=max(map(abs,x)) if x else 0
    ws=[(a,d.watch_hits(a)) for a in range(0x8000,0x10000) if d.watch_hits(a)]
    print("t+%4.1f peak=%5d gain[392]=%04X  writers so far %s"%((i+1)*0.5,pk,d.dm[0x392],' '.join('%04X:%d'%w for w in ws)))
