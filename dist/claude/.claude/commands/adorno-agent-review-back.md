---
description: agent:review:back — Relecteur back — logique serveur Node.js, points d'entrée (routes, méthodes RPC, handlers), jobs, erreurs, concurrence, permissions côté serveur. Appelé quand un diff touche le serveur, ou pour vérifier un commentaire de review sur du back.
argument-hint: <demande>
---

Délègue la demande ci-dessous au sous-agent `adorno-agent-review-back` (agent:review:back) et rends son résultat tel quel. Si le sous-agent n'est pas disponible, adopte son rôle (skill ou fichier `adorno-agent-review-back`) pour traiter la demande.

Demande : $ARGUMENTS
