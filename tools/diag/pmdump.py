"""dump live DSP program memory words [LO..HI] of A|B at call time T and report which loaded image (base/ov6/ov7/ov8) each matches. usage: pmdump.py WHO T LO HI"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; who=sys.argv[1]; T=float(sys.argv[2]); lo=int(sys.argv[3],16); hi=int(sys.argv[4],16)
L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(T*fs): L.run(CPU_HZ//16)
d=(L.a if who=='A' else L.b).dsp
imgs={"base":(0x8000,"dsp/dsp_base.bin"),"ov6":(0x9D00,"dsp/dsp_ov6.bin"),"ov7":(0xB000,"dsp/dsp_ov7.bin"),"ov8":(0xDC00,"dsp/dsp_ov8.bin")}
W={}
for k,(b,f) in imgs.items():
    x=open(os.path.join(ROOT,f),'rb').read(); W[k]=(b,[x[2*i]|(x[2*i+1]<<8) for i in range(len(x)//2)])
live=[d.pm[a] for a in range(lo,hi+1)]
print('live pm[%04X..%04X]:'%(lo,hi),' '.join('%04X'%v for v in live))
for k,(b,w) in W.items():
    eq=sum(1 for i,a in enumerate(range(lo,hi+1)) if 0<=a-b<len(w) and w[a-b]==live[i])
    print('  matches %s image: %d / %d words'%(k,eq,len(live)))
print('DM [0x3F6],[0x3F7] now: %04X %04X ; [0x3BC]=%04X [0x3A1]=%04X [0x3A0]=%04X'%(d.dm[0x3F6],d.dm[0x3F7],d.dm[0x3BC],d.dm[0x3A1],d.dm[0x3A0]))
