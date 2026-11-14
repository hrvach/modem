import sys; sys.path.insert(0, '.')
from c5x import *
CPS = 2083
def make(cmpr_ar0=True):
    d = DSP(); load_images(d)
    for i in range(11): d.set_ivec_ind(i, 0x60+i); d.dm[0x60+i] = 0x81AE
    d.dm[0x65]=0x8189; d.dm[0x68]=0x820C; d.dm[0x69]=0x81B7
    d.regs = {0x57:0, 0x5E:0, 0x5F:0}; d.outs = []; d.reads = []
    def rd(p):
        q = p & 0xFF
        v = d.regs.get(q, 0) if (p == q or p >= 0xFF50) and q in d.regs else 0
        if q in d.regs: d.reads.append((d.get("PC"), q, v))
        return v
    def wr(p, v):
        q = p & 0xFF; d.outs.append((d.get("PC"), q, v))
        if q == 0x57: d.regs[0x57] = 0            # ack clears "message pending"
    d.set_io(rd, wr); d.set_cmpr_ar0(cmpr_ar0); d.reset(0x8000)
    for n in range(14): d.run(CPS); d.serial_tick(0)
    return d
def post(d, cmd, arg=0, hi=0):
    d.regs[0x5E] = cmd; d.regs[0x5F] = arg; d.regs[0x57] = 1
def run(d, nsamp):
    for n in range(nsamp):
        r = d.run(CPS)
        if r != RUN_OK: return r
        d.serial_tick(0); d.irq(TRNT); d.irq(TXNT)
    return RUN_OK
if __name__ == "__main__":
    rows = []
    for cmd in range(0, 0x7F):
        d = make(); post(d, cmd, 0); d.outs.clear(); d.log(True); d.log_clear()
        imr0 = d.get("IMR"); r = run(d, 80)
        ev = d.events()
        ports = {}
        for c_,pc,p,v,w in ev:
            if w: ports[p] = ports.get(p,0)+1
        rows.append((cmd, r, d.get("PC"), imr0, d.get("IMR"), ports, len(d.outs)))
    for r in rows:
        print("%02X r=%d PC=%04X IMR %04X->%04X  writes=%s  hostwrites=%d" % (r[0], r[1], r[2], r[3], r[4], {hex(k):v for k,v in sorted(r[5].items())}, r[6]))
