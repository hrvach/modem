// The phone line: starts two independent modem workers, moves audio between
// them and writes a stereo WAV (left = caller B, right = answerer A).
// Run from the repo root:  node web/modem/line.js [seconds]
const { Worker } = require('worker_threads');
const fs = require('fs');
const path = require('path');

const duration = Number(process.argv[2] || 40);
const gain = 0.5;                              // link default
const lookaheadS = Number(process.env.LOOKAHEAD_S || 0.1);   // line latency: 100 ms default
const outWav = path.join('out', 'modem_line.wav');

// Setup, as call.conf has it; the answerer autoanswers and the caller dials.
const scriptA = [[1.0, 'AT\r'], [2.0, 'ATQ0V1\r']];   // answerer: host answers RING with ATA
const dialNumber = process.env.DIAL || '5551234';
const setupB = 'ATQ0V1X3\r';   // X3: no dial-tone detection
const toneOnB = false;   // no line dial tone (X3 is set)
const scriptB = [[1.0, 'AT\r'], [2.0, setupB], [3.0, `ATDT${dialNumber}\r`]];

const rec = { A: [], B: [] };
let ataSent = false;
const pendTxt = {};
const dte = { A: '', B: '' };
const sent = { A: false, B: false };
let rate = 0, done = 0;
const workers = {};

function start(role, script) {
  const w = new Worker(path.join(__dirname, 'worker.js'),
    { workerData: { role, script, duration: duration + 1, lookaheadS, dialTone: role === 'B' && toneOnB } });
  workers[role] = w;
  w.on('message', (m) => {
    if (m.error) { console.error(role, 'error:', m.error); process.exit(1); }
    if (m.host !== undefined) {
      process.stdout.write(`${m.sim.toFixed(2)} HOST->${role} ${JSON.stringify(m.host)}\n`);
      if (role === 'B' && m.host.includes('ATDT')) workers.A.postMessage({ ring: 1 });
      return;
    }
    if (m.done) { rate = m.rate; if (++done === 2) finish(); return; }
    rec[role].push(Int32Array.from(m.tx));
    if (m.host !== undefined && role === 'B' && m.host.includes('ATDT')) workers.A.postMessage({ ring: 1 });
    if (m.dte) {
      dte[role] += m.dte;
      // Log only complete lines: hold text until a newline arrives.
      pendTxt[role] = (pendTxt[role] || '') + m.dte;
      if (role === 'A' && !ataSent && (dte.A + m.dte).includes('RING')) {
        ataSent = true;
        workers.A.postMessage({ cmd: 'send', text: 'ATA\r' });
        workers.A.postMessage({ ring: 0 });   // stop ringing once ATA is sent
      }
      const parts = pendTxt[role].split(/\r\n|\r|\n/);
      pendTxt[role] = parts.pop();             // unfinished fragment stays pending
      for (const line of parts) if (line.trim()) process.stdout.write(`${m.sim.toFixed(2)} ${role}->HOST ${JSON.stringify(line)}\n`);
      if (dte.A.includes('CONNECT') && dte.B.includes('CONNECT') && !sent.A) {
        sent.A = sent.B = true;
        workers.B.postMessage({ cmd: 'send', text: 'Hello world from courier\r' });
        workers.A.postMessage({ cmd: 'send', text: 'Hello back from the answerer\r' });
      }
    }
    // Route this chunk to the other modem, with the line gain applied.
    const other = role === 'A' ? 'B' : 'A';
    const g = gain;
    const out = new Int32Array(m.tx.length);
    for (let i = 0; i < m.tx.length; i++) out[i] = (Math.trunc(m.tx[i] * g)) & 0xFFFF;
    setTimeout(() => workers[other].postMessage({ rx: out, s0: m.s0, peer: m.sim }), lookaheadS * 1000);   // line latency
  });
}

function writeWav(path_, left, right, sr) {
  const n = Math.min(left.length, right.length);
  const buf = Buffer.alloc(44 + n * 4);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * 4, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(2, 22); buf.writeUInt32LE(sr, 24); buf.writeUInt32LE(sr * 4, 28);
  buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36);
  buf.writeUInt32LE(n * 4, 40);
  for (let i = 0; i < n; i++) {
    buf.writeInt16LE(Math.max(-32768, Math.min(32767, left[i] << 16 >> 16)), 44 + i * 4);
    buf.writeInt16LE(Math.max(-32768, Math.min(32767, right[i] << 16 >> 16)), 46 + i * 4);
  }
  fs.writeFileSync(path_, buf);
}

function finish() {
  const cat = (arrs) => {
    const n = arrs.reduce((s, a) => s + a.length, 0);
    const out = new Int32Array(n); let o = 0;
    for (const a of arrs) { out.set(a, o); o += a.length; }
    return out;
  };
  const B = cat(rec.B), A = cat(rec.A);
  writeWav(outWav, B, A, rate);
  console.log(`done: wrote ${outWav} (${(Math.min(A.length, B.length) / rate).toFixed(2)} s at ${rate} Hz)`);
  console.log('CONNECT both:', dte.A.includes('CONNECT') && dte.B.includes('CONNECT'));
  console.log('answerer got caller text:', dte.A.includes('Hello world from courier'));
  console.log('caller got answerer text:', dte.B.includes('Hello back from the answerer'));
  process.exit(0);
}

fs.mkdirSync('out', { recursive: true });
start('A', scriptA);
start('B', scriptB);
