import sys, math; sys.path.insert(0,'.')
from machine import *
from line import *
fs=7200
def lines(x):
    res=[]
    for f in range(100,3590,10):
        re=sum(x[k]*math.cos(2*math.pi*f*k/fs) for k in range(len(x))); im=sum(x[k]*math.sin(2*math.pi*f*k/fs) for k in range(len(x)))
        res.append((math.hypot(re,im)/len(x)*2,f))
    mx=max(a for a,f in res)
    return [(f,int(a)) for a,f in res if a>0.3*mx and a>=max(b for b,g in res if abs(g-f)<=40)]
def scenario(label, slice_cycles, with_idle_a):
    m=Machine(nvram_mode=None); m.logging=False
    a=Machine(nvram_mode=None) if with_idle_a else None
    def adv(n):
        done=0
        while done<n:
            m.run(slice_cycles)
            if a: a.run(slice_cycles)
            done+=slice_cycles
    adv(900_000_000); m.dte_text()
    for c in ("AT\r","ATQ0V1X3\r"): m.send(c); adv(150_000_000); m.dte_text()
    m.rx_gen=dial_tone(3000); m.tx_all.clear(); m.send("ATDT1\r")
    while len(m.tx_all)<int(9*fs): adv(10_000_000)
    print(label,"peak per 0.25 s, 6.5-9 s:",[max(map(abs,m.tx_all[int(t*fs):int((t+0.25)*fs)])) for t in (6.5,6.75,7.0,7.25,7.5,7.75,8.0,8.25,8.5,8.75)],flush=True)
    for t in (7.0,7.25,7.5,8.5):
        x=m.tx_all[int(t*fs):int(t*fs)+600]
        if max(map(abs,x))>300: print("    t=%.2f lines %s first samples %s"%(t,lines(x),x[:8]),flush=True)
scenario("alone, 100k-cycle slices", 100_000, False)
scenario("with idle 2nd machine, 100k", 100_000, True)
