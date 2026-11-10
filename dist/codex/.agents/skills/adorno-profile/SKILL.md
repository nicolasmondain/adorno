---
name: adorno-profile
description: How the owner designs, ships and reviews code — types and single source of truth, scale and zero incidents, method, git, PR and review discipline, SBI charter. Load before any review, reply, decision or code written in their name (agent:adorno and any agent acting as them).
---

# The owner's profile

Who the owner is and how they decide. **This profile is personal**: the public repo ships no `references/`; the
owner's files come from their personal layer (`local/src/skills/adorno-profile/references/`, git-ignored) and are
installed here. **No `references/` folder next to this file → the profile is not set up**: say so once, point the
owner to the `adorno-setup` skill (mode `profile`), and meanwhile rely on the instructions and the repo settings only.

The always-on summary lives in the kit instructions (`20-owner.md`, personal too). The detail is in `references/`,
read **in full** when the task calls for it:

| File | Read it when |
| --- | --- |
| `references/engineering-types.md` | designing or judging code: TypeScript, single source of truth, simplicity, layers, maintainability |
| `references/engineering-scale.md` | anything on a read path, a cron, a worker, a hot route, error handling, a rollout |
| `references/process.md` | delivering: method, verifying the input, scope, git and stacks, PRs, fixing errors, conflicts, delegating, **review discipline** |
| `references/product.md` | judging scope, priorities, user impact, a trade-off between shipping and polishing (if present) |
| `references/personality.md` | any text that mentions a person (SBI charter, non-negotiable) |

Then the current repo's settings: `adorno-github/scripts/repo-conf` (no argument = the repo of the current directory),
from the git-ignored `local/adorno.yaml`: `team`, default `reviewers`, `commit_skill` / `pr_skill` / `setup_skill`, `context` (facts
that bind like rules), `vision` (the owner's vision lines for this repo) and `voice`. `scopes` says which workspace,
preset or repo entry each came from. Repo not registered → this profile only, and say so.

## Authority

For code, **the repo wins**: its `CLAUDE.md` and the `.claude/rules/` matching the diff are read first and override
this profile and the repo settings. A conflict is applied the repo's way and flagged to the owner.

## Traceability

When you recommend, decide, refuse or question something non-trivial, say what you rely on, in place: a repo rule
(`.claude/rules/…`), a repo `context` line, a profile principle (`engineering-types.md` ·
`engineering-scale.md` · `process.md` · `product.md` · `personality.md`) or a verified fact (`file:line`). Never cite a source you
did not read in this session; a choice without a source is a judgment call, owned as such.

## Changing it

These files are the owner's own words. Agents never edit them directly: the `adorno-setup` skill writes them on
first setup, and the `adorno-learn` skill proposes adjustments as they show up (`workflow:profile:learn` applies the
ones the owner validates). When the owner corrects you, overrides a verdict or states a preference that this profile
does not say, note it with `adorno-learn`.
