"""what does each modem transmit over time? per window: rms and normalised autocorrelation at lags 3, 6 and 144 samples (S/S-bar repeat every 6 samples, PP every 144), next to both DSPs' state callback [6D]/[2F]. usage: sigtype.py T1 STEP (CPU_SCALE, LINK_SLICE env)"""
import os, sys, math; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
T1=float(sys.argv[1]); ST=float(sys.argv[2]); L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda: (L.a.cpu.cycles-base)/CPU_HZ
rows=[]; t=14.0
while T()<14.0: L.run(CPU_HZ//32)
last=(len(L.audio['a']),len(L.audio['b']))
while T()<T1:
    L.run(int(CPU_HZ*ST))
    na,nb=len(L.audio['a']),len(L.audio['b'])
    rows.append((T(),last,(na,nb),(L.a.dsp.dm[0x6D],L.a.dsp.dm[0x32F]),(L.b.dsp.dm[0x6D],L.b.dsp.dm[0x32F]))); last=(na,nb)
sg=lambda v: v-65536 if v>=32768 else v
def feat(x):
    if len(x)<400: return (0,0,0,0)
    x=[sg(v&0xFFFF) for v in x]; e=sum(v*v for v in x) or 1
    ac=lambda k: sum(x[i]*x[i+k] for i in range(len(x)-k))/e
    return (math.sqrt(e/len(x)),ac(3),ac(6),ac(144))
print(' time   A[6D]/[2F]    B[6D]/[2F]     | A tx: rms  ac3   ac6  ac144 | B tx: rms  ac3   ac6  ac144')
for t,(a0,b0),(a1,b1),sa,sb in rows:
    fa=feat(L.audio['a'][a0:a1]); fb=feat(L.audio['b'][b0:b1])
    print('%6.2f  %04X/%04X  %04X/%04X  | %5.0f %5.2f %5.2f %5.2f | %5.0f %5.2f %5.2f %5.2f'%((t,)+sa+sb+fa+fb))
