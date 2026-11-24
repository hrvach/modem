//! Rust port of tools/cline/gateway.py. std only.
//!
//! Modules: `ws` (SHA-1, base64, WebSocket framing), `json` (flat objects), `dsp` (resamplers, G.711),
//! `sip` (INVITE/ACK/BYE), `session` (the threads of one WebSocket client), `logfile`.
pub mod dsp;
pub mod json;
pub mod logfile;
pub mod session;
pub mod sip;
pub mod ws;
