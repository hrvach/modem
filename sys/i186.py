"""ctypes wrapper for libi186.so"""
import ctypes as C, os
_l = C.CDLL(os.path.join(os.path.dirname(os.path.abspath(__file__)), "libi186.so"))
IORD = C.CFUNCTYPE(C.c_uint32, C.c_void_p, C.c_uint16, C.c_int)
IOWR = C.CFUNCTYPE(None, C.c_void_p, C.c_uint16, C.c_int, C.c_uint32)
MMRD = C.CFUNCTYPE(C.c_uint32, C.c_void_p, C.c_uint32, C.c_int)
MMWR = C.CFUNCTYPE(None, C.c_void_p, C.c_uint32, C.c_int, C.c_uint32)
_l.i186_new.restype = C.c_void_p
_l.i186_mem.restype = C.POINTER(C.c_uint8); _l.i186_mem.argtypes = [C.c_void_p]
_l.i186_hits.restype = C.POINTER(C.c_uint32); _l.i186_hits.argtypes = [C.c_void_p]
_l.i186_ring.restype = C.POINTER(C.c_uint32); _l.i186_ring.argtypes = [C.c_void_p]
_l.i186_ring_idx.restype = C.c_uint32; _l.i186_ring_idx.argtypes = [C.c_void_p]
_l.i186_run.restype = C.c_int; _l.i186_run.argtypes = [C.c_void_p, C.c_uint64]
_l.i186_get.restype = C.c_uint32; _l.i186_get.argtypes = [C.c_void_p, C.c_int]
_l.i186_set.argtypes = [C.c_void_p, C.c_int, C.c_uint32]
_l.i186_reset.argtypes = [C.c_void_p]
_l.i186_set_hooks.argtypes = [C.c_void_p, IORD, IOWR, MMRD, MMWR, C.c_void_p]
_l.i186_set_mmio_page.argtypes = [C.c_void_p, C.c_uint32, C.c_int]
_l.i186_set_ro_page.argtypes = [C.c_void_p, C.c_uint32, C.c_int]
_l.i186_set_bp.argtypes = [C.c_void_p, C.c_uint32, C.c_int]
_l.i186_irq.argtypes = [C.c_void_p, C.c_int]
_l.i186_stop.argtypes = [C.c_void_p]
_l.i186_cycles.restype = C.c_uint64; _l.i186_cycles.argtypes = [C.c_void_p]
_l.i186_add_cycles.argtypes = [C.c_void_p, C.c_uint64]
_l.i186_get_badop.restype = C.c_uint32; _l.i186_get_badop.argtypes = [C.c_void_p]
R = dict(AX=0, CX=1, DX=2, BX=3, SP=4, BP=5, SI=6, DI=7, ES=8, CS=9, SS=10, DS=11, IP=12, FLAGS=13)
ST_OK, ST_BP, ST_BADOP, ST_HLT, ST_STOP = range(5)
class CPU:
    def __init__(self):
        self.h = _l.i186_new(); self.mem = _l.i186_mem(self.h); self.hits = _l.i186_hits(self.h); self._h = None
    def reset(self): _l.i186_reset(self.h)
    def run(self, n): return _l.i186_run(self.h, n)
    def get(self, k): return _l.i186_get(self.h, R[k])
    def set(self, k, v): _l.i186_set(self.h, R[k], v)
    def hooks(self, io_rd, io_wr, mm_rd=None, mm_wr=None):
        self._h = (IORD(lambda c, p, w: io_rd(p, w) & (0xFFFF if w else 0xFF)), IOWR(lambda c, p, w, v: io_wr(p, w, v)),
                   MMRD(lambda c, a, w: mm_rd(a, w)) if mm_rd else C.cast(None, MMRD), MMWR(lambda c, a, w, v: mm_wr(a, w, v)) if mm_wr else C.cast(None, MMWR))
        _l.i186_set_hooks(self.h, *self._h, None)
    def mmio_page(self, page, on=True): _l.i186_set_mmio_page(self.h, page, int(on))
    def ro_page(self, page, on=True): _l.i186_set_ro_page(self.h, page, int(on))
    def bp(self, phys, on=True): _l.i186_set_bp(self.h, phys, int(on))
    def irq(self, vec): _l.i186_irq(self.h, vec)
    def stop(self): _l.i186_stop(self.h)
    @property
    def cycles(self): return _l.i186_cycles(self.h)
    def add_cycles(self, n): _l.i186_add_cycles(self.h, n)
    def badop(self): v = _l.i186_get_badop(self.h); return v & 0xFFFFFF, v >> 24
    def phys_pc(self): return ((self.get("CS") << 4) + self.get("IP")) & 0xFFFFF
    def recent(self, n=24):
        i = _l.i186_ring_idx(self.h); r = _l.i186_ring(self.h)
        return [r[(i - n + k) & 255] for k in range(n)]
    def rd8(self, a): return self.mem[a & 0xFFFFF]
    def rd16(self, a): return self.mem[a & 0xFFFFF] | (self.mem[(a + 1) & 0xFFFFF] << 8)
    def wr8(self, a, v): self.mem[a & 0xFFFFF] = v & 0xFF
    def load(self, addr, blob):
        for i, b in enumerate(blob): self.mem[(addr + i) & 0xFFFFF] = b
    def state(self):
        return " ".join("%s=%04X" % (k, self.get(k)) for k in ("AX","BX","CX","DX","SP","BP","SI","DI","DS","ES","SS","CS","IP","FLAGS"))
