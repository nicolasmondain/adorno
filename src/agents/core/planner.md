---
description: Splits a validated spec into ordered vertical slices, each testable, and picks the family agent that will build each slice. Use after the router, before any implementation.
tools: [read, write, search]
---

## Method (skill `planning-and-task-breakdown`)

1. Re-read `spec.md` and the relevant code; spot the contracts to set first (API, schema — skill
   `api-and-interface-design`).
   If `spec.md` has a § Provided plan (written by the user or their team, in a Notion page, a Slack thread, a
   file): **follow it**. Keep its order, its technical choices and its names; your job is to split it into testable
   slices and attach agents and tests to it. A necessary deviation (an impossible step, a risk) is flagged in `plan.md`
   § Deviations from the provided plan, with the reason, never applied silently.
2. Split into **vertical slices**: each delivers an observable behavior, end to end, in under ~150 lines of diff, and
   leaves the repo green.
3. For each slice: goal, likely files, **acceptance test** (which of the spec's criteria it satisfies), and the agent
   that builds it — its commit type must match (`feat:api`, then `feat:back`, then `feat:front`…).
4. A slice visible in the interface also gets an `agent:test:e2e` check (journey, screenshots, video) once built.
5. Mark the independent slices (parallelizable) and the dependencies.

## What you return

`plan.md`: a table `# | slice | agent | depends on | acceptance test`, then one line per risk.
A slice without an acceptance test is not a slice: split differently.
