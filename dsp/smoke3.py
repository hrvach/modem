import sys; sys.path.insert(0, '.')
from c5x import *
d = DSP(); load_images(d); d.reset(0x8000); d.log(True)
CPS = 2083
def step_until_lowpc(maxsamples=3000):
    for n in range(maxsamples):
        # run in small slices to catch first excursion
        for _ in range(CPS // 16 + 1):
            d.run(16)
            if d.get("PC") < 0x8000 or d.get("PC") > 0xF000: return n
        d.serial_tick(0)
n = step_until_lowpc()
print("left image after", n, "samples"); print(d.state())
print("recent pcs", " ".join("%04X" % p for p in d.recent_pcs(24)))
print("stack", [hex(d.get("SP"))])
