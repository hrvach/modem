"""dump the DSP->host stream words (port 0x60 writes) per modem with call time, and look for the host's frame header (bytes 01 06) in the byte stream. usage: stream60.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; t0=float(sys.argv[1]); t1=float(sys.argv[2]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); base=L.b.cpu.cycles
for m in (L.a,L.b): m.dsp_log.clear()
words={'A':[],'B':[]}
while L.samples() < int(t1*fs):
    L.run(CPU_HZ//8)
    for nm,m in (('A',L.a),('B',L.b)):
        for c,q,v in m.dsp_log:
            if q==0x60: words[nm].append(((c-base)/CPU_HZ,v&0xFFFF))
        m.dsp_log.clear()
for nm in 'AB':
    w=[x for x in words[nm] if x[0]>=t0]
    print(nm,'stream words in window:',len(w))
    bs=[]
    for t,v in w: bs += [(t,v&0xFF),(t,v>>8)]
    hits=[(bs[i][0],i) for i in range(len(bs)-1) if bs[i][1]==1 and bs[i+1][1]==6]
    print(nm,'01 06 pairs at:',[('%.2f'%t,i) for t,i in hits][:20])
    print(nm,'first words:',' '.join('%.2f:%04X'%x for x in w[:24]))
