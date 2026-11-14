import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
from collections import Counter
fs=7200
L=Link(); L.run(900_000_000); L.text()
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(150_000_000)
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0; mm.cmd_log16.clear()
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")

for nm,mm in (("B",L.b),("A",L.a)):
    mm.port5_pcs.clear() if hasattr(mm.port5_pcs,'clear') else None


t=0
for T in (12,16,20,26,32,40,50,60):
    while L.samples() < T*fs: L.run(5_000_000)
    for nm,mm in (("B",L.b),("A",L.a)):
        r=mm.cpu.rd16
        print("t=%2d %s E88=%02X [134]=%04X [138]=%04X 298=%04X 26E=%04X 32C=%02X BD7=%02X"%(T,nm,mm.cpu.rd8(0xE88),r(0x134),r(0x138),r(0x298),r(0x26E),mm.cpu.rd8(0x32C),mm.cpu.rd8(0xBD7)), "cmds:",[("%04X"%c,"%04X"%x) for tt,c,x in mm.cmd_log16 if tt>T*fs-4*fs][-4:])
