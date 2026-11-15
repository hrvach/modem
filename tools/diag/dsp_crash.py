import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(7*CPU_HZ); m.send("AT\r"); m.run(CPU_HZ); m.send("ATQ0V1\r"); m.run(CPU_HZ)
m.send("ATA\r"); d=m.dsp; d.bp(0x81AE)
class Hit(Exception): pass
_run=d.run
def run(c):
    r=_run(c)
    if d.get('PC')==0x81AE and d.recent_pcs(2)==[0x81AE,0x81AE]: raise Hit()
    return r
d.run=run
i=0
try:
    m.run(20*CPU_HZ)
except Hit: pass
print("t",i,"PC=%04X"%d.get('PC'), d.state())
print(["%04X"%p for p in d.recent_pcs(48)])
print("dm60:",["%04X"%d.dm[i] for i in range(0x60,0x6C)])
