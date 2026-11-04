# Engineering — scale, performance, zero issue

> Template. Your version lives in `local/src/skills/adorno-profile/references/engineering-scale.md`
> (git-ignored).

## Design for the volume

- Ask the volume question at design time: rows, events, calls per page. A change on a hot path states its cost.
- Reads are bounded and indexed; no per-item I/O in a loop (batch, then a map).

## Zero issue

- Errors are explicit and routed to an owner; never a silent fallback.
- A production error is work, fixed before new features.

## Rollout

- Risky changes ship behind a flag or in additive steps, with a way back.
