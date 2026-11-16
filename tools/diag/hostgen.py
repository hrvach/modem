"""what word does the host's TX word generator (call *[DS:0x3B5] at 0x93BF8..) return, over time, and where is that function? usage: hostgen.py T0 T1 (CPU_SCALE, LINK_SLICE env)"""
import os, sys, collections; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
base=[0]; T=lambda m:(m.cpu.cycles-base[0])/CPU_HZ
H={'A':collections.Counter(),'B':collections.Counter()}; info={}
for nm,m in (('A',L.a),('B',L.b)):
    o=m.iowr
    def mk(nm,m,o):
        def w(p,wd,v):
            if p==0x48 and m.cpu.phys_pc() in (0x93C19,0x93C1D,0x93C17,0x93C1B) and T0<=T(m)<=T1:
                ax=m.cpu.get('AX'); H[nm]['%04X'%(ax & 0xFFFF)]+=1
                if nm not in info:
                    ds=m.cpu.get('DS'); ptr=m.cpu.rd16((ds<<4)+0x3B5); cs=m.cpu.get('CS')
                    info[nm]=(ds,ptr,cs,bytes(m.cpu.rd8((cs<<4)+ptr+i) for i in range(64)))
            return o(p,wd,v)
        return w
    m.iowr=mk(nm,m,o); m.cpu.hooks(m.iord,m.iowr,m.mmrd,m.mmwr)
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); base[0]=L.a.cpu.cycles
while T(L.a)<T1: L.run(CPU_HZ//64)
for nm in 'AB':
    print(nm,'words from the generator (third word of each group, port 0x48 data):',H[nm].most_common(8))
    if nm in info: ds,ptr,cs,code=info[nm]; print(nm,'DS=%04X [DS:3B5]=%04X CS=%04X code:'%(ds,ptr,cs),code.hex())
