import sys, wave, struct, math; sys.path.insert(0,'.')
from link import *
from capture_caller import wav
L=Link()
L.run(900_000_000); L.text()
for m,cmds in ((L.a,("AT\r","ATQ0V1\r")),(L.b,("AT\r","ATQ0V1X3\r"))):
    for c in cmds: m.send(c); L.run(150_000_000)       # one command at a time: the first one after boot is garbled
L.text()
for m in (L.a,L.b): m.tx_all.clear(); m._lk_seen=0
for mm in (L.a,L.b): mm.cmd_log16.clear()
L.audio={'a':[],'b':[]}; L.events=[]; L.start_call("1")
oa=b''; ob=b''
for i in range(22):
    L.run(100_000_000); ta,tb=L.text(); oa+=ta; ob+=tb
    if ta or tb: print("t=%.1fs  A:%r  B:%r"%(L.samples()/FS,ta,tb))
print("state events (s):",L.events)
t0=len(L.audio['b'])
for nm,mm in (('B caller',L.b),('A callee',L.a)):
    print(nm,"DSP commands since start of call (sample time s, cmd, arg):")
    last=None
    for t,c,a in mm.cmd_log16:
        if t>=0: 
            print("    %6.2f  %04X %04X"%(t/7200,c,a))
print("A DTE total:",oa); print("B DTE total:",ob)
wav('/home/hrvoje/Programming/USR/out/link3_callee_A.wav',L.audio['a']); wav('/home/hrvoje/Programming/USR/out/link3_caller_B.wav',L.audio['b'])
print("wrote out/link3_callee_A.wav and out/link3_caller_B.wav (%.0f s)"%(L.samples()/FS))
import json; json.dump(L.audio,open('/tmp/claude-1000/-home-hrvoje-Programming-USR/831d3a18-6a9c-4288-84f9-a85e9135fc6f/scratchpad/link3.json','w'))

import capstone as cs
cpu=L.b.cpu
print("B CPU:",cpu.state()); print("B [0xbd7]=%02X [0xbd6]=%02X [0x134]=%04X [0x26e]=%04X [0x26a]=%04X [0x32c]=%02X [0xbe1]=%04X"%(cpu.rd8(0xbd7),cpu.rd8(0xbd6),cpu.rd16(0x134),cpu.rd16(0x26e),cpu.rd16(0x26a),cpu.rd8(0x32c),cpu.rd16(0xbe1)))
before=[cpu.hits[i] for i in range(0x80000,0x100000)]
L.b.run(20_000_000)
after=[cpu.hits[i] for i in range(0x80000,0x100000)]
d=sorted(((after[i]-before[i],i+0x80000) for i in range(len(after)) if after[i]!=before[i]),reverse=True)
print("B hot:",[("%05X"%(a-0x80000),n) for n,a in d[:8]])
rom=open('../SV25.flash.bin','rb').read(); md=cs.Cs(cs.CS_ARCH_X86,cs.CS_MODE_16)
for a in sorted(a-0x80000 for n,a in d[:16]):
    for i in md.disasm(rom[a:a+8],a): print("   %05X  %-14s %s %s"%(a,rom[a:a+i.size].hex(' ')[:14],i.mnemonic,i.op_str)); break
sp=cpu.get("SP"); ss=cpu.get("SS"); print("B stack:",["%04X"%cpu.rd16((ss<<4)+sp+2*k) for k in range(10)])

import wave, struct
def mono(p,x):
    with wave.open(p,'wb') as w: w.setnchannels(1); w.setsampwidth(2); w.setframerate(7200); w.writeframes(struct.pack('<%dh'%len(x),*[max(-32768,min(32767,v)) for v in x]))
a=L.audio['a']; b=L.audio['b']; n=min(len(a),len(b))
mono('/home/hrvoje/Programming/USR/out/call_callee_A.wav',a); mono('/home/hrvoje/Programming/USR/out/call_caller_B.wav',b)
with wave.open('/home/hrvoje/Programming/USR/out/call_caller_left_answerer_right.wav','wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(7200)
    fr=[]
    for k in range(n): fr += [max(-32768,min(32767,b[k])), max(-32768,min(32767,a[k]))]
    w.writeframes(struct.pack('<%dh'%len(fr),*fr))
print("wrote call_*.wav (%.0f s)"%(n/7200))
import json; json.dump({'a':a,'b':b},open('/tmp/claude-1000/-home-hrvoje-Programming-USR/831d3a18-6a9c-4288-84f9-a85e9135fc6f/scratchpad/call_noise.json','w'))
