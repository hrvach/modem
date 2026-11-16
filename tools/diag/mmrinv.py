"""inventory of DSP accesses to data page 0 (MMRs, peripheral regs, memory-mapped ports 50-5F) during a two-modem call, per modem, with the last PC.
usage: mmrinv.py SECONDS"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; dur=float(sys.argv[1])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.start_call("1")
while L.samples() < int(dur*fs): L.run(10_000_000)
for nm,m in (('A',L.a),('B',L.b)):
    d=m.dsp
    print(nm,'addr  reads  writes  lastPC(r/w)')
    for a in range(0x60):
        r=d.mmr_count(0,a); w=d.mmr_count(1,a)
        if r or w: print('  %02X %8d %8d  %04X/%04X  val(first or last init)=%04X'%(a,r,w,d.mmr_pc(0,a),d.mmr_pc(1,a),d.mmr_val(a)))
for nm,m in (('A',L.a),('B',L.b)):
    d=m.dsp; print(nm,'external data space accesses per 1K block (read/write):',{'%04X'%(b<<10):(d.ext_count(0,b),d.ext_count(1,b)) for b in range(64) if d.ext_count(0,b) or d.ext_count(1,b)})
for nm,m in (('A',L.a),('B',L.b)): print(nm,'last read of reserved data 0500-07FF: addr %04X by PC %04X'%(m.dsp.rsv(0),m.dsp.rsv(1)))
