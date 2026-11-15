import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(4*CPU_HZ); m.send("AT\r"); m.run(CPU_HZ); m.dte_text(); m.send("ATA\r"); d=m.dsp
last=None
for i in range(int(float(sys.argv[1])*20)):
    n0=len(m.tx_all); m.run(CPU_HZ//20); x=m.tx_all[n0:]; pk=max(map(abs,x)) if x else 0
    st=(d.dm[0x39A],d.dm[0x39B],d.dm[0x392]); 
    if st!=last: print("t+%5.2f tasks 1A=%04X 1B=%04X gain=%04X peak=%d"%(i/20,*st,pk)); last=st
