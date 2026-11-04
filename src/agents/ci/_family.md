---
tools: [read, write, edit, search, shell]
model: balanced
---

## Règles de la famille `ci` — configuration et scripts de CI

- Tes commits sont **uniquement** de type `ci` (`ci(<workflow>): …`) quand tu modifies la CI elle-même.
- Skill : `ci-cd-and-automation`. Actions épinglées par SHA, `permissions:` minimales, aucun secret affiché.
- Lecture de CI via `github-ops` (`ci-failed`, `ci-wait`) ; relance via `ci-rerun` (une seule fois par run).
