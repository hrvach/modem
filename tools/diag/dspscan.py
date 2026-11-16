"""boot one modem, then scan the loaded DSP program for OUT/IN instructions to a port range. usage: dspscan.py LO HI"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from machine import *
lo=int(sys.argv[1],16); hi=int(sys.argv[2],16); m=Machine(nvram_mode=None); m.logging=False; m.run(int(4*CPU_HZ)); d=m.dsp
print('DSP loaded:', d is not None, 'overlay loads:', [(hex(b),c) for a,b,c in m.ovl_loads])
for a in range(0x8000,0xFF00):
    w=d.pm[a]
    if (w>>8)==0x0C and lo<=d.pm[a+1]<=hi: print('OUT at %04X: %04X %04X  | %s'%(a,w,d.pm[a+1],' '.join('%04X'%d.pm[a+k] for k in range(-3,5))))
    if (w>>8)==0xAF and lo<=d.pm[a+1]<=hi: print('IN  at %04X: %04X %04X'%(a,w,d.pm[a+1]))
