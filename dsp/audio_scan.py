import sys, struct; sys.path.insert(0, '.')
from c5x import *
base = open('dsp_base.bin','rb').read(); BW = struct.unpack('<%dH'%(len(base)//2), base)
tab = [BW[0x8401-0x8000+i] for i in range(0x80)]
OV = {6:(0x9D00,'dsp_ov6.bin'), 7:(0xB000,'dsp_ov7.bin'), 8:(0xDC00,'dsp_ov8.bin')}
ovdata = {k:open(f,'rb').read() for k,(a,f) in OV.items()}
rng = {k:(a, a+len(ovdata[k])//2) for k,(a,f) in OV.items()}
CPS = 2083
def boot():
    d = DSP(); load_images(d)
    for i in range(11): d.set_ivec_ind(i, 0x60+i); d.dm[0x60+i] = 0x81AE
    d.dm[0x65]=0x8189; d.dm[0x68]=0x820C; d.dm[0x69]=0x81B7
    d.reset(0x8000); d.log(True)
    for n in range(14): d.run(CPS); d.serial_tick(0)
    return d
def measure(d, nsamp=300):
    d.log_clear(); ok = True
    for n in range(nsamp):
        r = d.run(CPS)
        if r != RUN_OK: ok = False; break
        d.serial_tick(0)
    vals = [v for c,pc,p,v,w in d.events() if p == 0x8021]
    return ok, vals
d = boot(); ok, v = measure(d); print("baseline idle: ok=%s DXR writes=%d distinct=%s" % (ok, len(v), sorted(set(v))[:10]))
res = []
seen = set()
for cmd, addr in enumerate(tab):
    if addr < 0x8100 or addr in seen or cmd >= 0x7A: continue
    seen.add(addr)
    ov = next((k for k,(lo,hi) in rng.items() if lo <= addr < hi), None)
    d = boot()
    if ov: d.load_pm(OV[ov][0], ovdata[ov])
    d.set("PUSH", 0x813A); d.set("PC", addr); d.set("ST0", d.get("ST0") & ~0x200)
    ok, v = measure(d)
    s = sorted(set(v))
    res.append((cmd, addr, ov, ok, len(v), len(s), s[:3], s[-3:]))
print("cmd addr   ov ok  nDXR distinct  min..max")
for r in res:
    if r[5] > 8 or not r[3]:
        print("%02X  %04X  %s  %-5s %5d %5d  %s .. %s" % (r[0], r[1], r[2], r[3], r[4], r[5], [hex(x) for x in r[6]], [hex(x) for x in r[7]]))
print("handlers tried:", len(res), " with varied DXR output:", sum(1 for r in res if r[5] > 8))
