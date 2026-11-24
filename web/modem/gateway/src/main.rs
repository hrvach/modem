//! gateway: one modem in the browser (the wasm page's SIP tab) as a SIP caller. Rust port of gateway.py.
//!
//!   gateway [--host 127.0.0.1] [--port 8777] [--log DIR] [--tx-gain 0.5] [--rx-gain 0.5] [--jitter-ms 150]
//!
//! Environment: GW_BINMODEM_PORT (default 5060; test override only).
use courier_gw::logfile;
use courier_gw::session::{self, Cfg};
use std::env;
use std::fs;
use std::net::TcpListener;
use std::path::PathBuf;
use std::process::exit;

fn usage() -> ! {
    eprintln!("usage: gateway [--host H] [--port P] [--log DIR] [--tx-gain G] [--rx-gain G] [--jitter-ms MS]");
    exit(2)
}

fn main() {
    let mut host = "127.0.0.1".to_string();
    let mut port: u16 = 8777;
    let mut log_dir: Option<PathBuf> = None;
    let mut tx_gain = 0.5f64;
    let mut rx_gain = 0.5f64;
    let mut jitter_ms = 150.0f64;
    let args: Vec<String> = env::args().skip(1).collect();
    let mut i = 0;
    while i < args.len() {
        let val = || args.get(i + 1).cloned().unwrap_or_else(|| usage());
        match args[i].as_str() {
            "--host" => host = val(),
            "--port" => port = val().parse().unwrap_or_else(|_| usage()),
            "--log" => log_dir = Some(PathBuf::from(val())),
            "--tx-gain" => tx_gain = val().parse().unwrap_or_else(|_| usage()),
            "--rx-gain" => rx_gain = val().parse().unwrap_or_else(|_| usage()),
            "--jitter-ms" => jitter_ms = val().parse().unwrap_or_else(|_| usage()),
            "-h" | "--help" => usage(),
            _ => usage(),
        }
        i += 2;
    }
    let home = env::var("HOME").unwrap_or_else(|_| ".".into());
    let log_dir = log_dir.unwrap_or_else(|| PathBuf::from(home).join(".cache/courier-sip"));
    fs::create_dir_all(&log_dir).expect("create log dir");
    logfile::init(&log_dir.join("gateway.log")).expect("open gateway.log");
    let binmodem_port = env::var("GW_BINMODEM_PORT").ok().and_then(|v| v.parse().ok()).unwrap_or(5060);
    let cfg = Cfg { jitter_ms, tx_gain, rx_gain, binmodem_port };

    let listener = TcpListener::bind((host.as_str(), port)).expect("bind");
    let line = format!("gateway on ws://{host}:{port} (tx gain {tx_gain:.2}, rx gain {rx_gain:.2}, jitter {} ms)", jitter_ms as i64);
    logfile::log(&line);
    println!("gateway on ws://{host}:{port}");
    for conn in listener.incoming() {
        let Ok(mut stream) = conn else { continue };
        let Some(leftover) = session::accept(&mut stream, &host) else {
            continue;
        };
        if let Err(e) = session::run(&cfg, stream, leftover) {
            logfile::log(&format!("session error: {e}"));
        }
    }
}
