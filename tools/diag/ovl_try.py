import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
e3c=int(sys.argv[1],16)
m=Machine(nvram_mode=None); m.logging=False
m.run(7*CPU_HZ); m.send("AT\r"); m.run(CPU_HZ); m.dte_text()
m.cpu.wr8(0xE3C,e3c); m.cmd_log16.clear(); m.send("ATA\r"); h0=m.hb_count; d=m.dsp
for i in range(int(sys.argv[2])):
    m.run(CPU_HZ//2)
    print("t+%.1f dxr=%d dspPC=%04X E3C=%02X E3B=%02X txt=%r"%(i/2+.5,d.dxr_head(),d.get('PC'),m.cpu.rd8(0xE3C),m.cpu.rd8(0xE3B),m.dte_text()))
print([(t,"%04X"%x,"%04X"%y) for t,x,y in m.cmd_log16][:40])
print("ovl loads",m.ovl_loads)
