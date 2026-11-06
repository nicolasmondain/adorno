# `workflow:spec:*`

## `workflow:spec:new`

```mermaid
flowchart TD
  IN["Input: idea, clear prompt or links, optional owner/repo and --mode"]
  RP["Resolve repo (repo-conf); create .agent-run/date-slug/"]
  UN{"Repo declared?"}
  ON["Offer workflow:repo:onboard"]
  SR["adorno-inputs/scripts/input-refs -> source.md"]
  MD{"Mode"}
  DI["discuss: one question at a time"]
  CO["confirm: spec first, then numbered confirmations"]
  IT["agent:core:intake writes spec.md"]
  CP["Checkpoint 1: explicit yes"]
  FX["Corrections: agent updates spec"]
  OUT["Return run folder + next command"]
  FB["workflow:feature:build folder"]
  IF["workflow:issue:fix folder"]
  IN --> RP --> UN
  UN -->|"no"| ON
  UN -->|"yes"| SR --> MD
  MD -->|"idea, no sources"| DI --> IT
  MD -->|"source.md or clear request"| CO --> IT
  IT --> CP
  CP -->|"corrections"| FX --> CP
  CP -->|"yes"| OUT
  OUT --> FB
  OUT --> IF
