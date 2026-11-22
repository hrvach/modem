#!/usr/bin/env python3
"""lined.py -- the telephone exchange between the FPGA modem and a SIP trunk. Talks to the baresip module `modemline` (datagram sockets) and to baresip's ctrl_tcp (netstrings).

  outgoing: the modem dials (DTMF seen by the module as "digit N" events); when no digit has come for --dwell seconds the number is dialled over SIP; ringback is played
            to the modem until the far end answers, then the audio is bridged.
  incoming: a SIP call rings the modem (RING on the DTE, cadence 2 s on / 4 s off); when the modem answers (it starts transmitting: "tx 1") the SIP call is accepted.
  hangup:   SIP BYE when the modem has been silent for a while during a call; the modem sees the line drop by itself when the far end hangs up.

Usage: lined.py --domain sip.example.com [--prefix 00] [--dwell 2.0] [--ctrl 127.0.0.1:4444] [--dialtone]
"""
import argparse, json, os, select, socket, subprocess, sys, time

CMD = "/tmp/modemline.cmd"
EV = "/tmp/modemline.ev"
DSPTRACE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dsptrace.py")


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


class Ctrl:
    """baresip ctrl_tcp: netstring framed JSON."""
    def __init__(self, hostport):
        h, p = hostport.rsplit(":", 1)
        self.s = socket.create_connection((h, int(p)))
        self.buf = b""

    def send(self, command, params=None):
        d = {"command": command, "token": command}
        if params is not None:
            d["params"] = params
        b = json.dumps(d).encode()
        self.s.sendall(b"%d:%s," % (len(b), b))

    def read(self):
        data = self.s.recv(65536)
        if not data:
            raise ConnectionError("baresip closed the control connection")
        self.buf += data
        out = []
        while True:
            i = self.buf.find(b":")
            if i < 0:
                break
            n = int(self.buf[:i])
            if len(self.buf) < i + 1 + n + 1:
                break
            out.append(json.loads(self.buf[i + 1:i + 1 + n]))
            self.buf = self.buf[i + 2 + n:]
        return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--domain", required=True, help="SIP domain / trunk host the number is dialled at")
    ap.add_argument("--prefix", default="", help="digits put in front of the dialled number")
    ap.add_argument("--dwell", type=float, default=2.0, help="seconds without a digit before the number is dialled")
    ap.add_argument("--quiet", type=float, default=4.0, help="seconds of modem silence during a call before hanging up")
    ap.add_argument("--ctrl", default="127.0.0.1:4444")
    ap.add_argument("--dialtone", action="store_true", help="play a dial tone to the modem while it is idle")
    a = ap.parse_args()

    ev = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    try:
        os.unlink(EV)
    except FileNotFoundError:
        pass
    ev.bind(EV)
    cmd = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)

    def line(msg):
        try:
            cmd.sendto(msg.encode(), CMD)
        except OSError as e:
            log("modemline socket:", e)

    ctrl = Ctrl(a.ctrl)
    state = "idle"           # idle, dialling, calling, connected, ringing
    digits = ""
    t_digit = 0.0
    t_tx_off = None
    t_est = 0.0
    ring_t0 = 0.0
    ring_on = False
    log("lined up; waiting for the modem")
    if a.dialtone:
        line("tone dial")

    def to_idle(why=""):
        nonlocal state, digits, ring_on, t_tx_off
        state, digits, ring_on, t_tx_off = "idle", "", False, None
        line("ring 0"); line("connected 0"); line("tone dial" if a.dialtone else "tone none")
        log("idle", why)

    while True:
        timeout = 0.2
        r, _, _ = select.select([ev, ctrl.s], [], [], timeout)
        now = time.time()
        if ev in r:
            m = ev.recv(512).decode(errors="replace").split()
            if m and m[0] == "digit" and state in ("idle", "dialling"):
                digits += m[1]
                t_digit = now
                if state == "idle":
                    line("tone none")
                state = "dialling"
                log("digit", m[1], "->", digits)
            elif m and m[0] == "tx":
                if m[1] == "1" and state == "ringing":
                    log("modem answered")
                    line("ring 0")
                    ctrl.send("accept")
                    state = "connected"
                    line("connected 1")
                if m[1] == "1":
                    t_tx_off = None
                elif state == "connected":
                    t_tx_off = now
            elif m and m[0] == "status":
                log(" ".join(m))
        if ctrl.s in r:
            try:
                msgs = ctrl.read()
            except ConnectionError as e:
                log(e); sys.exit(1)
            for j in msgs:
                if not j.get("event"):
                    if j.get("ok") is False:
                        log("baresip:", j)
                    continue
                typ = j.get("type", "")
                log("sip", typ, j.get("param", ""))
                if typ == "CALL_INCOMING" and state == "idle":
                    state = "ringing"; ring_t0 = now; ring_on = True
                    line("tone none"); line("ring 1")
                elif typ == "CALL_ESTABLISHED":
                    t_est = now
                    if state == "calling":
                        state = "connected"; line("tone none"); line("connected 1"); t_tx_off = None
                elif typ == "CALL_CLOSED":
                    if state in ("calling", "connected") and now - t_est > 4.0 and os.path.exists(DSPTRACE):
                        # freeze the DSP instruction history (dsptrace.py arm) at the end of the call, so the ring still holds the call
                        subprocess.run(["nice", "python3", DSPTRACE, "freeze"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        log("dsp trace frozen")
                    to_idle("call closed")
        # timers
        if state == "dialling" and now - t_digit > a.dwell:
            d = digits.replace("*", "").replace("#", "")
            for ip in ("011", "00"):                 # international access code: the number is E.164 from the country code on
                if d.startswith(ip):
                    d = d[len(ip):]
                    break
            number = a.prefix + d
            log("dialling", number)
            line("tone ringback")
            ctrl.send("dial", "sip:%s@%s" % (number, a.domain))
            state = "calling"; digits = ""
        if state == "ringing":
            on = ((now - ring_t0) % 6.0) < 2.0
            if on != ring_on:
                ring_on = on; line("ring 1" if on else "ring 0")
        if state == "connected" and t_tx_off is not None and now - t_tx_off > a.quiet:
            log("modem silent, hanging up")
            ctrl.send("hangup")
            to_idle("modem hung up")


if __name__ == "__main__":
    main()
