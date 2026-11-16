"""which DSP data cells change at the short (3-tick) frame? snapshot data 0x60..0x4FF at every 9F6C frame of modem B between T0 and T1, then show, for cells whose value differs at the slip frame, their values over the neighbouring frames. usage: slipcells.py T0 T1   (run with DELAY_SAMPLES=140)"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as _M
from machine import CPU_HZ
fs=7200; T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=0.5; rec=[]; LO,HI=0x60,0x500
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
tgt=L.b; d=tgt.dsp; d.bp(0x9F6C); ticks=[0]; ot=d.serial_tick
def tick(v): ticks[0]+=1; ot(v)
d.serial_tick=tick; orig=_M.Machine._sample
def s(self):
    r=orig(self)
    if self is tgt and d.get("PC")==0x9F6C and T0<=L.samples()/fs<=T1: rec.append((ticks[0],[d.dm[a] for a in range(LO,HI)],d.get('PRD')))
    return r
_M.Machine._sample=s
while L.samples()<int((T1+0.05)*fs): L.run(CPU_HZ//32)
gaps=[rec[i][0]-rec[i-1][0] for i in range(1,len(rec))]
k=next((i+1 for i,g in enumerate(gaps) if g!=6),None)
print('frames',len(rec),'tick gaps',gaps[:40],' short frame index',k)
if k is None: sys.exit()
sg=lambda v: v-65536 if v>=32768 else v
rows=[]
for a in range(HI-LO):
    seq=[rec[i][1][a] for i in range(k-3,min(len(rec),k+3))]
    prev=[rec[i][1][a] for i in range(k-3,k)]
    if rec[k][1][a]!=rec[k-1][1][a] and len(set(prev))==1: rows.append((LO+a,seq))
print('cells constant over 3 frames before the slip frame but changed AT it (value per frame k-3..k+2):')
for a,seq in rows[:60]: print('  [%03X]'%a,' '.join('%04X'%v for v in seq))
print('PRD at frames k-2..k+1:',[hex(rec[i][2]) for i in range(k-2,k+2)])
# cells that advance by a constant step per frame (k-4..k-1) and break the step at k
print('cells with constant non-zero per-frame step before the slip frame, step differs at it (step k-3..k-1 | step at k, k+1):')
n=0
for a in range(HI-LO):
    v=[rec[i][1][a] for i in range(k-4,k+3)]
    st=[(v[i+1]-v[i])&0xFFFF for i in range(len(v)-1)]
    if st[0]==st[1]==st[2] and st[0]!=0 and st[3]!=st[2]:
        print('  [%03X] %04X..%04X step %04X | at slip %04X, next %04X'%(LO+a,v[0],v[3],st[2],st[3],st[4])); n+=1
        if n>40: break
