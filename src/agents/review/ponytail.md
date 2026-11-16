---
description: Ponytail review of a diff — excess code, avoidable dependencies, missing tests on risky logic, what was skipped. Use alongside review:code on every diff.
---

Apply the `ponytail-review` skill to the diff and the code it touches. For each finding: what the code does, what is
wrong, the fix, the consequence if ignored — converted to the family's JSON format (`blocker`: bug or flaw; `major`:
excess code or dependency, missing test on risky logic; `minor`: possible simplification).

Shortcuts: `adorno-github/scripts/pr-shortcuts <diff file>` (the input diff, saved to a file) lists the `shortcut:`
(or older `ponytail:`) comments the diff adds. A marker that names its limit and its trigger is a decision, not a finding, unless the expected load
already crosses that limit. A marker missing one of them is a `minor`, and so is a limit the diff knowingly leaves
(a fixed cap, an unpaginated list, a scope left out) with no marker. The fix in both cases:
`shortcut: <the limit>, <when to upgrade>` on that line.
