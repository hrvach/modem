"""polyphase bank of the ov6 resampler A2A7: on each A2A7 call from T0 record ([0x21] counter, [0x3C] table base, the two coefficients copied to [0x3F6]/[0x3F7] by the TBLR pair, the program words they came from); on the first call also dump 0x80 program words from the base and the whole range 0xB400-0xB500.
usage: a2a7bank.py WHO T0 N TAG   -> /tmp/tbank_TAG.json"""
import os, sys, json; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
fs=7200; who=sys.argv[1]; t0=float(sys.argv[2]); N=int(sys.argv[3]); tag=sys.argv[4]; L=Link(); L.gain=0.5; rec=[]; dump={}
tgt=L.a if who=='A' else L.b
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
import machine as _M
d=tgt.dsp; d.bp(0xA2B1); orig=_M.Machine._sample      # A2B1 = first instruction after the TBLR pair: ACC = program address read, [3F6]/[3F7] = the words
def s(self):
    r=orig(self)
    if self is tgt and d.get('PC')==0xA2B1 and L.samples()/fs>=t0 and len(rec)<N:
        dm=d.dm; pm=d.pm; dp=(d.get('ST0')&0x1FF)<<7; acc=d.get('ACC')&0xFFFF
        if not dump: dump.update(t=round(L.samples()/fs,4), acc=acc, dp=dp, tab=[pm[(acc-0x40+i)&0xFFFF] for i in range(0x80)], b4=[pm[0xB400+i] for i in range(0x100)])
        rec.append((round(L.samples()/fs,4), dp, dm[dp+0x21], dm[dp+0x3C], dm[dp+0x20], acc, pm[acc], pm[(acc+1)&0xFFFF], dm[0x3F6], dm[0x3F7]))
    return r
_M.Machine._sample=s
while len(rec)<N and L.samples()<int((t0+10)*fs): L.run(CPU_HZ//32)
json.dump({'rec':rec,'dump':dump},open('/tmp/tbank_%s.json'%tag,'w')); print('saved',len(rec))
