import sys
from capstone import *
md=Cs(CS_ARCH_X86,CS_MODE_16)
img=open('/home/hrvoje/Programming/USR/SV25.flash.bin','rb').read()
def dis(off,n=40,seg=None):
    if seg is None:
        seg=0x8000 if off<0xF460 else (0x8F46 if off<0x21100 else 0xA110)
    base=off-((seg*16)-0x80000)
    k=0
    for i in md.disasm(img[off:off+n*6],off-(seg*16-0x80000)):
        print("%06x %04x:%04x %-20s %s %s"%(i.address+(seg*16-0x80000),seg,i.address,i.bytes.hex(),i.mnemonic,i.op_str)); k+=1
        if k>=n: break
if __name__=='__main__':
    off=int(sys.argv[1],16); n=int(sys.argv[2]) if len(sys.argv)>2 else 40
    seg=int(sys.argv[3],16) if len(sys.argv)>3 else None
    dis(off,n,seg)
