# Decisions — a journal of every run, and a local viewer

Date: 2026-11-14. Status: accepted (the owner's answers to the open points of the plan).

Context: a workflow run involves the main session, agents in parallel, scripts, the guard, GitHub and several models,
and nothing recorded it in one place: `status.md` says how a run ended, not how it went. Now every run has a journal,
one event per line, written while it happens by `adorno-journal/scripts/journal.py` (format:
`src/skills/adorno-journal/schema.json`), and a local viewer replays it.

| # | Decision | Why |
| --- | --- | --- |
| 1 | Models' reasoning is **off by default**, enabled by `journal.reasoning: true` in `local/adorno.yaml`. Thinking tokens and thinking time are always recorded. | It is the most sensitive part of a run, and the installed Claude Code no longer keeps its text in transcripts (signature only): nothing is lost today, and the owner opts in knowingly for the models that still expose it. |
| 2 | Prompts, results and messages are kept as an **excerpt, a hash and a pointer to the transcript**, not in full. | The transcript already holds the whole text on the same machine; copying it would double the size and the surface to redact. Limit: the whole text is gone once the tool prunes its transcripts. |
| 3 | Hooks and transcripts: **Claude Code only**. The events of adorno's scripts are recorded under every tool. | Codex and Gemini hooks and transcripts differ and were not studied; the scripts go through `_lib.sh` whatever the tool. |
| 4 | **Replay only**, with a Reload control for a run still going. | Following a run live belongs to the run monitor; the append-only format allows it later without a change. |
| 5 | Journals are kept **30 days and 2 GB**, pruned by `run-begin`, both adjustable in `local/adorno.yaml`. Only the journal's files are removed. | `~/.adorno/runs` was never pruned; a run folder also holds deliverables the journal does not own. |
| 6 | The server and the viewer are a **tool of this repo**, not shipped in `dist/`; the `adorno-journal` skill ships only what records. | A skill is copied four times into `dist/` and installed in every project, while `bin/kit serve` only runs from here. |
| 7 | **No export** in this version. | A replay shows code and names: an export needs a redaction pass the owner validates, a subject of its own. |
| 8 | **Tokens only**, no price. | A price table goes stale; tokens per model do not. |
| 9 | The server serves the journal's folder, and the run's `dir` **only when its parent folder is named `.agent-run`**. | Workflows opened with `run-begin --dir` keep their reviews, plan and status there; the name bounds what can be read to agents' deliverables. |
| 10 | The viewer's browser test runs **in CI** (job `check`, a skip fails) and locally; the macOS job skips it with a warning. | `check` is already required: the viewer is proven on every PR without a new required check. |

Consequences:

- A journal always lives under `~/.adorno/runs/<slug>-<run id>/`, whatever `run-begin --dir` says: a run's working
  folder can be inside a repo (`.agent-run/`), a journal never is. `run.begin` records `dir`.
- No workflow declares `steps:`; `step.*` and `loop` events exist for the runs that mark them, and the viewer derives
  phases from the delegations otherwise.
- The redaction patterns are the writer's own (none existed to reuse); the secret names are those of `bin/kit`
  (`SECRET_ENV_RE`), kept equal by a test.
- The writer checks every event against the schema before writing it, with a standard-library checker limited to
  the keywords the schema uses (`journal.py validate` runs the same check on a file): no dependency for one schema,
  and no line a reader would have to guess at.
