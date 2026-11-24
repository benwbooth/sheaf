//! The scanner thread: owns libsane and the open scanner (libsane isn't
//! thread-safe), takes commands from the window and answers by queueing
//! property changes and signals on the Qt thread.

use crate::bridge::ffi;
use cxx_qt::CxxQtThread;
use cxx_qt_lib::QString;
use serde_json::{json, Map, Value};
use sheaf_core::imgproc;
use sheaf_core::pages::Store;
use sheaf_core::sane::{self, Device, Sane};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::Arc;
use std::time::{Duration, Instant};

pub enum Cmd {
    Refresh,
    /// Open a scanner and apply its remembered settings.
    Open { name: String, saved: Map<String, Value> },
    Set { name: String, value: Value },
    Preview,
    Scan { area: Option<[f64; 4]>, straighten: bool, crop: bool },
}

pub struct Scanner {
    tx: Sender<Cmd>,
    pub cancel: Arc<AtomicBool>,
}

impl Scanner {
    pub fn send(&self, c: Cmd) {
        if matches!(c, Cmd::Preview | Cmd::Scan { .. }) {
            self.cancel.store(false, Ordering::Relaxed);
        }
        let _ = self.tx.send(c);
    }
}

type Qt = CxxQtThread<ffi::Sheaf>;

fn qs(s: &str) -> QString {
    QString::from(s)
}

pub fn spawn(qt: Qt, store: Arc<Store>) -> Scanner {
    let (tx, rx) = channel();
    let cancel = Arc::new(AtomicBool::new(false));
    let c = cancel.clone();
    std::thread::Builder::new()
        .name("scanner".into())
        .spawn(move || run(qt, store, rx, c))
        .expect("scanner thread");
    Scanner { tx, cancel }
}

struct Worker {
    qt: Qt,
    store: Arc<Store>,
    cancel: Arc<AtomicBool>,
    sane: Option<Sane>,
    dev: Option<Device>,
}

static LIVE: AtomicU64 = AtomicU64::new(0);

fn run(qt: Qt, store: Arc<Store>, rx: Receiver<Cmd>, cancel: Arc<AtomicBool>) {
    let sane = match Sane::init() {
        Ok(s) => Some(s),
        Err(e) => {
            let m = format!("Scanning isn't available: SANE couldn't start ({e}).");
            let _ = qt.queue(move |s| s.notify(qs("error"), qs(&m)));
            None
        }
    };
    let mut w = Worker { qt, store, cancel, sane, dev: None };
    while let Ok(cmd) = rx.recv() {
        match cmd {
            Cmd::Refresh => w.refresh(),
            Cmd::Open { name, saved } => w.open(&name, saved),
            Cmd::Set { name, value } => w.set(&name, &value),
            Cmd::Preview => w.preview(),
            Cmd::Scan { area, straighten, crop } => w.scan(area, straighten, crop),
        }
    }
}

impl Worker {
    fn queue(&self, f: impl FnOnce(Pin<&mut ffi::Sheaf>) + Send + 'static) {
        let _ = self.qt.queue(f);
    }

    fn notify(&self, level: &'static str, msg: String) {
        self.queue(move |s| s.notify(qs(level), qs(&msg)));
    }

    fn refresh(&mut self) {
        self.queue(|s| s.set_searching(true));
        let list = match &self.sane {
            Some(s) => s.devices().unwrap_or_else(|e| {
                self.notify("error", format!("Couldn't look for scanners: {e}"));
                Vec::new()
            }),
            None => Vec::new(),
        };
        let j = serde_json::to_string(&list).unwrap_or_else(|_| "[]".into());
        self.queue(move |mut s| {
            s.as_mut().set_devices_json(qs(&j));
            s.set_searching(false);
        });
    }

    fn send_options(&self) {
        let (name, j) = match &self.dev {
            Some(d) => (d.name.clone(), serde_json::to_string(&d.options).unwrap_or_else(|_| "[]".into())),
            None => (String::new(), "[]".into()),
        };
        self.queue(move |mut s| {
            s.as_mut().set_options_json(qs(&j));
            s.set_device(qs(&name));
        });
    }

    fn open(&mut self, name: &str, saved: Map<String, Value>) {
        self.dev = None;
        self.queue(|mut s| {
            s.as_mut().set_opening(true);
            s.as_mut().set_preview_url(QString::default());
            s.as_mut().set_preview_bounds(QString::default());
            s.set_status(qs("Connecting to the scanner…"));
        });
        let r = match &self.sane {
            Some(s) => s.open(name),
            None => Err(anyhow::anyhow!("SANE isn't available.")),
        };
        match r {
            Ok(mut d) => {
                // Remembered settings: the source first (it changes which
                // modes and resolutions there are), then the rest.
                let mut keys: Vec<&String> = saved.keys().collect();
                keys.sort_by_key(|k| (k.as_str() != "source", k.as_str() != "mode", k.as_str().to_string()));
                for k in keys {
                    if d.option(k).map(|o| o.active && o.settable).unwrap_or(false) {
                        let _ = d.set(k, &saved[k.as_str()]);
                    }
                }
                // A starting resolution the scanner doesn't itself allow.
                if let Some(r) = d.number("resolution") {
                    if !d.allows("resolution", r) {
                        let _ = d.set("resolution", &json!(150));
                    }
                }
                self.dev = Some(d);
                self.queue(|mut s| s.as_mut().set_status(QString::default()));
            }
            Err(e) => {
                self.notify("error", format!("Couldn't open the scanner: {e}"));
                self.queue(|mut s| s.as_mut().set_status(QString::default()));
            }
        }
        self.send_options();
        self.queue(|s| s.set_opening(false));
    }

    fn set(&mut self, name: &str, value: &Value) {
        let Some(d) = self.dev.as_mut() else { return };
        if let Err(e) = d.set(name, value) {
            self.notify("error", e.to_string());
        }
        self.send_options();
    }

    fn begin(&self, kind: &'static str, status: &'static str) {
        self.queue(move |mut s| {
            s.as_mut().set_busy(true);
            s.as_mut().set_busy_kind(qs(kind));
            s.as_mut().set_progress(0.0);
            s.as_mut().set_live_url(QString::default());
            s.set_status(qs(status));
        });
    }

    fn end(&self) {
        self.queue(|mut s| {
            s.as_mut().set_busy(false);
            s.as_mut().set_busy_kind(QString::default());
            s.as_mut().set_progress(0.0);
            s.as_mut().set_live_url(QString::default());
            s.set_status(QString::default());
        });
    }

    /// Scan one page, showing it as it comes in.
    fn scan_page(&mut self) -> anyhow::Result<Option<sane::Frame>> {
        let qt = self.qt.clone();
        let dir = self.store.dir().to_path_buf();
        let cancel = self.cancel.clone();
        let Some(d) = self.dev.as_mut() else { anyhow::bail!("No scanner is open.") };
        let mut last = Instant::now();
        let mut last_file: Option<std::path::PathBuf> = None;
        let r = d.scan(&cancel, |p| {
            if last.elapsed() < Duration::from_millis(250) {
                return;
            }
            last = Instant::now();
            let frac = p.fraction;
            let mut url = None;
            if let Some(img) = imgproc::partial_image(p.data, p.width, p.rows, p.channels, p.depth, 900) {
                let n = LIVE.fetch_add(1, Ordering::Relaxed);
                let f = dir.join(format!("live-{n}.jpg"));
                if img.to_rgb8().save_with_format(&f, image::ImageFormat::Jpeg).is_ok() {
                    url = Some(format!("file://{}", f.display()));
                    if let Some(old) = last_file.replace(f) {
                        // The view may still be loading the one before:
                        // remove the one before that.
                        std::thread::spawn(move || {
                            std::thread::sleep(Duration::from_secs(2));
                            let _ = std::fs::remove_file(old);
                        });
                    }
                }
            }
            let _ = qt.queue(move |mut s| {
                s.as_mut().set_progress(frac);
                if let Some(u) = url {
                    s.set_live_url(qs(&u));
                }
            });
        });
        if let Some(f) = last_file {
            std::thread::spawn(move || {
                std::thread::sleep(Duration::from_secs(2));
                let _ = std::fs::remove_file(f);
            });
        }
        r
    }

    fn set_quiet(&mut self, name: &str, v: Value) {
        if let Some(d) = self.dev.as_mut() {
            if d.option(name).map(|o| o.active && o.settable).unwrap_or(false) {
                let _ = d.set(name, &v);
            }
        }
    }

    /// The whole glass, or a part of it (fractions).
    fn set_area(&mut self, area: Option<[f64; 4]>) {
        let Some(((x0, x1), (y0, y1))) = self.dev.as_ref().and_then(|d| d.area_limits()) else { return };
        let a = area.unwrap_or([0.0, 0.0, 1.0, 1.0]);
        let (w, h) = (x1 - x0, y1 - y0);
        // tl to the corner first, so the bottom-right is never above or left
        // of it while setting.
        self.set_quiet("tl-x", json!(x0));
        self.set_quiet("tl-y", json!(y0));
        self.set_quiet("br-x", json!(x0 + a[2].clamp(0.0, 1.0) * w));
        self.set_quiet("br-y", json!(y0 + a[3].clamp(0.0, 1.0) * h));
        self.set_quiet("tl-x", json!(x0 + a[0].clamp(0.0, 1.0) * w));
        self.set_quiet("tl-y", json!(y0 + a[1].clamp(0.0, 1.0) * h));
    }

    fn preview(&mut self) {
        if self.dev.is_none() {
            return;
        }
        self.begin("preview", "Making an overview…");
        let (res, prev) = {
            let d = self.dev.as_ref().unwrap();
            (d.option("resolution").map(|o| o.value.clone()), d.option("preview").map(|o| o.value.clone()))
        };
        // Low resolution (about 75 dpi) of the whole glass, from the
        // flatbed's point of view.
        let low = self.dev.as_ref().unwrap().option("resolution").and_then(|o| {
            if let Some(l) = &o.list {
                let v: Vec<f64> = l.iter().filter_map(|x| x.as_f64()).collect();
                v.iter().copied().filter(|&x| x >= 75.0).fold(None, |m: Option<f64>, x| Some(m.map_or(x, |m| m.min(x)))).or(v.iter().copied().reduce(f64::max))
            } else {
                o.range.as_ref().map(|r| 75f64.clamp(r["min"].as_f64().unwrap_or(75.0), r["max"].as_f64().unwrap_or(75.0)))
            }
        });
        if let Some(l) = low {
            self.set_quiet("resolution", json!(l));
        }
        self.set_quiet("preview", json!(true));
        self.set_area(None);
        let r = self.scan_page();
        if let Some(d) = self.dev.as_mut() {
            d.finish();
        }
        if let Some(v) = prev {
            self.set_quiet("preview", v);
        }
        // Back to the resolution chosen before; one the scanner started
        // with but doesn't allow (SANE's test backend does that) becomes
        // 150 dpi.
        if let Some(v) = res {
            let ok = v.as_f64().map(|x| self.dev.as_ref().is_some_and(|d| d.allows("resolution", x))).unwrap_or(false);
            self.set_quiet("resolution", if ok { v } else { json!(150) });
        }
        self.send_options();
        match r {
            Ok(Some(f)) => {
                let img = imgproc::frame_to_image(f);
                let n = LIVE.fetch_add(1, Ordering::Relaxed);
                let file = self.store.dir().join(format!("overview-{n}.jpg"));
                let bounds = imgproc::content_bounds(&img).map(|b| json!([b.0, b.1, b.2, b.3]).to_string()).unwrap_or_default();
                let saved = imgproc::shrink(&img, 2000).to_rgb8().save_with_format(&file, image::ImageFormat::Jpeg);
                match saved {
                    Ok(()) => {
                        let url = format!("file://{}", file.display());
                        self.queue(move |mut s| {
                            s.as_mut().set_preview_bounds(qs(&bounds));
                            s.set_preview_url(qs(&url));
                        });
                    }
                    Err(e) => self.notify("error", format!("Couldn't keep the overview: {e}")),
                }
            }
            Ok(None) => self.notify("error", "The document feeder is empty. An overview needs the flatbed, or pages in the feeder.".into()),
            Err(e) if e.to_string() == "cancelled" => {}
            Err(e) => self.notify("error", format!("The overview failed: {e}")),
        }
        self.end();
    }

    fn scan(&mut self, area: Option<[f64; 4]>, straighten: bool, crop: bool) {
        if self.dev.is_none() {
            return;
        }
        self.begin("scan", "Scanning…");
        self.set_area(area);
        let (feeder, dpi) = {
            let d = self.dev.as_ref().unwrap();
            let src = d.string("source").unwrap_or_default();
            (sane::is_feeder(&src), d.number("resolution").or_else(|| d.number("x-resolution")).unwrap_or(300.0))
        };
        let mut pages = 0;
        let mut result = json!({ "ok": true });
        loop {
            let n = pages + 1;
            self.queue(move |mut s| {
                s.as_mut().set_progress(0.0);
                s.set_status(qs(&if n > 1 || feeder { format!("Scanning page {n}…") } else { "Scanning…".into() }));
            });
            match self.scan_page() {
                Ok(Some(f)) => {
                    self.queue(|s| s.set_status(qs("Finishing the page…")));
                    let mut img = imgproc::frame_to_image(f);
                    if straighten {
                        img = imgproc::deskew(&img).0;
                    }
                    if crop {
                        img = imgproc::autocrop(&img).0;
                    }
                    match self.store.add(&img, dpi) {
                        Ok(info) => {
                            let j = serde_json::to_string(&info).unwrap_or_default();
                            self.queue(move |s| s.page_scanned(qs(&j)));
                            pages += 1;
                        }
                        Err(e) => {
                            result = json!({ "ok": false, "message": e.to_string() });
                            break;
                        }
                    }
                    if !feeder {
                        break;
                    }
                }
                Ok(None) => {
                    if pages == 0 {
                        result = json!({ "ok": false, "message": sane::status_text(7) });
                    }
                    break;
                }
                Err(e) if e.to_string() == "cancelled" => {
                    result = json!({ "ok": false, "cancelled": true });
                    break;
                }
                Err(e) => {
                    result = json!({ "ok": false, "message": e.to_string() });
                    break;
                }
            }
        }
        if let Some(d) = self.dev.as_mut() {
            d.finish();
        }
        result["pages"] = json!(pages);
        let j = result.to_string();
        self.end();
        self.queue(move |s| s.scan_finished(qs(&j)));
    }
}
