"""does the DSP of modem WHO miss a frame (a codec tick without a DXR write / without an XINT ISR run) near T? prints (ticks - dxr_writes) and (ticks - xint_isr_hits) every 5 ms and every change. usage: slipwatch.py WHO T0 T1 [ISR_PC_HEX]"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
who=sys.argv[1]; T0=float(sys.argv[2]); T1=float(sys.argv[3]); isr=int(sys.argv[4],16) if len(sys.argv)>4 else 0x8189
L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
m=L.a if who=='A' else L.b; base=m.cpu.cycles; d=m.dsp; ticks=[0]; ot=d.serial_tick
def tick(v): ticks[0]+=1; ot(v)
d.serial_tick=tick; last=None; n=0
print('t      rate  ticks  dxr_head  isr_hits   ticks-dxr  ticks-isr')
while (m.cpu.cycles-base) < T1*CPU_HZ:
    L.run(CPU_HZ//400); t=(m.cpu.cycles-base)/CPU_HZ
    if t>=T0:
        dx=d.dxr_head(); ih=d.pc_hits(isr); st=(ticks[0]-dx,ticks[0]-ih)
        if last is None or st!=last or n%40==0: print('%.4f %5d %6d %8d %9d   %6d    %6d'%(t,m.rate,ticks[0],dx,ih,st[0],st[1]))
        last=st; n+=1
