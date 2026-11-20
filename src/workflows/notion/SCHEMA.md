# `workflow:notion:*`

## `workflow:notion:assigned`

```mermaid
flowchart TD
  IN["Input: --mode report|run, --since, --dry-run, --all"]
  CF["watch-conf notion-assigned"]
  FD["Notion connector (read-only): assigned pages -> docs.json"]
  FL["watch-seen filter notion-assigned -> new.json"]
  EM{"Anything new?"}
  RD["Read each new doc: content, properties, all comments, then history from creation to now -> read.json with authors, authors_complete"]
  TR["watch-trust notion-assigned read.json: trusted, action_level, untrusted per doc (fails: nothing above L0, run mode stops)"]
  DRY{"--dry-run?"}
  CH["Choose action on what was read: agents config per database, else agent:core:router"]
  MD{"mode"}
  AN["report: agent:core:analyst - analysis and what the action would do"]
  RUN["run: workflow:spec:new or workflow:issue:fix on the saved source.md (never the live page) at action_level: level if every writer trusted, else L0 (own run-begin)"]
  MK["watch-seen mark + touch, only if no connector call failed"]
  RP["report.md + message to the owner only (notify)"]
  END1["End"]
  FAIL["Connector failure: no mark for the unread docs, no touch, report at the top with the --since replay (Slack DM still sent unless Slack failed)"]
  IN --> CF --> FD --> FL --> EM
  FD -->|"any connector call: error, timeout, rate limit"| FAIL
  RD -->|"error, timeout, rate limit"| FAIL
  EM -->|"no: touch"| END1
  EM -->|"yes"| RD --> TR --> DRY
  DRY -->|"yes: list only"| END1
  DRY -->|"no"| CH --> MD
  MD -->|"report"| AN --> MK
  MD -->|"run, batches of 3"| RUN --> MK
  MK --> RP
