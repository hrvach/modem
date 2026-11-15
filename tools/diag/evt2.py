import sys; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
from machine import CPU_HZ
fs=7200; dur=float(sys.argv[1])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
for m in (L.a,L.b): m.dsp.pc_hits_clear()
last={}
while L.samples() < int(dur*fs):
    L.run(CPU_HZ*2)
    t=L.samples()/fs; s=[]
    for nm,m in (('A',L.a),('B',L.b)):
        s.append("%s 3CE=%02X E=%04X D=%04X flaglog=%d 27B=%04X 27D=%04X words=%d/%d"%(nm,m.cpu.rd8(0x3CE),m.flags56,m.flagsD,len(m.flag_log),m.cpu.rd16(0x27B),m.cpu.rd16(0x27D),m.data_words_sent,m.data_words_read))
    print("t=%5.1f"%t,' | '.join(s))
