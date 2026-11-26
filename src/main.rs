//! sheaf: a document and photo scanner, like macOS Image Capture.
//!
//!   sheaf                    open the window
//!   sheaf --screenshot FILE  (tests) grab the window and quit;
//!                            SHEAF_TEST="device=test:0;preview;scan" runs
//!                            steps first (qml/Main.qml testSteps)

mod bridge;
mod controller;
mod desktop;
mod scanner;

use bridge::ffi;
use cxx_qt_lib::QString;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--screenshot" => {
                if let Some(p) = args.get(i + 1) {
                    let abs = std::env::current_dir().unwrap_or_default().join(p);
                    std::env::set_var("SHEAF_SCREENSHOT", abs);
                }
                i += 1;
            }
            "--help" | "-h" => {
                println!("sheaf\n\nScan documents and photos. Press F1 in the window for help and shortcuts.");
                return;
            }
            "--version" => {
                println!("sheaf {}", env!("CARGO_PKG_VERSION"));
                return;
            }
            _ => {}
        }
        i += 1;
    }
    // hearth's light/dark mode and accent, so sheaf matches the shell.
    let hearth = sheaf_core::settings::config_home().join("hearth/settings.json");
    if let Ok(t) = std::fs::read_to_string(hearth) {
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&t) {
            std::env::set_var("SHEAF_HEARTH", v["appearance"].to_string());
        }
    }
    set_qt_env("QT_QUICK_CONTROLS_STYLE", "Basic");
    // Its own Qt's plugins first (a desktop QT_PLUGIN_PATH from another Qt
    // build would stop the window from opening).
    if let Some(p) = option_env!("SHEAF_QT_PLUGINS").filter(|p| std::path::Path::new(p).is_dir()) {
        let old = std::env::var("QT_PLUGIN_PATH").unwrap_or_default();
        set_qt_env("QT_PLUGIN_PATH", if old.is_empty() { p.to_string() } else { format!("{p}:{old}") });
    }
    ffi::sheaf_create_app();
    let import = option_env!("SHEAF_QT_QML").filter(|p| std::path::Path::new(p).exists()).unwrap_or("");
    let code = ffi::sheaf_run(&QString::from("qrc:/qt/qml/Sheaf/qml/Main.qml"), &QString::from(import));
    std::process::exit(code);
}

/// Sets an environment variable Qt reads while starting, noting what it was
/// (as `__APP_ORIG_<name>`: empty = unset, else "=value") so
/// `restore_launch_env` puts it back once the window is loaded: programs this
/// app starts get the desktop's own. (QT_QUICK_CONTROLS_STYLE=Basic leaking
/// from our apps made KDE apps opened from them draw plain light controls,
/// 2026-11-25.)
fn set_qt_env(name: &str, value: impl AsRef<std::ffi::OsStr>) {
    let note = format!("__APP_ORIG_{name}");
    if std::env::var_os(&note).is_none() {
        let was = std::env::var_os(name)
            .map(|v| {
                let mut s = std::ffi::OsString::from("=");
                s.push(v);
                s
            })
            .unwrap_or_default();
        #[allow(unused_unsafe)]
        unsafe { std::env::set_var(&note, was) };
    }
    #[allow(unused_unsafe)]
    unsafe { std::env::set_var(name, value) };
}

/// Puts back what `set_qt_env` (or the C++ start-up) changed, once the main
/// QML has loaded: Qt has read them all by then.
#[allow(dead_code)]
fn restore_launch_env() {
    for (k, v) in std::env::vars_os() {
        let Some(name) = k.to_str().and_then(|k| k.strip_prefix("__APP_ORIG_")).map(str::to_owned) else { continue };
        let v = v.to_string_lossy().into_owned();
        #[allow(unused_unsafe)]
        unsafe {
            match v.strip_prefix('=') {
                Some(old) => std::env::set_var(&name, old),
                None => std::env::remove_var(&name),
            }
            std::env::remove_var(&k);
        }
    }
}
