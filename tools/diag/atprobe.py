import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(7*CPU_HZ); m.dte_text()
for cmd in sys.argv[1:]:
    m.send(cmd+"\r"); m.run(CPU_HZ*3//2); print(repr(cmd),'->',m.dte_text())
