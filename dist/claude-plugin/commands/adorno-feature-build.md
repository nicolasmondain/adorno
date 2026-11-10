---
description: Take a feature end to end — scoping, routing, sliced plan, build by the feat agents, parallel review, commit and PR without asking (workflow:pr:ship), follow-up until ready to merge. Two human checkpoints, the spec and the merge.
argument-hint: <the request, Slack / Notion / GitHub links, a plan file, or the .agent-run folder of a validated spec> [--mode discuss|confirm]
model: sonnet
---

Input: $ARGUMENTS

**Run** — before anything else: `adorno-github/scripts/run-begin --workflow workflow:feature:build --mode auto --level <spec level> --repo owner/repo`; keep `id` and `dir` (the run folder). Called by another workflow that already opened its own: reuse it. Always, even after a failure: `run-end <id>`. Without an open run, the scripts refuse any write.

1. **Scope** — without a validated spec, `workflow:spec:new $ARGUMENTS` first (checkpoint 1): an idea is discussed, a
   clear prompt or links (Slack thread, Notion page, issue, plan file) are confirmed. A plan that is already written
   goes into `spec.md` § Provided plan, and `core:planner` follows it. Once the spec is validated:
   `adorno-notion-sync start <spec folder> owner/repo` (the Notion page of the request gets the repo's
   `notion_spec.start` properties; nothing to do without a Notion page or without that setting).
2. **Route** — `agent:core:router` reads `spec.md` and writes `run-plan.yaml`. If the router concludes that a single
   agent is enough, the plan has only one step: that is normal.
3. **Plan** — `agent:core:planner` writes `plan.md` (slices, the `build` agent of each slice from `pr-areas`, acceptance tests).
4. **Build and verify** — you run `run-plan.yaml` yourself (skill `adorno-run-plan`: a subagent cannot launch
   others) on the branch `<type>/<slug>`: slices (test loop, three rounds; the `qa` agent of `pr-areas` with
   screenshots and video for visible slices), then, per slice, `pr-areas` on its diff and its `review` agents in
   parallel (fix loop, two rounds, each 🔴 or 🟠 to the `fix` or `perf` of its file's area).
5. **Ship** — `workflow:pr:ship owner/repo <branch> <worktree> <run folder>`, without asking: the repo's
   `commit_skill` commits what is left; the area reviewers and `agent:adorno` check the whole branch against the
   repo's rules and `spec.md`, and every 🔴 or 🟠 is fixed in the flow (two rounds); then its `pr_skill` (default
   `workflow:pr:open`) opens the PR **ready for review**, its description in your voice. Still a 🔴 or 🟠 at the
   cap: the PR goes out as draft, those points first, and `status.md` says what waits for you.
6. **Follow** — `workflow:pr:watch` until the PR is ready (checkpoint 2: the merge, by the user).

At every stop (cap, missing permission, escalation to the spec): `status.md` says where and why, and the command to
resume.
