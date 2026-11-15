import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(7*CPU_HZ); c=m.cpu; m.dte_text()
for cmd in sys.argv[1:]:
    b=(c.rd8(0x5FA),c.rd8(0x600),c.rd8(0x5EF),c.rd8(0x5EC),c.rd8(0x5CD))
    m.send(cmd+"\r"); m.run(CPU_HZ*3//4); a=(c.rd8(0x5FA),c.rd8(0x600),c.rd8(0x5EF),c.rd8(0x5EC),c.rd8(0x5CD))
    print(cmd,'(5FA,600,5EF,5EC,5CD) before',b,'after',a,m.dte_text().strip()[:20])
