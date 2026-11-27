---
name: adorno-github
description: Deterministic scripts for everything GitHub — list your PRs and the reviews expected from you, prepare a dedicated workspace per PR, classify a diff by code area, read and publish reviews, reply and resolve, re-request, follow CI, open a PR. Use whenever an agent or workflow must read or write on GitHub; never call `gh` by hand to write.
---

# adorno-github

All GitHub access goes through the scripts in `scripts/` (path relative to this file). They read the `repos.json`
registry (generated from the kit's `repos.yaml`), refuse an unregistered repo, enforce the permission levels and print
JSON on stdout; messages go to stderr. Prerequisites: authenticated `gh` and `jq`.

## Scripts

| Script | Does | Level |
| --- | --- | --- |
| `repo-conf owner/repo` | the repo's merged settings (base, commands, thread policy…) | L0 |
| `pr-status [--ready] [owner/repo]` | all your open PRs: branch, review, CI, threads, `blocker`; `--ready`: without drafts, most recent first | L0 |
| `pr-review-requested [owner/repo]` | PRs where your review is requested (directly or via a team), `reviewedHead` | L0 |
| `pr-feedback-fetch owner/repo#N` | threads, comments and review summaries to handle (`needsReply`, `bot`), CI; `pending`: their ids keyed by last activity, for `watch-seen` | L0 |
| `pr-workspace owner/repo#N` | your PR, run from your clone: its branch's worktree (created if missing); otherwise a dedicated workspace under `~/.adorno` (separate clone, detached at the head commit) | L0 * |
| `pr-workspace --clean` | deletes the workspaces of closed PRs | L0 * |
| `pr-areas owner/repo DIFF_FILE` or `owner/repo --files PATH…` (`--files -`: paths on stdin) | code areas touched (front, back, back.migration…) and the agents to use: `build`, `fix`, `perf`, `qa`, `review`, `skills`, and `ponytail` (the repo's level) | L0 |
| `pr-diff owner/repo#N` | metadata + diff saved to a file | L0 |
| `pr-shortcuts DIFF_FILE` | the `shortcut:` (and older `ponytail:`) comments the diff adds, with `file` and `line`: the PR's shortcuts ledger | L0 |
| `refactor-gate owner/repo --base SHA --baseline REPORT --after REPORT [--dir PATH]` | whether a refactor kept the behavior, from the test reports at `--base` and at HEAD (JUnit XML, else one passing id per line) and the commits of `base..HEAD`: `ok`, `green` (null for a plain list), `tests` (passing ids before and after) and `violations` (`test-file-changed`, `refactor-touches-test`, `test-lost`, `test-failing`); test files are the paths of the areas built by `agent:test:*`; it proves committed rounds only: exit 1 when refused, 2 for a dirty tree (untracked files included), a `--base` that is not an ancestor of HEAD, or a repo without an area built by `agent:test:*` | L0 |
| `issue-fetch owner/repo#N` | issue + comments | L0 |
| `pr-merged owner/repo [--since 14d] [--author LOGIN] [--pr N]` | merged PRs (yours by default): merge commit, files, whether an impact report was already posted | L0 |
| `pr-deploys owner/repo#N` | when the merge reached each environment (GitHub deployments); `source: none` without deployments | L0 |
| `ci-wait owner/repo#N [seconds]` | waits for the checks to finish (required ones only, if configured) | L0 |
| `ci-failed owner/repo#N [lines]` | failed runs on the latest commit + log tails in files | L0 |
| `ci-rerun owner/repo RUN_ID` | re-runs the failed jobs, once per run | L2 |
| `notion-step plan STEP RUN_DIR [owner/repo] [--pr-url URL] [--force]` · `done STEP RUN_DIR` | the properties your repo config sets for a workflow step (`notion_spec`) on the run's Notion spec page, or why there is nothing to do; `done` records it (skill `adorno-notion-sync`) | — |
| `after-pr plan RUN_DIR [owner/repo] --pr-url URL --workflow ID [--force]` · `done SKILL RUN_DIR` | the repo skills your config says to run once the PR exists (`after_pr`), for `--workflow` (the workflow of an active run of this session on the repo, else exit 5), each with its `args` list, or why there is nothing to do; `done` records one (`workflow:pr:ship`) | — |
| `run-begin --workflow ID --mode report\|draft\|pending\|comment\|auto --level Lx --repo owner/repo… [--deny a,b] [--ttl 2h] [--max-usd N\|off]` | opens a run for the named repos: what it may write, its folder, its cost cap (`max_usd`: the smallest of the workflow's over the repos, unless `--max-usd` replaces or removes it); `report` forces a dry run, `draft` refuses the conversation (code still goes out) | — |
| `run-begin --workflow ID --watch [--ttl 24h]` | opens a watch run (`workflow:slack:*`, `workflow:notion:assigned`): report, L0, no repo, no cost cap; while it is open, the guard lets Slack and Notion read only and send to your own DM only | — |
| `guard_bash.py deny\|ask [--format=claude\|codex\|gemini]` | hook (Claude Code, Codex, Gemini) installed by `bin/kit install`: refuses or asks to confirm a push, a GitHub publication, a write to the registry or to runs, whatever the shape of the command; blocks everything without `python3`. Inside a run (Claude Code): `allow` for `git add` / `git commit` with listed flags, `git push origin BRANCH\|HEAD`, `gh pr create` of the current branch and `gh pr edit\|ready N` on your own PR, and a closed list of scripts (never `run-begin`), at the run's level, so a repo's `commit_skill` / `pr_skill` run without a prompt. Slack and Notion connectors (Claude Code): in a watch run, reads only and a message or draft to `slack.user_id` only; outside one, a Slack message to someone else asks | — |
| `repo-audit [owner/repo…]` | read-only: type and scope of the `gh` token, default branch protection (ruleset, branch protection), admin rights; advice | — |
| `run-end ID [OUTCOME] [--status FILE]` | closes the run (always do it, even after a failure); `OUTCOME` is how it ended, recorded in the journal: `done`, `draft`, `stopped`, `failed` or `ended` (the default); any other word is said on stderr and recorded as `ended`, the run closed all the same, then exit 2. After withdrawing its grant, writes what it consumed to `<dir>/usage.json`, a line to `~/.adorno/runs/usage.jsonl` and a `Cost:` line to the run's `status.md` (FILE, else `<dir>/status.md`); prints that line as `usage` | — |
| `run-usage collect --session ID --since ISO --until ISO` | read-only: duration, agents started, the real model and the tokens of each, and the cost (`prices` of the registry), from the Claude Code transcripts of the session; `source: unavailable` without a session (Codex, Gemini, a terminal). Called by `run-end`; usable on a past session | — |
| `run-budget ID` | read-only: is the run still under its cost cap (`max_usd` of `run-begin`)? Measures it like `run-end` (`run-usage` from its start to now), writes nothing; prints `{capped, id, workflow, max_usd, usd, remaining, unpriced, source, stop, reason}`. Exit 7 when the cap is reached, a model has no price (`unpriced`) or the cost cannot be measured (`source` unavailable or error); no cap: `capped: false`, exit 0. Called before each delegation, loop round and batch | L0 |
| `run-mark step-begin\|step-end INDEX NAME` · `round N CAP [REASON]` · `self-review AGENT N` | marks in the run's journal where a step of the run plan starts and ends, where a fix and review round starts, and the self-review an agent returned (`N`: the count of its `Fixed (N):`, 0 allowed) | — |
| `run-check owner/repo\|--dir PATH LEVEL [action] [--pr N]` | read-only: would that write be allowed now (same rules as the write scripts, a dry run allows nothing; `--pr`: N is your own open PR)? Used by the guard | L0 |
| `git-push owner/repo [BRANCH] [--dir PATH] [--check]` | pushes a branch without a PR: never forced, never the base, name matching `branch_pattern`; `--check`: the checks only | L2 |
| `pr-push owner/repo#N` | pushes the workspace's commits to your PR's branch, never forced | L2 |
| `pr-reply owner/repo#N THREAD_ID FILE` | replies in a thread (`-` = stdin) | L3 |
| `pr-resolve owner/repo#N THREAD_ID` | resolves a thread if `resolve_threads: author` and you are the author | L3 |
| `pr-comment owner/repo#N FILE [--attach F]…` | comment in the PR conversation (`-` = stdin), screenshots or videos attached | L3 |
| `pr-review-submit owner/repo#N JSON_FILE` | publishes a review with inline comments; `APPROVE` only if `allow_approve` | L3 |
| `pr-rerequest owner/repo#N [login…]` | re-requests those whose latest decisive review requested changes, once a commit or a reply of yours followed their latest review and if not already requested (named: same rule) | L3 |
| `pr-open owner/repo BRANCH "type(scope): title" FILE [--draft] [--refs R [--withhold U]…] [--attach F]…` | opens the PR, requests the registry's reviewers; `--attach`: the proof (screenshots, videos); `--refs <run>/refs.json`: refuses (2) a body that misses a Notion, doc or Slack link of the request; `--withhold`: a doc link of R not to publish (never Notion or Slack), listed in `withheld` | L3 |
| `pr-edit owner/repo#N "type(scope): title" FILE [--refs R [--withhold U]…] [--attach F]…` | updates the title and description of your open PR, new proof attached; `--refs` and `--withhold` as for `pr-open` | L3 |
| `pr-ready owner/repo#N` | marks your draft PR ready for review (once nothing 🔴 or 🟠 is left open) | L3 |

\* Writes only under `~/.adorno` (no variable moves it), never in your working copies nor on GitHub.

## Rules

- **Rights**: every write script checks the repo's `max_level`, its `permissions.deny`, and the active run
  (`run-begin`: level, denied actions, covered repos). Without an active run: L0, every write is refused. A run is
  valid only for the repos it names; two runs on the same repo (two sessions): the strictest applies, and the script
  says so. `ADORNO_LEVEL` can only **lower** the level.
- **Dry run**: a run in `report` mode, or `ADORNO_DRY_RUN=1`, makes the write scripts print what they would
  publish, without publishing anything. A `draft` run pushes code and opens or updates the PR, and refuses the
  conversation: `reply`, `comment`, `resolve`, `rerequest`, `review`, `submit`, `ci_rerun` (exit 4).
- **Pushing**: `git-push owner/repo <branch>` (no PR) or `pr-push owner/repo#N`. A direct push only from a repo's
  own `commit_skill` / `pr_skill`, inside the run (`workflow:pr:ship`): the guard lets it through at the run's level.
- **Language**: texts published on GitHub (replies, PR descriptions) are in the repo's `reply_language` (`en` by
  default), whatever the language of the conversation.
- **Journal**: inside a run, every script (but `run-end`, which records `run.end`) records what it did in the run's journal (skill `adorno-journal`): its
  call and exit code, the level it asked for, each write that reached GitHub, each merged finding, each refusal of
  the guard. Private (`~/.adorno/runs/<slug>-<run id>/events.jsonl`, whatever `--dir` says), secrets redacted, and
  never a reason to fail: without `python3` or the skill, nothing is recorded and the script goes on.
- **Working files**: each script has its own temporary folder, readable only by you (`~/.adorno/tmp/<pid>`, purged
  after a day); deliverables go in the run folder that `run-begin` returns.
- **Workspaces**: your PR (not a fork), `pr-workspace` run from your clone of the repo → the worktree where its branch
  is checked out, created under `~/.adorno/worktrees/<owner>__<repo>/<branch>` if there is none, fast-forwarded to the
  branch on GitHub; `pr-push` pushes from it. Any other PR, or outside your clone → one per PR,
  `~/.adorno/workspaces/<owner>__<repo>/pr-<N>`, detached at the head commit. `worktree` (`branch` | `detached`) in the
  output says which. `.agent-run/` is excluded from git there. `pr-workspace` refuses a workspace that contains
  uncommitted changes or commits missing from GitHub.
- **Signature**: if `reply_footer` is set for the repo, it is appended to any published text.

## Exit codes

| Code | Meaning | What to do |
| --- | --- | --- |
| 0 | success | — |
| 1 | failure (or red CI for `ci-wait`) | read stderr |
| 2 | wrong usage | fix the arguments |
| 3 | repo declared nowhere (`local/adorno.yaml`: `repos`, `workspaces`) | stop and report it, never work around it |
| 4 | refused by the repo's policy | stop and report it |
| 5 | insufficient permission level | stop and ask the user to widen it |
| 6 | timeout (`ci-wait`) | retry later or report |
| 7 | the run's cost cap is reached, or cannot be guaranteed (`run-budget`: a model with no price, cost not measurable) | launch nothing more (any non-zero exit of `run-budget`, orchestration › Runs), `status.md` starts with `Stopped: budget`, then `run-end ID stopped`; resume: rerun the workflow with `--max-usd N` (the budget for the rest, counted from the resume) or `off` |
