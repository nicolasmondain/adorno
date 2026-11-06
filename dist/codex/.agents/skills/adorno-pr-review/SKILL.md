---
name: adorno-pr-review
description: workflow:pr:review — Reviews a colleague's PR in a dedicated workspace — specialized reviewers chosen by the touched code areas (front, back, mongodb, api, security…), in parallel, then your agent who rechecks, slices and writes. By default, a pending review that you reread and submit yourself.
---

# workflow:pr:review

Input: the user's request. Follow the steps in order.

Input: the user’s request

**Run** — before anything else: `adorno-github/scripts/run-begin --workflow workflow:pr:review --mode <mode> --level L3 --repo owner/repo` (`--deny submit` in `pending` mode); keep `id` and `dir` (the run folder). Called by another workflow that already opened its own: reuse it. Always, even after a failure: `run-end <id>`. With no open run, the scripts refuse any write.

| Mode | What goes to GitHub | Level |
| --- | --- | --- |
| `report` | nothing: the report only | L0 |
| `pending` (default) | a **pending** review, visible only to you, that you edit and submit | L3 |
| `auto` | the submitted review (`COMMENT` or `REQUEST_CHANGES`, never `APPROVE` unless `allow_approve`) | L3 |

Run folder: `<workspace>/.agent-run/review-<date>/` (excluded from git by `pr-workspace`), passed to `run-begin
--dir`; when called by `review:requested`, a subfolder of its run.

1. **Preconditions** — `pr-review-requested owner/repo` (or `pr-diff`): PR closed, put back to draft, or a pending
   review already opened by you (`pendingReview`) → stop, and say so.
2. **Workspace** — `pr-workspace owner/repo#N`: dedicated clone under `~/.adorno`, at the head commit, `diffBase`
   computed (diff of the PR against its own base, never the cumulative diff of a stack). Your own copies are not touched.
3. **Context** — `pr-diff owner/repo#N` (description, files, diff); linked issue if the description cites one.
4. **Areas and reviewers** — `pr-areas owner/repo <diff file>` → touched areas and `reviewers` (`always` + those of
   each area, set in `repos.yaml` and overridable in `local/adorno.yaml`). Files in `other` go to `review:code`.
5. **Local checks** according to `commands.review_checks`: `none` by default (a point that needs execution is
   a ❓, CI decides); `lint`: lint and typecheck only; `full`: + install and tests. Outputs in `checks.log`.
   A PR from a fork (`untrusted: true`): never executed, whatever the setting.
6. **Specialists in parallel** — all the agents in `reviewers` in the same turn, in review mode, each with the
   workspace, `diffBase`, the description, the files of its area (all of them for `review:code`) → `reviews/<agent>.json`.
7. **Merge** — `adorno-github/scripts/review-merge reviews/ > review.json`: always the same merge (duplicates, highest
   severity, most severe verdict); do not read each review yourself, only `review.json` (`invalid` lists a
   malformed review: rerun that specialist once).
8. **Your pass** — `agent:adorno`, situation 2, with `review.json` and the workspace: loads the area (repo rules,
   profile, `repo-conf`), rechecks each point, keeps what you would post (8 inline comments at most), writes
   `review-final.json` and `review-notes.md`. If it returns `consult` requests, run those specialists on their
   precise question and call it back with their answers (once).
9. **Publish** — `report`: nothing. `pending`: `pr-review-submit owner/repo#N review-final.json` without `event` → pending
   review. `auto`: same script, with the chosen `event`. Nothing worth posting → no review, and say so.
10. **Report** — scope, one line per point (severity, `file:line`, problem, consequence, source), verdict,
    reviewers and areas, dropped points and why, review link.
