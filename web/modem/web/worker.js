// One modem in the browser: its own wasm instance, paced to its own CPU
// clock, never faster than realtime and never more than lookaheadS past the
// other modem's audio. Audio goes out as it is produced.
importScripts('modem.js');

let M = null, role = '', cpuHz = 0, rate = 0;
const rxQueue = [], cmdQueue = [];
let peerSim = 0;
let toneOn = false;
let linePort = null;   // this modem's channel to the line worker
let ringStart = -1, ringState = 0, stopNow = false;   // ring cadence: 1 s on, 6 s period (as link.c)

self.onmessage = (e) => {
  const d = e.data;
  if (d.init) {
    if (d.port) {
      linePort = d.port;
      linePort.onmessage = (ev) => {
        if (ev.data.rx) rxQueue.push(ev.data.rx);
        if (ev.data.peer !== undefined) peerSim = ev.data.peer;
      };
    }
    start(d);
    return;
  }
  if (d.stop) { stopNow = true; return; }
  if (d.rx) rxQueue.push(d.rx);
  if (d.peer !== undefined) peerSim = d.peer;
  if (d.cmd === 'send') cmdQueue.push(d.text);
  if (d.ring !== undefined) ringStart = d.ring ? -2 : -1;   // -2: start at the next step
  if (d.tone !== undefined) toneOn = !!d.tone;
};

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
    while (pending.length && pending[0].cyc <= simCycles) sendHost(pending.shift().text);
    while (cmdQueue.length) sendHost(cmdQueue.shift());

    // Buffer level is reported (rxMs, starved) but does not gate running.
    const rxLevel = call('modem_rx_level', 'number', [], []);
    const rxOk = rxLevel >= 0.01 * rate;
    if (!rxOk) starved++;
    if (simCycles < target) {
      const n = Math.min(chunk, target - simCycles);
      if (toneOn) { pushTone(Math.round(n * rate / cpuHz)); rxQueue.length = 0; }
      call('modem_run', 'number', ['number'], [n]);
      simCycles = call('modem_cycles', 'number', [], []);
      const latch = [0x10, 0x12, 0x14].map((p) => call('modem_port', 'number', ['number'], [p]));
      if (latch.some((v, i) => v !== lastLatch[i])) { lastLatch = latch; postMessage({ latch, sim: simCycles / cpuHz }); }
      const got = call('modem_pull_tx', 'number', ['number', 'number'], [txBuf, chunk]);
      const tx = M.HEAP32.slice(txBuf >> 2, (txBuf >> 2) + got);
      const dn = call('modem_dte', 'number', ['number', 'number'], [dteBuf, 4096]);
      let text = '';
      for (let i = 0; i < dn; i++) text += String.fromCharCode(M.HEAPU8[dteBuf + i]);
      if (linePort) { const c = tx.slice(); linePort.postMessage({ tx: c, sim: simCycles / cpuHz }, [c.buffer]); }
      postMessage({ tx, dte: text, sim: simCycles / cpuHz }, [tx.buffer]);
    } else {
      waits++;
      await tick();
    }
    if (wall - lastStat >= 1) {   // once a second: where the time goes
      lastStat = wall;
      postMessage({ stat: true, wall, sim: simCycles / cpuHz, waits, starved, rxMs: 1000 * rxLevel / rate });
    }
  }
  postMessage({ done: true, sim: simCycles / cpuHz, rate });
}
