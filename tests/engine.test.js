// Unit tests for the layout engine, against a fake KWin workspace.
// Run with `node --test tests/`.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const src = fs.readFileSync(path.join(__dirname, "../package/contents/ui/engine.js"), "utf8");
const E = vm.createContext({});
vm.runInContext(src, E);

const rect = (x, y, width, height) => ({ x, y, width, height });
const plain = (r) => ({ x: r.x, y: r.y, width: r.width, height: r.height });

let nextId = 1;
function win(geometry, extra) {
    return Object.assign({
        internalId: "{w" + nextId++ + "}",
        frameGeometry: geometry,
        normalWindow: true,
        moveable: true,
        resizeable: true,
        desktops: [{ id: "d1" }],
        activities: [],
        maximizeMode: 0,
        resourceClass: "app",
    }, extra);
}

function workspace(outputs, config) {
    const ws = {
        windows: [],
        active: null,
        cursor: { x: 0, y: 0 },
        desktop: "d1",
        saved: null,
        osd: [],
        outputs: outputs || [{ name: "A", geometry: rect(0, 0, 1920, 1080) }],
    };
    ws.api = {
        stackingOrder: () => ws.windows.slice(),
        activeWindow: () => ws.active,
        activate: (w) => { ws.active = w; ws.engine.windowActivated(w); },
        outputs: () => ws.outputs,
        area: (name) => ws.outputs.find((o) => o.name === name).geometry,
        virtualScreen: () => {
            const xs = ws.outputs.map((o) => o.geometry);
            const x = Math.min(...xs.map((g) => g.x)), y = Math.min(...xs.map((g) => g.y));
            return rect(x, y, Math.max(...xs.map((g) => g.x + g.width)) - x, Math.max(...xs.map((g) => g.y + g.height)) - y);
        },
        currentDesktop: () => ws.desktop,
        currentActivity: () => "",
        cursor: () => ws.cursor,
        setGeometry: (w, r) => { w.frameGeometry = plain(r); },
        setMaximized: (w, on) => { w.maximizeMode = on ? 3 : 0; },
        osd: (text) => ws.osd.push(text),
        saveModes: (m) => { ws.saved = JSON.stringify(m); },
        schedule: () => {},
        animate: () => {},
        now: () => 0,
    };
    ws.engine = E.createEngine(ws.api, Object.assign({ gap: 8, outerGap: 0, defaultMode: "floating", animate: false }, config), {});
    ws.open = (geometry, extra) => {
        const w = win(geometry, extra);
        ws.windows.push(w);
        ws.engine.windowAdded(w);
        ws.active = w;
        ws.engine.arrange();
        return w;
    };
    return ws;
}

test("dwindle spirals along the longer side", () => {
    const area = rect(0, 0, 1920, 1080);
    const d = (n) => [...E.dwindleRects(area, new Array(n).fill(0), 8)].map((s) => plain(s.rect));
    assert.deepEqual(d(1), [area]);
    assert.deepEqual(d(2), [rect(0, 0, 956, 1080), rect(964, 0, 956, 1080)]);
    assert.deepEqual(d(3), [rect(0, 0, 956, 1080), rect(964, 0, 956, 536), rect(964, 544, 956, 536)]);
    for (const r of d(9)) {
        assert.ok(r.width >= E.MIN_TILE && r.height >= E.MIN_TILE);
    }
});

test("a dragged divider moves the dwindle split", () => {
    const rects = E.dwindleRects(rect(0, 0, 1920, 1080), [1 / 3, 0], 8);
    assert.equal(rects[0].rect.width, 637);
    assert.ok(rects[0].splitX);
    assert.equal(rects[1].rect.x, 645);
    assert.equal(rects[1].rect.width, 1275);
    const squeezed = E.dwindleRects(rect(0, 0, 1920, 1080), [0.999, 0], 8);
    assert.ok(squeezed[0].rect.width <= 1912 - E.MIN_TILE);
    assert.ok(squeezed[1].rect.width >= E.MIN_TILE);
});

test("columns fill and scroll to the focused one", () => {
    const area = rect(100, 50, 1000, 600);
    assert.deepEqual([...E.columnRects(area, [0.5, 0.5], 10, 0)].map(plain), [rect(100, 50, 495, 600), rect(605, 50, 495, 600)]);
    assert.equal(E.scrollToShow(1000, [0.5, 0.5], 10, 0, 1), 0);
    assert.equal(E.scrollToShow(1000, [0.5, 0.5, 0.5], 10, 0, 0), 0);
    const s = E.scrollToShow(1000, [0.5, 0.5, 0.5], 10, 0, 2);
    assert.equal(s, 505);
    assert.equal(E.scrollToShow(1000, [0.5, 0.5, 0.5], 10, s, 0), 0);
    assert.equal(E.columnWidth(1000, 1, 10), 1000);
});

test("snap halves partition an odd-width output", () => {
    const area = rect(-1919, 42, 1919, 1001);
    assert.equal(E.snapRect(area, "left-half").width + E.snapRect(area, "right-half").width, area.width);
    const game = E.snapRect(area, "left-two-thirds"), companion = E.snapRect(area, "right-third");
    assert.equal(game.x + game.width, companion.x);
    assert.equal(companion.x + companion.width, area.x + area.width);
});

test("modes parse and cycle", () => {
    assert.equal(E.parseMode("niri"), "columns");
    assert.equal(E.parseMode("Hyprland"), "dwindle");
    assert.equal(E.parseMode("kde"), "floating");
    assert.equal(E.parseMode("x"), null);
    assert.equal(E.nextMode(E.nextMode(E.nextMode("floating"))), "floating");
});

test("neighbours are picked by direction", () => {
    const from = rect(0, 0, 100, 100);
    const cands = [{ item: "a", rect: rect(200, 0, 100, 100) }, { item: "b", rect: rect(0, 200, 100, 100) }];
    assert.equal(E.neighbourIn(from, "right", cands), "a");
    assert.equal(E.neighbourIn(from, "down", cands), "b");
    assert.equal(E.neighbourIn(from, "left", cands), null);
});

test("tiling remembers every window's floating geometry and gives it back", () => {
    const ws = workspace();
    const a = ws.open(rect(100, 100, 800, 600));
    const b = ws.open(rect(300, 200, 640, 480));
    ws.engine.arrange();
    assert.deepEqual(a.frameGeometry, rect(100, 100, 800, 600), "floating leaves windows alone");

    ws.engine.setMode("tiles");
    ws.engine.arrange();
    assert.equal(ws.osd.pop(), "Tiles");
    assert.deepEqual(a.frameGeometry, rect(0, 0, 956, 1080));
    assert.deepEqual(b.frameGeometry, rect(964, 0, 956, 1080));

    ws.engine.setMode("columns");
    ws.engine.arrange();
    assert.deepEqual(a.frameGeometry, rect(0, 0, 956, 1080));

    ws.engine.setMode("floating");
    ws.engine.arrange();
    assert.deepEqual(a.frameGeometry, rect(100, 100, 800, 600));
    assert.deepEqual(b.frameGeometry, rect(300, 200, 640, 480));
    assert.equal(JSON.parse(ws.saved).d1, "floating");
});

test("a window born as a tile floats as three fifths of the screen, centred", () => {
    const ws = workspace();
    ws.engine.setMode("dwindle");
    const a = ws.open(rect(10, 10, 300, 300));
    // What it opened with never counted: the tile was its first place.
    a.frameGeometry = rect(0, 0, 1920, 1080);
    ws.engine._data(a).untiled = null;
    ws.engine.setMode("floating");
    ws.engine.arrange();
    assert.deepEqual(a.frameGeometry, rect(384, 216, 1152, 648));
});

test("floating one tile puts it back and the rest close up", () => {
    const ws = workspace();
    const a = ws.open(rect(100, 100, 800, 600));
    const b = ws.open(rect(300, 200, 640, 480));
    ws.engine.setMode("dwindle");
    ws.engine.arrange();
    ws.active = b;
    ws.engine.toggleFloating();
    ws.engine.arrange();
    assert.deepEqual(b.frameGeometry, rect(300, 200, 640, 480));
    assert.deepEqual(a.frameGeometry, rect(0, 0, 1920, 1080));
    ws.engine.toggleFloating();
    ws.engine.arrange();
    assert.deepEqual(b.frameGeometry, rect(964, 0, 956, 1080));
});

test("new tiles go after the focused one", () => {
    const ws = workspace();
    ws.engine.setMode("columns");
    const a = ws.open(rect(0, 0, 500, 500));
    const b = ws.open(rect(0, 0, 500, 500));
    ws.active = a;
    const c = ws.open(rect(0, 0, 500, 500));
    ws.active = a;
    ws.engine.arrange();
    const xs = [a, c, b].map((w) => w.frameGeometry.x);
    assert.deepEqual(xs, [0, 964, 1928]);
});

test("the strip scrolls to the focused column", () => {
    const ws = workspace();
    ws.engine.setMode("columns");
    const a = ws.open(rect(0, 0, 500, 500));
    ws.open(rect(0, 0, 500, 500));
    const c = ws.open(rect(0, 0, 500, 500));
    // c is focused: the strip shows b and c
    assert.equal(c.frameGeometry.x, 964);
    assert.equal(a.frameGeometry.x, -964);
    ws.engine.focusStep(true); // wraps to a
    ws.engine.arrange();
    assert.equal(ws.active, a);
    assert.equal(a.frameGeometry.x, 0);
});

test("an off-screen column waits below the desktop instead of showing next door", () => {
    const ws = workspace([
        { name: "L", geometry: rect(0, 0, 1000, 800) },
        { name: "R", geometry: rect(1000, 0, 1600, 900) },
    ]);
    ws.engine.setMode("columns");
    const a = ws.open(rect(100, 100, 400, 400));
    const b = ws.open(rect(100, 100, 400, 400));
    const c = ws.open(rect(100, 100, 400, 400));
    ws.active = a;
    ws.engine.arrange();
    // c's slot is x = 1008, entirely on R: it is parked below the desktop.
    assert.ok(c.frameGeometry.y >= 900, JSON.stringify(c.frameGeometry));
    assert.equal(ws.engine._data(c).target.x, 1008);
    assert.equal(ws.engine._data(c).output, "L");
    // b spills onto R but shows on L: it stays put.
    assert.equal(b.frameGeometry.y, 0);
});

test("swapping tiles and cycling sizes", () => {
    const ws = workspace();
    ws.engine.setMode("dwindle");
    const a = ws.open(rect(0, 0, 500, 500));
    const b = ws.open(rect(0, 0, 500, 500));
    ws.engine.moveDirection("left");
    ws.engine.arrange();
    assert.equal(b.frameGeometry.x, 0);
    assert.equal(a.frameGeometry.x, 964);
    ws.engine.cycleSize(); // b: half -> two thirds
    ws.engine.arrange();
    assert.equal(b.frameGeometry.width, 1275);
});

test("a floating window snaps to a half and comes back", () => {
    const ws = workspace();
    const a = ws.open(rect(200, 200, 700, 500));
    ws.engine.moveDirection("left");
    ws.engine.arrange();
    assert.deepEqual(a.frameGeometry, rect(0, 0, 960, 1080));
    ws.engine.moveDirection("left");
    ws.engine.arrange();
    assert.deepEqual(a.frameGeometry, rect(200, 200, 700, 500));
});

test("resizing a tile moves its split, or the split of the tile before it", () => {
    const ws = workspace();
    ws.engine.setMode("dwindle");
    const a = ws.open(rect(0, 0, 500, 500));
    const b = ws.open(rect(0, 0, 500, 500));
    const c = ws.open(rect(0, 0, 500, 500));
    // a | b over c. Drag b's left edge (a's divider) to x = 645.
    ws.engine.dragStarted(b, true);
    b.frameGeometry = rect(645, 0, 1275, 536);
    ws.engine.dragFinished(b);
    ws.engine.arrange();
    assert.equal(a.frameGeometry.width, 637);
    assert.equal(b.frameGeometry.x, 645);
    // What is left is now wider than tall, so b and c sit side by side.
    assert.deepEqual(b.frameGeometry, rect(645, 0, 634, 1080));
    // Drag b's right edge (its own split) to x = 1400.
    ws.engine.dragStarted(b, true);
    b.frameGeometry = rect(645, 0, 755, 1080);
    ws.engine.dragFinished(b);
    ws.engine.arrange();
    assert.equal(b.frameGeometry.width, 755);
    assert.equal(c.frameGeometry.x, 1408);
});

test("dropping a tile on another swaps them", () => {
    const ws = workspace();
    ws.engine.setMode("dwindle");
    const a = ws.open(rect(0, 0, 500, 500));
    const b = ws.open(rect(0, 0, 500, 500));
    ws.engine.dragStarted(a, false);
    a.frameGeometry = rect(1200, 300, 956, 1080);
    ws.cursor = { x: 1500, y: 500 };
    ws.engine.dragFinished(a);
    ws.engine.arrange();
    assert.equal(a.frameGeometry.x, 964);
    assert.equal(b.frameGeometry.x, 0);
});

test("dialogs, apps on every desktop and listed apps float", () => {
    const ws = workspace(undefined, { floatingApps: ["steam_app_*", "org.kde.kcalc"] });
    ws.engine.setMode("dwindle");
    const a = ws.open(rect(0, 0, 500, 500));
    const dialog = ws.open(rect(50, 50, 300, 200), { dialog: true });
    const sticky = ws.open(rect(60, 60, 300, 200), { onAllDesktops: true });
    const game = ws.open(rect(70, 70, 300, 200), { resourceClass: "steam_app_1091500" });
    const calc = ws.open(rect(80, 80, 300, 200), { resourceClass: "org.kde.kcalc" });
    ws.engine.arrange();
    assert.deepEqual(a.frameGeometry, rect(0, 0, 1920, 1080));
    assert.deepEqual(dialog.frameGeometry, rect(50, 50, 300, 200));
    assert.deepEqual(sticky.frameGeometry, rect(60, 60, 300, 200));
    assert.deepEqual(game.frameGeometry, rect(70, 70, 300, 200));
    assert.deepEqual(calc.frameGeometry, rect(80, 80, 300, 200));
});

test("each desktop keeps its own mode", () => {
    const ws = workspace();
    const a = ws.open(rect(100, 100, 800, 600));
    ws.engine.setMode("dwindle");
    ws.engine.arrange();
    ws.desktop = "d2";
    assert.equal(ws.engine.mode(), "floating");
    const b = ws.open(rect(100, 100, 800, 600), { desktops: [{ id: "d2" }] });
    ws.engine.arrange();
    assert.deepEqual(b.frameGeometry, rect(100, 100, 800, 600));
    assert.deepEqual(a.frameGeometry, rect(0, 0, 1920, 1080), "the other desktop is left alone");
    ws.desktop = "d1";
    assert.equal(ws.engine.mode(), "dwindle");
});

test("a maximised window that becomes a tile floats at its size from before", () => {
    const ws = workspace();
    const a = ws.open(rect(100, 100, 800, 600));
    ws.engine.maximizing(a, 3);
    ws.api.setMaximized(a, true);
    a.frameGeometry = rect(0, 0, 1920, 1080);
    ws.engine.setMode("dwindle");
    // KWin has cleared the state but not yet the geometry.
    ws.engine.arrange();
    assert.equal(a.maximizeMode, 0);
    ws.engine.setMode("floating");
    ws.engine.arrange();
    assert.deepEqual(a.frameGeometry, rect(100, 100, 800, 600));
});

test("a tile sent to the other screen floats in its old place over there", () => {
    const ws = workspace([
        { name: "L", geometry: rect(0, 0, 2560, 1440) },
        { name: "R", geometry: rect(2560, 0, 1920, 1080) },
    ]);
    const a = ws.open(rect(1800, 1200, 700, 500));
    ws.engine.setMode("dwindle");
    ws.engine.arrange();
    // Window to Next Screen: KWin moves it, the engine sees the output change.
    a.frameGeometry = rect(2568, 8, 1904, 1064);
    ws.engine.windowOutputChanged(a);
    ws.engine.arrange();
    assert.deepEqual(a.frameGeometry, rect(2560, 0, 1920, 1080));
    ws.engine.setMode("floating");
    ws.engine.arrange();
    assert.deepEqual(a.frameGeometry, rect(3780, 580, 700, 500));
});
