"""dump A's transmit samples for call-time window to JSON with start index. usage: txdump.py T0 T1 OUT"""
import os, sys, json; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples()<int((T1+0.05)*fs): L.run(CPU_HZ//64)
# audio index i corresponds to call sample i (+ small constant offset); window by index
xa=L.audio['a']; i0=int(T0*fs)+9103; json.dump({'i0':i0,'x':xa[i0:int(T1*fs)+9103]},open(sys.argv[3],'w')); print('saved',len(xa))
