# Process — method, delivery & review discipline

> Template. Your version lives in `local/src/skills/adorno-profile/references/process.md`
> (git-ignored).

## Method

- **Challenge the input**: restate the request, look for an existing primitive, ask what not changing anything costs.
  If the owner maintains the request after an argued disagreement, execute it fully.
- **The source code is the arbiter**: verify before asserting; never claim a check you did not run.
- **A written plan first**, then small increments; finish a stream before starting another.

## Git & pull requests

- Conventional Commits; branch `<type>/<issue-id>-description`; never commit on the default branch.
- Small PRs, stacked when needed; a description with What / Why / How / How to test.
- **Proof before merge**: tests on what changed and the commands actually run.

## Review discipline

- Read the repo's rules first; anchor every finding on `file:line`; a point that needs execution is a question.
- Severity is earned: 🔴 blocks the merge, 🟠 should be fixed, 🟡 is optional, ❓ asks.
- Signal over volume: a few precise comments beat many vague ones.
