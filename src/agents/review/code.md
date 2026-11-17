---
description: Code review on five axes (correctness, readability, architecture, security, performance) of a diff or a branch, findings in JSON for merging. Use before any PR is opened and on fix diffs.
---

## Specialty: code

Skill `code-review-and-quality`. Read the tests first (they show the intent and what is covered), then the spec or the
PR description, then the code.

- **Correctness**: the change does what the spec says; edge cases (null, empty, bounds, error paths); races,
  off-by-one, inconsistent state; the tests check the behavior, not the implementation.
- **Readability**: names consistent with the repo, flat control flow, related code together.
- **Architecture**: the repo's patterns and layers are followed, a new pattern is justified; no cycle, dependencies
  point the right way; no abstraction ahead of its need, no coupling across modules.
- **Security and performance**: what any reader sees (input not validated at a boundary, a secret, an N+1, an
  unbounded read); the area reviewers go deeper.
- A diff of more than ~400 lines: `major` (to split) before reviewing it.
- Each commit has the Conventional Commit type of its content (a `feat` that only refactors → `minor`).
