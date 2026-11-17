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
  E --> K["Performance: unbounded reads, per-item I/O, blocking work, unbounded cache; query detail goes to review:sql or review:mongodb"]
  K --> F["External dependencies: timeout, bounded retry"]
  F --> G["Observability: useful log, no personal data"]
  G --> P{"Needs a measurement (explain, profile) that cannot run?"}
  P -->|"yes"| Q["Question with the command to run, never blocker"]
  P -->|"no"| H{"Mode?"}
  Q --> H
  H -->|"review"| I["reviews/agent.json + verdict line"]
  H -->|"consultation"| J["JSON: right, partly, wrong, unclear with evidence"]
```

## `agent:review:code`

```mermaid
flowchart TD
  A["Input: diff or branch (before any PR, fix diffs)"] --> B["Five axes, skill code-review-and-quality"]
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
  B --> C["State and rendering: derived state, effects, keys, unstable references, long lists, leaks"]
  C --> D["Accessibility WCAG 2.1 AA: roles, focus, keyboard, contrast"]
  D --> E["Consistency: design system, i18n"]
  E --> F["Robustness: empty, loading, error states, unescaped input"]
  F --> G["Performance: bundle weight, deferred code, loading, interaction (INP)"]
  G --> P{"Needs a measurement (Lighthouse, profile) that cannot run?"}
  P -->|"yes"| Q["Question with the command to run, never blocker"]
  P -->|"no"| H{"Mode?"}
  Q --> H
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
  F --> G["Measure before/after: usage, reliability, performance, resources, client (front end)"]
  G --> H["Confounders: pr-merged, incidents, traffic"]
  H --> I["Verdict: grade each signal green/yellow/red, worst decides: positive, neutral, regression, inconclusive + confidence"]
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

## `agent:review:sql`

```mermaid
flowchart TD
  A["Input: diff with SQL, ORM queries or a migration, or a review comment"] --> B["Read repo rules, schema and migrations"]
  B --> C["Queries: index coverage, bounded reads, columns used"]
  C --> D["N+1: eager loading, join or IN"]
  D --> E["Injection: bound parameters, allowlisted names"]
  E --> F["Writes: atomic update, transaction scope"]
  F --> G["Migrations: no long lock, expand then contract, index first"]
  G --> H["New index: cost, duplicate leading columns, order"]
  H --> I{"Mode?"}
  I -->|"review"| J["reviews/agent.json + verdict line"]
  I -->|"consultation"| K["JSON: right, partly, wrong, unclear with evidence"]
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
  A --> S["pr-shortcuts on the diff: shortcut: markers added"]
  S -->|"limit or trigger missing, or a known limit left unmarked"| G
  S -->|"limit and trigger named"| N["a decision, not a finding"]
  E --> H["reviews/agent.json"]
  F --> H
  G --> H
  M["Audit mode: clone and optional scope"] --> N["Apply skill ponytail-audit"]
  N --> O["audit.md: Must fix / Should fix / Nice to have, Verdict, Lean, Not checked"]
  O --> P["Written in the run folder only, never published"]
```

## `agent:review:security`

```mermaid
flowchart TD
  A["Input: diff matched by a security keyword"] --> Q{"Step 0: real sensitive surface? input, authn, authz, secret, personal data, dependency"}
  Q -->|"no"| P["pass, no finding, one-line reason in the reply"]
  Q -->|"yes"| B["Audit, skill security-and-hardening, concerned files only"]
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
  A["Input: diff where logic changes"] --> B["Scenarios and level per changed function"]
  B --> C["Coverage of risky paths, edge cases, errors, readability"]
  C --> D["List missing tests: behavior, case, file"]
  D --> E{"Risky logic without a test?"}
  E -->|"yes"| F["major"]
  E -->|"no"| G["Run the repo's test suite"]
  F --> G
  G --> H["reviews/agent.json with tests: command, passed, failed"]
```
