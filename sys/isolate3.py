import sys, math, json; sys.path.insert(0,'.')
from machine import *
from line import *
fs=7200
m=Machine(nvram_mode=None); m.logging=False
m.run(900_000_000); m.dte_text()
for c in ("AT\r","ATQ0V1X3\r"): m.send(c); m.run(150_000_000); m.dte_text()
m.rx_gen=dial_tone(3000); m.tx_all.clear(); m.cmd_log16.clear(); m.send("ATDT1\r")
removed=None
while len(m.tx_all)<int(14*fs):
    m.run(100_000)
    if removed is None and m.tx_all and max(map(abs,m.tx_all[-2000:]))>15000:
        m.rx_gen=None; removed=len(m.tx_all)/fs; print("dial tone cut at %.3f s (first loud sample)"%removed)
print("commands:",[(round(t/fs,2),"%04X"%c,"%04X"%a) for t,c,a in m.cmd_log16 if t>7*fs][:20])
print("peak per 0.5 s from 7 s:",[max(map(abs,m.tx_all[int(t*fs):int((t+0.5)*fs)])) for t in (7,7.5,8,9,10,12,13)])
x=m.tx_all[int(10*fs):int(10*fs)+16]; print("samples at 10 s:",x)
json.dump(m.tx_all,open('/tmp/claude-1000/-home-hrvoje-Programming-USR/831d3a18-6a9c-4288-84f9-a85e9135fc6f/scratchpad/isolate3.json','w'))
import capstone as cs
cpu=m.cpu
print(cpu.state())
before=[cpu.hits[i] for i in range(0x80000,0x100000)]
m.run(30_000_000)
after=[cpu.hits[i] for i in range(0x80000,0x100000)]
d=sorted(((after[i]-before[i],i+0x80000) for i in range(len(after)) if after[i]!=before[i]),reverse=True)
print("distinct pcs:",len(d),"hot:",[("%05X"%(a-0x80000),n) for n,a in d[:10]])
rom=open('../SV25.flash.bin','rb').read(); md=cs.Cs(cs.CS_ARCH_X86,cs.CS_MODE_16)
for a in sorted(a-0x80000 for n,a in d[:20]):
    for i in md.disasm(rom[a:a+8],a):
        print("   %05X  %-14s %s %s x%d"%(a,rom[a:a+i.size].hex(' ')[:14],i.mnemonic,i.op_str,after[a+0x80000]-before[a+0x80000-0x80000+0x80000-0x80000]) if False else "   %05X  %-14s %s %s"%(a,rom[a:a+i.size].hex(' ')[:14],i.mnemonic,i.op_str)); break
sp=cpu.get("SP"); ss=cpu.get("SS"); print("stack:",["%04X"%cpu.rd16((ss<<4)+sp+2*k) for k in range(10)])
print("[0xbd7]=%02X [0xbd6]=%02X [0x134]=%04X [0x26e]=%04X"%(cpu.rd8(0xbd7),cpu.rd8(0xbd6),cpu.rd16(0x134),cpu.rd16(0x26e)))
