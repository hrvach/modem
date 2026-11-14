import sys; sys.path.insert(0, '.')
from c5x import *
exec(open('smoke5.py').read().split("p = d.recent_pcs")[0].split("CPS = 2083")[0])
CPS=2083
for n in range(3000):
    d.run(CPS); d.serial_tick(0)
print(d.state())
print("data[0x60..0x7F]:", " ".join("%04X"%d.dm[i] for i in range(0x60,0x80)))
ev=d.events()
print([ (hex(p),hex(v),w) for c_,pc,p,v,w in ev if p<0x8000][:40])
