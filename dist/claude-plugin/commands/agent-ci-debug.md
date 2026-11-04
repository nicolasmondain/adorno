---
description: agent:ci:debug — Diagnostique une CI rouge à partir des logs — classe l'échec (flaky, infra, vrai échec) et désigne l'agent qui doit corriger. À utiliser dès qu'un check échoue sur une PR ou sur la branche par défaut.
argument-hint: <demande>
---

Délègue la demande ci-dessous au sous-agent `agent-ci-debug` (agent:ci:debug) et rends son résultat tel quel. Si le sous-agent n'est pas disponible, adopte son rôle (skill ou fichier `agent-ci-debug`) pour traiter la demande.

Demande : $ARGUMENTS
