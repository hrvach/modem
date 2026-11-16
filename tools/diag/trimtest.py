"""diagnostic only: shorten B's 9D88->9DCF countdown [0x31A] by TRIM symbols (set at 9D93) and see whether the exit test reaches 20 and whether a retrain follows. usage: trimtest.py T1 (TRIM, GAIN, LINK_SLICE, DELAY_SAMPLES env)"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
T1=float(sys.argv[1]); TRIM=int(os.environ.get('TRIM','0')); L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda m:(m.cpu.cycles-base)/CPU_HZ
tgt=L.b; d=tgt.dsp; d.bp(0x9D93); d.bp(0x9F33); mx=[0,0.0]; trims=[]
o_s=_M.Machine._sample
def s(self):
    r=o_s(self)
    if self is tgt:
        pc=d.get('PC')
        if pc==0x9D93 and TRIM and T(self)>14.5: d.dm[0x31A]=(d.dm[0x31A]-TRIM)&0xFFFF; trims.append(round(T(self),3))
        if pc==0x9F33 and d.dm[0x334]>mx[0]: mx[0]=d.dm[0x334]; mx[1]=T(self)
    return r
_M.Machine._sample=s
while T(L.a)<T1: L.run(CPU_HZ//64)
print('TRIM',TRIM,'trimmed at',trims,'| max exit-test counter',mx[0],'at %.3f'%mx[1])
for nm,m in (('A',L.a),('B',L.b)):
    print(nm,'rate changes:',' '.join('%.2f:%d'%(t-base/CPU_HZ,r) for t,r in m.rate_log if t-base/CPU_HZ>12))
