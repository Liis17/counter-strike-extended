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
const DECOR_TYPES = ["Line", "Shade", "Panel"];
const DEFAULT_RESOLUTION = { w: 2560, h: 1440 };

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

let state = {
	resW: DEFAULT_RESOLUTION.w,
	resH: DEFAULT_RESOLUTION.h,
	elements: {},
	decorations: [],
};
let fileHandle = null;
let scaleK = 1;

function newConfig() {
	state = {
		resW: DEFAULT_RESOLUTION.w,
		resH: DEFAULT_RESOLUTION.h,
		elements: JSON.parse(JSON.stringify(DEFAULT_ELEMENTS)),
		decorations: [
			{ type: "Shade", x: 0,  y: 0,  anchor: "top_left", w: DEFAULT_RESOLUTION.w, h: 36, r: 0,  g: 0,  b: 0, a: 140, radius: 0 },
			{ type: "Line",  x: 10, y: 40, anchor: "top_left", w: 300,  h: 2,  r: 255, g: 140, b: 0, a: 255, radius: 0 },
		],
	};
	fileHandle = null;
	render();
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

	const parsed = { elements, decorations };
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

// --- Drag/resize helper: converts screen mouse delta to stage-space delta ---
function beginDrag(onMove, onEnd) {
	function move(ev) {
		onMove(ev.movementX / scaleK, ev.movementY / scaleK);
	}
	function up() {
		document.removeEventListener("mousemove", move);
		document.removeEventListener("mouseup", up);
		if (onEnd) onEnd();
	}
	document.addEventListener("mousemove", move);
	document.addEventListener("mouseup", up);
}

// --- Rendering ---
function layoutStageScale() {
	const wrap = document.getElementById("stageWrap");
	const availW = wrap.clientWidth - 24;
	const availH = wrap.clientHeight - 24;
	scaleK = Math.min(1, availW / state.resW, availH / state.resH);
	if (!isFinite(scaleK) || scaleK <= 0) scaleK = 1;

	const sizer = document.getElementById("stageSizer");
	sizer.style.width = Math.round(state.resW * scaleK) + "px";
	sizer.style.height = Math.round(state.resH * scaleK) + "px";
}

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

function beginElementDrag(node, e) {
	node.addEventListener("mousedown", (ev) => {
		ev.preventDefault();
		ev.stopPropagation();
		beginDrag((dx, dy) => {
			const cur = resolveAnchoredPos(e.anchor, e.x, e.y, state.resW, state.resH);
			const np = inverseAnchoredPos(e.anchor, cur.x + dx, cur.y + dy, state.resW, state.resH);
			e.x = Math.round(np.x);
			e.y = Math.round(np.y);
			renderStage();
		}, renderElementsList);
	});
}

function render() {
	document.getElementById("resW").value = state.resW;
	document.getElementById("resH").value = state.resH;
	renderStage();
	renderElementsList();
	renderDecorationsList();
}

function renderStage() {
	layoutStageScale();
	const stage = document.getElementById("stage");
	stage.style.width = state.resW + "px";
	stage.style.height = state.resH + "px";
	stage.style.transform = `scale(${scaleK})`;
	stage.innerHTML = "";

	// Decorations first (painter's algorithm matches CHud::DrawDecorations()
	// being called before every HUD element's Draw()).
	state.decorations.forEach((d, i) => {
		const pos = resolveAnchoredPos(d.anchor, d.x, d.y, state.resW, state.resH);
		const box = document.createElement("div");
		box.className = "decor-box type-" + d.type.toLowerCase();
		box.style.left = pos.x + "px";
		box.style.top = pos.y + "px";
		box.style.width = d.w + "px";
		box.style.height = d.h + "px";
		box.style.background = `rgba(${d.r}, ${d.g}, ${d.b}, ${d.a / 255})`;
		if (d.type === "Panel") box.style.borderRadius = d.radius + "px";
		box.title = d.type;

		box.addEventListener("mousedown", (e) => {
			e.preventDefault();
			e.stopPropagation();
			beginDrag((dx, dy) => {
				const cur = resolveAnchoredPos(d.anchor, d.x, d.y, state.resW, state.resH);
				const np = inverseAnchoredPos(d.anchor, cur.x + dx, cur.y + dy, state.resW, state.resH);
				d.x = Math.round(np.x);
				d.y = Math.round(np.y);
				renderStage();
			}, renderDecorationsList);
		});

		const handle = document.createElement("div");
		handle.className = "resize-handle";
		handle.addEventListener("mousedown", (e) => {
			e.preventDefault();
			e.stopPropagation();
			beginDrag((dx, dy) => {
				d.w = Math.max(2, Math.round(d.w + dx));
				d.h = Math.max(2, Math.round(d.h + dy));
				renderStage();
			}, renderDecorationsList);
		});
		box.appendChild(handle);
		stage.appendChild(box);
	});

	// Required elements on top. The preview box follows the drawn footprint,
	// while the small square stays on the exact layout origin for right/bottom
	// aligned elements.
	for (const id of ELEMENT_IDS) {
		const e = state.elements[id];
		const meta = ELEMENT_PREVIEWS[id];
		const preview = getElementPreview(id, e);

		const box = document.createElement("div");
		box.className = "hud-preview hud-preview-" + id.toLowerCase();
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
		beginElementDrag(box, e);
		stage.appendChild(box);

		const origin = document.createElement("div");
		origin.className = "hud-origin";
		origin.style.left = preview.origin.x + "px";
		origin.style.top = preview.origin.y + "px";
		origin.title = `${id}: точка layout`;
		beginElementDrag(origin, e);
		stage.appendChild(origin);
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
	inp.addEventListener("input", () => onChange(parseFloat(inp.value) || 0));
	return inp;
}

function labeled(text, node) {
	const lbl = document.createElement("label");
	lbl.textContent = text;
	lbl.appendChild(node);
	return lbl;
}

function renderElementsList() {
	const list = document.getElementById("elementsList");
	list.innerHTML = "";
	for (const id of ELEMENT_IDS) {
		const e = state.elements[id];
		const row = document.createElement("div");
		row.className = "elem-row";

		const head = document.createElement("div");
		head.className = "row-head";
		head.innerHTML = `<b>${id}</b>`;
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
		grid.appendChild(labeled("anchor", anchorSelect(e.anchor, (v) => { e.anchor = v; renderStage(); })));
		row.appendChild(grid);

		list.appendChild(row);
	}
}

function renderDecorationsList() {
	const list = document.getElementById("decorationsList");
	list.innerHTML = "";
	state.decorations.forEach((d, i) => {
		const row = document.createElement("div");
		row.className = "decor-row";

		const head = document.createElement("div");
		head.className = "row-head";
		const title = document.createElement("b");
		title.textContent = d.type;
		head.appendChild(title);
		const del = document.createElement("button");
		del.className = "del-btn";
		del.textContent = "×";
		del.addEventListener("click", () => {
			state.decorations.splice(i, 1);
			render();
		});
		head.appendChild(del);
		row.appendChild(head);

		const grid = document.createElement("div");
		grid.className = "field-grid";
		grid.appendChild(labeled("x", numberInput(d.x, 1, (v) => { d.x = Math.round(v); renderStage(); })));
		grid.appendChild(labeled("y", numberInput(d.y, 1, (v) => { d.y = Math.round(v); renderStage(); })));
		grid.appendChild(labeled("w", numberInput(d.w, 1, (v) => { d.w = Math.max(2, Math.round(v)); renderStage(); })));
		grid.appendChild(labeled("h", numberInput(d.h, 1, (v) => { d.h = Math.max(2, Math.round(v)); renderStage(); })));
		grid.appendChild(labeled("anchor", anchorSelect(d.anchor, (v) => { d.anchor = v; renderStage(); })));

		const colorInp = document.createElement("input");
		colorInp.type = "color";
		colorInp.value = rgbToHex(d.r, d.g, d.b);
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
		list.appendChild(row);
	});
}

// --- Toolbar wiring ---
document.getElementById("resW").addEventListener("change", (e) => { state.resW = parseInt(e.target.value, 10) || DEFAULT_RESOLUTION.w; renderStage(); });
document.getElementById("resH").addEventListener("change", (e) => { state.resH = parseInt(e.target.value, 10) || DEFAULT_RESOLUTION.h; renderStage(); });
document.getElementById("resPreset").addEventListener("change", (e) => {
	if (!e.target.value) return;
	const [w, h] = e.target.value.split("x").map(Number);
	state.resW = w; state.resH = h;
	e.target.value = "";
	renderStage();
	document.getElementById("resW").value = w;
	document.getElementById("resH").value = h;
});

document.querySelectorAll("[data-add]").forEach((btn) => {
	btn.addEventListener("click", () => {
		const type = btn.getAttribute("data-add");
		const base = { x: 20, y: 20, anchor: "top_left", w: 200, h: type === "Line" ? 2 : 60, r: 255, g: 255, b: 255, a: type === "Shade" ? 120 : 200, radius: type === "Panel" ? 10 : 0 };
		if (type === "Panel") { base.r = 20; base.g = 20; base.b = 20; }
		if (type === "Shade") { base.r = 0; base.g = 0; base.b = 0; }
		if (type === "Line") { base.r = 255; base.g = 140; base.b = 0; }
		state.decorations.push(Object.assign({ type }, base));
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
		if (parsed.resW && parsed.resH) {
			state.resW = parsed.resW;
			state.resH = parsed.resH;
		}
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
