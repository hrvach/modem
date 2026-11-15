"""Log hits of 80186 breakpoints (flash/phys addresses) during an ATA on one machine.
usage: bp186.py CMD SECONDS addr[,addr...]   e.g. bp186.py ATA 8 8b6aa,8b6fc,8e60a  (phys = flash+0x80000)"""
import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
cmd=sys.argv[1]; secs=float(sys.argv[2]); bps=[int(a,16) for a in sys.argv[3].split(',')]
m=Machine(nvram_mode=None); m.logging=False
m.run(7*CPU_HZ); m.send("AT\r"); m.run(CPU_HZ); m.send("ATQ0V1\r"); m.run(CPU_HZ)
m.send(cmd+"\r"); t0=m.cpu.cycles; end=t0+int(secs*CPU_HZ)
for b in bps: m.cpu.bp(b)
hits=[]
while m.cpu.cycles<end:
    r=m.run(end-m.cpu.cycles)
    if r==ST_BP:
        c=m.cpu; hits.append(((c.cycles-t0)/CPU_HZ,c.phys_pc()-0x80000,c.rd8(0xE3C),c.rd8(0xE88),c.rd8(0xEA6),c.rd8(0xEA7)))
for h in hits[:80]: print("t+%.3f flash %05X E3C=%02X E88=%02X EA6=%02X EA7=%02X"%h)
print(len(hits),"hits; text",m.dte_text()[-60:])
