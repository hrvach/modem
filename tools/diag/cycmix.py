"""where do the DSP cycles go? PC hit deltas of modem A's DSP over a window, mapped to mnemonic (from the dsp_*.asm listings) and to the manual cycle table (dsp/c5x_cyctab.h); prints the instruction classes that cost more than 1 cycle, weighted by how often they run. usage: cycmix.py T0 T1"""
import os, sys, re, collections; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
hdr=open(ROOT+'/dsp/c5x_cyctab.h').read(); cyc=[int(x) for x in re.findall(r'\b\d+\b',hdr[hdr.index('{'):])]
assert len(cyc)==65536,len(cyc)
def load(fn):
    m={}
    for l in open(ROOT+'/dsp/'+fn):
        g=re.match(r'^([0-9A-F]{4})\s+((?:[0-9a-f]{4}\s?)+)\s+(?:\w+:\s*)?(\S+)',l)
        if g: m[int(g.group(1),16)]=g.group(3)
    return m
base,ov6,ov8=load('dsp_base.asm'),load('dsp_ov6.asm'),load('dsp_ov8.asm')
def mnem(a):
    if 0x9D00<=a<=0xC9F6: return ov6.get(a,'?')
    if 0xDC00<=a<=0xF8B6: return ov8.get(a,'?')
    return base.get(a,'?')
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base_c=L.a.cpu.cycles; T=lambda: (L.a.cpu.cycles-base_c)/CPU_HZ
while T()<T0: L.run(CPU_HZ//64)
d=L.a.dsp; h0=[d.pc_hits(i) for i in range(0x10000)]; c0=d.total_cycles(); i0=d.idle_cycles()
while T()<T1: L.run(CPU_HZ//64)
h1=[d.pc_hits(i) for i in range(0x10000)]; c1=d.total_cycles(); i1=d.idle_cycles()
agg=collections.defaultdict(lambda:[0,0,0])
tot_i=0; tot_c=0
for pc in range(0x10000):
    n=h1[pc]-h0[pc]
    if n<=0 or pc<0x60: continue
    op=d.pm[pc]; c=cyc[op]; mn=mnem(pc)
    a=agg[mn]; a[0]+=n; a[1]+=n*c; a[2]+=n*(c-1); tot_i+=n; tot_c+=n*c
print('window %.1f-%.1f s: %d cycles, idle %d, executed instructions %d; table cost of executed instructions %d cycles (%.2f per instruction)'%(T0,T1,c1-c0,i1-i0,tot_i,tot_c,tot_c/max(1,tot_i)))
print('mnemonic        count   cycles(table)  extra over 1 cycle  share of extra')
ex=sum(v[2] for v in agg.values()) or 1
for mn,v in sorted(agg.items(),key=lambda kv:-kv[1][2])[:22]: print('%-12s %9d %12d %14d     %5.1f%%'%(mn,v[0],v[1],v[2],100*v[2]/ex))
