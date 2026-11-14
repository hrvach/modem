import sys; sys.path.insert(0, '.')
from c5x import *
d = DSP(); load_images(d)
def vec(a, tgt): d.pm[a] = 0x7980; d.pm[a+1] = tgt
vec(0x18, 0x820C); d.set_ivec_ind(XINT, 0x65); d.dm[0x65] = 0x8189
d.reset(0x8000); d.log(True)
CPS = 2083
done = False
for n in range(3000):
    left = CPS
    while left > 0:
        d.run(1); left -= 1
        pc = d.get("PC")
        if (0x40 < pc < 0x2000) or (0x2400 <= pc < 0x8000): done = True; break
    if done: break
    d.serial_tick(0)
p = d.recent_pcs(30)
print("sample", n, " ".join("%04X" % x for x in p)); print(d.state())
