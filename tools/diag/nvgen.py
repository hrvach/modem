"""create a NVRAM image the firmware itself writes: boot with blank EEPROM, AT&F, AT&W, dump. usage: nvgen.py out.bin [extra AT commands...]"""
import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(7*CPU_HZ); print(m.dte_text()[-200:])
for c in ['AT','AT&F']+sys.argv[2:]+['AT&W']:
    m.send(c+"\r"); m.run(CPU_HZ*2); print(c,'->',m.dte_text()[-40:])
img=m.eeprom.image(); open(sys.argv[1],'wb').write(img)
print('dirty',m.eeprom.dirty,'ewen',m.eeprom.ewen,'nonFF words',sum(1 for x in m.eeprom.w if x!=0xFFFF),'len',len(img))
