import sys, struct; sys.path.insert(0, '.')
from c5x import *
CPS = 2083
CMPR_AR0 = True
def make():
    d = DSP(); load_images(d)
    for i in range(11): d.set_ivec_ind(i, 0x60+i); d.dm[0x60+i] = 0x81AE
    d.dm[0x65]=0x8189; d.dm[0x68]=0x820C; d.dm[0x69]=0x81B7
    d.q = []; d.acks = []; d.outs = []
    def rd(p):
        if p == 0x57 and d.q: return d.q.pop(0)       # real value of each helper call = 2nd read (port 0x57)
        return 0
    def wr(p, v):
        d.outs.append((d.get("PC"), p, v))
        if p == 0x57: d.acks.append(v)
    d.set_io(rd, wr); d.set_cmpr_ar0(CMPR_AR0); d.reset(0x8000)
    for n in range(14): d.run(CPS); d.serial_tick(0)
    return d
def send(d, cmd, arg, nsamp=60):
    d.q[:] = [0x0001, cmd, arg]; d.outs.clear(); d.acks.clear(); d.log(True); d.log_clear()
    imr0 = d.get("IMR"); pcs = set()
    for n in range(nsamp):
        r = d.run(CPS)
        if r != RUN_OK: return ("stop%d"%r, d.get("PC"), imr0, d.get("IMR"), 0, 0)
        d.serial_tick(0); d.irq(TRNT); d.irq(TXNT)
    ev = d.events()
    return ("ok", d.get("PC"), imr0, d.get("IMR"), len(d.acks), len([e for e in ev if e[2] in (0x8021,0x8030,0x8031,0x6A,0x68,0x69,0x6B,0x6C)]))
if __name__ == "__main__":
    rows = []
    for cmd in range(0, 0x7F):
        d = make(); res = send(d, cmd, 0)
        rows.append((cmd,)+res)
    print("cmd  status  PC    IMR0->IMR  acks outs")
    for r in rows:
        if r[1] != "ok" or r[4] != r[5] or r[6] or r[3] != 0x813A: print("%02X   %-6s %04X  %04X->%04X  %d  %d" % (r[0], r[1], r[2], r[3], r[4], r[5], r[6]))
    print("total", len(rows), "ran; acks>0:", sum(1 for r in rows if r[5]>0))
