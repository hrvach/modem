import sys, math, json; sys.path.insert(0,'.')
from machine import *
from line import *
fs=7200
m=Machine(nvram_mode=None); cpu=m.cpu; m.logging=False
m.run(900_000_000); m.dte_text()
for c in ("AT\r","ATQ0V1X3\r"): m.send(c); m.run(150_000_000); m.dte_text()
m.rx_gen=dial_tone(3000); m.tx_all.clear(); m.cmd_log16.clear(); m.send("ATDT1\r")
removed=False
for i in range(60):
    m.run(100_000_000)
    if not removed and len(m.tx_all)>int(7.4*fs):
        m.rx_gen=None; removed=True; print("dial tone removed at %.2f s"%(len(m.tx_all)/fs))
    if len(m.tx_all)>40*fs: break
print("captured %.1f s; DTE: %r"%(len(m.tx_all)/fs,m.dte_text()))
for t,c,a in m.cmd_log16: print("   %6.2f  %04X %04X"%(t/fs,c,a))
json.dump(m.tx_all,open('/tmp/claude-1000/-home-hrvoje-Programming-USR/831d3a18-6a9c-4288-84f9-a85e9135fc6f/scratchpad/callertest2.json','w'))
tx=m.tx_all
def lines(x):
    res=[]
    for f in range(100,3590,10):
        re=sum(x[k]*math.cos(2*math.pi*f*k/fs) for k in range(0,len(x),2)); im=sum(x[k]*math.sin(2*math.pi*f*k/fs) for k in range(0,len(x),2))
        res.append((math.hypot(re,im)/(len(x)/2)*2,f))
    mx=max(a for a,f in res)
    return [(f,int(a)) for a,f in res if a>0.3*mx and a>=max(b for b,g in res if abs(g-f)<=40)]
for t in (7.35,7.40,9.8,12.0,20.0,30.0,38.0):
    x=tx[int(t*fs):int(t*fs)+500]
    print("t=%.2fs peak %5d lines %s"%(t,max(map(abs,x)),lines(x) if max(map(abs,x))>300 else "-"))
