# `workflow:review:*`

## workflow:review:received

```mermaid
flowchart TD
  A["Input: PR, repo, or none; --mode; --all"] --> B["run-begin L3 (draft: code goes out, conversation stays local)"]
  B --> C["Target: pr-status --ready, pr-feedback-fetch, pending"]
  C --> S["watch-seen filter review-received (skipped for an explicit PR or --all)"]
  S -->|"something new"| D["pr-workspace: worktree of the PR branch"]
  D -->|"draft or auto, unpushed fixes of a previous pass, all clean"| DP["pr-push"]
  DP --> D
  D -->|"unknown commits or uncommitted changes"| N
  D --> E["agent:core:triage: triage.json"]
  E --> F["Specialists of the item's area (by_area review) in consult mode, in parallel"]
  F --> G["agent:adorno (situation 3): every item confirmed, refused or deferred, never asked to the owner"]
  G --> H{"Mode"}
  H -->|"report"| N["status.md and table"]
  G -->|"untrusted author"| N
  H -->|"draft or auto"| I["Fix every confirmed item, minors included: by_area fix or perf of the file, fallbacks nit or test, 3 rounds max"]
  I --> SH["workflow:pr:ship: commit_skill, review loop on new commits (2 rounds), pr-push, description updated, ready once clean (no prompt)"]
  SH -->|"blocker left after the caps: nothing pushed"| N
  SH -->|"pushed"| K{"Mode auto?"}
  K -->|"no"| N
  K -->|"yes"| L["agent:adorno replies to every item and resolves it (people and unfixed items stay drafts)"]
  L --> M["pr-rerequest, ci-wait"]
  M -->|"CI red, 2 attempts max"| R["workflow:ci:red"]
  R --> M
  M --> N
  N -->|"draft or auto"| P["watch-seen mark + touch review-received"]
  N -->|"report"| O
  P --> O["run-end"]
```

## workflow:review:requested

```mermaid
flowchart TD
  A["Input: optional owner/repo, --mode, flags"] --> B["run-begin L3, one --repo per repo"]
  B --> C["pr-review-requested"]
  C --> D{"Unregistered, draft, reviewedHead, pendingReview, team-only with --direct-only?"}
  D -->|"yes"| E["Drop and cite in report"]
  D -->|"no"| X["Keep the first --max (5 by default), least recently updated first"]
  X -->|"beyond --max"| Y["Deferred, cited in report"]
  X --> F["Announce list"]
  F --> G{"More than 10 PRs or a PR over 1500 lines?"}
  G -->|"yes"| H["Ask confirmation"]
  G -->|"yes, --unattended: no confirmation"| I
  G -->|"no"| I["For each PR: steps of workflow:pr:review in the open run"]
  H --> I
  I --> J["Batches of max_parallel: specialists in the same turn"]
  J --> K["Keep only merged review.json and adorno pass"]
  K --> L["Report table sorted by urgency"]
  E --> L
  Y --> L
  L --> M["run-end"]
```
