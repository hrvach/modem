import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/dsp')
import c5x
def run(prog, setup, steps=300):
    d=c5x.DSP(); d.load_pm(0x8000,b'\0'*64)
    for i,w in enumerate(prog): d.pm[0x7000+i]=w
    d.pm[0x7000+len(prog)]=0x7980; d.pm[0x7001+len(prog)]=0x7000+len(prog)   # B self
    d.reset(0x7000); d.run(3)
    d.set('PC',0x7000); d.set('SP',0); d.set('ST0',0x0200)
    setup(d)
    d.run(steps)
    return d
# SUBC division: 100 / 7
def setup(d): d.set('ACC',100); d.dm[0x200]=7; d.set('AR1',0x200); d.set('ST0',0x0200|0x2000|0)  # ARP=1
d=run([0xBB0F,0x0A80],setup)
acc=d.get('ACC'); print("SUBC 100/7: ACC=%08X quotient=%d remainder=%d (want 14 r 2)"%(acc,acc&0xFFFF,acc>>16))
def setup(d): d.set('ACC',0xFFFF); d.dm[0x200]=3; d.set('AR1',0x200); d.set('ST0',0x0200|0x2000)
d=run([0xBB0F,0x0A80],setup); acc=d.get('ACC'); print("SUBC 65535/3: quotient=%d remainder=%d (want 21845 r 0)"%(acc&0xFFFF,acc>>16))
print("--- MACD FIR")
def setup(d):
    for i,v in enumerate([1,2,3,4]): d.dm[0x300+i]=v
    for i,v in enumerate([10,20,30,40]): d.pm[0x7100+i]=v
    d.set('AR1',0x303); d.set('ST0',0x0200|0x2000)
d=run([0xBE59,0xBB03,0xA390,0x7100,0xBE04],setup)
print("ACC=%d (want 200)  data now"%d.get('ACC'),[d.dm[0x300+i] for i in range(5)],"(want [1,1,2,3,4])  PREG=%d BMAR/T0=%d AR1=%04X(want 02FF)"%(d.get('PREG'),d.get('T0'),d.get('AR1')))
print("--- MAC FIR (no move), BMAR untouched check with MADS")
def setup(d):
    for i,v in enumerate([1,2,3,4]): d.dm[0x300+i]=v
    for i,v in enumerate([10,20,30,40]): d.pm[0x7100+i]=v
    d.set('AR1',0x300); d.set('ST0',0x0200|0x2000); d.set('BMAR',0x7100)
d=run([0xBE59,0xBB03,0xAA90+0,0xBE04],setup)  # MADS *+? opcode AA/mads with ind '*' => 0xAA80; use *+ = 0xA0|? 
