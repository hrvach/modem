"""Two emulated modems on one simulated phone line.
Central-office state machine: dial tone -> (caller dials, DTMF detected) -> ring -> callee answers -> audio connected both ways."""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from machine import *
from line import *
FS = 7200
class Link:
    def __init__(self, a=None, b=None, slice_=100_000):
        self.a = a or Machine(nvram_mode=None); self.b = b or Machine(nvram_mode=None)   # a = callee (answers), b = caller
        for m in (self.a, self.b): m.logging = False
        self.slice = slice_; self.audio = {'a': [], 'b': []}; self.gain = 1.0; self.echo = 0.0; self.gate = False     # gate: mute A->B between A starting its carrier (cmd 0x21) and B starting its mode (cmd 0x20)     # echo = hybrid leakage of a side's own transmit into its receive
        self.state = 'idle'; self.t_state = 0; self.events = []; self.txt = {'a': b'', 'b': b''}; self.answer_on_ring = True; self.ring_seen_at = 0; self.ring_t0 = 0
    def samples(self): return len(self.audio['b'])
    def set_state(self, st):
        self.state = st; self.t_state = self.samples(); self.events.append((self.samples() / FS, st))
    def start_call(self, number="1"):
        self.b.send("ATDT%s\r" % number); self.b.rx_gen = dial_tone(3000); self.set_state('dialtone')
    def co_step(self, ta, tb):
        t = (self.samples() - self.t_state) / FS
        quiet = (not tb) or max(map(abs, tb)) < 300
        if self.state == 'dialtone' and tb and max(map(abs, tb)) > 15000:
            self.set_state('digit')                                          # first DTMF digit starts (keep the dial tone for now)
        elif self.state == 'digit' and quiet and t > 0.05:
            self.b.rx_gen = None; self.set_state('dialing')                  # digit finished: exchange drops the dial tone
        elif self.state == 'dialing' and t > 3.0:
            self.ring_t0 = self.samples(); self._rb_on = False; self._rb = Tones((440, 480), 2500)
            self.b.rx_gen = lambda: self._rb() if self._rb_on else 0        # ringback follows the callee's ring cadence
            self.set_state('ringing')                                        # ring voltage to the callee, ringback to the caller
        elif self.state == 'ringing':
            tr = (self.samples() - self.ring_t0) / FS
            on = (tr % 6.0) < 2.0                                            # US cadence: 2 s on, 4 s off
            self.a.ring_on = on
            self._rb_on = on
            if self.answer_on_ring and b'RING' in self.txt['a'] and tr > 0.5 and (self.samples() - self.ring_seen_at) / FS > 0.4:
                self.a.send("ATA\r"); self.a.ring_on = False; self.b.rx_gen = None; self.set_state('answering')
            elif b'RING' in self.txt['a'] and self.ring_seen_at is None: pass
        elif self.state == 'answering':
            self.set_state('connected')                                      # line connected both ways
    def run(self, cycles):
        done = 0
        while done < cycles:
            self.a.run(self.slice); self.b.run(self.slice); done += self.slice
            ta = self._new(self.a, 'a'); tb = self._new(self.b, 'b')
            xa = self.a.dte_text(); xb = self.b.dte_text()
            if xa:
                self.txt['a'] += xa
                if b'RING' in xa: self.ring_seen_at = self.samples()
            if xb: self.txt['b'] += xb
            self.co_step(ta, tb)
            if self.state == 'connected':
                n = min(len(ta), len(tb))
                g_ab = self.gain
                if self.gate:
                    a21 = any((c & 0xFF) == 0x21 for t, c, x in self.a.cmd_log16); b20 = any((c & 0xFF) == 0x20 for t, c, x in self.b.cmd_log16)
                    if a21 and not b20: g_ab = 0.0
                self.b.rxbuf.extend(int(ta[k] * g_ab + self.echo * tb[k]) & 0xFFFF for k in range(n))
                self.a.rxbuf.extend(int(tb[k] * self.gain + self.echo * ta[k]) & 0xFFFF for k in range(n))
                for k in range(n, len(ta)): self.b.rxbuf.append(int(ta[k] * g_ab) & 0xFFFF)
                for k in range(n, len(tb)): self.a.rxbuf.append(int(tb[k] * self.gain) & 0xFFFF)
    def _new(self, m, k):
        n0 = getattr(m, '_lk_seen', 0); new = m.tx_all[n0:]; m._lk_seen = len(m.tx_all); self.audio[k] += new; return new
    def text(self): return self.a.dte_text(), self.b.dte_text()   # (only valid before start_call; during a call read self.txt)
