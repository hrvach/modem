"""does the firmware reprogram the DSP timer (PRD/TDDR) when the codec rate changes? polls PRD/TIM period and logs changes with the rate. usage: prdwatch.py WHO T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; who=sys.argv[1]; t1=float(sys.argv[2]); L=Link(); L.gain=0.5
tgt=L.a if who=='A' else L.b
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
d=tgt.dsp; last=None
while L.samples() < int(t1*fs):
    L.run(CPU_HZ//64)
    v=(tgt.rate, d.get('PRD'), d.mmr_val(0x26) if hasattr(d,'mmr_val') else 0, d.get('IMR'))
    if v[:2]!=(last or (None,None))[:2]: print('t=%.2f rate=%d PRD=%04X (%d cycles/tick) TCR-view=%04X IMR=%04X'%(L.samples()/fs, v[0], v[1], v[1]+1, v[2], v[3]), flush=True)
    last=v
