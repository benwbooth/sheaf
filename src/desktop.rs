//! The desktop around sheaf: showing a saved file in grove, opening it,
//! and the desktop's folder chooser (the FileChooser portal, which grove
//! provides). Called from background threads only.

use anyhow::{anyhow, bail, Result};
use std::collections::HashMap;
use std::process::{Command, Stdio};
use zbus::zvariant::{OwnedValue, Value};

fn run_detached(cmd: &str, args: &[&str]) -> bool {
    match Command::new(cmd).args(args).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn() {
        // Waited for on this (background) thread so it doesn't linger as a zombie.
        Ok(mut c) => {
            let _ = c.wait();
            true
        }
        Err(_) => false,
    }
}

/// Show the file selected in its folder: grove first, else whatever file
/// manager answers org.freedesktop.FileManager1, else open the folder.
pub fn show_in_file_manager(path: &str) {
    if run_detached("grove", &["--select", path]) {
        return;
    }
    let uri = format!("file://{}", path);
    let ok = zbus::blocking::Connection::session()
        .and_then(|c| {
            c.call_method(Some("org.freedesktop.FileManager1"), "/org/freedesktop/FileManager1", Some("org.freedesktop.FileManager1"), "ShowItems", &(vec![uri.as_str()], ""))
                .map(|_| ())
        })
        .is_ok();
    if !ok {
        let dir = std::path::Path::new(path).parent().map(|p| p.to_string_lossy().into_owned()).unwrap_or_default();
        run_detached("xdg-open", &[&dir]);
    }
}

pub fn open_file(path: &str) {
    run_detached("xdg-open", &[path]);
}

/// Ask the desktop for a folder (FileChooser portal). Ok(None) when the
/// person cancelled.
pub fn choose_folder(current: &str) -> Result<Option<String>> {
    let conn = zbus::blocking::Connection::session()?;
    let token = format!("sheaf{}", std::process::id());
    // The request's object path is known in advance, so its Response
    // signal can be listened for before asking (no race).
    let sender = conn.unique_name().ok_or_else(|| anyhow!("no D-Bus name"))?.trim_start_matches(':').replace('.', "_");
    let path = format!("/org/freedesktop/portal/desktop/request/{sender}/{token}");
    let request = zbus::blocking::Proxy::new(&conn, "org.freedesktop.portal.Desktop", path.as_str(), "org.freedesktop.portal.Request")?;
    let mut responses = request.receive_signal("Response")?;
    let mut opts: HashMap<&str, Value> = HashMap::new();
    opts.insert("handle_token", Value::from(token.as_str()));
    opts.insert("directory", Value::from(true));
    opts.insert("accept_label", Value::from("Choose"));
    let mut cur = current.as_bytes().to_vec();
    cur.push(0);
    if !current.is_empty() {
        opts.insert("current_folder", Value::from(cur));
    }
    conn.call_method(
        Some("org.freedesktop.portal.Desktop"),
        "/org/freedesktop/portal/desktop",
        Some("org.freedesktop.portal.FileChooser"),
        "OpenFile",
        &("", "Choose Where to Save Scans", opts),
    )
    .map_err(|e| anyhow!("The desktop's folder chooser isn't available ({e})."))?;
    let Some(msg) = responses.next() else { bail!("The folder chooser closed unexpectedly.") };
    let (code, results): (u32, HashMap<String, OwnedValue>) = msg.body().deserialize()?;
    if code != 0 {
        return Ok(None);
    }
    let uris: Vec<String> = results.get("uris").and_then(|v| Vec::<String>::try_from(v.try_clone().ok()?).ok()).unwrap_or_default();
    let Some(uri) = uris.first() else { return Ok(None) };
    let p = uri.strip_prefix("file://").unwrap_or(uri);
    Ok(Some(percent_decode(p)))
}

fn percent_decode(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            if let Ok(v) = u8::from_str_radix(&s[i + 1..i + 3], 16) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}
