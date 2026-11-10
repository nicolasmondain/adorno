# Instructions for agents working on this repo

adorno is a portable, reusable agent setup. Agents, workflows and skills are written in a neutral format;
`bin/kit` translates them for each tool (Claude Code, Codex, Gemini CLI…).

## Where to put what

| I want… | File |
| --- | --- |
| an instruction valid in all projects | `src/instructions/NN-topic.md` (concatenated in name order) |
| an agent | `src/agents/<type>/<specialty>.md` → `agent:<type>:<specialty>`; `<type>` = a Conventional Commit type, or `core`, `review`; outside a family: `src/agents/adorno.md` → `agent:adorno` |
| a rule shared by a family | `src/agents/<type>/_family.md` (merged before each specialty; `{{specialty}}` and `{{family}}` are replaced in it) |
| a workflow | `src/workflows/<domain>/<action>.md` → `workflow:<domain>:<action>`; `{{args}}` = the input |
| an on-demand know-how | `src/skills/<name>/SKILL.md` (+ `scripts/`, `references/`) |
| a diagram of an agent family, workflow domain or skill | `SCHEMA.md` in that folder (mermaid only; ignored by `bin/kit` as an item and not shipped to `dist/`) |
| a GitHub access | a script in `src/skills/adorno-github/scripts/` + its test in `tests/adorno-github.test.sh` |
| a Slack or Notion watch | a workflow `src/workflows/slack/…` or `src/workflows/notion/…`; the deterministic part in `src/skills/adorno-watch/scripts/` + `tests/adorno-watch.test.sh`; read through the connectors, only write: the report to oneself |
| an agent's or workflow's model | its `model:` tier (`fast`, `balanced`, `deep`, `frontier`) and, if needed, `effort:` (`low` … `max`), chosen by [docs/models.md](docs/models.md); `delegable: true` if it can judge on inputs gathered in advance (external route); the actual choice per tool and per repo is in `local/` › `models` |
| a repo, a workspace, permissions, a voice, a vision | `local/` (ignored by git; template: `local.example/`) — never in the repo |
| a default public setting | `repos.yaml` (+ its validation in `bin/kit` › `validate_registry`) |
| a settings resolution rule | `src/skills/adorno-github/scripts/resolve.jq` (shared by the scripts and `kit conf`) + its tests |
| content from another repo | `imports:` in `kit.yaml`, then `bin/kit import` |
| modifying an imported item | a local file with `extends: <import>/<name>` (never edit in `vendor/`) |

`bin/kit new agent perf:redis` (or `new workflow ci:flaky`, `new skill <name>`) creates a starter file.

## Rules

- **This repo is static, enriched by hand**: nothing is committed into it from another project, or by an agent. What
  concerns a real person or repo (identity, reviewers, team, context, permissions, voice, vision, profile) goes in
  `local/`, ignored by git; the public repo only has templates (`local.example/`). Only the `adorno-setup` skill and
  `workflow:profile:learn` write into `local/`, and only what the owner has validated.

- An agent of a family only produces commits of its type; `core` and `review` do not commit.
- The `description` says what the item does and when to use it: it is what gets it chosen.
- `tools`: neutral capabilities `read`, `write`, `edit`, `search`, `shell`, `web`, `agent`. `model`: `inherit`,
  `fast`, `balanced`, `deep`, `frontier`; `effort`: `low`, `medium`, `high`, `max`. A tool-specific setting goes under `targets: { claude: { … } }`.
- A workflow's `uses:`: logical identifiers (`agent:fix:patch`, `workflow:ci:red`, `adorno-github`), checked by
  `kit check`.
- Scripts: bash compatible with macOS 3.2, `set -euo pipefail`, JSON on stdout, exit codes from `adorno-github/SKILL.md`,
  GitHub writes only after `require_level`, `ADORNO_DRY_RUN` mode.
- Never modify `dist/` or `vendor/` by hand.

## After every change

```sh
bin/kit check && bin/kit build && for t in tests/*.test.sh; do $t || break; done
```

Commit `src/`, `dist/`, `vendor/`, `kit.yaml`, `kit.lock` and `repos.yaml` together: CI rejects a stale `dist/`.

## Branches and pull requests

`master` only changes through a pull request, squash-merged by the owner (a ruleset enforces it, without bypass).

1. A branch `<type>/kebab-description` from `master` (`<type>` = a Conventional Commit type, no issue id).
2. Commits in Conventional Commits format (`adorno-commit` skill), then the checks above.
3. `/adorno-pr-open`: review gate, push, PR. The PR title is a Conventional Commit header, e.g.
   `feat(agents): add perf:redis`: the squash merge makes it the commit on `master` (checked by the `pr` workflow).
4. CI green (`check`, `macos-bash-3-2`, `pr-title`), conversations resolved; `/adorno-pr-watch` if needed.
5. The owner squash-merges; the branch is deleted. A child PR in a stack is retargeted to `master`: rebase it with
   `git rebase --onto master <old parent tip>`.
