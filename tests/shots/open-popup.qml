    // Screenshot copy only: opens the popup once $XDG_CONFIG_HOME/mindtile-shot
    // has open=1, since nothing can click in the headless session.
    Settings {
        id: shotFlag
        location: StandardPaths.writableLocation(StandardPaths.GenericConfigLocation) + "/mindtile-shot"
        category: "Shot"
    }
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            shotFlag.sync();
            if (String(shotFlag.value("open", "")) === "1" && !root.expanded) {
                console.warn("SHOT opening popup");
                root.expanded = true;
            }
        }
    }
}
