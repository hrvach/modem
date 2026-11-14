import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
fs=7200
L=Link(); L.run(900_000_000); L.text()
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(150_000_000)
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0; mm.cmd_log16.clear(); mm.dsp_log.clear(); mm.rx_log.clear(); mm.rx_under=0
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < 32*fs: L.run(10_000_000)
print("events",[(round(t,1),s) for t,s in L.events])
for nm,rx,tx in (("B<-A",L.b,L.a),("A<-B",L.a,L.b)):
    r=rx.rx_log; t=[v&0xFFFF for v in tx.tx_all]
    print(nm,"underruns",rx.rx_under,"rx_log",len(r),"peer tx",len(t))
    # take a window of 200 received samples late in the call, find it in peer's tx (gain 1.0 => identical)
    w=r[-300:-100]; pos=None
    ts=bytes(); 
    idx=-1
    for i in range(len(t)-200, 0, -1):
        if t[i:i+8]==w[:8] and t[i:i+200]==w: idx=i; break
    print("  late window found in peer tx at",idx,"(total tx",len(t),") -> lag",(len(t)-idx) if idx>=0 else None,"samples")
    # how many rx_log entries are from the call phase vs tx index: lag at an early point too
