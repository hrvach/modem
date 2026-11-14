import sys; sys.path.insert(0,'.')
from link import *
L=Link()
L.run(900_000_000); L.text()
for m,cmds in ((L.a,("AT\r","ATQ0V1\r")),(L.b,("AT\r","ATQ0V1X3\r"))):
    for c in cmds: m.send(c); L.run(150_000_000)
L.text()
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(30*7200): L.run(10_000_000)
def s16(v): return v-65536 if v>32767 else v
b=L.b.dsp; a=L.a.dsp
for pc in (0x87B6,0x87CE,0xD8C1,0xD94A,0xD8C8):
    b.hits  # hits are cumulative; take deltas
h0={pc:b.hits[pc] for pc in (0x87B6,0x87CE,0xD8C1,0xD94A,0xD8C8,0x8BCE)}
L.run(20_000_000)
print("B DSP executions in ~2.6 s of audio:",{hex(pc):b.hits[pc]-h0[pc] for pc in h0})
dm=b.dm
print("B data page 0x300-0x31F:",["%04X"%dm[0x300+i] for i in range(32)])
print("B data page 0x360-0x37F:",["%04X"%dm[0x360+i] for i in range(32)])
print("B [0x36F]=%04X [0x370]=%04X [0x30B]=%04X [0x300]=%04X [0x302]=%04X [0x314]=%04X"%(dm[0x36F],dm[0x370],dm[0x30B],dm[0x300],dm[0x302],dm[0x314]))
print("B task ptrs [0x39A]=%04X [0x39B]=%04X"%(dm[0x39A],dm[0x39B]))
print("A task ptrs [0x39A]=%04X [0x39B]=%04X  [0x370]=%04X"%(a.dm[0x39A],a.dm[0x39B],a.dm[0x370]))
