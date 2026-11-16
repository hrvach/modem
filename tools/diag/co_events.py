"""print the central-office state machine events (dialtone/digit/dialing/ringing/answering/connected) and the first DTE text of each modem; usage: co_events.py T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link_mp import LinkMP
from machine import CPU_HZ
t1=float(sys.argv[1]); fs=7200; L=LinkMP(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
print('pre-call DTE:',L.text())
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
peak=0
while L.samples()<int(t1*fs):
    L.run(CPU_HZ//8)
print('events:',L.events); print('A txt',L.txt['a'][:200]); print('B txt',L.txt['b'][:200])
import statistics
tb=L.audio['b']; print('B tx peak overall:',max(map(abs,tb)) if tb else None,'samples',len(tb))

for nm,mm in (('A',L.a),('B',L.b)):
    cl=mm.eval('m.cmd_log'); base=getattr(L,'_base',0)
    print('CMD',nm,' '.join('%.1f:%02X/%04X'%((c-base)/CPU_HZ,cmd,arg) for c,cmd,arg in cl if cmd<0x80)[:700])
    ml=mm.eval('m.msg_log'); print('MSG',nm,' '.join('%.1f:%02X/%04X'%((e[5]-base)/CPU_HZ,e[3]&0xFF,e[4]) for e in ml if len(e)>5)[:500])
print('B DSP PC',hex(L.b.eval('m.dsp.get("PC")')),' B host state',L.b.eval('m.cpu.state()')[:80])
