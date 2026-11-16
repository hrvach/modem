"""two modems, other firmware: boot, AT setup, B dials, show the host commands and DSP messages of both. usage: link403.py SECONDS"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
secs=float(sys.argv[1]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ)); print(('A' if m is L.a else 'B'),repr(c),'->',m.dte_text()[:60])
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); b0=L.b.cpu.cycles
while L.samples() < int(secs*7200): L.run(CPU_HZ//8)
for nm,m in (('A',L.a),('B',L.b)):
    base=b0 if nm=='B' else L.a.cpu.cycles-(L.b.cpu.cycles-b0)
    print(nm,'state',L.state,'host cmds (t,cmd,arg):',[(round((c-b0)/CPU_HZ,2),hex(a),hex(b)) for c,a,b in m.cmd_log[-25:]],'n',len(m.cmd_log))
    print(nm,'DSP msgs (type,w,w):',[(hex(x[1]),hex(x[3]),hex(x[4])) for x in m.msg_log[:12]],'... n',len(m.msg_log))
    print(nm,'DSP',m.dsp.state(),'rate',m.rate)
print('events',L.events[:10]); print('A txt',L.txt['a'][:80],'B txt',L.txt['b'][:80])
