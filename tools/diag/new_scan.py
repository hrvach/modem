import wave,struct,math,sys
def load(p):
    w=wave.open(p); n=w.getnframes(); return struct.unpack('<%dh'%n,w.readframes(n))
def scan(x,fs=7200,win=1800,t0=0,t1=1e9):
    for s in range(int(t0*fs),min(len(x),int(t1*fs))-win+1,win):
        seg=x[s:s+win]; rms=math.sqrt(sum(v*v for v in seg)/win)
        best=[]
        if rms>30:
            for f in range(300,3500,25):
                c=sum(v*math.cos(2*math.pi*f*i/fs) for i,v in enumerate(seg)); q=sum(v*math.sin(2*math.pi*f*i/fs) for i,v in enumerate(seg))
                best.append((math.hypot(c,q)*2/win,f))
            best.sort(reverse=True)
        print("%6.2f rms=%6.0f %s"%(s/fs,rms," ".join("%d:%d"%(f,a) for a,f in best[:4])))
for k in sys.argv[1]:
    print("==",k); scan(load('/home/hrvoje/Programming/USR/out/new1/diag_%s.wav'%k),t0=float(sys.argv[2]),t1=float(sys.argv[3]))
