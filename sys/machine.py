"""Full-system SV25 machine: 80186 + (later) DSP + peripherals."""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'dsp'))
from i186 import *
import c5x
DSP_CPS = 2083          # DSP cycles per codec sample (assumed)
DSP_RATIO = 0.8         # DSP cycles per 80186 cycle (20 MIPS vs 25 MHz)
FLASH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'SV25.flash.bin')
TICK = 100000
class Machine:
    def __init__(self, patch_crc=0x1735, nvram_mode=6):
        self.cpu = CPU(); flash = bytearray(open(FLASH, 'rb').read())
        if patch_crc is not None:        # SDL writes the image CRC into flash after programming; XMD does not contain it
            flash[0x77FFE] = patch_crc & 0xFF; flash[0x77FFF] = patch_crc >> 8
        self.cpu.load(0x80000, bytes(flash))
        for p in range(0x80, 0x100): self.cpu.ro_page(p)
        self.ports = {}; self.log = []; self.logging = True
        self.pcb = {}; self.pcblog = []; self.t3_start = None; self.t3_period = 0
        self.dsp_bursts = []; self._burst = {}
        self.rxq = []; self.dte_out = bytearray(); self.rx_next = 0; self.rx_gap = 30000
        self.hb_pending = False
        from collections import deque
        self.noise_amp = 8; self._seed = 12345                  # peak line-noise amplitude in DRR units (0 = digital silence)
        self.ring_on = False                                   # ring voltage present on the line (callee side)
        self.rx_gen = None                                     # optional callable returning the next line sample when the queue is empty (e.g. a dial tone)
        self.xint_mode = 1; self.cycle_model = 1; self.legacy = 0; self.tdm_irqs = False   # DSP-audit switches (legacy = 0, 0, True)
        self.rxbuf = deque(); self.rx_under = 0; self.rx_log = []; self.cur_rx = 0; self.tx_seen = 0; self.tx_all = []   # audio link: input samples from the peer, output samples we produced
        from collections import Counter
        self.port5_pcs = Counter()
        self.cmd_log16 = []; self.cmd_log = []; self.rom_replies = False; self.hb_ticks = 3; self.hb_count = 0; self.heartbeat = True   # DSP -> host INT0 heartbeat at the DSP sample rate (supervisor timebase)
        self.dsp = None; self.dsp_log = []; self.dsp_acc = 0.0
        self.h2d = {w: 0 for w in range(0x58, 0x60)}; self.d2h = {w: 0 for w in range(0x58, 0x60)}
        self.hostbytes = {}                       # host-side byte registers 0x40..0x5E (what the host wrote)
        self.h2d_pending = 0; self.d2h_valid = 0; self.imask = 0; self.evt = 0; self.int0_req = 0; self.evt_seen = 0
        self.cpu.hooks(self.iord, self.iowr, self.mmrd, self.mmwr)
        self.cpu.mmio_page(0x0F)            # PCB window 0x0FF00-0x0FFFF (memory-mapped); other bytes of the page act as RAM
        self.port_in = {0x10: 0x00, 0x12: 0x00, 0x14: 0x00}   # input-line values; reads of these ports never echo the output latch
        self.dte_speed_code = 0x02                          # stands in for the autobaud result at [0x3FBA] (one-hot speed mask; value is arbitrary)
        self.nvram_mode = nvram_mode; self.nvram_done = False; self.tx_next = 0
        self.cpu.bp(0x9EB96)                                 # F168 caller: DTE-speed-locked flag [0xEA7] bit0 comes from the (absent) NVRAM profile
        if nvram_mode is not None: self.cpu.bp(0x8063E)      # no NVRAM profile: supply the configuration value the init checks at 8000:063E
        self.cpu.reset(); self.next_tick = TICK
    def iord(self, p, w):
        if self.logging: self.log.append(("R", p, w, self.cpu.phys_pc()))
        if p == 0x00: return (self.ports.get(0, 0) & ~0x08) | (0x08 if self.rxq else 0)   # DTE status: bit3 = RX char ready
        if p == 0x0A and self.rxq: return self.rxq.pop(0)
        if p == 0x18 and self.dsp is None: return 0x03   # DSP boot ROM: bank A (bit0) and bank B (bit1) free
        if p in (0x1C, 0x1E):                             # interrupt/event status from the DSP interface
            return (self.evt & 0xFF) if p == 0x1C else 0                       # latched events: bit0 TX slot freed, bit1 DSP message waiting
        if 0x40 <= p <= 0x5E and p % 2 == 0 and self.dsp is not None:    # host reads DSP->host words
            idx = (p - 0x40) // 4; hi = ((p - 0x40) // 2) % 2; wv = self.d2h[0x58 + idx]
            if p == 0x58: self.d2h_valid = 0                               # host consumed the message
            return (wv >> 8) & 0xFF if hi else wv & 0xFF
        if p == 0x14:                                   # bit1 = ring detect (idle high; during ring toggles at 20 Hz = 120 heartbeats/period; heartbeat = hb_ticks DSP ticks)
            v = self.port_in.get(0x14, 0) | 0x02
            if self.ring_on and (((self.hb_count // self.hb_ticks) // 60) & 1): v &= ~0x02
            return v
        if p in self.port_in: return self.port_in[p]
        return self.ports.get(p, 0)
    def iowr(self, p, w, v):
        if self.logging: self.log.append(("W", p, w, v, self.cpu.phys_pc()))
        self.ports[p] = v
        if p == 0x0A: self.dte_out.append(v & 0xFF)
        if p == 0x18 and (v & 0xFF) == 4 and self.dsp is None: self.start_dsp()
        if p == 0x1C and self.dsp is not None: self.evt &= ~(v & 0xFF); self.evt_seen &= self.evt   # write-1-to-clear acknowledge
        if self.dsp is not None and 0x40 <= p <= 0x5E and p % 2 == 0:               # host -> DSP words
            idx = (p - 0x40) // 4; hi = ((p - 0x40) // 2) % 2; w = 0x58 + idx
            self.h2d[w] = (self.h2d[w] & 0x00FF) | ((v & 0xFF) << 8) if hi else (self.h2d[w] & 0xFF00) | (v & 0xFF)
            if p == 0x5E: self.h2d_pending = 1
        if 0x40 <= p <= 0x5E and p % 2 == 0 and self.dsp is None:             # banks A (0x40-0x4E) and B (0x50-0x5E): 4 words each, lo at +0, hi at +2
            self._burst[p] = v & 0xFF
            if p in (0x4E, 0x5E):
                base = 0x40 if p == 0x4E else 0x50
                self.dsp_bursts.append(tuple(self._burst.get(base + 2 * q, 0) for q in range(8))); self._burst = {}
    def take_tx(self):
        """Return the DSP output samples (signed 16-bit) produced since the last call."""
        if self.dsp is None: return []
        h = self.dsp.dxr_head(); r = self.dsp.dxr_ring(); n = h - self.tx_seen
        if n > 65536: n = 65536
        out = [(r[(h - n + i) & 0xFFFF]) for i in range(n)]; self.tx_seen = h
        out = [v - 65536 if v > 32767 else v for v in out]; self.tx_all += out
        return out
    def dte_text(self):
        b = bytes(c for c in self.dte_out if c != 0xFF); self.dte_out.clear(); return b
    def send(self, text):
        if self.cpu.rd16(0x270) == 0:                      # DTE ISR calls a hook through [0x270]; real init installs a bare `ret` (1DF0) in the other boot flow
            self.cpu.wr8(0x270, 0xF0); self.cpu.wr8(0x271, 0x1D)
        self.rxq.extend(text.encode() if isinstance(text, str) else text)
    def start_dsp(self):
        b = b''.join(bytes(x) for x in self.dsp_bursts)[16:16 + 55420]
        self.dsp = c5x.DSP(); self.dsp.load_pm(0x8000, b)
        for i in range(11): self.dsp.set_ivec_ind(i, 0x60 + i); self.dsp.dm[0x60 + i] = 0x81AE
        self.dsp.dm[0x65] = 0x8189; self.dsp.dm[0x68] = 0x820C; self.dsp.dm[0x69] = 0x81B7
        self._dxr_h = self.dsp.dxr_head()
        self.dsp.set_io(self.dsp_rd, self.dsp_wr); self.dsp.set_cmpr_ar0(True); self.dsp.set_xint_mode(self.xint_mode); self.dsp.set_cycle_model(self.cycle_model); self.dsp.set_legacy(self.legacy); self.dsp.reset(0x8000)
        self.dsp_started_at = self.cpu.cycles
        # NOTE: types 0x80-0x84 are internal supervisor events (posted by 8000:05B5 etc.), not DSP messages
    def dsp_rd(self, p):
        q = p & 0xFF
        if q == 0x57: return self.h2d_pending | ((0 if self.d2h_valid else 1) << 1)
        if 0x58 <= q <= 0x5F: return self.h2d[q]
        return 0
    def dsp_wr(self, p, v):
        q = p & 0xFF
        self.dsp_log.append((self.cpu.cycles, q, v))
        if q in (0x5E, 0x5F): self.port5_pcs[(self.dsp.get('PC'), q, v)] += 1
        if q == 0x57 and (v & 1):
            self.h2d_pending = 0; self.evt |= 1; self.int0_req = 1            # DSP consumed host word -> TX slot freed event
            cmd = self.h2d[0x5E] & 0xFF; arg = self.h2d[0x5F] & 0xFF
            self.cmd_log.append((self.cpu.cycles, cmd, arg)); self.cmd_log16.append((len(self.tx_all) + (self.dsp.dxr_head() - self.tx_seen), self.h2d[0x5E], self.h2d[0x5F]))
            if cmd == 0x01 and arg == 0x3F and self.rom_replies:             # emulate boot-ROM/app 'started' reply (type 0x84)
                self.d2h[0x5E] = 0x0084; self.d2h[0x5F] = 0; self.d2h_valid = 1; self.evt |= 2; self.int0_req = 1
        if 0x58 <= q <= 0x5F and 0x83D6 <= self.dsp.get("PC") <= 0x8420:      # only the DSP message-send routine produces messages
            self.d2h[q] = v & 0xFFFF
            if q == 0x5F: self.d2h_valid = 1; self.evt |= 2; self.int0_req = 1   # DSP->host message complete
    def mmrd(self, a, w):
        if 0x0FF00 <= a <= 0x0FFFF:
            v = self.pcb.get(a & 0xFF, 0) | (self.pcb.get((a + 1) & 0xFF, 0) << 8 if w else 0)
            if (a & 0xFF) == 0x46:                    # timer 3 control: bit5 = max count reached (after period)
                if self.t3_start is not None and self.cpu.cycles - self.t3_start >= self.t3_period: self.pcb[0x46] |= 0x20
                v = self.pcb.get(0x46, 0) | (self.pcb.get(0x47, 0) << 8)
            if (a & 0xFF) == 0x40 and self.t3_start is not None:
                v = ((self.cpu.cycles - self.t3_start) // 4) & 0xFFFF
            if (a & 0xFF) == 0x66: v = self.pcb.get(0x66, 0) | 0x08            # DTE UART status: bit3 = TX ready
            if self.logging: self.pcblog.append(("R", a & 0xFF, w, v, self.cpu.phys_pc()))
            return v & (0xFFFF if w else 0xFF)
        m = self.cpu.mem; return m[a] | (m[(a + 1) & 0xFFFFF] << 8 if w else 0)
    def mmwr(self, a, w, v):
        if 0x0FF00 <= a <= 0x0FFFF:
            self.pcb[a & 0xFF] = v & 0xFF
            if w: self.pcb[(a + 1) & 0xFF] = (v >> 8) & 0xFF
            if (a & 0xFF) == 0x40 and self.t3_start is not None: self.t3_start = self.cpu.cycles   # count reset restarts the timeout
            if (a & 0xFF) == 0x6A: self.dte_out.append(v & 0xFF)               # DTE UART transmit register
            if (a & 0xFF) == 0x46:
                self.pcb[0x46] &= ~0x20                # writing control clears the max-count flag
                if v & 0x8000:                         # EN: (re)start timer; period = max count (0 -> 65536) * 4 cycles
                    mc = self.pcb.get(0x42, 0) | (self.pcb.get(0x43, 0) << 8)
                    self.t3_start = self.cpu.cycles; self.t3_period = (mc or 0x10000) * 4
                else: self.t3_start = None
            if self.logging: self.pcblog.append(("W", a & 0xFF, w, v, self.cpu.phys_pc()))
            return
        m = self.cpu.mem; m[a] = v & 0xFF
        if w: m[(a + 1) & 0xFFFFF] = (v >> 8) & 0xFF
    def run(self, cycles, slice_=5000):
        end = self.cpu.cycles + cycles; r = ST_OK
        try: return self._run(end, slice_)
        finally: self.take_tx()                 # keep tx_all complete (the DSP output ring only holds 65536 samples)
    def _run(self, end, slice_):
        r = ST_OK
        while self.cpu.cycles < end:
            r = self.cpu.run(slice_)
            if r == ST_BP and self.cpu.phys_pc() == 0x9EB96:
                self.cpu.wr8(0xEA7, self.cpu.rd8(0xEA7) | 1); self.cpu.wr8(0x3FBA, self.dte_speed_code); continue
            if r == ST_BP and not self.nvram_done and self.cpu.phys_pc() == 0x8063E:
                self.cpu.wr8(0x5F1, self.nvram_mode); self.cpu.bp(0x8063E, False); self.nvram_done = True; continue
            if r not in (ST_OK, ST_HLT): return r
            if self.cpu.cycles >= self.next_tick: self.cpu.irq(0x0F); self.next_tick += TICK
            if self.rxq and self.cpu.cycles >= self.rx_next: self.cpu.irq(0x0E); self.rx_next = self.cpu.cycles + self.rx_gap
            elif not self.rxq and self.cpu.rd16(0x270) and self.cpu.cycles >= self.tx_next:     # TX-ready interrupt once the DTE hook exists
                self.cpu.irq(0x0E); self.tx_next = self.cpu.cycles + self.rx_gap
            if self.dsp is not None:
                self.dsp_acc += slice_ * DSP_RATIO
                while self.dsp_acc >= DSP_CPS:
                    self.dsp.run(DSP_CPS)
                    h = self.dsp.dxr_head()
                    if h != self._dxr_h:                         # one new input sample consumed per output sample produced (matched sample clocks)
                        for _ in range(min(h - self._dxr_h, 8)):
                            if self.rxbuf: self.cur_rx = self.rxbuf.popleft(); self.rx_log.append(self.cur_rx)
                            elif self.rx_gen is not None: self.cur_rx = self.rx_gen() & 0xFFFF
                            else: self.cur_rx = 0; self.rx_under += 1
                        self._dxr_h = h
                    base = self.cur_rx if self.cur_rx < 32768 else self.cur_rx - 65536
                    if self.noise_amp:                                      # line noise floor: the DSP's level estimator (NORM loop at DSP 0x8810) hangs on exact digital silence
                        self._seed = (self._seed * 1103515245 + 12345) & 0x7FFFFFFF
                        base += ((self._seed >> 16) % (2 * self.noise_amp + 1)) - self.noise_amp
                    self.dsp.serial_tick(max(-32768, min(32767, base)));
                    if self.tdm_irqs: self.dsp.irq(c5x.TRNT); self.dsp.irq(c5x.TXNT)
                    self.dsp_acc -= DSP_CPS
                    self.hb_count += 1
                    if self.heartbeat and self.hb_count % self.hb_ticks == 0: self.hb_pending = True
                if (not self.h2d_pending) and self.cpu.rd16(0x29A) != self.cpu.rd16(0x29C):
                    self.evt |= 1; self.evt_seen &= ~1             # HLE stand-in: TX slot free and the supervisor has queued words -> new TX event
                ivt = (self.cpu.rd16(0x32), self.cpu.rd16(0x30))
                if self.hb_pending and ivt not in ((0, 0x305), (0, 0)) and not (self.pcb.get(0x38, 0) & 8): self.cpu.irq(0x0C); self.hb_pending = False
                if (self.evt & ~self.evt_seen) and ivt not in ((0, 0x305), (0, 0)) and not (self.pcb.get(0x38, 0) & 8):
                    self.cpu.irq(0x0C); self.evt_seen |= self.evt
        return r
