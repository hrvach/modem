import sys; sys.path.insert(0, '.')
from c5x import *
d = DSP(); load_images(d); d.reset(0x8000); d.log(True)
for step in range(40):
    r = d.run(200000)
    if r != RUN_OK: break
print("run result", r); print(d.state())
ev = d.events(); print(len(ev), "io events")
seen = {}
for cyc, pc, port, val, wr in ev[:60]: print("%8d pc=%04X %s port=%04X val=%04X" % (cyc, pc, "W" if wr else "R", port, val))
print("recent pcs", " ".join("%04X" % p for p in d.recent_pcs(16)))
