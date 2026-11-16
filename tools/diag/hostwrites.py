"""what does each host (80186) write to the DSP mailbox ports 0x58..0x5F in the window? histogram of (port, width, value) and writer PCs. usage: hostwrites.py T0 T1 (CPU_SCALE, LINK_SLICE env)"""
import os, sys, collections; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
base=[0]; T=lambda m:(m.cpu.cycles-base[0])/CPU_HZ
H={'A':collections.Counter(),'B':collections.Counter()}; PC={'A':collections.Counter(),'B':collections.Counter()}
for nm,m in (('A',L.a),('B',L.b)):
    o=m.iowr
    def mk(nm,m,o):
        def w(p,wd,v):
            if (0x58<=p<=0x5F or p in (0x18,0x1A,0x1C,0x1E,0x40,0x42,0x44,0x46,0x48,0x4A,0x4C,0x4E)) and T0<=T(m)<=T1: H[nm][('%02X'%p,wd,'%04X'%(v&0xFFFF))]+=1; PC[nm]['%05X'%m.cpu.phys_pc()]+=1
            return o(p,wd,v)
        return w
    m.iowr=mk(nm,m,o); m.cpu.hooks(m.iord,m.iowr,m.mmrd,m.mmwr)
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); base[0]=L.a.cpu.cycles
while T(L.a)<T1: L.run(CPU_HZ//64)
for nm in 'AB':
    print(nm,'mailbox writes %d-%d s: total'%(T0,T1),sum(H[nm].values()))
    print('  top (port,width,value):',H[nm].most_common(10))
    print('  writer PCs:',PC[nm].most_common(6))
