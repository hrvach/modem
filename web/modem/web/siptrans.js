// SIP mode audio path, in its own worker so that the page's drawing never delays it: modem worker <-> gateway WebSocket.
let ws = null, toP, fromP, t0 = 0, ready = false, codecOn = false, inCall = false, rate = 7200, fed = 0, used = 0, acc = [], accRate = 0, skipped = 0;
const sim = () => (performance.now() - t0) / 1000;
function flush() {
  if (acc.length && ws && ws.readyState === 1) {
    const n = acc.length, b = new ArrayBuffer(8 + 2 * n), dv = new DataView(b), s = new Int16Array(b, 8);
    dv.setUint32(0, accRate, true); dv.setUint32(4, n, true);
    for (let i = 0; i < n; i++) s[i] = Math.max(-32768, Math.min(32767, acc[i]));
    ws.send(b);
  }
  acc = [];
}
onmessage = (e) => {
  const d = e.data;
  if (d.init) {
    toP = d.toP; fromP = d.fromP;
    ws = new WebSocket(d.url); ws.binaryType = 'arraybuffer';
    ws.onopen = () => postMessage({ open: true });
    ws.onclose = () => postMessage({ closed: true });
    ws.onerror = () => postMessage({ error: true });
    ws.onmessage = (ev) => {
      if (typeof ev.data === 'string') return postMessage({ text: ev.data });
      if (!ready || !codecOn) return;      // the codec starts ~2 s after power on: audio before that would stay queued as delay
      const dv = new DataView(ev.data), r = dv.getUint32(0, true), n = dv.getUint32(4, true);
      if (fed - used > (inCall ? 0.4 : 0.1)) { skipped++; return; }   // the modem stalled: do not let the delay grow
      const xs = Int32Array.from(new Int16Array(ev.data, 8, n));
      fed += n / r;
      if (inCall) postMessage({ rx: xs.slice(), rate: r });
      fromP.postMessage({ tx: xs, rate: r, sim: sim() }, [xs.buffer]);
    };
    toP.onmessage = (ev) => {
      const x = ev.data.tx; codecOn = true; rate = ev.data.rate; used += x.length / rate;
      if (rate !== accRate) { flush(); accRate = rate; }
      for (let i = 0; i < x.length; i++) acc.push(x[i]);
      if (acc.length >= rate * 0.01) flush();
    };
    setInterval(() => { if (ready) fromP.postMessage({ tx: new Int32Array(0), rate, sim: sim() }); }, 10);   // keeps the modem's clock limit moving
    return;
  }
  if (d.ready) { t0 = performance.now(); fed = used = 0; ready = true; }
  if (d.inCall !== undefined) inCall = d.inCall;
  if (d.send && ws.readyState === 1) ws.send(d.send);
};
