//! One WebSocket client, at most one call. Threads (std::thread::scope):
//!   ws reader  (this thread): parses frames, text commands, modem audio into the transmit resampler
//!   pacer      : 20 ms ticks on absolute deadlines: RTP out, modem frame out (20 ms per 20 ms), stats
//!   sip        : SIP datagrams, INVITE retries
//!   rtp        : RTP datagrams, symmetric source, G.711 decode into the receive queue
use crate::dsp::{self, Puller, Resampler, DRIFT_MAX};
use crate::json::{self, Obj};
use crate::logfile::log;
use crate::sip::{self, Call, CallState};
use crate::ws::{self, Msg, Parser};
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::net::{Shutdown, SocketAddr, TcpStream, UdpSocket};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const TICK: Duration = Duration::from_millis(20);
const RX_TARGET_MAX_MS: f64 = 200.0;
const RX_TARGET_STEP_MS: f64 = 20.0;

#[derive(Clone, Debug)]
pub struct Cfg {
    pub jitter_ms: f64,
    pub tx_gain: f64,
    pub rx_gain: f64,
    pub binmodem_port: u16,
}

#[derive(Default)]
struct Counters {
    tx_gaps: u64,
    tx_pkts: u64,
    rx_pkts: u64,
    rx_lost: u64,
    rx_late: u64,
    rx_underruns: u64,
    rx_frames: u64,
    tx_in: u64,
    tx_sq: f64,
    rx_n: u64,
    rx_sq: f64,
    t_rep: Option<Instant>,
}

struct State {
    cfg: Cfg,
    call: Option<Call>,
    rate: u32,
    tx_gain: f64,
    rx_gain: f64,
    tx_rs: Resampler,
    tx_out: Vec<f32>,
    tx_primed: bool,
    rxq: Puller,
    rx_primed: bool,
    rx_target_ms: f64,
    c: Counters,
    exp_seq: Option<u16>,
    seq: u16,
    ts: u32,
    ssrc: u32,
    rec: Option<Rec>,
    last_stat: Instant,
}

struct Ctx {
    cfg: Cfg,
    st: Mutex<State>,
    ws: Mutex<TcpStream>,
    sip: UdpSocket,
    rtp: UdpSocket,
    stop: AtomicBool,
}

fn to_i16s(x: &[f32]) -> Vec<i16> {
    x.iter().map(|&v| dsp::to_i16(v)).collect()
}

fn ev_call(state: &str, msg: &str) -> String {
    format!("{{\"type\": \"call\", \"state\": {}, \"msg\": {}}}", json::esc(state), json::esc(msg))
}

fn ev_event(msg: &str) -> String {
    format!("{{\"type\": \"event\", \"msg\": {}}}", json::esc(msg))
}

fn ws_send(ctx: &Ctx, op: u8, payload: &[u8]) {
    let fr = ws::frame(op, payload);
    let mut w = ctx.ws.lock().unwrap();
    if w.write_all(&fr).is_err() {
        ctx.stop.store(true, Ordering::SeqCst);
        let _ = w.shutdown(Shutdown::Both);
    }
}

fn send_text(ctx: &Ctx, s: &str) {
    ws_send(ctx, 0x1, s.as_bytes());
}

fn send_bin(ctx: &Ctx, rate: u32, s: &[i16]) {
    let mut p = Vec::with_capacity(8 + 2 * s.len());
    p.extend_from_slice(&rate.to_le_bytes());
    p.extend_from_slice(&(s.len() as u32).to_le_bytes());
    for v in s {
        p.extend_from_slice(&v.to_le_bytes());
    }
    ws_send(ctx, 0x2, &p);
}

/// Recording to ~/.cache/courier-sip/rec (as gateway.py): raw int16 LE files and rate.txt.
struct Rec {
    tx8k: File,
    rx8k: File,
    modem_out: File,
    modem_in: File,
    rate: File,
    n: u64,
    last: Option<u32>,
    t0: Instant,
}

impl Rec {
    fn new() -> io::Result<Rec> {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
        let dir: PathBuf = PathBuf::from(home).join(".cache/courier-sip/rec");
        fs::create_dir_all(&dir)?;
        let p = dir.join(stamp());
        let f = |k: &str| File::create(format!("{}_{}.raw", p.display(), k));
        Ok(Rec {
            tx8k: f("tx8k")?,
            rx8k: f("rx8k")?,
            modem_out: f("modem_out")?,
            modem_in: f("modem_in")?,
            rate: File::create(format!("{}_rate.txt", p.display()))?,
            n: 0,
            last: None,
            t0: Instant::now(),
        })
    }

    fn w(f: &mut File, x: &[i16]) {
        let mut b = Vec::with_capacity(2 * x.len());
        for v in x {
            b.extend_from_slice(&v.to_le_bytes());
        }
        let _ = f.write_all(&b);
    }

    fn rate(&mut self, r: u32, n: usize) {
        if self.last != Some(r) {
            let _ = writeln!(self.rate, "{:.3} s modem sample {} rate {}", self.t0.elapsed().as_secs_f64(), self.n, r);
            let _ = self.rate.flush();
            self.last = Some(r);
        }
        self.n += n as u64;
    }
}

/// "MMDD_HHMMSS" in UTC (gateway.py uses local time).
fn stamp() -> String {
    let secs = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0) as i64;
    let days = secs.div_euclid(86400);
    let rem = secs.rem_euclid(86400);
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    format!("{:02}{:02}_{:02}{:02}{:02}", m, d, rem / 3600, (rem / 60) % 60, rem % 60)
}

fn hello(cfg: &Cfg) -> String {
    format!(
        "{{\"type\": \"hello\", \"jitter_ms\": {:?}, \"levels\": {{\"tx\": {:?}, \"rx\": {:?}}}, \"dests\": [\"binmodem\", \"dmodem\"]}}",
        cfg.jitter_ms, cfg.tx_gain, cfg.rx_gain
    )
}

/// Handshake. Returns the bytes after the request head (frames the client may have sent early), or None.
pub fn accept(stream: &mut TcpStream, host: &str) -> Option<Vec<u8>> {
    stream.set_read_timeout(Some(Duration::from_secs(5))).ok()?;
    let mut data = Vec::new();
    let mut buf = [0u8; 4096];
    let end = loop {
        if let Some(p) = data.windows(4).position(|w| w == b"\r\n\r\n") {
            break p;
        }
        if data.len() > 16384 {
            return None;
        }
        match stream.read(&mut buf) {
            Ok(0) | Err(_) => return None,
            Ok(n) => data.extend_from_slice(&buf[..n]),
        }
    };
    let head = String::from_utf8_lossy(&data[..end]).into_owned();
    let leftover = data[end + 4..].to_vec();
    let hdr = ws::parse_headers(&head);
    if let Some(o) = hdr.get("origin") {
        if !o.is_empty() && !ws::origin_ok(o, host) {
            let _ = stream.write_all(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n");
            log(&format!("refused origin {:?}", o));
            return None;
        }
    }
    let Some(key) = hdr.get("sec-websocket-key") else {
        let _ = stream.write_all(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n");
        return None;
    };
    stream.write_all(ws::response_101(key).as_bytes()).ok()?;
    stream.set_read_timeout(None).ok()?;
    stream.set_nodelay(true).ok()?;
    Some(leftover)
}

/// Runs one WebSocket session until the client closes.
pub fn run(cfg: &Cfg, stream: TcpStream, leftover: Vec<u8>) -> io::Result<()> {
    let rd = stream.try_clone()?;
    stream.set_write_timeout(Some(Duration::from_secs(3)))?;
    let sip = UdpSocket::bind("0.0.0.0:0")?;
    let rtp = UdpSocket::bind("0.0.0.0:0")?;
    sip.set_read_timeout(Some(Duration::from_millis(50)))?;
    rtp.set_read_timeout(Some(Duration::from_millis(50)))?;
    let st = State {
        cfg: cfg.clone(),
        call: None,
        rate: 9600,
        tx_gain: cfg.tx_gain,
        rx_gain: cfg.rx_gain,
        tx_rs: Resampler::new(),
        tx_out: vec![],
        tx_primed: false,
        rxq: Puller::new(),
        rx_primed: false,
        rx_target_ms: cfg.jitter_ms,
        c: Counters::default(),
        exp_seq: None,
        seq: sip::rnd32() as u16,
        ts: sip::rnd32(),
        ssrc: sip::rnd32(),
        rec: None,
        last_stat: Instant::now(),
    };
    let ctx = Ctx { cfg: cfg.clone(), st: Mutex::new(st), ws: Mutex::new(stream), sip, rtp, stop: AtomicBool::new(false) };
    send_text(&ctx, &hello(&ctx.cfg));
    log("session opened");
    let mut parser = Parser::default();
    parser.feed(&leftover);
    thread::scope(|s| {
        s.spawn(|| pacer(&ctx));
        s.spawn(|| sip_loop(&ctx));
        s.spawn(|| rtp_loop(&ctx));
        ws_reader(&ctx, rd, parser);
        ctx.stop.store(true, Ordering::SeqCst);
    });
    {
        let mut g = ctx.st.lock().unwrap();
        if let Some(call) = g.call.as_mut() {
            if call.state == CallState::Connected {
                call.bye(&ctx.sip);
            }
        }
    }
    log("session closed");
    Ok(())
}

fn ws_reader(ctx: &Ctx, mut rd: TcpStream, mut parser: Parser) {
    let mut buf = vec![0u8; 65536];
    loop {
        while let Some(m) = parser.next() {
            match m {
                Msg::Ping(p) => ws_send(ctx, 0xA, &p),
                Msg::Close => return,
                Msg::Text(t) => handle_text(ctx, &t),
                Msg::Binary(b) => handle_bin(ctx, &b),
            }
            if ctx.stop.load(Ordering::SeqCst) {
                return;
            }
        }
        match rd.read(&mut buf) {
            Ok(0) | Err(_) => return,
            Ok(n) => parser.feed(&buf[..n]),
        }
    }
}

fn handle_text(ctx: &Ctx, t: &[u8]) {
    let Ok(m) = json::parse_flat(&String::from_utf8_lossy(t)) else { return };
    match json::get_str(&m, "cmd").unwrap_or("") {
        "invite" => invite(ctx, &m),
        "hangup" => {
            let ev = {
                let mut g = ctx.st.lock().unwrap();
                match g.call.as_mut() {
                    Some(c) if c.state != CallState::Ended => {
                        c.bye(&ctx.sip);
                        Some(ev_call("ended", &c.end_reason))
                    }
                    _ => None,
                }
            };
            if let Some(e) = ev {
                send_text(ctx, &e);
                log("hangup");
            }
        }
        "levels" => {
            let msg = {
                let mut g = ctx.st.lock().unwrap();
                if let Some(v) = json::get_num(&m, "tx") {
                    g.tx_gain = v;
                }
                if let Some(v) = json::get_num(&m, "rx") {
                    g.rx_gain = v;
                }
                format!("levels tx {:.3} rx {:.3}", g.tx_gain, g.rx_gain)
            };
            send_text(ctx, &ev_event(&msg));
        }
        "page" => {
            let f = |k: &str| json::get_num(&m, k).unwrap_or(0.0);
            log(&format!(
                "page speed={:.3} headroom={:.2} worst={:.2} starved={} rxMs={:.0}",
                f("speed"),
                f("headroom"),
                f("worst"),
                f("starved") as i64,
                f("rxMs")
            ));
        }
        "rate" => {
            if let Some(r) = json::get_num(&m, "rate") {
                ctx.st.lock().unwrap().rate = r as u32;
            }
        }
        _ => {}
    }
}

fn invite(ctx: &Ctx, m: &Obj) {
    let ev_out;
    let mut g = ctx.st.lock().unwrap();
    let s = &mut *g;
    if !s.call.as_ref().is_none_or(|c| c.state == CallState::Ended) {
        return;
    }
    let dest = json::get_str(m, "dest").unwrap_or("binmodem").to_string();
    let num = match json::get(m, "number") {
        Some(json::Val::Str(x)) => x.clone(),
        Some(json::Val::Num(x)) => format!("{}", *x as i64),
        _ => "100".to_string(),
    };
    let Some(dest_sa) = sip::dest_addr(&dest, s.cfg.binmodem_port) else {
        drop(g);
        send_text(ctx, &ev_event("refused: bad destination or number"));
        return;
    };
    if num.is_empty() || !num.bytes().all(|b| b.is_ascii_digit()) {
        drop(g);
        send_text(ctx, &ev_event("refused: bad destination or number"));
        return;
    }
    let lip = sip::local_ip(dest_sa);
    let rport = ctx.rtp.local_addr().map(|a| a.port()).unwrap_or(0);
    let lport = ctx.sip.local_addr().map(|a| a.port()).unwrap_or(0);
    let mut call = Call::new(dest_sa, &num, lip, rport, lport);
    s.c = Counters::default();
    s.exp_seq = None;
    s.tx_out.clear();
    s.tx_rs = Resampler::new();
    s.rxq = Puller::new();
    s.tx_primed = false;
    s.rx_primed = false;
    s.rx_target_ms = s.cfg.jitter_ms;
    s.rec = Rec::new().ok();
    call.invite(&ctx.sip);
    s.call = Some(call);
    ev_out = format!(
        "{{\"type\": \"call\", \"state\": \"inviting\", \"dest\": {}, \"number\": {}}}",
        json::esc(&dest),
        json::esc(&num)
    );
    drop(g);
    send_text(ctx, &ev_out);
    log(&format!("INVITE {} to {}", num, dest_sa));
}

fn handle_bin(ctx: &Ctx, p: &[u8]) {
    if p.len() < 8 {
        return;
    }
    let rate = u32::from_le_bytes([p[0], p[1], p[2], p[3]]);
    let n = (u32::from_le_bytes([p[4], p[5], p[6], p[7]]) as usize).min((p.len() - 8) / 2);
    let x: Vec<i16> = (0..n).map(|i| i16::from_le_bytes([p[8 + 2 * i], p[9 + 2 * i]])).collect();
    let xf: Vec<f32> = x.iter().map(|&v| v as f32).collect();
    let mut g = ctx.st.lock().unwrap();
    let s = &mut *g;
    s.rate = rate;
    s.c.tx_in += n as u64;
    s.c.tx_sq += xf.iter().map(|&v| (v * v) as f64).sum::<f64>();
    if let Some(rec) = s.rec.as_mut() {
        rec.rate(rate, n);
        Rec::w(&mut rec.modem_out, &x);
    }
    if matches!(&s.call, Some(c) if c.state == CallState::Connected) {
        let target = s.cfg.jitter_ms;
        let adj = ((s.tx_out.len() as f64 / 8000.0 - target / 1000.0) / 0.05 * DRIFT_MAX).clamp(-DRIFT_MAX, DRIFT_MAX);
        let gain = s.tx_gain as f32;
        let scaled: Vec<f32> = xf.iter().map(|v| v * gain).collect();
        let out = s.tx_rs.process(&scaled, rate as f64, 8000.0, adj);
        s.tx_out.extend_from_slice(&out);
    }
}

fn sip_loop(ctx: &Ctx) {
    let mut buf = vec![0u8; 65535];
    while !ctx.stop.load(Ordering::SeqCst) {
        match ctx.sip.recv_from(&mut buf) {
            Ok((n, _)) => {
                let txt = String::from_utf8_lossy(&buf[..n]).into_owned();
                if txt.starts_with("SIP/2.0") || txt.starts_with("BYE") {
                    let hdr = sip::parse_sip(&txt);
                    let ev = {
                        let mut g = ctx.st.lock().unwrap();
                        g.call.as_mut().and_then(|c| c.on_sip(&ctx.sip, &txt, &hdr))
                    };
                    if let Some((state, msg)) = ev {
                        send_text(ctx, &ev_call(state, &msg));
                        log(&format!("SIP: {} {}", state, msg));
                    }
                }
            }
            Err(e) if !matches!(e.kind(), io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut) => {
                thread::sleep(Duration::from_millis(10));
            }
            Err(_) => {}
        }
        let mut g = ctx.st.lock().unwrap();
        if let Some(call) = g.call.as_mut() {
            if call.retry_due() {
                call.send(&ctx.sip);
            }
        }
    }
}

fn rtp_loop(ctx: &Ctx) {
    let mut buf = vec![0u8; 2048];
    while !ctx.stop.load(Ordering::SeqCst) {
        match ctx.rtp.recv_from(&mut buf) {
            Ok((n, src)) => rtp_packet(ctx, &buf[..n], src),
            Err(e) if !matches!(e.kind(), io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut) => {
                thread::sleep(Duration::from_millis(10));
            }
            Err(_) => {}
        }
    }
}

fn rtp_packet(ctx: &Ctx, d: &[u8], src: SocketAddr) {
    if d.len() <= 12 {
        return;
    }
    let mut g = ctx.st.lock().unwrap();
    let s = &mut *g;
    let Some(call) = s.call.as_mut() else { return };
    if call.state != CallState::Connected {
        return;
    }
    if call.remote != Some(src) {
        log(&format!("RTP source {}", src));
        call.remote = Some(src);
    }
    let sq = u16::from_be_bytes([d[2], d[3]]);
    if let Some(e) = s.exp_seq {
        let gap = sq.wrapping_sub(e);
        if gap < 0x8000 {
            s.c.rx_lost += gap as u64;
        } else {
            s.c.rx_late += 1;
            return;
        }
    }
    s.exp_seq = Some(sq.wrapping_add(1));
    s.c.rx_pkts += 1;
    let x: Vec<f32> = d[12..].iter().map(|&b| dsp::ulaw_dec(b) as f32 * s.rx_gain as f32).collect();
    s.c.rx_sq += x.iter().map(|&v| (v * v) as f64).sum::<f64>();
    s.c.rx_n += x.len() as u64;
    if let Some(rec) = s.rec.as_mut() {
        Rec::w(&mut rec.rx8k, &to_i16s(&x));
    }
    s.rxq.push(&x);
}

/// 20 ms ticks on absolute deadlines (no drift); a late wake catches up at most 10 ticks, then resyncs.
fn pacer(ctx: &Ctx) {
    let mut next = Instant::now() + TICK;
    while !ctx.stop.load(Ordering::SeqCst) {
        let now = Instant::now();
        if next > now {
            thread::sleep(next - now);
        }
        let now = Instant::now();
        let mut k = 0;
        while next <= now && k < 10 {
            tick(ctx);
            next += TICK;
            k += 1;
        }
        if next <= now {
            next = now + TICK;
        }
    }
}

fn tick(ctx: &Ctx) {
    let mut pkt: Option<(Vec<u8>, SocketAddr)> = None;
    let mut events: Vec<String> = Vec::new();
    let mut logs: Vec<String> = Vec::new();
    let (rate, samples) = {
        let mut g = ctx.st.lock().unwrap();
        let s = &mut *g;
        let connected = matches!(&s.call, Some(c) if c.state == CallState::Connected);
        // transmit: 160 samples (20 ms at 8 kHz) per tick once primed; a gap is counted, never filled
        if connected {
            let jit_tx = s.cfg.jitter_ms * 8.0;
            if !s.tx_primed && s.tx_out.len() as f64 >= jit_tx {
                s.tx_primed = true;
            }
            if s.tx_primed && s.tx_out.len() >= 160 {
                let chunk: Vec<f32> = s.tx_out.drain(..160).collect();
                let c16 = to_i16s(&chunk);
                if let Some(rec) = s.rec.as_mut() {
                    Rec::w(&mut rec.tx8k, &c16);
                }
                if let Some(remote) = s.call.as_ref().and_then(|c| c.remote) {
                    let mut p = Vec::with_capacity(172);
                    p.extend_from_slice(&[0x80, 0]);
                    p.extend_from_slice(&s.seq.to_be_bytes());
                    p.extend_from_slice(&s.ts.to_be_bytes());
                    p.extend_from_slice(&s.ssrc.to_be_bytes());
                    p.extend(c16.iter().map(|&v| dsp::ulaw_enc(v)));
                    pkt = Some((p, remote));
                    s.c.tx_pkts += 1;
                    s.seq = s.seq.wrapping_add(1);
                }
            } else if s.tx_primed {
                s.c.tx_gaps += 1;
                s.tx_primed = false; // re-prime to the prefill level before resuming
            }
            s.ts = s.ts.wrapping_add(160);
        } else if s.call.is_none() {
            s.tx_out.clear();
            s.tx_primed = false;
        }
        // receive: 20 ms at the codec rate of the moment per 20 ms of wall time; silence when nothing plays
        let n = (s.rate as f64 * 0.02).round() as usize;
        let mut fr: Option<Vec<f32>> = None;
        if connected {
            let target = s.rx_target_ms * 8.0;
            if !s.rx_primed && s.rxq.avail() >= target {
                s.rx_primed = true;
            }
            if s.rx_primed {
                let adj = ((s.rxq.avail() - target) / 400.0 * DRIFT_MAX).clamp(-DRIFT_MAX, DRIFT_MAX);
                fr = s.rxq.pull(n, s.rate as f64, adj);
                if fr.is_none() {
                    s.rx_primed = false;
                    s.c.rx_underruns += 1;
                    let old = s.rx_target_ms;
                    s.rx_target_ms = (s.rx_target_ms + RX_TARGET_STEP_MS).min(RX_TARGET_MAX_MS);
                    logs.push(format!("rx underrun: jitter target {:.0} -> {:.0} ms", old, s.rx_target_ms));
                }
            }
        }
        let samples = match fr {
            Some(v) => to_i16s(&v),
            None => vec![0; n],
        };
        s.c.rx_frames += 1;
        if let Some(rec) = s.rec.as_mut() {
            Rec::w(&mut rec.modem_in, &samples);
        }
        // call ended by the peer or by hangup: report once, forget the call
        if let Some(call) = s.call.as_ref() {
            if call.state == CallState::Ended {
                events.push(ev_call("ended", &call.end_reason));
                s.call = None;
                s.rec = None;
            }
        }
        let now = Instant::now();
        if now.duration_since(s.last_stat) >= Duration::from_secs(1) {
            s.last_stat = now;
            let c = &mut s.c;
            let dt = c.t_rep.map(|t| now.duration_since(t).as_secs_f64()).unwrap_or(1.0).max(1e-3);
            c.t_rep = Some(now);
            let tx_in = c.tx_in.max(1) as f64;
            let rx_n = c.rx_n.max(1) as f64;
            logs.push(format!(
                "flow modem->gw {:.0} samples/s rms {:.0} | rtp->gw {:.0} samples/s rms {:.0} (after gain) | gw->modem frames {}",
                c.tx_in as f64 / dt,
                (c.tx_sq / tx_in).sqrt(),
                c.rx_n as f64 / dt,
                (c.rx_sq / rx_n).sqrt(),
                c.rx_frames
            ));
            let call_state = s.call.as_ref().map_or("idle", |c| c.state.name());
            let tx_buf_ms = round1(out_len_ms(s.tx_out.len()));
            let rx_buf_ms = round1(s.rxq.avail() / 8.0);
            let c = &mut s.c;
            let st = format!(
                "{{\"type\": \"stat\", \"call\": \"{}\", \"rate\": {}, \"tx_buf_ms\": {:?}, \"rx_buf_ms\": {:?}, \"levels\": {{\"tx\": {:?}, \"rx\": {:?}}}, \"tx_gaps\": {}, \"tx_pkts\": {}, \"rx_pkts\": {}, \"rx_lost\": {}, \"rx_late\": {}, \"rx_underruns\": {}}}",
                call_state, s.rate, tx_buf_ms, rx_buf_ms, s.tx_gain, s.rx_gain, c.tx_gaps, c.tx_pkts, c.rx_pkts, c.rx_lost, c.rx_late, c.rx_underruns
            );
            logs.push(format!(
                "stat call={} rate={} tx_buf_ms={:?} rx_buf_ms={:?} tx_gaps={} rx_pkts={} rx_lost={} rx_late={} rx_underruns={}",
                call_state, s.rate, tx_buf_ms, rx_buf_ms, c.tx_gaps, c.rx_pkts, c.rx_lost, c.rx_late, c.rx_underruns
            ));
            c.tx_in = 0;
            c.tx_sq = 0.0;
            c.rx_n = 0;
            c.rx_sq = 0.0;
            c.rx_frames = 0;
            events.push(st);
        }
        (s.rate, samples)
    };
    if let Some((p, remote)) = pkt {
        let _ = ctx.rtp.send_to(&p, remote);
    }
    send_bin(ctx, rate, &samples);
    for e in events {
        send_text(ctx, &e);
    }
    for l in logs {
        log(&l);
    }
}

fn out_len_ms(n: usize) -> f64 {
    n as f64 * 1000.0 / 8000.0
}

fn round1(x: f64) -> f64 {
    (x * 10.0).round() / 10.0
}
