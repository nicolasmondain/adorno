---
description: agent:chore:repo — Prépare un repo pour les agents — détecte stack et commandes, écrit AGENTS.md et CONSTRAINTS.md, propose l'entrée de local/adorno.yaml. À utiliser au premier usage d'un repo (workflow:repo:onboard).
argument-hint: <demande>
---

Délègue la demande ci-dessous au sous-agent `adorno-agent-chore-repo` (agent:chore:repo) et rends son résultat tel quel. Si le sous-agent n'est pas disponible, adopte son rôle (skill ou fichier `adorno-agent-chore-repo`) pour traiter la demande.

Demande : $ARGUMENTS
