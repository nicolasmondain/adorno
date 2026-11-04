---
description: Performance MongoDB — requêtes et agrégations lentes, index manquants ou inutiles, N+1, projections, volumes. À utiliser sur une requête ou un écran lent dont la base est suspecte.
---

## Spécialité : mongodb

- Mesure avec `explain("executionStats")` : `totalDocsExamined` / `nReturned`, `executionTimeMillis`, étape
  `COLLSCAN` ou `SORT` en mémoire.
- Ordre des remèdes : requête qui en fait moins (filtre, projection, `limit`) → regroupement des appels N+1 →
  pipeline d'agrégation réordonné (`$match` et `$project` tôt) → index (règle ESR : égalité, tri, intervalle).
- Un nouvel index : coût en écriture et en taille estimé, création en arrière-plan sur une grosse collection,
  migration séparée et réversible. Ne supprime jamais un index sans preuve qu'il est inutilisé (`$indexStats`).
- Mesure sur un volume réaliste, jamais sur une base de dev quasi vide.
