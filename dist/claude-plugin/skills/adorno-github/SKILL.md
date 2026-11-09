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
| `pr-status [--ready] [owner/repo]` | all your open PRs: review, CI, threads, `blocker`; `--ready`: without drafts, most recent first | L0 |
| `pr-review-requested [owner/repo]` | PRs where your review is requested (directly or via a team), `reviewedHead` | L0 |
| `pr-feedback-fetch owner/repo#N` | threads, comments and review summaries to handle (`needsReply`, `bot`), CI | L0 |
| `pr-workspace owner/repo#N` | your PR, run from your clone: its branch's worktree (created if missing); otherwise a dedicated workspace under `~/.adorno` (separate clone, detached at the head commit) | L0 * |
| `pr-workspace --clean` | deletes the workspaces of closed PRs | L0 * |
| `pr-areas owner/repo DIFF_FILE` | code areas touched (front, back, mongodb…) and the reviewers to call | L0 |
| `pr-diff owner/repo#N` | metadata + diff saved to a file | L0 |
| `issue-fetch owner/repo#N` | issue + comments | L0 |
| `pr-merged owner/repo [--since 14d] [--author LOGIN] [--pr N]` | merged PRs (yours by default): merge commit, files, whether an impact report was already posted | L0 |
| `pr-deploys owner/repo#N` | when the merge reached each environment (GitHub deployments); `source: none` without deployments | L0 |
| `ci-wait owner/repo#N [seconds]` | waits for the checks to finish (required ones only, if configured) | L0 |
| `ci-failed owner/repo#N [lines]` | failed runs on the latest commit + log tails in files | L0 |
| `ci-rerun owner/repo RUN_ID` | re-runs the failed jobs, once per run | L2 |
| `run-begin --workflow ID --mode report\|draft\|pending\|comment\|auto --level Lx --repo owner/repo… [--deny a,b] [--ttl 2h]` | opens a run for the named repos: what it may write, its folder; `report` forces a dry run, `draft` refuses the conversation (code still goes out) | — |
| `guard_bash.py deny\|ask [--format=claude\|codex\|gemini]` | hook (Claude Code, Codex, Gemini) installed by `bin/kit install`: refuses or asks to confirm a push, a GitHub publication, a write to the registry or to runs, whatever the shape of the command; blocks everything without `python3`. Inside a run (Claude Code): `allow` for `git add`, `git commit`, a plain push of the branch and `gh pr create\|edit` at the run's level, so a repo's `commit_skill` / `pr_skill` run without a prompt | — |
| `repo-audit [owner/repo…]` | read-only: type and scope of the `gh` token, default branch protection (ruleset, branch protection), admin rights; advice | — |
| `run-end ID` | closes the run (always do it, even after a failure) | — |
| `run-check owner/repo\|--dir PATH LEVEL [action]` | read-only: would that write be allowed now (same rules as the write scripts, a dry run allows nothing)? Used by the guard | L0 |
| `git-push owner/repo [BRANCH] [--dir PATH] [--check]` | pushes a branch without a PR: never forced, never the base, name matching `branch_pattern`; `--check`: the checks only | L2 |
| `pr-push owner/repo#N` | pushes the workspace's commits to your PR's branch, never forced | L2 |
| `pr-reply owner/repo#N THREAD_ID FILE` | replies in a thread (`-` = stdin) | L3 |
| `pr-resolve owner/repo#N THREAD_ID` | resolves a thread if `resolve_threads: author` and you are the author | L3 |
| `pr-comment owner/repo#N FILE` | comment in the PR conversation (`-` = stdin) | L3 |
| `pr-review-submit owner/repo#N JSON_FILE` | publishes a review with inline comments; `APPROVE` only if `allow_approve` | L3 |
| `pr-rerequest owner/repo#N [login…]` | re-requests a review (default: those who already reviewed) | L3 |
| `pr-open owner/repo BRANCH "type(scope): title" FILE [--draft]` | opens the PR, requests the registry's reviewers | L3 |
| `pr-edit owner/repo#N "type(scope): title" FILE` | updates the title and description of your open PR | L3 |

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
