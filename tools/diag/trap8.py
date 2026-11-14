import sys; sys.path.insert(0,'.')
from link import *
L=Link()
L.run(900_000_000); L.text()
for m,cmds in ((L.a,("AT\r","ATQ0V1\r")),(L.b,("AT\r","ATQ0V1X3\r"))):
    for c in cmds: m.send(c); L.run(150_000_000)
L.text()
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0; mm.cmd_log16.clear()
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(30*7200): L.run(10_000_000)
b=L.b; cpu=b.cpu
print("B [0x298]=%04X at 30 s"%cpu.rd16(0x298))
# trap the supervisor's dispatch call [0x298] in the INT0 ISR (flash F512 -> phys 0x8F512) and also the FDD3 variant
cpu.bp(0x8F512)
got=0
for i in range(4000):
    r=b.run(100_000)
    if r==ST_BP:
        ax=cpu.get("AX")&0xFFFF
        print("dispatch at F512: AL(type)=%02X AH=%02X BX=%04X CF=%d [0x298]=%04X"%(ax&0xFF,ax>>8,cpu.get("BX"),cpu.get("FLAGS")&1,cpu.rd16(0x298)))
        got+=1
        if got>=12: break
cpu.bp(0x8F512,False)
# now follow one dispatch with type 8 if seen
seen8=False
cpu.bp(0x8F512)
for i in range(4000):
    r=b.run(100_000)
    if r==ST_BP and (cpu.get("AX")&0xFF)==8:
        seen8=True; break
cpu.bp(0x8F512,False)
if seen8:
    path=[]
    for k in range(400):
        cpu.run(1); pc=cpu.phys_pc()-0x80000
        if not path or path[-1]!=pc: path.append(pc)
    print("PATH after dispatch (type 8):"," ".join("%05X"%p for p in path[:140]))
    print("regs:",cpu.state())
else: print("no type-8 dispatch seen")
