"""linering.py -- the FPGA modem's phone line as seen from the HPS: two sample rings and a control block in DDR memory (layout: rtl/line_ddr.sv).

    ln = Line()                  # maps physical 0x3A000000 through /dev/mem (or Line(path="file") for a plain file in tests)
    ln.tx_read()                 # new DAC samples (list of int16) the modem produced since the last call
    ln.rx_write(samples)         # ADC samples for the modem (int16), at the codec rate ln.rate_hz()
    ln.set_ring(True)            # the modem sees RING (port 0x14 bit 1)
    ln.set_connected(True)
"""
import mmap, os, struct

BASE = 0x3A000000
WORD = 8
A_MAGIC, A_TXCNT, A_RXTAKEN, A_STATUS, A_CTRL = 0, 1, 2, 3, 8
A_TX, A_RX = 0x400, 0x1400
RING_SAMPLES = 16384          # 4096 words of four samples
SIZE = (A_RX + 4096) * WORD
DSP_HZ = 40_320_000


class Line:
    def __init__(self, path="/dev/mem", base=BASE):
        flags = os.O_RDWR | (os.O_SYNC if path == "/dev/mem" else os.O_CREAT)
        self.fd = os.open(path, flags)
        if path != "/dev/mem":
            if os.fstat(self.fd).st_size < SIZE:
                os.ftruncate(self.fd, SIZE)
            base = 0
        self.m = mmap.mmap(self.fd, SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=base)
        self.tx_last = self.tx_count()
        self.rx_count = struct.unpack_from("<I", self.m, A_CTRL * WORD)[0]   # the control word keeps the count across restarts
        self.ctrl_flags = 0
        self.rx_taken_seen = 0

    # ---- raw words
    def _q(self, word):
        return struct.unpack_from("<Q", self.m, word * WORD)[0]

    def _put_q(self, word, v):
        struct.pack_into("<Q", self.m, word * WORD, v & 0xFFFFFFFFFFFFFFFF)

    def alive(self):
        return self.m[0:8] in (b"MDMLINE1", b"1ENILMDM")   # the FPGA writes the 64-bit constant "MDMLINE1": the first character lands in the top byte

    def tx_count(self):
        return self._q(A_TXCNT) & 0xFFFFFFFF

    def status(self):
        s = self._q(A_STATUS)
        return {"rate_cps": s & 0xFFFF, "underruns": (s >> 16) & 0xFFFF, "tx_lost": (s >> 32) & 0xFFFF, "version": s >> 48,
                "rx_taken": self._q(A_RXTAKEN) & 0xFFFFFFFF}

    def rate_hz(self):
        cps = self.status()["rate_cps"]
        return DSP_HZ / cps if cps else 0.0

    # ---- DAC samples from the modem
    def tx_read(self):
        cnt = self.tx_count()
        n = (cnt - self.tx_last) & 0xFFFFFFFF
        if n > RING_SAMPLES - 64:                  # we fell behind a whole ring: skip ahead
            self.tx_last = (cnt - RING_SAMPLES // 2) & 0xFFFFFFFF
            n = RING_SAMPLES // 2
        out = []
        base = A_TX * WORD
        for i in range(n):
            idx = (self.tx_last + i) % RING_SAMPLES
            out.append(struct.unpack_from("<h", self.m, base + idx * 2)[0])
        self.tx_last = cnt
        return out

    # ---- ADC samples for the modem
    def rx_free(self):
        taken = self._q(A_RXTAKEN) & 0xFFFFFFFF
        return RING_SAMPLES - ((self.rx_count - taken) & 0xFFFFFFFF) - 8

    def rx_write(self, samples):
        """Append samples; returns how many were taken (the ring may be full)."""
        n = min(len(samples), self.rx_free())
        base = A_RX * WORD
        for i in range(n):
            idx = (self.rx_count + i) % RING_SAMPLES
            struct.pack_into("<h", self.m, base + idx * 2, max(-32768, min(32767, int(samples[i]))))
        self.rx_count = (self.rx_count + n) & 0xFFFFFFFF
        self._put_ctrl()
        return n

    def _put_ctrl(self):
        self._put_q(A_CTRL, self.rx_count | (self.ctrl_flags << 32))

    def set_ring(self, on):
        self.ctrl_flags = (self.ctrl_flags & ~1) | (1 if on else 0)
        self._put_ctrl()

    def set_connected(self, on):
        self.ctrl_flags = (self.ctrl_flags & ~2) | (2 if on else 0)
        self._put_ctrl()


if __name__ == "__main__":
    import sys, time
    ln = Line(*(sys.argv[1:2] or []))
    print("alive:", ln.alive(), ln.status(), "rate %.1f Hz" % ln.rate_hz())
