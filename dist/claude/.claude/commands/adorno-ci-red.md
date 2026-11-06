---
description: Handles a red CI on a PR — diagnosis from the logs, a single rerun if flaky, otherwise a fix by the designated agent and a push. Use as soon as a check fails.
argument-hint: <owner/repo#N>
---

Input: $ARGUMENTS

**Run** — before anything else: `adorno-github/scripts/run-begin --workflow workflow:ci:red --mode auto --level L2 --repo owner/repo`; keep `id` and `dir` (the run folder). Called by another workflow that already opened its own: reuse it. Always, even after a failure: `run-end <id>`. With no open run, the scripts refuse any write.

1. `agent:ci:debug` reads `ci-failed $ARGUMENTS` and writes `ci.md` (class, cause, designated agent).
2. According to the class:
   - **infra**: nothing to fix; report and stop.
   - **flaky**: `ci-rerun owner/repo <run>` only once, then `ci-wait`. Relapse → treat as a real failure.
   - **real failure**: the designated agent fixes on the PR's branch, in a worktree; tests and lint locally
     first, one typed commit, then `pr-push owner/repo#N` (or `git-push owner/repo <branch>` with no PR) — never
     a direct `git push`.
3. `ci-wait $ARGUMENTS`. Still red after two fix attempts: stop.
4. Report: check, class, what was done (commit or rerun), final CI state.
