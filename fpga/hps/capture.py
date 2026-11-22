#!/usr/bin/env python3
"""capture.py [seconds] [prefix] -- record both directions of the modem's line for offline analysis:
   <prefix>_tx.raw  what the modem sends (its DAC samples)           <prefix>_rx.raw  what the line gives the modem (the RX ring content)
   <prefix>_rate.txt  codec rate (Hz) over time.  raw = int16 little endian; the codec rate changes during a handshake, see the rate log."""
import sys, time, struct, signal
from linering import Line, A_RX, WORD, RING_SAMPLES, A_CTRL
secs = float(sys.argv[1]) if len(sys.argv) > 1 else 30
pre = sys.argv[2] if len(sys.argv) > 2 else "/tmp/cap"
ln = Line()
tx = bytearray(); rx = bytearray(); rates = []
rx_last = struct.unpack_from("<I", ln.m, A_CTRL * WORD)[0]
t0 = time.time(); last_rate = None; t_save = t0; stop = []
signal.signal(signal.SIGTERM, lambda *a: stop.append(1)); signal.signal(signal.SIGINT, lambda *a: stop.append(1))   # kill it any time: the files are written on the way out
def save():
    open(pre + "_tx.raw", "wb").write(tx); open(pre + "_rx.raw", "wb").write(rx)
    open(pre + "_rate.txt", "w").write("\n".join(rates) + "\n")
while time.time() - t0 < secs and not stop:
    s = ln.tx_read()
    if s:
        tx += struct.pack("<%dh" % len(s), *s)
    cnt = struct.unpack_from("<I", ln.m, A_CTRL * WORD)[0]
    n = (cnt - rx_last) & 0xFFFFFFFF
    if n and n < RING_SAMPLES // 2:
        for i in range(n):
            rx += ln.m[A_RX * WORD + ((rx_last + i) % RING_SAMPLES) * 2: A_RX * WORD + ((rx_last + i) % RING_SAMPLES) * 2 + 2]
    rx_last = cnt
    r = round(ln.rate_hz())
    if r != last_rate:
        rates.append("%.2f s  tx_sample %d  rx_sample %d  rate %d Hz" % (time.time() - t0, len(tx) // 2, len(rx) // 2, r)); last_rate = r
    if time.time() - t_save > 5:
        save(); t_save = time.time()          # the files grow while it runs
    time.sleep(0.01)
save()
print("tx %d samples, rx %d samples, rate changes %d -> %s_*" % (len(tx) // 2, len(rx) // 2, len(rates), pre))
