//! Saving scans: PDF (one file, every page; optionally with searchable
//! text from tesseract), PNG or JPEG (a file per page).

use anyhow::{anyhow, bail, Context, Result};
use image::{codecs::jpeg::JpegEncoder, DynamicImage, ImageEncoder};
use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

use crate::imgproc::is_bilevel;

/// A page to save: its picture file and resolution.
#[derive(Debug, Clone)]
pub struct PageSrc {
    pub path: PathBuf,
    pub dpi: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Format {
    Pdf,
    Png,
    Jpeg,
}

impl Format {
    pub fn parse(s: &str) -> Format {
        match s {
            "png" => Format::Png,
            "jpeg" | "jpg" => Format::Jpeg,
            _ => Format::Pdf,
        }
    }
    pub fn ext(self) -> &'static str {
        match self {
            Format::Pdf => "pdf",
            Format::Png => "png",
            Format::Jpeg => "jpg",
        }
    }
}

pub struct Options {
    pub format: Format,
    /// JPEG quality (and of the pictures inside PDFs), 1–100.
    pub quality: u8,
    /// Searchable PDF: tesseract's language codes joined by '+' ("eng").
    pub ocr: Option<String>,
    pub title: String,
}

/// `name.ext` in `dir`, or `name 2.ext`, `name 3.ext`... when taken.
pub fn unique_path(dir: &Path, name: &str, ext: &str) -> PathBuf {
    let first = dir.join(format!("{name}.{ext}"));
    if !first.exists() {
        return first;
    }
    for n in 2.. {
        let p = dir.join(format!("{name} {n}.{ext}"));
        if !p.exists() {
            return p;
        }
    }
    unreachable!()
}

/// Save the pages. Returns the files written. `progress(done, total)`.
pub fn save(pages: &[PageSrc], dir: &Path, name: &str, opts: &Options, cancel: &AtomicBool, mut progress: impl FnMut(usize, usize)) -> Result<Vec<PathBuf>> {
    if pages.is_empty() {
        bail!("There are no pages to save.");
    }
    std::fs::create_dir_all(dir).with_context(|| format!("Couldn't make the folder {}", dir.display()))?;
    let name = sanitize(name);
    match opts.format {
        Format::Pdf => {
            let dest = unique_path(dir, &name, "pdf");
            match &opts.ocr {
                Some(lang) => ocr_pdf(pages, &dest, lang, opts, cancel, &mut progress)?,
                None => plain_pdf(pages, &dest, opts, cancel, &mut progress)?,
            }
            Ok(vec![dest])
        }
        f => {
            let mut out = Vec::new();
            for (i, p) in pages.iter().enumerate() {
                if cancel.load(Ordering::Relaxed) {
                    bail!("cancelled");
                }
                let n = if pages.len() == 1 { name.clone() } else { format!("{name} {}", i + 1) };
                let dest = unique_path(dir, &n, f.ext());
                let img = image::open(&p.path).with_context(|| format!("Couldn't read page {}", i + 1))?;
                write_image(&img, &dest, f, opts.quality, p.dpi)?;
                out.push(dest);
                progress(i + 1, pages.len());
            }
            Ok(out)
        }
    }
}

fn sanitize(name: &str) -> String {
    let n: String = name.trim().chars().map(|c| if c == '/' || c == '\0' { '-' } else { c }).collect();
    if n.is_empty() || n == "." || n == ".." {
        "Scan".into()
    } else {
        n
    }
}

/// Write one picture (PNG or JPEG), going through a temporary file so a
/// half-written file never appears under the real name.
pub fn write_image(img: &DynamicImage, dest: &Path, f: Format, quality: u8, dpi: f64) -> Result<()> {
    let tmp = dest.with_file_name(format!(".{}.part", dest.file_name().unwrap_or_default().to_string_lossy()));
    {
        let file = std::fs::File::create(&tmp).with_context(|| format!("Couldn't write {}", dest.display()))?;
        let mut w = std::io::BufWriter::new(file);
        match f {
            Format::Jpeg => {
                let img = to8(img);
                let mut enc = JpegEncoder::new_with_quality(&mut w, quality.clamp(1, 100));
                let d = dpi.round().clamp(1.0, 65535.0) as u16;
                enc.set_pixel_density(image::codecs::jpeg::PixelDensity::dpi(d));
                enc.encode_image(&img)?;
            }
            _ => {
                let enc = image::codecs::png::PngEncoder::new_with_quality(&mut w, image::codecs::png::CompressionType::Default, image::codecs::png::FilterType::Adaptive);
                enc.write_image(img.as_bytes(), img.width(), img.height(), img.color().into())?;
            }
        }
        w.flush()?;
    }
    std::fs::rename(&tmp, dest)?;
    Ok(())
}

/// 8 bits per sample, gray or RGB (what JPEG and PDF pictures hold).
fn to8(img: &DynamicImage) -> DynamicImage {
    match img {
        DynamicImage::ImageLuma8(_) | DynamicImage::ImageRgb8(_) => img.clone(),
        DynamicImage::ImageLuma16(_) | DynamicImage::ImageLumaA8(_) | DynamicImage::ImageLumaA16(_) => DynamicImage::ImageLuma8(img.to_luma8()),
        _ => DynamicImage::ImageRgb8(img.to_rgb8()),
    }
}

// ---- PDF without text: a page per picture, sized from its resolution ----

struct PdfWriter {
    out: Vec<u8>,
    offsets: Vec<usize>,
}

impl PdfWriter {
    fn new() -> PdfWriter {
        let mut out = Vec::new();
        out.extend_from_slice(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n");
        PdfWriter { out, offsets: Vec::new() }
    }
    /// Start object `n` (objects must be written in order 1, 2, 3...).
    fn obj(&mut self, n: usize, body: &[u8]) {
        while self.offsets.len() < n {
            self.offsets.push(0);
        }
        self.offsets[n - 1] = self.out.len();
        self.out.extend_from_slice(format!("{n} 0 obj\n").as_bytes());
        self.out.extend_from_slice(body);
        self.out.extend_from_slice(b"\nendobj\n");
    }
    fn stream(&mut self, n: usize, dict: &str, data: &[u8]) {
        let mut b = format!("<< {dict} /Length {} >>\nstream\n", data.len()).into_bytes();
        b.extend_from_slice(data);
        b.extend_from_slice(b"\nendstream");
        self.obj(n, &b);
    }
    fn finish(mut self, root: usize, info: usize) -> Vec<u8> {
        let xref = self.out.len();
        let n = self.offsets.len() + 1;
        self.out.extend_from_slice(format!("xref\n0 {n}\n0000000000 65535 f \n").as_bytes());
        for o in &self.offsets {
            self.out.extend_from_slice(format!("{o:010} 00000 n \n").as_bytes());
        }
        self.out.extend_from_slice(format!("trailer\n<< /Size {n} /Root {root} 0 R /Info {info} 0 R >>\nstartxref\n{xref}\n%%EOF\n").as_bytes());
        self.out
    }
}

/// A PDF string: (text) with escapes, or UTF-16 when not plain ASCII.
fn pdf_string(s: &str) -> String {
    if s.is_ascii() {
        let e: String = s.chars().flat_map(|c| match c {
            '(' | ')' | '\\' => vec!['\\', c],
            c => vec![c],
        }).collect();
        format!("({e})")
    } else {
        let mut hex = String::from("<FEFF");
        for u in s.encode_utf16() {
            hex.push_str(&format!("{u:04X}"));
        }
        hex.push('>');
        hex
    }
}

fn plain_pdf(pages: &[PageSrc], dest: &Path, opts: &Options, cancel: &AtomicBool, progress: &mut impl FnMut(usize, usize)) -> Result<()> {
    let mut w = PdfWriter::new();
    // 1 catalog, 2 pages, 3 info, then 3 objects per page.
    let kids: Vec<String> = (0..pages.len()).map(|i| format!("{} 0 R", 4 + i * 3)).collect();
    w.obj(1, b"<< /Type /Catalog /Pages 2 0 R >>");
    w.obj(2, format!("<< /Type /Pages /Count {} /Kids [{}] >>", pages.len(), kids.join(" ")).as_bytes());
    w.obj(3, format!("<< /Title {} /Creator (sheaf) /Producer (sheaf) >>", pdf_string(&opts.title)).as_bytes());
    for (i, p) in pages.iter().enumerate() {
        if cancel.load(Ordering::Relaxed) {
            bail!("cancelled");
        }
        let img = image::open(&p.path).with_context(|| format!("Couldn't read page {}", i + 1))?;
        let (pw, ph) = (img.width(), img.height());
        let dpi = if p.dpi > 0.0 { p.dpi } else { 300.0 };
        let (wpt, hpt) = (pw as f64 * 72.0 / dpi, ph as f64 * 72.0 / dpi);
        let (page, content, xobj) = (4 + i * 3, 5 + i * 3, 6 + i * 3);
        w.obj(page, format!("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {wpt:.3} {hpt:.3}] /Resources << /XObject << /Im0 {xobj} 0 R >> >> /Contents {content} 0 R >>").as_bytes());
        let c = format!("q {wpt:.3} 0 0 {hpt:.3} 0 0 cm /Im0 Do Q");
        w.stream(content, "", c.as_bytes());
        if is_bilevel(&img) {
            // Line art: 1 bit per pixel, deflated (0 black, 1 white).
            let g = img.to_luma8();
            let row = (pw as usize).div_ceil(8);
            let mut bits = vec![0u8; row * ph as usize];
            for (x, y, px) in g.enumerate_pixels() {
                if px.0[0] > 127 {
                    bits[y as usize * row + x as usize / 8] |= 0x80 >> (x % 8);
                }
            }
            let mut z = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::default());
            z.write_all(&bits)?;
            let data = z.finish()?;
            w.stream(xobj, &format!("/Type /XObject /Subtype /Image /Width {pw} /Height {ph} /ColorSpace /DeviceGray /BitsPerComponent 1 /Filter /FlateDecode"), &data);
        } else {
            let img = to8(&img);
            let cs = if matches!(img, DynamicImage::ImageLuma8(_)) { "/DeviceGray" } else { "/DeviceRGB" };
            let mut data = Vec::new();
            JpegEncoder::new_with_quality(&mut data, opts.quality.clamp(1, 100)).encode_image(&img)?;
            w.stream(xobj, &format!("/Type /XObject /Subtype /Image /Width {pw} /Height {ph} /ColorSpace {cs} /BitsPerComponent 8 /Filter /DCTDecode"), &data);
        }
        progress(i + 1, pages.len());
    }
    let bytes = w.finish(1, 3);
    let tmp = dest.with_file_name(format!(".{}.part", dest.file_name().unwrap_or_default().to_string_lossy()));
    std::fs::write(&tmp, bytes).with_context(|| format!("Couldn't write {}", dest.display()))?;
    std::fs::rename(&tmp, dest)?;
    Ok(())
}

// ---- searchable PDF: tesseract's own PDF renderer (the picture with an
// invisible text layer over it) ----

#[allow(non_camel_case_types)]
mod tess {
    use super::*;
    pub type TessBaseAPI = c_void;
    pub type TessResultRenderer = c_void;
    pub type Pix = c_void;


    extern "C" {
        pub fn TessBaseAPICreate() -> *mut TessBaseAPI;
        pub fn TessBaseAPIDelete(h: *mut TessBaseAPI);
        pub fn TessBaseAPIEnd(h: *mut TessBaseAPI);
        pub fn TessBaseAPIInit3(h: *mut TessBaseAPI, datapath: *const c_char, language: *const c_char) -> c_int;
        pub fn TessBaseAPIGetDatapath(h: *mut TessBaseAPI) -> *const c_char;
        pub fn TessPDFRendererCreate(outputbase: *const c_char, datadir: *const c_char, textonly: c_int) -> *mut TessResultRenderer;
        pub fn TessDeleteResultRenderer(r: *mut TessResultRenderer);
        pub fn TessResultRendererBeginDocument(r: *mut TessResultRenderer, title: *const c_char) -> c_int;
        pub fn TessResultRendererEndDocument(r: *mut TessResultRenderer) -> c_int;
        pub fn TessBaseAPIProcessPage(h: *mut TessBaseAPI, pix: *mut Pix, page_index: c_int, filename: *const c_char, retry_config: *const c_char, timeout_ms: c_int, renderer: *mut TessResultRenderer) -> c_int;
    }


    extern "C" {
        pub fn pixRead(filename: *const c_char) -> *mut Pix;
        pub fn pixSetResolution(pix: *mut Pix, x: c_int, y: c_int) -> c_int;
        pub fn pixDestroy(pix: *mut *mut Pix);
    }
}

/// Where tesseract's language files are (SHEAF_TESSDATA, set by the
/// package, else TESSDATA_PREFIX).
pub fn tessdata_dir() -> Option<PathBuf> {
    for v in ["SHEAF_TESSDATA", "TESSDATA_PREFIX"] {
        if let Some(p) = std::env::var_os(v).map(PathBuf::from) {
            if p.is_dir() {
                return Some(p);
            }
        }
    }
    None
}

/// The text-recognition languages installed ("eng", "deu"...), without
/// osd (orientation only).
pub fn ocr_languages() -> Vec<String> {
    let Some(dir) = tessdata_dir() else { return Vec::new() };
    let mut v: Vec<String> = std::fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| e.file_name().to_str()?.strip_suffix(".traineddata").map(String::from))
        .filter(|n| n != "osd" && n != "equ")
        .collect();
    v.sort();
    v
}

fn ocr_pdf(pages: &[PageSrc], dest: &Path, lang: &str, opts: &Options, cancel: &AtomicBool, progress: &mut impl FnMut(usize, usize)) -> Result<()> {
    let dir = dest.parent().unwrap_or(Path::new("."));
    let work = tempdir_in(dir)?;
    let result = (|| -> Result<()> {
        let datapath = tessdata_dir().map(|p| CString::new(p.to_string_lossy().as_bytes()).unwrap());
        let lang_c = CString::new(lang)?;
        let base = work.join("out");
        let base_c = CString::new(base.to_string_lossy().as_bytes())?;
        let title_c = CString::new(opts.title.replace('\0', ""))?;
        unsafe {
            let api = tess::TessBaseAPICreate();
            if tess::TessBaseAPIInit3(api, datapath.as_ref().map_or(std::ptr::null(), |c| c.as_ptr()), lang_c.as_ptr()) != 0 {
                tess::TessBaseAPIDelete(api);
                bail!("Text recognition couldn't start: the language “{lang}” isn't installed.");
            }
            let dp = tess::TessBaseAPIGetDatapath(api);
            let dp = CStr::from_ptr(dp).to_owned();
            let r = tess::TessPDFRendererCreate(base_c.as_ptr(), dp.as_ptr(), 0);
            let cleanup = |api, r| {
                tess::TessDeleteResultRenderer(r);
                tess::TessBaseAPIEnd(api);
                tess::TessBaseAPIDelete(api);
            };
            if r.is_null() || tess::TessResultRendererBeginDocument(r, title_c.as_ptr()) == 0 {
                cleanup(api, r);
                bail!("Text recognition couldn't start the PDF.");
            }
            for (i, p) in pages.iter().enumerate() {
                if cancel.load(Ordering::Relaxed) {
                    cleanup(api, r);
                    bail!("cancelled");
                }
                // tesseract puts JPEG files in the PDF as they are; other
                // pictures it re-encodes losslessly. So: JPEG for photos
                // and gray pages, PNG for line art.
                let img = image::open(&p.path).with_context(|| format!("Couldn't read page {}", i + 1))?;
                let (file, f) = if is_bilevel(&img) { (work.join(format!("p{i}.png")), Format::Png) } else { (work.join(format!("p{i}.jpg")), Format::Jpeg) };
                write_image(&to8(&img), &file, f, opts.quality, p.dpi)?;
                let fc = CString::new(file.to_string_lossy().as_bytes())?;
                let mut pix = tess::pixRead(fc.as_ptr());
                if pix.is_null() {
                    cleanup(api, r);
                    bail!("Text recognition couldn't read page {}.", i + 1);
                }
                let dpi = p.dpi.round().max(1.0) as c_int;
                tess::pixSetResolution(pix, dpi, dpi);
                let ok = tess::TessBaseAPIProcessPage(api, pix, i as c_int, fc.as_ptr(), std::ptr::null(), 0, r);
                tess::pixDestroy(&mut pix);
                if ok == 0 {
                    cleanup(api, r);
                    bail!("Text recognition failed on page {}.", i + 1);
                }
                let _ = std::fs::remove_file(&file);
                progress(i + 1, pages.len());
            }
            tess::TessResultRendererEndDocument(r);
            cleanup(api, r);
        }
        let made = base.with_extension("pdf");
        std::fs::rename(&made, dest).or_else(|_| std::fs::copy(&made, dest).map(|_| ())).map_err(|e| anyhow!("Couldn't write {}: {e}", dest.display()))?;
        Ok(())
    })();
    let _ = std::fs::remove_dir_all(&work);
    result
}

fn tempdir_in(dir: &Path) -> Result<PathBuf> {
    for n in 0..1000 {
        let p = dir.join(format!(".sheaf-{}-{n}", std::process::id()));
        if std::fs::create_dir(&p).is_ok() {
            return Ok(p);
        }
    }
    bail!("Couldn't make a work folder in {}", dir.display())
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{GrayImage, Luma, Rgb, RgbImage};

    fn scratch(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("sheaf-test-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn pdf_has_every_page() {
        let d = scratch("pdf");
        let a = d.join("a.png");
        let b = d.join("b.png");
        RgbImage::from_pixel(85, 110, Rgb([200, 10, 10])).save(&a).unwrap();
        GrayImage::from_fn(85, 110, |x, _| Luma([if x % 2 == 0 { 0 } else { 255 }])).save(&b).unwrap();
        let pages = vec![PageSrc { path: a, dpi: 10.0 }, PageSrc { path: b, dpi: 10.0 }];
        let opts = Options { format: Format::Pdf, quality: 80, ocr: None, title: "Test (1)".into() };
        let out = save(&pages, &d, "Scan", &opts, &AtomicBool::new(false), |_, _| {}).unwrap();
        let bytes = std::fs::read(&out[0]).unwrap();
        let s = String::from_utf8_lossy(&bytes);
        assert!(s.starts_with("%PDF-1.4"));
        assert!(s.contains("/Count 2"));
        assert!(s.contains("/MediaBox [0 0 612.000 792.000]"));
        assert!(s.contains("/BitsPerComponent 1"));
        assert!(s.contains("/DCTDecode"));
        // A second save doesn't replace the first.
        let out2 = save(&pages, &d, "Scan", &opts, &AtomicBool::new(false), |_, _| {}).unwrap();
        assert!(out2[0].ends_with("Scan 2.pdf"));
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn images_numbered() {
        let d = scratch("img");
        let a = d.join("a.png");
        RgbImage::from_pixel(10, 10, Rgb([1, 2, 3])).save(&a).unwrap();
        let pages = vec![PageSrc { path: a.clone(), dpi: 300.0 }, PageSrc { path: a, dpi: 300.0 }];
        let opts = Options { format: Format::Jpeg, quality: 90, ocr: None, title: String::new() };
        let out = save(&pages, &d, "Receipt", &opts, &AtomicBool::new(false), |_, _| {}).unwrap();
        assert!(out[0].ends_with("Receipt 1.jpg") && out[1].ends_with("Receipt 2.jpg"));
        let _ = std::fs::remove_dir_all(&d);
    }
}
