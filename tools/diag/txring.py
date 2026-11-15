import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(4*CPU_HZ); m.send("AT\r"); m.run(CPU_HZ); m.dte_text(); m.send("ATA\r"); d=m.dsp
for i in range(14):
    m.run(CPU_HZ//2)
    print("t+%.1f AR7=%04X dm390=%04X dm391=%04X dm6B=%04X ring[0x390..]=%s"%(i/2+.5,d.get('AR7'),d.dm[0x390],d.dm[0x391],d.dm[0x6B],' '.join('%04X'%d.dm[a] for a in range(d.dm[0x390]&0xFFFF,(d.dm[0x390]&0xFFFF)+6)) if d.dm[0x390]<0xF000 else ''))
