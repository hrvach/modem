// SIP mode of the Lab page: one modem (role B, the caller's settings and script) shown in the left slot (A), its
// audio carried by gateway.py over a WebSocket to BinModem or D-Modem. The worker's toPeer / fromPeer ports stand
// in for the other modem: the worker sends its audio on toPeer; the peer feeds the received audio back on fromPeer
// with the sim time it expects (the SIP clock is the wall clock) and keeps the worker's peerSim moving.
// The page's shared code (powerOn is routed here, dial / hang up, the LINE A and LINE B cards, the VU meters) is
// in index.html; this file is the transport and the SIP panel only.
(function () {
  const $s = (id) => document.getElementById(id);
  const DEFAULT_URL = 'ws://' + (location.hostname || '127.0.0.1') + ':8777';   // gateway.py on the machine that serves the page
  let sip = null;   // { w, ws, t0, timers, lastRate, state, offhook, dialing, invited }

  function say(msg) { const el = $s('sip-status'); if (el) el.textContent = msg; }
  function setCall(st) { if (sip) sip.state = st; const el = $s('sip-call-state'); if (el) el.textContent = st; }
  function wallSim() { return sip ? (performance.now() - sip.t0) / 1000 : 0; }

  function readGateway(m) {
    if (m.type === 'stat') {
      const el = $s('sip-gw');
      if (el) el.textContent = 'gaps ' + m.tx_gaps + ' · late ' + m.rx_late + ' · lost ' + m.rx_lost + ' · underruns ' + m.rx_underruns +
        ' · tx buf ' + m.tx_buf_ms + ' ms · rx buf ' + m.rx_buf_ms + ' ms';
      if (m.call) setCall(m.call);
    } else if (m.type === 'call') { setCall(m.state + (m.msg ? ' (' + m.msg + ')' : '')); say('Call: ' + m.state);
    } else if (m.type === 'event') { say(m.msg); }
  }

  function onWorker(m) {   // the modem's stat and latch messages (the Lab's onMessage gets the same messages)
    if (m.ready) { sip.ready = true; sip.tr.postMessage({ ready: true }); return; }   // the modem's own clock starts now: count the line from here, or the start-up time becomes a permanent delay
    if (m.stat) {
      if (sip.ws.readyState === 1) sip.ws.send(JSON.stringify({ cmd: 'page', speed: m.speed, headroom: m.headroom, worst: m.worst, starved: m.starved, rxMs: m.rxMs }));
      const f = (v, d) => (typeof v === 'number' ? v.toFixed(d) : '-');
      if ($s('sip-speed')) $s('sip-speed').textContent = f(m.speed, 3) + ' (sim ' + f(m.sim, 1) + ' s / wall ' + f(m.wall, 1) + ' s)';
      if ($s('sip-headroom')) $s('sip-headroom').textContent = f(m.headroom, 2) + 'x';
      if ($s('sip-worst')) $s('sip-worst').textContent = f(m.worst, 2) + ' ms';
      return;
    }
    if (m.rate) { sip.lastRate = m.rate; if ($s('sip-codec')) $s('sip-codec').textContent = m.rate + ' Hz'; }
    if (m.dte) { if (/CONNECT/.test(m.dte)) sip.online = true; if (/NO CARRIER/.test(m.dte)) sip.online = false; }
    if (m.tx) listenDigits(m.tx, m.rate);
    if (m.latch) { try { setSpeaker('B', m.latch[1]); } catch (e) { /* no audio */ } }   // the modem's speaker plays the line: both sides, under its own ATM / ATL setting
    if (m.latch) offHook(m.latch[0] >= 0 && (m.latch[0] & 1) === 1);
  }

  // powerOn is called by the Lab's Power on button when the page is in SIP mode
  function powerOn() {
    if (sip) return say('Already on.');
    if (typeof workers === 'undefined') return;
    if (Object.keys(workers).length) return say('Modem A is on: power off first.');
    if (!fwBytes) { statusEl.textContent = 'Load the firmware first.'; return; }
    try { audioInit(); instClear(); } catch (e) { /* no audio */ }
    simNow = { A: 0, B: 0 }; dte = { A: '', B: '' }; stopping = false; logText.A = ['']; logCol.A = 0; logEls.A.textContent = ''; for (const r of ['A', 'B']) { fftBuf[r] = []; }
    const url = $s('sip-url').value.trim() || DEFAULT_URL;
    const toW = new MessageChannel(), fromW = new MessageChannel();   // modem worker: toPeer = toW.port1, fromPeer = fromW.port2
    const w = new Worker('worker.js?v=' + WORKER_BUILD), tr = new Worker('siptrans.js?v=' + WORKER_BUILD);
    const ws = { readyState: 0, send: (m) => tr.postMessage({ send: m }), close: () => tr.terminate() };   // the socket lives in siptrans.js
    sip = { w, tr, ws, t0: performance.now(), timers: [], lastRate: 7200, state: 'off', offhook: false, invited: false, digits: '', dtmf: [], dtmfRate: 0, lastKey: null, toneOn: false, ready: false };
    workers = { A: w };   // the Lab's shared code sees one modem, in the left slot
    w.onmessage = (e) => { onWorker(e.data); onMessage('A', e.data); };
    w.onerror = (e) => say('worker error: ' + e.message);
    tr.onmessage = (e) => {
      const m = e.data;
      if (m.open) { ws.readyState = 1; levels(); say('Gateway connected. Dial from the terminal: ATDT100.'); }
      else if (m.closed) { ws.readyState = 3; say('Gateway closed.'); setCall('gateway closed'); }
      else if (m.error) say('Gateway not reachable at ' + url + ' (start gateway.py).');
      else if (m.rx) { try { playChunk('B', m.rx, m.rate); } catch (err) { /* audio only */ } }
      else if (m.text) { try { readGateway(JSON.parse(m.text)); } catch (err) { /* ignore */ } }
    };
    tr.postMessage({ init: true, url, toP: toW.port2, fromP: fromW.port1 }, [toW.port2, fromW.port1]);
    // the caller's settings and script (B): the speed selector, as the Lab sends them to B
    const script = typeof setupScripts === 'function' ? setupScripts().B : [];
    w.postMessage({ init: true, flash: fwBytes, profile: fwProfile, scope: typeof scopeWanted === 'function' ? scopeWanted() : false, role: 'B', script, restore: null,
      lookaheadS: 0.08, gain: GAIN, noise: 0, line: lineParams(), dialTone: false, toPeer: toW.port1, fromPeer: fromW.port2 },
      [toW.port1, fromW.port2]);
    $('go').disabled = false; $('go').textContent = 'Power off'; $('speed').disabled = true; $('dial').disabled = false; $('hangup').disabled = false;
    setCall('powered on');
    statusEl.textContent = 'SIP mode: modem powered on. Dial from the terminal: ATDT100.';
  }

  function powerOff() {
    if (!sip) return;
    const s = sip; sip = null;
    for (const t of s.timers) clearInterval(t);
    s.w.terminate();   // at once: no CPU used after this
    try { s.ws.send(JSON.stringify({ cmd: 'hangup' })); } catch (e) { /* closed */ }
    try { s.ws.close(); } catch (e) { /* closed */ }
    workers = {}; $('go').textContent = 'Power on';
    $('go').disabled = false; $('speed').disabled = false; $('dial').disabled = true; $('hangup').disabled = true;
    setCall('off'); say('Powered off.');
  }

  // The modem does everything, as on a real line: off hook -> dial tone; its DTMF digits -> INVITE 2 s after the last one
  // (# at once); on hook -> BYE. Start call / Hang up in the toolbar only type ATDT100 / ATH.
  function call() { if (sip) sip.w.postMessage({ cmd: 'send', text: 'ATDT100\r' }); else say('Power on first.'); }
  function hangup() {   // end the SIP call at once; the modem: a key aborts a dial, +++ leaves data mode, then ATH
    if (!sip) return;
    clearTimeout(sip.digitTimer);
    if (sip.ws.readyState === 1) sip.ws.send(JSON.stringify({ cmd: 'hangup' }));
    sip.invited = false; sip.tr.postMessage({ inCall: false }); setCall('hanging up');
    const type = (t, ms) => setTimeout(() => sip && sip.offhook && sip.w.postMessage({ cmd: 'send', text: t }), ms);
    if (sip.online) { type('+++', 1200); type('ATH\r', 2600); } else { type('\r', 0); type('ATH\r', 700); }
    sip.online = false;
  }
  function tone(onoff) { if (sip.toneOn !== onoff) { sip.toneOn = onoff; sip.w.postMessage({ tone: onoff }); } }
  function offHook(oh) {
    if (oh === sip.offhook) return;
    sip.offhook = oh;
    if (oh) {
      sip.digits = ''; sip.lastKey = null; sip.dtmf = []; sip.invited = false; lcd(''); tone(true); setCall('off hook');
    } else {
      tone(false); clearTimeout(sip.digitTimer);
      if (sip.invited && sip.ws.readyState === 1) sip.ws.send(JSON.stringify({ cmd: 'hangup' }));
      sip.invited = false; sip.tr.postMessage({ inCall: false }); setCall('on hook');
    }
  }
  function listenDigits(tx, r) {   // the modem's own DTMF
    if (!sip.offhook || sip.invited) return;
    if (r !== sip.dtmfRate) { sip.dtmf = []; sip.dtmfRate = r; }
    for (let i = 0; i < tx.length; i++) sip.dtmf.push(tx[i]);
    const N = Math.round(r * 0.025);
    while (sip.dtmf.length >= N) {
      const key = decodeDigit(sip.dtmf.splice(0, N), r);
      if (key && key !== sip.lastKey) {
        tone(false); stopDialTone();
        if (key !== '#') sip.digits += key;
        lcd(sip.digits); setCall('dialing ' + sip.digits);
        clearTimeout(sip.digitTimer);
        sip.digitTimer = setTimeout(invite, key === '#' ? 50 : 2000);
      }
      sip.lastKey = key;
    }
  }
  function invite() {
    if (!sip || sip.invited || !sip.offhook || !sip.digits) return;
    if (sip.ws.readyState !== 1) return say('Gateway is not connected: power off and on again.');
    sip.invited = true; sip.tr.postMessage({ inCall: true });
    sip.ws.send(JSON.stringify({ cmd: 'invite', dest: $s('sip-dest').value, number: sip.digits }));
    setCall('calling ' + sip.digits);
  }

  function levels() {
    if (!sip || sip.ws.readyState !== 1) return;
    sip.ws.send(JSON.stringify({ cmd: 'levels', tx: Number($s('sip-tx').value), rx: Number($s('sip-rx').value) }));
  }

  const on = (id, fn) => { const el = $s(id); if (el) el.addEventListener('click', fn); };
  on('sip-btn-off', powerOff);
  if ($s('sip-url')) $s('sip-url').value = DEFAULT_URL;
  if ($s('sip-rx')) { $s('sip-rx').value = '2'; $s('sip-tx').value = '1'; $s('sip-dest').value = 'dmodem'; }   // not what the browser remembered from an older page
  for (const id of ['sip-tx', 'sip-rx']) { const el = $s(id); if (el) el.addEventListener('change', levels); }
  window.SIP = { powerOn, powerOff, call, hangup, isOn: () => !!sip };
})();
