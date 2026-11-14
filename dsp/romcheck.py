import sys; sys.path.insert(0, '.')
from c5x import *
import re
asm = {}
for l in open('dsp_base.asm'):
    m = re.match(r'([0-9A-F]{4})\s+(.*)', l)
    if m: asm[int(m.group(1),16)] = m.group(2)[:56]
def make(mode):
    d = DSP(); load_images(d)
    for i in range(11): d.set_ivec_ind(i, 0x60 + i); d.dm[0x60+i] = 0x81AE
    d.dm[0x65]=0x8189; d.dm[0x68]=0x820C; d.dm[0x69]=0x81B7
    if mode == "zero": d.set_io(lambda p: 0, lambda p, v: None)
    for a in list(range(0x40, 0x2000)) + list(range(0x2400, 0x8000)): d.bp(a)
    d.reset(0x8000); return d
for mode in ("default", "zero"):
    d = make(mode); CPS = 2083; hit = None
    for n in range(200):
        r = d.run(CPS)
        if r == RUN_BP: hit = n; break
        d.serial_tick(0)
    print("=== io mode:", mode)
    if hit is None: print("no ROM/unmapped entry in 200 samples; state", d.state()); continue
    print("entered %04X at sample %d" % (d.get("PC"), hit)); print(d.state())
    print("last 24 pcs before entry:")
    for p in d.recent_pcs(24)[-24:]: print("  %04X  %s" % (p, asm.get(p, '')))
