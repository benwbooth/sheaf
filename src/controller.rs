//! The `Sheaf` controller's invokables (declared in bridge.rs).

use crate::bridge::ffi;
use crate::desktop;
use crate::scanner::{self, Cmd, Scanner};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use serde_json::{json, Value};
use sheaf_core::export::{self, Format, Options, PageSrc};
use sheaf_core::pages::{PageInfo, Store};
use sheaf_core::settings::{user_dir, Settings};
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock};

fn qs(s: &str) -> QString {
    QString::from(s)
}

/// The session's pages (shared by the scanner thread and page edits).
fn store() -> &'static Arc<Store> {
    static S: OnceLock<Arc<Store>> = OnceLock::new();
    S.get_or_init(|| Arc::new(Store::new().expect("can't make sheaf's cache folder")))
}

static SAVE_CANCEL: AtomicBool = AtomicBool::new(false);

pub struct SheafRust {
    pub(crate) devices_json: QString,
    pub(crate) searching: bool,
    pub(crate) device: QString,
    pub(crate) opening: bool,
    pub(crate) options_json: QString,
    pub(crate) busy: bool,
    pub(crate) busy_kind: QString,
    pub(crate) progress: f64,
    pub(crate) status: QString,
    pub(crate) live_url: QString,
    pub(crate) preview_url: QString,
    pub(crate) preview_bounds: QString,
    pub(crate) settings_json: QString,
    settings: Settings,
    scanner: Option<Scanner>,
}

impl Default for SheafRust {
    fn default() -> Self {
        let settings = Settings::load();
        SheafRust {
            devices_json: qs("[]"),
            searching: false,
            device: QString::default(),
            opening: false,
            options_json: qs("[]"),
            busy: false,
            busy_kind: QString::default(),
            progress: 0.0,
            status: QString::default(),
            live_url: QString::default(),
            preview_url: QString::default(),
            preview_bounds: QString::default(),
            settings_json: qs(&serde_json::to_string(&settings).unwrap_or_default()),
            settings,
            scanner: None,
        }
    }
}

fn save_settings_bg(s: Settings) {
    std::thread::spawn(move || {
        if let Err(e) = s.save() {
            eprintln!("sheaf: couldn't save settings: {e}");
        }
    });
}

impl ffi::Sheaf {
    fn answer(&self, key: &QString, f: impl FnOnce() -> Value + Send + 'static) {
        let key = key.to_string();
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let v = f().to_string();
            let _ = qt.queue(move |s| s.async_reply(qs(&key), qs(&v)));
        });
    }

    fn send(&self, c: Cmd) {
        if let Some(s) = &self.rust().scanner {
            s.send(c);
        }
    }

    pub fn start(mut self: Pin<&mut Self>) {
        if self.rust().scanner.is_some() {
            return;
        }
        let qt = self.qt_thread();
        let sc = scanner::spawn(qt, store().clone());
        sc.send(Cmd::Refresh);
        self.as_mut().rust_mut().scanner = Some(sc);
    }

    pub fn refresh_devices(self: Pin<&mut Self>) {
        self.send(Cmd::Refresh);
    }

    pub fn open_device(mut self: Pin<&mut Self>, name: &QString) {
        let name = name.to_string();
        let saved = self.rust().settings.device_options.get(&name).and_then(|v| v.as_object().cloned()).unwrap_or_default();
        if self.rust().settings.last_device != name {
            self.as_mut().rust_mut().settings.last_device = name.clone();
            save_settings_bg(self.rust().settings.clone());
        }
        self.send(Cmd::Open { name, saved });
    }

    pub fn set_option(mut self: Pin<&mut Self>, name: &QString, value_json: &QString) {
        let name = name.to_string();
        let value: Value = serde_json::from_str(&value_json.to_string()).unwrap_or(Value::Null);
        // Remembered for this scanner (applied when it's opened again).
        let dev = self.rust().device.to_string();
        if !dev.is_empty() {
            let mut s = self.rust().settings.clone();
            let e = s.device_options.entry(dev).or_insert_with(|| json!({}));
            if let Some(o) = e.as_object_mut() {
                o.insert(name.clone(), value.clone());
            }
            self.as_mut().rust_mut().settings = s.clone();
            save_settings_bg(s);
        }
        self.send(Cmd::Set { name, value });
    }

    pub fn preview(self: Pin<&mut Self>) {
        self.send(Cmd::Preview);
    }

    pub fn scan(self: Pin<&mut Self>, json: &QString) {
        let v: Value = serde_json::from_str(&json.to_string()).unwrap_or_default();
        let area = v["area"].as_array().filter(|a| a.len() == 4).map(|a| {
            let f = |i: usize| a[i].as_f64().unwrap_or(if i < 2 { 0.0 } else { 1.0 });
            [f(0), f(1), f(2), f(3)]
        });
        self.send(Cmd::Scan { area, straighten: v["straighten"].as_bool().unwrap_or(false), crop: v["crop"].as_bool().unwrap_or(false) });
    }

    pub fn cancel(&self) {
        if let Some(s) = &self.rust().scanner {
            s.cancel.store(true, Ordering::Relaxed);
        }
    }

    pub fn edit_page(&self, key: &QString, page_json: &QString, op: &QString) {
        let page: Option<PageInfo> = parse_page(&serde_json::from_str(&page_json.to_string()).unwrap_or_default());
        let op = op.to_string();
        self.answer(key, move || {
            let Some(page) = page else { return json!({ "error": "That page is gone." }) };
            match store().edit(&page, &op) {
                Ok(Some(p)) => serde_json::to_value(p).unwrap_or_default(),
                Ok(None) => json!({ "unchanged": true }),
                Err(e) => json!({ "error": e.to_string() }),
            }
        });
    }

    pub fn save(&self, key: &QString, json: &QString) {
        let v: Value = serde_json::from_str(&json.to_string()).unwrap_or_default();
        let qt = self.qt_thread();
        SAVE_CANCEL.store(false, Ordering::Relaxed);
        self.answer(key, move || {
            let pages: Vec<PageSrc> = v["pages"]
                .as_array()
                .map(|a| a.iter().filter_map(parse_page).map(|p| PageSrc { path: PathBuf::from(p.path), dpi: p.dpi }).collect())
                .unwrap_or_default();
            let folder = PathBuf::from(v["folder"].as_str().unwrap_or_default());
            let name = v["name"].as_str().unwrap_or("Scan").to_string();
            let format = Format::parse(v["format"].as_str().unwrap_or("pdf"));
            let ocr = (format == Format::Pdf && v["ocr"].as_bool().unwrap_or(false)).then(|| v["language"].as_str().filter(|l| !l.is_empty()).unwrap_or("eng").to_string());
            let opts = Options { format, quality: v["quality"].as_u64().unwrap_or(85).clamp(1, 100) as u8, ocr, title: name.clone() };
            let r = export::save(&pages, &folder, &name, &opts, &SAVE_CANCEL, |done, total| {
                let _ = qt.queue(move |s| s.save_progress(done as i32, total as i32));
            });
            match r {
                Ok(files) => json!({ "files": files }),
                Err(e) if e.to_string() == "cancelled" => json!({ "cancelled": true }),
                Err(e) => json!({ "error": format!("{e:#}") }),
            }
        });
    }

    pub fn cancel_save(&self) {
        SAVE_CANCEL.store(true, Ordering::Relaxed);
    }

    pub fn show_in_file_manager(&self, path: &QString) {
        let p = path.to_string();
        std::thread::spawn(move || desktop::show_in_file_manager(&p));
    }

    pub fn open_file(&self, path: &QString) {
        let p = path.to_string();
        std::thread::spawn(move || desktop::open_file(&p));
    }

    pub fn choose_folder(&self, key: &QString, current: &QString) {
        let cur = current.to_string();
        self.answer(key, move || match desktop::choose_folder(&cur) {
            Ok(Some(f)) => json!({ "folder": f }),
            Ok(None) => json!({ "cancelled": true }),
            Err(e) => json!({ "error": e.to_string() }),
        });
    }

    pub fn ocr_languages(&self) -> QString {
        // A directory listing of a handful of files: quick enough to read
        // where it's asked (the Settings sheet opening).
        qs(&serde_json::to_string(&export::ocr_languages()).unwrap_or_else(|_| "[]".into()))
    }

    pub fn user_folders(&self) -> QString {
        let v: Vec<Value> = [("Documents", "DOCUMENTS"), ("Pictures", "PICTURES"), ("Desktop", "DESKTOP"), ("Downloads", "DOWNLOAD")]
            .iter()
            .map(|(n, k)| json!({ "name": n, "path": user_dir(k) }))
            .collect();
        qs(&Value::Array(v).to_string())
    }

    pub fn save_settings(mut self: Pin<&mut Self>, json: &QString) {
        let Ok(mut s) = serde_json::from_str::<Settings>(&json.to_string()) else { return };
        // Options per scanner are kept here, not by QML.
        s.device_options = self.rust().settings.device_options.clone();
        self.as_mut().rust_mut().settings = s.clone();
        let j = serde_json::to_string(&s).unwrap_or_default();
        self.as_mut().set_settings_json(qs(&j));
        save_settings_bg(s);
    }

    pub fn set_icon_theme(&self, dark: bool) {
        ffi::sheaf_set_icon_theme(dark);
    }

    pub fn env(&self, name: &QString) -> QString {
        qs(&std::env::var(name.to_string()).unwrap_or_default())
    }

    pub fn grab_windows(&self, path: &QString) {
        ffi::sheaf_grab_windows(path);
    }

    pub fn clear_session(&self) {
        store().clear();
    }
}

fn parse_page(v: &Value) -> Option<PageInfo> {
    Some(PageInfo {
        id: v["id"].as_u64()?,
        rev: v["rev"].as_u64().unwrap_or(1),
        path: v["path"].as_str()?.to_string(),
        thumb: v["thumb"].as_str().unwrap_or_default().to_string(),
        width: v["width"].as_u64().unwrap_or(0) as u32,
        height: v["height"].as_u64().unwrap_or(0) as u32,
        dpi: v["dpi"].as_f64().unwrap_or(300.0),
    })
}
