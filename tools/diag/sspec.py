"""spectrum of a modem's transmitted S burst: take TX samples of A or B between T0 and T1 (call time) from the per-slice chunks, Goertzel scan at the codec rate of that moment. usage: sspec.py WHO T0 T1"""
import os, sys, math; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link_mp import LinkMP
from machine import CPU_HZ
who=sys.argv[1].lower(); T0=float(sys.argv[2]); T1=float(sys.argv[3])
L=LinkMP(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; chunk0=len(L.chunks['a']); L.start_call("1")
L.run(int((T1+0.3)*CPU_HZ))
per=L.slice/CPU_HZ; xs=[]; rate=None
for i,(r,x) in enumerate(L.chunks[who][chunk0:]):
    t=i*per
    if T0<=t<=T1: xs+=x; rate=r
print('%s samples %d at rate %s'%(who.upper(),len(xs),rate))
fs=float(rate)
def g(f):
    k=2*math.cos(2*math.pi*f/fs); a=b=0.0
    for v in xs: c=v+k*a-b; b=a; a=c
    return a*a+b*b-k*a*b
res=sorted(((g(f),f) for f in range(100,int(fs/2),10)),reverse=True)
top=[]
for p,f in res:
    if all(abs(f-q)>60 for q in top): top.append(f)
    if len(top)==6: break
print('strongest spectral lines (Hz):',sorted(top))
print('S expected at carrier +- symbol_rate/2; symbol rate = fs/3 = %.1f Hz -> half = %.1f Hz'%(fs/3,fs/6))
