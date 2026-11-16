// The phone line, in its own worker so page UI work cannot delay the audio.
// Each modem worker talks to this worker over its own message channel; audio
// is routed to the other modem after the line latency, with the line gain.
let lookahead = 0.1, gain = 0.5;
const ports = {};

self.onmessage = (e) => {
  const d = e.data;
  if (d.init) { lookahead = d.lookaheadS; gain = d.gain; return; }
  if (d.role && d.port) {
    ports[d.role] = d.port;
    d.port.onmessage = (ev) => route(d.role, ev.data);
  }
};

function route(role, m) {
  if (!m.tx) return;
  const other = role === 'A' ? 'B' : 'A';
  const out = new Int32Array(m.tx.length);
  for (let i = 0; i < m.tx.length; i++) out[i] = Math.trunc(m.tx[i] * gain) & 0xFFFF;
  setTimeout(() => {
    if (ports[other]) ports[other].postMessage({ rx: out, peer: m.sim }, [out.buffer]);
  }, lookahead * 1000);
}
