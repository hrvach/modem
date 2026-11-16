"""let a firmware build its own NVRAM: boot with a blank EEPROM, send AT&F / AT+SF / AT&W, save the EEPROM contents. usage: mknvram.py OUT.bin [extra AT commands...]
env: FLASH, CPU_HZ, DSP_HZ as for the machine; the blank image is created here."""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
out=sys.argv[1]; extra=sys.argv[2:]
blank='/tmp/blank_nvram.bin'; open(blank,'wb').write(b'\xff'*512); os.environ['NVRAM']=blank
sys.path.insert(0, ROOT+'/sys')
from machine import *
m=Machine(nvram_mode=None); m.logging=False
m.run(int(8*CPU_HZ)); m.dte_text()
for c in ["AT\r","AT&F\r","AT+SF\r","AT&W\r"]+[x+"\r" for x in extra]:
    m.send(c); m.run(int(2*CPU_HZ)); t=m.dte_text(); print(repr(c),'->',t[:80])
ee=m.eeprom; data=bytearray()
for w in ee.w: data+=bytes([w&0xFF,w>>8])
open(out,'wb').write(data)
nz=sum(1 for w in ee.w if w!=0xFFFF); print('EEPROM words programmed:',nz,'of',len(ee.w),'dirty',ee.dirty,'->',out)
