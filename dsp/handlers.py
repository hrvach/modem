import sys, struct, re; sys.path.insert(0, '.')
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
    for a in list(range(0x40,0x2000)) + list(range(0x2400,0x8000)): d.bp(a)
    d.reset(0x8000)
    for n in range(14): d.run(CPS); d.serial_tick(0)
    return d
def try_handler(ov, cmd, addr):
    d = boot(); d.load_pm(OV[ov][0], ovdata[ov])
    d.set("PUSH", 0x813A); d.set("PC", addr); d.set("ST0", d.get("ST0") & ~0x200)
    d.set("SETIDLE", 0)
    for n in range(40):
        r = d.run(CPS)
        if r == RUN_BP: return ("ROM/unmapped entry", "%04X from %s" % (d.get("PC"), " ".join("%04X"%p for p in d.recent_pcs(6))))
        if r == RUN_BADOP: return ("badop", "%04X" % d.get("PC"))
        d.serial_tick(0)
        if 0x813A <= d.get("PC") <= 0x813C: return ("returned/parked", n)
    return ("still running", "%04X" % d.get("PC"))
summary = {}
for ov,(lo,hi) in rng.items():
    hs = sorted({(c,a) for c,a in enumerate(tab) if lo <= a < hi})
    print("overlay", ov, "range %04X-%04X, %d command handlers inside" % (lo,hi,len(hs)), flush=True)
    for c,a in hs:
        res = try_handler(ov, c, a); summary.setdefault(res[0], []).append((ov,c,a,res[1]))
        if res[0] in ("ROM/unmapped entry","badop"): print("  cmd %02X -> %04X : %s %s" % (c,a,res[0],res[1]), flush=True)
print({k: len(v) for k,v in summary.items()})
