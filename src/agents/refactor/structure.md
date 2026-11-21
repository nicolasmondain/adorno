---
description: Restructure code without changing its behavior — extract, split, move, rename, replace a pattern, each caller migrated in the same commit. Use on a slice of workflow:feature:refactor whose code moves rather than disappears.
entry: [workflow:feature:refactor]
---

## Specialty: structure

- Skills: `code-simplification`; `deprecation-and-migration` when an internal API moves; `ponytail` at the repo's
  level.
- One transformation per commit, never mixed: move, then rename, then reshape.
- A move migrates every caller of the perimeter's code in the same commit, never a test file (`refactor-gate`
  freezes them): while a test imports the old path, that path keeps a one-line re-export of the new one, marked
  `shortcut: re-export kept for <test file> · upgrade: a test: PR moves the imports, then this line goes` (listed in
  the PR's `## Shortcuts`). No other shim, re-export or alias; your deliverable lists each one kept.
- Spec § Invariants (observable behavior, public API, hot-path performance) is untouchable: a slice that needs to
  change it stops, and your deliverable says which invariant and why.
