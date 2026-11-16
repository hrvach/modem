"""(OR/XOR imm,r/m: the manual prints 4/10, read-modify-write like AND/ADD is 16; 16 is used.) compare the 80186 core's per-instruction clock counts (CPU model 1) with the 80C186EB manual Table D-2 (memory forms, 16-bit, fastest case). usage: i186time.py [model]"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from i186 import CPU
T=[ # name, bytes, manual clocks (single value or (lo,hi)), setup dict
("mov r,r 89 C8",[0x89,0xC8],2),("mov [bx],ax 89 07",[0x89,0x07],12),("mov ax,[bx] 8B 07",[0x8B,0x07],9),
("mov r16,imm B8",[0xB8,1,0],4),("mov [bx],imm C7 07",[0xC7,0x07,1,0],13),("mov ax,[addr] A1",[0xA1,0,1],9),("mov [addr],ax A3",[0xA3,0,1],8),
("mov sreg,[bx] 8E 07",[0x8E,0x07],9),("mov [bx],sreg 8C 07",[0x8C,0x07],11),
("push r 50",[0x50],10),("pop r 58",[0x58],10),("push [bx] FF 37",[0xFF,0x37],16),("pop [bx] 8F 07",[0x8F,0x07],20),("push sreg 06",[0x06],9),("pop sreg 07",[0x07],8),("push imm 68",[0x68,1,0],10),
("pusha 60",[0x60],36),("popa 61",[0x61],51),("xchg [bx],ax 87 07",[0x87,0x07],17),("xchg ax,r 93",[0x93],3),("xlat D7",[0xD7],11),
("in al,imm E4",[0xE4,0x10],10),("in al,dx EC",[0xEC],8),("out imm,al E6",[0xE6,0x10],9),("out dx,al EE",[0xEE],7),
("lea 8D 07",[0x8D,0x07],6),("lds C5 07",[0xC5,0x07],18),("les C4 07",[0xC4,0x07],18),("leave C9",[0xC9],8),("lahf 9F",[0x9F],2),("sahf 9E",[0x9E],3),("pushf 9C",[0x9C],9),("popf 9D",[0x9D],8),
("add r,r 01 D8",[0x01,0xD8],3),("add [bx],ax 01 07",[0x01,0x07],10),("add ax,[bx] 03 07",[0x03,0x07],10),("add r,imm 83 C0",[0x83,0xC0,1],4),("add [bx],imm 83 07",[0x83,0x07,1],16),
("or [bx],imm 83 0F",[0x83,0x0F,1],16),("and [bx],imm 83 27",[0x83,0x27,1],16),("cmp [bx],imm 83 3F",[0x83,0x3F,1],10),("cmp r,[bx] 3B 07",[0x3B,0x07],10),("add ax,imm8 04",[0x04,1],3),("add ax,imm16 05",[0x05,1,0],4),
("inc r 40",[0x40],3),("dec r 48",[0x48],3),("inc [bx] FF 07",[0xFF,0x07],15),("dec [bx] FF 0F",[0xFF,0x0F],15),("neg r F7 D8",[0xF7,0xD8],3),("not r F7 D0",[0xF7,0xD0],3),
("mul r16 F7 E3",[0xF7,0xE3],(35,37)),("mul [bx] F7 27",[0xF7,0x27],(41,43)),("imul r16 F7 EB",[0xF7,0xEB],(34,37)),("div r16 F7 F3",[0xF7,0xF3],38),("div [bx] F7 37",[0xF7,0x37],44),("cbw 98",[0x98],2),("cwd 99",[0x99],4),
("and r,r 21 D8",[0x21,0xD8],3),("and [bx],ax 21 07",[0x21,0x07],10),("test r,r 85 D8",[0x85,0xD8],3),("test [bx],r 85 07",[0x85,0x07],10),("test [bx],imm F7 07",[0xF7,0x07,1,0],10),("xor r,r 31 C0",[0x31,0xC0],3),
("shl r,1 D1 E0",[0xD1,0xE0],2),("shl [bx],1 D1 27",[0xD1,0x27],15),("shl r,cl(1) D3 E0",[0xD3,0xE0],6),("shl [bx],cl(1) D3 27",[0xD3,0x27],18),("shl r,3 C1 E0 03",[0xC1,0xE0,3],8),("shl [bx],3 C1 27 03",[0xC1,0x27,3],20),
("movsw A5",[0xA5],14),("stosw AB",[0xAB],10),("lodsw AD",[0xAD],12),("cmpsw A7",[0xA7],22),("scasw AF",[0xAF],15),
("rep movsw x4 F3 A5",[0xF3,0xA5],8+8*4),("rep stosw x4 F3 AB",[0xF3,0xAB],6+9*4),("rep lodsw x4 F3 AD",[0xF3,0xAD],6+11*4),("rep cmpsw(eq) x4 F3 A7",[0xF3,0xA7],5+22*4),
("jmp short EB",[0xEB,0],14),("jmp near E9",[0xE9,0,0],14),("jz not taken 74",[0x74,0],4),("jz taken 74",[0x74,0],13),("call near E8",[0xE8,0,0],15),("call r FF D3",[0xFF,0xD3],13),("call [bx] FF 17",[0xFF,0x17],19),("ret C3",[0xC3],16),("ret imm C2",[0xC2,0,0],18),("jmp r FF E3",[0xFF,0xE3],11),("jmp [bx] FF 27",[0xFF,0x27],17),
("loop taken E2",[0xE2,0],16),("loop not taken E2",[0xE2,0],6),("jcxz taken E3",[0xE3,0],16),("jcxz not taken E3",[0xE3,0],6),
("int n CD",[0xCD,0x20],47),("int3 CC",[0xCC],45),("iret CF",[0xCF],28),("clc F8",[0xF8],2),("cli FA",[0xFA],2),("sti FB",[0xFB],2),("nop 90",[0x90],3),("cs: prefix 2E",[0x2E,0x90],2+3),
]
model=int(sys.argv[1]) if len(sys.argv)>1 else 1
bad=0
for name,code,exp in T:
    c=CPU(); c.cycle_model(model); c.reset(); c.ud_trap(0)
    c.set('CS',0x1000); c.set('IP',0); c.set('DS',0x2000); c.set('ES',0x2000); c.set('SS',0x3000); c.set('SP',0x1000)
    c.set('BX',0x100); c.set('SI',0x200); c.set('DI',0x300); c.set('CX',4 if 'x4' in name else 1); c.set('AX',3); c.set('DX',0x50)
    fl=0x0002
    if 'jz taken' in name: fl|=0x40
    if 'loop taken' in name or 'jcxz taken' in name: c.set('CX',5 if 'loop' in name else 0)
    if 'loop not' in name: c.set('CX',1)
    if 'jcxz not' in name: c.set('CX',5)
    if 'div' in name: c.set('BX',1) if 'r16' in name else None; c.set('DX',0)
    if 'mul' in name: c.set('BX',2)
    if 'rep cmpsw' in name: fl|=0x40
    c.set('FLAGS',fl)
    for a in range(0x20000,0x20400): c.mem[a]=0
    c.mem[0x20100]=1
    c.load(0x10000,code+[0x90]*8)
    if 'div [bx]' in name: c.mem[0x20100]=1; c.mem[0x20101]=0
    if 'div r16' in name: c.set('BX',1)
    t0=c.cycles; c.run(1)
    if 'rep' in name:                                        # REP strings yield at the cycle budget: resume until the instruction is complete
        while c.get('IP')<len(code): c.run(1)
    got=c.cycles-t0
    lo,hi=(exp if isinstance(exp,tuple) else (exp,exp))
    ok=lo<=got<=hi; bad+=not ok
    print('%-28s model %3d  manual %-8s %s'%(name,got,('%d-%d'%(lo,hi)) if lo!=hi else str(lo),'' if ok else '<-- %+d'%(got-lo if got<lo else got-hi)))
print('mismatches:',bad,'of',len(T))
