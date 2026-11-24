//! SANE through libsane (the same library scanimage and every other SANE
//! frontend links): devices, their options, and reading scans.
//!
//! libsane is not thread-safe, so everything here runs on one thread (the
//! scanner thread in the app). A scan can be stopped from another thread
//! with the `cancel` flag given to [`Device::scan`]; it is checked between
//! reads.

use anyhow::{anyhow, bail, Result};
use serde::Serialize;
use serde_json::{json, Value};
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::sync::atomic::{AtomicBool, Ordering};

#[allow(non_camel_case_types, dead_code)]
mod sys {
    use super::*;
    pub type SANE_Status = c_int;
    pub type SANE_Word = c_int;
    pub type SANE_Handle = *mut c_void;

    pub const STATUS_GOOD: SANE_Status = 0;
    pub const STATUS_EOF: SANE_Status = 5;
    pub const STATUS_NO_DOCS: SANE_Status = 7;

    pub const TYPE_BOOL: c_int = 0;
    pub const TYPE_INT: c_int = 1;
    pub const TYPE_FIXED: c_int = 2;
    pub const TYPE_STRING: c_int = 3;
    pub const TYPE_BUTTON: c_int = 4;
    pub const TYPE_GROUP: c_int = 5;

    pub const CAP_SOFT_SELECT: c_int = 1 << 0;
    pub const CAP_AUTOMATIC: c_int = 1 << 4;
    pub const CAP_INACTIVE: c_int = 1 << 5;
    pub const CAP_ADVANCED: c_int = 1 << 6;

    pub const INFO_RELOAD_OPTIONS: c_int = 1 << 1;

    pub const CONSTRAINT_RANGE: c_int = 1;
    pub const CONSTRAINT_WORD_LIST: c_int = 2;
    pub const CONSTRAINT_STRING_LIST: c_int = 3;

    pub const ACTION_GET: c_int = 0;
    pub const ACTION_SET: c_int = 1;
    pub const ACTION_AUTO: c_int = 2;

    pub const FRAME_GRAY: c_int = 0;
    pub const FRAME_RGB: c_int = 1;
    pub const FRAME_RED: c_int = 2;
    pub const FRAME_GREEN: c_int = 3;
    pub const FRAME_BLUE: c_int = 4;

    #[repr(C)]
    pub struct SANE_Device {
        pub name: *const c_char,
        pub vendor: *const c_char,
        pub model: *const c_char,
        pub kind: *const c_char,
    }

    #[repr(C)]
    pub struct SANE_Range {
        pub min: SANE_Word,
        pub max: SANE_Word,
        pub quant: SANE_Word,
    }

    #[repr(C)]
    pub struct SANE_Option_Descriptor {
        pub name: *const c_char,
        pub title: *const c_char,
        pub desc: *const c_char,
        pub kind: c_int,
        pub unit: c_int,
        pub size: c_int,
        pub cap: c_int,
        pub constraint_type: c_int,
        pub constraint: *const c_void,
    }

    #[repr(C)]
    #[derive(Default)]
    pub struct SANE_Parameters {
        pub format: c_int,
        pub last_frame: c_int,
        pub bytes_per_line: c_int,
        pub pixels_per_line: c_int,
        pub lines: c_int,
        pub depth: c_int,
    }

    pub type AuthCallback = Option<extern "C" fn(*const c_char, *mut c_char, *mut c_char)>;


    extern "C" {
        pub fn sane_init(version: *mut SANE_Word, auth: AuthCallback) -> SANE_Status;
        pub fn sane_exit();
        pub fn sane_get_devices(list: *mut *const *const SANE_Device, local_only: c_int) -> SANE_Status;
        pub fn sane_open(name: *const c_char, h: *mut SANE_Handle) -> SANE_Status;
        pub fn sane_close(h: SANE_Handle);
        pub fn sane_get_option_descriptor(h: SANE_Handle, n: c_int) -> *const SANE_Option_Descriptor;
        pub fn sane_control_option(h: SANE_Handle, n: c_int, action: c_int, value: *mut c_void, info: *mut c_int) -> SANE_Status;
        pub fn sane_get_parameters(h: SANE_Handle, p: *mut SANE_Parameters) -> SANE_Status;
        pub fn sane_start(h: SANE_Handle) -> SANE_Status;
        pub fn sane_read(h: SANE_Handle, buf: *mut u8, max: SANE_Word, len: *mut SANE_Word) -> SANE_Status;
        pub fn sane_cancel(h: SANE_Handle);
        pub fn sane_strstatus(s: SANE_Status) -> *const c_char;
    }
}

const FIXED_SCALE: f64 = 65536.0;

fn cstr(p: *const c_char) -> String {
    if p.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned()
}

/// What a SANE status means, in plain words.
pub fn status_text(s: sys::SANE_Status) -> String {
    match s {
        1 => "The scanner can't do that.".into(),
        2 => "The scan was cancelled.".into(),
        3 => "The scanner is busy (another app may be using it). Try again in a moment.".into(),
        4 => "The scanner didn't accept that setting.".into(),
        6 => "Paper is jammed in the document feeder.".into(),
        7 => "The document feeder is empty. Put the pages in the feeder, face down, and try again.".into(),
        8 => "The scanner's lid is open.".into(),
        9 => "The scanner stopped answering. Check its cable or network connection.".into(),
        10 => "Out of memory.".into(),
        11 => "Not allowed to use this scanner (check its permissions or password).".into(),
        _ => cstr(unsafe { sys::sane_strstatus(s) }),
    }
}

fn check(s: sys::SANE_Status) -> Result<()> {
    if s == sys::STATUS_GOOD {
        Ok(())
    } else {
        Err(anyhow!(status_text(s)))
    }
}

/// libsane itself: initialised once, closed when dropped.
pub struct Sane {
    _private: (),
}

impl Sane {
    pub fn init() -> Result<Sane> {
        let mut v = 0;
        check(unsafe { sys::sane_init(&mut v, None) })?;
        Ok(Sane { _private: () })
    }

    /// Every scanner SANE finds: USB, and network ones (eSCL/AirScan,
    /// WSD, saned). This can take a few seconds while it listens for
    /// network scanners.
    pub fn devices(&self) -> Result<Vec<DeviceInfo>> {
        let mut list: *const *const sys::SANE_Device = std::ptr::null();
        check(unsafe { sys::sane_get_devices(&mut list, 0) })?;
        let mut out = Vec::new();
        if list.is_null() {
            return Ok(out);
        }
        let mut i = 0;
        loop {
            let d = unsafe { *list.add(i) };
            if d.is_null() {
                break;
            }
            let d = unsafe { &*d };
            i += 1;
            // Webcams (SANE's v4l backend) aren't scanners.
            if cstr(d.name).starts_with("v4l:") {
                continue;
            }
            out.push(DeviceInfo::new(cstr(d.name), cstr(d.vendor), cstr(d.model), cstr(d.kind)));
        }
        Ok(out)
    }

    pub fn open(&self, name: &str) -> Result<Device> {
        let c = CString::new(name)?;
        let mut h: sys::SANE_Handle = std::ptr::null_mut();
        check(unsafe { sys::sane_open(c.as_ptr(), &mut h) })?;
        let mut d = Device { h, name: name.to_string(), options: Vec::new() };
        d.reload();
        Ok(d)
    }
}

impl Drop for Sane {
    fn drop(&mut self) {
        unsafe { sys::sane_exit() };
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct DeviceInfo {
    pub name: String,
    pub vendor: String,
    pub model: String,
    pub kind: String,
    /// "usb", "network" or "other": for the icon and the list's sections.
    pub connection: String,
    /// The name to show ("Canon PIXMA TS5300 (network)").
    pub label: String,
}

impl DeviceInfo {
    fn new(name: String, vendor: String, model: String, kind: String) -> DeviceInfo {
        let n = name.to_ascii_lowercase();
        let connection = if n.starts_with("airscan:") || n.starts_with("escl:") || n.starts_with("net:") || n.contains("tcp") || n.contains("http") || n.contains("ip=") {
            "network"
        } else if n.contains("usb") || n.contains("libusb") {
            "usb"
        } else {
            "other"
        };
        let mut label = if model.to_ascii_lowercase().starts_with(&vendor.to_ascii_lowercase()) || vendor.is_empty() || vendor == "Noname" {
            model.clone()
        } else {
            format!("{vendor} {model}")
        };
        if label.trim().is_empty() {
            label = name.clone();
        }
        DeviceInfo { name, vendor, model, kind, connection: connection.into(), label }
    }
}

/// One scanner option as QML shows it.
#[derive(Debug, Clone, Serialize)]
pub struct Opt {
    pub index: i32,
    pub name: String,
    pub title: String,
    pub desc: String,
    /// bool, int, fixed, string, button, group
    #[serde(rename = "type")]
    pub kind: String,
    /// "", px, bit, mm, dpi, %, us
    pub unit: String,
    /// Values in the option (1 for plain options; more for gamma tables).
    pub count: i32,
    pub settable: bool,
    pub active: bool,
    pub advanced: bool,
    pub automatic: bool,
    /// {min, max, step} for a range; a list of numbers or strings otherwise.
    pub range: Option<Value>,
    pub list: Option<Vec<Value>>,
    pub value: Value,
}

pub struct Device {
    h: sys::SANE_Handle,
    pub name: String,
    pub options: Vec<Opt>,
}

// The handle is only ever used from one thread at a time (the scanner
// thread owns the Device).
unsafe impl Send for Device {}

impl Drop for Device {
    fn drop(&mut self) {
        unsafe { sys::sane_close(self.h) };
    }
}

/// A finished scan of one page.
pub struct Frame {
    pub width: u32,
    pub height: u32,
    /// 1 (gray or line art), 3 (RGB)
    pub channels: u32,
    /// 1, 8 or 16
    pub depth: u32,
    /// Rows top to bottom: 8-bit samples, 16-bit samples in native byte
    /// order, or for depth 1 one byte per pixel (0 black, 255 white).
    pub data: Vec<u8>,
}

/// How a scan is going: called often while reading.
pub struct Progress<'a> {
    pub fraction: f64,
    /// Rows read so far (for a live picture of the scan).
    pub rows: u32,
    pub width: u32,
    pub channels: u32,
    pub depth: u32,
    pub data: &'a [u8],
}

impl Device {
    /// Read every option descriptor and value again.
    pub fn reload(&mut self) {
        let mut opts = Vec::new();
        let mut n = 0i32;
        // Option 0 holds the number of options.
        let mut count: c_int = 0;
        unsafe {
            sys::sane_control_option(self.h, 0, sys::ACTION_GET, &mut count as *mut c_int as *mut c_void, std::ptr::null_mut());
        }
        let count = count.clamp(1, 1000);
        for i in 1..count {
            let d = unsafe { sys::sane_get_option_descriptor(self.h, i) };
            if d.is_null() {
                continue;
            }
            let d = unsafe { &*d };
            n += 1;
            let kind = match d.kind {
                sys::TYPE_BOOL => "bool",
                sys::TYPE_INT => "int",
                sys::TYPE_FIXED => "fixed",
                sys::TYPE_STRING => "string",
                sys::TYPE_BUTTON => "button",
                _ => "group",
            };
            let unit = match d.unit {
                1 => "px",
                2 => "bit",
                3 => "mm",
                4 => "dpi",
                5 => "%",
                6 => "µs",
                _ => "",
            };
            let word_count = if matches!(d.kind, sys::TYPE_INT | sys::TYPE_FIXED | sys::TYPE_BOOL) { (d.size / 4).max(1) } else { 1 };
            let fixed = d.kind == sys::TYPE_FIXED;
            let num = |w: c_int| -> Value { if fixed { json!(w as f64 / FIXED_SCALE) } else { json!(w) } };
            let (mut range, mut list) = (None, None);
            if !d.constraint.is_null() {
                match d.constraint_type {
                    sys::CONSTRAINT_RANGE => {
                        let r = unsafe { &*(d.constraint as *const sys::SANE_Range) };
                        range = Some(json!({ "min": num(r.min), "max": num(r.max), "step": num(r.quant) }));
                    }
                    sys::CONSTRAINT_WORD_LIST => {
                        let w = d.constraint as *const c_int;
                        let len = unsafe { *w }.clamp(0, 10000) as usize;
                        list = Some((1..=len).map(|k| num(unsafe { *w.add(k) })).collect());
                    }
                    sys::CONSTRAINT_STRING_LIST => {
                        let s = d.constraint as *const *const c_char;
                        let mut v = Vec::new();
                        let mut k = 0;
                        loop {
                            let p = unsafe { *s.add(k) };
                            if p.is_null() || k > 1000 {
                                break;
                            }
                            v.push(json!(cstr(p)));
                            k += 1;
                        }
                        list = Some(v);
                    }
                    _ => {}
                }
            }
            let active = d.cap & sys::CAP_INACTIVE == 0;
            let value = if active && word_count == 1 { self.get_raw(i, d.kind, d.size) } else { Value::Null };
            opts.push(Opt {
                index: i,
                name: cstr(d.name),
                title: cstr(d.title),
                desc: cstr(d.desc),
                kind: kind.into(),
                unit: unit.into(),
                count: word_count,
                settable: d.cap & sys::CAP_SOFT_SELECT != 0,
                active,
                advanced: d.cap & sys::CAP_ADVANCED != 0,
                automatic: d.cap & sys::CAP_AUTOMATIC != 0,
                range,
                list,
                value,
            });
        }
        let _ = n;
        self.options = opts;
    }

    fn get_raw(&self, i: i32, kind: c_int, size: c_int) -> Value {
        let mut buf = vec![0u8; (size.max(4) as usize) + 1];
        let s = unsafe { sys::sane_control_option(self.h, i, sys::ACTION_GET, buf.as_mut_ptr() as *mut c_void, std::ptr::null_mut()) };
        if s != sys::STATUS_GOOD {
            return Value::Null;
        }
        let w = c_int::from_ne_bytes([buf[0], buf[1], buf[2], buf[3]]);
        match kind {
            sys::TYPE_BOOL => json!(w != 0),
            sys::TYPE_INT => json!(w),
            sys::TYPE_FIXED => json!(w as f64 / FIXED_SCALE),
            sys::TYPE_STRING => {
                let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
                json!(String::from_utf8_lossy(&buf[..end]))
            }
            _ => Value::Null,
        }
    }

    /// Whether `v` is one of the option's allowed values (within its range
    /// or in its list). Some backends start with a value outside them.
    pub fn allows(&self, name: &str, v: f64) -> bool {
        let Some(o) = self.option(name) else { return false };
        if let Some(l) = &o.list {
            return l.iter().filter_map(|x| x.as_f64()).any(|x| (x - v).abs() < 1e-6);
        }
        if let Some(r) = &o.range {
            return v >= r["min"].as_f64().unwrap_or(f64::MIN) && v <= r["max"].as_f64().unwrap_or(f64::MAX);
        }
        true
    }

    pub fn option(&self, name: &str) -> Option<&Opt> {
        self.options.iter().find(|o| o.name == name)
    }

    /// Set an option by name. Numbers go to the nearest allowed value (a
    /// list's closest entry, a range's step). Returns true when the
    /// scanner changed other options too (they have been read again).
    pub fn set(&mut self, name: &str, value: &Value) -> Result<bool> {
        let Some(o) = self.option(name).cloned() else { bail!("This scanner has no “{name}” setting.") };
        if !o.active || !o.settable {
            bail!("“{}” can't be changed right now.", o.title);
        }
        let d = unsafe { &*sys::sane_get_option_descriptor(self.h, o.index) };
        let mut info: c_int = 0;
        let status = match o.kind.as_str() {
            "string" => {
                let s = value.as_str().unwrap_or_default();
                let mut buf = vec![0u8; d.size.max(1) as usize];
                let n = s.len().min(buf.len() - 1);
                buf[..n].copy_from_slice(&s.as_bytes()[..n]);
                unsafe { sys::sane_control_option(self.h, o.index, sys::ACTION_SET, buf.as_mut_ptr() as *mut c_void, &mut info) }
            }
            "button" => unsafe { sys::sane_control_option(self.h, o.index, sys::ACTION_SET, std::ptr::null_mut(), &mut info) },
            "bool" => {
                let mut w: c_int = value.as_bool().unwrap_or(value.as_f64().unwrap_or(0.0) != 0.0) as c_int;
                unsafe { sys::sane_control_option(self.h, o.index, sys::ACTION_SET, &mut w as *mut c_int as *mut c_void, &mut info) }
            }
            "int" | "fixed" => {
                let v = nearest(&o, value.as_f64().unwrap_or(0.0));
                let w = if o.kind == "fixed" { (v * FIXED_SCALE).round() as c_int } else { v.round() as c_int };
                // Options holding several values (rare outside gamma tables)
                // get the value in every slot.
                let mut words = vec![w; o.count.max(1) as usize];
                unsafe { sys::sane_control_option(self.h, o.index, sys::ACTION_SET, words.as_mut_ptr() as *mut c_void, &mut info) }
            }
            _ => bail!("“{}” isn't a setting.", o.title),
        };
        check(status).map_err(|e| anyhow!("{}: {e}", o.title))?;
        // Always read the values back (the scanner may round them); the
        // descriptors too when it says others changed.
        let reload = info & sys::INFO_RELOAD_OPTIONS != 0;
        self.reload();
        Ok(reload)
    }

    /// Let the scanner choose (options marked automatic).
    pub fn set_auto(&mut self, name: &str) -> Result<()> {
        let Some(o) = self.option(name).cloned() else { bail!("no option {name}") };
        let mut info = 0;
        check(unsafe { sys::sane_control_option(self.h, o.index, sys::ACTION_AUTO, std::ptr::null_mut(), &mut info) })?;
        self.reload();
        Ok(())
    }

    pub fn number(&self, name: &str) -> Option<f64> {
        self.option(name).filter(|o| o.active).and_then(|o| o.value.as_f64())
    }

    pub fn string(&self, name: &str) -> Option<String> {
        self.option(name).filter(|o| o.active).and_then(|o| o.value.as_str().map(String::from))
    }

    /// The scan area's limits: (min, max) of tl-x and tl-y / br-x and br-y.
    pub fn area_limits(&self) -> Option<((f64, f64), (f64, f64))> {
        let lim = |n: &str| -> Option<(f64, f64)> {
            let r = self.option(n)?.range.as_ref()?;
            Some((r["min"].as_f64()?, r["max"].as_f64()?))
        };
        Some((lim("br-x").or_else(|| lim("tl-x"))?, lim("br-y").or_else(|| lim("tl-y"))?))
    }

    /// Scan one page. `cancel` stops it (Err "cancelled"). Ok(None) when the
    /// feeder has no (more) pages.
    pub fn scan(&mut self, cancel: &AtomicBool, mut progress: impl FnMut(&Progress)) -> Result<Option<Frame>> {
        let s = unsafe { sys::sane_start(self.h) };
        if s == sys::STATUS_NO_DOCS {
            unsafe { sys::sane_cancel(self.h) };
            return Ok(None);
        }
        if let Err(e) = check(s) {
            unsafe { sys::sane_cancel(self.h) };
            return Err(e);
        }
        let r = self.read_frames(cancel, &mut progress);
        // A finished page needs sane_cancel too only when it's the last of a
        // batch; the caller calls finish() then. On error, stop now.
        if r.is_err() {
            unsafe { sys::sane_cancel(self.h) };
        }
        r.map(Some)
    }

    /// End a batch of scans (the feeder stops, the lamp may go off).
    pub fn finish(&mut self) {
        unsafe { sys::sane_cancel(self.h) };
    }

    fn read_frames(&mut self, cancel: &AtomicBool, progress: &mut impl FnMut(&Progress)) -> Result<Frame> {
        let mut frame: Option<Frame> = None;
        let mut first = true;
        loop {
            if !first {
                check(unsafe { sys::sane_start(self.h) })?;
            }
            first = false;
            let mut p = sys::SANE_Parameters::default();
            check(unsafe { sys::sane_get_parameters(self.h, &mut p) })?;
            let depth = p.depth as u32;
            if !matches!(depth, 1 | 8 | 16) {
                bail!("This scanner sent {depth}-bit pictures, which sheaf can't read.");
            }
            let bpl = p.bytes_per_line.max(1) as usize;
            let width = p.pixels_per_line.max(1) as u32;
            let known_lines = p.lines > 0;
            let (channels, plane) = match p.format {
                sys::FRAME_GRAY => (1, None),
                sys::FRAME_RGB => (3, None),
                sys::FRAME_RED => (3, Some(0)),
                sys::FRAME_GREEN => (3, Some(1)),
                sys::FRAME_BLUE => (3, Some(2)),
                f => bail!("This scanner sent a kind of picture sheaf can't read (frame type {f})."),
            };
            let expected = if known_lines { bpl * p.lines as usize } else { 0 };
            let mut raw: Vec<u8> = Vec::with_capacity(expected.max(bpl * 64));
            let mut buf = vec![0u8; 256 * 1024];
            loop {
                if cancel.load(Ordering::Relaxed) {
                    unsafe { sys::sane_cancel(self.h) };
                    bail!("cancelled");
                }
                let mut len: c_int = 0;
                let s = unsafe { sys::sane_read(self.h, buf.as_mut_ptr(), buf.len() as c_int, &mut len) };
                if s == sys::STATUS_EOF {
                    break;
                }
                check(s)?;
                raw.extend_from_slice(&buf[..len.max(0) as usize]);
                if plane.is_none() {
                    let rows = (raw.len() / bpl) as u32;
                    let fraction = if known_lines { raw.len() as f64 / expected as f64 } else { 0.0 };
                    progress(&Progress { fraction, rows, width, channels, depth, data: &raw[..rows as usize * bpl] });
                } else {
                    let done = plane.unwrap() as f64;
                    let fraction = if known_lines { (done + raw.len() as f64 / expected as f64) / 3.0 } else { 0.0 };
                    progress(&Progress { fraction, rows: 0, width, channels, depth, data: &[] });
                }
            }
            let lines = (raw.len() / bpl) as u32;
            raw.truncate(lines as usize * bpl);
            let samples = unpack(&raw, bpl, width, lines, depth, if plane.is_some() { 1 } else { channels });
            match plane {
                None => {
                    return Ok(Frame { width, height: lines, channels, depth: if depth == 1 { 1 } else { depth }, data: samples });
                }
                Some(c) => {
                    let bytes = if depth == 16 { 2 } else { 1 };
                    let f = frame.get_or_insert_with(|| Frame { width, height: lines, channels: 3, depth, data: vec![0; (width * lines * 3) as usize * bytes] });
                    let n = (f.width.min(width) * f.height.min(lines)) as usize;
                    for i in 0..n {
                        for b in 0..bytes {
                            f.data[(i * 3 + c) * bytes + b] = samples[i * bytes + b];
                        }
                    }
                    if p.last_frame != 0 {
                        return Ok(frame.take().unwrap());
                    }
                }
            }
        }
    }
}

/// SANE rows (padded to bytes_per_line) to tight rows; depth 1 becomes one
/// byte per pixel (SANE's 1 is black).
fn unpack(raw: &[u8], bpl: usize, width: u32, lines: u32, depth: u32, channels: u32) -> Vec<u8> {
    let w = width as usize;
    let c = channels as usize;
    let mut out = Vec::with_capacity(w * c * lines as usize * if depth == 16 { 2 } else { 1 });
    for row in raw.chunks(bpl).take(lines as usize) {
        match depth {
            1 => {
                for x in 0..w * c {
                    let bit = row.get(x / 8).map(|b| b >> (7 - (x % 8)) & 1).unwrap_or(0);
                    out.push(if bit == 1 { 0 } else { 255 });
                }
            }
            8 => out.extend_from_slice(&row[..(w * c).min(row.len())]),
            _ => out.extend_from_slice(&row[..(w * c * 2).min(row.len())]),
        }
    }
    out
}

/// The allowed value nearest `v`: a list's closest entry, or a range's
/// clamp and step.
fn nearest(o: &Opt, v: f64) -> f64 {
    if let Some(list) = &o.list {
        let mut best = v;
        let mut dist = f64::MAX;
        for x in list.iter().filter_map(|x| x.as_f64()) {
            if (x - v).abs() < dist {
                dist = (x - v).abs();
                best = x;
            }
        }
        return best;
    }
    if let Some(r) = &o.range {
        let (min, max, step) = (r["min"].as_f64().unwrap_or(v), r["max"].as_f64().unwrap_or(v), r["step"].as_f64().unwrap_or(0.0));
        let mut x = v.clamp(min, max);
        if step > 0.0 {
            x = (min + ((x - min) / step).round() * step).clamp(min, max);
        }
        return x;
    }
    v
}

/// Whether a source name means the document feeder.
pub fn is_feeder(source: &str) -> bool {
    let s = source.to_ascii_lowercase();
    s.contains("adf") || s.contains("feeder") || s.contains("duplex") || s.contains("automatic")
}

/// Whether a source name means both sides of each sheet.
pub fn is_duplex(source: &str) -> bool {
    let s = source.to_ascii_lowercase();
    s.contains("duplex") || s.contains("both")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unpack_lineart() {
        // 0b1010_0000: black, white, black, white...
        let v = unpack(&[0b1010_0000], 1, 4, 1, 1, 1);
        assert_eq!(v, vec![0, 255, 0, 255]);
    }

    #[test]
    fn feeder_names() {
        assert!(is_feeder("ADF Duplex"));
        assert!(is_feeder("Automatic Document Feeder"));
        assert!(!is_feeder("Flatbed"));
        assert!(is_duplex("ADF Duplex"));
    }
}

/// Scans from SANE's `test` backend (no hardware). Run with
/// SHEAF_SANE_TEST=1 and SANE_CONFIG_DIR pointing at a folder whose
/// dll.conf says `test` (scripts/sane-test-env.sh).
#[cfg(test)]
mod device_tests {
    use super::*;

    #[test]
    fn scan_from_test_backend() {
        if std::env::var_os("SHEAF_SANE_TEST").is_none() {
            return;
        }
        let sane = Sane::init().unwrap();
        let devs = sane.devices().unwrap();
        let d = devs.iter().find(|d| d.name.starts_with("test")).expect("test backend not configured");
        let mut dev = sane.open(&d.name).unwrap();
        assert!(dev.option("resolution").is_some());
        dev.set("resolution", &json!(75.0)).unwrap();
        assert_eq!(dev.number("resolution"), Some(75.0));
        dev.set("mode", &json!("Color")).unwrap();
        dev.set("resolution", &json!(50)).unwrap();
        let cancel = AtomicBool::new(false);
        let mut calls = 0;
        let f = dev.scan(&cancel, |_| calls += 1).unwrap().unwrap();
        dev.finish();
        assert_eq!(f.channels, 3);
        assert!(f.width > 100 && f.height > 100, "{}x{}", f.width, f.height);
        assert_eq!(f.data.len(), (f.width * f.height * 3) as usize);
        assert!(calls > 0);
        // The feeder gives several pages, then says it's empty.
        dev.set("source", &json!("Automatic Document Feeder")).unwrap();
        let mut pages = 0;
        while let Some(_) = dev.scan(&cancel, |_| {}).unwrap() {
            pages += 1;
            assert!(pages < 50);
        }
        dev.finish();
        assert!(pages >= 1);
    }
}
