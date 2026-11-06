---
name: adorno-commit
description: Writes a Conventional Commits message from the staged changes. Use to commit, write or fix a commit message, or split changes into several commits.
---

# Commit message

## Steps

1. Read `git diff --staged` (and `git status` if nothing is staged: suggest what to stage).
2. If the diff mixes several intents, suggest splitting it into separate commits.
3. Pick the type:

   | type | when |
   |---|---|
   | `feat` | new user-visible feature |
   | `fix` | bug fix |
   | `refactor` | restructuring without behavior change |
   | `perf` | performance |
   | `test` | tests only |
   | `docs` | documentation only |
   | `build` / `ci` | dependencies, build, pipeline |
   | `chore` | everything else (tooling, maintenance) |

4. Write the message:

   ```
   <type>(<optional scope>): <imperative summary, ≤ 72 characters, no trailing period>

   <optional body: the why, not the how; lines ≤ 72 characters>

   <optional footer: BREAKING CHANGE: …, Refs #123>
   ```

5. Add `!` after the type and a `BREAKING CHANGE:` footer if a public API changes incompatibly.

## Examples

```
fix(auth): refresh expired token before retrying request
```

```
feat(api)!: return paginated results from /users

BREAKING CHANGE: /users now returns { items, next } instead of an array.
```
