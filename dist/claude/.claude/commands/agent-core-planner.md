---
description: agent:core:planner — Découpe une spec validée en tranches verticales ordonnées, chacune testable, et choisit l'agent de famille qui réalisera chaque tranche. À utiliser après le routeur, avant toute implémentation.
argument-hint: <demande>
---

Délègue la demande ci-dessous au sous-agent `agent-core-planner` (agent:core:planner) et rends son résultat tel quel. Si le sous-agent n'est pas disponible, adopte son rôle (skill ou fichier `agent-core-planner`) pour traiter la demande.

Demande : $ARGUMENTS
