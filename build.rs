use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

fn main() {
    // The dev shell links a merged Qt tree at .qt-env; elsewhere set QMAKE
    // or put qmake on PATH.
    if std::env::var_os("QMAKE").is_none() {
        let manifest = std::path::PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
        let local = manifest.join(".qt-env").join("bin").join("qmake");
        if local.exists() {
            std::env::set_var("QMAKE", &local);
        }
    }
    println!("cargo::rerun-if-env-changed=QMAKE");
    println!("cargo::rerun-if-changed=include");
    println!("cargo::rerun-if-changed=cpp");
    println!("cargo::rerun-if-changed=qml");
    let qmake = std::env::var("QMAKE").unwrap_or_else(|_| "qmake6".into());
    let query = |var: &str| {
        std::process::Command::new(&qmake)
            .args(["-query", var])
            .output()
            .ok()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .filter(|s| !s.is_empty())
    };
    if let Some(qml) = query("QT_INSTALL_QML") {
        println!("cargo::rustc-env=SHEAF_QT_QML={qml}");
    }
    if let Some(p) = query("QT_INSTALL_PLUGINS") {
        println!("cargo::rustc-env=SHEAF_QT_PLUGINS={p}");
    }
    check_text_rendering();

    // Every QML file in qml/ (Theme, Async and Help are singletons).
    let mut files: Vec<String> = std::fs::read_dir("qml")
        .unwrap()
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().map(|x| x == "qml").unwrap_or(false))
        .map(|p| p.to_string_lossy().into_owned())
        .collect();
    files.sort();
    let singletons = ["Theme.qml", "Async.qml", "Help.qml"];
    let qml_files: Vec<QmlFile> = files
        .iter()
        .map(|f| {
            let name = std::path::Path::new(f).file_name().unwrap().to_string_lossy().into_owned();
            QmlFile::from(f.as_str()).singleton(singletons.contains(&name.as_str()))
        })
        .collect();

    // Qt's private QPA headers, for the global menu bar (GlobalMenuBar).
    let qpa_headers: Vec<std::path::PathBuf> = match (query("QT_INSTALL_HEADERS"), query("QT_VERSION")) {
        (Some(h), Some(v)) => {
            let h = std::path::PathBuf::from(h);
            let gui = h.join("QtGui").join(&v);
            let core = h.join("QtCore").join(&v);
            vec![gui.join("QtGui"), gui, core.join("QtCore"), core]
        }
        _ => Vec::new(),
    };

    let builder = CxxQtBuilder::new_qml_module(QmlModule::new("Sheaf").qml_files(qml_files))
        .crate_include_root(None)
        .include_dir("include")
        .qt_module("Quick")
        .qt_module("QuickControls2")
        .cpp_file("cpp/native.cpp")
        // The menus in the desktop's global menu bar (moc runs on the header).
        .cpp_file("include/global_menu.h")
        .cpp_file("cpp/global_menu.cpp")
        .files(["src/bridge.rs"]);
    let builder = unsafe {
        builder.cc_builder(|cc| {
            cc.includes(&qpa_headers);
            cc.define("SHEAF_VERSION", Some(format!("{:?}", env!("CARGO_PKG_VERSION")).as_str()));
        })
    };
    builder.build();
}

/// Ben's rule: native text everywhere. The app sets NativeTextRendering
/// globally; no QML file may ask for Qt's own (distance-field) text.
fn check_text_rendering() {
    let Ok(rd) = std::fs::read_dir("qml") else { return };
    for e in rd.flatten() {
        let p = e.path();
        let Ok(src) = std::fs::read_to_string(&p) else { continue };
        if src.contains("Text.QtRendering") || src.contains("Text.CurveRendering") {
            panic!("{}: use Text.NativeRendering (native text rendering is required)", p.display());
        }
    }
}
