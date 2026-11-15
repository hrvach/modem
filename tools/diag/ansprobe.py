"""single machine ATA with E3C poked: report DSP output after command 14"""
import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
import collections
e3c=int(sys.argv[1],16); secs=int(sys.argv[2])
m=Machine(nvram_mode=None); m.logging=False
m.run(7*CPU_HZ); m.send("AT\r"); m.run(CPU_HZ); m.dte_text()
m.dsp.pc_hits_clear(); m.cpu.wr8(0xE3C,e3c); m.cmd_log16.clear(); m.send("ATA\r"); d=m.dsp
for i in range(secs):
    m.run(CPU_HZ); x=m.tx_all[-7200:]; pcs=collections.Counter(d.recent_pcs(200))
    print('hits 9E45=%d 9EA4=%d 80E1=%d 80E5=%d 80F8=%d 810B=%d 80C8=%d dm31A/B=%04X %04X'%tuple([d.pc_hits(a) for a in (0x9E45,0x9EA4,0x80E1,0x80E5,0x80F8,0x810B,0x80C8)]+[d.dm[0x31A],d.dm[0x31B]])); print("t+%d peak=%d dspPC=%04X ovl=%s top=%s txt=%r"%(i+1,max(map(abs,x)) if x else 0,d.get('PC'),[hex(a) for _,a,_ in m.ovl_loads][-3:],[('%04X'%p,c) for p,c in pcs.most_common(3)],m.dte_text()[-30:]))
print([(t,"%04X"%x,"%04X"%y) for t,x,y in m.cmd_log16][-6:])

import wave,struct
x=m.tx_all[-secs*7200:]
with wave.open('/tmp/claude-1000/-home-hrvoje-Programming-USR/831d3a18-6a9c-4288-84f9-a85e9135fc6f/scratchpad/ans.wav','wb') as w: w.setnchannels(1); w.setsampwidth(2); w.setframerate(7200); w.writeframes(struct.pack('<%dh'%len(x),*x))
print("ALLCMDS",[(round(t/7200,2),"%04X"%a,"%04X"%b) for t,a,b in m.cmd_log16])
