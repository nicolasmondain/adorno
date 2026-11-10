# `agent:review:*`

## `agent:review:api`

```mermaid
flowchart TD
  A["Input: diff + API files, or a review comment"] --> B["Read repo rules and context"]
  B --> C["Contract: validated typed inputs, stable outputs, usable errors"]
  C --> D["Compatibility: removed, renamed or retyped = breaking, must be announced"]
  D --> E["Pagination and volumes"]
  E --> F["Security: per-resource authorization, no internal fields"]
  F --> G["Public docs: up to date, placeholders only"]
  G --> H{"Mode?"}
  H -->|"review"| I["reviews/agent.json + verdict line"]
  H -->|"consultation"| J["JSON: right, partly, wrong, unclear with evidence"]
```

## `agent:review:back`

```mermaid
flowchart TD
  A["Input: diff + server files, or a review comment"] --> B["Read repo rules and context"]
  B --> C["Correctness: edge cases, swallowed errors, missing await"]
  C --> D["Concurrency and idempotence: double run, races, retries"]
  D --> E["Entry points: schema validation, server-side user, no cross-account data"]
  E --> F["External dependencies: timeout, bounded retry"]
  F --> G["Observability: useful log, no personal data"]
  G --> H{"Mode?"}
  H -->|"review"| I["reviews/agent.json + verdict line"]
  H -->|"consultation"| J["JSON: right, partly, wrong, unclear with evidence"]
```

## `agent:review:code`

```mermaid
flowchart TD
  A["Input: diff or branch (before any PR, fix diffs)"] --> B["Extends addy/code-reviewer, skill code-review-and-quality"]
  B --> C{"Diff over ~400 lines?"}
  C -->|"yes"| D["Flag major: split it"]
  C -->|"no"| E["Review five axes"]
  D --> E
  E --> E1["Correctness"]
  E --> E2["Readability"]
  E --> E3["Architecture"]
  E --> E4["Security"]
  E --> E5["Performance"]
  E1 --> F["Check Conventional Commit type per commit"]
  E2 --> F
  E3 --> F
  E4 --> F
  E5 --> F
  F --> G["reviews/agent.json, merged by strictest verdict"]
```

## `agent:review:front`

```mermaid
flowchart TD
  A["Input: diff + UI files, or a review comment"] --> B["Read repo rules and context"]
  B --> C["State and rendering: derived state, effects, keys, leaks"]
  C --> D["Accessibility WCAG 2.1 AA: roles, focus, keyboard, contrast"]
  D --> E["Consistency: design system, i18n"]
  E --> F["Robustness: empty, loading, error states, unescaped input"]
  F --> G["Weight: heavy deps, images"]
  G --> H{"Mode?"}
  H -->|"review"| I["reviews/agent.json + verdict line"]
  H -->|"consultation"| J["JSON: right, partly, wrong, unclear with evidence"]
```

## `agent:review:impact`

```mermaid
flowchart TD
  A["Merged PR (workflow:pr:impact)"] --> B["What should move: signals from PR, pr-areas"]
  B --> C["When: pr-deploys, else release or tag, else merge time"]
  C --> D{"Older than impact.min_age?"}
  D -->|"no"| T["Verdict too_early"]
  D -->|"yes"| E["Windows: impact.window before and after, same weekdays"]
  E --> F["Query sources: impact.sources then every connector, note queried, no data, unavailable"]
  F --> G["Measure before/after: usage, reliability, performance, resources"]
  G --> H["Confounders: pr-merged, incidents, traffic"]
  H --> I["Verdict: positive, neutral, regression, inconclusive + confidence"]
  I --> J["impact/N.json and impact/N.md, aggregates only, every number sourced"]
  T --> J
```

## `agent:review:mongodb`

```mermaid
flowchart TD
  A["Input: diff with queries or migration, or a review comment"] --> B["Read repo rules and context"]
  B --> C["Queries: index coverage, no unbounded find"]
  C --> D["N+1: use in, lookup, grouped loading"]
  D --> E["Aggregations: early match and project, bounded lookup, sort"]
  E --> F["Writes: broad updateMany, upserts, atomic operators"]
  F --> G["Migrations: reversible, idempotent, batched, index first"]
  G --> H["New index: cost, duplicate prefix, ESR order"]
  H --> I{"Mode?"}
  I -->|"review"| J["reviews/agent.json + verdict line"]
  I -->|"consultation"| K["JSON: right, partly, wrong, unclear with evidence"]
```

## `agent:review:perf`

```mermaid
flowchart TD
  A["Input: front-end diff, or a review comment"] --> B["Scope: only what the diff changes, tied to file:line"]
  B --> C["Bundle: new deps, whole-lib imports, deferred loading"]
  C --> D["Rendering: unstable references, long lists, global state, DOM reads"]
  D --> E["Loading: image dimensions, fonts, request waterfalls, double fetch"]
  E --> F["Interaction: long sync handlers, layout-forcing animation"]
  F --> G{"Needs a measurement (Lighthouse, profile)?"}
  G -->|"yes, cannot run"| Q["Question with the command to run, never blocker"]
  G -->|"no"| H["Finding with severity and fix"]
  Q --> I["reviews/agent.json"]
  H --> I
```

## `agent:review:ponytail`

```mermaid
flowchart TD
  A["Input: diff and touched code"] --> B["Apply skill ponytail-review"]
  B --> C["Per finding: what it does, what is wrong, fix, consequence"]
  C --> D{"Kind?"}
  D -->|"bug or flaw"| E["blocker"]
  D -->|"excess code or dependency, missing test on risky logic"| F["major"]
  D -->|"possible simplification"| G["minor"]
  E --> H["reviews/agent.json"]
  F --> H
  G --> H
```

## `agent:review:security`

```mermaid
flowchart TD
  A["Input: diff matched by a security keyword"] --> Q{"Step 0: real sensitive surface? input, authn, authz, secret, personal data, dependency"}
  Q -->|"no"| P["pass, no finding, one-line reason in the reply"]
  Q -->|"yes"| B["Extends addy/security-auditor, skill security-and-hardening, concerned files only"]
  B --> C["OWASP Top 10, authentication and authorization, sensitive data"]
  C --> D{"Real secret, token or personal data in diff, fixture or docs?"}
  D -->|"yes"| E["blocker"]
  D -->|"no"| F{"Dependency added?"}
  E --> F
  F -->|"yes"| G["Maintained and necessary? Three lines of use = major"]
  F -->|"no"| H["reviews/agent.json"]
  G --> H
```

## `agent:review:tests`

```mermaid
flowchart TD
  A["Input: diff where logic changes"] --> B["Extends addy/test-engineer"]
  B --> C["Coverage of risky paths, edge cases, errors, readability"]
  C --> D["List missing tests: behavior, case, file"]
  D --> E{"Risky logic without a test?"}
  E -->|"yes"| F["major"]
  E -->|"no"| G["Run the repo's test suite"]
  F --> G
  G --> H["reviews/agent.json with tests: command, passed, failed"]
```

## `agent:review:perf-back`

```mermaid
flowchart TD
  A["Input: server diff, or a review comment"] --> B["Scope: only what the diff changes, tied to file:line"]
  B --> C["Unbounded work: no limit, whole collection in memory"]
  C --> D["Per-item I/O: N+1, unbounded concurrency"]
  D --> E["Event loop: heavy CPU, sync I/O, huge JSON"]
  E --> F["Hot paths: repeated work, unbounded cache, unreleased listeners"]
  F --> G["Projection: whole documents for a few fields; index detail goes to review:mongodb"]
  G --> H{"Needs a measurement (explain, profile)?"}
  H -->|"yes, cannot run"| Q["Question with the command to run, never blocker"]
  H -->|"no"| I["Finding with severity and fix"]
  Q --> J["reviews/agent.json"]
  I --> J
```
