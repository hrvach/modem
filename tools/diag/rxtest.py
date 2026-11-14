import sys, math; sys.path.insert(0,'../dsp')
from host3 import *
from collections import Counter
fs=7200
def send_cmds(d, cmds):
    for c,a in cmds:
        post(d,c,a)
        for _ in range(400):
            run(d,1)
            if d.regs[0x57]==0: break
def trial(amp, freq=1650, nsamp=6000, noise=8):
    d=make()
    d.msgs=[]
    orig_wr=d.outs
    send_cmds(d,[(0x01,0x3F),(0x1A,0x3D00),(0x3C,0x32D6),(0x20,0x0100)])
    d.outs.clear()
    seed=1; k=0; h0=d.dxr_head()
    for n in range(nsamp):
        seed=(seed*1103515245+12345)&0x7FFFFFFF
        x=int(amp*math.sin(2*math.pi*freq*n/fs))+((seed>>16)%(2*noise+1))-noise
        r=d.run(CPS); d.serial_tick(x); d.irq(TRNT); d.irq(TXNT)
    msgs=[]; cur={}
    for pc,q,v in d.outs:
        if q in (0x5E,0x5F): cur[q]=v
        if q==0x5F: msgs.append((cur.get(0x5E,0),v))
    h=d.dxr_head(); r_=d.dxr_ring()
    tx=[(r_[i&0xFFFF]-65536 if r_[i&0xFFFF]>32767 else r_[i&0xFFFF]) for i in range(h0,h)]
    return Counter(msgs).most_common(5), (max(map(abs,tx)) if tx else 0), len(tx)
for amp in (0,300,1000,3000,8000,18000):
    print("input 1650 Hz amp %5d -> messages %s  tx peak %d (%d writes)"%((amp,)+trial(amp)),flush=True)
