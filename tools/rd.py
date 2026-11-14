"""Recursive-descent 16-bit x86 disassembler over a flat image (capstone)."""
from capstone import *
from capstone.x86 import *
md=Cs(CS_ARCH_X86,CS_MODE_16);md.detail=True
def disasm(img,base,entries,limit,names=None):
    """img: bytes of the segment; base: address of img[0]; returns dict addr->insn, set of functions, edges."""
    ins={};funcs=set(entries);work=list(entries);edges=[]
    def fetch(a):
        o=a-base
        if o<0 or o>=len(img):return None
        for i in md.disasm(img[o:o+16],a):return i
    while work:
        a=work.pop()
        while a not in ins:
            i=fetch(a)
            if i is None or a>=limit:break
            ins[a]=i;m=i.mnemonic
            def tgt():
                if i.operands and i.operands[0].type==X86_OP_IMM:return i.operands[0].imm&0xffff
            if m in('ret','retf','iret','lret'):break
            if m=='call':
                t=tgt()
                if t is not None:
                    edges.append((a,t));
                    if t not in funcs:funcs.add(t);work.append(t)
            elif m in('jmp',):
                t=tgt()
                if t is not None and t not in ins:work.append(t)
                break
            elif m in('ljmp','hlt'):break
            elif m.startswith('j') or m.startswith('loop') or m=='jcxz':
                t=tgt()
                if t is not None and t not in ins:work.append(t)
            a+=i.size
    return ins,funcs,edges
