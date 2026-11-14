import sys, math, json; sys.path.insert(0,'.')
from link import *
fs=7200
def top(x):
    best=(0,0)
    for f in range(50,3600,10):
        re=sum(x[n]*math.cos(2*math.pi*f*n/fs) for n in range(0,len(x),2)); im=sum(x[n]*math.sin(2*math.pi*f*n/fs) for n in range(0,len(x),2))
        if re*re+im*im>best[0]: best=(re*re+im*im,f)
    return best[1], int(math.sqrt(best[0])/(len(x)/2)*2)
def summarize(name,s,maxsec=60):
    print("%s: %.1f s; per-second peak|dominant Hz:amp"%(name,len(s)/fs))
    print("   ",["%d|%d:%d"%(max(map(abs,s[t*fs:(t+1)*fs])),*top(s[t*fs:t*fs+1200])) for t in range(min(len(s)//fs,maxsec))])
L=Link(); L.run(900_000_000); L.text()
na=len(L.a.cmd_log); nb=len(L.b.cmd_log); L.audio={'a':[],'b':[]}
L.b.send("ATX3\r"); L.run(150_000_000); print("B after ATX3:",L.b.dte_text())
L.b.send("ATDT1\r"); L.a.send("ATA\r")
oa=b''; ob=b''
for i in range(10):
    L.run(250_000_000); ta,tb=L.text(); oa+=ta; ob+=tb
print("A DTE:",oa); print("B DTE:",ob)
print("A cmds:",[(hex(x),hex(y)) for c,x,y in L.a.cmd_log[na:]])
print("B cmds:",[(hex(x),hex(y)) for c,x,y in L.b.cmd_log[nb:]])
summarize("A out",L.audio['a']); summarize("B out",L.audio['b'])
import wave,struct
for k in 'ab':
    with wave.open('/home/hrvoje/Programming/USR/out/link2_%s.wav'%k,'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(fs); w.writeframes(struct.pack('<%dh'%len(L.audio[k]),*[max(-32768,min(32767,v)) for v in L.audio[k]]))
print("wrote out/link2_a.wav, out/link2_b.wav (local only)")
