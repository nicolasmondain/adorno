#!/usr/bin/env python3
"""The run journal's only writer (Python 3 standard library, like the guard).

Usage: journal.py event TYPE [JSON] [--run ID] [--session ID] [--actor ACTOR]
  Appends one event to the journal of every run open for the session (CLAUDE_CODE_SESSION_ID unless --session), or
  of the run ID alone. JSON (argument, else stdin) holds the type's own fields; `v`, `t`, `run`, `session`, `actor`,
  `parent` are filled here. A `text` field is replaced by `excerpt` + `hash` + `chars`.

Journals are private: ~/.adorno/runs/<slug>-<run id>/events.jsonl, mode 600, never in a repo. Every string is
redacted before it is written. Recording never breaks a run: whatever fails, the reason goes to stderr and the exit
code is 0.
"""
import datetime
import glob
import hashlib
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
SCHEMA = os.path.join(os.path.dirname(HERE), "schema.json")
EXCERPT = 500        # characters of a prompt, a result or a message kept in the journal
MAX_STRING = 2000    # any other string is cut there (`reasoning`, opted into by the owner, is kept whole)
# A value is a secret when its key, variable or flag name says so: the names `bin/kit` refuses in `claude_env`
# (SECRET_ENV_RE), which tests keep equal to this one.
SECRET_NAME = r"(KEY|TOKEN|SECRET|PASSWORD)"
SECRET_NAME_RE = re.compile(SECRET_NAME, re.I)
SECRET_FLAG_RE = re.compile(r"^--?[\w-]*" + SECRET_NAME + r"[\w-]*$", re.I)
# (kind, pattern, replacement) applied in order to every string. Best effort: a secret none of them recognises is
# written as it is, which is why journals stay on this machine.
REDACTIONS = [(kind, re.compile(pattern, flags), repl) for kind, pattern, flags, repl in (
    ("private-key", r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?(-----END [A-Z ]*PRIVATE KEY-----|\Z)", re.S, "[redacted:{}]"),
    ("authorization", r"(authorization[\"']?\s*[:=]\s*[\"']?)(?:[a-z]+\s+)?[^\s\"',;]+", re.I, r"\1[redacted:{}]"),
    ("bearer", r"\b(bearer\s+)[A-Za-z0-9._~+/=-]{8,}", re.I, r"\1[redacted:{}]"),
    ("credentials", r"\b([a-z][a-z0-9+.-]*://)[^/\s:@]+:[^/\s@]+@", re.I, r"\1[redacted:{}]@"),
    ("github", r"\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})", 0, "[redacted:{}]"),
    ("api-key", r"\bsk-[A-Za-z0-9_-]{16,}", 0, "[redacted:{}]"),
    ("aws", r"\b(AKIA|ASIA)[0-9A-Z]{16}\b", 0, "[redacted:{}]"),
    ("slack", r"\bxox[abeoprs]-[A-Za-z0-9-]{10,}", 0, "[redacted:{}]"),
    ("jwt", r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}", 0, "[redacted:{}]"),
    # NAME=value, "name": "value", --name=value
    ("secret", r"([\w.-]*" + SECRET_NAME + r"[\w.-]*[\"']?\s*[=:]\s*[\"']?)[^\s\"',;&]+", re.I, r"\1[redacted:{}]"),
    # --name value
    ("secret", r"(--?[\w-]*" + SECRET_NAME + r"[\w-]*\s+)[^\s-]\S*", re.I, r"\1[redacted:{}]"),
)]


def warn(message):
    print(f"adorno journal: {message}", file=sys.stderr)


def redact_string(text):
    for kind, pattern, repl in REDACTIONS:
        text = pattern.sub(repl.format(kind), text)
    return text


def redact(value, key=""):
    """value with every secret replaced, strings cut to their limit. A string under a key named like a secret, or
    after a flag named like one in a list of arguments, goes whole; numbers and booleans never do (`tokens` holds
    counts)."""
    if isinstance(value, str):
        if SECRET_NAME_RE.search(key):
            return "[redacted:secret]"
        text = redact_string(value)
        return text if key == "reasoning" or len(text) <= MAX_STRING else text[:MAX_STRING] + "…"
    if isinstance(value, dict):
        return {k: redact(v, str(k)) for k, v in value.items()}
    if isinstance(value, list):
        return [redact(v, "secret" if i and isinstance(value[i - 1], str) and SECRET_FLAG_RE.match(value[i - 1])
                       else key) for i, v in enumerate(value)]
    return value


def text_fields(text):
    """A long text (prompt, result, message) as the journal keeps it: an excerpt, and the hash and length of the whole
    so the full text can be matched in the transcript."""
    text = str(text)
    cut = text[:EXCERPT] + ("…" if len(text) > EXCERPT else "")
    return {"excerpt": cut, "hash": hashlib.sha256(text.encode()).hexdigest(), "chars": len(text)}


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def runs_root():
    return os.path.join(os.path.expanduser("~"), ".adorno", "runs")


def open_runs(session, run=None):
    """[(run id, journal folder)] of the runs open for this session (run-begin wrote them; expired ones are over), or
    of the one run asked for. A run without a journal folder was opened by an older run-begin: not recorded."""
    found = []
    for path in sorted(glob.glob(os.path.join(runs_root(), "active", "*.json"))):
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError):
            continue  # run-begin may be writing it
        if not isinstance(data, dict) or not isinstance(data.get("journal"), str):
            continue
        if run is not None and data.get("id") != run:
            continue
        if run is None and (str(data.get("session") or "") != session or data.get("expires", 0) <= time.time()):
            continue
        found.append((str(data.get("id")), data["journal"]))
    return found


def event_types():
    with open(SCHEMA, encoding="utf-8") as f:
        return json.load(f)["properties"]["type"]["enum"]


def append(folder, event):
    """One line, one write, on a file opened for append: concurrent writers (hooks, scripts) never interleave."""
    root = os.path.realpath(runs_root())
    real = os.path.realpath(folder)
    if os.path.dirname(real) != root or os.path.basename(real) == "active":
        raise ValueError(f"{folder} is not a run folder of {root}")
    os.makedirs(real, mode=0o700, exist_ok=True)
    line = json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n"
    fd = os.open(os.path.join(real, "events.jsonl"), os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        os.write(fd, line.encode())
    finally:
        os.close(fd)


def record(kind, fields, session, run=None, actor="session"):
    """Writes the event to each open run's journal. Returns how many journals got it."""
    if kind not in event_types():
        raise ValueError(f"unknown event type '{kind}' (schema.json lists them)")
    if not isinstance(fields, dict):
        raise ValueError("the event's fields must be a JSON object")
    fields = dict(fields)
    if "text" in fields:
        fields.update(text_fields(fields.pop("text")))
    written = 0
    for run_id, folder in open_runs(session, run):
        event = {"v": 1, "t": now_iso(), "run": run_id, "session": session, "actor": actor,
                 "parent": "session" if actor.startswith("agent:") else None, "type": kind}
        event.update({k: v for k, v in redact(fields).items() if k not in ("v", "run", "session", "type")})
        try:
            append(folder, event)
            written += 1
        except (OSError, ValueError) as e:
            warn(f"{kind} not recorded for run {run_id}: {e}")
    return written


def cmd_event(argv):
    options = {"--run": None, "--session": os.environ.get("CLAUDE_CODE_SESSION_ID", ""), "--actor": "session"}
    positional = []
    while argv:
        arg = argv.pop(0)
        if arg in options:
            options[arg] = argv.pop(0)
        else:
            positional.append(arg)
    if not positional or len(positional) > 2:
        raise ValueError("usage: journal.py event TYPE [JSON] [--run ID] [--session ID] [--actor ACTOR]")
    raw = positional[1] if len(positional) == 2 else sys.stdin.read()
    record(positional[0], json.loads(raw or "{}"), options["--session"], options["--run"], options["--actor"])


COMMANDS = {"event": cmd_event}


def main(argv):
    try:
        if not argv or argv[0] not in COMMANDS:
            raise ValueError(f"usage: journal.py {'|'.join(COMMANDS)} …")
        COMMANDS[argv[0]](argv[1:])
    except Exception as e:  # recording never breaks a run
        warn(f"{type(e).__name__}: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
