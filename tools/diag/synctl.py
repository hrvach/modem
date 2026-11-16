"""timeline of B's receiver stage: stage entry ([6F]=0AC0 at 9DFD), first S energy at the exit-test frames (9F6C), first A12B step (writes [34B]) and the value it leaves. usage: synctl.py T0 T1 (DELAY_SAMPLES env)"""
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
tgt=L.b; d=tgt.dsp; PCS=(0x9DFD,0xA12B,0x9F6C,0x9F33); [d.bp(p) for p in PCS]
ev={'entry':None,'S':None,'A12B':None,'after':None,'frames':0,'f_at_A12B':None}; sg=lambda v: v-65536 if v>=32768 else v
orig=_M.Machine._sample
def s(self):
    r=orig(self)
    if self is tgt and T0<=L.samples()/fs<=T1:
        pc=d.get("PC"); t=L.samples()/fs
        if pc==0x9DFD and d.dm[0x6F]==0x0AC0: ev['entry']=t; ev['S']=None; ev['frames']=0
        elif pc==0x9F6C:
            ev['frames']+=1
            if ev['S'] is None and max(abs(sg(d.dm[0x300+i])) for i in range(4))>5000: ev['S']=(t,ev['frames'])
        elif pc==0xA12B and ev['A12B'] is None: ev['A12B']=(t,ev['frames']); ev['arm']=d.dm[0x34B]
        elif pc==0x9F33 and ev['A12B'] and ev['after'] is None: ev['after']=(t,d.dm[0x34B])
    return r
_M.Machine._sample=s
while L.samples()<int((T1+0.02)*fs): L.run(CPU_HZ//32)
S=ev['S']; A=ev['A12B']; E=ev['entry']
print('entry %s | S arrives %s | A12B %s (frame#%s) | [34B] before %s, next %s'%('%.4f'%E if E else None, '%.4f frame#%d'%S if S else None, '%.4f'%A[0] if A else None, A[1] if A else None, hex(ev.get('arm',0)), ('%04X'%ev['after'][1]) if ev['after'] else None))
