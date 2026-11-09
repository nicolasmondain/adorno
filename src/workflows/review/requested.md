---
description: Analyzes all the PRs where your review is requested — a dedicated workspace per PR, specialized reviewers chosen by the touched code, then your agent who slices and writes. By default, a pending review per PR, that you reread and submit yourself.
args: "[owner/repo] [--mode report|pending|auto] [--include-reviewed] [--direct-only] [--max N]"
uses:
  skills: [adorno-github]
  workflows: [workflow:pr:review]
model: balanced
---

Input: {{args}}

**Run** — before any write: `adorno-github/scripts/run-begin --workflow workflow:review:requested --mode <mode> --level L3 --repo owner/repo [--repo …]` — once the PR list is known, one `--repo` per repo of the kept PRs (a run only covers the repos it names) (`--deny submit` in `pending` mode); keep `id` and `dir` (the run folder). Called by another workflow that already opened its own: reuse it. Always, even after a failure: `run-end <id>`. With no open run, the scripts refuse any write.

Modes of `workflow:pr:review`: `report` (nothing on GitHub), `pending` (default: a pending review, visible only to
you), `auto` (submitted, never `APPROVE` if `allow_approve` is false).

1. **List** — `adorno-github/scripts/pr-review-requested [owner/repo]`. Drop and cite in the report:
   - unregistered repos (`registered: false`);
   - drafts (`isDraft`);
   - PRs already reviewed at their current commit (`reviewedHead`), unless `--include-reviewed`;
   - those where you already have a pending review (`pendingReview`): it is yours, leave it alone;
   - requests made to a team only, with `--direct-only`.

   Then keep at most `--max` PRs (5 by default; a positive integer, otherwise stop and say so), in the script's
   order (not yet reviewed first, then least recently updated: the longest-waiting); the others are *deferred*:
   cited in the report.
2. **Announce** — show the kept list (repo, PR, author, size) and the number deferred before starting. More than 10
   PRs (raised `--max`) or a PR of more than 1,500 lines: ask for confirmation, the analysis is expensive.
3. **Analyze** — for each PR, you run through the steps of `workflow:pr:review owner/repo#N --mode <mode>` yourself
   in the already open run (a subagent cannot launch others). PRs are independent: in batches
   of `max_parallel` (3 by default), launch in the same turn the specialists of all the PRs in the batch. Each PR has its
   own workspace and `reviews/` folder; from each PR, keep in context only its merged `review.json`
   (`review-merge`) and Adorno's pass, never the raw reviews.
4. **Report** — a table sorted by urgency: PR (link), author, touched areas, reviewers called, verdict,
   number of points (🔴 / 🟠 / 🟡 / ❓), and the link to the pending review (or submitted in `auto`). In `report`, the command
   to create the pending review: `adorno-github/scripts/pr-review-submit owner/repo#N <review-final.json>`. Below the table, the deferred
   PRs (repo, PR, author) and how to take them: in `pending` or `auto`, rerun the workflow (the PRs just reviewed
   drop out in step 1); in `report`, which leaves no trace on GitHub and would take the same PRs again, `--max N` or
   `owner/repo` to narrow.

Workspaces stay in place for a second pass; `pr-workspace --clean` deletes those of closed PRs.
