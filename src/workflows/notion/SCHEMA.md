# `workflow:notion:*`

## `workflow:notion:assigned`

```mermaid
flowchart TD
  IN["Input: --mode report|run, --since, --dry-run, --all"]
  CF["watch-conf notion-assigned"]
  FD["Notion connector (read-only): assigned pages + comments -> docs.json with authors, authors_complete"]
  FL["watch-seen filter notion-assigned"]
  EM{"Anything new?"}
  TR["watch-trust notion-assigned: trusted, action_level, untrusted per doc"]
  DRY{"--dry-run?"}
  CH["Read each doc, choose action: agents config per database, else agent:core:router"]
  MD{"mode"}
  AN["report: agent:core:analyst - analysis and what the action would do"]
  RUN["run: workflow:spec:new or workflow:issue:fix at action_level: level if every writer trusted, else L0 (own run-begin)"]
  MK["watch-seen mark + touch"]
  RP["report.md + message to the owner only (notify)"]
  END1["End"]
  FAIL["Connector failure: no mark, no touch, report at the top (Slack DM still sent unless Slack failed)"]
  IN --> CF --> FD --> FL --> EM
  FD -->|"error, timeout, rate limit"| FAIL
  EM -->|"no: touch"| END1
  EM -->|"yes"| TR --> DRY
  DRY -->|"yes: list only"| END1
  DRY -->|"no"| CH --> MD
  MD -->|"report"| AN --> MK
  MD -->|"run, batches of 3"| RUN --> MK
  MK --> RP
