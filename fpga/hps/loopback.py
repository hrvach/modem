#!/usr/bin/env python3
"""loopback.py -- board test with no SIP: whatever the modem sends to the line comes back into its receiver (after a delay).
Also reports the DTMF digits and the level it sees. Run on the MiSTer: python3 loopback.py [delay_ms]"""
import sys, time
from linering import Line
from tones import dtmf_digit

delay_ms = float(sys.argv[1]) if len(sys.argv) > 1 else 40
ln = Line()
print("alive", ln.alive(), ln.status())
ln.set_connected(True)
buf = []
pending = []                 # samples waiting out the delay
t_report = time.time()
peak = 0
digs = []
lastd = None
while True:
    s = ln.tx_read()
    if s:
        pending.extend(s)
        peak = max(peak, max(abs(x) for x in s))
        buf.extend(s)
        fs = ln.rate_hz() or 7200.0
        n20 = int(fs * 0.02)
        while len(buf) >= n20:
            d = dtmf_digit(buf[:n20], fs)
            del buf[:n20]
            if d and d != lastd:
                print('DIGIT', d, flush=True)
            lastd = d
    rate = ln.rate_hz() or 7200.0
    want = int(delay_ms * rate / 1000)
    if len(pending) > want:
        n = ln.rx_write(pending[: len(pending) - want])
        del pending[:n]
    if time.time() - t_report > 1.0:
        st = ln.status()
        print("rate %.0f Hz  tx_peak %d  underruns %d  tx_lost %d  rx_taken %d" % (ln.rate_hz(), peak, st["underruns"], st["tx_lost"], st["rx_taken"]))
        t_report = time.time(); peak = 0
    time.sleep(0.005)
