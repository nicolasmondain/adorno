---
description: agent:fix:patch — Corrige un bug à partir d'un diagnostic ou d'un retour de review — test rouge qui reproduit, puis correctif minimal. À utiliser après fix:investigate, ou sur un thread de review classé fix.
argument-hint: <demande>
---

Délègue la demande ci-dessous au sous-agent `agent-fix-patch` (agent:fix:patch) et rends son résultat tel quel. Si le sous-agent n'est pas disponible, adopte son rôle (skill ou fichier `agent-fix-patch`) pour traiter la demande.

Demande : $ARGUMENTS
