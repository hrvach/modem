//! gateway.log: "%9.3f <text>" lines, appended, flushed per line (as gateway.py).
use std::fs::{File, OpenOptions};
use std::io::{self, Write};
use std::path::Path;
use std::sync::{Mutex, OnceLock};
use std::time::Instant;

static T0: OnceLock<Instant> = OnceLock::new();
static FILE: OnceLock<Mutex<File>> = OnceLock::new();

pub fn init(path: &Path) -> io::Result<()> {
    T0.get_or_init(Instant::now);
    let f = OpenOptions::new().create(true).append(true).open(path)?;
    let _ = FILE.set(Mutex::new(f));
    Ok(())
}

pub fn log(s: &str) {
    if let Some(m) = FILE.get() {
        let t = T0.get_or_init(Instant::now).elapsed().as_secs_f64();
        if let Ok(mut f) = m.lock() {
            let _ = writeln!(f, "{:9.3} {}", t, s);
        }
    }
}
