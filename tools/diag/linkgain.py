import sys; sys.path.insert(0,'.')
from link import *
g=float(sys.argv[1]); dur=float(sys.argv[2]) if len(sys.argv)>2 else 45
L=Link(); L.gain=g
L.run(900_000_000); L.text()
for m,cmds in ((L.a,("AT\r","ATQ0V1\r")),(L.b,("AT\r","ATQ0V1X3\r"))):
    for c in cmds: m.send(c); L.run(150_000_000)
L.text()
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0; mm.cmd_log16.clear(); mm.dsp_log.clear()
L.audio={'a':[],'b':[]}; L.events=[]; L.start_call("1")
while L.samples() < int(dur*7200): L.run(10_000_000)
fs=7200
b=L.audio['b']; a=L.audio['a']
def pk(s,t0,t1): 
    x=s[int(t0*fs):int(t1*fs)]; return max(map(abs,x)) if x else 0
print("gain %.2f: B peak per 2 s from 22 s:"%g,[pk(b,t,t+2) for t in range(22,int(dur)-1,2)])
print("gain %.2f: A peak per 2 s from 22 s:"%g,[pk(a,t,t+2) for t in range(22,int(dur)-1,2)])
print("gain %.2f: B cmds after 22 s:"%g,[(round(t/fs,2),"%04X"%c,"%04X"%x) for t,c,x in L.b.cmd_log16 if t>22*fs])
print("gain %.2f: A cmds after 22 s:"%g,[(round(t/fs,2),"%04X"%c,"%04X"%x) for t,c,x in L.a.cmd_log16 if t>22*fs])
import json; json.dump({'a':a,'b':b},open('call_g%s.json'%sys.argv[1],'w'))
