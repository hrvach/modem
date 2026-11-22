#!/usr/bin/env python3
"""trapdump.py CAPTURE.txt [dsp_listing.asm] -- read the frozen rings the trap latched (heartbeat text from the DTE port: Ctrl-A x3, D, with the modem crashed):
   '#nn Rw AAAAA CCDD'  host -> DSP commands (AAAAA = DSP model time / 4096, CC = command, DD = argument), oldest first in each 64 block
   '$nn Wb AAAAA DDDD'  DSP -> host messages (word 6 in the address field, word 7 as data)
   '!nn Rb AAAAA OOOO'  DSP instructions retired (program counter, opcode), oldest first
Prints the last block of each ring in order. With a listing (c5xdis format "ADDR: ...") the program counters are annotated."""
import re, sys
txt = open(sys.argv[1], errors="replace").read().replace("\r", "\n")
asm = {}
if len(sys.argv) > 2:
    for l in open(sys.argv[2], errors="replace"):
        m = re.match(r"\s*([0-9a-fA-F]{4}):\s*(.*)", l)
        if m:
            asm[int(m.group(1), 16)] = m.group(2).strip()
rings = {"#": [], "$": [], "!": [], "%": []}
for m in re.finditer(r"([#$!%])([0-9A-F]{2}) R?W?[wb] ?([0-9A-F]{5}) ([0-9A-F]{4})", txt):
    rings[m.group(1)].append((int(m.group(2), 16), int(m.group(3), 16), int(m.group(4), 16)))
for k, name in (("#", "host -> DSP commands"), ("$", "DSP -> host messages"), ("!", "DSP instructions (pc op)"), ("%", "DSP writes to data 0x326 (writer pc, value)")):
    e = rings[k][-64:]
    print("==", name, "(%d entries seen, last block of %d)" % (len(rings[k]), len(e)))
    for i, a, d in e:
        if k == "#":
            print("  %02X  t=%.3fs  cmd %02X arg %02X" % (i, a * 4096 / 40.32e6, d >> 8, d & 255))
        elif k == "$":
            print("  %02X  w6=%04X w7=%04X" % (i, a & 0xFFFF, d))
        elif k == "%":
            print("  %02X  pc %04X  wrote %04X  %s" % (i, a & 0xFFFF, d, asm.get(a & 0xFFFF, "")))
        else:
            print("  %02X  %04X  %04X  %s" % (i, a & 0xFFFF, d, asm.get(a & 0xFFFF, "")))
