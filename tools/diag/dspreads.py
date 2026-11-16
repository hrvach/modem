"""what does the DSP read from its host-window ports 0x56..0x5F in the window (value histogram per port) and what does it write back? usage: dspreads.py T0 T1 (CPU_SCALE, LINK_SLICE env)"""
import os, sys, collections; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
base=[0]; T=lambda m:(m.cpu.cycles-base[0])/CPU_HZ
DW={'A':[],'B':[]}; R={'A':collections.Counter(),'B':collections.Counter()}; W={'A':collections.Counter(),'B':collections.Counter()}
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
for nm,m in (('A',L.a),('B',L.b)):
    ro,wo=m.dsp_rd,m.dsp_wr
    def mk(nm,m,ro,wo):
        def rd(p):
            v=ro(p)
            if 0x50<=(p&0xFF)<=0x5F and T0<=T(m)<=T1: R[nm][('%02X'%(p&0xFF),'%04X'%(v&0xFFFF),'pc%04X'%m.dsp.get('PC'))]+=1
            return v
        def wr(p,v):
            if 0x50<=(p&0xFF)<=0x5F and T0<=T(m)<=T1: W[nm][('%02X'%(p&0xFF),'%04X'%(v&0xFFFF))]+=1
            if (p&0xFF)==0x60 and T0<=T(m)<=T1: DW[nm].append((round(T(m),3),v&0xFFFF))
            return wo(p,v)
        return rd,wr
    rd,wr=mk(nm,m,ro,wo); m.dsp.set_io(rd,wr)
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); base[0]=L.a.cpu.cycles
while T(L.a)<T1: L.run(CPU_HZ//64)
for nm in 'AB':
    print(nm,'DSP reads %d-%d s:'%(T0,T1),R[nm].most_common(8))
    print(nm,'DSP writes (non-flag ports):',[(k,v) for k,v in W[nm].most_common(60) if k[0] not in ('56',)][:30])
for nm in 'AB':
    ws=DW[nm]; print(nm,'port 0x60 data words:',len(ws),'first',[('%.2f'%t,'%04X'%v) for t,v in ws[:12]],'... ascii run:',''.join(chr(v&0xFF) if 32<=(v&0xFF)<127 else '.' for t,v in ws[:200]))
