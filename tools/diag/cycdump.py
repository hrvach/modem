"""charge each of the 65536 first opcode words once on the selected DSP core (DSP_CORE=sib for the sibling core) and dump cycles per opcode (0xFFFF = the core rejected the opcode / crashed). usage: cycdump.py OUTFILE"""
import os, sys, struct, mmap; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/dsp')
N=0x10000
shm=mmap.mmap(-1, N*2+8); prog_off=N*2
def worker(start):
    import c5x
    d=c5x.DSP(); d.set_io(lambda p:0, lambda p,v:None); d.set_cycle_model(1)
    for w in range(start,N):
        struct.pack_into('<I',shm,prog_off,w)
        d.load_pm(0x8000, struct.pack('<HHHH', w, 0x8100, 0x8B00, 0x8B00)); d.reset(0x8000)
        c0=d.total_cycles(); d.run(1)
        struct.pack_into('<H',shm,w*2,min(65534,d.total_cycles()-c0))
    os._exit(0)
start=0
for i in range(N): struct.pack_into('<H',shm,i*2,0xFFFF)
bad=0
while start<N:
    pid=os.fork()
    if pid==0: worker(start)
    _,st=os.waitpid(pid,0)
    if st==0: break
    k=struct.unpack_from('<I',shm,prog_off)[0]; bad+=1; start=k+1       # the opcode that was running when the child died stays 0xFFFF
open(sys.argv[1],'wb').write(bytes(shm[:N*2]))
print('done, rejected/crashed opcodes: %d'%bad)
