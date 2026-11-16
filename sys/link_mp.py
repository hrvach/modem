"""Two emulated modems on one simulated phone line, one process per modem (A = callee, B = caller).
Same slice-and-exchange protocol as link.Link (run A and B for one slice, then deliver each side's new audio to the other's input
for the next slice), so results are identical to the single-process Link while the two emulations run in parallel.
Limits: tools that reach into L.a.dsp / L.b.dsp (data memory, PC hits, breakpoints) need the single-process Link; here m.<attr> reads go
through an RPC (read-only, e.g. L.a.rate_log) and m.eval("expr") evaluates an expression on the worker's Machine (name `m`)."""
import sys, os, multiprocessing as mp
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
FS = 7200


def _worker(conn):
    from machine import Machine
    from line import dial_tone, Tones
    m = Machine(nvram_mode=None); m.logging = False
    gens = {}; seen = 0
    while True:
        msg = conn.recv(); op = msg['op']
        if op == 'run':
            for s in msg.get('send', ()): m.send(s)
            if msg.get('ring_on') is not None: m.ring_on = msg['ring_on']
            if msg['rx']: m.rxbuf.extend(msg['rx'])
            g = msg.get('gen')
            if g is None: m.rx_gen = None
            elif g[0] == 'dial':
                gens.setdefault('dial', dial_tone(g[1])); m.rx_gen = gens['dial']
            elif g[0] == 'rb':
                rb = gens.setdefault('rb', Tones((440, 480), 2500)); on = g[1]
                m.rx_gen = (lambda rb=rb, on=on: rb() if on else 0)
            m.run(msg['slice'])
            new = m.tx_all[seen:]; seen = len(m.tx_all)
            conn.send({'tx': new, 'dte': m.dte_text(), 'rate': m.rate, 'cyc': m.cpu.cycles})
        elif op == 'eval':
            try: conn.send(eval(msg['expr'], {'m': m}))
            except Exception as e: conn.send(('ERR', repr(e)))
        elif op == 'quit':
            conn.send(None); return


class _Biquad:
    """RBJ biquad, direct form I; coefficients are recomputed when the sample rate changes."""
    def __init__(self, kind, f0, q=0.7071): self.kind = kind; self.f0 = f0; self.q = q; self.fs = 0; self.x1 = self.x2 = self.y1 = self.y2 = 0.0
    def _design(self, fs):
        import math
        self.fs = fs; w = 2 * math.pi * min(self.f0, 0.45 * fs) / fs; c = math.cos(w); al = math.sin(w) / (2 * self.q)
        if self.kind == 'lp': b0 = (1 - c) / 2; b1 = 1 - c; b2 = (1 - c) / 2
        else: b0 = (1 + c) / 2; b1 = -(1 + c); b2 = (1 + c) / 2
        a0 = 1 + al; self.b = (b0 / a0, b1 / a0, b2 / a0); self.a = (-2 * c / a0, (1 - al) / a0)
    def run(self, xs, fs):
        if fs != self.fs: self._design(fs)
        b0, b1, b2 = self.b; a1, a2 = self.a; x1, x2, y1, y2 = self.x1, self.x2, self.y1, self.y2; out = []
        for x in xs:
            y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2; x2 = x1; x1 = x; y2 = y1; y1 = y; out.append(y)
        self.x1, self.x2, self.y1, self.y2 = x1, x2, y1, y2; return out


class _Proxy:
    """Stands in for L.a / L.b: send() and ring_on are queued for the next slice, everything else is read through the worker."""
    def __init__(self, link, key): object.__setattr__(self, '_l', link); object.__setattr__(self, '_k', key)
    def send(self, text): self._l._q[self._k]['send'].append(text if isinstance(text, str) else text.decode('latin1'))
    def __setattr__(self, name, value):
        if name == 'ring_on': self._l._q[self._k]['ring_on'] = bool(value)
        else: raise AttributeError('LinkMP proxy: cannot set %s' % name)
    def eval(self, expr): return self._l._rpc(self._k, expr)
    def __getattr__(self, name):
        if name == 'rate': return self._l.rate[self._k]
        return self._l._rpc(self._k, 'm.' + name)
    @property
    def cpu(self):
        l = self._l; k = self._k
        class _C:
            cycles = l.cyc[k]
        return _C


class LinkMP:
    def __init__(self, slice_=100_000):
        ctx = mp.get_context('fork')
        self._c = {}; self._p = {}
        for k in ('a', 'b'):
            pc, cc = ctx.Pipe(); p = ctx.Process(target=_worker, args=(cc,), daemon=True); p.start(); self._c[k] = pc; self._p[k] = p
        self._q = {k: {'send': [], 'ring_on': None, 'rx': []} for k in 'ab'}
        self.a = _Proxy(self, 'a'); self.b = _Proxy(self, 'b'); self.rate = {'a': 7200, 'b': 7200}; self.cyc = {'a': 0, 'b': 0}
        self.slice = slice_; self.audio = {'a': [], 'b': []}; self.gain = 1.0; self.echo = 0.0; self.gate = False
        self.state = 'idle'; self.t_state = 0; self.events = []; self.txt = {'a': b'', 'b': b''}; self.answer_on_ring = True
        self.ring_seen_at = 0; self.ring_t0 = 0; self._pre = {'a': b'', 'b': b''}
        self._gen_b = None; self._rb_on = False; self._st_ab = [0.0, 0]; self._st_ba = [0.0, 0]; self._inj = [float(x) for x in os.environ['INJECT_A'].split(',')] if os.environ.get('INJECT_A') else None; self._inj_n = 0; self.chunks = {'a': [], 'b': []}; self.delay_ms = float(os.environ.get('DELAY_MS', '0')); self.delay_samples = int(os.environ.get('DELAY_SAMPLES', '0'))
        lp = float(os.environ.get('LINE_LP', '0')); hp = float(os.environ.get('LINE_HP', '0'))     # line band limits in Hz (0 = none); two 2nd-order sections low-pass, one high-pass, per direction
        self._flt = {k: ([_Biquad('lp', lp), _Biquad('lp', lp)] if lp else []) + ([_Biquad('hp', hp)] if hp else []) for k in 'ab'}; self._dq = {'a': [], 'b': []}

    # ---- plumbing
    def _rpc(self, k, expr):
        self._c[k].send({'op': 'eval', 'expr': expr}); r = self._c[k].recv()
        if isinstance(r, tuple) and r and r[0] == 'ERR': raise AttributeError(r[1])
        return r
    def close(self):
        for k in 'ab':
            try: self._c[k].send({'op': 'quit'}); self._c[k].recv()
            except Exception: pass
    def samples(self):
        if not self.audio['a'] and not self.audio['b']: self._base = self.cyc['b']
        from machine import CPU_HZ
        return int((self.cyc['b'] - getattr(self, '_base', 0)) * FS // CPU_HZ)
    def text(self):
        out = self._pre['a'], self._pre['b']; self._pre = {'a': b'', 'b': b''}; return out

    # ---- central office (same logic as link.Link.co_step; machine access goes through the proxies / queued commands)
    def set_state(self, st):
        self.state = st; self.t_state = self.samples(); self.events.append((self.samples() / FS, st))
    def start_call(self, number="1"):
        self.b.send("ATDT%s\r" % number); self._gen_b = ('dial', 3000); self.set_state('dialtone')
    def co_step(self, ta, tb):
        t = (self.samples() - self.t_state) / FS
        quiet = (not tb) or max(map(abs, tb)) < 300
        if self.state == 'dialtone' and tb and max(map(abs, tb)) > 15000:
            self.set_state('digit')
        elif self.state == 'digit' and quiet and t > 0.05:
            self._gen_b = None; self.set_state('dialing')
        elif self.state == 'dialing' and t > 3.0:
            self.ring_t0 = self.samples(); self._rb_on = False; self._gen_b = ('rb', False)
            self.set_state('ringing')
        elif self.state == 'ringing':
            tr = (self.samples() - self.ring_t0) / FS
            on = (tr % 6.0) < 2.0
            self.a.ring_on = on; self._rb_on = on; self._gen_b = ('rb', on)
            if self.answer_on_ring and b'RING' in self.txt['a'] and tr > 0.5 and (self.samples() - self.ring_seen_at) / FS > 0.4:
                self.a.send("ATA\r"); self.a.ring_on = False; self._gen_b = None; self.set_state('answering')
        elif self.state == 'answering':
            self.set_state('connected')

    def write_wav(self, path, rate=22050, first_chunk=0):
        """Stereo wav (left = caller B, right = answerer A) at a fixed sample rate: every slice is the same span of time, each side's samples of that slice
        (produced at that modem's codec rate at the time) are linearly interpolated onto the output grid."""
        import wave, struct
        from machine import CPU_HZ
        per = rate * self.slice / CPU_HZ; out = {}
        for k in 'ab':
            o = []
            for r, xs in self.chunks[k][first_chunk:]:
                n = len(xs); t = 0.0
                if n == 0: o += [0] * int(round(per)); continue
                while t < per:
                    i = min(int(t * n / per), n - 1); f = t * n / per - i
                    x0 = xs[i]; x1 = xs[i + 1] if i + 1 < n else x0
                    o.append(int(x0 + (x1 - x0) * f)); t += 1.0
            out[k] = o
        m = min(len(out['a']), len(out['b']))
        with wave.open(path, 'wb') as w:
            w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
            w.writeframes(b''.join(struct.pack('<hh', max(-32768, min(32767, out['b'][i])), max(-32768, min(32767, out['a'][i]))) for i in range(m)))
    def _rs(self, st, xs, r_in, r_out):
        step = r_in / r_out; out = []
        for x in xs:
            while st[0] < 1.0:
                out.append(int(st[1] + (x - st[1]) * st[0])); st[0] += step
            st[0] -= 1.0; st[1] = x
        return out

    def run(self, cycles):
        done = 0
        while done < cycles:
            # same time policy as Link.run: one shared absolute clock; a worker that overshot its slice gets a shorter budget (see sys/FULL_SYSTEM.md, "Time policy")
            if not hasattr(self, '_gt'): self._gt = 0; self._off = {'a': 0, 'b': 0}
            self._gt += self.slice
            for k in 'ab':                                     # both workers run their slice in parallel
                q = self._q[k]
                self._c[k].send({'op': 'run', 'slice': max(0, self._gt - (self.cyc.get(k, 0) - self._off[k])), 'rx': q['rx'], 'send': q['send'], 'ring_on': q['ring_on'], 'gen': self._gen_b if k == 'b' else None})
                self._q[k] = {'send': [], 'ring_on': None, 'rx': []}
            ra = self._c['a'].recv(); rb = self._c['b'].recv(); done += self.slice
            self.rate = {'a': ra['rate'], 'b': rb['rate']}; self.cyc = {'a': ra['cyc'], 'b': rb['cyc']}
            ta, tb = ra['tx'], rb['tx']; self.audio['a'] += ta; self.audio['b'] += tb
            self.chunks['a'].append((ra['rate'], ta)); self.chunks['b'].append((rb['rate'], tb))
            for k, x in (('a', ra['dte']), ('b', rb['dte'])):
                self._pre[k] += x
                if x:
                    self.txt[k] += x
                    if k == 'a' and b'RING' in x: self.ring_seen_at = self.samples()
            self.co_step(ta, tb)
            if self.state == 'connected':
                n = min(len(ta), len(tb)); g_ab = self.gain
                if self.rate['a'] == self.rate['b']:
                    self._q['b']['rx'] = [int(ta[k] * g_ab + self.echo * tb[k]) & 0xFFFF for k in range(n)] + [int(ta[k] * g_ab) & 0xFFFF for k in range(n, len(ta))]
                    self._q['a']['rx'] = [int(tb[k] * self.gain + self.echo * ta[k]) & 0xFFFF for k in range(n)] + [int(tb[k] * self.gain) & 0xFFFF for k in range(n, len(tb))]
                else:
                    self._q['b']['rx'] = [int(v * g_ab) & 0xFFFF for v in self._rs(self._st_ab, ta, self.rate['a'], self.rate['b'])]
                    self._q['a']['rx'] = [int(v * self.gain) & 0xFFFF for v in self._rs(self._st_ba, tb, self.rate['b'], self.rate['a'])]
                if self._inj:                                              # experiment: replace A's received signal by an ideal S sequence (INJECT_A=t0,t1,amp,fc,sps)
                    t0, t1, amp, fc, sps = self._inj; tc = (self.cyc['b'] - getattr(self, '_base', 0)) / float(__import__('machine').CPU_HZ)
                    if t0 <= tc < t1:
                        import math
                        rx = self._q['a']['rx']; out = []
                        for _ in rx:
                            n = self._inj_n; self._inj_n += 1
                            out.append(int(amp * (1 if (n // int(sps)) % 2 == 0 else -1) * math.cos(2 * math.pi * fc * n / self.rate['a'])) & 0xFFFF)
                        self._q['a']['rx'] = out
                for k in 'ab':                                             # line band-limiting on what each modem receives (at its own codec rate)
                    if self._flt[k] and self._q[k]['rx']:
                        v = [float(x if x < 32768 else x - 65536) for x in self._q[k]['rx']]
                        for f in self._flt[k]: v = f.run(v, self.rate[k])
                        self._q[k]['rx'] = [int(max(-32768, min(32767, y))) & 0xFFFF for y in v]
                if self.delay_ms > 0 or self.delay_samples > 0:             # one-way propagation delay (in receiver samples; fixed at the length chosen on first use)
                    for k in 'ab':
                        d = self.delay_samples or int(self.delay_ms * self.rate[k] / 1000.0); q = self._q[k]['rx']
                        buf = self._dq[k] if self._dq[k] else [0] * d
                        buf = buf + q; self._q[k]['rx'] = buf[:len(q)]; self._dq[k] = buf[len(q):]
