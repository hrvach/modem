// One modem in the browser: its own wasm instance, paced to its own CPU
// clock, never faster than realtime and never more than lookaheadS past the
// other modem's audio. Audio goes out as it is produced.
// The page starts this worker as worker.js?v=<build>; the same version goes on the modem files, so a browser
// that cached an older build fetches the new one.
const VER = self.location.search;
importScripts('modem.js' + VER);

let M = null, role = '', cpuHz = 0, rate = 0;
const rxQueue = [], cmdQueue = [];
// White noise added to what this modem hears, set by the page's Line noise slider as a fraction of a nominal
// received signal (NOISE_REF, the rms a modem delivers across the line at gain 0.5). 0.06 is about 24 dB SNR.
let noiseRel = 0;
const NOISE_REF = 2400;
let gaussSpare = null;
function gauss() {   // Box-Muller
  if (gaussSpare !== null) { const g = gaussSpare; gaussSpare = null; return g; }
  let u = 0; while (u === 0) u = Math.random();
  const r = Math.sqrt(-2 * Math.log(u)), a = 2 * Math.PI * Math.random();
  gaussSpare = r * Math.sin(a);
  return r * Math.cos(a);
}
const addNoise = (x) => (noiseRel > 0 ? x + Math.round(gauss() * noiseRel * NOISE_REF) : x);
// Line impairments, all on what this modem hears (set by the page's Line card):
//  attDb: loss in dB; freqHz: frequency shift; jitDeg/jitHz: phase jitter; impPerSec: random clicks; dropLeft: samples left muted.
// Shift and jitter rotate the analytic signal (a 33-tap Hilbert transformer), so they need no firmware help.
const line = { attDb: 0, freqHz: 0, jitDeg: 0, jitHz: 20, impPerSec: 0, echoPct: 0, echoMs: 2 };
const ECHO_N = 1024, echoBuf = new Float64Array(ECHO_N); let echoPos = 0;   // the line's own past, for the multipath echo
let dropLeft = 0, impLeft = 0, impAmp = 0, lineN = 0;
const HT = 33, HC = (HT - 1) / 2, hilb = new Float64Array(HT), hist = new Float64Array(HT);
for (let k = -HC; k <= HC; k++) hilb[k + HC] = (k & 1) ? (2 / (Math.PI * k)) * (0.54 + 0.46 * Math.cos(Math.PI * k / (HC + 1))) : 0;
let histPos = 0;
function setLine(l) { Object.assign(line, l); }
// One received sample (already scaled by the line gain) through the impairments, plus noise; returns an integer.
function shape(v) {
  lineN++;
  const g = line.attDb > 0 ? Math.pow(10, -line.attDb / 20) : 1;
  v *= g;
  { const dly = Math.min(ECHO_N - 1, Math.max(1, Math.round(line.echoMs * rate / 1000)));   // multipath: the signal plus a delayed, weaker copy of it
    echoBuf[echoPos] = v; if (line.echoPct > 0) v += echoBuf[(echoPos - dly + ECHO_N) % ECHO_N] * line.echoPct / 100; echoPos = (echoPos + 1) % ECHO_N; }
  if (line.freqHz !== 0 || line.jitDeg > 0) {
    hist[histPos] = v; histPos = (histPos + 1) % HT;
    let im = 0;
    for (let k = 0; k < HT; k++) im += hilb[k] * hist[(histPos + k) % HT];
    const re = hist[(histPos + HC) % HT];
    const th = 2 * Math.PI * line.freqHz * lineN / rate + line.jitDeg * Math.PI / 180 * Math.sin(2 * Math.PI * line.jitHz * lineN / rate);
    v = re * Math.cos(th) - im * Math.sin(th);
  }
  if (impLeft <= 0 && line.impPerSec > 0 && Math.random() < line.impPerSec / rate) { impLeft = Math.round(rate * 0.002); impAmp = (Math.random() < 0.5 ? -1 : 1) * NOISE_REF * (2 + 4 * Math.random()); }
  if (impLeft > 0) { v += impAmp * Math.exp(-3 * (1 - impLeft / (rate * 0.002))) * (Math.random() * 2 - 1); impLeft--; }
  if (dropLeft > 0) { dropLeft--; v = 0; }
  return addNoise(Math.round(v));
}
let peerSim = 0;
let toneOn = false;
let toPeer = null, fromPeer = null;   // direct channels to the other modem's worker
let gain = 0.5;   // the line gain
const relayConv = { phase: 0, last: 0 };   // the other modem's rate -> this one's, as rs_linear in link.c
let paused = false, pauseAck = false, pausedAt = 0, snapPtrs = null, t0 = 0;   // snapshot support (see 'snap' messages)
let ringStart = -1, ringState = 0, stopNow = false;   // ring cadence: 1 s on, 6 s period (as link.c)

self.onmessage = (e) => {
  const d = e.data;
  if (d.init) {
    gain = d.gain; noiseRel = d.noise || 0; if (d.line) setLine(d.line);
    toPeer = d.toPeer;
    fromPeer = d.fromPeer;
    // The other modem's chunks arrive in order, straight from its worker. Each carries its sim time.
    fromPeer.onmessage = (ev) => { pushRelay(ev.data.tx, ev.data.rate); peerSim = ev.data.sim; };
    start(d);
    return;
  }
  if (d.stop) { stopNow = true; return; }
  if (d.snap === 'pause') { paused = true; pauseAck = false; pausedAt = performance.now(); return; }
  if (d.snap === 'resume') { if (paused) t0 += performance.now() - pausedAt; paused = false; return; }
  if (d.snap === 'take') { takeSnapshot(); return; }
  if (d.dm) { postMessage({ dmvals: M && typeof M._modem_dm === 'function' ? d.dm.map((x) => M.ccall('modem_dm', 'number', ['number'], [x])) : null }); return; }   // DSP data cells, for the link measurements
  if (d.cmd === 'send') cmdQueue.push(d.text);
  if (d.cmd === 'sendbytes') cmdQueue.push(d.bytes);   // raw bytes (a Uint8Array), for the speed test
  if (d.noise !== undefined) noiseRel = d.noise;
  if (d.line) setLine(d.line);
  if (d.scope !== undefined && M) M.ccall('modem_scope_set', null, ['number', 'number', 'number', 'number'], d.scope ? [0x0300, 0x0302, 0x0239, 0x023C] : [-1, -1, -1, -1]);
  if (d.dropMs) dropLeft = Math.round(rate * d.dropMs / 1000);
  if (d.click) { impLeft = Math.round(rate * 0.002); impAmp = NOISE_REF * 6; }
  if (d.ring !== undefined) ringStart = d.ring ? -2 : -1;   // -2: start at the next step
  if (d.tone !== undefined) toneOn = !!d.tone;
};

// Snapshot: the whole wasm memory (every bit of the emulated modem: CPU, DSP, codec, buffers) plus the few things
// the worker itself holds. The worker is paused and idle between wasm calls, so the memory is consistent. Restoring
// it into a fresh instance gives a modem that carries on exactly where this one was.
function takeSnapshot() {
  const mem = M.HEAPU8.slice().buffer;
  postMessage({ snapshot: {
    mem, ptrs: snapPtrs, rate, peerSim, relayConv: { ...relayConv },
    rxQueue: rxQueue.map((a) => a.slice()), sim: simNow,
  } }, [mem]);
}
let simNow = 0;

// The other modem's samples (codec rate fromRate), in order, into this modem's receive
// queue at this modem's rate, with the line gain. Linear interpolation between rates, as
// rs_linear in link.c; equal rates pass straight through.
function pushRelay(xs, fromRate) {
  const vals = [];
  if (fromRate === rate) {
    for (let i = 0; i < xs.length; i++) vals.push(shape(xs[i] * gain) & 0xFFFF);
  } else {
    const step = fromRate / rate;
    for (let i = 0; i < xs.length; i++) {
      const x = xs[i];
      while (relayConv.phase < 1.0) {
        vals.push(shape(Math.trunc(relayConv.last + (x - relayConv.last) * relayConv.phase) * gain) & 0xFFFF);
        relayConv.phase += step;
      }
      relayConv.phase -= 1.0;
      relayConv.last = x;
    }
  }
  if (vals.length) rxQueue.push(Int32Array.from(vals));
}

// Yield without browser timer clamping (setTimeout(0) is clamped to ~4 ms).
const yieldChan = new MessageChannel();
let resumeFn = null;
yieldChan.port1.onmessage = () => { const f = resumeFn; resumeFn = null; if (f) f(); };
const tick = () => new Promise((r) => { resumeFn = r; yieldChan.port2.postMessage(0); });

async function start(d) {
  role = d.role;
  toneOn = !!d.dialTone;
  M = await ModemModule({ print: () => {}, printErr: () => {}, locateFile: (p) => p + VER });
  const call = (name, ret, args, vals) => M.ccall(name, ret, args, vals);
  if (d.flash && d.flash.byteLength) M.FS.writeFile('/fw/SV25.flash.bin', new Uint8Array(d.flash));   // no image from the page: the build's embedded one (build-wasm.sh EMBED_FW) is used
  if (d.profile) {   // the firmware's emulator profile (CPU clock): the preloaded call.conf names sv25
    const conf = M.FS.readFile('/call.conf', { encoding: 'utf8' }).replace(/^profile\s*=.*$/m, 'profile = ' + d.profile);
    M.FS.writeFile('/call.conf', conf);
  }   // the user's own firmware, decoded by the page
  if (call('modem_create', 'number', ['string'], ['call.conf']) !== 0) {
    postMessage({ error: 'modem_create failed' });
    return;
  }
  cpuHz = call('modem_cpu_hz', 'number', [], []);
  rate = call('modem_rate', 'number', [], []);

  const chunk = Math.floor(cpuHz / 200);             // 5 ms of simulated time per step
  const R = d.restore || null;
  const pending = R ? [] : d.script.map(([sec, text]) => ({ cyc: Math.floor(sec * cpuHz), text }));
  // The firmware is up after a time that depends on the image and its clock (about 2.0 s of simulated time for SV25, 2.5 s for SV20), so the script's times are relative to the moment
  // its MR (modem ready) lamp lights, which is when it starts answering commands: port 0x12 bit 0x02, active low.
  let ready = pending.length === 0;
  const scriptStart = pending.length ? pending[0].cyc : 0;
  let txBuf, dteBuf, scopeBuf, rxBuf;
  if (R) {
    // Grow this instance to the snapshot's size, then overwrite its memory with the snapshot's.
    const mem = new Uint8Array(R.mem);
    while (M.HEAPU8.length < mem.length) { if (!M._malloc(mem.length - M.HEAPU8.length + (8 << 20))) { postMessage({ error: 'cannot grow memory for the snapshot' }); return; } }
    M.HEAPU8.set(mem);
    ({ txBuf, dteBuf, scopeBuf, rxBuf } = R.ptrs);
    rate = call('modem_rate', 'number', [], []);
    peerSim = R.peerSim; relayConv.phase = R.relayConv.phase; relayConv.last = R.relayConv.last;
    for (const a of R.rxQueue) rxQueue.push(new Int32Array(a));
  } else {
    txBuf = M._malloc(4 * chunk);
    dteBuf = M._malloc(4096);
    scopeBuf = M._malloc(4 * 2048 * 2);
    rxBuf = M._malloc(4 * 65536);
  }
  snapPtrs = { txBuf, dteBuf, scopeBuf, rxBuf };
  // Constellation scope: the DSP cells that hold the point the data pump is working on (DM 0x0300, 0x0302).
  call('modem_scope_set', null, ['number', 'number', 'number', 'number'], d.scope === false ? [-1, -1, -1, -1] : [0x0300, 0x0302, 0x0239, 0x023C]);
  let scopeAcc = [], lastScope = 0;
  // Dial tone from the line (350 + 440 Hz) while the caller is off hook.
  let toneSamp = 0, toneAcc = 0;
  function pushTone(k) {
    const vals = new Int32Array(k);
    for (let j = 0; j < k; j++) {
      const t = (toneSamp + j) / rate;
      vals[j] = Math.round(0.3 * 32767 * (Math.sin(2 * Math.PI * 350 * t) + Math.sin(2 * Math.PI * 440 * t)) / 2) & 0xFFFF;
    }
    toneSamp += k;
    M.HEAP32.set(vals, rxBuf >> 2);
    call('modem_push_rx', 'number', ['number', 'number'], [rxBuf, k]);
  }
  // Fixed line delay: the receive buffer starts with lookahead of silence, so the
  // modem hears the other side's audio lookahead seconds late, never early.
  if (!R) {
    const pre = new Int32Array(Math.round(d.lookaheadS * 7200));
    M.HEAP32.set(pre, rxBuf >> 2);
    call('modem_push_rx', 'number', ['number', 'number'], [rxBuf, pre.length]);
  }
  t0 = performance.now();
  let simCycles = 0, waits = 0, starved = 0, lastStat = 0;
  let lastStatWall = 0, lastStatSim = 0, worstX = 0;   // sim/wall ratio per second; worst step: compute time / simulated time
  let busyMs = 0, lastBusy = 0;   // time spent inside modem_run: the emulator's share of wall time
  let lastLatch = [-2, -2, -2];   // front-panel latches, reported on change
  if (R) { simCycles = call('modem_cycles', 'number', [], []); t0 -= 1000 * simCycles / cpuHz; simNow = simCycles / cpuHz; }   // pace from where the snapshot was
  postMessage({ ready: true, rate, cpuHz });

  while (true) {
    await tick();   // let queued audio and commands in
    if (paused) {
      if (!pauseAck) { pauseAck = true; postMessage({ paused: true, sim: simCycles / cpuHz }); }
      await new Promise((r) => setTimeout(r, 15));
      continue;
    }
    const wall = (performance.now() - t0) / 1000;
    if (stopNow) break;   // runs until hung up
    if (ringStart === -2) ringStart = simCycles;
    if (ringStart >= 0) {
      const on = ((simCycles - ringStart) / cpuHz) % 6 < 2 ? 1 : 0;   // US cadence: 2 s on, 4 s off
      if (on !== ringState) { ringState = on; call('modem_set_ring', null, ['number'], [on]); postMessage({ ringState: on }); }
    } else if (ringState) { ringState = 0; call('modem_set_ring', null, ['number'], [0]); postMessage({ ringState: 0 }); }
    // Never faster than realtime, never past the other modem's audio + lookahead.
    // Run no further than the other modem's audio plus the line delay, and never faster than the wall clock.
    const limitS = Math.min(wall, peerSim + d.lookaheadS);
    const target = Math.floor(limitS * cpuHz);

    while (!toneOn && rxQueue.length) {
      const a = rxQueue.shift();
      M.HEAP32.set(a, rxBuf >> 2);
      call('modem_push_rx', 'number', ['number', 'number'], [rxBuf, a.length]);
    }
    const sendHost = (text) => {
      if (typeof text !== 'string') {   // raw bytes: through the heap, so NUL and bytes above 127 go out unchanged
        const buf = M._malloc(text.length); M.HEAPU8.set(text, buf);
        call('modem_send_bytes', null, ['number', 'number'], [buf, text.length]); M._free(buf);
        postMessage({ host: '', sim: simCycles / cpuHz });
        return;
      }
      if (/^ATD/i.test(text)) toneOn = false;   // the line stops the tone when digits start
      call('modem_send', null, ['string'], [text]);
      postMessage({ host: text, sim: simCycles / cpuHz });
    };
    while (ready && pending.length && pending[0].cyc <= simCycles) sendHost(pending.shift().text);
    while (cmdQueue.length) sendHost(cmdQueue.shift());

    // The modem runs only while its receive queue holds the audio for the time it is
    // about to simulate. Otherwise it waits: it never hears silence where audio should be.
    const rxLevel = call('modem_rx_level', 'number', [], []);
    const n = Math.min(chunk, target - simCycles);
    const fed = toneOn || rxLevel >= Math.ceil(n * rate / cpuHz);
    if (!fed) starved++;
    if (simCycles < target && fed) {
      if (toneOn) { toneAcc += n * rate / cpuHz; const k = Math.floor(toneAcc); toneAcc -= k; if (k) pushTone(k); rxQueue.length = 0; }   // exact on average: rounding every step up would pile up a permanent delay on a fast machine (tiny steps)
      const tRun = performance.now();
      call('modem_run', 'number', ['number'], [n]);
      const runMs = performance.now() - tRun;
      busyMs += runMs;
      if (n >= chunk / 2) worstX = Math.max(worstX, runMs / (1000 * n / cpuHz));   // short remainder steps are too short for the timer
      const sn = call('modem_scope_pull', 'number', ['number', 'number'], [scopeBuf, 2048]);
      if (sn) {
        const v = new Int16Array(M.HEAPU8.buffer, scopeBuf, 4 * sn);   // a fresh view: memory growth detaches old ones
        if (scopeAcc.length < 32000) for (let i = 0; i < 4 * sn; i++) scopeAcc.push(v[i]);
      }
      if (scopeAcc.length && performance.now() - lastScope > 60) {
        postMessage({ scope: Int16Array.from(scopeAcc) });
        scopeAcc = []; lastScope = performance.now();
      }
      simCycles = call('modem_cycles', 'number', [], []);
      simNow = simCycles / cpuHz;
      const latch = [0x10, 0x12, 0x14].map((p) => call('modem_port', 'number', ['number'], [p]));
      if (!ready && latch[1] >= 0 && (latch[1] & 0x02) === 0) {   // MR lit: the modem is up, the script starts 0.1 s from now
        ready = true;
        const shift = simCycles + Math.floor(0.1 * cpuHz) - scriptStart;
        for (const q of pending) q.cyc += shift;
      }
      if (latch.some((v, i) => v !== lastLatch[i])) { lastLatch = latch; postMessage({ latch, sim: simCycles / cpuHz }); }
      const got = call('modem_pull_tx', 'number', ['number', 'number'], [txBuf, chunk]);
      const tx = M.HEAP32.slice(txBuf >> 2, (txBuf >> 2) + got);
      const dn = call('modem_dte', 'number', ['number', 'number'], [dteBuf, 4096]);
      let text = '';
      for (let i = 0; i < dn; i++) text += String.fromCharCode(M.HEAPU8[dteBuf + i]);
      rate = call('modem_rate', 'number', [], []);   // the codec rate these samples were made at
      const c = tx.slice();
      toPeer.postMessage({ tx: c, rate, sim: simCycles / cpuHz }, [c.buffer]);
      postMessage({ tx, rate, dte: text, sim: simCycles / cpuHz }, [tx.buffer]);
    } else {
      waits++;
      await tick();
    }
    if (wall - lastStat >= 1) {   // once a second: where the time goes
      lastStat = wall;
      const cpu = (busyMs - lastBusy) / 10;   // percent of the last second spent computing
      const dBusy = (busyMs - lastBusy) / 1000;
      lastBusy = busyMs;
      const simT = simCycles / cpuHz, dSim = simT - lastStatSim, dWall = wall - lastStatWall;
      const speed = dWall > 0 ? dSim / dWall : 0;        // 1 = keeps up with the wall clock
      const headroom = dBusy > 0 ? dSim / dBusy : 0;     // how fast it would run unpaced
      lastStatSim = simT; lastStatWall = wall;
      postMessage({ stat: true, wall, sim: simCycles / cpuHz, waits, starved, rxMs: 1000 * rxLevel / rate, cpu, speed, headroom, worst: worstX });
      worstX = 0;
    }
  }
  postMessage({ done: true, sim: simCycles / cpuHz, rate });
}
