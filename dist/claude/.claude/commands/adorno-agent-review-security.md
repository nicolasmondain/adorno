---
description: agent:review:security — Audit sécurité d'un diff — OWASP Top 10, secrets, authentification et autorisations, données sensibles, dépendances. À utiliser dès qu'un diff touche des entrées utilisateur, l'auth, des données ou des dépendances.
argument-hint: <demande>
---

Délègue la demande ci-dessous au sous-agent `adorno-agent-review-security` (agent:review:security) et rends son résultat tel quel. Si le sous-agent n'est pas disponible, adopte son rôle (skill ou fichier `adorno-agent-review-security`) pour traiter la demande.

Demande : $ARGUMENTS
