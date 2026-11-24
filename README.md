# Sheaf

A document and photo scanner for Linux, in the spirit of macOS Image
Capture. Rust + Qt Quick (cxx-qt), no KDE libraries.

- Every SANE scanner: USB and network (AirScan/eSCL, WSD, saned), through
  libsane directly.
- Overview scan, then drag a box over what you want; paper-size presets;
  Select the Document picks the page found on the overview.
- Source (flatbed or document feeder), both sides (duplex), kind of picture
  (colour, gray, text), resolution, and every other option the scanner has
  (More Options; remembered per scanner).
- Many pages: the feeder scans until it's empty; on the flatbed each Scan
  adds a page. Drag pages to reorder; rotate, straighten (deskew), crop to
  the content or by hand; Undo.
- Save as one PDF (optionally searchable, with tesseract), or a PNG or
  JPEG per page; then show it in Grove or open it.
- Tooltips on everything, Help (F1) with search and a shortcut list, a
  first-run tour, Settings with a line about each one.

## Build and run

    nix run github:benwbooth/sheaf
    # or, working on it:
    nix develop -c cargo build && ./target/debug/sheaf

## Tests

    nix develop -c cargo test -p sheaf-core
    # scanning, with SANE's pretend `test` scanner:
    eval "$(scripts/sane-test-env.sh)"
    SHEAF_SANE_TEST=1 nix develop -c cargo test -p sheaf-core device_tests
    # the whole app, headless, with screenshots:
    QT_QPA_PLATFORM=offscreen DBUS_SESSION_BUS_ADDRESS=disabled: \
      SHEAF_TEST="device=test:0;preview;scan;shot=scanned" \
      ./target/debug/sheaf --screenshot /tmp/sheaf.png
