//! SHA-1, base64 and WebSocket (RFC 6455) framing, std only.
use std::collections::HashMap;

pub const WS_GUID: &str = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

pub fn sha1(data: &[u8]) -> [u8; 20] {
    let mut h: [u32; 5] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0];
    let mut msg = data.to_vec();
    let bit_len = (data.len() as u64).wrapping_mul(8);
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());
    for chunk in msg.chunks(64) {
        let mut w = [0u32; 80];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([chunk[4 * i], chunk[4 * i + 1], chunk[4 * i + 2], chunk[4 * i + 3]]);
        }
        for i in 16..80 {
            w[i] = (w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]).rotate_left(1);
        }
        let (mut a, mut b, mut c, mut d, mut e) = (h[0], h[1], h[2], h[3], h[4]);
        for (i, wi) in w.iter().enumerate() {
            let (f, k) = match i {
                0..=19 => ((b & c) | (!b & d), 0x5A82_7999u32),
                20..=39 => (b ^ c ^ d, 0x6ED9_EBA1),
                40..=59 => ((b & c) | (b & d) | (c & d), 0x8F1B_BCDC),
                _ => (b ^ c ^ d, 0xCA62_C1D6),
            };
            let t = a.rotate_left(5).wrapping_add(f).wrapping_add(e).wrapping_add(k).wrapping_add(*wi);
            e = d;
            d = c;
            c = b.rotate_left(30);
            b = a;
            a = t;
        }
        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
    }
    let mut out = [0u8; 20];
    for i in 0..5 {
        out[4 * i..4 * i + 4].copy_from_slice(&h[i].to_be_bytes());
    }
    out
}

pub fn b64(data: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for c in data.chunks(3) {
        let b1 = *c.get(1).unwrap_or(&0) as u32;
        let b2 = *c.get(2).unwrap_or(&0) as u32;
        let n = (c[0] as u32) << 16 | b1 << 8 | b2;
        out.push(T[(n >> 18) as usize & 63] as char);
        out.push(T[(n >> 12) as usize & 63] as char);
        out.push(if c.len() > 1 { T[(n >> 6) as usize & 63] as char } else { '=' });
        out.push(if c.len() > 2 { T[n as usize & 63] as char } else { '=' });
    }
    out
}

/// Sec-WebSocket-Accept for a Sec-WebSocket-Key.
pub fn accept_key(key: &str) -> String {
    b64(&sha1(format!("{key}{WS_GUID}").as_bytes()))
}

/// The 101 response for a client key.
pub fn response_101(key: &str) -> String {
    format!(
        "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {}\r\n\r\n",
        accept_key(key)
    )
}

/// Server frame (unmasked), FIN set.
pub fn frame(opcode: u8, payload: &[u8]) -> Vec<u8> {
    let n = payload.len();
    let mut h = vec![0x80 | opcode];
    if n < 126 {
        h.push(n as u8);
    } else if n < 65536 {
        h.push(126);
        h.extend_from_slice(&(n as u16).to_be_bytes());
    } else {
        h.push(127);
        h.extend_from_slice(&(n as u64).to_be_bytes());
    }
    h.extend_from_slice(payload);
    h
}

/// Client frame (masked with `key`), as a browser sends it. Used by tests and peers.
pub fn client_frame(opcode: u8, payload: &[u8], key: [u8; 4]) -> Vec<u8> {
    let n = payload.len();
    let mut h = vec![0x80 | opcode];
    if n < 126 {
        h.push(0x80 | n as u8);
    } else if n < 65536 {
        h.push(0x80 | 126);
        h.extend_from_slice(&(n as u16).to_be_bytes());
    } else {
        h.push(0x80 | 127);
        h.extend_from_slice(&(n as u64).to_be_bytes());
    }
    h.extend_from_slice(&key);
    h.extend(payload.iter().enumerate().map(|(i, b)| b ^ key[i % 4]));
    h
}

/// Header lines after the request line, lower-cased names.
pub fn parse_headers(head: &str) -> HashMap<String, String> {
    let mut hdr = HashMap::new();
    for line in head.split("\r\n").skip(1) {
        if let Some((k, v)) = line.split_once(':') {
            hdr.insert(k.trim().to_ascii_lowercase(), v.trim().to_string());
        }
    }
    hdr
}

/// Origin check as gateway.py: localhost, 127.0.0.1 (http or https, any port) and the listen host.
pub fn origin_ok(origin: &str, host: &str) -> bool {
    let allowed = [
        "http://localhost".to_string(),
        "http://127.0.0.1".to_string(),
        "https://localhost".to_string(),
        "https://127.0.0.1".to_string(),
        format!("http://{host}"),
        format!("https://{host}"),
    ];
    allowed.iter().any(|o| origin == o || origin.starts_with(&format!("{o}:")))
}

#[derive(Debug, PartialEq)]
pub enum Msg {
    Text(Vec<u8>),
    Binary(Vec<u8>),
    Ping(Vec<u8>),
    Close,
}

/// Incremental parser of client frames. Feed any byte split; `next` yields complete messages.
#[derive(Default)]
pub struct Parser {
    buf: Vec<u8>,
    start: usize,
}

/// Largest payload accepted from a client (the page sends 10 ms blocks, far below this).
pub const MAX_PAYLOAD: usize = 1 << 20;

impl Parser {
    pub fn feed(&mut self, data: &[u8]) {
        self.buf.extend_from_slice(data);
    }

    /// The next complete Text/Binary/Ping/Close message, or None when more bytes are needed.
    /// Other opcodes (continuation, pong) are skipped, as gateway.py does.
    pub fn next(&mut self) -> Option<Msg> {
        loop {
            let b = &self.buf[self.start..];
            if b.len() < 2 {
                return self.compact_none();
            }
            let op = b[0] & 0x0F;
            let masked = b[1] & 0x80 != 0;
            let mut n = (b[1] & 0x7F) as usize;
            let mut p = 2;
            if n == 126 {
                if b.len() < 4 {
                    return self.compact_none();
                }
                n = u16::from_be_bytes([b[2], b[3]]) as usize;
                p = 4;
            } else if n == 127 {
                if b.len() < 10 {
                    return self.compact_none();
                }
                let mut q = [0u8; 8];
                q.copy_from_slice(&b[2..10]);
                n = u64::from_be_bytes(q) as usize;
                p = 10;
            }
            if n > MAX_PAYLOAD {
                self.start = self.buf.len();
                return Some(Msg::Close);
            }
            let mut key = [0u8; 4];
            if masked {
                if b.len() < p + 4 {
                    return self.compact_none();
                }
                key.copy_from_slice(&b[p..p + 4]);
                p += 4;
            }
            if b.len() < p + n {
                return self.compact_none();
            }
            let mut payload = b[p..p + n].to_vec();
            if masked {
                for (i, x) in payload.iter_mut().enumerate() {
                    *x ^= key[i % 4];
                }
            }
            self.start += p + n;
            match op {
                0x1 => return Some(Msg::Text(payload)),
                0x2 => return Some(Msg::Binary(payload)),
                0x8 => return Some(Msg::Close),
                0x9 => return Some(Msg::Ping(payload)),
                _ => continue,
            }
        }
    }

    fn compact_none(&mut self) -> Option<Msg> {
        if self.start > 0 {
            self.buf.drain(..self.start);
            self.start = 0;
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha1_vectors() {
        let hex = |d: [u8; 20]| d.iter().map(|b| format!("{b:02x}")).collect::<String>();
        assert_eq!(hex(sha1(b"")), "da39a3ee5e6b4b0d3255bfef95601890afd80709");
        assert_eq!(hex(sha1(b"abc")), "a9993e364706816aba3e25717850c26c9cd0d89d");
        assert_eq!(
            hex(sha1(b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")),
            "84983e441c3bd26ebaae4aa1f95129e5e54670f1"
        );
        assert_eq!(hex(sha1(&vec![b'a'; 1000])), "291e9a6c66994949b57ba5e650361e98fc36b1ba");
    }

    #[test]
    fn base64_vectors() {
        assert_eq!(b64(b""), "");
        assert_eq!(b64(b"f"), "Zg==");
        assert_eq!(b64(b"fo"), "Zm8=");
        assert_eq!(b64(b"foo"), "Zm9v");
        assert_eq!(b64(b"foobar"), "Zm9vYmFy");
        assert_eq!(b64(b"M"), "TQ==");
        assert_eq!(b64(b"Ma"), "TWE=");
        assert_eq!(b64(b"Man"), "TWFu");
        assert_eq!(b64(&[0xFF, 0xFE, 0x00]), "//4A");
    }

    #[test]
    fn websocket_handshake_vector() {
        // RFC 6455 section 1.3
        assert_eq!(accept_key("dGhlIHNhbXBsZSBub25jZQ=="), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=");
        assert!(response_101("dGhlIHNhbXBsZSBub25jZQ==").contains("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n"));
    }

    #[test]
    fn origin_rules() {
        assert!(origin_ok("http://localhost", "127.0.0.1"));
        assert!(origin_ok("http://localhost:8080", "127.0.0.1"));
        assert!(origin_ok("http://127.0.0.1:5173", "127.0.0.1"));
        assert!(origin_ok("https://localhost", "127.0.0.1"));
        assert!(origin_ok("http://192.168.88.250:8000", "192.168.88.250"));
        assert!(!origin_ok("http://evil.example", "127.0.0.1"));
        assert!(!origin_ok("http://localhost.evil.example", "127.0.0.1"));
        assert!(!origin_ok("http://192.168.88.250", "127.0.0.1"));
    }

    #[test]
    fn frames_fragmented_tcp_reads() {
        let key = [1u8, 2, 3, 4];
        let mut wire = Vec::new();
        let mut want = Vec::new();
        for i in 0..300usize {
            let n = [0usize, 1, 125, 126, 127, 300, 65535, 65536, 3000][i % 9];
            let payload: Vec<u8> = (0..n).map(|k| (k * 7 + i) as u8).collect();
            let op = if i % 5 == 0 { 0x1 } else { 0x2 };
            wire.extend(client_frame(op, &payload, key));
            want.push(if op == 0x1 { Msg::Text(payload) } else { Msg::Binary(payload) });
        }
        wire.extend(client_frame(0x9, b"hi", key));
        wire.extend(client_frame(0x8, b"", key));
        want.push(Msg::Ping(b"hi".to_vec()));
        want.push(Msg::Close);
        // byte by byte
        let mut p = Parser::default();
        let mut got = Vec::new();
        for b in &wire {
            p.feed(std::slice::from_ref(b));
            while let Some(m) = p.next() {
                got.push(m);
            }
        }
        assert_eq!(got, want);
        // irregular chunks
        let mut p = Parser::default();
        let mut got = Vec::new();
        let mut i = 0;
        let mut step = 1;
        while i < wire.len() {
            let e = (i + step).min(wire.len());
            p.feed(&wire[i..e]);
            i = e;
            step = step * 3 % 101 + 1;
            while let Some(m) = p.next() {
                got.push(m);
            }
        }
        assert_eq!(got, want);
    }

    #[test]
    fn thousand_tiny_messages() {
        let key = [9u8, 8, 7, 6];
        let mut wire = Vec::new();
        for i in 0..1000u32 {
            wire.extend(client_frame(0x2, &(i as u16).to_le_bytes(), key));
        }
        // all in one read, then in 7-byte reads
        let mut p = Parser::default();
        p.feed(&wire);
        let mut n = 0u32;
        while let Some(m) = p.next() {
            assert_eq!(m, Msg::Binary((n as u16).to_le_bytes().to_vec()));
            n += 1;
        }
        assert_eq!(n, 1000);
        let mut p = Parser::default();
        let mut n = 0u32;
        for c in wire.chunks(7) {
            p.feed(c);
            while let Some(m) = p.next() {
                assert_eq!(m, Msg::Binary((n as u16).to_le_bytes().to_vec()));
                n += 1;
            }
        }
        assert_eq!(n, 1000);
    }

    #[test]
    fn server_frame_lengths() {
        assert_eq!(frame(0x1, b"abc"), [0x81, 3, b'a', b'b', b'c']);
        assert_eq!(frame(0x2, &vec![0u8; 130])[..4], [0x82, 126, 0, 130]);
        assert_eq!(frame(0x2, &vec![0u8; 70000])[..10], [0x82, 127, 0, 0, 0, 0, 0, 1, 0x11, 0x70]);
    }
}
