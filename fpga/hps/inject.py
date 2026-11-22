#!/usr/bin/env python3
"""inject.py KIND [seconds] [level] -- feed a synthetic signal into the modem's line input (RX ring) and watch the codec rate: no SIP, no baresip (stop it first).
KIND: sine2100 | ansam | ring | cng1300 | noise | silence | file:<raw int16 7200 Hz>.  level = rms (default 2300).
Prints the codec rate, DSP program counter is not visible here: use the heartbeat / trap rings afterwards."""
import math, random, os, subprocess, sys, time
from linering import Line

kind = sys.argv[1]
secs = float(sys.argv[2]) if len(sys.argv) > 2 else 15
level = float(sys.argv[3]) if len(sys.argv) > 3 else 2300
ln = Line()
t = 0.0
rng = random.Random(1)
raw = None
if kind.startswith("file:"):
    import struct
    d = open(kind[5:], "rb").read(); raw = struct.unpack("<%dh" % (len(d) // 2), d)
    pos = 0

def gen(n, fs):
    global t, pos
    out = []
    for _ in range(n):
        if kind == "sine2100":
            v = math.sin(2 * math.pi * 2100 * t) * level * 1.414
        elif kind == "ansam":
            rev = 0 if int(t / 0.45) % 2 == 0 else math.pi
            v = level * 1.414 * (1 + 0.2 * math.sin(2 * math.pi * 15 * t)) / 1.2 * math.sin(2 * math.pi * 2100 * t + rev)
        elif kind == "ring":
            v = (math.sin(2 * math.pi * 440 * t) + math.sin(2 * math.pi * 480 * t)) * level * 0.7 if (t % 6.0) < 2.0 else 0
        elif kind == "cng1300":
            v = math.sin(2 * math.pi * 1300 * t) * level * 1.414 if (t % 3.0) < 0.5 else 0
        elif kind == "noise":
            v = rng.gauss(0, level)
        elif raw is not None:
            v = raw[pos % len(raw)] * (level / 2300.0); pos += 1
        else:
            v = 0
        out.append(int(max(-32768, min(32767, v))))
        t += 1.0 / fs
    return out

t0 = time.time(); last = None; lines = []
while time.time() - t0 < secs:
    fs = ln.rate_hz() or 7200.0
    free = ln.rx_free()
    ahead = RING = 16384 - free
    want = int(fs * 0.1) - (16384 - free - 0) if False else 0
    # keep about 100 ms queued: queued = rx_count - taken
    st = ln.status()
    queued = (ln.rx_count - st["rx_taken"]) & 0xFFFFFFFF
    if queued < int(fs * 0.1):
        ln.rx_write(gen(int(fs * 0.1) - queued, fs))
    r = round(fs)
    if r != 7200 and os.environ.get("CATCH") and not os.path.exists("/tmp/caught"):
        # the codec left its normal rate: start the heartbeat dump (the trap rings are frozen by now) before anything else happens
        open("/tmp/caught", "w").write("1")
        cap = subprocess.Popen("timeout 6 cat /dev/ttyS1 > %s" % os.environ["CATCH"], shell=True)
        time.sleep(0.15)
        with open("/dev/ttyS1", "wb", buffering=0) as tty:
            tty.write(b"\x01\x01\x01D")
        time.sleep(3.3)
        with open("/dev/ttyS1", "wb", buffering=0) as tty:
            tty.write(b"\x01\x01\x01D")
        cap.wait()
        print("CAUGHT at %.2f s: rate %d" % (time.time() - t0, r), flush=True)
        break
    if r != last:
        lines.append("%6.2f s  codec rate %d Hz  (cps %d)" % (time.time() - t0, r, st["rate_cps"])); print(lines[-1], flush=True); last = r
    time.sleep(0.01)
print("done; final rate %d Hz, rx_taken %d" % (round(ln.rate_hz()), ln.status()["rx_taken"]))
