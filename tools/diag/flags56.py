import sys, collections; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from link import *
from machine import CPU_HZ
fs=7200; dur=float(sys.argv[1])
L=Link(); L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}
for m in (L.a,L.b): m.dsp_log.clear(); m.flag_log.clear()
L.start_call("1")
while L.samples() < int(dur*fs): L.run(10_000_000)
m=L.b
w=[(c,v) for c,q,v in m.dsp_log if q==0x56]
print('B DSP writes to port 0x56:',len(w)); 
cnt=collections.Counter(v for c,v in w); print(' values:',[('%04X'%k,n) for k,n in cnt.most_common(12)])
print('B host flag writes (t, port, val, flags after):',[(t,hex(p),'%02X'%v,'%04X'%f) for t,p,v,f in m.flag_log][:40])
rd=collections.Counter(q for c,q,v in m.dsp_log); print('B DSP port writes by port:',{hex(k):n for k,n in sorted(rd.items())})

print('B DSP write PCs (port,pc):',sorted(((k,n) for k,n in m.wr_pcs.items() if k[0] in (0x50,0x51,0x56,0x58,0x59,0x5a,0x5b)),key=lambda x:-x[1])[:14])

print('B DSP read PCs (port,pc):',sorted(((hex(k[0]),hex(k[1]),n) for k,n in m.rd_pcs.items()),key=lambda x:-x[2])[:16])
print('A DSP read PCs:',sorted(((hex(k[0]),hex(k[1]),n) for k,n in L.a.rd_pcs.items()),key=lambda x:-x[2])[:10])
