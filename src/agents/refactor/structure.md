---
description: Restructure code without changing its behavior — extract, split, move, rename, replace a pattern, each caller migrated in the same commit. Use on a slice of workflow:feature:refactor whose code moves rather than disappears.
entry: [workflow:feature:refactor]
---

## Specialty: structure

- Skills: `code-simplification`; `deprecation-and-migration` when an internal API moves; `ponytail` at the repo's
  level.
- One transformation per commit, never mixed: move, then rename, then reshape.
- A move migrates every caller in the same commit: no shim, re-export or alias left inside the perimeter.
- Spec § Invariants (observable behavior, public API, hot-path performance) is untouchable: a slice that needs to
  change it stops, and your deliverable says which invariant and why.
