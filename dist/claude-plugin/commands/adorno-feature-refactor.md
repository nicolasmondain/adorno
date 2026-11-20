---
description: Restructure code end to end without changing its behavior — refactor spec, green baseline and characterization tests, sliced plan, refactor agents gated by refactor-gate (no existing test changed or lost), review, PR ready for review without asking (workflow:pr:ship), follow-up until ready to merge. Two human checkpoints, the spec and the merge.
argument-hint: <the request, Slack / Notion / GitHub links, a plan file, or the .agent-run folder of a validated spec> [--mode discuss|confirm]
model: sonnet
---

Input: $ARGUMENTS

**Run** — as in `workflow:feature:build`, with `--workflow workflow:feature:refactor`.

1. **Scope** — as `workflow:feature:build` step 1 (checkpoint 1): `workflow:spec:new $ARGUMENTS`, where
   `agent:core:intake` writes the refactor shape (§ Why, § Perimeter, § Invariants, § Measures, branch
   `refactor/<slug>`), then `adorno-notion-sync start`. A spec whose goal is new or changed behavior is not a
   refactor: stop here and point to `/adorno-feature-build`.
2. **Baseline** — on `refactor/<slug>` from the base, before any change:
   1. the repo's `test`, `lint` and `typecheck` (`commands` from `pr-workspace` or `repo-conf`). A red base: stop,
      `status.md` says why; never refactor on a red base;
   2. the test command with its JUnit reporter → `<run>/baseline/tests.xml`; without JUnit, `baseline/tests.txt`
      from the runner's own list of passing tests, one id per line;
   3. the measures before: each of spec § Measures, its command and value → `<run>/measures.md`;
   4. the perimeter's code no test exercises: `pr-areas owner/repo --files <perimeter>` → `by_area.<a>.qa` for a
      visible journey, else `fallbacks.test` (`agent:test:unit`) writes characterization tests, green on the
      unchanged code, in `test:` commits (test loop, three rounds);
   5. sub-step 2 again on HEAD: that commit is the baseline, its SHA → `<run>/baseline/sha`.
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
   1. the tests with JUnit → `<run>/slices/<n>/tests.xml` (or its plain list);
   2. `adorno-github/scripts/refactor-gate owner/repo --base <baseline sha> --baseline <run>/baseline/tests.xml
      --after <run>/slices/<n>/tests.xml`: exit 0 passes; exit 1 lists its `violations`;
   3. a refusal goes back to the agent like a failing test; the fix loop's commits pass the same gate;
   4. the cap reached, or a slice that cannot stay green without changing behavior or the public API: stop, back to
      `agent:core:intake`; `status.md` proposes `/adorno-feature-build <run folder>`.
5. **Ship** — the gate on the whole branch (same `--base` and `--baseline`, `--after` from the last commit) →
   `<run>/qa/refactor-gate.json`; the measures after, in `measures.md`; then
   `workflow:pr:ship owner/repo <branch> <worktree> <run folder>`, as `workflow:feature:build` step 5.
6. **Follow** — `workflow:pr:watch` until the PR is ready (checkpoint 2: the merge, by the user).

At every stop (red base, cap, missing permission, escalation to the spec): `status.md` says where and why, and the
command to resume.
