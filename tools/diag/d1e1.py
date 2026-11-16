"""trace the base-image data-mode state machine at D1E1 (types 0x12-0x15) on both DSPs: hit counts, first times and the cells it tests ([0x330] bit 2 at D223, [0x333..0x339]). usage: d1e1.py T0 T1"""
import os, sys, collections; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda m:(m.cpu.cycles-base)/CPU_HZ
PCS={0xD1E1:'enter',0xD1D6:'D1D6',0xD1D9:'D1D9',0xD201:'sendX12',0xD217:'sendX13',0xD223:'gate(bit13,[30])',0xD229:'sendX14',0xD251:'sendX15',0xD262:'sendX14b',0xD1CB:'D1CB',0xD204:'D204',0xD209:'D209',0xD230:'D230',0xD256:'D256',0xD25B:'D25B'}
for m in (L.a,L.b):
    for p in PCS: m.dsp.bp(p)
cnt={'A':collections.Counter(),'B':collections.Counter()}; first={'A':{},'B':{}}; snap={'A':{},'B':{}}
o_s=_M.Machine._sample
def s(self):
    r=o_s(self); d=self.dsp; pc=d.get('PC'); nm='A' if self is L.a else 'B'
    if pc in PCS and T0<=T(self)<=T1:
        cnt[nm][pc]+=1
        if pc not in first[nm]:
            first[nm][pc]=T(self); snap[nm][pc]=[d.dm[0x300+i] for i in (0x30,0x33,0x34,0x35,0x36,0x37,0x39,0x3B,0x3F)]
    return r
_M.Machine._sample=s
while T(L.a)<T1: L.run(CPU_HZ//64)
for nm in 'AB':
    print('== DSP',nm)
    for pc,name in PCS.items():
        if cnt[nm][pc]: print('  %04X %-18s hits %6d first %.3f  [330,333,334,335,336,337,339,33B,33F]=%s'%(pc,name,cnt[nm][pc],first[nm][pc],' '.join('%04X'%v for v in snap[nm][pc])))
        else: print('  %04X %-18s never'%(pc,name))
    print('  final cells [330,333..33F]:',' '.join('%04X'%getattr(L.a if nm=="A" else L.b,'dsp').dm[0x300+i] for i in (0x30,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x3B,0x3F)))
