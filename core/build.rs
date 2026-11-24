// libsane (SANE's frontend library: every backend, USB and network), and
// libtesseract + leptonica for searchable PDFs. All found with pkg-config.
fn main() {
    for (lib, min) in [("sane-backends", "1.0"), ("tesseract", "4.0"), ("lept", "1.70")] {
        if let Err(e) = pkg_config::Config::new().atleast_version(min).probe(lib) {
            panic!("{lib} not found ({e}); build inside `nix develop`");
        }
    }
}
