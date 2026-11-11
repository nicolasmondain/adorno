# Decisions — one area table decides every agent

Date: 2026-11-10. Status: accepted (the owner's answers to the open points of the plan).

Context: `repos.yaml` › `areas` used to detect the subjects of a diff, and only `area_reviewers` turned them into agents
(reviewers). Every other choice (build, fix, perf, QA, skills) was prose, hard-coded workflow by workflow. Now one table,
`defaults.areas`, gives each area its `build`, `fix`, `perf`, `review`, `qa` and `skills`; every dispatcher reads it
through `pr-areas`, and `bin/kit check` proves every agent is reachable. How it works: [setup](../setup.md#areas-and-roles).

| # | Decision | Why |
| --- | --- | --- |
| 1 | Repo override: lists (`review`, `skills`) **add up**; an entry `-agent:…` / `-<skill>` removes one explicitly. Single-valued roles are replaced. | Replacing could drop a reviewer by mistake, pure addition could never remove a noisy one; an explicit `-x`, visible in `bin/kit conf`, gives both, like `permissions.deny` already adds up. |
| 2 | Wrongly guessed builder: **flag** in `status.md` and **recompute** reviewers, fixers and skills on the real diff; no rebuild. | The planner guesses files before the code exists; the review and fix steps must follow the real diff, but redoing a slice that works costs more than it brings. |
| 3 | **One PR** (commits per lot), opened ready by `pr:ship`. Run at **L3**. | Per-lot commits keep the review readable; a single PR removes the need for any transition layer between lots. |
| 4 | Single-use agents declare front-matter **`entry: [workflow:…]`**, checked by `kit check` (the workflow exists and lists the agent in `uses.agents`). | The declaration lives next to the agent it concerns, rather than in a separate list in `bin/kit` or `kit.yaml` that drifts. |
| 5 | **`api` is a top-level area** (not under `back`); no front sub-areas. | A route is both server code and a contract: as its own area it also matches `api-reference/` docs without pulling in `back`. Front sub-areas had no agent to give. |
| 6 | `agent:review:perf` **keeps its name**. | Renaming it to `review:perf-front` would break the local configs that name it, for symmetry alone. |
| 7 | `agent:chore:deps` commits **`chore(deps)`**, chore family. | The usual convention for dependency bumps; the default `branch_pattern` accepts it. |
| 8 | Sub-areas on **one level only** (`back.query`, `back.mongodb`); `sub` inside `sub` is refused. | One level covers the real need (queries vs schema under `back`) and keeps inheritance and the main-area rule simple to predict and test. |
| C3 | Legacy reading **removed**: `area_reviewers` is a `kit check` **error** pointing at the migration (`bin/kit migrate areas`, the `adorno-setup` skill). | With one PR (3) there is no staged delivery to bridge; a hard error with the exact conversion is clearer than two formats read side by side. |

Consequence of 3 and C3: `pr-areas` has no `reviewers` output and `resolve.jq` no legacy reading; dispatchers read
`review` directly. A local `area_reviewers` makes `bin/kit check` and `bin/kit install` fail until it is migrated.
