"use strict";

const ELEMENT_IDS = ["Health", "Battery", "Ammo", "AmmoSecondary", "Money", "Timer", "Flashlight", "DeathNotice", "StatusBar"];
const ANCHORS = [
	"top_left",    "top_center",    "top_right",
	"center_left", "center",        "center_right",
	"bottom_left", "bottom_center", "bottom_right",
];
// Aliases accepted by Layout_ParseAnchor in hud_layout.cpp, normalized on load
// so the editor's <select> always holds a canonical name.
const ANCHOR_ALIASES = {
	topleft: "top_left", topcenter: "top_center", center_top: "top_center",
	topright: "top_right", centerleft: "center_left", left_center: "center_left",
	centerright: "center_right", right_center: "center_right",
	bottomleft: "bottom_left", bottomcenter: "bottom_center",
	center_bottom: "bottom_center", bottomright: "bottom_right",
};
function normalizeAnchor(name) {
	const key = String(name || "").toLowerCase();
	if (ANCHORS.includes(key)) return key;
	return ANCHOR_ALIASES[key] || "top_left";
}
const DEFAULT_RESOLUTION = { w: 2560, h: 1440 };
const SNAP_THRESHOLD_PX = 6; // in screen pixels, converted to stage units via scaleK
const HISTORY_LIMIT = 100;
const RULER_SIZE = 20;

// Representative cstrike 640-HUD footprints. The point returned by the
// runtime is the top-left for left/center elements and the right edge for
// Ammo/Money/Flashlight/DeathNotice. StatusBar receives a bottom margin.
// These previews use the same origin and scale semantics; their content is
// illustrative because live values and weapon sprites are not available in a
// standalone browser editor.
const ELEMENT_PREVIEWS = {
	Health:        { width: 94,  height: 25, fontSize: 20, scalable: true,  sample: "✚ 100" },
	Battery:       { width: 84,  height: 25, fontSize: 20, scalable: true,  sample: "▣ 100" },
	Ammo:          { width: 192, height: 32, fontSize: 20, scalable: true,  align: "right", sample: "13 | 90  ▪" },
	AmmoSecondary: { width: 106, height: 50, fontSize: 20, scalable: false, align: "right", sample: "▪ 2 | 1" },
	Money:         { width: 125, height: 25, fontSize: 20, scalable: true,  align: "right", sample: "$ 800" },
	Timer:         { width: 114, height: 25, fontSize: 20, scalable: true,  sample: "◷ 04:52" },
	Flashlight:    { width: 48,  height: 32, fontSize: 20, scalable: false, align: "right", sample: "▰" },
	DeathNotice:   { width: 240, height: 16, fontSize: 12, scalable: false, align: "right", sample: "Killer ▪ Victim" },
	StatusBar:     { width: 220, height: 13, fontSize: 13, scalable: false, originY: -4, sample: "Player: 100 HP" },
};

// Matches the shipped runtime/cstrike/scripts/HudLayout.txt defaults.
const DEFAULT_ELEMENTS = {
	Health:        { x: 10,  y: 40, anchor: "bottom_left",  scale: 1 },
	Battery:       { x: 120, y: 40, anchor: "bottom_left",  scale: 1 },
	Ammo:          { x: 20,  y: 40, anchor: "bottom_right", scale: 2 },
	AmmoSecondary: { x: 20,  y: 90, anchor: "bottom_right", scale: 1 },
	Money:         { x: 20,  y: 75, anchor: "bottom_right", scale: 2 },
	Timer:         { x: 0,   y: 35, anchor: "center",       scale: 2 },
	Flashlight:    { x: 40,  y: 10, anchor: "top_right",    scale: 2 },
	DeathNotice:   { x: 20,  y: 40, anchor: "top_right",    scale: 2 },
	StatusBar:     { x: 10,  y: 40, anchor: "bottom_left",  scale: 2 },
};

// Everything under `state` is persisted (groups via a comment line); the view
// state below is session-only and never reaches HudLayout.txt.
let state = {
	resW: DEFAULT_RESOLUTION.w,
	resH: DEFAULT_RESOLUTION.h,
	elements: {},
	decorations: [],
	groups: [],
};
let fileHandle = null;
let scaleK = 1;
let decorUidSeq = 1;

let selection = new Set();
let view = { zoom: "fit", grid: 0, snap: true, rulers: true, underlay: null, underlayAlpha: 0.6 };
let guides = [];   // {axis: "x"|"y", pos} drawn while dragging
let marquee = null; // {x, y, w, h} in stage units while rubber-band selecting
let history = [];
let future = [];

// --- Item identity -------------------------------------------------------
// Selection and groups are keyed by stable strings, never by array index:
// decorations get a runtime uid so deleting or reordering cannot silently
// repoint a selection or a group member at the wrong box.
const elKey = (id) => "el:" + id;
const decKey = (d) => "dec:" + d.uid;

function itemByKey(key) {
	if (key.startsWith("el:")) return state.elements[key.slice(3)];
	const uid = Number(key.slice(4));
	return state.decorations.find((d) => d.uid === uid);
}
function allKeys() {
	return ELEMENT_IDS.map(elKey).concat(state.decorations.map(decKey));
}
function keyLabel(key) {
	if (key.startsWith("el:")) return key.slice(3);
	const d = itemByKey(key);
	return d ? d.type : key;
}

function newConfig() {
	decorUidSeq = 1;
	state = {
		resW: DEFAULT_RESOLUTION.w,
		resH: DEFAULT_RESOLUTION.h,
		elements: JSON.parse(JSON.stringify(DEFAULT_ELEMENTS)),
		decorations: [
			makeDecoration("Shade", { x: 0, y: 0, w: DEFAULT_RESOLUTION.w, h: 36, r: 0, g: 0, b: 0, a: 140 }),
			makeDecoration("Line", { x: 10, y: 40, w: 300, h: 2, r: 255, g: 140, b: 0, a: 255 }),
		],
		groups: [],
	};
	fileHandle = null;
	selection = new Set();
	history = [];
	future = [];
	render();
}

function makeDecoration(type, over) {
	const base = {
		uid: decorUidSeq++,
		type,
		x: 20, y: 20, anchor: "top_left",
		w: 200, h: type === "Line" ? 2 : 60,
		r: 255, g: 255, b: 255, a: type === "Shade" ? 120 : 200,
		radius: type === "Panel" ? 10 : 0,
	};
	if (type === "Panel") { base.r = 20; base.g = 20; base.b = 20; }
	if (type === "Shade") { base.r = 0; base.g = 0; base.b = 0; }
	if (type === "Line") { base.r = 255; base.g = 140; base.b = 0; }
	return Object.assign(base, over);
}

// --- Anchor math: mirrors CHudBase::GetLayoutPos / Decoration_ResolveTopLeft
// in src/cs16-client/cl_dll/hud_layout.cpp exactly. Both axes resolve
// independently, same as ResolveAnchoredPos()'s two switches. ---
function anchorAxes(anchor) {
	const [vert, horiz = "center"] = anchor === "center" ? ["center", "center"] : anchor.split("_");
	return { vert, horiz };
}
function resolveAnchoredPos(anchor, lx, ly, resW, resH) {
	const { vert, horiz } = anchorAxes(anchor);
	const x = horiz === "right" ? resW - lx : horiz === "center" ? resW / 2 + lx : lx;
	const y = vert === "bottom" ? resH - ly : vert === "center" ? resH / 2 + ly : ly;
	return { x, y };
}
function inverseAnchoredPos(anchor, x, y, resW, resH) {
	const { vert, horiz } = anchorAxes(anchor);
	const lx = horiz === "right" ? resW - x : horiz === "center" ? x - resW / 2 : x;
	const ly = vert === "bottom" ? resH - y : vert === "center" ? y - resH / 2 : y;
	return { x: lx, y: ly };
}

// --- Item geometry -------------------------------------------------------
// itemOrigin is the anchor point the game resolves; itemRect is the drawn
// footprint. They differ for right-aligned elements and for StatusBar, so
// moves go through the origin while snapping and aligning use the rect.
function getElementPreview(id, e) {
	const meta = ELEMENT_PREVIEWS[id];
	const origin = resolveAnchoredPos(e.anchor, e.x, e.y, state.resW, state.resH);
	const scale = meta.scalable ? Math.max(0.1, Number(e.scale) || 1) : 1;
	const width = meta.width * scale;
	const height = meta.height * scale;
	return {
		origin,
		left: meta.align === "right" ? origin.x - width : origin.x,
		top: origin.y + (meta.originY || 0),
		width,
		height,
		scale,
	};
}

function itemOrigin(key) {
	const item = itemByKey(key);
	return resolveAnchoredPos(item.anchor, item.x, item.y, state.resW, state.resH);
}
function setItemOrigin(key, x, y) {
	const item = itemByKey(key);
	const p = inverseAnchoredPos(item.anchor, x, y, state.resW, state.resH);
	item.x = Math.round(p.x);
	item.y = Math.round(p.y);
}
function itemRect(key) {
	const item = itemByKey(key);
	if (key.startsWith("el:")) {
		const p = getElementPreview(key.slice(3), item);
		return { left: p.left, top: p.top, w: p.width, h: p.height };
	}
	const o = itemOrigin(key);
	return { left: o.x, top: o.y, w: item.w, h: item.h };
}
// Vector from the anchor point to the drawn top-left, so aligning a rect can
// be translated back into an origin.
function rectOffset(key) {
	const r = itemRect(key);
	const o = itemOrigin(key);
	return { dx: r.left - o.x, dy: r.top - o.y };
}

// --- Selection and groups ------------------------------------------------
function groupOf(key) {
	return state.groups.find((g) => g.members.includes(key));
}
// Clicking any member picks up the whole group; Alt isolates a single item.
function expandSelection(key, isolate) {
	if (isolate) return [key];
	const g = groupOf(key);
	return g ? g.members.filter((k) => itemByKey(k)) : [key];
}
function selectableKeys() {
	return allKeys().filter((k) => {
		const item = itemByKey(k);
		return item && !item.locked && !item.hidden;
	});
}
function movableSelection() {
	return [...selection].filter((k) => {
		const item = itemByKey(k);
		return item && !item.locked;
	});
}

// --- History -------------------------------------------------------------
function snapshot() {
	return JSON.stringify({
		resW: state.resW, resH: state.resH,
		elements: state.elements, decorations: state.decorations, groups: state.groups,
	});
}
// Focusing a field snapshots the pre-edit state, so identical consecutive
// snapshots are dropped to keep Ctrl+Z from stepping through no-ops.
function pushHistory() {
	const snap = snapshot();
	if (history.length && history[history.length - 1] === snap) return;
	history.push(snap);
	if (history.length > HISTORY_LIMIT) history.shift();
	future.length = 0;
}
function restore(json) {
	const s = JSON.parse(json);
	state.resW = s.resW;
	state.resH = s.resH;
	state.elements = s.elements;
	state.decorations = s.decorations;
	state.groups = s.groups;
	decorUidSeq = state.decorations.reduce((m, d) => Math.max(m, d.uid + 1), 1);
	selection = new Set([...selection].filter((k) => itemByKey(k)));
	render();
}
function undo() {
	if (!history.length) return;
	future.push(snapshot());
	restore(history.pop());
}
function redo() {
	if (!future.length) return;
	history.push(snapshot());
	restore(future.pop());
}

// --- Parser: mirrors the COM_ParseFile-based reader in hud_layout.cpp ---
function tokenize(text) {
	const tokens = [];
	let i = 0;
	const n = text.length;
	while (i < n) {
		while (i < n && /\s/.test(text[i])) i++;
		if (i >= n) break;
		if (text[i] === "/" && text[i + 1] === "/") {
			while (i < n && text[i] !== "\n") i++;
			continue;
		}
		if (text[i] === '"') {
			i++;
			const start = i;
			while (i < n && text[i] !== '"') i++;
			tokens.push(text.slice(start, i));
			i++;
		} else {
			const start = i;
			while (i < n && !/\s/.test(text[i])) i++;
			tokens.push(text.slice(start, i));
		}
	}
	return tokens;
}

// Groups are an editor-only concept, so they live in a "//" comment that
// COM_ParseFile skips. Decoration members are stored by array index (the file
// has no uids) and mapped back to uids on load.
function groupsToComment() {
	const byKey = new Map(state.decorations.map((d, i) => [decKey(d), "dec:" + i]));
	const out = state.groups
		.map((g) => ({ name: g.name, members: g.members.map((k) => byKey.get(k) || k) }))
		.filter((g) => g.members.length > 1);
	return out.length ? JSON.stringify(out) : "";
}
function groupsFromComment(text, decorations) {
	const m = text.match(/^[ \t]*\/\/[ \t]*EditorGroups:[ \t]*(\[.*\])[ \t]*$/im);
	if (!m) return [];
	let raw;
	try {
		raw = JSON.parse(m[1]);
	} catch (err) {
		return [];
	}
	if (!Array.isArray(raw)) return [];
	return raw
		.map((g) => ({
			name: String(g && g.name || "Группа"),
			members: (g && Array.isArray(g.members) ? g.members : [])
				.map((k) => {
					if (typeof k !== "string") return null;
					if (!k.startsWith("dec:")) return ELEMENT_IDS.includes(k.slice(3)) ? k : null;
					const d = decorations[Number(k.slice(4))];
					return d ? decKey(d) : null;
				})
				.filter(Boolean),
		}))
		.filter((g) => g.members.length > 1);
}

function parseHudLayout(text) {
	const resolutionMatch = text.match(/^\s*\/\/\s*Editor preview resolution:\s*(\d+)\s*x\s*(\d+)/im);
	const tokens = tokenize(text);
	let idx = 0;
	const next = () => tokens[idx++];
	const peek = () => tokens[idx];

	if (next() !== "HudLayout") throw new Error('Ожидался токен "HudLayout"');
	if (next() !== "{") throw new Error('Ожидался "{" после "HudLayout"');

	const elements = JSON.parse(JSON.stringify(DEFAULT_ELEMENTS));
	for (;;) {
		const id = next();
		if (id === undefined || id === "}") break;
		const x = parseInt(next(), 10);
		const y = parseInt(next(), 10);
		const anchor = next();
		let scale = 1;
		const maybe = peek();
		if (maybe !== undefined && maybe !== "}" && !isNaN(parseFloat(maybe)) && parseFloat(maybe) !== 0) {
			scale = parseFloat(next());
		}
		elements[id] = { x, y, anchor: normalizeAnchor(anchor), scale };
	}

	const decorations = [];
	if (peek() === "HudDecorations") {
		next();
		if (next() !== "{") throw new Error('Ожидался "{" после "HudDecorations"');
		for (;;) {
			const type = next();
			if (type === undefined || type === "}") break;
			decorations.push({
				uid: decorUidSeq++,
				type,
				x: parseInt(next(), 10),
				y: parseInt(next(), 10),
				anchor: normalizeAnchor(next()),
				w: parseInt(next(), 10),
				h: parseInt(next(), 10),
				r: parseInt(next(), 10),
				g: parseInt(next(), 10),
				b: parseInt(next(), 10),
				a: parseInt(next(), 10),
				radius: parseInt(next(), 10),
			});
		}
	}

	const parsed = { elements, decorations, groups: groupsFromComment(text, decorations) };
	if (resolutionMatch) {
		parsed.resW = parseInt(resolutionMatch[1], 10);
		parsed.resH = parseInt(resolutionMatch[2], 10);
	}
	return parsed;
}

function serializeHudLayout(st) {
	const lines = [];
	lines.push("// Customizable HUD layout for CS16Client.");
	lines.push('// Format: "id" "x" "y" "anchor" ["scale"]');
	lines.push('// Set "hud_layout_reload 1" in console to reload. Generated by tools/hud-editor.');
	lines.push(`// Editor preview resolution: ${st.resW}x${st.resH} (game uses its current screen resolution).`);
	const groups = groupsToComment();
	if (groups) lines.push(`// EditorGroups: ${groups}`);
	lines.push('"HudLayout"');
	lines.push("{");
	for (const id of ELEMENT_IDS) {
		const e = st.elements[id] || DEFAULT_ELEMENTS[id];
		lines.push(`\t "${id}" "${e.x}" "${e.y}" "${e.anchor}" "${e.scale}"`);
	}
	lines.push("}");
	lines.push("");
	lines.push('// "Type" "x" "y" "anchor" "w" "h" "r" "g" "b" "a" "radius"');
	lines.push('"HudDecorations"');
	lines.push("{");
	for (const d of st.decorations) {
		lines.push(`\t "${d.type}" "${d.x}" "${d.y}" "${d.anchor}" "${d.w}" "${d.h}" "${d.r}" "${d.g}" "${d.b}" "${d.a}" "${d.radius}"`);
	}
	lines.push("}");
	return lines.join("\n") + "\n";
}

// --- Color helpers ---
function rgbToHex(r, g, b) {
	return "#" + [r, g, b].map((v) => Math.max(0, Math.min(255, v | 0)).toString(16).padStart(2, "0")).join("");
}
function hexToRgb(hex) {
	const n = parseInt(hex.slice(1), 16);
	return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}

// --- Drag primitive ------------------------------------------------------
// The delta is measured from the mousedown point and accumulated as a float,
// so callers apply round(start + delta) once per frame. Summing per-event
// deltas instead would drop every fraction that rounds to zero, which at a
// fitted 2560x1440 stage (scaleK ~ 0.35) makes precise placement impossible.
function beginDrag(startEv, onMove, onEnd) {
	const sx = startEv.clientX;
	const sy = startEv.clientY;
	let moved = false;
	function move(ev) {
		if (!moved && Math.abs(ev.clientX - sx) + Math.abs(ev.clientY - sy) < 3) return;
		moved = true;
		onMove((ev.clientX - sx) / scaleK, (ev.clientY - sy) / scaleK, ev);
	}
	function up() {
		document.removeEventListener("mousemove", move);
		document.removeEventListener("mouseup", up);
		if (onEnd) onEnd(moved);
	}
	document.addEventListener("mousemove", move);
	document.addEventListener("mouseup", up);
}

function stagePoint(ev) {
	const r = document.getElementById("stage").getBoundingClientRect();
	return { x: (ev.clientX - r.left) / scaleK, y: (ev.clientY - r.top) / scaleK };
}

// --- Snapping ------------------------------------------------------------
function unionRect(rects) {
	let l = Infinity, t = Infinity, r = -Infinity, b = -Infinity;
	for (const rc of rects) {
		l = Math.min(l, rc.left);
		t = Math.min(t, rc.top);
		r = Math.max(r, rc.left + rc.w);
		b = Math.max(b, rc.top + rc.h);
	}
	return { left: l, top: t, w: r - l, h: b - t };
}

// Snaps the moving selection's bounding box to the stage edges/center, to the
// edges/centers of every other visible item, or to the grid. Returns a single
// offset applied to the whole group so relative spacing is preserved.
function computeSnap(keys, startRects, dx, dy) {
	if (!view.snap) return { dx: 0, dy: 0, guides: [] };
	const thr = SNAP_THRESHOLD_PX / scaleK;
	const bb = unionRect([...startRects.values()]);
	const l = bb.left + dx, t = bb.top + dy;
	const movingX = [l, l + bb.w / 2, l + bb.w];
	const movingY = [t, t + bb.h / 2, t + bb.h];

	const targetsX = [0, state.resW / 2, state.resW];
	const targetsY = [0, state.resH / 2, state.resH];
	for (const k of allKeys()) {
		const item = itemByKey(k);
		if (keys.includes(k) || item.hidden) continue;
		const r = itemRect(k);
		targetsX.push(r.left, r.left + r.w / 2, r.left + r.w);
		targetsY.push(r.top, r.top + r.h / 2, r.top + r.h);
	}

	const best = (moving, targets) => {
		let diff = null, pos = null;
		for (const m of moving) {
			for (const tg of targets) {
				const d = tg - m;
				if (Math.abs(d) <= thr && (diff === null || Math.abs(d) < Math.abs(diff))) {
					diff = d;
					pos = tg;
				}
			}
		}
		return { diff, pos };
	};

	const sx = best(movingX, targetsX);
	const sy = best(movingY, targetsY);
	const out = { dx: 0, dy: 0, guides: [] };
	if (sx.diff !== null) {
		out.dx = sx.diff;
		out.guides.push({ axis: "x", pos: sx.pos });
	} else if (view.grid > 0) {
		out.dx = Math.round(l / view.grid) * view.grid - l;
	}
	if (sy.diff !== null) {
		out.dy = sy.diff;
		out.guides.push({ axis: "y", pos: sy.pos });
	} else if (view.grid > 0) {
		out.dy = Math.round(t / view.grid) * view.grid - t;
	}
	return out;
}

// --- Moving --------------------------------------------------------------
function startMoveDrag(ev) {
	const keys = movableSelection();
	if (!keys.length) return;
	const starts = new Map(keys.map((k) => [k, itemOrigin(k)]));
	const startRects = new Map(keys.map((k) => [k, itemRect(k)]));
	let pushed = false;
	beginDrag(ev, (dx, dy, mev) => {
		if (!pushed) {
			pushHistory();
			pushed = true;
		}
		// Alt bypasses snapping; every member round-trips through its own
		// anchor so a group mixing bottom_left and top_right stays rigid.
		const snap = mev.altKey ? { dx: 0, dy: 0, guides: [] } : computeSnap(keys, startRects, dx, dy);
		guides = snap.guides;
		for (const k of keys) {
			const s = starts.get(k);
			setItemOrigin(k, s.x + dx + snap.dx, s.y + dy + snap.dy);
		}
		renderStage();
	}, () => {
		guides = [];
		renderStage();
		renderLists();
	});
}

function nudgeSelection(dx, dy) {
	const keys = movableSelection();
	if (!keys.length) return;
	pushHistory();
	for (const k of keys) {
		const o = itemOrigin(k);
		setItemOrigin(k, o.x + dx, o.y + dy);
	}
	render();
}

// --- Align / distribute --------------------------------------------------
function alignSelection(mode) {
	const keys = movableSelection();
	if (keys.length < 2) return;
	pushHistory();
	const bb = unionRect(keys.map(itemRect));
	for (const k of keys) {
		const r = itemRect(k);
		const off = rectOffset(k);
		let left = r.left, top = r.top;
		if (mode === "left") left = bb.left;
		if (mode === "hcenter") left = bb.left + (bb.w - r.w) / 2;
		if (mode === "right") left = bb.left + bb.w - r.w;
		if (mode === "top") top = bb.top;
		if (mode === "vcenter") top = bb.top + (bb.h - r.h) / 2;
		if (mode === "bottom") top = bb.top + bb.h - r.h;
		setItemOrigin(k, left - off.dx, top - off.dy);
	}
	render();
}

// Equalizes the gaps between rects along one axis, keeping the outermost two
// in place.
function distributeSelection(axis) {
	const keys = movableSelection();
	if (keys.length < 3) return;
	pushHistory();
	const entries = keys.map((k) => ({ k, r: itemRect(k) }));
	entries.sort((a, b) => (axis === "x" ? a.r.left - b.r.left : a.r.top - b.r.top));
	const first = entries[0].r;
	const last = entries[entries.length - 1].r;
	const span = axis === "x"
		? (last.left + last.w) - first.left
		: (last.top + last.h) - first.top;
	const used = entries.reduce((s, e) => s + (axis === "x" ? e.r.w : e.r.h), 0);
	const gap = (span - used) / (entries.length - 1);
	let cursor = axis === "x" ? first.left : first.top;
	for (const e of entries) {
		const off = rectOffset(e.k);
		if (axis === "x") setItemOrigin(e.k, cursor - off.dx, e.r.top - off.dy);
		else setItemOrigin(e.k, e.r.left - off.dx, cursor - off.dy);
		cursor += (axis === "x" ? e.r.w : e.r.h) + gap;
	}
	render();
}

// --- Rendering -----------------------------------------------------------
function layoutStageScale() {
	const wrap = document.getElementById("stageWrap");
	const chrome = 24 + (view.rulers ? RULER_SIZE : 0);
	const availW = wrap.clientWidth - chrome;
	const availH = wrap.clientHeight - chrome;
	if (view.zoom === "fit") {
		scaleK = Math.min(1, availW / state.resW, availH / state.resH);
	} else {
		scaleK = view.zoom;
	}
	if (!isFinite(scaleK) || scaleK <= 0) scaleK = 1;

	const sizer = document.getElementById("stageSizer");
	sizer.style.width = Math.round(state.resW * scaleK) + "px";
	sizer.style.height = Math.round(state.resH * scaleK) + "px";
	document.getElementById("stageArea").classList.toggle("no-rulers", !view.rulers);
	document.getElementById("zoomHint").textContent = Math.round(scaleK * 100) + "%";
}

// Ticks are labelled in game pixels, so the numbers stay meaningful at any zoom.
function renderRulers() {
	const top = document.getElementById("rulerTop");
	const left = document.getElementById("rulerLeft");
	top.innerHTML = "";
	left.innerHTML = "";
	if (!view.rulers) return;
	const step = [50, 100, 200, 500, 1000].find((s) => s * scaleK >= 60) || 1000;
	for (let x = 0; x <= state.resW; x += step) {
		const t = document.createElement("span");
		t.className = "tick";
		t.style.left = x * scaleK + "px";
		t.textContent = x;
		top.appendChild(t);
	}
	for (let y = 0; y <= state.resH; y += step) {
		const t = document.createElement("span");
		t.className = "tick";
		t.style.top = y * scaleK + "px";
		t.textContent = y;
		left.appendChild(t);
	}
}

function renderStage() {
	layoutStageScale();
	renderRulers();
	const stage = document.getElementById("stage");
	stage.style.width = state.resW + "px";
	stage.style.height = state.resH + "px";
	stage.style.transform = `scale(${scaleK})`;
	stage.style.backgroundImage = view.grid > 0
		? `repeating-linear-gradient(to right, rgba(255,255,255,.07) 0 1px, transparent 1px ${view.grid}px),` +
		  `repeating-linear-gradient(to bottom, rgba(255,255,255,.07) 0 1px, transparent 1px ${view.grid}px)`
		: "none";
	stage.innerHTML = "";

	if (view.underlay) {
		const under = document.createElement("div");
		under.className = "underlay";
		under.style.backgroundImage = `url(${view.underlay})`;
		under.style.opacity = view.underlayAlpha;
		stage.appendChild(under);
	}

	// Decorations first (painter's algorithm matches CHud::DrawDecorations()
	// being called before every HUD element's Draw()).
	for (const d of state.decorations) {
		const key = decKey(d);
		if (d.hidden) continue;
		const pos = resolveAnchoredPos(d.anchor, d.x, d.y, state.resW, state.resH);
		const box = document.createElement("div");
		box.className = "decor-box type-" + d.type.toLowerCase() +
			(selection.has(key) ? " selected" : "") + (d.locked ? " locked" : "");
		box.style.left = pos.x + "px";
		box.style.top = pos.y + "px";
		box.style.width = d.w + "px";
		box.style.height = d.h + "px";
		box.style.background = `rgba(${d.r}, ${d.g}, ${d.b}, ${d.a / 255})`;
		if (d.type === "Panel") box.style.borderRadius = d.radius + "px";
		box.title = d.type;
		box.addEventListener("mousedown", (ev) => onItemMouseDown(ev, key));

		if (selection.has(key) && !d.locked) {
			const handle = document.createElement("div");
			handle.className = "resize-handle";
			handle.addEventListener("mousedown", (ev) => {
				ev.preventDefault();
				ev.stopPropagation();
				const w0 = d.w, h0 = d.h;
				let pushed = false;
				beginDrag(ev, (dx, dy) => {
					if (!pushed) { pushHistory(); pushed = true; }
					d.w = Math.max(2, Math.round(w0 + dx));
					d.h = Math.max(2, Math.round(h0 + dy));
					renderStage();
				}, renderLists);
			});
			box.appendChild(handle);
		}
		stage.appendChild(box);
	}

	// Required elements on top. The preview box follows the drawn footprint,
	// while the small square stays on the exact layout origin for right/bottom
	// aligned elements.
	for (const id of ELEMENT_IDS) {
		const e = state.elements[id];
		if (e.hidden) continue;
		const key = elKey(id);
		const meta = ELEMENT_PREVIEWS[id];
		const preview = getElementPreview(id, e);
		const sel = selection.has(key);

		const box = document.createElement("div");
		box.className = "hud-preview" + (sel ? " selected" : "") + (e.locked ? " locked" : "");
		box.style.left = preview.left + "px";
		box.style.top = preview.top + "px";
		box.style.width = preview.width + "px";
		box.style.height = preview.height + "px";
		box.style.setProperty("--preview-font-size", `${meta.fontSize * preview.scale}px`);
		box.style.setProperty("--preview-line-height", `${25 * preview.scale}px`);
		const label = document.createElement("span");
		label.className = "hud-preview-label";
		label.textContent = id;
		box.appendChild(label);
		const content = document.createElement("span");
		content.className = "hud-preview-content";
		content.textContent = meta.sample;
		box.appendChild(content);
		box.addEventListener("mousedown", (ev) => onItemMouseDown(ev, key));
		stage.appendChild(box);

		const origin = document.createElement("div");
		origin.className = "hud-origin" + (sel ? " selected" : "");
		origin.style.left = preview.origin.x + "px";
		origin.style.top = preview.origin.y + "px";
		origin.title = `${id}: точка layout`;
		origin.addEventListener("mousedown", (ev) => onItemMouseDown(ev, key));
		stage.appendChild(origin);
	}

	for (const g of guides) {
		const line = document.createElement("div");
		line.className = "guide guide-" + g.axis;
		if (g.axis === "x") line.style.left = g.pos + "px";
		else line.style.top = g.pos + "px";
		stage.appendChild(line);
	}

	if (marquee) {
		const box = document.createElement("div");
		box.className = "marquee";
		box.style.left = marquee.left + "px";
		box.style.top = marquee.top + "px";
		box.style.width = marquee.w + "px";
		box.style.height = marquee.h + "px";
		stage.appendChild(box);
	}
}

function anchorSelect(value, onChange) {
	const sel = document.createElement("select");
	for (const a of ANCHORS) {
		const opt = document.createElement("option");
		opt.value = a;
		opt.textContent = a;
		if (a === value) opt.selected = true;
		sel.appendChild(opt);
	}
	sel.addEventListener("change", () => onChange(sel.value));
	return sel;
}

function numberInput(value, step, onChange) {
	const inp = document.createElement("input");
	inp.type = "number";
	inp.value = value;
	if (step) inp.step = step;
	// Snapshot on focus: the value mutates on every keystroke, so this is the
	// last moment the pre-edit state is still intact.
	inp.addEventListener("focus", pushHistory);
	inp.addEventListener("input", () => onChange(parseFloat(inp.value) || 0));
	return inp;
}

function labeled(text, node) {
	const lbl = document.createElement("label");
	lbl.textContent = text;
	lbl.appendChild(node);
	return lbl;
}

function toggleButton(text, title, active, onClick) {
	const b = document.createElement("button");
	b.className = "icon-btn" + (active ? " active" : "");
	b.textContent = text;
	b.title = title;
	b.addEventListener("click", (ev) => {
		ev.stopPropagation();
		onClick();
	});
	return b;
}

// Clicking a row selects the same item the stage would, keeping both views in
// sync in either direction.
function wireRowSelection(row, key) {
	row.addEventListener("mousedown", (ev) => {
		if (ev.target.closest("input, select, button")) return;
		applySelectionClick(key, ev);
		renderStage();
		renderLists();
	});
}

function renderElementsList() {
	const list = document.getElementById("elementsList");
	list.innerHTML = "";
	for (const id of ELEMENT_IDS) {
		const e = state.elements[id];
		const key = elKey(id);
		const row = document.createElement("div");
		row.className = "elem-row" + (selection.has(key) ? " selected" : "");
		row.dataset.key = key;

		const head = document.createElement("div");
		head.className = "row-head";
		const title = document.createElement("b");
		title.textContent = id;
		head.appendChild(title);
		const tools = document.createElement("span");
		tools.className = "row-tools";
		const g = groupOf(key);
		if (g) {
			const badge = document.createElement("span");
			badge.className = "group-badge";
			badge.textContent = g.name;
			tools.appendChild(badge);
		}
		tools.appendChild(toggleButton(e.hidden ? "🚫" : "👁", "Скрыть на превью", e.hidden, () => {
			e.hidden = !e.hidden;
			if (e.hidden) selection.delete(key);
			render();
		}));
		tools.appendChild(toggleButton(e.locked ? "🔒" : "🔓", "Заблокировать от перетаскивания", e.locked, () => {
			e.locked = !e.locked;
			render();
		}));
		head.appendChild(tools);
		row.appendChild(head);

		const grid = document.createElement("div");
		grid.className = "field-grid";
		grid.appendChild(labeled("x", numberInput(e.x, 1, (v) => { e.x = Math.round(v); renderStage(); })));
		grid.appendChild(labeled("y", numberInput(e.y, 1, (v) => { e.y = Math.round(v); renderStage(); })));
		const scaleInput = numberInput(e.scale, 0.1, (v) => { e.scale = Math.max(0.1, v); renderStage(); });
		scaleInput.min = "0.1";
		scaleInput.disabled = !ELEMENT_PREVIEWS[id].scalable;
		scaleInput.title = scaleInput.disabled ? "Для этого элемента scale не поддерживается игрой" : "Масштабирует глифы элемента";
		grid.appendChild(labeled("scale", scaleInput));
		grid.appendChild(labeled("anchor", anchorSelect(e.anchor, (v) => { pushHistory(); e.anchor = v; renderStage(); })));
		row.appendChild(grid);

		wireRowSelection(row, key);
		list.appendChild(row);
	}
}

function renderDecorationsList() {
	const list = document.getElementById("decorationsList");
	list.innerHTML = "";
	state.decorations.forEach((d, i) => {
		const key = decKey(d);
		const row = document.createElement("div");
		row.className = "decor-row" + (selection.has(key) ? " selected" : "");
		row.dataset.key = key;

		const head = document.createElement("div");
		head.className = "row-head";
		const title = document.createElement("b");
		title.textContent = `${i + 1}. ${d.type}`;
		head.appendChild(title);
		const tools = document.createElement("span");
		tools.className = "row-tools";
		const g = groupOf(key);
		if (g) {
			const badge = document.createElement("span");
			badge.className = "group-badge";
			badge.textContent = g.name;
			tools.appendChild(badge);
		}
		// Draw order is the file order, so these buttons are the only z-control:
		// a later entry is drawn later and therefore sits on top.
		tools.appendChild(toggleButton("↑", "Выше в списке — рисуется раньше (под остальными)", false, () => moveDecoration(i, -1)));
		tools.appendChild(toggleButton("↓", "Ниже в списке — рисуется позже (поверх)", false, () => moveDecoration(i, 1)));
		tools.appendChild(toggleButton(d.hidden ? "🚫" : "👁", "Скрыть на превью", d.hidden, () => {
			d.hidden = !d.hidden;
			if (d.hidden) selection.delete(key);
			render();
		}));
		tools.appendChild(toggleButton(d.locked ? "🔒" : "🔓", "Заблокировать от перетаскивания", d.locked, () => {
			d.locked = !d.locked;
			render();
		}));
		const del = document.createElement("button");
		del.className = "icon-btn del-btn";
		del.textContent = "×";
		del.title = "Удалить";
		del.addEventListener("click", (ev) => {
			ev.stopPropagation();
			pushHistory();
			removeDecorations([key]);
			render();
		});
		tools.appendChild(del);
		head.appendChild(tools);
		row.appendChild(head);

		const grid = document.createElement("div");
		grid.className = "field-grid";
		grid.appendChild(labeled("x", numberInput(d.x, 1, (v) => { d.x = Math.round(v); renderStage(); })));
		grid.appendChild(labeled("y", numberInput(d.y, 1, (v) => { d.y = Math.round(v); renderStage(); })));
		grid.appendChild(labeled("w", numberInput(d.w, 1, (v) => { d.w = Math.max(2, Math.round(v)); renderStage(); })));
		grid.appendChild(labeled("h", numberInput(d.h, 1, (v) => { d.h = Math.max(2, Math.round(v)); renderStage(); })));
		grid.appendChild(labeled("anchor", anchorSelect(d.anchor, (v) => { pushHistory(); d.anchor = v; renderStage(); })));

		const colorInp = document.createElement("input");
		colorInp.type = "color";
		colorInp.value = rgbToHex(d.r, d.g, d.b);
		colorInp.addEventListener("focus", pushHistory);
		colorInp.addEventListener("input", () => {
			const rgb = hexToRgb(colorInp.value);
			d.r = rgb.r; d.g = rgb.g; d.b = rgb.b;
			renderStage();
		});
		grid.appendChild(labeled("цвет", colorInp));

		grid.appendChild(labeled("alpha", numberInput(d.a, 1, (v) => { d.a = Math.max(0, Math.min(255, Math.round(v))); renderStage(); })));

		if (d.type === "Panel") {
			grid.appendChild(labeled("radius", numberInput(d.radius, 1, (v) => { d.radius = Math.max(0, Math.round(v)); renderStage(); })));
		}

		row.appendChild(grid);
		wireRowSelection(row, key);
		list.appendChild(row);
	});
}

function renderGroupsList() {
	const list = document.getElementById("groupsList");
	list.innerHTML = "";
	document.getElementById("btnGroup").disabled = selection.size < 2;
	if (!state.groups.length) {
		const empty = document.createElement("div");
		empty.className = "hint";
		empty.textContent = "Выдели 2+ элемента и нажми «Сгруппировать».";
		list.appendChild(empty);
		return;
	}
	state.groups.forEach((g, i) => {
		const row = document.createElement("div");
		row.className = "group-row";
		const head = document.createElement("div");
		head.className = "row-head";
		const name = document.createElement("b");
		name.textContent = g.name;
		name.title = g.members.map(keyLabel).join(", ");
		head.appendChild(name);
		const tools = document.createElement("span");
		tools.className = "row-tools";
		tools.appendChild(toggleButton("◉", "Выделить группу", false, () => {
			selection = new Set(g.members.filter((k) => itemByKey(k)));
			render();
		}));
		tools.appendChild(toggleButton("✎", "Переименовать", false, () => {
			const next = prompt("Название группы", g.name);
			if (next) {
				pushHistory();
				g.name = next;
				render();
			}
		}));
		const del = document.createElement("button");
		del.className = "icon-btn del-btn";
		del.textContent = "×";
		del.title = "Разгруппировать";
		del.addEventListener("click", () => {
			pushHistory();
			state.groups.splice(i, 1);
			render();
		});
		tools.appendChild(del);
		head.appendChild(tools);
		row.appendChild(head);

		const members = document.createElement("div");
		members.className = "group-members";
		members.textContent = g.members.map(keyLabel).join(" · ");
		row.appendChild(members);
		list.appendChild(row);
	});
}

function renderLists() {
	renderElementsList();
	renderDecorationsList();
	renderGroupsList();
	const alignDisabled = selection.size < 2;
	document.querySelectorAll("[data-align]").forEach((b) => { b.disabled = alignDisabled; });
	document.querySelectorAll("[data-distribute]").forEach((b) => { b.disabled = selection.size < 3; });
	document.getElementById("selectionHint").textContent = selection.size
		? `Выделено: ${selection.size}`
		: "Ничего не выделено";
}

function render() {
	document.getElementById("resW").value = state.resW;
	document.getElementById("resH").value = state.resH;
	renderStage();
	renderLists();
}

function scrollRowIntoView(key) {
	const row = document.querySelector(`[data-key="${key}"]`);
	if (row) row.scrollIntoView({ block: "nearest" });
}

// --- Mutations -----------------------------------------------------------
function moveDecoration(i, dir) {
	const j = i + dir;
	if (j < 0 || j >= state.decorations.length) return;
	pushHistory();
	const [d] = state.decorations.splice(i, 1);
	state.decorations.splice(j, 0, d);
	render();
}

function removeDecorations(keys) {
	state.decorations = state.decorations.filter((d) => !keys.includes(decKey(d)));
	for (const k of keys) selection.delete(k);
	for (const g of state.groups) g.members = g.members.filter((k) => !keys.includes(k));
	state.groups = state.groups.filter((g) => g.members.length > 1);
}

function duplicateSelection() {
	const keys = [...selection].filter((k) => k.startsWith("dec:"));
	if (!keys.length) return;
	pushHistory();
	const copies = [];
	for (const k of keys) {
		const src = itemByKey(k);
		const copy = Object.assign({}, src, { uid: decorUidSeq++, x: src.x + 10, y: src.y + 10 });
		state.decorations.push(copy);
		copies.push(decKey(copy));
	}
	selection = new Set(copies);
	render();
}

function groupSelection() {
	if (selection.size < 2) return;
	pushHistory();
	const members = [...selection];
	// An item belongs to at most one group, so drop it from any previous one.
	for (const g of state.groups) g.members = g.members.filter((k) => !members.includes(k));
	state.groups = state.groups.filter((g) => g.members.length > 1);
	state.groups.push({ name: "Группа " + (state.groups.length + 1), members });
	render();
}

function ungroupSelection() {
	const touched = state.groups.filter((g) => g.members.some((k) => selection.has(k)));
	if (!touched.length) return;
	pushHistory();
	state.groups = state.groups.filter((g) => !touched.includes(g));
	render();
}

// --- Input ---------------------------------------------------------------
function applySelectionClick(key, ev) {
	const item = itemByKey(key);
	if (!item) return;
	const keys = expandSelection(key, ev.altKey);
	const additive = ev.ctrlKey || ev.metaKey || ev.shiftKey;
	if (additive) {
		const allSelected = keys.every((k) => selection.has(k));
		for (const k of keys) {
			if (allSelected) selection.delete(k);
			else selection.add(k);
		}
	} else if (!keys.every((k) => selection.has(k))) {
		selection = new Set(keys);
	}
}

function onItemMouseDown(ev, key) {
	ev.preventDefault();
	ev.stopPropagation();
	const item = itemByKey(key);
	if (!item || item.locked) return;
	applySelectionClick(key, ev);
	renderStage();
	renderLists();
	scrollRowIntoView(key);
	if (selection.has(key)) startMoveDrag(ev);
}

function onStageMouseDown(ev) {
	if (ev.button !== 0) return;
	const additive = ev.ctrlKey || ev.metaKey || ev.shiftKey;
	const base = additive ? new Set(selection) : new Set();
	const start = stagePoint(ev);
	selection = base;
	renderStage();
	renderLists();
	beginDrag(ev, (dx, dy) => {
		marquee = {
			left: Math.min(start.x, start.x + dx),
			top: Math.min(start.y, start.y + dy),
			w: Math.abs(dx),
			h: Math.abs(dy),
		};
		selection = new Set(base);
		for (const k of selectableKeys()) {
			const r = itemRect(k);
			const hit = r.left < marquee.left + marquee.w && r.left + r.w > marquee.left &&
				r.top < marquee.top + marquee.h && r.top + r.h > marquee.top;
			if (hit) for (const m of expandSelection(k, ev.altKey)) selection.add(m);
		}
		renderStage();
	}, () => {
		marquee = null;
		renderStage();
		renderLists();
	});
}

document.addEventListener("keydown", (ev) => {
	if (ev.target.matches("input, select, textarea")) return;
	const mod = ev.ctrlKey || ev.metaKey;
	if (mod && ev.key.toLowerCase() === "z") {
		ev.preventDefault();
		if (ev.shiftKey) redo(); else undo();
		return;
	}
	if (mod && ev.key.toLowerCase() === "y") {
		ev.preventDefault();
		redo();
		return;
	}
	if (mod && ev.key.toLowerCase() === "d") {
		ev.preventDefault();
		duplicateSelection();
		return;
	}
	if (mod && ev.key.toLowerCase() === "g") {
		ev.preventDefault();
		if (ev.shiftKey) ungroupSelection(); else groupSelection();
		return;
	}
	if (mod && ev.key.toLowerCase() === "a") {
		ev.preventDefault();
		selection = new Set(selectableKeys());
		render();
		return;
	}
	if (ev.key === "Escape") {
		selection = new Set();
		render();
		return;
	}
	if (ev.key === "Delete") {
		const keys = [...selection].filter((k) => k.startsWith("dec:") && !itemByKey(k).locked);
		if (keys.length) {
			pushHistory();
			removeDecorations(keys);
			render();
		}
		return;
	}
	const steps = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
	if (steps[ev.key]) {
		ev.preventDefault();
		const mul = ev.shiftKey ? 10 : 1;
		nudgeSelection(steps[ev.key][0] * mul, steps[ev.key][1] * mul);
	}
});

// --- Toolbar wiring ------------------------------------------------------
document.getElementById("stage").addEventListener("mousedown", onStageMouseDown);

document.getElementById("resW").addEventListener("change", (e) => { pushHistory(); state.resW = parseInt(e.target.value, 10) || DEFAULT_RESOLUTION.w; renderStage(); });
document.getElementById("resH").addEventListener("change", (e) => { pushHistory(); state.resH = parseInt(e.target.value, 10) || DEFAULT_RESOLUTION.h; renderStage(); });
document.getElementById("resPreset").addEventListener("change", (e) => {
	if (!e.target.value) return;
	const [w, h] = e.target.value.split("x").map(Number);
	pushHistory();
	state.resW = w; state.resH = h;
	e.target.value = "";
	renderStage();
	document.getElementById("resW").value = w;
	document.getElementById("resH").value = h;
});

document.getElementById("zoomSelect").addEventListener("change", (e) => {
	view.zoom = e.target.value === "fit" ? "fit" : parseFloat(e.target.value);
	renderStage();
});
document.getElementById("gridSize").addEventListener("change", (e) => {
	view.grid = Math.max(0, parseInt(e.target.value, 10) || 0);
	renderStage();
});
document.getElementById("snapToggle").addEventListener("change", (e) => { view.snap = e.target.checked; });
document.getElementById("rulersToggle").addEventListener("change", (e) => { view.rulers = e.target.checked; renderStage(); });

document.getElementById("underlayFile").addEventListener("change", (e) => {
	const file = e.target.files && e.target.files[0];
	if (!file) return;
	if (view.underlay) URL.revokeObjectURL(view.underlay);
	view.underlay = URL.createObjectURL(file);
	renderStage();
});
document.getElementById("underlayClear").addEventListener("click", () => {
	if (view.underlay) URL.revokeObjectURL(view.underlay);
	view.underlay = null;
	document.getElementById("underlayFile").value = "";
	renderStage();
});
document.getElementById("underlayAlpha").addEventListener("input", (e) => {
	view.underlayAlpha = parseInt(e.target.value, 10) / 100;
	renderStage();
});

document.querySelectorAll("[data-align]").forEach((b) => b.addEventListener("click", () => alignSelection(b.dataset.align)));
document.querySelectorAll("[data-distribute]").forEach((b) => b.addEventListener("click", () => distributeSelection(b.dataset.distribute)));
document.getElementById("btnGroup").addEventListener("click", groupSelection);
document.getElementById("btnUngroup").addEventListener("click", ungroupSelection);
document.getElementById("btnUndo").addEventListener("click", undo);
document.getElementById("btnRedo").addEventListener("click", redo);

document.querySelectorAll("[data-add]").forEach((btn) => {
	btn.addEventListener("click", () => {
		pushHistory();
		const d = makeDecoration(btn.getAttribute("data-add"));
		state.decorations.push(d);
		selection = new Set([decKey(d)]);
		render();
	});
});

document.getElementById("btnNew").addEventListener("click", () => {
	if (confirm("Сбросить текущую конфигурацию к значениям по умолчанию?")) newConfig();
});

const hasFsApi = "showOpenFilePicker" in window;
if (!hasFsApi) document.getElementById("fsapiWarning").hidden = false;

document.getElementById("btnOpen").addEventListener("click", async () => {
	if (!hasFsApi) { alert("File System Access API недоступен в этом браузере. Открой в Chrome/Edge."); return; }
	try {
		const [handle] = await window.showOpenFilePicker({
			types: [{ description: "HudLayout.txt", accept: { "text/plain": [".txt"] } }],
		});
		fileHandle = handle;
		const file = await handle.getFile();
		const text = await file.text();
		const parsed = parseHudLayout(text);
		state.elements = parsed.elements;
		state.decorations = parsed.decorations;
		state.groups = parsed.groups;
		if (parsed.resW && parsed.resH) {
			state.resW = parsed.resW;
			state.resH = parsed.resH;
		}
		selection = new Set();
		history = [];
		future = [];
		render();
	} catch (err) {
		if (err.name !== "AbortError") alert("Не удалось открыть файл: " + err.message);
	}
});

document.getElementById("btnSave").addEventListener("click", async () => {
	if (!hasFsApi) { alert("File System Access API недоступен в этом браузере. Открой в Chrome/Edge."); return; }
	try {
		if (!fileHandle) {
			fileHandle = await window.showSaveFilePicker({
				suggestedName: "HudLayout.txt",
				types: [{ description: "HudLayout.txt", accept: { "text/plain": [".txt"] } }],
			});
		}
		const writable = await fileHandle.createWritable();
		await writable.write(serializeHudLayout(state));
		await writable.close();
	} catch (err) {
		if (err.name !== "AbortError") alert("Не удалось сохранить файл: " + err.message);
	}
});

window.addEventListener("resize", renderStage);

newConfig();
