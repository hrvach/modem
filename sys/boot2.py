import sys; sys.path.insert(0, '.')
from i186 import *
TICK = 250000
cpu = CPU()
flash = open('../SV25.flash.bin', 'rb').read()
cpu.load(0x80000, flash)
for p in range(0x80, 0x100): cpu.ro_page(p)
ports = {}; log = []
def iord(p, w): log.append(("R", p, w, cpu.phys_pc())); return ports.get(p, 0)
def iowr(p, w, v): log.append(("W", p, w, v, cpu.phys_pc())); ports[p] = v
cpu.hooks(iord, iowr)
cpu.reset()
next_tick = TICK; r = 0
while cpu.cycles < 60_000_000:
    r = cpu.run(5000)
    if r not in (ST_OK, ST_HLT): break
    if cpu.cycles >= next_tick: cpu.irq(0x0F); next_tick += TICK
print("status", r, "cycles", cpu.cycles); print(cpu.state())
print("phys pc %05X" % cpu.phys_pc(), " badop", [hex(x) for x in cpu.badop()])
print("last pcs:", " ".join("%05X" % p for p in cpu.recent(14)))
from collections import Counter
c = Counter((e[0], e[1]) for e in log); print("io (dir,port):count top:", [(d, hex(p), n) for (d, p), n in c.most_common(14)])
print("last 12 io:", log[-12:])
