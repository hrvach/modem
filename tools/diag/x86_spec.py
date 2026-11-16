"""spec checks of our i186 core against the mathematical definitions (no sibling): ALU flags, shifts/rotates by 1, DAA/DAS/AAA/AAS, RET imm, PUSH SP.
usage: x86_spec.py [N]"""
import os, sys, random, ctypes as C
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")); sys.path.insert(0, ROOT+'/sys')
import i186
N=int(sys.argv[1]) if len(sys.argv)>1 else 2000; rnd=random.Random(5)
def run(code, **regs):
    c=i186.CPU(); c.cycle_model(1); c.ud_trap(1); c.reset(); c.load(0x20000,bytes(code)+bytes(8))
    for r in ('SS','DS','ES'): c.set(r,0x1000)
    c.set('CS',0x2000); c.set('IP',0); c.set('SP',0x8000); c.set('FLAGS',2|regs.pop('FL',0))
    for r,v in regs.items(): c.set(r,v)
    c.run(1); return c
def par(v): return bin(v&0xFF).count('1')%2==0
def fl(c): f=c.get('FLAGS'); return dict(CF=f&1,PF=(f>>2)&1,AF=(f>>4)&1,ZF=(f>>6)&1,SF=(f>>7)&1,OF=(f>>11)&1)
bad={}
def chk(name,got,exp,info):
    for k,v in exp.items():
        if got[k]!=v: bad.setdefault((name,k),[]).append((info,got[k],v))
for _ in range(N):
    for w,mask,sign in ((0,0xFF,0x80),(1,0xFFFF,0x8000)):
        a=rnd.choice([rnd.randrange(mask+1),mask,0,sign,sign-1,0x0F,0x10,1]); b=rnd.choice([rnd.randrange(mask+1),mask,0,sign,1,0x0F]); cf=rnd.randrange(2)
        for name,op,fn in (('ADD',0x00,lambda a,b,c:a+b),('ADC',0x10,lambda a,b,c:a+b+c),('SUB',0x28,lambda a,b,c:a-b),('SBB',0x18,lambda a,b,c:a-b-c),('CMP',0x38,lambda a,b,c:a-b)):
            sub=op in (0x28,0x18,0x38); cin=cf if op in (0x10,0x18) else 0
            r=fn(a,b,cin); res=r&mask
            # AL/AX,imm form: opcode op+4+w
            code=[op+4+w, b&0xFF]+([b>>8] if w else [])
            c=run(code,AX=a,FL=cf); g=fl(c)
            carry=int(r>mask) if not sub else int(r<0)
            af=((a^b^res)&0x10)>>4
            of=int(((a^b)&(a^res)&sign)!=0) if sub else int(((a^res)&(b^res)&sign)!=0)
            chk(name+str(8<<w),g,dict(CF=carry,AF=af,OF=of,ZF=int(res==0),SF=int(res&sign!=0),PF=int(par(res))),(hex(a),hex(b),cf))
            if name!='CMP': 
                got=c.get('AX')&mask
                if got!=res: bad.setdefault((name+str(8<<w),'RESULT'),[]).append(((hex(a),hex(b),cf),got,res))
        # shifts/rotates by 1 (D0/D1 on AL/AX)
        a=rnd.randrange(mask+1)
        for sub,name in enumerate(('ROL','ROR','RCL','RCR','SHL','SHR','SAL','SAR')):
            c=run([0xD0|w,0xC0|(sub<<3)],AX=a,FL=cf); g=fl(c); res=c.get('AX')&mask; bits=8<<w
            if sub==0: e=((a<<1)|(a>>(bits-1)))&mask; ec=a>>(bits-1); eo=((e>>(bits-1))&1)^ec
            elif sub==1: e=((a>>1)|((a&1)<<(bits-1)))&mask; ec=a&1; eo=((e>>(bits-1))^(e>>(bits-2)))&1
            elif sub==2: e=((a<<1)|cf)&mask; ec=a>>(bits-1); eo=((e>>(bits-1))&1)^ec
            elif sub==3: e=((a>>1)|(cf<<(bits-1)))&mask; ec=a&1; eo=((e>>(bits-1))^(e>>(bits-2)))&1
            elif sub in (4,6): e=(a<<1)&mask; ec=a>>(bits-1); eo=((e>>(bits-1))&1)^ec
            elif sub==5: e=a>>1; ec=a&1; eo=a>>(bits-1)
            else: e=(a>>1)|(a&sign); ec=a&1; eo=0
            ex=dict(CF=ec,OF=eo)
            if sub>=4: ex.update(ZF=int(e==0),SF=int(e&sign!=0),PF=int(par(e)))
            chk(name+str(bits),g,ex,(hex(a),cf))
            if res!=e: bad.setdefault((name+str(bits),'RESULT'),[]).append(((hex(a),cf),res,e))
# decimal adjust
for al in range(256):
    for cf in (0,1):
        for af in (0,1):
            f=cf|(af<<4)
            c=run([0x27],AX=al,FL=f); r=c.get('AX')&0xFF; g=fl(c); a0=al; ecf=cf; l=al
            if (l&0xF)>9 or af: l+=6; ecf=ecf|(l>0xFF); l&=0xFF; eaf=1
            else: eaf=0
            if a0>0x99 or cf: l=(l+0x60)&0xFF; ecf=1
            chk('DAA',dict(CF=g['CF'],AF=g['AF'],AX=r),dict(CF=ecf,AF=eaf,AX=l),(hex(al),cf,af))
            c=run([0x2F],AX=al,FL=f); r=c.get('AX')&0xFF; g=fl(c); l=al; ecf=cf; eaf=0
            if (l&0xF)>9 or af: ecf=ecf|(l<6); l=(l-6)&0xFF; eaf=1
            if al>0x99 or cf: l=(l-0x60)&0xFF; ecf=1
            chk('DAS',dict(CF=g['CF'],AF=g['AF'],AX=r),dict(CF=ecf,AF=eaf,AX=l),(hex(al),cf,af))
# RET imm / PUSH SP
c=run([0xC2,0x06,0x00]); 
mem=lambda c,a,v: [c.wr8(a+i,(v>>(8*i))&0xFF) for i in range(2)]
c=i186.CPU(); c.cycle_model(1); c.ud_trap(1); c.reset(); c.load(0x20000,bytes([0xC2,0x06,0x00])); mem(c,0x18000,0x1234)
for r in ('SS','DS','ES'): c.set(r,0x1000)
c.set('CS',0x2000); c.set('IP',0); c.set('SP',0x8000); c.run(1); print("RET 6 : IP=%04X SP=%04X (expect 1234 / 8008)"%(c.get('IP'),c.get('SP')))
c=run([0x54]); print("PUSH SP: pushed %02X%02X (80186: old SP 8000)"%(c.mem[0x17FFF],c.mem[0x17FFE]))
for k,v in sorted(bad.items()): print(k,len(v),v[:2])
print("spec checks done, failing groups:",len(bad))
