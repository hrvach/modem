import sys; sys.path.insert(0,'.')
from machine import *
from line import *
import capstone as cs
fs=7200
m=Machine(nvram_mode=None); cpu=m.cpu; m.logging=False
m.run(900_000_000); m.dte_text()
for c in ("AT\r","ATQ0V1X3\r"): m.send(c); m.run(150_000_000); m.dte_text()
m.rx_gen=dial_tone(3000); m.tx_all.clear(); m.send("ATDT1\r")
cpu.bp(0x8F684); cpu.bp(0x8F688)
rom=open('../SV25.flash.bin','rb').read(); md=cs.Cs(cs.CS_ARCH_X86,cs.CS_MODE_16)
cut=False; log=[]
for i in range(20000):
    r=m.run(50_000)
    if not cut and m.tx_all and max(map(abs,m.tx_all[-1500:]))>15000: m.rx_gen=None; cut=True; log.append(("CUT dial tone",len(m.tx_all)/fs))
    if r==ST_BP:
        pc=cpu.phys_pc()-0x80000; sp=cpu.get("SP"); ss=cpu.get("SS")
        log.append(("send entry %05X AX=%04X BX=%04X ret=%04X:%04X [bd7]=%02X [134]=%04X"%(pc,cpu.get("AX"),cpu.get("BX"),cpu.rd16((ss<<4)+sp+2),cpu.rd16((ss<<4)+sp),cpu.rd8(0xbd7),cpu.rd16(0x134)),len(m.tx_all)/fs))
    if len(m.tx_all)>int(11*fs): break
for l in log:
    if l[1]>6.5 or l[0].startswith("CUT"): print("%6.2fs  %s"%(l[1],l[0]))
