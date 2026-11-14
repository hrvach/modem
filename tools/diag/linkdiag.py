import sys; sys.path.insert(0,'.')
from link import *
L=Link()
L.run(900_000_000); L.text()
for m,cmds in ((L.a,("AT\r","ATQ0V1\r")),(L.b,("AT\r","ATQ0V1X3\r"))):
    for c in cmds: m.send(c); L.run(150_000_000)
L.text()
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0; mm.cmd_log16.clear(); mm.dsp_log.clear()
L.audio={'a':[],'b':[]}; L.events=[]; L.start_call("1")
while L.samples() < int(40*7200): L.run(10_000_000)
print("t=%.1f s events:"%(L.samples()/7200),L.events)
b=L.b; cpu=b.cpu; dsp=b.dsp
print("B DSP:",dsp.state())
# DSP->host messages sent by B after 23 s: (kcycles, port, val) for ports 5e/5f
msgs=[(c//1000,hex(q),hex(v)) for c,q,v in b.dsp_log if q in (0x5e,0x5f)]
print("B DSP->host message words:",len(msgs),msgs[:24])
# DSP PC histogram (hits) in the 0x8000-0xFFFF range, top 12
hits=[(dsp.hits[i],i) for i in range(0x8000,0x10000) if dsp.hits[i]]
hits.sort(reverse=True); print("B DSP hottest pcs:",[("%04X"%i,n) for n,i in hits[:12]])
dsp_before={i:dsp.hits[i] for i in range(0x8000,0x10000)}
b.run(30_000_000)
d2=sorted(((dsp.hits[i]-dsp_before[i],i) for i in range(0x8000,0x10000) if dsp.hits[i]!=dsp_before[i]),reverse=True)
print("B DSP pcs in the next 30M cycles:",len(d2),[("%04X"%i,n) for n,i in d2[:12]])
print("B DSP ptr[0x39A]=%04X [0x39B]=%04X IMR=%04X"%(dsp.dm[0x39A],dsp.dm[0x39B],dsp.get("IMR")))
print("B CPU: [0x26e]=%04X [0x298]=%04X [0x134]=%04X [0x32c]=%02X [0xbd7]=%02X [0xe3c]=%02X [0xe88]=%02X"%(cpu.rd16(0x26e),cpu.rd16(0x298),cpu.rd16(0x134),cpu.rd8(0x32c),cpu.rd8(0xbd7),cpu.rd8(0xe3c),cpu.rd8(0xe88)))
cb=[cpu.hits[i] for i in range(0x80000,0x100000)]
b.run(20_000_000)
ca=[cpu.hits[i] for i in range(0x80000,0x100000)]
d3=sorted(((ca[i]-cb[i],i) for i in range(len(ca)) if ca[i]!=cb[i]),reverse=True)
print("B CPU hot flash offsets:",[("%05X"%i,n) for n,i in d3[:8]])
sp=cpu.get("SP"); ss=cpu.get("SS"); print("B stack:",["%04X"%cpu.rd16((ss<<4)+sp+2*k) for k in range(10)])
print("B cmds:",[(round(t/7200,2),"%04X"%c,"%04X"%a) for t,c,a in b.cmd_log16 if t>20*7200])
print("A cmds:",[(round(t/7200,2),"%04X"%c,"%04X"%a) for t,c,a in L.a.cmd_log16 if t>20*7200])
