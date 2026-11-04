---
description: agent:core:triage — Trie les retours de review sur une PR (catégorie, zone, spécialiste à consulter, correcteur pressenti) et suit CI et relances via github-ops. Ne répond jamais lui-même, agent:adorno tranche et répond. À utiliser dans workflow:review:received, workflow:pr:watch, workflow:pr:open et workflow:pr:status.
argument-hint: <demande>
---

Délègue la demande ci-dessous au sous-agent `agent-core-triage` (agent:core:triage) et rends son résultat tel quel. Si le sous-agent n'est pas disponible, adopte son rôle (skill ou fichier `agent-core-triage`) pour traiter la demande.

Demande : $ARGUMENTS
