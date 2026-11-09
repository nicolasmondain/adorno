---
description: Goes over all your open PRs (or a single one) — every unanswered comment, thread or review summary is checked by the subject's specialist in a dedicated workspace, fixed if needed, then your agent replies in your voice and resolves. Modes report, draft (default), auto.
args: "[owner/repo#N | owner/repo] [--mode report|draft|auto]"
uses:
  skills: [adorno-github, adorno-profile, adorno-voice]
  agents: [agent:core:triage, agent:adorno, agent:review:code, agent:review:ponytail, agent:review:front, agent:review:perf, agent:review:back, agent:review:mongodb, agent:review:api, agent:review:security, agent:review:tests, agent:fix:patch, agent:refactor:simplify, agent:test:unit]
  workflows: [workflow:ci:red, workflow:pr:ship]
model: balanced
---

Input: {{args}} — with no argument: your open, ready PRs, and only those (`pr-status --ready`:
`is:pr author:@me state:open archived:false draft:false sort:updated-desc`), in the registered repos.

**Run** — before any write: `adorno-github/scripts/run-begin --workflow workflow:review:received --mode <mode> --level L3 --repo owner/repo [--repo …]` — once the PR list is known, one `--repo` per repo to process (a run only covers the repos it names); keep `id` and `dir` (the run folder). Called by another workflow that already opened its own: reuse it. Always, even after a failure: `run-end <id>`. With no open run, the scripts refuse any write.

| Mode | Does | Level | Publishes |
| --- | --- | --- | --- |
| `report` | steps 1 to 4 and 9: what awaits a reply, with the specialists' verified opinion | L0 | nothing |
| `draft` (default) | + fixes committed, pushed and the PR updated (`workflow:pr:ship`), replies drafted | L3, the conversation refused (forced by `run-begin --mode draft`) | the code only: no reply, resolution nor re-request |
| `auto` | everything: push, replies, resolutions, reviewer re-requests | L3 | yes, except what `adorno-profile` files under "to validate" |

A lower repo `max_level` always wins.

1. **Target** — with no argument: `pr-status --ready` (no drafts, no archived; most recently updated first), then `pr-feedback-fetch` on each `registered` PR; keep those with
   `needsReplyCount > 0` or with red CI. PRs are independent: in batches of `max_parallel`, launch in the same
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
   new commits only; a `blocker` → back to the fix, twice at most (still open after that: it does not block, it
   goes to the report and the description).
   **Ship** (`draft` and `auto` modes), without asking: `workflow:pr:ship owner/repo <branch> <workspace>` — the
   repo's `commit_skill` for what is left, `pr-push` (never forced) or the repo's `pr_skill` pushing itself, the title
   and description updated if the fixes moved the scope.
7. **Publish** (`auto` mode) — `agent:adorno` writes each reply
   in the repo's language (`reply_language`, English by default) and in your voice, with the commit SHA, and publishes: `pr-reply` (thread) or `pr-comment` (general
   comment, review summary). It resolves (`pr-resolve`) the settled threads; it leaves open those where it asks a
   question or disputes, and keeps as a draft everything that is "to validate".
8. **Re-request** — `pr-rerequest owner/repo#N` for each reviewer whose points are all handled;
   `ci-wait owner/repo#N`, and `workflow:ci:red` if CI turns red (two attempts at most).
9. **Report** — `status.md` per PR and, as the reply, a table: PR, item, what the reviewer said, verified verdict
   (right / partly / wrong / unclear), action, reply published or drafted. **At the top: what awaits
   your decision.** In `draft`, the command to publish everything: `workflow:review:received owner/repo#N --mode auto`.
