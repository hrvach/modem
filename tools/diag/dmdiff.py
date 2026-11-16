"""snapshot the answerer's (A) DSP data memory at T0, T0+1, T0+2 s inside a waiting phase; list words that change (counter / timeout candidates) and [0x40..0x4F].
usage: dmdiff.py T0 [A|B]"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; t0=float(sys.argv[1]); who=sys.argv[2] if len(sys.argv)>2 else 'A'
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
m=L.a if who=='A' else L.b
snaps=[]
for k in range(4):
    while L.samples() < int((t0+k*0.5)*fs): L.run(CPU_HZ//16)
    snaps.append([m.dsp.dm[a] for a in range(0x0C00)])
print('[6F]=%04X'%m.dsp.dm[0x6F], 'dm[0x40..0x4F]', ' '.join('%04X'%v for v in snaps[-1][0x40:0x50]))
rows=[]
for a in range(0x0C00):
    v=[s[a] for s in snaps]
    if len(set(v))>1: rows.append((a,v))
print('changing words:',len(rows))
for a,v in rows:
    d=[(v[i+1]-v[i])&0xFFFF for i in range(3)]
    kind='COUNTER?' if len(set(d))==1 and d[0] not in (0,) else ''
    if kind or len(rows)<80: print('%04X %s %s'%(a,' '.join('%04X'%x for x in v),kind))
