import sys, math; sys.path.insert(0,'.')
from link import *
L=Link()
fed=[]
orig=L.b.dsp_rd if hasattr(L.b,'dsp_rd') else None
L.run(900_000_000); L.text()
for m,cmds in ((L.a,("AT\r","ATQ0V1\r")),(L.b,("AT\r","ATQ0V1X3\r"))):
    for c in cmds: m.send(c); L.run(150_000_000)
L.text()
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0; mm.cmd_log16.clear()
L.audio={'a':[],'b':[]}; L.events=[]; L.start_call("1")
while L.samples() < int(32*7200): L.run(10_000_000)
b=L.b
print("B rxbuf backlog (samples waiting to be read by B's DSP): %d ; A rxbuf backlog %d"%(len(b.rxbuf),len(L.a.rxbuf)))
print("A audio produced: %d samples, B audio produced: %d samples"%(len(L.audio['a']),len(L.audio['b'])))
# what B's DSP has stored from DRR: ring at data 0x0BD0..0x0BDF
def s16(v): return v-65536 if v>32767 else v
ring=[s16(b.dsp.dm[0x0BD0+i]) for i in range(16)]
print("B DSP ring 0x0BD0..0x0BDF:",ring)
# sample B's DSP DRR register and A's latest output for a window of ticks
print("last A output samples:",L.audio['a'][-16:])
print("B cur_rx now:",b.cur_rx, " B noise_amp",b.noise_amp)
# step the machine tick by tick and log (cur_rx fed, DSP's dm[0x20? DRR] ) for 40 ticks
import c5x
vals=[]
for i in range(60):
    b.run(5000)
    vals.append((s16(b.cur_rx), s16(b.dsp.get("DRR"))))
print("fed vs DSP DRR register (last 30):",vals[-30:])
