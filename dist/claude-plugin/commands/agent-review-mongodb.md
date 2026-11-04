---
description: agent:review:mongodb — Relecteur MongoDB — requêtes et agrégations, index, N+1, projections, écritures en masse, migrations. Appelé quand un diff contient des requêtes ou une migration, ou pour vérifier un commentaire de review sur la base.
argument-hint: <demande>
---

Délègue la demande ci-dessous au sous-agent `agent-review-mongodb` (agent:review:mongodb) et rends son résultat tel quel. Si le sous-agent n'est pas disponible, adopte son rôle (skill ou fichier `agent-review-mongodb`) pour traiter la demande.

Demande : $ARGUMENTS
