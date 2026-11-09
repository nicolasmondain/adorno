---
name: adorno-review-received
description: workflow:review:received — Goes over all your open PRs (or a single one) — every unanswered comment, thread or review summary is checked by the subject's specialist in a dedicated workspace, fixed if needed, then your agent replies in your voice and resolves. Modes report, draft (default), auto.
---

# workflow:review:received

Input: the user's request. Follow the steps in order.

Input: the user’s request — with no argument: your open, ready PRs, and only those (`pr-status --ready`:
`is:pr author:@me state:open archived:false draft:false sort:updated-desc`), in the registered repos.

**Run** — before any write: `adorno-github/scripts/run-begin --workflow workflow:review:received --mode <mode> --level L3 --repo owner/repo [--repo …]` — once the PR list is known, one `--repo` per repo to process (a run only covers the repos it names); keep `id` and `dir` (the run folder). Called by another workflow that already opened its own: reuse it. Always, even after a failure: `run-end <id>`. With no open run, the scripts refuse any write.

**Never ask the owner mid-run** — this workflow often runs unattended (a scheduled job): a question blocks it. Every
item is ruled by `agent:adorno` from the specialists' evidence, whatever its severity or category. What no agent may
settle goes to *What awaits your decision* in the report, and never blocks the other items or PRs: a conflict to
rebase, a refused action (exit 4 or 5) other than those steps 2 and 7 handle, a need beyond the run's level, and
what step 7 leaves open.

| Mode | Does | Level | Publishes |
| --- | --- | --- | --- |
| `report` | steps 1 to 4 and 9: what awaits a reply, with the specialists' verified opinion | L0 | nothing |
| `draft` (default) | + fixes committed in the workspace, replies drafted | L3, push forbidden and dry run (forced by `run-begin --mode draft`) | nothing: commits stay in the workspace |
| `auto` | everything: push, replies, resolutions, reviewer re-requests | L3 | yes (step 7) |

A lower repo `max_level` always wins.

1. **Target** — with no argument: `pr-status --ready` (no drafts, no archived; most recently updated first), then `pr-feedback-fetch` on each `registered` PR; keep those with
   `needsReplyCount > 0` or with red CI. PRs are independent: in batches of `max_parallel`, launch in the same
   turn the agents of all the PRs in the batch (you delegate: an agent does not launch agents); from each PR keep
   in context only the deliverables (`triage.json`, verdicts), never the raw exchanges.
2. **Workspace** — `pr-workspace owner/repo#N`, run from your clone of the repo: the worktree of the PR's branch,
   created if it does not exist (`worktree: branch`); never a shared workspace from a previous pass. Refused (exit 4) if there are
   uncommitted changes or commits missing from GitHub. In `auto`, for commits missing from GitHub only: the error
   names the worktree `<dir>`; list `git -C <dir> rev-list origin/<branch>..HEAD`; if **every** one of these SHAs is
   recorded `clean` in a `<dir>/.agent-run/feedback-*/status.md` (the fixes of a previous `draft` pass, step 6),
   `pr-push owner/repo#N`, then `pr-workspace` again. Otherwise (a SHA not listed or not `clean`, uncommitted changes): stop on
   this PR and report it. Run folder: `<workspace>/.agent-run/feedback-<date>/` (one per PR, under the open run), with
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
   reproduced → refused. Deferred (`scope` included): the next slice of the stack or a follow-up, named.
6. **Fix** (`draft` and `auto` modes) — every confirmed item, in the workspace, each fix by the designated agent (`fix:patch`,
   `refactor:simplify`, `test:unit`, or the agent of the subject's family): one typed commit per item, message citing
   the comment, repo tests and lint green, three rounds at most. Then `review:code` and `review:ponytail` on the
   new commits only; a `blocker` → back to the fix, twice at most. Right after, each commit's SHA, its item and the review
   outcome (`clean`, or `blocker left` after the caps) go in `status.md`. A `blocker left` stops this PR before
   `pr-push`: nothing of it is pushed or replied to, and it goes to *What awaits your decision*.
7. **Publish** (`auto` mode) — `pr-push owner/repo#N` (never forced). Then `agent:adorno` writes a reply to **every** item
   in the repo's language (`reply_language`, English by default) and in your voice, with the commit SHA, and publishes: `pr-reply` (thread) or `pr-comment` (general
   comment, review summary). Then it resolves (`pr-resolve`) every thread it replied to. Left open and listed in the
   report: a point about a person and a confirmed item with no fix commit (failing after its caps), both
   unpublished drafts; a thread `pr-resolve` refuses (exit 4: the repo's `resolve_threads` leaves it to the
   reviewer, or the PR is not yours), reply published, resolution left to the reviewer.
8. **Re-request** — `pr-rerequest owner/repo#N` for each reviewer whose points are all handled;
   `ci-wait owner/repo#N`, and `workflow:ci:red` if CI turns red (two attempts at most).
9. **Report** — `status.md` per PR and, as the reply, a table: PR, item, what the reviewer said, verified verdict
   (right / partly / wrong / unclear), action, reply published or drafted. **At the top: what awaits
   your decision** (only the cases of "Never ask the owner mid-run"). In `draft`, the command to publish everything: `workflow:review:received owner/repo#N --mode auto`.
