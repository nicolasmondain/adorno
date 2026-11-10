---
description: Prepare a repo for the agents — detect stack, commands and checks, write AGENTS.md and CONSTRAINTS.md, propose its complete entry in local/adorno.yaml, then commit them and open the PR without asking (workflow:pr:ship). Do it once per repo.
args: "<owner/repo> [path of the local clone]"
uses:
  skills: [adorno-github, adorno-setup]
  agents: [agent:chore:repo]
  workflows: [workflow:pr:ship]
model: balanced
---

Input: {{args}}

1. Local clone: the given path, otherwise a clone in a temporary folder.
2. `agent:chore:repo` detects, verifies each command by running it, and writes `AGENTS.md` and `CONSTRAINTS.md` in a
   branch `chore/agents-onboarding` (it does not commit: `workflow:pr:ship` does).
3. Declare the repo with the skill `adorno-setup`, mode `repo`: settings, permissions, voice, possibly a workspace,
   written to `local/adorno.yaml` (ignored by git) after validation, then `bin/kit install` on the repo. Nothing is
   written or committed in the tracked files of the adorno repo.
4. **Ship**, without asking, once the repo is declared (before, no run can cover it):
   `adorno-github/scripts/run-begin --workflow workflow:repo:onboard --mode auto --level L3 --repo owner/repo`, then
   `workflow:pr:ship owner/repo chore/agents-onboarding <clone>`: the repo's `commit_skill` commits the two files
   (`chore(agents): …`), its `pr_skill` opens the PR. Always `run-end <id>`, even after a failure. The repo's
   `max_level` below L3 or a denied `push` / `open_pr`: the files stay committed locally, and the report says so.
