# Decisions — a benchmark for the reviewers

Date: 2026-11-14. Status: in progress (the owner's answers to the open points of the plan, recorded as they come).

Context: adorno picks its reviewers by area (`repos.yaml` › `areas`, `pr-areas`), merges their reviews
(`review-merge`), then `agent:adorno` rechecks. Models, tiers and prompts change often and nothing measured whether
the reviews stay good. `bench/` holds synthetic cases, a free routing check that runs in CI, and (next lots) a headless
runner, a scoring and a report.

| # | Decision | Why |
| --- | --- | --- |
| A | A case is described in **`case.json`**, not `case.yaml`. | The scripts and tests of this repo read JSON with `jq`; only `bin/kit` reads YAML, through PyYAML. JSON keeps the benchmark on bash and the Python standard library, with no dependency. The `rationale` field replaces comments. |
| B | A reported finding matches an expected one on **file, lines (±3) and one of the case's keywords** (regex, case-insensitive, searched in `title`, `detail` and `fix`). `category` is a label for the report, not a matching key. | The review format has no `category` field (`reviews/<agent>.json`: `severity`, `file`, `line`, `title`, `detail`, `fix`). Adding one would change the prompts being measured. |

Consequence of A and B: `case.json` › `findings[]` carries `keywords` (what a reviewer who found the defect would
write) next to `category`; `tests/bench.test.sh` checks the shape of every case.
