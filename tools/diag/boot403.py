"""boot one modem with another firmware and show the CPU<->DSP traffic: host commands, DSP messages, DSP state, CPU port access counts. usage: boot403.py SECONDS  (env FLASH NVRAM CPU_HZ DSP_HZ IFACE)"""
import os, sys, collections; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from machine import *
secs=float(sys.argv[1]); m=Machine(nvram_mode=None); m.logging=False
m.run(int(2*CPU_HZ)); print('t=2s dsp started:', m.dsp is not None, 'DTE:', m.dte_text()[:60])
m.logging=True
for i in range(int(secs)-2):
    m.run(CPU_HZ)
    if i==0 or i==int(secs)-3:
        cnt=collections.Counter((e[0],e[1]) for e in m.log); print('t=%ds CPU port accesses (R/W, port: count):'%(3+i), sorted(cnt.items(), key=lambda kv:-kv[1])[:14])
    m.log.clear()
m.logging=False
print('DTE text:', repr(m.dte_text()[:200]))
print('host commands to DSP (cycle/CPU_HZ, cmd, arg), first 30:', [(round(c/CPU_HZ,2),hex(a),hex(b)) for c,a,b in m.cmd_log[:30]], 'total', len(m.cmd_log))
print('DSP messages (type words), first 20:', [(hex(x[1]),hex(x[3]),hex(x[4])) for x in m.msg_log[:20]], 'total', len(m.msg_log))
d=m.dsp
if d: print('DSP state:', d.state(), 'IDLE', d.get('IDLE'), 'cycles', d.total_cycles())
print('h2d_pending',m.h2d_pending,'d2h_valid',m.d2h_valid,'evt',m.evt,'ovl_status',m.ovl_status,'ovl_loads',[(round(a/CPU_HZ,2),hex(b),c) for a,b,c in m.ovl_loads[:8]])
