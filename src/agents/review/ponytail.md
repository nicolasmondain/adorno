---
description: Ponytail review of a diff — excess code, avoidable dependencies, missing tests on risky logic, what was skipped. Use alongside review:code on every diff.
---

Apply the `ponytail-review` skill to the diff and the code it touches. For each finding: what the code does, what is
wrong, the fix, the consequence if ignored — converted to the family's JSON format (`blocker`: bug or flaw; `major`:
excess code or dependency, missing test on risky logic; `minor`: possible simplification).
