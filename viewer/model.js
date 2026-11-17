// Pure functions over a run as `GET /api/runs/<id>` returns it (bin/kit_serve.py › normalize). No DOM here.
// Times: `t` is real milliseconds from the start of the run, `u` drawn milliseconds (idle time compressed by the
// server: run.time.segments is the map between the two).

export const VIEWS = ["everything", "agents", "tokens", "workflow"];
export const SPEEDS = [0.5, 1, 2, 4, 8];
export const LANE_H = 34;        // px, a lane's height outside the tokens view
export const BUCKET = 8;         // px: marks of one lane closer than this are drawn as one
export const NODE_BUDGET = 1500; // SVG nodes drawn for the marks of one diagram, whatever the run's size
export const FULL_RUN_MS = 90000; // at 1×, no run takes longer than this to play
const TOKEN_KEYS = ["in", "out", "cache_read", "cache_write"];

// First index of `sorted` whose key is greater than `value`.
export function upperBound(sorted, value, key = (x) => x) {
  let lo = 0;
  let hi = sorted.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (key(sorted[mid]) <= value) lo = mid + 1;
    else hi = mid;
  }
  return lo;
}

function segmentAt(run, field, value) {
  const s = run.time.segments;
  return s[Math.min(s.length - 1, Math.max(0, upperBound(s, value, (x) => x[field]) - 1))];
}

// Real time → drawn time, and back: linear inside a segment, clamped to the run.
export function uOf(run, t) {
  const s = segmentAt(run, "t0", t);
  if (s.t1 === s.t0) return s.u0;
  return s.u0 + ((Math.min(Math.max(t, s.t0), s.t1) - s.t0) * (s.u1 - s.u0)) / (s.t1 - s.t0);
}

export function tOf(run, u) {
  const s = segmentAt(run, "u0", u);
  if (s.u1 === s.u0) return s.t0;
  return s.t0 + ((Math.min(Math.max(u, s.u0), s.u1) - s.u0) * (s.t1 - s.t0)) / (s.u1 - s.u0);
}

// What a view shows. The position of an event never depends on the view.
export function visible(event, view) {
  return !(view === "agents" && event.type === "tool.call");
}

export function sumTokens(tokens) {
  return tokens ? TOKEN_KEYS.reduce((n, k) => n + (tokens[k] || 0), 0) : 0;
}

// prefix[i] = the tokens of events 0..i-1, so the tokens spent at a playhead are one lookup.
export function tokenPrefix(run) {
  const prefix = [{ in: 0, out: 0, cache_read: 0, cache_write: 0 }];
  for (const e of run.events) {
    const last = prefix[prefix.length - 1];
    prefix.push(e.tokens ? Object.fromEntries(TOKEN_KEYS.map((k) => [k, last[k] + (e.tokens[k] || 0)])) : last);
  }
  return prefix;
}

// Number of events that have happened at drawn time u.
export function cursorAt(run, u) {
  return upperBound(run.events, u, (e) => e.u);
}

// The lanes' heights: all the same, except in the tokens view where a lane weighs what it spent.
export function laneHeights(run, view) {
  const total = sumTokens(run.totals.tokens);
  return run.lanes.map((lane) => {
    if (view !== "tokens" || !total) return LANE_H;
    return Math.max(18, Math.round((160 * sumTokens(run.totals.by_lane[lane.id])) / total));
  });
}

// Marks that stand for themselves, never merged with their neighbours.
const SINGULAR = new Set(["agent.spawn", "agent.return", "checkpoint", "answer", "guard", "github", "run.begin", "run.end"]);

// The marks to draw for the events run.events[from..to) at a zoom (px per drawn ms): one per event, except the
// marks of one lane that fall in the same bucket of pixels, drawn as one with a count. When that is still more than
// the node budget, the buckets widen and nothing stands for itself any more.
export function marksFor(run, view, from, to, zoom) {
  for (let bucket = BUCKET; ; bucket *= 2) {
    const marks = new Map();
    for (let i = from; i < to; i += 1) {
      const e = run.events[i];
      if (!visible(e, view)) continue;
      const x = e.u * zoom;
      const width = e.type === "model.turn" ? (uOf(run, e.t + e.dur) - e.u) * zoom : 0;
      const kind = e.to !== null && e.to !== e.from ? "arrow" : width >= bucket ? "bar" : "tick";
      const alone = kind === "bar" || (bucket === BUCKET && SINGULAR.has(e.type));
      const slot = alone ? `#${i}` : Math.floor(x / bucket);
      const key = `${kind}|${kind === "arrow" ? e.type : ""}|${e.from}|${e.to}|${slot}`;
      const mark = marks.get(key);
      if (mark) mark.events.push(i);
      else marks.set(key, { kind, type: e.type, from: e.from, to: e.to, x, width, events: [i] });
    }
    // a mark is a group, its title and its shape; an arrow has a tip, and at most a sign and a count
    let nodes = 0;
    for (const mark of marks.values()) nodes += mark.kind === "arrow" ? 6 : 3;
    if (nodes <= NODE_BUDGET || bucket > 1e7) return [...marks.values()];
  }
}

export function formatDuration(ms) {
  const s = Math.round(ms / 1000);
  if (s < 60) return `${s} s`;
  if (s < 3600) return `${Math.floor(s / 60)} min ${String(s % 60).padStart(2, "0")} s`;
  return `${Math.floor(s / 3600)} h ${String(Math.floor((s % 3600) / 60)).padStart(2, "0")} min`;
}

export function formatClock(ms) {
  const s = Math.floor(ms / 1000);
  const hours = Math.floor(s / 3600);
  const rest = `${String(Math.floor((s % 3600) / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
  return hours ? `${hours}:${rest}` : rest;
}

export function formatCount(n) {
  if (n >= 1e6) return `${(n / 1e6).toFixed(1)}M`;
  if (n >= 1e4) return `${Math.round(n / 1e3)}k`;
  if (n >= 1e3) return `${(n / 1e3).toFixed(1)}k`;
  return String(n);
}

export function formatTokens(tokens) {
  if (!tokens) return "";
  return `${formatCount(tokens.in)} in · ${formatCount(tokens.out)} out · ${formatCount(tokens.cache_read + tokens.cache_write)} cache`;
}

// What two runs differ by, for the comparison table: [label, a, b] with numbers where a difference means something.
export function compareRows(a, b) {
  const rounds = (r) => r.rounds.length;
  const count = (r, type, test = () => true) => r.events.filter((e) => e.type === type && test(e)).length;
  const agents = (r) => r.lanes.filter((l) => l.kind === "agent").length;
  return [
    ["duration", a.duration_ms, b.duration_ms, formatDuration],
    ["agents", agents(a), agents(b), String],
    ["fix rounds", rounds(a), rounds(b), String],
    ["guard refusals", count(a, "guard", (e) => e.d.decision === "deny"), count(b, "guard", (e) => e.d.decision === "deny"), String],
    ["tokens in", a.totals.tokens.in, b.totals.tokens.in, formatCount],
    ["tokens out", a.totals.tokens.out, b.totals.tokens.out, formatCount],
    ["cache read", a.totals.tokens.cache_read, b.totals.tokens.cache_read, formatCount],
    ["cache write", a.totals.tokens.cache_write, b.totals.tokens.cache_write, formatCount],
  ];
}
