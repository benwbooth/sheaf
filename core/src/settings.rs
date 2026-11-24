//! sheaf's settings (~/.config/sheaf/settings.json). Everything has a
//! default; unknown or missing keys are fine.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

pub fn config_home() -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).filter(|p| p.is_absolute()).unwrap_or_else(|| home().join(".config"))
}

pub fn cache_home() -> PathBuf {
    std::env::var_os("XDG_CACHE_HOME").map(PathBuf::from).filter(|p| p.is_absolute()).unwrap_or_else(|| home().join(".cache"))
}

pub fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"))
}

/// An XDG user folder (DOCUMENTS, PICTURES, DESKTOP, DOWNLOAD) from
/// user-dirs.dirs, else ~/Documents and the like.
pub fn user_dir(key: &str) -> PathBuf {
    let h = home();
    if let Ok(t) = std::fs::read_to_string(config_home().join("user-dirs.dirs")) {
        for line in t.lines() {
            if let Some(rest) = line.strip_prefix(&format!("XDG_{key}_DIR=")) {
                let v = rest.trim().trim_matches('"').replace("$HOME", &h.to_string_lossy());
                if !v.is_empty() {
                    return PathBuf::from(v);
                }
            }
        }
    }
    h.join(match key {
        "PICTURES" => "Pictures",
        "DESKTOP" => "Desktop",
        "DOWNLOAD" => "Downloads",
        _ => "Documents",
    })
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    /// "auto" (follow hearth), "light", "dark"
    pub appearance: String,
    /// The scanner used last (opened again at start when it's there).
    pub last_device: String,
    /// Scan settings remembered per scanner: {device: {option: value}}.
    pub device_options: serde_json::Map<String, serde_json::Value>,
    /// pdf, png, jpeg
    pub format: String,
    pub jpeg_quality: u8,
    /// Make PDFs searchable (text recognition).
    pub ocr: bool,
    /// tesseract language codes joined by '+'.
    pub ocr_language: String,
    pub save_folder: String,
    /// The suggested name: {date} {time} are filled in.
    pub name_pattern: String,
    /// After saving: "nothing", "grove" (show it in grove), "open".
    pub after_save: String,
    /// Straighten / crop each new page.
    pub auto_straighten: bool,
    pub auto_crop: bool,
    /// Show the advanced scanner options in More Options.
    pub show_advanced: bool,
    pub welcomed: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            appearance: "auto".into(),
            last_device: String::new(),
            device_options: Default::default(),
            format: "pdf".into(),
            jpeg_quality: 85,
            ocr: false,
            ocr_language: "eng".into(),
            save_folder: user_dir("DOCUMENTS").to_string_lossy().into_owned(),
            name_pattern: "Scan {date} at {time}".into(),
            after_save: "grove".into(),
            auto_straighten: false,
            auto_crop: false,
            show_advanced: false,
            welcomed: false,
        }
    }
}

impl Settings {
    pub fn path() -> PathBuf {
        config_home().join("sheaf").join("settings.json")
    }

    pub fn load() -> Settings {
        std::fs::read_to_string(Self::path()).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
    }

    pub fn save(&self) -> std::io::Result<()> {
        let p = Self::path();
        if let Some(d) = p.parent() {
            std::fs::create_dir_all(d)?;
        }
        let tmp = p.with_extension("json.part");
        std::fs::write(&tmp, serde_json::to_string_pretty(self).unwrap_or_default())?;
        std::fs::rename(tmp, p)
    }
}
