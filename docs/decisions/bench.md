# Decisions — a benchmark for the reviewers

Date: 2026-11-14. Status: in progress (the owner's answers to the open points of the plan, recorded as they come).

Context: adorno picks its reviewers by area (`repos.yaml` › `areas`, `pr-areas`), merges their reviews
(`review-merge`), then `agent:adorno` rechecks. Models, tiers and prompts change often and nothing measured whether
the reviews stay good. `bench/` holds synthetic cases, a free routing check that runs in CI, and (next lots) a headless
runner, a scoring and a report.

| # | Decision | Why |
| --- | --- | --- |
| A | A case is described in **`case.json`**, not `case.yaml`. | The scripts and tests of this repo read JSON with `jq`; only `bin/kit` reads YAML, through PyYAML. JSON keeps the benchmark on bash and the Python standard library, with no dependency. The `rationale` field replaces comments. |
| 3 | A run replays the **review stage only**: the reviewers in parallel, `review-merge`, then the `agent:adorno` pass. No fake GitHub. | `pr-review-submit` only does mechanics on `review-final.json` (the `max_inline` cap, a comment outside the diff folded into the body), already covered by `tests/adorno-github.test.sh`. A fake GitHub would measure a script, not a model, and hide the cost of each agent inside one session. |
| 4 | **Claude Code first**, one adapter per tool in `bench/run` (`TOOLS`). Another provider (DeepSeek…) goes through the same adapter, with the provider's environment variables inherited from the shell that starts the run. | Codex turns agents into role skills and Gemini is driven differently again: each needs its own spike. The runner stores no key and sets no provider variable; the model that really ran is read from the tool's output. |
| 6 | The report shows **tokens, and the cost the tool reports itself** (`total_cost_usd` for Claude Code), empty otherwise. No price table. | A price table goes stale and a wrong price goes unnoticed. `--budget-usd` relies on the reported cost; with a tool that reports none, the runner says the budget did not apply. |
| N1 | The prompts measured are **those of the working tree**: the agents of `dist/claude-plugin`, the instructions of `dist/AGENTS.md`, public layer only. User settings, global instructions and hooks are not loaded (`--setting-sources project,local`). | A result is tied to a commit and can be reproduced on another machine; `agent:adorno` judges with the generic profile. `--model` replaces the tier of every agent. |
| N2 | **The agent writes its own review**, as in production, inside Claude Code's sandbox (writes confined to the workspace, no network, no way out of the sandbox). A review given in the last message instead of the file is salvaged and recorded as such; a missing or invalid one is run once more. | Verified on Claude Code 2.1.325: without the sandbox, `dontAsk` refuses the shell command a reviewer writes its file with. The run also measures whether an agent delivers its file. |
| N3 | In a real run the **routing follows the registry**: `bench/run --repo owner/repo`, `adorno/bench` by default, declared once in `local/adorno.yaml`. The throwaway registry with the public defaults stays in `tests/bench.test.sh`. | A script outside `tests/` that builds a `registry.json` is what the guard hook refuses, rightly: the registry decides what the scripts may write. If `local/` overrides `areas`, the run follows it and records `routing_ok: false`. |
| B | A reported finding matches an expected one on **file, lines (±3) and one of the case's keywords** (regex, case-insensitive, searched in `title`, `detail` and `fix`). `category` is a label for the report, not a matching key. | The review format has no `category` field (`reviews/<agent>.json`: `severity`, `file`, `line`, `title`, `detail`, `fix`). Adding one would change the prompts being measured. |

Still open: the default number of repeats and what the report shows over them (2), unmatched findings (1), who
validates a baseline and where it lives (5).

Consequence of A and B: `case.json` › `findings[]` carries `keywords` (what a reviewer who found the defect would
write) next to `category`; `tests/bench.test.sh` checks the shape of every case.
