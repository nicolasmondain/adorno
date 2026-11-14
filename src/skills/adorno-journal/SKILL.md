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

- `t` is when the event **started** (UTC, milliseconds); `dur` is how long it lasted, in ms, when that is known. An
  event is written as it ends: the writer sets `t` to now minus `dur`.
- `actor` is who acts: `you` (the owner), `session` (the main session) or `agent:<instance id>`; `parent` is `session`
  for an agent, `null` otherwise.
- A long text (prompt, result, message) is kept as `excerpt` (500 characters), `hash` (SHA-256 of the whole) and
  `chars`; the whole text stays in the tool's transcript.

| `type` | When | Own fields (required first) |
| --- | --- | --- |
| `run.begin` / `run.end` | the run opens / closes | `workflow`, `mode`, `level`, `repos`, `dir` / `workflow`, `outcome` (`done`, `draft`, `stopped`, `failed`, or `ended` when the workflow passed none) |
| `step.begin` / `step.end` | a step of the run's plan starts / ends | `index`, `name` |
| `agent.spawn` / `agent.return` | a subagent starts / returns | `agent` (`id`, `type`), `model`, `tool`, text, `transcript` |
| `model.turn` | one model response | `model`, `tokens` (`in`, `out`, `cache_read`, `cache_write`), `thinking_tokens`, `thinking_ms`, `stop`, `reasoning` |
| `tool.call` | one tool call | `tool`, `input`, `exit`, `error`, text of the result |
| `script.call` | one adorno script | `script`, `exit`, `args`, `level`, `action`, `dry_run` |
| `guard` | the guard refused or asked | `decision` (`deny`, `ask`), `reason`, `command` |
| `message` | a prompt, a reply, a text a model wrote, the merged verdict of a review | `from`, `to`, `kind` (`prompt`, `reply`, `text`, `verdict`), text, `transcript` or `ref` |
| `checkpoint` | the owner decides | `question`, `answer`, `by` |
| `finding` | a review finding | `severity`, `title`, `stage` (`produced`, `merged`), `reviewer`, `file`, `line` |
| `loop` | a fix and review round starts | `round`, `cap`, `reason` |
| `github` | a write to GitHub | `action`, `target`, `url` |
| `session` | the session starts, ends or compacts | `kind` (`start`, `end`, `compact`), `source`, `model`, `transcript` |

## Who records what

| Recorded by | Events |
| --- | --- |
| `adorno-github/scripts/run-begin`, `run-end` | `run.begin`, `run.end` (`run-end ID [OUTCOME]`) |
| every other `adorno-github` script, as it exits | its own `script.call` (exit code, the level and action it asked `require_level` for, dry run) |
| the write scripts, after a write that reached GitHub | `github` |
| `review-merge` | `finding`, as produced by each reviewer then as merged; a `message` of kind `verdict`, from `scripts` to `session` |
| the guard (`guard_bash.py`) | `guard`, for a refusal or a question; what it lets through is not an event |
| `adorno-github/scripts/run-mark`, called by the session that runs a plan | `step.begin`, `step.end`, `loop` |
| the Claude Code hooks `bin/kit install` adds (`journal.py hook`) | `session`, `message` (the owner's prompt, the session's reply), `tool.call`, `checkpoint` (a question to the owner), `agent.spawn`, `agent.return` |

`ADORNO_JOURNAL=0` in a script's environment records nothing for it.

Not recorded in this version: an agent's `tier` (no producer knows it: the hooks give the model it resolved to), a
`consult` between agents, and a handoff through a file. An agent's written files are not a field either: the viewer's
server derives them from the agent's own `Write`, `Edit` and `NotebookEdit` calls.

The hooks are Claude Code's only (Codex and Gemini sessions record their scripts, not their turns). They do nothing
outside a run, never block (`PostToolUse` is not even waited for) and always exit 0. A tool call is recorded by what
it was about (a command, a path, a pattern), never by the content it carried: an edit is its file, not its code. A
project installed next to a global install leaves the recording to the global one.

## What the transcripts add

Hooks do not carry the model of a turn nor its tokens. `run-end` starts, without waiting for it,
`journal.py enrich <run id>`: it reads the Claude Code transcripts of the run's session and subagents (their paths are
in the hooks' events, never guessed), keeps what happened between `run.begin` and `run.end`, and writes
`enriched.jsonl` next to `events.jsonl`:

- one `model.turn` per model response: model, tokens (the usage of a response counted once, whatever its number of
  blocks), thinking tokens and time, stop reason; `t` is when the request was sent;
- one `message` per text a model wrote, with `ref` (`file`, `id`) pointing at the transcript line that holds the
  whole; a text a hook already recorded is not written twice.

`events.jsonl` is never rewritten; `enriched.jsonl` is rewritten whole each time, so the reading can be run again
(`journal.py enrich <run id>`, or `bin/kit journal enrich <run id>` from the adorno repo), as long as Claude Code has
not pruned its transcripts. What goes wrong is said in `enrich.log`. A reader takes both files together, sorted on
`t`. The transcript format is Claude Code's own (read on 2.1.325), not a contract: what is not recognised is skipped.

## Settings

`journal` in the owner's `local/adorno.yaml` (installed by `bin/kit install`):

| Setting | Default | Does |
| --- | --- | --- |
| `reasoning` | `false` | `true`: `model.turn` also holds the model's reasoning, when the transcript has it in clear |
| `retention_days` | `30` | journals older than this are removed when a run opens |
| `max_mb` | `2048` | then the oldest ones, while all journals weigh more than this |

## Writing an event

The writer is called by adorno's scripts and hooks, not by an agent through its shell: the guard does not let
`adorno-journal/scripts/*` through as an adorno script. An agent marks a run with `run-mark`. The command line is what
the scripts use (`--session` and `--actor` serve the hooks and the tests):

```sh
adorno-journal/scripts/journal.py event TYPE 'JSON of the own fields' [--run ID] [--session ID] [--actor ACTOR]
```

The event goes to the journal of every run open for the session (`CLAUDE_CODE_SESSION_ID` unless `--session`), or to
the run `ID` alone. A JSON array writes one event per element. A `text` field is replaced by `excerpt` + `hash` +
`chars`. An event `schema.json` refuses is not written, and the reason is said on stderr.

`journal.py validate FILE.jsonl…` runs the same check on whole files (exit 1 on an invalid line).

## Retention

`run-begin` prunes as it opens a run: journals older than `retention_days` go, then the oldest ones while all
journals weigh more than `max_mb`. A run's journal files go together, and only they (`events.jsonl`, `enriched.jsonl`,
`enrich.log`), never a run's deliverables nor the journal of an open run; a linked run folder is never followed. To
delete one by hand: remove those files.

## Redaction

Every string is redacted before it is written, and before it is cut to its excerpt (a secret across the cut is
recognised whole; the hash and length are those of the raw text): GitHub and GitLab tokens, `sk-…`, `sk_live_…` and
`rk_live_…` keys, AWS and Slack keys, JWTs, private key blocks, `Authorization` headers, `Bearer …`, credentials in a
URL or after `-u` / `--user` (`user:pass`), and any value whose key, variable or flag name contains `key`, `token`,
`secret` or `password` (a quoted value goes whole, spaces included); each becomes `[redacted:<kind>]`. For a tool the
writer does not know (an MCP tool), a call keeps only numbers, booleans and identifier-like strings; any other value is
written as `…`. It is best effort: a secret that matches none of these is written as it is, one more reason a journal
never leaves the machine.
