import sys; sys.path.insert(0,'.')
from link import *
from collections import Counter
L=Link()
L.run(900_000_000); L.text()
for m,cmds in ((L.a,("AT\r","ATQ0V1\r")),(L.b,("AT\r","ATQ0V1X3\r"))):
    for c in cmds: m.send(c); L.run(150_000_000)
L.text()
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0; mm.cmd_log16.clear(); mm.dsp_log.clear()
L.audio={'a':[],'b':[]}; L.events=[]; L.start_call("1")
snap=[]
while L.samples() < int(45*7200):
    L.run(10_000_000)
    snap.append((round(L.samples()/7200,1),"A task %04X/%04X"%(L.a.dsp.dm[0x39A],L.a.dsp.dm[0x39B]),"B task %04X/%04X"%(L.b.dsp.dm[0x39A],L.b.dsp.dm[0x39B])))
for s in snap[::2]: print(s)
def msgs(m,label):
    cur={}; out=[]
    for c,q,v in m.dsp_log:
        if q in (0x5E,0x5F): cur[q]=v
        if q==0x5F: out.append((cur.get(0x5E,0),v))
    cnt=Counter(out)
    print(label,"DSP->host message pairs (low word, high word) counts:",cnt.most_common(12),"total",len(out))
msgs(L.a,"A"); msgs(L.b,"B")
