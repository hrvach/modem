"""two-modem call; log every call of the result-code printer (flash 9E60) on both machines with AL, time, recent supervisor PCs and last DSP messages"""
import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
from machine import CPU_HZ, ST_BP
fs=7200; dur=float(sys.argv[1])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}
hits=[]
for nm,m in (('A',L.a),('B',L.b)):
    m.cpu.bp(0x89E60)
    orig=m.run
    def mk(nm,m,orig):
        def run(c,s=None):
            r=orig(c,s)
            if r==ST_BP:
                cp=m.cpu; hits.append((nm,L.samples()/fs,cp.get('AX')&0xFF,[p-0x80000 for p in cp.recent(200)],list(m.msg_log[-6:]),m.cpu.rd16(0x298),cp.rd8(0x32B),cp.rd8(0x32C),[cp.rd16(cp.get('SS')*16+cp.get('SP')+2*i) for i in range(24)]))
            return r
        return run
    m.run=mk(nm,m,orig)
L.start_call("1")
while L.samples() < int(dur*fs): L.run(10_000_000)
for nm,t,al,pcs,msgs,h298,b32b,b32c,stk in hits:
    print("%s t=%.2f result-printer AL=%02X h298=%04X 32B=%02X 32C=%02X"%(nm,t,al,h298,b32b,b32c))
    seen=[]; 
    for p in pcs[::-1]:
        if p not in seen: seen.append(p)
    print("   stack:",' '.join('%04X'%w for w in stk))
    print("   recent distinct PCs (newest first):",' '.join('%05X'%p for p in seen[:40]))
    print("   last DSP msgs:",[(round(a/fs,2),'%04X'%c,'%04X'%d) for a,b,b2,c,d in msgs][-6:] if msgs and len(msgs[0])==5 else msgs)
