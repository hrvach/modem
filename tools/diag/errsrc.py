"""who prints the result code? bp at result-printer (flash 9EAA), dump AL and return-address chain"""
import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(7*CPU_HZ); m.dte_text()
c=m.cpu; [c.bp(int(x,16)) for x in sys.argv[2].split(",")]
m.send(sys.argv[1]+"\r"); end=c.cycles+int(2*CPU_HZ)
while c.cycles<end:
    r=m.run(end-c.cycles)
    if r==ST_BP:
        ss=c.get('SS'); sp=c.get('SP'); st=[c.rd16(ss*16+sp+2*i) for i in range(8)]
        print("recent:",' '.join('%05X'%(p-0x80000) for p in c.recent(int(sys.argv[3])))) if True else None
        print("pc=%05X AX=%04X stack=%s"%(c.phys_pc()-0x80000,c.get('AX'),' '.join('%04X'%w for w in st)))
print(m.dte_text())
