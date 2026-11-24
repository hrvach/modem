//! Tiny JSON reader for the flat command objects the page sends ({"cmd":"invite","number":"5551234"}).
//! Values: strings, numbers, booleans, null. Nested objects or arrays are an error.

#[derive(Debug, Clone, PartialEq)]
pub enum Val {
    Str(String),
    Num(f64),
    Bool(bool),
    Null,
}

pub type Obj = Vec<(String, Val)>;

pub fn parse_flat(s: &str) -> Result<Obj, String> {
    let b = s.as_bytes();
    let mut i = 0;
    let mut out = Obj::new();
    skip_ws(b, &mut i);
    expect(b, &mut i, b'{')?;
    skip_ws(b, &mut i);
    if b.get(i) == Some(&b'}') {
        return Ok(out);
    }
    loop {
        skip_ws(b, &mut i);
        let k = string(b, &mut i)?;
        skip_ws(b, &mut i);
        expect(b, &mut i, b':')?;
        skip_ws(b, &mut i);
        let v = value(b, &mut i)?;
        out.push((k, v));
        skip_ws(b, &mut i);
        match b.get(i) {
            Some(b',') => i += 1,
            Some(b'}') => return Ok(out),
            _ => return Err(format!("expected , or }} at {i}")),
        }
    }
}

pub fn get<'a>(o: &'a [(String, Val)], k: &str) -> Option<&'a Val> {
    o.iter().find(|(kk, _)| kk == k).map(|(_, v)| v)
}

pub fn get_str<'a>(o: &'a [(String, Val)], k: &str) -> Option<&'a str> {
    match get(o, k) {
        Some(Val::Str(s)) => Some(s.as_str()),
        _ => None,
    }
}

pub fn get_num(o: &[(String, Val)], k: &str) -> Option<f64> {
    match get(o, k) {
        Some(Val::Num(x)) => Some(*x),
        _ => None,
    }
}

/// JSON string literal with escapes.
pub fn esc(s: &str) -> String {
    let mut o = String::with_capacity(s.len() + 2);
    o.push('"');
    for c in s.chars() {
        match c {
            '"' => o.push_str("\\\""),
            '\\' => o.push_str("\\\\"),
            '\n' => o.push_str("\\n"),
            '\r' => o.push_str("\\r"),
            '\t' => o.push_str("\\t"),
            c if (c as u32) < 0x20 => o.push_str(&format!("\\u{:04x}", c as u32)),
            c => o.push(c),
        }
    }
    o.push('"');
    o
}

fn skip_ws(b: &[u8], i: &mut usize) {
    while *i < b.len() && matches!(b[*i], b' ' | b'\t' | b'\r' | b'\n') {
        *i += 1;
    }
}

fn expect(b: &[u8], i: &mut usize, c: u8) -> Result<(), String> {
    if b.get(*i) == Some(&c) {
        *i += 1;
        Ok(())
    } else {
        Err(format!("expected '{}' at {}", c as char, *i))
    }
}

fn string(b: &[u8], i: &mut usize) -> Result<String, String> {
    expect(b, i, b'"')?;
    let mut out: Vec<u8> = Vec::new();
    loop {
        let c = *b.get(*i).ok_or("unterminated string")?;
        *i += 1;
        match c {
            b'"' => return Ok(String::from_utf8_lossy(&out).into_owned()),
            b'\\' => {
                let e = *b.get(*i).ok_or("bad escape")?;
                *i += 1;
                match e {
                    b'"' => out.push(b'"'),
                    b'\\' => out.push(b'\\'),
                    b'/' => out.push(b'/'),
                    b'b' => out.push(8),
                    b'f' => out.push(12),
                    b'n' => out.push(b'\n'),
                    b'r' => out.push(b'\r'),
                    b't' => out.push(b'\t'),
                    b'u' => {
                        let hex = b.get(*i..*i + 4).ok_or("bad \\u escape")?;
                        let code = u32::from_str_radix(std::str::from_utf8(hex).map_err(|e| e.to_string())?, 16)
                            .map_err(|e| e.to_string())?;
                        *i += 4;
                        let ch = char::from_u32(code).unwrap_or('\u{fffd}');
                        let mut tmp = [0u8; 4];
                        out.extend_from_slice(ch.encode_utf8(&mut tmp).as_bytes());
                    }
                    _ => return Err("bad escape".into()),
                }
            }
            c => out.push(c),
        }
    }
}

fn value(b: &[u8], i: &mut usize) -> Result<Val, String> {
    match b.get(*i) {
        Some(b'"') => Ok(Val::Str(string(b, i)?)),
        Some(b'{') | Some(b'[') => Err("nested values are not supported".into()),
        Some(b't') if b[*i..].starts_with(b"true") => {
            *i += 4;
            Ok(Val::Bool(true))
        }
        Some(b'f') if b[*i..].starts_with(b"false") => {
            *i += 5;
            Ok(Val::Bool(false))
        }
        Some(b'n') if b[*i..].starts_with(b"null") => {
            *i += 4;
            Ok(Val::Null)
        }
        Some(_) => {
            let st = *i;
            while *i < b.len() && matches!(b[*i], b'0'..=b'9' | b'+' | b'-' | b'.' | b'e' | b'E') {
                *i += 1;
            }
            let t = std::str::from_utf8(&b[st..*i]).map_err(|e| e.to_string())?;
            t.parse::<f64>().map(Val::Num).map_err(|_| format!("bad value at {st}"))
        }
        None => Err("unexpected end".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flat_objects() {
        let o = parse_flat(r#" {"cmd":"invite","dest":"dmodem","number":"5551234"} "#).unwrap();
        assert_eq!(get_str(&o, "cmd"), Some("invite"));
        assert_eq!(get_str(&o, "number"), Some("5551234"));
        let o = parse_flat(r#"{"cmd":"levels","tx":0.25,"rx":-1e-1,"on":true,"x":null}"#).unwrap();
        assert_eq!(get_num(&o, "tx"), Some(0.25));
        assert_eq!(get_num(&o, "rx"), Some(-0.1));
        assert_eq!(get(&o, "on"), Some(&Val::Bool(true)));
        assert_eq!(get(&o, "x"), Some(&Val::Null));
        let o = parse_flat(r#"{"a":"q\"\\\n\u00e9"}"#).unwrap();
        assert_eq!(get_str(&o, "a"), Some("q\"\\\né"));
        assert_eq!(parse_flat("{}").unwrap(), vec![]);
        assert!(parse_flat(r#"{"a":{"b":1}}"#).is_err());
        assert!(parse_flat(r#"{"a":1"#).is_err());
        assert!(parse_flat("not json").is_err());
    }

    #[test]
    fn escaping() {
        assert_eq!(esc("a\"b\\c\nd"), r#""a\"b\\c\nd""#);
        assert_eq!(esc("\u{1}"), "\"\\u0001\"");
    }
}
