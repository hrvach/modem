import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
from machine import CPU_HZ
fs=7200; dur=float(sys.argv[1])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
last={}
t=0
while L.samples() < int(dur*fs):
    L.run(CPU_HZ//20); t+=0.05
    for nm,mm in (('A',L.a),('B',L.b)):
        d=mm.dsp; st=(d.dm[0x39A],d.dm[0x39B])
        if st!=last.get(nm): print("t=%6.2f %s tasks 1A=%04X 1B=%04X nmsg=%d ovl=%s"%(t,nm,st[0],st[1],len(mm.msg_log),[hex(a) for _,a,_ in mm.ovl_loads][-1:])); last[nm]=st
