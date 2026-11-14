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

b=L.b.dsp; dm=b.dm
b.bp(0x87CE)
r=b.run(200000)
st0=b.get("ST0"); dp=(st0&0x1FF)*128
print("stopped at 87CE: run result",r,"PC=%04X"%b.get("PC"),"ST0=%04X DP page base=%04X"%(st0,dp),"ACC=%08X AR1=%04X"%(b.get("ACC"),b.get("AR1")))
print("regs:",b.state())
print("data at DP: [DP+0x00]=%04X [DP+0x02]=%04X [DP+0x0B]=%04X [DP+0x14]=%04X [DP+0x07]=%04X [DP+0x05]=%04X"%tuple(dm[(dp+o)&0xFFFF] for o in (0,2,0x0B,0x14,0x07,0x05)))
print("dm[DP..DP+0x7F]:",["%04X"%dm[(dp+i)&0xFFFF] for i in range(0x80)])
ar1=b.get("AR1"); print("*AR1 (flags word) at %04X = %04X"%(ar1,dm[ar1]))
# find the same for several consecutive stops: sample a few values of the energy words
vals=[]
for k in range(8):
    b.run(5000)
    r=b.run(50000)
    vals.append(("%04X"%dm[dp],"%04X"%dm[(dp+2)&0xFFFF],b.get("ACC")))
print("energy words [DP+0],[DP+2] and ACC at next stops:",vals)
