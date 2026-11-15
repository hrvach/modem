import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(7*CPU_HZ); c=m.cpu
for a in sys.argv[1:]:
    a=int(a,16); print("[%04X]=%02X %02X"%(a,c.rd8(a),c.rd8(a+1)))
