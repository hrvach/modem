// One modem, paced to the wall clock by its own CPU clock. Runs in a worker.
const { parentPort, workerData } = require('worker_threads');
const path = require('path');

const { role, script, duration, lookaheadS, dialTone } = workerData;
let toneOn = !!dialTone;   // script: [[atSec, text], ...]
let peerSim = 0;   // simulated seconds the other modem's output has reached
const ModemModule = require(path.join(__dirname, 'build', 'modem.js'));

(async () => {
  const M = await ModemModule();
  const call = (name, ret, args, vals) => M.ccall(name, ret, args, vals);
  if (call('modem_create', 'number', ['string'], ['call.conf']) !== 0)
    throw new Error('modem_create failed');
  const cpuHz = call('modem_cpu_hz', 'number', [], []);
  const rate = call('modem_rate', 'number', [], []);
  const chunk = Math.floor(cpuHz / 200);            // 5 ms of simulated time per step

  // Setup and dial commands, each at a simulated time (seconds).
  const pending = script.map(([sec, text]) => ({ cyc: Math.floor(sec * cpuHz), text }));
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
  // Fixed line delay: start with lookahead of silence, then feed audio as it arrives.
  const pre = new Int32Array(Math.round(lookaheadS * 7200));
  M.HEAP32.set(pre, rxBuf >> 2);
  call('modem_push_rx', 'number', ['number', 'number'], [rxBuf, pre.length]);
  let rxQueue = [];
  const cmdQueue = [];
  let ringStart = -1, ringState = 0;   // ring cadence: 1 s on, 6 s period (as link.c)
  parentPort.on('message', (m) => {
    if (m.rx) rxQueue.push(m.rx);
    if (m.peer !== undefined) peerSim = m.peer;
    if (m.cmd === 'send') cmdQueue.push(m.text);
    if (m.ring !== undefined) ringStart = m.ring ? -2 : -1;
    if (m.tone !== undefined) toneOn = !!m.tone;   // -2: start at the next step
  });

  const t0 = performance.now();
  let maxLagMs = 0, simCycles = 0, starved = 0;
  while (true) {
    await new Promise((r) => setImmediate(r));   // let queued audio and commands in
    const wall = (performance.now() - t0) / 1000;
    if (wall >= duration) break;
    if (ringStart === -2) ringStart = simCycles;
    if (ringStart >= 0) {
      const on = ((simCycles - ringStart) / cpuHz) % 6 < 1 ? 1 : 0;
      if (on !== ringState) { ringState = on; call('modem_set_ring', null, ['number'], [on]); }
    } else if (ringState) { ringState = 0; call('modem_set_ring', null, ['number'], [0]); }
    // Never run more than lookaheadS past the other modem's audio: with no
    // audio to hear we wait, so both stay in step.
    // Run no further than the other modem's audio plus the line delay (so no gaps),
    // and never faster than the wall clock.
    const target = Math.floor(Math.min(wall, peerSim + lookaheadS) * cpuHz);
    // Feed received audio.

    // Send any commands whose simulated time has come.
    const sendHost = (text) => {
      if (/^ATD/i.test(text)) toneOn = false;   // the line stops the tone when digits start
      call('modem_send', null, ['string'], [text]);
      parentPort.postMessage({ host: text, sim: simCycles / cpuHz });
    };
    while (pending.length && pending[0].cyc <= simCycles) sendHost(pending.shift().text);
    while (cmdQueue.length) sendHost(cmdQueue.shift());
    // Buffer level is reported (rxMs, starved) but does not gate running.
    const rxLevel = call('modem_rx_level', 'number', [], []);
    const rxOk = rxLevel >= 0.01 * rate;
    if (!rxOk) starved++;
    while (!toneOn && rxQueue.length) {
      const a = rxQueue.shift();
      M.HEAP32.set(a, rxBuf >> 2);
      call('modem_push_rx', 'number', ['number', 'number'], [rxBuf, a.length]);
    }
    if (simCycles < target) {
      const lag = (target - simCycles) / cpuHz * 1000;
      if (lag > maxLagMs) maxLagMs = lag;
      const n = Math.min(chunk, target - simCycles);
      if (toneOn) { pushTone(Math.round(n * rate / cpuHz)); rxQueue.length = 0; }
      call('modem_run', 'number', ['number'], [n]);
      simCycles = call('modem_cycles', 'number', [], []);
      const got = call('modem_pull_tx', 'number', ['number', 'number'], [txBuf, chunk]);
      const samples = M.HEAP32.slice(txBuf >> 2, (txBuf >> 2) + got);
      const dn = call('modem_dte', 'number', ['number', 'number'], [dteBuf, 4096]);
      const text = dn ? Buffer.from(M.HEAPU8.slice(dteBuf, dteBuf + dn)).toString('latin1') : '';
      parentPort.postMessage({ tx: samples, dte: text, sim: simCycles / cpuHz, lagMs: maxLagMs });
      maxLagMs = 0;
    } else {
      await new Promise((r) => setImmediate(r));
    }
  }
  parentPort.postMessage({ done: true, sim: simCycles / cpuHz, rate });
})().catch((e) => parentPort.postMessage({ error: String(e && e.stack || e) }));
