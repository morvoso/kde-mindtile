// MindTile: the MindOS window layouts (Floating, Tiles, Columns) for KWin.
//
// This file is the whole layout engine, ported from mindwm's src/layout.rs.
// It knows nothing about QML: main.qml hands it an `api` object that wraps
// KWin's Workspace, and the tests hand it a fake one. Rectangles are plain
// {x, y, width, height} objects in logical pixels.

var MODES = ["floating", "dwindle", "columns"];
var MODE_LABELS = { floating: "Floating", dwindle: "Tiles", columns: "Columns" };

/// Column width presets (fraction of the usable width), cycled with Meta+R.
var COLUMN_WIDTHS = [1 / 3, 1 / 2, 2 / 3, 1];
/// A dwindle tile shares its split with a sibling, so it never takes all of it.
var SPLIT_WIDTHS = [1 / 3, 1 / 2, 2 / 3];
/// What a floating window takes of the screen when it is stepped through sizes.
var FLOAT_SIZES = [0.5, 0.7, 0.9];
var DEFAULT_COLUMN_WIDTH = 0.5;
var MIN_TILE = 120;
/// The columns strip slides on a critically damped spring, like niri's
/// default view movement (stiffness 800): a new target mid-slide keeps the
/// speed the strip already has instead of starting again from rest.
var SPRING_OMEGA = Math.sqrt(800);
/// Meta+wheel moves the focus at most once in this many milliseconds, so a
/// touchpad or a free-spinning wheel steps one column at a time (niri's
/// cooldown-ms=150).
var WHEEL_COOLDOWN_MS = 150;
/// KWin's ClientAreaOption::MaximizeArea (the enum is not exposed to QML).
var MAXIMIZE_AREA = 2;

function parseMode(s) {
    switch (String(s).trim().toLowerCase()) {
    case "floating": case "float": case "kde": case "stacking":
        return "floating";
    case "dwindle": case "tiles": case "tiling": case "hyprland":
        return "dwindle";
    case "columns": case "scroll": case "scrolling": case "niri":
        return "columns";
    }
    return null;
}

function nextMode(mode) {
    return MODES[(MODES.indexOf(mode) + 1) % MODES.length];
}

function isTiling(mode) {
    return mode !== "floating";
}

// ---------------------------------------------------------------- geometry

function rect(x, y, width, height) {
    return { x: x, y: y, width: width, height: height };
}

function copyRect(r) {
    return rect(r.x, r.y, r.width, r.height);
}

function clamp(v, lo, hi) {
    return Math.min(Math.max(v, lo), hi);
}

function intersection(a, b) {
    var x = Math.max(a.x, b.x);
    var y = Math.max(a.y, b.y);
    var w = Math.min(a.x + a.width, b.x + b.width) - x;
    var h = Math.min(a.y + a.height, b.y + b.height) - y;
    return w > 0 && h > 0 ? rect(x, y, w, h) : null;
}

function contains(r, p) {
    return p.x >= r.x && p.x < r.x + r.width && p.y >= r.y && p.y < r.y + r.height;
}

function centre(r) {
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
}

function sameRect(a, b) {
    return Math.abs(a.x - b.x) < 1 && Math.abs(a.y - b.y) < 1
        && Math.abs(a.width - b.width) < 1 && Math.abs(a.height - b.height) < 1;
}

function centred(area, width, height) {
    return rect(area.x + Math.round((area.width - width) / 2),
                area.y + Math.round((area.height - height) / 2), width, height);
}

/// Dwindle: window `i` takes `fracs[i]` of what is left (split along the
/// longer side), the rest goes to the windows after it. A fraction of 0 means
/// the default half. Each entry says which way its split ran (`splitX`) and
/// what space it was carved from (`rest`), so a resize knows which split a
/// moved edge belongs to.
function dwindleRects(area, fracs, gap) {
    var n = fracs.length;
    var out = [];
    var rest = area;
    for (var i = 0; i < n; i++) {
        if (i + 1 === n) {
            out.push({ rect: rest, splitX: rest.width >= rest.height, rest: rest });
            break;
        }
        var frac = fracs[i] <= 0 ? 0.5 : clamp(fracs[i], 0.1, 0.9);
        if (rest.width >= rest.height) {
            var w1 = splitAt(rest.width, frac, gap);
            out.push({ rect: rect(rest.x, rest.y, w1, rest.height), splitX: true, rest: rest });
            rest = rect(rest.x + w1 + gap, rest.y, Math.max(rest.width - w1 - gap, MIN_TILE), rest.height);
        } else {
            var h1 = splitAt(rest.height, frac, gap);
            out.push({ rect: rect(rest.x, rest.y, rest.width, h1), splitX: false, rest: rest });
            rest = rect(rest.x, rest.y + h1 + gap, rest.width, Math.max(rest.height - h1 - gap, MIN_TILE));
        }
    }
    return out;
}

/// Where a split falls: `frac` of the space either side of the gap, never
/// leaving less than a usable tile on either side.
function splitAt(span, frac, gap) {
    var usable = Math.max(span - gap, 2 * MIN_TILE);
    return clamp(Math.round(usable * frac), MIN_TILE, usable - MIN_TILE);
}

/// Columns: full-height columns of the given width fractions on a strip
/// starting at `area.x - scroll`.
function columnRects(area, widths, gap, scroll) {
    var out = [];
    var x = area.x - scroll;
    for (var i = 0; i < widths.length; i++) {
        var w = columnWidth(area.width, widths[i], gap);
        out.push(rect(x, area.y, w, area.height));
        x += w + gap;
    }
    return out;
}

function columnWidth(areaW, frac, gap) {
    frac = frac <= 0 ? DEFAULT_COLUMN_WIDTH : clamp(frac, 0.1, 1);
    if (frac >= 0.999) {
        return Math.max(areaW, MIN_TILE);
    }
    return Math.max(Math.round((areaW - gap) * frac), MIN_TILE);
}

/// Scroll offset that keeps column `focused` inside the area.
function scrollToShow(areaW, widths, gap, scroll, focused) {
    var total = 0;
    for (var i = 0; i < widths.length; i++) {
        total += columnWidth(areaW, widths[i], gap);
    }
    total += gap * Math.max(widths.length - 1, 0);
    if (total <= areaW) {
        return 0;
    }
    scroll = clamp(scroll, 0, total - areaW);
    if (focused !== null && focused !== undefined && focused >= 0) {
        var x = 0;
        for (var j = 0; j < widths.length; j++) {
            var w = columnWidth(areaW, widths[j], gap);
            if (j === focused) {
                if (x < scroll) {
                    scroll = x;
                } else if (x + w > scroll + areaW) {
                    scroll = x + w - areaW;
                }
                break;
            }
            x += w + gap;
        }
    }
    return clamp(scroll, 0, total - areaW);
}

/// Where a slide is at `now`, and how fast it moves (pixels per second).
/// `anim` is {from, vel, to, start}: the position and speed it had when the
/// target last changed.
function springAt(anim, now) {
    var t = Math.max(now - anim.start, 0) / 1000;
    var x0 = anim.from - anim.to;
    var w = SPRING_OMEGA;
    var e = Math.exp(-w * t);
    return {
        pos: anim.to + (x0 + (anim.vel + w * x0) * t) * e,
        vel: (anim.vel - w * (anim.vel + w * x0) * t) * e,
    };
}

/// A slide is over once it is within half a pixel and nearly still.
function springDone(state, to) {
    return Math.abs(state.pos - to) < 0.5 && Math.abs(state.vel) < 20;
}

/// The nearest candidate in `dir` from `from`, judged by rectangle centres.
/// `candidates` is a list of {item, rect}.
function neighbourIn(from, dir, candidates) {
    var c = centre(from);
    var best = null;
    for (var i = 0; i < candidates.length; i++) {
        var o = centre(candidates[i].rect);
        var dx = o.x - c.x;
        var dy = o.y - c.y;
        var primary, secondary;
        switch (dir) {
        case "left": primary = -dx; secondary = Math.abs(dy); break;
        case "right": primary = dx; secondary = Math.abs(dy); break;
        case "up": primary = -dy; secondary = Math.abs(dx); break;
        default: primary = dy; secondary = Math.abs(dx); break;
        }
        if (primary <= 0) {
            continue;
        }
        var score = primary + secondary * 2;
        if (best === null || score < best.score) {
            best = { score: score, item: candidates[i].item };
        }
    }
    return best === null ? null : best.item;
}

/// The same window on another screen: the offset it had from the corner of
/// its old screen, trimmed to fit if the new one is smaller.
function across(r, from, to) {
    var width = Math.min(r.width, to.width);
    var height = Math.min(r.height, to.height);
    return rect(clamp(to.x + r.x - from.x, to.x, to.x + to.width - width),
                clamp(to.y + r.y - from.y, to.y, to.y + to.height - height), width, height);
}

function snapRect(area, zone) {
    var split = zone.indexOf("half") >= 0 ? Math.floor(area.width / 2) : Math.floor(area.width * 2 / 3);
    if (zone.indexOf("right") === 0) {
        return rect(area.x + split, area.y, area.width - split, area.height);
    }
    return rect(area.x, area.y, split, area.height);
}

// ------------------------------------------------------------------ engine

/// The layout engine. `api` is the KWin side:
///   stackingOrder()        windows, bottom to top
///   activeWindow()         the focused window or null
///   activate(w)
///   outputs()              [{name, geometry}] (geometry is the whole screen)
///   area(outputName)       the usable area of an output on the current desktop
///   virtualScreen()        the bounding box of every screen
///   currentDesktop()       an id string
///   currentActivity()      an id string ("" without activities)
///   cursor()               {x, y}
///   setGeometry(w, rect)
///   setMaximized(w, on)
///   osd(text)
///   saveModes(object)
///   saveMemory(object)     the window memory, to hand back after a reload
///   schedule()             run arrange() on the next event-loop turn
///   animate(on)            keep calling arrange() every frame, or stop
///   now()                  milliseconds
/// `config` is {gap, outerGap, defaultMode, animate, floatingApps: [..]} and
/// `modes` the saved mode of every virtual desktop. `memory` is what the last
/// saveMemory() got: KWin keeps a window's internal id while it runs, so the
/// floating geometry of the tiles survives a reload of the script (which
/// System Settings does whenever the script's settings are applied).
function createEngine(api, config, modes, memory) {
    var gap = clamp(config.gap, 0, 64);
    var outerGap = clamp(config.outerGap, 0, 64);
    var lastWheel = -Infinity;
    var defaultMode = parseMode(config.defaultMode) || "floating";
    var floatingApps = (config.floatingApps || []).map(function (s) { return s.toLowerCase(); });
    modes = modes || {};
    memory = memory || {};
    var memorySaved = JSON.stringify(memory);

    /// Per-window layout data, by KWin's internal id.
    var windows = {};
    /// The tiles of one desktop, activity and output, in layout order, plus
    /// the strip scroll of the columns mode. Keyed by tilingKey().
    var tilings = {};
    /// New windows and the window that had the focus when they opened: they
    /// join the tiling right after it.
    var pending = [];
    var arranging = false;
    var scheduled = false;

    function idOf(w) {
        return String(w.internalId);
    }

    function dataOf(w) {
        var id = idOf(w);
        var d = windows[id];
        if (!d) {
            d = windows[id] = {
                win: w,
                /// Stable output ownership: columns may extend beyond its bounds.
                output: null,
                /// Taken out of the tiling by the user (Meta+Shift+F).
                floating: false,
                /// Columns: fraction of the usable width. Dwindle: fraction of
                /// the space still unallocated when it is placed. Floating:
                /// the last Meta+R size. 0 means the layout's default.
                width: 0,
                splitX: true,
                /// Dwindle: the space this tile was carved from.
                rest: null,
                /// Geometry before the window became a tile; it goes back there
                /// when the desktop returns to floating or the window is floated.
                untiled: null,
                /// The layout has this window in a tile slot right now.
                tiledNow: false,
                /// Its geometry just before it was last maximised.
                unmaximized: null,
                /// The slot the layout gave it (before any off-screen parking).
                target: null,
                /// What was last asked of KWin, to tell our moves from the user's.
                applied: null,
                snap: null,
                snapSaved: null,
                dragging: null,
            };
            var kept = memory[id];
            if (kept) {
                d.tiledNow = !!kept.tiled;
                d.untiled = kept.untiled ? copyRect(kept.untiled) : null;
                d.floating = !!kept.floating;
                d.width = typeof kept.width === "number" ? kept.width : 0;
            }
        }
        d.win = w;
        return d;
    }

    function mode() {
        return modes[api.currentDesktop()] || defaultMode;
    }

    function tilingKey(outputName) {
        return api.currentDesktop() + "|" + api.currentActivity() + "|" + outputName;
    }

    function tilingOf(key) {
        if (!tilings[key]) {
            tilings[key] = { order: [], scroll: 0, anim: null };
        }
        return tilings[key];
    }

    function schedule() {
        if (!scheduled) {
            scheduled = true;
            api.schedule();
        }
    }

    /// A window the layout looks after at all: an application's own window.
    /// KWin's own windows (the focus border, on-screen displays) have no
    /// process and are never laid out.
    function relevant(w) {
        return w && !w.deleted && w.normalWindow && !w.specialWindow && !w.popupWindow && w.pid !== -1;
    }

    function onCurrentDesktop(w) {
        if (!w.onAllDesktops) {
            var desk = api.currentDesktop();
            var on = false;
            var desktops = w.desktops || [];
            for (var i = 0; i < desktops.length; i++) {
                if (String(desktops[i].id) === desk) {
                    on = true;
                }
            }
            if (!on) {
                return false;
            }
        }
        var acts = w.activities || [];
        return acts.length === 0 || acts.indexOf(api.currentActivity()) >= 0;
    }

    function floatingApp(w) {
        var cls = String(w.resourceClass || "").toLowerCase();
        for (var i = 0; i < floatingApps.length; i++) {
            var pat = floatingApps[i];
            if (pat.charAt(pat.length - 1) === "*" ? cls.indexOf(pat.slice(0, -1)) === 0 : cls === pat) {
                return true;
            }
        }
        return false;
    }

    /// A window the tiling modes manage: not a dialog, not floating, on one
    /// desktop only (a window on every desktop would need a slot on each).
    function tileable(w) {
        var d = dataOf(w);
        return relevant(w) && !w.transient && !w.dialog && w.moveable && w.resizeable
            && !w.onAllDesktops && (w.desktops || []).length <= 1
            && !d.floating && d.snap === null && !floatingApp(w);
    }

    function isTiled(w) {
        if (!isTiling(mode()) || !tileable(w)) {
            return false;
        }
        var id = idOf(w);
        for (var key in tilings) {
            if (tilings[key].order.indexOf(id) >= 0) {
                return true;
            }
        }
        return false;
    }

    function outputByName(outs, name) {
        for (var i = 0; i < outs.length; i++) {
            if (outs[i].name === name) {
                return outs[i];
            }
        }
        return null;
    }

    function outputAt(outs, p) {
        for (var i = 0; i < outs.length; i++) {
            if (contains(outs[i].geometry, p)) {
                return outs[i];
            }
        }
        return null;
    }

    /// Squared distance from a point to a rectangle (0 inside it).
    function gapTo(r, p) {
        var dx = Math.max(r.x - p.x, p.x - (r.x + r.width), 0);
        var dy = Math.max(r.y - p.y, p.y - (r.y + r.height), 0);
        return dx * dx + dy * dy;
    }

    function nearestOutput(outs, p) {
        var best = null;
        for (var i = 0; i < outs.length; i++) {
            if (best === null || gapTo(outs[i].geometry, p) < gapTo(best.geometry, p)) {
                best = outs[i];
            }
        }
        return best;
    }

    /// The output a rectangle is most on, else the one nearest to it.
    function outputOver(outs, r) {
        var best = null;
        var bestArea = 0;
        for (var i = 0; i < outs.length; i++) {
            var hit = intersection(outs[i].geometry, r);
            if (hit && hit.width * hit.height > bestArea) {
                best = outs[i];
                bestArea = hit.width * hit.height;
            }
        }
        return best || nearestOutput(outs, centre(r));
    }

    /// Prefer a connected owner over geometry while the layout places the
    /// window: an off-screen column may overlap another display. Only an
    /// explicit move or a disconnection changes its home.
    function ownerOf(w, outs) {
        var d = dataOf(w);
        if ((isTiling(mode()) || d.snap !== null) && d.output !== null && outputByName(outs, d.output)) {
            return d.output;
        }
        var geo = w.frameGeometry;
        var best = null;
        var bestArea = -1;
        for (var i = 0; i < outs.length; i++) {
            var hit = intersection(outs[i].geometry, geo);
            var a = hit ? hit.width * hit.height : 0;
            if (a > bestArea) {
                best = outs[i];
                bestArea = a;
            }
        }
        if (bestArea <= 0 && d.output !== null && outputByName(outs, d.output)) {
            return d.output;
        }
        return best ? best.name : null;
    }

    function apply(w, r) {
        r = copyRect(r);
        var d = dataOf(w);
        d.applied = r;
        if (!sameRect(w.frameGeometry, r)) {
            api.setGeometry(w, r);
        }
    }

    /// Note where a window is before its first tile slot, so that it can go
    /// back there.
    function rememberUntiled(w) {
        var d = dataOf(w);
        if (d.tiledNow) {
            return;
        }
        d.tiledNow = true;
        // A window that is (or was a moment ago) maximised keeps the size it
        // had before, not the maximised one KWin may still report.
        var wasMaximized = w.maximizeMode || d.unmaximizing;
        d.unmaximizing = false;
        d.untiled = wasMaximized ? d.unmaximized : copyRect(w.frameGeometry);
    }

    /// Where a window leaving the tiling goes: `saved` if it is still on a
    /// screen, else a window three fifths of the output, centred. A tile that
    /// moved to another screen meanwhile takes its old place over there.
    function floatingRect(w, saved, outs) {
        var owner = ownerOf(w, outs);
        var home = owner === null ? null : outputByName(outs, owner);
        if (saved) {
            var from = outputOver(outs, saved);
            if (from && home && from !== home) {
                return across(saved, from.geometry, home.geometry);
            }
            for (var i = 0; i < outs.length; i++) {
                if (intersection(outs[i].geometry, saved)) {
                    return saved;
                }
            }
        }
        if (owner === null) {
            return null;
        }
        var area = api.area(owner);
        return centred(area, Math.round(area.width * 3 / 5), Math.round(area.height * 3 / 5));
    }

    /// A window that was a tile goes back to its floating geometry.
    function ensureUntiled(w, outs) {
        var d = dataOf(w);
        if (!d.tiledNow) {
            return;
        }
        d.tiledNow = false;
        var saved = d.untiled;
        d.untiled = null;
        d.target = null;
        var r = floatingRect(w, saved, outs);
        if (r) {
            apply(w, r);
        }
    }

    /// A column whose slot is entirely off its own screen but on another one
    /// would show there: KWin cannot clip a window to an output, so it waits
    /// below the desktop instead until the strip scrolls back to it.
    function parked(r, out, outs) {
        if (intersection(r, out.geometry)) {
            return r;
        }
        for (var i = 0; i < outs.length; i++) {
            if (outs[i] !== out && intersection(r, outs[i].geometry)) {
                var v = api.virtualScreen();
                return rect(r.x, v.y + v.height + 64, r.width, r.height);
            }
        }
        return r;
    }

    // ------------------------------------------------------------ arranging

    /// Lay out every window of the current desktop for its mode. Returns
    /// whether a strip is still sliding.
    function arrange() {
        scheduled = false;
        if (arranging) {
            return false;
        }
        arranging = true;
        var animating = false;
        try {
            var outs = api.outputs();
            var stack = api.stackingOrder().filter(function (w) {
                return relevant(w) && onCurrentDesktop(w);
            });
            // Assign all homes before moving any geometry.
            for (var i = 0; i < stack.length; i++) {
                dataOf(stack[i]).output = ownerOf(stack[i], outs);
            }
            if (!isTiling(mode())) {
                // Only the tiling modes place new windows in an order.
                pending = [];
            }
            for (var j = 0; j < outs.length; j++) {
                animating = arrangeOutput(outs[j], outs, stack) || animating;
            }
        } finally {
            arranging = false;
        }
        api.animate(animating);
        saveMemory();
        return animating;
    }

    /// Hand the window memory to the host when it changed. Windows that are
    /// gone drop out, since only the windows seen since the start are kept.
    function saveMemory() {
        if (!api.saveMemory) {
            return;
        }
        var out = {};
        for (var id in windows) {
            var d = windows[id];
            if (d.tiledNow || d.floating || d.width) {
                out[id] = { tiled: d.tiledNow, untiled: d.untiled, floating: d.floating, width: d.width };
            }
        }
        var text = JSON.stringify(out);
        if (text !== memorySaved) {
            memorySaved = text;
            api.saveMemory(out);
        }
    }

    function arrangeOutput(out, outs, stack) {
        var m = mode();
        var area = api.area(out.name);
        var focused = api.activeWindow();
        var wins = stack.filter(function (w) { return dataOf(w).output === out.name; });
        var ids = wins.map(idOf);
        var handled = {};
        var animating = false;

        if (isTiling(m)) {
            var t = tilingOf(tilingKey(out.name));
            // Maintain the order: new tiles go after the focused window.
            t.order = t.order.filter(function (id) {
                var d = windows[id];
                return d && ids.indexOf(id) >= 0 && tileable(d.win);
            });
            var later = [];
            for (var p = 0; p < pending.length; p++) {
                var entry = pending[p];
                var pd = windows[entry.id];
                if (!pd) {
                    continue;
                }
                if (ids.indexOf(entry.id) < 0) {
                    // opened on another output; it will be picked up there
                    later.push(entry);
                    continue;
                }
                if (!tileable(pd.win) || t.order.indexOf(entry.id) >= 0) {
                    continue;
                }
                var at = entry.after === null ? -1 : t.order.indexOf(entry.after);
                t.order.splice(at < 0 ? t.order.length : at + 1, 0, entry.id);
            }
            pending = later;
            for (var k = 0; k < wins.length; k++) {
                if (tileable(wins[k]) && t.order.indexOf(ids[k]) < 0) {
                    t.order.push(ids[k]);
                }
            }
            var tiles = t.order.map(function (id) { return windows[id].win; }).filter(function (w) {
                return !w.minimized && !w.fullScreen;
            });
            var inner = rect(area.x + outerGap, area.y + outerGap,
                             Math.max(area.width - 2 * outerGap, MIN_TILE),
                             Math.max(area.height - 2 * outerGap, MIN_TILE));
            var rects;
            if (m === "dwindle") {
                var slots = dwindleRects(inner, tiles.map(function (w) { return dataOf(w).width; }), gap);
                rects = slots.map(function (s, i) {
                    var d = dataOf(tiles[i]);
                    d.splitX = s.splitX;
                    d.rest = s.rest;
                    return s.rect;
                });
                t.scroll = 0;
                t.anim = null;
            } else {
                var widths = tiles.map(function (w) { return dataOf(w).width; });
                var focusedIdx = focused ? tiles.indexOf(focused) : -1;
                var target = scrollToShow(inner.width, widths, gap, t.scroll, focusedIdx);
                var now = api.now();
                if (target !== t.scroll) {
                    // Slide from wherever the strip is right now, at the speed
                    // it already has.
                    var cur = t.anim ? springAt(t.anim, now) : { pos: t.scroll, vel: 0 };
                    t.anim = config.animate && Math.abs(cur.pos - target) >= 1
                        ? { from: cur.pos, vel: cur.vel, to: target, start: now } : null;
                    t.scroll = target;
                }
                var visual = t.scroll;
                if (t.anim) {
                    var state = springAt(t.anim, now);
                    if (springDone(state, t.anim.to)) {
                        t.anim = null;
                    } else {
                        visual = Math.round(state.pos);
                        animating = true;
                    }
                }
                rects = columnRects(inner, widths, gap, visual);
            }
            for (var n = 0; n < tiles.length; n++) {
                var w = tiles[n];
                var d = dataOf(w);
                handled[idOf(w)] = true;
                if (d.dragging) {
                    continue;
                }
                rememberUntiled(w);
                d.target = copyRect(rects[n]);
                if (w.maximizeMode) {
                    // KWin keeps a maximised window's geometry; its slot waits.
                    continue;
                }
                apply(w, m === "columns" ? parked(rects[n], out, outs) : rects[n]);
            }
        }

        for (var q = 0; q < wins.length; q++) {
            var fw = wins[q];
            var fd = dataOf(fw);
            if (handled[ids[q]] || fd.dragging || fw.fullScreen || fw.minimized) {
                continue;
            }
            if (fd.snap !== null) {
                apply(fw, snapRect(area, fd.snap));
            } else if (!fw.maximizeMode) {
                ensureUntiled(fw, outs);
            }
        }
        return animating;
    }

    // ------------------------------------------------------------- commands

    /// Switch the current desktop's layout mode.
    function setMode(next, quiet) {
        next = parseMode(next);
        if (next === null || next === mode()) {
            return;
        }
        modes[api.currentDesktop()] = next;
        api.saveModes(modes);
        if (isTiling(next)) {
            // Start from the stacking order and show the tiles right away:
            // a maximised window would hide them.
            var prefix = api.currentDesktop() + "|";
            for (var key in tilings) {
                if (key.indexOf(prefix) === 0) {
                    delete tilings[key];
                }
            }
            pending = [];
            var stack = api.stackingOrder();
            for (var i = 0; i < stack.length; i++) {
                var w = stack[i];
                if (relevant(w) && onCurrentDesktop(w) && w.maximizeMode && tileable(w)) {
                    dataOf(w).unmaximizing = true;
                    api.setMaximized(w, false);
                }
            }
        }
        if (!quiet) {
            api.osd(MODE_LABELS[next]);
        }
        schedule();
    }

    function cycleMode() {
        setMode(nextMode(mode()));
    }

    /// Take the focused window out of the tiling, or put it back.
    function toggleFloating() {
        var w = api.activeWindow();
        if (!relevant(w) || w.transient || w.dialog) {
            return;
        }
        var d = dataOf(w);
        d.floating = !d.floating;
        if (d.floating && isTiling(mode())) {
            // Back where it was before it became a tile, else a bit smaller
            // and centred.
            ensureUntiled(w, api.outputs());
        }
        schedule();
    }

    /// Meta+R: the next size preset for the focused window, whatever the
    /// layout is. A column takes a share of the strip, a dwindle tile a share
    /// of the split it was carved from, and a floating window a share of the
    /// screen about the middle it already has.
    function cycleSize() {
        var w = api.activeWindow();
        if (!relevant(w) || w.fullScreen) {
            return;
        }
        var d = dataOf(w);
        if (isTiled(w)) {
            var presets = mode() === "columns" ? COLUMN_WIDTHS : SPLIT_WIDTHS;
            var current = d.width <= 0 ? DEFAULT_COLUMN_WIDTH : d.width;
            var idx = presets.findIndex(function (p) { return Math.abs(p - current) < 0.01; });
            d.width = presets[idx < 0 ? 1 : (idx + 1) % presets.length];
            schedule();
            return;
        }
        if (w.maximizeMode) {
            api.setMaximized(w, false);
        }
        var outs = api.outputs();
        var owner = ownerOf(w, outs);
        if (owner === null) {
            return;
        }
        var area = api.area(owner);
        var fidx = FLOAT_SIZES.findIndex(function (f) { return Math.abs(f - d.width) < 0.01; });
        var fraction = FLOAT_SIZES[fidx < 0 ? 0 : (fidx + 1) % FLOAT_SIZES.length];
        d.width = fraction;
        d.snap = null;
        d.snapSaved = null;
        var size = { width: Math.max(Math.round(area.width * fraction), 240),
                     height: Math.max(Math.round(area.height * fraction), 160) };
        var c = centre(w.frameGeometry);
        apply(w, rect(
            clamp(Math.round(c.x - size.width / 2), area.x, Math.max(area.x + area.width - size.width, area.x)),
            clamp(Math.round(c.y - size.height / 2), area.y, Math.max(area.y + area.height - size.height, area.y)),
            size.width, size.height));
        schedule();
    }

    /// The windows focus and moves can reach: on screen, on this desktop.
    function visibleWindows() {
        return api.stackingOrder().filter(function (w) {
            return relevant(w) && onCurrentDesktop(w) && !w.minimized;
        });
    }

    /// Where a tile is as far as direction is concerned: its slot, not a
    /// parked position below the desktop.
    function layoutRect(w) {
        var d = dataOf(w);
        return d.tiledNow && d.target ? d.target : w.frameGeometry;
    }

    /// Meta+arrows: focus the nearest window in a direction.
    function focusDirection(dir) {
        var from = api.activeWindow();
        var visible = visibleWindows();
        if (!relevant(from)) {
            if (visible.length > 0) {
                api.activate(visible[visible.length - 1]);
            }
            return;
        }
        var home = dataOf(from).output;
        var tiling = isTiling(mode());
        var candidates = visible.filter(function (w) {
            return w !== from && (!tiling || dataOf(w).output === home);
        }).map(function (w) {
            return { item: w, rect: layoutRect(w) };
        });
        var next = neighbourIn(layoutRect(from), dir, candidates);
        if (next) {
            api.activate(next);
            schedule();
        }
    }

    /// Step through the windows in the layout order (in columns that walks
    /// the strip left and right). The keys wrap round at the ends; the wheel
    /// stops there, as niri does.
    function focusStep(forward, noWrap) {
        if (!isTiling(mode())) {
            return;
        }
        var outs = api.outputs();
        var focused = api.activeWindow();
        var out = focused && relevant(focused) ? dataOf(focused).output : null;
        if (out === null) {
            var under = outputAt(outs, api.cursor());
            out = under ? under.name : (outs.length ? outs[0].name : null);
        }
        if (out === null) {
            return;
        }
        var t = tilings[tilingKey(out)];
        var order = (t ? t.order : []).map(function (id) { return windows[id]; }).filter(function (d) {
            return d && !d.win.minimized;
        }).map(function (d) { return d.win; });
        if (order.length === 0) {
            return;
        }
        var i = focused ? order.indexOf(focused) : -1;
        var next;
        if (i >= 0) {
            next = forward ? i + 1 : i - 1;
            if (noWrap && (next < 0 || next >= order.length)) {
                return;
            }
            next = (next + order.length) % order.length;
        } else {
            next = forward ? 0 : order.length - 1;
        }
        api.activate(order[next]);
        schedule();
    }

    /// Meta+wheel: the next or previous window in the layout, one step per
    /// cooldown.
    function wheelFocus(forward) {
        var now = api.now();
        if (!isTiling(mode()) || now - lastWheel < WHEEL_COOLDOWN_MS) {
            return;
        }
        lastWheel = now;
        focusStep(forward, true);
    }

    /// New gaps from the settings; the layout follows straight away.
    function setGaps(inner, outer) {
        gap = clamp(Number(inner) || 0, 0, 64);
        outerGap = clamp(Number(outer) || 0, 0, 64);
        schedule();
    }

    /// Exchange the slots of two tiles (they may be on different outputs).
    function swap(a, b) {
        if (a === b) {
            return;
        }
        var ia = idOf(a), ib = idOf(b);
        var found = [];
        for (var key in tilings) {
            var order = tilings[key].order;
            var pa = order.indexOf(ia), pb = order.indexOf(ib);
            if (pa >= 0) found.push({ key: key, i: pa });
            if (pb >= 0) found.push({ key: key, i: pb });
        }
        if (found.length !== 2) {
            return;
        }
        var oa = tilings[found[0].key].order, ob = tilings[found[1].key].order;
        var first = oa[found[0].i], second = ob[found[1].i];
        var da = windows[first], db = windows[second];
        var outA = da.output;
        da.output = db.output;
        db.output = outA;
        oa[found[0].i] = second;
        ob[found[1].i] = first;
        schedule();
    }

    /// Move a tile one slot towards the start or the end of its order.
    function shift(w, towardsEnd) {
        var id = idOf(w);
        for (var key in tilings) {
            var order = tilings[key].order;
            var i = order.indexOf(id);
            if (i < 0) {
                continue;
            }
            var j = towardsEnd ? i + 1 : i - 1;
            if (j < 0 || j >= order.length) {
                return false;
            }
            order[i] = order[j];
            order[j] = id;
            schedule();
            return true;
        }
        return false;
    }

    /// Put a floating window against an edge ("left-half", "right-half") or
    /// give it back ("release").
    function snapWindow(w, zone) {
        var d = dataOf(w);
        var outs = api.outputs();
        if (zone === "release") {
            d.snap = null;
            var saved = d.snapSaved;
            d.snapSaved = null;
            if (saved) {
                d.output = saved.output;
                d.floating = saved.floating;
                apply(w, saved.rect);
                if (saved.maximized && !w.maximizeMode) {
                    api.setMaximized(w, true);
                }
            }
        } else {
            if (d.snapSaved === null) {
                d.snapSaved = { rect: copyRect(w.frameGeometry), floating: d.floating,
                                maximized: !!w.maximizeMode, output: ownerOf(w, outs) };
            }
            if (w.maximizeMode) {
                api.setMaximized(w, false);
            }
            d.tiledNow = false;
            d.untiled = null;
            d.target = null;
            var owner = ownerOf(w, outs);
            d.snap = zone;
            if (owner !== null) {
                d.output = owner;
                apply(w, snapRect(api.area(owner), zone));
            }
        }
        api.activate(w);
        schedule();
    }

    /// Meta+Shift+arrows: swap the focused tile with its neighbour; a floating
    /// window snaps to that half, maximises (up) or is given back (down).
    function moveDirection(dir) {
        var from = api.activeWindow();
        if (!relevant(from)) {
            return;
        }
        var d = dataOf(from);
        if (!isTiled(from)) {
            if (dir === "left" || dir === "right") {
                var want = dir === "left" ? "left-half" : "right-half";
                snapWindow(from, d.snap === want ? "release" : want);
            } else if (dir === "up") {
                if (!from.maximizeMode) {
                    api.setMaximized(from, true);
                }
            } else if (from.maximizeMode) {
                api.setMaximized(from, false);
            } else if (d.snap !== null) {
                snapWindow(from, "release");
            }
            return;
        }
        if (mode() === "columns") {
            if (dir === "left" || dir === "right") {
                shift(from, dir === "right");
            }
            return;
        }
        var candidates = visibleWindows().filter(function (w) {
            return w !== from && isTiled(w) && dataOf(w).output === d.output;
        }).map(function (w) {
            return { item: w, rect: layoutRect(w) };
        });
        var target = neighbourIn(layoutRect(from), dir, candidates);
        if (target) {
            swap(from, target);
        }
    }

    // --------------------------------------------------------------- events

    /// A new window. `existing` is a window that was already open when the
    /// script started: those join the tiling in stacking order, not after
    /// the focused window.
    function windowAdded(w, existing) {
        if (!relevant(w)) {
            return;
        }
        dataOf(w);
        if (!existing) {
            var active = api.activeWindow();
            pending.push({ id: idOf(w), after: active && active !== w ? idOf(active) : null });
        }
        schedule();
    }

    function windowRemoved(w) {
        var id = idOf(w);
        delete windows[id];
        for (var key in tilings) {
            var i = tilings[key].order.indexOf(id);
            if (i >= 0) {
                tilings[key].order.splice(i, 1);
            }
        }
        pending = pending.filter(function (p) { return p.id !== id; });
        schedule();
    }

    /// Columns follow the focus: a click into a half-visible column, the task
    /// bar or Meta+arrows slide the strip so the focused column is in view.
    function windowActivated(w) {
        if (mode() === "columns") {
            schedule();
        }
    }

    /// A window changed screens. The layout's own moves (a column scrolling or
    /// parking) are not a change of home; the user's (Window to Next Screen)
    /// are, and the window joins the tiling over there.
    function windowOutputChanged(w) {
        if (!relevant(w) || arranging) {
            return;
        }
        var d = dataOf(w);
        if (d.dragging || w.fullScreen) {
            return;
        }
        var geo = w.frameGeometry;
        if (d.applied && Math.abs(geo.x - d.applied.x) < 2 && Math.abs(geo.y - d.applied.y) < 2) {
            return;
        }
        var outs = api.outputs();
        var dest = outputAt(outs, centre(geo));
        if (dest && dest.name !== d.output) {
            moveToOutput(w, dest.name);
        }
    }

    function moveToOutput(w, name) {
        var d = dataOf(w);
        d.output = name;
        var id = idOf(w);
        for (var key in tilings) {
            var i = tilings[key].order.indexOf(id);
            if (i >= 0) {
                tilings[key].order.splice(i, 1);
            }
        }
        schedule();
    }

    /// Called before a window's maximise state changes to `next`.
    function maximizing(w, next) {
        if (relevant(w) && !w.maximizeMode && next) {
            dataOf(w).unmaximized = copyRect(w.frameGeometry);
        }
    }

    function dragStarted(w, resizing) {
        if (!relevant(w)) {
            return;
        }
        var d = dataOf(w);
        d.dragging = { resize: !!resizing, start: copyRect(w.frameGeometry) };
    }

    /// A move ended: a tile dropped on another tile swaps with it, one dropped
    /// on another screen joins the tiling there. A resize ended: the tile's
    /// share of its column or split follows the edge that moved.
    function dragFinished(w) {
        if (!relevant(w)) {
            return;
        }
        var d = dataOf(w);
        var drag = d.dragging;
        d.dragging = null;
        if (!drag) {
            schedule();
            return;
        }
        if (drag.resize) {
            resized(w, drag.start);
            schedule();
            return;
        }
        var outs = api.outputs();
        var pointer = api.cursor();
        var dest = outputAt(outs, pointer) || outputAt(outs, centre(w.frameGeometry))
            || nearestOutput(outs, centre(w.frameGeometry));
        // Dragging a pinned window lets it go.
        d.snap = null;
        d.snapSaved = null;
        if (dest && dest.name !== d.output) {
            moveToOutput(w, dest.name);
            return;
        }
        if (!isTiled(w)) {
            schedule();
            return;
        }
        var stack = visibleWindows().reverse();
        for (var i = 0; i < stack.length; i++) {
            var other = stack[i];
            if (other !== w && isTiled(other) && contains(layoutRect(other), pointer)) {
                swap(w, other);
                break;
            }
        }
        schedule();
    }

    function resized(w, before) {
        if (!isTiled(w)) {
            return;
        }
        var d = dataOf(w);
        var old = d.target || before;
        var now = w.frameGeometry;
        if (mode() === "columns") {
            var inner = api.area(d.output).width - 2 * outerGap;
            d.width = now.width >= inner - 2 ? 1 : clamp(now.width / (inner - gap), 0.1, 1);
            return;
        }
        // Dwindle: a tile's right or bottom edge is its own split (when the
        // split ran that way); its left or top edge is the split of an
        // earlier tile. The rest of its edges are the edge of the area.
        var t = tilings[tilingKey(d.output)];
        if (!t) {
            return;
        }
        var tiles = t.order.map(function (id) { return windows[id].win; }).filter(function (x) {
            return !x.minimized && !x.fullScreen;
        });
        var i = tiles.indexOf(w);
        if (i < 0) {
            return;
        }
        var last = i === tiles.length - 1;
        var edges = [
            { axisX: true, far: true, before: old.x + old.width, after: now.x + now.width },
            { axisX: false, far: true, before: old.y + old.height, after: now.y + now.height },
            { axisX: true, far: false, before: old.x, after: now.x },
            { axisX: false, far: false, before: old.y, after: now.y },
        ];
        for (var e = 0; e < edges.length; e++) {
            var edge = edges[e];
            if (Math.abs(edge.after - edge.before) < 2) {
                continue;
            }
            if (edge.far) {
                if (!last && d.splitX === edge.axisX && d.rest) {
                    d.width = splitFraction(d.rest, edge.axisX, edge.after);
                }
                continue;
            }
            for (var j = i - 1; j >= 0; j--) {
                var dj = dataOf(tiles[j]);
                if (dj.splitX !== edge.axisX || !dj.target || !dj.rest) {
                    continue;
                }
                var divider = edge.axisX ? dj.target.x + dj.target.width + gap : dj.target.y + dj.target.height + gap;
                if (Math.abs(divider - edge.before) < 2) {
                    dj.width = splitFraction(dj.rest, edge.axisX, edge.after - gap);
                    break;
                }
            }
        }
    }

    /// The share of `rest` that puts its split at `edge`.
    function splitFraction(rest, axisX, edge) {
        var start = axisX ? rest.x : rest.y;
        var span = axisX ? rest.width : rest.height;
        var usable = Math.max(span - gap, 2 * MIN_TILE);
        return clamp((edge - start) / usable, 0.1, 0.9);
    }

    return {
        arrange: arrange,
        schedule: schedule,
        mode: mode,
        setMode: setMode,
        cycleMode: cycleMode,
        toggleFloating: toggleFloating,
        cycleSize: cycleSize,
        focusDirection: focusDirection,
        focusStep: focusStep,
        wheelFocus: wheelFocus,
        setGaps: setGaps,
        moveDirection: moveDirection,
        windowAdded: windowAdded,
        windowRemoved: windowRemoved,
        windowActivated: windowActivated,
        windowOutputChanged: windowOutputChanged,
        maximizing: maximizing,
        dragStarted: dragStarted,
        dragFinished: dragFinished,
        isTiled: isTiled,
        // for the tests
        _data: function (w) { return dataOf(w); },
        _tilings: tilings,
    };
}
