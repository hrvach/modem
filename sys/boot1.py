import sys; sys.path.insert(0, '.')
from i186 import *
cpu = CPU()
flash = open('../SV25.flash.bin', 'rb').read()
cpu.load(0x80000, flash)
for p in range(0x80, 0x100): cpu.ro_page(p)
ports = {}; log = []
def iord(p, w): log.append(("R", p, w, cpu.phys_pc())); return ports.get(p, 0)
def iowr(p, w, v): log.append(("W", p, w, v, cpu.phys_pc())); ports[p] = v
cpu.hooks(iord, iowr)
cpu.reset()
for i in range(200):
    r = cpu.run(20000)
    if r != ST_OK: break
print("status", r, "cycles", cpu.cycles); print(cpu.state())
print("phys pc %05X" % cpu.phys_pc(), " badop", [hex(x) for x in cpu.badop()])
print("last pcs:", " ".join("%05X" % p for p in cpu.recent(16)))
print("io events", len(log)); 
for e in log[:40]: print(e)
