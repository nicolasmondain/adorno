---
name: adorno-setup
description: Set up adorno for its owner — mode `profile` builds a fine-grained profile from a corpus of your own writing (GitHub reviews and diffs, Slack messages, Notion pages, any files you point to) and writes who you are, how you work on tech, product and code, how you write and your vision into your personal layer (local/, git-ignored); mode `repo` declares the current repo (or a whole workspace) with its reviewers, team, context, permissions and voice. Use on first use of adorno, when an agent reports that the profile or the voice is not set up, when a repo is "not registered", or when the owner asks to change their profile, voice, vision or a repo's settings.
---

# Set up adorno

Everything this skill writes goes to the owner's **personal layer** (`local/` of the adorno repo, git-ignored): never
to a tracked file of the adorno repo, never to the current project. Nothing is written before the owner has read and
validated it. Ask **one question at a time**, propose a default each time, and move on when they say "skip".

Locate the layer first: `scripts/adorno-source` → `source` (the adorno repo), `local` (the layer), `localExists`.
`localExists: false` → offer `cp -r <source>/local.example <local>` and continue once they agree.

Mode from the request: `profile`, `repo`, or both (`profile` first). Unclear → ask.

## Mode `profile`

Goal: `agent:adorno` decides and writes like the owner. The templates of `local.example/` show the expected shape;
the owner's real words beat any template.

1. **Identity** → `local/adorno.yaml` › `owner`: `name`, GitHub login (`gh api user --jq .login`), `language` of the
   exchanges with the agents.
2. **Corpus** — the finer the sources, the finer the profile. Offer each source, take only those the owner agrees
   to, and keep **only their own words** (other people's messages serve as context, never stored or quoted):
   - **GitHub** — `scripts/voice-samples 30`: their review comments, review summaries and PR descriptions; plus the
     diffs of 5-10 of their merged PRs (`gh pr list --author @me --state merged`) for how they actually write code.
   - **Slack** — through the Slack connector: their own messages over the last 90 days (search `from:<@their id>`),
     300 at most, in the channels they name or all; threads where they decided or explained something first.
   - **Notion** — pages they wrote (specs, ADRs, post-mortems) through the Notion connector.
   - **Files** — anything they point to: notes, docs, exported conversations, a folder of past write-ups.
   Work in the run folder (`~/.adorno/runs/adorno-setup-<date>/`); nothing from the corpus is kept after the run,
   only what goes into the profile.
3. **Analyse** — per dimension, with evidence: **tech** (architecture, scale, tooling), **code** (types, naming,
   structure, tests, what they always ask to change), **product** (priorities, scope, user impact, ship vs polish),
   **process** (method, PR and review discipline), **communication** (feedback, conflict, how they address people),
   **voice** per channel (length, tone, recurring phrases, badges, what they never do). A trait needs at least two
   samples; quote short excerpts (no names of third parties) with their links; show contradictions instead of
   smoothing them. Present it as a table per dimension: trait, evidence, confidence.
   Then the files, each section confronted with the analysis, the owner correcting what doesn't sound like them:
   `local/src/skills/adorno-profile/references/{personality,engineering-types,engineering-scale,product,process}.md`,
   `local/src/skills/adorno-voice/references/voice.md`, and the voice knobs (`defaults.voice`).
4. **Summary** — 15-30 lines always loaded, distilled from step 3 (hard limits included).
   → `local/src/instructions/20-owner.md`.
5. **Vision** — the few principles that must win over every agent (60 lines at most, usually 3-10).
   → `local/vision.md`; repo-specific lines go to that repo's `vision:` instead.
6. **Show, then write** — show each file in full (or the diff when it exists), write it once validated.
7. **Apply** — `<source>/bin/kit check`, then offer `<source>/bin/kit install --global` (or the project path they use).

## Mode `repo`

Goal: the workflows know this repo — or a whole set of repos — and act within the rights the owner gives them.

1. **Which repo** — the current directory's GitHub `origin` (or the `owner/repo` given). `<source>/bin/kit conf
   owner/repo`: already declared → show what it resolves to (`scopes` says where each value comes from) and ask what
   to change.
2. **One repo or a workspace?** — if sibling repos share the team and the rules (same GitHub owner, same parent
   folder), propose a `workspaces:` entry (`repos: ["owner/*"]` and/or `paths: ["~/code/<folder>"]`) with the shared
   settings in a `presets:` block, and keep only what differs under `repos:`.
3. **Detect, then ask** — from the repo, not from memory:
   - commands `test`, `lint`, `typecheck` (package scripts, Makefile, CI workflow), `base` (default branch);
   - default `reviewers`: who reviewed the last PRs (`gh pr list --state merged --limit 20 --json reviews`), never the
     owner; `team` (name, GitHub team, Slack channels) by asking;
   - `context`: 3-8 one-line facts every agent must know (priorities, conventions, coverage bar, module layout), from
     the repo's `CLAUDE.md`, `.claude/rules/` and the owner's answers — never copy a whole rule file;
   - `pr_skill` / `setup_skill` if the repo has its own skills.
4. **Rights** — ask, with the safe default first:
   - `max_level` (L0 read … L3 open PRs, reply, resolve; L4 is never automatic) — default `L3`, `L2` on a sensitive repo;
   - `permissions.deny`: GitHub actions to refuse there (`push`, `reply`, `comment`, `resolve`, `rerequest`, `review`,
     `submit`, `open_pr`, `ci_rerun`);
   - `permissions.claude` (`allow`, `ask`, `deny`): native Claude Code rules for that repo, e.g. allow its test and lint
     commands, deny `Bash(git push:*)`.
5. **Voice and vision for this repo** — only what differs (`voice: {formality: formal}` on public docs, a `vision`
   line…).
6. **Show, then write** — the YAML block to add to `local/adorno.yaml`, merged by hand into the existing file
   (keep its comments and order); write it once validated.
7. **Apply** — `<source>/bin/kit check`, `<source>/bin/kit conf owner/repo` to show the result, then offer
   `<source>/bin/kit install <repo path>` (or `--workspace <name>`) so the native permissions land in the repo.
   Preparing the repo itself (`AGENTS.md`, `CONSTRAINTS.md`, verified commands) is `workflow:repo:onboard`.

## Afterwards

The profile keeps learning: the `adorno-learn` skill records what the owner's corrections and choices reveal, and
`workflow:profile:learn` (`/adorno-profile-learn`) proposes the updates. Running this mode again on a fresh corpus
is the deep refresh.

## Rules

- Personal data (names, logins, teammates, internal URLs, Slack channels, real samples) goes **only** to `local/`.
- Never invent a sample, a reviewer, a command or a rule: detected, or asked, or left out.
- A text about a person follows the SBI charter (`adorno-profile` › `personality.md`).
