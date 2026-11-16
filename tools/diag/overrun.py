"""does the DSP finish its per-sample work before the next codec frame? Per 2 s window and modem: codec rate, DSP cycles/sample budget, busy %, % of frame ticks that find the DSP NOT idle (work spilled over), max busy cycles in one sample. usage: overrun.py T1"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; t1=float(sys.argv[1]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
if os.environ.get('CYC0')=='1':          # lower bound: one cycle per instruction, no manual cycle table / wait states (set on the live DSP objects: they already exist here)
    for m in (L.a,L.b): m.cycle_model=0; m.dsp.set_cycle_model(0)
st={}
def hook(k,m):
    d=m.dsp; orig=d.serial_tick; s=st[k]={'n':0,'late':0,'maxbusy':0,'sumbusy':0,'last':d.idle_cycles(),'lastt':d.total_cycles()}
    def tick(rx):
        i,t=d.idle_cycles(),d.total_cycles(); busy=(t-s['lastt'])-(i-s['last']); s['last'],s['lastt']=i,t
        s['n']+=1; s['sumbusy']+=busy; s['maxbusy']=max(s['maxbusy'],busy)
        if not d.get('IDLE'): s['late']+=1
        orig(rx)
    d.serial_tick=tick
hook('A',L.a); hook('B',L.b); w=0
while L.samples() < int(t1*fs):
    L.run(CPU_HZ//8); t=L.samples()/fs
    if int(t/2)>w:
        w=int(t/2); out=[]
        for k,m in (('A',L.a),('B',L.b)):
            s=st[k]; n=max(s['n'],1)
            out.append('%s rate %d budget %d avg busy %.0f%% not-idle-at-tick %.1f%% max busy %d'%(k,m.rate,m.dsp_cps,100*s['sumbusy']/n/m.dsp_cps,100*s['late']/n,s['maxbusy']))
            s.update(n=0,late=0,maxbusy=0,sumbusy=0)
        print('t<%2d: '%(w*2),' | '.join(out),flush=True)
