"""who re-enters the acquisition stage setup (ov6 9DF1/9E24) mid-S? print PC history at each hit in the window. usage: stagere.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
fs=7200; T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=0.5
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
tgt=L.b; d=tgt.dsp; PCS=(0xA12B,0xA135,0x9F33,0x9DFD,0x9E13,0x9E00); f6f=[None]; F6F=os.environ.get('FORCE6F')=='1'; mx=[0]; FORCE=os.environ.get('FORCE0')=='1'; [d.bp(p) for p in PCS]; last=[0]
def comp(h):
    o=[];i=0
    while i<len(h):
        j=i
        while j+1<len(h) and h[j+1]==h[j]+1: j+=1
        o.append('%04X-%04X'%(h[i],h[j]) if j>i else '%04X'%h[i]); i=j+1
    return ' '.join(o)
orig=_M.Machine._sample; n=[0]
def s(self):
    r=orig(self)
    if self is tgt and T0<=L.samples()/fs<=T1:
        pc=d.get("PC")
        if pc==0x9DFD and F6F: f6f[0]=d.dm[0x6F]; d.dm[0x6F]=f6f[0]&~0x800; print('  [6F] %04X -> %04X at entry'%(f6f[0],d.dm[0x6F]))
        if pc in (0x9E13,0x9E00) and F6F and f6f[0] is not None: d.dm[0x6F]=f6f[0]; f6f[0]=None; print('  [6F] restored, table', 'A068' if pc==0x9E13 else 'A086')
        if pc==0x9F33:
            mx[0]=max(mx[0],d.dm[0x334])
            v=d.dm[0x34B]
            if FORCE and last[0]>=1 and last[0]<0x30 and v!=last[0]-1 and v!=last[0]: d.dm[0x34B]=last[0]-1; v=last[0]-1; print('  restored [34B] at t=%.4f'%(L.samples()/fs))
            if v<=1 and last[0]>=3 and last[0]!=0x30: print('SLIP 9F33 t=%.4f [34B] %04X -> %04X [2F]=%04X'%(L.samples()/fs,last[0],v,d.dm[0x32F]))
            last[0]=v
        elif pc in PCS and n[0]<12:
            n[0]+=1; h=d.recent_pcs(400)
            print('t=%.4f hit %04X  [6D]=%04X [2F]=%04X [4B]=%04X [6F]=%04X'%(L.samples()/fs,pc,d.dm[0x6D],d.dm[0x32F],d.dm[0x34B],d.dm[0x6F]))
            print('   ACC=%08X'%d.get('ACC'))
    return r
_M.Machine._sample=s
while L.samples()<int((T1+0.02)*fs): L.run(CPU_HZ//32)
print('hits',n[0],'max pass counter [0x334] =',mx[0],'FORCE0' if FORCE else '')
