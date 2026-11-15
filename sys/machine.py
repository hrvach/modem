"""Full-system SV25 machine: 80C186EB + DSP + peripherals.

Time base: cpu.cycles are CPU clocks at 25.8048 MHz (cycle model 1 of the core). One codec sample (7200 Hz)
= 3584 CPU clocks. Timers count at CPU/4. See fable-progress.md sections 5-8 for where each fact comes from."""
import os
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'dsp'))
from collections import deque, Counter
from i186 import *
import c5x
DSP_CPS = int(os.environ.get('DSP_CPS', '5600'))          # DSP cycles per 7200 Hz codec sample: the symbol timer PRD 0x419F (16800 cycles = 3 samples = 2400 Hz) fixes it at 5600 (CLKOUT1 = 40.32 MHz); 2083 was a wrong guess
CPU_HZ = 25804800       # from the firmware baud table (9EB0:0C1A)
SAMPLE_CYC = 3584       # CPU clocks per 7200 Hz sample
FLASH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'SV25.flash.bin')
INF = 1 << 62
# interrupt sources in default priority order: (name, vector type, IMASK bit, control register)
SRC = (("T0", 0x08, 0x01, 0x12), ("T1", 0x12, 0x01, 0x12), ("T2", 0x13, 0x01, 0x12), ("S0RX", 0x14, 0x04, 0x14), ("S0TX", 0x15, 0x04, 0x14),
       ("INT4", 0x11, 0x08, 0x16), ("INT0", 0x0C, 0x10, 0x18), ("INT1", 0x0D, 0x20, 0x1A), ("INT2", 0x0E, 0x40, 0x1C), ("INT3", 0x0F, 0x80, 0x1E))
S_T0, S_T1, S_T2, S_S0RX, S_S0TX, S_INT4, S_INT0, S_INT1, S_INT2, S_INT3 = range(10)
CON_BIT = {0x12: 0x01, 0x14: 0x04, 0x16: 0x08, 0x18: 0x10, 0x1A: 0x20, 0x1C: 0x40, 0x1E: 0x80}
EOI_BIT = {0x08: 0x01, 0x12: 0x01, 0x13: 0x01, 0x14: 0x04, 0x15: 0x04, 0x11: 0x08, 0x0C: 0x10, 0x0D: 0x20, 0x0E: 0x40, 0x0F: 0x80}
class Tmr:
    __slots__ = ('cnt', 'cmpa', 'cmpb', 'con', 'last', 'run', 'nxt')
    def __init__(self): self.cnt = 0; self.cmpa = 0; self.cmpb = 0; self.con = 0; self.last = 0; self.run = False; self.nxt = INF
class Uart:
    __slots__ = ('cmp', 'con', 'sts', 'rbuf', 'rx_t', 'bit', 'sh', 'tx_t', 'pu')
    def __init__(self): self.cmp = 0; self.con = 0; self.sts = 0x08; self.rbuf = 0; self.rx_t = INF; self.bit = 0; self.sh = 0; self.tx_t = INF; self.pu = 8
class Eeprom:
    """3-wire (Microwire, 93C66-like, 256 x 16 bit) serial EEPROM as driven by the firmware's bit-bang routines (flash 8000:1330 write, 8000:1419 read):
    CS = P1LTCH(0xFF56) bit5, SK = P1LTCH bit2, DI = P2LTCH(0xFF5E) bit7 (output while P2DIR(0xFF58) bit7 = 0), DO = P2PIN(0xFF5A) bit7 (P2DIR bit7 = 1).
    Word i is the little-endian word at 80186 RAM 0x696 + 2 i; byte 0x895 holds the checksum (sum of bytes 0x696..0x893)."""
    def __init__(self, image=None, words=256):
        self.n = words; self.w = [0xFFFF] * words; self.ewen = False; self.dirty = False
        if image:
            for i in range(min(words, len(image) // 2)): self.w[i] = image[2 * i] | (image[2 * i + 1] << 8)
        self.reset()
    def reset(self): self.state = 'idle'; self.bits = []; self.do = 1; self.addr = 0; self.rdn = 0
    def clock(self, di):
        st = self.state
        if st == 'idle':
            if di: self.state = 'cmd'; self.bits = []
        elif st == 'cmd':
            self.bits.append(di)
            if len(self.bits) == 10:
                op = self.bits[0] * 2 + self.bits[1]; a = 0
                for b in self.bits[2:]: a = (a << 1) | b
                if op == 2: self.state = 'read'; self.addr = a; self.rdn = 0; self.do = 0
                elif op == 1: self.state = 'wdata'; self.addr = a; self.bits = []
                elif op == 3:
                    if self.ewen: self.w[a % self.n] = 0xFFFF; self.dirty = True
                    self.state = 'idle'
                else:
                    sub = a >> 6
                    if sub == 3: self.ewen = True
                    elif sub == 0: self.ewen = False
                    elif sub == 2 and self.ewen: self.w = [0xFFFF] * self.n; self.dirty = True
                    self.state = 'idle'; self.do = 1
        elif st == 'read':
            self.do = (self.w[self.addr % self.n] >> (15 - self.rdn)) & 1; self.rdn += 1
            if self.rdn == 16: self.rdn = 0; self.addr = (self.addr + 1) % self.n
        elif st == 'wdata':
            self.bits.append(di)
            if len(self.bits) == 16:
                v = 0
                for b in self.bits: v = (v << 1) | b
                if self.ewen: self.w[self.addr % self.n] = v; self.dirty = True
                self.state = 'idle'; self.do = 1
    def cs_rise(self): self.state = 'idle'; self.do = 1
    def cs_fall(self): self.state = 'idle'; self.do = 1
    def image(self): return b''.join(bytes((x & 0xFF, x >> 8)) for x in self.w)

class Machine:
    def __init__(self, patch_crc=0x1735, nvram_mode=6, fax_patch=False, cpu_model=1):
        self.cpu = CPU(); flash = bytearray(open(FLASH, 'rb').read())
        if patch_crc is not None:        # SDL writes the image CRC into flash after programming; XMD does not contain it
            flash[0x77FFE] = patch_crc & 0xFF; flash[0x77FFF] = patch_crc >> 8
        self.cpu.load(0x80000, bytes(flash))
        for p in range(0x80, 0x100): self.cpu.ro_page(p)
        self.ports = {}; self.log = []; self.logging = True
        self.pcb = {}; self.pcblog = []
        self.dsp_bursts = []; self._burst = {}
        self.dte_out = bytearray()
        self.hb_pending = False
        self.noise_amp = int(os.environ.get('NOISE', '8')); self._seed = 12345                  # peak line-noise amplitude in DRR units (0 = digital silence)
        self.ring_on = False                                   # ring voltage present on the line (callee side)
        self.rx_gen = None                                     # optional callable returning the next line sample when the queue is empty (e.g. a dial tone)
        self.xint_mode = 1; self.cycle_model = 1; self.legacy = int(os.environ.get('LEGACY', '0')); self.tdm_irqs = False   # DSP-audit switches (legacy = 0, 0, True)
        self.rxbuf = deque(); self.rx_under = 0; self.rx_log = []; self.cur_rx = 0; self.tx_seen = 0; self.tx_all = []   # audio link: input samples from the peer, output samples we produced
        self.port5_pcs = Counter()
        self.cmd_log16 = []; self.cmd_log = []; self.rom_replies = False; self.hb_ticks = 3; self.hb_count = 0; self.heartbeat = True   # DSP -> host INT0 heartbeat at the DSP sample rate (supervisor timebase)
        self.dsp = None; self.dsp_log = []; self.next_samp = INF
        self.h2d = {w: 0 for w in range(0x58, 0x60)}; self.d2h = {w: 0 for w in range(0x58, 0x60)}
        self.hostbytes = {}                       # host-side byte registers 0x40..0x5E (what the host wrote)
        self.wr_pcs = Counter(); self.rd_pcs = Counter(); self.msg_log = []; self.flags56 = 0x0003; self.flagsD = 0; self.bankwr = os.environ.get('BANKWR', '1') == '1'; self.flag_log = []; self.evt4_n = 0; self.data_word = 0; self.data_full = 0; self.data_words_sent = 0; self.data_words_read = 0; self.ovl_status = 0; self.ovl_addr = 0; self.ovl_data = bytearray(); self.ovl_bytes = {}; self.ovl_loads = []
        self.h2d_pending = 0; self.d2h_valid = 0; self.evt = 0; self.int0_req = 0; self.evt_seen = 0
        # --- 80C186EB interrupt controller
        self.req = 0                                           # latched requests, bit = index into SRC (INT4 is a level: live Serial1 status)
        self.msk = 0xFD; self.primsk = 7; self.icon = {r: 0x07 for r in CON_BIT}   # IMASK, PRIMSK, xCON without the mask bit
        self.isv = {}                                          # in service: IMASK bit -> priority level
        self.offered = None; self.irq_count = Counter()
        # --- timers 0/1/2, serial 0/1, DTE line
        self.tm = [Tmr(), Tmr(), Tmr()]; self.uart = [Uart(), Uart()]
        self.line = 1                                          # DTE TXD as the modem sees it: 1 = mark/idle
        self.edges = deque(); self.txq = deque(); self.line_free = 0
        self.dte_baud = 115200; self.dte_gap = CPU_HZ // 500   # speed of the emulated terminal; idle time between characters (2 ms)
        nv = os.environ.get('NVRAM') or os.path.join(os.path.dirname(os.path.abspath(__file__)), 'nvram.bin'); self.eeprom = Eeprom(open(nv, 'rb').read() if os.path.exists(nv) else None)   # factory profile (&F1) made with tools/diag/nvgen.py; env NVRAM overrides; NVRAM=/dev/null -> blank chip
        self.p2pin = 0                                         # P2PIN bits other than bit5 (unknown inputs)
        self.pcb_mem = False                                   # PCB lives in I/O space at 0xFF00 after reset; RELREG (0xA8) bit12 moves it to memory
        self.cpu.hooks(self.iord, self.iowr, self.mmrd, self.mmwr)
        self.cpu.mmio_page(0x0F)            # PCB window 0x0FF00-0x0FFFF (memory-mapped); other bytes of the page act as RAM
        self.port_in = {0x10: 0x00, 0x12: 0x00, 0x14: 0x00}   # input-line values; reads of these ports never echo the output latch
        self.hw_idx = int(os.environ.get('HWID', '7')); self.voice_data_button = os.environ.get('VDBTN', '0') == '1'; self.set_dip()
        self.fax_patch = fax_patch; self.dte_speed_code = 0x02   # old hack: force the fax-session flag [0xEA7] bit0 so F168 installs the fixed-speed fax DTE handler
        self.nvram_mode = nvram_mode; self.nvram_done = False
        if fax_patch: self.cpu.bp(0x9EB96)
        if nvram_mode is not None: self.cpu.bp(0x8063E)      # no NVRAM profile: supply the configuration value the init checks at 8000:063E
        self.cpu.cycle_model(cpu_model); self.cpu.reset()
    def _ovl_host_ack(self, v):
        """Host acknowledge on port 0x1E during an overlay download (flash 8000:E60A): 1 = bank A (ports 0x40-0x46) filled, 2 = bank B (0x48-0x4E) filled,
        4 = download finished. The DSP consumes banks instantly here and the words are written to program memory at the address given in command 2."""
        ob = self.ovl_bytes
        if v & 1: self.ovl_data += bytes(ob.get(a, 0) for a in (0x40, 0x42, 0x44, 0x46))
        if v & 2: self.ovl_data += bytes(ob.get(a, 0) for a in (0x48, 0x4A, 0x4C, 0x4E))
        if v & 4:
            if self.ovl_data:
                self.dsp.load_pm(self.ovl_addr, bytes(self.ovl_data)); self.ovl_loads.append((self.cpu.cycles, self.ovl_addr, len(self.ovl_data)))
                self.ovl_data = bytearray()
            self.ovl_status &= ~4
    def _hw_id_bit(self):
        """8000:0951 identifies the board by clearing each of 4 output lines in turn (D=port14.6, A=port12.1, B=port14.4, C=port14.5) and reading port14.3;
        the 4 answers (D,A,B,C = MSB..LSB) index the ID table at 8000:09F6. All lines high -> 1. hw_idx = that 4-bit index (valid: 2,5,7,9,11,12,13,14)."""
        a = self.ports.get(0x12, 0xFF); b = self.ports.get(0x14, 0xFF)
        low = [bit for bit, hi in ((3, b & 0x40), (2, a & 0x02), (1, b & 0x10), (0, b & 0x20)) if not hi]
        r = 1
        for bit in low: r &= (self.hw_idx >> bit) & 1
        return r
    def set_dip(self, on=(3, 5, 8, 9)):
        """DIP switches (table 8000:7A05, reader 8000:27F9): a 0 bit = ON. Default = factory setting from the manual:
        1 OFF DTR normal, 2 OFF verbal, 3 ON result codes, 4 OFF echo, 5 ON no auto answer, 6 OFF normal CD, 7 OFF, 8 ON AT enabled, 9 ON, 10 OFF NVRAM."""
        p12 = {2: 0x02, 3: 0x01, 4: 0x08, 5: 0x04, 7: 0x80, 8: 0x40, 9: 0x20, 10: 0x10}   # port 0x12
        self.port_in[0x12] = sum(b for k, b in p12.items() if k not in on)
        self.port_in[0x14] = (self.port_in.get(0x14, 0) & ~0x04) | (0 if 6 in on else 0x04)   # switch 6 = port 0x14 bit2
        self.port_in[0x14] = (self.port_in[0x14] & ~0x40) | (0 if self.voice_data_button else 0x40)   # front-panel Voice/Data button = port 0x14 bit6, active low; held at power-on (8000:77A9) = run the self-test
        self.p2pin = (self.p2pin & ~0x40) | (0 if 1 in on else 0x40)                          # switch 1 = P2PIN bit6
    # ------------------------------------------------------------------ I/O ports
    def iord(self, p, w):
        if self.logging: self.log.append(("R", p, w, self.cpu.phys_pc()))
        if p >= 0xFF00 and not self.pcb_mem:
            v = self._preg(p & 0xFE, self.cpu.cycles, True)
            return v if w else ((v >> 8) & 0xFF if p & 1 else v & 0xFF)
        if p == 0x00: return self.ports.get(0, 0) & ~0x08
        if p == 0x18 and self.dsp is None: return 0x03   # DSP boot ROM: bank A (bit0) and bank B (bit1) free
        if p in (0x1C, 0x1E):                             # interrupt/event status from the DSP interface
            return (self.evt & 0xFF) if p == 0x1C else (self.ovl_status if self.dsp is not None else 0)   # 0x1C: bit0 TX slot freed, bit1 DSP message waiting; 0x1E: overlay-load handshake (DSP cmd 2/3 write 0x0700/0x0300 to its port 0x57: bit0/1 = bank A/B free, bit2 = ready)
        if 0x40 <= p <= 0x5E and p % 2 == 0 and self.dsp is not None:    # host reads DSP->host words
            idx = (p - 0x40) // 4; hi = ((p - 0x40) // 2) % 2; wv = self.d2h[0x58 + idx]
            if p == 0x58: self.d2h_valid = 0                               # host consumed the message
            return (wv >> 8) & 0xFF if hi else wv & 0xFF
        if p in (0x18, 0x1A) and self.dsp is not None:    # bank flags shared with the DSP (its port 0x56)
            return (self.flags56 >> (8 if p == 0x1A else 0)) & 0xFF
        if p in (0x60, 0x62) and self.dsp is not None:    # DSP data word (see dsp_wr q == 0x60): hook [0x2D3] reads hi (0x62) then lo (0x60)
            if p == 0x60: self.data_full = 0; self.data_words_read += 1
            return (self.data_word >> 8) & 0xFF if p == 0x62 else self.data_word & 0xFF
        if p == 0x14:                                   # bit1 = ring detect (idle high; during ring toggles at 20 Hz = 120 heartbeats/period; heartbeat = hb_ticks DSP ticks)
            v = self.port_in.get(0x14, 0) | 0x02
            v = (v & ~0x08) | (0x08 if self._hw_id_bit() else 0)       # hardware-ID strap (routine 8000:0951): input bit3 answers which output line is pulled low
            if self.ring_on and (((self.hb_count // self.hb_ticks) // 60) & 1): v &= ~0x02
            return v
        if p in self.port_in: return self.port_in[p]
        return self.ports.get(p, 0)
    def iowr(self, p, w, v):
        if self.logging: self.log.append(("W", p, w, v, self.cpu.phys_pc()))
        if p >= 0xFF00 and not self.pcb_mem:
            now = self.cpu.cycles; r = p & 0xFE
            if not w:
                old = self._preg(r, now); v = (old & 0x00FF) | ((v & 0xFF) << 8) if p & 1 else (old & 0xFF00) | (v & 0xFF)
            self._pwr(r, v & 0xFFFF, now); return
        self.ports[p] = v
        if p == 0x0A: self.dte_out.append(v & 0xFF)
        if p in (0x18, 0x1A) and self.dsp is not None:    # host write-1-to-clear (ack / bank filled)
            sh = 8 if p == 0x1A else 0; self.flags56 &= ~((v & 0xFF) << sh) & 0xFFFF; self.flagsD |= (v & 0xFF) << sh   # host write-1: clears E, sets D for the DSP
            if len(self.flag_log) < 400: self.flag_log.append((round(self.cpu.cycles / CPU_HZ, 2), p, v & 0xFF, self.flags56))
        if p == 0x18 and (v & 0xFF) == 4 and self.dsp is None: self.start_dsp()
        if p == 0x1C and self.dsp is not None: self.evt &= ~(v & 0xFF); self.evt_seen &= self.evt   # write-1-to-clear acknowledge
        if p == 0x1E and self.dsp is not None: self._ovl_host_ack(v & 0xFF)
        if self.dsp is not None and 0x40 <= p <= 0x4E and p % 2 == 0: self.ovl_bytes[p] = v & 0xFF
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
        """Type characters on the terminal: they go out on the DTE TXD line as 8N1 at dte_baud."""
        self.txq.extend(text.encode() if isinstance(text, str) else text)
    def start_dsp(self):
        b = b''.join(bytes(x) for x in self.dsp_bursts)[16:16 + 55420]
        self.dsp = c5x.DSP(); self.dsp.load_pm(0x8000, b)
        for i in range(11): self.dsp.set_ivec_ind(i, 0x60 + i); self.dsp.dm[0x60 + i] = 0x81AE
        self.dsp.dm[0x65] = 0x8189; self.dsp.dm[0x68] = 0x820C; self.dsp.dm[0x69] = 0x81B7
        if os.environ.get('TINTSLOT'): self.dsp.set_ivec_ind(3, int(os.environ['TINTSLOT'], 16))      # experiment: route TINT (IFR bit3) to another indirect vector slot (0x68 = the 820C timer ISR)
        self._dxr_h = self.dsp.dxr_head()
        self.dsp.set_io(self.dsp_rd, self.dsp_wr); self.dsp.set_cmpr_ar0(os.environ.get('CMPR', '0') == '1'); self.dsp.set_xint_mode(self.xint_mode); self.dsp.set_cycle_model(self.cycle_model); self.dsp.set_legacy(self.legacy); self.dsp.reset(0x8000)
        self.dsp_started_at = self.cpu.cycles; self.next_samp = self.cpu.cycles + SAMPLE_CYC; self.cpu.stop()
        # NOTE: types 0x80-0x84 are internal supervisor events (posted by 8000:05B5 etc.), not DSP messages
    def dsp_rd(self, p):
        q = p & 0xFF
        if q == 0x57: return self.h2d_pending | ((0 if self.d2h_valid else 1) << 1) | (0 if self.data_full else 4)   # bit2 = DSP->host data word channel (ports 0x60/0x62) free: the host has read the previous word
        if 0x50 <= q <= 0x5F: self.rd_pcs[(q, self.dsp.get('PC'))] += 1
        if q == 0x56: return self.flagsD                                              # host->DSP flags (set by host writes to ports 0x18/0x1A, cleared by DSP writes)
        if 0x58 <= q <= 0x5F: return self.h2d[q]
        return 0
    def dsp_wr(self, p, v):
        q = p & 0xFF
        self.dsp_log.append((self.cpu.cycles, q, v))
        self.wr_pcs[(q, self.dsp.get('PC'))] += 1
        if q == 0x56: self.flagsD &= ~v & 0xFFFF; self.flags56 |= v & 0xFFFF         # DSP write-1: clears its pending flag D and sets the host-visible flag E (bank free / word valid)
        if 0x58 <= q <= 0x5D and self.bankwr: self.d2h[q] = v & 0xFFFF                 # DSP->host bank words (host reads ports 0x40..0x56)
        if q == 0x60: self.data_word = v & 0xFFFF; self.data_full = 1; self.data_words_sent += 1       # DSP -> host synchronous data word (host reads ports 0x62 hi, 0x60 lo in the INT0 event-bit2 hook [0x2D3])
        if q in (0x5E, 0x5F): self.port5_pcs[(self.dsp.get('PC'), q, v)] += 1
        if q == 0x57 and (v & 4): self.evt |= 4; self.evt_seen &= ~4; self.int0_req = 1; self.evt4_n += 1     # DSP raises the 'service request' event (host INT0 event bit2 -> hook [0x2D3], 8000:0674)
        if q == 0x57 and (v >> 8) & 7: self.ovl_status = (v >> 8) & 7             # DSP loader reports bank/ready flags
        if q == 0x57 and (v & 1):
            self.h2d_pending = 0; self.evt |= 1; self.int0_req = 1            # DSP consumed host word -> TX slot freed event
            cmd = self.h2d[0x5E] & 0xFF; arg = self.h2d[0x5F] & 0xFF
            if cmd == 0x02: self.ovl_addr = self.h2d[0x5F] & 0xFFFF; self.ovl_data = bytearray()   # overlay download: load address in the 2nd word
            self.cmd_log.append((self.cpu.cycles, cmd, arg)); self.cmd_log16.append((len(self.tx_all) + (self.dsp.dxr_head() - self.tx_seen), self.h2d[0x5E], self.h2d[0x5F]))
            if cmd == 0x01 and arg == 0x3F and self.rom_replies:             # emulate boot-ROM/app 'started' reply (type 0x84)
                self.d2h[0x5E] = 0x0084; self.d2h[0x5F] = 0; self.d2h_valid = 1; self.evt |= 2; self.int0_req = 1
        if 0x58 <= q <= 0x5F and 0x83D6 <= self.dsp.get("PC") <= 0x8420:      # only the DSP message-send routine produces messages
            self.d2h[q] = v & 0xFFFF
            if q == 0x5F: self.d2h_valid = 1; self.evt |= 2; self.int0_req = 1; self.msg_log.append((len(self.tx_all) + (self.dsp.dxr_head() - self.tx_seen), self.d2h[0x5C], self.d2h[0x5D], self.d2h[0x5E], self.d2h[0x5F]))   # DSP->host message complete (host reads type at port 0x58 = word 0x5C low byte)
    # ------------------------------------------------------------------ interrupt controller
    def _sync_ack(self):
        """The core took the offered interrupt: clear its request latch and mark it in service."""
        o = self.offered
        if o is not None and not self.cpu.irq_pending():
            self.offered = None; self.req &= ~(1 << o); s = SRC[o]
            self.isv[s[2]] = self.icon[s[3]] & 7; self.irq_count[s[1]] += 1
    def _requests(self):
        return self.req | ((1 << S_INT4) if self.uart[1].sts & 0x60 else 0)     # INT4 = Serial1 interrupt output, level
    def _icu_eval(self):
        self._sync_ack()
        r = self._requests(); best = None
        if r:
            bp = min(self.isv.values()) if self.isv else 8                      # must beat everything in service
            if self.primsk + 1 < bp: bp = self.primsk + 1
            for i in range(10):
                if r >> i & 1:
                    s = SRC[i]
                    if self.msk & s[2]: continue
                    p = self.icon[s[3]] & 7
                    if p < bp: best = i; bp = p
        if best != self.offered:
            if self.offered is not None: self.cpu.irq_clear()
            if best is not None: self.cpu.irq(SRC[best][1])
            self.offered = best
    def _eoi(self, v):
        self._sync_ack()
        if v & 0x8000:                                                          # non-specific: highest priority in service
            if self.isv:
                lo = min(self.isv.values())
                for b in (0x01, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80):
                    if self.isv.get(b) == lo: del self.isv[b]; break
        else: self.isv.pop(EOI_BIT.get(v & 0x1F, 0), None)
    def icu_state(self):
        return "req=%s msk=%02X primsk=%d isv=%s offered=%s con=%s" % ([SRC[i][0] for i in range(10) if self._requests() >> i & 1], self.msk, self.primsk,
            self.isv, None if self.offered is None else SRC[self.offered][0], {"%02X" % k: v for k, v in self.icon.items()})
    # ------------------------------------------------------------------ timers
    def _trun(self, i):
        T = self.tm[i]; T.run = bool(T.con & 0x8000) and (i != 1 or self.line == 0)   # Timer1 is gated by T1IN: counts only while DTE TXD is space
    def _tsched(self, i):
        T = self.tm[i]
        if not T.run: T.nxt = INF; return
        lim = T.cmpa or 0x10000
        if T.cnt >= lim: lim = 0x10000
        T.nxt = T.last + (lim - T.cnt) * 4
    def _tupd(self, i, t):
        """Bring timer i up to time t (count = CPU/4), firing max-count events on the way."""
        T = self.tm[i]
        if not T.run: T.last = t; return
        n = (t - T.last) // 4
        if n <= 0: return
        T.last += n * 4
        while n:
            lim = T.cmpa or 0x10000; hit = True
            if T.cnt >= lim: lim = 0x10000; hit = False                        # count was set past the compare value: wrap at 16 bits
            d = lim - T.cnt
            if n < d: T.cnt += n; break
            n -= d; T.cnt = 0
            if hit:
                T.con |= 0x20                                                   # MC
                if T.con & 0x2000: self.req |= 1 << i                           # INT enabled: Timer0/1/2 request
                if i == 0: self.req |= 1 << S_INT3                              # assumption: T0OUT is wired to INT3 = the 200 Hz supervisor tick
                if not T.con & 1: T.con &= ~0x8000; T.run = False; T.last = t; break   # one-shot: EN clears
        self._tsched(i)
    # ------------------------------------------------------------------ DTE line and serial ports
    def _edge(self, t, lv):
        self._tupd(1, t); self.line = lv
        self._trun(1); self.tm[1].last = t; self._tsched(1)
        if lv: self.req |= 1 << S_INT1                                          # INT1 = rising edge of DTE TXD (latched even while masked)
        else:
            for u in self.uart:
                if u.rx_t == INF and (u.con & 0x20) and (u.con & 7): u.rx_t = t + u.pu // 2; u.bit = 0; u.sh = 0   # start bit: check it at mid-bit
    def _uart_rx(self, j, t):
        u = self.uart[j]; lv = self.line
        if u.bit == 0:
            if lv: u.rx_t = INF; return                                         # false start
        elif u.bit <= 8: u.sh |= lv << (u.bit - 1)
        else:
            if u.sts & 0x40: u.sts |= 0x04                                      # OE: previous character not acknowledged
            u.rbuf = u.sh; u.sts |= 0x40 | (0 if lv else 0x10); u.rx_t = INF    # RI, FE if the stop bit is 0
            if j == 0: self.req |= 1 << S_S0RX
            return
        u.bit += 1; u.rx_t = t + u.pu
    def _line_feed(self, now):
        """Start the next typed character: 8N1, LSB first."""
        c = self.txq.popleft(); bl = CPU_HZ / self.dte_baud; prev = 1
        for k, lv in enumerate([0] + [(c >> b) & 1 for b in range(8)] + [1]):
            if lv != prev: self.edges.append((now + int(k * bl + 0.5), lv)); prev = lv
        self.line_free = now + int(10 * bl + 0.5) + self.dte_gap
    # ------------------------------------------------------------------ PCB (memory mapped at 0xFF00)
    def _preg(self, r, now, rd=False):
        """Value of the 16-bit PCB register r; rd = apply read side effects."""
        if 0x30 <= r <= 0x46:
            i = (r - 0x30) >> 3; k = r & 6; T = self.tm[i]; self._tupd(i, now)
            return (T.cnt, T.cmpa, T.cmpb, T.con)[k >> 1]
        if 0x60 <= r <= 0x7A:
            j = (r >> 4) - 6; k = r & 0x0E; u = self.uart[j]
            if k == 6:
                v = u.sts
                if rd:
                    u.sts &= ~0xF4                                              # reading SxSTS clears RB8, RI, TI, FE, OE
                    if j == 1 and v & 0x60: self.cpu.stop()                     # INT4 level drops
                return v
            return (u.cmp, 0, u.con, 0, u.rbuf, 0)[k >> 1] if k <= 0x0A else 0
        if r in CON_BIT: return self.icon[r] | (8 if self.msk & CON_BIT[r] else 0)
        if r == 0x08: return self.msk
        if r == 0x0A: return self.primsk
        if r == 0x0C: self._sync_ack(); return sum(self.isv)
        if r == 0x0E:
            q = self._requests(); return sum(SRC[i][2] for i in range(10) if q >> i & 1 and i not in (S_T1, S_T2, S_S0TX)) | (1 if q & 7 else 0) | (4 if q & 0x18 else 0)
        if r == 0x10: return self.req & 7
        if r == 0x5A:
            v = (self.p2pin & ~0x20) | (0x20 if self.line else 0)         # P2PIN bit5 = raw DTE TXD
            v &= ~0x80
            if self.pcb.get(0x58, 0) & 0x80: v |= 0x80 if self.eeprom.do else 0     # bit7 = EEPROM DO while P2.7 is an input
            else: v |= self.pcb.get(0x5E, 0) & 0x80                        # ... else the driven latch value
            return v
        return self.pcb.get(r, 0) | (self.pcb.get(r + 1, 0) << 8)
    def _pwr(self, r, v, now):
        old = self.pcb.get(r, 0)
        self.pcb[r] = v & 0xFF; self.pcb[r + 1] = v >> 8
        if r == 0x56:                                                          # P1LTCH: EEPROM chip select (bit5) and clock (bit2)
            ee = self.eeprom; cs0 = old & 0x20; cs1 = v & 0x20
            if cs1 and not cs0: ee.cs_rise()
            elif cs0 and not cs1: ee.cs_fall()
            if cs1 and (v & 4) and not (old & 4): ee.clock((self.pcb.get(0x5E, 0) >> 7) & 1)
        if 0x30 <= r <= 0x46:
            i = (r - 0x30) >> 3; k = r & 6; T = self.tm[i]; self._tupd(i, now)
            if k == 0: T.cnt = v
            elif k == 2: T.cmpa = v
            elif k == 4: T.cmpb = v
            else:
                en = (v & 0x8000) if v & 0x4000 else (T.con & 0x8000)           # EN changes only when INH is written 1
                T.con = (v & 0x3FFF) | en
            self._trun(i); T.last = now; self._tsched(i); self.cpu.stop()
        elif 0x60 <= r <= 0x7A:
            j = (r >> 4) - 6; k = r & 0x0E; u = self.uart[j]
            if k == 0: u.cmp = v; u.pu = 8 * ((v & 0x7FFF) + 1)
            elif k == 4:
                u.con = v
                if not v & 0x20: u.rx_t = INF                                   # REN off aborts reception
            elif k == 0x0A:
                self.dte_out.append(v & 0xFF); u.sts &= ~0x08                   # TXE low while the character shifts out
                u.tx_t = (now if u.tx_t == INF else u.tx_t) + 10 * u.pu; self.cpu.stop()
        elif r in CON_BIT:
            self.icon[r] = v & 0x77
            self.msk = (self.msk | CON_BIT[r]) if v & 8 else (self.msk & ~CON_BIT[r]); self.cpu.stop()
        elif r == 0x08:
            self.msk = v & 0xFD; self.cpu.stop()
        elif r == 0x0A: self.primsk = v & 7; self.cpu.stop()
        elif r == 0x02: self._eoi(v); self.cpu.stop()
        elif r == 0xA8: self.pcb_mem = bool(v & 0x1000)                         # RELREG: firmware writes 0x10FF = memory mapped at 0x0FF00
    def mmrd(self, a, w):
        if self.pcb_mem and 0x0FF00 <= a <= 0x0FFFF:
            v = self._preg(a & 0xFE, self.cpu.cycles, True)
            if not w: v = (v >> 8) & 0xFF if a & 1 else v & 0xFF
            if self.logging: self.pcblog.append(("R", a & 0xFF, w, v, self.cpu.phys_pc()))
            return v & 0xFFFF
        m = self.cpu.mem; return m[a] | (m[(a + 1) & 0xFFFFF] << 8 if w else 0)
    def mmwr(self, a, w, v):
        if self.pcb_mem and 0x0FF00 <= a <= 0x0FFFF:
            if self.logging: self.pcblog.append(("W", a & 0xFF, w, v, self.cpu.phys_pc()))
            now = self.cpu.cycles; r = a & 0xFE
            if not w:
                old = self._preg(r, now)
                v = (old & 0x00FF) | ((v & 0xFF) << 8) if a & 1 else (old & 0xFF00) | (v & 0xFF)
            self._pwr(r, v & 0xFFFF, now)
            return
        m = self.cpu.mem; m[a] = v & 0xFF
        if w: m[(a + 1) & 0xFFFFF] = (v >> 8) & 0xFF
    # ------------------------------------------------------------------ main loop
    def _sample(self):
        """One codec sample period of the DSP."""
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
        self.dsp.serial_tick(max(-32768, min(32767, base)))
        if self.tdm_irqs: self.dsp.irq(c5x.TRNT); self.dsp.irq(c5x.TXNT)
        self.hb_count += 1
        if self.heartbeat and self.hb_count % self.hb_ticks == 0: self.hb_pending = True
    def _service(self, now):
        """Process everything that is due at time `now`."""
        edges = self.edges; u0, u1 = self.uart
        while True:                                             # line edges and receiver sample points, in time order
            t = edges[0][0] if edges else INF; k = 0
            if u0.rx_t < t: t = u0.rx_t; k = 1
            if u1.rx_t < t: t = u1.rx_t; k = 2
            if t > now: break
            if k == 0: self._edge(*edges.popleft())
            else: self._uart_rx(k - 1, t)
        if self.txq and not edges and now >= self.line_free: self._line_feed(now)
        for j in (0, 1):
            u = self.uart[j]
            if u.tx_t <= now:
                u.tx_t = INF; u.sts |= 0x28                     # TXE, TI
                if j == 0: self.req |= 1 << S_S0TX
        tm = self.tm
        if tm[0].nxt <= now: self._tupd(0, now)
        if tm[1].nxt <= now: self._tupd(1, now)
        if tm[2].nxt <= now: self._tupd(2, now)
        if now >= self.next_samp:
            while now >= self.next_samp: self._sample(); self.next_samp += SAMPLE_CYC
            cpu = self.cpu
            if (not self.h2d_pending) and cpu.rd16(0x29A) != cpu.rd16(0x29C):
                self.evt |= 1; self.evt_seen &= ~1             # HLE stand-in: TX slot free and the supervisor has queued words -> new TX event
            if self.hb_pending or (self.evt & ~self.evt_seen):
                if (cpu.rd16(0x32), cpu.rd16(0x30)) not in ((0, 0x305), (0, 0)):   # only once the firmware has installed its INT0 handler
                    self.req |= 1 << S_INT0; self.hb_pending = False; self.evt_seen |= self.evt
    def _next_event(self):
        t = self.next_samp; tm = self.tm; u0, u1 = self.uart
        if tm[0].nxt < t: t = tm[0].nxt
        if tm[1].nxt < t: t = tm[1].nxt
        if tm[2].nxt < t: t = tm[2].nxt
        if u0.rx_t < t: t = u0.rx_t
        if u1.rx_t < t: t = u1.rx_t
        if u0.tx_t < t: t = u0.tx_t
        if u1.tx_t < t: t = u1.tx_t
        if self.edges:
            if self.edges[0][0] < t: t = self.edges[0][0]
        elif self.txq and self.line_free < t: t = self.line_free
        return t
    def run(self, cycles, slice_=None):
        end = self.cpu.cycles + cycles
        try: return self._run(end)
        finally: self.take_tx()                 # keep tx_all complete (the DSP output ring only holds 65536 samples)
    def _run(self, end):
        cpu = self.cpu; r = ST_OK
        while True:
            now = cpu.cycles
            if now >= end: break
            self._service(now); self._icu_eval()
            b = min(end, self._next_event()) - now
            r = cpu.run(b if b > 0 else 1)
            self._sync_ack()
            if r == ST_BP:
                pc = cpu.phys_pc()
                if pc == 0x9EB96 and self.fax_patch:
                    cpu.wr8(0xEA7, cpu.rd8(0xEA7) | 1); cpu.wr8(0x3FBA, self.dte_speed_code); continue
                if not self.nvram_done and pc == 0x8063E:
                    cpu.wr8(0x5F1, self.nvram_mode); cpu.bp(0x8063E, False); self.nvram_done = True; continue
                return r
            if r not in (ST_OK, ST_HLT, ST_STOP): return r
        return r
