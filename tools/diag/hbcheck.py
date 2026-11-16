"""host heartbeat check: per 1 s of real (CPU-clock) time, the DSP timer expiries and the heartbeat count, with the codec rate. usage: hbcheck.py WHO T1  (env HB_TIMER=0/1)"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
import machine as M
from machine import CPU_HZ
fs=7200; who=sys.argv[1]; t1=float(sys.argv[2]); L=Link(); L.gain=0.5
tgt=L.a if who=='A' else L.b
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
print('HB_TIMER =',M.HB_TIMER,' hb_ticks =',tgt.hb_ticks)
d=tgt.dsp; c0=tgt.cpu.cycles; e0=d.timer_expiries(); h0=tgt.hb_count; w=0; ints=[0]
while tgt.cpu.cycles-c0 < t1*CPU_HZ:
    L.run(CPU_HZ//16); t=(tgt.cpu.cycles-c0)/CPU_HZ
    if int(t)>w:
        e,h=d.timer_expiries(),tgt.hb_count; print('t=%2d s  codec rate %5d  DSP timer expiries/s %5d  heartbeat count/s %5d  PRD %04X'%(int(t),tgt.rate,(e-e0)/(int(t)-w),(h-h0)/(int(t)-w),d.get('PRD'))); e0,h0,w=e,h,int(t)
