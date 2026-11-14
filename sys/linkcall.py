import sys, wave, struct, json; sys.path.insert(0,'.')
from link import *
mode=sys.argv[1]; dur=float(sys.argv[2]) if len(sys.argv)>2 else 70
outdir=sys.argv[3] if len(sys.argv)>3 else '../out'
fs=7200
L=Link()
import os
for _m in (L.a,L.b):
    _m.noise_amp=int(os.environ.get('NOISE','8')); _m.xint_mode=int(os.environ.get('XM','1')); _m.cycle_model=int(os.environ.get('CM','1')); _m.tdm_irqs=bool(int(os.environ.get('TDM','0'))); _m.legacy=int(os.environ.get('LEGACY','0'))
L.run(900_000_000); L.text()
setupA=["AT\r","ATQ0V1\r"]; setupB=["AT\r","ATQ0V1X3\r"]
if mode=="v21": setupA+=["AT&N1\r","ATB0\r"]; setupB+=["AT&N1\r","ATB0\r"]
if mode=="v22": setupA+=["AT&N3\r","ATB0\r"]; setupB+=["AT&N3\r","ATB0\r"]
if mode=="echo": L.echo=0.1
if mode=="gate": L.gate=True
for m,cmds in ((L.a,setupA),(L.b,setupB)):
    for c in cmds: m.send(c); L.run(150_000_000)
setup_txt=L.text()
for mm in (L.a,L.b): mm.tx_all.clear(); mm._lk_seen=0; mm.cmd_log16.clear(); mm.dsp_log.clear()
L.audio={'a':[],'b':[]}; L.events=[]; L.txt={'a':b'','b':b''}; L.start_call("1")
while L.samples() < int(dur*fs): L.run(10_000_000)
print("== mode",mode,"setup replies:",setup_txt)
print("events:",[(round(t,2),s) for t,s in L.events])
print("A (callee) DTE text:",L.txt['a']); print("B (caller) DTE text:",L.txt['b'])
for nm,mm in (('A',L.a),('B',L.b)):
    print(nm,"DSP commands after 12 s:",[(round(t/fs,2),"%04X"%c,"%04X"%x) for t,c,x in mm.cmd_log16 if t>12*fs][:40])
def mono(p,x):
    with wave.open(p,'wb') as w: w.setnchannels(1); w.setsampwidth(2); w.setframerate(fs); w.writeframes(struct.pack('<%dh'%len(x),*[max(-32768,min(32767,v)) for v in x]))
a=L.audio['a']; b=L.audio['b']; n=min(len(a),len(b))
mono('%s/call_%s_callee_A.wav'%(outdir,mode),a); mono('%s/call_%s_caller_B.wav'%(outdir,mode),b)
with wave.open('%s/call_%s_caller_left_answerer_right.wav'%(outdir,mode),'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(fs)
    fr=[]
    for k in range(n): fr += [max(-32768,min(32767,b[k])), max(-32768,min(32767,a[k]))]
    w.writeframes(struct.pack('<%dh'%len(fr),*fr))
print("wrote call_%s_*.wav (%.0f s)"%(mode,n/fs))
