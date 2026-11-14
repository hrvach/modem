import sys; sys.path.insert(0, '.')
from c5x import *
d = DSP(); load_images(d)
for i in range(11): d.set_ivec_ind(i, 0x60 + i)
for i in range(11): d.dm[0x60+i] = 0x81AE
d.dm[0x65]=0x8189; d.dm[0x68]=0x820C; d.dm[0x69]=0x81B7
reads = []
fifo = []
def rd(p):
    v = fifo.pop(0) if (p in (0x57, 0xFF57) and fifo) else 0
    reads.append((d.get("PC"), p, v)); return v
def wr(p, v): reads.append((d.get("PC"), p, v, 'W'))
d.set_io(rd, wr)
d.reset(0x8000)
CPS = 2083
for n in range(14): d.run(CPS); d.serial_tick(0)
print("booted:", d.state()); reads.clear()
fifo[:] = [0x8001, 0x0002, 0x1234]     # trial message: status/flag, command 2, arg
for n in range(6): d.run(CPS); d.serial_tick(0)
print("after msg:", d.state()); print("remaining fifo", fifo)
for r in reads[:40]: print(r)
