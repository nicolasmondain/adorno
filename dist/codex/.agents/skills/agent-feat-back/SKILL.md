---
name: agent-feat-back
description: Rôle agent:feat:back — Fonctionnalités côté serveur Node.js — services, points d'entrée (routes, méthodes RPC), jobs, accès MongoDB. À utiliser pour une tranche feat qui touche la logique serveur.
---

# Rôle : agent:feat:back

Quand ce skill est invoqué, adopte le rôle ci-dessous pour la tâche en cours, puis reviens à ton comportement normal une fois le résultat rendu.

## Règles de la famille `feat` — nouvelle fonctionnalité

- Tes commits sont **uniquement** de type `feat` : `feat(back): …` ou `feat(<module>): …`. Un changement
  qui n'ajoute pas de comportement visible relève d'une autre famille : signale-le au lieu de le committer.
- Tu travailles une tranche de `plan.md` à la fois, sur la branche `<type>/<issue-id>-<slug>` (L2 : commit et push de branche,
  jamais de PR toi-même).
- Boucle par tranche (skills `incremental-implementation`, `test-driven-development`) : test d'acceptation qui
  échoue → code minimal (skill `ponytail`) → tests, lint, typecheck verts → commit. Trois tours au plus, puis
  arrêt et compte rendu.
- API, lib ou service tiers que tu n'as pas déjà vu dans le repo : vérifie dans la doc officielle avant de coder
  (skill `source-driven-development`).

## Ce que tu rends

Une ligne par commit dans `slices.log` (`<sha> <tranche> <tests: ok|ko>`), puis : ce qui marche, comment tu l'as
vérifié, ce que tu as sauté et pourquoi.
- Code TypeScript : skill `typescript-pro` (types avancés, garde-fous de type, `tsconfig` strict). Le profil et les
  règles du repo priment sur ses choix (ni tRPC ni dépendance qu'il suggère sans accord).

## Spécialité : back

- Logique métier isolée des entrées-sorties pour être testable sans réseau ; aucun appel réseau réel dans les
  tests unitaires.
- Accès MongoDB : requêtes ciblées et projetées, index existant vérifié (`explain`) pour toute nouvelle requête
  sur une grosse collection ; un index manquant se signale, il ne s'ajoute pas en douce.
- Erreurs : jamais avalées ; message et contexte utiles dans les logs, sans donnée personnelle.
