import sys, math, json; sys.path.insert(0,'.')
from link import *
fs=7200
def top(x):
    best=(0,0)
    for f in range(50,3600,10):
        re=sum(x[n]*math.cos(2*math.pi*f*n/fs) for n in range(0,len(x),2)); im=sum(x[n]*math.sin(2*math.pi*f*n/fs) for n in range(0,len(x),2))
        if re*re+im*im>best[0]: best=(re*re+im*im,f)
    return best[1], int(math.sqrt(best[0])/(len(x)/2)*2)
def summarize(name,s):
    secs=len(s)//fs
    print("%s: %.1f s of audio; per-second (peak, dominant Hz:amp):"%(name,len(s)/fs))
    print("   ",["%d|%d:%d"%(max(map(abs,s[t*fs:(t+1)*fs])) if s[t*fs:(t+1)*fs] else 0,*top(s[t*fs:t*fs+1200])) for t in range(min(secs,45))])
L=Link()
L.run(900_000_000); L.text()
n0a=len(L.a.cmd_log); n0b=len(L.b.cmd_log)
L.audio={'a':[],'b':[]}
L.b.send("ATDT1\r"); L.a.send("ATA\r")
out_a=b''; out_b=b''
for i in range(12):
    L.run(250_000_000)
    ta,tb=L.text(); out_a+=ta; out_b+=tb
print("A DTE:",out_a); print("B DTE:",out_b)
print("A cmds:",[(hex(x),hex(y)) for c,x,y in L.a.cmd_log[n0a:]])
print("B cmds:",[(hex(x),hex(y)) for c,x,y in L.b.cmd_log[n0b:]])
summarize("A out",L.audio['a']); summarize("B out",L.audio['b'])
json.dump({'a':L.audio['a'],'b':L.audio['b']},open('/tmp/claude-1000/-home-hrvoje-Programming-USR/831d3a18-6a9c-4288-84f9-a85e9135fc6f/scratchpad/link1.json','w'))
