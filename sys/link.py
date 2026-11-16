"""Two emulated modems on one simulated phone line.
Central-office state machine: dial tone -> (caller dials, DTMF detected) -> ring -> callee answers -> audio connected both ways."""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from machine import *
from line import *
FS = 7200
import ctypes
_rl = ctypes.CDLL(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'libresamp.so'))
_rl.rs_new.restype = ctypes.c_void_p; _rl.rs_run.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_int, ctypes.c_double, ctypes.c_double]
LINE8K = os.environ.get('LINE8K', '0') == '1'    # route each direction through the 8000 Hz PCM telephone line (codec rate -> 8 kHz -> far codec rate, band-limited); LINE8K=0 = old direct copy / linear interpolation
class Resampler:
    def __init__(self): self.h = _rl.rs_new()
    def __call__(self, xs, r_in, r_out):
        n = len(xs)
        if not n: return []
        a = (ctypes.c_int16 * n)(*[max(-32768, min(32767, int(v))) for v in xs]); mo = int(n * r_out / r_in) + 4; o = (ctypes.c_int16 * mo)()
        return list(o[:_rl.rs_run(self.h, a, n, o, mo, float(r_in), float(r_out))])
DIAL_DWELL = float(os.environ.get('DIAL_DWELL', '0.5'))     # seconds between the end of the dialled digit and ring voltage at the callee (was a fixed 3.0 s)
RING_ON = float(os.environ.get('RING_ON', '2.0'))           # seconds of ring voltage per cadence period
RING_PERIOD = float(os.environ.get('RING_PERIOD', '6.0'))   # cadence period
class Link:
    """Two Machines joined by a line. TIME POLICY: both machines are advanced against ONE shared absolute clock (self._gt, in CPU cycles). Every slice the clock
    moves by self.slice; each machine is then run for (clock - its own elapsed cycles), so a machine whose last instruction/event ran past the slice gets a
    shorter budget next time and the overshoot is repaid. With relative budgets (m.run(slice)) the overshoot accumulated differently in A and B (~2% at
    1000-cycle slices), the machines drifted apart and one receive queue grew to ~46 samples. Samples are handed over once per slice (latency <= one slice);
    the call state machine (co_step) is fed 100k-cycle windows whatever the slice is. LinkMP (link_mp.py) follows the same policy."""
    def __init__(self, a=None, b=None, slice_=int(os.environ.get('LINK_SLICE', '1000'))):   # CPU cycles per lockstep slice; ~1960 = one codec sample at 10267 Hz / 20.16 MHz
        self.a = a or Machine(nvram_mode=None); self.b = b or Machine(nvram_mode=None)   # a = callee (answers), b = caller
        for m in (self.a, self.b): m.logging = False
        self.slice = slice_; self.audio = {'a': [], 'b': []}; self.gain = 1.0; self.echo = 0.0; self.gate = False     # gate: mute A->B between A starting its carrier (cmd 0x21) and B starting its mode (cmd 0x20)     # echo = hybrid leakage of a side's own transmit into its receive
        self.delay_samples = int(os.environ.get('DELAY_SAMPLES', '0')); self._dq = {'a': [], 'b': []}
        self._line = {d: (Resampler(), Resampler()) for d in ('ab', 'ba')}
        self.state = 'idle'; self.t_state = 0; self.events = []; self.txt = {'a': b'', 'b': b''}; self.answer_on_ring = True; self.ring_seen_at = 0; self.ring_t0 = 0
    def samples(self):
        """Call time in 7200 Hz units, counted from the last reset of self.audio (the codec rate can change per modem, see Machine.set_rate)."""
        if not self.audio['a'] and not self.audio['b']: self._base = self.b.cpu.cycles
        return int((self.b.cpu.cycles - getattr(self, '_base', 0)) * FS // CPU_HZ)
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
        elif self.state == 'dialing' and t > DIAL_DWELL:
            self.ring_t0 = self.samples(); self._rb_on = False; self._rb = Tones((440, 480), 2500)
            self.b.rx_gen = lambda: self._rb() if self._rb_on else 0        # ringback follows the callee's ring cadence
            self.set_state('ringing')                                        # ring voltage to the callee, ringback to the caller
        elif self.state == 'ringing':
            tr = (self.samples() - self.ring_t0) / FS
            on = (tr % RING_PERIOD) < RING_ON                                # ring cadence (US: 2 s on, 4 s off; shortened for faster test calls)
            self.a.ring_on = on
            self._rb_on = on
            if self.answer_on_ring and b'RING' in self.txt['a'] and tr > 0.5 and (self.samples() - self.ring_seen_at) / FS > 0.4:
                self.a.send("ATA\r"); self.a.ring_on = False; self.b.rx_gen = None; self.set_state('answering')
            elif b'RING' in self.txt['a'] and self.ring_seen_at is None: pass
        elif self.state == 'answering':
            self.set_state('connected')                                      # line connected both ways
    def _delayed(self, k, lst):
        if self.delay_samples <= 0: return lst
        buf = (self._dq[k] if self._dq[k] else [0] * self.delay_samples) + lst
        self._dq[k] = buf[len(lst):]; return buf[:len(lst)]
    def run(self, cycles):
        done = 0
        while done < cycles:
            # one shared absolute clock: a machine that overshot its slice (the last instruction/event ran past the budget) gets a shorter budget next time,
            # so A and B never drift apart (relative budgets let the overshoot accumulate: ~2% per machine at 1000-cycle slices)
            if not hasattr(self, '_gt'): self._gt = 0; self._off = (self.a.cpu.cycles, self.b.cpu.cycles)
            self._gt += self.slice; done += self.slice
            na = self._gt - (self.a.cpu.cycles - self._off[0]); nb = self._gt - (self.b.cpu.cycles - self._off[1])
            if na > 0: self.a.run(na)
            if nb > 0: self.b.run(nb)
            ta = self._new(self.a, 'a'); tb = self._new(self.b, 'b')
            xa = self.a.dte_text(); xb = self.b.dte_text()
            if xa:
                self.txt['a'] += xa
                if b'RING' in xa: self.ring_seen_at = self.samples()
            if xb: self.txt['b'] += xb
            self._acc_a = getattr(self, '_acc_a', []) + ta; self._acc_b = getattr(self, '_acc_b', []) + tb; self._acc_cyc = getattr(self, '_acc_cyc', 0) + self.slice
            if self._acc_cyc >= 100_000:                                     # the call state machine sees 100k-cycle windows whatever the exchange slice is
                self.co_step(self._acc_a, self._acc_b); self._acc_a = []; self._acc_b = []; self._acc_cyc = 0
            if self.state == 'connected':
                n = min(len(ta), len(tb))
                g_ab = self.gain
                if self.gate:
                    a21 = any((c & 0xFF) == 0x21 for t, c, x in self.a.cmd_log16); b20 = any((c & 0xFF) == 0x20 for t, c, x in self.b.cmd_log16)
                    if a21 and not b20: g_ab = 0.0
                if LINE8K and not self.echo:
                    ab, ba = self._line['ab'], self._line['ba']
                    rb = [int(v) & 0xFFFF for v in ab[1](ab[0]([v * g_ab for v in ta], self.a.rate, 8000), 8000, self.b.rate)]
                    ra = [int(v) & 0xFFFF for v in ba[1](ba[0]([v * self.gain for v in tb], self.b.rate, 8000), 8000, self.a.rate)]
                    self.b.rxbuf.extend(self._delayed('b', rb)); self.a.rxbuf.extend(self._delayed('a', ra))
                elif self.a.rate == self.b.rate:
                    rb = [int(ta[k] * g_ab + self.echo * tb[k]) & 0xFFFF for k in range(n)] + [int(ta[k] * g_ab) & 0xFFFF for k in range(n, len(ta))]
                    ra = [int(tb[k] * self.gain + self.echo * ta[k]) & 0xFFFF for k in range(n)] + [int(tb[k] * self.gain) & 0xFFFF for k in range(n, len(tb))]
                    self.b.rxbuf.extend(self._delayed('b', rb)); self.a.rxbuf.extend(self._delayed('a', ra))
                else:                                                        # different codec rates: resample each direction to the receiver's rate (linear interpolation)
                    self.b.rxbuf.extend(int(v * g_ab) & 0xFFFF for v in self._rs_ab(ta, self.a.rate, self.b.rate))
                    self.a.rxbuf.extend(int(v * self.gain) & 0xFFFF for v in self._rs_ba(tb, self.b.rate, self.a.rate))
    def _rs(self, st, xs, r_in, r_out):
        step = r_in / r_out; out = []
        for x in xs:
            while st[0] < 1.0:
                out.append(int(st[1] + (x - st[1]) * st[0])); st[0] += step
            st[0] -= 1.0; st[1] = x
        return out
    def _rs_ab(self, xs, r_in, r_out): return self._rs(self.__dict__.setdefault('_st_ab', [0.0, 0]), xs, r_in, r_out)
    def _rs_ba(self, xs, r_in, r_out): return self._rs(self.__dict__.setdefault('_st_ba', [0.0, 0]), xs, r_in, r_out)
    def _new(self, m, k):
        n0 = getattr(m, '_lk_seen', 0); new = m.tx_all[n0:]; m._lk_seen = len(m.tx_all); self.audio[k] += new; return new
    def text(self): return self.a.dte_text(), self.b.dte_text()   # (only valid before start_call; during a call read self.txt)
