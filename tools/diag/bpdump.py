"""run to T, then break the DSP of A|B at PC the first N times; dump registers, ST0 DP and data words around AR1 plus a data window. usage: bpdump.py T A|B PC N [lo hi]"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
import machine as _M
fs=7200; T=float(sys.argv[1]); who=sys.argv[2]; pc=int(sys.argv[3],16); N=int(sys.argv[4])
lo=int(sys.argv[5],16) if len(sys.argv)>5 else None; hi=int(sys.argv[6],16) if len(sys.argv)>6 else None
L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(T*fs): L.run(CPU_HZ//16)
mach=(L.a if who=='A' else L.b); d=mach.dsp; d.bp(pc); hits=[0]
orig=_M.Machine._sample
def s(self):
    r=orig(self)
    if self is mach and d.get('PC')==pc and hits[0]<N:
        hits[0]+=1; ar=d.get('AR1'); st0=d.get('ST0')
        print('hit',hits[0],'PC=%04X ACC=%08X ST0=%04X DP=%d AR1=%04X AR0=%04X TC=?'%(pc,d.get('ACC'),st0,st0&0x1FF,ar,d.get('AR0')))
        print('  words at AR1-8..AR1+2:',' '.join('%04X'%d.dm[(ar+i)&0xFFFF] for i in range(-8,3)))
        if lo is not None: print('  dm[%X..%X]:'%(lo,hi),' '.join('%04X'%d.dm[a] for a in range(lo,hi+1)))
    return r
_M.Machine._sample=s
while hits[0]<N and L.samples() < int((T+3)*fs): L.run(CPU_HZ//64)
