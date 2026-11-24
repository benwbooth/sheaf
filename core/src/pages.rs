//! The scanned pages of this session: picture files in
//! ~/.cache/sheaf/session-<pid>/. Every change writes new files (a new
//! revision) and leaves the old ones, so Undo can go back to them; the
//! folder goes when the app quits (or at the next start, after a crash).

use crate::imgproc;
use anyhow::{Context, Result};
use image::DynamicImage;
use serde::Serialize;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

#[derive(Debug, Clone, Serialize)]
pub struct PageInfo {
    pub id: u64,
    pub rev: u64,
    /// The full picture (PNG).
    pub path: String,
    /// A small JPEG for the page list.
    pub thumb: String,
    pub width: u32,
    pub height: u32,
    pub dpi: f64,
}

pub struct Store {
    dir: PathBuf,
    next: AtomicU64,
}

/// Thumbnail size (pixels, longest side): sharp in the page list at 2×.
const THUMB: u32 = 420;

impl Store {
    pub fn new() -> Result<Store> {
        let root = crate::settings::cache_home().join("sheaf");
        std::fs::create_dir_all(&root)?;
        // Sessions of sheafs that are no longer running.
        for e in std::fs::read_dir(&root).into_iter().flatten().flatten() {
            let n = e.file_name().to_string_lossy().into_owned();
            if let Some(pid) = n.strip_prefix("session-").and_then(|p| p.parse::<u32>().ok()) {
                if pid != std::process::id() && !Path::new(&format!("/proc/{pid}")).exists() {
                    let _ = std::fs::remove_dir_all(e.path());
                }
            }
        }
        let dir = root.join(format!("session-{}", std::process::id()));
        std::fs::create_dir_all(&dir)?;
        Ok(Store { dir, next: AtomicU64::new(1) })
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }

    /// Remove this session's files (at quit).
    pub fn clear(&self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }

    /// A new page from a scan.
    pub fn add(&self, img: &DynamicImage, dpi: f64) -> Result<PageInfo> {
        let id = self.next.fetch_add(1, Ordering::Relaxed);
        self.write(id, 1, img, dpi)
    }

    fn write(&self, id: u64, rev: u64, img: &DynamicImage, dpi: f64) -> Result<PageInfo> {
        let path = self.dir.join(format!("page-{id}-r{rev}.png"));
        let thumb = self.dir.join(format!("page-{id}-r{rev}-thumb.jpg"));
        {
            let f = std::fs::File::create(&path).context("Couldn't keep the scanned page (is the disk full?)")?;
            let w = std::io::BufWriter::new(f);
            // Fast compression: pages are written often and kept only for
            // the session.
            let enc = image::codecs::png::PngEncoder::new_with_quality(w, image::codecs::png::CompressionType::Fast, image::codecs::png::FilterType::Sub);
            img.write_with_encoder(enc)?;
        }
        let small = imgproc::shrink(img, THUMB);
        let small = match small {
            DynamicImage::ImageLuma8(_) | DynamicImage::ImageRgb8(_) => small,
            DynamicImage::ImageLuma16(_) => DynamicImage::ImageLuma8(small.to_luma8()),
            _ => DynamicImage::ImageRgb8(small.to_rgb8()),
        };
        small.save_with_format(&thumb, image::ImageFormat::Jpeg)?;
        Ok(PageInfo {
            id,
            rev,
            path: path.to_string_lossy().into_owned(),
            thumb: thumb.to_string_lossy().into_owned(),
            width: img.width(),
            height: img.height(),
            dpi,
        })
    }

    /// Change a page: `op` is rotate:<degrees>, straighten, autocrop or
    /// crop:x0,y0,x1,y1 (fractions). Returns the new revision, or None when
    /// nothing changed (a straight page, nothing to crop).
    pub fn edit(&self, page: &PageInfo, op: &str) -> Result<Option<PageInfo>> {
        let img = image::open(&page.path).context("Couldn't read the page")?;
        let out = if let Some(d) = op.strip_prefix("rotate:") {
            Some(imgproc::rotate(&img, d.parse().unwrap_or(90)))
        } else if op == "straighten" {
            let (i, a) = imgproc::deskew(&img);
            (a != 0.0).then_some(i)
        } else if op == "autocrop" {
            let (i, cut) = imgproc::autocrop(&img);
            cut.then_some(i)
        } else if let Some(r) = op.strip_prefix("crop:") {
            let v: Vec<f64> = r.split(',').filter_map(|x| x.trim().parse().ok()).collect();
            (v.len() == 4).then(|| imgproc::crop_fraction(&img, (v[0], v[1], v[2], v[3])))
        } else {
            None
        };
        match out {
            // A revision number never used before (after an Undo the old
            // number would name a different picture, and views cache by
            // file name).
            Some(i) => Ok(Some(self.write(page.id, self.next.fetch_add(1, Ordering::Relaxed), &i, page.dpi)?)),
            None => Ok(None),
        }
    }
}
