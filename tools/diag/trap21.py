import sys; sys.path.insert(0,'.')
from machine import *
m=Machine(nvram_mode=None); cpu=m.cpu; m.logging=False
m.run(900_000_000); m.dte_text()
for c in ("AT\r","ATQ0V1\r"): m.send(c); m.run(150_000_000); m.dte_text()
m.send("ATA\r")
cpu.bp(0x8F684); cpu.bp(0x8F688)
n=0
for i in range(6000):
    r=m.run(100_000)
    if r==ST_BP:
        ax=cpu.get("AX"); bx=cpu.get("BX"); sp=cpu.get("SP"); ss=cpu.get("SS")
        ret=cpu.rd16((ss<<4)+sp); rcs=cpu.rd16((ss<<4)+sp+2); n+=1
        print("send AX=%04X BX=%04X from %04X:%04X"%(ax,bx,rcs,ret))
        if (ax&0xFF)==0x21 and rcs!=0:
            print("  stack:",["%04X"%cpu.rd16((ss<<4)+sp+2*k) for k in range(12)])
            break
    if n>60: break
print("[0xe3c]=%02X"%cpu.rd8(0xe3c), "E60A hits:",cpu.hits[0x80000+0xE60A])
