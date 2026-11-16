"""per-frame exit-test values at 9F6C for B around A's S burst: E1',E2', pass/fail, counter. usage: frames9f6c.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
import machine as _M
dump=[]; fs=7200; T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=float(os.environ.get('GAIN','0.5')); rec=[]
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
tgt=L.b; d=tgt.dsp; d.bp(0x9F6C); orig=_M.Machine._sample
def s(self):
    r=orig(self)
    if self is tgt and d.get("PC")==0x9F6C and T0<=L.samples()/fs<=T1:
        dm=d.dm; rec.append((L.samples()/fs,list(dm[0x300:0x304]),list(dm[0x330:0x334]),dm[0x334])); dump.append(list(dm[0x380:0x400]))
    return r
_M.Machine._sample=s
while L.samples()<int((T1+0.05)*fs): L.run(CPU_HZ//32)
sg=lambda v: v-65536 if v>=32768 else v
K=-24150016; LO=0x06670000; HI=LO+0x13320000
for t,a,b,c in rec:
    a=[sg(v) for v in a]; b=[sg(v) for v in b]
    s7d=(a[0]+a[3]+b[0]+b[3])>>2; s7e=(a[2]-a[1]+b[2]-b[1])>>2; s7c=(a[2]+a[1]+b[2]+b[1])>>2; s7f=(a[3]-a[0]-b[0]+b[3])>>2
    e1=K+2*(s7c*s7c+s7f*s7f); e2=K+2*(s7d*s7d+s7e*s7e)
    ok=(e1<0)!=(e2<0) and LO<(e2 if e1<0 else e1)<HI
    print('%.4f ctr=%s %s E1=%d E2=%d a=%s'%(t,c,'PASS' if ok else 'fail',e1,e2,a))

import sys as _s
if len(_s.argv)>3:
    print('cells that change between frames, first 16 frames (addr: values as signed):')
    for c in range(0x80):
        v=[sg(dump[i][c]) for i in range(min(16,len(dump)))]
        if len(set(v))>1: print('%03X'%(0x380+c),v)
