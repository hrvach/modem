"""replay the ov6 exit test (9F6C..9FA2) on captured inputs in a standalone DSP and print a per-instruction trace (PC, ACC, ACCB, PREG, ST0/ST1 flags). usage: replay9f6c.py JSON IDX"""
import os, sys, json, struct; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/dsp')
import c5x
rec=json.load(open(sys.argv[1]))[int(sys.argv[2])]
d=c5x.DSP(); d.reset(0x9F6C)
ov=open(ROOT+'/dsp/dsp_ov6.bin','rb').read()
for i in range(len(ov)//2): d.pm[0x9D00+i]=ov[2*i]|(ov[2*i+1]<<8)
t,a,b,ctr,st1,st0=rec
for i,v in enumerate(a): d.dm[0x300+i]=v
for i,v in enumerate(b[:4]): d.dm[0x330+i]=v
d.dm[0x334]=b[4]
d.set('ST0',st0); d.set('ST1',st1)
asm={}
for l in open(ROOT+'/dsp/dsp_ov6.asm'):
    p=l.split(None,1)
    if len(p)==2 and len(p[0])==4:
        try: asm[int(p[0],16)]=p[1].rstrip()[:60]
        except: pass
print('inputs a=',a,'b=',b,'counter=',b[4],'ST0=%04X ST1=%04X'%(st0,st1))
def s32(x): x&=0xFFFFFFFF; return x-(1<<32) if x>=1<<31 else x
for n in range(44):
    pc=d.get('PC')
    print('%04X %-52s ACC=%08X ACCB=%08X P=%08X'%(pc,asm.get(pc,''),d.get('ACC')&0xFFFFFFFF,d.get('ACCB')&0xFFFFFFFF,d.get('PREG')&0xFFFFFFFF))
    d.run(1)
    if d.get('PC') in (0x9FA2,): print('-> reached 9FA2 (pass path)'); break
    if pc==0x9FA0: print('-> executed 9FA0 splk (fail/reset). [334]=',d.dm[0x334]); break
print('[334] after =',d.dm[0x334])
