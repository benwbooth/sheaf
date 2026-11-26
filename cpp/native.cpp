#include "native_helpers.h"
#include "global_menu.h"
#include <QtCore/QProcessEnvironment>

#include <QtCore/QDir>
#include <QtCore/QFile>
#include <QtCore/QUrl>
#include <QtCore/QUrlQuery>
#include <QtGui/QFontDatabase>
#include <QtGui/QGuiApplication>
#include <QtGui/QIcon>
#include <QtGui/QPainter>
#include <QtGui/QWindow>
#include <QtQml/QQmlApplicationEngine>
#include <QtQml/qqml.h>
#include <QtQuick/QQuickImageProvider>
#include <QtQuick/QQuickWindow>
#include <algorithm>

// Puts back what start-up changed in the environment for Qt (noted as
// __APP_ORIG_<name>: empty = unset, else "=value"), once the main QML has
// loaded, so programs this app starts get the desktop's own (our
// QT_QUICK_CONTROLS_STYLE=Basic made KDE apps opened from here draw plain
// light controls, 2026-11-25).
static void restoreLaunchEnv()
{
    const QStringList keys = QProcessEnvironment::systemEnvironment().keys();
    for (const QString& k : keys) {
        if (!k.startsWith(QLatin1String("__APP_ORIG_")))
            continue;
        const QByteArray key = k.toLocal8Bit();
        const QByteArray name = k.mid(11).toLocal8Bit();
        const QByteArray v = qgetenv(key.constData());
        if (v.startsWith('='))
            qputenv(name.constData(), v.mid(1));
        else
            qunsetenv(name.constData());
        qunsetenv(key.constData());
    }
}

namespace {

// image://icon/<name>[|fallback...]?tint=rrggbb : a freedesktop theme icon,
// drawn at exactly the size asked (line-art glyphs lose strokes when
// shrunk), optionally recoloured (one-colour toolbar glyphs).
class IconProvider : public QQuickImageProvider {
public:
    // QImage, not QPixmap: this runs on a loader thread.
    IconProvider() : QQuickImageProvider(QQuickImageProvider::Image, QQuickImageProvider::ForceAsynchronousImageLoading) {}
    QImage requestImage(const QString& id, QSize* size, const QSize& req) override
    {
        const int s = qMax(16, qMax(req.width(), req.height()));
        QString key = id;
        QColor tint;
        const int q = key.lastIndexOf(QLatin1Char('?'));
        if (q >= 0) {
            const QUrlQuery query(key.mid(q + 1));
            if (query.hasQueryItem(QStringLiteral("tint")))
                tint = QColor(QLatin1Char('#') + query.queryItemValue(QStringLiteral("tint")));
            key.truncate(q);
        }
        QIcon icon;
        for (const QString& n : QUrl::fromPercentEncoding(key.toUtf8()).split(QLatin1Char('|'), Qt::SkipEmptyParts)) {
            if (QIcon::hasThemeIcon(n)) { icon = QIcon::fromTheme(n); break; }
        }
        QImage img(s, s, QImage::Format_ARGB32_Premultiplied);
        img.fill(Qt::transparent);
        if (!icon.isNull()) {
            QPainter p(&img);
            icon.paint(&p, QRect(0, 0, s, s));
            if (tint.isValid() && tint.alpha() > 0) {
                p.setCompositionMode(QPainter::CompositionMode_SourceIn);
                p.fillRect(img.rect(), tint);
            }
        }
        if (size) *size = img.size();
        return img;
    }
};

bool themeExists(const QString& name)
{
    for (const QString& d : QIcon::themeSearchPaths())
        if (QFile::exists(d + QLatin1Char('/') + name + QStringLiteral("/index.theme"))) return true;
    return false;
}

}  // namespace

void sheaf_create_app()
{
    // Native (FreeType) text everywhere: Qt Quick's distance-field text is
    // soft at fractional scales. Must be set before any window exists.
    QQuickWindow::setTextRenderType(QQuickWindow::NativeTextRendering);
    static int argc = 1;
    static char name[] = "sheaf";
    static char* argv[] = { name, nullptr };
    new QGuiApplication(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("sheaf"));
    QGuiApplication::setApplicationDisplayName(QStringLiteral("Sheaf"));
    QGuiApplication::setApplicationVersion(QStringLiteral(SHEAF_VERSION));
    QGuiApplication::setOrganizationName(QStringLiteral("sheaf"));
    QGuiApplication::setDesktopFileName(QStringLiteral("sheaf"));
    QGuiApplication::setWindowIcon(QIcon::fromTheme(QStringLiteral("sheaf"), QIcon::fromTheme(QStringLiteral("scanner"))));
    // Inter (SF Pro's open relative) when SF Pro isn't installed: the
    // package hands its folder over in SHEAF_FONT_DIR, as grove does.
    const QString fontDir = QString::fromLocal8Bit(qgetenv("SHEAF_FONT_DIR"));
    if (!fontDir.isEmpty()) {
        const QFileInfoList files = QDir(fontDir).entryInfoList({ QStringLiteral("Inter*.tt*") }, QDir::Files);
        for (const QFileInfo& f : files) QFontDatabase::addApplicationFont(f.absoluteFilePath());
    }
    // Icon theme folders from the XDG directories (some platform plugins,
    // e.g. offscreen, leave only Qt's resources).
    QStringList paths = QIcon::themeSearchPaths();
    const QString home = QString::fromLocal8Bit(qgetenv("HOME"));
    QString dataHome = QString::fromLocal8Bit(qgetenv("XDG_DATA_HOME"));
    if (dataHome.isEmpty()) dataHome = home + QStringLiteral("/.local/share");
    QStringList want { dataHome + QStringLiteral("/icons"), home + QStringLiteral("/.icons") };
    QString dirs = QString::fromLocal8Bit(qgetenv("XDG_DATA_DIRS"));
    if (dirs.isEmpty()) dirs = QStringLiteral("/usr/local/share:/usr/share");
    for (const QString& d : dirs.split(QLatin1Char(':'), Qt::SkipEmptyParts)) want << d + QStringLiteral("/icons");
    want << QStringLiteral("/run/current-system/sw/share/icons") << home + QStringLiteral("/.nix-profile/share/icons");
    for (const QString& w : want)
        if (!paths.contains(w) && QFile::exists(w)) paths << w;
    QIcon::setThemeSearchPaths(paths);
    sheaf_set_icon_theme(true);
}

void sheaf_set_icon_theme(bool dark)
{
    // The desktop's own theme when it set one; else WhiteSur (as grove),
    // then Breeze's or Adwaita's icon data.
    static const QString desktop = QIcon::themeName();
    if (!desktop.isEmpty() && desktop != QLatin1String("hicolor")) return;
    const QStringList tries = dark ? QStringList { QStringLiteral("WhiteSur-dark"), QStringLiteral("breeze-dark"), QStringLiteral("Adwaita") }
                                   : QStringList { QStringLiteral("WhiteSur"), QStringLiteral("breeze"), QStringLiteral("Adwaita") };
    for (const QString& t : tries) {
        if (themeExists(t)) { QIcon::setThemeName(t); break; }
    }
    QIcon::setFallbackThemeName(QStringLiteral("hicolor"));
}

int sheaf_run(const QString& url, const QString& importPath)
{
    qmlRegisterType<GlobalMenuBar>("GlobalMenu", 1, 0, "GlobalMenuBar");
    auto* engine = new QQmlApplicationEngine;
    engine->addImageProvider(QStringLiteral("icon"), new IconProvider);
    if (!importPath.isEmpty()) engine->addImportPath(importPath);
    engine->load(QUrl(url));
    if (engine->rootObjects().isEmpty()) return 1;
    restoreLaunchEnv();
    return QGuiApplication::exec();
}

void sheaf_grab_windows(const QString& path)
{
    int n = 0;
    QList<QQuickWindow*> wins;
    for (QWindow* w : QGuiApplication::topLevelWindows())
        if (auto* q = qobject_cast<QQuickWindow*>(w); q && q->isVisible()) wins << q;
    std::stable_sort(wins.begin(), wins.end(), [](QQuickWindow* a, QQuickWindow* b) { return a->width() * a->height() > b->width() * b->height(); });
    for (QQuickWindow* q : wins) {
        QString out = path;
        if (n > 0) out.replace(QStringLiteral(".png"), QStringLiteral("-%1.png").arg(n));
        q->grabWindow().save(out);
        n++;
    }
}
