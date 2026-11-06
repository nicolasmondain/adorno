# `workflow:profile:*`

## `workflow:profile:learn`

```mermaid
flowchart TD
  IN["Input: --all, --kind"]
  LS["adorno-learn/scripts/learn-list --ready"]
  EM{"Pending points?"}
  END1["Say so, end"]
  SRC["adorno-setup/scripts/adorno-source -> personal layer"]
  RD["Read target file: profile references, voice.md or 20-owner.md"]
  PR["Show point: evidence, exact diff, contradiction if any"]
  CH{"Owner decides"}
  RF["Rephrase: owner dictates, new diff"]
  WR["Write in personal layer only"]
  LD["learn-decide key accepted"]
  LD2["learn-decide key rejected or later"]
  AP["bin/kit check, then bin/kit install --global"]
  RP["Report: what changed, file by file"]
  IN --> LS --> EM
  EM -->|"no"| END1
  EM -->|"yes"| SRC --> RD --> PR --> CH
  CH -->|"rephrase"| RF --> PR
  CH -->|"accept"| WR --> LD --> AP
  CH -->|"reject / later"| LD2 --> AP
  AP --> RP
