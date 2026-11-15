"""one modem, ATA, nothing on the line. usage: ata_solo.py SECONDS [tag]; writes out/<tag>/ata_solo.wav; prints DSP commands, spectrum timeline, DTE text"""
import sys, os, wave, struct, math; sys.path.insert(0,'/home/hrvoje/Programming/USR/sys')
from machine import *
secs=int(sys.argv[1]); tag=sys.argv[2] if len(sys.argv)>2 else 'ata_solo'
m=Machine(nvram_mode=None); m.logging=False
m.run(4*CPU_HZ); m.send("AT\r"); m.run(CPU_HZ); m.dte_text()
for pc in os.environ.get("PRE","").split(";"):
    if pc: m.send(pc+"\r"); m.run(CPU_HZ)
m.dte_text(); m.cmd_log16.clear(); n0=len(m.tx_all); m.send("ATA\r"); t0=m.cpu.cycles
for i in range(secs):
    m.run(CPU_HZ)
    if i%5==4: print("t+%d txt=%r"%(i+1,m.dte_text()),flush=True)
x=m.tx_all[n0:]
print("cmds:",[(round(t/7200,2),"%04X"%a,"%04X"%b) for t,a,b in m.cmd_log16][:60])
os.makedirs('/home/hrvoje/Programming/USR/out/'+tag,exist_ok=True)
with wave.open('/home/hrvoje/Programming/USR/out/%s/ata_solo.wav'%tag,'wb') as w: w.setnchannels(1); w.setsampwidth(2); w.setframerate(7200); w.writeframes(struct.pack('<%dh'%len(x),*x))
fs=7200
def g(s,f):
    k=2*math.cos(2*math.pi*f/fs); a=b=0.0
    for v in s: a,b=v+k*a-b,a
    return math.sqrt(max(a*a+b*b-k*a*b,0))*2/len(s)
for i in range(0,len(x)-3600,3600):
    s=x[i:i+3600]; rms=math.sqrt(sum(v*v for v in s)/len(s))
    if rms>30:
        top=sorted(((g(s,f),f) for f in range(100,3600,50)),reverse=True)[:3]
        print("  t=%4.1f rms=%6.0f pk=%5d %s"%(i/fs,rms,max(map(abs,s)),' '.join('%d(%.0f)'%(f,a) for a,f in top)))
d=m.dsp; print("msg kinds:",sorted(set((a,b,c,dd) for t,a,b,c,dd in m.msg_log))[:30])
