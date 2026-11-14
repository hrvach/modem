import sys, wave, struct, math; sys.path.insert(0,'.')
from link import *
from capture_caller import wav
L=Link()
L.run(900_000_000); L.text()
for m,cmds in ((L.a,("AT\r","ATQ0V1\r")),(L.b,("AT\r","ATQ0V1X3\r"))):
    for c in cmds: m.send(c); L.run(150_000_000)       # one command at a time: the first one after boot is garbled
L.text()
for m in (L.a,L.b): m.tx_all.clear(); m._lk_seen=0
for mm in (L.a,L.b): mm.cmd_log16.clear()
L.audio={'a':[],'b':[]}; L.events=[]; L.start_call("1")
oa=b''; ob=b''
for i in range(22):
    L.run(100_000_000); ta,tb=L.text(); oa+=ta; ob+=tb
    if ta or tb: print("t=%.1fs  A:%r  B:%r"%(L.samples()/FS,ta,tb))
print("state events (s):",L.events)
t0=len(L.audio['b'])
for nm,mm in (('B caller',L.b),('A callee',L.a)):
    print(nm,"DSP commands since start of call (sample time s, cmd, arg):")
    last=None
    for t,c,a in mm.cmd_log16:
        if t>=0: 
            print("    %6.2f  %04X %04X"%(t/7200,c,a))
print("A DTE total:",oa); print("B DTE total:",ob)
wav('/home/hrvoje/Programming/USR/out/link3_callee_A.wav',L.audio['a']); wav('/home/hrvoje/Programming/USR/out/link3_caller_B.wav',L.audio['b'])
print("wrote out/link3_callee_A.wav and out/link3_caller_B.wav (%.0f s)"%(L.samples()/FS))
import json; json.dump(L.audio,open('/tmp/claude-1000/-home-hrvoje-Programming-USR/831d3a18-6a9c-4288-84f9-a85e9135fc6f/scratchpad/link3.json','w'))
