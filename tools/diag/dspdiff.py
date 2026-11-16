"""differential test of one DSP routine on the active C5x core (DSP_CORE=sib for the courier-emu core): run base-image code from ENTRY with random data cells, print the resulting cells. usage: dspdiff.py ENTRY_HEX N CELLS(hex,comma) RANDCELLS(hex,comma) [SEED]"""
import os, sys, random; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/dsp')
import c5x
entry=int(sys.argv[1],16); N=int(sys.argv[2]); out=[int(a,16) for a in sys.argv[3].split(',')]; rnd=[int(a,16) for a in sys.argv[4].split(',')]; seed=int(sys.argv[5]) if len(sys.argv)>5 else 1
base=open(os.path.join(ROOT,'dsp','dsp_base.bin'),'rb').read()
d=c5x.DSP(); d.load_pm(0x8000,base)
d.load_pm(0x7000,bytes([0x06,0xBC, 0x80,0x7A, entry&0xFF,entry>>8, 0x80,0x79, 0x03,0x70]))   # ldp #6 ; call ENTRY ; b $
for i in range(11): d.set_ivec_ind(i,0x60+i); d.dm[0x60+i]=0x81AE
d.set_io(lambda p:0, lambda p,v:None)
R=random.Random(seed)
for case in range(N):
    d.reset(0x7000)
    for a in range(0x300,0x330): d.dm[a]=0
    vals={}
    for a in rnd:
        v=R.randrange(0x10000)
        if a==0x6F: v=(v&~0x4000)|(R.getrandbits(1)<<14)
        d.dm[a]=v; vals[a]=v
    d.run(400)
    print(case,' '.join('%03X=%04X'%(a,vals[a]) for a in rnd),'->',' '.join('%03X=%04X'%(a,d.dm[a]) for a in out),'ACC=%08X T0=%04X PC=%04X'%(d.get('ACC'),d.get('T0'),d.get('PC')))
