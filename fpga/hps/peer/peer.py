#!/usr/bin/env python3
"""peer.py -- run D-Modem (slmodemd + d-modem, answer patch) on the builder as a modem peer, controlled through a FIFO.
   python3 peer.py start            start slmodemd -e ./d-modem, hold its pty open, log to modem.log (stays in the foreground)
   echo 'ATA' > cmd.fifo            type a line to the modem (from anywhere, e.g. ssh)
Run from the directory that has D-Modem/ (build there with the answer patch). Needs no privileges: the /dev/ttySL0 link is not made, the pty path is used."""
import os, pty, re, select, subprocess, sys, termios, time

HERE = os.path.dirname(os.path.abspath(__file__))
DM = os.path.join(HERE, "D-Modem")
FIFO = os.path.join(HERE, "cmd.fifo")
WRAP = os.path.join(HERE, "wrap.sh")
LOG = open(os.path.join(HERE, "modem.log"), "a", buffering=1)

def log(*a):
    LOG.write(time.strftime("%H:%M:%S ") + " ".join(str(x) for x in a) + "\n")

def main():
    if not os.path.exists(FIFO):
        os.mkfifo(FIFO)
    env = dict(os.environ)
    p = subprocess.Popen([os.path.join(DM, "slmodemd", "slmodemd"), "-d9", "-e", WRAP if os.path.exists(WRAP) else os.path.join(DM, "d-modem")], cwd=DM, env=env,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    tty = None
    t0 = time.time()
    buf = b""
    while tty is None and time.time() - t0 < 10:
        r, _, _ = select.select([p.stdout], [], [], 0.5)
        if r:
            line = os.read(p.stdout.fileno(), 4096)
            buf += line
            log("slmodemd:", line.decode(errors="replace").strip())
            m = re.search(rb"TTY is `([^']+)'", buf)
            if m:
                tty = m.group(1).decode()
    if not tty:
        log("no tty found"); p.kill(); sys.exit(1)
    log("modem tty", tty)
    fd = os.open(tty, os.O_RDWR | os.O_NOCTTY)
    a = termios.tcgetattr(fd)
    a[0] = a[1] = a[3] = 0                       # raw
    a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    a[4] = a[5] = termios.B115200
    termios.tcsetattr(fd, termios.TCSANOW, a)
    cf = os.open(FIFO, os.O_RDONLY | os.O_NONBLOCK)
    pending = b""
    # auto-answer: slmodemd's answer wait (S7) is long, and whenever a call ends (NO CARRIER) the modem is armed again 9 s later (the SIP listener needs ~9 s after ATA,
    # an invite earlier than that is refused), so a caller can dial at any time. `peer.py start noauto` leaves it manual.
    auto = "noauto" not in sys.argv
    queue = [(time.time() + 3.0, b"ATS7=120"), (time.time() + 5.0, b"ATA")] if auto else []
    while p.poll() is None:
        now = time.time()
        while queue and queue[0][0] <= now:
            _, cmd = queue.pop(0)
            log("auto:", cmd.decode())
            os.write(fd, cmd + b"\r")
        r, _, _ = select.select([fd, cf, p.stdout], [], [], 1.0)
        if fd in r:
            try:
                d = os.read(fd, 4096)
            except OSError:
                d = b""
            if d:
                txt = d.decode(errors="replace")
                log("modem>", txt.replace("\r", " ").replace("\n", " ").strip())
                if auto and "NO CARRIER" in txt and not queue:
                    queue = [(time.time() + 9.0, b"ATS7=120"), (time.time() + 10.0, b"ATA")]
        if p.stdout in r:
            d = os.read(p.stdout.fileno(), 4096)
            if d:
                log("slmodemd:", d.decode(errors="replace").strip())
        if cf in r:
            try:
                d = os.read(cf, 4096)
            except BlockingIOError:
                d = b""
            if not d:                    # the writer closed the FIFO: open it again, or select() would return at once for ever
                os.close(cf)
                cf = os.open(FIFO, os.O_RDONLY | os.O_NONBLOCK)
                time.sleep(0.05)
            if d:
                pending += d
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    log("send:", line.decode(errors="replace"))
                    os.write(fd, line + b"\r")
    log("slmodemd exited", p.returncode)

if __name__ == "__main__":
    main()
