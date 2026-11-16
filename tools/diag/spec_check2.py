"""verify the C5x core against doc/06a (SPRU056D Tables 6-4..6-10): run every opcode row once; report BADOP, wrong word count, wrong cycles (fastest case).
usage: spec_check2.py"""
import os, sys, re; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/dsp')
from c5x import *
rows=[]
for l in open(ROOT+'/doc/06a-instruction-set-summary.md').read().split('\n'):
    m=re.match(r"\| (?:\*\*)?([A-Z0-9]+)(?:\*\*)? \| (.*?) \| (\d) \| ([^|]*?) \| `([01A-Za-z #]+)`( \+ 1 word)? \| ",l)
    if m: rows.append((m.group(1),m.group(2),int(m.group(3)),m.group(4).strip(),m.group(5).strip().replace(' ',''),bool(m.group(6))))
print(len(rows),'rows')
BASE=0x8100
def run1(op,sec,setup):
    d=DSP(); d.set_cycle_model(1)
    d.pm[BASE]=op
    if sec is not None: d.pm[BASE+1]=sec
    for i in range(2,8): d.pm[BASE+i]=0x8B00
    d.reset(BASE); d.set('PC',BASE)
    for a in range(0x200,0x400): d.dm[a]=0
    d.set('AR0',0x300); d.set('AR1',0x300)
    d.set('ST1',d.get('ST1')&~1) if False else None
    if setup: setup(d)
    c0=d.total_cycles(); st=d.run(1)
    return st,(d.get('PC')-BASE)&0xFFFF,d.total_cycles()-c0
bad=0
for mn,desc,w,cyc,pat,two in rows:
    if len(pat)!=16: continue
    ch=list(pat)
    def fill(letter,val,exact=None):
        idx=[i for i,x in enumerate(ch) if x==letter]
        for j,i in enumerate(idx): ch[i]='1' if (val>>(len(idx)-1-j))&1 else '0'
    cond='TPZLVC' in pat
    if cond: fill('T',1); fill('P',1)
    fill('A',0x60 if ch[8]!='1' else 0)
    for k in range(len(ch)):
        pass

    for L in 'IBCDEFGHJKLMNOPQRSUVWXYZ'+'abcdefghijklmnopqrstuvwxyz': 
        if L in ch: fill(L,0 if L!='N' else 0)
    op=int(''.join('0' if x not in '01' else x for x in ch),2)
    mnem=mn
    sec=None
    if two: sec=0x9000 if mnem in ('B','BD','BANZ','BANZD','BCND','BCNDD','CALL','CALLD','CC','CCD') else (0x0010 if mnem in('IN','OUT') else (0x0060 if mnem in ('BLDD','BLPD','SMMR','LMMR') else 0x0001))
    def setup(d):
        if mnem in ('BANZ','BANZD'): d.set('AR0',1)
    st,dpc,dc=run1(op,sec,setup)
    first=int(re.match(r'\d',cyc).group())
    flags=[]
    if st==2: flags.append('BADOP')
    ctrl=mnem in ('B','BD','BACC','BACCD','BANZ','BANZD','BCND','BCNDD','CALA','CALAD','CALL','CALLD','CC','CCD','RET','RETD','RETC','RETCD','RETE','RETI','INTR','TRAP','NMI','RPT','RPTB','RPTZ','XC','IDLE','IDLE2')
    if not ctrl and st!=2 and dpc!=w: flags.append('words %d!=%d'%(dpc,w))
    if st!=2 and dc!=first and not ctrl: flags.append('cycles %d!=%d [%s]'%(dc,first,cyc))
    if ctrl and st!=2 and dc!=first: flags.append('ctrl cycles %d vs [%s] words %d vs %d'%(dc,cyc,dpc,w))
    if flags: bad+=1
    print('%-7s %s %-5s %s'%(mn,pat,'%04X'%op,('  <<< '+'; '.join(flags)) if flags else ''))
print(bad,'rows with differences')
