import sys, math; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
name,xm,cm,tdm=sys.argv[1],int(sys.argv[2]),int(sys.argv[3]),int(sys.argv[4]); noise=int(sys.argv[5]) if len(sys.argv)>5 else 8
m=Machine(nvram_mode=None); m.logging=False; m.xint_mode=xm; m.cycle_model=cm; m.tdm_irqs=bool(tdm); m.noise_amp=noise
m.run(900_000_000); m.send("AT\r"); m.run(150_000_000); m.send("ATI7\r"); m.run(250_000_000)
txt=bytes(c for c in m.dte_out if c!=0xFF); ok=b"Supervisor" in txt or b"7.3.14" in txt
m.send("ATA\r"); h0=m.dsp.dxr_head(); t0=m.hb_count; m.cmd_log16.clear(); m.tx_all.clear(); m._lk_seen=0
m.run(500_000_000)
n=m.dsp.dxr_head()-h0; ticks=m.hb_count-t0
a=[v for v in m.tx_all]; a=[(v^0x8000)-0x8000 for v in a]
def peak(x):
    N=len(x); w=[0.5-0.5*math.cos(2*math.pi*i/N) for i in range(N)]; best=(0,0)
    for k in range(100,400):
        f=k/1000; c=sum(x[i]*w[i]*math.cos(2*math.pi*f*i) for i in range(N)); s=sum(x[i]*w[i]*math.sin(2*math.pi*f*i) for i in range(N))
        if c*c+s*s>best[0]: best=(c*c+s*s,f)
    return best[1]*7200
wins=[round(peak(a[i:i+1024])) for i in range(2048,min(len(a)-1024,60000),12000)]
print("%s: ATI7 ok=%s  ticks=%d dxr=%d  tone peaks(Hz) %s  cmds %s"%(name,ok,ticks,n,wins,[("%04X"%c,"%04X"%x) for t,c,x in m.cmd_log16][:12]))
