import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
from machine import CPU_HZ
fs=7200; dur=float(sys.argv[1])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
last={}; t=0
while L.samples() < int(dur*fs):
    L.run(CPU_HZ//50); t=L.samples()/fs
    for nm,m in (('A',L.a),('B',L.b)):
        c=m.cpu; st=(c.rd16(0x298),c.rd8(0x32B),c.rd8(0x32C),c.rd16(0x30),c.rd16(0x138))
        if st!=last.get(nm): print("t=%6.2f %s h298=%04X 32B=%02X 32C=%02X h30=%04X h138=%04X"%(t,nm,*st)); last[nm]=st
