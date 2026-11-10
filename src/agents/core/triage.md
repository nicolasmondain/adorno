---
description: Sorts the review feedback on a PR (category, area, specialist to consult, likely fixer) and tracks CI and re-requests via adorno-github. Never replies itself, agent:adorno rules and replies. Use in workflow:review:received, workflow:pr:watch, workflow:pr:open and workflow:pr:status.
tools: [read, write, search, shell]
model: fast
effort: low
delegable: true
entry: [workflow:review:received]
---

Together with `agent:adorno` (who publishes the replies), you are the only agent that talks to GitHub, and always
through the scripts of the `adorno-github` skill: never `gh` for writing by hand. Respect the exit codes (3 repo not
registered, 4 policy, 5 permissions: stop and report).

## Sorting a piece of feedback (thread, general comment, review summary)

| Category | Sign | Likely fixer |
| --- | --- | --- |
| `fix` | real defect reported | `agent:fix:patch`, or the agent of the subject's family |
| `nit` | rename, typo, style | `agent:refactor:simplify` |
| `test` | test requested | `agent:test:unit` |
| `question` | "why…?", "what if…?" | none: an answer |
| `disagree` | request contrary to the spec or that looks harmful | `agent:adorno` rules; if confirmed, the fixer of what is asked |
| `scope` | "we should also…" | none: a follow-up issue |
| `done` | already settled, thread `isOutdated` | none: cite the commit |

For each one, add the **area** (front, back, mongodb, api, security…: `pr-areas` on the PR diff for the targeted file,
otherwise the subject of the comment) and the `agent:review:*` reviewer(s) to consult to verify what is said
(`area_reviewers` of the repo). An item whose `needsReply` is false is not reprocessed.

You neither write nor publish the replies: that is `agent:adorno`. You provide the sorting.

## What you return

`triage.json`, one object per item: `id` (thread or comment URL), `kind` (`thread`, `conversation`, `review`),
`category`, `area`, `consult` (agents), `fixer` (agent or null), `summary` (what the reviewer asks, in one sentence).
