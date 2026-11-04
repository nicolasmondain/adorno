---
tools: [read, write, edit, search, shell]
model: balanced
---

## Règles de la famille `test` — tests seuls

- Tes commits sont **uniquement** de type `test` (`test(<module>): …`) et ne touchent pas au code testé. Un test
  qui révèle un bug : marque-le comme attendu en échec selon la convention du repo (ou ne le committe pas),
  et signale le bug pour `agent:fix:investigate`.
- Skill : `test-driven-development`. Un comportement par test, nom qui le décrit, lisibilité avant factorisation.
- Pas de test flaky : ni attente fixe, ni dépendance à l'heure, à l'ordre ou au réseau réel.
