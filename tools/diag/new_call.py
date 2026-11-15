import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
from machine import CPU_HZ
fs=7200; dur=float(sys.argv[1])
L=Link(); L.run(8*CPU_HZ); 
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
print("setup:",L.txt)
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0; mm.cmd_log16.clear(); mm.dsp_log.clear()
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(dur*fs): L.run(10_000_000)
print("events:",[(round(t,2),s) for t,s in L.events]); print(L.txt)
for nm,mm in (('A',L.a),('B',L.b)):
    c=mm.cpu
    print(nm,"cmds:",[(round(t/fs,2),"%04X"%x,"%04X"%y) for t,x,y in mm.cmd_log16][:120])
    print(nm,"audio",len(L.audio[nm.lower()]),"pc=%05X dspPC=%04X E3C=%04X EA7=%02X E88=%02X 134=%04X under=%d"%(c.phys_pc(),mm.dsp.get('PC'),c.rd16(0xE3C),c.rd8(0xEA7),c.rd8(0xE88),c.rd16(0x134),mm.rx_under), mm.icu_state(), dict(mm.irq_count))
    print(nm, "recent:", ["%05X"%x for x in c.recent(16)])
d=L.a.dsp
print("A dsp:",d.state()); print(["%04X"%p for p in d.recent_pcs(64)])
h=d.dxr_head(); L.run(3_000_000); print("dxr advance in 3M cycles:", d.dxr_head()-h, "hb", L.a.hb_count, L.b.hb_count, "PC %04X"%d.get('PC'))
print(["%04X"%p for p in d.recent_pcs(40)])
import struct,wave
for k in 'ab':
    x=L.audio[k]
    with wave.open('/home/hrvoje/Programming/USR/out/new1/diag_%s.wav'%k,'wb') as w: w.setnchannels(1); w.setsampwidth(2); w.setframerate(7200); w.writeframes(struct.pack('<%dh'%len(x),*x))
print("dm60:",["%04X"%d.dm[i] for i in range(0x60,0x70)], "timer TIM/PRD/TCR", ["%04X"%d.dm[i] for i in (0x24,0x25,0x26)], "SPC %04X"%d.dm[0x22])
for i in range(6):
    d.run(1); print("step PC=%04X IFR=%04X IMR=%04X ST0=%04X SP=%s"%(d.get('PC'),d.get('IFR'),d.get('IMR'),d.get('ST0'),d.get('SP')))
