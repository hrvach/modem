#!/usr/bin/env python3
"""Decode a USRobotics Courier SV*.XMD firmware image.

Layout: 0x80-byte header (XOR 0x4A), then 4096 x 128-byte blocks of flash.
Each block is XORed with one byte: the key for block n is the LAST DECODED
(plaintext) byte of block n-1; the first block uses decoded header[9]
(0x55 here). This is exactly what the modem's boot-block XMODEM receiver does
(RAM 0xD1E: header ^0x4A, key=buf[9]; RAM 0xC8E: buf^=key, key=buf[0x7F]).
Flash address A  <->  file offset A + 0x80.
"""
import sys

def decode(data: bytes):
    hdr = bytes(b ^ 0x4A for b in data[:0x80])
    out, key = bytearray(), hdr[9]
    for o in range(0x80, len(data), 0x80):
        p = bytes(b ^ key for b in data[o:o + 0x80])
        out += p
        key = p[-1]
    return hdr, bytes(out)

if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    hdr, flash = decode(open(src, "rb").read())
    open(dst, "wb").write(flash)
    open(dst + ".hdr", "wb").write(hdr)
    print(f"wrote {len(flash):#x} bytes flash image to {dst} (+ header to {dst}.hdr)")
