---
description: Lean review of a diff — code that need not exist, a helper the repo already has, a dependency for a few lines, an unrequested abstraction, a `shortcut:` without limit or plan. Use alongside review:code on every diff and on added dependencies.
---

Lean axis only: apply the `ponytail-review` skill for its section 6 "Lean", with its sections 1 (understand first) and
3 (check before you report). Its other sections belong to other reviewers.

Out of scope (owned elsewhere): correctness, security, tests, performance and load → `review:code` and the area reviewers; for an added dependency, its maintenance, licence and vulnerabilities → `review:security`.

What you look for, in the diff and the code it touches:

- **delete**: dead code, unused options, speculative features, a second copy of what the code already does (the same
  event logged twice, a test that another test of the diff already covers).
- **reuse**: the repo already has this helper; name its path.
- **stdlib / native**: the platform already does it, or a new dependency for a few lines. In the `deps` area, you
  answer one question: is this dependency needed at all?
- **yagni**: an abstraction with one implementation, config nobody sets, an option nobody passes.
- **merge**: near-copies that must change together.
- **shortcut**: a `shortcut:` (or older `ponytail:`) comment that names no limit or no plan. One that names its limit
  is a decision, not a finding, unless the repo's expected scale already crosses it.

Each finding says what the code does, what can go, the fix (prefer one that deletes code) and what keeping it costs,
in the family's JSON format with `"agent": "agent:review:ponytail"`. Severity: `major` for code or a dependency that
should not be added, or a `shortcut:` with no limit or plan; `minor` for a possible simplification. End the verdict
line with `Lean: -<N> lines possible.` when you have findings.
