---
description: Evolve your profile and your voice — reviews the points noted by adorno-learn during work (tech, product logic, code logic, method, writing), shows you each with its evidence and the proposed sentence in the right file, and writes only what you validate, in your personal layer. Launched by hand when Adorno signals ready points.
argument-hint: '[--all] [--kind tech|product|code|process|voice|personality]'
model: opus
---

Input: $ARGUMENTS

1. **List** — `adorno-learn/scripts/learn-list --ready` (`--all`: every pending point, including those seen only
   once; `--kind` filters). Nothing → say so, end.
2. **Locate** — `adorno-setup/scripts/adorno-source` → the personal layer. For each point, read the targeted file
   (`local/src/skills/adorno-profile/references/<file>`, `…/adorno-voice/references/voice.md` or
   `local/src/instructions/20-owner.md`): is the principle already there, partly, or contradicted?
3. **Propose**, one point at a time:
   - what was observed, how many times, with the links;
   - the exact change: the sentence added or replaced, in which section (a diff; for `voice` and `personality`,
     in the use case or the situation the `adorno-learn` table names); a contradiction with the current profile is
     shown as such, with both versions;
   - the choice: **accept**, **rephrase** (you dictate, the new diff is shown), **later**, **reject**.
4. **Write** what is accepted, in the personal layer file only (never in a tracked file of the adorno repo), then
   `learn-decide <key> accepted`; `rejected` or `later` otherwise. A principle that changes how you work day to day
   also goes up, in one line, into `20-owner.md` if you want.
5. **Apply** — `<source>/bin/kit check`, then `<source>/bin/kit install --global` (and the repos installed
   separately, if any). Report: what changed, file by file.
