import re,sys,itertools,random
sys.path.insert(0,'/home/hrvoje/Programming/USR/dsp')
import c5x
from c5x import _lib
rows=[]
for l in open('/home/hrvoje/Programming/USR/doc/06a-instruction-set-summary.md').read().split('\n'):
    m=re.match(r"\| (\*\*)?([A-Z0-9]+)(\*\*)? \| (.*?) \| (\d+) \| ([^|]*?) \| `([01A-Za-z #]+)`( \+ 1 word)? \| ",l)
    if m: rows.append((m.group(2),int(m.group(5)),m.group(6).strip(),m.group(7).strip().replace(' ','')))
BR={'B','BD','BANZ','BANZD','BCND','BCNDD','CALL','CALLD','CC','CCD','CALA','CALAD','RET','RETD','RETC','RETCD','RETI','RETE','BACC','BACCD','INTR','TRAP','NMI','IDLE','IDLE2','XC','RPT','RPTZ','RPTB','RPTB'}
def variants(p):
    out=set()
    letters=[i for i,ch in enumerate(p) if ch not in '01']
    for mode in ('zero','one','mix'):
        bits=list(p)
        for i in letters:
            ch=p[i]
            if mode=='zero': bits[i]='0'
            elif mode=='one': bits[i]='1'
            else: bits[i]=str(random.Random(i*7+len(p)).randint(0,1))
        w=int(''.join(bits),2)
        out.add(w)
    # indirect forms: I bit set with A=0 -> '*'
    return sorted(out)
bad=[];lenmis=[];cyc=[]
for mn,words,cy,pat in rows:
    if len(pat)!=16: bad.append((mn,"pattern len %d"%len(pat),pat)); continue
    # find I bit: pattern letter 'I' at bit 7 position index 8 for dma forms
    for w in variants(pat):
        for xl in range(2):
            ww=w
            if xl and pat[8]=='I' and pat[9:]=='AAAAAAA': ww=(w&0xFF00)|0x80   # indirect, no modify
            d=c5x.DSP(); d.load_pm(0x8000,bytes(0)); 
            d.set_cmpr_ar0(True); d.set_cycle_model(1)
            for i in range(11): d.set_ivec_ind(i,0x60+i); d.dm[0x60+i]=0x81AE
            d.set_io(lambda p:0, lambda p,v:None)
            for i,v in enumerate([ww,0x0123,0x8B00,0x8B00,0x8B00,0x8B00]): d.pm[0x8000+i]=v
            d.reset(0x8000)
            r=d.run(1); pc=d.get("PC"); cy_=_lib.c5x_get(d.h,27)
            if r==2: bad.append((mn,"BADOP","%04X"%ww,pat)); continue
            if mn not in BR and pc-0x8000!=words: lenmis.append((mn,"%04X"%ww,"pc adv %d vs words %d"%(pc-0x8000,words)))
            exp=int(re.match(r"\d+",cy).group())
            if cy and mn not in BR or mn in ('B','BD','CALL','CALLD'): cyc.append((mn,ww,exp,cy_)) 
import collections
print("rows",len(rows),"BADOP/oddities:",len(bad)); 
for b in bad[:40]: print("  ",b)
print("length mismatches:",len(lenmis)); 
for b in lenmis[:30]: print("  ",b)
mism=collections.OrderedDict()
for mn,w,e,g in cyc:
    if e!=g: mism.setdefault(mn,set()).add((e,g))
print("cycle mismatches (mnemonic: {(manual, core)}):"); 
for k,v in mism.items(): print("  ",k,sorted(v))
