---
name: adorno-journal
description: The journal of a workflow run — one structured event per line (who did what, with which model, tool calls, scripts, guard decisions, findings, rounds, checkpoints, GitHub writes), written while the run happens into the owner's private folder, secrets redacted. Use when a script or a workflow must record an event of the run it is part of, or to read what a run did.
---

# adorno-journal

A run opened by `adorno-github/scripts/run-begin` has a journal: `~/.adorno/runs/<slug>-<run id>/events.jsonl`, one
JSON object per line, append-only. `schema.json` (next to this file) is the format; `scripts/journal.py` is the only
writer.

**Journals are private.** They hold commands, prompts and names: they stay under `~/.adorno/runs/` (mode 600), are
never written in a repo, never committed, never sent anywhere.

**Recording never breaks a run.** No run open, a folder that cannot be written, an event that is refused: the reason
goes to stderr, the exit code is 0, and the run goes on.

## An event

```json
{"v": 1, "t": "2026-01-01T10:14:07.000Z", "run": "20260101T100000-1000-1", "session": "…", "actor": "agent:a1b2",
 "parent": "session", "type": "guard", "decision": "deny", "reason": "…", "command": "…"}
```

- `t` is when the event **started** (UTC, milliseconds); `dur` is how long it lasted, in ms, when that is known.
- `actor` is who acts: `you` (the owner), `session` (the main session) or `agent:<instance id>`; `parent` is `session`
  for an agent, `null` otherwise.
- A long text (prompt, result, message) is kept as `excerpt` (500 characters), `hash` (SHA-256 of the whole) and
  `chars`; the whole text stays in the tool's transcript.

| `type` | When | Own fields (required first) |
| --- | --- | --- |
| `run.begin` / `run.end` | the run opens / closes | `workflow`, `mode`, `level`, `repos`, `dir` / `workflow`, `outcome` |
| `step.begin` / `step.end` | a step of the run's plan starts / ends | `index`, `name` |
| `agent.spawn` / `agent.return` | a subagent starts / returns | `agent` (`id`, `type`), `tier`, `model`, `tool`, text, `file`, `transcript` |
| `model.turn` | one model response | `model`, `tokens` (`in`, `out`, `cache_read`, `cache_write`), `thinking_tokens`, `thinking_ms`, `stop`, `reasoning` |
| `tool.call` | one tool call | `tool`, `input`, `exit`, `error`, text of the result |
| `script.call` | one adorno script | `script`, `exit`, `args`, `level`, `action`, `dry_run` |
| `guard` | the guard refused or asked | `decision` (`deny`, `ask`), `reason`, `command` |
| `message` | a prompt, a reply, a consult, a handoff | `from`, `to`, `kind`, text, `file` |
| `checkpoint` | the owner decides | `question`, `answer`, `by` |
| `finding` | a review finding | `severity`, `title`, `stage` (`produced`, `merged`), `reviewer`, `file`, `line` |
| `loop` | a fix and review round starts | `round`, `cap`, `reason` |
| `github` | a write to GitHub | `action`, `target`, `url` |
| `session` | the session starts, ends or compacts | `kind` (`start`, `end`, `compact`), `source`, `model`, `transcript` |

## Writing an event

```sh
adorno-journal/scripts/journal.py event TYPE 'JSON of the own fields' [--run ID] [--session ID] [--actor ACTOR]
```

The event goes to the journal of every run open for the session (`CLAUDE_CODE_SESSION_ID` unless `--session`), or to
the run `ID` alone. A `text` field is replaced by `excerpt` + `hash` + `chars`. An unknown `type` is refused.

## Redaction

Every string is redacted before it is written: GitHub tokens, `sk-…` keys, AWS and Slack keys, JWTs, private key
blocks, `Authorization` headers, `Bearer …`, credentials in a URL, and any value whose key, variable or flag name
contains `key`, `token`, `secret` or `password`; each becomes `[redacted:<kind>]`. It is best effort: a secret that
matches none of these is written as it is, one more reason a journal never leaves the machine.
