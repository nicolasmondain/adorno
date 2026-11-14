"""kit serve — the local, read-only server of the run journals and of their viewer (standard library only).

Journals are private: the server listens on 127.0.0.1 only, answers GET and HEAD only, checks the Host header (a
page of another site cannot reach it through DNS rebinding), sends no CORS header, never writes anything and never
serves a file outside a run's own folders. It does every computation a reader could get silently wrong (order,
lanes, totals, the compression of idle time); the viewer only draws.

  GET /api/runs                  every journal under the runs folder, newest first
  GET /api/runs/<id>             one run, normalized: lanes, events with from/to and a label, rounds, steps, totals
  GET /api/runs/<id>/file?path=  a text file of the run's folder, or of its `dir` when that is an .agent-run folder
  GET /…                         the viewer's own files
"""
import json
import os
import re
import sys
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlsplit

JOURNAL_FILES = ("events.jsonl", "enriched.jsonl")   # what the hooks and scripts wrote, what the transcripts added
RUN_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
GAP_MS = 5000          # a silence longer than this is drawn this wide
FILE_TYPES = (".md", ".json", ".jsonl", ".yaml", ".yml", ".txt", ".diff", ".patch", ".log")
FILE_MAX = 2 * 1024 * 1024
FILES_LISTED, FILES_DEPTH = 200, 3
CONTENT_TYPES = {".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
                 ".js": "text/javascript; charset=utf-8", ".woff2": "font/woff2", ".txt": "text/plain; charset=utf-8",
                 ".svg": "image/svg+xml"}
CSP = "default-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
TOKEN_KEYS = ("in", "out", "cache_read", "cache_write")
COMMON = ("v", "t", "run", "session", "actor", "parent", "type", "dur")
TIME = "%Y-%m-%dT%H:%M:%S.%fZ"


# ── reading ───────────────────────────────────────────────────────────────────────────────────────────────────────

def scan(runs):
    """{id: folder} of the runs that have a journal: a real folder of `runs` (not `active`, the grants; not a link)
    holding a regular events.jsonl. The folder's name is the id: a request names a run, never a path."""
    found = {}
    try:
        names = sorted(os.listdir(runs))
    except OSError:
        return found
    for name in names:
        folder = os.path.join(runs, name)
        journal = os.path.join(folder, JOURNAL_FILES[0])
        if (RUN_NAME.match(name) and name != "active" and not os.path.islink(folder) and os.path.isdir(folder)
                and os.path.isfile(journal) and not os.path.islink(journal)):
            found[name] = folder
    return found


def stamp(folder):
    """What changes when a journal does: size and time of its files (append-only, or rewritten whole)."""
    out = []
    for name in JOURNAL_FILES:
        try:
            st = os.stat(os.path.join(folder, name))
            out.append((st.st_size, st.st_mtime_ns))
        except OSError:
            out.append(None)
    return tuple(out)


def read_journal(folder):
    """(events sorted on `t`, number of lines that could not be read) of a run: both files together."""
    events, bad = [], 0
    for name in JOURNAL_FILES:
        path = os.path.join(folder, name)
        if not os.path.isfile(path) or os.path.islink(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    event = json.loads(line)
                    datetime.strptime(event["t"], TIME)
                    if not isinstance(event.get("type"), str):
                        raise ValueError("no type")
                except (ValueError, KeyError, TypeError):
                    bad += 1
                    continue
                events.append(event)
    events.sort(key=lambda e: e["t"])   # stable: lines of the same instant keep their order
    return events, bad


def ms_between(start, end):
    return (datetime.strptime(end, TIME) - datetime.strptime(start, TIME)) // timedelta(milliseconds=1)


def tokens_of(event):
    got = event.get("tokens") if event.get("type") == "model.turn" else None
    if not isinstance(got, dict):
        return None
    return {k: got[k] if isinstance(got.get(k), int) else 0 for k in TOKEN_KEYS}


def add_tokens(total, more):
    for k in TOKEN_KEYS:
        total[k] = total.get(k, 0) + more[k]
    return total


def duration_of(event):
    return event["dur"] if isinstance(event.get("dur"), int) and event["dur"] > 0 else 0


def agent_id(event):
    """The lane an event's `agent` names (`agent:<id>`), or None."""
    about = event.get("agent")
    return f"agent:{about['id']}" if isinstance(about, dict) and isinstance(about.get("id"), str) else None


def head(events):
    """What the run says about itself: its run.begin and run.end, and its bounds."""
    begin = next((e for e in events if e["type"] == "run.begin"), {})
    end = next((e for e in events if e["type"] == "run.end"), None)
    first = events[0]["t"] if events else None
    last = max((ms_between(first, e["t"]) + duration_of(e) for e in events), default=0)
    return begin, end, first, last


def summarize(name, folder):
    events, bad = read_journal(folder)
    begin, end, first, last = head(events)
    tokens = {k: 0 for k in TOKEN_KEYS}
    for e in events:
        got = tokens_of(e)
        if got:
            add_tokens(tokens, got)
    agents = {a for e in events for a in (agent_id(e), e.get("actor")) if isinstance(a, str) and a.startswith("agent:")}
    size = sum(s[0] for s in stamp(folder) if s)
    return {"id": name, "run": begin.get("run") or (events[0].get("run") if events else None),
            "workflow": begin.get("workflow"), "mode": begin.get("mode"), "level": begin.get("level"),
            "repos": begin.get("repos") or [], "start": first, "end": end["t"] if end else None, "duration_ms": last,
            "outcome": (end.get("outcome") or "ended") if end else "open", "agents": len(agents), "events": len(events),
            "bad_lines": bad, "tokens": tokens, "size": size}


# ── one run, normalized ───────────────────────────────────────────────────────────────────────────────────────────

def short(agent_type):
    return re.sub(r"^adorno-agent-", "", agent_type or "") or "agent"


def lanes_of(events, t0, last):
    """The lanes, top to bottom: you, the main session, each agent instance in spawn order, scripts, the guard,
    GitHub. An agent seen without its spawn (hooks missed it, the run opened late) still gets a lane, marked orphan;
    one that never returned (still running, or its return missed) lives until the end of what was recorded."""
    agents, models = {}, {}
    for e in events:
        at = ms_between(t0, e["t"])
        actor = e.get("actor")
        if e["type"] == "model.turn" and isinstance(e.get("model"), str):
            models.setdefault(actor, {}).setdefault(e["model"], 0)
            models[actor][e["model"]] += 1
        for lane in {a for a in (agent_id(e), actor) if isinstance(a, str) and a.startswith("agent:")}:
            a = agents.setdefault(lane, {"id": lane, "kind": "agent", "instance": lane[len("agent:"):], "parent": "session",
                                         "agent": None, "model": None, "tier": None, "start": at, "end": None,
                                         "orphan": True})
            about = e.get("agent") if lane == agent_id(e) else None
            if about and about.get("type") and not a["agent"]:
                a["agent"] = about["type"]
            if e["type"] == "agent.spawn" and about:
                a["orphan"], a["start"] = False, at
            if e["type"] == "agent.return" and about:
                a["end"] = at
            if about:  # the Agent tool call names the model the instance runs on
                a["model"] = a["model"] or e.get("model")
                a["tier"] = a["tier"] or e.get("tier")

    def usual(actor):
        seen = models.get(actor) or {}
        return max(seen, key=seen.get) if seen else None

    out = [{"id": "you", "kind": "you", "label": "You"},
           {"id": "session", "kind": "session", "label": "main session", "model": usual("session")}]
    for a in sorted(agents.values(), key=lambda a: (a["start"], a["id"])):
        a["end"] = a["end"] if a["end"] is not None else last
        a["model"] = a["model"] or usual(a["id"])
        a["label"] = short(a["agent"])
        out.append(a)
    return out + [{"id": "scripts", "kind": "scripts", "label": "scripts"}, {"id": "guard", "kind": "guard", "label": "guard"},
                  {"id": "github", "kind": "github", "label": "GitHub"}]


def label_of(e, names):
    """One sentence a person can read: the text log's line, and what a screen reader says for the mark."""
    kind, who = e["type"], names.get(e.get("actor"), str(e.get("actor")))
    if kind == "run.begin":
        return f"run begins: {e.get('workflow')} ({e.get('mode')}, {e.get('level')})"
    if kind == "run.end":
        return f"run ends: {e.get('outcome')}"
    if kind == "agent.spawn":
        return f"{who} starts {names.get(agent_id(e), 'an agent')}"
    if kind == "agent.return":
        return f"{who} returns" + (f", wrote {e['file']}" if e.get("file") else "")
    if kind == "model.turn":
        got = tokens_of(e) or {}
        return f"{who}: {e.get('model')} responds ({got.get('in', 0)} in, {got.get('out', 0)} out)"
    if kind == "tool.call":
        return f"{who}: {e.get('tool')} {e.get('input') or ''}".rstrip() + (" (failed)" if e.get("error") else "")
    if kind == "script.call":
        return f"{who} runs {e.get('script')} (exit {e.get('exit')})"
    if kind == "guard":
        return f"guard {e.get('decision')}: {e.get('command')}"
    if kind == "message":
        return f"{names.get(e.get('from'), e.get('from'))} to {names.get(e.get('to'), e.get('to'))}: {e.get('kind')}"
    if kind == "checkpoint":
        return f"question to you: {e.get('question')}"
    if kind == "finding":
        return f"{e.get('severity')} finding ({e.get('stage')}): {e.get('title')}"
    if kind == "github":
        return f"GitHub {e.get('action')}: {e.get('target')}"
    if kind == "session":
        return f"session {e.get('kind')}"
    return kind


def ends_of(e, lanes):
    """(from, to) of an event: an arrow between two lanes, or a mark on one lane (to: None)."""
    kind, actor = e["type"], e.get("actor") if e.get("actor") in lanes else "session"
    if kind == "agent.spawn" and agent_id(e) in lanes:
        return actor, agent_id(e)
    if kind == "agent.return":
        return actor, "session"
    if kind in ("script.call", "guard", "github"):
        return actor, {"script.call": "scripts"}.get(kind, kind)
    if kind == "checkpoint":
        return actor, "you"
    if kind == "message" and e.get("from") in lanes and e.get("to") in lanes:
        return e["from"], e["to"]
    return actor, None


def time_map(spans, width):
    """The compression of idle time: [{t0, t1, u0, u1, gap}], a piecewise-linear, increasing map from real time to
    drawn time. Activity keeps its length; a silence longer than GAP_MS is drawn GAP_MS wide."""
    merged = []
    for start, end in sorted(spans):
        if merged and start <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    segments, t, u = [], 0, 0
    for start, end in merged + [[width, width]]:
        if start > t:
            drawn = min(start - t, GAP_MS)
            segments.append({"t0": t, "t1": start, "u0": u, "u1": u + drawn, "gap": start - t > GAP_MS})
            u += drawn
        if end > start:
            segments.append({"t0": start, "t1": end, "u0": u, "u1": u + end - start, "gap": False})
            u += end - start
        t = max(t, end)
    return segments or [{"t0": 0, "t1": 0, "u0": 0, "u1": 0, "gap": False}]


def drawn(segments, t):
    for s in segments:
        if s["t0"] <= t <= s["t1"]:
            return s["u0"] if s["t1"] == s["t0"] else s["u0"] + (t - s["t0"]) * (s["u1"] - s["u0"]) // (s["t1"] - s["t0"])
    return segments[-1]["u1"]


def steps_of(events, lanes, t0, last):
    """The steps of the run's plan, when the session marked them (source: journal). Otherwise phases derived from
    the delegations (source: derived): agents the session started whose lifetimes overlap are one phase."""
    marked = {}
    for e in events:
        if e["type"] in ("step.begin", "step.end") and isinstance(e.get("index"), int):
            step = marked.setdefault(e["index"], {"index": e["index"], "name": e.get("name"), "start": None, "end": None,
                                                  "source": "journal"})
            step["start" if e["type"] == "step.begin" else "end"] = ms_between(t0, e["t"])
    if marked:
        steps = sorted(marked.values(), key=lambda s: s["index"])
        for s in steps:
            s["start"] = s["start"] if s["start"] is not None else 0
            s["end"] = s["end"] if s["end"] is not None else last
        return steps
    groups = []
    for a in [l for l in lanes if l["kind"] == "agent"]:
        if groups and a["start"] <= groups[-1]["end"]:
            groups[-1]["end"] = max(groups[-1]["end"], a["end"])
            groups[-1]["labels"].append(a["label"])
        else:
            groups.append({"start": a["start"], "end": a["end"], "labels": [a["label"]]})
    steps = []
    for i, g in enumerate(groups, 1):
        kinds = sorted(set(g["labels"]))
        name = kinds[0] if len(kinds) == 1 else ", ".join(kinds)
        steps.append({"index": i, "name": name + (f" ×{len(g['labels'])}" if len(g["labels"]) > 1 and len(kinds) == 1 else ""),
                      "start": g["start"], "end": g["end"], "source": "derived"})
    return steps


def rounds_of(events, lanes, steps, t0, last):
    """A fix and review round: from its mark to the next one, the end of the step it is in, or the end of the run;
    with the agents started inside."""
    marks = [e for e in events if e["type"] == "loop" and isinstance(e.get("round"), int)]
    rounds = []
    for i, e in enumerate(marks):
        start = ms_between(t0, e["t"])
        end = ms_between(t0, marks[i + 1]["t"]) if i + 1 < len(marks) else next(
            (s["end"] for s in steps if s["source"] == "journal" and s["start"] <= start <= s["end"]), last)
        rounds.append({"round": e["round"], "cap": e.get("cap"), "reason": e.get("reason"), "start": start, "end": end,
                       "lanes": [l["id"] for l in lanes if l["kind"] == "agent" and start <= l["start"] < end]})
    return rounds


def listed_files(roots):
    """The text files a run's folders hold, as the paths the file endpoint takes (bounded in depth and number)."""
    out = []
    for root in roots:
        base = os.path.realpath(root)
        for folder, dirs, files in os.walk(base):
            depth = os.path.relpath(folder, base).count(os.sep) + (0 if folder == base else 1)
            dirs[:] = sorted(d for d in dirs if not d.startswith(".")) if depth < FILES_DEPTH - 1 else []
            for name in sorted(files):
                path = os.path.join(folder, name)
                rel = os.path.relpath(path, base)
                if (name not in JOURNAL_FILES and name.lower().endswith(FILE_TYPES) and os.path.isfile(path)
                        and os.path.getsize(path) <= FILE_MAX and not any(f["path"] == rel for f in out)
                        and resolve_file(roots, rel)):
                    out.append({"path": rel, "size": os.path.getsize(path)})
                if len(out) >= FILES_LISTED:
                    return out
    return out


def normalize(name, folder):
    events, bad = read_journal(folder)
    begin, end, t0, last = head(events)
    if not events:
        return {"id": name, "run": None, "bad_lines": bad, "open": True, "outcome": "open", "t0": None, "duration_ms": 0,
                "lanes": [], "events": [], "steps": [], "rounds": [], "files": [],
                "time": {"gap_ms": GAP_MS, "width": 0, "segments": time_map([], 0)},
                "totals": {"tokens": {k: 0 for k in TOKEN_KEYS}, "by_lane": {}, "by_model": {}, "counts": {}}}
    lanes = lanes_of(events, t0, last)
    ids = {l["id"] for l in lanes}
    names = {l["id"]: l["label"] for l in lanes}
    steps = steps_of(events, lanes, t0, last)
    rounds = rounds_of(events, lanes, steps, t0, last)
    # what counts as activity: every event while it lasts, an agent while it lives; waiting for the owner does not
    spans = [(ms_between(t0, e["t"]), ms_between(t0, e["t"]) + (0 if e["type"] == "checkpoint" else duration_of(e)))
             for e in events]
    spans += [(l["start"], l["end"]) for l in lanes if l["kind"] == "agent"]
    segments = time_map(spans, last)
    totals = {"tokens": {k: 0 for k in TOKEN_KEYS}, "by_lane": {}, "by_model": {}, "counts": {}}
    out = []
    for e in events:
        totals["counts"][e["type"]] = totals["counts"].get(e["type"], 0) + 1
        if e["type"] in ("step.begin", "step.end", "loop"):
            continue  # not marks of their own: they are the steps and the rounds
        at, dur = ms_between(t0, e["t"]), duration_of(e)
        source, target = ends_of(e, ids)
        got = tokens_of(e)
        if got:
            add_tokens(totals["tokens"], got)
            add_tokens(totals["by_lane"].setdefault(source, {}), got)
            add_tokens(totals["by_model"].setdefault(str(e.get("model")), {}), got)
        detail = {k: v for k, v in e.items() if k not in COMMON}
        out.append({"t": at, "dur": dur, "type": e["type"], "from": source, "to": target, "label": label_of(e, names),
                    "tokens": got, "d": detail})
        if e["type"] == "checkpoint" and e.get("answer") is not None:
            out.append({"t": at + dur, "dur": 0, "type": "answer", "from": "you", "to": source,
                        "label": f"you answer: {e['answer']}", "tokens": None, "d": {"answer": e["answer"], "by": e.get("by")}})
    out.sort(key=lambda e: e["t"])
    for i, e in enumerate(out):
        e["i"], e["u"] = i, drawn(segments, e["t"])
    roots = file_roots(folder, begin.get("dir"))
    return {"id": name, "run": begin.get("run") or events[0].get("run"), "workflow": begin.get("workflow"),
            "mode": begin.get("mode"), "level": begin.get("level"), "repos": begin.get("repos") or [],
            "outcome": (end.get("outcome") or "ended") if end else "open", "open": end is None, "bad_lines": bad,
            "t0": t0, "duration_ms": last, "lanes": lanes, "events": out, "steps": steps, "rounds": rounds,
            "time": {"gap_ms": GAP_MS, "width": segments[-1]["u1"], "segments": segments}, "totals": totals,
            "files": listed_files(roots)}


# ── files ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def file_roots(folder, run_dir):
    """Where a run's files may be read: its journal folder, and the folder run.begin recorded as `dir` only when that
    is an `.agent-run/<x>` folder (agents' deliverables by convention, never a checkout nor a home)."""
    roots = [os.path.realpath(folder)]
    if isinstance(run_dir, str) and os.path.isabs(run_dir):
        real = os.path.realpath(run_dir)
        if os.path.isdir(real) and os.path.basename(os.path.dirname(real)) == ".agent-run" and real not in roots:
            roots.append(real)
    return roots


def resolve_file(roots, rel):
    """The real path of a file a request may read, or None: relative, without `..`, of a text type, and still inside
    one of the roots once every link is resolved."""
    if not rel or "\0" in rel or os.path.isabs(rel) or ".." in rel.replace("\\", "/").split("/"):
        return None
    if not rel.lower().endswith(FILE_TYPES):
        return None
    for root in roots:
        real = os.path.realpath(os.path.join(root, rel))
        if os.path.commonpath([root, real]) == root and real != root and os.path.isfile(real):
            return real
    return None


# ── http ──────────────────────────────────────────────────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    server_version = "adorno-journal"
    runs = ""       # set by serve()
    static = {}     # {"/path": file}
    hosts = ()
    cache = {}      # {folder: (stamp, summary)}: a journal is read again only when it changed

    def log_message(self, *_args):
        pass

    def reply(self, status, body, content_type="application/json; charset=utf-8"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", CSP)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def refuse(self, status, why):
        self.reply(status, {"error": why})   # never echoes what was asked

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        if self.headers.get("Host") not in self.hosts:
            return self.refuse(403, "this server only answers on its own address")
        url = urlsplit(self.path)
        path = unquote(url.path)
        try:
            if path == "/api/runs":
                return self.reply(200, {"runs": self.summaries()})
            if path.startswith("/api/runs/"):
                name, _, rest = path[len("/api/runs/"):].partition("/")
                folder = scan(self.runs).get(name)
                if not folder:
                    return self.refuse(404, "no such run")
                if rest == "":
                    return self.reply(200, normalize(name, folder))
                if rest == "file":
                    return self.file(folder, (parse_qs(url.query).get("path") or [""])[0])
                return self.refuse(404, "not found")
            if path in self.static:
                with open(self.static[path], "rb") as f:
                    kind = CONTENT_TYPES.get(os.path.splitext(self.static[path])[1], "application/octet-stream")
                    return self.reply(200, f.read(), kind)
            return self.refuse(404, "not found")
        except OSError:
            return self.refuse(500, "could not read")

    def summaries(self):
        out = []
        for name, folder in scan(self.runs).items():
            now = stamp(folder)
            if self.cache.get(folder, (None,))[0] != now:
                self.cache[folder] = (now, summarize(name, folder))
            out.append(self.cache[folder][1])
        return sorted(out, key=lambda r: r["start"] or "", reverse=True)

    def file(self, folder, rel):
        events, _bad = read_journal(folder)
        real = resolve_file(file_roots(folder, head(events)[0].get("dir")), rel)
        if not real:
            return self.refuse(404, "no such file")
        if os.path.getsize(real) > FILE_MAX:
            return self.refuse(413, "file too large")
        with open(real, "rb") as f:   # as text, whatever it holds: a file an agent wrote is never a page of this origin
            kind = "application/json; charset=utf-8" if real.lower().endswith(".json") else "text/plain; charset=utf-8"
            return self.reply(200, f.read(), kind)

    def do_POST(self):
        self.refuse(405, "read-only")

    do_PUT = do_DELETE = do_PATCH = do_OPTIONS = do_POST


def static_files(viewer):
    """{"/path": file} of the viewer's files, read once: a request is a lookup in this table, never a path joined to a
    folder."""
    table = {}
    for folder, _dirs, files in os.walk(viewer):
        for name in files:
            path = os.path.join(folder, name)
            if not name.startswith(".") and os.path.isfile(path) and not os.path.islink(path):
                table["/" + os.path.relpath(path, viewer).replace(os.sep, "/")] = path
    if "/index.html" in table:
        table["/"] = table["/index.html"]
    return table


def serve(port, runs, viewer):
    if port == 8000:
        print("kit serve: port 8000 is taken by convention on this machine: pass another --port", file=sys.stderr)
        return 2
    try:
        server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    except OSError as e:
        print(f"kit serve: cannot listen on 127.0.0.1:{port} ({e.strerror}): pass another --port", file=sys.stderr)
        return 1
    bound = server.server_address[1]
    Handler.runs, Handler.static = os.path.realpath(runs), static_files(viewer)
    Handler.hosts = (f"127.0.0.1:{bound}", f"localhost:{bound}")
    print(f"http://127.0.0.1:{bound}/", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0
