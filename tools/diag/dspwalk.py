"""run to T seconds, then single-step one DSP and print PC / ACC / DP / AR1 / TC for N steps (only PCs in a given set of ranges if RANGE=lo-hi given).
usage: dspwalk.py T A|B N"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; T=float(sys.argv[1]); who=sys.argv[2]; N=int(sys.argv[3])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(T*fs): L.run(CPU_HZ//16)
d=(L.a if who=='A' else L.b).dsp
for i in range(N):
    pc=d.get('PC'); d.run(1)
    print('%04X acc=%08X st0=%04X ar1=%04X [3B4]=%04X [6D]=%04X [6E]=%04X [6F]=%04X'%(pc,d.get('ACC'),d.get('ST0'),d.get('AR1'),d.dm[0x3B4],d.dm[0x6D],d.dm[0x6E],d.dm[0x6F]))
