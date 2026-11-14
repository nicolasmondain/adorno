#!/usr/bin/env python3
"""The run journal's only writer (Python 3 standard library, like the guard).

Usage: journal.py event TYPE [JSON] [--run ID] [--session ID] [--actor ACTOR]
  Appends one event to the journal of every run open for the session (CLAUDE_CODE_SESSION_ID unless --session), or
  of the run ID alone. JSON (argument, else stdin) holds the type's own fields (an array: one event per element);
  `v`, `t`, `run`, `session`, `actor`, `parent` are filled here. An event is written as it ends: `t`, its start, is
  now minus its `dur`. A `text` field is replaced by `excerpt` + `hash` + `chars`.
Usage: journal.py hook
  The command of the Claude Code hooks `bin/kit install` adds: records what the hook's payload (stdin) says.
Usage: journal.py enrich RUN
  Reads the Claude Code transcripts of the run's session and subagents (their paths come from the hooks' events) and
  writes what the hooks do not carry into enriched.jsonl, next to events.jsonl: one `model.turn` per model response
  (model, tokens, thinking), and the texts the models wrote. Rewritten whole each time: run it again at will.
Usage: journal.py prune
  Removes the journals older than `retention_days`, then the oldest while they weigh more than `max_mb` together.
Usage: journal.py validate [--schema FILE] FILE.jsonl…
  Checks every line against schema.json, the check each event passes before it is written.

Journals are private: ~/.adorno/runs/<slug>-<run id>/events.jsonl, mode 600, never in a repo. Every string is
redacted before it is written. The owner's settings: `journal` in local/adorno.yaml (DEFAULTS below). Recording never
breaks a run: whatever fails, the reason goes to stderr and the exit
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
JOURNAL_FILES = ("events.jsonl", "enriched.jsonl", "enrich.log")   # what a run folder holds for its journal
# The owner's settings (`journal` in local/adorno.yaml, which `bin/kit install` puts in the registry) and their
# defaults: models' reasoning is copied only when asked for; `prune` (run-begin calls it) removes journals older than
# retention_days, then the oldest ones while all journals weigh more than max_mb.
DEFAULTS = {"reasoning": False, "retention_days": 30, "max_mb": 2048}
# A value is a secret when its key, variable or flag name says so: the names `bin/kit` refuses in `claude_env`
# (SECRET_ENV_RE), which tests keep equal to this one.
SECRET_NAME = r"(KEY|TOKEN|SECRET|PASSWORD)"
SECRET_NAME_RE = re.compile(SECRET_NAME, re.I)
SECRET_FLAG_RE = re.compile(r"^--?[\w-]*" + SECRET_NAME + r"[\w-]*$", re.I)
# A value after a secret's name: quoted, it ends at the quote that opened it (in double quotes, an escaped quote is
# part of it, as in JSON); unquoted, at the pattern given to format().
OPENING_QUOTE = r"(?:(?P<dq>\")|(?P<sq>'))?"
QUOTED_VALUE = r"(?(dq)(?:[^\"\\\n]|\\.)+|(?(sq)[^'\n]+|{}))"
# (kind, pattern, replacement) applied in order to every string. Best effort: a secret none of them recognises is
# written as it is, which is why journals stay on this machine. A name pattern starts only at the start of a token
# (the lookbehinds): unanchored, a long run of word characters or dashes made it quadratic.
REDACTIONS = [(kind, re.compile(pattern, flags), repl) for kind, pattern, flags, repl in (
    ("private-key", r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?(-----END [A-Z ]*PRIVATE KEY-----|\Z)", re.S, "[redacted:{}]"),
    ("authorization", r"(authorization[\"']?\s*[:=]\s*[\"']?)(?:[a-z]+\s+)?[^\s\"',;]+", re.I, r"\1[redacted:{}]"),
    ("bearer", r"\b(bearer\s+)[A-Za-z0-9._~+/=-]{8,}", re.I, r"\1[redacted:{}]"),
    ("credentials", r"\b([a-z][a-z0-9+.-]*://)[^/\s:@]+:[^/\s@]+@", re.I, r"\1[redacted:{}]@"),
    # curl -u user:password, -uuser:password, --user=user:password
    ("credentials", r"((?<![\w-])(?:-u\s*|--user(?:\s+|=))[\"']?)[^\s:\"']+:[^\s\"']+", 0, r"\1[redacted:{}]"),
    ("github", r"\b(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})", 0, "[redacted:{}]"),
    ("gitlab", r"\bglpat-[A-Za-z0-9_-]{20,}", 0, "[redacted:{}]"),
    ("api-key", r"\bsk-[A-Za-z0-9_-]{16,}", 0, "[redacted:{}]"),
    ("api-key", r"\b[sr]k_(?:live|test)_[A-Za-z0-9]{16,}", 0, "[redacted:{}]"),
    ("aws", r"\b(AKIA|ASIA)[0-9A-Z]{16}\b", 0, "[redacted:{}]"),
    ("slack", r"\bxox[abeoprs]-[A-Za-z0-9-]{10,}", 0, "[redacted:{}]"),
    ("jwt", r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}", 0, "[redacted:{}]"),
    # NAME=value, "name": "value", --name=value; a quoted value goes whole, spaces included
    ("secret", r"((?<![\w.-])[\w.-]*" + SECRET_NAME + r"[\w.-]*[\"']?\s*[=:]\s*" + OPENING_QUOTE + ")"
     + QUOTED_VALUE.format(r"[^\s\"',;&]+"), re.I, r"\1[redacted:{}]"),
    # --name value, --name "a value"
    ("secret", r"((?<![\w-])--?[\w-]*" + SECRET_NAME + r"[\w-]*\s+" + OPENING_QUOTE + ")"
     + QUOTED_VALUE.format(r"[^\s-]\S*"), re.I, r"\1[redacted:{}]"),
)]
WINDOW = 1024   # characters redacted past a cut, so that a secret across it is recognised whole before it is cut
IDENTIFIER = re.compile(r"^[\w.:/@#+-]{1,80}$")   # an id, a name, a path: one short token, no spaces, no content


def warn(message):
    print(f"adorno journal: {message}", file=sys.stderr)


def redact_string(text):
    for kind, pattern, repl in REDACTIONS:
        text = pattern.sub(repl.format(kind), text)
    return text


def redacted_head(text, keep):
    """The first `keep` characters of text once redacted (with "…" when cut), redacted before they are cut: the raw
    window doubles until WINDOW redacted characters follow the cut or the whole text is in, since each redaction
    shortens it and a secret across a fixed raw window's end would be cut first, then written in part. The patterns
    are linear, so the doubling costs at most twice redacting the whole text."""
    n = keep + WINDOW
    red = redact_string(text[:n])
    while n < len(text) and len(red) < keep + WINDOW:
        n *= 2
        red = redact_string(text[:n])
    return red if len(text) <= keep and len(red) <= keep else red[:keep] + "…"


def redact(value, key=""):
    """value with every secret replaced, strings cut to their limit. A string under a key named like a secret, or
    after a flag named like one in a list of arguments, goes whole; numbers and booleans never do (`tokens` holds
    counts). A long string is redacted, then cut (redacted_head): never cut first."""
    if isinstance(value, str):
        if SECRET_NAME_RE.search(key):
            return "[redacted:secret]"
        if key == "reasoning" or len(value) <= MAX_STRING:
            return redact_string(value)
        return redacted_head(value, MAX_STRING)
    if isinstance(value, dict):
        return {k: redact(v, str(k)) for k, v in value.items()}
    if isinstance(value, list):
        return [redact(v, "secret" if i and isinstance(value[i - 1], str) and SECRET_FLAG_RE.match(value[i - 1])
                       else key) for i, v in enumerate(value)]
    return value


def text_fields(text):
    """A long text (prompt, result, message) as the journal keeps it: an excerpt, and the hash and length of the whole
    so the full text can be matched in the transcript. The excerpt is redacted before it is cut (redacted_head: a
    secret across the cut is recognised whole); the hash and the length are those of the raw text, as the transcript
    holds it."""
    text = str(text)
    return {"excerpt": redacted_head(text, EXCERPT), "hash": hashlib.sha256(text.encode()).hexdigest(), "chars": len(text)}


def started(dur_ms=0):
    """`t` of an event written as it ends: now, minus how long it lasted."""
    at = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(milliseconds=dur_ms)
    return at.isoformat(timespec="milliseconds").replace("+00:00", "Z")


def runs_root():
    return os.path.join(os.path.expanduser("~"), ".adorno", "runs")


def settings():
    conf = dict(DEFAULTS)
    try:
        with open(os.path.join(os.path.dirname(runs_root()), "registry.json"), encoding="utf-8") as f:
            own = json.load(f).get("journal")
        conf.update({k: own[k] for k in DEFAULTS if k in own})
    except (OSError, ValueError, AttributeError, TypeError):
        pass  # no registry, or no `journal` in it: the defaults
    return conf


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
    """One line, one write, on a file opened for append: concurrent writers (hooks, scripts) never interleave. A
    write cut short (a full disk) is taken back, so no half line is left for the next one to be glued to."""
    root = os.path.realpath(runs_root())
    real = os.path.realpath(folder)
    if os.path.dirname(real) != root or os.path.basename(real) == "active":
        raise ValueError(f"{folder} is not a run folder of {root}")
    os.makedirs(real, mode=0o700, exist_ok=True)
    line = (json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
    fd = os.open(os.path.join(real, JOURNAL_FILES[0]), os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        written = os.write(fd, line)
        if written != len(line):
            os.ftruncate(fd, os.lseek(fd, 0, os.SEEK_CUR) - written)   # the offset is the end of what was written
            raise OSError(f"short write ({written} of {len(line)} bytes), taken back")
    finally:
        os.close(fd)


def event_for(kind, fields, run_id, session, actor, schema):
    """The event as it is written: common fields filled (`t`: now minus `dur`, unless given), a `text` turned into
    excerpt + hash + chars, every string redacted. Raises unless schema.json accepts it."""
    if not isinstance(fields, dict):
        raise ValueError("the event's fields must be a JSON object")
    fields = dict(fields)
    if "text" in fields:
        fields.update(text_fields(fields.pop("text")))
    dur = fields.get("dur")
    event = {"v": 1, "t": started(dur if isinstance(dur, int) and not isinstance(dur, bool) and dur > 0 else 0),
             "run": run_id, "session": session, "actor": actor,
             "parent": "session" if actor.startswith("agent:") else None, "type": kind}
    event.update({k: v for k, v in redact(fields).items() if k not in ("v", "run", "session", "type")})
    wrong = problems(event, schema)
    if wrong:
        raise ValueError(f"invalid {kind} event, not recorded: {'; '.join(wrong[:5])}")
    return event


def record(kind, fields, session, run=None, actor="session"):
    """Writes the event to each open run's journal. Returns how many journals got it."""
    schema, written = None, 0
    for run_id, folder in open_runs(session, run):
        schema = schema or load_schema()
        event = event_for(kind, fields, run_id, session, actor, schema)
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
    # a tool this does not know (an MCP tool: a Slack message, a Notion page): its numbers, booleans and
    # identifier-like strings; any other value is named, never written
    return json.dumps({k: v if isinstance(v, (int, float, bool)) or (isinstance(v, str) and IDENTIFIER.match(v))
                       else "…" for k, v in tool_input.items()}, ensure_ascii=False)


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
        return [("message", {"from": "you", "to": "session", "kind": "prompt", "text": prompt,
                             "transcript": payload.get("transcript_path")}, "you")]
    if name == "Stop":
        return [("message", {"from": "session", "to": "you", "kind": "reply", "text": said,
                             "transcript": payload.get("transcript_path")}, "session")]
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


def read_events(path):
    """The events of a journal file, skipping lines that do not parse (a line being written, a damaged file)."""
    events = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                if isinstance(event, dict):
                    events.append(event)
    except OSError:
        pass
    return events


def millis(start, end):
    """Milliseconds between two timestamps (ISO, UTC, with milliseconds), never negative; 0 when one does not read."""
    fmt = "%Y-%m-%dT%H:%M:%S.%fZ"
    try:
        delta = datetime.datetime.strptime(end, fmt) - datetime.datetime.strptime(start, fmt)
    except ValueError:
        return 0
    return max(0, delta // datetime.timedelta(milliseconds=1))


def turn_fields(turn, reasoning):
    usage = turn["usage"] if isinstance(turn["usage"], dict) else {}
    details = usage.get("output_tokens_details") if isinstance(usage.get("output_tokens_details"), dict) else {}
    counts = {ours: usage[theirs] if isinstance(usage.get(theirs), int) else 0 for ours, theirs in (
        ("in", "input_tokens"), ("out", "output_tokens"), ("cache_read", "cache_read_input_tokens"),
        ("cache_write", "cache_creation_input_tokens"))}
    fields = {"t": turn["start"], "dur": millis(turn["start"], turn["end"]), "model": str(turn["model"] or "unknown"),
              "tokens": counts, "thinking_ms": turn["thinking_ms"]}
    if isinstance(details.get("thinking_tokens"), int):
        fields["thinking_tokens"] = details["thinking_tokens"]
    if isinstance(turn["stop"], str):
        fields["stop"] = turn["stop"]
    if reasoning and turn["reasoning"]:
        fields["reasoning"] = "\n\n".join(turn["reasoning"])
    return fields


def transcript_events(path, actor, since, until, reasoning):
    """[(type, fields)] read from one Claude Code transcript, between two instants: a `model.turn` per model response,
    and a `message` per text the model wrote. The format is Claude Code's own (read on 2.1.325), not a contract: what
    is not recognised is skipped. One response is several lines, one per content block, each repeating the same
    usage: they are grouped on `requestId` and the usage is counted once. A turn starts when its request is sent
    (the `api-request` line before it)."""
    found, turn, asked_at = [], None, None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if '"assistant"' not in line and '"api-request"' not in line:
                continue  # most of a transcript is prompts and tool results: not parsed
            try:
                row = json.loads(line)
            except ValueError:
                continue
            at = row.get("timestamp") if isinstance(row, dict) else None
            if not isinstance(at, str) or not since <= at <= until:
                continue
            if row.get("type") == "api-request":
                asked_at = at
                continue
            message = row.get("message")
            if row.get("type") != "assistant" or not isinstance(message, dict):
                continue
            request = row.get("requestId") or message.get("id")
            if turn is None or turn["id"] != request:
                if turn:
                    found.append(("model.turn", turn_fields(turn, reasoning)))
                turn = {"id": request, "start": asked_at if asked_at and asked_at <= at else at, "thinking_ms": 0,
                        "reasoning": []}
                asked_at = None
            turn.update(end=at, model=message.get("model"), usage=message.get("usage"), stop=message.get("stop_reason"))
            if isinstance(row.get("thinkingDurationMs"), int):
                turn["thinking_ms"] += row["thinkingDurationMs"]
            for block in message.get("content") or []:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "thinking" and isinstance(block.get("thinking"), str) and block["thinking"]:
                    turn["reasoning"].append(block["thinking"])
                elif block.get("type") == "text" and isinstance(block.get("text"), str) and block["text"].strip():
                    ref = {"file": path, **({"id": row["uuid"]} if isinstance(row.get("uuid"), str) else {})}
                    found.append(("message", {"t": at, "from": actor, "to": "you" if actor == "session" else "session",
                                              "kind": "text", "text": block["text"], "ref": ref}))
    if turn:
        found.append(("model.turn", turn_fields(turn, reasoning)))
    return found


def run_transcripts(events):
    """{transcript path: actor} of a run, as its hooks' events say (never guessed): the session's on its `session`
    and `message` events, each subagent's on its `agent.return`. A subagent still running when the run ended has no
    return: its file is next to the session's, in `<session>/subagents/`."""
    main = next((e["transcript"] for e in events if e.get("type") in ("session", "message")
                 and isinstance(e.get("transcript"), str)), None)
    sources = {}
    for e in events:
        if e.get("type") == "agent.return" and isinstance(e.get("transcript"), str) and isinstance(e.get("agent"), dict):
            sources[e["transcript"]] = f"agent:{e['agent'].get('id')}"
            main = main or os.path.dirname(os.path.dirname(e["transcript"])) + ".jsonl"
    if main:
        for path in glob.glob(os.path.join(main[:-len(".jsonl")], "subagents", "agent-*.jsonl")):
            sources.setdefault(path, "agent:" + os.path.basename(path)[len("agent-"):-len(".jsonl")])
        sources[main] = "session"
    return sources


def cmd_enrich(argv):
    if len(argv) != 1:
        raise ValueError("usage: journal.py enrich RUN (a run id, or the name of its folder)")
    folders = [d for d in glob.glob(os.path.join(runs_root(), "*"))
               if (os.path.basename(d) == argv[0] or os.path.basename(d).endswith("-" + argv[0]))
               and os.path.isfile(os.path.join(d, JOURNAL_FILES[0])) and not os.path.islink(d)]
    if len(folders) != 1:
        raise ValueError(f"no journal for run '{argv[0]}' under {runs_root()}")
    events = read_events(os.path.join(folders[0], JOURNAL_FILES[0]))
    begin = next((e for e in events if e.get("type") == "run.begin"), None)
    if not begin:
        raise ValueError(f"{folders[0]}: no run.begin in the journal")
    since = str(begin.get("t"))
    until = next((str(e.get("t")) for e in events if e.get("type") == "run.end"), started())
    known = {e.get("hash") for e in events if e.get("hash")}  # texts the hooks already recorded (a reply, a return)
    schema, reasoning, out, read = load_schema(), settings()["reasoning"] is True, [], 0
    for path, actor in sorted(run_transcripts(events).items()):
        if not os.path.isfile(path):
            warn(f"transcript not found (pruned by Claude Code?): {path}")
            continue
        read += 1
        for kind, fields in transcript_events(path, actor, since, until, reasoning):
            if kind == "message" and hashlib.sha256(fields["text"].encode()).hexdigest() in known:
                continue
            try:
                out.append(event_for(kind, fields, str(begin.get("run")), str(begin.get("session") or ""), actor, schema))
            except ValueError as e:
                warn(str(e))
    out.sort(key=lambda e: e["t"])
    target = os.path.join(folders[0], JOURNAL_FILES[1])
    tmp = f"{target}.{os.getpid()}.tmp"   # two passes at once (run-end's, a manual one) never share it
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        for event in out:
            f.write(json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n")
    os.replace(tmp, target)
    print(json.dumps({"run": begin.get("run"), "transcripts": read, "file": target,
                      "model_turns": sum(e["type"] == "model.turn" for e in out),
                      "messages": sum(e["type"] == "message" for e in out)}))


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


def run_journals():
    """[(age, size, folder, [journal files])] of every run that is not open, oldest first: a run's age is its newest
    journal file, its size their sum. Only real folders directly under the runs folder: a link is never followed."""
    root = os.path.realpath(runs_root())
    open_folders = set()
    for path in glob.glob(os.path.join(root, "active", "*.json")):
        try:
            with open(path, encoding="utf-8") as f:
                open_folders.add(os.path.realpath(json.load(f).get("journal") or ""))
        except (OSError, ValueError, AttributeError):
            pass
    found = []
    for folder in glob.glob(os.path.join(root, "*")):
        if (os.path.islink(folder) or not os.path.isdir(folder) or os.path.basename(folder) == "active"
                or os.path.dirname(os.path.realpath(folder)) != root or os.path.realpath(folder) in open_folders):
            continue
        files = [p for p in (os.path.join(folder, n) for n in JOURNAL_FILES) if os.path.isfile(p) and not os.path.islink(p)]
        if files:
            stats = [os.stat(p) for p in files]
            found.append((max(s.st_mtime for s in stats), sum(s.st_size for s in stats), folder, files))
    return sorted(found)


def cmd_prune(_argv):
    """Removes the journals of the runs older than `retention_days`, then of the oldest runs while all journals weigh
    more than `max_mb`. A run's journal files go together, and only them: a run folder also holds deliverables the
    journal does not own (an emptied folder is removed)."""
    conf, runs = settings(), run_journals()
    limit = time.time() - conf["retention_days"] * 86400
    total = sum(size for _age, size, _folder, _files in runs)
    for age, size, folder, files in runs:
        if age >= limit and total <= conf["max_mb"] * 1024 * 1024:
            break
        for path in files:
            os.remove(path)
        total -= size
        try:
            os.rmdir(folder)
        except OSError:
            pass  # not empty: the run's other files stay


COMMANDS = {"event": cmd_event, "hook": cmd_hook, "enrich": cmd_enrich, "prune": cmd_prune}


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
