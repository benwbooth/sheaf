# sheaf conventions

Scanner app (Image Capture-like) replacing Skanpage. Rust + Qt Quick via
cxx-qt, same layout and nixpkgs pin as ~/src/grove.

- `core/` (crate sheaf-core): no Qt. `sane.rs` (libsane FFI: devices,
  options, scanning; one thread only), `imgproc.rs` (frames to images,
  deskew, content bounds/autocrop, rotate), `export.rs` (own PDF writer;
  searchable PDF via libtesseract's PDF renderer; PNG/JPEG), `pages.rs`
  (session page files with revisions for Undo), `settings.rs`.
  `cargo test -p sheaf-core`; device tests need SHEAF_SANE_TEST=1 and
  scripts/sane-test-env.sh.
- `src/`: `bridge.rs` (Sheaf controller declarations), `controller.rs`,
  `scanner.rs` (the scanner thread owning libsane), `desktop.rs` (grove,
  xdg-open, FileChooser portal).
- `cpp/native.cpp`: app creation (native text), icon provider, window grab.
  `cpp/global_menu.cpp`, `include/global_menu.h`, `qml/AppMenu.qml` are
  shared with grove: keep the copies the same.
- `qml/`: every file registered automatically (build.rs).

Rules (Ben's):
- Native text: set in native.cpp; build.rs rejects QtRendering/Curve.
  The window's shell has the 0.001 px nudge (topMargin + Translate x);
  popups carry `.001` padding.
- Never block the UI thread: scanner work goes to scanner.rs; disk and
  programs through `answer()` (asyncReply + qml/Async.qml).
- No KDE libraries. Links libsane/tesseract/leptonica; runs no scanner tools.
- Tooltips on every control; shortcuts and help topics in qml/Help.qml
  (menus and the Shortcuts page read them).
- Commit and push every working piece (`git commit -- <paths>`).

Headless test: `SHEAF_TEST="device=test:0;preview;scan;shot=x;save=DIR,pdf,ocr"`
with `--screenshot FILE`, QT_QPA_PLATFORM=offscreen,
DBUS_SESSION_BUS_ADDRESS=disabled: and scratch XDG_CONFIG_HOME/XDG_CACHE_HOME
(steps: Main.qml testTimer).
