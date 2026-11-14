// The page: which runs are open, where the playhead is, what the keyboard does. One state, the progress `p` in
// [0, 1] of the replay; everything shown (marks drawn, elapsed time, tokens, current event) is derived from it.

import { el } from "./dom.js";
import { Diagram } from "./diagram.js";
import { FULL_RUN_MS, SPEEDS, cursorAt, formatClock, formatTokens, tOf, tokenPrefix, uOf, visible } from "./model.js";
import { KEYS, markLogRow, renderDelta, renderLog, renderPanel, renderPicker, showFile } from "./ui.js";

const $ = (id) => document.getElementById(id);
const calm = matchMedia("(prefers-reduced-motion: reduce)");
const narrow = matchMedia("(max-width: 720px)");

const state = {
  runs: [],        // the list (GET /api/runs)
  filters: {},
  open: [],        // one run, or two when comparing (GET /api/runs/<id>)
  diagrams: [],
  prefix: null,    // token prefix sums of the first run
  view: "everything",
  speed: 1,
  playing: false,
  p: 1,            // progress of the replay
  index: -1,       // the event of the first run the reader is on
  tab: "diagram",
  selected: null,  // indices shown in the detail panel
  frame: 0,
  before: 0,
  focusBack: null,
};

async function api(path) {
  const response = await fetch(path);
  if (!response.ok) throw new Error(`${response.status} on ${path.split("?")[0]}`);
  return response;
}

function say(text) {
  $("status").textContent = text;
}

// ── which runs ──────────────────────────────────────────────────────────────────────────────────────────────────

function hashRuns() {
  const params = new URLSearchParams(location.hash.slice(1));
  return [params.get("run"), params.get("b")].filter(Boolean);
}

function go(ids) {
  const params = new URLSearchParams();
  if (ids[0]) params.set("run", ids[0]);
  if (ids[1]) params.set("b", ids[1]);
  const hash = params.toString();
  if (hash === location.hash.slice(1)) route();
  else location.hash = hash;
}

function picker() {
  renderPicker($("picker"), state.runs, state.filters, state.open[0]?.id, {
    onOpen: (id) => go([id]),
    onCompare: (id) => go([state.open[0].id, id]),
    onFilter: (key, value) => {
      state.filters[key] = value;
      picker();
      $("picker").querySelector(`[data-filter="${key}"]`)?.focus();
    },
  });
}

async function loadRuns() {
  try {
    state.runs = (await (await api("/api/runs")).json()).runs;
    say("");
  } catch (error) {
    say(`The runs could not be read (${error.message}).`);
  }
  picker();
}

async function route() {
  pause();
  const ids = hashRuns();
  closePanel();
  if (!ids.length) {
    state.open = [];
    $("stage").hidden = true;
    $("picker").hidden = false;
    picker();
    return;
  }
  try {
    state.open = await Promise.all(ids.map(async (id) => (await api(`/api/runs/${encodeURIComponent(id)}`)).json()));
    say("");
  } catch (error) {
    say(`That run could not be read (${error.message}).`);
    return;
  }
  state.p = 1;
  state.index = state.open[0].events.length - 1;
  if (narrow.matches) state.tab = "log";
  stage();
}

// ── the stage ───────────────────────────────────────────────────────────────────────────────────────────────────

function stage() {
  const [a, b] = state.open;
  state.prefix = tokenPrefix(a);
  $("picker").hidden = true;
  $("choose").setAttribute("aria-expanded", "false");
  $("uncompare").hidden = !b;
  $("stage").hidden = false;
  $("diagrams").replaceChildren();
  $("diagrams").classList.toggle("compare", Boolean(b));
  state.diagrams = state.open.map((run, i) => new Diagram($("diagrams"), run, (indices) => select(indices, i)));
  renderDelta($("delta"), a, b);
  const notes = [];
  if (a.open) notes.push("This run is still open: reload to read what it wrote since.");
  if (a.bad_lines) notes.push(`${a.bad_lines} unreadable line(s) of the journal were skipped.`);
  if (a.steps.some((s) => s.source === "derived")) notes.push("This run did not mark its steps: in the workflow view, phases are derived from the delegations.");
  $("note").textContent = notes.join(" ");
  picker();
  tab(state.tab);
  for (const d of state.diagrams) {
    d.view = state.view;
    d.fit();
  }
  seek(state.p, { index: state.index });
}

function tab(name) {
  state.tab = name;
  $("tab-diagram").setAttribute("aria-selected", String(name === "diagram"));
  $("tab-log").setAttribute("aria-selected", String(name === "log"));
  $("diagrams").hidden = name !== "diagram";
  $("log").hidden = name !== "log";
  if (name === "log") {
    renderLog($("log"), state.open[0], state.view, select);
    setTimeout(() => markLogRow($("log"), state.index)?.scrollIntoView({ block: "nearest" }), 0);
  } else {
    for (const d of state.diagrams) d.fit();
    seek(state.p, { index: state.index });
  }
}

function setView(view) {
  state.view = view;
  $("view").value = view;
  for (const d of state.diagrams) d.setView(view);
  if (state.tab === "log") renderLog($("log"), state.open[0], view, select);
  seek(state.p, { index: state.index });
}

// ── the playhead ────────────────────────────────────────────────────────────────────────────────────────────────

// p: progress in [0, 1]; index: the event to stand on (default: the last one that happened); follow: scroll to it.
function seek(p, { index, follow = false, announce = false } = {}) {
  const [a] = state.open;
  if (!a) return;
  state.p = Math.min(1, Math.max(0, p));
  const u = state.p * a.time.width;
  state.index = index ?? cursorAt(a, u) - 1;
  state.diagrams.forEach((d, i) => d.setPlayhead(state.p * d.run.time.width, follow, i === 0 ? state.index : undefined));
  $("scrub").value = String(Math.round(state.p * 1000));
  $("clock").textContent = `${formatClock(tOf(a, u))} / ${formatClock(a.duration_ms)}`;
  $("spent").textContent = formatTokens(state.prefix[Math.max(0, state.index + 1)]);
  $("stage").dataset.state = state.playing ? "playing" : state.p >= 1 ? "ended" : "paused";
  $("stage").dataset.index = String(state.index);
  if (state.tab === "log") {
    const row = markLogRow($("log"), state.index);
    if (follow) row?.scrollIntoView({ block: "nearest" });
  }
  if (announce && state.index >= 0) $("live").textContent = a.events[state.index].label;
}

function tick(now) {
  const [a] = state.open;
  const elapsed = now - state.before;
  state.before = now;
  // at 1×, drawn time passes as real time does, faster for a run longer than FULL_RUN_MS
  const rate = Math.max(1, a.time.width / FULL_RUN_MS) * state.speed;
  const p = state.p + (elapsed * rate) / Math.max(1, a.time.width);
  if (p >= 1) {
    state.playing = false;
    $("play").textContent = "Play";
    $("play").setAttribute("aria-pressed", "false");
    seek(1, { follow: true, announce: true });
    return;
  }
  seek(p, { follow: true });
  state.frame = requestAnimationFrame(tick);
}

function play() {
  if (!state.open.length || state.playing) return;
  if (calm.matches) {   // no animation asked for: playing is stepping, from the start once at the end
    if (state.index >= state.open[0].events.length - 1) seek(0, { index: -1 });
    step(1);
    return;
  }
  if (state.p >= 1) seek(0);
  state.playing = true;
  $("play").textContent = "Pause";
  $("play").setAttribute("aria-pressed", "true");
  state.before = performance.now();
  $("stage").dataset.state = "playing";
  state.frame = requestAnimationFrame(tick);
}

function pause() {
  if (!state.playing) return;
  state.playing = false;
  cancelAnimationFrame(state.frame);
  $("play").textContent = "Play";
  $("play").setAttribute("aria-pressed", "false");
  seek(state.p, { announce: true });
}

// To the previous or next event the view shows.
function step(direction) {
  const [a] = state.open;
  if (!a) return;
  pause();
  let i = state.index + direction;
  while (i >= 0 && i < a.events.length && !visible(a.events[i], state.view)) i += direction;
  if (i < 0) seek(0, { index: -1, follow: true });
  else if (i < a.events.length) seek(a.events[i].u / Math.max(1, a.time.width), { index: i, follow: true, announce: true });
}

// To the previous or next start of a step or of a round.
function jump(direction) {
  const [a] = state.open;
  if (!a) return;
  pause();
  const u = state.p * a.time.width;
  const starts = [...new Set([...a.steps, ...a.rounds].map((s) => uOf(a, s.start)))].sort((x, y) => x - y);
  const target = direction > 0 ? starts.find((s) => s > u + 0.5) : starts.reverse().find((s) => s < u - 0.5);
  if (target !== undefined) seek(target / Math.max(1, a.time.width), { follow: true, announce: true });
}

function zoom(factor) {
  for (const d of state.diagrams) {
    if (factor) d.setZoom(d.zoom * factor);
    else d.fit();
  }
  seek(state.p, { index: state.index, follow: true });
}

async function reload() {
  const [a] = state.open;
  await loadRuns();
  if (!a) return;
  const at = tOf(a, state.p * a.time.width);
  pause();
  try {
    state.open = await Promise.all(state.open.map(async (run) => (await api(`/api/runs/${encodeURIComponent(run.id)}`)).json()));
  } catch (error) {
    say(`The run could not be read again (${error.message}).`);
    return;
  }
  const fresh = state.open[0];
  state.p = fresh.time.width ? uOf(fresh, Math.min(at, fresh.duration_ms)) / fresh.time.width : 1;
  state.index = cursorAt(fresh, state.p * fresh.time.width) - 1;
  stage();
  say("Read again.");
}

// ── the detail ──────────────────────────────────────────────────────────────────────────────────────────────────

// indices: events of the run `which` (0, or 1 for the run compared with): one event, or those one mark stands for.
function select(indices, which = 0) {
  const run = state.open[which];
  if (!run || !indices.length) return;
  if ($("panel").hidden) state.focusBack = document.activeElement;
  state.selected = indices;
  if (which === 0 && indices.length === 1) seek(run.events[indices[0]].u / Math.max(1, run.time.width), { index: indices[0] });
  renderPanel($("panel"), run, indices, {
    onClose: closePanel,
    onPick: (picked) => select(picked, which),
    onFile: async (path) => {
      try {
        showFile($("panel"), path, await (await api(`/api/runs/${encodeURIComponent(run.id)}/file?path=${encodeURIComponent(path)}`)).text());
      } catch (error) {
        say(`That file could not be read (${error.message}).`);
      }
    },
  });
  $("panel").hidden = false;
  document.body.classList.add("with-panel");
  $("panel").querySelector("h2").focus();
}

function closePanel() {
  if ($("panel").hidden) return;
  $("panel").hidden = true;
  document.body.classList.remove("with-panel");
  state.selected = null;
  (state.focusBack?.isConnected ? state.focusBack : state.diagrams[0]?.scroll)?.focus();
}

// ── controls ────────────────────────────────────────────────────────────────────────────────────────────────────

function setSpeed(speed) {
  state.speed = speed;
  $("speed").value = String(speed);
}

function keyboard(event) {
  const typing = event.target.closest("input, select, textarea, dialog");
  if (event.key === "Escape") {
    closePanel();
    return;
  }
  if (typing || event.metaKey || event.ctrlKey || event.altKey || !state.open.length) return;
  // what activates itself on Enter or Space (a button, a link, a disclosure) keeps those keys
  const onControl = event.target.closest("button, a[href], summary, [role=tab]");
  const speedAt = SPEEDS.indexOf(state.speed);
  const actions = {
    " ": () => (onControl ? null : state.playing ? pause() : play()),
    ArrowRight: () => step(1),
    ArrowLeft: () => step(-1),
    Home: () => { pause(); seek(0, { index: -1, follow: true }); },
    End: () => { pause(); seek(1, { follow: true, announce: true }); },
    ">": () => setSpeed(SPEEDS[Math.min(SPEEDS.length - 1, speedAt + 1)]),
    "<": () => setSpeed(SPEEDS[Math.max(0, speedAt - 1)]),
    "+": () => zoom(1.5),
    "=": () => zoom(1.5),
    "-": () => zoom(1 / 1.5),
    0: () => zoom(0),
    1: () => setView("everything"),
    2: () => setView("agents"),
    3: () => setView("tokens"),
    4: () => setView("workflow"),
    "[": () => jump(-1),
    "]": () => jump(1),
    Enter: () => (onControl || state.index < 0 ? null : select([state.index])),
    l: () => tab(state.tab === "log" ? "diagram" : "log"),
    r: () => reload(),
    "?": () => $("help").showModal(),
  };
  const action = actions[event.key] || actions[event.key.toLowerCase()];
  if (!action) return;
  if (action() !== null) event.preventDefault();
}

function start() {
  $("speed").replaceChildren(...SPEEDS.map((s) => el("option", { value: String(s), text: `${s}×`, selected: s === 1 || null })));
  $("keys").replaceChildren(...KEYS.flatMap(([key, does]) => [el("dt", { text: key }), el("dd", { text: does })]));
  $("home").addEventListener("click", (event) => { event.preventDefault(); go([]); });
  $("play").addEventListener("click", () => (state.playing ? pause() : play()));
  $("back").addEventListener("click", () => step(-1));
  $("forward").addEventListener("click", () => step(1));
  $("speed").addEventListener("change", (event) => setSpeed(Number(event.target.value)));
  $("scrub").addEventListener("input", (event) => { pause(); seek(Number(event.target.value) / 1000, { follow: true }); });
  $("view").addEventListener("change", (event) => setView(event.target.value));
  $("zoom-in").addEventListener("click", () => zoom(1.5));
  $("zoom-out").addEventListener("click", () => zoom(1 / 1.5));
  $("zoom-fit").addEventListener("click", () => zoom(0));
  $("tab-diagram").addEventListener("click", () => tab("diagram"));
  $("tab-log").addEventListener("click", () => tab("log"));
  $("reload").addEventListener("click", reload);
  $("choose").addEventListener("click", () => {
    $("picker").hidden = !$("picker").hidden;
    $("choose").setAttribute("aria-expanded", String(!$("picker").hidden));
  });
  $("uncompare").addEventListener("click", () => go([state.open[0].id]));
  $("help-open").addEventListener("click", () => $("help").showModal());
  $("help-close").addEventListener("click", () => $("help").close());
  document.addEventListener("keydown", keyboard);
  window.addEventListener("hashchange", route);
  window.addEventListener("resize", () => state.diagrams.forEach((d) => d.schedule()));
  loadRuns().then(route);
}

start();
