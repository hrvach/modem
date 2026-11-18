use modem::{Modem, State};
use std::io::{Read, Write};

fn selftest(fs: f64, carrier: &str) {
    let mut caller = Modem::new(fs);
    let mut host = Modem::new(fs);
    for m in [&mut caller, &mut host] {
        for b in format!("AT+MS={carrier}\r").bytes() { m.feed_dte(b); }
        m.take_dte();
    }
    for b in b"ATA\r" { host.feed_dte(*b); }
    for b in b"ATD5551234\r" { caller.feed_dte(*b); }
    let (mut a, mut b) = (0.0, 0.0);
    let mut up_at = None;
    for i in 0..(40.0 * fs) as usize {
        let (x, y) = (a, b);
        a = caller.step(y);
        b = host.step(x);
        caller.take_dte(); host.take_dte();
        if up_at.is_none() && caller.state() == State::Data && host.state() == State::Data { up_at = Some(i as f64 / fs); }
    }
    println!("fs {fs} {carrier}: up_at {:?} rate {:?} mod {}", up_at, caller.rate(), caller.modulation());
}

/// Streaming windowed-sinc (Lanczos) resampler, arbitrary ratio.
struct Rs { step: f64, scale: f64, a: f64, pos: f64, buf: Vec<f64>, base: usize }
impl Rs {
    fn new(fin: f64, fout: f64) -> Self {
        Rs { step: fin / fout, scale: (fout / fin).min(1.0), a: 12.0, pos: 0.0, buf: vec![0.0; 40], base: 0 }
    }
    fn lz(&self, x: f64) -> f64 {
        let u = x * self.scale; let a = self.a;
        if u.abs() >= a { return 0.0; }
        let sinc = |t: f64| if t.abs() < 1e-12 { 1.0 } else { (std::f64::consts::PI * t).sin() / (std::f64::consts::PI * t) };
        self.scale * sinc(u) * sinc(u / a)
    }
    fn push(&mut self, x: f64) { self.buf.push(x); }
    fn pull(&mut self, out: &mut Vec<f64>) {
        let reach = (self.a / self.scale).ceil() as usize + 1;
        while (self.pos as usize) + reach < self.buf.len() {
            let c = self.pos; let lo = (c as usize).saturating_sub(reach); let hi = (c as usize) + reach;
            let (mut acc, mut w) = (0.0, 0.0);
            for k in lo..=hi { let wk = self.lz(c - k as f64); acc += self.buf[k] * wk; w += wk; }
            out.push(if w.abs() > 1e-9 { acc / w } else { 0.0 });
            self.pos += self.step;
        }
        let drop = (self.pos as usize).saturating_sub(reach + 2);
        if drop > 4096 { self.buf.drain(..drop); self.pos -= drop as f64; }
    }
}

fn rd(r: &mut impl Read, n: usize) -> Option<Vec<u8>> {
    let mut v = vec![0u8; n];
    r.read_exact(&mut v).ok()?;
    Some(v)
}

/// Lockstep peer. Frame in:  u32 n, u32 d, u32 line_rate, n x f32 line-in, d DTE bytes.
/// Frame out: u32 n, u32 d, n x f32 line-out, d DTE bytes.
fn serve(line_fs: f64, init: &[String]) {
    const MFS: f64 = 9600.0;
    const SCALE: f64 = 16384.0; // line DRR units per modem full-scale (input side)
    // BinModem's output scale in line units per modem full scale. 3000 and 5000 both get the emulated
    // caller through phase 3; at 7000 (and 16384) its receiver stops recognising J. About 5000 rms
    // either way, which is also the emulated modem's own training level, so the two are comparable.
    let out_scale: f64 = std::env::var("BM_OUTSCALE").ok().and_then(|v| v.parse().ok()).unwrap_or(5000.0);
    let mut m = Modem::new(MFS);
    for cmd in init { for b in cmd.bytes() { m.feed_dte(b); } m.feed_dte(b'\r'); }
    m.take_dte();
    let mut line_fs = line_fs;
    let (mut rin, mut rout) = (Rs::new(line_fs, MFS), Rs::new(MFS, line_fs));
    let mut fifo: std::collections::VecDeque<f64> = std::collections::VecDeque::new();
    let (mut stdin, mut stdout) = (std::io::stdin().lock(), std::io::stdout().lock());
    let mut last_state = String::new();
    let mut total_s: f64 = 0.0;
    let mut tmp = Vec::new();
    loop {
        let Some(h) = rd(&mut stdin, 12) else { break };
        let n = u32::from_le_bytes(h[0..4].try_into().unwrap()) as usize;
        let d = u32::from_le_bytes(h[4..8].try_into().unwrap()) as usize;
        let rate = u32::from_le_bytes(h[8..12].try_into().unwrap()) as f64;
        if rate > 0.0 && rate != line_fs {
            eprintln!("[binmodem {:7.3}s] line rate {line_fs} -> {rate}", total_s);
            line_fs = rate; rin = Rs::new(line_fs, MFS); rout = Rs::new(MFS, line_fs); fifo.clear();
        }
        let sb = rd(&mut stdin, n * 4).unwrap();
        let db = rd(&mut stdin, d).unwrap();
        for b in db { m.feed_dte(b); }
        for i in 0..n { rin.push(f32::from_le_bytes(sb[i * 4..i * 4 + 4].try_into().unwrap()) as f64 / SCALE); }
        tmp.clear(); rin.pull(&mut tmp);
        let mut mo = Vec::with_capacity(tmp.len());
        for &x in &tmp { let y = m.step(x); mo.push(y); }
        for y in mo { rout.push(y); }
        tmp.clear(); rout.pull(&mut tmp);
        fifo.extend(tmp.iter().copied());
        let mut out = Vec::with_capacity(n * 4);
        for _ in 0..n { out.extend_from_slice(&((fifo.pop_front().unwrap_or(0.0) * out_scale) as f32).to_le_bytes()); }
        let dte = m.take_dte();
        total_s += n as f64 / line_fs;
        let st = format!("{:?} {} {:?} phase={} p2={:?}", m.state(), m.modulation(), m.rate(), m.line_phase(), m.phase2_stage());
        let t = total_s;
        if st != last_state { eprintln!("[binmodem {t:7.3}s] {st}"); last_state = st; }
        for note in m.take_line_notes() { eprintln!("[binmodem {t:7.3}s]   note: {note}"); }
        stdout.write_all(&(n as u32).to_le_bytes()).unwrap();
        stdout.write_all(&(dte.len() as u32).to_le_bytes()).unwrap();
        stdout.write_all(&out).unwrap();
        stdout.write_all(&dte).unwrap();
        stdout.flush().unwrap();
    }
}

/// Replay a raw s16le mono recording into a fresh answering modem.
/// replay <raw> <rate> <start_s> <gain> : gain is modem units per sample unit (live run used 0.5/16384).
fn replay(path: &str, rate: f64, start: f64, gain: f64) {
    let data = std::fs::read(path).unwrap();
    let pcm: Vec<f64> = data.chunks_exact(2).map(|c| i16::from_le_bytes([c[0], c[1]]) as f64).collect();
    let mut m = Modem::new(9600.0);
    for cmd in ["AT+MS=V34", "ATA"] { for b in cmd.bytes() { m.feed_dte(b); } m.feed_dte(b'\r'); }
    m.take_dte();
    let mut rs = Rs::new(rate, 9600.0);
    let from = (start * rate) as usize;
    for &x in &pcm[from..] { rs.push(x * gain); }
    let mut samples = Vec::new(); rs.pull(&mut samples);
    let mut last = String::new();
    for (i, &x) in samples.iter().enumerate() {
        m.step(x);
        let st = format!("{:?} phase={} p2={:?}", m.state(), m.line_phase(), m.phase2_stage());
        if st != last { eprintln!("  [{:7.3}s] {st}", i as f64 / 9600.0); last = st; }
        for note in m.take_line_notes() { eprintln!("  [{:7.3}s]   note: {note}", i as f64 / 9600.0); }
        if i as f64 / 9600.0 > 20.0 { break; }
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("selftest") => {
            let carrier = args.get(1).cloned().unwrap_or("V34".into());
            for fs in args[2..].iter().map(|s| s.parse::<f64>().unwrap()) { selftest(fs, &carrier); }
        }
        Some("replay") => replay(&args[1], args[2].parse().unwrap(), args[3].parse().unwrap(), args[4].parse().unwrap()),
        Some("serve") => {
            let fs: f64 = args[1].parse().unwrap();
            serve(fs, &args[2..]);
        }
        _ => eprintln!("bridge selftest <carrier> <fs>... | bridge serve <fs> [AT cmd]..."),
    }
}
