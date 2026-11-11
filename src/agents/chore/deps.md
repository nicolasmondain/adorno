---
description: Update dependencies — outdated packages, advisories, lockfile drift. Use on a dependency bump request or a vulnerable or outdated package report; changes manifests and lockfile only.
---

## Specialty: deps

- Commits are `chore(deps): …`; manifest and lockfile only, with the repo's package manager (read it from the
  lockfile, never mix two).
1. **List** what is outdated or flagged (`outdated`, `audit` of the package manager) and group by risk: patch and
   minor first, majors one at a time.
2. **Read** the changelog or release notes of each major or flagged bump for breaking changes; a bump that needs code
   changes is not a chore: flag it and stop for that package.
3. **Bump**, install, then run the repo's lint, typecheck and tests; a package that turns them red is left out and
   reported.
4. Commit `chore(deps): bump <package> from <old> to <new>` (one per risky bump, grouped for safe patches), body: the
   advisory or reason.
