"""line fidelity in data mode: correlate the last N DAC samples of one modem with what the other modem's ADC consumed (rx_log), both directions. usage: linkfid.py T1 [N]"""
import os, sys, math; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
T1=float(sys.argv[1]); N=int(sys.argv[2]) if len(sys.argv)>2 else 3000; L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles
while (L.a.cpu.cycles-base)/CPU_HZ<T1: L.run(CPU_HZ//4)
sg=lambda v: v-65536 if v>=32768 else v
def analyse(src,dst,name):
    tx=[sg(v&0xFFFF) for v in src.tx_all]; rx=[sg(v) for v in dst.rx_log]
    seg=rx[-N:]; best=None
    for lag in range(0,3000):
        # rx[-N:] corresponds to tx[len(tx)-lag-N : len(tx)-lag]
        a=len(tx)-lag-N
        if a<0: break
        t=tx[a:a+N]
        num=sum(x*y for x,y in zip(t,seg)); den=math.sqrt(sum(x*x for x in t)*sum(y*y for y in seg)) or 1
        c=num/den
        if best is None or c>best[0]: best=(c,lag,num/(sum(x*x for x in t) or 1))
    print('%s: tx %d rx %d samples; best corr %.4f at lag %d samples, gain %.3f; rx rms %.0f tx rms %.0f'%(name,len(tx),len(rx),best[0],best[1],best[2],math.sqrt(sum(y*y for y in seg)/N),math.sqrt(sum(x*x for x in tx[-N:])/N)))
analyse(L.a,L.b,'A DAC -> B ADC'); analyse(L.b,L.a,'B DAC -> A ADC')
print('underruns A',L.a.rx_under,'B',L.b.rx_under,' rates',L.a.rate,L.b.rate)
