---
description: Take a feature end to end — scoping, routing, sliced plan, build by the feat agents, parallel review, commit and PR without asking (workflow:pr:ship), follow-up until ready to merge. Two human checkpoints, the spec and the merge.
argument-hint: <the request, Slack / Notion / GitHub links, a plan file, or the .agent-run folder of a validated spec> [--mode discuss|confirm]
---

Input: $ARGUMENTS

**Run** — before anything else: `adorno-github/scripts/run-begin --workflow workflow:feature:build --mode auto --level <spec level> --repo owner/repo`; keep `id` and `dir` (the run folder). Called by another workflow that already opened its own: reuse it. Always, even after a failure: `run-end <id>`. Without an open run, the scripts refuse any write.

1. **Scope** — without a validated spec, `workflow:spec:new $ARGUMENTS` first (checkpoint 1): an idea is discussed, a
   clear prompt or links (Slack thread, Notion page, issue, plan file) are confirmed. A plan that is already written
   goes into `spec.md` § Provided plan, and `core:planner` follows it.
2. **Route** — `agent:core:router` reads `spec.md` and writes `run-plan.yaml`. If the router concludes that a single
   agent is enough, the plan has only one step: that is normal.
3. **Plan** — `agent:core:planner` writes `plan.md` (slices, the `feat:*` agent of each slice, acceptance tests).
4. **Build and verify** — you run `run-plan.yaml` yourself (skill `adorno-run-plan`: a subagent cannot launch
   others) on the branch `<type>/<issue-id>-<slug>`: slices (test loop, three rounds; QA by `agent:test:e2e` with
   screenshots and video for visible slices), then reviewers in parallel (fix loop, two rounds).
5. **Ship** — `workflow:pr:ship owner/repo <branch>`, without asking: the repo's `commit_skill` commits what is
   left, its `pr_skill` (default `workflow:pr:open`, where `agent:adorno` reviews the branch as you would) opens the
   PR, its description in your voice. An open 🔴 or 🟠 keeps it as draft, at the top of the description.
6. **Follow** — `workflow:pr:watch` until the PR is ready (checkpoint 2: the merge, by the user).

At every stop (cap, missing permission, escalation to the spec): `status.md` says where and why, and the command to
resume.
