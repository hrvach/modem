import sys, re; sys.path.insert(0, '.')
from c5x import *
d = DSP(); load_images(d)
for i in range(11): d.set_ivec_ind(i, 0x60 + i)
d.dm[0x65] = 0x8189   # firmware may overwrite; ROM-initialised table assumed
for i in range(11): d.dm[0x60+i] = 0x81AE
d.dm[0x65]=0x8189; d.dm[0x68]=0x820C; d.dm[0x69]=0x81B7
asm = {}
for l in open('dsp_base.asm'):
    m = re.match(r'([0-9A-F]{4})\s+(.*)', l)
    if m: asm[int(m.group(1),16)] = m.group(2)[:60]
d.reset(0x8000); d.log(True)
CPS = 2083; trace = []
for n in range(40):
    for _ in range(CPS):
        trace.append(d.get("PC")); d.run(1)
    d.serial_tick(0)
# print distinct-run compressed trace from first visit of 0x80C5
i0 = trace.index(0x80C5)
last = None; out = []
for pc in trace[i0:]:
    if pc == last: continue
    out.append(pc); last = pc
seen=set(); lines=[]
for pc in out[:260]:
    lines.append("%04X  %s" % (pc, asm.get(pc,'?')))
print("\n".join(lines))
