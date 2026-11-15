import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(4*CPU_HZ); m.send("AT\r"); m.run(CPU_HZ); m.dte_text(); m.send("ATA\r"); d=m.dsp; d.set_watch(int(sys.argv[1],16))
prev={}
for i in range(26):
    n0=len(m.tx_all); m.run(CPU_HZ//2); x=m.tx_all[n0:]; pk=max(map(abs,x)) if x else 0
    cur={a:d.watch_hits(a) for a in range(0x8000,0x10000) if d.watch_hits(a)}
    delta={a:cur[a]-prev.get(a,0) for a in cur if cur[a]-prev.get(a,0)}
    prev=cur
    print("t+%4.1f peak=%5d writers %s"%((i+1)*0.5+0,pk,' '.join('%04X:%d'%(a,n) for a,n in sorted(delta.items(),key=lambda x:-x[1])[:5])))
