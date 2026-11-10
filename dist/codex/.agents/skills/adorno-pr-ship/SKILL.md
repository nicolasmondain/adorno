---
name: adorno-pr-ship
description: workflow:pr:ship — Ends every workflow that touched code — commit (the repo's commit_skill), review and fix until no 🔴 or 🟠 is left and the change meets the request, then the PR (the repo's pr_skill) opened ready for review, or pushed and updated when it is already open. No confirmation and no permission prompt, within the run's level. Last step of feature:build, issue:fix, ci:red, review:received and repo:onboard.
---

# workflow:pr:ship

Input: the user's request. Follow the steps in order.

Input: the user’s request

**Run** — reuse the caller's run: it needs L3 to open or update the PR (L2: commit and push, then stop and say the
PR is beyond the run's level). Called alone: `adorno-github/scripts/run-begin --workflow workflow:pr:ship --mode auto
--level L3 --repo owner/repo`, then always `run-end <id>`, even after a failure.

Nothing here waits for a "yes": running the workflow that touched the code is the explicit request. What stops it is
a refusal (exit 4 or 5 from a script, `deny` from the guard): report it, never work around it, never reword a refused
command.

1. **Settings** — `repo-conf owner/repo` → `commit_skill` (default `adorno-commit`) and `pr_skill` (default
   `adorno-pr-open`). A value starting with `/` is a command of the repo, otherwise a skill: load it and follow it.
2. **Commit** — in the branch's worktree (the given path, else the current clone; on the base or a shared branch:
   stop). `git status --porcelain` not empty → `commit_skill`: typed Conventional Commits, one intent each, never
   `.agent-run/`, a secret or a file the workflow did not touch, hooks run (never `--no-verify`). A hook fails → the
   `fix` of the area of the failing files (`pr-areas --files`; lint: `fallbacks.nit`) fixes it, two rounds at most, then
   stop and report. Nothing to commit and nothing
   ahead of `origin/<branch>` → nothing to ship: say so and stop.
3. **Which PR** — `pr-status owner/repo` → the line whose `branch` is this one (`isDraft` says how it stands).
4. **Review and fix, until clean** — the scope: `origin/<base>...HEAD` with no PR yet **or a PR still in draft**
   (a draft goes ready only on a verdict about the whole branch, never on its last commits alone), the commits not
   yet on `origin/<branch>` when it is open and ready.
   - `pr-areas owner/repo` on that diff → their `review` agents, in parallel, read-only, each into `reviews/<agent>.json` (with the `skills` of its areas);
     then `agent:adorno` (situation 1) rechecks them and judges as the owner: the repo's rules and `context`, the
     profile, and **the request** — the run's `spec.md`, the issue or the plan: an acceptance criterion missed or
     half done is a 🟠 anchored on its line there. `review-merge` → the verdict.
   - A 🔴 or a 🟠 → fixed in the flow: each by `by_area.<a>.fix` (or `.perf` for a performance point) of its file's
     area (`pr-areas --files <file>`; nit: `fallbacks.nit`, missing test: `fallbacks.test`), with that area's `skills`, tests and lint green, committed with `commit_skill`;
     then the reviewers again on the new commits and on the points still open. Two fix rounds at most.
   - Clean (no 🔴 nor 🟠, the request met) → **ready for review**. The cap reached with a 🔴 or 🟠 still open:
     no PR yet → it is opened as **draft**, those points at the top of its description with `file:line`; a PR already
     open → those commits are not pushed (reviewers would see known 🔴 or 🟠 land on it). Either way `status.md` says
     what waits for the owner. 🟡 and ❓ never hold it: they go in the description.
5. **No PR yet** → `pr_skill`, told whether the PR goes out ready or draft:
   - default `adorno-pr-open`: `workflow:pr:open owner/repo <branch> [.agent-run folder]`;
   - a repo skill: run it in the worktree, as it is written. It may push and run `gh pr create` itself: inside the
     run the guard lets `git push origin <branch>` and `gh pr create` through (never forced, never the base, at the
     run's level). Then `pr-status owner/repo` again: no PR for the branch → stop and report what the skill did;
     opened as draft while the verdict is clean → `pr-ready owner/repo#N`.
6. **PR already open** → push, update, ready:
   - push: `pr-push owner/repo#N` (or the repo skill pushes itself, as above);
   - default update: `agent:adorno` compares the title and description to `git diff origin/<base>...HEAD`. The scope
     moved (a new What or How, a new risk, a verification that no longer matches) → new title and description in
     English, in the owner's voice (`adorno-voice`), published by `pr-edit owner/repo#N "<title>" <file>`. Unchanged
     → nothing. A repo skill: run it in update mode (it receives `#N`); it may run `gh pr edit` itself;
   - still a draft and the verdict on the whole branch is clean → `pr-ready owner/repo#N`.
7. **Report** — commits (SHA, message), review rounds and what they fixed, push, PR URL and `opened | updated |
   unchanged`, `ready | draft` (and why), and what stopped the workflow if anything did — commits the cap held back:
   the worktree and their SHAs, and how to resume (fix, then `pr-push owner/repo#N`). Suggest
   `workflow:pr:watch owner/repo#N` when the caller does not run it.
