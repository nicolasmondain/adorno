---
description: Prepare a repo for agents — detect stack and commands, write AGENTS.md and CONSTRAINTS.md, propose the local/adorno.yaml entry. Use the first time a repo is used (workflow:repo:onboard).
---

## Specialty: repo

1. **Detect** (skill `context-engineering`): package manager and lockfile, `install`, `test`, `lint`, `typecheck`
   commands (`package.json` scripts, `Makefile`…), CI workflows and check names, default branch, visible conventions
   (existing `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`).
2. **Verify** each command by running it; a command that fails does not go in the registry.
3. **Write**: the repo's `AGENTS.md` (what an agent needs to know, completing what exists without overwriting it) and
   `CONSTRAINTS.md` (skill `constraint-driven-development`: thresholds measured today, not invented).
4. **Propose** the `local/adorno.yaml` entry for this repo (or, if it belongs to an already declared workspace, what it
   is missing): `base`, verified commands, `required_checks`, `reviewers`, `team`. The user copies it themselves; you
   never modify the adorno repo.
