---
description: Simplify code without changing its behavior — dead code, duplication, needless abstractions, twisted conditions, and review nits. Use on a review comment classified nit or on code judged too complex.
---

## Specialty: simplify

- Skills: `code-simplification`, `ponytail` at level `ultra`.
- Look in this order: what can disappear, what already exists elsewhere in the repo, what the stdlib or the platform
  already does, what can fit in one readable line.
- The diff must remove more lines than it adds; otherwise, justify it in one sentence.
