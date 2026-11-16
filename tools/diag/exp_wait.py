"""experiment: shorten B's post-arming wait by N ticks (patch the 'sub #4B' immediate at DSP 9DFB, word BA4B) then run call_data.py. usage: exp_wait.py N MAXSEC TAG"""
import os, sys, runpy; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/sys')
import machine as _M
N=int(sys.argv[1]); orig=_M.Machine._sample; hit=[0]
def s(self):
    r=orig(self)
    if N and self.dsp.pm[0x9DFB]==0xBA4B and self.dsp.dm[0x3A0]==0x2A:     # overlay loaded and not yet patched
        pass
    return r
def s2(self):
    r=orig(self); pm=self.dsp.pm
    if N and pm[0x9DFB]==0xBA4B: pm[0x9DFB]=0xBA4B-N; hit[0]+=1; print('patched',self is not None,hit[0],flush=True)
    return r
_M.Machine._sample=s2
sys.argv=['call_data.py']+sys.argv[2:]
runpy.run_path(ROOT+'/tools/diag/call_data.py',run_name='__main__')
