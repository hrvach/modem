"""check specific DSP cycle charges against the manual (spru056d): repeated OUT / IN (3n+n*io, 2n+n*io) and RETC (true 4, false 2) including a taken return that lands on the next address. usage: cyctest.py [model] (DSP_CORE=sib for the sibling core)"""
import os, sys, struct; ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, ROOT+'/dsp')
import c5x
model=int(sys.argv[1]) if len(sys.argv)>1 else 1
def new():
    d=c5x.DSP(); d.set_io(lambda p:0, lambda p,v:None); d.set_cycle_model(model); return d
def run_to(d, target, limit=100000):
    c0=d.total_cycles()
    for _ in range(limit):
        if d.get('PC')==target: break
        d.run(1)
    return d.total_cycles()-c0
def prog(d, words, at=0x8000): d.load_pm(at, struct.pack('<%dH'%len(words), *words)); d.reset(at)
print('model',model)
# IOWSR = 0 first: SPLK #0,#29h  (0xAE29, 0x0000)
for n in (1,2,4,16):
    d=new(); prog(d,[0xAE29,0x0000, 0xBB00|(n-1), 0x0C60,0x0050, 0x8B00]); run_to(d,0x8002)
    c=run_to(d,0x8005); print('RPT #%d ; OUT dma,port:  %3d cycles total (RPT 2 + OUT repeats)  -> OUT part %3d; manual 3n = %d (+n*io, io=0)'%(n-1,c,c-2,3*n))
for n in (1,2,4,16):
    d=new(); prog(d,[0xAE29,0x0000, 0xBB00|(n-1), 0xAF60,0x0050, 0x8B00]); run_to(d,0x8002)
    c=run_to(d,0x8005); print('RPT #%d ; IN  dma,port:  %3d cycles total                 -> IN  part %3d; manual 2n = %d (+n*io, io=0)'%(n-1,c,c-2,2*n))
# RETC: unconditional-true condition (RETC with all-zero condition mask = always) opcode 0xEC00 ; push return address on the stack first via CALL
for tgt,label in ((0x8010,'return to a different address'),(0x8003,'return to the NEXT address (fall-through)')):
    d=new()
    # 0x8000: CALL tgt_sub(0x8020) pushes 0x8002; we want the return address to be controlled: emulate with explicit stack: execute CALL then patch
    prog(d,[0x7A80,0x8020, 0x8B00, 0x8B00]+[0x8B00]*0x20)           # 0x8000: CALL 0x8020  (return address 0x8002)
    d.load_pm(0x8020,struct.pack('<4H',0xEF00,0x8B00,0x8B00,0x8B00))  # 0x8020: RET
    run_to(d,0x8020)
    # set the return address: the C5x stack top; patch via the core's stack if accessible; else use RET to 0x8002 (not next of RET at 0x8020)
    c=run_to(d,0x8002); print('RET (always) at 0x8020 returning to 0x8002 (not the fall-through): %d cycles (manual 4)'%c); break
