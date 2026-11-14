#!/usr/bin/env python3
"""The run journal's only writer (Python 3 standard library, like the guard).

Usage: journal.py event TYPE [JSON] [--run ID] [--session ID] [--actor ACTOR]
  Appends one event to the journal of every run open for the session (CLAUDE_CODE_SESSION_ID unless --session), or
  of the run ID alone. JSON (argument, else stdin) holds the type's own fields (an array: one event per element);
  `v`, `t`, `run`, `session`, `actor`, `parent` are filled here. An event is written as it ends: `t`, its start, is
  now minus its `dur`. A `text` field is replaced by `excerpt` + `hash` + `chars`.
Usage: journal.py hook
  The command of the Claude Code hooks `bin/kit install` adds: records what the hook's payload (stdin) says.
Usage: journal.py prune
  Removes the journals older than RETENTION_DAYS, then the oldest while they weigh more than MAX_MB together.
Usage: journal.py validate [--schema FILE] FILE.jsonl…
  Checks every line against schema.json, the check each event passes before it is written.

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
JOURNAL_FILES = ("events.jsonl",)   # what a run folder holds for its journal
RETENTION_DAYS = 30  # `prune` (run-begin calls it) removes older journals…
MAX_MB = 2048        # …then the oldest ones while all journals weigh more than this
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


def started(dur_ms=0):
    """`t` of an event written as it ends: now, minus how long it lasted."""
    at = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(milliseconds=dur_ms)
    return at.isoformat(timespec="milliseconds").replace("+00:00", "Z")


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


def load_schema(path=SCHEMA):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


JSON_TYPES = {"string": str, "integer": int, "number": (int, float), "boolean": bool, "object": dict, "array": list,
              "null": type(None)}


def is_type(value, name):
    if isinstance(value, bool) and name in ("integer", "number"):
        return False
    return isinstance(value, JSON_TYPES[name])


def problems(value, schema, where="event"):
    """What is wrong with value against a JSON Schema, as a list of strings (empty: valid). Only the keywords
    schema.json uses are implemented; any other raises rather than being half-checked."""
    out = []
    for keyword, want in schema.items():
        if keyword in ("$schema", "title", "description", "then"):
            continue
        if keyword == "type":
            names = want if isinstance(want, list) else [want]
            if not any(is_type(value, n) for n in names):
                out.append(f"{where}: expected {' or '.join(names)}")
        elif keyword == "const":
            if value != want:
                out.append(f"{where}: expected {want!r}")
        elif keyword == "enum":
            if value not in want:
                out.append(f"{where}: {value!r} is not one of {want}")
        elif keyword == "pattern":
            if isinstance(value, str) and not re.search(want, value):
                out.append(f"{where}: {value!r} does not match {want}")
        elif keyword == "minimum":
            if is_type(value, "number") and value < want:
                out.append(f"{where}: {value} is below {want}")
        elif keyword == "required":
            if isinstance(value, dict):
                out += [f"{where}: missing '{k}'" for k in want if k not in value]
        elif keyword == "properties":
            if isinstance(value, dict):
                for k, sub in want.items():
                    if k in value:
                        out += problems(value[k], sub, f"{where}.{k}")
        elif keyword == "additionalProperties":
            if want is False and isinstance(value, dict):
                out += [f"{where}: unknown field '{k}'" for k in value if k not in schema.get("properties", {})]
        elif keyword == "items":
            if isinstance(value, list):
                for i, item in enumerate(value):
                    out += problems(item, want, f"{where}[{i}]")
        elif keyword == "allOf":
            for sub in want:
                out += problems(value, sub, where)
        elif keyword == "if":
            if not problems(value, want, where):
                out += problems(value, schema.get("then", {}), where)
        else:
            raise NotImplementedError(f"schema keyword '{keyword}' is not supported")
    return out


def append(folder, event):
    """One line, one write, on a file opened for append: concurrent writers (hooks, scripts) never interleave."""
    root = os.path.realpath(runs_root())
    real = os.path.realpath(folder)
    if os.path.dirname(real) != root or os.path.basename(real) == "active":
        raise ValueError(f"{folder} is not a run folder of {root}")
    os.makedirs(real, mode=0o700, exist_ok=True)
    line = json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n"
    fd = os.open(os.path.join(real, JOURNAL_FILES[0]), os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        os.write(fd, line.encode())
    finally:
        os.close(fd)


def record(kind, fields, session, run=None, actor="session"):
    """Writes the event to each open run's journal: only an event schema.json accepts is written. Returns how many
    journals got it."""
    if not isinstance(fields, dict):
        raise ValueError("the event's fields must be a JSON object")
    fields = dict(fields)
    if "text" in fields:
        fields.update(text_fields(fields.pop("text")))
    dur = fields.get("dur")
    at = started(dur if isinstance(dur, int) and not isinstance(dur, bool) and dur > 0 else 0)
    schema, written = None, 0
    for run_id, folder in open_runs(session, run):
        event = {"v": 1, "t": at, "run": run_id, "session": session, "actor": actor,
                 "parent": "session" if actor.startswith("agent:") else None, "type": kind}
        event.update({k: v for k, v in redact(fields).items() if k not in ("v", "run", "session", "type")})
        schema = schema or load_schema()
        wrong = problems(event, schema)
        if wrong:
            raise ValueError(f"invalid {kind} event, not recorded: {'; '.join(wrong[:5])}")
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
    fields = json.loads(raw or "{}")
    for one in fields if isinstance(fields, list) else [fields]:  # an array: one event per element, in one call
        try:
            record(positional[0], one, options["--session"], options["--run"], options["--actor"])
        except ValueError as e:  # one refused event does not lose the others
            warn(str(e))


def tool_summary(tool, tool_input):
    """One line saying what a tool call was about, never the content it carried (a file's text, an edit's strings)."""
    if not isinstance(tool_input, dict):
        return ""
    if tool in ("Agent", "Task"):
        return f"{tool_input.get('subagent_type') or ''}: {tool_input.get('description') or ''}"
    for key in ("command", "file_path", "notebook_path", "pattern", "url", "query", "skill"):
        if isinstance(tool_input.get(key), str):
            return tool_input[key]
    return json.dumps({k: v for k, v in tool_input.items() if isinstance(v, (str, int, float, bool))},
                      ensure_ascii=False)


def hook_events(payload):
    """What a Claude Code hook received (its stdin), as [(type, fields, actor)]. The payload's fields are those of the
    hooks reference, checked on Claude Code 2.1.325: in a subagent, `session_id` is the main session's and `agent_id`
    names the subagent. An event this does not map gives nothing."""
    name, agent = payload.get("hook_event_name"), payload.get("agent_id")
    actor = f"agent:{agent}" if agent else "session"
    about = {"id": str(agent), "type": str(payload.get("agent_type") or "")} if agent else None
    dur = payload.get("duration_ms")
    dur = int(dur) if isinstance(dur, (int, float)) and not isinstance(dur, bool) else None
    said = payload.get("last_assistant_message")
    if name == "SessionStart":
        return [("session", {"kind": "start", "source": payload.get("source"), "model": payload.get("model"),
                             "transcript": payload.get("transcript_path")}, "session")]
    if name == "SessionEnd":
        return [("session", {"kind": "end", "source": payload.get("reason")}, "session")]
    if name == "PostCompact":
        return [("session", {"kind": "compact", "source": payload.get("trigger")}, "session")]
    if name == "UserPromptSubmit":
        prompt = str(payload.get("prompt") or "")
        if prompt.lstrip().startswith("<task-notification"):  # the harness reporting a background agent, not the owner
            return []
        return [("message", {"from": "you", "to": "session", "kind": "prompt", "text": prompt}, "you")]
    if name == "Stop":
        return [("message", {"from": "session", "to": "you", "kind": "reply", "text": said}, "session")]
    if name == "SubagentStart" and agent:
        return [("agent.spawn", {"agent": about, "tool": "claude"}, "session")]
    if name == "SubagentStop" and agent:
        return [("agent.return", {"agent": about, "transcript": payload.get("agent_transcript_path"), "text": said},
                 actor)]
    if name in ("PostToolUse", "PostToolUseFailure"):
        tool, given, got = str(payload.get("tool_name") or ""), payload.get("tool_input"), payload.get("tool_response")
        given, got = given if isinstance(given, dict) else {}, got if isinstance(got, dict) else {}
        if tool == "AskUserQuestion":
            asked = [q.get("question") for q in given.get("questions") or [] if isinstance(q, dict)]
            answers = got.get("answers") if isinstance(got.get("answers"), dict) else {}
            return [("checkpoint", {"question": " / ".join(str(q) for q in asked if q), "by": "you", "dur": dur,
                                    "answer": " / ".join(str(a) for a in answers.values()) or None}, actor)]
        fields = {"tool": tool, "input": tool_summary(tool, given), "dur": dur}
        if name == "PostToolUseFailure":
            fields.update(error=True, text=payload.get("error"))
        elif tool == "Bash":
            fields["text"] = "\n".join(str(got[k]) for k in ("stdout", "stderr") if got.get(k)) or None
        elif tool in ("Agent", "Task") and got.get("agentId"):
            # the call that spawned a subagent: what links the instance to its prompt and its model
            fields.update(agent={"id": str(got["agentId"]), "type": str(given.get("subagent_type") or "")},
                          model=got.get("resolvedModel"), text=given.get("prompt"))
        return [("tool.call", fields, actor)]
    return []


def cmd_hook(_argv):
    """journal.py hook — the command of the hooks `bin/kit install` adds to Claude Code: reads the hook's payload on
    stdin and records what it says, when a run is open for that session."""
    payload = json.load(sys.stdin)
    session = str(payload.get("session_id") or "")
    for kind, fields, actor in hook_events(payload):
        record(kind, {k: v for k, v in fields.items() if v is not None}, session, actor=actor)


def cmd_validate(argv):
    """journal.py validate [--schema FILE] FILE.jsonl… — prints `file:line: problem` for each line schema.json
    refuses. Exit 1 if there is one, 2 if the schema uses a keyword this checker does not implement."""
    schema = load_schema(*argv[1:2]) if argv[:1] == ["--schema"] else load_schema()
    argv = argv[2:] if argv[:1] == ["--schema"] else argv
    bad = 0
    for path in argv:
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                try:
                    wrong = problems(json.loads(line), schema)
                except ValueError as e:
                    wrong = [f"not JSON ({e})"]
                except NotImplementedError as e:
                    print(e, file=sys.stderr)
                    return 2
                bad += len(wrong)
                for w in wrong:
                    print(f"{path}:{n}: {w}")
    return 1 if bad else 0


def journal_files():
    """[(mtime, size, path)] of every journal file of every run that is not open, oldest first."""
    root = runs_root()
    open_folders = set()
    for path in glob.glob(os.path.join(root, "active", "*.json")):
        try:
            with open(path, encoding="utf-8") as f:
                open_folders.add(os.path.realpath(json.load(f).get("journal") or ""))
        except (OSError, ValueError, AttributeError):
            pass
    found = []
    for name in JOURNAL_FILES:
        for path in glob.glob(os.path.join(root, "*", name)):
            if os.path.realpath(os.path.dirname(path)) in open_folders or os.path.islink(path):
                continue
            st = os.stat(path)
            found.append((st.st_mtime, st.st_size, path))
    return sorted(found)


def cmd_prune(_argv):
    """Removes the journal files older than RETENTION_DAYS, then the oldest ones while they weigh more than MAX_MB
    together. Only journal files: a run folder also holds deliverables the journal does not own (an emptied folder
    is removed)."""
    files = journal_files()
    limit = time.time() - RETENTION_DAYS * 86400
    total = sum(size for _mtime, size, _path in files)
    for mtime, size, path in files:
        if mtime >= limit and total <= MAX_MB * 1024 * 1024:
            break
        os.remove(path)
        total -= size
        try:
            os.rmdir(os.path.dirname(path))
        except OSError:
            pass  # not empty: the run's other files stay


COMMANDS = {"event": cmd_event, "hook": cmd_hook, "prune": cmd_prune}


def main(argv):
    if argv[:1] == ["validate"]:  # a check, not a recording: the one command whose exit code says something
        return cmd_validate(argv[1:])
    try:
        if not argv or argv[0] not in COMMANDS:
            raise ValueError(f"usage: journal.py {'|'.join(COMMANDS)} …")
        COMMANDS[argv[0]](argv[1:])
    except Exception as e:  # recording never breaks a run
        warn(f"{type(e).__name__}: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
