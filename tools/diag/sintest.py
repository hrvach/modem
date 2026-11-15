import sys, math; sys.path.insert(0,'/home/hrvoje/Programming/USR/dsp')
import c5x
d=c5x.DSP(); base=open('/home/hrvoje/Programming/USR/dsp/dsp_base.bin','rb').read(); d.load_pm(0x8000,base)
d.dm[0x60+3]=0x81AE
# stub at 0x7000: call 8B75 ; b 7002 (loop)
d.pm[0x7000]=0x7A80; d.pm[0x7001]=int(sys.argv[1],16) if len(sys.argv)>1 else 0x8B75; d.pm[0x7002]=0x7980; d.pm[0x7003]=0x7002
d.reset(0x7000); d.run(5)  # let reset settle
for ph in range(0,65536,8192):
    d.set('PC',0x7000); d.set('SP',0); d.set('ACC',(ph<<16)&0xFFFFFFFF)
    d.set('ST0',0x0200|7)   # INTM=1, DP=7 (page 0x380)
    for _ in range(400):
        d.run(1)
        if d.get('PC') in (0x7002,): break
    acc=d.get('ACC'); acc= acc-(1<<32) if acc&0x80000000 else acc
    print("phase %5d (%.1f deg) ACC=%08X  hi16=%6d  sin*32768=%7.0f  PC=%04X"%(ph,ph*360/65536,acc&0xFFFFFFFF,acc>>16,32768*math.sin(2*math.pi*ph/65536),d.get('PC')))
