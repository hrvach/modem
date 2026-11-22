#!/usr/bin/env python3
"""Turns a Courier firmware .XMD into the flash image the MiSTer core loads (boot0.rom).

    xmd2rom.py <firmware.XMD> <boot0.rom>

XMD decode as in the C emulator's tools/xmd_decode.py (128-byte header, then 128-byte blocks XORed with a rolling key starting at 0x55). The boot block CRC the supervisor checks at
start-up (flash 0x77FFE, over 0x40000..0x77FFD) is not in the XMD (SDL writes it after programming), so it is computed here exactly as the C glue does (machine.c boot_crc) and written
when the slot is still erased; an image that already carries one keeps it. Local files only: never publish the XMD or the image.
"""
import sys

HEADER, BLOCK, FLASH = 128, 128, 524288
CRC_FROM, CRC_SLOT = 0x40000, 0x77FFE


def decode(xmd):
    if len(xmd) != HEADER + FLASH:
        raise SystemExit("unexpected XMD size %d (want %d)" % (len(xmd), HEADER + FLASH))
    body, out, key = xmd[HEADER:], bytearray(), 0x55
    for i in range(0, len(body), BLOCK):
        dec = bytes(b ^ key for b in body[i:i + BLOCK])
        out += dec
        key = dec[-1]
    return bytearray(out)


def boot_crc(flash):
    crc = 0xFFFF
    for i in range(CRC_FROM, CRC_SLOT):
        dx = crc
        al = flash[i] ^ (dx & 0xFF)
        ax = (al << 4) & 0xFFFF
        dx = (dx & 0xFF00) | al
        dx ^= ax
        ax >>= 1
        dx = ((dx & 0xFF) << 8) | (dx >> 8)
        dx ^= ax
        ax = (ax << 4) & 0xFFFF
        ax = (ax & 0x00FF) | (ax & 0x0700)
        dx ^= ax
        ax = (ax << 1) & 0xFFFF
        dx = (dx & 0xFF00) | ((dx ^ (ax >> 8)) & 0xFF)
        crc = dx & 0xFFFF
    return crc


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    flash = decode(open(sys.argv[1], "rb").read())
    if flash[CRC_SLOT] == 0xFF and flash[CRC_SLOT + 1] == 0xFF:
        crc = boot_crc(flash)
        flash[CRC_SLOT], flash[CRC_SLOT + 1] = crc & 0xFF, crc >> 8
        print("boot CRC %04X written at %05X" % (crc, CRC_SLOT))
    else:
        print("image already carries a boot CRC: %02X%02X" % (flash[CRC_SLOT + 1], flash[CRC_SLOT]))
    open(sys.argv[2], "wb").write(flash)


if __name__ == "__main__":
    main()
