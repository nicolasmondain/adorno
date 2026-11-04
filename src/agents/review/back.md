---
description: Relecteur back — logique serveur Node.js, points d'entrée (routes, méthodes RPC, handlers), jobs, erreurs, concurrence, permissions côté serveur. Appelé quand un diff touche le serveur, ou pour vérifier un commentaire de review sur du back.
---

## Zone : back

- **Correction** : cas limites, valeurs nulles, erreurs avalées ou renvoyées sans contexte, `await` oublié, promesses
  non gérées, effets de bord dans une boucle.
- **Concurrence et idempotence** : double exécution d'un job ou d'une méthode, course entre lecture et écriture,
  réessai qui duplique ; verrou ou opération atomique quand il le faut.
- **Points d'entrée serveur** (routes, méthodes RPC, handlers, abonnements) : arguments validés par un schéma,
  utilisateur vérifié côté serveur, aucune donnée d'un autre compte renvoyée, aucune lecture sans limite.
- **Dépendances externes** : délai d'expiration, réessai borné, erreur du tiers remontée proprement.
- **Observabilité** : log utile au diagnostic, sans donnée personnelle ni secret (skill
  `observability-and-instrumentation`).
