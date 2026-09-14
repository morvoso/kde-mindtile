// MindTile: the KWin side of the layout engine. Everything that decides
// where a window goes is in engine.js; this file wires it to KWin's
// Workspace, the global shortcuts, the on-screen display, the saved modes and
// the focus border. The panel widget writes the gaps and the border to
// ~/.config/mindtilerc and asks for "MindTile: Reload settings".

import QtQuick
import QtCore
import org.kde.kwin
import "engine.js" as Engine

Item {
    id: root

    property var engine: null
    /// Every signal handler put on a window, so that they can be taken off
    /// when the script is unloaded. KWin keeps the windows, and a handler
    /// left on one would call into a script that no longer exists.
    property var hooks: []

    function list(model) {
        var out = [];
        for (var i = 0; i < model.length; i++) {
            out.push(model[i]);
        }
        return out;
    }

    function plainRect(r) {
        return { x: r.x, y: r.y, width: r.width, height: r.height };
    }

    function outputNamed(name) {
        var screens = Workspace.screens;
        for (var i = 0; i < screens.length; i++) {
            if (screens[i].name === name) {
                return screens[i];
            }
        }
        return Workspace.activeScreen;
    }

    Settings {
        id: store
        location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/mindtilerc"
        category: "Layout"
        property string modes: "{}"
        property string memory: "{}"
    }

    /// The accent colour, for a border without a colour of its own.
    Settings {
        id: kdeglobals
        location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/kdeglobals"
    }

    property var style: ({ gap: 8, outerGap: 8, border: true, borderWidth: 3, borderColor: "" })

    function accentColor() {
        kdeglobals.sync();
        var accent = kdeglobals.value("General/AccentColor", "");
        if (!accent || String(accent).length === 0) {
            accent = kdeglobals.value("Colors:Selection/BackgroundNormal", "");
        }
        var parts = Array.isArray(accent) ? accent : String(accent).split(",");
        if (parts.length >= 3) {
            return Qt.rgba(Number(parts[0]) / 255, Number(parts[1]) / 255, Number(parts[2]) / 255, 1);
        }
        return "#3daee9";
    }

    /// Gaps and border from mindtilerc. Before the widget has saved any, the
    /// gaps come from the script settings of earlier versions.
    function loadStyle() {
        store.sync();
        var saved = root.parsed(store.value("style", "") || "");
        var number = function (v, fallback) {
            var n = Number(v);
            return v === undefined || v === null || v === "" || isNaN(n) ? fallback : n;
        };
        root.style = {
            gap: number(saved.gap, number(KWin.readConfig("Gap", 8), 8)),
            outerGap: number(saved.outerGap, number(KWin.readConfig("OuterGap", 8), 8)),
            border: saved.border === undefined ? true : saved.border === true || saved.border === "true",
            borderWidth: number(saved.borderWidth, 3),
            borderColor: String(saved.borderColor || ""),
        };
        ring.borderWidth = root.style.border ? Math.max(0, Math.min(root.style.borderWidth, 32)) : 0;
        ring.borderColor = root.style.borderColor.length > 0 ? root.style.borderColor : root.accentColor();
        if (root.engine) {
            root.engine.setGaps(root.style.gap, root.style.outerGap);
        }
        root.updateRing();
    }

    FocusRing {
        id: ring
    }

    /// The window the border follows, and its signal handlers.
    property var ringWindow: null
    property var ringHooks: []

    function unwatchRing() {
        for (var i = 0; i < root.ringHooks.length; i++) {
            try {
                root.ringHooks[i].signal.disconnect(root.ringHooks[i].fn);
            } catch (err) {
                // the window is already gone
            }
        }
        root.ringHooks = [];
        root.ringWindow = null;
    }

    function watchRing(w) {
        if (w === root.ringWindow) {
            return;
        }
        root.unwatchRing();
        if (!w) {
            return;
        }
        root.ringWindow = w;
        var update = function () { root.updateRing(); };
        [w.frameGeometryChanged, w.maximizedChanged, w.fullScreenChanged, w.minimizedChanged, w.desktopsChanged].forEach(function (signal) {
            signal.connect(update);
            root.ringHooks.push({ signal: signal, fn: update });
        });
    }

    /// Open menus and popups. The border stays above other windows, so it is
    /// hidden while one is open instead of being drawn over it.
    property var popups: []

    function isPopup(w) {
        return w.popupWindow || w.popupMenu || w.dropdownMenu || w.comboBox;
    }

    function updateRing() {
        var w = Workspace.activeWindow;
        root.watchRing(w);
        var shown = w && !w.deleted && w.normalWindow && w.pid !== -1 && !w.fullScreen && !w.minimized
            && !w.maximizeMode && ring.borderWidth > 0 && root.popups.length === 0;
        ring.wrap(shown ? w.frameGeometry : null);
    }

    DBusCall {
        id: osdCall
        service: "org.kde.plasmashell"
        path: "/org/kde/osdService"
        dbusInterface: "org.kde.osdService"
        method: "showText"
    }

    // Coalesces everything that asks for a re-arrange into one pass per turn.
    Timer {
        id: soon
        interval: 0
        onTriggered: root.engine.arrange()
    }

    // Drives the columns strip while it slides, once per frame of the
    // fastest screen.
    Timer {
        id: frame
        interval: 16
        repeat: true
        onTriggered: root.engine.arrange()
    }

    function frameInterval() {
        var fastest = 60000;
        var screens = Workspace.screens;
        for (var i = 0; i < screens.length; i++) {
            fastest = Math.max(fastest, Number(screens[i].refreshRate) || 0);
        }
        return Math.max(4, Math.floor(1000000 / fastest));
    }

    readonly property var api: ({
        stackingOrder: function () { return root.list(Workspace.stackingOrder); },
        activeWindow: function () { return Workspace.activeWindow; },
        activate: function (w) { Workspace.activeWindow = w; },
        outputs: function () {
            return root.list(Workspace.screens).map(function (o) {
                return { name: o.name, geometry: root.plainRect(o.geometry) };
            });
        },
        area: function (name) {
            return root.plainRect(Workspace.clientArea(Engine.MAXIMIZE_AREA, root.outputNamed(name), Workspace.currentDesktop));
        },
        virtualScreen: function () { return root.plainRect(Workspace.virtualScreenGeometry); },
        currentDesktop: function () { return String(Workspace.currentDesktop.id); },
        currentActivity: function () { return String(Workspace.currentActivity || ""); },
        cursor: function () { return { x: Workspace.cursorPos.x, y: Workspace.cursorPos.y }; },
        setGeometry: function (w, r) { w.frameGeometry = Qt.rect(r.x, r.y, r.width, r.height); },
        setMaximized: function (w, on) { w.setMaximize(on, on); },
        osd: function (text) {
            osdCall.arguments = ["preferences-system-windows-effect-flipswitch", text];
            osdCall.call();
        },
        saveModes: function (modes) { store.modes = JSON.stringify(modes); store.sync(); },
        saveMemory: function (memory) { store.memory = JSON.stringify(memory); store.sync(); },
        schedule: function () { soon.restart(); },
        animate: function (on) {
            if (on && !frame.running) {
                frame.interval = root.frameInterval();
                frame.start();
            } else if (!on && frame.running) {
                frame.stop();
            }
        },
        now: function () { return Date.now(); },
    })

    function watch(w, existing) {
        if (!w || !w.normalWindow) {
            return;
        }
        var e = root.engine;
        function hook(signal, fn) {
            signal.connect(fn);
            root.hooks.push({ win: w, signal: signal, fn: fn });
        }
        hook(w.maximizedAboutToChange, function (mode) { e.maximizing(w, mode); });
        hook(w.maximizedChanged, e.schedule);
        hook(w.fullScreenChanged, e.schedule);
        hook(w.minimizedChanged, e.schedule);
        hook(w.desktopsChanged, e.schedule);
        hook(w.activitiesChanged, e.schedule);
        hook(w.outputChanged, function () { e.windowOutputChanged(w); });
        hook(w.interactiveMoveResizeStarted, function () { e.dragStarted(w, w.resize); });
        hook(w.interactiveMoveResizeFinished, function () { e.dragFinished(w); });
        e.windowAdded(w, existing);
    }

    function readList(key, fallback) {
        return String(KWin.readConfig(key, fallback)).split(",").map(function (s) {
            return s.trim();
        }).filter(function (s) {
            return s.length > 0;
        });
    }

    function parsed(text) {
        try {
            return JSON.parse(text) || {};
        } catch (err) {
            return {};
        }
    }

    Component.onCompleted: {
        root.engine = Engine.createEngine(root.api, {
            gap: KWin.readConfig("Gap", 8),
            outerGap: KWin.readConfig("OuterGap", 8),
            defaultMode: KWin.readConfig("DefaultMode", "floating"),
            animate: KWin.readConfig("Animate", true),
            floatingApps: root.readList("FloatingApps", ""),
        }, root.parsed(store.modes), root.parsed(store.memory));
        root.loadStyle();
        var existing = root.list(Workspace.stackingOrder);
        for (var i = 0; i < existing.length; i++) {
            root.watch(existing[i], true);
        }
    }

    Component.onDestruction: {
        root.unwatchRing();
        ring.visible = false;
        for (var i = 0; i < root.hooks.length; i++) {
            try {
                root.hooks[i].signal.disconnect(root.hooks[i].fn);
            } catch (err) {
                // the window is already gone
            }
        }
        root.hooks = [];
    }

    Connections {
        target: Workspace
        function onWindowAdded(w) {
            if (root.isPopup(w)) {
                root.popups = root.popups.concat([w]);
                root.updateRing();
                return;
            }
            root.watch(w, false);
        }
        function onWindowRemoved(w) {
            if (root.popups.indexOf(w) >= 0) {
                root.popups = root.popups.filter(function (p) { return p !== w; });
                root.updateRing();
                return;
            }
            root.hooks = root.hooks.filter(function (h) { return h.win !== w; });
            root.engine.windowRemoved(w);
        }
        function onWindowActivated(w) {
            root.engine.windowActivated(w);
            root.updateRing();
        }
        function onCurrentDesktopChanged() {
            root.engine.schedule();
            root.updateRing();
        }
        function onCurrentActivityChanged() { root.engine.schedule(); }
        function onScreensChanged() { root.engine.schedule(); }
        function onVirtualScreenGeometryChanged() { root.engine.schedule(); }
    }

    ShortcutHandler {
        name: "MindTile: Next layout"
        text: "MindTile: Next layout (Floating, Tiles, Columns)"
        sequence: "Meta+T"
        onActivated: root.engine.cycleMode()
    }
    ShortcutHandler {
        name: "MindTile: Floating layout"
        text: "MindTile: Floating layout"
        sequence: ""
        onActivated: root.engine.setMode("floating")
    }
    ShortcutHandler {
        name: "MindTile: Tiles layout"
        text: "MindTile: Tiles layout"
        sequence: ""
        onActivated: root.engine.setMode("dwindle")
    }
    ShortcutHandler {
        name: "MindTile: Columns layout"
        text: "MindTile: Columns layout"
        sequence: ""
        onActivated: root.engine.setMode("columns")
    }
    ShortcutHandler {
        name: "MindTile: Float window"
        text: "MindTile: Float or tile the focused window"
        sequence: "Meta+Shift+F"
        onActivated: root.engine.toggleFloating()
    }
    ShortcutHandler {
        name: "MindTile: Cycle size"
        text: "MindTile: Step the focused window's size"
        sequence: "Meta+R"
        onActivated: root.engine.cycleSize()
    }
    ShortcutHandler {
        name: "MindTile: Focus left"
        text: "MindTile: Focus the window to the left"
        sequence: "Meta+Left"
        onActivated: root.engine.focusDirection("left")
    }
    ShortcutHandler {
        name: "MindTile: Focus right"
        text: "MindTile: Focus the window to the right"
        sequence: "Meta+Right"
        onActivated: root.engine.focusDirection("right")
    }
    ShortcutHandler {
        name: "MindTile: Focus up"
        text: "MindTile: Focus the window above"
        sequence: "Meta+Up"
        onActivated: root.engine.focusDirection("up")
    }
    ShortcutHandler {
        name: "MindTile: Focus down"
        text: "MindTile: Focus the window below"
        sequence: "Meta+Down"
        onActivated: root.engine.focusDirection("down")
    }
    ShortcutHandler {
        name: "MindTile: Move left"
        text: "MindTile: Move the window left"
        sequence: "Meta+Shift+Left"
        onActivated: root.engine.moveDirection("left")
    }
    ShortcutHandler {
        name: "MindTile: Move right"
        text: "MindTile: Move the window right"
        sequence: "Meta+Shift+Right"
        onActivated: root.engine.moveDirection("right")
    }
    ShortcutHandler {
        name: "MindTile: Move up"
        text: "MindTile: Move the window up"
        sequence: "Meta+Shift+Up"
        onActivated: root.engine.moveDirection("up")
    }
    ShortcutHandler {
        name: "MindTile: Move down"
        text: "MindTile: Move the window down"
        sequence: "Meta+Shift+Down"
        onActivated: root.engine.moveDirection("down")
    }
    ShortcutHandler {
        name: "MindTile: Reload settings"
        text: "MindTile: Reload the gaps and the focus border from the widget"
        sequence: ""
        onActivated: root.loadStyle()
    }
    ShortcutHandler {
        name: "MindTile: Wheel focus next"
        text: "MindTile: Focus the next window (Meta+wheel down)"
        sequence: ""
        onActivated: root.engine.wheelFocus(true)
    }
    ShortcutHandler {
        name: "MindTile: Wheel focus previous"
        text: "MindTile: Focus the previous window (Meta+wheel up)"
        sequence: ""
        onActivated: root.engine.wheelFocus(false)
    }
    ShortcutHandler {
        name: "MindTile: Focus next"
        text: "MindTile: Focus the next window in the layout"
        sequence: ""
        onActivated: root.engine.focusStep(true)
    }
    ShortcutHandler {
        name: "MindTile: Focus previous"
        text: "MindTile: Focus the previous window in the layout"
        sequence: ""
        onActivated: root.engine.focusStep(false)
    }
}
