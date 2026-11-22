#!/usr/bin/env python3
"""mksnap.py PREFIX -- turn a C-machine system snapshot (PREFIX_mem.bin / _dsp.bin / _sys.txt, written by courier's SYS_SNAP_T) into the files tb_fast2 +restore=PREFIX reads:
PREFIX_snv.hex, _pm.hex, _dm.hex (DSP state), and PREFIX_mem.bin with a restore stub at 0x70000 + a far jump at the reset vector, so the 186 starts with the snapshot's registers."""
import struct, sys
pre = sys.argv[1]
d = open(pre + '_dsp.bin', 'rb').read()
n, = struct.unpack_from('<I', d, 0)
snv = struct.unpack_from('<%dI' % n, d, 4)
off = 4 + 4 * n
pm = struct.unpack_from('<65536H', d, off); off += 131072
dm = struct.unpack_from('<65536H', d, off)
open(pre + '_snv.hex', 'w').write('\n'.join('%08x' % v for v in snv) + '\n')
open(pre + '_pm.hex', 'w').write('\n'.join('%04x' % v for v in pm) + '\n')
open(pre + '_dm.hex', 'w').write('\n'.join('%04x' % v for v in dm) + '\n')
cpu = {}
for l in open(pre + '_sys.txt'):
    k, i, v = l.split()
    if k == 'cpu': cpu[int(i)] = int(v, 16)
AX, CX, DX, BX, SP, BP, SI, DI, ES, CS, SS, DS, IP, FL = [cpu[i] for i in range(14)]
def mov(opc, v): return bytes([opc, v & 0xFF, v >> 8])
stub = (bytes([0xFA]) + mov(0xB8, SS) + bytes([0x8E, 0xD0]) + mov(0xBC, SP)          # cli; mov ax,SS; mov ss,ax; mov sp,SP
        + mov(0xB8, FL) + b'\x50' + mov(0xB8, CS) + b'\x50' + mov(0xB8, IP) + b'\x50'   # push flags, cs, ip (iret frame)
        + mov(0xB8, ES) + bytes([0x8E, 0xC0]) + mov(0xB8, DS) + bytes([0x8E, 0xD8])    # es, ds
        + mov(0xB9, CX) + mov(0xBA, DX) + mov(0xBB, BX) + mov(0xBD, BP) + mov(0xBE, SI) + mov(0xBF, DI) + mov(0xB8, AX)
        + b'\xCF')                                                                      # iret
m = bytearray(open(pre + '_mem.bin', 'rb').read())
m[0x70000:0x70000 + len(stub)] = stub
# reset vector FFFF0: jmp far 7000:0000
m[0xFFFF0:0xFFFF5] = bytes([0xEA, 0x00, 0x00, 0x00, 0x70])
open(pre + '_mem.bin', 'wb').write(m)
print('stub %d bytes, cpu CS:IP=%04x:%04x SS:SP=%04x:%04x pc_dsp=%04x' % (len(stub), CS, IP, SS, SP, snv[28]))
