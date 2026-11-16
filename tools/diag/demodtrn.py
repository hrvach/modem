"""independent demodulation of a modem's transmitted training signal (DAC samples) in the A417 stage: mix with the carrier (phase step 4/21 turn per sample, fs/3 baud), low-pass, symbol timing by energy, 4th-power carrier phase, quadrants -> dibits (all 24 maps, 2 bit orders, plain and differential), descramble with GPA (1+x^-5+x^-23) and GPC (1+x^-18+x^-23), report how close the output is to constant ones. usage: demodtrn.py T0 T1 (env as call tools)"""
import os, sys, math, cmath, itertools; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
from link import *
from machine import CPU_HZ
T0=float(sys.argv[1]); T1=float(sys.argv[2]); L=Link(); L.gain=float(os.environ.get('GAIN','0.5'))
L.run(8*CPU_HZ)
for m,cmds in ((L.a,["AT\r","ATQ0V1\r"]),(L.b,["AT\r","ATQ0V1X3\r"])):
    for c in cmds: m.send(c); L.run(int(1.5*CPU_HZ))
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
base=L.a.cpu.cycles; T=lambda: (L.a.cpu.cycles-base)/CPU_HZ
while T()<T0: L.run(CPU_HZ//64)
i0=(len(L.audio['a']),len(L.audio['b']))
while T()<T1: L.run(CPU_HZ//64)
i1=(len(L.audio['a']),len(L.audio['b']))
sg=lambda v: v-65536 if v>=32768 else v
FC=None
def find_carrier(x):
    # search the carrier that makes the 4th power of the symbol-rate samples coherent
    best=None
    for fc in [1800+5*k for k in range(60)]:
        w=2*math.pi*fc/FSR
        z=[x[i]*cmath.exp(-1j*w*i) for i in range(0,min(len(x),3000))]
        taps=41; fcut=0.165; h=[(math.sin(2*math.pi*fcut*(k-(taps-1)/2))/(math.pi*(k-(taps-1)/2)) if k!=(taps-1)//2 else 2*fcut)*(0.54-0.46*math.cos(2*math.pi*k/(taps-1))) for k in range(taps)]
        y=[sum(h[k]*z[i+k] for k in range(taps)) for i in range(len(z)-taps)]
        for off in range(3):
            s_=y[off::3]; m4=abs(sum(v**4 for v in s_))/(sum(abs(v)**4 for v in s_) or 1)
            if best is None or m4>best[0]: best=(m4,fc,off)
    return best
FSR=10266.67
def demod(x,name):
    x=[sg(v&0xFFFF) for v in x]; n=len(x)
    bc=find_carrier(x); print('%s: best carrier %.0f Hz, timing offset %d, 4th-power coherence %.2f'%(name,bc[1],bc[2],bc[0]))
    w=2*math.pi*bc[1]/FSR
    z=[x[i]*cmath.exp(-1j*w*i) for i in range(n)]
    # low-pass: moving-average style windowed sinc, cutoff ~1.7 kHz at fs 10267 -> 0.165 fs
    taps=41; fc=0.165; h=[(math.sin(2*math.pi*fc*(k-(taps-1)/2))/(math.pi*(k-(taps-1)/2)) if k!=(taps-1)//2 else 2*fc)*(0.54-0.46*math.cos(2*math.pi*k/(taps-1))) for k in range(taps)]
    y=[sum(h[k]*z[i+k] for k in range(taps)) for i in range(n-taps)]
    best=None
    for off in range(3):
        s=y[off::3]; e=sum(abs(v)**2 for v in s)/len(s)
        if best is None or e>best[0]: best=(e,off,s)
    e,off,s=best
    s=s[5:-5]
    ang=cmath.phase(sum(v**4 for v in s))/4
    q=[int(round((cmath.phase(v*cmath.exp(-1j*ang))/(math.pi/2))))%4 for v in s]
    rad=[abs(v) for v in s]; mr=sum(rad)/len(rad); sd=math.sqrt(sum((r-mr)**2 for r in rad)/len(rad))
    print('%s: %d symbols, timing offset %d, radius mean %.0f sd %.0f (sd/mean %.2f), carrier phase %.1f deg'%(name,len(s),off,mr,sd,sd/mr if mr else 0,math.degrees(ang)))
    # constellation spread: angular error around the nearest 90-degree grid
    err=[abs(((cmath.phase(v*cmath.exp(-1j*ang)))/(math.pi/2))-round(cmath.phase(v*cmath.exp(-1j*ang))/(math.pi/2))) for v in s]
    print('   mean angular error %.3f of a quadrant (0 = on the grid, 0.5 = worst)'%(sum(err)/len(err)))
    res=[]
    for perm in itertools.permutations(range(4)):
        for diff in (False,True):
            qq=[(q[i]-q[i-1])%4 for i in range(1,len(q))] if diff else q
            d=[perm[v] for v in qq]
            for order in ('hl','lh'):
                bits=[]
                for v in d: bits+= [v>>1,v&1] if order=='hl' else [v&1,v>>1]
                for pn,tp in (('GPA',(5,23)),('GPC',(18,23))):
                    o=[bits[i]^bits[i-tp[0]]^bits[i-tp[1]] for i in range(23,len(bits))]
                    f=sum(o)/len(o); res.append((max(f,1-f),f,perm,diff,order,pn))
    res.sort(reverse=True)
    for r in res[:4]: print('   best: ones fraction %.3f  map %s %s %s %s'%(r[1],r[2],'diff' if r[3] else 'plain',r[4],r[5]))
if os.environ.get('SEGMENTS')=='1':
    def seg(x,name,W=600):
        x=[sg(v&0xFFFF) for v in x]
        print(name,'per %d-sample window: t0=%.2f s; rms, ac6, ac144, radius sd/mean after demod'%(W,T0))
        for a in range(0,len(x)-W-60,W):
            w=x[a:a+W]; e=sum(v*v for v in w) or 1
            ac=lambda k: sum(w[i]*w[i+k] for i in range(len(w)-k))/e
            z=[w[i]*cmath.exp(-2j*math.pi*(4/21)*(a+i)) for i in range(len(w))]
            taps=41; fc=0.165; h=[(math.sin(2*math.pi*fc*(k-(taps-1)/2))/(math.pi*(k-(taps-1)/2)) if k!=(taps-1)//2 else 2*fc)*(0.54-0.46*math.cos(2*math.pi*k/(taps-1))) for k in range(taps)]
            y=[sum(h[k]*z[i+k] for k in range(taps)) for i in range(len(z)-taps)]
            b=min((sum((abs(v)-sum(abs(u) for u in y[o::3])/len(y[o::3]))**2 for v in y[o::3])/len(y[o::3]),o) for o in range(3))
            sd=math.sqrt(b[0]); m=sum(abs(v) for v in y[b[1]::3])/len(y[b[1]::3])
            print('  +%5d  rms %5.0f  ac6 %5.2f  ac144 %5.2f  sd/mean %.2f'%(a,math.sqrt(e/W),ac(6),ac(144),sd/m if m else 0))
    seg(L.audio['a'][i0[0]:i1[0]],'A TX'); seg(L.audio['b'][i0[1]:i1[1]],'B TX')
else:
    demod(L.audio['a'][i0[0]:i1[0]],'A TX')
    demod(L.audio['b'][i0[1]:i1[1]],'B TX')
