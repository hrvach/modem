import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
fs=7200
L=Link(); L.run(900_000_000); L.text()
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(150_000_000)
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0; mm.cmd_log16.clear()
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
last={}
def util(tag):
    out=[]
    for nm,mm in (("A",L.a),("B",L.b)):
        i,t=mm.dsp.idle_cycles(),mm.dsp.total_cycles(); pi,pt=last.get(nm,(0,0)); last[nm]=(i,t)
        out.append("%s idle %.0f%%"%(nm,100*(i-pi)/max(t-pt,1)))
    print("t=%5.1fs"%(L.samples()/fs),tag,"  ".join(out),flush=True)
for T in (4,8,12,16,20,24,28,32,40):
    while L.samples() < T*fs: L.run(5_000_000)
    util(str(L.events[-1][1] if L.events else ''))
