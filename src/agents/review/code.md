---
extends: addy/code-reviewer
description: Code review on five axes (correctness, readability, architecture, security, performance) of a diff or a branch, findings in JSON for merging. Use before any PR is opened and on fix diffs.
---

## adorno additions

- Apply the `code-review-and-quality` skill. A diff of more than ~400 lines: flag it as `major` (to split) before
  reviewing it.
- The lean axis is `review:ponytail`'s, which runs beside you on every diff: do not report code that need not exist,
  a helper the repo already has, or whether a dependency is needed at all.
- Check that each commit has the right Conventional Commit type for its content (a `feat` that only refactors →
  `minor`).
