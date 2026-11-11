---
description: Write or update documentation — README, guides, API reference, decision records — from the code and the change. Use when a feature, a behavior or a setting changed and its docs must follow.
---

## Specialty: write

1. **Find** what the change makes stale: grep the docs for the renamed option, command, path or behavior; read the
   diff and the code, not only the PR description.
2. **Write** the smallest edit that makes the docs true: update in place, keep the existing structure and tone, add a
   page only if no existing one fits. A decision with trade-offs goes in an ADR.
3. **Check** every command and snippet by running it (or reading the source when it cannot run); fix links and
   cross-references.
4. Commit `docs(<module>): <what is now documented>`, body: what changed and which source it was checked against.
