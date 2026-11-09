---
description: Goes over all your open PRs (or a single one) — every unanswered comment, thread or review summary is checked by the subject's specialist in a dedicated workspace, fixed if needed, then your agent replies in your voice and resolves. Modes report, draft (default), auto.
args: "[owner/repo#N | owner/repo] [--mode report|draft|auto] [--all]"
uses:
  skills: [adorno-github, adorno-watch, adorno-profile, adorno-voice]
  agents: [agent:core:triage, agent:adorno, agent:review:code, agent:review:ponytail, agent:review:front, agent:review:perf, agent:review:back, agent:review:mongodb, agent:review:api, agent:review:security, agent:review:tests, agent:fix:patch, agent:refactor:simplify, agent:test:unit]
  workflows: [workflow:ci:red]
model: balanced
---

Input: {{args}} — with no argument: your open, ready PRs, and only those (`pr-status --ready`:
`is:pr author:@me state:open archived:false draft:false sort:updated-desc`), in the registered repos.

**Run** — before any write: `adorno-github/scripts/run-begin --workflow workflow:review:received --mode <mode> --level L3 --repo owner/repo [--repo …]` — once the PR list is known, one `--repo` per repo to process (a run only covers the repos it names); keep `id` and `dir` (the run folder). Called by another workflow that already opened its own: reuse it. Always, even after a failure: `run-end <id>`. With no open run, the scripts refuse any write.

| Mode | Does | Level | Publishes |
| --- | --- | --- | --- |
| `report` | steps 1 to 4 and 9: what awaits a reply, with the specialists' verified opinion | L0 | nothing |
| `draft` (default) | + fixes committed in the workspace, replies drafted | L3, push forbidden and dry run (forced by `run-begin --mode draft`) | nothing: commits stay in the workspace |
| `auto` | everything: push, replies, resolutions, reviewer re-requests | L3 | yes, except what `adorno-profile` files under "to validate" |

A lower repo `max_level` always wins.

1. **Target** — with no argument: `pr-status --ready` (no drafts, no archived; most recently updated first), then `pr-feedback-fetch` on each `registered` PR.
   **Keep only what is new**: `pr-feedback-fetch owner/repo#N | jq .pending | adorno-watch/scripts/watch-seen filter
   review-received -` — `pending` lists what needs a reply plus a red CI, each keyed by its last activity (a new reply
   in a thread, a new head commit bring it back); keep the PRs with at least one entry left, and hand triage only
   those items. An explicit `owner/repo#N` or `--all` skips this filter (that is how a draft gets published). PRs are independent: in batches of `max_parallel`, launch in the same
   turn the agents of all the PRs in the batch (you delegate: an agent does not launch agents); from each PR keep
   in context only the deliverables (`triage.json`, verdicts), never the raw exchanges.
2. **Workspace** — `pr-workspace owner/repo#N`, run from your clone of the repo: the worktree of the PR's branch,
   created if it does not exist (`worktree: branch`); never a shared workspace from a previous pass. Refused if there are
   uncommitted changes or commits missing from GitHub: stop on this PR and report it. Run folder: `<workspace>/.agent-run/feedback-<date>/` (one per PR, under the open run), with
   `feedback.json`.
3. **Triage** — `agent:core:triage` classifies each item where `needsReply` is true (thread, general comment,
   review summary): category (`fix`, `nit`, `test`, `question`, `disagree`, `scope`, `done`), **area** (deduced
   from the targeted file with `pr-areas` on the PR diff, or from the comment's subject), specialist(s) to consult,
   likely fixer agent → `triage.json`. Bot comments do not require a reply; their findings
   are checked like the others when they target code (AI reviewer).
4. **Verify what is said** — for each item that claims something about the code (everything except `done`), the
   specialist(s) of its area in **consult** mode, in parallel: is the reviewer right? evidence required
   (code read, command run in the workspace) → `consult/<item>-<agent>.json`.
5. **Decide** — `agent:adorno`, situation 3: loads the area (repo rules, profile, the repo's `repo-conf`), reads triage and opinions, consults another specialist if an opinion does not hold, and rules
   **confirmed / refused / deferred** for each item. A colleague: no evidence against them → confirmed. A bot: not
   reproduced → refused. Deferred: the next slice of the stack, named.
6. **Fix** (`draft` and `auto` modes) — in the workspace, each fix by the designated agent (`fix:patch`,
   `refactor:simplify`, `test:unit`, or the agent of the subject's family): one typed commit per item, message citing
   the comment, repo tests and lint green, three rounds at most. Then `review:code` and `review:ponytail` on the
   new commits only; a `blocker` → back to the fix, twice at most.
7. **Publish** (`auto` mode) — `pr-push owner/repo#N` (never forced). Then `agent:adorno` writes each reply
   in the repo's language (`reply_language`, English by default) and in your voice, with the commit SHA, and publishes: `pr-reply` (thread) or `pr-comment` (general
   comment, review summary). It resolves (`pr-resolve`) the settled threads; it leaves open those where it asks a
   question or disputes, and keeps as a draft everything that is "to validate".
8. **Re-request** — `pr-rerequest owner/repo#N` for each reviewer whose points are all handled;
   `ci-wait owner/repo#N`, and `workflow:ci:red` if CI turns red (two attempts at most).
9. **Report** — `status.md` per PR and, as the reply, a table: PR, item, what the reviewer said, verified verdict
   (right / partly / wrong / unclear), action, reply published or drafted. **At the top: what awaits
   your decision.** In `draft`, the command to publish everything: `workflow:review:received owner/repo#N --mode auto`.
10. **Remember** (`draft` and `auto` modes) — `watch-seen mark review-received <id>…` with the `pending` ids of each
   PR that got its verdicts (not a PR stopped at step 2), then `watch-seen touch review-received`: the next sweep
   skips them until someone writes again. `report` remembers nothing.
