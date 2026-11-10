---
description: Handles a red CI on a PR — diagnosis from the logs, a single rerun if flaky, otherwise a fix by the designated agent, committed and pushed without asking (workflow:pr:ship), the PR description updated if the scope moved. Use as soon as a check fails.
args: "<owner/repo#N>"
roles: [fix, perf]
uses:
  skills: [adorno-github]
  agents: [agent:ci:debug, agent:fix:patch, agent:test:unit, agent:refactor:simplify, agent:chore:deps, agent:ci:fix, agent:docs:write, agent:fix:security, agent:test:e2e, agent:perf:front, agent:perf:mongodb, agent:perf:nodejs]
  workflows: [workflow:pr:ship]
model: balanced
---

Input: {{args}}

**Run** — before anything else: `adorno-github/scripts/run-begin --workflow workflow:ci:red --mode auto --level L3 --repo owner/repo`; keep `id` and `dir` (the run folder). Called by another workflow that already opened its own: reuse it. Always, even after a failure: `run-end <id>`. With no open run, the scripts refuse any write.

1. `agent:ci:debug` reads `ci-failed {{args}}` and writes `ci.md` (class, cause, designated agent).
2. According to the class:
   - **infra**: nothing to fix; report and stop.
   - **flaky**: `ci-rerun owner/repo <run>` only once, then `ci-wait`. Relapse → treat as a real failure.
   - **real failure**: the designated agent fixes on the PR's branch, in its worktree (`pr-workspace {{args}}`);
     tests and lint locally first, one typed commit. Then `workflow:pr:ship owner/repo <branch> <worktree>`: the
     repo's `commit_skill` for what is left, `pr-push` (or the repo's `pr_skill` pushes itself), the title and
     description updated if the fix moved the scope.
3. `ci-wait {{args}}`. Still red after two fix attempts: stop.
4. Report: check, class, what was done (commit or rerun), final CI state.
