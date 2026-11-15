"""ctypes wrapper for libc5x.so (TMS320C5x emulator)."""
import ctypes as C, os, struct
_lib = C.CDLL(os.path.join(os.path.dirname(os.path.abspath(__file__)), "libc5x.so"))
class IoEv(C.Structure):
    _fields_ = [("cyc", C.c_uint64), ("pc", C.c_uint16), ("port", C.c_uint16), ("val", C.c_uint16), ("wr", C.c_uint8)]
IORD = C.CFUNCTYPE(C.c_uint16, C.c_void_p, C.c_uint16)
IOWR = C.CFUNCTYPE(None, C.c_void_p, C.c_uint16, C.c_uint16)
_lib.c5x_new.restype = C.c_void_p
for n in ("pmem", "dmem", "iomem"):
    getattr(_lib, "c5x_" + n).restype = C.POINTER(C.c_uint16); getattr(_lib, "c5x_" + n).argtypes = [C.c_void_p]
_lib.c5x_hits.restype = C.POINTER(C.c_uint32); _lib.c5x_hits.argtypes = [C.c_void_p]
_lib.c5x_iolog.restype = C.POINTER(IoEv); _lib.c5x_iolog.argtypes = [C.c_void_p]
_lib.c5x_iolog_count.restype = C.c_uint32; _lib.c5x_iolog_count.argtypes = [C.c_void_p]
_lib.c5x_pcring.restype = C.POINTER(C.c_uint16); _lib.c5x_pcring.argtypes = [C.c_void_p]
_lib.c5x_pcring_idx.restype = C.c_uint32; _lib.c5x_pcring_idx.argtypes = [C.c_void_p]
_lib.c5x_run.restype = C.c_int; _lib.c5x_run.argtypes = [C.c_void_p, C.c_uint64]
_lib.c5x_get.restype = C.c_uint32; _lib.c5x_get.argtypes = [C.c_void_p, C.c_int]
_lib.c5x_set.argtypes = [C.c_void_p, C.c_int, C.c_uint32]
_lib.c5x_reset.argtypes = [C.c_void_p, C.c_uint16]
_lib.c5x_irq.argtypes = [C.c_void_p, C.c_int]
_lib.c5x_set_bp.argtypes = [C.c_void_p, C.c_uint16, C.c_int]
_lib.c5x_iolog_enable.argtypes = [C.c_void_p, C.c_int]
_lib.c5x_iolog_clear.argtypes = [C.c_void_p]
_lib.c5x_set_io.argtypes = [C.c_void_p, IORD, IOWR, C.c_void_p]
_lib.c5x_serial_tick.argtypes = [C.c_void_p, C.c_int16]
_lib.c5x_set_ivec_ind.argtypes = [C.c_void_p, C.c_int, C.c_uint16]
_lib.c5x_set_cmpr_ar0.argtypes = [C.c_void_p, C.c_int]
_lib.c5x_set_xint_mode.argtypes = [C.c_void_p, C.c_int]
_lib.c5x_set_cycle_model.argtypes = [C.c_void_p, C.c_int]
_lib.c5x_set_legacy.argtypes = [C.c_void_p, C.c_int]
_lib.c5x_idle_cycles.argtypes = [C.c_void_p]; _lib.c5x_idle_cycles.restype = C.c_uint64
_lib.c5x_total_cycles.argtypes = [C.c_void_p]; _lib.c5x_total_cycles.restype = C.c_uint64
_lib.c5x_dxr_head.restype = C.c_uint32; _lib.c5x_dxr_head.argtypes = [C.c_void_p]
_lib.c5x_dxr_ring.restype = C.POINTER(C.c_uint16); _lib.c5x_dxr_ring.argtypes = [C.c_void_p]
_lib.c5x_set_trace.argtypes = [C.c_void_p, C.c_int32]
_lib.c5x_set_watch.argtypes = [C.c_void_p, C.c_int32]; _lib.c5x_watch_hits.restype = C.c_uint32; _lib.c5x_watch_hits.argtypes = [C.c_void_p, C.c_uint32]
_lib.c5x_pc_hits.restype = C.c_uint32; _lib.c5x_pc_hits.argtypes = [C.c_void_p, C.c_uint32]; _lib.c5x_pc_hits_clear.argtypes = [C.c_void_p]
_lib.c5x_trace_n.restype = C.c_uint32; _lib.c5x_trace_n.argtypes = [C.c_void_p]
_lib.c5x_trace_get.argtypes = [C.c_void_p, C.c_uint32, C.POINTER(C.c_uint32), C.POINTER(C.c_uint16), C.POINTER(C.c_uint16)]
_lib.c5x_stop.argtypes = [C.c_void_p]
_lib.c5x_set_bio.argtypes = [C.c_void_p, C.c_int]
REG = dict(PC=0, ACC=1, ACCB=2, PREG=3, T0=4, T1=5, T2=6, ST0=20, ST1=21, PMST=22, RPTC=23, IFR=24, IMR=25, SP=26,
           BMAR=29, DBMR=30, INDX=31, ARCR=32, DXR=33, DRR=34, TIM=35, PRD=36, IDLE=37, PUSH=40, SETIDLE=41)
for i in range(8): REG["AR%d" % i] = 7 + i
RUN_OK, RUN_BP, RUN_BADOP, RUN_STOP = range(4)
INT1, INT2, INT3, TINT, RINT, XINT, TRNT, TXNT, INT4 = range(9)

class DSP:
    def __init__(self):
        self.h = _lib.c5x_new()
        self.pm = self.pmem = _lib.c5x_pmem(self.h); self.dm = self.dmem = _lib.c5x_dmem(self.h); self.io = _lib.c5x_iomem(self.h)
        self.hits = _lib.c5x_hits(self.h)
        self._rd = self._wr = None
    def load_pm(self, addr, blob):
        for i, (w,) in enumerate(struct.iter_unpack("<H", blob[: len(blob) // 2 * 2])): self.pm[(addr + i) & 0xFFFF] = w
    def reset(self, pc): _lib.c5x_reset(self.h, pc)
    def run(self, cycles): return _lib.c5x_run(self.h, cycles)
    def get(self, name): return _lib.c5x_get(self.h, REG[name])
    def set(self, name, v): _lib.c5x_set(self.h, REG[name], v)
    def irq(self, bit): _lib.c5x_irq(self.h, bit)
    def bp(self, a, on=True): _lib.c5x_set_bp(self.h, a, int(on))
    def log(self, on=True): _lib.c5x_iolog_enable(self.h, int(on))
    def log_clear(self): _lib.c5x_iolog_clear(self.h)
    def events(self):
        n = _lib.c5x_iolog_count(self.h); a = _lib.c5x_iolog(self.h)
        return [(a[i].cyc, a[i].pc, a[i].port, a[i].val, a[i].wr) for i in range(n)]
    def set_io(self, rd=None, wr=None):
        self._rd = IORD(lambda ctx, p: rd(p) & 0xFFFF) if rd else C.cast(None, IORD)
        self._wr = IOWR(lambda ctx, p, v: wr(p, v)) if wr else C.cast(None, IOWR)
        _lib.c5x_set_io(self.h, self._rd, self._wr, None)
    def serial_tick(self, rx=0): _lib.c5x_serial_tick(self.h, rx)
    def set_ivec_ind(self, bit, daddr): _lib.c5x_set_ivec_ind(self.h, bit, daddr)
    def set_cmpr_ar0(self, v): _lib.c5x_set_cmpr_ar0(self.h, int(v))
    def set_xint_mode(self, m): _lib.c5x_set_xint_mode(self.h, int(m))
    def idle_cycles(self): return _lib.c5x_idle_cycles(self.h)
    def total_cycles(self): return _lib.c5x_total_cycles(self.h)
    def set_legacy(self, m): _lib.c5x_set_legacy(self.h, int(m))
    def set_cycle_model(self, m): _lib.c5x_set_cycle_model(self.h, int(m))
    def dxr_head(self): return _lib.c5x_dxr_head(self.h)
    def dxr_ring(self): return _lib.c5x_dxr_ring(self.h)
    def set_watch(self, a): _lib.c5x_set_watch(self.h, a)
    def watch_hits(self, pc): return _lib.c5x_watch_hits(self.h, pc)
    def pc_hits(self, pc): return _lib.c5x_pc_hits(self.h, pc)
    def pc_hits_clear(self): _lib.c5x_pc_hits_clear(self.h)
    def set_trace(self, pc): _lib.c5x_set_trace(self.h, pc)
    def trace(self):
        out = []
        for i in range(_lib.c5x_trace_n(self.h)):
            a = C.c_uint32(); r = C.c_uint16(); r2 = C.c_uint16(); _lib.c5x_trace_get(self.h, i, C.byref(a), C.byref(r), C.byref(r2)); out.append((a.value, r.value, r2.value))
        return out
    def stop(self): _lib.c5x_stop(self.h)
    def set_bio(self, v): _lib.c5x_set_bio(self.h, v)
    def recent_pcs(self, n=32):
        i = _lib.c5x_pcring_idx(self.h); r = _lib.c5x_pcring(self.h)
        return [r[(i - n + k) & 255] for k in range(n)]
    def state(self):
        return "PC=%04X ACC=%08X T0=%04X ST0=%04X ST1=%04X IFR=%04X IMR=%04X " % tuple(self.get(k) for k in ("PC","ACC","T0","ST0","ST1","IFR","IMR")) + \
               " ".join("AR%d=%04X" % (i, self.get("AR%d" % i)) for i in range(8))

def load_images(d, base_only=False):
    d.load_pm(0x8000, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "dsp_base.bin"), "rb").read())
