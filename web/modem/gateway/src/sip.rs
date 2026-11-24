//! SIP caller: INVITE (retried), ACK, BYE, PCMU RTP. Message formats as tools/cline/gateway.py (sipcall.py).
use std::cell::Cell;
use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr, SocketAddr, UdpSocket};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

thread_local! {
    static RNG: Cell<u64> = const { Cell::new(0) };
}

/// Random 32-bit value (xorshift64, seeded from the clock per thread).
pub fn rnd32() -> u32 {
    RNG.with(|s| {
        let mut x = s.get();
        if x == 0 {
            let n = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(1);
            x = (n ^ (std::process::id() as u64) << 32) | 1;
        }
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        s.set(x);
        (x >> 16) as u32
    })
}

/// Destination address: "binmodem" (127.0.0.1, port from GW_BINMODEM_PORT) or "dmodem" (79.137.67.20:5060).
pub fn dest_addr(name: &str, binmodem_port: u16) -> Option<SocketAddr> {
    match name {
        "binmodem" => Some(SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), binmodem_port)),
        "dmodem" => Some(SocketAddr::new(IpAddr::V4(Ipv4Addr::new(79, 137, 67, 20)), 5060)),
        _ => None,
    }
}

/// Local address the OS would use toward `dest` (UDP connect, no packet sent).
pub fn local_ip(dest: SocketAddr) -> String {
    UdpSocket::bind("0.0.0.0:0")
        .and_then(|s| {
            s.connect(SocketAddr::new(dest.ip(), 9))?;
            s.local_addr()
        })
        .map(|a| a.ip().to_string())
        .unwrap_or_else(|_| "127.0.0.1".into())
}

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum CallState {
    Inviting,
    Connected,
    Ended,
}

impl CallState {
    pub fn name(self) -> &'static str {
        match self {
            CallState::Inviting => "inviting",
            CallState::Connected => "connected",
            CallState::Ended => "ended",
        }
    }
}

pub struct Call {
    pub dest: SocketAddr,
    pub number: String,
    pub lip: String,
    pub rport: u16,
    pub lport: u16,
    pub callid: String,
    pub tag: String,
    pub branch: String,
    pub cseq: u32,
    pub to_hdr: String,
    pub state: CallState,
    pub remote: Option<SocketAddr>,
    pub tries: u32,
    pub last_send: Instant,
    pub end_reason: String,
    msg: Vec<u8>,
}

/// Parsed headers of a SIP message (names lower-cased; the last occurrence wins, as gateway.py).
pub fn parse_sip(txt: &str) -> HashMap<String, String> {
    let head = txt.split("\r\n\r\n").next().unwrap_or("");
    let mut hdr = HashMap::new();
    for line in head.split("\r\n").skip(1) {
        if let Some((k, v)) = line.split_once(':') {
            hdr.insert(k.trim().to_ascii_lowercase(), v.trim().to_string());
        }
    }
    hdr
}

impl Call {
    pub fn new(dest: SocketAddr, number: &str, lip: String, rport: u16, lport: u16) -> Call {
        Call {
            dest,
            number: number.to_string(),
            lip,
            rport,
            lport,
            callid: format!("{:08x}@{}", rnd32(), ""),
            tag: format!("{:06x}", rnd32() & 0xFF_FFFF),
            branch: format!("z9hG4bK{:08x}", rnd32()),
            cseq: 1,
            to_hdr: String::new(),
            state: CallState::Inviting,
            remote: None,
            tries: 0,
            last_send: Instant::now(),
            end_reason: String::new(),
            msg: vec![],
        }
        .with_callid()
    }

    fn with_callid(mut self) -> Self {
        self.callid = format!("{:08x}@{}", rnd32(), self.lip);
        self
    }

    fn dh(&self) -> String {
        self.dest.ip().to_string()
    }

    fn via(&self, branch: &str) -> String {
        format!("SIP/2.0/UDP {}:{};branch={}", self.lip, self.lport, branch)
    }

    pub fn invite(&mut self, sip: &UdpSocket) {
        let sdp = format!(
            "v=0\r\no=gw 1 1 IN IP4 {ip}\r\ns=gw\r\nc=IN IP4 {ip}\r\nt=0 0\r\nm=audio {rp} RTP/AVP 0\r\na=rtpmap:0 PCMU/8000\r\na=ptime:20\r\na=sendrecv\r\n",
            ip = self.lip,
            rp = self.rport
        );
        let msg = format!(
            "INVITE sip:{n}@{dh} SIP/2.0\r\nVia: {via};rport\r\nMax-Forwards: 70\r\nFrom: <sip:gw@{ip}>;tag={tag}\r\nTo: <sip:{n}@{dh}>\r\nCall-ID: {cid}\r\nCSeq: {cseq} INVITE\r\nContact: <sip:gw@{ip}:{lp}>\r\nContent-Type: application/sdp\r\nContent-Length: {len}\r\n\r\n{sdp}",
            n = self.number,
            dh = self.dh(),
            via = self.via(&self.branch),
            ip = self.lip,
            tag = self.tag,
            cid = self.callid,
            cseq = self.cseq,
            lp = self.lport,
            len = sdp.len(),
            sdp = sdp
        );
        self.msg = msg.into_bytes();
        self.send(sip);
    }

    /// Sends (or re-sends) the INVITE.
    pub fn send(&mut self, sip: &UdpSocket) {
        let _ = sip.send_to(&self.msg, self.dest);
        self.last_send = Instant::now();
        self.tries += 1;
    }

    pub fn retry_due(&self) -> bool {
        self.state == CallState::Inviting && self.tries < 6 && self.last_send.elapsed() > Duration::from_secs(1)
    }

    fn send_ack(&self, sip: &UdpSocket) {
        let msg = format!(
            "ACK sip:{n}@{dh} SIP/2.0\r\nVia: {via};\r\nMax-Forwards: 70\r\nFrom: <sip:gw@{ip}>;tag={tag}\r\nTo: {to}\r\nCall-ID: {cid}\r\nCSeq: {cseq} ACK\r\nContent-Length: 0\r\n\r\n",
            n = self.number,
            dh = self.dh(),
            via = self.via(&format!("z9hG4bK{:08x}", rnd32())),
            ip = self.lip,
            tag = self.tag,
            to = self.to_hdr,
            cid = self.callid,
            cseq = self.cseq
        );
        let _ = sip.send_to(msg.as_bytes(), self.dest);
    }

    /// Handles one SIP message from the destination. Returns (state, message) for the page and the log.
    pub fn on_sip(&mut self, sip: &UdpSocket, txt: &str, hdr: &HashMap<String, String>) -> Option<(&'static str, String)> {
        let first = txt.split("\r\n").next().unwrap_or("").to_string();
        let g = |k: &str| hdr.get(k).cloned().unwrap_or_default();
        let cseq_invite = g("cseq").to_ascii_lowercase().contains("invite");
        if first.starts_with("SIP/2.0 1") {
            return Some(("ringing", first));
        }
        if first.starts_with("SIP/2.0 200") && cseq_invite {
            if self.state == CallState::Connected {
                self.send_ack(sip); // retransmitted 200
                return None;
            }
            self.to_hdr = g("to");
            let body = txt.split_once("\r\n\r\n").map(|x| x.1).unwrap_or("");
            let mut ip: Option<String> = None;
            let mut port: Option<u16> = None;
            for l in body.split("\r\n") {
                if let Some(rest) = l.strip_prefix("c=IN IP4 ") {
                    ip = rest.split_whitespace().last().map(|s| s.to_string());
                }
                if let Some(rest) = l.strip_prefix("m=audio ") {
                    port = rest.split_whitespace().next().and_then(|p| p.parse().ok());
                }
            }
            let remote_ip = ip.and_then(|s| s.parse::<IpAddr>().ok()).unwrap_or(self.dest.ip());
            let remote = SocketAddr::new(remote_ip, port.unwrap_or(10000));
            self.remote = Some(remote);
            self.state = CallState::Connected;
            self.send_ack(sip);
            return Some(("connected", format!("RTP -> {remote}")));
        }
        if first.starts_with("BYE") {
            let resp = format!(
                "SIP/2.0 200 OK\r\nVia: {}\r\nFrom: {}\r\nTo: {}\r\nCall-ID: {}\r\nCSeq: {}\r\nContent-Length: 0\r\n\r\n",
                g("via"),
                g("from"),
                g("to"),
                self.callid,
                g("cseq")
            );
            let _ = sip.send_to(resp.as_bytes(), self.dest);
            self.state = CallState::Ended;
            self.end_reason = "peer sent BYE".into();
            return Some(("ended", self.end_reason.clone()));
        }
        let is_err = ["SIP/2.0 3", "SIP/2.0 4", "SIP/2.0 5", "SIP/2.0 6"].iter().any(|p| first.starts_with(p));
        if is_err && cseq_invite {
            let msg = format!(
                "ACK sip:{n}@{dh} SIP/2.0\r\nVia: {via}\r\nFrom: <sip:gw@{ip}>;tag={tag}\r\nTo: {to}\r\nCall-ID: {cid}\r\nCSeq: {cseq} ACK\r\nContent-Length: 0\r\n\r\n",
                n = self.number,
                dh = self.dh(),
                via = self.via(&format!("z9hG4bK{:08x}", rnd32())),
                ip = self.lip,
                tag = self.tag,
                to = g("to"),
                cid = self.callid,
                cseq = self.cseq
            );
            let _ = sip.send_to(msg.as_bytes(), self.dest);
            self.state = CallState::Ended;
            self.end_reason = format!("failed: {first}");
            return Some(("ended", self.end_reason.clone()));
        }
        None
    }

    pub fn bye(&mut self, sip: &UdpSocket) {
        if self.state == CallState::Connected {
            self.cseq += 1;
            let msg = format!(
                "BYE sip:{n}@{dh} SIP/2.0\r\nVia: {via}\r\nMax-Forwards: 70\r\nFrom: <sip:gw@{ip}>;tag={tag}\r\nTo: {to}\r\nCall-ID: {cid}\r\nCSeq: {cseq} BYE\r\nContent-Length: 0\r\n\r\n",
                n = self.number,
                dh = self.dh(),
                via = self.via(&format!("z9hG4bK{:08x}", rnd32())),
                ip = self.lip,
                tag = self.tag,
                to = self.to_hdr,
                cid = self.callid,
                cseq = self.cseq
            );
            let _ = sip.send_to(msg.as_bytes(), self.dest);
        }
        self.state = CallState::Ended;
        if self.end_reason.is_empty() {
            self.end_reason = "hung up".into();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_headers() {
        let h = parse_sip("BYE sip:x SIP/2.0\r\nVia: a\r\nFROM: <b>;tag=1\r\nCSeq: 2 BYE\r\n\r\nbody");
        assert_eq!(h.get("from").map(String::as_str), Some("<b>;tag=1"));
        assert_eq!(h.get("cseq").map(String::as_str), Some("2 BYE"));
    }

    #[test]
    fn rnd_varies() {
        let a: Vec<u32> = (0..8).map(|_| rnd32()).collect();
        assert!(a.windows(2).any(|w| w[0] != w[1]));
    }
}
