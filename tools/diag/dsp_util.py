"""DSP utilisation: fraction of DSP cycles spent in IDLE per 2 s window of call time, per modem (idle_cycles / total_cycles deltas), plus the codec rate. usage: dsp_util.py T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; t1=float(sys.argv[1]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
prev={k:(m.dsp.idle_cycles(),m.dsp.total_cycles()) for k,m in (('A',L.a),('B',L.b))}; w=0
while L.samples() < int(t1*fs):
    L.run(CPU_HZ//8); t=L.samples()/fs
    if int(t/2)>w:
        w=int(t/2); out=[]
        for k,m in (('A',L.a),('B',L.b)):
            i,tt=m.dsp.idle_cycles(),m.dsp.total_cycles(); di=i-prev[k][0]; dt=tt-prev[k][1]; prev[k]=(i,tt)
            out.append('%s busy %.0f%% (rate %d, %d cycles/sample budget)'%(k,100*(1-di/max(dt,1)),m.rate,m.dsp_cps))
        print('t<%2d: '%(w*2),' | '.join(out),flush=True)
