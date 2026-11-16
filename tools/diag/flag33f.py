"""poll host RAM [0x33F] (selects TX word high byte 0x40 vs 0x20 in the generator at 0x9058A), [0x32B], [0x3D3] over time on both hosts. usage: flag33f.py T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
T1=float(sys.argv[1]); L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda m:(m.cpu.cycles-base)/CPU_HZ
last={}
while T(L.a)<T1:
    L.run(CPU_HZ//4)
    row=[]
    for nm,m in (('A',L.a),('B',L.b)):
        v=(m.cpu.rd8(0x33F),m.cpu.rd8(0x32B),m.cpu.rd8(0x3D3))
        if last.get(nm)!=v: row.append('%s [33F]=%02X [32B]=%02X [3D3]=%02X'%(nm,*v)); last[nm]=v
    if row: print('%.2f  %s'%(T(L.a),'   '.join(row)),flush=True)
