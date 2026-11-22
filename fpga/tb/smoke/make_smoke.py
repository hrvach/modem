#!/usr/bin/env python3
"""Generates the end-to-end smoke images for tb_modem_core: a flash image with a tiny 80186 program and a tiny DSP program (sent as firmware bursts),
and a zero NVRAM. Expected DTE output: 34 12 4B (the DSP echoed the mailbox word 0x1234 written by the 186, then 'K').
Usage: make_smoke.py <outdir>"""
import sys, os
out = sys.argv[1] if len(sys.argv) > 1 else "."
flash = bytearray(0x80000)           # 186 physical 0x80000..0xFFFFF
def put(phys, data):
    flash[phys - 0x80000: phys - 0x80000 + len(data)] = bytes(data)

# DSP program (loaded at program 0x8000 by three bursts after two skipped ones)
dsp = [0xBC00,                       # LDP #0
       0xBEC4, 0xC000,               # RPT #0xC000
       0xB900,                       # LACK #0 (repeated: a delay so the 186 can write the mailbox first)
       0xAF60, 0x0058,               # IN  dm[0x60], port 0x58   (host word 0)
       0x0C60, 0x005C,               # OUT dm[0x60], port 0x5C   (DSP word 4)
       0x0C60, 0x005F,               # OUT dm[0x60], port 0x5F   (DSP word 7: message valid)
       0x7980, 0x800B]               # B $
assert len(dsp) == 12
stream = bytearray(16)               # the first 16 bytes are skipped by the glue
for w in dsp:
    stream += bytes([w & 0xFF, w >> 8])
assert len(stream) == 40

TBL = 0xE100
code = bytearray()
code += bytes([0xFA, 0x8C, 0xC8, 0x8E, 0xD8, 0xBE, TBL & 0xFF, TBL >> 8])      # CLI; MOV AX,CS; MOV DS,AX; MOV SI,tbl
for burst in range(5):
    for p in (0x40, 0x42, 0x44, 0x46, 0x48, 0x4A, 0x4C, 0x4E):
        code += bytes([0xAC, 0xE6, p])                                          # LODSB; OUT p,AL
code += bytes([0xB0, 0x04, 0xE6, 0x18])                                          # start the DSP
code += bytes([0xB0, 0x34, 0xE6, 0x40, 0xB0, 0x12, 0xE6, 0x42])                  # host word 0 = 0x1234
code += bytes([0xE4, 0x1C, 0xA8, 0x02, 0x74, 0xFA])                              # wait for event bit 1
code += bytes([0xE4, 0x50, 0xE6, 0x0A, 0xE4, 0x52, 0xE6, 0x0A])                  # DSP word 4 -> DTE
code += bytes([0xB0, 0x4B, 0xE6, 0x0A, 0xEB, 0xFE])                              # 'K'; hang
put(0xFE000, code)
put(0xFE000 + (TBL - 0xE000), stream)
put(0xFFFF0, [0xEA, 0x00, 0xE0, 0x00, 0xF0])                                    # JMP F000:E000
# receive test: the 186 polls UART0's status register for RI, reads RBUF and echoes (byte + 1) to the DTE; no DSP involved
rx = bytearray(0x80000)
rxcode = bytes([0xFA,                       # CLI
                0xBA, 0x66, 0xFF,           # MOV DX,0xFF66   (S0STS, PCB in I/O space)
                0xED,                       # IN AX,DX
                0xA8, 0x40,                 # TEST AL,0x40    (RI)
                0x74, 0xFB,                 # JZ  -5
                0xBA, 0x68, 0xFF,           # MOV DX,0xFF68   (S0RBUF)
                0xED,                       # IN AX,DX
                0xFE, 0xC0,                 # INC AL
                0xE6, 0x0A,                 # OUT 0x0A,AL
                0xEB, 0xFE])                # hang
rx[0xFE000 - 0x80000: 0xFE000 - 0x80000 + len(rxcode)] = rxcode
rx[0xFFFF0 - 0x80000: 0xFFFF0 - 0x80000 + 5] = bytes([0xEA, 0x00, 0xE0, 0x00, 0xF0])
# interrupt-driven receive (the firmware's way: the S0RX handler reads RBUF only, never S0STS): two bytes in a row must both arrive; each is echoed + 1
irx = bytearray(0x80000)
main = bytes([0xFA, 0x31, 0xC0, 0x8E, 0xD8,                                   # CLI; XOR AX,AX; MOV DS,AX
              0xC7, 0x06, 0x50, 0x00, 0x00, 0xE1,                             # MOV WORD [0x50],0xE100   (vector 0x14: S0RX)
              0xC7, 0x06, 0x52, 0x00, 0x00, 0xF0,                             # MOV WORD [0x52],0xF000
              0xBC, 0x00, 0x02,                                               # MOV SP,0x200
              0xBA, 0x14, 0xFF, 0xEF,                                         # MOV DX,0xFF14; OUT DX,AX (AX=0: S0 interrupt unmasked)
              0xBA, 0x0A, 0xFF, 0xB8, 0x07, 0x00, 0xEF,                       # MOV DX,0xFF0A; MOV AX,7; OUT DX,AX (priority mask)
              0xFB, 0xEB, 0xFE])                                              # STI; JMP $
isr = bytes([0x50, 0x52, 0xBA, 0x68, 0xFF, 0xED, 0xFE, 0xC0, 0xE6, 0x0A,       # PUSH AX; PUSH DX; MOV DX,0xFF68; IN AX,DX; INC AL; OUT 0x0A,AL
             0xBA, 0x02, 0xFF, 0xB8, 0x00, 0x80, 0xEF,                         # EOI: MOV DX,0xFF02; MOV AX,0x8000; OUT DX,AX
             0x5A, 0x58, 0xCF])                                                # POP DX; POP AX; IRET
irx[0xFE000 - 0x80000: 0xFE000 - 0x80000 + len(main)] = main
irx[0xFE100 - 0x80000: 0xFE100 - 0x80000 + len(isr)] = isr
irx[0xFFFF0 - 0x80000: 0xFFFF0 - 0x80000 + 5] = bytes([0xEA, 0x00, 0xE0, 0x00, 0xF0])
os.makedirs(out, exist_ok=True)
open(os.path.join(out, "flash_smoke_irx.bin"), "wb").write(irx)
import random
random.seed(11)
open(os.path.join(out, "rom_smoke.bin"), "wb").write(bytes(random.getrandbits(8) for _ in range(16384)))
open(os.path.join(out, "flash_smoke_rx.bin"), "wb").write(rx)
open(os.path.join(out, "flash_smoke.bin"), "wb").write(flash)
open(os.path.join(out, "nvram_smoke.bin"), "wb").write(bytes(512))
print("wrote", out)
