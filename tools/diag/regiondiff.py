"""find the table that collapses between two training attempts: snapshot data 0x60..0xBFF of modem WHO every STEP s, then report 164-word windows that are nearly full early and nearly empty later. usage: regiondiff.py WHO T0 T1 STEP"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
who=sys.argv[1]; T0=float(sys.argv[2]); T1=float(sys.argv[3]); STEP=float(sys.argv[4]); LO,HI=0x60,0xC00
L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
tgt=L.a if who=='A' else L.b; base=tgt.cpu.cycles; d=tgt.dsp; snaps=[]; nxt=T0
while (tgt.cpu.cycles-base) < T1*CPU_HZ:
    L.run(max(1,int(CPU_HZ*STEP/2))); t=(tgt.cpu.cycles-base)/CPU_HZ
    if t>=nxt: snaps.append((t,[d.dm[a] for a in range(LO,HI)],d.get('PC'))); nxt+=STEP
W=164; n=HI-LO; ts=[s[0] for s in snaps]
def nzs(s,a): return sum(1 for v in s[a:a+W] if v)
best=[]
for a in range(0,n-W):
    series=[nzs(s[1],a) for s in snaps]
    early=[x for t,x in zip(ts,series) if t<20.9]; late=[x for t,x in zip(ts,series) if t>21.6]
    if early and late and max(early)>=100 and min(late)<=max(early)*0.5: best.append((max(early)-min(late),a+LO,series))
best.sort(reverse=True)
print('snapshots',len(snaps),'t %.2f..%.2f'%(ts[0],ts[-1]))
seen=[]
for drop,a,series in best[:12]:
    if any(abs(a-b)<40 for b in seen): continue
    seen.append(a); print('window %04X..%04X  early max %d -> late min %d'%(a,a+W-1,max(x for t,x in zip(ts,series) if t<20.9),min(x for t,x in zip(ts,series) if t>21.6)))
    print('   nonzero count over time:',' '.join('%.1f:%d'%(t,x) for t,x in zip(ts,series)))
