# `workflow:repo:*`

## `workflow:repo:onboard`

```mermaid
flowchart TD
  IN["Input: owner/repo and optional clone path"]
  CL["Local clone (given path or temp folder) - no run to open"]
  AG["agent:chore:repo detects stack and commands, runs each to verify"]
  BR["Writes AGENTS.md + CONSTRAINTS.md on branch chore/agents-onboarding - not committed"]
  UR["User reviews"]
  SU["adorno-setup, mode repo: settings, permissions, voice, workspace"]
  LY["Written to local/adorno.yaml after validation"]
  KI["bin/kit install on the repo"]
  IN --> CL --> AG --> BR --> UR --> SU --> LY --> KI
