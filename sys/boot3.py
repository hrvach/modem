import sys; sys.path.insert(0,'.')
from machine import *
m = Machine(); cpu = m.cpu
m.log.clear()
r = m.run(80_000_000)
print("status", r, "cycles", cpu.cycles); print(cpu.state())
print("phys pc %05X"%cpu.phys_pc(), "badop", [hex(x) for x in cpu.badop()])
print("last pcs:", " ".join("%05X"%p for p in cpu.recent(14)))
from collections import Counter
c = Counter((e[0], e[1]) for e in m.log); print("io top:", [(d, hex(p), n) for (d, p), n in c.most_common(12)])

c2 = Counter((e[0], hex(e[1])) for e in m.pcblog); print("pcb window top:", c2.most_common(12))
print("last pcb:", m.pcblog[-6:])
