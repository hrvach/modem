"""time/frequency profile of a mono wav (7200 Hz): per 0.5 s window, rms and the strongest of a list of modem tones. usage: spec.py file.wav [t0 t1]"""
import sys,wave,struct,math
w=wave.open(sys.argv[1]); n=w.getnframes(); ch=w.getnchannels(); x=struct.unpack('<%dh'%(n*ch),w.readframes(n))
chs=[x[i::ch] for i in range(ch)]
fs=7200; win=3600
fr=[300,390,980,1100,1180,1200,1300,1650,1750,1850,2100,2225,2250,2400,2600,3000]
def g(s,f):
    k=2*math.cos(2*math.pi*f/fs); a=b=0.0
    for v in s: a,b=v+k*a-b,a
    return (a*a+b*b-k*a*b)/len(s)**2
t0=float(sys.argv[2]) if len(sys.argv)>2 else 0; t1=float(sys.argv[3]) if len(sys.argv)>3 else n/fs
for c,s in enumerate(chs):
    print("channel",c)
    for i in range(int(t0*fs),min(len(s),int(t1*fs))-win+1,win):
        seg=s[i:i+win]; rms=math.sqrt(sum(v*v for v in seg)/win)
        if rms<20: continue
        top=sorted(((g(seg,f),f) for f in fr),reverse=True)[:3]
        print("  t=%5.1f rms=%6.0f  %s"%(i/fs,rms,' '.join('%d(%.0f)'%(f,math.sqrt(p)*2) for p,f in top)))
