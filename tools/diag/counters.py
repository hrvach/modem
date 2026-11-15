import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(4*CPU_HZ); m.send("AT\r"); m.run(CPU_HZ); m.dte_text(); m.send("ATA\r"); d=m.dsp
m.run(int(2.4*CPU_HZ))          # inside the first burst (starts ~2.15 s)
def snap(): return list(d.dm[0:0x1000])
a=snap(); m.run(CPU_HZ//10); b=snap()
print("samples per 0.1 s = 720; dm changes ~1 per sample (|delta| in 60..800):")
for i in range(0x1000):
    dv=(b[i]-a[i])&0xFFFF
    if dv>0x8000: dv-=0x10000
    if 100<=abs(dv)<=800: print("  dm[%04X] %04X -> %04X  delta %d"%(i,a[i],b[i],dv))
