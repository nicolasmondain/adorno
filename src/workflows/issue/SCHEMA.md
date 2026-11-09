# `workflow:issue:*`

## `workflow:issue:fix`

```mermaid
flowchart TD
  IN["Input: owner/repo#N, links, description or .agent-run folder"]
  SRC{"Kind of report"}
  IF["issue-fetch -> issue.json"]
  IR["input-refs -> source.md"]
  SP["Validated spec.md"]
  DS["Description + repo"]
  INV["agent:fix:investigate reproduces, writes diagnosis.md"]
  REP{"Reproduced?"}
  DR["Draft reply asking for missing info - never posted, stop"]
  CP1["Checkpoint 1: diagnosis and level (L3 default) validated"]
  RB["run-begin --mode auto --level validated"]
  PT["Branch fix/n-slug: agent:fix:patch - red test, fix, green suite"]
  RV["workflow:pr:ship review loop: area reviewers + agent:adorno vs the diagnosis"]
  BL{"red or orange?"}
  PO["pr_skill: PR ready for review once clean (draft at the cap), Fixes #N if issue"]
  PW["workflow:pr:watch"]
  RE["run-end id - always"]
  IN --> SRC
  SRC -->|"issue"| IF --> INV
  SRC -->|"links or file"| IR --> INV
  SRC -->|"spec folder"| SP --> INV
  SRC -->|"description"| DS --> INV
  INV --> REP
  REP -->|"no"| DR
  REP -->|"yes"| CP1 --> RB --> PT --> RV --> BL
  BL -->|"yes, max 2 rounds"| PT
  BL -->|"no"| PO --> PW --> RE
