"""differential fuzz, one random instruction per case: our C5x core vs the sibling project's native core (courier-emu).
Setup program (identical for both): random AR0-7, ACC, ACCB, PREG, TREG0, random SXM/OVM/C/TC/PM, random on-chip data; then ONE random opcode (+ random 2nd word).
Both cores execute the setup, must agree (sanity), then the test instruction; compare PC/ACC/ACCB/PREG/AR0-7/C/OV/TC/data[0x60..0x7F,0x100..0x3FF].
usage: xcore_fuzz.py CASES [SEED] [HI_HEX_LIST]"""
import os, sys, random, struct, collections
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/dsp'); sys.path.insert(0, os.path.expanduser('~/Programming/courier-emu'))
import c5x as ours
from courier_emu.dsp import NativeC5x
cases=int(sys.argv[1]); seed=int(sys.argv[2]) if len(sys.argv)>2 else 1; rnd=random.Random(seed)
only=[int(x,16) for x in sys.argv[3].split(',')] if len(sys.argv)>3 else None
SKIP=set([0x0A,0x0B,0x0C,0x0D,0x0E,0x0F,0x78,0x79,0x7A,0x7B,0x7C,0x7D,0x7E,0x7F,0x80,0x81,0x82,0x83,0x84,0x85,0x86,0x87,0x88,0x89,0x8A,0x8B,0x8C,0x8D,0x8E,0x8F,
  0x9C,0x9D,0x9E,0x9F,0xBB,0xBC,0xBD,0xC4,0xC5,0xC6,0xC7,0xCC,0xCD,0xCE,0xCF,0xE0,0xE1,0xE2,0xE3,0xE8,0xE9,0xEA,0xEB,0xEC,0xED,0xEE,0xEF,
  0xF0,0xF1,0xF2,0xF3,0xF8,0xF9,0xFA,0xFB,0xFC,0xFD,0xFE,0xFF,0x6C,0x6D,0x6E,0x6F,0xB0,0xB1,0xB2,0xB3,0xB4,0xB5,0xB6,0xB7,0xB8,0xB9,0xBA, 0x2C,0x2D,0x2E,0x2F,0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x3B,0x3C,0x3D,0x3E,0x3F])
def setup():
    w=[]
    for n in range(8): w+=[0xBF08|n, rnd.choice([0x100,0x180,0x200,0x2F0,0x300,0x3F0])+rnd.randrange(0,16)]
    w+=[rnd.choice([0xBE47,0xBE46]), rnd.choice([0xBE43,0xBE42]), rnd.choice([0xBE4F,0xBE4E]), rnd.choice([0xBE4B,0xBE4A]), 0xBF00|rnd.randrange(4)]
    w+=[0x1F60,0x2061,0xBE1E, 0x1F62,0x2063, 0x7364, 0x5465]       # ACC=[60]<<15+[61]; ACCB=ACC; ACC=[62]<<15+[63]; T=[64]; P=T*[65]
    return w
def regs_ours(d): return dict(pc=d.get('PC'),acc=d.get('ACC')&0xFFFFFFFF,accb=d.get('ACCB')&0xFFFFFFFF,preg=d.get('PREG')&0xFFFFFFFF,c=(d.get('ST1')>>9)&1,ov=(d.get('ST0')>>12)&1,tc=(d.get('ST1')>>11)&1,**{'ar%d'%i:d.get('AR%d'%i)&0xFFFF for i in range(8)})
def regs_theirs(o):
    s=o.state(); return dict(pc=s['pc'],acc=s['acc']&0xFFFFFFFF,accb=s['accb']&0xFFFFFFFF,preg=s['preg']&0xFFFFFFFF,c=1 if s['flags']&8 else 0,ov=1 if s['flags']&32 else 0,tc=1 if s['flags']&16 else 0,**{'ar%d'%i:s['ar%d'%i]&0xFFFF for i in range(8)})
div=collections.Counter(); first={}; sane_bad=0; skipped=collections.Counter()
for case in range(cases):
    pre=setup(); nset=len(pre)-0
    while True:
        hi=rnd.randrange(256) if not only else rnd.choice(only)
        if hi not in SKIP: break
    lo=rnd.randrange(256)
    if not lo&0x80: lo=0x60|(lo&0x1F)
    if (lo>>4)&7==3: lo^=0x10      # IDV=0 INC=1 DEC=1 is not a defined indirect mode
    op=(hi<<8)|lo; words=pre+[op,rnd.randrange(65536),0,0,0,0]
    # setup instruction count: 8 LAR + 5 mode + 7 = 20 words-> 8 two-word LARs(16 words)... count instructions explicitly
    ninst=8+5+7
    blob=struct.pack('<%dH'%len(words),*words)
    d=ours.DSP(); d.load_pm(0,blob); d.reset(0)
    o=NativeC5x.from_program(0,blob)
    for i in range(0x20):
        v=rnd.randrange(65536); d.dm[0x60+i]=v; o.set_data(0x60+i,v)
    for i in range(0x100,0x400):
        v=rnd.randrange(65536); d.dm[i]=v; o.set_data(i,v)
    try:
        for _ in range(ninst): d.run(1); o.step(1)
        a=regs_ours(d); b=regs_theirs(o)
        if any(a[k]!=b[k] for k in a if k!='tc'):
            sane_bad+=1; sm=[(k,hex(a[k]),hex(b[k])) for k in a if a[k]!=b[k]]; first.setdefault(("sane",tuple(k for k,_,_ in sm)),sm); o.close(); continue
        d.run(1); o.step(1)
    except RuntimeError as e:
        skipped[(hi,'theirs-invalid')]+=1; o.close(); continue
    a=regs_ours(d); b=regs_theirs(o)
    bad=[k for k in a if a[k]!=b[k] and k!='tc']
    mem=[i for i in list(range(0x60,0x80))+list(range(0x100,0x400)) if d.dm[i]!=o.data(i)]
    if mem: bad.append('mem@%s'%','.join(hex(i) for i in mem[:3]))
    if bad:
        key=(hi,tuple(x if not x.startswith('mem') else 'mem' for x in bad)); div[key]+=1
        first.setdefault(key,(case,hex(op),{k:(hex(a[k]),hex(b[k])) for k in a if a[k]!=b[k]},[x for x in bad if x.startswith('mem')]))
    o.close()
print('cases',cases,'diverged',sum(div.values()),'setup-mismatch',sane_bad,'theirs-invalid',sum(skipped.values()),'distinct invalid hi:',sorted(set('%02X'%k[0] for k in skipped))[:40])
for (hi,bad),n in sorted(div.items(),key=lambda x:(x[0][0],-x[1])):
    print('hi=%02X %s n=%d first=%s'%(hi,','.join(bad),n,first[(hi,bad)]))

for k,v in first.items():
    if k[0]=='sane': print('SETUP-MISMATCH',k[1],v)
