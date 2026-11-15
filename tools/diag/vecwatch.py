import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(4*CPU_HZ); m.send("AT\r"); m.run(CPU_HZ); m.dte_text(); m.send("ATA\r"); d=m.dsp
seen={}
for i in range(int(float(sys.argv[1])*10)):
    m.run(CPU_HZ//10)
    v=tuple(d.dm[0x60:0x6C])
    if v!=seen.get('v'):
        seen['v']=v; print("t+%.1f dm60..6B="%(i/10),' '.join('%04X'%x for x in v),'IMR=%04X'%d.get('IMR'))
