import sys; sys.path.insert(0,'.')
from machine import *
from line import *
import capstone as cs
m=Machine(nvram_mode=None); cpu=m.cpu; m.logging=False
m.run(900_000_000); m.dte_text()
for c in ("AT\r","ATQ0V1X3\r"): m.send(c); m.run(150_000_000); m.dte_text()
m.rx_gen=dial_tone(3000); m.send("ATDT1\r")
cpu.bp(0x8F684)   # 8F46:0224 send-command entry (AX=cmd, BX=arg)
rom=open('../SV25.flash.bin','rb').read(); md=cs.Cs(cs.CS_ARCH_X86,cs.CS_MODE_16)
seen=0
for i in range(4000):
    r=m.run(200_000)
    if r==ST_BP:
        ax=cpu.get("AX"); bx=cpu.get("BX"); sp=cpu.get("SP"); ss=cpu.get("SS")
        ret=cpu.rd16((ss<<4)+sp); retcs=cpu.rd16((ss<<4)+sp+2)
        print("send cmd AX=%04X BX=%04X  from far-ret %04X:%04X  [0xbd7]=%02X"%(ax,bx,retcs,ret,cpu.rd8(0xbd7)))
        seen+=1
        if ax==0x13:
            base=(retcs*16-0x80000)
            for off in range(0,8):
                st=base+ret-60+off; ins=list(md.disasm(rom[st:base+ret+90],st))
                if any(i.address==base+ret for i in ins):
                    for j in ins: print("      %05X  %-14s %s %s"%(j.address,rom[j.address:j.address+j.size].hex(' ')[:14],j.mnemonic,j.op_str))
                    break
            break
        if seen>40: break
