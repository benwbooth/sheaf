// Qt-side helpers sheaf's Rust code calls: the application (native text),
// the QML engine with its theme-icon provider, and the screenshot hook.
#pragma once

#include <QtCore/QString>
#include "rust/cxx.h"

// The application object: native text rendering, names, fonts, icons.
void sheaf_create_app();
// Create the QML engine, load `url`, run the event loop.
int sheaf_run(const QString& url, const QString& importPath);
// The icon theme to match light or dark.
void sheaf_set_icon_theme(bool dark);
// Test hook: save every visible window (the first to `path`, others to
// path-1.png, path-2.png...).
void sheaf_grab_windows(const QString& path);
