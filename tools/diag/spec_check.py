"""verify the C5x core against doc/tms320c5x.md section 6: every listed instruction must decode (no BADOP), consume the documented words and take the documented cycles.
usage: spec_check.py"""
import os, sys, re; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/dsp')
from c5x import *
txt=open(ROOT+'/doc/tms320c5x.md').read().split('## Chapter 6')[1]
rows=[]
for l in txt.split('\n'):
    m=re.match(r"\| `([^`]+)` \| `([01 a-zA-Z]{19})`( \+ `#?\w+`)? \| `(\d) / (\d)(?:\((\d)\))?` \|",l)
    if m: rows.append((m.group(1),m.group(2).replace(' ',''),m.group(3) is not None,int(m.group(4)),int(m.group(5)),m.group(6)))
print(len(rows),"rows")
BASE=0x8100
def run1(op,second,setup=None,rpt=False):
    d=DSP(); d.set_cycle_model(1)
    d.dm[0]=0
    d.pm[BASE]=op
    if second is not None: d.pm[BASE+1]=second
    d.pm[BASE+2]=0x8B00; d.pm[BASE+3]=0x8B00; d.pm[BASE+4]=0x8B00
    d.reset(BASE)
    d.set('PC',BASE)
    if setup: setup(d)
    c0=d.total_cycles(); st=d.run(1); 
    return st,d.get('PC')-BASE,d.total_cycles()-c0,d
bad=[];res=[]
for mn,pat,has2,w,c,c2 in rows:
    op=0
    for ch in pat:
        op<<=1
        if ch=='1': op|=1
    # variable fields: cc for conditionals -> 11 = unconditional(TP=3); direct address bits a -> 0x20 (set later)
    pm=pat
    def mk(sub):
        v=0
        for i,ch in enumerate(pm):
            b=1 if ch=='1' else 0
            if ch in 'abcdefghijklmnopqrstuvwxyz' or ch in 'IA':
                pass
            v=(v<<1)|b
        return v
    op=mk(None)
    # fill fields
    ch=list(pm)
    def fill(letter,val):
        idx=[i for i,x in enumerate(ch) if x==letter]
        for j,i in enumerate(idx): ch[i]='1' if (val>>(len(idx)-1-j))&1 else '0'
    fill('a',0x20 if 'I' in pm else 0); fill('I',0)
    cond_cc=None
    if 'cccc' in pm and mn.split()[0] in ('BCND','BCNDD','CC','CCD','RETC','RETCD','XC'):
        fill('c',0x300)           # TP=11 unconditional
    else: fill('c',0)
    if mn.startswith('CMPR'): pass
    for L in 'skbxfn': fill(L,0)
    opv=int(''.join(ch).replace('s','0').replace('k','0').replace('x','0').replace('f','0').replace('b','0').replace('n','0'),2)
    mnem=mn.split()[0]
    second=None
    if has2: second=0x9000 if mnem in ('B','BD','BANZ','BANZD','BCND','BCNDD','CALL','CALLD','CC','CCD') else (0x0010 if mnem in('IN','OUT') else (0x0060 if mnem in ('BLDD','BLPD','SMMR','LMMR','BLDD') else 0x0001))
    if mnem in ('BANZ','BANZD'):
        setup=lambda d:(d.set('ARP',0),d.set('AR0',1))
    elif mnem=='RPTB': setup=None
    else: setup=None
    if mnem in('RET','RETD','RETC','RETCD','RETE','RETI','POP','POPD'):
        def setup(d): pass
    st,dpc,dc,d=run1(opv,second,setup)
    flag=[]
    if st==-1 or st>=3: pass
    ok_c = (dc==c) 
    notes=''
    if c2 and mnem not in ('BANZ',):
        pass
    taken_exp=c
    res.append((mn,'%04X'%opv,st,dpc,dc,w,c,c2))
for r in res:
    mn,op,st,dpc,dc,w,c,c2=r
    flags=[]
    if st not in (0,): flags.append('status=%s'%st)
    mnem=mn.split()[0]
    branch=mnem in ('B','BD','BACC','BACCD','BANZ','BANZD','BCND','BCNDD','CALA','CALAD','CALL','CALLD','CC','CCD','RET','RETD','RETC','RETCD','RETE','RETI','INTR','TRAP')
    if not branch and dpc!=w: flags.append('words %d != %d'%(dpc,w))
    if dc!=c: flags.append('cycles %d != %d'%(dc,c))
    print('%-22s %s st=%s dPC=%d cyc=%d  doc W/C=%d/%d%s %s'%(mn,op,st,dpc,dc,w,c,'(%s)'%c2 if c2 else '',' <<< '+'; '.join(flags) if flags else ''))
