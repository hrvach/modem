import sys; sys.path.insert(0,'.')
from machine import *
m=Machine(nvram_mode=None); m.logging=False; m.run(900_000_000); cpu=m.cpu
print("[0xdf0..0xdf6]:",[hex(cpu.rd8(0xdf0+i)) for i in range(7)])
print("[0xe29]=%04X [0xbe4]=%02X [0xbe5]=%02X [0xc02]=%02X [0xbf6]=%04X [0x5db]=%02X"%(cpu.rd16(0xe29),cpu.rd8(0xbe4),cpu.rd8(0xbe5),cpu.rd8(0xc02),cpu.rd16(0xbf6),cpu.rd8(0x5db)))
print("hb_ticks",m.hb_ticks)
# measure heartbeat rate: INT0 services per DSP tick over a window
n0=cpu.hits[0x80000+0xF460]; t0=m.hb_count; m.run(50_000_000); n1=cpu.hits[0x80000+0xF460]; t1=m.hb_count
print("INT0 services: %d over %d DSP ticks -> one per %.2f ticks"%(n1-n0,t1-t0,(t1-t0)/max(1,n1-n0)))
