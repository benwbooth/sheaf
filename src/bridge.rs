//! The Rust <-> C++/QML boundary: the `Sheaf` controller QML talks to.
//!
//! Nothing here waits on the scanner, the disk or another program: scanner
//! work goes to the scanner thread (scanner.rs) and everything else to a
//! short-lived thread, answering through properties and signals
//! (`asyncReply(key, json)`; qml/Async.qml matches the key to its
//! callback).

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    unsafe extern "C++" {
        include!("native_helpers.h");
        fn sheaf_create_app();
        fn sheaf_run(url: &QString, import_path: &QString) -> i32;
        fn sheaf_set_icon_theme(dark: bool);
        fn sheaf_grab_windows(path: &QString);
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        /// The scanners found: [{name, label, vendor, model, kind, connection}].
        #[qproperty(QString, devices_json, cxx_name = "devicesJson")]
        /// Looking for scanners.
        #[qproperty(bool, searching)]
        /// The open scanner's SANE name ("" none).
        #[qproperty(QString, device)]
        /// Opening a scanner.
        #[qproperty(bool, opening)]
        /// The open scanner's options (sane::Opt list).
        #[qproperty(QString, options_json, cxx_name = "optionsJson")]
        /// A scan or preview is running.
        #[qproperty(bool, busy)]
        /// "preview" or "scan" while busy.
        #[qproperty(QString, busy_kind, cxx_name = "busyKind")]
        /// 0–1 (0 when the scanner can't say how far it is).
        #[qproperty(f64, progress)]
        /// What's happening, in words ("Scanning page 2…").
        #[qproperty(QString, status)]
        /// The scan in progress, as far as it's got (a file URL).
        #[qproperty(QString, live_url, cxx_name = "liveUrl")]
        /// The last overview scan (a file URL, "" none).
        #[qproperty(QString, preview_url, cxx_name = "previewUrl")]
        /// Where the document seems to be on the overview (fractions
        /// [x0, y0, x1, y1]) as JSON, "" when not found.
        #[qproperty(QString, preview_bounds, cxx_name = "previewBounds")]
        #[qproperty(QString, settings_json, cxx_name = "settingsJson")]
        type Sheaf = super::SheafRust;
    }

    impl cxx_qt::Threading for Sheaf {}

    #[auto_cxx_name]
    extern "RustQt" {
        /// The answer to a background call (key, JSON).
        #[qsignal]
        fn async_reply(self: Pin<&mut Sheaf>, key: QString, json: QString);
        /// A new page came in (pages::PageInfo JSON).
        #[qsignal]
        fn page_scanned(self: Pin<&mut Sheaf>, json: QString);
        /// A scan ended: {ok, pages, message, cancelled}.
        #[qsignal]
        fn scan_finished(self: Pin<&mut Sheaf>, json: QString);
        /// Something to tell the user in plain words. level: info, error.
        #[qsignal]
        fn notify(self: Pin<&mut Sheaf>, level: QString, message: QString);
        /// Saving: pages done of total.
        #[qsignal]
        fn save_progress(self: Pin<&mut Sheaf>, done: i32, total: i32);

        /// Start the scanner thread and look for scanners.
        #[qinvokable]
        fn start(self: Pin<&mut Sheaf>);
        #[qinvokable]
        fn refresh_devices(self: Pin<&mut Sheaf>);
        #[qinvokable]
        fn open_device(self: Pin<&mut Sheaf>, name: &QString);
        /// Change a scanner option (value as JSON).
        #[qinvokable]
        fn set_option(self: Pin<&mut Sheaf>, name: &QString, value_json: &QString);
        /// A quick low-resolution scan of the whole glass.
        #[qinvokable]
        fn preview(self: Pin<&mut Sheaf>);
        /// Scan pages: {area: [x0,y0,x1,y1] | null, straighten, crop}.
        #[qinvokable]
        fn scan(self: Pin<&mut Sheaf>, json: &QString);
        #[qinvokable]
        fn cancel(self: &Sheaf);

        /// Change a page (op: rotate:90, straighten, autocrop,
        /// crop:x0,y0,x1,y1). Answers the new PageInfo or {unchanged}.
        #[qinvokable]
        fn edit_page(self: &Sheaf, key: &QString, page_json: &QString, op: &QString);
        /// Save pages: {pages: [PageInfo], folder, name, format, quality,
        /// ocr, language}. Answers {files: [...]} or {error}.
        #[qinvokable]
        fn save(self: &Sheaf, key: &QString, json: &QString);
        #[qinvokable]
        fn cancel_save(self: &Sheaf);
        /// Show a file selected in grove (or the desktop's file manager).
        #[qinvokable]
        fn show_in_file_manager(self: &Sheaf, path: &QString);
        /// Open a file in its default app.
        #[qinvokable]
        fn open_file(self: &Sheaf, path: &QString);
        /// The desktop's folder chooser. Answers {folder} or {error}.
        #[qinvokable]
        fn choose_folder(self: &Sheaf, key: &QString, current: &QString);
        /// The text-recognition languages installed: ["eng", ...].
        #[qinvokable]
        fn ocr_languages(self: &Sheaf) -> QString;
        /// Folders to offer for saving: [{name, path}].
        #[qinvokable]
        fn user_folders(self: &Sheaf) -> QString;
        #[qinvokable]
        fn save_settings(self: Pin<&mut Sheaf>, json: &QString);
        #[qinvokable]
        fn set_icon_theme(self: &Sheaf, dark: bool);
        #[qinvokable]
        fn env(self: &Sheaf, name: &QString) -> QString;
        /// Test hook: save the windows to `path`.
        #[qinvokable]
        fn grab_windows(self: &Sheaf, path: &QString);
        /// Remove this session's page files (at quit).
        #[qinvokable]
        fn clear_session(self: &Sheaf);
    }
}

pub use crate::controller::SheafRust;
