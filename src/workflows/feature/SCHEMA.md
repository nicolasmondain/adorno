# `workflow:feature:*`

## `workflow:feature:build`

```mermaid
flowchart TD
  IN["Input: request, links, plan file or .agent-run folder"]
  RB["run-begin --mode auto --level from spec"]
  SPEC{"Validated spec?"}
  SN["workflow:spec:new - checkpoint 1"]
  NS["adorno-notion-sync start - Notion spec page properties"]
  RT["agent:core:router writes run-plan.yaml"]
  PL["agent:core:planner writes plan.md"]
  subgraph BUILD["Run plan on branch type/slug (adorno-run-plan)"]
    SL["feat:* agent builds each slice - test loop, 3 rounds"]
    QA["agent:test:e2e - screenshots and video for visible slices"]
    RV["Parallel reviewers: review:code, review:security, review:tests, review:ponytail"]
    FX["Fix loop - 2 rounds"]
  end
  PO["workflow:pr:ship with the spec folder - commit_skill, review loop, pr_skill, without asking"]
  PW["workflow:pr:watch until ready"]
  CP3["Checkpoint 2: merge by the user"]
  ST["status.md: where, why, how to resume"]
  RE["run-end id - always"]
  IN --> RB --> SPEC
  SPEC -->|"no"| SN --> NS
  SPEC -->|"yes"| NS
  NS --> RT
  RT --> PL --> SL --> QA --> RV
  RV -->|"blocker or major"| FX --> RV
  RV -->|"pass"| PO --> PW --> CP3 --> RE
  FX -->|"cap reached"| ST --> RE
  SL -->|"cap, missing permission, spec escalation"| ST
