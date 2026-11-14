import sys, math, json; sys.path.insert(0,'.')
from machine import *
from line import *
fs=7200
m=Machine(nvram_mode=None); cpu=m.cpu; m.logging=False
m.run(900_000_000); m.dte_text()
for c in ("AT\r","ATQ0V1X3\r"): m.send(c); m.run(150_000_000); m.dte_text()
m.rx_gen=dial_tone(3000); m.tx_all.clear(); m.cmd_log16.clear(); m.send("ATDT1\r")
phase=0
for i in range(30):
    m.run(100_000_000)
    if phase==0 and any(abs(v)>15000 for v in m.tx_all[-20000:]):
        m.rx_gen=None; phase=1; print("dial tone removed at %.2f s"%(len(m.tx_all)/fs))
print("captured %.1f s"%(len(m.tx_all)/fs)); print("DTE:",m.dte_text())
print("DSP commands (sample time s, cmd word, arg word):")
last=None
for t,c,a in m.cmd_log16:
    key=(c,a)
    print("   %6.2f  %04X %04X"%(t/fs,c,a))
json.dump(m.tx_all,open('/tmp/claude-1000/-home-hrvoje-Programming-USR/831d3a18-6a9c-4288-84f9-a85e9135fc6f/scratchpad/callertest.json','w'))
