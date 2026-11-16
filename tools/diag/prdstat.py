"""statistics of the symbol-timer period chosen by ISR 820C: per modem, per 2 s window, count of PRD=419A vs 41A4 samples (polled every 1/64 s) plus BF5. usage: prdstat.py T1"""
import os, sys, collections; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; t1=float(sys.argv[1]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
cnt={'A':collections.Counter(),'B':collections.Counter()}; w=0
while L.samples() < int(t1*fs):
    L.run(CPU_HZ//64); t=L.samples()/fs
    for nm,m in (('A',L.a),('B',L.b)): cnt[nm][m.dsp.get('PRD')]+=1
    if int(t/4)>w:
        w=int(t/4); print('t<%d: '%(w*4),' | '.join('%s %s'%(nm,{('%04X'%k):v for k,v in cnt[nm].items()}) for nm in 'AB'),flush=True); cnt={'A':collections.Counter(),'B':collections.Counter()}
