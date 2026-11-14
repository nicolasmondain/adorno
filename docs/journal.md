# The run journal and its viewer

A workflow run involves the main session, agents in parallel, scripts, the guard, GitHub and several models.
`status.md` says how a run ended; the journal says how it went: every exchange, in order, with who sent what to whom.
A local viewer replays it. Why it is built this way: [decisions](decisions/journal.md). The format and who writes
what: the [`adorno-journal` skill](../src/skills/adorno-journal/SKILL.md).

## What is recorded

A run opened by `run-begin` gets a journal, one event per line:

| Recorded | By |
| --- | --- |
| the run opening and closing, with how it ended (`done`, `draft`, `stopped`, `failed`) | `run-begin`, `run-end` |
| each adorno script: its name, arguments, exit code, the level and action it asked for, a dry run | the script itself, as it exits |
| each write that reached GitHub | the write scripts |
| each review finding, as produced then as merged, and the merged verdict | `review-merge` |
| each refusal or question of the guard | the guard hook |
| the steps of a run plan and the fix rounds | the session, with `run-mark` |
| your prompts and the session's replies, each tool call, each question asked to you, each subagent starting and returning | Claude Code hooks, installed by `bin/kit install` |
| each model response: model, tokens, thinking time; the texts the models wrote | a reading of Claude Code's transcripts, started by `run-end` |

Codex and Gemini sessions record what the scripts and the guard do; their turns and tool calls are not recorded.

The writer, `journal.py`, is called by adorno's scripts and hooks: it is not a command for agents, and the guard does
not let it through. An agent marks a run with `run-mark`.

A tool call is recorded by what it was about (a command, a path, a pattern), never by the content it carried: an edit
is its file, not its code. A prompt, a result or a message is kept as its first 500 characters, the hash of the whole
and where the whole is (the transcript). The models' reasoning is **not** copied, unless you ask for it (below).

Recording never breaks nor blocks a run: without `python3`, without an open run, or when a journal cannot be written,
the script or the session goes on, and the reason is said on stderr (or in the journal's `enrich.log`).

## Where, and who can read it

`~/.adorno/runs/<workflow>-<run id>/`: `events.jsonl` (what scripts and hooks wrote, append-only), `enriched.jsonl`
(what the transcripts added, rewritten whole at each reading), `enrich.log`. Always there, even when the run's own
folder is a `.agent-run/` in a workspace: a journal is never written in a repo, never committed, never sent anywhere.
The files are readable by you only.

## What is redacted

Every string goes through the redaction before it is written, and before it is cut to its excerpt, so a secret
across the cut is recognised whole: GitHub and GitLab tokens, `sk-…` and `sk_live_…` keys, AWS and Slack keys, JWTs,
private key blocks, `Authorization` headers, `Bearer …`, credentials in a URL or after `-u` / `--user`, and any value
whose key, variable or flag is named like a secret (`key`, `token`, `secret`, `password`), a quoted value with its
spaces. Each becomes `[redacted:<kind>]`. For a tool the writer does not know (an MCP tool), a call keeps only numbers,
booleans and short identifier-like strings; any other value is written as `…`.

It is best effort: a secret that looks like none of these is written as it is. A journal also holds commands, paths,
excerpts of prompts and names. Treat it as private; it has no export.

## Settings

In your `local/adorno.yaml` (then `bin/kit install`):

```yaml
journal:
  reasoning: false      # true: also copy the models' reasoning, when the tool's transcripts hold it in clear
  retention_days: 30    # journals older than this are removed when a run opens…
  max_mb: 2048          # …then the oldest ones while all journals weigh more than this
```

Claude Code 2.1.319 and later no longer keep the reasoning's text in their transcripts (a signature only): with
`reasoning: true` you get it for the models that still expose it; thinking tokens and time are recorded either way.

## Opening the viewer

From the adorno repo:

```sh
bin/kit serve            # http://127.0.0.1:8765 — or --port N, --runs DIR
```

- **Pick** a run (filters: workflow, repo, outcome, day); "compare with…" draws a second one next to it, with a table
  of what differs.
- **The diagram**: one lane per actor — you, the main session, each agent instance with its model, scripts, the
  guard, GitHub. Time runs left to right, idle time shortened (a grey band, with its real length). An arrow is an
  exchange; a framed block is a fix round; a red disc on your lane is a question asked to you; a red cross on the
  guard's lane is a refusal.
- **Replay**: play, pause, speed (0.5× to 8×), step, a scrubber. Elapsed time and tokens add up as it plays.
- **Detail**: click a mark (or press Enter on the current event) for its prompt excerpt, model, tokens, tool call,
  exit code, and the run's files (reviews, plan, status), opened as text. The return of an agent also lists the files
  it wrote, read from its own Write, Edit and NotebookEdit calls.
- **Views**: everything; agents only (no tool calls); tokens (a lane is as tall as what it spent); workflow (the
  steps of the run plan, or phases derived from the delegations when the run did not mark them).
- **Text log**: the same events, one per row, for a screen reader or a narrow window.

| Key | Does |
| --- | --- |
| Space | play or pause |
| ← → | previous or next event |
| Home, End | start, end |
| `<` `>` | slower, faster |
| `+` `-` `0` | zoom in, out, fit |
| `1` `2` `3` `4` | the four views |
| `[` `]` | previous or next step or round |
| Enter, Esc | open, close the detail |
| `L` | diagram or text log |
| `R` | read the run again (a run still open grows) |
| `?` | the keys |

Enter and Space keep their usual job on a link, a button or a summary. With "reduce motion" set in your system,
nothing animates: Space advances one event, from the start when the run is at its end.

The server is read-only and listens on `127.0.0.1` only. It serves a run's files from its journal folder, and from
the run's own folder only when that is an `.agent-run/` folder; never a transcript: the viewer shows its path, to copy.

## Reading the transcripts again

`run-end` starts the reading without waiting for it. To run it again (it was interrupted, the run was still going,
you changed `reasoning`):

```sh
bin/kit journal enrich <run id>
```

It only works while Claude Code still has the transcripts (it prunes them after 30 days by default).

## Deleting journals

`run-begin` prunes by itself, as the settings say: only the journal's files, never a run's deliverables nor the
journal of an open run. By hand: remove `events.jsonl`, `enriched.jsonl` and `enrich.log` from a run's folder under
`~/.adorno/runs/` — or the whole folder if you do not need its deliverables.

## Limits

- The transcript format is Claude Code's own, not a contract: the reader skips what it does not recognise. It was
  read on Claude Code 2.1.325.
- A run that does not call `run-mark` shows no step nor round; the viewer then derives phases from the delegations
  and says so.
- A session opened before the run records nothing for the time before `run-begin`.
- Not recorded: an agent's tier (the hooks give the model it resolved to, not the tier it was declared with), a
  consult between agents, and a handoff through a file. An agent's written files are not recorded as such: the viewer
  derives them from its Write, Edit and NotebookEdit calls.
- The viewer's colours are those named for the public page (paper, black rules, one red); its fonts fall back to the
  system's until Jost and IBM Plex Mono are added next to `viewer/tokens.css`, the one file to change.
