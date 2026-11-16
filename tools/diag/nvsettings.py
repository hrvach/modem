"""write the six settings records (EEPROM words 94..102, RAM 0752..0763) into an NVRAM image and fix the checksum byte.
Record layout (supervisor 7.3.14 decoder at flash 0xE237, same as courier-emu IDSDL302): three redundant obfuscated copies of one byte, stored in the order settings 2,3,4,5,6,1.
Setting 2 is the feature bitmap the ATI7 'Options' line is built from (bit1->[89D]&8, bit2->&0x40, bit3->&0x80, bit4->&0x20 = 'x2,V90').
usage: nvsettings.py IN.bin OUT.bin [v1 v2 v3 v4 v5 v6]   (default 0 30 7 30 0 0, values recovered from a running 20.16 MHz Courier)"""
import sys
def enc(v):
    a=(v-5)&0xFF; a=((a<<2)|(a>>6))&0xFF
    b=(v+0x0F)&0xFF; b=((b>>1)|(b<<7))&0xFF
    return bytes((a,b,v^0x1D))
src,dst=sys.argv[1],sys.argv[2]; vals=[int(x) for x in sys.argv[3:]] or [0,30,7,30,0,0]
d=bytearray(open(src,'rb').read()); assert len(d)==512
blob=b''.join(enc(vals[i]) for i in (1,2,3,4,5,0)); d[94*2:94*2+18]=blob
d[511]=sum(d[:510])&0xFF
open(dst,'wb').write(d); print('settings',vals,'-> words 94..102 =',blob.hex(),'checksum byte %02X'%d[511])
