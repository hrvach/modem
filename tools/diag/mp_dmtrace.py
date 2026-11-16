"""two-process call; every 0.1 s record DSP state of A and B ([6F] and data pages 6/7 = dm[0x300..0x3FF]) to /tmp/trace_TAG.json for differential analysis.
usage: mp_dmtrace.py TAG T0 T1   (env DELAY_SAMPLES etc.)"""
import os, sys, json; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link_mp import LinkMP
from machine import CPU_HZ
fs=7200; tag=sys.argv[1]; t0=float(sys.argv[2]); t1=float(sys.argv[3])
L=LinkMP(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
out=[]; t=0.0
while t<t1:
    L.run(CPU_HZ//10); t+=0.1
    if t>=t0:
        rec={'t':round(t,2)}
        for k,m in (('A',L.a),('B',L.b)):
            rec[k]=m.eval('[m.dsp.dm[0x6F]]+m.dsp.dm[0x300:0x400]')
        out.append(rec)
json.dump(out,open('/tmp/trace_%s.json'%tag,'w')); print('saved',len(out))
