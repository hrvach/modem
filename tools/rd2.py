"""Segment-aware recursive descent for the SV25 flash image.
Physical address = seg*16+off; flash offset = phys - 0x80000 (flash mapped at 0x80000)."""
from capstone import *
from capstone.x86 import *
import struct,collections
md=Cs(CS_ARCH_X86,CS_MODE_16);md.detail=True
FLASH_BASE=0x80000
BADM={'int3','into','hlt','insb','insw','outsb','outsw','salc','aam','aad','daa','das','aaa','aas','arpl','bound','enter','lock','wait','icebp','sysret','syscall','cmpxchg','xadd','bswap'}
def bad(i):return i.mnemonic in BADM or i.mnemonic.startswith('f') and i.mnemonic not in('fs',)

class Dis:
    def __init__(s,flash):
        s.f=flash;s.ins={};s.seg_of={}   # flash_off -> insn ; -> cs
        s.funcs=collections.OrderedDict();s.edges=[];s.xtabs=[];s.far_targets=collections.Counter()
    def phys2fl(s,seg,off):
        p=(seg*16+(off&0xffff));o=p-FLASH_BASE
        return o if 0<=o<len(s.f) else None
    def dec(s,seg,off):
        o=s.phys2fl(seg,off)
        if o is None:return None
        for i in md.disasm(s.f[o:o+16],off&0xffff):return i
    def plausible(s,seg,off,n=6):
        a=off;k=0
        while k<n:
            i=s.dec(seg,a)
            if i is None or bad(i):return False
            if i.mnemonic in('ret','retf','jmp','iret','ljmp'):return k>=1 or i.mnemonic in('ret','retf','iret')
            a+=i.size;k+=1
        return True
    def run(s,entries):
        work=[(seg,off) for seg,off in entries]
        for e in entries:s.funcs.setdefault(e,'entry')
        while work:
            seg,off=work.pop()
            while True:
                o=s.phys2fl(seg,off)
                if o is None or o in s.ins:break
                i=s.dec(seg,off)
                if i is None or bad(i):break
                s.ins[o]=i;s.seg_of[o]=seg;m=i.mnemonic;b=i.bytes
                nxt=(off+i.size)&0xffff
                if m in('ret','retf','iret','lret'):break
                if b[0] in(0xea,0x9a):             # far jmp/call
                    t=(struct.unpack('<H',b[3:5])[0],struct.unpack('<H',b[1:3])[0])
                    s.far_targets[t]+=1
                    if b[0]==0x9a:
                        s.edges.append(((seg,off),t))
                        if t not in s.funcs:s.funcs[t]='far';work.append(t)
                        off=nxt;continue
                    else:
                        if t not in s.funcs:s.funcs[t]='farjmp';work.append(t)
                        break
                imm=i.operands[0].imm&0xffff if i.operands and i.operands[0].type==X86_OP_IMM else None
                if m=='call':
                    if imm is not None:
                        s.edges.append(((seg,off),(seg,imm)))
                        if (seg,imm) not in s.funcs:s.funcs[(seg,imm)]='near';work.append((seg,imm))
                    elif 'cs:[' in i.op_str:s.xtabs.append((seg,off,i))
                elif m=='jmp':
                    if imm is not None:work.append((seg,imm))
                    elif 'cs:[' in i.op_str:s.xtabs.append((seg,off,i))
                    break
                elif m.startswith('j') or m.startswith('loop'):
                    if imm is not None:work.append((seg,imm))
                if m=='hlt':break
                off=nxt
    def seed_tables(s,maxn=64):
        """indirect jmp/call via cs:[reg+K]: read words at cs:K, accept while plausible code."""
        import re,collections
        new=[];seen=set()
        for seg,off,i in s.xtabs:
            m=re.search(r'\[(?:(bx|si|di|bp)(?: \+ (bx|si|di))?)? ?\+? ?(0x[0-9a-f]+)?\]',i.op_str)
            mm=re.search(r'cs:\[(.*)\]',i.op_str)
            if not mm:continue
            parts=[p.strip() for p in mm.group(1).split('+')]
            K=[int(p,16) for p in parts if p.startswith('0x')]
            if not K:continue
            k=K[0]
            if (seg,k) in seen:continue
            seen.add((seg,k));o=s.phys2fl(seg,k)
            if o is None:continue
            for n in range(maxn):
                if o+2*n+2>len(s.f):break
                t=struct.unpack('<H',s.f[o+2*n:o+2*n+2])[0]
                if not s.plausible(seg,t):break
                new.append((seg,t));s.funcs.setdefault((seg,t),'table')
        return new
