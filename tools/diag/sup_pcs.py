import sys, collections; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
e3c=int(sys.argv[1],16); secs=float(sys.argv[2])
m=Machine(nvram_mode=None); m.logging=False
m.run(4*CPU_HZ); m.send("AT\r"); m.run(CPU_HZ); m.dte_text()
m.cpu.wr8(0xE3C,e3c); m.send("ATA\r"); c=m.cpu
pcs=collections.Counter(); end=c.cycles+int(secs*CPU_HZ)
while c.cycles<end:
    m.run(100_000); pcs[c.phys_pc()-0x80000]+=1
print([('%05X'%p,n) for p,n in pcs.most_common(25)])
print('E88=%02X E3C=%02X 134=%04X 32B=%02X 32C=%02X EA6=%02X EA7=%02X B88=%02X'%(c.rd8(0xE88),c.rd8(0xE3C),c.rd16(0x134),c.rd8(0x32B),c.rd8(0x32C),c.rd8(0xEA6),c.rd8(0xEA7),c.rd8(0xB88)))
