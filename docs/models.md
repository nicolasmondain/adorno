# Models: each step on the model that suffices

A workflow is a chain of steps: scripts, an orchestrating session, and agents. Each step runs on the cheapest model
that does it well, measured by the **cost of a finished task, not the price of a token**. A model too small for its
step costs more in rework than it saves.

Source: [Which Claude model should you build with?](https://claude.dev/blog/which-claude-model-should-you-build-with/).
The setting of each item is in its frontmatter (`model:`, `effort:`). Change it per repo in `local/adorno.yaml` ›
`models` ([setup.md › Models](setup.md#9-models-and-providers)).

## The four tiers

| Tier | Claude Code | In adorno |
| --- | --- | --- |
| `fast` | haiku | classify, route, format the output of a script: `core:triage`, `core:router`, `workflow:pr:status` |
| `balanced` | sonnet | the session that orchestrates a workflow: runs the scripts, delegates, merges by script, never judges; `review:api` and `review:tests` (measured, see [Measuring](#measuring)) |
| `deep` | opus | every other agent that judges, investigates, reviews or writes code, `agent:adorno` included (the default) |
| `frontier` | fable | the thinking phases: frame the spec (`core:intake`), slice the plan (`core:planner`), find a root cause (`fix:investigate`); the last round of a capped loop |

`inherit` keeps the session's model. Gemini CLI and Codex run everything on the session's model unless
`models.tiers.<tool>` maps the tiers (Codex has no subagents).

```mermaid
flowchart LR
  S["scripts<br/>no model"] --> O["orchestrating session<br/>balanced"]
  O --> F["triage, router<br/>fast · effort low"]
  O --> D["specialists, builders, Adorno<br/>deep"]
  O --> X["intake, planner, investigate<br/>frontier"]
  D -.->|"last round of a cap"| X
```

## The rules

1. **Scripts first.** Listing, filtering, waiting, merging reviews and publishing cost no tokens. They stay in
   `adorno-github`, `adorno-watch` and the other skills' scripts, never in a model.
2. **The session orchestrates, agents judge.** A workflow's session runs on `balanced`: it calls scripts, starts
   agents and keeps only their deliverables (`review.json`, `triage.json`, verdicts), never the raw reading. Any
   verdict, diagnosis, plan or code goes to an agent, the only way it runs on its own model. Exceptions:
   - `workflow:pr:status` is a script and a table, so it runs on `fast`;
   - `workflow:profile:learn` delegates nothing (the session itself proposes the sentences of your profile), so it
     runs on `deep`.
3. **A nested workflow runs in its caller's session.** `pr:watch` runs `ci:red` and `review:received` in its own
   session, and `slack:watch` can run a workflow action. A workflow that launches others is therefore never on
   `fast`: the guide advises against small models for long agentic loops.
4. **Thinking phases on `frontier`.** Framing a request, slicing it into vertical slices and finding a bug's root
   cause each happen once per run, and every later step depends on them: the guide gives Fable architecture planning,
   major refactors and work where Opus at `high` falls short.
5. **Effort before tier.** Effort is the finer dial. `low` for classification and formatting (triage, router,
   pr:status); the model's default everywhere else. Past `high`, the next tier at a lower effort is usually cheaper
   for the same result.
6. **Climb only on failure.** Every capped loop starts each agent on its own tier. A failed round goes again at
   `effort: high`, and the last round runs one tier up (`deep` → `frontier`), within the same cap
   ([`adorno-run-plan` › Loops](../src/skills/adorno-run-plan/SKILL.md)). An agent on an external route does not
   climb. This is the guide's "run cheap, re-run only the failures higher" pattern.
7. **Lean context for expensive models.** An agent receives the previous deliverable and the files of its area, never
   the history. Verbose reading (logs, threads, full documents) happens in the agent that needs it, not in the
   session. Exception: the Slack and Notion connectors belong to the session alone (agents have no MCP tools), so
   `notion:assigned`, `slack:mentions` and `slack:watch` read the document or thread in the session and pass it to
   the agent.

**A deliberate departure from the guide.** The guide puts well-scoped coding (bug fix, spec-driven feature) and
repeated reviews on Sonnet. The owner of this setup chose Opus for every agent that writes or judges code
(`feat:*`, `fix:patch`, `test:*`, `refactor:simplify`, `review:*`, `agent:adorno`). That costs more per token on
building and reviewing (the guide's price table). To go back to the guide on a repo, set `models.agents.<id>: balanced`
for those agents.

Reviewers follow the guide only where `bench/` measured it: `review:api` and `review:tests` run on `balanced`, the
other reviewers stay on `deep` (table in [Measuring](#measuring)). A test keeps `review:code`, `review:security` and
`agent:adorno` on `deep` or above.

## Step by step

| Workflow | Session | Steps (agent → tier) |
| --- | --- | --- |
| `ci:red` | balanced | `ci:debug` → deep; the designated fixer → deep; `pr:ship` |
| `feature:build` | balanced | `spec:new` (`intake` → frontier); `router` → fast; `planner` → frontier; `feat:*`, `test:e2e` → deep (3 rounds, the 3rd on frontier); reviewers → deep, except `review:api` and `review:tests` → balanced (2 rounds); `pr:ship`; `pr:watch` |
| `issue:fix` | balanced | `fix:investigate` → frontier; `fix:patch` → deep; `pr:ship`; `pr:watch` |
| `notion:assigned` | balanced | the session reads each document (it alone has the Notion connector); `router` → fast; `core:analyst` → deep, or the chosen workflow |
| `pr:impact` | balanced | `review:impact` → deep, per PR in parallel; `adorno` → deep |
| `pr:open` | balanced | `adorno` → deep (title and description) |
| `pr:review` | balanced | the area's `review:*` → deep (`review:api`, `review:tests` → balanced), in parallel; `review-merge` (script); `adorno` → deep |
| `pr:ship` | balanced | area reviewers → deep (`review:api`, `review:tests` → balanced); `adorno` → deep; fixers → deep (2 rounds, the 2nd on frontier) |
| `pr:status` | fast, effort low | `pr-status` (script) |
| `pr:watch` | balanced | `ci:red`, `review:received` (nested) |
| `profile:learn` | deep | none: the session proposes, you validate each point |
| `repo:audit` | balanced | `review:ponytail` (mode Audit) → deep |
| `repo:onboard` | balanced | `chore:repo` → deep; `pr:ship`; `repo:audit` with `--audit` |
| `review:received` | balanced | `triage` → fast, effort low; specialists (consult) → deep; `adorno` → deep; fixers → deep (3 rounds, the 3rd on frontier); `pr:ship` |
| `review:requested` | balanced | the steps of `pr:review` per PR |
| `slack:mentions` | balanced | `core:analyst` → deep; `adorno` → deep (draft reply) |
| `slack:watch` | balanced | the rule's action: an agent on its own tier, or a workflow in this session |
| `spec:new` | balanced | `core:intake` → frontier |

## Measuring

Every run measures itself: `run-end` writes `usage.json` in the run folder (duration, each agent with the model it
really ran on, its tokens by kind and its cost from `repos.yaml` › `prices`) and a line to
`~/.adorno/runs/usage.jsonl`. For a past session: `adorno-github/scripts/run-usage collect --session <id> --since
<ISO> --until <ISO>`. The source is the Claude Code transcripts; Codex and Gemini expose no session id to the shell,
so their runs record the duration only (`source: unavailable`). The same measure, taken during a run, enforces its
cap: `run-budget` against `max_usd` ([setup › Permissions](setup.md#4-permissions)).

Before changing a tier for good, take a real task with a check (a test that passes, a review that holds), run it on
both models, and compare their `usage.json`. Keep a mix of models only if it beats the best single model on cost per
finished task. Compare costs, not token totals: cache reads are most of the tokens and a small share of the bill.

**A tier per reviewer, with `bench/`.** Move one reviewer alone with `bench/run --agent-model agent:review:<x>=sonnet`
and compare each reviewer on its own review before the merge with `bench/report --label b --against a`
([bench/README.md › Compare a tier per reviewer](../bench/README.md#compare-a-tier-per-reviewer)). The pass rule was fixed
before the run and lives in the same section of `bench/README.md`.

Measured on 17 review cases, 2 repeats, prompts at `f91e364`, Claude Code 2.1.326, 2026-11-16/17. Run `rev-deep`
(every agent on its tier): 43.25 USD. Run `rev-balanced` (`api`, `mongodb`, `perf`, `ponytail`, `tests` on sonnet):
33.76 USD. The grades of the 194 unplanned findings of `api`, `mongodb` and `tests` were validated by the owner. The raw
results are local, not committed.

| Reviewer | Own recall (opus → sonnet) | Precision | False alarms | Cost per call | Tier |
| --- | --- | --- | --- | --- | --- |
| `review:api` | 4/4 → 4/4 | 80 % → 75 % | n/a (no clean case routes to it) | -59 % (0.18 → 0.07 USD) | balanced |
| `review:tests` | 4/4 → 4/4 (own severity 4/4 → 3/4) | 50 % → 61 % | 0 → 0 | -61 % | balanced |
| `review:mongodb` | 4/4 → 4/4 | 83 % → 68 % | n/a | -61 % | deep |

`review:mongodb` fails the precision bound (-14 points: index questions outside the diff, plaintext tokens already in
the base, a wrong Express 5 claim). On `test-asserts-nothing` (run 1), `review:tests` on sonnet raised its own
expected finding as a blocker where the case accepts major (over-rating, 1 occurrence in 4; deep rated it major both
runs). It did not change that run's merged verdict, already `block` from `review:ponytail`, and `agent:adorno` (deep)
re-rates every finding before anything is posted. The remaining risk is that a 🔴 can start a fix loop. Not decided by the measure: `review:ponytail` stays on `deep` (decided with its prompt rescope),
and `review:perf` has since been merged into `review:front` (#39). The prompt of `review:tests` was rewritten after
the measure (#38: its own scenarios instead of `addy/test-engineer`): the tier rests on the old prompt until the next
run. The controls (`code`, `back`, `front`, `security`, `perf-back`,
unchanged) kept recall and cost within 3 %, but their ungraded precision moved by up to 10 points between runs: that
is the noise of one run pair.

## Known limits

- The measure is small (4 expected findings per candidate: 2 cases x 2 repeats) and made on Claude only.
- Codex has no subagents: reviewers are skills run on the session's model, so a tier changes nothing. Gemini maps only
  `inherit` by default (`adapters/targets.yaml`), so reviewers run on the session's model. If `models.tiers.gemini` maps
  `balanced` to a flash model, `review:api` and `review:tests` go to it, which `bench/` did not measure: map `balanced`
  to a model of equivalent level, or keep them on `deep` with `models.agents.<id>: deep`.

- When a workflow runs inside another (rule 3), whether Claude Code applies the nested workflow's own `model:` is not
  verified. Assume the caller's session model.
- The prompt cache belongs to the model that wrote it: a session that switches model (a workflow whose `model:`
  differs from yours) re-reads its context at the new model's price. Start a workflow in a fresh session when you can.
