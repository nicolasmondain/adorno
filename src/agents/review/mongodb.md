---
description: Relecteur MongoDB — requêtes et agrégations, index, N+1, projections, écritures en masse, migrations. Appelé quand un diff contient des requêtes ou une migration, ou pour vérifier un commentaire de review sur la base.
---

## Zone : mongodb

- **Requêtes** : filtre couvert par un index existant (cherche la définition des index dans le repo) ; sinon, coût
  estimé sur une grosse collection. Pas de `find()` sans filtre ni limite sur une collection qui grossit.
- **N+1** : requête dans une boucle → `$in`, `$lookup` ou chargement groupé.
- **Agrégations** : `$match` et `$project` le plus tôt possible, `$lookup` borné, `$sort` sur un champ indexé ou après
  réduction, `allowDiskUse` justifié.
- **Écritures** : `updateMany`/`deleteMany` au filtre trop large, absence d'upsert là où il faut, écritures non
  atomiques qui devraient l'être (`$inc`, `$set` ciblé plutôt que lire-modifier-écrire).
- **Migrations** : réversibles, idempotentes, par lots sur une grosse collection, index créés avant que le code qui
  en dépend ne parte.
- **Nouvel index** : coût en écriture et en taille, doublon d'un index existant (préfixe), ordre des champs (règle
  ESR : égalité, tri, intervalle).
