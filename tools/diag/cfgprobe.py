import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
def show(t): c=m.cpu; print(t,"A96=%02X 5A5=%02X 685=%02X 5CD=%02X 5FA=%02X 600=%02X 27F=%04X 5E5=%02X E06=%02X"%(c.rd8(0xA96),c.rd8(0x5A5),c.rd8(0x685),c.rd8(0x5CD),c.rd8(0x5FA),c.rd8(0x600),c.rd16(0x27F),c.rd8(0x5E5),c.rd8(0xE06)))
m.run(7*CPU_HZ); show("boot")
for cmd in sys.argv[1:]:
    m.send(cmd+"\r"); m.run(CPU_HZ); show(cmd); print(m.dte_text()[-50:])
