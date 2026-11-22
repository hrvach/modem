#!/usr/bin/env python3
"""dsptrace.py -- read the DSP instruction history the FPGA keeps in HPS DDR memory (layout: rtl/dsp_trace_ddr.sv) and print / save it.

   dsptrace.py arm | disarm                 enable / disable the capture (off after every core load; nothing is written to DDR while disarmed)
   dsptrace.py freeze                       stop the capture now with the final header written (lined.py does this when the SIP call ends; sticky until the core is reloaded; arm first)
   dsptrace.py status                       header: words written, words dropped, frozen
   dsptrace.py grab OUT.bin                 copy header + ring (64 MB) to a file, or to stdout with OUT = - (`ssh board 'nice python3 dsptrace.py grab -' > ring.bin`: nothing lands in the board's tmpfs); cheap, analyse on the PC
   dsptrace.py dump OUT.txt [N]             the last N instructions (default 200000) as lines "PC AR7", oldest first
   dsptrace.py escape [LO HI] [LIST]        find the first instruction after which AR7 is outside LO..HI (default 0BD0..0BDF) and print the 60 before it (annotated with a
                                            c5xdis-style listing "ADDR: instr" if LIST is given)
   dsptrace.py around PC [LIST] [BEFORE] [AFTER]   the last occurrence of PC with its neighbours

Words hold three PCs and AR7 (the value at the third): { ar7, pc2, pc1, pc0 }, pc0 the oldest.  The capture freezes at the first trap after a core reload, so after a crash the ring ends
at (or just after) the failure.  Run on the MiSTer (maps physical 0x3B000000 through /dev/mem); on the MiSTer use only arm / disarm / status / grab (the analysis commands build Python lists and belong on the PC:
`dsptrace.py --file RING.bin escape LIST`). A grab file is a plain copy of header + ring and works with --file.
"""
import mmap, os, struct, sys

BASE = 0x3B000000
WORD = 8
A_MAGIC, A_COUNT, A_INFO, A_RING = 0, 1, 2, 0x10
RING_BITS = 23                       # 8 M words = 64 MB (about 12 s)
LINE_BASE = 0x3A000000               # the line ring block: word 9 = trace control (bit 0 = armed), written only by this tool
A_TRCTL = 9
SIZE = (A_RING + (1 << RING_BITS)) * WORD


def open_ring(path=None):
    if path:
        fd = os.open(path, os.O_RDONLY)
        return mmap.mmap(fd, 0, mmap.MAP_SHARED, mmap.PROT_READ)
    fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
    return mmap.mmap(fd, SIZE, mmap.MAP_SHARED, mmap.PROT_READ, offset=BASE)


def set_armed(on, freeze=False):
    fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=LINE_BASE)
    struct.pack_into("<Q", m, A_TRCTL * WORD, (1 if on else 0) | (2 if freeze else 0))     # bit 0 armed, bit 1 freeze
    print("trace %s" % ("frozen" if freeze else "armed" if on else "disarmed"))


def header(m):
    magic = bytes(m[0:8])
    count = struct.unpack_from("<Q", m, A_COUNT * WORD)[0] & 0xFFFFFFFF
    info = struct.unpack_from("<Q", m, A_INFO * WORD)[0]
    return magic, count, info & 0xFFFFFFFF, (info >> 32) & 1


def entries(m, n_instr):
    """the last n_instr (pc, ar7) pairs, oldest first; ar7 is the value at the third PC of each word, None for the other two"""
    magic, count, drops, frozen = header(m)
    ring = 1 << RING_BITS
    words = min(count, ring, (n_instr + 2) // 3)
    out = []
    for i in range(count - words, count):
        w = struct.unpack_from("<Q", m, (A_RING + (i % ring)) * WORD)[0]
        pc0, pc1, pc2, ar7 = w & 0xFFFF, (w >> 16) & 0xFFFF, (w >> 32) & 0xFFFF, (w >> 48) & 0xFFFF
        out += [(pc0, None), (pc1, None), (pc2, ar7)]
    return out


def load_listing(path):
    asm = {}
    if path:
        import re
        for l in open(path, errors="replace"):
            mt = re.match(r"\s*([0-9a-fA-F]{4}):\s*(.*)", l)
            if mt:
                asm[int(mt.group(1), 16)] = mt.group(2).strip()
    return asm


def main():
    a = [x for x in sys.argv[1:]]
    path = None
    if "--file" in a:
        i = a.index("--file"); path = a[i + 1]; del a[i:i + 2]
    if not a:
        print(__doc__); return
    if a[0] in ("arm", "disarm", "freeze"):
        set_armed(a[0] != "disarm", a[0] == "freeze"); return
    m = open_ring(path)
    magic, count, drops, frozen = header(m)
    if a[0] == "grab":
        # a plain copy of header + ring (4 MB), in 1 MB chunks; the file works with --file on the PC
        total = (A_RING + (1 << RING_BITS)) * WORD
        out = sys.stdout.buffer if a[1] == "-" else open(a[1], "wb")
        for off in range(0, total, 1 << 20):
            out.write(bytes(m[off:min(total, off + (1 << 20))]))
        out.flush()
        sys.stderr.write("grabbed header + ring (count %d words, dropped %d, frozen %d)\n" % (count, drops, frozen))
    elif a[0] == "status":
        print("magic %r  words %d  dropped %d  frozen %d  (%d instructions)" % (magic, count, drops, frozen, count * 3))
    elif a[0] == "dump":
        n = int(a[2]) if len(a) > 2 else 200000
        with open(a[1], "w") as f:
            for pc, ar7 in entries(m, n):
                f.write("%04X %s\n" % (pc, "%04X" % ar7 if ar7 is not None else "----"))
        print("wrote", a[1])
    elif a[0] == "escape":
        lo, hi = (int(a[1], 16), int(a[2], 16)) if len(a) > 2 else (0x0BD0, 0x0BDF)
        listing = load_listing(a[3] if len(a) > 3 else (a[1] if len(a) == 2 else None))
        ent = entries(m, 1 << 24)
        seen_in = False
        for i, (pc, ar7) in enumerate(ent):
            if ar7 is None:
                continue
            if lo <= ar7 <= hi:
                seen_in = True
            elif seen_in:
                print("AR7 left %04X..%04X at instruction #%d of %d: AR7=%04X (value at the third pc of that word)" % (lo, hi, i, len(ent), ar7))
                for j in range(max(0, i - 60), min(len(ent), i + 6)):
                    p = ent[j][0]
                    print("  %s %04X  %s%s" % ("->" if j == i else "  ", p, listing.get(p, ""), "   AR7=%04X" % ent[j][1] if ent[j][1] is not None else ""))
                return
        print("AR7 never left the range in %d recorded instructions (frozen=%d, dropped=%d)" % (len(ent), frozen, drops))
    elif a[0] == "around":
        pcx = int(a[1], 16)
        listing = load_listing(a[2] if len(a) > 2 else None)
        before = int(a[3]) if len(a) > 3 else 40
        after = int(a[4]) if len(a) > 4 else 10
        ent = entries(m, 1 << 24)
        idx = [i for i, e in enumerate(ent) if e[0] == pcx]
        if not idx:
            print("pc %04X not in the recorded history" % pcx); return
        i = idx[-1]
        for j in range(max(0, i - before), min(len(ent), i + after)):
            p = ent[j][0]
            print("  %s %04X  %s%s" % ("->" if j == i else "  ", p, listing.get(p, ""), "   AR7=%04X" % ent[j][1] if ent[j][1] is not None else ""))
    else:
        print(__doc__)


main()
