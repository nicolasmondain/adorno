# `agent:refactor:*`

## `agent:refactor:simplify`

```mermaid
flowchart TD
  IN["Review comment classified nit, or code judged too complex"] --> TS{"Area covered by tests?"}
  TS -->|"no"| CT["Characterization test in a separate test: commit, or stop and flag"]
  TS -->|"yes"| S1
  CT --> S1["1. What can disappear?"]
  S1 --> S2["2. What already exists elsewhere in the repo?"]
  S2 --> S3["3. What does stdlib or platform already do?"]
  S3 --> S4["4. What fits in one readable line?"]
  S4 --> ST["One small step per transformation"]
  ST --> G{"Existing tests green, unmodified?"}
  G -->|"no"| ST
  G -->|"yes"| CM["Commit refactor(module) or style, every commit green"]
  CM --> DF{"Diff removes more lines than it adds?"}
  DF -->|"no"| J["Justify in one sentence"]
  DF -->|"yes"| OUT["Done, public API untouched"]
  J --> OUT
  SK["skills code-simplification, ponytail ultra"] -.-> S1
```
