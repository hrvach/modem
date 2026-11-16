"""dump the receive filter / equalizer coefficient table (data 0x12A-0x1CD) of both DSPs at time T and compare. usage: eqdump.py T [T2]"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
Ts=[float(x) for x in sys.argv[1:]]; L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda: (L.a.cpu.cycles-base)/CPU_HZ
sg=lambda v: v-65536 if v>=32768 else v
for t in Ts:
    while T()<t: L.run(CPU_HZ//32)
    for nm,m in (('A',L.a),('B',L.b)):
        tab=[sg(m.dsp.dm[a]) for a in range(0x12A,0x1CE)]
        nz=[(0x12A+i,v) for i,v in enumerate(tab) if v]
        e=sum(v*v for v in tab)**0.5
        print('t=%.1f %s table: %d nonzero of %d, |coef| %.0f, max %d at %04X'%(t,nm,len(nz),len(tab),e,max(tab,key=abs),0x12A+max(range(len(tab)),key=lambda i:abs(tab[i]))))
        print('   ',' '.join('%04X:%d'%(a,v) for a,v in nz[:40]))
