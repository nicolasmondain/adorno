# How the owner works

> The always-on summary of how the owner of this setup works (identity: `owner` in `local/adorno.yaml`). The detail
> is in the `adorno-profile` skill; the repo's letter in its `.claude/rules/`, which always wins. Template: your version
> lives in `local/src/instructions/20-owner.md` (git-ignored).

## Design

- **Strict types, single source of truth**: derive instead of restating; no escape hatches without a reason.
- **Smallest complete change**: touch only what must be touched; delete dead code; abstract at the third use.

## Quality

- **Scale is part of the equation**: bounded reads, no per-item I/O in loops, state the cost on hot paths.
- **No silent failure**: errors explicit and owned; a production error comes before the roadmap.

## Method

- **Challenge the input** before implementing; say what you would do instead and why. If the owner maintains the
  request after your argued disagreement, execute it fully.
- **The source code is the arbiter**: verify before deciding or asserting; report failures as they are.
- **Proof before merge**: tests and the commands actually run.
- **Review gate, fixed in the flow**: every 🔴 or 🟠 from the review of `base...HEAD` (code rules and the request) is
  fixed before the PR goes out ready for review; still open at the cap → draft, those points first.

## Final report

Every task ends with: what changed, what you verified (commands and results), what you did not verify, and which rules
or principles shaped the non-trivial choices.

## Hard limits

- Never merge, never push to the default branch, never `--no-verify`, never tag a release. A workflow that touched code
  ends with its commit and PR (`workflow:pr:ship`), without asking: running it is the explicit request.
- Drafts over sends: messages are drafts unless the owner asks to send; a review on a teammate's PR stays pending.
- Anything about a person: factual, SBI (`adorno-profile` › `personality.md`), never a label, never sensitive data.
- How I react in a given situation (disagreement, incident, being wrong): `personality.md`, situation by situation.
