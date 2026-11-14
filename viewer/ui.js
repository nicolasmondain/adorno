// Everything around the diagram: the list of runs and its filters, the text log, the detail panel, the comparison
// table. Each function fills an element from data and calls back; none keeps state.

import { el } from "./dom.js";
import { compareRows, formatClock, formatCount, formatDuration, formatTokens, visible } from "./model.js";

const LOG_CHUNK = 200; // rows of the text log added per tick, so a long run never freezes the page

function option(value, label, selected) {
  return el("option", { value, text: label, selected: selected || null });
}

function choices(label, key, values, filters, onChange) {
  return el("label", {}, el("span", { text: label }),
    el("select", { "data-filter": key, on: { change: (e) => onChange(key, e.target.value) } },
      option("", "all", !filters[key]), ...values.map((v) => option(v, v, filters[key] === v))));
}

export function matches(run, filters) {
  return (!filters.workflow || run.workflow === filters.workflow)
    && (!filters.repo || run.repos.includes(filters.repo))
    && (!filters.outcome || run.outcome === filters.outcome)
    && (!filters.date || (run.start || "").startsWith(filters.date));
}

// The runs that have a journal: filters, then one row per run. onOpen(id), onCompare(id), onFilter(key, value).
export function renderPicker(root, runs, filters, compareWith, handlers) {
  const unique = (values) => [...new Set(values.filter(Boolean))].sort();
  const shown = runs.filter((run) => matches(run, filters));
  root.replaceChildren(
    el("div", { class: "filters" },
      choices("workflow", "workflow", unique(runs.map((r) => r.workflow)), filters, handlers.onFilter),
      choices("repo", "repo", unique(runs.flatMap((r) => r.repos)), filters, handlers.onFilter),
      choices("outcome", "outcome", unique(runs.map((r) => r.outcome)), filters, handlers.onFilter),
      el("label", {}, el("span", { text: "day" }),
        el("input", { type: "date", value: filters.date || null, "data-filter": "date", on: { change: (e) => handlers.onFilter("date", e.target.value) } })),
      el("span", { class: "count", text: `${shown.length} of ${runs.length} runs` })),
    shown.length === 0
      ? el("p", { class: "empty", text: runs.length ? "No run matches these filters." : "No journal yet: a run opened with run-begin writes one under ~/.adorno/runs." })
      : el("table", { class: "runs" },
        el("thead", {}, el("tr", {}, ...["run", "repos", "started", "lasted", "outcome", "agents", "tokens", ""].map((t) => el("th", { text: t, scope: "col" })))),
        el("tbody", {}, ...shown.map((run) => el("tr", { "data-run": run.id },
          el("td", {}, el("button", { class: "open", text: run.workflow || run.id, title: run.id, on: { click: () => handlers.onOpen(run.id) } })),
          el("td", { text: run.repos.join(", ") }),
          el("td", { text: (run.start || "").replace("T", " ").slice(0, 16) }),
          el("td", { text: formatDuration(run.duration_ms) }),
          el("td", {}, el("span", { class: `badge ${run.outcome === "open" ? "open" : ""}`, text: run.outcome }),
            run.bad_lines ? el("span", { class: "badge open", text: `${run.bad_lines} unreadable` }) : null),
          el("td", { text: String(run.agents) }),
          el("td", { text: formatTokens(run.tokens) }),
          el("td", {}, compareWith && compareWith !== run.id
            ? el("button", { class: "compare", text: "compare", on: { click: () => handlers.onCompare(run.id) } }) : null))))));
}

// The same events as the diagram, as text: one row per event, a button that opens its detail.
export function renderLog(root, run, view, onSelect) {
  const list = el("ol", { class: "log-rows" });
  root.replaceChildren(list);
  const names = Object.fromEntries(run.lanes.map((l) => [l.id, l.label]));
  const rows = run.events.filter((e) => visible(e, view));
  root.dataset.rows = String(rows.length);
  let next = 0;
  const more = () => {
    if (!list.isConnected) return;
    list.append(...rows.slice(next, next + LOG_CHUNK).map((e) => el("li", { "data-i": e.i },
      el("button", { on: { click: () => onSelect([e.i]) } },
        el("time", { text: formatClock(e.t) }),
        el("span", { class: "who", text: e.to ? `${names[e.from] || e.from} → ${names[e.to] || e.to}` : names[e.from] || e.from }),
        el("span", { class: "what", text: e.label })))));
    next += LOG_CHUNK;
    if (next < rows.length) setTimeout(more, 0);
  };
  more();
}

export function markLogRow(root, index) {
  root.querySelector("[aria-current]")?.removeAttribute("aria-current");
  const row = root.querySelector(`li[data-i="${index}"]`);
  row?.setAttribute("aria-current", "true");
  return row;
}

function field(name, value) {
  return value === undefined || value === null || value === "" ? null : [el("dt", { text: name }), el("dd", { text: String(value) })];
}

function copyable(name, value) {
  if (!value) return null;
  return [el("dt", { text: name }), el("dd", {}, el("code", { text: value }), " ",
    el("button", { class: "copy", text: "copy", on: { click: (e) => navigator.clipboard?.writeText(value).then(() => { e.target.textContent = "copied"; }) } }))];
}

function tokensTable(tokens) {
  return el("table", { class: "tokens" }, el("tbody", {},
    ...[["in", tokens.in], ["out", tokens.out], ["cache read", tokens.cache_read], ["cache write", tokens.cache_write]]
      .map(([name, n]) => el("tr", {}, el("th", { text: name, scope: "row" }), el("td", { text: formatCount(n || 0) })))));
}

// The detail of what the reader selected: one event, or the events one mark stands for. onClose(), onPick(indices),
// onFile(path).
export function renderPanel(root, run, indices, handlers) {
  const lanes = Object.fromEntries(run.lanes.map((l) => [l.id, l]));
  const head = el("header", {}, el("h2", { text: indices.length > 1 ? `${indices.length} events` : "Detail", tabindex: "-1" }),
    el("button", { class: "close", text: "close", "aria-label": "Close the detail", on: { click: handlers.onClose } }));
  if (indices.length > 1) {
    root.replaceChildren(head, el("ol", { class: "group" }, ...indices.map((i) => el("li", {},
      el("button", { text: `${formatClock(run.events[i].t)} ${run.events[i].label}`, on: { click: () => handlers.onPick([i]) } })))));
    return;
  }
  const e = run.events[indices[0]];
  const d = e.d;
  const about = d.agent ? lanes[`agent:${d.agent.id}`] : lanes[e.from];
  const rows = [
    field("when", `${formatClock(e.t)} after the start${e.dur ? `, lasted ${formatDuration(e.dur)}` : ""}`),
    field("who", e.to ? `${lanes[e.from]?.label || e.from} → ${lanes[e.to]?.label || e.to}` : lanes[e.from]?.label || e.from),
    field("agent", d.agent ? [d.agent.type, d.agent.id].filter(Boolean).join(" · ") : null),
    field("model", d.model || about?.model),
    field("tool", d.tool), field("input", d.input), field("script", d.script), field("arguments", d.args?.join(" ")),
    field("exit code", d.exit), field("failed", d.error ? "yes" : null),
    field("level asked", d.level), field("action", d.action), field("dry run", d.dry_run === undefined ? null : d.dry_run ? "yes" : "no"),
    field("decision", d.decision), field("reason", d.reason), field("command", d.command),
    field("question", d.question), field("answer", d.answer), field("answered by", d.by),
    field("severity", d.severity), field("finding", d.title), field("stage", d.stage), field("reviewer", d.reviewer),
    field("at", d.file && d.line ? `${d.file}:${d.line}` : null),
    field("target", d.target), field("url", d.url), field("kind", d.kind), field("source", d.source), field("stop reason", d.stop),
    field("thinking", d.thinking_tokens !== undefined || d.thinking_ms ? `${formatCount(d.thinking_tokens || 0)} tokens, ${formatDuration(d.thinking_ms || 0)}` : null),
    field("text", d.excerpt), field("length", d.chars ? `${d.chars} characters` : null),
    copyable("hash", d.hash), copyable("transcript", d.ref?.file || d.transcript), field("transcript line", d.ref?.id),
  ].filter(Boolean).flat();
  // the files an agent wrote (the server reads them from its own Write and Edit calls), on its return only
  const wrote = e.type === "agent.return" ? about?.wrote || [] : [];
  root.replaceChildren(head,
    el("p", { class: "label", text: e.label }),
    el("dl", {}, ...rows),
    e.tokens ? tokensTable(e.tokens) : null,
    d.reasoning ? el("details", {}, el("summary", { text: "reasoning" }), el("pre", { text: d.reasoning })) : null,
    wrote.length ? el("section", { class: "wrote" }, el("h3", { text: "What it wrote" }),
      el("ul", {}, ...wrote.map((w) => el("li", {}, w.file
        ? el("button", { class: "file", text: w.path, on: { click: () => handlers.onFile(w.file) } }) : el("code", { text: w.path })))))
      : null,
    run.files.length ? el("section", { class: "files" }, el("h3", { text: "Files of the run" }),
      el("ul", {}, ...run.files.map((f) => el("li", {}, el("button", { class: "file", text: f.path, on: { click: () => handlers.onFile(f.path) } })))))
      : null,
    el("pre", { class: "file-view", hidden: true }));
}

// A file of the run, as text, in the panel.
export function showFile(root, path, text) {
  const view = root.querySelector(".file-view");
  if (!view) return;
  let shown = text;
  if (path.endsWith(".json")) {
    try { shown = JSON.stringify(JSON.parse(text), null, 2); } catch { /* not JSON after all: as it is */ }
  }
  view.textContent = `${path}\n\n${shown}`;
  view.hidden = false;
  view.scrollIntoView({ block: "nearest" });
}

// Two runs side by side: what differs, as numbers.
export function renderDelta(root, a, b) {
  if (!b) {
    root.replaceChildren();
    return;
  }
  root.replaceChildren(el("table", { class: "delta" },
    el("thead", {}, el("tr", {}, ...["", a.workflow || a.id, b.workflow || b.id, "difference"].map((t) => el("th", { text: t, scope: "col" })))),
    el("tbody", {}, ...compareRows(a, b).map(([name, x, y, format]) => el("tr", {},
      el("th", { text: name, scope: "row" }), el("td", { text: format(x) }), el("td", { text: format(y) }),
      el("td", { text: x === y ? "=" : `${y > x ? "+" : "−"}${format(Math.abs(y - x))}` }))))));
}

export const KEYS = [
  ["Space", "play or pause"], ["← →", "previous or next event"], ["Home End", "start, end"], ["< >", "slower, faster"],
  ["+ − 0", "zoom in, out, fit"], ["1 2 3 4", "views: everything, agents only, tokens, workflow"],
  ["[ ]", "previous or next step or round"], ["Enter", "detail of the current event"], ["Esc", "close the detail"],
  ["L", "diagram or text log"], ["R", "reload the run"], ["?", "this help"],
];
