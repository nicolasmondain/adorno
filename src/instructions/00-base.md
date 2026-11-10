# Working instructions

## Communication

- Talk to the user in their language (`owner.language` in `local/adorno.yaml`, read by `repo-conf`). Code, code comments,
  commit messages, PR descriptions and texts published on GitHub are in English (the repo's `reply_language`). Any text
  published in their name goes through the `adorno-voice` skill.
- Get to the point: what changed, what was verified, what is still open, what waits for a decision.

## Before changing anything

- Read the repo's `CLAUDE.md` and `.claude/rules/` first: they are authoritative on the code (except
  `.claude/rules/adorno.md`, which is this text, placed by `bin/kit` when the repo already follows its own `CLAUDE.md`).
- Then the profile (`adorno-profile` skill) and the current repo's settings: `adorno-github/scripts/repo-conf` (team,
  reviewers, `context`, `vision`, `voice`, `permissions`, the repo's skills), taken from `local/adorno.yaml`.
- The owner corrects you, decides differently from what their profile expected, rewrites your draft or says how they
  want it done: note it with the `adorno-learn` skill (with the evidence), without interrupting the task.
- Profile missing (`adorno-profile` skill without `references/`) or repo not declared (`repo-conf` exits 3): say so once
  and offer the `adorno-setup` skill (mode `profile` or `repo`).
- Vague task, or costly to undo: `workflow:spec:new` before writing code.

## During

- Minimal, surgical changes (`ponytail` skill, at the repo's `ponytail` level, `full` by default); where it overlaps
  the profile, the profile wins, and the repo wins over both.
- No secret (key, token, password) in a file, a command, a log, a commit or a published text.
- Shell commands the permission rules can read: the program written literally (`node /abs/path/cdp.mjs 58624 open …`),
  never a variable or alias as program (`C="node …"; $C …`), no `eval`; one action per call rather than a chain of
  `$( … )` captures, reusing a printed value (port, target id, path) as a literal in the next call. A command the guard
  or the allow rules cannot read stops on a permission prompt, and nobody answers it in a scheduled run.

## Git

- Branch `<type>/<issue-id>-kebab-description` (`<type>` = Conventional Commit type), never a commit on the default
  branch, never `--no-verify`.
- Commits in Conventional Commits format (`adorno-commit` skill), numbered in a stack. An `agent:<type>:*` agent only
  produces commits of its type.
- Never a merge, a tag, a push to the default branch or a force push without explicit agreement
  (`--force-with-lease` only, and only if they ask for it).
