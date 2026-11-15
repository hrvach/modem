import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(7*CPU_HZ); m.send("AT\r"); m.run(CPU_HZ); m.send("ATA\r"); d=m.dsp
m.run(12*CPU_HZ)
print(d.state())
for i in range(10):
    r=d.run(1); print(r,'RPTC',d.get('RPTC'),'IDLE',d.get('IDLE'),"PC=%04X IFR=%04X IMR=%04X ST0=%04X SP=%s st=%s"%(d.get('PC'),d.get('IFR'),d.get('IMR'),d.get('ST0'),d.get('SP'),d.get('STK0') if 'STK0' in c5x.REG else ''))
print({k:v for k,v in c5x.REG.items() if 'S' in k[:2]})

print('pm81A8..',['%04X'%d.pm[a] for a in range(0x81A8,0x81B6)]); print('dm60',['%04X'%d.dm[a] for a in range(0x60,0x6C)]); print('mmr21',hex(d.dm[0x21]),'SP',d.get('SP'))

for i in range(3):
    t0=d.total_cycles(); r=d.run(5); print('run5',r,'cycles',d.total_cycles()-t0,'PC=%04X'%d.get('PC'),'SP',d.get('SP'),'ST0=%04X'%d.get('ST0'))

d.run(3); print(['%04X'%p for p in d.recent_pcs(10)]); print('IFR %04X IMR %04X'%(d.get('IFR'),d.get('IMR')))

print('TIM %04X PRD %04X TCR(dm26) %04X dm24 %04X dm25 %04X'%(d.get('TIM'),d.get('PRD'),d.dm[0x26],d.dm[0x24],d.dm[0x25]))
