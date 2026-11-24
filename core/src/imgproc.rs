//! Pictures: scans to images, straightening (deskew), cropping to the
//! page, turning, and the small copies the window shows.

use crate::sane::Frame;
use image::{imageops, DynamicImage, GrayImage, ImageBuffer, Luma, Rgb, RgbImage};

/// A scanned frame as an image. 16-bit scans stay 16-bit.
pub fn frame_to_image(f: Frame) -> DynamicImage {
    let (w, h) = (f.width, f.height);
    match (f.channels, f.depth) {
        (3, 16) => {
            let v: Vec<u16> = f.data.chunks_exact(2).map(|b| u16::from_ne_bytes([b[0], b[1]])).collect();
            ImageBuffer::<Rgb<u16>, _>::from_raw(w, h, v).map(DynamicImage::ImageRgb16).unwrap_or_else(|| blank(w, h))
        }
        (1, 16) => {
            let v: Vec<u16> = f.data.chunks_exact(2).map(|b| u16::from_ne_bytes([b[0], b[1]])).collect();
            ImageBuffer::<Luma<u16>, _>::from_raw(w, h, v).map(DynamicImage::ImageLuma16).unwrap_or_else(|| blank(w, h))
        }
        (3, _) => RgbImage::from_raw(w, h, f.data).map(DynamicImage::ImageRgb8).unwrap_or_else(|| blank(w, h)),
        _ => GrayImage::from_raw(w, h, f.data).map(DynamicImage::ImageLuma8).unwrap_or_else(|| blank(w, h)),
    }
}

fn blank(w: u32, h: u32) -> DynamicImage {
    DynamicImage::ImageLuma8(GrayImage::from_pixel(w.max(1), h.max(1), Luma([255])))
}

/// Rows of a scan in progress as an 8-bit image (for the live view),
/// shrunk to at most `max` pixels across.
pub fn partial_image(data: &[u8], width: u32, rows: u32, channels: u32, depth: u32, max: u32) -> Option<DynamicImage> {
    if rows == 0 || width == 0 {
        return None;
    }
    let row_bytes = (width * channels) as usize * if depth == 16 { 2 } else { 1 };
    let mut v = Vec::with_capacity((width * channels * rows) as usize);
    for row in data.chunks(if depth == 1 { ((width * channels) as usize).div_ceil(8) } else { row_bytes }).take(rows as usize) {
        match depth {
            1 => {
                for x in 0..(width * channels) as usize {
                    let bit = row.get(x / 8).map(|b| b >> (7 - (x % 8)) & 1).unwrap_or(0);
                    v.push(if bit == 1 { 0 } else { 255 });
                }
            }
            16 => v.extend(row.chunks_exact(2).map(|b| (u16::from_ne_bytes([b[0], b[1]]) >> 8) as u8)),
            _ => v.extend_from_slice(row),
        }
    }
    v.resize((width * channels * rows) as usize, 255);
    let img = if channels == 3 {
        DynamicImage::ImageRgb8(RgbImage::from_raw(width, rows, v)?)
    } else {
        DynamicImage::ImageLuma8(GrayImage::from_raw(width, rows, v)?)
    };
    Some(shrink(&img, max))
}

/// At most `max` pixels across and down (never enlarged).
pub fn shrink(img: &DynamicImage, max: u32) -> DynamicImage {
    if img.width() <= max && img.height() <= max {
        return img.clone();
    }
    img.resize(max, max, imageops::FilterType::Triangle)
}

/// Whether a picture has only black and white in it (line art).
pub fn is_bilevel(img: &DynamicImage) -> bool {
    match img {
        DynamicImage::ImageLuma8(g) => g.pixels().all(|p| p.0[0] == 0 || p.0[0] == 255),
        _ => false,
    }
}

/// Turn by a multiple of 90° (clockwise for positive).
pub fn rotate(img: &DynamicImage, degrees: i32) -> DynamicImage {
    match degrees.rem_euclid(360) {
        90 => img.rotate90(),
        180 => img.rotate180(),
        270 => img.rotate270(),
        _ => img.clone(),
    }
}

/// A small gray copy for analysis, with the scale from it to the original.
fn analysis_copy(img: &DynamicImage, max: u32) -> (GrayImage, f64) {
    let g = shrink(img, max).to_luma8();
    let s = img.width() as f64 / g.width().max(1) as f64;
    (g, s)
}

/// The colour around the edges (the lid or the page): the median of the
/// outermost pixels.
fn border_level(g: &GrayImage) -> u8 {
    let (w, h) = g.dimensions();
    let mut v: Vec<u8> = Vec::new();
    for x in 0..w {
        v.push(g.get_pixel(x, 0).0[0]);
        v.push(g.get_pixel(x, h - 1).0[0]);
    }
    for y in 0..h {
        v.push(g.get_pixel(0, y).0[0]);
        v.push(g.get_pixel(w - 1, y).0[0]);
    }
    v.sort_unstable();
    v[v.len() / 2]
}

/// The level that splits ink from paper (Otsu's method).
fn otsu(g: &GrayImage) -> u8 {
    let mut hist = [0u64; 256];
    for p in g.pixels() {
        hist[p.0[0] as usize] += 1;
    }
    let total: u64 = hist.iter().sum();
    let sum: f64 = hist.iter().enumerate().map(|(i, &c)| i as f64 * c as f64).sum();
    let (mut sum_b, mut w_b, mut best, mut level) = (0.0, 0u64, 0.0, 128u8);
    for (t, &c) in hist.iter().enumerate() {
        w_b += c;
        if w_b == 0 {
            continue;
        }
        let w_f = total - w_b;
        if w_f == 0 {
            break;
        }
        sum_b += t as f64 * c as f64;
        let m_b = sum_b / w_b as f64;
        let m_f = (sum - sum_b) / w_f as f64;
        let between = w_b as f64 * w_f as f64 * (m_b - m_f).powi(2);
        if between > best {
            best = between;
            level = t as u8;
        }
    }
    level
}

/// How far the lines of text are tilted, in degrees (positive: the page is
/// turned clockwise). Projection profiles: at the right angle the rows of
/// ink line up and the profile is the most uneven. None when there's too
/// little ink to tell.
pub fn skew_angle(img: &DynamicImage) -> Option<f64> {
    let (g, _) = analysis_copy(img, 1000);
    let level = otsu(&g).min(200);
    let ink: Vec<(f64, f64)> = g
        .enumerate_pixels()
        .filter(|(_, _, p)| p.0[0] <= level)
        .map(|(x, y, _)| (x as f64, y as f64))
        .collect();
    let (w, h) = g.dimensions();
    if ink.len() < 200 || ink.len() as f64 > 0.5 * (w * h) as f64 {
        return None;
    }
    let diag = ((w * w + h * h) as f64).sqrt();
    let bins = (diag * 2.0) as usize + 4;
    let score = |deg: f64| -> f64 {
        let (s, c) = deg.to_radians().sin_cos();
        let mut hist = vec![0u32; bins];
        for &(x, y) in &ink {
            let r = y * c - x * s + diag;
            let i = r as usize;
            if i < bins {
                hist[i] += 1;
            }
        }
        hist.windows(2).map(|p| (p[1] as f64 - p[0] as f64).powi(2)).sum()
    };
    let mut best = (0.0, score(0.0));
    let base = best.1;
    let mut a = -10.0;
    while a <= 10.0 {
        let s = score(a);
        if s > best.1 {
            best = (a, s);
        }
        a += 0.5;
    }
    let centre = best.0;
    let mut a = centre - 0.5;
    while a <= centre + 0.5 {
        let s = score(a);
        if s > best.1 {
            best = (a, s);
        }
        a += 0.05;
    }
    // Not clearly better than level: leave it.
    if best.0.abs() < 0.1 || best.1 < base * 1.02 {
        return Some(0.0);
    }
    Some(best.0)
}

/// Turn by any angle (degrees, clockwise), filling the corners with the
/// page's own colour. Bilinear.
pub fn rotate_free(img: &DynamicImage, degrees: f64) -> DynamicImage {
    if degrees.abs() < 0.01 {
        return img.clone();
    }
    let rgb = img.to_rgb8();
    let (w, h) = rgb.dimensions();
    let fill = {
        let mut v: Vec<[u8; 3]> = Vec::new();
        for x in (0..w).step_by((w / 64).max(1) as usize) {
            v.push(rgb.get_pixel(x, 0).0);
            v.push(rgb.get_pixel(x, h - 1).0);
        }
        v.sort_unstable_by_key(|p| p[0] as u32 + p[1] as u32 + p[2] as u32);
        v[v.len() / 2]
    };
    let (s, c) = (-degrees).to_radians().sin_cos();
    let (cx, cy) = (w as f64 / 2.0, h as f64 / 2.0);
    let mut out = RgbImage::new(w, h);
    for (x, y, px) in out.enumerate_pixels_mut() {
        let dx = x as f64 + 0.5 - cx;
        let dy = y as f64 + 0.5 - cy;
        let sx = dx * c - dy * s + cx - 0.5;
        let sy = dx * s + dy * c + cy - 0.5;
        if sx < 0.0 || sy < 0.0 || sx > (w - 1) as f64 || sy > (h - 1) as f64 {
            *px = Rgb(fill);
            continue;
        }
        let (x0, y0) = (sx.floor() as u32, sy.floor() as u32);
        let (x1, y1) = ((x0 + 1).min(w - 1), (y0 + 1).min(h - 1));
        let (fx, fy) = (sx - x0 as f64, sy - y0 as f64);
        let p = |x, y| rgb.get_pixel(x, y).0;
        let (a, b, cc, d) = (p(x0, y0), p(x1, y0), p(x0, y1), p(x1, y1));
        let mut o = [0u8; 3];
        for k in 0..3 {
            let top = a[k] as f64 * (1.0 - fx) + b[k] as f64 * fx;
            let bot = cc[k] as f64 * (1.0 - fx) + d[k] as f64 * fx;
            o[k] = (top * (1.0 - fy) + bot * fy).round() as u8;
        }
        *px = Rgb(o);
    }
    let out = DynamicImage::ImageRgb8(out);
    match img {
        DynamicImage::ImageLuma8(_) | DynamicImage::ImageLuma16(_) => DynamicImage::ImageLuma8(out.to_luma8()),
        _ => out,
    }
}

/// Straighten a page. Returns the angle it was turned by.
pub fn deskew(img: &DynamicImage) -> (DynamicImage, f64) {
    match skew_angle(img) {
        Some(a) if a.abs() >= 0.1 => (rotate_free(img, -a), -a),
        _ => (img.clone(), 0.0),
    }
}

/// The part of the scan that holds the document or its content, as
/// fractions (x0, y0, x1, y1) of the whole. Anything that differs from the
/// colour at the edges counts; specks and a thin dark rim (the scanner
/// glass's edge) don't. None when it would keep (nearly) everything or
/// finds nothing.
pub fn content_bounds(img: &DynamicImage) -> Option<(f64, f64, f64, f64)> {
    let (g, _) = analysis_copy(img, 800);
    let (w, h) = g.dimensions();
    if w < 16 || h < 16 {
        return None;
    }
    let bg = border_level(&g) as i32;
    let diff = 28;
    let differs = |x: u32, y: u32| (g.get_pixel(x, y).0[0] as i32 - bg).abs() > diff;
    // Ignore a 1% rim: scanners often show a dark line at the glass's edge.
    let mx = (w / 100).max(1);
    let my = (h / 100).max(1);
    let min_row = ((w - 2 * mx) as f64 * 0.004).max(2.0) as u32;
    let min_col = ((h - 2 * my) as f64 * 0.004).max(2.0) as u32;
    let rows: Vec<bool> = (0..h).map(|y| y >= my && y < h - my && (mx..w - mx).filter(|&x| differs(x, y)).count() as u32 >= min_row).collect();
    let cols: Vec<bool> = (0..w).map(|x| x >= mx && x < w - mx && (my..h - my).filter(|&y| differs(x, y)).count() as u32 >= min_col).collect();
    let first = |v: &[bool]| v.iter().position(|&b| b);
    let last = |v: &[bool]| v.iter().rposition(|&b| b);
    let (y0, y1, x0, x1) = (first(&rows)?, last(&rows)?, first(&cols)?, last(&cols)?);
    // A small margin round the content.
    let pad = (w.min(h) as f64 * 0.012) as usize;
    let x0 = x0.saturating_sub(pad) as f64 / w as f64;
    let y0 = y0.saturating_sub(pad) as f64 / h as f64;
    let x1 = ((x1 + 1 + pad).min(w as usize)) as f64 / w as f64;
    let y1 = ((y1 + 1 + pad).min(h as usize)) as f64 / h as f64;
    let area = (x1 - x0) * (y1 - y0);
    if area > 0.96 || area < 0.002 {
        return None;
    }
    Some((x0, y0, x1, y1))
}

/// Cut out a part given as fractions of the whole.
pub fn crop_fraction(img: &DynamicImage, r: (f64, f64, f64, f64)) -> DynamicImage {
    let (w, h) = (img.width() as f64, img.height() as f64);
    let x0 = (r.0.clamp(0.0, 1.0) * w).floor() as u32;
    let y0 = (r.1.clamp(0.0, 1.0) * h).floor() as u32;
    let x1 = (r.2.clamp(0.0, 1.0) * w).ceil() as u32;
    let y1 = (r.3.clamp(0.0, 1.0) * h).ceil() as u32;
    if x1 <= x0 + 1 || y1 <= y0 + 1 {
        return img.clone();
    }
    img.crop_imm(x0, y0, x1 - x0, y1 - y0)
}

/// Crop to the document. Returns whether anything was cut.
pub fn autocrop(img: &DynamicImage) -> (DynamicImage, bool) {
    match content_bounds(img) {
        Some(r) => (crop_fraction(img, r), true),
        None => (img.clone(), false),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn page_with_lines(angle: f64) -> DynamicImage {
        let mut g = GrayImage::from_pixel(800, 1000, Luma([250]));
        let (s, c) = angle.to_radians().sin_cos();
        for line in 0..20 {
            let y = 150.0 + line as f64 * 35.0;
            for x in 100..700 {
                if (x / 9) % 4 == 3 {
                    continue; // gaps between "words"
                }
                for t in 0..6 {
                    let (dx, dy) = (x as f64 - 400.0, y + t as f64 - 500.0);
                    let (rx, ry) = (dx * c - dy * s + 400.0, dx * s + dy * c + 500.0);
                    if rx >= 0.0 && ry >= 0.0 && rx < 800.0 && ry < 1000.0 {
                        g.put_pixel(rx as u32, ry as u32, Luma([20]));
                    }
                }
            }
        }
        DynamicImage::ImageLuma8(g)
    }

    #[test]
    fn finds_skew() {
        let a = skew_angle(&page_with_lines(3.0)).unwrap();
        assert!((a - 3.0).abs() < 0.3, "found {a}");
        let a = skew_angle(&page_with_lines(-1.5)).unwrap();
        assert!((a + 1.5).abs() < 0.3, "found {a}");
        let a = skew_angle(&page_with_lines(0.0)).unwrap();
        assert!(a.abs() < 0.2, "found {a}");
    }

    #[test]
    fn deskew_straightens() {
        let (fixed, turned) = deskew(&page_with_lines(4.0));
        assert!((turned + 4.0).abs() < 0.4, "turned {turned}");
        let a = skew_angle(&fixed).unwrap();
        assert!(a.abs() < 0.3, "still {a}");
    }

    #[test]
    fn crops_to_document() {
        // A light page on a dark lid.
        let mut g = GrayImage::from_pixel(1000, 1000, Luma([40]));
        for y in 200..800 {
            for x in 300..700 {
                g.put_pixel(x, y, Luma([245]));
            }
        }
        let r = content_bounds(&DynamicImage::ImageLuma8(g)).unwrap();
        assert!((r.0 - 0.3).abs() < 0.03 && (r.1 - 0.2).abs() < 0.03, "{r:?}");
        assert!((r.2 - 0.7).abs() < 0.03 && (r.3 - 0.8).abs() < 0.03, "{r:?}");
    }

    #[test]
    fn blank_page_isnt_cropped() {
        let g = GrayImage::from_pixel(500, 500, Luma([250]));
        assert!(content_bounds(&DynamicImage::ImageLuma8(g)).is_none());
    }
}
