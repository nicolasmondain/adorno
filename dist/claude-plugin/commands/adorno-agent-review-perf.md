---
description: agent:review:perf — Relecteur performance web d'un diff front — Core Web Vitals, poids du bundle, rendu, chargement des ressources, régressions mesurables. Appelé quand un diff touche le front et peut peser sur le chargement ou le rendu.
argument-hint: <demande>
---

Délègue la demande ci-dessous au sous-agent `adorno-agent-review-perf` (agent:review:perf) et rends son résultat tel quel. Si le sous-agent n'est pas disponible, adopte son rôle (skill ou fichier `adorno-agent-review-perf`) pour traiter la demande.

Demande : $ARGUMENTS
