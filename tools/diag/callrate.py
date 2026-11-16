"""how often does the receive filter A2A7 (and the other per-sample routines) run per codec sample? pc_hits deltas vs codec ticks per modem over windows. usage: callrate.py T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; t1=float(sys.argv[1]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
PCS={'A2A7 resampler':0xA2A7,'8837 agc':0x8837,'9E6B accum':0x9E6B,'9F6C frame test':0x9F6C,'81B7 RINT isr':0x81B7,'8189 XINT isr':0x8189,'820C TINT isr':0x820C}
prev={}
def snap(): return {k:{n:m.dsp.pc_hits(pc) for n,pc in PCS.items()} | {'ticks':m.hb_count} for k,m in (('A',L.a),('B',L.b))}
w=0; prev=snap()
while L.samples() < int(t1*fs):
    L.run(CPU_HZ//8); t=L.samples()/fs
    if int(t/2)>w:
        w=int(t/2); cur=snap()
        for k in 'AB':
            dt=cur[k]['ticks']-prev[k]['ticks']
            print('t<%2d %s ticks=%5d  '%(w*2,k,dt)+'  '.join('%s %.2f'%(n.split()[0],(cur[k][n]-prev[k][n])/max(dt,1)) for n in PCS),flush=True)
        prev=cur
