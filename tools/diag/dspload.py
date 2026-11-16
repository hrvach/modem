"""DSP real-time load: per codec tick, DSP cycles available vs idle cycles (IDLE instruction), and how often the previous serial interrupt was still pending (IFR RINT/XINT set when the next frame arrives = a missed deadline). usage: dspload.py T0 T1 (CYC_MODEL env selects the DSP cycle model)"""
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
st={'A':None,'B':None}; acc={'A':collections.Counter(),'B':collections.Counter()}; per={'A':[],'B':[]}
o_s=_M.Machine._sample
def s(self):
    nm='A' if self is L.a else 'B'; d=self.dsp
    if T0<=T(self)<=T1:
        tc=d.total_cycles(); ic=d.idle_cycles(); ifr=d.get('IFR')
        p=st[nm]
        if p is not None:
            dt=tc-p[0]; di=ic-p[1]; acc[nm]['ticks']+=1; acc[nm]['cyc']+=dt; acc[nm]['idle']+=di
            if ifr & 0x30: acc[nm]['pending']+=1              # RINT (0x10) / XINT (0x20) still pending when the next frame arrives
            per[nm].append(dt-di)
        st[nm]=(tc,ic)
    return o_s(self)
_M.Machine._sample=s
while T(L.a)<T1: L.run(CPU_HZ//64)
print('DSP cycle model CYC_MODEL=%s, window %.1f-%.1f s'%(os.environ.get('CYC_MODEL','1'),T0,T1))
for nm in 'AB':
    a=acc[nm]; n=max(1,a['ticks']); b=per[nm]
    # per symbol (3 ticks) busy cycles, worst case over the window
    sym=[sum(b[i:i+3]) for i in range(0,len(b)-2,3)]
    print('  DSP %s: %d ticks, %.0f cycles/tick available, busy %.1f%% (idle %.1f%%), pending serial IRQ at tick: %d (%.2f%%), busiest symbol %d of %d cycles (%.1f%%)'%(nm,a['ticks'],a['cyc']/n,100*(1-a['idle']/max(1,a['cyc'])),100*a['idle']/max(1,a['cyc']),a['pending'],100*a['pending']/n,max(sym) if sym else 0,int(3*a['cyc']/n),100*(max(sym) if sym else 0)/(3*a['cyc']/n)))
