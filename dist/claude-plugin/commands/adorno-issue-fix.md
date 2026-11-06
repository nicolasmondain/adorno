---
description: Fix a bug from a GitHub issue, a Slack thread, a Notion page, a prompt or a validated spec — investigation, red test, minimal fix, review, PR ("Fixes
argument-hint: <owner/repo#N | Slack / Notion links | bug description with owner/repo | .agent-run folder>
---

Input: $ARGUMENTS

**Run** — as soon as checkpoint 1 is passed (before it, everything is read-only): `adorno-github/scripts/run-begin --workflow workflow:issue:fix --mode auto --level <level validated at checkpoint 1> --repo owner/repo`; keep `id` and `dir` (the run folder). Called by another workflow that already opened its own: reuse it. Always, even after a failure: `run-end <id>`. Without an open run, the scripts refuse any write.

1. **What is reported**, in a new `.agent-run/` folder:
   - an issue (`owner/repo#N` or its link): `adorno-github/scripts/issue-fetch` → `issue.json`;
   - links (Slack thread where the bug is reported, Notion page) or a file: `adorno-inputs/scripts/input-refs`, then
     `source.md` (skill `adorno-inputs`); an issue cited in the sources is read too;
   - an `.agent-run` folder with a validated `spec.md`: it stands in for the report;
   - only a description: it stands in for the report, and the repo must be named in it (or be the current clone).
2. `agent:fix:investigate` reproduces from this report and writes `diagnosis.md`. No repro possible → draft a reply
   (on the issue or the original thread, never posted) in English asking for what is missing, handed to the user;
   stop.
3. **Checkpoint 1**: diagnosis and level (L3 by default) validated by the user.
4. Branch `fix/<n>-<slug>` (no issue: `fix/<slug>`) from the base; `agent:fix:patch`: red test, fix, green suite.
5. `agent:review:code` and `agent:review:tests` in parallel; a `blocker` → back to `fix:patch` (two rounds).
6. `workflow:pr:open` with `Fixes #N` in the description if there is an issue (otherwise the links of the sources, if
   the team can access them), then `workflow:pr:watch`.
