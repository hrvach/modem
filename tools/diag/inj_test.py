"""inject an ideal S sequence into A's receiver and watch the exit-test counters [0x334] (consecutive passes, needs 20) and [0x336] and the DSP messages. usage: inj_test.py T0 T1 (env INJECT_A, DELAY_SAMPLES)"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link_mp import LinkMP
from machine import CPU_HZ
t0=float(sys.argv[1]); t1=float(sys.argv[2]); fs=7200
L=LinkMP(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
t=0.0; mx=0; last=None
while t<t1:
    L.run(CPU_HZ//50); t+=0.02
    if t>=t0:
        v=L.a.eval('[m.dsp.dm[0x334],m.dsp.dm[0x336],m.dsp.dm[0x6F],m.dsp.dm[0x3B4]]')
        if v!=last: print('%.2f A [334]=%d [336]=%d [6F]=%04X [3B4]=%04X'%(t,v[0],v[1],v[2],v[3]),flush=True); last=v
ml=L.a.eval('m.msg_log'); print('A msgs after t0:',[(round((e[5]-L._base)/CPU_HZ,1),hex(e[3]&0xFF)) for e in ml if len(e)>5 and (e[5]-L._base)/CPU_HZ>=t0])
