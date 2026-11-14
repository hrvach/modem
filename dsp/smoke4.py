import sys; sys.path.insert(0, '.')
from c5x import *
from collections import Counter
d = DSP(); load_images(d)
def vec(a, tgt): d.pm[a] = 0x7980; d.pm[a+1] = tgt   # B tgt
vec(0x18, 0x820C); d.set_ivec_ind(XINT, 0x65); d.dm[0x65] = 0x8189
d.reset(0x8000); d.log(True)
CPS = 2083
for n in range(3000):
    r = d.run(CPS)
    if r != RUN_OK: print("stopped", r); break
    d.serial_tick(0)
    if d.get("PC") < 0x8000: print("lowpc at sample", n); break
print(d.state())
print("recent pcs", " ".join("%04X" % p for p in d.recent_pcs(20)))
ev = d.events(); cnt = Counter((p, w) for _, _, p, _, w in ev)
for (p, w), k in sorted(cnt.items()): print("  %s %04X x%d" % ("W" if w else "R", p, k))
print("first 25 DXR/SPC/0x32 writes:", [(hex(p),hex(v)) for c_,pc,p,v,w in ev if p in (0x8021,)][:40])
p = d.recent_pcs(256)
k = next(i for i in range(256) if p[i] < 0x8000)
print("last in-image pcs before excursion:", " ".join("%04X" % x for x in p[max(0,k-14):k+3]))
print("stack depth sp=", d.get("SP"))
