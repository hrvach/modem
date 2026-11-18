// One modem in the browser: its own wasm instance, paced to its own CPU
// clock, never faster than realtime and never more than lookaheadS past the
// other modem's audio. Audio goes out as it is produced.
importScripts('modem.js');

let M = null, role = '', cpuHz = 0, rate = 0;
const rxQueue = [], cmdQueue = [];
let escapeReq = false;   // set by the page's "+++ escape" button
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
let peerSim = 0;
let toneOn = false;
let toPeer = null, fromPeer = null;   // direct channels to the other modem's worker
let gain = 0.5;   // the line gain
const relayConv = { phase: 0, last: 0 };   // the other modem's rate -> this one's, as rs_linear in link.c
let ringStart = -1, ringState = 0, stopNow = false;   // ring cadence: 1 s on, 6 s period (as link.c)

self.onmessage = (e) => {
  const d = e.data;
  if (d.init) {
    gain = d.gain; noiseRel = d.noise || 0;
    toPeer = d.toPeer;
    fromPeer = d.fromPeer;
    // The other modem's chunks arrive in order, straight from its worker. Each carries its sim time.
    fromPeer.onmessage = (ev) => { pushRelay(ev.data.tx, ev.data.rate); peerSim = ev.data.sim; };
    start(d);
    return;
  }
  if (d.stop) { stopNow = true; return; }
  if (d.cmd === 'send') cmdQueue.push(d.text);
  if (d.cmd === 'escape') escapeReq = true;
  if (d.noise !== undefined) noiseRel = d.noise;
  if (d.ring !== undefined) ringStart = d.ring ? -2 : -1;   // -2: start at the next step
  if (d.tone !== undefined) toneOn = !!d.tone;
};

// The other modem's samples (codec rate fromRate), in order, into this modem's receive
// queue at this modem's rate, with the line gain. Linear interpolation between rates, as
// rs_linear in link.c; equal rates pass straight through.
function pushRelay(xs, fromRate) {
  const vals = [];
  if (fromRate === rate) {
    for (let i = 0; i < xs.length; i++) vals.push(addNoise(Math.trunc(xs[i] * gain)) & 0xFFFF);
  } else {
    const step = fromRate / rate;
    for (let i = 0; i < xs.length; i++) {
      const x = xs[i];
      while (relayConv.phase < 1.0) {
        vals.push(addNoise(Math.trunc(Math.trunc(relayConv.last + (x - relayConv.last) * relayConv.phase) * gain)) & 0xFFFF);
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
  M = await ModemModule({ print: () => {}, printErr: () => {} });
  const call = (name, ret, args, vals) => M.ccall(name, ret, args, vals);
  if (call('modem_create', 'number', ['string'], ['call.conf']) !== 0) {
    postMessage({ error: 'modem_create failed' });
    return;
  }
  cpuHz = call('modem_cpu_hz', 'number', [], []);
  rate = call('modem_rate', 'number', [], []);

  const chunk = Math.floor(cpuHz / 200);             // 5 ms of simulated time per step
  const pending = d.script.map(([sec, text]) => ({ cyc: Math.floor(sec * cpuHz), text }));
  const txBuf = M._malloc(4 * chunk);
  const dteBuf = M._malloc(4096);
  // Constellation scope: the DSP cells that hold the point the data pump is working on (DM 0x0224, 0x0228).
  const scopeBuf = M._malloc(2 * 2048 * 2);
  call('modem_scope_set', null, ['number', 'number'], [0x0224, 0x0228]);
  let scopeAcc = [], lastScope = 0;
  const rxBuf = M._malloc(4 * 65536);
  // Dial tone from the line (350 + 440 Hz) while the caller is off hook.
  let toneSamp = 0;
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
  const pre = new Int32Array(Math.round(d.lookaheadS * 7200));
  M.HEAP32.set(pre, rxBuf >> 2);
  call('modem_push_rx', 'number', ['number', 'number'], [rxBuf, pre.length]);
  const t0 = performance.now();
  let simCycles = 0, waits = 0, starved = 0, lastStat = 0;
  let busyMs = 0, lastBusy = 0;   // time spent inside modem_run: the emulator's share of wall time
  let lastLatch = [-2, -2, -2];   // front-panel latches, reported on change
  postMessage({ ready: true, rate, cpuHz });

  while (true) {
    await tick();   // let queued audio and commands in
    const wall = (performance.now() - t0) / 1000;
    if (stopNow) break;   // runs until hung up
    if (ringStart === -2) ringStart = simCycles;
    if (ringStart >= 0) {
      const on = ((simCycles - ringStart) / cpuHz) % 6 < 1 ? 1 : 0;
      if (on !== ringState) { ringState = on; call('modem_set_ring', null, ['number'], [on]); }
    } else if (ringState) { ringState = 0; call('modem_set_ring', null, ['number'], [0]); }
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
      if (/^ATD/i.test(text)) toneOn = false;   // the line stops the tone when digits start
      call('modem_send', null, ['string'], [text]);
      postMessage({ host: text, sim: simCycles / cpuHz });
    };
    if (escapeReq) {
      // Hayes escape: guard time of silence before, "+++" in one go, guard time of silence after. The
      // modem measures the guard in its own (simulated) time, so schedule on that clock, with margin
      // over S12's default of 1 s.
      escapeReq = false;
      pending.push({ cyc: simCycles + Math.round(1.2 * cpuHz), text: '+++' });
      pending.sort((a, b) => a.cyc - b.cyc);
    }
    while (pending.length && pending[0].cyc <= simCycles) sendHost(pending.shift().text);
    while (cmdQueue.length) sendHost(cmdQueue.shift());

    // The modem runs only while its receive queue holds the audio for the time it is
    // about to simulate. Otherwise it waits: it never hears silence where audio should be.
    const rxLevel = call('modem_rx_level', 'number', [], []);
    const n = Math.min(chunk, target - simCycles);
    const fed = toneOn || rxLevel >= Math.ceil(n * rate / cpuHz);
    if (!fed) starved++;
    if (simCycles < target && fed) {
      if (toneOn) { pushTone(Math.round(n * rate / cpuHz)); rxQueue.length = 0; }
      const tRun = performance.now();
      call('modem_run', 'number', ['number'], [n]);
      busyMs += performance.now() - tRun;
      const sn = call('modem_scope_pull', 'number', ['number', 'number'], [scopeBuf, 2048]);
      if (sn) {
        const v = new Int16Array(M.HEAPU8.buffer, scopeBuf, 2 * sn);   // a fresh view: memory growth detaches old ones
        if (scopeAcc.length < 16000) for (let i = 0; i < 2 * sn; i++) scopeAcc.push(v[i]);
      }
      if (scopeAcc.length && performance.now() - lastScope > 60) {
        postMessage({ scope: Int16Array.from(scopeAcc) });
        scopeAcc = []; lastScope = performance.now();
      }
      simCycles = call('modem_cycles', 'number', [], []);
      const latch = [0x10, 0x12, 0x14].map((p) => call('modem_port', 'number', ['number'], [p]));
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
      lastBusy = busyMs;
      postMessage({ stat: true, wall, sim: simCycles / cpuHz, waits, starved, rxMs: 1000 * rxLevel / rate, cpu });
    }
  }
  postMessage({ done: true, sim: simCycles / cpuHz, rate });
}
