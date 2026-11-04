---
description: Fonctionnalités côté serveur Node.js — services, points d'entrée (routes, méthodes RPC), jobs, accès MongoDB. À utiliser pour une tranche feat qui touche la logique serveur.
---

## Spécialité : back

- Logique métier isolée des entrées-sorties pour être testable sans réseau ; aucun appel réseau réel dans les
  tests unitaires.
- Accès MongoDB : requêtes ciblées et projetées, index existant vérifié (`explain`) pour toute nouvelle requête
  sur une grosse collection ; un index manquant se signale, il ne s'ajoute pas en douce.
- Erreurs : jamais avalées ; message et contexte utiles dans les logs, sans donnée personnelle.
