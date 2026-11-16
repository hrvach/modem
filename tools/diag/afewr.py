"""who writes the AFE config words (DSP ports 0x68/0x69/0x6B/0x6C)? print writer PC, value, call-time per modem. usage: afewr.py T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
import machine as _M
fs=7200; t1=float(sys.argv[1]); cur={'t':0.0}; LOG=[]
_w=_M.Machine.dsp_wr
def w(self,p,v):
    q=p&0xFF
    if q in (0x68,0x69,0x6B,0x6C): LOG.append((cur['t'],'A' if self is L.a else 'B',q,v&0xFFFF,self.dsp.get('PC'),[hex(x) for x in self.dsp.recent_pcs(6)]))
    return _w(self,p,v)
_M.Machine.dsp_wr=w
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(t1*fs):
    L.run(CPU_HZ//32); cur['t']=L.samples()/fs
for t,nm,q,v,pc,rp in LOG:
    if t>=10: print('%6.2f %s port %02X <- %04X  pc=%04X recent=%s'%(t,nm,q,v,pc,' '.join(rp)))
