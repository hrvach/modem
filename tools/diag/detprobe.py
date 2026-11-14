import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
import c5x
fs=7200
L=Link(); L.run(900_000_000); L.text()
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(150_000_000)
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0; mm.cmd_log16.clear(); mm.dsp_log.clear()
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < 26*fs: L.run(10_000_000)
b=L.b.dsp; dm=b.dm
print("B ring ptrs [78]=%04X [79]=%04X"%(dm[0x78],dm[0x79]), "ring:",["%04X"%dm[0xBD0+i] for i in range(16)])
print("ptrs [39A]=%04X [39B]=%04X"%(dm[0x39A],dm[0x39B]), "dm[0x6F]=%04X dm[0x70]=%04X"%(dm[0x6F],dm[0x70]))
for pc,name in ((0x87D5,"after-compare"),(0x83C8,"post-msg"),(0x83D6,"send-msg"),(0x87CE,"detector-entry")):
    b.set_trace(pc)
    # advance only B's DSP ~1.5 s (ticks of 2083 cycles); keep feeding its input from the link queue
    for k in range(10800):
        base = L.b.rxbuf.popleft() if L.b.rxbuf else 0
        v = base if base<32768 else base-65536
        b.run(2083); b.serial_tick(v); b.irq(c5x.TRNT); b.irq(c5x.TXNT)
    t=b.trace()
    print(name,"hits",len(t),"first acc/ret:",[("%08X"%a,"%04X"%r1) for a,r1,r2 in t[:6]])
