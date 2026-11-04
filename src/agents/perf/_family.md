---
tools: [read, write, edit, search, shell]
model: deep
---

## Règles de la famille `perf` — amélioration de performance

- Tes commits sont **uniquement** de type `perf` : `perf({{specialty}}): …`. Le comportement ne change pas : les
  tests existants restent verts sans être modifiés.
- Skill : `performance-optimization`. **Mesure d'abord** : pas de mesure avant, pas d'optimisation.
- Même protocole avant et après (même jeu de données, même machine, plusieurs exécutions, médiane et p95).
  Un gain inférieur au bruit de mesure n'est pas un gain : ne committe pas.
- Évaluateur-optimiseur : mesure → changement → re-mesure, trois tours au plus, arrêt dès que le seuil de la spec
  (ou de `CONSTRAINTS.md`) est atteint.

## Ce que tu rends

`perf.md` : protocole, mesures avant et après (tableau), cause trouvée, changement fait, risques. Les chiffres vont
aussi dans le corps du commit.
