// The sequence diagram of one run: a lane per actor, time from left to right (idle time compressed), an arrow per
// exchange. SVG, so every mark can be clicked and described; only the marks near the visible window are in the page,
// and marks too close to tell apart are drawn as one.

import { el, svg } from "./dom.js";
import { cursorAt, formatDuration, formatTokens, laneHeights, marksFor, tOf, uOf, upperBound } from "./model.js";

const RULER = 24; // px above the lanes: the steps of the plan, the labels of the gaps
const PAD = 12;   // px left and right of the drawing

export class Diagram {
  // onSelect(indices): the events of the mark the reader clicked
  constructor(parent, run, onSelect) {
    this.run = run;
    this.onSelect = onSelect;
    this.view = "everything";
    this.zoom = 1;
    this.u = run.time.width;
    this.current = -1;
    this.marks = [];
    this.pending = false;

    this.heads = el("div", { class: "heads" });
    this.layers = Object.fromEntries(["bands", "lanes", "gaps", "rounds", "marks"].map((name) => [name, svg("g", { class: name })]));
    this.playhead = svg("line", { class: "playhead", y1: 0 });
    this.canvas = svg("svg", { class: "canvas", "aria-hidden": "true" }, ...Object.values(this.layers), this.playhead);
    this.scroll = el("div", {
      class: "scroll", tabindex: "0", role: "group",
      "aria-label": `Sequence diagram of ${run.workflow || run.id}. Arrow keys step through its events; L shows them as a text log.`,
      on: { scroll: () => this.schedule() },
    }, this.canvas);
    this.root = el("section", { class: "diagram", "data-run": run.id },
      el("h2", {},
        el("span", { text: run.workflow || "run" }), " ",
        el("small", { text: `${run.id} · ${formatDuration(run.duration_ms)} · ${formatTokens(run.totals.tokens)}` }), " ",
        el("span", { class: `badge ${run.open ? "open" : ""}`, text: run.open ? "open run" : run.outcome })),
      el("div", { class: "frame" }, this.heads, this.scroll));
    parent.append(this.root);
  }

  x(u) {
    return PAD + u * this.zoom;
  }

  fit() {
    this.setZoom((this.scroll.clientWidth - 2 * PAD) / Math.max(1, this.run.time.width));
  }

  setZoom(zoom) {
    const centre = (this.scroll.scrollLeft + this.scroll.clientWidth / 2 - PAD) / this.zoom;
    this.zoom = Math.min(2, Math.max(1e-7, zoom));
    this.layout();
    this.scroll.scrollLeft = centre * this.zoom + PAD - this.scroll.clientWidth / 2;
    this.draw();
  }

  setView(view) {
    this.view = view;
    this.layout();
    this.draw();
  }

  // Everything that does not depend on the scroll position: lanes, lifelines, gaps, rounds, steps.
  layout() {
    const { run } = this;
    const heights = laneHeights(run, this.view);
    this.mid = {};
    this.top = {};
    let y = RULER;
    this.heads.replaceChildren(el("div", { class: "ruler" }));
    this.layers.lanes.replaceChildren();
    const width = this.x(run.time.width) + PAD;
    run.lanes.forEach((lane, i) => {
      this.top[lane.id] = y;
      this.mid[lane.id] = y + heights[i] / 2;
      const spent = run.totals.by_lane[lane.id];
      const head = el("div", { class: `head ${lane.kind}${lane.orphan ? " orphan" : ""}`, "data-lane": lane.id },
        el("strong", { text: lane.label }),
        el("small", { text: this.view === "tokens" ? formatTokens(spent) || "no tokens" : [lane.model, lane.tier].filter(Boolean).join(" · ") }));
      head.style.height = `${heights[i]}px`;
      this.heads.append(head);
      const lived = lane.kind === "agent";
      this.layers.lanes.append(
        svg("line", { class: "lane-rule", x1: 0, x2: width, y1: y + heights[i], y2: y + heights[i] }),
        svg("line", {
          class: `lifeline ${lane.kind}`, "data-lane": lane.id, y1: this.mid[lane.id], y2: this.mid[lane.id],
          x1: this.x(lived ? uOf(run, lane.start) : 0), x2: this.x(lived ? uOf(run, lane.end) : run.time.width),
        }));
      y += heights[i];
    });
    this.height = y;
    this.canvas.setAttribute("width", width);
    this.canvas.setAttribute("height", y);
    this.playhead.setAttribute("y2", y);

    this.layers.gaps.replaceChildren(...run.time.segments.filter((s) => s.gap).flatMap((s) => [
      svg("rect", { class: "gap", x: this.x(s.u0), y: RULER, width: (s.u1 - s.u0) * this.zoom, height: y - RULER }),
      svg("text", { class: "gap-label", x: this.x((s.u0 + s.u1) / 2), y: RULER - 6, "text-anchor": "middle", text: `// ${formatDuration(s.t1 - s.t0)}` }),
    ]));

    const agents = run.lanes.filter((l) => l.kind === "agent").map((l) => l.id);
    this.layers.rounds.replaceChildren(...run.rounds.flatMap((round) => {
      const lanes = round.lanes.length ? round.lanes : agents;
      if (!lanes.length) return [];
      const top = Math.min(...lanes.map((id) => this.top[id]));
      const bottom = Math.max(...lanes.map((id) => 2 * this.mid[id] - this.top[id]));
      const x0 = this.x(uOf(run, round.start));
      return [
        svg("rect", { class: `round${round.round >= round.cap ? " last" : ""}`, x: x0, y: top + 2, width: Math.max(2, this.x(uOf(run, round.end)) - x0), height: bottom - top - 4 }),
        svg("text", { class: "round-label", x: x0 + 4, y: top - 3, text: `round ${round.round} / ${round.cap}` }),
      ];
    }));

    this.layers.bands.replaceChildren(...(this.view === "workflow" ? run.steps : []).flatMap((step) => {
      const x0 = this.x(uOf(run, step.start));
      const w = Math.max(2, this.x(uOf(run, step.end)) - x0);
      return [
        svg("rect", { class: "step", x: x0, y: 2, width: w, height: y - 4 }),
        svg("text", { class: "step-label", x: x0 + 4, y: 14, text: `${step.index} ${step.name || ""}` }),
      ];
    }));
  }

  schedule() {
    if (this.pending) return;
    this.pending = true;
    requestAnimationFrame(() => {
      this.pending = false;
      this.draw();
    });
  }

  // The marks of the events in view, plus one screen on each side.
  draw() {
    const { run } = this;
    const span = this.scroll.clientWidth || 800;
    const first = upperBound(run.events, (this.scroll.scrollLeft - span - PAD) / this.zoom - 1, (e) => e.u);
    const last = upperBound(run.events, (this.scroll.scrollLeft + 2 * span - PAD) / this.zoom, (e) => e.u);
    this.marks = marksFor(run, this.view, first, last, this.zoom).map((mark) => ({ ...mark, node: this.node(mark) }));
    this.layers.marks.replaceChildren(...this.marks.map((m) => m.node));
    this.paint();
  }

  node(mark) {
    const { run } = this;
    const event = run.events[mark.events[0]];
    const n = mark.events.length;
    const x = PAD + mark.x;
    const y1 = this.mid[mark.from];
    const shapes = [];
    if (mark.kind === "arrow") {
      const y2 = this.mid[mark.to];
      const dir = y2 > y1 ? 1 : -1;
      shapes.push(
        svg("line", { class: "shaft", x1: x, x2: x, y1, y2: y2 - dir * 6, pathLength: 1 }),
        svg("polygon", { class: "tip", points: `${x},${y2} ${x - 4},${y2 - dir * 7} ${x + 4},${y2 - dir * 7}` }));
      if (mark.type === "checkpoint") shapes.push(svg("circle", { class: "disc", cx: x, cy: y2, r: 5 }));
      if (mark.type === "guard") {
        shapes.push(event.d.decision === "deny"
          ? svg("path", { class: "cross", d: `M${x - 5},${y2 - 5} L${x + 5},${y2 + 5} M${x + 5},${y2 - 5} L${x - 5},${y2 + 5}` })
          : svg("circle", { class: "ring", cx: x, cy: y2, r: 5 }));
      }
      if (n > 1) shapes.push(svg("text", { class: "count", x: x + 6, y: (y1 + y2) / 2, text: String(n) }));
    } else if (mark.kind === "bar") {
      shapes.push(svg("rect", { class: "turn", x, y: y1 - 4, width: Math.max(2, mark.width), height: 8 }));
    } else if (n > 1) {
      const tall = Math.min(22, 6 + 4 * Math.log2(n));
      shapes.push(svg("rect", { class: "many", x: x - 2, y: y1 - tall / 2, width: 5, height: tall }));
    } else if (mark.type === "tool.call") {
      shapes.push(svg("circle", { class: event.d.error ? "tool failed" : "tool", cx: x, cy: y1, r: 3 }));
    } else if (mark.type === "finding") {
      shapes.push(svg("polygon", { class: `finding ${event.d.severity || ""}`, points: `${x},${y1 - 5} ${x + 5},${y1} ${x},${y1 + 5} ${x - 5},${y1}` }));
    } else if (mark.type === "message") {
      shapes.push(svg("rect", { class: "said", x: x - 3, y: y1 - 3, width: 6, height: 6 }));
    } else {
      shapes.push(svg("line", { class: "tick-line", x1: x, x2: x, y1: y1 - 7, y2: y1 + 7 }));
    }
    return svg("g", {
      class: `mark ${mark.kind} t-${mark.type.replace(/\./g, "-")}`, "data-i": mark.events[0], "data-n": n,
      on: { click: () => this.onSelect(mark.events) },
    }, svg("title", { text: n > 1 ? `${n} events, first: ${event.label}` : event.label }), ...shapes);
  }

  // What changes with the playhead: which marks are drawn, where the line is, which lanes are alive.
  paint() {
    const { run } = this;
    const x = this.x(this.u);
    this.playhead.setAttribute("x1", x);
    this.playhead.setAttribute("x2", x);
    for (const mark of this.marks) {
      mark.node.classList.toggle("drawn", mark.events[0] <= this.current);
      mark.node.classList.toggle("current", mark.events.includes(this.current));
    }
    const t = tOf(run, this.u);
    const speaking = this.current >= 0 ? run.events[this.current].from : null;
    for (const head of this.heads.querySelectorAll(".head")) {
      const lane = run.lanes.find((l) => l.id === head.dataset.lane);
      head.classList.toggle("active", lane.id === speaking || (lane.kind === "agent" && lane.start <= t && t <= lane.end));
    }
  }

  // u: drawn time of the playhead; follow: keep it in view (while playing or stepping); current: the event the
  // reader is on, when several share that instant (default: the last one that happened).
  setPlayhead(u, follow, current) {
    this.u = Math.min(this.run.time.width, Math.max(0, u));
    this.current = current ?? cursorAt(this.run, this.u) - 1;
    if (follow) {
      const x = this.x(this.u) - this.scroll.scrollLeft;
      if (x < 40 || x > this.scroll.clientWidth - 40) this.scroll.scrollLeft = this.x(this.u) - this.scroll.clientWidth * 0.3;
    }
    this.paint();
  }
}
