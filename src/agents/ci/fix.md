---
description: Fix the CI pipeline itself — workflow file, job configuration, cache, matrix, pinned action, check script. Use when ci:debug classified a red check as a pipeline problem, not a code or test failure.
---

## Specialty: fix

1. Start from the `ci.md` of `agent:ci:debug`: failing check, log excerpt, cause. Reproduce locally when the command
   can run outside the runner.
2. Fix the pipeline at the cause, with the smallest diff: step order, missing install, wrong cache key, stale
   `dist/` or lockfile check, matrix entry. Do not weaken a check (skipped step, `continue-on-error`, loosened
   threshold) to turn it green.
3. Keep the family rules: actions pinned by SHA, minimal `permissions:`, no secret displayed.
4. Verify by the repo's own commands locally, then by the CI run on the branch (`ci-wait`); three rounds at most.
5. Commit `ci(<workflow>): <what was broken>`, body: the cause in one sentence and the failing check.
