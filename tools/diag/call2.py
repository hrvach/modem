"""two-modem data call with optional E3C poke. usage: call2.py SECONDS [E3C_hex] [tag]; writes out/<tag>/ stereo (caller left, answerer right) + mono wavs"""
import sys, os, struct, wave; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
from machine import CPU_HZ
fs=7200; dur=float(sys.argv[1]); e3c=int(sys.argv[2],16) if len(sys.argv)>2 and sys.argv[2]!='-' else 0; tag=sys.argv[3] if len(sys.argv)>3 else 'new2'
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
print("setup:",L.txt)
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0; mm.cmd_log16.clear(); mm.dsp_log.clear(); mm.cpu.wr8(0xE3C,e3c)
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(dur*fs): L.run(10_000_000)
print("events:",[(round(t,2),s) for t,s in L.events]); print(L.txt)
for nm,mm in (('A',L.a),('B',L.b)):
    c=mm.cpu
    print(nm,"cmds:",[(round(t/fs,2),"%04X"%x,"%04X"%y) for t,x,y in mm.cmd_log16][:150])
    print(nm,"ovl",[(round((cy-0)/CPU_HZ,1),hex(a),n) for cy,a,n in mm.ovl_loads],"dspPC=%04X E3C=%02X EA7=%02X E88=%02X"%(mm.dsp.get('PC'),c.rd8(0xE3C),c.rd8(0xEA7),c.rd8(0xE88)))
for nm,mm in (('A',L.a),('B',L.b)):
    import collections
    seen=collections.OrderedDict()
    for t,a,b,c,d in mm.msg_log:
        k=(a,b,c,d); e=seen.setdefault(k,[t,t,0]); e[1]=t; e[2]+=1
    print(nm,"msg kinds (5E/5F... first,last s,count):",[("%04X/%04X/%04X/%04X"%k,round(v[0]/fs,2),round(v[1]/fs,2),v[2]) for k,v in seen.items()][:60])
import collections
for nm,mm in (('A',L.a),('B',L.b)):
    c=mm.cpu; pcs=collections.Counter()
    for i in range(300): L.run(200_000); pcs[(c.phys_pc()-0x80000)]+=1
    print(nm,"supervisor PCs:",[('%05X'%p,n) for p,n in pcs.most_common(8)],"BD7=%02X 134=%04X E88=%02X B88=%02X EA6=%02X"%(c.rd8(0xBD7),c.rd16(0x134),c.rd8(0xE88),c.rd8(0xB88),c.rd8(0xEA6)))
os.makedirs('/home/hrvoje/Programming/USR/out/'+tag,exist_ok=True)
a=L.audio['a']; b=L.audio['b']; n=min(len(a),len(b))
def wr(path,chs):
    with wave.open(path,'wb') as w:
        w.setnchannels(len(chs)); w.setsampwidth(2); w.setframerate(7200)
        w.writeframes(struct.pack('<%dh'%(n*len(chs)),*[chs[i%len(chs)][i//len(chs)] for i in range(n*len(chs))]))
wr('/home/hrvoje/Programming/USR/out/%s/call_caller_B_left_answerer_A_right.wav'%tag,[b,a])
wr('/home/hrvoje/Programming/USR/out/%s/caller_B.wav'%tag,[b]); wr('/home/hrvoje/Programming/USR/out/%s/answerer_A.wav'%tag,[a])
print("wrote",tag,n,"samples")
