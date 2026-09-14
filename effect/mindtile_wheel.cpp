// MindTile wheel focus: a KWin effect that only registers Meta+wheel
// shortcuts. KWin scripts can't bind the mouse wheel, so this passes each
// turn of the wheel on to the script's "MindTile: Wheel focus next/previous"
// shortcuts over D-Bus. It draws nothing.
//
// It is built against the KWin on this machine and refuses to load into any
// other KWin version, since KWin has no stable plugin ABI. Run the installer
// again after a KWin update to rebuild it.

#include <config-kwin.h>
#include <effect/effect.h>
#include <effect/effecthandler.h>

#include <QAction>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>

namespace MindTile
{

class WheelFocus : public KWin::Effect
{
public:
    WheelFocus()
    {
        bind(KWin::PointerAxisDown, QStringLiteral("MindTile: Wheel focus next"));
        bind(KWin::PointerAxisRight, QStringLiteral("MindTile: Wheel focus next"));
        bind(KWin::PointerAxisUp, QStringLiteral("MindTile: Wheel focus previous"));
        bind(KWin::PointerAxisLeft, QStringLiteral("MindTile: Wheel focus previous"));
    }

    bool isActive() const override
    {
        return false;
    }

private:
    void bind(KWin::PointerAxisDirection direction, const QString &shortcut)
    {
        auto *action = new QAction(this);
        QObject::connect(action, &QAction::triggered, this, [shortcut]() {
            QDBusMessage call = QDBusMessage::createMethodCall(QStringLiteral("org.kde.kglobalaccel"),
                                                               QStringLiteral("/component/kwin"),
                                                               QStringLiteral("org.kde.kglobalaccel.Component"),
                                                               QStringLiteral("invokeShortcut"));
            call << shortcut;
            QDBusConnection::sessionBus().send(call);
        });
        KWin::effects->registerAxisShortcut(Qt::MetaModifier, direction, action);
    }
};

static bool sameKWin()
{
    return QCoreApplication::applicationVersion() == KWIN_VERSION_STRING;
}

class WheelFocusFactory : public KWin::EffectPluginFactory
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID EffectPluginFactory_iid FILE "metadata.json")
    Q_INTERFACES(KPluginFactory)

public:
    bool isSupported() const override
    {
        return sameKWin();
    }

    bool enabledByDefault() const override
    {
        return false;
    }

    KWin::Effect *createEffect() const override
    {
        return sameKWin() ? new WheelFocus() : nullptr;
    }
};

} // namespace MindTile

#include "mindtile_wheel.moc"
