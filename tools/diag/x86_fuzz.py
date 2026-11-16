"""differential fuzz, one random instruction per case: our i186 core vs the sibling's courier_emu.x86_interpreter (Python reference).
Both start from identical random registers / memory / IVT; compare AX..DI, segments, IP, FLAGS (mask FLAGMASK) and the memory window.
usage: x86_fuzz.py CASES [SEED] [OPCODE_HEX_LIST]; env FLAGMASK (default 0x0FD5), NATIVE=1 uses the sibling's native engine"""
import os, sys, random, collections, ctypes as C
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys'); sys.path.insert(0, os.path.expanduser('~/Programming/courier-emu'))
os.environ.setdefault('COURIER_X86_NATIVE', os.environ.get('NATIVE', '0'))
import i186
from courier_emu import x86_interpreter as X
cases=int(sys.argv[1]); seed=int(sys.argv[2]) if len(sys.argv)>2 else 1; only=[int(x,16) for x in sys.argv[3].split(',')] if len(sys.argv)>3 else None
FM=int(os.environ.get('FLAGMASK','0x0FD5'),16); rnd=random.Random(seed)
SKIP={0xE4,0xE5,0xE6,0xE7,0xEC,0xED,0xEE,0xEF,0x6C,0x6D,0x6E,0x6F,0xCC,0xCD,0xCE,0xCF,0xF4,0x9B,0xF0,0xD8,0xD9,0xDA,0xDB,0xDC,0xDD,0xDE,0xDF,0x0F,0x63,0x64,0x65,0x66,0x67,0xD6,0xF1,}
SKIP|={0x62,0x8F,0xC4,0xC5,0xF2,0xF3,0xA4,0xA5,0xA6,0xA7,0xAA,0xAB,0xAC,0xAD,0xAE,0xAF}   # sibling raises UcError for these forms / steps REP per iteration
SEGS=dict(ES=0x1000,SS=0x1000,DS=0x1000,CS=0x2000)
REGS=['AX','CX','DX','BX','SP','BP','SI','DI']
OURS_R=dict(AX='AX',CX='CX',DX='DX',BX='BX',SP='SP',BP='BP',SI='SI',DI='DI',ES='ES',CS='CS',SS='SS',DS='DS',IP='IP',FLAGS='FLAGS')
THEIR={'AX':X.UC_X86_REG_AX,'CX':X.UC_X86_REG_CX,'DX':X.UC_X86_REG_DX,'BX':X.UC_X86_REG_BX,'SP':X.UC_X86_REG_SP,'BP':X.UC_X86_REG_BP,'SI':X.UC_X86_REG_SI,'DI':X.UC_X86_REG_DI,'ES':X.UC_X86_REG_ES,'CS':X.UC_X86_REG_CS,'SS':X.UC_X86_REG_SS,'DS':X.UC_X86_REG_DS,'IP':X.UC_X86_REG_IP,'FLAGS':X.UC_X86_REG_FLAGS}
mism=collections.Counter(); ex={}; ncase=collections.Counter()
for case in range(cases):
    REP=os.environ.get('REP')=='1'
    op=rnd.choice([0xA4,0xA5,0xA6,0xA7,0xAA,0xAB,0xAC,0xAD,0xAE,0xAF,0xD7,0xC8,0xC9,0x60,0x61,0x69,0x6B,0x68,0x6A,0x9E,0x9F,0x98,0x99,0xD4,0xD5,0x37,0x3F]) if REP else rnd.choice(only) if only else rnd.choice([o for o in range(256) if o not in SKIP])
    pre=[rnd.choice([0x26,0x2E,0x36,0x3E])] if rnd.random()<0.15 else []
    if REP and op in (0xA4,0xA5,0xA6,0xA7,0xAA,0xAB,0xAC,0xAD,0xAE,0xAF) and rnd.random()<0.7: pre.append(rnd.choice([0xF2,0xF3]))
    code=bytes(pre+[op]+[rnd.randrange(256) for _ in range(6)])
    regs={r:rnd.choice([rnd.randrange(0x10000),rnd.randrange(16),0xFFFF,0x8000,0x7FFF,0x100*rnd.randrange(256)]) for r in REGS}
    regs['SP']=rnd.choice([0x8000,0x8002,0xFFF0,0x100,0x7FFE]); 
    if rnd.random()<0.3 or REP: regs['CX']=rnd.randrange(0,7)
    for r in ('BX','SI','DI','BP'): regs[r]=rnd.randrange(0x4000,0xC000) if rnd.random()<0.8 else regs[r]
    flags=2|(rnd.randrange(0x1000)&0x0FD5)&~0x300   # no TF/IF
    seg=bytes(rnd.randrange(256) for _ in range(0x10000)); ivt=bytes(rnd.choice([0,0x20,0x40]) if i%4 in (1,3) else rnd.randrange(256) for i in range(0x400))
    # ours
    c=i186.CPU(); c.cycle_model(1); c.ud_trap(1); c.reset()
    base=C.addressof(c.mem.contents); C.memmove(base+0x10000,seg,len(seg)); C.memmove(base,ivt,len(ivt)); C.memmove(base+0x20000,code,len(code))
    for r,v in regs.items(): c.set(r,v)
    for r,v in SEGS.items(): c.set(r,v)
    c.set('IP',0); c.set('FLAGS',flags)
    st=c.run(1)
    # theirs
    u=X.Uc(X.UC_ARCH_X86,X.UC_MODE_16,profile='186eb'); u.mem_map(0,0x100000)
    u.mem_write(0x10000,seg); u.mem_write(0,ivt); u.mem_write(0x20000,code)
    for r,v in {**regs,**SEGS,'IP':0,'FLAGS':flags}.items(): u.reg_write(THEIR[r],v)
    try:
        u.emu_start(0x20000,0x20100,count=1); err=None
        for _ in range(12):
            if u.reg_read(THEIR['IP'])!=0: break
            u.emu_start(0x20000,0x20100,count=1)
    except Exception as e: err=repr(e)[:60]
    key=(code[len(pre)] if True else 0); sub=(code[len(pre)+1]>>3)&7 if op in (0x80,0x81,0x82,0x83,0xC0,0xC1,0xD0,0xD1,0xD2,0xD3,0xF6,0xF7,0xFE,0xFF) else None
    tag=(op,sub); ncase[tag]+=1
    m=FM; o=op; sb=sub
    if o in (0x08,0x09,0x0A,0x0B,0x0C,0x0D,0x20,0x21,0x22,0x23,0x24,0x25,0x30,0x31,0x32,0x33,0x34,0x35,0x84,0x85,0xA8,0xA9) or (o in (0x80,0x81,0x82,0x83) and sb in (1,4,6)) or (o in (0xF6,0xF7) and sb in (0,1)): m&=~0x10          # AF undefined after logic ops
    if o in (0xC0,0xC1,0xD0,0xD1,0xD2,0xD3):
        m&=~0x10
        cnt=1 if o in (0xD0,0xD1) else (code[len(pre)+2+ (1 if (code[len(pre)+1]>>6)==1 else 2 if (code[len(pre)+1]>>6)==2 or (code[len(pre)+1]&0xC7)==6 else 0)] if o in (0xC0,0xC1) else regs['CX']&0xFF)&31
        if cnt!=1: m&=~0x800
        if sb in (0,1,2,3): m&=~0x10|0x0FC5&~0x0FC5|0x801 & 0x801 if False else m
        if sb in (0,1,2,3): m&=0x801|(~0x0FD5)
    if o in (0xF6,0xF7) and sb in (4,5): m&=~0xD4
    if o in (0xF6,0xF7) and sb in (6,7): m&=~0x8D5
    if o in (0xD4,0xD5): m&=~0x810
    if o in (0x27,0x2F,0x37,0x3F): m&=~0x800
    diffs=[]
    for r in OURS_R:
        a=c.get(r); b=u.reg_read(THEIR[r])
        if r=='FLAGS': a&=m; b&=m
        if a!=b: diffs.append((r,a,b))
    ma=C.string_at(base+0x10000,0x10000); mb=bytes(u.memory[0x10000:0x20000])
    if ma!=mb: diffs.append(('MEM',next(i for i in range(0x10000) if ma[i]!=mb[i]),0))
    if C.string_at(base,0x400)!=bytes(u.memory[0:0x400]): diffs.append(('IVT',0,0))
    if err: diffs.append(('ERR',err,''))
    if diffs:
        mism[tag]+=1
        if tag not in ex: ex[tag]=(code.hex(),regs,hex(flags),diffs[:5])
print("cases",cases,"mismatching opcode tags:",len(mism))
for tag,n in sorted(mism.items()):
    print("%02X%s: %d/%d  e.g. code=%s flags_in=%s diffs=%s"%(tag[0],'' if tag[1] is None else '/%d'%tag[1],n,ncase[tag],ex[tag][0],ex[tag][2],[(d[0],hex(d[1]) if isinstance(d[1],int) else d[1],hex(d[2]) if isinstance(d[2],int) else d[2]) for d in ex[tag][3]]))
