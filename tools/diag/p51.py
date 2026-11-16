"""inspect the symbol-timer phase loop (DSP ISR 820C): constants [0xBF5] [0xBF6] [0xBF7] [0xBF8], PRD, and the value the ISR computes from port 0x51. usage: p51.py T"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; T=float(sys.argv[1]); L=Link(); L.gain=0.5; L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
for t in (2,8,14,18,22,26):
    if t>T: break
    while L.samples() < int(t*fs): L.run(CPU_HZ//16)
    for nm,m in (('A',L.a),('B',L.b)):
        d=m.dsp; print('%5.1f %s BF5=%04X BF6=%04X BF7=%04X BF8=%04X PRD=%04X TIM=%04X  mmr51 reads=%d'%(t,nm,d.dm[0xBF5],d.dm[0xBF6],d.dm[0xBF7],d.dm[0xBF8],d.get('PRD'),d.get('TIM'),d.mmr_count(0,0x51)),flush=True)
