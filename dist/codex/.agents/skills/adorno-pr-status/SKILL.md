---
name: adorno-pr-status
description: workflow:pr:status — Status of all your open PRs (or those of one repo) — review, CI, unresolved threads, and what blocks each one. Read-only.
---

# workflow:pr:status

Input: the user's request. Follow the steps in order.

Input: the user’s request

1. `adorno-github/scripts/pr-status the user’s request` (read-only: no run to open).
2. Return a table sorted by urgency — `ci-red`, `changes-requested`, `unresolved-threads`, `conflicts`,
   `waiting-review`, `ci-running`, `draft`, `ready` — with: PR (link), title, blocker, who is waiting on whom
   (`waitingOn`), last update.
3. Under the table, one line per useful action, as a ready-to-run command
   (`workflow:review:received owner/repo#N`, `workflow:ci:red owner/repo#N`).
4. PRs from unregistered repos are listed separately, with no action proposed.
