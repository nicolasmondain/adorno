---
name: adorno-learn
description: Garde le profil et la voix du propriétaire en phase avec ses vraies décisions — pendant toute tâche, repère ce qui révèle son jugement en tech, logique produit, logique code, méthode ou écriture (une correction, un verdict renversé, un brouillon réécrit, une préférence dite, un choix répété), le note avec sa preuve et propose une mise à jour du profil quand c'est solide. À utiliser chaque fois que le propriétaire te corrige ou tranche autrement, réécrit un brouillon avant de l'envoyer, dit comment il veut les choses, ou à la fin d'un workflow mené par agent:adorno ; workflow:profile:learn applique ce qu'il valide.
---

# adorno-learn

The profile (`adorno-profile`, `adorno-voice`, the summary `20-owner.md`) only stays true if it learns. This skill
records **candidates** while you work, and proposes them to the owner when they are solid. It never edits the
profile: `workflow:profile:learn` does, after the owner validates each change.

## What is a signal

| Kind | Typical signal | Goes to |
| --- | --- | --- |
| `tech` | architecture, performance, scale or tooling choice the owner makes or insists on | `engineering-scale.md` |
| `code` | how code should be written: types, naming, structure, tests, what they always ask to change | `engineering-types.md` |
| `product` | priority, scope cut, user-impact argument, ship-vs-polish call | `product.md` |
| `process` | method, PR and review discipline, what they check before deciding | `process.md` |
| `voice` | a draft they rewrote: what they cut, added, softened, reworded | `voice.md` (`adorno-voice`) |
| `personality` | how they address people, give feedback, handle conflict | `personality.md` |

Strong signals: the owner **says** it ("always…", "never…", "I prefer…") → `--strength explicit`; the owner
**overrides** a verdict of `agent:adorno`; the owner **edits** a draft before sending it (compare draft and sent
version). Weak signals: a choice repeated across tasks → `inferred`, proposed only when seen twice.

Not a signal: a one-off constraint of a single task, a repo's own rule (that is `context` or the repo's
`.claude/rules/`, not the owner's profile), anything about a third person.

## Record

```sh
scripts/learn-note --key prefer-batch-reads --kind tech --target engineering-scale.md#design-for-the-volume \
  --observation "Asked to batch the user lookups instead of one query per row, on two PRs" \
  --proposal "Reads in a loop are always batched (one query, then a map); flag any per-row query as 🟠." \
  --evidence https://github.com/acme/app/pull/481#discussion_r1 --strength inferred
```

- `--key`: a short slug naming the principle, reused when the same principle shows up again (check
  `scripts/learn-list --all` first).
- `--proposal`: the sentence as it would read in the profile — in the profile's language, generic, no names of
  people, customers or internal systems that do not belong there.
- `--evidence`: a link or `file:line` for each occurrence. No evidence, no candidate.

State: `~/.adorno/learn/candidates.json` (outside every repo).

## Propose

At the end of a run (the last step of `agent:adorno`), `scripts/learn-list --ready`: anything ready gets **one line**
in the report — "Profile: 2 points ready to validate (`/adorno-profile-learn`)". Never interrupt a task for it.

| Script | Does |
| --- | --- |
| `learn-note …` | record or reinforce a candidate |
| `learn-list [--ready\|--all]` | pending candidates, most supported first; `--ready` = explicit or seen twice |
| `learn-decide KEY accepted\|rejected\|later` | the owner's decision; a rejected key stays rejected |
