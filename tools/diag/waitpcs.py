"""what do the DSPs execute while a start-up phase is waiting? clear the PC hit counters at T0, run to T1, print the hottest DSP PCs per modem plus [0x6F]/[0x3CB].
usage: waitpcs.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; t0=float(sys.argv[1]); t1=float(sys.argv[2])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(t0*fs): L.run(CPU_HZ//8)
for m in (L.a,L.b): m.dsp.pc_hits_clear()
while L.samples() < int(t1*fs): L.run(CPU_HZ//8)
for nm,m in (('A',L.a),('B',L.b)):
    d=m.dsp; h=[(d.pc_hits(pc),pc) for pc in range(0x0000,0x10000) if d.pc_hits(pc)]
    tot=sum(n for n,_ in h)
    print(nm,'[6F]=%04X [3CB]=%04X total=%d distinct=%d'%(d.dm[0x6F],d.dm[0x3CB],tot,len(h)))
    h.sort(reverse=True)
    print(nm,'top:',' '.join('%04X:%d'%(pc,n) for n,pc in h[:60]),flush=True)
    rng=sorted(pc for n,pc in h)
    # contiguous ranges
    out=[];s=rng[0];p=s
    for x in rng[1:]:
        if x>p+8: out.append((s,p)); s=x
        p=x
    out.append((s,p)); print(nm,'ranges:',' '.join('%04X-%04X'%r for r in out))
