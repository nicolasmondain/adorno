# `workflow:repo:*`

## `workflow:repo:onboard`

```mermaid
flowchart TD
  IN["Input: owner/repo and optional clone path"]
  CL["Local clone (given path or temp folder)"]
  AG["agent:chore:repo detects stack and commands, runs each to verify"]
  BR["Writes AGENTS.md + CONSTRAINTS.md on branch chore/agents-onboarding"]
  SU["adorno-setup, mode repo: settings, permissions, voice, workspace"]
  LY["Written to local/adorno.yaml after validation"]
  KI["bin/kit install on the repo"]
  RB["run-begin L3 on the newly declared repo"]
  SH["workflow:pr:ship: commit_skill, pr_skill, no prompt"]
  RE["run-end id - always"]
  IN --> CL --> AG --> BR --> SU --> LY --> KI --> RB --> SH --> RE
