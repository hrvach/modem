import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(7*CPU_HZ); m.send("AT\r"); m.run(CPU_HZ); m.send("ATQ0V1\r"); m.run(CPU_HZ); print(m.dte_text()[-30:])
m.cmd_log16.clear(); m.send(sys.argv[1]+"\r")
h0=m.hb_count
for i in range(int(sys.argv[2])):
    m.run(CPU_HZ//2); d=m.dsp
    print("t+%.1f samp=%d dxr=%d dspPC=%04X idle=%d txt=%r E3C=%04X"%(i/2+.5,m.hb_count-h0,d.dxr_head(),d.get('PC'),d.idle_cycles(),m.dte_text(),m.cpu.rd16(0xE3C)))
print("cmds:",[(t,"%04X"%x,"%04X"%y) for t,x,y in m.cmd_log16][-12:])
print(d.state()); print(["%04X"%p for p in d.recent_pcs(48)])
x=m.tx_all[-int(sys.argv[2])*3600:]
print("peak",max(map(abs,x)), "first nonzero at +%.2fs"%(next((i for i,v in enumerate(x) if abs(v)>500),-1)/7200))
i0=next((i for i,v in enumerate(x) if abs(v)>500),0); print(x[i0+3600:i0+3640])
print("dm60:",["%04X"%d.dm[i] for i in range(0x60,0x6C)])
