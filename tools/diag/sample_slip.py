"""count codec ticks vs input samples actually consumed (rx_log) and underruns per modem over windows: any difference is a sample slip inserted by the emulator. usage: sample_slip.py T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link_mp import LinkMP
from machine import CPU_HZ
fs=7200; t1=float(sys.argv[1]); L=LinkMP(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
prev={}; t=0.0
while t<t1:
    L.run(CPU_HZ//2); t+=0.5
    for nm,m in (('A',L.a),('B',L.b)):
        v=m.eval('[m.hb_count,len(m.rx_log),m.rx_under,len(m.rxbuf),m.dsp.dxr_head()]')
        if nm in prev:
            p=prev[nm]; print('%5.1f %s ticks %6d  rx consumed %6d  (diff %+d)  underruns +%d  rxbuf %d  dxr writes %d'%(t,nm,v[0]-p[0],v[1]-p[1],(v[1]-p[1])-(v[0]-p[0]),v[2]-p[2],v[3],v[4]-p[4]))
        prev[nm]=v
