"""filter coefficient table across training attempts: snapshots of the working region and its source, plus the init routine A0DE entry state. usage: tablewatch.py WHO T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
who=sys.argv[1]; T0=float(sys.argv[2]); T1=float(sys.argv[3]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
tgt=L.a if who=='A' else L.b; base=tgt.cpu.cycles; d=tgt.dsp; d.bp(0xA0DE); orig=_M.Machine._sample; calls=[]
def stat(lo,hi):
    v=[d.dm[a] for a in range(lo,hi)]; nz=[x for x in v if x]; return len(nz), len(set(nz)), (max(set(nz),key=nz.count) if nz else 0)
def s(self):
    r=orig(self)
    if self is tgt and d.get('PC')==0xA0DE:
        t=(tgt.cpu.cycles-base)/CPU_HZ
        calls.append('A0DE entry t=%.3f INDX=%04X AR0=%04X ARCR=%04X PMST=%04X (NDX=%d OVLY=%d RAM=%d) work nz/distinct %s src nz/distinct %s'%(t,d.get('INDX'),d.get('AR0'),d.get('ARCR'),d.get('PMST'),(d.get('PMST')>>2)&1,(d.get('PMST')>>5)&1,(d.get('PMST')>>4)&1,stat(0x12A,0x1CE)[:2],stat(0x800,0x880)[:2]))
    return r
_M.Machine._sample=s; last=None
while (tgt.cpu.cycles-base) < T1*CPU_HZ:
    L.run(CPU_HZ//50); t=(tgt.cpu.cycles-base)/CPU_HZ
    if t>=T0:
        st=(stat(0x12A,0x1CE),stat(0x800,0x880))
        if st!=last: print('t=%.3f  work[12A..1CD] nz=%3d distinct=%3d mode=%04X | src[800..87F] nz=%3d distinct=%3d mode=%04X  OVLY=%d'%(t,st[0][0],st[0][1],st[0][2],st[1][0],st[1][1],st[1][2],(d.get('PMST')>>5)&1),flush=True)
        last=st
print('\n'.join(calls))
