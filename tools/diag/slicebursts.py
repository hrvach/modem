"""log link slices in which one modem delivers an unusual number of tx samples (burst), with time. usage: slicebursts.py T0 T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda m:(m.cpu.cycles-base)/CPU_HZ
o=L._new
def nw(m,k):
    r=o(m,k)
    if T0<=T(m)<=T1: print('%.4f slice: %s delivered %d tx samples  (rate %d, queue of peer %d)'%(T(m),k.upper(),len(r),m.rate,len((L.b if k=='a' else L.a).rxbuf)))
    return r
L._new=nw
while T(L.a)<T1: L.run(CPU_HZ//64)
