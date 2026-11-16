"""log the 80186 peripheral-control-block writes (chip selects / wait states / timers) in the first seconds of boot. usage: pcbwrites.py [seconds]"""
import os, sys; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
import machine as M
from machine import CPU_HZ
m=M.Machine(nvram_mode=None); seen={}; o=m.iowr
def w(p,wd,v):
    if 0xFF00<=p<=0xFFFF and (p,v) not in seen: seen[(p,v)]=1; print('t=%.3f out %04X <- %04X'%(m.cpu.cycles/CPU_HZ,p,v))
    return o(p,wd,v)
m.iowr=w; m.cpu.hooks(m.iord, m.iowr, m.mmrd, m.mmwr)
m.run(int(CPU_HZ*float(sys.argv[1] if len(sys.argv)>1 else 1.0)))
