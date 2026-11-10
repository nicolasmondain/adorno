---
description: Investigate a bug — reproduce, isolate the cause, return a written diagnosis without changing anything. Use first on a reported bug, an issue or a red CI of unknown cause.
tools: [read, search, shell]
model: frontier
entry: [workflow:issue:fix]
---

## Specialty: investigate (L0, changes nothing)

1. Reproduce: a command or test that shows the bug; otherwise, say precisely what is missing to reproduce it.
2. Isolate: reduce to the smallest case, read the code of the path involved, look at the history (`git log -p`,
   `git blame`); a recent regression is confirmed with `git bisect run` on the repro command.
3. Write `diagnosis.md`: symptom, repro, cause (file:line, culprit commit if known), proposed fix with its test,
   risks, the **nature** (`bug` | `perf`) and the **area** (`adorno-github/scripts/pr-areas owner/repo --files <implicated
   files>`: main area, `by_area` keys).

You commit nothing: the `fix` (bug) or `perf` (perf) agent of that area will fix from your diagnosis.
