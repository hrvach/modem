"""FORCED 300 bps (AT&N1 on both) variant of call_data.py: A sends 120 x U (alternating bits) after CONNECT, for the FSK bit-duration check. Original: two-modem call, then user data both ways: after both modems print CONNECT, A's DTE sends MSGA and B's DTE sends MSGB.
usage: call_data.py MAXSEC TAG [MSGA] [MSGB]; prints what each DTE received after CONNECT (text + hex), writes out/TAG/ stereo wav"""
import os, sys, struct, wave; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
if os.environ.get('LINKMP') == '1': from link_mp import LinkMP as Link      # one process per modem
from machine import CPU_HZ
fs=7200; maxsec=float(sys.argv[1]); tag=sys.argv[2]
msga=(sys.argv[3] if len(sys.argv)>3 else "U"*120).encode(); msgb=(sys.argv[4] if len(sys.argv)>4 else "HelloFromB").encode()
connect_t={}
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r","AT&N1\r"]),(L.b,["AT\r","ATQ0V1X3\r","AT&N1\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.gain=float(os.environ.get('GAIN','0.5')); L.echo=float(os.environ.get('ECHO','0.0')); chunk0=len(L.chunks['a']) if hasattr(L,'chunks') else 0; L.start_call("1")
t_conn=None; sent_at=None; ia=ib=0
while L.samples() < int(maxsec*fs):
    L.run(CPU_HZ//2); t=L.samples()/fs
    for k in 'ab':
        if k not in connect_t and b'CONNECT' in L.txt[k]: connect_t[k]=round(L.samples()/fs,2)
    if t_conn is None and b'CONNECT' in L.txt['a'] and b'CONNECT' in L.txt['b']:
        t_conn=t; ia=L.txt['a'].index(b'CONNECT'); ib=L.txt['b'].index(b'CONNECT')
        ia=L.txt['a'].index(b'\n',ia)+1 if b'\n' in L.txt['a'][ia:] else len(L.txt['a']); ib=L.txt['b'].index(b'\n',ib)+1 if b'\n' in L.txt['b'][ib:] else len(L.txt['b'])
        print("both CONNECT at %.1f s"%t,flush=True)
    if t_conn is not None and sent_at is None and t>t_conn+float(os.environ.get("SENDDELAY","4")):
        L.a.send(msga.decode()); L.b.send(msgb.decode()); sent_at=t; print("sent at %.1f s: A->%r B->%r"%(t,msga,msgb),flush=True)
    if sent_at is not None and t>sent_at+20: break
base_c=getattr(L,'_base',0)
for nm,mm in (('A',L.a),('B',L.b)):
    ml=mm.msg_log if not hasattr(mm,'eval') else mm.eval('m.msg_log'); first={}
    for e in ml:
        if len(e)>5: first.setdefault(e[3]&0xFF,(e[5]-base_c)/CPU_HZ)
    print('MSGT',nm,' '.join('%02X@%.1f'%(k,v) for k,v in sorted(first.items(),key=lambda kv:kv[1])))
for nm,mm in (('A',L.a),('B',L.b)):
    cl=mm.cmd_log if not hasattr(mm,'eval') else mm.eval('m.cmd_log')
    print('CMDT',nm,' '.join('%.1f:%02X/%04X'%((c-base_c)/CPU_HZ,cmd,arg) for c,cmd,arg in cl if cmd<0x80 and (c-base_c)/CPU_HZ>=17))
for nm,mm in (('A',L.a),('B',L.b)):
    rl=mm.rate_log if not hasattr(mm,'eval') else mm.eval('m.rate_log'); al=mm.aic_log if not hasattr(mm,'eval') else mm.eval('m.aic_log')
    print('RATET',nm,' '.join('%.2f:%d'%(t-base_c/CPU_HZ,r) for t,r in rl if t-base_c/CPU_HZ>0))
    print('AICT',nm,' '.join('%.2f:r%d=%d'%(t-base_c/CPU_HZ,rg,v) for t,rg,v in al if t-base_c/CPU_HZ>0))
def lagcorr(x,k):
    num=sum(x[i]*x[i+k] for i in range(len(x)-k)); den=sum(v*v for v in x) or 1
    return num/den
for nm in 'ab':
    x=L.audio[nm]; out=[]
    for i in range(0,len(x)-5000,5000):
        seg=x[i:i+5000]; out.append('%.2f' % lagcorr(seg,6))
    print('LAG6',nm.upper(),'(per 5000 samples from call start)',' '.join(out))
if hasattr(L,'chunks'):
    from machine import CPU_HZ as _CH
    per=L.slice/_CH
    for nm in 'ab':
        ch=L.chunks[nm][chunk0:]; w=int(0.1/per)+1; bursts=[]
        for i in range(0,len(ch)-w,w):
            x=[v for r,xs in ch[i:i+w] for v in xs]
            if len(x)<200: continue
            num=sum(x[j]*x[j+6] for j in range(len(x)-6)); den=sum(v*v for v in x) or 1
            c=num/den
            if abs(c)>0.25 and den/len(x)>1e5 and i*per>=14: bursts.append('%.1f:%+.2f/%d'%(i*per,c,int((den/len(x))**0.5)))
        print('SBURST',nm.upper(),'lag-6 corr windows (t:corr) |corr|>0.45:',' '.join(bursts))
for nm,mm in (('A',L.a),('B',L.b)):
    ml=mm.msg_log if not hasattr(mm,'eval') else mm.eval('m.msg_log')
    print('MSGALL',nm,' '.join('%.2f:%02X/%02X%02X'%((e[5]-base_c)/CPU_HZ,e[3]&0xFF,(e[4]>>8)&0xFF,e[4]&0xFF) for e in ml if len(e)>5 and 17<=(e[5]-base_c)/CPU_HZ<=34))
if hasattr(L,'chunks'):
    from machine import CPU_HZ as _CH2
    per=L.slice/_CH2
    for nm in 'ab':
        ch=L.chunks[nm][chunk0:]; xs=[]; ts=[]
        for i,(r,x) in enumerate(ch):
            for j,v in enumerate(x): xs.append(v); ts.append((i+(j+0.5)/max(len(x),1))*per)
        seg=[]; W=48; run=None
        for i in range(0,len(xs)-W-6,6):
            w=xs[i:i+W+6]; num=sum(w[k]*w[k+6] for k in range(W)); den=sum(v*v for v in w[:W]) or 1
            ok=(den/W>1e5 and 0.45<num/den<0.8)
            if ok and run is None: run=ts[i]
            if not ok and run is not None:
                if ts[i]-run>0.001 and run>=14: seg.append('%.3f+%.0fms'%(run,(ts[i]-run)*1000))
                run=None
        print('SLEN',nm.upper(),'segments with lag-6 corr>0.8 (start+duration):',' '.join(seg))
print('CONNECT_T A %s B %s'%(connect_t.get('a'),connect_t.get('b')))
print("rate changes A:",L.a.rate_log,"B:",L.b.rate_log)
print("A DTE text:",L.txt['a'][-300:])
print("B DTE text:",L.txt['b'][-300:])
if t_conn is not None:
    ra=L.txt['a'][ia:]; rb=L.txt['b'][ib:]
    print("A received after CONNECT (%d bytes): %r"%(len(ra),ra[:120])); print("   hex:",ra[:60].hex(' '))
    print("B received after CONNECT (%d bytes): %r"%(len(rb),rb[:120])); print("   hex:",rb[:60].hex(' '))
    print("A got MSGB:",msgb in ra,"  B got MSGA:",msga in rb)
os.makedirs(ROOT+'/out/'+tag,exist_ok=True)
if hasattr(L,'write_wav'): L.write_wav(ROOT+'/out/%s/call_22k_B_left_A_right.wav'%tag, 22050, first_chunk=chunk0)
if t_conn is not None:
    open(ROOT+'/out/%s/A_rx.bin'%tag,'wb').write(ra); open(ROOT+'/out/%s/B_rx.bin'%tag,'wb').write(rb)
a=L.audio['a']; b=L.audio['b']; n=min(len(a),len(b))
with wave.open(ROOT+'/out/%s/call_caller_B_left_answerer_A_right.wav'%tag,'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(7200); w.writeframes(struct.pack('<%dh'%(2*n),*[v for i in range(n) for v in (b[i],a[i])]))
