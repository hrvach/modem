"""what happens to user data after CONNECT: host->DSP commands, DSP->host data words, DTE receive, per modem. usage: datapath.py T_AFTER_CONNECT_SEND (s)"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
send_after=float(sys.argv[1]) if len(sys.argv)>1 else 4.0
L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1"); b0=L.b.cpu.cycles; a0=L.a.cpu.cycles
tconn=None; sent=None; snap={}
def T(m,base): return (m.cpu.cycles-base)/CPU_HZ
while L.samples() < int(float(os.environ.get("MAXS","80"))*7200):
    L.run(CPU_HZ//8)
    if tconn is None and b'CONNECT' in L.txt['a'] and b'CONNECT' in L.txt['b']:
        tconn=L.samples()/7200; print('both CONNECT at %.1f s'%tconn)
        for k,m in (('A',L.a),('B',L.b)): snap[k]=(len(m.cmd_log),len(m.msg_log),m.data_words_sent,m.data_words_read,len(L.txt[k.lower()]))
    if tconn is not None and sent is None and L.samples()/7200>tconn+send_after:
        L.a.send("HelloFromA"); L.b.send("HelloFromB"); sent=L.samples()/7200; print('typed HelloFromA / HelloFromB at %.1f s'%sent)
    if sent is not None and L.samples()/7200>sent+float(os.environ.get("TAIL","10")): break
for k,m,base in (('A',L.a,a0),('B',L.b,b0)):
    s=snap.get(k,(0,0,0,0,0))
    print(k,'host->DSP cmds after CONNECT:',[(round((c-base)/CPU_HZ,2),'%02X/%04X'%(a&0xFF,b&0xFFFF)) for c,a,b in m.cmd_log[s[0]:][:30]],'n',len(m.cmd_log)-s[0])
    print(k,'DSP->host msgs after CONNECT (tag/word):',[(round((x[5]-base)/CPU_HZ,2),'%02X/%04X'%(x[3]&0xFF,x[4])) for x in m.msg_log[s[1]:][:14]],'n',len(m.msg_log)-s[1])
    print(k,'stream data words sent by DSP / read by host since CONNECT:',m.data_words_sent-s[2],'/',m.data_words_read-s[3])
    print(k,'DTE text after CONNECT:',L.txt[k.lower()][s[4]:][:80],'len',len(L.txt[k.lower()])-s[4])
    print(k,'rate',m.rate,'dsp',m.dsp.state()[:60])
