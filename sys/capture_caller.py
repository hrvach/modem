import sys, math, wave, struct; sys.path.insert(0,'.')
from machine import *
from line import *
def wav(path, s, fs=7200):
    with wave.open(path,'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(fs); w.writeframes(struct.pack('<%dh'%len(s),*[max(-32768,min(32767,v)) for v in s]))
if __name__=="__main__":
    m=Machine(nvram_mode=None); cpu=m.cpu; m.logging=False
    m.run(900_000_000); m.dte_text()
    for c in ("AT\r","ATQ0V1X3\r"): m.send(c); m.run(150_000_000); m.dte_text()
    m.rx_gen=dial_tone(3000); m.tx_all.clear(); n0=len(m.cmd_log); m.send("ATDT1\r")
    for i in range(14): m.run(100_000_000)
    tx=m.tx_all; print("captured %.1f s, peak %d; DTE: %r"%(len(tx)/7200,max(map(abs,tx)),m.dte_text()))
    wav('/home/hrvoje/Programming/USR/out/caller_B_dial_%ds.wav'%(len(tx)//7200), tx)
    import json; json.dump(tx,open('/tmp/claude-1000/-home-hrvoje-Programming-USR/831d3a18-6a9c-4288-84f9-a85e9135fc6f/scratchpad/callerB.json','w'))
    fs=7200
    def peaks(x,n=3):
        res=[]
        for f in range(200,3500,10):
            re=sum(x[k]*math.cos(2*math.pi*f*k/fs) for k in range(len(x))); im=sum(x[k]*math.sin(2*math.pi*f*k/fs) for k in range(len(x)))
            res.append((math.hypot(re,im)/len(x)*2,f))
        res.sort(reverse=True); out=[]
        for a,f in res:
            if all(abs(f-g)>80 for g,_ in out): out.append((f,int(a)))
            if len(out)==n: break
        return out
    for t in range(0,len(tx)-900,1800):
        x=tx[t:t+900]; pk=max(abs(v) for v in x)
        print("t=%5.2fs peak=%5d  %s"%(t/fs,pk,peaks(x) if pk>300 else "-"))
