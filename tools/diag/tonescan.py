"""Goertzel scan of a wav channel window assuming sample rate FS. usage: tonescan.py WAV CH(0|1) START_SAMPLE LEN FS [step_hz]"""
import sys, wave, struct, math
w=wave.open(sys.argv[1]); n=w.getnframes(); ch=w.getnchannels(); raw=struct.unpack('<%dh'%(n*ch),w.readframes(n)); x=raw[int(sys.argv[2])::ch]
s0=int(sys.argv[3]); ln=int(sys.argv[4]); fs=float(sys.argv[5]); step=float(sys.argv[6]) if len(sys.argv)>6 else 25.0
seg=x[s0:s0+ln]; rms=math.sqrt(sum(v*v for v in seg)/len(seg))
def g(f):
    k=2*math.cos(2*math.pi*f/fs); a=b=0.0
    for v in seg: c=v+k*a-b; b=a; a=c
    return a*a+b*b-k*a*b
fr=[step*i for i in range(1,int(fs/2/step))]
p=sorted(((g(f),f) for f in fr),reverse=True)[:8]
print('rms %.0f top peaks (Hz): %s'%(rms,[round(f) for _,f in sorted(p[:8],key=lambda t:t[1])]))
