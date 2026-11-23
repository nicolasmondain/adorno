---
description: Restructure code end to end without changing its behavior — refactor spec, green baseline and characterization tests, before videos of its user paths, sliced plan, refactor agents gated by refactor-gate (no existing test changed or lost), review, PR ready for review with the after videos, without asking (workflow:pr:ship), follow-up until ready to merge. Two human checkpoints, the spec and the merge.
args: "<the request, Slack / Notion / GitHub links, a plan file, or the .agent-run folder of a validated spec> [--mode discuss|confirm]"
roles: [qa, review, fix, perf]
uses:
  skills: [adorno-run-plan, adorno-inputs, adorno-notion-sync, adorno-github]
  agents: [agent:core:intake, agent:core:planner, agent:refactor:simplify, agent:refactor:structure, agent:test:unit, agent:test:e2e, agent:adorno, agent:review:code, agent:review:security, agent:review:tests, agent:review:ponytail, agent:review:api, agent:review:back, agent:review:front, agent:review:mongodb, agent:review:sql, agent:chore:deps, agent:ci:fix, agent:docs:write, agent:fix:patch, agent:fix:security, agent:perf:front, agent:perf:mongodb, agent:perf:nodejs]
  workflows: [workflow:spec:new, workflow:pr:ship, workflow:pr:watch]
model: balanced
---

Input: {{args}}

**Run** — as in `workflow:feature:build`, with `--workflow workflow:feature:refactor`.

1. **Scope** — as `workflow:feature:build` step 1 (checkpoint 1): `workflow:spec:new {{args}}`, where
   `agent:core:intake` writes the refactor shape (§ Why, § Perimeter, § Invariants, § Measures, branch
   `refactor/<slug>`), then `adorno-notion-sync start`. A spec whose goal is new or changed behavior is not a
   refactor: stop here and point to `/adorno-feature-build`.
2. **Baseline** — on `refactor/<slug>` from the base, before any change:
   1. the repo's `lint`, `typecheck` and `test` (`commands` from `pr-workspace` or `repo-conf`), the tests in one run
      with their JUnit reporter → `<run>/baseline/tests.xml` (without JUnit, `baseline/tests.txt` from the runner's
      own list of passing tests, one id per line). Any of them red: stop, `status.md` says why; never refactor on a
      red base. Then `git status --porcelain` in the worktree must be empty (the reports go to the run folder): a
      file the runner leaves (coverage, a default `junit.xml`, caches) → stop, `status.md` names them; their ignore
      line is a `chore:` PR to the repo, outside this run, never a commit here;
   2. the measures before: each of spec § Measures, its command and value → `<run>/measures.md`;
   3. the perimeter's code no test exercises: `pr-areas owner/repo --files <perimeter>` → `by_area.<a>.qa` for a
      visible journey, else `fallbacks.test` (`agent:test:unit`) writes characterization tests, green on the
      unchanged code, in `test:` commits (test loop, three rounds);
   4. sub-step 1 again on HEAD: that commit is the baseline, its SHA → `<run>/baseline/sha`;
   5. the videos before: each user path the perimeter serves (a screen, a route, a command, a job a user or a client
      reaches) → `<run>/qa/journeys.md`, recorded on the baseline by the `qa` agent of its area (`by_area.<a>.qa`,
      null: `agent:test:e2e`) → `<run>/qa/before-<journey>.<ext>`. A path that cannot be recorded: `status.md` says
      why, and the PR will go out as draft (`workflow:pr:ship` step 5).
3. **Plan** — `agent:core:planner` (§ Refactor) writes `plan.md`; no router. You write `run-plan.yaml` yourself:

   ```yaml
   workflow: workflow:feature:refactor
   pattern: sequential
   why: "behavior-preserving slices, each proven by refactor-gate"
   steps:
     - {per: slice, agent: from_plan, loop: {evaluator: refactor-gate, max: 3}}
     - {parallel: [agent:review:code, agent:review:ponytail], merge: strictest,
        loop: {fix_with: same_agent, until: no_blocker, max: 2}}
     - {workflow: workflow:pr:ship}
     - {workflow: workflow:pr:watch, mode: auto}
   permissions: <spec level>
   gates: [spec, merge]
   ```

4. **Refactor and verify** — as `workflow:feature:build` step 4, on `refactor/<slug>`, with this evaluator after each
   round:
   1. the tests, in the baseline's format → `<run>/slices/<n>/tests.<xml|txt>`;
   2. `adorno-github/scripts/refactor-gate owner/repo --dir <worktree> --base <baseline sha> --baseline
      <run>/baseline/tests.<xml|txt> --after <run>/slices/<n>/tests.<xml|txt>`, on the round's commits (it refuses a
      dirty working tree, and a `--base` that is not an ancestor of HEAD): exit 0 passes; exit 1 lists its
      `violations`; exit 2 proves nothing (dirty tree, `--base` not an ancestor, no test area, bad report);
   3. a refusal goes back to the agent like a failing test; the fix loop's commits pass the same gate. Exit 2 is
      never sent back as a refusal: a file the round's agent wrote and did not commit goes back to it to commit;
      anything else stops the slice, `status.md` quotes the gate's message;
   4. the cap reached, or a slice that cannot stay green without changing behavior or the public API: stop, back to
      `agent:core:intake`; `status.md` proposes `/adorno-feature-build <run folder>`. A move stopped because a test
      mocks the old path (`agent:refactor:structure`, planner § Refactor): stop, `status.md` names the test and the
      `test:` PR to merge first, then resume from step 2 (new baseline) with `/adorno-feature-refactor <run folder>`.
5. **Ship** — the gate on the whole branch (same `--dir`, `--base` and `--baseline`, `--after` from the last
   commit) → `<run>/qa/refactor-gate.json`; the measures after, in `measures.md`; then
   `workflow:pr:ship owner/repo <branch> <worktree> <run folder>`, as `workflow:feature:build` step 5: its step 5
   records each journey of `qa/journeys.md` again on the last commit (`qa/after-<journey>.<ext>`, the same result as
   before) and puts each before/after pair in the PR.
6. **Follow** — `workflow:pr:watch` until the PR is ready (checkpoint 2: the merge, by the user).

At every stop (red base, cap, missing permission, escalation to the spec): `status.md` says where and why, and the
command to resume.
