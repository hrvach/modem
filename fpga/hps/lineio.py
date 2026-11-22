#!/usr/bin/env python3
"""lineio.py -- the modem's phone line over stdin/stdout, for a peer that runs elsewhere (use through ssh; no SIP, no baresip).
   board -> host: '<II' n, fs  + n int16   (the modem's DAC samples, fs = the codec rate now)
   host -> board: '<I' n       + n int16   (ADC samples for the modem, at the codec rate fs the host was told)
The line is reported connected only after the host says so (control frames). The RX ring is kept about 150 ms deep (LINEIO_FILL_S); when the codec rate changes the queued samples are dropped
(they were made for the old rate). Run on the MiSTer: python3 -u lineio.py"""
import os, select, struct, sys, time
from linering import Line, RING_SAMPLES

TARGET_S = float(os.environ.get("LINEIO_FILL_S", "0.15"))            # RX ring depth: the host side runs over ssh, so be generous
ln = Line()
ln.set_connected(os.environ.get("LINEIO_CONNECTED", "0") == "1")                                           # the host switches it on when the far end answers (frame n = 0xFFFFFFF1; 0xFFFFFFF0 = off)
out = sys.stdout.buffer
buf = b""
pending = []
fs_prev = 0.0
t0 = time.time()
while True:
    tx = ln.tx_read()
    fs = ln.rate_hz() or 7200.0
    if tx:
        out.write(struct.pack("<II", len(tx), int(round(fs))) + struct.pack("<%dh" % len(tx), *tx)); out.flush()
    r, _, _ = select.select([0], [], [], 0.003)
    if r:
        d = os.read(0, 65536)
        if not d: break
        buf += d
        while len(buf) >= 4:
            n = struct.unpack_from("<I", buf)[0]
            if n >= 0xFFFFFFF0:                                         # control frame
                ln.set_connected(n == 0xFFFFFFF1); buf = buf[4:]; continue
            if len(buf) < 4 + 2 * n: break
            pending.extend(struct.unpack_from("<%dh" % n, buf, 4)); buf = buf[4 + 2 * n:]
    if fs_prev and abs(fs - fs_prev) > 50:                      # codec rate change: drop what was made for the old rate
        pending.clear(); ln.rx_count = ln.status()["rx_taken"]; ln._put_ctrl()
    fs_prev = fs
    taken = ln.status()["rx_taken"]
    fill = (ln.rx_count - taken) & 0xFFFFFFFF
    want = int(fs * TARGET_S) - fill
    if want > 0 and pending:
        n = ln.rx_write(pending[:want]); del pending[:n]
