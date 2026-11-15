"""two-modem call, then user data both ways: after both modems print CONNECT, A's DTE sends MSGA and B's DTE sends MSGB.
usage: call_data.py MAXSEC TAG [MSGA] [MSGB]; prints what each DTE received after CONNECT (text + hex), writes out/TAG/ stereo wav"""
import os, sys, struct, wave; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; maxsec=float(sys.argv[1]); tag=sys.argv[2]
msga=(sys.argv[3] if len(sys.argv)>3 else "HelloFromA").encode(); msgb=(sys.argv[4] if len(sys.argv)>4 else "HelloFromB").encode()
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
t_conn=None; sent_at=None; ia=ib=0
while L.samples() < int(maxsec*fs):
    L.run(CPU_HZ//2); t=L.samples()/fs
    if t_conn is None and b'CONNECT' in L.txt['a'] and b'CONNECT' in L.txt['b']:
        t_conn=t; ia=L.txt['a'].index(b'CONNECT'); ib=L.txt['b'].index(b'CONNECT')
        ia=L.txt['a'].index(b'\n',ia)+1 if b'\n' in L.txt['a'][ia:] else len(L.txt['a']); ib=L.txt['b'].index(b'\n',ib)+1 if b'\n' in L.txt['b'][ib:] else len(L.txt['b'])
        print("both CONNECT at %.1f s"%t,flush=True)
    if t_conn is not None and sent_at is None and t>t_conn+4:
        L.a.send(msga.decode()); L.b.send(msgb.decode()); sent_at=t; print("sent at %.1f s: A->%r B->%r"%(t,msga,msgb),flush=True)
    if sent_at is not None and t>sent_at+20: break
print("A DTE text:",L.txt['a'][-300:])
print("B DTE text:",L.txt['b'][-300:])
if t_conn is not None:
    ra=L.txt['a'][ia:]; rb=L.txt['b'][ib:]
    print("A received after CONNECT (%d bytes): %r"%(len(ra),ra[:120])); print("   hex:",ra[:60].hex(' '))
    print("B received after CONNECT (%d bytes): %r"%(len(rb),rb[:120])); print("   hex:",rb[:60].hex(' '))
    print("A got MSGB:",msgb in ra,"  B got MSGA:",msga in rb)
os.makedirs(ROOT+'/out/'+tag,exist_ok=True)
if t_conn is not None:
    open(ROOT+'/out/%s/A_rx.bin'%tag,'wb').write(ra); open(ROOT+'/out/%s/B_rx.bin'%tag,'wb').write(rb)
a=L.audio['a']; b=L.audio['b']; n=min(len(a),len(b))
with wave.open(ROOT+'/out/%s/call_caller_B_left_answerer_A_right.wav'%tag,'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(7200); w.writeframes(struct.pack('<%dh'%(2*n),*[v for i in range(n) for v in (b[i],a[i])]))
