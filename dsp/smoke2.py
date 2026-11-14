import sys; sys.path.insert(0, '.')
from c5x import *
d = DSP(); load_images(d); d.reset(0x8000); d.log(True)
CPS = 2083  # cycles per codec sample
dx = []
for n in range(3000):
    r = d.run(CPS)
    if r != RUN_OK: print("stopped", r); break
    d.serial_tick(0)
print(d.state())
ev = d.events()
from collections import Counter
cnt = Counter((p, w) for _, _, p, _, w in ev)
print(len(ev), "events"); 
for (p, w), k in sorted(cnt.items()): print("  %s %04X x%d" % ("W" if w else "R", p, k))
print("recent pcs", " ".join("%04X" % p for p in d.recent_pcs(16)))
hits = [i for i in range(0x8000, 0xF000) if d.hits[i]]
print("distinct pcs executed:", len(hits))
