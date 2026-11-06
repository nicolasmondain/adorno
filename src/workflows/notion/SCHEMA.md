# `workflow:notion:*`

## `workflow:notion:assigned`

```mermaid
flowchart TD
  IN["Input: --mode report|run, --since, --dry-run, --all"]
  CF["watch-conf notion-assigned"]
  FD["Notion connector (read-only): assigned pages -> docs.json"]
  FL["watch-seen filter notion-assigned"]
  EM{"Anything new?"}
  DRY{"--dry-run?"}
  CH["Read each doc, choose action: agents config per database, else agent:core:router"]
  MD{"mode"}
  AN["report: agent:core:analyst - analysis and what the action would do"]
  RUN["run: workflow:spec:new or workflow:issue:fix at configured level (own run-begin)"]
  MK["watch-seen mark + touch"]
  RP["report.md + message to the owner only (notify)"]
  END1["End"]
  IN --> CF --> FD --> FL --> EM
  EM -->|"no"| END1
  EM -->|"yes"| DRY
  DRY -->|"yes: list only"| END1
  DRY -->|"no"| CH --> MD
  MD -->|"report"| AN --> MK
  MD -->|"run, batches of 3"| RUN --> MK
  MK --> RP
