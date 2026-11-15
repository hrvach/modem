import sys, collections; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
from machine import CPU_HZ, ST_BP
fs=7200; dur=float(sys.argv[1]); which=sys.argv[2]; bps=[int(x,16) for x in sys.argv[3].split(',')]
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}
m=L.a if which=='a' else L.b
hits=collections.defaultdict(list)
for b in bps: m.cpu.bp(b+0x80000)
orig=m.run
def run(c,s=None):
    r=orig(c,s)
    while r==ST_BP:
        pc=m.cpu.phys_pc()-0x80000
        hits[pc].append(round(L.samples()/fs,2))
        r=orig(c,s)
    return r
m.run=run
L.start_call("1")
while L.samples() < int(dur*fs): L.run(10_000_000)
for pc,ts in sorted(hits.items()): print('%05X hits=%d first=%s last=%s'%(pc,len(ts),ts[:4],ts[-2:]))
