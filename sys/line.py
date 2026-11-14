"""Telephone line signals for the emulated modems (7200 Hz samples, DXR/DRR units)."""
import math
FS = 7200
class Tones:
    """Sum of sine tones, one sample per call."""
    def __init__(self, freqs, amp=3000): self.freqs = freqs; self.amp = amp; self.n = 0
    def __call__(self):
        v = sum(math.sin(2 * math.pi * f * self.n / FS) for f in self.freqs) * self.amp; self.n += 1
        return int(v)
def dial_tone(amp=3000): return Tones((350, 440), amp)

def ringback(amp=2500):
    """US ringback: 440 + 480 Hz, 2 s on / 4 s off."""
    t = Tones((440, 480), amp); st = {'n': 0}
    def gen():
        n = st['n']; st['n'] += 1
        return t() if (n % (6 * FS)) < 2 * FS else 0
    return gen

def ringback_gen(on, amp=2500):
    """Ringback tone for the caller while the callee is in the 'on' part of its ring cadence."""
    return _RB(on, amp)
class _RB:
    def __init__(self, on, amp): self.on = on; self.t = Tones((440, 480), amp)
    def __call__(self): return self.t() if self.on else 0
