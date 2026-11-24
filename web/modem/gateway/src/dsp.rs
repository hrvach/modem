//! Sample-rate conversion and G.711 mu-law.
//!
//! Both resamplers use a 64-tap (H = 32 each side) Hann-windowed sinc. The kernel is precomputed for 256 phases
//! (257 rows, the last one for interpolation) per cutoff and cached; a tap row is linearly interpolated between
//! the two nearest phases, so the per-sample cost is 64 multiply-adds.
use std::collections::HashMap;
use std::f64::consts::PI;
use std::sync::{Arc, Mutex, OnceLock};

pub const H: usize = 32;
pub const TAPS: usize = 2 * H;
pub const PHASES: usize = 256;
/// Largest drift trim of a resampler ratio (0.03 %), as gateway.py.
pub const DRIFT_MAX: f64 = 0.0003;

fn sinc(x: f64) -> f64 {
    if x.abs() < 1e-12 {
        1.0
    } else {
        (PI * x).sin() / (PI * x)
    }
}

/// Kernel rows for `cut` (cycles per input sample, 0.485 = 97 % of Nyquist). Row p is the weight of tap j at
/// fractional position p/PHASES; each row sums to 1.
fn build(cut: f64) -> Vec<f32> {
    let mut w = vec![0f32; (PHASES + 1) * TAPS];
    for p in 0..=PHASES {
        let frac = p as f64 / PHASES as f64;
        let mut row = [0f64; TAPS];
        let mut sum = 0.0;
        for (j, r) in row.iter_mut().enumerate() {
            let off = j as f64 - (H as f64 - 1.0);
            let u = frac - off;
            let v = 2.0 * cut * sinc(2.0 * cut * u) * (0.5 + 0.5 * (PI * u / H as f64).cos());
            *r = v;
            sum += v;
        }
        for j in 0..TAPS {
            w[p * TAPS + j] = (row[j] / sum) as f32;
        }
    }
    w
}

static CACHE: OnceLock<Mutex<HashMap<u64, Arc<Vec<f32>>>>> = OnceLock::new();

/// Kernel table for a cutoff, built once and shared.
pub fn table(cut: f64) -> Arc<Vec<f32>> {
    let key = (cut * 1e9).round() as u64;
    let m = CACHE.get_or_init(|| Mutex::new(HashMap::new()));
    let mut g = m.lock().unwrap();
    g.entry(key).or_insert_with(|| Arc::new(build(cut))).clone()
}

/// Interpolated tap weights at fractional position `frac` in [0, 1).
fn weights(t: &[f32], frac: f64, out: &mut [f32; TAPS]) {
    let pos = frac.clamp(0.0, 1.0) * PHASES as f64;
    let p = (pos.floor() as usize).min(PHASES - 1);
    let a = (pos - p as f64) as f32;
    for j in 0..TAPS {
        out[j] = t[p * TAPS + j] * (1.0 - a) + t[(p + 1) * TAPS + j] * a;
    }
}

/// Transmit side: modem codec rate -> 8 kHz on one continuous timeline. Every input sample carries its own time
/// (cumulative 1/rate), so a rate change moves no phase. Outputs are taken at k*(1+adj)/out_rate. No flush, no zeros.
pub struct Resampler {
    buf: Vec<f32>,
    t: Vec<f64>,
    r: Vec<f64>,
    tend: f64,
    tnext: f64,
    started: bool,
    cut_key: f64,
    tab: Option<Arc<Vec<f32>>>,
}

impl Default for Resampler {
    fn default() -> Self {
        Self::new()
    }
}

impl Resampler {
    pub fn new() -> Self {
        Resampler { buf: vec![], t: vec![], r: vec![], tend: 0.0, tnext: 0.0, started: false, cut_key: -1.0, tab: None }
    }

    /// `x` at `in_rate` (Hz). Returns the output samples now available at `out_rate`.
    pub fn process(&mut self, x: &[f32], in_rate: f64, out_rate: f64, adj: f64) -> Vec<f32> {
        if !self.started {
            // H zeros of history before t = 0
            self.started = true;
            self.buf = vec![0.0; H];
            self.t = (0..H).map(|k| -((H - k) as f64) / in_rate).collect();
            self.r = vec![in_rate; H];
        }
        for (k, &s) in x.iter().enumerate() {
            self.buf.push(s);
            self.t.push(self.tend + k as f64 / in_rate);
            self.r.push(in_rate);
        }
        self.tend += x.len() as f64 / in_rate;
        let spacing = (1.0 + adj) / out_rate;
        let last = self.tend - (H as f64 + 1.0) / in_rate;
        let mut out = Vec::new();
        let mut wrow = [0f32; TAPS];
        while self.tnext <= last {
            let tau = self.tnext;
            let i0 = self.t.partition_point(|&t| t <= tau) - 1;
            let r0 = self.r[i0];
            let cut = 0.485 * (out_rate / r0).min(1.0);
            if self.tab.is_none() || cut != self.cut_key {
                self.tab = Some(table(cut));
                self.cut_key = cut;
            }
            let frac = (tau - self.t[i0]) * r0;
            weights(self.tab.as_ref().unwrap(), frac, &mut wrow);
            let mut acc = 0f32;
            for (j, w) in wrow.iter().enumerate() {
                let idx = i0 as isize + j as isize - (H as isize - 1);
                if idx >= 0 && (idx as usize) < self.buf.len() {
                    acc += self.buf[idx as usize] * w;
                }
            }
            out.push(acc);
            self.tnext += spacing;
        }
        // drop history no future output can reach
        let k = self.t.partition_point(|&t| t <= self.tnext) as isize - H as isize - 2;
        if k > 0 {
            let k = k as usize;
            self.buf.drain(..k);
            self.t.drain(..k);
            self.r.drain(..k);
        }
        out
    }
}

/// Receive side: an 8 kHz queue read on demand at the codec's rate of the moment. `pull` returns None when the
/// queue cannot cover the request (an underrun, the caller re-primes).
pub struct Puller {
    buf: Vec<f32>,
    pos: f64,
    cut_key: f64,
    tab: Option<Arc<Vec<f32>>>,
}

impl Default for Puller {
    fn default() -> Self {
        Self::new()
    }
}

impl Puller {
    pub fn new() -> Self {
        Puller { buf: vec![0.0; TAPS], pos: H as f64, cut_key: -1.0, tab: None }
    }

    pub fn push(&mut self, x: &[f32]) {
        self.buf.extend_from_slice(x);
    }

    /// 8 kHz samples queued beyond the read position.
    pub fn avail(&self) -> f64 {
        self.buf.len() as f64 - self.pos - H as f64
    }

    pub fn pull(&mut self, n: usize, rate: f64, adj: f64) -> Option<Vec<f32>> {
        let step = 8000.0 / rate * (1.0 + adj);
        if self.avail() < n as f64 * step + 1.0 {
            return None;
        }
        let cut = 0.485 * (rate / 8000.0).min(1.0);
        if self.tab.is_none() || cut != self.cut_key {
            self.tab = Some(table(cut));
            self.cut_key = cut;
        }
        let tab = self.tab.clone().unwrap();
        let mut out = Vec::with_capacity(n);
        let mut wrow = [0f32; TAPS];
        for k in 0..n {
            let p = self.pos + k as f64 * step;
            let i = p.floor();
            weights(&tab, p - i, &mut wrow);
            let i = i as isize;
            let mut acc = 0f32;
            for (j, w) in wrow.iter().enumerate() {
                acc += self.buf[(i + j as isize - (H as isize - 1)) as usize] * w;
            }
            out.push(acc);
        }
        self.pos += n as f64 * step;
        let k = self.pos.floor() as isize - 2 * H as isize;
        if k > 800 {
            let k = k as usize;
            self.buf.drain(..k);
            self.pos -= k as f64;
        }
        Some(out)
    }
}

/// G.711 mu-law decode (as gateway.py).
pub fn ulaw_dec(c: u8) -> i16 {
    let u = !c as i32;
    let mut t = ((u & 0x0F) << 3) + 0x84;
    t <<= (u & 0x70) >> 4;
    if u & 0x80 != 0 {
        (0x84 - t) as i16
    } else {
        (t - 0x84) as i16
    }
}

/// G.711 mu-law encode (as gateway.py: bias 0x84, clip 32635).
pub fn ulaw_enc(s: i16) -> u8 {
    let x0 = s as i32;
    let sign = if x0 < 0 { 0x80 } else { 0 };
    let x = x0.abs().min(32635) + 0x84;
    let e = (31 - (x.max(1) as u32).leading_zeros() as i32 - 7).clamp(0, 7);
    let m = (x >> (e + 3)) & 0x0F;
    (!(sign | (e << 4) | m)) as u8
}

/// Float sample to i16 with round and clip (np.clip(np.round(x))).
pub fn to_i16(x: f32) -> i16 {
    x.round().clamp(-32768.0, 32767.0) as i16
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ulaw_roundtrip() {
        // every code word survives decode/encode, except the second zero 0x7F, which encodes as 0xFF
        for c in 0..=255u8 {
            let v = ulaw_dec(c);
            let back = ulaw_enc(v);
            if c == 0x7F {
                assert_eq!((v, back), (0, 0xFF));
            } else {
                assert_eq!(back, c, "code {c:#04x} decodes to {v}");
            }
        }
        // encode/decode error stays within the segment step
        for s in (-32768i32..32768).step_by(7) {
            let s = s.clamp(-32768, 32767) as i16;
            let e = (ulaw_dec(ulaw_enc(s)) as i32 - s as i32).abs();
            let limit = (s as i32).abs().max(256) / 16 + 8;
            assert!(e <= limit.min(1100), "sample {s} error {e}");
        }
        assert_eq!(ulaw_dec(0xFF), 0);
        assert_eq!(ulaw_enc(0), 0xFF);
    }

    #[test]
    fn kernel_rows_sum_to_one() {
        let t = table(0.485);
        for p in 0..=PHASES {
            let s: f32 = t[p * TAPS..(p + 1) * TAPS].iter().sum();
            assert!((s - 1.0).abs() < 1e-4);
        }
    }
}
