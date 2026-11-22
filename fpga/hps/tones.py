"""tones.py -- Goertzel DTMF detector and the central-office tone generators (dial tone, ringback), as in ../courier/src/glue/link.c."""
import math

DTMF_LOW = (697, 770, 852, 941)
DTMF_HIGH = (1209, 1336, 1477, 1633)
DTMF_MAP = {(0, 0): "1", (0, 1): "2", (0, 2): "3", (0, 3): "A", (1, 0): "4", (1, 1): "5", (1, 2): "6", (1, 3): "B",
            (2, 0): "7", (2, 1): "8", (2, 2): "9", (2, 3): "C", (3, 0): "*", (3, 1): "0", (3, 2): "#", (3, 3): "D"}


class Goertzel:
    def __init__(self, f, fs):
        self.c = 2 * math.cos(2 * math.pi * f / fs)

    def power(self, xs):
        s1 = s2 = 0.0
        for x in xs:
            s0 = x + self.c * s1 - s2
            s2, s1 = s1, s0
        return s1 * s1 + s2 * s2 - self.c * s1 * s2


def dtmf_digit(xs, fs):
    """The DTMF digit in one block of samples (about 20 ms), or None."""
    if len(xs) < 40:
        return None
    tot = sum(x * x for x in xs) + 1.0
    lo = [Goertzel(f, fs).power(xs) for f in DTMF_LOW]
    hi = [Goertzel(f, fs).power(xs) for f in DTMF_HIGH]
    il = max(range(4), key=lambda i: lo[i])
    ih = max(range(4), key=lambda i: hi[i])
    n = len(xs)
    # each present tone carries about (n/2 * amplitude^2/2)^2 / ... : compare with the block energy and with the runner-up
    if lo[il] < 0.08 * tot * n or hi[ih] < 0.08 * tot * n:
        return None
    if sorted(lo)[-2] * 8 > lo[il] or sorted(hi)[-2] * 8 > hi[ih]:
        return None
    return DTMF_MAP[(il, ih)]


class ToneGen:
    """Sum of sine tones, optionally cadenced (on_s seconds on, off_s off); sample rate fs may change between calls."""
    def __init__(self, freqs, amp=3000, on_s=None, off_s=None):
        self.freqs, self.amp, self.on_s, self.off_s = freqs, amp, on_s, off_s
        self.t = 0.0

    def next_block(self, n, fs):
        out = []
        for _ in range(n):
            on = True
            if self.on_s is not None:
                on = (self.t % (self.on_s + self.off_s)) < self.on_s
            v = sum(math.sin(2 * math.pi * f * self.t) for f in self.freqs) * self.amp / max(1, len(self.freqs)) if on else 0
            out.append(int(v))
            self.t += 1.0 / fs
        return out


def dial_tone():
    return ToneGen((350, 440))


def ringback():
    return ToneGen((440, 480), on_s=2.0, off_s=4.0)
